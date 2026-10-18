import XCTest
import FeedMineDomain

/// T11: a curated feed's recipe. V1 kept these fields and these weight keys
/// (`Models/FeedRecipeDefinition.swift`); this states them as V2's own value, with the two asymmetries V1 had:
/// an answer weighs ±1.5 while "normal" weighs nothing, and a media kind the reader *removed* weighs −3 while
/// the kinds they kept carry no weight at all.
final class FeedRecipeDefinitionTests: XCTestCase {
    func testNeutralRecipeIsV1sOwn() {
        let neutral = FeedRecipeDefinition.neutral(languages: ["PT-br", "en", "pt"])
        XCTAssertEqual(neutral.languages, ["en", "pt"], "primary subtags, lowercased, deduped and sorted")
        XCTAssertEqual(neutral.discoveryLevel, 0.55, accuracy: 0.0001, "V1's own neutral value")
        XCTAssertTrue(neutral.topicPreferences.isEmpty)
        XCTAssertTrue(neutral.editorialPreferences.isEmpty)
        XCTAssertEqual(neutral.mediaTypes, [.article, .podcast, .video])
        XCTAssertFalse(neutral.adjustFromOpens)
        XCTAssertEqual(neutral.modelVersion, FeedRecipeDefinition.currentModelVersion)
    }

    func testInitialisationNormalisesWhatItCanAndClampsTheRest() {
        let recipe = FeedRecipeDefinition(languages: ["EN", "en-US"], discoveryLevel: 4,
            mediaTypes: [])
        XCTAssertEqual(recipe.languages, ["en"])
        XCTAssertEqual(recipe.discoveryLevel, 1, "discovery is clamped into 0…1")
        XCTAssertEqual(FeedRecipeDefinition(languages: [], discoveryLevel: -3).discoveryLevel, 0)
        XCTAssertEqual(recipe.mediaTypes, [.article, .podcast, .video],
            "an empty set is V1's own default — every kind, not none")
    }

    func testAnAnswerWeighsOneAndAHalfAndNormalWeighsNothing() {
        let recipe = FeedRecipeDefinition(
            topicPreferences: ["topic:technology": .more, "topic:sport": .less, "topic:culture": .neutral],
            editorialPreferences: ["editorial:reference": .more])
        XCTAssertEqual(recipe.weight(forKey: "topic:technology"), 1.5, accuracy: 0.0001)
        XCTAssertEqual(recipe.weight(forKey: "topic:sport"), -1.5, accuracy: 0.0001)
        XCTAssertEqual(recipe.weight(forKey: "topic:culture"), 0)
        XCTAssertEqual(recipe.weight(forKey: "editorial:reference"), 1.5, accuracy: 0.0001)
        XCTAssertEqual(recipe.weight(forKey: "topic:unknown"), 0, "a key the recipe never asked about")
    }

    /// V1's media asymmetry, kept: removed kinds are pushed away hard, kept kinds are neutral.
    func testARemovedMediaKindWeighsMinusThree() {
        let recipe = FeedRecipeDefinition(mediaTypes: [.article, .video])
        XCTAssertEqual(recipe.weight(forKey: "media:audio"), -3, "the podcast kind was removed")
        XCTAssertEqual(recipe.weight(forKey: "media:text"), 0, "the article kind is what the reader kept")
        XCTAssertEqual(recipe.weight(forKey: "media:video"), 0)
        XCTAssertEqual(recipe.weight(forKey: "media:nonsense"), 0)
        // The resolver's own vocabulary is the key set, not the recipe's own names.
        XCTAssertEqual(ReaderRecipeMediaType.article.featureKey, "media:text")
        XCTAssertEqual(ReaderRecipeMediaType.podcast.featureKey, "media:audio")
        let keys = Set(recipe.weightKeys)
        let expected: Set<String> = ["media:text", "media:video"]
        XCTAssertEqual(keys, expected, "only the kinds the recipe names are keys")
    }

    /// The two criteria V2 can express as a filter: languages and content type. All three kinds is "no
    /// criterion", which is what a filter's `.all` means.
    func testFilterCriteriaComeFromTheRecipe() {
        let recipe = FeedRecipeDefinition(languages: ["pt"], mediaTypes: [.podcast])
        XCTAssertEqual(recipe.languageCriterion, ["pt"])
        XCTAssertEqual(recipe.contentTypeCriterion, .audio)
        XCTAssertEqual(FeedRecipeDefinition(mediaTypes: [.article]).contentTypeCriterion, .text)
        XCTAssertEqual(FeedRecipeDefinition(mediaTypes: [.article, .podcast]).contentTypeCriterion, .all,
            "two kinds is not one criterion a filter can state")
        XCTAssertEqual(FeedRecipeDefinition().contentTypeCriterion, .all)
    }

    /// V1's `autoName()`: the feed is named by what the reader asked for more of, and "My Feed" otherwise.
    func testTheSummaryStatesTheReadersOwnAnswersStrongestFirst() {
        let recipe = FeedRecipeDefinition(
            topicPreferences: ["topic:science": .more, "topic:sport": .less],
            editorialPreferences: ["editorial:reference": .more],
            mediaTypes: [.article, .podcast])
        let summary = CuratedFeedSummary(name: "Ciência", recipe: recipe)
        XCTAssertEqual(summary.name, "Ciência")
        XCTAssertEqual(summary.languages, [])
        XCTAssertEqual(summary.mediaTypes, [.article, .podcast])
        XCTAssertEqual(summary.answers.map(\.key), ["editorial:reference", "topic:science", "topic:sport"],
            "the answers the reader actually gave, strongest first, then by key")
        XCTAssertTrue(summary.answers.allSatisfy { $0.level != .neutral },
            "a summary states answers, not defaults")
        XCTAssertTrue(summary.answers.first(where: { $0.key == "topic:science" })?.isTopic == true)
        XCTAssertFalse(summary.answers.first(where: { $0.key == "editorial:reference" })?.isTopic ?? true)
    }

    /// An envelope written by an older build is read with the fields it has and V1's defaults elsewhere.
    func testAPartialStoredRecipeTakesDefaultsForMissingFields() throws {
        let json = Data(#"{"languages":["pt"],"discoveryLevel":0.9,"modelVersion":1}"#.utf8)
        let decoded = try JSONDecoder().decode(FeedRecipeDefinition.self, from: json)
        XCTAssertEqual(decoded.languages, ["pt"])
        XCTAssertEqual(decoded.discoveryLevel, 0.9, accuracy: 0.0001)
        XCTAssertEqual(decoded.mediaTypes, [.article, .podcast, .video])
        XCTAssertFalse(decoded.adjustFromOpens)
        XCTAssertTrue(decoded.topicPreferences.isEmpty)
    }

    func testRoundingTheRecipeThroughJSONKeepsItWhole() throws {
        let recipe = FeedRecipeDefinition(languages: ["pt"], discoveryLevel: 0.2,
            topicPreferences: ["topic:climate": .more], editorialPreferences: ["editorial:distinctive": .less],
            mediaTypes: [.video], adjustFromOpens: true)
        let decoded = try JSONDecoder().decode(FeedRecipeDefinition.self, from: JSONEncoder().encode(recipe))
        XCTAssertEqual(decoded, recipe)
    }

    /// R13: every media selection the reader can make keeps its own meaning in the recipe. Empty is the declared
    /// "all kinds" (V1's default); a single kind is its content type; a pair is a real criterion — its own value,
    /// never "all". Weights keep V1's asymmetry (kept = 0, removed = −3).
    func testEveryMediaSelectionCombinationKeepsItsMeaning() throws {
        let kinds = ReaderRecipeMediaType.allCases
        XCTAssertEqual(kinds.count, 3)
        XCTAssertEqual(FeedRecipeDefinition().mediaTypes, Set(kinds), "vazio é o padrão declarado de todos os tipos")
        for mask in 1..<(1 << kinds.count) {
            let selection = Set(kinds.enumerated().compactMap { mask & (1 << $0.offset) != 0 ? $0.element : nil })
            let recipe = FeedRecipeDefinition(mediaTypes: selection)
            XCTAssertEqual(recipe.mediaTypes, selection, "a seleção é preservada em \\(selection)")
            if selection.count == 1 {
                XCTAssertEqual(recipe.contentTypeCriterion, selection.first?.contentType)
            } else {
                XCTAssertEqual(recipe.contentTypeCriterion, .all,
                    "a lente de tipo único não representa um par; o conjunto é a resposta")
            }
            for kind in kinds {
                let weight = recipe.weight(forKey: kind.featureKey)
                XCTAssertEqual(weight, selection.contains(kind) ? 0 : -3)
            }
        }
        let pair = ReaderFilter(mediaTypes: [.article, .video])
        let all = ReaderFilter()
        XCTAssertNotEqual(pair, all, "um par não é todos os tipos")
        XCTAssertNotEqual(pair.identityText, all.identityText)
        XCTAssertEqual(pair, ReaderFilter(mediaTypes: [.video, .article]), "ordem não é identidade")
        XCTAssertEqual(ReaderFilter(mediaTypes: Set(kinds)), all, "todos os tipos volta a não-critério")
        // Legacy identity preservation: one kind is the single lens, all three is no criterion — neither adds a
        // media component, so a persisted context keeps the same key (and checkpoint).
        XCTAssertEqual(ReaderFilter(mediaTypes: [.article]), ReaderFilter(contentType: .text))
        XCTAssertEqual(ReaderFilter(mediaTypes: [.article]).identityText,
            ReaderFilter(contentType: .text).identityText)
        XCTAssertEqual(ReaderFilter(mediaTypes: Set(kinds)).identityText, all.identityText)
    }

    /// R13: a filter persisted before the media-set field decodes as "no criterion" and keeps its old identity;
    /// a pair round-trips.
    func testLegacyFilterDecodesAsNoMediaCriterionAndPairsRoundTrip() throws {
        let legacy = #"{"regionIDs":[],"taxonomyNodeIDs":[],"languages":[],"contentType":"All","mood":"All","exclusions":{"isEnabled":false,"rules":[]}}"#
        let decoded = try JSONDecoder().decode(ReaderFilter.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.mediaTypes.isEmpty)
        XCTAssertEqual(decoded, ReaderFilter())
        XCTAssertEqual(decoded.identityText, ReaderFilter().identityText,
            "a representação antiga mantém a identidade antiga")
        // A single-kind filter persisted by the legacy shape (contentType=Articles, no media key) also keeps it.
        let legacySingle = #"{"regionIDs":[],"taxonomyNodeIDs":[],"languages":[],"contentType":"Articles","mood":"All","exclusions":{"isEnabled":false,"rules":[]}}"#
        let single = try JSONDecoder().decode(ReaderFilter.self, from: Data(legacySingle.utf8))
        XCTAssertEqual(single.identityText, ReaderFilter(contentType: .text).identityText)
        let pair = ReaderFilter(mediaTypes: [.article, .video])
        let round = try JSONDecoder().decode(ReaderFilter.self, from: JSONEncoder().encode(pair))
        XCTAssertEqual(round, pair)
        XCTAssertEqual(round.mediaTypes, [.article, .video])
    }
}
