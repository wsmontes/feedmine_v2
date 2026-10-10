import XCTest
import FeedMineDomain

/// T10: reading an OPML file as values — nesting, duplicates, unicode, malformed input — and writing one back.
final class OPMLDocumentTests: XCTestCase {
    private func data(_ body: String, title: String = "Assinaturas") -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0"><head><title>\(title)</title></head><body>\(body)</body></opml>
        """.utf8)
    }

    /// V1's rule: an outline with `xmlUrl` is a feed, an outline without one is a category that may nest, and
    /// the category path arrives outermost first.
    func testNestedCategoriesBecomeTheEntrysPath() throws {
        let preview = try OPMLDocument.preview(data("""
        <outline text="Ciência">
          <outline text="Brasil">
            <outline type="rss" text="Revista" xmlUrl="https://revista.example/feed"/>
          </outline>
        </outline>
        <outline type="rss" text="Solto" xmlUrl="https://solto.example/rss"/>
        """))
        XCTAssertEqual(preview.name, "Assinaturas")
        XCTAssertEqual(preview.entries.map(\.title), ["Revista", "Solto"])
        XCTAssertEqual(preview.entries[0].categoryPath, ["Ciência", "Brasil"])
        XCTAssertTrue(preview.entries[1].categoryPath.isEmpty)
        XCTAssertEqual(preview.entries[0].id, FeedAddress.identity("https://revista.example/feed"))
        XCTAssertEqual(preview.repeats, 0)
        XCTAssertTrue(preview.rejections.isEmpty)
    }

    /// The same feed twice — in different categories, or spelled differently — is one entry, and the first
    /// occurrence wins. The fetchable address of that first occurrence is what is kept.
    func testRepeatsFollowTheIdentityAndTheFirstOccurrenceWins() throws {
        let preview = try OPMLDocument.preview(data("""
        <outline type="rss" text="Primeiro" xmlUrl="https://www.example.com/feed/?token=abc"/>
        <outline type="rss" text="Repetido" xmlUrl="HTTPS://example.com:443/feed?token=abc"/>
        """))
        XCTAssertEqual(preview.entries.count, 1)
        XCTAssertEqual(preview.repeats, 1)
        XCTAssertEqual(preview.entries[0].title, "Primeiro")
        XCTAssertEqual(preview.entries[0].requestURL, "https://www.example.com/feed/?token=abc",
            "the first occurrence's own request address is kept verbatim")
        XCTAssertEqual(preview.entries[0].id, "https://example.com/feed",
            "the two spellings agree once identity strips www, forces https and drops the signed parameter")
    }

    /// Unicode titles and addresses survive the parse, and an entry this build could never fetch is reported
    /// rather than dropped in silence.
    func testUnicodeSurvivesAndUnusableAddressesAreReported() throws {
        let preview = try OPMLDocument.preview(data("""
        <outline type="rss" text="Áudio &amp; Vídeo – São Paulo" xmlUrl="https://例え.jp/feed?q=ção"/>
        <outline type="rss" text="Sem esquema" xmlUrl="example.com/feed"/>
        <outline text="Categoria vazia"/>
        """))
        XCTAssertEqual(preview.entries.map(\.title), ["Áudio & Vídeo – São Paulo"])
        XCTAssertEqual(preview.entries[0].requestURL, "https://例え.jp/feed?q=%C3%A7%C3%A3o",
            "a request address is percent-normalised, so the same feed offered two ways is one address")
        XCTAssertEqual(preview.rejections.map(\.reason), [.unusableAddress, .emptyCategory])
        XCTAssertEqual(preview.rejections[0].rawAddress, "example.com/feed")
        XCTAssertEqual(preview.rejections[1].title, "Categoria vazia")
    }

    /// A file that is not XML is an error, not an empty preview: the reader is told the file could not be read.
    func testMalformedInputThrows() {
        XCTAssertThrowsError(try OPMLDocument.preview(Data("<not xml".utf8))) { error in
            guard case OPMLDocumentError.malformed = error else { return XCTFail("expected a malformed error") }
        }
        XCTAssertThrowsError(try OPMLDocument.preview(Data("not a document at all".utf8)))
    }

    /// Round trip: what an export writes, an import reads back with the same identities, requests and paths.
    func testTheWrittenDocumentReadsBackWhole() throws {
        let entries = [
            ReaderImportEntry(id: "https://a.example/feed", title: "Alpha & Beta",
                requestURL: "https://a.example/feed?token=1", categoryPath: ["Ciência"]),
            ReaderImportEntry(id: "https://b.example/feed", title: "Áudio",
                requestURL: "https://b.example/feed", categoryPath: ["Ciência", "Podcasts"]),
            ReaderImportEntry(id: "https://c.example/feed", title: "Solto",
                requestURL: "https://c.example/feed", categoryPath: []),
        ]
        let document = OPMLDocument.opml(title: "Minhas fontes", entries: entries,
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(document.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(document.contains("<title>Minhas fontes</title>"))
        let preview = try OPMLDocument.preview(Data(document.utf8))
        XCTAssertEqual(preview.name, "Minhas fontes")
        XCTAssertEqual(preview.entries.map(\.title), ["Solto", "Alpha & Beta", "Áudio"],
            "top-level feeds draw first, then the categories in their own order")
        XCTAssertEqual(Set(preview.entries.map(\.id)), Set(entries.map(\.id)))
        let alpha = try XCTUnwrap(preview.entries.first { $0.title == "Alpha & Beta" })
        XCTAssertEqual(alpha.requestURL, "https://a.example/feed?token=1",
            "the request address survives the round trip, entities and all")
        XCTAssertEqual(alpha.categoryPath, ["Ciência"])
        let audio = try XCTUnwrap(preview.entries.first { $0.title == "Áudio" })
        XCTAssertEqual(audio.categoryPath, ["Ciência", "Podcasts"])
        XCTAssertEqual(preview.repeats, 0)
    }
}
