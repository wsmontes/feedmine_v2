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

}
