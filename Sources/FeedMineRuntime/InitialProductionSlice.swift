// Owns: one bounded local attempt to publish the first durable Edition and position.
// Does not own: remote supply, scheduling or presentation installation.

import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication

public enum InitialProductionSliceOutcome: Hashable, Sendable {
    case advancedWithoutPublication(LocalProductionProgress)
    case published(LocalProductionProgress, PublicationReceipt)
}

public enum InitialProductionSliceError: Error, Equatable, Sendable {
    case automaticExposurePolicyRequired
    case invalidExposureFacts
    case inconsistentPublicationOutcome
    case staleSourceExclusions
}

public struct InitialProductionSlice: Sendable {
    private let candidateProvider: CandidateProvider
    private let selectionEngine: SelectionEngine
    private let coordinator: PublicationCoordinator
    private let readiness: MediaReadiness?
    /// The bounded memory of stories the first Edition's walk skipped while their media was pending. The first
    /// opportunity of a launch walks several windows in a row, so a skip there would otherwise be permanent too.
    private let reoffer: PendingMediaReconsideration?
    private let contentStore: ContentStore
    /// Optional evidence of the publication this slice concludes; nil records nothing. DEBUG-only at the point
    /// of recording (the host passes nil in a shipping build).
    private let trace: ReplenishmentTrace?
    /// How many cards the first publication may publish, stated by the host from the runway's own
    /// published-reserve target. Nil (every v2–v5 caller and any host that does not cap) keeps the previous behavior.
    private let publicationLimit: Int?

    public init(database: RuntimeDatabase, readiness: MediaReadiness? = nil,
        reoffer: PendingMediaReconsideration? = nil, trace: ReplenishmentTrace? = nil,
        publicationLimit: Int? = nil) {
        self.readiness = readiness
        self.reoffer = reoffer
        self.trace = trace
        self.publicationLimit = publicationLimit
        self.contentStore = ContentStore(database: database)
        candidateProvider = CandidateProvider(contentStore: contentStore)
        selectionEngine = SelectionEngine()
        coordinator = PublicationCoordinator(database: database)
    }

    public struct Request: Sendable {
        /// Captured once before preparation. Nil preserves callers outside the guarded app pipeline.
        public var sourceExclusions: ProductionSourceExclusions? = nil
        public let plan: FeedPlan
        public let policy: ResolvedSelectionPolicy
        public let examinedCapacity: Int
        public let editionID: FeedEditionID
        public let publicationSchemaVersion: PublicationSchemaVersion
        public let selectionSeed: UInt64
        public let editionCreatedAt: Date
        public let segmentID: FeedSegmentID
        public let segmentSeed: UInt64
        public let segmentCreatedAt: Date
        public let anchorPlacement: AnchorPlacement
        public let checkpointedAt: Date
        /// Structural examination position; it is not a reader checkpoint or reserved publication rank.
        public let after: CandidateSupplyCursor?

        public init(plan: FeedPlan, policy: ResolvedSelectionPolicy, examinedCapacity: Int, editionID: FeedEditionID, publicationSchemaVersion: PublicationSchemaVersion, selectionSeed: UInt64, editionCreatedAt: Date, segmentID: FeedSegmentID, segmentSeed: UInt64, segmentCreatedAt: Date, anchorPlacement: AnchorPlacement, checkpointedAt: Date, after: CandidateSupplyCursor? = nil) {
            self.plan = plan
            self.policy = policy
            self.examinedCapacity = examinedCapacity
            self.editionID = editionID
            self.publicationSchemaVersion = publicationSchemaVersion
            self.selectionSeed = selectionSeed
            self.editionCreatedAt = editionCreatedAt
            self.segmentID = segmentID
            self.segmentSeed = segmentSeed
            self.segmentCreatedAt = segmentCreatedAt
            self.anchorPlacement = anchorPlacement
            self.checkpointedAt = checkpointedAt
            self.after = after
        }
    }

    /// The first publication of a Source context is bounded by that source's own
    /// supply, not by unrelated global rows. Main and Search keep the global window.
    private func firstWindow(for request: Request) throws -> CandidateSupplyWindow {
        let sourceScoped: Bool
        if case .source = request.plan.context.request { sourceScoped = true } else { sourceScoped = false }
        return try candidateProvider.candidates(for: request.plan, after: request.after,
            examinedCapacity: request.examinedCapacity, sourceScoped: sourceScoped,
            excludingSourceIDs: request.sourceExclusions?.sourceIDs ?? [])
    }

    /// The next bounded structural window, including unresolved revisions so preparation can
    /// work on them. Composition supplies resources; Runtime retains ownership of supply lookup.
    public func revisionsToPrepare(for request: Request) throws -> [OriginRevisionID] {
        let window = try firstWindow(for: request)
        switch request.policy.eligibility {
        case .structuralOnly: return window.candidates.map(\.originRevisionID)
        case .selectedSources(let selected):
            return window.candidates.filter { !Set($0.sourceIDs).isDisjoint(with: selected) }.map(\.originRevisionID)
        }
    }

    /// Only a successful outcome authorizes the caller to advance episode progress.
    public func run(_ request: Request,
        prepare: @Sendable (SelectionResult) throws -> LocalPreparedPublication) throws -> InitialProductionSliceOutcome {
        guard request.policy.exposure == .excludePublishedRevisions || request.policy.exposure == .excludePublishedMaterial else {
            throw InitialProductionSliceError.automaticExposurePolicyRequired
        }
        // The structural walk this attempt advances; the first Edition publishes nothing yet, so the only facts the
        // window needs are its own candidates.
        let structural = try firstWindow(for: request)
        // Same rule as the live walk: a story this walk skipped for pending media is re-offered here, placed before
        // the structural candidates in the array (SelectionEngine orders by its comparator) and contributing nothing
        // to what the walk reports as examined.
        let reconsidered = try MediaSkippedSupply.reconsider(provider: candidateProvider, plan: request.plan,
            editionID: request.editionID, structural: structural, readiness: readiness, reoffer: reoffer,
            excludingSourceIDs: request.sourceExclusions?.sourceIDs ?? [])
        let window = reconsidered.candidates.isEmpty ? structural : CandidateSupplyWindow(
            candidates: reconsidered.candidates + structural.candidates,
            examinedCount: structural.examinedCount, nextCursor: structural.nextCursor,
            exhausted: structural.exhausted)
        guard let exposure = SelectionExposureSnapshot(
            requestedOriginIDs: window.candidates.map(\.originRecordID), publishedOriginIDs: []) else {
            throw InitialProductionSliceError.invalidExposureFacts
        }
        let revisions = window.candidates.map(\.originRevisionID)
        let readinessFacts: SelectionReadinessSnapshot?
        if let readiness {
            guard let facts = SelectionReadinessSnapshot(requestedRevisionIDs: revisions,
                readyRevisionIDs: Set(readiness.presentations(for: revisions).keys)) else {
                throw SelectionError.readinessCoverageMismatch
            }
            readinessFacts = facts
            // The first Edition has published nothing, so no skip can already be settled by publication here.
            try MediaSkippedSupply.remember(structural: structural, editionID: request.editionID,
                publishedOriginIDs: [], readiness: readiness, reoffer: reoffer)
        } else { readinessFacts = nil }
        let selection = try selectionEngine.select(plan: request.plan, policy: request.policy,
            window: window, exposure: exposure, after: nil, readiness: readinessFacts,
            publicationLimit: publicationLimit)
        // Examination advances through structural supply, independently of editorial holds.
        // A held candidate owns no occurrence or rank; a later supply reconsideration may
        // revisit it under fresh exposure and readiness facts without rewinding this walk.
        // The reconsidered set contributes candidates to this attempt and nothing to what the walk reports.
        // A publication that hits the publication cap reports the walk it started from instead
        // (`afterPublication`): the first publication leaves ready supply behind, and the walk must not pass it.
        let progress = LocalProductionProgress(examinedCount: structural.examinedCount,
            nextCursor: structural.nextCursor, exhausted: structural.exhausted)
        // An opportunity that publishes nothing settles nothing: the reconsidered story stays eligible.
        guard !selection.orderedCandidates.isEmpty else {
            return .advancedWithoutPublication(progress)
        }
        let prepared = try prepare(selection)
        // An image-bearing candidate whose media is not prepared leaves this opportunity; the card is never
        // published as text in its place (INV-17).
        let plan = try PublicationPreparation.plan(selection: selection, publication: prepared)
        guard !plan.drafts.isEmpty else {
            return .advancedWithoutPublication(progress)
        }
        let publication = PublicationCoordinator.CreateRequest(selection: plan.selection, drafts: plan.drafts,
            editionID: request.editionID, publicationSchemaVersion: request.publicationSchemaVersion,
            selectionSeed: request.selectionSeed, editionCreatedAt: request.editionCreatedAt,
            segmentID: request.segmentID, segmentSeed: request.segmentSeed,
            segmentCreatedAt: request.segmentCreatedAt, cardIDs: plan.cardIDs,
            expectedSourceExclusions: request.sourceExclusions?.snapshot)
        let publicationOutcome: PublicationOutcome
        do { publicationOutcome = try coordinator.createInitialEdition(.init(publication: publication,
            anchorPlacement: request.anchorPlacement, checkpointedAt: request.checkpointedAt)) }
        catch PublicationStoreError.staleSourceExclusions { throw InitialProductionSliceError.staleSourceExclusions }
        switch publicationOutcome {
        case .published(let receipt):
            #if DEBUG
            MediaPreparationTrace.recordPublished(plan.drafts, in: contentStore, to: trace)
            #endif
            // Only the stories this receipt published are settled; a held or filtered one keeps its chance.
            let publishedRevisions = Set(plan.selection.orderedCandidates.map(\.originRevisionID))
            reoffer?.forget(reconsidered.considered.filter {
                publishedRevisions.contains($0.originRevisionID)
            })
            return .published(LocalProductionProgress.afterPublication(selection, examining: structural,
                from: request.after, publicationLimit: publicationLimit), receipt)
        case .nothingToPublish: throw InitialProductionSliceError.inconsistentPublicationOutcome
        }
    }
}
