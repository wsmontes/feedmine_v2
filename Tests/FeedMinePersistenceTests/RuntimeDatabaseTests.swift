//
// File: RuntimeDatabaseTests.swift
// Module: FeedMinePersistenceTests
//
// Responsibility:
//   Verify physical runtime lifecycle, SQLite configuration and factual failures.
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

final class RuntimeDatabaseTests: XCTestCase {
    private func location() throws -> RuntimeDatabaseLocation {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RuntimeDatabaseLocation(directory: directory)
    }

    func testLocationUsesCanonicalRuntimeFilename() {
        let root = URL(fileURLWithPath: "/application-support", isDirectory: true)
        XCTAssertEqual(RuntimeDatabaseLocation.applicationSupport(root).databaseURL.path, "/application-support/FeedMine/runtime.sqlite")
    }

    func testOpenCreatesFileWithOnlyMigrationBookkeeping() throws {
        let location = try location()
        let database = try RuntimeDatabase(location: location)
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.databaseURL.path))
        let tables = try database.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%'") }
        XCTAssertEqual(tables, ["grdb_migrations"])
    }

    func testPoolUsesWALAndForeignKeysOnReaderAndWriter() throws {
        let database = try RuntimeDatabase(location: location())
        XCTAssertEqual(try database.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }, "wal")
        XCTAssertEqual(try database.read { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") }, 1)
        XCTAssertEqual(try database.write { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") }, 1)
        try database.write { db in
            try db.execute(sql: "CREATE TABLE parent (id INTEGER PRIMARY KEY)")
            try db.execute(sql: "CREATE TABLE child (parent_id INTEGER REFERENCES parent(id))")
        }
        XCTAssertThrowsError(try database.write { try $0.execute(sql: "INSERT INTO child VALUES (123)") }) { error in
            guard case RuntimeDatabaseError.storage(let code, let message) = error else {
                return XCTFail("Expected typed SQLite storage failure, got \(error)")
            }
            XCTAssertEqual(code & 0xFF, 19) // SQLITE_CONSTRAINT primary code.
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testWritesRollBackOnFailure() throws {
        let database = try RuntimeDatabase(location: location())
        try database.write { try $0.execute(sql: "CREATE TABLE sentinel (value INTEGER UNIQUE)") }
        XCTAssertThrowsError(try database.write { db in
            try db.execute(sql: "INSERT INTO sentinel VALUES (1)")
            try db.execute(sql: "INSERT INTO sentinel VALUES (1)")
        })
        XCTAssertEqual(try database.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM sentinel") }, 0)
    }

    func testDirectoryFailureThrowsWithoutVolatileFallback() throws {
        let location = try location()
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let blocker = location.directory.appendingPathComponent("file")
        try Data("blocker".utf8).write(to: blocker)
        XCTAssertThrowsError(try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: blocker.appendingPathComponent("child")))) { error in
            guard case RuntimeDatabaseError.couldNotCreateDirectory = error else {
                return XCTFail("Expected directory failure, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: blocker), Data("blocker".utf8))
    }

    func testUnopenableDatabaseThrowsWithoutReplacement() throws {
        let location = try location()
        try FileManager.default.createDirectory(at: location.databaseURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try RuntimeDatabase(location: location))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.databaseURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCheckpointPreservesThreeSQLiteValues() throws {
        let database = try RuntimeDatabase(location: location())
        try database.write { try $0.execute(sql: "CREATE TABLE checkpoint_test (value INTEGER)") }
        let result = try database.checkpointWAL(mode: .passive)
        XCTAssertEqual(result.busy, 0)
        XCTAssertGreaterThanOrEqual(result.logFrames, 0)
        XCTAssertGreaterThanOrEqual(result.checkpointedFrames, 0)
        XCTAssertLessThanOrEqual(result.checkpointedFrames, result.logFrames)
        let truncated = try database.checkpointWAL(mode: .truncate)
        XCTAssertEqual(truncated, WALCheckpointResult(busy: 0, logFrames: 0, checkpointedFrames: 0))
    }
}
