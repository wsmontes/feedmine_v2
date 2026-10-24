import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence

/// Owner directive 2026-10-17 §2: availability is persisted per saved occurrence, replaced in place, and goes
/// away with the link. A second store instance reads the same fact — it is not process memory.
final class SavedMediaAvailabilityStoreTests: XCTestCase {
    private func saved(_ database: RuntimeDatabase, _ cards: [PublicationStore.CardRecord],
        in listID: String = ReaderBookmarkList.defaultID) throws -> PublicationStore {
        let store = PublicationStore(database: database)
        let edition = StorageFixture.edition()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, cards), cards: cards)
        for card in cards {
            try store.toggleBookmark(cardID: card.id, in: listID, at: Date(timeIntervalSince1970: 10))
        }
        return store
    }

    func testAvailabilityIsPersistedReplacedInPlaceAndCountsAttempts() throws {
        let database = try StorageFixture.database(self)
        let cards = [StorageFixture.card(), StorageFixture.card()]
        _ = try saved(database, cards)
        let store = SavedMediaAvailabilityStore(database: database)
        XCTAssertNil(try store.availability(cardID: cards[0].id))

        try store.record(cardID: cards[0].id, availability: .pending, at: Date(timeIntervalSince1970: 20))
        try store.record(cardID: cards[1].id, availability: .textOnly, at: Date(timeIntervalSince1970: 21))
        var record = try XCTUnwrap(store.availability(cardID: cards[0].id))
        XCTAssertEqual(record.availability, .pending)
        XCTAssertEqual(record.attempts, 0)

        try store.record(cardID: cards[0].id, availability: .insufficientSpace,
            at: Date(timeIntervalSince1970: 22), attempted: true)
        record = try XCTUnwrap(SavedMediaAvailabilityStore(database: database).availability(cardID: cards[0].id))
        XCTAssertEqual(record.availability, .insufficientSpace, "one row per card, replaced in place")
        XCTAssertEqual(record.attempts, 1)
        XCTAssertEqual(record.updatedAt, Date(timeIntervalSince1970: 22))
        XCTAssertEqual(try store.availability(cardID: cards[1].id)?.availability, .textOnly)

        try store.record(cardID: cards[0].id, availability: .ready, at: Date(timeIntervalSince1970: 23),
            attempted: true)
        XCTAssertEqual(try store.availability(cardID: cards[0].id)?.attempts, 2)
        XCTAssertEqual(try store.availabilities().count, 2)
    }

    func testClearingUnsavedLeavesCardsStillInAnotherBox() throws {
        let database = try StorageFixture.database(self)
        let publication = PublicationStore(database: database)
        let cards = [StorageFixture.card(), StorageFixture.card()]
        _ = try saved(database, cards)
        let second = try ReaderLibraryStore(database: database).createBookmarkList(named: "Longreads").id
        try publication.toggleBookmark(cardID: cards[0].id, in: second, at: Date(timeIntervalSince1970: 11))

        let store = SavedMediaAvailabilityStore(database: database)
        for card in cards {
            try store.record(cardID: card.id, availability: .pending, at: Date(timeIntervalSince1970: 20))
        }
        // Removed from the default box only: still saved, so the availability stays.
        try publication.toggleBookmark(cardID: cards[0].id, at: Date(timeIntervalSince1970: 30))
        XCTAssertEqual(try store.clearUnsaved(), 0)
        XCTAssertNotNil(try store.availability(cardID: cards[0].id))
        // Removed from its last box: no link, no claim. The card that was never unsaved is untouched.
        try publication.toggleBookmark(cardID: cards[0].id, in: second, at: Date(timeIntervalSince1970: 31))
        try publication.toggleBookmark(cardID: cards[1].id, at: Date(timeIntervalSince1970: 32))
        XCTAssertEqual(try store.clearUnsaved(), 2)
        XCTAssertTrue(try store.availabilities().isEmpty)
        XCTAssertEqual(try store.savedCardIDs(limit: 10), [])
    }

    func testRecordedCardsAreBoundedAndOrderedByLeastRecentUpdate() throws {
        let database = try StorageFixture.database(self)
        let cards = (0..<3).map { _ in StorageFixture.card() }
        _ = try saved(database, cards)
        let store = SavedMediaAvailabilityStore(database: database)
        // A membership with no recorded row is still a saved card: the resume pass is what gives it a state.
        XCTAssertEqual(Set(try store.savedCardIDs(limit: 10)), Set(cards.map(\.id)))
        for (index, card) in cards.enumerated() {
            try store.record(cardID: card.id, availability: .pending,
                at: Date(timeIntervalSince1970: Double(100 - index)))
        }
        XCTAssertEqual(try store.savedCardIDs(limit: 2), [cards[2].id, cards[1].id])
        XCTAssertEqual(try store.savedCardIDs(limit: 0), [])
    }
}
