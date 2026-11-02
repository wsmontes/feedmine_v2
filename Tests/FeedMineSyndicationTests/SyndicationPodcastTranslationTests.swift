import Foundation
import XCTest
import FeedMineDomain
import FeedMineAcquisition
@testable import FeedMineSyndication

/// 2026-11-02, V1 podcast parity (`docs/reviews/2026-11-02-kiro-v1-lessons.md` and the podcast comparison): an
/// episode keeps the length its feed declared, an enclosure whose MIME type says nothing is still an episode when
/// its file is audio, and the show's artwork is the episode's last visual.
final class SyndicationPodcastTranslationTests: XCTestCase {
    private let target = AcquisitionTargetID(rawValue: UUID(uuidString: "123E4567-E89B-12D3-A456-426614174001")!)
    private let observed = Date(timeIntervalSince1970: 1_700_000_000)

    private func config() -> SyndicationTargetConfiguration {
        .init(targetID: target, endpoint: URL(string: "https://example.test/podcast.xml")!,
            memberships: [.init(sourceID: SourceID(), kind: .derived)])!
    }
    private func rss(channel: String = "", _ items: String) -> Data {
        Data("""
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" \
        xmlns:media="http://search.yahoo.com/mrss/"><channel><title>Show</title>\(channel)\(items)</channel></rss>
        """.utf8)
    }
    private func items(_ data: Data) throws -> [AcquisitionObservation] {
        try SyndicationTranslator().translate(data: data, configuration: config(), observedAt: observed,
            startIndex: 0, itemCapacity: 10).observations
    }
    private func item(_ data: Data) throws -> AcquisitionObservation { try XCTUnwrap(items(data).first) }
    private func playback(_ o: AcquisitionObservation) -> AcquisitionMediaCandidateClaim? {
        o.mediaCandidates.first { $0.role == .playback }
    }

    func testDeclaredDurationTravelsWithThePlaybackCandidate() throws {
        let o = try item(rss("""
            <item><guid>e1</guid><itunes:duration>1:02:03</itunes:duration>\
            <enclosure url="https://cdn.example.test/e1.mp3" type="audio/mpeg" length="1"/></item>
            """))
        XCTAssertEqual(playback(o)?.declaredDurationSeconds, 3_723)
        XCTAssertNil(o.mediaCandidates.first { $0.role == .cardVisual }?.declaredDurationSeconds,
            "only the playback candidate states a length")
    }

    func testAbsentOrImplausibleDurationIsNotDeclared() throws {
        let none = try item(rss("<item><guid>e2</guid><enclosure url=\"https://cdn.example.test/e2.mp3\" type=\"audio/mpeg\"/></item>"))
        XCTAssertNil(playback(none)?.declaredDurationSeconds)
        XCTAssertNotNil(playback(none), "the episode is still an episode")
        XCTAssertNil(SyndicationTranslator.declaredSeconds(0))
        XCTAssertNil(SyndicationTranslator.declaredSeconds(.infinity))
        XCTAssertNil(SyndicationTranslator.declaredSeconds(400_000), "a placeholder of days is not a length")
        XCTAssertEqual(SyndicationTranslator.declaredSeconds(59.6), 60)
    }

    func testAnUntypedOrGenericEnclosureIsAnEpisodeWhenItsFileIsAudio() throws {
        let untyped = try item(rss("<item><guid>e3</guid><enclosure url=\"https://cdn.example.test/e3.mp3?token=1\"/></item>"))
        XCTAssertEqual(playback(untyped)?.mediaClass, .audio, "V1's isAudioCandidate: the path decides, not the query")
        XCTAssertNil(playback(untyped)?.declaredMimeType, "the declaration stays what the feed said")
        let generic = try item(rss("""
            <item><guid>e4</guid><enclosure url="https://cdn.example.test/e4.m4a" type="application/octet-stream"/></item>
            """))
        XCTAssertEqual(playback(generic)?.mediaClass, .audio)
        XCTAssertEqual(playback(generic)?.declaredMimeType, "application/octet-stream")
    }

    func testASpecificNonAudioTypeOrANonAudioFileIsNeverGuessed() throws {
        let page = try item(rss("<item><guid>e5</guid><enclosure url=\"https://cdn.example.test/e5.mp3\" type=\"text/html\"/></item>"))
        XCTAssertNil(playback(page), "a declared page is not overruled by its file name")
        let document = try item(rss("<item><guid>e6</guid><enclosure url=\"https://cdn.example.test/e6.pdf\"/></item>"))
        XCTAssertNil(playback(document))
        XCTAssertTrue(SyndicationTranslator.isGenericMIME(nil))
        XCTAssertTrue(SyndicationTranslator.isGenericMIME(" Application/Octet-Stream; charset=binary "))
        XCTAssertFalse(SyndicationTranslator.isGenericMIME("audio/mpeg"))
    }

    func testTheShowArtworkIsTheLastVisualOfAnEpisodeAndOfNothingElse() throws {
        let channel = "<itunes:image href=\"https://cdn.example.test/show-3000x3000.jpg\"/>"
        let values = try items(rss(channel: channel, """
            <item><guid>bare</guid><enclosure url="https://cdn.example.test/bare.mp3" type="audio/mpeg"/></item>\
            <item><guid>own</guid><itunes:image href="https://cdn.example.test/own.jpg"/>\
            <enclosure url="https://cdn.example.test/own.mp3" type="audio/mpeg"/></item>\
            <item><guid>article</guid><link>https://site.example.test/a</link><title>Text</title></item>
            """))
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0].mediaCandidates.map(\.remoteURL.absoluteString),
            ["https://cdn.example.test/show-3000x3000.jpg", "https://cdn.example.test/bare.mp3"],
            "an episode with no art of its own gets the show's, before its playback (ordinal 0 is the visual)")
        XCTAssertEqual(values[1].mediaCandidates.map(\.remoteURL.absoluteString),
            ["https://cdn.example.test/own.jpg", "https://cdn.example.test/show-3000x3000.jpg",
             "https://cdn.example.test/own.mp3"],
            "the episode's own art stays first; the show's is the fallback when it cannot be prepared")
        XCTAssertTrue(values[2].mediaCandidates.isEmpty, "a text item never borrows the show's art")
    }

    func testTheChannelImageIsUsedOnlyWhenItDoesNotLookLikeALogo() throws {
        let logo = try item(rss(channel: "<image><url>https://site.example.test/wp-content/site-logo.png</url></image>",
            "<item><guid>l</guid><enclosure url=\"https://cdn.example.test/l.mp3\" type=\"audio/mpeg\"/></item>"))
        XCTAssertEqual(logo.mediaCandidates.map(\.role), [.playback])
        let art = try item(rss(channel: "<image><url>https://cdn.example.test/cover.jpg</url></image>",
            "<item><guid>c</guid><enclosure url=\"https://cdn.example.test/c.mp3\" type=\"audio/mpeg\"/></item>"))
        XCTAssertEqual(art.mediaCandidates.map(\.remoteURL.absoluteString),
            ["https://cdn.example.test/cover.jpg", "https://cdn.example.test/c.mp3"])
    }
}
