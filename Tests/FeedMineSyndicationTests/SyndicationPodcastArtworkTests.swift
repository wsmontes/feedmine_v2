import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineAcquisition
import FeedMineSyndication

final class SyndicationPodcastArtworkTests: XCTestCase {
    private let target = AcquisitionTargetID()
    private let source = SourceID()
    private let observed = Date(timeIntervalSince1970: 1_700_000_000)
    private let audio = "<enclosure url=\"https://audio.example.test/episode.mp3\" type=\"audio/mpeg\"/>"
    private let show = "<itunes:image href=\"https://art.example.test/show.jpg\"/>"

    private func configuration() throws -> SyndicationTargetConfiguration {
        try XCTUnwrap(.init(targetID: target, endpoint: URL(string: "https://feeds.example.test/program/feed.xml")!,
            memberships: [.init(sourceID: source, kind: .direct)]))
    }

    private func episode(channel: String, item: String, observedAt: Date? = nil) throws -> AcquisitionObservation {
        let data = Data("""
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
            xmlns:media="http://search.yahoo.com/mrss/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel><title>Program</title>\(channel)
        <item><guid isPermaLink="false">episode-1</guid><title>Episode</title>
        <link>https://episodes.example.test/unrelated/episode-1</link>\(item)</item></channel></rss>
        """.utf8)
        let result = try SyndicationTranslator().translate(data: data, configuration: configuration(),
            observedAt: observedAt ?? observed, startIndex: 0, itemCapacity: 1)
        XCTAssertTrue(result.rejections.isEmpty)
        return try XCTUnwrap(result.observations.first)
    }

    func testAudioEpisodeUsesChannelITunesCoverBeforeRSSImageAndKeepsOnePlayback() throws {
        let value = try episode(channel: show + "<image><url>https://art.example.test/rss.jpg</url></image>",
            item: audio + "<media:content url=\"https://video.example.test/trailer.mp4\" medium=\"video\"/>")
        XCTAssertEqual(value.mediaCandidates.map(\.remoteURL.absoluteString),
            ["https://art.example.test/show.jpg", "https://audio.example.test/episode.mp3"])
        XCTAssertEqual(value.mediaCandidates.map(\.role), [.cardVisual, .playback])
        XCTAssertEqual(value.mediaCandidates.map(\.mediaClass), [.image, .audio])
        XCTAssertEqual(value.mediaCandidates.last?.declaredMimeType, "audio/mpeg")
    }

    func testEveryAdmittedItemVisualSuppressesChannelFallback() throws {
        let declarations = [
            "<itunes:image href=\"https://art.example.test/episode.jpg\"/>",
            "<media:thumbnail url=\"https://art.example.test/episode.jpg\" width=\"600\" height=\"600\"/>",
            "<media:content url=\"https://art.example.test/episode.jpg\" type=\"image/jpeg\"/>",
            "<media:group><media:thumbnail url=\"https://art.example.test/episode.jpg\"/></media:group>",
            "<description><![CDATA[<img src=\"https://art.example.test/episode.jpg\">]]></description>",
            "<content:encoded><![CDATA[<img src=\"https://art.example.test/episode.jpg\">]]></content:encoded>"
        ]
        for declaration in declarations {
            let value = try episode(channel: show, item: declaration + audio)
            XCTAssertEqual(value.mediaCandidates.map(\.remoteURL.absoluteString),
                ["https://art.example.test/episode.jpg", "https://audio.example.test/episode.mp3"], declaration)
        }
    }

    func testRejectedItemVisualDoesNotBlockShowCover() throws {
        let value = try episode(channel: show,
            item: "<itunes:image href=\"https://art.example.test/favicon.png\"/>" + audio)
        XCTAssertEqual(value.mediaCandidates.first?.remoteURL.absoluteString, "https://art.example.test/show.jpg")
        XCTAssertEqual(value.mediaCandidates.map(\.role), [.cardVisual, .playback])
    }

    func testRSSImageFallbackRetainsDeclaredDimensions() throws {
        for preferred in ["", "<itunes:image href=\"https://art.example.test/favicon.png\"/>"] {
            let value = try episode(channel: preferred + """
                <image><url>https://art.example.test/rss.jpg</url><width>1400</width><height>1400</height></image>
                """, item: audio)
            let image = try XCTUnwrap(value.mediaCandidates.first)
            XCTAssertEqual(image.remoteURL.absoluteString, "https://art.example.test/rss.jpg")
            XCTAssertEqual(image.role, .cardVisual)
            XCTAssertEqual(image.declaredPixelWidth, 1400)
            XCTAssertEqual(image.declaredPixelHeight, 1400)
        }
    }

    func testRelativeShowArtUsesChannelOrFeedBaseNeverEpisodePermalink() throws {
        let cases: [(String, String, String)] = [
            ("<link>https://shows.example.test/program/</link>", "covers/show.jpg",
                "https://shows.example.test/program/covers/show.jpg"),
            ("<link>/shows/program/</link>", "covers/show.jpg",
                "https://feeds.example.test/shows/program/covers/show.jpg"),
            ("", "covers/show.jpg", "https://feeds.example.test/program/covers/show.jpg"),
            ("<link>https://shows.example.test/program/</link>", "/covers/show.jpg",
                "https://shows.example.test/covers/show.jpg")
        ]
        for (link, locator, expected) in cases {
            for artwork in ["<itunes:image href=\"\(locator)\"/>", "<image><url>\(locator)</url></image>"] {
                let value = try episode(channel: link + artwork, item: audio)
                XCTAssertEqual(value.mediaCandidates.first?.remoteURL.absoluteString, expected)
                XCTAssertEqual(value.mediaCandidates.last?.remoteURL.absoluteString, "https://audio.example.test/episode.mp3")
            }
        }
    }

    func testDecorativeAndUnsafeChannelArtIsNeverAdmitted() throws {
        let rejected = [
            "https://art.example.test/favicon.png", "https://art.example.test/show-100x100.jpg",
            "https://art.example.test/pixel.gif", "https://art.example.test/show.svg",
            "https://art.example.test/episode.mp3", "https://127.0.0.1/show.jpg",
            "http://192.168.1.2/show.jpg", "http://169.254.169.254/show.jpg",
            "https://user:password@art.example.test/show.jpg", "file:///show.jpg",
            "data:image/png;base64,AAAA", "javascript:alert(1)", ""
        ]
        for locator in rejected {
            for artwork in ["<itunes:image href=\"\(locator)\"/>", "<image><url>\(locator)</url></image>"] {
                let value = try episode(channel: artwork, item: audio)
                XCTAssertEqual(value.mediaCandidates.map(\.role), [.playback], locator)
            }
        }
        let tiny = try episode(channel: """
            <image><url>https://art.example.test/show.jpg</url><width>88</width><height>31</height></image>
            """, item: audio)
        XCTAssertEqual(tiny.mediaCandidates.map(\.role), [.playback])
        let privateBase = try episode(channel:
            "<link>http://192.168.1.2/program/</link><itunes:image href=\"cover.jpg\"/>", item: audio)
        XCTAssertEqual(privateBase.mediaCandidates.map(\.role), [.playback])
    }

    func testInvalidPreferredCoverCanFallThroughToAdmittedRSSCover() throws {
        let value = try episode(channel: """
            <itunes:image href="http://127.0.0.1/show.jpg"/>
            <image><url>https://art.example.test/rss.jpg</url></image>
            """, item: audio)
        XCTAssertEqual(value.mediaCandidates.map(\.remoteURL.absoluteString),
            ["https://art.example.test/rss.jpg", "https://audio.example.test/episode.mp3"])
    }

    func testNewsAndNonAudioItemsDoNotInheritChannelLogo() throws {
        let channel = show + "<image><url>https://art.example.test/rss.jpg</url></image>"
        let cases: [(String, [MediaCandidateRole])] = [
            ("<description>News article without an image</description>", []),
            ("<itunes:duration>20:00</itunes:duration>", []),
            ("<enclosure url=\"https://audio.example.test/episode.mp3\"/>", []),
            ("<enclosure url=\"http://127.0.0.1/episode.mp3\" type=\"audio/mpeg\"/>", []),
            ("<enclosure url=\"https://video.example.test/episode.mp4\" type=\"video/mp4\"/>", [.playback]),
            ("<media:content url=\"https://video.example.test/episode.mp4\" medium=\"video\"/>", [.playback])
        ]
        for (declaration, roles) in cases {
            let value = try episode(channel: channel, item: declaration)
            XCTAssertEqual(value.mediaCandidates.map(\.role), roles, declaration)
        }
    }

    func testShowCoverChangeCreatesNewCanonicalMaterialWithoutRewritingOldRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        _ = try AcquisitionTargetAuthority(database: database).register(id: target, connectorKind: .syndication,
            authorizedSources: [source])
        let content = ContentStore(database: database)
        func admit(_ artwork: String, itemVisual: String = "", seconds: TimeInterval) throws -> (AdmissionReceipt, OriginRevision) {
            let value = try episode(channel: artwork, item: itemVisual + audio,
                observedAt: observed.addingTimeInterval(seconds))
            let batch = try XCTUnwrap(AcquisitionBatch(targetID: target, targetGeneration: 1,
                expectedCheckpointRevision: 0, observations: [value], nextCheckpoint: nil))
            let receipt = try AdmissionPolicy(database: database).admit(batch)
            XCTAssertTrue(receipt.rejectedObservations.isEmpty)
            let record = try XCTUnwrap(content.candidateWindow(sourceID: source, after: nil, examinedCapacity: 1).records.first)
            return (receipt, try XCTUnwrap(content.currentRevision(originRecordID: record.originRecordID)))
        }

        // Start with the old parser's text-only visual supply; discovering a cover is material even without dates.
        let (_, before) = try admit("", seconds: 0)
        let (added, first) = try admit(show, seconds: 1)
        XCTAssertTrue(added.selectableSupplyChanged)
        XCTAssertEqual(first.originRecordID, before.originRecordID)
        XCTAssertNotEqual(first.id, before.id)
        let originalMedia = try XCTUnwrap(content.mediaCandidates(originRevisionID: first.id))
        XCTAssertEqual(originalMedia.map(\.remoteURL.absoluteString),
            ["https://art.example.test/show.jpg", "https://audio.example.test/episode.mp3"])
        let (replay, same) = try admit(show, seconds: 2)
        XCTAssertFalse(replay.selectableSupplyChanged)
        XCTAssertEqual(same.id, first.id)
        let changedShow = "<itunes:image href=\"https://art.example.test/new-show.jpg\"/>"
        let (edited, next) = try admit(changedShow, seconds: 3)
        XCTAssertTrue(edited.selectableSupplyChanged)
        XCTAssertEqual(next.originRecordID, first.originRecordID)
        XCTAssertNotEqual(next.id, first.id)
        XCTAssertEqual(try content.mediaCandidates(originRevisionID: next.id)?.first?.remoteURL.absoluteString,
            "https://art.example.test/new-show.jpg")
        XCTAssertEqual(try content.originRevision(id: first.id), first)
        XCTAssertEqual(try content.mediaCandidates(originRevisionID: first.id), originalMedia)
        XCTAssertEqual(try content.mediaCandidates(originRevisionID: before.id)?.map(\.role), [.playback])
        XCTAssertEqual(try content.memberships(originRecordID: next.originRecordID).map(\.sourceID), [source])

        // Once the episode declares its own artwork, an unrelated show-cover change is no longer material.
        let itemVisual = "<itunes:image href=\"https://art.example.test/episode.jpg\"/>"
        let (_, ownArt) = try admit(show, itemVisual: itemVisual, seconds: 4)
        let (unrelated, unchanged) = try admit(changedShow, itemVisual: itemVisual, seconds: 5)
        XCTAssertFalse(unrelated.selectableSupplyChanged)
        XCTAssertEqual(unchanged.id, ownArt.id)
    }
}
