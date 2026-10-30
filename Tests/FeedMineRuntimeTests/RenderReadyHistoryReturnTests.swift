import Foundation
import XCTest
import CoreGraphics
import ImageIO
import CryptoKit
import FeedMineDomain
import FeedMinePersistence
import FeedMinePublication
import FeedMineMedia
import FeedMineRuntime

/// Independent from B05: a released historical image must be decoded before
/// its identity can become the reader's anchored presentation again.
final class RenderReadyHistoryReturnTests: XCTestCase {
    private func localPNG(in directory: URL) throws -> (digest: String, file: URL, bytes: Data) {
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
        let file = folder.appendingPathComponent(digest)
        try bytes.write(to: file)
        return (digest, file, bytes)
    }

    func testReturningToReleasedHeroRequiresPixelsAndPreservesReaderIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = try localPNG(in: directory)
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let version = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(
            id: EditorialRevisionID(), contextKey: .init(request: .main),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: version,
            eligibilityPolicyVersion: version, scoringPolicyVersion: version,
            sequencingPolicyVersion: version, exposurePolicyVersion: version,
            selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(
            id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: 1, selectionSeed: 1, createdAt: Date())
        let hero = PublicationStore.CardRecord(
            id: PublicationCardID(), originRecordID: OriginRecordID(),
            originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
            sourceDisplayName: nil, providerDisplayName: nil,
            contentEntityID: nil, contentClusterID: nil,
            title: "Historical hero", primaryText: "Locally decoded",
            timestampValue: nil, timestampKind: nil,
            mediaKey: "sha256:" + png.digest,
            mediaPixelWidth: 32, mediaPixelHeight: 24,
            mediaMimeType: "image/png", renderLayout: "hero",
            renderMediaAspectRatio: 4.0 / 3.0, primaryActionKind: nil,
            primaryActionReference: nil)
        func textCard(_ title: String) -> PublicationStore.CardRecord {
            PublicationStore.CardRecord(
                id: PublicationCardID(), originRecordID: OriginRecordID(),
                originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil,
                sourceDisplayName: nil, providerDisplayName: nil,
                contentEntityID: nil, contentClusterID: nil,
                title: title, primaryText: "Already ready",
                timestampValue: nil, timestampKind: nil,
                mediaKey: nil, mediaPixelWidth: nil, mediaPixelHeight: nil,
                mediaMimeType: nil, renderLayout: "textOnly",
                renderMediaAspectRatio: nil, primaryActionKind: nil,
                primaryActionReference: nil)
        }
        let middle = textCard("Middle ready text")
        let last = textCard("Last ready text")
        let records = [hero, middle, last]
        try PublicationStore(database: database).createInitialEdition(
            edition,
            firstSegment: .init(id: FeedSegmentID(), editionID: edition.id,
                ordinal: 0, segmentSeed: 1, publicationSchemaVersion: 1,
                createdAt: Date(), cardIDs: records.map(\.id)),
            cards: records,
            initialCheckpoint: .init(editionID: edition.id, cardID: hero.id,
                anchorPlacement: "center", updatedAt: Date()))

        let decoder = try XCTUnwrap(PresentationImageDecoder(
            assetDirectory: directory.appendingPathComponent("Media"),
            heroMaxPixel: 64, thumbnailMaxPixel: 32))
        let session = FeedSession(
            publicationHistory: .init(database: database), imageDecoder: decoder)
        let bounds = FeedPresentationBounds(
            backwardCapacity: 0, forwardCapacity: 2, keepsAdmittedHead: true)
        let initialResult = try await session.admitPresentation(.restore(bounds))
        let initial = try XCTUnwrap(initialResult)
        let ids = records.map(\.id)
        XCTAssertEqual(initial.window.items.map(\.id), ids)
        XCTAssertEqual(initial.window.anchor.cardID, hero.id)
        XCTAssertNotNil(initial.window.items.first?.image, "Control: local hero must decode on first admission")

        let lastObservation = ViewportObservation(
            anchor: .init(cardID: last.id, placement: .center))
        let heroObservation = ViewportObservation(
            anchor: .init(cardID: hero.id, placement: .center))

        let awayResult = try await session.submitViewport(lastObservation)
        let away = try XCTUnwrap(awayResult)
        XCTAssertEqual(away.window.anchor.cardID, last.id)
        XCTAssertEqual(away.window.items.map(\.id), ids,
            "Keeping the head must preserve historical identity and ordering")
        XCTAssertNil(away.window.items.first?.image,
            "The historical bitmap must be released outside the residency band")

        // Positive control: an existing local asset can rematerialize the hero
        // before it becomes the current anchored card again.
        let returnedResult = try await session.submitViewport(heroObservation)
        let returned = try XCTUnwrap(returnedResult)
        XCTAssertEqual(returned.window.anchor.cardID, hero.id)
        XCTAssertEqual(returned.window.items.map(\.id), ids)
        XCTAssertNotNil(returned.window.items.first?.image,
            "Returning to a released historical hero requires decoded pixels")
        XCTAssertEqual(returned.window.items.last?.id, last.id,
            "The already-ready text sibling must remain reachable")

        let secondAwayResult = try await session.submitViewport(lastObservation)
        _ = try XCTUnwrap(secondAwayResult)
        try FileManager.default.removeItem(at: png.file)

        // Failure control: when local bytes disappear, a return must not make
        // the undecodable hero the reader's active anchor or consume its retry.
        let missingReturn = try await session.submitViewport(heroObservation)
        let afterMissing = await session.currentPresentation()
        XCTAssertNotEqual(missingReturn?.window.anchor.cardID, hero.id,
            "An undecodable historical hero cannot be readmitted as the active card")
        XCTAssertEqual(afterMissing?.window.anchor.cardID, last.id,
            "A rejected return must preserve the ready text reader position")
        XCTAssertTrue(afterMissing?.window.items.contains(where: { $0.id == last.id }) == true)

        // Make the same frozen published asset local again; no new publication,
        // identity or editorial layout is created to repair the previous failure.
        try png.bytes.write(to: png.file)
        let retriedResult = try await session.submitViewport(heroObservation)
        let retried = try XCTUnwrap(retriedResult)
        XCTAssertEqual(retried.window.anchor.cardID, hero.id)
        XCTAssertEqual(retried.window.items.map(\.id), ids)
        XCTAssertNotNil(retried.window.items.first?.image,
            "The returning image must remain retryable after a failed local decode")
    }
}
