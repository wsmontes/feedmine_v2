import Foundation
import GRDB
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication
@testable import FeedMineRuntime

/// 2026-10-20 (D10): the reader's position is a **card**, not a row of one Edition's layout.
///
/// The reopen resolved the saved anchor against the Edition its record spells. Once the discovery pool admitted
/// audio sources, a later publication rebuilt the Edition for the same context — a new revision, a new segment
/// seed, a pool drawn again — and the restore had no way to find the card the reader left there: the read threw
/// (`anchor membership`), the launch took the cold path, and the reader landed at the top of a layout that was not
/// theirs. These tests state the contract the fix implements: the restore lands on the durable card — or on the
/// neighbour it names when that card left published history — whatever Edition is current.
final class DurableAnchorRestoreTests: XCTestCase {

    private let savedAt = Date(timeIntervalSince1970: 500)

    private func withLocation(_ body: (RuntimeDatabaseLocation) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(RuntimeDatabaseLocation(directory: directory))
    }

    private func revision(contextKey: ContextKey) -> EditorialRevision {
        EditorialRevision(id: EditorialRevisionID(), contextKey: contextKey,
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 2),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 3), scoringPolicyVersion: PolicyVersion(rawValue: 4),
            sequencingPolicyVersion: PolicyVersion(rawValue: 5), exposurePolicyVersion: PolicyVersion(rawValue: 6),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 7))
    }

    private func makeEdition(_ revision: EditorialRevision, seed: UInt64) -> FeedEdition {
        FeedEdition(id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1), selectionSeed: seed,
            createdAt: Date(timeIntervalSince1970: 40))
    }

    private func publish(_ edition: FeedEdition, cards: [PublishedCard], in store: PublicationStore) throws {
        let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: edition.id, ordinal: 0,
            segmentSeed: edition.selectionSeed + 1, publicationSchemaVersion: edition.publicationSchemaVersion,
            createdAt: edition.createdAt, cardIDs: cards.map(\.id)))
        let records = try PublicationPersistenceMapping.records(segment: segment, cards: cards)
        try store.createEdition(PublicationPersistenceMapping.record(edition), firstSegment: records.0,
            cards: records.1)
    }

    private func makeCards(_ count: Int, prefix: String) throws -> [PublishedCard] {
        try (0..<count).map {
            try WarmPresentationFixture.card(layout: .textOnly, action: nil, title: "\(prefix)\($0)")
        }
    }

    /// The reproduction: a checkpoint names the card the reader left, and a **newly built Edition** — the kind a
    /// rebuild publishes, whose segment and pool never contained that card — is the Edition the record spells. The
    /// restored window must start at the reader's card (and be read from the Edition that holds it), not at the top
    /// of the rebuilt one. Before the fix this throws `PublicationStoreError.corruption("anchor membership")` (or,
    /// one read earlier, `SessionStoreError.corruption`), which is how the reopen loses the position and the launch
    /// restarts cold.
    func testTheReaderCardIsRestoredWhenTheRebuiltEditionCannotHoldIt() async throws {
        try await withLocation { location in
            let database = try RuntimeDatabase(location: location)
            let store = PublicationStore(database: database)
            let contextKey = ContextKey(request: .main)
            let first = makeEdition(revision(contextKey: contextKey), seed: 1)
            let firstCards = try makeCards(10, prefix: "A")
            try publish(first, cards: firstCards, in: store)
            try PublicationHistory(database: database).saveCursor(SessionCursor(editionID: first.id,
                anchor: FeedWindowAnchor(cardID: firstCards[6].id, placement: .top)), updatedAt: savedAt)

            // The rebuild: same context identity, another revision and another segment seed, a pool without the
            // reader's card (D10 admits audio, so the pool is drawn again and the Edition is republished).
            let rebuilt = makeEdition(revision(contextKey: contextKey), seed: 2)
            let rebuiltCards = try makeCards(6, prefix: "B")
            try publish(rebuilt, cards: rebuiltCards, in: store)
            // The durable record now spells the rebuilt Edition — the state a carried-over checkpoint has.
            try database.write { db in
                try db.execute(sql: "UPDATE session_checkpoint SET edition_id = ?",
                    arguments: [rebuilt.id.rawValue.uuidString.lowercased()])
            }

            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 2,
                forwardCapacity: 2, keepsAdmittedHead: true)))
            let snapshot = try XCTUnwrap(restored)
            XCTAssertEqual(snapshot.editionID, first.id,
                "a janela é lida da edição que contém a carta durável, não da edição que a linha nomeia")
            XCTAssertEqual(snapshot.window.anchor, PresentationAnchor(cardID: firstCards[6].id, placement: .top),
                "a reabertura começa na carta que o leitor deixou, não no topo")
            XCTAssertEqual(snapshot.window.items.first?.id, firstCards[0].id,
                "a cabeça admitida continua vindo junto: a carta salva acima do leitor permanece desenhada")

            let direct = try XCTUnwrap(PublicationHistory(database: database)
                .restore(backwardCapacity: 2, forwardCapacity: 2))
            XCTAssertEqual(direct.position, .exact(firstCards[6].id))
            XCTAssertEqual(direct.edition.id, first.id)
            XCTAssertEqual(direct.window.cards.map(\.id), Array(firstCards[4...8]).map(\.id))
        }
    }

    /// The same restore, unchanged Edition: the durable card is still where the window starts, and the bounded
    /// read is still the neighbourhood of that card.
    func testTheRestoreStillStartsAtTheReaderCardWhenTheEditionIsUnchanged() async throws {
        try await withLocation { location in
            let database = try RuntimeDatabase(location: location)
            let store = PublicationStore(database: database)
            let edition = makeEdition(revision(contextKey: ContextKey(request: .main)), seed: 3)
            let cards = try makeCards(10, prefix: "C")
            try publish(edition, cards: cards, in: store)
            let history = PublicationHistory(database: database)
            let progress = try XCTUnwrap(CardTopOffset(topDelta: -120, height: 500))
            try history.saveCursor(SessionCursor(editionID: edition.id,
                anchor: FeedWindowAnchor(cardID: cards[4].id, placement: .top), progress: progress),
                updatedAt: savedAt)

            let bounded = try XCTUnwrap(history.restore(backwardCapacity: 2, forwardCapacity: 2))
            XCTAssertEqual(bounded.position, .exact(cards[4].id))
            XCTAssertEqual(bounded.window.anchor, FeedWindowAnchor(cardID: cards[4].id, placement: .top))
            XCTAssertEqual(bounded.window.cards.map(\.id), Array(cards[2...6]).map(\.id))

            let head = try XCTUnwrap(history.restoreFromEditionStart(forwardCapacity: 2))
            XCTAssertEqual(head.position, .exact(cards[4].id))
            XCTAssertEqual(head.window.anchor.cardID, cards[4].id)
            XCTAssertEqual(head.window.cards.map(\.id), Array(cards[0...6]).map(\.id))

            let session = FeedSession(publicationHistory: PublicationHistory(database: database))
            let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 2,
                forwardCapacity: 2, keepsAdmittedHead: true)))
            XCTAssertEqual(restored?.window.anchor, PresentationAnchor(cardID: cards[4].id, placement: .top))
            XCTAssertEqual(restored?.editionID, edition.id)
            XCTAssertEqual(restored?.restoredPosition, PresentationAnchor(cardID: cards[4].id,
                placement: .top, progress: progress), "a restauração exata carrega o ponto relativo")
        }
    }

    /// The rule a withdrawn card lands by, at the read that decides it. A checkpoint cannot name an archived card
    /// in this schema (the row is referenced), so the neighbour rule is exercised where it lives: the position is
    /// still known, the card is not drawable, and the nearest surviving card before it is the landing.
    func testAWithdrawnCardLandsOnItsNearestSurvivingNeighbour() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: directory))
        let store = PublicationStore(database: database)
        let edition = makeEdition(revision(contextKey: ContextKey(request: .main)), seed: 4)
        let cards = try makeCards(6, prefix: "D")
        try publish(edition, cards: cards, in: store)

        // What tail succession does to an unseen suffix: archive the rows, then delete the live ones.
        let tail = cards[5]
        try database.write { db in
            let key = tail.id.rawValue.uuidString.lowercased()
            try db.execute(sql: """
                INSERT INTO retired_published_cards SELECT * FROM published_cards WHERE id = ?
                """, arguments: [key])
            try db.execute(sql: """
                INSERT INTO retired_feed_segments SELECT * FROM feed_segments
                WHERE id = (SELECT segment_id FROM published_cards WHERE id = ?)
                """, arguments: [key])
            try db.execute(sql: "DELETE FROM published_cards WHERE id = ?", arguments: [key])
        }

        let archived = try XCTUnwrap(store.location(ofCard: tail.id))
        XCTAssertFalse(archived.isLive, "a carta não é mais desenhável")
        XCTAssertEqual(archived.editionID, edition.id)
        XCTAssertEqual(archived.segmentOrdinal, 0)
        XCTAssertEqual(archived.cardOrdinal, 5)
        XCTAssertEqual(try store.survivingCard(inEdition: edition.id, beforeSegment: 0, cardOrdinal: 5),
            cards[4].id, "o vizinho sobrevivente mais próximo é a carta imediatamente anterior")
        XCTAssertEqual(try store.survivingCard(inEdition: edition.id, beforeSegment: 0, cardOrdinal: 0),
            cards[0].id, "uma posição antes do início da edição cai para a primeira carta sobrevivente")
        XCTAssertNil(try store.location(ofCard: PublicationCardID()),
            "uma carta que este banco nunca publicou não tem localização")
    }
}

extension DurableAnchorRestoreTests {
    func testOwnedFeedSessionRestoresAndCheckpointsThenRejectsRetiredMilestone() async throws {
        try await withLocation { location in
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db)
            let edition = makeEdition(revision(contextKey: ContextKey(request: .main)), seed: 4)
            let cards = try makeCards(3, prefix: "owned")
            try publish(edition, cards: cards, in: store)
            let cursor = SessionCursor(editionID: edition.id, anchor: .init(cardID: cards[1].id, placement: .top),
                progress: try XCTUnwrap(CardTopOffset(topDelta: -25, height: 300)))
            try PublicationHistory(database: db).saveCursor(cursor, updatedAt: savedAt)
            let bindings = ReaderHistoryBindingStore(database: db), checkpoints = SessionStore(database: db)
            let binding = try bindings.resolve(logicalKey: edition.editorialRevision.contextKey,
                adopting: .init(editionID: edition.id, publicationKey: edition.editorialRevision.contextKey, evidence: .exactContext))
            let active = try checkpoints.activateBinding(binding.id)
            let reader = FeedSession(publicationHistory: PublicationHistory(database: db, bindingActivation: active))
            let result = try await reader.admitPresentation(.restore(.init(backwardCapacity: 2, forwardCapacity: 1,
                contextKey: edition.editorialRevision.contextKey, keepsAdmittedHead: true)))
            let snapshot = try XCTUnwrap(result)
            XCTAssertEqual(snapshot.editionID, edition.id)
            XCTAssertEqual(snapshot.window.items.map(\.id), cards.map(\.id))
            XCTAssertEqual(snapshot.window.anchor, PresentationAnchor(cardID: cursor.anchor.cardID, placement: .top))
            let wrote = try await reader.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 600))
            XCTAssertTrue(wrote)
            let saved = try checkpoints.checkpoint(bindingID: binding.id)
            XCTAssertEqual(saved?.cardID, cursor.anchor.cardID)
            let other = try bindings.resolve(logicalKey: ContextKey(request: .source(SourceID())))
            _ = try checkpoints.activateBinding(other.id)
            do {
                _ = try await reader.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 700))
                XCTFail("a retired FeedSession must not checkpoint over the new reader")
            } catch { XCTAssertEqual(error as? SessionStoreError, .staleHistoryBinding) }
            XCTAssertNil(try checkpoints.checkpoint())
            XCTAssertEqual(try checkpoints.checkpoint(bindingID: binding.id), saved)
        }
    }
    func testPreparedFeedSessionCanRestoreBeforePromotionButCannotCheckpointOverPresentedReader() async throws {
        try await withLocation { location in
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db)
            let a = makeEdition(revision(contextKey: ContextKey(request: .main)), seed: 4)
            let b = makeEdition(revision(contextKey: ContextKey(request: .source(SourceID()))), seed: 5)
            let cardsA = try makeCards(3, prefix: "presented"), cardsB = try makeCards(3, prefix: "prepared")
            try publish(a, cards: cardsA, in: store)
            try publish(b, cards: cardsB, in: store)
            let legacy = PublicationHistory(database: db)
            try legacy.saveCursor(.init(editionID: b.id, anchor: .init(cardID: cardsB[1].id, placement: .top)), updatedAt: savedAt)
            try legacy.saveCursor(.init(editionID: a.id, anchor: .init(cardID: cardsA[1].id, placement: .top)), updatedAt: savedAt)
            let bindings = ReaderHistoryBindingStore(database: db), checkpoints = SessionStore(database: db)
            let ba = try bindings.resolve(logicalKey: a.editorialRevision.contextKey,
                adopting: .init(editionID: a.id, publicationKey: a.editorialRevision.contextKey, evidence: .exactContext))
            let bb = try bindings.resolve(logicalKey: b.editorialRevision.contextKey,
                adopting: .init(editionID: b.id, publicationKey: b.editorialRevision.contextKey, evidence: .exactContext))
            let active = try checkpoints.activateBinding(ba.id)
            let current = FeedSession(publicationHistory: PublicationHistory(database: db, bindingActivation: active))
            _ = try await current.admitPresentation(.initial(.init(backwardCapacity: 2, forwardCapacity: 2)))
            let pointA = try checkpoints.checkpoint()
            let pending = try checkpoints.prepareBinding(bb.id)
            let next = FeedSession(publicationHistory: PublicationHistory(database: db, bindingActivation: pending))
            let restored = try await next.admitPresentation(.initial(.init(backwardCapacity: 2, forwardCapacity: 2)))
            XCTAssertEqual(restored?.editionID, b.id)
            XCTAssertEqual(restored?.window.anchor.cardID, cardsB[1].id)
            do {
                _ = try await next.checkpointCurrentPosition(at: Date())
                XCTFail("a hidden candidate has no viewport authority")
            } catch { XCTAssertEqual(error as? SessionStoreError, .staleHistoryBinding) }
            XCTAssertEqual(try checkpoints.checkpoint(), pointA)
            _ = try await current.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 600))
            try checkpoints.promotePreparedBinding(pending)
            let wrote = try await next.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 700))
            XCTAssertTrue(wrote)
            XCTAssertEqual(try checkpoints.checkpoint()?.editionID, b.id)
            do {
                _ = try await current.checkpointCurrentPosition(at: Date())
                XCTFail("the old presented reader is retired only after promotion")
            } catch { XCTAssertEqual(error as? SessionStoreError, .staleHistoryBinding) }
        }
    }

    func testOnlyHiddenPreparedReaderCanRefreshFromTheFinalPredecessorPoint() async throws {
        try await withLocation { location in
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db)
            let e = makeEdition(revision(contextKey: ContextKey(request: .main)), seed: 4)
            let cards = try makeCards(3, prefix: "handoff")
            try publish(e, cards: cards, in: store)
            try PublicationHistory(database: db).saveCursor(.init(editionID: e.id,
                anchor: .init(cardID: cards[0].id, placement: .top)), updatedAt: savedAt)
            let bindings = ReaderHistoryBindingStore(database: db), checkpoints = SessionStore(database: db)
            let binding = try bindings.resolve(logicalKey: e.editorialRevision.contextKey,
                adopting: .init(editionID: e.id, publicationKey: e.editorialRevision.contextKey, evidence: .exactContext))
            let active = try checkpoints.activateBinding(binding.id)
            let bounds = FeedPresentationBounds(backwardCapacity: 2, forwardCapacity: 2, keepsAdmittedHead: true)
            let current = FeedSession(publicationHistory: PublicationHistory(database: db, bindingActivation: active))
            _ = try await current.admitPresentation(.initial(bounds))
            let prepared = try checkpoints.prepareBinding(binding.id)
            let next = FeedSession(publicationHistory: PublicationHistory(database: db, bindingActivation: prepared))
            let first = try await next.admitPresentation(.initial(bounds))
            XCTAssertEqual(first?.window.anchor.cardID, cards[0].id)
            _ = try await current.submitViewport(.init(anchor: .init(cardID: cards[2].id, placement: .top)), deliberate: true)
            _ = try await current.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 800))
            let refreshed = try await next.refreshPreparedPresentation(bounds)
            XCTAssertEqual(refreshed?.window.anchor.cardID, cards[2].id)
            XCTAssertEqual(refreshed?.provenance.sequenceID, first?.provenance.sequenceID)
            XCTAssertGreaterThan(try XCTUnwrap(refreshed?.provenance.position), try XCTUnwrap(first?.provenance.position))
            let point = try checkpoints.checkpoint()
            do { _ = try await current.refreshPreparedPresentation(bounds); XCTFail("current admitted reader cannot reset its projection") }
            catch { XCTAssertEqual(error as? FeedSessionError, .readerIsNotPrepared) }
            try checkpoints.promotePreparedBinding(prepared)
            do { _ = try await next.refreshPreparedPresentation(bounds); XCTFail("promotion closes hidden refresh authority") }
            catch { XCTAssertEqual(error as? FeedSessionError, .readerIsNotPrepared) }
            XCTAssertEqual(try checkpoints.checkpoint(), point)
        }
    }

}
