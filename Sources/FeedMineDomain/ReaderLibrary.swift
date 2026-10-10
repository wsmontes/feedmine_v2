//
// File: ReaderLibrary.swift
// Module: FeedMineDomain
//
// Responsibility:
// The reader's own library: named bookmark boxes (V1's bookmark lists), named source collections, and named
// presets (V1's Smart Bookmark and Curated Feed). It states identity, naming rules and ordering — nothing
// about storage, acquisition or layout.
//
// The preset's *content* is a T6 `ContextKey`: activating one is an ordinary context transition, so a saved
// search never grows a second feed engine behind the reader's back. Its identity inside that key is the T6
// `ReaderPresetID` payload (`.smartFeed(id)` / `.curatedFeed(id)` / `.collection(id)`), never a display name.
import Foundation

/// A named group of bookmarked publications. V1 called them bookmark lists; V2 boxes hold card *occurrences*
/// (the bookmark is a mark on a published card, not on a source), so a card may sit in several boxes.
public struct ReaderBookmarkList: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var position: Int

    public init(id: String, name: String, position: Int) {
        self.id = id; self.name = name; self.position = position
    }

    /// Default box id, the one a card lands in when the reader taps the bookmark control without choosing.
    public static let defaultID = "saved"

    public static func defaultList() -> ReaderBookmarkList {
        ReaderBookmarkList(id: defaultID, name: String(localized: "Salvos"), position: 0)
    }
}

/// A named group of catalog sources. Its identity is the `ReaderPresetID.collection(id)` payload, so a
/// collection can be *activated* as a feed context exactly like any other preset.
public struct ReaderCollection: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var position: Int

    public init(id: String, name: String, position: Int) {
        self.id = id; self.name = name; self.position = position
    }
}

/// A named saved context: V1's Smart Bookmark (born from a search) and Curated Feed (built by hand).
public struct ReaderPreset: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// V1's "Save as Smart Bookmark": the search that produced it is part of its key.
        case smartBookmark
        /// V1's Curated Feed: a feed the reader assembled and named.
        case curatedFeed
    }

    public let id: String
    public var name: String
    public var position: Int
    public let kind: Kind
    /// The whole identity it activates — the T6 key, including the search scope it was saved from.
    public let key: ContextKey
    /// T11: a curated feed's recipe. A smart bookmark has none (its rule is the search it was saved from), and a
    /// curated feed without one would be a name with nothing behind it.
    public let recipe: FeedRecipeDefinition?

    public init(id: String, name: String, kind: Kind, position: Int, key: ContextKey,
        recipe: FeedRecipeDefinition? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.position = position; self.key = key
        self.recipe = recipe
    }

    /// The preset identity this saved context activates. A preset whose key does not name itself cannot be
    /// activated without pretending to be another preset, so the pairing is stated once, here.
    public var presetID: ReaderPresetID {
        switch kind {
        case .smartBookmark: return .smartFeed(id)
        case .curatedFeed: return .curatedFeed(id)
        }
    }
}

/// A whole library to insert at once, as values. An import builds one of these and the store applies it in a
/// **single** transaction, so an interrupted import leaves nothing partial behind.
public struct ReaderLibraryImport: Hashable, Sendable {
    public struct BookmarkList: Hashable, Sendable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    public struct Collection: Hashable, Sendable {
        public let id: String
        public let name: String
        public let memberKeys: [String]
        public init(id: String, name: String, memberKeys: [String]) {
            self.id = id; self.name = name; self.memberKeys = memberKeys
        }
    }

    public struct Preset: Hashable, Sendable {
        public let id: String
        public let name: String
        public let kind: ReaderPreset.Kind
        public let key: ContextKey
        public let recipe: FeedRecipeDefinition?
        public init(id: String, name: String, kind: ReaderPreset.Kind, key: ContextKey,
            recipe: FeedRecipeDefinition? = nil) {
            self.id = id; self.name = name; self.kind = kind; self.key = key
            self.recipe = recipe
        }
    }

    public let bookmarkLists: [BookmarkList]
    public let collections: [Collection]
    public let presets: [Preset]

    public init(bookmarkLists: [BookmarkList] = [], collections: [Collection] = [], presets: [Preset] = []) {
        self.bookmarkLists = bookmarkLists; self.collections = collections; self.presets = presets
    }

    public var isEmpty: Bool { bookmarkLists.isEmpty && collections.isEmpty && presets.isEmpty }
}

/// What an import actually inserted. A second run of the same import reports zeroes: ids are stable, so a
/// repeated or interrupted import can never duplicate a box, a collection or a preset.
public struct ReaderLibraryImportReport: Hashable, Sendable {
    public let insertedBookmarkLists: Int
    public let insertedCollections: Int
    public let insertedPresets: Int
    public let insertedMemberships: Int

    public init(insertedBookmarkLists: Int, insertedCollections: Int, insertedPresets: Int,
        insertedMemberships: Int) {
        self.insertedBookmarkLists = insertedBookmarkLists
        self.insertedCollections = insertedCollections
        self.insertedPresets = insertedPresets
        self.insertedMemberships = insertedMemberships
    }
}

/// Naming and ordering rules shared by every library family. V1 let the reader name and reorder boxes and
/// collections; both must survive a relaunch, so positions are contiguous and assigned by one rule.
public enum ReaderLibraryRules {
    /// A usable name: trimmed, and never empty. V1 refused an empty name at the alert.
    public static func normalizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The positions a reorder assigns: contiguous from zero following `ids`, with anything `ids` does not name
    /// keeping its own relative order after them. A list that omits an id therefore cannot lose it.
    public static func positions(current: [String], reordered ids: [String]) -> [String: Int] {
        var seen = Set<String>()
        var ordered: [String] = []
        for id in ids where !seen.contains(id) {
            guard current.contains(id) else { continue }
            seen.insert(id); ordered.append(id)
        }
        ordered.append(contentsOf: current.filter { !seen.contains($0) })
        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })
    }
}
