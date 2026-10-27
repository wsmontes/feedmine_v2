//
// File: ReaderSheetDismissalUITests.swift
// Module: FeedMineUITests
//
// The reader sheet's gestures, on the device, on both pages it draws:
//
//   * a deliberate pull at the top dismisses it, and the feed returns to the **exact** card and position it was
//     opened from (`anchor` is the product's sacred fact, T9/U2);
//   * a page scrolled down is **not** dismissed by scrolling back up — the reader keeps reading;
//   * the visible close control is still there and still works (the existing journeys depend on it);
//   * the publisher's page is read inside the same sheet, in the app's own web view, and it obeys the same rule.
//
// Nothing here reaches the network: the app's own fixture feed supplies the cards, and for the web page the app
// serves its fixture document (`FEEDMINE_READER_WEB_FIXTURE=1`) for the fixture feed's own addresses. The address
// is the card's; no URL is rewritten.
import XCTest

@MainActor
final class ReaderSheetDismissalUITests: XCTestCase {
    private static let cardIdentifier = NSPredicate(format: "identifier MATCHES %@",
        "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    // MARK: - Launch

    /// The hermetic run: the app's own fixture feed, no network, no discovery, no onboarding. The text shape picks
    /// the card's own reading target (`body` → the text the app holds, `shortSummary` → the site).
    private func launched(shape: String, webFixture: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_TEXT"] = shape
        if webFixture { app.launchEnvironment["FEEDMINE_READER_WEB_FIXTURE"] = "1" }
        app.launch()
        return app
    }

    // MARK: - Queries

    private func byIdentifier(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A card the reader can really act on: its opening control is hittable and the card is inside the window.
    private func visibleCard(_ app: XCUIApplication) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 40 && $0.frame.intersects(window) }
            .first { card in
                let control = card.buttons["card.open"].firstMatch
                return control.exists && control.isHittable
            }
    }

    /// Opens the first card the feed presents and returns its identity and frame, so the return can be measured on
    /// the same surface the reader left.
    private func openTheFirstCard(_ app: XCUIApplication) -> (identity: String, frame: CGRect)? {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, visibleCard(app) == nil { Thread.sleep(forTimeInterval: 1) }
        guard let card = visibleCard(app) else {
            XCTFail("the fixture feed publishes cards")
            return nil
        }
        let identity = card.identifier
        let frame = card.frame
        let control = card.buttons["card.open"].firstMatch
        if control.exists && control.isHittable { control.tap() } else { card.tap() }
        return (identity, frame)
    }

    /// The text page and the publisher's page are two surfaces of one sheet. Either being up is "the reader is
    /// up"; the assertions below name which one they expect.
    private func readerIsUp(_ app: XCUIApplication) -> Bool {
        byIdentifier(app, "reading.body").exists || byIdentifier(app, "reading.web").exists
    }

    private func waitForReaderToGo(_ app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !readerIsUp(app) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !readerIsUp(app)
    }

    private func waitForReader(_ app: XCUIApplication, _ identifier: String,
        timeout: TimeInterval = 30) -> Bool {
        byIdentifier(app, identifier).waitForExistence(timeout: timeout)
    }

    /// The reader's own gesture, repeated: a first downward drag may only return a scrolled page to its top — and
    /// that is exactly what must *not* dismiss. The run continues until the sheet is really gone or the attempts
    /// are spent, and the caller asserts which happened.
    private func pullDownUntilDismissed(_ app: XCUIApplication, attempts: Int = 4) -> Bool {
        for _ in 0..<attempts {
            if !readerIsUp(app) { return true }
            app.swipeDown(velocity: .fast)
            if waitForReaderToGo(app, timeout: 3) { return true }
        }
        return !readerIsUp(app)
    }

    /// The anchor: the same card, at the same height, once the sheet is gone. One point is the measured tolerance
    /// the rest of the reader journeys use.
    private func assertSameAnchor(_ app: XCUIApplication, identity: String, frame: CGRect) {
        let card = byIdentifier(app, identity)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the card the reader left is still there")
        XCTAssertEqual(card.frame.minY, frame.minY, accuracy: 1.0,
            "the reader sheet never moved the feed: the exact card is at the exact position it was opened from")
    }

    // MARK: - The text page

    /// A page scrolled down is not dismissed by scrolling back up, and a deliberate pull at the top is. The two
    /// halves are one journey on purpose: the second only means something after the first has left the page
    /// scrolled.
    func testAScrolledLocalPageIsNotDismissedAndAPullAtItsTopIs() throws {
        let app = launched(shape: "body")
        defer { app.terminate() }
        guard let (identity, frame) = openTheFirstCard(app) else { return }

        XCTAssertTrue(waitForReader(app, "reading.body"), "a stored body opens the text page")
        XCTAssertTrue(byIdentifier(app, "reading.close").exists,
            "the visible close control is kept, whatever the gesture does")
        attach(app, "local-reader-sheet")

        // Scroll down through the text. That is a reader reading, not a dismissal.
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(readerIsUp(app), "scrolling down never dismisses the reader")

        // Now drag back up: a normal scroll from inside the article. It must not dismiss either.
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(readerIsUp(app),
            "a page scrolled down is not dismissed by a normal downward scroll")
        XCTAssertTrue(byIdentifier(app, "reading.body").exists,
            "the text is still the page the reader is on")
        attach(app, "local-reader-scrolled-not-dismissed")

        // At the top, a deliberate pull is the dismissal.
        XCTAssertTrue(pullDownUntilDismissed(app),
            "a deliberate pull at the top dismisses the reader sheet")
        XCTAssertTrue(waitForReaderToGo(app), "and the reader is gone")
        assertSameAnchor(app, identity: identity, frame: frame)
        attach(app, "local-reader-returned-to-the-same-anchor")
    }

    /// The existing path the rest of the suite uses: the visible close control. It is not replaced by the gesture;
    /// both end at the same finish.
    func testTheCloseControlStillEndsTheReaderAndKeepsTheAnchor() throws {
        let app = launched(shape: "body")
        defer { app.terminate() }
        guard let (identity, frame) = openTheFirstCard(app) else { return }
        XCTAssertTrue(waitForReader(app, "reading.body"))

        let close = byIdentifier(app, "reading.close")
        XCTAssertTrue(close.isHittable, "the close control is on screen")
        close.tap()

        XCTAssertTrue(waitForReaderToGo(app), "the close control ends the reader")
        assertSameAnchor(app, identity: identity, frame: frame)
    }

    // MARK: - The publisher's page

    /// The site is read in an in-app web view inside the sheet, and the same rule applies: scrolled down it does
    /// not dismiss; at its top a deliberate pull does. The page is the app's own long fixture, so the scroll is
    /// real and no network is involved.
    func testThePublisherPageScrollsWithoutDismissingAndPullsDownAtItsTop() throws {
        let app = launched(shape: "shortSummary", webFixture: true)
        defer { app.terminate() }
        guard let (identity, frame) = openTheFirstCard(app) else { return }

        XCTAssertTrue(waitForReader(app, "reading.web", timeout: 40),
            "a teaser opens the publisher's page in the app's own web view")
        XCTAssertTrue(byIdentifier(app, "reading.close").exists, "the sheet keeps its close control")
        XCTAssertEqual(byIdentifier(app, "reading.web-source").label, "example.test",
            "the page names the site the card carries")
        attach(app, "web-reader-sheet")

        let state = byIdentifier(app, "reader-web-state")
        XCTAssertTrue(state.waitForExistence(timeout: 10), "the page reports where it is")
        XCTAssertEqual(state.label, "atTop=1", "the page starts at its top")

        // Scroll down the page: the fixture is long enough for the scroll to be real.
        app.swipeUp()
        XCTAssertTrue(waitForLabel(state, "atTop=0", timeout: 10),
            "the page really scrolled away from its top")
        XCTAssertTrue(readerIsUp(app), "scrolling the page never dismisses the reader")
        assertWebHeaderIsVisible(app)

        // A normal downward scroll from inside the page. The reader keeps reading.
        app.swipeDown()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(readerIsUp(app),
            "a publisher page scrolled down is not dismissed by a normal downward scroll")
        XCTAssertTrue(byIdentifier(app, "reading.web").exists)
        attach(app, "web-reader-scrolled-not-dismissed")
        let physicalScreen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        physicalScreen.name = "reader-web-physical-screen"
        physicalScreen.lifetime = .keepAlways
        add(physicalScreen)
        assertWebHeaderIsVisible(app)

        // Back at the top, the deliberate pull dismisses — and the feed is where it was.
        XCTAssertTrue(pullDownUntilDismissed(app),
            "a deliberate pull at the page's top dismisses the reader sheet")
        XCTAssertTrue(waitForReaderToGo(app), "and the reader is gone")
        assertSameAnchor(app, identity: identity, frame: frame)
        attach(app, "web-reader-returned-to-the-same-anchor")
    }

    /// Header controls must stay visible above the web viewport, not merely remain in the accessibility tree.
    private func assertWebHeaderIsVisible(_ app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let viewport = byIdentifier(app, "reading.web").frame
        XCTAssertFalse(window.isEmpty, "the app has a visible window")
        XCTAssertFalse(viewport.isEmpty, "the publisher page has a visible viewport")
        for identifier in ["reading.close", "reading.web-source"] {
            let control = byIdentifier(app, identifier)
            XCTAssertTrue(control.isHittable, "\(identifier) remains reachable after scrolling")
            let frame = control.frame
            XCTAssertFalse(frame.isEmpty, "\(identifier) has visible bounds")
            XCTAssertTrue(window.contains(frame), "\(identifier) stays fully inside the app window")
            XCTAssertLessThanOrEqual(frame.maxY, viewport.minY,
                "\(identifier) stays above the web viewport, not behind web content")
        }
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label == label { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return element.exists && element.label == label
    }
}
