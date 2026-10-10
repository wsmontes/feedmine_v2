import XCTest
import FeedMineDomain
@testable import FeedMineEditorial

/// T11: a recipe resolved into a ranking. V1's formula (`CuratedPreferenceEngine.sourceMultiplier`) is pinned
/// here by hand, so the numbers a curated feed ranks by cannot drift unnoticed.
final class FeedRecipeResolutionTests: XCTestCase {
    private func source(_ id: String = "https://a.example/feed", nodes: [String] = [],
        media: String = "text", nature: String? = nil, quality: Int? = 70,
        editorial: FeedEditorialAssessment? = nil) -> FeedRecipeResolution.SourceFacts {
        .init(identity: id, nodeKeys: nodes, mediaKind: media, nature: nature, qualityScore: quality,
            editorial: editorial)
    }

    func testTheKeysASourceMatchesComeFromWhatTheCatalogueSays() {
        let keys = FeedRecipeResolution.featureKeys(for: source(nodes: ["topics/science", "countries/br"],
            media: "audio", nature: "Evergreen",
            editorial: FeedEditorialAssessment(style: .reference, isRecognized: true, isSpecialist: false,
                score: 0.9, isEligible: true)))
        XCTAssertTrue(keys.contains("topic:topics/science"))
        XCTAssertTrue(keys.contains("region:countries/br"))
        XCTAssertTrue(keys.contains("media:audio"))
        XCTAssertTrue(keys.contains("nature:evergreen"))
        XCTAssertTrue(keys.contains("editorial:reference"))
        XCTAssertTrue(keys.contains("scope:regional"), "a country placement is a regional scope")
        let global = FeedRecipeResolution.featureKeys(for: source(nodes: ["topics/science"]))
        XCTAssertTrue(global.contains("scope:global"))
        XCTAssertFalse(global.contains("scope:regional"))
    }

    /// V1's own arithmetic, by hand: `.more` weighs 1.5, its key keeps the 0.25 confidence floor, discovery
    /// flattens with (1 − discovery·0.42), and the catalogue's own quality nudges the result.
    func testTheMultiplierFollowsV1sFormulaExactly() {
        let recipe = FeedRecipeDefinition(discoveryLevel: 0.5,
            topicPreferences: ["topic:topics/science": .more])
        let science = source(nodes: ["topics/science"])
        let expected = exp(1.5 * 0.25 * 0.19 * (1 - 0.5 * 0.42)) * (0.9 + 0.7 * 0.2)
        XCTAssertEqual(FeedRecipeResolution.multiplier(for: science, recipe: recipe), expected, accuracy: 0.0005)
        XCTAssertEqual(expected, 1.1002, accuracy: 0.001, "the hand-computed value this pins")
        // A topic the reader asked for *less* of pulls the other way.
        let less = FeedRecipeDefinition(discoveryLevel: 0.5, topicPreferences: ["topic:topics/science": .less])
        let pulled = FeedRecipeResolution.multiplier(for: science, recipe: less)
        XCTAssertLessThan(pulled, 1)
        XCTAssertEqual(pulled, exp(-1.5 * 0.25 * 0.19 * (1 - 0.5 * 0.42)) * (0.9 + 0.7 * 0.2),
            accuracy: 0.0005, "the same weight, mirrored below the centre")
        XCTAssertEqual(pulled, 0.9831, accuracy: 0.001, "the hand-computed value this pins")
    }

    /// Higher discovery keeps a weakly preferred source closer to the centre — V1's own reason for the slider.
    func testDiscoveryFlattensThePreference() {
        let source = source(nodes: ["topics/science"])
        let focused = FeedRecipeResolution.multiplier(for: source,
            recipe: FeedRecipeDefinition(discoveryLevel: 0, topicPreferences: ["topic:topics/science": .more]))
        let exploratory = FeedRecipeResolution.multiplier(for: source,
            recipe: FeedRecipeDefinition(discoveryLevel: 1, topicPreferences: ["topic:topics/science": .more]))
        XCTAssertGreaterThan(focused, exploratory)
        XCTAssertGreaterThan(exploratory, 1, "still on the preferred side, just less strongly")
        XCTAssertLessThan(exploratory - 1, focused - 1)
    }

    /// A kind the reader removed weighs −3, so a source of that kind lands below the centre.
    func testARemovedKindIsPushedAway() {
        let recipe = FeedRecipeDefinition(discoveryLevel: 0.5, mediaTypes: [.article, .video])
        // Both are placed: a media weight only bites for a source the taxonomy knows (V1's own guard).
        let podcast = source(nodes: ["topics/science"], media: "audio")
        let article = source(nodes: ["topics/science"], media: "text")
        XCTAssertLessThan(FeedRecipeResolution.multiplier(for: podcast, recipe: recipe), 1)
        XCTAssertEqual(FeedRecipeResolution.multiplier(for: article, recipe: recipe),
            0.9 + 0.7 * 0.2, accuracy: 0.0005,
            "a kept kind carries no weight, so the source sits at the centre times its quality")
    }

    /// The catalogue's quality score is the only other thing V1 let move a multiplier, and it can never leave
    /// the 0.42…3 window.
    func testQualityNudgesWithinTheWindow() {
        let recipe = FeedRecipeDefinition(discoveryLevel: 0.5, topicPreferences: ["topic:topics/science": .more])
        let good = FeedRecipeResolution.multiplier(for: source(nodes: ["topics/science"], quality: 100), recipe: recipe)
        let poor = FeedRecipeResolution.multiplier(for: source(nodes: ["topics/science"], quality: 0), recipe: recipe)
        XCTAssertGreaterThan(good, poor)
        XCTAssertGreaterThanOrEqual(poor, 0.42)
        XCTAssertLessThanOrEqual(good, 3)
        // A source the taxonomy places nowhere is outside the vocabulary a recipe speaks: V1 weighed it
        // exactly 1, quality and all, and left it out of the map.
        let unplaced = source("https://b.example/feed")
        XCTAssertEqual(FeedRecipeResolution.multiplier(for: unplaced, recipe: recipe), 1)
        let multipliers = FeedRecipeResolution.multipliers(for: [source(nodes: ["topics/science"]), unplaced],
            recipe: recipe)
        XCTAssertNil(multipliers["https://b.example/feed"])
        XCTAssertNotNil(multipliers["https://a.example/feed"])
        // A source that *is* placed, with a recipe that says nothing about it, keeps its quality nudge.
        let neutral = FeedRecipeDefinition(discoveryLevel: 0.5)
        XCTAssertEqual(FeedRecipeResolution.multiplier(for: source(nodes: ["topics/science"]), recipe: neutral),
            1.04, accuracy: 0.0005)
    }

    /// A regional weight is halved: V1 scaled anything under `scope:` by 0.5.
    func testARegionalWeightCountsHalf() {
        let recipe = FeedRecipeDefinition(discoveryLevel: 0.5,
            topicPreferences: ["region:countries/br": .more])
        let brazil = source(nodes: ["countries/br"])
        let expected = exp(1.5 * 0.25 * 0.19 * (1 - 0.5 * 0.42)) * (0.9 + 0.7 * 0.2)
        XCTAssertEqual(FeedRecipeResolution.multiplier(for: brazil, recipe: recipe), expected, accuracy: 0.0005,
            "the region key itself is not halved — only the `scope:` key is")
        let scoped = FeedRecipeDefinition(discoveryLevel: 0.5, topicPreferences: ["scope:regional": .more])
        let scopedExpected = exp(1.5 * 0.25 * 0.5 * 0.19 * (1 - 0.5 * 0.42)) * (0.9 + 0.7 * 0.2)
        XCTAssertEqual(FeedRecipeResolution.multiplier(for: brazil, recipe: scoped), scopedExpected,
            accuracy: 0.0005)
    }

    /// The filter a recipe states, and V1's own naming rule.
    func testTheFilterAndTheSuggestedName() {
        let recipe = FeedRecipeDefinition(languages: ["pt"], discoveryLevel: 0.5,
            topicPreferences: ["topic:topics/science": .more, "topic:topics/sport": .more,
                "topic:topics/culture": .less],
            mediaTypes: [.podcast])
        XCTAssertEqual(FeedRecipeResolution.filter(for: recipe).languages, ["pt"])
        XCTAssertEqual(FeedRecipeResolution.filter(for: recipe).contentType, .audio)
        // Without a catalogue name the key is all the resolver has, so it states the key itself.
        XCTAssertEqual(FeedRecipeResolution.suggestedName(for: recipe), "topics/science & topics/sport",
            "the topics asked for more of, in key order; a topic asked for less is left out")
        XCTAssertEqual(FeedRecipeResolution.suggestedName(for: recipe,
            names: ["topic:topics/science": "Ciência", "topic:topics/sport": "Esporte"]), "Ciência & Esporte")
        XCTAssertEqual(FeedRecipeResolution.suggestedName(for: FeedRecipeDefinition()), "Meu feed")
        XCTAssertEqual(FeedRecipeResolution.suggestedName(
            for: FeedRecipeDefinition(topicPreferences: ["topic:topics/science": .more])), "topics/science")
    }
}
