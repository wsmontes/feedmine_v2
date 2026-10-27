import FeedMineDomain

/// One opportunity's effective rule and its resolved memberships. This is a value transported from
/// composition to preparation/selection/commit, never a second policy registry.
public struct ProductionSourceExclusions: Hashable, Sendable {
    public let snapshot: ReaderSourceExclusionSnapshot
    public let sourceIDs: Set<SourceID>

    public init(snapshot: ReaderSourceExclusionSnapshot, resolvedSourceIDs: Set<SourceID>) {
        self.snapshot = snapshot
        self.sourceIDs = resolvedSourceIDs.union(snapshot.sourceIDs)
    }
}
