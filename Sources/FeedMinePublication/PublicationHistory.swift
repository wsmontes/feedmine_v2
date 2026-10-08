// File: PublicationHistory.swift
// Module: FeedMinePublication
// Owns: retained semantic history and explicit logical cursor durability boundary.
// Does not own: publication, retention or Runtime session state.

import Foundation
import FeedMineDomain
import FeedMinePersistence

public enum PublicationHistoryError: Error, Equatable, Sendable {
    case missingEdition
    case invalidWindow
    case inconsistentRestore
    case invalidExposureRequest
}

/// Exact retained history and logical position, with no mechanical records exposed.
public struct RestoredPublication: Hashable, Sendable {
    public let edition: FeedEdition
    public let cursor: SessionCursor
    public let window: FeedWindow

    public init?(edition: FeedEdition, cursor: SessionCursor, window: FeedWindow) {
        guard edition.id == cursor.editionID,
            edition.id == window.editionID,
            cursor.anchor == window.anchor else { return nil }
        self.edition = edition
        self.cursor = cursor
        self.window = window
    }
}

/// Semantic boundary over retained local history and explicit session checkpoints.
/// Local operations are synchronous; no retention/delete API or background
/// deletion exists. Before concurrent retention, deletion or persisted session switching
/// during restore, reassess a single Persistence snapshot for checkpoint + Edition + window.
public struct PublicationHistory: Sendable {
    private let publicationStore: PublicationStore
    private let sessionStore: SessionStore

    public init(database: RuntimeDatabase) {
        publicationStore = PublicationStore(database: database)
        sessionStore = SessionStore(database: database)
    }

    /// Committed ready-ahead history, independent of presentation window capacities.
    public func readyAhead(editionID: FeedEditionID, anchorCardID: PublicationCardID,
        probeBound: Int) throws -> ReadyAheadFacts {
        let record = try publicationStore.readyAhead(editionID: editionID,
            anchorCardID: anchorCardID, probeBound: probeBound)
        let amount: ReadyAheadAmount
        switch record.amount {
        case .exact(let count): amount = .exact(count)
        case .atLeast(let bound): amount = .atLeast(bound)
        }
        return ReadyAheadFacts(editionID: record.editionID, anchorCardID: record.anchorCardID,
            observedTailCardID: record.observedTailCardID, amount: amount)
    }

    /// History presence only; Editorial decides what to exclude in a future gate.
    public func exposure(editionID: FeedEditionID,
        revisionIDs: [OriginRevisionID]) throws -> PublishedExposureFacts {
        guard Set(revisionIDs).count == revisionIDs.count else {
            throw PublicationHistoryError.invalidExposureRequest
        }
        let published = try publicationStore.publishedRevisionIDs(editionID: editionID, revisionIDs: revisionIDs)
        return PublishedExposureFacts(editionID: editionID,
            requestedRevisionIDs: revisionIDs, publishedRevisionIDs: published)
    }

    public func forwardAdvance(editionID: FeedEditionID, fromCardID: PublicationCardID,
        toCardID: PublicationCardID, probeBound: Int) throws -> PublicationAdvanceFacts {
        let record = try publicationStore.forwardAdvance(editionID: editionID,
            fromCardID: fromCardID, toCardID: toCardID, probeBound: probeBound)
        let advance: PublicationAdvance
        switch record {
        case .same: advance = .same
        case .backward: advance = .backward
        case .forwardExact(let count): advance = .forwardExact(count)
        case .forwardBeyondProbe(let bound): advance = .forwardBeyondProbe(bound)
        }
        return PublicationAdvanceFacts(editionID: editionID, fromCardID: fromCardID,
            toCardID: toCardID, advance: advance)
    }

    /// Nil means no saved session. Storage and mapping failures propagate unchanged.
    public func restore(backwardCapacity: Int, forwardCapacity: Int) throws -> RestoredPublication? {
        guard let checkpoint = try sessionStore.checkpoint() else { return nil }
        let cursor = try PublicationPersistenceMapping.cursor(checkpoint)
        guard let record = try publicationStore.edition(id: cursor.editionID) else {
            throw PublicationHistoryError.missingEdition
        }
        let edition = try PublicationPersistenceMapping.edition(record)
        let window = try window(editionID: edition.id, around: cursor.anchor,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity)
        guard let restored = RestoredPublication(edition: edition, cursor: cursor, window: window) else {
            throw PublicationHistoryError.inconsistentRestore
        }
        return restored
    }

    /// Persists a logical cursor for an explicit session checkpoint milestone.
    public func saveCursor(_ cursor: SessionCursor, updatedAt: Date) throws {
        try sessionStore.saveCheckpoint(PublicationPersistenceMapping.checkpoint(cursor, updatedAt: updatedAt))
    }

    /// Materializes another immutable projection without changing the durable checkpoint.
    /// Capacity validation belongs to PublicationStore.
    public func window(
        editionID: FeedEditionID,
        around anchor: FeedWindowAnchor,
        backwardCapacity: Int,
        forwardCapacity: Int
    ) throws -> FeedWindow {
        let records = try publicationStore.cards(editionID: editionID, around: anchor.cardID,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity)
        let cards = try records.map(PublicationPersistenceMapping.card)
        guard let window = FeedWindow(editionID: editionID, cards: cards, anchor: anchor) else {
            throw PublicationHistoryError.invalidWindow
        }
        return window
    }
}
