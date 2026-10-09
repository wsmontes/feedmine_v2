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
    private let contentStore: ContentStore
    private let candidateProvider: CandidateProvider
    private let selectionEngine: SelectionEngine
    private let publicationHistory: PublicationHistory
    private let coordinator: PublicationCoordinator

    public init(database: RuntimeDatabase) {
        contentStore = ContentStore(database: database)
        candidateProvider = CandidateProvider(contentStore: contentStore)
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
        guard request.policy.exposure == .excludePublishedRevisions || request.policy.exposure == .excludePublishedMaterial else {
            throw LocalProductionSliceError.automaticExposurePolicyRequired
        }
        let window = try candidateProvider.candidates(for: request.plan,
            after: request.after, examinedCapacity: request.examinedCapacity)
        let facts = try publicationHistory.exposure(editionID: request.editionID,
            originIDs: window.candidates.map(\.originRecordID))
        guard facts.editionID == request.editionID,
            let exposure = SelectionExposureSnapshot(requestedOriginIDs: facts.requestedOriginIDs,
                publishedOriginIDs: facts.publishedOriginIDs, publishedMaterialKeys: facts.publishedMaterialKeys) else {
            throw LocalProductionSliceError.invalidExposureFacts
        }
        // PD-4: the Edition tail precedes this segment, so alternation holds across segments.
        let selection = try selectionEngine.select(plan: request.plan, policy: request.policy,
            window: window, exposure: exposure,
            after: try neighbor(editionID: request.editionID, tail: facts.observedTailCardID))
        let report = selection.supplyReport
        let progress = LocalProductionProgress(examinedCount: report.examinedCount,
            nextCursor: report.nextCursor, exhausted: report.exhausted)
        guard !selection.orderedCandidates.isEmpty else { return .advancedWithoutPublication(progress) }
        let prepared = try prepare(selection)
        let drafts = try PublicationPreparation.drafts(selection: selection, inputs: prepared.inputs)
        let append = PublicationCoordinator.AppendRequest(selection: selection, drafts: drafts,
            editionID: request.editionID, segmentID: request.segmentID, segmentSeed: request.segmentSeed,
            segmentCreatedAt: request.segmentCreatedAt, cardIDs: prepared.cardIDs,
            originRecurrence: request.policy.exposure == .excludePublishedMaterial ? .whenMaterialChanged : .forbidden)
        switch try coordinator.append(append, expectingTailCardID: facts.observedTailCardID) {
        case .published(let receipt): return .published(progress, receipt)
        case .nothingToPublish: throw LocalProductionSliceError.inconsistentPublicationOutcome
        }
    }

    /// Attribution of the published tail: its frozen source plus the origin's current memberships.
    private func neighbor(editionID: FeedEditionID, tail: PublicationCardID) throws -> SelectionNeighbor {
        let window = try publicationHistory.window(editionID: editionID,
            around: FeedWindowAnchor(cardID: tail, placement: .top), backwardCapacity: 0, forwardCapacity: 0)
        guard let card = window.cards.first(where: { $0.id == tail }) else {
            throw LocalProductionSliceError.invalidExposureFacts
        }
        var sources = Set(try contentStore.memberships(originRecordID: card.origin.originRecordID).map(\.sourceID))
        if let frozen = card.origin.sourceID { sources.insert(frozen) }
        return SelectionNeighbor(sourceIDs: sources, providerID: card.origin.providerID)
    }
}
