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

    /// Whether the volume holding `url` can tell two spellings apart. True (the safe, isolating answer) when the
    /// question cannot be answered: only a volume that *says* it is case-insensitive may collapse the names.
    static func volumeIsCaseSensitive(_ url: URL, fileManager: FileManager = .default) -> Bool {
        var probe = url
        while probe.path != "/" {
            if let values = try? probe.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]),
                let insensitive = values.volumeSupportsCaseSensitiveNames {
                return insensitive
            }
            probe = probe.deletingLastPathComponent()
        }
        return true
    }

    /// The existing sibling whose name differs only by case, if any.
    static func caseVariantDirectory(of directory: URL, fileManager: FileManager = .default) -> URL? {
        let parent = directory.deletingLastPathComponent()
        let name = directory.lastPathComponent
        guard let entries = try? fileManager.contentsOfDirectory(at: parent,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        return entries.first { $0.lastPathComponent.lowercased() == name.lowercased() }
    }

    public convenience init(
        location: RuntimeDatabaseLocation,
        fileManager: FileManager = .default,
        sqlTrace: (@Sendable (String) -> Void)? = nil
    ) throws {
        try self.init(location: location, migrator: RuntimeMigrations.current,
            fileManager: fileManager, sqlTrace: sqlTrace)
    }

    /// Internal injection supports migration tests without exposing GRDB to consumers.
    init(
        location: RuntimeDatabaseLocation,
        migrator: DatabaseMigrator,
        fileManager: FileManager = .default,
        sqlTrace: (@Sendable (String) -> Void)? = nil
    ) throws {
        // The **exact** spelling wins whenever it can exist: on a case-sensitive volume (the iPhone's) `Feedmine`
        // and `FeedMine` are genuinely distinct directories, and V2's store must never be opened inside V1's
        // data directory. Only when creation fails *and* the volume cannot tell the spellings apart is the
        // existing variant reused — that failure is the case-collision (measured 2026-10-20 in the D7-A
        // rehearsal: NSCocoaErrorDomain 512 / POSIX 5 EIO), and there the two names are one directory anyway.
        var directory = location.directory
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            if !Self.volumeIsCaseSensitive(directory, fileManager: fileManager),
                let variant = Self.caseVariantDirectory(of: directory, fileManager: fileManager) {
                directory = variant
            } else {
                throw RuntimeDatabaseError.couldNotCreateDirectory(directory: directory,
                    message: error.localizedDescription)
            }
        }
        let databaseURL = directory.appendingPathComponent("runtime.sqlite")

        var configuration = Configuration()
        // GRDB applies this to writer and reader connections. No duplicate PRAGMA setup.
        configuration.foreignKeysEnabled = true
        // Explicit optional observer for tests that need to prove query counts; nil in product paths and no
        // effect on results or scheduling.
        if let sqlTrace {
            configuration.prepareDatabase { db in
                db.trace { event in sqlTrace(event.expandedDescription) }
            }
        }
        // DatabasePool's default persistent journal mode establishes WAL.
        // Reader count and busy behavior use GRDB defaults, not product tuning.
        do {
            let pool = try DatabasePool(path: databaseURL.path, configuration: configuration)
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
