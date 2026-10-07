import Foundation
import XCTest
import FeedMineDomain
import FeedMineMedia
import FeedMinePersistence
@testable import FeedMinePublication

// Semantic fixtures, shared only within the test target.
enum RestoreFixture {
    static func edition(context: FeedContextRequest = .main) -> FeedEdition {
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: ContextKey(request: context),
            catalogGeneration: CatalogGeneration(rawValue: 1), userSelectionVersion: PolicyVersion(rawValue: 2),
            eligibilityPolicyVersion: PolicyVersion(rawValue: 3), scoringPolicyVersion: PolicyVersion(rawValue: 4),
            sequencingPolicyVersion: PolicyVersion(rawValue: 5), exposurePolicyVersion: PolicyVersion(rawValue: 6),
            selectionSchemaVersion: SelectionSchemaVersion(rawValue: 7))
        return FeedEdition(id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: PublicationSchemaVersion(rawValue: 1), selectionSeed: UInt64.max,
            createdAt: Date(timeIntervalSince1970: 123.125))
    }
    static func card(index: Int) throws -> PublishedCard {
        let layout: PublishedCardLayout = index == 0 ? .textOnly : (index == 2 ? .thumbnail : .hero)
        let media: PublishedMediaSet
        if index == 1 || index == 4 {
            media = PublishedMediaSet(primary: try XCTUnwrap(PublishedMediaRef(
                key: XCTUnwrap(PublishedMediaKey(rawValue: " ")), pixelWidth: 300, pixelHeight: 200, mimeType: "image/jpeg")))
        } else { media = .none }
        let action: PublishedPrimaryAction?
        switch index {
        case 1: action = .externalURL(try XCTUnwrap(URL(string: "https://example.test/article?id=1")))
        case 4: action = .mediaPlayback(try XCTUnwrap(URL(string: "https://example.test/audio.mp3")))
        case 2: action = .localContentDetail
        default: action = nil
        }
        return try XCTUnwrap(PublishedCard(id: PublicationCardID(),
            origin: PublishedOrigin(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                sourceID: SourceID(), providerID: ProviderID(), sourceDisplayName: " Frozen News ", providerDisplayName: "Author É"),
            contentEntityID: ContentEntityID(), contentClusterID: ContentClusterID(),
            text: PublishedText(title: index == 0 ? nil : " Title \(index) ", primaryText: index == 0 ? "" : " Original excerpt \(index)\n"),
            timestamp: index == 0 ? nil : PublishedTimestamp(value: Date(timeIntervalSince1970: 200.25), kind: index == 2 ? .modified : (index == 1 ? .authored : .observed)),
            media: media, renderContract: XCTUnwrap(RenderContract(layout: layout, mediaAspectRatio: layout == .textOnly ? nil : 1.0)),
            primaryAction: action))
    }
    static func segment(_ edition: FeedEdition, cards: [PublishedCard], ordinal: UInt64) throws -> FeedSegment {
        try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: edition.id, ordinal: ordinal,
            segmentSeed: UInt64.max, publicationSchemaVersion: edition.publicationSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 250.5), cardIDs: cards.map(\.id)))
    }
}

final class PublicationPersistenceMappingTests: XCTestCase {
    func testEditionSegmentCardAndCursorRoundTrips() throws {
        for request in [FeedContextRequest.main, .source(SourceID()), .search(try XCTUnwrap(SearchContext(query: " Exact Query ")))] {
            let edition = RestoreFixture.edition(context: request)
            XCTAssertEqual(try PublicationPersistenceMapping.edition(PublicationPersistenceMapping.record(edition)), edition)
        }
        let edition = RestoreFixture.edition()
        let cards = try (0..<6).map { try RestoreFixture.card(index: $0) }
        let segment = try RestoreFixture.segment(edition, cards: cards, ordinal: 0)
        XCTAssertEqual(try PublicationPersistenceMapping.segment(PublicationPersistenceMapping.record(segment)), segment)
        for card in cards {
            XCTAssertEqual(try PublicationPersistenceMapping.card(PublicationPersistenceMapping.record(card)), card)
        }
        for placement in [AnchorPlacement.top, .center] {
            let cursor = SessionCursor(editionID: edition.id, anchor: FeedWindowAnchor(cardID: cards[4].id, placement: placement))
            XCTAssertEqual(try PublicationPersistenceMapping.cursor(PublicationPersistenceMapping.checkpoint(cursor, updatedAt: Date(timeIntervalSince1970: 1))), cursor)
        }
        let envelope = try PublicationPersistenceMapping.records(segment: segment, cards: cards)
        XCTAssertEqual(envelope.0.cardIDs, cards.map(\.id))
        XCTAssertThrowsError(try PublicationPersistenceMapping.records(segment: segment, cards: Array(cards.reversed())))
    }

    func testInvalidPersistedSegmentAndCheckpointDoNotDefault() throws {
        let edition = RestoreFixture.edition()
        let segment = PublicationStore.SegmentRecord(id: FeedSegmentID(), editionID: edition.id, ordinal: 0,
            segmentSeed: 0, publicationSchemaVersion: 1, createdAt: edition.createdAt, cardIDs: [])
        XCTAssertThrowsError(try PublicationPersistenceMapping.segment(segment))
        XCTAssertThrowsError(try PublicationPersistenceMapping.cursor(.init(editionID: edition.id,
            cardID: PublicationCardID(), anchorPlacement: "bottom", updatedAt: edition.createdAt)))
    }
    func testMalformedMechanicalCardsAreRejectedWithoutDroppingFields() throws {
        let baseline = PublicationPersistenceMapping.record(try RestoreFixture.card(index: 1))
        let invalid: [PublicationStore.CardRecord] = [
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: baseline.timestampValue, timestampKind: "unknown", mediaKey: baseline.mediaKey, mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: baseline.mediaPixelHeight, mediaMimeType: baseline.mediaMimeType, renderLayout: baseline.renderLayout, renderMediaAspectRatio: baseline.renderMediaAspectRatio, primaryActionKind: baseline.primaryActionKind, primaryActionReference: baseline.primaryActionReference),
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: nil, timestampKind: baseline.timestampKind, mediaKey: baseline.mediaKey, mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: baseline.mediaPixelHeight, mediaMimeType: baseline.mediaMimeType, renderLayout: baseline.renderLayout, renderMediaAspectRatio: baseline.renderMediaAspectRatio, primaryActionKind: baseline.primaryActionKind, primaryActionReference: baseline.primaryActionReference),
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: baseline.timestampValue, timestampKind: baseline.timestampKind, mediaKey: "", mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: baseline.mediaPixelHeight, mediaMimeType: baseline.mediaMimeType, renderLayout: baseline.renderLayout, renderMediaAspectRatio: baseline.renderMediaAspectRatio, primaryActionKind: baseline.primaryActionKind, primaryActionReference: baseline.primaryActionReference),
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: baseline.timestampValue, timestampKind: baseline.timestampKind, mediaKey: baseline.mediaKey, mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: nil, mediaMimeType: baseline.mediaMimeType, renderLayout: baseline.renderLayout, renderMediaAspectRatio: baseline.renderMediaAspectRatio, primaryActionKind: baseline.primaryActionKind, primaryActionReference: baseline.primaryActionReference),
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: baseline.timestampValue, timestampKind: baseline.timestampKind, mediaKey: baseline.mediaKey, mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: baseline.mediaPixelHeight, mediaMimeType: baseline.mediaMimeType, renderLayout: "unknown", renderMediaAspectRatio: baseline.renderMediaAspectRatio, primaryActionKind: baseline.primaryActionKind, primaryActionReference: baseline.primaryActionReference),
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: baseline.timestampValue, timestampKind: baseline.timestampKind, mediaKey: baseline.mediaKey, mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: baseline.mediaPixelHeight, mediaMimeType: baseline.mediaMimeType, renderLayout: baseline.renderLayout, renderMediaAspectRatio: Double.infinity, primaryActionKind: baseline.primaryActionKind, primaryActionReference: baseline.primaryActionReference),
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: baseline.timestampValue, timestampKind: baseline.timestampKind, mediaKey: baseline.mediaKey, mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: baseline.mediaPixelHeight, mediaMimeType: baseline.mediaMimeType, renderLayout: baseline.renderLayout, renderMediaAspectRatio: baseline.renderMediaAspectRatio, primaryActionKind: "unknown", primaryActionReference: baseline.primaryActionReference),
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: baseline.timestampValue, timestampKind: baseline.timestampKind, mediaKey: baseline.mediaKey, mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: baseline.mediaPixelHeight, mediaMimeType: baseline.mediaMimeType, renderLayout: baseline.renderLayout, renderMediaAspectRatio: baseline.renderMediaAspectRatio, primaryActionKind: baseline.primaryActionKind, primaryActionReference: nil),
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: baseline.timestampValue, timestampKind: baseline.timestampKind, mediaKey: baseline.mediaKey, mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: baseline.mediaPixelHeight, mediaMimeType: baseline.mediaMimeType, renderLayout: baseline.renderLayout, renderMediaAspectRatio: baseline.renderMediaAspectRatio, primaryActionKind: baseline.primaryActionKind, primaryActionReference: "http://[invalid"),
            .init(id: baseline.id, originRecordID: baseline.originRecordID, originRevisionID: baseline.originRevisionID, sourceID: baseline.sourceID, providerID: baseline.providerID, sourceDisplayName: baseline.sourceDisplayName, providerDisplayName: baseline.providerDisplayName, contentEntityID: baseline.contentEntityID, contentClusterID: baseline.contentClusterID, title: baseline.title, primaryText: baseline.primaryText, timestampValue: baseline.timestampValue, timestampKind: baseline.timestampKind, mediaKey: baseline.mediaKey, mediaPixelWidth: baseline.mediaPixelWidth, mediaPixelHeight: baseline.mediaPixelHeight, mediaMimeType: baseline.mediaMimeType, renderLayout: "textOnly", renderMediaAspectRatio: baseline.renderMediaAspectRatio, primaryActionKind: baseline.primaryActionKind, primaryActionReference: baseline.primaryActionReference),
        ]
        for record in invalid {
            XCTAssertThrowsError(try PublicationPersistenceMapping.card(record)) { error in
                XCTAssertEqual(error as? PublicationPersistenceMappingError, .invalidPersistedCard)
            }
        }
    }

}
