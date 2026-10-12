import XCTest
import FeedMineUI
import FeedMineRuntime
import FeedMineDomain

/// Round 9: the surfaces that offer a language agree about what a row *is* — the language — and a selection
/// stored with a regional code still shows the language it belongs to, instead of showing every row unselected
/// while the filter still filters.
@MainActor
final class LanguageSurfaceTests: XCTestCase {
    private let groups = CatalogLanguageGroup.groups([
        CatalogLanguageSummary(code: "en", displayName: "English", regionName: nil,
            enabledSources: 17_971, totalSources: 17_971, isUndeclared: false),
        CatalogLanguageSummary(code: "en-US", displayName: "English", regionName: "United States",
            enabledSources: 7_028, totalSources: 7_028, isUndeclared: false),
        CatalogLanguageSummary(code: "und", displayName: "Idioma não declarado", regionName: nil,
            enabledSources: 0, totalSources: 27_741, isUndeclared: true)
    ])

    func testFilterRowsAreOnePerLanguageAndCountWhatTheCatalogueHolds() throws {
        let rows = FilterSheetView.languageRows(groups, selected: [])
        XCTAssertEqual(rows.map(\.code), ["en", "und"], "one row per language, in the catalogue's order")
        let english = try XCTUnwrap(rows.first)
        XCTAssertEqual(english.availableSources, 24_999, "the row counts the language, not one of its codes")
        XCTAssertEqual(english.variants.map(\.code), ["en", "en-US"], "the codes are the expansion's information")
        XCTAssertEqual(english.variants.map(\.availableSources), [17_971, 7_028])
        XCTAssertTrue(english.hasVariants)
        XCTAssertEqual(Set(rows.map(\.name)).count, rows.count, "two rows must never read the same")
        XCTAssertFalse(rows.contains { $0.name.isEmpty })
    }

    /// The old sheet wrote the catalogue's own code, so a stored filter can hold `en-US`. It is the language, and
    /// the row has to say so: an unselected row over a filter that still filters is the defect being fixed.
    func testALegacyRegionalSelectionShowsAsItsLanguage() throws {
        let rows = FilterSheetView.languageRows(groups, selected: ["en-US"])
        let english = try XCTUnwrap(rows.first { $0.code == "en" })
        XCTAssertTrue(english.isSelected)
        XCTAssertEqual(rows.map(\.code), ["en", "und"], "a regional code never becomes a row of its own")
        XCTAssertFalse(try XCTUnwrap(rows.last).isSelected)
    }

    func testTogglingStoresTheLanguageAndNotTheCatalogueCode() throws {
        var draft = ReaderFilterDraft(applying: ReaderFilter())
        draft.toggleLanguage("en-US")
        XCTAssertEqual(draft.languages, ["en"], "the draft holds the same choice the row shows")
        let rows = FilterSheetView.languageRows(groups, selected: draft.languages)
        XCTAssertEqual(rows.first { $0.code == "en" }?.isSelected, true)
        XCTAssertNil(rows.first { $0.code == "en-US" }, "there is no control for a region")
    }

    /// The onboarding value type never shows a code, and a recipe that already named `pt-BR` is the language it
    /// belongs to.
    func testOnboardingLanguageNeverShowsACode() {
        let language = OnboardingLanguage(recipeCode: "pt-BR")
        XCTAssertEqual(language.code, "pt")
        XCTAssertNotEqual(language.name, language.code)
        XCTAssertFalse(language.name.isEmpty)
        XCTAssertEqual(OnboardingLanguage(recipeCode: "und").name, "Idioma não declarado")
    }

    /// The expansion is information: the row's own identity is the language, so a variant cannot be selected as
    /// if it were a narrower filter.
    func testVariantsAreInformationAndCarryCounts() throws {
        let rows = FilterSheetView.languageRows(groups, selected: [])
        let english = try XCTUnwrap(rows.first)
        XCTAssertEqual(english.code, "en")
        XCTAssertFalse(english.variants.contains { $0.code == english.code && $0.hasRegion })
        let regional = try XCTUnwrap(english.variants.first { $0.code == "en-US" })
        XCTAssertEqual(regional.label, "English (United States)")
        XCTAssertTrue(regional.hasRegion)
        XCTAssertEqual(regional.availableSources, 7_028)
        XCTAssertEqual(english.variants.first?.hasRegion, false, "the language itself names no region")
    }
}
