// File: MediaPrefetcher.swift
// Module: FeedMineRuntime
// Owns: the single remote-media acquisition owner (PD-6): choosing, downloading and materializing
//   card visuals for supply *before* it is selected, plus a synchronous readiness index that
//   publication preparation reads.
// Does not own: HTTP transport (injected by composition), editorial order or published history.
//
// v1 lessons (03-media.md): one pipeline and one owner (MD-1); resolve before publish, never mutate
// a visible card afterwards (MD-2); single-flight per item; measured dimensions decide the layout;
// bounded byte ceiling per download; record "no image" so it is not retried endlessly (MD-9).

import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineMedia
import FeedMinePublication

/// Synchronous, thread-safe view of prepared media used inside the synchronous `prepare` closure.
public final class MediaReadiness: @unchecked Sendable {
    public struct Ready: Hashable, Sendable {
        public let result: MediaPreparationResult
        public let fit: MediaSlotFit
    }
    private let lock = NSLock()
    private var ready: [OriginRevisionID: Ready] = [:]
    private var settled: Set<OriginRevisionID> = []

    public init() {}

    public func prepared(_ revision: OriginRevisionID) -> Ready? {
        lock.lock(); defer { lock.unlock() }
        return ready[revision]
    }
    func isSettled(_ revision: OriginRevisionID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return settled.contains(revision)
    }
    func record(_ revision: OriginRevisionID, _ value: Ready?) {
        lock.lock(); defer { lock.unlock() }
        settled.insert(revision)
        if let value { ready[revision] = value }
    }

    /// PD-5: a card is either drawn with a real, prepared image or designed without one.
    public func presentation(for revision: OriginRevisionID) -> PublicationPresentation {
        guard let value = prepared(revision) else { return .textOnly }
        switch value.fit {
        case .hero: return .image(value.result, layout: .hero)
        case .thumbnail: return .image(value.result, layout: .thumbnail)
        case .unsuitable: return .textOnly
        }
    }
}

public actor MediaPrefetcher {
    public typealias Fetch = @Sendable (_ url: URL, _ byteCeiling: Int) async throws -> Data
    public typealias Conditions = @Sendable (_ measuredBytesPerSecond: Double?) -> MediaPolicy?

    public nonisolated let readiness: MediaReadiness
    private let contentStore: ContentStore
    private let preparation: MediaPreparation
    private let fetch: Fetch
    private let conditions: Conditions
    private let concurrentDownloadLimit: Int
    private var inFlight: Set<OriginRevisionID> = []
    private var measuredBytesPerSecond: Double?

    public init(database: RuntimeDatabase, assetDirectory: URL, readiness: MediaReadiness = MediaReadiness(),
        concurrentDownloadLimit: Int, fetch: @escaping Fetch, conditions: @escaping Conditions) {
        self.readiness = readiness
        contentStore = ContentStore(database: database)
        preparation = MediaPreparation(assetDirectory: assetDirectory)
        self.fetch = fetch
        self.conditions = conditions
        self.concurrentDownloadLimit = max(1, concurrentDownloadLimit)
    }

    /// Prepares media for the newest `limit` supply items not yet settled. Returns when all chosen
    /// items settled, or when `deadline` (monotonic seconds) passes — unfinished downloads keep
    /// running and only help later selections.
    public func prefetchSupplyHead(limit: Int, deadline: Double? = nil) async {
        guard limit > 0, let window = try? contentStore.candidateWindow(sourceID: nil, after: nil, examinedCapacity: limit) else { return }
        let revisions = window.records.map(\.originRevisionID).filter { !readiness.isSettled($0) && !inFlight.contains($0) }
        guard !revisions.isEmpty else { return }
        inFlight.formUnion(revisions)
        let work = Task { await self.prepareAll(revisions) }
        guard let deadline else { await work.value; return }
        let wait = deadline - ProcessInfo.processInfo.systemUptime
        guard wait > 0 else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await work.value }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            await group.next()
            group.cancelAll()
        }
    }

    private func prepareAll(_ revisions: [OriginRevisionID]) async {
        await withTaskGroup(of: Void.self) { group in
            var next = 0, running = 0
            while next < revisions.count || running > 0 {
                while running < concurrentDownloadLimit, next < revisions.count {
                    let revision = revisions[next]
                    group.addTask { await self.prepare(revision) }
                    next += 1; running += 1
                }
                await group.next()
                running -= 1
            }
        }
    }

    private func prepare(_ revision: OriginRevisionID) async {
        defer { inFlight.remove(revision) }
        guard let policy = conditions(measuredBytesPerSecond),
            let candidates = try? contentStore.mediaCandidates(originRevisionID: revision) else {
            return // Conditions unknown or storage unreadable: leave unsettled for a later opportunity.
        }
        let first: MediaCandidate, fallbacks: [MediaCandidate]
        switch MediaResolver.resolve(candidates, policy: policy) {
        case .prepare(let chosen, let rest): first = chosen; fallbacks = rest
        case .textOnly(.conditionsForbidRemoteMedia): return // Offline or overheated: try again later.
        case .textOnly: readiness.record(revision, nil); return
        }
        let ceiling = policy.downloadByteBudget
        guard ceiling > 0 else { return } // Not affordable now; retry when conditions improve.
        for candidate in [first] + fallbacks {
            if Task.isCancelled { return }
            let started = ProcessInfo.processInfo.systemUptime
            guard let bytes = try? await fetch(candidate.remoteURL, ceiling) else { continue }
            observeThroughput(bytes: bytes.count, seconds: ProcessInfo.processInfo.systemUptime - started)
            guard let result = try? preparation.prepare(candidate: candidate, input: .bytes(bytes)),
                case .usable(let asset) = result.state else { continue }
            let fit = policy.fit(measuredPixelWidth: asset.pixelWidth, height: asset.pixelHeight)
            guard fit != .unsuitable else { continue }
            readiness.record(revision, .init(result: result, fit: fit))
            return
        }
        // Every viable candidate failed or was unsuitable: this revision is designed text-only.
        readiness.record(revision, nil)
    }

    /// Exponentially weighted throughput; feeds the next policy's byte budget (PD-6).
    private func observeThroughput(bytes: Int, seconds: Double) {
        guard bytes > 0, seconds > 0, seconds.isFinite else { return }
        let sample = Double(bytes) / seconds
        measuredBytesPerSecond = measuredBytesPerSecond.map { $0 * 0.7 + sample * 0.3 } ?? sample
    }
}
