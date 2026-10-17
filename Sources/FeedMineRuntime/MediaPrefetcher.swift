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
    /// Revisions whose feed declares **no card image**, so their text presentation is the card as designed. A
    /// revision that declares an image and whose media could not be prepared is settled too, but it has no
    /// presentation: it stays out of the current publication queue (INV-17) instead of becoming a text card.
    private var textDeclared: Set<OriginRevisionID> = []

    public init() {}

    public func prepared(_ revision: OriginRevisionID) -> Ready? {
        lock.lock(); defer { lock.unlock() }
        return ready[revision]
    }
    /// Whether this revision's media was **decided** (definitively unavailable, or prepared): a revision that is
    /// neither prepared nor settled is *pending*, which is not the same fact as text-only (PD-5/PD-9, F06).
    public func isSettled(_ revision: OriginRevisionID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return settled.contains(revision)
    }

    /// How many revisions this index has decided at all, and how many of those carry a prepared image. Stated for
    /// the device console's journey line (PO, 2026-10-15): the media pipeline's own numbers, so a run says what it
    /// really prepared instead of a second registry having to guess. No state is added — these read what the two
    /// members above already keep, under the same lock.
    public var settledCount: Int {
        lock.lock(); defer { lock.unlock() }
        return settled.count
    }
    public var preparedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return ready.count
    }
    /// `textDeclared` states whether nil is the absence of media work (a card designed as text) or the failure of
    /// media the card declared. Only the first is a presentation, so the flag is **required**: a caller recording a
    /// failure cannot inherit "declared text" by omitting it and turn a missing image into `.textOnly`.
    @discardableResult
    func record(_ revision: OriginRevisionID, _ value: Ready?, textDeclared: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !settled.contains(revision) else { return false }
        settled.insert(revision)
        if let value { ready[revision] = value } else if textDeclared { self.textDeclared.insert(revision) }
        return true
    }

    /// nil means pending, never an implicit text-only fallback. Read the decision under one lock.
    public func presentation(for revision: OriginRevisionID) -> PublicationPresentation? {
        lock.lock(); defer { lock.unlock() }
        return presentationLocked(for: revision)
    }

    /// One atomic snapshot for a publication opportunity. Missing entries are suspended;
    /// their records and acquisition/preparation work remain in their existing owners.
    public func presentations(for revisions: [OriginRevisionID]) -> [OriginRevisionID: PublicationPresentation] {
        lock.lock(); defer { lock.unlock() }
        var presentations: [OriginRevisionID: PublicationPresentation] = [:]
        for revision in revisions { presentations[revision] = presentationLocked(for: revision) }
        return presentations
    }

    private func presentationLocked(for revision: OriginRevisionID) -> PublicationPresentation? {
        guard settled.contains(revision) else { return nil }
        guard let value = ready[revision] else {
            // A declared text card is a final presentation. An image card whose media never became ready has no
            // presentation at all: publishing it as text would be the fallback the owner's rule forbids.
            return textDeclared.contains(revision) ? .textOnly : nil
        }
        switch value.fit {
        case .hero: return .image(value.result, layout: .hero)
        case .thumbnail: return .image(value.result, layout: .thumbnail)
        case .unsuitable: return .textOnly
        }
    }
}

/// How a media fetch failed. Definitive failures (missing, not an image, too large) settle the
/// revision as designed text-only; transient ones (timeouts, 5xx, lost connection) retry later.
public enum MediaFetchFailure: Error, Hashable, Sendable {
    case transient
    case definitive
}

/// Resumes one continuation exactly once, from whichever racer gets there first.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var resumed = false
    func install(_ value: CheckedContinuation<Void, Never>) {
        lock.lock()
        if resumed { lock.unlock(); value.resume(); return }
        continuation = value
        lock.unlock()
    }
    func resume() {
        lock.lock()
        guard !resumed else { lock.unlock(); return }
        resumed = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
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
    private let transientRetryBaseSeconds: Double
    private let monotonicSeconds: @Sendable () -> Double
    private let onReadinessChanged: (@Sendable (OriginRevisionID) async -> Void)?
    private var inFlight: Set<OriginRevisionID> = []
    private var measuredBytesPerSecond: Double?
    private var transientFailures: [OriginRevisionID: Int] = [:]
    private var transientRetryAt: [OriginRevisionID: Double] = [:]

    public init(database: RuntimeDatabase, assetDirectory: URL, readiness: MediaReadiness = MediaReadiness(),
        concurrentDownloadLimit: Int, transientRetryBaseSeconds: Double = 30,
        monotonicSeconds: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
        fetch: @escaping Fetch, conditions: @escaping Conditions,
        onReadinessChanged: (@Sendable (OriginRevisionID) async -> Void)? = nil) {
        self.readiness = readiness
        contentStore = ContentStore(database: database)
        preparation = MediaPreparation(assetDirectory: assetDirectory)
        self.fetch = fetch
        self.conditions = conditions
        self.onReadinessChanged = onReadinessChanged
        self.concurrentDownloadLimit = max(1, concurrentDownloadLimit)
        self.transientRetryBaseSeconds = transientRetryBaseSeconds.isFinite && transientRetryBaseSeconds > 0 ? transientRetryBaseSeconds : 30
        self.monotonicSeconds = monotonicSeconds
    }

    /// Prepares media for the newest `limit` supply items not yet settled. Returns when all chosen
    /// items settled, or when `deadline` (monotonic seconds) passes — unfinished downloads keep
    /// running (owned by this actor, single-flight via `inFlight`) and only help later selections.
    public func prefetchSupplyHead(limit: Int, deadline: Double? = nil) async {
        guard limit > 0, let window = try? contentStore.candidateWindow(sourceID: nil, after: nil, examinedCapacity: limit) else { return }
        await prefetch(window.records.map(\.originRevisionID), deadline: deadline)
    }

    /// Prepares media for an explicit, priority-ordered list of revisions (review F05: the next
    /// editorial candidates). Same deadline contract as `prefetchSupplyHead`.
    public func prefetch(_ ordered: [OriginRevisionID], deadline: Double? = nil) async {
        let now = monotonicSeconds()
        var seen = Set<OriginRevisionID>()
        let revisions = ordered.filter { revision in
            guard seen.insert(revision).inserted, !readiness.isSettled(revision), !inFlight.contains(revision) else { return false }
            if let retry = transientRetryAt[revision], now < retry { return false }
            return true
        }
        guard !revisions.isEmpty else { return }
        inFlight.formUnion(revisions)
        let work = Task { await self.prepareAll(revisions) }
        guard let deadline else { await work.value; return }
        let wait = deadline - ProcessInfo.processInfo.systemUptime
        guard wait > 0 else { return }
        // Review F03: never join the unstructured work. Whichever finishes first — the work or the
        // deadline — resumes the caller exactly once; the work keeps running independently.
        await Self.firstOf(work, orSeconds: wait)
    }

    private static func firstOf(_ work: Task<Void, Never>, orSeconds wait: Double) async {
        let gate = ResumeOnce()
        var timer: Task<Void, Never>?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.install(continuation)
            Task { await work.value; gate.resume() }
            timer = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, wait) * 1_000_000_000))
                gate.resume()
            }
        }
        timer?.cancel()
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
        // The card contract is what the feed declared: a visible card image. Without one (an audio-only or
        // text-only item) the text presentation is the card as designed, and settling it as text is not a fallback.
        let declaresImage = candidates.contains { $0.role == .cardVisual && $0.mediaClass == .image }
        let first: MediaCandidate, fallbacks: [MediaCandidate]
        switch MediaResolver.resolve(candidates, policy: policy) {
        case .prepare(let chosen, let rest): first = chosen; fallbacks = rest
        case .textOnly(.conditionsForbidRemoteMedia): return // Offline or overheated: try again later.
        case .textOnly:
            // Nothing viable to prepare. An image the card declared is unpublished work, not a text card.
            await settle(revision, nil, textDeclared: !declaresImage)
            return
        }
        let ceiling = policy.downloadByteBudget
        guard ceiling > 0 else { return } // Not affordable now; retry when conditions improve.
        var sawTransient = false
        for candidate in [first] + fallbacks {
            if Task.isCancelled { return }
            let started = ProcessInfo.processInfo.systemUptime
            let bytes: Data
            do { bytes = try await fetch(candidate.remoteURL, ceiling) }
            catch {
                // Review F04: only a definitive answer (missing, not an image, too large) is final.
                if Self.isTransient(error) { sawTransient = true }
                continue
            }
            observeThroughput(bytes: bytes.count, seconds: ProcessInfo.processInfo.systemUptime - started)
            guard let result = try? preparation.prepare(candidate: candidate, input: .bytes(bytes)),
                case .usable(let asset) = result.state else { continue }
            let fit = policy.fit(measuredPixelWidth: asset.pixelWidth, height: asset.pixelHeight)
            guard fit != .unsuitable else { continue }
            await settle(revision, .init(result: result, fit: fit), textDeclared: false)
            return
        }
        if sawTransient {
            // Network trouble, not a bad image: offer the revision again after a growing delay.
            let failures = (transientFailures[revision] ?? 0) + 1
            transientFailures[revision] = failures
            transientRetryAt[revision] = monotonicSeconds() + transientRetryBaseSeconds * pow(2, Double(min(failures - 1, 16)))
            return
        }
        // Every viable candidate was definitively unusable. The card declared an image and has none: it leaves
        // the current publication queue (INV-17) and is never published as a text card in its place.
        await settle(revision, nil, textDeclared: !declaresImage)
    }

    /// A real transition may reopen the existing supply episode; no polling or retry owner is added.
    private func settle(_ revision: OriginRevisionID, _ value: MediaReadiness.Ready?,
        textDeclared: Bool) async {
        transientFailures.removeValue(forKey: revision)
        transientRetryAt.removeValue(forKey: revision)
        if readiness.record(revision, value, textDeclared: textDeclared) { await onReadinessChanged?(revision) }
    }

    /// Definitive failures are explicitly marked by the fetcher; anything else (timeouts, lost
    /// connections, 5xx, unknown errors) is treated as transient.
    static func isTransient(_ error: any Error) -> Bool {
        if let failure = error as? MediaFetchFailure { return failure == .transient }
        if let url = error as? URLError {
            switch url.code {
            case .badURL, .unsupportedURL, .fileDoesNotExist, .noPermissionsToReadFile, .dataLengthExceedsMaximum: return false
            default: return true
            }
        }
        return true
    }

    /// Exponentially weighted throughput; feeds the next policy's byte budget (PD-6).
    private func observeThroughput(bytes: Int, seconds: Double) {
        guard bytes > 0, seconds > 0, seconds.isFinite else { return }
        let sample = Double(bytes) / seconds
        measuredBytesPerSecond = measuredBytesPerSecond.map { $0 * 0.7 + sample * 0.3 } ?? sample
    }
}
