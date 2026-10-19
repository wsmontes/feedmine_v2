// File: FeedDestinationGate.swift
// Module: FeedMineRuntime
// Owns: the decision of whether a navigation destination may be applied to the surface now.
// Does not own: navigation, gestures, accessibility or preparation. It reads the admitted value and states readiness.
import Foundation
import FeedMineDomain

/// R04: a programmatic jump or an accessibility move may reach only a destination whose pixels are **ready**. A card
/// admitted inside the window but outside the protected pixel region has released its bitmap; applying the position
/// there would expose an empty slot at the instant of the move. The surface asks this gate, asks the session to
/// prepare the destination band, and applies the position only when the prepared value says `ready`. An asset that is
/// gone after preparation is `unavailable`: the move is stated, never faked and never applied to a placeholder.
public enum FeedDestinationReadiness: Hashable, Sendable {
    /// The card is admitted and may be drawn now (text, or an image with its pixels).
    case ready
    /// The card is admitted but its bitmap is released: prepare the destination band first.
    case needsPreparation
    /// The card is not admitted in this presentation at all; an ordinary viewport move is inert for it.
    case notAdmitted
    /// After preparation the destination is no longer in the window: its asset could not be reconstructed.
    case unavailableAfterPreparation
}

public enum FeedDestinationGate {
    public static func readiness(of cardID: PublicationCardID,
        in presentation: FeedPresentationSnapshot?) -> FeedDestinationReadiness {
        guard let presentation,
            let card = presentation.window.items.first(where: { $0.id == cardID }) else { return .notAdmitted }
        return card.isRenderReady ? .ready : .needsPreparation
    }

    /// The same question after the preparation the surface requested. A destination that is no longer in the
    /// prepared window is **unavailable** — the honest answer for an asset that could not be reconstructed — and the
    /// card's identity, order and anchor are untouched by that answer.
    public static func readinessAfterPreparation(of cardID: PublicationCardID,
        in presentation: FeedPresentationSnapshot?) -> FeedDestinationReadiness {
        guard let presentation, presentation.window.items.contains(where: { $0.id == cardID }) else {
            return .unavailableAfterPreparation
        }
        // Preserving the card's identity is the right answer for the reader, but it must not hide the failure:
        // a release that could not be reconstructed is decided, not pending for another preparation.
        if presentation.unavailableImageCardIDs.contains(cardID) { return .unavailableAfterPreparation }
        return readiness(of: cardID, in: presentation)
    }
}
