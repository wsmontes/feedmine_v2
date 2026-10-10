//
// File: LegacyUserStateImport.swift
// Module: FeedMineComposition
//
// Responsibility:
// Carry the reader's own state from V1's `user.sqlite` into V2's library: bookmark boxes, source collections
// and the smart feeds that a saved search can express. It reads the V1 file read-only, maps every V1 integer id
// through an explicit, stable map (`v1:list:<id>`), and hands the whole result to the library store, which
// applies it in one transaction.
//
// What it deliberately does **not** carry, and says so in its report instead of importing a half-truth:
// - V1's bookmarked *articles*: their `item_id` names an object in V1's article schema, and V2 has no referent
//   for it (V2's bookmarks mark published card occurrences). The boxes keep their names, order and identity;
//   the items cannot come with them.
// - V1's curated feeds: their definitions carry profile weights and a recipe; V2's filter cannot express them,
//   and T11 owns curation. They are counted, not approximated.
// - A smart feed's source-collection scope: V2's identity has no collection-scoped request, so the terms and
//   filters are imported and the scope is reported as dropped.
// - V1's persistent-search bookmark lists: no V1 UI ever created one (the columns exist, the surface does not).
import Foundation
import FeedMineDomain
import FeedMinePersistence

public struct LegacyUserStateImport: Sendable {
    public struct Report: Hashable, Sendable {
        public let inserted: ReaderLibraryImportReport
        public let skippedBoxItems: Int
        public let skippedBoxes: Int
        public let skippedPersistentSearchLists: Int
        public let skippedCuratedFeeds: Int
        public let skippedSmartFeeds: Int
        public let droppedCollectionScopes: Int
        public let carriedCollections: Int
        public let carriedSmartFeeds: Int
    }

    /// The explicit id map. A V1 integer is never reused as a V2 identity: it names the row it came from, so a
    /// repeated import finds its own work and adds nothing.
    static func listID(_ legacy: Int64) -> String { "v1:list:\(legacy)" }
    static func collectionID(_ legacy: Int64) -> String { "v1:collection:\(legacy)" }
    static func presetID(_ legacy: Int64) -> String { "v1:smart:\(legacy)" }

    /// V1's smart-feed payload, as V1 wrote it. Every field is optional here: an older V1 wrote fewer of them,
    /// and a field that is absent must not fail the import of the fields that are present.
    struct SmartFeedDefinition: Decodable {
        var query: String?
        var requiredSearchTerms: [String]?
        var excludedSearchTerms: [String]?
        var includeSources: Bool?
        var includeContents: Bool?
        var region: String?
        var taxonomyNodeIDs: [String]?
        var languages: [String]?
        var contentType: String?
        var mood: String?
        var sourceCollectionID: Int64?
        var excludedKeywords: [String]?
    }

    @discardableResult
    public static func run(reader: LegacyUserStateReader, into database: RuntimeDatabase,
        at date: Date = Date()) throws -> Report {
        let lists = try reader.bookmarkLists()
        let itemCounts = try reader.bookmarkItemCounts()
        let collections = try reader.collections()
        let smartFeeds = try reader.smartFeeds()
        let curatedCount = try reader.curatedFeedCount()

        var importPayload = ReaderLibraryImport()
        var skippedBoxes = 0, skippedBoxItems = 0, skippedPersistentSearch = 0
        var droppedCollectionScopes = 0, skippedSmartFeeds = 0

        // Boxes: V1's default box *is* V2's default box, so it is not imported again — its identity is the one
        // the card control already writes to. Every other box keeps V1's name and its own order.
        var imported: [ReaderLibraryImport.BookmarkList] = []
        for list in lists {
            skippedBoxItems += itemCounts[list.id] ?? 0
            if list.carriesDeadPersistentSearch { skippedPersistentSearch += 1 }
            guard !list.isDefault, !list.carriesDeadPersistentSearch else {
                if !list.isDefault { skippedBoxes += 1 }
                continue
            }
            imported.append(.init(id: listID(list.id), name: list.name))
        }
        importPayload = ReaderLibraryImport(bookmarkLists: imported, collections: [], presets: [])

        // Collections carry over whole: V2's catalog keys and V1's `source_url` are the same vocabulary.
        let collectionPayload = collections.map { collection in
            ReaderLibraryImport.Collection(id: collectionID(collection.id), name: collection.name,
                memberKeys: collection.memberKeys)
        }

        // Smart feeds: the terms, the scope, the filters and the exclusions V2 can express, as one T6 key.
        var smartPayload: [ReaderLibraryImport.Preset] = []
        for feed in smartFeeds {
            guard let definition = try? JSONDecoder().decode(SmartFeedDefinition.self,
                from: Data(feed.definitionJSON.utf8)) else {
                skippedSmartFeeds += 1
                continue
            }
            let id = presetID(feed.id)
            guard let key = contextKey(for: definition, presetID: .smartFeed(id)) else {
                skippedSmartFeeds += 1
                continue
            }
            if definition.sourceCollectionID != nil { droppedCollectionScopes += 1 }
            smartPayload.append(.init(id: id, name: feed.name, kind: .smartBookmark, key: key))
        }

        let payload = ReaderLibraryImport(bookmarkLists: importPayload.bookmarkLists,
            collections: collectionPayload, presets: smartPayload)
        let inserted = try ReaderLibraryStore(database: database).apply(payload, at: date)
        return Report(inserted: inserted, skippedBoxItems: skippedBoxItems, skippedBoxes: skippedBoxes,
            skippedPersistentSearchLists: skippedPersistentSearch, skippedCuratedFeeds: curatedCount,
            skippedSmartFeeds: skippedSmartFeeds, droppedCollectionScopes: droppedCollectionScopes,
            carriedCollections: collectionPayload.count, carriedSmartFeeds: smartPayload.count)
    }

    /// The T6 identity a V1 smart feed becomes. Nil when nothing about it can be activated: a preset with no
    /// terms, no filters and no exclusions would be an empty context the reader could not tell from "everything".
    public static func contextKey(forLegacyJSON json: String, presetID: ReaderPresetID) -> ContextKey? {
        guard let definition = try? JSONDecoder().decode(SmartFeedDefinition.self, from: Data(json.utf8)) else {
            return nil
        }
        return contextKey(for: definition, presetID: presetID)
    }

    static func contextKey(for definition: SmartFeedDefinition, presetID: ReaderPresetID) -> ContextKey? {
        let terms = (definition.requiredSearchTerms ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let query = (terms.isEmpty ? (definition.query ?? "") : terms.joined(separator: " "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scope: ReaderSearchScope? = {
            switch (definition.includeSources ?? true, definition.includeContents ?? true) {
            case (true, true): return .both
            case (true, false): return .sources
            case (false, true): return .contents
            case (false, false): return nil
            }
        }()
        let rules = (definition.excludedSearchTerms ?? []) + (definition.excludedKeywords ?? [])
        let exclusions = rules.isEmpty ? ReaderContentExclusions.disabled
            : ReaderContentExclusions(isEnabled: true, rules: rules)
        let filter = ReaderFilter(
            regionIDs: Set([definition.region].compactMap { $0 }),
            taxonomyNodeIDs: Set(definition.taxonomyNodeIDs ?? []),
            languages: Set(definition.languages ?? []),
            contentType: ReaderContentType(rawValue: definition.contentType ?? "") ?? .all,
            mood: ReaderMood(rawValue: definition.mood ?? "") ?? .all,
            exclusions: exclusions)
        guard let search = SearchContext(query: query) else {
            // No search text: the preset is its filters, and only if it has any.
            guard filter != .unrestricted else { return nil }
            return ContextKey(request: .main, preset: presetID, filter: filter)
        }
        return ContextKey(request: .search(search), preset: presetID, filter: filter, searchScope: scope ?? .both)
    }
}
