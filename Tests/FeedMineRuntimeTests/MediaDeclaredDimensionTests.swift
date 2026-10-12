import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
import FeedMineRuntime

/// Kiro K-09 (review E3-11): declared dimensions are hints, measured dimensions decide (MediaResolver header,
/// v1 lesson 03-media). Regression requested by the PO: an image declared 10 px wide whose real bytes are
/// 1200 x 800 becomes the card's hero after measurement instead of being discarded before any byte moves.
final class MediaDeclaredDimensionTests: XCTestCase {
    /// A real 1200 x 800 PNG (1-bit grayscale, 197 bytes): ImageIO reports its true dimensions.
    private let wide = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAABLAAAAMgAQAAAAAbm6avAAAAjElEQVR42u3BMQEAAADCoPVPbQdvoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD4D1+8AARpxgZ8AAAAASUVORK5CYII=")!
    /// A real 2 x 3 PNG: genuinely too small for this device's slots.
    private let tiny = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock(); private var urls: [URL] = []
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
    }

    /// Phone-like slots: 360 pt hero, 100 pt thumbnail at 3x, so the thumbnail minimum is 100 px.
    private static func policy() -> MediaPolicy? {
        guard let c = MediaDeviceConditions(heroSlotPointWidth: 360, thumbnailSlotPointWidth: 100, screenScale: 3,
            network: .unconstrained, measuredBytesPerSecond: nil, waitBudgetSeconds: nil, freeStorageBytes: nil,
            lowPowerMode: false, thermal: .nominal),
            let ceilings = MediaSafetyCeilings(maximumDownloadBytes: 1_000_000, maximumPixelSide: 10_000, maximumPixelCount: 50_000_000)
        else { return nil }
        return MediaPolicy(conditions: c, ceilings: ceilings)
    }

    private func setup() throws -> (RuntimeDatabase, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try RuntimeDatabase(location: .init(directory: root)), root.appendingPathComponent("Media"))
    }

    private func admit(_ db: RuntimeDatabase, url: String, declaredWidth: Int, declaredHeight: Int) throws -> OriginRevisionID {
        let origin = OriginRecordID(), revision = OriginRevisionID(), date = Date(timeIntervalSince1970: 100)
        let media = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: revision, role: .cardVisual,
            mediaClass: .image, remoteURL: URL(string: url)!, declaredMimeType: "image/png",
            declaredPixelWidth: declaredWidth, declaredPixelHeight: declaredHeight))
        try ContentStore(database: db).commitCanonicalChange(.init(recordID: origin, externalObjectIdentity: .init(connectorKind: .syndication,
            namespace: "media", value: UUID().uuidString, role: .object), revision: OriginRevision(id: revision, originRecordID: origin,
            externalVersionIdentity: nil, headline: "H", summary: nil, bodyText: nil, authoredAt: date, modifiedAt: nil, observedAt: date,
            language: nil, primaryLink: nil, searchProjection: nil, providerID: nil), mediaCandidates: [media], availability: .available,
            observedAt: date, expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: date)]))
        return revision
    }

    func testDeclared10pxWithReal1200pxBytesBecomesHero() async throws {
        let (db, assets) = try setup(), calls = Calls(), wide = self.wide
        let revision = try admit(db, url: "https://example.test/mislabeled.png", declaredWidth: 10, declaredHeight: 10)
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { url, _ in calls.add(url); return wide }, conditions: { _ in Self.policy() })
        await prefetcher.prefetch([revision])
        XCTAssertEqual(calls.all.map(\.lastPathComponent), ["mislabeled.png"], "the declared hint must not prevent measuring")
        let ready = try XCTUnwrap(prefetcher.readiness.prepared(revision))
        XCTAssertEqual(ready.fit, .hero)
        guard case .image(_, let layout) = prefetcher.readiness.presentation(for: revision) else { return XCTFail("Expected image") }
        XCTAssertEqual(layout, .hero)
    }

    /// A candidate that really is as small as declared is measured once and settles as designed text-only.
    func testDeclaredTinyThatIsReallyTinySettlesTextOnlyAfterOneMeasurement() async throws {
        let (db, assets) = try setup(), calls = Calls(), tiny = self.tiny
        let revision = try admit(db, url: "https://example.test/tiny.png", declaredWidth: 2, declaredHeight: 3)
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { url, _ in calls.add(url); return tiny }, conditions: { _ in Self.policy() })
        await prefetcher.prefetch([revision])
        await prefetcher.prefetch([revision])
        XCTAssertEqual(calls.all.count, 1)
        XCTAssertNil(prefetcher.readiness.prepared(revision))
        XCTAssertEqual(prefetcher.readiness.presentation(for: revision), .textOnly)
    }
}
