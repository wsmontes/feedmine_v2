import Foundation
import GRDB
import FeedMineDomain

/// Durable ownership of frozen history. Resolving known raw inputs never reinterprets words stored
/// in an old Edition; ambiguous adoption rolls back instead of merging two logical readers.
public struct ReaderHistoryBindingStore: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case missingEdition, incompatibleAdoption, staleAdoptionPolicy, editionAlreadyOwned
        case runtimeNamespaceAlreadyOwned, runtimeNamespaceConflict, activeEditionConflict, corruption
    }

    public struct Record: Hashable, Sendable {
        public let id: UUID
        public let logicalKey: ContextKey
        public let runtimeNamespace: String
        public let activeEditionID: FeedEditionID?
    }

    public enum Evidence: Hashable, Sendable {
        case exactContext
        case legacyWords(ReaderWordExclusionSnapshot)
    }

    public struct Adoption: Hashable, Sendable {
        public let editionID: FeedEditionID
        public let publicationKey: ContextKey
        public let evidence: Evidence
        /// Original durable statement, before card-authoritative Edition correction. Never a neighbour cursor.
        public let checkpoint: SessionStore.CheckpointRecord?
        public init(editionID: FeedEditionID, publicationKey: ContextKey, evidence: Evidence,
            checkpoint: SessionStore.CheckpointRecord? = nil) {
            self.editionID = editionID
            self.publicationKey = publicationKey
            self.evidence = evidence
            self.checkpoint = checkpoint
        }
    }

    let database: RuntimeDatabase
    public init(database: RuntimeDatabase) { self.database = database }

    public func binding(for key: ContextKey) throws -> Record? {
        try database.read { try Self.read(key, in: $0) }
    }

    public func owner(ofEditionID editionID: FeedEditionID) throws -> Record? {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT b.logical_key_json FROM reader_history_bindings b
                JOIN reader_history_editions e ON e.binding_id = b.id WHERE e.edition_id = ?
                """, arguments: [PersistenceValueCoding.uuid(editionID.rawValue)]) else { return nil }
            return try Self.read(Self.key(row, field: "logical_key_json"), in: db)
        }
    }

    public func resolve(logicalKey: ContextKey, adopting adoption: Adoption? = nil) throws -> Record {
        try resolve(logicalKey: logicalKey, adopting: adoption, independentCheckpoint: nil)
    }

    /// An explicit recovery choice selects the raw criteria without borrowing an unowned legacy
    /// namespace. The shown active statement must still be current in the same writer transaction.
    public func resolveIndependentHistory(logicalKey: ContextKey,
        preservingActiveCheckpoint checkpoint: SessionStore.CheckpointRecord) throws -> Record {
        try resolve(logicalKey: logicalKey, adopting: nil, independentCheckpoint: checkpoint)
    }

    /// Commits the reader's explicit criteria choice and its ownership interpretation together.
    /// Later activation may fail, but a relaunch must honour the choice already saved here.
    public func chooseRecoveryCriteria(_ key: ContextKey, adopting adoption: Adoption? = nil,
        preservingActiveCheckpoint checkpoint: SessionStore.CheckpointRecord,
        expectedContext: ContextKey) throws -> Record {
        try database.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1"),
                try SessionStore.checkpoint(row) == checkpoint,
                try ReaderPreferencesStore.read(db)?.activeContextKey == expectedContext else {
                throw Failure.incompatibleAdoption
            }
            let binding = try Self.resolve(logicalKey: key, adopting: adoption,
                independentCheckpoint: adoption == nil ? checkpoint : nil, in: db)
            _ = try ReaderPreferencesStore.setContext(key, in: db)
            return binding
        }
    }

    private func resolve(logicalKey: ContextKey, adopting adoption: Adoption?,
        independentCheckpoint: SessionStore.CheckpointRecord?) throws -> Record {
        try database.write { db in
            try Self.resolve(logicalKey: logicalKey, adopting: adoption,
                independentCheckpoint: independentCheckpoint, in: db)
        }
    }

    private static func resolve(logicalKey: ContextKey, adopting adoption: Adoption?,
        independentCheckpoint: SessionStore.CheckpointRecord?, in db: Database) throws -> Record {
        if let independentCheckpoint {
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1"),
                try SessionStore.checkpoint(row) == independentCheckpoint else { throw Failure.incompatibleAdoption }
        }
        let existing = try Self.read(logicalKey, in: db)
        if let existing, adoption == nil { return existing }
        if let existing, let adoption, let active = existing.activeEditionID {
            guard active == adoption.editionID else { throw Failure.activeEditionConflict }
            guard let row = try Row.fetchOne(db, sql: """
                SELECT publication_key_json FROM reader_history_editions WHERE edition_id = ? AND binding_id = ?
                """, arguments: [PersistenceValueCoding.uuid(active.rawValue), PersistenceValueCoding.uuid(existing.id)]),
                try Self.key(row, field: "publication_key_json") == adoption.publicationKey else { throw Failure.incompatibleAdoption }
            // Established ownership is a fact, not a fresh policy inference. Do not replace its provenance.
            return existing
        }
        var adoptedPoint: SessionStore.CheckpointRecord?
        var provenance: Data?
        var kind = "exact_context"
        if let adoption {
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM feed_editions WHERE id = ?",
                arguments: [PersistenceValueCoding.uuid(adoption.editionID.rawValue)]) else { throw Failure.missingEdition }
            guard try PublicationStore.decodeEdition(row).editorialRevision.contextKey == adoption.publicationKey else {
                throw Failure.incompatibleAdoption
            }
            switch adoption.evidence {
            case .exactContext:
                guard logicalKey == adoption.publicationKey else { throw Failure.incompatibleAdoption }
            case .legacyWords(let snapshot):
                let forward = ContextKey(request: logicalKey.request, preset: logicalKey.preset,
                    filter: logicalKey.filter.replacing(exclusions: snapshot.exclusions), searchScope: logicalKey.searchScope,
                    identitySchemaVersion: logicalKey.identitySchemaVersion)
                guard snapshot.context == logicalKey.filter.exclusions, forward == adoption.publicationKey else {
                    throw Failure.incompatibleAdoption
                }
                guard try snapshot.matches(settings: ReaderPreferencesStore.publicationSettings(in: db)) else {
                    throw Failure.staleAdoptionPolicy
                }
                kind = "legacy_words"
                provenance = try Self.encode(PolicyEvidence(snapshot))
            }
            if let original = adoption.checkpoint {
                adoptedPoint = try Self.validatedCheckpoint(original, editionID: adoption.editionID, in: db)
            }
            if let owner = try String.fetchOne(db,
                sql: "SELECT binding_id FROM reader_history_editions WHERE edition_id = ?",
                arguments: [PersistenceValueCoding.uuid(adoption.editionID.rawValue)]),
                owner != existing.map({ PersistenceValueCoding.uuid($0.id) }) { throw Failure.editionAlreadyOwned }
        }
        let id = existing?.id ?? UUID()
        let preferredNamespace = adoption?.publicationKey.canonicalIdentity ?? logicalKey.canonicalIdentity
        var namespace = independentCheckpoint == nil ? preferredNamespace
            : "reader-binding:" + PersistenceValueCoding.uuid(id)
        if let existing, existing.runtimeNamespace != preferredNamespace { throw Failure.runtimeNamespaceConflict }
        if let owner = try String.fetchOne(db, sql: "SELECT id FROM reader_history_bindings WHERE runtime_namespace = ?",
            arguments: [preferredNamespace]), owner != PersistenceValueCoding.uuid(id) {
            guard adoption == nil else { throw Failure.runtimeNamespaceAlreadyOwned }
            namespace = "reader-binding:" + PersistenceValueCoding.uuid(id)
        }
        if existing == nil {
            try db.execute(sql: """
                INSERT INTO reader_history_bindings(id, logical_identity, logical_key_json, runtime_namespace)
                VALUES (?, ?, ?, ?)
                """, arguments: [PersistenceValueCoding.uuid(id), logicalKey.canonicalIdentity,
                    try Self.encode(logicalKey), namespace])
        }
        if let adoption {
            try db.execute(sql: """
                INSERT INTO reader_history_editions(edition_id, binding_id, publication_key_json, adoption_kind, adoption_policy_json)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [PersistenceValueCoding.uuid(adoption.editionID.rawValue), PersistenceValueCoding.uuid(id),
                    try Self.encode(adoption.publicationKey), kind, provenance])
            try db.execute(sql: "UPDATE reader_history_bindings SET active_edition_id = ? WHERE id = ?",
                arguments: [PersistenceValueCoding.uuid(adoption.editionID.rawValue), PersistenceValueCoding.uuid(id)])
            if let adoptedPoint {
                try SessionStore.persistOwned(adoptedPoint, bindingID: id, in: db)
            } else {
                try SessionStore.seedBindingCheckpoint(bindingID: id, editionID: adoption.editionID, in: db)
            }
        }
        guard let result = try Self.read(logicalKey, in: db) else { throw Failure.corruption }
        return result
    }


    private static func validatedCheckpoint(_ original: SessionStore.CheckpointRecord,
        editionID: FeedEditionID, in db: Database) throws -> SessionStore.CheckpointRecord {
        // Recheck the exact source statement in the ownership transaction. A caller cannot fabricate
        // a position or silently substitute a resolved neighbour for the saved durable anchor.
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM session_checkpoint WHERE card_id = ?",
            arguments: [PersistenceValueCoding.uuid(original.cardID.rawValue)])
            + Row.fetchAll(db, sql: "SELECT * FROM context_checkpoints WHERE card_id = ?",
                arguments: [PersistenceValueCoding.uuid(original.cardID.rawValue)])
        guard try rows.contains(where: { try SessionStore.checkpoint($0) == original }) else {
            throw Failure.incompatibleAdoption
        }
        let resolvedEdition = try PublicationStore.location(ofCard: original.cardID, in: db)?.editionID
            ?? original.editionID
        guard resolvedEdition == editionID else { throw Failure.incompatibleAdoption }
        return .init(editionID: editionID, cardID: original.cardID, anchorPlacement: original.anchorPlacement,
            updatedAt: original.updatedAt, topDelta: original.topDelta, cardHeight: original.cardHeight)
    }

    static func attachNewEdition(_ edition: PublicationStore.EditionRecord,
        expectation: PublicationStore.BindingPublicationExpectation, in db: Database) throws {
        try SessionStore.requirePublicationActivation(expectation.activation, in: db)
        let id = PersistenceValueCoding.uuid(expectation.activation.bindingID)
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM reader_history_bindings WHERE id = ?", arguments: [id]) else {
            throw SessionStoreError.missingHistoryBinding
        }
        let active = try SessionStore.scopedEdition(expectation.activation, in: db)
        guard active == expectation.expectedActiveEditionID else { throw SessionStoreError.staleHistoryBinding }
        guard try Self.key(row, field: "logical_key_json") == edition.editorialRevision.contextKey else {
            throw Failure.incompatibleAdoption
        }
        try db.execute(sql: """
            INSERT INTO reader_history_editions(edition_id, binding_id, publication_key_json, adoption_kind)
            VALUES (?, ?, ?, 'exact_context')
            """, arguments: [PersistenceValueCoding.uuid(edition.id.rawValue), id, try encode(edition.editorialRevision.contextKey)])
        if try SessionStore.isCurrentActivation(expectation.activation, in: db) {
            try db.execute(sql: "UPDATE reader_history_bindings SET active_edition_id = ? WHERE id = ?",
                arguments: [PersistenceValueCoding.uuid(edition.id.rawValue), id])
        } else {
            try db.execute(sql: "UPDATE reader_history_preparations SET edition_id = ?, checkpoint_present = 0 WHERE binding_id = ?",
                arguments: [PersistenceValueCoding.uuid(edition.id.rawValue), id])
        }
    }

    private struct PolicyEvidence: Encodable {
        struct Template: Encodable { let key: String; let rules: [String] }
        let context: ReaderContentExclusions
        let effective: ReaderContentExclusions
        let templates: [Template]
        init(_ snapshot: ReaderWordExclusionSnapshot) {
            context = snapshot.context
            effective = snapshot.exclusions
            templates = snapshot.templates.map { Template(key: $0.key, rules: $0.rules) }
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func key(_ row: Row, field: String) throws -> ContextKey {
        guard case .blob(let data) = PublicationRecordFields(row).value(field).storage else { throw Failure.corruption }
        return try JSONDecoder().decode(ContextKey.self, from: data)
    }

    private static func read(_ key: ContextKey, in db: Database) throws -> Record? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM reader_history_bindings WHERE logical_identity = ?",
            arguments: [key.canonicalIdentity]) else { return nil }
        let fields = PublicationRecordFields(row), logical = try Self.key(row, field: "logical_key_json")
        guard logical == key, try fields.string("logical_identity") == logical.canonicalIdentity else { throw Failure.corruption }
        return Record(id: try fields.uuid("id"), logicalKey: logical,
            runtimeNamespace: try fields.string("runtime_namespace"),
            activeEditionID: try fields.optionalUUID("active_edition_id").map { FeedEditionID(rawValue: $0) })
    }
}
