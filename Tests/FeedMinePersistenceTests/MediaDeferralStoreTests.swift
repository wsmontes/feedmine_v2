import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class MediaDeferralStoreTests: XCTestCase {
    private func location() -> RuntimeDatabaseLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return .init(directory: root)
    }

    private func database() throws -> RuntimeDatabase {
        try RuntimeDatabase(location: location())
    }

    private func admit(_ db: RuntimeDatabase, edition: FeedEditionID, n: Int) throws -> MediaDeferralRecord {
        let origin = OriginRecordID()
        let revision = OriginRevision(id: OriginRevisionID(), originRecordID: origin,
            externalVersionIdentity: nil, headline: "Story \(n)", summary: nil, bodyText: nil,
            authoredAt: nil, modifiedAt: nil, observedAt: Date(timeIntervalSince1970: Double(n)),
            language: nil, primaryLink: nil, searchProjection: nil, providerID: nil)
        try ContentStore(database: db).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .init(rawValue: "test"), namespace: "deferrals",
                value: origin.rawValue.uuidString, role: .object), revision: revision, mediaCandidates: [],
            availability: .available, observedAt: revision.observedAt, expectedCurrent: .none,
            currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: revision.observedAt)]))
        return .init(editionID: edition, originRecordID: origin, originRevisionID: revision.id)
    }

    func testReadyOldRevisionRemainsReachableUnderContinuousFullPagesOfNewSkips() throws {
        let db = try database(), edition = FeedEditionID(), store = MediaDeferralStore(database: db)
        let old = try (0..<32).map { try admit(db, edition: edition, n: $0) }
        try store.record(old, at: Date(timeIntervalSince1970: 100))
        _ = try store.page(editionID: edition, limit: 32, offerAt: Date(timeIntervalSince1970: 101))
        var found = Set<OriginRevisionID>()
        for round in 0..<4 {
            let incoming = try (0..<32).map { try admit(db, edition: edition, n: 1000 + round * 32 + $0) }
            let now = Date(timeIntervalSince1970: Double(102 + round))
            try store.record(incoming, at: now)
            let page = try store.page(editionID: edition, limit: 32, offerAt: now)
            found.formUnion(page.map(\.originRevisionID))
        }
        XCTAssertTrue(Set(old.map(\.originRevisionID)).isSubset(of: found),
            "an older ready revision cannot starve behind a full page of new pending skips forever")
    }

    func testReturningToEditionARetainsItsRevisionAfterEditionBDefersTheSameStory() throws {
        let db = try database(), a = FeedEditionID(), b = FeedEditionID()
        let store = MediaDeferralStore(database: db)
        let x = try admit(db, edition: a, n: 1)
        let bx = MediaDeferralRecord(editionID: b, originRecordID: x.originRecordID,
            originRevisionID: x.originRevisionID)
        try store.record([x], at: Date(timeIntervalSince1970: 1))
        try store.record([bx], at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(try store.page(editionID: a, limit: 32, offerAt: nil).map(\.originRevisionID),
            [x.originRevisionID], "returning A must retain X, not merely a page count")
        XCTAssertEqual(try store.page(editionID: b, limit: 32, offerAt: nil).map(\.originRevisionID),
            [x.originRevisionID])
        try store.forget([bx])
        XCTAssertEqual(try store.page(editionID: a, limit: 32, offerAt: nil).map(\.originRevisionID),
            [x.originRevisionID], "settling B must not consume A's eligibility")
    }
    func testScopedPageUsesIndexAmongTenThousandOtherEditionAssociations() throws {
        let db = try database(), edition = FeedEditionID(), store = MediaDeferralStore(database: db)
        let x = try admit(db, edition: edition, n: 1)
        try store.record([x], at: Date(timeIntervalSince1970: 1))
        try db.write { sql in
            for n in 1...10_000 {
                try sql.execute(sql: """
                    INSERT INTO selection_supply_media_deferrals VALUES (?, ?, ?, ?)
                    """, arguments: [UUID().uuidString.lowercased(),
                        x.originRecordID.rawValue.uuidString.lowercased(),
                        x.originRevisionID.rawValue.uuidString.lowercased(), n])
            }
        }
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(try store.page(editionID: edition, limit: 32, offerAt: nil), [x])
        let plan = try db.read { sql in
            try Row.fetchAll(sql, sql: """
                EXPLAIN QUERY PLAN SELECT origin_record_id, origin_revision_id
                FROM selection_supply_media_deferrals WHERE edition_id = ?
                ORDER BY turn_at, origin_record_id LIMIT 32
                """, arguments: [edition.rawValue.uuidString.lowercased()]).map { $0["detail"] as String }
        }
        print("MEDIA_DEFERRAL_SCALE rows=10001 page_seconds=\(ProcessInfo.processInfo.systemUptime - started) plan=\(plan)")
    }

    /// A database that applied the committed v1 shape (columns on `selection_supply`) must keep every stored
    /// deferral when v2 adds the association table. The test removes only the v2 table and its bookkeeping row, so
    /// the reopened database runs the real additive migration against real legacy columns.
    func testLegacyColumnDeferralSurvivesV2MigrationAndReopen() throws {
        let location = location(), edition = FeedEditionID()
        let db = try RuntimeDatabase(location: location)
        let x = try admit(db, edition: edition, n: 7)
        try db.write { sql in
            try sql.execute(sql: "DROP TABLE IF EXISTS selection_supply_media_deferrals")
            try sql.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'selection-supply-media-deferral-v2'")
            try sql.execute(sql: """
                UPDATE selection_supply SET media_deferred_edition_id = ?, media_deferred_at = 100,
                    media_offered_at = NULL WHERE origin_record_id = ?
                """, arguments: [edition.rawValue.uuidString.lowercased(),
                    x.originRecordID.rawValue.uuidString.lowercased()])
        }
        // The legacy-era build wrote columns only; the current build must not require a fresh registration.
        let reopened = MediaDeferralStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.page(editionID: edition, limit: 32, offerAt: nil), [x],
            "a persisted v1-column deferral must survive the v2 migration, not be re-derived from memory")
        XCTAssertEqual(try reopened.count(editionID: edition), 1)
    }

    /// A -> B -> A across a process boundary: both Editions keep their own association, and closing the database
    /// between the writes cannot turn either one into a page-of-one-memory.
    func testEditionRoundTripAndReopenKeepBothAssociations() throws {
        let location = location(), a = FeedEditionID(), b = FeedEditionID()
        let db = try RuntimeDatabase(location: location)
        let x = try admit(db, edition: a, n: 1)
        let bx = MediaDeferralRecord(editionID: b, originRecordID: x.originRecordID,
            originRevisionID: x.originRevisionID)
        try MediaDeferralStore(database: db).record([x, bx], at: Date(timeIntervalSince1970: 1))

        let reopened = MediaDeferralStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.page(editionID: a, limit: 32, offerAt: nil), [x],
            "returning to A after B deferred the same story keeps A's record on disk")
        XCTAssertEqual(try reopened.page(editionID: b, limit: 32, offerAt: nil).map(\.originRevisionID),
            [x.originRevisionID])
        try reopened.forget([bx])
        let after = MediaDeferralStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try after.page(editionID: a, limit: 32, offerAt: nil), [x],
            "settling B must not consume A's eligibility")
        XCTAssertEqual(try after.page(editionID: b, limit: 32, offerAt: nil), [])
    }

    /// More pending stories than one in-memory ceiling (32): the page rotates instead of evicting, and reopening
    /// the process still finds all of them.
    func testMoreThanOnePageOfPendingStoriesRotatesAndSurvivesReopen() throws {
        let location = location(), edition = FeedEditionID()
        let db = try RuntimeDatabase(location: location), store = MediaDeferralStore(database: db)
        let records = try (0..<40).map { try admit(db, edition: edition, n: $0) }
        try store.record(records, at: Date(timeIntervalSince1970: 1))
        let first = try store.page(editionID: edition, limit: 32, offerAt: Date(timeIntervalSince1970: 2))
        let second = try store.page(editionID: edition, limit: 32, offerAt: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(Set((first + second).map(\.originRevisionID)).count, 40,
            "a full page cannot evict the rows behind it; every deferral is offered eventually")
        let reopened = MediaDeferralStore(database: try RuntimeDatabase(location: location))
        XCTAssertEqual(try reopened.count(editionID: edition), 40)
        XCTAssertEqual(try reopened.page(editionID: edition, limit: 32, offerAt: nil).count, 32)
    }
}
