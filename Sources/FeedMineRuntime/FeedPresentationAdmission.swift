// File: FeedPresentationAdmission.swift
// Module: FeedMineRuntime
// Owns: the only explicit reasons that may change the admitted reader list, and its bounds.
// Does not own: production, publication, acquisition, geometry or persistence.

import FeedMineDomain

/// Structural bounds of one admitted presentation. They are supplied when the presentation is
/// installed and frozen for the life of that presentation: no later path may rematerialize the
/// list with different bounds (plan constraint "congelar valores estruturais por sessão").
public struct FeedPresentationBounds: Hashable, Sendable {
    public let backwardCapacity: Int
    public let forwardCapacity: Int
    public let contextKey: ContextKey?
    /// Whether the admitted list keeps every card the reader has already passed instead of cutting them behind the
    /// anchor.
    ///
    /// `false` is the architect's rule: the list is bounded **around** the anchor in both directions, and a card cut
    /// behind stays reachable because the next admission near that end re-reads it from the local store.
    ///
    /// `true` is V1's behaviour, which the owner asked to feel (2026-10-13): nothing above the reader is ever
    /// removed, so a forward read never changes the content above them — and the native offset correction, which
    /// exists to hide exactly that shift, has nothing to correct. The cost is memory: the admitted list grows with
    /// how far the reader has read, which is bounded by the session and by nothing else.
    public let keepsAdmittedHead: Bool

    public init(backwardCapacity: Int, forwardCapacity: Int, contextKey: ContextKey? = nil,
        keepsAdmittedHead: Bool = false) {
        self.backwardCapacity = backwardCapacity
        self.forwardCapacity = forwardCapacity
        self.contextKey = contextKey
        self.keepsAdmittedHead = keepsAdmittedHead
    }
}

/// Admission is the explicit boundary between *produced reserve* and the *admitted list*.
///
/// Production (acquisition, local slices, retry, foreground) extends the reserve and only ever
/// reads `FeedSession.currentPresentation()`. Nothing in that path may install a different list:
/// the reader's cards, order and geometry change only through one of the cases below.
public enum FeedPresentationAdmission: Hashable, Sendable {
    /// Installs the first presentation of an association, at most once per session.
    case initial(FeedPresentationBounds)
    /// Extends the admitted prefix after real forward movement of the reader.
    /// Stationary and layout-driven observations do not extend the boundary.
    case forwardScroll(ViewportObservation)
    /// Extends the admitted list **below its head**, after real backward movement of the reader reached that head.
    /// Mirror of `forwardScroll` in the direction the reader is actually moving: older cards already published are
    /// prepended, the anchor, the edition and every already-admitted card keep their identity and position, and the
    /// batch is bounded by the frozen backward bound. No network is involved — the cards come from the local store.
    ///
    /// Without this case the admitted list could only grow forward, and a relaunch that anchored the reader near
    /// the tail left everything older than the frozen backward bound unreachable by any gesture (measured: 17 cards
    /// visible before closing, 9 after reopening offline, and the 8 oldest reachable by nothing).
    case backwardScroll(ViewportObservation)
    /// Extends the admitted prefix with cards **already published** beyond the admitted tail, owned by
    /// the runtime rather than by a reader gesture (F05/R4: the first open shows what the local store
    /// already holds instead of waiting for a scroll that no one made).
    ///
    /// It invents no observation: the anchor, the reader's position and every already-admitted card are
    /// untouched, and cards are only ever appended after the current tail, bounded by the frozen
    /// forward capacity of the installed presentation. A window with nothing new is a no-op.
    case publishedGrowth
    /// Recovers a presentation for an association that has none (relaunch after a state loss).
    case restore(FeedPresentationBounds)
}

public extension RunwayActivity {
    /// Real forward movement *and* the need to extend the content: the reader has reached the
    /// admitted tail. A forward scroll inside already-admitted history, a stationary settle, a
    /// backward gesture and a layout change never admit.
    var admitsForwardContent: Bool {
        self == .explicitTailApproach
    }

    /// Real backward movement *and* the need to reach what is below it: the reader has reached the admitted head.
    /// A stationary settle and a layout change never admit, and the symmetric case has no separate activity — the
    /// reader moving back **is** the demand, and the frozen backward bound is what keeps it bounded.
    var admitsBackwardContent: Bool {
        self == .backward
    }
}
