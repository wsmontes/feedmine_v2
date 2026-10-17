//
// File: FeedReadingWordingTests.swift
// Module: ArchitectureSmokeTests
//
// The reader's honesty note: the surface used to say the whole article was on the site, which is an availability
// claim the app never established. The note now states only what the app knows — text the source supplied, whose
// completeness was not confirmed — and names the site only when there is an address to offer. Both languages live
// in the app catalogue, so this test resolves the exact keys the surface asks for in pt-BR and en, and fails if the
// old promise returns.
import XCTest
import FeedMineUI

final class FeedReadingWordingTests: XCTestCase {
    private static let oldPromise = "Conteúdo parcial: o artigo completo está no site."

    /// The catalogue the app actually ships, read from the checkout this test was compiled in: the question is
    /// what the bundle will resolve, not what a fixture says it would.
    private func catalogue() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FeedMineApp/FeedMineApp/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["sourceLanguage"] as? String, "pt-BR",
            "the catalogue's source language is what makes the key the Portuguese sentence")
        return try XCTUnwrap(root["strings"] as? [String: Any])
    }

    /// One language's resolved value for one key. A key with no value in that language fails the test: the surface
    /// asks for it, so the catalogue has to answer.
    private func value(for key: String, language: String, in strings: [String: Any]) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "the catalogue has no entry for “\(key)”")
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any],
            "“\(key)” has no localizations")
        let unit = try XCTUnwrap(localizations[language] as? [String: Any],
            "“\(key)” does not resolve in \(language)")
        let stringUnit = try XCTUnwrap(unit["stringUnit"] as? [String: Any])
        return try XCTUnwrap(stringUnit["value"] as? String,
            "“\(key)” has no value in \(language)")
    }

    private var notes: [String] {
        [FeedReadingWording.textWithoutSite, FeedReadingWording.textWithSite]
    }

    /// Both variants, in both languages: pt-BR is the source sentence and en is a real translation of it.
    func testBothNotesResolveInPortugueseAndEnglish() throws {
        let strings = try catalogue()
        for note in notes {
            let portuguese = try value(for: note, language: "pt-BR", in: strings)
            let english = try value(for: note, language: "en", in: strings)
            XCTAssertEqual(portuguese, note, "the source language resolves the sentence the surface asks for")
            XCTAssertFalse(english.isEmpty, "English must have its own value")
            XCTAssertNotEqual(english, portuguese, "English is a translation, not the Portuguese copied over")
        }
    }

    /// The note says what the app knows — the source supplied the text, completeness was not confirmed — and
    /// nothing it cannot establish.
    func testTheNoteStatesOnlyWhatTheAppKnows() throws {
        let strings = try catalogue()
        for note in notes {
            XCTAssertTrue(note.contains("Texto fornecido pela fonte"), "the note states the text's origin")
            XCTAssertTrue(note.contains("Não foi possível confirmar"),
                "the note states that completeness was not confirmed")
            let english = try value(for: note, language: "en", in: strings)
            XCTAssertTrue(english.contains("supplied by the source"))
            XCTAssertTrue(english.contains("could not be confirmed as complete"))
        }
    }

    /// The old sentence asserted a truncated text and an article available on the site. Neither is established,
    /// and neither may come back — not in the new notes, and nowhere else in the catalogue either.
    func testTheOldPromiseIsGoneAndNoNoteRepeatsIt() throws {
        let strings = try catalogue()
        XCTAssertNil(strings[Self.oldPromise], "the sentence that promised the article on the site is gone")

        let forbidden = ["artigo completo", "está no site", "conteúdo parcial", "full article", "is on the site",
            "partial content"]
        for (key, entry) in strings {
            var texts = [key]
            if let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] {
                for language in localizations.values {
                    let unit = language as? [String: Any]
                    let stringUnit = unit?["stringUnit"] as? [String: Any]
                    if let value = stringUnit?["value"] as? String { texts.append(value) }
                }
            }
            for text in texts {
                for promise in forbidden {
                    XCTAssertFalse(text.localizedCaseInsensitiveContains(promise),
                        "the catalogue still promises what the app has not established: “\(text)”")
                }
            }
        }

        for note in notes {
            XCTAssertFalse(note.localizedCaseInsensitiveContains("artigo completo"))
            XCTAssertFalse(note.localizedCaseInsensitiveContains("está no site"))
        }
    }

    /// The site is named only when the card carries an address the surface can offer. Without one, the note is
    /// about the text alone, and the reader is left with no promise of more.
    func testTheSiteIsNamedOnlyWhenThereIsAnAddress() {
        XCTAssertEqual(FeedReadingWording.note(offersSite: true), FeedReadingWording.textWithSite)
        XCTAssertEqual(FeedReadingWording.note(offersSite: false), FeedReadingWording.textWithoutSite)
        XCTAssertNotEqual(FeedReadingWording.textWithSite, FeedReadingWording.textWithoutSite)
        XCTAssertTrue(FeedReadingWording.textWithSite.lowercased().contains("site"),
            "with an address the note names the site")
        XCTAssertFalse(FeedReadingWording.textWithoutSite.lowercased().contains("site"),
            "without an address the note mentions no site")
        XCTAssertTrue(FeedReadingWording.textWithSite.contains("pode conter"),
            "the site is a possibility of more content, never a delivery of it")
    }
}
