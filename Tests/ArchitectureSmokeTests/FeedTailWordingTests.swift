//
// File: FeedTailWordingTests.swift
// Module: ArchitectureSmokeTests
//
// NF-04: `deferred` is not a search in flight. The engine deferred the opportunity (resources denied, or a
// generation conflict superseded it), so the absence surface states the wait and offers the host's real retry.
// The sentences that claimed "looking for more news" and promised "trying again in a moment" were invented work;
// they may not return to the catalogue, and the two surfaces that do state the fact must resolve in both shipped
// languages.
import XCTest
import FeedMineUI

final class FeedTailWordingTests: XCTestCase {
    /// The sentences the surface no longer says, and that no other surface may reintroduce.
    private static let retiredSentences = [
        "Procurando mais novidades…",
        "Ainda não encontramos conteúdo suficiente. Vamos tentar novamente em instantes."
    ]

    /// What `FeedLoadingView` asks the catalogue for when the work is `.deferred`.
    private static let deferredSentences = ["Aguardando nova oportunidade", "Nada está sendo buscado agora."]

    /// The catalogue the app ships, read from this checkout: the question is what the bundle resolves, not what a
    /// fixture says it would.
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

    private func value(for key: String, language: String, in strings: [String: Any]) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "the catalogue has no entry for “\(key)”")
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any],
            "“\(key)” has no localizations")
        let unit = try XCTUnwrap(localizations[language] as? [String: Any],
            "“\(key)” does not resolve in \(language)")
        let stringUnit = try XCTUnwrap(unit["stringUnit"] as? [String: Any])
        return try XCTUnwrap(stringUnit["value"] as? String, "“\(key)” has no value in \(language)")
    }

    func testDeferredSentencesResolveInPortugueseAndEnglish() throws {
        let strings = try catalogue()
        for sentence in Self.deferredSentences {
            let portuguese = try value(for: sentence, language: "pt-BR", in: strings)
            let english = try value(for: sentence, language: "en", in: strings)
            XCTAssertEqual(portuguese, sentence, "the source language resolves the sentence the surface asks for")
            XCTAssertFalse(english.isEmpty, "English must have its own value")
            XCTAssertNotEqual(english, portuguese, "English is a translation, not the Portuguese copied over")
        }
    }

    /// The deferred surface states a situation, never an activity: no sentence may claim a search that the
    /// pipeline did not start, and none may promise an instant.
    func testDeferredSentencesClaimNoSearchAndNoDeadline() {
        for sentence in Self.deferredSentences {
            let lower = sentence.lowercased()
            XCTAssertFalse(lower.contains("procurando"), "“\(sentence)” claims a search in flight")
            XCTAssertFalse(lower.contains("buscando histórias"), "“\(sentence)” claims discovery is running")
            XCTAssertFalse(lower.contains("instantes"), "“\(sentence)” promises a retry instant")
        }
    }

    func testTheRetiredSentencesAreGoneFromTheCatalogue() throws {
        let strings = try catalogue()
        for sentence in Self.retiredSentences {
            XCTAssertNil(strings[sentence], "“\(sentence)” was retired: the state never supported it")
        }
    }
}
