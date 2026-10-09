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

    public init(originRecordID: OriginRecordID, originRevisionID: OriginRevisionID,
        headline: String?, summary: String?, timestamp: CandidateTimestamp,
        language: String?, providerID: ProviderID?, sourceIDs: Set<SourceID> = [], primaryMediaLocator: String? = nil) {
        self.originRecordID = originRecordID
        self.originRevisionID = originRevisionID
        self.headline = headline
        self.summary = summary
        self.timestamp = timestamp
        self.language = language
        self.providerID = providerID
        self.sourceIDs = sourceIDs
        self.primaryMediaLocator = primaryMediaLocator
    }
}
