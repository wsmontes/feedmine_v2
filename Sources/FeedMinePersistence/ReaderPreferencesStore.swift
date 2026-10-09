// Owns: durable reader source selection and active logical context; never acquisition.
import Foundation
import GRDB
import FeedMineDomain

public enum ReaderPreferencesError: Error { case invalidSelection, invalidRecord, missingPreferences, versionOverflow }

public struct ReaderPreferencesStore: Sendable {
    public struct Record: Hashable, Sendable {
        public let sourceKeys: [String]
        public let selectionVersion: UInt64
        public let activeContext: FeedContextRequest
    }
    private let database: RuntimeDatabase
    public init(database: RuntimeDatabase) { self.database = database }
    public func load() throws -> Record? { try database.read { try Self.read($0) } }
    public func initialize(sourceKeys: [String]) throws -> Record {
        try Self.validate(sourceKeys)
        return try database.write { db in
            if let current = try Self.read(db) { return current }
            let initial = Record(sourceKeys: sourceKeys, selectionVersion: 2, activeContext: .main)
            try Self.save(initial, in: db)
            return initial
        }
    }
    public func updateSources(_ keys: [String]) throws -> Record {
        try Self.validate(keys)
        return try database.write { db in
            guard let current = try Self.read(db) else { throw ReaderPreferencesError.missingPreferences }
            // OMP C4: a selection is a set; reordering the same sources is not a new selection and
            // must not bump the version that fences restore (the reader would lose the position).
            if Set(keys) == Set(current.sourceKeys) { return current }
            guard current.selectionVersion < UInt64(Int64.max) else { throw ReaderPreferencesError.versionOverflow }
            let updated = Record(sourceKeys: keys, selectionVersion: current.selectionVersion + 1, activeContext: current.activeContext)
            try Self.save(updated, in: db)
            return updated
        }
    }
    public func setContext(_ context: FeedContextRequest) throws -> Record {
        try database.write { db in
            guard let current = try Self.read(db) else { throw ReaderPreferencesError.missingPreferences }
            let updated = Record(sourceKeys: current.sourceKeys, selectionVersion: current.selectionVersion, activeContext: context)
            try Self.save(updated, in: db)
            return updated
        }
    }
    private static func validate(_ keys: [String]) throws {
        guard !keys.isEmpty, Set(keys).count == keys.count, keys.allSatisfy({ !$0.isEmpty }) else { throw ReaderPreferencesError.invalidSelection }
    }
    private static func read(_ db: Database) throws -> Record? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM reader_preferences WHERE singleton_id = 1") else { return nil }
        let keys = try JSONDecoder().decode([String].self, from: row["source_keys"] as Data)
        let context = try JSONDecoder().decode(FeedContextRequest.self, from: row["active_context"] as Data)
        let version: Int64 = row["selection_version"]
        guard version >= 2 else { throw ReaderPreferencesError.invalidRecord }
        try validate(keys)
        return Record(sourceKeys: keys, selectionVersion: UInt64(version), activeContext: context)
    }
    private static func save(_ value: Record, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO reader_preferences (singleton_id, source_keys, selection_version, active_context) VALUES (1, ?, ?, ?)
            ON CONFLICT(singleton_id) DO UPDATE SET source_keys = excluded.source_keys,
                selection_version = excluded.selection_version, active_context = excluded.active_context
            """, arguments: [try JSONEncoder().encode(value.sourceKeys), Int64(value.selectionVersion), try JSONEncoder().encode(value.activeContext)])
    }
}
