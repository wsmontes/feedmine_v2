import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
@testable import FeedMineRuntime

/// The media-preparation path's evidence: one settlement line per revision it considers for publication, with
/// the outcome the path actually reached. The transient case is the one that must never read as `unavailable`.
final class MediaPreparationTraceTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Double
        init(_ value: Double) { self.value = value }
        var now: Double {
            get { lock.lock(); defer { lock.unlock() }; return value }
            set { lock.lock(); value = newValue; lock.unlock() }
        }
    }

    private final class TraceRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [(event: String, fields: [String: String])] = []

        var trace: ReplenishmentTrace { ReplenishmentTrace { [self] event, fields in record(event, fields) } }

        func record(_ event: String, _ fields: [String: String]) {
            lock.lock(); defer { lock.unlock() }
            storage.append((event, fields))
        }
        func fields(_ event: String) -> [[String: String]] {
            lock.lock(); defer { lock.unlock() }
            return storage.filter { $0.event == event }.map(\.fields)
        }
        var count: Int { lock.lock(); defer { lock.unlock() }; return storage.count }
    }

    private final class FetchProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var seenCeiling: Int?
        private var budgetLines = 0

        func observe(ceiling: Int, budgetLines: Int) {
            lock.lock(); seenCeiling = ceiling; self.budgetLines = budgetLines; lock.unlock()
        }
        var ceiling: Int? { lock.lock(); defer { lock.unlock() }; return seenCeiling }
        var linesBeforeFetch: Int { lock.lock(); defer { lock.unlock() }; return budgetLines }
    }

    private static func policy(hero: Double = 2, thumbnail: Double = 1,
        rate: Double? = nil, wait: Double? = nil) -> MediaPolicy? {
        guard let conditions = MediaDeviceConditions(heroSlotPointWidth: hero, thumbnailSlotPointWidth: thumbnail,
            screenScale: 1, network: .unconstrained, measuredBytesPerSecond: rate, waitBudgetSeconds: wait,
            freeStorageBytes: nil, lowPowerMode: false, thermal: .nominal),
            let ceilings = MediaSafetyCeilings(maximumDownloadBytes: 1_000_000,
                maximumPixelSide: 10_000, maximumPixelCount: 10_000_000) else { return nil }
        return MediaPolicy(conditions: conditions, ceilings: ceilings)
    }

    /// A revision with the card visuals the feed declared and one direct membership, so the trace states both
    /// the declaration and the source it belongs to.
    private func admit(_ db: RuntimeDatabase, images: [String], source: SourceID) throws -> OriginRevisionID {
        let origin = OriginRecordID(), revision = OriginRevisionID(), date = Date(timeIntervalSince1970: 100)
        let media = try images.map { url in
            try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: revision,
                role: .cardVisual, mediaClass: .image, remoteURL: URL(string: url)!,
                declaredMimeType: nil, declaredPixelWidth: nil, declaredPixelHeight: nil))
        }
        try ContentStore(database: db).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "media",
                value: UUID().uuidString, role: .object),
            revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                headline: "H", summary: nil, bodyText: nil, authoredAt: date, modifiedAt: nil,
                observedAt: date, language: nil, primaryLink: nil, searchProjection: nil, providerID: nil),
            mediaCandidates: media, availability: .available, observedAt: date,
            expectedCurrent: .none, currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: source, kind: .direct, observedAt: date)]))
        return revision
    }

    private func setup() throws -> (RuntimeDatabase, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try RuntimeDatabase(location: .init(directory: root)), root.appendingPathComponent("Media"))
    }

    func testReadyImageIsOneLineWithSourceDeclarationOutcomeAndElapsed() async throws {
        let (db, assets) = try setup()
        let source = SourceID()
        let revision = try admit(db, images: ["https://example.test/card.png"], source: source)
        let clock = Clock(100), recorder = TraceRecorder(), png = self.png
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            monotonicSeconds: { clock.now },
            fetch: { _, _ in clock.now = 102.5; return png },
            conditions: { _ in Self.policy() }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        XCTAssertNotNil(prefetcher.readiness.prepared(revision))
        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.count, 1, "one settlement line for one considered revision")
        XCTAssertEqual(lines[0]["revision"], revision.rawValue.uuidString)
        XCTAssertEqual(lines[0]["source"], source.rawValue.uuidString)
        XCTAssertEqual(lines[0]["declared_image"], "true")
        XCTAssertEqual(lines[0]["outcome"], "ready-image")
        XCTAssertEqual(lines[0]["elapsed_ms"], "2500", "elapsed is measured from first consideration")
        XCTAssertNil(lines[0]["reason"], "a ready image states no failure cause")
        XCTAssertEqual(recorder.fields(ReplenishmentEvent.mediaSettled).count, 1,
            "the settlement is stated once")
        XCTAssertEqual(recorder.fields(ReplenishmentEvent.mediaByteBudget).count, 1,
            "the ceiling that bounded the fetch is stated once before it starts")
    }

    /// A timeout is network trouble, not a verdict on the image: the line says `transient-failed` and the
    /// revision stays pending. Reporting `unavailable` here would retire a story for the whole run.
    func testTransientFailureIsReportedAsTransientAndNeverAsUnavailable() async throws {
        let (db, assets) = try setup()
        let source = SourceID()
        let revision = try admit(db, images: ["https://example.test/card.png"], source: source)
        let recorder = TraceRecorder()
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            transientRetryBaseSeconds: 10,
            fetch: { _, _ in throw URLError(.timedOut) },
            conditions: { _ in Self.policy() }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["revision"], revision.rawValue.uuidString)
        XCTAssertEqual(lines[0]["declared_image"], "true")
        XCTAssertEqual(lines[0]["outcome"], "transient-failed")
        XCTAssertNotEqual(lines[0]["outcome"], "unavailable")
        XCTAssertFalse(prefetcher.readiness.isSettled(revision), "a transient failure decides nothing")
        XCTAssertNil(prefetcher.readiness.presentation(for: revision))
    }

    func testAFeedThatDeclaresNoCardImageSettlesAsTextOnly() async throws {
        let (db, assets) = try setup()
        let source = SourceID()
        let revision = try admit(db, images: [], source: source)
        let recorder = TraceRecorder()
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in XCTFail("no declared image means nothing to fetch"); return Data() },
            conditions: { _ in Self.policy() }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["declared_image"], "false")
        XCTAssertEqual(lines[0]["outcome"], "text-only")
        XCTAssertNil(lines[0]["reason"], "text as designed is not a failure")
        XCTAssertEqual(prefetcher.readiness.presentation(for: revision), .textOnly)
    }

    func testDeclaredImageThatCannotBePreparedSettlesAsUnavailable() async throws {
        let (db, assets) = try setup()
        let source = SourceID()
        let revision = try admit(db, images: ["https://example.test/gone.png"], source: source)
        let recorder = TraceRecorder()
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in throw MediaFetchFailure.definitive },
            conditions: { _ in Self.policy() }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["declared_image"], "true")
        XCTAssertEqual(lines[0]["outcome"], "unavailable")
        XCTAssertEqual(lines[0]["reason"], "unknown",
            "a caller that states only the classification cannot invent a cause")
        XCTAssertTrue(prefetcher.readiness.isSettled(revision))
        XCTAssertNil(prefetcher.readiness.presentation(for: revision),
            "an unavailable declared image has no text fallback")
    }

    func testConditionsUnknownEndsTheAttemptAsDeferredWithoutSettling() async throws {
        let (db, assets) = try setup()
        let source = SourceID()
        let revision = try admit(db, images: ["https://example.test/card.png"], source: source)
        let recorder = TraceRecorder()
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in XCTFail("unknown conditions forbid remote work"); return Data() },
            conditions: { _ in nil }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["outcome"], "deferred")
        XCTAssertEqual(lines[0]["declared_image"], "true")
        XCTAssertNil(lines[0]["reason"], "a deferred attempt decides nothing")
        XCTAssertFalse(prefetcher.readiness.isSettled(revision))
    }

    /// One line per revision, never one per candidate and never two for the same revision: the first working
    /// candidate settles the revision and later prefetch calls are offered no work.
    func testEveryConsideredRevisionGetsExactlyOneLine() async throws {
        let (db, assets) = try setup()
        let image = try admit(db, images: ["https://example.test/broken.jpg",
            "https://example.test/good.png"], source: SourceID())
        let text = try admit(db, images: [], source: SourceID())
        let recorder = TraceRecorder(), png = self.png
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 2,
            fetch: { url, _ in
                if url.lastPathComponent == "broken.jpg" { throw URLError(.badServerResponse) }
                return png
            },
            conditions: { _ in Self.policy() }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([image, text])
        await prefetcher.prefetch([image, text])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.count, 2, "one line for each considered revision")
        let byRevision = Dictionary(uniqueKeysWithValues: lines.map { ($0["revision"] ?? "", $0) })
        XCTAssertEqual(Set(byRevision.keys), [image.rawValue.uuidString, text.rawValue.uuidString])
        XCTAssertEqual(byRevision[image.rawValue.uuidString]?["outcome"], "ready-image")
        XCTAssertEqual(byRevision[text.rawValue.uuidString]?["outcome"], "text-only")
    }

    func testNoTraceWritesNothing() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, images: [], source: SourceID())
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in Data() }, conditions: { _ in Self.policy() })
        await prefetcher.prefetch([revision])
        XCTAssertEqual(prefetcher.readiness.presentation(for: revision), .textOnly,
            "the behavior without a trace is the behavior the module had before")
    }

    /// A definitive end states its cause: an image refused over the byte ceiling is not the same fact as a 404 or
    /// a tiny image, and only the cause lets a run tell them apart.
    func testOverCeilingFetchStatesItsReason() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, images: ["https://example.test/huge.png"], source: SourceID())
        let recorder = TraceRecorder()
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in throw MediaFetchFailure(.definitive, reason: .overCeiling) },
            conditions: { _ in Self.policy() }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["outcome"], "unavailable")
        XCTAssertEqual(lines[0]["reason"], "over-ceiling")
    }

    /// Measured pixels below the slot minimum are their own cause, distinct from any fetch failure.
    func testTooSmallMeasurementStatesItsReason() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, images: ["https://example.test/tiny.png"], source: SourceID())
        let recorder = TraceRecorder(), png = self.png
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in png },
            conditions: { _ in Self.policy(hero: 40, thumbnail: 40) }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["outcome"], "unavailable")
        XCTAssertEqual(lines[0]["reason"], "too-small")
        XCTAssertNil(prefetcher.readiness.presentation(for: revision))
    }

    /// A timeout is retried, so it must never read as a definitive cause: the outcome is `transient-failed` and
    /// the cause is the timeout itself.
    func testTransientTimeoutIsNotReportedAsADefinitiveReason() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, images: ["https://example.test/slow.png"], source: SourceID())
        let recorder = TraceRecorder()
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            transientRetryBaseSeconds: 10,
            fetch: { _, _ in throw URLError(.timedOut) },
            conditions: { _ in Self.policy() }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaSettled)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["outcome"], "transient-failed")
        XCTAssertEqual(lines[0]["reason"], "timeout")
        XCTAssertNotEqual(lines[0]["outcome"], "unavailable")
        XCTAssertFalse(prefetcher.readiness.isSettled(revision), "a timeout decides nothing")
    }

    /// The ceiling is not a constant: with a measured rate and a wait it is their product. The line is written
    /// before the fetch and carries exactly the number the fetch was handed.
    func testByteBudgetLineCarriesTheMeasuredProductBeforeTheFetch() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, images: ["https://example.test/card.png"], source: SourceID())
        let recorder = TraceRecorder(), png = self.png, probe = FetchProbe()
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, ceiling in
                probe.observe(ceiling: ceiling,
                    budgetLines: recorder.fields(ReplenishmentEvent.mediaByteBudget).count)
                return png
            },
            conditions: { _ in Self.policy(rate: 1_000, wait: 2) }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaByteBudget)
        XCTAssertEqual(lines.count, 1, "one budget line per attempt")
        XCTAssertEqual(lines[0]["revision"], revision.rawValue.uuidString)
        XCTAssertEqual(lines[0]["ceiling"], "2000")
        XCTAssertEqual(lines[0]["source"], "dynamic")
        XCTAssertEqual(lines[0]["rate_bps"], "1000.0")
        XCTAssertEqual(lines[0]["wait_seconds"], "2.0")
        XCTAssertEqual(lines[0]["cap"], "1000000")
        XCTAssertEqual(probe.linesBeforeFetch, 1, "the line exists before the fetch starts")
        XCTAssertEqual(probe.ceiling, 2_000, "the traced ceiling is the one the fetch was handed")
    }

    /// Without a measured rate the budget is the safety cap itself, and the line states that provenance.
    func testByteBudgetLineStatesTheCapWhenNothingWasMeasured() async throws {
        let (db, assets) = try setup()
        let revision = try admit(db, images: ["https://example.test/card.png"], source: SourceID())
        let recorder = TraceRecorder(), png = self.png
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in png },
            conditions: { _ in Self.policy() }, mediaTrace: recorder.trace)

        await prefetcher.prefetch([revision])

        let lines = recorder.fields(ReplenishmentEvent.mediaByteBudget)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["ceiling"], "1000000")
        XCTAssertEqual(lines[0]["source"], "ceiling-cap")
        XCTAssertEqual(lines[0]["rate_bps"], "none")
        XCTAssertEqual(lines[0]["wait_seconds"], "none")
        XCTAssertEqual(lines[0]["cap"], "1000000")
    }
}
