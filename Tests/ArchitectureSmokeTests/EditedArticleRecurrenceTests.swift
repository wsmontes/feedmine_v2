// PD-1 integration: an edited article reappears as a new card; replay and whitespace churn do not.
import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime

final class EditedArticleRecurrenceTests: XCTestCase {
    private static func prepare(_ selection: SelectionResult) -> LocalPreparedPublication {
        .init(inputs: selection.orderedCandidates.map {
            .init(origin: .init(originRecordID: $0.originRecordID, originRevisionID: $0.originRevisionID,
                sourceID: nil, providerID: $0.providerID, sourceDisplayName: "Feed", providerDisplayName: nil),
                contentEntityID: nil, contentClusterID: nil, primaryAction: .localContentDetail, presentation: .textOnly)
        }, cardIDs: selection.orderedCandidates.map { _ in PublicationCardID() })
    }

    func testEditedArticleIsPublishedAgainButReplayAndWhitespaceAreNot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: .init(directory: root))
        let store = ContentStore(database: database), source = SourceID(), origin = OriginRecordID(), edition = FeedEditionID()
        let identity = ExternalIdentity(connectorKind: .syndication, namespace: "pd1", value: "article", role: .object)
        var current: OriginRevisionID?
        var clock = 1000.0
        func admit(_ summary: String) throws {
            clock += 10
            let date = Date(timeIntervalSince1970: clock)
            let revision = OriginRevision(id: OriginRevisionID(), originRecordID: origin, externalVersionIdentity: nil,
                headline: "Headline", summary: summary, bodyText: nil, authoredAt: Date(timeIntervalSince1970: 900),
                modifiedAt: nil, observedAt: date, language: nil, primaryLink: nil, searchProjection: nil, providerID: nil)
            try store.commitCanonicalChange(.init(recordID: origin, externalObjectIdentity: identity, revision: revision,
                mediaCandidates: [], availability: .available, observedAt: date,
                expectedCurrent: current.map { .revision($0) } ?? .none, currentUpdate: .useSuppliedRevision,
                membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: date)]))
            current = revision.id
        }
        let context = FeedContext(request: .main), v1 = PolicyVersion(rawValue: 1), v2 = PolicyVersion(rawValue: 2)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key, catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: v1, eligibilityPolicyVersion: v1, scoringPolicyVersion: v1, sequencingPolicyVersion: v1,
            exposurePolicyVersion: v2, selectionSchemaVersion: .init(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
        let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: v1, eligibilityPolicyVersion: v1,
            scoringPolicyVersion: v1, sequencingPolicyVersion: v1, exposurePolicyVersion: v2,
            selectionSchemaVersion: revision.selectionSchemaVersion, eligibility: .structuralOnly, scoring: .equal,
            sequencing: .recencyDescending, exposure: .excludePublishedMaterial)
        func slice() throws -> LocalProductionSliceOutcome {
            try LocalProductionSlice(database: database).run(.init(plan: plan, policy: policy, editionID: edition, after: nil,
                examinedCapacity: 5, segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(timeIntervalSince1970: clock)),
                prepare: Self.prepare)
        }

        try admit("Original text")
        let initial = try InitialProductionSlice(database: database).run(.init(plan: plan, policy: policy, examinedCapacity: 5,
            editionID: edition, publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1,
            editionCreatedAt: Date(timeIntervalSince1970: clock), segmentID: FeedSegmentID(), segmentSeed: 1,
            segmentCreatedAt: Date(timeIntervalSince1970: clock), anchorPlacement: .top,
            checkpointedAt: Date(timeIntervalSince1970: clock)), prepare: Self.prepare)
        guard case .published = initial else { return XCTFail("Expected first publication") }

        // Whitespace-only change: a new canonical revision, but not a material edit.
        try admit("Original   text ")
        guard case .advancedWithoutPublication = try slice() else { return XCTFail("Whitespace churn must not republish") }

        // Material edit: the article reappears as a new occurrence.
        try admit("Corrected text")
        guard case .published(_, let receipt) = try slice() else { return XCTFail("Edited article must reappear") }
        let cards = try PublicationStore(database: database).segments(editionID: edition).flatMap(\.cardIDs)
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(try PublicationStore(database: database).card(id: receipt.cardIDs[0])?.primaryText, "Corrected text")

        // Replay of the same edit is not published a third time.
        guard case .advancedWithoutPublication = try slice() else { return XCTFail("Replay must not republish") }
    }

    func testRecurrenceForbiddenPolicyKeepsPhase3R5Uniqueness() throws {
        let snapshot = try XCTUnwrap(SelectionExposureSnapshot(requestedOriginIDs: [OriginRecordID()], publishedOriginIDs: []))
        XCTAssertTrue(snapshot.publishedMaterialKeys.isEmpty)
        XCTAssertEqual(SelectionExposureSnapshot.materialKey(headline: " A  b ", summary: "c\n d"),
            PublicationStore.materialKey(title: "A b", primaryText: "c d"))
    }
}

extension EditedArticleRecurrenceTests {
    /// Review F07: a new primary image is a material change, and an origin with an occurrence still
    /// ahead of the reader is never queued again (PD-1 rule 2).
    func testPrimaryMediaIsMaterialAndUnseenOccurrenceBlocksAnother() throws {
        let origin = OriginRecordID()
        func candidate(media: String?) -> Candidate {
            Candidate(originRecordID: origin, originRevisionID: OriginRevisionID(), headline: "H", summary: "S",
                timestamp: .init(value: Date(timeIntervalSince1970: 1), kind: .authored), language: nil, providerID: nil,
                primaryMediaLocator: media)
        }
        let publishedKey = PublicationStore.materialKey(title: "H", primaryText: "S", primaryMedia: "https://example.test/a.jpg")
        XCTAssertEqual(publishedKey, SelectionExposureSnapshot.materialKey(headline: "H", summary: "S",
            primaryMedia: "https://example.test/a.jpg"))
        let v = PolicyVersion(rawValue: 1), context = FeedContext(request: .main)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key, catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: v,
            exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
        let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1),
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedMaterial)
        func select(_ c: Candidate, unseen: Bool) throws -> Int {
            let exposure = try XCTUnwrap(SelectionExposureSnapshot(requestedOriginIDs: [origin], publishedOriginIDs: [origin],
                publishedMaterialKeys: [origin: [publishedKey]], unseenOriginIDs: unseen ? [origin] : []))
            return try SelectionEngine().select(plan: plan, policy: policy,
                window: .init(candidates: [c], examinedCount: 1, nextCursor: nil, exhausted: true), exposure: exposure).orderedCandidates.count
        }
        XCTAssertEqual(try select(candidate(media: "https://example.test/a.jpg"), unseen: false), 0, "same text and image")
        XCTAssertEqual(try select(candidate(media: "https://example.test/b.jpg"), unseen: false), 1, "new primary image")
        XCTAssertEqual(try select(candidate(media: "https://example.test/b.jpg"), unseen: true), 0, "earlier occurrence still unseen")
    }
}