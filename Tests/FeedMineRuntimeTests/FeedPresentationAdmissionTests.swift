import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication
@testable import FeedMineRuntime

/// T2 — the admission boundary: production extends the reserve, only an explicit forward scroll
/// extends the admitted reader list. (Plan `2026-10-09-transferencia-frontend-v1-v2.md`, T2.)
@MainActor
final class FeedPresentationAdmissionTests: XCTestCase {
    private struct Fixture {
        let database: RuntimeDatabase
        let edition: FeedEdition
        let cards: [PublishedCard]
        let session: FeedSession
        let bounds: FeedPresentationBounds

        /// Publishes `cards[4...5]` as a second segment: production after the initial admission.
        func publishTail() throws {
            let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: edition.id, ordinal: 1,
                segmentSeed: 2, publicationSchemaVersion: edition.publicationSchemaVersion,
                createdAt: edition.createdAt, cardIDs: Array(cards[4...5]).map(\.id)))
            let values = try PublicationPersistenceMapping.records(segment: segment, cards: Array(cards[4...5]))
            try PublicationStore(database: database).appendSegment(values.0, cards: values.1)
        }

        func readyAhead(_ cardID: PublicationCardID) throws -> Int {
            let facts = try PublicationHistory(database: database).readyAhead(editionID: edition.id,
                anchorCardID: cardID, probeBound: 64)
            switch facts.amount {
            case .exact(let count): return count
            case .atLeast(let bound): return bound
            }
        }
    }

    private func fixture(backwardCapacity: Int = 1, forwardCapacity: Int = 2) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let edition = WarmPresentationFixture.edition()
        let cards = try (0..<6).map { try WarmPresentationFixture.card(layout: .textOnly, action: nil, title: "P\($0)") }
        let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: edition.id, ordinal: 0,
            segmentSeed: 1, publicationSchemaVersion: edition.publicationSchemaVersion,
            createdAt: edition.createdAt, cardIDs: Array(cards[0...3]).map(\.id)))
        let values = try PublicationPersistenceMapping.records(segment: segment, cards: Array(cards[0...3]))
        try PublicationStore(database: database).createEdition(PublicationPersistenceMapping.record(edition),
            firstSegment: values.0, cards: values.1)
        try PublicationHistory(database: database).saveCursor(.init(editionID: edition.id,
            anchor: .init(cardID: cards[2].id, placement: .center)), updatedAt: Date(timeIntervalSince1970: 20))
        return .init(database: database, edition: edition, cards: cards,
            session: FeedSession(publicationHistory: .init(database: database)),
            bounds: .init(backwardCapacity: backwardCapacity, forwardCapacity: forwardCapacity))
    }

    private func observation(_ card: PublishedCard, placement: PresentationAnchorPlacement = .center) -> ViewportObservation {
        .init(anchor: .init(cardID: card.id, placement: placement))
    }

    private func admitted(_ session: FeedSession,
        _ admission: FeedPresentationAdmission) async throws -> FeedPresentationSnapshot {
        let value = try await session.admitPresentation(admission)
        return try XCTUnwrap(value)
    }

    private func recorded(_ session: FeedSession,
        _ observation: ViewportObservation) async throws -> FeedPresentationSnapshot {
        let value = try await session.submitViewport(observation)
        return try XCTUnwrap(value)
    }

    /// Committed publication while the reader is stationary: the reserve grows, the list does not.
    func testPreparationWhileStationaryDoesNotExtendPresentation() async throws {
        let f = try fixture()
        let before = try await admitted(f.session, .initial(f.bounds))
        XCTAssertEqual(before.window.items.map(\.id), Array(f.cards[1...3]).map(\.id))
        let reserved = try f.readyAhead(before.window.anchor.cardID)
        try f.publishTail()
        let after = await f.session.currentPresentation()
        XCTAssertEqual(after, before, "Stationary preparation must not change the admitted list")
        XCTAssertEqual(after?.window.anchor, before.window.anchor)
        XCTAssertEqual(after?.provenance, before.provenance)
        XCTAssertGreaterThan(try f.readyAhead(before.window.anchor.cardID), reserved, "The reserve must grow")
    }

    /// Retry and foreground are production opportunities. Neither may admit cards.
    func testRetryAndForegroundDoNotAdmitCards() async throws {
        let f = try fixture()
        let before = try await admitted(f.session, .initial(f.bounds))
        try f.publishTail()
        // A foreground read is a read; a recovery attempt on an installed presentation is refused.
        let foregroundRead = await f.session.currentPresentation()
        XCTAssertEqual(foregroundRead, before)
        let recovery = try await f.session.admitPresentation(.restore(f.bounds))
        XCTAssertEqual(recovery, before)
        let repeatInitial = try await f.session.admitPresentation(.initial(f.bounds))
        XCTAssertEqual(repeatInitial, before)
        let settled = await f.session.currentPresentation()
        XCTAssertEqual(settled, before)
        XCTAssertEqual(before.window.items.count, 3)
    }

    /// The first presentation of an association is installed exactly once.
    func testInitialAdmissionIsNotRepeated() async throws {
        let f = try fixture()
        let first = try await admitted(f.session, .initial(f.bounds))
        let again = try await f.session.admitPresentation(.initial(f.bounds))
        XCTAssertEqual(again, first)
        XCTAssertEqual(again?.provenance.position, first.provenance.position, "A repeat must not allocate a projection")
        try f.publishTail()
        let afterProduction = try await f.session.admitPresentation(.initial(f.bounds))
        XCTAssertEqual(afterProduction, first)
        // Recovery is still available for an association that lost its presentation, but never widens one.
        let recovered = FeedSession(publicationHistory: .init(database: f.database))
        let recoveredPresentation = try await recovered.admitPresentation(.restore(f.bounds))
        XCTAssertNotNil(recoveredPresentation)
    }

    /// A forward scroll at the boundary admits exactly the ready prefix, appending after the tail.
    func testForwardScrollAdmitsOnlyReadyPrefix() async throws {
        let f = try fixture()
        let before = try await admitted(f.session, .initial(f.bounds))
        try f.publishTail()
        let observed = observation(f.cards[3], placement: .top)
        // The driver records the reader's position first; only then does the gesture admit.
        _ = try await f.session.submitViewport(observed)
        let admitted = try await admitted(f.session, .forwardScroll(observed))
        XCTAssertEqual(admitted.window.items.count, before.window.items.count + 2)
        XCTAssertEqual(Array(admitted.window.items.prefix(before.window.items.count)), before.window.items,
            "Earlier cards keep identity, order and projection")
        XCTAssertEqual(admitted.window.items.map(\.id), Array(f.cards[1...5]).map(\.id))
        XCTAssertEqual(Set(admitted.window.items.map(\.id)).count, admitted.window.items.count)
        XCTAssertEqual(admitted.window.anchor.cardID, f.cards[3].id)
        // Every published card is admitted now, so a repeat admission below the boundary adds nothing.
        let repeated = try await f.session.admitPresentation(.forwardScroll(observation(f.cards[3], placement: .top)))
        XCTAssertEqual(repeated, admitted, "An admission with nothing ready to add adds nothing")
    }

    /// An observation inside the admitted list moves the anchor without rebuilding anything.
    func testStationaryObservationMovesTheAnchorWithoutChangingTheList() async throws {
        let f = try fixture()
        let before = try await admitted(f.session, .initial(f.bounds))
        let moved = try await recorded(f.session, observation(f.cards[3], placement: .top))
        XCTAssertEqual(moved.window.items, before.window.items)
        XCTAssertEqual(moved.window.anchor, .init(cardID: f.cards[3].id, placement: .top))
        XCTAssertGreaterThan(moved.provenance.position, before.provenance.position)
        let repeatObservation = try await f.session.submitViewport(observation(f.cards[3], placement: .top))
        XCTAssertEqual(repeatObservation, moved, "An identical observation allocates nothing")
        let unknown = try await f.session.submitViewport(observation(f.cards[0]))
        XCTAssertEqual(unknown, moved, "An anchor outside the admitted list is inert")
        let settled = await f.session.currentPresentation()
        XCTAssertEqual(settled, moved)
    }

    /// A backward observation never admits, even at the head of the list.
    func testBackwardObservationDoesNotAdmit() async throws {
        let f = try fixture()
        let before = try await admitted(f.session, .initial(f.bounds))
        try f.publishTail()
        let atHead = try await recorded(f.session, observation(f.cards[1], placement: .top))
        XCTAssertEqual(atHead.window.items, before.window.items)
        let settled = await f.session.currentPresentation()
        XCTAssertEqual(settled?.window.items.count, before.window.items.count)
    }

    /// Without an installed presentation, recovery is the only path and it installs nothing when
    /// the store has no checkpoint for the requested context.
    func testRestoreWithoutCheckpointInstallsNothing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let empty = try RuntimeDatabase(location: .init(directory: directory))
        let session = FeedSession(publicationHistory: .init(database: empty))
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1)
        let restored = try await session.admitPresentation(.restore(bounds))
        XCTAssertNil(restored)
        let read = await session.currentPresentation()
        XCTAssertNil(read)
        let admitted = try await session.admitPresentation(.forwardScroll(.init(anchor: .init(
            cardID: PublicationCardID(), placement: .center))))
        XCTAssertNil(admitted)
    }
}
