// Owns: one bounded Runtime intent-to-Acquisition handoff and committed supply notifications.
// Does not own: eligibility discovery, local production, publication or scheduling.
import FeedMineAcquisition
import FeedMineDomain
import FeedMineRuntime

public enum RunwayAcquisitionCycleError: Error, Equatable, Sendable {
    case staleIntent
}

public enum RunwayAcquisitionCycleOutcome: Hashable, Sendable {
    case executed([AcquisitionExecutionResult])
    case acceptedUnavailable(AcquisitionPlanningDisposition)
    case deferred(AcquisitionPlanningDisposition)

    public var selectableSupplyChanged: Bool {
        switch self {
        case .executed(let results): return results.contains { $0.selectableSupplyChanged }
        case .acceptedUnavailable, .deferred: return false
        }
    }
}

public enum RunwayAcquisitionStart: Sendable {
    case round(RunwayAcquisitionRound)
    /// The plan only joined executions another owner already runs. Their durable results notify the runway when
    /// they settle in their own round, so this opportunity states the fact and returns instead of holding the
    /// reader's drain on an unrelated pull (P02).
    case joining
    case acceptedUnavailable(AcquisitionPlanningDisposition)
    case deferred(AcquisitionPlanningDisposition)
}

/// A started acquisition round: its durable results, in completion order, and the completion of the whole round.
public struct RunwayAcquisitionRound: Sendable {
    public let results: AsyncStream<AcquisitionExecutionResult>
    public let completion: Task<[AcquisitionExecutionResult], Error>
    /// The targets this round actually owns (`.start` work), in plan order.
    public let targetIDs: [AcquisitionTargetID]
}

public struct RunwayAcquisitionCycle: Sendable {
    private let runway: RunwayController
    private let coordinator: AcquisitionCoordinator
    /// Optional evidence of the replenishment attempt the intent names; nil records nothing.
    private let trace: ReplenishmentTrace?

    public init(runway: RunwayController, coordinator: AcquisitionCoordinator,
        trace: ReplenishmentTrace? = nil) {
        self.runway = runway
        self.coordinator = coordinator
        self.trace = trace
    }

    /// R06: one finite round, observed as it settles. The plan is acknowledged and owned exactly as the snapshot gate
    /// requires, but the durable results are streamed to the caller instead of being awaited as one block: a supply
    /// change that is already durable is a fact for the existing owner **while the round is still running**, so a slow
    /// target can no longer hold the fast target's cards behind the end of the round. The stream's backlog is bounded
    /// by the plan (at most one result per planned item); the round keeps running after the caller stops reading.
    public func start(_ intent: RunwayAcquisitionIntent, eligibleTargets: [AcquisitionTarget],
        resources: AcquisitionPlanningResources, preferUnattempted: Bool = false,
        onDurableResult: (@Sendable (AcquisitionExecutionResult) async -> Void)? = nil) async throws
        -> RunwayAcquisitionStart {
        let snapshot = await runway.snapshot()
        guard snapshot.outstandingAcquisition == intent else { throw RunwayAcquisitionCycleError.staleIntent }
        let planning = try await coordinator.selectionOpportunity { position, active, cooling, settled in
            let available = eligibleTargets.filter { !cooling.contains($0.id) }
            let uncovered = available.filter { settled[$0.id] != $0.generation }
            return try AcquisitionPlanner.plan(demand: intent.demand,
                eligibleTargets: preferUnattempted && !uncovered.isEmpty ? uncovered : available,
                activeExecutions: active, resources: resources, selectionAfter: position)
        }
        switch planning {
        case .disposition(.noEligibleTargets):
            // Review F08: eligible targets that are only cooling down are a temporary denial. The
            // intent stays outstanding so the opportunity at cooling expiry resumes it.
            if !eligibleTargets.isEmpty, await coordinator.nextCoolingExpiry() != nil {
                return .deferred(.resourceDenied)
            }
            try await runway.acknowledgeAcquisition(intent)
            return .acceptedUnavailable(.noEligibleTargets)
        case .disposition(.resourceDenied):
            return .deferred(.resourceDenied)
        case .disposition(.activeGenerationConflict):
            return .deferred(.activeGenerationConflict)
        case .planned(let plan):
            // Ownership of the finite plan is accepted before any external work begins.
            try await runway.acknowledgeAcquisition(intent)
            try Task.checkCancellation()
            // P02: joining an execution another owner already runs is not this opportunity's work. Its durable
            // result reaches the runway through that owner's callback; awaiting it here held the drain on an
            // unrelated slow pull and delayed the late drive that publishes what already settled.
            let owned = plan.work.filter { work in
                if case .start = work { return true }
                return false
            }
            guard !owned.isEmpty else { return .joining }
            let (stream, continuation) = AsyncStream.makeStream(of: AcquisitionExecutionResult.self,
                bufferingPolicy: .bufferingOldest(owned.count))
            let runway = self.runway, coordinator = self.coordinator, trace = self.trace
            let scope = intent.scope
            let completion = Task {
                defer { continuation.finish() }
                return try await coordinator.executeConcurrently(owned, operation: intent.operation,
                    trace: trace) { result in
                    // The durable outcome is stated to the reader of the stream **before** the editorial
                    // notification, and the notification is the existing local-supply one.
                    continuation.yield(result)
                    guard result.selectableSupplyChanged else { return }
                    do { try await runway.noteLocalSupplyChanged(scope: scope) }
                    catch RunwayControllerError.noActiveScope {}
                    catch RunwayControllerError.scopeMismatch {}
                    // P02: the caller observes this same durable fact per result, before the rest of the round
                    // settles; a slow later target cannot hold an already-published supply change.
                    await onDurableResult?(result)
                }
            }
            return .round(RunwayAcquisitionRound(results: stream, completion: completion,
                targetIDs: owned.compactMap { work in
                    if case .start(let target, _) = work { return target.id }
                    return nil
                }))
        }
    }

    /// Coverage uses the existing planner/coordinator without claiming local exhaustion or
    /// reserving a depth-shortage intent in Runtime. The driver owns this finite opportunity.
    public func runCoverage(_ demand: AcquisitionDemand, scope: RunwayScope,
        eligibleTargets: [AcquisitionTarget], resources: AcquisitionPlanningResources) async throws -> RunwayAcquisitionCycleOutcome {
        guard demand.pressure == .selectedSourceCoverage,
            demand.contextKey == scope.contextKey, demand.editorialRevisionID == scope.editorialRevisionID,
            await runway.snapshot().scope == scope else { throw RunwayAcquisitionCycleError.staleIntent }
        let planning = try await coordinator.selectionOpportunity { position, active, cooling, settled in
            try AcquisitionPlanner.plan(demand: demand,
                eligibleTargets: eligibleTargets.filter {
                    settled[$0.id] != $0.generation && !cooling.contains($0.id)
                }, activeExecutions: active, resources: resources, selectionAfter: position)
        }
        switch planning {
        case .disposition(let reason): return .acceptedUnavailable(reason)
        case .planned(let plan):
            guard await runway.snapshot().scope == scope else { throw RunwayAcquisitionCycleError.staleIntent }
            try Task.checkCancellation()
            // P1: coverage owns only the work it can start. An execution another owner already has in flight is
            // not this opportunity's work: joining it would make the caller wait for a slow target (and, in the
            // driver, hold the publication loop) even when the ready supply is already published. The active
            // execution keeps its own late notification; a later opportunity covers it once it settles.
            let work = plan.work.filter {
                if case .joinActive = $0 { return false }
                return true
            }
            guard !work.isEmpty else { return .executed([]) }
            let results = try await coordinator.executeConcurrently(work) { result in
                guard result.selectableSupplyChanged else { return }
                do { try await runway.noteLocalSupplyChanged(scope: scope) }
                catch RunwayControllerError.noActiveScope {}
                catch RunwayControllerError.scopeMismatch {}
            }
            return .executed(results)
        }
    }

    /// Starts one coverage round and returns its streamed round without waiting for a slow target. The caller owns
    /// the round (exactly one at a time), so the next planner pass cannot duplicate its starts. Durable results are
    /// yielded and notified as they settle; completion is observed by the caller.
    public func startCoverage(_ demand: AcquisitionDemand, scope: RunwayScope,
        eligibleTargets: [AcquisitionTarget], resources: AcquisitionPlanningResources,
        onDurableResult: (@Sendable (AcquisitionExecutionResult) async -> Void)? = nil) async throws
        -> RunwayAcquisitionStart {
        guard demand.pressure == .selectedSourceCoverage,
            demand.contextKey == scope.contextKey, demand.editorialRevisionID == scope.editorialRevisionID,
            await runway.snapshot().scope == scope else { throw RunwayAcquisitionCycleError.staleIntent }
        let planning = try await coordinator.selectionOpportunity { position, active, cooling, settled in
            try AcquisitionPlanner.plan(demand: demand,
                eligibleTargets: eligibleTargets.filter {
                    settled[$0.id] != $0.generation && !cooling.contains($0.id)
                }, activeExecutions: active, resources: resources, selectionAfter: position,
                includeActiveJoins: false)
        }
        switch planning {
        case .disposition(let reason): return .acceptedUnavailable(reason)
        case .planned(let plan):
            guard await runway.snapshot().scope == scope else { throw RunwayAcquisitionCycleError.staleIntent }
            let owned = plan.work.filter { work in
                if case .start = work { return true }
                return false
            }
            guard !owned.isEmpty else { return .joining }
            let (stream, continuation) = AsyncStream.makeStream(of: AcquisitionExecutionResult.self,
                bufferingPolicy: .bufferingOldest(owned.count))
            let runway = self.runway, coordinator = self.coordinator, trace = self.trace
            let completion = Task {
                defer { continuation.finish() }
                return try await coordinator.executeConcurrently(owned, trace: trace) { result in
                    continuation.yield(result)
                    guard result.selectableSupplyChanged else { return }
                    do { try await runway.noteLocalSupplyChanged(scope: scope) }
                    catch RunwayControllerError.noActiveScope {}
                    catch RunwayControllerError.scopeMismatch {}
                    await onDurableResult?(result)
                }
            }
            return .round(RunwayAcquisitionRound(results: stream, completion: completion,
                targetIDs: owned.compactMap { work in
                    if case .start(let target, _) = work { return target.id }
                    return nil
                }))
        }
    }

}
