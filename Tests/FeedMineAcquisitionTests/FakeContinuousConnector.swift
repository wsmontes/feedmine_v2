import FeedMineAcquisition

// Test-only event control: one pending step and one suspended pull, never a step queue.
actor FakeContinuousConnector: FeedConnector {
    typealias Step = FakeFiniteConnector.Step
    private var pending: Step?
    private var waiting: CheckedContinuation<Step, Never>?
    private var pullEntered: CheckedContinuation<Void, Never>?
    private(set) var receivedPulls: [FeedConnectorPull] = []
    var bufferedCount: Int { pending == nil ? 0 : 1 }
    var waitingPullCount: Int { waiting == nil ? 0 : 1 }

    func offer(_ step: Step) -> Bool {
        if let waiting {
            self.waiting = nil
            waiting.resume(returning: step)
            return true
        }
        guard pending == nil else { return false }
        pending = step
        return true
    }

    // Synchronization is test-control only; it neither produces events nor polls.
    func waitForWaitingPull() async {
        if waiting != nil { return }
        precondition(pullEntered == nil)
        await withCheckedContinuation { pullEntered = $0 }
    }

    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        guard waiting == nil else { throw FakeFiniteConnector.Failure.overlappingPull }
        receivedPulls.append(request)
        let step: Step
        if let pending {
            self.pending = nil
            step = pending
        } else {
            step = await withCheckedContinuation { continuation in
                waiting = continuation
                pullEntered?.resume()
                pullEntered = nil
            }
        }
        return try step.event(for: request)
    }
}
