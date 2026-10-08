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
    public init(database: RuntimeDatabase) { self.store = PublicationStore(database: database) }

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

        public init(selection: SelectionResult, drafts: [PublicationCardDraft], editionID: FeedEditionID, publicationSchemaVersion: PublicationSchemaVersion, selectionSeed: UInt64, editionCreatedAt: Date, segmentID: FeedSegmentID, segmentSeed: UInt64, segmentCreatedAt: Date, cardIDs: [PublicationCardID]) {
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

    public struct AppendRequest: Sendable {
        public let selection: SelectionResult
        public let drafts: [PublicationCardDraft]
        public let editionID: FeedEditionID
        public let segmentID: FeedSegmentID
        public let segmentSeed: UInt64
        public let segmentCreatedAt: Date
        public let cardIDs: [PublicationCardID]

        public init(selection: SelectionResult, drafts: [PublicationCardDraft], editionID: FeedEditionID, segmentID: FeedSegmentID, segmentSeed: UInt64, segmentCreatedAt: Date, cardIDs: [PublicationCardID]) {
            self.selection = selection
            self.drafts = drafts
            self.editionID = editionID
            self.segmentID = segmentID
            self.segmentSeed = segmentSeed
            self.segmentCreatedAt = segmentCreatedAt
            self.cardIDs = cardIDs
        }
    }

    public func createEdition(_ request: CreateRequest) throws -> PublicationOutcome {
        let cards = try Self.prepareCards(selection: request.selection, drafts: request.drafts, cardIDs: request.cardIDs)
        guard !cards.isEmpty else { return .nothingToPublish }
        let edition = FeedEdition(id: request.editionID, editorialRevision: request.selection.editorialRevision,
            publicationSchemaVersion: request.publicationSchemaVersion, selectionSeed: request.selectionSeed,
            createdAt: request.editionCreatedAt)
        guard let segment = FeedSegment(id: request.segmentID, editionID: request.editionID, ordinal: 0,
            segmentSeed: request.segmentSeed, publicationSchemaVersion: request.publicationSchemaVersion,
            createdAt: request.segmentCreatedAt, cardIDs: request.cardIDs) else {
            throw PublicationCoordinatorError.inputCountMismatch
        }
        let records = try PublicationPersistenceMapping.records(segment: segment, cards: cards)
        try store.createEdition(PublicationPersistenceMapping.record(edition), firstSegment: records.0, cards: records.1)
        return .published(PublicationReceipt(editionID: request.editionID, segmentID: request.segmentID,
            segmentOrdinal: 0, cardIDs: request.cardIDs))
    }

    public func append(_ request: AppendRequest) throws -> PublicationOutcome {
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
        try store.appendSegment(records.0, cards: records.1)
        return .published(PublicationReceipt(editionID: request.editionID, segmentID: request.segmentID,
            segmentOrdinal: ordinal, cardIDs: request.cardIDs))
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
                renderContract: draft.renderContract, primaryAction: draft.primaryAction) else {
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
