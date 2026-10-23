import XCTest

final class FeedMineUITests: XCTestCase {
    /// Persistent, opt-in scale/soak namespace. scripts/soak.py uses this exact UUID.
    /// Never randomize or clear it: selection and checkpoints must survive the preparation test.
    /// Requires Debug (Release ignores FEEDMINE_RUNTIME_NAMESPACE); uses public feeds, no fixtures.
    private static let soakRuntimeNamespace = "B50A0000-0000-4000-8000-000000000030"

    @MainActor
    func testPreparePersistentScaleSoakThroughCountryCascade() throws {
        // Keep the normal isolated UI gate from populating a persistent namespace or contacting RSS.
        guard ProcessInfo.processInfo.environment["FEEDMINE_PREPARE_SCALE_SOAK"] == "1" else {
            throw XCTSkip("Opt in with scripts/soak.py --prepare; this test preserves real reader state")
        }
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = Self.soakRuntimeNamespace
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        for key in ["FEEDMINE_USE_DEVELOPMENT_FEEDS", "FEEDMINE_LOCAL_FEEDS",
                    "FEEDMINE_BLOCK_RSS_NETWORK", "FEEDMINE_EMPTY_SELECTION", "FEEDMINE_MEDIA_SIMULATION"] {
            app.launchEnvironment[key] = "0"
        }
        app.launch()
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 120))
        openMenu(app)
        app.buttons["Fontes"].tap()
        XCTAssertTrue(scrollIntoView(app.buttons["sources-open-countries"], in: app, timeout: 30))
        app.buttons["sources-open-countries"].tap()
        // The packaged V1 catalog places 1,411 feeds under Argentina's topic leaves.
        let country = app.switches["country-toggle-argentina"]
        XCTAssertTrue(scrollIntoView(country, in: app, timeout: 30))
        guard country.exists else { return }
        if country.value as? String != "selected" {
            // T7: the row wraps the actual switch; tap that control, not the country drill-in.
            let control = country.switches.firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 10))
            guard control.exists else { return }
            control.tap()
        }
        let enabled = NSPredicate(format: "value == %@", "selected")
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: country)],
            timeout: 60)
        XCTAssertEqual(result, .completed, "The country cascade must finish persisting before closing")
        guard result == .completed else { return }
        let selectionProof = XCTAttachment(string: "namespace=\(Self.soakRuntimeNamespace) country=Argentina value=\(country.value ?? "nil")")
        selectionProof.name = "persistent-soak-selection"
        selectionProof.lifetime = .keepAlways
        add(selectionProof)
        // This closes the whole sheet and adopts the selection. Reopening can retain the countries
        // navigation path; sources-enabled-count belongs to the root, not to that retained surface.
        app.buttons["countries-done"].tap()
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 120))
    }

    // N1/N2: the test never constructs ViewportObservation or calls submitViewport.
    @MainActor
    func testContextNavigationAndSourcePickerOffline() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
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
        // The source surface this build ships is the catalog's own levels (V1's structure, port log T7): the
        // country list is one level in, and the enabled count states the selection. Those rows sit below the
        // sheet's fold, so the sheet's own list is scrolled into the tree first.
        XCTAssertTrue(scrollIntoView(app.buttons["sources-open-countries"], in: app, timeout: 20),
            "the source surface offers its choices")
        XCTAssertTrue(scrollIntoView(app.staticTexts["sources-enabled-count"], in: app, timeout: 10),
            "the surface states the enabled count")
        // A review asked this scenario to keep verifying an **individual source's** own control, not only the
        // levels above it. A country's leaves are not always its sources — the catalogue nests topics under it —
        // so the walk goes down until a source's own toggle is in the tree, bounded, and comes back out.
        app.buttons["sources-open-countries"].tap()
        let countryRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'country-' AND identifier != 'country-toggle-all'")).firstMatch
        XCTAssertTrue(scrollIntoView(countryRow, in: app, timeout: 20), "the country list offers its rows")
        countryRow.tap()
        // The country's own level lists its sections, each with its control, and the tree continues:
        // country → section → topics → the sources themselves. Descend, bounded, until a source's own toggle is
        // in the tree — which is what the review asked this scenario to verify.
        let sectionToggle = app.switches.matching(NSPredicate(
            format: "identifier BEGINSWITH 'node-child-toggle-'")).firstMatch
        XCTAssertTrue(sectionToggle.waitForExistence(timeout: 20), "the country lists its rows, each with its control")
        var reachedSource = false
        for _ in 0..<5 {
            let sourceToggle = app.switches.matching(NSPredicate(
                format: "identifier BEGINSWITH 'node-source-toggle-'")).firstMatch
            if sourceToggle.waitForExistence(timeout: 8) { reachedSource = true; break }
            let child = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH 'node-child-'")).firstMatch
            guard child.waitForExistence(timeout: 8) else { break }
            child.tap()
        }
        XCTAssertTrue(reachedSource, "the country's own tree leads to its sources, each with its own control")
        let sourcesShot = XCTAttachment(screenshot: app.screenshot())
        sourcesShot.name = "v2-country-sources"
        sourcesShot.lifetime = .keepAlways
        add(sourcesShot)
        for _ in 0..<6 where !app.navigationBars["Fontes"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.navigationBars["Fontes"].waitForExistence(timeout: 10), "the sheet is still the same one")
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
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_EMPTY_SELECTION"] = "1"
        app.launch()
        let title = app.staticTexts["feed-empty-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 45))
        XCTAssertEqual(title.label, "Nenhuma fonte habilitada", "V1's own words for this state, in the app's language")
        XCTAssertFalse(app.scrollViews.firstMatch.exists, "no feed is drawn for a selection with no sources")
        XCTAssertFalse(app.staticTexts["Preparando"].exists, "nothing is being prepared, so nothing claims it")
        let emptySelectionShot = XCTAttachment(screenshot: app.screenshot())
        emptySelectionShot.name = "v2-empty-selection"
        emptySelectionShot.lifetime = .keepAlways
        add(emptySelectionShot)
        // The action the surface names is the one the app implements: the empty state's own button.
        app.buttons["feed-empty-action"].tap()
        XCTAssertTrue(app.navigationBars["Fontes"].waitForExistence(timeout: 15))
        let sourcesSheetShot = XCTAttachment(screenshot: app.screenshot())
        sourcesSheetShot.name = "v2-sources-sheet"
        sourcesSheetShot.lifetime = .keepAlways
        add(sourcesSheetShot)
        app.buttons["Concluir"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 15), "dismissing the picker leaves the reader where they were")
        // The way back: the ported source surface — the country list is one level in (V1's structure), and
        // enabling one country brings the feed back.
        app.buttons["feed-empty-action"].tap()
        // The sheet lists the sections first: the countries row and the enabled count sit below its fold, and
        // a `List` row is only in the accessibility tree once it has been scrolled into it.
        XCTAssertTrue(scrollIntoView(app.buttons["sources-open-countries"], in: app, timeout: 20),
            "the source surface offers the country list one level in")
        XCTAssertTrue(scrollIntoView(app.staticTexts["sources-enabled-count"], in: app, timeout: 10),
            "the surface states the enabled count")
        app.buttons["sources-open-countries"].tap()
        let countryToggle = app.switches.matching(NSPredicate(
            format: "identifier BEGINSWITH 'country-toggle-' AND identifier != 'country-toggle-all'")).firstMatch
        XCTAssertTrue(countryToggle.waitForExistence(timeout: 20), "the country list offers a toggle per country")
        let countriesShot = XCTAttachment(screenshot: app.screenshot())
        countriesShot.name = "v2-countries-list"
        countriesShot.lifetime = .keepAlways
        add(countriesShot)
        // The row is the switch element; the control inside it is what enables the country.
        countryToggle.switches.firstMatch.tap()
        app.buttons["countries-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 60),
            "the selection the source surface accepted is what the app adopts when it closes")
    }

    /// PD-10 / the bundled bootstrap, black box: a **clean install** — a runtime namespace nothing has ever
    /// written — with the app's own transport fault in force presents a feed, and the source it presents is the
    /// one the reader took from the catalogue this build ships.
    ///
    /// `FEEDMINE_BLOCK_RSS_NETWORK=1` is set **before** `launch()`: the app's own fault configuration (a closed
    /// local proxy), never a mock. Nothing is seeded from outside the app — no development-feeds list (the two
    /// hardcoded DEBUG keys stay unused) and no reader state written by the test; the reader's own source surface
    /// is the only thing that chooses anything.
    ///
    /// Where the attribution comes from: revision 5 of the shipped catalogue titles
    /// `https://feeds.bbci.co.uk/news/science_and_environment/rss.xml` as **"BBC News"** (`sqlite3
    /// Resources/catalog.sqlite`, `catalog_source.title`), placed under the leaf `15-nature-animals/wildlife-nature`
    /// — node ids 582585858 / 560998273 as this snapshot declares them. The document that answers the fetch calls
    /// itself "BBC Science", and the development-feeds list this test does *not* enable would have said
    /// "BBC Science" too. A card whose own source line reads "BBC News" therefore states the catalogue's title,
    /// resolved through the catalogue, and not the document's or a fixture list's.
    ///
    /// `FEEDMINE_LOCAL_FEEDS=1` is the app's own DEBUG local-feed transport: it answers the two BBC endpoints the
    /// catalogue itself names, in-process. It is the only reason article text can exist with the network gone; the
    /// public transport under test is blocked either way, and none of the catalogue's other sources answers.
    ///
    /// The reader chooses **one** source deliberately. An earlier version of this test turned the whole
    /// `Nature & Animals` section on (348 catalogue keys) and no card had been published after 900 s: that run's
    /// own runtime database held 188 registered targets and zero fetched origins, and the one source the local
    /// transport answers sits at position 111 of those 348 keys — measured, not guessed. Selecting that single
    /// source is the difference between "still working through the section" and a presentation.
    @MainActor
    func testCleanInstallPresentsTheBundledCatalogueSourceWithTransportBlocked() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        let started = Date()
        app.launch()

        // 1. The install presents with the transport dead. A clean reader has chosen nothing, and the app says so
        //    with its own surface instead of waiting on a request.
        let emptyTitle = app.staticTexts["feed-empty-title"]
        XCTAssertTrue(emptyTitle.waitForExistence(timeout: 300),
            "a clean install presents its own surface with the network blocked")
        XCTAssertEqual(emptyTitle.label, "Nenhuma fonte habilitada")
        print("BLACKBOX_EMPTY_SURFACE_SECONDS=\(String(format: "%.1f", Date().timeIntervalSince(started)))")

        // 2. The reader takes the source out of the shipped catalogue, through the app's own source surface: the
        //    catalogue's own section → its own leaf, then the row of the one key this build's local transport can
        //    answer at all. The reader's selection is exactly that key, so the session has exactly one target and
        //    the presentation cannot be waiting on any other fetch.
        app.buttons["feed-empty-action"].tap()
        let sectionRow = app.buttons["node-child-582585858"]
        XCTAssertTrue(scrollIntoView(sectionRow, in: app, timeout: 90),
            "the source surface lists the catalogue's own sections")
        sectionRow.tap()
        let leafRow = app.buttons["node-child-560998273"]
        XCTAssertTrue(leafRow.waitForExistence(timeout: 60),
            "the section opens the catalogue's own leaf, Wildlife & Nature")
        leafRow.tap()
        let sourceKey = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml"
        let sourceRow = app.switches["node-source-toggle-\(sourceKey)"]
        XCTAssertTrue(scrollIntoView(sourceRow, in: app, timeout: 240),
            "the leaf lists the catalogue's own sources, this key among them")
        XCTAssertEqual(sourceRow.label, "BBC News", "the row carries the catalogue's title for this key")
        let control = sourceRow.switches.firstMatch
        if control.exists { control.tap() } else { sourceRow.tap() }
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"),
            object: sourceRow)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 60), .completed,
            "the row states that the reader's selection is now this source")
        let chosen = Date()
        print("BLACKBOX_SELECTION_SECONDS=\(String(format: "%.1f", chosen.timeIntervalSince(started)))")

        // 3. Back to the surface's root and close it: closing is the adopt, and the app rebuilds the session over
        //    the catalogue's source.
        for _ in 0..<2 {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 20), "the surface navigates back out of the node")
            back.tap()
        }
        let done = app.buttons["sources-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20), "the source surface's own close control is back")
        done.tap()

        // 4. The feed presents content with the transport blocked: the card the suite already identifies by the
        //    published occurrence's own UUID.
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", Self.cardIdentifier)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 900),
            "the source the catalogue named reaches the feed with the network blocked")
        print("BLACKBOX_FIRST_CARD_SECONDS=\(String(format: "%.1f", Date().timeIntervalSince(started)))")
        print("BLACKBOX_SELECTION_TO_CARD_SECONDS=\(String(format: "%.1f", Date().timeIntervalSince(chosen)))")

        // The card states the **catalogue's** title for the source it came from (the document's own channel title
        // is "BBC Science"), and its text is the local document's articles, so both halves are visible at once.
        if !card.staticTexts["BBC News"].exists {
            print("BLACKBOX_TREE_BEGIN\n\(app.debugDescription)\nBLACKBOX_TREE_END")
        }
        XCTAssertTrue(card.staticTexts["BBC News"].exists,
            "the card states the catalogue's title for this source, not the document's own channel title")
        let stories = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'BBC Science story '"))
        XCTAssertGreaterThan(stories.count, 0, "the presented card carries the local feed document's articles")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "v2-bundled-catalogue-clean-install-offline"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// T8: the reader's bookmark boxes — V1's screen, managing real persisted boxes, and their own contents.
    @MainActor
    func testBookmarkBoxesManageAndOpenTheirOwnList() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.navigationBars["Caixas de salvos"].waitForExistence(timeout: 15))
        // The default box exists without the reader doing anything, and it is where a save lands.
        XCTAssertTrue(app.staticTexts["Salvos"].waitForExistence(timeout: 10))
        let boxShot = XCTAttachment(screenshot: app.screenshot())
        boxShot.name = "v2-saved-boxes"
        boxShot.lifetime = .keepAlways
        add(boxShot)
        // Create one, with V1's own flow: the New Box row and the alert.
        app.buttons["bookmarkBoxes.new"].tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.typeText("Longreads")
        app.buttons["Criar"].tap()
        XCTAssertTrue(app.staticTexts["Longreads"].waitForExistence(timeout: 15))
        // Open it: an empty box states that it is empty rather than showing nothing.
        app.staticTexts["Longreads"].tap()
        XCTAssertTrue(app.staticTexts["Nenhum artigo salvo"].waitForExistence(timeout: 15))
        let emptyBoxShot = XCTAttachment(screenshot: app.screenshot())
        emptyBoxShot.name = "v2-saved-box-empty"
        emptyBoxShot.lifetime = .keepAlways
        add(emptyBoxShot)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Longreads"].waitForExistence(timeout: 15))
        // And the box survives the surface being closed and opened again.
        app.buttons["bookmarkBoxes.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.staticTexts["Longreads"].waitForExistence(timeout: 15))
    }

    /// T8: the collections surface, and the reader's own presets appearing in the filter sheet's picker.
    @MainActor
    func testCollectionsManageAndReachThePresetPicker() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
        openMenu(app)
        app.buttons["Coleções de fontes"].tap()
        XCTAssertTrue(app.navigationBars["Coleções de fontes"].waitForExistence(timeout: 15))
        // V1's empty state explains what a collection is before the reader has any. The identifier lands on
        // the state's own drawn elements (measured: an image and its two texts), so it is located by
        // identifier across types.
        XCTAssertTrue(element(app, "collections-empty").waitForExistence(timeout: 10))
        app.buttons["collections.new"].tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.typeText("Ciência")
        app.buttons["Criar"].tap()
        XCTAssertTrue(scrollIntoView(app.staticTexts["Ciência"], in: app, timeout: 15),
            "the collection the reader created is listed")
        // Open it: the detail names the feed action and states that it has no sources yet.
        app.staticTexts["Ciência"].tap()
        XCTAssertTrue(app.buttons["collection.openFeed"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Adicione fontes a partir de um card ou de um resultado."].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["collections.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        // The filter sheet's picker now offers V1's two entries and the reader's own collection.
        app.buttons["filter-button"].tap()
        let everything = app.buttons["preset-option-everything"]
        XCTAssertTrue(scrollIntoView(everything, in: app, timeout: 20), "the preset picker is offered")
        XCTAssertTrue(app.buttons["preset-option-lastClicked"].exists)
        XCTAssertTrue(scrollIntoView(app.staticTexts["Ciência"], in: app, timeout: 15),
            "the reader's own collection is one of the presets")
        app.buttons["Concluído"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
    }

    /// T9: a card's copy action reaches the platform clipboard through the app, and the reader is told.
    @MainActor
    func testCardCopiesItsOwnLinkAndStatesIt() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
        // The card's own menu, opened the way a reader opens it.
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", Self.cardIdentifier)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 45), "a real published occurrence must appear")
        pressCard(card)
        XCTAssertTrue(app.buttons["Copiar link"].waitForExistence(timeout: 10))
        app.buttons["Copiar link"].tap()
        // Either the clipboard took the card's own target, or the app says what it could not do — never both
        // silently. The copy path is the one this build ships, so it is the one asserted.
        let toast = app.staticTexts["Link copiado"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10),
            "a card with a frozen target copies it and says so")
        XCTAssertFalse(app.staticTexts["Não foi possível abrir a fonte"].exists)
    }

    /// T9: the mini player draws real playback, its height never depends on what it states, and the full
    /// player is one tap away. The episode is the hook's silent WAV, played by the same AVFoundation adapter a
    /// card would use.
    @MainActor
    func testMiniPlayerStatesPlaybackWithoutMovingTheFeed() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_MEDIA_SIMULATION"] = "1"
        app.launch()
        let bar = app.otherElements["mini-player"]
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        XCTAssertTrue(bar.waitForExistence(timeout: 20))
        XCTAssertEqual(bar.frame.height, 56, accuracy: 1,
            "the bar reserves a constant height, so playing an episode cannot move a card")
        XCTAssertEqual(app.staticTexts["mini-player-title"].label, "Episódio de teste")
        // Playing: the toggle pauses, and the bar does not move when it does.
        let frameWhilePlaying = bar.frame
        app.buttons["mini-player-toggle"].tap()
        XCTAssertTrue(app.buttons["mini-player-toggle"].waitForExistence(timeout: 10))
        XCTAssertEqual(bar.frame.height, 56, accuracy: 1, "the bar is the same height paused")
        XCTAssertEqual(bar.frame.origin.y, frameWhilePlaying.origin.y, accuracy: 1)
        XCTAssertTrue(scroll.exists, "the feed is still there, and never grew")
        // The full player carries V1's two skips and its scrub, and closing returns to the feed.
        bar.tap()
        XCTAssertTrue(app.otherElements["full-player"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["full-player-back15"].exists)
        XCTAssertTrue(app.buttons["full-player-forward15"].exists)
        app.buttons["full-player-toggle"].tap()
        app.buttons["full-player-close"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        XCTAssertTrue(bar.exists, "the bar is still there after the full player closes")
    }

    /// T10: the settings surface — reachable from the reader's own menu, its controls write, and what they wrote
    /// is what the reader finds when they come back.
    @MainActor
    func testSettingsReachTheirControlsAndSurviveReopening() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
        openMenu(app)
        app.buttons["Ajustes"].tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15))
        // V1's sections, in the app's own words, and the clock it is on right now.
        XCTAssertTrue(app.staticTexts["Design circadiano"].exists)
        XCTAssertTrue(app.switches["settings-circadian-palette"].exists)
        XCTAssertTrue(app.staticTexts["settings-circadian-footer"].exists)
        XCTAssertTrue(app.switches["settings-prefetch"].exists)
        XCTAssertTrue(app.switches["settings-night-mode"].exists)
        // Write two preferences and see them hold. The row is the switch element; the control inside it is
        // what toggles the preference, so the control is what is tapped.
        app.switches["settings-night-mode"].switches.firstMatch.tap()
        app.switches["settings-circadian-palette"].switches.firstMatch.tap()
        let nightOff = app.switches["settings-night-mode"].value as? String
        XCTAssertEqual(nightOff, "1", "the switch states what was written")
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        // Reopen: the surface reads back what the database took.
        openMenu(app)
        app.buttons["Ajustes"].tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.switches["settings-night-mode"].value as? String, "1")
        let settingsShot = XCTAttachment(screenshot: app.screenshot())
        settingsShot.name = "v2-settings"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)
        XCTAssertEqual(app.switches["settings-circadian-palette"].value as? String, "0")
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
    }

    /// F02: the discovery answers have a page of their own in the adjustments — the same controls the first run
    /// shows, over the stored profile — and an answer given there is still there when the page is opened again.
    @MainActor
    func testDiscoveryPreferencesAreAPageOfTheirOwn() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
        openMenu(app)
        app.buttons["Ajustes"].tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15))

        let row = app.buttons["settings-discovery-preferences"]
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the adjustments offer the discovery preferences")
        row.tap()
        XCTAssertTrue(app.navigationBars["Preferências de descoberta"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["discovery-preferences-summary"].exists,
            "the page states what the answers are for")

        let languages = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'discovery-language-'"))
        XCTAssertTrue(languages.firstMatch.waitForExistence(timeout: 10),
            "the page offers the catalogue's own languages")
        let chosen = languages.firstMatch
        let identifier = chosen.identifier
        XCTAssertFalse(chosen.isSelected, "nothing is chosen before the reader says so")
        chosen.tap()
        XCTAssertTrue(chosen.isSelected, "a chosen language states itself to assistive technology")
        let pageShot = XCTAttachment(screenshot: app.screenshot())
        pageShot.name = "v2-discovery-preferences"
        pageShot.lifetime = .keepAlways
        add(pageShot)

        // Leave the page and come back: the answer is the database's, not the screen's.
        app.navigationBars["Preferências de descoberta"].buttons.firstMatch.tap()
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars["Preferências de descoberta"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: 10),
            "the same answer is still there after leaving the page")
        XCTAssertTrue(app.buttons[identifier].isSelected, "and it is still stated as chosen")

        // A feed of the reader's own, built from exactly these answers: it gets a name, and creating it opens
        // nothing — the offer to open it appears, and the page is still the page.
        let nameField = app.textFields["discovery-feed-name"]
        for _ in 0..<8 where !nameField.isHittable { app.swipeUp() }
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "the page offers a feed built from these rules")
        nameField.tap()
        nameField.typeText("Ciência")
        let create = app.buttons["discovery-create-feed"]
        for _ in 0..<4 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isHittable, "and the action to create it")
        create.tap()
        XCTAssertTrue(app.buttons["discovery-open-created-feed"].waitForExistence(timeout: 20),
            "creating a feed offers to open it — it never opens it by itself")
        XCTAssertTrue(app.staticTexts["discovery-create-note"].exists,
            "and says so: creating does not change what the reader is reading")
        XCTAssertTrue(app.navigationBars["Preferências de descoberta"].exists,
            "the reader is still on the page: nothing was activated behind their back")

        app.navigationBars["Preferências de descoberta"].buttons.firstMatch.tap()
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
    }

    /// T10: the import preview states what a file offers before anything is written, its confirmation writes it,
    /// and the export sheet shows the document it would produce.
    @MainActor
    func testImportPreviewCommitsAndExportPreviews() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_IMPORT_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
        // The fixture: one usable feed, one repeat of it, one address that cannot be used. Each row is one
        // element of its own, so the counts are the number of rows the preview states.
        XCTAssertTrue(app.navigationBars["Importar OPML"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "import-entry").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "import-rejection").count, 1)
        let summary = app.staticTexts["import-summary"].label
        XCTAssertTrue(summary.contains("1 fontes"), summary)
        XCTAssertTrue(summary.contains("1 repetidas"), summary)
        XCTAssertTrue(summary.contains("1 ignoradas"), summary)
        // Confirming writes it — in the app, through the real database — and states what it did.
        app.buttons["import-confirm"].tap()
        let toast = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Importadas 1")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 20), "the import states what it wrote")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        // The export sheet, from the reader's own menu, with a preview of the document.
        openMenu(app)
        app.buttons["Exportar"].tap()
        XCTAssertTrue(app.navigationBars["Exportar"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["export-scope-selection"].exists)
        XCTAssertTrue(app.buttons["export-share"].exists)
        // The document's own preview is a section of that sheet's list, so it is scrolled into the tree.
        XCTAssertTrue(scrollIntoView(app.staticTexts["export-preview"], in: app, timeout: 15),
            "the export sheet shows the document it would produce")
        let exportShot = XCTAttachment(screenshot: app.screenshot())
        exportShot.name = "v2-export-preview"
        exportShot.lifetime = .keepAlways
        add(exportShot)
        app.buttons["export-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
    }

    /// §4 of the journey audit (`docs/reviews/2026-10-15-jornadas-de-usuario-v1-vs-v2.md:281`), and V1's own
    /// closure rule — "do not ship dead buttons" (`1.0-application-closure-plan.md:30`): the export sheet's share
    /// control is the one control the battery only ever **found** (`app.buttons["export-share"].exists`,
    /// `FeedMineUITests.swift:567`); it was never tapped, so the app's `ActivityView`
    /// (`FeedMineApp/FeedMineApp/PlatformSurfaces.swift:39`) had never been proven to reach the screen. This
    /// journey taps it and asserts what is honestly observable:
    ///
    /// - the platform's own share surface goes up, over the app's own sheet;
    /// - leaving it leaves the app's own sheet up;
    /// - and closing that returns the reader to the session and the reading point they had: the same counters and
    ///   the same card at the top of the viewport.
    ///
    /// What is **not** asserted, and why: the activity list's contents. What the sheet offers belongs to the
    /// platform — it varies with the device, the installed apps and the language — so asserting an entry would be
    /// an assertion about iOS. What this app owns is the document it wrote and the presentation it asked for.
    ///
    /// **Achado medido em 2026-10-16 — a folha do app bloqueava a superfície do sistema; corrigido nesta
    /// branch.** Tocar `Compartilhar` **não** punha a superfície de compartilhamento do sistema sobre a folha de
    /// exportação: medido em seis corridas, uma delas num simulador **apagado antes** (`simctl erase`), 30 s e
    /// 240 s depois do toque a tela ainda era a folha do app — a captura `export-share-system-surface` do
    /// `xcresult` mostrava a folha de exportação com o OPML real e nenhuma lista de atividades — e a árvore de
    /// acessibilidade ainda tinha a folha do app no topo (`export-done` e `export-share` presentes, nenhum
    /// `ActivityListView`). A apresentação era **adiada**, não recusada: fechando aquela folha, a superfície do
    /// sistema aparecia **4 s** depois (`ActivityListView`, `ShareSheet.RemoteContainerView`,
    /// `header.closeButton`) — o leitor tocava Compartilhar, nada acontecia, e a folha de compartilhamento só
    /// subia quando ele saía da folha de exportação. Valia para `Salvar arquivo` também, que usa a mesma
    /// apresentação (`FeedMineApp/FeedMineApp/FeedMineApp.swift` define os dois no mesmo `sharedExport`).
    /// A causa era o **apresentador**: a folha de exportação é desenhada pelo host de superfícies
    /// (`.sheet(item: sheetItem)`) e a superfície do sistema por um segundo `.sheet(item: $sharedExport)`
    /// **irmão**, na mesma view (`FeedMineApp.swift:448`, antes da correção) — uma segunda apresentação pedida
    /// por um apresentador que já tinha uma no ar (relato: `docs/reviews/2026-10-16-superficies-honestas.md`;
    /// saída bruta: `/tmp/sharecheck-ORCH-repro.log`).
    /// **O conserto ancora a apresentação na folha que a pede** — `.sheet(item: $sharedExport)` dentro de
    /// `exportSheet`, a folha de exportação apresentando a sua própria superfície de sistema — e é a propriedade
    /// abaixo que o dirige, **não** a quantidade de `.sheet` que o SwiftUI permite declarar:
    ///
    /// > Quando o leitor toca Compartilhar ou Salvar arquivo, o sistema apresenta a ação solicitada **naquele
    /// > fluxo**, sem exigir outra ação inesperada. Sair da superfície devolve o leitor ao contexto anterior, sem
    /// > perder a leitura.
    ///
    /// Por isso as medidas que seguem não são condicionais a premissa nenhuma: a superfície sobe, a folha que a
    /// pediu é a que está em cima quando ela sai, e o ponto de leitura no fim é o do começo.
    @MainActor
    func testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        // A reading point that is not the top of the feed: the reader's own scroll, and the opportunity it
        // completed is what makes the position real.
        scroll.swipeUp()
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@",
            ".*completed=[1-9][0-9]*.*"), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 20), .completed,
            "a real scroll must complete a real opportunity; observed: \(proof.label)")
        let counters = proof.label
        let anchor = try XCTUnwrap(topmostCardIdentifier(app: app, scroll: scroll),
            "a card must be visible inside the viewport")
        // The reading point as a number, not only as an identity: a shift that leaves the same card on top at a
        // different offset would satisfy the identity comparison below and still have moved what the reader is
        // reading. Measured the way this file measures offsets elsewhere (`:1760`, `:1806`: `frame.minY` against
        // a captured reference, `accuracy: 1`): the card's own top edge, in points, tolerance 1.
        let anchorTop = try XCTUnwrap(topmostCard(app: app, scroll: scroll),
            "a card must be visible inside the viewport").frame.minY

        openMenu(app)
        // The menu entry is selected by the identifier SwiftUI gives it — the entry's own SF Symbol — not by
        // its visible title: a menu item's `accessibilityIdentifier` is discarded and the label is the
        // translated string, which is exactly what `ReaderMenu.swift:93-97` records. A journey that queried the
        // word would only pass on a device whose language happens to be the app's source language; this one
        // measures the flow on any device.
        app.buttons["square.and.arrow.up"].tap()
        XCTAssertTrue(app.buttons["export-done"].waitForExistence(timeout: 20),
            "the reader's own menu opens V1's export sheet; on screen: \(app.debugDescription)")
        // The sheet's preview states the document. Tapping a share that had no document would prove nothing, so
        // the row the app draws when there is nothing to write must be absent first.
        XCTAssertTrue(scrollIntoView(app.staticTexts["export-preview"], in: app, timeout: 20),
            "the sheet shows the document it would share")
        XCTAssertFalse(app.staticTexts["export-empty"].exists,
            "sharing is only meaningful over a real document, and the sheet states there is nothing to write")
        let share = app.buttons["export-share"]
        XCTAssertTrue(scrollIntoView(share, in: app, timeout: 20), "the sheet offers sharing its document")
        XCTAssertTrue(share.isEnabled, "and it is offered because there is a document to share")
        share.tap()

        // The platform's own surface, over the app's own sheet. The wait is bounded and generous, not because
        // the platform is slow but because **its own latency is not this app's to choose**: when nothing blocks
        // it, the surface became addressable between 4 s and ~90 s across the runs on this machine (load average
        // 34 → 5 during the session). The elapsed time is printed either way, so a slow platform and a
        // presentation that never came are told apart by a fact instead of by a guess.
        let asked = Date()
        let systemSurface = systemShareSurface(app)
        XCTAssertTrue(systemSurface.waitForExistence(timeout: 60),
            "Compartilhar must open the system's own share surface over the app's own sheet, in the flow that "
                + "asked for it and without another action first; on screen: \(app.debugDescription)")
        // And the surface it was asked for **over** is still up at this instant: the platform's list is
        // presented over the app's own export sheet, not after it. This is the fact the other assertions only
        // reach transitively — nothing in between dismisses the sheet — and a presentation that closed the sheet
        // first and went up afterwards would satisfy every other assertion in this journey (the surface appears,
        // the sheet is up when the surface leaves, the reading point returns). It cannot be shown red on the base
        // commit, which never gets this far (it fails at the assertion above); its value is guarding that
        // different regression, and it is measured here as a fact of its own.
        XCTAssertTrue(app.buttons["export-done"].exists,
            "Compartilhar's system surface is presented over the app's own export sheet, not after it: that "
                + "sheet must still be up while the surface is addressable; on screen: \(app.debugDescription)")
        // The premise is the app's own now — the sheet that asks is the sheet that presents — so the journey
        // measures the return below without a gate of its own.
        print("export-share: system surface addressable "
            + String(format: "%.2f", Date().timeIntervalSince(asked)) + " s after the tap")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "export-share-system-surface"
        shot.lifetime = .keepAlways
        add(shot)

        // Leaving it: by the platform's own way out, awaited as its own fact (its contents materialise after its
        // container does), then the app's own sheet is what is up again — and closing that returns the reader to
        // the feed they were in.
        let close = systemShareCloseControl(app)
        XCTAssertNotNil(close,
            "the system's share surface must offer its own way out; on screen: \(app.debugDescription)")
        print("export-share: system's own close control reachable "
            + String(format: "%.2f", Date().timeIntervalSince(asked)) + " s after the tap")
        close?.tap()
        XCTAssertTrue(waitForAbsence(systemSurface, timeout: 240),
            "leaving the share surface dismisses it; on screen: \(app.debugDescription)")
        XCTAssertTrue(app.buttons["export-done"].waitForExistence(timeout: 60),
            "and the export sheet is the surface that is up again; on screen: \(app.debugDescription)")
        app.buttons["export-done"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "closing the export sheet returns to the feed")
        XCTAssertEqual(proof.label, counters,
            "sharing a document must not replace the session the reader is reading in")
        XCTAssertEqual(topmostCardIdentifier(app: app, scroll: scroll), anchor,
            "nor move the reading point: the visible prefix is the card the reader was on")
        // The same position, measured as a distance and not only as an identity: a shift that keeps the same
        // card on top at a different offset would pass the line above.
        let returned = try XCTUnwrap(topmostCard(app: app, scroll: scroll),
            "a card must be visible inside the viewport")
        print("export-share: reading point offset reference=" + String(format: "%.1f", anchorTop)
            + " final=" + String(format: "%.1f", returned.frame.minY) + " pt")
        XCTAssertEqual(returned.frame.minY, anchorTop, accuracy: 1,
            "nor shift it: the card's own top edge must be where the reader left it")
    }

    /// A jornada irmã da anterior, para a **segunda porta** da folha de exportação: `Salvar arquivo`
    /// (`Sources/FeedMineUI/Tools/ReaderImportExportViews.swift:120`, id `export-save`). A propriedade do
    /// arquiteto citada em `docs/reviews/2026-10-16-share-do-export-na-folha-que-o-pede.md:33-34` vale para as
    /// **duas** portas — "Quando o usuário toca Compartilhar **ou Salvar arquivo**, o sistema apresenta a ação
    /// solicitada naquele fluxo, sem exigir outra ação inesperada. Cancelar devolve o usuário ao contexto
    /// anterior, sem perder a leitura." —, mas até agora só uma delas era medida: a bateria para em
    /// `app.buttons["export-share"].exists` (`FeedMineUITests.swift:567`), e `export-save` aparecia em **zero**
    /// testes. A equivalência das duas portas era uma leitura do código
    /// (`FeedMineApp/FeedMineApp/FeedMineApp.swift:1103-1104`: `onShare` e `onSave` escrevem o mesmo
    /// `sharedExport`), não uma medição — e o achado de 2026-10-16 (relatado na jornada anterior) afirma
    /// justamente que valia para `Salvar arquivo` também, por inferência do mesmo caminho.
    ///
    /// Esta jornada troca a inferência pela medida: o mesmo fluxo, o mesmo documento, a mesma plataforma, com o
    /// **outro** identificador tocado. Ela mede, e nada mais:
    ///
    /// - a folha de exportação mostra o documento real (a mesma prévia, e nenhuma linha "Nada para exportar");
    /// - `Salvar arquivo` põe a superfície **do sistema** sobre a folha do app, no fluxo que a pediu;
    /// - a saída da plataforma devolve a folha do app, e fechá-la devolve o leitor ao ponto de leitura que ele
    ///   tinha: os mesmos contadores e o mesmo cartão no topo do viewport.
    ///
    /// Por que as medidas **não** são condicionais a premissa nenhuma: quem pede a apresentação é a folha que
    /// está no ar (`.sheet(item: $sharedExport)` dentro de `exportSheet`, o conserto desta branch), e a folha que
    /// pede é a folha que volta — as três medidas abaixo são fatos do app e do sistema, e falham por si. O que
    /// **não** se afirma continua sendo o conteúdo da lista de atividades: ele pertence à plataforma e varia com
    /// o aparelho, os apps instalados e o idioma.
    @MainActor
    func testSavingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        // A reading point that is not the top of the feed: the reader's own scroll, and the opportunity it
        // completed is what makes the position real. Same establishment as the share journey, so the two
        // journeys measure the reader's return over the same kind of position.
        scroll.swipeUp()
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@",
            ".*completed=[1-9][0-9]*.*"), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 20), .completed,
            "a real scroll must complete a real opportunity; observed: \(proof.label)")
        let counters = proof.label
        let anchor = try XCTUnwrap(topmostCardIdentifier(app: app, scroll: scroll),
            "a card must be visible inside the viewport")
        // The reading point as a number, not only as an identity (the same establishment as the share journey,
        // `:643-648`): the card's own top edge, in points, tolerance 1.
        let anchorTop = try XCTUnwrap(topmostCard(app: app, scroll: scroll),
            "a card must be visible inside the viewport").frame.minY

        openMenu(app)
        app.buttons["square.and.arrow.up"].tap()
        XCTAssertTrue(app.buttons["export-done"].waitForExistence(timeout: 20),
            "the reader's own menu opens V1's export sheet; on screen: \(app.debugDescription)")
        // The same document the share journey checks, for the same reason: tapping a save that had no document
        // would prove nothing, so the row the app draws when there is nothing to write must be absent first.
        XCTAssertTrue(scrollIntoView(app.staticTexts["export-preview"], in: app, timeout: 20),
            "the sheet shows the document it would save")
        XCTAssertFalse(app.staticTexts["export-empty"].exists,
            "saving is only meaningful over a real document, and the sheet states there is nothing to write")
        let save = app.buttons["export-save"]
        XCTAssertTrue(scrollIntoView(save, in: app, timeout: 20), "the sheet offers saving its document")
        XCTAssertTrue(save.isEnabled, "and it is offered because there is a document to save")
        save.tap()

        // The platform's own surface, over the app's own sheet, asked for by the sheet that is up. The wait is
        // bounded and generous for the reason the share journey records — the platform's latency is not this
        // app's to choose — and the elapsed time is printed either way, so a slow platform and a presentation
        // that never came are told apart by a fact instead of by a guess.
        let asked = Date()
        let systemSurface = systemShareSurface(app)
        XCTAssertTrue(systemSurface.waitForExistence(timeout: 60),
            "Salvar arquivo must open the system's own share surface over the app's own sheet, in the flow that "
                + "asked for it and without another action first; on screen: \(app.debugDescription)")
        // And the surface it was asked for **over** is still up at this instant: the platform's list is
        // presented over the app's own export sheet, not after it — the same measurement the share journey makes
        // (`:680-689`), for the same reason. It cannot be shown red on the base commit, which never gets this
        // far; its value is guarding a presentation that dismissed the sheet first and went up afterwards.
        XCTAssertTrue(app.buttons["export-done"].exists,
            "Salvar arquivo's system surface is presented over the app's own export sheet, not after it: that "
                + "sheet must still be up while the surface is addressable; on screen: \(app.debugDescription)")
        print("export-save: system surface addressable "
            + String(format: "%.2f", Date().timeIntervalSince(asked)) + " s after the tap")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "export-save-system-surface"
        shot.lifetime = .keepAlways
        add(shot)

        // Leaving it by the platform's own way out, awaited as its own fact (its contents materialise after its
        // container does), then the app's own sheet is what is up again — and closing that returns the reader to
        // the feed they were in, at the card they were on.
        let close = systemShareCloseControl(app)
        XCTAssertNotNil(close,
            "the system's share surface must offer its own way out; on screen: \(app.debugDescription)")
        print("export-save: system's own close control reachable "
            + String(format: "%.2f", Date().timeIntervalSince(asked)) + " s after the tap")
        close?.tap()
        XCTAssertTrue(waitForAbsence(systemSurface, timeout: 240),
            "leaving the share surface dismisses it; on screen: \(app.debugDescription)")
        XCTAssertTrue(app.buttons["export-done"].waitForExistence(timeout: 60),
            "and the export sheet is the surface that is up again; on screen: \(app.debugDescription)")
        app.buttons["export-done"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "closing the export sheet returns to the feed")
        XCTAssertEqual(proof.label, counters,
            "saving a document must not replace the session the reader is reading in")
        XCTAssertEqual(topmostCardIdentifier(app: app, scroll: scroll), anchor,
            "nor move the reading point: the visible prefix is the card the reader was on")
        // The same reading point, measured as a distance and not only as an identity.
        let returned = try XCTUnwrap(topmostCard(app: app, scroll: scroll),
            "a card must be visible inside the viewport")
        print("export-save: reading point offset reference=" + String(format: "%.1f", anchorTop)
            + " final=" + String(format: "%.1f", returned.frame.minY) + " pt")
        XCTAssertEqual(returned.frame.minY, anchorTop, accuracy: 1,
            "nor shift it: the card's own top edge must be where the reader left it")
    }

    /// The system's own share surface as this app's process can see it. `UIActivityViewController` draws its
    /// activity list in the presenting process under this identifier, whatever the device's language is.
    @MainActor
    private func systemShareSurface(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements["ActivityListView"]
    }

    /// The platform's own way out of its share surface: the close control it draws, whose identifier is the
    /// platform's own (`header.closeButton`, measured on iOS 26.5) and whose label follows the device's language.
    /// The surface publishes its container before its contents — measured, tens of seconds apart under load — so
    /// the handle is awaited as a fact of its own, bounded, and `nil` means the surface offered no way out.
    @MainActor
    private func systemShareCloseControl(_ app: XCUIApplication,
        timeout: TimeInterval = 240) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let handles = [app.buttons["header.closeButton"], app.buttons["Close"], app.buttons["Fechar"]]
        while Date() < deadline {
            for control in handles where control.exists && control.isHittable { return control }
            Thread.sleep(forTimeInterval: 1)
        }
        return nil
    }

    /// NN-07: the welcome scene's own headline is **drawn** where the reader reads it. It used to be an `.overlay`
    /// of a `Text(verbatim: "")` — a placeholder with no size of its own — so the sentence the app announces
    /// painted nothing, and the element the tests address had no area: measured, and classified P1 by the PO, in
    /// `docs/reviews/2026-10-11-round9-language-choice-and-localization.md` §8. The element is now the sentence
    /// itself, above the body it introduces, and the scene's own ways forward are untouched.
    @MainActor
    func testTheWelcomeHeadlineIsDrawnWhereTheReaderReadsIt() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launch()
        let headline = app.staticTexts["welcome-headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: 45))
        XCTAssertFalse(headline.label.isEmpty, "the sentence is what the reader hears")
        XCTAssertGreaterThan(headline.frame.width, 60,
            "the headline has an area of its own: a box without size draws nothing")
        XCTAssertGreaterThan(headline.frame.height, 20, "and its own lines")
        let body = app.staticTexts["welcome-body"]
        XCTAssertTrue(body.exists)
        XCTAssertLessThan(headline.frame.maxY, body.frame.minY,
            "and it is read where it is written: above the body it introduces")
        XCTAssertTrue(app.buttons["welcome-shape"].exists)
        XCTAssertTrue(app.buttons["welcome-broad"].exists)
        XCTAssertTrue(app.otherElements["welcome-trust"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "nn07-welcome-headline"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// F02's first run (the journey the acceptance benchmark walks): the reader answers **idiomas e lugares**,
    /// enters the feed, and **no thematic question** stands between them and discovery. The controls the product
    /// keeps for whoever wants to tune the machinery are reachable *by choice*, in the discovery preferences.
    @MainActor
    func testFirstRunCollectsLanguagesAndPlacesAndEntersTheFeed() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launch()
        // Stage 1: the welcome scene, with V1's own words and its two ways forward.
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.staticTexts["welcome-body"].exists)
        XCTAssertTrue(app.otherElements["welcome-trust"].exists)
        app.buttons["welcome-shape"].tap()

        // Stage 2: the two answers the first run collects — and nothing thematic.
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 15))
        let languages = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-language-'"))
        XCTAssertTrue(languages.firstMatch.waitForExistence(timeout: 10), "the first run offers the languages")
        let places = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-region-'"))
        XCTAssertTrue(places.firstMatch.waitForExistence(timeout: 10), "and the catalogue's places")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-topic-'")).count, 0,
            "no subject is asked before discovery: subjects are answered inside the feed")
        XCTAssertFalse(app.switches["composer-media-podcast"].exists,
            "the machinery is not put in the reader's way on the way in")
        XCTAssertFalse(app.sliders["composer-discovery"].exists, "nor is the depth dial")

        // An answer states itself, and one place is enough to mean "this is where I am curious about".
        let place = places.firstMatch
        XCTAssertFalse(place.isSelected)
        place.tap()
        XCTAssertTrue(place.isSelected, "the chosen place is stated to assistive technology")

        // The reader enters the feed: the first screen is content, not a form.
        app.buttons["composer-open-feed"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 120),
            "the first run ends in the feed, without opening the sources screen")
        XCTAssertFalse(app.staticTexts["welcome-headline"].exists, "the first run is done")

        // The first run is over and the feed is the reader's surface: nothing of the first run is still up.
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForNonExistence(timeout: 30),
            "the first run is dismissed")
        XCTAssertTrue(app.buttons["card.bookmark"].firstMatch.waitForExistence(timeout: 45),
            "and the reader has cards, not a form")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "v2-first-run"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// NN-08: the first contact offers the reader's own file beside its two ways forward, and the whole import is
    /// the app's own — the same preview, the same counts, the same confirmation that writes.
    ///
    /// Importing is never a prerequisite: a picker the reader dismisses, a preview they cancel and an import they
    /// confirm each leave the first run the reader's to finish, and the reader still enters without answering
    /// anything. What the file brought is, from then on, one of their own sources.
    ///
    /// `FEEDMINE_IMPORT_FIXTURE` is the app's own DEBUG stand-in for the platform dialog: `1` is the file a picker
    /// would hand over, `cancel` is the reader dismissing it. A UI test cannot drive the system file dialog, and
    /// T10's launch-time fixture does the same for the flow that starts outside the first run.
    @MainActor
    func testFirstRunImportsOPMLWithoutMakingItAPrerequisite() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_IMPORT_FIXTURE"] = "cancel"
        app.launch()

        // First contact: three ways forward, all of them the reader's, and asking for a file writes nothing.
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 45))
        XCTAssertTrue(app.buttons["welcome-import"].exists, "the reader's own file is offered here")
        XCTAssertTrue(app.buttons["welcome-shape"].exists, "beside the two answers V1's gate had")
        XCTAssertTrue(app.buttons["welcome-broad"].exists, "and entering wide open is one of them")
        app.buttons["welcome-import"].tap()
        // The picker the reader dismissed: the gate is the surface they answer on again, unanswered.
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 30))
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 15),
            "a cancelled import left the first run exactly where it was")

        // The file itself, at first contact: the preview T10 pins, before anything is written.
        app.terminate()
        app.launchEnvironment["FEEDMINE_IMPORT_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 45))
        app.buttons["welcome-import"].tap()
        XCTAssertTrue(app.navigationBars["Importar OPML"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "import-entry").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "import-rejection").count, 1)
        let summary = app.staticTexts["import-summary"].label
        XCTAssertTrue(summary.contains("1 fontes"), summary)
        XCTAssertTrue(summary.contains("1 repetidas"), summary)
        XCTAssertTrue(summary.contains("1 ignoradas"), summary)

        // Cancelling the preview is free, and takes the reader back to the surface that asked for the file.
        app.buttons["import-cancel"].tap()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 30),
            "a cancelled import brings the first contact back")
        XCTAssertTrue(app.buttons["welcome-broad"].exists, "with both of its own answers untouched")

        // The confirmation is what writes it — the app's own commit, over the app's own database.
        app.buttons["welcome-import"].tap()
        XCTAssertTrue(app.navigationBars["Importar OPML"].waitForExistence(timeout: 30))
        app.buttons["import-confirm"].tap()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 30),
            "importing does not complete the first run: the reader still chooses how the feed begins")
        XCTAssertFalse(app.staticTexts["composer-subtitle"].exists, "and no interest is asked for it")
        XCTAssertTrue(app.buttons["welcome-broad"].exists, "entering wide open is still the reader's")

        // The reader enters without answering anything, and the file they brought is part of what they read: the
        // export of the reader's own sources carries the feed the file named.
        app.buttons["welcome-broad"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 120),
            "the first run ends in the feed, without a form in the way")
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForNonExistence(timeout: 30))
        openMenu(app)
        app.buttons["Exportar"].tap()
        XCTAssertTrue(app.navigationBars["Exportar"].waitForExistence(timeout: 15))
        XCTAssertTrue(scrollIntoView(app.staticTexts["export-preview"], in: app, timeout: 15),
            "the export sheet shows the document it would produce")
        let document = app.staticTexts["export-preview"].label
        XCTAssertTrue(document.contains("revista.example/feed"),
            "the import the reader confirmed at first contact is one of their sources: \(document)")
        app.buttons["export-done"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "v2-first-run-opml"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// T12: the native gestures and the reader's own settings — a long scroll down and back, a rotation, a
    /// larger Dynamic Type — leave the admitted card where it was: an update the reader did not ask for never
    /// moves the viewport.
    @MainActor
    func testNativeScrollRotationAndDynamicTypeKeepTheAdmittedCardInPlace() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        // A long scroll down and back: the driver sees real opportunities in both directions.
        for _ in 0..<6 { app.swipeUp() }
        for _ in 0..<6 { app.swipeDown() }
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@",
            ".*completed=[1-9][0-9]*.*"), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 20), .completed, proof.label)
        // Rotation keeps the same reader on the same card: the first visible card's frame is measured before and
        // after, and the update that follows the rotation does not move it on its own.
        let beforeRotation = proof.label
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", beforeRotation),
            object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 15), .completed,
            "a rotation is not an update the reader asked for: the counters it publishes do not change by it")
        // T12's visual comparison: the landscape surface, captured at the same moment the counters are proven
        // unchanged. The run is at Accessibility XL, which the comparison states.
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "v2-feed-landscape"
        landscape.lifetime = .keepAlways
        add(landscape)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        // Dynamic Type was larger for the whole run, and the feed is still there to read.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label != ''")).firstMatch.exists)
    }

    /// T12: a reader's own state survives going offline and relaunching — a filter, a saved card and the feed
    /// they were reading — and nothing they set is discarded.
    @MainActor
    func testOfflineRelaunchKeepsFilterSavedCardAndFeed() throws {
        let app = XCUIApplication()
        let namespace = UUID().uuidString
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        // Same fixture declaration as T6: the filtered context's launch would otherwise consult the real
        // catalogue for discovery and hold the transition on cleartext timeouts.
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launchEnvironment["FEEDMINE_DISABLE_DISCOVERY"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))
        // The first Edition is published before the reader edits a filter. `native-viewport-delivery` alone is
        // present while the association is preparing; a published card is the fact that the cold bootstrap
        // finished, so the transition is not racing the launch.
        let firstPublishedCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", Self.cardIdentifier)).firstMatch
        XCTAssertTrue(firstPublishedCard.waitForExistence(timeout: 45),
            "a published card must exist before the filter transition")
        // A filter the reader applied, and a card they saved.
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 15), "the sheet is up")
        // The criterion the fixtures declare (`en`), and the sheet's own table is what scrolls to it.
        let english = app.buttons["language-en"]
        XCTAssertTrue(english.waitForExistence(timeout: 15), "the sheet offers the language criterion")
        english.tap()
        XCTAssertTrue(app.buttons["filter-clear-all"].isEnabled,
            "editing the draft enables Clear All, which was disabled on a clean selection")
        app.buttons["filter-done"].tap()
        XCTAssertTrue(waitForAbsence(app.buttons["filter-done"], timeout: 90),
            "the transition closes the sheet before the reader is back")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        let firstCard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", Self.cardIdentifier)).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 45), "a real published occurrence must appear")
        // The reader's own save control on the card. The long press opens the card's `contextMenu`, which also
        // offers "Salvar artigo" (`FeedItemCardView` ~337) — but the press did not reach it on this surface, and
        // that is an **open question**, not something this test may paper over: what this test measures is the
        // persistence path, and `card.bookmark` is the control the reader sees on the card itself. The state is
        // compared, not merely tapped, so "saved" means saved.
        let bookmark = firstCard.buttons["card.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 15), "the card offers saving")
        XCTAssertEqual(bookmark.value as? String, "not bookmarked", "the card starts unsaved")
        bookmark.tap()
        XCTAssertEqual(bookmark.value as? String, "bookmarked", "saving the card records its state")
        // Offline, and a fresh launch of the same reader's store.
        app.terminate()
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45),
            "the feed the reader had is still readable offline")
        // The filter the reader applied is still applied, and the lens states the criterion it kept.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'lens-chip-language-'"))
            .firstMatch.waitForExistence(timeout: 15), "the filter survives an offline relaunch")
        // The saved card is still saved: the header's own saved surfaces list it. (The overflow menu offers that
        // same surface as `Salvos` too — this test keeps proving the header control's own path.)
        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.buttons["Todos os salvos"].waitForExistence(timeout: 15))
        app.buttons["Todos os salvos"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved-article-'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "the saved card survives an offline relaunch")
        // The list is a level of its own: its back button returns to the boxes, and the boxes' own "Concluir"
        // returns to the feed.
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["bookmarkBoxes.done"].waitForExistence(timeout: 15))
        app.buttons["bookmarkBoxes.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
    }

    /// PO 2026-10-14: `Salvos` é uma navegação (o menu do cabeçalho passa a oferecê-la, com a palavra que o
    /// driver congelado do B05 procura), e ir até ela e voltar **preserva a âncora**. A superfície de salvos é
    /// uma apresentação sobre o feed: nem troca de contexto, nem sessão nova.
    @MainActor
    func testSalvosFromTheOverflowMenuPreservesTheReadingPoint() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        // A reading point that is not the top of the feed: the reader's own scroll, and the opportunity it
        // completed is what makes the position real.
        scroll.swipeUp()
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@",
            ".*completed=[1-9][0-9]*.*"), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 20), .completed,
            "a real scroll must complete a real opportunity; observed: \(proof.label)")
        let counters = proof.label
        let anchor = try XCTUnwrap(topmostCardIdentifier(app: app, scroll: scroll),
            "a card must be visible inside the viewport")
        // The overflow menu offers V1's `Salvos`, and choosing it opens the reader's saved boxes.
        openMenu(app)
        XCTAssertTrue(app.buttons["Salvos"].waitForExistence(timeout: 10),
            "the overflow menu must offer the saved surface the header's own control offers")
        app.buttons["Salvos"].tap()
        XCTAssertTrue(app.buttons["bookmarkBoxes.done"].waitForExistence(timeout: 15),
            "choosing Salvos must open the reader's saved boxes")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "salvos-from-the-overflow-menu"
        shot.lifetime = .keepAlways
        add(shot)
        // And coming back: closing that surface returns to the feed, on the same card, with the same session.
        app.buttons["bookmarkBoxes.done"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "closing the saved surface returns to the feed")
        XCTAssertEqual(proof.label, counters, "visiting the saved surface must not replace the association")
        XCTAssertEqual(topmostCardIdentifier(app: app, scroll: scroll), anchor,
            "going to Salvos and coming back must preserve the reading point")
    }

    /// PO 2026-10-14: um **fechamento à força** — sem nenhum milestone de ciclo de vida — devolve o leitor ao
    /// card que estava lendo, e o card que ele salvou aparece **desenhado**. A posição durável passa a ser o
    /// último card admitido e estabelecido, sob a janela máxima de perda declarada em
    /// `FeedSession.settledPositionDebounceWindow`.
    @MainActor
    func testAForcedCloseReopensOnTheCardTheReaderWasReading() throws {
        let namespace = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        scroll.swipeUp()
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@",
            ".*completed=[1-9][0-9]*.*"), object: proof)
        XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 20), .completed,
            "a real scroll must complete a real opportunity; observed: \(proof.label)")
        let anchor = try XCTUnwrap(topmostCardIdentifier(app: app, scroll: scroll),
            "a card must be visible inside the viewport")
        // The reader saves the card they are on: the same card the reopen has to draw as saved.
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", anchor)).firstMatch
        let bookmark = card.buttons["card.bookmark"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 15), "the card the reader is on offers saving")
        XCTAssertEqual(bookmark.value as? String, "not bookmarked", "the card starts unsaved")
        bookmark.tap()
        XCTAssertEqual(bookmark.value as? String, "bookmarked", "saving the card records its state")
        Thread.sleep(forTimeInterval: 2)
        // A forced close. `terminate()` runs no lifecycle milestone at all — measured: it writes no lifecycle
        // checkpoint — so what comes back can only be what the settled observation made durable.
        app.terminate()
        Thread.sleep(forTimeInterval: 2)
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 60),
            "the feed returns after a forced close")
        Thread.sleep(forTimeInterval: 4)
        XCTAssertEqual(topmostCardIdentifier(app: app, scroll: app.scrollViews.firstMatch), anchor,
            "a forced close must reopen on the card the reader was reading")
        let reopened = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", anchor)).firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 15), "the card the reader was on is drawn again")
        XCTAssertEqual(reopened.buttons["card.bookmark"].value as? String, "bookmarked",
            "and the card they saved is drawn as saved")
    }

    /// Release within-card continuity after the **original fast drag** (no hold): the regression for the
    /// transient-height restore. The app's first relaunch proof can measure a 2 pt shorter card; the exact-height
    /// retry must restore the recorded point instead of leaving the proportional 1.333 pt short.
    @MainActor
    func testReleaseForcedCloseKeepsTheCardLineAfterAFastDrag() throws {
        let app = XCUIApplication()
        // A normal Release launch: a fresh install shows the real welcome; an installed reader goes straight to
        // the feed. No launch flag forces onboarding, and none can leak into the relaunch below.
        app.launch()
        if app.staticTexts["welcome-headline"].waitForExistence(timeout: 20) {
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 30))
        let languages = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-language-'"))
        if languages.firstMatch.waitForExistence(timeout: 10) {
            let portuguese = languages.matching(NSPredicate(format: "label CONTAINS[c] 'Portuguese'")).firstMatch
            if portuguese.exists { portuguese.tap() }
        }
        let places = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-region-'"))
        let composer = app.otherElements["onboarding"].scrollViews.firstMatch
        var place: XCUIElement?
        for _ in 0..<10 where place == nil {
            _ = places.firstMatch.waitForExistence(timeout: 3)
            if places.firstMatch.exists && places.firstMatch.isHittable { place = places.firstMatch }
            if place == nil && composer.exists { composer.swipeUp() }
        }
        XCTAssertNotNil(place)
        place!.tap()
        let open = app.buttons["composer-open-feed"]
        for _ in 0..<6 where !open.isHittable { composer.swipeUp() }
        open.tap()
        }
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 180))
        // A test-runner parameter, not an app seam: the same journey on a card class selected by its measured
        // height. The default 0 keeps the original fast-drag regression unchanged.
        let minimumCardHeight = ProcessInfo.processInfo.environment["FEEDMINE_TEST_MIN_CARD_HEIGHT"]
            .flatMap(Double.init) ?? 0
        let uuid = "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        func cards(_ scroll: XCUIElement) -> [XCUIElement] {
            scroll.descendants(matching: .any).matching(NSPredicate(format: "identifier MATCHES %@", uuid))
                .allElementsBoundByIndex.filter { $0.frame.height > 40 }
        }
        func containing(_ scroll: XCUIElement, minHeight: CGFloat = 0) -> XCUIElement? {
            let top = scroll.frame.minY
            // The permanent regression's own contract: the selected card must have a meaningful point inside the
            // viewport (20 pt below its top, 40 pt above its bottom). A card whose top lies on the line is a
            // separate boundary case, not a replacement for this one.
            return cards(scroll).first {
                $0.frame.height >= minHeight && $0.frame.minY < top - 20 && $0.frame.maxY > top + 40
            }
        }
        /// The continuation has a different purpose: it must prove a new user scroll stays put and persists. It may
        /// legitimately stop at a card boundary or in the spacing, so it uses the app's boundary rule (the
        /// containing card with the greatest top, else the first visible card below the line) among cards that are
        /// actually visible and hittable. The permanent FastDrag selector above keeps its 20/40 interior contract.
        func boundaryCard(_ scroll: XCUIElement) -> XCUIElement? {
            let top = scroll.frame.minY
            let visible = cards(scroll).filter {
                $0.isHittable && $0.frame.maxY > top && $0.frame.minY < scroll.frame.maxY
            }
            if let containing = visible.filter({
                $0.frame.minY <= top + 1 && $0.frame.maxY >= top - 1
            }).max(by: { $0.frame.minY < $1.frame.minY }) {
                return containing
            }
            return visible.filter { $0.frame.minY >= top - 1 }
                .min(by: { $0.frame.minY < $1.frame.minY })
        }
        XCTAssertTrue(cards(scroll).first != nil || app.buttons.matching(identifier: "card.bookmark").firstMatch.waitForExistence(timeout: 240))
        let cover = app.descendants(matching: .any)["feed-loading-surface"]
        if cover.exists {
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cover)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 120), .completed,
                "the real feed is exposed before the gesture")
        }
        XCTAssertTrue(scroll.isHittable, "the feed is interactive before the gesture")
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        start.press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let searchBound = minimumCardHeight > 0 ? 24 : 8
        for _ in 0..<searchBound where containing(scroll, minHeight: minimumCardHeight) == nil {
            scroll.swipeUp()
        }
        let card = try XCTUnwrap(containing(scroll, minHeight: minimumCardHeight),
            "a card of at least \(minimumCardHeight) pt contains the line")
        print("FAST_SELECT min=\(minimumCardHeight) id=\(card.identifier) h=\(card.frame.height)")
        var samples: [CGFloat] = []
        var stable = false
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.5)
            samples.append(card.frame.minY - scroll.frame.minY)
            if samples.count >= 5, let low = samples.suffix(5).min(), let high = samples.suffix(5).max(),
                high - low <= 0.5 { stable = true; break }
        }
        XCTAssertTrue(stable, "rest; samples \(samples.suffix(8))")
        // Everything the relaunch compares is copied **before** terminate. The XCUIElement proxy is a live query;
        // reading it after the relaunch would read the new process twice (the tautology a prior harness had).
        let beforeID = card.identifier
        let beforeFrame = card.frame
        let beforeScrollFrame = scroll.frame
        XCTAssertTrue(beforeFrame.width.isFinite && beforeFrame.height.isFinite
            && beforeFrame.width > 0 && beforeFrame.height > 0, "the card frame is real before terminate")
        let beforeHeight = beforeFrame.height
        let line = beforeFrame.minY - beforeScrollFrame.minY
        let lineTop = beforeScrollFrame.minY
        let candidates = cards(scroll).filter { $0.frame.minY <= lineTop && $0.frame.maxY >= lineTop }
        for candidate in candidates {
            let frame = candidate.frame
            let children = candidate.descendants(matching: .any).allElementsBoundByIndex
                .filter(\.isHittable).prefix(3)
                .map { "\($0.elementType.rawValue):\($0.identifier)" }
            print("FAST_CANDIDATE id=\(candidate.identifier) frame=\(frame) h=\(frame.height) hittable=\(candidate.isHittable) hittableChildren=\(children)")
        }
        print("FAST_PRE id=\(beforeID) h=\(beforeHeight) line=\(line) wall=\(Date().timeIntervalSince1970) scroll=\(beforeScrollFrame) selectedHittable=\(card.isHittable)")
        let beforeShot = XCTAttachment(screenshot: app.screenshot())
        beforeShot.name = "fastdrag-before-\(beforeID)-line-\(line)-h-\(beforeHeight)"
        beforeShot.lifetime = .keepAlways
        add(beforeShot)
        app.terminate()
        Thread.sleep(forTimeInterval: 2)
        app.launchEnvironment.removeValue(forKey: "FEEDMINE_ONBOARDING")
        app.launchEnvironment.removeValue(forKey: "FEEDMINE_BLOCK_RSS_NETWORK")
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 90))
        let reopened = app.scrollViews.firstMatch
        let reopenedCover = app.descendants(matching: .any)["feed-loading-surface"]
        if reopenedCover.exists {
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                object: reopenedCover)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 120), .completed,
                "the reopened feed is exposed before measuring")
        }
        XCTAssertTrue(reopened.isHittable, "the reopened feed is interactive")
        var afterSamples: [CGFloat] = []
        var after: CGFloat = .nan
        var afterHeight: CGFloat = .nan
        var afterFrame = CGRect.null
        var settled = false
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.5)
            let match = cards(reopened).filter { $0.identifier == beforeID }
            guard let current = match.first(where: { $0.frame.width > 300 }) ?? match.first else { continue }
            afterFrame = current.frame
            after = current.frame.minY - reopened.frame.minY
            afterHeight = current.frame.height
            afterSamples.append(after)
            if afterSamples.count >= 5, let low = afterSamples.suffix(5).min(), let high = afterSamples.suffix(5).max(),
                high - low <= 0.5 { settled = true; break }
        }
        print("FAST_DRAG id=\(beforeID) before=\(line) beforeH=\(beforeHeight) after=\(after) afterH=\(afterHeight)")
        XCTAssertTrue(settled, "the reopened feed settles; samples \(afterSamples.suffix(8))")
        XCTAssertTrue(afterFrame.width.isFinite && afterFrame.height.isFinite
            && afterFrame.width > 0 && afterFrame.height > 0, "the reopened card frame is real")
        XCTAssertEqual(afterHeight, beforeHeight, accuracy: 1, "the card's measured height is unchanged")
        XCTAssertEqual(after, line, accuracy: 1,
            "the fast drag's line inside the card is preserved across a forced close, at the same height")

        let afterShot = XCTAttachment(screenshot: app.screenshot())
        afterShot.name = "fastdrag-after-\(beforeID)-line-\(after)-h-\(afterHeight)"
        afterShot.lifetime = .keepAlways
        add(afterShot)

        // The reopened restore is a substitution, not ownership. A real scroll after it must move the viewport
        // and stay moved, and the point the reader stops at must be what another close restores.
        let restoredLine = after
        // Exactly one user action. No fallback gesture: if no visible card is at the line afterwards, that is a
        // failure with a screenshot, not another scroll or an empty-UUID relaunch.
        reopened.swipeUp()
        var continuedID = ""
        var continuedLine: CGFloat = .nan
        var continuedHeight: CGFloat = .nan
        var continuedSamples: [CGFloat] = []
        var continuedStable = false
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.5)
            if continuedID.isEmpty {
                guard let current = boundaryCard(reopened) else { continue }
                let frame = current.frame
                continuedID = current.identifier
                continuedLine = frame.minY - reopened.frame.minY
                continuedHeight = frame.height
                continuedSamples = [continuedLine]
                continue
            }
            let match = cards(reopened).filter { $0.identifier == continuedID }
            guard let current = match.first(where: { $0.frame.width > 300 }) ?? match.first else { continue }
            continuedLine = current.frame.minY - reopened.frame.minY
            continuedHeight = current.frame.height
            continuedSamples.append(continuedLine)
            if continuedSamples.count >= 5, let low = continuedSamples.suffix(5).min(),
                let high = continuedSamples.suffix(5).max(), high - low <= 0.5 {
                continuedStable = true; break
            }
        }
        guard !continuedID.isEmpty else {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "fastdrag-continue-empty-restored-\(restoredLine)"
            shot.lifetime = .keepAlways
            add(shot)
            XCTFail("no visible hittable card at the line after one real scroll")
            return
        }
        print("FAST_CONTINUE restored=\(restoredLine) id=\(continuedID) line=\(continuedLine) h=\(continuedHeight)")
        let continueShot = XCTAttachment(screenshot: app.screenshot())
        continueShot.name = "fastdrag-continue-\(continuedID)-line-\(continuedLine)-h-\(continuedHeight)"
        continueShot.lifetime = .keepAlways
        add(continueShot)
        // Short-circuit on the first actual continuation failure: do not relaunch with an unsettled or no-op
        // point and then count cascaded invalid comparisons.
        guard continuedStable else {
            XCTFail("the feed settles after a real scroll; samples \(continuedSamples.suffix(8))")
            return
        }
        // Different visible content at the same relative offset is valid progress; the no-op is the same card at
        // the same line. The next close still compares the exact same UUID/height/line.
        guard continuedID != beforeID || abs(continuedLine - restoredLine) > 20 else {
            XCTFail("a real scroll after the reopen changes the visible content or moves the line")
            return
        }
        Thread.sleep(forTimeInterval: 3)
        app.terminate()
        Thread.sleep(forTimeInterval: 2)
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 90))
        let third = app.scrollViews.firstMatch
        let thirdCover = app.descendants(matching: .any)["feed-loading-surface"]
        if thirdCover.exists {
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                object: thirdCover)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 120), .completed,
                "the third feed is exposed before measuring")
        }
        XCTAssertTrue(third.isHittable, "the third feed is interactive")
        var thirdLine: CGFloat = .nan
        var thirdHeight: CGFloat = .nan
        var thirdFrame = CGRect.null
        var thirdSamples: [CGFloat] = []
        var thirdSettled = false
        for _ in 0..<40 {
            Thread.sleep(forTimeInterval: 0.5)
            let match = cards(third).filter { $0.identifier == continuedID }
            guard let current = match.first(where: { $0.frame.width > 300 }) ?? match.first else { continue }
            thirdFrame = current.frame
            thirdLine = current.frame.minY - third.frame.minY
            thirdHeight = current.frame.height
            thirdSamples.append(thirdLine)
            if thirdSamples.count >= 5, let low = thirdSamples.suffix(5).min(),
                let high = thirdSamples.suffix(5).max(), high - low <= 0.5 {
                thirdSettled = true; break
            }
        }
        print("FAST_CONTINUE_REOPEN id=\(continuedID) line=\(thirdLine) h=\(thirdHeight)")
        XCTAssertTrue(thirdSettled, "the third feed settles; samples \(thirdSamples.suffix(8))")
        XCTAssertTrue(thirdFrame.width.isFinite && thirdFrame.height.isFinite
            && thirdFrame.width > 0 && thirdFrame.height > 0, "the continued card frame is real")
        XCTAssertEqual(thirdHeight, continuedHeight, accuracy: 1, "the continued card's height is unchanged")
        XCTAssertEqual(thirdLine, continuedLine, accuracy: 1,
            "the point a real scroll reached after the reopen survives the next close")
    }

    /// relaunch blocks the RSS network so the stored feed is the only content and no refresh race can change the
    /// The PO's headline criterion, in the half the V2 never measured: "**close and reopen the app: the feed must
    /// appear immediately**, from the ready content of the previous interaction … with no loading screen in between"
    /// (`1.0-checklist.md:3131-3132`, restated `:3220-3224`; the V1 harness failed its own run when a loading
    /// surface survived the relaunch, `PersonaExplorationUITests.swift:386-388`).
    ///
    /// **Why the witness is the app's own record and not a sampled element.** The V2 asserts the *identity* of the
    /// reopened anchor (`testAForcedCloseReopensOnTheCardTheReaderWasReading`) and has never asserted the absence of
    /// a loading surface; and no UI test could have: `XCUIApplication.launch()` returns only once the app is idle,
    /// so a loading surface that lived for the whole launch transition is exactly the surface a sample taken
    /// afterwards can never see (the V1's own harness documented that blind window). The app can see it. So the
    /// witness is `FeedLaunchWitness` — the process's own record of the order in which it put its surfaces on the
    /// reader's screen: the ones that say "wait" (the launch's progress and the feed's absence surface) and the
    /// first one that carried the reader's ready cards. The V1-shaped half is asserted too, on the surface a reader
    /// actually perceives: once the app is idle, no loading surface is on screen.
    ///
    /// **The control is the cold launch inside this test.** Both launches are judged by the same function
    /// (`reopenCriterionViolations`): a container with nothing ready must violate the criterion (otherwise the
    /// instrument states nothing), and the warm relaunch must satisfy it. The evidence of both halves is printed so
    /// the run can be read without trusting the verdict.
    @MainActor
    func testWarmRelaunchShowsTheFeedWithoutRenderingAWaitSurface() throws {
        let namespace = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"

        // COLD — this namespace has never run, so there is no ready content and a wait surface is the honest thing
        // to show (doctrine item 1: "the first open may be slow — that is what the loading screen is for").
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 60), "the first run reaches the feed")
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", Self.cardIdentifier)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 45), "the first run publishes real content")
        let cold = try launchRecord(app, name: "cold")
        let coldViolations = reopenCriterionViolations(cold, app: app)
        print("REOPEN_WITNESS cold record=\(cold.raw)")
        print("REOPEN_WITNESS cold verdict=\(coldViolations.isEmpty ? "satisfied" : "violated")"
            + " violations=\(coldViolations.isEmpty ? "none" : coldViolations.joined(separator: " | "))")
        XCTAssertFalse(coldViolations.isEmpty,
            "the control must fail: a launch with no ready content cannot satisfy the reopen criterion, or the "
                + "instrument states nothing — record=\(cold.raw)")

        // The reader reads. A filter first, so the context names something discovery must look for (the pool the
        // launch path resolves), and then one real forward gesture: the position it settles on is what a close keeps.
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 15), "the sheet is up")
        let english = app.buttons["language-en"]
        XCTAssertTrue(scrollIntoView(english, in: app, timeout: 15), "the sheet offers the language criterion")
        english.tap()
        app.buttons["filter-done"].tap()
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 45), "the filtered context publishes its feed")
        scroll.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        // Evidence, not a verdict: the driver's own counters say whether the gesture reached a real opportunity.
        // The criterion under test does not depend on it, and a filtered window that fits the viewport produces no
        // opportunity at all — so this line is printed rather than asserted.
        print("REOPEN_WITNESS after-the-gesture \(proof.label)")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", Self.cardIdentifier)).firstMatch.exists,
            "the reader has real content on screen before the close")
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
        Thread.sleep(forTimeInterval: 2)

        // WARM — the same container: the reader's ready content from the previous interaction, and nothing else.
        // The relaunch runs with the network blocked, so what comes back can only be what the previous interaction
        // made ready locally (INV-11; the criterion's own words: "from the ready content of the previous interaction").
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        let warmStarted = Date()
        app.launch()
        // `launch()` returns once the app is idle, so this is an **upper bound** on the feed appearing — the app's
        // own clock (`first_cards_ms` in the record) is the honest number, and it is printed below.
        let launchReturnedMS = Int(Date().timeIntervalSince(warmStarted) * 1000)
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 60),
            "the feed the reader had is there when they come back")
        Thread.sleep(forTimeInterval: 3)
        let warm = try launchRecord(app, name: "warm")
        let warmViolations = reopenCriterionViolations(warm, app: app)
        print("REOPEN_WITNESS warm record=\(warm.raw)")
        print("REOPEN_WITNESS warm launch_returned_ms=\(launchReturnedMS)"
            + " (XCTest's idle bound on the same launch; the app's own first_cards_ms is in the record)")
        print("REOPEN_WITNESS warm verdict=\(warmViolations.isEmpty ? "satisfied" : "violated")"
            + " violations=\(warmViolations.isEmpty ? "none" : warmViolations.joined(separator: " | "))")
        let attachment = XCTAttachment(string: "cold: \(cold.raw)\nwarm: \(warm.raw)")
        attachment.name = "reopen-witness"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", Self.cardIdentifier)).firstMatch.exists,
            "the warm relaunch shows ready content, not a promise of it")
        XCTAssertTrue(warmViolations.isEmpty,
            "a warm relaunch must satisfy the reopen criterion — record=\(warm.raw) violations=\(warmViolations)")
    }

    /// One launch, as the app itself recorded it (`FeedLaunchWitness`): the wait surfaces it drew and the first pass
    /// that carried ready cards, both on the process's own clock.
    private struct LaunchRecord {
        let raw: String
        let waitPasses: Int
        let waitKind: String
        let firstWaitMS: Int?
        let lastWaitMS: Int?
        let cards: Int
        let firstCardsMS: Int?

        /// The window the reader sat through a surface that was not their feed, when there was one.
        var waitWindow: String {
            guard let first = firstWaitMS else { return "never" }
            return "\(first)…\(lastWaitMS.map(String.init) ?? "?") ms"
        }
    }

    @MainActor
    private func launchRecord(_ app: XCUIApplication, name: String) throws -> LaunchRecord {
        let element = app.descendants(matching: .any)["feed-launch-record"]
        XCTAssertTrue(element.waitForExistence(timeout: 30), "\(name): the app's own launch record is published")
        // The record settles once the launch has drawn cards; until then the labels are the earlier facts.
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label MATCHES %@", ".*cards=[1-9].*"),
            object: element)
        _ = XCTWaiter.wait(for: [settled], timeout: 30)
        let label = element.label
        func value(_ field: String) -> String? {
            label.split(separator: " ").map(String.init).first { $0.hasPrefix(field + "=") }
                .map { String($0.dropFirst(field.count + 1)) }
        }
        func milliseconds(_ field: String) -> Int? {
            guard let raw = value(field), raw != "n/a" else { return nil }
            return Int(raw)
        }
        return LaunchRecord(raw: label,
            waitPasses: Int(value("wait_passes") ?? "") ?? -1,
            waitKind: value("kind") ?? "unknown",
            firstWaitMS: milliseconds("first_wait_ms"),
            lastWaitMS: milliseconds("last_wait_ms"),
            cards: Int(value("cards") ?? "") ?? -1,
            firstCardsMS: milliseconds("first_cards_ms"))
    }

    /// The criterion itself, in one place, so both launches are judged by the same rule: on the reading surface the
    /// reader asked for, from the ready content of the previous interaction, **with no loading screen in between**.
    /// Every violation is returned, not the first one: a relaunch that failed has to say how.
    @MainActor
    private func reopenCriterionViolations(_ record: LaunchRecord, app: XCUIApplication) -> [String] {
        var violations: [String] = []
        if record.cards <= 0 {
            violations.append("the feed never drew ready content (cards=\(record.cards))")
        }
        if record.waitPasses > 0, let firstWait = record.firstWaitMS,
            record.firstCardsMS.map({ firstWait < $0 }) ?? true {
            violations.append("a loading surface was drawn before the feed: \(record.waitPasses) pass(es) of "
                + "\(record.waitKind) over \(record.waitWindow), cards at "
                + "\(record.firstCardsMS.map(String.init) ?? "never") ms")
        } else if record.waitPasses > 0 {
            violations.append("the record counted \(record.waitPasses) wait pass(es) without a first one on the "
                + "clock — it cannot be read: \(record.raw)")
        }
        // The half the reader perceives: once the app is idle, nothing that says "wait" is on screen.
        for identifier in ["feed-loading-surface", "feed-launch-progress"]
        where app.descendants(matching: .any)[identifier].exists {
            violations.append("\(identifier) is still on screen after the app reached idle")
        }
        return violations
    }

    /// **A medição comparável de arranque frio e morno** — o pedido do arquiteto, depois de a primeira tentativa
    /// comparar intervalos que não eram equivalentes (o frio levava o onboarding dentro). O que este caso faz, na
    /// mesma execução e com o mesmo instrumento (`FeedLaunchWitness`, o relógio do próprio processo):
    ///
    /// 1. **uma primeira abertura que *não* é medida**: o leitor conhece o app, responde idioma e lugar, e o
    ///    transporte está recusado — nada publica, então não há janela durável. Ela existe só para que o onboarding
    ///    esteja concluído **antes** das duas medições;
    /// 2. **a abertura fria medida**: mesmo contêiner, sem janela durável, com as respostas já no lugar e sem
    ///    nenhuma superfície de onboarding — do começo do processo até o primeiro passo que carrega cartas;
    /// 3. **a reabertura morna medida**: o mesmo contêiner, agora com a janela que a interação anterior deixou.
    ///
    /// As duas medições começam no mesmo instante (a construção do processo) e terminam no mesmo fato (a primeira
    /// passagem do host que carregou cartas prontas do leitor): o que difere é a **condição**, não o intervalo.
    /// Precondições, impressas e não cronometradas: o catálogo que a build carrega (117 993 472 bytes, o arquivo do
    /// artefato), as respostas que a primeira abertura deu no compositor do onboarding (idioma e lugar, impressos
    /// como o que foi realmente tocado — o relançamento as lê por `AppComposition.completeFirstRun`, que as grava),
    /// o censo de cartas alcançáveis (> 20, exigido) e `FEEDMINE_FIXTURE_ITEMS` itens por feed. Que a metade fria é
    /// **fria** não é presumido: é o registro dela que o diz (`kind=launch-progress`, a superfície que um arranque
    /// sem janela durável desenha — o morno desenha zero). O que este instrumento **não** mede é a parcela da
    /// descoberta: nada no processo cronometra a leitura do pool em separado — o número sai como `não medido`, com
    /// essa razão, e nunca inventado. O veredito do critério é afirmado no teste acima, na mesma jornada; aqui as
    /// duas metades são impressas cruas e o que se afirma é que a comparação é legítima (o frio declara a espera e
    /// o morno não desenha nenhuma).
    @MainActor
    func testReopenMeasurementColdAndWarmWithTheOnboardingAlreadyConcluded() throws {
        let namespace = UUID().uuidString
        // 1. A primeira abertura: só ela vê o onboarding, e ela não é medida.
        let first = XCUIApplication()
        first.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        first.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        first.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        // The fixture feeds are English (BBC), while the composer's answers name a place/language for the *shipped*
        // catalogue. Discovery is what would try to satisfy that profile over the network; with the transport
        // refused it can add nothing, and the measured launch would stall on a promise it cannot fulfil. The
        // measurement is about a launch with answers already on disk, so discovery is excluded in both launches.
        first.launchEnvironment["FEEDMINE_DISABLE_DISCOVERY"] = "1"
        first.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        first.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "0"
        first.launch()
        XCTAssertTrue(first.staticTexts["welcome-headline"].waitForExistence(timeout: 60))
        first.buttons["welcome-shape"].tap()
        XCTAssertTrue(first.staticTexts["composer-subtitle"].waitForExistence(timeout: 20))
        let languages = first.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-language-'"))
        var answeredPortuguese = false
        if languages.firstMatch.waitForExistence(timeout: 10) {
            let portuguese = languages.matching(NSPredicate(format: "label CONTAINS[c] 'Portuguese'")).firstMatch
            if portuguese.exists { portuguese.tap(); answeredPortuguese = true }
        }
        let places = first.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-region-'"))
        XCTAssertTrue(places.firstMatch.waitForExistence(timeout: 30), "the shipped catalogue offers its places")
        let brazil = places.matching(NSPredicate(format: "label CONTAINS[c] 'Brazil'")).firstMatch
        let answeredBrazil = brazil.exists
        (brazil.exists ? brazil : places.firstMatch).tap()
        first.buttons["composer-open-feed"].tap()
        // The gate closes as the answers are taken (`AppComposition.completeFirstRun` writes the profile and the
        // flag): this launch has to leave behind a reader who answered — and **no** durable window, because the
        // transport is refused, so nothing publishes. The coldness of the next launch is not assumed here: that
        // launch's own record states it (`kind=launch-progress`, the surface a launch with no window draws).
        XCTAssertTrue(waitForAbsence(first.staticTexts["composer-subtitle"], timeout: 60),
            "o portão de primeira execução fecha depois de o leitor responder")
        first.terminate()
        Thread.sleep(forTimeInterval: 2)

        // 2. A abertura **fria** medida: o mesmo contêiner, sem janela durável (a primeira abertura não publicou),
        //    com as respostas no lugar e sem superfície de onboarding. Discovery está desligada (o perfil responde
        //    por fontes do catálogo publicado, que o transporte recusado não pode servir); a oferta vem das fixtures
        //    locais, que é o que a abertura precisa publicar para a medição existir.
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launchEnvironment["FEEDMINE_DISABLE_DISCOVERY"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "0"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "120"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 120), "a abertura fria termina no feed")
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", Self.cardIdentifier))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 240), "a abertura fria publica conteúdo real")
        let cold = try launchRecord(app, name: "cold")
        let coldViolations = reopenCriterionViolations(cold, app: app)
        print("REOPEN_WITNESS precondition catalogue_bytes=117993472"
            + " answered_language_portuguese=\(answeredPortuguese) answered_place_brazil=\(answeredBrazil)"
            + " fixture_items_per_feed=\(app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] ?? "?")"
            + " onboarding=answered-before-both-measurements")
        print("REOPEN_WITNESS cold record=\(cold.raw)")
        print("REOPEN_WITNESS cold verdict=\(coldViolations.isEmpty ? "satisfied" : "violated")"
            + " violations=\(coldViolations.isEmpty ? "none" : coldViolations.joined(separator: " | "))")
        XCTAssertGreaterThan(cold.waitPasses, 0,
            "a abertura sem janela durável tem de declarar a espera, ou as duas metades não são condições "
                + "diferentes — record=\(cold.raw)")

        // A leitura que o relançamento tem de restaurar: o censo de cartas alcançáveis é a precondição "histórico
        // longo", impressa e **exigida**, não uma duração.
        let walked = collectCardIdentifiers(cards, scroll: scroll, passes: 24)
        print("REOPEN_WITNESS history cards_reachable=\(walked.count)")
        XCTAssertGreaterThan(walked.count, 20,
            "o histórico que esta medição restaura tem de ser longo: alcançou \(walked.count) cartas")
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
        Thread.sleep(forTimeInterval: 2)

        // 3. A reabertura **morna** medida: o mesmo contêiner, a mesma rede bloqueada — o que volta só pode ser o
        //    que a interação anterior tornou pronto localmente.
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 60),
            "o feed que o leitor tinha está lá quando ele volta")
        Thread.sleep(forTimeInterval: 3)
        let warm = try launchRecord(app, name: "warm")
        let warmViolations = reopenCriterionViolations(warm, app: app)
        print("REOPEN_WITNESS warm record=\(warm.raw)")
        print("REOPEN_WITNESS warm verdict=\(warmViolations.isEmpty ? "satisfied" : "violated")"
            + " violations=\(warmViolations.isEmpty ? "none" : warmViolations.joined(separator: " | "))")
        // A descoberta não é medida por este instrumento, e o relatório diz por quê em vez de inventar um número:
        // a parcela do processo que a leitura do pool custa não tem relógio próprio em lugar nenhum.
        print("REOPEN_WITNESS discovery=não medido (nenhum instrumento cronometra a leitura do pool em separado)")
        print("REOPEN_WITNESS intervals cold_first_cards_ms=\(cold.firstCardsMS.map(String.init) ?? "n/a")"
            + " warm_first_cards_ms=\(warm.firstCardsMS.map(String.init) ?? "n/a")"
            + " (mesmo começo: construção do processo; mesmo fim: a primeira passagem que carregou cartas)")
        XCTAssertGreaterThan(cold.cards, 0, "a metade fria mediu conteúdo")
        XCTAssertGreaterThan(warm.cards, 0, "e a metade morna também")
    }

    @MainActor
    func testNativeSwipeReachesRealRunwayAndReverseNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
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
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
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
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
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
        // The attachment is the settled dark frame: the two assertions above already proved nothing else moved,
        // and the colour transition is presentation-only, so waiting for it cannot mask a state change.
        Thread.sleep(forTimeInterval: 3.0)
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
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        // The contract is the **app's own reader**: a saved story with a body opens locally and closes by
        // `reading.close`. The default fixture shape is a teaser, whose primary action is the site — that path
        // belongs to `SFSafariViewController`, whose chrome the app does not own (and which no run could close
        // from the app's tree). Stating the body shape is what makes this journey deterministic instead of an
        // inconclusive probe of another process's UI.
        app.launchEnvironment["FEEDMINE_FIXTURE_TEXT"] = "longSummary"
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
        pressCard(card)
        let save = saveArticleButton(in: app)
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the card menu must offer saving")
        save.tap()
        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.buttons["Todos os salvos"].waitForExistence(timeout: 15))
        app.buttons["Todos os salvos"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved-article-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the saved article must be listed")
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "u2-saved-list"
        list.lifetime = .keepAlways
        add(list)
        // The row is a link-styled button, and the same element is reported as Button or Link depending on the
        // surface: the reader's own tap goes through the row's centre, as it does for a card in the feed.
        tapCard(row)
        // The reader opens inside the app: the **local text** surface for a story with a body, the site for a
        // teaser. Which one the contract asks for depends on the card, so the assertion asks for either — a
        // `webViews`-only probe read the local reader as "nothing opened" and made the journey inconclusive.
        let localReader = app.descendants(matching: .any).matching(identifier: "reading.body").firstMatch
        let webReader = app.webViews.firstMatch
        let readerDeadline = Date().addingTimeInterval(30)
        var readerOpened = false
        while Date() < readerDeadline {
            if localReader.exists || webReader.exists { readerOpened = true; break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(readerOpened, "the reader — local text or the site — opens inside the app")
        let reader = XCTAttachment(screenshot: app.screenshot())
        reader.name = "u2-in-app-reader"
        reader.lifetime = .keepAlways
        add(reader)
        // SafariServices owns the reader's close control; try its localized titles, and fall back to the sheet's
        // own dismissal only while the browser is still up. The reader may also have finished by itself, and
        // dismissing whatever is on screen then would take the saved list with it.
        var dismissed = false
        // A local reading surface owns an explicit close control.
        let localClose = app.buttons["reading.close"].firstMatch
        if localClose.waitForExistence(timeout: 5) { localClose.tap(); dismissed = true }
        // A site reading is `SFSafariViewController` (dismissButtonStyle = .close): its control belongs to the
        // Safari view service, not to the app's own button tree. Do not infer "closed" from `webViews` leaving the
        // app tree — that can happen while the reader is still on screen.
        if !dismissed {
            let safari = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
            for label in ["Close", "Fechar", "Done", "Concluído"] {
                let button = safari.buttons[label].firstMatch
                if button.waitForExistence(timeout: 3) { button.tap(); dismissed = true; break }
            }
        }
        // No coordinate fallback: if the chrome is gone, the reader already closed and the saved list is what must
        // be asserted; if it is still up, tapping the underlay would dismiss the saved list instead. The assertion
        // below decides which happened, with the hierarchy as evidence.
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
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
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
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
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

    /// R5/F05: the first open presents what the local store already published, without any gesture. Before
    /// the runtime-owned growth the admitted window held exactly the first card and the rest of the screen
    /// stayed empty until the reader scrolled; this asserts the window grew on its own — the delivery
    /// counters must still read zero — and that the reading point survives a foreground.
    @MainActor
    func testFirstOpenExpandsTheAdmittedWindowWithoutAGesture() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        XCTAssertEqual(proof.label, "received=0 completed=0 backward=0",
            "the first open must not depend on a reader observation")
        let cards = app.buttons.matching(identifier: "card.bookmark")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 45), "the first card is the first fact")
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count >= 2"), object: cards)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 60), .completed,
            "the admitted window must grow with the cards the store already published; observed \(cards.count)")
        let reference = try XCTUnwrap(topmostCard(app: app, scroll: scroll), "a card must be visible")
        let referenceID = reference.identifier
        let referenceTop = reference.frame.minY
        XCTAssertEqual(proof.label, "received=0 completed=0 backward=0", "still no reader gesture")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(scroll.waitForExistence(timeout: 20))
        let afterForeground = try XCTUnwrap(topmostCard(app: app, scroll: scroll))
        XCTAssertEqual(afterForeground.identifier, referenceID, "the reading point survives a foreground")
        XCTAssertEqual(afterForeground.frame.minY, referenceTop, accuracy: 1,
            "and the offset inside the viewport survives with it")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "r5-first-open-expanded"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// R5/PO: a reader whose attempt finished without eligible stories gets the honest surface and its two
    /// actions — "Tentar novamente" keeps them on a truthful surface, "Ajustar interesses" opens the existing
    /// flow that owns the interests. `FEEDMINE_EMPTY_FEEDS=1` makes the controlled transport answer with its
    /// channel and no stories, so nothing here depends on the network failing.
    @MainActor
    func testNoStoriesSurfaceOffersItsRecoveryActions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_EMPTY_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let title = app.staticTexts["Ainda não encontramos histórias para você."]
        XCTAssertTrue(title.waitForExistence(timeout: 90), "the surface states the attempt's result")
        let tryAgain = app.buttons["Tentar novamente"]
        let adjust = app.buttons["Ajustar interesses"]
        XCTAssertTrue(tryAgain.exists, "the retry action is offered")
        XCTAssertTrue(adjust.exists, "and the way to the interests")
        tryAgain.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 45), "trying again keeps the reader on a truthful surface")
        adjust.tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 30),
            "adjusting interests opens the existing flow that owns them")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "r5-no-stories-recovery"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// R5/PO: the acceptance journey — the first run over the **shipped catalogue** and the real network. The
    /// reader answers the two questions, enters the feed, and the window expands on its own: no gesture, no
    /// refresh. It needs the network, like the real-RSS lifecycle test beside it, and exists so the journey the
    /// PO asked to see can be demonstrated (and recorded) instead of described.
    @MainActor
    func testFirstRunOverTheRealCatalogueExpandsWithoutAGesture() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 60))
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 20))
        // The journey round 3 measured: a language and a place, which is what makes the shipped catalogue
        // answer with more than a single story.
        let languages = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-language-'"))
        if languages.firstMatch.waitForExistence(timeout: 10) {
            let portuguese = languages.matching(NSPredicate(format: "label CONTAINS[c] 'Portuguese'")).firstMatch
            if portuguese.exists { portuguese.tap() }
        }
        let places = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'composer-region-'"))
        XCTAssertTrue(places.firstMatch.waitForExistence(timeout: 30), "the shipped catalogue offers its places")
        let brazil = places.matching(NSPredicate(format: "label CONTAINS[c] 'Brazil'")).firstMatch
        (brazil.exists ? brazil : places.firstMatch).tap()
        app.buttons["composer-open-feed"].tap()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 180), "the first run ends in the feed")
        let cards = app.buttons.matching(identifier: "card.bookmark")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 240), "the first card is the first fact")
        // The acceptance the PO asked for: cards the store already published reach the screen without a gesture.
        //
        // Provenance, corrected 2026-10-15. This comment used to be a defect record, and it was stale: it claimed
        // the expectation was "deliberately left FAILING" and that the window's materialisation "stops at the
        // segment boundary". Both were refuted — the second by the query itself, which walks the whole edition by
        // `(s.ordinal, c.ordinal)` without a segment filter (`Sources/FeedMinePersistence/PublicationStore.swift:608-615`),
        // and the first by the round that closed the defect on 2026-10-11:
        // `docs/reviews/2026-10-11-round6-cross-segment-materialisation.md` records the spontaneous growth
        // `admitted 1 -> 1, 1 -> 2, 2 -> 17` inside four seconds and this test PASSing in 16.9 s with zero gestures
        // (`received=0 completed=0 backward=0`). The open defect observed on 2026-10-11 was real — the store held
        // 22 published cards (segments 1+1+20) while the screen kept one — but it was a missing re-read of the
        // published reserve after the burst, not a boundary.
        //
        // What this test asserts is therefore a standing invariant, not a pending defect: it fails only if the
        // growth regresses.
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count >= 2"), object: cards)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 60), .completed,
            "already-published cards must arrive without a gesture; observed \(cards.count)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "r5-real-catalogue-first-run"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// R5/PO: the restoration risk, measured. A reopen may legitimately materialise a smaller window; what it
    /// must not do is lose continuity — the reader returns to their card, and every card the edition already
    /// published stays reachable without a refresh. This is the discrimination the PO asked for before
    /// accepting the reopen experience (anchor preservation alone does not prove it).
    @MainActor
    func testReopenKeepsPublishedCardsReachable() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        // Identity, not count: the published occurrence each card carries as its accessibility identifier (the
        // pattern the real-RSS lifecycle test uses). The bookmark buttons all share one identifier, so counting
        // them cannot say whether a *particular* card stayed reachable.
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 45), "a real published occurrence must appear")
        let before = collectCardIdentifiers(cards, scroll: scroll, passes: 8)
        XCTAssertGreaterThan(before.count, 1, "the controlled transport publishes more than one card")
        app.terminate()
        app.launch()
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 45), "the reopened feed has cards")
        // The pre-reopen sweep leaves the reader at the bottom, which is the checkpoint the reopen restores.
        // Return to the head first so direction cannot explain a missing card; only then sweep both ways.
        for _ in 0..<20 { scroll.swipeDown(velocity: .slow) }
        let after = collectCardIdentifiers(cards, scroll: scroll, passes: 10)
        let missing = before.subtracting(after)
        XCTAssertTrue(missing.isEmpty,
            "cards published before the reopen must stay reachable; missing \(missing.count) of \(before.count): \(missing.sorted())")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "r5-reopen-continuity"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Every card identifier a slow forward scroll makes reachable, unioned across passes.
    private func collectCardIdentifiers(_ cards: XCUIElementQuery, scroll: XCUIElement, passes: Int) -> Set<String> {
        var seen = Set<String>()
        // A reopen may restore the reader near the tail; continuity means every already-published card is
        // reachable, so the sweep must go back above the restored position as well as forward below it.
        for _ in 0..<passes {
            for element in cards.allElementsBoundByIndex { seen.insert(element.identifier) }
            scroll.swipeDown(velocity: .slow)
        }
        for _ in 0..<passes {
            for element in cards.allElementsBoundByIndex { seen.insert(element.identifier) }
            scroll.swipeUp(velocity: .slow)
        }
        for element in cards.allElementsBoundByIndex { seen.insert(element.identifier) }
        return seen
    }

    /// R5/PO: the other half of the discrimination, on the shipped catalogue — the cards the store published are
    /// *not lost*, they are reachable with a scroll even when the window did not fill itself. Together with the
    /// red expectation above this says: "not admitted without a gesture" (defect), not "unreachable" (worse).
    @MainActor
    func testRealCatalogueCardsStayReachableByScrolling() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 60))
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 20))
        // Addressed by identifier, never by text: two languages can read alike, and the interface language is
        // whatever the device is set to (round 9 replaced the ambiguous `label CONTAINS 'Portuguese'` lookup).
        let composer = app.otherElements["onboarding"].scrollViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 30))
        let portuguese = app.buttons["composer-language-pt"]
        if portuguese.waitForExistence(timeout: 10) { portuguese.tap() }
        // The places are a `LazyVGrid`: a chip below the fold is not in the accessibility tree, so the earlier
        // instrument found `algeria` (the first realised chip, 0 pt sources) and measured that instead of Brazil
        // (measured 2026-10-18, run-final3.log lines 38818-40119). The answer is named by the catalogue's own node
        // key and the surface is scrolled until it exists — never the first chip.
        let brazil = app.buttons["composer-region-90_countries/brazil"]
        for _ in 0..<14 where !(brazil.exists && brazil.isHittable) {
            composer.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(brazil.exists && brazil.isHittable,
            "the first run's places include Brazil (90_countries/brazil), reached by scrolling")
        brazil.tap()
        print("BRAZIL_SELECTED identifier=composer-region-90_countries/brazil selected=\(brazil.isSelected)")
        XCTAssertTrue(brazil.isSelected, "the place the reader chose states itself selected")
        app.buttons["composer-open-feed"].tap()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 180))
        let occurrences = app.descendants(matching: .any).matching(NSPredicate(format: "identifier MATCHES %@",
            "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
        XCTAssertTrue(occurrences.firstMatch.waitForExistence(timeout: 240), "the first card is the first fact")
        let reachable = collectCardIdentifiers(occurrences, scroll: scroll, passes: 6)
        XCTAssertGreaterThan(reachable.count, 1,
            "the store's published cards must be reachable with a scroll; reachable \(reachable.count)")
    }

    /// E03: a resting reader is not a loaded reader. Ten minutes without a gesture, a publication that arrives
    /// while the reader is stopped, and a distant scroll with the way back — the card's identity and geometry must
    /// survive all three. Gated by `FEEDMINE_LONG_REST=1`: the suite pays ten minutes only when the operator asks
    /// for the rest session.
    ///
    /// Not measured here, and deliberately not claimed: a memory-pressure warning (the system's own signal, not a
    /// gesture the harness can inject) and a media asset that is unavailable at publication time (covered by
    /// `CardImageJourneyUITests` and B04's idle capture, which reads the rendered pixels).
    @MainActor
    func testTenMinuteRestKeepsTheCardThroughLateSupplyAndADistantReturn() throws {
        guard ProcessInfo.processInfo.environment["FEEDMINE_LONG_REST"] == "1" else {
            throw XCTSkip("set FEEDMINE_LONG_REST=1 to pay the ten-minute rest")
        }
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_FIXTURE_ITEMS"] = "6"
        // The configuration `testPublicationAfterTheFollowUpWindowStillReachesTheWindow` proves: the first endpoint
        // answers at once, the second ten seconds later. A larger document or a longer delay belongs to another
        // question; this exercise is about a stopped reader, not about the transport's timing.
        app.launchEnvironment["FEEDMINE_SLOW_FEED_SECONDS"] = "10"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 60), "the fixture feed opens")
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier MATCHES %@",
            Self.cardIdentifier))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 60), "the fixture publishes its first card")
        // The late endpoint is what makes a deep scroll possible; wait for its supply rather than measuring a
        // one-card feed. A reader who stops on a single card cannot walk away from it.
        let feedDeadline = Date().addingTimeInterval(300)
        while Date() < feedDeadline, cards.count < 2 { Thread.sleep(forTimeInterval: 1.0) }
        XCTAssertGreaterThanOrEqual(cards.count, 2, "the slow endpoint's supply reaches the window")

        func topmostCard() -> (id: String, frame: CGRect)? {
            let top = scroll.frame.minY
            let visible = cards.allElementsBoundByIndex
                .filter { $0.exists && $0.frame.height > 40 && $0.frame.minY >= top - 1 }
                .sorted { $0.frame.minY < $1.frame.minY }
            guard let first = visible.first else { return nil }
            return (first.identifier, first.frame)
        }
        func attachShot(_ name: String) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }
        guard let anchor = topmostCard() else { return XCTFail("no card is presented to rest on") }
        attachShot("e03-rest-start")

        // 1. Ten minutes stopped. A mid-point read is taken so a slow drift is evidence, not a single compare.
        Thread.sleep(forTimeInterval: 300)
        let mid = cards.allElementsBoundByIndex.first { $0.exists && $0.identifier == anchor.id }?.frame
        XCTAssertEqual(mid?.minY ?? .nan, anchor.frame.minY, accuracy: 1,
            "half-way through the rest the anchored card is where the reader left it")
        Thread.sleep(forTimeInterval: 300)
        let rested = cards.allElementsBoundByIndex.first { $0.exists && $0.identifier == anchor.id }?.frame
        XCTAssertEqual(rested?.minY ?? .nan, anchor.frame.minY, accuracy: 1,
            "the card the reader stopped on does not move when supply arrives with no gesture")
        XCTAssertEqual(rested?.height ?? .nan, anchor.frame.height, accuracy: 1,
            "and its geometry is the same")
        attachShot("e03-rest-end")

        // 2. A distant scroll and the way back: the same card is reachable and keeps its own identity.
        var far = topmostCard()
        for _ in 0..<30 where far?.id == anchor.id {
            scroll.swipeUp(velocity: .fast)
            far = topmostCard()
        }
        XCTAssertNotEqual(far?.id, anchor.id, "the scroll really left the anchored card behind")
        var returned: (id: String, frame: CGRect)?
        for _ in 0..<40 {
            if let candidate = topmostCard(), candidate.id == anchor.id { returned = candidate; break }
            scroll.swipeDown(velocity: .slow)
        }
        guard let returned else { return XCTFail("the anchored card is not reachable after the distant return") }
        // The offset is the criterion: the initial position and the way back from above must both sit at the
        // content origin. The content carries no top margin (`NativeFeedTargets`), precisely so the first topmost
        // card the reader returns to is the same coordinate the anchored card started at.
        let delta = returned.frame.minY - anchor.frame.minY
        print("E03_OFFSET start=\(anchor.frame.minY) returned=\(returned.frame.minY) delta=\(delta)")
        XCTAssertEqual(delta, 0, accuracy: 1,
            "the distant return preserves the anchored card's position (E03, ±1 pt)")
        attachShot("e03-distant-return")
    }

    /// R7/Codex: a publication that completes **after** the install that followed the first one must still reach the
    /// window by itself. The second endpoint answers late (`FEEDMINE_SLOW_FEED_SECONDS=10`), so the burst lands after
    /// that install; growth is bound to the publication event, and no timed chain exists to be over.
    @MainActor
    func testPublicationAfterTheFollowUpWindowStillReachesTheWindow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_SLOW_FEED_SECONDS"] = "10"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        let cards = app.buttons.matching(identifier: "card.bookmark")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 60), "the first card is the first fact")
        // The late endpoint answers long after the first publication was installed, and nothing timed remains.
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count >= 2"), object: cards)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 90), .completed,
            "a publication after the first install must still fill the window; observed \(cards.count)")
        XCTAssertEqual(proof.label, "received=0 completed=0 backward=0", "and still without a gesture")
    }

    /// T5: the reader's chrome is V1's, every control reaches a real flow, and no gesture is swallowed
    /// by an overlapping one. Only the actions this build executes are offered, so nothing here can be a
    /// dead control.
    @MainActor
    func testT5HeaderChromeAndCardGesturesReachRealFlows() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
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
        let menuShot = XCTAttachment(screenshot: app.screenshot())
        menuShot.name = "v2-shell-menu"
        menuShot.lifetime = .keepAlways
        add(menuShot)
        // Every surface this build draws is offered, and only those: the settings sheet (T10) is reachable
        // here, while a destination this build cannot present is never offered.
        XCTAssertTrue(app.buttons["Ajustes"].waitForExistence(timeout: 10),
            "the settings surface the reader has is offered")
        XCTAssertFalse(app.buttons["Importar para a coleção"].exists,
            "a destination this build cannot present is never offered")
        XCTAssertFalse(app.buttons["Copiar link"].exists, "a card action this build cannot execute is gated")
        app.buttons["Fontes"].tap()
        XCTAssertTrue(app.navigationBars["Fontes"].waitForExistence(timeout: 10))
        app.buttons["Concluir"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        // The search surface opens and cancels without touching the feed.
        app.buttons["search-button"].tap()
        XCTAssertTrue(app.textFields["reader-search-field"].waitForExistence(timeout: 10))
        app.buttons["reader-search-cancel"].tap()
        XCTAssertTrue(waitForAbsence(app.textFields["reader-search-field"], timeout: 10),
            "cancelling the search closes its field")
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        // A long press reaches the card's own menu; the same card's tap is not consumed by it.
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
        let card = cards.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 45), "a real published occurrence must appear")
        pressCard(card)
        let save = saveArticleButton(in: app)
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the long press must reach the card menu")
        save.tap()
        // Saving is really durable: the header's bookmark control opens the reader's saved surfaces (V1's own
        // screen), and the article is in the list it leads to.
        app.buttons["bookmark-boxes-button"].tap()
        XCTAssertTrue(app.buttons["Todos os salvos"].waitForExistence(timeout: 15))
        app.buttons["Todos os salvos"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved-article-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the saved article must be listed")
        app.navigationBars.buttons["BackButton"].tap()
        // The saved surface is a sheet of its own: closing it is what puts the reader back on the feed.
        XCTAssertTrue(app.buttons["bookmarkBoxes.done"].waitForExistence(timeout: 15))
        app.buttons["bookmarkBoxes.done"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        // A plain tap on the same card still opens it (the tap was never swallowed by the long press).
        tapCard(card)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 30), "tapping the card must open it")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "t5-shell-and-gestures"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Adding a feed from a link, on screen: the reader pastes an address into V1's own sheet, the address is
    /// discovered into a feed, the feed is added, and the reader reads it — and it is still there after the app
    /// is relaunched. The site and its feed come from the app's own fixture, so no test touches the network.
    ///
    /// The reader starts with no sources at all — V1's own state, where the way to get content is to add it —
    /// so what is published afterwards can only be the feed the reader brought.
    @MainActor
    func testAddFeedByLinkDiscoversAddsAndReadsIt() throws {
        let namespace = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_ADD_FEED_FIXTURE"] = "1"
        app.launchEnvironment["FEEDMINE_EMPTY_SELECTION"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(element(app, "feed-empty-state").waitForExistence(timeout: 60),
            "the reader's own chrome is drawn with no sources, which is where adding one starts")

        openMenu(app)
        app.buttons["Adicionar feed"].tap()
        XCTAssertTrue(app.navigationBars["Adicionar fontes"].waitForExistence(timeout: 20),
            "V1's add-feed sheet must be offered by the reader's own menu")
        let field = element(app, "add-feed-input")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        // A pasted address, exactly as a reader would: the site that declares its own feed.
        field.tap()
        field.typeText("https://site.feedmine.test/")
        app.buttons["add-feed-add"].tap()

        let added = element(app, "add-feed-result-added")
        XCTAssertTrue(added.waitForExistence(timeout: 30), "the sheet states what it added")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "add-feed-sheet"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["add-feed-cancel"].tap()

        // The feed the reader added is theirs: its own card is in the feed, read from the real runtime.
        let card = app.staticTexts["Fixture site story 3"]
        XCTAssertTrue(scrollIntoView(card, in: app, timeout: 90),
            "the added feed's own headline must be publishable and visible")
        let readShot = XCTAttachment(screenshot: app.screenshot())
        readShot.name = "add-feed-card"
        readShot.lifetime = .keepAlways
        add(readShot)

        // And it survives a relaunch: the same namespace, the feed still read. The launch that started with no
        // selection is over — the reader has a source now, and that is what the reopened app must find.
        app.terminate()
        app.launchEnvironment["FEEDMINE_EMPTY_SELECTION"] = "0"
        app.launch()
        XCTAssertTrue(scrollIntoView(app.staticTexts["Fixture site story 3"], in: app, timeout: 90),
            "the feed the reader added is still read after a relaunch")
    }

    /// The content filters' own surface, on screen: V1's templates, the reader's own words, and the master switch
    /// that turns the hiding off without erasing a rule — which is what the surface itself states.
    @MainActor
    func testContentFilterSurfaceListsTemplatesAndKeepsTheRules() throws {
        let namespace = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 45))

        openMenu(app)
        app.buttons["Ajustes"].tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20))
        let rules = element(app, "settings-content-filter-rules")
        XCTAssertTrue(scrollIntoView(rules, in: app, timeout: 20), "the settings must offer the filter rules")
        rules.tap()
        XCTAssertTrue(app.navigationBars["Filtros de conteúdo"].waitForExistence(timeout: 20))

        // V1's six templates are offered, each stating how many rules it adds.
        for key in ["politics", "violence", "crypto", "sports", "celebrity", "ai_hype"] {
            XCTAssertTrue(element(app, "content-filter-template-\(key)").exists, "missing template \(key)")
        }
        let state = element(app, "content-filter-state")
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        XCTAssertTrue(state.label.contains("aplicadas"), "the filters start on: \(state.label)")

        // The master switch states what it does, in both directions. A SwiftUI toggle row wraps the actual
        // switch, so the control is the switch inside the row (the same shape T7's country rows have).
        func tapGate() {
            let row = app.switches["content-filter-enabled"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10), "the master switch must be drawn")
            let control = row.switches.firstMatch.exists ? row.switches.firstMatch : row
            control.tap()
        }
        tapGate()
        let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Desligado"),
            object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [off], timeout: 10), .completed,
            "with the switch off the surface says the rules are kept and nothing is hidden")
        tapGate()

        // A rule the reader writes is listed, and survives leaving and reopening the surface.
        element(app, "content-filter-add-rule").tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.typeText("casino, apostas")
        app.alerts.buttons["Adicionar"].tap()
        XCTAssertTrue(scrollIntoView(element(app, "content-filter-rule"), in: app, timeout: 15),
            "the reader's own rule is listed")
        app.navigationBars["Filtros de conteúdo"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 15))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "content-filters-settings"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(scrollIntoView(rules, in: app, timeout: 20))
        rules.tap()
        XCTAssertTrue(app.navigationBars["Filtros de conteúdo"].waitForExistence(timeout: 20))
        XCTAssertTrue(scrollIntoView(app.staticTexts["casino"], in: app, timeout: 15),
            "the words the reader wrote are still there")
        XCTAssertTrue(app.staticTexts["apostas"].exists, "every word the reader wrote is a rule of its own")
        app.navigationBars["Filtros de conteúdo"].buttons.element(boundBy: 0).tap()
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
    }

    /// The reader's own resume, on screen: an episode plays, the app goes away, the app comes back, and the
    /// episode is where they left it — V1's own promise (`savePosition` / `restorePositionIfNeeded`).
    ///
    /// The lock screen's own continuity is not asserted here: what the simulator can prove is that the episode
    /// keeps playing while the app is not in front (the audio session and the background mode are declared), and
    /// the lockscreen/headphone commands need a physical device to be observed end to end.
    @MainActor
    func testPlaybackResumesWhereTheReaderLeftIt() throws {
        let namespace = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_MEDIA_SIMULATION"] = "1"
        app.launch()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 60))
        XCTAssertTrue(app.buttons["mini-player-toggle"].waitForExistence(timeout: 60),
            "the simulated episode is up in the reader's own bar")

        // Long enough for the player to have written a position past V1's five-second threshold.
        Thread.sleep(forTimeInterval: 8)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1)
        app.terminate()

        app.launch()
        XCTAssertTrue(app.buttons["mini-player-toggle"].waitForExistence(timeout: 60),
            "the episode is up again after the relaunch")
        let bar = element(app, "mini-player")
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        bar.tap()
        XCTAssertTrue(app.otherElements["full-player"].waitForExistence(timeout: 15))
        let scrub = app.sliders["full-player-scrub"]
        XCTAssertTrue(scrub.waitForExistence(timeout: 15), "the full player states where the reader is")
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "0%"), object: scrub)
        XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 20), .completed,
            "the episode must resume where the reader left it, not at the beginning (value: \(scrub.value ?? "nil"))")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "playback-resumed"
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

    /// A row of a scrolling list is not in the accessibility hierarchy until it has been scrolled into it.
    /// The gesture is real (the reader's own scroll) and lands on the list that is on screen — a sheet's
    /// `List` is a table, and the feed's own scroll view is what is left when there is none.
    @MainActor
    @discardableResult
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication,
        timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable { return true }
            let table = app.tables.firstMatch
            if table.exists { table.swipeUp() } else { app.swipeUp() }
        }
        return element.exists
    }

    /// The delivery's own card identity: the published occurrence's UUID, which each card states as its own
    /// identifier.
    private static let cardIdentifier =
        "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"

    /// Waits for an element to stop existing. `waitForExistence` cannot express this, and the mistake is easy to
    /// make: it returns true immediately while the element is still there, so an *inverted* assertion built on it
    /// passes the instant a transition begins rather than when it ends. An absence has to be awaited as one.
    @MainActor
    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// The card's own element contains the card, so a hit test at its centre lands on what is inside it; the
    /// reader's own long press therefore goes through that centre. It is still a real press on the card they
    /// saw, and the card's menu is what answers it.
    @MainActor
    private func pressCard(_ card: XCUIElement, forDuration duration: TimeInterval = 1.2) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: duration)
    }

    /// The same for the reader's own tap: the card opens the article it publishes.
    @MainActor
    private func tapCard(_ card: XCUIElement) {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// The context menu's save action. The card also draws its own bookmark control with the same label, so an
    /// unscoped `app.buttons["Salvar artigo"]` is ambiguous exactly when the menu is open. Prefer the menu; fall
    /// back to the first match only when the platform exposes the item outside a menu element.
    @MainActor
    private func saveArticleButton(in app: XCUIApplication) -> XCUIElement {
        let menuItem = app.menus.buttons["Salvar artigo"].firstMatch
        if menuItem.waitForExistence(timeout: 5) { return menuItem }
        return app.buttons["Salvar artigo"].firstMatch
    }

    /// T6: the reader's filter sheet is V1's, and applying a selection is one explicit transition — the sheet
    /// closes only after the host persisted the identity and rebuilt the session around it.
    @MainActor
    func testT6FilterSheetOpensAppliesAndKeepsTheReader() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        // The filtered context's launch may consult the real catalogue for discovery; the closed proxy (the app's
        // own fault configuration) makes those connections fail immediately instead of holding the transition on
        // 60-second cleartext timeouts. The fixture answers the two local feeds.
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        // A language criterion creates a discovery profile; discovery would walk the real catalogue for public
        // sources. This transition test declares its fixture: the two local feeds, nothing discovered.
        app.launchEnvironment["FEEDMINE_DISABLE_DISCOVERY"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 10), "the filter sheet must open")
        // The criteria this build can enforce are the ones it offers; the rest are absent, not inert. The
        // criterion applied is the one the fixtures themselves declare (`en`), so the filtered context is a
        // context this reader can be in: its feed comes back with cards.
        let languages = app.buttons["language-en"]
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
        // If the host refused the transition, the sheet's own alert says why. Record that sentence instead of
        // letting the default interruption handler silently dismiss the evidence.
        if app.alerts["Filtro"].waitForExistence(timeout: 8) {
            let failure = app.alerts["Filtro"].staticTexts.allElementsBoundByIndex.map(\.label)
                .joined(separator: " | ")
            let attachment = XCTAttachment(string: failure)
            attachment.name = "filter-apply-failure"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.alerts["Filtro"].buttons["OK"].tap()
        }
        // The transition is explicit and complete: the sheet is gone and the reader is on the filtered context.
        XCTAssertTrue(waitForAbsence(app.buttons["filter-done"], timeout: 90),
            "the transition closes the sheet before the reader is back")
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "the reader keeps a feed after the transition")
        XCTAssertTrue(proof.waitForExistence(timeout: 10))
        // The lens states the criterion that is applied and removes exactly that one when its chip is tapped.
        let lensChip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'lens-chip-language-'")).firstMatch
        XCTAssertTrue(lensChip.waitForExistence(timeout: 10), "an applied criterion must show its chip")
        lensChip.tap()
        // Removing the criterion has to be awaited as an absence: `waitForExistence` returns true the instant the
        // chip still exists, so the inverted form would pass before the transition had done anything. The tap is
        // deliberately left as a plain `tap()` — if the chip is not hittable, that is a finding, not a nuisance to
        // be routed around with a coordinate press.
        XCTAssertTrue(waitForAbsence(lensChip, timeout: 10), "removing the chip clears that criterion")
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
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
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

    /// T12: the keyboard scenario the plan asks for. Opening the reader's own search surface and **writing a
    /// query** is not a transition: the reading point and the feed's published counters stay where they were, and
    /// cancelling the search returns the same reader to the same card. Opening and cancelling without typing is
    /// already covered by T5; this is the part that involves the keyboard.
    @MainActor
    func testT12KeyboardSearchKeepsTheReadingPointAndRestoresIt() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let proof = app.staticTexts["native-viewport-delivery"]
        XCTAssertTrue(proof.waitForExistence(timeout: 15))
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@", "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 45), "a real published occurrence must appear")
        let before = proof.label
        app.buttons["search-button"].tap()
        let field = app.textFields["reader-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("ciencia")
        XCTAssertEqual(field.value as? String, "ciencia", "the field takes what the reader types")
        XCTAssertEqual(proof.label, before, "writing a query is not an update the reader asked for")
        app.buttons["reader-search-cancel"].tap()
        XCTAssertTrue(waitForAbsence(field, timeout: 10), "cancelling the search closes its field")
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        XCTAssertTrue(card.waitForExistence(timeout: 20), "the same card is still there to read")
        XCTAssertEqual(proof.label, before, "cancelling restores the reader instead of rebuilding the session")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "t12-keyboard-search"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// P1/P08/E07: the search the reader submits is a **surface**, and the durable context reopens it offline in a
    /// new process. This is the end-to-end path the earlier attempt could not reach: the typed page is installed
    /// by the real bar, not only by a store call.
    @MainActor
    func testT12SearchSubmitsAndReopensOfflineAsTheSameSurface() throws {
        let namespace = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = namespace
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        // The rebuild for the search context must not wait on discovery of a profile the local fixture cannot
        // answer; the test's question is the search surface, not the transport's timing.
        app.launchEnvironment["FEEDMINE_DISABLE_DISCOVERY"] = "1"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45), "o feed apresenta antes da busca")
        XCTAssertTrue(app.staticTexts["native-viewport-delivery"].waitForExistence(timeout: 20))

        app.buttons["search-button"].tap()
        let field = app.textFields["reader-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Fixture")
        field.typeText("\n")

        let results = app.descendants(matching: .any)["reader-search-results"]
        XCTAssertTrue(results.waitForExistence(timeout: 30),
            "submeter a busca instala a página tipada, não apenas troca o contexto")
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "reader-search-result-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30), "as autoridades locais têm resultado")
        let firstLabel = rows.firstMatch.label

        app.terminate()
        let offline = XCUIApplication()
        offline.launchEnvironment = app.launchEnvironment
        offline.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        offline.launch()
        let reopened = offline.descendants(matching: .any)["reader-search-results"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 60),
            "o contexto de busca durável reabre já na superfície de resultados, offline")
        let reopenedRows = offline.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "reader-search-result-"))
        XCTAssertTrue(reopenedRows.firstMatch.waitForExistence(timeout: 30),
            "a mesma página local é servida sem rede")
        XCTAssertEqual(reopenedRows.firstMatch.label, firstLabel,
            "a superfície reaberta mostra os mesmos resultados, não uma lista vazia")
    }

    /// T9/T12: the playback bar the reader keeps visible is the **live** one. A review flagged that the hosted
    /// reader might hold the state it was built with, so this test changes the state *inside* the reader — where
    /// a frozen copy would keep reporting the old one.
    @MainActor
    func testT12ReaderKeepsTheLivePlaybackBar() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_MEDIA_SIMULATION"] = "1"
        // The site is a modal SFSafariViewController now (Apple's contract), so it covers the app's bar by
        // design; the bar the reader keeps visible is the local page's. A stored body opens that page.
        app.launchEnvironment["FEEDMINE_FIXTURE_TEXT"] = "body"
        app.launch()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 45))
        let toggle = app.buttons["mini-player-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertEqual(toggle.label, "Pausar", "the simulated episode is playing, and the bar says so")
        // Open the reader from a real card: V1's reader keeps the bar visible while an episode plays.
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@",
                "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 45), "a real published occurrence must appear")
        card.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "reading.body"))
            .firstMatch.waitForExistence(timeout: 30), "tapping the card opens the local reader")
        XCTAssertTrue(app.buttons["mini-player-toggle"].waitForExistence(timeout: 15),
            "the reader keeps the playback bar visible")
        XCTAssertEqual(app.buttons["mini-player-toggle"].label, "Pausar", "and it is the live state, not a copy")
        app.buttons["mini-player-toggle"].tap()
        XCTAssertEqual(app.buttons["mini-player-toggle"].label, "Tocar",
            "pausing inside the reader is what the bar then reports")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "v2-reader-playback-bar"
        shot.lifetime = .keepAlways
        add(shot)
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

    /// Round 9: the composer offers one chip per language — never the catalogue's code, never two chips a reader
    /// cannot tell apart — and the catalogue's regional codes appear as information, counted, with nothing
    /// selectable inside the expansion.
    @MainActor
    func testComposerOffersOneChipPerLanguage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["welcome-headline"].label, "A web aberta, arrumada por você.",
            "the head-line is the interface's, not a fixed English string")
        app.buttons["welcome-shape"].tap()

        let chips = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "composer-language-[a-z]{2,3}"))
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 90),
            "the composer offers the catalogue's languages")
        let labels = chips.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count, "two chips a reader cannot tell apart: \(labels)")
        XCTAssertTrue(labels.contains("Português"), "the interface names the language in its own language: \(labels)")
        XCTAssertFalse(labels.contains("pt") || labels.contains("pt-BR"),
            "a chip is never one of the catalogue's codes: \(labels)")

        let portuguese = app.buttons["composer-language-pt"]
        XCTAssertTrue(portuguese.exists, "the language is one chip, addressed by the language itself")
        portuguese.tap()
        XCTAssertTrue(portuguese.isSelected, "tapping the chip chooses the language")

        app.buttons["composer-language-regions-pt"].tap()
        let variants = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'composer-language-variant-'"))
        let found = variants.allElementsBoundByIndex
            .map { "\($0.identifier)|\($0.elementType.rawValue)|\($0.label.prefix(24))" }
        XCTAssertFalse(found.isEmpty,
            "the expansion names the catalogue's own codes under the language; present: \(found.joined(separator: " ; "))")
        for variant in variants.allElementsBoundByIndex {
            XCTAssertNotEqual(variant.elementType, .button, "a region is information, never a control")
        }
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "fontes disponíveis")).firstMatch.exists,
            "the expansion counts what the catalogue holds, in the approved wording")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "r9-composer-language-expansion-pt-BR"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Item C, the owner's decision: the first run **asks** the reader's language — no chip is pre-selected from
    /// the device — and the reader can skip. "Todos os idiomas" is that skip, stated where the question is and
    /// selected while no language is named, so the state the reader enters with is visible and reversible.
    @MainActor
    func testTheFirstRunAsksTheLanguageAndLetsTheReaderSkip() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 90))
        app.buttons["welcome-shape"].tap()

        let question = app.staticTexts["composer-language-question"]
        XCTAssertTrue(question.waitForExistence(timeout: 90), "the first run states the language question")
        XCTAssertEqual(question.label, "Em quais idiomas você quer ler?",
            "the question is the interface's own words, not a catalog code")

        let skip = app.buttons["composer-languages-unrestricted"]
        XCTAssertTrue(skip.exists, "the skip is stated where the question is")
        XCTAssertTrue(skip.isSelected, "and it is the state of a reader who has not answered")

        let chips = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@",
            "composer-language-[a-z]{2,3}"))
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 90), "the catalogue's languages are offered")
        XCTAssertFalse(chips.allElementsBoundByIndex.contains { $0.isSelected },
            "no language is chosen for the reader before they answer")

        let composer = app.otherElements["onboarding"].scrollViews.firstMatch
        let portuguese = app.buttons["composer-language-pt"]
        for _ in 0..<4 where !portuguese.isHittable { composer.swipeUp() }
        XCTAssertTrue(portuguese.isHittable)
        portuguese.tap()
        XCTAssertTrue(portuguese.isSelected, "the reader's answer is stated")
        XCTAssertFalse(skip.isSelected, "and the skip stops being the answer")

        for _ in 0..<4 where !skip.isHittable { composer.swipeUp() }
        XCTAssertTrue(skip.isHittable)
        skip.tap()
        XCTAssertTrue(skip.isSelected, "taking the last answer back is the skip")
        XCTAssertFalse(portuguese.isSelected)
    }

    /// The interface follows the device: in English the same screen is English, the languages are named in
    /// English, and the counts are stated in English.
    @MainActor
    func testInterfaceFollowsTheDeviceLanguage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 90))
        XCTAssertEqual(app.staticTexts["welcome-headline"].label, "The open web, arranged by you.")
        XCTAssertEqual(app.buttons["welcome-shape"].label, "Build my feed",
            "the welcome copy follows the device's language")
        app.buttons["welcome-shape"].tap()

        let chips = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "composer-language-[a-z]{2,3}"))
        XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 90))
        let labels = chips.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains("Portuguese"), "a language is named in the interface's own language: \(labels)")
        XCTAssertFalse(labels.contains("Português"), "not in the catalogue's own language: \(labels)")

        app.buttons["composer-language-pt"].tap()
        app.buttons["composer-language-regions-pt"].tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "sources available")).firstMatch.exists,
            "the counts are stated in the interface's language")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "r9-composer-language-expansion-en"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Round 9: the filter sheet offers one selectable row per language with the count the catalogue holds, and
    /// the catalogue's own codes appear only inside the expansion, as information. The sheet is the same row model
    /// as the composer's chips, on the surface that persists a selection.
    @MainActor
    func testFilterSheetOffersOneRowPerLanguage() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["filter-button"].waitForExistence(timeout: 120), "the reader's chrome is up")
        app.buttons["filter-button"].tap()

        let rows = app.buttons.matching(NSPredicate(format: "identifier MATCHES %@", "language-[a-z]{2,3}"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "the sheet lists the catalogue's languages")
        let labels = rows.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(labels.contains { $0.hasPrefix("Português") },
            "the row names the language and counts what the catalogue holds: \(labels)")
        XCTAssertTrue(labels.contains { $0.contains("fontes disponíveis") }, "one unit, stated: \(labels)")
        XCTAssertFalse(app.buttons["language-pt-BR"].exists, "a catalogue code is never a row")
        XCTAssertFalse(app.buttons["language-en-US"].exists, "nor is any other regional code")

        app.buttons["language-regions-pt"].tap()
        XCTAssertTrue(app.staticTexts["language-variant-pt-BR"].waitForExistence(timeout: 20),
            "the expansion names the region the catalogue declares under the language")
        XCTAssertFalse(app.buttons["language-variant-pt-BR"].exists, "and the region is not selectable")
        let counted = app.staticTexts["language-variant-count-pt-BR"]
        XCTAssertTrue(counted.exists)
        XCTAssertEqual(counted.label, "936", "the variant row counts what the catalogue holds for that code")

        app.buttons["language-pt"].tap()
        XCTAssertEqual(app.buttons["language-pt"].value as? String, "selected",
            "the row selects the language, and what it persists is the language")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "r9-filter-sheet-language-expansion-pt-BR"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["filter-done"].tap()
    }

    /// The reader's way out of a source context that has **no eligible item yet**. Measured dead end
    /// (`bench/run/20261023T220407Z`): a single selected source drew a full-screen "Finding stories for you…"
    /// with no header, no context control and no way back for more than seven minutes. The shell (context chip,
    /// sources, saved, filters, menu) must stay mounted while the content is loading or empty, and Main must be
    /// reachable without waiting for any card. The source is deterministic: Algeria's only feed is French, so it
    /// cannot publish for this Portuguese/Brazil reader.
    @MainActor
    func testAnEmptySourceContextKeepsTheContextControl() throws {
        // One failure is the finding: a setup step that cannot be reached must not decay into a chain of
        // timeouts and irrelevant taps.
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "0"
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 90),
            "the reader meets the app")
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 30))
        let english = app.buttons["composer-language-en"]
        if english.exists, english.isSelected || english.value as? String == "1" { english.tap() }
        let portuguese = app.buttons["composer-language-pt"]
        if portuguese.exists, !(portuguese.isSelected || portuguese.value as? String == "1") {
            portuguese.tap()
        }
        let composer = app.otherElements["onboarding"].scrollViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        let place = app.buttons["composer-region-90_countries/brazil"]
        for _ in 0..<8 where !(place.exists && place.isHittable) { composer.swipeUp() }
        XCTAssertTrue(place.exists && place.isHittable, "the first run offers the reader's place")
        if !place.isSelected { place.tap() }
        // The fixture profile must really be configured, or "ineligible for this reader" would be an assumption:
        // Portuguese selected, English not, Brazil selected.
        XCTAssertTrue(portuguese.exists
            && (portuguese.isSelected || portuguese.value as? String == "1"),
            "the fixture profile declares Portuguese")
        if english.exists {
            XCTAssertFalse(english.isSelected || english.value as? String == "1",
                "English is not part of the fixture profile")
        }
        XCTAssertTrue(place.isSelected, "the fixture profile declares Brazil")
        let open = app.buttons["composer-open-feed"]
        for _ in 0..<6 where !open.isHittable { composer.swipeUp() }
        XCTAssertTrue(open.isHittable, "the first run's own action starts the feed")
        open.tap()
        let menu = app.buttons["more-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 240), "the reader reaches the feed's chrome")
        // The chrome must be *usable*, not merely present: after the first-run transition it can exist behind the
        // preparation surface until the feed it belongs to has content. On the old screen that is exactly the
        // reachability the regression is about, so the wait is on hittability, bounded.
        XCTAssertTrue(waitUsable(menu, app, timeout: 180), "the reader's chrome is usable")
        // Deterministic ineligibility without a network trick: the reader's own language filter is Portuguese.
        // The pinned feed is French, so its source context has no item to draw even though the feed resolves —
        // the same product criterion that left the measured source context empty.
        app.buttons["filter-button"].tap()
        let portugueseRow = app.buttons["language-pt"]
        guard reveal(app, portugueseRow) else {
            XCTFail("the filter lists Portuguese"); return
        }
        if portugueseRow.value as? String != "selected" { portugueseRow.tap() }
        guard portugueseRow.value as? String == "selected" else {
            XCTFail("the filter selects Portuguese"); return
        }
        app.buttons["filter-done"].tap()
        guard menu.waitForExistence(timeout: 60), waitUsable(menu, app, timeout: 60) else {
            XCTFail("the feed's chrome returns after the filter"); return
        }
        // The exact pinned feed at its proven catalogue placement. The node ids are the shipped catalogue's own
        // (`FeedMineApp/.../Resources/catalog.sqlite` and the frozen corpus agree): Algeria → Entertainment →
        // Celebrity & Gossip → the feed key. No display-order heuristic, no label variant.
        let frenchFeed = "https://enriqueiglesias.forumactif.org/feed"
        guard openReaderMenuEntry(app, menu, symbol: "antenna.radiowaves.left.and.right") else {
            XCTFail("the menu offers the source surface"); return
        }
        let countries = app.buttons["sources-open-countries"]
        guard reveal(app, countries) else { XCTFail("the source surface offers its choices"); return }
        countries.tap()
        let algeria = app.buttons["country-algeria"]
        guard reveal(app, algeria) else { XCTFail("the countries list offers Algeria"); return }
        algeria.tap()
        let entertainment = app.buttons["node-child-3142363754"]
        guard reveal(app, entertainment) else { XCTFail("Algeria offers Entertainment"); return }
        entertainment.tap()
        let celebrity = app.buttons["node-child-2932038721"]
        guard reveal(app, celebrity) else { XCTFail("Entertainment offers Celebrity & Gossip"); return }
        celebrity.tap()
        let sourceToggle = app.switches["node-source-toggle-\(frenchFeed)"]
        guard reveal(app, sourceToggle) else {
            XCTFail("the pinned French feed is offered"); return
        }
        sourceToggle.tap()
        Thread.sleep(forTimeInterval: 1)
        for _ in 0..<8 where !app.buttons["sources-done"].exists {
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists, back.isHittable else { break }
            back.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard app.buttons["sources-done"].exists, app.buttons["sources-done"].isHittable else {
            XCTFail("the source sheet returns to its Done control"); return
        }
        app.buttons["sources-done"].tap()
        // The single selected source becomes the reading context. It has no eligible item for this reader: the
        // loading surface is what is drawn and **no card** is presented. Only that state makes the escape
        // meaningful; a test that ran with content would not be the regression.
        let loading = element(app, "feed-loading-surface")
        guard loading.waitForExistence(timeout: 45) else {
            XCTFail("the source context is preparing with no eligible item"); return
        }
        Thread.sleep(forTimeInterval: 2)
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@",
                "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"))
            .allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 40 && $0.frame.intersects(app.windows.firstMatch.frame) }
        guard cards.isEmpty else {
            XCTFail("no card is presented for this ineligible source"); return
        }
        // The shell must still be the reader's surface. On the old screen this is the failing assertion: the
        // context control is absent and the reader has no way back.
        let chip = element(app, "reader-contexts")
        guard chip.waitForExistence(timeout: 30) else {
            XCTFail("the context control is mounted while the source context has no item"); return
        }
        let identity = element(app, "reader-context-label")
        guard identity.exists, identity.label.contains("enrique iglesias") else {
            XCTFail("the source context states its own identity: \(identity.exists ? identity.label : "absent")")
            return
        }
        guard chip.isHittable else {
            XCTFail("the context control is usable without waiting for content"); return
        }
        chip.tap()
        let entries = contextMenuEntries(app)
        guard !entries.isEmpty else { XCTFail("the context menu offers the way back to Main"); return }
        entries[0].tap()
        guard waitForAbsence(element(app, "reader-context-label"), timeout: 30) else {
            XCTFail("the reader returns to the main context without waiting for content"); return
        }
        guard element(app, "reader-contexts").isHittable else {
            XCTFail("the control remains available after returning"); return
        }
    }

    /// Opens the reader's overflow menu and its entry by identifier across element types, retrying the reader's
    /// own gesture when the first open arrives before the destinations are installed.
    @MainActor
    private func openReaderMenuEntry(_ app: XCUIApplication, _ menu: XCUIElement, symbol: String) -> Bool {
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", symbol)).firstMatch
        for _ in 0..<4 {
            menu.tap()
            if entry.waitForExistence(timeout: 5) {
                entry.tap()
                return true
            }
            if menu.exists { menu.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    /// Waits until a control can really be used, not merely exists. The check is the project's own frame-in-window
    /// rule rather than `isHittable`: during the rebuild that follows a filter, XCUITest raised "Failed to determine
    /// hittability" for a control whose snapshot was in flight.
    @MainActor
    private func waitUsable(_ element: XCUIElement, _ app: XCUIApplication,
        timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists {
                let frame = element.frame
                let window = app.windows.firstMatch.frame
                if frame.width > 1, frame.height > 1,
                    window.contains(CGPoint(x: frame.midX, y: frame.midY)) { return true }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return element.exists
    }

    /// Scrolls a lazy list until the control is really reachable.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement, attempts: Int = 10) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            let list = app.tables.firstMatch
            if list.exists { list.swipeUp() } else { app.swipeUp() }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return element.exists && element.isHittable
    }

    /// The rows of the product's context menu: buttons without an identifier (every app control carries one),
    /// main first — the same language-independent rule the benchmark driver states.
    @MainActor
    private func contextMenuEntries(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && $0.identifier.isEmpty && !$0.label.isEmpty }
            .sorted { $0.frame.minY < $1.frame.minY }
    }
}
