//
// File: FeedRecipeResolution.swift
// Module: FeedMineEditorial
//
// Responsibility:
// Turning a curated feed's recipe into a ranking: how much each *source* should weigh, given what the catalogue
// says about it. V1's own formula (`CuratedPreferenceEngine.sourceMultiplier`), with V1's own key vocabulary
// (`topic:`, `region:`, `media:`, `editorial:`, `nature:`, `scope:`).
//
// It is pure: no clock, no storage, no catalogue handle. The caller states each source's facts (which the
// catalogue owns) and the recipe; the result is a number per source, so a test can pin it exactly and a session
// can rank with it without growing a second editorial engine.
import Foundation
import FeedMineDomain

public enum FeedRecipeResolution {
    /// What a source carries, as the catalogue states it. The editorial assessment is the caller's, because it
    /// reads the same facts through `FeedEditorialReader`.
    public struct SourceFacts: Hashable, Sendable {
        /// The source's identity: the catalogue key, which is also how the session addresses its feeds.
        public let identity: String
        /// The taxonomy node keys it is placed under (topics, countries, sections).
        public let nodeKeys: [String]
        /// `text`, `audio` or `video`.
        public let mediaKind: String
        public let nature: String?
        public let qualityScore: Int?
        public let editorial: FeedEditorialAssessment?

        public init(identity: String, nodeKeys: [String] = [], mediaKind: String = "text",
            nature: String? = nil, qualityScore: Int? = nil,
            editorial: FeedEditorialAssessment? = nil) {
            self.identity = identity
            self.nodeKeys = nodeKeys; self.mediaKind = mediaKind
            self.nature = nature; self.qualityScore = qualityScore; self.editorial = editorial
        }
    }

    /// The taxonomy placements a source has (its `topic:`/`region:` keys). A source without one is outside the
    /// vocabulary a recipe speaks, which V1 treated as exactly neutral.
    public static func placementKeys(for source: SourceFacts) -> Set<String> {
        Set(source.nodeKeys.map { node in
            let parts = node.lowercased().split(separator: "/").map(String.init)
            return parts.count >= 2 && (parts[0] == "countries" || parts[0] == "regions")
                ? "region:\(parts[0])/\(parts[1])" : "topic:\(node.lowercased())"
        })
    }

    /// Every key a source matches, built the way V1 built them: the topics it is placed under, its media kind,
    /// its editorial natures, its own nature, and its region scope.
    public static func featureKeys(for source: SourceFacts) -> Set<String> {
        var keys: Set<String> = []
        for node in source.nodeKeys {
            let parts = node.lowercased().split(separator: "/").map(String.init)
            if parts.count >= 2, parts[0] == "countries" || parts[0] == "regions" {
                keys.insert("region:\(parts[0])/\(parts[1])")
            } else {
                keys.insert("topic:\(node.lowercased())")
            }
        }
        keys.insert("media:\(source.mediaKind.lowercased())")
        if let nature = source.nature?.trimmingCharacters(in: .whitespacesAndNewlines), !nature.isEmpty {
            keys.insert("nature:\(nature.lowercased())")
        }
        if let editorial = source.editorial { keys.formUnion(editorial.featureKeys) }
        let isRegional = source.nodeKeys.contains { $0.lowercased().hasPrefix("countries/") }
        keys.insert(isRegional ? "scope:regional" : "scope:global")
        return keys
    }

    /// V1's own multiplier: the recipe's weights, scaled by confidence and by the scope factor, exponentiated
    /// with the discovery flattening, then nudged by the catalogue's quality score. A source the recipe's
    /// vocabulary never touches weighs exactly 1 — the centre, not a penalty.
    public static func multiplier(for source: SourceFacts, recipe: FeedRecipeDefinition) -> Double {
        // V1's own guard: a source the taxonomy does not place anywhere weighs exactly 1 — the recipe cannot
        // say anything about it, so not even its quality moves it.
        guard placementKeys(for: source).isEmpty == false else { return 1 }
        let keys = featureKeys(for: source)
        var score = 0.0
        for key in keys {
            // A recipe keeps no learned evidence, so a key's confidence is zero and the weight keeps V1's
            // 0.25 floor. (When V2 learns from opens, evidence supplies the rest of that term.)
            let confidence = 0.0
            let scopeScale = key.hasPrefix("scope:") ? 0.5 : 1
            score += recipe.weight(forKey: key) * (0.25 + confidence * 0.75) * scopeScale
        }
        // Higher discovery keeps neutral and weakly preferred sources closer to the centre.
        let exploitation = 1 - recipe.discoveryLevel * 0.42
        let learned = exp(score * 0.19 * exploitation)
        let quality = 0.9 + (Double(source.qualityScore ?? 70) / 100) * 0.2
        return min(3, max(0.42, learned * quality))
    }

    /// The multipliers a session ranks with, keyed by each source's identity. A source that weighs exactly 1 is
    /// left out, exactly as V1 left it out.
    public static func multipliers(for sources: [SourceFacts],
        recipe: FeedRecipeDefinition) -> [String: Double] {
        var result: [String: Double] = [:]
        for source in sources {
            let value = multiplier(for: source, recipe: recipe)
            if abs(value - 1) > 0.001 { result[source.identity] = value }
        }
        return result
    }

    /// The filter the recipe states, as V2's own criteria: its languages and its content type. Everything else
    /// a recipe says is a *weight*, which is the ranking's business and not a criterion's.
    public static func filter(for recipe: FeedRecipeDefinition) -> ReaderFilter {
        ReaderFilter(languages: recipe.languageCriterion, contentType: recipe.contentTypeCriterion)
    }

    /// V1's `autoName()`: the feed is named by what the reader asked for more of. One topic is its own name, two
    /// or more are "A & B", and nothing is "My Feed".
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
