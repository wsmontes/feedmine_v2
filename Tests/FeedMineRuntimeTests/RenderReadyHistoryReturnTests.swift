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
        let initialRail = FeedVisualRailIndex(snapshot: initial)
        XCTAssertEqual(initialRail.slot(at: 0)?.id, hero.id)
        XCTAssertTrue(initialRail.slot(at: 0)?.isReady == true,
            "A real local hero must enter the virtual rail as ready")

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
        let awayRail = FeedVisualRailIndex(snapshot: away)
        XCTAssertEqual(awayRail.slot(at: 0), .deferred(index: 0, id: hero.id),
            "Releasing pixels must keep the original historical slot without rendering it")
        XCTAssertEqual(awayRail.logicalCount, ids.count)
        XCTAssertEqual(awayRail.visualAnchorID, last.id)

        // B05: the current kept-head window retains the old hero identity
        // without pixels; it cannot claim to have rendered the hero.
        XCTAssertNil(away.evidence(for: heroObservation, ordinal: 19),
            "A released historical descriptor is not a viewport witness")
        // The genuinely rendered earlier window may still be borrowed during
        // an active gesture. That older proof remains valid for reconciliation.
        let heldHeroProof = try XCTUnwrap(initial.evidence(
            for: heroObservation, ordinal: 19))
        let returnedResult = try await session.submitViewport(heroObservation, from: heldHeroProof)
        let returned = try XCTUnwrap(returnedResult)
        XCTAssertEqual(returned.window.anchor.cardID, hero.id)
        XCTAssertEqual(returned.window.items.map(\.id), ids)
        XCTAssertNotNil(returned.window.items.first?.image,
            "Returning to a released historical hero requires decoded pixels")
        let returnedRail = FeedVisualRailIndex(snapshot: returned)
        XCTAssertTrue(returnedRail.slot(at: 0)?.isReady == true,
            "The identical historical hero slot becomes ready after local rematerialization")
        XCTAssertEqual(returnedRail.slot(at: 0)?.id, hero.id)
        XCTAssertEqual(returnedRail.logicalAnchorIndex, 0)
        XCTAssertEqual(returned.window.items.last?.id, last.id,
            "The already-ready text sibling must remain reachable")

        // Real SHA-256 re-entry creates a continuous drawable run again,
        // without replacing its frozen hero ID or erasing the reader's text.
        let beforeReentry = try XCTUnwrap(FeedVisualWindowPlan(snapshot: away,
            center: 2, backward: 1, forward: 0))
        let afterReentry = try XCTUnwrap(FeedVisualWindowPlan(snapshot: returned,
            center: 1, backward: 1, forward: 1))
        XCTAssertEqual(beforeReentry.contiguousReadyCards?.map(\.id),
            [middle.id, last.id])
        XCTAssertEqual(afterReentry.contiguousReadyCards?.map(\.id), ids)
        XCTAssertEqual(beforeReentry.visualAnchorID, last.id)
        XCTAssertEqual(afterReentry.visualAnchorID, hero.id)
        XCTAssertEqual(beforeReentry.logicalCount, afterReentry.logicalCount)
        // Synthetic geometry tests handoff eligibility; actual pixel-offset
        // correction remains the responsibility of Apple native UI tests.
        let readerBefore = FeedVisualWindowWitness(cardID: last.id,
            viewportTop: 180, contentOffset: 500,
            cardHeight: 160, viewportHeight: 650)
        let readerAfter = FeedVisualWindowWitness(cardID: last.id,
            viewportTop: 420, contentOffset: 500,
            cardHeight: 160, viewportHeight: 650)
        XCTAssertNil(FeedVisualWindowHandoff(from: beforeReentry,
            to: afterReentry, before: readerBefore, after: readerAfter,
            gestureActive: true), "Do not replace the physical rail during a gesture")
        let idle = try XCTUnwrap(FeedVisualWindowHandoff(from: beforeReentry,
            to: afterReentry, before: readerBefore, after: readerAfter,
            gestureActive: false))
        XCTAssertEqual(idle.witnessID, last.id,
            "The reader's already-visible sibling is the transfer witness")
        XCTAssertEqual(idle.offsetAdjustment, 240, accuracy: 0.001)
        XCTAssertEqual(idle.provenance, returned.provenance)

        let secondAwayResult = try await session.submitViewport(lastObservation)
        let secondAway = try XCTUnwrap(secondAwayResult)
        XCTAssertNil(secondAway.evidence(for: heroObservation, ordinal: 73),
            "Released pixels cannot mint a new viewport proof")
        // The last actually rendered hero snapshot may still be held by UI.
        // It can authorize re-entry only after its local pixels rematerialize.
        let retryEvidence = try XCTUnwrap(returned.evidence(
            for: heroObservation, ordinal: 73))
        let beforeMissing = await session.currentPresentation()
        try FileManager.default.removeItem(at: png.file)

        // Failure control: when local bytes disappear, a return must not make
        // the undecodable hero the reader's active anchor or consume its retry.
        let missingReturn = try await session.submitViewport(heroObservation, from: retryEvidence)
        let afterMissing = await session.currentPresentation()
        XCTAssertEqual(afterMissing, beforeMissing,
            "Failed media return must not consume projection position, anchor or residency")
        XCTAssertNotEqual(missingReturn?.window.anchor.cardID, hero.id,
            "An undecodable historical hero cannot be readmitted as the active card")
        XCTAssertEqual(afterMissing?.window.anchor.cardID, last.id,
            "A rejected return must preserve the ready text reader position")
        XCTAssertTrue(afterMissing?.window.items.contains(where: { $0.id == last.id }) == true)

        // Make the same frozen published asset local again; no new publication,
        // identity or editorial layout is created to repair the previous failure.
        try png.bytes.write(to: png.file)
        // Replay the SAME evidence ordinal. A rejected return cannot consume it.
        let retriedResult = try await session.submitViewport(heroObservation, from: retryEvidence)
        let retried = try XCTUnwrap(retriedResult)
        XCTAssertEqual(retried.window.anchor.cardID, hero.id)
        XCTAssertEqual(retried.window.items.map(\.id), ids)
        XCTAssertNotNil(retried.window.items.first?.image,
            "The returning image must remain retryable after a failed local decode")
    }
}
