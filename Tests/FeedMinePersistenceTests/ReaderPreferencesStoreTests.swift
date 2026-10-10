import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence

final class ReaderPreferencesStoreTests: XCTestCase {
    func testSelectionAndContextPersistAndEmptyChangeIsAtomic() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let store = ReaderPreferencesStore(database: try RuntimeDatabase(location: location))
        let initial = try store.initialize(sourceKeys: ["a", "b"])
        XCTAssertEqual(initial.selectionVersion, 2)
        XCTAssertEqual(try store.updateSources(["a", "b"]), initial)
        XCTAssertEqual(try store.updateSources(["b", "a"]), initial, "reordering is the same selection")
        let selected = try store.updateSources(["b"])
        XCTAssertEqual(selected.selectionVersion, 3)
        let source = SourceID()
        let contextual = try store.setContext(.source(source))
        XCTAssertThrowsError(try store.updateSources([]))
        XCTAssertEqual(try store.load(), contextual)
        let reopened = ReaderPreferencesStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.load()?.sourceKeys, ["b"])
        XCTAssertEqual(try reopened.load()?.activeContext, .source(source))
    }

    /// T6: the stored active context is the whole identity, and a row written before that (a bare request)
    /// still loads — as the default surface of the request it recorded.
    func testActiveContextCarriesTheWholeIdentityAndReadsLegacyRows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let database = try RuntimeDatabase(location: location)
        let store = ReaderPreferencesStore(database: database)
        _ = try store.initialize(sourceKeys: ["a"])

        // A filtered identity with a preset survives a round trip.
        let key = ContextKey(request: .main, preset: .collection("c1"),
            filter: ReaderFilter(languages: ["pt", "en"], mood: .technical),
            searchScope: .contents)
        _ = try store.setContext(key)
        XCTAssertEqual(try store.load()?.activeContextKey, key)
        XCTAssertEqual(try store.load()?.activeContext, .main)
        // Equivalent selections are the same stored identity.
        let equivalent = ContextKey(request: .main, preset: .collection("c1"),
            filter: ReaderFilter(languages: ["en", "pt"], mood: .technical))
        _ = try store.setContext(equivalent)
        XCTAssertEqual(try store.load()?.activeContextKey, key)
        // A search keeps its query and gains the default scope.
        let search = try XCTUnwrap(SearchContext(query: "mercado"))
        _ = try store.setContext(.search(search))
        XCTAssertEqual(try store.load()?.activeContextKey.searchScope, .both)

        // A row written before T6 carried only a FeedContextRequest in the same column.
        let legacy = try JSONEncoder().encode(FeedContextRequest.source(SourceID()))
        try database.write { db in
            try db.execute(sql: "UPDATE reader_preferences SET active_context = ?", arguments: [legacy])
        }
        let loaded = try XCTUnwrap(try store.load())
        XCTAssertEqual(loaded.activeContext, try JSONDecoder().decode(FeedContextRequest.self, from: legacy))
        XCTAssertTrue(loaded.activeContextKey.isDefaultSurface,
            "a pre-T6 row is the default surface of the request it recorded")
        // And the plain-surface convenience still writes exactly that.
        _ = try store.setContext(.main)
        XCTAssertEqual(try store.load()?.activeContextKey, ContextKey(request: .main))
    }
}
