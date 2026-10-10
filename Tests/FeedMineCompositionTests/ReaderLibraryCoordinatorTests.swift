import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition

/// T8: the library as the UI uses it — the product operations V1 offered from a context, and the identity a
/// saved context must carry so activating it is an ordinary T6 transition.
final class ReaderLibraryCoordinatorTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    /// V1's "Save as Smart Bookmark": the context is stored, and the stored key names its own preset — the
    /// current key cannot, because it was minted before the preset existed.
    func testSavingAContextMakesItsKeyNameItsOwnPreset() throws {
        let coordinator = ReaderLibraryCoordinator(database: try database())
        let search = try XCTUnwrap(SearchContext(query: "clima"))
        let live = ContextKey(request: .search(search), preset: .everything,
            filter: ReaderFilter(languages: ["pt"]))
        let preset = try coordinator.savePreset(named: "Clima", kind: .smartBookmark, from: live)
        XCTAssertEqual(preset.presetID, ReaderPresetID.smartFeed(preset.id))
        XCTAssertEqual(preset.key.preset, preset.presetID, "the saved key activates the preset it was saved as")
        XCTAssertEqual(preset.key.request, live.request)
        XCTAssertEqual(preset.key.filter, live.filter, "everything else about the context is kept verbatim")
        XCTAssertEqual(preset.key.searchScope, live.searchScope)
        // It reads back the same way, and a second save of the same context is a second preset, not an update:
        // V1 let the reader keep two smart feeds over the same search.
        XCTAssertEqual(try coordinator.preset(id: preset.id), preset)
        let second = try coordinator.savePreset(named: "Clima 2", kind: .smartBookmark, from: live)
        XCTAssertNotEqual(second.id, preset.id)
        XCTAssertEqual(try coordinator.presets().count, 2)
        // A curated preset names itself too.
        let curated = try coordinator.savePreset(named: "Minha", kind: .curatedFeed,
            from: ContextKey(request: .main))
        XCTAssertEqual(curated.presetID, ReaderPresetID.curatedFeed(curated.id))
        XCTAssertEqual(curated.key.preset, curated.presetID)
    }

    /// V1's "Collect these sources": one transaction, deduplicated, and no source is touched.
    func testCollectingSourcesFillsOneCollectionAndKeepsTheSelection() throws {
        let database = try database()
        let preferences = ReaderPreferencesStore(database: database)
        _ = try preferences.initialize(sourceKeys: ["https://a/feed", "https://b/feed"])
        let before = try XCTUnwrap(try preferences.load())
        let coordinator = ReaderLibraryCoordinator(database: database)
        let collection = try coordinator.collectSources(named: "Mercados",
            sourceKeys: ["https://a/feed", "https://b/feed", "https://a/feed"])
        XCTAssertEqual(try coordinator.sourceKeys(inCollection: collection.id),
            ["https://a/feed", "https://b/feed"])
        XCTAssertEqual(try coordinator.collections().map(\.name), ["Mercados"])
        XCTAssertEqual(try preferences.load(), before, "collecting sources never changes the selection")
        // An empty collection is a state, not an error: the reader names it now and fills it later.
        let empty = try coordinator.collectSources(named: "Depois", sourceKeys: [])
        XCTAssertTrue(try coordinator.sourceKeys(inCollection: empty.id).isEmpty)
        XCTAssertEqual(try coordinator.collections().map(\.name), ["Mercados", "Depois"])
        // A name that is only whitespace is refused, and nothing is created.
        XCTAssertThrowsError(try coordinator.collectSources(named: "  ", sourceKeys: ["https://a/feed"]))
        XCTAssertEqual(try coordinator.collections().count, 2)
    }

    /// Boxes through the same boundary: the default box is the card control's target and cannot be deleted.
    func testBoxOperationsThroughTheCoordinator() throws {
        let coordinator = ReaderLibraryCoordinator(database: try database())
        let box = try coordinator.createBookmarkList(named: "Longreads")
        XCTAssertFalse(try coordinator.deleteBookmarkList(id: ReaderBookmarkList.defaultID))
        XCTAssertTrue(try coordinator.deleteBookmarkList(id: box.id))
        XCTAssertEqual(try coordinator.bookmarkLists().map(\.name), ["Salvos"])
        XCTAssertEqual(try coordinator.reorderBookmarkLists([]).map(\.id), [ReaderBookmarkList.defaultID])
        XCTAssertNil(try coordinator.preset(id: "missing"))
        XCTAssertThrowsError(try coordinator.renameCollection(id: "missing", to: "X"))
    }
}
