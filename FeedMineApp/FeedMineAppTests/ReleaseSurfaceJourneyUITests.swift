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

        // Settings: one stored option, read back after closing and reopening the sheet.
        SurfaceTest.menuEntry(app, "Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 30))
        let night = app.switches["settings-night-mode"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(night, in: app, timeout: 30))
        let before = night.value as? String
        night.tap()
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
        country.tap()
        XCTAssertTrue(SurfaceTest.waitForValue(country, differentFrom: countryBefore, timeout: 60))
        app.buttons["countries-done"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 30))
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        let proof = XCTAttachment(string: "release-night=\(after ?? "nil") country=\(country.identifier) "
            + "countryBefore=\(countryBefore ?? "nil")")
        proof.name = "release-surface-journey"
        proof.lifetime = .keepAlways
        add(proof)
    }
}
