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

    public init?(localExaminedCapacity: Int, acquisition: AcquisitionPlanningResources) {
        guard localExaminedCapacity > 0 else { return nil }
        self.localExaminedCapacity = localExaminedCapacity
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
}

/// Revocation and synchronous publication share one lock; close cannot race the commit boundary.
private final class ColdPublicationAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    func cancel() { lock.lock(); active = false; lock.unlock() }
    func perform<T>(_ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        guard active else { throw ColdFeedBootstrapError.closed }
        try Task.checkCancellation()
        return try operation()
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
    private let prepareMedia: (@Sendable () async -> Void)?
    private let evidence: (@Sendable (ColdFeedEvidence) async -> Void)?

    /// The external composition supplies a coordinator over the snapshot's same runtime database.
    public init(session: FeedSession, plan: FeedPlan, policy: ResolvedSelectionPolicy,
        acquisition: SyndicationAcquisitionSnapshot, coordinator: AcquisitionCoordinator,
        prepare: @escaping @Sendable (SelectionResult) throws -> LocalPreparedPublication,
        prepareMedia: (@Sendable () async -> Void)? = nil,
        evidence: (@Sendable (ColdFeedEvidence) async -> Void)? = nil) throws {
        guard policy.contextKey == plan.context.key else { throw ColdFeedBootstrapError.policyContextMismatch }
        self.prepareMedia = prepareMedia
        self.evidence = evidence
        self.session = session
        self.plan = plan
        self.policy = policy
        self.acquisition = acquisition
        self.coordinator = coordinator
        initialProductionSlice = InitialProductionSlice(database: acquisition.runtimeDatabase)
        self.prepare = prepare
    }

    public func run(identity: ColdFeedPublicationIdentity, resources: ColdFeedBootstrapResources,
        backwardCapacity: Int, forwardCapacity: Int) async throws -> ColdFeedBootstrapOutcome {
        guard await session.currentPresentation() == nil else { throw ColdFeedBootstrapError.sessionAlreadyInstalled }
        let request = makeRequest(identity: identity, resources: resources)
        let firstProgress: LocalProductionProgress
        switch try authority.perform({ try initialProductionSlice.run(request, prepare: prepare) }) {
        case .published:
            return try await installedPublication(identity: identity, backwardCapacity: backwardCapacity,
                forwardCapacity: forwardCapacity)
        case .advancedWithoutPublication(let progress):
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
            if case .published(let snapshot) = try await self.attemptFirstPublication(request, identity: identity,
                backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity) {
                first.snapshot = snapshot
                await evidence?(.published(snapshot))
            }
        }
        if let snapshot = first.snapshot { return .published(snapshot) }
        let changed = results.contains { $0.selectableSupplyChanged }
        guard changed else { return .noPublicationAfterAcquisition(firstProgress, results) }
        switch try await attemptFirstPublication(request, identity: identity,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity) {
        case .published(let snapshot): return .published(snapshot)
        case .notYet(let progress): return .noPublicationAfterAcquisition(progress, results)
        }
    }

    /// One initial-slice attempt over current supply. Reuses the exact request: each initial slice
    /// starts selection at the canonical head, and the durable first Edition is created at most once.
    private func attemptFirstPublication(_ request: InitialProductionSlice.Request, identity: ColdFeedPublicationIdentity,
        backwardCapacity: Int, forwardCapacity: Int) async throws -> PublicationAttempt {
        // PD-5/PD-6: give fresh supply a bounded chance to arrive with real images before the first
        // screen; whatever is not ready is published as a designed text-only card.
        if prepareMedia != nil { await evidence?(.preparingMedia) }
        await prepareMedia?()
        switch try authority.perform({ try initialProductionSlice.run(request, prepare: prepare) }) {
        case .published:
            guard case .published(let snapshot) = try await installedPublication(identity: identity,
                backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity) else {
                throw ColdFeedBootstrapError.inconsistentPublishedRestore
            }
            return .published(snapshot)
        case .advancedWithoutPublication(let progress):
            return .notYet(progress)
        }
    }

    private static func targetID(_ work: AcquisitionPlannedWork) -> AcquisitionTargetID {
        switch work { case .start(let target, _), .joinActive(let target): return target.id }
    }

    private func makeRequest(identity: ColdFeedPublicationIdentity,
        resources: ColdFeedBootstrapResources) -> InitialProductionSlice.Request {
        .init(plan: plan, policy: policy, examinedCapacity: resources.localExaminedCapacity,
            editionID: identity.editionID, publicationSchemaVersion: identity.publicationSchemaVersion,
            selectionSeed: identity.selectionSeed, editionCreatedAt: identity.editionCreatedAt,
            segmentID: identity.segmentID, segmentSeed: identity.segmentSeed, segmentCreatedAt: identity.segmentCreatedAt,
            anchorPlacement: identity.anchorPlacement, checkpointedAt: identity.checkpointedAt)
    }

    private func installedPublication(identity: ColdFeedPublicationIdentity,
        backwardCapacity: Int, forwardCapacity: Int) async throws -> ColdFeedBootstrapOutcome {
        guard let snapshot = try await session.restoreLocalPresentation(backwardCapacity: backwardCapacity,
            forwardCapacity: forwardCapacity, contextKey: plan.context.key), snapshot.editionID == identity.editionID else {
            throw ColdFeedBootstrapError.inconsistentPublishedRestore
        }
        return .published(snapshot)
    }
}
