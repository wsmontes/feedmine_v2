//
// File: PublicationWindowCrossedSegmentTests.swift
// Module: FeedMinePersistenceTests
//
// Responsibility:
//   Verify that a window read validates the Segments it crosses — non-empty, card ordinals 0…n-1, schema
//   equal to the Edition — without materialising the cards of Segments it does not return.
//
// Owns:
//   The three crossed-interval guards of `PublicationStore.cards(editionID:around:backwardCapacity:forwardCapacity:)`.
//
// Does not own:
//   Production schema, timing assertions, the window's own contents or the touched-Segment validation.
//
// Allowed dependencies:
//   FeedMinePersistence, Foundation, XCTest.
//
// Architectural invariants:
//   INV-12; a window read's work is bounded by the requested neighbourhood plus the crossed interval's
//   metadata, never by the number of cards an unrelated Segment retains.
//

import Foundation
import XCTest
@testable import FeedMinePersistence

final class PublicationWindowCrossedSegmentTests: XCTestCase {
    /// Three Segments of three cards each, so a read from the middle Segment crosses the third.
    private func fixture() throws -> (RuntimeDatabase, PublicationStore, PublicationStore.EditionRecord, [PublicationStore.CardRecord]) {
        let database = try StorageFixture.database(self), store = PublicationStore(database: database)
        let edition = StorageFixture.edition()
        let cards = (0..<9).map { _ in StorageFixture.card() }
        let first = Array(cards[0..<3])
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, first), cards: first)
        for ordinal in 1..<3 {
            let slice = Array(cards[(ordinal * 3)..<(ordinal * 3 + 3)])
            try store.appendSegment(StorageFixture.segment(edition, slice, ordinal: UInt64(ordinal)), cards: slice)
        }
        return (database, store, edition, cards)
    }

    /// The anchor sits in Segment 1 with five cards asked forward, so exhaustion reaches the Edition's
    /// last Segment and it becomes part of the crossed interval.
    private func read(_ store: PublicationStore, _ edition: PublicationStore.EditionRecord,
        _ anchor: PublicationStore.CardRecord) throws -> [PublicationStore.CardRecord] {
        try store.cards(editionID: edition.id, around: anchor.id, backwardCapacity: 0, forwardCapacity: 5)
    }

    func testWindowReturnsTheRequestedNeighbourhood() throws {
        let (_, store, edition, cards) = try fixture()
        let window = try store.cards(editionID: edition.id, around: cards[4].id, backwardCapacity: 1, forwardCapacity: 1)
        XCTAssertEqual(window.map(\.id), [cards[3].id, cards[4].id, cards[5].id])
    }

    func testCrossedEmptySegmentIsStillRejected() throws {
        let (database, store, edition, cards) = try fixture()
        try database.write { db in
            try db.execute(sql: """
                DELETE FROM published_cards WHERE segment_id =
                    (SELECT id FROM feed_segments WHERE ordinal = 2)
                """)
        }
        XCTAssertThrowsError(try read(store, edition, cards[4])) {
            XCTAssertEqual($0 as? PublicationStoreError, .corruption("empty segment"))
        }
    }

    func testCrossedSegmentWithNonContiguousCardOrdinalsIsStillRejected() throws {
        let (database, store, edition, cards) = try fixture()
        try database.write { db in
            try db.execute(sql: """
                UPDATE published_cards SET ordinal = 7 WHERE ordinal = 0 AND segment_id =
                    (SELECT id FROM feed_segments WHERE ordinal = 2)
                """)
        }
        XCTAssertThrowsError(try read(store, edition, cards[4])) {
            XCTAssertEqual($0 as? PublicationStoreError, .corruption("card ordinal"))
        }
    }

    /// A schema-mismatched Segment whose cards are inside the window is rejected by the touched-Segment
    /// validation (`segment membership/schema`), which runs before the crossed interval. The crossed
    /// loop's own schema guard is unreachable for a non-empty Segment: any Segment with cards that the
    /// window does not return is empty, and emptiness is rejected first.
    func testSegmentSchemaMismatchInsideTheWindowIsRejected() throws {
        let (database, store, edition, cards) = try fixture()
        try database.write { db in
            try db.execute(sql: "UPDATE feed_segments SET publication_schema_version = 99 WHERE ordinal = 2")
        }
        XCTAssertThrowsError(try read(store, edition, cards[4])) {
            XCTAssertEqual($0 as? PublicationStoreError, .corruption("segment membership/schema"))
        }
    }
}
