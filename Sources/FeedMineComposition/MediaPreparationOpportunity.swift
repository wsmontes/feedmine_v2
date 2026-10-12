// One media wait budget shared by every window in an explicit production opportunity.
import FeedMineDomain

public struct MediaPreparationOpportunity: Sendable {
    private let deadline: Double
    private let operation: @Sendable ([OriginRevisionID], Double) async -> Void

    public init(waitSeconds: Double, startedAt: Double,
        prepare: @escaping @Sendable ([OriginRevisionID], Double) async -> Void) {
        precondition(waitSeconds.isFinite && waitSeconds >= 0 && startedAt.isFinite)
        deadline = startedAt + waitSeconds
        operation = prepare
    }

    public func prepare(_ revisions: [OriginRevisionID]) async {
        await operation(revisions, deadline)
    }
}
