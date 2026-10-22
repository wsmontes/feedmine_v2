// File: ReleaseSurfaceJourneyUITests.swift
// Module: FeedMineUITests
// Owns: the Release build's own surfaces, driven without any DEBUG fixture, namespace or instrument. The app is
//       the one a reader gets; the run may reach the public catalogue for discovery, but every assertion here is
//       about the published controls and their stored effect, not about a fixture.
//
// Run through scripts/ui-surface-suite.sh --profile release (FeedMineSurfaces scheme). The script uninstalls the
// Release app first, so this test starts from a clean container.

import XCTest

final class ReleaseSurfaceJourneyUITests: XCTestCase {
    @MainActor
    func testReleaseOnboardingSettingsAndCountryFilterAct() throws {
        let app = XCUIApplication()
        app.launch()

        // First run: the gate is the product's own. "Começar amplo" is the shortest published way through it.
        let welcome = app.staticTexts["welcome-headline"]
        if welcome.waitForExistence(timeout: 90) {
            let broad = app.buttons["welcome-broad"]
            XCTAssertTrue(broad.waitForExistence(timeout: 20), "the gate offers the broad start")
            broad.tap()
        }
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 180),
            "the release app reaches its reader chrome")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 180),
            "the release association is up before a surface journey starts")

        // Settings: one stored option, read back after closing and reopening the sheet.
        SurfaceTest.menuEntry(app, "Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 30))
        let night = app.switches["settings-night-mode"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(night, in: app, timeout: 30))
        let before = night.value as? String
        let nightControl = night.switches.firstMatch
        (nightControl.exists ? nightControl : night).tap()
        XCTAssertTrue(SurfaceTest.waitForValue(night, differentFrom: before, timeout: 20))
        let after = night.value as? String
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
        SurfaceTest.menuEntry(app, "Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.switches["settings-night-mode"].value as? String, after,
            "the release settings read the stored option after reopening")
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        // Filters → Países, toggled and closed. The country selection is a durable source fact.
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 30))
        XCTAssertTrue(SurfaceTest.tapCountriesLink(app), "Países opens from the release filter sheet")
        let toggles = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH 'country-toggle-' AND identifier != 'country-toggle-all'"))
        let country = toggles.firstMatch
        XCTAssertTrue(country.waitForExistence(timeout: 60), "the bundled catalogue lists countries")
        let countryBefore = country.value as? String
        let countryID = country.identifier
        country.tap()
        XCTAssertTrue(SurfaceTest.waitForValue(country, differentFrom: countryBefore, timeout: 60))
        let countryAfter = country.value as? String
        app.buttons["countries-done"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 30))
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        // Reopen the same level and read the same country again: the Release selection is durable.
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 30))
        XCTAssertTrue(SurfaceTest.tapCountriesLink(app), "Países opens again in Release")
        let reopened = app.switches[countryID]
        XCTAssertTrue(reopened.waitForExistence(timeout: 60))
        XCTAssertEqual(reopened.value as? String, countryAfter,
            "the Release country selection is read back after reopening the filter sheet")
        app.buttons["countries-done"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 30))
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        let proof = XCTAttachment(string: "release-night=\(after ?? "nil") country=\(countryID) "
            + "countryBefore=\(countryBefore ?? "nil") countryAfter=\(countryAfter ?? "nil")")
        proof.name = "release-surface-journey"
        proof.lifetime = .keepAlways
        add(proof)
    }

    /// The rest of the published surfaces in Release: every destination the menu offers is reachable, and the
    /// sheets act (Salvos, Coleções, Exportar with a format change, Adicionar feed) without any fixture.
    @MainActor
    func testReleaseMenusAndToolsAct() throws {
        let app = XCUIApplication()
        app.launch()
        if app.staticTexts["welcome-headline"].waitForExistence(timeout: 90) {
            app.buttons["welcome-broad"].tap()
        }
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 180))
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 180))

        SurfaceTest.openMenu(app)
        for entry in ["Fontes", "Salvos", "Coleções de fontes", "Ajustes", "Exportar", "Adicionar feed"] {
            XCTAssertTrue(app.buttons[entry].firstMatch.waitForExistence(timeout: 10),
                "Release menu offers \(entry)")
        }
        app.buttons["Salvos"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Caixas de salvos"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["bookmarkBoxes.new"].exists)
        app.buttons["bookmarkBoxes.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        SurfaceTest.menuEntry(app, "Coleções de fontes")
        XCTAssertTrue(app.navigationBars["Coleções de fontes"].waitForExistence(timeout: 30))
        XCTAssertTrue(SurfaceTest.element(app, "collections-empty").waitForExistence(timeout: 20))
        app.buttons["collections.done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        SurfaceTest.menuEntry(app, "Exportar")
        XCTAssertTrue(app.navigationBars["Exportar"].waitForExistence(timeout: 30))
        let preview = app.staticTexts["export-preview"]
        let empty = app.staticTexts["export-empty"]
        let hasDocument = preview.waitForExistence(timeout: 30)
        XCTAssertTrue(hasDocument || empty.exists,
            "the Release export states either a document or that there is nothing to write")
        let format = app.buttons["export-format"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(format, in: app, timeout: 20))
        format.tap()
        let json = app.buttons["Backup JSON"].firstMatch
        XCTAssertTrue(json.waitForExistence(timeout: 5), "the format picker offers Backup JSON")
        json.tap()
        if hasDocument {
            let opml = preview.label
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label != %@", opml), object: preview)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 30), .completed,
                "the Release preview is recomputed in the chosen format")
        } else {
            XCTAssertFalse(app.buttons["export-share"].isEnabled,
                "an empty export cannot be shared")
        }
        app.buttons["export-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        SurfaceTest.menuEntry(app, "Adicionar feed")
        XCTAssertTrue(app.navigationBars["Adicionar fontes"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.textFields["add-feed-input"].exists)
        app.buttons["add-feed-cancel"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
    }
}
