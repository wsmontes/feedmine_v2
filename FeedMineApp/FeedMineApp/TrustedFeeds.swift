import Foundation
import Synchronization
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

    /// Operational resolution never edits reader preferences. Pinned historic identity is separate from the
    /// current catalog representation; a missing record is an unresolved choice, not a deselection.
    static func resolveAvailable(keys: [String], fallback: [TrustedFeed],
        readerSources: [ReaderImportEntry] = [], catalogueURL: URL?,
        identities: [String: ReaderLibraryStore.SourceLink] = [:]) throws -> [TrustedFeed] {
        let imported = Dictionary(readerSources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let catalog = try catalogueURL.map { try LegacyCatalogReader(catalogURL: $0) }
        var result: [TrustedFeed] = []
        var seen = Set<String>()
        for key in keys {
            let link = identities[key]
            let anchor = link?.anchorKey ?? key
            let catalogKey = link?.currentKey ?? key
            guard seen.insert(anchor).inserted else { continue }
            let personal = imported[catalogKey] ?? imported[key]
            if link?.authority == "reader", let personal,
                let entry = ReaderSourceIdentity.entry(personal, identityKey: anchor) {
                result.append(TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id,
                    bindingID: entry.bindingID, principal: anchor, endpoint: entry.endpoint,
                    displayName: entry.source.displayName, principalNamespace: ReaderSourceIdentity.principalNamespace))
                continue
            }
            if let record = try catalog?.source(key: catalogKey),
                let entry = LegacyCatalogImport.entryWithIdentityKey(record, identityKey: anchor) {
                result.append(TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id,
                    bindingID: entry.bindingID, principal: anchor, endpoint: entry.endpoint,
                    displayName: entry.source.displayName))
                continue
            }
            if let personal {
                // Keep the first catalog namespace if a formerly catalog-managed source now has only
                // its import endpoint; never flip source/target/binding IDs on catalog removal.
                let entry: LegacyCatalogEntry?
                if link?.authority == "catalog" {
                    entry = LegacyCatalogImport.entry(LegacyCatalogSourceRecord(key: anchor,
                        title: personal.title, requestURL: personal.requestURL, siteURL: nil,
                        language: nil, mediaKind: "text", qualityScore: nil, defaultEnabled: true,
                        nodeKeys: []))
                } else {
                    entry = ReaderSourceIdentity.entry(personal, identityKey: anchor)
                }
                if let entry {
                    result.append(TrustedFeed(targetID: entry.targetID, sourceID: entry.source.id,
                        bindingID: entry.bindingID, principal: anchor, endpoint: entry.endpoint,
                        displayName: entry.source.displayName,
                        principalNamespace: link?.authority == "catalog"
                            ? nil : ReaderSourceIdentity.principalNamespace))
                    continue
                }
            }
            if let supplied = fallback.first(where: { $0.principal == key || $0.principal == catalogKey }) {
                result.append(supplied)
            }
            // Unresolved is not unselected; the stored key stays untouched.
        }
        return result
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

    /// **A forma de mídia que esta execução serve.** O default (`off`) mantém o documento byte-idêntico ao que
    /// este transporte sempre serviu: item sem imagem, cartão text-only, nenhuma corrida de hoje muda. Com
    /// `image`, cada item declara o seu visual de cartão — e a imagem percorre então o caminho de produção
    /// inteiro (candidato → busca → materialização → decodificação → o slot congelado do card), sem rede e sem
    /// servidor, porque quem responde o endereço é este mesmo processo.
    ///
    /// É a jornada que faltava na bateria: nenhum teste da V2 afirmava que uma imagem foi **desenhada** (os dois
    /// desenhos do slot são decorativos e não existem na árvore de acessibilidade), e as fontes de
    /// desenvolvimento não declaravam mídia nenhuma, então a jornada não era construível. O custo em corrida
    /// normal é zero: a forma `off` é o default e nada é desenhado, gerado ou servido.
    enum MediaShape: String {
        /// O default: sem candidato de mídia, exatamente como sempre foi.
        case off
        /// Cada item declara `cardImageURL` como o seu visual.
        case image

        static var current: MediaShape {
            MediaShape(rawValue: ProcessInfo.processInfo.environment["FEEDMINE_FIXTURE_MEDIA"] ?? "") ?? .off
        }
    }

    static var mediaShape: MediaShape { MediaShape.current }

    /// O endereço que cada item declara. É um nome público de verdade — o localizador de mídia e a política de
    /// host exigem um, e nada no caminho de produção é especial-cased para teste — e esta sessão responde por ele,
    /// então a corrida não toca a rede.
    static let cardImageURL = "https://feeds.bbci.co.uk/fixture/card-visual.png"

    /// O PNG que essa imagem é: campo magenta sólido em 16:9 de hero, **desenhado aqui** — nenhum arquivo de
    /// recurso, nenhum asset catalog, nada novo no bundle. Magenta é uma cor que nenhuma paleta, placeholder,
    /// texto ou chrome do app desenha, e é isso que deixa um teste de jornada afirmar "estes pixels são a imagem"
    /// em vez de "há algo ali".
    ///
    /// O espaço é **sRGB** de propósito: com o `deviceRGB` genérico que estava aqui primeiro, os bytes eram
    /// (255, 64, 255) depois da conversão de cor (medido no blob em disco, 1200×675), e uma testemunha declarada
    /// em (255, 0, 255) não reconheceria o próprio desenho que ela mesma produziu.
    ///
    /// `static let` é preguiçoso: em corrida sem a forma `image` ele nunca é desenhado.
    static let cardImagePNG: Data = {
        let width = 1200, height = 675
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Data()
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return Data() }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return data as Data
    }()

    /// O elemento que declara o visual no documento desta execução (vazio na forma `off`).
    static var imageElement: String {
        guard mediaShape == .image else { return "" }
        return "<enclosure url=\"\(cardImageURL)\" type=\"image/png\" length=\"\(cardImagePNG.count)\"/>"
    }

    /// O mesmo visual no JSON Feed, que nomeia o seu campo (`item.image`).
    private static var imageField: String {
        guard mediaShape == .image else { return "" }
        return "\"image\": \"\(cardImageURL)\", "
    }

    /// Whether this is the fixture's own card visual — the third endpoint of this transport, and only when the
    /// run asked for it: a `off` run answers it exactly as an unreachable address.
    static func answersCardImage(_ url: URL) -> Bool {
        mediaShape == .image && url.absoluteString == cardImageURL
    }

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
             \(DevelopmentLocalFeeds.imageField)"url": "https://example.test/\(isScience ? "science" : "world")/\(index + 1)",
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
              \(DevelopmentLocalFeeds.imageElement)
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

    /// R7/E: `FEEDMINE_SLOW_FEED_SECONDS=<n>` delays only the second endpoint, so the first card appears at once
    /// and the rest of the burst lands n seconds later — after the install that followed the first publication, when
    /// no timed read exists any more to catch it and only the publication fact can.
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
        guard let url = request.url else { return false }
        return DevelopmentLocalFeeds.endpoints.contains(url.absoluteString)
            || DevelopmentLocalFeeds.answersCardImage(url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        // A imagem do fixture é o único byte que este transporte serve além dos documentos: o mesmo dono,
        // o mesmo `URLSessionConfiguration` da composição, então o caminho de mídia é o de produção.
        guard !DevelopmentLocalFeeds.answersCardImage(url) else { return deliverCardImage(url) }
        // R7/E: the second endpoint can answer *after* the first publication was installed, with no timed read left
        // to catch it, so a publication that completes later is reproducible instead of hoped for (the acceptance
        // question the round asks). What grows the window then is the publication fact itself.
        let delay = DevelopmentLocalFeeds.slowFeedSeconds(answering: url)
        guard delay > 0 else { return deliver(url) }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.deliver(url)
        }
    }

    private func deliverCardImage(_ url: URL) {
        let body = DevelopmentLocalFeeds.cardImagePNG
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/png", "Content-Length": String(body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
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
