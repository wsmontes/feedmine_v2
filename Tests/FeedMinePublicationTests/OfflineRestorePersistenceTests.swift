import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication

final class OfflineRestorePersistenceTests: XCTestCase {
    func testExactFrozenHistoryAndCenterAnchorAfterDatabaseDeallocationAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let edition = RestoreFixture.edition()
        let originalCards = try (0..<6).map { try RestoreFixture.card(index: $0) }
        let s0 = try RestoreFixture.segment(edition, cards: Array(originalCards.prefix(3)), ordinal: 0)
        let s1 = try RestoreFixture.segment(edition, cards: Array(originalCards.suffix(3)), ordinal: 1)
        let cursor = SessionCursor(editionID: edition.id, anchor: FeedWindowAnchor(cardID: originalCards[4].id, placement: .center))
        weak var firstDatabase: RuntimeDatabase?
        do {
            let database = try RuntimeDatabase(location: location)
            firstDatabase = database
            let publication = PublicationStore(database: database)
            let session = SessionStore(database: database)
            let first = try PublicationPersistenceMapping.records(segment: s0, cards: Array(originalCards.prefix(3)))
            let second = try PublicationPersistenceMapping.records(segment: s1, cards: Array(originalCards.suffix(3)))
            try publication.createEdition(PublicationPersistenceMapping.record(edition), firstSegment: first.0, cards: first.1)
            try publication.appendSegment(second.0, cards: second.1)
            try session.saveCheckpoint(PublicationPersistenceMapping.checkpoint(cursor, updatedAt: Date(timeIntervalSince1970: 300)))
        }
        XCTAssertNil(firstDatabase)
        let reopened = try RuntimeDatabase(location: location)
        let publication = PublicationStore(database: reopened)
        let session = SessionStore(database: reopened)
        let checkpoint = try XCTUnwrap(session.checkpoint())
        let restoredEdition = try PublicationPersistenceMapping.edition(XCTUnwrap(publication.edition(id: checkpoint.editionID)))
        let restoredCursor = try PublicationPersistenceMapping.cursor(checkpoint)
        let records = try publication.cards(editionID: checkpoint.editionID, around: checkpoint.cardID, backwardCapacity: 4, forwardCapacity: 1)
        let restoredCards = try records.map(PublicationPersistenceMapping.card)
        XCTAssertEqual(restoredEdition, edition)
        XCTAssertEqual(restoredEdition.editorialRevision, edition.editorialRevision)
        XCTAssertEqual(restoredCursor, cursor)
        XCTAssertEqual(restoredCursor.anchor.placement, .center)
        XCTAssertEqual(restoredCards.map(\.id), originalCards.map(\.id))
        XCTAssertEqual(restoredCards, originalCards)
        XCTAssertEqual(try publication.segments(editionID: edition.id).map(\.cardIDs).flatMap { $0 }, originalCards.map(\.id))
        for table in ["sources", "providers", "catalog", "assets", "asset_versions"] {
            XCTAssertFalse(try reopened.read { try $0.tableExists(table) }, table)
        }
        // Canonical supply tables now exist by design (Phase 3A design, Phase 3B1 schema).
        // Offline restore remains independent of canonical content: the tables are present
        // but hold no rows, so this asserts emptiness rather than absence. Catalog/provider/
        // asset storage stays absent. Only Domain/Publication/Persistence participate;
        // no network layer or bytes.
        for table in ["origin_records", "origin_revisions"] {
            XCTAssertTrue(try reopened.read { try $0.tableExists(table) }, table)
            XCTAssertEqual(try reopened.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") }, 0, table)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(files.allSatisfy { $0 == "runtime.sqlite" || $0.hasPrefix("runtime.sqlite-") })
    }
}
