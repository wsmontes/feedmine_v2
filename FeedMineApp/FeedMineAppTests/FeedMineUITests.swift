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
        openMenu(app)
        app.buttons["Fontes"].tap()
        XCTAssertTrue(app.navigationBars["Fontes"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'source-choice-'")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Concluir"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 10))
    }

    /// T7: a selection with no sources is a state the reader may choose (V1 allowed it), not a preparation
    /// and not a failure — its own surface, naming the action that fixes it, and the way back.
    @MainActor
    func testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_EMPTY_SELECTION"] = "1"
        app.launch()
        let title = app.staticTexts["feed-empty-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 45))
        XCTAssertEqual(title.label, "Nenhuma fonte habilitada", "V1's own words for this state, in the app's language")
        XCTAssertFalse(app.scrollViews.firstMatch.exists, "no feed is drawn for a selection with no sources")
        XCTAssertFalse(app.staticTexts["Preparando"].exists, "nothing is being prepared, so nothing claims it")
        // The action the surface names is the one the app implements: the empty state's own button.
        app.buttons["feed-empty-action"].tap()
        XCTAssertTrue(app.navigationBars["Fontes"].waitForExistence(timeout: 15))
        app.buttons["Concluir"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 15), "dismissing the picker leaves the reader where they were")
        // The way back: enable one source and the feed exists again.
        app.buttons["feed-empty-action"].tap()
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'source-choice-'")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 15))
        choice.tap()
        app.buttons["Concluir"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
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

    /// U1-P3/U1-P4/U1-P6: presenting and dismissing the existing source sheet, and changing the
    /// system appearance, keep the same FeedAssociation — proven by the DEBUG delivery counters
    /// not resetting — and keep the reading point. Navigation chrome must never rebuild the
    /// session or lose the anchor.
    @MainActor
    func testU1ChromeAndAppearancePreserveAssociationAndReadingPoint() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        XCTAssertEqual(proof.label, "received=0 completed=0 backward=0", "restore/layout is not a native observation")
        // Establish a reading point that is not the top of the feed.
        scroll.swipeUp()
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*completed=[1-9][0-9]*.*"), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 20), .completed, "observed: \(proof.label)")
        let counters = proof.label
        let anchor = try XCTUnwrap(topmostCardIdentifier(app: app, scroll: scroll), "a card must be visible inside the viewport")
        // U1-C: the source sheet is the one destination that exists today.
        openMenu(app)
        app.buttons["Fontes"].tap()
        XCTAssertTrue(app.navigationBars["Fontes"].waitForExistence(timeout: 10))
        app.buttons["Concluir"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        XCTAssertEqual(proof.label, counters, "presenting a sheet must not replace the association")
        XCTAssertEqual(topmostCardIdentifier(app: app, scroll: scroll), anchor, "presenting a sheet must keep the reading point")
        // U1-P1/P4: an appearance change is presentation only.
        XCUIDevice.shared.appearance = .dark
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        XCTAssertEqual(proof.label, counters, "an appearance change must not replace the association")
        XCTAssertEqual(topmostCardIdentifier(app: app, scroll: scroll), anchor, "an appearance change must keep the reading point")
        let dark = XCTAttachment(screenshot: app.screenshot())
        dark.name = "u1-dark-appearance"
        dark.lifetime = .keepAlways
        add(dark)
        XCUIDevice.shared.appearance = .light
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        XCTAssertEqual(proof.label, counters, "returning to the light appearance must not replace the association")
    }

    /// U2-P1/P3/P4: saving from the feed, finding the article in the saved list and reading it
    /// in-app must all keep the same association and the same reading point.
    @MainActor
    func testU2SavedListAndInAppReaderPreserveTheSession() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
        let card = cards.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 45), "a real published occurrence must appear")
        let counters = proof.label
        card.press(forDuration: 1.2)
        let save = app.buttons["Salvar artigo"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the card menu must offer saving")
        save.tap()
        app.buttons["bookmark-boxes-button"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved-article-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the saved article must be listed")
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "u2-saved-list"
        list.lifetime = .keepAlways
        add(list)
        row.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30), "the reader must open inside the app")
        let reader = XCTAttachment(screenshot: app.screenshot())
        reader.name = "u2-in-app-reader"
        reader.lifetime = .keepAlways
        add(reader)
        // SafariServices owns the reader's close control; try its localized titles, then the
        // standard sheet dismissal, and keep the hierarchy for diagnosis if neither works.
        var dismissed = false
        for label in ["Close", "Done", "Fechar", "Concluído"] {
            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 3) { button.tap(); dismissed = true; break }
        }
        if !dismissed {
            app.swipeDown(velocity: .fast)
        }
        // Closing the reader returns to the saved list (the feed is behind the pushed screen, so
        // its scroll view is not in the tree yet), and going back restores the same session.
        XCTAssertTrue(row.waitForExistence(timeout: 15), "closing the reader must return to the saved list")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 15), "returning to the feed must restore it")
        XCTAssertEqual(proof.label, counters, "reading a saved article must not rebuild the association")
    }

    /// U3: the active context is stated and has a way back. A source or search context used to be
    /// indistinguishable from the main feed apart from its contents.
    @MainActor
    func testU3ActiveContextIsVisibleAndClearable() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        // T5: the chip in the floating header states the context; the main context states none. The chip
        // is a SwiftUI Menu (a pop-up button to XCUITest), so it is located by identifier across types.
        let chip = element(app, "reader-contexts")
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "the header must state the reading context")
        XCTAssertFalse(chip.label.contains("BBC Science"), "the main context states no source")
        chip.tap()
        app.buttons["BBC Science"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        XCTAssertTrue(element(app, "reader-contexts").label.contains("BBC Science"),
            "a source context must state which source is shown; observed: \(element(app, "reader-contexts").label)")
        element(app, "reader-contexts").tap()
        element(app, "reader-context-clear").tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        XCTAssertFalse(element(app, "reader-contexts").label.contains("BBC Science"),
            "clearing returns to the main context")
    }

    /// The card whose top edge sits inside the scroll viewport and is closest to it.
    @MainActor
    private func topmostCardIdentifier(app: XCUIApplication, scroll: XCUIElement) -> String? {
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
        let top = scroll.frame.minY
        return cards.allElementsBoundByIndex
            .filter { $0.frame.height > 40 && $0.frame.minY >= top - 1 }
            .min { $0.frame.minY < $1.frame.minY }?
            .identifier
    }

    /// T3: a native gesture admits prepared cards without moving what the reader is reading. The
    /// reference card and the offset inside it survive completing production, a background/foreground
    /// cycle, and backward navigation in the same viewport (tolerance: 1 point).
    @MainActor
    func testT3ScrollAdmitsWithoutMovingTheReadingPoint() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        // A real forward gesture that reaches the admitted tail.
        for _ in 0..<3 { scroll.swipeUp(velocity: .slow) }
        let delivered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".*completed=[1-9][0-9]*.*"), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 25), .completed, "observed: \(proof.label)")
        let reference = try XCTUnwrap(topmostCard(app: app, scroll: scroll), "a card must be visible")
        let referenceID = reference.identifier
        let referenceTop = reference.frame.minY
        let counters = proof.label
        // Completing production, backgrounding and returning must not move the reader.
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(scroll.waitForExistence(timeout: 20))
        XCTAssertEqual(proof.label, counters, "returning to the app must not replace the association")
        let afterForeground = try XCTUnwrap(topmostCard(app: app, scroll: scroll))
        XCTAssertEqual(afterForeground.identifier, referenceID, "the reference card must survive a foreground")
        XCTAssertEqual(afterForeground.frame.minY, referenceTop, accuracy: 1,
            "the offset inside the viewport must survive a foreground")
        // Backward navigation stays inside the admitted history and records a real backward gesture.
        scroll.swipeDown(velocity: .slow)
        let backward = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label MATCHES %@", ".*backward=[1-9][0-9]*.*"), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [backward], timeout: 20), .completed, "observed: \(proof.label)")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "t3-scroll-admission"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
    }

    /// T5: the reader's chrome is V1's, every control reaches a real flow, and no gesture is swallowed
    /// by an overlapping one. Only the actions this build executes are offered, so nothing here can be a
    /// dead control.
    @MainActor
    func testT5HeaderChromeAndCardGesturesReachRealFlows() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        // V1's header controls exist, and the navigation toolbar is gone.
        for identifier in ["search-button", "bookmark-boxes-button", "more-menu"] {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 10), identifier)
        }
        XCTAssertFalse(app.buttons["reader-sources"].exists, "the V2 toolbar must be gone")
        // The overflow menu offers exactly what this build can present.
        openMenu(app)
        XCTAssertTrue(app.buttons["Fontes"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Ajustes"].exists, "an unimplemented destination is never offered")
        XCTAssertFalse(app.buttons["Copiar link"].exists, "a card action this build cannot execute is gated")
        app.buttons["Fontes"].tap()
        XCTAssertTrue(app.navigationBars["Fontes"].waitForExistence(timeout: 10))
        app.buttons["Concluir"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        // The search surface opens and cancels without touching the feed.
        app.buttons["search-button"].tap()
        XCTAssertTrue(app.textFields["reader-search-field"].waitForExistence(timeout: 10))
        app.buttons["reader-search-cancel"].tap()
        XCTAssertFalse(app.textFields["reader-search-field"].waitForExistence(timeout: 3))
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        // A long press reaches the card's own menu; the same card's tap is not consumed by it.
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
        let card = cards.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 45), "a real published occurrence must appear")
        card.press(forDuration: 1.2)
        let save = app.buttons["Salvar artigo"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the long press must reach the card menu")
        save.tap()
        // Saving is really durable: the header's bookmark control shows the saved list with the row.
        app.buttons["bookmark-boxes-button"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved-article-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the saved article must be listed")
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        // A plain tap on the same card still opens it (the tap was never swallowed by the long press).
        card.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30), "tapping the card must open it")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "t5-shell-and-gestures"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Any element with this identifier, whatever role SwiftUI exposed it as (a `Menu` is a pop-up
    /// button to XCUITest, and the same declaration can be reported as either one).
    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// T6: the reader's filter sheet is V1's, and applying a selection is one explicit transition — the sheet
    /// closes only after the host persisted the identity and rebuilt the session around it.
    @MainActor
    func testT6FilterSheetOpensAppliesAndKeepsTheReader() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 10), "the filter sheet must open")
        // The criteria this build can enforce are the ones it offers; the rest are absent, not inert.
        let languages = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'language-'")).firstMatch
        XCTAssertTrue(languages.waitForExistence(timeout: 10),
            "the declared languages come from the shipped catalog")
        XCTAssertFalse(app.buttons["browse-topics"].exists,
            "a criterion without metadata is not offered, never offered and ignored")
        XCTAssertFalse(app.buttons["content-type-videos"].exists,
            "content type still has no truthful derivation, so it is not offered")
        // A language criterion is a draft edit; the draft's own behaviour (toggle, mood rule, clear all) is
        // proven at the unit level — 257 language rows make scrolling to the last section a flaky gesture here.
        languages.tap()
        XCTAssertTrue(app.buttons["filter-clear-all"].isEnabled,
            "editing the draft enables Clear All, which was disabled on a clean selection")
        app.buttons["filter-done"].tap()
        // The transition is explicit and complete: the sheet is gone and the reader is on the filtered context.
        XCTAssertFalse(app.buttons["filter-done"].waitForExistence(timeout: 3))
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "the reader keeps a feed after the transition")
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        // The lens states the criterion that is applied and removes exactly that one when its chip is tapped.
        let lensChip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'lens-chip-language-'")).firstMatch
        XCTAssertTrue(lensChip.waitForExistence(timeout: 10), "an applied criterion must show its chip")
        lensChip.tap()
        XCTAssertFalse(lensChip.waitForExistence(timeout: 5), "removing the chip clears that criterion")
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "the reader survives a criterion removal")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "t6-filter-transition"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// T5: the reading destinations that used to live in the navigation toolbar are now V1's overflow
    /// menu inside the floating header.
    @MainActor
    private func openMenu(_ app: XCUIApplication) {
        let menu = app.buttons["more-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the header must offer the overflow menu")
        menu.tap()
    }

    /// The element of the card whose top edge sits inside the scroll viewport and is closest to it.
    @MainActor
    private func topmostCard(app: XCUIApplication, scroll: XCUIElement) -> XCUIElement? {
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
        let top = scroll.frame.minY
        return cards.allElementsBoundByIndex
            .filter { $0.frame.height > 40 && $0.frame.minY >= top - 1 }
            .min { $0.frame.minY < $1.frame.minY }
    }

    /// U1-P8: one FeedScreen serves iPhone and iPad. Portrait and landscape keep every visible
    /// card inside the viewport (no horizontal overflow) and rotating never fabricates backward
    /// movement.
    @MainActor
    func testU1iPadLayoutPortraitAndLandscape() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        assertCardsFitInsideViewport(app: app, scroll: scroll, name: "u1-wide-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        assertCardsFitInsideViewport(app: app, scroll: scroll, name: "u1-wide-landscape")
        XCTAssertTrue(proof.label.hasSuffix("backward=0"),
            "rotation must not fabricate backward movement; observed: \(proof.label)")
        XCUIDevice.shared.orientation = .portrait
    }

    /// U1-P8 geometry: no card may be wider than the window (that is what a stretched or clipped
    /// card looks like) and none may exceed the tokenised readable column. XCUITest rounds
    /// accessibility frames outward, so the window comparison allows a small tolerance; the real
    /// failures this guards against (a card stretched across an iPad, or a clipped row) are tens
    /// of points wide, not fractions.
    @MainActor
    private func assertCardsFitInsideViewport(app: XCUIApplication, scroll: XCUIElement, name: String) {
        let viewport = scroll.frame
        XCTAssertGreaterThan(viewport.width, 0)
        let window = app.windows.firstMatch.frame
        let tolerance: CGFloat = 4
        // FeedDesignTokens.Measurement.readableContentWidth; duplicated here because the UI test
        // target does not link the package module.
        let readableColumn: CGFloat = 700
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
            .allElementsBoundByIndex
        XCTAssertFalse(cards.isEmpty, "\(name): a card must be visible")
        for card in cards {
            XCTAssertLessThanOrEqual(card.frame.width, window.width + tolerance,
                "\(name): a card is wider than the window (\(card.frame.width) vs \(window.width))")
            XCTAssertLessThanOrEqual(card.frame.width, readableColumn + tolerance,
                "\(name): a card exceeds the readable column (\(card.frame.width))")
            XCTAssertGreaterThan(card.frame.width, 100, "\(name): a card collapsed")
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
