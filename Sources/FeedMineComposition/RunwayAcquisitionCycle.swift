// Owns: one bounded Runtime intent-to-Acquisition handoff and committed supply notifications.
// Does not own: eligibility discovery, local production, publication or scheduling.
import FeedMineAcquisition
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

public struct RunwayAcquisitionCycle: Sendable {
    private let runway: RunwayController
    private let coordinator: AcquisitionCoordinator

    public init(runway: RunwayController, coordinator: AcquisitionCoordinator) {
        self.runway = runway
        self.coordinator = coordinator
    }

    public func run(_ intent: RunwayAcquisitionIntent, eligibleTargets: [AcquisitionTarget],
        resources: AcquisitionPlanningResources, preferUnattempted: Bool = false) async throws -> RunwayAcquisitionCycleOutcome {
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
        case .disposition(.resourceDenied): return .deferred(.resourceDenied)
        case .disposition(.activeGenerationConflict): return .deferred(.activeGenerationConflict)
        case .planned(let plan):
            // Ownership of the finite plan must be accepted before any external work begins.
            try await runway.acknowledgeAcquisition(intent)
            try Task.checkCancellation()
            let runway = self.runway, scope = intent.scope
            // Targets run concurrently (bounded by the plan) so one slow feed never delays the rest.
            let results = try await coordinator.executeConcurrently(plan.work) { result in
                guard result.selectableSupplyChanged else { return }
                do { try await runway.noteLocalSupplyChanged(scope: scope) }
                catch RunwayControllerError.noActiveScope {}
                catch RunwayControllerError.scopeMismatch {}
            }
            return .executed(results)
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
            let results = try await coordinator.executeConcurrently(plan.work) { result in
                guard result.selectableSupplyChanged else { return }
                do { try await runway.noteLocalSupplyChanged(scope: scope) }
                catch RunwayControllerError.noActiveScope {}
                catch RunwayControllerError.scopeMismatch {}
            }
            return .executed(results)
        }
    }

}
