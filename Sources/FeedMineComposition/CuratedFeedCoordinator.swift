//
// File: CuratedFeedCoordinator.swift
// Module: FeedMineComposition
//
// Responsibility:
// A curated feed's whole life: saved from a recipe, inspected as values, edited, and ranked. The recipe is the
// artifact the reader authored; `FeedRecipeResolution` (Editorial) is what turns it into a ranking, and the
// catalog is what states each source's facts. Nothing here reads a clock or hides a rule.
//
// Does not own: the resolution (Editorial), storage (Persistence), the clock or any surface.
import Foundation
import FeedMineDomain
import FeedMineEditorial
import FeedMinePersistence
import FeedMineRuntime

public enum CuratedFeedError: Error, Equatable, Sendable {
    /// The preset exists but is not a curated feed, or a curated one lost its recipe.
    case notCurated
    case invalidName
}

public struct CuratedFeedCoordinator: Sendable {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    /// V1's save: the recipe resolves to the identity the feed runs on — its own preset, plus the criteria the
    /// recipe states (languages and content type) — and both are stored together. The weights are **not** part
    /// of the identity: they are how the feed ranks, and moving a slider must not move the reader to another
    /// context.
    @discardableResult
    public func save(_ recipe: FeedRecipeDefinition, named name: String) throws -> ReaderPreset {
        let library = ReaderLibraryCoordinator(database: database)
        return try library.savePreset(named: name, kind: .curatedFeed,
            from: ContextKey(request: .main, filter: FeedRecipeResolution.filter(for: recipe)), recipe: recipe)
    }

    /// V1's "capô": what the feed is, as values the surface can state.
    public func inspect(_ preset: ReaderPreset) throws -> CuratedFeedSummary {
        guard preset.kind == .curatedFeed, let recipe = preset.recipe else { throw CuratedFeedError.notCurated }
        return CuratedFeedSummary(name: preset.name, recipe: recipe)
    }

    /// Edits a feed: its name, its recipe, and the identity the recipe resolves to, in one write.
    @discardableResult
    public func update(_ preset: ReaderPreset, recipe: FeedRecipeDefinition, named name: String) throws -> ReaderPreset {
        guard preset.kind == .curatedFeed else { throw CuratedFeedError.notCurated }
        let library = ReaderLibraryCoordinator(database: database)
        return try library.updateCuratedPreset(id: preset.id, name: name,
            key: ContextKey(request: preset.key.request, preset: preset.presetID,
                filter: FeedRecipeResolution.filter(for: recipe), searchScope: preset.key.searchScope),
            recipe: recipe)
    }

    /// Deletes a feed. Nothing else is touched: its sources are the reader's selection, which is not the feed's.
    @discardableResult
    public func delete(_ preset: ReaderPreset) throws -> Bool {
        try ReaderLibraryCoordinator(database: database).deletePreset(id: preset.id)
    }

    /// The multipliers a session ranks this feed's sources by. It returns an empty map for a preset that is not
    /// a curated feed, which is exactly "no weighting" — not an error the caller has to handle.
    public func multipliers(for preset: ReaderPreset, sources: [FeedRecipeResolution.SourceFacts]) -> [String: Double] {
        guard let recipe = preset.recipe else { return [:] }
        return FeedRecipeResolution.multipliers(for: sources, recipe: recipe)
    }

    /// V1's `autoName()`: the topics the reader asked for more of, with the catalogue's own names when the
    /// caller can supply them.
    public func suggestedName(for recipe: FeedRecipeDefinition, names: [String: String] = [:]) -> String {
        FeedRecipeResolution.suggestedName(for: recipe, names: names)
    }

    /// The recipes a reader has, in the reader's own order: what an inspector lists.
    public func curatedPresets() throws -> [ReaderPreset] {
        try ReaderLibraryCoordinator(database: database).presets().filter { $0.kind == .curatedFeed }
    }
}
