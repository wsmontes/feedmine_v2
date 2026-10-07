//
// File: RuntimeMigrationTests.swift
// Module: FeedMinePersistenceTests
//
// Responsibility:
//   Verify migration authority, safe reopening and non-erasure on failure.
//
// Owns:
//   Isolated temporary on-disk lifecycle/configuration or migration invariant tests.
//
// Does not own:
//   Production schemas, in-memory fallback, retry/retention or generic test frameworks.
//
// Allowed dependencies:
//   FeedMinePersistence, Foundation, XCTest and GRDB for SQLite-specific checks.
//
// Architectural invariants:
//   INV-11, INV-12; runtime failure must not become an empty replacement store.
//
// Planned public surface:
//   Phase 2A lifecycle tests only; no product API.
//
// Status:
//   Phase 2A persistence lifecycle verification.
//

import Foundation
import XCTest
import GRDB
@testable import FeedMinePersistence

final class RuntimeMigrationTests: XCTestCase {
    private func location() -> RuntimeDatabaseLocation {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RuntimeDatabaseLocation(directory: directory)
    }

    func testReopenRetainsExactlyOneFoundationMigration() throws {
        let location = location()
        do {
            let database = try RuntimeDatabase(location: location)
            XCTAssertEqual(try database.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }, ["runtime-foundation-v1"])
        }
        let reopened = try RuntimeDatabase(location: location)
        XCTAssertEqual(try reopened.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }, ["runtime-foundation-v1"])
        XCTAssertFalse(RuntimeMigrations.current.eraseDatabaseOnSchemaChange)
    }

    func testFailedMigrationPreservesExistingSentinel() throws {
        let location = location()
        do {
            let database = try RuntimeDatabase(location: location)
            try database.write { db in
                try db.execute(sql: "CREATE TABLE sentinel (value TEXT)")
                try db.execute(sql: "INSERT INTO sentinel VALUES ('durable')")
            }
        }
        var failing = RuntimeMigrations.current
        failing.registerMigration("test-deliberate-failure") { db in
            try db.execute(sql: "DELETE FROM sentinel")
            throw NSError(domain: "MigrationTest", code: 1)
        }
        XCTAssertThrowsError(try RuntimeDatabase(location: location, migrator: failing))
        let reopened = try RuntimeDatabase(location: location)
        XCTAssertEqual(try reopened.read { try String.fetchAll($0, sql: "SELECT value FROM sentinel") }, ["durable"])
        XCTAssertEqual(try reopened.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }, ["runtime-foundation-v1"])
    }
}
