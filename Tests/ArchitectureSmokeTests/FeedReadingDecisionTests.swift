//
// File: FeedReadingDecisionTests.swift
// Module: ArchitectureSmokeTests
//
// The rule that decides between reading locally and reading on the site. It is pinned here because it is the
// boundary the architect fixed (3.000 characters *opens* the reader; it never claims completeness) and because
// the counting itself is a plausible defect: the threshold is characters as a reader sees them, not bytes.
import XCTest
import FeedMineUI

final class FeedReadingDecisionTests: XCTestCase {
    private let url = URL(string: "https://example.test/article")!

    private func target(body: String? = nil, summary: String? = nil, siteURL: URL?) -> FeedReadingTarget? {
        FeedReadingDecision.target(body: body, summary: summary, sourceName: "Fonte",
            headline: "Manchete", publishedAt: nil, siteURL: siteURL)
    }

    func testTheSourceBodyWinsOverALongerSummary() {
        let long = String(repeating: "s", count: 5_000)
        guard case .local(let content) = target(body: "Corpo do feed", summary: long, siteURL: url) else {
            return XCTFail("a stored body must be read locally")
        }
        XCTAssertEqual(content.origin, .sourceBody)
        XCTAssertEqual(content.text, "Corpo do feed", "the body is what the source published, not the summary")
        XCTAssertEqual(content.siteURL, url, "the local reader still offers the explicit way out to the site")
    }

    func testABodyOfOnlyWhitespaceIsNotText() {
        guard case .local(let content) = target(body: "  \n\t ", summary: String(repeating: "s", count: 3_000),
            siteURL: url) else {
            return XCTFail("a blank body must fall through to the summary rule")
        }
        XCTAssertEqual(content.origin, .sourceSummary)
    }

    func testTheThresholdOpensTheReaderAtExactlyThreeThousandCharacters() {
        let atThreshold = String(repeating: "a", count: 3_000)
        guard case .local(let content) = target(summary: atThreshold, siteURL: url) else {
            return XCTFail("3.000 characters is the published parameter of opening")
        }
        XCTAssertEqual(content.origin, .sourceSummary)
        XCTAssertEqual(content.origin.label, "Resumo fornecido pela fonte")

        guard case .site(let fallback) = target(summary: String(repeating: "a", count: 2_999), siteURL: url) else {
            return XCTFail("just below the threshold the site is the primary action")
        }
        XCTAssertEqual(fallback, url)
    }

    func testTheThresholdCountsCharactersAsAReaderSeesThem() {
        // A reader counts "ção" as three characters; a byte count would call this 3.000 and open the reader early.
        let accented = String(repeating: "ã", count: 2_999)
        XCTAssertEqual(accented.count, 2_999, "the fixture itself must be 2.999 characters")
        XCTAssertGreaterThan(accented.utf8.count, 3_000, "and more than 3.000 bytes, so a byte count would differ")
        guard case .site = target(summary: accented, siteURL: url) else {
            return XCTFail("2.999 characters is below the threshold whatever the encoding costs")
        }
    }

    func testATeaserKeepsTheSiteAsItsPrimaryAction() {
        guard case .site(let link) = target(summary: "So easy!", siteURL: url) else {
            return XCTFail("a short summary is a teaser: no intermediate screen")
        }
        XCTAssertEqual(link, url)
    }

    /// A teaser's text is not nothing. Without an address the stored summary is the only reading the card has, so
    /// the reader opens locally with it instead of the tap ending in no target. This is also the saved/offline
    /// case: `AppComposition.openSaved` routes a saved card through this same decision, and its text must stay
    /// readable when the address no longer resolves.
    func testATeaserWithoutAnAddressKeepsItsOwnTextLocally() {
        guard case .local(let content) = target(summary: "So easy!", siteURL: nil) else {
            return XCTFail("stored text with no address must not drop the reader with no target")
        }
        XCTAssertEqual(content.origin, .sourceSummary)
        XCTAssertEqual(content.text, "So easy!", "the reader holds exactly the text the app has, and no more")
        XCTAssertNil(content.siteURL, "no address means no site action and no promise about the site")
        XCTAssertTrue(content.isPartial, "completeness is still unconfirmed, so the note says so")
    }

    /// The address can exist and still be unusable. A scheme the in-app browser cannot open is not a door, and it
    /// must not cost the reader the text the app already holds.
    func testASavedArticleWithAnUnusableAddressReadsItsStoredTextLocally() {
        guard case .local(let content) = target(summary: "Guardado para ler offline.",
            siteURL: URL(string: "mailto:redacao@example.test")) else {
            return XCTFail("an address the browser cannot open is not a reason to lose the saved text")
        }
        XCTAssertEqual(content.text, "Guardado para ler offline.")
        XCTAssertNil(content.siteURL, "an address the app cannot open is not offered, because it cannot work")

        guard case .local(let body) = target(body: "Corpo do feed",
            siteURL: URL(string: "mailto:redacao@example.test")) else {
            return XCTFail("the stored body is readable whatever the address does")
        }
        XCTAssertEqual(body.origin, .sourceBody)
        XCTAssertNil(body.siteURL)
    }

    func testOnlyHTTPAddressesWithAHostAreDoors() {
        XCTAssertEqual(FeedReadingDecision.usableSiteURL(url), url)
        XCTAssertEqual(FeedReadingDecision.usableSiteURL(URL(string: "http://example.test/a")),
            URL(string: "http://example.test/a"))
        XCTAssertNil(FeedReadingDecision.usableSiteURL(nil))
        XCTAssertNil(FeedReadingDecision.usableSiteURL(URL(string: "mailto:redacao@example.test")))
        XCTAssertNil(FeedReadingDecision.usableSiteURL(URL(string: "javascript:alert(1)")))
        XCTAssertNil(FeedReadingDecision.usableSiteURL(URL(string: "feedmine://article")))
        XCTAssertNil(FeedReadingDecision.usableSiteURL(URL(string: "https:/article")), "no host is no door")
    }

    /// `nil` is reserved for the card that has neither text nor address: there is nothing to show and nothing a
    /// tap could offer. Text without an address is never nil — that is the local exit above.
    func testACardWithNothingToReadAndNoAddressOffersNothing() {
        XCTAssertNil(target(siteURL: nil), "no text and no address is not a reading experience")
        XCTAssertNil(target(body: "\n", summary: "  ", siteURL: nil), "whitespace is not text")

        guard case .site(let link) = target(body: "\n", summary: "  ", siteURL: url) else {
            return XCTFail("nothing to read with an address is still the site, the one thing the card offers")
        }
        XCTAssertEqual(link, url)
    }

    func testLocalTextIsNeverPresentedAsTheWholeArticle() {
        guard case .local(let content) = target(body: "Corpo", siteURL: url) else {
            return XCTFail("a body is read locally")
        }
        XCTAssertTrue(content.isPartial,
            "the app cannot claim a feed's own body is the article; local text is partial content")
    }
}
