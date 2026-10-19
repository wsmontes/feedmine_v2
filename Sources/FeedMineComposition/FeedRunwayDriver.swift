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
    let runway: RunwayController
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
    /// R06: a round whose durable supply already reached publication while the rest of the plan was still running.
    private var backgroundRound: Task<[AcquisitionExecutionResult], Error>?
    private var backgroundRoundSettled = false
    private var backgroundRoundFailure: (any Error)?
    /// The coverage round this driver owns. One at a time: while it runs, no pass starts another, so a slow
    /// target cannot be duplicated and the next opportunity is scheduled by its completion.
    private var coverageRound: Task<[AcquisitionExecutionResult], Error>?
    /// Identity of the coverage round this driver owns. A completion from a retired/replaced round cannot clear
    /// the new owner or schedule work in a scope it never belonged to.
    private var coverageRoundID: UInt64 = 0
    private var coverageRoundFailure: (any Error)?
    /// Evidence for the coverage-ownership tests: targets this driver's selected-source coverage rounds owned.
    private(set) var coverageStartedTargetIDs: [AcquisitionTargetID] = []
    /// P02: the last resource facts an explicit caller registered. A durable fact that arrives after the drain
    /// returned re-enters the **same** causal executor with these facts; it never invents a second loop or a
    /// new authorization. Nil after retirement/close.
    private var latestResources: FeedRunwayDriverResources?
    /// True between `suspendForBackground()` and the next foreground activation. An executor already in flight
    /// checks it before starting another action, so background revokes the door to new work even with captured
    /// resources.
    private var backgroundSuspended = false
    /// The one late-fact publisher. At most one task exists; facts that arrive while it runs set
    /// `lateFactsPending`, so a burst coalesces into the next pass of the same executor.
    private var lateOpportunity: Task<Void, Never>?
    private var lateFactsPending = false

    public init(session: FeedSession, runway: RunwayController, plan: FeedPlan, policy: ResolvedSelectionPolicy,
        acquisition: SyndicationAcquisitionSnapshot, coordinator: AcquisitionCoordinator,
        monotonicNow: @escaping @Sendable () -> RunwayMonotonicTime,
        makeSegmentIdentity: @escaping @Sendable () throws -> FeedRunwaySegmentIdentity,
        prepare: @escaping @Sendable (SelectionResult) throws -> LocalPreparedPublication,
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

    /// B (spec "Estabilidade de coleta e UI"): a media readiness transition is a **local-supply fact**. This is
    /// the same notification a committed acquisition receipt gives the runway (`noteLocalSupplyChanged`), so the
    /// next drive opportunity is the existing one — no second pipeline and no publication from the callback.
    public func noteMediaReadinessChanged() async {
        guard let scope = try? await validateCurrentScope() else { return }
        do { try await runway.noteLocalSupplyChanged(scope: scope) }
        catch RunwayControllerError.noActiveScope { return }
        catch RunwayControllerError.scopeMismatch { return }
        catch { return }
        // P02: the fact is durable now; a reader with no gesture must still receive what it unlocked.
        scheduleLateOpportunity()
    }

    /// P02: a per-result supply notification from a still-running acquisition round. The round notifies the runway
    /// for every durable result; this re-enters the executor immediately instead of waiting for the whole round —
    /// and does not claim a caller page.
    public func noteLateDurableFact() async { scheduleLateOpportunity() }

    /// Coalesces a late durable fact into the existing causal executor. When an execution is already in flight the
    /// fact requests its reconsideration; otherwise exactly one publisher task re-enters `drive` with the resource
    /// facts the last caller registered. Retirement clears the facts and cancels this task, so a late notification
    /// can only state canonical supply — it never reauthorizes a retired context.
    private func scheduleLateOpportunity() {
        guard latestResources != nil else { return }
        if causalExecution != nil {
            causalExecution?.reconsiderRequested = true
            return
        }
        lateFactsPending = true
        guard lateOpportunity == nil else { return }
        lateOpportunity = Task { await self.drainLateOpportunities() }
    }

    private func drainLateOpportunities() async {
        while lateFactsPending {
            lateFactsPending = false
            guard let resources = latestResources else { break }
            guard await runway.snapshot().scope != nil else { break }
            _ = try? await drive(resources: resources, isCallerOpportunity: false)
        }
        lateOpportunity = nil
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
        // P01: a new activation of this association reopens the start gate its retirement closed.
        backgroundSuspended = false
        await coordinator.setNewStartsAllowed(true)
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
    /// `sampledAt` is the instant the reader produced the observation, when the caller captured it **before**
    /// any suspension (the host's single ingress, `FeedAssociation`). The runway measures consumption as cards
    /// advanced over elapsed time between samples, so a coalesced opportunity delivered late must still carry the
    /// moment it happened: stamping it on delivery would turn the drain's own latency into reader velocity. Nil
    /// mints the instant here — the pre-existing behavior for callers with no earlier fact.
    public func submitViewport(_ observation: ViewportObservation, activity: RunwayActivity,
        resources: FeedRunwayDriverResources, sampledAt: RunwayMonotonicTime? = nil,
        onCommitted: (@Sendable (FeedPresentationSnapshot) async -> Void)? = nil) async throws -> FeedPresentationSnapshot? {
        guard let recorded = try await session.submitViewport(observation) else {
            await runway.deactivate(); return nil
        }
        return try await finishViewport(observation, recorded: recorded, activity: activity,
            resources: resources, sampledAt: sampledAt, onCommitted: onCommitted)
    }

    public func submitViewport(_ evidence: RenderedViewportEvidence, activity: RunwayActivity,
        resources: FeedRunwayDriverResources, sampledAt: RunwayMonotonicTime? = nil,
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
            resources: resources, sampledAt: sampledAt, onCommitted: onCommitted)
    }

    private func finishViewport(_ observation: ViewportObservation, recorded: FeedPresentationSnapshot,
        activity: RunwayActivity, resources: FeedRunwayDriverResources,
        sampledAt: RunwayMonotonicTime? = nil,
        onCommitted: (@Sendable (FeedPresentationSnapshot) async -> Void)?) async throws -> FeedPresentationSnapshot? {
        // An unknown anchor is inert: the session kept its current anchor and no observation is claimed.
        guard recorded.window.anchor == observation.anchor else { return recorded }
        _ = try await validateCurrentScope()
        try await runway.submitObservation(.init(editionID: recorded.editionID,
            anchorCardID: recorded.window.anchor.cardID, sampledAt: sampledAt ?? monotonicNow(), activity: activity))
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
        let start = try await acquisitionCycle.start(intent, eligibleTargets: targets,
            resources: resources.acquisition, preferUnattempted: selectedSourceCoverage != nil,
            onDurableResult: { [weak self] _ in await self?.noteLateDurableFact() })
        switch start {
        case .acceptedUnavailable(let disposition):
            settledAcquisition = .acceptedUnavailable(disposition)
            return false
        case .deferred(let disposition):
            settledAcquisition = .deferred(disposition)
            return false
        case .joining:
            // Nothing new was authorized: the execution already running owns its result and its own late
            // notification. This drain states no execution of its own.
            return false
        case .round(let round):
            // R06: each durable result is a fact the moment it is admitted. The first supply change returns to the
            // publication loop **without waiting for the rest of the round**, so a fast source publishes while a
            // slow one is still pending. The round keeps running: its remaining results still notify the runway,
            // and its completion (including a fatal error) is observed by the next opportunity.
            for await result in round.results {
                guard result.selectableSupplyChanged else { continue }
                settledAcquisition = nil
                observeBackgroundRound(round.completion)
                return true
            }
            let results = try await round.completion.value
            settledAcquisition = .executed(results)
            return results.contains { $0.selectableSupplyChanged }
        }
    }

    /// The completion of a round the publication loop left running. It is observed so a fatal error is not lost;
    /// the next `drive` rethrows it once. Nothing in this monitor publishes.
    private func observeCoverageRound(_ round: RunwayAcquisitionRound) {
        coverageStartedTargetIDs.append(contentsOf: round.targetIDs)
        coverageRoundID &+= 1
        let identity = coverageRoundID
        coverageRound = round.completion
        coverageRoundFailure = nil
        Task { [weak self] in
            // The stream is bounded; draining it keeps the pump free. The durable facts are already delivered by
            // the round's callback, so this observer only owns completion.
            for await _ in round.results {}
            do {
                _ = try await round.completion
                await self?.coverageSettled(identity, error: nil)
            } catch {
                await self?.coverageSettled(identity, error: error)
            }
        }
    }

    private func coverageSettled(_ identity: UInt64, error: (any Error)?) {
        guard identity == coverageRoundID else { return }
        coverageRound = nil
        if let error {
            coverageRoundFailure = error
            return
        }
        scheduleLateOpportunity()
    }

    private func collectSettledCoverageRound() throws {
        guard let failure = coverageRoundFailure else { return }
        coverageRoundFailure = nil
        throw failure
    }

    private func observeBackgroundRound(_ completion: Task<[AcquisitionExecutionResult], Error>) {
        backgroundRound = completion
        backgroundRoundSettled = false
        backgroundRoundFailure = nil
        Task { [weak self] in
            do {
                let results = try await completion.value
                await self?.noteBackgroundRoundSettled(nil,
                    changed: results.contains { $0.selectableSupplyChanged })
            } catch {
                await self?.noteBackgroundRoundSettled(error, changed: false)
            }
        }
    }

    private func noteBackgroundRoundSettled(_ error: (any Error)?, changed: Bool) {
        // A round that settled after retirement is not this driver's opportunity any more: the work keeps its own
        // durability, and its failure must not surface on a later scope.
        guard backgroundRound != nil else { return }
        backgroundRoundSettled = true
        backgroundRoundFailure = error
        if error == nil, changed { scheduleLateOpportunity() }
    }

    private func collectSettledBackgroundRound() throws {
        guard backgroundRoundSettled else { return }
        backgroundRoundSettled = false
        backgroundRound = nil
        if let failure = backgroundRoundFailure {
            backgroundRoundFailure = nil
            throw failure
        }
    }

    public func drive(resources: FeedRunwayDriverResources) async throws -> FeedPresentationSnapshot? {
        try await drive(resources: resources, isCallerOpportunity: true)
    }

    /// P02: a durable fact re-enters the same executor without claiming a caller opportunity (and therefore
    /// without consuming a catalogue page). Only an explicit caller adds to `callerPagesPending`.
    private func drive(resources: FeedRunwayDriverResources, isCallerOpportunity: Bool) async throws
        -> FeedPresentationSnapshot? {
        latestResources = resources
        if causalExecution != nil {
            causalExecution?.resources = resources
            causalExecution?.reconsiderRequested = true
            // A caller that coalesces into an execution already in flight is still a caller (PD8-R1): its own
            // opportunity waits for the examination that execution holds, and it owns its own page below.
            if isCallerOpportunity { causalExecution?.callerPagesPending += 1 }
            return await session.currentPresentation()
        }
        // Claim before the first suspension, including scope validation. A caller owns one page; a late fact does
        // not.
        guard !backgroundSuspended else { return await session.currentPresentation() }
        causalExecution = CausalExecution(resources: resources,
            callerPagesPending: isCallerOpportunity ? 1 : 0)
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
        // Only an explicit caller may resume a deferred acquisition intent; a late durable fact re-enters the
        // executor to publish what already settled, not to spend targets.
        var resumeOutstanding = isCallerOpportunity
        while true {
            // Codex P1.2: background revokes the door even for the executor already in flight. The action it was
            // already awaiting may conclude, but it starts no new work with the captured resources.
            if backgroundSuspended { return await session.currentPresentation() }
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
            // Codex P1.2: this loop is the in-flight executor. Background revokes the door before every action,
            // not only when the method returns; the operation already awaited may finish, but no new coverage,
            // slice or measurement starts with the resources captured before the transition.
            if backgroundSuspended { return await session.currentPresentation() }
            try collectSettledCoverageRound()
            try collectSettledBackgroundRound()
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
                if let demand = selectedSourceCoverage, coverageRound == nil {
                    let targets = try acquisition.eligibleTargets(for: plan.context)
                    do {
                        let started = try await acquisitionCycle.startCoverage(demand, scope: scope,
                            eligibleTargets: targets, resources: currentResources.acquisition,
                            onDurableResult: { [weak self] _ in await self?.noteLateDurableFact() })
                        if case .round(let round) = started { observeCoverageRound(round) }
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
                    // R07: state the coming slice's media priority without making preparation a condition of the
                    // slice. The slice selects only ready supply through the same readiness index; a candidate
                    // whose media is still pending is simply not in this publication (INV-17), and the readiness
                    // transition wakes the existing reconsideration. The opportunity is the only channel — the
                    // product always provides it, and an execution without one has nothing to request.
                    let revisions = try await nextEditorialRevisions(after: intent.after,
                        capacity: intent.examinedCapacity, editionID: intent.scope.editionID,
                        operation: intent.operation)
                    causalExecution?.mediaOpportunity?.request(revisions)
                    guard await session.currentRunwayScope() == scope, await runway.snapshot().scope == scope else {
                        try? await runway.failLocalSlice(intent, failure: .cancelled, at: monotonicNow())
                        return await session.currentPresentation()
                    }
                    let identity = try makeSegmentIdentity()
                    let request = LocalProductionSlice.Request(plan: plan, policy: try acquisition.policyIncludingDiscovery(policy), editionID: intent.scope.editionID,
                        after: intent.after, examinedCapacity: intent.examinedCapacity, segmentID: identity.segmentID,
                        segmentSeed: identity.segmentSeed, segmentCreatedAt: identity.segmentCreatedAt,
                        readerAnchorCardID: await session.currentPresentation()?.window.anchor.cardID,
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
        let anchor = await session.currentPresentation()?.window.anchor.cardID
        let facts = try publicationHistory.exposure(editionID: editionID,
            originIDs: window.candidates.map(\.originRecordID), readerAnchorCardID: anchor)
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
    /// The screen is gone: no late fact may use the resources a foreground caller registered to start a new
    /// opportunity. Authorized pulls keep running and still state durable supply; only the door to a new coverage
    /// pass is closed until a foreground activation registers resources again.
    public func suspendForBackground() async {
        backgroundSuspended = true
        latestResources = nil
        lateOpportunity?.cancel()
        lateOpportunity = nil
        lateFactsPending = false
    }

    public func deactivate() async {
        // R06/R14: retirement stops publication and the runway, not the network work already authorized. A pull in
        // flight still admits its durable supply (the cycle's contract); its late notification is ignored by the
        // cleared scope and its completion is not observed as this driver's opportunity anymore.
        // P01: the round itself must stop scheduling new targets — nil-ing a reference left a partially started
        // plan free to create fresh URL session tasks after the transport was invalidated. The fence is the
        // coordinator's start gate, not cancellation: an authorized pull must still state its durable supply
        // (R14), and only `close()`'s bounded settlement cancels it before the transport dies.
        backgroundRound = nil
        backgroundRoundSettled = false
        backgroundRoundFailure = nil
        coverageRound = nil
        coverageRoundID &+= 1
        coverageRoundFailure = nil
        await coordinator.setNewStartsAllowed(false)
        // P02: no late fact may re-enter a retired context.
        lateOpportunity?.cancel()
        lateOpportunity = nil
        lateFactsPending = false
        latestResources = nil
        await runway.deactivate()
    }
}
