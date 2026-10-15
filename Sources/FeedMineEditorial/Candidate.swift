// Owns: editorial candidate identity, narrow content and explicit timestamp meaning.
// Does not own: Persistence rows, PublishedCard snapshots, selection or ranking.

import Foundation
import FeedMineDomain

public enum CandidateTimestampKind: Hashable, Sendable {
    case authored
    case observed
}

public struct CandidateTimestamp: Hashable, Sendable {
    public let value: Date
    public let kind: CandidateTimestampKind

    public init(value: Date, kind: CandidateTimestampKind) {
        self.value = value
        self.kind = kind
    }
}

public struct Candidate: Hashable, Sendable {
    public let originRecordID: OriginRecordID
    public let originRevisionID: OriginRevisionID
    public let headline: String?
    public let summary: String?
    public let timestamp: CandidateTimestamp
    public let language: String?
    public let providerID: ProviderID?
    /// Sources this origin belongs to. Empty means unknown; it never constrains adjacency (PD-4).
    public let sourceIDs: Set<SourceID>
    /// Ordinal-0 canonical media locator; part of PD-1 material identity.
    public let primaryMediaLocator: String?
    /// Canonical body text or a generation-1 enrichment baseline for material recurrence.
    public let declaredBody: String?
    /// Generation 2 observed body presence/absence, or generation 1 has a baseline.
    /// False means legacy body state genuinely unknown (not the same as observed absent).
    public let bodyObserved: Bool
    /// Article URL the card opens (review F10).
    public let primaryLink: URL?

    public init(originRecordID: OriginRecordID, originRevisionID: OriginRevisionID,
        headline: String?, summary: String?, timestamp: CandidateTimestamp,
        language: String?, providerID: ProviderID?, sourceIDs: Set<SourceID> = [], primaryMediaLocator: String? = nil,
        primaryLink: URL? = nil, declaredBody: String? = nil, bodyObserved: Bool = false) {
        self.originRecordID = originRecordID
        self.originRevisionID = originRevisionID
        self.headline = headline
        self.summary = summary
        self.timestamp = timestamp
        self.language = language
        self.providerID = providerID
        self.sourceIDs = sourceIDs
        self.primaryMediaLocator = primaryMediaLocator
        self.primaryLink = primaryLink
        self.declaredBody = declaredBody
        self.bodyObserved = bodyObserved || declaredBody != nil
    }
}
