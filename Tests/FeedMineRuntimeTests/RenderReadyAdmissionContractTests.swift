import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMinePublication
import FeedMineMedia
import FeedMineRuntime

/// Product contract: historical image IDs survive restore, but cannot be
/// installed as physical cells until their local pixels have decoded.
/// The logical window is not the drawn LazyVStack (B05/T7).
final class RenderReadyAdmissionContractTests: XCTestCase {
    func testMissingLocalHeroPixelsRemainLogicalButAreDeferredOnRestoreAndWarmStart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(
            id: EditorialRevisionID(),
            contextKey: .init(request: .main),
            catalogGeneration: .init(rawValue: 1),
            userSelectionVersion: version,
            eligibilityPolicyVersion: version,
            scoringPolicyVersion: version,
            sequencingPolicyVersion: version,
            exposurePolicyVersion: version,
            selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(
            id: FeedEditionID(), editorialRevision: revision, publicationSchemaVersion: 1,
            selectionSeed: 1, createdAt: Date())

        // A valid published image descriptor whose sha256 file does not exist.
        // This isolates the admission boundary: no network, sleep or race.
        let card = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Missing pixels", primaryText: "Local hero image absent",
            timestampValue: nil, timestampKind: nil,
            mediaKey: "sha256:" + String(repeating: "0", count: 64),
            mediaPixelWidth: 600, mediaPixelHeight: 400,
            mediaMimeType: "image/png", renderLayout: "hero",
            renderMediaAspectRatio: 1.5, primaryActionKind: nil,
            primaryActionReference: nil)
        // A fully ready text card must remain readable when the earlier image
        // cannot be decoded; rejecting the entire edition is not a valid fix.
        let ready = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Ready text", primaryText: "No media required",
            timestampValue: nil, timestampKind: nil,
            mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil,
            mediaMimeType: nil, renderLayout: "textOnly",
            renderMediaAspectRatio: nil, primaryActionKind: nil,
            primaryActionReference: nil)
        try PublicationStore(database: database).createInitialEdition(
            edition,
            firstSegment: .init(id: FeedSegmentID(), editionID: edition.id,
                ordinal: 0, segmentSeed: 1, publicationSchemaVersion: 1,
                createdAt: Date(), cardIDs: [ready.id, card.id]),
            cards: [ready, card],
            initialCheckpoint: .init(editionID: edition.id, cardID: ready.id,
                anchorPlacement: "top", updatedAt: Date()))

        let history = PublicationHistory(database: database)
        // The decoder factory is failable. Do not allow a nil decoder to
        // masquerade as a missing-media admission failure.
        let decoder = try XCTUnwrap(PresentationImageDecoder(
            assetDirectory: directory.appendingPathComponent("Media"),
            heroMaxPixel: 300, thumbnailMaxPixel: 88))
        let bounds = FeedPresentationBounds(backwardCapacity: 8, forwardCapacity: 16)

        let session = FeedSession(publicationHistory: history, imageDecoder: decoder)
        let restored = try await session.admitPresentation(.restore(bounds))
        let restoredSnapshot = try XCTUnwrap(restored)
        XCTAssertEqual(restoredSnapshot.window.items.map(\.id), [ready.id, card.id],
            "The durable historical ordinal must survive; filtering it would collapse a gap")
        let restoredRail = FeedVisualRailIndex(snapshot: restoredSnapshot)
        XCTAssertEqual(restoredRail.visualAnchorID, ready.id)
        XCTAssertEqual(restoredRail.slot(at: 1), .deferred(index: 1, id: card.id),
            "A hero with missing local pixels is historical, not a drawable cell")

        // The synchronous warm-launch path must make the same distinction,
        // rather than introducing an invisible physical placeholder.
        let warm = try FeedSession.warmStart(
            publicationHistory: history, imageDecoder: decoder, bounds: bounds)
        let warmSnapshot = try XCTUnwrap(warm?.snapshot)
        XCTAssertEqual(warmSnapshot.window.items.map(\.id), [ready.id, card.id])
        let warmRail = FeedVisualRailIndex(snapshot: warmSnapshot)
        XCTAssertEqual(warmRail.visualAnchorID, ready.id)
        XCTAssertEqual(warmRail.slot(at: 1), .deferred(index: 1, id: card.id))
        let plan = try XCTUnwrap(FeedVisualWindowPlan(snapshot: warmSnapshot,
            center: 0, backward: 0, forward: 1))
        XCTAssertEqual(plan.segments, [
            .ready(range: 0..<1, cards: [warmSnapshot.window.items[0]]),
            .deferred(range: 1..<2, ids: [card.id])
        ], "Never join ready runs across an undecodable historical hero")

        // An invalid forward target must not change the admitted reader position
        // or mark an image-less card as seen in durable publication history.
        // This is a distinct failure mode from including it in the initial list.
        let unreadable = ViewportObservation(
            anchor: .init(cardID: card.id, placement: .center))
        _ = try await session.submitViewport(unreadable)
        let afterRejected = await session.currentPresentation()
        XCTAssertEqual(afterRejected?.window.anchor.cardID, ready.id,
            "An unreadable image cannot become the active reader position")
        let exposure = try XCTUnwrap(PublicationStore(database: database)
            .hiddenTail(editionID: edition.id))
        XCTAssertEqual(exposure.highWaterCardID, ready.id,
            "A rejected viewport must not advance durable seen high-water")
    }
}
