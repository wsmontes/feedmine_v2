import Foundation
import GRDB
import XCTest

@testable import FeedMinePersistence

/// The compiler against a catalogue that already exists. Two references, at two strengths:
///
/// * the frozen acceptance corpus in this repository (`bench/corpus/catalog.sqlite`, read-only, never written): it
///   is a slice of a catalogue the reference builder produced, so it pins the id rule — and therefore every
///   `catalog_source.key` derived from a real OPML tree — at catalogue scale;
/// * the tree that reference builder compiled, when the caller names it: `FEEDMINE_REFERENCE_FEEDS_ROOT` points at
///   an OPML tree, `FEEDMINE_REFERENCE_CATALOG` at the catalogue built from exactly that tree, and this test
///   compiles the tree and compares the two catalogues row by row. That is the only check that can settle "same
///   rules" for the whole derivation chain rather than for a fixture:
///
///       FEEDMINE_REFERENCE_FEEDS_ROOT=<tree> FEEDMINE_REFERENCE_CATALOG=<catalog.sqlite> \
///           [FEEDMINE_REFERENCE_STAGING=<new path>] swift test --filter CatalogCompilerReferenceTests
///
/// The comparison is keyed on the address the tree declared rather than on the compiled id, because identity is
/// the one column group where the app's transform (`FeedAddress`) and the builder's (`canonical_url`) are not
/// byte-identical — comparing by id would let one such row shift every row after it and hide real differences.
/// Identity differences are then *counted against a signature derived from the reference itself*, so a new kind
/// of divergence fails while the two known ones are measured rather than tolerated:
///
///   * an address with an explicit default port (`https://www.aljazeera.net:443/…`): the builder keys the port, the
///     app's identity transform drops it — a deliberate rule of the V1 Swift lineage that V2 inherited;
///   * an address with a punycode label (`https://xn--d1acibrhefqcr.bg/feed`): Foundation decodes the label into
///     Unicode, the builder keeps the ASCII the tree wrote.
///
/// Measured on the 118-file editorial tree (77,443 sources, 6,450 nodes): 12 identity differences (6 ports, 6
/// punycode) and 4 titles whose reference value begins with U+FEFF, which Foundation's XMLParser cannot carry
/// through (a raw BOM and its `&#xFEFF;` reference alike). Every other column of every table matches.
final class CatalogCompilerReferenceTests: XCTestCase {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func readOnlyQueue(_ url: URL) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.readonly = true
        return try DatabaseQueue(path: url.path, configuration: configuration)
    }

    // MARK: - The frozen corpus

    /// Every source and node id in a catalogue the reference builder compiled is the id this compiler derives.
    /// The root node is the one sentinel: the builder gives it id 0 and the key `root`, deliberately outside the
    /// hash, because 0 is the parent of every section.
    func testFrozenCorpusCatalogueUsesThisCompilersIdRule() throws {
        let url = Self.repositoryRoot.appendingPathComponent("bench/corpus/catalog.sqlite")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
            "the frozen corpus catalogue is not in this checkout")
        let queue = try readOnlyQueue(url)

        let sources = try queue.read { db in try Row.fetchAll(db, sql: "SELECT id, key FROM catalog_source") }
        XCTAssertFalse(sources.isEmpty)
        for row in sources {
            let id: Int64 = row["id"]
            let key: String = row["key"]
            XCTAssertEqual(id, CatalogCompiler.stableIdentifier(forKey: key), "source id for \(key)")
        }

        let nodes = try queue.read { db in try Row.fetchAll(db, sql: "SELECT id, key FROM catalog_node") }
        XCTAssertFalse(nodes.isEmpty)
        for row in nodes {
            let id: Int64 = row["id"]
            let key: String = row["key"]
            if key == "root" {
                XCTAssertEqual(id, 0)
            } else {
                XCTAssertEqual(id, CatalogCompiler.stableIdentifier(forKey: key), "node id for \(key)")
            }
        }
    }

    /// The corpus catalogue is also the reader's input in the acceptance runs, so the compiler's output has to be
    /// readable by the same reader and declare the same schema. Nothing here is written: the corpus is opened
    /// read-only.
    func testFrozenCorpusCatalogueIsReadableAndDeclaresTheSameSchema() throws {
        let url = Self.repositoryRoot.appendingPathComponent("bench/corpus/catalog.sqlite")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
            "the frozen corpus catalogue is not in this checkout")
        let reader = try LegacyCatalogReader(catalogURL: url)
        let metadata = try XCTUnwrap(reader.metadata())
        XCTAssertEqual(metadata.schemaVersion, LegacyCatalogReader.supportedSchemaVersion)
        XCTAssertEqual(try reader.sourceCount(), metadata.sourceCount)
        XCTAssertEqual(metadata.placementCount, metadata.sourceCount)
    }

    // MARK: - The whole derivation chain

    func testCompiledTreeMatchesTheReferenceCatalogueRowForRow() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let feedsRoot = environment["FEEDMINE_REFERENCE_FEEDS_ROOT"].map(URL.init(fileURLWithPath:)),
            let reference = environment["FEEDMINE_REFERENCE_CATALOG"].map(URL.init(fileURLWithPath:)) else {
            throw XCTSkip("set FEEDMINE_REFERENCE_FEEDS_ROOT and FEEDMINE_REFERENCE_CATALOG to compare a whole tree")
        }
        try XCTSkipUnless(FileManager.default.fileExists(atPath: reference.path),
            "no reference catalogue at \(reference.path)")

        // `FEEDMINE_REFERENCE_STAGING` keeps the compiled catalogue for inspection instead of a throwaway
        // directory — the caller's path then, so nothing is cleaned up.
        let override = environment["FEEDMINE_REFERENCE_STAGING"].map(URL.init(fileURLWithPath:))
        let staging = override ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-reference-\(UUID().uuidString)/catalog.sqlite")
        if override == nil {
            addTeardownBlock { try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
        }
        let report = try CatalogCompiler().compile(feedsRoot: feedsRoot, staging: staging)

        let produced = try readOnlyQueue(staging)
        let expected = try readOnlyQueue(reference)

        // 1. The taxonomy: no identity in it, so it is compared exactly.
        let nodesSQL = "SELECT key, parent_id, name, kind, source_count, child_count, language FROM catalog_node "
            + "ORDER BY key"
        XCTAssertEqual(try produced.read { try Self.renderedRows($0, nodesSQL) },
            try expected.read { try Self.renderedRows($0, nodesSQL) }, "catalog_node")

        // 2. The catalogue's own declaration, except the wall-clock revision.
        let metadataSQL = "SELECT key, value FROM catalog_metadata WHERE key <> 'catalog_version' ORDER BY key"
        XCTAssertEqual(try produced.read { try Self.renderedRows($0, metadataSQL) },
            try expected.read { try Self.renderedRows($0, metadataSQL) }, "catalog_metadata")

        // 3. Sources, one row per address the tree declared: every column that is a derivation of the tree, and
        //    the identity columns separately.
        let sources = try produced.read { try Self.sources($0) }
        let referenceSources = try expected.read { try Self.sources($0) }
        XCTAssertEqual(sources.count, referenceSources.count)
        XCTAssertEqual(Set(sources.keys), Set(referenceSources.keys),
            "the two catalogues must describe the same addresses")

        var byteOrderMarkTitles = 0
        var identityDivergences: [String] = []
        for (declared, row) in sources {
            guard let other = referenceSources[declared] else { continue }
            if row.title != other.title {
                if Self.withoutByteOrderMarks(row.title) == Self.withoutByteOrderMarks(other.title) {
                    byteOrderMarkTitles += 1
                } else {
                    XCTFail("\(declared): title is \(row.title.debugDescription), the reference has "
                        + "\(other.title.debugDescription)")
                }
            }
            for (name, value) in row.derivations {
                guard let referenceValue = other.derivations[name] else { return XCTFail("no \(name)") }
                if value != referenceValue {
                    XCTFail("\(declared): \(name) is \(value), the reference has \(referenceValue)")
                }
            }
            if row.key == other.key {
                XCTAssertEqual(row.id, other.id, "id of \(declared)")
            } else {
                identityDivergences.append(declared)
            }
        }
        XCTAssertEqual(identityDivergences.sorted(), Self.identityDivergenceSignatures(referenceSources),
            "identity may differ only where the builder's key carries a default port or a punycode label")
        XCTAssertEqual(byteOrderMarkTitles,
            referenceSources.values.filter { $0.title.hasPrefix("\u{FEFF}") }.count,
            "a title may differ only by a byte order mark the reference parser kept")
        print("reference comparison: \(sources.count) sources, \(identityDivergences.count) identity differences, "
            + "\(byteOrderMarkTitles) byte-order-mark titles")

        // 4. Placements and full-text rows, joined to the address they came from for the same reason as above.
        let placementsSQL = """
            SELECT s.declared_url, p.node_id, p.node_name, p.opml_file, p.sort_order, p.title_override,
                p.language_override, p.media_kind_override
            FROM catalog_placement p JOIN catalog_source s ON s.id = p.source_id
            ORDER BY s.declared_url, p.sort_order, p.opml_file
            """
        let fullTextSQL = """
            SELECT s.declared_url, f.title, f.description, f.tags, f.display_host, f.language, f.media_kind, f.path
            FROM catalog_source_fts f JOIN catalog_source s ON s.id = f.rowid
            ORDER BY s.declared_url
            """
        for (name, sql) in [("catalog_placement", placementsSQL), ("catalog_source_fts", fullTextSQL)] {
            let built = try produced.read { try Self.renderedRows($0, sql) }
                .map { Self.withoutByteOrderMarks($0) }
            let referenceRows = try expected.read { try Self.renderedRows($0, sql) }
                .map { Self.withoutByteOrderMarks($0) }
            XCTAssertEqual(built.count, referenceRows.count, "\(name): row count")
            if let difference = Self.firstDifference(built, referenceRows) {
                XCTFail("\(name): \(difference)")
            }
        }

        XCTAssertEqual(report.sourceCount, referenceSources.count)
        XCTAssertEqual(report.nodeCount, try expected.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM catalog_node") })
        XCTAssertEqual(report.placementCount,
            try expected.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM catalog_placement") })
    }

    // MARK: - Reading a catalogue into comparable rows

    /// One `catalog_source` row: the address it came from, its identity, and every column that is a derivation of
    /// the tree, by name.
    private struct SourceRow {
        let declared: String
        let key: String
        let id: Int64
        /// The catalogue's own title. Kept out of the column map because it is the one derivation a reference
        /// value may differ in by a byte order mark alone.
        let title: String
        let derivations: [String: String]
    }

    private static let derivationColumns = ["request_url", "display_host", "media_kind", "language",
        "site_url", "description", "tags", "nature", "activity", "latest_item_at", "quality_score",
        "default_enabled", "type"]

    private static func sources(_ db: Database) throws -> [String: SourceRow] {
        let sql = "SELECT declared_url, key, id, title, \(derivationColumns.joined(separator: ", ")) "
            + "FROM catalog_source"
        var result: [String: SourceRow] = [:]
        for row in try Row.fetchAll(db, sql: sql) {
            let declared: String = row["declared_url"]
            var derivations: [String: String] = [:]
            for column in derivationColumns { derivations[column] = String(describing: row[column]) }
            result[declared] = SourceRow(declared: declared, key: row["key"], id: row["id"], title: row["title"],
                derivations: derivations)
        }
        return result
    }

    /// The addresses whose identity may legitimately differ, from the reference keys themselves: a key with an
    /// explicit port the scheme already implies, or with a punycode label.
    private static func identityDivergenceSignatures(_ sources: [String: SourceRow]) -> [String] {
        sources.values.compactMap { row in
            guard let separator = row.key.range(of: "://") else { return nil }
            var authority = row.key[separator.upperBound...]
            if let end = authority.firstIndex(of: "/") { authority = authority[..<end] }
            let port = authority.contains(":") ? authority.split(separator: ":").last.map(String.init) : nil
            let defaultPort = (row.key.hasPrefix("https://") && port == "443")
                || (row.key.hasPrefix("http://") && port == "80")
            return defaultPort || authority.contains("xn--") ? row.declared : nil
        }.sorted()
    }

    /// One row per line, every column, `NULL` distinguished from the empty string by its own rendering.
    private static func renderedRows(_ db: Database, _ sql: String) throws -> [String] {
        try Row.fetchAll(db, sql: sql).map { row in
            row.databaseValues.map { $0.description }.joined(separator: "\u{1F}")
        }
    }

    private static func withoutByteOrderMarks(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{FEFF}", with: "")
    }

    private static func firstDifference(_ built: [String], _ reference: [String]) -> String? {
        for (index, pair) in zip(built, reference).enumerated() where pair.0 != pair.1 {
            return "row \(index) differs\n  compiled : \(pair.0)\n  reference: \(pair.1)"
        }
        return nil
    }
}
