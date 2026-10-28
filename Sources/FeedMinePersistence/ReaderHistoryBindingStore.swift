import Foundation
import GRDB
import FeedMineDomain

/// Durable ownership of frozen history. Resolving known raw inputs never reinterprets words stored
/// in an old Edition; ambiguous adoption rolls back instead of merging two logical readers.
public struct ReaderHistoryBindingStore: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        case missingEdition, incompatibleAdoption, staleAdoptionPolicy, editionAlreadyOwned
        case runtimeNamespaceAlreadyOwned, runtimeNamespaceConflict, activeEditionConflict, corruption
    }

    public struct Record: Hashable, Sendable {
        public let id: UUID
        public let logicalKey: ContextKey
        public let runtimeNamespace: String
        public let activeEditionID: FeedEditionID?
    }

    public enum Evidence: Hashable, Sendable {
        case exactContext
        case legacyWords(ReaderWordExclusionSnapshot)
    }

    public struct Adoption: Hashable, Sendable {
        public let editionID: FeedEditionID
        public let publicationKey: ContextKey
        public let evidence: Evidence
        public init(editionID: FeedEditionID, publicationKey: ContextKey, evidence: Evidence) {
            self.editionID = editionID
            self.publicationKey = publicationKey
            self.evidence = evidence
        }
    }

    private let database: RuntimeDatabase
    public init(database: RuntimeDatabase) { self.database = database }

    public func binding(for key: ContextKey) throws -> Record? {
        try database.read { try Self.read(key, in: $0) }
    }

    public func resolve(logicalKey: ContextKey, adopting adoption: Adoption? = nil) throws -> Record {
        try database.write { db in
            let existing = try Self.read(logicalKey, in: db)
            if let existing, adoption == nil { return existing }
            if let existing, let adoption, let active = existing.activeEditionID {
                guard active == adoption.editionID else { throw Failure.activeEditionConflict }
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT publication_key_json FROM reader_history_editions WHERE edition_id = ? AND binding_id = ?
                    """, arguments: [PersistenceValueCoding.uuid(active.rawValue), PersistenceValueCoding.uuid(existing.id)]),
                    try Self.key(row, field: "publication_key_json") == adoption.publicationKey else { throw Failure.incompatibleAdoption }
                // Established ownership is a fact, not a fresh policy inference. Do not replace its provenance.
                return existing
            }
            var provenance: Data?
            var kind = "exact_context"
            if let adoption {
                guard let row = try Row.fetchOne(db, sql: "SELECT * FROM feed_editions WHERE id = ?",
                    arguments: [PersistenceValueCoding.uuid(adoption.editionID.rawValue)]) else { throw Failure.missingEdition }
                guard try PublicationStore.decodeEdition(row).editorialRevision.contextKey == adoption.publicationKey else {
                    throw Failure.incompatibleAdoption
                }
                switch adoption.evidence {
                case .exactContext:
                    guard logicalKey == adoption.publicationKey else { throw Failure.incompatibleAdoption }
                case .legacyWords(let snapshot):
                    let forward = ContextKey(request: logicalKey.request, preset: logicalKey.preset,
                        filter: logicalKey.filter.replacing(exclusions: snapshot.exclusions), searchScope: logicalKey.searchScope,
                        identitySchemaVersion: logicalKey.identitySchemaVersion)
                    guard snapshot.context == logicalKey.filter.exclusions, forward == adoption.publicationKey else {
                        throw Failure.incompatibleAdoption
                    }
                    guard try snapshot.matches(settings: ReaderPreferencesStore.publicationSettings(in: db)) else {
                        throw Failure.staleAdoptionPolicy
                    }
                    kind = "legacy_words"
                    provenance = try Self.encode(PolicyEvidence(snapshot))
                }
                if let owner = try String.fetchOne(db,
                    sql: "SELECT binding_id FROM reader_history_editions WHERE edition_id = ?",
                    arguments: [PersistenceValueCoding.uuid(adoption.editionID.rawValue)]),
                    owner != existing.map({ PersistenceValueCoding.uuid($0.id) }) { throw Failure.editionAlreadyOwned }
            }
            let id = existing?.id ?? UUID()
            let preferredNamespace = adoption?.publicationKey.canonicalIdentity ?? logicalKey.canonicalIdentity
            var namespace = preferredNamespace
            if let existing, existing.runtimeNamespace != preferredNamespace { throw Failure.runtimeNamespaceConflict }
            if let owner = try String.fetchOne(db, sql: "SELECT id FROM reader_history_bindings WHERE runtime_namespace = ?",
                arguments: [preferredNamespace]), owner != PersistenceValueCoding.uuid(id) {
                guard adoption == nil else { throw Failure.runtimeNamespaceAlreadyOwned }
                namespace = "reader-binding:" + PersistenceValueCoding.uuid(id)
            }
            if existing == nil {
                try db.execute(sql: """
                    INSERT INTO reader_history_bindings(id, logical_identity, logical_key_json, runtime_namespace)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [PersistenceValueCoding.uuid(id), logicalKey.canonicalIdentity,
                        try Self.encode(logicalKey), namespace])
            }
            if let adoption {
                try db.execute(sql: """
                    INSERT INTO reader_history_editions(edition_id, binding_id, publication_key_json, adoption_kind, adoption_policy_json)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [PersistenceValueCoding.uuid(adoption.editionID.rawValue), PersistenceValueCoding.uuid(id),
                        try Self.encode(adoption.publicationKey), kind, provenance])
                try db.execute(sql: "UPDATE reader_history_bindings SET active_edition_id = ? WHERE id = ?",
                    arguments: [PersistenceValueCoding.uuid(adoption.editionID.rawValue), PersistenceValueCoding.uuid(id)])
            }
            guard let result = try Self.read(logicalKey, in: db) else { throw Failure.corruption }
            return result
        }
    }

    private struct PolicyEvidence: Encodable {
        struct Template: Encodable { let key: String; let rules: [String] }
        let context: ReaderContentExclusions
        let effective: ReaderContentExclusions
        let templates: [Template]
        init(_ snapshot: ReaderWordExclusionSnapshot) {
            context = snapshot.context
            effective = snapshot.exclusions
            templates = snapshot.templates.map { Template(key: $0.key, rules: $0.rules) }
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func key(_ row: Row, field: String) throws -> ContextKey {
        guard case .blob(let data) = PublicationRecordFields(row).value(field).storage else { throw Failure.corruption }
        return try JSONDecoder().decode(ContextKey.self, from: data)
    }

    private static func read(_ key: ContextKey, in db: Database) throws -> Record? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM reader_history_bindings WHERE logical_identity = ?",
            arguments: [key.canonicalIdentity]) else { return nil }
        let fields = PublicationRecordFields(row), logical = try Self.key(row, field: "logical_key_json")
        guard logical == key, try fields.string("logical_identity") == logical.canonicalIdentity else { throw Failure.corruption }
        return Record(id: try fields.uuid("id"), logicalKey: logical,
            runtimeNamespace: try fields.string("runtime_namespace"),
            activeEditionID: try fields.optionalUUID("active_edition_id").map { FeedEditionID(rawValue: $0) })
    }
}
