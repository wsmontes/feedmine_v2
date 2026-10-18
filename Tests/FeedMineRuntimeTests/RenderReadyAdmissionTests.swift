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
            // A distinct shade per card that cannot overflow UInt8 as the fixture grows.
            let bytes = try pngBytes(shade: UInt8(20 + (index * 17) % 200))
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
    /// boundary at all — not as an image slot waiting for pixels (the placeholder defect), and not as a text card
    /// under the same identity (the hidden fallback the owner's rule forbids). The ready cards around it keep
    /// their pixels and are not blocked (INV-17).
    func testAnImageCardWhoseMediaCannotBeDecodedIsNotAdmitted() async throws {
        let f = try fixture(cards: 3, anchor: 1, materialized: [0, 2])
        let decodes = Counter()
        let session = try session(f) { decodes.increment() }
        let admitted = try await snapshot(session, .restore(.init(backwardCapacity: 1, forwardCapacity: 1)))

        XCTAssertEqual(decodes.value, 3, "the media of every candidate went through the decoder")
        XCTAssertFalse(admitted.window.items.contains { $0.id == f.cards[1].id },
            "a card without pixels does not cross the admission boundary")
        XCTAssertFalse(admitted.window.items.contains { $0.id == f.cards[1].id && !$0.isImageBearing },
            "no card with the failed identity is drawn as text")
        XCTAssertEqual(admitted.window.items.map(\.id), [f.ids[0], f.ids[2]],
            "the ready cards around it are admitted and are not blocked")
        XCTAssertEqual(admitted.window.anchor.cardID, f.ids[2],
            "the window is anchored on the closest admitted card when the published anchor is excluded")
        for item in admitted.window.items {
            XCTAssertEqual(item.layout, .hero)
            XCTAssertNotNil(item.image, "a ready card is admitted with its pixels")
        }
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
    /// reconstruction is settled before the value is published, and the card returns with its pixels.
    func testACardReturningToThePixelBandIsReconstructedBeforeItIsDrawn() async throws {
        let f = try fixture(cards: 9, anchor: 3, materialized: Set(0..<9))
        let decodes = Counter()
        let session = try session(f) { decodes.increment() }
        // The head is kept so the whole read is reachable by a forward move; the one-card bound is what decides
        // residency around the reader.
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1, keepsAdmittedHead: true)
        let initial = try await snapshot(session, .restore(bounds))
        XCTAssertEqual(initial.window.items.map(\.id), Array(f.ids.prefix(5)))

        // Forward: the band leaves the first cards, which release their pixels.
        let forwarded = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[4], placement: .center)))
        XCTAssertNil(forwarded.window.items[1].image, "outside the protected region the bitmap is released")

        let before = decodes.value
        let returned = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[2], placement: .center)))
        XCTAssertGreaterThan(decodes.value, before,
            "a reconstrução acontece antes de o valor ser publicado")
        XCTAssertEqual(returned.window.items.map(\.id), Array(f.ids.prefix(5)),
            "nenhuma identidade muda na reversão")
        XCTAssertNotNil(returned.window.items[1].image,
            "a carta reconstruída volta com os pixels antes de ser desenhada")
        for index in 1...3 {
            XCTAssertNotNil(returned.window.items[index].image, "a banda visível está pronta (carta \(index))")
        }
    }

    /// R03: a reverse can reach the surface **before** this observation reaches the runtime. The pixels of the
    /// region the reader was just looking at therefore survive the forward move — releasing them there is an empty
    /// slot at the very instant of exposure. The assertion is made on the value the surface holds *before* the
    /// reverse is delivered, not only after the callback.
    func testReverseExposurePrecedesViewportCallback() async throws {
        let f = try fixture(cards: 12, anchor: 9, materialized: Set(0..<12))
        let session = try session(f)
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1, keepsAdmittedHead: true)
        let initial = try await snapshot(session, .restore(bounds))
        XCTAssertEqual(initial.window.items.map(\.id), Array(f.ids.prefix(11)))

        // The reader moves one card forward; the band becomes 9...10 and the previous band 8...10.
        let forwarded = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[10], placement: .center)))
        XCTAssertEqual(forwarded.window.anchor.cardID, f.ids[10])

        // The reverse gesture happens before the runtime receives it: what the surface draws still holds the
        // destination, with its real image, identity and frozen geometry.
        let held = await session.currentPresentation()
        let beforeReverse = try XCTUnwrap(held)
        let destination = try XCTUnwrap(beforeReverse.window.items.first { $0.id == f.ids[8] })
        XCTAssertNotNil(destination.image,
            "a região que o gesto de reversão revela mantém os pixels antes do callback")
        XCTAssertEqual(destination.layout, .hero)
        XCTAssertEqual(destination.mediaAspectRatio, f.cards[8].renderMediaAspectRatio)

        // And only after the callback does the anchor (and residency) move — nothing disappears in the transition.
        let reversed = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[8], placement: .center)))
        XCTAssertEqual(reversed.window.anchor.cardID, f.ids[8])
        XCTAssertEqual(reversed.window.items.map(\.id), beforeReverse.window.items.map(\.id),
            "a reversão não remove nem reordena cartas")
        for index in 7...9 {
            XCTAssertNotNil(reversed.window.items[index].image,
                "a banda revelada está pronta (carta \(index))")
        }
    }

    /// R03: the asset of an already-admitted card may be gone when the reader returns. The card must not be
    /// removed — that moves every card below it and can take the reader's own anchor away — and it must not become
    /// a text card under the same identity. It keeps its identity, order, anchor and frozen geometry with the
    /// published placeholder, and the other returning cards are reconstructed normally.
    func testMissingAssetDoesNotRemoveVisibleAnchor() async throws {
        let f = try fixture(cards: 9, anchor: 6, materialized: Set(0..<9))
        let session = try session(f)
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1, keepsAdmittedHead: true)
        let initial = try await snapshot(session, .restore(bounds))
        XCTAssertEqual(initial.window.items.map(\.id), Array(f.ids.prefix(8)))
        XCTAssertNil(initial.window.items[1].image, "the restore released the cards outside its band")
        let frozen = try XCTUnwrap(initial.window.items.first { $0.id == f.ids[1] })

        // The bytes of card 1 disappear after publication, while it is outside the protected region.
        let key = try XCTUnwrap(f.cards[1].mediaKey)
        let digest = String(key.dropFirst("sha256:".count))
        try FileManager.default.removeItem(at: f.assets.appendingPathComponent("sha256").appendingPathComponent(digest))

        // Forward, then back into the region that contains card 1.
        _ = try await snapshot(session, ViewportObservation(anchor: .init(cardID: f.ids[7], placement: .center)))
        let returned = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[2], placement: .center)))

        XCTAssertEqual(returned.window.anchor.cardID, f.ids[2],
            "a âncora do leitor não muda por causa de um asset ausente")
        XCTAssertEqual(returned.window.items.map(\.id), Array(f.ids.prefix(8)),
            "nenhuma carta é removida da janela")
        let unavailable = try XCTUnwrap(returned.window.items.first { $0.id == f.ids[1] })
        XCTAssertNil(unavailable.image, "sem pixels")
        XCTAssertEqual(unavailable.layout, frozen.layout, "a geometria congelada não muda")
        XCTAssertEqual(unavailable.mediaAspectRatio, frozen.mediaAspectRatio)
        XCTAssertEqual(unavailable.title, frozen.title)
        XCTAssertEqual(unavailable.primaryText, frozen.primaryText)
        XCTAssertTrue(unavailable.isImageBearing, "não é reclassificada como texto")
        for index in [2, 3] {
            XCTAssertNotNil(returned.window.items[index].image,
                "as cartas ao redor são reconstruídas normalmente (carta \(index))")
        }
    }
}

private extension RenderReadyAdmissionTests {
    func snapshot(_ session: FeedSession, _ observation: ViewportObservation) async throws
        -> FeedPresentationSnapshot {
        let value = try await session.submitViewport(observation)
        return try XCTUnwrap(value)
    }
}
