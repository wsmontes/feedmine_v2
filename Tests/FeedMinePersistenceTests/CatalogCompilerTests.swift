import Foundation
import GRDB
import XCTest

import FeedMineDomain
@testable import FeedMinePersistence

/// The catalog compiler, against the reference builder. Every expected value in this file was produced by V1's
/// `scripts/build_catalog.py` (the builder that compiled the shipped snapshot) run over exactly this fixture:
///
///     python3 feedmine/scripts/build_catalog.py --feeds-root <fixture> --output /tmp/oracle.sqlite --json
///
/// The fixture is written here rather than kept as a resource so the input the expectations were measured on is
/// readable in the test that asserts them. `FEEDMINE_REFERENCE_FEEDS_ROOT`/`FEEDMINE_REFERENCE_CATALOG` extend the
/// same comparison to a whole published tree in `CatalogCompilerReferenceTests`.
final class CatalogCompilerTests: XCTestCase {
    // MARK: - The fixture

    /// What the builder's own run over this fixture reported (and therefore what the compiler must report too).
    private static let oracle = (files: 6, failed: 1, invalidSources: 2, sources: 10, nodes: 12, placements: 10)

    /// The tree: a topical folder with nesting and two unusable addresses, a country folder, a language folder, a
    /// file at the root, one default-namespaced file, and one file that does not parse.
    private static let tree: [String: String] = [
        "01_News_&_Current_Affairs/01_News_&_Current_Affairs.opml": """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0">
              <head>
                <title>News &amp; Current Affairs</title>
                <language>en</language>
              </head>
              <body>
                <outline text="Economy &amp; Markets" title="Economy &amp; Markets">
                  <outline text="ICC" title="ICC" type="rss" xmlUrl="https://iccwbo.org/feed/" description="Insights from the ICC." language="en-US" category="trade,policy" feedmineNature="current-sensitive" feedmineActivity="prolific" feedmineQualityScore="95" feedmineDefaultEnabled="true" feedmineMediaKind="text" htmlUrl="https://iccwbo.org/" />
                  <outline title="Podcast Show" xmlUrl="https://feeds.megaphone.fm/somepodcast" category="business, finance" feedmineMediaKind="text" feedmineQualityScore="87" />
                  <outline title="Video Channel" xmlUrl="https://youtube.com/feeds/videos.xml?channel_id=ABC" feedmineMediaKind="video" />
                  <outline title="Audio Declared" xmlUrl="https://audio.example/feed" feedmineMediaKind="audio" />
                  <outline text="" xmlUrl="ftp://example.com/feed" />
                  <outline text="Not A URL" xmlUrl="not a url" />
                  <outline title="Disabled" xmlUrl="https://disabled.example/rss" feedmineDefaultEnabled="false" feedmineQualityScore="abc" language="und" />
                </outline>
                <outline text="Sport" title="Sport">
                  <outline text="Deep" title="Deep">
                    <outline title="Nested Feed" xmlUrl="http://nested.example/feed" />
                  </outline>
                </outline>
              </body>
            </opml>
            """,
        "90_countries/algeria/algeria.opml": """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0">
              <head>
                <title>algeria</title>
                <language>ar</language>
              </head>
              <body>
                <outline text="News &amp; Current Affairs" title="News &amp; Current Affairs">
                  <outline title="Algeria Today" xmlUrl="https://algeria.example/feed" feedmineMediaKind="text" />
                  <outline title="Undeclared" xmlUrl="https://algeria.example/other" language="und" />
                </outline>
              </body>
            </opml>
            """,
        "languages/pt/pt.opml": """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0">
              <head><title>pt</title><language>pt-BR</language></head>
              <body>
                <outline title="Notícias" xmlUrl="https://pt.example/feed" feedmineMediaKind="text" category="noticias,mundo" />
              </body>
            </opml>
            """,
        "global_feeds.opml": """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0">
              <head><title>global_feeds</title></head>
              <body>
                <outline title="Global One" xmlUrl="https://global.example/feed" feedmineQualityScore="50" />
              </body>
            </opml>
            """,
        "namespaced/namespaced.opml": """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0" xmlns="http://opml.org/spec2">
              <head><title>namespaced</title><language>fr</language></head>
              <body>
                <outline title="Namespaced Feed" xmlUrl="https://ns.example/feed" />
              </body>
            </opml>
            """,
        "broken.opml": """
            <?xml version="1.0" encoding="utf-8"?>
            <opml version="2.0">
              <body>
                <outline title="Before The Error" xmlUrl="https://before-error.example/feed" />
              </body>
            </opml
            """,
    ]

    private func writeTree(_ tree: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-fixture-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        for (relativePath, content) in tree {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }

    private func stage(in root: URL) -> URL {
        let url = root.appendingPathComponent("staging/catalog.sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return url
    }

    // MARK: - The compiled catalogue is the one the reader reads

    func testCompiledCatalogueIsReadByLegacyCatalogReaderWithoutChanges() throws {
        let root = try writeTree(Self.tree)
        let staging = stage(in: root)
        let report = try CatalogCompiler().compile(feedsRoot: root, staging: staging)

        XCTAssertEqual(report.sourceCount, Self.oracle.sources)
        XCTAssertEqual(report.nodeCount, Self.oracle.nodes)
        XCTAssertEqual(report.placementCount, Self.oracle.placements)
        XCTAssertEqual(report.fileCount, Self.oracle.files)
        XCTAssertEqual(report.failedFileCount, Self.oracle.failed)
        XCTAssertEqual(report.invalidSourceCount, Self.oracle.invalidSources)
        XCTAssertEqual(report.duplicateOccurrenceCount, 0)
        XCTAssertGreaterThan(report.sizeBytes, 0)
        XCTAssertEqual(report.sizeBytes,
            (try FileManager.default.attributesOfItem(atPath: staging.path)[.size] as? Int) ?? -1)

        let reader = try LegacyCatalogReader(catalogURL: staging)
        XCTAssertEqual(try reader.sourceCount(), Self.oracle.sources)

        // The catalogue's own declaration, which is what a verifier reconciles a manifest against.
        let metadata = try XCTUnwrap(reader.metadata())
        XCTAssertEqual(metadata.schemaVersion, LegacyCatalogReader.supportedSchemaVersion)
        XCTAssertEqual(metadata.revision, report.catalogVersion)
        XCTAssertEqual(metadata.sourceCount, Self.oracle.sources)
        XCTAssertEqual(metadata.nodeCount, Self.oracle.nodes)
        XCTAssertEqual(metadata.placementCount, Self.oracle.placements)
        XCTAssertEqual(metadata.fileCount, Self.oracle.files)
        XCTAssertEqual(metadata.failedFileCount, Self.oracle.failed)
        XCTAssertEqual(metadata.invalidSourceCount, Self.oracle.invalidSources)

        // A source, by exact identity: the reader's exact lookup keeps the fetch address, the declared language
        // and the nodes the source is *placed* at (not its ancestors — those are the node rows' own business).
        let icc = try XCTUnwrap(reader.source(key: "https://iccwbo.org/feed"))
        XCTAssertEqual(icc.title, "ICC")
        XCTAssertEqual(icc.requestURL, "https://iccwbo.org/feed/")
        XCTAssertEqual(icc.siteURL, "https://iccwbo.org/")
        XCTAssertEqual(icc.language, "en-US")
        XCTAssertEqual(icc.mediaKind, "text")
        XCTAssertEqual(icc.qualityScore, 95)
        XCTAssertEqual(icc.defaultEnabled, true)
        XCTAssertEqual(icc.nodeKeys, ["01-news-current-affairs/economy-markets"])

        // The catalogue facts T11 reads are on the paged read, which is where the editorial fields are filled.
        let paged = try reader.sources(after: "https://iccwbo.org/feed", limit: 1, onlyDefaultEnabled: false,
            mediaKinds: [])
        XCTAssertEqual(paged.map(\.key), ["https://nested.example/feed"])
        let fromStart = try reader.sources(after: nil, limit: 1, onlyDefaultEnabled: false, mediaKinds: ["text"])
        XCTAssertEqual(fromStart.count, 1)
        let rich = try XCTUnwrap(try reader.sources(after: nil, limit: 100, onlyDefaultEnabled: false, mediaKinds: [])
            .first { $0.key == "https://iccwbo.org/feed" })
        XCTAssertEqual(rich.sourceDescription, "Insights from the ICC.")
        XCTAssertEqual(rich.displayHost, "iccwbo.org")
        XCTAssertEqual(rich.tags, ["trade", "policy"])
        XCTAssertEqual(rich.nature, "current-sensitive")
        XCTAssertEqual(rich.activity, "prolific")

        // Taxonomy: the root's children are the sections the tree declared, read in the index's own order
        // (`parent_id, name COLLATE NOCASE`).
        XCTAssertEqual(try reader.sectionNodes().map(\.key),
            ["90_countries", "global", "languages", "01-news-current-affairs"])
        let countries = try reader.countries(limit: 10)
        XCTAssertEqual(countries.nodes.map(\.key), ["90_countries/algeria"])
        XCTAssertEqual(countries.nodes.first?.sourceCount, 2)

        // The country node holds no placements of its own — the tree places its sources under the topic leaf, as
        // the shipped catalogue does — so a country's sources are read through its subtree, in placement order.
        let algeria = try XCTUnwrap(countries.nodes.first)
        XCTAssertEqual(try reader.sources(inNode: algeria.id, limit: 10).records, [])
        XCTAssertEqual(try reader.sourceKeys(inSubtreeOf: algeria.id), ["https://algeria.example/feed",
            "https://algeria.example/other"])
        let leafID = try XCTUnwrap(try reader.nodes(parentID: algeria.id, limit: 10).nodes.first).id
        XCTAssertEqual(try reader.sources(inNode: leafID, limit: 10).records.map(\.title),
            ["Algeria Today", "Undeclared"])

        // Languages, including the undeclared bucket: the reader's own ordering, and a real count per bucket.
        let languages = try reader.languages()
        XCTAssertEqual(languages.map(\.code), ["en", "ar", "en-US", "pt-BR", "", "und"])
        XCTAssertEqual(languages.first { $0.code == "en" }?.totalSources, 4)
        XCTAssertEqual(languages.first { $0.code == "und" }?.enabledSources, 1)
        XCTAssertEqual(languages.first { $0.code == "" }?.isUndeclared, true)

        // The curated default set, paged the way the surfaces page it.
        let enabled = try reader.sources(after: nil, limit: 100, onlyDefaultEnabled: true, mediaKinds: [])
        XCTAssertEqual(enabled.count, 9)
        XCTAssertNil(enabled.first { $0.key.contains("disabled.example") })
        let audio = try reader.sources(after: nil, limit: 100, onlyDefaultEnabled: true, mediaKinds: ["audio"])
        XCTAssertEqual(audio.map(\.key).sorted(), ["https://audio.example/feed", "https://feeds.megaphone.fm/somepodcast"])
    }

    /// The two inputs the builder refuses to guess about: a file it cannot parse contributes nothing at all
    /// (not even the sources it parsed before the error), and a default-namespaced OPML is a file ElementTree
    /// finds no `body` in — so the reference build contributes nothing from it, and a build that did would
    /// disagree with the manifest's `sourceCount`.
    func testUnparseableFileIsDroppedAndNamespacedTreeContributesNothing() throws {
        let root = try writeTree(Self.tree)
        let staging = stage(in: root)
        _ = try CatalogCompiler().compile(feedsRoot: root, staging: staging)
        let reader = try LegacyCatalogReader(catalogURL: staging)
        XCTAssertNil(try reader.source(key: "https://before-error.example/feed"))
        XCTAssertNil(try reader.source(key: "https://ns.example/feed"))
        XCTAssertEqual(try reader.sources(after: nil, limit: 100, onlyDefaultEnabled: false, mediaKinds: []).count,
            Self.oracle.sources)
    }

    // MARK: - The derivations

    /// Ids, node paths, kinds and the media-kind precedence, each against the value the builder produced for this
    /// fixture. `id` is asserted against the literal and against the rule, because the rule is the public
    /// contract: a rebuild has to keep every source's id.
    func testDerivationsMatchTheReferenceBuilder() throws {
        let root = try writeTree(Self.tree)
        let staging = stage(in: root)
        _ = try CatalogCompiler().compile(feedsRoot: root, staging: staging)
        let queue = try DatabaseQueue(path: staging.path)

        // type of the id: the canonical URL identity, which is not the declared address (trailing `/`, scheme).
        let sources: [(id: Int64, key: String, title: String, declared: String, mediaKind: String, language: String?,
            quality: Int?, enabled: Bool, feedType: String?)] = [
            (134775528, "https://algeria.example/other", "Undeclared", "https://algeria.example/other", "text", "und",
                nil, true, nil),
            (204098000, "https://youtube.com/feeds/videos.xml?channel_id=ABC", "Video Channel",
                "https://youtube.com/feeds/videos.xml?channel_id=ABC", "video", "en", nil, true, nil),
            (312025372, "https://nested.example/feed", "Nested Feed", "http://nested.example/feed", "text", "en",
                nil, true, nil),
            (1500613855, "https://global.example/feed", "Global One", "https://global.example/feed", "text", nil,
                50, true, nil),
            (1518440942, "https://feeds.megaphone.fm/somepodcast", "Podcast Show",
                "https://feeds.megaphone.fm/somepodcast", "audio", "en", 87, true, nil),
            (1839657070, "https://algeria.example/feed", "Algeria Today", "https://algeria.example/feed", "text", "ar",
                nil, true, nil),
            (1907499022, "https://disabled.example/rss", "Disabled", "https://disabled.example/rss", "text", "und",
                nil, false, nil),
            (3045434990, "https://iccwbo.org/feed", "ICC", "https://iccwbo.org/feed/", "text", "en-US", 95, true,
                "rss"),
            (3825438557, "https://pt.example/feed", "Notícias", "https://pt.example/feed", "text", "pt-BR", nil, true,
                nil),
            (4266934898, "https://audio.example/feed", "Audio Declared", "https://audio.example/feed", "audio", "en",
                nil, true, nil),
        ]
        let rows = try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, key, title, declared_url, media_kind, language, quality_score, default_enabled, type
                FROM catalog_source ORDER BY id
                """)
        }
        XCTAssertEqual(rows.count, sources.count)
        for (row, expected) in zip(rows, sources) {
            let id: Int64 = row["id"]
            let key: String = row["key"]
            XCTAssertEqual(id, expected.id, "id of \(expected.key)")
            XCTAssertEqual(id, CatalogCompiler.stableIdentifier(forKey: key), "the id rule for \(key)")
            XCTAssertEqual(key, FeedAddress.identity(expected.declared), "identity of \(expected.declared)")
            XCTAssertEqual(key, expected.key)
            XCTAssertEqual(row["title"] as String, expected.title)
            XCTAssertEqual(row["declared_url"] as String, expected.declared)
            XCTAssertEqual(row["media_kind"] as String, expected.mediaKind, "media kind of \(expected.title)")
            XCTAssertEqual(row["language"] as String?, expected.language, "language of \(expected.title)")
            XCTAssertEqual(row["quality_score"] as Int?, expected.quality)
            XCTAssertEqual((row["default_enabled"] as Int64?) == 1, expected.enabled)
            XCTAssertEqual(row["type"] as String?, expected.feedType)
        }

        // Nodes: node_path from the folder tree plus the outline nesting, with the kinds the builder assigns. The
        // list is in the order the builder inserts them (by id), which is the order the query returns.
        let nodes: [(id: Int64, key: String, parent: Int64?, name: String, kind: Int, sources: Int, children: Int,
            language: String?)] = [
            (0, "root", nil, "Root", 0, 10, 4, nil),
            (333844902, "90_countries/algeria/news-current-affairs", 4087496191, "News & Current Affairs", 3, 2, 0,
                "ar"),
            (1145820100, "90_countries", 0, "Countries", 0, 2, 1, nil),
            (1681750652, "01-news-current-affairs", 0, "News & Current Affairs", 0, 6, 2, nil),
            (1823831290, "languages", 0, "Languages", 0, 1, 1, nil),
            (2116999343, "01-news-current-affairs/sport", 1681750652, "Sport", 3, 1, 1, "en"),
            (2147598964, "global", 0, "Global", 0, 1, 1, nil),
            (2229704856, "01-news-current-affairs/economy-markets", 1681750652, "Economy & Markets", 3, 5, 0, "en"),
            (2330971054, "01-news-current-affairs/sport/deep", 2116999343, "Deep", 3, 1, 0, "en"),
            (2525877054, "global/global-feeds", 2147598964, "Global Feeds", 3, 1, 0, nil),
            (4087496191, "90_countries/algeria", 1145820100, "Algeria", 1, 2, 1, nil),
            (4125165046, "languages/pt", 1823831290, "Pt", 4, 1, 0, "pt"),
        ]
        let nodeRows = try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, key, parent_id, name, kind, source_count, child_count, language FROM catalog_node
                ORDER BY id
                """)
        }
        XCTAssertEqual(nodeRows.count, nodes.count)
        for (row, expected) in zip(nodeRows, nodes) {
            let key: String = row["key"]
            XCTAssertEqual(row["id"] as Int64, expected.id, "id of node \(expected.key)")
            if expected.id != 0 {
                XCTAssertEqual(row["id"] as Int64, CatalogCompiler.stableIdentifier(forKey: key), "the id rule for \(key)")
            }
            XCTAssertEqual(key, expected.key)
            XCTAssertEqual(row["parent_id"] as Int64?, expected.parent, "parent of \(key)")
            XCTAssertEqual(row["name"] as String, expected.name)
            XCTAssertEqual(row["kind"] as Int, expected.kind, "kind of \(key)")
            XCTAssertEqual(row["source_count"] as Int, expected.sources, "source count of \(key)")
            XCTAssertEqual(row["child_count"] as Int, expected.children, "child count of \(key)")
            XCTAssertEqual(row["language"] as String?, expected.language, "language of \(key)")
        }

        // Placements: one per occurrence, in file then document order, carrying the overrides the builder writes.
        let placements: [(id: Int64, source: Int64, node: Int64, nodeName: String, file: String, order: Int64,
            language: String?, mediaKind: String)] = [
            (1, 3045434990, 2229704856, "Economy & Markets",
                "01_News_&_Current_Affairs/01_News_&_Current_Affairs.opml", 0, "en-US", "text"),
            (2, 1518440942, 2229704856, "Economy & Markets",
                "01_News_&_Current_Affairs/01_News_&_Current_Affairs.opml", 1, "en", "audio"),
            (3, 204098000, 2229704856, "Economy & Markets",
                "01_News_&_Current_Affairs/01_News_&_Current_Affairs.opml", 2, "en", "video"),
            (4, 4266934898, 2229704856, "Economy & Markets",
                "01_News_&_Current_Affairs/01_News_&_Current_Affairs.opml", 3, "en", "audio"),
            (5, 1907499022, 2229704856, "Economy & Markets",
                "01_News_&_Current_Affairs/01_News_&_Current_Affairs.opml", 4, "und", "text"),
            (6, 312025372, 2330971054, "Deep", "01_News_&_Current_Affairs/01_News_&_Current_Affairs.opml", 5, "en",
                "text"),
            (7, 1839657070, 333844902, "News & Current Affairs", "90_countries/algeria/algeria.opml", 1_000_000, "ar",
                "text"),
            (8, 134775528, 333844902, "News & Current Affairs", "90_countries/algeria/algeria.opml", 1_000_001, "und",
                "text"),
            (9, 1500613855, 2525877054, "Global Feeds", "global_feeds.opml", 3_000_000, nil, "text"),
            (10, 3825438557, 4125165046, "Pt", "languages/pt/pt.opml", 4_000_000, "pt-BR", "text"),
        ]
        let placementRows = try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, source_id, node_id, node_name, opml_file, sort_order, language_override,
                    media_kind_override FROM catalog_placement ORDER BY id
                """)
        }
        XCTAssertEqual(placementRows.count, placements.count)
        for (row, expected) in zip(placementRows, placements) {
            XCTAssertEqual(row["id"] as Int64, expected.id)
            XCTAssertEqual(row["source_id"] as Int64, expected.source)
            XCTAssertEqual(row["node_id"] as Int64, expected.node)
            XCTAssertEqual(row["node_name"] as String, expected.nodeName)
            XCTAssertEqual(row["opml_file"] as String, expected.file)
            XCTAssertEqual(row["sort_order"] as Int64, expected.order, "order of placement \(expected.id)")
            XCTAssertEqual(row["language_override"] as String?, expected.language, "language of placement \(expected.id)")
            XCTAssertEqual(row["media_kind_override"] as String?, expected.mediaKind)
        }
    }

    /// The editorial media-kind rules, spelled out: an explicit audio/video/forum wins, `text` does not (the
    /// builder's `EXPLICIT_MEDIA_KINDS`), and the file-name and URL guesses are what replaces it.
    func testMediaKindPrecedence() throws {
        XCTAssertEqual(CatalogOPMLScan.declaredMediaKind("audio"), "audio")
        XCTAssertEqual(CatalogOPMLScan.declaredMediaKind(" Text "), nil)
        XCTAssertEqual(CatalogOPMLScan.declaredMediaKind(nil), nil)
        XCTAssertEqual(CatalogOPMLScan.mediaKind(forURL: "https://x/podcast/rss", default: "text"), "audio")
        XCTAssertEqual(CatalogOPMLScan.mediaKind(forURL: "https://youtube.com/feeds/videos.xml", default: "text"), "video")
        XCTAssertEqual(CatalogOPMLScan.mediaKind(forURL: "https://www.reddit.com/r/swift/.rss", default: "text"), "forum")
        XCTAssertEqual(CatalogOPMLScan.mediaKind(forURL: "https://news.example/feed", default: "video"), "video")
        XCTAssertEqual(CatalogOPMLScan.mediaKind(forFileName: "15_Music_&_Audio"), "text")
        XCTAssertEqual(CatalogOPMLScan.mediaKind(forFileName: "podcasts"), "audio")
    }

    /// The slug/display-name rules the whole taxonomy is keyed by, including the folding.
    func testSlugAndDisplayNameRules() throws {
        XCTAssertEqual(CatalogOPMLScan.slug("01_News_&_Current_Affairs"), "01-news-current-affairs")
        XCTAssertEqual(CatalogOPMLScan.slug("Notícias"), "noticias")
        XCTAssertEqual(CatalogOPMLScan.slug("  "), "untitled")
        XCTAssertEqual(CatalogOPMLScan.semanticPathName("90_countries"), "countries")
        XCTAssertEqual(CatalogOPMLScan.semanticPathName("07_Sports"), "sports")
        XCTAssertEqual(CatalogOPMLScan.displayName("01_News_&_Current_Affairs"), "News & Current Affairs")
        XCTAssertEqual(CatalogOPMLScan.displayName("costa_rica"), "Costa Rica")
    }

    /// `display_host` is read out of the address text, as `urlsplit(...).hostname` reads it: the host the tree
    /// wrote, lowercased, without userinfo, port or brackets — and *not* through `URLComponents`, which decodes a
    /// punycode label into Unicode and re-encodes it as percent-escapes.
    func testDisplayHostIsReadFromTheDeclaredAddress() throws {
        XCTAssertEqual(CatalogOPMLScan.displayHost("https://www.AlJazeera.net:443/feed"), "www.aljazeera.net")
        XCTAssertEqual(CatalogOPMLScan.displayHost("https://xn--d1acibrhefqcr.bg/feed/"), "xn--d1acibrhefqcr.bg")
        XCTAssertEqual(CatalogOPMLScan.displayHost("https://user:pw@例え.jp:8080/x"), "例え.jp")
        XCTAssertEqual(CatalogOPMLScan.displayHost("https://[2001:db8::1]:8080/x"), "2001:db8::1")
        XCTAssertEqual(CatalogOPMLScan.displayHost("https://FEED.example/rss?x=1#f"), "feed.example")
        XCTAssertNil(CatalogOPMLScan.displayHost("feed.example/rss"))
        XCTAssertNil(CatalogOPMLScan.displayHost("https:///rss"))
    }

    /// The builder's trim is Python's `str.strip()`. A byte order mark is data, not whitespace, so it stays; the
    /// ASCII separators Unicode does not list as `White_Space` go.
    func testTrimFollowsPythonStrip() throws {
        XCTAssertEqual(CatalogOPMLScan.trimmed("  Py  "), "Py")
        XCTAssertEqual(CatalogOPMLScan.trimmed("\u{FEFF}Title"), "\u{FEFF}Title")
        XCTAssertEqual(CatalogOPMLScan.trimmed(" \u{FEFF}Title\u{FEFF} "), "\u{FEFF}Title\u{FEFF}")
        XCTAssertEqual(CatalogOPMLScan.trimmed("\u{1C}Title\u{1F}"), "Title")
        XCTAssertEqual(CatalogOPMLScan.trimmed("\u{00A0}Title\u{00A0}"), "Title")
        XCTAssertEqual(CatalogOPMLScan.trimmed("\u{0B}\tTitle\u{0C}"), "Title")
        XCTAssertEqual(CatalogOPMLScan.trimmed("\u{200B}Title"), "\u{200B}Title")
        XCTAssertEqual(CatalogOPMLScan.trimmed(""), "")
    }

    // MARK: - The full-text index

    /// The FTS table is produced and queryable — including the `path` column, which is the placement keys with `/`
    /// read as a space, so a taxonomy word finds the sources placed under it.
    func testFullTextIndexIsProducedAndQueryable() throws {
        let root = try writeTree(Self.tree)
        let staging = stage(in: root)
        _ = try CatalogCompiler().compile(feedsRoot: root, staging: staging)

        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: staging.path, configuration: configuration)
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM catalog_source_fts"), Self.oracle.sources)
            let algeria = try String.fetchAll(db, sql: """
                SELECT s.key FROM catalog_source_fts f JOIN catalog_source s ON s.id = f.rowid
                WHERE catalog_source_fts MATCH ? ORDER BY s.key
                """, arguments: ["\"algeria\""])
            XCTAssertEqual(algeria, ["https://algeria.example/feed", "https://algeria.example/other"])
            let taxonomy = try String.fetchAll(db, sql: """
                SELECT s.title FROM catalog_source_fts f JOIN catalog_source s ON s.id = f.rowid
                WHERE catalog_source_fts MATCH ? ORDER BY s.title
                """, arguments: ["\"economy\""])
            XCTAssertEqual(taxonomy.count, 5)
            let byHost = try String.fetchAll(db, sql: """
                SELECT s.title FROM catalog_source_fts f JOIN catalog_source s ON s.id = f.rowid
                WHERE catalog_source_fts MATCH ? ORDER BY s.title
                """, arguments: ["\"youtube.com\""])
            XCTAssertEqual(byHost, ["Video Channel"])
            // The index follows the source id, so a search result joins back to the row the reader pages.
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT rowid FROM catalog_source_fts WHERE title = ?",
                arguments: ["ICC"]), 3045434990)
        }
    }

    // MARK: - Refusals and publication

    /// Two files declaring one identity: the builder refuses to compile, and so does the compiler — before it
    /// publishes anything.
    func testIdentityCollapseIsRefusedAndNothingIsPublished() throws {
        let root = try writeTree([
            "a/first.opml": """
                <opml version="2.0"><body><outline title="First" xmlUrl="https://same.example/feed?utm_source=x" /></body></opml>
                """,
            "b/second.opml": """
                <opml version="2.0"><body><outline title="Second" xmlUrl="https://same.example/feed" /></body></opml>
                """,
        ])
        let staging = stage(in: root)
        XCTAssertThrowsError(try CatalogCompiler().compile(feedsRoot: root, staging: staging)) { error in
            guard case let CatalogCompilerError.sourceIdentityCollapse(key, firstURL, secondURL) = error else {
                return XCTFail("expected an identity collapse, got \(error)")
            }
            XCTAssertEqual(key, "https://same.example/feed")
            XCTAssertEqual(firstURL, "https://same.example/feed?utm_source=x")
            XCTAssertEqual(secondURL, "https://same.example/feed")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        let directory = staging.deletingLastPathComponent()
        let leftovers = FileManager.default.fileExists(atPath: directory.path)
            ? try FileManager.default.contentsOfDirectory(atPath: directory.path) : []
        XCTAssertEqual(leftovers, [], "a refused build leaves no staging file behind")
    }

    /// The staging file is published as a whole: what is replaced is the destination, and the build's own temp
    /// file never survives.
    func testPublicationReplacesTheDestinationAtomically() throws {
        let root = try writeTree(Self.tree)
        let staging = stage(in: root)
        try FileManager.default.createDirectory(at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("not a catalogue".utf8).write(to: staging)

        let report = try CatalogCompiler().compile(feedsRoot: root, staging: staging)
        XCTAssertEqual(report.output, staging.path)
        XCTAssertNoThrow(try LegacyCatalogReader(catalogURL: staging))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: staging.deletingLastPathComponent().path)
        XCTAssertEqual(siblings, ["catalog.sqlite"], "no temporary file is left beside the catalogue")
    }

    /// The report keeps the shape the release path reads (`scripts/bootstrap_catalog.py`): the builder's keys.
    func testReportKeepsTheBuildersJSONShape() throws {
        let root = try writeTree(Self.tree)
        let staging = stage(in: root)
        let report = try CatalogCompiler().compile(feedsRoot: root, staging: staging)
        let json = try JSONSerialization.jsonObject(with: try report.encoded()) as? [String: Any]
        let object = try XCTUnwrap(json)
        for key in ["file_count", "source_count", "failed_file_count", "invalid_source_count", "node_count",
                    "placement_count", "duplicate_occurrence_count", "size_bytes", "output"] {
            XCTAssertNotNil(object[key], "the report declares no \(key)")
        }
        XCTAssertEqual(object["file_count"] as? Int, Self.oracle.files)
        XCTAssertEqual(object["source_count"] as? Int, Self.oracle.sources)
        XCTAssertEqual(object["catalog_version"] as? Int64, report.catalogVersion)
    }

    func testMissingTreeIsRefused() throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-\(UUID().uuidString)/catalog.sqlite")
        addTeardownBlock { try? FileManager.default.removeItem(at: staging.deletingLastPathComponent()) }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-tree-\(UUID().uuidString)")
        XCTAssertThrowsError(try CatalogCompiler().compile(feedsRoot: missing, staging: staging)) { error in
            XCTAssertEqual(error as? CatalogCompilerError, .feedsRootUnreadable(missing.path))
        }
    }
}
