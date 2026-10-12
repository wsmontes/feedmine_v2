import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMineSyndication

/// Reading what the reader typed: extraction, normalization and classification, with V1's rules.
final class FeedLinkInputTests: XCTestCase {
    func testItFindsEveryAddressInProseBareDomainsAndLists() {
        let links = FeedLinkInput.parse("""
        Olha estas: https://a.example/feed, b.example
        e também https://c.example/rss.xml
        """)
        XCTAssertEqual(links.map(\.url.absoluteString), ["https://a.example/feed", "https://b.example",
            "https://c.example/rss.xml"])
        XCTAssertEqual(Set(links.map(\.kind)), [.feed, .website])
    }

    func testTheSameAddressTwiceIsOneLink() {
        let links = FeedLinkInput.parse("https://a.example/feed https://a.example/feed")
        XCTAssertEqual(links.count, 1)
    }

    /// The scheme vocabulary is closed: a non-web scheme is refused, never rewritten into an HTTPS address.
    func testANonWebSchemeIsRefusedNotRewritten() {
        XCTAssertNil(FeedLinkInput.normalizeWebURL("javascript:alert(1)"))
        XCTAssertNil(FeedLinkInput.normalizeWebURL("data:text/html,<b>x</b>"))
        XCTAssertNil(FeedLinkInput.parse("javascript:alert(1)").first)
        XCTAssertEqual(FeedLinkInput.normalizeWebURL("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(FeedLinkInput.normalizeWebURL("http://example.com/feed")?.absoluteString,
            "http://example.com/feed")
    }

    /// An e-mail address is not a feed: `https://user@host` would be a source with credentials in its address.
    func testAnEmailIsNotALink() {
        XCTAssertNil(FeedLinkInput.normalizeWebURL("reader@example.com"))
        XCTAssertTrue(FeedLinkInput.parse("escreva para reader@example.com").isEmpty)
    }

    /// Classification is ordered and matches whole hosts only, so a lookalike domain is not a podcast.
    func testClassificationIsOrderedAndHostExact() {
        func kind(_ text: String) -> FeedLinkKind? { FeedLinkInput.parse(text).first?.kind }
        XCTAssertEqual(kind("https://example.com/list.opml"), .opml)
        XCTAssertEqual(kind("https://www.youtube.com/@someone"), .youtube)
        XCTAssertEqual(kind("https://youtu.be/abc"), .youtube)
        XCTAssertEqual(kind("https://github.com/nmdias/FeedKit"), .github)
        XCTAssertEqual(kind("https://podcasts.apple.com/br/podcast/x/id123"), .podcast)
        XCTAssertEqual(kind("https://fake-podcasts.apple.com.evil.org/x"), .website,
            "a lookalike host is not a podcast")
        XCTAssertEqual(kind("https://open.spotify.com/show/abc"), .podcast)
        XCTAssertEqual(kind("https://example.com/feed"), .feed)
        XCTAssertEqual(kind("https://example.com/atom.xml"), .feed)
        XCTAssertEqual(kind("https://example.com/"), .website)
    }
}

/// Turning links into feed addresses, with a transport that answers from documents instead of a network.
final class FeedLinkResolverTests: XCTestCase {
    private struct StubTransport: FeedDiscoveryTransport {
        let handler: @Sendable (FeedDiscoveryRequest) async throws -> FeedDiscoveryResponse

        func send(_ request: FeedDiscoveryRequest) async throws -> FeedDiscoveryResponse {
            try await handler(request)
        }
    }

    private func resolver(transport: StubTransport, deadline: TimeInterval = 8) -> FeedLinkResolver {
        var budget = FeedLinkResolver.Budget()
        budget.discoveryDeadline = deadline
        budget.requestTimeout = 1
        budget.probeTimeout = 1
        return FeedLinkResolver(transport: transport, budget: budget)
    }

    private func link(_ text: String) throws -> FeedLink {
        try XCTUnwrap(FeedLinkInput.parse(text).first)
    }

    private static func rss(_ title: String = "Feed") -> Data {
        Data("<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>\(title)</title></channel></rss>".utf8)
    }

    /// An address that looks like a feed but serves a page is not accepted on its path alone: the probe
    /// decides, and discovery takes over.
    func testAFeedLookingAddressIsProbedAndAFailedProbeFallsThroughToDiscovery() async throws {
        let page = Data("""
        <html><head><link rel="alternate" type="application/rss+xml" title="Real feed" href="/real.xml">
        </head><body>oi</body></html>
        """.utf8)
        let transport = StubTransport { request in
            switch request.url.absoluteString {
            case "https://example.com/feed":
                return FeedDiscoveryResponse(statusCode: 200, contentType: "text/html", body: request.method == .head ? Data() : page)
            case "https://example.com/real.xml":
                return FeedDiscoveryResponse(statusCode: 200, contentType: "application/rss+xml", body: Data())
            default:
                return FeedDiscoveryResponse(statusCode: 404, contentType: nil, body: Data())
            }
        }
        let resolution = await resolver(transport: transport).resolve(try link("https://example.com/feed"))
        XCTAssertEqual(resolution.feeds.map(\.feedURL), ["https://example.com/real.xml"])
        XCTAssertEqual(resolution.feeds.first?.title, "Real feed")
        XCTAssertNil(resolution.failure)
    }

    /// An address that really is a feed is kept as it is, with the reader's own address.
    func testAProbedFeedIsKeptAsGiven() async throws {
        let transport = StubTransport { request in
            XCTAssertEqual(request.method, .head)
            return FeedDiscoveryResponse(statusCode: 200, contentType: "application/rss+xml", body: Data())
        }
        let resolution = await resolver(transport: transport).resolve(try link("https://example.com/rss.xml"))
        XCTAssertEqual(resolution.feeds.map(\.feedURL), ["https://example.com/rss.xml"])
        XCTAssertEqual(resolution.feeds.first?.mediaKind, .text)
    }

    /// A page with no declaration is probed on the common paths, and the first one that serves a feed wins.
    func testCommonPathsAreProbedWhenThePageDeclaresNothing() async throws {
        let page = Data("<html><head><title>Sem feed</title></head></html>".utf8)
        let transport = StubTransport { request in
            switch request.url.absoluteString {
            case "https://example.com/", "https://example.com/feed":
                return FeedDiscoveryResponse(statusCode: 200, contentType: "text/html", body: request.method == .head ? Data() : page)
            case "https://example.com/rss":
                return FeedDiscoveryResponse(statusCode: 200, contentType: "text/xml", body: Self.rss())
            default:
                return FeedDiscoveryResponse(statusCode: 404, contentType: nil, body: Data())
            }
        }
        let resolution = await resolver(transport: transport).resolve(try link("https://example.com/"))
        XCTAssertEqual(resolution.feeds.map(\.feedURL), ["https://example.com/rss"])
    }

    /// A site with no feed says so, per input, instead of failing the whole paste.
    func testNoFeedIsReportedPerInput() async throws {
        let transport = StubTransport { _ in
            FeedDiscoveryResponse(statusCode: 404, contentType: nil, body: Data())
        }
        let resolutions = await resolver(transport: transport).resolveAll([
            try link("https://a.example/"), try link("https://b.example/")])
        XCTAssertEqual(resolutions.count, 2)
        XCTAssertTrue(resolutions.allSatisfy { $0.failure == .noFeedFound })
        XCTAssertEqual(resolutions.map(\.link.url.absoluteString), ["https://a.example/", "https://b.example/"],
            "results come back in the order the reader pasted them")
    }

    /// A search that never gets an answer ends at the deadline instead of holding the reader. The stub honors
    /// the request's own timeout the way the live transport does, so what is measured is the deadline and not
    /// a sleep that no real URLSession would allow.
    func testTheDeadlineEndsASearchThatNeverAnswers() async throws {
        let transport = StubTransport { request in
            if request.method == .head {
                return FeedDiscoveryResponse(statusCode: 200, contentType: "text/html", body: Data())
            }
            try await Task.sleep(nanoseconds: UInt64(max(0, request.timeout) * 1_000_000_000))
            throw FeedDiscoveryTransportError.unreachable
        }
        let started = Date()
        let resolution = await resolver(transport: transport, deadline: 0.3).resolve(try link("https://slow.example/"))
        XCTAssertEqual(resolution.failure, .noFeedFound)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "the deadline bounds the search")
    }

    /// An oversized page is refused by the transport's ceiling and reported, never buffered whole.
    func testAnOversizedPageIsReportedNotRead() async throws {
        let transport = StubTransport { _ in throw FeedDiscoveryTransportError.tooLarge }
        let resolution = await resolver(transport: transport).resolve(try link("https://big.example/"))
        XCTAssertEqual(resolution.failure, .noFeedFound)
        XCTAssertTrue(resolution.feeds.isEmpty)
    }

    /// YouTube: a channel id is a channel feed; a handle needs the page; a playlist is its own feed.
    func testYouTubeChannelPlaylistAndHandle() async throws {
        let transport = StubTransport { request in
            if request.url.absoluteString == "https://www.youtube.com/@someone" {
                return FeedDiscoveryResponse(statusCode: 200, contentType: "text/html",
                    body: Data("<html><meta itemprop=\"channelId\" content=\"UCabc123\"></html>".utf8))
            }
            return FeedDiscoveryResponse(statusCode: 404, contentType: nil, body: Data())
        }
        let resolver = resolver(transport: transport)
        let channel = await resolver.resolve(try link("https://www.youtube.com/channel/UCxyz"))
        XCTAssertEqual(channel.feeds.map(\.feedURL),
            ["https://www.youtube.com/feeds/videos.xml?channel_id=UCxyz"])
        XCTAssertEqual(channel.feeds.first?.mediaKind, .video)
        let playlist = await resolver.resolve(try link("https://www.youtube.com/playlist?list=PL9"))
        XCTAssertEqual(playlist.feeds.map(\.feedURL),
            ["https://www.youtube.com/feeds/videos.xml?playlist_id=PL9"])
        let handle = await resolver.resolve(try link("https://www.youtube.com/@someone"))
        XCTAssertEqual(handle.feeds.map(\.feedURL),
            ["https://www.youtube.com/feeds/videos.xml?channel_id=UCabc123"])
    }

    /// GitHub: a repository is its releases, a user is their activity.
    func testGitHubRepositoryAndUser() async throws {
        let transport = StubTransport { _ in
            FeedDiscoveryResponse(statusCode: 404, contentType: nil, body: Data())
        }
        let resolver = resolver(transport: transport)
        let repo = await resolver.resolve(try link("https://github.com/nmdias/FeedKit"))
        XCTAssertEqual(repo.feeds.map(\.feedURL), ["https://github.com/nmdias/FeedKit/releases.atom"])
        XCTAssertEqual(repo.feeds.first?.title, "FeedKit releases")
        let user = await resolver.resolve(try link("https://github.com/nmdias"))
        XCTAssertEqual(user.feeds.map(\.feedURL), ["https://github.com/nmdias.atom"])
    }

    /// An Apple Podcasts page becomes the show's own feed, through the public lookup.
    func testApplePodcastUsesTheLookupFeed() async throws {
        let transport = StubTransport { request in
            guard request.url.absoluteString.hasPrefix("https://itunes.apple.com/lookup") else {
                return FeedDiscoveryResponse(statusCode: 404, contentType: nil, body: Data())
            }
            XCTAssertTrue(request.url.absoluteString.contains("id=12345"))
            return FeedDiscoveryResponse(statusCode: 200, contentType: "application/json",
                body: Data("{\"results\":[{\"feedUrl\":\"https://feeds.example/show.xml\"}]}".utf8))
        }
        let resolution = await resolver(transport: transport)
            .resolve(try link("https://podcasts.apple.com/br/podcast/meu-show/id12345"))
        XCTAssertEqual(resolution.feeds.map(\.feedURL), ["https://feeds.example/show.xml"])
        XCTAssertEqual(resolution.feeds.first?.mediaKind, .audio)
    }

    /// An OPML address is the import pipeline's business: this resolver says nothing about it.
    func testAnOPMLIsNotResolvedHere() async throws {
        let transport = StubTransport { _ in
            XCTFail("nothing is fetched for an OPML")
            return FeedDiscoveryResponse(statusCode: 404, contentType: nil, body: Data())
        }
        let resolution = await resolver(transport: transport).resolve(try link("https://example.com/list.opml"))
        XCTAssertTrue(resolution.feeds.isEmpty)
        XCTAssertNil(resolution.failure)
    }
}
