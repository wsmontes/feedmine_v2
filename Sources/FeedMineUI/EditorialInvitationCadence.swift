//
// File: EditorialInvitationCadence.swift
// Module: FeedMineUI
//
// Responsibility:
// F02's offer budget: how many cards the reader has really been exposed to, how many invitations were shown, what
// they did with them, and whether the invitations are hidden. It answers one question — "may an offer be placed
// here, and why not" — and it holds the two facts that outlive a single render: which subjects were already
// offered, and on which card each offered block lives.
//
// Does not own: which subject a card may be asked about (Composition), what an answer means (the reader's
// stored preferences), discovery, or the feed's cards. It never reads a clock: an interval is counted in cards
// the reader actually passed, which is the unit the product decision is stated in.
//
// Vocabulary, deliberately (architect, 2026-10-11): an **exposure** is a card the app presented to the reader; it
// is not proof that the reader read it. The budget is counted in cards exposed/traversed, and the reports say so.
import Foundation
import FeedMineDomain
import FeedMineRuntime

/// The cards the reader was **actually exposed to**, by identity.
///
/// The feed's own visual capture publishes exactly this — the card at the reader's position — and the
/// composition delivers it here. A window that was rendered but never shown is not an exposure, so the
/// presentation's own window size is deliberately not a source for this count.
public final class EditorialExposureLedger {
    private var seen: Set<PublicationCardID> = []

    public init() {}

    /// How many distinct cards the reader has been exposed to. Turning back does not inflate it: the same card
    /// seen twice is one card exposed.
    public var count: Int { seen.count }

    public func expose(_ cardID: PublicationCardID) {
        seen.insert(cardID)
    }

    /// Whether this card has already been presented to the reader.
    ///
    /// The feed asks this before it places an invitation (architect, 2026-10-11): a block placed on a card the
    /// reader has already passed is a block the reader will never see, which the app's own trace showed happening
    /// with real content. An offer belongs where the reader is *going*, not where they have been.
    public func wasExposed(_ cardID: PublicationCardID) -> Bool {
        seen.contains(cardID)
    }
}

/// The reader's in-feed invitations, as a **budget over real exposures**.
///
/// The product decision it implements (round 10, alternative A): the invitation stays where the answer lives —
/// after its card — but stops being unlimited. Every number is a calibration parameter in one place, so the rule
/// can be re-argued without touching the feed.
public final class EditorialInvitationCadence {
    /// The calibration parameters. Conservative on purpose: the acceptance driver walks the feed in bounded
    /// strides and must still reach two answers, while a thirty-minute trace may not become a wall of blocks.
    public struct Budget: Equatable, Sendable {
        /// No offer before the reader has been exposed to this many cards.
        public var firstOfferAfterCards: Int
        /// Cards between offers when nothing has been left unanswered.
        public var baseInterval: Int
        /// An offer shown and left unanswered multiplies the next interval by this.
        public var ignoredMultiplier: Int
        /// The growth stops here: an interval may never become "never".
        public var maximumInterval: Int
        /// How many offers one session may place at all.
        public var sessionOfferCap: Int

        public init(firstOfferAfterCards: Int = 4, baseInterval: Int = 12, ignoredMultiplier: Int = 2,
            maximumInterval: Int = 96, sessionOfferCap: Int = 4) {
            self.firstOfferAfterCards = firstOfferAfterCards
            self.baseInterval = baseInterval
            self.ignoredMultiplier = ignoredMultiplier
            self.maximumInterval = maximumInterval
            self.sessionOfferCap = sessionOfferCap
        }
    }

    /// Why no offer was placed. Stated, never swallowed: the trace and the tests read the same value.
    public enum Refusal: Equatable, Sendable {
        case hidden
        case subjectAnswered
        case subjectAlreadyOffered
        case sessionCapReached
        case tooSoon(cardsRemaining: Int)
    }

    /// A block that was offered, and the form it was offered in. The form travels with the offer because the feed
    /// re-renders its window constantly: a block that came back as the full question after the reader had already
    /// met the compact one would be a different offer than the one that was made (measured on the device,
    /// 2026-10-11: the second offer rendered full again on the next window change).
    public struct HostedOffer: Equatable, Sendable {
        public let subject: String
        public let isCompact: Bool
    }

    /// One reading session's own numbers.
    ///
    /// Sessions are kept **per context key for the lifetime of the app run**. Navigating away and back resumes the
    /// session the reader left instead of handing them a new one — the architect's rule: the cap must not be
    /// renewed by navigating (a foreground and an internal session rebuild do not start one either, which is why
    /// nothing here is keyed by the association or by the process's foreground state).
    private struct Session {
        var baseline: Int
        var lastOfferAt: Int?
        var offersShown = 0
        var ignoredOffers = 0
        var pendingSubject: String?
        var offeredSubjects: Set<String> = []
        var hosts: [PublicationCardID: HostedOffer] = [:]
    }

    public let budget: Budget
    private var sessions: [ContextKey: Session] = [:]
    /// The room each offered block took, measured while it was on screen. The reader's layout is theirs: hiding
    /// the invitations must not move the cards under them, so the slot is kept — with **nothing** drawn in it
    /// (measured on the device, 2026-10-11: neither the container nor each leaf of a hidden block leaves the
    /// accessibility tree when they are merely marked hidden; the only thing that certainly does not announce
    /// itself is something that was never drawn).
    private var blockHeights: [PublicationCardID: CGFloat] = [:]
    /// The tallest block seen in each form. A block that was offered but never laid out (a card beyond the lazy
    /// stack's instantiation margin) has no height of its own, and hiding it must not collapse its slot — the
    /// reader's feed would move under them (measured on the device, 2026-10-11: the card the reader was on left
    /// the viewport entirely after hiding, because an unmeasured block's slot went to zero).
    private var formHeights: [Bool: CGFloat] = [:]

    /// The context the current session belongs to. `nil` until the first `beginSession`.
    public private(set) var sessionKey: ContextKey?
    public private(set) var hidden = false

    public init(budget: Budget = Budget()) { self.budget = budget }

    private var current: Session {
        get { sessionKey.flatMap { sessions[$0] } ?? Session(baseline: 0) }
        set { if let key = sessionKey { sessions[key] = newValue } }
    }

    /// The subjects already offered in this session: one offer per subject, by construction.
    public var offeredSubjects: Set<String> { current.offeredSubjects }
    /// Where each offered block lives, and in which form. A block that was offered keeps its card — the answer,
    /// the way back and the hide stay reachable there instead of being recomputed away by the next evaluation.
    public var hosts: [PublicationCardID: HostedOffer] { current.hosts }
    public var offersShown: Int { current.offersShown }
    /// Offers that were shown and left unanswered. It is what makes the interval grow.
    public var ignoredOffers: Int { current.ignoredOffers }

    /// The distance the reader must cover before the next offer. The first offer of a session (or of a cycle
    /// after an explicit re-enable) is governed by `firstOfferAfterCards`; afterwards the interval grows with
    /// every offer left unanswered, up to the ceiling.
    public var interval: Int {
        guard current.offersShown > 0 else { return budget.firstOfferAfterCards }
        var value = budget.baseInterval
        for _ in 0..<current.ignoredOffers {
            value = min(value * max(budget.ignoredMultiplier, 1), budget.maximumInterval)
        }
        return value
    }

    /// Makes `key` the session the budget is spoken about. A context the reader has already visited **resumes its
    /// own session** (its cap, its subjects and its blocks are still there); a new one starts with a full budget.
    /// A foreground and an internal rebuild of the same context are not events here at all.
    public func beginSession(key: ContextKey, cardsTraversed: Int) {
        guard key != sessionKey else { return }
        if sessions[key] == nil { sessions[key] = Session(baseline: cardsTraversed) }
        sessionKey = key
    }

    public func setHidden(_ hidden: Bool) { self.hidden = hidden }

    /// The block that was offered on this card reports the room it takes, while it is on screen and not hidden.
    ///
    /// The slot **never shrinks once it is known**: answering a block makes its form shorter, and a shorter block
    /// above the reader pulls everything below it up — the reader's own card moves, which is exactly what the
    /// answer must not do (measured by the benchmark's B04 on the device, 2026-10-11: `b04-after-answer-stable`
    /// false while the card was below the block). A taller form (a bigger text size) may grow the slot.
    public func remember(height: CGFloat, of card: PublicationCardID, isCompact: Bool) {
        guard !hidden, height > 0 else { return }
        blockHeights[card] = max(blockHeights[card] ?? 0, height)
        formHeights[isCompact] = max(formHeights[isCompact] ?? 0, height)
    }

    /// The room the block on this card took, once it is known.
    public func height(of card: PublicationCardID) -> CGFloat? { blockHeights[card] }

    /// The room to keep for the block on this card when it is hidden: its own measurement, or — for a block that
    /// was never laid out — the tallest one seen in the same form. Never zero once any block of that form has been
    /// seen, because a zero slot is a feed that moves under the reader.
    public func slotHeight(of card: PublicationCardID, isCompact: Bool) -> CGFloat? {
        blockHeights[card] ?? formHeights[isCompact] ?? formHeights[!isCompact]
    }

    /// The reader brought the invitations back from the preferences they were hidden in. Re-enabling is a
    /// deliberate act: it clears the penalty an ignored offer left behind and gives a comfortable interval before
    /// the next one — but it never hands out a new session's worth of offers. The cap the session already spent
    /// stays spent (architect, 2026-10-11: re-enabling must not silently exceed the session's limit), and the
    /// distance already covered still counts.
    public func reenabled(cardsTraversed: Int) {
        hidden = false
        var session = current
        session.ignoredOffers = 0
        session.pendingSubject = nil
        session.lastOfferAt = cardsTraversed
        current = session
    }

    /// Whether a **new** offer may be placed now. `nil` means yes; anything else states why not.
    public func decision(subject: String, isAnswered: Bool, cardsTraversed: Int) -> Refusal? {
        if hidden { return .hidden }
        if isAnswered { return .subjectAnswered }
        let session = current
        if session.offeredSubjects.contains(subject) { return .subjectAlreadyOffered }
        if session.offersShown >= budget.sessionOfferCap { return .sessionCapReached }
        let since = cardsTraversed - (session.lastOfferAt ?? session.baseline)
        if since < interval { return .tooSoon(cardsRemaining: interval - since) }
        return nil
    }

    /// Places an offer: binds it to the card it was made on, and counts the previous offer as unanswered when
    /// the reader reached the next one without answering it.
    public func offered(subject: String, on card: PublicationCardID, cardsTraversed: Int,
        isCompact: Bool = false) {
        var session = current
        if session.pendingSubject != nil { session.ignoredOffers += 1 }
        session.offeredSubjects.insert(subject)
        session.hosts[card] = HostedOffer(subject: subject, isCompact: isCompact)
        session.lastOfferAt = cardsTraversed
        session.offersShown += 1
        session.pendingSubject = subject
        current = session
    }

    /// The reader answered. Engagement is not punished: the penalty is cleared, so the next opportunity comes
    /// after a comfortable interval instead of a doubled one.
    public func answered(subject: String) {
        var session = current
        if session.pendingSubject == subject { session.pendingSubject = nil }
        session.ignoredOffers = 0
        current = session
    }
}
