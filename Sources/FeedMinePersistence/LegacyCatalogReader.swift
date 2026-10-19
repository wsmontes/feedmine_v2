// File: LegacyCatalogReader.swift
// Module: FeedMinePersistence
// Owns: read-only mechanical access to the v1 `catalog.sqlite` (PD-2: v2 reuses the v1 catalog).
// Does not own: identity mapping, selection of sources, target registration or Domain values.
//
// The v1 catalog is a separate, replaceable, shipped database (77,443 sources in the bundled snapshot). It is opened read-only
// and never migrated or written; runtime.sqlite remains the only semantic store (INV-11/INV-12).
// v1 schema (feedmine/FeedEngine/SQLiteCatalogStore.swift): catalog_source(key = canonical URL
// identity, request_url = fetch URL), catalog_node (taxonomy), catalog_placement (source ↔ node).

import Foundation
import GRDB
import FeedMineDomain

public enum LegacyCatalogError: Error, Equatable, Sendable {
    case open(String)
    case unsupportedSchema
    case storage(String)
}

public struct LegacyCatalogSourceRecord: Hashable, Sendable {
    /// v1 canonical identity key (normalized URL). Stable across catalog rebuilds.
    public let key: String
    public let title: String
    /// URL to fetch (keeps signed/auth parameters the identity key drops).
    public let requestURL: String
    public let siteURL: String?
    public let language: String?
    /// v1 MediaKind raw value: text, video, audio or forum.
    public let mediaKind: String
    public let qualityScore: Int?
    public let defaultEnabled: Bool
    /// Taxonomy node keys (slash-joined paths) this source is placed under.
    public let nodeKeys: [String]
    /// The catalogue's own description, and the host its feed lives on. T11 needs both: V1's editorial
    /// assessment reads a source's description and its host, and a curated feed's "source balance" cannot weigh
    /// anything without them.
    public let sourceDescription: String?
    public let displayHost: String?
    public let tags: [String]
    public let nature: String?
    /// How busy the catalogue says the source is: V1's editorial assessment weighs it (prolific…dormant).
    public let activity: String?

    public init(key: String, title: String, requestURL: String, siteURL: String?, language: String?, mediaKind: String,
        qualityScore: Int?, defaultEnabled: Bool, nodeKeys: [String], sourceDescription: String? = nil,
        displayHost: String? = nil, tags: [String] = [], nature: String? = nil, activity: String? = nil) {
        self.key = key; self.title = title; self.requestURL = requestURL; self.siteURL = siteURL
        self.language = language; self.mediaKind = mediaKind; self.qualityScore = qualityScore
        self.defaultEnabled = defaultEnabled; self.nodeKeys = nodeKeys
        self.sourceDescription = sourceDescription; self.displayHost = displayHost
        self.tags = tags; self.nature = nature; self.activity = activity
    }
}

/// P07: one bounded page of expression-matched sources plus the fact that the page is not the whole universe.
public struct LegacyCatalogSourceSearch: Hashable, Sendable {
    public let records: [LegacyCatalogSourceRecord]
    public let truncated: Bool
    public init(records: [LegacyCatalogSourceRecord], truncated: Bool) {
        self.records = records; self.truncated = truncated
    }
}

/// The catalogue facts an acquisition order reads, and only them. `source(key:)` predates the ranking and stays
/// exactly as it was, so this narrow lookup cannot change any existing reader's record.
public struct LegacyCatalogRankingFacts: Hashable, Sendable {
    public let key: String
    /// 0…100, the catalogue's technical-quality claim.
    public let qualityScore: Int?
    /// `prolific`, `active`, `quiet`, `dormant` — V1's own activity classes.
    public let activity: String?

    public init(key: String, qualityScore: Int?, activity: String?) {
        self.key = key; self.qualityScore = qualityScore; self.activity = activity
    }

    /// Whether the catalogue said anything a ranking can use. Absence is not zero.
    public var hasEvidence: Bool { qualityScore != nil || activity != nil }
}

/// One language as the catalogue declares it, with the counts T6's sheet must show. `und`/empty is a real
/// bucket in this data (27,741 of 77,443 sources) and is never presented as a language a reader can pick.
public struct LegacyCatalogLanguageRecord: Hashable, Sendable {
    public let code: String
    public let enabledSources: Int
    public let totalSources: Int

    public init(code: String, enabledSources: Int, totalSources: Int) {
        self.code = code; self.enabledSources = enabledSources; self.totalSources = totalSources
    }

    /// V1 compared the primary subtag when a feed declared "pt-BR" and the reader selected "pt"; the rule lives
    /// in `ReaderLanguageCode` so the catalogue, the filter and the pool cannot disagree about it.
    public var primarySubtag: String { ReaderLanguageCode.choice(code) }
    public var isUndeclared: Bool { ReaderLanguageCode.isUndeclared(code) }
}

/// The `catalog_metadata` row v1's compiler writes: the catalogue's own claims about itself
/// (`04-catalog-editorial.md` §2.1 — `build_catalog.py` emits the key/value table). Read-only, and
/// authoritative for what a snapshot declares about its own revision, schema and size; the public
/// preparation is the publisher of that table, so a reader that verifies it is reconciling with the
/// authority rather than inventing a second identity. `nil` when the file carries no such table
/// (a catalogue predating it), which is itself the answer "this snapshot declares nothing".
public struct LegacyCatalogMetadata: Hashable, Sendable {
    /// `schema_version` — the v1 compiler's own catalogue schema counter.
    public let schemaVersion: Int?
    /// `catalog_version` — the catalogue's own revision counter, the number the edition stamps as
    /// `CatalogGeneration` provenance.
    public let revision: Int64?
    public let sourceCount: Int?
    public let nodeCount: Int?
    public let placementCount: Int?
    public let fileCount: Int?
    public let invalidSourceCount: Int?
    public let failedFileCount: Int?

    public init(schemaVersion: Int?, revision: Int64?, sourceCount: Int?, nodeCount: Int?, placementCount: Int?,
        fileCount: Int?, invalidSourceCount: Int?, failedFileCount: Int?) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.sourceCount = sourceCount
        self.nodeCount = nodeCount
        self.placementCount = placementCount
        self.fileCount = fileCount
        self.invalidSourceCount = invalidSourceCount
        self.failedFileCount = failedFileCount
    }
}

/// One taxonomy node. `kind` is the catalogue's own discriminator, measured on the bundled snapshot
/// (2026-10-09, 6,450 nodes): 0 = section under the root, 1 = country, 3 = topic leaf.
public struct LegacyCatalogNodeRecord: Hashable, Sendable {
    public static let sectionKind = 0
    public static let countryKind = 1
    public static let topicKind = 3

    public let id: Int64
    public let key: String
    public let name: String
    public let kind: Int
    public let parentID: Int64?
    public let sourceCount: Int
    public let childCount: Int

    public init(id: Int64, key: String, name: String, kind: Int, parentID: Int64?, sourceCount: Int, childCount: Int) {
        self.id = id; self.key = key; self.name = name; self.kind = kind; self.parentID = parentID
        self.sourceCount = sourceCount; self.childCount = childCount
    }

    public var isCountry: Bool { kind == Self.countryKind }
    public var isSection: Bool { kind == Self.sectionKind }
    public var hasChildren: Bool { childCount > 0 }
}

public struct LegacyCatalogSourcePage: Hashable, Sendable {
    public let records: [LegacyCatalogSourceRecord]
    /// Last placement position of this page: `(sort_order, source_id)`.
    public let nextCursor: (sortOrder: Int64, sourceID: Int64)?
    public let exhausted: Bool

    public init(records: [LegacyCatalogSourceRecord], nextCursor: (sortOrder: Int64, sourceID: Int64)?,
        exhausted: Bool) {
        self.records = records; self.nextCursor = nextCursor; self.exhausted = exhausted
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.records == rhs.records && lhs.exhausted == rhs.exhausted
            && lhs.nextCursor?.sortOrder == rhs.nextCursor?.sortOrder
            && lhs.nextCursor?.sourceID == rhs.nextCursor?.sourceID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(records); hasher.combine(exhausted)
        hasher.combine(nextCursor?.sortOrder); hasher.combine(nextCursor?.sourceID)
    }
}

public struct LegacyCatalogNodePage: Hashable, Sendable {
    public let nodes: [LegacyCatalogNodeRecord]
    public let nextCursor: Int64?
    public let exhausted: Bool

    public init(nodes: [LegacyCatalogNodeRecord], nextCursor: Int64?, exhausted: Bool) {
        self.nodes = nodes; self.nextCursor = nextCursor; self.exhausted = exhausted
    }
}

public struct LegacyCatalogReader: Sendable {
    /// The catalogue schema this build reads, as the compiled snapshot declares it in `catalog_metadata`
    /// (`schema_version`). A snapshot declaring another version is refused by a caller that verifies the
    /// catalogue, rather than opened and misread; the reader's own table check
    /// (`catalog_source`/`catalog_node`/`catalog_placement`) remains the mechanical gate.
    public static let supportedSchemaVersion = 2

    private let queue: DatabaseQueue

    public init(catalogURL: URL) throws {
        var configuration = Configuration()
        configuration.readonly = true
        do { queue = try DatabaseQueue(path: catalogURL.path, configuration: configuration) }
        catch { throw LegacyCatalogError.open(String(describing: error)) }
        let tables = try Self.wrap { try queue.read { db in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'") } }
        guard Set(["catalog_source", "catalog_node", "catalog_placement"]).isSubset(of: Set(tables)) else {
            throw LegacyCatalogError.unsupportedSchema
        }
    }

    public func sourceCount() throws -> Int {
        try Self.wrap { try queue.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM catalog_source") ?? 0 } }
    }

    /// The catalogue's own `catalog_metadata` table, as values; `nil` when the snapshot carries no such table
    /// or names no keys. Mechanical only: nothing is inferred and no key is invented (the table is written by
    /// the external preparation, so keys this build does not know are ignored rather than refused).
    public func metadata() throws -> LegacyCatalogMetadata? {
        try Self.wrap { try queue.read { db in
            let tables = try String.fetchAll(db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'catalog_metadata'")
            guard !tables.isEmpty else { return nil }
            let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM catalog_metadata")
            guard !rows.isEmpty else { return nil }
            var values: [String: String] = [:]
            for row in rows {
                let key: String = row["key"]
                values[key] = row["value"] as String?
            }
            let int = { (key: String) -> Int? in values[key].flatMap(Int.init) }
            return LegacyCatalogMetadata(schemaVersion: int("schema_version"),
                revision: values["catalog_version"].flatMap(Int64.init), sourceCount: int("source_count"),
                nodeCount: int("node_count"), placementCount: int("placement_count"),
                fileCount: int("file_count"), invalidSourceCount: int("invalid_source_count"),
                failedFileCount: int("failed_file_count"))
        } }
    }

    /// One bounded page in stable key order. `after` is the last key of the previous page.
    /// `onlyDefaultEnabled` mirrors v1's curated default set; `mediaKinds` filters by v1 MediaKind.
    public func sources(after: String?, limit: Int, onlyDefaultEnabled: Bool, mediaKinds: Set<String>) throws -> [LegacyCatalogSourceRecord] {
        guard limit > 0 else { return [] }
        return try Self.wrap {
            try queue.read { db in
                var conditions: [String] = []
                var arguments: [DatabaseValueConvertible] = []
                if let after { conditions.append("s.key > ?"); arguments.append(after) }
                if onlyDefaultEnabled { conditions.append("s.default_enabled = 1") }
                if !mediaKinds.isEmpty {
                    conditions.append("s.media_kind IN (" + Array(repeating: "?", count: mediaKinds.count).joined(separator: ",") + ")")
                    arguments.append(contentsOf: mediaKinds.sorted() as [DatabaseValueConvertible])
                }
                arguments.append(limit)
                let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
                let rows = try Row.fetchAll(db, sql: """
                    SELECT s.id, s.key, s.title, s.request_url, s.site_url, s.language, s.media_kind,
                        s.quality_score, s.default_enabled, s.description, s.display_host, s.tags, s.nature, s.activity
                    FROM catalog_source s \(whereClause)
                    ORDER BY s.key LIMIT ?
                    """, arguments: StatementArguments(arguments))
                return try rows.map { row in
                    let id: Int64 = row["id"]
                    let nodes = try String.fetchAll(db, sql: """
                        SELECT DISTINCT n.key FROM catalog_placement p JOIN catalog_node n ON n.id = p.node_id
                        WHERE p.source_id = ? ORDER BY n.key
                        """, arguments: [id])
                    let tags = (row["tags"] as String?).map { value in
                        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    } ?? []
                    return LegacyCatalogSourceRecord(key: row["key"], title: row["title"], requestURL: row["request_url"],
                        siteURL: row["site_url"], language: row["language"], mediaKind: row["media_kind"],
                        qualityScore: row["quality_score"], defaultEnabled: (row["default_enabled"] as Int64? ?? 0) != 0,
                        nodeKeys: nodes, sourceDescription: row["description"], displayHost: row["display_host"],
                        tags: tags, nature: row["nature"], activity: row["activity"])
                }
            }
        }
    }

    /// One page of the sources placed in a taxonomy node, in the catalogue's own order for that node
    /// (`idx_catalog_placement_node_order`: sort_order, source_id). The cursor is the last (sortOrder, sourceID)
    /// of the previous page, so a page never depends on a global id that a catalog rebuild could change.
    public func sources(inNode nodeID: Int64, after: (sortOrder: Int64, sourceID: Int64)? = nil,
        limit: Int) throws -> LegacyCatalogSourcePage {
        guard limit > 0 else { return LegacyCatalogSourcePage(records: [], nextCursor: nil, exhausted: true) }
        return try Self.wrap { try queue.read { db in
            var sql = """
                SELECT s.id, s.key, s.title, s.request_url, s.site_url, s.language, s.media_kind,
                    s.quality_score, s.default_enabled, p.sort_order
                FROM catalog_placement p JOIN catalog_source s ON s.id = p.source_id
                WHERE p.node_id = ?
                """
            var arguments: [DatabaseValueConvertible] = [nodeID]
            if let after {
                sql += " AND (p.sort_order > ? OR (p.sort_order = ? AND p.source_id > ?))"
                arguments.append(after.sortOrder); arguments.append(after.sortOrder); arguments.append(after.sourceID)
            }
            sql += " ORDER BY p.sort_order, p.source_id LIMIT ?"
            arguments.append(limit + 1)
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            let page = try rows.prefix(limit).map { row -> LegacyCatalogSourceRecord in
                let id: Int64 = row["id"]
                let nodes = try String.fetchAll(db, sql: """
                    SELECT DISTINCT n.key FROM catalog_placement p JOIN catalog_node n ON n.id = p.node_id
                    WHERE p.source_id = ? ORDER BY n.key
                    """, arguments: [id])
                return LegacyCatalogSourceRecord(key: row["key"], title: row["title"], requestURL: row["request_url"],
                    siteURL: row["site_url"], language: row["language"], mediaKind: row["media_kind"],
                    qualityScore: row["quality_score"], defaultEnabled: (row["default_enabled"] as Int64? ?? 0) != 0,
                    nodeKeys: nodes)
            }
            let exhausted = rows.count <= limit
            let last = rows.prefix(limit).last
            let nextCursor: (sortOrder: Int64, sourceID: Int64)? = exhausted ? nil : last.map {
                (sortOrder: $0["sort_order"] as Int64? ?? 0, sourceID: $0["id"] as Int64? ?? 0)
            }
            return LegacyCatalogSourcePage(records: page, nextCursor: nextCursor, exhausted: exhausted)
        } }
    }

    /// Every source key placed in a node, for a bulk enable/disable. Bounded by the caller's own ceiling.
    public func sourceKeys(inNode nodeID: Int64, ceiling: Int = 5_000) throws -> [String] {
        guard ceiling > 0 else { return [] }
        return try Self.wrap { try queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT s.key FROM catalog_placement p JOIN catalog_source s ON s.id = p.source_id
                WHERE p.node_id = ? ORDER BY p.sort_order, p.source_id LIMIT ?
                """, arguments: [nodeID, ceiling])
        } }
    }

    /// Every source key placed under a node of one kind, grouped by node — one query, for a surface that must
    /// show each country's state without asking per row.
    public func sourceKeysByNode(kind: Int, perNodeCeiling: Int = 20_000) throws -> [Int64: [String]] {
        guard perNodeCeiling > 0 else { return [:] }
        return try Self.wrap { try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.node_id AS node_id, s.key AS key
                FROM catalog_node n JOIN catalog_placement p ON p.node_id = n.id
                JOIN catalog_source s ON s.id = p.source_id
                WHERE n.kind = ? ORDER BY p.node_id, p.sort_order, p.source_id
                """, arguments: [kind])
            var grouped: [Int64: [String]] = [:]
            for row in rows {
                let nodeID: Int64 = row["node_id"]
                guard (grouped[nodeID]?.count ?? 0) < perNodeCeiling else { continue }
                grouped[nodeID, default: []].append(row["key"])
            }
            return grouped
        } }
    }

    /// Every source key placed at a node **or anywhere beneath it** (V1's `SourceRegistry.setRegionEnabled`
    /// cascaded down the region tree). The shipped catalog places a country's sources at its topic leaves —
    /// `90_countries/algeria/sports/football` — so a region's own rows are not its sources, and a surface that
    /// toggles a region must state and change the whole tree under it.
    public func sourceKeys(inSubtreeOf nodeID: Int64, ceiling: Int = 20_000) throws -> [String] {
        guard ceiling > 0 else { return [] }
        return try Self.wrap { try queue.read { db in
            try String.fetchAll(db, sql: """
                WITH RECURSIVE subtree(id) AS (
                    SELECT id FROM catalog_node WHERE id = ?
                    UNION ALL
                    SELECT n.id FROM catalog_node n JOIN subtree s ON n.parent_id = s.id
                )
                SELECT s.key FROM catalog_placement p JOIN catalog_source s ON s.id = p.source_id
                WHERE p.node_id IN (SELECT id FROM subtree)
                ORDER BY p.sort_order, p.source_id LIMIT ?
                """, arguments: [nodeID, ceiling])
        } }
    }

    /// The same grouping as `sourceKeysByNode(kind:)`, with each node's whole subtree: what a list needs to
    /// state a country's own state when the catalog places its sources below it.
    public func sourceKeysByNodeInSubtree(kind: Int, perNodeCeiling: Int = 20_000) throws -> [Int64: [String]] {
        guard perNodeCeiling > 0 else { return [:] }
        return try Self.wrap { try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                WITH RECURSIVE subtree(root_id, id) AS (
                    SELECT id, id FROM catalog_node WHERE kind = ?
                    UNION ALL
                    SELECT s.root_id, n.id FROM catalog_node n JOIN subtree s ON n.parent_id = s.id
                )
                SELECT s.root_id AS node_id, src.key AS key
                FROM subtree s JOIN catalog_placement p ON p.node_id = s.id
                JOIN catalog_source src ON src.id = p.source_id
                ORDER BY s.root_id, p.sort_order, p.source_id
                """, arguments: [kind])
            var grouped: [Int64: [String]] = [:]
            for row in rows {
                let nodeID: Int64 = row["node_id"]
                guard (grouped[nodeID]?.count ?? 0) < perNodeCeiling else { continue }
                grouped[nodeID, default: []].append(row["key"])
            }
            return grouped
        } }
    }

    /// The same grouping as `sourceKeysByParent(nodeID:)`, with each child's whole subtree.
    public func sourceKeysByParentInSubtree(nodeID: Int64, perNodeCeiling: Int = 20_000)
        throws -> [Int64: [String]] {
        guard perNodeCeiling > 0 else { return [:] }
        return try Self.wrap { try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                WITH RECURSIVE subtree(root_id, id) AS (
                    SELECT id, id FROM catalog_node WHERE parent_id = ?
                    UNION ALL
                    SELECT s.root_id, n.id FROM catalog_node n JOIN subtree s ON n.parent_id = s.id
                )
                SELECT s.root_id AS node_id, src.key AS key
                FROM subtree s JOIN catalog_placement p ON p.node_id = s.id
                JOIN catalog_source src ON src.id = p.source_id
                ORDER BY s.root_id, p.sort_order, p.source_id
                """, arguments: [nodeID])
            var grouped: [Int64: [String]] = [:]
            for row in rows {
                let nodeID: Int64 = row["node_id"]
                guard (grouped[nodeID]?.count ?? 0) < perNodeCeiling else { continue }
                grouped[nodeID, default: []].append(row["key"])
            }
            return grouped
        } }
    }

    /// Every source key placed under each child of one node, grouped by the child — one query, so a node's
    /// level states which sub-nodes are fully selected without asking per row (V1's `isRegionEnabled`).
    public func sourceKeysByParent(nodeID: Int64, perNodeCeiling: Int = 20_000) throws -> [Int64: [String]] {
        guard perNodeCeiling > 0 else { return [:] }
        return try Self.wrap { try queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.node_id AS node_id, s.key AS key
                FROM catalog_node n JOIN catalog_placement p ON p.node_id = n.id
                JOIN catalog_source s ON s.id = p.source_id
                WHERE n.parent_id = ? ORDER BY p.node_id, p.sort_order, p.source_id
                """, arguments: [nodeID])
            var grouped: [Int64: [String]] = [:]
            for row in rows {
                let childID: Int64 = row["node_id"]
                guard (grouped[childID]?.count ?? 0) < perNodeCeiling else { continue }
                grouped[childID, default: []].append(row["key"])
            }
            return grouped
        } }
    }

    /// Exact canonical identity lookup; fetching still uses the separate requestURL.
    public func source(key: String) throws -> LegacyCatalogSourceRecord? {
        try Self.wrap { try queue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM catalog_source WHERE key = ?", arguments: [key]) else { return nil }
            let id: Int64 = row["id"]
            let nodes = try String.fetchAll(db, sql: """
                SELECT DISTINCT n.key FROM catalog_placement p JOIN catalog_node n ON n.id = p.node_id
                WHERE p.source_id = ? ORDER BY n.key
                """, arguments: [id])
            return LegacyCatalogSourceRecord(key: row["key"], title: row["title"], requestURL: row["request_url"],
                siteURL: row["site_url"], language: row["language"], mediaKind: row["media_kind"],
                qualityScore: row["quality_score"], defaultEnabled: (row["default_enabled"] as Int64? ?? 0) != 0, nodeKeys: nodes)
        } }
    }

    /// The quality/activity facts one source contributes to the composition's acquisition order. Nil means the
    /// catalogue does not describe the key; no rank is invented for it.
    public func rankingFacts(key: String) throws -> LegacyCatalogRankingFacts? {
        try Self.wrap { try queue.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT key, quality_score, activity FROM catalog_source WHERE key = ?", arguments: [key]) else {
                return nil
            }
            return LegacyCatalogRankingFacts(key: row["key"], qualityScore: row["quality_score"],
                activity: row["activity"])
        } }
    }

    /// Bounded literal name/key lookup; values never become SQL syntax. Result order is v1's catalog
    /// sort key (`04-catalog-editorial.md`: default_enabled, 100 - quality, title) after titles that
    /// start with the query; key breaks ties. It orders search results only; it is not feed ranking.
    public func matchingSources(query: String, limit: Int) throws -> [LegacyCatalogSourceRecord] {
        guard limit > 0 else { return [] }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return try sources(after: nil, limit: min(limit, 100), onlyDefaultEnabled: true, mediaKinds: ["text"]) }
        let escaped = text.replacingOccurrences(of: "!", with: "!!").replacingOccurrences(of: "%", with: "!%")
            .replacingOccurrences(of: "_", with: "!_")
        let keys = try Self.wrap { try queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT key FROM catalog_source WHERE media_kind = 'text'
                    AND (title LIKE ? ESCAPE '!' OR key LIKE ? ESCAPE '!')
                    ORDER BY (title LIKE ? ESCAPE '!') DESC, default_enabled DESC, quality_score IS NULL, quality_score DESC, title, key LIMIT ?
                """, arguments: ["%" + escaped + "%", "%" + escaped + "%", escaped + "%", min(limit, 100)])
        } }
        return try keys.compactMap { try source(key: $0) }
    }

    /// P07/R14: the catalogue search consumes the **same expression** the rest of the product does. The old method
    /// applied the whole query as one literal LIKE, so a valid source whose positives land in different fields
    /// (title + taxonomy), whose title carries diacritics, or whose match sits beyond the literal pre-filter was
    /// discarded before the grammar could see it. Ranking is still v1's; the filter is the expression's.
    public func matchingSources(expression: SearchExpression, limit: Int,
        offset: Int = 0) throws -> LegacyCatalogSourceSearch {
        guard limit > 0 else { return .init(records: [], truncated: false) }
        let skip = max(0, offset)
        let prefixTerm = expression.terms.first ?? ""
        let escapedPrefix = prefixTerm
            .replacingOccurrences(of: "!", with: "!!")
            .replacingOccurrences(of: "%", with: "!%")
            .replacingOccurrences(of: "_", with: "!_") + "%"
        // No text predicate here: folding happens in Swift with the domain's own normalizer, so a source is never
        // lost to SQLite's ASCII-only LIKE before the expression reads it. The scan is bounded by the catalogue's
        // own row order and stops as soon as one match beyond the page is found.
        let candidates = try Self.wrap { try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.key AS key, s.title AS title, COALESCE(s.tags, '') AS tags,
                    (SELECT group_concat(n.key, ' ') FROM catalog_placement p
                        JOIN catalog_node n ON n.id = p.node_id WHERE p.source_id = s.id) AS node_keys
                FROM catalog_source s WHERE s.media_kind = 'text'
                ORDER BY (s.title LIKE ? ESCAPE '!' OR s.key LIKE ? ESCAPE '!') DESC,
                    s.default_enabled DESC, s.quality_score IS NULL, s.quality_score DESC, s.title, s.key
                """, arguments: [escapedPrefix, escapedPrefix])
        } }
        var keys: [String] = []
        var seen = 0
        var truncated = false
        for row in candidates {
            guard let key = row["key"] as String?, let title = row["title"] as String? else { continue }
            let tags = (row["tags"] as String?) ?? ""
            let nodeKeys = (row["node_keys"] as String?) ?? ""
            guard expression.matches(fields: [title, tags, nodeKeys, key]) else { continue }
            if seen < skip { seen += 1; continue }
            seen += 1
            if keys.count >= limit { truncated = true; break }
            keys.append(key)
        }
        return LegacyCatalogSourceSearch(records: try keys.compactMap { try source(key: $0) },
            truncated: truncated)
    }

    // MARK: - Metadata (T6's sheet, T7's taxonomy and regions)

    /// Every language the catalogue declares, biggest enabled set first, with `und`/empty last. One pass over the
    /// whole table: the caller caches it, because nothing changes under a shipped asset.
    public func languages() throws -> [LegacyCatalogLanguageRecord] {
        try Self.wrap { try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT COALESCE(language, '') AS code, COUNT(*) AS total, SUM(default_enabled) AS enabled
                FROM catalog_source GROUP BY COALESCE(language, '')
                ORDER BY (COALESCE(language, '') = '' OR language = 'und') ASC, enabled DESC, code COLLATE NOCASE
                """).map { row in
                LegacyCatalogLanguageRecord(code: row["code"], enabledSources: Int(row["enabled"] as Int64? ?? 0),
                    totalSources: Int(row["total"] as Int64? ?? 0))
            }
        } }
    }

    /// One bounded page of a node's children, ordered the way the index is (`parent_id, name COLLATE NOCASE`).
    /// `after` is the last node id of the previous page.
    public func nodes(parentID: Int64, after: Int64? = nil, limit: Int) throws -> LegacyCatalogNodePage {
        guard limit > 0 else { return LegacyCatalogNodePage(nodes: [], nextCursor: nil, exhausted: true) }
        return try Self.wrap { try queue.read { db in
            var sql = """
                SELECT id, key, name, kind, parent_id, source_count, child_count FROM catalog_node
                WHERE parent_id = ?
                """
            var arguments: [DatabaseValueConvertible] = [parentID]
            if let after { sql += " AND id > ?"; arguments.append(after) }
            sql += " ORDER BY name COLLATE NOCASE, id LIMIT ?"
            arguments.append(limit + 1)
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            let records = try rows.prefix(limit).map { try Self.node($0) }
            let exhausted = rows.count <= limit
            return LegacyCatalogNodePage(nodes: records, nextCursor: exhausted ? nil : records.last?.id,
                exhausted: exhausted)
        } }
    }

    /// The sections that sit directly under the root (`parent_id = 0`).
    public func sectionNodes(limit: Int = 100) throws -> [LegacyCatalogNodeRecord] {
        try nodes(parentID: 0, limit: limit).nodes
    }

    /// The countries the catalogue places sources in — the 101 `kind = 1` nodes of the bundled snapshot.
    public func countries(after: Int64? = nil, limit: Int) throws -> LegacyCatalogNodePage {
        guard limit > 0 else { return LegacyCatalogNodePage(nodes: [], nextCursor: nil, exhausted: true) }
        return try Self.wrap { try queue.read { db in
            var sql = "SELECT id, key, name, kind, parent_id, source_count, child_count FROM catalog_node WHERE kind = ?"
            var arguments: [DatabaseValueConvertible] = [LegacyCatalogNodeRecord.countryKind]
            if let after { sql += " AND id > ?"; arguments.append(after) }
            sql += " ORDER BY name COLLATE NOCASE, id LIMIT ?"
            arguments.append(limit + 1)
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            let records = try rows.prefix(limit).map { try Self.node($0) }
            let exhausted = rows.count <= limit
            return LegacyCatalogNodePage(nodes: records, nextCursor: exhausted ? nil : records.last?.id,
                exhausted: exhausted)
        } }
    }

    public func node(id: Int64) throws -> LegacyCatalogNodeRecord? {
        try Self.wrap { try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT id, key, name, kind, parent_id, source_count, child_count FROM catalog_node WHERE id = ?",
                arguments: [id]).map { try Self.node($0) }
        } }
    }

    public func node(key: String) throws -> LegacyCatalogNodeRecord? {
        try Self.wrap { try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT id, key, name, kind, parent_id, source_count, child_count FROM catalog_node WHERE key = ?",
                arguments: [key]).map { try Self.node($0) }
        } }
    }

    /// The path from the root down to (but not including) this node, for a breadcrumb.
    public func ancestors(ofNodeID id: Int64, ceiling: Int = 16) throws -> [LegacyCatalogNodeRecord] {
        try Self.wrap { try queue.read { db in
            var path: [LegacyCatalogNodeRecord] = []
            var current = try Self.nodeRecord(db, id: id)
            while let node = current, let parentID = node.parentID, path.count < ceiling {
                guard let parent = try Self.nodeRecord(db, id: parentID) else { break }
                path.insert(parent, at: 0)
                current = parent
            }
            return path
        } }
    }

    private static func nodeRecord(_ db: Database, id: Int64) throws -> LegacyCatalogNodeRecord? {
        try Row.fetchOne(db, sql: "SELECT id, key, name, kind, parent_id, source_count, child_count FROM catalog_node WHERE id = ?",
            arguments: [id]).map { try Self.node($0) }
    }

    /// Bounded literal name/key lookup; values never become SQL syntax.
    public func matchingNodes(query: String, limit: Int) throws -> [LegacyCatalogNodeRecord] {
        guard limit > 0 else { return [] }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let escaped = text.replacingOccurrences(of: "!", with: "!!").replacingOccurrences(of: "%", with: "!%")
            .replacingOccurrences(of: "_", with: "!_")
        return try Self.wrap { try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, key, name, kind, parent_id, source_count, child_count FROM catalog_node
                WHERE name LIKE ? ESCAPE '!' OR key LIKE ? ESCAPE '!'
                ORDER BY (name LIKE ? ESCAPE '!') DESC, name COLLATE NOCASE, id LIMIT ?
                """, arguments: ["%" + escaped + "%", "%" + escaped + "%", escaped + "%", limit]).map { try Self.node($0) }
        } }
    }

    private static func node(_ row: Row) throws -> LegacyCatalogNodeRecord {
        let id: Int64 = row["id"]
        let kind: Int64 = row["kind"]
        let sourceCount: Int64 = row["source_count"] ?? 0
        let childCount: Int64 = row["child_count"] ?? 0
        let parentID: Int64? = row["parent_id"]
        return LegacyCatalogNodeRecord(id: id, key: row["key"], name: row["name"], kind: Int(kind),
            parentID: parentID, sourceCount: Int(sourceCount), childCount: Int(childCount))
    }

    private static func wrap<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch let error as LegacyCatalogError { throw error }
        catch { throw LegacyCatalogError.storage(String(describing: error)) }
    }
}
