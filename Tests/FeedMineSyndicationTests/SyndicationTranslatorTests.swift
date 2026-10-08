import Foundation
import XCTest
import FeedMineDomain
import FeedMineAcquisition
import FeedMineSyndication

final class SyndicationTranslatorTests: XCTestCase {
    private let target = AcquisitionTargetID(rawValue: UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000")!)
    private let source = SourceID()
    private let observed = Date(timeIntervalSince1970: 12345.125)
    private func config(target: AcquisitionTargetID? = nil, memberships: [AcquisitionMembershipClaim]? = nil) -> SyndicationTargetConfiguration {
        .init(targetID: target ?? self.target,endpoint: URL(string: "http://Example.test/Feed?Case=A")!,
            memberships: memberships ?? [.init(sourceID: source,kind: .derived)])!
    }
    private var prefix: String { "syndication:"+target.rawValue.uuidString.lowercased() }
    private func rss(_ items: String) -> Data {
        Data("<rss version=\"2.0\" xmlns:itunes=\"http://www.itunes.com/dtds/podcast-1.0.dtd\" xmlns:media=\"http://search.yahoo.com/mrss/\"><channel><title>Feed</title><language>pt-BR</language>\(items)</channel></rss>".utf8)
    }
    private func atom(_ entries: String) -> Data {
        Data("<feed xmlns=\"http://www.w3.org/2005/Atom\" xmlns:media=\"http://search.yahoo.com/mrss/\"><title>Feed</title>\(entries)</feed>".utf8)
    }
    private func json(_ items: String) -> Data {
        Data("{\"version\":\"https://jsonfeed.org/version/1.1\",\"title\":\"Feed\",\"items\":[\(items)]}".utf8)
    }
    private func translate(_ data: Data, start: Int = 0, capacity: Int = 10, config: SyndicationTargetConfiguration? = nil,
        observed: Date? = nil) throws -> SyndicationTranslation {
        let value = try SyndicationTranslator().translate(data: data,configuration: config ?? self.config(),observedAt: observed ?? self.observed,
            startIndex: start,itemCapacity: capacity)
        XCTAssertEqual(value.observations.count+value.rejections.count,value.examinedItemCount)
        XCTAssertLessThanOrEqual(value.examinedItemCount,capacity)
        return value
    }
    private func item(_ data: Data) throws -> AcquisitionObservation { try XCTUnwrap(translate(data).observations.first) }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func test01RSSGuid() throws {
        let value = try translate(rss("<item><guid isPermaLink=\"false\">Opaque:GUID</guid><link>https://example.test/other</link><title>Title</title><description><![CDATA[<b>Summary</b>]]></description></item>"))
        XCTAssertEqual(value.documentKind,.rss)
        let o = try XCTUnwrap(value.observations.first)
        XCTAssertEqual(o.objectIdentity.namespace,prefix+":rss-guid"); XCTAssertEqual(o.objectIdentity.value,"Opaque:GUID")
        XCTAssertEqual(o.objectIdentity.connectorKind,.syndication); XCTAssertEqual(o.objectIdentity.role,.object); XCTAssertNil(o.versionIdentity)
        XCTAssertEqual(o.headline,"Title"); XCTAssertEqual(o.summary,"<b>Summary</b>"); XCTAssertNil(o.bodyText); XCTAssertEqual(o.language,"pt-BR")
    }
    func test02RSSLinkFallback() throws {
        let o = try item(rss("<item><guid></guid><link>https://Example.test/A?Case=B</link></item>"))
        XCTAssertEqual(o.objectIdentity.namespace,prefix+":rss-link"); XCTAssertEqual(o.objectIdentity.value,"https://Example.test/A?Case=B")
    }
    func test03RSSMissingIdentityRejection() throws {
        let value = try translate(rss("<item><title>Only title</title></item>"))
        XCTAssertTrue(value.observations.isEmpty); XCTAssertEqual(value.rejections,[.init(index: 0,reason: .missingStableIdentity)])
    }
    func test04RSSPubDateIsNotVersion() throws {
        let o = try item(rss("<item><guid>g</guid><pubDate>Tue, 03 Jun 2003 09:39:21 GMT</pubDate></item>"))
        XCTAssertEqual(o.authoredAt,date("2003-06-03T09:39:21Z")); XCTAssertNil(o.modifiedAt); XCTAssertNil(o.versionIdentity)
    }
    func test05RDF() throws {
        let data = Data("""
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/">
        <channel rdf:about="https://example.test/feed"><title>Feed</title><link>https://example.test/</link><description>Feed</description></channel>
        <item rdf:about="https://example.test/a"><title>A</title><link>https://example.test/a</link></item>
        </rdf:RDF>
        """.utf8)
        let value = try translate(data); XCTAssertEqual(value.documentKind,.rdf)
        let o = try XCTUnwrap(value.observations.first)
        XCTAssertEqual(o.objectIdentity.namespace,prefix+":rdf-link"); XCTAssertEqual(o.objectIdentity.value,"https://example.test/a")
        XCTAssertNil(o.versionIdentity); XCTAssertNil(o.language)
    }
    func test06AtomIDUpdatedVersion() throws {
        let o = try item(atom("<entry><id>urn:Opaque:ID</id><title>Atom</title><summary type=\"text\">Summary</summary><published>2020-01-01T00:00:00Z</published><updated>2020-01-02T00:00:00Z</updated><link rel=\"self\" href=\"https://example.test/self\"/><link rel=\"ALTERNATE\" href=\"https://example.test/article\"/><content>Not copied</content></entry>"))
        XCTAssertEqual(o.objectIdentity.namespace,prefix+":atom-id"); XCTAssertEqual(o.objectIdentity.value,"urn:Opaque:ID")
        XCTAssertEqual(o.versionIdentity?.namespace,prefix+":atom-updated"); XCTAssertEqual(o.versionIdentity?.role,.version)
        XCTAssertEqual(o.versionIdentity?.value,String(date("2020-01-02T00:00:00Z").timeIntervalSinceReferenceDate.bitPattern,radix: 16))
        XCTAssertEqual(o.authoredAt,date("2020-01-01T00:00:00Z")); XCTAssertEqual(o.modifiedAt,date("2020-01-02T00:00:00Z"))
        XCTAssertEqual(o.primaryLink?.absoluteString,"https://example.test/article"); XCTAssertEqual(o.summary,"Summary"); XCTAssertNil(o.bodyText)
    }
    func test07AtomLinkFallback() throws {
        let o = try item(atom("<entry><link rel=\"enclosure\" href=\"https://example.test/audio\"/><link href=\"https://example.test/article\"/></entry>"))
        XCTAssertEqual(o.objectIdentity.namespace,prefix+":atom-link"); XCTAssertEqual(o.objectIdentity.value,"https://example.test/article")
    }
    func test08JSONIDModifiedVersionAndTextOnlyMapping() throws {
        let value = try translate(json("""
        {"id":"item-1","url":"https://example.com/permalink","external_url":"https://elsewhere.example/story","title":" exact é ","summary":" summary ","content_text":" text ","content_html":"<b>html</b>","date_published":"2020-01-01T00:00:00Z","date_modified":"2020-01-02T00:00:00Z","language":"PT"}
        """))
        XCTAssertEqual(value.documentKind,.json)
        let o = try XCTUnwrap(value.observations.first)
        XCTAssertEqual(o.objectIdentity.namespace,prefix+":json-id"); XCTAssertEqual(o.objectIdentity.value,"item-1")
        XCTAssertEqual(o.versionIdentity?.namespace,prefix+":json-modified"); XCTAssertEqual(o.versionIdentity?.role,.version)
        XCTAssertEqual(o.versionIdentity?.value,String(date("2020-01-02T00:00:00Z").timeIntervalSinceReferenceDate.bitPattern,radix: 16))
        XCTAssertEqual(o.bodyText," text "); XCTAssertEqual(o.summary," summary "); XCTAssertEqual(o.language,"PT")
        XCTAssertEqual(o.authoredAt,date("2020-01-01T00:00:00Z")); XCTAssertEqual(o.modifiedAt,date("2020-01-02T00:00:00Z"))
        XCTAssertEqual(o.primaryLink?.absoluteString,"https://example.com/permalink")
        let external = try item(json("{\"id\":\"item-2\",\"external_url\":\"https://elsewhere.example/story\"}"))
        XCTAssertEqual(external.primaryLink?.absoluteString,"https://elsewhere.example/story")
        XCTAssertEqual(external.objectIdentity.namespace,prefix+":json-id")
        XCTAssertEqual(external.objectIdentity.value,"item-2")
        XCTAssertNil(external.versionIdentity)
        let opaque = try item(json("{\"id\":\" Opaque ID \"}"))
        XCTAssertEqual(opaque.objectIdentity.value.utf8.map { $0 },Array(" Opaque ID ".utf8))
        XCTAssertNil(try item(json("{\"id\":\"html-only\",\"content_html\":\"<b>html</b>\"}")).bodyText)
    }
    func test09JSONFeedMissingRequiredIDFailsParse() throws {
        for items in [
            "{\"url\":\"https://example.com/permalink\",\"external_url\":\"https://elsewhere.example/story\",\"content_text\":\"text\"}",
            "{\"external_url\":\"https://elsewhere.example/story\"}"
        ] {
            // Throwing returns neither observations nor item-level rejections; links cannot rescue identity.
            XCTAssertThrowsError(try translate(json(items))) {
                XCTAssertEqual($0 as? SyndicationTranslationError, .parseFailed)
            }
        }
    }
    func test10TargetScopedIdentity() throws {
        let data = rss("<item><guid>same</guid></item>")
        let a = try translate(data), b = try translate(data,config: config(target: AcquisitionTargetID()))
        XCTAssertNotEqual(a.observations[0].objectIdentity,b.observations[0].objectIdentity)
    }
    func test11MembershipsExactOrderKindsAndNonempty() throws {
        let claims: [AcquisitionMembershipClaim] = [.init(sourceID: SourceID(),kind: .derived),.init(sourceID: source,kind: .direct)]
        let value = try translate(rss("<item><guid>g</guid></item>"),config: config(memberships: claims))
        XCTAssertEqual(value.observations[0].memberships,claims)
        XCTAssertNil(SyndicationTargetConfiguration(targetID: target,endpoint: config().endpoint,memberships: []))
    }
    func test12DuplicateSourceConfigRefused() {
        XCTAssertNil(SyndicationTargetConfiguration(targetID: target,endpoint: config().endpoint,memberships: [.init(sourceID: source,kind: .direct),.init(sourceID: source,kind: .derived)]))
    }
    func test13EndpointValidationAndExactPreservation() {
        for text in ["file:///feed","data:text/plain,feed","https:/missing","https://user@example.test/feed","https://:password@example.test/feed","https://user:password@example.test/feed"] {
            XCTAssertNil(SyndicationTargetConfiguration(targetID: target,endpoint: URL(string: text)!,memberships: [.init(sourceID: source,kind: .direct)]))
        }
        for text in ["http://Example.test/Feed?Case=A","HTTPS://Example.test/Feed?Case=A"] {
            let endpoint = URL(string: text)!, value = SyndicationTargetConfiguration(targetID: target,endpoint: endpoint,memberships: [.init(sourceID: source,kind: .direct)])!
            XCTAssertEqual(value.endpoint.absoluteString,endpoint.absoluteString)
        }
    }
    func test14ItemCapacityAndDeclaredPosition() throws {
        let data = rss("<item><guid>A</guid></item><item><guid>B</guid></item><item><guid>C</guid></item>")
        for index in 0..<3 {
            let value = try translate(data,start: index,capacity: 1)
            XCTAssertEqual(value.declaredItemCount,3); XCTAssertEqual(value.examinedItemCount,1)
            XCTAssertEqual(value.observations.count,1); XCTAssertEqual(value.observations[0].objectIdentity.value,["A","B","C"][index])
            XCTAssertEqual(value.nextItemIndex,index == 2 ? nil : index+1); XCTAssertEqual(value.consumedWholeDocument,index == 2)
        }
        XCTAssertEqual(try translate(data,capacity: .max).examinedItemCount,3)
    }
    func test15RejectionDoesNotRefill() throws {
        let data = rss("<item><title>Invalid</title></item><item><guid>valid</guid></item>")
        let value = try translate(data,capacity: 1)
        XCTAssertEqual(value.examinedItemCount,1); XCTAssertTrue(value.observations.isEmpty)
        XCTAssertEqual(value.rejections,[.init(index: 0,reason: .missingStableIdentity)]); XCTAssertEqual(value.nextItemIndex,1)
        let later = try translate(rss("<item><guid>first</guid></item><item><title>Invalid</title></item>"),start: 1,capacity: 1)
        XCTAssertEqual(later.rejections[0].index,1)
    }
    func test16StartAtEnd() throws {
        let value = try translate(rss("<item><guid>A</guid></item>"),start: 1)
        XCTAssertEqual(value.examinedItemCount,0); XCTAssertTrue(value.observations.isEmpty); XCTAssertTrue(value.rejections.isEmpty); XCTAssertTrue(value.consumedWholeDocument)
    }
    func test17StartBeyondEnd() {
        XCTAssertThrowsError(try translate(rss(""),start: 1)) { XCTAssertEqual($0 as? SyndicationTranslationError,.invalidStartIndex) }
        XCTAssertThrowsError(try translate(rss(""),start: -1)) { XCTAssertEqual($0 as? SyndicationTranslationError,.invalidStartIndex) }
    }
    func test18InvalidCapacity() {
        for value in [0,-1] { XCTAssertThrowsError(try translate(rss(""),capacity: value)) { XCTAssertEqual($0 as? SyndicationTranslationError,.invalidItemCapacity) } }
    }
    func test19MalformedFeed() {
        XCTAssertThrowsError(try translate(Data("unsupported malformed bytes".utf8))) { XCTAssertEqual($0 as? SyndicationTranslationError,.parseFailed) }
        XCTAssertThrowsError(try translate(json("{\"url\":\"https://example.com/permalink\"}"))) {
            XCTAssertEqual($0 as? SyndicationTranslationError,.parseFailed)
        }
    }
    func test20ObservedAtExactAndBaseline() throws {
        for data in [rss("<item><guid>g</guid></item>"),atom("<entry><id>a</id></entry>"),json("{\"id\":\"j\"}")] {
            let o = try item(data)
            XCTAssertEqual(o.observedAt,observed); XCTAssertEqual(o.precedence,.makeCurrent); XCTAssertEqual(o.availability,.available)
            XCTAssertNil(o.providerID); XCTAssertNil(o.searchProjection)
        }
        for value in [Double.nan,.infinity,-.infinity] {
            XCTAssertThrowsError(try translate(rss(""),observed: Date(timeIntervalSince1970: value))) { XCTAssertEqual($0 as? SyndicationTranslationError,.invalidObservedAt) }
        }
    }
    func test21RSSITunesImage() throws {
        let o = try item(rss("<item><guid>g</guid><itunes:image href=\"https://Example.test/Artwork?Size=A\"/></item>"))
        XCTAssertEqual(o.mediaCandidates.count,1); XCTAssertEqual(o.mediaCandidates[0].role,.cardVisual); XCTAssertEqual(o.mediaCandidates[0].mediaClass,.image)
        XCTAssertEqual(o.mediaCandidates[0].remoteURL.absoluteString,"https://Example.test/Artwork?Size=A")
    }
    func test22RSSMediaThumbnailDimensionsAndPrecedence() throws {
        let o = try item(rss("<item><guid>g</guid><media:thumbnail url=\"https://example.test/one\" width=\"20\" height=\"30\"/><media:thumbnail url=\"https://example.test/two\" width=\"20\"/><media:thumbnail url=\"https://example.test/three\" width=\"bad\" height=\"-1\"/><itunes:image href=\"https://example.test/art\"/></item>"))
        XCTAssertEqual(o.mediaCandidates.map(\.remoteURL.absoluteString),["https://example.test/art","https://example.test/one","https://example.test/two","https://example.test/three"])
        XCTAssertEqual(o.mediaCandidates.map(\.declaredPixelWidth),[nil,20,nil,nil]); XCTAssertEqual(o.mediaCandidates.map(\.declaredPixelHeight),[nil,30,nil,nil])
        XCTAssertTrue(o.mediaCandidates.allSatisfy { $0.declaredMimeType == nil })
    }
    func test23AtomMediaThumbnail() throws {
        let o = try item(atom("<entry><id>a</id><media:thumbnail url=\"https://example.test/A\"/><media:thumbnail url=\"https://example.test/B\" width=\"1\" height=\"2\"/></entry>"))
        XCTAssertEqual(o.mediaCandidates.map(\.remoteURL.absoluteString),["https://example.test/A","https://example.test/B"])
    }
    func test24JSONImageOrder() throws {
        let o = try item(json("{\"id\":\"j\",\"image\":\"https://example.test/image\",\"banner_image\":\"https://example.test/banner\"}"))
        XCTAssertEqual(o.mediaCandidates.map(\.remoteURL.absoluteString),["https://example.test/image","https://example.test/banner"])
    }
    func test25InvalidMediaURLDoesNotRejectContent() throws {
        let value = try translate(rss("<item><guid>g</guid><itunes:image href=\"file:///art\"/><media:thumbnail url=\"relative\"/></item>"))
        XCTAssertEqual(value.observations.count,1); XCTAssertTrue(value.rejections.isEmpty); XCTAssertTrue(value.observations[0].mediaCandidates.isEmpty)
    }
}
