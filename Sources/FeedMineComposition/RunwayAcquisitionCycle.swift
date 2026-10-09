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
        resources: AcquisitionPlanningResources) async throws -> RunwayAcquisitionCycleOutcome {
        let snapshot = await runway.snapshot()
        guard snapshot.outstandingAcquisition == intent else { throw RunwayAcquisitionCycleError.staleIntent }
        let planning = try await coordinator.selectionOpportunity { position, active, cooling in
            try AcquisitionPlanner.plan(demand: intent.demand,
                eligibleTargets: eligibleTargets.filter { !cooling.contains($0.id) },
                activeExecutions: active, resources: resources, selectionAfter: position)
        }
        switch planning {
        case .disposition(.noEligibleTargets):
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
}
