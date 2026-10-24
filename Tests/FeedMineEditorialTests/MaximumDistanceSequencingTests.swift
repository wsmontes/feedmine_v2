import XCTest
import FeedMineDomain
@testable import FeedMineEditorial

/// Pure editorial v6 order: per-choice nearest-prior maximum distance, type → subjects → source, with
/// unknown neutral and PD-4 held by the existing supply report. No persistence or App wiring is involved.
final class MaximumDistanceSequencingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func origin(_ number: Int) -> OriginRecordID {
        OriginRecordID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!)
    }
    private func plan(version: UInt64, request: FeedContextRequest = .main) -> FeedPlan {
        let context = FeedContext(request: request), v = PolicyVersion(rawValue: 1)
        return FeedPlan(context: context, revision: EditorialRevision(
            id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: v,
            eligibilityPolicyVersion: v, scoringPolicyVersion: v,
            sequencingPolicyVersion: PolicyVersion(rawValue: version),
            exposurePolicyVersion: v, selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1)))!
    }
    private func policy(_ plan: FeedPlan,
        scoring: ResolvedSelectionPolicy.ScoringBehavior = .equal) -> ResolvedSelectionPolicy {
        let r = plan.revision
        return ResolvedSelectionPolicy(contextKey: r.contextKey, userSelectionVersion: r.userSelectionVersion,
            eligibilityPolicyVersion: r.eligibilityPolicyVersion, scoringPolicyVersion: r.scoringPolicyVersion,
            sequencingPolicyVersion: r.sequencingPolicyVersion, exposurePolicyVersion: r.exposurePolicyVersion,
            selectionSchemaVersion: r.selectionSchemaVersion, eligibility: .structuralOnly,
            scoring: scoring, sequencing: .maximumDistance, exposure: .none)
    }
    private func candidate(_ number: Int, kind: EditorialMediaKind?, sources: Set<SourceID> = [],
        subjects: [String] = [], time: Double) -> Candidate {
        let topics: CandidateTopicEvidence
        if subjects.isEmpty {
            topics = .absent
        } else {
            let claims = subjects.map {
                DeclaredSubjectClaim(surface: .rssItemCategory, scheme: nil, label: $0)!
            }
            topics = CandidateTopicEvidence(StoryDeclaredSubjects(claims)!)
        }
        return Candidate(originRecordID: origin(number), originRevisionID: OriginRevisionID(),
            headline: "C\(number)", summary: nil,
            timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: time), kind: .observed),
            topics: topics, language: nil, providerID: nil, sourceIDs: sources, mediaKind: kind)
    }
    private func fact(_ kind: EditorialMediaKind?, sources: [SourceID] = [],
        subjects: [String] = []) -> EditorialDiversityFact {
        EditorialDiversityFact(sourceIDs: sources, providerID: nil, subjects: subjects, mediaKind: kind)
    }
    private func window(_ candidates: [Candidate]) -> CandidateSupplyWindow {
        CandidateSupplyWindow(candidates: candidates, examinedCount: candidates.count,
            nextCursor: nil, exhausted: true)
    }
    @discardableResult
    private func select(_ candidates: [Candidate], positions: [EditorialDiversityFact?] = [],
        version: UInt64 = 6, after: SelectionNeighbor? = nil,
        readiness: SelectionReadinessSnapshot? = nil, request: FeedContextRequest = .main,
        scoring: ResolvedSelectionPolicy.ScoringBehavior = .equal) throws -> SelectionResult {
        let plan = plan(version: version, request: request)
        let diversity = positions.isEmpty ? nil : SelectionDiversityContext(publishedPositions: positions)
        return try SelectionEngine().select(plan: plan, policy: policy(plan, scoring: scoring),
            window: window(candidates), exposure: nil, after: after, readiness: readiness, diversity: diversity)
    }
    private func ids(_ result: SelectionResult) -> [OriginRecordID] {
        result.orderedCandidates.map(\.originRecordID)
    }

    /// RED first: the old weight/recency order takes the heavy repeated type; v6 must take the available other type.
    func testNovelTypeBeatsHeavyRepeatedType() throws {
        let a = SourceID(), b = SourceID()
        let repeated = candidate(1, kind: .audio, sources: [a], time: 30)
        let fresh = candidate(2, kind: EditorialMediaKind.none, sources: [b], time: 20)
        let result = try select([repeated, fresh], positions: [fact(.audio)],
            scoring: .weighted([a: 100, b: 1]))
        XCTAssertEqual(ids(result), [fresh.originRecordID, repeated.originRecordID],
            "type distance precedes weight; the repeated type is not chosen for being heavy")
    }

    func testBalancedABCABC() throws {
        let input = [
            candidate(1, kind: .audio, time: 60), candidate(2, kind: .video, time: 50),
            candidate(3, kind: EditorialMediaKind.none, time: 40), candidate(4, kind: .audio, time: 30),
            candidate(5, kind: .video, time: 20), candidate(6, kind: EditorialMediaKind.none, time: 10),
        ]
        XCTAssertEqual(ids(try select(input)), input.map(\.originRecordID),
            "A B C A B C by type")
    }

    func testDynamicChoiceAndCrossSegmentPositions() throws {
        let a = SourceID()
        let positions = [fact(.audio, sources: [a])]
        let none = candidate(1, kind: EditorialMediaKind.none, time: 20)
        let video = candidate(2, kind: .video, time: 10)
        XCTAssertEqual(ids(try select([none, video], positions: positions)),
            [none.originRecordID, video.originRecordID])
    }

    func testHistoryBeyondSixteenAndNilHoles() throws {
        var positions = [EditorialDiversityFact?](repeating: nil, count: 17)
        positions.append(fact(.audio))
        let audio = candidate(1, kind: .audio, time: 20)
        let none = candidate(2, kind: EditorialMediaKind.none, time: 10)
        XCTAssertEqual(ids(try select([audio, none], positions: positions)),
            [none.originRecordID, audio.originRecordID],
            "the far audio at position 18 is known; nil holes count in its distance")
    }

    func testDominantPoolUnavoidableAdjacentTypeIsHonest() throws {
        let positions = [fact(.audio)]
        let firstAudio = candidate(1, kind: .audio, time: 30)
        let secondAudio = candidate(2, kind: .audio, time: 20)
        let onlyOther = candidate(3, kind: EditorialMediaKind.none, time: 10)
        let result = try select([firstAudio, secondAudio, onlyOther], positions: positions)
        XCTAssertEqual(result.orderedCandidates.map(\.mediaKind), [EditorialMediaKind.none, .audio, .audio],
            "the available other type goes first; the remaining audio pair is unavoidable")
    }

    func testMultisourceAdjacencyIsHeldByTheExistingReport() throws {
        let a = SourceID(), c = SourceID(), d = SourceID()
        let first = candidate(1, kind: .audio, sources: [c, d], time: 30)
        let held = candidate(2, kind: EditorialMediaKind.none, sources: [c], time: 20)
        let after = SelectionNeighbor(sourceIDs: [a], providerID: nil)
        let result = try select([first, held], after: after)
        XCTAssertEqual(ids(result), [first.originRecordID],
            "full source-set overlap with the chosen preceding card is held, never placed adjacent")
        XCTAssertEqual(result.supplyReport.nextCursor?.originRecordID, first.originRecordID,
            "the held candidate is reachable through the existing cursor report")
    }

    func testOverlappingSubjectsUseNearestAnyOverlap() throws {
        let positions: [EditorialDiversityFact?] = [
            fact(.audio, subjects: ["space"]), nil, fact(.audio, subjects: ["ocean"]),
        ]
        let near = candidate(1, kind: .audio, subjects: ["space"], time: 30)
        let far = candidate(2, kind: .audio, subjects: ["ocean", "science"], time: 20)
        XCTAssertEqual(ids(try select([near, far], positions: positions)),
            [far.originRecordID, near.originRecordID],
            "ocean at distance 3 wins over space at distance 1; science is not treated as infinity")
    }

    func testSingleSourceContextExemptsOnlyPD4() throws {
        let a = SourceID(), b = SourceID(), c = SourceID()
        let overlapping = candidate(1, kind: EditorialMediaKind.none, sources: [a, b], time: 30)
        let free = candidate(2, kind: .audio, sources: [c], time: 20)
        let after = SelectionNeighbor(sourceIDs: [a], providerID: nil)
        let request = FeedContextRequest.source(SourceID())
        let result = try select([overlapping, free], positions: [fact(.audio, sources: [a])],
            after: after, request: request)
        XCTAssertEqual(ids(result), [overlapping.originRecordID, free.originRecordID],
            "source-only context skips PD4; type distance still acts")
    }

    func testUnknownIsNeutralAndDoesNotDisableKnownComparison() throws {
        let a = SourceID(), b = SourceID()
        let positions = [fact(.audio, sources: [a])]
        let prior = candidate(1, kind: .audio, sources: [a], time: 30)
        let fresh = candidate(2, kind: .audio, sources: [b], time: 20)
        let unknown = candidate(3, kind: nil, sources: [a], time: 10)
        let result = try select([prior, fresh, unknown], positions: positions,
            request: .source(SourceID()))
        XCTAssertEqual(ids(result), [fresh.originRecordID, prior.originRecordID, unknown.originRecordID],
            "unknown stays neutral; the known source comparison eliminates the repeated a")
    }

    func testInputPermutationIsDeterministic() throws {
        let input = [
            candidate(1, kind: .audio, time: 60), candidate(2, kind: .video, time: 50),
            candidate(3, kind: EditorialMediaKind.none, time: 40), candidate(4, kind: .audio, time: 30),
        ]
        let expected = ids(try select(input))
        for permutation in [[input[2], input[0], input[3], input[1]],
                            [input[1], input[3], input[0], input[2]],
                            [input[3], input[2], input[1], input[0]]] {
            XCTAssertEqual(ids(try select(permutation)), expected)
        }
    }

    func testPendingReadinessIsExcludedBeforeV6Choice() throws {
        let positions = [fact(.audio)]
        let novel = candidate(1, kind: EditorialMediaKind.none, time: 30)
        let repeated = candidate(2, kind: .audio, time: 20)
        let requested = [novel.originRevisionID, repeated.originRevisionID]
        let ready = SelectionReadinessSnapshot(requestedRevisionIDs: requested,
            readyRevisionIDs: [repeated.originRevisionID])!
        let result = try select([novel, repeated], positions: positions, readiness: ready)
        XCTAssertEqual(ids(result), [repeated.originRecordID])
    }

    func testOldFactJSONDecodesNilAndNewRoundTripsOptionalKind() throws {
        let old = Data(#"{"sourceIDs":[],"providerID":null,"subjects":[]}"#.utf8)
        let decodedOld = try JSONDecoder().decode(EditorialDiversityFact.self, from: old)
        XCTAssertNil(decodedOld.mediaKind)
        let new = fact(.audio, subjects: ["space"])
        let decodedNew = try JSONDecoder().decode(EditorialDiversityFact.self,
            from: try JSONEncoder().encode(new))
        XCTAssertEqual(decodedNew.mediaKind, .audio)
        XCTAssertEqual(decodedNew.subjects, ["space"])
    }

    func testUnknownFutureVersionDoesNotInheritV6() throws {
        let repeated = candidate(1, kind: .audio, time: 30)
        let novel = candidate(2, kind: EditorialMediaKind.none, time: 20)
        let result = try select([repeated, novel], positions: [fact(.audio)], version: 7)
        XCTAssertEqual(ids(result), [repeated.originRecordID, novel.originRecordID],
            "version 7 keeps the legacy order instead of inheriting v6")
    }
}
