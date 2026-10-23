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

/// PD-3: real first-launch evidence for an entertaining, honest preparation screen.
public enum ColdFeedEvidence: Hashable, Sendable {
    case contacting([AcquisitionTargetID])
    case settled(AcquisitionTargetID, stop: AcquisitionExecutionStop, supplyChanged: Bool)
    case preparingMedia
    /// Review F06: the first Edition is installed; slower feeds are still answering.
    case published(FeedPresentationSnapshot)
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
    private let onDiscoveryPage: (@Sendable ([LegacyCatalogEntry]) async -> Void)?
    private let evidence: (@Sendable (ColdFeedEvidence) async -> Void)?

    /// The external composition supplies a coordinator over the snapshot's same runtime database.
    public init(session: FeedSession, plan: FeedPlan, policy: ResolvedSelectionPolicy,
        acquisition: SyndicationAcquisitionSnapshot, coordinator: AcquisitionCoordinator,
        prepare: @escaping @Sendable (SelectionResult) throws -> LocalPreparedPublication,
        evidence: (@Sendable (ColdFeedEvidence) async -> Void)? = nil,
        readiness: MediaReadiness? = nil,
        reoffer: PendingMediaReconsideration? = nil,
        trace: ReplenishmentTrace? = nil,
        onDiscoveryPage: (@Sendable ([LegacyCatalogEntry]) async -> Void)? = nil,
        makeMediaOpportunity: (@Sendable () async -> MediaPreparationOpportunity)? = nil) throws {
        guard policy.contextKey == plan.context.key else { throw ColdFeedBootstrapError.policyContextMismatch }
        self.makeMediaOpportunity = makeMediaOpportunity
        self.onDiscoveryPage = onDiscoveryPage
        self.evidence = evidence
        self.session = session
        self.plan = plan
        self.policy = policy
        self.acquisition = acquisition
        self.coordinator = coordinator
        initialProductionSlice = InitialProductionSlice(database: acquisition.runtimeDatabase, readiness: readiness,
            reoffer: reoffer, trace: trace)
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
        let firstProgress: LocalProductionProgress
        switch try await attemptFirstPublication(identity: identity, resources: resources,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
            keepsAdmittedHead: keepsAdmittedHead, mediaOpportunity: mediaOpportunity) {
        case .published(let snapshot): return .published(snapshot)
        case .notYet(let progress):
            if !progress.exhausted {
                // A Source context's local-first walk is bounded by its own supply. The
                // structural page is global, so a full page of unrelated supply reports
                // nonexhausted even when the selected source owns nothing: that page is
                // never local work this context can publish. Acquisition is the next fact
                // then; Main and Search keep the documented local-first rule.
                let sourceHasNoLocalSupply: Bool
                if case .source = plan.context.request {
                    sourceHasNoLocalSupply = try initialProductionSlice.hasLocalSupply(for: plan.context) == false
                } else {
                    sourceHasNoLocalSupply = false
                }
                guard sourceHasNoLocalSupply else { return .localWorkRemaining(progress) }
            }
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
            guard result.selectableSupplyChanged, first.snapshot == nil else { return }
            // New canonical supply may precede the cursor. Only a real change reopens the head.
            try self.authority.restartExamination()
            if case .published(let snapshot) = try await self.attemptFirstPublication(identity: identity, resources: resources,
                backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
                keepsAdmittedHead: keepsAdmittedHead, mediaOpportunity: mediaOpportunity) {
                first.snapshot = snapshot
                await evidence?(.published(snapshot))
            }
        }
        if let snapshot = first.snapshot { return .published(snapshot) }
        let changed = results.contains { $0.selectableSupplyChanged }
        guard changed else { return .noPublicationAfterAcquisition(firstProgress, results) }
        switch try await attemptFirstPublication(identity: identity, resources: resources,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity,
            keepsAdmittedHead: keepsAdmittedHead, mediaOpportunity: mediaOpportunity) {
        case .published(let snapshot): return .published(snapshot)
        case .notYet(let progress): return .noPublicationAfterAcquisition(progress, results)
        }
    }

    /// Scoped preparation examines a finite number of windows per explicit opportunity.
    /// A pending head advances examination without reserving an Edition or reader position.
    private func attemptFirstPublication(identity: ColdFeedPublicationIdentity, resources: ColdFeedBootstrapResources,
        backwardCapacity: Int, forwardCapacity: Int, keepsAdmittedHead: Bool,
        remainingWindows: Int? = nil, mediaOpportunity: MediaPreparationOpportunity? = nil) async throws -> PublicationAttempt {
        try Task.checkCancellation()
        let remaining = remainingWindows ?? resources.localWindowCapacity
        let after = try authority.currentCursor()
        let request = try makeRequest(identity: identity, resources: resources, after: after)
        let outcome: InitialProductionSliceOutcome
        let mediaRevisions = try initialProductionSlice.revisionsToPrepare(for: request)
        if let mediaOpportunity, !mediaRevisions.isEmpty {
            // R07: the first screen states its priority and examines what is ready; it never waits for media.
            await evidence?(.preparingMedia)
            mediaOpportunity.request(mediaRevisions)
        }
        outcome = try authority.examine(after: after, { try initialProductionSlice.run(request, prepare: prepare) })
        switch outcome {
        case .published:
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
                remainingWindows: remaining - 1, mediaOpportunity: mediaOpportunity)
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
