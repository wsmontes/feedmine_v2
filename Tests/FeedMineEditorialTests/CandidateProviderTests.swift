import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial

final class CandidateProviderTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_700_000_000)

    private func withProvider(_ body: (ContentStore, CandidateProvider) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        let store = ContentStore(database: database)
        try body(store, CandidateProvider(contentStore: store))
    }
    private func origin(_ number: Int) -> OriginRecordID {
        OriginRecordID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!)
    }
    private func plan(_ request: FeedContextRequest, policy: UInt64 = 1) throws -> FeedPlan {
        let context = FeedContext(request: request)
        let version = PolicyVersion(rawValue: policy)
        return try XCTUnwrap(FeedPlan(context: context, revision: EditorialRevision(id: EditorialRevisionID(),
            contextKey: context.key, catalogGeneration: CatalogGeneration(rawValue: 1),
            userSelectionVersion: version, eligibilityPolicyVersion: version, scoringPolicyVersion: version,
            sequencingPolicyVersion: version, exposurePolicyVersion: version,
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))))
    }
    @discardableResult
    private func insert(_ number: Int, source: SourceID, into store: ContentStore,
        authored: Date? = nil, observed: Date? = nil, headline: String? = "", summary: String? = nil,
        language: String? = nil, provider: ProviderID? = nil) throws -> OriginRevision {
        let revision = OriginRevision(id: OriginRevisionID(), originRecordID: origin(number), externalVersionIdentity: nil,
            headline: headline, summary: summary, bodyText: "not a candidate field", authoredAt: authored,
            modifiedAt: nil, observedAt: observed ?? time, language: language,
            primaryLink: URL(string: "https://example.test/item")!, searchProjection: "not a candidate field", providerID: provider)
        try store.commitCanonicalChange(ContentStore.CanonicalChange(recordID: origin(number),
            externalObjectIdentity: ExternalIdentity(connectorKind: ConnectorKind(rawValue: "test"),
                namespace: "objects", value: String(number), role: .object), revision: revision, mediaCandidates: [],
            availability: .available, observedAt: time, expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: time)]))
        return revision
    }

    func testReadableProjectionPreservesCanonicalBytesIdentityMetadataAndWindow() throws {
        try withProvider { store, provider in
            let source = SourceID(), other = SourceID(), attribution = ProviderID()
            let raw = try insert(1, source: source, into: store, authored: time.addingTimeInterval(10),
                headline: "<em>Headline &amp; news</em>", summary: "<p>One</p><p>Two &amp; three</p>", language: "pt", provider: attribution)
            _ = try insert(2, source: other, into: store, headline: "plain  title", summary: "2 < 3\n next")
            let original = try store.candidateWindow(sourceID: nil, after: nil, examinedCapacity: 1)
            let projected = try provider.candidates(for: plan(.main), after: nil, examinedCapacity: 1)
            let candidate = try XCTUnwrap(projected.candidates.first)
            XCTAssertEqual(candidate.headline, "Headline & news"); XCTAssertEqual(candidate.summary, "One\n\nTwo & three")
            XCTAssertEqual(candidate.originRecordID, raw.originRecordID); XCTAssertEqual(candidate.originRevisionID, raw.id)
            XCTAssertEqual(candidate.timestamp, .init(value: time.addingTimeInterval(10), kind: .authored))
            XCTAssertEqual(candidate.language, "pt"); XCTAssertEqual(candidate.providerID, attribution)
            XCTAssertEqual(projected.examinedCount, original.examinedCount); XCTAssertEqual(projected.exhausted, original.exhausted)
            XCTAssertEqual(projected.nextCursor, original.nextCursor.map { .init(sortDate: $0.sortDate, originRecordID: $0.originRecordID) })
            XCTAssertEqual(try store.originRevision(id: raw.id), raw)
            let rest = try provider.candidates(for: plan(.main), after: projected.nextCursor, examinedCapacity: 2)
            XCTAssertEqual(rest.candidates.map(\.originRecordID), [origin(2)])
            XCTAssertEqual(rest.candidates.first?.headline, "plain  title"); XCTAssertEqual(rest.candidates.first?.summary, "2 < 3\n next")
            let filtered = try provider.candidates(for: plan(.source(source)), after: nil, examinedCapacity: 3)
            XCTAssertEqual(filtered.candidates.map(\.originRecordID), [raw.originRecordID])
        }
    }

    func testMainMapsIDsOptionalPayloadTimestampsAndWindowMetadata() throws {
        try withProvider { store, provider in
            let a = SourceID(), b = SourceID(), attribution = ProviderID()
            let authored = time.addingTimeInterval(20), observed = time.addingTimeInterval(100)
            let v1 = try insert(1, source: a, into: store, authored: authored, observed: observed,
                headline: nil, summary: "summary é", language: "pt-BR", provider: attribution)
            let v2 = try insert(2, source: b, into: store, headline: "", summary: "")
            let result = try provider.candidates(for: plan(.main), after: nil, examinedCapacity: 3)
            XCTAssertEqual(result.candidates, [
                Candidate(originRecordID: origin(1), originRevisionID: v1.id, headline: nil, summary: "summary é",
                    timestamp: CandidateTimestamp(value: authored, kind: .authored), language: "pt-BR", providerID: attribution, sourceIDs: [a], primaryLink: URL(string: "https://example.test/item")!),
                Candidate(originRecordID: origin(2), originRevisionID: v2.id, headline: "", summary: "",
                    timestamp: CandidateTimestamp(value: time, kind: .observed), language: nil, providerID: nil, sourceIDs: [b], primaryLink: URL(string: "https://example.test/item")!)])
            XCTAssertEqual(result.examinedCount, 2)
            XCTAssertEqual(result.nextCursor, CandidateSupplyCursor(sortDate: time, originRecordID: origin(2)))
            XCTAssertTrue(result.exhausted)
            // This baseline uses context only; versions are not executed as policy.
            XCTAssertEqual(try provider.candidates(for: plan(.main, policy: UInt64.max), after: nil, examinedCapacity: 3), result)
        }
    }

    func testSourceFilteringPreservesExaminedCountAndRelativeOrder() throws {
        try withProvider { store, provider in
            let a = SourceID(), b = SourceID()
            let v1 = try insert(1, source: a, into: store)
            try insert(2, source: b, into: store)
            let v3 = try insert(3, source: a, into: store)
            let result = try provider.candidates(for: plan(.source(a)), after: nil, examinedCapacity: 4)
            XCTAssertEqual(result.candidates.map(\.originRecordID), [origin(3), origin(1)])
            XCTAssertEqual(result.candidates.map(\.originRevisionID), [v3.id, v1.id])
            XCTAssertEqual(result.examinedCount, 3)
            XCTAssertEqual(result.nextCursor, CandidateSupplyCursor(sortDate: time, originRecordID: origin(1)))
            XCTAssertTrue(result.exhausted)
        }
    }

    func testSparseSourceDoesNotRefillAndEditorialCursorProgresses() throws {
        try withProvider { store, provider in
            let a = SourceID(), b = SourceID()
            for n in 1...4 { try insert(n, source: n <= 2 ? a : b, into: store) }
            let sourcePlan = try plan(.source(a))
            let first = try provider.candidates(for: sourcePlan, after: nil, examinedCapacity: 2)
            XCTAssertEqual(first.candidates, [])
            XCTAssertEqual(first.examinedCount, 2)
            XCTAssertFalse(first.exhausted)
            XCTAssertEqual(first.nextCursor, CandidateSupplyCursor(sortDate: time, originRecordID: origin(3)))
            let second = try provider.candidates(for: sourcePlan, after: first.nextCursor, examinedCapacity: 2)
            XCTAssertEqual(second.candidates.map(\.originRecordID), [origin(2), origin(1)])
            XCTAssertEqual(second.examinedCount, 2)
            XCTAssertEqual(second.nextCursor, CandidateSupplyCursor(sortDate: time, originRecordID: origin(1)))
            XCTAssertNotEqual(second.nextCursor, first.nextCursor)
            XCTAssertFalse(second.exhausted)
            let empty = try provider.candidates(for: sourcePlan, after: second.nextCursor, examinedCapacity: 2)
            XCTAssertEqual(empty.candidates, [])
            XCTAssertEqual(empty.examinedCount, 0)
            XCTAssertNil(empty.nextCursor)
            XCTAssertTrue(empty.exhausted)
        }
    }

    func testMainCursorIsExclusiveWithNoDuplicateOrMissingCandidate() throws {
        try withProvider { store, provider in
            let source = SourceID()
            for n in 1...5 { try insert(n, source: source, into: store, observed: time.addingTimeInterval(Double(n / 2))) }
            let main = try plan(.main)
            let first = try provider.candidates(for: main, after: nil, examinedCapacity: 2)
            XCTAssertEqual(first.candidates.map(\.originRecordID), [origin(5), origin(4)])
            XCTAssertEqual(first.nextCursor, CandidateSupplyCursor(sortDate: time.addingTimeInterval(2), originRecordID: origin(4)))
            let second = try provider.candidates(for: main, after: first.nextCursor, examinedCapacity: 2)
            let third = try provider.candidates(for: main, after: second.nextCursor, examinedCapacity: 2)
            let all = (first.candidates + second.candidates + third.candidates).map(\.originRecordID)
            XCTAssertEqual(all, [5, 4, 3, 2, 1].map(origin))
            XCTAssertEqual(Set(all).count, 5)
            XCTAssertEqual(third.examinedCount, 1)
            XCTAssertTrue(third.exhausted)
        }
    }

    func testLocalSearchReadsReadableTextAndPreservesBoundedCursor() throws {
        try withProvider { store, provider in
            let source = SourceID()
            try insert(1, source: source, into: store, headline: "<b>Café</b>")
            try insert(2, source: source, into: store, headline: "other")
            let search = try plan(.search(XCTUnwrap(SearchContext(query: " CAFE "))))
            let first = try provider.candidates(for: search, after: nil, examinedCapacity: 1)
            XCTAssertTrue(first.candidates.isEmpty)
            XCTAssertEqual(first.examinedCount, 1)
            XCTAssertFalse(first.exhausted)
            let second = try provider.candidates(for: search, after: first.nextCursor, examinedCapacity: 1)
            XCTAssertEqual(second.candidates.map(\.originRecordID), [origin(1)])
            let end = try provider.candidates(for: search, after: second.nextCursor, examinedCapacity: 1)
            XCTAssertTrue(end.exhausted)
            XCTAssertTrue(end.candidates.isEmpty)
            XCTAssertEqual(search.context.request, .search(SearchContext(query: " CAFE ")!))
        }
    }

    func testFactualPersistenceValidationErrorsPropagate() throws {
        try withProvider { _, provider in
            for request in [FeedContextRequest.main, .source(SourceID())] {
                for capacity in [0, -1] {
                    XCTAssertThrowsError(try provider.candidates(for: plan(request), after: nil, examinedCapacity: capacity)) {
                        XCTAssertEqual($0 as? ContentStoreError, .invalidCapacity)
                    }
                }
                let cursor = CandidateSupplyCursor(sortDate: Date(timeIntervalSince1970: .nan), originRecordID: origin(1))
                XCTAssertThrowsError(try provider.candidates(for: plan(request), after: cursor, examinedCapacity: 1)) {
                    XCTAssertEqual($0 as? ContentStoreError, .invalidRepresentation("cursor.sort_date"))
                }
            }
        }
    }
}
