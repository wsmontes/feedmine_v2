//
// File: FeedEditorialAssessment.swift
// Module: FeedMineEditorial
//
// Responsibility:
// The one place that reads a *source* the way a curated feed's "source balance" needs it: is it a recognized
// masthead, an institutional publisher, a specialist, a generic distributor — and how strong is the evidence.
// It is V1's `CuratedPreferenceEngine.editorialAssessment(for:)` — the same signals, the same weights, the same
// formula — reading V2's catalog facts (title, description, tags, host, quality, activity, nature).
//
// The signal lists below are V1's own curation data, copied verbatim: they are what makes the assessment
// comparable, and inventing new ones would silently change what "reference" means.
//
// Does not own: ranking (FeedRecipeResolution does), storage or any surface.
import Foundation

public struct FeedEditorialAssessment: Hashable, Sendable {
    public enum Style: String, CaseIterable, Hashable, Sendable {
        case reference
        case specialist
        case distinctive

        public var featureKey: String { "editorial:\(rawValue)" }
    }

    public let style: Style
    public let isRecognized: Bool
    public let isSpecialist: Bool
    /// 0…1, V1's own blend of technical quality, editorial authority, activity and directness.
    public let score: Double
    /// V1's `isEligible`: whether the source clears the quality floor its class implies.
    public let isEligible: Bool

    /// The keys this source matches, exactly as V1 built them: its style, plus `reference` when it is a
    /// recognized masthead, plus `specialist` when it is one, plus `distinctive` when it is neither.
    public var featureKeys: Set<String> {
        var keys: Set<String> = [style.featureKey]
        if isRecognized { keys.insert(Style.reference.featureKey) }
        if isSpecialist { keys.insert(Style.specialist.featureKey) }
        if !isRecognized && !isSpecialist { keys.insert(Style.distinctive.featureKey) }
        return keys
    }
}

public enum FeedEditorialReader {
    /// What the assessment reads. V2's catalog owns every field; nothing is fetched or guessed.
    public struct Facts: Hashable, Sendable {
        public let title: String
        public let description: String?
        public let tags: [String]
        public let host: String
        public let qualityScore: Int?
        public let activity: String?
        public let nature: String?

        public init(title: String, description: String? = nil, tags: [String] = [], host: String,
            qualityScore: Int? = nil, activity: String? = nil, nature: String? = nil) {
            self.title = title; self.description = description; self.tags = tags; self.host = host
            self.qualityScore = qualityScore; self.activity = activity; self.nature = nature
        }
    }

    public static func assess(_ source: Facts) -> FeedEditorialAssessment {
        let host = source.host.lowercased().replacingOccurrences(of: "www.", with: "")
        let identity = editorialText("\(source.title) \(host)")
        let context = editorialText([source.title, source.description ?? "", source.tags.joined(separator: " ")]
            .joined(separator: " "))

        let recognized = recognizedPublisherSignals.contains { identity.contains($0) }
        let institutional = [".edu", ".ac.uk", ".gov", ".int"].contains { host.hasSuffix($0) }
            || institutionalSignals.contains { context.contains($0) }
        let specialist = specialistSignals.contains { context.contains($0) }
        let hasPublishingPurpose = publishingSignals.contains { context.contains($0) }
        let genericHost = genericDistributionHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        _ = commercialSignals.contains { context.contains($0) }
        _ = aggregationSignals.contains { context.contains($0) } || excludedShowcaseHosts.contains(host)
        _ = genericSourceTitleSignals.contains { editorialText(source.title).contains($0) }

        let technicalQuality = min(1, max(0, Double(source.qualityScore ?? 70) / 100))
        let activityFactor: Double = switch source.activity?.lowercased() {
        case "prolific": 1
        case "active": 0.94
        case "quiet": 0.76
        case "dormant": 0.35
        default: 0.82
        }
        let authority: Double = recognized ? 1 : (institutional ? 0.92 : (specialist ? 0.83 : 0.70))
        let directPublisherFactor: Double = genericHost ? 0.62 : 1
        let score = min(1, technicalQuality * 0.30 + authority * 0.42 + activityFactor * 0.18
            + directPublisherFactor * 0.10)

        let evidenceFloor: Bool
        if recognized || institutional {
            evidenceFloor = technicalQuality >= 0.70
        } else if specialist && hasPublishingPurpose {
            evidenceFloor = technicalQuality >= 0.80
        } else {
            evidenceFloor = technicalQuality >= 0.87
        }

        let style: FeedEditorialAssessment.Style = recognized ? .reference : (specialist ? .specialist : .distinctive)
        return FeedEditorialAssessment(style: style, isRecognized: recognized, isSpecialist: specialist,
            score: score, isEligible: evidenceFloor)
    }

    /// V1's own normalisation for editorial text: ASCII, lowercased, dashes and underscores as spaces.
    static func editorialText(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    static let recognizedPublisherSignals = [
        "associated press", "ap news", "reuters", "bbc", "npr", "pbs",
        "cbc", "radio canada", "abc news", "abc australia", "sbs australia",
        "deutsche welle", "france 24", "radio france", "arte", "al jazeera",
        "euronews", "the guardian", "financial times", "the economist",
        "bloomberg", "propublica", "pew research center", "the conversation",
        "nature journal", "nature.com", "science magazine", "science.org",
        "scientific american", "new scientist",
        "national geographic", "smithsonian", "mit technology review", "wired",
        "ars technica", "nasa", "european space agency", "world health organization",
        "united nations", "unesco", "agencia brasil", "agencia efe", "nexo jornal",
        "folha de s paulo", "estadao", "publico", "rtp", "el pais", "rtve",
        "la nacion", "le monde", "franceinfo", "tagesschau", "der spiegel",
        "die zeit", "deutschlandfunk", "ansa", "rai news", "la repubblica",
        "corriere della sera", "il sole 24 ore", "nhk", "asahi shimbun",
        "mainichi", "nikkei", "yomiuri", "svt", "sveriges radio", "nrk",
        "danmarks radio", "yle", "ruv", "channel newsasia", "the hindu",
        "indian express", "dawn", "rappler", "yonhap", "africa check",
        "daily maverick", "mail guardian", "premium times", "balkan insight",
    ]

    static let institutionalSignals = [
        "university", "universidade", "universidad", "universite", "universitat",
        "universita", "universiteit", "universitet", "college", "academy",
        "institute", "instituto", "institut", "research center", "research centre",
        "museum", "museu", "museo", "library", "biblioteca", "foundation",
        "fundacao", "fondation", "public radio", "public media", "public broadcaster",
        "national radio", "national museum", "national library", "observatory",
        "medical journal", "scientific journal", "fact check", "fact checking",
    ]

    static let specialistSignals = [
        "research", "science", "scientific", "analysis", "in depth", "longform",
        "journal", "review", "criticism", "essays", "history", "literature",
        "architecture", "design", "medicine", "medical", "law", "economics",
        "philosophy", "documentary", "investigation", "investigative",
        "data journalism", "expert", "scholar", "academic",
    ]

    static let publishingSignals = [
        "news", "reporting", "journalism", "coverage", "stories", "interviews",
        "analysis", "explores", "magazine", "journal", "documentary", "reviews",
        "criticism", "essays", "research", "education", "history", "culture",
        "science", "music", "books", "literature", "sports", "cooking",
    ]

    static let commercialSignals = [
        "coupon", "discount code", "affiliate", "buy now", "online store",
        "real estate listings", "marketing agency", "sales funnel", "casino",
        "betting tips", "forex signals", "product promotion", "distributor",
        "sponsored offers", "price alerts", "luxury products",
    ]

    static let aggregationSignals = [
        "news aggregator", "content aggregator", "feed aggregating all",
        "aggregates stories", "aggregates articles",
    ]

    static let genericSourceTitleSignals = [
        "latest newsfeed articles", "rss feed", "all articles",
        "top stories google news",
    ]

    static let excludedShowcaseHosts = [
        "news.google.com", "flipboard.com",
    ]

    static let genericDistributionHosts = [
        "anchor.fm", "buzzsprout.com", "libsyn.com", "podbean.com",
        "spotify.com", "soundcloud.com", "simplecast.com", "acast.com",
        "megaphone.fm", "transistor.fm", "rss.com", "ivoox.com",
"podomatic.com", "redcircle.com",
    ]
}
