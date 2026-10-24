import Foundation
import XCTest
import FeedMineDomain

/// R14: one expression, one meaning. The domain's grammar is deliberately small and is what the provider and the UI
/// both read; legacy literals keep their old meaning and their old identity.
final class SearchExpressionTests: XCTestCase {
    private func expression(_ query: String) throws -> SearchExpression {
        try XCTUnwrap(SearchExpression(query: query))
    }

    /// Positives may match different fields (`astronomia` in the title, `ciência` in the summary), and an excluded
    /// term in any field makes the whole candidate fail.
    func testPositivesMayLiveInDifferentFieldsAndAnExclusionAnywhereFails() throws {
        let value = try expression("astronomia ciência -astrologia")
        XCTAssertEqual(value.terms, ["astronomia", "ciencia"])
        XCTAssertEqual(value.excludedTerms, ["astrologia"])
        XCTAssertTrue(value.matches(fields: ["Astronomia", "Ciência aberta"]),
            "o exemplo discriminante do contrato")
        XCTAssertFalse(value.matches(fields: ["Astronomia", "Ciência e astrologia"]),
            "um campo com o termo excluído derruba o candidato")
        XCTAssertFalse(value.matches(fields: ["Astronomia"]), "todo positivo é obrigatório")
        XCTAssertFalse(value.matches(fields: []))
    }

    func testHyphenInsideATermIsPartOfItAndCaseOrDiacriticsNeverDistinguish() throws {
        let hyphen = try expression("teoria-de-cordas")
        XCTAssertEqual(hyphen.terms, ["teoria-de-cordas"])
        XCTAssertTrue(hyphen.matches(fields: ["A teoria-de-cordas hoje"]))
        XCTAssertFalse(hyphen.matches(fields: ["teoria de cordas"]),
            "o hífen interno não é separador")
        let accented = try expression("CIÊNCIA")
        XCTAssertEqual(accented.terms, ["ciencia"])
        XCTAssertTrue(accented.matches(fields: ["Resumo sobre ciencia"]))
        XCTAssertTrue(accented.matches(fields: ["CIÊNCIA"]))
    }

    func testOnlyNegativesAndBareHyphenCannotStartASearch() throws {
        let negativeOnly = try expression("-astrologia")
        XCTAssertFalse(negativeOnly.canSearch)
        XCTAssertFalse(negativeOnly.matches(fields: ["Astronomia"]))
        XCTAssertNil(SearchContext(query: "-astrologia"), "só negativos não inicia busca")
        XCTAssertNil(SearchContext(query: "-"), "um hífen isolado não é consulta")
        XCTAssertNil(SearchContext(query: "   "))
        // A bare hyphen among real terms is ignored, not a term.
        let mixed = try expression("astronomia - ciência")
        XCTAssertEqual(mixed.terms, ["astronomia", "ciencia"])
        XCTAssertTrue(mixed.canSearch)
    }

    /// A stored legacy query keeps its literal semantics, its bytes and its historical context identity; a new
    /// search states the expression grammar and participates in equality/identity.
    func testLegacyLiteralKeepsItsMeaningBytesAndIdentity() throws {
        let legacyJSON = #"{"query":"astronomia ciência"}"#
        let legacy = try JSONDecoder().decode(SearchContext.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacy.semantics, .legacyLiteral)
        XCTAssertNil(legacy.expression, "o legado não é interpretado pela gramática nova")
        XCTAssertEqual(legacy.query, "astronomia ciência")
        let legacyKey = ContextKey(request: .search(legacy))
        XCTAssertEqual(legacyKey.surfaceIdentity, "search:astronomia ciência")
        XCTAssertEqual(legacyKey.canonicalIdentity, ContextKey(request: .search(legacy)).canonicalIdentity)
        // Re-encoding the legacy value omits the marker, so the representation is the previous one.
        let encoded = try JSONEncoder().encode(legacy)
        XCTAssertFalse(String(data: encoded, encoding: .utf8)!.contains("semantics"))
        let round = try JSONDecoder().decode(SearchContext.self, from: encoded)
        XCTAssertEqual(round, legacy)

        let current = try XCTUnwrap(SearchContext(query: "astronomia ciência"))
        XCTAssertEqual(current.semantics, .termsV1)
        XCTAssertNotEqual(current, legacy, "a semântica participa da igualdade")
        XCTAssertNotEqual(ContextKey(request: .search(current)).canonicalIdentity, legacyKey.canonicalIdentity,
            "a semântica participa da identidade do contexto")
        XCTAssertEqual(ContextKey(request: .search(current)).surfaceIdentity, "search:terms-v1:astronomia ciência")
        let currentJSON = String(data: try JSONEncoder().encode(current), encoding: .utf8)!
        XCTAssertTrue(currentJSON.contains("termsV1"))
        XCTAssertEqual(try JSONDecoder().decode(SearchContext.self, from: Data(currentJSON.utf8)), current)
        // A legacy value that the new grammar would refuse still decodes (it never starts a search anyway).
        let legacyNegative = #"{"query":"-astrologia"}"#
        XCTAssertEqual(try JSONDecoder().decode(SearchContext.self,
            from: Data(legacyNegative.utf8)).semantics, .legacyLiteral)
    }
}
