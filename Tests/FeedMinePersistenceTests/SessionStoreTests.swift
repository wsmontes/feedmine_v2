import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class SessionStoreTests: XCTestCase {
    func testUnseenSuccessionArchivesOldValuesAndRollsBackOnIdentityConflict() throws {
        let database = try StorageFixture.database(self)
        let store = PublicationStore(database: database), edition = StorageFixture.edition()
        let cards = (0..<4).map { _ in StorageFixture.card() }
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, cards), cards: cards)
        let checkpoint = SessionStore.CheckpointRecord(editionID: edition.id, cardID: cards[0].id, anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: 1234))
        try SessionStore(database: database).saveCheckpoint(checkpoint)
        let lease = try XCTUnwrap(store.hiddenTail(editionID: edition.id))
        XCTAssertThrowsError(try store.succeedTail(lease: lease, segmentID: FeedSegmentID(), cards: [cards[0]], createdAt: Date()))
        XCTAssertEqual(try store.segments(editionID: edition.id).flatMap(\.cardIDs), cards.map(\.id))
        let newest = StorageFixture.card()
        XCTAssertEqual(try store.succeedTail(lease: lease, segmentID: FeedSegmentID(), cards: [newest], createdAt: Date()), .applied)
        XCTAssertEqual(try store.segments(editionID: edition.id).flatMap(\.cardIDs), [cards[0].id, newest.id])
        XCTAssertEqual(try store.card(id: cards[1].id), cards[1])
        XCTAssertEqual(try store.card(id: cards[0].id), cards[0])
        XCTAssertEqual(try SessionStore(database: database).checkpoint(), checkpoint)
        XCTAssertEqual(try store.succeedTail(lease: lease, segmentID: FeedSegmentID(), cards: [StorageFixture.card()], createdAt: Date()), .stale)
    }

    func testSeenHighWaterDoesNotRewindAndHiddenLeaseIsRevokedByForeground() throws {
        let database = try StorageFixture.database(self)
        let store = PublicationStore(database: database), edition = StorageFixture.edition()
        let cards = (0..<4).map { _ in StorageFixture.card() }
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, cards), cards: cards)
        try store.markSeen(editionID: edition.id, cardID: cards[2].id)
        try store.markSeen(editionID: edition.id, cardID: cards[0].id)
        let lease = try XCTUnwrap(store.hiddenTail(editionID: edition.id))
        XCTAssertEqual(lease.highWaterCardID, cards[2].id)
        try store.setVisibility(editionID: edition.id, visible: true)
        let updated = StorageFixture.card()
        XCTAssertEqual(try store.succeedTail(lease: lease, segmentID: FeedSegmentID(), cards: [updated], createdAt: Date()), .stale)
        XCTAssertNil(try store.card(id: updated.id))
        XCTAssertEqual(try store.segments(editionID: edition.id).flatMap(\.cardIDs), cards.map(\.id))
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

    func testPersistedEditionCardMismatchThrowsCorruptionInsteadOfNil() throws {
        let db = try StorageFixture.database(self)
        let publication = PublicationStore(database: db)
        let sessions = SessionStore(database: db)
        let e1 = StorageFixture.edition(), e2 = StorageFixture.edition()
        let a = StorageFixture.card(), b = StorageFixture.card()
        for (e,c) in [(e1,a),(e2,b)] { try publication.createEdition(e, firstSegment: StorageFixture.segment(e,[c]), cards:[c]) }
        try sessions.saveCheckpoint(.init(editionID:e1.id,cardID:a.id,anchorPlacement:"center",updatedAt:Date(timeIntervalSince1970:1)))
        try db.write { try $0.execute(sql:"UPDATE session_checkpoint SET card_id = ?",arguments:[b.id.rawValue.uuidString.lowercased()]) }
        XCTAssertThrowsError(try sessions.checkpoint()) { error in
            guard case SessionStoreError.corruption = error else { return XCTFail("Expected corruption: \(error)") }
        }
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
