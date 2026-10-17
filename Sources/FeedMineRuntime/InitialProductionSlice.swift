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

    public init(database: RuntimeDatabase, readiness: MediaReadiness? = nil) {
        self.readiness = readiness
        candidateProvider = CandidateProvider(contentStore: ContentStore(database: database))
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
        let window = try candidateProvider.candidates(for: request.plan,
            after: request.after, examinedCapacity: request.examinedCapacity)
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
        } else { readinessFacts = nil }
        let selection = try selectionEngine.select(plan: request.plan, policy: request.policy,
            window: window, exposure: exposure, after: nil, readiness: readinessFacts)
        // Examination advances through structural supply, independently of editorial holds.
        // A held candidate owns no occurrence or rank; a later supply reconsideration may
        // revisit it under fresh exposure and readiness facts without rewinding this walk.
        let progress = LocalProductionProgress(examinedCount: window.examinedCount,
            nextCursor: window.nextCursor, exhausted: window.exhausted)
        guard !selection.orderedCandidates.isEmpty else { return .advancedWithoutPublication(progress) }
        let prepared = try prepare(selection)
        // An image-bearing candidate whose media is not prepared leaves this opportunity; the card is never
        // published as text in its place (INV-17).
        let plan = try PublicationPreparation.plan(selection: selection, publication: prepared)
        guard !plan.drafts.isEmpty else { return .advancedWithoutPublication(progress) }
        let publication = PublicationCoordinator.CreateRequest(selection: plan.selection, drafts: plan.drafts,
            editionID: request.editionID, publicationSchemaVersion: request.publicationSchemaVersion,
            selectionSeed: request.selectionSeed, editionCreatedAt: request.editionCreatedAt,
            segmentID: request.segmentID, segmentSeed: request.segmentSeed,
            segmentCreatedAt: request.segmentCreatedAt, cardIDs: plan.cardIDs)
        switch try coordinator.createInitialEdition(.init(publication: publication,
            anchorPlacement: request.anchorPlacement, checkpointedAt: request.checkpointedAt)) {
        case .published(let receipt): return .published(progress, receipt)
        case .nothingToPublish: throw InitialProductionSliceError.inconsistentPublicationOutcome
        }
    }
}
