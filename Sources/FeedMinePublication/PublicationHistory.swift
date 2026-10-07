// File: PublicationHistory.swift
// Module: FeedMinePublication
// Owns: semantic local history reads through private stores and internal mapping.
// Does not own: publication, checkpoint writes, retention or Runtime session state.

import FeedMineDomain
import FeedMinePersistence

public enum PublicationHistoryError: Error, Equatable, Sendable {
    case missingEdition
    case invalidWindow
    case inconsistentRestore
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

/// Read-only semantic boundary over already published local history.
/// Restore precedes active session mutation; no retention/delete API or background
/// deletion exists. Before concurrent retention, deletion or persisted session switching
/// during restore, reassess a single Persistence snapshot for checkpoint + Edition + window.
public struct PublicationHistory: Sendable {
    private let publicationStore: PublicationStore
    private let sessionStore: SessionStore

    public init(database: RuntimeDatabase) {
        publicationStore = PublicationStore(database: database)
        sessionStore = SessionStore(database: database)
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
