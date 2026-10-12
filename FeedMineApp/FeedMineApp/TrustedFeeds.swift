import Foundation
import Synchronization
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
    /// The authority the principal's key came from, when the feed is not the catalogue's. The reader's own
    /// sources are a different namespace from the catalogue's even though both keys look like URLs, so a
    /// binding says where its key came from instead of guessing it from the text.
    let principalNamespace: String?

    init(targetID: AcquisitionTargetID, sourceID: SourceID, bindingID: SourceBindingID, principal: String,
        endpoint: URL, displayName: String, principalNamespace: String? = nil) {
        self.targetID = targetID
        self.sourceID = sourceID
        self.bindingID = bindingID
        self.principal = principal
        self.endpoint = endpoint
        self.displayName = displayName
        self.principalNamespace = principalNamespace
    }

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
    ///
    /// `readerSources` are the feeds the reader brought themselves — a pasted link, an imported file — kept
    /// beside the selection by `ReaderLibraryStore`. They are resolved **before** the catalogue is opened, and
    /// a key that is in neither is still dropped: an imported or pasted feed used to be written, selected and
    /// then dropped here, so the reader's own source never became a target and produced no card.
    /// The order is an **authority** order, and it is the same on every launch and for every session:
    /// the shipped catalogue, then the reader's own sources, then the session's list, then nothing.
    ///
    /// `catalogueURL` is the installed catalogue the app handed over (`AppComposition.catalogueURL`); this
    /// function does not look one up, so the resolution is made against the snapshot the app actually verified.
    ///
    /// A key the catalogue carries keeps the catalogue's identities even when the reader imported it (an OPML
    /// file full of popular feeds must not mint a second identity per feed, and a relaunch must not change the
    /// binding under a reader who did nothing); a key the catalogue does not carry — a pasted link — is the
    /// reader's, under the reader's own namespace. A key in none of them is still dropped, never invented.
    static func resolveAvailable(keys: [String], fallback: [TrustedFeed],
        readerSources: [ReaderImportEntry] = [], catalogueURL: URL?) throws -> [TrustedFeed] {
        var reader: LegacyCatalogReader?
        var mine: [String: TrustedFeed] = [:]
        for entry in readerSources {
            guard mine[entry.id] == nil, let mapped = ReaderSourceIdentity.entry(entry) else { continue }
            mine[entry.id] = TrustedFeed(targetID: mapped.targetID, sourceID: mapped.source.id,
                bindingID: mapped.bindingID, principal: mapped.principal, endpoint: mapped.endpoint,
                displayName: mapped.source.displayName, principalNamespace: ReaderSourceIdentity.principalNamespace)
        }
        return try keys.compactMap { key in
            // The catalogue is the app's installed one, handed in — not a second lookup of `Bundle.main` that
            // only pretends to be the same file. `nil` means this build carries no readable catalogue, and the
            // reader's own sources and the session's list still resolve, exactly as before.
            if reader == nil, let catalogueURL {
                reader = try LegacyCatalogReader(catalogURL: catalogueURL)
            }
            if let record = try reader?.source(key: key), let entry = LegacyCatalogImport.entry(record) {
                return TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id, bindingID: entry.bindingID,
                    principal: entry.principal, endpoint: entry.endpoint, displayName: entry.source.displayName)
            }
            // Residual, recorded: a key the catalogue *stops* carrying (an app update with a rebuilt catalogue)
            // falls through to the reader's entry and changes identity from the catalogue's namespaces to the
            // reader's. Recording the authority that first resolved a key, with the imported entry, is the fix;
            // it is not needed while the bundled catalogue only changes with an app update.
            if let readerFeed = mine[key] { return readerFeed }
            if let supplied = fallback.first(where: { $0.principal == key }) { return supplied }
            return nil
        }
    }

    /// The tests' own way in: a reader with **known** sources, so the control, navigation and restoration tests do
    /// not have to re-walk discovery to have something to poke. DEBUG-only and behind an explicit flag, and never a
    /// product default — `AppComposition()` seeds nothing, because the bundled catalogue is what discovery reads
    /// (F01) and seeding it as the reader's own selection is the failure the acceptance benchmark names. Normal use
    /// gets `[]`, and a release build cannot reach the flag at all.
    static var developmentSelection: [TrustedFeed] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FEEDMINE_USE_DEVELOPMENT_FEEDS"] == "1" { return development }
        #endif
        return []
    }
}

#if DEBUG
/// The add-feed UI test's own site: a page that declares its own feed, and the feed itself. Both come from the
/// app's process, so the whole path a reader walks — paste an address, discovery, storage, acquisition, a card —
/// runs through the real code with no network and no server.
///
/// The host is a real-looking public name (`feeds.bbci.co.uk`'s own policy check accepts it), so nothing in the
/// production path is special-cased for a test.
enum AddFeedFixtureSite {
    static let siteURL = "https://site.feedmine.test/"
    static let feedURL = "https://site.feedmine.test/feed.xml"
    /// A page whose own declaration is not a web address this build can fetch: the reader's boundary has to
    /// refuse it instead of writing a source that can never resolve.
    static let alternateSiteURL = "https://site.feedmine.test/alt-site/"
    static let alternateFeedURL = "ftp://site.feedmine.test/feed.xml"
    static let siteTitle = "Site de teste"
    /// The three headlines the fixture feed carries, oldest first.
    static let headlines = (1...3).map { "Fixture site story \($0)" }
    static let headline = headlines.last!

    static func apply(to configuration: URLSessionConfiguration) {
        var protocols = configuration.protocolClasses ?? []
        protocols.insert(AddFeedFixtureProtocol.self, at: 0)
        configuration.protocolClasses = protocols
    }

    /// Every request the fixture answered, so a test can state that the session really fetched the feed it
    /// resolved — and not just that some card appeared.
    static let requests = Mutex<[String]>([])

    static func recordedRequests() -> [String] { requests.withLock { $0 } }
    static func resetRequests() { requests.withLock { $0 = [] } }

    static var page: Data {
        Data("""
        <html><head><title>\(siteTitle)</title>
        <link rel="alternate" type="application/rss+xml" title="\(siteTitle)" href="/feed.xml">
        </head><body><p>Um site com o seu próprio feed.</p></body></html>
        """.utf8)
    }

    static var alternatePage: Data {
        Data("""
        <html><head><title>Sem feed web</title>
        <link rel="alternate" type="application/rss+xml" title="Não é web" href="\(alternateFeedURL)">
        </head><body><p>Um site que só declara um endereço que este aplicativo não busca.</p></body></html>
        """.utf8)
    }

    static var feed: Data {
        let items = (1...3).map { index in
            """
            <item><title>Fixture site story \(index)</title>
            <link>https://site.feedmine.test/story-\(index)</link>
            <guid>https://site.feedmine.test/story-\(index)</guid>
            <description>Resumo \(index).</description>
            <pubDate>Sun, 05 Oct 2026 1\(index):00:00 GMT</pubDate></item>
            """
        }.joined()
        return Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>\(siteTitle)</title>
        <link>\(siteURL)</link><description>Fixture</description><language>pt</language>
        \(items)</channel></rss>
        """.utf8)
    }

}

private final class AddFeedFixtureProtocol: URLProtocol {
    /// The fixture answers by host and path, so an address that carries credentials still reaches it — which is
    /// what lets a test prove the reader's boundary refuses such an address instead of the fixture hiding it.
    private static func isFixture(_ url: URL) -> Bool {
        guard url.host == "site.feedmine.test" else { return false }
        return url.path == "/" || url.path == "/feed.xml" || url.path == "/alt-site/"
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return isFixture(url) || DevelopmentLocalFeeds.endpoints.contains(url.absoluteString)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        // The developer feeds are not this test's supply, and this test never touches the network: they fail
        // the way an unreachable host fails.
        guard Self.isFixture(url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        respond(url)
    }

    private func respond(_ url: URL) {
        AddFeedFixtureSite.requests.withLock { $0.append(url.absoluteString) }
        let isFeed = url.path == "/feed.xml"
        let body: Data
        switch url.path {
        case "/feed.xml": body = AddFeedFixtureSite.feed
        case "/alt-site/": body = AddFeedFixtureSite.alternatePage
        default: body = AddFeedFixtureSite.page
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": isFeed ? "application/rss+xml" : "text/html; charset=utf-8",
                "Content-Length": String(body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if request.httpMethod != "HEAD" { client?.urlProtocol(self, didLoad: body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif

#if DEBUG
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
    /// U-reading: the text shape this run serves. One feed, four shapes — the architect's verification needs a
    /// stored body, a substantial summary, a short summary and no text at all, and a fixture that varies them is
    /// the only way to prove all four without touching the network.
    enum TextShape: String {
        /// A body: only the JSON Feed branch fills `bodyText` (`SyndicationTranslator` passes `content_text`
        /// there and a summary only for RSS) — measured: that is why the whole real catalogue's is empty.
        case body
        /// A summary over the 3.000-character parameter that opens the local reader.
        case longSummary
        /// The default shape: a teaser, so the site stays the card's primary action. Every document stays
        /// byte-identical to what this transport always served.
        case shortSummary
        /// No text at all.
        case none

        static var current: TextShape {
            TextShape(rawValue: ProcessInfo.processInfo.environment["FEEDMINE_FIXTURE_TEXT"] ?? "") ?? .shortSummary
        }
    }

    static var textShape: TextShape { TextShape.current }

    /// **Quantos itens por feed esta execução serve.** O default (6) mantém todo documento byte-idêntico ao que este
    /// transporte sempre serviu — seis itens por feed, dois feeds, doze cartas, que é *menos* que uma janela. Um teste
    /// que precisa de histórico **mais fundo que uma janela** (para exercitar poda de verdade, e não a re-projeção da
    /// mesma janela) pede mais por variável de ambiente. Autorizado pelo arquiteto: fixture configurável, default
    /// existente preservado.
    static var itemCount: Int {
        let requested = Int(ProcessInfo.processInfo.environment["FEEDMINE_FIXTURE_ITEMS"] ?? "") ?? 6
        return max(1, requested)
    }

    /// Long enough to be read locally, and recognisable when it appears on screen.
    static var longText: String {
        (1...60).map { "Parágrafo \($0): o texto que a fonte publicou para este artigo de teste." }
            .joined(separator: " ")
    }

    /// The type this run's documents answer with. A body only ever exists in a JSON Feed.
    static var contentType: String { textShape == .body ? "application/feed+json" : "application/rss+xml" }

    /// The summary element for this shape. The default keeps the document every existing test already reads.
    private static func summaryElement(_ index: Int, _ feedTitle: String) -> String {
        switch textShape {
        case .longSummary: "<description>\(DevelopmentLocalFeeds.longText)</description>"
        case .none: ""
        default: "<description>Fixture summary \(index + 1) for \(feedTitle).</description>"
        }
    }

    /// The JSON Feed for the body shape: `content_text` becomes the stored body while `summary` stays the teaser.
    static func jsonDocument(for url: URL) -> Data {
        let isScience = url.absoluteString.contains("science")
        let feedTitle = isScience ? "BBC Science" : "BBC World"
        let items = (0..<itemCount).map { index in
            """
            {"id": "\(url.absoluteString)#\(index + 1)",
             "url": "https://example.test/\(isScience ? "science" : "world")/\(index + 1)",
             "title": "\(feedTitle) story \(index + 1)",
             "summary": "Fixture summary \(index + 1) for \(feedTitle).",
             "content_text": "\(DevelopmentLocalFeeds.longText)",
             "date_published": "2026-10-05T12:00:00Z"}
            """
        }.joined(separator: ",")
        return Data("""
        {"version": "https://jsonfeed.org/version/1.1", "title": "\(feedTitle)",
         "home_page_url": "\(url.absoluteString)", "language": "en", "items": [\(items)]}
        """.utf8)
    }

    static func document(for url: URL) -> Data {
        if textShape == .body { return jsonDocument(for: url) }
        let isScience = url.absoluteString.contains("science")
        let feedTitle = isScience ? "BBC Science" : "BBC World"
        // R5: with `FEEDMINE_EMPTY_FEEDS=1` the same transport answers with its channel and no stories —
        // the deterministic way to reach the surface a reader sees when the attempt finished without
        // eligible content, without pretending the network failed.
        let items = answersWithNothing ? "" : (0..<itemCount).map { index -> String in
            let stamp = isScience ? 900 - index * 60 : 950 - index * 60
            return """
            <item>
              <title>\(feedTitle) story \(index + 1)</title>
              <link>https://example.test/\(isScience ? "science" : "world")/\(index + 1)</link>
              <guid>\(url.absoluteString)#\(index + 1)</guid>
              \(summaryElement(index, feedTitle))
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

    /// R5: `FEEDMINE_EMPTY_FEEDS=1` makes the fixture answer with its channel and none of its stories.
    static var answersWithNothing: Bool {
        ProcessInfo.processInfo.environment["FEEDMINE_EMPTY_FEEDS"] == "1"
    }

    /// R7: `FEEDMINE_SLOW_FEED_SECONDS=<n>` delays only the second endpoint, so the first card appears at once
    /// and the rest of the burst lands n seconds later — after any bounded follow-up has finished.
    static func slowFeedSeconds(answering url: URL) -> Double {
        guard url.absoluteString.contains("science"),
            let value = ProcessInfo.processInfo.environment["FEEDMINE_SLOW_FEED_SECONDS"].flatMap(Double.init),
            value > 0 else { return 0 }
        return value
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
        // R7: the second endpoint can answer *after* any timed follow-up has finished, so a publication that
        // completes later is reproducible instead of hoped for (the acceptance question the round asks).
        let delay = DevelopmentLocalFeeds.slowFeedSeconds(answering: url)
        guard delay > 0 else { return deliver(url) }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.deliver(url)
        }
    }

    private func deliver(_ url: URL) {
        let body = DevelopmentLocalFeeds.document(for: url)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": DevelopmentLocalFeeds.contentType, "Content-Length": String(body.count)])!
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
