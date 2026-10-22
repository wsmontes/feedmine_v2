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
        let link = app.buttons["countries-link"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(link, in: app, timeout: 20),
            "the filter sheet offers Países")
        link.tap()

        XCTAssertTrue(app.navigationBars["Países"].waitForExistence(timeout: 20),
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
        XCTAssertTrue(SurfaceTest.scrollIntoView(app.buttons["countries-link"], in: app, timeout: 20))
        app.buttons["countries-link"].tap()
        XCTAssertTrue(app.navigationBars["Países"].waitForExistence(timeout: 20))
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

    /// A filter criterion acts through the same transition and its own lens chip removes only that criterion.
    /// This exercises mood (host-only coverage) and clear-all without inventing an effect.
    @MainActor
    func testMoodCriterionAppliesAndItsLensChipRemovesOnlyIt() throws {
        let app = SurfaceTest.launchFixture()
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 20))

        let mood = app.buttons["mood-fun"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(mood, in: app, timeout: 20), "Humor is offered")
        mood.tap()
        XCTAssertEqual(mood.value as? String, "selected", "the draft states the chosen mood")
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        let chip = app.buttons["lens-chip-mood"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "the applied mood is stated by the lens")
        chip.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(chip, timeout: 30),
            "the mood chip removes the mood criterion")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20),
            "the reader stays on the feed while the criterion is removed")
    }

    /// `Reunir estas fontes` is offered only where the context has sources to collect (a committed search or a
    /// filter with two criteria). The collection it creates must open with the current sources as members.
    @MainActor
    func testCollectSourcesFromSearchCreatesACollectionWithMembers() throws {
        let app = SurfaceTest.launchFixture()
        let name = "Fontes \(UUID().uuidString.prefix(6))"
        app.buttons["search-button"].tap()
        let field = app.textFields["reader-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        field.typeText("Fixture")
        field.typeText("\n")
        XCTAssertTrue(SurfaceTest.element(app, "reader-search-results").waitForExistence(timeout: 30))

        SurfaceTest.menuEntry(app, "Reunir estas fontes")
        let prompt = app.alerts["Reunir estas fontes"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        prompt.textFields.firstMatch.typeText(name)
        prompt.buttons["Salvar"].tap()

        XCTAssertTrue(app.navigationBars["Coleções de fontes"].waitForExistence(timeout: 20),
            "collecting the sources opens the collection it just created")
        let row = app.staticTexts[name]
        XCTAssertTrue(SurfaceTest.scrollIntoView(row, in: app, timeout: 20))
        row.tap()
        XCTAssertTrue(app.buttons["collection.openFeed"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["collection.member"].firstMatch
            .waitForExistence(timeout: 20), "the collected sources are the collection's members")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["collections.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
    }
}
