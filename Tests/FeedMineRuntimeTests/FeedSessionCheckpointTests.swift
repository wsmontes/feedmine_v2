import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication
@testable import FeedMineRuntime

final class FeedSessionCheckpointTests: XCTestCase {
    private let initialTime = Date(timeIntervalSince1970: 300.75)
    private let milestoneTime = Date(timeIntervalSince1970: 400.5)

    private func withLocation(_ body: (RuntimeDatabaseLocation) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(RuntimeDatabaseLocation(directory: directory))
    }

    private func persist(location: RuntimeDatabaseLocation) throws -> (FeedEdition, [PublishedCard]) {
        let edition = WarmPresentationFixture.edition()
        let cards = try (0..<10).map {
            try WarmPresentationFixture.card(layout: .textOnly, action: nil, title: "P\($0)")
        }
        let database = try RuntimeDatabase(location: location)
        let store = PublicationStore(database: database)
        for ordinal in 0..<2 {
            let segmentCards = Array(cards[(ordinal * 5)..<(ordinal * 5 + 5)])
            let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: edition.id,
                ordinal: UInt64(ordinal), segmentSeed: UInt64(ordinal),
                publicationSchemaVersion: edition.publicationSchemaVersion,
                createdAt: edition.createdAt, cardIDs: segmentCards.map(\.id)))
            let records = try PublicationPersistenceMapping.records(segment: segment, cards: segmentCards)
            if ordinal == 0 {
                try store.createEdition(PublicationPersistenceMapping.record(edition), firstSegment: records.0, cards: records.1)
            } else {
                try store.appendSegment(records.0, cards: records.1)
            }
        }
        let cursor = SessionCursor(editionID: edition.id,
            anchor: FeedWindowAnchor(cardID: cards[4].id, placement: .center))
        try SessionStore(database: database).saveCheckpoint(
            PublicationPersistenceMapping.checkpoint(cursor, updatedAt: initialTime))
        return (edition, cards)
    }

    func testNoStateReturnsFalseWithoutCreatingCheckpoint() async throws {
        try await withLocation { location in
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let saved = try await session.checkpointCurrentPosition(at: milestoneTime)
            XCTAssertFalse(saved)
            XCTAssertNil(try SessionStore(database: database).checkpoint())
            let current = await session.currentPresentation()
            XCTAssertNil(current)
        }
    }

    func testRestoreThenMilestonePersistsSamePositionWithSuppliedTime() async throws {
        try await withLocation { location in
            let (edition, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let restored = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            let saved = try await session.checkpointCurrentPosition(at: milestoneTime)
            XCTAssertTrue(saved)
            let checkpoint = try XCTUnwrap(SessionStore(database: database).checkpoint())
            XCTAssertEqual(checkpoint.editionID, edition.id)
            XCTAssertEqual(checkpoint.cardID, cards[4].id)
            XCTAssertEqual(checkpoint.anchorPlacement, "center")
            XCTAssertEqual(checkpoint.updatedAt, milestoneTime)
            let current = await session.currentPresentation()
            XCTAssertEqual(current, restored)
        }
    }

    // Session, history and database references all leave scope before the caller reopens.
    private func shiftCheckpointAndClose(location: RuntimeDatabaseLocation, edition: FeedEdition,
        cards: [PublishedCard], index: Int, placement: PresentationAnchorPlacement) async throws {
        let database = try RuntimeDatabase(location: location)
        let history = PublicationHistory(database: database)
        let session = FeedSession(publicationHistory: history)
        let restored = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
        XCTAssertEqual(restored?.window.items.map(\.id), Array(cards[2...6]).map(\.id))
        let before = try XCTUnwrap(SessionStore(database: database).checkpoint())
        let shifted = try await session.submitViewport(ViewportObservation(
            anchor: PresentationAnchor(cardID: cards[index].id, placement: placement)))
        XCTAssertEqual(shifted?.window.anchor, PresentationAnchor(cardID: cards[index].id, placement: placement))
        XCTAssertEqual(try SessionStore(database: database).checkpoint(), before)
        XCTAssertEqual(before.cardID, cards[4].id)
        XCTAssertEqual(before.anchorPlacement, "center")
        let saved = try await session.checkpointCurrentPosition(at: milestoneTime)
        XCTAssertTrue(saved)
        let checkpoint = try XCTUnwrap(SessionStore(database: database).checkpoint())
        XCTAssertEqual(checkpoint.editionID, edition.id)
        XCTAssertEqual(checkpoint.cardID, cards[index].id)
        XCTAssertEqual(checkpoint.anchorPlacement, placement.rawValue)
        XCTAssertEqual(checkpoint.updatedAt, milestoneTime)
        let current = await session.currentPresentation()
        XCTAssertEqual(current, shifted)
    }

    func testShiftToP6ThenMilestoneSurvivesCloseAndReopen() async throws {
        try await withLocation { location in
            let (edition, cards) = try persist(location: location)
            try await shiftCheckpointAndClose(location: location, edition: edition, cards: cards, index: 6, placement: .center)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let restored = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            XCTAssertEqual(restored?.window.anchor, PresentationAnchor(cardID: cards[6].id, placement: .center))
            XCTAssertEqual(restored?.window.items.map(\.id), Array(cards[4...8]).map(\.id))
            XCTAssertEqual(restored?.contextKey, edition.contextKey)
            XCTAssertEqual(restored?.editionID, edition.id)
        }
    }

    func testP5TopMilestoneSurvivesCloseAndReopen() async throws {
        try await withLocation { location in
            let (edition, cards) = try persist(location: location)
            try await shiftCheckpointAndClose(location: location, edition: edition, cards: cards, index: 5, placement: .top)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let restored = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            XCTAssertEqual(restored?.window.anchor, PresentationAnchor(cardID: cards[5].id, placement: .top))
        }
    }

    func testStorageFailurePreservesMemoryP6AndDurableP4() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            let shifted = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            let before = try XCTUnwrap(SessionStore(database: database).checkpoint())
            try database.write { db in
                try db.execute(sql: """
                    CREATE TRIGGER reject_checkpoint BEFORE UPDATE ON session_checkpoint
                    BEGIN SELECT RAISE(ABORT, 'test checkpoint failure'); END
                    """)
            }
            do {
                _ = try await session.checkpointCurrentPosition(at: milestoneTime)
                XCTFail("Expected checkpoint failure")
            } catch {
                XCTAssertTrue(String(describing: error).contains("test checkpoint failure"))
            }
            let current = await session.currentPresentation()
            XCTAssertEqual(current, shifted)
            XCTAssertEqual(current?.window.anchor.cardID, cards[6].id)
            XCTAssertEqual(try SessionStore(database: database).checkpoint(), before)
            XCTAssertEqual(before.cardID, cards[4].id)
            try database.write { db in
                try db.execute(sql: "DROP TRIGGER reject_checkpoint")
            }
        }
    }

    func testInvalidDatePropagatesPersistenceErrorWithoutChangingStateOrCursor() async throws {
        try await withLocation { location in
            let (_, cards) = try persist(location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            _ = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            let shifted = try await session.submitViewport(ViewportObservation(
                anchor: PresentationAnchor(cardID: cards[6].id, placement: .center)))
            let before = try SessionStore(database: database).checkpoint()
            do {
                _ = try await session.checkpointCurrentPosition(at: Date(timeIntervalSince1970: .infinity))
                XCTFail("Expected invalid date")
            } catch {
                XCTAssertEqual(error as? SessionStoreError, .invalidRepresentation("updated_at"))
            }
            let current = await session.currentPresentation()
            XCTAssertEqual(current, shifted)
            XCTAssertEqual(try SessionStore(database: database).checkpoint(), before)
        }
    }
}
