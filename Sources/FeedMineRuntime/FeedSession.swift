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
    private var lastRenderedViewportOrdinal: UInt64 = 0

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
        case .backwardScroll(let observation):
            return try admitBackwardScroll(observation)
        case .publishedGrowth:
            return try admitPublishedGrowth()
        }
    }

    /// Observes a reading position in the current snapshot, using retained history only.
    /// Recording an observation moves the logical anchor and marks exposure. Evidence of a still
    /// rendered previous window may rematerialize its already-admitted local IDs; it cannot
    /// publish or acquire content. Ordinary admission remains an explicit operation.
    public func submitViewport(_ observation: ViewportObservation, from evidence: RenderedViewportEvidence? = nil) throws -> FeedPresentationSnapshot? {
        guard let original = state else { return nil }
        if let evidence {
            guard evidence.observation == observation, evidence.belongs(to: original.presentation),
                evidence.ordinal > lastRenderedViewportOrdinal else { return nil }
            lastRenderedViewportOrdinal = evidence.ordinal
            if !original.presentation.window.items.contains(where: { $0.id == observation.anchor.cardID }) {
                // The reader is still looking at a previous presentation from this same association.
                // Re-read only locally published IDs already admitted by one of these two values.
                let allowed = Set(original.presentation.window.items.map(\.id) + evidence.admittedIDs)
                // Com a cabeça mantida, a releitura tem de alcançar **toda** carta já admitida; com a regra do
                // arquiteto basta a capacidade congelada. O filtro abaixo continua mantendo exatamente as
                // identidades admitidas, então alargar a leitura não admite nada de novo.
                let kept = original.bounds.keepsAdmittedHead ? allowed.count : original.bounds.backwardCapacity
                let history = try publicationHistory.window(editionID: original.presentation.editionID,
                    around: FeedWindowAnchor(cardID: observation.anchor.cardID, placement: .center),
                    backwardCapacity: kept,
                    forwardCapacity: original.bounds.forwardCapacity)
                let cards = history.cards.filter { allowed.contains($0.id) }
                    .map { PresentationCard(publishedCard: $0, decoder: imageDecoder) }
                guard let window = FeedWindowSnapshot(items: cards, anchor: observation.anchor) else { return nil }
                let restored = try projectWindow(contextKey: original.presentation.contextKey,
                    editionID: original.presentation.editionID, window: window)
                state = FeedSessionState(editorialRevisionID: original.editorialRevisionID,
                    presentation: restored, bounds: original.bounds)
            }
        }
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
        // O teto vale para a janela inteira, **nas duas direções** (decisão do arquiteto): crescer para frente sem
        // limite também é defeito. O corte é em volta da âncora, então ordem, identidade, âncora e posição ficam, e
        // as cartas cortadas seguem alcançáveis — a admissão seguinte as relê do store.
        let (bounded, _) = try boundedResidency(
            items: boundedToTotalWindow(items + extensionCards, around: observation.anchor.cardID,
                bounds: current.bounds),
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

    /// Keeps the admitted list bounded **around the anchor**: at most `backwardCapacity` cards before it and
    /// `forwardCapacity` after it, which is what the presentation was installed with. The architect separated the
    /// two claims and he is right: every admission obeying the bound *locally* does not bound the list — prepending
    /// pushes the anchor right, appending grows the tail, and over a long navigation either end accumulates. Cards
    /// cut here stay **reachable**: the next admission near that end reads them from the store again, so leaving the
    /// window is not losing the content. The anchor itself is never cut — it is inside `first...last` by construction.
    private func boundedToTotalWindow(_ items: [PresentationCard], around anchorCardID: PublicationCardID,
        bounds: FeedPresentationBounds) -> [PresentationCard] {
        guard let anchorIndex = items.firstIndex(where: { $0.id == anchorCardID }) else { return items }
        // Both directions by default; the **head is kept** when the presentation was installed that way (the
        // owner's experiment, 2026-10-13): nothing above the reader is removed, so a forward read never changes the
        // content above them and the offset corrector has nothing to hide. The forward reserve is bounded either way.
        let first = bounds.keepsAdmittedHead ? 0 : max(0, anchorIndex - bounds.backwardCapacity)
        let last = min(items.count - 1, anchorIndex + bounds.forwardCapacity)
        guard first > 0 || last < items.count - 1 else { return items }
        return Array(items[first...last])
    }

    /// Prepends already-published cards that precede the admitted head, after a real backward movement of the
    /// reader reached it. Mirror of `admitForwardScroll`: the observation must still be the reader's current anchor
    /// (an older gesture cannot reinstall a position a newer one already left), the prepend is ordered and
    /// deduplicated, and the batch is bounded by the frozen backward bound *around the anchor* — which is what makes
    /// a repeat a no-op and what keeps the admitted list's memory bounded by the bounds it was installed with.
    ///
    /// Nothing else moves: the anchor, the edition and every already-admitted card keep their identity and their
    /// order, so the reader's position does not jump when history appears above them. The cards come from the local
    /// store; the network is not consulted, which is what makes this work offline.
    private func admitBackwardScroll(_ observation: ViewportObservation) throws -> FeedPresentationSnapshot? {
        guard let current = state else { return nil }
        guard current.presentation.window.anchor == observation.anchor else { return current.presentation }
        let items = current.presentation.window.items
        guard let head = items.first,
            let anchorIndex = items.firstIndex(where: { $0.id == current.presentation.window.anchor.cardID })
        else { return current.presentation }
        // How many cards the frozen bounds still allow *before* the anchor: the admitted list is bounded around the
        // anchor, not by an ever-growing list. Zero means the reader is already as far back as this session admits.
        let allowed = max(0, current.bounds.backwardCapacity - anchorIndex)
        guard allowed > 0 else { return current.presentation }
        let published = try publicationHistory.window(editionID: current.presentation.editionID,
            around: FeedWindowAnchor(cardID: head.id, placement: .center),
            backwardCapacity: current.bounds.backwardCapacity, forwardCapacity: 0)
        let admitted = Set(items.map(\.id))
        // The read is centred on the head, so its last card *is* the head: the extension is what precedes it. Taking
        // the suffix keeps the cards closest to the head — the reader's next step back, not the far end of history.
        let extensionCards = published.cards.dropLast().filter { !admitted.contains($0.id) }
            .suffix(allowed)
            .map { PresentationCard(publishedCard: $0, decoder: imageDecoder) }
        guard !extensionCards.isEmpty else { return current.presentation }
        let (bounded, _) = try boundedResidency(
            items: boundedToTotalWindow(extensionCards + items, around: observation.anchor.cardID,
                bounds: current.bounds),
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

    /// Appends cards already published beyond the admitted tail, without any reader observation and
    /// without inventing one. Order, anchor and every already-admitted card are preserved; only the
    /// end of the list grows, bounded by the frozen forward capacity.
    private func admitPublishedGrowth() throws -> FeedPresentationSnapshot? {
        guard let current = state else { return nil }
        let items = current.presentation.window.items
        guard let tail = items.last,
            let anchorIndex = items.firstIndex(where: { $0.id == current.presentation.window.anchor.cardID }) else {
            return current.presentation
        }
        // The admitted list is bounded by the frozen bounds *around the anchor*: growth fills the reader's
        // forward window and never extends past it. That is also what makes a repeat growth a no-op — the
        // extension cannot walk the tail past the bound however often it runs (measured: an unbounded tail
        // walk grew a window past its own capacity and broke two composition tests).
        let allowed = anchorIndex + current.bounds.forwardCapacity + 1
        guard items.count < allowed else { return current.presentation }
        let published = try publicationHistory.window(editionID: current.presentation.editionID,
            around: FeedWindowAnchor(cardID: tail.id, placement: .center),
            backwardCapacity: 0, forwardCapacity: current.bounds.forwardCapacity)
        let admitted = Set(items.map(\.id))
        let extensionCards = published.cards.dropFirst().filter { !admitted.contains($0.id) }
            .prefix(allowed - items.count)
            .map { PresentationCard(publishedCard: $0, decoder: imageDecoder) }
        guard !extensionCards.isEmpty else { return current.presentation }
        let anchor = current.presentation.window.anchor
        // Mesma regra do arquiteto, e agora num lugar só: o teto vale para a janela inteira nas duas direções.
        let (bounded, _) = try boundedResidency(
            items: boundedToTotalWindow(items + extensionCards, around: anchor.cardID, bounds: current.bounds),
            editionID: current.presentation.editionID, around: anchor.cardID, bounds: current.bounds)
        guard let window = FeedWindowSnapshot(items: bounded, anchor: anchor) else {
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
