import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

// Shared fixtures remain test-only and contain no storage behavior.
enum StorageFixture {
    static func database(_ test: XCTestCase) throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
    }
    static func revision(id: EditorialRevisionID = EditorialRevisionID(), policy: UInt64 = 1) -> EditorialRevision {
        EditorialRevision(id: id, contextKey: ContextKey(request: .main), catalogGeneration: CatalogGeneration(rawValue: 1),
            userSelectionVersion: PolicyVersion(rawValue: policy), eligibilityPolicyVersion: PolicyVersion(rawValue: 2),
            scoringPolicyVersion: PolicyVersion(rawValue: 3), sequencingPolicyVersion: PolicyVersion(rawValue: 4),
            exposurePolicyVersion: PolicyVersion(rawValue: 5), selectionSchemaVersion: SelectionSchemaVersion(rawValue: 6))
    }
    static func edition(revision: EditorialRevision? = nil, version: UInt64 = 1) -> PublicationStore.EditionRecord {
        .init(id: FeedEditionID(), editorialRevision: revision ?? self.revision(), publicationSchemaVersion: version,
            selectionSeed: UInt64.max, createdAt: Date(timeIntervalSince1970: 123.25))
    }
    static func card(id: PublicationCardID = PublicationCardID()) -> PublicationStore.CardRecord {
        .init(id: id, originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: "Frozen News", providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil,
            title: "", primaryText: " exact text ", timestampValue: nil, timestampKind: nil,
            mediaKey: " ", mediaPixelWidth: 300, mediaPixelHeight: 200, mediaMimeType: "image/test",
            renderLayout: "hero", renderMediaAspectRatio: 1.0, primaryActionKind: nil, primaryActionReference: nil)
    }
    static func segment(_ edition: PublicationStore.EditionRecord, _ cards: [PublicationStore.CardRecord], ordinal: UInt64 = 0, version: UInt64? = nil) -> PublicationStore.SegmentRecord {
        .init(id: FeedSegmentID(), editionID: edition.id, ordinal: ordinal, segmentSeed: UInt64.max,
            publicationSchemaVersion: version ?? edition.publicationSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 124.5), cardIDs: cards.map(\.id))
    }
}

final class PublicationStoreTests: XCTestCase {
    func testCreateAppendAndKeysetWindowsPreserveScalarsAndOrder() throws {
        let database = try StorageFixture.database(self)
        let store = PublicationStore(database: database)
        let edition = StorageFixture.edition()
        let cards = (0..<6).map { _ in StorageFixture.card() }
        let s0 = StorageFixture.segment(edition, Array(cards.prefix(3)))
        let s1 = StorageFixture.segment(edition, Array(cards.suffix(3)), ordinal: 1)
        try store.createEdition(edition, firstSegment: s0, cards: Array(cards.prefix(3)))
        try store.appendSegment(s1, cards: Array(cards.suffix(3)))
        XCTAssertEqual(try store.edition(id: edition.id), edition)
        XCTAssertEqual(try store.segments(editionID: edition.id), [s0, s1])
        XCTAssertEqual(try store.card(id: cards[0].id), cards[0])
        XCTAssertEqual(try store.cards(editionID: edition.id, around: cards[4].id, backwardCapacity: 2, forwardCapacity: 1), Array(cards[2...5]))
        XCTAssertEqual(try store.cards(editionID: edition.id, around: cards[4].id, backwardCapacity: 0, forwardCapacity: 0), [cards[4]])
        XCTAssertThrowsError(try store.cards(editionID: edition.id, around: cards[4].id, backwardCapacity: -1, forwardCapacity: 0))
        let raw = try database.read { try String.fetchOne($0, sql: "SELECT id FROM feed_editions") }
        XCTAssertEqual(raw, edition.id.rawValue.uuidString.lowercased())
        XCTAssertEqual(try database.read { try Int64.fetchOne($0, sql: "SELECT selection_seed FROM feed_editions") }, -1)
    }

    func testValidationRejectsInvalidOrdinalsSchemaEmptyAndCardOrder() throws {
        let database = try StorageFixture.database(self)
        let store = PublicationStore(database: database)
        let edition = StorageFixture.edition()
        let a = StorageFixture.card(), b = StorageFixture.card()
        XCTAssertThrowsError(try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [a], ordinal: 1), cards: [a]))
        XCTAssertNil(try store.edition(id: edition.id))
        XCTAssertThrowsError(try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, []), cards: []))
        XCTAssertThrowsError(try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [a,b]), cards: [b,a]))
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [a]), cards: [a])
        XCTAssertThrowsError(try store.appendSegment(StorageFixture.segment(edition, [b], ordinal: 3), cards: [b]))
        XCTAssertThrowsError(try store.appendSegment(StorageFixture.segment(edition, [b], ordinal: 1, version: 2), cards: [b]))
        XCTAssertThrowsError(try store.appendSegment(StorageFixture.segment(edition, [], ordinal: 1), cards: []))
        XCTAssertEqual(try store.segments(editionID: edition.id).count, 1)
    }

    func testRevisionIdentityConflictAndSharedRevisionAllowed() throws {
        let store = PublicationStore(database: try StorageFixture.database(self))
        let revision = StorageFixture.revision()
        let first = StorageFixture.edition(revision: revision)
        let second = StorageFixture.edition(revision: revision)
        let conflict = StorageFixture.edition(revision: StorageFixture.revision(id: revision.id, policy: 99))
        for edition in [first, second] {
            let card = StorageFixture.card()
            try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [card]), cards: [card])
        }
        let card = StorageFixture.card()
        XCTAssertThrowsError(try store.createEdition(conflict, firstSegment: StorageFixture.segment(conflict, [card]), cards: [card])) { error in
            XCTAssertEqual(error as? PublicationStoreError, .editorialRevisionConflict)
        }
        XCTAssertNil(try store.edition(id: conflict.id))
    }

    func testLateInsertFailureRollsBackInitialEditionAndAppend() throws {
        let store = PublicationStore(database: try StorageFixture.database(self))
        let existing = StorageFixture.edition()
        let collision = StorageFixture.card()
        try store.createEdition(existing, firstSegment: StorageFixture.segment(existing, [collision]), cards: [collision])
        let failed = StorageFixture.edition()
        let fresh = StorageFixture.card()
        XCTAssertThrowsError(try store.createEdition(failed, firstSegment: StorageFixture.segment(failed, [fresh, collision]), cards: [fresh, collision]))
        XCTAssertNil(try store.edition(id: failed.id))
        XCTAssertNil(try store.card(id: fresh.id))
        XCTAssertThrowsError(try store.appendSegment(StorageFixture.segment(existing, [fresh, collision], ordinal: 1), cards: [fresh, collision]))
        XCTAssertEqual(try store.segments(editionID: existing.id).count, 1)
        XCTAssertNil(try store.card(id: fresh.id))
    }

    func testCounterOverflowNonfiniteDatesAndNoncanonicalUUIDsFail() throws {
        let database = try StorageFixture.database(self)
        let store = PublicationStore(database: database)
        let card = StorageFixture.card()
        let oversized = StorageFixture.edition(version: UInt64(Int64.max) + 1)
        XCTAssertThrowsError(try store.createEdition(oversized, firstSegment: StorageFixture.segment(oversized, [card]), cards: [card]))
        let revisionOverflow = StorageFixture.edition(revision: StorageFixture.revision(policy: UInt64(Int64.max) + 1))
        XCTAssertThrowsError(try store.createEdition(revisionOverflow, firstSegment: StorageFixture.segment(revisionOverflow, [card]), cards: [card]))
        XCTAssertThrowsError(try PersistenceValueCoding.date(Date(timeIntervalSince1970: .infinity), field: "date"))
        let edition = StorageFixture.edition()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [card]), cards: [card])
        for malformed in [card.originRevisionID.rawValue.uuidString.uppercased(), "550e8400e29b41d4a716446655440000", "bad", " 550e8400-e29b-41d4-a716-446655440000"] {
            try database.write { try $0.execute(sql: "UPDATE published_cards SET origin_revision_id = ?", arguments: [malformed]) }
            XCTAssertThrowsError(try store.card(id: card.id))
        }
    }

    func testEncounteredOrdinalGapAndWrongEditionAnchorAreCorruption() throws {
        let database = try StorageFixture.database(self)
        let store = PublicationStore(database: database)
        let edition = StorageFixture.edition()
        let a = StorageFixture.card(), b = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [a,b]), cards: [a,b])
        XCTAssertThrowsError(try store.cards(editionID: FeedEditionID(), around: a.id, backwardCapacity: 1, forwardCapacity: 1))
        try database.write { try $0.execute(sql: "UPDATE published_cards SET ordinal = 3 WHERE id = ?", arguments: [b.id.rawValue.uuidString.lowercased()]) }
        XCTAssertThrowsError(try store.segments(editionID: edition.id))
        XCTAssertThrowsError(try store.cards(editionID: edition.id, around: a.id, backwardCapacity: 0, forwardCapacity: 1))
    }
    func testSQLAllowedNonfiniteRatioAndMalformedScalarReadAsCorruption() throws {
        let db = try StorageFixture.database(self)
        let store = PublicationStore(database: db)
        let edition = StorageFixture.edition()
        let card = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [card]), cards: [card])
        try db.write { try $0.execute(sql: "UPDATE published_cards SET render_media_aspect_ratio = 1e999") }
        XCTAssertThrowsError(try store.card(id: card.id)) { error in
            guard case PublicationStoreError.corruption = error else { return XCTFail("Expected corruption: \(error)") }
        }
        try db.write { try $0.execute(sql: "UPDATE feed_editions SET catalog_generation = 'not an integer'") }
        XCTAssertThrowsError(try store.edition(id: edition.id))
    }

    func testAppendRejectsPersistedFractionalTailAndSegmentGapAtomically() throws {
        for tail in ["0.5", "2"] {
            let db = try StorageFixture.database(self)
            let store = PublicationStore(database: db)
            let edition = StorageFixture.edition()
            let a = StorageFixture.card(), b = StorageFixture.card(), c = StorageFixture.card()
            try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [a]), cards: [a])
            try store.appendSegment(StorageFixture.segment(edition, [b], ordinal: 1), cards: [b])
            try db.write { try $0.execute(sql: "UPDATE feed_segments SET ordinal = " + tail + " WHERE ordinal = 1") }
            let ordinal: UInt64 = tail == "0.5" ? 1 : 3
            XCTAssertThrowsError(try store.appendSegment(StorageFixture.segment(edition, [c], ordinal: ordinal), cards: [c])) { error in
                guard case PublicationStoreError.corruption = error else { return XCTFail("Expected corruption: \(error)") }
            }
            XCTAssertNil(try store.card(id: c.id))
            XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM feed_segments") }, 2)
        }
    }

    func testRequestedWindowDetectsEmptyTrailingAndLeadingSegments() throws {
        for leading in [false, true] {
            let db = try StorageFixture.database(self)
            let store = PublicationStore(database: db)
            let edition = StorageFixture.edition()
            let a = StorageFixture.card(), b = StorageFixture.card()
            try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [a]), cards: [a])
            try store.appendSegment(StorageFixture.segment(edition, [b], ordinal: 1), cards: [b])
            let removed = leading ? a.id : b.id
            try db.write { try $0.execute(sql: "DELETE FROM published_cards WHERE id = ?", arguments: [removed.rawValue.uuidString.lowercased()]) }
            XCTAssertThrowsError(try store.cards(editionID: edition.id, around: leading ? b.id : a.id,
                backwardCapacity: leading ? 1 : 0, forwardCapacity: leading ? 0 : 1)) { error in
                guard case PublicationStoreError.corruption = error else { return XCTFail("Expected corruption: \(error)") }
            }
        }
    }

    func testLargestRepresentableCounterRoundTrips() throws {
        let store = PublicationStore(database: try StorageFixture.database(self))
        let edition = StorageFixture.edition(revision: StorageFixture.revision(policy: UInt64(Int64.max)), version: UInt64(Int64.max))
        let card = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [card]), cards: [card])
        XCTAssertEqual(try store.edition(id: edition.id), edition)
    }

}
