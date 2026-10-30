//
// File: ReadingSurfaceUITests.swift
// Module: FeedMineUITests
//
// The architect's verification for the local reading surface, on the device: the four text shapes, the metadata,
// Dynamic Type, the app's network blocked, the position re-measured *on this surface*, and the explicit request
// for the site kept apart from the feed's own work.
//
// It drives the app's own fixture (`FEEDMINE_FIXTURE_TEXT` picks the shape), so nothing here needs the internet —
// and one case runs with the app's real transport blocked outright, which is what "connectivity really
// unavailable" means for a physical device.
import XCTest

@MainActor
final class ReadingSurfaceUITests: XCTestCase {
    private static let cardIdentifier = NSPredicate(format: "identifier MATCHES %@",
        "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")

    /// A real namespace from this session's acceptance runs: it holds 173 published cards, stored by earlier runs
    /// (including articles whose source published thousands of characters). It is what the offline proof opens.
    private static let readerWithContent = "3E1B4C1A-6F2D-4A5B-9C7E-8D5A2F0B7C31"

    private func byIdentifier(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// A run whose only supply is the app's own local fixtures: the development feeds served in process, so there
    /// is no network, no server, no clock — and no add-feed sheet in the way of reaching an article.
    private func launched(shape: String, blocked: Bool = false, largeText: Bool = false,
        itemsPerFeed: Int? = nil, safariDiagnostic: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_TEXT"] = shape
        if let itemsPerFeed { app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = String(itemsPerFeed) }
        if safariDiagnostic { app.launchEnvironment["FEEDMINE_SAFARI_DIAGNOSTIC"] = "1" }
        // The closed HTTPS proxy the app itself installs: real connections fail, the fixture still answers.
        if blocked { app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1" }
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func visibleCard(_ app: XCUIApplication) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 40 }
            .first { $0.frame.minY > window.minY + 120 && $0.frame.maxY < window.maxY - 80 }
    }

    /// XCUITest may return immediately after the last fast fling, while the native scroll
    /// is still decelerating. Sample the same card and frame three times before opening it.
    /// This waits only during setup: browser return is still inspected without a recovery swipe.
    private func settledVisibleCard(_ app: XCUIApplication, within seconds: TimeInterval)
        -> (identity: String, frame: CGRect)? {
        let deadline = Date().addingTimeInterval(seconds)
        var previous: (identity: String, frame: CGRect)?
        var matches = 0
        while Date() < deadline {
            if let card = visibleCard(app), card.isHittable {
                let current = (identity: card.identifier, frame: card.frame)
                if let previous, previous.identity == current.identity,
                    abs(previous.frame.minY - current.frame.minY) <= 1,
                    abs(previous.frame.maxY - current.frame.maxY) <= 1 {
                    matches += 1
                } else {
                    matches = 1
                }
                if matches >= 3 { return current }
                previous = current
            } else {
                previous = nil
                matches = 0
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    /// Browser dismissal is asynchronous. Read the returned card only after its frame
    /// settles, without scrolling to find it: a card in the wrong place still fails.
    private func settledFrame(of card: XCUIElement, within seconds: TimeInterval) -> CGRect? {
        let deadline = Date().addingTimeInterval(seconds)
        var previous: CGRect?
        var matches = 0
        while Date() < deadline {
            if card.exists, card.frame.height > 40 {
                let current = card.frame
                if let previous, abs(previous.minY - current.minY) <= 1,
                    abs(previous.maxY - current.maxY) <= 1 {
                    matches += 1
                } else {
                    matches = 1
                }
                if matches >= 3 { return current }
                previous = current
            } else {
                previous = nil
                matches = 0
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return nil
    }

    /// The card's own *open* control. It carries `card.open`: measured on the device
    /// (`docs/reviews/2026-10-11-article-reading-diagnosis.md` §3), the card's tree had the bookmark control with
    /// an identifier and the opening label with **none**, so a test had to guess ("the first button with an empty
    /// identifier") — and the bookmark comes first, so guessing wrong saved the article instead of opening it. The
    /// compact row answers the same tap with a gesture and has no control of its own, hence the card itself.
    private func openControl(_ card: XCUIElement) -> XCUIElement {
        let control = card.buttons["card.open"]
        return control.exists ? control : card
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Opens the first card the feed presents and returns its identity plus its frame, so the return can be
    /// measured on this surface.
    @discardableResult
    private func openTheFirstCard(_ app: XCUIApplication) -> (String, CGRect)? {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, visibleCard(app) == nil { Thread.sleep(forTimeInterval: 1.0) }
        guard let card = visibleCard(app) else {
            XCTFail("the local fixture feed publishes cards")
            return nil
        }
        let identity = card.identifier
        let frame = card.frame
        let control = openControl(card)
        if control.exists && control.isHittable { control.tap() } else { card.tap() }
        return (identity, frame)
    }

    /// The PO's remaining proof: stored content readable with the iPhone **actually** disconnected. The app's own
    /// transport block is not that proof — it cuts the app's traffic, not the device's. So this test never asks
    /// for the network in the first place, and is meant to run with airplane mode on: part 1 shows a real
    /// namespace's edition coming from the store alone; part 2 shows the stored article text in the local reader.
    func testStoredContentIsReadableWithTheDeviceActuallyOffline() async throws {
        try await assertTheDeviceIsReallyOffline()

        // Part 1 — a namespace with 173 cards stored by earlier runs: with no connectivity, the edition can only
        // come from the store.
        let real = XCUIApplication()
        real.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = Self.readerWithContent
        real.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        real.launch()
        XCTAssertTrue(waitForAVisibleCard(real, within: 120),
            "with the device offline, the stored edition must still be presented")
        attach(real, "offline-1-stored-edition")
        real.terminate()

        // Part 2 — the reading itself, still offline: the feed is the app's own fixture (in process, no network)
        // and what the reader opens is text already stored, with no request made to open it.
        let app = launched(shape: "longSummary")
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 25),
            "the stored text must open for reading with the device disconnected")
        XCTAssertGreaterThan(byIdentifier(app, "reading.body").label.count, 3_000,
            "the whole stored text is there, not a teaser")
        XCTAssertEqual(byIdentifier(app, "reading.origin").label, "Resumo fornecido pela fonte")
        attach(app, "offline-2-stored-article")
    }

    /// Refuses to claim an offline proof it did not have. One real request, from this test's own process on the
    /// device: if it reaches the network, the device is not disconnected and every claim below would be worthless.
    private func assertTheDeviceIsReallyOffline() async throws {
        var configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let reached = (try? await session.data(from: URL(string: "https://example.com/")!)) != nil
        XCTAssertFalse(reached,
            "o aparelho está online — esta rodada não pode alegar prova offline. Ligue o Modo Avião e rode de novo")
    }

    @discardableResult
    private func waitForAVisibleCard(_ app: XCUIApplication, within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if visibleCard(app) != nil { return true }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return false
    }

    /// The in-app browser's address field, once it shows what it was given. Its chrome arrives with the reader and
    /// the field is populated in its own time — a wait rather than a read, the way every other arrival in this file
    /// is asserted.
    @discardableResult
    private func waitForAddress(_ app: XCUIApplication, showing fragment: String,
        within seconds: TimeInterval) -> Bool {
        let address = app.buttons["URL"].firstMatch
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if address.exists, String(describing: address.value).contains(fragment) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    func testABodyIsReadLocallyWithItsSourceHeadlineDateAndExit() throws {
        let app = launched(shape: "body")
        guard let (identity, frame) = openTheFirstCard(app) else { return XCTFail("no card to open") }

        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 20),
            "a stored body opens the local reading surface")
        XCTAssertEqual(byIdentifier(app, "reading.origin").label, "Texto publicado pela fonte")
        XCTAssertTrue(byIdentifier(app, "reading.partial").exists,
            "a feed's body is never presented as the whole article")
        XCTAssertTrue(byIdentifier(app, "reading.source").label.contains("BBC"), "the source is named")
        XCTAssertTrue(byIdentifier(app, "reading.headline").label.hasPrefix("BBC"),
            "the headline the source published is the one shown")
        XCTAssertTrue(byIdentifier(app, "reading.date").exists, "the article's date is shown")
        XCTAssertTrue(byIdentifier(app, "reading.open-site").exists, "the header offers the site")
        XCTAssertTrue(byIdentifier(app, "reading.open-site-footer").exists, "and so does the end of the text")
        XCTAssertTrue(byIdentifier(app, "reading.body").label.contains("Parágrafo 60"),
            "the whole stored text is readable locally")
        attach(app, "reading-body")

        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForNonExistence(timeout: 20),
            "closing the local reader returns to the feed")
        let after = app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .first { $0.identifier == identity }?.frame
        XCTAssertNotNil(after, "the card the reader left is still there")
        XCTAssertEqual(after?.minY ?? -1, frame.minY, accuracy: 1.0,
            "opening and closing the local reader preserves the exact position, on this surface too")
        attach(app, "reading-back-in-the-feed")
    }

    func testASubstantialSummaryIsReadLocallyAndLabelledAsASummary() throws {
        let app = launched(shape: "longSummary")
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 20))
        XCTAssertEqual(byIdentifier(app, "reading.origin").label, "Resumo fornecido pela fonte",
            "a summary is named as a summary, never as the article")
        XCTAssertTrue(byIdentifier(app, "reading.body").label.contains("Parágrafo 60"))
        attach(app, "reading-long-summary")
    }

    /// Browser-close regression: a nontrivial admitted history must return to the SAME card, not merely
    /// to any card somewhere in the feed. The long local fixture keeps the scenario reproducible offline.
    /// This is a UI proof: a session-level anchor assertion cannot detect a UIKit/SwiftUI scroll jump.
    /// Evidence only. Unlike the regression test below, this reports all three
    /// independent seams without claiming to fix the browser-return displacement.
    func testSafariViewportDiagnosisCapturesMountWindowAndAnchor() throws {
        let app = launched(shape: "shortSummary", itemsPerFeed: 95, safariDiagnostic: true)
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 180))
        XCTAssertTrue(waitForAVisibleCard(app, within: 180))
        let diagnostic = app.otherElements["native-viewport-diagnosis"].firstMatch
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 20), "debug diagnostic must be accessible")
        let initial = diagnostic.value as? String ?? "diagnostic-unavailable"
        for _ in 0..<8 { scroll.swipeUp(velocity: .fast) }
        guard let tracked = settledVisibleCard(app, within: 30) else {
            attach(app, "safari-diagnosis-setup-unsettled")
            return XCTFail("no stable card after the eight reader gestures")
        }
        let before = diagnostic.value as? String ?? "diagnostic-unavailable"
        let card = byIdentifier(app, tracked.identity)
        XCTAssertTrue(card.exists && card.isHittable)
        let opener = openControl(card)
        if opener.exists && opener.isHittable { opener.tap() } else { card.tap() }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 20))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForNonExistence(timeout: 20))
        let after = diagnostic.value as? String ?? "diagnostic-unavailable"
        let returned = byIdentifier(app, tracked.identity)
        let finalFrame = settledFrame(of: returned, within: 20)
        let attachment = XCTAttachment(string: [
            "initial=\(initial)", "before=\(before)", "after=\(after)",
            "tracked=\(tracked.identity)", "beforeY=\(tracked.frame.minY)",
            "afterY=\(finalFrame.map { String(describing: $0.minY) } ?? "missing")"
        ].joined(separator: "\n"))
        attachment.name = "safari-native-window-anchor-diagnosis"
        attachment.lifetime = .keepAlways
        add(attachment)
        attach(app, "safari-native-window-anchor-diagnosis")
        XCTAssertTrue(before.contains("captureInstance=") && before.contains("scrollInstances=") && before.contains("windowRevision=")
            && before.contains("positionID=") && before.contains("presentedTop="),
            "the first observation must include native identity, publication and capture")
        XCTAssertTrue(after.contains("captureInstance=") && after.contains("scrollInstances=") && after.contains("windowRevision=")
            && after.contains("positionID=") && after.contains("presentedTop="),
            "a missing post-dismissal diagnostic is itself evidence of hierarchy loss")
        // Do not assert that the position was retained: this probe must produce evidence
        // even when the main browser-return regression fails.
    }

    func testClosingSitePreservesScrolledCardIdentityAndFrameWithDeepHistory() throws {
        let app = launched(shape: "shortSummary", itemsPerFeed: 95)
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 180), "the local fixture publishes a feed")
        guard waitForAVisibleCard(app, within: 180), let firstID = visibleCard(app)?.identifier else {
            return XCTFail("the fixture draws a first visible card")
        }

        // Move away from the opening position; a test that reopens the first card cannot exercise
        // window growth or the restoration of a lazy cell that was scrolled into view.
        // Eight real gestures, rather than stopping as soon as any other card is seen: the test
        // must cross multiple viewport windows and exercise the long-history presentation.
        for _ in 0..<8 { scroll.swipeUp(velocity: .fast) }
        guard let settled = settledVisibleCard(app, within: 30) else {
            attach(app, "browser-close-setup-not-settled")
            return XCTFail("after eight flings, no hittable card had a stable frame")
        }
        guard settled.identity != firstID else {
            attach(app, "browser-close-setup-did-not-advance")
            return XCTFail("eight flings did not leave the initial visible card")
        }
        let identity = settled.identity
        let card = byIdentifier(app, identity)
        guard card.exists, card.isHittable else {
            return XCTFail("the card stabilized after the flings must remain tappable")
        }
        let before = card.frame
        XCTAssertEqual(before.minY, settled.frame.minY, accuracy: 1.0,
            "the tracked card moved between settling and opening the browser")
        XCTAssertTrue(before.intersects(scroll.frame), "the tracked card starts in the actual feed viewport")
        let opener = openControl(card)
        if opener.exists && opener.isHittable { opener.tap() } else { card.tap() }

        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 20),
            "the card opens the site's in-app browser")
        XCTAssertTrue(waitForAddress(app, showing: "example.test", within: 20),
            "the browser navigated to the fixture card's original URL")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForNonExistence(timeout: 20),
            "the browser must actually finish dismissal before measuring the underlying feed")

        // No scroll, search or recovery gesture is allowed after closing. Let the native
        // frame settle, but never scroll the missing card back into the viewport.
        let returned = byIdentifier(app, identity)
        guard let after = settledFrame(of: returned, within: 20) else {
            attach(app, "browser-close-return-card-missing-or-moving")
            return XCTFail("browser close did not restore a stable instance of the original card")
        }
        XCTAssertTrue(after.intersects(scroll.frame),
            "the same card must still intersect the feed viewport without a recovery scroll")
        XCTAssertEqual(after.minY, before.minY, accuracy: 1.0,
            "browser close must preserve the card's vertical position")
        XCTAssertEqual(after.maxY, before.maxY, accuracy: 1.0,
            "browser close must preserve the card's height and trailing edge")
        // Persist the numeric evidence for each CI repetition, not only screenshots
        // and a pass/fail flag. The two A/B arms use byte-identical assertions.
        let result = XCTAttachment(string: [
            "cardUUID=\(identity)",
            "beforeMinY=\(before.minY)", "afterMinY=\(after.minY)",
            "beforeMaxY=\(before.maxY)", "afterMaxY=\(after.maxY)",
            "deltaMinY=\(after.minY - before.minY)"
        ].joined(separator: "\n"))
        result.name = "browser-return-position-metrics"
        result.lifetime = .keepAlways
        add(result)
        attach(app, "browser-close-deep-history-same-card")
    }

    func testATeaserOpensTheSiteWithNoIntermediateScreen() throws {
        let app = launched(shape: "shortSummary")
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 20),
            "a teaser's primary action is the site, in the app's own reader")
        XCTAssertFalse(byIdentifier(app, "reading.body").exists,
            "and there is no intermediate screen in the way")
        attach(app, "reading-teaser-goes-to-the-site")
    }

    func testACardWithoutTextOpensTheSite() throws {
        let app = launched(shape: "none")
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 20))
        XCTAssertFalse(byIdentifier(app, "reading.body").exists,
            "no text at all still has an address, and no local reader is invented for it")
    }

    func testTheLocalReaderWorksWithTheAppsNetworkBlocked() throws {
        let app = launched(shape: "longSummary", blocked: true)
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 25),
            "the app's own transport is closed and the local text is still there")
        XCTAssertTrue(byIdentifier(app, "reading.body").label.contains("Parágrafo 60"),
            "the whole text is readable with no network at all")
        attach(app, "reading-offline")
    }

    func testTheLocalReaderHonoursALargeAccessibilityTextSize() throws {
        let app = launched(shape: "body", largeText: true)
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 25))
        let body = byIdentifier(app, "reading.body")
        XCTAssertTrue(body.exists)
        // At the accessibility sizes the same text occupies more height: that is Dynamic Type, measured rather
        // than asserted by hope.
        XCTAssertGreaterThan(body.frame.height, 400,
            "with the largest accessibility size the article text must be laid out for it")
        // The architect's fix, revalidated at the maximum size: the header action carries its short visual label
        // beside an external-opening glyph and the *full* accessibility label, and the footer keeps the full
        // wording. The screenshot below is the visual half of this proof.
        XCTAssertEqual(byIdentifier(app, "reading.open-site").label, "Abrir no site",
            "the header action must announce the full wording even when its visual label is short")
        XCTAssertEqual(byIdentifier(app, "reading.open-site-footer").label, "Abrir no site",
            "the footer keeps the full wording")
        attach(app, "reading-large-text")
    }

    /// NN-07: the card's own controls are the reader's at the largest text size too. The open surface states
    /// itself (`card.open`) and is reached by that identifier, and the save control states its action in the
    /// interface's own words — the same words the card's own menu uses for the same act — instead of the symbol's
    /// name. Both stay reachable, and the control the reader reached really opens the article.
    func testTheCardsOwnControlsAreReachableAndNamedAtTheLargestTextSize() throws {
        let app = launched(shape: "body", largeText: true)
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline, visibleCard(app) == nil { Thread.sleep(forTimeInterval: 1.0) }
        guard let card = visibleCard(app) else { return XCTFail("the local fixture feed publishes cards") }

        let open = card.buttons["card.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "the card's own open surface states itself")
        XCTAssertFalse(open.label.isEmpty, "and it carries the card's own words")
        XCTAssertTrue(open.isHittable, "the largest accessibility size does not take the control away")
        let save = card.buttons["card.bookmark"]
        XCTAssertTrue(save.waitForExistence(timeout: 20), "the card offers saving")
        XCTAssertTrue(save.isHittable)
        XCTAssertEqual(save.label, "Salvar artigo", "the save control states its action in words")
        XCTAssertEqual(save.value as? String, "not bookmarked", "and the state the reader's own list records")
        attach(app, "nn07-card-controls-at-the-largest-text-size")

        open.tap()
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 25),
            "the control the reader reached opens the article, at the largest text size")
    }

    /// The explicit request for the site, and the close that follows it. U-reading's rule is one reader drawing
    /// one page: the site replaces the text inside that same presentation, so closing the site ends the reader
    /// and the app comes back to the feed it was opened from — there is no text surface left behind it to return
    /// to, and none stacked underneath it either.
    func testOpeningTheSiteFromTheLocalReaderIsAnExplicitRequestAndComesBackToTheFeed() throws {
        let app = launched(shape: "body")
        guard let (identity, frame) = openTheFirstCard(app) else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 20))

        byIdentifier(app, "reading.open-site").tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 20),
            "the explicit request opens the site in the app's own reader")
        // The address the reader opened is the article's own. The stock browser's chrome arrives with the reader
        // and its address field is populated in its own time, so what is claimed here is what the address shows,
        // not the instant it shows it.
        XCTAssertTrue(waitForAddress(app, showing: "example.test", within: 20),
            "the address the reader opened is the article's own, the one the card carries")
        attach(app, "reading-explicit-site")

        app.buttons["Close"].tap()
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForNonExistence(timeout: 20),
            "closing the site ends the reader: the text does not come back as a surface of its own")
        XCTAssertTrue(waitForAVisibleCard(app, within: 20), "and the feed the reader was opened from is back")
        let returned = byIdentifier(app, identity)
        XCTAssertTrue(returned.waitForExistence(timeout: 20), "the original card is still in the feed")
        if returned.exists {
            XCTAssertEqual(returned.frame.minY, frame.minY, accuracy: 1.0,
                "site dismissal preserves the original card position")
        }
        attach(app, "reading-back-in-the-feed")
    }
}
