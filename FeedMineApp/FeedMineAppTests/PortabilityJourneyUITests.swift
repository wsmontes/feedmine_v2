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
        #if canImport(UIKit)
        UIPasteboard.general.string = "https://site.feedmine.test/"
        #endif
        let app = SurfaceTest.launchFixture(["FEEDMINE_ADD_FEED_FIXTURE": "1"])
        SurfaceTest.menuEntry(app, "Adicionar feed")
        XCTAssertTrue(app.navigationBars["Adicionar fontes"].waitForExistence(timeout: 20))

        app.buttons["add-feed-paste"].tap()
        let input = app.textFields["add-feed-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "https://site.feedmine.test/",
            "Colar da área de transferência really reads the clipboard into the field")

        // The input is already enough to resolve; submit and re-read the preview entry and the adopted result.
        let add = app.buttons["add-feed-add"]
        XCTAssertTrue(add.isEnabled)
        add.tap()
        let preview = app.descendants(matching: .any)["add-feed-preview-entry"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 60), "the address resolves into a feed preview")
        XCTAssertTrue(app.staticTexts["add-feed-result-added"].waitForExistence(timeout: 60),
            "the resolved feed is adopted, not only previewed")
        app.buttons["add-feed-cancel"].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 30))
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
        let json = app.buttons["JSON"].firstMatch
        if json.waitForExistence(timeout: 5) {
            json.tap()
        } else {
            let menuJSON = app.menus.buttons["JSON"].firstMatch
            XCTAssertTrue(menuJSON.waitForExistence(timeout: 5), "the format picker offers JSON")
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
