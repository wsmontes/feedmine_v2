import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class InitialPublicationAtomicityTests: XCTestCase {
    private func checkpoint(_ e: PublicationStore.EditionRecord, _ c: PublicationStore.CardRecord,
        time: Double = 200) -> SessionStore.CheckpointRecord {
        .init(editionID: e.id, cardID: c.id, anchorPlacement: "center", updatedAt: Date(timeIntervalSince1970: time))
    }
    private func assertAbsent(_ db: RuntimeDatabase, _ e: PublicationStore.EditionRecord,
        _ s: PublicationStore.SegmentRecord, _ c: PublicationStore.CardRecord) throws {
        let store = PublicationStore(database: db)
        XCTAssertNil(try store.edition(id: e.id))
        XCTAssertNil(try store.card(id: c.id))
        XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM feed_segments WHERE id = ?", arguments: [s.id.rawValue.uuidString.lowercased()]) }, 0)
    }
    func testP1SuccessCreatesFourExactFacts() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let e = StorageFixture.edition(), c = StorageFixture.card(), s: PublicationStore.SegmentRecord
        s = StorageFixture.segment(e, [c])
        let cp = checkpoint(e, c)
        try store.createInitialEdition(e, firstSegment: s, cards: [c], initialCheckpoint: cp)
        XCTAssertEqual(try store.edition(id: e.id), e)
        XCTAssertEqual(try store.segments(editionID: e.id), [s])
        XCTAssertEqual(try store.card(id: c.id), c)
        XCTAssertEqual(try SessionStore(database: db).checkpoint(), cp)
    }
    func testP2CheckpointCardOutsideSegmentWritesNothing() throws {
        let db = try StorageFixture.database(self), e = StorageFixture.edition(), c = StorageFixture.card()
        let s = StorageFixture.segment(e, [c])
        XCTAssertThrowsError(try PublicationStore(database: db).createInitialEdition(e, firstSegment: s, cards: [c], initialCheckpoint: checkpoint(e, StorageFixture.card()))) {
            XCTAssertEqual($0 as? PublicationStoreError, .invalidInitialCheckpoint)
        }
        try assertAbsent(db, e, s, c)
        XCTAssertNil(try SessionStore(database: db).checkpoint())
    }
    func testP3FinalCheckpointFailureRollsBackPublication() throws {
        let db = try StorageFixture.database(self), e = StorageFixture.edition(), c = StorageFixture.card()
        let s = StorageFixture.segment(e, [c])
        XCTAssertThrowsError(try PublicationStore(database: db).createInitialEdition(e, firstSegment: s, cards: [c], initialCheckpoint: checkpoint(e, c, time: .infinity))) {
            XCTAssertEqual($0 as? SessionStoreError, .invalidRepresentation("updated_at"))
        }
        try assertAbsent(db, e, s, c)
        XCTAssertNil(try SessionStore(database: db).checkpoint())
    }
    func testP4ExistingCheckpointBlocksTakeoverAndRemainsUnchanged() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let old = StorageFixture.edition(), oldCard = StorageFixture.card(), oldSegment = StorageFixture.segment(old, [oldCard])
        let original = checkpoint(old, oldCard)
        try store.createInitialEdition(old, firstSegment: oldSegment, cards: [oldCard], initialCheckpoint: original)
        let e = StorageFixture.edition(), c = StorageFixture.card(), s = StorageFixture.segment(e, [c])
        XCTAssertThrowsError(try store.createInitialEdition(e, firstSegment: s, cards: [c], initialCheckpoint: checkpoint(e, c))) {
            XCTAssertEqual($0 as? SessionStoreError, .checkpointAlreadyExists)
        }
        try assertAbsent(db, e, s, c)
        XCTAssertEqual(try SessionStore(database: db).checkpoint(), original)
        XCTAssertEqual(try store.edition(id: old.id), old)
        XCTAssertEqual(try store.segments(editionID: old.id), [oldSegment])
        XCTAssertEqual(try store.card(id: oldCard.id), oldCard)
    }
    func testP5NormalCreateDoesNotSaveSession() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let e = StorageFixture.edition(), c = StorageFixture.card(), s = StorageFixture.segment(e, [c])
        try store.createEdition(e, firstSegment: s, cards: [c])
        XCTAssertEqual(try store.edition(id: e.id), e)
        XCTAssertEqual(try store.segments(editionID: e.id), [s])
        XCTAssertEqual(try store.card(id: c.id), c)
        XCTAssertNil(try SessionStore(database: db).checkpoint())
    }
    func testP6WrongCheckpointEditionWritesNothing() throws {
        let db = try StorageFixture.database(self), e = StorageFixture.edition(), c = StorageFixture.card()
        let s = StorageFixture.segment(e, [c])
        XCTAssertThrowsError(try PublicationStore(database: db).createInitialEdition(e, firstSegment: s, cards: [c], initialCheckpoint: checkpoint(StorageFixture.edition(), c))) {
            XCTAssertEqual($0 as? PublicationStoreError, .invalidInitialCheckpoint)
        }
        try assertAbsent(db, e, s, c)
        XCTAssertNil(try SessionStore(database: db).checkpoint())
    }
}
