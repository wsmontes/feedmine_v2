import Foundation
import XCTest
import GRDB
@testable import FeedMinePersistence

final class CanonicalSupplySchemaTests: XCTestCase {
    private func withDatabase(_ body: (RuntimeDatabaseLocation, RuntimeDatabase) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        try body(location, RuntimeDatabase(location: location))
    }

    private func migrationIdentifiers(_ database: RuntimeDatabase) throws -> [String] {
        try database.read {
            try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
    }

    /// Asserts the ownership of canonical-supply-v1: its four tables exist and the tables
    /// explicitly deferred by Phase 3B1 stay absent. It deliberately makes no claim about
    /// the total set of runtime tables, so later migrations may legitimately add theirs.
    private func assertCanonicalTableOwnership(_ database: RuntimeDatabase,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let tables = try database.read {
            try String.fetchAll($0, sql: "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations' ORDER BY name")
        }
        for owned in ["origin_records", "origin_revisions", "source_memberships", "selection_supply", "media_candidates"] {
            XCTAssertTrue(tables.contains(owned),
                "canonical-supply-v1 must own table \(owned), present tables: \(tables)", file: file, line: line)
        }
        let deferred = ["content_relations", "content_entities", "content_clusters",
            "interaction_offers"]
        for absent in deferred {
            XCTAssertFalse(tables.contains(absent),
                "Deferred table \(absent) must remain absent, present tables: \(tables)", file: file, line: line)
        }
    }

    func testCanonicalMigrationCreatesOwnedTablesAndSurvivesReopen() throws {
        try withDatabase { location, database in
            let firstHistory = try migrationIdentifiers(database)
            for identifier in ["canonical-supply-v1", "publication-restore-v1", "runtime-foundation-v1"] {
                XCTAssertEqual(firstHistory.filter { $0 == identifier }.count, 1,
                    "Expected \(identifier) exactly once, got \(firstHistory)")
            }
            try assertCanonicalTableOwnership(database)

            let reopened = try RuntimeDatabase(location: location)
            let secondHistory = try migrationIdentifiers(reopened)
            XCTAssertEqual(secondHistory, firstHistory)
            try assertCanonicalTableOwnership(reopened)
        }
    }

    private func insertOrigin(_ database: RuntimeDatabase, id: String, value: String) throws {
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO origin_records (id, object_connector_kind, object_namespace, object_value,
                    object_role, availability, first_observed_at, last_observed_at)
                VALUES (?, 'test', 'namespace', ?, 'object', 'available', 1, 1)
                """, arguments: [id, value])
        }
    }

    private func insertRevision(_ database: RuntimeDatabase, id: String, origin: String,
        version: String? = nil) throws {
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO origin_revisions (id, origin_record_id, version_connector_kind,
                    version_namespace, version_value, version_role, observed_at)
                VALUES (?, ?, ?, ?, ?, ?, 1)
                """, arguments: [id, origin, version.map { _ in "test" },
                    version.map { _ in "versions" }, version, version.map { _ in "version" }])
        }
    }

    private func assertConstraint(_ database: RuntimeDatabase, sql: String, kind: String,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try database.write { try $0.execute(sql: sql) }, file: file, line: line) { error in
            guard case let RuntimeDatabaseError.storage(code, message) = error else {
                return XCTFail("Expected SQLite constraint error, got \(error)", file: file, line: line)
            }
            XCTAssertEqual(code & 0xff, 19, file: file, line: line)
            XCTAssertTrue(message.contains(kind), message, file: file, line: line)
        }
    }

    func testExternalObjectTupleUsesExactBinaryUniqueness() throws {
        try withDatabase { _, database in
            let r1 = UUID().uuidString.lowercased()
            try insertOrigin(database, id: r1, value: "Object")
            XCTAssertThrowsError(try insertOrigin(database, id: UUID().uuidString.lowercased(), value: "Object")) { error in
                guard case let RuntimeDatabaseError.storage(code, message) = error else {
                    return XCTFail("Expected unique constraint, got \(error)")
                }
                XCTAssertEqual(code & 0xff, 19)
                XCTAssertTrue(message.contains("UNIQUE"))
            }
            try insertOrigin(database, id: UUID().uuidString.lowercased(), value: "object")
            try insertOrigin(database, id: UUID().uuidString.lowercased(), value: " Object ")
            let count = try database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM origin_records") }
            XCTAssertEqual(count, 3)
            assertConstraint(database, sql: "UPDATE origin_records SET object_role = 'alias' WHERE id = '\(r1)'", kind: "CHECK")
            assertConstraint(database, sql: "UPDATE origin_records SET availability = 'invalid' WHERE id = '\(r1)'", kind: "CHECK")
        }
    }

    func testVersionIdentityIsCompleteAndUniqueWithinOrigin() throws {
        try withDatabase { _, database in
            let r1 = UUID().uuidString.lowercased(), r2 = UUID().uuidString.lowercased()
            let v1 = UUID().uuidString.lowercased()
            try insertOrigin(database, id: r1, value: "one")
            try insertOrigin(database, id: r2, value: "two")
            try insertRevision(database, id: v1, origin: r1)
            // Every incomplete combination of the four optional identity columns fails.
            let fields = ["version_connector_kind", "version_namespace", "version_value", "version_role"]
            let values = ["test", "versions", "v1", "version"]
            for mask in 1..<15 {
                let assignments = fields.enumerated().map { index, field in
                    "\(field) = " + ((mask & (1 << index)) != 0 ? "'\(values[index])'" : "NULL")
                }.joined(separator: ", ")
                assertConstraint(database, sql: "UPDATE origin_revisions SET \(assignments) WHERE id = '\(v1)'", kind: "CHECK")
            }
            assertConstraint(database, sql: """
                UPDATE origin_revisions SET version_connector_kind = 'test', version_namespace = 'versions',
                    version_value = 'v1', version_role = 'object' WHERE id = '\(v1)'
                """, kind: "CHECK")
            try insertRevision(database, id: UUID().uuidString.lowercased(), origin: r1, version: "v1")
            XCTAssertThrowsError(try insertRevision(database, id: UUID().uuidString.lowercased(), origin: r1, version: "v1")) { error in
                guard case let RuntimeDatabaseError.storage(code, message) = error else {
                    return XCTFail("Expected unique constraint, got \(error)")
                }
                XCTAssertEqual(code & 0xff, 19)
                XCTAssertTrue(message.contains("UNIQUE"))
            }
            try insertRevision(database, id: UUID().uuidString.lowercased(), origin: r2, version: "v1")
            try insertRevision(database, id: UUID().uuidString.lowercased(), origin: r1)
        }
    }

    func testSameOriginCurrentPointerAndSupplyForeignKeysProtectRevisions() throws {
        try withDatabase { _, database in
            let r1 = UUID().uuidString.lowercased(), r2 = UUID().uuidString.lowercased()
            let v1 = UUID().uuidString.lowercased(), v2 = UUID().uuidString.lowercased()
            try insertOrigin(database, id: r1, value: "one")
            try insertOrigin(database, id: r2, value: "two")
            try insertRevision(database, id: v1, origin: r1)
            try insertRevision(database, id: v2, origin: r2)
            try database.write { db in
                try db.execute(sql: "UPDATE origin_records SET current_revision_id = ? WHERE id = ?", arguments: [v1, r1])
            }
            assertConstraint(database, sql: "UPDATE origin_records SET current_revision_id = '\(v2)' WHERE id = '\(r1)'", kind: "FOREIGN KEY")
            assertConstraint(database, sql: "DELETE FROM origin_revisions WHERE id = '\(v1)'", kind: "FOREIGN KEY")
            assertConstraint(database, sql: """
                INSERT INTO selection_supply (origin_record_id, origin_revision_id, sort_date, sort_date_basis)
                VALUES ('\(r1)', '\(v2)', 1, 'authored')
                """, kind: "FOREIGN KEY")
            let current = try database.read { try String.fetchOne($0,
                sql: "SELECT current_revision_id FROM origin_records WHERE id = ?", arguments: [r1]) }
            XCTAssertEqual(current, v1)
            let revisions = try database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM origin_revisions") }
            XCTAssertEqual(revisions, 2)
        }
    }

    func testMembershipAndSortBasisConstraintsAndOrderingIndex() throws {
        try withDatabase { _, database in
            let origin = UUID().uuidString.lowercased(), revision = UUID().uuidString.lowercased()
            let source = UUID().uuidString.lowercased()
            try insertOrigin(database, id: origin, value: "one")
            try insertRevision(database, id: revision, origin: origin)
            assertConstraint(database, sql: """
                INSERT INTO source_memberships (origin_record_id, source_id, membership_kind, first_observed_at, last_observed_at)
                VALUES ('\(origin)', '\(source)', 'invalid', 1, 1)
                """, kind: "CHECK")
            try database.write { db in
                try db.execute(sql: """
                    INSERT INTO source_memberships VALUES (?, ?, 'direct', 1, 1);
                    """, arguments: [origin, source])
                try db.execute(sql: """
                    INSERT INTO selection_supply VALUES (?, ?, 1, 'observedFallback')
                    """, arguments: [origin, revision])
            }
            assertConstraint(database, sql: "UPDATE selection_supply SET sort_date_basis = 'modified'", kind: "CHECK")
            assertConstraint(database, sql: "DELETE FROM origin_records WHERE id = '\(origin)'", kind: "FOREIGN KEY")
            let keys = try database.read { db in
                try Row.fetchAll(db, sql: "PRAGMA index_xinfo('selection_supply_order')")
                    .filter { ($0["key"] as Int) == 1 }
                    .map { row in "\(row["name"] as String):\(row["desc"] as Int)" }
            }
            XCTAssertEqual(keys, ["sort_date:1", "origin_record_id:1"])
        }
    }
}
