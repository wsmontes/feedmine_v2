import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMineEditorial

/// TX-07 / F03 characterization, NOT implementation of contextual freshness.
///
/// There is no canonical per-story temporal-nature or date-confidence fact in the
/// candidate contract. These tests deliberately describe the existing behavior,
/// including its F03 gap. A test-only label must never become an implicit classifier.
///
/// In particular, `observed` is an observation timestamp, NOT a publication date.
/// The legacy selector still sorts its numeric value as if it were comparable
/// to `authored`; that is a known product gap, not an acceptance criterion.
final class ContextualFreshnessCharacterizationTests: XCTestCase {
    private enum Nature: Hashable {
        case recentNews
        case oldNews
        case oldDurableExplanation
        case materiallyEditedStory
        case publicationDateUnknown
    }

    private struct LabeledStory {
        let nature: Nature // Test oracle only; the production Candidate has no equivalent fact.
        let candidate: Candidate
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    private func story(_ id: Int, revision: Int? = nil, source: Int,
        timestamp: Date, kind: CandidateTimestampKind, headline: String,
        body: String? = nil) -> Candidate {
        Candidate(originRecordID: OriginRecordID(rawValue: uuid(id)),
            originRevisionID: OriginRevisionID(rawValue: uuid(revision ?? id)),
            headline: headline, summary: "Summary for \(id)",
            timestamp: CandidateTimestamp(value: timestamp, kind: kind),
            language: "en", providerID: nil,
            sourceIDs: [SourceID(rawValue: uuid(1000 + source))],
            declaredBody: body)
    }

    /// All timestamps are derived from an explicitly supplied reference instant.
    /// SelectionEngine has no `asOf` parameter and never reads a clock here.
    private func corpus(asOf: Date) -> [LabeledStory] {
        let day: TimeInterval = 86_400
        return [
            LabeledStory(nature: .recentNews, candidate: story(1, source: 1,
                timestamp: asOf.addingTimeInterval(-day), kind: .authored,
                headline: "Recent breaking report")),
            LabeledStory(nature: .oldNews, candidate: story(2, source: 2,
                timestamp: asOf.addingTimeInterval(-40 * day), kind: .authored,
                headline: "An old breaking report")),
            LabeledStory(nature: .oldDurableExplanation, candidate: story(3, source: 3,
                timestamp: asOf.addingTimeInterval(-5 * 365 * day), kind: .authored,
                headline: "A lasting explanation")),
            LabeledStory(nature: .materiallyEditedStory, candidate: story(4, revision: 44, source: 4,
                timestamp: asOf.addingTimeInterval(-100 * day), kind: .authored,
                headline: "A revised investigation", body: "Substantially revised article body")),
            // The test oracle knows this old story has no trustworthy publication date.
            // The candidate itself only knows when FeedMine observed it.
            LabeledStory(nature: .publicationDateUnknown, candidate: story(5, source: 2,
                timestamp: asOf, kind: .observed,
                headline: "Undated older story seen today")),
        ]
    }

    private func plan(sequencingVersion: UInt64 = 2) throws -> FeedPlan {
        let context = FeedContext(request: .main)
        return try XCTUnwrap(FeedPlan(context: context, revision: EditorialRevision(
            id: EditorialRevisionID(rawValue: uuid(800)), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1),
            userSelectionVersion: PolicyVersion(rawValue: 1),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 1),
            scoringPolicyVersion: PolicyVersion(rawValue: 1),
            sequencingPolicyVersion: PolicyVersion(rawValue: sequencingVersion),
            exposurePolicyVersion: PolicyVersion(rawValue: 1),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))))
    }

    private func policy(_ revision: EditorialRevision,
        sequencing: ResolvedSelectionPolicy.SequencingBehavior = .recencyDescending,
        exposure: ResolvedSelectionPolicy.ExposureBehavior = .none) -> ResolvedSelectionPolicy {
        ResolvedSelectionPolicy(contextKey: revision.contextKey,
            userSelectionVersion: revision.userSelectionVersion,
            eligibilityPolicyVersion: revision.eligibilityPolicyVersion,
            scoringPolicyVersion: revision.scoringPolicyVersion,
            sequencingPolicyVersion: revision.sequencingPolicyVersion,
            exposurePolicyVersion: revision.exposurePolicyVersion,
            selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal,
            sequencing: sequencing, exposure: exposure)
    }

    private func window(_ candidates: [Candidate]) -> CandidateSupplyWindow {
        CandidateSupplyWindow(candidates: candidates, examinedCount: candidates.count,
            nextCursor: nil, exhausted: true)
    }

    func testF03ObservedTodayCurrentlyOutranksPublishedYesterdayDespiteUnknownPublicationDate() throws {
        // This is a *characterization of the failing F03 behavior*, NOT proof of compliance.
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let labeled = corpus(asOf: asOf)
        let plan = try plan()
        let result = try SelectionEngine().select(plan: plan, policy: policy(plan.revision),
            window: window(labeled.map(\.candidate)))
        let selected = result.orderedCandidates

        XCTAssertEqual(Set(labeled.map(\.nature)),
            [.recentNews, .oldNews, .oldDurableExplanation, .materiallyEditedStory, .publicationDateUnknown])
        XCTAssertEqual(selected.map(\.originRecordID),
            [5, 1, 2, 4, 3].map { OriginRecordID(rawValue: uuid($0)) })
        XCTAssertEqual(selected.first?.timestamp.kind, .observed)
        XCTAssertEqual(selected.first?.timestamp.value, asOf)
        // F03 GAP: observed-at currently acts like publication recency in ordering,
        // even though the timestamp kind remains honestly marked as observation.
    }

    func testF03ComparableAuthoredDatesPreferNewerAndOldDurableStoryRemainsReachable() throws {
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let labeled = corpus(asOf: asOf)
        let plan = try plan()
        let result = try SelectionEngine().select(plan: plan, policy: policy(plan.revision),
            window: window(labeled.map(\.candidate)))
        let ids = result.orderedCandidates.map(\.originRecordID)
        let newer = try XCTUnwrap(labeled.first(where: { $0.nature == .recentNews })).candidate
        let older = try XCTUnwrap(labeled.first(where: { $0.nature == .oldNews })).candidate
        let durable = try XCTUnwrap(labeled.first(where: { $0.nature == .oldDurableExplanation })).candidate

        XCTAssertLessThan(try XCTUnwrap(ids.firstIndex(of: newer.originRecordID)),
            try XCTUnwrap(ids.firstIndex(of: older.originRecordID)))
        XCTAssertTrue(ids.contains(durable.originRecordID))
        XCTAssertEqual(result.orderedCandidates.count, labeled.count)
        // F03 GAP: the old explanation is reachable, but the engine has no way
        // to apply a slower age penalty to it than to an equally old news report.
    }

    func testF03MaterialEditRemainsSelectableWithoutInventingNewPublicationTime() throws {
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let edited = try XCTUnwrap(corpus(asOf: asOf).first(where: {
            $0.nature == .materiallyEditedStory
        })).candidate
        let original = story(4, revision: 4, source: 4,
            timestamp: edited.timestamp.value, kind: .authored,
            headline: edited.headline ?? "", body: "Original article body")
        let oldKey = SelectionExposureSnapshot.materialKey(
            headline: original.headline, summary: original.summary,
            declaredBody: original.declaredBody)
        let exposure = try XCTUnwrap(SelectionExposureSnapshot(
            requestedOriginIDs: [edited.originRecordID],
            publishedOriginIDs: [edited.originRecordID],
            publishedMaterialKeys: [edited.originRecordID: [oldKey]]))
        let plan = try plan()
        let selected = try SelectionEngine().select(plan: plan,
            policy: policy(plan.revision, exposure: .excludePublishedMaterial),
            window: window([edited]), exposure: exposure)

        XCTAssertEqual(selected.orderedCandidates, [edited])
        XCTAssertEqual(edited.timestamp, original.timestamp)
        XCTAssertEqual(edited.timestamp.kind, .authored)
        // A material edit can qualify under PD-1 without changing its authored date.
        // A changed date or revision ID alone must not be treated as new content.
    }

    func testF03LegacyPD4AlternationStillReachesOlderStoriesAndIsPermutationInvariant() throws {
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let candidates = corpus(asOf: asOf).map(\.candidate)
        let plan = try plan(sequencingVersion: 2)
        let oldPolicy = policy(plan.revision, sequencing: .recencyAlternatingSources)
        let engine = SelectionEngine()
        let expected = try engine.select(plan: plan, policy: oldPolicy,
            window: window(candidates)).orderedCandidates

        XCTAssertEqual(Set(expected.map(\.originRecordID)), Set(candidates.map(\.originRecordID)))
        for (previous, next) in zip(expected, expected.dropFirst()) {
            XCTAssertTrue(previous.sourceIDs.isDisjoint(with: next.sourceIDs), "PD-4 must hold")
        }
        for shuffled in [Array(candidates.reversed()),
            [candidates[4], candidates[2], candidates[0], candidates[3], candidates[1]],
            [candidates[1], candidates[3], candidates[4], candidates[0], candidates[2]]] {
            let actual = try engine.select(plan: plan, policy: oldPolicy,
                window: window(shuffled)).orderedCandidates
            XCTAssertEqual(actual, expected, "the same supply and legacy policy must remain deterministic")
        }
    }

    func testF03TestOnlyNatureLabelsCannotAlterLegacyOrderingOrEditionPolicyIdentity() throws {
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let labeled = corpus(asOf: asOf)
        let relabeled = labeled.map { item in
            LabeledStory(nature: .oldNews, candidate: item.candidate)
        }
        // The labels intentionally never enter Candidate or a resolved policy.
        // There is no evidentiary basis for distinguishing per-story decay speeds.
        let plan = try plan(sequencingVersion: 2)
        let oldPolicy = policy(plan.revision, sequencing: .recencyAlternatingSources)
        let engine = SelectionEngine()
        let before = try engine.select(plan: plan, policy: oldPolicy,
            window: window(labeled.map(\.candidate)))
        let after = try engine.select(plan: plan, policy: oldPolicy,
            window: window(relabeled.map(\.candidate)))
        XCTAssertEqual(before, after)
        XCTAssertEqual(before.editorialRevision, plan.revision)
        XCTAssertEqual(oldPolicy.sequencingPolicyVersion, PolicyVersion(rawValue: 2))
    }
}
