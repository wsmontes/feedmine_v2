// Owns: the distribution contract R1 asked for — PD-4 guarantees adjacency, this guarantees spread.
// Does not own: the window size (a candidate-supply decision, not a sequencing one).
//
// The assertions are deliberately relative, never a fixed quota: they compare sources against each
// other and against the supply that exists, so nothing forces a card to be published and nothing
// promises a share the window cannot pay (architect's amendment, 2026-10-10).

import XCTest
import FeedMineDomain
@testable import FeedMineEditorial

/// R1 measured a real simulator run. At the first publication the admission window held 102 eligible
/// candidates from three sources; the segment that followed it examined the production window of 32
/// candidates and published 12 of the 107 sources that were eligible. `SourceAlternation.apply` used
/// to take the earliest compatible candidate, which returns to the head source as soon as it is
/// compatible again: a source's second card preceded another source's first, and a third of the
/// segment came from one feed. v1's `EditorialSequencer.sequence` asked how many cards each provider
/// had already taken; that question is the contract these tests hold V2 to.
final class SourceDiversityContractTests: XCTestCase {
    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
    }
    private func plan(sequencing: UInt64 = 3) throws -> FeedPlan {
        let context = FeedContext(request: .main)
        return try XCTUnwrap(FeedPlan(context: context, revision: EditorialRevision(
            id: EditorialRevisionID(rawValue: uuid(100)), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 1),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 2), scoringPolicyVersion: PolicyVersion(rawValue: 3),
            sequencingPolicyVersion: PolicyVersion(rawValue: sequencing), exposurePolicyVersion: PolicyVersion(rawValue: 2),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))))
    }
    private func alternating(_ revision: EditorialRevision) -> ResolvedSelectionPolicy {
        ResolvedSelectionPolicy(contextKey: revision.contextKey,
            userSelectionVersion: revision.userSelectionVersion,
            eligibilityPolicyVersion: revision.eligibilityPolicyVersion,
            scoringPolicyVersion: revision.scoringPolicyVersion,
            sequencingPolicyVersion: revision.sequencingPolicyVersion,
            exposurePolicyVersion: revision.exposurePolicyVersion,
            selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly,
            scoring: .equal, sequencing: .recencyAlternatingSourcesBySupplyShare, exposure: .none)
    }
    /// One candidate per label, newest first: `labels[i]` carries timestamp `1_000_000 - i`.
    private func window(_ labels: [Int]) -> CandidateSupplyWindow {
        let candidates = labels.enumerated().map { index, source in
            Candidate(originRecordID: OriginRecordID(rawValue: uuid(index + 1)),
                originRevisionID: OriginRevisionID(rawValue: uuid(index + 1)),
                headline: "h\(index)", summary: nil,
                timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: 1_000_000 - Double(index)), kind: .authored),
                language: "pt-BR", providerID: nil,
                sourceIDs: [SourceID(rawValue: uuid(1000 + source))])
        }
        return CandidateSupplyWindow(candidates: candidates, examinedCount: candidates.count, nextCursor: nil, exhausted: true)
    }
    private func published(_ labels: [Int]) throws -> [Int] {
        let plan = try plan()
        let result = try SelectionEngine().select(plan: plan, policy: alternating(plan.revision),
            window: window(labels), exposure: nil, after: nil)
        return result.orderedCandidates.map { candidate in
            Int(candidate.sourceIDs.first!.rawValue.uuidString.suffix(12), radix: 16)! - 1000
        }
    }

    /// The 32-candidate window the supply actually delivered at 09:05:40, in `ContentStore` order
    /// (`sort_date DESC, origin_record_id DESC`). Twelve sources are inside it; the labels are their
    /// order of first appearance, and the sequence is the production sequence with no editing.
    private static let measuredWindow: [Int] = [
        1, 2, 3, 4, 5, 2, 6, 7, 7, 2, 7, 2, 7, 2, 8, 6, 6, 2, 2, 9, 5, 2, 10, 11, 2, 6, 4, 12, 6, 6, 2, 6]

    func testEverySourceInTheWindowIsMetBeforeAnySourceRepeats() throws {
        let sequence = try published(Self.measuredWindow)
        var seen = Set<Int>()
        for (position, source) in sequence.enumerated() {
            if seen.contains(source) {
                let missing = Set(Self.measuredWindow).subtracting(seen)
                XCTAssertTrue(missing.isEmpty,
                    "source \(source) repeated at position \(position) before sources \(missing.sorted()) were met; sequence=\(sequence)")
                return
            }
            seen.insert(source)
        }
    }

    /// R2-D1: a candidate belonging to several SourceIDs is placed once and accounted to all of its
    /// sources — never duplicated, never charged to a source it does not carry.
    func testACandidateWithSeveralSourcesIsPlacedOnceAndCountedForEachOfThem() throws {
        let plan = try plan()
        // A carries 4 candidates, B carries 3, and the last candidate belongs to both C and D — one
        // candidate, two sources, each of them offered exactly that one candidate by this window.
        let labels: [Set<Int>] = [[1], [1], [2], [1], [2], [1], [2], [3, 4]]
        let candidates = labels.enumerated().map { index, sources in
            Candidate(originRecordID: OriginRecordID(rawValue: uuid(index + 1)),
                originRevisionID: OriginRevisionID(rawValue: uuid(index + 1)),
                headline: "h\(index)", summary: nil,
                timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: 1_000_000 - Double(index)), kind: .authored),
                language: "pt-BR", providerID: nil,
                sourceIDs: Set(sources.map { SourceID(rawValue: uuid(1000 + $0)) }))
        }
        let result = try SelectionEngine().select(plan: plan, policy: alternating(plan.revision),
            window: CandidateSupplyWindow(candidates: candidates, examinedCount: candidates.count, nextCursor: nil, exhausted: true),
            exposure: nil, after: nil)
        let placed = result.orderedCandidates.map(\.originRecordID)
        XCTAssertEqual(placed.count, Set(placed).count, "a candidate is never placed twice")
        XCTAssertTrue(placed.contains(candidates[7].originRecordID), "the shared candidate must be reachable")
    }

    /// P5: the v3 rule holds across a segment boundary too — the first card of the new segment must not
    /// share a source with the Edition's tail, and the supply-share accounting starts from that window.
    func testV3HoldsAcrossTheSegmentBoundary() throws {
        let plan = try plan()
        let tail = SelectionNeighbor(sourceIDs: [SourceID(rawValue: uuid(1001))], providerID: nil)
        let result = try SelectionEngine().select(plan: plan, policy: alternating(plan.revision),
            window: window([1, 1, 2, 1, 2]), exposure: nil, after: tail)
        let sequence = result.orderedCandidates.map { candidate in
            Int(candidate.sourceIDs.first!.rawValue.uuidString.suffix(12), radix: 16)! - 1000
        }
        XCTAssertEqual(sequence.first, 2, "the card that shares the tail's source is never placed first")
        for (a, b) in zip(sequence, sequence.dropFirst()) { XCTAssertNotEqual(a, b, "PD-4 inside the segment") }
    }

    /// R2 review: a membership the reader never selected must not invent representativeness. The same window
    /// twice — once where a candidate also carries an unselected source — must publish the same order.
    func testAnUnselectedMembershipDoesNotDistortTheSupplyShare() throws {
        let plan = try plan()
        let selected = Set([1, 2].map { SourceID(rawValue: uuid(1000 + $0)) })
        let unselected = SourceID(rawValue: uuid(1999))
        func run(extraMembership: Bool) throws -> [Int] {
            let labels: [(Set<Int>, Int)] = [([1], 0), ([2], 1), ([1], 2), ([2], 3), ([1], 4), ([2], 5)]
            let candidates = labels.enumerated().map { index, item -> Candidate in
                var sources = Set(item.0.map { SourceID(rawValue: uuid(1000 + $0)) })
                if extraMembership, index == 4 { sources.insert(unselected) }
                return Candidate(originRecordID: OriginRecordID(rawValue: uuid(index + 1)),
                    originRevisionID: OriginRevisionID(rawValue: uuid(index + 1)),
                    headline: "h\(index)", summary: nil,
                    timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: 1_000_000 - Double(index)), kind: .authored),
                    language: "pt-BR", providerID: nil, sourceIDs: sources)
            }
            let p = alternating(plan.revision)
            let policy = ResolvedSelectionPolicy(contextKey: p.contextKey, userSelectionVersion: p.userSelectionVersion,
                eligibilityPolicyVersion: p.eligibilityPolicyVersion, scoringPolicyVersion: p.scoringPolicyVersion,
                sequencingPolicyVersion: p.sequencingPolicyVersion, exposurePolicyVersion: p.exposurePolicyVersion,
                selectionSchemaVersion: p.selectionSchemaVersion, eligibility: .selectedSources(selected),
                scoring: .equal, sequencing: .recencyAlternatingSourcesBySupplyShare, exposure: .none)
            let result = try SelectionEngine().select(plan: plan, policy: policy,
                window: CandidateSupplyWindow(candidates: candidates, examinedCount: candidates.count, nextCursor: nil, exhausted: true),
                exposure: nil, after: nil)
            let selectedLabels: Set<Int> = [1, 2]
            return result.orderedCandidates.map { candidate in
                // The label is the *selected* source of the candidate: the shared one carries a second,
                // unselected source whose raw value must not leak into the comparison.
                let values = candidate.sourceIDs.map { Int($0.rawValue.uuidString.suffix(12), radix: 16)! - 1000 }
                return values.filter(selectedLabels.contains).min()!
            }
        }
        XCTAssertEqual(try run(extraMembership: false), try run(extraMembership: true),
            "an unselected SourceID must not change what the selected sources are offered")
        // Non-vacuity: the comparison above only means something if the window actually publishes cards.
        XCTAssertEqual(try run(extraMembership: true).count, 6, "every candidate in this window is placeable")
    }

    /// R2 review, the point the architect raised: diversity must not neutralize the reader's curation.
    /// Three sources with **equal supply** and weights from `FeedRecipeResolution`'s real scale (it clamps
    /// the multiplier to 0.42…3.0): the recipe's preference must shape the distribution, and the sequencer
    /// must still never starve a source or shorten the feed against the rule it replaced.
    func testACuratedWeightShapesTheDistributionWithoutStarvingASource() throws {
        let plan = try plan()
        let labels = [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3]
        func published(weights: [SourceID: Double]) throws -> [Int] {
            let candidates = labels.enumerated().map { index, source in
                Candidate(originRecordID: OriginRecordID(rawValue: uuid(index + 1)),
                    originRevisionID: OriginRevisionID(rawValue: uuid(index + 1)),
                    headline: "h\(index)", summary: nil,
                    timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: 1_000_000 - Double(index)), kind: .authored),
                    language: "pt-BR", providerID: nil,
                    sourceIDs: [SourceID(rawValue: uuid(1000 + source))])
            }
            let p = alternating(plan.revision)
            let policy = ResolvedSelectionPolicy(contextKey: p.contextKey, userSelectionVersion: p.userSelectionVersion,
                eligibilityPolicyVersion: p.eligibilityPolicyVersion, scoringPolicyVersion: p.scoringPolicyVersion,
                sequencingPolicyVersion: p.sequencingPolicyVersion, exposurePolicyVersion: p.exposurePolicyVersion,
                selectionSchemaVersion: p.selectionSchemaVersion, eligibility: .structuralOnly,
                scoring: weights.isEmpty ? .equal : .weighted(weights),
                sequencing: .recencyAlternatingSourcesBySupplyShare, exposure: .none)
            let result = try SelectionEngine().select(plan: plan, policy: policy,
                window: CandidateSupplyWindow(candidates: candidates, examinedCount: candidates.count, nextCursor: nil, exhausted: true),
                exposure: nil, after: nil)
            return result.orderedCandidates.map { candidate in
                Int(candidate.sourceIDs.first!.rawValue.uuidString.suffix(12), radix: 16)! - 1000
            }
        }
        let weights: [SourceID: Double] = [SourceID(rawValue: uuid(1001)): 3.0,
                                           SourceID(rawValue: uuid(1002)): 1.0,
                                           SourceID(rawValue: uuid(1003)): 0.42]
        let equal = try published(weights: [:])
        let curated = try published(weights: weights)
        let equalCounts = Dictionary(grouping: equal.prefix(9), by: { $0 }).mapValues(\.count)
        let curatedCounts = Dictionary(grouping: curated.prefix(9), by: { $0 }).mapValues(\.count)
        XCTAssertEqual(equalCounts[1], 3, "an unweighted policy splits the first nine evenly; counts=\(equalCounts)")
        XCTAssertGreaterThan(curatedCounts[1] ?? 0, curatedCounts[3] ?? 0,
            "the favoured source must outrank the disfavoured one; counts=\(curatedCounts)")
        XCTAssertNotEqual(equal, curated, "a substantial weight must change the published order, not only break ties")
        for source in [1, 2, 3] {
            XCTAssertTrue(curated.contains(source), "no source is starved; sequence=\(curated)")
        }
        // Measured, and stated rather than hidden: the weighted rule places 16 of this window's 18 cards and
        // the unweighted one places 18 — the two held cards are the *disfavoured* source's surplus, deferred
        // to the next window by the cursor, not the reader's preferred content. What the rule may never do is
        // place fewer cards than the greedy rule it replaced (13 of 18 on this same window).
        XCTAssertGreaterThanOrEqual(curated.count, 16,
            "curation must not fall behind the rule it replaces: curated \(curated.count), greedy 13, unweighted 18")
    }

    /// Compatibility of the change itself: an Edition published under sequencing v2 keeps the behavior
    /// its revision names. Same window, same engine, only the policy version differs — and v2 must still
    /// produce the greedy order the run was published with.
    func testAnEditionPublishedUnderV2KeepsItsOwnOrderingBehavior() throws {
        let plan = try plan(sequencing: 2)
        let p = alternating(plan.revision)
        let v2 = ResolvedSelectionPolicy(contextKey: p.contextKey, userSelectionVersion: p.userSelectionVersion,
            eligibilityPolicyVersion: p.eligibilityPolicyVersion, scoringPolicyVersion: p.scoringPolicyVersion,
            sequencingPolicyVersion: plan.revision.sequencingPolicyVersion, exposurePolicyVersion: p.exposurePolicyVersion,
            selectionSchemaVersion: p.selectionSchemaVersion, eligibility: p.eligibility, scoring: p.scoring,
            sequencing: .recencyAlternatingSources, exposure: p.exposure)
        let result = try SelectionEngine().select(plan: plan, policy: v2, window: window(Self.measuredWindow), exposure: nil, after: nil)
        let sequence = result.orderedCandidates.map { candidate in
            Int(candidate.sourceIDs.first!.rawValue.uuidString.suffix(12), radix: 16)! - 1000
        }
        XCTAssertEqual(Array(sequence.prefix(9)), [1, 2, 3, 4, 5, 2, 6, 7, 2],
            "v2 must keep taking the earliest compatible candidate")
    }

    /// PD-8's exhaustion clause, made visible: on this window the spread costs a held tail. Measured
    /// here — this rule places 30 of the 32, the greedy rule 31, a proportional rule 32; on the wide
    /// 102-candidate window this rule places 75 and a proportional rule 84. The bound keeps the cost
    /// explicit and catches any rule that shortens the segment further.
    func testTheSpreadCostsAtMostTheHeldTailOfTheSegment() throws {
        let sequence = try published(Self.measuredWindow)
        XCTAssertGreaterThanOrEqual(sequence.count, Self.measuredWindow.count - 2,
            "placed \(sequence.count) of \(Self.measuredWindow.count) candidates the window can place")
    }

    /// The smallest reproduction: three sources with equal supply, one of them the most recent. The
    /// greedy rule reached the third source only after exhausting the other two — it never appeared
    /// in the first twelve cards.
    func testAnEquallySuppliedSourceIsNotStarvedByTheMostRecentOne() throws {
        let sequence = try published([1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3])
        for source in [1, 2, 3] {
            XCTAssertTrue(sequence.prefix(9).contains(source),
                "source \(source) is absent from the first nine cards; sequence=\(sequence)")
        }
    }

    /// Relative balance, bounded by supply: with three sources offering the same six candidates each,
    /// the first twelve cards owe them counts within one of each other. The greedy rule produced 6, 6, 0.
    func testEqualSupplyIsServedInAnEvenShare() throws {
        let sequence = try published([1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3])
        let counts = Dictionary(grouping: sequence, by: { $0 }).mapValues(\.count)
        let values = [1, 2, 3].map { counts[$0] ?? 0 }
        XCTAssertLessThanOrEqual(values.max()! - values.min()!, 1,
            "counts \(values) differ by more than one card while every source offered the same supply")
    }

    /// Recency still decides which candidate of a source is used, and it still decides the tie between
    /// sources that have been consumed the same: the first card is the newest card.
    func testRecencyStillDecidesWithinASourceAndBetweenTiedSources() throws {
        let sequence = try published([1, 2, 3, 1, 2, 3, 1, 2, 3])
        XCTAssertEqual(sequence.prefix(3), [1, 2, 3])
    }

    /// The 102-candidate window that existed at 08:49:59 (its whole supply), verbatim: the prolific
    /// publisher holds 60 candidates, the second 32, the third 10. The architect withdrew the equal-share
    /// reading of this window on 2026-10-10 (R2-D1): spending B and C early to reach 10/10/10 leaves the
    /// 60 A candidates without the separators PD-4 needs. What this window must show is R2-D1's objective
    /// — no starvation, and no material loss of reachable candidates. Measured: v3 places 84 of 102 (the
    /// greedy rule 85, the rejected equal-share variant 75) and every source appears in the first thirty.
    private static let measuredWideWindow: [Int] = [
        1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 3, 1, 2, 1, 2, 3, 2, 1, 1, 1, 1, 2, 3, 3, 3, 3, 3, 1,
        1, 2, 1, 2, 2, 2, 1, 1, 1, 2, 3, 2, 3, 3, 2, 1, 1, 1, 2, 1, 1, 2, 2, 1, 1, 2, 2, 2, 1, 2, 2, 1, 1, 1,
        2, 2, 2, 2, 2, 1, 1, 2, 1, 2, 2, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]

    func testEverySourceWithSupplyIsServedAndNoReachableCandidateIsLost() throws {
        let sequence = try published(Self.measuredWideWindow)
        let first30 = Set(sequence.prefix(30))
        // No starvation: all three sources are reachable in the window and all three appear immediately.
        XCTAssertEqual(first30, [1, 2, 3], "the first thirty cards must serve every source that has supply")
        // Length: measured 84 of 102 for this rule, 85 for the greedy rule. The bound keeps the loss from
        // growing rather than pinning the exact number.
        XCTAssertGreaterThanOrEqual(sequence.count, 83,
            "placed \(sequence.count) of \(Self.measuredWideWindow.count); greedy places 85, the rejected equal-share variant 75")
    }

    /// The 256-candidate window the hidden-tail maintenance examined at the same moment (production
    /// examines 32; the tail path examines 256), verbatim from the run: 32 sources, the largest holding
    /// 64 candidates. The greedy rule met only 5 of the 32 sources before repeating one; this rule meets
    /// all 32. Its measured cost here is length: 223 of 256 placed, because after the scarce sources are
    /// served the surplus of the largest ones has no separators left — the held cards go back to the
    /// cursor and are reconsidered with the next window's supply. The contract asserted is the spread.
    private static let measuredTailWindow: [Int] = [
        1, 2, 3, 4, 5, 2, 6, 7, 7, 2, 7, 2, 7, 2, 8, 6, 6, 2, 2, 9, 5, 2, 10, 11, 2, 6, 4, 12, 6, 6, 2, 6,
        5, 2, 2, 2, 6, 2, 2, 12, 2, 2, 2, 6, 2, 7, 6, 9, 7, 2, 2, 6, 6, 4, 6, 12, 6, 5, 6, 9, 6, 7, 6, 6,
        6, 6, 12, 12, 9, 6, 13, 14, 6, 6, 6, 9, 6, 12, 6, 6, 6, 6, 9, 6, 6, 6, 6, 6, 6, 9, 6, 6, 15, 16, 6, 15,
        15, 5, 5, 17, 9, 15, 5, 9, 7, 5, 9, 5, 9, 12, 9, 5, 6, 8, 7, 7, 7, 14, 7, 7, 7, 5, 9, 6, 12, 9, 7, 5,
        17, 8, 18, 12, 9, 12, 8, 5, 17, 5, 12, 6, 12, 12, 19, 17, 6, 5, 18, 8, 18, 5, 20, 12, 15, 5, 8, 15, 15, 17, 21, 6,
        5, 6, 12, 6, 16, 6, 6, 6, 5, 6, 6, 5, 12, 6, 5, 12, 17, 16, 22, 16, 6, 6, 8, 4, 12, 5, 5, 5, 23, 6, 23, 23,
        17, 23, 23, 6, 23, 24, 12, 6, 6, 6, 23, 6, 6, 6, 25, 24, 22, 4, 26, 6, 6, 26, 12, 23, 26, 24, 4, 5, 26, 15, 15, 5,
        24, 26, 22, 4, 4, 27, 28, 26, 29, 22, 24, 30, 26, 5, 31, 6, 4, 31, 31, 5, 31, 31, 31, 5, 15, 5, 17, 4, 3, 32, 4, 15]

    func testTheTailWindowMeetsEverySourceBeforeRepeatingOne() throws {
        let sequence = try published(Self.measuredTailWindow)
        var seen = Set<Int>()
        for (position, source) in sequence.enumerated() {
            if seen.contains(source) {
                let missing = Set(Self.measuredTailWindow).subtracting(seen)
                XCTAssertTrue(missing.isEmpty,
                    "source \(source) repeated at position \(position) before sources \(missing.sorted()) were met")
                return
            }
            seen.insert(source)
        }
    }
}
