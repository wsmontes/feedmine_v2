// Owns durable target validity and opaque resumption mechanics in one writer transaction.
import Foundation
import GRDB
import FeedMineDomain

public enum AcquisitionTargetStoreError: Error, Equatable, Sendable {
    case sourceConfigurationConflict(AcquisitionTargetID)
    case connectorKindMismatch(AcquisitionTargetID)
    case invalidRepresentation(String)
    case corruption(String)
    case targetAlreadyExists(AcquisitionTargetID)
    case missingTarget(AcquisitionTargetID)
    case staleGeneration(expected: UInt64, actual: UInt64)
    case staleCheckpoint(expected: UInt64, actual: UInt64)
    case targetRevoked(AcquisitionTargetID)
    case generationExhausted(AcquisitionTargetID)
    case checkpointRevisionExhausted(AcquisitionTargetID)
}

public struct AcquisitionTargetStore: Sendable {
    public struct CheckpointRecord: Hashable, Sendable {
        public let blob: Data
        public let serializationSchema: UInt64
        public let connectorVersion: String
        public init?(blob: Data, serializationSchema: UInt64, connectorVersion: String) {
            guard serializationSchema > 0, !connectorVersion.utf8.isEmpty else { return nil }
            self.blob = blob
            self.serializationSchema = serializationSchema
            self.connectorVersion = connectorVersion
        }
    }

    public struct TargetRecord: Hashable, Sendable {
        public let id: AcquisitionTargetID
        public let connectorKind: ConnectorKind
        public let generation: UInt64
        public let state: String
        public let checkpointRevision: UInt64
        public let checkpoint: CheckpointRecord?
    }

    public enum ReconfigurationCheckpoint: Hashable, Sendable {
        case preserve
        case clear
        case replace(CheckpointRecord)
    }

    private let database: RuntimeDatabase
    public init(database: RuntimeDatabase) { self.database = database }

    public func register(id: AcquisitionTargetID, connectorKind: ConnectorKind, authorizedSources: Set<SourceID>) throws -> TargetRecord {
        guard !connectorKind.rawValue.utf8.isEmpty else { throw AcquisitionTargetStoreError.invalidRepresentation("connector_kind") }
        try Self.validateSources(authorizedSources)
        return try database.write { db in
            guard try Self.readTarget(id: id,in: db) == nil else { throw AcquisitionTargetStoreError.targetAlreadyExists(id) }
            try db.execute(sql: """
                INSERT INTO acquisition_targets (id, connector_kind, generation, state, checkpoint_revision)
                VALUES (?, ?, 1, 'enabled', 0)
                """,arguments: [PersistenceValueCoding.uuid(id.rawValue),connectorKind.rawValue])
            try Self.replaceSources(authorizedSources, id: id, generation: 1, in: db)
            return try Self.requireTarget(id: id,in: db)
        }
    }

    public func target(id: AcquisitionTargetID) throws -> TargetRecord? {
        try database.read { try Self.readTarget(id: id,in: $0) }
    }

    public func reconfigure(id: AcquisitionTargetID, expectedGeneration: UInt64,
        connectorKind: ConnectorKind, checkpoint: ReconfigurationCheckpoint, authorizedSources: Set<SourceID>) throws -> TargetRecord {
        guard !connectorKind.rawValue.utf8.isEmpty else { throw AcquisitionTargetStoreError.invalidRepresentation("connector_kind") }
        try Self.validateSources(authorizedSources)
        return try database.write { db in
            let old = try Self.requireTarget(id: id,in: db)
            try Self.validateGeneration(old,expected: expectedGeneration)
            _ = try Self.readSources(old, in: db)
            let generation = try Self.nextGeneration(old)
            let next: CheckpointRecord?
            switch checkpoint {
            case .preserve: next = old.checkpoint
            case .clear: next = nil
            case .replace(let value): next = value
            }
            let revision = Self.sameCheckpoint(old.checkpoint,next) ? old.checkpointRevision : try Self.nextCheckpointRevision(old)
            let updated = TargetRecord(id: id,connectorKind: connectorKind,generation: generation,
                state: old.state,checkpointRevision: revision,checkpoint: next)
            try Self.update(updated,in: db)
            try Self.replaceSources(authorizedSources, id: id, generation: generation, in: db)
            return updated
        }
    }

    public func revoke(id: AcquisitionTargetID, expectedGeneration: UInt64) throws -> TargetRecord {
        try setState("revoked",id: id,expectedGeneration: expectedGeneration)
    }

    public func enable(id: AcquisitionTargetID, expectedGeneration: UInt64) throws -> TargetRecord {
        try setState("enabled",id: id,expectedGeneration: expectedGeneration)
    }

    private func setState(_ state: String, id: AcquisitionTargetID, expectedGeneration: UInt64) throws -> TargetRecord {
        try database.write { db in
            let old = try Self.requireTarget(id: id,in: db)
            try Self.validateGeneration(old,expected: expectedGeneration)
            let sources = try Self.readSources(old, in: db)
            guard old.state != state else { return old }
            let updated = TargetRecord(id: id,connectorKind: old.connectorKind,generation: try Self.nextGeneration(old),
                state: state,checkpointRevision: old.checkpointRevision,checkpoint: old.checkpoint)
            try Self.update(updated,in: db)
            if let sources { try Self.replaceSources(sources, id: id, generation: updated.generation, in: db) }
            return updated
        }
    }

    public func compareAndSwapCheckpoint(id: AcquisitionTargetID, expectedGeneration: UInt64,
        expectedCheckpointRevision: UInt64, next: CheckpointRecord) throws -> TargetRecord {
        try database.write { db in
            let old = try Self.requireTarget(id: id,in: db)
            try Self.validateEnabledStamp(old,expectedGeneration: expectedGeneration,
                expectedCheckpointRevision: expectedCheckpointRevision)
            return try Self.applyCheckpoint(next,to: old,in: db)
        }
    }

    /// Nil denotes an unreconciled legacy target. New registration and reconfiguration require nonempty grants.
    public func authorizedSources(id: AcquisitionTargetID) throws -> Set<SourceID>? {
        try database.read { db in try Self.readSources(Self.requireTarget(id: id, in: db), in: db) }
    }

    public func materializeSources(id: AcquisitionTargetID, expectedGeneration: UInt64,
        connectorKind: ConnectorKind, authorizedSources: Set<SourceID>) throws -> TargetRecord {
        try Self.validateSources(authorizedSources)
        return try database.write { db in
            let target = try Self.requireTarget(id: id, in: db)
            try Self.validateGeneration(target, expected: expectedGeneration)
            guard target.connectorKind.rawValue.utf8.elementsEqual(connectorKind.rawValue.utf8) else {
                throw AcquisitionTargetStoreError.connectorKindMismatch(id)
            }
            if let current = try Self.readSources(target, in: db) {
                guard current == authorizedSources else { throw AcquisitionTargetStoreError.sourceConfigurationConflict(id) }
            } else {
                guard target.state == "enabled" else { throw AcquisitionTargetStoreError.targetRevoked(id) }
                try Self.replaceSources(authorizedSources, id: id, generation: target.generation, in: db)
            }
            return target
        }
    }

    private static func validateSources(_ sources: Set<SourceID>) throws {
        guard !sources.isEmpty else { throw AcquisitionTargetStoreError.invalidRepresentation("authorizedSources") }
    }

    static func readSources(_ target: TargetRecord, in db: Database) throws -> Set<SourceID>? {
        let rows = try Row.fetchAll(db, sql: "SELECT source_id, generation FROM acquisition_target_sources WHERE target_id = ?",
            arguments: [PersistenceValueCoding.uuid(target.id.rawValue)])
        if rows.isEmpty { return nil }
        var sources = Set<SourceID>()
        for row in rows {
            let generation: DatabaseValue = row["generation"]
            let source: DatabaseValue = row["source_id"]
            guard case .int64(let number) = generation.storage, number > 0, UInt64(number) == target.generation,
                case .string(let text) = source.storage, let uuid = UUID(uuidString: text),
                PersistenceValueCoding.uuid(uuid) == text else { throw AcquisitionTargetStoreError.corruption("target source authority") }
            sources.insert(SourceID(rawValue: uuid))
        }
        return sources
    }

    private static func replaceSources(_ sources: Set<SourceID>, id: AcquisitionTargetID,
        generation: UInt64, in db: Database) throws {
        let key = PersistenceValueCoding.uuid(id.rawValue)
        try db.execute(sql: "DELETE FROM acquisition_target_sources WHERE target_id = ?", arguments: [key])
        for source in sources {
            try db.execute(sql: "INSERT INTO acquisition_target_sources (target_id, source_id, generation) VALUES (?, ?, ?)",
                arguments: [key, PersistenceValueCoding.uuid(source.rawValue), try encoded(generation, field: "generation")])
        }
    }

    // Internal primitives can participate in a future wider Persistence-owned transaction.
    static func validateEnabledStamp(_ record: TargetRecord, expectedGeneration: UInt64,
        expectedCheckpointRevision: UInt64) throws {
        guard record.state == "enabled" else { throw AcquisitionTargetStoreError.targetRevoked(record.id) }
        try validateGeneration(record,expected: expectedGeneration)
        guard record.checkpointRevision == expectedCheckpointRevision else {
            throw AcquisitionTargetStoreError.staleCheckpoint(expected: expectedCheckpointRevision,actual: record.checkpointRevision)
        }
    }

    static func applyCheckpoint(_ next: CheckpointRecord, to old: TargetRecord, in db: Database) throws -> TargetRecord {
        let updated = TargetRecord(id: old.id,connectorKind: old.connectorKind,generation: old.generation,
            state: old.state,checkpointRevision: try nextCheckpointRevision(old),checkpoint: next)
        try update(updated,in: db)
        return updated
    }

    private static func validateGeneration(_ record: TargetRecord, expected: UInt64) throws {
        guard record.generation == expected else {
            throw AcquisitionTargetStoreError.staleGeneration(expected: expected,actual: record.generation)
        }
    }

    private static func nextGeneration(_ record: TargetRecord) throws -> UInt64 {
        guard record.generation < UInt64(Int64.max) else { throw AcquisitionTargetStoreError.generationExhausted(record.id) }
        return record.generation + 1
    }

    private static func nextCheckpointRevision(_ record: TargetRecord) throws -> UInt64 {
        guard record.checkpointRevision < UInt64(Int64.max) else { throw AcquisitionTargetStoreError.checkpointRevisionExhausted(record.id) }
        return record.checkpointRevision + 1
    }

    private static func sameCheckpoint(_ a: CheckpointRecord?, _ b: CheckpointRecord?) -> Bool {
        switch (a,b) {
        case (nil,nil): return true
        case (.some(let a),.some(let b)):
            return a.blob == b.blob && a.serializationSchema == b.serializationSchema
                && a.connectorVersion.utf8.elementsEqual(b.connectorVersion.utf8)
        default: return false
        }
    }

    private static func encoded(_ value: UInt64, field: String) throws -> Int64 {
        guard let result = Int64(exactly: value) else { throw AcquisitionTargetStoreError.invalidRepresentation(field) }
        return result
    }

    private static func update(_ record: TargetRecord, in db: Database) throws {
        let schema = try record.checkpoint.map { try encoded($0.serializationSchema,field: "checkpoint_schema") }
        let generation = try encoded(record.generation,field: "generation")
        let revision = try encoded(record.checkpointRevision,field: "checkpoint_revision")
        try db.execute(sql: """
            UPDATE acquisition_targets SET connector_kind=?, generation=?, state=?, checkpoint_revision=?,
                checkpoint_blob=?, checkpoint_schema=?, checkpoint_connector_version=? WHERE id=?
            """,arguments: [record.connectorKind.rawValue,generation,record.state,revision,
                record.checkpoint?.blob,schema,record.checkpoint?.connectorVersion,PersistenceValueCoding.uuid(record.id.rawValue)])
    }

    static func requireTarget(id: AcquisitionTargetID, in db: Database) throws -> TargetRecord {
        guard let record = try readTarget(id: id,in: db) else { throw AcquisitionTargetStoreError.missingTarget(id) }
        return record
    }

    static func readTarget(id: AcquisitionTargetID, in db: Database) throws -> TargetRecord? {
        guard let row = try Row.fetchOne(db,sql: "SELECT * FROM acquisition_targets WHERE id=?",
            arguments: [PersistenceValueCoding.uuid(id.rawValue)]) else { return nil }
        func text(_ field: String) throws -> String {
            let stored: DatabaseValue = row[field]
            guard case .string(let value) = stored.storage else {
                throw AcquisitionTargetStoreError.corruption(field)
            }
            return value
        }
        func counter(_ field: String) throws -> UInt64 {
            let value: DatabaseValue = row[field]
            guard case .int64(let integer) = value.storage, integer >= 0 else {
                throw AcquisitionTargetStoreError.corruption(field)
            }
            return UInt64(integer)
        }
        let storedID = try text("id")
        guard let uuid = UUID(uuidString: storedID), PersistenceValueCoding.uuid(uuid) == storedID else {
            throw AcquisitionTargetStoreError.corruption("id")
        }
        let kind = try text("connector_kind")
        guard !kind.utf8.isEmpty else { throw AcquisitionTargetStoreError.corruption("connector_kind") }
        let generation = try counter("generation")
        guard generation > 0 else { throw AcquisitionTargetStoreError.corruption("generation") }
        let state = try text("state")
        guard state == "enabled" || state == "revoked" else { throw AcquisitionTargetStoreError.corruption("state") }
        let revision = try counter("checkpoint_revision")
        let blob: DatabaseValue = row["checkpoint_blob"]
        let schema: DatabaseValue = row["checkpoint_schema"]
        let version: DatabaseValue = row["checkpoint_connector_version"]
        let checkpoint: CheckpointRecord?
        if blob.isNull && schema.isNull && version.isNull { checkpoint = nil }
        else {
            guard !blob.isNull, !schema.isNull, !version.isNull else { throw AcquisitionTargetStoreError.corruption("checkpoint") }
            guard case .blob(let data) = blob.storage else { throw AcquisitionTargetStoreError.corruption("checkpoint_blob") }
            let schemaNumber = try counter("checkpoint_schema")
            guard schemaNumber > 0 else { throw AcquisitionTargetStoreError.corruption("checkpoint_schema") }
            let versionText = try text("checkpoint_connector_version")
            guard !versionText.utf8.isEmpty else { throw AcquisitionTargetStoreError.corruption("checkpoint_connector_version") }
            guard revision > 0 else { throw AcquisitionTargetStoreError.corruption("checkpoint_revision") }
            checkpoint = CheckpointRecord(blob: data,serializationSchema: schemaNumber,connectorVersion: versionText)
        }
        return TargetRecord(id: AcquisitionTargetID(rawValue: uuid),connectorKind: ConnectorKind(rawValue: kind),
            generation: generation,state: state,checkpointRevision: revision,checkpoint: checkpoint)
    }
}
