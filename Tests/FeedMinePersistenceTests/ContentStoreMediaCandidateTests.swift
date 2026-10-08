import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class ContentStoreMediaCandidateTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_700_000_000)
    private func location() -> RuntimeDatabaseLocation {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RuntimeDatabaseLocation(directory: root)
    }
    private func revision(_ origin: OriginRecordID, id: OriginRevisionID = OriginRevisionID(),
        headline: String = "headline") -> OriginRevision {
        OriginRevision(id: id, originRecordID: origin, externalVersionIdentity: nil,
            headline: headline, summary: nil, bodyText: nil, authoredAt: nil, modifiedAt: nil,
            observedAt: time, language: nil, primaryLink: nil, searchProjection: nil, providerID: nil)
    }
    private func candidate(_ revision: OriginRevisionID, id: MediaCandidateID = MediaCandidateID(),
        url: String = "HTTPS://example.test/A%2fb?q=Upper#Fragment", mime: String? = " Image/PNG é ",
        width: Int? = 200, height: Int? = 100) -> MediaCandidate {
        MediaCandidate(id: id, originRevisionID: revision, role: .cardVisual, mediaClass: .image,
            remoteURL: URL(string: url)!, declaredMimeType: mime,
            declaredPixelWidth: width, declaredPixelHeight: height)!
    }
    private func change(_ revision: OriginRevision, _ media: [MediaCandidate],
        expected: ContentStore.CurrentRevisionExpectation = .none,
        availability: OriginAvailability = .available,
        mutations: [ContentStore.MembershipMutation] = []) -> ContentStore.CanonicalChange {
        .init(recordID: revision.originRecordID,
            externalObjectIdentity: ExternalIdentity(connectorKind: ConnectorKind(rawValue: "test"),
                namespace: "objects", value: revision.originRecordID.description, role: .object),
            revision: revision, mediaCandidates: media, availability: availability, observedAt: time,
            expectedCurrent: expected, currentUpdate: .useSuppliedRevision, membershipMutations: mutations)
    }
    private func assertError(_ expected: ContentStoreError, _ body: () throws -> Void,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? ContentStoreError, expected, file: file, line: line)
        }
    }
    private func rows(_ database: RuntimeDatabase, table: String) throws -> [[DatabaseValue]] {
        try database.read { try Row.fetchAll($0, sql: "SELECT * FROM \(table) ORDER BY 1").map { $0.map { $0.1 } } }
    }
    private func snapshot(_ database: RuntimeDatabase) throws -> [[[DatabaseValue]]] {
        try ["origin_records", "origin_revisions", "media_candidates", "source_memberships", "selection_supply"]
            .map { try rows(database, table: $0) }
    }
    private func failMediaInsert(_ database: RuntimeDatabase) throws {
        try database.write { try $0.execute(sql: """
            CREATE TRIGGER fail_media BEFORE INSERT ON media_candidates
            BEGIN SELECT RAISE(ABORT, 'test media insertion failure'); END
            """) }
    }
    private func assertStorageFailure(_ body: () throws -> Void) {
        XCTAssertThrowsError(try body()) {
            guard case let RuntimeDatabaseError.storage(code, message) = $0 else {
                return XCTFail("Expected storage failure, got \($0)")
            }
            XCTAssertEqual(code & 0xff, 19)
            XCTAssertTrue(message.contains("test media insertion failure"))
        }
    }

    func testOrderedAdmissionExactReplayAndReopen() throws {
        let location = location(), v1 = revision(OriginRecordID()), source = SourceID()
        let a = candidate(v1.id), b = candidate(v1.id, mime: "", width: nil, height: nil)
        do {
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            try store.commitCanonicalChange(change(v1, [a, b], mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
            XCTAssertEqual(try store.mediaCandidates(originRevisionID: v1.id), [a, b])
            let before = try snapshot(database)
            for _ in 0..<2 {
                try store.commitCanonicalChange(change(v1, [a, b], expected: .revision(v1.id)))
                XCTAssertEqual(try snapshot(database), before)
            }
            XCTAssertEqual(try rows(database, table: "origin_revisions").count, 1)
            XCTAssertEqual(try rows(database, table: "media_candidates").count, 2)
        }
        let store = ContentStore(database: try RuntimeDatabase(location: location))
        let restored = try XCTUnwrap(store.mediaCandidates(originRevisionID: v1.id))
        XCTAssertEqual(restored.map(\.id), [a.id, b.id])
        XCTAssertEqual(restored[0].remoteURL.absoluteString.utf8.map { $0 }, a.remoteURL.absoluteString.utf8.map { $0 })
        XCTAssertEqual(restored[0].declaredMimeType?.utf8.map { $0 }, a.declaredMimeType?.utf8.map { $0 })
        XCTAssertEqual(restored[1].declaredMimeType, "")
        XCTAssertNil(restored[1].declaredPixelWidth)
    }

    func testChangedFactsConflictBeforeCollectionComparisonAndRollback() throws {
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID()), a = candidate(v1.id), b = candidate(v1.id)
        try store.commitCanonicalChange(change(v1, [a, b]))
        let before = try snapshot(database)
        for altered in [candidate(v1.id, id: a.id, url: "https://example.test/other"),
            candidate(v1.id, id: a.id, mime: nil), candidate(v1.id, id: a.id, width: 400, height: 300)] {
            assertError(.mediaCandidateConflict(a.id)) {
                try store.commitCanonicalChange(change(v1, [altered], expected: .revision(v1.id), availability: .removed))
            }
            XCTAssertEqual(try snapshot(database), before)
        }
        let changedRevision = revision(v1.originRecordID, id: v1.id, headline: "different")
        assertError(.revisionConflict) {
            try store.commitCanonicalChange(change(changedRevision, [candidate(v1.id, id: a.id, mime: nil)], expected: .revision(v1.id)))
        }
        XCTAssertEqual(try snapshot(database), before)
    }

    func testCandidateIdentityCannotBeReboundToNewRevision() throws {
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID()), a = candidate(v1.id)
        try store.commitCanonicalChange(change(v1, [a]))
        let before = try snapshot(database), v2 = revision(v1.originRecordID)
        for url in [a.remoteURL.absoluteString, "https://example.test/different"] {
            assertError(.mediaCandidateConflict(a.id)) {
                try store.commitCanonicalChange(change(v2, [candidate(v2.id, id: a.id, url: url)], expected: .revision(v1.id)))
            }
            XCTAssertNil(try store.originRevision(id: v2.id))
            XCTAssertEqual(try snapshot(database), before)
        }
    }

    func testCollectionAdditionRemovalReplacementAndReorderAreConflicts() throws {
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID()), a = candidate(v1.id), b = candidate(v1.id), c = candidate(v1.id)
        try store.commitCanonicalChange(change(v1, [a, b]))
        let before = try snapshot(database)
        for media in [[a], [a, b, c], [b, a], [a, c], []] {
            assertError(.mediaCandidateCollectionConflict(v1.id)) {
                try store.commitCanonicalChange(change(v1, media, expected: .revision(v1.id)))
            }
            XCTAssertEqual(try snapshot(database), before)
        }
    }

    func testEmptyCollectionIsImmutableAndDistinctFromMissingRevision() throws {
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID())
        try store.commitCanonicalChange(change(v1, []))
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: v1.id), .some([]))
        try store.commitCanonicalChange(change(v1, [], expected: .revision(v1.id)))
        assertError(.mediaCandidateCollectionConflict(v1.id)) {
            try store.commitCanonicalChange(change(v1, [candidate(v1.id)], expected: .revision(v1.id)))
        }
        XCTAssertNil(try store.mediaCandidates(originRevisionID: OriginRevisionID()))
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: v1.id), [])
    }

    func testHistoricalReadNeverFollowsCurrentPointer() throws {
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID()), v2 = revision(v1.originRecordID)
        let a = candidate(v1.id), b = candidate(v2.id), c = candidate(v2.id)
        try store.commitCanonicalChange(change(v1, [a]))
        try store.commitCanonicalChange(change(v2, [b, c], expected: .revision(v1.id)))
        XCTAssertEqual(try store.currentRevision(originRecordID: v1.originRecordID)?.id, v2.id)
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: v1.id), [a])
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: v2.id), [b, c])
    }

    func testOwnershipAndDuplicateIDsAreRejectedBeforeWrites() throws {
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID()), a = candidate(v1.id)
        assertError(.invalidChange("media candidate revision")) {
            try store.commitCanonicalChange(change(v1, [candidate(OriginRevisionID())]))
        }
        assertError(.invalidChange("duplicate media candidate id")) {
            try store.commitCanonicalChange(change(v1, [a, a]))
        }
        for table in ["origin_records", "origin_revisions", "media_candidates", "source_memberships", "selection_supply"] {
            XCTAssertEqual(try rows(database, table: table).count, 0)
        }
    }

    func testNewOriginMediaFailureRollsBackEverythingAfterReopen() throws {
        let location = location(), v1 = revision(OriginRecordID()), source = SourceID()
        do {
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            try failMediaInsert(database)
            assertStorageFailure {
                try store.commitCanonicalChange(change(v1, [candidate(v1.id)], mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
            }
        }
        let reopened = try RuntimeDatabase(location: location)
        for table in ["origin_records", "origin_revisions", "media_candidates", "source_memberships", "selection_supply"] {
            XCTAssertEqual(try rows(reopened, table: table).count, 0)
        }
    }

    func testExistingOriginMediaFailurePreservesAllPriorFactsAfterReopen() throws {
        let location = location(), v1 = revision(OriginRecordID()), v2 = revision(v1.originRecordID), source = SourceID()
        let a = candidate(v1.id), b = candidate(v2.id)
        let before: [[[DatabaseValue]]]
        do {
            let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
            try store.commitCanonicalChange(change(v1, [a], mutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
            before = try snapshot(database)
            try failMediaInsert(database)
            assertStorageFailure {
                try store.commitCanonicalChange(change(v2, [b], expected: .revision(v1.id), availability: .removed, mutations: [.remove(sourceID: source)]))
            }
        }
        let reopened = try RuntimeDatabase(location: location), store = ContentStore(database: reopened)
        XCTAssertEqual(try snapshot(reopened), before)
        XCTAssertEqual(try store.currentRevision(originRecordID: v1.originRecordID)?.id, v1.id)
        XCTAssertNil(try store.originRevision(id: v2.id))
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: v1.id), [a])
    }

    func testReadRefusesMalformedIDsLocatorsAndOrdinalGaps() throws {
        for damage in ["id = 'broken'", "remote_locator = 'file:///tmp/image'", "ordinal = 1",
            "ordinal = 0.5", "declared_pixel_width = 1.5, declared_pixel_height = 2"] {
            let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
            let v1 = revision(OriginRecordID())
            try store.commitCanonicalChange(change(v1, [candidate(v1.id)]))
            try database.write { try $0.execute(sql: "UPDATE media_candidates SET \(damage)") }
            XCTAssertThrowsError(try store.mediaCandidates(originRevisionID: v1.id)) {
                guard case ContentStoreError.corruption = $0 else { return XCTFail("Expected corruption, got \($0)") }
            }
        }
        // Malformed revision owner is damaged in both parent and child, preserving the FK.
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID())
        try store.commitCanonicalChange(change(v1, [candidate(v1.id)]))
        try database.write { db in
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
            try db.execute(sql: "UPDATE origin_records SET current_revision_id = 'broken'")
            try db.execute(sql: "UPDATE origin_revisions SET id = 'broken'")
            try db.execute(sql: "UPDATE media_candidates SET origin_revision_id = 'broken'")
        }
        XCTAssertThrowsError(try store.currentRevision(originRecordID: v1.originRecordID)) {
            guard case ContentStoreError.corruption = $0 else { return XCTFail("Expected corruption, got \($0)") }
        }

    }

    func testExactMediaReadDoesNotDecodeUnrelatedRevisionPayload() throws {
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID()), a = candidate(v1.id)
        try store.commitCanonicalChange(change(v1, [a]))
        try database.write { try $0.execute(sql: "UPDATE origin_revisions SET primary_link = 'https://example.test/contains space'") }
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: v1.id), [a])
    }

    func testMalformedCandidateRevisionIdentityIsCorruptionNotARebindConflict() throws {
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID()), a = candidate(v1.id)
        try store.commitCanonicalChange(change(v1, [a]))
        try database.write { db in
            try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
            try db.execute(sql: "UPDATE origin_records SET current_revision_id = 'broken'")
            try db.execute(sql: "UPDATE origin_revisions SET id = 'broken'")
            try db.execute(sql: "UPDATE media_candidates SET origin_revision_id = 'broken'")
        }
        let v2 = revision(OriginRecordID())
        XCTAssertThrowsError(try store.commitCanonicalChange(change(v2, [candidate(v2.id, id: a.id)]))) {
            XCTAssertEqual($0 as? ContentStoreError, .corruption("origin_revision_id"))
        }
        XCTAssertNil(try store.originRecord(id: v2.originRecordID))
        XCTAssertNil(try store.originRevision(id: v2.id))
    }

    func testExactLocatorAndMIMEByteSemantics() throws {
        let database = try RuntimeDatabase(location: location()), store = ContentStore(database: database)
        let v1 = revision(OriginRecordID())
        let url = "https://example.test/%C3%A9", a = candidate(v1.id, url: url, mime: "é")
        try store.commitCanonicalChange(change(v1, [a]))
        for mime in [nil, "", "É", " é ", "e\u{301}"] as [String?] {
            assertError(.mediaCandidateConflict(a.id)) {
                try store.commitCanonicalChange(change(v1, [candidate(v1.id, id: a.id, url: url, mime: mime)], expected: .revision(v1.id)))
            }
        }
        for other in ["https://EXAMPLE.test/%C3%A9", "https://example.test/%c3%a9", "https://example.test/e%CC%81"] {
            assertError(.mediaCandidateConflict(a.id)) {
                try store.commitCanonicalChange(change(v1, [candidate(v1.id, id: a.id, url: other, mime: "é")], expected: .revision(v1.id)))
            }
        }
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: v1.id)?[0].declaredMimeType?.utf8.map { $0 }, [0xc3, 0xa9])
    }
}
