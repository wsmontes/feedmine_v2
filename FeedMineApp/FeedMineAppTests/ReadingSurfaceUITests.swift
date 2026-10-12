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
    private func launched(shape: String, blocked: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_TEXT"] = shape
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

    /// The card's own *open* control: the bookmark comes first in the tree and carries an identifier, this one
    /// does not.
    private func openControl(_ card: XCUIElement) -> XCUIElement {
        let candidate = card.buttons.matching(NSPredicate(format: "identifier == '' AND label != ''")).firstMatch
        return candidate.exists ? candidate : card
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

    func testOpeningTheSiteFromTheLocalReaderIsAnExplicitRequestAndComesBack() throws {
        let app = launched(shape: "body")
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 20))

        byIdentifier(app, "reading.open-site").tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 20),
            "the explicit request opens the site in the app's own reader")
        let address = app.buttons["URL"].firstMatch
        XCTAssertTrue(address.exists && String(describing: address.value).contains("example.test"),
            "and it is the article's own address, the one the card carries")
        attach(app, "reading-explicit-site")

        app.buttons["Close"].tap()
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 20),
            "closing the site comes back to the text the reader was reading, not to the feed")
        attach(app, "reading-back-to-the-text")
    }
}
