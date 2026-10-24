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
import CryptoKit
import FeedMineDomain

public enum ReaderLibraryError: Error, Equatable, Sendable {
    case missingLibraryItem
    case invalidName
    case cardIdentityMismatch
    case invalidSourceIdentity
    case ambiguousSourceIdentity
}


public struct VerifiedSourceAlias: Sendable {
    public let oldKey: String
    public let newKey: String
    public let fingerprint: String
    public let requestURL: String

    /// Proof is intentionally explicit, from two compiled catalog snapshots. The public update manifest
    /// publishes no alias map, so a routine catalog update must never guess this relationship.
    public init(old: LegacyCatalogReader, new: LegacyCatalogReader, oldKey: String, newKey: String) throws {
        guard oldKey != newKey, !oldKey.isEmpty, !newKey.isEmpty,
            let oldRevision = try old.metadata()?.revision, let newRevision = try new.metadata()?.revision,
            oldRevision < newRevision, try old.source(key: newKey) == nil,
            try new.source(key: oldKey) == nil,
            let prior = try old.source(key: oldKey), let current = try new.source(key: newKey),
            prior.requestURL == current.requestURL, prior.mediaKind == current.mediaKind,
            let endpoint = URL(string: prior.requestURL),
            ["http", "https"].contains(endpoint.scheme?.lowercased() ?? ""),
            endpoint.host != nil, endpoint.user == nil, endpoint.password == nil else {
            throw ReaderLibraryError.invalidSourceIdentity
        }
        // Reject an endpoint used by two distinct source records in either snapshot.
        // This full scan is reserved for explicit verification, never startup or feed presentation.
        for (catalog, expected) in [(old, oldKey), (new, newKey)] {
            var cursor: String?
            var matches: [String] = []
            while true {
                let page = try catalog.sources(after: cursor, limit: 500,
                    onlyDefaultEnabled: false, mediaKinds: [])
                guard let last = page.last else { break }
                matches += page.filter { $0.requestURL == prior.requestURL }.map(\.key)
                guard matches.count <= 1 else { throw ReaderLibraryError.ambiguousSourceIdentity }
                cursor = last.key
            }
            guard matches == [expected] else { throw ReaderLibraryError.ambiguousSourceIdentity }
        }
        self.oldKey = oldKey
        self.newKey = newKey
        self.requestURL = prior.requestURL
        let text = "\(oldRevision)|\(newRevision)|\(oldKey)|\(newKey)|\(prior.requestURL)"
        self.fingerprint = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

public struct ReaderLibraryStore: Sendable {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }


    // MARK: - Personal source identity (PD10-P0D)

    /// sourceKey is the durable reader choice, anchorKey fixes its historical IDs, currentKey is only
    /// the verified catalog lookup. Publication IDs and saved card references never depend on this table.
    public struct SourceLink: Hashable, Sendable {
        public let sourceKey: String
        public let anchorKey: String
        public let currentKey: String
        public let authority: String
        public let proof: String?
        public let requestURL: String?
    }

    public func sourceLinks() throws -> [String: SourceLink] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT source_key, anchor_key, current_key, authority, proof, request_url FROM reader_source_identity
                """)
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let link = SourceLink(sourceKey: row["source_key"], anchorKey: row["anchor_key"],
                    currentKey: row["current_key"], authority: row["authority"], proof: row["proof"],
                    requestURL: row["request_url"])
                return (link.sourceKey, link)
            })
        }
    }

    /// The first operational resolution pins an existing namespace. Repeated launches cannot flip it.
    public func rememberResolvedSources(_ sources: [(key: String, authority: String)]) throws {
        try database.write { db in
            for (key, authority) in sources {
                guard !key.isEmpty, authority == "catalog" || authority == "reader" else {
                    throw ReaderLibraryError.invalidSourceIdentity
                }
                try db.execute(sql: """
                    INSERT OR IGNORE INTO reader_source_identity
                        (source_key, anchor_key, current_key, authority) VALUES (?, ?, ?, ?)
                    """, arguments: [key, key, key, authority])
            }
        }
    }

    /// A single personal transaction. Do not rewrite published cards, user selection, checkpoints or presets.
    /// Returns false when the identical verified relation was already committed.
    @discardableResult
    public func reconcile(_ proof: VerifiedSourceAlias) throws -> Bool {
        try database.write { db in
            let old = try Row.fetchOne(db, sql: """
                SELECT anchor_key, current_key, authority, proof FROM reader_source_identity
                WHERE source_key = ?
                """, arguments: [proof.oldKey])
            let anchor: String = old?["anchor_key"] ?? proof.oldKey
            let current: String = old?["current_key"] ?? proof.oldKey
            let authority: String = old?["authority"] ?? "catalog"
            let recorded: String? = old?["proof"]
            guard anchor == proof.oldKey else { throw ReaderLibraryError.ambiguousSourceIdentity }
            if current == proof.newKey && recorded == proof.fingerprint { return false }
            guard current == proof.oldKey else { throw ReaderLibraryError.ambiguousSourceIdentity }
            if let destination = try Row.fetchOne(db, sql: """
                SELECT anchor_key, current_key FROM reader_source_identity WHERE source_key = ?
                """, arguments: [proof.newKey]) {
                let destinationAnchor: String = destination["anchor_key"]
                let destinationCurrent: String = destination["current_key"]
                guard destinationAnchor == proof.oldKey, destinationCurrent == proof.newKey else {
                    throw ReaderLibraryError.ambiguousSourceIdentity
                }
            }
            let conflicting = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM reader_source_identity WHERE current_key = ? AND anchor_key <> ?
                """, arguments: [proof.newKey, proof.oldKey]) ?? 0
            guard conflicting == 0 else { throw ReaderLibraryError.ambiguousSourceIdentity }
            try db.execute(sql: """
                INSERT INTO reader_source_identity (source_key, anchor_key, current_key, authority, proof, request_url)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_key) DO UPDATE SET current_key = excluded.current_key,
                    proof = excluded.proof, request_url = excluded.request_url
                """, arguments: [proof.oldKey, proof.oldKey, proof.newKey, authority, proof.fingerprint,
                    proof.requestURL])
            try db.execute(sql: """
                INSERT OR IGNORE INTO reader_source_identity
                    (source_key, anchor_key, current_key, authority, proof, request_url)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [proof.newKey, proof.oldKey, proof.newKey, authority, proof.fingerprint,
                    proof.requestURL])
            // Collections referencing B become A without duplicate memberships.
            try db.execute(sql: """
                INSERT OR IGNORE INTO reader_collection_memberships (collection_id, source_key, added_at)
                SELECT collection_id, ?, added_at FROM reader_collection_memberships WHERE source_key = ?
                """, arguments: [proof.oldKey, proof.newKey])
            try db.execute(sql: "DELETE FROM reader_collection_memberships WHERE source_key = ?",
                arguments: [proof.newKey])
            return true
        }
    }

    private static func anchor(_ key: String, in db: Database) throws -> String {
        try String.fetchOne(db, sql: "SELECT anchor_key FROM reader_source_identity WHERE source_key = ?",
            arguments: [key]) ?? key
    }

    /// An OPML round-trip may canonicalize a signed request URL into a different key.
    /// Reattach it ONLY when an already verified alias recorded this exact request endpoint.
    /// A title, shared host, redirect guess or unproved URL normalization can never create a link.
    private static func importKey(_ entry: ReaderImportEntry, in db: Database) throws -> String {
        if try Bool.fetchOne(db, sql: """
            SELECT EXISTS(SELECT 1 FROM reader_source_identity WHERE source_key = ?)
            """, arguments: [entry.id]) == true { return entry.id }
        let matches = try String.fetchAll(db, sql: """
            SELECT source_key FROM reader_source_identity
            WHERE source_key = current_key AND proof IS NOT NULL AND request_url = ?
            ORDER BY source_key
            """, arguments: [entry.requestURL])
        return matches.count == 1 ? matches[0] : entry.id
    }

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

    /// The facts the upgrade receipt is written from. Counts in the receipt are the transaction's own report,
    /// never a second tally taken afterwards.
    public struct LegacyUpgradeWrite: Hashable, Sendable {
        public let sourcePath: String
        public let status: ReaderLegacyUpgradeReceipt.Status
        public let failureReason: String?
        public let skips: [ReaderLegacySkip]
        public init(sourcePath: String, status: ReaderLegacyUpgradeReceipt.Status,
            failureReason: String? = nil, skips: [ReaderLegacySkip] = []) {
            self.sourcePath = sourcePath; self.status = status
            self.failureReason = failureReason; self.skips = skips
        }
    }

    /// Applies a whole library in one transaction. Imported items are appended after what the reader already
    /// has, in the imported order, so an import can never reorder or overwrite existing library items; items
    /// whose id already exists are skipped, which is what makes a repeated or interrupted import idempotent.
    ///
    /// `legacyUpgrade` writes the durable receipt in the **same** transaction: an interrupted upgrade commits
    /// neither the imported rows nor a marker claiming they landed.
    public func apply(_ import: ReaderLibraryImport, legacyUpgrade: LegacyUpgradeWrite? = nil,
        at date: Date) throws -> ReaderLibraryImportReport {
        let time = try PersistenceValueCoding.date(date, field: "added_at")
        return try database.write { db in
            var lists = 0, sources = 0, selectedSources = 0, collections = 0, presets = 0, memberships = 0
            for list in `import`.bookmarkLists {
                guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_bookmark_lists WHERE id = ?)",
                    arguments: [list.id]) == false else { continue }
                try db.execute(sql: "INSERT INTO reader_bookmark_lists (id, name, position) VALUES (?, ?, ?)",
                    arguments: [list.id, list.name, Self.nextListPosition(db)])
                lists += 1
            }
            // V1's personal feeds: the canonical key is the primary key, so a second run adds nothing. Their
            // selection is a union with whatever the reader already chose — an upgrade never removes a source.
            for source in `import`.sources {
                try db.execute(sql: """
                    INSERT INTO reader_imported_sources (key, request_url, title, imported_at) VALUES (?, ?, ?, ?)
                    ON CONFLICT(key) DO NOTHING
                    """, arguments: [source.key, source.requestURL, source.title, time])
                sources += db.changesCount
            }
            let selected = `import`.sources.filter(\.select).map(\.key)
            if !selected.isEmpty,
                let row = try Row.fetchOne(db, sql: "SELECT source_keys, selection_version FROM reader_preferences WHERE singleton_id = 1") {
                let current = Set(try JSONDecoder().decode([String].self, from: row["source_keys"] as Data))
                let union = current.union(selected)
                if union != current {
                    let version: Int64 = row["selection_version"]
                    guard version < Int64.max else { throw ReaderLibraryError.missingLibraryItem }
                    try db.execute(sql: "UPDATE reader_preferences SET source_keys = ?, selection_version = ? WHERE singleton_id = 1",
                        arguments: [try JSONEncoder().encode(union.sorted()), version + 1])
                    selectedSources = union.count - current.count
                }
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
                try db.execute(sql: """
                    INSERT INTO reader_presets (id, name, kind, position, context_key, recipe_json)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [preset.id, preset.name, preset.kind.rawValue, position,
                    try JSONEncoder().encode(preset.key), try preset.recipe.map { try JSONEncoder().encode($0) }])
                presets += 1
            }
            let report = ReaderLibraryImportReport(insertedBookmarkLists: lists, insertedSources: sources,
                selectedSources: selectedSources, insertedCollections: collections, insertedPresets: presets,
                insertedMemberships: memberships)
            if let legacyUpgrade {
                try Self.writeLegacyUpgrade(legacyUpgrade, report: report, at: date, in: db)
            }
            return report
        }
    }

    private static func nextListPosition(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM reader_bookmark_lists") ?? 0
    }

    // MARK: - V1 upgrade receipt (D7-A)

    private static func writeLegacyUpgrade(_ write: LegacyUpgradeWrite,
        report: ReaderLibraryImportReport, at date: Date, in db: Database) throws {
        let time = try PersistenceValueCoding.date(date, field: "ran_at")
        try db.execute(sql: """
            INSERT INTO reader_legacy_upgrade
                (singleton_id, source_path, status, ran_at, failure_reason, imported_boxes, imported_sources,
                 selected_sources, imported_collections, imported_collection_members, notice_presented)
            VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            ON CONFLICT(singleton_id) DO UPDATE SET
                source_path = excluded.source_path,
                status = excluded.status,
                ran_at = excluded.ran_at,
                failure_reason = excluded.failure_reason,
                imported_boxes = excluded.imported_boxes,
                imported_sources = excluded.imported_sources,
                selected_sources = excluded.selected_sources,
                imported_collections = excluded.imported_collections,
                imported_collection_members = excluded.imported_collection_members,
                notice_presented = 0
            """, arguments: [write.sourcePath, write.status.rawValue, time, write.failureReason,
            report.insertedBookmarkLists, report.insertedSources, report.selectedSources,
            report.insertedCollections, report.insertedMemberships])
        try db.execute(sql: "DELETE FROM reader_legacy_upgrade_skips")
        for skip in write.skips where skip.count > 0 {
            try db.execute(sql: """
                INSERT INTO reader_legacy_upgrade_skips (category, reason, count) VALUES (?, ?, ?)
                """, arguments: [skip.category, skip.reason, skip.count])
        }
    }

    /// The durable upgrade receipt: nil when no V1 container has ever been upgraded in this database.
    public func legacyUpgradeReceipt() throws -> ReaderLegacyUpgradeReceipt? {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT * FROM reader_legacy_upgrade WHERE singleton_id = 1
                """) else { return nil }
            let skips = try Row.fetchAll(db, sql: """
                SELECT category, reason, count FROM reader_legacy_upgrade_skips ORDER BY category, reason
                """).map { ReaderLegacySkip(category: $0["category"], reason: $0["reason"], count: $0["count"]) }
            return ReaderLegacyUpgradeReceipt(
                sourcePath: row["source_path"],
                status: ReaderLegacyUpgradeReceipt.Status(rawValue: row["status"]) ?? .failed,
                ranAt: Date(timeIntervalSince1970: row["ran_at"]),
                failureReason: row["failure_reason"],
                importedBoxes: row["imported_boxes"],
                importedSources: row["imported_sources"],
                selectedSources: row["selected_sources"],
                importedCollections: row["imported_collections"],
                importedCollectionMembers: row["imported_collection_members"],
                skips: skips,
                noticePresented: (row["notice_presented"] as Int64) != 0)
        }
    }

    /// Records that the reader has been told. It never rewrites the counts or the marker: the notice is a
    /// separate fact from the upgrade.
    @discardableResult
    public func markLegacyUpgradeNoticePresented() throws -> Bool {
        try database.write { db in
            try db.execute(sql: """
                UPDATE reader_legacy_upgrade SET notice_presented = 1 WHERE singleton_id = 1
                """)
            return db.changesCount > 0
        }
    }

    /// A failed attempt is recorded, but a completed upgrade is never overwritten by a later failure.
    public func recordLegacyUpgradeFailure(sourcePath: String, reason: String, at date: Date) throws {
        if let existing = try legacyUpgradeReceipt(), existing.status == .completed { return }
        let time = try PersistenceValueCoding.date(date, field: "ran_at")
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO reader_legacy_upgrade
                    (singleton_id, source_path, status, ran_at, failure_reason)
                VALUES (1, ?, 'failed', ?, ?)
                ON CONFLICT(singleton_id) DO UPDATE SET
                    source_path = excluded.source_path,
                    status = 'failed',
                    ran_at = excluded.ran_at,
                    failure_reason = excluded.failure_reason
                """, arguments: [sourcePath, time, reason])
        }
    }

    // MARK: - Imported sources (T10)

    /// Writes an imported file's feeds and selects them, in **one** transaction. The feed's identity is the
    /// primary key, so running the same import twice adds nothing; the selection is versioned exactly as any
    /// other selection change is, so a session that fences on the version sees it.
    ///
    /// `collectionID` files the same feeds into a personal collection **inside the same transaction**: an import
    /// a reader asked to be filed either lands whole (feeds, selection and memberships) or not at all. A
    /// collection that does not exist refuses the whole write rather than leaving a reader with feeds they
    /// believed were in a collection.
    public func commitImport(_ entries: [ReaderImportEntry], rejected: Int, collectionID: String? = nil,
        at date: Date) throws -> ReaderImportResult {
        let time = try PersistenceValueCoding.date(date, field: "imported_at")
        return try database.write { db in
            if let collectionID {
                guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_collections WHERE id = ?)",
                    arguments: [collectionID]) == true else {
                    throw ReaderLibraryError.missingLibraryItem
                }
            }
            let resolvedKeys = try entries.map { try Self.importKey($0, in: db) }
            var inserted = 0
            for (entry, key) in zip(entries, resolvedKeys) {
                try db.execute(sql: """
                    INSERT INTO reader_imported_sources (key, request_url, title, imported_at) VALUES (?, ?, ?, ?)
                    ON CONFLICT(key) DO NOTHING
                    """, arguments: [key, entry.requestURL, entry.title, time])
                inserted += db.changesCount
            }
            var filed = 0
            if let collectionID {
                for key in resolvedKeys {
                    try db.execute(sql: """
                        INSERT INTO reader_collection_memberships (collection_id, source_key, added_at) VALUES (?, ?, ?)
                        ON CONFLICT(collection_id, source_key) DO NOTHING
                        """, arguments: [collectionID, try Self.anchor(key, in: db), time])
                    filed += db.changesCount
                }
            }
            guard let row = try Row.fetchOne(db, sql: "SELECT source_keys, selection_version FROM reader_preferences WHERE singleton_id = 1") else {
                throw ReaderLibraryError.missingLibraryItem
            }
            let current = Set(try JSONDecoder().decode([String].self, from: row["source_keys"] as Data))
            let anchors = try resolvedKeys.map { try Self.anchor($0, in: db) }
            let selected = current.union(anchors)
            let alreadySelected = anchors.filter { current.contains($0) }.count
            if selected != current {
                let version: Int64 = row["selection_version"]
                guard version < Int64.max else { throw ReaderLibraryError.missingLibraryItem }
                try db.execute(sql: "UPDATE reader_preferences SET source_keys = ?, selection_version = ? WHERE singleton_id = 1",
                    arguments: [try JSONEncoder().encode(selected.sorted()), version + 1])
            }
            return ReaderImportResult(insertedSources: inserted, alreadySelected: alreadySelected,
                rejected: rejected, filedInCollection: filed)
        }
    }

    /// Every feed this app imported from a file. The shipped catalog is not consulted: an imported feed is only
    /// here.
    public func importedSources() throws -> [ReaderImportEntry] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT key, request_url, title FROM reader_imported_sources ORDER BY imported_at, key
                """).map { row in
                ReaderImportEntry(id: row["key"], title: row["title"], requestURL: row["request_url"],
                    categoryPath: [])
            }
        }
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
                    """, arguments: [collectionID, try Self.anchor(sourceKey, in: db), time])
            } else {
                try db.execute(sql: "DELETE FROM reader_collection_memberships WHERE collection_id = ? AND source_key = ?",
                    arguments: [collectionID, try Self.anchor(sourceKey, in: db)])
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
                    """, arguments: [id, try Self.anchor(key, in: db), time])
                added += db.changesCount
            }
            return added
        }
    }

    public func sourceKeys(inCollection id: String) throws -> Set<String> {
        try database.read { db in
            Set(try String.fetchAll(db, sql: """
                SELECT COALESCE(i.anchor_key, m.source_key)
                FROM reader_collection_memberships m
                LEFT JOIN reader_source_identity i ON i.source_key = m.source_key
                WHERE m.collection_id = ? ORDER BY m.added_at, m.source_key
                """, arguments: [id]))
        }
    }

    // MARK: - Saved presets

    public func presets() throws -> [ReaderPreset] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, kind, position, context_key, recipe_json, recipe_revision FROM reader_presets
                ORDER BY \(Self.presetKindRank), position, id
                """)
                .map { row in
                    guard let kind = ReaderPreset.Kind(rawValue: row["kind"] as String) else {
                        throw ReaderLibraryError.missingLibraryItem
                    }
                    let key = try JSONDecoder().decode(ContextKey.self, from: row["context_key"] as Data)
                    return ReaderPreset(id: row["id"], name: row["name"], kind: kind, position: row["position"],
                        key: key, recipe: try Self.recipe(row["recipe_json"] as Data?),
                        recipeRevision: row["recipe_revision"])
                }
        }
    }

    @discardableResult
    public func createPreset(named rawName: String, kind: ReaderPreset.Kind, key: ContextKey,
        recipe: FeedRecipeDefinition? = nil) throws -> ReaderPreset {
        guard let name = ReaderLibraryRules.normalizedName(rawName) else { throw ReaderLibraryError.invalidName }
        let payload = try JSONEncoder().encode(key)
        let recipePayload = try recipe.map { try JSONEncoder().encode($0) }
        return try database.write { db in
            let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM reader_presets WHERE kind = ?",
                arguments: [kind.rawValue]) ?? 0
            let preset = ReaderPreset(id: Self.mintID(), name: name, kind: kind, position: position, key: key,
                recipe: recipe)
            try db.execute(sql: """
                INSERT INTO reader_presets (id, name, kind, position, context_key, recipe_json)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [preset.id, preset.name, preset.kind.rawValue, preset.position, payload,
                recipePayload])
            return preset
        }
    }

    /// T11: rewrites a curated preset's recipe and the identity it activates, in one transaction — editing a
    /// feed's controls changes both, and they must never disagree.
    @discardableResult
    public func updateCuratedPreset(id: String, name: String, key: ContextKey,
        recipe: FeedRecipeDefinition) throws -> ReaderPreset {
        guard let name = ReaderLibraryRules.normalizedName(name) else { throw ReaderLibraryError.invalidName }
        let payload = try JSONEncoder().encode(key)
        let recipePayload = try JSONEncoder().encode(recipe)
        return try database.write { db in
            // An edit is a new revision of the recipe: the behaviour changes while the identity does not.
            try db.execute(sql: """
                UPDATE reader_presets SET name = ?, context_key = ?, recipe_json = ?,
                    recipe_revision = recipe_revision + 1 WHERE id = ?
                """, arguments: [name, payload, recipePayload, id])
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, name, kind, position, context_key, recipe_json, recipe_revision
                FROM reader_presets WHERE id = ?
                """, arguments: [id]), let kind = ReaderPreset.Kind(rawValue: row["kind"] as String) else {
                throw ReaderLibraryError.missingLibraryItem
            }
            return ReaderPreset(id: row["id"], name: row["name"], kind: kind, position: row["position"],
                key: try JSONDecoder().decode(ContextKey.self, from: row["context_key"] as Data),
                recipe: try Self.recipe(row["recipe_json"] as Data?), recipeRevision: row["recipe_revision"])
        }
    }

    /// A stored recipe, or nil when the preset is not a curated one. A recipe that cannot be decoded is a
    /// missing library item, not a preset that silently lost its controls.
    private static func recipe(_ payload: Data?) throws -> FeedRecipeDefinition? {
        guard let payload else { return nil }
        guard let recipe = try? JSONDecoder().decode(FeedRecipeDefinition.self, from: payload) else {
            throw ReaderLibraryError.missingLibraryItem
        }
        return recipe
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
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, name, kind, position, context_key, recipe_json, recipe_revision
                FROM reader_presets WHERE id = ?
                """, arguments: [id]), let kind = ReaderPreset.Kind(rawValue: row["kind"] as String) else {
                throw ReaderLibraryError.missingLibraryItem
            }
            return ReaderPreset(id: row["id"], name: row["name"], kind: kind, position: row["position"],
                key: try JSONDecoder().decode(ContextKey.self, from: row["context_key"] as Data),
                recipe: try Self.recipe(row["recipe_json"] as Data?), recipeRevision: row["recipe_revision"])
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
