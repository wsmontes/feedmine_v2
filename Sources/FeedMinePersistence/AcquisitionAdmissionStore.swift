// Owns: one Persistence-owned canonical admission transaction and mechanical command values.
// Does not own: connector translation, execution, planning or protocol transport.
import Foundation
import GRDB
import FeedMineDomain

public enum AcquisitionAdmissionStoreError: Error, Equatable, Sendable {
    case unauthorizedSource(index: Int, targetID: AcquisitionTargetID, sourceID: SourceID)
    case invalidObservation(index: Int, field: String)
    case connectorMismatch(index: Int)
    case unsupportedUnversionedHistorical(index: Int)
}

public struct AcquisitionAdmissionStore: Sendable {
    private let database: RuntimeDatabase
    private let contentStore: ContentStore
    public init(database: RuntimeDatabase) {
        self.database = database
        self.contentStore = ContentStore(database: database)
    }

    public enum PrecedenceCommand: Hashable, Sendable {
        case makeCurrent
        case historicalOnly
    }

    public struct MembershipCommand: Hashable, Sendable {
        public let sourceID: SourceID
        public let kind: SourceMembershipKind
        public init(sourceID: SourceID, kind: SourceMembershipKind) {
            self.sourceID = sourceID
            self.kind = kind
        }
    }

    public struct MediaCandidateCommand: Hashable, Sendable {
        public let role: MediaCandidateRole
        public let mediaClass: MediaCandidateClass
        public let remoteURL: URL
        public let declaredMimeType: String?
        public let declaredPixelWidth: Int?
        public let declaredPixelHeight: Int?
        public init?(role: MediaCandidateRole, mediaClass: MediaCandidateClass, remoteURL: URL,
            declaredMimeType: String?, declaredPixelWidth: Int?, declaredPixelHeight: Int?) {
            guard let scheme = remoteURL.scheme?.lowercased(), scheme == "http" || scheme == "https",
                let host = remoteURL.host, !host.isEmpty else { return nil }
            switch (declaredPixelWidth, declaredPixelHeight) {
            case (nil, nil): break
            case (.some(let width), .some(let height)) where width > 0 && height > 0: break
            default: return nil
            }
            self.role = role
            self.mediaClass = mediaClass
            self.remoteURL = remoteURL
            self.declaredMimeType = declaredMimeType
            self.declaredPixelWidth = declaredPixelWidth
            self.declaredPixelHeight = declaredPixelHeight
        }
    }

    public struct ObservationCommand: Hashable, Sendable {
        public let objectIdentity: ExternalIdentity
        public let versionIdentity: ExternalIdentity?
        public let legacyVersionIdentity: ExternalIdentity?
        public let fingerprintGeneration: Int
        public let bodySourceElement: String?
        public let precedence: PrecedenceCommand
        public let availability: OriginAvailability
        public let headline: String?
        public let summary: String?
        public let bodyText: String?
        public let authoredAt: Date?
        public let modifiedAt: Date?
        public let observedAt: Date
        /// What the origin itself declared, when it declared something. The accepted values above are
        /// the claim or the observation instant, and the store refuses a pair that does not follow
        /// `OriginDeclaredInstant.accepted(observingAt:)`. nil is unknown evidence, not recency.
        ///
        /// TRANSIENT: the declaration is checked here and then dropped. Canonical supply persists the
        /// accepted value only, so a stored revision cannot be read as if the declaration survived, and an
        /// accepted instant equal to the observation instant stays ambiguous downstream. Persisting the
        /// declaration needs an authorized schema change, proposed separately.
        public let declaredAuthoredAt: Date?
        public let declaredModifiedAt: Date?
        public let language: String?
        public let primaryLink: URL?
        public let searchProjection: String?
        public let providerID: ProviderID?
        public let memberships: [MembershipCommand]
        public let mediaCandidates: [MediaCandidateCommand]
        public init(objectIdentity: ExternalIdentity, versionIdentity: ExternalIdentity?,
            precedence: PrecedenceCommand, availability: OriginAvailability, headline: String?, summary: String?,
            bodyText: String?, authoredAt: Date?, modifiedAt: Date?, observedAt: Date, language: String?,
            primaryLink: URL?, searchProjection: String?, providerID: ProviderID?, memberships: [MembershipCommand],
            mediaCandidates: [MediaCandidateCommand], fingerprintGeneration: Int = 1,
            legacyVersionIdentity: ExternalIdentity? = nil, bodySourceElement: String? = nil,
            declaredAuthoredAt: Date? = nil, declaredModifiedAt: Date? = nil) {
            self.objectIdentity = objectIdentity
            self.versionIdentity = versionIdentity
            self.legacyVersionIdentity = legacyVersionIdentity
            self.fingerprintGeneration = fingerprintGeneration
            self.bodySourceElement = bodySourceElement
            self.precedence = precedence
            self.availability = availability
            self.headline = headline
            self.summary = summary
            self.bodyText = bodyText
            self.authoredAt = authoredAt
            self.modifiedAt = modifiedAt
            self.observedAt = observedAt
            self.declaredAuthoredAt = declaredAuthoredAt
            self.declaredModifiedAt = declaredModifiedAt
            self.language = language
            self.primaryLink = primaryLink
            self.searchProjection = searchProjection
            self.providerID = providerID
            self.memberships = memberships
            self.mediaCandidates = mediaCandidates
        }
    }

    public struct BatchCommand: Hashable, Sendable {
        public let targetID: AcquisitionTargetID
        public let targetGeneration: UInt64
        public let expectedCheckpointRevision: UInt64
        public let observations: [ObservationCommand]
        public let nextCheckpoint: AcquisitionTargetStore.CheckpointRecord?
        public init(targetID: AcquisitionTargetID, targetGeneration: UInt64, expectedCheckpointRevision: UInt64,
            observations: [ObservationCommand], nextCheckpoint: AcquisitionTargetStore.CheckpointRecord?) {
            self.targetID = targetID
            self.targetGeneration = targetGeneration
            self.expectedCheckpointRevision = expectedCheckpointRevision
            self.observations = observations
            self.nextCheckpoint = nextCheckpoint
        }
    }

    public enum ObservationRejectionReason: Hashable, Sendable {
        case knownVersionPayloadConflict
        case knownVersionMediaConflict
    }

    public struct ObservationRejection: Hashable, Sendable {
        public let index: Int
        public let reason: ObservationRejectionReason
        public init(index: Int, reason: ObservationRejectionReason) {
            self.index = index
            self.reason = reason
        }
    }

    public struct AdmissionRecord: Hashable, Sendable {
        public let targetID: AcquisitionTargetID
        public let checkpointAdvanced: Bool
        public let selectableSupplyChanged: Bool
        public let rejectedObservations: [ObservationRejection]
        public init(targetID: AcquisitionTargetID, checkpointAdvanced: Bool, selectableSupplyChanged: Bool,
            rejectedObservations: [ObservationRejection] = []) {
            self.targetID = targetID
            self.checkpointAdvanced = checkpointAdvanced
            self.selectableSupplyChanged = selectableSupplyChanged
            self.rejectedObservations = rejectedObservations
        }
    }

    public func admit(_ command: BatchCommand) throws -> AdmissionRecord {
        try database.write { db in
            let target = try AcquisitionTargetStore.requireTarget(id: command.targetID, in: db)
            try AcquisitionTargetStore.validateEnabledStamp(target, expectedGeneration: command.targetGeneration,
                expectedCheckpointRevision: command.expectedCheckpointRevision)
            let authorized = try AcquisitionTargetStore.readSources(target, in: db) ?? []
            for (index, observation) in command.observations.enumerated() {
                try Self.validate(observation, index: index, connectorKind: target.connectorKind)
                for membership in observation.memberships where !authorized.contains(membership.sourceID) {
                    throw AcquisitionAdmissionStoreError.unauthorizedSource(index: index, targetID: target.id, sourceID: membership.sourceID)
                }
            }
            let activeFingerprintGeneration = try contentStore.admissionCurrentFingerprintGeneration(in: db)
            var before: [OriginRecordID: SupplyFingerprint] = [:]
            var rejections: [ObservationRejection] = []
            for (index, observation) in command.observations.enumerated() {
                let record = try contentStore.admissionRecord(matching: observation.objectIdentity, in: db)
                let recordID = record?.id ?? OriginRecordID()
                if before[recordID] == nil { before[recordID] = try Self.fingerprint(recordID, in: db) }
                let current = try record.flatMap { try contentStore.admissionCurrentRevision(for: $0, in: db) }
                let knownVersion = try observation.versionIdentity.flatMap {
                    try contentStore.admissionRevision(originRecordID: recordID, matching: $0, in: db)
                }
                // K-15: the new parser may discover body in bytes that created a generation-1 revision.
                // Match that exact legacy identity first; its persisted revision never changes. The first
                // declared body is a baseline enrichment, and only a subsequent different body is an edit.
                if knownVersion == nil, observation.fingerprintGeneration == activeFingerprintGeneration {
                    let historical = try observation.legacyVersionIdentity.flatMap {
                        try contentStore.admissionRevision(originRecordID: recordID, matching: $0, in: db)
                    } ?? (observation.versionIdentity == nil && current?.externalVersionIdentity == nil ? current : nil)
                    if let historical, try contentStore.admissionFingerprintGeneration(of: historical.id, in: db) == 1,
                        Self.sameExceptBody(observation, historical) {
                        let storedMedia = try contentStore.admissionMediaCandidates(originRevisionID: historical.id, in: db)
                        let proposedMedia = try Self.media(observation, revisionID: historical.id, reusing: storedMedia, index: index)
                        let sameMedia = proposedMedia.count == storedMedia.count
                            && zip(proposedMedia, storedMedia).allSatisfy {
                                ContentStore.admissionSameMediaCandidate($0.0, $0.1)
                            }
                        if sameMedia {
                            let enrichment = try contentStore.admissionEnrichedBody(of: historical.id, in: db)
                            // "absent" is meaningful evidence: if generation 2 already observed
                            // no body, its later appearance is a publisher edit, not parser enrichment.
                            let source = observation.bodySourceElement ?? "absent"
                            let sameBody: Bool
                            if let enrichment {
                                sameBody = enrichment.source == source && enrichment.text == observation.bodyText
                            } else {
                                sameBody = historical.bodyText == observation.bodyText
                            }
                            if sameBody || (enrichment == nil && historical.bodyText == nil) {
                                if enrichment == nil && historical.bodyText == nil {
                                    try contentStore.admissionAddBodyEnrichment(observation.bodyText,
                                        source: source, revisionID: historical.id, in: db)
                                }
                                try contentStore.apply(ContentStore.CanonicalChange(recordID: recordID,
                                    externalObjectIdentity: observation.objectIdentity, revision: historical,
                                    mediaCandidates: storedMedia, availability: observation.availability,
                                    observedAt: observation.observedAt,
                                    expectedCurrent: current.map { .revision($0.id) } ?? .none,
                                    currentUpdate: .unchanged,
                                    membershipMutations: observation.memberships.map {
                                        .upsert(sourceID: $0.sourceID, kind: $0.kind, observedAt: observation.observedAt)
                                    }), in: db)
                                continue
                            }
                        }
                    }
                }
                let revision: OriginRevision
                let media: [MediaCandidate]
                let update: ContentStore.CurrentRevisionUpdate
                if let knownVersion {
                    revision = Self.revision(observation, recordID: recordID, id: knownVersion.id, observedAt: knownVersion.observedAt)
                    let stored = try contentStore.admissionMediaCandidates(originRevisionID: knownVersion.id, in: db)
                    media = try Self.media(observation, revisionID: knownVersion.id, reusing: stored, index: index)
                    // Compare using ContentStore's byte-exact authority before any canonical write.
                    // Stored media is decoded first so corruption is never classified as a payload conflict.
                    guard ContentStore.admissionSameRevision(revision, knownVersion) else {
                        rejections.append(.init(index: index, reason: .knownVersionPayloadConflict))
                        try contentStore.applyAvailability(observation.availability, observedAt: observation.observedAt,
                            recordID: recordID, in: db)
                        try contentStore.applyMemberships(observation.memberships.map {
                            .upsert(sourceID: $0.sourceID, kind: $0.kind, observedAt: observation.observedAt)
                        }, recordID: recordID, in: db)
                        continue
                    }
                    guard media.count == stored.count,
                        zip(media, stored).allSatisfy({ ContentStore.admissionSameMediaCandidate($0.0, $0.1) }) else {
                        rejections.append(.init(index: index, reason: .knownVersionMediaConflict))
                        try contentStore.applyAvailability(observation.availability, observedAt: observation.observedAt,
                            recordID: recordID, in: db)
                        try contentStore.applyMemberships(observation.memberships.map {
                            .upsert(sourceID: $0.sourceID, kind: $0.kind, observedAt: observation.observedAt)
                        }, recordID: recordID, in: db)
                        continue
                    }
                    // A known historical version cannot supersede a different current revision.
                    update = observation.precedence == .makeCurrent && current == nil ? .useSuppliedRevision : .unchanged
                } else if observation.versionIdentity == nil, let current, current.externalVersionIdentity == nil {
                    let comparison = Self.revision(observation, recordID: recordID, id: current.id, observedAt: current.observedAt)
                    let stored = try contentStore.admissionMediaCandidates(originRevisionID: current.id, in: db)
                    let comparisonMedia = try Self.media(observation, revisionID: current.id, reusing: stored, index: index)
                    if ContentStore.admissionSameRevision(comparison, current), comparisonMedia.count == stored.count,
                        zip(comparisonMedia, stored).allSatisfy({ ContentStore.admissionSameMediaCandidate($0.0, $0.1) }) {
                        revision = comparison
                        media = comparisonMedia
                        update = .unchanged
                    } else {
                        revision = Self.revision(observation, recordID: recordID, id: OriginRevisionID(), observedAt: observation.observedAt)
                        media = try Self.media(observation, revisionID: revision.id, reusing: [], index: index)
                        update = .useSuppliedRevision
                    }
                } else {
                    revision = Self.revision(observation, recordID: recordID, id: OriginRevisionID(), observedAt: observation.observedAt)
                    media = try Self.media(observation, revisionID: revision.id, reusing: [], index: index)
                    update = observation.precedence == .makeCurrent ? .useSuppliedRevision : .unchanged
                }
                try contentStore.apply(ContentStore.CanonicalChange(recordID: recordID,
                    externalObjectIdentity: observation.objectIdentity, revision: revision, mediaCandidates: media,
                    availability: observation.availability, observedAt: observation.observedAt,
                    expectedCurrent: current.map { .revision($0.id) } ?? .none, currentUpdate: update,
                    membershipMutations: observation.memberships.map {
                        .upsert(sourceID: $0.sourceID, kind: $0.kind, observedAt: observation.observedAt)
                    }, fingerprintGeneration: observation.fingerprintGeneration,
                    bodySourceElement: observation.bodySourceElement), in: db)
            }
            var supplyChanged = false
            for (id, fingerprint) in before {
                if try Self.fingerprint(id, in: db) != fingerprint { supplyChanged = true }
            }
            if let checkpoint = command.nextCheckpoint {
                _ = try AcquisitionTargetStore.applyCheckpoint(checkpoint, to: target, in: db)
            }
            return AdmissionRecord(targetID: command.targetID, checkpointAdvanced: command.nextCheckpoint != nil,
                selectableSupplyChanged: supplyChanged, rejectedObservations: rejections)
        }
    }

    private static func validate(_ value: ObservationCommand, index: Int, connectorKind: ConnectorKind) throws {
        func invalid(_ field: String) -> AcquisitionAdmissionStoreError { .invalidObservation(index: index, field: field) }
        guard value.objectIdentity.role == .object else { throw invalid("objectIdentity.role") }
        guard !value.objectIdentity.connectorKind.rawValue.utf8.isEmpty else { throw invalid("objectIdentity.connectorKind") }
        guard value.objectIdentity.connectorKind.rawValue.utf8.elementsEqual(connectorKind.rawValue.utf8) else {
            throw AcquisitionAdmissionStoreError.connectorMismatch(index: index)
        }
        guard value.fingerprintGeneration == 1 || value.fingerprintGeneration == 2 else {
            throw invalid("fingerprintGeneration")
        }
        guard value.bodySourceElement == nil
            || (value.fingerprintGeneration == 2 && value.bodyText != nil) else {
            throw invalid("bodySourceElement")
        }
        if let legacy = value.legacyVersionIdentity {
            guard value.fingerprintGeneration == 2, legacy.role == .version,
                legacy.connectorKind == value.objectIdentity.connectorKind else {
                throw invalid("legacyVersionIdentity")
            }
        }
        if let version = value.versionIdentity {
            guard version.role == .version else { throw invalid("versionIdentity.role") }
            guard version.connectorKind.rawValue.utf8.elementsEqual(value.objectIdentity.connectorKind.rawValue.utf8) else {
                throw invalid("versionIdentity.connectorKind")
            }
        } else if value.precedence == .historicalOnly {
            throw AcquisitionAdmissionStoreError.unsupportedUnversionedHistorical(index: index)
        }
        guard Set(value.memberships.map(\.sourceID)).count == value.memberships.count else { throw invalid("memberships") }
        guard value.observedAt.timeIntervalSince1970.isFinite else { throw invalid("observedAt") }
        guard value.authoredAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw invalid("authoredAt") }
        guard value.modifiedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw invalid("modifiedAt") }
        // TX-07D: a declaration is evidence, and acceptance is a stated rule, not a convention. When an
        // origin's claim is present the accepted value must be exactly what the observation could accept
        // (`OriginDeclaredInstant.accepted(observingAt:)`), so no producer can present a claim as though
        // the observation had accepted it, and a claim ahead of the observation never becomes a real date.
        for (claim, accepted, field) in [(value.declaredAuthoredAt, value.authoredAt, "declaredAuthoredAt"),
                                         (value.declaredModifiedAt, value.modifiedAt, "declaredModifiedAt")] {
            guard let claim else { continue }
            guard claim.timeIntervalSince1970.isFinite else { throw invalid(field) }
            guard accepted == OriginDeclaredInstant(claimed: claim).accepted(observingAt: value.observedAt) else {
                throw invalid(field)
            }
        }
    }

    private static func sameExceptBody(_ incoming: ObservationCommand, _ old: OriginRevision) -> Bool {
        incoming.headline == old.headline && incoming.summary == old.summary
            && incoming.authoredAt == old.authoredAt && incoming.modifiedAt == old.modifiedAt
            && incoming.language == old.language && incoming.primaryLink == old.primaryLink
            && incoming.searchProjection == old.searchProjection && incoming.providerID == old.providerID
    }

    private static func revision(_ value: ObservationCommand, recordID: OriginRecordID,
        id: OriginRevisionID, observedAt: Date) -> OriginRevision {
        OriginRevision(id: id, originRecordID: recordID, externalVersionIdentity: value.versionIdentity,
            headline: value.headline, summary: value.summary, bodyText: value.bodyText, authoredAt: value.authoredAt,
            modifiedAt: value.modifiedAt, observedAt: observedAt, language: value.language, primaryLink: value.primaryLink,
            searchProjection: value.searchProjection, providerID: value.providerID)
    }

    private static func media(_ value: ObservationCommand, revisionID: OriginRevisionID,
        reusing stored: [MediaCandidate], index: Int) throws -> [MediaCandidate] {
        try value.mediaCandidates.enumerated().map { ordinal, claim in
            guard let result = MediaCandidate(id: ordinal < stored.count ? stored[ordinal].id : MediaCandidateID(),
                originRevisionID: revisionID, role: claim.role, mediaClass: claim.mediaClass, remoteURL: claim.remoteURL,
                declaredMimeType: claim.declaredMimeType, declaredPixelWidth: claim.declaredPixelWidth,
                declaredPixelHeight: claim.declaredPixelHeight) else {
                throw AcquisitionAdmissionStoreError.invalidObservation(index: index, field: "mediaCandidates")
            }
            return result
        }
    }

    private enum SupplyFingerprint: Equatable {
        case absent
        case selectable(revision: String, sortDate: Double, basis: String, sources: Set<String>)
    }

    private static func fingerprint(_ id: OriginRecordID, in db: Database) throws -> SupplyFingerprint {
        let key = id.rawValue.uuidString.lowercased()
        guard let row = try Row.fetchOne(db, sql: """
            SELECT origin_revision_id, sort_date, sort_date_basis FROM selection_supply WHERE origin_record_id = ?
            """, arguments: [key]) else { return .absent }
        let revision: String = row["origin_revision_id"], date: Double = row["sort_date"], basis: String = row["sort_date_basis"]
        let sources = try String.fetchAll(db, sql: "SELECT source_id FROM source_memberships WHERE origin_record_id = ?", arguments: [key])
        return .selectable(revision: revision, sortDate: date, basis: basis, sources: Set(sources))
    }
}
