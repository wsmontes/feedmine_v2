// File: FirstScreenPresentationTests.swift
// Target: FeedMineCompositionTests
//
// Responsibility:
//   Judge the rule that holds the preparation surface until the first screen's **measured layout** fills the
//   viewport (D4, PD-2026-10-20), and every legitimate way out of that wait.
//
// Does not own:
//   The measurement (FeedScreen reports what the layout produced), rendering, publication, admission or the app's
//   UI journey. This target only exercises the pure decision.
//
// Why it lives here: `FeedFirstScreenGate` is the one place the transition is decided, so the failing-before /
// passing-after evidence can be a unit test instead of a screenshot. Before it existed, `FeedScreen` yielded on the
// first non-empty window — the first card was enough — and the first screen the owner saw carried one card 589 pt
// above the viewport bottom (docs/reviews/evidence/2026-10-20-first-screen/).
//

import XCTest
@testable import FeedMineUI
import FeedMineRuntime

@MainActor
final class FirstScreenPresentationTests: XCTestCase {
    /// The height the measured fixture card had in the recorded red run (`content_bottom=141` of `viewport_height=730`).
    private let recordedCardBottom: CGFloat = 141
    private let recordedViewport: CGFloat = 730
    /// The spacing between cards in the list the reader sees (`FeedScreen`'s `LazyVStack` spacing). Stated here so
    /// the fixtures below are built by the project's own composition rule — slot heights plus the list's spacing —
    /// instead of by numbers that only look like a layout.
    private var cardSpacing: CGFloat { FeedDesignTokens.Spacing.section }

    private var preparing: FeedPresentationState.Work { .preparing(PreparationProgress(startedAt: 0)) }

    /// A layout of `heights` stacked in list order, starting `topInset` points below the viewport's top. The bottom
    /// is the last card's own bottom, in viewport coordinates — the same quantity `FeedScreen` measures.
    private func layout(_ heights: [CGFloat], topInset: CGFloat = 0) -> CGFloat {
        heights.enumerated().reduce(topInset) { bottom, pair in
            bottom + pair.element + (pair.offset == 0 ? 0 : cardSpacing)
        }
    }

    private func coverage(_ heights: [CGFloat], viewport: CGFloat, topInset: CGFloat = 0) throws -> FeedFirstScreenCoverage {
        try XCTUnwrap(FeedFirstScreenCoverage(laidOutCards: heights.count,
            contentBottom: layout(heights, topInset: topInset), viewportHeight: viewport))
    }

    // MARK: - The first exposure is judged by the layout

    /// **The failing-before case.** One card was that whole first screen: measured, it fills 141 pt of 730. The
    /// old rule (any card ⇒ reading) exposed exactly this. The gate must hold the preparation over it.
    func testTheRecordedOneCardFirstScreenIsNotExposed() throws {
        let measured = try XCTUnwrap(FeedFirstScreenCoverage(laidOutCards: 1,
            contentBottom: recordedCardBottom, viewportHeight: recordedViewport))
        XCTAssertFalse(measured.coversViewport, "one 141 pt card cannot fill a 730 pt viewport")

        let surface = FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: measured, work: preparing, waited: .seconds(1),
            maximumWait: .seconds(5), alreadyExposed: false)
        XCTAssertEqual(surface, .preparation,
            "the first card is not a first screen: the preparation surface holds until the layout fills the viewport")
    }

    /// The composition rule is geometry: the bottom of the last laid-out card reaches the viewport bottom within the
    /// project's 1 pt tolerance. Slot heights and the list's spacing are what the measurement carries.
    func testTheTransitionHappensAtTheViewportBottomWithinTheProjectsTolerance() throws {
        let fills = try coverage([300, 413], viewport: 730) // 300 + 16 + 413 = 729 ≥ 730 − 1
        XCTAssertTrue(fills.coversViewport)
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 2, coverage: fills, work: preparing, waited: .seconds(1), maximumWait: .seconds(5),
            alreadyExposed: false), .reading)

        let justShort = try coverage([300, 412], viewport: 730) // 728 < 729
        XCTAssertFalse(justShort.coversViewport)
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 2, coverage: justShort, work: preparing, waited: .seconds(1), maximumWait: .seconds(5),
            alreadyExposed: false), .preparation,
            "the rule is the measured bottom with the project's 1 pt tolerance, not an approximate fill")
    }

    /// The count is not the rule. One tall card fills the screen; twelve short ones do not.
    func testTheDecisionIsTheLayoutAndNeverACardCount() throws {
        let oneTallCard = try coverage([800], viewport: 730)
        XCTAssertEqual(oneTallCard.laidOutCards, 1)
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: oneTallCard, work: preparing, waited: .zero, maximumWait: .seconds(5),
            alreadyExposed: false), .reading)

        let twelveShortCards = try coverage(Array(repeating: 40, count: 12), viewport: 730) // 12×40 + 11×16 = 656
        XCTAssertEqual(twelveShortCards.laidOutCards, 12)
        XCTAssertFalse(twelveShortCards.coversViewport)
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 12, coverage: twelveShortCards, work: preparing, waited: .zero, maximumWait: .seconds(5),
            alreadyExposed: false), .preparation,
            "a card count threshold would have exposed this layout; the geometry says it is still short")
    }

    /// The sequence a cold launch really walks, judged at every step: the reading surface first appears only when
    /// the layout it is carrying covers the viewport. This is the "first exposure" assertion in unit form — the
    /// card-carrying state that produced the recorded red run is held, and the exposure that follows is full.
    func testTheFirstExposureHappensOnlyWhenTheCarriedLayoutCoversTheViewport() throws {
        let steps: [(cards: Int, heights: [CGFloat])] = [
            (1, [recordedCardBottom]),      // the first segment: one short card
            (3, [141, 141, 141]),           // growing under the cover
            (5, [141, 141, 141, 141, 141])  // 5×141 + 4×16 = 769 ≥ 730 − 1
        ]
        var exposed: [CGFloat] = []
        for step in steps {
            let measured = try coverage(step.heights, viewport: recordedViewport)
            let surface = FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
                cardCount: step.cards, coverage: measured, work: preparing, waited: .seconds(1),
                maximumWait: .seconds(5), alreadyExposed: !exposed.isEmpty)
            if surface == .reading { exposed.append(measured.contentBottom) }
        }
        XCTAssertEqual(exposed, [layout([141, 141, 141, 141, 141])],
            "exactly one exposure, and it is the layout that covers the viewport")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(exposed.first), recordedViewport - FeedFirstScreenCoverage.tolerancePoints)
    }

    /// A durable restore appears with its cards already on screen: no preparation surface was drawn, so there is no
    /// transition to hold and the reading surface is shown at once (the reopen criterion).
    func testARestoreIsShownAtOnceBecauseNothingWasPrepared() {
        let surface = FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: false,
            cardCount: 3, coverage: nil, work: .idle, waited: .zero, maximumWait: .seconds(5), alreadyExposed: false)
        XCTAssertEqual(surface, .reading)
    }

    /// Once the reader's cards are on screen the reading surface is never taken back — a window that grows, a
    /// context that rebuilds, or an under-filled measurement later is not a reason to draw the preparation again.
    func testTheReadingSurfaceIsNeverTakenBack() {
        let surface = FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: nil, work: preparing, waited: .zero, maximumWait: .seconds(5), alreadyExposed: true)
        XCTAssertEqual(surface, .reading)
    }

    // MARK: - Every legitimate exit reaches a surface

    /// The eligible offer ended: the reader sees what exists, with the end block after the last card. No wait.
    func testOfferExhaustedShowsWhatExists() {
        let surface = FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 2, coverage: nil, work: .endOfContent, waited: .zero, maximumWait: .seconds(5),
            alreadyExposed: false)
        XCTAssertEqual(surface, .reading)
    }

    /// A proven transport failure and the generic failure both end the wait: what exists is shown, and the work
    /// badge states the failure. The reader is not held behind a preparation for content that will not arrive.
    func testOfflineAndFailureShowWhatExists() {
        for work in [FeedPresentationState.Work.unreachable, .failed(message: "Falha ao atualizar o feed")] {
            let surface = FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
                cardCount: 1, coverage: nil, work: work, waited: .zero, maximumWait: .seconds(5),
                alreadyExposed: false)
            XCTAssertEqual(surface, .reading, "\(work) must reach the reader's surface immediately")
        }
    }

    /// The bounded wait ends the **unquestioned** wait, not an honest preparation while the pipeline is running.
    /// The recorded D4 run exposed one 166 pt card at 9.9 s with the work badge still `.preparing`; the bound had
    /// elapsed at ~5 s and turned the first card into a "first screen". While work is pending/preparing the
    /// preparation keeps its real progress; idle/terminal work still ends the wait with what exists.
    func testTheBoundedWaitDoesNotExposeAPipelineThatIsStillPreparing() {
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: nil, work: preparing, waited: .milliseconds(4_999), maximumWait: .seconds(5),
            alreadyExposed: false), .preparation)
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: nil, work: preparing, waited: .seconds(5), maximumWait: .seconds(5),
            alreadyExposed: false), .preparation,
            "a card measured while the pipeline is still preparing is not the first screen")
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: nil, work: preparing, waited: .seconds(30), maximumWait: .seconds(5),
            alreadyExposed: false), .preparation,
            "the honest preparation keeps its real progress while the pipeline is running")

        // No work behind the wait: the bounded exit still happens, so a launch cannot sit in preparation forever.
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: nil, work: .idle, waited: .seconds(5), maximumWait: .seconds(5),
            alreadyExposed: false), .reading)
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: nil, work: .deferred, waited: .seconds(12.5), maximumWait: .seconds(12.5),
            alreadyExposed: false), .reading)

        // A long `.preparing` is still the pipeline's fact, not the gate's clock: the gate does not invent a second
        // deadline and expose a card the pipeline is still filling. The hold ends when the same work reports idle or
        // terminal; the bootstrap's acquisition is the bounded work (`ColdFeedBootstrap.run` awaits it, each pull has
        // its transport timeout). An acquisition that never returns would hold the preparation: that is a pipeline
        // defect, stated as a residual risk, not hidden by a magic gate threshold.
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: nil, work: preparing, waited: .seconds(600), maximumWait: .seconds(5),
            alreadyExposed: false), .preparation)
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: nil, work: .endOfContent, waited: .seconds(600), maximumWait: .seconds(5),
            alreadyExposed: false), .reading)
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
            cardCount: 1, coverage: nil, work: .failed(message: "X"), waited: .seconds(600), maximumWait: .seconds(5),
            alreadyExposed: false), .reading)
    }

    /// Nothing to lay out: the surface is the app's existing loading/failure surface — a surface with the work
    /// state's own copy and its recovery action, never a spinner that waits forever for a measurement that cannot
    /// come.
    func testNoCardsDrawTheExistingSurfaceForEveryWorkState() {
        for work in [FeedPresentationState.Work.idle, preparing, .unavailable, .deferred, .unreachable,
            .failed(message: "Falha ao atualizar o feed"), .endOfContent] {
            let surface = FeedFirstScreenGate.surface(hasSources: true, isSearching: false, preparationShown: true,
                cardCount: 0, coverage: nil, work: work, waited: .seconds(20), maximumWait: .seconds(5),
                alreadyExposed: false)
            XCTAssertEqual(surface, .absence, "\(work) with no cards draws the existing absence surface")
        }
    }

    /// Neither an empty selection nor a search is a wait: both are surfaces of their own.
    func testEmptySelectionAndSearchAreNotWaits() {
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: false, isSearching: false, preparationShown: true,
            cardCount: 4, coverage: nil, work: .idle, waited: .zero, maximumWait: .seconds(5),
            alreadyExposed: false), .sourcesEmpty)
        XCTAssertEqual(FeedFirstScreenGate.surface(hasSources: true, isSearching: true, preparationShown: true,
            cardCount: 1, coverage: nil, work: preparing, waited: .zero, maximumWait: .seconds(5),
            alreadyExposed: false), .search)
    }

    // MARK: - The measured value itself

    func testCoverageRejectsMeasurementsThatAreNotLayout() {
        XCTAssertNil(FeedFirstScreenCoverage(laidOutCards: 0, contentBottom: 730, viewportHeight: 730),
            "no distinct card was laid out")
        XCTAssertNil(FeedFirstScreenCoverage(laidOutCards: 1, contentBottom: 730, viewportHeight: 0),
            "an unmeasured viewport cannot judge a layout")
        XCTAssertNil(FeedFirstScreenCoverage(laidOutCards: 1, contentBottom: .nan, viewportHeight: 730))
        XCTAssertNil(FeedFirstScreenCoverage(laidOutCards: 1, contentBottom: 730, viewportHeight: -1))
    }

    func testADeeperLayoutThanTheViewportStillCoversIt() throws {
        let deep = try coverage([400, 400, 400], viewport: 730)
        XCTAssertTrue(deep.coversViewport, "content past the viewport bottom covers it")
        XCTAssertEqual(deep.laidOutCards, 3)
    }
}
