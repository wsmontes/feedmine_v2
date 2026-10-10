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

    public init(key: String, title: String, requestURL: String, siteURL: String?, language: String?, mediaKind: String,
        qualityScore: Int?, defaultEnabled: Bool, nodeKeys: [String]) {
        self.key = key; self.title = title; self.requestURL = requestURL; self.siteURL = siteURL
        self.language = language; self.mediaKind = mediaKind; self.qualityScore = qualityScore
        self.defaultEnabled = defaultEnabled; self.nodeKeys = nodeKeys
    }
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

    /// V1 compared the primary subtag when a feed declared "pt-BR" and the reader selected "pt".
    public var primarySubtag: String {
        String(code.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
    }
    public var isUndeclared: Bool { code.isEmpty || primarySubtag == "und" }
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

public struct LegacyCatalogNodePage: Hashable, Sendable {
    public let nodes: [LegacyCatalogNodeRecord]
    public let nextCursor: Int64?
    public let exhausted: Bool

    public init(nodes: [LegacyCatalogNodeRecord], nextCursor: Int64?, exhausted: Bool) {
        self.nodes = nodes; self.nextCursor = nextCursor; self.exhausted = exhausted
    }
}

public struct LegacyCatalogReader: Sendable {
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
                        s.quality_score, s.default_enabled
                    FROM catalog_source s \(whereClause)
                    ORDER BY s.key LIMIT ?
                    """, arguments: StatementArguments(arguments))
                return try rows.map { row in
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
            }
        }
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
