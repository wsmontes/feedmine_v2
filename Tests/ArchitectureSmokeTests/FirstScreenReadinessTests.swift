import CoreGraphics
import XCTest
import FeedMineRuntime
@testable import FeedMineUI

/// The first-screen decision: geometry first, then the **published page's** own content targets, and every exit
/// bounded by a fact the pipeline produced. These tests are the review's counterexamples written as decisions:
/// a three-card page with a producer active must keep buffering; a genuinely constrained feed must not be held for
/// sources or images it cannot have; an active media wait is not a stall; and the ceiling is the last honest exit.
final class FirstScreenReadinessTests: XCTestCase {
    private func coverage(covered: Bool, cards: Int = 4) -> FeedFirstScreenCoverage {
        FeedFirstScreenCoverage(laidOutCards: cards, contentBottom: covered ? 1000 : 300, viewportHeight: 1000)!
    }

    private func content(cards: Int, ahead: Int, providers: Int, eligible: Int, images: Int,
        page: Int = 12, declaresImages: Bool = true, pending: Bool = false, producing: Bool = true)
        -> FeedFirstScreenContent {
        FeedFirstScreenContent(publishedCards: cards, publishedAhead: ahead, distinctProviders: providers,
            eligibleProviders: eligible, imageCardsInFirstPage: images, firstPageCount: min(page, cards),
            declaresImages: declaresImages, mediaPending: pending, supplyProducing: producing)
    }

    private func surface(cards: Int, work: FeedPresentationState.Work = .idle, waited: Duration = .zero,
        preparationShown: Bool = true, requested: Bool = false, filterPageShown: Bool = true, covered: Bool = true,
        maximumWait: Duration = .seconds(5), ceilingExpired: Bool = false, alreadyExposed: Bool = false,
        content: FeedFirstScreenContent) -> FeedFirstScreenSurface {
        FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: preparationShown,
            requestedPreparation: requested, filterPageShown: filterPageShown, cardCount: cards,
            coverage: coverage(covered: covered), work: work,
            content: content, waited: waited, maximumWait: maximumWait, ceilingExpired: ceilingExpired,
            alreadyExposed: alreadyExposed)
    }

    /// Abundant supply, three published cards: the batch target is a hold, not a bypass — the reader keeps the page
    /// while the producer is filling the reserve floor.
    func testThreeCardsUnderAnActiveProducerHoldsForTheBuffer() {
        let decision = surface(cards: 3, work: .preparing(PreparationProgress(startedAt: 0)),
            content: content(cards: 3, ahead: 2, providers: 2, eligible: 4, images: 2))
        XCTAssertEqual(decision, .preparation)
    }

    /// The same three cards after every producer settled: buffering more is not something the pipeline is doing, so
    /// the stall releases the page with what exists (the ceiling is not reached).
    func testThreeCardsWithNoProducerLeftReleasesOnTheStall() {
        let decision = surface(cards: 3, work: .idle, waited: .seconds(6),
            content: content(cards: 3, ahead: 2, providers: 2, eligible: 4, images: 2, producing: false))
        XCTAssertEqual(decision, .reading)
    }

    /// A full page that meets every target is reading — no hold for its own sake.
    func testFullPageMeetingEveryTargetIsReading() {
        let decision = surface(cards: 34, content: content(cards: 34, ahead: 20, providers: 3, eligible: 4, images: 6))
        XCTAssertEqual(decision, .reading)
    }

    /// A genuinely constrained single-source feed is never held for a third provider: the target is capped by what
    /// the selection can contribute.
    func testSingleSourceContextIsNotHeldForMoreProviders() {
        let decision = surface(cards: 14, content: content(cards: 14, ahead: 13, providers: 1, eligible: 1,
            images: 6))
        XCTAssertEqual(decision, .reading)
    }

    /// A three-source selection with two contributing providers is held: the variety target applies when the
    /// selection can satisfy it.
    func testMultiSourceSelectionHoldsForTheThirdProvider() {
        let decision = surface(cards: 14, content: content(cards: 14, ahead: 13, providers: 2, eligible: 3,
            images: 6))
        XCTAssertEqual(decision, .preparation)
    }

    /// Images are counted on the published first page: four image cards are not enough for an image-bearing page.
    func testImageTargetHoldsBelowSixOnTheFirstPage() {
        let decision = surface(cards: 20, content: content(cards: 20, ahead: 16, providers: 3, eligible: 3,
            images: 4))
        XCTAssertEqual(decision, .preparation)
    }

    /// Six image cards on the first page satisfy it even when the window behind them is much larger.
    func testImageTargetSatisfiedBySixOfTheFirstTwelve() {
        let decision = surface(cards: 96, content: content(cards: 96, ahead: 80, providers: 3, eligible: 3,
            images: 6))
        XCTAssertEqual(decision, .reading)
    }

    /// A page whose context declares no images is text by design: it is never held for pixels.
    func testTextOnlyContextIsNotHeldForImages() {
        let decision = surface(cards: 20, content: content(cards: 20, ahead: 16, providers: 2, eligible: 2,
            images: 0, declaresImages: false))
        XCTAssertEqual(decision, .reading)
    }

    /// With fewer than six cards installed the image target is the page itself, not six.
    func testSmallPageIsNotHeldForImagesItCannotHave() {
        let decision = surface(cards: 4, work: .idle, waited: .seconds(6),
            content: content(cards: 4, ahead: 3, providers: 1, eligible: 1, images: 4, declaresImages: true,
                producing: false))
        XCTAssertEqual(decision, .reading)
    }

    /// An active media wait is real work: the stall clock cannot release the page while it is pending.
    func testActiveMediaWaitIsNotAStall() {
        let decision = surface(cards: 20, waited: .seconds(30),
            content: content(cards: 20, ahead: 10, providers: 3, eligible: 3, images: 3, pending: true))
        XCTAssertEqual(decision, .preparation)
    }

    /// The total ceiling ends the hold even with media still pending — the last legitimate exit.
    func testTotalCeilingEndsTheHoldEvenWithMediaPending() {
        let decision = surface(cards: 20, waited: .seconds(31), ceilingExpired: true,
            content: content(cards: 20, ahead: 10, providers: 3, eligible: 3, images: 3, pending: true))
        XCTAssertEqual(decision, .reading)
    }

    /// A legitimate end of the offer releases the page: every target is moot once the offer ended.
    func testEndOfContentReleasesThePage() {
        let decision = surface(cards: 20, work: .endOfContent,
            content: content(cards: 20, ahead: 4, providers: 1, eligible: 3, images: 1, pending: true))
        XCTAssertEqual(decision, .reading)
    }

    /// A proven transport failure releases too: the reader sees what exists with the failure stated.
    func testTransportFailureReleasesThePage() {
        let decision = surface(cards: 6, work: .unreachable,
            content: content(cards: 6, ahead: 5, providers: 1, eligible: 3, images: 2, pending: true))
        XCTAssertEqual(decision, .reading)
    }

    /// A filter change is a **new feed**: its page is drawn at least once, even when the new context restored an
    /// Edition it already had — the `preparationShown=false` shortcut (which exists for a relaunch) must not swallow
    /// the request, and a cached page must not appear under the previous feed.
    func testFilterChangeDrawsItsPageOnceEvenOverACachedEdition() {
        let decision = surface(cards: 34, work: .idle, preparationShown: false, requested: true,
            filterPageShown: false,
            content: content(cards: 34, ahead: 20, providers: 3, eligible: 4, images: 6))
        XCTAssertEqual(decision, .preparation)
    }

    /// Once that page has been drawn, an Edition that already meets every target is shown at once: the request is
    /// honoured, and the reader is not held behind a page for content that is already there.
    func testFilterChangePageLeavesOnceItWasDrawn() {
        let decision = surface(cards: 34, work: .idle, preparationShown: false, requested: true,
            filterPageShown: true,
            content: content(cards: 34, ahead: 20, providers: 3, eligible: 4, images: 6))
        XCTAssertEqual(decision, .reading)
    }

    /// While the new feed is still being made, the page stays: the request does not expire with the first pass.
    func testFilterChangePageStaysWhileItsContentIsNotReady() {
        let decision = surface(cards: 12, work: .preparing(PreparationProgress(startedAt: 0)),
            preparationShown: false, requested: true, filterPageShown: true,
            content: content(cards: 12, ahead: 4, providers: 2, eligible: 3, images: 3, pending: true))
        XCTAssertEqual(decision, .preparation)
    }

    /// A filter change whose new context ends immediately still draws **its** page once. The terminal exits are
    /// about the content the reader ends up seeing, not about skipping the new feed's page: releasing first showed
    /// the previous feed's cards under a new lens.
    func testFilterChangePagePrecedesATerminalWorkState() {
        let decision = surface(cards: 3, work: .endOfContent, preparationShown: false, requested: true,
            filterPageShown: false,
            content: content(cards: 3, ahead: 2, providers: 1, eligible: 1, images: 0, declaresImages: false,
                producing: false))
        XCTAssertEqual(decision, .preparation)
    }

    /// Once that page was drawn, the terminal state releases it: no endless hold over an offer that already ended.
    func testTerminalWorkReleasesAfterTheFilterPageWasDrawn() {
        let decision = surface(cards: 3, work: .endOfContent, preparationShown: false, requested: true,
            filterPageShown: true,
            content: content(cards: 3, ahead: 2, providers: 1, eligible: 1, images: 0, declaresImages: false,
                producing: false))
        XCTAssertEqual(decision, .reading)
    }

    /// The total ceiling bounds the filter page too: a new context that never manages a drawing pass cannot hold
    /// the reader past the run's own bound.
    func testCeilingBoundsTheFilterPage() {
        let decision = surface(cards: 3, work: .preparing(PreparationProgress(startedAt: 0)),
            preparationShown: false, requested: true, filterPageShown: false, ceilingExpired: true,
            content: content(cards: 3, ahead: 1, providers: 1, eligible: 1, images: 0, declaresImages: false,
                pending: true))
        XCTAssertEqual(decision, .reading)
    }

    /// A publication of twelve cards whose producers are all finished is read at once: the buffer target cannot be
    /// met by a feed that has nothing more to send, and the reader must not pay the ceiling for it.
    func testLimitedSupplyThatFinishedIsReadAtOnce() {
        let decision = surface(cards: 12, work: .idle, waited: .seconds(6),
            content: content(cards: 12, ahead: 11, providers: 2, eligible: 2, images: 6, producing: false))
        XCTAssertEqual(decision, .reading)
    }

    /// The same twelve cards while a slower source is still answering hold the buffer: the producer fact is what
    /// separates a small feed from a delayed one.
    func testLimitedSupplyWithASlowerSourceStillAnsweringHolds() {
        let decision = surface(cards: 12, work: .preparing(PreparationProgress(startedAt: 0)),
            content: content(cards: 12, ahead: 11, providers: 2, eligible: 2, images: 6, producing: true))
        XCTAssertEqual(decision, .preparation)
    }

    /// An active producer keeps the page past the stall even when no media is pending: a slower source still
    /// fetching would otherwise expose a one-source short buffer at the 5 s mark.
    func testAnActiveProducerHoldsPastTheStallWithoutMediaWork() {
        let decision = surface(cards: 12, work: .preparing(PreparationProgress(startedAt: 0)),
            waited: .seconds(6),
            content: content(cards: 12, ahead: 4, providers: 1, eligible: 3, images: 6, pending: false,
                producing: true))
        XCTAssertEqual(decision, .preparation)
    }

    /// The same page once every producer finished: nothing more can arrive, so the stall releases it.
    func testAFinishedProducerReleasesOnTheStall() {
        let decision = surface(cards: 12, work: .idle, waited: .seconds(6),
            content: content(cards: 12, ahead: 4, providers: 1, eligible: 3, images: 6, pending: false,
                producing: false))
        XCTAssertEqual(decision, .reading)
    }

    /// The total ceiling still bounds an active producer: no page can outlive the run's own bound.
    func testTheCeilingBoundsAnActiveProducer() {
        let decision = surface(cards: 12, work: .preparing(PreparationProgress(startedAt: 0)),
            waited: .seconds(31), ceilingExpired: true,
            content: content(cards: 12, ahead: 4, providers: 1, eligible: 3, images: 6, pending: false,
                producing: true))
        XCTAssertEqual(decision, .reading)
    }

    /// An ordinary relaunch that already has its window is immediate: no page, no wait.
    func testOrdinaryResumeWithAnInstalledWindowIsImmediate() {
        let decision = surface(cards: 34, preparationShown: false, requested: false,
            content: content(cards: 34, ahead: 20, providers: 3, eligible: 4, images: 6))
        XCTAssertEqual(decision, .reading)
    }

    /// Geometry keeps its own rule: a page that meets its content targets but does not fill the viewport still
    /// waits.
    func testGeometryStillDecidesIndependentlyOfContent() {
        let decision = surface(cards: 20, covered: false,
            content: content(cards: 20, ahead: 16, providers: 3, eligible: 3, images: 6))
        XCTAssertEqual(decision, .preparation)
    }

    /// No cards is the absence surface, never a preparation.
    func testNoCardsIsAbsence() {
        XCTAssertEqual(surface(cards: 0, content: .empty), .absence)
    }

    /// The reading surface is never taken back.
    func testAlreadyExposedIsReading() {
        let decision = surface(cards: 3, alreadyExposed: true,
            content: content(cards: 3, ahead: 2, providers: 1, eligible: 3, images: 0))
        XCTAssertEqual(decision, .reading)
    }

    /// An empty selection is its own surface, before any hold.
    func testNoSourcesIsTheEmptySurface() {
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: false, isSearching: false, preparationShown: true,
            cardCount: 0, coverage: nil, work: .idle, content: .empty, waited: .zero, maximumWait: .seconds(5),
            alreadyExposed: false), .sourcesEmpty)
    }

    /// The publication batch (32) is not a hold: the admitted window can only project ≤25 cards, so a gate that
    /// waited for 32 window cards would be a 30 s wait by construction. It is recorded as a target and judged where
    /// it is achievable — the bootstrap's publication limit.
    func testPublicationBatchIsNotAHoldOnTheWindow() {
        let facts = content(cards: 20, ahead: 16, providers: 3, eligible: 3, images: 6, producing: true)
        XCTAssertFalse(facts.batchReached, "20 window cards are not the 32-card publication batch")
        XCTAssertFalse(facts.holdsForContent, "but the batch is not a reason to hold the page")
        XCTAssertEqual(surface(cards: 20, content: facts), .reading)
    }
}
