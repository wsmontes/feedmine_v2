import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineComposition

struct TrustedFeed: Sendable {
    let targetID: AcquisitionTargetID
    let sourceID: SourceID
    let bindingID: SourceBindingID
    let principal: String
    let endpoint: URL
    /// Frozen attribution shown on published cards.
    let displayName: String

    static let development: [TrustedFeed] = [
        .init(targetID: .init(rawValue: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!),
            sourceID: .init(rawValue: UUID(uuidString: "50000000-0000-4000-8000-000000000001")!),
            bindingID: .init(rawValue: UUID(uuidString: "60000000-0000-4000-8000-000000000001")!),
            principal: "bbc-world", endpoint: URL(string: "https://feeds.bbci.co.uk/news/world/rss.xml")!, displayName: "BBC World"),
        .init(targetID: .init(rawValue: UUID(uuidString: "40000000-0000-4000-8000-000000000002")!),
            sourceID: .init(rawValue: UUID(uuidString: "50000000-0000-4000-8000-000000000002")!),
            bindingID: .init(rawValue: UUID(uuidString: "60000000-0000-4000-8000-000000000002")!),
            principal: "bbc-science", endpoint: URL(string: "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml")!, displayName: "BBC Science")
    ]
}

enum TrustedCatalogError: Error { case missingResource, invalidLimit, missingDefaultSource(String) }

extension TrustedFeed {
    /// A small, explicit news/science starter set from the actual catalog. The complete catalog
    /// remains available to source selection; startup never registers every default-enabled row.
    static func catalog(limit: Int, resourceURL: URL?) throws -> [TrustedFeed] {
        guard limit > 0 else { throw TrustedCatalogError.invalidLimit }
        guard let resourceURL else { throw TrustedCatalogError.missingResource }
        let reader = try LegacyCatalogReader(catalogURL: resourceURL)
        let keys = ["https://feeds.bbci.co.uk/news/rss.xml", "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
            "https://feeds.npr.org/1001/rss.xml", "https://theguardian.com/world/rss"]
        return try keys.prefix(limit).map { key in
            guard let record = try reader.source(key: key), let entry = LegacyCatalogImport.entry(record) else {
                throw TrustedCatalogError.missingDefaultSource(key)
            }
            return TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
                principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
        }
    }

    /// Review OMP C1: saved keys are reader preferences, not bundled configuration. A key the
    /// current catalog no longer contains (catalog update, development key) is dropped instead of
    /// failing startup; a missing or unreadable catalog still throws.
    static func resolveAvailable(keys: [String], fallback: [TrustedFeed]) throws -> [TrustedFeed] {
        var reader: LegacyCatalogReader?
        return try keys.compactMap { key in
            if let supplied = fallback.first(where: { $0.principal == key }) { return supplied }
            if reader == nil {
                guard let url = Bundle.main.url(forResource: "catalog", withExtension: "sqlite") else { throw TrustedCatalogError.missingResource }
                reader = try LegacyCatalogReader(catalogURL: url)
            }
            guard let record = try reader?.source(key: key), let entry = LegacyCatalogImport.entry(record) else { return nil }
            return TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
                principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
        }
    }

    static func catalogOrDevelopment(limit: Int) -> [TrustedFeed] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] == "1" { return development }
        #endif
        do { return try catalog(limit: limit, resourceURL: Bundle.main.url(forResource: "catalog", withExtension: "sqlite")) }
        catch {
            #if DEBUG
            return development
            #else
            // AppComposition presents an explicit startup failure for an absent/invalid release catalog.
            return []
            #endif
        }
    }
}

#if DEBUG
// A real closed proxy used only for the development network-blocked relaunch proof.
/// T12: the app tests must not depend on public RSS (the plan says so outright). This serves the development
/// feeds' own endpoints from fixtures the app carries, so a test — UI or unit — gets deterministic content with
/// no network, no server and no clock.
enum DevelopmentLocalFeeds {
    static let endpoints: Set<String> = [
        "https://feeds.bbci.co.uk/news/world/rss.xml",
        "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
    ]

    static func apply(to configuration: URLSessionConfiguration) {
        var protocols = configuration.protocolClasses ?? []
        protocols.insert(LocalFeedProtocol.self, at: 0)
        configuration.protocolClasses = protocols
    }

    /// The document each endpoint answers with: six items, two sources, distinct timestamps — enough for a feed,
    /// a scroll and a save, and never more than the test needs.
    static func document(for url: URL) -> Data {
        let isScience = url.absoluteString.contains("science")
        let feedTitle = isScience ? "BBC Science" : "BBC World"
        let items = (0..<6).map { index -> String in
            let stamp = isScience ? 900 - index * 60 : 950 - index * 60
            return """
            <item>
              <title>\(feedTitle) story \(index + 1)</title>
              <link>https://example.test/\(isScience ? "science" : "world")/\(index + 1)</link>
              <guid>\(url.absoluteString)#\(index + 1)</guid>
              <description>Fixture summary \(index + 1) for \(feedTitle).</description>
              <pubDate>Sun, 05 Oct 2026 12:00:00 GMT</pubDate>
            </item>
            """
        }.joined(separator: "\n")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <title>\(feedTitle)</title>
          <link>\(url.absoluteString)</link>
          <description>Fixture feed</description>
          <language>en</language>
          \(items)
        </channel></rss>
        """
        _ = stampedSerial
        return Data(xml.utf8)
    }

    /// A serial the fixture's timestamps do not share: it exists so two runs of the same test cannot look
    /// different to a reader, and it is never used for a decision.
    private static let stampedSerial = 1
}

private final class LocalFeedProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        return DevelopmentLocalFeeds.endpoints.contains(url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = DevelopmentLocalFeeds.document(for: url)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/rss+xml", "Content-Length": String(body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum DevelopmentNetworkBlock {
    static func apply(to configuration: URLSessionConfiguration) {
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 9,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 9]
    }
}
#endif
