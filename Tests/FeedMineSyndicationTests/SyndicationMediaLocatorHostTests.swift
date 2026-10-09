import XCTest
@testable import FeedMineSyndication

/// Review R15: admission refuses image locators aimed at non-public hosts, including relative
/// locators resolved against a non-public base.
final class SyndicationMediaLocatorHostTests: XCTestCase {
    func testNonPublicImageHostsAreNotAdmitted() {
        for raw in ["http://127.0.0.1/a.jpg", "https://169.254.169.254/latest/meta-data/x.jpg", "https://[::1]/a.png",
            "https://nas.local/photo.jpg", "//192.168.0.2/hero.jpg"] {
            XCTAssertNil(SyndicationMediaLocator.resolve(raw, base: nil), raw)
        }
        XCTAssertNil(SyndicationMediaLocator.resolve("/img/hero.jpg", base: URL(string: "http://10.0.0.5/feed.xml")))
        XCTAssertNotNil(SyndicationMediaLocator.resolve("https://ichef.bbci.co.uk/images/hero.jpg", base: nil))
    }
}