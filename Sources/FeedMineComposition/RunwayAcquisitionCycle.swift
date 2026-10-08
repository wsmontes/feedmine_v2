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
        let planning = try await coordinator.selectionOpportunity { position, active in
            try AcquisitionPlanner.plan(demand: intent.demand, eligibleTargets: eligibleTargets,
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
            var results: [AcquisitionExecutionResult] = []
            for work in plan.work {
                try Task.checkCancellation()
                let result = try await coordinator.execute(work)
                results.append(result)
                if result.selectableSupplyChanged {
                    do { try await runway.noteLocalSupplyChanged(scope: intent.scope) }
                    catch RunwayControllerError.noActiveScope {}
                    catch RunwayControllerError.scopeMismatch {}
                }
                if result.stop == .cancelled { break }
            }
            return .executed(results)
        }
    }
}
