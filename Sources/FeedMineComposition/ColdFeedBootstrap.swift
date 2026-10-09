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
}

public enum ColdFeedBootstrapError: Error, Equatable, Sendable {
    case policyContextMismatch
    case sessionAlreadyInstalled
    case inconsistentPublishedRestore
}

public struct ColdFeedBootstrap: Sendable {
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
        switch try initialProductionSlice.run(request, prepare: prepare) {
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
        let results = try await coordinator.executeConcurrently(acquisitionPlan.work) { result in
            await evidence?(.settled(result.targetID, stop: result.stop, supplyChanged: result.selectableSupplyChanged))
        }
        let changed = results.contains { $0.selectableSupplyChanged }
        guard changed else { return .noPublicationAfterAcquisition(firstProgress, results) }
        // PD-5/PD-6: give fresh supply a bounded chance to arrive with real images before the first
        // screen; whatever is not ready is published as a designed text-only card.
        if prepareMedia != nil { await evidence?(.preparingMedia) }
        await prepareMedia?()

        // Reuse the exact request; each initial slice starts selection at the canonical head.
        switch try initialProductionSlice.run(request, prepare: prepare) {
        case .published:
            return try await installedPublication(identity: identity, backwardCapacity: backwardCapacity,
                forwardCapacity: forwardCapacity)
        case .advancedWithoutPublication(let progress):
            return .noPublicationAfterAcquisition(progress, results)
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
            forwardCapacity: forwardCapacity), snapshot.editionID == identity.editionID else {
            throw ColdFeedBootstrapError.inconsistentPublishedRestore
        }
        return .published(snapshot)
    }
}
