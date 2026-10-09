// Owns: one Persistence-owned canonical admission transaction and mechanical command values.
// Does not own: connector translation, execution, planning or protocol transport.
import Foundation
import GRDB
import FeedMineDomain

public enum AcquisitionAdmissionStoreError: Error, Equatable, Sendable {
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
        public let precedence: PrecedenceCommand
        public let availability: OriginAvailability
        public let headline: String?
        public let summary: String?
        public let bodyText: String?
        public let authoredAt: Date?
        public let modifiedAt: Date?
        public let observedAt: Date
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
            mediaCandidates: [MediaCandidateCommand]) {
            self.objectIdentity = objectIdentity
            self.versionIdentity = versionIdentity
            self.precedence = precedence
            self.availability = availability
            self.headline = headline
            self.summary = summary
            self.bodyText = bodyText
            self.authoredAt = authoredAt
            self.modifiedAt = modifiedAt
            self.observedAt = observedAt
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
            for (index, observation) in command.observations.enumerated() {
                try Self.validate(observation, index: index, connectorKind: target.connectorKind)
            }
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
                        continue
                    }
                    guard media.count == stored.count,
                        zip(media, stored).allSatisfy({ ContentStore.admissionSameMediaCandidate($0.0, $0.1) }) else {
                        rejections.append(.init(index: index, reason: .knownVersionMediaConflict))
                        try contentStore.applyAvailability(observation.availability, observedAt: observation.observedAt,
                            recordID: recordID, in: db)
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
                    }), in: db)
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
