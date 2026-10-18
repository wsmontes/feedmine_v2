// File: PublicationStore+Presentation.swift
// Module: FeedMinePersistence
// Owns: the reader-facing reads: checkpoint tails, Editions, Segments, keyset card windows, media locators and bookmark/media use.
// Does not own: publication semantics, ordering decisions, retention or probing.
// Dependencies: FeedMineDomain, Foundation and private GRDB access only.

import Foundation
import GRDB
import FeedMineDomain

extension PublicationStore {

    /// The ordinal-0 canonical media locator of a card's own revision. It is immutable per occurrence, so a
    /// card's media is the media it was published with, whatever the origin says later.
    public func mediaLocator(cardID: PublicationCardID) throws -> String? {
        try database.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT m.remote_locator AS locator FROM published_cards c
                LEFT JOIN media_candidates m ON m.origin_revision_id = c.origin_revision_id AND m.ordinal = 0 AND m.media_class = 'image'
                WHERE c.id = ?
                """, arguments: [PersistenceValueCoding.uuid(cardID.rawValue)])
            return row?["locator"] as String?
        }
    }

    public struct MediaUsage: Hashable, Sendable {
        public let lastSeenAt: Date?
        public let bookmarked: Bool
    }
    public func bookmarkedCardIDs() throws -> Set<PublicationCardID> {
        try database.read { db in
            Set(try String.fetchAll(db, sql: "SELECT DISTINCT card_id FROM reader_bookmark_memberships").map {
                PublicationCardID(rawValue: try PublicationValueCoding.uuid($0, field: "card_id"))
            })
        }
    }
    /// Toggles one card in one box. The caller states the box: V1 wrote into the reader's *preferred* box, and
    /// the app resolves that preference before calling here.
    public func toggleBookmark(cardID: PublicationCardID, in listID: String, at date: Date) throws {
        let time = try PersistenceValueCoding.date(date, field: "bookmarked_at")
        try database.write { db in
            let key = PersistenceValueCoding.uuid(cardID.rawValue)
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM published_cards WHERE id = ?)", arguments: [key]) == true else {
                throw PublicationStoreError.cardIdentityMismatch
            }
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_bookmark_lists WHERE id = ?)",
                arguments: [listID]) == true else {
                throw PublicationStoreError.cardIdentityMismatch
            }
            if try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_bookmark_memberships WHERE list_id = ? AND card_id = ?)",
                arguments: [listID, key]) == true {
                try db.execute(sql: "DELETE FROM reader_bookmark_memberships WHERE list_id = ? AND card_id = ?",
                    arguments: [listID, key])
            } else {
                try db.execute(sql: "INSERT INTO reader_bookmark_memberships (list_id, card_id, added_at) VALUES (?, ?, ?)",
                    arguments: [listID, key, time])
            }
        }
    }

    /// The default box's convenience, for a caller with no preference to resolve.
    public func toggleBookmark(cardID: PublicationCardID, at date: Date) throws {
        try toggleBookmark(cardID: cardID, in: ReaderBookmarkList.defaultID, at: date)
    }
    public func mediaUsage() throws -> [String: MediaUsage] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.media_key, MAX(u.last_seen_at) AS seen_at, MAX(b.card_id IS NOT NULL) AS bookmarked
                FROM published_cards c LEFT JOIN publication_card_usage u ON u.card_id = c.id
                LEFT JOIN reader_bookmark_memberships b ON b.card_id = c.id
                WHERE c.media_key IS NOT NULL GROUP BY c.media_key
                """)
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                let time: Double? = row["seen_at"]
                return (row["media_key"] as String, MediaUsage(lastSeenAt: time.map(Date.init(timeIntervalSince1970:)), bookmarked: (row["bookmarked"] as Int) != 0))
            })
        }
    }

    public struct TailRecord: Hashable, Sendable {
        public let ordinal: UInt64
        public init(ordinal: UInt64) { self.ordinal = ordinal }
    }

    public func tail(editionID: FeedEditionID) throws -> TailRecord {
        try database.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT publication_schema_version FROM feed_editions WHERE id = ?",
                arguments: [PersistenceValueCoding.uuid(editionID.rawValue)]) else {
                throw PublicationStoreError.missingEdition
            }
            return try Self.readTail(editionID: editionID,
                schemaVersion: PublicationRecordFields(row).counter("publication_schema_version"), in: db)
        }
    }

    static func readTail(editionID: FeedEditionID, schemaVersion: UInt64, in db: Database) throws -> TailRecord {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT ordinal, publication_schema_version FROM feed_segments
            WHERE edition_id = ? ORDER BY ordinal DESC LIMIT 1
            """, arguments: [PersistenceValueCoding.uuid(editionID.rawValue)]) else {
            throw PublicationStoreError.corruption("empty edition")
        }
        let fields = PublicationRecordFields(row)
        let ordinal = try fields.counter("ordinal")
        guard try fields.counter("publication_schema_version") == schemaVersion else {
            throw PublicationStoreError.corruption("tail publication schema")
        }
        return TailRecord(ordinal: ordinal)
    }

    public func edition(id: FeedEditionID) throws -> EditionRecord? {
        try database.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM feed_editions WHERE id = ?", arguments: [PersistenceValueCoding.uuid(id.rawValue)])
                .map(Self.decodeEdition)
        }
    }

    /// R16: the published cards a bounded set of occurrences named, resolved in **one** query. A unified search
    /// asks this once for its examined window instead of one scan per result.
    public func cardIDs(originRecordIDs: [OriginRecordID]) throws -> [OriginRecordID: PublicationCardID] {
        guard !originRecordIDs.isEmpty else { return [:] }
        let keys = Set(originRecordIDs.map { PersistenceValueCoding.uuid($0.rawValue) }).sorted()
        return try database.read { db in
            guard keys.count <= db.maximumStatementArgumentCount - 1 else { throw PublicationStoreError.invalidCapacity }
            let rows = try Row.fetchAll(db,
                sql: "SELECT origin_record_id, id FROM published_cards WHERE origin_record_id IN ("
                    + Array(repeating: "?", count: keys.count).joined(separator: ",") + ")",
                arguments: StatementArguments(keys))
            var result: [OriginRecordID: PublicationCardID] = [:]
            for row in rows {
                guard let origin = UUID(uuidString: row["origin_record_id"]),
                    let card = UUID(uuidString: row["id"]) else { continue }
                result[OriginRecordID(rawValue: origin)] = PublicationCardID(rawValue: card)
            }
            return result
        }
    }

    public func card(id: PublicationCardID) throws -> CardRecord? {
        try database.read { db in
            let key = PersistenceValueCoding.uuid(id.rawValue)
            let active = try Row.fetchOne(db, sql: "SELECT * FROM published_cards WHERE id = ?", arguments: [key])
            if let active { return try Self.decodeCard(active) }
            return try Row.fetchOne(db, sql: "SELECT * FROM retired_published_cards WHERE id = ?", arguments: [key]).map(Self.decodeCard)
        }
    }

    public func segments(editionID: FeedEditionID) throws -> [SegmentRecord] {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM feed_editions WHERE id = ?", arguments: [PersistenceValueCoding.uuid(editionID.rawValue)]) else {
                throw PublicationStoreError.missingEdition
            }
            let edition = try Self.decodeEdition(row)
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM feed_segments WHERE edition_id = ? ORDER BY ordinal",
                arguments: [PersistenceValueCoding.uuid(editionID.rawValue)])
            guard !rows.isEmpty else { throw PublicationStoreError.corruption("empty edition") }
            return try rows.enumerated().map { index, row in
                let segment = try Self.decodeSegment(row, db: db)
                guard segment.ordinal == UInt64(index), segment.publicationSchemaVersion == edition.publicationSchemaVersion else {
                    throw PublicationStoreError.corruption("segment ordinal/schema")
                }
                return segment
            }
        }
    }

    public func cards(editionID: FeedEditionID, around anchorID: PublicationCardID, backwardCapacity: Int, forwardCapacity: Int) throws -> [CardRecord] {
        guard backwardCapacity >= 0, forwardCapacity >= 0 else { throw PublicationStoreError.invalidCapacity }
        return try cards(editionID: editionID, around: anchorID, backwardLimit: backwardCapacity,
            forwardCapacity: forwardCapacity)
    }

    /// The same read with **no backward limit**: every card of the Edition from its first Segment up to and
    /// including `anchorID`, then `forwardCapacity` cards after it. One query, one owner, two reaches — the
    /// backward `LIMIT` is what differs.
    ///
    /// The caller that needs this is a restore of a presentation installed with `keepsAdmittedHead`: that list held
    /// every card above the reader for the life of the session, so the head is what the reader had, not a bound to
    /// be recomputed at the reopen.
    public func cards(editionID: FeedEditionID, fromEditionStartTo anchorID: PublicationCardID, forwardCapacity: Int) throws -> [CardRecord] {
        guard forwardCapacity >= 0 else { throw PublicationStoreError.invalidCapacity }
        return try cards(editionID: editionID, around: anchorID, backwardLimit: nil, forwardCapacity: forwardCapacity)
    }

    private func cards(editionID: FeedEditionID, around anchorID: PublicationCardID, backwardLimit: Int?,
        forwardCapacity: Int) throws -> [CardRecord] {
        try database.read { db in
            let editionKey = PersistenceValueCoding.uuid(editionID.rawValue)
            guard let editionRow = try Row.fetchOne(db, sql: "SELECT * FROM feed_editions WHERE id = ?", arguments: [editionKey]) else {
                throw PublicationStoreError.missingEdition
            }
            let edition = try Self.decodeEdition(editionRow)
            guard let anchor = try Row.fetchOne(db, sql: """
                SELECT c.*, s.ordinal AS segment_ordinal, s.edition_id AS anchor_edition_id
                FROM published_cards c JOIN feed_segments s ON s.id = c.segment_id
                WHERE c.id = ?
                """, arguments: [PersistenceValueCoding.uuid(anchorID.rawValue)]),
                try PublicationRecordFields(anchor).string("anchor_edition_id") == editionKey else {
                throw PublicationStoreError.corruption("anchor membership")
            }
            let f = PublicationRecordFields(anchor)
            let segmentOrdinal = try f.integer("segment_ordinal"), cardOrdinal = try f.integer("ordinal")
            guard segmentOrdinal >= 0, cardOrdinal >= 0 else { throw PublicationStoreError.corruption("anchor position") }
            // Metadata aggregate detects retained Segment gaps without loading every Segment/card payload.
            let summary = try Row.fetchOne(db, sql: "SELECT COUNT(*) AS count, MIN(ordinal) AS low, MAX(ordinal) AS high FROM feed_segments WHERE edition_id = ?", arguments: [editionKey])!
            let sf = PublicationRecordFields(summary)
            let count = try sf.integer("count"), low = try sf.integer("low"), high = try sf.integer("high")
            guard count > 0, low == 0, high == count - 1 else { throw PublicationStoreError.corruption("segment continuity") }
            let query = "SELECT c.*, s.ordinal AS segment_ordinal FROM feed_segments s JOIN published_cards c ON c.segment_id = s.id WHERE s.edition_id = ? AND (s.ordinal, c.ordinal) "
            let backward: [Row]
            if let backwardLimit {
                backward = try Row.fetchAll(db, sql: query + "< (?, ?) ORDER BY s.ordinal DESC, c.ordinal DESC LIMIT ?",
                    arguments: [editionKey, segmentOrdinal, cardOrdinal, backwardLimit])
            } else {
                backward = try Row.fetchAll(db, sql: query + "< (?, ?) ORDER BY s.ordinal DESC, c.ordinal DESC",
                    arguments: [editionKey, segmentOrdinal, cardOrdinal])
            }
            let forward = try Row.fetchAll(db, sql: query + "> (?, ?) ORDER BY s.ordinal ASC, c.ordinal ASC LIMIT ?",
                arguments: [editionKey, segmentOrdinal, cardOrdinal, forwardCapacity])
            let rows = Array(backward.reversed()) + [anchor] + forward
            let touched = try Set(rows.map { try PublicationRecordFields($0).string("segment_id") })
            for segmentKey in touched {
                guard let segmentRow = try Row.fetchOne(db, sql: "SELECT * FROM feed_segments WHERE id = ?", arguments: [segmentKey]) else {
                    throw PublicationStoreError.corruption("missing segment")
                }
                let segment = try Self.decodeSegment(segmentRow, db: db)
                guard segment.editionID == editionID, segment.publicationSchemaVersion == edition.publicationSchemaVersion else {
                    throw PublicationStoreError.corruption("segment membership/schema")
                }
            }
            // Also reject empty Segments crossed by the required neighborhood.
            let firstPosition = try PublicationRecordFields(rows.first!).integer("segment_ordinal")
            let lastPosition = try PublicationRecordFields(rows.last!).integer("segment_ordinal")
            // An exhausted requested side traversed to the Edition boundary even if
            // an empty Segment produced no joined card row. Validate that full interval.
            // With no backward limit there is no request to fall short of: the read reached the Edition's start.
            let requiredFirst = backwardLimit.map { backward.count < $0 ? 0 : firstPosition } ?? 0
            let requiredLast = forward.count < forwardCapacity ? high : lastPosition
            let crossed = try Row.fetchAll(db, sql: "SELECT * FROM feed_segments WHERE edition_id = ? AND ordinal BETWEEN ? AND ? ORDER BY ordinal", arguments: [editionKey, requiredFirst, requiredLast])
            for row in crossed {
                let segment = try Self.decodeSegment(row, db: db)
                guard segment.publicationSchemaVersion == edition.publicationSchemaVersion else { throw PublicationStoreError.corruption("segment schema") }
            }
            return try rows.map(Self.decodeCard)
        }
    }

}
