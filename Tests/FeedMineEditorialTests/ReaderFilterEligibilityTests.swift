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

    /// Round 9: the filter's value is the language, so a legacy regional code is the same criterion as the
    /// language it belongs to. This path and the discovery pool admit the same sources for the same filter.
    func testALegacyRegionalFilterAdmitsItsWholeLanguage() {
        let regional = ReaderFilterEligibility(filter: ReaderFilter(languages: ["pt-BR"]))
        XCTAssertTrue(regional.admits(candidate(language: "pt-BR")))
        XCTAssertTrue(regional.admits(candidate(language: "pt")), "the language itself")
        XCTAssertTrue(regional.admits(candidate(language: "pt-PT")), "every variant of the same language")
        XCTAssertFalse(regional.admits(candidate(language: "en")))
        XCTAssertEqual(regional.filter.languages, ["pt"], "the regional code is the language, not a second identity")
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

    /// The measured defect of 2026-10-24: a catalogue channel declared `en` and published "Архитектура капитала",
    /// and a reader who had chosen only English received it. A story cannot be speaking a language its own text is
    /// not written in, whoever the reader is — this is integrity, not preference.
    func testADeclaredEnglishStoryWrittenInAnotherScriptIsNeverAdmitted() {
        let russian = candidate(language: "en", headline: "Архитектура капитала",
            summary: "За этой цифрой стоят сделки. +45 454 USDT за неделю на BTC…")
        XCTAssertFalse(ReaderFilterEligibility.unfiltered.admits(russian))
        XCTAssertFalse(ReaderFilterEligibility(filter: ReaderFilter(languages: ["en"])).admits(russian))
        XCTAssertFalse(ReaderFilterEligibility(filter: ReaderFilter(languages: ["en", "pt"])).admits(russian))
        // The same rule answers the reader's own choice from the text, not only from the declaration.
        let mislabeledButLatin = candidate(language: "en", headline: "Cómo EE.UU. se ha convertido en una gerontocracia")
        XCTAssertTrue(ReaderFilterEligibility.unfiltered.admits(mislabeledButLatin),
            "Latin script is no evidence against an English declaration; the minimal rule does not claim to tell them apart")
    }

    /// A Russian story declared as Russian is admitted to a reader who chose Russian too, and rejected for a reader
    /// who chose only English.
    func testARussianStoryFollowsTheDeclaredLanguageAndTheChosenSet() {
        let story = candidate(language: "ru", headline: "Архитектура капитала", summary: "Российская экономика")
        XCTAssertTrue(ReaderFilterEligibility.unfiltered.admits(story))
        XCTAssertTrue(ReaderFilterEligibility(filter: ReaderFilter(languages: ["en", "ru"])).admits(story))
        XCTAssertTrue(ReaderFilterEligibility(filter: ReaderFilter(languages: ["ru"])).admits(story))
        XCTAssertFalse(ReaderFilterEligibility(filter: ReaderFilter(languages: ["en"])).admits(story))
    }
}
