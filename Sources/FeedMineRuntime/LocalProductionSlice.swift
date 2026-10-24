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
    private let readiness: MediaReadiness?
    /// The bounded memory of stories this Edition's walk skipped while their media was pending. Without it a skip
    /// is permanent: the cursor never returns to it. Nil leaves the one-way walk exactly as it was.
    private let reoffer: PendingMediaReconsideration?
    /// Optional evidence of the replenishment attempt this slice executes; nil records nothing.
    private let trace: ReplenishmentTrace?

    /// Existing callers may supply their own intentional presentations. Media-dependent callers
    /// must inject the same readiness index used by their preparation closure.
    public init(database: RuntimeDatabase, readiness: MediaReadiness? = nil,
        reoffer: PendingMediaReconsideration? = nil, trace: ReplenishmentTrace? = nil) {
        self.readiness = readiness
        self.reoffer = reoffer
        self.trace = trace
        contentStore = ContentStore(database: database)
        candidateProvider = CandidateProvider(contentStore: contentStore)
        selectionEngine = SelectionEngine()
        publicationHistory = PublicationHistory(database: database)
        coordinator = PublicationCoordinator(database: database, trace: trace)
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
        /// Reader position; an origin with an occurrence after it is not published again (PD-1 rule 2).
        public let readerAnchorCardID: PublicationCardID?
        /// The replenishment attempt this slice belongs to, when a host decided one; nil for work that is not a
        /// replenishment (the first Edition, hidden tail maintenance).
        public let operation: FeedReplenishmentOperationID?

        public init(plan: FeedPlan, policy: ResolvedSelectionPolicy, editionID: FeedEditionID,
            after: CandidateSupplyCursor?, examinedCapacity: Int, segmentID: FeedSegmentID,
            segmentSeed: UInt64, segmentCreatedAt: Date, readerAnchorCardID: PublicationCardID? = nil,
            operation: FeedReplenishmentOperationID? = nil) {
            self.readerAnchorCardID = readerAnchorCardID
            self.operation = operation
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
        // Examination advances through structural supply, independently of editorial holds: the progress this
        // slice reports below is this window's, never the reconsidered set's.
        let structural = try candidateProvider.candidates(for: request.plan,
            after: request.after, examinedCapacity: request.examinedCapacity,
            operation: request.operation, consult: "slice", trace: trace)
        // What the one-way walk already passed and whose media became ready since. It joins the same selection,
        // after the structural candidates, and the structural walk stays exactly where it was.
        let reconsidered = try MediaSkippedSupply.reconsider(provider: candidateProvider, plan: request.plan,
            editionID: request.editionID, structural: structural, readiness: readiness, reoffer: reoffer)
        let window = reconsidered.candidates.isEmpty ? structural : CandidateSupplyWindow(
            candidates: reconsidered.candidates + structural.candidates,
            examinedCount: structural.examinedCount, nextCursor: structural.nextCursor,
            exhausted: structural.exhausted)
        let facts = try publicationHistory.exposure(editionID: request.editionID,
            originIDs: window.candidates.map(\.originRecordID), readerAnchorCardID: request.readerAnchorCardID)
        guard facts.editionID == request.editionID,
            let exposure = SelectionExposureSnapshot(requestedOriginIDs: facts.requestedOriginIDs,
                publishedOriginIDs: facts.publishedOriginIDs, publishedMaterialKeys: facts.publishedMaterialKeys,
                unseenOriginIDs: facts.unseenOriginIDs) else {
            throw LocalProductionSliceError.invalidExposureFacts
        }
        // PD-1: this Edition already published the origin, so the skip can never become a card here. It leaves the
        // queue with the fact that settled it. The candidate stays in the window because exposure is what states
        // that fact to selection; it is the queue entry, not the supply, that this rule removes.
        if let reoffer, !facts.publishedOriginIDs.isEmpty {
            reoffer.forget(reconsidered.considered.filter {
                facts.publishedOriginIDs.contains($0.originRecordID)
            })
        }
        let revisions = window.candidates.map(\.originRevisionID)
        let readinessFacts: SelectionReadinessSnapshot?
        if let readiness {
            guard let snapshot = SelectionReadinessSnapshot(requestedRevisionIDs: revisions,
                readyRevisionIDs: Set(readiness.presentations(for: revisions).keys)) else {
                throw SelectionError.readinessCoverageMismatch
            }
            readinessFacts = snapshot
            MediaSkippedSupply.remember(structural: structural, editionID: request.editionID,
                publishedOriginIDs: facts.publishedOriginIDs, readiness: readiness, reoffer: reoffer)
        } else {
            readinessFacts = nil
        }
        // P10/R17: diversity reads the facts the **publication** froze, newest first, in the same Edition. A legacy
        // row has no fact and contributes nothing; the engine enables the tie-break only for the supported version.
        let recentDiversity = try publicationHistory.recentDiversity(editionID: request.editionID, limit: 16)
        let diversity = SelectionDiversityContext(recent: recentDiversity)
        // PD-4: the Edition tail precedes this segment, so alternation holds across segments.
        let selection = try selectionEngine.select(plan: request.plan, policy: request.policy,
            window: window, exposure: exposure,
            after: try neighbor(editionID: request.editionID, tail: facts.observedTailCardID),
            readiness: readinessFacts, diversity: diversity)
        // Examination advances through structural supply, independently of editorial holds.
        // A held candidate owns no occurrence or rank; a later supply reconsideration may
        // revisit it under fresh exposure and readiness facts without rewinding this walk.
        // The reconsidered set is not part of that walk: it adds candidates to this opportunity and nothing to
        // `examinedCount` or `nextCursor`, so a re-offered story never moves the cursor, not even backwards.
        let progress = LocalProductionProgress(examinedCount: structural.examinedCount,
            nextCursor: structural.nextCursor, exhausted: structural.exhausted)
        guard !selection.orderedCandidates.isEmpty else {
            reoffer?.forget(reconsidered.considered)
            return .advancedWithoutPublication(progress)
        }
        let prepared = try prepare(selection)
        // A selected candidate whose declared image is not prepared is not published as text; it leaves this
        // opportunity and the ready candidates around it are published normally (INV-17).
        let plan = try PublicationPreparation.plan(selection: selection, publication: prepared)
        guard !plan.drafts.isEmpty else {
            reoffer?.forget(reconsidered.considered)
            return .advancedWithoutPublication(progress)
        }
        let append = PublicationCoordinator.AppendRequest(selection: plan.selection, drafts: plan.drafts,
            editionID: request.editionID, segmentID: request.segmentID, segmentSeed: request.segmentSeed,
            segmentCreatedAt: request.segmentCreatedAt, cardIDs: plan.cardIDs,
            originRecurrence: request.policy.exposure == .excludePublishedMaterial ? .whenMaterialChanged : .forbidden,
            operation: request.operation)
        switch try coordinator.append(append, expectingTailCardID: facts.observedTailCardID) {
        case .published(let receipt):
            #if DEBUG
            // The slice's contract with the port is that work which is not a replenishment reports nothing; the
            // media fact rides the same port, so it follows the same rule. Production local slices always carry
            // the operation their attempt minted.
            if request.operation != nil {
                MediaPreparationTrace.recordPublished(plan.drafts, in: contentStore, to: trace)
            }
            #endif
            // The opportunity settled these skips: published, held by alternation, or excluded by a filter. The
            // queue is an admission back into selection, not an override of it, so it does not re-offer them.
            reoffer?.forget(reconsidered.considered)
            return .published(progress, receipt)
        case .nothingToPublish: throw LocalProductionSliceError.inconsistentPublicationOutcome
        }
    }

    /// PD-4 uses the published tail's frozen attribution, not mutable supply memberships.
    private func neighbor(editionID: FeedEditionID, tail: PublicationCardID) throws -> SelectionNeighbor {
        let window = try publicationHistory.window(editionID: editionID,
            around: FeedWindowAnchor(cardID: tail, placement: .top), backwardCapacity: 0, forwardCapacity: 0)
        guard let card = window.cards.first(where: { $0.id == tail }) else {
            throw LocalProductionSliceError.invalidExposureFacts
        }
        let sources = Set(card.origin.sourceID.map { [$0] } ?? [])
        return SelectionNeighbor(sourceIDs: sources, providerID: card.origin.providerID)
    }
}
