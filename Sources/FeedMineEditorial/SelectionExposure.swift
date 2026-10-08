// Owns: explicitly supplied pure exposure facts, independent of publication storage.
import FeedMineDomain

public struct SelectionExposureSnapshot: Hashable, Sendable {
    public let requestedRevisionIDs: [OriginRevisionID]
    public let publishedRevisionIDs: Set<OriginRevisionID>

    public init?(requestedRevisionIDs: [OriginRevisionID], publishedRevisionIDs: Set<OriginRevisionID>) {
        let requested = Set(requestedRevisionIDs)
        guard requested.count == requestedRevisionIDs.count,
            publishedRevisionIDs.isSubset(of: requested) else { return nil }
        self.requestedRevisionIDs = requestedRevisionIDs
        self.publishedRevisionIDs = publishedRevisionIDs
    }
}
