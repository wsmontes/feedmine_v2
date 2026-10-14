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

    /// A forward scroll at the boundary admits the ready cards beyond the tail into the anchored window:
    /// the reader's frozen bounds decide the list, so what is published past the tail enters and what is
    /// left behind the backward bound leaves — still in the store, and read back by the next admission there.
    func testForwardScrollAdmitsOnlyReadyPrefix() async throws {
        let f = try fixture()
        // Expected windows are derived from the anchor, the fixture's bounds and the published order — never
        // from a hand-copied published prefix: the admitted list is the window around the anchor, at most the
        // frozen backward capacity before it and the frozen forward capacity after it.
        let published = f.cards.map(\.id)
        func expectedWindow(around card: PublishedCard) throws -> [PublicationCardID] {
            let index = try XCTUnwrap(published.firstIndex(of: card.id))
            let start = max(0, index - f.bounds.backwardCapacity)
            let end = min(published.count - 1, index + f.bounds.forwardCapacity)
            return Array(published[start...end])
        }
        let before = try await admitted(f.session, .initial(f.bounds))
        // The installed window is the checkpoint anchor's neighbourhood, clamped to what is published then
        // (cards[4...5] do not exist yet).
        XCTAssertEqual(before.window.items.map(\.id), Array(f.cards[1...3]).map(\.id))
        try f.publishTail()
        let observed = observation(f.cards[3], placement: .top)
        // The driver records the reader's position first; only then does the gesture admit.
        _ = try await f.session.submitViewport(observed)
        let forward = try await admitted(f.session, .forwardScroll(observed))
        // The new anchor's neighbourhood: cards[4...5] enter past the tail, and cards[1] — admitted before —
        // is left behind by the frozen backward bound.
        let expected = try expectedWindow(around: f.cards[3])
        XCTAssertEqual(forward.window.items.map(\.id), expected)
        XCTAssertEqual(forward.window.items.count, f.bounds.backwardCapacity + 1 + f.bounds.forwardCapacity)
        // The window is centred on the reader: exactly the frozen backward capacity before the anchor and the
        // frozen forward capacity after it.
        let anchorPosition = try XCTUnwrap(forward.window.items.firstIndex { $0.id == f.cards[3].id })
        XCTAssertEqual(anchorPosition, f.bounds.backwardCapacity)
        XCTAssertEqual(forward.window.items.count - anchorPosition - 1, f.bounds.forwardCapacity)
        // The cards the window keeps keep identity, order and projection; the only card that leaves is the one
        // behind the backward bound.
        let kept = before.window.items.filter { expected.contains($0.id) }
        XCTAssertEqual(Array(forward.window.items.prefix(kept.count)), kept,
            "Earlier cards keep identity, order and projection")
        XCTAssertEqual(before.window.items.map(\.id).filter { !expected.contains($0) }, [f.cards[1].id],
            "Only the card behind the reader leaves the window")
        XCTAssertEqual(Set(forward.window.items.map(\.id)).count, forward.window.items.count)
        XCTAssertEqual(forward.window.anchor, .init(cardID: f.cards[3].id, placement: .top))
        XCTAssertEqual(forward.provenance.sequenceID, before.provenance.sequenceID,
            "The session keeps its projection sequence")
        XCTAssertGreaterThan(forward.provenance.position, before.provenance.position,
            "The admission allocates a new projection in the session's sequence")
        // The window already reaches the published tail, so a repeat admission has nothing ready to add.
        let repeated = try await admitted(f.session, .forwardScroll(observation(f.cards[3], placement: .top)))
        XCTAssertEqual(repeated, forward, "An admission with nothing ready to add adds nothing")
        // Leaving the window is not losing the card: the cut card is still published in the local store ...
        let stored = try PublicationHistory(database: f.database).window(editionID: f.edition.id,
            around: FeedWindowAnchor(cardID: f.cards[1].id, placement: .center),
            backwardCapacity: 0, forwardCapacity: 0)
        XCTAssertEqual(stored.cards.map(\.id), [f.cards[1].id])
        // ... and the next admission near it reads it back, in its place before the anchor. Recording the
        // reader's position alone never changes the admitted list.
        let atHead = try await recorded(f.session, observation(f.cards[2]))
        XCTAssertEqual(atHead.window.items.map(\.id), expected,
            "Recording a position never widens the window")
        let headWindow = try expectedWindow(around: f.cards[2])
        let back = try await admitted(f.session, .backwardScroll(observation(f.cards[2])))
        XCTAssertEqual(back.window.items.map(\.id), headWindow,
            "The admission next to the cut card brings it back, in order, before the anchor")
        XCTAssertEqual(back.window.items.first?.id, f.cards[1].id)
        XCTAssertEqual(back.window.anchor, .init(cardID: f.cards[2].id, placement: .center))
        XCTAssertFalse(back.window.items.contains { $0.id == f.cards[5].id },
            "The same anchored bound cuts both ends: the far card leaves while the cut one returns")
    }

    /// Decisão do dono (2026-10-13): a lista pode **manter a cabeça**. Continua limitada à frente, mas nada acima
    /// do leitor é removido — é o comportamento da V1, e é o que deixa o corretor de offset sem nada a corrigir.
    /// O default preserva a regra do arquiteto (limitada nos dois sentidos), provada logo acima.
    func testKeptHeadNeverRemovesTheCardsBehindTheReader() async throws {
        let f = try fixture()
        XCTAssertFalse(f.bounds.keepsAdmittedHead, "o default do bounds continua a regra do arquiteto")
        let bounds = FeedPresentationBounds(backwardCapacity: f.bounds.backwardCapacity,
            forwardCapacity: f.bounds.forwardCapacity, keepsAdmittedHead: true)
        let before = try await admitted(f.session, .initial(bounds))
        XCTAssertEqual(before.window.items.map(\.id), Array(f.cards[1...3]).map(\.id))
        try f.publishTail()
        let observed = observation(f.cards[3], placement: .top)
        _ = try await f.session.submitViewport(observed)
        let forward = try await admitted(f.session, .forwardScroll(observed))
        XCTAssertEqual(forward.window.items.map(\.id), Array(f.cards[1...5]).map(\.id),
            "com a cabeça mantida, a carta que o leitor já passou continua na lista")
        XCTAssertEqual(Set(forward.window.items.map(\.id)).count, forward.window.items.count)
        XCTAssertEqual(forward.window.anchor, .init(cardID: f.cards[3].id, placement: .top))
        // O teto à frente continua valendo: a cauda é exatamente a âncora mais a reserva congelada.
        let anchorPosition = try XCTUnwrap(forward.window.items.firstIndex { $0.id == f.cards[3].id })
        XCTAssertEqual(forward.window.items.count - anchorPosition - 1, f.bounds.forwardCapacity,
            "a reserva à frente permanece limitada")
        // E a cabeça não se move: as cartas admitidas antes continuam idênticas, na mesma ordem, no mesmo lugar.
        let kept = before.window.items.filter { forward.window.items.contains($0) }
        XCTAssertEqual(Array(forward.window.items.prefix(kept.count)), kept,
            "nada acima do leitor muda quando a lista cresce para frente")
    }

    /// R4/F05: the runtime grows the admitted window with cards **already published**, without any
    /// reader gesture and without inventing one. The anchor, the order and every admitted card stay
    /// exactly as they were; only the end of the list moves.
    func testPublishedGrowthAppendsWithoutAGestureAndKeepsTheAnchor() async throws {
        let f = try fixture()
        let before = try await admitted(f.session, .initial(f.bounds))
        // Nothing published beyond the admitted tail yet: growth is a no-op, not a new projection.
        let unchanged = try await f.session.admitPresentation(.publishedGrowth)
        XCTAssertEqual(unchanged, before)
        try f.publishTail()
        let grown = try await admitted(f.session, .publishedGrowth)
        XCTAssertGreaterThan(grown.window.items.count, before.window.items.count,
            "Cards the store already published enter without a reader gesture")
        let anchorIndex = try XCTUnwrap(grown.window.items.firstIndex { $0.id == grown.window.anchor.cardID })
        XCTAssertLessThanOrEqual(grown.window.items.count, anchorIndex + f.bounds.forwardCapacity + 1,
            "Growth fills the reader's forward window and stops at its frozen bound")
        XCTAssertEqual(Array(grown.window.items.prefix(before.window.items.count)), before.window.items,
            "Earlier cards keep identity, order and projection")
        XCTAssertEqual(Set(grown.window.items.map(\.id)).count, grown.window.items.count,
            "Growth appends once per card: no duplicates")
        XCTAssertEqual(grown.window.anchor, before.window.anchor, "Growth never moves the reading point")
        XCTAssertEqual(grown.contextKey, before.contextKey)
        XCTAssertEqual(grown.editionID, before.editionID)
        let repeated = try await f.session.admitPresentation(.publishedGrowth)
        XCTAssertEqual(repeated, grown, "A repeat never walks the tail past the bound")
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
