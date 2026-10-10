//
// File: ReaderLibraryStore.swift
// Module: FeedMinePersistence
//
// Responsibility:
// The reader's own library in storage: bookmark boxes, source collections and saved presets. Every write is
// one GRDB transaction, so a refused change leaves no partial membership behind, and every read hands out
// Domain values — no row, no integer id and no SQL crosses this boundary.
//
// Does not own: acquisition, publication, the active context (Composition) or any layout (UI). Deleting a
// collection never deletes a source or an article: memberships are its own table and are cascaded by the
// collection row alone.
import Foundation
import GRDB
import FeedMineDomain

public enum ReaderLibraryError: Error, Equatable, Sendable {
    case missingLibraryItem
    case invalidName
    case cardIdentityMismatch
}

public struct ReaderLibraryStore: Sendable {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    // MARK: - Bookmark boxes

    /// Every box in the reader's own order. The default box is created by the migration, so this is never
    /// empty in a migrated database.
    public func bookmarkLists() throws -> [ReaderBookmarkList] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, position FROM reader_bookmark_lists ORDER BY position, id")
                .map { ReaderBookmarkList(id: $0["id"], name: $0["name"], position: $0["position"]) }
        }
    }

    @discardableResult
    public func createBookmarkList(named rawName: String) throws -> ReaderBookmarkList {
        guard let name = ReaderLibraryRules.normalizedName(rawName) else { throw ReaderLibraryError.invalidName }
        return try database.write { db in
            let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM reader_bookmark_lists") ?? 0
            let list = ReaderBookmarkList(id: Self.mintID(), name: name, position: position)
            try db.execute(sql: "INSERT INTO reader_bookmark_lists (id, name, position) VALUES (?, ?, ?)",
                arguments: [list.id, list.name, list.position])
            return list
        }
    }

    @discardableResult
    public func renameBookmarkList(id: String, to rawName: String) throws -> ReaderBookmarkList {
        guard let name = ReaderLibraryRules.normalizedName(rawName) else { throw ReaderLibraryError.invalidName }
        return try database.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_bookmark_lists WHERE id = ?)",
                arguments: [id]) == true else { throw ReaderLibraryError.missingLibraryItem }
            try db.execute(sql: "UPDATE reader_bookmark_lists SET name = ? WHERE id = ?", arguments: [name, id])
            let position = try Int.fetchOne(db, sql: "SELECT position FROM reader_bookmark_lists WHERE id = ?",
                arguments: [id]) ?? 0
            return ReaderBookmarkList(id: id, name: name, position: position)
        }
    }

    /// Deletes a box and its memberships. The default box cannot be deleted: the card control needs somewhere
    /// to put a bookmark, and V1's own default list had the same role.
    @discardableResult
    public func deleteBookmarkList(id: String) throws -> Bool {
        try database.write { db in
            guard id != ReaderBookmarkList.defaultID else { return false }
            try db.execute(sql: "DELETE FROM reader_bookmark_lists WHERE id = ?", arguments: [id])
            let removed = db.changesCount > 0
            // The memberships are already gone by the foreign key's cascade; the sweep is for a database that
            // predates it and costs nothing when there is nothing to delete.
            try db.execute(sql: "DELETE FROM reader_bookmark_memberships WHERE list_id = ?", arguments: [id])
            return removed
        }
    }

    /// Applies a reorder: positions follow `ids`, and a box the reorder does not name keeps its own order.
    @discardableResult
    public func reorderBookmarkLists(_ ids: [String]) throws -> [ReaderBookmarkList] {
        try database.write { db in
            let current = try Row.fetchAll(db, sql: "SELECT id, name, position FROM reader_bookmark_lists ORDER BY position, id")
                .map { ReaderBookmarkList(id: $0["id"], name: $0["name"], position: $0["position"]) }
            let positions = ReaderLibraryRules.positions(current: current.map(\.id), reordered: ids)
            for (id, position) in positions {
                try db.execute(sql: "UPDATE reader_bookmark_lists SET position = ? WHERE id = ?", arguments: [position, id])
            }
            return current.map { ReaderBookmarkList(id: $0.id, name: $0.name, position: positions[$0.id] ?? $0.position) }
                .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
        }
    }

    /// Adds or removes one published card in one box. The card must exist as a published occurrence.
    public func setBookmarkMembership(cardID: PublicationCardID, listID: String, included: Bool, at date: Date)
        throws {
        let time = try PersistenceValueCoding.date(date, field: "added_at")
        let card = PersistenceValueCoding.uuid(cardID.rawValue)
        try database.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_bookmark_lists WHERE id = ?)",
                arguments: [listID]) == true else { throw ReaderLibraryError.missingLibraryItem }
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM published_cards WHERE id = ?)",
                arguments: [card]) == true else { throw ReaderLibraryError.cardIdentityMismatch }
            if included {
                try db.execute(sql: """
                    INSERT INTO reader_bookmark_memberships (list_id, card_id, added_at) VALUES (?, ?, ?)
                    ON CONFLICT(list_id, card_id) DO NOTHING
                    """, arguments: [listID, card, time])
            } else {
                try db.execute(sql: "DELETE FROM reader_bookmark_memberships WHERE list_id = ? AND card_id = ?",
                    arguments: [listID, card])
            }
        }
    }

    /// How many cards each box holds, in one read — the row's own figure, never one query per row.
    public func bookmarkListCounts() throws -> [String: Int] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT list_id, COUNT(*) AS total FROM reader_bookmark_memberships GROUP BY list_id
                """)
            return Dictionary(uniqueKeysWithValues: rows.map { row in (row["list_id"] as String, row["total"] as Int) })
        }
    }

    public func bookmarkedCardIDs(inList listID: String) throws -> Set<PublicationCardID> {
        try database.read { db in
            Set(try String.fetchAll(db, sql: "SELECT card_id FROM reader_bookmark_memberships WHERE list_id = ? ORDER BY added_at, card_id",
                arguments: [listID]).map { raw in
                    // Card ids are stored exactly as `PublicationStore` writes them, and read back through the
                    // same coding, so the two never disagree about the shape of an identity.
                    PublicationCardID(rawValue: try PersistenceValueCoding.uuid(raw, field: "card_id"))
                })
        }
    }

    /// Which boxes hold a card. The card control states "saved" from this, never from one box alone.
    public func bookmarkListIDs(forCard cardID: PublicationCardID) throws -> Set<String> {
        let card = PersistenceValueCoding.uuid(cardID.rawValue)
        return try database.read { db in
            Set(try String.fetchAll(db, sql: "SELECT list_id FROM reader_bookmark_memberships WHERE card_id = ?",
                arguments: [card]))
        }
    }

    /// Applies a whole library in one transaction. Imported items are appended after what the reader already
    /// has, in the imported order, so an import can never reorder or overwrite existing library items; items
    /// whose id already exists are skipped, which is what makes a repeated or interrupted import idempotent.
    public func apply(_ import: ReaderLibraryImport, at date: Date) throws -> ReaderLibraryImportReport {
        let time = try PersistenceValueCoding.date(date, field: "added_at")
        return try database.write { db in
            var lists = 0, collections = 0, presets = 0, memberships = 0
            for list in `import`.bookmarkLists {
                guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_bookmark_lists WHERE id = ?)",
                    arguments: [list.id]) == false else { continue }
                try db.execute(sql: "INSERT INTO reader_bookmark_lists (id, name, position) VALUES (?, ?, ?)",
                    arguments: [list.id, list.name, Self.nextListPosition(db)])
                lists += 1
            }
            for collection in `import`.collections {
                guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_collections WHERE id = ?)",
                    arguments: [collection.id]) == false else { continue }
                let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM reader_collections") ?? 0
                try db.execute(sql: "INSERT INTO reader_collections (id, name, position) VALUES (?, ?, ?)",
                    arguments: [collection.id, collection.name, position])
                collections += 1
                for key in Array(Set(collection.memberKeys)).filter({ !$0.isEmpty }).sorted() {
                    try db.execute(sql: """
                        INSERT INTO reader_collection_memberships (collection_id, source_key, added_at) VALUES (?, ?, ?)
                        ON CONFLICT(collection_id, source_key) DO NOTHING
                        """, arguments: [collection.id, key, time])
                    memberships += db.changesCount
                }
            }
            for preset in `import`.presets {
                guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_presets WHERE id = ?)",
                    arguments: [preset.id]) == false else { continue }
                let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM reader_presets WHERE kind = ?",
                    arguments: [preset.kind.rawValue]) ?? 0
                try db.execute(sql: "INSERT INTO reader_presets (id, name, kind, position, context_key) VALUES (?, ?, ?, ?, ?)",
                    arguments: [preset.id, preset.name, preset.kind.rawValue, position,
                        try JSONEncoder().encode(preset.key)])
                presets += 1
            }
            return ReaderLibraryImportReport(insertedBookmarkLists: lists, insertedCollections: collections,
                insertedPresets: presets, insertedMemberships: memberships)
        }
    }

    private static func nextListPosition(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM reader_bookmark_lists") ?? 0
    }

    // MARK: - Source collections

    public func collections() throws -> [ReaderCollection] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, position FROM reader_collections ORDER BY position, id")
                .map { ReaderCollection(id: $0["id"], name: $0["name"], position: $0["position"]) }
        }
    }

    @discardableResult
    public func createCollection(named rawName: String) throws -> ReaderCollection {
        guard let name = ReaderLibraryRules.normalizedName(rawName) else { throw ReaderLibraryError.invalidName }
        return try database.write { db in
            let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM reader_collections") ?? 0
            let collection = ReaderCollection(id: Self.mintID(), name: name, position: position)
            try db.execute(sql: "INSERT INTO reader_collections (id, name, position) VALUES (?, ?, ?)",
                arguments: [collection.id, collection.name, collection.position])
            return collection
        }
    }

    @discardableResult
    public func renameCollection(id: String, to rawName: String) throws -> ReaderCollection {
        guard let name = ReaderLibraryRules.normalizedName(rawName) else { throw ReaderLibraryError.invalidName }
        return try database.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_collections WHERE id = ?)",
                arguments: [id]) == true else { throw ReaderLibraryError.missingLibraryItem }
            try db.execute(sql: "UPDATE reader_collections SET name = ? WHERE id = ?", arguments: [name, id])
            let position = try Int.fetchOne(db, sql: "SELECT position FROM reader_collections WHERE id = ?",
                arguments: [id]) ?? 0
            return ReaderCollection(id: id, name: name, position: position)
        }
    }

    /// Deletes a collection and its memberships. No source, feed or article is touched: a collection is a
    /// reader-made group, not an owner (V1 behaved the same way).
    @discardableResult
    public func deleteCollection(id: String) throws -> Bool {
        try database.write { db in
            try db.execute(sql: "DELETE FROM reader_collections WHERE id = ?", arguments: [id])
            let removed = db.changesCount > 0
            try db.execute(sql: "DELETE FROM reader_collection_memberships WHERE collection_id = ?", arguments: [id])
            return removed
        }
    }

    @discardableResult
    public func reorderCollections(_ ids: [String]) throws -> [ReaderCollection] {
        try database.write { db in
            let current = try Row.fetchAll(db, sql: "SELECT id, name, position FROM reader_collections ORDER BY position, id")
                .map { ReaderCollection(id: $0["id"], name: $0["name"], position: $0["position"]) }
            let positions = ReaderLibraryRules.positions(current: current.map(\.id), reordered: ids)
            for (id, position) in positions {
                try db.execute(sql: "UPDATE reader_collections SET position = ? WHERE id = ?", arguments: [position, id])
            }
            return current.map { ReaderCollection(id: $0.id, name: $0.name, position: positions[$0.id] ?? $0.position) }
                .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
        }
    }

    public func setCollectionMembership(sourceKey: String, collectionID: String, included: Bool, at date: Date)
        throws {
        let time = try PersistenceValueCoding.date(date, field: "added_at")
        try database.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_collections WHERE id = ?)",
                arguments: [collectionID]) == true else { throw ReaderLibraryError.missingLibraryItem }
            if included {
                try db.execute(sql: """
                    INSERT INTO reader_collection_memberships (collection_id, source_key, added_at) VALUES (?, ?, ?)
                    ON CONFLICT(collection_id, source_key) DO NOTHING
                    """, arguments: [collectionID, sourceKey, time])
            } else {
                try db.execute(sql: "DELETE FROM reader_collection_memberships WHERE collection_id = ? AND source_key = ?",
                    arguments: [collectionID, sourceKey])
            }
        }
    }

    /// Adds every key the reader named in one transaction, so "collect these sources" either lands whole or
    /// not at all.
    @discardableResult
    public func addToCollection(id: String, sourceKeys: [String], at date: Date) throws -> Int {
        let time = try PersistenceValueCoding.date(date, field: "added_at")
        let keys = Array(Set(sourceKeys)).filter { !$0.isEmpty }
        return try database.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_collections WHERE id = ?)",
                arguments: [id]) == true else { throw ReaderLibraryError.missingLibraryItem }
            var added = 0
            for key in keys {
                try db.execute(sql: """
                    INSERT INTO reader_collection_memberships (collection_id, source_key, added_at) VALUES (?, ?, ?)
                    ON CONFLICT(collection_id, source_key) DO NOTHING
                    """, arguments: [id, key, time])
                added += db.changesCount
            }
            return added
        }
    }

    public func sourceKeys(inCollection id: String) throws -> Set<String> {
        try database.read { db in
            Set(try String.fetchAll(db, sql: "SELECT source_key FROM reader_collection_memberships WHERE collection_id = ? ORDER BY added_at, source_key",
                arguments: [id]))
        }
    }

    // MARK: - Saved presets

    public func presets() throws -> [ReaderPreset] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, kind, position, context_key FROM reader_presets
                ORDER BY \(Self.presetKindRank), position, id
                """)
                .map { row in
                    guard let kind = ReaderPreset.Kind(rawValue: row["kind"] as String) else {
                        throw ReaderLibraryError.missingLibraryItem
                    }
                    let key = try JSONDecoder().decode(ContextKey.self, from: row["context_key"] as Data)
                    return ReaderPreset(id: row["id"], name: row["name"], kind: kind, position: row["position"], key: key)
                }
        }
    }

    @discardableResult
    public func createPreset(named rawName: String, kind: ReaderPreset.Kind, key: ContextKey) throws -> ReaderPreset {
        guard let name = ReaderLibraryRules.normalizedName(rawName) else { throw ReaderLibraryError.invalidName }
        let payload = try JSONEncoder().encode(key)
        return try database.write { db in
            let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM reader_presets WHERE kind = ?",
                arguments: [kind.rawValue]) ?? 0
            let preset = ReaderPreset(id: Self.mintID(), name: name, kind: kind, position: position, key: key)
            try db.execute(sql: "INSERT INTO reader_presets (id, name, kind, position, context_key) VALUES (?, ?, ?, ?, ?)",
                arguments: [preset.id, preset.name, preset.kind.rawValue, preset.position, payload])
            return preset
        }
    }

    @discardableResult
    public func renamePreset(id: String, to rawName: String) throws -> ReaderPreset {
        guard let name = ReaderLibraryRules.normalizedName(rawName) else { throw ReaderLibraryError.invalidName }
        return try database.write { db in
            try db.execute(sql: "UPDATE reader_presets SET name = ? WHERE id = ?", arguments: [name, id])
            guard let row = try Row.fetchOne(db, sql: "SELECT id, name, kind, position, context_key FROM reader_presets WHERE id = ?",
                arguments: [id]), let kind = ReaderPreset.Kind(rawValue: row["kind"] as String) else {
                throw ReaderLibraryError.missingLibraryItem
            }
            return ReaderPreset(id: row["id"], name: row["name"], kind: kind, position: row["position"],
                key: try JSONDecoder().decode(ContextKey.self, from: row["context_key"] as Data))
        }
    }

    /// Rewrites one preset's stored key. Used when a context is saved: the key a preset activates has to name
    /// that preset, otherwise activating it would claim to be a surface it is not.
    @discardableResult
    public func replacePresetKey(id: String, key: ContextKey) throws -> ReaderPreset {
        let payload = try JSONEncoder().encode(key)
        return try database.write { db in
            try db.execute(sql: "UPDATE reader_presets SET context_key = ? WHERE id = ?", arguments: [payload, id])
            guard let row = try Row.fetchOne(db, sql: "SELECT id, name, kind, position, context_key FROM reader_presets WHERE id = ?",
                arguments: [id]), let kind = ReaderPreset.Kind(rawValue: row["kind"] as String) else {
                throw ReaderLibraryError.missingLibraryItem
            }
            return ReaderPreset(id: row["id"], name: row["name"], kind: kind, position: row["position"],
                key: try JSONDecoder().decode(ContextKey.self, from: row["context_key"] as Data))
        }
    }

    @discardableResult
    public func deletePreset(id: String) throws -> Bool {
        try database.write { db in
            try db.execute(sql: "DELETE FROM reader_presets WHERE id = ?", arguments: [id])
            return db.changesCount > 0
        }
    }

    @discardableResult
    public func reorderPresets(_ ids: [String]) throws -> [ReaderPreset] {
        try database.write { db in
            let current = try presets(in: db)
            let positions = ReaderLibraryRules.positions(current: current.map(\.id), reordered: ids)
            for (id, position) in positions {
                try db.execute(sql: "UPDATE reader_presets SET position = ? WHERE id = ?", arguments: [position, id])
            }
            return current.map { preset in
                ReaderPreset(id: preset.id, name: preset.name, kind: preset.kind,
                    position: positions[preset.id] ?? preset.position, key: preset.key)
            }
            .sorted { ($0.kind.rawValue, $0.position, $0.id) < ($1.kind.rawValue, $1.position, $1.id) }
        }
    }

    /// V1's picker drew curated feeds before smart bookmarks, and the store keeps that order so a list of
    /// presets is the same list wherever it is read.
    static var presetKindRank: String {
        "CASE kind WHEN 'curatedFeed' THEN 0 WHEN 'smartBookmark' THEN 1 ELSE 2 END"
    }

    private func presets(in db: Database) throws -> [ReaderPreset] {
        try Row.fetchAll(db, sql: "SELECT id, name, kind, position, context_key FROM reader_presets ORDER BY \(Self.presetKindRank), position, id")
            .map { row in
                guard let kind = ReaderPreset.Kind(rawValue: row["kind"] as String) else {
                    throw ReaderLibraryError.missingLibraryItem
                }
                return ReaderPreset(id: row["id"], name: row["name"], kind: kind, position: row["position"],
                    key: try JSONDecoder().decode(ContextKey.self, from: row["context_key"] as Data))
            }
    }

    /// A stable, opaque id. Never a V1 integer and never reused: a deleted collection's id stays deleted.
    /// Public so a caller that must build a whole library atomically (an import, or "collect these sources")
    /// mints the id it will then insert in one transaction.
    public static func mintID() -> String { UUID().uuidString.lowercased() }
}
