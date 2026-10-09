import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
import FeedMineRuntime

/// PD-5/PD-6: one owner prepares supply media before selection; failures become text-only.
final class MediaPrefetcherTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock(); private var urls: [URL] = []
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
        var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
    }

    private static func policy(network: MediaNetworkPath = .unconstrained) -> MediaPolicy? {
        guard let c = MediaDeviceConditions(heroSlotPointWidth: 2, thumbnailSlotPointWidth: 1, screenScale: 1, network: network,
            measuredBytesPerSecond: nil, waitBudgetSeconds: nil, freeStorageBytes: nil, lowPowerMode: false, thermal: .nominal),
            let ceilings = MediaSafetyCeilings(maximumDownloadBytes: 1_000_000, maximumPixelSide: 10_000, maximumPixelCount: 10_000_000)
        else { return nil }
        return MediaPolicy(conditions: c, ceilings: ceilings)
    }

    private func admit(_ db: RuntimeDatabase, urls: [String]) throws -> OriginRevisionID {
        let origin = OriginRecordID(), revision = OriginRevisionID(), date = Date(timeIntervalSince1970: 100)
        let media = try urls.map { try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: revision, role: .cardVisual,
            mediaClass: .image, remoteURL: URL(string: $0)!, declaredMimeType: nil, declaredPixelWidth: nil, declaredPixelHeight: nil)) }
        try ContentStore(database: db).commitCanonicalChange(.init(recordID: origin, externalObjectIdentity: .init(connectorKind: .syndication,
            namespace: "media", value: UUID().uuidString, role: .object), revision: OriginRevision(id: revision, originRecordID: origin,
            externalVersionIdentity: nil, headline: "H", summary: nil, bodyText: nil, authoredAt: date, modifiedAt: nil, observedAt: date,
            language: nil, primaryLink: nil, searchProjection: nil, providerID: nil), mediaCandidates: media, availability: .available,
            observedAt: date, expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: date)]))
        return revision
    }

    private func setup() throws -> (RuntimeDatabase, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try RuntimeDatabase(location: .init(directory: root)), root.appendingPathComponent("Media"))
    }

    func testPreparesFirstWorkingCandidateAndPresentsItAsImage() async throws {
        let (db, assets) = try setup(), calls = Calls(), png = self.png
        let revision = try admit(db, urls: ["https://example.test/broken.jpg", "https://example.test/good.png"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 2,
            fetch: { url, _ in calls.add(url); if url.lastPathComponent == "broken.jpg" { throw URLError(.badServerResponse) }; return png },
            conditions: { _ in Self.policy() })
        await prefetcher.prefetchSupplyHead(limit: 10)
        XCTAssertEqual(calls.all.map(\.lastPathComponent), ["broken.jpg", "good.png"])
        let ready = try XCTUnwrap(prefetcher.readiness.prepared(revision))
        XCTAssertEqual(ready.fit, .thumbnail) // measured 2x3 is tall → thumbnail
        guard case .image(_, let layout) = prefetcher.readiness.presentation(for: revision) else { return XCTFail("Expected image") }
        XCTAssertEqual(layout, .thumbnail)
        // Settled items are not fetched again.
        await prefetcher.prefetchSupplyHead(limit: 10)
        XCTAssertEqual(calls.all.count, 2)
    }

    func testAllCandidatesFailingIsDesignedTextOnlyAndNotRetried() async throws {
        let (db, assets) = try setup(), calls = Calls()
        let revision = try admit(db, urls: ["https://example.test/a.jpg"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { url, _ in calls.add(url); return Data("not an image".utf8) }, conditions: { _ in Self.policy() })
        await prefetcher.prefetchSupplyHead(limit: 10)
        await prefetcher.prefetchSupplyHead(limit: 10)
        XCTAssertEqual(calls.all.count, 1)
        XCTAssertNil(prefetcher.readiness.prepared(revision))
        XCTAssertEqual(prefetcher.readiness.presentation(for: revision), .textOnly)
    }

    func testOfflineConditionsFetchNothing() async throws {
        let (db, assets) = try setup(), calls = Calls()
        let revision = try admit(db, urls: ["https://example.test/a.jpg"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { url, _ in calls.add(url); return Data() }, conditions: { _ in Self.policy(network: .unavailable) })
        await prefetcher.prefetchSupplyHead(limit: 10)
        XCTAssertTrue(calls.all.isEmpty)
        XCTAssertEqual(prefetcher.readiness.presentation(for: revision), .textOnly)
    }
}
