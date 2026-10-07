import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class SessionStoreTests: XCTestCase {
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
}
