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
import CryptoKit

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
    private let queue: DatabaseQueue
    private let userURL: URL

    /// Opens the file read-only. A missing file is not a failure at this boundary: the caller decides whether
    /// that means "nothing to import" (the usual case, on a device that never ran V1).
    public init(url: URL) throws {
        var configuration = Configuration()
        configuration.readonly = true
        userURL = url
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
            try Row.fetchAll(db, sql: "SELECT id, name, sort_order FROM source_collection ORDER BY sort_order, id")
                .map { row in
                    let id: Int64 = row["id"]
                    let keys = try String.fetchAll(db, sql: """
                        SELECT source_url FROM source_collection_member WHERE collection_id = ? ORDER BY sort_order, source_url
                        """, arguments: [id])
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


// MIG-V1V2-B: identities remain in the legacy namespace. A snapshot does NOT name a published card.
public struct LegacyPersonalBookmark: Hashable, Sendable {
    public let listID: Int64
    public let itemID: String
    public let addedAt: Double
    public let position: Int
    public let title: String?
    public let url: String?
    public let sourceTitle: String?
    public let sourceURL: String?
    public let excerpt: String?
    public let mediaURL: String?
    public let authoredAt: Double?
    public let capturedAt: Double?
    public let hasSnapshot: Bool
}

public struct LegacyPersonalCollectionMember: Hashable, Sendable {
    public let collectionID: Int64
    public let identity: String?
    public let requestURL: String
    public let title: String
    public let mediaKind: String
    public let position: Int
    public let addedAt: Double
}

public struct LegacyPersonalImportedSource: Hashable, Sendable {
    public let identity: String
    public let requestURL: String
    public let title: String
    public let enabled: Bool
    public let addedAt: Double
}

public struct LegacyPersonalArchiveRecord: Hashable, Sendable {
    public let category: String
    public let key: String
    public let payloadJSON: String
    public let status: String
    public init(category: String, key: String, payloadJSON: String, status: String = "recoverable") {
        self.category = category; self.key = key; self.payloadJSON = payloadJSON; self.status = status
    }
}

public struct LegacyPersonalState: Sendable {
    public let lists: [LegacyUserBookmarkList]
    public let collections: [LegacyUserCollection]
    public let collectionMembers: [LegacyPersonalCollectionMember]
    public let smartFeeds: [LegacyUserSmartFeed]
    public let bookmarks: [LegacyPersonalBookmark]
    public let importedSources: [LegacyPersonalImportedSource]
    public let archived: [LegacyPersonalArchiveRecord]
    public let fingerprint: String
}

extension LegacyUserStateReader {
    /// Reads all V1 personal facts as one consistent WAL snapshot. Missing optional tables indicate
    /// a historical schema, not an empty/invalid V1. V1 is never migrated or checkpointed here.
    public func personalState() throws -> LegacyPersonalState {
        try Self.wrap {
            try queue.read { db in
                guard try db.tableExists("bookmark_list"),
                    try db.tableExists("source_collection"),
                    try db.tableExists("bookmark_item"),
                    try db.tableExists("source_collection_member") else {
                    throw ReaderError.corrupt("Not a V1 user-state schema")
                }
                let lists = try Row.fetchAll(db, sql: """
                    SELECT id, name, sort_order, is_default, search_query
                    FROM bookmark_list ORDER BY sort_order, id
                    """).map { row in
                    LegacyUserBookmarkList(id: row["id"], name: row["name"],
                        position: row["sort_order"], isDefault: (row["is_default"] as Int64) != 0,
                        carriesDeadPersistentSearch: (row["search_query"] as String?) != nil)
                }
                let collections = try Row.fetchAll(db, sql: """
                    SELECT id, name, sort_order FROM source_collection ORDER BY sort_order, id
                    """).map { row in
                    let id: Int64 = row["id"]
                    let keys = try String.fetchAll(db, sql: """
                        SELECT source_url FROM source_collection_member WHERE collection_id = ?
                        ORDER BY sort_order, source_url
                        """, arguments: [id])
                    return LegacyUserCollection(id: id, name: row["name"],
                        position: row["sort_order"], memberKeys: keys)
                }
                let smartFeeds: [LegacyUserSmartFeed]
                if try db.tableExists("smart_feed") {
                    smartFeeds = try Row.fetchAll(db, sql: """
                        SELECT id, name, definition_json, sort_order FROM smart_feed ORDER BY sort_order, id
                        """).map { row in
                        LegacyUserSmartFeed(id: row["id"], name: row["name"],
                            position: row["sort_order"], definitionJSON: row["definition_json"])
                    }
                } else { smartFeeds = [] }
                let memberColumns = try db.columns(in: "source_collection_member").map(\.name)
                let identityColumn = memberColumns.contains("source_identity")
                    ? "source_identity" : "NULL AS source_identity"
                let members = try Row.fetchAll(db, sql: """
                    SELECT collection_id, \(identityColumn), source_url, title_snapshot, media_kind,
                        sort_order, added_at FROM source_collection_member
                    ORDER BY collection_id, sort_order, source_url
                    """).map { row in
                    LegacyPersonalCollectionMember(collectionID: row["collection_id"],
                        identity: row["source_identity"], requestURL: row["source_url"],
                        title: row["title_snapshot"], mediaKind: row["media_kind"],
                        position: row["sort_order"], addedAt: Double(row["added_at"] as Int64))
                }
                let hasSnapshots = try db.tableExists("bookmark_snapshot")
                let join = hasSnapshots
                    ? """
                      s.title, s.url, s.source_title, s.source_url, s.excerpt, s.media_url,
                      s.authored_at, s.captured_at,
                      CASE WHEN s.item_id IS NOT NULL THEN 1 ELSE 0 END AS has_snapshot
                      """
                    : """
                      NULL AS title, NULL AS url, NULL AS source_title, NULL AS source_url,
                      NULL AS excerpt, NULL AS media_url, NULL AS authored_at, NULL AS captured_at,
                       0 AS has_snapshot
                      """
                let bookmarks = try Row.fetchAll(db, sql: """
                    SELECT b.list_id, b.item_id, b.added_at, b.sort_order, \(join)
                    FROM bookmark_item b
                    \(hasSnapshots ? "LEFT JOIN bookmark_snapshot s ON s.list_id = b.list_id AND s.item_id = b.item_id" : "")
                    ORDER BY b.list_id, b.sort_order, b.added_at, b.item_id
                    """).map { row in
                    LegacyPersonalBookmark(listID: row["list_id"], itemID: row["item_id"],
                        addedAt: Double(row["added_at"] as Int64), position: row["sort_order"],
                        title: row["title"], url: row["url"], sourceTitle: row["source_title"],
                        sourceURL: row["source_url"], excerpt: row["excerpt"], mediaURL: row["media_url"],
                        authoredAt: (row["authored_at"] as Double?),
                        capturedAt: (row["captured_at"] as Double?),
                         hasSnapshot: (row["has_snapshot"] as Int64) != 0)
                }
                let imported: [LegacyPersonalImportedSource]
                if try db.tableExists("imported_source") {
                    imported = try Row.fetchAll(db, sql: """
                        SELECT source_identity, request_url, title, enabled, added_at FROM imported_source
                        ORDER BY id
                        """).map { row in
                        LegacyPersonalImportedSource(identity: row["source_identity"],
                            requestURL: row["request_url"], title: row["title"],
                            enabled: (row["enabled"] as Int64) != 0,
                            addedAt: Double(row["added_at"] as Int64))
                    }
                } else { imported = [] }

                // Cold provenance: keep complete V1 rows (including recipe, journal payload and
                // source metadata), rather than declaring unrepresentable fields migrated.
                let archivedTables = [
                    "bookmark_list", "source_collection", "source_collection_member", "smart_feed",
                    "curated_feed", "imported_source", "user_operation", "user_metadata",
                     "bookmark_snapshot"
                ]
                var archived: [LegacyPersonalArchiveRecord] = []
                for table in archivedTables {
                    if try db.tableExists(table) {
                        archived += try Self.archive(table: table, in: db)
                    }
                }
                // The content database was never the bookmark authority. It may, however,
                // contain source_history_access. Read it only if present, without creating it.
                let contentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("feedmine.sqlite")
                if FileManager.default.fileExists(atPath: contentURL.path) {
                    var config = Configuration()
                    config.readonly = true
                    let content = try DatabaseQueue(path: contentURL.path, configuration: config)
                    archived += try content.read { cdb in
                        try cdb.tableExists("source_history_access")
                            ? Self.archive(table: "source_history_access", in: cdb) : []
                    }
                }
                let evidence = archived.sorted {
                    ($0.category, $0.key) < ($1.category, $1.key)
                }.map { "\($0.category)|\($0.key)|\($0.payloadJSON)" }.joined(separator: "\n")
                let bookmarkIdentity = bookmarks.map {
                    "\($0.listID)|\($0.itemID)|\($0.addedAt)|\($0.position)|\($0.hasSnapshot)"
                }.joined(separator: "\n")
                let fingerprint = SHA256.hash(data: Data((evidence + bookmarkIdentity).utf8))
                    .map { String(format: "%02x", $0) }.joined()
                return LegacyPersonalState(lists: lists, collections: collections,
                    collectionMembers: members, smartFeeds: smartFeeds, bookmarks: bookmarks,
                    importedSources: imported, archived: archived, fingerprint: fingerprint)
            }
        }
    }

    private static func archive(table: String, in db: Database) throws -> [LegacyPersonalArchiveRecord] {
        let columns = try db.columns(in: table).map(\.name)
        // Names are discovered from SQLite and always double-quoted; data never interpolates SQL.
        let arguments = columns.map { name in
            "'\(name.replacingOccurrences(of: "'", with: "''"))', \"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
        }.joined(separator: ", ")
        let rows = try String.fetchAll(db, sql: """
            SELECT json_object(\(arguments)) FROM "\(table)" ORDER BY rowid
            """)
        return rows.enumerated().map { offset, payload in
            LegacyPersonalArchiveRecord(category: table, key: "\(offset)",
                payloadJSON: payload, status: "recoverable")
        }
    }
}
