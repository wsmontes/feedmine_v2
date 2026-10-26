import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class SessionStoreTests: XCTestCase {
    func testSeenHighWaterDoesNotRewind() throws {
        let database = try StorageFixture.database(self)
        let store = PublicationStore(database: database), edition = StorageFixture.edition()
        let cards = (0..<4).map { _ in StorageFixture.card() }
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, cards), cards: cards)
        try store.markSeen(editionID: edition.id, cardID: cards[2].id)
        try store.markSeen(editionID: edition.id, cardID: cards[0].id)
        let exposure = try store.exposure(editionID: edition.id, originIDs: [cards[1].originRecordID],
            readerAnchorCardID: cards[0].id)
        XCTAssertTrue(exposure.unseenOriginIDs.isEmpty,
            "The high water reached card 2 and never rewound to card 0")
        XCTAssertEqual(try store.segments(editionID: edition.id).flatMap(\.cardIDs), cards.map(\.id),
            "Seeing a card never removes or reorders a published occurrence")
    }

    func testSingletonReplacementMembershipAndFailedSavePreserveCheckpoint() throws {
        let db = try StorageFixture.database(self)
        let publication = PublicationStore(database: db)
        let sessions = SessionStore(database: db)
        XCTAssertNil(try sessions.checkpoint())
        let e1 = StorageFixture.edition(), e2 = StorageFixture.edition()
        let a = StorageFixture.card(), b = StorageFixture.card()
        for (e,c) in [(e1,a),(e2,b)] { try publication.createEdition(e, firstSegment: StorageFixture.segment(e,[c]), cards:[c]) }
        let original = SessionStore.CheckpointRecord(editionID: e1.id, cardID: a.id, anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 2.5))
        try sessions.saveCheckpoint(original)
        XCTAssertEqual(try sessions.checkpoint(), original)
        XCTAssertThrowsError(try sessions.saveCheckpoint(.init(editionID: e1.id, cardID: b.id, anchorPlacement: "center", updatedAt: original.updatedAt)))
        XCTAssertThrowsError(try sessions.saveCheckpoint(.init(editionID: e1.id, cardID: a.id, anchorPlacement: "bottom", updatedAt: original.updatedAt)))
        XCTAssertThrowsError(try sessions.saveCheckpoint(.init(editionID: e1.id, cardID: a.id, anchorPlacement: "top", updatedAt: Date(timeIntervalSince1970: .infinity))))
        XCTAssertEqual(try sessions.checkpoint(), original)
        XCTAssertThrowsError(try db.write { try $0.execute(sql: "DELETE FROM feed_editions WHERE id = ?", arguments:[e1.id.rawValue.uuidString.lowercased()]) })
        XCTAssertThrowsError(try db.write { try $0.execute(sql: "DELETE FROM published_cards WHERE id = ?", arguments:[a.id.rawValue.uuidString.lowercased()]) })
        let replacement = SessionStore.CheckpointRecord(editionID: e2.id, cardID: b.id, anchorPlacement: "top", updatedAt: Date(timeIntervalSince1970: 3))
        try sessions.saveCheckpoint(replacement)
        XCTAssertEqual(try sessions.checkpoint(), replacement)
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql:"SELECT count(*) FROM session_checkpoint") }, 1)
    }

    /// 2026-10-20: a record whose card is filed under another Edition is **still the reader's position**, not
    /// corruption. Reading it as an error would let a rebuilt Edition delete the position (the launch then
    /// restarts at the top); reading it as nil would be worse — a silent cold start. The record reads, and the
    /// restore resolves the card against the Edition that actually holds it (`PublicationHistory.restore`).
    func testACardFiledUnderAnotherEditionStillReadsAsTheReadersPosition() throws {
        let db = try StorageFixture.database(self)
        let publication = PublicationStore(database: db)
        let sessions = SessionStore(database: db)
        let e1 = StorageFixture.edition(), e2 = StorageFixture.edition()
        let a = StorageFixture.card(), b = StorageFixture.card()
        for (e,c) in [(e1,a),(e2,b)] { try publication.createEdition(e, firstSegment: StorageFixture.segment(e,[c]), cards:[c]) }
        try sessions.saveCheckpoint(.init(editionID:e1.id,cardID:a.id,anchorPlacement:"center",updatedAt:Date(timeIntervalSince1970:1)))
        try db.write { try $0.execute(sql:"UPDATE session_checkpoint SET card_id = ?",arguments:[b.id.rawValue.uuidString.lowercased()]) }
        let record = try XCTUnwrap(try sessions.checkpoint())
        XCTAssertEqual(record.cardID, b.id)
        XCTAssertEqual(record.editionID, e1.id, "a linha continua dizendo onde foi arquivada")
        XCTAssertEqual(try publication.location(ofCard: b.id)?.editionID, e2.id,
            "a carta pertence à sua própria edição, e é ela que a restauração lê")
        // Writing a pair that contradicts itself is still refused: the reader's position must stay locatable.
        XCTAssertThrowsError(try sessions.saveCheckpoint(.init(editionID: e1.id, cardID: b.id,
            anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 2))))
    }
    /// Continuity extension: the relative point survives the singleton and the per-context row, and a row that
    /// carries only one of the two values reads as absent (the card record still stands).
    func testTheRelativePointRoundTripsBothCheckpointTables() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db), sessions = SessionStore(database: db)
        let edition = StorageFixture.edition(), card = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [card]), cards: [card])
        let record = SessionStore.CheckpointRecord(editionID: edition.id, cardID: card.id,
            anchorPlacement: "top", updatedAt: Date(timeIntervalSince1970: 5),
            topDelta: -159, cardHeight: 600)
        try sessions.saveCheckpoint(record)
        XCTAssertEqual(try sessions.checkpoint(), record)
        let key = ContextKey(request: .main)
        XCTAssertEqual(try sessions.checkpoint(for: key), record)
        try sessions.activateContext(key)
        XCTAssertEqual(try sessions.checkpoint(), record, "a troca de contexto reinstala o mesmo ponto relativo")
        // An incomplete pair is not a relative point; the row still names the reader's card.
        try db.write { db in
            try db.execute(sql: "UPDATE context_checkpoints SET anchor_height = NULL")
        }
        let incomplete = try XCTUnwrap(try sessions.checkpoint(for: key))
        XCTAssertNil(incomplete.cardHeight)
        XCTAssertEqual(incomplete.topDelta, -159)
        XCTAssertEqual(incomplete.cardID, card.id)
    }

    func testContextSwitchArchivesAndRestoresEachCheckpoint() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db), sessions = SessionStore(database: db)
        let main = StorageFixture.edition(), source = SourceID(), r = main.editorialRevision
        let sourceRevision = EditorialRevision(id: EditorialRevisionID(), contextKey: .init(request: .source(source)),
            catalogGeneration: r.catalogGeneration, userSelectionVersion: r.userSelectionVersion,
            eligibilityPolicyVersion: r.eligibilityPolicyVersion, scoringPolicyVersion: r.scoringPolicyVersion,
            sequencingPolicyVersion: r.sequencingPolicyVersion, exposurePolicyVersion: r.exposurePolicyVersion,
            selectionSchemaVersion: r.selectionSchemaVersion)
        let other = StorageFixture.edition(revision: sourceRevision), a = StorageFixture.card(), b = StorageFixture.card()
        for (e,c) in [(main,a),(other,b)] { try store.createEdition(e, firstSegment: StorageFixture.segment(e,[c]), cards: [c]) }
        let first = SessionStore.CheckpointRecord(editionID: main.id, cardID: a.id, anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 1))
        let second = SessionStore.CheckpointRecord(editionID: other.id, cardID: b.id, anchorPlacement: "top", updatedAt: Date(timeIntervalSince1970: 2))
        try sessions.saveCheckpoint(first)
        try sessions.activateContext(.source(source))
        XCTAssertNil(try sessions.checkpoint())
        try sessions.saveCheckpoint(second)
        try sessions.activateContext(.main)
        XCTAssertEqual(try sessions.checkpoint(), first)
        try sessions.activateContext(.source(source))
        XCTAssertEqual(try sessions.checkpoint(), second)
        XCTAssertNotNil(try store.card(id: a.id))
    }

}
