import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
@testable import FeedMineRuntime

/// PD-5/PD-6: definitive decisions permit text-only; pending work never does.
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

    func testAllCandidatesFailingHasNoPresentationAndIsNotRetried() async throws {
        let (db, assets) = try setup(), calls = Calls()
        let revision = try admit(db, urls: ["https://example.test/a.jpg"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { url, _ in calls.add(url); return Data("not an image".utf8) }, conditions: { _ in Self.policy() })
        await prefetcher.prefetchSupplyHead(limit: 10)
        await prefetcher.prefetchSupplyHead(limit: 10)
        XCTAssertEqual(calls.all.count, 1)
        XCTAssertNil(prefetcher.readiness.prepared(revision))
        XCTAssertTrue(prefetcher.readiness.isSettled(revision), "a definitive failure is decided, not pending")
        XCTAssertNil(prefetcher.readiness.presentation(for: revision),
            "the image the card declared is not replaced by a text presentation")
    }

    func testOfflineConditionsFetchNothing() async throws {
        let (db, assets) = try setup(), calls = Calls()
        let revision = try admit(db, urls: ["https://example.test/a.jpg"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { url, _ in calls.add(url); return Data() }, conditions: { _ in Self.policy(network: .unavailable) })
        await prefetcher.prefetchSupplyHead(limit: 10)
        XCTAssertTrue(calls.all.isEmpty)
        XCTAssertNil(prefetcher.readiness.presentation(for: revision), "Offline is pending, not evidence for text-only")
    }
}

extension MediaPrefetcherTests {
    private actor Hold {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var released = false
        func wait() async { if released { return }; await withCheckedContinuation { waiters.append($0) } }
        func release() { released = true; waiters.forEach { $0.resume() }; waiters = [] }
    }
    private final class Clock: @unchecked Sendable { var now = 0.0 }

    /// Review F03: a download that never finishes cannot hold the caller past its deadline.
    func testDeadlineReturnsWhileDownloadStillBlocked() async throws {
        let (db, assets) = try setup(), hold = Hold(), png = self.png
        let revision = try admit(db, urls: ["https://example.test/slow.png"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in await hold.wait(); return png }, conditions: { _ in Self.policy() })
        let started = ProcessInfo.processInfo.systemUptime
        await prefetcher.prefetchSupplyHead(limit: 10, deadline: started + 0.2)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        XCTAssertLessThan(elapsed, 2.0, "prefetch must return near its deadline")
        XCTAssertNil(prefetcher.readiness.prepared(revision))
        XCTAssertNil(prefetcher.readiness.presentation(for: revision), "The deadline ends waiting, not preparation")
        // The owned download keeps going and still helps the next selection.
        await hold.release()
        for _ in 0..<200 where prefetcher.readiness.prepared(revision) == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotNil(prefetcher.readiness.prepared(revision))
    }

    private final class TransportGate: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var afterInvalidation = 0
        private var invalidated = false
        func record() {
            lock.lock(); defer { lock.unlock() }
            count += 1
            if invalidated { afterInvalidation += 1 }
        }
        func invalidate() { lock.lock(); invalidated = true; lock.unlock() }
        var started: Int { lock.lock(); defer { lock.unlock() }; return count }
        var startsAfterInvalidation: Int { lock.lock(); defer { lock.unlock() }; return afterInvalidation }
    }

    /// P01/A2: close happens with more revisions queued than slots. The owner's fence must refuse every queued
    /// start **before** the shared transport is invalidated; a fetch already authorized may still finish.
    func testClosePreventsQueuedMediaFromStartingOnInvalidatedSession() async throws {
        let (db, assets) = try setup(), hold = Hold(), gate = TransportGate(), png = self.png
        let first = try admit(db, urls: ["https://example.test/a.png"])
        let second = try admit(db, urls: ["https://example.test/b.png"])
        let third = try admit(db, urls: ["https://example.test/c.png"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { url, _ in
                gate.record()
                if url.lastPathComponent == "a.png" { await hold.wait() }
                return png
            }, conditions: { _ in Self.policy() })
        let work = Task { await prefetcher.prefetch([first, second, third]) }
        for _ in 0..<400 where gate.started == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(gate.started, 1, "premissa: a primeira revisão está em voo")
        // Real close order: the owner refuses new starts before the transport dies.
        let retired = await prefetcher.retire(budget: .milliseconds(100))
        XCTAssertFalse(retired, "o fetch suspenso não drena dentro do orçamento")
        gate.invalidate()
        await hold.release()
        _ = await work.value
        XCTAssertEqual(gate.startsAfterInvalidation, 0,
            "nenhuma revisão enfileirada pode criar tarefa na sessão invalidada")
        XCTAssertEqual(gate.started, 1)
    }

    /// P01: the budget expiring is a statement of the drain, not permission. After a failed retirement the owner
    /// still denies saved preparation and fresh prefetch calls.
    func testRetirementTimeoutDoesNotAuthorizeLateTransportStarts() async throws {
        let (db, assets) = try setup(), hold = Hold(), gate = TransportGate(), png = self.png
        let first = try admit(db, urls: ["https://example.test/a.png"])
        let queued = try admit(db, urls: ["https://example.test/b.png"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { _, _ in gate.record(); await hold.wait(); return png },
            conditions: { _ in Self.policy() })
        let work = Task { await prefetcher.prefetch([first]) }
        for _ in 0..<400 where gate.started == 0 { try await Task.sleep(nanoseconds: 5_000_000) }
        let retired = await prefetcher.retire(budget: .milliseconds(50))
        XCTAssertFalse(retired)
        let saved = await prefetcher.prepareForSave(queued)
        XCTAssertEqual(saved, .deferred, "a aposentadoria não autoriza preparo novo")
        await prefetcher.prefetch([queued])
        XCTAssertEqual(gate.started, 1, "o timeout da drenagem não reabre o fence")
        await hold.release()
        _ = await work.value
        XCTAssertEqual(gate.started, 1)
    }

    /// Review F04: a timeout is retried after a delay; a definitive failure decides the image is unavailable.
    func testTransientFailureRetriesLaterDefinitiveSettles() async throws {
        let (db, assets) = try setup(), calls = Calls(), clock = Clock(), png = self.png
        final class Mode: @unchecked Sendable { var failure: (any Error)? = URLError(.timedOut) }
        let mode = Mode()
        let revision = try admit(db, urls: ["https://example.test/a.png"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            transientRetryBaseSeconds: 10, monotonicSeconds: { clock.now },
            fetch: { url, _ in calls.add(url); if let failure = mode.failure { throw failure }; return png },
            conditions: { _ in Self.policy() })
        await prefetcher.prefetchSupplyHead(limit: 10)
        XCTAssertEqual(calls.all.count, 1); XCTAssertNil(prefetcher.readiness.prepared(revision))
        XCTAssertNil(prefetcher.readiness.presentation(for: revision), "Transient failure must remain pending")
        clock.now = 5
        await prefetcher.prefetchSupplyHead(limit: 10)
        XCTAssertEqual(calls.all.count, 1, "cooling after a transient failure")
        clock.now = 10; mode.failure = nil
        await prefetcher.prefetchSupplyHead(limit: 10)
        XCTAssertEqual(calls.all.count, 2); XCTAssertNotNil(prefetcher.readiness.prepared(revision))

        let other = try admit(db, urls: ["https://example.test/gone.png"])
        mode.failure = MediaFetchFailure.definitive
        clock.now = 11
        await prefetcher.prefetch([other])
        clock.now = 10_000
        await prefetcher.prefetch([other])
        XCTAssertEqual(calls.all.filter { $0.lastPathComponent == "gone.png" }.count, 1)
        XCTAssertNil(prefetcher.readiness.presentation(for: other),
            "a definitively unavailable image is not published as a text card")
    }
    func testExplicitEditorialRevisionsIgnoreGlobalHeadAndDeduplicate() async throws {
        let (db, assets) = try setup(), calls = Calls(), png = self.png
        let unrelated = try admit(db, urls: ["https://example.test/unrelated.png"])
        let next = try admit(db, urls: ["https://example.test/next.png"])
        let prefetcher = MediaPrefetcher(database: db, assetDirectory: assets, concurrentDownloadLimit: 1,
            fetch: { url, _ in calls.add(url); return png }, conditions: { _ in Self.policy() })
        await prefetcher.prefetch([next, next])
        XCTAssertEqual(calls.all.map(\.lastPathComponent), ["next.png"])
        XCTAssertNotNil(prefetcher.readiness.prepared(next))
        XCTAssertNil(prefetcher.readiness.prepared(unrelated))
    }

    /// The index decides what a nil record **means** from the caller, never from a default. An image the card
    /// declared and that could not be prepared is decided without a presentation; only a card that declares no
    /// image is settled as text. `record` requires the flag, so the old failure mode — a future caller omitting it
    /// and reading as "declared text", publishing `.textOnly` over a broken image — no longer compiles.
    func testANilRecordIsTextOnlyOnlyWhenTheCallerDeclaresText() {
        let index = MediaReadiness(), failed = OriginRevisionID(), designed = OriginRevisionID()
        XCTAssertTrue(index.record(failed, nil, textDeclared: false))
        XCTAssertTrue(index.record(designed, nil, textDeclared: true))
        XCTAssertTrue(index.isSettled(failed)); XCTAssertTrue(index.isSettled(designed))
        XCTAssertNil(index.presentation(for: failed),
            "a recorded image failure has no presentation; it must never become a .textOnly card")
        XCTAssertEqual(index.presentation(for: designed), .textOnly)
        XCTAssertEqual(index.presentations(for: [failed, designed]), [designed: .textOnly],
            "the atomic snapshot agrees with the per-revision answer")
    }

}
