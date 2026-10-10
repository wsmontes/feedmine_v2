import Foundation
import XCTest
import CoreGraphics
import ImageIO
import CryptoKit
import Darwin
import FeedMineDomain
import FeedMinePersistence
import FeedMinePublication
import FeedMineMedia
import FeedMineRuntime

final class ProjectionDecodeMeasurementTests: XCTestCase {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
    func testRepeatedLocalRefreshMeasuresDecodeWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = data as Data
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let assets = directory.appendingPathComponent("Media/sha256")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try bytes.write(to: assets.appendingPathComponent(digest))
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let v = PolicyVersion(rawValue: 1), revision = EditorialRevision(id: EditorialRevisionID(), contextKey: .init(request: .main),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v,
            sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(), editorialRevision: revision, publicationSchemaVersion: 1, selectionSeed: 1, createdAt: Date())
        let card = PublicationStore.CardRecord(id: PublicationCardID(), originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
            sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil,
            title: "Measured", primaryText: "Local image", timestampValue: nil, timestampKind: nil, mediaKey: "sha256:" + digest,
            mediaPixelWidth: 600, mediaPixelHeight: 400, mediaMimeType: "image/png", renderLayout: "hero", renderMediaAspectRatio: 1.5,
            primaryActionKind: nil, primaryActionReference: nil)
        try PublicationStore(database: database).createInitialEdition(edition, firstSegment: .init(id: FeedSegmentID(), editionID: edition.id,
            ordinal: 0, segmentSeed: 1, publicationSchemaVersion: 1, createdAt: Date(), cardIDs: [card.id]), cards: [card],
            initialCheckpoint: .init(editionID: edition.id, cardID: card.id, anchorPlacement: "top", updatedAt: Date()))
        let counter = Counter()
        let session = FeedSession(publicationHistory: .init(database: database), imageDecoder: .init(assetDirectory: directory.appendingPathComponent("Media"),
            heroMaxPixel: 300, thumbnailMaxPixel: 88, onDecode: { counter.increment() }))
        let restored = try await session.admitPresentation(.restore(.init(backwardCapacity: 8, forwardCapacity: 16)))
        let initial = try XCTUnwrap(restored)
        XCTAssertEqual(initial.window.items[0].image?.cgImage.width, 300)
        let anchor = ViewportObservation(anchor: initial.window.anchor)
        var before = rusage(), after = rusage()
        getrusage(RUSAGE_SELF, &before)
        let started = ProcessInfo.processInfo.systemUptime
        // Only the admitted list can change; repeated observations and repeat admission attempts with
        // nothing new published must neither re-project nor re-decode the visible card.
        for _ in 0..<100 {
            _ = try await session.submitViewport(anchor)
            _ = try await session.admitPresentation(.forwardScroll(anchor))
        }
        getrusage(RUSAGE_SELF, &after)
        let userCPU = Double(after.ru_utime.tv_sec - before.ru_utime.tv_sec) + Double(after.ru_utime.tv_usec - before.ru_utime.tv_usec) / 1_000_000
        let systemCPU = Double(after.ru_stime.tv_sec - before.ru_stime.tv_sec) + Double(after.ru_stime.tv_usec - before.ru_stime.tv_usec) / 1_000_000
        print("T7 CPU user=\(userCPU)s system=\(systemCPU)s processMaxRSS=\(after.ru_maxrss) bytes")
        print("T7 projection 100 refresh: ms=\((ProcessInfo.processInfo.systemUptime - started) * 1000), decode=\(counter.value), decodedBytes=\(300 * 200 * 4)")
        XCTAssertEqual(counter.value, 1, "Unchanged visible card must reuse its prepared image")
        try FileManager.default.removeItem(at: assets.appendingPathComponent(digest))
        let retained = try await session.admitPresentation(.forwardScroll(anchor))
        XCTAssertEqual(retained?.window.items[0].image, initial.window.items[0].image, "Visible projection stays frozen")
        let reopened = FeedSession(publicationHistory: .init(database: database), imageDecoder: .init(assetDirectory: directory.appendingPathComponent("Media"), heroMaxPixel: 300, thumbnailMaxPixel: 88))
        let missing = try await reopened.admitPresentation(.restore(.init(backwardCapacity: 8, forwardCapacity: 16)))
        XCTAssertNil(missing?.window.items[0].image)
        XCTAssertEqual(missing?.window.items[0].mediaAspectRatio, initial.window.items[0].mediaAspectRatio)
        XCTAssertEqual(missing?.window.items[0].id, initial.window.items[0].id)
    }
}
