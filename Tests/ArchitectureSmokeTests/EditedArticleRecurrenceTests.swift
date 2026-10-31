// PD-1 integration: an edited article reappears as a new card; replay and whitespace churn do not.
import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
@testable import FeedMineEditorial
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

    /// PD-5 supersedes the old permission to re-prepare published-but-unseen cards: an occurrence published in an
    /// Edition keeps its ID, text and position whether or not the reader has seen it. A material edit therefore
    /// waits for a later segment instead of rewriting this one — it is neither lost (PD-1) nor duplicated.
    func testPublishedUnseenOccurrenceIsImmutableAndTheEditWaitsForAFutureSegment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: .init(directory: root))
        let content = ContentStore(database: database)
        let seenSource = SourceID(), unseenSource = SourceID(), lateSource = SourceID()
        let anchorOrigin = OriginRecordID(), editedOrigin = OriginRecordID(), lateOrigin = OriginRecordID()
        func admit(_ origin: OriginRecordID, source: SourceID, text: String,
            previous: OriginRevisionID?, authored: Double) throws -> OriginRevisionID {
            let date = Date(timeIntervalSince1970: authored)
            let revision = OriginRevision(id: OriginRevisionID(), originRecordID: origin, externalVersionIdentity: nil,
                headline: "H", summary: text, bodyText: nil, authoredAt: date, modifiedAt: nil, observedAt: date,
                language: nil, primaryLink: nil, searchProjection: nil, providerID: nil)
            try content.commitCanonicalChange(.init(recordID: origin, externalObjectIdentity: .init(connectorKind: .syndication,
                namespace: "pd5-tail", value: origin.rawValue.uuidString, role: .object), revision: revision, mediaCandidates: [],
                availability: .available, observedAt: date, expectedCurrent: previous.map { .revision($0) } ?? .none,
                currentUpdate: .useSuppliedRevision, membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: date)]))
            return revision.id
        }
        _ = try admit(anchorOrigin, source: seenSource, text: "seen", previous: nil, authored: 2000)
        let e1 = try admit(editedOrigin, source: unseenSource, text: "E1", previous: nil, authored: 1000)
        let context = FeedContext(request: .main), v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key, catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: v,
            exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: context, revision: revision))
        let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1),
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending, exposure: .excludePublishedMaterial)
        let edition = FeedEditionID()
        guard case .published(_, let initial) = try InitialProductionSlice(database: database).run(.init(plan: plan, policy: policy,
            examinedCapacity: 10, editionID: edition, publicationSchemaVersion: .init(rawValue: 1), selectionSeed: 1,
            editionCreatedAt: Date(timeIntervalSince1970: 2500), segmentID: FeedSegmentID(), segmentSeed: 1,
            segmentCreatedAt: Date(timeIntervalSince1970: 2500), anchorPlacement: .center,
            checkpointedAt: Date(timeIntervalSince1970: 2500)), prepare: Self.prepare) else {
            return XCTFail("Expected the first Edition to publish the two admitted stories")
        }
        let store = PublicationStore(database: database)
        let anchor = initial.cardIDs[0]
        func live() throws -> [PublicationStore.CardRecord] {
            try store.cards(editionID: edition, around: anchor, backwardCapacity: 0, forwardCapacity: 10)
        }
        // The second card is published and ahead of the reader's anchor: it has never been exposed.
        let published = try live()
        XCTAssertEqual(published.map(\.primaryText), ["seen", "E1"])
        XCTAssertEqual(try PublicationHistory(database: database).exposure(editionID: edition,
            originIDs: [editedOrigin]).unseenOriginIDs, [editedOrigin],
            "The second occurrence is published and still ahead of the reader")
        let segmentsBefore = try store.segments(editionID: edition)
        let checkpointBefore = try SessionStore(database: database).checkpoint()
        XCTAssertEqual(checkpointBefore?.cardID, anchor)

        // A material edit of the unexposed occurrence, and an unrelated story that has never been published.
        let e2 = try admit(editedOrigin, source: unseenSource, text: "E2", previous: e1, authored: 1500)
        _ = try admit(lateOrigin, source: lateSource, text: "late", previous: nil, authored: 3000)

        // Production with the reader still before the unexposed occurrence: PD-1 rule 2 holds the edit, PD-5
        // forbids rewriting the published card, and the never-published story is published normally.
        guard case .published(_, let late) = try LocalProductionSlice(database: database).run(.init(plan: plan, policy: policy,
            editionID: edition, after: nil, examinedCapacity: 10, segmentID: FeedSegmentID(), segmentSeed: 1,
            segmentCreatedAt: Date(timeIntervalSince1970: 3500)), prepare: Self.prepare) else {
            return XCTFail("The unexposed story must not block the rest of the supply")
        }
        XCTAssertEqual(try store.card(id: late.cardIDs[0])?.primaryText, "late")
        let held = try live()
        XCTAssertEqual(held.map(\.primaryText), ["seen", "E1", "late"])
        XCTAssertEqual(held.filter { $0.originRecordID == editedOrigin }.map(\.originRevisionID), [e1],
            "The edit is held, not published and not replacing the published occurrence")
        XCTAssertEqual(held[0], published[0])
        XCTAssertEqual(held[1], published[1], "Every published field of the unexposed occurrence is unchanged")
        XCTAssertEqual(try store.segments(editionID: edition).first, segmentsBefore.first)
        XCTAssertEqual(try SessionStore(database: database).checkpoint(), checkpointBefore, "anchor never moves on its own")

        // A relaunch reads the same Edition: the published tail is the card that was published, not a newer edit.
        let reopened = try RuntimeDatabase(location: .init(directory: root))
        let restored = try XCTUnwrap(PublicationHistory(database: reopened).restore(backwardCapacity: 2, forwardCapacity: 10))
        XCTAssertEqual(restored.window.cards.map(\.text.primaryText), ["seen", "E1", "late"])
        XCTAssertEqual(restored.window.cards[1].origin.originRevisionID, e1)
        XCTAssertEqual(restored.cursor.anchor.cardID, anchor)

        // Once the reader has seen the occurrence, the edit is a new occurrence in a later segment (PD-1): a new
        // card id, the old one untouched, appended rather than substituted.
        try store.markSeen(editionID: edition, cardID: published[1].id)
        guard case .published(_, let recurrence) = try LocalProductionSlice(database: database).run(.init(plan: plan, policy: policy,
            editionID: edition, after: nil, examinedCapacity: 10, segmentID: FeedSegmentID(), segmentSeed: 1,
            segmentCreatedAt: Date(timeIntervalSince1970: 4500)), prepare: Self.prepare) else {
            return XCTFail("A material edit of a seen occurrence must be published")
        }
        XCTAssertEqual(recurrence.cardIDs.count, 1)
        XCTAssertNotEqual(recurrence.cardIDs[0], published[1].id)
        XCTAssertEqual(try store.card(id: recurrence.cardIDs[0])?.primaryText, "E2")
        XCTAssertEqual(try store.card(id: recurrence.cardIDs[0])?.originRevisionID, e2)
        let eventual = try live()
        XCTAssertEqual(eventual.map(\.primaryText), ["seen", "E1", "late", "E2"])
        XCTAssertEqual(eventual[1], published[1], "The earlier occurrence stays in history unchanged")
        XCTAssertEqual(try store.segments(editionID: edition).first, segmentsBefore.first)
        XCTAssertEqual(try SessionStore(database: database).checkpoint(), checkpointBefore)
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
        XCTAssertEqual(try select(candidate(media: "https://example.test/a.jpg?utm_source=rss&fbclid=changed"), unseen: false), 0,
            "tracking parameters do not change the primary image")
        XCTAssertEqual(try select(candidate(media: "https://example.test/a.jpg?image=other"), unseen: false), 1,
            "meaningful query parameters still identify a different image")
        XCTAssertEqual(try select(candidate(media: "https://example.test/b.jpg"), unseen: false), 1, "new primary image")
        XCTAssertEqual(try select(candidate(media: "https://example.test/b.jpg"), unseen: true), 0, "earlier occurrence still unseen")
    }
}