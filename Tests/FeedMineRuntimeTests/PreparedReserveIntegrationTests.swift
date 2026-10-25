import Foundation
import XCTest
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
@testable import FeedMineRuntime

/// PM-028A §5: the three discriminants the PM named, driven through the **real** `MediaPrefetcher`, the real asset
/// store and the existing durable deferral rows. The transport is a continuation-controlled stub: nothing here
/// sleeps, polls or measures wall-clock time, so a slow image is slow because the test has not opened its transport
/// call yet — not because some interval elapsed.
final class PreparedReserveIntegrationTests: XCTestCase {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==")!

    /// The transport: a call for a held path suspends until the test opens it. Everything else answers at once.
    /// An actor, not a lock: the suspension is the actor's own, so no lock is taken across a suspension point.
    private actor Transport {
        private var calls: [String] = []
        private var opened: Set<String> = []
        private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
        private let holds: Set<String>
        private let png: Data

        init(holds: Set<String> = [], png: Data) {
            self.holds = holds
            self.png = png
        }

        var calledPaths: [String] { calls }

        func fetch(_ url: URL) async throws -> Data {
            let name = url.lastPathComponent
            calls.append(name)
            if holds.contains(name), !opened.contains(name) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    waiters[name, default: []].append(continuation)
                }
            }
            return name == "broken.jpg" ? Data("not an image".utf8) : png
        }

        /// The image the held call was waiting for has now arrived: the fetch continues where it stopped.
        func open(_ name: String) {
            opened.insert(name)
            let pending = waiters.removeValue(forKey: name) ?? []
            for continuation in pending { continuation.resume() }
        }
    }

    private static func policy() -> MediaPolicy? {
        guard let conditions = MediaDeviceConditions(heroSlotPointWidth: 2, thumbnailSlotPointWidth: 1,
            screenScale: 1, network: .unconstrained, measuredBytesPerSecond: nil, waitBudgetSeconds: nil,
            freeStorageBytes: nil, lowPowerMode: false, thermal: .nominal),
            let ceilings = MediaSafetyCeilings(maximumDownloadBytes: 1_000_000, maximumPixelSide: 10_000,
                maximumPixelCount: 10_000_000)
        else { return nil }
        return MediaPolicy(conditions: conditions, ceilings: ceilings)
    }

    private func setup() throws -> (RuntimeDatabase, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try RuntimeDatabase(location: .init(directory: root)), root.appendingPathComponent("Media"))
    }

    @discardableResult
    private func admit(_ db: RuntimeDatabase, urls: [String]) throws -> (OriginRecordID, OriginRevisionID) {
        let origin = OriginRecordID(), revision = OriginRevisionID(), date = Date(timeIntervalSince1970: 100)
        let media = try urls.map { url in
            try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: revision, role: .cardVisual,
                mediaClass: .image, remoteURL: URL(string: url)!, declaredMimeType: nil, declaredPixelWidth: nil,
                declaredPixelHeight: nil))
        }
        try ContentStore(database: db).commitCanonicalChange(.init(recordID: origin,
            externalObjectIdentity: .init(connectorKind: .syndication, namespace: "media",
                value: UUID().uuidString, role: .object),
            revision: OriginRevision(id: revision, originRecordID: origin, externalVersionIdentity: nil,
                headline: "H", summary: nil, bodyText: nil, authoredAt: date, modifiedAt: nil, observedAt: date,
                language: nil, primaryLink: nil, searchProjection: nil, providerID: nil),
            mediaCandidates: media, availability: .available, observedAt: date, expectedCurrent: .none,
            currentUpdate: .useSuppliedRevision,
            membershipMutations: [.upsert(sourceID: SourceID(), kind: .direct, observedAt: date)]))
        return (origin, revision)
    }

    /// The one rule the app wires from a readiness transition to the reserve: a presentation is `.prepared`, and a
    /// revision whose **declared** image was decided with no presentation at all is `.definitiveFailure` — the card
    /// that cannot become what the feed declared, not a text card in its place (INV-17).
    private static func settleFromReadiness(_ revision: OriginRevisionID, readiness: MediaReadiness,
        reserve: PreparedReserve) async {
        let prepared = readiness.prepared(revision)
        if prepared == nil, readiness.isSettled(revision), readiness.presentation(for: revision) == nil {
            await reserve.settle(revision, outcome: .definitiveFailure)
        } else {
            await reserve.settle(revision, outcome: .prepared(hasImage: prepared != nil),
                persistedBytes: prepared?.byteCount ?? 0)
        }
    }

    private func prefetcher(_ db: RuntimeDatabase, assets: URL, transport: Transport, readiness: MediaReadiness,
        reserve: PreparedReserve,
        onTransition: (@Sendable (OriginRevisionID) async -> Void)? = nil) -> MediaPrefetcher {
        MediaPrefetcher(database: db, assetDirectory: assets, readiness: readiness, concurrentDownloadLimit: 2,
            fetch: { url, _ in try await transport.fetch(url) },
            conditions: { _ in Self.policy() },
            onReadinessChanged: { revision in
                await Self.settleFromReadiness(revision, readiness: readiness, reserve: reserve)
                await onTransition?(revision)
            })
    }

    /// One opportunity exactly as the app runs it: plan over the same revisions the slice will offer, record the
    /// attempts, hand them to the prefetcher under the slice's deadline, and close the window when it returns. The
    /// returned list is what this opportunity actually charged to the pipeline.
    @discardableResult
    private func opportunity(_ reserve: PreparedReserve, _ prefetcher: MediaPrefetcher,
        offer: [OriginRevisionID], deadline: Double) async -> [OriginRevisionID] {
        let planned = await reserve.plan(offer: offer)
        for revision in planned { await reserve.markPreparing(revision, attempt: 0) }
        await prefetcher.prefetch(planned, deadline: deadline)
        await reserve.windowClosed(planned)
        return planned
    }

    /// Discriminant 1: the fetch finishes inside the opportunity's own deadline. The prefetcher returns with the
    /// revision ready, the reserve does not offer it again, and an immediate selection has a presentation for it.
    func testFastImageIsPreparedInsideTheWindowAndSelectedAtOnce() async throws {
        let (db, assets) = try setup()
        let (_, revision) = try admit(db, urls: ["https://example.test/fast.png"])
        let readiness = MediaReadiness()
        let reserve = PreparedReserve(targetDepth: 8, lowWaterMark: 4)
        let transport = Transport(png: png)
        let media = prefetcher(db, assets: assets, transport: transport, readiness: readiness, reserve: reserve)

        let planned = await opportunity(reserve, media, offer: [revision],
            deadline: ProcessInfo.processInfo.systemUptime + 30)
        XCTAssertEqual(planned, [revision])

        let prepared = try XCTUnwrap(readiness.prepared(revision), "the fetch was inside the deadline")
        XCTAssertEqual(prepared.byteCount, png.count, "the reserve is told the asset's own persisted size")
        let phase = await reserve.phase(of: revision)
        XCTAssertEqual(phase, .ready(hasImage: true))
        var snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.ready, 1)
        XCTAssertEqual(snapshot.preparing, 0)
        XCTAssertEqual(snapshot.lateCompletions, 0, "a completion inside its window is not late")
        XCTAssertEqual(snapshot.persistedBytes, png.count)

        // An immediate selection includes it: the presentation the selection reads exists.
        let presentations = readiness.presentations(for: [revision])
        XCTAssertNotNil(presentations[revision])

        // The reserve does not hand it back to the pipeline, and the prefetcher does not fetch it twice.
        let reoffered = await reserve.plan(offer: [revision])
        XCTAssertEqual(reoffered, [])
        await media.prefetch([revision])
        let fastCalls = await transport.calledPaths
        XCTAssertEqual(fastCalls, ["fast.png"])
    }

    /// Discriminant 2: the fetch finishes **after** the opportunity's deadline. The prefetcher has already returned;
    /// when the bytes arrive the reserve takes them, counts the completion as late, and the story the durable
    /// deferral row remembers is offered to the next selection — the existing re-offer path, not a second one.
    func testSlowImageCompletesAfterTheDeadlineAndJoinsTheNextOffer() async throws {
        let (db, assets) = try setup()
        let (origin, revision) = try admit(db, urls: ["https://example.test/slow.png"])
        let edition = FeedEditionID()
        // The durable memory the walk already keeps: this story was skipped while its media was pending.
        let deferrals = PendingMediaReconsideration(database: db, ceiling: 128)
        try deferrals.remember([.init(editionID: edition, originRecordID: origin, originRevisionID: revision)])

        let readiness = MediaReadiness()
        let reserve = PreparedReserve(targetDepth: 8, lowWaterMark: 4)
        let transport = Transport(holds: ["slow.png"], png: png)
        let settled = expectation(description: "the late completion reached the reserve")
        let media = prefetcher(db, assets: assets, transport: transport, readiness: readiness, reserve: reserve,
            onTransition: { _ in settled.fulfill() })

        // The throttled deadline: the opportunity's wait is already over when it starts, so `prefetch` returns
        // while the download it authorized is still running.
        let planned = await opportunity(reserve, media, offer: [revision],
            deadline: ProcessInfo.processInfo.systemUptime)
        XCTAssertEqual(planned, [revision])
        XCTAssertNil(readiness.prepared(revision), "the deadline ended the wait, not the preparation")
        var snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.preparing, 0, "the window closed, so nothing is in flight from its point of view")
        XCTAssertEqual(snapshot.deferred, 1)
        // While it is pending, the re-offer path leaves it queued: `MediaSkippedSupply.reconsider` only offers a
        // queued revision that already has a presentation.
        let queued = try deferrals.pendingEntries(for: edition, limit: deferrals.ceiling)
        XCTAssertEqual(queued.map(\.originRevisionID), [revision])
        XCTAssertTrue(readiness.presentations(for: queued.map(\.originRevisionID)).isEmpty,
            "still pending: nothing to offer yet")

        // The bytes arrive after the window.
        await transport.open("slow.png")
        await fulfillment(of: [settled], timeout: 10)

        snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.ready, 1, "the late completion is taken as a presentation")
        XCTAssertEqual(snapshot.lateCompletions, 1, "it arrived after the slice's deadline")
        XCTAssertEqual(snapshot.persistedBytes, png.count)
        let phase = await reserve.phase(of: revision)
        XCTAssertEqual(phase, .ready(hasImage: true))
        // The next slice offers it, by the existing rule and by the reserve's own accounting.
        let offered = readiness.presentations(for: queued.map(\.originRevisionID))
        XCTAssertNotNil(offered[revision], "the re-offer path now has a presentation to offer")
        let reoffered = await reserve.plan(offer: [revision])
        XCTAssertEqual(reoffered, [], "it is prepared, so it is not fetched again")
        await media.prefetch([revision])
        let slowCalls = await transport.calledPaths
        XCTAssertEqual(slowCalls, ["slow.png"], "one download, never a second one")
    }

    /// Discriminant 3: a declared image that cannot be prepared exhausts on its first answer, the rest of the same
    /// offer proceeds, and the card carries no declared image (the existing INV-17 behaviour, preserved).
    func testUnavailableImageExhaustsWithoutBlockingTheRestOfTheOffer() async throws {
        let (db, assets) = try setup()
        let (_, broken) = try admit(db, urls: ["https://example.test/broken.jpg"])
        let (_, healthy) = try admit(db, urls: ["https://example.test/healthy.png"])
        let readiness = MediaReadiness()
        let reserve = PreparedReserve(targetDepth: 8, lowWaterMark: 4)
        let transport = Transport(png: png)
        let both = expectation(description: "both revisions were decided")
        both.expectedFulfillmentCount = 2
        let media = prefetcher(db, assets: assets, transport: transport, readiness: readiness, reserve: reserve,
            onTransition: { _ in both.fulfill() })

        let planned = await opportunity(reserve, media, offer: [broken, healthy],
            deadline: ProcessInfo.processInfo.systemUptime + 30)
        XCTAssertEqual(planned, [broken, healthy])
        await fulfillment(of: [both], timeout: 10)

        let brokenPhase = await reserve.phase(of: broken)
        XCTAssertEqual(brokenPhase, .exhausted(.mediaInvalid), "the first definitive answer is final")
        let healthyPhase = await reserve.phase(of: healthy)
        XCTAssertEqual(healthyPhase, .ready(hasImage: true), "the rest of the offer was not blocked")
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.exhausted, 1)
        XCTAssertEqual(snapshot.ready, 1)
        XCTAssertNil(readiness.presentation(for: broken),
            "a declared image is never published as the text card it is not")
        XCTAssertNotNil(readiness.presentation(for: healthy))
        let reoffered = await reserve.plan(offer: [broken, healthy])
        XCTAssertEqual(reoffered, [], "neither an exhausted nor a ready revision is charged again")
        let calls = await transport.calledPaths
        XCTAssertEqual(calls.sorted(), ["broken.jpg", "healthy.png"])
    }

    /// PM-028A §3/§4: the depth is a real bound on the pipeline, and it is applied to the very set the slice is
    /// about to offer — the structural window plus the deferral page the driver prepares.
    func testReserveDepthBoundsWhatThePipelineIsCharged() async throws {
        let (db, assets) = try setup()
        let revisions = try (0..<3).map { index in
            try admit(db, urls: ["https://example.test/card\(index).png"]).1
        }
        let readiness = MediaReadiness()
        let reserve = PreparedReserve(targetDepth: 1, lowWaterMark: 1)
        let transport = Transport(png: png)
        let media = prefetcher(db, assets: assets, transport: transport, readiness: readiness, reserve: reserve)

        let planned = await opportunity(reserve, media, offer: revisions,
            deadline: ProcessInfo.processInfo.systemUptime + 30)
        XCTAssertEqual(planned, [revisions[0]], "one slot, one revision charged")
        let charged = await transport.calledPaths
        XCTAssertEqual(charged, ["card0.png"])
        let snapshot = await reserve.snapshot()
        XCTAssertEqual(snapshot.ready, 1)
        let untouched = await reserve.phase(of: revisions[1])
        XCTAssertEqual(untouched, .pending, "a revision beyond the depth is left untouched, not decided")
    }
}
