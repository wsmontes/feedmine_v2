import Foundation
import XCTest
import FeedMineDomain
import FeedMineMedia
import FeedMinePublication

final class PublishedCardTests: XCTestCase {
    private func origin() -> PublishedOrigin {
        PublishedOrigin(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
            sourceID: nil, providerID: nil, sourceDisplayName: "Frozen News", providerDisplayName: "Frozen Author")
    }

    private func card(layout: PublishedCardLayout, media: PublishedMediaSet,
                      action: PublishedPrimaryAction? = nil) throws -> PublishedCard? {
        PublishedCard(id: PublicationCardID(), origin: origin(), contentEntityID: nil,
            contentClusterID: nil, text: PublishedText(title: nil, primaryText: nil), timestamp: nil,
            media: media, renderContract: try XCTUnwrap(RenderContract(layout: layout, mediaAspectRatio: nil)),
            primaryAction: action)
    }

    func testAllowedLayoutMediaCombinationsAndContradictoryTextOnly() throws {
        let ref = try XCTUnwrap(PublishedMediaRef(key: XCTUnwrap(PublishedMediaKey(rawValue: "local")),
            pixelWidth: 400, pixelHeight: 200, mimeType: "image/jpeg"))
        for layout in [PublishedCardLayout.hero, .thumbnail] {
            XCTAssertNotNil(try card(layout: layout, media: PublishedMediaSet(primary: ref)))
            let placeholder = try XCTUnwrap(card(layout: layout, media: .none))
            XCTAssertNil(placeholder.media.primary)
            XCTAssertEqual(placeholder.renderContract.layout, layout)
        }
        let textOnly = try XCTUnwrap(card(layout: .textOnly, media: .none))
        XCTAssertNil(textOnly.primaryAction)
        XCTAssertNil(textOnly.timestamp)
        XCTAssertNil(textOnly.text.title)
        XCTAssertNil(textOnly.text.primaryText)
        XCTAssertNil(try card(layout: .textOnly, media: PublishedMediaSet(primary: ref)))
    }

    func testFrozenPrimaryActionTargetsAndLocalDetail() throws {
        let external = try XCTUnwrap(URL(string: "https://example.test/article?id=1"))
        let playback = try XCTUnwrap(URL(string: "https://example.test/audio.mp3"))
        for action in [PublishedPrimaryAction.externalURL(external), .mediaPlayback(playback), .localContentDetail] {
            let published = try XCTUnwrap(card(layout: .textOnly, media: .none, action: action))
            XCTAssertEqual(published.primaryAction, action)
        }
    }

    func testSameOriginCanHaveDistinctPublishedOccurrences() throws {
        let frozenOrigin = origin()
        let contract = try XCTUnwrap(RenderContract(layout: .textOnly, mediaAspectRatio: nil))
        let text = PublishedText(title: nil, primaryText: "Same text")
        let first = try XCTUnwrap(PublishedCard(id: PublicationCardID(), origin: frozenOrigin,
            contentEntityID: nil, contentClusterID: nil, text: text, timestamp: nil,
            media: .none, renderContract: contract, primaryAction: nil))
        let second = try XCTUnwrap(PublishedCard(id: PublicationCardID(), origin: frozenOrigin,
            contentEntityID: nil, contentClusterID: nil, text: text, timestamp: nil,
            media: .none, renderContract: contract, primaryAction: nil))
        XCTAssertEqual(first.origin, second.origin)
        XCTAssertEqual(first.text, second.text)
        XCTAssertEqual(first.media, second.media)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first, second)
    }

    func testSnapshotSurvivesNewCanonicalRevisionAndPayloadLeavingScope() throws {
        let recordID = OriginRecordID()
        let v1 = OriginRevisionID()
        let entityID = ContentEntityID()
        let clusterID = ContentClusterID()
        let published: PublishedCard = try {
            let revision = OriginRevision(id: v1, originRecordID: recordID, externalVersionIdentity: nil,
                headline: "  Original title\n", summary: " Original excerpt ", bodyText: nil,
                authoredAt: nil, modifiedAt: nil, observedAt: Date(timeIntervalSince1970: 100),
                language: nil, primaryLink: nil, searchProjection: nil, providerID: ProviderID())
            return try XCTUnwrap(PublishedCard(id: PublicationCardID(),
                origin: PublishedOrigin(originRecordID: revision.originRecordID, originRevisionID: revision.id,
                    sourceID: SourceID(), providerID: revision.providerID,
                    sourceDisplayName: "Example News", providerDisplayName: "Original Author"),
                contentEntityID: entityID, contentClusterID: clusterID,
                text: PublishedText(title: revision.headline, primaryText: revision.summary),
                timestamp: PublishedTimestamp(value: revision.observedAt, kind: .observed), media: .none,
                renderContract: XCTUnwrap(RenderContract(layout: .hero, mediaAspectRatio: 1.5)),
                primaryAction: .localContentDetail))
        }()
        let revision2 = OriginRevision(id: OriginRevisionID(), originRecordID: recordID, externalVersionIdentity: nil,
            headline: "Updated title", summary: "Updated excerpt", bodyText: nil,
            authoredAt: nil, modifiedAt: Date(timeIntervalSince1970: 200), observedAt: Date(timeIntervalSince1970: 200),
            language: nil, primaryLink: nil, searchProjection: nil, providerID: nil)
        XCTAssertEqual(revision2.originRecordID, recordID)
        XCTAssertNotEqual(revision2.id, published.origin.originRevisionID)
        XCTAssertEqual(published.origin.originRevisionID, v1)
        XCTAssertEqual(published.origin.originRecordID, recordID)
        XCTAssertNotNil(published.origin.sourceID)
        XCTAssertNotNil(published.origin.providerID)
        XCTAssertEqual(published.origin.sourceDisplayName, "Example News")
        XCTAssertEqual(published.origin.providerDisplayName, "Original Author")
        XCTAssertEqual(published.contentEntityID, entityID)
        XCTAssertEqual(published.contentClusterID, clusterID)
        XCTAssertEqual(published.text.title, "  Original title\n")
        XCTAssertEqual(published.text.primaryText, " Original excerpt ")
        XCTAssertEqual(published.timestamp?.value, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(published.timestamp?.kind, .observed)
        XCTAssertEqual(published.renderContract.layout, .hero)
        XCTAssertEqual(published.renderContract.mediaAspectRatio, 1.5)
        XCTAssertNil(published.media.primary)
        XCTAssertEqual(published.primaryAction, .localContentDetail)
    }

    func testTimestampKindPreservesChosenMeaningAndSlotRatioCanDifferFromAsset() throws {
        let ref = try XCTUnwrap(PublishedMediaRef(key: XCTUnwrap(PublishedMediaKey(rawValue: "asset")),
            pixelWidth: 200, pixelHeight: 100, mimeType: nil))
        let contract = try XCTUnwrap(RenderContract(layout: .hero, mediaAspectRatio: 1.0))
        for kind in [PublishedTimestampKind.authored, .modified, .observed] {
            let timestamp = PublishedTimestamp(value: Date(timeIntervalSince1970: 50), kind: kind)
            let published = try XCTUnwrap(PublishedCard(id: PublicationCardID(), origin: origin(),
                contentEntityID: nil, contentClusterID: nil, text: PublishedText(title: nil, primaryText: "Text"),
                timestamp: timestamp, media: PublishedMediaSet(primary: ref), renderContract: contract, primaryAction: nil))
            XCTAssertEqual(published.timestamp?.kind, kind)
            XCTAssertEqual(published.timestamp?.value, Date(timeIntervalSince1970: 50))
            XCTAssertEqual(published.media.primary?.aspectRatio, 2.0)
            XCTAssertEqual(published.renderContract.mediaAspectRatio, 1.0)
        }
    }
}
