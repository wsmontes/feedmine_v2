import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication
@testable import FeedMineRuntime

final class FeedSessionViewportTests: XCTestCase {
    private let initialTime = Date(timeIntervalSince1970: 300.75)

    private func withLocation(_ body: (RuntimeDatabaseLocation) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(RuntimeDatabaseLocation(directory: directory))
    }

    private func persist(_ edition: FeedEdition, cards: [PublishedCard], location: RuntimeDatabaseLocation) throws {
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
    }

    private func cards() throws -> [PublishedCard] {
        try (0..<10).map { try WarmPresentationFixture.card(layout: .textOnly, action: nil, title: "P\($0)") }
    }

    private func observation(_ card: PublishedCard, placement: PresentationAnchorPlacement = .center) -> ViewportObservation {
        ViewportObservation(anchor: PresentationAnchor(cardID: card.id, placement: placement))
    }

    // All references to the first database/history/session leave scope before reopen.
    private func shiftAndClose(location: RuntimeDatabaseLocation, edition: FeedEdition, cards: [PublishedCard],
        index: Int, placement: PresentationAnchorPlacement) async throws {
        let database = try RuntimeDatabase(location: location)
        let history = PublicationHistory(database: database)
        let session = FeedSession(publicationHistory: history)
        let restored = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
        let initial = try XCTUnwrap(restored)
        XCTAssertEqual(initial.window.items.map(\.id), Array(cards[2...6]).map(\.id))
        let installed = await session.currentPresentation()
        XCTAssertEqual(installed, initial)
        let result = try await session.submitViewport(observation(cards[index], placement: placement))
        let shifted = try XCTUnwrap(result)
        XCTAssertEqual(shifted.contextKey, edition.contextKey)
        XCTAssertEqual(shifted.editionID, edition.id)
        XCTAssertEqual(shifted.window.items.map(\.id), Array(cards[(index - 2)...(index + 2)]).map(\.id))
        XCTAssertEqual(shifted.window.anchor, PresentationAnchor(cardID: cards[index].id, placement: placement))
        let current = await session.currentPresentation()
        XCTAssertEqual(current, shifted)
        let checkpoint = try XCTUnwrap(SessionStore(database: database).checkpoint())
        XCTAssertEqual(checkpoint.cardID, cards[4].id)
        XCTAssertEqual(checkpoint.anchorPlacement, "center")
        XCTAssertEqual(checkpoint.updatedAt, initialTime)
        let retained = try history.window(editionID: edition.id,
            around: FeedWindowAnchor(cardID: cards[index].id, placement: .center),
            backwardCapacity: 10, forwardCapacity: 10)
        XCTAssertEqual(retained.cards, cards)
    }

    func testShiftToP6IsMemoryLocalAndReopenRestoresP4() async throws {
        try await withLocation { location in
            let edition = WarmPresentationFixture.edition()
            let cards = try cards()
            try persist(edition, cards: cards, location: location)
            try await shiftAndClose(location: location, edition: edition, cards: cards, index: 6, placement: .center)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let result = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            let snapshot = try XCTUnwrap(result)
            XCTAssertEqual(snapshot.window.anchor, PresentationAnchor(cardID: cards[4].id, placement: .center))
            XCTAssertEqual(snapshot.window.items.map(\.id), Array(cards[2...6]).map(\.id))
            XCTAssertEqual(snapshot.contextKey, edition.contextKey)
            XCTAssertEqual(snapshot.editionID, edition.id)
        }
    }

    func testP5TopIsMemoryLocalAndReopenRestoresP4Center() async throws {
        try await withLocation { location in
            let edition = WarmPresentationFixture.edition()
            let cards = try cards()
            try persist(edition, cards: cards, location: location)
            try await shiftAndClose(location: location, edition: edition, cards: cards, index: 5, placement: .top)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let result = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            XCTAssertEqual(result?.window.anchor, PresentationAnchor(cardID: cards[4].id, placement: .center))
        }
    }

    func testStaleAndSameAnchorObservationsPreserveStateAndCheckpoint() async throws {
        try await withLocation { location in
            let edition = WarmPresentationFixture.edition()
            let cards = try cards()
            try persist(edition, cards: cards, location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let initial = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            let before = try XCTUnwrap(SessionStore(database: database).checkpoint())
            for index in [9, 4] {
                let returned = try await session.submitViewport(observation(cards[index]))
                let current = await session.currentPresentation()
                XCTAssertEqual(returned, initial)
                XCTAssertEqual(current, initial)
                XCTAssertEqual(try SessionStore(database: database).checkpoint(), before)
            }
        }
    }

    func testPlacementOnlyChangeAndSequentialShiftAreAccepted() async throws {
        try await withLocation { location in
            let edition = WarmPresentationFixture.edition()
            let cards = try cards()
            try persist(edition, cards: cards, location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let initial = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            let top = try await session.submitViewport(observation(cards[4], placement: .top))
            XCTAssertEqual(top?.window.items, initial?.window.items)
            XCTAssertEqual(top?.window.anchor, PresentationAnchor(cardID: cards[4].id, placement: .top))
            let currentTop = await session.currentPresentation()
            XCTAssertEqual(currentTop, top)
            let checkpoint = try XCTUnwrap(SessionStore(database: database).checkpoint())
            XCTAssertEqual(checkpoint.cardID, cards[4].id)
            XCTAssertEqual(checkpoint.anchorPlacement, "center")
            XCTAssertEqual(checkpoint.updatedAt, initialTime)
            let shifted = try await session.submitViewport(observation(cards[6]))
            XCTAssertEqual(shifted?.window.items.map(\.id), Array(cards[4...8]).map(\.id))
            let current = await session.currentPresentation()
            XCTAssertEqual(current, shifted)
        }
    }

    func testViewportWithoutStateIsInert() async throws {
        try await withLocation { location in
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let observation = ViewportObservation(
                anchor: PresentationAnchor(cardID: PublicationCardID(), placement: .top))
            let result = try await session.submitViewport(observation)
            let current = await session.currentPresentation()
            XCTAssertNil(result)
            XCTAssertNil(current)
            XCTAssertNil(try SessionStore(database: database).checkpoint())
        }
    }

    func testWindowFailurePreservesInstalledState() async throws {
        try await withLocation { location in
            let edition = WarmPresentationFixture.edition()
            let cards = try cards()
            try persist(edition, cards: cards, location: location)
            let database = try RuntimeDatabase(location: location)
            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let initial = try await session.restoreLocalPresentation(backwardCapacity: 2, forwardCapacity: 2)
            let before = try SessionStore(database: database).checkpoint()
            try database.write { db in
                try db.execute(sql: "ALTER TABLE published_cards RENAME TO unavailable_cards")
            }
            do {
                _ = try await session.submitViewport(observation(cards[6]))
                XCTFail("Expected window materialization failure")
            } catch {
                XCTAssertTrue(String(describing: error).contains("no such table: published_cards"))
            }
            let current = await session.currentPresentation()
            XCTAssertEqual(current, initial)
            try database.write { db in
                try db.execute(sql: "ALTER TABLE unavailable_cards RENAME TO published_cards")
            }
            XCTAssertEqual(try SessionStore(database: database).checkpoint(), before)
        }
    }
}
