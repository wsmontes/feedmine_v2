import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
@testable import FeedMinePublication

final class PublicationHistoryTests: XCTestCase {
    private func withDatabase(_ body: (RuntimeDatabaseLocation, RuntimeDatabase) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = RuntimeDatabaseLocation(directory: directory)
        try body(location, RuntimeDatabase(location: location))
    }

    private func persist(_ edition: FeedEdition, cards: [PublishedCard], database: RuntimeDatabase) throws {
        let store = PublicationStore(database: database)
        let first = try PublicationPersistenceMapping.records(
            segment: RestoreFixture.segment(edition, cards: Array(cards[0..<3]), ordinal: 0), cards: Array(cards[0..<3]))
        try store.createEdition(PublicationPersistenceMapping.record(edition), firstSegment: first.0, cards: first.1)
        let next = try PublicationPersistenceMapping.records(
            segment: RestoreFixture.segment(edition, cards: Array(cards[3..<6]), ordinal: 1), cards: Array(cards[3..<6]))
        try store.appendSegment(next.0, cards: next.1)
    }

    func testNoCheckpointReturnsNil() throws {
        try withDatabase { _, database in
            XCTAssertNil(try PublicationHistory(database: database).restore(backwardCapacity: 1, forwardCapacity: 2))
        }
    }

    func testExactSemanticRestoreFromReopenedDatabase() throws {
        try withDatabase { location, database in
            let edition = RestoreFixture.edition()
            let cards = try (0..<6).map { try RestoreFixture.card(index: $0) }
            try persist(edition, cards: cards, database: database)
            let cursor = SessionCursor(editionID: edition.id, anchor: FeedWindowAnchor(cardID: cards[4].id, placement: .center))
            try SessionStore(database: database).saveCheckpoint(PublicationPersistenceMapping.checkpoint(cursor, updatedAt: edition.createdAt))
            let history = PublicationHistory(database: try RuntimeDatabase(location: location))
            let restored = try XCTUnwrap(history.restore(backwardCapacity: 2, forwardCapacity: 1))
            XCTAssertEqual(restored.edition, edition)
            XCTAssertEqual(restored.edition.editorialRevision, edition.editorialRevision)
            XCTAssertEqual(restored.cursor, cursor)
            XCTAssertEqual(restored.window.editionID, edition.id)
            XCTAssertEqual(restored.window.anchor, cursor.anchor)
            XCTAssertEqual(restored.window.cards, Array(cards[2...5]))
            let anchorOnly = try XCTUnwrap(history.restore(backwardCapacity: 0, forwardCapacity: 0))
            XCTAssertEqual(anchorOnly.window.cards, [cards[4]])
            XCTAssertEqual(anchorOnly.window.anchor, cursor.anchor)
        }
    }

    func testDifferentWindowPreservesCheckpointAndClipsToRetainedHistory() throws {
        try withDatabase { _, database in
            let edition = RestoreFixture.edition()
            let cards = try (0..<6).map { try RestoreFixture.card(index: $0) }
            try persist(edition, cards: cards, database: database)
            let cursor = SessionCursor(editionID: edition.id, anchor: FeedWindowAnchor(cardID: cards[4].id, placement: .center))
            try SessionStore(database: database).saveCheckpoint(PublicationPersistenceMapping.checkpoint(cursor, updatedAt: edition.createdAt))
            let history = PublicationHistory(database: database)
            let anchor = FeedWindowAnchor(cardID: cards[1].id, placement: .top)
            let window = try history.window(editionID: edition.id, around: anchor, backwardCapacity: 1, forwardCapacity: 2)
            XCTAssertEqual(window.editionID, edition.id)
            XCTAssertEqual(window.cards, Array(cards[0...3]))
            XCTAssertEqual(window.anchor, anchor)
            let all = try history.window(editionID: edition.id, around: anchor, backwardCapacity: 10, forwardCapacity: 10)
            XCTAssertEqual(all.cards, cards)
            XCTAssertEqual(all.anchor, anchor)
            XCTAssertEqual(try XCTUnwrap(history.restore(backwardCapacity: 0, forwardCapacity: 0)).cursor, cursor)
        }
    }

    func testWindowWithoutCheckpointAndStoreErrorsPropagate() throws {
        try withDatabase { _, database in
            let edition = RestoreFixture.edition()
            let cards = try (0..<6).map { try RestoreFixture.card(index: $0) }
            try persist(edition, cards: cards, database: database)
            let history = PublicationHistory(database: database)
            let anchor = FeedWindowAnchor(cardID: cards[4].id, placement: .top)
            XCTAssertEqual(try history.window(editionID: edition.id, around: anchor,
                backwardCapacity: 0, forwardCapacity: 0).cards, [cards[4]])
            XCTAssertNil(try history.restore(backwardCapacity: 0, forwardCapacity: 0))
            for capacities in [(-1, 0), (0, -1)] {
                XCTAssertThrowsError(try history.window(editionID: edition.id, around: anchor,
                    backwardCapacity: capacities.0, forwardCapacity: capacities.1)) { error in
                    XCTAssertEqual(error as? PublicationStoreError, .invalidCapacity)
                }
            }
            XCTAssertThrowsError(try history.window(editionID: FeedEditionID(), around: anchor,
                backwardCapacity: 0, forwardCapacity: 0)) { error in
                XCTAssertEqual(error as? PublicationStoreError, .missingEdition)
            }
            XCTAssertThrowsError(try history.window(editionID: edition.id,
                around: FeedWindowAnchor(cardID: PublicationCardID(), placement: .center),
                backwardCapacity: 0, forwardCapacity: 0)) { error in
                guard case .corruption = error as? PublicationStoreError else {
                    return XCTFail("Expected unchanged store membership error, got \(error)")
                }
            }
        }
    }

    func testRestoredPublicationRejectsContradictorySemanticValues() throws {
        let edition = RestoreFixture.edition()
        let cards = try (0..<2).map { try RestoreFixture.card(index: $0) }
        let anchor = FeedWindowAnchor(cardID: cards[0].id, placement: .center)
        let cursor = SessionCursor(editionID: edition.id, anchor: anchor)
        let window = try XCTUnwrap(FeedWindow(editionID: edition.id, cards: cards, anchor: anchor))
        XCTAssertNotNil(RestoredPublication(edition: edition, cursor: cursor, window: window))
        XCTAssertNil(RestoredPublication(edition: edition,
            cursor: SessionCursor(editionID: FeedEditionID(), anchor: anchor), window: window))
        XCTAssertNil(RestoredPublication(edition: edition, cursor: cursor,
            window: try XCTUnwrap(FeedWindow(editionID: FeedEditionID(), cards: cards, anchor: anchor))))
        for otherAnchor in [FeedWindowAnchor(cardID: cards[1].id, placement: .center),
            FeedWindowAnchor(cardID: cards[0].id, placement: .top)] {
            XCTAssertNil(RestoredPublication(edition: edition,
                cursor: SessionCursor(editionID: edition.id, anchor: otherAnchor), window: window))
        }
    }
}
