// File: PublicationStore+History.swift
// Module: FeedMinePersistence
// Owns: history positions, exposure probes and the reader's position state: seen high water, hidden tail and tail succession.
// Does not own: publication semantics, card payloads or reader-facing reads.
// Dependencies: FeedMineDomain, Foundation and private GRDB access only.

import Foundation
import GRDB
import FeedMineDomain

extension PublicationStore {

    public struct HiddenTailLease: Hashable, Sendable {
        public let editionID: FeedEditionID
        public let generation: Int64
        public let highWaterCardID: PublicationCardID
        /// Last card that may not be replaced; never earlier than the seen high water.
        public let protectedThroughCardID: PublicationCardID
        public let expectedTailCardID: PublicationCardID
    }
    public enum TailSuccessionResult: Hashable, Sendable { case applied; case stale; case ineligible }

    public func markSeen(editionID: FeedEditionID, cardID: PublicationCardID, at date: Date = Date()) throws {
        try database.write { try Self.markSeen(editionID: editionID, cardID: cardID, at: date, in: $0) }
    }
    static func markSeen(editionID: FeedEditionID, cardID: PublicationCardID, at date: Date = Date(), in db: Database) throws {
        let key = PersistenceValueCoding.uuid(editionID.rawValue)
        let schema = try historySchema(key, in: db)
        let position = try historyPosition(cardID, editionKey: key, schema: schema, in: db)
        let time = try PersistenceValueCoding.date(date, field: "last_seen_at")
        try db.execute(sql: """
            INSERT INTO publication_card_usage VALUES (?, ?)
            ON CONFLICT(card_id) DO UPDATE SET last_seen_at = excluded.last_seen_at
            """, arguments: [PersistenceValueCoding.uuid(cardID.rawValue), time])
        if let row = try Row.fetchOne(db, sql: "SELECT * FROM edition_reading_state WHERE edition_id = ?", arguments: [key]) {
            let old = PublicationCardID(rawValue: try PublicationValueCoding.uuid(row["high_water_card_id"], field: "high_water_card_id"))
            let prior = try historyPosition(old, editionKey: key, schema: schema, in: db)
            guard prior.isBefore(position) else { return }
            try db.execute(sql: """
                INSERT INTO publication_card_usage SELECT c.id, ? FROM published_cards c JOIN feed_segments s ON s.id = c.segment_id
                WHERE s.edition_id = ? AND (s.ordinal,c.ordinal) > (?,?) AND (s.ordinal,c.ordinal) <= (?,?)
                ON CONFLICT(card_id) DO UPDATE SET last_seen_at = excluded.last_seen_at
                """, arguments: [time, key, Int64(prior.segmentOrdinal), Int64(prior.cardOrdinal), Int64(position.segmentOrdinal), Int64(position.cardOrdinal)])
            try db.execute(sql: "UPDATE edition_reading_state SET high_water_card_id = ?, generation = generation + 1 WHERE edition_id = ?",
                arguments: [PersistenceValueCoding.uuid(cardID.rawValue), key])
        } else {
            try db.execute(sql: """
                INSERT INTO publication_card_usage SELECT c.id, ? FROM published_cards c JOIN feed_segments s ON s.id = c.segment_id
                WHERE s.edition_id = ? AND (s.ordinal,c.ordinal) <= (?,?)
                ON CONFLICT(card_id) DO UPDATE SET last_seen_at = excluded.last_seen_at
                """, arguments: [time, key, Int64(position.segmentOrdinal), Int64(position.cardOrdinal)])
            try db.execute(sql: "INSERT INTO edition_reading_state VALUES (?, ?, 1, 1)", arguments: [key, PersistenceValueCoding.uuid(cardID.rawValue)])
        }
    }
    /// Protects a durable cursor (and all earlier published occurrences) without
    /// claiming that the reader actually viewed any of them. The frontier only
    /// moves forward; an older saved position must not make history replaceable.
    /// An advancing fence invalidates a concurrent hidden-tail lease even if
    /// the separate seen high-water has not moved.
    static func protectPosition(editionID: FeedEditionID, cardID: PublicationCardID, in db: Database) throws {
        let key = PersistenceValueCoding.uuid(editionID.rawValue)
        let schema = try historySchema(key, in: db)
        let position = try historyPosition(cardID, editionKey: key, schema: schema, in: db)
        if let oldKey = try String.fetchOne(db, sql:
            "SELECT protected_card_id FROM edition_position_protection WHERE edition_id = ?", arguments: [key]) {
            let old = PublicationCardID(rawValue: try PublicationValueCoding.uuid(oldKey, field: "protected_card_id"))
            let previous = try historyPosition(old, editionKey: key, schema: schema, in: db)
            guard previous.isBefore(position) else { return }
            try db.execute(sql: "UPDATE edition_position_protection SET protected_card_id = ? WHERE edition_id = ?",
                arguments: [PersistenceValueCoding.uuid(cardID.rawValue), key])
        } else {
            try db.execute(sql: "INSERT INTO edition_position_protection VALUES (?, ?)",
                arguments: [key, PersistenceValueCoding.uuid(cardID.rawValue)])
        }
        try db.execute(sql: "UPDATE edition_reading_state SET generation = generation + 1 WHERE edition_id = ?",
            arguments: [key])
    }

    public func setVisibility(editionID: FeedEditionID, visible: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE edition_reading_state SET visible = ?, generation = generation + 1 WHERE edition_id = ?",
                arguments: [visible ? 1 : 0, PersistenceValueCoding.uuid(editionID.rawValue)])
        }
    }
    public func hiddenTail(editionID: FeedEditionID, protectingThrough admittedCardID: PublicationCardID? = nil) throws -> HiddenTailLease? {
        try database.write { db in
            let key = PersistenceValueCoding.uuid(editionID.rawValue)
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM edition_reading_state WHERE edition_id = ?", arguments: [key]) else { return nil }
            let card = PublicationCardID(rawValue: try PublicationValueCoding.uuid(row["high_water_card_id"], field: "high_water_card_id"))
            let generation: Int64 = row["generation"]
            let schema = try Self.historySchema(key, in: db)
            let tail = try Self.historyTail(editionKey: key, schema: schema, in: db)
            let seen = try Self.historyPosition(card, editionKey: key, schema: schema, in: db)
            var protectedCard = card
            var protectedPosition = seen
            if let saved = try String.fetchOne(db, sql:
                "SELECT protected_card_id FROM edition_position_protection WHERE edition_id = ?", arguments: [key]) {
                let savedID = PublicationCardID(rawValue: try PublicationValueCoding.uuid(saved, field: "protected_card_id"))
                let persisted = try Self.historyPosition(savedID, editionKey: key, schema: schema, in: db)
                if protectedPosition.isBefore(persisted) {
                    protectedCard = savedID
                    protectedPosition = persisted
                }
            }
            if let admittedCardID {
                let admitted = try Self.historyPosition(admittedCardID, editionKey: key, schema: schema, in: db)
                if protectedPosition.isBefore(admitted) { protectedCard = admittedCardID }
            }
            try db.execute(sql: "UPDATE edition_reading_state SET visible = 0, generation = generation + 1 WHERE edition_id = ?", arguments: [key])
            return HiddenTailLease(editionID: editionID, generation: generation + 1,
                highWaterCardID: card, protectedThroughCardID: protectedCard, expectedTailCardID: tail.cardID)
        }
    }
    /// Archives only a non-visible, unseen suffix. Every fence is checked inside the writer.
    public func succeedTail(lease: HiddenTailLease, segmentID: FeedSegmentID, cards: [CardRecord], createdAt: Date, requiredMemberships: [OriginRecordID: Set<SourceID>] = [:]) throws -> TailSuccessionResult {
        try database.write { db in
            let key = PersistenceValueCoding.uuid(lease.editionID.rawValue)
            guard let state = try Row.fetchOne(db, sql: "SELECT * FROM edition_reading_state WHERE edition_id = ?", arguments: [key]),
                (state["visible"] as Int) == 0, (state["generation"] as Int64) == lease.generation,
                (state["high_water_card_id"] as String) == PersistenceValueCoding.uuid(lease.highWaterCardID.rawValue) else { return .stale }
            let schema = try Self.historySchema(key, in: db)
            let tail = try Self.historyTail(editionKey: key, schema: schema, in: db)
            guard tail.cardID == lease.expectedTailCardID else { return .stale }
            let high = try Self.historyPosition(lease.protectedThroughCardID, editionKey: key, schema: schema, in: db)
            guard high.isBefore(tail), !cards.isEmpty else { return .ineligible }
            let segment = SegmentRecord(id: segmentID, editionID: lease.editionID, ordinal: high.segmentOrdinal + 1,
                segmentSeed: 1, publicationSchemaVersion: schema, createdAt: createdAt, cardIDs: cards.map(\.id))
            try Self.validate(segment, cards: cards, version: schema)
            for card in cards {
                let originKey = PersistenceValueCoding.uuid(card.originRecordID.rawValue)
                if let origin = try Row.fetchOne(db, sql: "SELECT current_revision_id, availability FROM origin_records WHERE id = ?", arguments: [originKey]) {
                    guard (origin["current_revision_id"] as String?) == PersistenceValueCoding.uuid(card.originRevisionID.rawValue),
                        ["available", "updated"].contains(origin["availability"] as String) else { return .stale }
                    if let required = requiredMemberships[card.originRecordID] {
                        let memberships = Set(try String.fetchAll(db, sql: "SELECT source_id FROM source_memberships WHERE origin_record_id = ?", arguments: [originKey]))
                        guard memberships == Set(required.map { PersistenceValueCoding.uuid($0.rawValue) }) else { return .stale }
                    }
                } else if requiredMemberships[card.originRecordID] != nil { return .stale }
            }
            let suffixSQL = "SELECT c.id FROM published_cards c JOIN feed_segments s ON s.id = c.segment_id WHERE s.edition_id = ? AND (s.ordinal, c.ordinal) > (?, ?)"
            let args: StatementArguments = [key, Int64(high.segmentOrdinal), Int64(high.cardOrdinal)]
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM reader_bookmark_memberships WHERE card_id IN (" + suffixSQL + ")", arguments: args) == 0,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM publication_card_usage WHERE card_id IN (" + suffixSQL + ")", arguments: args) == 0 else { return .ineligible }
            // Archival happens before deletion and shares its transaction. Duplicate identities abort.
            try db.execute(sql: "INSERT INTO retired_published_cards SELECT * FROM published_cards WHERE id IN (" + suffixSQL + ")", arguments: args)
            try db.execute(sql: "INSERT INTO retired_feed_segments SELECT * FROM feed_segments WHERE edition_id = ? AND ordinal > ?", arguments: [key, Int64(high.segmentOrdinal)])
            try db.execute(sql: "DELETE FROM published_cards WHERE id IN (" + suffixSQL + ")", arguments: args)
            try db.execute(sql: "DELETE FROM feed_segments WHERE edition_id = ? AND ordinal > ?", arguments: [key, Int64(high.segmentOrdinal)])
            try Self.insertSegment(segment, cards: cards, db: db)
            try db.execute(sql: "UPDATE edition_reading_state SET generation = generation + 1 WHERE edition_id = ?", arguments: [key])
            return .applied
        }
    }

    public func seenMaterial(lease: HiddenTailLease, originIDs: [OriginRecordID]) throws -> [OriginRecordID: Set<String>] {
        try database.read { db in
            let key = PersistenceValueCoding.uuid(lease.editionID.rawValue)
            let high = try Self.historyPosition(lease.highWaterCardID, editionKey: key, schema: Self.historySchema(key, in: db), in: db)
            let keys = Array(Set(originIDs)).map { PersistenceValueCoding.uuid($0.rawValue) }
            guard !keys.isEmpty else { return [:] }
            let capacity = db.maximumStatementArgumentCount - 3
            var result: [OriginRecordID: Set<String>] = [:]
            for start in stride(from: 0, to: keys.count, by: capacity) {
                let group = Array(keys[start..<min(start + capacity, keys.count)])
                let parameters = Array(repeating: "?", count: group.count).joined(separator: ",")
                let rows = try Row.fetchAll(db, sql: """
                    SELECT c.origin_record_id, c.title, c.primary_text, m.remote_locator AS primary_media,
                        CASE WHEN r.fingerprint_generation = 2 THEN r.body_text
                             WHEN e.origin_revision_id IS NOT NULL THEN e.body_text
                             ELSE NULL END AS declared_body,
                        CASE WHEN r.fingerprint_generation = 2 OR e.origin_revision_id IS NOT NULL
                             THEN 1 ELSE 0 END AS body_observed
                    FROM published_cards c JOIN feed_segments s ON s.id = c.segment_id
                    LEFT JOIN origin_revisions r ON r.id = c.origin_revision_id
                    LEFT JOIN origin_revision_body_enrichment e ON e.origin_revision_id = c.origin_revision_id
                    LEFT JOIN media_candidates m ON m.origin_revision_id = c.origin_revision_id AND m.ordinal = 0 AND m.media_class = 'image'
                    WHERE s.edition_id = ? AND (s.ordinal, c.ordinal) <= (?, ?) AND c.origin_record_id IN (\(parameters))
                    """, arguments: StatementArguments([key as DatabaseValueConvertible, Int64(high.segmentOrdinal), Int64(high.cardOrdinal)] + group.map { $0 as DatabaseValueConvertible }))
                for row in rows {
                    let fields = PublicationRecordFields(row)
                    let origin = OriginRecordID(rawValue: try fields.uuid("origin_record_id"))
                    result[origin, default: []].insert(Self.materialKey(title: try fields.optionalString("title"),
                        primaryText: try fields.optionalString("primary_text"), primaryMedia: try fields.optionalString("primary_media"),
                        declaredBody: try fields.optionalString("declared_body"),
                        bodyObserved: (try fields.integer("body_observed")) == 1))
                }
            }
            return result
        }
    }

    public enum ProbeCountRecord: Hashable, Sendable {
        case exact(Int)
        case atLeast(Int)
    }

    public struct ReadyAheadRecord: Hashable, Sendable {
        public let editionID: FeedEditionID
        public let anchorCardID: PublicationCardID
        public let observedTailCardID: PublicationCardID
        public let amount: ProbeCountRecord
    }

    public enum ForwardAdvanceRecord: Hashable, Sendable {
        case same
        case backward
        case forwardExact(Int)
        case forwardBeyondProbe(Int)
    }

    public func readyAhead(editionID: FeedEditionID, anchorCardID: PublicationCardID,
        probeBound: Int) throws -> ReadyAheadRecord {
        let limit = try Self.probeLimit(probeBound)
        return try database.read { db in
            let editionKey = PersistenceValueCoding.uuid(editionID.rawValue)
            let schema = try Self.historySchema(editionKey, in: db)
            let anchor = try Self.historyPosition(anchorCardID, editionKey: editionKey, schema: schema, in: db)
            let tail = try Self.historyTail(editionKey: editionKey, schema: schema, in: db)
            guard !tail.isBefore(anchor) else { throw PublicationStoreError.corruption("tail before anchor") }
            let positions = try Self.probePositions(after: anchor, through: tail,
                editionKey: editionKey, limit: limit, in: db)
            let amount: ProbeCountRecord = positions.count > probeBound ? .atLeast(probeBound) : .exact(positions.count)
            return ReadyAheadRecord(editionID: editionID, anchorCardID: anchorCardID,
                observedTailCardID: tail.cardID, amount: amount)
        }
    }

    public struct ExposureRecord: Hashable, Sendable {
        public let observedTailCardID: PublicationCardID
        public let publishedOriginIDs: Set<OriginRecordID>
        /// Material keys (`materialKey`) of every occurrence of each requested published origin.
        public let publishedMaterialKeys: [OriginRecordID: Set<String>]
        /// Requested published origins not yet reached by confirmed visual seen high-water (PD-1 rule 2).
        public let unseenOriginIDs: Set<OriginRecordID>
    }

    public func exposure(editionID: FeedEditionID, originIDs: [OriginRecordID]) throws -> ExposureRecord {
        try database.read { db in
            let editionKey = PersistenceValueCoding.uuid(editionID.rawValue)
            let schema = try Self.historySchema(editionKey, in: db)
            let tail = try Self.historyTail(editionKey: editionKey, schema: schema, in: db)
            let material = try Self.publishedMaterial(originIDs, editionID: editionID, in: db)
            // Absence of a visual high-water is not proof that a projected or
            // restored reader anchor was seen. Until viewport evidence advances
            // the high-water, every published occurrence remains ahead.
            var unseen = Set(material.keys)
            if !material.isEmpty,
                let water = try String.fetchOne(db, sql: "SELECT high_water_card_id FROM edition_reading_state WHERE edition_id = ?", arguments: [editionKey]) {
                let anchor = try Self.historyPosition(
                    PublicationCardID(rawValue: PublicationValueCoding.uuid(water, field: "high_water_card_id")),
                    editionKey: editionKey, schema: schema, in: db)
                unseen.removeAll()
                let keys = material.keys.map { PersistenceValueCoding.uuid($0.rawValue) }
                let capacity = db.maximumStatementArgumentCount - 3
                guard capacity > 0 else { throw PublicationStoreError.invalidCapacity }
                for start in stride(from: 0, to: keys.count, by: capacity) {
                    let group = Array(keys[start..<min(start + capacity, keys.count)])
                    let placeholders = Array(repeating: "?", count: group.count).joined(separator: ",")
                    let values = try String.fetchAll(db, sql: """
                        SELECT DISTINCT c.origin_record_id FROM published_cards c
                        JOIN feed_segments s ON s.id = c.segment_id
                        WHERE c.origin_record_id IN (\(placeholders)) AND s.edition_id = ? AND (s.ordinal, c.ordinal) > (?, ?)
                        """, arguments: StatementArguments(group.map { $0 as DatabaseValueConvertible }
                            + [editionKey, Int64(anchor.segmentOrdinal), Int64(anchor.cardOrdinal)]))
                    for value in values { unseen.insert(OriginRecordID(rawValue: try PublicationValueCoding.uuid(value, field: "origin_record_id"))) }
                }
            }
            return ExposureRecord(observedTailCardID: tail.cardID,
                publishedOriginIDs: Set(material.keys), publishedMaterialKeys: material, unseenOriginIDs: unseen)
        }
    }

    public func forwardAdvance(editionID: FeedEditionID, fromCardID: PublicationCardID,
        toCardID: PublicationCardID, probeBound: Int) throws -> ForwardAdvanceRecord {
        let limit = try Self.probeLimit(probeBound)
        return try database.read { db in
            let editionKey = PersistenceValueCoding.uuid(editionID.rawValue)
            let schema = try Self.historySchema(editionKey, in: db)
            let from = try Self.historyPosition(fromCardID, editionKey: editionKey, schema: schema, in: db)
            let to = try Self.historyPosition(toCardID, editionKey: editionKey, schema: schema, in: db)
            if fromCardID == toCardID { return .same }
            if to.isBefore(from) { return .backward }
            let positions = try Self.probePositions(after: from, through: to,
                editionKey: editionKey, limit: limit, in: db)
            return positions.count > probeBound ? .forwardBeyondProbe(probeBound) : .forwardExact(positions.count)
        }
    }

    struct HistoryPosition {
        let segmentKey: String
        let segmentOrdinal: UInt64
        let cardOrdinal: UInt64
        let cardID: PublicationCardID

        func isBefore(_ other: Self) -> Bool {
            (segmentOrdinal, cardOrdinal) < (other.segmentOrdinal, other.cardOrdinal)
        }
    }

    static func historyTail(editionKey: String, schema: UInt64, in db: Database) throws -> HistoryPosition {
        guard let segment = try Row.fetchOne(db, sql: """
            SELECT id, ordinal, publication_schema_version FROM feed_segments
            WHERE edition_id = ? ORDER BY ordinal DESC LIMIT 1
            """, arguments: [editionKey]) else { throw PublicationStoreError.corruption("empty edition") }
        let fields = PublicationRecordFields(segment)
        guard try fields.counter("publication_schema_version") == schema else {
            throw PublicationStoreError.corruption("tail publication schema")
        }
        let segmentKey = try fields.string("id")
        guard let row = try Row.fetchOne(db, sql: """
            SELECT id, ordinal FROM published_cards
            WHERE segment_id = ? ORDER BY ordinal DESC LIMIT 1
            """, arguments: [segmentKey]) else { throw PublicationStoreError.corruption("empty tail segment") }
        let card = PublicationRecordFields(row)
        return HistoryPosition(segmentKey: segmentKey, segmentOrdinal: try fields.counter("ordinal"),
            cardOrdinal: try card.counter("ordinal"), cardID: PublicationCardID(rawValue: try card.uuid("id")))
    }

    private static func probeLimit(_ bound: Int) throws -> Int {
        guard bound > 0, bound < Int.max, Int64(exactly: bound + 1) != nil else {
            throw PublicationStoreError.invalidCapacity
        }
        return bound + 1
    }

    private static func historySchema(_ editionKey: String, in db: Database) throws -> UInt64 {
        guard let row = try Row.fetchOne(db, sql: "SELECT publication_schema_version FROM feed_editions WHERE id = ?",
            arguments: [editionKey]) else { throw PublicationStoreError.missingEdition }
        return try PublicationRecordFields(row).counter("publication_schema_version")
    }

    private static func historyPosition(_ cardID: PublicationCardID, editionKey: String,
        schema: UInt64, in db: Database) throws -> HistoryPosition {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT c.id, c.segment_id, c.ordinal, s.ordinal AS segment_ordinal,
                s.edition_id, s.publication_schema_version
            FROM published_cards c JOIN feed_segments s ON s.id = c.segment_id WHERE c.id = ?
            """, arguments: [PersistenceValueCoding.uuid(cardID.rawValue)]) else {
            throw PublicationStoreError.corruption("occurrence membership")
        }
        let fields = PublicationRecordFields(row)
        guard try fields.string("edition_id") == editionKey,
            try fields.counter("publication_schema_version") == schema else {
            throw PublicationStoreError.corruption("occurrence membership/schema")
        }
        return HistoryPosition(segmentKey: try fields.string("segment_id"),
            segmentOrdinal: try fields.counter("segment_ordinal"), cardOrdinal: try fields.counter("ordinal"), cardID: cardID)
    }

    /// At most limit occurrence positions total. Each later-segment seek is LIMIT 1;
    /// nonempty immutable segments make the number of seeks bounded by returned positions.
    private static func probePositions(after from: HistoryPosition, through to: HistoryPosition,
        editionKey: String, limit: Int, in db: Database) throws -> [PublicationCardID] {
        var ids: [PublicationCardID] = []
        var segmentKey = from.segmentKey, segmentOrdinal = from.segmentOrdinal
        var lower = Int64(from.cardOrdinal)
        while ids.count < limit {
            let upper = segmentOrdinal == to.segmentOrdinal ? Int64(to.cardOrdinal) : Int64.max
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, ordinal FROM published_cards
                WHERE segment_id = ? AND ordinal > ? AND ordinal <= ?
                ORDER BY ordinal ASC LIMIT ?
                """, arguments: [segmentKey, lower, upper, limit - ids.count])
            if lower == -1, rows.isEmpty { throw PublicationStoreError.corruption("empty probe segment") }
            for row in rows {
                let fields = PublicationRecordFields(row)
                _ = try fields.counter("ordinal")
                ids.append(PublicationCardID(rawValue: try fields.uuid("id")))
            }
            if ids.count == limit { break }
            if segmentOrdinal == to.segmentOrdinal {
                guard from.cardID == to.cardID || ids.last == to.cardID else {
                    throw PublicationStoreError.corruption("probe destination")
                }
                break
            }
            guard let segment = try Row.fetchOne(db, sql: """
                SELECT id, ordinal FROM feed_segments
                WHERE edition_id = ? AND ordinal > ? AND ordinal <= ?
                ORDER BY ordinal ASC LIMIT 1
                """, arguments: [editionKey, Int64(segmentOrdinal), Int64(to.segmentOrdinal)]) else {
                throw PublicationStoreError.corruption("probe segment membership")
            }
            let fields = PublicationRecordFields(segment)
            segmentKey = try fields.string("id")
            segmentOrdinal = try fields.counter("ordinal")
            lower = -1
        }
        return ids
    }

}
