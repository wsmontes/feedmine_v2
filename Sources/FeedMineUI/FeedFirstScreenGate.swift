// File: FeedFirstScreenGate.swift
// Module: FeedMineUI
//
// Responsibility:
//   Decide which surface the feed shows while the first screen's composition is being proven: the preparation
//   surface until the cards that are actually laid out reach the bottom of the viewport the app measured, and the
//   reading surface once they do — or once a legitimate exit settles the question.
//
// Owns:
//   One pure decision over the measured layout, one coverage value, and the vocabulary of the surfaces the feed can
//   be drawing. Nothing else.
//
// Does not own:
//   The measurement (FeedScreen reports what the layout produced), the clock (the caller states how long the wait
//   has lasted), publication, admission, acquisition, the window, the reader's position or any rendering. Nothing
//   here starts work, and nothing here changes a card.
//
// Architectural invariants:
//   D4 (docs/product/PD-2026-10-20-build-54-reader-promise.md): "a primeira tela nasce preenchida … não existe piso
//   universal de duas cartas; contagem não substitui … geometria observável". The criterion is therefore geometry,
//   never a card count: the bottom of the last laid-out card reaches (or passes) the viewport bottom within the
//   project's own 1 pt tolerance — the rule the first-exposure witness states and the UI journey judges.
//   Every legitimate way out of the wait is a case here (offer exhausted, transport failure, the run's bounded
//   maximum wait), so no launch can sit in preparation forever.
//

import CoreGraphics
import Foundation
import FeedMineRuntime

/// The geometry of the layout the feed is drawing: how many **distinct** cards it laid out, the bottom of the last
/// one in viewport coordinates, and the height of the viewport that contains them.
///
/// It is built from measurements, never from an estimate: `FeedScreen` reports each laid-out card's own frame and
/// the scroll view's measured height, so spacing and slot sizes are already inside `contentBottom`. A card count
/// alone can never satisfy the rule (`laidOutCards` starts at one); a single tall card can, and several short ones
/// cannot — which is exactly the difference the count-based rule could not state.
public struct FeedFirstScreenCoverage: Equatable, Sendable {
    /// The project's own tolerance for "the card reaches the bottom": the same 1 pt the first-exposure witness and
    /// `FeedVisibleExperienceUITests` judge with. Not a fraction of the viewport, and not chosen per run.
    public static let tolerancePoints: CGFloat = 1

    /// Distinct publication IDs the layout actually reported.
    public let laidOutCards: Int
    /// Bottom of the lowest laid-out card, in the scroll view's coordinates.
    public let contentBottom: CGFloat
    /// The viewport height the layout was measured against.
    public let viewportHeight: CGFloat

    public init?(laidOutCards: Int, contentBottom: CGFloat, viewportHeight: CGFloat) {
        guard laidOutCards > 0, viewportHeight.isFinite, viewportHeight > 0,
            contentBottom.isFinite, contentBottom > 0 else { return nil }
        self.laidOutCards = laidOutCards
        self.contentBottom = contentBottom
        self.viewportHeight = viewportHeight
    }

    /// Whether the laid-out content fills the useful area: the last card's bottom is at (or below) the viewport
    /// bottom, within the tolerance.
    public var coversViewport: Bool {
        contentBottom >= viewportHeight - Self.tolerancePoints
    }
}

/// What the feed's own surface is doing right now.
///
/// Two of the cases draw the app's preparation/absence surface (`FeedLoadingView`), and two draw the reader's
/// screen without waiting for anything. `preparation` is the hold this gate exists for: the reader sees the honest
/// preparation surface while the cards behind it are laid out and measured; `absence` is the same surface with
/// nothing to lay out yet.
public enum FeedFirstScreenSurface: Equatable, Sendable {
    /// No accepted selection at all: V1's own empty state, not a wait.
    case sourcesEmpty
    /// The reader is searching; results are a surface of their own, never a preparation.
    case search
    /// Nothing to lay out yet: the loading/failure surface, with the copy its work state names.
    case absence
    /// Cards exist and are laid out, but the measured layout does not fill the viewport yet: hold the
    /// preparation surface over them.
    case preparation
    /// The reader's own cards are on screen.
    case reading
}

/// The first screen's decision. One function, ordered exits, no hidden state.
public enum FeedFirstScreenGate {
    /// Which surface the feed draws.
    ///
    /// The order is the product rule, stated once:
    ///
    /// 1. no sources → `sourcesEmpty` (a decision, not a wait);
    /// 2. searching → `search` (the window is intentionally empty while the reader searches);
    /// 3. already exposed → `reading` (the reading surface is never taken back: a later window change is the feed
    ///    growing under the reader, not a reason to draw the preparation again);
    /// 4. no cards → `absence` (the existing loading/failure surface; there is nothing to measure);
    /// 5. the measured layout covers the viewport → `reading`;
    /// 6. the offer ended → `reading` (the end block is drawn after the last card, so the reader sees what exists);
    /// 7. the transport failed → `reading` (what exists is shown; the work badge states the failure);
    /// 8. the bounded maximum wait elapsed → `reading` (never an infinite preparation);
    /// 9. otherwise → `preparation`.
    ///
    /// `preparationShown` is the fact that keeps a relaunch honest: when the window is already there on the first
    /// pass (a durable restore), no preparation surface was ever drawn, so there is no transition to hold and the
    /// reading surface is shown at once. The hold applies only to a first screen that was actually being prepared.
    public static func surface(hasSources: Bool, isSearching: Bool, preparationShown: Bool,
        cardCount: Int, coverage: FeedFirstScreenCoverage?, work: FeedPresentationState.Work,
        waited: Duration, maximumWait: Duration, alreadyExposed: Bool) -> FeedFirstScreenSurface {
        if !hasSources { return .sourcesEmpty }
        if isSearching { return .search }
        if alreadyExposed { return .reading }
        guard cardCount > 0 else { return .absence }
        // A window that was already there when the screen appeared had no preparation to hold: the reader's
        // reopen shows their own content immediately (the launch witness's headline criterion).
        guard preparationShown else { return .reading }
        if let coverage, coverage.coversViewport { return .reading }
        switch work {
        case .endOfContent, .unreachable, .failed:
            // Both are legitimate ends of the wait: the offer stopped, or the transport proved a failure. What
            // exists is shown; the reader is never held behind a preparation for content that will not arrive.
            return .reading
        case .idle, .pending, .preparing, .unavailable, .deferred:
            break
        }
        if waited >= maximumWait {
            // The bound ends the **unquestioned** wait, not an honest preparation while the pipeline is actually
            // running. A first card at 9.9 s with the work still `.preparing` (the measured D4 run: one 166 pt card
            // of a 718 pt viewport) must not be exposed as the first screen. `.preparing` carries the real
            // PreparationProgress and its own bounded timeouts; when it settles to idle/terminal the cases above
            // end the wait with what exists.
            switch work {
            case .pending, .preparing: return .preparation
            case .idle, .unavailable, .deferred, .endOfContent, .unreachable, .failed: return .reading
            }
        }
        return .preparation
    }
}
