import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMineEditorial

/// TX-07 / F03 characterization, NOT implementation of contextual freshness.
///
/// TX-07D added an explicit temporal-evidence contract to `Candidate`: accepted publication instant,
/// accepted change instant, FeedMine's observation, the inconsistencies the facts themselves state, and
/// a contextual nature that stays `unknown`. It carries recorded facts only — there is no confidence
/// score, no inferred category, and no automatic classifier.
///
/// What did NOT change is the gap this file documents: `SelectionEngine` still compares the numeric
/// value of `timestamp` without regard to its kind, so a story with no publication date, observed today,
/// still outranks a story genuinely published yesterday. The tests below keep describing that existing
/// behavior, and the added ones state exactly what the contract can and cannot tell apart. A test-only
/// label must never become an implicit classifier.
///
/// In particular, `observed` is an observation timestamp, NOT a publication date.
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

    // MARK: - TX-07D additions: what the temporal-evidence contract states, and its named limit

    /// The contract states the publication date as evidence: absence stays absence, and an accepted
    /// authored value stays that value. It also keeps the gap: ordering still reads the numeric value.
    func testF03ContractStatesPublicationEvidenceWhileOrderingStaysNumeric() throws {
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let labeled = corpus(asOf: asOf)
        let undated = try XCTUnwrap(labeled.first { $0.nature == .publicationDateUnknown })
        XCTAssertEqual(undated.candidate.temporal.publicationDate, .absent)
        XCTAssertNil(undated.candidate.temporal.acceptedAuthoredAt)
        XCTAssertEqual(undated.candidate.temporal.observedAt, asOf)
        for item in labeled where item.nature != .publicationDateUnknown {
            XCTAssertEqual(item.candidate.temporal.publicationDate,
                .declared(item.candidate.timestamp.value))
            XCTAssertEqual(item.candidate.temporal.observedAt, item.candidate.timestamp.value)
            XCTAssertTrue(item.candidate.temporal.inconsistencies.isEmpty)
        }
        // The evidence does not reach the ordering: the undated story still leads numerically.
        let plan = try plan()
        let ordered = try SelectionEngine().select(plan: plan, policy: policy(plan.revision),
            window: window(labeled.map(\.candidate))).orderedCandidates
        XCTAssertEqual(ordered.first?.temporal.publicationDate, .absent)
        XCTAssertEqual(ordered.first?.timestamp.value, asOf)
    }

    /// Named limit: canonical supply stores the accepted value only, so a claim the translator had to
    /// clamp and a claim that genuinely equalled the observation instant read identically here. The
    /// contract states that they are indistinguishable instead of inventing a distinction, and the two
    /// are consequently indistinguishable to the selector as well.
    func testF03ClampedDeclarationIsIndistinguishableFromADeclarationOfTheObservationInstant() throws {
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let clamped = story(9, source: 1, timestamp: asOf, kind: .authored, headline: "Declared 2100, clamped")
        let declaredNow = story(8, source: 2, timestamp: asOf, kind: .authored, headline: "Declared the observation instant")
        // Both carry exactly the evidence canonical supply can reconstruct for them.
        for candidate in [clamped, declaredNow] {
            XCTAssertEqual(candidate.temporal, CandidateTemporalEvidence(observedAt: asOf, acceptedAuthoredAt: asOf))
            XCTAssertEqual(candidate.temporal.publicationDate, .declared(asOf))
            XCTAssertTrue(candidate.temporal.inconsistencies.isEmpty)
        }
        let plan = try plan()
        let ordered = try SelectionEngine().select(plan: plan, policy: policy(plan.revision),
            window: window([declaredNow, clamped])).orderedCandidates
        // Deterministic on the documented tie-break, and identical for both: nothing here pretends the
        // clamped declaration was noticed. Re-exposing it needs the claim persisted with the revision.
        XCTAssertEqual(ordered.map(\.originRecordID), [clamped, declaredNow].map(\.originRecordID))
        XCTAssertEqual(ordered.map(\.timestamp), [asOf, asOf].map { CandidateTimestamp(value: $0, kind: .authored) })
    }

    /// The contract is sufficient for the policy F03 needs, and this proves it without installing
    /// anything. A demonstration-only ordering that gives no recency credit to an absent publication date
    /// is computable from `CandidateTemporalEvidence` alone — no new field, no classifier, no clock — and
    /// the engine's actual order is untouched, because the contract activates no editorial behaviour.
    func testF03ContractSufficesForARecencyRuleThatNeverSubstitutesObservation() throws {
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let candidates = corpus(asOf: asOf).map(\.candidate)
        func ids(_ values: [Candidate]) -> [OriginRecordID] { values.map(\.originRecordID) }
        // Test scope only: undated stories lose recency instead of receiving the observation's, and among
        // dated stories the later declared publication instant wins.
        let demonstration = candidates.sorted { left, right in
            switch (left.temporal.publicationDate, right.temporal.publicationDate) {
            case (.absent, .absent):
                return left.originRecordID.rawValue.uuidString > right.originRecordID.rawValue.uuidString
            case (.absent, .declared): return false
            case (.declared, .absent): return true
            case (.declared(let left), .declared(let right)): return left > right
            }
        }
        XCTAssertEqual(ids(demonstration), [1, 2, 4, 3, 5].map { OriginRecordID(rawValue: uuid($0)) })
        XCTAssertEqual(demonstration.last?.temporal.publicationDate, .absent)
        XCTAssertEqual(demonstration.last?.temporal.observedAt, asOf)
        // The installed engine still orders by the numeric timestamp, so nothing above was activated:
        // observing today currently pays as though it were publishing today.
        let plan = try plan()
        let installed = try SelectionEngine().select(plan: plan, policy: policy(plan.revision),
            window: window(candidates)).orderedCandidates
        XCTAssertEqual(ids(installed), [5, 1, 2, 4, 3].map { OriginRecordID(rawValue: uuid($0)) })
        XCTAssertNotEqual(ids(installed), ids(demonstration))
        XCTAssertEqual(plan.revision.sequencingPolicyVersion, PolicyVersion(rawValue: 2))
    }

    /// An unknown representation never becomes a presumed temporal category: the vocabulary holds only
    /// `unknown`, so no classifier can reach a category from age, subject, source or title alone.
    func testF03NoRepresentationBecomesAPresumedTemporalCategory() throws {
        let asOf = Date(timeIntervalSince1970: 1_800_000_000)
        let labeled = corpus(asOf: asOf)
        let candidates = labeled.map(\.candidate)
        XCTAssertEqual(Set(candidates.map(\.temporal.nature)), [.unknown])
        XCTAssertNil(StoryTemporalNature(rawValue: "timeSensitive"))
        XCTAssertNil(StoryTemporalNature(rawValue: "durable"))
        XCTAssertNil(StoryTemporalNature(rawValue: "evergreen"))
        XCTAssertNil(StoryTemporalNature(rawValue: "breaking"))
        let plan = try plan()
        let engine = SelectionEngine()
        let ordered = try engine.select(plan: plan, policy: policy(plan.revision),
            window: window(candidates)).orderedCandidates
        XCTAssertTrue(ordered.allSatisfy { $0.temporal.nature == .unknown })
        // Nature does not participate in ordering today, and no version of the policy supplied here
        // changes that: the value is carried, never executed (the contract activates no new policy).
        let otherPolicy = policy(plan.revision, sequencing: .recencyAlternatingSources)
        XCTAssertEqual(try engine.select(plan: plan, policy: otherPolicy,
            window: window(candidates)).orderedCandidates.map(\.temporal.nature),
            ordered.map(\.temporal.nature))
    }
}
