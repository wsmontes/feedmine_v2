//
// File: RuntimeDatabaseHardeningTests.swift
// Module: FeedMinePersistenceTests
//
// Responsibility:
//   Verify the two lifecycle properties the database audit asked for: a competing writer waits for the
//   lock instead of failing at once, and a database written by a newer build is refused rather than
//   opened as if it were current.
//
// Owns:
//   Writer-contention and downgrade-refusal behaviour of RuntimeDatabase.
//
// Does not own:
//   Production schema, retry policy, backup or any volatile fallback.
//
// Allowed dependencies:
//   FeedMinePersistence, Foundation, XCTest and GRDB for SQLite-specific setup.
//
// Architectural invariants:
//   INV-11, INV-12; runtime.sqlite is non-replaceable semantic state, and a transient SQLITE_BUSY
//   must not surface as a user-visible failure while the lock is still reachable.
//

import Foundation
import XCTest
import GRDB
@testable import FeedMinePersistence

final class RuntimeDatabaseHardeningTests: XCTestCase {
    private func location() -> RuntimeDatabaseLocation {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return RuntimeDatabaseLocation(directory: directory)
    }

    /// Confines a value written on one queue and read after a join, so the test expresses the
    /// concurrency it needs without mutating a captured `var` across queues.
    private final class Box<Value>: @unchecked Sendable {
        var value: Value?
        init() {}
    }

    /// Two independently opened pools on the same file: the second writer must wait for the first to
    /// commit. With an immediate-error busy mode it fails with SQLITE_BUSY while the lock is held, which
    /// is a transient condition presented as a failure.
    func testCompetingWriterWaitsForTheLockInsteadOfFailingImmediately() throws {
        let location = location()
        let first = try RuntimeDatabase(location: location)
        let second = try RuntimeDatabase(location: location)
        try first.write { db in try db.execute(sql: "CREATE TABLE contention (value TEXT)") }

        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let holder = DispatchQueue(label: "feedmine.test.holder")
        let holdError = Box<Error>()
        holder.async {
            do {
                try first.write { db in
                    try db.execute(sql: "INSERT INTO contention VALUES ('first')")
                    started.signal()
                    _ = release.wait(timeout: .now() + 10)
                }
            } catch { holdError.value = error }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 5), .success, "the first writer never acquired the lock")

        let secondError = Box<Error>()
        let contender = DispatchQueue(label: "feedmine.test.contender")
        contender.async {
            do { try second.write { db in try db.execute(sql: "INSERT INTO contention VALUES ('second')") } } catch { secondError.value = error }
        }
        // The contender is now inside SQLite's busy handling; release the lock well before any timeout.
        Thread.sleep(forTimeInterval: 0.5)
        release.signal()
        holder.sync {}
        contender.sync {}

        XCTAssertNil(holdError.value)
        XCTAssertNil(secondError.value, "a competing writer must wait for the lock, not fail with SQLITE_BUSY")
        XCTAssertEqual(try first.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM contention") }, 2)
    }

    /// A file carrying an applied migration this build does not register was written by newer code.
    /// GRDB ignores unknown identifiers, so opening successfully would present newer state as current.
    /// The error's identity is pinned by `testUnknownAppliedMigrationIsRefusedByItsOwnCase` once the
    /// refusal exists; this test states the behaviour and therefore compiles before the fix.
    func testDatabaseWithUnknownAppliedMigrationIsRefused() throws {
        let location = location()
        _ = try RuntimeDatabase(location: location)
        let raw = try DatabaseQueue(path: location.databaseURL.path)
        try raw.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('future-build-v9')")
        }
        XCTAssertThrowsError(try RuntimeDatabase(location: location), "a database written by a newer build must be refused")
    }
}
