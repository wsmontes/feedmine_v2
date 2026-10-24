import Foundation
import XCTest
import FeedMineDomain
import FeedMineMedia
@testable import FeedMinePublication
@testable import FeedMineRuntime

/// D2 (PD-2026-10-20): the presentation states what the publication froze. An unknown identity is history, and
/// it is never presented as playable audio just because the card's action kind says `mediaPlayback`.
final class PresentationMediaIdentityTests: XCTestCase {
    private func presentation(identity: PublishedMediaIdentity?, action: PublishedPrimaryAction?) throws
        -> PresentationCard {
        let card = try XCTUnwrap(PublishedCard(id: PublicationCardID(),
            origin: PublishedOrigin(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                sourceID: SourceID(), providerID: nil, sourceDisplayName: "Fonte", providerDisplayName: nil),
            contentEntityID: nil, contentClusterID: nil,
            text: PublishedText(title: "Título", primaryText: nil), timestamp: nil, media: .none,
            renderContract: try XCTUnwrap(RenderContract(layout: .textOnly, mediaAspectRatio: nil)),
            primaryAction: action, mediaIdentity: identity))
        return PresentationCard(publishedCard: card)
    }

    func testAudioIsPlayableAndVideoIsIdentifiedWithoutThePlayer() throws {
        let audio = try presentation(identity: .audio,
            action: .mediaPlayback(try XCTUnwrap(URL(string: "https://example.test/ep.mp3"))))
        XCTAssertEqual(audio.mediaIdentity, .audio)
        XCTAssertTrue(audio.playsAudio)
        XCTAssertFalse(audio.identifiesVideo)

        let video = try presentation(identity: .video,
            action: .externalURL(try XCTUnwrap(URL(string: "https://example.test/story"))))
        XCTAssertEqual(video.mediaIdentity, .video)
        XCTAssertFalse(video.playsAudio, "D2: a video card never offers the in-app player")
        XCTAssertTrue(video.identifiesVideo)
        XCTAssertEqual(video.primaryActionKind, .externalURL, "and it opens the origin")
    }

    func testUnknownIdentityIsNeverTreatedAsPlayableAudio() throws {
        // A card written before the fact existed keeps its frozen action, but the identity stays unknown.
        let legacy = try presentation(identity: nil,
            action: .mediaPlayback(try XCTUnwrap(URL(string: "https://example.test/ep.mp3"))))
        XCTAssertNil(legacy.mediaIdentity)
        XCTAssertFalse(legacy.playsAudio)
        XCTAssertFalse(legacy.identifiesVideo)
        XCTAssertEqual(legacy.primaryActionKind, .mediaPlayback, "the frozen action itself is still readable")
    }

    func testDecodedPixelsNeverChangeTheIdentity() throws {
        let card = try presentation(identity: .video, action: nil)
        XCTAssertEqual(card.withDecodedImage(nil).mediaIdentity, .video)
        XCTAssertEqual(card.releasingDecodedImage().mediaIdentity, .video)
    }
}
