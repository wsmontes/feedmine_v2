// Owns: durable reader source selection and active logical context; never acquisition.
import Foundation
import GRDB
import FeedMineDomain

public enum ReaderPreferencesError: Error { case invalidSelection, invalidRecord, missingPreferences, versionOverflow }

public struct ReaderPreferencesStore: Sendable {
    public struct Record: Hashable, Sendable {
        public let sourceKeys: [String]
        public let selectionVersion: UInt64
        /// T6: the active *identity* — surface, preset, filter and search scope. The column has always held
        /// JSON and a legacy payload (a bare `FeedContextRequest`) decodes into the key's default surface, so
        /// no migration is needed and a pre-T6 row keeps working.
        public let activeContextKey: ContextKey
        /// V1's `filterAutoExpire` + `filterSetAt`: when the overlay selection was set, and whether the
        /// four-hour rule is on. A deadline is not identity, so it does not live in the key.
        public let filterExpiry: ReaderFilterExpiry

        /// The surface of the active identity; the convenience older callers used.
        public var activeContext: FeedContextRequest { activeContextKey.request }
    }
    private let database: RuntimeDatabase
    public init(database: RuntimeDatabase) { self.database = database }
    public func load() throws -> Record? { try database.read { try Self.read($0) } }
    public func initialize(sourceKeys: [String]) throws -> Record {
        try Self.validate(sourceKeys)
        return try database.write { db in
            if let current = try Self.read(db) { return current }
            let initial = Record(sourceKeys: sourceKeys, selectionVersion: 2,
                activeContextKey: ContextKey(request: .main),
                // V1 shipped auto-expiry on; a fresh database says so explicitly rather than relying on the
                // column default.
                filterExpiry: ReaderFilterExpiry(isEnabled: true, startsAt: nil))
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
            let updated = Record(sourceKeys: keys, selectionVersion: current.selectionVersion + 1,
                activeContextKey: current.activeContextKey, filterExpiry: current.filterExpiry)
            try Self.save(updated, in: db)
            return updated
        }
    }
    /// Saves the expiry record of the overlay selection (V1 wrote it beside the filter itself).
    public func setFilterExpiry(_ expiry: ReaderFilterExpiry) throws -> Record {
        try database.write { db in
            guard let current = try Self.read(db) else { throw ReaderPreferencesError.missingPreferences }
            let updated = Record(sourceKeys: current.sourceKeys, selectionVersion: current.selectionVersion,
                activeContextKey: current.activeContextKey, filterExpiry: expiry)
            try Self.save(updated, in: db)
            return updated
        }
    }

    /// Saves the active identity. `setContext(_ request:)` stays as the plain-surface convenience.
    public func setContext(_ key: ContextKey) throws -> Record {
        try database.write { db in
            guard let current = try Self.read(db) else { throw ReaderPreferencesError.missingPreferences }
            let updated = Record(sourceKeys: current.sourceKeys, selectionVersion: current.selectionVersion,
                activeContextKey: key, filterExpiry: current.filterExpiry)
            try Self.save(updated, in: db)
            return updated
        }
    }

    public func setContext(_ context: FeedContextRequest) throws -> Record {
        try setContext(ContextKey(request: context))
    }
    private static func validate(_ keys: [String]) throws {
        guard !keys.isEmpty, Set(keys).count == keys.count, keys.allSatisfy({ !$0.isEmpty }) else { throw ReaderPreferencesError.invalidSelection }
    }
    private static func read(_ db: Database) throws -> Record? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM reader_preferences WHERE singleton_id = 1") else { return nil }
        let keys = try JSONDecoder().decode([String].self, from: row["source_keys"] as Data)
        // Two shapes live in this column: a pre-T6 row stored the bare `FeedContextRequest`, and a row written
        // since T6 stores the whole key. The bare request was the default surface of that request.
        let payload = row["active_context"] as Data
        let context: ContextKey
        if let key = try? JSONDecoder().decode(ContextKey.self, from: payload) {
            context = key
        } else {
            context = ContextKey(request: try JSONDecoder().decode(FeedContextRequest.self, from: payload))
        }
        let version: Int64 = row["selection_version"]
        guard version >= 2 else { throw ReaderPreferencesError.invalidRecord }
        try validate(keys)
        let autoExpire: Int64 = row["filter_auto_expire"] as Int64? ?? 1
        let setAt: Double? = row["filter_set_at"]
        return Record(sourceKeys: keys, selectionVersion: UInt64(version), activeContextKey: context,
            filterExpiry: ReaderFilterExpiry(isEnabled: autoExpire != 0,
                startsAt: setAt.map(Date.init(timeIntervalSince1970:))))
    }
    private static func save(_ value: Record, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO reader_preferences (singleton_id, source_keys, selection_version, active_context,
                filter_auto_expire, filter_set_at) VALUES (1, ?, ?, ?, ?, ?)
            ON CONFLICT(singleton_id) DO UPDATE SET source_keys = excluded.source_keys,
                selection_version = excluded.selection_version, active_context = excluded.active_context,
                filter_auto_expire = excluded.filter_auto_expire, filter_set_at = excluded.filter_set_at
            """, arguments: [try JSONEncoder().encode(value.sourceKeys), Int64(value.selectionVersion),
                try JSONEncoder().encode(value.activeContextKey), value.filterExpiry.isEnabled ? 1 : 0,
                value.filterExpiry.startsAt?.timeIntervalSince1970])
    }
}
