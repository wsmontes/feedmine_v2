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

/// What one preparation attempt produced, in the terms a durable save has to state honestly.
///
/// Supply preparation is allowed to say "text-only" and move on; a saved occurrence has a reader attached to
/// the link, so the same attempt must also be able to say "nothing was attempted yet" (`deferred`), "it failed"
/// (`failed`) and "the disk could not hold it" (`insufficientSpace`). None of the three is a decision about the
/// occurrence, and none of them may delete the save.
public enum MediaPreparationOutcome: Hashable, Sendable {
    case ready(MediaReadiness.Ready)
    /// Definitive and *declared*: the feed declares no card image, so the text presentation is the occurrence as
    /// designed. This never means "an image failed" — that is `unavailable`.
    case textOnly
    /// Definitive: the occurrence declared a card image and no candidate could supply it. Supply excludes such a
    /// card from the current publication queue (INV-17) instead of publishing it as text under the same identity;
    /// a saved card states this as a failure and keeps the link.
    case unavailable
    /// Conditions forbid remote work right now (offline, thermally critical) or the store is unreadable. Nothing
    /// was attempted, so nothing is claimed.
    case deferred
    /// A fetch or a storage operation failed in a way a later attempt can change.
    case failed
    /// The bytes could not be stored durably because the volume had no room. Distinct from `failed`: the reader
    /// is told the specific state, and nothing is promised as available offline.
    case insufficientSpace
}

/// Why a fetch failed, in the vocabulary the run trace states. It names the cause the fetcher already observed;
/// it never decides anything — `MediaFetchFailure.classification` is what the retry policy reads.
public enum MediaFetchFailureReason: Hashable, Sendable {
    case status(Int)
    case notAnImage
    /// The file is over the **safety** ceiling (bytes, pixels or pixel count): refused, not merely late.
    case overCeiling
    /// The attempt ran out of the wait the device had. It is a fact about time, never about the image, and it is
    /// transient: the revision stays eligible for a later attempt.
    case deadline
    case httpDowngrade
    case privateHost
    case timeout
    case offline
    case invalidURL
    case transport
    case storage
    case tooSmall
    case insufficientSpace
    /// The cause could not be stated by a typed failure the caller already had.
    case unknown

    /// The token a settlement line carries. A status stays its own fact (`status-404`), never a bucket.
    public var traced: String {
        switch self {
        case .status(let code): return "status-\(code)"
        case .notAnImage: return "not-an-image"
        case .overCeiling: return "over-ceiling"
        case .deadline: return "deadline"
        case .httpDowngrade: return "http-downgrade"
        case .privateHost: return "private-host"
        case .timeout: return "timeout"
        case .offline: return "offline"
        case .invalidURL: return "invalid-url"
        case .transport: return "transport"
        case .storage: return "storage"
        case .tooSmall: return "too-small"
        case .insufficientSpace: return "insufficient-space"
        case .unknown: return "unknown"
        }
    }
}

/// How a media fetch failed. `classification` is the only part the retry policy reads: definitive failures
/// (missing, not an image, over the **safety** ceiling) settle the revision as designed text-only; transient ones
/// (timeouts, 5xx, lost connection, the wait running out) retry later. `reason` is the cause the fetcher observed,
/// carried for the run trace — it never changes the classification and never decides anything.
public struct MediaFetchFailure: Error, Hashable, Sendable {
    public enum Classification: Hashable, Sendable {
        case transient
        case definitive
    }

    public let classification: Classification
    public let reason: MediaFetchFailureReason

    public init(_ classification: Classification, reason: MediaFetchFailureReason = .unknown) {
        self.classification = classification
        self.reason = reason
    }

    /// A failure whose caller knows only the classification (tests, old call sites): the cause is `unknown`.
    public static let transient = MediaFetchFailure(.transient)
    public static let definitive = MediaFetchFailure(.definitive)
}

/// One attempt's outcome with the cause the settlement line states for a non-ready end. Internal: the decision
/// is still `MediaPreparationOutcome`, and the reason is evidence that nothing consults.
struct MediaPreparationAttempt: Sendable {
    let outcome: MediaPreparationOutcome
    let reason: MediaFetchFailureReason?

    init(_ outcome: MediaPreparationOutcome, reason: MediaFetchFailureReason? = nil) {
        self.outcome = outcome
        self.reason = reason
    }
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

/// First answer wins: the transport returned bytes, it threw, or the attempt's time allowance ended. The loser is
/// never awaited here, so a transport that ignores cancellation cannot hold the owner past the deadline.
private final class MediaFetchSettlement: @unchecked Sendable {
    struct Box: @unchecked Sendable { let error: any Error }
    enum Outcome: @unchecked Sendable {
        case bytes(Data)
        case failure(Box)
        case expired
    }

    private let lock = NSLock()
    private var outcome: Outcome?
    private var continuation: CheckedContinuation<Outcome, Never>?

    func settle(_ value: Outcome) {
        lock.lock()
        guard outcome == nil else { lock.unlock(); return }
        outcome = value
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    func wait() async -> Outcome {
        if let settled = settled() { return settled }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            // Re-read under the lock: the answer may have arrived between the check above and this install.
            lock.lock()
            if let settled = outcome {
                lock.unlock()
                continuation.resume(returning: settled)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func settled() -> Outcome? {
        lock.lock(); defer { lock.unlock() }
        return outcome
    }
}

/// Runs one transport call inside what is left of the attempt's time allowance. A call still running when the
/// allowance ends is cut and reported as the transient `deadline` cause: the device ran out of wait, the image did
/// not fail, and the revision stays eligible for a later attempt. Without an allowance (no measured wait) the call
/// is bounded only by the transport itself.
private func fetchWithinTimeAllowance(_ seconds: Double?,
    _ operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
    guard let seconds else { return try await operation() }
    guard seconds.isFinite, seconds > 0 else { throw MediaFetchFailure(.transient, reason: .deadline) }
    let settlement = MediaFetchSettlement()
    let work = Task { [settlement] in
        do { settlement.settle(.bytes(try await operation())) }
        catch { settlement.settle(.failure(MediaFetchSettlement.Box(error: error))) }
    }
    // A day is far past any runway tolerance; the cap only keeps the nanosecond conversion inside UInt64.
    let timer = Task { [settlement] in
        try? await Task.sleep(nanoseconds: UInt64((min(seconds, 86_400) * 1_000_000_000).rounded(.up)))
        guard !Task.isCancelled else { return }
        settlement.settle(.expired)
    }
    let outcome = await settlement.wait()
    timer.cancel()
    switch outcome {
    case .bytes(let data): return data
    case .failure(let boxed): throw boxed.error
    case .expired:
        work.cancel()
        throw MediaFetchFailure(.transient, reason: .deadline)
    }
}

/// First answer wins: the drain finished, or its budget expired. The budget only bounds the wait; the retirement
/// fence in `MediaPrefetcher` is what forbids later starts.
private actor MediaRetirementSettlement {
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    func finish(_ value: Bool) {
        guard result == nil else { return }
        result = value
        continuation?.resume(returning: value)
        continuation = nil
    }

    func wait() async -> Bool {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }
}

public actor MediaPrefetcher {
    /// One transport call under the terms its attempt runs on: the budget states the safety ceiling the bytes may
    /// not exceed and the wait the owner allows. It never asks the transport to refuse an image for not fitting the
    /// wait — that is `MediaPrefetcher`'s time allowance, and its outcome is transient.
    public typealias Fetch = @Sendable (_ url: URL, _ budget: MediaByteBudget) async throws -> Data
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
    /// One entry per revision with work in progress: the single-flight owner both supply and saved preparation
    /// join. It replaces the set of in-flight ids so a save can wait for the same download instead of starting
    /// a second one.
    private var running: [OriginRevisionID: Task<MediaPreparationAttempt, Never>] = [:]
    private var measuredBytesPerSecond: Double?
    private var transientFailures: [OriginRevisionID: Int] = [:]
    private var transientRetryAt: [OriginRevisionID: Double] = [:]
    /// R20/P01 retirement fence. Once set, no new download may start on the shared transport; the owner refuses
    /// new work and lets the current attempts settle (or its bounded drain expire) before the transport dies.
    private var retired = false
    #if DEBUG
    /// Evidence of the supply preparation path (first consideration, settlement line). Nil records nothing; a
    /// shipping build compiles it out. It is not read by any decision.
    private let mediaWitness: MediaPreparationWitness?
    #endif

    public init(database: RuntimeDatabase, assetDirectory: URL, readiness: MediaReadiness = MediaReadiness(),
        concurrentDownloadLimit: Int, transientRetryBaseSeconds: Double = 30,
        monotonicSeconds: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
        preparation: MediaPreparation? = nil,
        fetch: @escaping Fetch, conditions: @escaping Conditions,
        onReadinessChanged: (@Sendable (OriginRevisionID) async -> Void)? = nil,
        mediaTrace: ReplenishmentTrace? = nil) {
        self.readiness = readiness
        contentStore = ContentStore(database: database)
        self.preparation = preparation ?? MediaPreparation(assetDirectory: assetDirectory)
        self.fetch = fetch
        self.conditions = conditions
        self.onReadinessChanged = onReadinessChanged
        self.concurrentDownloadLimit = max(1, concurrentDownloadLimit)
        self.transientRetryBaseSeconds = transientRetryBaseSeconds.isFinite && transientRetryBaseSeconds > 0 ? transientRetryBaseSeconds : 30
        self.monotonicSeconds = monotonicSeconds
        #if DEBUG
        mediaWitness = mediaTrace.map { MediaPreparationWitness(trace: $0, clock: monotonicSeconds) }
        #endif
    }

    /// Retirement order for the shared transport owner (P01/R20): deny every new start first, cancel the attempts
    /// this owner already authorized, then wait **boundedly** for them. `false` states that the drain did not
    /// settle inside the budget; it is never an authorization for a late start — the fence stays closed.
    @discardableResult
    public func retire(budget: Duration = .seconds(2)) async -> Bool {
        retired = true
        let work = Array(running.values)
        for task in work { task.cancel() }
        guard !work.isEmpty else { return true }
        let settlement = MediaRetirementSettlement()
        Task {
            for task in work { _ = await task.value }
            await settlement.finish(true)
        }
        Task {
            try? await Task.sleep(for: budget)
            await settlement.finish(false)
        }
        return await settlement.wait()
    }

    /// Prepares media for the newest `limit` supply items not yet settled. Returns when all chosen
    /// items settled, or when `deadline` (monotonic seconds) passes — unfinished downloads keep
    /// running (owned by this actor, single-flight via `running`) and only help later selections.
    public func prefetchSupplyHead(limit: Int, deadline: Double? = nil) async {
        guard !retired, limit > 0,
            let window = try? contentStore.candidateWindow(sourceID: nil, after: nil, examinedCapacity: limit) else { return }
        await prefetch(window.records.map(\.originRevisionID), deadline: deadline)
    }

    /// Prepares media for an explicit, priority-ordered list of revisions (review F05: the next
    /// editorial candidates). Same deadline contract as `prefetchSupplyHead`.
    public func prefetch(_ ordered: [OriginRevisionID], deadline: Double? = nil) async {
        guard !retired else { return }
        #if DEBUG
        // Every revision handed to the path is one it considers for publication; the first instant is what the
        // settlement line measures its elapsed time from.
        mediaWitness?.consider(ordered)
        #endif
        let now = monotonicSeconds()
        var seen = Set<OriginRevisionID>()
        let revisions = ordered.filter { revision in
            guard seen.insert(revision).inserted, !readiness.isSettled(revision), running[revision] == nil else {
                return false
            }
            if let retry = transientRetryAt[revision], now < retry { return false }
            return true
        }
        guard !revisions.isEmpty else { return }
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
            var next = 0, active = 0
            while !retired, next < revisions.count || active > 0 {
                while !retired, active < concurrentDownloadLimit, next < revisions.count {
                    let revision = revisions[next]
                    group.addTask { await self.prepare(revision) }
                    next += 1; active += 1
                }
                await group.next()
                active -= 1
            }
        }
    }

    /// Supply's own use of the pipeline: run one attempt and turn its outcome into the readiness decision the
    /// feed's selection reads. Nothing here is about a saved card.
    private func prepare(_ revision: OriginRevisionID) async {
        let attempt = await acquireSingleFlight(revision)
        #if DEBUG
        // One line per revision per attempt, written at the attempt's end — including the attempts that end
        // without settling, because "still pending" is a fact the run must be able to read.
        if let mediaWitness {
            mediaWitness.settle(revision, outcome: attempt.outcome, reason: attempt.reason,
                facts: MediaRevisionFacts.read(revision, in: contentStore))
        }
        #endif
        switch attempt.outcome {
        case .ready(let value): await settle(revision, value, textDeclared: false)
        case .textOnly: await settle(revision, nil, textDeclared: true)
        // An image the card declared could not be prepared: it settles without a presentation, which keeps it out
        // of the current publication queue (INV-17). It is never published as a text card in its place.
        case .unavailable: await settle(revision, nil, textDeclared: false)
        case .deferred: return
        case .failed, .insufficientSpace:
            // Network or storage trouble is not a statement about the occurrence: offer it again after a
            // growing delay instead of settling it as designed text-only.
            let failures = (transientFailures[revision] ?? 0) + 1
            transientFailures[revision] = failures
            transientRetryAt[revision] = monotonicSeconds() + transientRetryBaseSeconds * pow(2, Double(min(failures - 1, 16)))
        }
    }

    /// The re-preparation entry point for an occurrence a reader saved (its bytes were evicted, or the save
    /// found none). It joins the same download owner and the same fetch/policy: there is no second pipeline.
    ///
    /// It deliberately ignores the two in-memory shortcuts that are correct for *supply* — `isSettled` and the
    /// transient backoff — because neither is a fact about the durable asset. A settled decision was made for a
    /// selection; a saved card's link is the reader's request to try again. The outcome is returned instead of
    /// settling, so the caller records it as availability and never claims readiness it did not get. When the
    /// bytes are missing the saved occurrence simply is not render-ready: the feed excludes it from the current
    /// window (INV-17) and the availability row states `pending`/`failed`/`insufficientSpace` with retry — it is
    /// never converted into a text card under the same identity.
    public func prepareForSave(_ revision: OriginRevisionID) async -> MediaPreparationOutcome {
        guard !retired else { return .deferred }
        return await acquireSingleFlight(revision).outcome
    }

    /// One attempt per revision at a time, shared by supply and saved preparation. A caller that arrives while
    /// work is running waits for that work rather than starting a competing download.
    private func acquireSingleFlight(_ revision: OriginRevisionID) async -> MediaPreparationAttempt {
        guard !retired else { return MediaPreparationAttempt(.deferred) }
        // Only the owner of the work removes it. A joiner that removed it after resuming could erase a *newer*
        // task registered in the same revision, and the next caller would start a second download.
        if let work = running[revision] { return await work.value }
        let work = Task { await self.acquire(revision) }
        running[revision] = work
        defer { running.removeValue(forKey: revision) }
        return await work.value
    }

    private func acquire(_ revision: OriginRevisionID) async -> MediaPreparationAttempt {
        guard let policy = conditions(measuredBytesPerSecond),
            let candidates = try? contentStore.mediaCandidates(originRevisionID: revision) else {
            return MediaPreparationAttempt(.deferred) // Conditions unknown or storage unreadable: leave unsettled.
        }
        // The card contract is what the feed declared: a visible card image. Without one (an audio-only or
        // text-only item) the text presentation is the card as designed, and settling it as text is not a fallback.
        let declaresImage = candidates.contains { $0.role == .cardVisual && $0.mediaClass == .image }
        let first: MediaCandidate, fallbacks: [MediaCandidate]
        switch MediaResolver.resolve(candidates, policy: policy) {
        case .prepare(let chosen, let rest): first = chosen; fallbacks = rest
        case .textOnly(.conditionsForbidRemoteMedia): return MediaPreparationAttempt(.deferred) // Offline or hot.
        case .textOnly:
            // Nothing viable to prepare. Whether that means "a text card as designed" or "an image the feed
            // declared could not be prepared" is the feed's declaration, not the resolver's answer. A declared
            // image refused here was skipped by its own declaration (non-image MIME, SVG, over the ceiling).
            return declaresImage
                ? MediaPreparationAttempt(.unavailable, reason: Self.declaredRefusal(candidates, policy: policy))
                : MediaPreparationAttempt(.textOnly)
        }
        let budget = policy.byteBudget
        // The affordable bytes never decide whether to attempt — only a zero wait does, because then there is no time
        // at all and a call could only fail. The revision is left eligible rather than refused.
        guard budget.waitSeconds.map({ $0 > 0 }) ?? true else { return MediaPreparationAttempt(.deferred) }
        #if DEBUG
        // The terms and their provenance, once per attempt and before the first fetch, so a truncation pairs with
        // the exact allowance that caused it. Emitted from the same value the fetch below is handed.
        mediaWitness?.byteBudget(revision, budget)
        #endif
        // The time this revision's attempt has, read once: the budget's own wait tolerance. A candidate that does not
        // finish inside it is cut as `deadline` (transient); a candidate larger than `affordableBytes` is attempted
        // like any other and is never refused for it.
        let allowanceEnds = budget.waitSeconds.map { monotonicSeconds() + $0 }
        var sawTransient = false, sawStorageFailure = false, sawSpace = false
        // The cause the settlement line states. The first definitive refusal is the preferred candidate's, which
        // is the most informative one; a transient attempt keeps its own cause because it is retried.
        var definitiveReason: MediaFetchFailureReason?
        var transientReason: MediaFetchFailureReason?
        for candidate in [first] + fallbacks {
            if Task.isCancelled { return MediaPreparationAttempt(.deferred) }
            let started = ProcessInfo.processInfo.systemUptime
            let remaining = allowanceEnds.map { $0 - monotonicSeconds() }
            let bytes: Data
            do {
                bytes = try await fetchWithinTimeAllowance(remaining) {
                    try await self.fetch(candidate.remoteURL, budget)
                }
            } catch {
                // Review F04: only a definitive answer (missing, not an image, over the safety ceiling) is final.
                if Self.isTransient(error) {
                    sawTransient = true
                    if transientReason == nil { transientReason = Self.failureReason(error) }
                } else if definitiveReason == nil {
                    definitiveReason = Self.failureReason(error)
                }
                continue
            }
            observeThroughput(bytes: bytes.count, seconds: ProcessInfo.processInfo.systemUptime - started)
            let result: MediaPreparationResult
            do { result = try preparation.prepare(candidate: candidate, input: .bytes(bytes)) }
            catch LocalMediaAssetError.insufficientSpace { sawSpace = true; continue }
            catch { sawStorageFailure = true; continue }
            guard case .usable(let asset) = result.state else {
                // Media's own inspection refused the bytes as an image container (`invalidImage`).
                if definitiveReason == nil { definitiveReason = .notAnImage }
                continue
            }
            let fit = policy.fit(measuredPixelWidth: asset.pixelWidth, height: asset.pixelHeight)
            guard fit != .unsuitable else {
                if definitiveReason == nil {
                    definitiveReason = Self.fitReason(width: asset.pixelWidth, height: asset.pixelHeight,
                        ceilings: policy.ceilings)
                }
                continue
            }
            return MediaPreparationAttempt(.ready(.init(result: result, fit: fit)))
        }
        // A volume that could not hold the chosen image is the most specific fact, and the one the reader can
        // act on; then a failed attempt; only then "this occurrence's declared media is unusable".
        if sawSpace { return MediaPreparationAttempt(.insufficientSpace, reason: .insufficientSpace) }
        if sawStorageFailure { return MediaPreparationAttempt(.failed, reason: .storage) }
        if sawTransient { return MediaPreparationAttempt(.failed, reason: transientReason ?? .unknown) }
        // Every viable candidate was definitively unusable. A card that declared an image leaves the current
        // publication queue (INV-17); only an occurrence that declared no image is the text card as designed.
        return declaresImage
            ? MediaPreparationAttempt(.unavailable, reason: definitiveReason ?? .unknown)
            : MediaPreparationAttempt(.textOnly)
    }

    /// Why a declared image was refused before any bytes moved: the resolver skips a candidate whose declared
    /// MIME is not an image (or is SVG) or whose declared pixels exceed the safety ceiling. `unknown` when the
    /// resolver refused for a reason none of those facts states.
    static func declaredRefusal(_ candidates: [MediaCandidate], policy: MediaPolicy) -> MediaFetchFailureReason {
        for candidate in candidates where candidate.role == .cardVisual && candidate.mediaClass == .image {
            if let mime = candidate.declaredMimeType?.lowercased(), !mime.hasPrefix("image/") || mime.contains("svg") {
                return .notAnImage
            }
            if let width = candidate.declaredPixelWidth, let height = candidate.declaredPixelHeight,
                width > policy.ceilings.maximumPixelSide || height > policy.ceilings.maximumPixelSide {
                return .overCeiling
            }
        }
        return .unknown
    }

    /// Why a measured image fits no slot: over a safety ceiling, or smaller than the thumbnail minimum.
    static func fitReason(width: Int, height: Int, ceilings: MediaSafetyCeilings) -> MediaFetchFailureReason {
        if width > ceilings.maximumPixelSide || height > ceilings.maximumPixelSide
            || width.multipliedReportingOverflow(by: height).overflow
            || width * height > ceilings.maximumPixelCount {
            return .overCeiling
        }
        return .tooSmall
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
        if let failure = error as? MediaFetchFailure { return failure.classification == .transient }
        if let url = error as? URLError {
            switch url.code {
            case .badURL, .unsupportedURL, .fileDoesNotExist, .noPermissionsToReadFile, .dataLengthExceedsMaximum: return false
            default: return true
            }
        }
        return true
    }

    /// The cause a fetch error already states, for the settlement line. This reads the existing typed failure
    /// (or the `URLError` code); it classifies nothing and changes nothing.
    static func failureReason(_ error: any Error) -> MediaFetchFailureReason {
        if let failure = error as? MediaFetchFailure { return failure.reason }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .resourceUnavailable:
                return .offline
            case .dataLengthExceedsMaximum: return .overCeiling
            case .badURL, .unsupportedURL: return .invalidURL
            case .cancelled: return .transport
            default: return .transport
            }
        }
        return .unknown
    }

    /// Exponentially weighted throughput; feeds the next policy's byte budget (PD-6).
    private func observeThroughput(bytes: Int, seconds: Double) {
        guard bytes > 0, seconds > 0, seconds.isFinite else { return }
        let sample = Double(bytes) / seconds
        measuredBytesPerSecond = measuredBytesPerSecond.map { $0 * 0.7 + sample * 0.3 } ?? sample
    }
}
