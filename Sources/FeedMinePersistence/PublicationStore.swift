// File: PublicationStore.swift
// Module: FeedMinePersistence
// Owns: concrete atomic immutable history storage and mechanical boundary records.
// Does not own: publication semantics, rendering, coordination, canonical data or retention.
// Dependencies: FeedMineDomain, Foundation and private GRDB access only.

import Foundation
import GRDB
import FeedMineDomain

public enum PublicationStoreError: Error, Equatable, Sendable {
    case invalidRepresentation(String)
    case missingEdition
    case editorialRevisionConflict
    case invalidInitialCheckpoint
    case invalidFirstSegment
    case invalidAppendOrdinal
    case publicationSchemaMismatch
    case cardIdentityMismatch
    case corruption(String)
    case invalidCapacity
    case staleHistoryExpectation
    case duplicateOriginInEdition
}

public struct PublicationStore: Sendable {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    public struct EditionRecord: Hashable, Sendable {
        public let id: FeedEditionID
        public let editorialRevision: EditorialRevision
        public let publicationSchemaVersion: UInt64
        public let selectionSeed: UInt64
        public let createdAt: Date

        public init(
            id: FeedEditionID,
            editorialRevision: EditorialRevision,
            publicationSchemaVersion: UInt64,
            selectionSeed: UInt64,
            createdAt: Date
        ) {
            self.id = id
            self.editorialRevision = editorialRevision
            self.publicationSchemaVersion = publicationSchemaVersion
            self.selectionSeed = selectionSeed
            self.createdAt = createdAt
        }
    }

    public struct SegmentRecord: Hashable, Sendable {
        public let id: FeedSegmentID
        public let editionID: FeedEditionID
        public let ordinal: UInt64
        public let segmentSeed: UInt64
        public let publicationSchemaVersion: UInt64
        public let createdAt: Date
        public let cardIDs: [PublicationCardID]

        public init(
            id: FeedSegmentID,
            editionID: FeedEditionID,
            ordinal: UInt64,
            segmentSeed: UInt64,
            publicationSchemaVersion: UInt64,
            createdAt: Date,
            cardIDs: [PublicationCardID]
        ) {
            self.id = id
            self.editionID = editionID
            self.ordinal = ordinal
            self.segmentSeed = segmentSeed
            self.publicationSchemaVersion = publicationSchemaVersion
            self.createdAt = createdAt
            self.cardIDs = cardIDs
        }
    }

    public struct CardRecord: Hashable, Sendable {
        public let id: PublicationCardID
        public let originRecordID: OriginRecordID
        public let originRevisionID: OriginRevisionID
        public let sourceID: SourceID?
        public let providerID: ProviderID?
        public let sourceDisplayName: String?
        public let providerDisplayName: String?
        public let contentEntityID: ContentEntityID?
        public let contentClusterID: ContentClusterID?
        public let title: String?
        public let primaryText: String?
        public let timestampValue: Date?
        public let timestampKind: String?
        public let mediaKey: String?
        public let mediaPixelWidth: Int?
        public let mediaPixelHeight: Int?
        public let mediaMimeType: String?
        public let renderLayout: String
        public let renderMediaAspectRatio: Double?
        public let primaryActionKind: String?
        public let primaryActionReference: String?

        public init(
            id: PublicationCardID,
            originRecordID: OriginRecordID,
            originRevisionID: OriginRevisionID,
            sourceID: SourceID?,
            providerID: ProviderID?,
            sourceDisplayName: String?,
            providerDisplayName: String?,
            contentEntityID: ContentEntityID?,
            contentClusterID: ContentClusterID?,
            title: String?,
            primaryText: String?,
            timestampValue: Date?,
            timestampKind: String?,
            mediaKey: String?,
            mediaPixelWidth: Int?,
            mediaPixelHeight: Int?,
            mediaMimeType: String?,
            renderLayout: String,
            renderMediaAspectRatio: Double?,
            primaryActionKind: String?,
            primaryActionReference: String?
        ) {
            self.id = id
            self.originRecordID = originRecordID
            self.originRevisionID = originRevisionID
            self.sourceID = sourceID
            self.providerID = providerID
            self.sourceDisplayName = sourceDisplayName
            self.providerDisplayName = providerDisplayName
            self.contentEntityID = contentEntityID
            self.contentClusterID = contentClusterID
            self.title = title
            self.primaryText = primaryText
            self.timestampValue = timestampValue
            self.timestampKind = timestampKind
            self.mediaKey = mediaKey
            self.mediaPixelWidth = mediaPixelWidth
            self.mediaPixelHeight = mediaPixelHeight
            self.mediaMimeType = mediaMimeType
            self.renderLayout = renderLayout
            self.renderMediaAspectRatio = renderMediaAspectRatio
            self.primaryActionKind = primaryActionKind
            self.primaryActionReference = primaryActionReference
        }
    }

    public func createEdition(_ edition: EditionRecord, firstSegment: SegmentRecord, cards: [CardRecord]) throws {
        try database.write { db in
            try Self.insertEditionAndFirstSegment(edition, firstSegment: firstSegment, cards: cards, in: db)
        }
    }

    public func createInitialEdition(_ edition: EditionRecord, firstSegment: SegmentRecord,
        cards: [CardRecord], initialCheckpoint: SessionStore.CheckpointRecord) throws {
        try database.write { db in
            guard firstSegment.editionID == edition.id, firstSegment.ordinal == 0,
                initialCheckpoint.editionID == edition.id,
                firstSegment.cardIDs.contains(initialCheckpoint.cardID) else {
                throw PublicationStoreError.invalidInitialCheckpoint
            }
            try Self.insertEditionAndFirstSegment(edition, firstSegment: firstSegment, cards: cards, in: db)
            try SessionStore.insertInitialCheckpoint(initialCheckpoint, in: db)
        }
    }

    private static func insertEditionAndFirstSegment(_ edition: EditionRecord,
        firstSegment: SegmentRecord, cards: [CardRecord], in db: Database) throws {
        guard firstSegment.editionID == edition.id, firstSegment.ordinal == 0 else {
            throw PublicationStoreError.invalidFirstSegment
        }
        try Self.validate(firstSegment, cards: cards, version: edition.publicationSchemaVersion)
        let editionValues = try Self.editionValues(edition)
        let existing = try Row.fetchAll(db, sql: "SELECT * FROM feed_editions WHERE editorial_revision_id = ?",
            arguments: [PersistenceValueCoding.uuid(edition.editorialRevision.id.rawValue)])
        for row in existing {
            guard try Self.decodeEdition(row).editorialRevision == edition.editorialRevision else {
                throw PublicationStoreError.editorialRevisionConflict
            }
        }
        try Self.insert(db, table: "feed_editions", columns: Self.editionColumns, values: editionValues)
        try Self.insertSegment(firstSegment, cards: cards, db: db)
    }

    public func appendSegment(_ segment: SegmentRecord, cards: [CardRecord]) throws {
        try appendSegment(segment, cards: cards, expectedTail: nil, recurrence: .forbidden)
    }

    public func appendSegment(_ segment: SegmentRecord, cards: [CardRecord],
        expectingTailCardID: PublicationCardID, recurrence: OriginRecurrenceRecord = .forbidden) throws {
        try appendSegment(segment, cards: cards, expectedTail: expectingTailCardID, recurrence: recurrence)
    }

    /// Whether an origin already published in the Edition may occur again (PD-1).
    public enum OriginRecurrenceRecord: Hashable, Sendable {
        /// Phase 3R5: at most one occurrence per origin in an Edition.
        case forbidden
        /// PD-1: an origin may occur again only with materially different text.
        case whenMaterialChanged
    }

    /// Material identity of an occurrence: whitespace-collapsed title and primary text, plus the
    /// revision's primary media locator (review F07 / PD-1: a new primary image is material).
    /// Editorial computes the identical key from candidate facts (`SelectionExposureSnapshot`).
    public static func materialKey(title: String?, primaryText: String?, primaryMedia: String? = nil) -> String {
        MaterialContentIdentity.key(title: title, text: primaryText, primaryMedia: primaryMedia)
    }

    /// Ordinal-0 canonical media locator of a revision; immutable, so both sides agree.
    static func primaryMediaLocator(_ revision: OriginRevisionID, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT remote_locator FROM media_candidates WHERE origin_revision_id = ? AND ordinal = 0 AND media_class = 'image'",
            arguments: [PersistenceValueCoding.uuid(revision.rawValue)])
    }

    private func appendSegment(_ segment: SegmentRecord, cards: [CardRecord],
        expectedTail: PublicationCardID?, recurrence: OriginRecurrenceRecord) throws {
        try database.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM feed_editions WHERE id = ?",
                arguments: [PersistenceValueCoding.uuid(segment.editionID.rawValue)]) else { throw PublicationStoreError.missingEdition }
            let edition = try Self.decodeEdition(row)
            // Read and validate the actual tail within the serialized writer transaction.
            let tail: TailRecord
            if let expectedTail {
                let actual = try Self.historyTail(editionKey: PersistenceValueCoding.uuid(segment.editionID.rawValue),
                    schema: edition.publicationSchemaVersion, in: db)
                guard actual.cardID == expectedTail else { throw PublicationStoreError.staleHistoryExpectation }
                tail = TailRecord(ordinal: actual.segmentOrdinal)
            } else {
                tail = try Self.readTail(editionID: segment.editionID,
                    schemaVersion: edition.publicationSchemaVersion, in: db)
            }
            guard tail.ordinal < UInt64(Int64.max), segment.ordinal == tail.ordinal + 1 else {
                throw PublicationStoreError.invalidAppendOrdinal
            }
            try Self.validate(segment, cards: cards, version: edition.publicationSchemaVersion)
            switch recurrence {
            case .forbidden:
                guard try Self.publishedOrigins(cards.map(\.originRecordID), editionID: segment.editionID, in: db).isEmpty else {
                    throw PublicationStoreError.duplicateOriginInEdition
                }
            case .whenMaterialChanged:
                let published = try Self.publishedMaterial(cards.map(\.originRecordID), editionID: segment.editionID, in: db)
                for card in cards where published[card.originRecordID]?
                    .contains(Self.materialKey(title: card.title, primaryText: card.primaryText,
                        primaryMedia: try Self.primaryMediaLocator(card.originRevisionID, in: db))) == true {
                    throw PublicationStoreError.duplicateOriginInEdition
                }
            }
            try Self.insertSegment(segment, cards: cards, db: db)
        }
    }

    public struct HiddenTailLease: Hashable, Sendable {
        public let editionID: FeedEditionID
        public let generation: Int64
        public let highWaterCardID: PublicationCardID
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
    public func setVisibility(editionID: FeedEditionID, visible: Bool) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE edition_reading_state SET visible = ?, generation = generation + 1 WHERE edition_id = ?",
                arguments: [visible ? 1 : 0, PersistenceValueCoding.uuid(editionID.rawValue)])
        }
    }
    public func hiddenTail(editionID: FeedEditionID) throws -> HiddenTailLease? {
        try database.write { db in
            let key = PersistenceValueCoding.uuid(editionID.rawValue)
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM edition_reading_state WHERE edition_id = ?", arguments: [key]) else { return nil }
            let card = PublicationCardID(rawValue: try PublicationValueCoding.uuid(row["high_water_card_id"], field: "high_water_card_id"))
            let generation: Int64 = row["generation"]
            let tail = try Self.historyTail(editionKey: key, schema: Self.historySchema(key, in: db), in: db)
            try db.execute(sql: "UPDATE edition_reading_state SET visible = 0, generation = generation + 1 WHERE edition_id = ?", arguments: [key])
            return HiddenTailLease(editionID: editionID, generation: generation + 1, highWaterCardID: card, expectedTailCardID: tail.cardID)
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
            let high = try Self.historyPosition(lease.highWaterCardID, editionKey: key, schema: schema, in: db)
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
                    SELECT c.origin_record_id, c.title, c.primary_text, m.remote_locator AS primary_media
                    FROM published_cards c JOIN feed_segments s ON s.id = c.segment_id
                    LEFT JOIN media_candidates m ON m.origin_revision_id = c.origin_revision_id AND m.ordinal = 0 AND m.media_class = 'image'
                    WHERE s.edition_id = ? AND (s.ordinal, c.ordinal) <= (?, ?) AND c.origin_record_id IN (\(parameters))
                    """, arguments: StatementArguments([key as DatabaseValueConvertible, Int64(high.segmentOrdinal), Int64(high.cardOrdinal)] + group.map { $0 as DatabaseValueConvertible }))
                for row in rows {
                    let fields = PublicationRecordFields(row)
                    let origin = OriginRecordID(rawValue: try fields.uuid("origin_record_id"))
                    result[origin, default: []].insert(Self.materialKey(title: try fields.optionalString("title"),
                        primaryText: try fields.optionalString("primary_text"), primaryMedia: try fields.optionalString("primary_media")))
                }
            }
            return result
        }
    }

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

    private static func readTail(editionID: FeedEditionID, schemaVersion: UInt64, in db: Database) throws -> TailRecord {
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
        return try database.read { db in
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
            let backward = try Row.fetchAll(db, sql: query + "< (?, ?) ORDER BY s.ordinal DESC, c.ordinal DESC LIMIT ?",
                arguments: [editionKey, segmentOrdinal, cardOrdinal, backwardCapacity])
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
            let requiredFirst = backward.count < backwardCapacity ? 0 : firstPosition
            let requiredLast = forward.count < forwardCapacity ? high : lastPosition
            let crossed = try Row.fetchAll(db, sql: "SELECT * FROM feed_segments WHERE edition_id = ? AND ordinal BETWEEN ? AND ? ORDER BY ordinal", arguments: [editionKey, requiredFirst, requiredLast])
            for row in crossed {
                let segment = try Self.decodeSegment(row, db: db)
                guard segment.publicationSchemaVersion == edition.publicationSchemaVersion else { throw PublicationStoreError.corruption("segment schema") }
            }
            return try rows.map(Self.decodeCard)
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
        /// Requested origins with an occurrence positioned after the reader anchor (PD-1 rule 2).
        public let unseenOriginIDs: Set<OriginRecordID>
    }

    public func exposure(editionID: FeedEditionID, originIDs: [OriginRecordID],
        readerAnchorCardID: PublicationCardID? = nil) throws -> ExposureRecord {
        try database.read { db in
            let editionKey = PersistenceValueCoding.uuid(editionID.rawValue)
            let schema = try Self.historySchema(editionKey, in: db)
            let tail = try Self.historyTail(editionKey: editionKey, schema: schema, in: db)
            let material = try Self.publishedMaterial(originIDs, editionID: editionID, in: db)
            var unseen = Set<OriginRecordID>()
            if let readerAnchorCardID, !material.isEmpty {
                var anchor = try Self.historyPosition(readerAnchorCardID, editionKey: editionKey, schema: schema, in: db)
                if let water = try String.fetchOne(db, sql: "SELECT high_water_card_id FROM edition_reading_state WHERE edition_id = ?", arguments: [editionKey]) {
                    let high = try Self.historyPosition(PublicationCardID(rawValue: PublicationValueCoding.uuid(water, field: "high_water_card_id")), editionKey: editionKey, schema: schema, in: db)
                    if anchor.isBefore(high) { anchor = high }
                }
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

    private static func publishedMaterial(_ ids: [OriginRecordID], editionID: FeedEditionID,
        in db: Database) throws -> [OriginRecordID: Set<String>] {
        let keys = Array(Set(ids)).map { PersistenceValueCoding.uuid($0.rawValue) }
        let capacity = db.maximumStatementArgumentCount - 1
        guard capacity > 0 else { throw PublicationStoreError.invalidCapacity }
        var found: [OriginRecordID: Set<String>] = [:]
        for start in stride(from: 0, to: keys.count, by: capacity) {
            let group = Array(keys[start..<min(start + capacity, keys.count)])
            let placeholders = Array(repeating: "?", count: group.count).joined(separator: ",")
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.origin_record_id, c.title, c.primary_text, m.remote_locator AS primary_media FROM published_cards c
                JOIN feed_segments s ON s.id = c.segment_id
                LEFT JOIN media_candidates m ON m.origin_revision_id = c.origin_revision_id AND m.ordinal = 0 AND m.media_class = 'image'
                WHERE c.origin_record_id IN (\(placeholders)) AND s.edition_id = ?
                """, arguments: StatementArguments(group + [PersistenceValueCoding.uuid(editionID.rawValue)]))
            for row in rows {
                let fields = PublicationRecordFields(row)
                let origin = OriginRecordID(rawValue: try fields.uuid("origin_record_id"))
                found[origin, default: []].insert(materialKey(title: try fields.optionalString("title"),
                    primaryText: try fields.optionalString("primary_text"), primaryMedia: try fields.optionalString("primary_media")))
            }
        }
        return found
    }

    // Shared by the bounded exposure read and the serialized pre-insert guard.
    // Chunk only at SQLite's actual parameter limit; never one query per candidate.
    private static func publishedOrigins(_ ids: [OriginRecordID], editionID: FeedEditionID,
        in db: Database) throws -> Set<OriginRecordID> {
        let keys = Array(Set(ids)).map { PersistenceValueCoding.uuid($0.rawValue) }
        let capacity = db.maximumStatementArgumentCount - 1
        guard capacity > 0 else { throw PublicationStoreError.invalidCapacity }
        var found = Set<OriginRecordID>()
        for start in stride(from: 0, to: keys.count, by: capacity) {
            let group = Array(keys[start..<min(start + capacity, keys.count)])
            let placeholders = Array(repeating: "?", count: group.count).joined(separator: ",")
            let values = try String.fetchAll(db, sql: """
                SELECT DISTINCT c.origin_record_id FROM published_cards c
                JOIN feed_segments s ON s.id = c.segment_id
                WHERE c.origin_record_id IN (\(placeholders)) AND s.edition_id = ?
                """, arguments: StatementArguments(group + [PersistenceValueCoding.uuid(editionID.rawValue)]))
            for value in values {
                guard let uuid = UUID(uuidString: value), PersistenceValueCoding.uuid(uuid) == value else {
                    throw PublicationStoreError.corruption("origin_record_id")
                }
                found.insert(OriginRecordID(rawValue: uuid))
            }
        }
        return found
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

    private struct HistoryPosition {
        let segmentKey: String
        let segmentOrdinal: UInt64
        let cardOrdinal: UInt64
        let cardID: PublicationCardID

        func isBefore(_ other: Self) -> Bool {
            (segmentOrdinal, cardOrdinal) < (other.segmentOrdinal, other.cardOrdinal)
        }
    }

    private static func historyTail(editionKey: String, schema: UInt64, in db: Database) throws -> HistoryPosition {
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

    private static func validate(_ segment: SegmentRecord, cards: [CardRecord], version: UInt64) throws {
        guard segment.publicationSchemaVersion == version else { throw PublicationStoreError.publicationSchemaMismatch }
        guard !cards.isEmpty, segment.cardIDs == cards.map(\.id), Set(segment.cardIDs).count == segment.cardIDs.count else {
            throw PublicationStoreError.cardIdentityMismatch
        }
        _ = try segmentValues(segment)
        for card in cards { try validateCard(card); _ = try cardValues(card) }
        guard Set(cards.map(\.originRecordID)).count == cards.count else {
            throw PublicationStoreError.duplicateOriginInEdition
        }
    }

    private static func validateCard(_ card: CardRecord) throws {
        func require(_ condition: Bool, _ field: String) throws {
            guard condition else { throw PublicationStoreError.invalidRepresentation(field) }
        }
        try require((card.timestampValue == nil && card.timestampKind == nil)
            || (card.timestampValue != nil && ["authored", "modified", "observed"].contains(card.timestampKind ?? "")), "timestamp")
        if let key = card.mediaKey {
            try require(!key.isEmpty, "media_key")
            try require((card.mediaPixelWidth == nil && card.mediaPixelHeight == nil)
                || ((card.mediaPixelWidth ?? 0) > 0 && (card.mediaPixelHeight ?? 0) > 0), "media dimensions")
        } else {
            try require(card.mediaPixelWidth == nil && card.mediaPixelHeight == nil && card.mediaMimeType == nil, "media group")
        }
        try require(["hero", "thumbnail", "textOnly"].contains(card.renderLayout), "render_layout")
        if let ratio = card.renderMediaAspectRatio { try require(ratio.isFinite && ratio > 0, "render ratio") }
        try require(card.renderLayout != "textOnly" || (card.mediaKey == nil && card.renderMediaAspectRatio == nil), "textOnly media")
        switch card.primaryActionKind {
        case nil: try require(card.primaryActionReference == nil, "action")
        case "localContentDetail": try require(card.primaryActionReference == nil, "action")
        case "externalURL", "mediaPlayback":
            guard let reference = card.primaryActionReference, let url = URL(string: reference), url.absoluteString == reference else {
                throw PublicationStoreError.invalidRepresentation("action URL")
            }
        default: throw PublicationStoreError.invalidRepresentation("action kind")
        }
    }

    // These insert envelopes are private. No public row type or generic CRUD API escapes.
    private static func insert(_ db: Database, table: String, columns: [String], values: [DatabaseValue]) throws {
        let marks = Array(repeating: "?", count: columns.count).joined(separator: ",")
        try db.execute(sql: "INSERT INTO \(table) (\(columns.joined(separator: ","))) VALUES (\(marks))", arguments: StatementArguments(values))
    }

    private static func insertSegment(_ segment: SegmentRecord, cards: [CardRecord], db: Database) throws {
        try insert(db, table: "feed_segments", columns: segmentColumns, values: segmentValues(segment))
        for (ordinal, card) in cards.enumerated() {
            try insert(db, table: "published_cards", columns: ["segment_id", "ordinal"] + cardColumns,
                values: [PersistenceValueCoding.uuid(segment.id.rawValue).databaseValue, Int64(ordinal).databaseValue] + cardValues(card))
        }
    }

    private static let editionColumns = ["id", "editorial_revision_id", "context_kind", "context_source_id", "context_search_query", "catalog_generation", "user_selection_version", "eligibility_policy_version", "scoring_policy_version", "sequencing_policy_version", "exposure_policy_version", "selection_schema_version", "publication_schema_version", "selection_seed", "created_at", "context_identity", "context_key_json"]
    private static let segmentColumns = ["id", "edition_id", "ordinal", "segment_seed", "publication_schema_version", "created_at"]
    private static func editionValues(_ e: EditionRecord) throws -> [DatabaseValue] {
        let r = e.editorialRevision
        let kind: String, source: String?, query: String?
        switch r.contextKey.request {
        case .main: kind = "main"; source = nil; query = nil
        case .source(let id): kind = "source"; source = PersistenceValueCoding.uuid(id.rawValue); query = nil
        case .search(let search): kind = "search"; source = nil; query = search.query
        }
        // T6: the Edition records the whole context identity it belongs to, in both the matching form and
        // the reversible form, so a filtered context survives a read (spec §6).
        let identity = r.contextKey.canonicalIdentity.databaseValue
        let identityJSON = (r.contextKey.canonicalJSON() ?? "").databaseValue
        return try [
            PersistenceValueCoding.uuid(e.id.rawValue).databaseValue,
            PersistenceValueCoding.uuid(r.id.rawValue).databaseValue,
            kind.databaseValue, source.databaseValue, query.databaseValue,
            PublicationValueCoding.counter(r.catalogGeneration.rawValue, field: "catalogGeneration").databaseValue,
            PublicationValueCoding.counter(r.userSelectionVersion.rawValue, field: "userSelectionVersion").databaseValue,
            PublicationValueCoding.counter(r.eligibilityPolicyVersion.rawValue, field: "eligibilityPolicyVersion").databaseValue,
            PublicationValueCoding.counter(r.scoringPolicyVersion.rawValue, field: "scoringPolicyVersion").databaseValue,
            PublicationValueCoding.counter(r.sequencingPolicyVersion.rawValue, field: "sequencingPolicyVersion").databaseValue,
            PublicationValueCoding.counter(r.exposurePolicyVersion.rawValue, field: "exposurePolicyVersion").databaseValue,
            PublicationValueCoding.counter(r.selectionSchemaVersion.rawValue, field: "selectionSchemaVersion").databaseValue,
            PublicationValueCoding.counter(e.publicationSchemaVersion, field: "publication_schema_version").databaseValue,
            PersistenceValueCoding.seed(e.selectionSeed).databaseValue,
            PublicationValueCoding.date(e.createdAt, field: "created_at").databaseValue,
            identity, identityJSON
        ]
    }

    private static func segmentValues(_ s: SegmentRecord) throws -> [DatabaseValue] {
        try [PersistenceValueCoding.uuid(s.id.rawValue).databaseValue,
             PersistenceValueCoding.uuid(s.editionID.rawValue).databaseValue,
             PublicationValueCoding.counter(s.ordinal, field: "ordinal").databaseValue,
             PersistenceValueCoding.seed(s.segmentSeed).databaseValue,
             PublicationValueCoding.counter(s.publicationSchemaVersion, field: "publication_schema_version").databaseValue,
             PublicationValueCoding.date(s.createdAt, field: "created_at").databaseValue]
    }

    private static func decodeEdition(_ row: Row) throws -> EditionRecord {
        let f = PublicationRecordFields(row)
        let request: FeedContextRequest
        let source = try f.optionalUUID("context_source_id"), query = try f.optionalString("context_search_query")
        switch try f.string("context_kind") {
        case "main" where source == nil && query == nil: request = .main
        case "source" where source != nil && query == nil: request = .source(SourceID(rawValue: source!))
        case "search" where source == nil && query != nil:
            guard let search = SearchContext(query: query!) else { throw PublicationStoreError.corruption("search context") }
            request = .search(search)
        default: throw PublicationStoreError.corruption("context")
        }
        // T6: a row written with an identity restores its exact key (filter, preset and scope included);
        // a row from before the migration restores the default surface it recorded.
        let storedIdentity = (row["context_key_json"] as String?) ?? ""
        let contextKey = ContextKey.fromCanonicalJSON(storedIdentity) ?? ContextKey(request: request)
        let revision = EditorialRevision(id: EditorialRevisionID(rawValue: try f.uuid("editorial_revision_id")),
            contextKey: contextKey,
            catalogGeneration: CatalogGeneration(rawValue: try f.counter("catalog_generation")),
            userSelectionVersion: PolicyVersion(rawValue: try f.counter("user_selection_version")),
            eligibilityPolicyVersion: PolicyVersion(rawValue: try f.counter("eligibility_policy_version")),
            scoringPolicyVersion: PolicyVersion(rawValue: try f.counter("scoring_policy_version")),
            sequencingPolicyVersion: PolicyVersion(rawValue: try f.counter("sequencing_policy_version")),
            exposurePolicyVersion: PolicyVersion(rawValue: try f.counter("exposure_policy_version")),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: try f.counter("selection_schema_version")))
        return EditionRecord(id: FeedEditionID(rawValue: try f.uuid("id")), editorialRevision: revision,
            publicationSchemaVersion: try f.counter("publication_schema_version"),
            selectionSeed: PersistenceValueCoding.seed(try f.integer("selection_seed")), createdAt: try f.date("created_at"))
    }

    private static func decodeSegment(_ row: Row, db: Database) throws -> SegmentRecord {
        let f = PublicationRecordFields(row)
        let id = try f.uuid("id")
        let positions = try Row.fetchAll(db, sql: "SELECT id, ordinal FROM published_cards WHERE segment_id = ? ORDER BY ordinal", arguments: [PersistenceValueCoding.uuid(id)])
        guard !positions.isEmpty else { throw PublicationStoreError.corruption("empty segment") }
        let ids = try positions.enumerated().map { index, row -> PublicationCardID in
            let fields = PublicationRecordFields(row)
            guard try fields.counter("ordinal") == UInt64(index) else { throw PublicationStoreError.corruption("card ordinal") }
            return PublicationCardID(rawValue: try fields.uuid("id"))
        }
        guard Set(ids).count == ids.count else { throw PublicationStoreError.corruption("duplicate occurrence") }
        return SegmentRecord(id: FeedSegmentID(rawValue: id), editionID: FeedEditionID(rawValue: try f.uuid("edition_id")),
            ordinal: try f.counter("ordinal"), segmentSeed: PersistenceValueCoding.seed(try f.integer("segment_seed")),
            publicationSchemaVersion: try f.counter("publication_schema_version"), createdAt: try f.date("created_at"), cardIDs: ids)
    }
    private static let cardColumns = ["id", "origin_record_id", "origin_revision_id", "source_id", "provider_id", "source_display_name", "provider_display_name", "content_entity_id", "content_cluster_id", "title", "primary_text", "timestamp_value", "timestamp_kind", "media_key", "media_pixel_width", "media_pixel_height", "media_mime_type", "render_layout", "render_media_aspect_ratio", "primary_action_kind", "primary_action_reference"]
    private static func cardValues(_ c: CardRecord) throws -> [DatabaseValue] {
        try [
            (PersistenceValueCoding.uuid(c.id.rawValue)).databaseValue,
            (PersistenceValueCoding.uuid(c.originRecordID.rawValue)).databaseValue,
            (PersistenceValueCoding.uuid(c.originRevisionID.rawValue)).databaseValue,
            (c.sourceID.map { PersistenceValueCoding.uuid($0.rawValue) }).databaseValue,
            (c.providerID.map { PersistenceValueCoding.uuid($0.rawValue) }).databaseValue,
            (c.sourceDisplayName).databaseValue,
            (c.providerDisplayName).databaseValue,
            (c.contentEntityID.map { PersistenceValueCoding.uuid($0.rawValue) }).databaseValue,
            (c.contentClusterID.map { PersistenceValueCoding.uuid($0.rawValue) }).databaseValue,
            (c.title).databaseValue,
            (c.primaryText).databaseValue,
            (c.timestampValue.map { try PublicationValueCoding.date($0, field: "timestamp_value") }).databaseValue,
            (c.timestampKind).databaseValue,
            (c.mediaKey).databaseValue,
            (c.mediaPixelWidth).databaseValue,
            (c.mediaPixelHeight).databaseValue,
            (c.mediaMimeType).databaseValue,
            (c.renderLayout).databaseValue,
            (c.renderMediaAspectRatio).databaseValue,
            (c.primaryActionKind).databaseValue,
            (c.primaryActionReference).databaseValue
        ]
    }
    private static func decodeCard(_ row: Row) throws -> CardRecord {
        let f = PublicationRecordFields(row)
        let card = CardRecord(
            id: PublicationCardID(rawValue: try f.uuid("id")),
            originRecordID: OriginRecordID(rawValue: try f.uuid("origin_record_id")),
            originRevisionID: OriginRevisionID(rawValue: try f.uuid("origin_revision_id")),
            sourceID: try f.optionalUUID("source_id").map { SourceID(rawValue: $0) },
            providerID: try f.optionalUUID("provider_id").map { ProviderID(rawValue: $0) },
            sourceDisplayName: try f.optionalString("source_display_name"),
            providerDisplayName: try f.optionalString("provider_display_name"),
            contentEntityID: try f.optionalUUID("content_entity_id").map { ContentEntityID(rawValue: $0) },
            contentClusterID: try f.optionalUUID("content_cluster_id").map { ContentClusterID(rawValue: $0) },
            title: try f.optionalString("title"),
            primaryText: try f.optionalString("primary_text"),
            timestampValue: try f.optionalDate("timestamp_value"),
            timestampKind: try f.optionalString("timestamp_kind"),
            mediaKey: try f.optionalString("media_key"),
            mediaPixelWidth: try f.optionalInt("media_pixel_width"),
            mediaPixelHeight: try f.optionalInt("media_pixel_height"),
            mediaMimeType: try f.optionalString("media_mime_type"),
            renderLayout: try f.string("render_layout"),
            renderMediaAspectRatio: try f.optionalReal("render_media_aspect_ratio"),
            primaryActionKind: try f.optionalString("primary_action_kind"),
            primaryActionReference: try f.optionalString("primary_action_reference")
        )
        do { try validateCard(card) } catch { throw PublicationStoreError.corruption("card payload: \(error)") }
        return card
    }
}

// Internal scalar field checks shared by the two concrete stores; no row types escape.
struct PublicationRecordFields {
    let row: Row
    init(_ row: Row) { self.row = row }
    func value(_ field: String) -> DatabaseValue { row[field] }
    func optionalString(_ field: String) throws -> String? {
        switch value(field).storage {
        case .null: return nil
        case .string(let string): return string
        default: throw PublicationStoreError.corruption(field)
        }
    }
    func string(_ field: String) throws -> String {
        guard let string = try optionalString(field) else { throw PublicationStoreError.corruption(field) }
        return string
    }
    func integer(_ field: String) throws -> Int64 {
        guard case .int64(let integer) = value(field).storage else { throw PublicationStoreError.corruption(field) }
        return integer
    }
    func optionalInt(_ field: String) throws -> Int? {
        if case .null = value(field).storage { return nil }
        guard let integer = Int(exactly: try self.integer(field)) else { throw PublicationStoreError.corruption(field) }
        return integer
    }
    func optionalReal(_ field: String) throws -> Double? {
        switch value(field).storage {
        case .null: return nil
        case .double(let real) where real.isFinite: return real
        default: throw PublicationStoreError.corruption(field)
        }
    }
    func date(_ field: String) throws -> Date {
        guard let real = try optionalReal(field) else { throw PublicationStoreError.corruption(field) }
        return try PublicationValueCoding.date(real, field: field)
    }
    func optionalDate(_ field: String) throws -> Date? {
        try optionalReal(field).map { try PublicationValueCoding.date($0, field: field) }
    }
    func uuid(_ field: String) throws -> UUID { try PublicationValueCoding.uuid(string(field), field: field) }
    func optionalUUID(_ field: String) throws -> UUID? { try optionalString(field).map { try PublicationValueCoding.uuid($0, field: field) } }
    func counter(_ field: String) throws -> UInt64 { try PublicationValueCoding.counter(integer(field), field: field) }
}

// Preserve the publication/session boundary while the shared codec stays neutral.
private enum PublicationValueCoding {
    private static func translate<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch let error as PersistenceValueCodingError {
            switch error {
            case .invalidRepresentation(let field): throw PublicationStoreError.invalidRepresentation(field)
            case .corruption(let field): throw PublicationStoreError.corruption(field)
            }
        }
    }
    static func uuid(_ value: String, field: String) throws -> UUID {
        try translate { try PersistenceValueCoding.uuid(value, field: field) }
    }
    static func counter(_ value: UInt64, field: String) throws -> Int64 {
        try translate { try PersistenceValueCoding.counter(value, field: field) }
    }
    static func counter(_ value: Int64, field: String) throws -> UInt64 {
        try translate { try PersistenceValueCoding.counter(value, field: field) }
    }
    static func date(_ value: Date, field: String) throws -> Double {
        try translate { try PersistenceValueCoding.date(value, field: field) }
    }
    static func date(_ value: Double, field: String) throws -> Date {
        try translate { try PersistenceValueCoding.date(value, field: field) }
    }
}
