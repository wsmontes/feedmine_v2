// File: CuratedFeedJourneyUITests.swift
// Module: FeedMineUITests
// Owns: creating a curated feed through the published controls, and the destructive deletion path that must
//       confirm, allow cancelling, and actually remove the preset.
// Does not own: the reader host or its presentation (another owner).

import XCTest

final class CuratedFeedJourneyUITests: XCTestCase {
    /// G4: "Excluir feed curado" promised a confirmation and then removal; the old host mapped it to a generic
    /// error alert with only OK. The test cancels once (the preset must stay) and deletes once (it must go).
    @MainActor
    func testDeleteCuratedFeedConfirmsCancelsAndRemovesThePreset() throws {
        let app = SurfaceTest.launchFixture()
        let name = "Curado \(UUID().uuidString.prefix(6))"
        try createCuratedFeed(named: name, in: app)

        // The curated feed is active: its preset chip is the durable proof of the context.
        let chip = app.buttons["lens-chip-preset"]
        XCTAssertTrue(chip.waitForExistence(timeout: 30), "the newly opened curated feed is the active preset")

        SurfaceTest.menuEntry(app, "Excluir feed curado")
        let alert = app.alerts["Excluir feed curado"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15),
            "the destructive entry asks the reader to confirm the actual action")
        XCTAssertTrue(alert.buttons["Cancelar"].exists, "cancelling is offered")
        alert.buttons["Cancelar"].tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "cancelling preserves the curated feed")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))

        SurfaceTest.menuEntry(app, "Excluir feed curado")
        XCTAssertTrue(app.alerts["Excluir feed curado"].waitForExistence(timeout: 15))
        app.alerts["Excluir feed curado"].buttons["Excluir"].tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(chip, timeout: 30),
            "confirming removes the curated context the reader was on")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30),
            "the reader lands on the plain feed, not on a dead context")

        // Durable result: the preset is gone from the filter sheet, not only from the lens.
        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 20))
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertFalse(SurfaceTest.scrollIntoView(row, in: app, timeout: 10),
            "the deleted curated feed is no longer offered as a preset")
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))

        let proof = XCTAttachment(string: "curated=\(name) cancel-preserved=true delete-removed=true")
        proof.name = "curated-deletion"
        proof.lifetime = .keepAlways
        add(proof)
    }

    /// The hood's rename is the other half of the same menu: it must change what the header/preset says and
    /// survive closing and reopening the surface.
    @MainActor
    func testCuratedHoodRenamesTheFeedAndKeepsIt() throws {
        let app = SurfaceTest.launchFixture()
        let name = "Curado \(UUID().uuidString.prefix(6))"
        let renamed = "Renomeado \(UUID().uuidString.prefix(6))"
        try createCuratedFeed(named: name, in: app)

        SurfaceTest.menuEntry(app, "Abrir o capô do feed curado")
        XCTAssertTrue(app.navigationBars["Feed curado"].waitForExistence(timeout: 20))
        let field = app.textFields["hood-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        SurfaceTest.replaceText(field, with: renamed)
        app.buttons["hood-save"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))

        SurfaceTest.menuEntry(app, "Abrir o capô do feed curado")
        XCTAssertTrue(app.navigationBars["Feed curado"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.textFields["hood-name"].value as? String, renamed,
            "the renamed curated feed is what the hood reads after reopening")
        app.buttons["hood-close"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
    }

    /// Creates and opens a curated feed through Settings → discovery preferences. The surface states that creating
    /// does not activate; opening is the explicit second action this function takes.
    @MainActor
    private func createCuratedFeed(named name: String, in app: XCUIApplication) throws {
        SurfaceTest.menuEntry(app, "Ajustes")
        XCTAssertTrue(app.navigationBars["Ajustes"].waitForExistence(timeout: 20))
        let discovery = app.buttons["settings-discovery-preferences"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(discovery, in: app, timeout: 20),
            "the settings page offers discovery preferences")
        discovery.tap()
        XCTAssertTrue(app.navigationBars["Preferências de descoberta"].waitForExistence(timeout: 20))

        let nameField = app.textFields["discovery-feed-name"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(nameField, in: app, timeout: 20))
        nameField.tap()
        nameField.typeText(name)
        let create = app.buttons["discovery-create-feed"]
        XCTAssertTrue(create.isEnabled, "a non-empty name enables creation")
        create.tap()
        let open = app.buttons["discovery-open-created-feed"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "creating a feed offers the way to open it")
        open.tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 60),
            "opening the created feed returns to the reader")
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 30))
    }

    /// B5: the published "Criar feed curado" entry must create a curated preset from its own composer and must
    /// not activate it. The preset is then offered in the filter sheet.
    @MainActor
    func testCreateCuratedFromMenuCreatesButDoesNotActivate() throws {
        let app = SurfaceTest.launchFixture()
        SurfaceTest.menuEntry(app, "Criar feed curado")
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 30),
            "the curated entry opens the composer, not the first-run welcome")
        let primary = app.buttons["composer-open-feed"]
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        XCTAssertEqual(primary.label, "Salvar feed curado",
            "the primary action names saving, not opening")
        primary.tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 60),
            "saving the composer returns to the feed")
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["lens-chip-preset"].exists,
            "creating a curated feed must not activate it")

        app.buttons["filter-button"].tap()
        XCTAssertTrue(app.navigationBars["Filtros"].waitForExistence(timeout: 20))
        let created = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Meu feed curado")).firstMatch
        XCTAssertTrue(SurfaceTest.scrollIntoView(created, in: app, timeout: 20),
            "the created curated feed is offered as a preset")
        app.buttons["filter-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
    }
}
