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

/// How a restore reached the reader's card. A position is the reader's, so it is never replaced silently: the one
/// case where the card itself is no longer published says so, with the card it lost and the neighbour it landed on.
public enum RestoredPosition: Hashable, Sendable {
    /// The card the reader left, restored exactly, in the Edition that card belongs to.
    case exact(PublicationCardID)
    /// The card was published and later archived, so it cannot be drawn. Its position is still known: the restore
    /// lands on the nearest surviving neighbour (the Edition's first card when nothing survived before it).
    case nearestNeighbour(withdrawn: PublicationCardID, landedOn: PublicationCardID)
    /// This database holds no trace of the card at all. Stated, never silent, and the landing is the Edition's
    /// first surviving card — the only position with any evidence behind it.
    case unknownCard(landedOn: PublicationCardID)

    public var landedOn: PublicationCardID {
        switch self {
        case .exact(let card): card
        case .nearestNeighbour(_, let landed): landed
        case .unknownCard(let landed): landed
        }
    }
}

/// Exact retained history and logical position, with no mechanical records exposed.
public struct RestoredPublication: Hashable, Sendable {
    public let edition: FeedEdition
    public let cursor: SessionCursor
    public let window: FeedWindow
    /// What the restore could honour of the durable statement, and what it landed on when it could not.
    public let position: RestoredPosition

    public init?(edition: FeedEdition, cursor: SessionCursor, window: FeedWindow,
        position: RestoredPosition) {
        guard edition.id == cursor.editionID,
            edition.id == window.editionID,
            cursor.anchor == window.anchor,
            position.landedOn == cursor.anchor.cardID else { return nil }
        self.edition = edition
        self.cursor = cursor
        self.window = window
        self.position = position
    }
}

/// Semantic boundary over retained local history and explicit session checkpoints.
/// Local operations are synchronous; no retention/delete API or background
/// deletion exists. Before concurrent retention, deletion or persisted session switching
/// during restore, reassess a single Persistence snapshot for checkpoint + Edition + window.
public struct PublicationHistory: Sendable {
    private let publicationStore: PublicationStore
    private let sessionStore: SessionStore
    private let bindingActivation: SessionStore.BindingActivation?

    public init(database: RuntimeDatabase, bindingActivation: SessionStore.BindingActivation? = nil) {
        publicationStore = PublicationStore(database: database)
        sessionStore = SessionStore(database: database)
        self.bindingActivation = bindingActivation
    }

    public func markSeen(editionID: FeedEditionID, cardID: PublicationCardID) throws {
        if let bindingActivation, try sessionStore.isPreparedBinding(bindingActivation) {
            try sessionStore.validateBinding(bindingActivation, editionID: editionID)
            return // A hidden replacement's projection is not a presented/seen event.
        }
        try publicationStore.markSeen(editionID: editionID, cardID: cardID, bindingActivation: bindingActivation)
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
    public func exposure(editionID: FeedEditionID, originIDs: [OriginRecordID],
        readerAnchorCardID: PublicationCardID? = nil) throws -> PublishedExposureFacts {
        guard Set(originIDs).count == originIDs.count else {
            throw PublicationHistoryError.invalidExposureRequest
        }
        let record = try publicationStore.exposure(editionID: editionID, originIDs: originIDs,
            readerAnchorCardID: readerAnchorCardID)
        return PublishedExposureFacts(editionID: editionID, observedTailCardID: record.observedTailCardID,
            requestedOriginIDs: originIDs, publishedOriginIDs: record.publishedOriginIDs,
            publishedMaterialKeys: record.publishedMaterialKeys, unseenOriginIDs: record.unseenOriginIDs)
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
    ///
    /// The window carries `backwardCapacity` cards behind the cursor: the bound of a presentation whose admitted
    /// list is bounded **around** the reader, where a card cut behind the anchor stays reachable because the next
    /// backward admission re-reads it from the local store.
    public func restore(backwardCapacity: Int, forwardCapacity: Int, contextKey: ContextKey? = nil) throws -> RestoredPublication? {
        try restore(contextKey: contextKey) { edition, anchor in
            try publicationStore.cards(editionID: edition.id, around: anchor.cardID,
                backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity)
        }
    }

    /// The same restore with the backward side **unbounded**: every card from the Edition's start up to the cursor,
    /// plus `forwardCapacity` cards after it.
    ///
    /// This is the shape a presentation installed with `keepsAdmittedHead` had while it ran — it held every card
    /// above the reader — so it is the shape a reopen must install. Restoring only a neighbourhood around the
    /// cursor drops cards the reader had already passed, and a card they saved above the cursor is not drawn at all
    /// (B05, 2026-10-14: the saved card sat 22 cards above the durable position and was absent after
    /// terminate+launch). The reach is the Edition itself: a cap below it would be the same defect for a reader who
    /// read past the cap, which is why there is none.
    public func restoreFromEditionStart(forwardCapacity: Int, contextKey: ContextKey? = nil) throws -> RestoredPublication? {
        try restore(contextKey: contextKey) { edition, anchor in
            try publicationStore.cards(editionID: edition.id, fromEditionStartTo: anchor.cardID,
                forwardCapacity: forwardCapacity)
        }
    }

    private func restore(contextKey: ContextKey?,
        read: (FeedEdition, FeedWindowAnchor) throws -> [PublicationStore.CardRecord]) throws -> RestoredPublication? {
        let saved = try readCheckpoint(contextKey: contextKey)
        guard let checkpoint = saved else { return nil }
        let (cursor, position) = try resolved(try PublicationPersistenceMapping.cursor(checkpoint))
        try validateBinding(editionID: cursor.editionID)
        guard let record = try publicationStore.edition(id: cursor.editionID) else {
            throw PublicationHistoryError.missingEdition
        }
        let edition = try PublicationPersistenceMapping.edition(record)
        let cards = try read(edition, cursor.anchor).map(PublicationPersistenceMapping.card)
        guard let window = FeedWindow(editionID: edition.id, cards: cards, anchor: cursor.anchor) else {
            throw PublicationHistoryError.invalidWindow
        }
        guard let restored = RestoredPublication(edition: edition, cursor: cursor, window: window,
            position: position) else {
            throw PublicationHistoryError.inconsistentRestore
        }
        try validateBinding(editionID: restored.edition.id)
        return restored
    }

    /// The reader's position resolved **by the durable card**, not by the Edition a record happens to spell.
    ///
    /// The card is the statement; the Edition column is where it was filed. A rebuild publishes a new Edition for
    /// the same context identity — and with it a new segment seed and a new pool — so that column can name an
    /// Edition whose segments never held the reader's card. Reading the window from it either throws
    /// (`anchor membership`) or drops the reader at the top of a layout that is not theirs (D10, 2026-10-20: audio
    /// sources in the discovery pool rebuilt the Edition and the reopen lost the anchor). So:
    ///
    /// - the card's own Edition is the one the window is read from, whatever the record says;
    /// - a card that was published and archived lands on its nearest surviving neighbour, and says so;
    /// - a card this database never held is stated, and lands on the Edition's first surviving card.
    private func resolved(_ stored: SessionCursor) throws -> (SessionCursor, RestoredPosition) {
        let placement = stored.anchor.placement
        func cursor(edition: FeedEditionID, card: PublicationCardID,
            progress: CardTopOffset?) -> SessionCursor {
            SessionCursor(editionID: edition, anchor: FeedWindowAnchor(cardID: card, placement: placement),
                progress: progress)
        }
        if let located = try publicationStore.location(ofCard: stored.anchor.cardID) {
            if located.isLive {
                // The relative point belongs to this exact card; it is carried only with `.exact`.
                return (cursor(edition: located.editionID, card: located.cardID, progress: stored.progress),
                    .exact(located.cardID))
            }
            if let surviving = try publicationStore.survivingCard(inEdition: located.editionID,
                beforeSegment: located.segmentOrdinal, cardOrdinal: located.cardOrdinal) {
                // A different card has no relative point: applying the original delta to the neighbour would
                // name a position the reader never held. The checkpoint keeps its own value; this restore is
                // approximate and states it.
                return (cursor(edition: located.editionID, card: surviving, progress: nil),
                    .nearestNeighbour(withdrawn: located.cardID, landedOn: surviving))
            }
        }
        guard let surviving = try publicationStore.firstCard(inEdition: stored.editionID) else {
            throw PublicationHistoryError.missingEdition
        }
        return (cursor(edition: stored.editionID, card: surviving, progress: nil),
            .unknownCard(landedOn: surviving))
    }

    /// P10/R17: the facts the publication froze for this Edition, newest first. The editorial context reads history,
    /// never canonical supply.
    public func recentDiversity(editionID: FeedEditionID, limit: Int) throws -> [EditorialDiversityFact] {
        try publicationStore.recentDiversity(editionID: editionID, limit: limit)
    }

    /// v6: complete active-Edition positions, newest first, with nil holes preserved.
    public func diversityPositions(editionID: FeedEditionID) throws -> [EditorialDiversityFact?] {
        try publicationStore.diversityPositions(editionID: editionID)
    }

    /// Persists a logical cursor for an explicit session checkpoint milestone.
    public func saveCursor(_ cursor: SessionCursor, updatedAt: Date) throws {
        try sessionStore.saveCheckpoint(PublicationPersistenceMapping.checkpoint(cursor, updatedAt: updatedAt),
            bindingActivation: bindingActivation)
    }

    /// The durable cursor a restore would read for this identity — nothing more: no Edition lookup, no window and no
    /// card materialization. It is the record the conditional durability write compares its own statement against
    /// (`FeedSession`), so what that rule protects is exactly what a reopen would honour.
    /// Nil means no saved session. Storage and mapping failures propagate unchanged.
    public func savedCursor(contextKey: ContextKey? = nil) throws -> SessionCursor? {
        guard let checkpoint = try readCheckpoint(contextKey: contextKey)
        else { return nil }
        return try PublicationPersistenceMapping.cursor(checkpoint)
    }

    private func readCheckpoint(contextKey: ContextKey?) throws -> SessionStore.CheckpointRecord? {
        if let bindingActivation {
            return try sessionStore.checkpoint(bindingActivation: bindingActivation, contextKey: contextKey)
        }
        return try contextKey.map { try sessionStore.checkpoint(for: $0) } ?? sessionStore.checkpoint()
    }

    private func validateBinding(editionID: FeedEditionID) throws {
        if let bindingActivation { try sessionStore.validateBinding(bindingActivation, editionID: editionID) }
    }

    /// Materializes another immutable projection without changing the durable checkpoint.
    /// Capacity validation belongs to PublicationStore.
    public func window(
        editionID: FeedEditionID,
        around anchor: FeedWindowAnchor,
        backwardCapacity: Int,
        forwardCapacity: Int
    ) throws -> FeedWindow {
        try validateBinding(editionID: editionID)
        let records = try publicationStore.cards(editionID: editionID, around: anchor.cardID,
            backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity)
        let cards = try records.map(PublicationPersistenceMapping.card)
        guard let window = FeedWindow(editionID: editionID, cards: cards, anchor: anchor) else {
            throw PublicationHistoryError.invalidWindow
        }
        try validateBinding(editionID: editionID)
        return window
    }
}
