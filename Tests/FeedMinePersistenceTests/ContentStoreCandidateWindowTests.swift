import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class ContentStoreCandidateWindowTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_700_000_000)
    private let source = SourceID()

    private func withDatabase(_ body: (RuntimeDatabase, ContentStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        try body(database, ContentStore(database: database))
    }
    private func origin(_ number: Int) -> OriginRecordID {
        OriginRecordID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!)
    }
    @discardableResult
    private func insert(_ number: Int, into store: ContentStore, date: Date? = nil, source: SourceID? = nil,
        authored: Date? = nil, headline: String? = "", summary: String? = nil,
        provider: ProviderID? = nil, expected: ContentStore.CurrentRevisionExpectation = .none) throws -> OriginRevision {
        let revision = OriginRevision(id: OriginRevisionID(), originRecordID: origin(number), externalVersionIdentity: nil,
            headline: headline, summary: summary, bodyText: "body excluded", authoredAt: authored, modifiedAt: nil,
            observedAt: date ?? time, language: "pt-BR", primaryLink: URL(string: "https://example.test/content")!,
            searchProjection: "search excluded", providerID: provider)
        try store.commitCanonicalChange(ContentStore.CanonicalChange(recordID: origin(number),
            externalObjectIdentity: ExternalIdentity(connectorKind: ConnectorKind(rawValue: "test"),
                namespace: "objects", value: String(number), role: .object),
            revision: revision, availability: .available, observedAt: time, expectedCurrent: expected,
            currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: source ?? self.source, kind: .direct, observedAt: time)]))
        return revision
    }
    private func window(_ store: ContentStore, capacity: Int, source: SourceID? = nil,
        after cursor: ContentStore.CandidateCursor? = nil,
        file: StaticString = #filePath, line: UInt = #line) throws -> ContentStore.CandidateWindow {
        let result = try store.candidateWindow(sourceID: source, after: cursor, examinedCapacity: capacity)
        XCTAssertLessThanOrEqual(result.records.count, result.examinedCount, file: file, line: line)
        XCTAssertLessThanOrEqual(result.examinedCount, capacity, file: file, line: line)
        XCTAssertEqual(result.exhausted, result.examinedCount < capacity, file: file, line: line)
        return result
    }
    private func assertCorruption(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            guard case ContentStoreError.corruption = $0 else { return XCTFail("Expected corruption: \($0)", file: file, line: line) }
        }
    }

    func testDescendingDatesAndKnownUUIDTies() throws {
        try withDatabase { _, store in
            try insert(1, into: store)
            try insert(3, into: store)
            try insert(2, into: store)
            try insert(4, into: store, date: time.addingTimeInterval(-10))
            try insert(5, into: store, date: time.addingTimeInterval(10))
            let result = try window(store, capacity: 6)
            XCTAssertEqual(result.records.map(\.originRecordID), [5, 3, 2, 1, 4].map(origin))
            XCTAssertEqual(result.examinedCount, 5)
            XCTAssertEqual(result.nextCursor, ContentStore.CandidateCursor(sortDate: time.addingTimeInterval(-10), originRecordID: origin(4)))
            XCTAssertTrue(result.exhausted)
        }
    }

    func testExclusiveKeysetHasNoDuplicatesOrMissingRowsAndPartialFinalBatch() throws {
        try withDatabase { _, store in
            for n in 1...5 { try insert(n, into: store) }
            let first = try window(store, capacity: 2)
            XCTAssertEqual(first.records.map(\.originRecordID), [5, 4].map(origin))
            XCTAssertEqual(first.nextCursor, ContentStore.CandidateCursor(sortDate: time, originRecordID: origin(4)))
            let second = try window(store, capacity: 2, after: first.nextCursor)
            XCTAssertEqual(second.records.map(\.originRecordID), [3, 2].map(origin))
            let third = try window(store, capacity: 2, after: second.nextCursor)
            XCTAssertEqual(third.records.map(\.originRecordID), [origin(1)])
            XCTAssertEqual(third.examinedCount, 1)
            XCTAssertTrue(third.exhausted)
            let all = (first.records + second.records + third.records).map(\.originRecordID)
            XCTAssertEqual(all, [5, 4, 3, 2, 1].map(origin))
            XCTAssertEqual(Set(all).count, 5)
        }
    }

    func testExactCapacityAtEndRequiresEmptyFollowupToConfirmExhaustion() throws {
        try withDatabase { _, store in
            try insert(1, into: store)
            try insert(2, into: store)
            let full = try window(store, capacity: 2)
            XCTAssertEqual(full.examinedCount, 2)
            XCTAssertFalse(full.exhausted)
            let empty = try window(store, capacity: 2, after: full.nextCursor)
            XCTAssertEqual(empty.records, [])
            XCTAssertEqual(empty.examinedCount, 0)
            XCTAssertNil(empty.nextCursor)
            XCTAssertTrue(empty.exhausted)
        }
    }

    func testSourceFilteringAfterBoundDoesNotRefillAndEmptyWindowsProgress() throws {
        try withDatabase { _, store in
            let requested = SourceID()
            for n in 1...6 { try insert(n, into: store, source: n <= 2 ? requested : source) }
            let first = try window(store, capacity: 2, source: requested)
            XCTAssertEqual(first.records, [])
            XCTAssertEqual(first.examinedCount, 2)
            XCTAssertFalse(first.exhausted)
            XCTAssertEqual(first.nextCursor, ContentStore.CandidateCursor(sortDate: time, originRecordID: origin(5)))
            let second = try window(store, capacity: 2, source: requested, after: first.nextCursor)
            XCTAssertEqual(second.records, [])
            XCTAssertEqual(second.examinedCount, 2)
            XCTAssertEqual(second.nextCursor, ContentStore.CandidateCursor(sortDate: time, originRecordID: origin(3)))
            XCTAssertNotEqual(second.nextCursor, first.nextCursor)
            let third = try window(store, capacity: 2, source: requested, after: second.nextCursor)
            XCTAssertEqual(third.records.map(\.originRecordID), [2, 1].map(origin))
            XCTAssertEqual(third.examinedCount, 2)
        }
    }

    func testCursorComesFromLastExaminedEvenWhenLastEligibleIsEarlier() throws {
        try withDatabase { _, store in
            let requested = SourceID()
            try insert(3, into: store, source: requested)
            try insert(2, into: store)
            try insert(1, into: store, source: requested)
            let first = try window(store, capacity: 2, source: requested)
            XCTAssertEqual(first.records.map(\.originRecordID), [origin(3)])
            XCTAssertEqual(first.examinedCount, 2)
            XCTAssertEqual(first.nextCursor, ContentStore.CandidateCursor(sortDate: time, originRecordID: origin(2)))
            let second = try window(store, capacity: 2, source: requested, after: first.nextCursor)
            XCTAssertEqual(second.records.map(\.originRecordID), [origin(1)])
            XCTAssertTrue(second.exhausted)
        }
    }

    func testInvalidCapacityAndNonfiniteCursorDates() throws {
        try withDatabase { _, store in
            for capacity in [0, -1] {
                XCTAssertThrowsError(try store.candidateWindow(sourceID: nil, after: nil, examinedCapacity: capacity)) {
                    XCTAssertEqual($0 as? ContentStoreError, .invalidCapacity)
                }
            }
            for value in [Double.infinity, -.infinity, .nan] {
                let cursor = ContentStore.CandidateCursor(sortDate: Date(timeIntervalSince1970: value), originRecordID: origin(1))
                XCTAssertThrowsError(try store.candidateWindow(sourceID: nil, after: cursor, examinedCapacity: 1)) {
                    XCTAssertEqual($0 as? ContentStoreError, .invalidRepresentation("cursor.sort_date"))
                }
            }
        }
    }

    func testCurrentOnlyNarrowPayloadAndAuthoredObservedBasis() throws {
        try withDatabase { database, store in
            let v1 = try insert(1, into: store, headline: "historical")
            let provider = ProviderID(), authored = time.addingTimeInterval(-50), observed = time.addingTimeInterval(20)
            let v2 = try insert(1, into: store, date: observed, authored: authored, headline: nil,
                summary: "summary é", provider: provider, expected: .revision(v1.id))
            let fallback = try insert(2, into: store, headline: "", summary: "")
            // These excluded fields would make a broad revision decode fail. Narrow
            // hydration must neither select nor interpret them.
            try database.write { db in
                try db.execute(sql: "UPDATE origin_revisions SET primary_link = 'https://example.test/a b', body_text = x'ff', search_projection = x'ff'")
            }
            let result = try window(store, capacity: 3)
            XCTAssertEqual(result.records.map(\.originRevisionID), [fallback.id, v2.id])
            let current = try XCTUnwrap(result.records.last)
            XCTAssertEqual(current.originRecordID, origin(1))
            XCTAssertEqual(current.sortDate, authored)
            XCTAssertEqual(current.sortDateBasis, .authored)
            XCTAssertNil(current.headline)
            XCTAssertEqual(current.summary, "summary é")
            XCTAssertEqual(current.authoredAt, authored)
            XCTAssertEqual(current.observedAt, observed)
            XCTAssertEqual(current.language, "pt-BR")
            XCTAssertEqual(current.providerID, provider)
            let other = try XCTUnwrap(result.records.first)
            XCTAssertEqual(other.sortDate, time)
            XCTAssertEqual(other.sortDateBasis, .observedFallback)
            XCTAssertNil(other.authoredAt)
            XCTAssertEqual(other.observedAt, time)
            XCTAssertEqual(other.headline, "")
            XCTAssertEqual(other.summary, "")
            XCTAssertNil(other.providerID)
        }
    }

    func testCorruptCurrentnessAndAvailabilityRejectedEvenForIneligibleSource() throws {
        try withDatabase { database, store in
            let v1 = try insert(1, into: store)
            let v2 = try insert(1, into: store, expected: .revision(v1.id))
            // Both revisions belong to this origin, so FK remains satisfied while
            // projection is stale and must be rejected by the read boundary.
            try database.write { db in
                try db.execute(sql: "UPDATE selection_supply SET origin_revision_id = ?", arguments: [v1.id.rawValue.uuidString.lowercased()])
            }
            assertCorruption { _ = try window(store, capacity: 1) }
            assertCorruption { _ = try window(store, capacity: 1, source: SourceID()) }
            try database.write { db in
                try db.execute(sql: "UPDATE selection_supply SET origin_revision_id = ?", arguments: [v2.id.rawValue.uuidString.lowercased()])
                try db.execute(sql: "UPDATE origin_records SET availability = 'removed'")
            }
            assertCorruption { _ = try window(store, capacity: 1) }
            try database.write { db in
                try db.execute(sql: "UPDATE origin_records SET availability = 'available', current_revision_id = NULL")
            }
            assertCorruption { _ = try window(store, capacity: 1) }
        }
    }

    func testMissingMembershipIsCorruptionButDifferentLegitimateSourceIsIneligible() throws {
        try withDatabase { database, store in
            try insert(1, into: store)
            let notMember = try window(store, capacity: 2, source: SourceID())
            XCTAssertEqual(notMember.records, [])
            XCTAssertEqual(notMember.examinedCount, 1)
            XCTAssertNotNil(notMember.nextCursor)
            XCTAssertTrue(notMember.exhausted)
            try database.write { db in try db.execute(sql: "DELETE FROM source_memberships") }
            assertCorruption { _ = try window(store, capacity: 2) }
        }
    }

    func testIneligibleRevisionPayloadIsNotHydratedAndMalformedEligiblePayloadThrows() throws {
        try withDatabase { database, store in
            try insert(1, into: store)
            try database.write { db in try db.execute(sql: "UPDATE origin_revisions SET provider_id = 'bad-uuid'") }
            let filtered = try window(store, capacity: 1, source: SourceID())
            XCTAssertEqual(filtered.records, [])
            XCTAssertEqual(filtered.examinedCount, 1)
            assertCorruption { _ = try window(store, capacity: 1) }
        }
    }
}
