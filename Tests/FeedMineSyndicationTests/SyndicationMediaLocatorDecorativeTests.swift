import Foundation
import XCTest
@testable import FeedMineSyndication

/// 2026-11-02 (V1 lessons): decoration is filtered where the claim is made, so an item whose only image is a
/// beacon, an icon or a smiley is the text card as designed instead of a declared image that fails to prepare and
/// leaves the queue (INV-17).
final class SyndicationMediaLocatorDecorativeTests: XCTestCase {
    private let base = URL(string: "https://news.example/story/1")!
    private func image(_ html: String) -> String? {
        SyndicationMediaLocator.firstContentImage(inHTML: html, base: base)?.absoluteString
    }

    func testNewDecorativeMarkersAreRejected() {
        for url in [
            "https://news.example/wp-includes/images/smilies/icon_smile.gif",
            "https://s0.wp.com/wp-content/mu-plugins/wpcom-smileys/twemoji/2/72x72/1f642.png?wp-smiley",
            "https://feeds.wordpress.com/1.0/comments/example.wordpress.com/123/",
            "https://da.feedsportal.com/r/123/u/49/f/1/story01.htm",
            "https://ad.doubleclick.com/ddm/trackimp/N1.gif",
            "https://news.example/wp-content/uploads/avatars/12/thumb.jpg",
        ] {
            XCTAssertTrue(SyndicationMediaLocator.isDecorative(url), url)
        }
        XCTAssertFalse(SyndicationMediaLocator.isDecorative("https://cdn.example/2026/11/avatar-fire-and-ash-review.jpg"),
            "a film named Avatar is not an avatar directory")
    }

    func testDeclaredBeaconAndIconSizesAreSkippedForTheNextImage() {
        XCTAssertEqual(image("<img src=\"https://cdn.example/beacon.gif\" width=\"1\" height=\"1\">"
            + "<img src=\"https://cdn.example/art.jpg\">"), "https://cdn.example/art.jpg")
        XCTAssertEqual(image("<img width=\"1px\" src=\"https://cdn.example/b\"><img src=\"https://cdn.example/art.jpg\">"),
            "https://cdn.example/art.jpg", "one declared pixel side is enough")
        XCTAssertEqual(image("<img src=\"https://cdn.example/icon.png\" width=\"48\" height=\"48\">"
            + "<img src=\"https://cdn.example/art.jpg\" width=\"1200\" height=\"630\">"), "https://cdn.example/art.jpg")
        XCTAssertNil(image("<img src=\"https://cdn.example/only-beacon.gif\" height=\"2\">"),
            "an item whose only image is a beacon declares no image")
    }

    func testUndeclaredOrRelativeSizesSayNothing() {
        XCTAssertEqual(image("<img src=\"https://cdn.example/a.jpg\" width=\"100%\">"), "https://cdn.example/a.jpg")
        XCTAssertEqual(image("<img src=\"https://cdn.example/b.jpg\" width=\"0\" height=\"0\">"), "https://cdn.example/b.jpg")
        XCTAssertEqual(image("<img src=\"https://cdn.example/c.jpg\" width=\"640\">"), "https://cdn.example/c.jpg")
        XCTAssertEqual(image("<img src=\"https://cdn.example/d.jpg\" width=\"120\" height=\"400\">"),
            "https://cdn.example/d.jpg", "one small side alone is not an icon")
    }

    func testDeclaredSizeRule() {
        XCTAssertTrue(SyndicationMediaLocator.isDecorativeDeclaredSize(width: "1", height: nil))
        XCTAssertTrue(SyndicationMediaLocator.isDecorativeDeclaredSize(width: nil, height: " 2px "))
        XCTAssertTrue(SyndicationMediaLocator.isDecorativeDeclaredSize(width: "150", height: "150"))
        XCTAssertFalse(SyndicationMediaLocator.isDecorativeDeclaredSize(width: "151", height: "150"))
        XCTAssertFalse(SyndicationMediaLocator.isDecorativeDeclaredSize(width: nil, height: nil))
        XCTAssertFalse(SyndicationMediaLocator.isDecorativeDeclaredSize(width: "auto", height: "1em"))
    }
}
