import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
@testable import FeedMinePublication
@testable import FeedMineRuntime

final class FeedSessionWarmRestoreTests: XCTestCase {
    private func withLocation(_ body: (RuntimeDatabaseLocation) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(RuntimeDatabaseLocation(directory: directory))
    }

    // The database and both stores leave scope before the caller reopens runtime.sqlite.
    private func persist(edition: FeedEdition, cards: [PublishedCard], location: RuntimeDatabaseLocation) throws {
        let database = try RuntimeDatabase(location: location)
        let store = PublicationStore(database: database)
        for ordinal in 0..<2 {
            let segmentCards = Array(cards[(ordinal * 3)..<(ordinal * 3 + 3)])
            let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: edition.id,
                ordinal: UInt64(ordinal), segmentSeed: UInt64.max,
                publicationSchemaVersion: edition.publicationSchemaVersion,
                createdAt: Date(timeIntervalSince1970: 250.5), cardIDs: segmentCards.map(\.id)))
            let records = try PublicationPersistenceMapping.records(segment: segment, cards: segmentCards)
            if ordinal == 0 {
                try store.createEdition(PublicationPersistenceMapping.record(edition), firstSegment: records.0, cards: records.1)
            } else { try store.appendSegment(records.0, cards: records.1) }
        }
        let cursor = SessionCursor(editionID: edition.id, anchor: FeedWindowAnchor(cardID: cards[4].id, placement: .center))
        try SessionStore(database: database).saveCheckpoint(PublicationPersistenceMapping.checkpoint(
            cursor, updatedAt: Date(timeIntervalSince1970: 300.75)))
    }

    func testNoCheckpointReturnsNil() throws {
        try withLocation { location in
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            XCTAssertNil(try session.restoreLocalPresentation(backwardCapacity: 4, forwardCapacity: 1))
        }
    }

    func testFullWarmRestoreAfterClosingAndReopeningPreservesPresentationAndCheckpoint() throws {
        try withLocation { location in
            let edition = WarmPresentationFixture.edition()
            let cards = try (0..<6).map { _ in try WarmPresentationFixture.card() }
            try persist(edition: edition, cards: cards, location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let savedCheckpoint = try XCTUnwrap(SessionStore(database: database).checkpoint())
            let snapshot = try XCTUnwrap(session.restoreLocalPresentation(backwardCapacity: 4, forwardCapacity: 1))
            XCTAssertEqual(snapshot.contextKey, edition.contextKey)
            XCTAssertEqual(snapshot.editionID, edition.id)
            XCTAssertEqual(snapshot.window.anchor.cardID, cards[4].id)
            XCTAssertEqual(snapshot.window.anchor.placement, .center)
            XCTAssertEqual(snapshot.window.items.map(\.id), cards.map(\.id))
            let item = snapshot.window.items[4]
            XCTAssertEqual(item.title, "  Frozen title É\n")
            XCTAssertEqual(item.primaryText, " Original text\n ")
            XCTAssertEqual(item.timestamp?.value, Date(timeIntervalSince1970: 200.25))
            XCTAssertEqual(item.timestamp?.kind, .observed)
            XCTAssertEqual(item.sourceDisplayName, " Frozen source ")
            XCTAssertEqual(item.providerDisplayName, "Provider É")
            XCTAssertEqual(item.layout, .hero)
            XCTAssertEqual(item.mediaAspectRatio, 1.5)
            XCTAssertEqual(item.primaryActionKind, .externalURL)
            XCTAssertEqual(try SessionStore(database: database).checkpoint(), savedCheckpoint)
        }
    }

    func testZeroCapacitiesRestoreOnlyAnchorWithoutCheckpointWrite() throws {
        try withLocation { location in
            let edition = WarmPresentationFixture.edition()
            let cards = try (0..<6).map { _ in try WarmPresentationFixture.card() }
            try persist(edition: edition, cards: cards, location: location)
            let database = try RuntimeDatabase(location: location)
            let store = SessionStore(database: database)
            let before = try XCTUnwrap(store.checkpoint())
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let snapshot = try XCTUnwrap(session.restoreLocalPresentation(backwardCapacity: 0, forwardCapacity: 0))
            XCTAssertEqual(snapshot.window.items.map(\.id), [cards[4].id])
            XCTAssertEqual(snapshot.window.anchor.cardID, cards[4].id)
            XCTAssertEqual(snapshot.window.anchor.placement, .center)
            XCTAssertEqual(try store.checkpoint(), before)
        }
    }

    func testCapacityFailurePropagatesWithoutReplacingCheckpoint() throws {
        try withLocation { location in
            let edition = WarmPresentationFixture.edition()
            let cards = try (0..<6).map { _ in try WarmPresentationFixture.card() }
            try persist(edition: edition, cards: cards, location: location)
            let database = try RuntimeDatabase(location: location)
            let store = SessionStore(database: database)
            let before = try XCTUnwrap(store.checkpoint())
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            for capacities in [(-1, 0), (0, -1)] {
                XCTAssertThrowsError(try session.restoreLocalPresentation(
                    backwardCapacity: capacities.0, forwardCapacity: capacities.1)) { error in
                    XCTAssertEqual(error as? PublicationStoreError, .invalidCapacity)
                }
            }
            XCTAssertEqual(try store.checkpoint(), before)
        }
    }
}
