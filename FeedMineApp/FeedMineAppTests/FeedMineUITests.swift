import XCTest

final class FeedMineUITests: XCTestCase {
    // N1/N2: the test never constructs ViewportObservation or calls submitViewport.
    @MainActor
    func testContextNavigationAndSourcePickerOffline() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
        app.terminate()
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 15))
        app.buttons["reader-contexts"].tap()
        app.buttons["BBC Science"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 15))
        app.buttons["reader-contexts"].tap()
        app.buttons["Principal"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 15))
        app.buttons["reader-sources"].tap()
        XCTAssertTrue(app.navigationBars["Fontes"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'source-choice-'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Concluir"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testNativeSwipeReachesRealRunwayAndReverseNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        XCTAssertEqual(proof.label, "received=0 completed=0 backward=0", "Restore/layout is not a native user observation")
        app.swipeUp()
        let delivered = NSPredicate(format: "label MATCHES %@", ".*completed=[1-9][0-9]*.*")
        let forward = XCTNSPredicateExpectation(predicate: delivered, object: proof)
        let result = XCTWaiter.wait(for: [forward], timeout: 15)
        XCTAssertEqual(result, .completed, "N1/N2 real swipe must complete a real driver opportunity; observed: \(proof.label)")
        guard result == .completed else { return }
        app.swipeUp()
        app.swipeDown()
        let backward = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*backward=[1-9][0-9]*.*"), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [backward], timeout: 15), .completed,
            "N11 reverse gesture must reach the same real driver")
    }

    @MainActor
    func testRealRSSNavigationLifecycleAndNetworkBlockedRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 45), "A real published occurrence must appear")
        let before = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(before.isEmpty)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "real-rss-launch"
        attachment.lifetime = .keepAlways
        add(attachment)
        scroll.swipeUp(velocity: .slow)
        scroll.swipeUp(velocity: .fast)
        scroll.swipeDown(velocity: .slow)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        app.terminate()
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "Local cards must restore without network")
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        app.scrollViews.firstMatch.swipeDown(velocity: .slow)
        let reopened = XCTAttachment(screenshot: app.screenshot())
        reopened.name = "network-blocked-local-reopen"
        reopened.lifetime = .keepAlways
        add(reopened)
    }
}
