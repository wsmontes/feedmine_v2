// Executes controller-owned causal effects for an explicitly driven local session.
import Foundation
import FeedMineDomain
import FeedMineAcquisition
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime

public struct FeedRunwaySegmentIdentity: Hashable, Sendable {
    public let segmentID: FeedSegmentID
    public let segmentSeed: UInt64
    public let segmentCreatedAt: Date
    public init?(segmentID: FeedSegmentID, segmentSeed: UInt64, segmentCreatedAt: Date) {
        guard segmentCreatedAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        self.segmentID = segmentID; self.segmentSeed = segmentSeed; self.segmentCreatedAt = segmentCreatedAt
    }
}
public struct FeedRunwayDriverResources: Hashable, Sendable {
    public let runway: RunwayResourceFacts
    public let acquisition: AcquisitionPlanningResources
    public init(runway: RunwayResourceFacts, acquisition: AcquisitionPlanningResources) {
        self.runway = runway; self.acquisition = acquisition
    }
}
public enum FeedRunwayDriverError: Error, Equatable, Sendable {
    case policyContextMismatch
    case sessionContextMismatch(expected: ContextKey, actual: ContextKey)
    case sessionEditorialRevisionMismatch(expected: EditorialRevisionID, actual: EditorialRevisionID)
}
public actor FeedRunwayDriver {
    private let session: FeedSession
    private let runway: RunwayController
    private let plan: FeedPlan
    private let policy: ResolvedSelectionPolicy
    private let acquisition: SyndicationAcquisitionSnapshot
    private let publicationHistory: PublicationHistory
    private let localProductionSlice: LocalProductionSlice
    private let acquisitionCycle: RunwayAcquisitionCycle
    private let monotonicNow: @Sendable () -> RunwayMonotonicTime
    private let makeSegmentIdentity: @Sendable () throws -> FeedRunwaySegmentIdentity
    private let prepare: @Sendable (SelectionResult) throws -> LocalPreparedPublication

    public init(session: FeedSession, runway: RunwayController, plan: FeedPlan, policy: ResolvedSelectionPolicy,
        acquisition: SyndicationAcquisitionSnapshot, monotonicNow: @escaping @Sendable () -> RunwayMonotonicTime,
        makeSegmentIdentity: @escaping @Sendable () throws -> FeedRunwaySegmentIdentity,
        prepare: @escaping @Sendable (SelectionResult) throws -> LocalPreparedPublication) throws {
        guard policy.contextKey == plan.context.key else { throw FeedRunwayDriverError.policyContextMismatch }
        self.session = session; self.runway = runway; self.plan = plan; self.policy = policy; self.acquisition = acquisition
        publicationHistory = PublicationHistory(database: acquisition.runtimeDatabase)
        localProductionSlice = LocalProductionSlice(database: acquisition.runtimeDatabase)
        acquisitionCycle = RunwayAcquisitionCycle(runway: runway, coordinator: acquisition.makeCoordinator())
        self.monotonicNow = monotonicNow; self.makeSegmentIdentity = makeSegmentIdentity; self.prepare = prepare
    }

    private func validateCurrentScope() async throws -> RunwayScope? {
        guard let scope = await session.currentRunwayScope() else { return nil }
        guard scope.contextKey == plan.context.key else {
            throw FeedRunwayDriverError.sessionContextMismatch(expected: plan.context.key, actual: scope.contextKey)
        }
        guard scope.editorialRevisionID == plan.revision.id else {
            throw FeedRunwayDriverError.sessionEditorialRevisionMismatch(expected: plan.revision.id, actual: scope.editorialRevisionID)
        }
        return scope
    }

    public func restoreAndActivate(backwardCapacity: Int, forwardCapacity: Int,
        resources: FeedRunwayDriverResources) async throws -> FeedPresentationSnapshot? {
        guard try await session.restoreLocalPresentation(backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity) != nil else {
            await runway.deactivate(); return nil
        }
        return try await activateCurrentPresentation(resources: resources)
    }

    public func activateCurrentPresentation(resources: FeedRunwayDriverResources) async throws -> FeedPresentationSnapshot? {
        guard let presentation = await session.currentPresentation(), let scope = try await validateCurrentScope() else {
            await runway.deactivate(); return nil
        }
        await runway.activate(scope)
        try await runway.submitObservation(.init(editionID: presentation.editionID,
            anchorCardID: presentation.window.anchor.cardID, sampledAt: monotonicNow(), activity: .stationary))
        return try await drive(resources: resources)
    }

    public func submitViewport(_ observation: ViewportObservation, activity: RunwayActivity,
        resources: FeedRunwayDriverResources) async throws -> FeedPresentationSnapshot? {
        guard let presentation = try await session.submitViewport(observation) else {
            await runway.deactivate(); return nil
        }
        guard presentation.window.anchor == observation.anchor else { return presentation }
        _ = try await validateCurrentScope()
        try await runway.submitObservation(.init(editionID: presentation.editionID,
            anchorCardID: presentation.window.anchor.cardID, sampledAt: monotonicNow(), activity: activity))
        return try await drive(resources: resources)
    }

    private func executeAcquisition(_ intent: RunwayAcquisitionIntent, resources: FeedRunwayDriverResources) async throws -> Bool {
        let targets = try acquisition.eligibleTargets(for: plan.context)
        let outcome = try await acquisitionCycle.run(intent, eligibleTargets: targets, resources: resources.acquisition)
        return outcome.selectableSupplyChanged
    }

    public func drive(resources: FeedRunwayDriverResources) async throws -> FeedPresentationSnapshot? {
        guard try await validateCurrentScope() != nil else { return nil }
        // An explicit new caller opportunity may execute the exact controller-owned deferred intent.
        // reconsider does not emit an outstanding intent twice; this does not create a new action.
        if let outstanding = await runway.snapshot().outstandingAcquisition {
            guard try await executeAcquisition(outstanding, resources: resources) else { return await session.currentPresentation() }
        }
        while true {
            let action = try await runway.reconsider(resources: resources.runway, at: monotonicNow())
            switch action {
            case .none: return await session.currentPresentation()
            case .measure(let request):
                let ready = try publicationHistory.readyAhead(editionID: request.scope.editionID,
                    anchorCardID: request.observation.anchorCardID, probeBound: request.readyProbeBound)
                let advance = try request.advance.map {
                    try publicationHistory.forwardAdvance(editionID: $0.editionID, fromCardID: $0.fromCardID,
                        toCardID: $0.toCardID, probeBound: $0.probeBound)
                }
                try await runway.acceptMeasurement(.init(observation: request.observation, readyAhead: ready, advanceFromHighWater: advance))
            case .runLocalSlice(let intent):
                do {
                    let identity = try makeSegmentIdentity()
                    let request = LocalProductionSlice.Request(plan: plan, policy: policy, editionID: intent.scope.editionID,
                        after: intent.after, examinedCapacity: intent.examinedCapacity, segmentID: identity.segmentID,
                        segmentSeed: identity.segmentSeed, segmentCreatedAt: identity.segmentCreatedAt)
                    let outcome = try localProductionSlice.run(request, prepare: prepare)
                    try await runway.completeLocalSlice(intent, outcome: outcome, at: monotonicNow())
                    if case .published = outcome { _ = try await session.refreshCurrentPresentation() }
                } catch {
                    try await runway.failLocalSlice(intent, failure: error is CancellationError ? .cancelled : .failed, at: monotonicNow())
                    throw error
                }
            case .requestAcquisition(let intent):
                guard try await executeAcquisition(intent, resources: resources) else { return await session.currentPresentation() }
            }
        }
    }

    public func markConsumptionInactive() async { await runway.markConsumptionInactive() }
    public func deactivate() async { await runway.deactivate() }
}
