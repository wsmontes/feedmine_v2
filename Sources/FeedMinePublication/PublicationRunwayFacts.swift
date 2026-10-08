// Owns: immutable semantic facts about committed publication history.
// Does not own: Editorial eligibility, Runway policy or production progress.

import FeedMineDomain

public enum ReadyAheadAmount: Hashable, Sendable {
    case exact(Int)
    case atLeast(Int)
}

public struct ReadyAheadFacts: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let anchorCardID: PublicationCardID
    public let observedTailCardID: PublicationCardID
    public let amount: ReadyAheadAmount
}

public struct PublishedExposureFacts: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let observedTailCardID: PublicationCardID
    public let requestedRevisionIDs: [OriginRevisionID]
    public let publishedRevisionIDs: Set<OriginRevisionID>
}

public enum PublicationAdvance: Hashable, Sendable {
    case same
    case backward
    case forwardExact(Int)
    /// A bound witness, not an exact distance or consumption rate.
    case forwardBeyondProbe(Int)
}

public struct PublicationAdvanceFacts: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let fromCardID: PublicationCardID
    public let toCardID: PublicationCardID
    public let advance: PublicationAdvance
}
