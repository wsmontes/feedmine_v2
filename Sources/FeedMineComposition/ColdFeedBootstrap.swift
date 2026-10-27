// Owns one explicit finite bridge from canonical supply to the first presentation.
// Durable initial publication remains the concurrency authority.
import Foundation
import FeedMineDomain
import FeedMineAcquisition
import FeedMineEditorial
import FeedMineRuntime
import FeedMinePublication

public struct ColdFeedPublicationIdentity: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let publicationSchemaVersion: PublicationSchemaVersion
    public let selectionSeed: UInt64
    public let editionCreatedAt: Date
    public let segmentID: FeedSegmentID
    public let segmentSeed: UInt64
    public let segmentCreatedAt: Date
    public let anchorPlacement: AnchorPlacement
    public let checkpointedAt: Date

    public init?(editionID: FeedEditionID, publicationSchemaVersion: PublicationSchemaVersion,
        selectionSeed: UInt64, editionCreatedAt: Date, segmentID: FeedSegmentID, segmentSeed: UInt64,
        segmentCreatedAt: Date, anchorPlacement: AnchorPlacement, checkpointedAt: Date) {
        guard editionCreatedAt.timeIntervalSinceReferenceDate.isFinite,
            segmentCreatedAt.timeIntervalSinceReferenceDate.isFinite,
            checkpointedAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        self.editionID = editionID
        self.publicationSchemaVersion = publicationSchemaVersion
        self.selectionSeed = selectionSeed
        self.editionCreatedAt = editionCreatedAt
        self.segmentID = segmentID
        self.segmentSeed = segmentSeed
        self.segmentCreatedAt = segmentCreatedAt
        self.anchorPlacement = anchorPlacement
        self.checkpointedAt = checkpointedAt
    }
}

public struct ColdFeedBootstrapResources: Hashable, Sendable {
    public let localExaminedCapacity: Int
    public let acquisition: AcquisitionPlanningResources
    public let localWindowCapacity: Int

    public init?(localExaminedCapacity: Int, acquisition: AcquisitionPlanningResources, localWindowCapacity: Int = 8) {
        guard localExaminedCapacity > 0, localWindowCapacity > 0 else { return nil }
        self.localExaminedCapacity = localExaminedCapacity
        self.localWindowCapacity = localWindowCapacity
        self.acquisition = acquisition
    }
}

public enum ColdFeedBootstrapOutcome: Hashable, Sendable {
    case published(FeedPresentationSnapshot)
    case localWorkRemaining(LocalProductionProgress)
    case unavailable(LocalProductionProgress)
    case deferred(LocalProductionProgress, AcquisitionPlanningDisposition)
    case noPublicationAfterAcquisition(LocalProductionProgress, [AcquisitionExecutionResult])
}

/// The **one** media budget of a whole first publication.
///
/// It is fixed the first time there is actually something to wait for — the first window with candidates — and never
/// again: eight empty windows cannot add up to eight budgets, and media acquired *later* (the acquisition round's
/// own supply) still gets a real opportunity from that same clock instead of a budget that expired before it existed.
final class PublicationMediaBudget: @unchecked Sendable {
    private let duration: Duration
    private let lock = NSLock()
    private var boundAt: ContinuousClock.Instant?

    init(duration: Duration) { self.duration = duration }

    /// The shared instant this budget runs out at; computed once, under the lock, on first use.
    func instant() -> ContinuousClock.Instant {
        lock.lock(); defer { lock.unlock() }
        if let boundAt { return boundAt }
        let instant = ContinuousClock.now + duration
        boundAt = instant
        return instant
    }
}

/// PD-3: real first-launch evidence for an entertaining, honest preparation screen.
public enum ColdFeedEvidence: Hashable, Sendable {
    case contacting([AcquisitionTargetID])
    case settled(AcquisitionTargetID, stop: AcquisitionExecutionStop, supplyChanged: Bool)
    case preparingMedia
    /// Review F06: the first Edition is installed; slower feeds are still answering.
    case published(FeedPresentationSnapshot)
    /// The **identities** the first publication wrote, stated before the snapshot is admitted. It is the same fact
    /// a later segment's receipt carries, and it is what lets the first screen measure its buffer on the publication
    /// instead of on the admitted window.
    case publishedCards([PublicationCardID])
}

/// First-publication result shared by the per-target callbacks (serialized by the coordinator).
private final class FirstPublication: @unchecked Sendable {
    private let lock = NSLock()
    private var value: FeedPresentationSnapshot?
    var snapshot: FeedPresentationSnapshot? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

private enum PublicationAttempt {
    case published(FeedPresentationSnapshot)
    case notYet(LocalProductionProgress)
}

public enum ColdFeedBootstrapError: Error, Equatable, Sendable {
    case policyContextMismatch
    case sessionAlreadyInstalled
    case inconsistentPublishedRestore
    case closed
    case staleInitialExamination
}

/// Revocation and synchronous publication share one lock; close cannot race the commit boundary.
private final class ColdPublicationAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    // Examination progress belongs to this bootstrap, not to a reserved Edition or checkpoint.
    private var cursor: CandidateSupplyCursor?
    func cancel() { lock.lock(); active = false; lock.unlock() }
    func perform<T>(_ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard active else { throw ColdFeedBootstrapError.closed }
        try Task.checkCancellation()
        return try operation()
    }

    /// The wait below is not a publication commit, but it must still stop when the bootstrap was closed: an
    /// abandoned association may not keep decoding media for a context that is no longer on screen.
    func ensureActive() throws { _ = try perform {} }
    func currentCursor() throws -> CandidateSupplyCursor? { try perform { cursor } }
    func restartExamination() throws { try perform { cursor = nil } }
    func examine(after expectedCursor: CandidateSupplyCursor?,
        _ operation: () throws -> InitialProductionSliceOutcome) throws -> InitialProductionSliceOutcome {
        try perform {
            guard cursor == expectedCursor else { throw ColdFeedBootstrapError.staleInitialExamination }
            let outcome = try operation()
            if case .advancedWithoutPublication(let progress) = outcome {
                // A complete pass may be reconsidered on the next explicit opportunity.
                cursor = progress.exhausted ? nil : progress.nextCursor
            }
            return outcome
        }
    }
}

public struct ColdFeedBootstrap: Sendable {
    private let authority = ColdPublicationAuthority()
    public func cancel() { authority.cancel() }
    private let session: FeedSession
    private let plan: FeedPlan
    private let policy: ResolvedSelectionPolicy
    private let acquisition: SyndicationAcquisitionSnapshot
    private let initialProductionSlice: InitialProductionSlice
    private let coordinator: AcquisitionCoordinator
    private let prepare: @Sendable (SelectionResult) throws -> LocalPreparedPublication
    private let makeMediaOpportunity: (@Sendable () async -> MediaPreparationOpportunity)?
    /// The index the first publication waits on. It is the same object the slice reads, so the wait and the
    /// selection can never disagree about what is ready.
    private let readiness: MediaReadiness?
    /// How many prepared images the first publication wants before it examines, and the **one** budget for it.
    /// The budget is spent across every window this run walks: a second window does not renew it.
    private let firstPublicationMediaTarget: Int
    private let firstPublicationMediaBudget: Duration?
    private let onDiscoveryPage: (@Sendable ([LegacyCatalogEntry]) async -> Void)?
    private let evidence: (@Sendable (ColdFeedEvidence) async -> Void)?
    /// The durable ingestion fact of every per-target result whose selectable supply changed. It is stated to the
    /// owner that decides local work, for **every** result — see the call site for why publication is not the
    /// condition. Nil records nothing.
    private let onDurableSupply: (@Sendable () async -> Void)?

    /// The external composition supplies a coordinator over the snapshot's same runtime database.
    public init(session: FeedSession, plan: FeedPlan, policy: ResolvedSelectionPolicy,
        acquisition: SyndicationAcquisitionSnapshot, coordinator: AcquisitionCoordinator,
        prepare: @escaping @Sendable (SelectionResult) throws -> LocalPreparedPublication,
        evidence: (@Sendable (ColdFeedEvidence) async -> Void)? = nil,
        readiness: MediaReadiness? = nil,
        reoffer: PendingMediaReconsideration? = nil,
        trace: ReplenishmentTrace? = nil,
        onDiscoveryPage: (@Sendable ([LegacyCatalogEntry]) async -> Void)? = nil,
        makeMediaOpportunity: (@Sendable () async -> MediaPreparationOpportunity)? = nil,
        // The same cap the live walk uses: the first publication may not publish more cards than the reserve target
        // the host states. Nil keeps the uncapped first publication; a capped one leaves the rest ready.
        publicationLimit: Int? = nil,
        // The first screen's own priority: wait for this many prepared images (clamped to the candidates this
        // window actually offers) but only until the shared bound below. Nil budget keeps the previous
        // behavior — examine what is ready and never wait.
        firstPublicationMediaTarget: Int = 6,
        firstPublicationMediaBudget: Duration? = nil,
        // The ingestion receipt this run produces for the consumer that owns local work. `selectableSupplyChanged` is
        // the same durable fact this bootstrap uses to reopen its own examination; the composition states it to the
        // driver so the walk the first drive declared exhausted can be reopened by supply that arrived later.
        onDurableSupply: (@Sendable () async -> Void)? = nil) throws {
        guard policy.contextKey == plan.context.key else { throw ColdFeedBootstrapError.policyContextMismatch }
        self.makeMediaOpportunity = makeMediaOpportunity
        self.readiness = readiness
        self.firstPublicationMediaTarget = max(1, firstPublicationMediaTarget)
        self.firstPublicationMediaBudget = firstPublicationMediaBudget
        self.onDiscoveryPage = onDiscoveryPage
        self.onDurableSupply = onDurableSupply
        self.evidence = evidence
        self.session = session
        self.plan = plan
        self.policy = policy
        self.acquisition = acquisition
        self.coordinator = coordinator
        initialProductionSlice = InitialProductionSlice(database: acquisition.runtimeDatabase, readiness: readiness,
            reoffer: reoffer, trace: trace, publicationLimit: publicationLimit)
        self.prepare = prepare
    }

    public func run(identity: ColdFeedPublicationIdentity, resources: ColdFeedBootstrapResources,
        backwardCapacity: Int, forwardCapacity: Int, keepsAdmittedHead: Bool = false) async throws -> ColdFeedBootstrapOutcome {
        guard await session.currentPresentation() == nil else { throw ColdFeedBootstrapError.sessionAlreadyInstalled }
        if let page = try authority.perform({
            try acquisition.advanceDiscovery(for: plan.context, examinedCapacity: resources.localExaminedCapacity)
        }) {
            await onDiscoveryPage?(page.entries)
        }
        let mediaOpportunity = await makeMediaOpportunity?()
        // One budget for the whole first publication, fixed at the first window that has something to wait for.
        let mediaBudget = firstPublicationMediaBudget.map { PublicationMediaBudget(duration: $0) }
        let firstProgress: LocalProductionProgress
        switch try await attemptFirstPublication(identity: identity, resources: resources,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
            keepsAdmittedHead: keepsAdmittedHead, mediaOpportunity: mediaOpportunity,
            mediaBudget: mediaBudget) {
        case .published(let snapshot): return .published(snapshot)
        case .notYet(let progress):
            guard progress.exhausted else { return .localWorkRemaining(progress) }
            firstProgress = progress
        }

        // Both constructors succeed: structural exhaustion is proven and no published runway exists.
        let bootstrapPlan = BootstrapPlan(contextKey: plan.context.key, editorialRevisionID: plan.revision.id,
            exhaustedLocalSupply: ExhaustedLocalSupply(readyCards: 0)!, acquisitionResources: resources.acquisition)!
        let eligibleTargets = try acquisition.eligibleTargets(for: plan.context)
        let acquisitionPlan: AcquisitionPlan
        let planning = try await coordinator.selectionOpportunity { position, active, cooling in
            try AcquisitionPlanner.plan(demand: bootstrapPlan.demand,
                eligibleTargets: eligibleTargets.filter { !cooling.contains($0.id) },
                activeExecutions: active, resources: bootstrapPlan.acquisitionResources, selectionAfter: position)
        }
        switch planning {
        case .disposition(.noEligibleTargets):
            if eligibleTargets.isEmpty, let discovery = acquisition.discovery,
                discovery.contextKey == plan.context.key, !discovery.exhausted {
                // Canonical supply is exhausted, but local catalogue examination remains.
                // A filtered resource page cannot establish product unavailability.
                return .localWorkRemaining(firstProgress)
            }
            // Review F08: only cooling down is a temporary denial, not unavailability.
            if !eligibleTargets.isEmpty, await coordinator.nextCoolingExpiry() != nil {
                return .deferred(firstProgress, .resourceDenied)
            }
            return .unavailable(firstProgress)
        case .disposition(.resourceDenied):
            return .deferred(firstProgress, .resourceDenied)
        case .disposition(.activeGenerationConflict):
            return .deferred(firstProgress, .activeGenerationConflict)
        case .planned(let planned):
            acquisitionPlan = planned
        }

        try Task.checkCancellation()
        // First launch contacts every planned feed at once; the slowest no longer gates the rest.
        let evidence = self.evidence
        await evidence?(.contacting(acquisitionPlan.work.map(Self.targetID)))
        // Review F06: the first feed that brings supply gets a publication attempt immediately;
        // slower feeds keep admitting supply for the following cards instead of holding the screen.
        let first = FirstPublication()
        let results = try await coordinator.executeConcurrently(acquisitionPlan.work) { result in
            await evidence?(.settled(result.targetID, stop: result.stop, supplyChanged: result.selectableSupplyChanged))
            guard result.selectableSupplyChanged else { return }
            // The ingestion fact is stated to its consumer **before** the attempt below and whether or not this run
            // still publishes. `first.snapshot == nil` is a condition of *this* bootstrap publishing, never of the
            // supply existing: once the first Edition was installed, a slower source's durable result used to be
            // dropped here, so the walk the first drive had already declared exhausted was never reopened and the
            // next opportunities spent themselves on a network round that answered `up_to_date`.
            await self.onDurableSupply?()
            guard first.snapshot == nil else { return }
            // New canonical supply may precede the cursor. Only a real change reopens the head.
            try self.authority.restartExamination()
            if case .published(let snapshot) = try await self.attemptFirstPublication(identity: identity, resources: resources,
                backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
                keepsAdmittedHead: keepsAdmittedHead, mediaOpportunity: mediaOpportunity,
                mediaBudget: mediaBudget) {
                first.snapshot = snapshot
                await evidence?(.published(snapshot))
            }
        }
        if let snapshot = first.snapshot { return .published(snapshot) }
        let changed = results.contains { $0.selectableSupplyChanged }
        guard changed else { return .noPublicationAfterAcquisition(firstProgress, results) }
        switch try await attemptFirstPublication(identity: identity, resources: resources,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
            keepsAdmittedHead: keepsAdmittedHead, mediaOpportunity: mediaOpportunity,
            mediaBudget: mediaBudget) {
        case .published(let snapshot): return .published(snapshot)
        case .notYet(let progress): return .noPublicationAfterAcquisition(progress, results)
        }
    }

    /// Scoped preparation examines a finite number of windows per explicit opportunity.
    /// A pending head advances examination without reserving an Edition or reader position.
    private func attemptFirstPublication(identity: ColdFeedPublicationIdentity, resources: ColdFeedBootstrapResources,
        backwardCapacity: Int, forwardCapacity: Int, keepsAdmittedHead: Bool,
        remainingWindows: Int? = nil, mediaOpportunity: MediaPreparationOpportunity? = nil,
        mediaBudget: PublicationMediaBudget? = nil) async throws -> PublicationAttempt {
        try Task.checkCancellation()
        let remaining = remainingWindows ?? resources.localWindowCapacity
        let after = try authority.currentCursor()
        let request = try makeRequest(identity: identity, resources: resources, after: after)
        let outcome: InitialProductionSliceOutcome
        let mediaRevisions = try initialProductionSlice.revisionsToPrepare(for: request)
        if let mediaOpportunity, !mediaRevisions.isEmpty {
            // The first screen states its priority: it asks for the images of the window it is about to examine and
            // then **waits, bounded**, for them. Publishing a sparse page and hoping images arrive later was the
            // measured cause of a text-only first screen (only what happened to be ready got published), so the
            // wait is what makes an image-bearing first page possible.
            await evidence?(.preparingMedia)
            mediaOpportunity.request(mediaRevisions)
            if let readiness, let mediaBudget {
                // The target is clamped to this window's own candidate count: a window that offers three stories
                // is not a failure to find six images, and must not spend the budget waiting for them.
                let target = min(firstPublicationMediaTarget, mediaRevisions.count)
                _ = await readiness.waitForPrepared(mediaRevisions, atLeast: target, until: mediaBudget.instant())
                try Task.checkCancellation()
                try authority.ensureActive()
            }
        }
        outcome = try authority.examine(after: after, { try initialProductionSlice.run(request, prepare: prepare) })
        switch outcome {
        case .published(_, let receipt):
            // The publication's own identity leaves here, before the snapshot is admitted: the recipient counts the
            // first Edition's cards the same way it counts every later segment's. Without it the first screen's
            // buffer could only be measured on the admitted window (≤17), which is not what the publication holds.
            await evidence?(.publishedCards(receipt.cardIDs))
            guard case .published(let snapshot) = try await installedPublication(identity: identity,
                backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
                keepsAdmittedHead: keepsAdmittedHead) else {
                throw ColdFeedBootstrapError.inconsistentPublishedRestore
            }
            return .published(snapshot)
        case .advancedWithoutPublication(let progress):
            guard mediaOpportunity != nil, remaining > 1, !progress.exhausted,
                progress.examinedCount > 0, progress.nextCursor != after else { return .notYet(progress) }
            await Task.yield()
            return try await attemptFirstPublication(identity: identity, resources: resources,
                backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
                keepsAdmittedHead: keepsAdmittedHead,
                remainingWindows: remaining - 1, mediaOpportunity: mediaOpportunity,
                mediaBudget: mediaBudget)
        }
    }

    private static func targetID(_ work: AcquisitionPlannedWork) -> AcquisitionTargetID {
        switch work { case .start(let target, _), .joinActive(let target): return target.id }
    }

    private func makeRequest(identity: ColdFeedPublicationIdentity,
        resources: ColdFeedBootstrapResources, after: CandidateSupplyCursor?) throws -> InitialProductionSlice.Request {
        .init(plan: plan, policy: try acquisition.policyIncludingDiscovery(policy), examinedCapacity: resources.localExaminedCapacity,
            editionID: identity.editionID, publicationSchemaVersion: identity.publicationSchemaVersion,
            selectionSeed: identity.selectionSeed, editionCreatedAt: identity.editionCreatedAt,
            segmentID: identity.segmentID, segmentSeed: identity.segmentSeed, segmentCreatedAt: identity.segmentCreatedAt,
            anchorPlacement: identity.anchorPlacement, checkpointedAt: identity.checkpointedAt, after: after)
    }

    private func installedPublication(identity: ColdFeedPublicationIdentity, backwardCapacity: Int,
        forwardCapacity: Int, keepsAdmittedHead: Bool) async throws -> ColdFeedBootstrapOutcome {
        let bounds = FeedPresentationBounds(backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
            contextKey: plan.context.key, keepsAdmittedHead: keepsAdmittedHead)
        guard let snapshot = try await session.admitPresentation(.initial(bounds)),
            snapshot.editionID == identity.editionID else {
            throw ColdFeedBootstrapError.inconsistentPublishedRestore
        }
        return .published(snapshot)
    }
}
