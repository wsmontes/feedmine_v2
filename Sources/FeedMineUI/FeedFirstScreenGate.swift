// File: FeedFirstScreenGate.swift
// Module: FeedMineUI
//
// Responsibility:
//   Decide which surface the feed shows while a new feed is being made: the preparation page until the cards that
//   are actually laid out reach the bottom of the viewport the app measured **and** the published page meets its
//   content targets, and the reading surface once both hold — or once a legitimate exit settles the question.
//
// Owns:
//   One pure decision over the measured layout, the published page's own counts, one coverage value, and the
//   vocabulary of the surfaces the feed can be drawing. Nothing else.
//
// Does not own:
//   The measurement (FeedScreen reports what the layout produced), the clock (the caller states how long the wait
//   has lasted), publication, admission, acquisition, the window, the reader's position or any rendering. Nothing
//   here starts work, and nothing here changes a card.
//
// Architectural invariants:
//   D4 (docs/product/PD-2026-10-20-build-54-reader-promise.md): "a primeira tela nasce preenchida … não existe piso
//   universal de duas cartas; contagem não substitui … geometria observável". Geometry stays the product rule for
//   *layout*: the bottom of the last laid-out card reaches (or passes) the viewport bottom within the project's own
//   1 pt tolerance. Build 58 adds **content** targets on top of it (buffer ahead of the anchor, image-bearing first
//   page, variety) — they are holds with a total ceiling, never promises, and they are measured on the publication
//   and the published page, never on the number of cards a lazy list happened to lay out.
//   Every legitimate way out of the wait is a case here (offer exhausted, transport failure, the stall with no work
//   left, the run's bounded maximum wait and the total ceiling), so no launch can sit in preparation forever.
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
/// The two wait cases draw the app's preparation/absence surface (`FeedLoadingView`); the other two draw the
/// reader's screen without waiting for anything.
public enum FeedFirstScreenSurface: Equatable, Sendable {
    /// No accepted selection at all: V1's own empty state, not a wait.
    case sourcesEmpty
    /// The reader is searching; results are a surface of their own, never a preparation.
    case search
    /// Nothing to lay out yet: the loading/failure surface, with the copy its work state names.
    case absence
    /// Cards exist, but the page is not ready to be read yet: hold the preparation page over them.
    case preparation
    /// The reader's own cards are on screen.
    case reading
}

/// The **publication's own** supply facts for the first screen, stated by the composition.
///
/// These are deliberately not window counts. The admitted window projects at most 16 cards ahead of the anchor and
/// 8 behind it, so a window can never state how much the *publication* holds; the publication is where the 32-card
/// batch and the reader's real buffer live. A host that cannot state them (a unit render, a projection without a
/// receipt) leaves them nil and the store falls back to the window — never the other way round.
public struct FirstScreenSupplyFacts: Equatable, Sendable {
    /// How many cards the Edition really published (the receipts' own card identities, deduplicated).
    public let publishedCards: Int
    /// How many of those come **after** the reader's anchor, in publication order.
    public let publishedAhead: Int
    /// A producer can still add cards to this context: the publication is under its batch floor, media for the
    /// examined window is still undecided, or the admitted window has not caught up with what was published.
    public let producing: Bool

    public init(publishedCards: Int, publishedAhead: Int, producing: Bool) {
        self.publishedCards = max(0, publishedCards)
        self.publishedAhead = max(0, publishedAhead)
        self.producing = producing
    }
}

/// What the **published page** states, plus the host facts the decision needs.
///
/// This is deliberately not a layout count: with a lazy list only ~3 cards are ever laid out, so "how many cards
/// are installed" is a different measurement from "how many are drawn". Content readiness prefers the publication
/// facts above and falls back to the installed window; geometry keeps its own rule.
public struct FeedFirstScreenContent: Equatable, Sendable {
    /// The buffer floor: with a real page installed, a normal scroll must not reach the tail immediately.
    public static let aheadFloor = 12
    /// The batch the **first publication** targets while supply is still arriving: the reserve's own floor (32).
    ///
    /// It is deliberately not a hold. Three different counts are in play: the publication may write up to 32 cards,
    /// the *admitted window* projects at most 16 ahead + 8 back around the anchor (≤25), and the lazy list lays out
    /// ~3. Holding the page until the **window** reports 32 would be a 30 s wait by construction, so the batch is
    /// enforced where it belongs (the bootstrap's `publicationLimit`) and the hold is judged on
    /// `FirstScreenSupplyFacts` — the publication's own count — instead.
    public static let batchFloor = 32
    /// The image floor: a page that is meant to be image-bearing must not open text-only.
    public static let imageFloor = 6
    /// The variety floor, capped by what the reader's own selection can supply.
    public static let providerFloor = 3
    /// The "first page" is the first screenful-plus of cards; the image distribution is measured there, never
    /// diluted by the whole window.
    public static let firstPageCards = 12

    public let publishedCards: Int
    public let publishedAhead: Int
    public let distinctProviders: Int
    /// How many distinct sources the reader's selection can contribute at all (host fact). A single-source
    /// context has a provider target of one: it can never satisfy three, and waiting for them would be a bug.
    public let eligibleProviders: Int
    public let imageCardsInFirstPage: Int
    public let firstPageCount: Int
    /// Whether this context asks for images at all. Nil media requests and a text-only published page mean the
    /// page is text by design, so it is never held for pixels it was never meant to have.
    public let declaresImages: Bool
    /// Undecided media work for the examined window. While true, the wait is real work: the stall exit must not
    /// fire, and the absence vocabulary must not call it "no stories".
    public let mediaPending: Bool
    /// A producer can still add cards for this context. Only then does a buffer hold apply: it is the one fact that
    /// separates "abundant supply still arriving" from "this feed has what it will ever have".
    public let supplyProducing: Bool

    public init(publishedCards: Int, publishedAhead: Int, distinctProviders: Int, eligibleProviders: Int,
        imageCardsInFirstPage: Int, firstPageCount: Int, declaresImages: Bool, mediaPending: Bool,
        supplyProducing: Bool = false) {
        self.publishedCards = publishedCards
        self.publishedAhead = max(0, publishedAhead)
        self.distinctProviders = max(0, distinctProviders)
        self.eligibleProviders = max(1, eligibleProviders)
        self.imageCardsInFirstPage = max(0, imageCardsInFirstPage)
        self.firstPageCount = max(0, firstPageCount)
        self.declaresImages = declaresImages
        self.mediaPending = mediaPending
        self.supplyProducing = supplyProducing
    }

    /// The page states nothing yet: used before a snapshot exists.
    public static let empty = FeedFirstScreenContent(publishedCards: 0, publishedAhead: 0, distinctProviders: 0,
        eligibleProviders: 1, imageCardsInFirstPage: 0, firstPageCount: 0, declaresImages: false, mediaPending: false,
        supplyProducing: false)

    public var imageTarget: Int { declaresImages ? min(Self.imageFloor, firstPageCount) : 0 }
    public var providerTarget: Int { min(Self.providerFloor, eligibleProviders) }

    /// The buffer is short **and a producer is active**: a page that still has cards coming is exactly the case
    /// that must keep buffering, and a page with nothing left to arrive is not. Counting cards alone would equate a
    /// finite window with an exhausted supply.
    public var needsAhead: Bool { supplyProducing && publishedCards > 0 && publishedAhead < Self.aheadFloor }
    /// Whether the publication has reached the reserve's batch floor. Informational: see `batchFloor`.
    public var batchReached: Bool { publishedCards >= Self.batchFloor }
    public var needsImages: Bool { publishedCards > 0 && declaresImages && imageCardsInFirstPage < imageTarget }
    public var needsProviders: Bool { publishedCards > 0 && distinctProviders < providerTarget }

    /// Whether a content target is still unmet. Every one of them is a hold, never a promise: the ceiling, the
    /// stall-with-no-work and the terminal work states decide when the reader sees what exists.
    public var holdsForContent: Bool { needsAhead || needsImages || needsProviders }
}

/// The first screen's decision. One function, ordered exits, no hidden state.
public enum FeedFirstScreenGate {
    /// Which surface the feed draws.
    ///
    /// The order is the product rule, stated once:
    ///
    /// 1. no sources → `sourcesEmpty` (a decision, not a wait);
    /// 2. searching → `search` (the window is intentionally empty while the reader searches);
    /// 3. already exposed → `reading` (the reading surface is never taken back);
    /// 4. no cards → `absence` (the loading/failure surface; there is nothing to measure);
    /// 5. no preparation was requested → `reading` (a durable restore was never prepared here);
    /// 6. a filter change that has not drawn its page yet → `preparation` (the request is honoured for at least one
    ///    drawn pass, so a context whose Edition is already cached is installed behind the page instead of
    ///    appearing under the previous feed);
    /// 7. the layout covers the viewport **and** the published page meets its content targets → `reading`;
    /// 8. the offer ended / transport failed → `reading` (a legitimate end of the wait);
    /// 9. no meaningful progress **and no media work pending** → `reading`;
    /// 10. the total ceiling expired → `reading` (never an endless page);
    /// 11. otherwise → `preparation`.
    ///
    /// `preparationShown` keeps a relaunch honest: when the window is already there on the first pass (a durable
    /// restore), no preparation surface was ever drawn, so there is no transition to hold. `requestedPreparation`
    /// is the host's opposite fact — a filter change is a new feed — and `filterPageShown` says that page has already
    /// been drawn once for this context.
    public static func surface(hasSources: Bool, isSearching: Bool, preparationShown: Bool,
        requestedPreparation: Bool = false, filterPageShown: Bool = false,
        cardCount: Int, coverage: FeedFirstScreenCoverage?, work: FeedPresentationState.Work,
        content: FeedFirstScreenContent = .empty,
        waited: Duration, maximumWait: Duration, ceilingExpired: Bool = false,
        alreadyExposed: Bool) -> FeedFirstScreenSurface {
        if !hasSources { return .sourcesEmpty }
        if isSearching { return .search }
        if alreadyExposed { return .reading }
        guard cardCount > 0 else { return .absence }
        guard preparationShown || requestedPreparation else { return .reading }
        if ceilingExpired {
            // The total ceiling bounds **every** hold, the filter page included: a new context that never manages a
            // drawing pass must not hold the reader past the run's own bound. It is the last legitimate exit.
            return .reading
        }
        if requestedPreparation, !filterPageShown {
            // The new feed's page is drawn **once** before the terminal exits or the content targets can release it:
            // the reader changed the selection, so the new feed's own page is what must appear, not the previous
            // feed's cards under a new lens. It is a real page with the new context's facts, and the store marks it
            // shown on the first drawing pass.
            return .preparation
        }
        switch work {
        case .endOfContent, .unreachable, .failed:
            // Both are legitimate ends of the wait: the offer stopped, or the transport proved a failure. What
            // exists is shown; the reader is never held behind a preparation for content that will not arrive.
            return .reading
        case .idle, .pending, .preparing, .unavailable, .deferred:
            break
        }
        let geometrySettled = coverage?.coversViewport ?? false
        if geometrySettled && !content.holdsForContent { return .reading }
        if waited >= maximumWait && !content.mediaPending && !content.supplyProducing {
            // The stall measures **meaningful progress**, media included: the clock is reset by a new card, a lower
            // bottom or a newly prepared image. It releases the page only when nothing is scheduled — no media work
            // **and no producer still fetching** — so a slower source answering behind an already-image-bearing
            // window cannot expose a one-source short buffer at the 5 s mark. A finished pipeline still releases
            // here (nothing more is coming), and the total ceiling remains the outer bound for everything else.
            return .reading
        }
        return .preparation
    }
}
