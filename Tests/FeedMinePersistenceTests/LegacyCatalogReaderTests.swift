import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

/// PD-2: the v1 catalog is read-only input, paged in stable key order with v1 filters.
final class LegacyCatalogReaderTests: XCTestCase {
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
                    contact_email TEXT, contact_name TEXT, contact_source TEXT, contact_type TEXT);
                CREATE TABLE catalog_placement (id INTEGER PRIMARY KEY, source_id INTEGER NOT NULL, node_id INTEGER NOT NULL,
                    node_name TEXT NOT NULL, opml_file TEXT NOT NULL, sort_order INTEGER NOT NULL, title_override TEXT,
                    language_override TEXT, media_kind_override TEXT);
                INSERT INTO catalog_node (id, key, name, kind) VALUES (1, 'news/world', 'World', 0), (2, 'science', 'Science', 0);
                INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, language, quality_score, default_enabled) VALUES
                    (10, 'https://b.example/feed', 'B', 'http://b.example/feed', 'https://b.example/feed?sig=1', 'text', 'pt', 80, 1),
                    (11, 'https://a.example/rss', 'A', 'https://a.example/rss', 'https://a.example/rss', 'text', 'en', NULL, 1),
                    (12, 'https://c.example/pod', 'C', 'https://c.example/pod', 'https://c.example/pod', 'audio', NULL, NULL, 1),
                    (13, 'https://d.example/off', 'D', 'https://d.example/off', 'https://d.example/off', 'text', NULL, NULL, 0);
                INSERT INTO catalog_placement (source_id, node_id, node_name, opml_file, sort_order) VALUES
                    (10, 2, 'Science', 'x.opml', 0), (10, 1, 'World', 'y.opml', 1), (11, 1, 'World', 'y.opml', 0);
                """)
        }
        return url
    }

    func testPagesInKeyOrderWithFiltersAndPlacements() throws {
        let reader = try LegacyCatalogReader(catalogURL: try catalog())
        XCTAssertEqual(try reader.sourceCount(), 4)
        let first = try reader.sources(after: nil, limit: 1, onlyDefaultEnabled: true, mediaKinds: ["text"])
        XCTAssertEqual(first.map(\.key), ["https://a.example/rss"])
        let rest = try reader.sources(after: first.last?.key, limit: 10, onlyDefaultEnabled: true, mediaKinds: ["text"])
        XCTAssertEqual(rest.map(\.key), ["https://b.example/feed"])
        XCTAssertEqual(rest[0].requestURL, "https://b.example/feed?sig=1")
        XCTAssertEqual(rest[0].nodeKeys, ["news/world", "science"])
        XCTAssertEqual(rest[0].qualityScore, 80)
        let all = try reader.sources(after: nil, limit: 10, onlyDefaultEnabled: false, mediaKinds: [])
        XCTAssertEqual(all.map(\.key).count, 4)
        XCTAssertFalse(all.first { $0.key.contains("d.example") }?.defaultEnabled ?? true)
    }

    func testRejectsNonCatalogDatabase() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try DatabaseQueue(path: url.path).write { try $0.execute(sql: "CREATE TABLE other (id INTEGER)") }
        XCTAssertThrowsError(try LegacyCatalogReader(catalogURL: url)) { XCTAssertEqual($0 as? LegacyCatalogError, .unsupportedSchema) }
    }
    func testExactIdentityLookupPreservesRequestURLAndRejectsMissingKey() throws {
        let reader = try LegacyCatalogReader(catalogURL: try catalog())
        let found = try XCTUnwrap(reader.source(key: "https://b.example/feed"))
        XCTAssertEqual(found.requestURL, "https://b.example/feed?sig=1")
        XCTAssertEqual(found.nodeKeys, ["news/world", "science"])
        XCTAssertNil(try reader.source(key: "missing' OR 1=1 --"))
    }

    /// P07/R14: the expression is applied **before** any literal truncation. Positives may land in different
    /// fields (title, taxonomy, tags, key), negatives exclude, diacritics fold, and the page states its truncation.
    func testExpressionMatchesAcrossFieldsNegativesDiacriticsAndPages() throws {
        let url = try catalog()
        try DatabaseQueue(path: url.path).write { db in
            try db.execute(sql: """
                INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, tags, default_enabled)
                VALUES (15, 'https://ocean.example/feed', 'Deep Ocean', 'https://ocean.example/feed',
                        'https://ocean.example/feed', 'text', 'nature', 1),
                       (16, 'https://astro.example/feed', 'Ocean Astrology', 'https://astro.example/feed',
                        'https://astro.example/feed', 'text', NULL, 1),
                       (17, 'https://es.example/feed', 'Astronomía', 'https://es.example/feed',
                        'https://es.example/feed', 'text', NULL, 1);
                INSERT INTO catalog_placement (source_id, node_id, node_name, opml_file, sort_order)
                VALUES (15, 2, 'Science', 'x.opml', 0);
                """)
        }
        let reader = try LegacyCatalogReader(catalogURL: url)

        // "deep" is in the title and "science" only in the taxonomy: the whole-string LIKE could never see it.
        let split = try reader.matchingSources(expression: try XCTUnwrap(SearchExpression(query: "deep science")),
            limit: 10)
        XCTAssertEqual(split.records.map(\.key), ["https://ocean.example/feed"])

        let negative = try reader.matchingSources(
            expression: try XCTUnwrap(SearchExpression(query: "ocean -astrology")), limit: 10)
        XCTAssertEqual(negative.records.map(\.key), ["https://ocean.example/feed"])

        let folded = try reader.matchingSources(
            expression: try XCTUnwrap(SearchExpression(query: "astronomia")), limit: 10)
        XCTAssertEqual(folded.records.map(\.key), ["https://es.example/feed"])

        let byTag = try reader.matchingSources(
            expression: try XCTUnwrap(SearchExpression(query: "nature")), limit: 10)
        XCTAssertEqual(byTag.records.map(\.key), ["https://ocean.example/feed"])

        // A bounded page says it is not the whole universe; the next page starts after it without duplicates.
        let firstPage = try reader.matchingSources(
            expression: try XCTUnwrap(SearchExpression(query: "example")), limit: 2)
        XCTAssertTrue(firstPage.truncated)
        XCTAssertEqual(firstPage.records.count, 2)
        let secondPage = try reader.matchingSources(
            expression: try XCTUnwrap(SearchExpression(query: "example")), limit: 10, offset: 2)
        XCTAssertFalse(secondPage.truncated)
        XCTAssertTrue(Set(firstPage.records.map(\.key)).isDisjoint(with: secondPage.records.map(\.key)))
    }

    /// Search order: title prefix, then v1 sort key (default_enabled, quality descending, title).
    func testSearchRanksByTitlePrefixThenQuality() throws {
        let url = try catalog()
        try DatabaseQueue(path: url.path).write { db in
            try db.execute(sql: """
                INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, quality_score, default_enabled)
                VALUES (14, 'https://e.example/feed', 'E', 'https://e.example/feed', 'https://e.example/feed', 'text', 40, 1)
                """)
        }
        let reader = try LegacyCatalogReader(catalogURL: url)
        // Matches by key: B (80) before E (40) proves descending quality; unscored A next; disabled D last.
        XCTAssertEqual(try reader.matchingSources(query: "example", limit: 10).map(\.title), ["B", "E", "A", "D"])
        // "A" is a title prefix only for A, so A comes first despite B's score.
        XCTAssertEqual(try reader.matchingSources(query: "a", limit: 10).first?.title, "A")
        XCTAssertEqual(try reader.matchingSources(query: "100%_", limit: 10), [])
    }

}
