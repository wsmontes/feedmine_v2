//
// File: FeedRecipeDefinition.swift
// Module: FeedMineDomain
//
// Responsibility:
// A curated feed's recipe: what the reader answered in the Composer/onboarding, as a value. V1 kept the same
// fields (`Models/FeedRecipeDefinition.swift`) and the same *weight key* vocabulary — `topic:<key>`,
// `region:<key>`, `media:<kind>`, `nature:<key>` — which is what lets a recipe keep its meaning.
//
// The keys are V2's own identities: a region key is a catalog node key (`countries/br`), a topic key is a topic
// node key, and a media key names a kind the reader can filter by. Nothing here decides anything: the
// *resolution* of a recipe into a selection policy belongs to Editorial, so a view can never grow a second
// editorial engine.
import Foundation

/// V1's three-level answer, with its own two labels: a topic row is "Less / Normal / More" and a source balance
/// row is "Less / Balanced / More".
public enum ReaderPreferenceLevel: String, CaseIterable, Codable, Sendable {
    case less
    case neutral
    case more

    public var topicLabel: String {
        switch self {
        case .less: return String(localized: "Menos")
        case .neutral: return String(localized: "Normal")
        case .more: return String(localized: "Mais")
        }
    }

    public var balanceLabel: String {
        switch self {
        case .less: return String(localized: "Menos")
        case .neutral: return String(localized: "Equilibrado")
        case .more: return String(localized: "Mais")
        }
    }

    /// V1's own cycle for a row the reader taps: normal → more → less → normal.
    public func next() -> ReaderPreferenceLevel {
        switch self {
        case .neutral: return .more
        case .more: return .less
        case .less: return .neutral
        }
    }

    /// V1's `profileWeight`: an answer weighs ±1.5, and "normal" weighs nothing at all.
    public var weight: Double {
        switch self {
        case .less: return -1.5
        case .neutral: return 0
        case .more: return 1.5
        }
    }
}

/// The kinds of item a recipe can ask for. V2's own filter vocabulary owns the cases, so a recipe and a filter
/// cannot disagree about what "podcasts" means.
public enum ReaderRecipeMediaType: String, CaseIterable, Codable, Sendable {
    case article
    case podcast
    case video

    public var displayName: String {
        switch self {
        case .article: return String(localized: "Artigos")
        case .podcast: return String(localized: "Podcasts")
        case .video: return String(localized: "Vídeo")
        }
    }

    /// The key the *resolver* uses for this kind (V1 maps its own `article`/`podcast`/`video` onto
    /// `media:text`/`media:audio`/`media:video`), kept so a stored recipe's weights keep their meaning.
    public var featureKey: String {
        switch self {
        case .article: return "media:text"
        case .podcast: return "media:audio"
        case .video: return "media:video"
        }
    }

    /// The filter criterion the kind is, when one can express it.
    public var contentType: ReaderContentType {
        switch self {
        case .article: return .text
        case .podcast: return .audio
        case .video: return .video
        }
    }
}

public struct FeedRecipeDefinition: Hashable, Codable, Sendable {
    public static let currentModelVersion = 1

    /// Language codes, lowercased to their primary subtag and sorted — V1 normalised them the same way.
    public var languages: [String]
    /// 0…1: how far outside the reader's own choices the feed may look.
    public var discoveryLevel: Double
    /// Catalog node keys the reader answered on, by level.
    public var topicPreferences: [String: ReaderPreferenceLevel]
    /// Source-balance answers, keyed the way V1 keyed them (`nature:<key>`, `media:<kind>`).
    public var editorialPreferences: [String: ReaderPreferenceLevel]
    public var mediaTypes: Set<ReaderRecipeMediaType>
    /// V1's `adjustFromOpens`: whether later reading adjusts the recipe.
    public var adjustFromOpens: Bool
    public var modelVersion: Int

    public init(languages: [String] = [], discoveryLevel: Double = 0.5,
        topicPreferences: [String: ReaderPreferenceLevel] = [:],
        editorialPreferences: [String: ReaderPreferenceLevel] = [:],
        mediaTypes: Set<ReaderRecipeMediaType> = [.article, .podcast, .video],
        adjustFromOpens: Bool = false, modelVersion: Int = FeedRecipeDefinition.currentModelVersion) {
        self.languages = Array(Set(languages.map(Self.primarySubtag))).sorted()
        self.discoveryLevel = min(1, max(0, discoveryLevel))
        self.topicPreferences = topicPreferences
        self.editorialPreferences = editorialPreferences
        // An empty set is not a recipe that asks for nothing: it is V1's own default, every kind.
        self.mediaTypes = mediaTypes.isEmpty ? [.article, .podcast, .video] : mediaTypes
        self.adjustFromOpens = adjustFromOpens
        self.modelVersion = modelVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = FeedRecipeDefinition()
        self.init(
            languages: try container.decodeIfPresent([String].self, forKey: .languages) ?? standard.languages,
            discoveryLevel: try container.decodeIfPresent(Double.self, forKey: .discoveryLevel)
                ?? standard.discoveryLevel,
            topicPreferences: try container.decodeIfPresent([String: ReaderPreferenceLevel].self,
                forKey: .topicPreferences) ?? [:],
            editorialPreferences: try container.decodeIfPresent([String: ReaderPreferenceLevel].self,
                forKey: .editorialPreferences) ?? [:],
            mediaTypes: try container.decodeIfPresent(Set<ReaderRecipeMediaType>.self, forKey: .mediaTypes)
                ?? standard.mediaTypes,
            adjustFromOpens: try container.decodeIfPresent(Bool.self, forKey: .adjustFromOpens)
                ?? standard.adjustFromOpens,
            modelVersion: try container.decodeIfPresent(Int.self, forKey: .modelVersion)
                ?? FeedRecipeDefinition.currentModelVersion)
    }

    /// V1's "Start broad" / "Reset to neutral": everything at its middle, every kind, the reader's language.
    public static func neutral(languages: [String] = []) -> FeedRecipeDefinition {
        FeedRecipeDefinition(languages: languages, discoveryLevel: 0.55, topicPreferences: [:],
            editorialPreferences: [:], mediaTypes: [.article, .podcast, .video], adjustFromOpens: false)
    }

    static func primarySubtag(_ code: String) -> String {
        code.lowercased().split(separator: "-").first.map(String.init) ?? code.lowercased()
    }

    // MARK: - Weight keys

    /// The weight keys a recipe states, as V1's namespaced vocabulary. `topic:` and `region:` name catalog node
    /// keys; `media:` names a kind; everything else the reader answered on is carried under its own namespace.
    public var weightKeys: [String] {
        var keys: [String] = topicPreferences.keys.sorted()
        keys += editorialPreferences.keys.sorted()
        keys += mediaTypes.map(\.featureKey).sorted()
        return keys
    }

    /// 0 for a key the recipe says nothing about, ±1 for an answer. Media kinds the recipe asks for weigh in
    /// positively, and a kind it does not offer is simply absent.
    public func weight(forKey key: String) -> Double {
        if let level = topicPreferences[key] ?? editorialPreferences[key] { return level.weight }
        if key.hasPrefix("media:") {
            // V1's own asymmetry: a kind the reader kept carries no weight (it is the default), and a kind they
            // *removed* carries −3, the strongest negative a profile can hold.
            guard let kind = ReaderRecipeMediaType.allCases.first(where: { $0.featureKey == key }) else {
                return 0
            }
            return mediaTypes.contains(kind) ? 0 : -3
        }
        return 0
    }

    /// The languages the recipe asks for, as the filter states them.
    public var languageCriterion: Set<String> { Set(languages) }

    /// The content types the recipe asks for. All three kinds is "no criterion", which is what a filter's `.all`
    /// means; one or two kinds is a real criterion.
    public var contentTypeCriterion: ReaderContentType {
        guard mediaTypes.count < ReaderRecipeMediaType.allCases.count else { return .all }
        let kinds = mediaTypes.map(\.contentType)
        return kinds.count == 1 ? kinds[0] : .all
    }
}

/// V1's `autoName()`: the feed is named by what the reader asked for more of. One topic is its own name, two or
/// more are "A & B", and nothing is "My Feed". It lives here so the resolver and the Composer cannot name the
/// same recipe differently.
public enum FeedRecipeNaming {
    public static func suggestedName(for recipe: FeedRecipeDefinition, names: [String: String] = [:]) -> String {
        let more = recipe.topicPreferences.filter { $0.value == .more }.keys.sorted()
        let labels = more.map { key -> String in
            if let name = names[key] { return name }
            return key.hasPrefix("topic:") ? String(key.dropFirst("topic:".count)) : key
        }
        switch labels.count {
        case 0: return String(localized: "Meu feed")
        case 1: return labels[0]
        default: return labels.prefix(2).joined(separator: " & ")
        }
    }
}

/// What a curated feed *is*, for the surface that inspects it (V1's own "capô"): its name, the recipe's shape in
/// words the reader recognizes, and how many answers stand behind it.
public struct CuratedFeedSummary: Hashable, Sendable {
    public let name: String
    public let languages: [String]
    public let mediaTypes: [ReaderRecipeMediaType]
    public let discoveryLevel: Double
    public let adjustFromOpens: Bool
    /// The answers that count, strongest first: the reader's own choices, never a derived guess.
    public let answers: [Answer]

    public struct Answer: Hashable, Sendable {
        public let key: String
        public let level: ReaderPreferenceLevel
        public let isTopic: Bool

        public init(key: String, level: ReaderPreferenceLevel, isTopic: Bool) {
            self.key = key; self.level = level; self.isTopic = isTopic
        }
    }

    public init(name: String, recipe: FeedRecipeDefinition) {
        self.name = name
        self.languages = recipe.languages
        self.mediaTypes = recipe.mediaTypes.sorted { $0.rawValue < $1.rawValue }
        self.discoveryLevel = recipe.discoveryLevel
        self.adjustFromOpens = recipe.adjustFromOpens
        let topics = recipe.topicPreferences.map { Answer(key: $0.key, level: $0.value, isTopic: true) }
        let others = recipe.editorialPreferences.map { Answer(key: $0.key, level: $0.value, isTopic: false) }
        self.answers = (topics + others).sorted {
            abs($0.level.weight) == abs($1.level.weight) ? $0.key < $1.key
                : abs($0.level.weight) > abs($1.level.weight)
        }
    }
}
