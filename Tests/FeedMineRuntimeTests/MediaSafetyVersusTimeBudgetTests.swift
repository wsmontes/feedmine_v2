import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
@testable import FeedMineRuntime

/// The two questions a media attempt must keep apart, stated as behaviour rather than as a number:
///
/// * **Is this file valid media?** — the safety ceiling (12 MB, 12k px side, 50 MP) refuses definitively.
/// * **Does it fit the time we have?** — the affordable bytes say how much fits the wait. An image above them is
///   attempted anyway; the wait bounds the attempt, and a truncation is transient, never a verdict on the image.
///
/// Owner's product decision: the dynamic budget must not reject the typical image. Before this split, a 3 MB card
/// image was refused `over-ceiling` as definitive because ~500 KB "fit" the measured wait.
final class MediaSafetyVersusTimeBudgetTests: XCTestCase {
    /// A real 2 x 3 PNG padded to the size a typical card image has today (3 MB): a valid image whose bytes far
    /// exceed what a tiny wait affords.
    private let typical = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!
        + Data(repeating: 0, count: 3_000_000)
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!

    /// The terms the attempt ran on, as the transport observed them.
    private final class BudgetProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: MediaByteBudget?
        func record(_ budget: MediaByteBudget) { lock.lock(); seen = budget; lock.unlock() }
        var budget: MediaByteBudget? { lock.lock(); defer { lock.unlock() }; return seen }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [(event: String, fields: [String: String])] = []
        var trace: ReplenishmentTrace { ReplenishmentTrace { [self] event, fields in
            lock.lock(); events.append((event, fields)); lock.unlock()
        } }
        func fields(_ event: String) -> [[String: String]] {
            lock.lock(); defer { lock.unlock() }
            return events.filter { $0.event == event }.map(\.fields)
        }
    }

    /// 1000 B/s for half a second: 500 B fit the wait, while the safety ceilings stay at their production values.
    private static func policy(rate: Double? = 1_000, wait: Double? = 0.5,
        safetyCeiling: Int = 12_000_000) -> MediaPolicy? {
        guard let conditions = MediaDeviceConditions(heroSlotPointWidth: 2, thumbnailSlotPointWidth: 1,
            screenScale: 1, network: .unconstrained, measuredBytesPerSecond: rate, waitBudgetSeconds: wait,
            freeStorageBytes: nil, lowPowerMode: false, thermal: .nominal),
            let ceilings = MediaSafetyCeilings(maximumDownloadBytes: safetyCeiling, maximumPixelSide: 10_000,
                maximumPixelCount: 10_000_000) else { return nil }
        return MediaPolicy(conditions: conditions, ceilings: ceilings)
    }

    /// The transport's contract stated the way `MediaHTTPFetcher` states it: refuse only what the safety ceiling
    /// does not admit, and return everything else whatever the affordable bytes were.
    private func transport(_ body: Data, probe: BudgetProbe? = nil) -> MediaPrefetcher.Fetch {
        { _, budget in
            probe?.record(budget)
            guard !budget.refuses(declaredLength: Int64(body.count)) else {
                throw MediaFetchFailure(.definitive, reason: .overCeiling)
            }
            return body
        }
    }

    private func admit(_ db: RuntimeDatabase, url: String) throws -> OriginRevisionID {
        let origin = OriginRecordID(), revision = OriginRevisionID(), date = Date(timeIntervalSince1970: 100)
        let media = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: revision,
            role: .cardVisual, mediaClass: .image, remoteURL: URL(string: url)!,
            declaredMimeType: nil, declaredPixelWidth: nil, declaredPixelHeight: nil))
        try ContentStore(database: db).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "media",
                value: UUID().uuidString, role: .object),
            revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                headline: "H", summary: nil, bodyText: nil, authoredAt: date, modifiedAt: nil,
                observedAt: date, language: nil, primaryLink: nil, searchProjection: nil, providerID: nil),
            mediaCandidates: [media], availability: .available, observedAt: date,
            expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: date)]))
        return revision
    }

    private func setup() throws -> (RuntimeDatabase, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try RuntimeDatabase(location: .init(directory: root)), root.appendingPathComponent("Media"))
    }

    /// The product failure this split removes: a 3 MB image, ten times what half a second affords, is fetched and
    /// becomes ready. It must never settle as `unavailable` for not fitting the wait.
    func testAnImageAboveTheAffordableBytesIsFetchedAndNeverSettlesUnavailable() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, url: "https://example.test/typical.png")
        let probe = BudgetProbe(), typical = self.typical
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: transport(typical, probe: probe), conditions: { _ in Self.policy() })

        await prefetcher.prefetch([revision])

        let budget = try XCTUnwrap(probe.budget)
        XCTAssertEqual(budget.affordableBytes, 500, "half a second at 1000 B/s fits 500 B")
        XCTAssertEqual(budget.safetyCeilingBytes, 12_000_000, "the transport is bounded by safety, not by the wait")
        XCTAssertFalse(budget.refuses(declaredLength: Int64(typical.count)),
            "3 MB does not fit the wait and is still a valid transfer")
        let ready = try XCTUnwrap(prefetcher.readiness.prepared(revision),
            "an image above the affordable bytes must be prepared, not settled unavailable")
        XCTAssertEqual(ready.fit, .thumbnail)
        XCTAssertNotNil(prefetcher.readiness.presentation(for: revision))
    }

    /// The safety ceiling still protects: 13 MB is refused definitively and settles `unavailable` with its cause.
    func testAnImageOverTheSafetyCeilingIsStillDefinitivelyRefused() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, url: "https://example.test/huge.png")
        let recorder = Recorder(), huge = Data(repeating: 0, count: 13_000_000)
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: transport(huge),
            conditions: { _ in Self.policy(rate: 100_000_000, wait: 10) }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.last?["outcome"], "unavailable")
        XCTAssertEqual(lines.last?["reason"], "over-ceiling")
        XCTAssertTrue(prefetcher.readiness.isSettled(revision))
        XCTAssertNil(prefetcher.readiness.presentation(for: revision),
            "an image over the safety ceiling has no presentation to publish")
    }

    /// A candidate that does not finish inside the wait is cut, and that is a fact about time: the line says
    /// `deadline` (distinct from `over-ceiling`), the revision is not settled, and the next attempt can prepare it.
    func testATimeBudgetTruncationIsTransientWithItsOwnReason() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, url: "https://example.test/slow.png")
        let recorder = Recorder(), calls = Counter(), png = self.png
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in
                // The first attempt never answers inside the wait; the second is fast.
                if calls.next() == 1 { try await Task.sleep(nanoseconds: 5_000_000_000) }
                return png
            },
            conditions: { _ in Self.policy(rate: 1_000, wait: 0.2) }, mediaTrace: recorder.trace)

        let started = ProcessInfo.processInfo.systemUptime
        await prefetcher.prefetch([revision])
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        XCTAssertLessThan(elapsed, 2, "the wait ends the attempt; the transport does not hold it")
        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.last?["outcome"], "transient-failed")
        XCTAssertNotEqual(lines.last?["outcome"], "unavailable")
        XCTAssertEqual(lines.last?["reason"], "deadline", "a time truncation states its own cause")
        XCTAssertNotEqual(lines.last?["reason"], "over-ceiling", "the file was never refused for its size")
        XCTAssertFalse(prefetcher.readiness.isSettled(revision), "running out of wait decides nothing")

        // Eligibility, observed rather than assumed: the same revision goes through the same pipeline again.
        guard case .ready = await prefetcher.prepareForSave(revision) else {
            return XCTFail("a revision cut by the wait must still be preparable later")
        }
    }

    /// A zero wait fits nothing, so nothing is attempted — and that is `deferred`, never an unavailable image.
    func testAZeroWaitDefersWithoutJudgingTheImage() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, url: "https://example.test/card.png")
        let recorder = Recorder()
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in XCTFail("a zero wait affords no attempt"); return Data() },
            conditions: { _ in Self.policy(rate: 1_000, wait: 0) }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.last?["outcome"], "deferred")
        XCTAssertEqual(lines.last?["declared_image"], "true")
        XCTAssertNotEqual(lines.last?["outcome"], "unavailable")
        XCTAssertFalse(prefetcher.readiness.isSettled(revision))
    }
}
