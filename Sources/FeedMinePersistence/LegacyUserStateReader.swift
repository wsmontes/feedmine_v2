//
// File: LegacyUserStateReader.swift
// Module: FeedMinePersistence
//
// Responsibility:
// Read V1's `user.sqlite` — the reader's own state in the previous app — as plain records, without touching
// it. It is opened read-only: an import must never modify the database it reads.
//
// Does not own: deciding what an importable record *means* in V2 (Composition does) or writing anything into
// the V2 database (the library store does).
import Foundation
import GRDB
import FeedMineDomain

/// Which V1 `user.sqlite` generation this file is. The importer targets the shape V1's own `UserStateStore`
/// migrations (`v1_bookmarks` … `v11_user_operation`) created — the same shape `BookmarkStore` writes. An older
/// shape (the `RollbackRehearsalTests` fixture: `bookmark_list(list_id, title, position)`,
/// `source_collection(collection_id, name, source_keys)`) is recognised and reported as unsupported; it is
/// never queried with the modern columns and never crashes the upgrade.
public enum LegacyUserStateSchema: String, Sendable {
    case modern
    case unsupported
}

/// One of V1's personal feeds (`imported_source`, schema v8+): the canonical identity, the fetch address, the
/// title and V1's `enabled` flag.
public struct LegacyUserImportedSource: Hashable, Sendable {
    public let identity: String
    public let requestURL: String
    public let title: String
    public let enabled: Bool
}

/// One of V1's bookmark boxes. `isDefault` marks the one its card control put a bookmark in.
public struct LegacyUserBookmarkList: Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let position: Int
    public let isDefault: Bool
    /// V1 also stored a persistent-search flavour on a list (`search_query`/`region`/`category`). Nothing in
    /// V1's UI ever created one, so it is read and reported instead of silently becoming a V2 preset.
    public let carriesDeadPersistentSearch: Bool
}

/// One of V1's source collections, with its members in V1's own order.
public struct LegacyUserCollection: Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let position: Int
    public let memberKeys: [String]
}

/// One of V1's smart feeds: its name, order and definition payload, still encoded exactly as V1 wrote it.
public struct LegacyUserSmartFeed: Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let position: Int
    public let definitionJSON: String
}

public struct LegacyUserStateReader: Sendable {
    public let url: URL
    private let queue: DatabaseQueue

    /// Opens the file read-only. A missing file is not a failure at this boundary: the caller decides whether
    /// that means "nothing to import" (the usual case, on a device that never ran V1).
    public init(url: URL) throws {
        self.url = url
        var configuration = Configuration()
        configuration.readonly = true
        queue = try DatabaseQueue(path: url.path, configuration: configuration)
    }

    private static let requiredTables = ["bookmark_list", "source_collection"]

    /// Whether this file is a V1 user-state database at all: a table set is a better witness than a filename.
    public func isLegacyUserState() throws -> Bool {
        try queue.read { db in
            for table in Self.requiredTables {
                guard try Bool.fetchOne(db, sql: """
                    SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?)
                    """, arguments: [table]) == true else { return false }
            }
            return true
        }
    }

    /// The generation this file belongs to, decided by the columns the importer actually reads. A file with the
    /// tables but not these columns is reported, never queried with assumptions it does not satisfy.
    public func schemaVariant() throws -> LegacyUserStateSchema {
        try Self.wrap { try queue.read { db in
            func has(_ table: String, _ columns: [String]) throws -> Bool {
                let present = Set(try db.columns(in: table).map(\.name))
                return columns.allSatisfy { present.contains($0) }
            }
            let modern = try has("bookmark_list", ["id", "name", "sort_order", "is_default", "search_query"])
                && has("bookmark_item", ["list_id", "item_id", "added_at"])
                && has("source_collection", ["id", "name", "sort_order"])
                && has("source_collection_member", ["collection_id", "source_url"])
            return modern ? .modern : .unsupported
        } }
    }

    /// V1's personal feeds (`imported_source`). An older V1 generation had no such table, which is not a
    /// failure; a table whose columns cannot be read is reported by the import instead of being guessed at.
    public func importedSources() throws -> [LegacyUserImportedSource] {
        try Self.wrap { try queue.read { db in
            guard try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'imported_source')
                """) == true else { return [] }
            let present = Set(try db.columns(in: "imported_source").map(\.name))
            guard present.contains("request_url"), present.contains("title") else { return [] }
            let identity = present.contains("source_identity") ? "source_identity" : "NULL"
            let enabled = present.contains("enabled") ? "enabled" : "1"
            return try Row.fetchAll(db, sql: """
                SELECT \(identity) AS source_identity, request_url, title, \(enabled) AS enabled
                FROM imported_source ORDER BY id
                """).map { row in
                let requestURL: String = row["request_url"]
                let storedIdentity: String? = row["source_identity"]
                return LegacyUserImportedSource(
                    identity: storedIdentity.flatMap { $0.isEmpty ? nil : $0 } ?? FeedAddress.identity(requestURL),
                    requestURL: requestURL,
                    title: row["title"],
                    enabled: (row["enabled"] as Int64) != 0)
            }
        } }
    }

    /// How many rows `imported_source` holds, so an unreadable row can be reported instead of disappearing.
    public func importedSourceCount() throws -> Int {
        try Self.wrap { try queue.read { db in
            guard try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'imported_source')
                """) == true else { return 0 }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM imported_source") ?? 0
        } }
    }

    public func bookmarkLists() throws -> [LegacyUserBookmarkList] {
        try Self.wrap { try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, sort_order, is_default, search_query FROM bookmark_list ORDER BY sort_order, id
                """).map { row in
                LegacyUserBookmarkList(id: row["id"], name: row["name"], position: row["sort_order"],
                    isDefault: (row["is_default"] as Int64) != 0,
                    carriesDeadPersistentSearch: (row["search_query"] as String?) != nil)
            }
        } }
    }

    public func collections() throws -> [LegacyUserCollection] {
        try Self.wrap { try queue.read { db in
            // Schema v7_4 stores both the canonical `source_identity` and the fetch `source_url`. The identity is
            // what V2 memberships and the selection use; an older member table has only the URL, which is
            // canonicalised through the one domain function so a fetch URL never becomes a key by accident.
            let columns = Set(try db.columns(in: "source_collection_member").map(\.name))
            let carriesIdentity = columns.contains("source_identity")
            let selected = carriesIdentity ? "source_identity" : "source_url"
            return try Row.fetchAll(db, sql: "SELECT id, name, sort_order FROM source_collection ORDER BY sort_order, id")
                .map { row in
                    let id: Int64 = row["id"]
                    let raw = try String.fetchAll(db, sql: """
                        SELECT \(selected) FROM source_collection_member
                        WHERE collection_id = ? ORDER BY sort_order, \(selected)
                        """, arguments: [id])
                    let keys = raw.map { carriesIdentity ? $0 : FeedAddress.identity($0) }
                    return LegacyUserCollection(id: id, name: row["name"], position: row["sort_order"], memberKeys: keys)
                }
        } }
    }

    public func smartFeeds() throws -> [LegacyUserSmartFeed] {
        try Self.wrap { try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, definition_json, sort_order FROM smart_feed ORDER BY sort_order, id")
                .map { row in
                    LegacyUserSmartFeed(id: row["id"], name: row["name"], position: row["sort_order"],
                        definitionJSON: row["definition_json"])
                }
        } }
    }

    /// How many curated feeds V1 had. They are deliberately not imported (T11 owns curation, and V1's
    /// definitions carry profile weights and recipes V2's filter cannot express), but the import states how
    /// many it left behind instead of staying silent about them.
    public func curatedFeedCount() throws -> Int {
        try Self.wrap { try queue.read { db in
            guard try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'curated_feed')
                """) == true else { return 0 }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM curated_feed") ?? 0
        } }
    }

    /// How many items each V1 box holds — read only so the import can *state* what it could not carry over,
    /// instead of pretending the boxes were empty in V1 too.
    public func bookmarkItemCounts() throws -> [Int64: Int] {
        try Self.wrap { try queue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT list_id, COUNT(*) AS total FROM bookmark_item GROUP BY list_id")
            return Dictionary(uniqueKeysWithValues: rows.map { row in (row["list_id"] as Int64, row["total"] as Int) })
        } }
    }

    private enum ReaderError: Error { case corrupt(String) }

    private static func wrap<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch let error as ReaderError { throw error }
        catch { throw ReaderError.corrupt(String(describing: error)) }
    }
}
