import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence

final class ReaderPreferencesStoreTests: XCTestCase {
    func testSelectionAndContextPersistAndEmptyChangeIsAtomic() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let store = ReaderPreferencesStore(database: try RuntimeDatabase(location: location))
        let initial = try store.initialize(sourceKeys: ["a", "b"])
        XCTAssertEqual(initial.selectionVersion, 2)
        XCTAssertEqual(try store.updateSources(["a", "b"]), initial)
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
}
