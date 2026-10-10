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
        // A *malformed* change is still refused and still atomic (T7 relaxed emptiness, not validity):
        XCTAssertThrowsError(try store.updateSources(["", "b"]))
        XCTAssertEqual(try store.load(), contextual, "a refused write leaves nothing behind")
        // T7: emptying the selection is legal, atomic, and does not touch the surface the reader is on.
        let emptied = try store.updateSources([])
        XCTAssertEqual(emptied.selectionVersion, selected.selectionVersion + 1)
        XCTAssertEqual(emptied.activeContext, .source(source))
        XCTAssertEqual(try store.load()?.sourceKeys, [])
        let reopened = ReaderPreferencesStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.load()?.sourceKeys, [], "the reopened store states the emptied selection")
        XCTAssertEqual(try reopened.load()?.activeContext, .source(source))
    }

    /// T7: V1 allowed zero selected sources, and that state is now reachable again (the reader can empty the
    /// selection from source management). Only a malformed set is refused.
    func testEmptySelectionIsAStateAndNotAMalformedRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let store = ReaderPreferencesStore(database: database)
        let initial = try store.initialize(sourceKeys: ["a", "b"])
        let emptied = try store.updateSources([])
        XCTAssertTrue(emptied.sourceKeys.isEmpty)
        XCTAssertGreaterThan(emptied.selectionVersion, initial.selectionVersion, "emptying is a selection change")
        XCTAssertEqual(emptied.activeContextKey, initial.activeContextKey, "the surface is not the selection")
        XCTAssertEqual(try store.load()?.sourceKeys, [])
        // Malformed sets stay refused.
        XCTAssertThrowsError(try store.updateSources(["a", "a"]))
        XCTAssertThrowsError(try store.updateSources([""]))
    }

    /// T6: the expiry record lives with the preferences, and a fresh row reads as V1's default (auto-expire
    /// on, nothing set yet — which is not the same as "expired").
    func testFilterExpiryPersistsAndDefaultsForLegacyRows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let store = ReaderPreferencesStore(database: database)
        let initial = try store.initialize(sourceKeys: ["a"])
        XCTAssertTrue(initial.filterExpiry.isEnabled, "V1's four-hour rule is on by default")
        XCTAssertNil(initial.filterExpiry.startsAt)
        XCTAssertFalse(initial.filterExpiry.isExpired(at: Date()), "nothing set is not expired")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = try store.setFilterExpiry(ReaderFilterExpiry(isEnabled: true, startsAt: start))
        XCTAssertEqual(saved.filterExpiry.startsAt, start)
        XCTAssertEqual(try store.load()?.filterExpiry, saved.filterExpiry)
        // Turning the rule off persists too, and survives a reopened store.
        _ = try store.setFilterExpiry(ReaderFilterExpiry(isEnabled: false, startsAt: start))
        let reopened = try ReaderPreferencesStore(
            database: RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))).load()
        XCTAssertEqual(reopened?.filterExpiry.isEnabled, false)
        XCTAssertNil(reopened?.filterExpiry.expiresAt())
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
