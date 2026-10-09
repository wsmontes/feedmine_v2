import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
import FeedMineRuntime

final class MediaTidyFactsTests: XCTestCase {
    func testDiskPressureUsesReadingFactsAndRetainsBookmarkAndWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try RuntimeDatabase(location: .init(directory: root))
        let directory = root.appendingPathComponent("Media"), materializer = ImageMaterializer(assetDirectory: directory)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
        let assets = try (0..<5).map { try materializer.materialize(png + Data([UInt8($0)])) }
        let cards = assets.map { asset in
            PublicationStore.CardRecord(id: PublicationCardID(), originRecordID: OriginRecordID(), originRevisionID: OriginRevisionID(),
                sourceID: nil, providerID: nil, sourceDisplayName: nil, providerDisplayName: nil, contentEntityID: nil, contentClusterID: nil,
                title: "Card", primaryText: nil, timestampValue: nil, timestampKind: nil, mediaKey: asset.key.rawValue,
                mediaPixelWidth: 2, mediaPixelHeight: 3, mediaMimeType: "image/png", renderLayout: "hero", renderMediaAspectRatio: 2.0 / 3,
                primaryActionKind: nil, primaryActionReference: nil)
        }
        let v = PolicyVersion(rawValue: 1), revision = EditorialRevision(id: EditorialRevisionID(), contextKey: .init(request: .main),
            catalogGeneration: .init(rawValue: 1), userSelectionVersion: v, eligibilityPolicyVersion: v, scoringPolicyVersion: v,
            sequencingPolicyVersion: v, exposurePolicyVersion: v, selectionSchemaVersion: .init(rawValue: 1))
        let edition = PublicationStore.EditionRecord(id: FeedEditionID(), editorialRevision: revision, publicationSchemaVersion: 1, selectionSeed: 1, createdAt: Date())
        let store = PublicationStore(database: database)
        try store.createEdition(edition, firstSegment: .init(id: FeedSegmentID(), editionID: edition.id, ordinal: 0, segmentSeed: 1,
            publicationSchemaVersion: 1, createdAt: Date(), cardIDs: cards.map(\.id)), cards: cards)
        let now = Date(timeIntervalSince1970: 2_000_000)
        try store.markSeen(editionID: edition.id, cardID: cards[0].id, at: now.addingTimeInterval(-14 * 86_400))
        try store.markSeen(editionID: edition.id, cardID: cards[1].id, at: now)
        try store.toggleBookmark(cardID: cards[3].id, at: now)
        let facts = try store.mediaUsage()
        XCTAssertLessThan(try XCTUnwrap(facts[assets[0].key.rawValue]?.lastSeenAt), now.addingTimeInterval(-7 * 86_400))
        XCTAssertEqual(facts[assets[1].key.rawValue]?.lastSeenAt, now)
        XCTAssertNil(facts[assets[2].key.rawValue]?.lastSeenAt)
        let prefetcher = MediaPrefetcher(database: database, assetDirectory: directory, readiness: MediaReadiness(),
            concurrentDownloadLimit: 1, fetch: { _, _ in XCTFail("No supply may download"); return Data() }, conditions: { _ in nil })
        let tidy = MediaTidy(assetDirectory: directory, prefetcher: prefetcher, freeStorageBytes: { 0 },
            usage: { try store.mediaUsage() }, now: { now })
        let report = await tidy.run(visibleKeys: [assets[4].key.rawValue], supplyHeadLimit: 1, deadline: nil)
        XCTAssertEqual(report.evictedAssets, 3)
        XCTAssertEqual(Set(MediaHousekeeping(assetDirectory: directory).inventory().map(\.key)), [assets[3].key, assets[4].key])
        XCTAssertEqual(try store.bookmarkedCardIDs(), [cards[3].id])
        XCTAssertEqual(try store.segments(editionID: edition.id).flatMap(\.cardIDs), cards.map(\.id))
    }
}
