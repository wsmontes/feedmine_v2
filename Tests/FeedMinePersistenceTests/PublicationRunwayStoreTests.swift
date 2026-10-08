import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class PublicationRunwayStoreTests: XCTestCase {
    private func fixture() throws -> (RuntimeDatabase, PublicationStore, PublicationStore.EditionRecord, [PublicationStore.CardRecord]) {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let edition = StorageFixture.edition(), cards = (0..<6).map { _ in StorageFixture.card() }
        try store.createEdition(edition, firstSegment: StorageFixture.segment(edition, Array(cards[0..<2])), cards: Array(cards[0..<2]))
        try store.appendSegment(StorageFixture.segment(edition, Array(cards[2..<4]), ordinal: 1), cards: Array(cards[2..<4]))
        try store.appendSegment(StorageFixture.segment(edition, Array(cards[4..<6]), ordinal: 2), cards: Array(cards[4..<6]))
        return (db, store, edition, cards)
    }

    func testReadyAheadExcludesAnchorAndUsesWitnessAcrossSegments() throws {
        let (_, store, edition, cards) = try fixture()
        for (anchor, bound, expected) in [(5, 1, PublicationStore.ProbeCountRecord.exact(0)), (4, 1, .exact(1)), (1, 4, .exact(4)), (1, 2, .atLeast(2)), (0, 20, .exact(5))] {
            let result = try store.readyAhead(editionID: edition.id, anchorCardID: cards[anchor].id, probeBound: bound)
            XCTAssertEqual(result.editionID, edition.id)
            XCTAssertEqual(result.anchorCardID, cards[anchor].id)
            XCTAssertEqual(result.observedTailCardID, cards[5].id)
            XCTAssertEqual(result.amount, expected)
        }
    }

    func testAppendProducesNewSnapshotWithoutChangingOldFact() throws {
        let (_, store, edition, cards) = try fixture()
        let old = try store.readyAhead(editionID: edition.id, anchorCardID: cards[4].id, probeBound: 10)
        let next = StorageFixture.card()
        try store.appendSegment(StorageFixture.segment(edition, [next], ordinal: 3), cards: [next])
        let fresh = try store.readyAhead(editionID: edition.id, anchorCardID: cards[4].id, probeBound: 10)
        XCTAssertEqual(old.amount, .exact(1)); XCTAssertEqual(old.observedTailCardID, cards[5].id)
        XCTAssertEqual(fresh.amount, .exact(2)); XCTAssertEqual(fresh.observedTailCardID, next.id)
        XCTAssertEqual(fresh.anchorCardID, old.anchorCardID)
    }

    func testForwardDirectionAndBoundedExactDistance() throws {
        let (_, store, edition, c) = try fixture()
        for (from, to, bound, expected) in [(2, 2, 1, PublicationStore.ForwardAdvanceRecord.same), (4, 1, 1, .backward), (0, 1, 1, .forwardExact(1)), (1, 2, 1, .forwardExact(1)), (0, 5, 5, .forwardExact(5)), (0, 5, 2, .forwardBeyondProbe(2)), (0, 5, 10, .forwardExact(5))] {
            XCTAssertEqual(try store.forwardAdvance(editionID: edition.id, fromCardID: c[from].id, toCardID: c[to].id, probeBound: bound), expected)
        }
    }

    func testInvalidBoundsMembershipAndMissingEditionAreErrors() throws {
        let (_, store, edition, c) = try fixture()
        for bound in [-1, 0, Int.max] {
            XCTAssertThrowsError(try store.readyAhead(editionID: edition.id, anchorCardID: c[0].id, probeBound: bound)) { XCTAssertEqual($0 as? PublicationStoreError, .invalidCapacity) }
            XCTAssertThrowsError(try store.forwardAdvance(editionID: edition.id, fromCardID: c[0].id, toCardID: c[1].id, probeBound: bound)) { XCTAssertEqual($0 as? PublicationStoreError, .invalidCapacity) }
        }
        let other = StorageFixture.edition(), foreign = StorageFixture.card()
        try store.createEdition(other, firstSegment: StorageFixture.segment(other, [foreign]), cards: [foreign])
        for id in [foreign.id, PublicationCardID()] {
            XCTAssertThrowsError(try store.readyAhead(editionID: edition.id, anchorCardID: id, probeBound: 1)) { guard case .corruption = $0 as? PublicationStoreError else { return XCTFail("\($0)") } }
            XCTAssertThrowsError(try store.forwardAdvance(editionID: edition.id, fromCardID: c[0].id, toCardID: id, probeBound: 1))
            XCTAssertThrowsError(try store.forwardAdvance(editionID: edition.id, fromCardID: id, toCardID: c[0].id, probeBound: 1))
        }
        XCTAssertThrowsError(try store.exposure(editionID: FeedEditionID(), revisionIDs: []).publishedRevisionIDs) { XCTAssertEqual($0 as? PublicationStoreError, .missingEdition) }
        XCTAssertThrowsError(try store.readyAhead(editionID: FeedEditionID(), anchorCardID: c[0].id, probeBound: 1)) { XCTAssertEqual($0 as? PublicationStoreError, .missingEdition) }
    }

    func testExposureUsesExactRevisionAndEditionAndAllowsRepeatedOccurrences() throws {
        let (db, store, edition, c) = try fixture()
        let r1 = c[0].originRevisionID, r2 = OriginRevisionID(), r3 = c[2].originRevisionID
        let other = StorageFixture.edition(revision: edition.editorialRevision), card = StorageFixture.card()
        try store.createEdition(other, firstSegment: StorageFixture.segment(other, [card]), cards: [card])
        // Same origin record, different revision; and repeated explicit R1 occurrence.
        try db.write { db in
            try db.execute(sql: "UPDATE published_cards SET origin_record_id = ? WHERE id = ?", arguments: [c[0].originRecordID.rawValue.uuidString.lowercased(), c[1].id.rawValue.uuidString.lowercased()])
            try db.execute(sql: "UPDATE published_cards SET origin_revision_id = ? WHERE id IN (?, ?)", arguments: [r1.rawValue.uuidString.lowercased(), c[5].id.rawValue.uuidString.lowercased(), card.id.rawValue.uuidString.lowercased()])
        }
        XCTAssertEqual(try store.exposure(editionID: edition.id, revisionIDs: [r1,r2,r3,r1]).publishedRevisionIDs, [r1,r3])
        XCTAssertEqual(try store.exposure(editionID: other.id, revisionIDs: [r1,r2,r3]).publishedRevisionIDs, [r1])
        XCTAssertEqual(try store.exposure(editionID: edition.id, revisionIDs: []).publishedRevisionIDs, [])
        XCTAssertEqual(try store.exposure(editionID: edition.id, revisionIDs: [c[0].originRevisionID, c[1].originRevisionID]).publishedRevisionIDs, [c[0].originRevisionID,c[1].originRevisionID])
    }

    func testUnpublishedNewRevisionOfSameOriginIsNotSuppressedByOldRevision() throws {
        let (_, store, edition, cards) = try fixture()
        let old = cards[0]
        let new = PublicationStore.CardRecord(id: PublicationCardID(), originRecordID: old.originRecordID,
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil,
            title: nil, primaryText: nil, timestampValue: nil, timestampKind: nil,
            mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil, mediaMimeType: nil,
            renderLayout: "textOnly", renderMediaAspectRatio: nil, primaryActionKind: nil, primaryActionReference: nil)
        XCTAssertEqual(new.originRecordID, old.originRecordID)
        XCTAssertEqual(try store.exposure(editionID: edition.id,
            revisionIDs: [old.originRevisionID, new.originRevisionID]).publishedRevisionIDs, [old.originRevisionID])
    }

    func testReadyOnlyValidatesAnchorAndTailSchemaRatherThanAuditingOldSegments() throws {
        let (db, store, edition, c) = try fixture()
        try db.write { try $0.execute(sql: "UPDATE feed_segments SET publication_schema_version = 99 WHERE ordinal = 0") }
        XCTAssertEqual(try store.readyAhead(editionID: edition.id, anchorCardID: c[4].id, probeBound: 2).amount, .exact(1))
        XCTAssertThrowsError(try store.readyAhead(editionID: edition.id, anchorCardID: c[0].id, probeBound: 2))
        try db.write { try $0.execute(sql: "UPDATE feed_segments SET publication_schema_version = 99 WHERE ordinal = 2") }
        XCTAssertThrowsError(try store.readyAhead(editionID: edition.id, anchorCardID: c[2].id, probeBound: 2))
    }
    func testLargeHistoryUsesOrderingRangeSeeksAndRevisionProbesWithoutTemporarySort() throws {
        let db = try StorageFixture.database(self), store = PublicationStore(database: db)
        let edition = StorageFixture.edition()
        var all: [PublicationStore.CardRecord] = []
        // 10,000 retained occurrences, 100 independently ordered segments; no timing SLA.
        for ordinal in 0..<100 {
            let cards = (0..<100).map { _ in StorageFixture.card() }
            let segment = StorageFixture.segment(edition, cards, ordinal: UInt64(ordinal))
            if ordinal == 0 { try store.createEdition(edition, firstSegment: segment, cards: cards) }
            else { try store.appendSegment(segment, cards: cards) }
            all.append(contentsOf: cards)
        }
        XCTAssertEqual(try store.readyAhead(editionID: edition.id, anchorCardID: all[98].id, probeBound: 3).amount, .atLeast(3))
        XCTAssertEqual(try store.readyAhead(editionID: edition.id, anchorCardID: all[9998].id, probeBound: 3).amount, .exact(1))
        XCTAssertEqual(try store.forwardAdvance(editionID: edition.id, fromCardID: all[20].id, toCardID: all[30].id, probeBound: 10), .forwardExact(10))
        XCTAssertEqual(try store.forwardAdvance(editionID: edition.id, fromCardID: all[98].id, toCardID: all[102].id, probeBound: 4), .forwardExact(4))
        XCTAssertEqual(try store.forwardAdvance(editionID: edition.id, fromCardID: all[98].id, toCardID: all[9999].id, probeBound: 3), .forwardBeyondProbe(3))
        XCTAssertEqual(try store.exposure(editionID: edition.id, revisionIDs: [all[0].originRevisionID, OriginRevisionID(), all[9999].originRevisionID]).publishedRevisionIDs, [all[0].originRevisionID,all[9999].originRevisionID])
        try db.read { db in
            func indexes(_ table: String, _ fields: [String]) throws -> [String] {
                var names: [String] = []
                for row in try Row.fetchAll(db, sql: "SELECT name FROM pragma_index_list(?)", arguments: [table]) {
                    let name: String = row["name"]
                    let columns = try String.fetchAll(db, sql: "SELECT name FROM pragma_index_info(?) ORDER BY seqno", arguments: [name])
                    if columns == fields { names.append(name) }
                }
                return names
            }
            let cardIndexes = try indexes("published_cards", ["segment_id","ordinal"])
            let segmentIndexes = try indexes("feed_segments", ["edition_id","ordinal"])
            XCTAssertFalse(cardIndexes.isEmpty); XCTAssertFalse(segmentIndexes.isEmpty)
            XCTAssertEqual(try indexes("published_cards", ["origin_revision_id","segment_id"]), ["published_cards_origin_revision_segment"])
            // Same SQL shapes used by the production per-segment bounded probe and tail read.
            let cases: [(String, StatementArguments, [String])] = [
                ("SELECT id, ordinal FROM published_cards WHERE segment_id = ? AND ordinal > ? AND ordinal <= ? ORDER BY ordinal ASC LIMIT ?", ["segment",98,Int64.max,4], cardIndexes),
                ("SELECT id, ordinal FROM feed_segments WHERE edition_id = ? AND ordinal > ? AND ordinal <= ? ORDER BY ordinal ASC LIMIT 1", ["edition",0,99], segmentIndexes),
                ("SELECT id, ordinal, publication_schema_version FROM feed_segments WHERE edition_id = ? ORDER BY ordinal DESC LIMIT 1", ["edition"], segmentIndexes),
                ("SELECT id, ordinal FROM published_cards WHERE segment_id = ? ORDER BY ordinal DESC LIMIT 1", ["segment"], cardIndexes),
                ("SELECT 1 FROM published_cards c INDEXED BY published_cards_origin_revision_segment JOIN feed_segments s ON s.id = c.segment_id WHERE c.origin_revision_id = ? AND s.edition_id = ? LIMIT 1", ["revision","edition"], ["published_cards_origin_revision_segment"])
            ]
            for (sql, arguments, names) in cases {
                let details = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + sql, arguments: arguments).map { $0["detail"] as String }
                XCTAssertTrue(details.contains { d in names.contains { d.contains($0) } }, "\(details)")
                XCTAssertFalse(details.contains { $0.uppercased().contains("TEMP B-TREE") || $0.uppercased().contains("SCAN PUBLISHED_CARDS") || $0.uppercased().hasPrefix("SCAN C ") }, "\(details)")
                if sql.contains("c.origin_revision_id") {
                    XCTAssertTrue(details.contains { $0.contains("origin_revision_id=?") }, "\(details)")
                    XCTAssertTrue(details.contains { $0.contains("SEARCH s") && $0.contains("id=?") }, "\(details)")
                }
                print("3K1 query plan: \(details)")
            }
        }
    }

    func testMigrationPreservesBaseDataAndAddsOnlyTheNarrowIndex() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let loc = RuntimeDatabaseLocation(directory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let edition = StorageFixture.edition(), card = StorageFixture.card(), segment = StorageFixture.segment(StorageFixture.edition(), [])
        let eid = edition.id.rawValue.uuidString.lowercased(), sid = segment.id.rawValue.uuidString.lowercased()
        let cid = card.id.rawValue.uuidString.lowercased(), rid = card.originRevisionID.rawValue.uuidString.lowercased()
        let oldSchema: [String]
        do {
            let pool = try DatabasePool(path: loc.databaseURL.path)
            try RuntimeMigrations.current.migrate(pool, upTo: "canonical-media-candidates-v1")
            oldSchema = try pool.read { db in
                let fields = try String.fetchAll(db, sql: "SELECT name FROM pragma_index_info('published_cards_origin_revision_segment') ORDER BY seqno")
                XCTAssertEqual(fields, [])
                let details = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN SELECT 1 FROM published_cards c JOIN feed_segments s ON s.id = c.segment_id WHERE c.origin_revision_id = ? AND s.edition_id = ? LIMIT 1", arguments: [rid,eid]).map { $0["detail"] as String }
                XCTAssertFalse(details.contains { $0.contains("origin_revision_id=?") })
                print("3K1 pre-index GRDB SQLite plan: \(details)")
                return try String.fetchAll(db, sql: "SELECT name || ':' || COALESCE(sql, '') FROM sqlite_master ORDER BY name")
            }
            try pool.write { db in
                try db.execute(sql: """
                    INSERT INTO feed_editions (id, editorial_revision_id, context_kind, catalog_generation,
                        user_selection_version, eligibility_policy_version, scoring_policy_version,
                        sequencing_policy_version, exposure_policy_version, selection_schema_version,
                        publication_schema_version, selection_seed, created_at)
                    VALUES (?, ?, 'main', 1, 1, 2, 3, 4, 5, 6, 1, -1, 123.25)
                    """, arguments: [eid, edition.editorialRevision.id.rawValue.uuidString.lowercased()])
                try db.execute(sql: "INSERT INTO feed_segments (id,edition_id,ordinal,segment_seed,publication_schema_version,created_at) VALUES (?,?,0,-1,1,124.5)", arguments: [sid,eid])
                try db.execute(sql: "INSERT INTO published_cards (id,segment_id,ordinal,origin_record_id,origin_revision_id,render_layout) VALUES (?,?,0,?,?,'textOnly')", arguments: [cid,sid,card.originRecordID.rawValue.uuidString.lowercased(),rid])
                try db.execute(sql: "INSERT INTO session_checkpoint VALUES (1,?,?,'center',125.5)", arguments: [eid,cid])
            }
        }
        let migrated = try RuntimeDatabase(location: loc), store = PublicationStore(database: migrated)
        XCTAssertEqual(try store.edition(id: edition.id), edition)
        XCTAssertEqual(try XCTUnwrap(store.card(id: card.id)).originRevisionID, card.originRevisionID)
        XCTAssertEqual(try SessionStore(database: migrated).checkpoint()?.cardID, card.id)
        XCTAssertEqual(try store.readyAhead(editionID: edition.id, anchorCardID: card.id, probeBound: 1).amount, .exact(0))
        XCTAssertEqual(try store.exposure(editionID: edition.id, revisionIDs: [card.originRevisionID]).publishedRevisionIDs, [card.originRevisionID])
        XCTAssertFalse(RuntimeMigrations.current.eraseDatabaseOnSchemaChange)
        try migrated.read { db in
            let schema = try String.fetchAll(db, sql: "SELECT name || ':' || COALESCE(sql, '') FROM sqlite_master WHERE name != 'published_cards_origin_revision_segment' ORDER BY name")
            XCTAssertEqual(schema, oldSchema) // Every old table, column, trigger and index definition unchanged.
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT name FROM pragma_index_info('published_cards_origin_revision_segment') ORDER BY seqno"), ["origin_revision_id","segment_id"])
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"), ["runtime-foundation-v1","publication-restore-v1","canonical-supply-v1","canonical-media-candidates-v1","publication-exposure-index-v1"])
        }
    }

    func testExposureTailIsObservedEvenForEmptyRequestAndOldFactsStayImmutable() throws {
        let (_,store,edition,c) = try fixture()
        let old = try store.exposure(editionID: edition.id,revisionIDs: [])
        XCTAssertEqual(old.observedTailCardID,c[5].id); XCTAssertEqual(old.publishedRevisionIDs,[])
        let next = StorageFixture.card()
        try store.appendSegment(StorageFixture.segment(edition,[next],ordinal: 3),cards: [next],expectingTailCardID: c[5].id)
        XCTAssertEqual(old.observedTailCardID,c[5].id)
        XCTAssertEqual(try store.exposure(editionID: edition.id,revisionIDs: []).observedTailCardID,next.id)
    }

    func testExpectedTailStaleRefusesBeforeOrdinalAcceptanceAndLeavesWinnerIntact() throws {
        let (_,store,edition,c) = try fixture()
        let winner = StorageFixture.card(), stale = StorageFixture.card()
        try store.appendSegment(StorageFixture.segment(edition,[winner],ordinal: 3),cards: [winner])
        let incoming = StorageFixture.segment(edition,[stale],ordinal: 4)
        XCTAssertThrowsError(try store.appendSegment(incoming,cards: [stale],expectingTailCardID: c[5].id)) { XCTAssertEqual($0 as? PublicationStoreError,.staleHistoryExpectation) }
        XCTAssertNil(try store.card(id: stale.id))
        XCTAssertFalse(try store.segments(editionID: edition.id).contains { $0.id == incoming.id })
        XCTAssertEqual(try store.card(id: winner.id),winner)
        XCTAssertEqual(try store.exposure(editionID: edition.id,revisionIDs: []).observedTailCardID,winner.id)
    }

}
