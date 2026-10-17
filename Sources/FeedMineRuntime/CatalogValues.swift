// File: CatalogValues.swift
// Module: FeedMineRuntime
// Owns: the reader-facing catalog values — languages, taxonomy nodes, one page of either, and source summaries.
// Does not own: reading the catalog (Persistence), acquisition, persistence of a selection, or any view. UI
// imports Runtime, so these values must live here and not in Composition.

import Foundation
import FeedMineDomain

/// One language the catalogue declares, as the reader's sheet shows it.
public struct CatalogLanguageSummary: Hashable, Sendable, Identifiable {
    public let code: String
    /// The language's own name in the interface language — never the code, never a region.
    public let displayName: String
    /// The region this code names (`en-US` → the United States' name), nil when the code names a language only.
    /// A region is information about a variant, never a second way to choose the same language.
    public let regionName: String?
    /// Enabled (selected) sources for this language, and the total the catalog holds.
    public let enabledSources: Int
    public let totalSources: Int
    /// `und`/empty: a bucket, never a choice a reader makes.
    public let isUndeclared: Bool

    public init(code: String, displayName: String, regionName: String? = nil, enabledSources: Int,
        totalSources: Int, isUndeclared: Bool) {
        self.code = code; self.displayName = displayName; self.regionName = regionName
        self.enabledSources = enabledSources
        self.totalSources = totalSources; self.isUndeclared = isUndeclared
    }

    public var id: String { code }
    public var primarySubtag: String { ReaderLanguageCode.choice(code) }
    /// Whether this code names a region on top of the language (`en` does not, `en-US` does).
    public var hasRegion: Bool { primarySubtag != code.lowercased() }
    /// The label a variant row shows: the language, and its region when the code names one.
    public var variantLabel: String { regionName.map { "\(displayName) (\($0))" } ?? displayName }
}

/// One language the reader chooses, with its regional variants kept as information.
///
/// The catalogue declares 257 codes (`en`, `en-US`, `en-GB`, `pt`, `pt-BR`…); a reader chooses a language, and
/// the engine matches a source's own code by its primary subtag. A group is therefore the choice, and the
/// variants are what the catalogue holds under it — never a second identity for the same language.
public struct CatalogLanguageGroup: Hashable, Sendable, Identifiable {
    /// The primary subtag: the identity every surface persists, and the one the engine matches.
    public let languageCode: String
    /// The language's name in the interface language.
    public let displayName: String
    /// Every source the catalogue holds for the variants: what "fontes disponíveis" counts.
    public let availableSources: Int
    /// The subset the reader's own source selection leaves enabled; a different fact, never shown as the same
    /// number.
    public let enabledSources: Int
    /// `und`/empty: a bucket that says so, never a choice.
    public let isUndeclared: Bool
    /// The catalogue's own codes under this language, biggest first.
    public let variants: [CatalogLanguageSummary]

    public init(languageCode: String, displayName: String, availableSources: Int, enabledSources: Int,
        isUndeclared: Bool, variants: [CatalogLanguageSummary]) {
        self.languageCode = languageCode; self.displayName = displayName
        self.availableSources = availableSources; self.enabledSources = enabledSources
        self.isUndeclared = isUndeclared; self.variants = variants
    }

    public var id: String { languageCode }
    /// True when naming the region adds something: a language declared once has nothing to expand.
    public var hasRegionVariants: Bool { variants.contains { $0.hasRegion } }

    /// The catalogue's rows as the reader's choices, in the order the catalogue gave them: biggest language
    /// first, the undeclared bucket last. Order is the catalogue's own, so a group never jumps around as the
    /// snapshot changes.
    public static func groups(_ languages: [CatalogLanguageSummary]) -> [CatalogLanguageGroup] {
        var order: [String] = []
        var grouped: [String: [CatalogLanguageSummary]] = [:]
        for language in languages {
            let key = language.primarySubtag
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(language)
        }
        return order.compactMap { key in
            guard let variants = grouped[key], let first = variants.first else { return nil }
            return CatalogLanguageGroup(
                languageCode: key,
                displayName: first.displayName,
                availableSources: variants.reduce(0) { $0 + $1.totalSources },
                enabledSources: variants.reduce(0) { $0 + $1.enabledSources },
                isUndeclared: variants.allSatisfy(\.isUndeclared),
                variants: variants)
        }
    }
}

/// The one place a language or region code becomes a label, so every surface names a language the same way.
public enum CatalogLanguageNaming {
    /// The language the interface is in: the bundle's own resolution of the reader's device settings, which is
    /// what "the interface follows the device" means — the app's per-app override included, English when the
    /// device asks for a language FeedMine does not ship.
    public static var interfaceLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// The language's name in the interface language. An undeclared or unknown code says so instead of
    /// pretending to be a language nobody chose.
    public static func displayName(forLanguageCode code: String,
        in locale: Locale = CatalogLanguageNaming.interfaceLocale) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return String(localized: "Idioma não declarado") }
        let primary = String(trimmed.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
        guard primary != "und" else { return String(localized: "Idioma não declarado") }
        return locale.localizedString(forLanguageCode: primary)?.capitalized ?? trimmed
    }

    /// The region a code names, in the interface language, or nil when the code names a language only.
    public static func regionName(forLanguageCode code: String,
        in locale: Locale = CatalogLanguageNaming.interfaceLocale) -> String? {
        regionCode(forLanguageCode: code).flatMap { locale.localizedString(forRegionCode: $0) }
    }

    /// The region subtag (`en-US` → `US`), nil when the code carries none or carries a script.
    public static func regionCode(forLanguageCode code: String) -> String? {
        let parts = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).dropFirst()
        guard let region = parts.first(where: { $0.count == 2 && $0.allSatisfy(\.isLetter) }) else { return nil }
        return region.uppercased()
    }

    /// A code as a choice: the primary subtag, lowercased — what every surface persists.
    public static func choiceCode(_ code: String) -> String { ReaderLanguageCode.choice(code) }

    /// The one number a language row shows — what the catalogue holds — under one name everywhere, so two
    /// surfaces cannot count different things with the same words.
    public static func availableSourcesLabel(_ count: Int,
        in locale: Locale = CatalogLanguageNaming.interfaceLocale) -> String {
        String(localized: "\(numberLabel(count, in: locale)) fontes disponíveis")
    }

    /// A plain count in the interface language's own grouping (`26.012` for pt-BR, `26,012` for en).
    public static func numberLabel(_ count: Int,
        in locale: Locale = CatalogLanguageNaming.interfaceLocale) -> String {
        count.formatted(.number.locale(locale))
    }
}

/// The one place a country the catalogue names becomes a label in the interface language.
public enum CatalogRegionNaming {
    /// A name the reversal cannot place keeps the catalogue's own: an untranslated label is honest, an invented
    /// one is not.
    public static func localizedName(_ catalogueName: String,
        in locale: Locale = CatalogLanguageNaming.interfaceLocale) -> String {
        guard let code = regionCode(forCatalogueName: catalogueName) else { return catalogueName }
        return locale.localizedString(forRegionCode: code) ?? catalogueName
    }

    /// The catalogue names a country by its English name (`90_countries/south_africa`), so the reversal is
    /// Foundation's own list of regions read backwards. Built once: 292 regions, no network, no table.
    public static func regionCode(forCatalogueName name: String) -> String? {
        code(forCatalogueSlug: slug(name))
    }

    /// A country node's own key (`90_countries/south_africa` → `ZA`). The key is the slug, so this is the
    /// name-free path a caller holding the catalogue's vocabulary uses.
    public static func regionCode(forCatalogueKey key: String) -> String? {
        code(forCatalogueSlug: key.split(separator: "/").last.map(String.init) ?? key)
    }

    private static func code(forCatalogueSlug slug: String) -> String? {
        catalogueSpellings[slug] ?? codesBySlug[slug]
    }

    /// The shipped catalogue's OPML names are not all CLDR's English names: it says `usa` for the United States,
    /// `czech_republic` where CLDR now says Czechia, and its own spelling for five more. Those slugs are named
    /// here so the reversal places them. A country the catalogue spells differently and this table does not know
    /// stays unplaced rather than being mapped by resemblance.
    private static let catalogueSpellings: [String: String] = [
        "china": "CN", "czech_republic": "CZ", "ivory_coast": "CI", "myanmar": "MM",
        "turkey": "TR", "uae": "AE", "usa": "US",
    ]

    private static let codesBySlug: [String: String] = {
        let english = Locale(identifier: "en")
        var map: [String: String] = [:]
        for region in Locale.Region.isoRegions {
            guard let name = english.localizedString(forRegionCode: region.identifier) else { continue }
            let key = slug(name)
            guard !key.isEmpty, map[key] == nil else { continue }
            map[key] = region.identifier
        }
        return map
    }()

    /// `South Africa` and `south_africa` are the same name; accents and punctuation are the only difference
    /// between the catalogue's slugs and Foundation's.
    static func slug(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en"))
        var out = ""
        var pendingSeparator = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSeparator, !out.isEmpty { out.append("_") }
                pendingSeparator = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        return out
    }
}

/// One taxonomy node, as the reader's browser shows it.
public struct CatalogNodeSummary: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case section
        case country
        case topic
        case other
    }

    public let id: Int64
    public let key: String
    public let name: String
    public let kind: Kind
    public let sourceCount: Int
    public let hasChildren: Bool

    public init(id: Int64, key: String, name: String, kind: Kind, sourceCount: Int, hasChildren: Bool) {
        self.id = id; self.key = key; self.name = name; self.kind = kind
        self.sourceCount = sourceCount; self.hasChildren = hasChildren
    }
}

/// One page of catalog values: bounded, with a cursor and a truthful exhaustion flag. The cursor is the
/// catalogue's own position type (a node id, a placement position), never a global row number.
public struct CatalogPage<Value: Hashable & Sendable, Cursor: Hashable & Sendable>: Hashable, Sendable {
    public let values: [Value]
    public let nextCursor: Cursor?
    public let exhausted: Bool

    public init(values: [Value], nextCursor: Cursor?, exhausted: Bool) {
        self.values = values; self.nextCursor = nextCursor; self.exhausted = exhausted
    }
}

/// Placement cursor for a node's sources: `(sort_order, source_id)` in the catalogue's own order.
public struct CatalogSourceCursor: Hashable, Sendable {
    public let sortOrder: Int64
    public let sourceID: Int64

    public init(sortOrder: Int64, sourceID: Int64) {
        self.sortOrder = sortOrder
        self.sourceID = sourceID
    }
}

/// One source the catalog offers, as a row in source management shows it.
/// What the runtime observed about one source's own reachability this launch. V1 stated the same column per
/// source (`loader.healthFor`); V2 states the acquisition coordinator's own measured record instead of a
/// second probe of its own.
public struct CatalogSourceHealth: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// The last attempt settled without an operational failure.
        case responding
        /// Consecutive failures, and the source is being retried after its backoff window (or is about to be).
        case failing(consecutive: Int)
    }

    public let state: State

    public init(state: State) { self.state = state }

    public var failures: Int {
        if case .failing(let consecutive) = state { return consecutive }
        return 0
    }
}

public struct CatalogSourceSummary: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let language: String?
    public let mediaKind: String
    public let defaultEnabled: Bool

    public init(id: String, title: String, language: String?, mediaKind: String, defaultEnabled: Bool) {
        self.id = id; self.title = title; self.language = language; self.mediaKind = mediaKind
        self.defaultEnabled = defaultEnabled
    }
}


