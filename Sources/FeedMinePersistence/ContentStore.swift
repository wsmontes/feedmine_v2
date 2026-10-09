// Owns: atomic canonical accepted facts, immutable revisions with complete ordered media facts and supply projection.
// Does not own: admission, candidate queries, acquisition or published history.

import Foundation
import GRDB
import FeedMineDomain

public enum ContentStoreError: Error, Equatable, Sendable {
    case invalidCapacity
    case invalidRepresentation(String)
    case corruption(String)
    case originIdentityConflict
    case revisionConflict
    case mediaCandidateConflict(MediaCandidateID)
    case mediaCandidateCollectionConflict(OriginRevisionID)
    case versionIdentityConflict
    case staleCurrent(expected: OriginRevisionID?, actual: OriginRevisionID?)
    case invalidChange(String)
}

public struct ContentStore: Sendable {
    private let database: RuntimeDatabase
    public init(database: RuntimeDatabase) { self.database = database }

    public struct CandidateCursor: Hashable, Sendable {
        public let sortDate: Date
        public let originRecordID: OriginRecordID

        public init(sortDate: Date, originRecordID: OriginRecordID) {
            self.sortDate = sortDate
            self.originRecordID = originRecordID
        }
    }

    public enum SupplySortDateBasis: String, Hashable, Sendable {
        case authored
        case observedFallback
    }

    public struct CandidateRecord: Hashable, Sendable {
        public let originRecordID: OriginRecordID
        public let originRevisionID: OriginRevisionID
        public let sortDate: Date
        public let sortDateBasis: SupplySortDateBasis
        public let headline: String?
        public let summary: String?
        public let authoredAt: Date?
        public let observedAt: Date
        public let language: String?
        public let providerID: ProviderID?
        /// Every Source this origin belongs to, in stable ID order (PD-4 adjacency facts).
        public let sourceIDs: [SourceID]
        /// Ordinal-0 canonical media locator (PD-1 material identity, review F07).
        public let primaryMediaLocator: String?
        /// Article URL to open (review F10); nil when the revision has none.
        public let primaryLink: URL?
    }

    public struct CandidateWindow: Hashable, Sendable {
        public let records: [CandidateRecord]
        public let examinedCount: Int
        public let nextCursor: CandidateCursor?
        public let exhausted: Bool
    }

    public func candidateWindow(sourceID: SourceID?, after cursor: CandidateCursor?, examinedCapacity: Int) throws -> CandidateWindow {
        try candidateWindow(sourceID: sourceID, after: cursor, examinedCapacity: examinedCapacity, originIDs: nil)
    }

    public func candidateWindow(sourceID: SourceID?, after cursor: CandidateCursor?,
        examinedCapacity: Int, originIDs: [OriginRecordID]?) throws -> CandidateWindow {
        guard examinedCapacity > 0 else { throw ContentStoreError.invalidCapacity }
        return try database.read { db in
            try Self.coding {
                // Fix examined work before performing any source eligibility lookup.
                let columns = "SELECT origin_record_id, origin_revision_id, sort_date, sort_date_basis FROM selection_supply"
                let order = " ORDER BY sort_date DESC, origin_record_id DESC LIMIT ?"
                var conditions: [String] = []
                var arguments: [DatabaseValueConvertible] = []
                if let originIDs {
                    let keys = Set(originIDs).map { Self.key($0.rawValue) }.sorted()
                    if keys.isEmpty { return CandidateWindow(records: [], examinedCount: 0, nextCursor: nil, exhausted: true) }
                    guard keys.count <= db.maximumStatementArgumentCount - 3 else { throw ContentStoreError.invalidCapacity }
                    conditions.append("origin_record_id IN (" + Array(repeating: "?", count: keys.count).joined(separator: ",") + ")")
                    arguments += keys.map { $0 as DatabaseValueConvertible }
                }
                if let cursor {
                    let date = try PersistenceValueCoding.date(cursor.sortDate, field: "cursor.sort_date")
                    conditions.append("(sort_date, origin_record_id) < (?, ?)")
                    arguments += [date, Self.key(cursor.originRecordID.rawValue)]
                }
                arguments.append(examinedCapacity)
                let filter = conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND ")
                let rows = try Row.fetchAll(db, sql: columns + filter + order, arguments: StatementArguments(arguments))
                var records: [CandidateRecord] = []
                var nextCursor: CandidateCursor?
                for row in rows {
                    let f = ContentFields(row)
                    let origin = OriginRecordID(rawValue: try f.uuid("origin_record_id"))
                    let revision = OriginRevisionID(rawValue: try f.uuid("origin_revision_id"))
                    let sortDate = try f.date("sort_date")
                    guard let basis = SupplySortDateBasis(rawValue: try f.string("sort_date_basis")) else {
                        throw ContentStoreError.corruption("sort_date_basis")
                    }
                    nextCursor = CandidateCursor(sortDate: sortDate, originRecordID: origin)
                    let key = Self.key(origin.rawValue)
                    guard let originRow = try Row.fetchOne(db,
                        sql: "SELECT availability, current_revision_id FROM origin_records WHERE id = ?", arguments: [key]) else {
                        throw ContentStoreError.corruption("supply origin")
                    }
                    let originFields = ContentFields(originRow)
                    let availability = try originFields.string("availability")
                    guard availability == "available" || availability == "updated",
                        try originFields.optionalUUID("current_revision_id") == revision.rawValue else {
                        throw ContentStoreError.corruption("supply currentness/availability")
                    }
                    // Every projection must remain structurally backed by membership.
                    guard try Bool.fetchOne(db,
                        sql: "SELECT EXISTS(SELECT 1 FROM source_memberships WHERE origin_record_id = ?)", arguments: [key]) == true else {
                        throw ContentStoreError.corruption("supply membership")
                    }
                    if let sourceID, try Bool.fetchOne(db,
                        sql: "SELECT EXISTS(SELECT 1 FROM source_memberships WHERE origin_record_id = ? AND source_id = ?)",
                        arguments: [key, Self.key(sourceID.rawValue)]) != true {
                        continue
                    }
                    // No broad revision decode: excluded payloads are never selected.
                    guard let payload = try Row.fetchOne(db, sql: """
                        SELECT id, origin_record_id, headline, summary, authored_at, observed_at, language, provider_id, primary_link
                        FROM origin_revisions WHERE id = ?
                        """, arguments: [Self.key(revision.rawValue)]) else {
                        throw ContentStoreError.corruption("supply revision")
                    }
                    let p = ContentFields(payload)
                    guard try p.uuid("origin_record_id") == origin.rawValue else {
                        throw ContentStoreError.corruption("supply revision origin")
                    }
                    records.append(CandidateRecord(originRecordID: origin,
                        originRevisionID: OriginRevisionID(rawValue: try p.uuid("id")), sortDate: sortDate, sortDateBasis: basis,
                        headline: try p.optionalString("headline"), summary: try p.optionalString("summary"),
                        authoredAt: try p.optionalDate("authored_at"), observedAt: try p.date("observed_at"),
                        language: try p.optionalString("language"),
                        providerID: try p.optionalUUID("provider_id").map { ProviderID(rawValue: $0) },
                        sourceIDs: try String.fetchAll(db, sql: "SELECT source_id FROM source_memberships WHERE origin_record_id = ? ORDER BY source_id COLLATE BINARY ASC",
                            arguments: [key]).map { SourceID(rawValue: try PersistenceValueCoding.uuid($0, field: "source_memberships.source_id")) },
                        primaryMediaLocator: try String.fetchOne(db, sql: "SELECT remote_locator FROM media_candidates WHERE origin_revision_id = ? AND ordinal = 0",
                            arguments: [Self.key(revision.rawValue)]),
                        primaryLink: try p.optionalString("primary_link").flatMap { URL(string: $0) }))
                }
                return CandidateWindow(records: records, examinedCount: rows.count,
                    nextCursor: nextCursor, exhausted: rows.count < examinedCapacity)
            }
        }
    }

    public enum CurrentRevisionExpectation: Equatable, Sendable {
        case none
        case revision(OriginRevisionID)

        fileprivate var id: OriginRevisionID? {
            switch self {
            case .none: return nil
            case .revision(let id): return id
            }
        }
    }

    public enum CurrentRevisionUpdate: Equatable, Sendable {
        case unchanged
        case useSuppliedRevision
        case clear
    }

    public enum MembershipMutation: Equatable, Sendable {
        case upsert(sourceID: SourceID, kind: SourceMembershipKind, observedAt: Date)
        case remove(sourceID: SourceID)

        fileprivate var sourceID: SourceID {
            switch self {
            case .upsert(let id, _, _), .remove(let id): return id
            }
        }
    }

    public struct CanonicalChange: Sendable {
        public let recordID: OriginRecordID
        public let externalObjectIdentity: ExternalIdentity
        public let revision: OriginRevision
        public let mediaCandidates: [MediaCandidate]
        public let availability: OriginAvailability
        public let observedAt: Date
        public let expectedCurrent: CurrentRevisionExpectation
        public let currentUpdate: CurrentRevisionUpdate
        public let membershipMutations: [MembershipMutation]

        public init(recordID: OriginRecordID, externalObjectIdentity: ExternalIdentity,
            revision: OriginRevision, mediaCandidates: [MediaCandidate], availability: OriginAvailability, observedAt: Date,
            expectedCurrent: CurrentRevisionExpectation, currentUpdate: CurrentRevisionUpdate,
            membershipMutations: [MembershipMutation]) {
            self.recordID = recordID
            self.externalObjectIdentity = externalObjectIdentity
            self.revision = revision
            self.mediaCandidates = mediaCandidates
            self.availability = availability
            self.observedAt = observedAt
            self.expectedCurrent = expectedCurrent
            self.currentUpdate = currentUpdate
            self.membershipMutations = membershipMutations
        }
    }

    // Narrow transaction-scoped admission reads; canonical mutation stays in apply.
    func admissionRecord(matching identity: ExternalIdentity, in db: Database) throws -> OriginRecord? {
        try Self.coding {
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id FROM origin_records WHERE object_connector_kind = ? AND object_namespace = ?
                    AND object_value = ? AND object_role = ?
                """, arguments: [identity.connectorKind.rawValue, identity.namespace, identity.value, identity.role.rawValue]) else { return nil }
            return try Self.record(OriginRecordID(rawValue: ContentFields(row).uuid("id")), in: db)
        }
    }

    func admissionRevision(originRecordID: OriginRecordID, matching version: ExternalIdentity, in db: Database) throws -> OriginRevision? {
        try Self.coding {
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id FROM origin_revisions WHERE origin_record_id = ? AND version_connector_kind = ?
                    AND version_namespace = ? AND version_value = ? AND version_role = ?
                """, arguments: [Self.key(originRecordID.rawValue), version.connectorKind.rawValue,
                    version.namespace, version.value, version.role.rawValue]) else { return nil }
            return try Self.revision(OriginRevisionID(rawValue: ContentFields(row).uuid("id")), in: db)
        }
    }

    func admissionCurrentRevision(for record: OriginRecord, in db: Database) throws -> OriginRevision? {
        try Self.coding { try Self.current(record, in: db) }
    }

    func admissionMediaCandidates(originRevisionID: OriginRevisionID, in db: Database) throws -> [MediaCandidate] {
        try Self.coding { try Self.mediaCandidates(originRevisionID, in: db) }
    }

    static func admissionSameRevision(_ a: OriginRevision, _ b: OriginRevision) -> Bool { sameRevision(a, b) }
    static func admissionSameMediaCandidate(_ a: MediaCandidate, _ b: MediaCandidate) -> Bool { sameMediaCandidate(a, b) }

    public func commitCanonicalChange(_ change: CanonicalChange) throws {
        try database.write { try self.apply(change, in: $0) }
    }

    // Transaction body also permits a future Persistence-owned shared transaction.
    // It never opens a nested transaction or exposes GRDB publicly.
    func apply(_ change: CanonicalChange, in db: Database) throws {
        try Self.coding {
            try Self.validate(change)
            let key = Self.key(change.recordID.rawValue)
            let object = change.externalObjectIdentity
            let existing = try Self.record(change.recordID, in: db)
            if let existing, !Self.sameIdentity(existing.externalObjectIdentity, object) {
                throw ContentStoreError.originIdentityConflict
            }
            if let row = try Row.fetchOne(db, sql: """
                SELECT id FROM origin_records WHERE object_connector_kind = ? AND object_namespace = ?
                    AND object_value = ? AND object_role = ?
                """, arguments: [object.connectorKind.rawValue, object.namespace, object.value, object.role.rawValue]),
                try ContentFields(row).uuid("id") != change.recordID.rawValue {
                throw ContentStoreError.originIdentityConflict
            }
            let actual = existing?.currentRevisionID
            guard actual == change.expectedCurrent.id else {
                throw ContentStoreError.staleCurrent(expected: change.expectedCurrent.id, actual: actual)
            }
            let observed = try PersistenceValueCoding.date(change.observedAt, field: "last_observed_at")
            if existing == nil {
                try db.execute(sql: """
                    INSERT INTO origin_records (id, object_connector_kind, object_namespace, object_value,
                        object_role, current_revision_id, availability, first_observed_at, last_observed_at,
                        availability_observed_at)
                    VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
                    """, arguments: [key, object.connectorKind.rawValue, object.namespace, object.value,
                        object.role.rawValue, change.availability.rawValue, observed, observed, observed])
            }
            let revision = change.revision
            if let stored = try Self.revision(revision.id, in: db) {
                guard Self.sameRevision(stored, revision) else { throw ContentStoreError.revisionConflict }
                try Self.validateMediaReplay(change.mediaCandidates, revisionID: revision.id, in: db)
            } else {
                if let version = revision.externalVersionIdentity,
                    try Row.fetchOne(db, sql: """
                        SELECT id FROM origin_revisions WHERE origin_record_id = ? AND version_connector_kind = ?
                            AND version_namespace = ? AND version_value = ? AND version_role = ?
                        """, arguments: [key, version.connectorKind.rawValue, version.namespace,
                            version.value, version.role.rawValue]) != nil {
                    throw ContentStoreError.versionIdentityConflict
                }
                try Self.insertRevision(revision, in: db)
                for (ordinal, candidate) in change.mediaCandidates.enumerated() {
                    guard try Self.mediaCandidate(candidate.id, in: db) == nil else {
                        throw ContentStoreError.mediaCandidateConflict(candidate.id)
                    }
                    try Self.insertMediaCandidate(candidate, ordinal: ordinal, in: db)
                }
            }
            try Self.writeMemberships(change.membershipMutations, recordID: change.recordID, in: db)
            let current: OriginRevisionID?
            switch change.currentUpdate {
            case .unchanged: current = actual
            case .useSuppliedRevision: current = revision.id
            case .clear: current = nil
            }
            try db.execute(sql: "UPDATE origin_records SET current_revision_id = ? WHERE id = ?",
                arguments: [current.map { Self.key($0.rawValue) }, key])
            try Self.updateAvailability(change.availability, observedAt: change.observedAt, recordID: change.recordID, in: db)
            try db.execute(sql: "UPDATE origin_records SET last_observed_at = ? WHERE id = ?",
                arguments: [observed, key])
            try Self.refreshSupply(change.recordID, in: db)
        }
    }

    /// Admission calls this only after durable target/Source validation, in its existing transaction.
    func applyMemberships(_ mutations: [MembershipMutation], recordID: OriginRecordID, in db: Database) throws {
        try Self.coding {
            try Self.writeMemberships(mutations, recordID: recordID, in: db)
            try Self.refreshSupply(recordID, in: db)
        }
    }

    private static func writeMemberships(_ mutations: [MembershipMutation], recordID: OriginRecordID, in db: Database) throws {
        let key = Self.key(recordID.rawValue)
            for mutation in mutations {
                switch mutation {
                case .upsert(let source, let kind, let date):
                    let time = try PersistenceValueCoding.date(date, field: "membership.observed_at")
                    try db.execute(sql: """
                        INSERT INTO source_memberships (origin_record_id, source_id, membership_kind,
                            first_observed_at, last_observed_at) VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(origin_record_id, source_id) DO UPDATE SET
                            membership_kind = excluded.membership_kind, last_observed_at = excluded.last_observed_at
                        """, arguments: [key, Self.key(source.rawValue), kind.rawValue, time, time])
                case .remove(let source):
                    try db.execute(sql: "DELETE FROM source_memberships WHERE origin_record_id = ? AND source_id = ?",
                        arguments: [key, Self.key(source.rawValue)])
                }
            }
    }

    /// Admission may reject an immutable revision while retaining its independent availability signal.
    /// The caller owns the admission transaction; membership and lastObservedAt are untouched here.
    func applyAvailability(_ availability: OriginAvailability, observedAt: Date,
        recordID: OriginRecordID, in db: Database) throws {
        try Self.coding {
            try Self.updateAvailability(availability, observedAt: observedAt, recordID: recordID, in: db)
            try Self.refreshSupply(recordID, in: db)
        }
    }

    private static func updateAvailability(_ availability: OriginAvailability, observedAt: Date,
        recordID: OriginRecordID, in db: Database) throws {
        let observed = try PersistenceValueCoding.date(observedAt, field: "availability_observed_at")
        guard let row = try Row.fetchOne(db, sql: "SELECT availability, availability_observed_at FROM origin_records WHERE id = ?",
            arguments: [key(recordID.rawValue)]) else { throw ContentStoreError.corruption("availability origin") }
        let fields = ContentFields(row)
        guard OriginAvailability(rawValue: try fields.string("availability")) != nil else {
            throw ContentStoreError.corruption("availability")
        }
        let previous = try fields.date("availability_observed_at")
        // Older signals and both kinds of ties preserve the established durable state.
        // Admission's existing rejection reasons describe revision conflicts, not availability ties.
        guard observedAt > previous else { return }
        try db.execute(sql: "UPDATE origin_records SET availability = ?, availability_observed_at = ? WHERE id = ?",
            arguments: [availability.rawValue, observed, key(recordID.rawValue)])
    }

    public func originRecord(id: OriginRecordID) throws -> OriginRecord? {
        try database.read { db in try Self.coding { try Self.record(id, in: db) } }
    }
    public func originRevision(id: OriginRevisionID) throws -> OriginRevision? {
        try database.read { db in try Self.coding { try Self.revision(id, in: db) } }
    }
    /// Exact immutable historical collection. Missing revision differs from an admitted empty collection.
    public func mediaCandidates(originRevisionID: OriginRevisionID) throws -> [MediaCandidate]? {
        try database.read { db in
            try Self.coding {
                guard let row = try Row.fetchOne(db, sql: "SELECT id FROM origin_revisions WHERE id = ?",
                    arguments: [Self.key(originRevisionID.rawValue)]) else { return nil }
                guard try ContentFields(row).uuid("id") == originRevisionID.rawValue else {
                    throw ContentStoreError.corruption("media candidate revision")
                }
                return try Self.mediaCandidates(originRevisionID, in: db)
            }
        }
    }
    public func currentRevision(originRecordID: OriginRecordID) throws -> OriginRevision? {
        try database.read { db in
            try Self.coding {
                guard let record = try Self.record(originRecordID, in: db) else { return nil }
                return try Self.current(record, in: db)
            }
        }
    }
    public func memberships(originRecordID: OriginRecordID) throws -> [SourceMembership] {
        try database.read { db in
            try Self.coding {
                try Row.fetchAll(db, sql: "SELECT * FROM source_memberships WHERE origin_record_id = ? ORDER BY source_id COLLATE BINARY ASC",
                    arguments: [Self.key(originRecordID.rawValue)]).map { row in
                    let f = ContentFields(row)
                    guard let kind = SourceMembershipKind(rawValue: try f.string("membership_kind")) else {
                        throw ContentStoreError.corruption("membership_kind")
                    }
                    return SourceMembership(originRecordID: OriginRecordID(rawValue: try f.uuid("origin_record_id")),
                        sourceID: SourceID(rawValue: try f.uuid("source_id")), kind: kind,
                        firstObservedAt: try f.date("first_observed_at"), lastObservedAt: try f.date("last_observed_at"))
                }
            }
        }
    }

    private static func key(_ id: UUID) -> String { PersistenceValueCoding.uuid(id) }
    private static func coding<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch let error as PersistenceValueCodingError {
            switch error {
            case .invalidRepresentation(let field): throw ContentStoreError.invalidRepresentation(field)
            case .corruption(let field): throw ContentStoreError.corruption(field)
            }
        }
    }

    private static func validate(_ change: CanonicalChange) throws {
        guard change.externalObjectIdentity.role == .object else { throw ContentStoreError.invalidChange("object role") }
        let revision = change.revision
        guard revision.originRecordID == change.recordID else { throw ContentStoreError.invalidChange("revision origin") }
        if let version = revision.externalVersionIdentity {
            guard version.role == .version,
                exact(version.connectorKind.rawValue, change.externalObjectIdentity.connectorKind.rawValue) else {
                throw ContentStoreError.invalidChange("version role/connector")
            }
        }
        guard change.mediaCandidates.allSatisfy({ $0.originRevisionID == revision.id }) else {
            throw ContentStoreError.invalidChange("media candidate revision")
        }
        guard Set(change.mediaCandidates.map(\.id)).count == change.mediaCandidates.count else {
            throw ContentStoreError.invalidChange("duplicate media candidate id")
        }
        guard Set(change.membershipMutations.map(\.sourceID)).count == change.membershipMutations.count else {
            throw ContentStoreError.invalidChange("duplicate membership mutation")
        }
        _ = try PersistenceValueCoding.date(change.observedAt, field: "last_observed_at")
        _ = try PersistenceValueCoding.date(revision.observedAt, field: "observed_at")
        _ = try revision.authoredAt.map { try PersistenceValueCoding.date($0, field: "authored_at") }
        _ = try revision.modifiedAt.map { try PersistenceValueCoding.date($0, field: "modified_at") }
        for mutation in change.membershipMutations {
            if case .upsert(_, _, let date) = mutation {
                _ = try PersistenceValueCoding.date(date, field: "membership.observed_at")
            }
        }
        if let link = revision.primaryLink {
            guard let decoded = URL(string: link.absoluteString), exact(decoded.absoluteString, link.absoluteString) else {
                throw ContentStoreError.invalidRepresentation("primary_link")
            }
        }
    }

    // Swift String equality folds Unicode canonical equivalents; persisted opaque text
    // instead follows SQLite BINARY identity and must compare its exact UTF-8 bytes.
    private static func exact(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    private static func exact(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (.some(let a), .some(let b)): return exact(a, b)
        default: return false
        }
    }
    private static func sameIdentity(_ a: ExternalIdentity, _ b: ExternalIdentity) -> Bool {
        exact(a.connectorKind.rawValue, b.connectorKind.rawValue) && exact(a.namespace, b.namespace)
            && exact(a.value, b.value) && a.role == b.role
    }
    private static func sameRevision(_ a: OriginRevision, _ b: OriginRevision) -> Bool {
        let versionEqual: Bool
        switch (a.externalVersionIdentity, b.externalVersionIdentity) {
        case (nil, nil): versionEqual = true
        case (.some(let a), .some(let b)): versionEqual = sameIdentity(a, b)
        default: versionEqual = false
        }
        return a.id == b.id && a.originRecordID == b.originRecordID && versionEqual
            && exact(a.headline, b.headline) && exact(a.summary, b.summary) && exact(a.bodyText, b.bodyText)
            && a.authoredAt == b.authoredAt && a.modifiedAt == b.modifiedAt && a.observedAt == b.observedAt
            && exact(a.language, b.language) && exact(a.primaryLink?.absoluteString, b.primaryLink?.absoluteString)
            && exact(a.searchProjection, b.searchProjection) && a.providerID == b.providerID
    }

    private static func record(_ id: OriginRecordID, in db: Database) throws -> OriginRecord? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM origin_records WHERE id = ?", arguments: [key(id.rawValue)]) else { return nil }
        let f = ContentFields(row)
        guard let availability = OriginAvailability(rawValue: try f.string("availability")) else {
            throw ContentStoreError.corruption("availability")
        }
        return OriginRecord(id: OriginRecordID(rawValue: try f.uuid("id")),
            externalObjectIdentity: try f.identity(prefix: "object", role: .object),
            currentRevisionID: try f.optionalUUID("current_revision_id").map { OriginRevisionID(rawValue: $0) },
            availability: availability, firstObservedAt: try f.date("first_observed_at"), lastObservedAt: try f.date("last_observed_at"))
    }

    private static func revision(_ id: OriginRevisionID, in db: Database) throws -> OriginRevision? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM origin_revisions WHERE id = ?", arguments: [key(id.rawValue)]) else { return nil }
        let f = ContentFields(row)
        let versionFields = try ["connector_kind", "namespace", "value", "role"].map { try f.optionalString("version_" + $0) }
        let version: ExternalIdentity?
        if versionFields.allSatisfy({ $0 == nil }) { version = nil }
        else { version = try f.identity(prefix: "version", role: .version) }
        let link: URL?
        if let text = try f.optionalString("primary_link") {
            guard let url = URL(string: text), exact(url.absoluteString, text) else { throw ContentStoreError.corruption("primary_link") }
            link = url
        } else { link = nil }
        let originID = OriginRecordID(rawValue: try f.uuid("origin_record_id"))
        if let version {
            guard let origin = try record(originID, in: db),
                exact(version.connectorKind.rawValue, origin.connectorKind.rawValue) else {
                throw ContentStoreError.corruption("version connector/origin")
            }
        }
        return OriginRevision(id: OriginRevisionID(rawValue: try f.uuid("id")), originRecordID: originID,
            externalVersionIdentity: version, headline: try f.optionalString("headline"), summary: try f.optionalString("summary"),
            bodyText: try f.optionalString("body_text"), authoredAt: try f.optionalDate("authored_at"),
            modifiedAt: try f.optionalDate("modified_at"), observedAt: try f.date("observed_at"),
            language: try f.optionalString("language"), primaryLink: link, searchProjection: try f.optionalString("search_projection"),
            providerID: try f.optionalUUID("provider_id").map { ProviderID(rawValue: $0) })
    }

    private static func sameMediaCandidate(_ a: MediaCandidate, _ b: MediaCandidate) -> Bool {
        a.id == b.id && a.originRevisionID == b.originRevisionID
            && a.role == b.role && a.mediaClass == b.mediaClass
            && exact(a.remoteURL.absoluteString, b.remoteURL.absoluteString)
            && exact(a.declaredMimeType, b.declaredMimeType)
            && a.declaredPixelWidth == b.declaredPixelWidth && a.declaredPixelHeight == b.declaredPixelHeight
    }

    private static func validateMediaReplay(_ supplied: [MediaCandidate], revisionID: OriginRevisionID,
        in db: Database) throws {
        // Factual conflicts by ID take precedence over collection shape/order conflicts.
        for candidate in supplied {
            if let stored = try mediaCandidate(candidate.id, in: db), !sameMediaCandidate(stored, candidate) {
                throw ContentStoreError.mediaCandidateConflict(candidate.id)
            }
        }
        let stored = try mediaCandidates(revisionID, in: db)
        guard stored.count == supplied.count,
            zip(stored, supplied).allSatisfy({ sameMediaCandidate($0.0, $0.1) }) else {
            throw ContentStoreError.mediaCandidateCollectionConflict(revisionID)
        }
    }

    private static func mediaCandidates(_ revisionID: OriginRevisionID, in db: Database) throws -> [MediaCandidate] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT * FROM media_candidates WHERE origin_revision_id = ? ORDER BY ordinal ASC
            """, arguments: [key(revisionID.rawValue)])
        return try rows.enumerated().map { ordinal, row in
            let fields = ContentFields(row)
            guard try fields.integer("ordinal") == ordinal else {
                throw ContentStoreError.corruption("media candidate ordinal")
            }
            let candidate = try decodeMediaCandidate(row)
            guard candidate.originRevisionID == revisionID else {
                throw ContentStoreError.corruption("media candidate revision")
            }
            return candidate
        }
    }

    private static func mediaCandidate(_ id: MediaCandidateID, in db: Database) throws -> MediaCandidate? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM media_candidates WHERE id = ?",
            arguments: [key(id.rawValue)]) else { return nil }
        return try decodeMediaCandidate(row)
    }

    private static func decodeMediaCandidate(_ row: Row) throws -> MediaCandidate {
        let f = ContentFields(row)
        guard try f.integer("ordinal") >= 0,
            let role = MediaCandidateRole(rawValue: try f.string("role")),
            let mediaClass = MediaCandidateClass(rawValue: try f.string("media_class")) else {
            throw ContentStoreError.corruption("media candidate role/class/ordinal")
        }
        let locator = try f.string("remote_locator")
        guard let url = URL(string: locator), exact(url.absoluteString, locator),
            let candidate = MediaCandidate(id: MediaCandidateID(rawValue: try f.uuid("id")),
                originRevisionID: OriginRevisionID(rawValue: try f.uuid("origin_revision_id")),
                role: role, mediaClass: mediaClass, remoteURL: url,
                declaredMimeType: try f.optionalString("declared_mime_type"),
                declaredPixelWidth: try f.optionalInteger("declared_pixel_width"),
                declaredPixelHeight: try f.optionalInteger("declared_pixel_height")) else {
            throw ContentStoreError.corruption("media candidate locator/dimensions")
        }
        return candidate
    }

    private static func insertMediaCandidate(_ candidate: MediaCandidate, ordinal: Int, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO media_candidates (id, origin_revision_id, ordinal, role, media_class,
                remote_locator, declared_mime_type, declared_pixel_width, declared_pixel_height)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [key(candidate.id.rawValue), key(candidate.originRevisionID.rawValue), ordinal,
                candidate.role.rawValue, candidate.mediaClass.rawValue, candidate.remoteURL.absoluteString,
                candidate.declaredMimeType, candidate.declaredPixelWidth, candidate.declaredPixelHeight])
    }

    private static func current(_ record: OriginRecord, in db: Database) throws -> OriginRevision? {
        guard let id = record.currentRevisionID else { return nil }
        guard let revision = try revision(id, in: db), revision.originRecordID == record.id else {
            throw ContentStoreError.corruption("current_revision_id")
        }
        return revision
    }

    private static func insertRevision(_ revision: OriginRevision, in db: Database) throws {
        let version = revision.externalVersionIdentity
        try db.execute(sql: """
            INSERT INTO origin_revisions (id, origin_record_id, version_connector_kind, version_namespace,
                version_value, version_role, headline, summary, body_text, authored_at, modified_at, observed_at,
                language, primary_link, search_projection, provider_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [key(revision.id.rawValue), key(revision.originRecordID.rawValue),
                version?.connectorKind.rawValue, version?.namespace, version?.value, version?.role.rawValue,
                revision.headline, revision.summary, revision.bodyText,
                try revision.authoredAt.map { try PersistenceValueCoding.date($0, field: "authored_at") },
                try revision.modifiedAt.map { try PersistenceValueCoding.date($0, field: "modified_at") },
                try PersistenceValueCoding.date(revision.observedAt, field: "observed_at"), revision.language,
                revision.primaryLink?.absoluteString, revision.searchProjection, revision.providerID.map { key($0.rawValue) }])
    }

    private static func refreshSupply(_ id: OriginRecordID, in db: Database) throws {
        guard let record = try record(id, in: db) else { throw ContentStoreError.corruption("origin_record_id") }
        let hasMembership = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM source_memberships WHERE origin_record_id = ?)", arguments: [key(id.rawValue)]) == true
        guard (record.availability == .available || record.availability == .updated), record.currentRevisionID != nil, hasMembership else {
            try db.execute(sql: "DELETE FROM selection_supply WHERE origin_record_id = ?", arguments: [key(id.rawValue)])
            return
        }
        guard let revision = try current(record, in: db) else { throw ContentStoreError.corruption("current_revision_id") }
        let date = revision.authoredAt ?? revision.observedAt
        try db.execute(sql: """
            INSERT INTO selection_supply (origin_record_id, origin_revision_id, sort_date, sort_date_basis)
            VALUES (?, ?, ?, ?) ON CONFLICT(origin_record_id) DO UPDATE SET
                origin_revision_id = excluded.origin_revision_id, sort_date = excluded.sort_date,
                sort_date_basis = excluded.sort_date_basis
            """, arguments: [key(id.rawValue), key(revision.id.rawValue),
                try PersistenceValueCoding.date(date, field: "sort_date"), revision.authoredAt == nil ? "observedFallback" : "authored"])
    }
}

private struct ContentFields {
    let row: Row
    init(_ row: Row) { self.row = row }
    func optionalString(_ field: String) throws -> String? {
        let value: DatabaseValue = row[field]
        switch value.storage {
        case .null: return nil
        case .string(let text): return text
        default: throw ContentStoreError.corruption(field)
        }
    }
    func string(_ field: String) throws -> String {
        guard let text = try optionalString(field) else { throw ContentStoreError.corruption(field) }
        return text
    }
    func uuid(_ field: String) throws -> UUID { try PersistenceValueCoding.uuid(string(field), field: field) }
    func optionalUUID(_ field: String) throws -> UUID? { try optionalString(field).map { try PersistenceValueCoding.uuid($0, field: field) } }
    func optionalInteger(_ field: String) throws -> Int? {
        let value: DatabaseValue = row[field]
        switch value.storage {
        case .null: return nil
        case .int64(let number):
            guard let integer = Int(exactly: number) else { throw ContentStoreError.corruption(field) }
            return integer
        default: throw ContentStoreError.corruption(field)
        }
    }
    func integer(_ field: String) throws -> Int {
        guard let number = try optionalInteger(field) else { throw ContentStoreError.corruption(field) }
        return number
    }
    func optionalDate(_ field: String) throws -> Date? {
        let value: DatabaseValue = row[field]
        switch value.storage {
        case .null: return nil
        case .double(let real): return try PersistenceValueCoding.date(real, field: field)
        default: throw ContentStoreError.corruption(field)
        }
    }
    func date(_ field: String) throws -> Date {
        guard let date = try optionalDate(field) else { throw ContentStoreError.corruption(field) }
        return date
    }
    func identity(prefix: String, role: ExternalIdentityRole) throws -> ExternalIdentity {
        guard try string(prefix + "_role") == role.rawValue else { throw ContentStoreError.corruption(prefix + "_role") }
        return ExternalIdentity(connectorKind: ConnectorKind(rawValue: try string(prefix + "_connector_kind")),
            namespace: try string(prefix + "_namespace"), value: try string(prefix + "_value"), role: role)
    }
}
