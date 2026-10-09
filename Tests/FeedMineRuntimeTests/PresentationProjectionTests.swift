import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
@testable import FeedMinePublication
@testable import FeedMineRuntime

// Test-only semantic fixtures; no catalog, media bytes or network access.
enum WarmPresentationFixture {
    static func edition() -> FeedEdition {
        let revision = EditorialRevision(id: EditorialRevisionID(),
            contextKey: ContextKey(request: .source(SourceID())),
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 2),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 3), scoringPolicyVersion: PolicyVersion(rawValue: 4),
            sequencingPolicyVersion: PolicyVersion(rawValue: 5), exposurePolicyVersion: PolicyVersion(rawValue: 6),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 7))
        return FeedEdition(id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1), selectionSeed: UInt64.max,
            createdAt: Date(timeIntervalSince1970: 123.125))
    }

    static func card(
        layout: PublishedCardLayout = .hero,
        timestampKind: PublishedTimestampKind? = .observed,
        action: PublishedPrimaryAction? = .externalURL(URL(string: "https://example.com/private-target-for-test")!),
        title: String? = "  Frozen title É\n",
        primaryText: String? = " Original text\n "
    ) throws -> PublishedCard {
        let media: PublishedMediaSet
        if layout == .textOnly { media = .none }
        else {
            let key = try XCTUnwrap(PublishedMediaKey(rawValue: "local-only-key"))
            media = PublishedMediaSet(primary: try XCTUnwrap(PublishedMediaRef(
                key: key, pixelWidth: 600, pixelHeight: 400, mimeType: "image/jpeg")))
        }
        return try XCTUnwrap(PublishedCard(id: PublicationCardID(),
            origin: PublishedOrigin(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                sourceID: SourceID(), providerID: ProviderID(), sourceDisplayName: " Frozen source ", providerDisplayName: "Provider É"),
            contentEntityID: ContentEntityID(), contentClusterID: ContentClusterID(),
            text: PublishedText(title: title, primaryText: primaryText),
            timestamp: timestampKind.map { PublishedTimestamp(value: Date(timeIntervalSince1970: 200.25), kind: $0) },
            media: media,
            renderContract: XCTUnwrap(RenderContract(layout: layout, mediaAspectRatio: layout == .textOnly ? nil : 1.5)),
            primaryAction: action))
    }
}

final class PresentationProjectionTests: XCTestCase {
    func testCompleteCardPreservesUIFacingPayload() throws {
        let card = try WarmPresentationFixture.card()
        let projected = PresentationCard(publishedCard: card)
        XCTAssertEqual(projected.id, card.id)
        XCTAssertEqual(projected.title, "  Frozen title É\n")
        XCTAssertEqual(projected.primaryText, " Original text\n ")
        XCTAssertEqual(projected.sourceDisplayName, " Frozen source ")
        XCTAssertEqual(projected.providerDisplayName, "Provider É")
        XCTAssertEqual(projected.timestamp?.value, Date(timeIntervalSince1970: 200.25))
        XCTAssertEqual(projected.timestamp?.kind, .observed)
        XCTAssertEqual(projected.layout, .hero)
        XCTAssertEqual(projected.mediaAspectRatio, 1.5)
        XCTAssertEqual(projected.primaryActionKind, .externalURL)
    }

    func testEveryTimestampKindAndMissingTimestampArePreserved() throws {
        let cases: [(PublishedTimestampKind, PresentationTimestampKind)] = [
            (.authored, .authored), (.modified, .modified), (.observed, .observed)
        ]
        for (published, expected) in cases {
            let projected = PresentationCard(publishedCard: try WarmPresentationFixture.card(timestampKind: published))
            XCTAssertEqual(projected.timestamp?.kind, expected)
            XCTAssertEqual(projected.timestamp?.value, Date(timeIntervalSince1970: 200.25))
        }
        XCTAssertNil(PresentationCard(publishedCard: try WarmPresentationFixture.card(timestampKind: nil)).timestamp)
    }

    func testEveryLayoutAndActionAffordanceArePreserved() throws {
        let layouts: [(PublishedCardLayout, PresentationCardLayout)] = [
            (.hero, .hero), (.thumbnail, .thumbnail), (.textOnly, .textOnly)
        ]
        for (published, expected) in layouts {
            let projected = PresentationCard(publishedCard: try WarmPresentationFixture.card(layout: published))
            XCTAssertEqual(projected.layout, expected)
            XCTAssertEqual(projected.mediaAspectRatio, published == .textOnly ? nil : 1.5)
        }
        let target = try XCTUnwrap(URL(string: "https://example.com/private-playback-target"))
        let actions: [(PublishedPrimaryAction?, PresentationPrimaryActionKind?)] = [
            (nil, nil), (.externalURL(target), .externalURL),
            (.mediaPlayback(target), .mediaPlayback), (.localContentDetail, .localContentDetail)
        ]
        for (published, expected) in actions {
            XCTAssertEqual(PresentationCard(publishedCard: try WarmPresentationFixture.card(action: published)).primaryActionKind, expected)
        }
    }

    func testMissingAndEmptyTextRemainDistinctAndAttributionCanBeMissing() throws {
        let original = try WarmPresentationFixture.card(title: nil, primaryText: "")
        let card = try XCTUnwrap(PublishedCard(id: original.id,
            origin: PublishedOrigin(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil),
            contentEntityID: nil, contentClusterID: nil, text: original.text, timestamp: original.timestamp,
            media: original.media, renderContract: original.renderContract, primaryAction: original.primaryAction))
        let projected = PresentationCard(publishedCard: card)
        XCTAssertNil(projected.title)
        XCTAssertEqual(projected.primaryText, "")
        XCTAssertNil(projected.sourceDisplayName)
        XCTAssertNil(projected.providerDisplayName)
    }

    func testSnapshotProjectionPreservesContextOrderAndBothPlacements() async throws {
        let edition = WarmPresentationFixture.edition()
        let cards = try (0..<3).map { _ in try WarmPresentationFixture.card() }
        for placement in [AnchorPlacement.top, .center] {
            let anchor = FeedWindowAnchor(cardID: cards[1].id, placement: placement)
            let window = try XCTUnwrap(FeedWindow(editionID: edition.id, cards: cards, anchor: anchor))
            let restored = try XCTUnwrap(RestoredPublication(edition: edition,
                cursor: SessionCursor(editionID: edition.id, anchor: anchor), window: window))
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let db = try RuntimeDatabase(location: .init(directory: directory))
            let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: edition.id, ordinal: 0,
                segmentSeed: 1, publicationSchemaVersion: edition.publicationSchemaVersion,
                createdAt: edition.createdAt, cardIDs: cards.map(\.id)))
            let records = try PublicationPersistenceMapping.records(segment: segment, cards: cards)
            try PublicationStore(database: db).createEdition(PublicationPersistenceMapping.record(edition), firstSegment: records.0, cards: records.1)
            let history = PublicationHistory(database: db)
            try history.saveCursor(restored.cursor, updatedAt: edition.createdAt)
            let session = FeedSession(publicationHistory: history)
            let projected = try await session.restoreLocalPresentation(backwardCapacity: 1, forwardCapacity: 1)
            let snapshot = try XCTUnwrap(projected)
            XCTAssertEqual(snapshot.contextKey, edition.contextKey)
            XCTAssertEqual(snapshot.editionID, edition.id)
            XCTAssertEqual(snapshot.window.items.map(\.id), cards.map(\.id))
            XCTAssertEqual(snapshot.window.anchor.cardID, cards[1].id)
            XCTAssertEqual(snapshot.window.anchor.placement, placement == .top ? .top : .center)
        }
    }

    func testWindowSnapshotRejectsEmptyDuplicateAndAbsentAnchorAndKeepsOrder() throws {
        let cards = try (0..<3).map { _ in PresentationCard(publishedCard: try WarmPresentationFixture.card()) }
        let anchor = PresentationAnchor(cardID: cards[1].id, placement: .center)
        let order = [cards[2], cards[1], cards[0]]
        let window = try XCTUnwrap(FeedWindowSnapshot(items: order, anchor: anchor))
        XCTAssertEqual(window.items, order)
        XCTAssertEqual(window.anchor, anchor)
        XCTAssertNil(FeedWindowSnapshot(items: [], anchor: anchor))
        XCTAssertNil(FeedWindowSnapshot(items: [cards[0], cards[1], cards[0]], anchor: anchor))
        XCTAssertNil(FeedWindowSnapshot(items: [cards[1], cards[1]], anchor: anchor))
        XCTAssertNil(FeedWindowSnapshot(items: [cards[0]], anchor: anchor))
    }
}
