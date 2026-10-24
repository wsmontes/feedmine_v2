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
            try history.saveCursor(SessionCursor(editionID: edition.id,
                anchor: FeedWindowAnchor(cardID: cards[4].id, placement: .top)), updatedAt: savedAt)

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
