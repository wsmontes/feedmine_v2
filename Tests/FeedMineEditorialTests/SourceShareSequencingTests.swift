import XCTest
import FeedMineDomain
@testable import FeedMineEditorial

/// Sequencing v7: the source's share of the recent positions decides first, v6's type → subjects → source distance
/// decides inside that tie. The supplies mirror docs/reviews/evidence/2026-11-02-v6-sequencing-sim/v7_sim.py, which
/// ports this rule and prints the expected counts (v6 25/50 and v7 3/50 for one podcast among 20 text feeds).
final class SourceShareSequencingTests: XCTestCase {
    private var nextOrigin = 0

    private func origin() -> OriginRecordID {
        nextOrigin += 1
        return OriginRecordID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", nextOrigin))!)
    }
    private func plan(version: UInt64) -> FeedPlan {
        let context = FeedContext(request: .main), v = PolicyVersion(rawValue: 1)
        return FeedPlan(context: context, revision: EditorialRevision(
            id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: v,
            eligibilityPolicyVersion: v, scoringPolicyVersion: v,
            sequencingPolicyVersion: PolicyVersion(rawValue: version),
            exposurePolicyVersion: v, selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1)))!
    }
    private func policy(_ plan: FeedPlan,
        sequencing: ResolvedSelectionPolicy.SequencingBehavior) -> ResolvedSelectionPolicy {
        let r = plan.revision
        return ResolvedSelectionPolicy(contextKey: r.contextKey, userSelectionVersion: r.userSelectionVersion,
            eligibilityPolicyVersion: r.eligibilityPolicyVersion, scoringPolicyVersion: r.scoringPolicyVersion,
            sequencingPolicyVersion: r.sequencingPolicyVersion, exposurePolicyVersion: r.exposurePolicyVersion,
            selectionSchemaVersion: r.selectionSchemaVersion, eligibility: .structuralOnly,
            scoring: .equal, sequencing: sequencing, exposure: .none)
    }
    private func items(_ source: SourceID, count: Int, kind: EditorialMediaKind,
        time: (Int) -> Double) -> [Candidate] {
        (0..<count).map { index in
            Candidate(originRecordID: origin(), originRevisionID: OriginRevisionID(),
                headline: "C\(index)", summary: nil,
                timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: time(index)), kind: .observed),
                topics: .absent, language: nil, providerID: nil, sourceIDs: [source], mediaKind: kind)
        }
    }
    private func select(_ candidates: [Candidate], positions: [EditorialDiversityFact?] = [],
        version: UInt64, sequencing: ResolvedSelectionPolicy.SequencingBehavior) throws -> SelectionResult {
        let plan = plan(version: version)
        let diversity = positions.isEmpty ? nil : SelectionDiversityContext(publishedPositions: positions)
        return try SelectionEngine().select(plan: plan, policy: policy(plan, sequencing: sequencing),
            window: CandidateSupplyWindow(candidates: candidates, examinedCount: candidates.count,
                nextCursor: nil, exhausted: true),
            exposure: nil, after: nil, readiness: nil, diversity: diversity)
    }
    private func v7(_ candidates: [Candidate], positions: [EditorialDiversityFact?] = []) throws -> SelectionResult {
        try select(candidates, positions: positions, version: 7, sequencing: .sourceShareThenMaximumDistance)
    }

    /// The supply of the 24/out measurement, reduced: one prolific podcast (always the newest) among 20 text feeds.
    private func onePodcastAmongTwentyTextFeeds() -> (podcast: SourceID, supply: [Candidate]) {
        let podcast = SourceID()
        var supply = items(podcast, count: 40, kind: .audio) { 1_000 - Double($0) }
        for feed in 0..<20 {
            supply += items(SourceID(), count: 5, kind: EditorialMediaKind.none) { 500 - Double($0 * 20 + feed) }
        }
        return (podcast, supply)
    }

    func testOneRareTypeSourceNoLongerTakesEveryOtherCard() throws {
        let (podcast, supply) = onePodcastAmongTwentyTextFeeds()
        let v6Order = try select(supply, version: 6, sequencing: .maximumDistance).orderedCandidates.prefix(50)
        let v7Order = try v7(supply).orderedCandidates.prefix(50)
        XCTAssertEqual(v7Order.count, 50)
        XCTAssertEqual(v6Order.filter { $0.sourceIDs.contains(podcast) }.count, 25,
            "v6 behaviour is unchanged: the rare type wins every other choice")
        XCTAssertEqual(v7Order.filter { $0.sourceIDs.contains(podcast) }.count, 3,
            "v7 serves the podcast at the share of any other source")
        XCTAssertEqual(Set(v7Order.flatMap(\.sourceIDs)).count, 21, "every source appears in the first 50")
    }

    func testV7KeepsPD4() throws {
        let (_, supply) = onePodcastAmongTwentyTextFeeds()
        let placed = try v7(supply).orderedCandidates
        for (left, right) in zip(placed, placed.dropFirst()) {
            XCTAssertTrue(left.sourceIDs.isDisjoint(with: right.sourceIDs), "no two adjacent cards share a source")
        }
    }

    /// The share is read from a bounded window, so a source that joins a long Edition catches up in a few cards
    /// instead of owning the feed until its lifetime count reaches the others'.
    func testALateSourceCatchesUpWithinTheWindowAndNoFurther() throws {
        let established = (0..<10).map { _ in SourceID() }
        let history: [EditorialDiversityFact?] = (0..<200).map {
            EditorialDiversityFact(sourceIDs: [established[$0 % 10]], providerID: nil, subjects: [],
                mediaKind: EditorialMediaKind.none)
        }
        let late = SourceID()
        var supply = items(late, count: 20, kind: EditorialMediaKind.none) { 1_000 - Double($0) }
        for (index, source) in established.enumerated() {
            supply += items(source, count: 5, kind: EditorialMediaKind.none) { 500 - Double($0 * 20 + index) }
        }
        let first20 = try v7(supply, positions: history).orderedCandidates.prefix(20)
        XCTAssertEqual(first20.count, 20)
        XCTAssertTrue(first20.first?.sourceIDs.contains(late) == true, "the unseen source leads")
        XCTAssertEqual(first20.filter { $0.sourceIDs.contains(late) }.count, 3,
            "it reaches the window share of the others (32 positions / 10 sources) and then rotates normally")
    }

    func testAMismatchedVersionAndBehaviourNeverRunsV7() throws {
        let (_, supply) = onePodcastAmongTwentyTextFeeds()
        let legacy = try select(supply, version: 6, sequencing: .sourceShareThenMaximumDistance)
        XCTAssertEqual(legacy.orderedCandidates.map(\.originRecordID),
            try select(supply, version: 1, sequencing: .recencyDescending).orderedCandidates.map(\.originRecordID),
            "the v7 behaviour under revision 6 falls through to the legacy recency order")
        let future = try select(supply, version: 8, sequencing: .sourceShareThenMaximumDistance)
        XCTAssertEqual(future.orderedCandidates.map(\.originRecordID),
            legacy.orderedCandidates.map(\.originRecordID), "an unknown version does not inherit v7")
    }

    func testInputPermutationIsDeterministic() throws {
        let (_, supply) = onePodcastAmongTwentyTextFeeds()
        let expected = try v7(supply).orderedCandidates.map(\.originRecordID)
        XCTAssertEqual(try v7(Array(supply.reversed())).orderedCandidates.map(\.originRecordID), expected)
        XCTAssertEqual(try v7(supply.enumerated().sorted { ($0.offset * 37) % 140 < ($1.offset * 37) % 140 }
            .map(\.element)).orderedCandidates.map(\.originRecordID), expected)
    }
}
