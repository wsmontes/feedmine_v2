import XCTest
import Foundation
import FeedMineRuntime
import FeedMineDomain

/// Round 9 (the PO's round-8 verdict): the language list offers one row per language. The catalogue's regional
/// codes stay — as counts under the language. The defect was 257 rows labelled by their primary subtag, three of
/// them called "English", each with a different number beside it.
final class CatalogLanguageGroupingTests: XCTestCase {
    private static let portuguese = Locale(identifier: "pt-BR")

    private func summary(_ code: String, _ total: Int, enabled: Int? = nil,
        in locale: Locale = CatalogLanguageGroupingTests.portuguese) -> CatalogLanguageSummary {
        CatalogLanguageSummary(code: code,
            displayName: CatalogLanguageNaming.displayName(forLanguageCode: code, in: locale),
            regionName: CatalogLanguageNaming.regionName(forLanguageCode: code, in: locale),
            enabledSources: enabled ?? total, totalSources: total,
            isUndeclared: ReaderLanguageCode.isUndeclared(code))
    }

    /// The catalogue's own order, as `languages()` returns it: biggest first, the undeclared bucket last. The
    /// counts are the shipped snapshot's.
    private func catalogue() -> [CatalogLanguageSummary] {
        [summary("en", 17_971), summary("pt", 1_125), summary("en-US", 7_028),
         summary("pt-BR", 936), summary("en-GB", 1_013), summary("und", 27_741)]
    }

    func testGroupsSumTheirVariantsAndKeepEveryCodeAsInformation() throws {
        let groups = CatalogLanguageGroup.groups(catalogue())
        XCTAssertEqual(groups.map(\.languageCode), ["en", "pt", "und"],
            "one row per language, biggest first, the undeclared bucket last")
        let english = try XCTUnwrap(groups.first)
        XCTAssertEqual(english.displayName, "Inglês")
        XCTAssertEqual(english.availableSources, 26_012, "en 17.971 + en-US 7.028 + en-GB 1.013")
        XCTAssertEqual(english.enabledSources, 26_012)
        XCTAssertEqual(english.variants.map(\.code), ["en", "en-US", "en-GB"])
        XCTAssertEqual(english.variants.map(\.totalSources), [17_971, 7_028, 1_013])
        XCTAssertTrue(english.hasRegionVariants)

        let portuguese = try XCTUnwrap(groups.first { $0.languageCode == "pt" })
        XCTAssertEqual(portuguese.availableSources, 2_061)
        XCTAssertEqual(portuguese.variants.map(\.variantLabel), ["Português", "Português (Brasil)"])

        XCTAssertTrue(try XCTUnwrap(groups.last).isUndeclared, "the bucket is never a choice")
        XCTAssertFalse(english.isUndeclared)
    }

    /// A language the catalogue declares once has nothing to expand.
    func testALanguageWithoutRegionsHasNoVariantsToShow() throws {
        let groups = CatalogLanguageGroup.groups([summary("ja", 427)])
        let japanese = try XCTUnwrap(groups.first)
        XCTAssertEqual(japanese.variants.map(\.code), ["ja"])
        XCTAssertFalse(japanese.hasRegionVariants)
        XCTAssertFalse(try XCTUnwrap(japanese.variants.first).hasRegion)
    }

    func testNoTwoRowsShareAVisibleLabelInEitherInterfaceLanguage() {
        for locale in [CatalogLanguageGroupingTests.portuguese, Locale(identifier: "en")] {
            let labels = CatalogLanguageGroup.groups(catalogue())
                .map { CatalogLanguageNaming.displayName(forLanguageCode: $0.languageCode, in: locale) }
            XCTAssertEqual(Set(labels).count, labels.count,
                "two rows a reader cannot tell apart are the defect: \(labels)")
            XCTAssertFalse(labels.contains(""), "a row always has a name")
        }
    }

    func testLanguageAndRegionNamesComeFromTheInterfaceLanguage() {
        let portuguese = CatalogLanguageGroupingTests.portuguese
        XCTAssertEqual(CatalogLanguageNaming.displayName(forLanguageCode: "en", in: portuguese), "Inglês")
        XCTAssertEqual(CatalogLanguageNaming.displayName(forLanguageCode: "en-US", in: portuguese), "Inglês",
            "a regional code names the same language")
        XCTAssertEqual(CatalogLanguageNaming.regionName(forLanguageCode: "en-US", in: portuguese), "Estados Unidos")
        XCTAssertNil(CatalogLanguageNaming.regionName(forLanguageCode: "en", in: portuguese),
            "a code without a region names no region")
        XCTAssertEqual(CatalogLanguageNaming.displayName(forLanguageCode: "pt-BR", in: Locale(identifier: "en")),
            "Portuguese")
        XCTAssertEqual(CatalogLanguageNaming.displayName(forLanguageCode: "und", in: Locale(identifier: "en")),
            "Idioma não declarado", "an undeclared bucket says so instead of pretending")
        XCTAssertEqual(CatalogLanguageNaming.displayName(forLanguageCode: "  ", in: Locale(identifier: "en")),
            "Idioma não declarado")
    }

    /// A country is named in the interface language, from the catalogue's own English name; a name the reversal
    /// cannot place keeps the catalogue's own instead of inventing one.
    func testCountryNamesFollowTheInterfaceLanguage() {
        XCTAssertEqual(CatalogRegionNaming.localizedName("South Africa", in: CatalogLanguageGroupingTests.portuguese),
            "África do Sul")
        XCTAssertEqual(CatalogRegionNaming.localizedName("Costa Rica", in: CatalogLanguageGroupingTests.portuguese),
            "Costa Rica")
        XCTAssertEqual(CatalogRegionNaming.localizedName("Brazil", in: Locale(identifier: "en")), "Brazil")
        XCTAssertEqual(CatalogRegionNaming.localizedName("Nowhere Land", in: CatalogLanguageGroupingTests.portuguese),
            "Nowhere Land")
        XCTAssertNil(CatalogRegionNaming.regionCode(forCatalogueName: "Nowhere Land"))
    }

    func testCountsAreGroupedTheWayTheInterfaceLanguageWritesNumbers() {
        XCTAssertEqual(CatalogLanguageNaming.numberLabel(26_012, in: CatalogLanguageGroupingTests.portuguese),
            "26.012")
        XCTAssertEqual(CatalogLanguageNaming.numberLabel(26_012, in: Locale(identifier: "en")), "26,012")
    }
}
