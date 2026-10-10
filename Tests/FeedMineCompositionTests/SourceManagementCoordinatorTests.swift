import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMineComposition

/// T7: the reader-facing catalog surface — values only, a typed absence when the asset is missing, and a
/// selection change that persists through the reader's own preferences.
final class SourceManagementCoordinatorTests: XCTestCase {
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
                    (2, 'countries', 0, 'Countries', 0, 30, 1),
                    (10, 'countries/br', 2, 'Brazil', 1, 30, 0);
                INSERT INTO catalog_source (id, key, title, declared_url, request_url, media_kind, language, default_enabled) VALUES
                    (100, 'https://a.example/feed', 'Alpha Feed', 'https://a.example/feed', 'https://a.example/feed', 'text', 'pt-BR', 1),
                    (101, 'https://b.example/feed', 'Beta Feed', 'https://b.example/feed', 'https://b.example/feed', 'audio', 'und', 1);
                INSERT INTO catalog_placement (id, source_id, node_id, node_name, opml_file, sort_order) VALUES
                    (1, 100, 10, 'Brazil', 'br.opml', 0), (2, 101, 10, 'Brazil', 'br.opml', 1);
                """)
        }
        return url
    }

    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    /// UI receives values, never reader records or rows; a missing asset is a typed absence.
    func testExposesValuesOnlyAndStatesAMissingCatalog() throws {
        let empty = SourceManagementCoordinator(catalogURL: nil, database: nil)
        XCTAssertFalse(empty.hasCatalog)
        XCTAssertThrowsError(try empty.languages()) { XCTAssertEqual($0 as? SourceManagementError, .catalogUnavailable) }
        XCTAssertThrowsError(try empty.sections()) { XCTAssertEqual($0 as? SourceManagementError, .catalogUnavailable) }
        XCTAssertThrowsError(try empty.searchSources("a")) { XCTAssertEqual($0 as? SourceManagementError, .catalogUnavailable) }

        let coordinator = SourceManagementCoordinator(catalogURL: try catalog(), database: try database())
        XCTAssertTrue(coordinator.hasCatalog)
        let languages = try coordinator.languages()
        XCTAssertEqual(languages.map(\.code), ["pt-BR", "und"])
        XCTAssertEqual(languages.first?.displayName.isEmpty, false)
        XCTAssertEqual(languages.first?.primarySubtag, "pt", "a regional code keeps its primary subtag")
        XCTAssertTrue(try XCTUnwrap(languages.last).isUndeclared)
        XCTAssertEqual(SourceManagementCoordinator.displayName(""), "Idioma não declarado")
        XCTAssertEqual(SourceManagementCoordinator.displayName("und"), "Idioma não declarado")
        XCTAssertEqual(try coordinator.sections().map(\.kind), [.section])
        let countries = try coordinator.countries(limit: 10)
        XCTAssertEqual(countries.values.map(\.name), ["Brazil"])
        XCTAssertEqual(countries.values.map(\.kind), [.country])
        XCTAssertTrue(countries.exhausted)
        let brazil = try XCTUnwrap(countries.values.first)
        XCTAssertEqual(try coordinator.breadcrumb(ofNodeID: brazil.id).map(\.name), ["Root", "Countries"])
        XCTAssertEqual(try coordinator.nodeByKey("countries/br"), brazil.id)
        let nodes = try coordinator.nodes(parentID: brazil.id, limit: 10)
        XCTAssertTrue(nodes.values.isEmpty, "a country with no children pages empty, not nil")
        XCTAssertTrue(nodes.exhausted)
        let sources = try coordinator.searchSources("alpha")
        XCTAssertEqual(sources.map(\.title), ["Alpha Feed"])
        XCTAssertEqual(sources.first?.id, "https://a.example/feed", "identity is the catalog key, not the integer")
        // A node's sources keep the catalogue's own order for that node, and page by placement position.
        let placed = try coordinator.sources(inNode: brazil.id, limit: 1)
        XCTAssertEqual(placed.values.map(\.title), ["Alpha Feed"])
        XCTAssertEqual(placed.values.first?.id, "https://a.example/feed")
        XCTAssertFalse(placed.exhausted)
        let rest = try coordinator.sources(inNode: brazil.id, after: placed.nextCursor, limit: 5)
        XCTAssertEqual(rest.values.map(\.title), ["Beta Feed"])
        XCTAssertTrue(rest.exhausted)
        XCTAssertTrue(try coordinator.sources(inNode: 999, limit: 5).values.isEmpty)
    }

    /// A selection change persists through the reader's preferences and bumps the version that fences restore.
    func testSelectionChangesPersistAndVersion() throws {
        let database = try database()
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: ["https://a.example/feed"])
        let coordinator = SourceManagementCoordinator(catalogURL: try catalog(), database: database)
        XCTAssertEqual(try coordinator.selection(), ["https://a.example/feed"])
        let version = try coordinator.setSelection(["https://a.example/feed", "https://b.example/feed"])
        XCTAssertEqual(version, 3, "a changed selection is a new version")
        XCTAssertEqual(try coordinator.selection().count, 2)
        XCTAssertEqual(try coordinator.setSelection(["https://b.example/feed", "https://a.example/feed"]), version,
            "reordering the same set is not a new selection (V2 fences restore on this)")
        XCTAssertThrowsError(try coordinator.setSelection([])) {
            XCTAssertEqual($0 as? SourceManagementError, .invalidSelection)
        }
    }

    /// V1's "whole region on/off": enabling a node merges its placed sources into the selection; disabling it
    /// removes them, and never leaves an empty selection.
    func testBulkNodeEnableAndDisablePersistThroughPreferences() throws {
        let database = try database()
        let preferences = ReaderPreferencesStore(database: database)
        // One source inside the node's subtree and one outside it, so a bulk change has something to keep.
        _ = try preferences.initialize(sourceKeys: ["https://a.example/feed", "https://other.example/feed"])
        let coordinator = SourceManagementCoordinator(catalogURL: try catalog(), database: database)
        let brazil = try XCTUnwrap(try coordinator.nodeByKey("countries/br"))
        let enabled = try coordinator.setEnabled(nodeID: brazil, enabled: true)
        XCTAssertEqual(enabled, 3, "adding a key is a new selection version")
        XCTAssertEqual(Set(try coordinator.selection()),
            ["https://a.example/feed", "https://b.example/feed", "https://other.example/feed"])
        // Enabling again is not a new selection: the set did not change.
        XCTAssertEqual(try coordinator.setEnabled(nodeID: brazil, enabled: true), enabled)
        // Disabling the node removes exactly its sources and keeps the reader's others.
        XCTAssertEqual(try coordinator.setEnabled(nodeID: brazil, enabled: false), enabled + 1)
        XCTAssertEqual(try coordinator.selection(), ["https://other.example/feed"])
        XCTAssertEqual(try coordinator.setEnabled(nodeID: brazil, enabled: false), enabled + 1,
            "its sources are already absent, so nothing changes")
        // Emptying the reader's whole selection is refused: V2 requires one source, and V1's "zero sources"
        // state has to arrive together with its empty-state UI (recorded as T7's open parity item).
        _ = try coordinator.setSelection(["https://a.example/feed"])
        XCTAssertThrowsError(try coordinator.setEnabled(nodeID: brazil, enabled: false)) {
            XCTAssertEqual($0 as? SourceManagementError, .invalidSelection)
        }
    }
}
