import Foundation
import XCTest
import CryptoKit
import CoreGraphics
import ImageIO
import FeedMineDomain
@testable import FeedMinePersistence
@testable import FeedMinePublication
@testable import FeedMineMedia
import FeedMineRuntime

private final class ScrollDecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var decodes = 0
    func increment() { lock.lock(); decodes += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return decodes }
}

/// T3 — the admitted boundary under a real reader: the admitted list is the frozen window around the
/// reader's anchor (at most `backwardCapacity` cards before it and `forwardCapacity` after it), only
/// genuine forward movement at the tail grows it, layout changes and backward navigation never do, and
/// cards the window cuts stay reachable from the local store. Decoded pixels are residency (bounded),
/// and so is the admitted structure.
@MainActor
final class ScrollAdmissionTests: XCTestCase {
    func testRenderedOldCardRemainsObservableAfterTheCanonicalWindowMoved() async throws {
        let f = try fixture()
        let first = try await admitted(f.session, .initial(f.bounds))
        let reading = observation(f.cards[0], placement: .center)
        let evidence = try XCTUnwrap(first.evidence(for: reading))
        _ = try await recorded(f.session, observation(f.cards[4], placement: .top))
        let moved = try await admitted(f.session, .forwardScroll(observation(f.cards[4], placement: .top)))
        XCTAssertFalse(moved.window.items.contains(where: { $0.id == reading.anchor.cardID }))
        let result = try await f.session.submitViewport(reading, from: evidence)
        let returned = try XCTUnwrap(result)
        XCTAssertEqual(returned.editionID, first.editionID)
        XCTAssertEqual(returned.window.anchor, reading.anchor,
            "a real card in the borrowed rendered window remains a valid reading position")
        XCTAssertTrue(returned.window.items.contains(where: { $0.id == reading.anchor.cardID }))
        let permitted = Set(first.window.items.map(\.id) + moved.window.items.map(\.id))
        XCTAssertTrue(Set(returned.window.items.map(\.id)).isSubset(of: permitted),
            "a reading proof cannot admit unpublished or never-admitted future cards")
        XCTAssertLessThanOrEqual(returned.window.items.count, 7)
    }

    /// A historical card is still rendered in the borrowed window after the canonical
    /// presentation has moved on. A failed exposure transaction must not partially install
    /// its recovered window or consume the one-shot viewport evidence ordinal.
    func testBorrowedViewportWriteFailurePreservesStateAndEvidenceForRetry() async throws {
        let f = try fixture()
        let first = try await admitted(f.session, .initial(f.bounds))
        let oldReading = observation(f.cards[0], placement: .top)
        let evidence = try XCTUnwrap(first.evidence(for: oldReading, ordinal: 1))
        _ = try await recorded(f.session, observation(f.cards[4], placement: .top))
        let moved = try await admitted(f.session, .forwardScroll(observation(f.cards[4], placement: .top)))
        XCTAssertFalse(moved.window.items.contains { $0.id == f.cards[0].id })

        try f.database.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_borrowed_usage BEFORE UPDATE ON publication_card_usage
                BEGIN SELECT RAISE(ABORT, 'borrowed viewport exposure failed'); END
                """)
        }
        do {
            _ = try await f.session.submitViewport(oldReading, from: evidence)
            XCTFail("A real historical exposure must attempt the SQLite write")
        } catch {
            XCTAssertTrue(String(describing: error).contains("borrowed viewport exposure failed"))
        }
        let unchanged = await f.session.currentPresentation()
        XCTAssertEqual(unchanged, moved, "Failed exposure must not install a recovered viewport")
        try f.database.write { db in
            try db.execute(sql: "DROP TRIGGER fail_borrowed_usage")
        }
        let retried = try await f.session.submitViewport(oldReading, from: evidence)
        let returned = try XCTUnwrap(retried)
        XCTAssertEqual(returned.window.anchor, oldReading.anchor)
        XCTAssertTrue(returned.window.items.contains { $0.id == f.cards[0].id })
        XCTAssertEqual(returned.provenance.position, moved.provenance.position + 1,
            "Failed borrowed projection must not consume an extra provenance position")
        let installedAfterRetry = await f.session.currentPresentation()
        XCTAssertEqual(installedAfterRetry, returned)
    }

    func testAnotherSessionCannotAuthorizeAReadingPosition() async throws {
        let f = try fixture()
        _ = try await admitted(f.session, .initial(f.bounds))
        _ = try await recorded(f.session, observation(f.cards[4], placement: .top))
        let current = try await admitted(f.session, .forwardScroll(observation(f.cards[4], placement: .top)))
        let other = FeedSession(publicationHistory: PublicationHistory(database: f.database))
        let otherProjection = try await admitted(other, .initial(.init(backwardCapacity: 0, forwardCapacity: 10)))
        let observation = observation(f.cards[6], placement: .center)
        let wrong = try XCTUnwrap(otherProjection.evidence(for: observation))
        let after = try await f.session.submitViewport(observation, from: wrong)
        XCTAssertNil(after, "another sequence must not become a reading observation")
        let unchanged = await f.session.currentPresentation()
        XCTAssertEqual(unchanged, current)
    }

    func testLateRenderedObservationCannotUndoNewerReading() async throws {
        let f = try fixture()
        let first = try await admitted(f.session, .initial(f.bounds))
        let newer = observation(f.cards[3], placement: .center)
        let older = observation(f.cards[1], placement: .center)
        let accepted = try await f.session.submitViewport(newer,
            from: XCTUnwrap(first.evidence(for: newer, ordinal: 2)))
        let rejected = try await f.session.submitViewport(older,
            from: XCTUnwrap(first.evidence(for: older, ordinal: 1)))
        XCTAssertNil(rejected)
        let current = await f.session.currentPresentation()
        XCTAssertEqual(current, accepted)
    }

    private struct Fixture {
        let database: RuntimeDatabase
        let directory: URL
        let edition: FeedEdition
        let cards: [PublishedCard]
        let session: FeedSession
        let bounds: FeedPresentationBounds

        var ids: [PublicationCardID] { cards.map(\.id) }
    }

    /// 30 published cards in two segments, every card carrying the same local image bytes.
    private func fixture(cards count: Int = 30, bounds: FeedPresentationBounds = .init(backwardCapacity: 2,
        forwardCapacity: 4), onDecode: @escaping @Sendable () -> Void = {}) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let bytes = try Self.pngBytes(width: 60, height: 40)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let assets = directory.appendingPathComponent("Media/sha256", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try bytes.write(to: assets.appendingPathComponent(digest))
        let key = try XCTUnwrap(PublishedMediaKey(rawValue: "sha256:" + digest))
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let edition = WarmPresentationFixture.edition()
        let cards = try (0..<count).map { try Self.card(title: "P\($0)", key: key) }
        let half = count / 2
        let segments = [[Int](0..<half), [Int](half..<count)]
        let store = PublicationStore(database: database)
        for (ordinal, indexes) in segments.enumerated() {
            let segment = try XCTUnwrap(FeedSegment(id: FeedSegmentID(), editionID: edition.id,
                ordinal: UInt64(ordinal), segmentSeed: UInt64(ordinal),
                publicationSchemaVersion: edition.publicationSchemaVersion, createdAt: edition.createdAt,
                cardIDs: indexes.map { cards[$0].id }))
            let values = try PublicationPersistenceMapping.records(segment: segment,
                cards: indexes.map { cards[$0] })
            if ordinal == 0 {
                try store.createEdition(PublicationPersistenceMapping.record(edition), firstSegment: values.0,
                    cards: values.1)
            } else {
                try store.appendSegment(values.0, cards: values.1)
            }
        }
        try PublicationHistory(database: database).saveCursor(.init(editionID: edition.id,
            anchor: .init(cardID: cards[0].id, placement: .top)), updatedAt: Date(timeIntervalSince1970: 40))
        let session = FeedSession(publicationHistory: .init(database: database),
            imageDecoder: PresentationImageDecoder(assetDirectory: directory.appendingPathComponent("Media"),
                heroMaxPixel: 60, thumbnailMaxPixel: 30, onDecode: onDecode))
        return .init(database: database, directory: directory, edition: edition, cards: cards,
            session: session, bounds: bounds)
    }

    private static func card(title: String, key: PublishedMediaKey) throws -> PublishedCard {
        try XCTUnwrap(PublishedCard(id: PublicationCardID(),
            origin: PublishedOrigin(originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                sourceID: SourceID(), providerID: ProviderID(), sourceDisplayName: "Source",
                providerDisplayName: nil),
            contentEntityID: nil, contentClusterID: nil,
            text: PublishedText(title: title, primaryText: "Local text"),
            timestamp: PublishedTimestamp(value: Date(timeIntervalSince1970: 10), kind: .observed),
            media: PublishedMediaSet(primary: try XCTUnwrap(PublishedMediaRef(key: key, pixelWidth: 600,
                pixelHeight: 400, mimeType: "image/png"))),
            renderContract: XCTUnwrap(RenderContract(layout: .hero, mediaAspectRatio: 1.5)),
            primaryAction: nil))
    }

    private static func pngBytes(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func observation(_ card: PublishedCard, placement: PresentationAnchorPlacement = .center) -> ViewportObservation {
        .init(anchor: .init(cardID: card.id, placement: placement))
    }

    private func admitted(_ session: FeedSession,
        _ admission: FeedPresentationAdmission) async throws -> FeedPresentationSnapshot {
        let value = try await session.admitPresentation(admission)
        return try XCTUnwrap(value)
    }

    private func recorded(_ session: FeedSession,
        _ observation: ViewportObservation) async throws -> FeedPresentationSnapshot {
        let value = try await session.submitViewport(observation)
        return try XCTUnwrap(value)
    }

    /// A layout change (rotation, text size, an invalidated capture) re-reports geometry. It is not
    /// movement: it must not admit anything, whatever the placement it reports.
    func testLayoutChangeCannotAdmit() async throws {
        let f = try fixture()
        let admitted = try await self.admitted(f.session, .initial(f.bounds))
        XCTAssertEqual(admitted.window.items.map(\.id), Array(f.ids[0...4]))
        // The same anchor with the other placement is a layout fact, not a gesture.
        for placement in [PresentationAnchorPlacement.top, .center] {
            let again = try await recorded(f.session, observation(f.cards[4], placement: placement))
            XCTAssertEqual(again.window.items.map(\.id), Array(f.ids[0...4]),
                "A layout change must not extend the admitted prefix")
        }
        // A repeated admission that would extend still requires the observation to be the current one.
        let staleValue = try await f.session.admitPresentation(.forwardScroll(observation(f.cards[0], placement: .top)))
        XCTAssertEqual(staleValue?.window.items.map(\.id), Array(f.ids[0...4]),
            "An observation that is not the reader's current anchor cannot admit")
    }

    /// Moving back must never reveal cards that were not admitted, and re-entering admitted history
    /// is not a new admission. The admitted list is the window around the anchor, so a forward window
    /// cuts cards behind it — they stay reachable from the store instead of being lost.
    func testBackwardNavigationDoesNotExposeFuture() async throws {
        let f = try fixture()
        let admitted = try await self.admitted(f.session, .initial(f.bounds))
        // The checkpoint anchors the reader on the first card, so the installed window is its forward bound.
        XCTAssertEqual(admitted.window.items.map(\.id), Array(f.ids[0...4]))
        let tail = try XCTUnwrap(admitted.window.items.last)
        _ = try await recorded(f.session, observation(f.cards[4], placement: .top))
        let extended = try await self.admitted(f.session, .forwardScroll(observation(f.cards[4], placement: .top)))
        // The admitted list is the window around the anchor: two cards before it and four after it.
        XCTAssertEqual(extended.window.items.map(\.id), Array(f.ids[2...8]))
        XCTAssertEqual(extended.window.anchor.cardID, f.cards[4].id)
        let future = Set(f.ids[9...])
        XCTAssertTrue(Set(extended.window.items.map(\.id)).isDisjoint(with: future),
            "Navigation must never expose a card that was not admitted")
        // Backward navigation inside the admitted window adds nothing and removes nothing: the window
        // is the bound and the observation only moves the anchor.
        let backward = try await recorded(f.session, observation(f.cards[2], placement: .center))
        XCTAssertEqual(backward.window.items.map(\.id), Array(f.ids[2...8]))
        XCTAssertEqual(backward.window.anchor.cardID, f.cards[2].id)
        // Re-entering already-admitted history is not a new admission: only the anchor moves.
        let forwardAgain = try await recorded(f.session, observation(f.cards[8], placement: .top))
        XCTAssertEqual(forwardAgain.window.items.map(\.id), Array(f.ids[2...8]))
        XCTAssertEqual(forwardAgain.window.anchor.cardID, f.cards[8].id)
        XCTAssertEqual(Set(forwardAgain.window.items.map(\.id)).count, forwardAgain.window.items.count)
        XCTAssertGreaterThan(forwardAgain.provenance.position, backward.provenance.position)
        XCTAssertNotEqual(tail.id, f.cards[8].id)
        // What the forward window cut is not lost: an admission near the head re-reads those cards from
        // the local store, keeping the order, the anchor and the disjunction with the unadmitted future.
        let head = observation(f.cards[2], placement: .center)
        _ = try await recorded(f.session, head)
        let reachable = try await self.admitted(f.session, .backwardScroll(head))
        XCTAssertEqual(reachable.window.items.map(\.id), Array(f.ids[0...6]),
            "Backward admission re-reads the cards the window had cut")
        XCTAssertEqual(reachable.window.anchor.cardID, f.cards[2].id)
        XCTAssertEqual(Set(reachable.window.items.map(\.id)).count, reachable.window.items.count)
        XCTAssertTrue(Set(reachable.window.items.map(\.id)).isDisjoint(with: future))
    }

    /// A failed local re-decode is not a successful residency restore. When the exact asset returns
    /// after an offline/eviction interval, an ordinary viewport observation must be able to rematerialize
    /// the same historical card; no new Edition, retry timer or session recreation is involved.
    func testFailedRedecodeRetainsReturnEligibilityAfterLocalAssetRecovers() async throws {
        let decodes = ScrollDecodeCounter()
        let f = try fixture(cards: 10, bounds: .init(backwardCapacity: 2, forwardCapacity: 4),
            onDecode: { decodes.increment() })
        let installed = try await admitted(f.session, .initial(f.bounds))
        XCTAssertEqual(decodes.value, 5, "Initial restore decodes the actual five-card window")
        XCTAssertEqual(installed.window.items.map(\.id), Array(f.ids[0...4]))
        XCTAssertNotNil(installed.window.items.first?.image)

        // Moving to P4 releases P0 and P1 but leaves the history and its IDs admitted.
        let atFour = try await recorded(f.session, observation(f.cards[4], placement: .top))
        XCTAssertNil(atFour.window.items.first?.image)
        XCTAssertEqual(decodes.value, 5, "Releasing pixels must not trigger more decoding")
        let directory = f.directory.appendingPathComponent("Media/sha256")
        let asset = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil).first)
        let bytes = try Data(contentsOf: asset)
        try FileManager.default.removeItem(at: asset)

        // The return fails to decode because the asset has been evicted. This must not mark the
        // released pixels as restored; the published identity and fixed visual contract remain.
        let home = observation(f.cards[0], placement: .top)
        let unavailable = try await recorded(f.session, home)
        XCTAssertEqual(unavailable.window.items.map(\.id), installed.window.items.map(\.id))
        XCTAssertNil(unavailable.window.items.first?.image)
        XCTAssertEqual(decodes.value, 7, "Only the two released images should be tried, not the whole band")

        // Repeated reports of the same card cannot be treated as a timer for disk retries.
        // They must be exact no-ops even after bytes return, while a new reader movement
        // can reconstruct the earlier region without a new Edition or session.
        for _ in 0..<30 {
            let unchanged = try await recorded(f.session, home)
            XCTAssertEqual(unchanged, unavailable)
        }
        XCTAssertEqual(decodes.value, 7, "Missing local bytes cannot cause one decode per viewport tick")
        try bytes.write(to: asset)
        for _ in 0..<30 {
            let unchanged = try await recorded(f.session, home)
            XCTAssertEqual(unchanged, unavailable, "Stationary media arrival must not change a held card")
        }
        XCTAssertEqual(decodes.value, 7, "Late asset arrival cannot upgrade a stationary presentation")
        _ = try await recorded(f.session, observation(f.cards[4], placement: .top))
        let recovered = try await recorded(f.session, home)
        XCTAssertEqual(decodes.value, 9, "Re-entry decodes only the two released images")
        XCTAssertEqual(recovered.window.items.map(\.id), installed.window.items.map(\.id))
        XCTAssertNotNil(recovered.window.items[0].image,
            "Failed re-decode must remain eligible for the next local rematerialization")
        XCTAssertNotNil(recovered.window.items[1].image)
        XCTAssertEqual(recovered.window.anchor.cardID, installed.window.anchor.cardID)
    }

    /// Decoded pixels are bounded residency: far cards keep their frozen descriptor and release the
    /// bitmap; coming back re-decodes the same asset without changing geometry. The admitted list is the
    /// window around the anchor, so the pixels that stay resident are exactly the ones the window keeps.
    func testDecodedImageResidencyIsBoundedAroundTheReader() async throws {
        let f = try fixture(cards: 30, bounds: .init(backwardCapacity: 2, forwardCapacity: 4))
        var current = try await admitted(f.session, .initial(f.bounds))
        // The checkpoint anchors the reader on the first card: the installed window is cards 0...4.
        XCTAssertEqual(current.window.items.map(\.id), Array(f.ids[0...4]))
        XCTAssertTrue(current.window.items.allSatisfy { $0.image != nil }, "The admitted window decodes its images")
        let frozenLayout = try XCTUnwrap(current.window.items.first?.layout)
        let frozenRatio = try XCTUnwrap(current.window.items.first?.mediaAspectRatio)
        let originalImage = try XCTUnwrap(current.window.items.first?.image)
        // Scroll forward to the end of the edition, four cards at a time. The observation moves the reader
        // (and releases pixels outside the residency zone, without changing the list); the admission is what
        // cuts the list back to the window around that anchor.
        var reader = current
        var cursor = 4
        while cursor < f.cards.count - 1 {
            let anchor = f.cards[min(cursor, f.cards.count - 1)]
            reader = try await recorded(f.session, observation(anchor, placement: .top))
            current = try await admitted(f.session, .forwardScroll(observation(anchor, placement: .top)))
            cursor += 4
        }
        // The admitted list is now the window around the reader's anchor — two cards before it, four after
        // it — not the published prefix. The cards the reader left behind are cut and stay in the store.
        XCTAssertEqual(current.window.items.map(\.id), Array(f.ids[26...29]),
            "The admitted list is the window around the reader's anchor")
        XCTAssertEqual(current.window.anchor.cardID, f.cards[28].id)
        XCTAssertLessThanOrEqual(current.window.items.count,
            f.bounds.backwardCapacity + 1 + f.bounds.forwardCapacity)
        // The observation that preceded the last admission left the list wider than the residency zone (the
        // list only moves on admission), so that snapshot is where released pixels are observable.
        XCTAssertEqual(reader.window.items.map(\.id), Array(f.ids[22...28]))
        XCTAssertEqual(reader.window.anchor.cardID, f.cards[28].id)
        let farBehind = try XCTUnwrap(reader.window.items.first)
        XCTAssertNil(farBehind.image, "A card far behind the reader releases its decoded pixels")
        XCTAssertEqual(farBehind.layout, frozenLayout, "Residency never changes the published layout")
        XCTAssertEqual(farBehind.mediaAspectRatio, frozenRatio, "The slot keeps its frozen geometry")
        XCTAssertTrue(farBehind.isImageBearing, "A card published with an image slot is never redefined as text-only")
        XCTAssertNil(reader.window.items[2].image, "The card re-read below is one of the released ones")
        let nearTheReader = try XCTUnwrap(reader.window.items.last)
        XCTAssertNotNil(nearTheReader.image, "The reader's own window keeps its images")
        XCTAssertEqual(nearTheReader.id, f.cards[28].id)
        // Cards the window cut are reachable, not lost: an admission near the head reads them from the local
        // store again, and the ones that had released their pixels come back decoded from the same asset.
        let head = observation(f.cards[26], placement: .center)
        _ = try await recorded(f.session, head)
        let reachable = try await self.admitted(f.session, .backwardScroll(head))
        XCTAssertEqual(reachable.window.items.map(\.id), Array(f.ids[24...29]),
            "Backward admission re-reads the cards the window had cut")
        XCTAssertEqual(reachable.window.anchor.cardID, f.cards[26].id)
        XCTAssertEqual(Set(reachable.window.items.map(\.id)).count, reachable.window.items.count)
        let redecoded = try XCTUnwrap(reachable.window.items.first?.image)
        XCTAssertEqual(redecoded.key, originalImage.key)
        XCTAssertEqual(redecoded.cgImage.width, originalImage.cgImage.width)
        XCTAssertEqual(reachable.window.items.first?.layout, frozenLayout)
        XCTAssertEqual(reachable.window.items.first?.mediaAspectRatio, frozenRatio)
    }
}
