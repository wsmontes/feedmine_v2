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

    func testSaveCursorRestoresExactTopPosition() throws {
        try withDatabase { _, database in
            let edition = RestoreFixture.edition()
            let cards = try (0..<6).map { try RestoreFixture.card(index: $0) }
            try persist(edition, cards: cards, database: database)
            let history = PublicationHistory(database: database)
            let cursor = SessionCursor(editionID: edition.id,
                anchor: FeedWindowAnchor(cardID: cards[4].id, placement: .top))
            try history.saveCursor(cursor, updatedAt: Date(timeIntervalSince1970: 700.5))
            let restored = try XCTUnwrap(history.restore(backwardCapacity: 1, forwardCapacity: 1))
            XCTAssertEqual(restored.cursor, cursor)
        }
    }

    /// Continuity extension: an exact card carries the relative point through storage and back. The same
    /// record rewritten without it (legacy shape) still restores the same card.
    func testTheRelativePointRoundTripsOnTheExactCard() throws {
        try withDatabase { location, database in
            let edition = RestoreFixture.edition()
            let cards = try (0..<6).map { try RestoreFixture.card(index: $0) }
            try persist(edition, cards: cards, database: database)
            let progress = try XCTUnwrap(CardTopOffset(topDelta: -159, height: 600))
            let cursor = SessionCursor(editionID: edition.id,
                anchor: FeedWindowAnchor(cardID: cards[4].id, placement: .top), progress: progress)
            try PublicationHistory(database: database).saveCursor(cursor, updatedAt: Date(timeIntervalSince1970: 700.5))
            let restored = try XCTUnwrap(PublicationHistory(database: try RuntimeDatabase(location: location))
                .restore(backwardCapacity: 1, forwardCapacity: 1))
            XCTAssertEqual(restored.cursor.anchor, cursor.anchor)
            XCTAssertEqual(restored.cursor.progress, progress)
            XCTAssertEqual(restored.position, .exact(cards[4].id))
            // Legacy shape: a record with no extension keeps meaning exactly the card.
            try SessionStore(database: database).saveCheckpoint(PublicationPersistenceMapping.checkpoint(
                SessionCursor(editionID: edition.id, anchor: cursor.anchor), updatedAt: Date(timeIntervalSince1970: 701)))
            XCTAssertNil(try PublicationHistory(database: database)
                .restore(backwardCapacity: 1, forwardCapacity: 1)?.cursor.progress)
        }
    }

    /// Validation is in Swift, not a SQLite CHECK: a row that carries only one value, a non-positive height or
    /// a delta below the card is not a relative point. The card record still stands, exactly as before.
    func testAnInvalidRelativePointReadsAsAbsent() throws {
        try withDatabase { _, database in
            let edition = RestoreFixture.edition()
            let cards = try (0..<6).map { try RestoreFixture.card(index: $0) }
            try persist(edition, cards: cards, database: database)
            let sessions = SessionStore(database: database)
            let base = SessionStore.CheckpointRecord(editionID: edition.id, cardID: cards[4].id,
                anchorPlacement: "top", updatedAt: Date(timeIntervalSince1970: 700.5))
            let cases: [(Double?, Double?)] = [(-100, nil), (nil, 600), (-100, 0), (-601.5, 600)]
            for (topDelta, height) in cases {
                try sessions.saveCheckpoint(.init(editionID: base.editionID, cardID: base.cardID,
                    anchorPlacement: base.anchorPlacement, updatedAt: base.updatedAt,
                    topDelta: topDelta, cardHeight: height))
                let cursor = try XCTUnwrap(PublicationHistory(database: database).savedCursor())
                XCTAssertNil(cursor.progress, "topDelta=\(String(describing: topDelta)) height=\(String(describing: height))")
                XCTAssertEqual(cursor.anchor.cardID, cards[4].id)
            }
        }
    }

    func testRestoredPublicationRejectsContradictorySemanticValues() throws {
        let edition = RestoreFixture.edition()
        let cards = try (0..<2).map { try RestoreFixture.card(index: $0) }
        let anchor = FeedWindowAnchor(cardID: cards[0].id, placement: .center)
        let cursor = SessionCursor(editionID: edition.id, anchor: anchor)
        let window = try XCTUnwrap(FeedWindow(editionID: edition.id, cards: cards, anchor: anchor))
        let exact = RestoredPosition.exact(cards[0].id)
        XCTAssertNotNil(RestoredPublication(edition: edition, cursor: cursor, window: window, position: exact))
        XCTAssertNil(RestoredPublication(edition: edition,
            cursor: SessionCursor(editionID: FeedEditionID(), anchor: anchor), window: window, position: exact))
        XCTAssertNil(RestoredPublication(edition: edition, cursor: cursor,
            window: try XCTUnwrap(FeedWindow(editionID: FeedEditionID(), cards: cards, anchor: anchor)),
            position: exact))
        for otherAnchor in [FeedWindowAnchor(cardID: cards[1].id, placement: .center),
            FeedWindowAnchor(cardID: cards[0].id, placement: .top)] {
            XCTAssertNil(RestoredPublication(edition: edition,
                cursor: SessionCursor(editionID: edition.id, anchor: otherAnchor), window: window, position: exact))
        }
        // A statement that lands on a different card than the cursor contradicts itself.
        XCTAssertNil(RestoredPublication(edition: edition, cursor: cursor, window: window,
            position: .nearestNeighbour(withdrawn: cards[1].id, landedOn: cards[1].id)))
    }
}
