// Owns: explicitly supplied pure exposure facts, independent of publication storage.
import FeedMineDomain

public struct SelectionExposureSnapshot: Hashable, Sendable {
    public let requestedOriginIDs: [OriginRecordID]
    public let publishedOriginIDs: Set<OriginRecordID>

    public init?(requestedOriginIDs: [OriginRecordID], publishedOriginIDs: Set<OriginRecordID>) {
        let requested = Set(requestedOriginIDs)
        guard requested.count == requestedOriginIDs.count,
            publishedOriginIDs.isSubset(of: requested) else { return nil }
        self.requestedOriginIDs = requestedOriginIDs
        self.publishedOriginIDs = publishedOriginIDs
    }
}
