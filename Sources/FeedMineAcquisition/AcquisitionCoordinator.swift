// Owns: transient per-target execution sharing and bounded pull/admission settlement.
// Does not own: durable authority, planning, publication or Runtime handoff.
import Foundation
import FeedMineDomain
import FeedMinePersistence

public enum AcquisitionExecutionStop: Hashable, Sendable {
    case capacityReached
    case finished
    case upToDate
    case disconnected
    case cancelled
    case operationalFailure(ConnectorOperationalFailure)
}

public struct AcquisitionExecutionResult: Hashable, Sendable {
    public let targetID: AcquisitionTargetID
    public let generation: UInt64
    public let stop: AcquisitionExecutionStop
    public let receipts: [AdmissionReceipt]

    public init(targetID: AcquisitionTargetID, generation: UInt64, stop: AcquisitionExecutionStop,
        receipts: [AdmissionReceipt]) {
        self.targetID = targetID
        self.generation = generation
        self.stop = stop
        self.receipts = receipts
    }

    public var selectableSupplyChanged: Bool { receipts.contains { $0.selectableSupplyChanged } }
}

public enum AcquisitionCoordinatorError: Error, Equatable, Sendable {
    case missingConnector(AcquisitionTargetID)
    case missingActiveExecution(AcquisitionTargetID)
    case activeGenerationConflict(targetID: AcquisitionTargetID, activeGeneration: UInt64, requestedGeneration: UInt64)
    case targetMissing(AcquisitionTargetID)
    case targetRevoked(AcquisitionTargetID)
    case stalePlannedGeneration(targetID: AcquisitionTargetID, planned: UInt64, actual: UInt64)
    case targetConnectorMismatch(AcquisitionTargetID)
    case batchTargetMismatch(expected: AcquisitionTargetID, actual: AcquisitionTargetID)
    case batchGenerationMismatch(expected: UInt64, actual: UInt64)
    case batchCheckpointRevisionMismatch(expected: UInt64, actual: UInt64)
    case observationCapacityExceeded(limit: Int, actual: Int)
    case invalidTransportByteCount(Int)
    case byteCapacityExceeded(limit: Int, actual: Int)
}

public actor AcquisitionCoordinator {
    private struct InFlight {
        let generation: UInt64
        let task: Task<AcquisitionExecutionResult, Error>
    }
    private let database: RuntimeDatabase
    private let connectorForTarget: @Sendable (AcquisitionTarget) -> (any FeedConnector)?
    private let backoff: AcquisitionBackoffPolicy?
    private let monotonicSeconds: @Sendable () -> Double
    /// Operational bound on simultaneous target executions in `executeConcurrently` (≥ 1).
    public nonisolated let concurrentTargetLimit: Int
    private var selectionAfter: AcquisitionTargetID?
    private var inFlight: [AcquisitionTargetID: InFlight] = [:]
    private var failures: [AcquisitionTargetID: (consecutive: Int, at: Double)] = [:]

    public init(database: RuntimeDatabase,
        connectorForTarget: @escaping @Sendable (AcquisitionTarget) -> (any FeedConnector)?,
        backoff: AcquisitionBackoffPolicy? = nil, concurrentTargetLimit: Int = 1,
        monotonicSeconds: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.database = database
        self.connectorForTarget = connectorForTarget
        self.backoff = backoff
        self.concurrentTargetLimit = max(1, concurrentTargetLimit)
        self.monotonicSeconds = monotonicSeconds
    }

    /// Targets whose recent consecutive operational failures put them in a cooling window.
    /// A cooling target is skipped by planning so a broken feed stops consuming capacity (H2).
    public func coolingTargetIDs() -> Set<AcquisitionTargetID> {
        guard let backoff else { return [] }
        let now = monotonicSeconds()
        return Set(failures.compactMap { id, failure in
            now < failure.at + backoff.delay(afterConsecutiveFailures: failure.consecutive) ? id : nil
        })
    }

    /// Like `selectionOpportunity`, also lending the cooling set atomically with the position.
    public func selectionOpportunity(
        _ select: @Sendable (AcquisitionTargetID?, [AcquisitionActiveExecution], Set<AcquisitionTargetID>) throws -> AcquisitionPlanningResult
    ) rethrows -> AcquisitionPlanningResult {
        let cooling = coolingTargetIDs()
        return try selectionOpportunity { position, active in try select(position, active, cooling) }
    }

    /// Runs a finite plan through a sliding window of at most `concurrentTargetLimit` executions
    /// (v1 lesson, commit 814b0a5e: refill per completion, never per chunk). Results are returned
    /// in plan order; `onResult` sees each as it settles. A cancelled result stops starting new
    /// work; fatal errors propagate. A limit of 1 is exactly sequential.
    public nonisolated func executeConcurrently(_ work: [AcquisitionPlannedWork],
        onResult: @escaping @Sendable (AcquisitionExecutionResult) async throws -> Void) async throws -> [AcquisitionExecutionResult] {
        let limit = concurrentTargetLimit
        return try await withThrowingTaskGroup(of: (Int, AcquisitionExecutionResult).self) { group in
            var next = 0, running = 0, stopped = false
            var settled: [Int: AcquisitionExecutionResult] = [:]
            func startMore() {
                while !stopped, running < limit, next < work.count {
                    let index = next, item = work[index]
                    group.addTask { (index, try await self.execute(item)) }
                    next += 1; running += 1
                }
            }
            startMore()
            while let pair = try await group.next() {
                let (index, result) = pair
                running -= 1
                settled[index] = result
                try await onResult(result)
                if result.stop == .cancelled { stopped = true }
                if !stopped { try Task.checkCancellation() }
                startMore()
            }
            return work.indices.compactMap { settled[$0] }
        }
    }

    private func record(_ result: AcquisitionExecutionResult) {
        if case .operationalFailure = result.stop {
            let previous = failures[result.targetID]?.consecutive ?? 0
            failures[result.targetID] = (previous + 1, monotonicSeconds())
        } else if result.stop != .cancelled {
            failures.removeValue(forKey: result.targetID)
        }
    }

    public func activeExecutions() -> [AcquisitionActiveExecution] {
        inFlight.map { AcquisitionActiveExecution(targetID: $0.key, generation: $0.value.generation)! }
            .sorted { $0.targetID.rawValue.uuidString < $1.targetID.rawValue.uuidString }
    }

    /// Atomically lends the shared position to a caller's pure planner and consumes its finite selection.
    /// No eligibility, bounds or generation decisions are made by this owner.
    public func selectionOpportunity(
        _ select: @Sendable (AcquisitionTargetID?, [AcquisitionActiveExecution]) throws -> AcquisitionPlanningResult
    ) rethrows -> AcquisitionPlanningResult {
        let result = try select(selectionAfter, activeExecutions())
        if case .planned(let plan) = result, let last = plan.work.last {
            switch last {
            case .start(let target, _), .joinActive(let target): selectionAfter = target.id
            }
        }
        return result
    }

    public func execute(_ work: AcquisitionPlannedWork) async throws -> AcquisitionExecutionResult {
        let target: AcquisitionTarget
        switch work {
        case .start(let supplied, _), .joinActive(let supplied): target = supplied
        }
        if let existing = inFlight[target.id] {
            guard existing.generation == target.generation else {
                throw AcquisitionCoordinatorError.activeGenerationConflict(targetID: target.id,
                    activeGeneration: existing.generation, requestedGeneration: target.generation)
            }
            // Joiners share the original bounds/result and never remove execution ownership.
            return try await existing.task.value
        }
        guard case .start(_, let bounds) = work else {
            throw AcquisitionCoordinatorError.missingActiveExecution(target.id)
        }
        guard let connector = connectorForTarget(target) else {
            throw AcquisitionCoordinatorError.missingConnector(target.id)
        }
        let database = self.database
        let task = Task<AcquisitionExecutionResult, Error> {
            try await Self.run(target: target, bounds: bounds, connector: connector, database: database)
        }
        inFlight[target.id] = InFlight(generation: target.generation, task: task)
        // Only this creator removes the entry, on either result or error settlement.
        defer { inFlight.removeValue(forKey: target.id) }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        record(result)
        return result
    }

    private static func run(target: AcquisitionTarget, bounds: AcquisitionWorkBounds,
        connector: any FeedConnector, database: RuntimeDatabase) async throws -> AcquisitionExecutionResult {
        let authority = AcquisitionTargetAuthority(database: database)
        let admission = AdmissionPolicy(database: database)
        var receipts: [AdmissionReceipt] = []
        var context = FeedConnectorExecutionContext()
        func result(_ stop: AcquisitionExecutionStop) -> AcquisitionExecutionResult {
            AcquisitionExecutionResult(targetID: target.id, generation: target.generation, stop: stop, receipts: receipts)
        }
        while receipts.count < bounds.batchCapacity {
            if Task.isCancelled { return result(.cancelled) }
            guard let current = try authority.target(id: target.id) else {
                throw AcquisitionCoordinatorError.targetMissing(target.id)
            }
            guard current.state == .enabled else { throw AcquisitionCoordinatorError.targetRevoked(target.id) }
            guard current.generation == target.generation else {
                throw AcquisitionCoordinatorError.stalePlannedGeneration(targetID: target.id,
                    planned: target.generation, actual: current.generation)
            }
            guard current.connectorKind.rawValue.utf8.elementsEqual(target.connectorKind.rawValue.utf8) else {
                throw AcquisitionCoordinatorError.targetConnectorMismatch(target.id)
            }
            // Target and WorkBounds already guarantee this request's positive structural values.
            let request = FeedConnectorPull(targetID: current.id, targetGeneration: current.generation,
                checkpointRevision: current.checkpointRevision, checkpoint: current.checkpoint,
                observationCapacity: bounds.observationCapacityPerBatch, byteCapacity: bounds.byteCapacityPerBatch)!
            let event: FeedConnectorEvent
            do { event = try await connector.pull(request, context: &context) }
            catch is CancellationError { return result(.cancelled) }
            catch let failure as ConnectorOperationalFailure { return result(.operationalFailure(failure)) }
            if Task.isCancelled { return result(.cancelled) }
            switch event {
            case .finished: return result(.finished)
            case .upToDate: return result(.upToDate)
            case .disconnected: return result(.disconnected)
            case .cancelled: return result(.cancelled)
            case .batch(let batch, let transportByteCount):
                try validate(batch, transportByteCount: transportByteCount, request: request)
                // Admission is synchronous and durable; the next iteration rereads its settled checkpoint.
                receipts.append(try admission.admit(batch))
            }
        }
        return result(.capacityReached)
    }

    private static func validate(_ batch: AcquisitionBatch, transportByteCount: Int, request: FeedConnectorPull) throws {
        guard transportByteCount >= 0 else { throw AcquisitionCoordinatorError.invalidTransportByteCount(transportByteCount) }
        guard transportByteCount <= request.byteCapacity else {
            throw AcquisitionCoordinatorError.byteCapacityExceeded(limit: request.byteCapacity, actual: transportByteCount)
        }
        guard batch.observations.count <= request.observationCapacity else {
            throw AcquisitionCoordinatorError.observationCapacityExceeded(limit: request.observationCapacity, actual: batch.observations.count)
        }
        guard batch.targetID == request.targetID else {
            throw AcquisitionCoordinatorError.batchTargetMismatch(expected: request.targetID, actual: batch.targetID)
        }
        guard batch.targetGeneration == request.targetGeneration else {
            throw AcquisitionCoordinatorError.batchGenerationMismatch(expected: request.targetGeneration, actual: batch.targetGeneration)
        }
        guard batch.expectedCheckpointRevision == request.checkpointRevision else {
            throw AcquisitionCoordinatorError.batchCheckpointRevisionMismatch(expected: request.checkpointRevision,
                actual: batch.expectedCheckpointRevision)
        }
    }
}
