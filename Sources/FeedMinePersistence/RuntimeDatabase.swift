//
// File: RuntimeDatabase.swift
// Module: FeedMinePersistence
//
// Responsibility:
//   Own the physical non-replaceable runtime.sqlite connection lifecycle.
//
// Owns:
//   Location, directory creation, DatabasePool configuration/opening, migration
//   application, internal transactions, factual errors and explicit WAL checkpoints.
//
// Does not own:
//   Domain CRUD/schema, catalog lifecycle, assets, retention, backup, retries,
//   degraded Runtime/UI decisions or any volatile fallback.
//
// Allowed dependencies:
//   Foundation, GRDB and FeedMineDomain; GRDB access stays inside Persistence.
//
// Architectural invariants:
//   INV-11, INV-12; runtime.sqlite is non-replaceable semantic state.
//   Database unavailable is not empty database; failure is not first launch.
//
// Planned public surface:
//   RuntimeDatabaseLocation, RuntimeDatabaseError, RuntimeDatabase,
//   WALCheckpointMode and WALCheckpointResult; no public GRDB objects.
//
// Status:
//   Phase 2A runtime persistence lifecycle implementation; no domain tables.
//

import Foundation
import GRDB

public struct RuntimeDatabaseLocation: Hashable, Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var databaseURL: URL {
        directory.appendingPathComponent("runtime.sqlite")
    }

    public static func applicationSupport(_ applicationSupportDirectory: URL) -> Self {
        Self(directory: applicationSupportDirectory.appendingPathComponent("FeedMine", isDirectory: true))
    }
}

/// Factual failures. SQLite failures preserve the extended result code and message.
public enum RuntimeDatabaseError: Error, Sendable {
    case couldNotCreateDirectory(directory: URL, message: String)
    case open(databaseURL: URL, message: String)
    case storage(resultCode: Int32, message: String)
}

/// Explicit modes, not an automatic maintenance or checkpoint policy.
public enum WALCheckpointMode: String, Sendable {
    case passive
    case full
    case restart
    case truncate
}

/// Exact PRAGMA wal_checkpoint columns; busy is SQLite's integer indicator, not success.
public struct WALCheckpointResult: Sendable, Equatable {
    public let busy: Int
    public let logFrames: Int
    public let checkpointedFrames: Int

    public init(busy: Int, logFrames: Int, checkpointedFrames: Int) {
        self.busy = busy
        self.logFrames = logFrames
        self.checkpointedFrames = checkpointedFrames
    }
}

/// Checked Sendable: immutable wrapper around GRDB's thread-safe Sendable DatabasePool.
/// The pool serializes writes and protects reader connections; Database never escapes
/// the scoped internal access closures. No fallback or automatic rebuild exists.
public final class RuntimeDatabase: Sendable {
    private let pool: DatabasePool

    public convenience init(
        location: RuntimeDatabaseLocation,
        fileManager: FileManager = .default
    ) throws {
        try self.init(location: location, migrator: RuntimeMigrations.current, fileManager: fileManager)
    }

    /// Internal injection supports migration tests without exposing GRDB to consumers.
    init(
        location: RuntimeDatabaseLocation,
        migrator: DatabaseMigrator,
        fileManager: FileManager = .default
    ) throws {
        do {
            try fileManager.createDirectory(at: location.directory, withIntermediateDirectories: true)
        } catch {
            throw RuntimeDatabaseError.couldNotCreateDirectory(directory: location.directory, message: error.localizedDescription)
        }

        var configuration = Configuration()
        // GRDB applies this to writer and reader connections. No duplicate PRAGMA setup.
        configuration.foreignKeysEnabled = true
        // DatabasePool's default persistent journal mode establishes WAL.
        // Reader count and busy behavior use GRDB defaults, not product tuning.
        do {
            let pool = try DatabasePool(path: location.databaseURL.path, configuration: configuration)
            var nonErasingMigrator = migrator
            // Enforce non-erasure even for an internally supplied test migrator.
            nonErasingMigrator.eraseDatabaseOnSchemaChange = false
            try nonErasingMigrator.migrate(pool)
            self.pool = pool
        } catch let error as DatabaseError {
            throw RuntimeDatabaseError.storage(resultCode: error.extendedResultCode.rawValue, message: error.message ?? error.description)
        } catch {
            throw RuntimeDatabaseError.open(databaseURL: location.databaseURL, message: error.localizedDescription)
        }
    }

    /// Persistence-owned stores use bounded read snapshots, not public SQL access.
    func read<T: Sendable>(_ body: @Sendable (Database) throws -> T) throws -> T {
        do {
            return try pool.read(body)
        } catch let error as DatabaseError {
            throw RuntimeDatabaseError.storage(resultCode: error.extendedResultCode.rawValue, message: error.message ?? error.description)
        }
    }

    /// GRDB commits the transaction on success and rolls it back on thrown errors.
    func write<T: Sendable>(_ body: @Sendable (Database) throws -> T) throws -> T {
        do {
            return try pool.write(body)
        } catch let error as DatabaseError {
            throw RuntimeDatabaseError.storage(resultCode: error.extendedResultCode.rawValue, message: error.message ?? error.description)
        }
    }

    /// Checkpoint explicitly outside a transaction; never schedule automatic maintenance.
    public func checkpointWAL(mode: WALCheckpointMode) throws -> WALCheckpointResult {
        do {
            return try pool.writeWithoutTransaction { db in
                guard let row = try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(\(mode.rawValue))") else {
                    throw RuntimeDatabaseError.storage(resultCode: 1, message: "SQLite returned no WAL checkpoint result.")
                }
                return WALCheckpointResult(busy: row[0], logFrames: row[1], checkpointedFrames: row[2])
            }
        } catch let error as DatabaseError {
            throw RuntimeDatabaseError.storage(resultCode: error.extendedResultCode.rawValue, message: error.message ?? error.description)
        }
    }
}
