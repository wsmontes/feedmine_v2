import Foundation
import XCTest
import GRDB
@testable import FeedMinePersistence

/// T7 metadata: languages with counts, the taxonomy tree and the countries subtree — the values T6's filter
/// sheet and T7's source management need, read from the shipped catalogue. Brief:
/// `docs/superpowers/specs/2026-10-10-t7-catalog-metadata-queries.md`.
final class LegacyCatalogMetadataTests: XCTestCase {
    /// A small catalogue shaped like the bundled one: a root, sections, a Countries section with countries,
    /// countries with topics, and sources carrying declared (dirty) languages.
    private func catalog() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE catalog_node (id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE, parent_id INTEGER,
                    name TEXT NOT NULL, kind INTEGER NOT NULL, source_count INTEGER NOT NULL DEFAULT 0,
                    child_count INTEGER NOT NULL DEFAULT 0, language TEXT);
                CREATE TABLE catalog_source (id INTEGER PRIMARY KEY, key TEXT NOT NULL UNIQUE, title TEXT NOT NULL,
                    declared_url TEXT NOT NULL, request_url TEXT NOT NULL, display_host TEXT, media_kind TEXT NOT NULL,
                    language TEXT, site_url TEXT, description TEXT, tags TEXT, nature TEXT, activity TEXT,
                    latest_item_at TEXT, quality_score INTEGER, default_enabled INTEGER NOT NULL DEFAULT 1,
                    type TEXT);
                CREATE TABLE catalog_placement (id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL, node_id INTEGER NOT NULL,
                    node_name TEXT NOT NULL, opml_file TEXT NOT NULL, sort_order INTEGER NOT NULL, title_override TEXT,
                    language_override TEXT, media_kind_override TEXT);
                INSERT INTO catalog_node (id, key, parent_id, name, kind, source_count, child_count) VALUES
                    (0, '0', NULL, 'Root', 0, 0, 2),
                    (1, 'news', 0, 'News', 0, 12, 1),
                    (2, 'countries', 0, 'Countries', 0, 30, 2),
                    (10, 'countries/br', 2, 'Brazil', 1, 20, 1),
                    (11, 'countries/pt', 2, 'Portugal', 1, 10, 0),
                    (12, 'countries/br/politics', 10, 'Politics', 3, 20, 0),
                    (13, 'news/world', 1, 'World', 3, 12, 0);
                INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, language, default_enabled) VALUES
                    (100, 'https://a.example/feed', 'A', 'https://a.example/feed', 'https://a.example/feed', 'text', 'en', 1),
                    (101, 'https://b.example/feed', 'B', 'https://b.example/feed', 'https://b.example/feed', 'text', 'en-US', 1),
                    (102, 'https://c.example/feed', 'C', 'https://c.example/feed', 'https://c.example/feed', 'audio', 'pt', 1),
                    (103, 'https://d.example/feed', 'D', 'https://d.example/feed', 'https://d.example/feed', 'text', NULL, 1),
                    (104, 'https://e.example/feed', 'E', 'https://e.example/feed', 'https://e.example/feed', 'text', 'und', 0);
                """)
        }
        return url
    }

    /// The sheet's language list: biggest enabled set first, the undeclared bucket last, with both counts.
    func testLanguagesAreOrderedWithCountsAndUndeclaredLast() throws {
        let reader = try LegacyCatalogReader(catalogURL: try catalog())
        let languages = try reader.languages()
        XCTAssertEqual(languages.map(\.code), ["en", "en-US", "pt", "", "und"],
            "enabled counts order the list; the undeclared buckets ('', 'und') come last")
        XCTAssertEqual(languages.first { $0.code == "en" }?.enabledSources, 1)
        XCTAssertEqual(languages.first { $0.code == "en-US" }?.enabledSources, 1)
        XCTAssertEqual(languages.first { $0.code == "und" }?.totalSources, 1)
        XCTAssertEqual(languages.first { $0.code == "und" }?.enabledSources, 0)
        XCTAssertTrue(try XCTUnwrap(languages.first { $0.code == "und" }).isUndeclared)
        XCTAssertTrue(try XCTUnwrap(languages.first { $0.code == "" }).isUndeclared)
        XCTAssertFalse(try XCTUnwrap(languages.first { $0.code == "en-US" }).isUndeclared)
        // A language filter compares the primary subtag, so "en-US" belongs to "en".
        XCTAssertEqual(try XCTUnwrap(languages.first { $0.code == "en-US" }).primarySubtag, "en")
        XCTAssertEqual(languages.reduce(0) { $0 + $1.totalSources }, 5, "every source is counted exactly once")
    }

    /// The tree: sections under the root, countries under the Countries section, topics under a country.
    func testTaxonomyTreeNavigatesByParentAndKeepsOrder() throws {
        let reader = try LegacyCatalogReader(catalogURL: try catalog())
        let sections = try reader.sectionNodes()
        XCTAssertEqual(sections.map(\.name), ["Countries", "News"], "the index orders by name, not by id")
        XCTAssertTrue(sections.allSatisfy(\.isSection))
        let countries = try reader.countries(limit: 10)
        XCTAssertEqual(countries.nodes.map(\.name), ["Brazil", "Portugal"])
        XCTAssertEqual(countries.nodes.map(\.sourceCount), [20, 10])
        XCTAssertTrue(countries.nodes.allSatisfy(\.isCountry))
        XCTAssertTrue(countries.exhausted)
        let brazil = try XCTUnwrap(countries.nodes.first { $0.name == "Brazil" })
        XCTAssertTrue(brazil.hasChildren)
        let topics = try reader.nodes(parentID: brazil.id, limit: 10)
        XCTAssertEqual(topics.nodes.map(\.name), ["Politics"])
        XCTAssertEqual(topics.nodes.first?.kind, LegacyCatalogNodeRecord.topicKind)
        XCTAssertEqual(try reader.node(key: "news/world")?.name, "World")
        XCTAssertNil(try reader.node(key: "nope"))
    }

    /// Paging is stable and terminates; the cursor is the last id of the page.
    func testNodePagingIsStable() throws {
        let reader = try LegacyCatalogReader(catalogURL: try catalog())
        let first = try reader.countries(limit: 1)
        XCTAssertEqual(first.nodes.map(\.name), ["Brazil"])
        XCTAssertEqual(first.nextCursor, 10)
        XCTAssertFalse(first.exhausted)
        let second = try reader.countries(after: first.nextCursor, limit: 1)
        XCTAssertEqual(second.nodes.map(\.name), ["Portugal"])
        XCTAssertTrue(second.exhausted)
    }

    /// The breadcrumb walks parents from the root down, and search matches name or key.
    func testAncestorsAndSearch() throws {
        let reader = try LegacyCatalogReader(catalogURL: try catalog())
        let brazil = try XCTUnwrap(try reader.node(key: "countries/br"))
        XCTAssertEqual(try reader.ancestors(ofNodeID: brazil.id).map(\.name), ["Root", "Countries"],
            "the path excludes the node itself")
        let politics = try XCTUnwrap(try reader.node(key: "countries/br/politics"))
        XCTAssertEqual(try reader.ancestors(ofNodeID: politics.id).map(\.name), ["Root", "Countries", "Brazil"])
        XCTAssertEqual(try reader.matchingNodes(query: "braz", limit: 5).map(\.name), ["Brazil"])
        XCTAssertEqual(try reader.matchingNodes(query: "news/world", limit: 5).map(\.name), ["World"],
            "the key is searchable too")
        XCTAssertEqual(try reader.matchingNodes(query: "%", limit: 5).count, 0,
            "a wildcard is a literal, never a pattern")
        XCTAssertEqual(try reader.matchingNodes(query: "  ", limit: 5).count, 0)
    }

    /// The real bundled snapshot, when it is present: the measured shape must hold there too.
    func testBundledSnapshotShapeWhenPresent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("FeedMineApp/FeedMineApp/Resources/catalog.sqlite")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("the bundled catalogue is a release asset; run scripts/fetch-catalog.sh")
        }
        let reader = try LegacyCatalogReader(catalogURL: url)
        XCTAssertEqual(try reader.sourceCount(), 77_443)
        let sections = try reader.sectionNodes()
        XCTAssertEqual(sections.count, 18, "measured 2026-10-09 (the 19th kind-0 node is the root itself)")
        XCTAssertTrue(sections.contains { $0.name == "Countries" && $0.sourceCount > 60_000 })
        let countries = try reader.countries(limit: 200)
        XCTAssertEqual(countries.nodes.count, 101, "measured 2026-10-09")
        XCTAssertTrue(countries.exhausted, "101 is the whole subtree")
        let languages = try reader.languages()
        XCTAssertEqual(languages.count, 257, "measured 2026-10-09: 257 distinct declared codes")
        XCTAssertEqual(languages.reduce(0) { $0 + $1.totalSources }, 77_443,
            "every source is counted in exactly one bucket")
        XCTAssertEqual(languages.last?.code, "und", "the undeclared bucket sorts last")
        XCTAssertTrue(try XCTUnwrap(languages.last).isUndeclared)
        XCTAssertEqual(try XCTUnwrap(languages.last).enabledSources, 26_644, "measured 2026-10-09")
        // Declared buckets are ordered by enabled count, descending (V1's list shape).
        let declared = languages.filter { !$0.isUndeclared }
        XCTAssertEqual(declared.first?.code, "en")
        XCTAssertEqual(declared.map(\.enabledSources), declared.map(\.enabledSources).sorted(by: >))
    }
}
