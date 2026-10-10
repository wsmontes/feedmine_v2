import XCTest
import FeedMineDomain
@testable import FeedMineEditorial

/// T11: a curated feed's ranking inside the engine. The weights are the session's own source identities, and a
/// session that is not weighting (`scoring: .equal`) orders by recency exactly as it always did.
final class WeightedScoringTests: XCTestCase {
    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
    }

    private func candidate(_ origin: Int, sources: [Int], time: Double) -> Candidate {
        Candidate(originRecordID: OriginRecordID(rawValue: uuid(origin)),
            originRevisionID: OriginRevisionID(rawValue: uuid(origin)),
            headline: "c\(origin)", summary: nil,
            timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: time), kind: .observed),
            language: "pt", providerID: nil,
            sourceIDs: Set(sources.map { SourceID(rawValue: uuid($0)) }))
    }

    private func plan() throws -> FeedPlan {
        let context = FeedContext(request: .main)
        return try XCTUnwrap(FeedPlan(context: context, revision: EditorialRevision(
            id: EditorialRevisionID(rawValue: uuid(900)), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 1),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 2), scoringPolicyVersion: PolicyVersion(rawValue: 3),
            sequencingPolicyVersion: PolicyVersion(rawValue: 4), exposurePolicyVersion: PolicyVersion(rawValue: 5),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 6))))
    }

    private func policy(_ revision: EditorialRevision,
        scoring: ResolvedSelectionPolicy.ScoringBehavior) -> ResolvedSelectionPolicy {
        ResolvedSelectionPolicy(contextKey: revision.contextKey,
            userSelectionVersion: revision.userSelectionVersion,
            eligibilityPolicyVersion: revision.eligibilityPolicyVersion,
            scoringPolicyVersion: revision.scoringPolicyVersion,
            sequencingPolicyVersion: revision.sequencingPolicyVersion,
            exposurePolicyVersion: revision.exposurePolicyVersion,
            selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: scoring, sequencing: .recencyDescending, exposure: .none)
    }

    private func window(_ candidates: [Candidate]) -> CandidateSupplyWindow {
        CandidateSupplyWindow(candidates: candidates, examinedCount: candidates.count, nextCursor: nil,
            exhausted: true)
    }

    /// The reader's own weights decide the order, ahead of recency.
    func testAWeightedSessionRanksByTheReadersWeights() throws {
        let plan = try plan()
        let older = candidate(1, sources: [10], time: 100)
        let newer = candidate(2, sources: [20], time: 900)
        let weighted = policy(plan.revision, scoring: .weighted([
            SourceID(rawValue: uuid(10)): 1.4, SourceID(rawValue: uuid(20)): 0.8]))
        let result = try SelectionEngine().select(plan: plan, policy: weighted, window: window([newer, older]))
        XCTAssertEqual(result.orderedCandidates.map(\.headline), ["c1", "c2"],
            "the preferred source comes first even though it is older")
        // The same two candidates in a session that is not weighting: recency decides, as always.
        let plain = policy(plan.revision, scoring: .equal)
        let unweighted = try SelectionEngine().select(plan: plan, policy: plain, window: window([newer, older]))
        XCTAssertEqual(unweighted.orderedCandidates.map(\.headline), ["c2", "c1"])
    }

    /// The same weight keeps recency as the tie-break, so a curated feed is still a feed.
    func testEqualWeightsFallBackToRecency() throws {
        let plan = try plan()
        let older = candidate(1, sources: [10], time: 100)
        let newer = candidate(2, sources: [20], time: 900)
        let weighted = policy(plan.revision, scoring: .weighted([
            SourceID(rawValue: uuid(10)): 1.2, SourceID(rawValue: uuid(20)): 1.2]))
        let result = try SelectionEngine().select(plan: plan, policy: weighted, window: window([older, newer]))
        XCTAssertEqual(result.orderedCandidates.map(\.headline), ["c2", "c1"])
    }

    /// A card belonging to several sources takes the strongest weight, and a source the recipe never weighed
    /// counts as neutral rather than as a penalty.
    func testACardTakesItsStrongestSourceAndUnweightedSourcesAreNeutral() throws {
        let plan = try plan()
        let shared = candidate(1, sources: [10, 20], time: 100)
        let unweighted = candidate(2, sources: [30], time: 900)
        let weighted = policy(plan.revision, scoring: .weighted([SourceID(rawValue: uuid(10)): 1.5]))
        let result = try SelectionEngine().select(plan: plan, policy: weighted, window: window([unweighted, shared]))
        XCTAssertEqual(result.orderedCandidates.map(\.headline), ["c1", "c2"],
            "one strong source is enough to lift the card, and the unknown source weighs 1")
    }
}
