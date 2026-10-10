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

/// T3 — the admitted boundary under a real reader: only genuine forward movement at the tail
/// extends the list, layout changes and backward navigation never do, and decoded pixels are
/// residency (bounded) while the admitted structure is not.
@MainActor
final class ScrollAdmissionTests: XCTestCase {
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
        forwardCapacity: 4)) throws -> Fixture {
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
                heroMaxPixel: 60, thumbnailMaxPixel: 30))
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
    /// is not a new admission.
    func testBackwardNavigationDoesNotExposeFuture() async throws {
        let f = try fixture()
        let admitted = try await self.admitted(f.session, .initial(f.bounds))
        let tail = try XCTUnwrap(admitted.window.items.last)
        _ = try await recorded(f.session, observation(f.cards[4], placement: .top))
        let extended = try await self.admitted(f.session, .forwardScroll(observation(f.cards[4], placement: .top)))
        XCTAssertEqual(extended.window.items.map(\.id), Array(f.ids[0...8]))
        let future = Set(f.ids[9...])
        XCTAssertTrue(Set(extended.window.items.map(\.id)).isDisjoint(with: future),
            "Navigation must never expose a card that was not admitted")
        // Backward navigation inside the admitted list adds nothing and removes nothing.
        let backward = try await recorded(f.session, observation(f.cards[1], placement: .center))
        XCTAssertEqual(backward.window.items.map(\.id), Array(f.ids[0...8]))
        XCTAssertEqual(backward.window.anchor.cardID, f.cards[1].id)
        // Re-entering already-admitted history is not a new admission: only the anchor moves.
        let forwardAgain = try await recorded(f.session, observation(f.cards[8], placement: .top))
        XCTAssertEqual(forwardAgain.window.items.map(\.id), Array(f.ids[0...8]))
        XCTAssertEqual(Set(forwardAgain.window.items.map(\.id)).count, forwardAgain.window.items.count)
        XCTAssertGreaterThan(forwardAgain.provenance.position, backward.provenance.position)
        XCTAssertNotEqual(tail.id, f.cards[8].id)
    }

    /// Decoded pixels are bounded residency: far cards keep their frozen descriptor and release the
    /// bitmap; coming back re-decodes the same asset without changing geometry.
    func testDecodedImageResidencyIsBoundedAroundTheReader() async throws {
        let f = try fixture(cards: 30, bounds: .init(backwardCapacity: 2, forwardCapacity: 4))
        var current = try await admitted(f.session, .initial(f.bounds))
        XCTAssertEqual(current.window.items.count, 5)
        XCTAssertTrue(current.window.items.allSatisfy { $0.image != nil }, "The admitted window decodes its images")
        let frozenLayout = try XCTUnwrap(current.window.items.first?.layout)
        let frozenRatio = try XCTUnwrap(current.window.items.first?.mediaAspectRatio)
        let originalImage = try XCTUnwrap(current.window.items.first?.image)
        // Scroll forward to the end of the edition, four cards at a time.
        var cursor = 4
        while cursor < f.cards.count - 1 {
            let anchor = f.cards[min(cursor, f.cards.count - 1)]
            _ = try await recorded(f.session, observation(anchor, placement: .top))
            current = try await admitted(f.session, .forwardScroll(observation(anchor, placement: .top)))
            cursor += 4
        }
        XCTAssertEqual(current.window.items.map(\.id), f.ids, "The admitted list is the published order")
        let first = try XCTUnwrap(current.window.items.first)
        XCTAssertNil(first.image, "A card far behind the reader releases its decoded pixels")
        XCTAssertEqual(first.layout, frozenLayout, "Residency never changes the published layout")
        XCTAssertEqual(first.mediaAspectRatio, frozenRatio, "The slot keeps its frozen geometry")
        XCTAssertTrue(first.isImageBearing, "A card published with an image slot is never redefined as text-only")
        let last = try XCTUnwrap(current.window.items.last)
        XCTAssertNotNil(last.image, "The reader's own window keeps its images")
        // Coming back re-decodes the same asset; identity, order and geometry are untouched.
        let back = try await recorded(f.session, observation(f.cards[0], placement: .top))
        XCTAssertEqual(back.window.items.map(\.id), f.ids)
        let redecoded = try XCTUnwrap(back.window.items.first?.image)
        XCTAssertEqual(redecoded.key, originalImage.key)
        XCTAssertEqual(redecoded.cgImage.width, originalImage.cgImage.width)
        XCTAssertEqual(back.window.items.first?.mediaAspectRatio, frozenRatio)
    }
}
