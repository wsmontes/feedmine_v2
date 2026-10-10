import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMineComposition
import FeedMineUI

/// T7: the one boundary where the source surface's protocol (UI) meets the catalog coordinator
/// (Composition). The store's protocol is exercised here against a *real* catalog file and a real
/// preferences database, not against a recording double, so the adapter's mapping is what is proven.
final class SourceCatalogBackendTests: XCTestCase {
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
                    (0, '0', NULL, 'Root', 0, 0, 1),
                    (2, 'countries', 0, 'Countries', 0, 3, 1),
                    (10, 'countries/br', 2, 'Brazil', 1, 3, 1),
                    (30, 'countries/br/sao-paulo', 10, 'São Paulo', 3, 2, 0);
                INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, language, default_enabled) VALUES
                    (100, 'https://a.example/feed', 'Alpha', 'https://a.example/feed', 'https://a.example/feed', 'text', 'pt-BR', 1),
                    (101, 'https://b.example/feed', 'Beta', 'https://b.example/feed', 'https://b.example/feed', 'audio', 'und', 1),
                    (102, 'https://c.example/feed', 'Gamma', 'https://c.example/feed', 'https://c.example/feed', 'video', 'en', 1);
                INSERT INTO catalog_placement (id, source_id, node_id, node_name, opml_file, sort_order) VALUES
                    (1, 100, 10, 'Brazil', 'br.opml', 0), (2, 101, 10, 'Brazil', 'br.opml', 1),
                    (3, 102, 30, 'São Paulo', 'sp.opml', 0);
                """)
        }
        return url
    }

    private func backend() throws -> (SourceCatalogBackend, RuntimeDatabase) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a.example/feed"])
        let coordinator = SourceManagementCoordinator(catalogURL: try catalog(), database: database)
        return (SourceCatalogBackend(coordinator: coordinator), database)
    }

    /// Every read the surface performs, through the adapter, over the real catalog file.
    func testReadsMapTheCatalogToTheSurfaceValues() async throws {
        let (backend, _) = try backend()
        let sections = try await backend.sections()
        XCTAssertEqual(sections.map(\.key), ["countries"])
        let countries = try await backend.countries()
        XCTAssertEqual(countries.map(\.name), ["Brazil"])
        let brazil = try XCTUnwrap(countries.first)
        let children = try await backend.children(of: brazil)
        XCTAssertEqual(children.map(\.name), ["São Paulo"])
        XCTAssertEqual(children.map(\.kind), [.topic], "a child's kind reaches the surface as a value")
        let sources = try await backend.sources(in: brazil)
        XCTAssertEqual(sources.map(\.title), ["Alpha", "Beta"], "the node's own sources, in the catalog's order")
        XCTAssertEqual(sources.first?.mediaKind, "text")
        // One read for the whole level: each child with its own keys.
        let childKeys = try await backend.childKeys(of: brazil)
        XCTAssertEqual(childKeys[children[0].id], ["https://c.example/feed"])
        // V1's search is scoped to text sources, and that rule is kept: the audio and video sources in this
        // catalog are not offered by it.
        let results = try await backend.searchSources("alpha")
        XCTAssertEqual(results.map(\.title), ["Alpha"])
        let audioOnly = try await backend.searchSources("beta")
        XCTAssertTrue(audioOnly.isEmpty, "an audio source is not a text search result")
        let selected = try await backend.selection()
        XCTAssertEqual(selected, ["https://a.example/feed"])
    }

    /// The health the surface reads is the app's own observation, passed through untouched (the catalog knows
    /// nothing about reachability), and an app that has observed nothing states nothing.
    func testHealthComesFromTheCallerAndDefaultsToNothingObserved() async throws {
        let (silent, _) = try backend()
        let none = try await silent.health()
        XCTAssertTrue(none.isEmpty, "nothing observed is not a health claim")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let backend = SourceCatalogBackend(
            coordinator: SourceManagementCoordinator(catalogURL: try catalog(), database: database),
            healthProvider: { ["https://a.example/feed": .init(state: .failing(consecutive: 2))] })
        let observed = try await backend.health()
        XCTAssertEqual(observed["https://a.example/feed"]?.failures, 2)
    }

    /// Writes: a whole-node change and a direct selection both reach the reader's own preferences, and the
    /// version the store reads back is the one the app fences its session on.
    func testWritesReachTheReaderSelection() async throws {
        let (backend, database) = try backend()
        let countries = try await backend.countries()
        let brazil = try XCTUnwrap(countries.first)
        try await backend.setEnabled(node: brazil, enabled: true)
        let afterBulk = try await backend.selection()
        XCTAssertEqual(Set(afterBulk), ["https://a.example/feed", "https://b.example/feed"])
        try await backend.setSelection(["https://c.example/feed"])
        let afterDirect = try await backend.selection()
        XCTAssertEqual(afterDirect, ["https://c.example/feed"])
        // The same rows the app reads when the source surface closes.
        let record = try XCTUnwrap(try ReaderPreferencesStore(database: database).load())
        XCTAssertEqual(record.sourceKeys, ["https://c.example/feed"])
        XCTAssertGreaterThan(record.selectionVersion, 2)
        // An emptied selection is legal through this path too.
        try await backend.setSelection([])
        let afterEmptying = try await backend.selection()
        XCTAssertTrue(afterEmptying.isEmpty)
    }
}
