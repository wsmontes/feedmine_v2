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
    // One transient coverage fact per actually settled target, including empty/304/failure.
    // The coordinator is shared by cold and active-session work and lives for their association.
    // Checkpoints cannot represent an attempt that admitted nothing.
    private var settledGenerations: [AcquisitionTargetID: UInt64] = [:]
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

    /// What the runtime has observed about a target's own reachability this launch: how many consecutive
    /// attempts failed and, when it is cooling, when it may be tried again. It is a statement of measured work,
    /// never a prediction (T7's health column reads exactly this).
    public struct TargetHealth: Hashable, Sendable {
        public let consecutiveFailures: Int
        /// The monotonic deadline of the current cooling window, nil when the target is not cooling.
        public let coolingUntil: Double?
        public init(consecutiveFailures: Int, coolingUntil: Double?) {
            self.consecutiveFailures = consecutiveFailures
            self.coolingUntil = coolingUntil
        }
    }

    /// The health the coordinator can state right now for every target it has attempted. Targets never tried
    /// are absent — not reported as healthy.
    public func healthSnapshot() -> [AcquisitionTargetID: TargetHealth] {
        let now = monotonicSeconds()
        return failures.mapValues { failure in
            let deadline = backoff.map { failure.at + $0.delay(afterConsecutiveFailures: failure.consecutive) }
            let cooling = deadline.map { $0 > now } ?? false
            return TargetHealth(consecutiveFailures: failure.consecutive, coolingUntil: cooling ? deadline : nil)
        }
    }

    /// Review F08: the earliest monotonic time at which a cooling target becomes eligible again.
    public func nextCoolingExpiry() -> Double? {
        guard let backoff else { return nil }
        let now = monotonicSeconds()
        return failures.values.map { $0.at + backoff.delay(afterConsecutiveFailures: $0.consecutive) }.filter { $0 > now }.min()
    }

    /// Like `selectionOpportunity`, also lending the cooling set atomically with the position.
    public func selectionOpportunity(
        _ select: @Sendable (AcquisitionTargetID?, [AcquisitionActiveExecution], Set<AcquisitionTargetID>) throws -> AcquisitionPlanningResult
    ) rethrows -> AcquisitionPlanningResult {
        let cooling = coolingTargetIDs()
        return try selectionOpportunity { position, active in try select(position, active, cooling) }
    }

    /// Atomically supplies existing execution outcomes as coverage facts to the same planner.
    public func selectionOpportunity(
        _ select: @Sendable (AcquisitionTargetID?, [AcquisitionActiveExecution], Set<AcquisitionTargetID>,
            [AcquisitionTargetID: UInt64]) throws -> AcquisitionPlanningResult
    ) rethrows -> AcquisitionPlanningResult {
        let settled = settledGenerations
        return try selectionOpportunity { position, active, cooling in
            try select(position, active, cooling, settled)
        }
    }

    /// One settled execution, carried from the slot pump to the editorial consumer in completion order.
    private struct IndexedResult: Sendable {
        let index: Int
        let result: AcquisitionExecutionResult
    }

    /// The settled results of one call, written by the pump and read by the caller. The order is the plan's: a result
    /// that completed out of order still lands in its own slot.
    private final class SettledResults: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [Int: AcquisitionExecutionResult] = [:]
        func record(index: Int, result: AcquisitionExecutionResult) {
            lock.lock(); results[index] = result; lock.unlock()
        }
        func ordered(_ count: Int) -> [AcquisitionExecutionResult] {
            lock.lock(); defer { lock.unlock() }
            return (0..<count).compactMap { results[$0] }
        }
    }

    /// Runs a finite plan through a sliding window of at most `concurrentTargetLimit` executions and reports each
    /// result **as it settles**, in completion order. A cancelled result stops starting new work; a fatal error
    /// propagates and cancels the siblings. A limit of 1 is exactly sequential.
    ///
    /// R05: the network slot pump and the result consumer are two structured children of one group. The pump yields
    /// a settled, durable result to a stream whose backlog is bounded by the plan itself (one result per planned
    /// work item can exist), then refills the freed slot immediately. It never awaits the consumer: a suspended
    /// editorial callback cannot stop targets C and D from starting. The consumer drains the stream serially and
    /// awaits the caller's callback, so no unbounded task per result is created. Results already settled stay
    /// accounted for even when the callback fails or the round is cancelled.
    public nonisolated func executeConcurrently(_ work: [AcquisitionPlannedWork],
        operation: FeedReplenishmentOperationID? = nil, trace: ReplenishmentTrace? = nil,
        onResult: @escaping @Sendable (AcquisitionExecutionResult) async throws -> Void) async throws -> [AcquisitionExecutionResult] {
        guard !work.isEmpty else { return [] }
        let limit = concurrentTargetLimit
        let (stream, continuation) = AsyncStream.makeStream(of: IndexedResult.self,
            bufferingPolicy: .bufferingOldest(work.count))
        let settled = SettledResults()
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    // The durable outcome of each target is stated to the consumer here, before any editorial work;
                    // the pump is free to keep the slot window full while the consumer is suspended.
                    defer { continuation.finish() }
                    try await self.settle(work, limit: limit, operation: operation, trace: trace,
                        settled: settled, yield: { continuation.yield($0) })
                }
                group.addTask {
                    for await item in stream { try await onResult(item.result) }
                }
                do {
                    while let _ = try await group.next() {}
                } catch {
                    group.cancelAll()
                    continuation.finish()
                    throw error
                }
            }
        } catch {
            continuation.finish()
            throw error
        }
        return settled.ordered(work.count)
    }

    /// The slot pump: at most `limit` executions, refilled on every settlement. Reporting is a yield, never an
    /// `await` of the consumer.
    private func settle(_ work: [AcquisitionPlannedWork], limit: Int,
        operation: FeedReplenishmentOperationID?, trace: ReplenishmentTrace?,
        settled: SettledResults, yield: @escaping @Sendable (IndexedResult) -> Void) async throws {
        try await withThrowingTaskGroup(of: (Int, AcquisitionExecutionResult).self) { group in
            var next = 0, running = 0, stopped = false
            func startMore() {
                while !stopped, running < limit, next < work.count {
                    let index = next, item = work[index]
                    group.addTask { (index, try await self.execute(item, operation: operation, trace: trace)) }
                    next += 1; running += 1
                }
            }
            startMore()
            while let pair = try await group.next() {
                let (index, result) = pair
                running -= 1
                settled.record(index: index, result: result)
                yield(IndexedResult(index: index, result: result))
                if result.stop == .cancelled { stopped = true }
                if !stopped { try Task.checkCancellation() }
                startMore()
            }
        }
    }

    private func record(_ result: AcquisitionExecutionResult) {
        if result.stop != .cancelled { settledGenerations[result.targetID] = result.generation }
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

    public func execute(_ work: AcquisitionPlannedWork, operation: FeedReplenishmentOperationID? = nil,
        trace: ReplenishmentTrace? = nil) async throws -> AcquisitionExecutionResult {
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
            try await Self.run(target: target, bounds: bounds, connector: connector, database: database,
                operation: operation, trace: trace)
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
        connector: any FeedConnector, database: RuntimeDatabase,
        operation: FeedReplenishmentOperationID?, trace: ReplenishmentTrace?) async throws -> AcquisitionExecutionResult {
        let authority = AcquisitionTargetAuthority(database: database)
        let admission = AdmissionPolicy(database: database)
        var receipts: [AdmissionReceipt] = []
        var context = FeedConnectorExecutionContext()
        var attempt = 0
        func result(_ stop: AcquisitionExecutionStop) -> AcquisitionExecutionResult {
            AcquisitionExecutionResult(targetID: target.id, generation: target.generation, stop: stop, receipts: receipts)
        }
        /// The return of **one** pull, stated where it happened: including empty, failure and cancellation, because
        /// a pull that produced nothing is an outcome and not the absence of one. A joiner never reaches here — it
        /// reads the result of the execution that actually pulled, which is the attempt the arrival belongs to.
        func recordArrival(_ outcome: String, _ extra: [String: String] = [:]) {
            guard let operation, let trace else { return }
            var fields = ["op": operation.described, "kind": "network", "result": outcome,
                "target": target.id.rawValue.uuidString, "generation": String(target.generation),
                "attempt": String(attempt)]
            fields.merge(extra) { _, new in new }
            trace.record(ReplenishmentEvent.arrived, fields)
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
            attempt += 1
            let event: FeedConnectorEvent
            do { event = try await connector.pull(request, context: &context) }
            catch is CancellationError { recordArrival("cancelled"); return result(.cancelled) }
            catch let failure as ConnectorOperationalFailure {
                recordArrival("failure", ["failure": String(describing: failure)])
                return result(.operationalFailure(failure))
            }
            if Task.isCancelled { recordArrival("cancelled"); return result(.cancelled) }
            switch event {
            case .finished: recordArrival("finished"); return result(.finished)
            case .upToDate: recordArrival("up_to_date"); return result(.upToDate)
            case .disconnected: recordArrival("disconnected"); return result(.disconnected)
            case .cancelled: recordArrival("cancelled"); return result(.cancelled)
            case .batch(let batch, let transportByteCount):
                do { try validate(batch, transportByteCount: transportByteCount, request: request) }
                catch {
                    // The pull answered with bytes this build refuses: an outcome of the pull, named as such.
                    recordArrival("invalid_batch", ["observations": String(batch.observations.count),
                        "bytes": String(transportByteCount), "failure": String(describing: error)])
                    throw error
                }
                recordArrival("batch", ["observations": String(batch.observations.count),
                    "bytes": String(transportByteCount)])
                // Admission is synchronous and durable; the next iteration rereads its settled checkpoint.
                let receipt = try admission.admit(batch)
                if let operation, let trace {
                    trace.record(ReplenishmentEvent.concluded, ["op": operation.described,
                        "destination": "pool_admission", "target": receipt.targetID.rawValue.uuidString,
                        "generation": String(target.generation), "attempt": String(attempt),
                        "observations": String(batch.observations.count),
                        "rejected": String(receipt.rejectedObservations.count),
                        "checkpoint_advanced": receipt.checkpointAdvanced ? "true" : "false",
                        "selectable_supply_changed": receipt.selectableSupplyChanged ? "true" : "false"])
                }
                receipts.append(receipt)
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
