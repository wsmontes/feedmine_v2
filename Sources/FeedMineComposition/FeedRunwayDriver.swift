// Executes controller-owned causal effects for an explicitly driven local session.
import Foundation
import FeedMineDomain
import FeedMineAcquisition
import FeedMinePersistence
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
    // Non-nil only while one caller owns causal effects. Reentrant callers may update
    // resource facts; observations and intents remain exclusively controller-owned.
    private struct CausalExecution {
        var resources: FeedRunwayDriverResources
        var reconsiderRequested = false
    }
    private var causalExecution: CausalExecution?
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
    /// Receives the next editorial candidates (priority order) so media is prepared for exactly
    /// what the coming slice can publish (review F05).
    private let prepareMedia: (@Sendable ([OriginRevisionID]) async -> Void)?
    private let candidateProvider: CandidateProvider

    public init(session: FeedSession, runway: RunwayController, plan: FeedPlan, policy: ResolvedSelectionPolicy,
        acquisition: SyndicationAcquisitionSnapshot, coordinator: AcquisitionCoordinator,
        monotonicNow: @escaping @Sendable () -> RunwayMonotonicTime,
        makeSegmentIdentity: @escaping @Sendable () throws -> FeedRunwaySegmentIdentity,
        prepare: @escaping @Sendable (SelectionResult) throws -> LocalPreparedPublication,
        prepareMedia: (@Sendable ([OriginRevisionID]) async -> Void)? = nil) throws {
        guard policy.contextKey == plan.context.key else { throw FeedRunwayDriverError.policyContextMismatch }
        self.prepareMedia = prepareMedia
        candidateProvider = CandidateProvider(contentStore: ContentStore(database: acquisition.runtimeDatabase))
        self.session = session; self.runway = runway; self.plan = plan; self.policy = policy; self.acquisition = acquisition
        publicationHistory = PublicationHistory(database: acquisition.runtimeDatabase)
        localProductionSlice = LocalProductionSlice(database: acquisition.runtimeDatabase)
        acquisitionCycle = RunwayAcquisitionCycle(runway: runway, coordinator: coordinator)
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
        if causalExecution != nil {
            causalExecution?.resources = resources
            causalExecution?.reconsiderRequested = true
            return await session.currentPresentation()
        }
        // Claim before the first suspension, including scope validation.
        causalExecution = CausalExecution(resources: resources)
        defer { causalExecution = nil }
        var resumeOutstanding = true
        while true {
            causalExecution?.reconsiderRequested = false
            let presentation = try await driveCausalEffects(resumeOutstanding: resumeOutstanding)
            resumeOutstanding = false
            // No await between this decision and releasing ownership. A caller arriving
            // during the last presentation read therefore cannot lose its opportunity.
            if causalExecution!.reconsiderRequested { continue }
            return presentation
        }
    }

    private func driveCausalEffects(resumeOutstanding: Bool) async throws -> FeedPresentationSnapshot? {
        guard let scope = try await validateCurrentScope() else { return nil }
        var resumeOutstanding = resumeOutstanding
        while true {
            try Task.checkCancellation()
            let before = await runway.snapshot()
            guard before.scope == scope, await session.currentRunwayScope() == scope else {
                return await session.currentPresentation()
            }
            causalExecution?.reconsiderRequested = false
            let currentResources = causalExecution!.resources
            let action: RunwayControllerAction
            if resumeOutstanding, let outstanding = before.outstandingAcquisition {
                // Only an explicit caller opportunity resumes a deferred intent.
                action = .requestAcquisition(outstanding)
            } else {
                action = try await runway.reconsider(resources: currentResources.runway, at: monotonicNow())
            }
            resumeOutstanding = false
            switch action {
            case .none:
                let after = await runway.snapshot()
                if after.scope == scope, after.latestObservation != before.latestObservation { continue }
                let presentation = await session.currentPresentation()
                if causalExecution!.reconsiderRequested { continue }
                return presentation
            case .measure(let request):
                let ready = try publicationHistory.readyAhead(editionID: request.scope.editionID,
                    anchorCardID: request.observation.anchorCardID, probeBound: request.readyProbeBound)
                let advance = try request.advance.map {
                    try publicationHistory.forwardAdvance(editionID: $0.editionID, fromCardID: $0.fromCardID,
                        toCardID: $0.toCardID, probeBound: $0.probeBound)
                }
                do {
                    try await runway.acceptMeasurement(.init(observation: request.observation, readyAhead: ready, advanceFromHighWater: advance))
                } catch RunwayControllerError.staleMeasurement {
                    // A legitimate newer observation owns the next measurement.
                    continue
                }
            case .runLocalSlice(let intent):
                guard intent.scope == scope, await session.currentRunwayScope() == scope,
                    await runway.snapshot().scope == scope else { return await session.currentPresentation() }
                do {
                    try Task.checkCancellation()
                    // Bounded media preparation for the supply head before it is selected (PD-5).
                    if let prepareMedia {
                        await prepareMedia(try await nextEditorialRevisions(after: intent.after,
                            capacity: intent.examinedCapacity, editionID: intent.scope.editionID))
                    }
                    guard await session.currentRunwayScope() == scope, await runway.snapshot().scope == scope else {
                        try? await runway.failLocalSlice(intent, failure: .cancelled, at: monotonicNow())
                        return await session.currentPresentation()
                    }
                    let identity = try makeSegmentIdentity()
                    let request = LocalProductionSlice.Request(plan: plan, policy: policy, editionID: intent.scope.editionID,
                        after: intent.after, examinedCapacity: intent.examinedCapacity, segmentID: identity.segmentID,
                        segmentSeed: identity.segmentSeed, segmentCreatedAt: identity.segmentCreatedAt,
                        readerAnchorCardID: await session.currentPresentation()?.window.anchor.cardID)
                    let outcome = try localProductionSlice.run(request, prepare: prepare)
                    try await runway.completeLocalSlice(intent, outcome: outcome, at: monotonicNow())
                    if case .published = outcome, await session.currentRunwayScope() == scope {
                        _ = try await session.refreshCurrentPresentation()
                    }
                } catch {
                    try await runway.failLocalSlice(intent, failure: error is CancellationError ? .cancelled : .failed, at: monotonicNow())
                    throw error
                }
            case .requestAcquisition(let intent):
                let changed: Bool
                do { changed = try await executeAcquisition(intent, resources: currentResources) }
                catch RunwayAcquisitionCycleError.staleIntent { continue }
                catch RunwayControllerError.staleAcquisitionAcknowledgement { continue }
                if !changed {
                    let after = await runway.snapshot()
                    if after.scope == scope, after.latestObservation != before.latestObservation { continue }
                    let presentation = await session.currentPresentation()
                    if causalExecution!.reconsiderRequested { continue }
                    return presentation
                }
            }
        }
    }

    /// The same window the coming slice examines, minus origins this Edition already published
    /// (unless edited articles may recur) and origins still waiting ahead of the reader.
    private func nextEditorialRevisions(after cursor: CandidateSupplyCursor?, capacity: Int,
        editionID: FeedEditionID) async throws -> [OriginRevisionID] {
        let window = try candidateProvider.candidates(for: plan, after: cursor, examinedCapacity: capacity)
        let anchor = await session.currentPresentation()?.window.anchor.cardID
        let facts = try publicationHistory.exposure(editionID: editionID,
            originIDs: window.candidates.map(\.originRecordID), readerAnchorCardID: anchor)
        let recurring = policy.exposure == .excludePublishedMaterial
        return window.candidates.filter { candidate in
            guard facts.publishedOriginIDs.contains(candidate.originRecordID) else { return true }
            return recurring && !facts.unseenOriginIDs.contains(candidate.originRecordID)
        }.map(\.originRevisionID)
    }

    public func markConsumptionInactive() async { await runway.markConsumptionInactive() }
    /// Review M7: when a failed local slice becomes retryable without a new user signal.
    public func localRetryEligibleAt() async -> RunwayMonotonicTime? { await runway.snapshot().localRetryEligibleAt }
    public func deactivate() async { await runway.deactivate() }
}
