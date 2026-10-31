import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMinePublication
import FeedMineRuntime
import FeedMineUI

/// P0 / Issue #7: historical membership and render-ready UI membership are
/// different contracts. No post-admission image completion is allowed in a cell.
@MainActor
final class RenderReadyVisualHandoffContractTests: XCTestCase {
    func testMissingHeroRemainsInHistoryButNeverBecomesARenderedCell() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(
            id: EditorialRevisionID(), contextKey: .init(request: .main),
            catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: version, eligibilityPolicyVersion: version,
            scoringPolicyVersion: version, sequencingPolicyVersion: version,
            exposurePolicyVersion: version, selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(
            id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: 1, selectionSeed: 1, createdAt: Date())

        // Frozen image-bearing publication, but its SHA-256 file does not exist.
        let missing = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Missing hero", primaryText: "Historical identity",
            timestampValue: nil, timestampKind: nil,
            mediaKey: "sha256:" + String(repeating: "0", count: 64),
            mediaPixelWidth: 600, mediaPixelHeight: 400,
            mediaMimeType: "image/png", renderLayout: "hero",
            renderMediaAspectRatio: 1.5, primaryActionKind: nil,
            primaryActionReference: nil)
        let readyBefore = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Ready before", primaryText: "Ready even before the unavailable image",
            timestampValue: nil, timestampKind: nil,
            mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil,
            mediaMimeType: nil, renderLayout: "textOnly",
            renderMediaAspectRatio: nil, primaryActionKind: nil,
            primaryActionReference: nil)
        let ready = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Ready text", primaryText: "Already prepared",
            timestampValue: nil, timestampKind: nil,
            mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil,
            mediaMimeType: nil, renderLayout: "textOnly",
            renderMediaAspectRatio: nil, primaryActionKind: nil,
            primaryActionReference: nil)
        try PublicationStore(database: database).createInitialEdition(
            edition,
            firstSegment: .init(id: FeedSegmentID(), editionID: edition.id,
                ordinal: 0, segmentSeed: 1, publicationSchemaVersion: 1,
                createdAt: Date(), cardIDs: [readyBefore.id, missing.id, ready.id]),
            cards: [readyBefore, missing, ready],
            initialCheckpoint: .init(editionID: edition.id, cardID: ready.id,
                anchorPlacement: "top", updatedAt: Date()))

        let history = PublicationHistory(database: database)
        let retained = try history.window(
            editionID: edition.id,
            around: .init(cardID: missing.id, placement: .center),
            backwardCapacity: 1, forwardCapacity: 1)
        XCTAssertEqual(retained.cards.map(\.id), [readyBefore.id, missing.id, ready.id],
            "Not rendering a missing hero must not delete its publication identity")

        // No decoder: an image-bearing card is necessarily not render-ready.
        // The checkpoint itself is a legitimate ready text card.
        let session = FeedSession(publicationHistory: history)
        let result = try await session.admitPresentation(
            .restore(.init(backwardCapacity: 2, forwardCapacity: 0)))
        let snapshot = try XCTUnwrap(result)
        XCTAssertEqual(snapshot.window.anchor.cardID, ready.id)

        let screen = FeedScreenStore(onViewport: { _, _ in })
        try screen.install(FeedPresentationState(presentation: snapshot))
        XCTAssertEqual(screen.renderedItems.map(\.id), [readyBefore.id, ready.id],
            "Only prepared cells cross the visual handoff; history remains retrievable")
        XCTAssertFalse(screen.renderedItems.contains {
            $0.isImageBearing && $0.image == nil
        }, "An image-bearing placeholder must not be treated as a rendered card")
        XCTAssertEqual(screen.renderedItems.map(\.title), ["Ready before", "Ready text"],
            "Neither a ready predecessor nor a ready successor may be blocked by missing media")

        // A rejected historical observation must not erase the visible text
        // siblings, change the anchor or advance the projection.
        let attempted = ViewportObservation(anchor: .init(cardID: missing.id, placement: .center))
        let beforeRejected = await session.currentPresentation()
        _ = try await session.submitViewport(attempted)
        let afterRejected = await session.currentPresentation()
        XCTAssertEqual(afterRejected, beforeRejected,
            "A missing-image target must be rejectable without mutating the reader")
        if let afterRejected {
            try screen.install(FeedPresentationState(presentation: afterRejected))
        }
        XCTAssertEqual(screen.renderedItems.map(\.id), [readyBefore.id, ready.id],
            "A rejected image return cannot remove either ready sibling")
    }
}
