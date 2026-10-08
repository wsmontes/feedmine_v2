import XCTest
import FeedMineDomain
@testable import FeedMineEditorial

final class SelectionEngineTests: XCTestCase {
    private func uuid(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!
    }
    private func candidate(_ origin: Int, revision: Int? = nil, time: Double = 100,
        kind: CandidateTimestampKind = .authored) -> Candidate {
        Candidate(originRecordID: OriginRecordID(rawValue: uuid(origin)),
            originRevisionID: OriginRevisionID(rawValue: uuid(revision ?? origin)),
            headline: origin == 1 ? nil : "", summary: "summary \(origin)",
            timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: time), kind: kind),
            language: "pt-BR", providerID: ProviderID(rawValue: uuid(99)))
    }
    private func plan(catalog: UInt64 = 1) throws -> FeedPlan {
        let context = FeedContext(request: .main)
        return try XCTUnwrap(FeedPlan(context: context, revision: EditorialRevision(
            id: EditorialRevisionID(rawValue: uuid(100)), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: catalog), userSelectionVersion: PolicyVersion(rawValue: 1),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 2), scoringPolicyVersion: PolicyVersion(rawValue: 3),
            sequencingPolicyVersion: PolicyVersion(rawValue: 4), exposurePolicyVersion: PolicyVersion(rawValue: 5),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 6))))
    }
    private func policy(_ revision: EditorialRevision, mismatch: Int? = nil) -> ResolvedSelectionPolicy {
        ResolvedSelectionPolicy(contextKey: mismatch == 0 ? ContextKey(request: .source(SourceID(rawValue: uuid(9)))) : revision.contextKey,
            userSelectionVersion: mismatch == 1 ? PolicyVersion(rawValue: 101) : revision.userSelectionVersion,
            eligibilityPolicyVersion: mismatch == 2 ? PolicyVersion(rawValue: 102) : revision.eligibilityPolicyVersion,
            scoringPolicyVersion: mismatch == 3 ? PolicyVersion(rawValue: 103) : revision.scoringPolicyVersion,
            sequencingPolicyVersion: mismatch == 4 ? PolicyVersion(rawValue: 104) : revision.sequencingPolicyVersion,
            exposurePolicyVersion: mismatch == 5 ? PolicyVersion(rawValue: 105) : revision.exposurePolicyVersion,
            selectionSchemaVersion: mismatch == 6 ? SelectionSchemaVersion(rawValue: 106) : revision.selectionSchemaVersion,
            eligibility: .structuralOnly, scoring: .equal, sequencing: .recencyDescending, exposure: .none)
    }
    private func window(_ candidates: [Candidate], count: Int = 27,
        cursor: CandidateSupplyCursor? = nil, exhausted: Bool = false) -> CandidateSupplyWindow {
        CandidateSupplyWindow(candidates: candidates, examinedCount: count, nextCursor: cursor, exhausted: exhausted)
    }
    private func assertError(_ expected: SelectionError, plan: FeedPlan, policy: ResolvedSelectionPolicy,
        candidates: [Candidate] = [], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try SelectionEngine().select(plan: plan, policy: policy, window: window(candidates)), file: file, line: line) {
            XCTAssertEqual($0 as? SelectionError, expected, file: file, line: line)
        }
    }

    func testMatchingNominalPolicyAndExplicitBaselineBehaviors() throws {
        let plan = try plan(), policy = policy(plan.revision), input = [candidate(1)]
        XCTAssertEqual(policy.eligibility, .structuralOnly)
        XCTAssertEqual(policy.scoring, .equal)
        XCTAssertEqual(policy.sequencing, .recencyDescending)
        XCTAssertEqual(policy.exposure, .none)
        let result = try SelectionEngine().select(plan: plan, policy: policy, window: window(input))
        XCTAssertEqual(result.editorialRevision, plan.revision)
        XCTAssertEqual(result.orderedCandidates, input)
    }

    func testEachNominalIdentityFieldMismatchIsRejected() throws {
        let plan = try plan()
        for field in 0...6 {
            assertError(.policyMismatch, plan: plan, policy: policy(plan.revision, mismatch: field))
        }
    }

    func testCatalogGenerationIsExcludedFromExecutablePolicyGuard() throws {
        let first = try plan(catalog: 1), second = try plan(catalog: 900)
        let policy = policy(first.revision)
        for plan in [first, second] {
            let result = try SelectionEngine().select(plan: plan, policy: policy, window: window([candidate(1)]))
            XCTAssertEqual(result.editorialRevision, plan.revision)
        }
        XCTAssertNotEqual(first.revision, second.revision)
    }

    func testDistinctTimestampRecencyDescendingFromShuffledInput() throws {
        let plan = try plan()
        let oldest = candidate(3, time: 10), middle = candidate(1, time: 20), newest = candidate(2, time: 30)
        let result = try SelectionEngine().select(plan: plan, policy: policy(plan.revision), window: window([middle, oldest, newest]))
        XCTAssertEqual(result.orderedCandidates, [newest, middle, oldest])
    }

    func testTimestampTieUsesKnownOriginIDsDescendingAndPreservesKind() throws {
        let plan = try plan()
        let one = candidate(1, kind: .authored), two = candidate(2, kind: .observed), three = candidate(3, kind: .authored)
        let result = try SelectionEngine().select(plan: plan, policy: policy(plan.revision), window: window([two, one, three]))
        XCTAssertEqual(result.orderedCandidates, [three, two, one])
        XCTAssertEqual(result.orderedCandidates.map(\.timestamp.kind), [.authored, .observed, .authored])
    }

    func testInputPermutationProducesExactlyEqualResult() throws {
        let plan = try plan(), policy = policy(plan.revision)
        let a = candidate(1, time: 30), b = candidate(2, time: 10), c = candidate(3, time: 30, kind: .observed)
        let cursor = CandidateSupplyCursor(sortDate: Date(timeIntervalSince1970: 5), originRecordID: OriginRecordID(rawValue: uuid(8)))
        let engine = SelectionEngine()
        let expected = try engine.select(plan: plan, policy: policy, window: window([a, b, c], cursor: cursor))
        for permutation in [[c, a, b], [b, c, a], [a, c, b], [b, a, c], [c, b, a]] {
            XCTAssertEqual(try engine.select(plan: plan, policy: policy, window: window(permutation, cursor: cursor)), expected)
        }
    }

    func testDuplicateOriginWithDifferentRevisionAndTimestampAndExactDuplicateRejected() throws {
        let plan = try plan(), first = candidate(1, revision: 10), second = candidate(1, revision: 11, time: 200, kind: .observed)
        assertError(.duplicateCandidateIdentity, plan: plan, policy: policy(plan.revision), candidates: [first, second])
        assertError(.duplicateCandidateIdentity, plan: plan, policy: policy(plan.revision), candidates: [first, first])
    }

    func testPolicyMismatchPrecedesDuplicateValidation() throws {
        let plan = try plan(), candidate = candidate(1)
        assertError(.policyMismatch, plan: plan, policy: policy(plan.revision, mismatch: 0), candidates: [candidate, candidate])
    }

    func testEmptyNonExhaustedWindowPreservesExaminedProgressFacts() throws {
        let plan = try plan()
        let cursor = CandidateSupplyCursor(sortDate: Date(timeIntervalSince1970: 50), originRecordID: OriginRecordID(rawValue: uuid(8)))
        let result = try SelectionEngine().select(plan: plan, policy: policy(plan.revision), window: window([], count: 50, cursor: cursor))
        XCTAssertEqual(result.orderedCandidates, [])
        XCTAssertEqual(result.supplyReport, SelectionSupplyReport(examinedCount: 50, nextCursor: cursor, exhausted: false))
    }

    func testExhaustedEmptyWindowSucceeds() throws {
        let plan = try plan()
        let result = try SelectionEngine().select(plan: plan, policy: policy(plan.revision), window: window([], count: 0, exhausted: true))
        XCTAssertEqual(result.orderedCandidates, [])
        XCTAssertEqual(result.supplyReport, SelectionSupplyReport(examinedCount: 0, nextCursor: nil, exhausted: true))
    }

    func testShortExhaustedSupplyReturnsOnlySuppliedValuesWithoutDuplicates() throws {
        let plan = try plan(), input = [candidate(1), candidate(3), candidate(2)]
        let result = try SelectionEngine().select(plan: plan, policy: policy(plan.revision), window: window(input, count: 3, exhausted: true))
        XCTAssertEqual(result.orderedCandidates, [input[1], input[2], input[0]])
        XCTAssertEqual(result.orderedCandidates.count, 3)
        XCTAssertEqual(Set(result.orderedCandidates.map(\.originRecordID)).count, 3)
        XCTAssertEqual(result.supplyReport, SelectionSupplyReport(examinedCount: 3, nextCursor: nil, exhausted: true))
    }

    func testSupplyFactsAreNotRecomputedFromCandidateCount() throws {
        let plan = try plan()
        let cursor = CandidateSupplyCursor(sortDate: Date(timeIntervalSince1970: 50), originRecordID: OriginRecordID(rawValue: uuid(8)))
        let result = try SelectionEngine().select(plan: plan, policy: policy(plan.revision), window: window([candidate(1), candidate(2)], count: 27, cursor: cursor))
        XCTAssertEqual(result.orderedCandidates.count, 2)
        XCTAssertEqual(result.supplyReport, SelectionSupplyReport(examinedCount: 27, nextCursor: cursor, exhausted: false))
    }
}
