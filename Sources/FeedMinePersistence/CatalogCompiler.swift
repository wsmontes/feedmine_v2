//
// File: CatalogCompiler.swift
// Module: FeedMinePersistence
//
// Responsibility:
// Compiling an OPML tree into the `catalog.sqlite` this app reads: the same database, the same schema and the
// same derivations V1's `scripts/build_catalog.py` produces. It runs in both places the catalogue is produced —
// on the device, when a published OPML revision is installed (PD-10), and in the release, where the bundled
// snapshot (the bootstrap) is compiled.
//
// The rules are the builder's, not V1's Swift debug compiler's (`feedmine/FeedEngine/SQLiteCatalogStore.swift`,
// a DEBUG-only diagnostic with a divergent schema): the DDL of `create_schema`, the metadata table of
// `compile_catalog`, the id rule of `stable_uint32` (85-101), the folder→node_path and media-kind derivations of
// `folder_nodes`/`iter_outline_occurrences` (202-278), and the two counters `scan_opml` keeps. The architect's
// constraint is explicit — the legacy bootstrap already produces a usable catalogue with reference evidence, and
// a second permanent implementation with different rules is exactly what must not be created — so this file
// reproduces behaviour, and `CatalogOPMLScan` records each place V1's Swift scanner departs from the builder and
// therefore was not followed.
//
// Publishing: the compiler writes a fresh database beside the caller's destination and renames it into place, so
// the destination is either the previous file or the complete new one, never a half-written catalogue. It never
// touches an active catalogue on its own: the caller passes the staging path it wants, verifies the returned
// report, and installs the pair (PD-10). Every result is checked — `PRAGMA integrity_check`, foreign keys, row
// counts against the build, and a real full-text query — before the rename.
//
// Does not own: the OPML input rules (`CatalogOPMLScan`), source identity (`FeedAddress`), whether a revision is
// worth compiling or installing (`CatalogSyncPolicy`, `CatalogInstallation`), the manifest that declares the
// artefact (`CatalogManifest`) or fetching the payload (`CatalogUpdateChannel`).
//
// Allowed dependencies: Foundation, GRDB (the same SQLite layer the reader uses), FeedMineDomain.
//
// Status:
// Production.
//

import Darwin
import FeedMineDomain
import Foundation
import GRDB

/// What one compilation produced, keyed the way the builder's `--json` report is keyed: the release path
/// (`scripts/bootstrap_catalog.py`) reads those keys, so a Swift compiler that replaces the Python one keeps the
/// report contract. `catalog_version` is the revision the compiled catalogue declares about itself in
/// `catalog_metadata` (microseconds, as the builder stamps it); it is this compiler's addition to the report,
/// because a caller recording what it built needs the revision the artefact claims.
public struct CatalogCompilationReport: Hashable, Sendable, Codable {
    /// The staging path the catalogue was written to.
    public let output: String
    public let catalogVersion: Int64
    public let fileCount: Int
    public let failedFileCount: Int
    public let invalidSourceCount: Int
    public let sourceCount: Int
    public let nodeCount: Int
    public let placementCount: Int
    public let duplicateOccurrenceCount: Int
    public let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case output
        case catalogVersion = "catalog_version"
        case fileCount = "file_count"
        case failedFileCount = "failed_file_count"
        case invalidSourceCount = "invalid_source_count"
        case sourceCount = "source_count"
        case nodeCount = "node_count"
        case placementCount = "placement_count"
        case duplicateOccurrenceCount = "duplicate_occurrence_count"
        case sizeBytes = "size_bytes"
    }

    public init(output: String, catalogVersion: Int64, fileCount: Int, failedFileCount: Int,
        invalidSourceCount: Int, sourceCount: Int, nodeCount: Int, placementCount: Int,
        duplicateOccurrenceCount: Int, sizeBytes: Int) {
        self.output = output
        self.catalogVersion = catalogVersion
        self.fileCount = fileCount
        self.failedFileCount = failedFileCount
        self.invalidSourceCount = invalidSourceCount
        self.sourceCount = sourceCount
        self.nodeCount = nodeCount
        self.placementCount = placementCount
        self.duplicateOccurrenceCount = duplicateOccurrenceCount
        self.sizeBytes = sizeBytes
    }

    /// The report as the builder writes it with `--manifest-output`: the same keys, sorted, pretty-printed, one
    /// trailing newline. The shape is the contract — a release path that records the report does not have to know
    /// which implementation produced it.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}

public enum CatalogCompilerError: Error, Equatable, Sendable {
    /// The tree root is not a readable directory.
    case feedsRootUnreadable(String)
    /// Two files declared the same feed identity. The builder refuses rather than pick one: the catalogue keys a
    /// source by its identity, so the two rows would be one source with two different titles.
    case sourceIdentityCollapse(key: String, firstURL: String, secondURL: String)
    /// Two different keys hashed to one source id.
    case sourceIDCollision(id: Int64, firstKey: String, secondKey: String)
    /// Two different node keys hashed to one node id.
    case nodeIDCollision(id: Int64, firstKey: String, secondKey: String)
    case storage(String)
    /// The compiled database failed its own checks and was not published.
    case verificationFailed(String)
}

/// Compiles an OPML tree into a v1-schema `catalog.sqlite`.
public struct CatalogCompiler: Sendable {
    public init() {}

    /// The id a catalog `key` is given, by the builder's own rule. Exposed because the id is part of the
    /// catalogue's contract (`catalog_node.id`, `catalog_source.id`, the full-text rowid) and a caller reconciling
    /// a rebuild against a stored selection or a stored placement needs the same number the build will use.
    public static func stableIdentifier(forKey key: String) -> Int64 {
        Int64(CatalogOPMLScan.stableUInt32(key))
    }

    /// Compiles the validated OPML tree rooted at `feedsRoot` into a new catalogue at `staging`, and returns what
    /// it produced. The destination is replaced atomically, and only after the result passed its checks; the
    /// caller decides when that file becomes the catalogue the app opens.
    public func compile(feedsRoot: URL, staging: URL) throws -> CatalogCompilationReport {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: feedsRoot.path, isDirectory: &isDirectory),
            isDirectory.boolValue else {
            throw CatalogCompilerError.feedsRootUnreadable(feedsRoot.path)
        }

        let scan = try CatalogOPMLScan.scanTree(at: feedsRoot)
        let build = try CatalogBuild(scan: scan)
        let catalogVersion = Int64((Date().timeIntervalSince1970 * 1_000_000).rounded())

        let directory = staging.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw CatalogCompilerError.storage(String(describing: error)) }
        let temporary = directory.appendingPathComponent(".\(staging.lastPathComponent).tmp")
        Self.removeIfPresent(temporary)

        var published = false
        defer { if !published { Self.removeIfPresent(temporary) } }

        do { try build.write(to: temporary, catalogVersion: catalogVersion) }
        catch let error as CatalogCompilerError { throw error }
        catch { throw CatalogCompilerError.storage(String(describing: error)) }
        try verify(temporary, build: build)
        try replace(temporary, with: staging)
        published = true

        var size = 0
        if let attributes = try? FileManager.default.attributesOfItem(atPath: staging.path) {
            size = attributes[FileAttributeKey.size] as? Int ?? 0
        }
        return CatalogCompilationReport(output: staging.path, catalogVersion: catalogVersion,
            fileCount: scan.fileCount, failedFileCount: scan.failedFileCount,
            invalidSourceCount: scan.invalidSourceCount, sourceCount: build.sources.count,
            nodeCount: build.nodes.count, placementCount: build.placements.count,
            duplicateOccurrenceCount: build.placements.count - build.sources.count, sizeBytes: size)
    }

    // MARK: - Verification

    /// The checks that stand between a written file and a published one. Reading the fresh database back through
    /// its own schema is what a reader will do to it next; a catalogue that cannot answer these is not published
    /// at all, rather than installed and found broken.
    private func verify(_ url: URL, build: CatalogBuild) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue: DatabaseQueue
        do { queue = try DatabaseQueue(path: url.path, configuration: configuration) }
        catch { throw CatalogCompilerError.verificationFailed("could not reopen the compiled catalogue: \(error)") }

        try queue.read { db in
            let tables = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
            for table in ["catalog_metadata", "catalog_source", "catalog_node", "catalog_placement"] {
                guard tables.contains(table) else {
                    throw CatalogCompilerError.verificationFailed("the compiled catalogue has no \(table) table")
                }
            }
            guard tables.contains("catalog_source_fts") else {
                throw CatalogCompilerError.verificationFailed("the compiled catalogue has no full-text index")
            }
            let integrity = try String.fetchAll(db, sql: "PRAGMA integrity_check")
            guard integrity == ["ok"] else {
                throw CatalogCompilerError.verificationFailed(
                    "integrity_check: \(integrity.prefix(3).joined(separator: "; "))")
            }
            guard try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty else {
                throw CatalogCompilerError.verificationFailed("a placement references a source or node that is gone")
            }

            let sources = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM catalog_source") ?? -1
            let nodes = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM catalog_node") ?? -1
            let placements = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM catalog_placement") ?? -1
            let metadata = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM catalog_metadata") ?? -1
            guard sources == build.sources.count, nodes == build.nodes.count,
                placements == build.placements.count, metadata == CatalogBuild.metadataKeyCount else {
                throw CatalogCompilerError.verificationFailed(
                    "the compiled catalogue holds \(sources)/\(nodes)/\(placements)/\(metadata) rows, not the "
                        + "\(build.sources.count)/\(build.nodes.count)/\(build.placements.count)/"
                        + "\(CatalogBuild.metadataKeyCount) it was built from")
            }

            // The full-text index is the one table nothing else verifies: it has to cover every source, and it has
            // to answer a real query, not merely be present.
            let indexed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM catalog_source_fts") ?? -1
            guard indexed == sources else {
                throw CatalogCompilerError.verificationFailed(
                    "the full-text index covers \(indexed) of \(sources) sources")
            }
            if let title = try String.fetchOne(db, sql: "SELECT title FROM catalog_source ORDER BY id LIMIT 1"),
                let token = Self.searchToken(of: title) {
                let hits = try Int.fetchOne(db,
                    sql: "SELECT COUNT(*) FROM catalog_source_fts WHERE catalog_source_fts MATCH ?",
                    arguments: [token]) ?? 0
                guard hits > 0 else {
                    throw CatalogCompilerError.verificationFailed(
                        "the full-text index answered nothing for \(token)")
                }
            }
        }
    }

    /// A quoted FTS5 term from a title: the first run of alphanumerics long enough to be a token. Quoted, so a
    /// title that happens to spell an FTS5 operator cannot turn a verification query into syntax.
    static func searchToken(of title: String) -> String? {
        var current = ""
        for character in title {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if current.count >= 2 {
                return "\"" + current + "\""
            } else {
                current = ""
            }
        }
        return current.count >= 2 ? "\"" + current + "\"" : nil
    }

    // MARK: - Publishing

    /// Replaces the destination with the compiled file in one step, as the builder's `os.replace` does. A reader
    /// holding the old catalogue keeps reading it until this returns; nobody ever opens a partial file.
    private func replace(_ temporary: URL, with destination: URL) throws {
        let moved = temporary.withUnsafeFileSystemRepresentation { from -> Int32 in
            destination.withUnsafeFileSystemRepresentation { to -> Int32 in
                guard let from, let to else { return -1 }
                return rename(from, to)
            }
        }
        guard moved == 0 else {
            throw CatalogCompilerError.storage(
                "could not publish \(destination.lastPathComponent): errno \(errno)")
        }
    }

    private static func removeIfPresent(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
    }
}

/// The compiled catalogue, before it is a database: the builder's `compile_catalog` dictionaries in the same
/// shapes, so the derivations (ids, collisions, counts, full-text paths) are the builder's.
private struct CatalogBuild {
    /// One `catalog_source` row. `declared_url` is the address the tree authored and `request_url` the address to
    /// fetch; the builder keeps them equal (it has no fetch transform at compile time) and so does this — the
    /// reader hands `requestURL` to the fetch path, and `key` is the identity both sides agree on.
    struct Source {
        let id: Int64
        let key: String
        let title: String
        let declaredURL: String
        let requestURL: String
        let displayHost: String?
        let mediaKind: String
        let language: String?
        let siteURL: String?
        let description: String?
        let tags: String?
        let nature: String?
        let activity: String?
        let latestItemAt: String?
        let qualityScore: Int?
        let defaultEnabled: Bool
        let feedType: String?
    }

    struct Node {
        let id: Int64
        let key: String
        let parentID: Int64?
        let name: String
        let kind: Int
        let language: String?
    }

    struct Placement {
        let id: Int64
        let sourceID: Int64
        let nodeID: Int64
        let nodeName: String
        let opmlFile: String
        let sortOrder: Int64
        let titleOverride: String?
        let languageOverride: String?
        let mediaKindOverride: String?
    }

    static let metadataKeyCount = 9

    let scan: CatalogScanResult
    let sources: [Source]
    let nodes: [String: Node]
    let placements: [Placement]
    let sourceCounts: [Int64: Int]
    let childCounts: [Int64: Int]
    let fullTextPaths: [Int64: [String]]

    init(scan: CatalogScanResult) throws {
        var sources: [Source] = []
        var sourceIndexByKey: [String: Int] = [:]
        var sourceKeysByID: [Int64: String] = [:]
        var nodes: [String: Node] = ["root": Node(id: 0, key: "root", parentID: nil, name: "Root",
            kind: CatalogNodeKind.topic, language: nil)]
        var nodeKeysByID: [Int64: String] = [0: "root"]
        var placements: [Placement] = []
        var sourceIDsByNode: [Int64: Set<Int64>] = [:]
        var fullTextPaths: [Int64: [String]] = [:]

        for occurrence in scan.occurrences where !occurrence.nodePath.isEmpty {
            let key = FeedAddress.identity(occurrence.declaredURL)
            let id = Int64(CatalogOPMLScan.stableUInt32(key))
            if let previous = sourceKeysByID[id], previous != key {
                throw CatalogCompilerError.sourceIDCollision(id: id, firstKey: previous, secondKey: key)
            }
            sourceKeysByID[id] = key
            if let index = sourceIndexByKey[key] {
                throw CatalogCompilerError.sourceIdentityCollapse(key: key,
                    firstURL: sources[index].declaredURL, secondURL: occurrence.declaredURL)
            }
            sourceIndexByKey[key] = sources.count
            sources.append(Source(id: id, key: key, title: occurrence.title, declaredURL: occurrence.declaredURL,
                requestURL: occurrence.requestURL, displayHost: CatalogOPMLScan.displayHost(occurrence.declaredURL),
                mediaKind: occurrence.mediaKind, language: occurrence.language, siteURL: occurrence.siteURL,
                description: occurrence.description, tags: occurrence.tags, nature: occurrence.nature,
                activity: occurrence.activity, latestItemAt: occurrence.latestItemAt,
                qualityScore: occurrence.qualityScore, defaultEnabled: occurrence.defaultEnabled,
                feedType: occurrence.feedType))

            var parentID: Int64 = 0
            var components: [String] = []
            var ancestorIDs: [Int64] = [0]
            for inputNode in occurrence.nodePath {
                components.append(inputNode.key)
                let nodeKey = components.joined(separator: "/")
                let nodeID = Int64(CatalogOPMLScan.stableUInt32(nodeKey))
                if let previous = nodeKeysByID[nodeID], previous != nodeKey {
                    throw CatalogCompilerError.nodeIDCollision(id: nodeID, firstKey: previous, secondKey: nodeKey)
                }
                nodeKeysByID[nodeID] = nodeKey
                if nodes[nodeKey] == nil {
                    nodes[nodeKey] = Node(id: nodeID, key: nodeKey, parentID: parentID, name: inputNode.name,
                        kind: inputNode.kind, language: inputNode.language)
                }
                parentID = nodeID
                ancestorIDs.append(nodeID)
            }

            placements.append(Placement(id: Int64(placements.count + 1), sourceID: id, nodeID: parentID,
                nodeName: occurrence.nodePath[occurrence.nodePath.count - 1].name, opmlFile: occurrence.opmlFile,
                sortOrder: Int64(occurrence.sortOrder), titleOverride: occurrence.titleOverride,
                languageOverride: occurrence.languageOverride, mediaKindOverride: occurrence.mediaKindOverride))
            for ancestorID in ancestorIDs { sourceIDsByNode[ancestorID, default: []].insert(id) }
            fullTextPaths[id, default: []].append(components.joined(separator: " "))
        }

        var childCounts: [Int64: Int] = [:]
        for node in nodes.values {
            guard let parentID = node.parentID else { continue }
            childCounts[parentID, default: 0] += 1
        }
        self.scan = scan
        self.sources = sources
        self.nodes = nodes
        self.placements = placements
        self.childCounts = childCounts
        self.fullTextPaths = fullTextPaths
        self.sourceCounts = sourceIDsByNode.mapValues(\.count)
    }

    /// The `catalog_source` rows in id order, as the builder inserts them.
    var orderedSources: [Source] { sources.sorted { $0.id < $1.id } }

    /// The `catalog_node` rows in the builder's order: the root first, then by depth and key, so a parent is
    /// always written before the child that references it.
    var orderedNodes: [Node] {
        nodes.values.sorted { lhs, rhs in
            let leftDepth = lhs.parentID == nil ? 0 : lhs.key.filter { $0 == "/" }.count + 1
            let rightDepth = rhs.parentID == nil ? 0 : rhs.key.filter { $0 == "/" }.count + 1
            if leftDepth != rightDepth { return leftDepth < rightDepth }
            return lhs.key < rhs.key
        }
    }

    /// The catalogue's own claims about itself, as the builder writes them. `schema_version` is the reader's own
    /// supported version, so a compiled catalogue can never declare a schema the reader would refuse.
    func metadata(catalogVersion: Int64) -> [(key: String, value: String)] {
        [("schema_version", String(LegacyCatalogReader.supportedSchemaVersion)),
         ("catalog_version", String(catalogVersion)),
         ("source_count", String(sources.count)),
         ("node_count", String(nodes.count)),
         ("placement_count", String(placements.count)),
         ("duplicate_occurrence_count", String(placements.count - sources.count)),
         ("file_count", String(scan.fileCount)),
         ("failed_file_count", String(scan.failedFileCount)),
         ("invalid_source_count", String(scan.invalidSourceCount))]
    }

    // MARK: - Writing

    /// The v1 DDL, as `build_catalog.create_schema` declares it. The reader's contract is the three tables and the
    /// columns it selects; the indexes are the builder's, and the order a surface pages in depends on them.
    static let schema = """
        CREATE TABLE catalog_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE catalog_node (
            id INTEGER PRIMARY KEY,
            key TEXT NOT NULL UNIQUE,
            parent_id INTEGER REFERENCES catalog_node(id),
            name TEXT NOT NULL,
            kind INTEGER NOT NULL,
            source_count INTEGER NOT NULL DEFAULT 0,
            child_count INTEGER NOT NULL DEFAULT 0,
            language TEXT
        );
        CREATE INDEX idx_catalog_node_parent_name
            ON catalog_node(parent_id, name COLLATE NOCASE, id);
        CREATE TABLE catalog_source (
            id INTEGER PRIMARY KEY,
            key TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            declared_url TEXT NOT NULL,
            request_url TEXT NOT NULL,
            display_host TEXT,
            media_kind TEXT NOT NULL,
            language TEXT,
            site_url TEXT,
            description TEXT,
            tags TEXT,
            nature TEXT,
            activity TEXT,
            latest_item_at TEXT,
            quality_score INTEGER,
            default_enabled INTEGER NOT NULL DEFAULT 1,
            type TEXT
        );
        CREATE INDEX idx_catalog_source_title
            ON catalog_source(title COLLATE NOCASE, id);
        CREATE TABLE catalog_placement (
            id INTEGER PRIMARY KEY,
            source_id INTEGER NOT NULL REFERENCES catalog_source(id) ON DELETE CASCADE,
            node_id INTEGER NOT NULL REFERENCES catalog_node(id) ON DELETE CASCADE,
            node_name TEXT NOT NULL,
            opml_file TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            title_override TEXT,
            language_override TEXT,
            media_kind_override TEXT,
            UNIQUE(source_id, node_id, opml_file, sort_order)
        );
        CREATE INDEX idx_catalog_placement_node_order
            ON catalog_placement(node_id, sort_order, source_id);
        CREATE INDEX idx_catalog_placement_source
            ON catalog_placement(source_id);
        CREATE VIRTUAL TABLE catalog_source_fts USING fts5(
            title,
            description,
            tags,
            display_host,
            language,
            media_kind,
            path
        );
        """

    /// Writes the whole catalogue in one transaction. Foreign keys are enforced (GRDB's default, and the
    /// builder's `PRAGMA foreign_keys = ON`), so no placement can outlive its source or node.
    func write(to url: URL, catalogVersion: Int64) throws {
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: Self.schema)

            let metadata = try db.makeStatement(sql: "INSERT INTO catalog_metadata (key, value) VALUES (?, ?)")
            for row in self.metadata(catalogVersion: catalogVersion) {
                try metadata.execute(arguments: [row.key, row.value])
            }

            let source = try db.makeStatement(sql: """
                INSERT INTO catalog_source
                    (id, key, title, declared_url, request_url, display_host, media_kind, language, site_url,
                     description, tags, nature, activity, latest_item_at, quality_score, default_enabled, type)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for row in self.orderedSources {
                let values: [(any DatabaseValueConvertible)?] = [row.id, row.key, row.title, row.declaredURL,
                    row.requestURL, row.displayHost, row.mediaKind, row.language, row.siteURL, row.description,
                    row.tags, row.nature, row.activity, row.latestItemAt, row.qualityScore,
                    row.defaultEnabled ? 1 : 0, row.feedType]
                try source.execute(arguments: StatementArguments(values))
            }

            let node = try db.makeStatement(sql: """
                INSERT INTO catalog_node (id, key, parent_id, name, kind, source_count, child_count, language)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for row in self.orderedNodes {
                let values: [(any DatabaseValueConvertible)?] = [row.id, row.key, row.parentID, row.name, row.kind,
                    self.sourceCounts[row.id] ?? 0, self.childCounts[row.id] ?? 0, row.language]
                try node.execute(arguments: StatementArguments(values))
            }

            let placement = try db.makeStatement(sql: """
                INSERT INTO catalog_placement
                    (id, source_id, node_id, node_name, opml_file, sort_order, title_override, language_override,
                     media_kind_override)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for row in self.placements {
                let values: [(any DatabaseValueConvertible)?] = [row.id, row.sourceID, row.nodeID, row.nodeName,
                    row.opmlFile, row.sortOrder, row.titleOverride, row.languageOverride, row.mediaKindOverride]
                try placement.execute(arguments: StatementArguments(values))
            }

            // The full-text table is a plain FTS5 table (not external content): the builder inserts one row per
            // source, keyed by the source id, and its `path` column is the source's placement keys with `/` read as
            // a space, so a taxonomy word is searchable.
            let fullText = try db.makeStatement(sql: """
                INSERT INTO catalog_source_fts
                    (rowid, title, description, tags, display_host, language, media_kind, path)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """)
            for row in self.sources {
                let values: [(any DatabaseValueConvertible)?] = [row.id, row.title, row.description ?? "",
                    row.tags ?? "", row.displayHost ?? "", row.language ?? "", row.mediaKind,
                    (self.fullTextPaths[row.id] ?? []).joined(separator: " ")]
                try fullText.execute(arguments: StatementArguments(values))
            }

            try db.execute(sql: "PRAGMA optimize")
        }
    }
}
