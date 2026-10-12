import Foundation
import XCTest
import FeedMineDomain
import FeedMineAcquisition
@testable import FeedMineSyndication

/// Kiro K-08 (review E3-07): a card visual is chosen only from markup a reader would render. Before the fix,
/// `firstContentImage` ran its `<img>` expression over the whole fragment, so an image inside a comment,
/// script, style, template or iframe body became the card image. Cases mirror
/// docs/reviews/kiro-2026-10-11/k08_media_locator_repro.py, which reproduced 7 failures on main@ccba5e9.
final class SyndicationMediaLocatorHiddenMarkupTests: XCTestCase {
    private let base = URL(string: "https://news.example/story/1")!
    private func image(_ html: String) -> String? {
        SyndicationMediaLocator.firstContentImage(inHTML: html, base: base)?.absoluteString
    }

    func testImagesInsideNeverRenderedMarkupAreIgnored() {
        let hidden = [
            "<p>Text</p><!-- <img src=\"https://attacker.example/track.png?u=1\"> -->",
            "<script>var t = '<img src=\"https://attacker.example/s.png\">';</script><p>t</p>",
            "<style>/* <img src=\"https://attacker.example/c.png\"> */</style>",
            "<template><img src=\"https://attacker.example/t.png\"></template>",
            "&lt;!-- &lt;img src=\"https://attacker.example/e.png\"&gt; --&gt;&lt;p&gt;x&lt;/p&gt;",
            "<!-- unterminated <img src=\"https://attacker.example/u.png\">",
        ]
        for html in hidden { XCTAssertNil(image(html), html) }
    }

    func testVisibleImageAfterHiddenMarkupIsChosen() {
        XCTAssertEqual(image("<!-- <img src=\"https://attacker.example/x.png\"> --><img src=\"https://cdn.example/real.jpg\">"),
            "https://cdn.example/real.jpg")
        XCTAssertEqual(image("<iframe src=\"https://v.example/e\"><img src=\"https://attacker.example/i.png\"></iframe>"
            + "<img src=\"https://cdn.example/v.jpg\">"), "https://cdn.example/v.jpg")
        XCTAssertEqual(image("<SCRIPT>x='<img src=\"https://attacker.example/q.png\">'</SCRIPT><img src=\"https://cdn.example/q.jpg\">"),
            "https://cdn.example/q.jpg")
        XCTAssertEqual(image("<img src=\"https://cdn.example/ok.jpg\"><!-- <img src=\"https://attacker.example/u.png\">"),
            "https://cdn.example/ok.jpg")
    }

    /// Fallbacks that a reader without scripts or plugins does show remain eligible; void and custom elements
    /// never swallow the rest of the fragment.
    func testRenderedFallbacksAndLookalikeElementsAreKept() {
        XCTAssertEqual(image("<img src=\"data:image/gif;base64,R0\"><noscript><img src=\"https://cdn.example/ns.jpg\"></noscript>"),
            "https://cdn.example/ns.jpg")
        XCTAssertEqual(image("<object data=\"https://cdn.example/x.swf\"><img src=\"https://cdn.example/fallback.jpg\"></object>"),
            "https://cdn.example/fallback.jpg")
        XCTAssertEqual(image("<embed src=\"https://cdn.example/x.swf\"><img src=\"https://cdn.example/after.jpg\">"),
            "https://cdn.example/after.jpg")
        XCTAssertEqual(image("<template-card><img src=\"https://cdn.example/tc.jpg\"></template-card>"),
            "https://cdn.example/tc.jpg")
        XCTAssertEqual(image("<p><img src=\"/body.jpg\"></p>"), "https://news.example/body.jpg")
        XCTAssertEqual(image("&lt;img src=\"https://example.test/body.jpg\"&gt;"), "https://example.test/body.jpg")
    }

    /// Review E3-08 re-checked: entity-escaped ampersands in src and srcset already resolve (resolve() unescapes
    /// &amp;/&#038;/&#38; after the srcset choice, and the descriptor split never sees a decoded separator).
    /// Not a defect; pinned so the hidden-markup change cannot regress it.
    func testEscapedAmpersandsInSrcAndSrcsetStillResolve() {
        XCTAssertEqual(image("<img srcset=\"https://cdn.example/a.jpg?w=960&amp;s=x 960w, https://cdn.example/b.jpg?w=480&amp;s=y 480w\">"),
            "https://cdn.example/a.jpg?w=960&s=x")
        XCTAssertEqual(image("<img srcset=\"https://cdn.example/a.jpg?w=1200&#038;q=80 1200w\">"), "https://cdn.example/a.jpg?w=1200&q=80")
        XCTAssertEqual(image("<img src=\"https://cdn.example/a.jpg?x=1&amp;y=2\">"), "https://cdn.example/a.jpg?x=1&y=2")
        XCTAssertEqual(image("&lt;img src=\"https://cdn.example/a.jpg?x=1&amp;y=2\"&gt;"), "https://cdn.example/a.jpg?x=1&y=2")
    }

    /// End to end through the translator: a feed item whose only body image is commented out admits no media.
    func testTranslatorAdmitsNoMediaFromCommentedOutImage() throws {
        let target = AcquisitionTargetID()
        let configuration = try XCTUnwrap(SyndicationTargetConfiguration(targetID: target,
            endpoint: URL(string: "https://example.test/feed")!, memberships: [.init(sourceID: SourceID(), kind: .direct)]))
        let feed = "<rss version=\"2.0\"><channel><title>Feed</title><item><guid>g</guid><link>https://site.example/p</link>"
            + "<description><![CDATA[<p>Story</p><!-- <img src=\"https://attacker.example/beacon.png\"> -->]]></description>"
            + "</item></channel></rss>"
        let translation = try SyndicationTranslator().translate(data: Data(feed.utf8), configuration: configuration,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000), startIndex: 0, itemCapacity: 10)
        let observation = try XCTUnwrap(translation.observations.first)
        XCTAssertEqual(observation.mediaCandidates, [])
    }
}
