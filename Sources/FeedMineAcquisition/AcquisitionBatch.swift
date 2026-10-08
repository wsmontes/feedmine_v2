// Owns: protocol-free translated observations and explicit target/checkpoint admission stamps.
// Does not own: canonical identity allocation, transport, bytes or acquisition execution.
import Foundation
import FeedMineDomain

public enum AcquisitionPrecedence: Hashable, Sendable {
    case makeCurrent
    case historicalOnly
}

public struct AcquisitionMembershipClaim: Hashable, Sendable {
    public let sourceID: SourceID
    public let kind: SourceMembershipKind
    public init(sourceID: SourceID, kind: SourceMembershipKind) {
        self.sourceID = sourceID
        self.kind = kind
    }
}

public struct AcquisitionMediaCandidateClaim: Hashable, Sendable {
    public let role: MediaCandidateRole
    public let mediaClass: MediaCandidateClass
    public let remoteURL: URL
    public let declaredMimeType: String?
    public let declaredPixelWidth: Int?
    public let declaredPixelHeight: Int?
    public init?(role: MediaCandidateRole, mediaClass: MediaCandidateClass, remoteURL: URL, declaredMimeType: String?,
        declaredPixelWidth: Int?, declaredPixelHeight: Int?) {
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

public struct AcquisitionObservation: Hashable, Sendable {
    public let objectIdentity: ExternalIdentity
    public let versionIdentity: ExternalIdentity?
    public let precedence: AcquisitionPrecedence
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
    public let memberships: [AcquisitionMembershipClaim]
    public let mediaCandidates: [AcquisitionMediaCandidateClaim]
    public init?(objectIdentity: ExternalIdentity, versionIdentity: ExternalIdentity?,
        precedence: AcquisitionPrecedence, availability: OriginAvailability, headline: String?, summary: String?,
        bodyText: String?, authoredAt: Date?, modifiedAt: Date?, observedAt: Date, language: String?,
        primaryLink: URL?, searchProjection: String?, providerID: ProviderID?,
        memberships: [AcquisitionMembershipClaim], mediaCandidates: [AcquisitionMediaCandidateClaim]) {
        guard objectIdentity.role == .object, !objectIdentity.connectorKind.rawValue.utf8.isEmpty,
            versionIdentity.map({ $0.role == .version && $0.connectorKind.rawValue.utf8.elementsEqual(objectIdentity.connectorKind.rawValue.utf8) }) ?? true,
            Set(memberships.map(\.sourceID)).count == memberships.count,
            observedAt.timeIntervalSince1970.isFinite,
            authoredAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
            modifiedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { return nil }
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

public struct AcquisitionBatch: Hashable, Sendable {
    public let targetID: AcquisitionTargetID
    public let targetGeneration: UInt64
    public let expectedCheckpointRevision: UInt64
    public let observations: [AcquisitionObservation]
    public let nextCheckpoint: AcquisitionCheckpoint?
    public init?(targetID: AcquisitionTargetID, targetGeneration: UInt64, expectedCheckpointRevision: UInt64,
        observations: [AcquisitionObservation], nextCheckpoint: AcquisitionCheckpoint?) {
        guard targetGeneration > 0, !observations.isEmpty || nextCheckpoint != nil else { return nil }
        self.targetID = targetID
        self.targetGeneration = targetGeneration
        self.expectedCheckpointRevision = expectedCheckpointRevision
        self.observations = observations
        self.nextCheckpoint = nextCheckpoint
    }
}

public struct AdmissionReceipt: Hashable, Sendable {
    public let targetID: AcquisitionTargetID
    public let checkpointAdvanced: Bool
    public let selectableSupplyChanged: Bool
    public init(targetID: AcquisitionTargetID, checkpointAdvanced: Bool, selectableSupplyChanged: Bool) {
        self.targetID = targetID
        self.checkpointAdvanced = checkpointAdvanced
        self.selectableSupplyChanged = selectableSupplyChanged
    }
}
