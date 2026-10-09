import Foundation
import XCTest
import FeedMineDomain
import FeedMineEditorial
import FeedMinePublication
import FeedMineRuntime
import FeedMinePersistence

final class PublishedTextNormalizationTests: XCTestCase {
    private func text(_ value: String?, title: String? = nil) throws -> PublishedText {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentStore(database: try RuntimeDatabase(location: .init(directory: root))), source = SourceID()
        let origin = OriginRecordID(), revisionID = OriginRevisionID(), date = Date(timeIntervalSince1970: 1)
        let raw = OriginRevision(id: revisionID, originRecordID: origin, externalVersionIdentity: nil, headline: title,
            summary: value, bodyText: nil, authoredAt: nil, modifiedAt: nil, observedAt: date, language: nil,
            primaryLink: nil, searchProjection: nil, providerID: nil)
        try store.commitCanonicalChange(.init(recordID: origin, externalObjectIdentity: .init(connectorKind: .syndication,
            namespace: "normalization", value: "stable", role: .object), revision: raw, mediaCandidates: [], availability: .available,
            observedAt: date, expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: date)]))
        let v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: .init(request: .main), catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v, sequencingPolicyVersion: v,
            exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let plan = try XCTUnwrap(FeedPlan(context: .init(request: .main), revision: revision))
        let candidate = try XCTUnwrap(CandidateProvider(contentStore: store).candidates(for: plan, after: nil, examinedCapacity: 1).candidates.first)
        let selection = SelectionResult(editorialRevision: revision, orderedCandidates: [candidate],
            supplyReport: .init(examinedCount: 1, nextCursor: nil, exhausted: true))
        let input = PublicationPreparationInput(origin: .init(originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID,
            sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil), contentEntityID: nil, contentClusterID: nil,
            primaryAction: .localContentDetail, presentation: .textOnly)
        let draft = try XCTUnwrap(PublicationPreparation.drafts(selection: selection, inputs: [input]).first)
        XCTAssertEqual(draft.origin.originRecordID, candidate.originRecordID)
        XCTAssertEqual(draft.primaryAction, .localContentDetail)
        XCTAssertEqual(try store.originRevision(id: revisionID), raw)
        XCTAssertEqual(draft.text.primaryText, candidate.summary); XCTAssertEqual(draft.text.title, candidate.headline)
        return draft.text
    }
    private func check(_ input: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try text(input).primaryText, expected, file: file, line: line)
        XCTAssertEqual(try text(nil, title: input).title, expected, file: file, line: line)
    }
    func testH1H2H3ParagraphsBlocksAndBreaks() throws {
        try check("<p>Hello</p>", "Hello")
        try check("<p>Hello</p><p>World</p>", "Hello\n\nWorld")
        try check("<div>First<br>Second</div>", "First\nSecond")
        try check("a<BR/>b<br />c", "a\nb\nc")
        try check("<article><section><h1>Heading</h1><ul><li>One</li><li>Two</li></ul></section></article>", "Heading\n\nOne\n\nTwo")
    }
    func testH4H5EntitiesAndInvalidScalars() throws {
        try check("&amp; &lt; &gt; &quot; &apos; &nbsp; &copy; &reg; &trade; &hellip; &mdash; &ndash; &lsquo; &rsquo; &ldquo; &rdquo; &bull;", "& < > \" '   © ® ™ … — – ‘ ’ “ ” •")
        try check("&#65;&#x41;&#X41; &#128512; &#x1F600;", "AAA 😀 😀")
        try check("&#+65; &#x+41; &#-0; &#x-0;", "&#+65; &#x+41; &#-0; &#x-0;")
        try check("&unknown; &#xD800; &#1114112; &#xZZ; &amp", "&unknown; &#xD800; &#1114112; &#xZZ; &amp")
        try check("&amp;lt;p&amp;gt;literal&amp;lt;/p&amp;gt;", "&lt;p&gt;literal&lt;/p&gt;")
        try check("&lt;b&gt;literal&lt;/b&gt;", "<b>literal</b>")
    }
    /// v1 lesson IN-6: every entity missing from a curated subset became a user-visible bug.
    func testH5bCompleteHTML4NamedEntities() throws {
        try check("&eacute;t&eacute; &Ccedil;a &atilde;o &uuml;ber &szlig; &ntilde;", "\u{E9}t\u{E9} \u{C7}a \u{E3}o \u{FC}ber \u{DF} \u{F1}")
        try check("&euro;5 &pound;3 &yen; &cent; &deg;C &frac12; &times; &divide; &plusmn;",
            "\u{20AC}5 \u{A3}3 \u{A5} \u{A2} \u{B0}C \u{BD} \u{D7} \u{F7} \u{B1}")
        try check("&laquo;cita&raquo; &sbquo;a&lsquo; &bdquo;b&ldquo; &lsaquo;c&rsaquo;",
            "\u{AB}cita\u{BB} \u{201A}a\u{2018} \u{201E}b\u{201C} \u{2039}c\u{203A}")
        try check("&Alpha;&Omega;&alpha;&sigmaf;&omega; &rarr;&hArr; &ne;&le;&infin;&sum; &hearts;&diams;",
            "\u{391}\u{3A9}\u{3B1}\u{3C2}\u{3C9} \u{2192}\u{21D4} \u{2260}\u{2264}\u{221E}\u{2211} \u{2665}\u{2666}")
        try check("&OElig;uvre &Scaron; &Yuml; &yuml; &fnof; &dagger;&Dagger; &permil;",
            "\u{152}uvre \u{160} \u{178} \u{FF} \u{192} \u{2020}\u{2021} \u{2030}")
        // Names are case-sensitive; an unknown case variant stays literal.
        try check("&EACUTE; &Eacute;", "&EACUTE; \u{C9}")
    }
    func testH6H7H8UnicodeLinksAndInlineMarkup() throws {
        try check("<span>Olá <strong>世界 <em>😀</em></strong></span>", "Olá 世界 😀")
        try check("<a href='https://readable.test/?a=1>0' onclick='bad()'>Read more</a>", "Read more")
        try check("<custom-widget>Editorial <b>text</b></custom-widget>", "Editorial text")
    }
    func testH9RawTextAndCommentsNeverLeak() throws {
        try check("Hello<script>alert('<b>bad</b>')</script>World", "HelloWorld")
        try check("a<STYLE>.x{color:red}</STYLE>b<iframe src='https://readable.test'>bad</iframe>c<object>bad</object>d<embed>bad</embed>e", "abcde")
        try check("a<!-- hidden <b>comment</b> -->b<img src='https://readable.test/a.png'>c", "abc")
        try check("safe<script>unclosed code", "safe")
        try check("safe<!-- unclosed comment", "safe")
        try check("a<script>bad </scripture> still bad</script>b", "ab")
    }
    func testH10H11PlainTextRemainsByteIdentical() throws {
        for input in ["2 < 3 and 5 > 4", "A & B", "  text  \n\n\n  next\tline ", "e\u{301} 😀 ∑x ≤ y", "https://readable.test/a?x=1&y=2", "<3", "x < y > z"] {
            XCTAssertEqual(try text(input).primaryText?.utf8.map { $0 }, Array(input.utf8))
            XCTAssertEqual(try text(nil, title: input).title?.utf8.map { $0 }, Array(input.utf8))
        }
    }
    func testH12MalformedMarkupPreservesSafeText() throws {
        try check("<p>Hello <em>World", "Hello World")
        try check("text <broken", "text <broken")
        try check("text <a href='unterminated", "text <a href='unterminated")
        try check("text <broken <b>safe</b>", "text <broken safe")
    }
    func testH13SeparatorsDoNotCreateEmptyParagraphs() throws {
        try check("<div>\n  <p> Hello </p>\n<p> World </p>\n</div>", "Hello\n\nWorld")
        try check("<div><p><b>Hello</b></p></div><div>World</div>", "Hello\n\nWorld")
        try check("<span>Hello</span>, <em>world</em>!", "Hello, world!")
        try check("<pre>a  b\n c</pre>", "a  b\n c")
    }
    func testH14NilEmptyAndNoUsefulContentRetainOptionalContract() throws {
        XCTAssertNil(try text(nil).primaryText); XCTAssertNil(try text(nil).title)
        try check("", "")
        try check("<p></p><script>bad</script><img src='https://readable.test/a'>", "")
    }
    func testT1T2T3TitlesUseSamePreparation() throws {
        XCTAssertEqual(try text(nil, title: "<em>Headline</em>").title, "Headline")
        XCTAssertEqual(try text(nil, title: "Tom &amp; Jerry").title, "Tom & Jerry")
        XCTAssertEqual(try text(nil, title: "Plain headline").title, "Plain headline")
    }
    func testP10LargeAndPathologicalInputsWithoutTruncation() throws {
        let fragment = "<div>Olá &amp; 世界<br>😀</div>"
        let input = String(repeating: fragment, count: 20_000)
        let expected = Array(repeating: "Olá & 世界\n😀", count: 20_000).joined(separator: "\n\n")
        XCTAssertEqual(try text(input).primaryText, expected)
        let malformed = String(repeating: "<a ", count: 20_000)
        XCTAssertEqual(try text(malformed).primaryText, malformed)
        let entities = String(repeating: "&unknown", count: 20_000)
        XCTAssertEqual(try text(entities).primaryText, entities)
    }
}
