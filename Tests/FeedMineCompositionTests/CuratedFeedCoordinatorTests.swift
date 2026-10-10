import Foundation
import XCTest
import GRDB
import FeedMineDomain
import FeedMineEditorial
@testable import FeedMinePersistence
import FeedMineComposition

/// T11: a curated feed's life — saved from a recipe, inspected as values, edited, ranked and deleted.
@MainActor
final class CuratedFeedCoordinatorTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    private func recipe() -> FeedRecipeDefinition {
        FeedRecipeDefinition(languages: ["pt"], discoveryLevel: 0.3,
            topicPreferences: ["topic:topics/science": .more, "topic:topics/sport": .less],
            mediaTypes: [.article, .podcast])
    }

    /// Saving stores the recipe with the preset, and the identity the recipe resolves to is its own preset plus
    /// the criteria the recipe states — never the weights.
    func testSavingResolvesTheIdentityAndKeepsTheRecipe() throws {
        let database = try database()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a.example/feed"])
        let coordinator = CuratedFeedCoordinator(database: database)
        let preset = try coordinator.save(recipe(), named: "  Ciência  ")
        XCTAssertEqual(preset.name, "Ciência", "names are trimmed")
        XCTAssertEqual(preset.kind, .curatedFeed)
        XCTAssertEqual(preset.recipe, recipe(), "the recipe travels with the feed it produced")
        XCTAssertEqual(preset.key.preset, preset.presetID, "the identity names its own preset")
        XCTAssertEqual(preset.key.filter.languages, ["pt"], "the recipe's languages are criteria")
        XCTAssertEqual(preset.key.filter.contentType, .all,
            "two media kinds is not one criterion a filter can state — the weights are how that bites")
        XCTAssertEqual(preset.key.filter.taxonomyNodeIDs, [],
            "a topic weight is a ranking, not a criterion")
        // It survives a reopen, and the surface's own read sees the same thing.
        let reopened = try XCTUnwrap(try CuratedFeedCoordinator(database: database).curatedPresets().first)
        XCTAssertEqual(reopened, preset)
    }

    /// The "capô": the summary states the reader's own answers, never a default.
    func testInspectingStatesTheReadersOwnAnswers() throws {
        let database = try database()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a.example/feed"])
        let coordinator = CuratedFeedCoordinator(database: database)
        let preset = try coordinator.save(recipe(), named: "Ciência")
        let summary = try coordinator.inspect(preset)
        XCTAssertEqual(summary.name, "Ciência")
        XCTAssertEqual(summary.languages, ["pt"])
        XCTAssertEqual(summary.mediaTypes, [.article, .podcast])
        XCTAssertEqual(summary.discoveryLevel, 0.3, accuracy: 0.0001)
        XCTAssertEqual(summary.answers.map(\.key), ["topic:topics/science", "topic:topics/sport"],
            "the answers the reader gave, strongest first")
        // A preset that is not a curated feed is refused, rather than summarised as an empty one.
        let smart = try ReaderLibraryCoordinator(database: database).savePreset(named: "Busca", kind: .smartBookmark,
            from: ContextKey(request: .main))
        XCTAssertThrowsError(try coordinator.inspect(smart)) {
            XCTAssertEqual($0 as? CuratedFeedError, .notCurated)
        }
    }

    /// Editing changes the name, the recipe and the identity together; the saved feed is the edited one.
    func testEditingRewritesBothTheRecipeAndTheIdentity() throws {
        let database = try database()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a.example/feed"])
        let coordinator = CuratedFeedCoordinator(database: database)
        let preset = try coordinator.save(recipe(), named: "Ciência")
        var edited = recipe()
        edited.languages = ["en"]
        edited.mediaTypes = [.video]
        edited.topicPreferences["topic:topics/climate"] = .more
        let updated = try coordinator.update(preset, recipe: edited, named: "Climate")
        XCTAssertEqual(updated.id, preset.id, "editing is not a new feed")
        XCTAssertEqual(updated.name, "Climate")
        XCTAssertEqual(updated.recipe, edited)
        XCTAssertEqual(updated.key.filter.languages, ["en"])
        XCTAssertEqual(updated.key.filter.contentType, .video)
        XCTAssertEqual(updated.key.preset, updated.presetID, "still names itself")
        XCTAssertEqual(try coordinator.curatedPresets().count, 1)
        XCTAssertEqual(try coordinator.inspect(updated).languages, ["en"])
    }

    /// Deleting a feed deletes only the feed: the reader's sources and their selection are not its.
    func testDeletingAFeedLeavesTheSelectionAlone() throws {
        let database = try database()
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: ["https://a.example/feed"])
        let before = try XCTUnwrap(try preferences.load())
        let coordinator = CuratedFeedCoordinator(database: database)
        let preset = try coordinator.save(recipe(), named: "Ciência")
        XCTAssertTrue(try coordinator.delete(preset))
        XCTAssertTrue(try coordinator.curatedPresets().isEmpty)
        XCTAssertEqual(try preferences.load(), before)
    }

    /// The ranking a session uses: the recipe's multipliers for the sources it states facts about, and no
    /// weighting at all for a preset that is not a curated feed.
    func testTheMultipliersComeFromTheRecipeAndTheCatalogueFacts() throws {
        let database = try database()
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a.example/feed"])
        let coordinator = CuratedFeedCoordinator(database: database)
        let preset = try coordinator.save(recipe(), named: "Ciência")
        let sources = [
            FeedRecipeResolution.SourceFacts(identity: "https://science.example/feed",
                nodeKeys: ["topics/science"], qualityScore: 90),
            FeedRecipeResolution.SourceFacts(identity: "https://sport.example/feed",
                nodeKeys: ["topics/sport"], qualityScore: 90),
            FeedRecipeResolution.SourceFacts(identity: "https://nowhere.example/feed"),
        ]
        let multipliers = coordinator.multipliers(for: preset, sources: sources)
        let science = multipliers["https://science.example/feed"] ?? 1
        let sport = multipliers["https://sport.example/feed"] ?? 1
        XCTAssertGreaterThan(science, sport, "the topic the reader asked for more of ranks above the other")
        XCTAssertGreaterThan(science, 1)
        XCTAssertNil(multipliers["https://nowhere.example/feed"],
            "a source the taxonomy does not place anywhere is exactly neutral")
        // V1's own property, kept: a preference is weak while it has no evidence behind it, and the catalogue's
        // quality always applies — so a *high-quality* source the reader asked for less of can still sit just
        // above the centre. At the catalogue's default quality the answer is below it.
        XCTAssertGreaterThan(sport, 1, "quality 90 outweighs the 0.25-floor preference")
        let plain = [FeedRecipeResolution.SourceFacts(identity: "https://sport.example/feed",
            nodeKeys: ["topics/sport"])]
        XCTAssertLessThan(coordinator.multipliers(for: preset, sources: plain)["https://sport.example/feed"] ?? 1, 1)
        // A smart bookmark has no recipe: no weighting, not an error.
        let smart = try ReaderLibraryCoordinator(database: database).savePreset(named: "Busca", kind: .smartBookmark,
            from: ContextKey(request: .main))
        XCTAssertTrue(coordinator.multipliers(for: smart, sources: sources).isEmpty)
    }

    /// V1's naming rule, through the coordinator.
    func testTheSuggestedNameFollowsTheReadersChoices() throws {
        let coordinator = CuratedFeedCoordinator(database: try database())
        XCTAssertEqual(coordinator.suggestedName(for: recipe()), "topics/science",
            "one topic asked for more of is the name; the one asked for less is left out")
        var two = recipe()
        two.topicPreferences["topic:topics/climate"] = .more
        XCTAssertEqual(coordinator.suggestedName(for: two), "topics/climate & topics/science")
        XCTAssertEqual(coordinator.suggestedName(for: two,
            names: ["topic:topics/science": "Ciência", "topic:topics/climate": "Clima"]), "Clima & Ciência")
        XCTAssertEqual(coordinator.suggestedName(for: FeedRecipeDefinition()), "Meu feed")
    }
}
