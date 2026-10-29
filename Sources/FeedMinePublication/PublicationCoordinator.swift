// Owns: freezing aligned prepared values into atomic immutable history.
// Does not own: preparation, selection or session visibility.

import Foundation
import FeedMineDomain
import FeedMineEditorial
import FeedMinePersistence

public enum PublicationCoordinatorError: Error, Equatable, Sendable {
    case inputCountMismatch
    case duplicatePublicationCardID
    case draftCandidateMismatch(index: Int)
    case missingEdition
    case editorialRevisionMismatch
    case invalidPreparedCard(index: Int)
    case recurrenceRequiresTailExpectation
}

/// PD-1: occurrence policy for origins already published in the Edition.
public enum PublicationOriginRecurrence: Hashable, Sendable {
    /// Phase 3R5: one occurrence per origin per Edition.
    case forbidden
    /// An edited article (materially different title or text) is published again as a new card.
    case whenMaterialChanged
}

public struct PublicationReceipt: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let segmentID: FeedSegmentID
    public let segmentOrdinal: UInt64
    public let cardIDs: [PublicationCardID]
}

public enum PublicationOutcome: Hashable, Sendable {
    case nothingToPublish
    case published(PublicationReceipt)
}

public struct PublicationCoordinator: Sendable {
    private let store: PublicationStore
    /// Optional evidence of the replenishment attempt a publication concludes; nil records nothing.
    private let trace: ReplenishmentTrace?
    public init(database: RuntimeDatabase, trace: ReplenishmentTrace? = nil) {
        self.store = PublicationStore(database: database)
        self.trace = trace
    }

    public struct CreateRequest: Sendable {
        public let selection: SelectionResult
        public let drafts: [PublicationCardDraft]
        public let editionID: FeedEditionID
        public let publicationSchemaVersion: PublicationSchemaVersion
        public let selectionSeed: UInt64
        public let editionCreatedAt: Date
        public let segmentID: FeedSegmentID
        public let segmentSeed: UInt64
        public let segmentCreatedAt: Date
        public let cardIDs: [PublicationCardID]
        public let expectedSourceExclusions: ReaderSourceExclusionSnapshot?
        public let expectedWordExclusions: ReaderWordExclusionSnapshot?
        public let bindingPublication: PublicationStore.BindingPublicationExpectation?

        public init(selection: SelectionResult, drafts: [PublicationCardDraft], editionID: FeedEditionID, publicationSchemaVersion: PublicationSchemaVersion, selectionSeed: UInt64, editionCreatedAt: Date, segmentID: FeedSegmentID, segmentSeed: UInt64, segmentCreatedAt: Date, cardIDs: [PublicationCardID]) {
            self.init(selection: selection, drafts: drafts, editionID: editionID,
                publicationSchemaVersion: publicationSchemaVersion, selectionSeed: selectionSeed,
                editionCreatedAt: editionCreatedAt, segmentID: segmentID, segmentSeed: segmentSeed,
                segmentCreatedAt: segmentCreatedAt, cardIDs: cardIDs, expectedSourceExclusions: nil)
        }

        public init(selection: SelectionResult, drafts: [PublicationCardDraft], editionID: FeedEditionID,
            publicationSchemaVersion: PublicationSchemaVersion, selectionSeed: UInt64, editionCreatedAt: Date,
            segmentID: FeedSegmentID, segmentSeed: UInt64, segmentCreatedAt: Date, cardIDs: [PublicationCardID],
            expectedSourceExclusions: ReaderSourceExclusionSnapshot?,
            expectedWordExclusions: ReaderWordExclusionSnapshot? = nil,
            bindingPublication: PublicationStore.BindingPublicationExpectation? = nil) {
            self.expectedSourceExclusions = expectedSourceExclusions
            self.expectedWordExclusions = expectedWordExclusions
            self.bindingPublication = bindingPublication
            self.selection = selection
            self.drafts = drafts
            self.editionID = editionID
            self.publicationSchemaVersion = publicationSchemaVersion
            self.selectionSeed = selectionSeed
            self.editionCreatedAt = editionCreatedAt
            self.segmentID = segmentID
            self.segmentSeed = segmentSeed
            self.segmentCreatedAt = segmentCreatedAt
            self.cardIDs = cardIDs
        }
    }

    public struct InitialCreateRequest: Sendable {
        public let publication: CreateRequest
        public let anchorPlacement: AnchorPlacement
        public let checkpointedAt: Date

        public init(publication: CreateRequest, anchorPlacement: AnchorPlacement, checkpointedAt: Date) {
            self.publication = publication
            self.anchorPlacement = anchorPlacement
            self.checkpointedAt = checkpointedAt
        }
    }

    public struct AppendRequest: Sendable {
        public let selection: SelectionResult
        public let drafts: [PublicationCardDraft]
        public let editionID: FeedEditionID
        public let segmentID: FeedSegmentID
        public let segmentSeed: UInt64
        public let segmentCreatedAt: Date
        public let cardIDs: [PublicationCardID]
        /// PD-1: whether an already-published origin may occur again with materially new text.
        public let originRecurrence: PublicationOriginRecurrence
        /// The replenishment attempt this publication concludes, when a host decided one; nil for work that is not
        /// a replenishment (the first Edition).
        public let operation: FeedReplenishmentOperationID?
        public let expectedSourceExclusions: ReaderSourceExclusionSnapshot?
        public let expectedWordExclusions: ReaderWordExclusionSnapshot?
        public let bindingActivation: SessionStore.BindingActivation?

        public init(selection: SelectionResult, drafts: [PublicationCardDraft], editionID: FeedEditionID, segmentID: FeedSegmentID, segmentSeed: UInt64, segmentCreatedAt: Date, cardIDs: [PublicationCardID],
            originRecurrence: PublicationOriginRecurrence = .forbidden,
            operation: FeedReplenishmentOperationID? = nil) {
            self.init(selection: selection, drafts: drafts, editionID: editionID, segmentID: segmentID,
                segmentSeed: segmentSeed, segmentCreatedAt: segmentCreatedAt, cardIDs: cardIDs,
                originRecurrence: originRecurrence, operation: operation, expectedSourceExclusions: nil)
        }

        public init(selection: SelectionResult, drafts: [PublicationCardDraft], editionID: FeedEditionID,
            segmentID: FeedSegmentID, segmentSeed: UInt64, segmentCreatedAt: Date, cardIDs: [PublicationCardID],
            originRecurrence: PublicationOriginRecurrence = .forbidden,
            operation: FeedReplenishmentOperationID? = nil,
            expectedSourceExclusions: ReaderSourceExclusionSnapshot?,
            expectedWordExclusions: ReaderWordExclusionSnapshot? = nil,
            bindingActivation: SessionStore.BindingActivation? = nil) {
            self.expectedSourceExclusions = expectedSourceExclusions
            self.expectedWordExclusions = expectedWordExclusions
            self.bindingActivation = bindingActivation
            self.operation = operation
            self.selection = selection
            self.drafts = drafts
            self.editionID = editionID
            self.segmentID = segmentID
            self.segmentSeed = segmentSeed
            self.segmentCreatedAt = segmentCreatedAt
            self.cardIDs = cardIDs
            self.originRecurrence = originRecurrence
        }
    }

    public func createEdition(_ request: CreateRequest) throws -> PublicationOutcome {
        guard let records = try Self.firstPublication(request) else { return .nothingToPublish }
        try store.createEdition(records.0, firstSegment: records.1, cards: records.2,
            expectedSourceExclusions: request.expectedSourceExclusions, expectedWordExclusions: request.expectedWordExclusions, bindingPublication: request.bindingPublication)
        return .published(Self.initialReceipt(request))
    }

    public func createInitialEdition(_ request: InitialCreateRequest) throws -> PublicationOutcome {
        let publication = request.publication
        guard let records = try Self.firstPublication(publication) else { return .nothingToPublish }
        let cursor = SessionCursor(editionID: publication.editionID,
            anchor: FeedWindowAnchor(cardID: publication.cardIDs[0], placement: request.anchorPlacement))
        try store.createInitialEdition(records.0, firstSegment: records.1, cards: records.2,
            initialCheckpoint: PublicationPersistenceMapping.checkpoint(cursor, updatedAt: request.checkpointedAt),
            expectedSourceExclusions: publication.expectedSourceExclusions, expectedWordExclusions: publication.expectedWordExclusions, bindingPublication: publication.bindingPublication)
        return .published(Self.initialReceipt(publication))
    }

    private static func initialReceipt(_ request: CreateRequest) -> PublicationReceipt {
        PublicationReceipt(editionID: request.editionID, segmentID: request.segmentID,
            segmentOrdinal: 0, cardIDs: request.cardIDs)
    }

    private static func firstPublication(_ request: CreateRequest) throws ->
        (PublicationStore.EditionRecord, PublicationStore.SegmentRecord, [PublicationStore.CardRecord])? {
        let cards = try Self.prepareCards(selection: request.selection, drafts: request.drafts, cardIDs: request.cardIDs)
        guard !cards.isEmpty else { return nil }
        let edition = FeedEdition(id: request.editionID, editorialRevision: request.selection.editorialRevision,
            publicationSchemaVersion: request.publicationSchemaVersion, selectionSeed: request.selectionSeed,
            createdAt: request.editionCreatedAt)
        guard let segment = FeedSegment(id: request.segmentID, editionID: request.editionID, ordinal: 0,
            segmentSeed: request.segmentSeed, publicationSchemaVersion: request.publicationSchemaVersion,
            createdAt: request.segmentCreatedAt, cardIDs: request.cardIDs) else {
            throw PublicationCoordinatorError.inputCountMismatch
        }
        let records = try PublicationPersistenceMapping.records(segment: segment, cards: cards)
        return (try PublicationPersistenceMapping.record(edition), records.0, records.1)
    }

    public func append(_ request: AppendRequest) throws -> PublicationOutcome {
        try append(request, expectedTail: nil)
    }

    public func append(_ request: AppendRequest,
        expectingTailCardID: PublicationCardID) throws -> PublicationOutcome {
        try append(request, expectedTail: expectingTailCardID)
    }

    private func append(_ request: AppendRequest, expectedTail: PublicationCardID?) throws -> PublicationOutcome {
        let cards = try Self.prepareCards(selection: request.selection, drafts: request.drafts, cardIDs: request.cardIDs)
        guard !cards.isEmpty else { return .nothingToPublish }
        guard let record = try store.edition(id: request.editionID) else { throw PublicationCoordinatorError.missingEdition }
        let edition = try PublicationPersistenceMapping.edition(record)
        guard edition.editorialRevision == request.selection.editorialRevision else {
            throw PublicationCoordinatorError.editorialRevisionMismatch
        }
        let tail = try store.tail(editionID: request.editionID)
        let ordinal = tail.ordinal + 1
        guard let segment = FeedSegment(id: request.segmentID, editionID: request.editionID, ordinal: ordinal,
            segmentSeed: request.segmentSeed, publicationSchemaVersion: edition.publicationSchemaVersion,
            createdAt: request.segmentCreatedAt, cardIDs: request.cardIDs) else {
            throw PublicationCoordinatorError.inputCountMismatch
        }
        let records = try PublicationPersistenceMapping.records(segment: segment, cards: cards)
        let recurrence: PublicationStore.OriginRecurrenceRecord
        switch request.originRecurrence {
        case .forbidden: recurrence = .forbidden
        case .whenMaterialChanged: recurrence = .whenMaterialChanged
        }
        if let expectedTail {
            try store.appendSegment(records.0, cards: records.1, expectingTailCardID: expectedTail, recurrence: recurrence,
                expectedSourceExclusions: request.expectedSourceExclusions, expectedWordExclusions: request.expectedWordExclusions, bindingActivation: request.bindingActivation)
        } else {
            guard recurrence == .forbidden else { throw PublicationCoordinatorError.recurrenceRequiresTailExpectation }
            try store.appendSegment(records.0, cards: records.1,
                expectedSourceExclusions: request.expectedSourceExclusions, expectedWordExclusions: request.expectedWordExclusions, bindingActivation: request.bindingActivation)
        }
        let receipt = PublicationReceipt(editionID: request.editionID, segmentID: request.segmentID,
            segmentOrdinal: ordinal, cardIDs: request.cardIDs)
        // The destination, named: a segment is now frozen in history. This is **not** the same event as the host
        // installing an offer — `admitted` records that, and the card ids here are what lets the two be joined.
        if let operation = request.operation, let trace {
            trace.record(ReplenishmentEvent.concluded, ["op": operation.described,
                "destination": "segment_publication", "edition": receipt.editionID.rawValue.uuidString,
                "segment": receipt.segmentID.rawValue.uuidString, "ordinal": String(receipt.segmentOrdinal),
                "cards": String(receipt.cardIDs.count),
                "head": receipt.cardIDs.first?.rawValue.uuidString ?? "",
                "tail": receipt.cardIDs.last?.rawValue.uuidString ?? ""])
        }
        return .published(receipt)
    }

    private static func prepareCards(selection: SelectionResult, drafts: [PublicationCardDraft],
        cardIDs: [PublicationCardID]) throws -> [PublishedCard] {
        guard selection.orderedCandidates.count == drafts.count, drafts.count == cardIDs.count else {
            throw PublicationCoordinatorError.inputCountMismatch
        }
        guard !drafts.isEmpty else { return [] }
        guard Set(cardIDs).count == cardIDs.count else { throw PublicationCoordinatorError.duplicatePublicationCardID }
        return try drafts.enumerated().map { index, draft in
            let candidate = selection.orderedCandidates[index]
            let kind: PublishedTimestampKind
            switch candidate.timestamp.kind {
            case .authored: kind = .authored
            case .observed: kind = .observed
            }
            guard draft.origin.originRecordID == candidate.originRecordID,
                draft.origin.originRevisionID == candidate.originRevisionID,
                draft.origin.providerID == candidate.providerID,
                exactText(draft.text.title, candidate.headline), exactText(draft.text.primaryText, candidate.summary),
                draft.timestamp == PublishedTimestamp(value: candidate.timestamp.value, kind: kind) else {
                throw PublicationCoordinatorError.draftCandidateMismatch(index: index)
            }
            guard let card = PublishedCard(id: cardIDs[index], origin: draft.origin,
                contentEntityID: draft.contentEntityID, contentClusterID: draft.contentClusterID,
                text: draft.text, timestamp: draft.timestamp, media: draft.media,
                renderContract: draft.renderContract, primaryAction: draft.primaryAction,
                mediaIdentity: draft.mediaIdentity, diversity: draft.diversity) else {
                throw PublicationCoordinatorError.invalidPreparedCard(index: index)
            }
            return card
        }
    }

    private static func exactText(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (.some(let a), .some(let b)): return a.utf8.elementsEqual(b.utf8)
        default: return false
        }
    }
}
