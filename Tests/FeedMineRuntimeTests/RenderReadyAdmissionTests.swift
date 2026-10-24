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
/// decoded before admission; a card whose media cannot be decoded is excluded, never converted to text under
/// the same identity or admitted as an image slot waiting for bytes. Released pixels are reconstructed before return.
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

    /// `cards` real published rows, image cards unless `textIndices` declares a card as text, anchored at
    /// `anchor` (center).
    private func fixture(cards count: Int = 3, anchor: Int, materialized: Set<Int>,
        textIndices: Set<Int> = []) throws -> Fixture {
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
            let isText = textIndices.contains(index)
            return PublicationStore.CardRecord(id: PublicationCardID(), originRecordID: OriginRecordID(),
                originRevisionID: OriginRevisionID(), sourceID: nil, providerID: nil, sourceDisplayName: nil,
                providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil, title: "C\(index)",
                primaryText: isText ? "Local text" : "Local image", timestampValue: nil, timestampKind: nil,
                mediaKey: isText ? nil : "sha256:" + digest,
                mediaPixelWidth: isText ? nil : 60, mediaPixelHeight: isText ? nil : 40,
                mediaMimeType: isText ? nil : "image/png",
                renderLayout: isText ? "textOnly" : "hero",
                renderMediaAspectRatio: isText ? nil : 1.5,
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

    private func decoder(_ f: Fixture, onDecode: @escaping @Sendable () -> Void = {}) throws
        -> PresentationImageDecoder {
        try XCTUnwrap(PresentationImageDecoder(assetDirectory: f.assets,
            heroMaxPixel: 60, thumbnailMaxPixel: 30, onDecode: onDecode))
    }

    private func session(_ f: Fixture, onDecode: @escaping @Sendable () -> Void = {}) throws -> FeedSession {
        FeedSession(publicationHistory: .init(database: f.database), imageDecoder: try decoder(f, onDecode: onDecode))
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

    /// **The reopen.** The durable checkpoint names an image card whose local asset is gone; the ready text cards
    /// around it are admitted. The missing card does not cross the admission boundary (the owner's render-ready
    /// rule), so the window is presented on the closest ready card — but the media failure must be *stated*, not
    /// hidden behind a position that looks like the reader's own, and the durable record must keep naming the
    /// reader's card. Before the fix the restored snapshot carried no `unavailableImageCardIDs` at all.
    func testRestoreStatesAnUnavailableDurableAnchorWithoutRewritingTheCheckpoint() async throws {
        let f = try fixture(cards: 5, anchor: 2, materialized: [0, 1, 3, 4], textIndices: [0, 1, 3, 4])
        let store = SessionStore(database: f.database)
        let durable = try XCTUnwrap(store.checkpoint())
        XCTAssertEqual(durable.cardID, f.ids[2], "premise: the reader's card is the image card without an asset")

        let session = try session(f)
        let restored = try await snapshot(session, .restore(.init(backwardCapacity: 2, forwardCapacity: 2)))

        XCTAssertEqual(restored.window.items.map(\.id), [f.ids[0], f.ids[1], f.ids[3], f.ids[4]],
            "the missing card does not cross the boundary; the ready cards around it are admitted")
        XCTAssertEqual(restored.window.anchor.cardID, f.ids[3],
            "the presented anchor is the closest ready card, not the card without pixels")
        XCTAssertEqual(restored.unavailableImageCardIDs, [f.ids[2]],
            "the media failure of the reader's own card is stated, never hidden")
        XCTAssertEqual(try store.checkpoint(), durable,
            "the durable identity still names the reader's card; the substitute is a presentation fact")
        XCTAssertEqual(FeedDestinationGate.readiness(of: f.ids[3], in: restored), .ready)
        XCTAssertEqual(FeedDestinationGate.readinessAfterPreparation(of: f.ids[2], in: restored),
            .unavailableAfterPreparation)

        // The next observation replaces the projection; the unavailable fact must survive it.
        let observed = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[0], placement: .center)))
        XCTAssertEqual(observed.unavailableImageCardIDs, [f.ids[2]],
            "the unavailable fact survives the projection that follows the restore")
        XCTAssertEqual(try store.checkpoint(), durable)
    }

    /// **The accepted jump.** A destination the reader actually moved to (the UI states it as deliberate once the
    /// gate accepted it) establishes a new position: the substitution ends, the milestone writes that card and the
    /// next restore lands on it. A preparation request that never became a move (`deliberate: false`) must not:
    /// the milestone still refuses, and the durable record keeps the reader's card.
    func testAnAcceptedJumpWritesTheDestinationAndARejectedPreparationKeepsTheDurableCard() async throws {
        let f = try fixture(cards: 5, anchor: 2, materialized: [0, 1, 3, 4], textIndices: [0, 1, 3, 4])
        let reader = try session(f)
        _ = try await snapshot(reader, .restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
        let store = SessionStore(database: f.database)
        XCTAssertEqual(try store.checkpoint()?.cardID, f.ids[2], "premise: the durable card lost its asset")

        // A preparation request is not a completed move.
        _ = try await reader.submitViewport(.init(anchor: .init(cardID: f.ids[4], placement: .top)),
            deliberate: false)
        let refused = try await reader.checkpointCurrentPosition(at: Date())
        XCTAssertFalse(refused, "a request for a destination band must not end the restore's substitution")
        XCTAssertEqual(try store.checkpoint()?.cardID, f.ids[2],
            "the aborted preparation keeps the reader's durable card")

        // The accepted destination is a real move: the substitution ends and the milestone writes it.
        _ = try await reader.submitViewport(.init(anchor: .init(cardID: f.ids[4], placement: .top)),
            deliberate: true)
        let wrote = try await reader.checkpointCurrentPosition(at: Date())
        XCTAssertTrue(wrote)
        XCTAssertEqual(try store.checkpoint()?.cardID, f.ids[4])

        let reopened = try session(f)
        let restored = try await snapshot(reopened, .restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
        XCTAssertEqual(restored.window.anchor.cardID, f.ids[4],
            "the next restore lands on the destination the reader established")
        XCTAssertNil(restored.unavailablePositionCardID, "and no substitute fact remains")
    }

    /// **The automatic boundary.** After a restore that could not redraw the reader's card, the rendering's own
    /// resting position names the substitute. It is not a reader move: the durable record must keep the reader's
    /// card through the automatic statement and through a lifecycle checkpoint. The layout's own observation of
    /// another card is not a gesture either; only a deliberate move may establish a new position.
    func testAutomaticRestDoesNotReplaceTheUnavailableDurableAnchorAndADeliberateMoveDoes() async throws {
        let f = try fixture(cards: 5, anchor: 2, materialized: [0, 1, 3, 4], textIndices: [0, 1, 3, 4])
        let store = SessionStore(database: f.database)
        let durable = try XCTUnwrap(store.checkpoint())
        let session = try session(f)
        let restored = try await snapshot(session, .restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
        XCTAssertEqual(restored.unavailablePositionCardID, f.ids[2])
        XCTAssertEqual(restored.window.anchor.cardID, f.ids[3])

        let kept = try await session.notePresentedPosition(.init(cardID: f.ids[3], placement: .top), atRest: true,
            at: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(kept, .keptUnavailablePosition(cardID: f.ids[2]))
        let checkpointed = try await session.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 1_001))
        XCTAssertFalse(checkpointed, "a lifecycle milestone is not a reader move either")
        XCTAssertEqual(try store.checkpoint(), durable,
            "no reader move: the checkpoint still names the reader's card")

        // A deliberate move establishes the new position.
        _ = try await session.submitViewport(.init(anchor: .init(cardID: f.ids[4], placement: .center)),
            deliberate: true)
        let afterMove = await session.currentPresentation()
        XCTAssertNil(afterMove?.unavailablePositionCardID, "the substitute no longer stands for the reader")
        // The automatic rest above left the substitute as the rendering's presented top. A milestone before the
        // next report must not fall back to it: no reader move would repair that record afterwards.
        let milestone = try await session.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 1_003))
        XCTAssertTrue(milestone)
        XCTAssertEqual(try store.checkpoint()?.cardID, f.ids[4])
        let written = try await session.notePresentedPosition(.init(cardID: f.ids[4], placement: .top),
            atRest: true, at: Date(timeIntervalSince1970: 1_004))
        XCTAssertEqual(written, .written(cardID: f.ids[4], placement: .top),
            "the exact top replaces the milestone's window anchor, never the substitute")
        XCTAssertEqual(try store.checkpoint()?.cardID, f.ids[4])
    }

    /// The rendering's own observation of another card is not a gesture: the substitution protection stays until a
    /// deliberate move, and the automatic rest at that card is still refused.
    func testAutomaticObservationOfAnotherCardDoesNotEndTheSubstitutionProtection() async throws {
        let f = try fixture(cards: 5, anchor: 2, materialized: [0, 1, 3, 4], textIndices: [0, 1, 3, 4])
        let store = SessionStore(database: f.database)
        let durable = try XCTUnwrap(store.checkpoint())
        let session = try session(f)
        _ = try await snapshot(session, .restore(.init(backwardCapacity: 2, forwardCapacity: 2)))

        _ = try await session.submitViewport(.init(anchor: .init(cardID: f.ids[4], placement: .center)))
        let stillKept = try await session.notePresentedPosition(.init(cardID: f.ids[4], placement: .top),
            atRest: true, at: Date(timeIntervalSince1970: 1_002))
        XCTAssertEqual(stillKept, .keptUnavailablePosition(cardID: f.ids[2]))
        XCTAssertEqual(try store.checkpoint(), durable,
            "a layout observation is not a reader move")
    }

    /// **Asset recovery.** With the durable record protected from the automatic substitute, the bytes coming back
    /// make the next restore land on the reader's original card — not on the neighbour the first run had to draw.
    func testReturningAssetLetsTheNextRestoreLandOnTheOriginalCard() async throws {
        let f = try fixture(cards: 5, anchor: 2, materialized: [0, 1, 3, 4], textIndices: [0, 1, 3, 4])
        let store = SessionStore(database: f.database)
        let durable = try XCTUnwrap(store.checkpoint())
        let session = try session(f)
        let restored = try await snapshot(session, .restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
        _ = try await session.notePresentedPosition(.init(cardID: restored.window.anchor.cardID,
            placement: .top), atRest: true, at: Date(timeIntervalSince1970: 1_000))
        _ = try await session.checkpointCurrentPosition(at: Date(timeIntervalSince1970: 1_001))
        XCTAssertEqual(try store.checkpoint(), durable)

        let key = try XCTUnwrap(f.cards[2].mediaKey)
        let digest = String(key.dropFirst("sha256:".count))
        try pngBytes(shade: UInt8(20 + (2 * 17) % 200))
            .write(to: f.assets.appendingPathComponent("sha256").appendingPathComponent(digest))

        let reopened = FeedSession(publicationHistory: .init(database: f.database),
            imageDecoder: try decoder(f))
        let again = try await snapshot(reopened, .restore(.init(backwardCapacity: 2, forwardCapacity: 2)))
        XCTAssertEqual(again.window.anchor.cardID, f.ids[2], "the reader's card, not the substitute")
        XCTAssertNil(again.unavailablePositionCardID)
        XCTAssertTrue(again.unavailableImageCardIDs.isEmpty)
    }

    /// The launch path, not only `.restore`: a warm start projects the reader's window **before the actor exists**,
    /// so the unavailable fact has to be in that value, and the session that adopts it must keep it across the next
    /// projection instead of dropping the excluded card from its memory.
    func testWarmStartKeepsTheUnavailableDurableAnchorAcrossTheAdoptedSession() async throws {
        let f = try fixture(cards: 5, anchor: 2, materialized: [0, 1, 3, 4], textIndices: [0, 1, 3, 4])
        let decoder = try decoder(f)
        let warm = try XCTUnwrap(FeedSession.warmStart(publicationHistory: .init(database: f.database),
            imageDecoder: decoder, bounds: .init(backwardCapacity: 2, forwardCapacity: 2)))
        XCTAssertEqual(warm.snapshot.window.anchor.cardID, f.ids[3])
        XCTAssertEqual(warm.snapshot.unavailableImageCardIDs, [f.ids[2]],
            "the value drawn before the first frame states the media failure")

        let session = FeedSession(publicationHistory: .init(database: f.database), imageDecoder: decoder,
            warmStart: warm)
        let observed = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[0], placement: .center)))
        XCTAssertEqual(observed.unavailableImageCardIDs, [f.ids[2]],
            "the adopted session keeps the fact the warm start stated")
    }

    /// The unavailable fact is a **decision**, not a per-projection answer: when the bytes come back and the card is
    /// admitted with pixels, the decision ends for good. A later release outside the pixel band is residency, not a
    /// new media failure — and the card must be reconstructible again on return.
    func testARecoveredAnchorStopsBeingUnavailableAndIsReconstructedOnReturn() async throws {
        let f = try fixture(cards: 8, anchor: 3, materialized: [3], textIndices: [0, 1, 4, 5, 6, 7])
        let session = try session(f)
        let restored = try await snapshot(session, .restore(.init(backwardCapacity: 1, forwardCapacity: 4)))
        XCTAssertEqual(restored.window.items.map(\.id), [f.ids[3], f.ids[4], f.ids[5], f.ids[6], f.ids[7]])
        XCTAssertEqual(restored.unavailableImageCardIDs, [f.ids[2]], "premise: card 2 has no asset")

        // The asset returns while the session lives; the next admission reconstructs the card.
        let key = try XCTUnwrap(f.cards[2].mediaKey)
        let digest = String(key.dropFirst("sha256:".count))
        try pngBytes(shade: UInt8(20 + (2 * 17) % 200))
            .write(to: f.assets.appendingPathComponent("sha256").appendingPathComponent(digest))
        let backward = try await snapshot(session,
            .backwardScroll(ViewportObservation(anchor: .init(cardID: f.ids[3], placement: .center))))
        XCTAssertEqual(backward.window.items.map(\.id), [f.ids[2], f.ids[3], f.ids[4], f.ids[5], f.ids[6], f.ids[7]])
        XCTAssertNotNil(backward.window.items[0].image, "the reconstructed card returns with its pixels")
        XCTAssertTrue(backward.unavailableImageCardIDs.isEmpty,
            "the reconstruction ends the unavailable decision")

        // Two moves forward leave card 2 outside the protected band, so its bitmap is released.
        _ = try await snapshot(session, ViewportObservation(anchor: .init(cardID: f.ids[7], placement: .center)))
        let forwarded = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[6], placement: .center)))
        XCTAssertNil(forwarded.window.items[0].image, "premise: card 2 released its pixels")
        XCTAssertTrue(forwarded.unavailableImageCardIDs.isEmpty,
            "a residency release does not declare the media unavailable again")

        // And the return reaches it: the decision no longer blocks the reconstruction.
        let reversed = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[2], placement: .center)))
        XCTAssertNotNil(reversed.window.items[0].image, "the card is reconstructed on return")
        XCTAssertTrue(reversed.unavailableImageCardIDs.isEmpty)
    }

    /// A forward admission must not decode cards that cannot fit after the reader's current anchor.
    func testForwardAdmissionDecodesOnlyTheAvailableAnchoredSpace() async throws {
        for (anchorIndex, expectedIndices, expectedDecodes) in [(0, [0, 1, 2], 0), (1, [1, 2, 3], 1)] {
            let f = try fixture(cards: 9, anchor: 0, materialized: [0, 1, 2, 3])
            let decodes = Counter()
            let session = try session(f) { decodes.increment() }
            _ = try await snapshot(session, .restore(.init(backwardCapacity: 0, forwardCapacity: 2)))
            let observation = ViewportObservation(anchor: .init(cardID: f.ids[anchorIndex], placement: .center))
            let observed = try await snapshot(session, observation)
            let before = decodes.value

            let forward = try await snapshot(session, .forwardScroll(observation))

            XCTAssertEqual(forward.window.items.map(\.id), expectedIndices.map { f.ids[$0] })
            XCTAssertEqual(forward.window.anchor, observed.window.anchor)
            XCTAssertEqual(decodes.value - before, expectedDecodes,
                "only cards that can fit after the anchor should be decoded; no scan of the refused tail")
            if expectedDecodes == 0 { XCTAssertEqual(forward, observed) }
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

    /// P03/A5: when the destination's asset is gone, the identity preservation that keeps the list stable must not
    /// make the gate answer `needsPreparation` forever. The preparation completed **unavailable**, the card stays,
    /// and the surface can state the failure instead of spinning on it.
    func testMissingDestinationAssetCompletesAsUnavailableWithoutRemovingCard() async throws {
        let f = try fixture(cards: 9, anchor: 6, materialized: Set(0..<9))
        let session = try session(f)
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1, keepsAdmittedHead: true)
        _ = try await snapshot(session, .restore(bounds))
        let key = try XCTUnwrap(f.cards[1].mediaKey)
        let digest = String(key.dropFirst("sha256:".count))
        try FileManager.default.removeItem(at: f.assets.appendingPathComponent("sha256").appendingPathComponent(digest))
        _ = try await snapshot(session, ViewportObservation(anchor: .init(cardID: f.ids[7], placement: .center)))
        let prepared = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[0], placement: .center)))

        XCTAssertNotNil(prepared.window.items.first { $0.id == f.ids[1] },
            "a falha de asset não remove a carta nem move o leitor")
        XCTAssertEqual(FeedDestinationGate.readiness(of: f.ids[1], in: prepared), .needsPreparation)
        XCTAssertEqual(FeedDestinationGate.readinessAfterPreparation(of: f.ids[1], in: prepared),
            .unavailableAfterPreparation,
            "o preparo concluiu indisponível; não é um novo pedido de preparo")
        XCTAssertEqual(FeedDestinationGate.readinessAfterPreparation(of: f.ids[0], in: prepared), .ready)
    }

    /// P04/A4: a jump between the extremes of admitted history protects its two bands, not the interval between
    /// them. The restore released every index outside its band; the convex hull therefore re-decoded the whole gap,
    /// and residency/decode grew with the jump distance.
    func testDistantJumpRetainsOnlyTwoDisjointBands() async throws {
        let f = try fixture(cards: 48, anchor: 45, materialized: Set(0..<48))
        let decodes = Counter()
        let session = try session(f) { decodes.increment() }
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1, keepsAdmittedHead: true)
        let initial = try await snapshot(session, .restore(bounds))
        XCTAssertEqual(initial.window.items.map(\.id), Array(f.ids.prefix(47)))
        XCTAssertNil(initial.window.items[25].image, "premissa: o restore liberou o interior da janela")

        let before = decodes.value
        let jumped = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[5], placement: .center)))
        XCTAssertEqual(jumped.window.anchor.cardID, f.ids[5])
        XCTAssertEqual(jumped.window.items.map(\.id), Array(f.ids.prefix(47)), "identidade e ordem não mudam")
        let resident = jumped.window.items.filter { $0.image != nil }.count
        XCTAssertLessThanOrEqual(resident, 3 + 3,
            "a residência é a união das duas bandas, não o intervalo entre elas")
        XCTAssertLessThanOrEqual(decodes.value - before, 3,
            "só a banda de destino volta a ser decodificada")
        for index in 4...6 {
            XCTAssertNotNil(jumped.window.items[index].image, "a banda de destino está pronta (carta \(index))")
        }
        XCTAssertNil(jumped.window.items[25].image, "o intervalo entre as bandas não foi reconstruído")
    }

    /// P04: the decode cost of a jump does not depend on how far it goes, once the bands are what is protected.
    func testDistantJumpDecodeDoesNotGrowWithDistance() async throws {
        func decodesForJump(to index: Int) async throws -> Int {
            let f = try fixture(cards: 48, anchor: 45, materialized: Set(0..<48))
            let counter = Counter()
            let session = try session(f) { counter.increment() }
            let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1, keepsAdmittedHead: true)
            _ = try await snapshot(session, .restore(bounds))
            let before = counter.value
            _ = try await snapshot(session,
                ViewportObservation(anchor: .init(cardID: f.ids[index], placement: .center)))
            return counter.value - before
        }
        let near = try await decodesForJump(to: 35)
        let far = try await decodesForJump(to: 5)
        XCTAssertEqual(near, 3)
        XCTAssertEqual(far, near, "a distância entre as bandas não muda o número de decodes")
    }

    /// R04: a programmatic jump (or a VoiceOver/accessibility move, which also sets the position) may reach only a
    /// destination whose pixels are ready. An admitted card outside the protected region answers `needsPreparation`;
    /// the surface keeps the current reading, asks for the destination band (a local reconciliation), and applies the
    /// position only when the prepared value is `ready`.
    func testProgrammaticJumpWaitsForReadyDestination() async throws {
        let f = try fixture(cards: 9, anchor: 3, materialized: Set(0..<9))
        let session = try session(f)
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1, keepsAdmittedHead: true)
        let initial = try await snapshot(session, .restore(bounds))
        XCTAssertEqual(initial.window.items.map(\.id), Array(f.ids.prefix(5)))

        let forwarded = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[4], placement: .center)))
        XCTAssertEqual(FeedDestinationGate.readiness(of: f.ids[1], in: forwarded), .needsPreparation,
            "uma carta admitida fora da região protegida não pode ser aplicada imediatamente")
        XCTAssertEqual(FeedDestinationGate.readiness(of: f.ids[3], in: forwarded), .ready,
            "um destino pronto é aplicado na hora")

        // The surface's preparation: the destination band is decoded before the position is applied.
        let prepared = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[1], placement: .center)))
        XCTAssertEqual(prepared.window.anchor.cardID, f.ids[1])
        XCTAssertEqual(FeedDestinationGate.readinessAfterPreparation(of: f.ids[1], in: prepared), .ready,
            "depois do preparo, o destino está pronto para o salto")
        XCTAssertNotNil(prepared.window.items.first { $0.id == f.ids[1] }?.image)
    }

    /// R04: the VoiceOver rule is the same rule, checked over **every** card of the window: the gate may say `ready`
    /// only for a card that has pixels or is declared text. A released bitmap is never a navigable destination before
    /// preparation, so an assistive move cannot expose an empty slot.
    func testVoiceOverNavigationNeverExposesReleasedPixels() async throws {
        let f = try fixture(cards: 9, anchor: 3, materialized: Set(0..<9))
        let session = try session(f)
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1, keepsAdmittedHead: true)
        _ = try await snapshot(session, .restore(bounds))
        let forwarded = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[4], placement: .center)))

        var flagged = 0
        for card in forwarded.window.items {
            switch FeedDestinationGate.readiness(of: card.id, in: forwarded) {
            case .ready:
                XCTAssertTrue(!card.isImageBearing || card.image != nil,
                    "pronto implica pixels: a carta \(card.id) não pode ser destino acessível sem eles")
            case .needsPreparation:
                flagged += 1
                XCTAssertTrue(card.isImageBearing && card.image == nil)
            case .notAdmitted, .unavailableAfterPreparation:
                XCTFail("uma carta da janela não deveria ser inalcançável na própria janela")
            }
        }
        XCTAssertGreaterThan(flagged, 0, "o arranjo precisa conter ao menos um bitmap liberado")
    }

    /// R04: under memory pressure the reader's own band keeps its pixels — the reading is preserved — and the rest
    /// is released. Identity, order, anchor and geometry do not change; a second signal with nothing to release
    /// allocates nothing.
    func testMemoryPressurePreservesCurrentReading() async throws {
        let f = try fixture(cards: 12, anchor: 4, materialized: Set(0..<12))
        let session = try session(f)
        let bounds = FeedPresentationBounds(backwardCapacity: 1, forwardCapacity: 1, keepsAdmittedHead: true)
        let initial = try await snapshot(session, .restore(bounds))
        XCTAssertEqual(initial.window.items.map(\.id), Array(f.ids.prefix(6)))

        // The move keeps the previous band (R03), so a card just behind the reader still has pixels.
        let moved = try await snapshot(session,
            ViewportObservation(anchor: .init(cardID: f.ids[5], placement: .center)))
        XCTAssertNotNil(moved.window.items[3].image, "a banda anterior ainda está protegida antes da pressão")

        let trimmedOnce = try await session.trimResidencyForMemoryPressure()
        XCTAssertTrue(trimmedOnce)
        let current = await session.currentPresentation()
        let trimmed = try XCTUnwrap(current)
        XCTAssertEqual(trimmed.window.items.map(\.id), moved.window.items.map(\.id),
            "a pressão de memória não altera identidade, ordem nem geometria")
        XCTAssertEqual(trimmed.window.anchor, moved.window.anchor)
        XCTAssertNil(trimmed.window.items[3].image, "a banda anterior deixa de ser protegida sob pressão")
        for index in 4...5 {
            XCTAssertNotNil(trimmed.window.items[index].image,
                "a banda do leitor mantém os pixels (carta \(index))")
        }
        let trimmedAgain = try await session.trimResidencyForMemoryPressure()
        XCTAssertFalse(trimmedAgain,
            "sem nada para soltar, a pressão não aloca nem republica")
    }
}

private extension RenderReadyAdmissionTests {
    func snapshot(_ session: FeedSession, _ observation: ViewportObservation) async throws
        -> FeedPresentationSnapshot {
        let value = try await session.submitViewport(observation)
        return try XCTUnwrap(value)
    }
}
