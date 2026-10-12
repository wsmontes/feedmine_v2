import Foundation
import XCTest
import FeedMineDomain
@testable import FeedMinePersistence
import FeedMineComposition
import FeedMineSyndication
import FeedMineRuntime

/// The add-a-feed boundary: what the resolver finds is not automatically what the reader's library may hold. An
/// address this build could never fetch (a non-web alternate link, credentials in the URL) is refused at the
/// preview, so the selection never names a source that can never produce a card.
final class ReaderAddFeedAdapterTests: XCTestCase {
    private struct Stub: FeedDiscoveryTransport {
        let handler: @Sendable (FeedDiscoveryRequest) async throws -> FeedDiscoveryResponse
        func send(_ request: FeedDiscoveryRequest) async throws -> FeedDiscoveryResponse {
            try await handler(request)
        }
    }

    private func adapter(_ handler: @escaping @Sendable (FeedDiscoveryRequest) async throws -> FeedDiscoveryResponse)
        throws -> (ReaderAddFeedAdapter, RuntimeDatabase) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: RuntimeDatabaseLocation(directory: root))
        _ = try ReaderPreferencesStore(database: database).initialize(sourceKeys: [])
        let resolver = FeedLinkResolver(transport: Stub(handler: handler))
        return (ReaderAddFeedAdapter(database: database, resolver: resolver), database)
    }

    /// `https://site.example` and `https://site.example/` are the same page.
    private static func isRoot(_ url: URL) -> Bool { url.path.isEmpty || url.path == "/" }

    private static func rss() -> FeedDiscoveryResponse {
        FeedDiscoveryResponse(statusCode: 200, contentType: "application/rss+xml", body: Data("<rss>".utf8))
    }

    /// A page whose own declaration is not a web address: the resolver hands the address back, and the library
    /// refuses it — with a reason the surface can state.
    func testANonWebAlternateAddressIsRefusedWithAReason() async throws {
        let page = Data("""
        <html><head><link rel="alternate" type="application/rss+xml" href="ftp://site.example/feed.xml">
        </head></html>
        """.utf8)
        let (adapter, database) = try adapter { request in
            Self.isRoot(request.url)
                ? FeedDiscoveryResponse(statusCode: 200, contentType: "text/html", body: page)
                : FeedDiscoveryResponse(statusCode: 404, contentType: nil, body: Data())
        }
        let proposal = await adapter.resolve("https://site.example/")
        XCTAssertTrue(proposal.feeds.isEmpty, "a non-web feed address is not a source this build can keep")
        XCTAssertEqual(proposal.rejections.map(\.reason), [.refused])

        let result = try await adapter.adopt(proposal, collectionID: nil)
        XCTAssertEqual(result.added, 0)
        XCTAssertTrue(try ReaderLibraryStore(database: database).importedSources().isEmpty)
        XCTAssertTrue(try ReaderPreferencesStore(database: database).load()?.sourceKeys.isEmpty ?? false)
    }

    /// A feed address that carries credentials is a paid-feed shape: it is refused rather than stored, so the
    /// reader's selection never holds a secret it cannot use.
    func testACredentialedFeedAddressIsRefused() async throws {
        let (adapter, _) = try adapter { _ in Self.rss() }
        let proposal = await adapter.resolve("https://reader:secret@site.example/feed.xml")
        XCTAssertTrue(proposal.feeds.isEmpty)
        XCTAssertEqual(proposal.rejections.map(\.reason), [.refused])
    }

    /// The same path, clean: what the reader meant by pasting a link is added, with the resolved fetch address.
    func testACleanAddressIsAddedWithItsResolvedAddress() async throws {
        let page = Data("""
        <html><head><link rel="alternate" type="application/rss+xml" title="Um feed" href="/feed.xml">
        </head></html>
        """.utf8)
        let (adapter, database) = try adapter { request in
            Self.isRoot(request.url)
                ? FeedDiscoveryResponse(statusCode: 200, contentType: "text/html", body: page)
                : Self.rss()
        }
        let proposal = await adapter.resolve("site.example")
        XCTAssertEqual(proposal.feeds.map(\.feedURL), ["https://site.example/feed.xml"])
        XCTAssertEqual(proposal.feeds.map(\.title), ["Um feed"])
        let result = try await adapter.adopt(proposal, collectionID: nil)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(try ReaderLibraryStore(database: database).importedSources().map(\.id),
            ["https://site.example/feed.xml"])
    }
}
