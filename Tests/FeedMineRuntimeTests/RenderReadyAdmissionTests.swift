import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMinePublication
import FeedMineMedia
import FeedMineRuntime

/// INV: a card enters the feed's presentation only after its preparation is complete
/// (`docs/product/2026-10-17-render-ready-admission-rule.md`). For an image card that means the pixels are
/// decoded before admission; a presentation that cannot decode its media is a **declared** text card, never an
/// image slot waiting for bytes. Released pixels are reconstructed before the card is drawn again.
///
/// Seam: the injected `PresentationImageDecoder` (its real ImageIO path over a test asset directory, plus its
/// `onDecode` hook). The failing decode is a genuinely absent local asset; the delay is the hook holding the
/// actor inside the real decode. No production-only test hook was added for these tests.
final class RenderReadyAdmissionTests: XCTestCase {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// Holds every decode until the test opens the gate, so "still decoding" is an observable state rather
    /// than a guessed duration. A real wait, not a fixture: the closure runs inside `PresentationImageDecoder`.
    final class DecodeGate: @unchecked Sendable {
        private let condition = NSCondition()
        private var isOpen = false
        private var started = 0
        func enter() {
            condition.lock()
            started += 1
            condition.broadcast()
            while !isOpen { condition.wait() }
            condition.unlock()
        }
        func open() {
            condition.lock()
            isOpen = true
            condition.broadcast()
            condition.unlock()
        }
        var startedCount: Int { condition.lock(); defer { condition.unlock() }; return started }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var set = false
        func mark() { lock.lock(); set = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return set }
    }

    private struct Fixture {
        let directory: URL
        let database: RuntimeDatabase
        let edition: PublicationStore.EditionRecord
        let cards: [PublicationStore.CardRecord]
        let assets: URL
        var ids: [PublicationCardID] { cards.map(\.id) }
    }

    /// One real PNG per card, so a chosen card's media can be removed or held without touching the others.
    private func pngBytes(shade: UInt8) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 60, height: 40, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: CGFloat(shade) / 255, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    /// `cards` real published rows, every one an image card, anchored at `anchor` (center).
    private func fixture(cards count: Int = 3, anchor: Int, materialized: Set<Int>) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let assets = directory.appendingPathComponent("Media/sha256", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: .init(request: .main),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v,
            scoringPolicyVersion: v, sequencingPolicyVersion: v, exposurePolicyVersion: v,
            selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(), editorialRevision: revision,
            publicationSchemaVersion: 1, selectionSeed: 1, createdAt: Date())
        let rows = try (0..<count).map { index -> PublicationStore.CardRecord in
            let bytes = try pngBytes(shade: UInt8(20 + index * 30))
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            if materialized.contains(index) {
                try bytes.write(to: assets.appendingPathComponent(digest))
            }
            return PublicationStore.CardRecord(id: PublicationCardID(), originRecordID: OriginRecordID(),
                originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil, sourceDisplayName: nil,
                providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil, title: "C\(index)",
                primaryText: "Local image", timestampValue: nil, timestampKind: nil,
                mediaKey: "sha256:" + digest, mediaPixelWidth: 60, mediaPixelHeight: 40,
                mediaMimeType: "image/png", renderLayout: "hero", renderMediaAspectRatio: 1.5,
                primaryActionKind: nil, primaryActionReference: nil)
        }
        let database = try RuntimeDatabase(location: .init(directory: directory))
        try PublicationStore(database: database).createInitialEdition(edition,
            firstSegment: .init(id: FeedSegmentID(), editionID: edition.id, ordinal: 0, segmentSeed: 1,
                publicationSchemaVersion: 1, createdAt: Date(), cardIDs: rows.map(\.id)),
            cards: rows,
            initialCheckpoint: .init(editionID: edition.id, cardID: rows[anchor].id,
                anchorPlacement: "center", updatedAt: Date()))
        return Fixture(directory: directory, database: database, edition: edition, cards: rows,
            assets: directory.appendingPathComponent("Media"))
    }

    private func session(_ f: Fixture, onDecode: @escaping @Sendable () -> Void = {}) throws -> FeedSession {
        let decoder = try XCTUnwrap(PresentationImageDecoder(assetDirectory: f.assets,
            heroMaxPixel: 60, thumbnailMaxPixel: 30, onDecode: onDecode))
        return FeedSession(publicationHistory: .init(database: f.database), imageDecoder: decoder)
    }

    private func snapshot(_ session: FeedSession, _ admission: FeedPresentationAdmission) async throws
        -> FeedPresentationSnapshot {
        let value = try await session.admitPresentation(admission)
        return try XCTUnwrap(value)
    }

    /// **The discriminating test.** An image card whose media cannot be decoded does not cross the admission
    /// boundary as an image slot waiting for pixels (before this rule it entered as `.hero` with `image == nil`,
    /// which `FeedItemCardView.heroSlot` draws as the placeholder). It is admitted as a declared `.textOnly`
    /// presentation instead, and the ready cards around it keep their pixels and are not blocked.
    func testAnImageCardWhoseMediaCannotBeDecodedIsAdmittedAsDeclaredTextOnly() async throws {
        let f = try fixture(cards: 3, anchor: 1, materialized: [0, 2])
        let decodes = Counter()
        let session = try session(f) { decodes.increment() }
        let admitted = try await snapshot(session, .restore(.init(backwardCapacity: 1, forwardCapacity: 1)))

        XCTAssertEqual(admitted.window.items.map(\.id), f.ids, "the failing candidate does not block the ready ones")
        XCTAssertEqual(decodes.value, 3, "the media of every admitted card went through the decoder")
        let failed = admitted.window.items[1]
        XCTAssertEqual(failed.layout, .textOnly,
            "a card without pixels is presented as a declared text card")
        XCTAssertFalse(failed.isImageBearing, "the image slot is not admitted as something it cannot present")
        XCTAssertNil(failed.image)
        XCTAssertNil(failed.mediaAspectRatio, "a text presentation reserves no media slot")
        XCTAssertEqual(failed.id, f.cards[1].id, "identity is frozen publication, not residency")
        for index in [0, 2] {
            XCTAssertEqual(admitted.window.items[index].layout, .hero)
            XCTAssertNotNil(admitted.window.items[index].image, "a ready card is admitted with its pixels")
        }
        XCTAssertFalse(admitted.window.items.contains { $0.isImageBearing && $0.image == nil },
            "no admitted image card waits for the image it was published with")
    }

    /// While the decode is still in force there is no presentation at all: the card cannot be drawn before the
    /// work that prepares it finishes. The gate is opened only after the test has observed that fact.
    func testNoPresentationIsPublishedWhileAnImageIsStillBeingDecoded() async throws {
        let f = try fixture(cards: 1, anchor: 0, materialized: [0])
        let gate = DecodeGate(), decodes = Counter()
        let session = try session(f) { decodes.increment(); gate.enter() }
        let admission = Task { try await session.admitPresentation(.restore(.init(backwardCapacity: 0,
            forwardCapacity: 0))) }
        for _ in 0..<2_000 where gate.startedCount == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(gate.startedCount, 1, "admission reached the decoder before publishing anything")

        let probeFinished = Flag()
        let probe = Task { _ = await session.currentPresentation(); probeFinished.mark() }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(probeFinished.isSet,
            "while the decode is in force the card is not in presentation.window")

        gate.open()
        _ = await probe.value
        XCTAssertTrue(probeFinished.isSet, "the presentation exists once the decode has settled")
        let settled = try await admission.value
        let admitted = try XCTUnwrap(settled)
        XCTAssertEqual(admitted.window.items.map(\.id), f.ids, "the card enters only after the settlement")
        XCTAssertNotNil(admitted.window.items[0].image, "and it enters with its pixels ready to draw")
        XCTAssertEqual(admitted.window.items[0].layout, .hero)
    }

    /// **Re-admission.** A card that left the pixel band released its bitmap; when the reader comes back, its
    /// reconstruction is settled before the value is published. If the bytes cannot be decoded now, the card is
    /// drawn as a declared text card — never as an image slot re-entering with a placeholder.
    func testACardReturningToThePixelBandIsReconstructedBeforeItIsDrawn() async throws {
        let f = try fixture(cards: 5, anchor: 2, materialized: [0, 1, 2, 3, 4])
        let decodes = Counter()
        let session = try session(f) { decodes.increment() }
        let bounds = FeedPresentationBounds(backwardCapacity: 2, forwardCapacity: 2)
        let initial = try await snapshot(session, .restore(bounds))
        XCTAssertEqual(initial.window.items.map(\.id), f.ids)
        XCTAssertTrue(initial.window.items.allSatisfy { $0.image != nil })
        let keys = try f.cards.map { try XCTUnwrap(PublishedMediaKey(rawValue: $0.mediaKey!)) }

        // The bytes of card 1 disappear while it is outside the band.
        let digest = String(keys[1].rawValue.dropFirst("sha256:".count))
        try FileManager.default.removeItem(at: f.assets.appendingPathComponent("sha256").appendingPathComponent(digest))
        let forwarded = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.cards[4].id, placement: .center)))
        XCTAssertNil(forwarded.window.items[1].image, "outside the band the bitmap is released")

        let returned = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.cards[2].id, placement: .center)))
        XCTAssertEqual(returned.window.items.map(\.id), f.ids)
        let returning = returned.window.items[1]
        XCTAssertEqual(returning.layout, .textOnly,
            "the reconstruction failed, so the card is re-admitted as a declared text card")
        XCTAssertFalse(returning.isImageBearing, "a placeholder frame would have drawn it as an image slot")
        XCTAssertNil(returning.image)
        XCTAssertNotNil(returned.window.items[0].image, "the card whose reconstruction succeeded is ready")
        XCTAssertNotNil(returned.window.items[3].image)
        XCTAssertNotNil(returned.window.items[4].image)
    }
}

private extension RenderReadyAdmissionTests {
    func snapshot(_ session: FeedSession, _ observation: ViewportObservation) async throws
        -> FeedPresentationSnapshot {
        let value = try await session.submitViewport(observation)
        return try XCTUnwrap(value)
    }
}
