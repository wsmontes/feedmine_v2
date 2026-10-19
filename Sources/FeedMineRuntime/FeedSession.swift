// File: FeedSession.swift
// Module: FeedMineRuntime
// Owns: current local state, the admitted reader list and explicit checkpoints.
// Does not own: direct storage, publication, acquisition or UI layout.

import Foundation
import FeedMineDomain
import FeedMinePublication

/// What one debounced durability attempt did. The outcomes are deliberately not a boolean: "there was nothing to
/// record", "the durable cursor already holds this position" and "the reader moved inside the declared window" are
/// three different facts, and the run's own record has to be able to state which one happened (PO 2026-10-14).
public enum SettledPositionRecording: Hashable, Sendable {
    /// No admitted presentation: no position exists to record.
    case nothingToRecord
    /// The durable cursor already holds exactly this position, so no write was made — even past the window.
    case alreadyDurable
    /// The reader moved, but the declared window has not passed; the write waits `remaining` seconds.
    case withinWindow(remaining: TimeInterval)
    /// Written: the durable cursor now holds this card and placement, under this context's own identity.
    case written(cardID: PublicationCardID, placement: PresentationAnchorPlacement)
    /// The statement was **incomplete** — the window's anchor, the card the reader is *on* — and the durable record
    /// is **exact** (the card the viewport starts at, `.top`, same Edition): nothing was written and the exact
    /// record stands (lead, 2026-10-14). `cardID` is what the record holds.
    case keptExactRecord(cardID: PublicationCardID)
}

public actor FeedSession {
    private let publicationHistory: PublicationHistory
    private let imageDecoder: PresentationImageDecoder?
    private var state: FeedSessionState?
    private var hasAdmittedInitial = false
    /// Cards whose decoded pixels were released to bound residency. They are re-decoded from the same
    /// local asset when the reader comes back to them; their frozen descriptor never changed.
    private var releasedImageCards: Set<PublicationCardID> = []
    /// R03: cards whose bitmap was released and whose reconstruction failed because the local asset is gone. They
    /// keep their admitted identity, order, anchor and frozen geometry (the published placeholder), and they are not
    /// retried on every observation: the unavailable destination is stated once, not spun on.
    private var unrecoverableImageCards: Set<PublicationCardID> = []
    /// R03: the anchor of the last residency decision. Its band is kept alive with the current one, because the
    /// surface reveals the region the reader was **just** looking at before the runtime receives the next
    /// observation — releasing it there is an empty slot at the instant of exposure. Bounded: at most two bands.
    private var previousResidencyAnchor: PublicationCardID?
    /// The projection sequence this actor publishes under. It is fixed for the life of a session — a screen
    /// refuses a projection from another sequence — so a warm start that projected the reader's own window
    /// **before** this actor existed hands its sequence here rather than letting a second one begin.
    private var projectionSequenceID = UUID()
    private var projectionPosition: UInt64 = 0
    private var lastRenderedViewportOrdinal: UInt64 = 0
    /// What this association last made durable: the anchor the record holds and when it was written. It is the
    /// debounce's whole state — one rule, one owner, no timer and no second clock (PO 2026-10-14).
    private var durablePosition: (anchor: FeedWindowAnchor, at: Date)?
    /// Where the app says the reader's **rendered** viewport starts (see `notePresentedPosition(_:atRest:)`): the
    /// card the screen begins at, not the card the reader's observation anchors on. Memory-local until a rest makes
    /// it durable, and never a second presentation: it names one card and one placement, and a card the admitted
    /// window does not hold is ignored at the only place it is ever read.
    private var presentedPosition: PresentationAnchor?

    /// Composition-only exception: accepts the semantic Publication boundary.
    /// UI consumes Runtime presentation results without importing Publication.
    /// With a decoder, projected cards carry slot-sized local images. An image card whose pixels cannot be decoded —
    /// bytes absent or corrupt, or a composition built without a decoder — is admitted as a declared `.textOnly`
    /// card; it never crosses the boundary as an image slot waiting for bytes.
    ///
    /// `warmStart` is a window already read and projected from this context's durable checkpoint by
    /// `FeedSession.warmStart(...)`, for a host that must have the reader's own feed **before its first frame**
    /// (INV-07: a warm launch is local). The session adopts it as the state `.initial` would have installed — the
    /// same proposition, the same projection sequence, the same released pixels — so nothing is read twice and a
    /// later `.initial` admission returns exactly this window instead of restoring a second one.
    public init(publicationHistory: PublicationHistory, imageDecoder: PresentationImageDecoder? = nil,
        warmStart: WarmStart? = nil) {
        self.publicationHistory = publicationHistory
        self.imageDecoder = imageDecoder
        guard let warmStart else { return }
        state = warmStart.projection.state
        releasedImageCards = warmStart.projection.releasedImageCards
        previousResidencyAnchor = warmStart.projection.snapshot.window.anchor.cardID
        projectionSequenceID = warmStart.projection.sequenceID
        projectionPosition = warmStart.projection.position
        // The window is admitted: `.initial` is the admission that installs a session's first presentation once,
        // and this is that admission, made before the actor existed.
        hasAdmittedInitial = true
    }

    /// The reader's own window, projected from this context's durable checkpoint **without the actor** — the same
    /// projection `.initial`/`.restore` perform (one implementation, `FeedCheckpointProjection`), so a warm start
    /// cannot disagree with the restore a later admission would do.
    ///
    /// A host takes it when the previous interaction left something durable, and hands it straight back to the
    /// session it builds (`init(..., warmStart:)`). Nil means this context has no checkpoint: a cold launch, where
    /// the preparation surface is the honest thing to show and this value has nothing to say.
    public struct WarmStart: Sendable {
        /// The reader's own window, as the launch draws it.
        public let snapshot: FeedPresentationSnapshot
        let projection: FeedCheckpointProjection
    }

    public static func warmStart(publicationHistory: PublicationHistory,
        imageDecoder: PresentationImageDecoder?, bounds: FeedPresentationBounds) throws -> WarmStart? {
        guard let projection = try FeedCheckpointProjection.read(publicationHistory: publicationHistory,
            imageDecoder: imageDecoder, bounds: bounds, sequenceID: UUID()) else { return nil }
        return WarmStart(snapshot: projection.snapshot, projection: projection)
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
                let allowed = original.presentation.window.admittedIDs.union(evidence.admittedIDs)
                // Com a cabeça mantida, a releitura tem de alcançar **toda** carta já admitida; com a regra do
                // arquiteto basta a capacidade congelada. O filtro abaixo continua mantendo exatamente as
                // identidades admitidas, então alargar a leitura não admite nada de novo.
                let kept = original.bounds.keepsAdmittedHead ? allowed.count : original.bounds.backwardCapacity
                let history = try publicationHistory.window(editionID: original.presentation.editionID,
                    around: FeedWindowAnchor(cardID: observation.anchor.cardID, placement: .center),
                    backwardCapacity: kept,
                    forwardCapacity: original.bounds.forwardCapacity)
                let cards = history.cards.filter { allowed.contains($0.id) }
                    .compactMap { Self.admitted($0, decoder: imageDecoder) }
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
    ///
    /// **Only the two boundaries change.** Rewriting the whole list per advance builds a new `PresentationCard` for
    /// every admitted card on every step — and with the head kept that list grows with how far the reader has read,
    /// so the cost grew with the session (reported on the device as stutter that gets worse the longer one reads).
    /// The unchanged cards keep their identity, which also keeps the feed's own diff small.
    private func boundedResidency(items: [PresentationCard], editionID: FeedEditionID,
        around anchorCardID: PublicationCardID, bounds: FeedPresentationBounds) throws -> ([PresentationCard], Bool) {
        guard let anchorIndex = items.firstIndex(where: { $0.id == anchorCardID }) else { return (items, false) }
        let first = max(0, anchorIndex - bounds.backwardCapacity)
        let last = min(items.count - 1, anchorIndex + bounds.forwardCapacity)
        // R03: the region to protect is the union of the current band and the band the reader was at before this
        // decision. A reverse gesture (or an accessibility move, or a bounce) can reveal the previous region
        // **before** this observation reaches the runtime; releasing those bitmaps there is a slot that draws
        // empty at the instant of exposure. The union is at most two bands, so residency stays bounded.
        let previousBand: ClosedRange<Int>? = previousResidencyAnchor.flatMap { id in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
            return max(0, index - bounds.backwardCapacity)...min(items.count - 1, index + bounds.forwardCapacity)
        }
        // R03/P04: the region to protect is the **union** of the current band and the band the reader was at
        // before. Taking the convex hull of two distant bands protected the gap between them: its ids were released
        // from the restore, so every one of them was decoded again on a long jump, and memory/decode grew with the
        // distance the comment promises is irrelevant.
        let bands = Self.mergedBands([first...last, previousBand].compactMap { $0 })
        // The decision has run for this anchor, whatever it concluded: the next observation's "previous" is this one.
        previousResidencyAnchor = anchorCardID
        func isProtected(_ index: Int) -> Bool { bands.contains { $0.contains(index) } }
        // Cards that must hand their pixels back: outside every revealable region, still holding an image.
        let leaving = items.indices.filter { !isProtected($0) && items[$0].image != nil }
        // Cards that come back into a revealable region having released theirs. An asset already known to be gone is
        // not decoded again: it keeps its placeholder and the session does not spin on it.
        let returning = items.indices.filter {
            isProtected($0) && releasedImageCards.contains(items[$0].id)
                && !unrecoverableImageCards.contains(items[$0].id)
        }
        guard !leaving.isEmpty || !returning.isEmpty else { return (items, false) }
        var next = items
        for index in leaving {
            next[index] = next[index].releasingDecodedImage()
            releasedImageCards.insert(next[index].id)
        }
        if !returning.isEmpty, let imageDecoder {
            // Read each band alone, never the interval between them, and decode **only** the ids that are actually
            // returning: a card that never left the band already holds the pixels it was published with.
            let returningIDs = Set(returning.map { items[$0].id })
            let indexByID = Dictionary(uniqueKeysWithValues: items.indices.map { (items[$0].id, $0) })
            for band in bands {
                let published = try publicationHistory.window(editionID: editionID,
                    around: FeedWindowAnchor(cardID: items[band.lowerBound].id, placement: .center),
                    backwardCapacity: 0, forwardCapacity: band.count - 1)
                for card in published.cards where returningIDs.contains(card.id) {
                    guard let index = indexByID[card.id] else { continue }
                    let fresh = PresentationCard(publishedCard: card, decoder: imageDecoder)
                    releasedImageCards.remove(card.id)
                    if fresh.isRenderReady {
                        next[index] = fresh
                    } else {
                        // MUTATION (red proof): the old exclusion of a failed reconstruction.
                        unrecoverableImageCards.insert(card.id)
                    }
                }
            }
        }
        return (next, true)
    }

    /// Sorted, coalesced index ranges. Adjacent bands are one region; distant ones stay apart so the gap is never
    /// read or decoded.
    private static func mergedBands(_ ranges: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        var merged: [ClosedRange<Int>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound + 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// R04: memory pressure keeps the reader's own reading and releases everything else. The current band around
    /// the anchor **keeps its pixels** — the card the reader is on and the cards beside it must draw at once — and
    /// the previous band's protection (R03) is dropped, because the system is asking for bytes. Identity, order,
    /// anchor, geometry and the durable payload do not change; only residency does. Releasing pixels outside the
    /// reader's own band is exactly what the running session already did before R03 added the second band.
    ///
    /// Returns whether anything was released, so a pressure signal with nothing to release allocates nothing.
    @discardableResult
    public func trimResidencyForMemoryPressure() throws -> Bool {
        guard let current = state else { return false }
        let items = current.presentation.window.items
        guard let anchorIndex = items.firstIndex(where: { $0.id == current.presentation.window.anchor.cardID })
        else { return false }
        let first = max(0, anchorIndex - current.bounds.backwardCapacity)
        let last = min(items.count - 1, anchorIndex + current.bounds.forwardCapacity)
        var next = items
        var changed = false
        for index in items.indices where !(first...last).contains(index) {
            guard next[index].image != nil else { continue }
            next[index] = next[index].releasingDecodedImage()
            releasedImageCards.insert(next[index].id)
            changed = true
        }
        guard changed else { return false }
        guard let window = FeedWindowSnapshot(items: next, anchor: current.presentation.window.anchor) else {
            return false
        }
        let snapshot = try projectWindow(contextKey: current.presentation.contextKey,
            editionID: current.presentation.editionID, window: window)
        state = FeedSessionState(editorialRevisionID: current.editorialRevisionID,
            presentation: snapshot, bounds: current.bounds)
        // The pressure decision is the last residency decision: the next observation protects this band only.
        previousResidencyAnchor = snapshot.window.anchor.cardID
        return true
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
            .compactMap { Self.admitted($0, decoder: imageDecoder) }
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

    /// The absolute bound on the admitted list — a **memory guard**, not a window shape (owner's item F,
    /// 2026-10-17). It is deliberately high: no reading session reaches it, so it never acts as a page, a runway
    /// target or a health number; what it bounds is the one quantity `keepsAdmittedHead` leaves unbounded — a reader
    /// who reads a very long Edition in a single session grows the list monotonically, one admitted card at a time.
    /// Below it the kept head behaves exactly as the 2026-10-13 decision states.
    public static let maxAdmittedItems = 2000

    /// Keeps the admitted list bounded **around the anchor**: at most `backwardCapacity` cards before it and
    /// `forwardCapacity` after it, which is what the presentation was installed with. The architect separated the
    /// two claims and he is right: every admission obeying the bound *locally* does not bound the list — prepending
    /// pushes the anchor right, appending grows the tail, and over a long navigation either end accumulates. Cards
    /// cut here stay **reachable**: the next admission near that end reads them from the store again, so leaving the
    /// window is not losing the content. The anchor itself is never cut — it is inside `first...last` by construction.
    ///
    /// The anchor-relative trim is followed by the **absolute** cap: a kept head has no other ceiling, so a list
    /// that would exceed `maxAdmittedItems` drops its oldest cards — never the reader's own card, never the reserve
    /// ahead of it, and never anything at all below the cap.
    private func boundedToTotalWindow(_ items: [PresentationCard], around anchorCardID: PublicationCardID,
        bounds: FeedPresentationBounds) -> [PresentationCard] {
        guard let anchorIndex = items.firstIndex(where: { $0.id == anchorCardID }) else { return items }
        // Both directions by default; the **head is kept** when the presentation was installed that way (the
        // owner's experiment, 2026-10-13): nothing above the reader is removed, so a forward read never changes the
        // content above them and the offset corrector has nothing to hide. The forward reserve is bounded either way.
        let first = bounds.keepsAdmittedHead ? 0 : max(0, anchorIndex - bounds.backwardCapacity)
        let last = min(items.count - 1, anchorIndex + bounds.forwardCapacity)
        let windowCount = last - first + 1
        guard windowCount > Self.maxAdmittedItems else {
            guard first > 0 || last < items.count - 1 else { return items }
            return Array(items[first...last])
        }
        // The cap runs **after** that trim and drops the oldest: with the head kept, `first` is the Edition's own
        // first admitted card, so the cards beyond the cap are the ones furthest above the reader. `min` keeps the
        // reader's own card when a caller declares a forward reserve that by itself passes the cap — the anchor is
        // never one of the cards that leave.
        let dropped = windowCount - Self.maxAdmittedItems
        let keepFrom = first + min(dropped, anchorIndex - first)
        return Array(items[keepFrom...last])
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
            .compactMap { Self.admitted($0, decoder: imageDecoder) }
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
            .compactMap { Self.admitted($0, decoder: imageDecoder) }
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

    /// The admission boundary: a published card yields a presentation only when it is render-ready. An image
    /// card whose media cannot be decoded is excluded from the window — it is never converted to a text card under
    /// the same identity, and the ready candidates around it are admitted normally (INV-17).
    private static func admitted(_ card: PublishedCard, decoder: PresentationImageDecoder?) -> PresentationCard? {
        let projected = PresentationCard(publishedCard: card, decoder: decoder)
        return projected.isRenderReady ? projected : nil
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
    ///
    /// **What shape is restored is the presentation's own bound, not a neighbourhood of the cursor.** A list
    /// installed with `keepsAdmittedHead` holds every card above the reader for the life of the session, so the
    /// same list has to come back: restoring only `backwardCapacity` cards behind the cursor dropped everything the
    /// reader had already passed — `keepsAdmittedHead` promised the opposite, and a card they had saved above the
    /// cursor was not drawn at all after a reopen (B05, 2026-10-14: the saved card stood 22 cards above the durable
    /// position). A list bounded around the reader keeps its bounded restore: there a card cut behind the anchor is
    /// reachable by the next backward admission.
    private func installFromCheckpoint(_ bounds: FeedPresentationBounds) throws -> FeedPresentationSnapshot? {
        guard let projected = try FeedCheckpointProjection.read(publicationHistory: publicationHistory,
            imageDecoder: imageDecoder, bounds: bounds, sequenceID: projectionSequenceID,
            after: projectionPosition) else {
            state = nil
            return nil
        }
        releasedImageCards.formUnion(projected.releasedImageCards)
        projectionPosition = projected.position
        state = projected.state
        // R03: the restored band is the band the surface will reveal first; the next observation protects it too.
        previousResidencyAnchor = projected.snapshot.window.anchor.cardID
        return projected.snapshot
    }

    /// The restored window as a presentation, with the pixel decision made the way the running session makes it.
    ///
    /// `boundedResidency` keeps decoded pixels only in the band around the reader and releases every card outside
    /// it (`releasedImageCards` is what re-decodes them when the reader comes back). A restore that decoded a pixel
    /// for **every** admitted card would therefore hold — and pay, in one actor hop — one image per card the reader
    /// had ever passed, a state the session it restores never reached. So the band is decoded and the rest keeps
    /// its frozen values with the bitmap released, which is exactly what those cards had before the close.
    ///
    /// **One implementation of a restore**, and it deliberately lives outside the actor: a warm launch has to
    /// materialize the reader's own window **before its first frame** (INV-07), i.e. before it can `await` anything,
    /// and the actor's own `.initial`/`.restore` admissions call the same function — so the two can never disagree
    /// about what a durable checkpoint means, and no host needs a second restore path to have the feed on screen.
    ///
    /// It reads nothing but the checkpoint. The state a restore installs is always the fresh one: both admissions
    /// that reach here refuse to run while a presentation is admitted, so there are no already-materialized cards to
    /// reuse — the `reusable` map this used to build from `state?.presentation` could only ever be empty.
    struct FeedCheckpointProjection: Sendable {
        let state: FeedSessionState
        let snapshot: FeedPresentationSnapshot
        let releasedImageCards: Set<PublicationCardID>
        let sequenceID: UUID
        let position: UInt64

        static func read(publicationHistory: PublicationHistory, imageDecoder: PresentationImageDecoder?,
            bounds: FeedPresentationBounds, sequenceID: UUID, after position: UInt64 = 0) throws
            -> FeedCheckpointProjection? {
            let restored = bounds.keepsAdmittedHead
                ? try publicationHistory.restoreFromEditionStart(forwardCapacity: bounds.forwardCapacity,
                    contextKey: bounds.contextKey)
                : try publicationHistory.restore(backwardCapacity: bounds.backwardCapacity,
                    forwardCapacity: bounds.forwardCapacity, contextKey: bounds.contextKey)
            guard let restored else { return nil }
            try publicationHistory.markSeen(editionID: restored.edition.id,
                cardID: restored.cursor.anchor.cardID)
            var released: Set<PublicationCardID> = []
            guard let window = projectedWindow(restored.window, bounds: bounds, imageDecoder: imageDecoder,
                released: &released) else { return nil }
            let next = try FeedProjectionProvenance.nextPosition(after: position)
            let snapshot = FeedPresentationSnapshot(contextKey: restored.edition.contextKey,
                editionID: restored.edition.id, window: window,
                provenance: .init(sequenceID: sequenceID, position: next))
            return FeedCheckpointProjection(
                state: FeedSessionState(editorialRevisionID: restored.edition.editorialRevision.id,
                    presentation: snapshot, bounds: bounds),
                snapshot: snapshot, releasedImageCards: released, sequenceID: sequenceID, position: next)
        }

        private static func projectedWindow(_ published: FeedWindow, bounds: FeedPresentationBounds,
            imageDecoder: PresentationImageDecoder?, released: inout Set<PublicationCardID>) -> FeedWindowSnapshot? {
            // FeedWindow guarantees its anchor is one of its cards; a window without a numbered band has no outside
            // to release, so every card crosses the admission gate and nothing is admitted as a placeholder.
            guard let anchorIndex = published.cards.firstIndex(where: { $0.id == published.anchor.cardID }) else {
                let items = published.cards.compactMap { FeedSession.admitted($0, decoder: imageDecoder) }
                return FeedWindowSnapshot(items: items, publishedAnchor: published.anchor)
            }
            let first = max(0, anchorIndex - bounds.backwardCapacity)
            let last = min(published.cards.count - 1, anchorIndex + bounds.forwardCapacity)
            var items: [PresentationCard] = []
            items.reserveCapacity(published.cards.count)
            for (index, card) in published.cards.enumerated() {
                let value: PresentationCard?
                if first...last ~= index {
                    value = FeedSession.admitted(card, decoder: imageDecoder)
                } else if imageDecoder == nil {
                    // Nothing can reconstruct pixels in this composition, so an outside-band image card has no
                    // presentation now or later: it is not admitted anywhere in the window.
                    value = FeedSession.admitted(card, decoder: nil)
                } else {
                    // Fora da faixa: os valores congelados ficam, os pixels voltam.
                    let outside = PresentationCard(publishedCard: card)
                    released.insert(outside.id)
                    value = outside
                }
                if let value { items.append(value) }
            }
            // The window must name the reader's position among presented values. When the published anchor is one
            // of the excluded cards, the closest admitted card carries the same placement.
            var anchorID = published.anchor.cardID
            if !items.contains(where: { $0.id == anchorID }) {
                let following = items.first { candidate in
                    guard let position = published.cards.firstIndex(where: { $0.id == candidate.id }) else {
                        return false
                    }
                    return position > anchorIndex
                }
                guard let fallback = following ?? items.last else { return nil }
                anchorID = fallback.id
            }
            return FeedWindowSnapshot(items: items,
                publishedAnchor: FeedWindowAnchor(cardID: anchorID, placement: published.anchor.placement))
        }
    }

    /// Allocate only after a successful read, alongside the actor's synchronous state transition.
    /// An unchanged effective projection retains its exact provenance, even after another read.
    private func projectWindow(contextKey: ContextKey, editionID: FeedEditionID,
        window: FeedWindowSnapshot) throws -> FeedPresentationSnapshot {
        let unavailable = unrecoverableImageCards.intersection(window.admittedIDs)
        if let current = state?.presentation, current.contextKey == contextKey,
            current.editionID == editionID, current.window == window,
            current.unavailableImageCardIDs == unavailable { return current }
        let next = try FeedProjectionProvenance.nextPosition(after: projectionPosition)
        let snapshot = FeedPresentationSnapshot(contextKey: contextKey, editionID: editionID, window: window,
            provenance: .init(sequenceID: projectionSequenceID, position: next),
            unavailableImageCardIDs: unavailable)
        projectionPosition = next
        return snapshot
    }

    /// Makes the existing logical position durable without changing current presentation.
    /// The caller decides when a milestone occurs; date validation belongs to Persistence.
    ///
    /// This is an **explicit caller statement** — "this is the reader's position now" — so it writes the position it
    /// is asked to write, including the window's anchor when the app has stated no presented position: §9's contract
    /// ("an explicit milestone after that scroll reopens at the new position") and
    /// `PresentationProjectionOrderingTests.testO15ReopenStartsIndependentMemorySequenceAndPreservesHistory` pin it.
    /// The rule that keeps an incomplete statement from replacing an exact record belongs to the **automatic**
    /// boundary, which fires from the rendering on its own — `recordSettledPosition(at:settled:)`.
    public func checkpointCurrentPosition(at date: Date) throws -> Bool {
        guard let current = state else { return false }
        let anchor = recordedPosition(of: current)
        try publicationHistory.saveCursor(
            SessionCursor(editionID: current.presentation.editionID, anchor: anchor), updatedAt: date)
        // A milestone is a durable write of the same record: it also moves the debounce's own clock, so the
        // window that follows it measures from what the reader actually last made durable.
        durablePosition = (anchor, date)
        return true
    }

    /// Whether this statement may be written, and what stands when it may not: **an incomplete statement never
    /// replaces an exact one** (lead, 2026-10-14). It applies to this **automatic** boundary — the one that fires
    /// from the rendering on every rest and on every gesture-less move — and not to an explicit milestone, which is
    /// a caller decision with its own pinned contract (§9, `testO15…`).
    ///
    /// An **exact** record is the one the rendering stated — the card the viewport starts at, written as `.top`. An
    /// **incomplete** statement is the window's anchor, which `recordedPosition(of:)` falls back to when the app has
    /// stated no presented position: it is the card the reader is *on*, and §9a documents it as a record a restore
    /// can only honour by approximation. The two competing as equals is what let an association rebuilt by the
    /// A→B→A return overwrite the reader's exact position with its own restore point, 145 ms after the rendering had
    /// stated it (B05, 2026-10-14: the durable card became 15 while the top card drawn was 7). Returns the card the
    /// exact record holds when the write must be skipped, `nil` when it may proceed.
    ///
    /// The comparison reads the record **a restore would read** — the context's own, else the singleton — one
    /// single-row read, and **only** on the incomplete path: an exact statement is written without reading anything.
    /// Two incomplete statements still compete as they always did (the newer wins), a record for another Edition is
    /// not a competing statement, and neither is no record at all.
    private func exactRecordStanding(_ anchor: FeedWindowAnchor, editionID: FeedEditionID,
        contextKey: ContextKey?) throws -> PublicationCardID? {
        guard case .center = anchor.placement else { return nil }
        guard let saved = try publicationHistory.savedCursor(contextKey: contextKey) else { return nil }
        guard saved.editionID == editionID, case .top = saved.anchor.placement else { return nil }
        return saved.anchor.cardID
    }

    /// PO 2026-10-14, ratificado: retornar ao app tem de recuperar a posição **também depois de um fechamento à
    /// força**. O cursor durável passa a ser gravado sobre o último card **admitido e estabelecido** — e não só nos
    /// milestones (troca de contexto, substituição de sessão, ida para background, criação da edição): um leitor que
    /// morre sem passar por nenhum deles voltava ao **início da edição**, porque o cursor nunca tinha sido reescrito.
    ///
    /// **O que o registro nomeia** é a posição do *viewport* do leitor — o card em que a tela dele começa, preso à
    /// borda superior —, não o card em que ele está: ver `recordSettledPosition(at:settled:)` e
    /// `notePresentedPosition(_:atRest:)` para a medição que separa os dois. A perda espacial declarada é **o
    /// deslocamento dentro do primeiro card** (até uma altura de card), porque o contrato nunca carrega pixels; a
    /// identidade do card do topo é reproduzida exatamente, e é ela que a aceitação mede.
    ///
    /// A regra temporal tem duas partes, e as duas existem para que a **perda máxima declarada** seja pequena de
    /// verdade:
    ///
    /// - **O leitor chegando ao repouso é gravado na hora.** `settled: true` é o próprio fato que a decisão nomeia
    ///   (o último card *estabelecido*); ele nunca espera janela nenhuma, então quem para de rolar não perde nada.
    /// - **Enquanto o leitor está se movendo**, a gravação é limitada a no máximo uma por
    ///   `settledPositionDebounceWindow` — é esta a janela máxima de perda: um fechamento à força **em movimento**
    ///   pode perder no máximo o avanço dos últimos 20 s de rolagem, e nada além disso.
    ///
    /// O caminho comum de saída não depende disso: background continua gravando a posição exata sem esperar
    /// janela nenhuma, e a perda declarada só existe para a morte súbita *durante* o movimento.
    ///
    /// Custo declarado, ao lado do orçamento de performance (a fluidez medida pelo medidor de quadros: 16,67 ms por
    /// quadro a 60 Hz): **no máximo `60 / settledPositionDebounceWindow` = 3 escritas por minuto em movimento**,
    /// mais **uma por posição de repouso distinta** (o leitor que para é quem produz escritas; quem não se mexe não
    /// produz nenhuma), mais uma na primeira observação estabelecida de cada associação, mais os milestones que já
    /// existiam. Cada escrita é um upsert de uma linha no SQLite, executado no executor deste ator — nunca no corpo
    /// de uma view, nunca no ator principal e nunca no caminho de renderização — e mede 0,82 ms nesta máquina.
    public static let settledPositionDebounceWindow: TimeInterval = 20

    /// Records the admitted, settled position durably, under the declared debounce window.
    ///
    /// The caller states *when* the reader's own move happened and whether it was a **rest**; this owner states
    /// *how often* it may reach storage while the reader is still moving, and — from the rendered position the app
    /// has stated (`notePresentedPosition(_:atRest:)`) — *what* the record names. A position already durable is
    /// never rewritten, so a resting reader produces no writes at all. Nothing changes the current presentation,
    /// and a failed write propagates with both the memory state and the previous durable cursor intact — the same
    /// contract as the milestone write.
    ///
    /// One statement is refused without writing: an **incomplete** one — the window's anchor, because the app has
    /// stated no presented position — when the durable record is **exact** (`.top`, the card the viewport starts at,
    /// same Edition). Nothing is lost by keeping it: the exact record names the position a reopen honours exactly,
    /// while the window's anchor is the card the reader is *on*. That comparison is the one read this owner makes,
    /// and only here.
    ///
    /// - Parameter settled: the reader has come to rest (`RunwayActivity.stationary`, the app's own semantic
    ///   settle, or the rendering resting at a distinct position). A rest is always recorded; a moving observation
    ///   is recorded only once the window has passed.
    @discardableResult
    public func recordSettledPosition(at date: Date, settled: Bool = false) throws -> SettledPositionRecording {
        guard let current = state else { return .nothingToRecord }
        let anchor = recordedPosition(of: current)
        if let durable = durablePosition {
            if durable.anchor == anchor { return .alreadyDurable }
            let elapsed = date.timeIntervalSince(durable.at)
            if !settled, elapsed < Self.settledPositionDebounceWindow {
                return .withinWindow(remaining: Self.settledPositionDebounceWindow - elapsed)
            }
        }
        // Uma afirmação **incompleta** — a âncora da janela, quando o app não declarou posição apresentada — não
        // substitui um registro **exato** da mesma edição: a carta do topo que o desenho gravou fica (lead,
        // 2026-10-14). A comparação custa uma leitura de uma linha, e só neste caminho: uma afirmação exata escreve
        // sem ler nada.
        let stands = try exactRecordStanding(anchor, editionID: current.presentation.editionID,
            contextKey: current.bounds.contextKey)
        if let stands { return .keptExactRecord(cardID: stands) }
        try publicationHistory.saveCursor(
            SessionCursor(editionID: current.presentation.editionID, anchor: anchor), updatedAt: date)
        durablePosition = (anchor, date)
        return .written(cardID: anchor.cardID, placement: Self.presentationPlacement(of: anchor.placement))
    }

    /// The app states where the reader's **rendered viewport starts** — the first card whose top edge is at or
    /// below the viewport's top edge. That is the position a restore can honour **exactly** (pin the card's top
    /// edge to the viewport's top edge), which is why the durable record states it with `.top` instead of the
    /// admitted window's own anchor. The window's anchor is the card the reader is *on* — the one straddling the
    /// capture's reference line — and the record is **incomplete** for it: the distance from that line to the
    /// card's top edge is not part of a record that never carries pixels, so a restore that honours the anchor card
    /// lands on a neighbouring card (measured 2026-10-14, B05: with the reader's card at y=399 and the top card at
    /// y=234 inside an 834 pt viewport, the cold start drew a viewport whose top card sat four to five cards away
    /// from the one measured before the forced close).
    ///
    /// The fact is memory-local on its own: it becomes durable only when the rendering is **at rest** at it, and
    /// that is also the occasion a viewport moved **without any gesture** (an accessibility scroll, a system
    /// animation, a programmatic scroll) becomes a durable position — without it, a reader who dies after such a
    /// move returns to a position they had already left (measured in the same run: the app registered no
    /// observation for the driver's own scroll-to-visible, so the record stayed eight cards behind the screen).
    ///
    /// - Returns: the recording, when `atRest` made this a write attempt; `nil` when the position was only
    ///   remembered (the reader or the rendering is still moving).
    @discardableResult
    public func notePresentedPosition(_ anchor: PresentationAnchor, atRest: Bool,
        at date: Date = Date()) throws -> SettledPositionRecording? {
        presentedPosition = anchor
        guard atRest else { return nil }
        return try recordSettledPosition(at: date, settled: true)
    }

    /// The position a durable write states. The app's presented top card wins **only when this admitted window
    /// holds it**: a record may never name a card the reader's own window does not carry, so a stale rendering
    /// fact (another context, another Edition, a card the window trimmed) falls back to the window's own anchor
    /// instead of writing a position nobody can restore. Both boundaries state the position through this one
    /// mapping, so they can never disagree about what "the reader's position" is.
    private func recordedPosition(of current: FeedSessionState) -> FeedWindowAnchor {
        guard let presentedTop = presentedPosition?.cardID,
            current.presentation.window.items.contains(where: { $0.id == presentedTop })
        else { return Self.durableAnchor(of: current.presentation.window.anchor) }
        return FeedWindowAnchor(cardID: presentedTop, placement: .top)
    }

    /// The durable form of a presentation anchor: card and placement, nothing else. Used when the app states no
    /// rendered position, so the record keeps naming the card the reader's own observation produced.
    private static func durableAnchor(of anchor: PresentationAnchor) -> FeedWindowAnchor {
        FeedWindowAnchor(cardID: anchor.cardID, placement: placement(of: anchor.placement))
    }

    private static func placement(of placement: PresentationAnchorPlacement) -> AnchorPlacement {
        switch placement {
        case .top: return .top
        case .center: return .center
        }
    }

    private static func presentationPlacement(of placement: AnchorPlacement) -> PresentationAnchorPlacement {
        switch placement {
        case .top: return .top
        case .center: return .center
        }
    }
}
