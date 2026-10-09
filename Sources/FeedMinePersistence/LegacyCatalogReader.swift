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

    private static func wrap<T>(_ body: () throws -> T) throws -> T {
        do { return try body() }
        catch let error as LegacyCatalogError { throw error }
        catch { throw LegacyCatalogError.storage(String(describing: error)) }
    }
}
