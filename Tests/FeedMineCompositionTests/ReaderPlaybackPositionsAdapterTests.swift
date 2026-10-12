import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition
import FeedMineRuntime

/// The player's own memory, as the app hands it over: durable writes, V1's threshold applied on the way out, and
/// completion clearing what it should.
final class ReaderPlaybackPositionsAdapterTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    @MainActor
    func testPositionsAreDurableAndOnlyPastTheThresholdAreOffered() throws {
        let database = try database()
        let adapter = ReaderPlaybackPositionsAdapter(database: database)
        let card = PublicationCardID()

        adapter.save(position: 4, duration: 600, for: card)
        XCTAssertNil(adapter.position(for: card), "four seconds in is not worth resuming (V1's five)")

        adapter.save(position: 42, duration: 600, for: card)
        XCTAssertEqual(adapter.position(for: card), 42)

        // A fresh adapter over the same database sees the same position: this is what a relaunch does.
        let reopened = ReaderPlaybackPositionsAdapter(database: database)
        XCTAssertEqual(reopened.position(for: card), 42)
        XCTAssertEqual(try PlaybackPositionStore(database: database).position(for: card)?.duration, 600)

        adapter.clear(cardID: card)
        XCTAssertNil(reopened.position(for: card))
    }

    /// A position of zero is not written (there is nothing to come back to), and a writer that cannot open a
    /// database simply has no memory instead of failing the playback that asked it.
    @MainActor
    func testAWriterWithoutADatabaseHasNoMemory() {
        let adapter = ReaderPlaybackPositionsAdapter(database: { nil })
        let card = PublicationCardID()
        adapter.save(position: 30, duration: nil, for: card)
        XCTAssertNil(adapter.position(for: card))
        adapter.clear(cardID: card)
    }
}
