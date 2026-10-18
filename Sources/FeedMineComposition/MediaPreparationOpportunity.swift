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

    /// R07: state the coming slice's priority **without a barrier**. The request runs against the prefetcher's
    /// single-flight owner in its own task; the producing slice runs immediately with the readiness index it has.
    /// Individual readiness transitions already wake the existing reconsideration, so nothing polls and nothing
    /// waits for unrelated media. The budget is the opportunity's own fixed deadline (never renewed per slice).
    public func request(_ revisions: [OriginRevisionID]) {
        let operation = self.operation
        let deadline = self.deadline
        Task { await operation(revisions, deadline) }
    }
}
