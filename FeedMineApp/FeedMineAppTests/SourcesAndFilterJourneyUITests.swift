// File: SourcesAndFilterJourneyUITests.swift
// Module: FeedMineUITests
// Owns: the filter sheet's countries level, the lens chips, and the source/country selection transition.
// Each test acts and then re-reads the durable state (reopening the surface), never just existence.

import XCTest

final class SourcesAndFilterJourneyUITests: XCTestCase {
    /// G2: "Países" inside Filters must open the countries list, and a country toggle must reach the persisted
    /// selection. Before the host supplied `onShowCountries`, the tap did nothing at all.
    @MainActor
    func testCountriesLinkNavigatesAndCountryTogglePersists() throws {
        let app = SurfaceTest.launchFixture()

        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 20))
        XCTAssertTrue(SurfaceTest.tapCountriesLink(app),
            "Países opens the country list instead of leaving the tap unanswered")
        let toggles = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'country-toggle-' AND identifier != 'country-toggle-all'"))
        let country = toggles.firstMatch
        XCTAssertTrue(country.waitForExistence(timeout: 30), "the catalog's countries are listed")
        let before = country.value as? String
        country.tap()
        XCTAssertTrue(SurfaceTest.waitForValue(country, differentFrom: before, timeout: 30),
            "the country toggle changes its own value")
        let after = country.value as? String
        let slug = country.identifier.replacingOccurrences(of: "country-toggle-", with: "")

        // Return to the filter sheet without accepting it, then to the feed. The selection is a source fact and
        // must survive both dismissals.
        app.buttons["countries-done"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 20),
            "closing Países returns to the filter sheet that opened it")
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))

        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 20))
        XCTAssertTrue(SurfaceTest.tapCountriesLink(app),
            "Países opens again after the sheet is reopened")
        let reopened = app.switches["country-toggle-\(slug)"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 20))
        XCTAssertEqual(reopened.value as? String, after,
            "the country selection the reader made is still the one drawn after reopening")
        XCTAssertNotEqual(after, before, "the journey changed the selection it asserts")

        let proof = XCTAttachment(string:
            "countries-link=opened country=\(slug) before=\(before ?? "nil") after=\(after ?? "nil") "
                + "reopened=\(reopened.value as? String ?? "nil")")
        proof.name = "countries-link-and-toggle"
        proof.lifetime = .keepAlways
        add(proof)
    }

    /// G3: the preset chip states the active saved context and its `x` must remove *that preset*, exactly like
    /// V1's `setActivePreset(.everything)`. Before the host branch the tap re-applied the same preset, so the chip
    /// stayed and the reader could not leave the criterion from the lens.
    @MainActor
    func testLensPresetChipRemovesThePresetCriterion() throws {
        let app = SurfaceTest.launchFixture()
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 20))
        let preset = app.buttons["preset-option-lastClicked"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(preset, in: app, timeout: 20),
            "the filter sheet offers V1's Último aberto preset")
        preset.tap()
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        let chip = app.buttons["lens-chip-preset"]
        XCTAssertTrue(chip.waitForExistence(timeout: 30),
            "applying a preset is stated by the lens")
        chip.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(chip, timeout: 30),
            "removing the preset chip leaves the preset criterion")

        // The preset itself is not deleted by leaving it: the filter sheet still offers it.
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 20))
        XCTAssertTrue(SurfaceTest.scrollIntoView(app.buttons["preset-option-lastClicked"], in: app, timeout: 20),
            "the preset survives the lens removal and is offered again")
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["lens-chip-preset"].exists,
            "the lens stays without the preset chip after returning to the feed")

        let proof = XCTAttachment(string: "preset=lastClicked chip-removed=true preset-still-offered=true")
        proof.name = "lens-preset-chip-removal"
        proof.lifetime = .keepAlways
        add(proof)
    }

    /// F12/V1's filter contract: the sheet going away **is** the apply. The node level's Concluído closes the
    /// whole surface, so a draft edited before walking Filtros → Países → nó reaches the same `dismiss()` the
    /// toolbar uses. Before this, that close dropped the edits and left the old filter applied.
    /// Assertions use accessibility identifiers only: this device runs the app in English, so the localized titles
    /// ("Filtros") are not stable selectors.
    @MainActor
    func testFilterDraftEditedBeforeTheNodeLevelIsAppliedWhenThatLevelCloses() throws {
        let app = SurfaceTest.launchFixture()
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 30), "the filter sheet is presented")
        let preset = app.buttons["preset-option-lastClicked"]
        XCTAssertTrue(preset.waitForExistence(timeout: 20), "the sheet offers its preset criterion")
        XCTAssertEqual(preset.value as? String, "not selected", "premise: the draft starts clean")
        preset.tap()
        XCTAssertEqual(preset.value as? String, "selected", "the draft is dirty before the level is opened")

        let countries = app.buttons["countries-link"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(countries, in: app, timeout: 20), "Países is offered")
        for _ in 0..<3 where !app.buttons["countries-done"].exists {
            countries.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(app.buttons["countries-done"].waitForExistence(timeout: 30), "Países opens")
        let country = app.buttons["country-algeria"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(country, in: app, timeout: 30), "the countries are listed")
        country.tap()
        let done = app.buttons["node-sources-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30), "the node level offers its own Concluir")
        done.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.buttons["filter-done"], timeout: 20),
            "closing the node level goes away from the whole sheet")
        // What the **applied** selection is, not what the sheet would still hold as a draft: the lens is built from
        // the confirmed filter, so it is the discriminating fact of this journey.
        XCTAssertTrue(app.buttons["lens-chip-preset"].waitForExistence(timeout: 20),
            "the preset the draft named is applied, stated by the feed's own lens")

        // The durable re-read: reopening hydrates from what was applied, not from what was drawn.
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 30))
        let reopened = app.buttons["preset-option-lastClicked"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 20))
        XCTAssertEqual(reopened.value as? String, "selected",
            "the edit made before the node level was applied, not discarded")
        app.buttons["filter-done"].tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.buttons["filter-done"], timeout: 20))

        let proof = XCTAttachment(string: "path=Filtros>Paises>country-algeria>Concluir preset=lastClicked applied=true")
        proof.name = "filter-node-close-applies"
        proof.lifetime = .keepAlways
        add(proof)
    }

    /// The platform gesture: a swipe that dismisses the sheet ends its view tree, so the draft store lives with the
    /// presenter and the dismissal itself applies the draft. Before this, the swipe discarded the edits.
    @MainActor
    func testSwipeDismissalOfTheFilterSheetAppliesTheDraft() throws {
        let app = SurfaceTest.launchFixture()
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 30))
        let preset = app.buttons["preset-option-lastClicked"]
        XCTAssertTrue(preset.waitForExistence(timeout: 20), "the sheet offers its preset criterion")
        preset.tap()
        XCTAssertEqual(preset.value as? String, "selected", "the draft is dirty before the swipe")

        // The sheet's own grabber: a downward drag from the top of the presented sheet is the interactive
        // dismissal. Coordinates only — no localized title takes part.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.buttons["filter-done"], timeout: 20),
            "the swipe dismissed the sheet instead of leaving it up")
        // What the **applied** selection is, not what the sheet would still hold as a draft: the lens is built from
        // the confirmed filter, so it is the discriminating fact of this journey.
        XCTAssertTrue(app.buttons["lens-chip-preset"].waitForExistence(timeout: 20),
            "the preset the draft named is applied, stated by the feed's own lens")

        // The durable re-read: the state the dismissal wrote is what the sheet hydrates the next time.
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 30))
        let reopened = app.buttons["preset-option-lastClicked"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 20))
        XCTAssertEqual(reopened.value as? String, "selected",
            "the swipe applied the draft instead of discarding it")
        app.buttons["filter-done"].tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(app.buttons["filter-done"], timeout: 20))

        let proof = XCTAttachment(string: "path=swipe-down preset=lastClicked applied=true")
        proof.name = "filter-swipe-applies"
        proof.lifetime = .keepAlways
        add(proof)
    }

}
