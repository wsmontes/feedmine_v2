//
// File: ReadingCompositionTests.swift
// Module: FeedMineAppTests
//
// The reading decision, proved in process against the real composition: what a card's tap resolves to, and — the
// architect's invariant — that resolving it fetches nothing and publishes nothing. `CompositionTests`' own
// transport is reused, so admission and publication stay real.
//
// The four shapes are the ones the architect named: a stored body, a substantial summary, a short summary and no
// text. The default shape is byte-identical to the transport's existing payload, so no other test in this target
// changes behaviour because this file exists.
import XCTest
import Foundation
import Synchronization
import FeedMineDomain
import FeedMineUI
@testable import FeedMine

/// The text shape the controlled transport serves for this case. Set per test and restored by the test itself.
enum ReadingFixtureShape: String {
    case shortSummary
    case longSummary
    case none
    /// A body: only the JSON Feed branch fills `bodyText` (`content_text`), which is why the fixture needs one.
    case body
}

enum ReadingFixture {
    static let shape = Mutex(ReadingFixtureShape.shortSummary)

    /// Which batch of items the next payload serves. Default `0` keeps every payload byte-identical to what this
    /// transport always served; a test that needs a **deep store** (a long navigation, where the edition must hold
    /// far more cards than one window) advances it, so each publication brings *distinct* items instead of
    /// re-publishing the same twenty-four. Restored by the test itself, like `shape`.
    static let generation = Mutex(0)

    private static var itemRange: ClosedRange<Int> {
        let base = generation.withLock { $0 } * 24
        return (base + 1)...(base + 24)
    }

    /// Comfortably over the 3.000-character parameter that opens the local reader, and recognisable on screen.
    static var longText: String {
        (1...60).map { "Parágrafo \($0): o texto que a fonte publicou para este artigo." }.joined(separator: " ")
    }

    private static func rss(description: (Int) -> String) -> Data {
        let items = itemRange.map {
            "<item><guid>fixture-\($0)</guid><title>Published fixture \($0)</title><link>https://fixture.invalid/story-\($0)</link>\(description($0))</item>"
        }.joined()
        return Data("<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Trusted fixture</title><link>https://fixture.invalid/</link><description>Integration</description>\(items)</channel></rss>".utf8)
    }

    private static var jsonFeed: Data {
        let items = itemRange.map {
            """
            {"id": "https://fixture.invalid/story-\($0)", "url": "https://fixture.invalid/story-\($0)",
             "title": "Published fixture \($0)", "summary": "Readable local story \($0)",
             "content_text": "\(longText)"}
            """
        }.joined(separator: ",")
        return Data("""
        {"version": "https://jsonfeed.org/version/1.1", "title": "Trusted fixture",
         "home_page_url": "https://fixture.invalid/", "items": [\(items)]}
        """.utf8)
    }

    static func payload() -> (contentType: String, body: Data) {
        switch shape.withLock({ $0 }) {
        case .shortSummary:
            return ("application/rss+xml", rss { "<description>Readable local story \($0)</description>" })
        case .longSummary:
            return ("application/rss+xml", rss { _ in "<description>\(longText)</description>" })
        case .none:
            return ("application/rss+xml", rss { _ in "" })
        case .body:
            return ("application/feed+json", jsonFeed)
        }
    }
}

@MainActor
final class ReadingCompositionTests: XCTestCase {
    private func launched() async throws -> (AppComposition, FeedAssociation) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureTransport.self]
        configuration.timeoutIntervalForRequest = 60
        let root = AppComposition(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            feeds: TrustedFeed.development, transportConfiguration: configuration)
        await root.launch()
        XCTAssertNil(root.startupFailure)
        let association = try XCTUnwrap(root.association)
        XCTAssertNotNil(association.store.state.presentation, "Real cold acquisition must publish")
        return (root, association)
    }

    /// The card a reader would tap: the first one the feed presents.
    private func firstCard(_ association: FeedAssociation) throws -> PublicationCardID {
        try XCTUnwrap(association.store.state.presentation?.window.items.first?.id)
    }

    private func withShape(_ shape: ReadingFixtureShape, _ body: (AppComposition, FeedAssociation) async throws -> Void) async throws {
        ReadingFixture.shape.withLock { $0 = shape }
        defer { ReadingFixture.shape.withLock { $0 = .shortSummary } }
        let (root, association) = try await launched()
        defer { Task { await association.close() } }
        try await body(root, association)
    }

    /// The architect's invariant, measured: resolving a card's reading fetches nothing and publishes nothing.
    private func assertTheReadTouchesNothing(_ association: FeedAssociation, _ cardID: PublicationCardID) -> FeedReadingTarget? {
        let requestsBefore = FixtureTransport.requests.withLock { $0.count }
        let windowBefore = association.store.state.presentation?.window.items.map(\.id) ?? []
        let target = association.readingTarget(cardID)
        XCTAssertEqual(FixtureTransport.requests.withLock { $0.count }, requestsBefore,
            "opening a card's reading must not make a single request — not acquisition, not extraction, not cache")
        XCTAssertEqual(association.store.state.presentation?.window.items.map(\.id) ?? [], windowBefore,
            "opening a card's reading must not publish or replace anything")
        XCTAssertEqual(association.readingTarget(cardID)?.kindDescription, target?.kindDescription,
            "reading the same card twice must answer the same thing")
        return target
    }

    func testACardWithAStoredBodyIsReadLocally() async throws {
        try await withShape(.body) { _, association in
            let cardID = try firstCard(association)
            guard case .local(let content) = assertTheReadTouchesNothing(association, cardID) else {
                return XCTFail("a stored body must be read locally")
            }
            XCTAssertEqual(content.origin, .sourceBody)
            XCTAssertEqual(content.origin.label, "Texto publicado pela fonte")
            XCTAssertEqual(content.text, ReadingFixture.longText, "the body the source published is what is shown")
            let number = content.headline.split(separator: " ").last.map(String.init) ?? ""
            XCTAssertEqual(content.siteURL, URL(string: "https://fixture.invalid/story-\(number)"),
                "the local reader carries the address of this card's own article, not some other card's")
            XCTAssertTrue(content.isPartial, "a feed's body is not proof of the whole article")
        }
    }

    func testASubstantialSummaryIsReadLocallyAsASummaryOfTheSource() async throws {
        try await withShape(.longSummary) { _, association in
            let cardID = try firstCard(association)
            guard case .local(let content) = assertTheReadTouchesNothing(association, cardID) else {
                return XCTFail("a summary over the parameter must open the local reader")
            }
            XCTAssertEqual(content.origin, .sourceSummary)
            XCTAssertEqual(content.origin.label, "Resumo fornecido pela fonte")
            XCTAssertEqual(content.text.count, ReadingFixture.longText.count)
        }
    }

    func testATeaserKeepsTheSiteAsThePrimaryAction() async throws {
        try await withShape(.shortSummary) { _, association in
            let cardID = try firstCard(association)
            guard case .site(let url) = assertTheReadTouchesNothing(association, cardID) else {
                return XCTFail("a teaser is read on the site, with no intermediate screen")
            }
            XCTAssertEqual(url.host, "fixture.invalid")
        }
    }

    func testACardWithoutTextKeepsTheSiteAsItsPrimaryAction() async throws {
        try await withShape(.none) { _, association in
            let cardID = try firstCard(association)
            guard case .site = assertTheReadTouchesNothing(association, cardID) else {
                return XCTFail("no text at all still has an address to read")
            }
        }
    }
}

private extension FeedReadingTarget {
    /// A comparable description of the decision, so "the same answer twice" can be asserted without pinning the
    /// whole payload.
    var kindDescription: String {
        switch self {
        case .local(let content): "local:\(content.origin.rawValue):\(content.text.count)"
        case .site(let url): "site:\(url.absoluteString)"
        }
    }
}
