import XCTest
import Foundation
import FeedMineDomain
@testable import FeedMineEditorial

/// T6 enforcement: the criteria today's canonical data can answer, and the honesty rule that a criterion
/// this build cannot answer is never consulted.
final class ReaderFilterEligibilityTests: XCTestCase {
    private func candidate(language: String? = "en", headline: String? = "Quarterly earnings report",
        summary: String? = nil, sourceIDs: Set<SourceID> = []) -> Candidate {
        Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(), headline: headline,
            summary: summary, timestamp: CandidateTimestamp(value: Date(timeIntervalSince1970: 1), kind: .observed),
            language: language, providerID: nil, sourceIDs: sourceIDs)
    }

    func testUnfilteredEligibilityAdmitsEverything() {
        let eligibility = ReaderFilterEligibility.unfiltered
        XCTAssertTrue(eligibility.isUnrestricted)
        XCTAssertTrue(eligibility.admits(candidate(language: nil, headline: nil)))
        XCTAssertTrue(eligibility.admits(candidate(language: "pt", headline: "Crise no tribunal")))
    }

    /// A language criterion is satisfied by the same language, including a regional variant; a candidate with
    /// no language at all fails it — the criterion is never satisfied by inventing a missing fact.
    func testLanguageCriterionIsNeverSatisfiedByMissingMetadata() {
        let eligibility = ReaderFilterEligibility(filter: ReaderFilter(languages: ["pt", "en"]))
        XCTAssertTrue(eligibility.admits(candidate(language: "pt")))
        XCTAssertTrue(eligibility.admits(candidate(language: "pt-BR")))
        XCTAssertTrue(eligibility.admits(candidate(language: "EN")))
        XCTAssertFalse(eligibility.admits(candidate(language: "fr")))
        XCTAssertFalse(eligibility.admits(candidate(language: nil)),
            "an unknown language cannot pass a language filter")
        XCTAssertFalse(eligibility.admits(candidate(language: "   ")))
        // Without the criterion being enforced, the language is not consulted at all.
        let unenforced = ReaderFilterEligibility(filter: ReaderFilter(languages: ["pt"]), enforced: [])
        XCTAssertTrue(unenforced.admits(candidate(language: "fr")))
    }

    /// Mood uses V1's rule: a keyword test over the headline (`FeedLoader.MoodFilter`).
    func testMoodCriterionUsesV1KeywordRuleOnTheHeadline() {
        let serious = ReaderFilterEligibility(filter: ReaderFilter(mood: .serious))
        XCTAssertTrue(serious.admits(candidate(headline: "Court ruling bans the app")))
        XCTAssertFalse(serious.admits(candidate(headline: "An adorable puppy")))
        XCTAssertFalse(serious.admits(candidate(headline: nil)), "no title, no mood match")
        let inspiring = ReaderFilterEligibility(filter: ReaderFilter(mood: .inspiring))
        XCTAssertTrue(inspiring.admits(candidate(headline: "Scientists discovered a cure")))
        XCTAssertFalse(inspiring.admits(candidate(headline: "Quarterly earnings report")))
    }

    /// Exclusions hide a card by its readable text and are consulted whenever they carry rules.
    func testExclusionsHideByHeadlineOrSummary() {
        let eligibility = ReaderFilterEligibility(filter: ReaderFilter(
            exclusions: ReaderContentExclusions(isEnabled: true, rules: ["crypto", " casino "])))
        XCTAssertFalse(eligibility.admits(candidate(headline: "The CRYPTO market")))
        XCTAssertFalse(eligibility.admits(candidate(headline: "Markets", summary: "A casino story")))
        XCTAssertTrue(eligibility.admits(candidate(headline: "Markets", summary: "A bank story")))
        // Disabled or empty rule sets hide nothing.
        XCTAssertTrue(ReaderFilterEligibility(filter: ReaderFilter()).admits(candidate(headline: "Crypto")))
        XCTAssertTrue(ReaderFilterEligibility(filter: ReaderFilter(
            exclusions: ReaderContentExclusions(isEnabled: true, rules: []))).admits(candidate(headline: "Crypto")))
    }

    /// A criterion this build cannot answer is not consulted: the UI refuses to set it, so enforcement must
    /// not behave as if metadata existed.
    func testUnanswerableCriteriaAreNotConsulted() {
        let taxonomyOnly = ReaderFilter(regionIDs: ["us"], taxonomyNodeIDs: ["tech"], contentType: .video)
        let eligibility = ReaderFilterEligibility(filter: taxonomyOnly,
            enforced: Set(ReaderFilterCriterion.enforceable))
        XCTAssertTrue(eligibility.admits(candidate(language: "fr", headline: "Anything")),
            "taxonomy, region and content type have no metadata to answer them yet")
        XCTAssertEqual(Set(ReaderFilterCriterion.enforceable), [.preset, .languages, .mood])
    }

    /// A restricted source set excludes a candidate that belongs only to other sources, and a candidate with
    /// unknown memberships is not excluded by this rule (the acquisition boundary already scoped the query).
    func testSourceRestrictionExcludesDisjointCandidates() {
        let mine = SourceID(), other = SourceID()
        let eligibility = ReaderFilterEligibility(filter: .unrestricted, restrictedSourceIDs: [mine])
        XCTAssertTrue(eligibility.admits(candidate(sourceIDs: [mine])))
        XCTAssertTrue(eligibility.admits(candidate(sourceIDs: [mine, other])))
        XCTAssertFalse(eligibility.admits(candidate(sourceIDs: [other])))
        XCTAssertTrue(eligibility.admits(candidate(sourceIDs: [])))
        XCTAssertFalse(eligibility.isUnrestricted)
        XCTAssertTrue(ReaderFilterEligibility(filter: .unrestricted, restrictedSourceIDs: []).isUnrestricted)
    }
}
