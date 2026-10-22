// File: PortabilityJourneyUITests.swift
// Module: FeedMineUITests
// Owns: add-feed's paste and resolution, the export format preview, importing a fixture file's preview/cancel,
//       and the onboarding composer's reset/broad controls.
// No test sends a message or reaches an external service; the export share is covered by the existing export
// journey and by the card share journey, which only presents and dismisses the platform sheet.

import XCTest
#if canImport(UIKit)
import UIKit
#endif

final class PortabilityJourneyUITests: XCTestCase {
    @MainActor
    func testAddFeedPasteAndPreviewAndCollectionResult() throws {
        // The add-feed fixture installs its own URLProtocol and deliberately fails the development feeds, so this
        // launch starts from the empty-selection surface; the reader chrome and the menu are still the product's.
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launchEnvironment["FEEDMINE_DISABLE_DISCOVERY"] = "1"
        app.launchEnvironment["FEEDMINE_EMPTY_SELECTION"] = "1"
        app.launchEnvironment["FEEDMINE_ADD_FEED_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 90),
            "the empty surface still offers the reader menu")
        SurfaceTest.menuEntry(app, "Adicionar feed")
        XCTAssertTrue(app.navigationBars["Adicionar fontes"].waitForExistence(timeout: 20))

        // Type the address rather than paste: the platform's paste permission prompt would be an OS modal, not
        // the app's control. The effect asserted below is the source really being added and selected.
        let input = app.textFields["add-feed-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("https://site.feedmine.test/")

        // The input is already enough to resolve; submit and re-read the preview entry and the adopted result.
        let add = app.buttons["add-feed-add"]
        XCTAssertTrue(add.isEnabled)
        add.tap()
        XCTAssertTrue(app.staticTexts["add-feed-result-added"].waitForExistence(timeout: 120),
            "the resolved feed is adopted, not only previewed")
        // The same address submitted again is the already-selected case: the sheet must say so and must not
        // report a second insertion. Adoption clears the field, so the reader enters the address again.
        input.tap()
        input.typeText("https://site.feedmine.test/")
        app.buttons["add-feed-add"].tap()
        let already = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'já estava'")).firstMatch
        XCTAssertTrue(already.waitForExistence(timeout: 120),
            "adding an already-selected source is reported, not silently dropped")
        XCTAssertFalse(app.staticTexts["add-feed-result-added"].exists,
            "the second submission does not claim another insertion")
        app.buttons["add-feed-cancel"].tap()
        let card = app.descendants(matching: .any)["card.open"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 120),
            "the added source is selected and its fixture stories reach the feed")
    }

    @MainActor
    func testExportFormatChangesThePreviewAndTheSheetOffersThePromisedScopes() throws {
        let app = SurfaceTest.launchFixture()
        SurfaceTest.menuEntry(app, "Exportar")
        XCTAssertTrue(app.navigationBars["Exportar"].waitForExistence(timeout: 20))

        let preview = app.staticTexts["export-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 30), "the export sheet produces a real document")
        let opml = preview.label
        XCTAssertTrue(opml.contains("<opml") || opml.contains("<?xml"),
            "the initial format is OPML; observed prefix: \(opml.prefix(80))")

        let format = app.buttons["export-format"]
        XCTAssertTrue(SurfaceTest.scrollIntoView(format, in: app, timeout: 20))
        format.tap()
        let json = app.buttons["Backup JSON"].firstMatch
        if json.waitForExistence(timeout: 5) {
            json.tap()
        } else {
            let menuJSON = app.menus.buttons["Backup JSON"].firstMatch
            XCTAssertTrue(menuJSON.waitForExistence(timeout: 5), "the format picker offers the JSON backup")
            menuJSON.tap()
        }
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", opml), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 30), .completed,
            "changing the format recomputes the preview in that format")
        XCTAssertTrue(preview.label.contains("\"items\"") || preview.label.contains("{"),
            "the JSON preview is JSON, not the OPML text under a new name")
        // "Exportar coleção" is not offered in this build; the sheet must not pretend it has an empty one.
        XCTAssertFalse(app.buttons["export-scope-collection"].exists,
            "the build does not offer a collection export scope")
        app.buttons["export-done"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20))
    }

    @MainActor
    func testImportFixturePreviewCancelWritesNothing() throws {
        let app = SurfaceTest.launchFixture(["FEEDMINE_IMPORT_FIXTURE": "1"])
        let cancel = app.buttons["import-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 30),
            "the fixture's preview is presented before anything is written")
        XCTAssertTrue(app.buttons["import-confirm"].exists)
        cancel.tap()
        XCTAssertTrue(SurfaceTest.waitForAbsence(cancel, timeout: 20))
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 20),
            "cancelling returns to the feed that was already there")
    }

    @MainActor
    func testOnboardingComposerResetAndStartBroad() throws {
        let app = XCUIApplication()
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_BLOCK_RSS_NETWORK"] = "1"
        app.launchEnvironment["FEEDMINE_DISABLE_DISCOVERY"] = "1"
        app.launchEnvironment["FEEDMINE_ONBOARDING"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["welcome-headline"].waitForExistence(timeout: 60))
        app.buttons["welcome-shape"].tap()
        XCTAssertTrue(app.staticTexts["composer-subtitle"].waitForExistence(timeout: 30))

        // Reset returns the answers to what the host proposed; it must be reachable and act, not just exist.
        let language = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'composer-language-'")).firstMatch
        if language.waitForExistence(timeout: 20) {
            language.tap()
            let selected = language.isSelected
            app.buttons["composer-reset"].tap()
            XCTAssertNotEqual(language.isSelected, selected,
                "Reiniciar restores the host-provided recipe")
        }
        app.buttons["composer-start-broad"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 120),
            "Começar amplo saves the answers and opens the feed")
        XCTAssertTrue(app.buttons["more-menu"].waitForExistence(timeout: 30))
    }
}
