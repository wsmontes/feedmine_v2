import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class PublicationRunwayStoreTests: XCTestCase {
    /// Remove only the authorized additive column when comparing prior SQL definitions.
    /// Every other byte of each existing schema object's definition remains checked.
    /// T6 rebuilt `context_checkpoints` and expanded `feed_editions`; those two definitions are compared by
    /// their columns, never by their SQL text, in both before/after sets.
    static func normalizeRebuiltDefinitions(_ entries: [String]) -> Set<String> {
        Set(entries.map { entry in
            // reader_preferences also gained columns in T6 (the filter expiry record).
            for name in ["context_checkpoints", "feed_editions", "reader_preferences"]
                where entry.hasPrefix(name + ":") { return name }
            return entry
        })
    }

    private static func schemaBeforeAvailability(_ schema: [String], in db: Database) throws -> Set<String> {
        let addition = ", availability_observed_at REAL"
        let origin = try XCTUnwrap(schema.first { $0.hasPrefix("origin_records:") })
        XCTAssertEqual(origin.components(separatedBy: addition).count, 2)
        let column = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT type, \"notnull\", dflt_value, pk FROM pragma_table_info('origin_records') WHERE name = 'availability_observed_at'"))
        XCTAssertEqual(column["type"] as String, "REAL")
        XCTAssertEqual(column["notnull"] as Int, 0)
        XCTAssertNil(column["dflt_value"] as String?)
        XCTAssertEqual(column["pk"] as Int, 0)
        // T6 rebuilt context_checkpoints to key it by the context identity; its definition is checked by
        // columns, and its SQL text is not part of this comparison.
        let checkpoints = try XCTUnwrap(schema.first { $0.hasPrefix("context_checkpoints:") })
        XCTAssertEqual(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('context_checkpoints') ORDER BY cid"),
            ["context_identity", "context_key", "context_key_json", "edition_id", "card_id", "anchor_placement", "updated_at"])
        XCTAssertEqual(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('feed_editions') ORDER BY cid").suffix(2),
            ["context_identity", "context_key_json"])
        return Set(Self.normalizeRebuiltDefinitions(schema).map { entry in
            entry == origin ? entry.replacingOccurrences(of: addition, with: "") : entry
        })
    }

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
        XCTAssertThrowsError(try store.exposure(editionID: FeedEditionID(), originIDs: []).publishedOriginIDs) { XCTAssertEqual($0 as? PublicationStoreError, .missingEdition) }
        XCTAssertThrowsError(try store.readyAhead(editionID: FeedEditionID(), anchorCardID: c[0].id, probeBound: 1)) { XCTAssertEqual($0 as? PublicationStoreError, .missingEdition) }
    }

    func testExposureUsesExactOriginAndEdition() throws {
        let (_, store, edition, cards) = try fixture()
        let other = StorageFixture.edition(), foreign = StorageFixture.card()
        try store.createEdition(other, firstSegment: StorageFixture.segment(other,[foreign]), cards:[foreign])
        let request = [cards[0].originRecordID, foreign.originRecordID, OriginRecordID()]
        XCTAssertEqual(try store.exposure(editionID:edition.id,originIDs:request).publishedOriginIDs,[cards[0].originRecordID])
        XCTAssertEqual(try store.exposure(editionID:other.id,originIDs:request).publishedOriginIDs,[foreign.originRecordID])
        XCTAssertTrue(try store.exposure(editionID:edition.id,originIDs:[]).publishedOriginIDs.isEmpty)
    }

    func testNewRevisionOfPublishedOriginRemainsExposed() throws {
        let (_, store, edition, cards) = try fixture()
        XCTAssertEqual(try store.exposure(editionID:edition.id,originIDs:[cards[0].originRecordID]).publishedOriginIDs,[cards[0].originRecordID])
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
        XCTAssertEqual(try store.exposure(editionID: edition.id, originIDs: [all[0].originRecordID, OriginRecordID(), all[9999].originRecordID]).publishedOriginIDs, [all[0].originRecordID,all[9999].originRecordID])
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
        XCTAssertEqual(try store.exposure(editionID: edition.id, originIDs: [card.originRecordID]).publishedOriginIDs, [card.originRecordID])
        XCTAssertFalse(RuntimeMigrations.current.eraseDatabaseOnSchemaChange)
        try migrated.read { db in
            let schema = try String.fetchAll(db, sql: "SELECT name || ':' || COALESCE(sql, '') FROM sqlite_master WHERE name != 'published_cards_origin_revision_segment' ORDER BY name")
            XCTAssertTrue(Self.normalizeRebuiltDefinitions(oldSchema).isSubset(of: try Self.schemaBeforeAvailability(schema, in: db))) // Only the explicitly checked additive columns change an old definition.
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT name FROM pragma_index_info('published_cards_origin_revision_segment') ORDER BY seqno"), ["origin_revision_id","segment_id"])
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid"), ["runtime-foundation-v1","publication-restore-v1","canonical-supply-v1","canonical-media-candidates-v1","publication-exposure-index-v1","acquisition-target-authority-v1","publication-origin-exposure-index-v1","origin-availability-precedence-v1","acquisition-target-sources-v1","reader-contexts-v1","publication-reading-state-v1","publication-media-use-v1","reader-context-identity-v1","reader-filter-expiry-v1"])
        }
    }

    func testExposureTailIsObservedEvenForEmptyRequestAndOldFactsStayImmutable() throws {
        let (_,store,edition,c) = try fixture()
        let old = try store.exposure(editionID: edition.id,originIDs: [])
        XCTAssertEqual(old.observedTailCardID,c[5].id); XCTAssertEqual(old.publishedOriginIDs,[])
        let next = StorageFixture.card()
        try store.appendSegment(StorageFixture.segment(edition,[next],ordinal: 3),cards: [next],expectingTailCardID: c[5].id)
        XCTAssertEqual(old.observedTailCardID,c[5].id)
        XCTAssertEqual(try store.exposure(editionID: edition.id,originIDs: []).observedTailCardID,next.id)
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
        XCTAssertEqual(try store.exposure(editionID: edition.id,originIDs: []).observedTailCardID,winner.id)
    }

}

extension PublicationRunwayStoreTests {
    func test3R5MeasureOriginExposureOnExistingIndexes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        let location = RuntimeDatabaseLocation(directory: root)
        do {
            let pool = try DatabasePool(path: location.databaseURL.path)
            try RuntimeMigrations.current.migrate(pool,upTo: "acquisition-target-authority-v1")
        }
        // Existing test injection opens the real previous schema without applying later migrations.
        let database = try RuntimeDatabase(location: location,migrator: DatabaseMigrator())
        let store = PublicationStore(database: database)
        let edition = StorageFixture.edition()
        var first: OriginRecordID?, last: OriginRecordID?
        // The fixture is written with raw SQL: it is a *historical* schema, and the current store writes the
        // newest columns (T6 added the context identity to feed_editions). The subject here is the
        // origin-exposure index and its measurement, not which columns the writer knows.
        let fixture = (0..<100).map { ordinal -> (PublicationStore.SegmentRecord, [PublicationStore.CardRecord]) in
            let cards = (0..<100).map { _ in StorageFixture.card() }
            if first == nil { first = cards[0].originRecordID }
            last = cards.last!.originRecordID
            return (StorageFixture.segment(edition, cards, ordinal: UInt64(ordinal)), cards)
        }
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO feed_editions (id, editorial_revision_id, context_kind, catalog_generation,
                    user_selection_version, eligibility_policy_version, scoring_policy_version,
                    sequencing_policy_version, exposure_policy_version, selection_schema_version,
                    publication_schema_version, selection_seed, created_at)
                VALUES (?, ?, 'main', 1, 1, 2, 3, 4, 5, 6, 1, -1, 123.25)
                """, arguments: [edition.id.rawValue.uuidString.lowercased(),
                    edition.editorialRevision.id.rawValue.uuidString.lowercased()])
            for (segment, cards) in fixture {
                try db.execute(sql: """
                    INSERT INTO feed_segments (id, edition_id, ordinal, segment_seed,
                        publication_schema_version, created_at) VALUES (?, ?, ?, ?, 1, 124.5)
                    """, arguments: [segment.id.rawValue.uuidString.lowercased(),
                        edition.id.rawValue.uuidString.lowercased(), Int64(segment.ordinal), -1])
                for (index, card) in cards.enumerated() {
                    try db.execute(sql: """
                        INSERT INTO published_cards (id, segment_id, ordinal, origin_record_id, origin_revision_id,
                            render_layout) VALUES (?, ?, ?, ?, ?, 'textOnly')
                        """, arguments: [card.id.rawValue.uuidString.lowercased(),
                            segment.id.rawValue.uuidString.lowercased(), Int64(index),
                            card.originRecordID.rawValue.uuidString.lowercased(),
                            card.originRevisionID.rawValue.uuidString.lowercased()])
                }
            }
        }
        let ids = [first!, last!, OriginRecordID()].map { $0.rawValue.uuidString.lowercased() }
        let editionKey = edition.id.rawValue.uuidString.lowercased()
        let sql = """
                SELECT DISTINCT c.origin_record_id
                FROM feed_segments s JOIN published_cards c ON c.segment_id = s.id
                WHERE s.edition_id = ? AND c.origin_record_id IN (?, ?, ?)
                """
        let arguments = StatementArguments([editionKey] + ids)
        let before = try database.read { db in
            try Row.fetchAll(db,sql: "EXPLAIN QUERY PLAN " + sql,arguments: arguments).map { $0["detail"] as String }
        }
        let rowsBefore = try database.read { try String.fetchAll($0,sql: sql,arguments: arguments) }
        let cardsBefore = try store.segments(editionID: edition.id).flatMap { segment in
            try segment.cardIDs.map { try XCTUnwrap(store.card(id: $0)) }
        }
        let editionBefore = try store.edition(id: edition.id)
        let segmentsBefore = try store.segments(editionID: edition.id)
        // Historical schema fixture: the modern SessionStore also writes context_checkpoints.
        try database.write { db in
            try db.execute(sql: "INSERT INTO session_checkpoint VALUES (1, ?, ?, 'center', 1234)",
                arguments: [editionKey, cardsBefore[5000].id.rawValue.uuidString.lowercased()])
        }
        let checkpointBefore = try XCTUnwrap(SessionStore(database: database).checkpoint())
        let schemaBefore = try database.read { try String.fetchAll($0,sql: "SELECT name || ':' || COALESCE(sql,'') FROM sqlite_master ORDER BY name") }
        let upgraded = try RuntimeDatabase(location: location)
        let upgradedStore = PublicationStore(database: upgraded)
        XCTAssertEqual(try upgradedStore.edition(id: edition.id),editionBefore)
        XCTAssertEqual(try upgradedStore.segments(editionID: edition.id),segmentsBefore)
        XCTAssertEqual(try cardsBefore.map { try upgradedStore.card(id: $0.id) },cardsBefore.map(Optional.some))
        XCTAssertEqual(try SessionStore(database: upgraded).checkpoint(),checkpointBefore)
        try upgraded.read { db in
            let schemaAfter = try String.fetchAll(db,sql: "SELECT name || ':' || COALESCE(sql,'') FROM sqlite_master ORDER BY name")
            let priorDefinitions = try Self.schemaBeforeAvailability(schemaAfter, in: db)
            let normalizedBefore = Self.normalizeRebuiltDefinitions(schemaBefore)
            XCTAssertTrue(normalizedBefore.isSubset(of: priorDefinitions))
            // One new object (3R5 index), plus one altered existing definition (3R6B column).
            let originDefinition = try XCTUnwrap(schemaAfter.first { $0.hasPrefix("origin_records:") })
            let originIndex = "published_cards_origin_record_segment:CREATE INDEX published_cards_origin_record_segment\nON published_cards (origin_record_id, segment_id)"
            let authorityTable = """
                acquisition_target_sources:CREATE TABLE acquisition_target_sources (
                    target_id TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    generation INTEGER NOT NULL,
                    PRIMARY KEY (target_id, source_id),
                    FOREIGN KEY (target_id)
                        REFERENCES acquisition_targets(id)
                        ON DELETE CASCADE,
                    CHECK (generation >= 1)
                )
                """
            let authorityIndex = "sqlite_autoindex_acquisition_target_sources_1:"
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('acquisition_target_sources') ORDER BY cid"),["target_id","source_id","generation"])
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT name FROM pragma_index_info('sqlite_autoindex_acquisition_target_sources_1') ORDER BY seqno"),["target_id","source_id"])
            let addedNames = Set(["reader_preferences", "context_checkpoints", "sqlite_autoindex_context_checkpoints_1",
                "edition_reading_state", "sqlite_autoindex_edition_reading_state_1", "retired_published_cards", "retired_published_cards_id",
                "retired_feed_segments", "retired_feed_segments_id", "publication_card_usage", "sqlite_autoindex_publication_card_usage_1",
                "publication_bookmarks", "sqlite_autoindex_publication_bookmarks_1"])
            let contextual = Set(priorDefinitions.filter { addedNames.contains(String($0.split(separator: ":", maxSplits: 1)[0])) })
            XCTAssertEqual(contextual.count, addedNames.count)
            XCTAssertEqual(priorDefinitions.subtracting(normalizedBefore), Set([originIndex, authorityTable, authorityIndex]).union(contextual))
            XCTAssertEqual(Self.normalizeRebuiltDefinitions(schemaAfter).subtracting(normalizedBefore), Set([originIndex, originDefinition, authorityTable, authorityIndex]).union(contextual))
            XCTAssertEqual(try String.fetchAll(db,sql: "SELECT name FROM pragma_index_info('published_cards_origin_record_segment') ORDER BY seqno"),["origin_record_id","segment_id"])
            XCTAssertEqual(try Int.fetchOne(db,sql: "SELECT \"unique\" FROM pragma_index_list('published_cards') WHERE name='published_cards_origin_record_segment'"),0)
            let details = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN " + sql, arguments: arguments).map { $0["detail"] as String }
            let found = try String.fetchAll(db, sql: sql, arguments: arguments)
            XCTAssertEqual(Set(found), Set(ids.prefix(2)))
            XCTAssertEqual(Set(found),Set(rowsBefore))
            XCTAssertTrue(details.contains { $0.contains("published_cards_origin_record_segment (origin_record_id=?)") })
            XCTAssertFalse(before.contains { $0.contains("published_cards_origin_record_segment") })
            print("3R5 BEFORE: \(before)")
            print("3R5 AFTER: \(details)")
            let indexes = try Row.fetchAll(db, sql: "SELECT name, sql FROM sqlite_master WHERE type = 'index' AND tbl_name IN ('published_cards', 'feed_segments')")
                .map { "\($0["name"] as String): \($0["sql"] as String? ?? "autoindex")" }
            print("3R5 measurement: candidates=3 editionCards=10000 editionSegments=100 returnedOrigins=\(found.count)")
            print("3R5 origin query plan: \(details)")
            print("3R5 existing indexes: \(indexes)")
            // EXPLAIN bytecode shows where candidate identity is checked relative to the index traversal.
            let program = try Row.fetchAll(db, sql: "EXPLAIN " + sql, arguments: arguments)
            print("3R5 origin query bytecode: \(program.map { "\($0["addr"] as Int) \($0["opcode"] as String) \($0["p1"] as Int) \($0["p2"] as Int) \($0["p3"] as Int) \($0["p4"] as String? ?? "")" })")
        }
        let reopened = PublicationStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.segments(editionID: edition.id),segmentsBefore)
        XCTAssertEqual(try reopened.exposure(editionID: edition.id,originIDs: [first!,last!]).publishedOriginIDs,[first!,last!])
    }
}
