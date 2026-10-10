//
// File: ReaderFilter.swift
// Module: FeedMineDomain
//
// Responsibility:
//   The reader's filter criteria as one normalized value, and the vocabulary V1 used to express them.
//
// Owns:
//   ReaderFilter, ReaderContentType, ReaderMood (with V1's keyword rule), ReaderContentExclusions,
//   ReaderSearchScope, ReaderPresetID and the canonical identity encoding used by ContextKey.
//
// Does not own:
//   Applying a filter to supply (Editorial), persisting a selection (Persistence), the draft the reader
//   is editing (UI) or any expiry clock (Composition).
//
// Design: docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md (§2)
//

import Foundation

/// Content kinds exactly as V1 named them (`FeedLoader.ContentType`, which also supplied the icons).
public enum ReaderContentType: String, CaseIterable, Hashable, Codable, Sendable {
    case all = "All"
    case text = "Articles"
    case video = "Videos"
    case audio = "Podcasts"
    case forum = "Forums"

    public var icon: String {
        switch self {
        case .all: "circle.grid.3x3.fill"
        case .text: "doc.text.fill"
        case .video: "play.rectangle.fill"
        case .audio: "headphones"
        case .forum: "bubble.left.and.bubble.right.fill"
        }
    }
}

/// Moods exactly as V1 named them, with V1's own determination rule: a keyword test over the headline.
/// V1 derived mood from the title (`FeedLoader.MoodFilter.matches(_:)` 286–305); the sets below are
/// copied verbatim, so mood stays honestly answerable without catalog metadata.
public enum ReaderMood: String, CaseIterable, Hashable, Codable, Sendable {
    case all = "All"
    case serious = "Serious"
    case fun = "Fun"
    case technical = "Technical"
    case inspiring = "Inspiring"

    public var icon: String {
        switch self {
        case .all: "circle.grid.3x3.fill"
        case .serious: "newspaper.fill"
        case .fun: "sparkles"
        case .technical: "gearshape.2.fill"
        case .inspiring: "sun.max.fill"
        }
    }

    /// V1's keyword sets, verbatim. `all` matches everything and has no set.
    public var keywords: [String] {
        switch self {
        case .all: []
        case .serious: ["crisis", "war", "death", "killed", "attack", "emergency", "ban", "ruling", "court"]
        case .fun: ["fun", "amazing", "incredible", "wow", "hilarious", "funny", "adorable", "genius", "brilliant"]
        case .technical: ["ai", "code", "data", "algorithm", "startup", "tech", "software", "hardware", "api",
            "quantum", "robot", "chip"]
        case .inspiring: ["discovered", "breakthrough", "solved", "cure", "hope", "inspiring", "hero",
            "changed", "revolutionary"]
        }
    }

    /// V1's rule: case-insensitive substring test over the title. A missing title matches nothing.
    public func matches(_ title: String?) -> Bool {
        guard self != .all else { return true }
        guard let title, !title.isEmpty else { return false }
        let lower = title.lowercased()
        return keywords.contains { lower.contains($0) }
    }
}

/// Keyword exclusions (V1's content filters). They *hide* content and never expire.
public struct ReaderContentExclusions: Hashable, Codable, Sendable {
    public let isEnabled: Bool
    /// Lowercased, trimmed, deduplicated, sorted: canonical order so equivalent rules are one identity.
    public let rules: [String]

    public static let disabled = ReaderContentExclusions(isEnabled: false, rules: [])

    public init(isEnabled: Bool, rules: [String]) {
        self.isEnabled = isEnabled
        self.rules = Self.normalize(rules)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            rules: try container.decode([String].self, forKey: .rules))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(rules, forKey: .rules)
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, rules }

    public static func normalize(_ rules: [String]) -> [String] {
        Array(Set(rules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })).sorted()
    }

    /// True when this rule set hides a text. Disabled exclusions hide nothing.
    public func excludes(_ text: String?) -> Bool {
        guard isEnabled, !rules.isEmpty, let text, !text.isEmpty else { return false }
        let lower = text.lowercased()
        return rules.contains { lower.contains($0) }
    }
}

/// What a search looks through (V1 `searchIncludesSources` / `searchIncludesContents`).
public enum ReaderSearchScope: String, CaseIterable, Hashable, Codable, Sendable {
    case sources
    case contents
    case both

    public var includesSources: Bool { self != .contents }
    public var includesContents: Bool { self != .sources }
}

/// Which named selection the reader is on. V1's `PresetSelector`, without the payload duplication: the
/// id carries the identity, the name stays a display concern.
public enum ReaderPresetID: Hashable, Codable, Sendable {
    case everything
    case lastClicked
    case editorial(String)
    case collection(String)
    case smartFeed(String)
    case curatedFeed(String)

    /// Stable, order-independent identity text. Payloads are opaque external ids, never names.
    public var identityText: String {
        switch self {
        case .everything: "everything"
        case .lastClicked: "lastClicked"
        case .editorial(let slug): "editorial:\(slug)"
        case .collection(let id): "collection:\(id)"
        case .smartFeed(let id): "smartFeed:\(id)"
        case .curatedFeed(let id): "curatedFeed:\(id)"
        }
    }

    public var isCurated: Bool { if case .curatedFeed = self { return true } else { return false } }
    public var isSmart: Bool { if case .smartFeed = self { return true } else { return false } }
    public var isCollection: Bool { if case .collection = self { return true } else { return false } }
}

/// The reader's criteria as one normalized value. Criterion groups combine with **AND**; an empty group
/// means "unrestricted", so the default filter is exactly today's unfiltered feed.
public struct ReaderFilter: Hashable, Codable, Sendable {
    public let regionIDs: Set<String>
    public let taxonomyNodeIDs: Set<String>
    public let languages: Set<String>
    public let contentType: ReaderContentType
    public let mood: ReaderMood
    public let exclusions: ReaderContentExclusions

    public static let unrestricted = ReaderFilter()

    public init(regionIDs: Set<String> = [], taxonomyNodeIDs: Set<String> = [], languages: Set<String> = [],
        contentType: ReaderContentType = .all, mood: ReaderMood = .all,
        exclusions: ReaderContentExclusions = .disabled) {
        self.regionIDs = Self.normalizeSet(regionIDs)
        self.taxonomyNodeIDs = Self.normalizeSet(taxonomyNodeIDs)
        self.languages = Self.normalizeSet(languages)
        self.contentType = contentType
        self.mood = mood
        self.exclusions = exclusions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(regionIDs: Set(try container.decode([String].self, forKey: .regionIDs)),
            taxonomyNodeIDs: Set(try container.decode([String].self, forKey: .taxonomyNodeIDs)),
            languages: Set(try container.decode([String].self, forKey: .languages)),
            contentType: try container.decode(ReaderContentType.self, forKey: .contentType),
            mood: try container.decode(ReaderMood.self, forKey: .mood),
            exclusions: try container.decode(ReaderContentExclusions.self, forKey: .exclusions))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(regionIDs.sorted(), forKey: .regionIDs)
        try container.encode(taxonomyNodeIDs.sorted(), forKey: .taxonomyNodeIDs)
        try container.encode(languages.sorted(), forKey: .languages)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(mood, forKey: .mood)
        try container.encode(exclusions, forKey: .exclusions)
    }

    /// The exclusions that actually hide something. An enabled set with no rules filters nothing, so it is
    /// a preference, not a criterion: enabling it must not change the context identity (a no-op
    /// transition would otherwise reload the reader's feed).
    public var effectiveExclusionRules: [String]? {
        exclusions.isEnabled && !exclusions.rules.isEmpty ? exclusions.rules : nil
    }

    /// True when nothing is filtered: the default key must equal the unfiltered surface's key.
    public var isUnrestricted: Bool {
        regionIDs.isEmpty && taxonomyNodeIDs.isEmpty && languages.isEmpty
            && contentType == .all && mood == .all && effectiveExclusionRules == nil
    }

    /// Canonical, deterministic identity text for `ContextKey`. Equivalent selections — including any
    /// ordering of the same sets — produce byte-identical text.
    public var identityText: String {
        // Written as separate steps: the single-expression form defeats the type checker.
        let regions: String = "regions=" + regionIDs.sorted().joined(separator: ",")
        let taxonomy: String = "taxonomy=" + taxonomyNodeIDs.sorted().joined(separator: ",")
        let languageList: String = "languages=" + languages.sorted().joined(separator: ",")
        let type: String = "type=" + contentType.rawValue
        let moodValue: String = "mood=" + mood.rawValue
        let exclusionsValue: String = "exclusions=" + (effectiveExclusionRules?.joined(separator: "|") ?? "-")
        return [regions, taxonomy, languageList, type, moodValue, exclusionsValue].joined(separator: ";")
    }

    private static func normalizeSet(_ values: Set<String>) -> Set<String> {
        Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private enum CodingKeys: String, CodingKey {
        case regionIDs, taxonomyNodeIDs, languages, contentType, mood, exclusions
    }
}
