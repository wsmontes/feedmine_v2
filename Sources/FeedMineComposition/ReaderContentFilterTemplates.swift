//
// File: ReaderContentFilterTemplates.swift
// Module: FeedMineComposition
//
// Responsibility:
// V1's own content-filter templates, read from the catalogue V1 shipped (`content_filter_templates.json`, copied
// verbatim into the app's resources) and resolved the way V1 resolved them: a template's name and its keywords
// come from the reader's locale, with English always included, so a Portuguese reader hides Portuguese *and*
// English words for the same subject.
//
// The value type lives here rather than in Domain because it is app data — a bundled file — not a rule of the
// domain; the policy that turns templates plus the reader's own rules into exclusions is pure and lives beside
// it (`ReaderContentFilterPolicy`).
//
// Does not own: where the reader's choices are stored (Persistence/Settings), applying the rules (Editorial) or
// the surface that edits them (UI).
import Foundation
import FeedMineDomain

/// One template exactly as V1 shipped it: a key, its names and its keyword lists, both per locale.
public struct ReaderContentFilterTemplate: Hashable, Sendable, Identifiable {
    public let key: String
    /// locale → display name.
    public let names: [String: String]
    /// locale → keywords.
    public let keywords: [String: [String]]

    public var id: String { key }

    public init(key: String, names: [String: String], keywords: [String: [String]]) {
        self.key = key
        self.names = names
        self.keywords = keywords
    }

    /// V1's `resolvedName`: the locale's own name, else the base language's, else English, else the key.
    public func name() -> String { name(languages: Self.preferredLanguages) }

    public func name(languages: [String]) -> String {
        for candidate in languages {
            if let name = names[candidate] { return name }
        }
        return names["en"] ?? key.capitalized
    }

    /// V1's `resolvedKeywords`: English always, plus the locale's and the base language's lists.
    public func rules() -> [String] { rules(languages: Self.preferredLanguages) }

    public func rules(languages: [String]) -> [String] {
        var lists: [[String]] = []
        for candidate in languages {
            if let list = keywords[candidate] { lists.append(list) }
        }
        lists.append(keywords["en"] ?? [])
        return ReaderContentExclusions.normalize(lists.flatMap { $0 })
    }

    /// The reader's language and its base language, in that order — never a language they do not read.
    ///
    /// V1 read `Locale.current.language.languageCode` and so does this: the app's *content* language is the
    /// reader's, and this package's own bundle carries no localizations, so asking it for a preferred
    /// localization could only ever answer English. A test states the locale explicitly rather than borrowing the
    /// host's.
    public static func preferredLanguages(for locale: Locale = .current) -> [String] {
        var codes: [String] = []
        // The locale's own identifier, not its bare language code: V1's catalogue keys carry region and script
        // forms too (`zh-Hans`, `zh-Hant`), and `languageCode` alone would never reach them.
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        codes.append(identifier)
        if let base = identifier.split(separator: "-").first.map(String.init), base != identifier {
            codes.append(base)
        }
        return codes
    }

    public static var preferredLanguages: [String] { preferredLanguages(for: .current) }
}

/// The templates this build carries, read once from the app's own resource.
public enum ReaderContentFilterCatalog {
    /// V1 wrote the file with this name and this shape; reading it verbatim is what makes the words the same.
    public static let resourceName = "content_filter_templates"

    public static func templates(resourceURL: URL?) -> [ReaderContentFilterTemplate] {
        guard let resourceURL, let data = try? Data(contentsOf: resourceURL),
            let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap { entry in
            guard let key = entry["key"] as? String, !key.isEmpty else { return nil }
            return ReaderContentFilterTemplate(key: key,
                names: entry["names"] as? [String: String] ?? [:],
                keywords: entry["keywords"] as? [String: [String]] ?? [:])
        }
    }

    public static func bundled() -> [ReaderContentFilterTemplate] { bundled(.module) }

    public static func bundled(_ bundle: Bundle) -> [ReaderContentFilterTemplate] {
        templates(resourceURL: bundle.url(forResource: resourceName, withExtension: "json"))
    }
}
