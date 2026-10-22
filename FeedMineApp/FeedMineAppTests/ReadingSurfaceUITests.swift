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

    /// Safari's chrome belongs to SafariViewService: its element can be queried while its tap does not reach the
    /// X. The fallback is the X's own frame, so it follows the device's geometry instead of a screen constant.
    private func tapSafariClose(_ app: XCUIApplication, _ close: XCUIElement?) {
        guard let close else { return }
        // The remote service element's activation point is not where its X is drawn (measured: the frame's mid
        // matches the visual X, the synthesized tap point does not). One tap at the frame centre is the human
        // gesture; there is no second tap, because a fallback could land on the app already uncovered.
        let frame = close.frame
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let path = XCTAttachment(string: "frame=\(frame) point=\(point) source=SafariViewService element frame")
        path.name = "safari-close-path"
        path.lifetime = .keepAlways
        add(path)
        guard frame.width > 0, frame.height > 0 else {
            XCTFail("Safari's close control has no frame to tap")
            return
        }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        // The address bar stays while the dismissal animates; the effect is observed, not assumed.
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, app.buttons["URL"].exists {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// The site reader is `SFSafariViewController`, and its dismissal control is labelled in the device's own
    /// language. Measured on 2026-10-20 from `docs/reviews/evidence/2026-10-18-ui-suite/run-final3.log`: on this
    /// pt-BR device the tree exposes `Fechar`, `URL`, `PageFormatMenuButton`, `BackButton` while the site is open —
    /// the product opened the site and the English-only selector was what failed. Both trees are searched because
    /// the control belongs to the Safari view service, which surfaces either in the app's tree or in its own
    /// application, depending on how it was presented.
    private func siteReaderClose(_ app: XCUIApplication, timeout: TimeInterval = 20) -> XCUIElement? {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let labels = ["Close", "Fechar", "Done", "Concluído"]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                // The site is a modal SFSafariViewController now. The local reader's own close is also labelled
                // "Fechar" (identifier `reading.close`) and is still in the app's tree under Safari; tapping that
                // one leaves Safari up, which is exactly the RR-1 confusion. The site's chrome is looked for in
                // Safari's own process first, then in the app's tree excluding the local close.
                if safari.buttons[label].exists { return safari.buttons[label] }
                let site = app.buttons.matching(NSPredicate(
                    format: "label == %@ AND identifier != %@", label, "reading.close")).firstMatch
                if site.exists { return site }
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return nil
    }

    /// A run whose only supply is the app's own local fixtures: the development feeds served in process, so there
    /// is no network, no server, no clock — and no add-feed sheet in the way of reaching an article.
    private func launched(shape: String, blocked: Bool = false, largeText: Bool = false,
        media: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_TEXT"] = shape
        // A real silent episode through the real adapter: the periodic time observer writes
        // `MediaPlaybackAdapter.state` every 0.5 s, and the host reads that state while the reader is up. It is
        // the deterministic version of the churn a live feed produces while a reader is reading.
        if media { app.launchEnvironment["FEEDMINE_MEDIA_SIMULATION"] = "1" }
        // The closed HTTPS proxy the app itself installs: real connections fail, the fixture still answers.
        if blocked { app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1" }
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    /// A card the reader can really act on: its opening control is hittable and the card is inside the window.
    /// No fixed top/bottom margins: on the iPhone 14 Plus the first card's top is 107 pt and the second sits at
    /// 550–896 pt of a 926 pt screen; both are real, and a margin constant would call the feed empty.
    private func visibleCard(_ app: XCUIApplication) -> XCUIElement? {
        let window = app.windows.firstMatch.frame
        return app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 40 && $0.frame.intersects(window) }
            .first { card in
                let control = openControl(card)
                return control.exists && control.isHittable
            }
    }

    private func card(_ app: XCUIApplication, identity: String) -> XCUIElement? {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identity)).firstMatch
        return element.exists ? element : nil
    }

    private func waitForCard(_ app: XCUIApplication, identity: String,
        within seconds: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let card = card(app, identity: identity) { return card }
            Thread.sleep(forTimeInterval: 1.0)
        }
        return card(app, identity: identity)
    }

    /// The card's own *open* control. It carries `card.open`: measured on the device
    /// (`docs/reviews/2026-10-11-article-reading-diagnosis.md` §3), the card's tree had the bookmark control with
    /// an identifier and the opening label with **none**, so a test had to guess ("the first button with an empty
    /// identifier") — and the bookmark comes first, so guessing wrong saved the article instead of opening it. The
    /// compact row answers the same tap with a gesture and has no control of its own, hence the card itself.
    private func openControl(_ card: XCUIElement) -> XCUIElement {
        // A card can expose more than one element matching the query; one is the control the reader taps.
        let control = card.buttons["card.open"].firstMatch
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
        // A proof of offline behavior requires an offline device. Skipping states that the gate is blocked by
        // infrastructure; passing a simulated disconnect would be claiming an observation that did not happen.
        if reached {
            throw XCTSkip("Modo Avião desligado: a prova offline exige o aparelho realmente desconectado")
        }
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

    func testATeaserOpensTheSiteWithNoIntermediateScreen() throws {
        let app = launched(shape: "shortSummary")
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertNotNil(siteReaderClose(app),
            "a teaser's primary action is the site, in the app's own reader")
        XCTAssertFalse(byIdentifier(app, "reading.body").exists,
            "and there is no intermediate screen in the way")
        attach(app, "reading-teaser-goes-to-the-site")
    }

    func testACardWithoutTextOpensTheSite() throws {
        let app = launched(shape: "none")
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertNotNil(siteReaderClose(app))
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

    /// The owner's report, made measurable: "ao abrir conteúdo, fechar/abrir no site ficam inoperantes". The reader
    /// is presented by `ReaderHost`, and its host view is re-rendered whenever the app's body changes — a feed
    /// advance or a playback tick. A control the reader is already pressing must still act after that render.
    ///
    /// A press that spans a render is not an exotic gesture: a deliberate press lasts longer than one frame. With
    /// the simulated episode playing, `MediaPlaybackAdapter` publishes a new position every 0.5 s, so this press
    /// spans at least two host renders. The no-churn case below is the control for the press itself.
    func testACloseThatSpansAHostRenderStillClosesTheReader() throws {
        let app = launched(shape: "body", media: true)
        defer { app.terminate() }
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 25),
            "the stored body opens the local reading surface")
        XCTAssertTrue(app.otherElements["mini-player"].waitForExistence(timeout: 20),
            "the reader carries the live playback bar, which is the render source under test")

        let close = byIdentifier(app, "reading.close")
        XCTAssertTrue(close.isHittable, "the close control is on screen")
        close.press(forDuration: 1.2)
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForNonExistence(timeout: 10),
            "a close pressed while the host re-renders must still end the reader")
    }

    /// The control for the test above: the same press without any render in flight. If this failed too, the press
    /// duration would be the problem and the churn test would prove nothing.
    func testAClosePressWithoutChurnClosesTheReader() throws {
        let app = launched(shape: "body")
        defer { app.terminate() }
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 25))

        let close = byIdentifier(app, "reading.close")
        close.press(forDuration: 1.2)
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForNonExistence(timeout: 10),
            "a press on the close control ends the reader")
    }

    /// The same rule for the other control the owner named: "abrir no site" must act while the host re-renders.
    func testAnOpenSiteThatSpansAHostRenderStillOpensTheSite() throws {
        let app = launched(shape: "body", media: true)
        defer { app.terminate() }
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 25))
        XCTAssertTrue(app.otherElements["mini-player"].waitForExistence(timeout: 20))

        let openSite = byIdentifier(app, "reading.open-site")
        XCTAssertTrue(openSite.isHittable)
        openSite.press(forDuration: 1.2)
        // RR-1: the local reader's own close is also labelled "Fechar", so a close control being present is not
        // proof the site opened. The page that was up must be gone and the site's own address must be the one the
        // card carries; a no-op open-site leaves `reading.body` on screen and no address.
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForNonExistence(timeout: 20),
            "the site replaces the text page")
        XCTAssertTrue(waitForAddress(app, showing: "example.test", within: 20),
            "the site the reader asked for is the card's own address, not the reader's close control")
        attach(app, "reader-open-site-under-churn")
    }


    /// The press in the two tests above must really span a host render, otherwise it proves nothing about churn.
    /// While the simulated episode plays, the adapter writes a new position every 0.5 s; a 1.2 s press on the
    /// mini-player's own toggle must both act (its label flips) and span at least two of those renders (its
    /// progress value moves).
    func testAControlPressSpansPlaybackRenders() throws {
        let app = launched(shape: "body", media: true)
        defer { app.terminate() }
        guard openTheFirstCard(app) != nil else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 25))
        let toggle = app.buttons["mini-player-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        let progress = byIdentifier(app, "mini-player-progress")
        let before = progress.value as? String
        let labelBefore = toggle.label

        toggle.press(forDuration: 1.2)

        XCTAssertNotEqual(toggle.label, labelBefore, "the pressed control acted")
        XCTAssertNotNil(before, "the bar reports its position while playing")
        XCTAssertNotEqual(progress.value as? String, before, "a playback render happened during the press")
        attach(app, "reader-control-press-spanning-renders")
    }

    /// F15 R3: playback is the composition's, so passing through a modal Safari must not pause or restart it.
    /// The simulated episode plays under the site; after the site closes, the bar is the live one and its
    /// position has advanced.
    func testPlaybackContinuesAcrossTheSite() throws {
        let app = launched(shape: "body", media: true)
        defer { app.terminate() }
        guard let (identity, _) = openTheFirstCard(app) else { return XCTFail("no card to open") }
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 25))
        let progress = byIdentifier(app, "mini-player-progress")
        let before = progress.value as? String
        XCTAssertNotNil(before, "the bar reports its position while playing")

        byIdentifier(app, "reading.open-site").tap()
        guard let close = siteReaderClose(app, timeout: 20) else {
            return XCTFail("the site's close control is reachable")
        }
        tapSafariClose(app, close)
        XCTAssertFalse(app.buttons["URL"].exists, "Safari's chrome is gone")
        guard let returned = waitForCard(app, identity: identity, within: 20) else {
            return XCTFail("the feed returns with the same card")
        }
        XCTAssertTrue(openControl(returned).isHittable)
        let toggle = app.buttons["mini-player-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.label, "Pausar",
            "the episode is still playing after passing through the site")
        XCTAssertNotEqual(progress.value as? String, before,
            "and its position advanced while Safari was up")
        attach(app, "reader-playback-through-site")
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
        XCTAssertNotNil(siteReaderClose(app),
            "the explicit request opens the site in the app's own reader")
        // The address the reader opened is the article's own. The stock browser's chrome arrives with the reader
        // and its address field is populated in its own time, so what is claimed here is what the address shows,
        // not the instant it shows it.
        XCTAssertTrue(waitForAddress(app, showing: "example.test", within: 20),
            "the address the reader opened is the article's own, the one the card carries")
        attach(app, "reading-explicit-site")

        // The remote SafariViewService control can be found without its tap reaching the X; a stored body's own
        // close is also "Fechar". The address bar is the site-only witness and the X's frame is the fallback.
        tapSafariClose(app, siteReaderClose(app))
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForNonExistence(timeout: 20),
            "closing the site ends the reader: the text does not come back as a surface of its own")
        XCTAssertFalse(app.buttons["URL"].exists, "Safari's chrome is gone, not merely covered")
        guard let returned = waitForCard(app, identity: identity, within: 20) else {
            return XCTFail("the card the reader was opened from is back")
        }
        XCTAssertEqual(returned.frame.minY, frame.minY, accuracy: 1.0,
            "the same card returns at the same position")
        XCTAssertTrue(openControl(returned).isHittable, "and its own open control is actionable")
        attach(app, "reading-back-in-the-feed")
    }

    // The Release/live proof: the reader's controls on a real feed over the real network, in the permanent
    // `FeedMineSurfaces` scheme (Release app + UI tests). It needs network and a fresh app container, so it is
    // kept apart from the deterministic journeys above, which use only the app's own fixtures.
    //
    // Seed: the app's own Add Feed flow with https://blog.codinghorror.com/ (its page declares
    // https://blog.codinghorror.com/rss/, which carries content:encoded), so the article opens on the local
    // surface and its own HTTPS address is the site. The attachments record the feed, the card identity/label
    // and the site address for replay.
    //
    //   xcrun simctl uninstall <sim> com.feedmine.app
    //   xcodebuild test -project … -scheme FeedMineSurfaces -configuration Release \
    //     -destination 'platform=iOS Simulator,id=<sim>' -derivedDataPath <abs> \
    //     -only-testing:FeedMineUITests/ReadingSurfaceUITests/testLiveReaderControlsOnTheRealCatalogueAndNetwork
    func testLiveReaderControlsOnTheRealCatalogueAndNetwork() throws {
        guard ProcessInfo.processInfo.environment["FEEDMINE_LIVE_SURFACES"] == "1" else {
            throw XCTSkip("live surfaces proof requires FEEDMINE_LIVE_SURFACES=1")
        }
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        defer { app.terminate() }

        let menu = app.buttons["more-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 180), "the reader's shell is up")
        menu.tap()
        let addFeed = app.buttons.matching(NSPredicate(format: "label IN {'Adicionar feed', 'Add feed'}")).firstMatch
        XCTAssertTrue(addFeed.waitForExistence(timeout: 20), "the menu offers adding a feed")
        addFeed.tap()
        let field = app.textFields["add-feed-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "the add-feed sheet is up")
        field.tap()
        field.typeText("https://blog.codinghorror.com/")
        app.buttons["add-feed-add"].tap()
        let added = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "add-feed-result-added")).firstMatch
        if !added.waitForExistence(timeout: 120) {
            // The sheet's result element is an instrument; the durable effect is the feed's own card, asserted
            // below. Record why the element was late instead of turning the instrument into a product failure.
            let error = app.staticTexts["add-feed-error"]
            let failure = XCTAttachment(string:
                "add-feed-result-missing; add-feed-error=\(error.exists ? error.label : "-")\n\(app.debugDescription)")
            failure.name = "live-add-feed-tree"
            failure.lifetime = .keepAlways
            add(failure)
        }
        attach(app, "live-add-feed")
        app.buttons["add-feed-cancel"].tap()

        // The added source's own card, not whichever supply answers first: the live discovery may also publish.
        func codingHorrorCard(within seconds: TimeInterval) -> XCUIElement? {
            let deadline = Date().addingTimeInterval(seconds)
            let window = app.windows.firstMatch.frame
            while Date() < deadline {
                let cards = app.descendants(matching: .any).matching(Self.cardIdentifier).allElementsBoundByIndex
                    .filter { $0.exists && $0.frame.height > 40 && $0.frame.intersects(window) }
                for card in cards {
                    // The card must be one the reader can act on, not merely one in the tree.
                    let control = card.buttons["card.open"].firstMatch
                    guard control.exists, control.isHittable else { continue }
                    if card.label.localizedCaseInsensitiveContains("coding horror") { return card }
                    if card.staticTexts.allElementsBoundByIndex
                        .contains(where: { $0.label.localizedCaseInsensitiveContains("coding horror") }) {
                        return card
                    }
                }
                Thread.sleep(forTimeInterval: 1.0)
            }
            return nil
        }

        func openCard(_ card: XCUIElement) {
            let control = card.buttons["card.open"]
            if control.exists && control.isHittable { control.tap() } else { card.tap() }
        }

        guard let first = codingHorrorCard(within: 240) else {
            return XCTFail("the feed added publishes a Coding Horror card")
        }
        let seed = XCTAttachment(string:
            "feed=https://blog.codinghorror.com/rss/ via https://blog.codinghorror.com/; card=\(first.identifier); label=\(first.label)")
        seed.name = "live-seed"
        seed.lifetime = .keepAlways
        add(seed)
        attach(app, "live-feed")

        // 1. The local reader from content:encoded, and its close.
        openCard(first)
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 60),
            "the article opens on the local reading surface")
        XCTAssertGreaterThan(byIdentifier(app, "reading.body").label.count, 100)
        attach(app, "live-local-reader")
        byIdentifier(app, "reading.close").tap()
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForNonExistence(timeout: 30),
            "close returns to the feed")
        guard let firstReturned = waitForCard(app, identity: first.identifier, within: 60) else {
            return XCTFail("the feed returns with the same card")
        }
        XCTAssertTrue(openControl(firstReturned).isHittable, "and the card is actionable")

        // 2. Two open/close cycles while the live session is acquiring.
        for cycle in 1...2 {
            guard let card = codingHorrorCard(within: 90) else { return XCTFail("cycle \(cycle): no card") }
            openCard(card)
            XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 60),
                "cycle \(cycle): the reader opens")
            byIdentifier(app, "reading.close").tap()
            XCTAssertTrue(byIdentifier(app, "reading.body").waitForNonExistence(timeout: 30),
                "cycle \(cycle): close acts while the session is acquiring")
        }

        // 3. The explicit site request and Safari's own control on the real HTTPS page.
        guard let card = codingHorrorCard(within: 90) else { return XCTFail("no card for the site path") }
        let siteCardIdentity = card.identifier
        openCard(card)
        XCTAssertTrue(byIdentifier(app, "reading.body").waitForExistence(timeout: 60))
        byIdentifier(app, "reading.open-site").tap()
        guard let close = siteReaderClose(app, timeout: 40) else {
            return XCTFail("the site's own close control is reachable")
        }
        attach(app, "live-site-reader")
        let address = app.buttons["URL"].firstMatch
        if address.exists {
            let site = XCTAttachment(string: "address=\(String(describing: address.value))")
            site.name = "live-site-address"
            site.lifetime = .keepAlways
            add(site)
        }
        XCTAssertTrue(address.exists || app.webViews.firstMatch.exists,
            "the real page is in the app's reader")
        tapSafariClose(app, close)
        XCTAssertFalse(app.buttons["URL"].exists, "Safari's chrome is gone, not merely covered")
        guard let siteReturned = waitForCard(app, identity: siteCardIdentity, within: 60) else {
            return XCTFail("Safari's close returns to the same card")
        }
        XCTAssertTrue(openControl(siteReturned).isHittable, "and the card the reader left is actionable")
        attach(app, "live-back-in-feed")
    }
}
