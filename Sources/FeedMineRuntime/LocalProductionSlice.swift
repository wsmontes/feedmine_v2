// Owns: one caller-requested bounded local append and successful structural progress.
// Does not own: policy resolution, preparation decisions, session visibility or scheduling.

import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication

public struct LocalPreparedPublication: Hashable, Sendable {
    public let inputs: [PublicationPreparationInput]
    public let cardIDs: [PublicationCardID]

    public init(inputs: [PublicationPreparationInput], cardIDs: [PublicationCardID]) {
        self.inputs = inputs
        self.cardIDs = cardIDs
    }
}

public struct LocalProductionProgress: Hashable, Sendable {
    public let examinedCount: Int
    public let nextCursor: CandidateSupplyCursor?
    public let exhausted: Bool
}

public enum LocalProductionSliceOutcome: Hashable, Sendable {
    case advancedWithoutPublication(LocalProductionProgress)
    case published(LocalProductionProgress, PublicationReceipt)
}

public enum LocalProductionSliceError: Error, Equatable, Sendable {
    case automaticExposurePolicyRequired
    case invalidExposureFacts
    case inconsistentPublicationOutcome
}

public struct LocalProductionSlice: Sendable {
    private let candidateProvider: CandidateProvider
    private let selectionEngine: SelectionEngine
    private let publicationHistory: PublicationHistory
    private let coordinator: PublicationCoordinator

    public init(database: RuntimeDatabase) {
        candidateProvider = CandidateProvider(contentStore: ContentStore(database: database))
        selectionEngine = SelectionEngine()
        publicationHistory = PublicationHistory(database: database)
        coordinator = PublicationCoordinator(database: database)
    }

    public struct Request: Sendable {
        public let plan: FeedPlan
        public let policy: ResolvedSelectionPolicy
        public let editionID: FeedEditionID
        public let after: CandidateSupplyCursor?
        public let examinedCapacity: Int
        public let segmentID: FeedSegmentID
        public let segmentSeed: UInt64
        public let segmentCreatedAt: Date

        public init(plan: FeedPlan, policy: ResolvedSelectionPolicy, editionID: FeedEditionID,
            after: CandidateSupplyCursor?, examinedCapacity: Int, segmentID: FeedSegmentID,
            segmentSeed: UInt64, segmentCreatedAt: Date) {
            self.plan = plan
            self.policy = policy
            self.editionID = editionID
            self.after = after
            self.examinedCapacity = examinedCapacity
            self.segmentID = segmentID
            self.segmentSeed = segmentSeed
            self.segmentCreatedAt = segmentCreatedAt
        }
    }

    /// Only a successful outcome authorizes the caller to advance episode progress.
    public func run(_ request: Request,
        prepare: @Sendable (SelectionResult) throws -> LocalPreparedPublication) throws -> LocalProductionSliceOutcome {
        guard request.policy.exposure == .excludePublishedRevisions else {
            throw LocalProductionSliceError.automaticExposurePolicyRequired
        }
        let window = try candidateProvider.candidates(for: request.plan,
            after: request.after, examinedCapacity: request.examinedCapacity)
        let facts = try publicationHistory.exposure(editionID: request.editionID,
            revisionIDs: window.candidates.map(\.originRevisionID))
        guard facts.editionID == request.editionID,
            let exposure = SelectionExposureSnapshot(requestedRevisionIDs: facts.requestedRevisionIDs,
                publishedRevisionIDs: facts.publishedRevisionIDs) else {
            throw LocalProductionSliceError.invalidExposureFacts
        }
        let selection = try selectionEngine.select(plan: request.plan, policy: request.policy,
            window: window, exposure: exposure)
        let report = selection.supplyReport
        let progress = LocalProductionProgress(examinedCount: report.examinedCount,
            nextCursor: report.nextCursor, exhausted: report.exhausted)
        guard !selection.orderedCandidates.isEmpty else { return .advancedWithoutPublication(progress) }
        let prepared = try prepare(selection)
        let drafts = try PublicationPreparation.drafts(selection: selection, inputs: prepared.inputs)
        let append = PublicationCoordinator.AppendRequest(selection: selection, drafts: drafts,
            editionID: request.editionID, segmentID: request.segmentID, segmentSeed: request.segmentSeed,
            segmentCreatedAt: request.segmentCreatedAt, cardIDs: prepared.cardIDs)
        switch try coordinator.append(append, expectingTailCardID: facts.observedTailCardID) {
        case .published(let receipt): return .published(progress, receipt)
        case .nothingToPublish: throw LocalProductionSliceError.inconsistentPublicationOutcome
        }
    }
}
