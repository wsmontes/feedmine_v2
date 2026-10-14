import XCTest

/// PO 2026-10-14: the end of the reader's eligible offer is **drawn**, not announced. It is the last child of
/// the feed list — after the last published card — with the ratified sentence and the three routes, and it
/// never replaces the screen or moves anything above it.
///
/// The evidence is injected by the DEBUG hook `FEEDMINE_END_ELIGIBLE_OFFER`: no single run exhausts the corpus,
/// so the *settlement* is fabricated while the rule, the handoff, the store and the surface are the product's
/// own. That is the difference between this and the rendering unit test — this is a journey over the real screen.
final class EndOfContentUITests: XCTestCase {
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "6"
        app.launchEnvironment["FEEDMINE_END_ELIGIBLE_OFFER"] = "1"
        app.launch()
        return app
    }

    /// Every publication card the surface has laid out, wherever it is: each card carries its own identity.
    private func cardFrames(_ app: XCUIApplication) -> [CGRect] {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@",
                "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
            .allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 40 }
            .map { $0.frame }
    }

    func testTheEndIsDrawnAfterTheLastCardWithTheThreeRoutes() throws {
        let app = launched()
        let feed = app.scrollViews.firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 180), "the feed opens with the reader's own content")

        let end = app.otherElements["feed-end-of-content"]
        for _ in 0..<40 where !end.exists {
            feed.swipeUp()
        }
        XCTAssertTrue(end.waitForExistence(timeout: 30),
            "the end of the eligible offer is drawn after the last card")

        XCTAssertTrue(app.staticTexts["feed-end-message"].exists, "the ratified sentence is shown")
        for identifier in ["feed-end-explore-subjects", "feed-end-widen-sources",
            "feed-end-return-to-start"] {
            XCTAssertTrue(app.buttons[identifier].exists, "the route \(identifier) is offered")
        }

        // It is *after* the last card: every laid-out card sits above the block, and nothing was retracted.
        let block = app.otherElements["feed-end-of-content"].frame
        let cards = cardFrames(app)
        XCTAssertFalse(cards.isEmpty, "the cards the reader already had are still drawn")
        XCTAssertLessThanOrEqual(cards.map(\.maxY).max() ?? 0, block.minY + 1,
            "the block is drawn after the last card — never in the middle and never above one")

        // "Voltar ao início" moves the reading position back to what the reader already had.
        app.buttons["feed-end-return-to-start"].tap()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(app.otherElements["feed-end-of-content"].isHittable,
            "the route takes the reader away from the end, without rebuilding the session")
    }
}
