import FeedMineAcquisition

// Test-only finite script. Each pull consumes at most one step.
actor FakeFiniteConnector: FeedConnector {
    enum Failure: Error, Equatable, Sendable {
        case expected
        case overlappingPull
    }
    enum Step: Sendable {
        case batch(observations: [AcquisitionObservation], checkpoint: AcquisitionCheckpoint?, bytes: Int)
        case finished
        case upToDate
        case cancelled
        case disconnected
        case cancellationError
        case failure
        case raw(FeedConnectorEvent)

        func event(for request: FeedConnectorPull) throws -> FeedConnectorEvent {
            switch self {
            case .batch(let observations, let checkpoint, let bytes):
                return .batch(AcquisitionBatch(targetID: request.targetID,targetGeneration: request.targetGeneration,
                    expectedCheckpointRevision: request.checkpointRevision,observations: observations,nextCheckpoint: checkpoint)!,
                    transportByteCount: bytes)
            case .finished: return .finished
            case .upToDate: return .upToDate
            case .cancelled: return .cancelled
            case .disconnected: return .disconnected
            case .cancellationError: throw CancellationError()
            case .failure: throw Failure.expected
            case .raw(let event): return event
            }
        }
    }
    private let script: [Step]
    private var index = 0
    private(set) var receivedPulls: [FeedConnectorPull] = []

    init(_ script: [Step]) { self.script = script }

    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent {
        receivedPulls.append(request)
        guard index < script.count else { return .finished }
        let step = script[index]
        index += 1
        return try step.event(for: request)
    }
}
