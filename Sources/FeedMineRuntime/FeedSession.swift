// File: FeedSession.swift
// Module: FeedMineRuntime
// Owns: current local state, the admitted reader list and explicit checkpoints.
// Does not own: direct storage, publication, acquisition or UI layout.

import Foundation
import FeedMineDomain
import FeedMinePublication

public actor FeedSession {
    private let publicationHistory: PublicationHistory
    private let imageDecoder: PresentationImageDecoder?
    private var state: FeedSessionState?
    private var hasAdmittedInitial = false
    /// Cards whose decoded pixels were released to bound residency. They are re-decoded from the same
    /// local asset when the reader comes back to them; their frozen descriptor never changed.
    private var releasedImageCards: Set<PublicationCardID> = []
    private let projectionSequenceID = UUID()
    private var projectionPosition: UInt64 = 0

    /// Composition-only exception: accepts the semantic Publication boundary.
    /// UI consumes Runtime presentation results without importing Publication.
    /// With a decoder, projected cards carry slot-sized local images; without one they render placeholders.
    public init(publicationHistory: PublicationHistory, imageDecoder: PresentationImageDecoder? = nil) {
        self.publicationHistory = publicationHistory
        self.imageDecoder = imageDecoder
    }

    public func currentPresentation() -> FeedPresentationSnapshot? {
        state?.presentation
    }

    public func currentRunwayScope() -> RunwayScope? {
        guard let current = state else { return nil }
        return RunwayScope(editionID: current.presentation.editionID, contextKey: current.presentation.contextKey,
            editorialRevisionID: current.editorialRevisionID)
    }

    /// The single entry point that may change what the reader sees.
    ///
    /// `.initial` installs the first presentation of this association exactly once; `.restore`
    /// recovers an association that has no presentation at all; `.forwardScroll` extends the
    /// admitted prefix after a real forward movement. Every case refuses to change an already
    /// admitted list, so background production can never extend the reader's view.
    public func admitPresentation(_ admission: FeedPresentationAdmission) throws -> FeedPresentationSnapshot? {
        switch admission {
        case .initial(let bounds):
            try validate(bounds)
            guard !hasAdmittedInitial, state == nil else { return currentPresentation() }
            guard let installed = try installFromCheckpoint(bounds) else { return nil }
            hasAdmittedInitial = true
            return installed
        case .restore(let bounds):
            try validate(bounds)
            guard state == nil else { return currentPresentation() }
            return try installFromCheckpoint(bounds)
        case .forwardScroll(let observation):
            return try admitForwardScroll(observation)
        }
    }

    /// Observes a reading position in the current snapshot, using retained history only.
    /// Recording an observation moves the logical anchor and marks exposure; it never extends
    /// or rebuilds the admitted list, which only `admitPresentation(.forwardScroll:)` may do.
    public func submitViewport(_ observation: ViewportObservation) throws -> FeedPresentationSnapshot? {
        guard let current = state else { return nil }
        let items = current.presentation.window.items
        guard items.contains(where: { $0.id == observation.anchor.cardID }) else { return current.presentation }
        try publicationHistory.markSeen(editionID: current.presentation.editionID, cardID: observation.anchor.cardID)
        let (bounded, residencyChanged) = try boundedResidency(items: items,
            editionID: current.presentation.editionID, around: observation.anchor.cardID, bounds: current.bounds)
        let anchorChanged = observation.anchor != current.presentation.window.anchor
        guard anchorChanged || residencyChanged else { return current.presentation }
        guard let window = FeedWindowSnapshot(items: bounded, anchor: observation.anchor) else { return current.presentation }
        let snapshot = try projectWindow(contextKey: current.presentation.contextKey,
            editionID: current.presentation.editionID, window: window)
        state = FeedSessionState(editorialRevisionID: current.editorialRevisionID, presentation: snapshot,
            bounds: current.bounds)
        return snapshot
    }

    /// Bounds decoded-image residency around the reader: only cards inside the frozen bounds keep their
    /// pixels; everything else keeps the frozen descriptor and releases the bitmap, which is decoded
    /// again from the same local asset when the reader returns. Returns the items and whether anything
    /// actually changed, so an unmoved window allocates nothing.
    private func boundedResidency(items: [PresentationCard], editionID: FeedEditionID,
        around anchorCardID: PublicationCardID, bounds: FeedPresentationBounds) throws -> ([PresentationCard], Bool) {
        guard let anchorIndex = items.firstIndex(where: { $0.id == anchorCardID }) else { return (items, false) }
        let first = max(0, anchorIndex - bounds.backwardCapacity)
        let last = min(items.count - 1, anchorIndex + bounds.forwardCapacity)
        let inside = first...last
        let wantsDecode = items[inside].contains { releasedImageCards.contains($0.id) }
        let wantsRelease = items.enumerated().contains { index, item in
            !inside.contains(index) && item.image != nil
        }
        guard wantsDecode || wantsRelease else { return (items, false) }
        var decoded: [PublicationCardID: PresentationCard] = [:]
        if wantsDecode, let imageDecoder {
            let published = try publicationHistory.window(editionID: editionID,
                around: FeedWindowAnchor(cardID: items[first].id, placement: .center),
                backwardCapacity: 0, forwardCapacity: last - first)
            for card in published.cards {
                decoded[card.id] = PresentationCard(publishedCard: card, decoder: imageDecoder)
            }
        }
        var nextReleased = releasedImageCards
        let rebalanced = items.enumerated().map { index, item -> PresentationCard in
            if inside.contains(index) {
                guard let fresh = decoded[item.id] else { return item }
                nextReleased.remove(item.id)
                return fresh
            }
            if item.image != nil { nextReleased.insert(item.id) }
            return item.releasingDecodedImage()
        }
        releasedImageCards = nextReleased
        return (rebalanced, true)
    }

    /// Extends the admitted prefix with already-published cards that follow the admitted tail.
    /// Earlier cards keep their identity, order and projection: nothing is inserted above the
    /// reader, so no existing content moves. When the ready prefix is exhausted the screen is
    /// preserved unchanged instead of being replaced by a loading state.
    ///
    /// The session enforces what only it can enforce: the observation must still be the reader's
    /// current anchor (an older gesture cannot reinstall a position a newer one already left), the
    /// append is ordered and deduplicated, and the batch is bounded by the frozen forward bound.
    /// *When* a gesture deserves an admission is the UI's demand decision, not a ratio here.
    private func admitForwardScroll(_ observation: ViewportObservation) throws -> FeedPresentationSnapshot? {
        guard let current = state else { return nil }
        guard current.presentation.window.anchor == observation.anchor else { return current.presentation }
        let items = current.presentation.window.items
        guard let tail = items.last else { return current.presentation }
        let published = try publicationHistory.window(editionID: current.presentation.editionID,
            around: FeedWindowAnchor(cardID: tail.id, placement: .center),
            backwardCapacity: 0, forwardCapacity: current.bounds.forwardCapacity)
        let admitted = Set(items.map(\.id))
        let extensionCards = published.cards.dropFirst().filter { !admitted.contains($0.id) }
            .prefix(current.bounds.forwardCapacity)
            .map { PresentationCard(publishedCard: $0, decoder: imageDecoder) }
        guard !extensionCards.isEmpty else { return current.presentation }
        let (bounded, _) = try boundedResidency(items: items + extensionCards,
            editionID: current.presentation.editionID, around: observation.anchor.cardID, bounds: current.bounds)
        guard let window = FeedWindowSnapshot(items: bounded, anchor: observation.anchor) else {
            return current.presentation
        }
        let snapshot = try projectWindow(contextKey: current.presentation.contextKey,
            editionID: current.presentation.editionID, window: window)
        state = FeedSessionState(editorialRevisionID: current.editorialRevisionID, presentation: snapshot,
            bounds: current.bounds)
        return snapshot
    }

    /// Rejects unusable structural bounds before any state is consulted, so a repeat admission
    /// cannot hide a caller's mistake behind the "already admitted" refusal.
    private func validate(_ bounds: FeedPresentationBounds) throws {
        guard bounds.backwardCapacity >= 0, bounds.forwardCapacity >= 0 else {
            throw FeedSessionError.invalidMaterializationBounds
        }
    }

    /// Reads the durable checkpoint and installs it as the admitted presentation.
    /// A failed read preserves existing state; no checkpoint clears local state.
    private func installFromCheckpoint(_ bounds: FeedPresentationBounds) throws -> FeedPresentationSnapshot? {
        guard let restored = try publicationHistory.restore(backwardCapacity: bounds.backwardCapacity,
            forwardCapacity: bounds.forwardCapacity, contextKey: bounds.contextKey) else {
            state = nil
            return nil
        }
        try publicationHistory.markSeen(editionID: restored.edition.id, cardID: restored.cursor.anchor.cardID)
        let current = state?.presentation
        let reusable = current.flatMap { snapshot in
            snapshot.contextKey == restored.edition.contextKey && snapshot.editionID == restored.edition.id
                ? Dictionary(uniqueKeysWithValues: snapshot.window.items.map { ($0.id, $0) }) : nil
        } ?? [:]
        let window = FeedWindowSnapshot(publishedWindow: restored.window, decoder: imageDecoder, reusable: reusable)
        let snapshot = try projectWindow(contextKey: restored.edition.contextKey,
            editionID: restored.edition.id, window: window)
        state = FeedSessionState(editorialRevisionID: restored.edition.editorialRevision.id,
            presentation: snapshot, bounds: bounds)
        return snapshot
    }

    /// Allocate only after a successful read, alongside the actor's synchronous state transition.
    /// An unchanged effective projection retains its exact provenance, even after another read.
    private func projectWindow(contextKey: ContextKey, editionID: FeedEditionID,
        window: FeedWindowSnapshot) throws -> FeedPresentationSnapshot {
        if let current = state?.presentation, current.contextKey == contextKey,
            current.editionID == editionID, current.window == window { return current }
        let next = try FeedProjectionProvenance.nextPosition(after: projectionPosition)
        let snapshot = FeedPresentationSnapshot(contextKey: contextKey, editionID: editionID, window: window,
            provenance: .init(sequenceID: projectionSequenceID, position: next))
        projectionPosition = next
        return snapshot
    }

    /// Makes the existing logical position durable without changing current presentation.
    /// The caller decides when a milestone occurs; date validation belongs to Persistence.
    public func checkpointCurrentPosition(at date: Date) throws -> Bool {
        guard let current = state else { return false }
        let placement: AnchorPlacement
        switch current.presentation.window.anchor.placement {
        case .top: placement = .top
        case .center: placement = .center
        }
        let anchor = FeedWindowAnchor(cardID: current.presentation.window.anchor.cardID, placement: placement)
        let cursor = SessionCursor(editionID: current.presentation.editionID, anchor: anchor)
        try publicationHistory.saveCursor(cursor, updatedAt: date)
        return true
    }
}
