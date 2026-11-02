import Foundation
import XCTest
import FeedMineDomain
import FeedMineEditorial

/// New-publication contract. Revision 6 remains covered by its existing historical suite.
final class FM59SelectionVarietyTests: XCTestCase {
    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
    }
    private func source(_ number: Int) -> SourceID { .init(rawValue: uuid(20_000 + number)) }
    private func candidate(_ number: Int, source: Int, kind: EditorialMediaKind, time: Double) -> Candidate {
        Candidate(originRecordID: .init(rawValue: uuid(number)), originRevisionID: .init(rawValue: uuid(10_000 + number)),
            headline: "Story \(number)", summary: nil,
            timestamp: .init(value: Date(timeIntervalSince1970: time), kind: .authored),
            language: "pt", providerID: nil, sourceIDs: [self.source(source)], mediaKind: kind)
    }
    private func select(_ candidates: [Candidate], positions: [EditorialDiversityFact?] = [],
        request: FeedContextRequest = .main, limit: Int? = 50) throws -> SelectionResult {
        let context = FeedContext(request: request), v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: .init(rawValue: 7),
            exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let plan = FeedPlan(context: context, revision: revision)!
        let policy = ResolvedSelectionPolicy(contextKey: context.key, userSelectionVersion: v,
            eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: revision.sequencingPolicyVersion,
            exposurePolicyVersion: v, selectionSchemaVersion: revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .maximumDistance, exposure: .none)
        let diversity = positions.isEmpty ? nil : SelectionDiversityContext(publishedPositions: positions)
        return try SelectionEngine().select(plan: plan, policy: policy,
            window: .init(candidates: candidates, examinedCount: candidates.count, nextCursor: nil, exhausted: true),
            exposure: nil, after: nil, diversity: diversity, publicationLimit: limit)
    }
    private func richSupply(textSources: Range<Int> = 0..<40) -> [Candidate] {
        var result: [Candidate] = []
        var number = 1
        // Scarce formats have many recent items. Their type novelty must not consume most source opportunities.
        for (supplier, kind) in [(100, EditorialMediaKind.audio), (101, .audio), (102, .video)] {
            for _ in 0..<40 {
                result.append(candidate(number, source: supplier, kind: kind, time: Double(30_000-number)))
                number += 1
            }
        }
        for supplier in textSources {
            result.append(candidate(number, source: supplier, kind: EditorialMediaKind.none, time: Double(20_000-number)))
            number += 1
        }
        return result
    }
    private func sources(_ candidates: ArraySlice<Candidate>) -> Set<SourceID> {
        Set(candidates.flatMap(\.sourceIDs))
    }
    private func assertNoSourceAdjacency(_ candidates: [Candidate], previous: Set<SourceID> = [],
        file: StaticString = #filePath, line: UInt = #line) {
        var prior = previous
        for item in candidates {
            XCTAssertTrue(prior.isDisjoint(with: item.sourceIDs), "Source repetition at a publication seam", file: file, line: line)
            prior = item.sourceIDs
        }
    }

    func testFirstFiftyHaveFortySuppliersInsteadOfCyclingScarceFormatSuppliers() throws {
        let input = richSupply()
        let selected = try select(input).orderedCandidates
        XCTAssertEqual(selected.count, 50, "Rich supply must not be withheld to manufacture diversity")
        XCTAssertGreaterThanOrEqual(sources(selected.prefix(12)).count, 10, "The opening itself must be diverse")
        XCTAssertGreaterThanOrEqual(sources(selected.prefix(50)).count, 40,
            "Forty-three ready suppliers are not satisfied by fifty items from the same few suppliers")
        XCTAssertEqual(Set(selected.compactMap(\.mediaKind)), [EditorialMediaKind.none, .audio, .video])
        XCTAssertEqual(Set(selected.map(\.originRecordID)).count, selected.count)
        assertNoSourceAdjacency(selected)
    }

    func testContinuationDoesNotSpendItsWindowOnAlreadyServedScarceFormatSuppliers() throws {
        // Frozen previous segment ends with supplier102; input offers40 not-yet-served text suppliers.
        let positions: [EditorialDiversityFact?] = [102, 101, 100].map {
            EditorialDiversityFact(sourceIDs: [source($0)], providerID: nil, subjects: [],
                mediaKind: $0 == 102 ? .video : .audio)
        }
        let selected = try select(richSupply(textSources: 40..<80), positions: positions).orderedCandidates
        let newSources = Set((40..<80).map(source))
        XCTAssertGreaterThanOrEqual(sources(selected.prefix(50)).count, 40)
        XCTAssertGreaterThanOrEqual(sources(selected.prefix(50)).intersection(newSources).count, 37,
            "New compatible suppliers remain available beyond a segment boundary")
        assertNoSourceAdjacency(selected, previous: [source(102)])
    }

    func testUnknownProviderAndTopicFactsDoNotBecomeInventedDiversity() throws {
        let input = (1...35).map { candidate($0, source: $0, kind: EditorialMediaKind.none, time: Double(100-$0)) }
        let selected = try select(input).orderedCandidates
        XCTAssertEqual(sources(selected.prefix(50)), Set(input.flatMap(\.sourceIDs)))
        XCTAssertTrue(selected.allSatisfy { $0.providerID == nil && $0.topics.identities.isEmpty })
        XCTAssertEqual(Set(selected.compactMap(\.mediaKind)), [EditorialMediaKind.none],
            "Genuine text-only supply is not relabeled to complete an audio/video cycle")
    }

    func testGenuineSingleSourceContextPublishesDistinctStoriesWithoutInventingSuppliers() throws {
        let input = (1...3).map { candidate($0, source: 1, kind: .audio, time: Double(100-$0)) }
        let selected = try select(input, request: .source(source(1))).orderedCandidates
        XCTAssertEqual(Set(selected.map(\.originRecordID)), Set(input.map(\.originRecordID)))
        XCTAssertEqual(sources(selected.prefix(50)), [source(1)])
        XCTAssertEqual(Set(selected.compactMap(\.mediaKind)), [.audio])
    }
}
