import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMinePublication
import FeedMineRuntime
@testable import FeedMineUI

/// P0 / Issue #7: historical membership and render-ready UI membership are
/// different contracts. No post-admission image completion is allowed in a cell.
@MainActor
final class RenderReadyVisualHandoffContractTests: XCTestCase {
    /// Pixel-backed positive control: an existing valid SHA-256 asset must
    /// remain an actual image (not a placeholder or text-only downgrade).
    private func localPNG(in directory: URL) throws -> String {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 32, height: 24, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = data as Data
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let folder = directory.appendingPathComponent("Media/sha256")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try bytes.write(to: folder.appendingPathComponent(digest))
        return digest
    }

    func testReadyHeroIsActuallyDecodedInNormalAndHeldVisualSurfaces() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let digest = try localPNG(in: directory)
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
        let readyHero = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Decoded hero", primaryText: "Complete local media",
            timestampValue: nil, timestampKind: nil,
            mediaKey: "sha256:" + digest,
            mediaPixelWidth: 32, mediaPixelHeight: 24,
            mediaMimeType: "image/png", renderLayout: "hero",
            renderMediaAspectRatio: 4.0 / 3.0, primaryActionKind: nil,
            primaryActionReference: nil)
        let textSibling = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Ready sibling", primaryText: "Prepared text",
            timestampValue: nil, timestampKind: nil,
            mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil,
            mediaMimeType: nil, renderLayout: "textOnly",
            renderMediaAspectRatio: nil, primaryActionKind: nil,
            primaryActionReference: nil)
        try PublicationStore(database: database).createInitialEdition(
            edition,
            firstSegment: .init(id: FeedSegmentID(), editionID: edition.id,
                ordinal: 0, segmentSeed: 1, publicationSchemaVersion: 1,
                createdAt: Date(), cardIDs: [readyHero.id, textSibling.id]),
            cards: [readyHero, textSibling],
            initialCheckpoint: .init(editionID: edition.id, cardID: readyHero.id,
                anchorPlacement: "center", updatedAt: Date()))
        let decoder = try XCTUnwrap(PresentationImageDecoder(
            assetDirectory: directory.appendingPathComponent("Media"),
            heroMaxPixel: 64, thumbnailMaxPixel: 32))
        let session = FeedSession(
            publicationHistory: .init(database: database), imageDecoder: decoder)
        let result = try await session.admitPresentation(
            .restore(.init(backwardCapacity: 0, forwardCapacity: 1)))
        let snapshot = try XCTUnwrap(result)
        XCTAssertEqual(snapshot.window.items.map(\.id), [readyHero.id, textSibling.id],
            "Ready hero must retain its original slot and neighbouring text")
        XCTAssertEqual(snapshot.window.anchor.cardID, readyHero.id)
        let decoded = try XCTUnwrap(snapshot.window.items.first?.image,
            "The test's valid local asset must decode before admission")
        XCTAssertEqual(decoded.key, "sha256:" + digest)
        XCTAssertEqual(decoded.cgImage.width, 32)
        XCTAssertEqual(decoded.cgImage.height, 24)

        let screen = FeedScreenStore(onViewport: { _, _ in })
        try screen.install(FeedPresentationState(presentation: snapshot))
        XCTAssertEqual(screen.renderedItems.map(\.id), [readyHero.id, textSibling.id],
            "Visual readiness must not be implemented by dropping all images")
        XCTAssertEqual(screen.renderedItems.first?.layout, .hero)
        XCTAssertEqual(screen.renderedItems.first?.image, decoded)

        var interaction = FeedInteractionPresentation()
        interaction.begin(snapshot, owner: ObjectIdentifier(screen))
        let held = try XCTUnwrap(interaction.heldItems(matching: screen))
        XCTAssertEqual(held.map(\.id), [readyHero.id, textSibling.id],
            "Gesture-held surface must retain the same ready hero identity")
        XCTAssertEqual(held.first?.image, decoded,
            "Gesture hold must preserve the decoded image, not a placeholder")
        interaction.end()
    }

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

        // The held interaction is a second drawing route: it must not bypass
        // the same visual readiness gate while a finger owns the old snapshot.
        var interaction = FeedInteractionPresentation()
        interaction.begin(snapshot, owner: ObjectIdentifier(screen))
        XCTAssertEqual(interaction.heldItems(matching: screen)?.map(\.id),
            [readyBefore.id, ready.id],
            "A held viewport must not resurrect undecodable images after store admission")
        interaction.end()

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
