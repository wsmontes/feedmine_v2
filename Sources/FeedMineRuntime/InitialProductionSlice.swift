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

    public init(database: RuntimeDatabase, readiness: MediaReadiness? = nil,
        reoffer: PendingMediaReconsideration? = nil, trace: ReplenishmentTrace? = nil) {
        self.readiness = readiness
        self.reoffer = reoffer
        self.trace = trace
        self.contentStore = ContentStore(database: database)
        candidateProvider = CandidateProvider(contentStore: contentStore)
        selectionEngine = SelectionEngine()
        coordinator = PublicationCoordinator(database: database)
    }

    public struct Request: Sendable {
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

    /// The next bounded structural window, including unresolved revisions so preparation can
    /// work on them. Composition supplies resources; Runtime retains ownership of supply lookup.
    public func revisionsToPrepare(for request: Request) throws -> [OriginRevisionID] {
        let window = try candidateProvider.candidates(for: request.plan,
            after: request.after, examinedCapacity: request.examinedCapacity)
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
        let structural = try candidateProvider.candidates(for: request.plan,
            after: request.after, examinedCapacity: request.examinedCapacity)
        // Same rule as the live walk: a story this walk skipped for pending media is re-offered here, placed before
        // the structural candidates in the array (SelectionEngine orders by its comparator) and contributing nothing
        // to what the walk reports as examined.
        let reconsidered = try MediaSkippedSupply.reconsider(provider: candidateProvider, plan: request.plan,
            editionID: request.editionID, structural: structural, readiness: readiness, reoffer: reoffer)
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
            window: window, exposure: exposure, after: nil, readiness: readinessFacts)
        // Examination advances through structural supply, independently of editorial holds.
        // A held candidate owns no occurrence or rank; a later supply reconsideration may
        // revisit it under fresh exposure and readiness facts without rewinding this walk.
        // The reconsidered set contributes candidates to this attempt and nothing to what the walk reports.
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
            segmentCreatedAt: request.segmentCreatedAt, cardIDs: plan.cardIDs)
        switch try coordinator.createInitialEdition(.init(publication: publication,
            anchorPlacement: request.anchorPlacement, checkpointedAt: request.checkpointedAt)) {
        case .published(let receipt):
            #if DEBUG
            MediaPreparationTrace.recordPublished(plan.drafts, in: contentStore, to: trace)
            #endif
            // Only the stories this receipt published are settled; a held or filtered one keeps its chance.
            let publishedRevisions = Set(plan.selection.orderedCandidates.map(\.originRevisionID))
            reoffer?.forget(reconsidered.considered.filter {
                publishedRevisions.contains($0.originRevisionID)
            })
            return .published(progress, receipt)
        case .nothingToPublish: throw InitialProductionSliceError.inconsistentPublicationOutcome
        }
    }
}
