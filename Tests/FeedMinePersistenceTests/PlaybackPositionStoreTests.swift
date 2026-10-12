import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

/// Where the reader stopped listening, kept: one durable position per card, most recently heard first.
final class PlaybackPositionStoreTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }

    private func card() -> PublicationCardID { PublicationCardID() }

    /// A position is written, read back and overwritten: the same episode is one row, whatever the reader does.
    func testAPositionIsWrittenReadAndOverwritten() throws {
        let store = PlaybackPositionStore(database: try database())
        let id = card()
        XCTAssertNil(try store.position(for: id))
        try store.save(42.5, duration: 600, for: id)
        XCTAssertEqual(try store.position(for: id), ReaderPlaybackPosition(cardID: id, position: 42.5, duration: 600))
        try store.save(90, duration: 600, for: id)
        XCTAssertEqual(try store.position(for: id)?.position, 90)
    }

    /// A card that has no position is not a card with position zero: the difference is what makes "start from the
    /// beginning" and "continue" two different things.
    func testAnUnknownCardHasNoPosition() throws {
        let store = PlaybackPositionStore(database: try database())
        try store.save(10, duration: nil, for: card())
        XCTAssertNil(try store.position(for: card()))
    }

    /// Clearing is what completion does: after it there is nothing to come back to.
    func testClearingRemovesOnlyThatCardsPosition() throws {
        let store = PlaybackPositionStore(database: try database())
        let first = card(), second = card()
        try store.save(30, duration: 100, for: first)
        try store.save(70, duration: 100, for: second)
        try store.clear(for: first)
        XCTAssertNil(try store.position(for: first))
        XCTAssertEqual(try store.position(for: second)?.position, 70)
    }

    /// The schema refuses a negative position rather than storing one the player could then seek to.
    func testANegativePositionIsClampedByTheWriter() throws {
        let store = PlaybackPositionStore(database: try database())
        let id = card()
        try store.save(-5, duration: nil, for: id)
        XCTAssertEqual(try store.position(for: id)?.position, 0)
    }
}

