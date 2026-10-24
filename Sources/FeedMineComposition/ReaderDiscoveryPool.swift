//
// File: ReaderDiscoveryPool.swift
// Module: FeedMineComposition
//
// Responsibility:
// The sources the catalogue offers a reader who named **interests**, not feeds. This is the product's own promise
// (PRODUCT_NORTH_STAR: "diga o que desperta sua curiosidade; vamos descobrir o que existe"), and the reason the
// bundled catalogue is an editorial asset rather than a URL list: a profile of topics and languages turns into a
// bounded, deterministic set of real sources to acquire from, without the reader adding anything by hand.
//
// The pool is derived only from the catalogue's own labels (node placements, language, media kind, quality) — the
// same rows `LegacyCatalogImport` already maps to identities, so a source that reaches the pool has exactly the
// identity it would have had if the reader had picked it out of the sources screen.
//
// Does not own: which sources the reader selected (Preferences), acquiring them (Acquisition), ordering what is
// published (Editorial), or the interests themselves (the reader's recipe/filter).
import Foundation
import FeedMineDomain
import FeedMinePersistence

/// What the reader said they are curious about, in the catalogue's own vocabulary.
public struct ReaderDiscoveryProfile: Hashable, Sendable {
    /// Lowercased primary subtags (`pt`, `en`). Empty means "whatever the catalogue has".
    public let languages: Set<String>
    /// Catalogue node keys (`topics/science`), the placements a source is filed under.
    public let topicNodeKeys: Set<String>
    /// Placements the reader asked for **less** of (F02's in-feed answer): a source that the catalogue files only
    /// under these is not discovered. A source that is also filed under something the reader wants stays — one
    /// answer about a subject must not delete a source that covers two.
    public let excludedTopicNodeKeys: Set<String>
    /// The reader explicitly named **all languages**. An empty `languages` set alone is not this fact: it is also
    /// "no answer yet", which discovers nothing. With this flag the profile carries no language restriction and
    /// still searches — the widest scope the reader can name, not the absence of discovery.
    public let namesAllLanguages: Bool

    public init(languages: Set<String> = [], topicNodeKeys: Set<String> = [],
        excludedTopicNodeKeys: Set<String> = [], namesAllLanguages: Bool = false) {
        // A profile matches a source's own declaration by language, so both sides are the same vocabulary here:
        // a regional selection (`pt-BR`) answers the same rows as the language it belongs to.
        self.languages = ReaderLanguageCode.choices(languages)
        self.topicNodeKeys = Set(topicNodeKeys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        self.excludedTopicNodeKeys = Set(excludedTopicNodeKeys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        self.namesAllLanguages = namesAllLanguages && self.languages.isEmpty
    }

    /// A profile that names nothing discovers nothing: the plain feed stays the reader's own selection. Naming
    /// **all languages** is not "nothing": the reader answered, and the pool must serve the whole catalogue.
    public var isEmpty: Bool {
        languages.isEmpty && topicNodeKeys.isEmpty && !namesAllLanguages
    }
}

public extension ReaderDiscoveryProfile {
    /// The reader's own answer — the recipe the first run and the preferences page keep — in the catalogue's
    /// vocabulary: `topic:<node>` placements with `more` as interest and `less` as an exclusion, the editorial
    /// answers that only exclude, and the content languages. One mapping, so the onboarding answer, the settings
    /// page and discovery cannot read the same recipe differently.
    init(recipe: FeedRecipeDefinition) {
        var interested: Set<String> = [], excluded: Set<String> = []
        for (key, level) in recipe.topicPreferences {
            let node = key.hasPrefix("topic:") ? String(key.dropFirst("topic:".count)) : key
            guard !node.isEmpty else { continue }
            // R13: `.neutral` is the absence of an answer — it must neither interest nor exclude. The previous
            // `else` branch folded it into the exclusion set, so a reader who returned a subject to Normal kept
            // hiding it.
            switch level {
            case .more: interested.insert(node)
            case .less: excluded.insert(node)
            case .neutral: break
            }
        }
        for (key, level) in recipe.editorialPreferences where level == .less {
            // R13: subject and editorial namespaces stay distinct. An editorial answer (`media:`, `nature:`) is a
            // weight, not a catalogue node; only an explicitly topic-keyed editorial answer excludes a topic.
            guard key.hasPrefix("topic:") else { continue }
            let node = String(key.dropFirst("topic:".count))
            guard !node.isEmpty else { continue }
            excluded.insert(node)
        }
        self.init(languages: Set(recipe.languages), topicNodeKeys: interested,
            excludedTopicNodeKeys: excluded,
            namesAllLanguages: recipe.hasLanguageAnswer && recipe.languages.isEmpty)
    }
}

/// A bounded, deterministic set of sources for one profile.
public struct ReaderDiscoveryPool: Sendable {
    public let profile: ReaderDiscoveryProfile
    public let entries: [LegacyCatalogEntry]

    public init(profile: ReaderDiscoveryProfile, entries: [LegacyCatalogEntry]) {
        self.profile = profile
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }
}

public enum ReaderDiscoveryError: Error, Equatable, Sendable {
    case missingCatalog
    case invalidExaminedCapacity
    case cursorScopeMismatch
}

/// A structural catalogue position, scoped to the profile, media criteria and file revision.
/// It records examination, including misses; it reserves no source selection or publication.
public struct ReaderDiscoveryCursor: Hashable, Sendable {
    fileprivate let key: String
    fileprivate let profile: ReaderDiscoveryProfile
    fileprivate let mediaKinds: Set<String>
    fileprivate let catalogRevision: String
}

public struct ReaderDiscoveryPage: Sendable {
    public let entries: [LegacyCatalogEntry]
    public let examinedCount: Int
    public let nextCursor: ReaderDiscoveryCursor?
    public let exhausted: Bool
}

/// Reads the pool out of the bundled catalogue. Deterministic: the same profile and the same catalogue produce
/// the same list, in the same order, on every launch — a pool that reshuffled itself would move the reader's feed
/// without them asking.
public struct ReaderDiscoveryBuilder: Sendable {
    private let catalogURL: URL
    /// How deep one topic may be read before the builder stops: the catalogue's topic subtrees hold thousands of
    /// sources, and the pool only needs enough to keep a feed running.
    private let perTopicCeiling: Int
    /// How many source keys one pool may look up: the ceiling that keeps a profile query cheap while leaving room
    /// for the language and media filters to drop what the reader did not ask for.
    private let keyCeiling: Int
    /// The source kinds a discovery pool may draw from. Text **and** audio: a reader who asks for discovery
    /// must not be handed a text-only internet, and the product promises "listen" as well as "read"
    /// (PD-2026-10-20 D10). Video sources stay out of the automatic pool this round — a video source the reader
    /// already follows keeps working with its items identified; it is not discovered on their behalf.
    /// What an item **is** comes from its own enclosure, never from this source-level kind.
    private let mediaKinds: Set<String>

    public init(catalogURL: URL, perTopicCeiling: Int = 2_000, keyCeiling: Int = 4_000,
        mediaKinds: Set<String> = ["text", "audio"]) {
        self.catalogURL = catalogURL
        self.perTopicCeiling = perTopicCeiling
        self.keyCeiling = keyCeiling
        self.mediaKinds = mediaKinds
    }

    /// One finite examination in stable catalogue key order. Quality orders the admitted entries
    /// within the page; no resource limit removes the remainder of the eligible universe.
    /// A page with no matching entries is not evidence of catalogue exhaustion.
    public func page(for profile: ReaderDiscoveryProfile, after cursor: ReaderDiscoveryCursor? = nil,
        examinedCapacity: Int) throws -> ReaderDiscoveryPage {
        guard examinedCapacity > 0, examinedCapacity < Int.max else {
            throw ReaderDiscoveryError.invalidExaminedCapacity
        }
        let values = try catalogURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let revision = catalogURL.standardizedFileURL.path + "|" + String(values.fileSize ?? 0)
            + "|" + String(values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)
        if let cursor {
            guard cursor.profile == profile, cursor.mediaKinds == mediaKinds,
                cursor.catalogRevision == revision else { throw ReaderDiscoveryError.cursorScopeMismatch }
        }
        guard !profile.isEmpty else {
            return ReaderDiscoveryPage(entries: [], examinedCount: 0, nextCursor: nil, exhausted: true)
        }
        let reader = try LegacyCatalogReader(catalogURL: catalogURL)
        let records = try reader.sources(after: cursor?.key, limit: examinedCapacity + 1,
            onlyDefaultEnabled: true, mediaKinds: mediaKinds)
        let examined = Array(records.prefix(examinedCapacity))
        let entries = examined.filter { admits($0, profile: profile) }
            .sorted { left, right in
                let l = left.qualityScore ?? 0, r = right.qualityScore ?? 0
                return l == r ? left.key < right.key : l > r
            }.compactMap(LegacyCatalogImport.entry)
        let next = examined.last.map { ReaderDiscoveryCursor(key: $0.key, profile: profile,
            mediaKinds: mediaKinds, catalogRevision: revision) }
        return ReaderDiscoveryPage(entries: entries, examinedCount: examined.count,
            nextCursor: next ?? cursor, exhausted: records.count <= examinedCapacity)
    }

    /// The pool for one profile: sources the reader named an interest in, ordered by the catalogue's own quality
    /// and then by key, so the same profile always yields the same list.
    /// Compatibility preview only. Active associations should retain and advance `page` cursors.
    public func pool(for profile: ReaderDiscoveryProfile, limit: Int) throws -> ReaderDiscoveryPool {
        guard limit > 0 else { return ReaderDiscoveryPool(profile: profile, entries: []) }
        guard !profile.isEmpty else { return ReaderDiscoveryPool(profile: profile, entries: []) }
        let reader = try LegacyCatalogReader(catalogURL: catalogURL)

        var seen = Set<String>()
        var candidates: [LegacyCatalogSourceRecord] = []
        if profile.topicNodeKeys.isEmpty {
            // A reader who named only languages: the catalogue is read in key order, filtered by language.
            var cursor: String?
            while candidates.count < limit * 4 {
                let page = try reader.sources(after: cursor, limit: 500, onlyDefaultEnabled: true,
                    mediaKinds: mediaKinds)
                guard let last = page.last else { break }
                cursor = last.key
                candidates.append(contentsOf: page.filter { admits($0, profile: profile) })
                if page.count < 500 { break }
            }
        } else {
            // A country or a heading places nothing itself: its sources live under its leaves, so the pool reads
            // the subtree and then the records it names (bounded, in key order).
            var keys: [String] = []
            for nodeKey in profile.topicNodeKeys.sorted() {
                guard let node = try reader.node(key: nodeKey) else { continue }
                keys.append(contentsOf: try reader.sourceKeys(inSubtreeOf: node.id,
                    ceiling: min(perTopicCeiling, keyCeiling)))
            }
            var seenKey = Set<String>()
            var fetched = 0
            for key in keys.sorted() where seenKey.insert(key).inserted {
                guard fetched < keyCeiling else { break }
                fetched += 1
                let key = key
                guard let record = try reader.source(key: key), admits(record, profile: profile) else { continue }
                candidates.append(record)
            }
        }
        let ordered = candidates
            .sorted { left, right in
                let leftQuality = left.qualityScore ?? 0, rightQuality = right.qualityScore ?? 0
                return leftQuality == rightQuality ? left.key < right.key : leftQuality > rightQuality
            }
            .prefix(limit)
            .compactMap { LegacyCatalogImport.entry($0) }
        return ReaderDiscoveryPool(profile: profile, entries: Array(ordered))
    }

    /// What the profile admits: the source must be placed where the reader said they are curious, and (when the
    /// reader named languages) actually be in one of them. A source the catalogue does not place anywhere is not
    /// discovered — the recipe's own rule, kept here so a pool cannot invent relevance.
    private func admits(_ record: LegacyCatalogSourceRecord, profile: ReaderDiscoveryProfile) -> Bool {
        guard mediaKinds.isEmpty || mediaKinds.contains(record.mediaKind) else { return false }
        if !profile.languages.isEmpty {
            guard let language = record.language, !language.isEmpty else { return false }
            guard ReaderLanguageCode.answered(language, by: profile.languages) else { return false }
        }
        if !profile.topicNodeKeys.isEmpty {
            let placed = record.nodeKeys.contains { key in
                profile.topicNodeKeys.contains { asked in key == asked || key.hasPrefix(asked + "/") }
            }
            guard placed else { return false }
        }
        if !profile.excludedTopicNodeKeys.isEmpty, !record.nodeKeys.isEmpty {
            // Everything the catalogue says about this source is something the reader asked for less of.
            let onlyExcluded = record.nodeKeys.allSatisfy { key in
                profile.excludedTopicNodeKeys.contains { asked in key == asked || key.hasPrefix(asked + "/") }
            }
            guard !onlyExcluded else { return false }
        }
        return true
    }

    /// `pt-BR` and `pt` are the same language to a profile that named `pt` — the rule lives in
    /// `ReaderLanguageCode`, so the pool, the filter and the recipe cannot disagree about it.
}
