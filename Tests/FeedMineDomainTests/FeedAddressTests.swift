import XCTest
import FeedMineDomain

/// T10: a feed's two addresses. The identity decides whether two OPML entries are the same feed; the request
/// address is what is actually fetched. Both are V1's own rules (`OPMLParser.normalizeURL` / `requestURL`),
/// because an imported file has to land on the key the shipped catalog already uses.
final class FeedAddressTests: XCTestCase {
    func testIdentityLowercasesSchemeAndHostOnly() {
        XCTAssertEqual(FeedAddress.identity("HTTPS://Example.COM/Feed"), "https://example.com/Feed")
        XCTAssertEqual(FeedAddress.identity("  https://example.com/feed  "), "https://example.com/feed")
        XCTAssertEqual(FeedAddress.identity("https://example.com/A/B?Case=Kept"), "https://example.com/A/B?Case=Kept")
    }

    /// V1's identity is always `https`: a feed offered over plain http is the same feed, and the catalog's keys
    /// say so.
    func testIdentityForcesTheSecureScheme() {
        XCTAssertEqual(FeedAddress.identity("http://example.com/feed"), "https://example.com/feed")
        XCTAssertEqual(FeedAddress.request("http://example.com/feed"), "http://example.com/feed")
    }

    /// The query is part of identity only where it names the feed: tracking and session parameters are dropped,
    /// and a query that was nothing but those leaves no question mark behind.
    func testIdentityFiltersVisitParameters() {
        XCTAssertEqual(FeedAddress.identity("https://example.com/feed?utm_source=x&id=7"),
            "https://example.com/feed?id=7")
        XCTAssertEqual(FeedAddress.identity("https://example.com/feed?token=abc&sig=Zz"), "https://example.com/feed")
        XCTAssertEqual(FeedAddress.identity("https://example.com/feed?a=1&X-Amz-Signature=deadbeef"),
            "https://example.com/feed?a=1")
        // The request address keeps every parameter, which is what makes a signed feed fetchable.
        XCTAssertEqual(FeedAddress.request("https://example.com/feed?token=abc&sig=Zz"),
            "https://example.com/feed?token=abc&sig=Zz")
    }

    func testIdentityStripsWWWAndDefaultPortsAndOneTrailingSlash() {
        XCTAssertEqual(FeedAddress.identity("https://www.example.com/feed/"), "https://example.com/feed")
        XCTAssertEqual(FeedAddress.identity("https://example.com:443/feed"), "https://example.com/feed")
        XCTAssertEqual(FeedAddress.identity("https://example.com/feed///"), "https://example.com/feed",
            "V1 removed every trailing slash, not one")
        // A non-default port stays; a query keeps its own slashes while the *path's* trailing slash goes.
        XCTAssertEqual(FeedAddress.identity("https://example.com:8443/feed/"), "https://example.com:8443/feed")
        XCTAssertEqual(FeedAddress.identity("https://example.com/feed/?a=1"), "https://example.com/feed?a=1")
        XCTAssertEqual(FeedAddress.identity("https://example.com/a/b/?a=1"), "https://example.com/a/b?a=1")
    }

    func testRequestAddressKeepsWhatIdentityDrops() {
        XCTAssertEqual(FeedAddress.request("https://www.example.com/feed/"), "https://www.example.com/feed/")
        XCTAssertEqual(FeedAddress.request("https://example.com:443/feed"), "https://example.com:443/feed")
        let signed = "https://example.com/feed?token=abc&sig=Zz"
        XCTAssertEqual(FeedAddress.request(signed), signed, "the request address keeps what signs it")
        XCTAssertEqual(FeedAddress.identity(signed), "https://example.com/feed",
            "and identity sees one feed whether it is signed or not")
    }

    /// XML entities in an attribute are corruption, not preference: both addresses repair them.
    func testEntitiesAreRepairedForBothAddresses() {
        XCTAssertEqual(FeedAddress.identity("https://example.com/feed?a=1&amp;b=2"),
            "https://example.com/feed?a=1&b=2")
        XCTAssertEqual(FeedAddress.request("https://example.com/feed?a=1&#038;b=2"),
            "https://example.com/feed?a=1&b=2")
    }

    /// An identity that cannot be computed is returned as it stands: nothing is invented, and an unusable
    /// address is still recognisably unusable.
    func testUnusableAddressesAreReturnedUnchanged() {
        for raw in ["ftp://example.com/feed", "not a url", "https://", "mailto:someone@example.com"] {
            XCTAssertEqual(FeedAddress.identity(raw), raw)
        }
    }

    /// Two spellings of the same feed collapse to one identity, which is what makes a duplicate a duplicate.
    func testEquivalentSpellingsShareOneIdentity() {
        let spellings = ["https://www.example.com/feed/", "HTTPS://example.com:443/feed",
            "https://example.com/feed"]
        let identities = Set(spellings.map(FeedAddress.identity))
        XCTAssertEqual(identities.count, 1)
        XCTAssertEqual(FeedAddress.identity(spellings[0]), FeedAddress.identity(spellings[2]))
        // A different path is a different feed, whatever the scheme's case.
        XCTAssertNotEqual(FeedAddress.identity("https://example.com/feed"), FeedAddress.identity("https://example.com/other"))
    }
}
