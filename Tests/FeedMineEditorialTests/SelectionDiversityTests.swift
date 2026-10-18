import XCTest
import FeedMineDomain
@testable import FeedMineEditorial

/// R17: multidimensional diversity is a deterministic tie-break after eligibility and relevance, active from
/// sequencing version 5 only, over facts the publication froze (source, provider, story-declared subject). Missing
/// facts are unknown and cannot invent novelty or repetition; a homogeneous offer stays publishable.
final class SelectionDiversityTests: XCTestCase {
    private func plan(sequenceVersion: UInt64) -> FeedPlan {
        let context = FeedContext(request: .main), v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: context.key,
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: v,
            eligibilityPolicyVersion: v, scoringPolicyVersion: v,
            sequencingPolicyVersion: PolicyVersion(rawValue: sequenceVersion),
            exposurePolicyVersion: v, selectionSchemaVersion: SelectionSchemaVersion(rawValue: 1))
        return FeedPlan(context: context, revision: revision)!
    }
    private func policy(_ plan: FeedPlan) -> ResolvedSelectionPolicy {
        let r = plan.revision
        return ResolvedSelectionPolicy(contextKey: r.contextKey, userSelectionVersion: r.userSelectionVersion,
            eligibilityPolicyVersion: r.eligibilityPolicyVersion, scoringPolicyVersion: r.scoringPolicyVersion,
            sequencingPolicyVersion: r.sequencingPolicyVersion, exposurePolicyVersion: r.exposurePolicyVersion,
            selectionSchemaVersion: r.selectionSchemaVersion, eligibility: .structuralOnly, scoring: .equal,
            sequencing: .recencyDescending, exposure: .none)
    }
    private func candidate(_ number: Int, source: SourceID, subject: String?, time: Double) -> Candidate {
        let topics: CandidateTopicEvidence
        if let subject, let claims = StoryDeclaredSubjects([
            DeclaredSubjectClaim(surface: .rssItemCategory, scheme: nil, label: subject)!]) {
            topics = CandidateTopicEvidence(claims)
        } else {
            topics = .absent
        }
        return Candidate(originRecordID: OriginRecordID(rawValue: UUID(
                uuidString: String(format: "00000000-0000-0000-0000-%012x", number))!),
            originRevisionID: OriginRevisionID(), headline: "C\(number)", summary: nil,
            timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: time), kind: .observed),
            topics: topics, language: nil, providerID: nil, sourceIDs: [source])
    }
    private func window(_ candidates: [Candidate]) -> CandidateSupplyWindow {
        .init(candidates: candidates, examinedCount: candidates.count, nextCursor: nil, exhausted: true)
    }
    private func order(_ candidates: [Candidate], version: UInt64,
        diversity: SelectionDiversityContext?) throws -> [OriginRecordID] {
        let p = plan(sequenceVersion: version)
        return try SelectionEngine().select(plan: p, policy: policy(p), window: window(candidates),
            exposure: nil, after: nil, diversity: diversity).orderedCandidates.map(\.originRecordID)
    }

    /// The repeated source/subject in the recent window is deprioritized across a publication seam; the same
    /// selection under sequencing version 4 keeps the old order.
    func testDiversityUsesKnownDimensionsAcrossPublicationSeams() throws {
        let a = SourceID(), b = SourceID()
        let repeated = candidate(1, source: a, subject: "space", time: 10)
        let repeated2 = candidate(2, source: a, subject: "space", time: 9)
        let fresh = candidate(3, source: b, subject: "ocean", time: 8)
        let fact = EditorialDiversityFact(sourceIDs: [a], providerID: nil, subjects: ["space"])
        let diversity = try XCTUnwrap(SelectionDiversityContext(recent: [fact]))
        XCTAssertEqual(try order([repeated, repeated2, fresh], version: 5, diversity: diversity), [
            fresh.originRecordID, repeated.originRecordID, repeated2.originRecordID,
        ], "a fonte/assunto repetido cede lugar ao novo, e o empate antigo se mantém")
        XCTAssertEqual(try order([repeated, repeated2, fresh], version: 4, diversity: diversity), [
            repeated.originRecordID, repeated2.originRecordID, fresh.originRecordID,
        ], "a versão 4 preserva exatamente a ordem anterior")
        XCTAssertEqual(try order([repeated, repeated2, fresh], version: 5, diversity: nil), [
            repeated.originRecordID, repeated2.originRecordID, fresh.originRecordID,
        ], "sem contexto, o comportamento anterior")
    }

    /// A homogeneous offer is still publishable: diversity reorders, it never withholds.
    func testHomogeneousSupplyRemainsPublishable() throws {
        let a = SourceID()
        let one = candidate(1, source: a, subject: "space", time: 10)
        let two = candidate(2, source: a, subject: "space", time: 9)
        let three = candidate(3, source: a, subject: "space", time: 8)
        let diversity = try XCTUnwrap(SelectionDiversityContext(recent: [
            EditorialDiversityFact(sourceIDs: [a], providerID: nil, subjects: ["space"])]))
        let ordered = try order([one, two, three], version: 5, diversity: diversity)
        XCTAssertEqual(ordered.count, 3, "a oferta homogênea continua publicável")
        XCTAssertEqual(ordered, [one, two, three].map(\.originRecordID))
    }

    /// Missing metadata is unknown: a candidate without declared subjects gets neither a novelty advantage nor a
    /// repetition penalty on that dimension — the timestamp decides.
    func testMissingMetadataDoesNotInventNovelty() throws {
        let a = SourceID()
        let unknown = candidate(1, source: a, subject: nil, time: 10)
        let known = candidate(2, source: a, subject: "space", time: 9)
        let diversity = try XCTUnwrap(SelectionDiversityContext(recent: [
            EditorialDiversityFact(sourceIDs: [a], providerID: nil, subjects: ["space"])]))
        // Source repeats for both, so that dimension ties; the subject dimension is skipped because one side is
        // unknown; recency (10 > 9) decides, not the missing metadata.
        XCTAssertEqual(try order([unknown, known], version: 5, diversity: diversity),
            [unknown.originRecordID, known.originRecordID])
        // With the unknown candidate older, recency decides the other way — no invented advantage.
        let olderUnknown = candidate(3, source: a, subject: nil, time: 8)
        XCTAssertEqual(try order([olderUnknown, known], version: 5, diversity: diversity),
            [known.originRecordID, olderUnknown.originRecordID])
    }
}
