import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence

final class PublicationHiddenTailLeaseTests: XCTestCase {
    private func editionWithUnseenAdmittedCards() throws -> (PublicationStore, FeedEditionID, [PublicationStore.CardRecord]) {
        let store = PublicationStore(database: try StorageFixture.database(self))
        let edition = StorageFixture.edition()
        let cards = (0..<6).map { _ in StorageFixture.card() }
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, Array(cards[0..<2])),
            cards: Array(cards[0..<2]))
        try store.appendSegment(StorageFixture.segment(edition, Array(cards[2..<4]), ordinal: 1),
            cards: Array(cards[2..<4]))
        try store.appendSegment(StorageFixture.segment(edition, Array(cards[4..<6]), ordinal: 2),
            cards: Array(cards[4..<6]))
        // Only the first card was seen; the UI already admitted cards 0...3.
        try store.markSeen(editionID: edition.id, cardID: cards[0].id)
        return (store, edition.id, cards)
    }

    func testK14HiddenTailPreservesAdmittedBeyondSeenHighWater() throws {
        let (store, editionID, cards) = try editionWithUnseenAdmittedCards()
        let lease = try XCTUnwrap(store.hiddenTail(editionID: editionID, protectingThrough: cards[3].id))
        XCTAssertEqual(lease.highWaterCardID, cards[0].id)
        XCTAssertEqual(lease.protectedThroughCardID, cards[3].id)

        let replacement = StorageFixture.card()
        XCTAssertEqual(try store.succeedTail(lease: lease, segmentID: FeedSegmentID(),
            cards: [replacement], createdAt: Date(timeIntervalSince1970: 500)), .applied)

        let segments = try store.segments(editionID: editionID)
        XCTAssertEqual(segments.flatMap(\.cardIDs), cards.prefix(4).map(\.id) + [replacement.id],
            "Maintenance may replace only the suffix beyond the last admitted card")
        XCTAssertEqual(try store.card(id: cards[4].id), cards[4], "Retired suffix remains archived")
        XCTAssertEqual(try store.card(id: cards[5].id), cards[5], "Retired suffix remains archived")
    }

    func testK14HiddenTailDefaultPreservesSeenOnlyBehavior() throws {
        let (store, editionID, cards) = try editionWithUnseenAdmittedCards()
        let lease = try XCTUnwrap(store.hiddenTail(editionID: editionID))
        XCTAssertEqual(lease.highWaterCardID, cards[0].id)
        XCTAssertEqual(lease.protectedThroughCardID, cards[0].id)

        let replacement = StorageFixture.card()
        XCTAssertEqual(try store.succeedTail(lease: lease, segmentID: FeedSegmentID(),
            cards: [replacement], createdAt: Date(timeIntervalSince1970: 500)), .applied)
        XCTAssertEqual(try store.segments(editionID: editionID).flatMap(\.cardIDs),
            [cards[0].id, replacement.id])
    }
}
