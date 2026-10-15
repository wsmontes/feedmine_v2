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
// A nonconvertible V1 definition stays in the recoverable archive. Legacy bookmark IDs
// never become publication IDs. Conversion and the receipt are owned by ReaderLibraryStore.
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

    /// Capture V1's namespaced settings as recoverable facts; do not mutate UserDefaults.
    /// Values are wrapped because JSONSerialization does not accept top-level fragments by default.
    public static func personalDefaults(_ defaults: UserDefaults) throws -> [LegacyPersonalArchiveRecord] {
        let names: Set<String> = [
            "toggleDisabled", "toggleEnabledOverrides", "hasInitializedSourceDefaults",
            "filterRegion", "filterTaxonomyNodes", "filterContentType", "filterMood",
            "filterSetAt", "filterAutoExpire", "filterLanguages", "hasInitializedLanguageDefault",
            "circadianPaletteOn", "paletteFamily", "circadianTypographyOn", "fontStyle", "fontSize", "nightMode",
            "prefetchImages", "showDebugBar", "hasSeenOnboarding", "contentFiltersEnabled",
            "sessionStreak", "sessionMinutesToday", "daysWithAppTotal", "lastOpenDate",
            "activePreset", "last_whats_new_seen_at", "lastHeavyMaintenance",
            "lastPodcastItemID", "lastPodcastPosition"
        ]
        let values = defaults.dictionaryRepresentation()
        return try names.sorted().compactMap { key in
            guard let value = values[key] else { return nil }
            // UserDefaults permits Date/Data and nested property lists that are not JSON values.
            // Preserve their exact property-list representation instead of dropping them or failing upgrade.
            let plist = try PropertyListSerialization.data(fromPropertyList: ["value": value],
                format: .binary, options: 0)
            let json = try String(data: JSONSerialization.data(withJSONObject: [
                "format": "binary-plist-base64", "payload": plist.base64EncodedString()
            ], options: [.sortedKeys]), encoding: .utf8)
            guard let json else { return nil }
            return LegacyPersonalArchiveRecord(category: "user_defaults", key: key,
                payloadJSON: json, status: "recoverable")
        }
    }

    /// Only exact V1 feed identities can be applied to V2's initial chosen candidate keys.
    /// Group/category keys are preserved intact, never mistaken for source addresses.
    static func initialKeys(_ proposed: [String], defaults: UserDefaults,
        importedSources: [LegacyPersonalImportedSource]) -> [String] {
        let disabled = Set(defaults.stringArray(forKey: "toggleDisabled") ?? [])
        let explicitlyEnabled = Set(defaults.stringArray(forKey: "toggleEnabledOverrides") ?? [])
        let disabledImports = Set(importedSources.filter { !$0.enabled }.map(\.identity))
        return proposed.filter { key in
            let canonical = FeedAddress.identity(key)
            let original = "url:" + canonical
            if disabled.contains(original) || disabled.contains("url:" + key) { return false }
            if disabledImports.contains(key) || disabledImports.contains(canonical) { return false }
            // V1 per-feed enabled overrides matter for parent-disable policies, whose raw
            // keys remain archived until taxonomy equivalence is explicitly proved.
            _ = explicitlyEnabled.contains(original)
            return true
        }
    }

    @discardableResult
    public static func run(reader: LegacyUserStateReader, into database: RuntimeDatabase,
        defaults: UserDefaults = .standard, initialSourceKeys: [String]? = nil,
        at date: Date = Date()) throws -> Report {
        let state = try reader.personalState()
        let preferences = try personalDefaults(defaults)
        var skippedPersistentSearch = 0, skippedSmartFeeds = 0, droppedScopes = 0
        for list in state.lists where list.carriesDeadPersistentSearch { skippedPersistentSearch += 1 }

        // The V1 scope cannot be expressed by V2's smart-feed request. Never install a
        // silently broadened preset; its complete V1 JSON stays in the archival authority.
        var smartPayload: [ReaderLibraryImport.Preset] = []
        for feed in state.smartFeeds {
            guard let definition = try? JSONDecoder().decode(SmartFeedDefinition.self,
                from: Data(feed.definitionJSON.utf8)) else {
                skippedSmartFeeds += 1
                continue
            }
            if definition.sourceCollectionID != nil {
                droppedScopes += 1
                skippedSmartFeeds += 1
                continue
            }
            let id = presetID(feed.id)
            guard let key = contextKey(for: definition, presetID: .smartFeed(id)) else {
                skippedSmartFeeds += 1
                continue
            }
            smartPayload.append(.init(id: id, name: feed.name, kind: .smartBookmark, key: key))
        }
        let imported = try ReaderLibraryStore(database: database).applyLegacyPersonalState(state,
            payload: ReaderLibraryImport(presets: smartPayload), preferences: preferences,
            initialSourceKeys: initialSourceKeys.map {
                initialKeys($0, defaults: defaults, importedSources: state.importedSources)
            }, at: date)
        return Report(inserted: imported,
            skippedBoxItems: 0, skippedBoxes: 0,
            skippedPersistentSearchLists: skippedPersistentSearch,
            skippedCuratedFeeds: state.archived.filter { $0.category == "curated_feed" }.count,
            skippedSmartFeeds: skippedSmartFeeds, droppedCollectionScopes: droppedScopes,
            carriedCollections: state.collections.count,
            carriedSmartFeeds: smartPayload.count)
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
