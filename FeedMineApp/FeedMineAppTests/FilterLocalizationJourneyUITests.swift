//
// File: FilterLocalizationJourneyUITests.swift
// Module: FeedMineUITests
//
// The fix's claim on the device: the filter surfaces say what the reader reads, in the interface's language, while
// the identity each row persists stays the raw value V1 named (`All`, `Serious`, …). The package-level
// `LocalizationCoverageTests` pins the strings; what it cannot see is a sheet drawn by the app in a device language.
//
// The journey launches the same sheet twice — English and Portuguese — and asserts the *same identifiers* with
// *different labels*. That pairing is the proof: a display name that followed the identifier would read the same in
// both runs.
//
// What this build does not offer, and therefore cannot be asserted here: the content-type section. Its criterion is
// not in `ReaderFilterCriterion.enforceable` (`[.preset, .languages, .mood]`) and the sheet does not draw a section
// it cannot enforce (T6's honesty rule), so `Articles`/`Videos`/… are never on screen; only the preset and mood
// rows carry the translated display names. The identifiers this test prints are the evidence of what was there.
import XCTest

@MainActor
final class FilterLocalizationJourneyUITests: XCTestCase {

    func testFilterSheetSpeaksTheInterfaceLanguageWhileItsIdentitiesStayRaw() throws {
        let english = try openSheet(language: "en", locale: "en_US")
        XCTAssertTrue(english.navigationBars["Filters"].waitForExistence(timeout: 20),
            "the sheet's own title follows the interface language")
        let englishClearAll = english.buttons["filter-clear-all"].label
        XCTAssertEqual(englishClearAll, "Clear all filters", "the sheet's first control is translated")
        XCTAssertEqual(english.staticTexts["Feeds"].label, "Feeds", "the preset section is named in English")
        XCTAssertEqual(english.staticTexts["Language"].label, "Language", "the language section is named in English")

        // What the build does not draw: the content-type criterion is not enforceable, so the sheet does not offer
        // it — and the display names for it (`Articles`, `Videos`, …) cannot be reached on any screen. Asked while
        // the sections around its place in the list are on screen (the Language header is), so an absence here is
        // an absence of the section, not of a scrolled-away row.
        XCTAssertFalse(english.buttons["content-type-text"].exists,
            "content type is not an offered criterion in this build")
        XCTAssertFalse(english.staticTexts["Articles"].exists,
            "and its display names are therefore not on screen either")

        // The preset rows: identifier carries the preset's identity, label is the display name.
        let everything = english.buttons["preset-option-everything"]
        XCTAssertTrue(everything.waitForExistence(timeout: 10), "the preset row exists by its identity")
        XCTAssertEqual(everything.identifier, "preset-option-everything",
            "the identifier carries the identity, not the words")
        XCTAssertEqual(everything.label, "Everything",
            "the display name is translated: `Tudo` is the stored key, `Everything` is what the reader reads")
        let lastOpened = english.buttons["preset-option-lastClicked"].label
        XCTAssertEqual(lastOpened, "Last opened")
        print("FILTER_SHEET_EN clearAll=\"\(englishClearAll)\" everything=\"\(everything.label)\" lastOpened=\"\(lastOpened)\"")

        // Moods are the other criterion this build enforces, and the strongest case: `All` is the raw value, so a
        // label of `Everything` can only come from the translation — the identifier still says `mood-all`.
        let moodAll = english.buttons["mood-all"]
        XCTAssertTrue(scrollIntoView(moodAll, in: english, within: 40), "the mood rows are in the sheet")
        XCTAssertEqual(moodAll.identifier, "mood-all")
        XCTAssertEqual(moodAll.label, "Everything", "`All` reads `Everything`")
        var englishMoods = ["\(moodAll.identifier)=\"\(moodAll.label)\""]

        // The identity is what the control persists and announces: `mood-serious` is addressed by the raw `Serious`,
        // and its state is stated in English too.
        let serious = english.buttons["mood-serious"]
        XCTAssertTrue(scrollIntoView(serious, in: english, within: 20))
        XCTAssertEqual(serious.label, "Serious")
        englishMoods.append("\(serious.identifier)=\"\(serious.label)\"")
        serious.tap()
        XCTAssertEqual(serious.value as? String, "selected", "the state is translated: `selecionado` is the pt-BR word")
        for (identifier, label) in [("mood-fun", "Fun"), ("mood-technical", "Technical"),
                                    ("mood-inspiring", "Inspiring")] {
            let row = english.buttons[identifier]
            XCTAssertTrue(scrollIntoView(row, in: english, within: 20), "\(identifier) is in the sheet")
            XCTAssertEqual(row.label, label)
            englishMoods.append("\(row.identifier)=\"\(row.label)\"")
        }
        print("FILTER_SHEET_EN_MOODS \(englishMoods) state=\(serious.value ?? "nil") done=\"\(english.buttons["filter-done"].label)\"")
        attach(english, "filter-sheet-en")
        english.terminate()

        // The same sheet, in the device language the catalogue's keys are written in. Same identifiers, other words.
        let portuguese = try openSheet(language: "pt-BR", locale: "pt_BR")
        XCTAssertTrue(portuguese.navigationBars["Filtros"].waitForExistence(timeout: 20))
        XCTAssertEqual(portuguese.buttons["preset-option-everything"].identifier, "preset-option-everything",
            "the identity does not follow the language")
        XCTAssertEqual(portuguese.buttons["preset-option-everything"].label, "Tudo",
            "the same row reads `Tudo`: the label is the translated one")
        let portugueseClearAll = portuguese.buttons["filter-clear-all"].label
        XCTAssertEqual(portugueseClearAll, "Limpar todos os filtros", "the sheet's own control is Portuguese too")
        XCTAssertEqual(portuguese.staticTexts["Idioma"].label, "Idioma", "the language section is named in Portuguese")
        let ptMoodAll = portuguese.buttons["mood-all"]
        XCTAssertTrue(scrollIntoView(ptMoodAll, in: portuguese, within: 40))
        XCTAssertEqual(ptMoodAll.identifier, "mood-all", "the same identity in both runs")
        XCTAssertEqual(ptMoodAll.label, "Tudo", "and the other language's word for it")
        let ptSerious = portuguese.buttons["mood-serious"]
        XCTAssertTrue(scrollIntoView(ptSerious, in: portuguese, within: 20))
        XCTAssertEqual(ptSerious.label, "Sério")
        print("FILTER_SHEET_PT clearAll=\"\(portugueseClearAll)\" everything=\"Tudo\" moodAll=\"\(ptMoodAll.label)\" serious=\"\(ptSerious.label)\"")
        attach(portuguese, "filter-sheet-pt-br")
        print("FILTER_SHEET_IDENTITIES identical: preset-option-everything / mood-all / mood-serious")
    }

    // MARK: - Navigation

    private func openSheet(language: String, locale: String) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchEnvironment["FEEDMINE_RUNTIME_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_LOCAL_FEEDS"] = "1"
        app.launchEnvironment["FEEDMINE_SKIP_ONBOARDING"] = "1"
        app.launch()
        let filter = app.buttons["filter-button"]
        XCTAssertTrue(filter.waitForExistence(timeout: 120), "the reader's chrome is up")
        filter.tap()
        XCTAssertTrue(app.buttons["filter-done"].waitForExistence(timeout: 30), "the filter sheet opens")
        return app
    }

    /// A row of the sheet is not in the tree until it has been scrolled into it: the language section alone holds
    /// 257 rows, and the mood rows sit below them.
    @discardableResult
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication,
        within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if element.exists && element.isHittable { return true }
            let table = app.tables.firstMatch
            if table.exists { table.swipeUp() } else { app.swipeUp() }
        }
        return element.exists
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
