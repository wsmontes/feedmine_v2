import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class AcquisitionTargetStoreTests: XCTestCase {
    private func location() -> RuntimeDatabaseLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RuntimeDatabaseLocation(directory: root)
    }
    private func checkpoint(_ byte: UInt8 = 0) -> AcquisitionTargetStore.CheckpointRecord {
        AcquisitionTargetStore.CheckpointRecord(blob: byte == 0 ? Data() : Data([byte]),serializationSchema: 1,connectorVersion: "fake-1")!
    }
    private func failure(_ expected: AcquisitionTargetStoreError, _ operation: () throws -> Void,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(),file: file,line: line) {
            XCTAssertEqual($0 as? AcquisitionTargetStoreError,expected,file: file,line: line)
        }
    }

    func testMigrationExactTableColumnsConstraintsAndIndexes() throws {
        let db = try RuntimeDatabase(location: location())
        try db.read { sql in
            XCTAssertEqual(try Int.fetchOne(sql,sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier='acquisition-target-authority-v1'"),1)
            XCTAssertEqual(try String.fetchAll(sql,sql: "SELECT name FROM pragma_table_info('acquisition_targets') ORDER BY cid"),
                ["id","connector_kind","generation","state","checkpoint_revision","checkpoint_blob","checkpoint_schema","checkpoint_connector_version"])
            let indexes = try Row.fetchAll(sql,sql: "PRAGMA index_list(acquisition_targets)")
            XCTAssertEqual(indexes.count,1); XCTAssertEqual(indexes.first?["origin"] as String?,"pk")
            XCTAssertTrue(try Row.fetchAll(sql,sql: "PRAGMA foreign_key_list(acquisition_targets)").isEmpty)
            let tables = try String.fetchAll(sql,sql: "SELECT name FROM sqlite_schema WHERE type='table'")
            for absent in ["connector_checkpoint","acquisition_batches","sources","source_bindings","acquisition_checkpoints"] { XCTAssertFalse(tables.contains(absent)) }
        }
        XCTAssertFalse(RuntimeMigrations.current.eraseDatabaseOnSchemaChange)
        let invalid = [
            "'',1,'enabled',0,NULL,NULL,NULL",
            "'fake',0,'enabled',0,NULL,NULL,NULL", "'fake',-1,'enabled',0,NULL,NULL,NULL",
            "'fake',1,'unknown',0,NULL,NULL,NULL", "'fake',1,'enabled',-1,NULL,NULL,NULL",
            "'fake',1,'enabled',1,X'',NULL,NULL", "'fake',1,'enabled',1,NULL,1,NULL",
            "'fake',1,'enabled',1,NULL,NULL,'v'", "'fake',1,'enabled',1,X'',1,NULL",
            "'fake',1,'enabled',1,X'',NULL,'v'", "'fake',1,'enabled',1,NULL,1,'v'",
            "'fake',1,'enabled',1,X'',0,'v'", "'fake',1,'enabled',1,X'',-1,'v'",
            "'fake',1,'enabled',1,X'',1,''", "'fake',1,'enabled',0,X'',1,'v'"
        ]
        for (index, values) in invalid.enumerated() {
            do {
                try db.write { sql in try sql.execute(sql: "INSERT INTO acquisition_targets VALUES (?,"+values+")",arguments: [UUID().uuidString.lowercased()]) }
                XCTFail("Constraint accepted \(index)")
            } catch let error as RuntimeDatabaseError {
                guard case .storage(let code,_) = error else { return XCTFail("Expected constraint error") }
                XCTAssertEqual(code & 0xff,19)
            }
        }
    }

    func testRegisterDuplicateMissingAndExactReopen() throws {
        let location = location(), id = AcquisitionTargetID()
        let initial: AcquisitionTargetStore.TargetRecord
        do {
            let store = AcquisitionTargetStore(database: try RuntimeDatabase(location: location))
            initial = try store.register(id: id,connectorKind: ConnectorKind(rawValue: " exact "))
            XCTAssertEqual(initial.id,id); XCTAssertEqual(initial.connectorKind.rawValue," exact ")
            XCTAssertEqual(initial.generation,1); XCTAssertEqual(initial.state,"enabled")
            XCTAssertEqual(initial.checkpointRevision,0); XCTAssertNil(initial.checkpoint)
            failure(.targetAlreadyExists(id)) { _ = try store.register(id: id,connectorKind: .syndication) }
            failure(.invalidRepresentation("connector_kind")) { _ = try store.register(id: AcquisitionTargetID(),connectorKind: ConnectorKind(rawValue: "")) }
            let missing = AcquisitionTargetID()
            XCTAssertNil(try store.target(id: missing))
            failure(.missingTarget(missing)) { _ = try store.revoke(id: missing,expectedGeneration: 1) }
            XCTAssertEqual(try store.target(id: id),initial)
        }
        XCTAssertEqual(try AcquisitionTargetStore(database: RuntimeDatabase(location: location)).target(id: id),initial)
    }

    func testReconfigureAlwaysFencesWithCheckpointPreserveClearAndReplace() throws {
        let location = location(), id = AcquisitionTargetID()
        let final: AcquisitionTargetStore.TargetRecord
        do {
            let store = AcquisitionTargetStore(database: try RuntimeDatabase(location: location))
            _ = try store.register(id: id,connectorKind: .syndication)
            var record = try store.reconfigure(id: id,expectedGeneration: 1,connectorKind: .syndication,checkpoint: .clear)
            XCTAssertEqual(record.generation,2); XCTAssertEqual(record.checkpointRevision,0)
            record = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: 2,expectedCheckpointRevision: 0,next: checkpoint())
            let preserved = try store.reconfigure(id: id,expectedGeneration: 2,connectorKind: .syndication,checkpoint: .preserve)
            XCTAssertEqual(preserved.generation,3); XCTAssertEqual(preserved.checkpoint,record.checkpoint); XCTAssertEqual(preserved.checkpointRevision,1)
            record = try store.reconfigure(id: id,expectedGeneration: 3,connectorKind: ConnectorKind(rawValue: " new "),checkpoint: .replace(checkpoint(1)))
            XCTAssertEqual(record.id,id); XCTAssertEqual(record.connectorKind.rawValue," new "); XCTAssertEqual(record.generation,4); XCTAssertEqual(record.checkpointRevision,2)
            let identical = try store.reconfigure(id: id,expectedGeneration: 4,connectorKind: record.connectorKind,checkpoint: .replace(checkpoint(1)))
            XCTAssertEqual(identical.generation,5); XCTAssertEqual(identical.checkpointRevision,2)
            failure(.staleGeneration(expected: 4,actual: 5)) { _ = try store.reconfigure(id: id,expectedGeneration: 4,connectorKind: .syndication,checkpoint: .clear) }
            XCTAssertEqual(try store.target(id: id),identical)
            final = try store.reconfigure(id: id,expectedGeneration: 5,connectorKind: .syndication,checkpoint: .clear)
            XCTAssertNil(final.checkpoint); XCTAssertEqual(final.checkpointRevision,3); XCTAssertEqual(final.generation,6)
        }
        XCTAssertEqual(try AcquisitionTargetStore(database: RuntimeDatabase(location: location)).target(id: id),final)
    }

    func testStateTransitionsPreserveCheckpointAndFenceOldGenerations() throws {
        let store = AcquisitionTargetStore(database: try RuntimeDatabase(location: location())), id = AcquisitionTargetID()
        _ = try store.register(id: id,connectorKind: .syndication)
        _ = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: 0,next: checkpoint())
        let revoked = try store.revoke(id: id,expectedGeneration: 1)
        XCTAssertEqual(revoked.generation,2); XCTAssertEqual(revoked.state,"revoked"); XCTAssertEqual(revoked.checkpoint,checkpoint())
        XCTAssertEqual(try store.revoke(id: id,expectedGeneration: 2),revoked)
        failure(.targetRevoked(id)) { _ = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: 0,next: checkpoint(1)) }
        let configured = try store.reconfigure(id: id,expectedGeneration: 2,connectorKind: .syndication,checkpoint: .preserve)
        XCTAssertEqual(configured.state,"revoked"); XCTAssertEqual(configured.generation,3)
        let enabled = try store.enable(id: id,expectedGeneration: 3)
        XCTAssertEqual(enabled.generation,4); XCTAssertEqual(enabled.state,"enabled"); XCTAssertEqual(enabled.checkpoint,checkpoint())
        XCTAssertEqual(try store.enable(id: id,expectedGeneration: 4),enabled)
        for generation in [UInt64(1),2,3] {
            failure(.staleGeneration(expected: generation,actual: 4)) { _ = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: generation,expectedCheckpointRevision: 1,next: checkpoint()) }
        }
        XCTAssertEqual(try store.target(id: id),enabled)
    }

    func testCheckpointCASAlwaysAdvancesEvenIdenticalAndStaleProposalWritesNothing() throws {
        let location = location(), id = AcquisitionTargetID()
        let store = AcquisitionTargetStore(database: try RuntimeDatabase(location: location))
        _ = try store.register(id: id,connectorKind: .syndication)
        let first = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: 0,next: checkpoint())
        XCTAssertEqual(first.generation,1); XCTAssertEqual(first.checkpointRevision,1); XCTAssertEqual(first.checkpoint,checkpoint())
        let second = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: 1,next: checkpoint())
        XCTAssertEqual(second.checkpointRevision,2); XCTAssertEqual(second.generation,1)
        failure(.staleCheckpoint(expected: 1,actual: 2)) { _ = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: 1,next: checkpoint(1)) }
        XCTAssertEqual(try store.target(id: id),second)
        XCTAssertEqual(try AcquisitionTargetStore(database: RuntimeDatabase(location: location)).target(id: id)?.checkpoint?.blob,Data())
    }

    func testCounterOverflowAndCheckpointOverflowReconfigurationAreAtomic() throws {
        let db = try RuntimeDatabase(location: location()), store = AcquisitionTargetStore(database: db), id = AcquisitionTargetID()
        _ = try store.register(id: id,connectorKind: .syndication)
        try db.write { try $0.execute(sql: "UPDATE acquisition_targets SET generation = ?",arguments: [Int64.max]) }
        let before = try store.target(id: id)
        failure(.generationExhausted(id)) { _ = try store.revoke(id: id,expectedGeneration: UInt64(Int64.max)) }
        failure(.generationExhausted(id)) { _ = try store.reconfigure(id: id,expectedGeneration: UInt64(Int64.max),connectorKind: .syndication,checkpoint: .preserve) }
        XCTAssertEqual(try store.target(id: id),before)
        try db.write { try $0.execute(sql: "UPDATE acquisition_targets SET generation=1, checkpoint_revision=?",arguments: [Int64.max]) }
        let checkpointBefore = try store.target(id: id)
        failure(.checkpointRevisionExhausted(id)) { _ = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: UInt64(Int64.max),next: checkpoint()) }
        failure(.checkpointRevisionExhausted(id)) { _ = try store.reconfigure(id: id,expectedGeneration: 1,connectorKind: ConnectorKind(rawValue: "changed"),checkpoint: .replace(checkpoint())) }
        XCTAssertEqual(try store.target(id: id),checkpointBefore)
    }

    func testPersistedTypeCorruptionDoesNotNormalizeAndInputCounterIsChecked() throws {
        let db = try RuntimeDatabase(location: location()), store = AcquisitionTargetStore(database: db), id = AcquisitionTargetID()
        _ = try store.register(id: id,connectorKind: .syndication)
        // SQLite affinity/CHECK permits these representations; production decoding remains strict.
        try db.write { try $0.execute(sql: "UPDATE acquisition_targets SET generation=1.5") }
        failure(.corruption("generation")) { _ = try store.target(id: id) }
        try db.write { try $0.execute(sql: "UPDATE acquisition_targets SET generation=1, checkpoint_revision=1, checkpoint_blob='text', checkpoint_schema=1, checkpoint_connector_version='v'") }
        failure(.corruption("checkpoint_blob")) { _ = try store.target(id: id) }
        try db.write { try $0.execute(sql: "UPDATE acquisition_targets SET checkpoint_blob=NULL, checkpoint_schema=NULL, checkpoint_connector_version=NULL") }
        let huge = AcquisitionTargetStore.CheckpointRecord(blob: Data(),serializationSchema: .max,connectorVersion: "v")!
        failure(.invalidRepresentation("checkpoint_schema")) { _ = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: 1,next: huge) }
        XCTAssertNil(try store.target(id: id)?.checkpoint)
    }

    func testMigrationPreservesOldSchemaObjectsAndSentinelBytes() throws {
        let location = location(), bytes = Data([0,255,1,0])
        try FileManager.default.createDirectory(at: location.directory,withIntermediateDirectories: true)
        let before: Set<String>
        do {
            let queue = try DatabaseQueue(path: location.databaseURL.path)
            try RuntimeMigrations.current.migrate(queue,upTo: "publication-exposure-index-v1")
            try queue.write { sql in
                try sql.execute(sql: "CREATE TABLE sentinel (value BLOB NOT NULL)")
                try sql.execute(sql: "INSERT INTO sentinel VALUES (?)",arguments: [bytes])
            }
            before = try queue.read { Set(try String.fetchAll($0,sql: "SELECT type || ':' || name FROM sqlite_schema")) }
        }
        let db = try RuntimeDatabase(location: location)
        let after = try db.read { Set(try String.fetchAll($0,sql: "SELECT type || ':' || name FROM sqlite_schema")) }
        XCTAssertTrue(before.isSubset(of: after)); XCTAssertTrue(after.contains("table:acquisition_targets"))
        XCTAssertEqual(try db.read { try Data.fetchOne($0,sql: "SELECT value FROM sentinel") },bytes)
    }
    func testExactEnvelopeVersionBytesAndStateTransitionOverflow() throws {
        let db = try RuntimeDatabase(location: location()), store = AcquisitionTargetStore(database: db), id = AcquisitionTargetID()
        _ = try store.register(id: id,connectorKind: .syndication)
        let composed = AcquisitionTargetStore.CheckpointRecord(blob: Data(),serializationSchema: 1,connectorVersion: "\u{00e9}")!
        let decomposed = AcquisitionTargetStore.CheckpointRecord(blob: Data(),serializationSchema: 1,connectorVersion: "e\u{0301}")!
        _ = try store.compareAndSwapCheckpoint(id: id,expectedGeneration: 1,expectedCheckpointRevision: 0,next: composed)
        let changed = try store.reconfigure(id: id,expectedGeneration: 1,connectorKind: .syndication,checkpoint: .replace(decomposed))
        XCTAssertEqual(changed.checkpointRevision,2)
        XCTAssertEqual(Array(changed.checkpoint!.connectorVersion.utf8),Array(decomposed.connectorVersion.utf8))
        let revoked = try store.revoke(id: id,expectedGeneration: 2)
        XCTAssertEqual(revoked.generation,3)
        try db.write { try $0.execute(sql: "UPDATE acquisition_targets SET generation=?",arguments: [Int64.max]) }
        let before = try store.target(id: id)
        failure(.generationExhausted(id)) { _ = try store.enable(id: id,expectedGeneration: UInt64(Int64.max)) }
        XCTAssertEqual(try store.target(id: id),before)
        XCTAssertEqual(try store.revoke(id: id,expectedGeneration: UInt64(Int64.max)),before)
    }

}
