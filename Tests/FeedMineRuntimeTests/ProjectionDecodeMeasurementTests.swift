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

    /// One real PNG written at the media key's own path, as the pipeline stores it. Returns its digest.
    private func writeLocalAsset(directory: URL) throws -> String {
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
        return digest
    }

    private func localAssetURL(directory: URL, digest: String) -> URL {
        directory.appendingPathComponent("Media/sha256").appendingPathComponent(digest)
    }

    /// The run's own revision, shared by the measurements below.
    private static func measuredEdition() -> PublicationStore.EditionRecord {
        let v = PolicyVersion(rawValue: 1)
        let revision = EditorialRevision(id: EditorialRevisionID(), contextKey: .init(request: .main),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v,
            sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        return PublicationStore.EditionRecord(id: FeedEditionID(), editorialRevision: revision, publicationSchemaVersion: 1,
            selectionSeed: 1, createdAt: Date())
    }

    private static func measuredCard(digest: String) -> PublicationStore.CardRecord {
        PublicationStore.CardRecord(id: PublicationCardID(), originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
            sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil,
            title: "Measured", primaryText: "Local image", timestampValue: nil, timestampKind: nil, mediaKey: "sha256:" + digest,
            mediaPixelWidth: 600, mediaPixelHeight: 400, mediaMimeType: "image/png", renderLayout: "hero", renderMediaAspectRatio: 1.5,
            primaryActionKind: nil, primaryActionReference: nil)
    }

    /// **O custo da restauração larga, medido** (B05, 2026-10-14). Com `keepsAdmittedHead` a reabertura admite a
    /// cabeça da edição; o que ela **não** faz é decodificar um pixel por carta que o leitor já passou: a banda de
    /// residência em volta da posição durável decide os pixels, como na sessão viva. A corrida imprime as duas
    /// leituras no mesmo banco — a limitada (o que o reopen fazia) e a cabeça — para que a diferença de custo seja
    /// o número medido, e não uma afirmação.
    func testKeptHeadRestoreAdmitsTheEditionStartAndDecodesOnlyTheResidencyBand() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let digest = try writeLocalAsset(directory: directory)
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let edition = Self.measuredEdition()
        // A deep reader, the scale B03 reached (811 cards): the durable position stands at the 750th card, so the
        // head the reopen admits is 766 cards long while the residency band stays the bound's 25.
        let durable = 749
        let cards = (0..<800).map { _ in Self.measuredCard(digest: digest) }
        let head = Array(cards[...durable]), tail = Array(cards[(durable + 1)...])
        let store = PublicationStore(database: database)
        try store.createInitialEdition(edition,
            firstSegment: .init(id: FeedSegmentID(), editionID: edition.id, ordinal: 0, segmentSeed: 1,
                publicationSchemaVersion: 1, createdAt: Date(), cardIDs: head.map(\.id)),
            cards: head,
            initialCheckpoint: .init(editionID: edition.id, cardID: cards[durable].id, anchorPlacement: "center",
                updatedAt: Date()))
        try store.appendSegment(.init(id: FeedSegmentID(), editionID: edition.id, ordinal: 1, segmentSeed: 2,
            publicationSchemaVersion: 1, createdAt: Date(), cardIDs: tail.map(\.id)), cards: tail)
        let assets = directory.appendingPathComponent("Media")

        let boundedCounter = Counter()
        let boundedSession = FeedSession(publicationHistory: .init(database: database),
            imageDecoder: .init(assetDirectory: assets, heroMaxPixel: 300, thumbnailMaxPixel: 88,
                onDecode: { boundedCounter.increment() }))
        var boundedStart = ProcessInfo.processInfo.systemUptime
        let boundedValue = try await boundedSession.admitPresentation(
            .restore(.init(backwardCapacity: 8, forwardCapacity: 16)))
        let bounded = try XCTUnwrap(boundedValue)
        let boundedMilliseconds = (ProcessInfo.processInfo.systemUptime - boundedStart) * 1000

        let headCounter = Counter()
        let headSession = FeedSession(publicationHistory: .init(database: database),
            imageDecoder: .init(assetDirectory: assets, heroMaxPixel: 300, thumbnailMaxPixel: 88,
                onDecode: { headCounter.increment() }))
        boundedStart = ProcessInfo.processInfo.systemUptime
        let restoredValue = try await headSession.admitPresentation(
            .restore(.init(backwardCapacity: 8, forwardCapacity: 16, keepsAdmittedHead: true)))
        let restored = try XCTUnwrap(restoredValue)
        let headMilliseconds = (ProcessInfo.processInfo.systemUptime - boundedStart) * 1000
        let band = 8 + 1 + 16
        print("B05 restore cost: bounded cards=\(bounded.window.items.count) decodes=\(boundedCounter.value) "
            + "ms=\(boundedMilliseconds) | head cards=\(restored.window.items.count) decodes=\(headCounter.value) "
            + "ms=\(headMilliseconds) band=\(band)")

        XCTAssertEqual(bounded.window.items.map(\.id), Array(cards[(durable - 8)...(durable + 16)]).map(\.id),
            "a leitura limitada começa oito cartas antes da posição durável")
        XCTAssertEqual(boundedCounter.value, band)
        XCTAssertEqual(restored.window.items.map(\.id), Array(cards[0...(durable + 16)]).map(\.id),
            "a cabeça admite da primeira carta da edição até a reserva à frente da âncora")
        XCTAssertEqual(restored.window.items.first?.id, cards[0].id)
        XCTAssertEqual(restored.window.anchor.cardID, cards[durable].id)
        XCTAssertEqual(headCounter.value, band,
            "só a banda em volta da posição durável decodifica: a cabeça não custa um pixel por carta passada")
        XCTAssertEqual(restored.window.items.filter { $0.image != nil }.count, band,
            "as cartas acima da banda mantêm seus valores congelados com o bitmap liberado")
        XCTAssertTrue(restored.window.items[0].isImageBearing, "a residência nunca redefine o layout publicado")
        XCTAssertEqual(restored.window.items[0].mediaAspectRatio, bounded.window.items.last?.mediaAspectRatio)
    }

    func testRepeatedLocalRefreshMeasuresDecodeWork() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let digest = try writeLocalAsset(directory: directory)
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
        try FileManager.default.removeItem(at: localAssetURL(directory: directory, digest: digest))
        let retained = try await session.admitPresentation(.forwardScroll(anchor))
        XCTAssertEqual(retained?.window.items[0].image, initial.window.items[0].image, "Visible projection stays frozen")
        let reopened = FeedSession(publicationHistory: .init(database: database), imageDecoder: .init(assetDirectory: directory.appendingPathComponent("Media"), heroMaxPixel: 300, thumbnailMaxPixel: 88))
        let missing = try await reopened.admitPresentation(.restore(.init(backwardCapacity: 8, forwardCapacity: 16)))
        // PO 2026-10-17: preserving frozen geometry does not make an undecoded hero render-ready.
        // The caller may decline the restore, or present only cards that really have their final pixels.
        // A hero containing nil decoded pixels must never cross the presentation admission boundary.
        XCTAssertNil(missing, "An undecodable image-bearing card must not be admitted on restore")
        let warm = try FeedSession.warmStart(publicationHistory: .init(database: database),
            imageDecoder: .init(assetDirectory: directory.appendingPathComponent("Media"),
                heroMaxPixel: 300, thumbnailMaxPixel: 88),
            bounds: .init(backwardCapacity: 8, forwardCapacity: 16))
        XCTAssertNil(warm, "Warm-start must enforce the same readiness boundary as ordinary restore")
        let retainedHistory = try PublicationHistory(database: database).window(editionID: edition.id,
            around: .init(cardID: card.id, placement: .center), backwardCapacity: 0, forwardCapacity: 0)
        XCTAssertEqual(retainedHistory.cards.map(\.id), [card.id],
            "Withholding an undecodable presentation must not remove its published history")
        let recoveredDigest = try writeLocalAsset(directory: directory)
        XCTAssertEqual(recoveredDigest, digest)
        let retry = try await reopened.admitPresentation(.restore(.init(backwardCapacity: 8, forwardCapacity: 16)))
        XCTAssertEqual(retry?.window.items.map(\.id), [card.id])
        XCTAssertEqual(retry?.window.items.first?.image?.cgImage.width, 300,
            "The same preserved card becomes admissible once its exact local asset is available")
    }

    /// One frozen hero is already on screen. A later published hero loses its disk asset before
    /// projection: neither publication growth nor a forward admission may expose its placeholder.
    /// Once the same bytes return, both independent admission paths must reach it without reordering.
    func testGrowthAndForwardScrollWithholdUndecodableHeroUntilLocalAssetReturns() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let digest = try writeLocalAsset(directory: directory)
        let assetURL = localAssetURL(directory: directory, digest: digest)
        let savedBytes = try Data(contentsOf: assetURL)
        let database = try RuntimeDatabase(location: .init(directory: directory))
        let edition = Self.measuredEdition()
        let first = Self.measuredCard(digest: digest)
        let next = Self.measuredCard(digest: digest)
        let store = PublicationStore(database: database)
        try store.createInitialEdition(edition, firstSegment: .init(
            id: FeedSegmentID(), editionID: edition.id, ordinal: 0, segmentSeed: 1,
            publicationSchemaVersion: 1, createdAt: Date(), cardIDs: [first.id]),
            cards: [first], initialCheckpoint: .init(editionID: edition.id,
                cardID: first.id, anchorPlacement: "top", updatedAt: Date()))
        let history = PublicationHistory(database: database)
        let decoder = PresentationImageDecoder(assetDirectory: directory.appendingPathComponent("Media"),
            heroMaxPixel: 300, thumbnailMaxPixel: 88)
        let growth = FeedSession(publicationHistory: history, imageDecoder: decoder)
        let forward = FeedSession(publicationHistory: history, imageDecoder: decoder)
        let bounds = FeedPresentationBounds(backwardCapacity: 0, forwardCapacity: 2)
        let beforeGrowth = try XCTUnwrap(try await growth.admitPresentation(.initial(bounds)))
        let beforeForward = try XCTUnwrap(try await forward.admitPresentation(.initial(bounds)))
        XCTAssertEqual(beforeGrowth.window.items.map(\.id), [first.id])
        XCTAssertEqual(beforeForward.window.items.first?.image?.cgImage.width, 300)

        try FileManager.default.removeItem(at: assetURL)
        try store.appendSegment(.init(id: FeedSegmentID(), editionID: edition.id,
            ordinal: 1, segmentSeed: 2, publicationSchemaVersion: 1,
            createdAt: Date(), cardIDs: [next.id]), cards: [next])

        let afterGrowth = try await growth.admitPresentation(.publishedGrowth)
        let observed = ViewportObservation(anchor: beforeForward.window.anchor)
        _ = try await forward.submitViewport(observed)
        let afterForward = try await forward.admitPresentation(.forwardScroll(observed))
        for attempt in [afterGrowth, afterForward] {
            XCTAssertEqual(attempt?.window.items.map(\.id), [first.id],
                "A missing hero must not enter the admitted list or displace the ready prefix")
            XCTAssertEqual(attempt?.window.items.first?.image?.cgImage.width, 300,
                "An already-admitted hero must retain its pixels despite eviction of disk bytes")
        }
        // Publication is immutable; a failed visual admission must not mutate published order.
        let published = try history.window(editionID: edition.id,
            around: .init(cardID: first.id, placement: .center),
            backwardCapacity: 0, forwardCapacity: 2)
        XCTAssertEqual(published.cards.map(\.id), [first.id, next.id])

        try savedBytes.write(to: assetURL)
        let recoveredGrowth = try await growth.admitPresentation(.publishedGrowth)
        let recoveredForward = try await forward.admitPresentation(.forwardScroll(observed))
        for recovered in [recoveredGrowth, recoveredForward] {
            XCTAssertEqual(recovered?.window.items.map(\.id), [first.id, next.id])
            XCTAssertTrue(recovered?.window.items.allSatisfy { !$0.isImageBearing || $0.image != nil } ?? false,
                "Only render-ready values may cross admission")
        }
    }
}
