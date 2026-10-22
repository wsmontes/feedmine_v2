import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class MediaDeferralStoreTests: XCTestCase {
    private func database() throws -> RuntimeDatabase {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try RuntimeDatabase(location: .init(directory: root))
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
}
