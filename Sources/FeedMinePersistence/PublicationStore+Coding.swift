// File: PublicationStore+Coding.swift
// Module: FeedMinePersistence
// Owns: row-to-record decoding of the publication tables and the scalar field checks decoding shares.
// Does not own: SQL writes, ordering or publication semantics.
// Dependencies: FeedMineDomain, Foundation and private GRDB access only.

import Foundation
import GRDB
import FeedMineDomain

extension PublicationStore {

    static func decodeEdition(_ row: Row) throws -> EditionRecord {
        let f = PublicationRecordFields(row)
        let request: FeedContextRequest
        let source = try f.optionalUUID("context_source_id"), query = try f.optionalString("context_search_query")
        switch try f.string("context_kind") {
        case "main" where source == nil && query == nil: request = .main
        case "source" where source != nil && query == nil: request = .source(SourceID(rawValue: source!))
        case "search" where source == nil && query != nil:
            // R14: a row that only carried text is a legacy literal; the grammar must not reinterpret it.
            guard let search = SearchContext(query: query!, semantics: .legacyLiteral) else { throw PublicationStoreError.corruption("search context") }
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

    static func decodeSegment(_ row: Row, db: Database) throws -> SegmentRecord {
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
    static func decodeDiversity(_ raw: String?) throws -> EditorialDiversityFact? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8) else { throw PublicationStoreError.corruption("diversity facts") }
        do { return try JSONDecoder().decode(EditorialDiversityFact.self, from: data) }
        catch { throw PublicationStoreError.corruption("diversity facts: \(error)") }
    }

    static func encodeDiversity(_ facts: EditorialDiversityFact?) throws -> String? {
        guard let facts else { return nil }
        do { return String(decoding: try JSONEncoder().encode(facts), as: UTF8.self) }
        catch { throw PublicationStoreError.corruption("diversity facts: \(error)") }
    }

    static func decodeCard(_ row: Row) throws -> CardRecord {
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
            primaryActionReference: try f.optionalString("primary_action_reference"),
            // A historical schema opened by a migration test has no such column: absence is unknown, not an error.
            diversity: try Self.decodeDiversity(f.optionalStringIfPresent("diversity_facts"))
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
    /// Reads a column that may not exist in a historical schema; absent means nil, never a runtime failure.
    func optionalStringIfPresent(_ field: String) -> String? {
        guard row.columnNames.contains(field) else { return nil }
        return try? optionalString(field)
    }
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
enum PublicationValueCoding {
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
