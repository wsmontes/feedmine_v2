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

    func testAppendRejectsPersistedMalformedTailAtomically() throws {
        for tail in ["0.5", "'malformed'"] {
            let db = try StorageFixture.database(self)
            let store = PublicationStore(database: db)
            let edition = StorageFixture.edition()
            let a = StorageFixture.card(), b = StorageFixture.card(), c = StorageFixture.card()
            try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [a]), cards: [a])
            try store.appendSegment(StorageFixture.segment(edition, [b], ordinal: 1), cards: [b])
            try db.write { try $0.execute(sql: "UPDATE feed_segments SET ordinal = " + tail + " WHERE ordinal = 1") }
            XCTAssertThrowsError(try store.tail(editionID: edition.id)) { error in
                guard case PublicationStoreError.corruption = error else { return XCTFail("Expected tail corruption: \(error)") }
            }
            let ordinal: UInt64 = 1
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

    func testTailProgressionSurvivesCloseAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let edition = StorageFixture.edition()
        do {
            let database = try RuntimeDatabase(location: location), store = PublicationStore(database: database)
            let first = StorageFixture.card()
            try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [first]), cards: [first])
            XCTAssertEqual(try store.tail(editionID: edition.id), .init(ordinal: 0))
            for ordinal in UInt64(1)...2 {
                let card = StorageFixture.card()
                try store.appendSegment(StorageFixture.segment(edition, [card], ordinal: ordinal), cards: [card])
                XCTAssertEqual(try store.tail(editionID: edition.id), .init(ordinal: ordinal))
            }
        }
        let reopened = PublicationStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.tail(editionID: edition.id), .init(ordinal: 2))
    }

    func testStaleTailAppendRefusesWithoutRenumberingOrPersistingCard() throws {
        let store = PublicationStore(database: try StorageFixture.database(self))
        let edition = StorageFixture.edition(), first = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [first]), cards: [first])
        let observedTail = try store.tail(editionID: edition.id)
        XCTAssertEqual(observedTail.ordinal, 0)
        let winner = StorageFixture.card(), stale = StorageFixture.card()
        let winnerSegment = StorageFixture.segment(edition, [winner], ordinal: observedTail.ordinal + 1)
        let staleSegment = StorageFixture.segment(edition, [stale], ordinal: observedTail.ordinal + 1)
        try store.appendSegment(winnerSegment, cards: [winner])
        XCTAssertThrowsError(try store.appendSegment(staleSegment, cards: [stale])) {
            XCTAssertEqual($0 as? PublicationStoreError, .invalidAppendOrdinal)
        }
        XCTAssertNil(try store.card(id: stale.id))
        XCTAssertEqual(try store.card(id: winner.id), winner)
        XCTAssertEqual(try store.segments(editionID: edition.id).last, winnerSegment)
        XCTAssertEqual(try store.segments(editionID: edition.id).count, 2)
        XCTAssertEqual(try store.tail(editionID: edition.id).ordinal, 1)
    }

    func testHistoricalGapIsAuditedBySegmentsRatherThanHotAppend() throws {
        let database = try StorageFixture.database(self), store = PublicationStore(database: database)
        let edition = StorageFixture.edition(), a = StorageFixture.card(), b = StorageFixture.card(), c = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [a]), cards: [a])
        try store.appendSegment(StorageFixture.segment(edition, [b], ordinal: 1), cards: [b])
        try database.write { try $0.execute(sql: "UPDATE feed_segments SET ordinal = 2 WHERE ordinal = 1") }
        XCTAssertEqual(try store.tail(editionID: edition.id).ordinal, 2)
        // Deliberate invariant: append validates the real tail, not arbitrary past gaps.
        try store.appendSegment(StorageFixture.segment(edition, [c], ordinal: 3), cards: [c])
        XCTAssertEqual(try store.card(id: c.id), c)
        XCTAssertThrowsError(try store.segments(editionID: edition.id)) {
            guard case PublicationStoreError.corruption = $0 else { return XCTFail("Expected historical corruption: \($0)") }
        }
    }

    func testTailAndAppendRejectInvalidTailSchemaEmptyEditionAndOverflow() throws {
        let database = try StorageFixture.database(self), store = PublicationStore(database: database)
        XCTAssertThrowsError(try store.tail(editionID: FeedEditionID())) {
            XCTAssertEqual($0 as? PublicationStoreError, .missingEdition)
        }
        let edition = StorageFixture.edition(), first = StorageFixture.card(), next = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [first]), cards: [first])
        try database.write { try $0.execute(sql: "UPDATE feed_segments SET publication_schema_version = 2") }
        for operation in [
            { _ = try store.tail(editionID: edition.id) },
            { try store.appendSegment(StorageFixture.segment(edition, [next], ordinal: 1), cards: [next]) }
        ] {
            XCTAssertThrowsError(try operation()) {
                guard case PublicationStoreError.corruption = $0 else { return XCTFail("Expected schema corruption: \($0)") }
            }
        }
        XCTAssertNil(try store.card(id: next.id))
        try database.write { try $0.execute(sql: "UPDATE feed_segments SET publication_schema_version = 1, ordinal = ?", arguments: [Int64.max]) }
        XCTAssertEqual(try store.tail(editionID: edition.id).ordinal, UInt64(Int64.max))
        XCTAssertThrowsError(try store.appendSegment(StorageFixture.segment(edition, [next], ordinal: UInt64(Int64.max) + 1), cards: [next])) {
            XCTAssertEqual($0 as? PublicationStoreError, .invalidAppendOrdinal)
        }
        try database.write { db in
            try db.execute(sql: "DELETE FROM published_cards")
            try db.execute(sql: "DELETE FROM feed_segments")
        }
        XCTAssertThrowsError(try store.tail(editionID: edition.id)) {
            XCTAssertEqual($0 as? PublicationStoreError, .corruption("empty edition"))
        }
        XCTAssertThrowsError(try store.appendSegment(StorageFixture.segment(edition, [next], ordinal: 0), cards: [next])) {
            XCTAssertEqual($0 as? PublicationStoreError, .corruption("empty edition"))
        }
    }

    func testTailQueryUsesExistingEditionOrdinalIndexWithoutTemporaryOrder() throws {
        let database = try StorageFixture.database(self), store = PublicationStore(database: database)
        let edition = StorageFixture.edition(), card = StorageFixture.card()
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, [card]), cards: [card])
        try database.read { db in
            let indexes = try Row.fetchAll(db, sql: "PRAGMA index_list('feed_segments')")
            var matchingIndexes: [String] = []
            for index in indexes where (index["unique"] as Int) == 1 {
                let name: String = index["name"]
                let fields = try Row.fetchAll(db, sql: "SELECT name FROM pragma_index_info(?) ORDER BY seqno", arguments: [name])
                    .map { $0["name"] as String }
                if fields == ["edition_id", "ordinal"] { matchingIndexes.append(name) }
            }
            XCTAssertFalse(matchingIndexes.isEmpty)
            let details = try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN SELECT ordinal, publication_schema_version FROM feed_segments
                WHERE edition_id = ? ORDER BY ordinal DESC LIMIT 1
                """, arguments: [edition.id.rawValue.uuidString.lowercased()]).map { $0["detail"] as String }
            XCTAssertTrue(details.contains { detail in matchingIndexes.contains { detail.contains($0) } }, "\(details)")
            XCTAssertFalse(details.contains { $0.uppercased().contains("TEMP B-TREE") }, "\(details)")
        }
    }

}


extension PublicationStoreTests {
    private func revisedCard(_ original: PublicationStore.CardRecord) -> PublicationStore.CardRecord {
        .init(id: PublicationCardID(), originRecordID: original.originRecordID, originRevisionID: OriginRevisionID(),
            sourceID: nil,providerID: nil,sourceDisplayName: "New enrichment",providerDisplayName: nil,
            contentEntityID: nil,contentClusterID: nil,title: "New revision",primaryText: nil,
            timestampValue: nil,timestampKind: nil,mediaKey: nil,mediaPixelWidth: nil,mediaPixelHeight: nil,
            mediaMimeType: nil,renderLayout: "textOnly",renderMediaAspectRatio: nil,primaryActionKind: nil,primaryActionReference: nil)
    }

    func test3R5InitialAndAtomicInitialRejectDuplicateOriginsWithoutAnyWrites() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let edition = StorageFixture.edition(), first = StorageFixture.card(), duplicate = revisedCard(first)
        let cards = [first,duplicate], segment = StorageFixture.segment(edition,cards)
        XCTAssertThrowsError(try store.createEdition(edition,firstSegment: segment,cards: cards)) {
            XCTAssertEqual($0 as? PublicationStoreError,.duplicateOriginInEdition)
        }
        XCTAssertThrowsError(try store.createInitialEdition(edition,firstSegment: segment,cards: cards,
            initialCheckpoint: .init(editionID: edition.id,cardID: first.id,anchorPlacement: "top",updatedAt: Date()))) {
            XCTAssertEqual($0 as? PublicationStoreError,.duplicateOriginInEdition)
        }
        XCTAssertNil(try store.edition(id: edition.id)); XCTAssertNil(try store.card(id: first.id))
        XCTAssertNil(try SessionStore(database: db).checkpoint())
        try store.createInitialEdition(edition,firstSegment: StorageFixture.segment(edition,[first]),cards: [first],
            initialCheckpoint: .init(editionID: edition.id,cardID: first.id,anchorPlacement: "top",updatedAt: Date()))
        XCTAssertEqual(try SessionStore(database: db).checkpoint()?.cardID,first.id)
    }

    func test3R5BothAppendPathsRejectEntireMixedSegmentPreserveTailCheckpointAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = RuntimeDatabaseLocation(directory: root)
        let edition = StorageFixture.edition(), original = StorageFixture.card(), duplicate = revisedCard(original), fresh = StorageFixture.card()
        let checkpoint = SessionStore.CheckpointRecord(editionID: edition.id,cardID: original.id,anchorPlacement: "center",updatedAt: Date(timeIntervalSince1970: 500))
        do {
            let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db)
            try store.createInitialEdition(edition,firstSegment: StorageFixture.segment(edition,[original]),cards: [original],initialCheckpoint: checkpoint)
            let mixed = StorageFixture.segment(edition,[fresh,duplicate],ordinal: 1)
            XCTAssertThrowsError(try store.appendSegment(mixed,cards: [fresh,duplicate])) { XCTAssertEqual($0 as? PublicationStoreError,.duplicateOriginInEdition) }
            XCTAssertThrowsError(try store.appendSegment(mixed,cards: [fresh,duplicate],expectingTailCardID: original.id)) { XCTAssertEqual($0 as? PublicationStoreError,.duplicateOriginInEdition) }
            XCTAssertThrowsError(try store.appendSegment(mixed,cards: [fresh,duplicate],expectingTailCardID: PublicationCardID())) { XCTAssertEqual($0 as? PublicationStoreError,.staleHistoryExpectation) }
            XCTAssertNil(try store.card(id: fresh.id)); XCTAssertNil(try store.card(id: duplicate.id))
            XCTAssertEqual(try store.tail(editionID: edition.id).ordinal,0)
            XCTAssertEqual(try SessionStore(database: db).checkpoint(),checkpoint)
            let repeatedFresh = revisedCard(fresh)
            XCTAssertThrowsError(try store.appendSegment(StorageFixture.segment(edition,[fresh,repeatedFresh],ordinal: 1),cards: [fresh,repeatedFresh])) { XCTAssertEqual($0 as? PublicationStoreError,.duplicateOriginInEdition) }
            try store.appendSegment(StorageFixture.segment(edition,[fresh],ordinal: 1),cards: [fresh],expectingTailCardID: original.id)
        }
        let db = try RuntimeDatabase(location: location), store = PublicationStore(database: db)
        XCTAssertEqual(try store.card(id: original.id),original)
        XCTAssertEqual(try store.tail(editionID: edition.id).ordinal,1)
        XCTAssertEqual(try SessionStore(database: db).checkpoint(),checkpoint)
        XCTAssertEqual(try store.exposure(editionID: edition.id,originIDs: [duplicate.originRecordID]).publishedOriginIDs,[original.originRecordID])
        let other = StorageFixture.edition()
        try store.createEdition(other,firstSegment: StorageFixture.segment(other,[duplicate]),cards: [duplicate])
        XCTAssertEqual(try store.segments(editionID: other.id).flatMap(\.cardIDs),[duplicate.id])
    }
}
