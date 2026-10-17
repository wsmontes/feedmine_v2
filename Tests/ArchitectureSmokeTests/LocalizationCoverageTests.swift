import XCTest
import Foundation
import FeedMineDomain
import FeedMineUI

/// The reader-facing strings of the four surfaces the localisation audit measured — the end-of-feed block, the
/// reading surface, the filter controls and the failed-feed copy — resolve in **both** shipped localisations, and
/// no surface renders a persisted enum raw value or a bare Portuguese literal.
///
/// The catalogue is read from the app target's own `Localizable.xcstrings`, not from a copy: deleting a key or
/// dropping a localisation fails here even while every call site still compiles. The compiled-table check matters
/// because `xcstringstool` silently omits entries whose `state` is `new`, which is exactly how a "translated"
/// entry can exist in the source file and be missing at runtime.
final class LocalizationCoverageTests: XCTestCase {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ArchitectureSmokeTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
    }

    /// Every key this slice owns, with the text each localisation must produce. `pt-BR` is the source language, so
    /// its value equals the key — asserted explicitly, because a missing source entry looks correct at runtime.
    private static let ownedStrings: [(key: String, pt: String, en: String)] = [
        ("Você chegou ao fim das histórias disponíveis para sua seleção.",
            "Você chegou ao fim das histórias disponíveis para sua seleção.",
            "You've reached the end of the stories available for your selection."),
        ("Explore outros assuntos", "Explore outros assuntos", "Explore other topics"),
        ("Ampliar fontes", "Ampliar fontes", "Widen your sources"),
        ("Voltar ao início", "Voltar ao início", "Back to the start"),
        ("Conteúdo parcial: o artigo completo está no site.",
            "Conteúdo parcial: o artigo completo está no site.",
            "Partial content: the full article is on the site."),
        ("Abrir no site", "Abrir no site", "Open on site"),
        ("Tudo", "Tudo", "Everything"),
        ("Artigos", "Artigos", "Articles"),
        ("Vídeos", "Vídeos", "Videos"),
        ("Podcasts", "Podcasts", "Podcasts"),
        ("Fóruns", "Fóruns", "Forums"),
        ("Sério", "Sério", "Serious"),
        ("Divertido", "Divertido", "Fun"),
        ("Técnico", "Técnico", "Technical"),
        ("Inspirador", "Inspirador", "Inspiring"),
        ("Falha ao atualizar o feed", "Falha ao atualizar o feed", "Couldn't refresh the feed"),
        ("Não foi possível abrir o feed local.", "Não foi possível abrir o feed local.",
            "Couldn't open the local feed."),
        ("bookmarked", "salvo", "bookmarked"),
        ("not bookmarked", "não salvo", "not bookmarked"),
        ("selected", "selecionado", "selected"),
        ("not selected", "não selecionado", "not selected")
    ]

    private func catalogueStrings() throws -> [String: Any] {
        let url = Self.repositoryRoot.appendingPathComponent("FeedMineApp/FeedMineApp/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any], "catalogue is JSON")
        XCTAssertEqual(root["sourceLanguage"] as? String, "pt-BR", "the source language is the product's own")
        return try XCTUnwrap(root["strings"] as? [String: Any], "the catalogue has a strings table")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - The catalogue

    func testEveryOwnedKeyResolvesInBothLocalisations() throws {
        let strings = try catalogueStrings()
        for entry in Self.ownedStrings {
            let localizations = try XCTUnwrap((strings[entry.key] as? [String: Any])?["localizations"] as? [String: Any],
                "missing catalogue key: \(entry.key)")
            for (language, expected) in [("pt-BR", entry.pt), ("en", entry.en)] {
                let unit = try XCTUnwrap((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any],
                    "\(entry.key) has no \(language) localisation")
                XCTAssertEqual(unit["value"] as? String, expected, "\(language) value of \(entry.key)")
                // `new` entries are dropped by `xcstringstool compile`: the key would exist in the source file and
                // be absent from the .strings the app loads. The value then falls back to the key, which for a
                // Portuguese key hides the defect and for an English key ships untranslated Portuguese.
                XCTAssertEqual(unit["state"] as? String, "translated",
                    "\(entry.key) must be a compiled \(language) entry, not \(unit["state"] ?? "missing")")
            }
        }
    }

    // MARK: - Filter controls

    /// The reader reads a translated label; what a stored filter holds is V1's raw value, unchanged.
    ///
    /// The test bundle carries no catalogue, so `String(localized:)` returns the key — the source language, which
    /// is what the same key resolves to for a pt-BR reader. That makes the expectation exact here: a label that
    /// fell back to the raw value (`All`, `Serious`) would not match the key.
    func testFilterLabelsAreTranslatedWhilePersistedValuesStayV1s() throws {
        let contentTypes: [(type: ReaderContentType, raw: String, label: String)] = [
            (.all, "All", "Tudo"),
            (.text, "Articles", "Artigos"),
            (.video, "Videos", "Vídeos"),
            (.audio, "Podcasts", "Podcasts"),
            (.forum, "Forums", "Fóruns")
        ]
        XCTAssertEqual(ReaderContentType.allCases, contentTypes.map(\.type))
        for expected in contentTypes {
            XCTAssertEqual(expected.type.rawValue, expected.raw, "the persisted identity is V1's, verbatim")
            XCTAssertEqual(expected.type.displayName, expected.label, "the drawn label is the catalogue key")
        }

        let moods: [(mood: ReaderMood, raw: String, label: String)] = [
            (.all, "All", "Tudo"),
            (.serious, "Serious", "Sério"),
            (.fun, "Fun", "Divertido"),
            (.technical, "Technical", "Técnico"),
            (.inspiring, "Inspiring", "Inspirador")
        ]
        XCTAssertEqual(ReaderMood.allCases, moods.map(\.mood))
        for expected in moods {
            XCTAssertEqual(expected.mood.rawValue, expected.raw)
            XCTAssertEqual(expected.mood.displayName, expected.label, "the drawn label is the catalogue key")
            XCTAssertNotEqual(expected.mood.displayName, expected.raw, "mood \(expected.raw) is never its label")
        }

        // What is persisted did not move: a filter written by this build, and a legacy filter read by it, still
        // carry the raw values — the translation is display-only.
        let filter = ReaderFilter(contentType: .text, mood: .serious)
        let json = try XCTUnwrap(String(data: try JSONEncoder().encode(filter), encoding: .utf8))
        XCTAssertTrue(json.contains("\"Articles\""), json)
        XCTAssertTrue(json.contains("\"Serious\""), json)
        XCTAssertEqual(ReaderContentType(rawValue: "Articles"), .text)
        XCTAssertEqual(ReaderMood(rawValue: "Serious"), .serious)
    }

    func testLensChipsCarryTheTranslatedCriterionNotItsRawValue() throws {
        let filter = ReaderFilter(contentType: .text, mood: .fun)
        let chips = ReaderFilterLens.chips(filter: filter, preset: .everything)
        XCTAssertEqual(chips.map(\.kind), [.contentType, .mood], "one chip per active criterion, V1's order")
        XCTAssertEqual(chips[0].label, "Artigos")
        XCTAssertEqual(chips[1].label, "Divertido")
        XCTAssertEqual(chips[0].removal, .contentType)
        XCTAssertEqual(chips[1].removal, .mood)
    }

    // MARK: - The surfaces themselves

    /// A key in the catalogue does not help a call site that passes a bare literal to a verbatim API
    /// (`accessibilityValue`, `accessibilityLabel`) or that draws an enum's raw value.
    func testSurfacesResolveTheirCopyThroughTheCatalogue() throws {
        let end = try source("Sources/FeedMineUI/FeedEndOfContentView.swift")
        for key in ["Você chegou ao fim das histórias disponíveis para sua seleção.", "Explore outros assuntos",
            "Ampliar fontes", "Voltar ao início"] {
            XCTAssertTrue(end.contains("String(localized: \"\(key)\")"), "end-of-feed copy is localised: \(key)")
        }

        let reading = try source("Sources/FeedMineUI/Reader/FeedReadingSurface.swift")
        XCTAssertTrue(reading.contains("Text(\"Conteúdo parcial: o artigo completo está no site.\")"),
            "the partial-content sentence is a catalogue key")
        XCTAssertTrue(reading.contains("Text(\"Abrir no site\")"), "the footer action is a catalogue key")
        XCTAssertTrue(reading.contains("String(localized: \"Abrir no site\")"),
            "the header's accessibility label is resolved through the catalogue")
        XCTAssertFalse(reading.contains(".accessibilityLabel(\"Abrir no site\")"),
            "a verbatim accessibility label ignores the catalogue")

        let sheet = try source("Sources/FeedMineUI/Filters/FilterSheetView.swift")
        XCTAssertTrue(sheet.contains("checkRow(type.displayName"), "content types draw their label")
        XCTAssertTrue(sheet.contains("checkRow(mood.displayName"), "moods draw their label")
        XCTAssertFalse(sheet.contains("checkRow(type.rawValue"), "no control draws a persisted raw value")
        XCTAssertFalse(sheet.contains("checkRow(mood.rawValue"), "no control draws a persisted raw value")
        XCTAssertTrue(sheet.contains("String(localized: \"selected\")"), "the state is localised")
        XCTAssertTrue(sheet.contains("String(localized: \"not selected\")"), "the state is localised")

        // Every control that announces selected/saved state, anywhere in the module: preset rows, language rows,
        // topic rows, country and source toggles, and the card. A verbatim pair would ignore the catalogue.
        let uiRoot = Self.repositoryRoot.appendingPathComponent("Sources/FeedMineUI")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: uiRoot, includingPropertiesForKeys: nil))
        var scanned = 0
        while let file = files.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            scanned += 1
            for verbatim in ["? \"selected\" : \"not selected\"", "? \"bookmarked\" : \"not bookmarked\""] {
                XCTAssertFalse(source.contains(verbatim),
                    "\(file.lastPathComponent) announces state verbatim, outside the catalogue: \(verbatim)")
            }
        }
        XCTAssertGreaterThan(scanned, 20, "the scan covers the UI module")

        let lens = try source("Sources/FeedMineUI/Filters/ReaderFilterLens.swift")
        XCTAssertTrue(lens.contains("label: filter.contentType.displayName"))
        XCTAssertTrue(lens.contains("label: filter.mood.displayName"))
        XCTAssertFalse(lens.contains("label: filter.contentType.rawValue"))
        XCTAssertFalse(lens.contains("label: filter.mood.rawValue"))

        let card = try source("Sources/FeedMineUI/Cards/FeedItemCardView.swift")
        XCTAssertTrue(card.contains("String(localized: \"bookmarked\")"))
        XCTAssertTrue(card.contains("String(localized: \"not bookmarked\")"))
        XCTAssertFalse(card.contains(".accessibilityValue(isBookmarked ? \"bookmarked\""),
            "a verbatim accessibility value ignores the catalogue")

        let composition = try source("FeedMineApp/FeedMineApp/AppComposition.swift")
        XCTAssertFalse(composition.contains("startupFailure = \"Não foi possível abrir o feed local.\""),
            "startup copy goes through the catalogue in every branch")
        XCTAssertEqual(composition.components(
            separatedBy: "startupFailure = String(localized: \"Não foi possível abrir o feed local.\")").count - 1, 2,
            "both startup failure branches are localised")
        XCTAssertTrue(composition.contains(".failed(message: String(localized: \"Falha ao atualizar o feed\"))"),
            "the refresh failure states itself in the interface's language")
    }
}
