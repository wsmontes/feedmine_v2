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

    public init(database: RuntimeDatabase) {
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

        public init(plan: FeedPlan, policy: ResolvedSelectionPolicy, examinedCapacity: Int, editionID: FeedEditionID, publicationSchemaVersion: PublicationSchemaVersion, selectionSeed: UInt64, editionCreatedAt: Date, segmentID: FeedSegmentID, segmentSeed: UInt64, segmentCreatedAt: Date, anchorPlacement: AnchorPlacement, checkpointedAt: Date) {
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
        }
    }

    /// Only a successful outcome authorizes the caller to advance episode progress.
    public func run(_ request: Request,
        prepare: @Sendable (SelectionResult) throws -> LocalPreparedPublication) throws -> InitialProductionSliceOutcome {
        guard request.policy.exposure == .excludePublishedRevisions else {
            throw InitialProductionSliceError.automaticExposurePolicyRequired
        }
        let window = try candidateProvider.candidates(for: request.plan,
            after: nil, examinedCapacity: request.examinedCapacity)
        guard let exposure = SelectionExposureSnapshot(
            requestedRevisionIDs: window.candidates.map(\.originRevisionID), publishedRevisionIDs: []) else {
            throw InitialProductionSliceError.invalidExposureFacts
        }
        let selection = try selectionEngine.select(plan: request.plan, policy: request.policy,
            window: window, exposure: exposure)
        let report = selection.supplyReport
        let progress = LocalProductionProgress(examinedCount: report.examinedCount,
            nextCursor: report.nextCursor, exhausted: report.exhausted)
        guard !selection.orderedCandidates.isEmpty else { return .advancedWithoutPublication(progress) }
        let prepared = try prepare(selection)
        let drafts = try PublicationPreparation.drafts(selection: selection, inputs: prepared.inputs)
        let publication = PublicationCoordinator.CreateRequest(selection: selection, drafts: drafts,
            editionID: request.editionID, publicationSchemaVersion: request.publicationSchemaVersion,
            selectionSeed: request.selectionSeed, editionCreatedAt: request.editionCreatedAt,
            segmentID: request.segmentID, segmentSeed: request.segmentSeed,
            segmentCreatedAt: request.segmentCreatedAt, cardIDs: prepared.cardIDs)
        switch try coordinator.createInitialEdition(.init(publication: publication,
            anchorPlacement: request.anchorPlacement, checkpointedAt: request.checkpointedAt)) {
        case .published(let receipt): return .published(progress, receipt)
        case .nothingToPublish: throw InitialProductionSliceError.inconsistentPublicationOutcome
        }
    }
}
