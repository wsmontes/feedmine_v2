// File: PublicationStore+Writing.swift
// Module: FeedMinePersistence
// Owns: creating and appending Editions and Segments: the insert envelopes, their validation and the published-origin guards.
// Does not own: publication semantics, media resolution or reader-facing reads.
// Dependencies: FeedMineDomain, Foundation and private GRDB access only.

import Foundation
import GRDB
import FeedMineDomain

extension PublicationStore {

    public struct BindingPublicationExpectation: Hashable, Sendable {
        public let activation: SessionStore.BindingActivation
        public let expectedActiveEditionID: FeedEditionID?
        public init(activation: SessionStore.BindingActivation, expectedActiveEditionID: FeedEditionID? = nil) {
            self.activation = activation
            self.expectedActiveEditionID = expectedActiveEditionID
        }
    }

    public func createEdition(_ edition: EditionRecord, firstSegment: SegmentRecord, cards: [CardRecord]) throws {
        try createEdition(edition, firstSegment: firstSegment, cards: cards, expectedSourceExclusions: nil)
    }

    public func createEdition(_ edition: EditionRecord, firstSegment: SegmentRecord, cards: [CardRecord],
        expectedSourceExclusions: ReaderSourceExclusionSnapshot?,
        expectedWordExclusions: ReaderWordExclusionSnapshot? = nil,
        bindingPublication: BindingPublicationExpectation? = nil) throws {
        try database.write { db in
            try Self.requireSourceExclusions(expectedSourceExclusions, in: db)
            try Self.requireWordExclusions(expectedWordExclusions, in: db)
            try SessionStore.requirePublicationActivation(bindingPublication?.activation, in: db)
            try Self.insertEditionAndFirstSegment(edition, firstSegment: firstSegment, cards: cards, in: db)
            if let bindingPublication { try ReaderHistoryBindingStore.attachNewEdition(edition, expectation: bindingPublication, in: db) }
        }
    }

    public func createInitialEdition(_ edition: EditionRecord, firstSegment: SegmentRecord,
        cards: [CardRecord], initialCheckpoint: SessionStore.CheckpointRecord) throws {
        try createInitialEdition(edition, firstSegment: firstSegment, cards: cards,
            initialCheckpoint: initialCheckpoint, expectedSourceExclusions: nil)
    }

    public func createInitialEdition(_ edition: EditionRecord, firstSegment: SegmentRecord,
        cards: [CardRecord], initialCheckpoint: SessionStore.CheckpointRecord,
        expectedSourceExclusions: ReaderSourceExclusionSnapshot?,
        expectedWordExclusions: ReaderWordExclusionSnapshot? = nil,
        bindingPublication: BindingPublicationExpectation? = nil) throws {
        try database.write { db in
            try Self.requireSourceExclusions(expectedSourceExclusions, in: db)
            try Self.requireWordExclusions(expectedWordExclusions, in: db)
            guard firstSegment.editionID == edition.id, firstSegment.ordinal == 0,
                initialCheckpoint.editionID == edition.id,
                firstSegment.cardIDs.contains(initialCheckpoint.cardID) else {
                throw PublicationStoreError.invalidInitialCheckpoint
            }
            try SessionStore.requirePublicationActivation(bindingPublication?.activation, in: db)
            try Self.insertEditionAndFirstSegment(edition, firstSegment: firstSegment, cards: cards, in: db)
            if let bindingPublication { try ReaderHistoryBindingStore.attachNewEdition(edition, expectation: bindingPublication, in: db) }
            try SessionStore.insertInitialCheckpoint(initialCheckpoint, in: db, bindingActivation: bindingPublication?.activation)
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
        try appendSegment(segment, cards: cards, expectedSourceExclusions: nil)
    }

    public func appendSegment(_ segment: SegmentRecord, cards: [CardRecord],
        expectedSourceExclusions: ReaderSourceExclusionSnapshot?,
        expectedWordExclusions: ReaderWordExclusionSnapshot? = nil,
        bindingActivation: SessionStore.BindingActivation? = nil) throws {
        try appendSegment(segment, cards: cards, expectedTail: nil, recurrence: .forbidden,
            expectedSourceExclusions: expectedSourceExclusions, expectedWordExclusions: expectedWordExclusions,
            bindingActivation: bindingActivation)
    }

    public func appendSegment(_ segment: SegmentRecord, cards: [CardRecord],
        expectingTailCardID: PublicationCardID, recurrence: OriginRecurrenceRecord = .forbidden) throws {
        try appendSegment(segment, cards: cards, expectingTailCardID: expectingTailCardID,
            recurrence: recurrence, expectedSourceExclusions: nil)
    }

    public func appendSegment(_ segment: SegmentRecord, cards: [CardRecord],
        expectingTailCardID: PublicationCardID, recurrence: OriginRecurrenceRecord = .forbidden,
        expectedSourceExclusions: ReaderSourceExclusionSnapshot?,
        expectedWordExclusions: ReaderWordExclusionSnapshot? = nil,
        bindingActivation: SessionStore.BindingActivation? = nil) throws {
        try appendSegment(segment, cards: cards, expectedTail: expectingTailCardID, recurrence: recurrence,
            expectedSourceExclusions: expectedSourceExclusions, expectedWordExclusions: expectedWordExclusions,
            bindingActivation: bindingActivation)
    }

    private static func requireSourceExclusions(_ expected: ReaderSourceExclusionSnapshot?, in db: Database) throws {
        guard let expected else { return }
        guard try ReaderPreferencesStore.sourceExclusionSnapshot(in: db) == expected else {
            throw PublicationStoreError.staleSourceExclusions
        }
    }

    private static func requireWordExclusions(_ expected: ReaderWordExclusionSnapshot?, in db: Database) throws {
        guard let expected else { return }
        guard try expected.matches(settings: ReaderPreferencesStore.publicationSettings(in: db)) else {
            throw PublicationStoreError.staleWordExclusions
        }
    }

    /// Whether an origin already published in the Edition may occur again (PD-1).
    public enum OriginRecurrenceRecord: Hashable, Sendable {
        /// Phase 3R5: at most one occurrence per origin in an Edition.
        case forbidden
        /// PD-1: an origin may occur again only with materially different text.
        case whenMaterialChanged
    }

    /// Body material for the append guard, using the same three states as the editorial
    /// candidate and published-exposure queries; no published card or revision is rewritten.
    private static func materialBody(_ revision: OriginRevisionID, in db: Database) throws
        -> (text: String?, observed: Bool) {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT CASE WHEN r.fingerprint_generation = 2 THEN r.body_text
                        WHEN e.origin_revision_id IS NOT NULL THEN e.body_text
                        ELSE NULL END AS declared_body,
                   CASE WHEN r.fingerprint_generation = 2 OR e.origin_revision_id IS NOT NULL
                        THEN 1 ELSE 0 END AS body_observed
            FROM origin_revisions r
            LEFT JOIN origin_revision_body_enrichment e ON e.origin_revision_id = r.id
            WHERE r.id = ?
            """, arguments: [PersistenceValueCoding.uuid(revision.rawValue)]) else {
            return (nil, false) // Historical publication fixture without a canonical revision.
        }
        let body: String? = row["declared_body"]
        let observed: Int = row["body_observed"]
        return (body, observed == 1)
    }

    /// Ordinal-0 canonical media locator of a revision; immutable, so both sides agree.
    static func primaryMediaLocator(_ revision: OriginRevisionID, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT remote_locator FROM media_candidates WHERE origin_revision_id = ? AND ordinal = 0 AND media_class = 'image'",
            arguments: [PersistenceValueCoding.uuid(revision.rawValue)])
    }

    private func appendSegment(_ segment: SegmentRecord, cards: [CardRecord],
        expectedTail: PublicationCardID?, recurrence: OriginRecurrenceRecord,
        expectedSourceExclusions: ReaderSourceExclusionSnapshot?,
        expectedWordExclusions: ReaderWordExclusionSnapshot? = nil,
        bindingActivation: SessionStore.BindingActivation? = nil) throws {
        try database.write { db in
            try SessionStore.requireCheckpointOwner(editionID: segment.editionID, activation: bindingActivation, allowsPreparation: true, in: db)
            try Self.requireSourceExclusions(expectedSourceExclusions, in: db)
            try Self.requireWordExclusions(expectedWordExclusions, in: db)
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
                for card in cards {
                    let body = try Self.materialBody(card.originRevisionID, in: db)
                    if published[card.originRecordID]?
                        .contains(Self.materialKey(title: card.title, primaryText: card.primaryText,
                            primaryMedia: try Self.primaryMediaLocator(card.originRevisionID, in: db),
                            declaredBody: body.text, bodyObserved: body.observed)) == true {
                        throw PublicationStoreError.duplicateOriginInEdition
                    }
                }
            }
            try Self.insertSegment(segment, cards: cards, db: db)
        }
    }

    static func publishedMaterial(_ ids: [OriginRecordID], editionID: FeedEditionID,
        in db: Database) throws -> [OriginRecordID: Set<String>] {
        let keys = Array(Set(ids)).map { PersistenceValueCoding.uuid($0.rawValue) }
        let capacity = db.maximumStatementArgumentCount - 1
        guard capacity > 0 else { throw PublicationStoreError.invalidCapacity }
        var found: [OriginRecordID: Set<String>] = [:]
        for start in stride(from: 0, to: keys.count, by: capacity) {
            let group = Array(keys[start..<min(start + capacity, keys.count)])
            let placeholders = Array(repeating: "?", count: group.count).joined(separator: ",")
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.origin_record_id, c.title, c.primary_text, m.remote_locator AS primary_media,
                        CASE WHEN r.fingerprint_generation = 2 THEN r.body_text
                             WHEN e.origin_revision_id IS NOT NULL THEN e.body_text
                             ELSE NULL END AS declared_body,
                        CASE WHEN r.fingerprint_generation = 2 OR e.origin_revision_id IS NOT NULL
                             THEN 1 ELSE 0 END AS body_observed FROM published_cards c
                JOIN feed_segments s ON s.id = c.segment_id
                LEFT JOIN origin_revisions r ON r.id = c.origin_revision_id
                    LEFT JOIN origin_revision_body_enrichment e ON e.origin_revision_id = c.origin_revision_id
                LEFT JOIN media_candidates m ON m.origin_revision_id = c.origin_revision_id AND m.ordinal = 0 AND m.media_class = 'image'
                WHERE c.origin_record_id IN (\(placeholders)) AND s.edition_id = ?
                """, arguments: StatementArguments(group + [PersistenceValueCoding.uuid(editionID.rawValue)]))
            for row in rows {
                let fields = PublicationRecordFields(row)
                let origin = OriginRecordID(rawValue: try fields.uuid("origin_record_id"))
                found[origin, default: []].insert(materialKey(title: try fields.optionalString("title"),
                    primaryText: try fields.optionalString("primary_text"), primaryMedia: try fields.optionalString("primary_media"),
                        declaredBody: try fields.optionalString("declared_body"),
                        bodyObserved: (try fields.integer("body_observed")) == 1))
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

    static func validate(_ segment: SegmentRecord, cards: [CardRecord], version: UInt64) throws {
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

    static func validateCard(_ card: CardRecord) throws {
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
        // D2: the vocabulary is closed, and only an audio card may carry the in-app player. Unknown (nil) stays
        // allowed for history written before the column existed.
        if let identity = card.mediaIdentity {
            try require(["none", "audio", "video"].contains(identity), "media identity")
            try require(identity == "audio" || card.primaryActionKind != "mediaPlayback", "media identity action")
        }
    }

    // These insert envelopes are private. No public row type or generic CRUD API escapes.
    private static func insert(_ db: Database, table: String, columns: [String], values: [DatabaseValue]) throws {
        let marks = Array(repeating: "?", count: columns.count).joined(separator: ",")
        try db.execute(sql: "INSERT INTO \(table) (\(columns.joined(separator: ","))) VALUES (\(marks))", arguments: StatementArguments(values))
    }

    static func insertSegment(_ segment: SegmentRecord, cards: [CardRecord], db: Database) throws {
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

    private static let cardColumns = ["id", "origin_record_id", "origin_revision_id", "source_id", "provider_id", "source_display_name", "provider_display_name", "content_entity_id", "content_cluster_id", "title", "primary_text", "timestamp_value", "timestamp_kind", "media_key", "media_pixel_width", "media_pixel_height", "media_mime_type", "render_layout", "render_media_aspect_ratio", "primary_action_kind", "primary_action_reference", "media_identity", "diversity_facts"]
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
            (c.primaryActionReference).databaseValue,
            (c.mediaIdentity).databaseValue,
            (try PublicationStore.encodeDiversity(c.diversity)).databaseValue
        ]
    }

}
