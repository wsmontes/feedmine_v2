import Foundation
import XCTest
import FeedMineDomain
import FeedMineMedia
@testable import FeedMinePublication

/// D2 (PD-2026-10-20): the enclosure decides what a card is. Audio keeps the in-app player; video is identified
/// as video and opens its origin; an item with no playable payload states that absence and never invents a target.
final class PublishedMediaIdentityTests: XCTestCase {
    private let origin = OriginRevisionID()

    private func candidate(_ mime: String, url: String) throws -> MediaCandidate {
        let classOfEnclosure = try XCTUnwrap(MediaCandidateClass.playback(forMIME: mime),
            "the translator maps this enclosure MIME to a playable class")
        return try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: origin,
            role: classOfEnclosure.role, mediaClass: classOfEnclosure,
            remoteURL: XCTUnwrap(URL(string: url)), declaredMimeType: mime,
            declaredPixelWidth: nil, declaredPixelHeight: nil))
    }

    /// The translator's own vocabulary is what the rule reads: `audio/*` is audio, `video/*` is video.
    func testTheEnclosureMIMEIsWhatNamesTheKind() throws {
        XCTAssertEqual(try candidate("audio/mpeg", url: "https://example.test/episode.mp3").mediaClass, .audio)
        XCTAssertEqual(try candidate("video/mp4", url: "https://example.test/clip.mp4").mediaClass, .video)
        XCTAssertNil(MediaCandidateClass.playback(forMIME: "application/octet-stream"),
            "an enclosure it cannot classify is no playable payload")
    }

    /// Audio keeps exactly today's action: the enclosure is what the card plays.
    func testAudioKeepsThePlayableEnclosure() throws {
        let link = try XCTUnwrap(URL(string: "https://example.test/episode"))
        let decision = PublishedMediaDecision.resolve(
            playback: try candidate("audio/mpeg", url: "https://example.test/episode.mp3"), link: link)
        XCTAssertEqual(decision.identity, .audio)
        XCTAssertEqual(decision.primaryAction,
            .mediaPlayback(try XCTUnwrap(URL(string: "https://example.test/episode.mp3"))))
    }

    /// D2: a video card opens the item's own link — never the enclosure, and never the in-app player.
    func testVideoOpensTheOriginAndNeverTheEnclosure() throws {
        let link = try XCTUnwrap(URL(string: "https://example.test/article-with-clip"))
        let decision = PublishedMediaDecision.resolve(
            playback: try candidate("video/mp4", url: "https://example.test/clip.mp4"), link: link)
        XCTAssertEqual(decision.identity, .video)
        XCTAssertEqual(decision.primaryAction, .externalURL(link))
        XCTAssertNotEqual(decision.primaryAction,
            .mediaPlayback(try XCTUnwrap(URL(string: "https://example.test/clip.mp4"))))
    }

    /// D2: with no link there is nothing to open. The identity is still recorded honestly; no playable target is
    /// invented, because this build cannot play a video in-app.
    func testVideoWithoutALinkHasNoPlayableTarget() throws {
        let decision = PublishedMediaDecision.resolve(
            playback: try candidate("video/mp4", url: "https://example.test/clip.mp4"), link: nil)
        XCTAssertEqual(decision.identity, .video)
        XCTAssertNil(decision.primaryAction)
    }

    /// No enclosure: the card is not media at all, and it still opens its article when it has one.
    func testNoEnclosureIsNoneAndStillOpensTheArticle() throws {
        let link = try XCTUnwrap(URL(string: "https://example.test/story"))
        let withLink = PublishedMediaDecision.resolve(playback: nil, link: link)
        XCTAssertEqual(withLink.identity, .none)
        XCTAssertEqual(withLink.primaryAction, .externalURL(link))
        let withoutLink = PublishedMediaDecision.resolve(playback: nil, link: nil)
        XCTAssertEqual(withoutLink.identity, .none)
        XCTAssertNil(withoutLink.primaryAction)
    }

    /// The frozen value refuses a combination D2 forbids even if a caller builds it by hand.
    func testAFrozenCardRefusesInAppPlaybackForVideo() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/clip.mp4"))
        XCTAssertNil(try card(identity: .video, action: .mediaPlayback(url)))
        XCTAssertNotNil(try card(identity: .video, action: nil))
        XCTAssertNil(try card(identity: .audio, action: nil))
        XCTAssertNotNil(try card(identity: .unknown, action: .mediaPlayback(url)),
            "unknown history stays readable; it is just never treated as audio")
    }

    private enum StoredIdentity { case audio, video, unknown }

    private func card(identity: StoredIdentity, action: PublishedPrimaryAction?) throws -> PublishedCard? {
        let frozen: PublishedMediaIdentity? = switch identity {
        case .audio: .audio
        case .video: .video
        case .unknown: nil
        }
        return PublishedCard(id: PublicationCardID(),
            origin: PublishedOrigin(originRecordID: OriginRecordID(), originRevisionID: origin,
                sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil),
            contentEntityID: nil, contentClusterID: nil,
            text: PublishedText(title: "Title", primaryText: nil), timestamp: nil, media: .none,
            renderContract: try XCTUnwrap(RenderContract(layout: .textOnly, mediaAspectRatio: nil)),
            primaryAction: action, mediaIdentity: frozen)
    }
}
