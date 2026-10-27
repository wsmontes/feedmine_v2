import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial

final class SourceExclusionSupplyTests: XCTestCase {
    private func plan(_ request: FeedContextRequest) throws -> FeedPlan {
        let context = FeedContext(request: request), version = PolicyVersion(rawValue: 1)
        return try XCTUnwrap(FeedPlan(context: context, revision: .init(id: EditorialRevisionID(),
            contextKey: context.key, catalogGeneration: .init(rawValue: 1), userSelectionVersion: version,
            eligibilityPolicyVersion: version, scoringPolicyVersion: version, sequencingPolicyVersion: version,
            exposurePolicyVersion: version, selectionSchemaVersion: .init(rawValue: 1))))
    }

    private func fixture() throws -> (ContentStore, CandidateProvider, SourceID, SourceID, OriginRecordID) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let store = ContentStore(database: try RuntimeDatabase(location: .init(directory: root)))
        let a = SourceID(), b = SourceID(), shared = OriginRecordID()
        for (origin, sources) in [(shared, [a, b]), (OriginRecordID(), [a])] {
            let time = Date(timeIntervalSince1970: 100)
            let revision = OriginRevision(id: OriginRevisionID(), originRecordID: origin,
                externalVersionIdentity: nil, headline: "<em>Shared news</em>", summary: "A &amp; B",
                bodyText: "Body", authoredAt: time, modifiedAt: nil, observedAt: time,
                language: "en", primaryLink: URL(string: "https://example.test/item"),
                searchProjection: nil, providerID: ProviderID())
            try store.commitCanonicalChange(.init(recordID: origin,
                externalObjectIdentity: .init(connectorKind: .syndication, namespace: "exclusions",
                    value: origin.rawValue.uuidString, role: .object), revision: revision,
                mediaCandidates: [], availability: .available, observedAt: time, expectedCurrent: .none,
                currentUpdate: .useSuppliedRevision,
                membershipMutations: sources.map { .upsert(sourceID: $0, kind: .direct, observedAt: time) }))
        }
        return (store, CandidateProvider(contentStore: store), a, b, shared)
    }

    func testOnlySurvivingMembershipCanAttributeASharedStoryAndWalkProgressIsPreserved() throws {
        let (store, provider, a, b, shared) = try fixture()
        let plan = try plan(.main)
        let before = try provider.candidates(for: plan, after: nil, examinedCapacity: 10)
        let after = try provider.candidates(for: plan, after: nil, examinedCapacity: 10, excludingSourceIDs: [a])
        XCTAssertEqual(after.candidates.count, 1)
        let original = try XCTUnwrap(before.candidates.first { $0.originRecordID == shared })
        let expected = Candidate(originRecordID: original.originRecordID, originRevisionID: original.originRevisionID,
            headline: original.headline, summary: original.summary, timestamp: original.timestamp,
            temporal: original.temporal, topics: original.topics, language: original.language,
            providerID: original.providerID, sourceIDs: [b], primaryMediaLocator: original.primaryMediaLocator,
            primaryLink: original.primaryLink, declaredBody: original.declaredBody,
            bodyObserved: original.bodyObserved, mediaKind: original.mediaKind)
        XCTAssertEqual(after.candidates, [expected], "only membership changes; all story facts remain exact")
        XCTAssertEqual(after.examinedCount, before.examinedCount)
        XCTAssertEqual(after.nextCursor, before.nextCursor)
        XCTAssertEqual(after.exhausted, before.exhausted)
        XCTAssertEqual(try store.originRevision(id: original.originRevisionID)?.headline, "<em>Shared news</em>",
            "canonical content was never rewritten")
    }

    func testExcludedSourceContextCannotLeakAnAllowedMembershipFromAnotherSource() throws {
        let (_, provider, a, b, shared) = try fixture()
        for sourceScoped in [false, true] {
            let blocked = try provider.candidates(for: plan(.source(a)), after: nil,
                examinedCapacity: 10, sourceScoped: sourceScoped, excludingSourceIDs: [a])
            XCTAssertEqual(blocked.candidates, [])
            XCTAssertEqual(blocked.examinedCount, 2)
            XCTAssertNotNil(blocked.nextCursor)
            let allowed = try provider.candidates(for: plan(.source(b)), after: nil,
                examinedCapacity: 10, sourceScoped: sourceScoped, excludingSourceIDs: [a])
            XCTAssertEqual(allowed.candidates.map(\.originRecordID), [shared])
            XCTAssertEqual(allowed.candidates.first?.sourceIDs, [b])
        }
    }

    func testRemovingTheRuleReoffersCanonicalSupplyWithoutChangingDefaultProjection() throws {
        let (_, provider, a, _, _) = try fixture()
        let plan = try plan(.main)
        let before = try provider.candidates(for: plan, after: nil, examinedCapacity: 10)
        _ = try provider.candidates(for: plan, after: nil, examinedCapacity: 10, excludingSourceIDs: [a])
        let restored = try provider.candidates(for: plan, after: nil, examinedCapacity: 10, excludingSourceIDs: [])
        XCTAssertEqual(restored, before)
    }
}
