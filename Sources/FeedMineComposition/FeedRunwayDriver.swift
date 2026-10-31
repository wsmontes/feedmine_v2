// Executes controller-owned causal effects for an explicitly driven local session.
// Reports the publication facts a slice concludes (the receipt `PublicationOutcome.published` carries) to the host
// that owns the admitted list: the drain is where a publication becomes visible to this process, so the fact is
// stated there instead of being guessed later from the clock.
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
    public let discoveryExaminedCapacity: Int
    public init(runway: RunwayResourceFacts, acquisition: AcquisitionPlanningResources, discoveryExaminedCapacity: Int = 120) {
        self.runway = runway; self.acquisition = acquisition
        self.discoveryExaminedCapacity = max(1, discoveryExaminedCapacity)
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
        var mediaOpportunity: MediaPreparationOpportunity?
        /// Caller opportunities that arrived while this execution already owned the examination. Each one is an
        /// external fact and each one owns exactly one catalogue page; nothing inside the execution adds to it.
        var callerPagesPending = 0
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
    private let coordinator: AcquisitionCoordinator
    private let monotonicNow: @Sendable () -> RunwayMonotonicTime
    private let makeSegmentIdentity: @Sendable () throws -> FeedRunwaySegmentIdentity
    private let prepare: @Sendable (SelectionResult) throws -> LocalPreparedPublication
    /// Receives the next editorial candidates (priority order) so media is prepared for exactly
    /// what the coming slice can publish (review F05).
    private let makeMediaOpportunity: (@Sendable () async -> MediaPreparationOpportunity)?
    private let prepareMedia: (@Sendable ([OriginRevisionID]) async -> Void)?
    private let onDiscoveryPage: (@Sendable ([LegacyCatalogEntry]) async -> Void)?
    private let selectedSourceCoverage: AcquisitionDemand?
    private let candidateProvider: CandidateProvider
    /// Optional evidence of the replenishment attempts this driver executes; nil records nothing.
    private let trace: ReplenishmentTrace?
    /// The publication fact of this drain, delivered the moment it is concluded: the receipt
    /// `PublicationOutcome.published` carries, once `completeLocalSlice` accepted it. Reporting is not installing —
    /// nothing here changes the admitted list; the host that owns what the reader sees decides what follows. Nil
    /// when the host asks for no report.
    private let onPublication: (@Sendable (PublicationReceipt) async -> Void)?
    /// What the causal drain last settled: the acquisition it executed, or nil when it executed none.
    /// It is read once — where the reader's whole situation is drawn — and carries no lifetime of its own:
    /// the next drain clears it, and any newer observation or supply change moves the runway past it.
    private var settledAcquisition: RunwayAcquisitionCycleOutcome?

    public init(session: FeedSession, runway: RunwayController, plan: FeedPlan, policy: ResolvedSelectionPolicy,
        acquisition: SyndicationAcquisitionSnapshot, coordinator: AcquisitionCoordinator,
        monotonicNow: @escaping @Sendable () -> RunwayMonotonicTime,
        makeSegmentIdentity: @escaping @Sendable () throws -> FeedRunwaySegmentIdentity,
        prepare: @escaping @Sendable (SelectionResult) throws -> LocalPreparedPublication,
        prepareMedia: (@Sendable ([OriginRevisionID]) async -> Void)? = nil,
        selectedSourceCoverage: AcquisitionDemand? = nil,
        // F06-A (Codex's review): the slice must judge readiness with the **same** index the preparation closure
        // uses. Two different views of what is ready is how a suspended candidate becomes a text-only card.
        readiness: MediaReadiness? = nil,
        onDiscoveryPage: (@Sendable ([LegacyCatalogEntry]) async -> Void)? = nil,
        makeMediaOpportunity: (@Sendable () async -> MediaPreparationOpportunity)? = nil,
        trace: ReplenishmentTrace? = nil,
        onPublication: (@Sendable (PublicationReceipt) async -> Void)? = nil) throws {
        guard policy.contextKey == plan.context.key else { throw FeedRunwayDriverError.policyContextMismatch }
        if let demand = selectedSourceCoverage {
            guard demand.contextKey == plan.context.key, demand.editorialRevisionID == plan.revision.id,
                demand.pressure == .selectedSourceCoverage else { throw FeedRunwayDriverError.policyContextMismatch }
        }
        self.makeMediaOpportunity = makeMediaOpportunity
        self.onDiscoveryPage = onDiscoveryPage
        self.selectedSourceCoverage = selectedSourceCoverage
        self.prepareMedia = prepareMedia
        candidateProvider = CandidateProvider(contentStore: ContentStore(database: acquisition.runtimeDatabase))
        self.session = session; self.runway = runway; self.plan = plan; self.policy = policy; self.acquisition = acquisition
        publicationHistory = PublicationHistory(database: acquisition.runtimeDatabase)
        localProductionSlice = LocalProductionSlice(database: acquisition.runtimeDatabase, readiness: readiness,
            trace: trace)
        acquisitionCycle = RunwayAcquisitionCycle(runway: runway, coordinator: coordinator, trace: trace)
        self.coordinator = coordinator
        self.trace = trace
        self.onPublication = onPublication
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
        let bounds = FeedPresentationBounds(backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
            contextKey: plan.context.key)
        guard try await session.admitPresentation(.restore(bounds)) != nil else {
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

    /// Records one real observation and lets the runway produce. The admitted list changes only through
    /// `FeedPresentationAdmission.forwardScroll` when the movement was forward, and only through
    /// `FeedPresentationAdmission.backwardScroll` when it was backward and reached the admitted head.
    public func submitViewport(_ observation: ViewportObservation, activity: RunwayActivity,
        resources: FeedRunwayDriverResources,
        onCommitted: (@Sendable (FeedPresentationSnapshot) async -> Void)? = nil) async throws -> FeedPresentationSnapshot? {
        guard let recorded = try await session.submitViewport(observation) else {
            await runway.deactivate(); return nil
        }
        return try await finishViewport(observation, recorded: recorded, activity: activity,
            resources: resources, onCommitted: onCommitted)
    }

    public func submitViewport(_ evidence: RenderedViewportEvidence, activity: RunwayActivity,
        resources: FeedRunwayDriverResources,
        onCommitted: (@Sendable (FeedPresentationSnapshot) async -> Void)? = nil) async throws -> FeedPresentationSnapshot? {
        guard let recorded = try await session.submitViewport(evidence.observation, from: evidence) else {
            return await session.currentPresentation()
        }
        if evidence.isPositionReconciliation {
            // A local visual acknowledgement is not another runway/acquisition opportunity.
            if let onCommitted { await onCommitted(recorded) }
            return recorded
        }
        return try await finishViewport(evidence.observation, recorded: recorded, activity: activity,
            resources: resources, onCommitted: onCommitted)
    }

    private func finishViewport(_ observation: ViewportObservation, recorded: FeedPresentationSnapshot,
        activity: RunwayActivity, resources: FeedRunwayDriverResources,
        onCommitted: (@Sendable (FeedPresentationSnapshot) async -> Void)?) async throws -> FeedPresentationSnapshot? {
        // An unknown anchor is inert: the session kept its current anchor and no observation is claimed.
        guard recorded.window.anchor == observation.anchor else { return recorded }
        _ = try await validateCurrentScope()
        try await runway.submitObservation(.init(editionID: recorded.editionID,
            anchorCardID: recorded.window.anchor.cardID, sampledAt: monotonicNow(), activity: activity))
        if activity.admitsForwardContent {
            // The gesture reveals the prefix that was already ready; cards produced by this very
            // opportunity wait for the next genuine scroll observation.
            _ = try await session.admitPresentation(.forwardScroll(observation))
        }
        if activity.admitsBackwardContent {
            // The reader reached the admitted head: the history below it is already published locally, so it is
            // admitted from the store — no acquisition, no network, and bounded by the frozen backward bound.
            _ = try await session.admitPresentation(.backwardScroll(observation))
        }
        if let onCommitted, let current = await session.currentPresentation() { await onCommitted(current) }
        return try await drive(resources: resources)
    }

    private func executeAcquisition(_ intent: RunwayAcquisitionIntent, resources: FeedRunwayDriverResources) async throws -> Bool {
        let targets = try acquisition.eligibleTargets(for: plan.context)
        let outcome = try await acquisitionCycle.run(intent, eligibleTargets: targets, resources: resources.acquisition, preferUnattempted: selectedSourceCoverage != nil)
        settledAcquisition = outcome
        return outcome.selectableSupplyChanged
    }

    public func drive(resources: FeedRunwayDriverResources) async throws -> FeedPresentationSnapshot? {
        if causalExecution != nil {
            causalExecution?.resources = resources
            causalExecution?.reconsiderRequested = true
            // A caller that coalesces into an execution already in flight is still a caller (PD8-R1): its own
            // opportunity waits for the examination that execution holds, and it owns its own page below.
            causalExecution?.callerPagesPending += 1
            return await session.currentPresentation()
        }
        // Claim before the first suspension, including scope validation. The claiming call is itself a caller
        // opportunity, so it is the first page this execution owes.
        causalExecution = CausalExecution(resources: resources, callerPagesPending: 1)
        settledAcquisition = nil
        defer { causalExecution = nil }
        guard let scope = try await validateCurrentScope(), await runway.snapshot().scope == scope else {
            return await session.currentPresentation()
        }
        if causalExecution!.resources.runway.localWorkAllowed {
            causalExecution?.mediaOpportunity = await makeMediaOpportunity?()
        }
        // Reading the budget may suspend; revocation fences catalogue work as well as publication.
        guard await session.currentRunwayScope() == scope, await runway.snapshot().scope == scope else {
            return await session.currentPresentation()
        }
        var resumeOutstanding = true
        while true {
            // One catalogue page per caller opportunity, outside the causal drain. Coverage may settle a page
            // through the existing planner, and the drain may conclude plenty about the catalogue, but neither
            // can authorise a page here: only a caller opportunity adds to `callerPagesPending`. A caller that
            // coalesced while a pass was in flight owns exactly one page, served before that pass's own
            // conclusions are reconsidered.
            while causalExecution!.callerPagesPending > 0 {
                // Revocation fences catalogue work as well as publication.
                guard await session.currentRunwayScope() == scope, await runway.snapshot().scope == scope else {
                    return await session.currentPresentation()
                }
                causalExecution!.callerPagesPending -= 1
                try await serveCallerCataloguePage()
                guard await session.currentRunwayScope() == scope, await runway.snapshot().scope == scope else {
                    return await session.currentPresentation()
                }
            }
            causalExecution?.reconsiderRequested = false
            let presentation = try await driveCausalEffects(resumeOutstanding: resumeOutstanding)
            resumeOutstanding = false
            // No await between this decision and releasing ownership. A caller arriving
            // during the last presentation read therefore cannot lose its opportunity.
            if causalExecution!.reconsiderRequested || causalExecution!.callerPagesPending > 0 { continue }
            return presentation
        }
    }

    /// Serves the single catalogue page one caller opportunity owns, with the resource facts that caller
    /// registered. A page the catalogue does not have is an answer to that opportunity, not a new one.
    private func serveCallerCataloguePage() async throws {
        let discoveryResources = causalExecution!.resources
        guard discoveryResources.runway.localWorkAllowed else { return }
        if let page = try acquisition.advanceDiscovery(for: plan.context,
            examinedCapacity: discoveryResources.discoveryExaminedCapacity) {
            await onDiscoveryPage?(page.entries)
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
                if let demand = selectedSourceCoverage {
                    let targets = try acquisition.eligibleTargets(for: plan.context)
                    do {
                        let outcome = try await acquisitionCycle.runCoverage(demand, scope: scope,
                            eligibleTargets: targets, resources: currentResources.acquisition)
                        if case .executed(let results) = outcome,
                            !results.isEmpty, !results.contains(where: { $0.stop == .cancelled }) { continue }
                    } catch RunwayAcquisitionCycleError.staleIntent { continue }
                }
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
                    if let prepareMedia = causalExecution!.mediaOpportunity.map({ opportunity in
                        { @Sendable (revisions: [OriginRevisionID]) async in await opportunity.prepare(revisions) }
                    }) ?? prepareMedia {
                        await prepareMedia(try await nextEditorialRevisions(after: intent.after,
                            capacity: intent.examinedCapacity, editionID: intent.scope.editionID,
                            operation: intent.operation))
                    }
                    guard await session.currentRunwayScope() == scope, await runway.snapshot().scope == scope else {
                        try? await runway.failLocalSlice(intent, failure: .cancelled, at: monotonicNow())
                        return await session.currentPresentation()
                    }
                    let identity = try makeSegmentIdentity()
                    let request = LocalProductionSlice.Request(plan: plan, policy: try acquisition.policyIncludingDiscovery(policy), editionID: intent.scope.editionID,
                        after: intent.after, examinedCapacity: intent.examinedCapacity, segmentID: identity.segmentID,
                        segmentSeed: identity.segmentSeed, segmentCreatedAt: identity.segmentCreatedAt,
                        operation: intent.operation)
                    let outcome = try localProductionSlice.run(request, prepare: prepare)
                    try await runway.completeLocalSlice(intent, outcome: outcome, at: monotonicNow())
                    // Publication extends the reserve only. Installing a different admitted list here
                    // was the defect this task removes (analysis §2): no gesture, new cards on screen.
                    // R6-E: what the publication *is*, stated where it concludes — the receipt the line above just
                    // accepted, with scope and time already checked by it. Reporting it is not installing it: the
                    // host owns the admitted list, and the window that follows is its own `publishedGrowth`
                    // admission, which preserves the anchor and appends only already-published cards.
                    if case .published(_, let receipt) = outcome { await onPublication?(receipt) }
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
                    if selectedSourceCoverage != nil {
                        let after = await runway.snapshot()
                        // Deferred depth work must not be retried inside this drain. Coverage
                        // can still consider other targets when the depth intent has settled.
                        if after.scope == scope, after.outstandingAcquisition == nil { continue }
                    }
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
        editionID: FeedEditionID, operation: FeedReplenishmentOperationID) async throws -> [OriginRevisionID] {
        let window = try candidateProvider.candidates(for: plan, after: cursor, examinedCapacity: capacity,
            operation: operation, consult: "preparation", trace: trace)
        // The projected presentation anchor can precede physical viewport proof;
        // editorial recurrence must use only durable seen high-water.
        let facts = try publicationHistory.exposure(editionID: editionID,
            originIDs: window.candidates.map(\.originRecordID))
        let effectivePolicy = try acquisition.policyIncludingDiscovery(policy)
        let recurring = effectivePolicy.exposure == .excludePublishedMaterial
        return window.candidates.filter { candidate in
            if case .selectedSources(let sources) = effectivePolicy.eligibility,
                candidate.sourceIDs.isDisjoint(with: sources) { return false }
            guard facts.publishedOriginIDs.contains(candidate.originRecordID) else { return true }
            return recurring && !facts.unseenOriginIDs.contains(candidate.originRecordID)
        }.map(\.originRevisionID)
    }

    public func markConsumptionInactive() async { await runway.markConsumptionInactive() }
    /// PO 2026-10-14: the evidence the composition needs to state the end of the reader's eligible offer —
    /// the acquisition the last drain settled, read beside the runway's own facts. Nil when that drain
    /// executed no acquisition, so a provisional drain never even offers the question.
    public func settledEligibleOffer() async -> FeedEligibleOfferSettlement? {
        // Read only after the drain released ownership: a second opportunity must not install the end from an
        // unfinished drain, pairing an acquisition that drain may still act on with live runway facts (review,
        // 2026-10-14).
        guard causalExecution == nil, let settledAcquisition else { return nil }
        return FeedEligibleOfferSettlement(acquisition: settledAcquisition, runway: await runway.snapshot())
    }
    /// Review M7: when a failed local slice becomes retryable without a new user signal.
    public func localRetryEligibleAt() async -> RunwayMonotonicTime? { await runway.snapshot().localRetryEligibleAt }
    /// Review F08: when a deferred acquisition intent can be resumed because a cooling target recovers.
    public func acquisitionResumeAt() async -> RunwayMonotonicTime? {
        guard await runway.snapshot().outstandingAcquisition != nil,
            let expiry = await coordinator.nextCoolingExpiry() else { return nil }
        return RunwayMonotonicTime(seconds: expiry)
    }
    public func deactivate() async { await runway.deactivate() }
}
