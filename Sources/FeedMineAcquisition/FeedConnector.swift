// Owns: one bounded pull request and one protocol-free event per call.
// Does not own: durable writes, planning, publication or transport-specific models.
import FeedMineDomain

public struct FeedConnectorPull: Hashable, Sendable {
    public let targetID: AcquisitionTargetID
    public let targetGeneration: UInt64
    public let checkpointRevision: UInt64
    public let checkpoint: AcquisitionCheckpoint?
    public let observationCapacity: Int
    public let byteCapacity: Int

    public init?(targetID: AcquisitionTargetID, targetGeneration: UInt64, checkpointRevision: UInt64,
        checkpoint: AcquisitionCheckpoint?, observationCapacity: Int, byteCapacity: Int) {
        guard targetGeneration > 0, observationCapacity > 0, byteCapacity > 0 else { return nil }
        self.targetID = targetID
        self.targetGeneration = targetGeneration
        self.checkpointRevision = checkpointRevision
        self.checkpoint = checkpoint
        self.observationCapacity = observationCapacity
        self.byteCapacity = byteCapacity
    }
}

public enum FeedConnectorEvent: Hashable, Sendable {
    case batch(AcquisitionBatch, transportByteCount: Int)
    case finished
    case upToDate
    case cancelled
    case disconnected
}

/// Opaque connector state lent exclusively to sequential pulls of one coordinator execution.
/// It has no durable authority and is released with that execution's stack.
public struct FeedConnectorExecutionContext: Sendable {
    public var retainedValue: (any Sendable)?
    public init() { retainedValue = nil }
}

public protocol FeedConnector: Sendable {
    func pull(_ request: FeedConnectorPull) async throws -> FeedConnectorEvent
    func pull(_ request: FeedConnectorPull, context: inout FeedConnectorExecutionContext) async throws -> FeedConnectorEvent
}

public extension FeedConnector {
    func pull(_ request: FeedConnectorPull, context: inout FeedConnectorExecutionContext) async throws -> FeedConnectorEvent {
        try await pull(request)
    }
}
