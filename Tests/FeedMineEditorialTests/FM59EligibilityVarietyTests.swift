import Foundation
import XCTest
import FeedMineDomain
import FeedMineEditorial

final class FM59EligibilityVarietyTests: XCTestCase {
    private func candidate(kind: EditorialMediaKind?, language: String? = "pt-BR",
        sources: Set<SourceID> = [], title: String = "Uma descoberta sobre ciência") -> Candidate {
        Candidate(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(), headline: title,
            summary: nil, timestamp: .init(value: Date(timeIntervalSince1970: 1), kind: .authored),
            language: language, providerID: nil, sourceIDs: sources,
            // Every kind has an image locator: a cover cannot make audio/video satisfy Articles.
            primaryMediaLocator: "https://images.example.test/cover.jpg", mediaKind: kind)
    }

    func testSingleTypeFiltersMatchActualPayloadAndRejectUnknownKind() {
        let cases: [(ReaderContentType, EditorialMediaKind)] = [(.text, .none), (.audio, .audio), (.video, .video)]
        for (filterKind, matchingPayload) in cases {
            let eligibility = ReaderFilterEligibility(filter: ReaderFilter(languages: ["pt"], contentType: filterKind))
            for payload in [EditorialMediaKind.none, .audio, .video] {
                XCTAssertEqual(eligibility.admits(candidate(kind: payload)), payload == matchingPayload,
                    "\(filterKind) must answer actual item payload \(payload), not source labels or artwork")
            }
            XCTAssertFalse(eligibility.admits(candidate(kind: nil)), "Unknown is not a known no-playback article")
        }
    }

    func testPairedTypeFilterAllowsTextAndVideoButNeverAudioOrUnknown() {
        let filter = ReaderFilter(languages: ["pt"], mediaTypes: [.article, .video])
        let eligibility = ReaderFilterEligibility(filter: filter)
        XCTAssertTrue(eligibility.admits(candidate(kind: EditorialMediaKind.none)))
        XCTAssertTrue(eligibility.admits(candidate(kind: .video)))
        XCTAssertFalse(eligibility.admits(candidate(kind: .audio)))
        XCTAssertFalse(eligibility.admits(candidate(kind: nil)))
    }

    func testSourceLanguageAndTypeRestrictionsComposeWithoutBroadeningTheSelection() {
        let selected = SourceID(), other = SourceID()
        let eligibility = ReaderFilterEligibility(filter: ReaderFilter(languages: ["pt"], contentType: .video),
            restrictedSourceIDs: [selected])
        XCTAssertTrue(eligibility.admits(candidate(kind: .video, sources: [selected])))
        XCTAssertFalse(eligibility.admits(candidate(kind: .video, sources: [other])))
        XCTAssertFalse(eligibility.admits(candidate(kind: .audio, sources: [selected])))
        XCTAssertFalse(eligibility.admits(candidate(kind: .video, language: "en", sources: [selected])))
        XCTAssertFalse(eligibility.admits(candidate(kind: .video, language: nil, sources: [selected])))
    }

    func testUnknownContradictoryAndWrongLanguageRemainRejectedForVideo() {
        let eligibility = ReaderFilterEligibility(filter: ReaderFilter(languages: ["pt"], contentType: .video))
        XCTAssertFalse(eligibility.admits(candidate(kind: .video, language: nil)))
        XCTAssertFalse(eligibility.admits(candidate(kind: .video, language: " ")))
        XCTAssertFalse(eligibility.admits(candidate(kind: .video, language: "ja", title: "日本の科学と文化について")))
        XCTAssertFalse(eligibility.admits(candidate(kind: .video, language: "pt", title: "日本の科学と文化について")),
            "A source/catalogue Portuguese label cannot legitimize incompatible actual item text")
        XCTAssertTrue(eligibility.admits(candidate(kind: .video, language: "pt-PT")))
    }

    func testUnrestrictedKindDoesNotInventAnEvidenceRequirement() {
        let eligibility = ReaderFilterEligibility(filter: ReaderFilter(languages: ["pt"]))
        for payload in [EditorialMediaKind.none, .audio, .video] {
            XCTAssertTrue(eligibility.admits(candidate(kind: payload)))
        }
        XCTAssertTrue(eligibility.admits(candidate(kind: nil)), "No kind filter is different from an Articles filter")
        let explicitlyUnenforced = ReaderFilterEligibility(filter: ReaderFilter(contentType: .video), enforced: [])
        XCTAssertTrue(explicitlyUnenforced.admits(candidate(kind: .audio)))
    }
}
