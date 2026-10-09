import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence

final class PublicationMediaUseTests: XCTestCase {
    func testSharedBookmarkSurvivesReopenAndProtectsUnseenTail() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let store = PublicationStore(database: database), edition = StorageFixture.edition()
        let cards = (0..<3).map { _ in StorageFixture.card() }
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, cards), cards: cards)
        try store.markSeen(editionID: edition.id, cardID: cards[0].id)
        try store.toggleBookmark(cardID: cards[2].id, at: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try store.bookmarkedCardIDs(), [cards[2].id])
        let facts = try store.mediaUsage()
        XCTAssertTrue(try XCTUnwrap(facts[cards[0].mediaKey!]).bookmarked, "Shared asset inherits protection")
        let lease = try XCTUnwrap(store.hiddenTail(editionID: edition.id))
        XCTAssertEqual(try store.succeedTail(lease: lease, segmentID: FeedSegmentID(), cards: [StorageFixture.card()], createdAt: Date()), .ineligible)
        let reopened = try RuntimeDatabase(location: .init(directory: directory))
        XCTAssertEqual(try PublicationStore(database: reopened).bookmarkedCardIDs(), [cards[2].id])
        try store.toggleBookmark(cardID: cards[2].id, at: Date())
        XCTAssertFalse(try XCTUnwrap(store.mediaUsage()[cards[0].mediaKey!]).bookmarked)
    }
}
