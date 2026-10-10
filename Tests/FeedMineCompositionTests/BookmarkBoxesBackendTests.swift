import Foundation
import XCTest
import FeedMineDomain
import FeedMineUI
@testable import FeedMinePersistence
import FeedMineComposition

/// T8: the boxes surface's values and intents. The store is exercised with a backend that records every intent
/// and can be told to fail, so "what is shown is what the store accepted" is a claim about behaviour, not luck.
@MainActor
final class BookmarkBoxesStoreTests: XCTestCase {
    private final class Backend: BookmarkBoxesBackend, @unchecked Sendable {
        var rows: [BookmarkBoxRow] = [
            .init(id: ReaderBookmarkList.defaultID, name: "Salvos", count: 2, isDefault: true, isPreferred: true),
            .init(id: "longreads", name: "Longreads", count: 0, isDefault: false, isPreferred: false),
        ]
        var failEverything = false
        private(set) var created: [String] = []
        private(set) var renamed: [(String, String)] = []
        private(set) var deleted: [String] = []
        private(set) var orders: [[String]] = []
        private(set) var preferred: [String?] = []

        private func guardFailure() throws { if failEverything { throw SourceManagementErrorDouble.unavailable } }

        func boxes() async throws -> [BookmarkBoxRow] { try guardFailure(); return rows }
        func create(name: String) async throws -> String {
            try guardFailure(); created.append(name); return UUID().uuidString
        }
        func rename(id: String, name: String) async throws {
            try guardFailure(); renamed.append((id, name))
        }
        func delete(id: String) async throws {
            try guardFailure()
            guard id != ReaderBookmarkList.defaultID else { throw SourceManagementErrorDouble.invalid }
            deleted.append(id)
        }
        func reorder(ids: [String]) async throws { try guardFailure(); orders.append(ids) }
        func setPreferred(id: String?) async throws { try guardFailure(); preferred.append(id) }
    }

    private enum SourceManagementErrorDouble: Error { case unavailable, invalid }

    func testLoadAndPreferredResolution() async {
        let backend = Backend()
        let store = BookmarkBoxesStore(backend: backend)
        await store.load()
        XCTAssertEqual(store.boxes.map(\.name), ["Salvos", "Longreads"])
        XCTAssertEqual(store.preferredID, ReaderBookmarkList.defaultID)
        XCTAssertNil(store.errorMessage)
        // A failed load is a stated message, and the rows it could not read are not invented.
        backend.failEverything = true
        await store.load()
        XCTAssertNotNil(store.errorMessage)
    }

    /// A backend that never marks a box preferred falls back to the default box — never to "no box".
    func testWithoutAPreferenceTheDefaultBoxIsWhereASaveLands() async {
        let backend = Backend()
        backend.rows = [.init(id: ReaderBookmarkList.defaultID, name: "Salvos", count: 0, isDefault: true,
            isPreferred: false)]
        let store = BookmarkBoxesStore(backend: backend)
        await store.load()
        XCTAssertEqual(store.preferredID, ReaderBookmarkList.defaultID)
    }

    func testIntentsReachTheBackendAndARefusalIsVisible() async {
        let backend = Backend()
        let store = BookmarkBoxesStore(backend: backend)
        await store.load()
        await store.create(named: "Longreads")
        XCTAssertEqual(backend.created, ["Longreads"])
        await store.rename(id: "longreads", to: "Leituras")
        XCTAssertEqual(backend.renamed.first?.1, "Leituras")
        await store.reorder(["longreads", ReaderBookmarkList.defaultID])
        XCTAssertEqual(backend.orders.first, ["longreads", ReaderBookmarkList.defaultID])
        await store.setPreferred(id: "longreads")
        XCTAssertEqual(backend.preferred, ["longreads"])
        // The default box cannot be deleted, and the screen says so instead of pretending it went away.
        await store.delete(id: ReaderBookmarkList.defaultID)
        XCTAssertTrue(backend.deleted.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        await store.delete(id: "longreads")
        XCTAssertEqual(backend.deleted, ["longreads"])
    }

    /// A failed reorder reloads the stored order: the screen never keeps an order the database never received.
    func testAFailedReorderFallsBackToTheStoredOrder() async {
        let backend = Backend()
        let store = BookmarkBoxesStore(backend: backend)
        await store.load()
        backend.failEverything = true
        await store.reorder(["longreads", ReaderBookmarkList.defaultID])
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.boxes.map(\.name), ["Salvos", "Longreads"], "the stored order, not the dragged one")
    }

    func testNamesAreTrimmedAndEmptinessIsRefused() {
        XCTAssertEqual(BookmarkBoxesStore.usableName("  Longreads "), "Longreads")
        XCTAssertNil(BookmarkBoxesStore.usableName("   "))
        XCTAssertNil(BookmarkBoxesStore.usableName("\n"))
    }
}

/// The backend the app actually uses, over the reader's own library and preferences.
final class ReaderBookmarkBoxesBackendTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    func testBoxesCarryTheirCountsAndTheReaderPreference() async throws {
        let database = try database()
        // The reader's preferences exist from their first launch; a box preference is written beside them.
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: ["https://a/feed"])
        let library = ReaderLibraryStore(database: database)
        let longreads = try library.createBookmarkList(named: "Longreads")
        let backend = ReaderBookmarkBoxesBackend(database: database)
        var rows = try await backend.boxes()
        XCTAssertEqual(rows.map(\.name), ["Salvos", "Longreads"])
        XCTAssertEqual(rows.map(\.isDefault), [true, false])
        XCTAssertEqual(rows.map(\.isPreferred), [true, false], "nothing preferred means the default box")
        XCTAssertEqual(rows.map(\.count), [0, 0])
        try await backend.setPreferred(id: longreads.id)
        rows = try await backend.boxes()
        XCTAssertEqual(rows.map(\.isPreferred), [false, true])
        // The preference is the same one the app reads when it saves a card.
        XCTAssertEqual(try ReaderPreferencesStore(database: database).load()?.preferredBookmarkListID, longreads.id)
        // Clearing it goes back to the default box rather than to nothing.
        try await backend.setPreferred(id: nil)
        XCTAssertNil(try ReaderPreferencesStore(database: database).load()?.preferredBookmarkListID)
        let cleared = try await backend.boxes()
        XCTAssertEqual(cleared.map(\.isPreferred), [true, false])
        // A preference for a box that no longer exists is refused instead of stored.
        XCTAssertThrowsError(try ReaderPreferencesStore(database: database).setPreferredBookmarkList("missing"))
        // Delete and reorder through the same boundary.
        try await backend.delete(id: longreads.id)
        let afterDelete = try await backend.boxes()
        XCTAssertEqual(afterDelete.map(\.name), ["Salvos"])
        let another = try await backend.create(name: "Depois")
        try await backend.reorder(ids: [another, ReaderBookmarkList.defaultID])
        let afterReorder = try await backend.boxes()
        XCTAssertEqual(afterReorder.map(\.name), ["Depois", "Salvos"])
    }
}
