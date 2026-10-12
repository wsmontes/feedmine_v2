import XCTest
import FeedMineDomain

/// Round 9: the catalogue declares 257 codes (`en`, `en-US`, `pt`, `pt-BR`…) and a reader chooses a *language*.
/// One rule — the choice is the primary subtag — so a selection, a recipe and a source's own declaration cannot
/// hold two identities for the same answer.
final class ReaderLanguageChoiceTests: XCTestCase {
    func testChoiceIsThePrimarySubtagLowercased() {
        XCTAssertEqual(ReaderLanguageCode.choice("pt-BR"), "pt")
        XCTAssertEqual(ReaderLanguageCode.choice("en_US"), "en")
        XCTAssertEqual(ReaderLanguageCode.choice("  EN  "), "en")
        XCTAssertEqual(ReaderLanguageCode.choice("pt"), "pt")
        XCTAssertEqual(ReaderLanguageCode.choice(""), "")
    }

    func testUndeclaredIsNotALanguageAReaderChose() {
        XCTAssertTrue(ReaderLanguageCode.isUndeclared(""))
        XCTAssertTrue(ReaderLanguageCode.isUndeclared("und"))
        XCTAssertTrue(ReaderLanguageCode.isUndeclared("und-Latn"))
        XCTAssertTrue(ReaderLanguageCode.isUndeclared("und-x"),
            "a private-use tag of an undetermined language is still undetermined")
        XCTAssertFalse(ReaderLanguageCode.isUndeclared("pt"))
    }

    /// A filter that held `pt` and `pt-BR` held one answer twice. It is one choice, and the context identity
    /// says so: a reader who re-enters the same context re-enters the *same* context.
    func testFilterCollapsesRegionalAndDuplicateChoices() {
        let filter = ReaderFilter(languages: ["pt-BR", "pt", "EN-us"])
        XCTAssertEqual(filter.languages, ["pt", "en"])
        XCTAssertEqual(ReaderFilter(languages: ["pt-BR"]).identityText,
            ReaderFilter(languages: ["pt"]).identityText)
    }

    /// The compose chips write the recipe's own array directly; the observer keeps the invariant, so a raw
    /// catalogue code cannot enter a recipe behind the initializer's back.
    func testRecipeCollapsesCodesWrittenDirectly() {
        var recipe = FeedRecipeDefinition(languages: ["pt-BR", "en-US", "en-GB"])
        XCTAssertEqual(recipe.languages, ["en", "pt"])
        recipe.languages = recipe.languages + ["fr-FR"]
        XCTAssertEqual(recipe.languages, ["en", "fr", "pt"])
    }

    /// The migration, on the data: a filter stored before the choice became the language keeps a regional code
    /// in its JSON. Decoding normalizes it, so the stored value cannot mean something other than the selection.
    func testStoredRegionalFilterDecodesToItsLanguage() throws {
        let json = """
        {"regionIDs":[],"taxonomyNodeIDs":[],"languages":["pt-BR","en-US","pt"],
         "contentType":"All","mood":"All","exclusions":{"isEnabled":false,"rules":[]}}
        """
        let filter = try JSONDecoder().decode(ReaderFilter.self, from: Data(json.utf8))
        XCTAssertEqual(filter.languages, ["pt", "en"])
        XCTAssertEqual(filter.identityText, ReaderFilter(languages: ["pt", "en"]).identityText,
            "a legacy regional filter is the context of the language it belongs to")
    }

    /// A recipe stored with a regional code (the importer wrote raw values) decodes to the same answer as one
    /// written today.
    func testStoredRegionalRecipeDecodesToItsLanguage() throws {
        let json = """
        {"languages":["pt-BR"],"discoveryLevel":0.5,"topicPreferences":{},"editorialPreferences":{},
         "mediaTypes":["article"],"adjustFromOpens":false,"modelVersion":1}
        """
        let recipe = try JSONDecoder().decode(FeedRecipeDefinition.self, from: Data(json.utf8))
        XCTAssertEqual(recipe.languages, ["pt"])
    }
}
