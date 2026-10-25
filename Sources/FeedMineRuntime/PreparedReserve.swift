// File: PreparedReserve.swift
// Module: FeedMineRuntime
// Owns: the per-revision state machine, the depth policy and the retained-byte budget of the prepared-presentation
//   reserve (PM-028A). It keeps **state**, never data: the prepared presentation stays in `MediaReadiness`, the
//   asset stays in the content-addressed store, and no image bytes or decoded pixels are copied here.
// Does not own: acquisition (`MediaPrefetcher`), the readiness index (`MediaReadiness`), publication order or the
//   editorial walk. A revision is only ever a name here.

import Foundation
import FeedMineDomain

/// The index of prepared presentations that a publication opportunity can draw from, and the policy that decides
/// which revisions deserve remote work now.
///
/// The split the PM asked for (PM-028A §4.2) is explicit in the stored facts: this actor holds **persisted** bytes
/// only (`persistedBytes`, the size of the materialised asset a revision in the reserve already has on disk, handed
/// back when that revision publishes or exhausts). It holds no decoded-image memory and no in-flight download: those
/// two belong to `MediaReadiness` and `MediaPrefetcher`, and counting them here would be a second, diverging
/// measurement of the same work.
///
/// Every phase transition is explicit and idempotent, because a media attempt can end before, at, or long after the
/// deadline of the slice that started it:
///
/// - a completion that arrives **inside** the slice's window settles a `.preparing` revision and is on time;
/// - a completion that arrives **after** the window (`windowClosed`) settles a revision that is no longer
///   `.preparing`, is still accepted as `.ready`, and is counted in `lateCompletions` — the fact the whole reserve
///   exists to make visible (PM-028A §4.3);
/// - a `.published` or `.exhausted` revision ignores every later settlement: nothing is republished and nothing is
///   prepared twice.
public actor PreparedReserve {
    /// Where one revision stands. `pending` is the absence of a decision; `deferred` states a structural condition
    /// (budget, conditions, an ended window) that must be waited out and spends no attempt.
    public enum Phase: Hashable, Sendable {
        /// Never attempted, or released because the retained-byte budget forbade new work.
        case pending
        /// One attempt is in flight (the index of that attempt, from zero).
        case preparing(attempt: Int)
        /// Prepared and not yet published: the presentation is in `MediaReadiness` and may be selected.
        case ready(hasImage: Bool)
        /// It left in an edition; it never competes again and keeps its identity.
        case published
        /// A structural condition (budget, offline, an ended window) refuses work until `retryAt`; no attempt spent.
        case deferred(retryAt: Double)
        /// It will not be attempted again. The reason is kept so a run can state why.
        case exhausted(Reason)
    }

    /// Why a revision is exhausted. None of them is a silent failure: each one is a decision a run can read.
    public enum Reason: Hashable, Sendable {
        /// The attempt budget was spent on transient failures.
        case attemptsSpent
        /// The card declared a card image and no candidate could supply a usable one.
        case mediaInvalid
        /// It was published through another path (or the edition moved past it), so it must not compete again.
        case superseded
    }

    /// What one attempt concluded, in the terms the phase machine reads.
    public enum SettleOutcome: Hashable, Sendable {
        /// A presentation exists. `hasImage == false` is a legitimate text card, not a failure.
        case prepared(hasImage: Bool)
        /// Network, 5xx, a lost connection, the wait running out: an attempt was spent.
        case transientFailure
        /// The declared media is unusable (missing, not an image, over the ceiling): exhausted at once.
        case definitiveFailure
        /// Offline, thermally forbidden, no budget: nothing was attempted, so nothing is spent.
        case conditionsUnavailable
    }

    /// What the reserve currently holds, stated as counts and bytes — never as the cards themselves.
    public struct Snapshot: Hashable, Sendable {
        public let ready: Int
        public let preparing: Int
        public let pending: Int
        public let deferred: Int
        public let exhausted: Int
        public let published: Int
        /// The assets the revisions **still in the reserve** retain on disk, as reported by their settlements. A
        /// revision that is published or exhausted releases its share: its persisted file stays where the existing
        /// retention rules put it, but it no longer consumes the reserve's budget.
        public let persistedBytes: Int
        /// Settles `.prepared` that arrived for a revision that was not `.preparing`: completions past a window.
        public let lateCompletions: Int
        /// Attempts whose window ended while the prefetcher still owns them. They hold capacity until their outcome
        /// arrives, so a closed window cannot free the slots of work that is still downloading.
        public let outstanding: Int
        /// Published cards whose revision came from the durable deferral page — the stories the one-way walk had
        /// skipped for want of media and reconsideration recovered (PM-028A/PM-029).
        public let reconsideredPublished: Int
        /// Of those, the ones that published **with** an image.
        public let reconsideredWithImage: Int

        public init(ready: Int, preparing: Int, pending: Int, deferred: Int, exhausted: Int, published: Int,
            persistedBytes: Int, lateCompletions: Int, reconsideredPublished: Int, reconsideredWithImage: Int,
            outstanding: Int = 0) {
            self.ready = ready
            self.preparing = preparing
            self.pending = pending
            self.deferred = deferred
            self.exhausted = exhausted
            self.published = published
            self.persistedBytes = persistedBytes
            self.lateCompletions = lateCompletions
            self.reconsideredPublished = reconsideredPublished
            self.reconsideredWithImage = reconsideredWithImage
            self.outstanding = outstanding
        }
    }

    /// How many prepared presentations the reserve tries to hold.
    private let targetDepth: Int
    /// The depth at which topping up **begins** again: between this and `targetDepth` the reserve is in its dead
    /// band and asks for no new work, so a reader who walks a card or two does not start a download per card.
    private let lowWaterMark: Int
    private let maxAttempts: Int
    private let persistedByteBudget: Int
    private let retryDelays: [Double]
    private let clock: @Sendable () -> Double

    /// The explicit state of every revision this reserve has been told about. A missing entry is an implicit
    /// `.pending`; `plan` materialises that entry when it emits the revision, so counts stay honest.
    private var phases: [OriginRevisionID: Phase] = [:]
    /// Attempts already spent per revision (PM-028A §2 rule 1 reads this, never the caller's attempt index alone).
    private var spentAttempts: [OriginRevisionID: Int] = [:]
    /// The persisted bytes **each** revision in the reserve holds, so a revision that leaves the reserve can hand
    /// its share back. The asset itself is untouched by that release: the existing retention rules own the file.
    private var retainedBytesByRevision: [OriginRevisionID: Int] = [:]
    /// The retained total the budget reads: the sum of what the revisions currently in the reserve reported.
    private var retainedBytes = 0
    private var lateCompletions = 0
    /// Revisions the durable deferral page offered (PM-028A/PM-029): a story the one-way walk skipped for want of
    /// media, which this reserve therefore had to recover rather than meet in its structural window.
    private var reconsidered: Set<OriginRevisionID> = []
    private var reconsideredPublished = 0
    private var reconsideredWithImage = 0
    /// Hysteresis latch: set when topping up begins, cleared when the target depth is reached. Kept in the actor
    /// because the band has no meaning between two independent calls.
    private var refilling = false
    /// Attempts whose window ended while the prefetcher still owns them (PM-028A §4.3): the download outlived the
    /// slice that authorised it, so its slot stays taken until the outcome arrives. Without this, a closed window
    /// freed every slot at once and the next opportunity authorised a second full batch over running work.
    private var outstanding: Set<OriginRevisionID> = []
    /// Opportunities refused at the target depth since the last publication. Prepared depth must not permanently veto
    /// the work that unblocks selection (PD-4), so one refusal is treated as "a publication may still be on its way"
    /// and a second one authorises a bounded batch above the target (see `plan`).
    private var depthRefusals = 0
    /// The bounded set one opportunity may authorise above the target when the prepared reserve cannot be published.
    /// It is the reader's forward window (16): enough to reach another source, never a second reserve.
    private let unblockingBatch = 16

    public init(targetDepth: Int = 96, lowWaterMark: Int = 64, maxAttempts: Int = 3,
        persistedByteBudget: Int = 96 << 20, retryDelays: [Double] = [1, 4, 16],
        now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        // The parameters are the PM's initial numbers, not guarantees (PM-028A §4.3). They are made coherent here
        // rather than trusted: a low water mark above the target would never stop asking, and a zero ceiling would
        // refuse the first attempt forever.
        self.targetDepth = max(0, targetDepth)
        self.lowWaterMark = max(0, min(lowWaterMark, max(0, targetDepth)))
        self.maxAttempts = max(1, maxAttempts)
        self.persistedByteBudget = max(0, persistedByteBudget)
        self.retryDelays = retryDelays.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        self.clock = now
    }

    /// Which revisions deserve work now, in the order received, stopping when the reserve would hold `targetDepth`
    /// prepared presentations.
    ///
    /// Only `.pending` and `.deferred` whose `retryAt` has passed are emitted; `.ready`, `.preparing`, `.published`
    /// and `.exhausted` never are. When the retained-byte budget is exhausted nothing new is emitted — and nothing
    /// already ready is dropped: evicting a prepared presentation would demand re-materialising it, which is phase 2
    /// and not this delivery.
    ///
    /// `targetDepth` counts **authorised work**, not only what is already prepared: a revision with an attempt in
    /// flight, or one whose window closed while the prefetcher still owns it (`windowClosed(_:outstanding:)`), takes
    /// its slot until the outcome arrives. Counting `.ready` alone let a window close and free all 96 slots while 96
    /// downloads were still running, so the next opportunity authorised another full batch on top of them.
    ///
    /// Prepared depth must not permanently veto the work that unblocks selection (PD-4). When the reserve is full and
    /// two consecutive opportunities are refused at the target depth with no publication in between, one bounded
    /// batch (`unblockingBatch`) is authorised above it. That is the deadlock where the edition tail shares a source
    /// with every ready revision: `MaximumDistanceSequencing` holds them all, nothing publishes, nothing is marked
    /// published, and without this the reserve could never drain.
    public func plan(offer: [OriginRevisionID]) -> [OriginRevisionID] {
        var readyCount = 0, preparingCount = 0
        for phase in phases.values {
            switch phase {
            case .ready: readyCount += 1
            case .preparing: preparingCount += 1
            default: break
            }
        }
        // What this reserve has authorised and has not seen conclude: prepared, in flight, and still owned by the
        // prefetcher after its window ended.
        let admitted = readyCount + preparingCount + outstanding.count
        guard targetDepth > 0 else {
            refilling = false
            return []
        }
        let full = readyCount >= targetDepth
        if full, depthRefusals == 0 {
            // The first refusal states the observation and waits: a publication of what is already ready may be on its
            // way, and authorising more before it concludes is how the reserve would overshoot.
            depthRefusals += 1
            refilling = false
            return []
        }
        // A second refusal with nothing published: the prepared reserve cannot be placed right now, so the depth may
        // not keep refusing the work that would unblock selection. Bounded by the forward window.
        let unblocking = full
        let ceiling = unblocking ? targetDepth + unblockingBatch : targetDepth
        // The budget refuses new work. `.pending` stays `.pending`, so the revision is reconsidered when room exists.
        guard retainedBytes < persistedByteBudget else { return [] }
        // Hysteresis: while the reserve is in its dead band and no top-up is under way, this opportunity adds nothing.
        guard unblocking || refilling || admitted <= lowWaterMark else { return [] }
        if !unblocking { refilling = true }
        let now = clock()
        var planned: [OriginRevisionID] = []
        var seen = Set<OriginRevisionID>()
        for revision in offer {
            guard admitted + planned.count < ceiling else { break }
            guard retainedBytes < persistedByteBudget else { break }
            guard seen.insert(revision).inserted else { continue }
            switch phases[revision] {
            case .none:
                phases[revision] = .pending
                planned.append(revision)
            case .pending?:
                planned.append(revision)
            case .deferred(let retryAt)? where retryAt <= now:
                planned.append(revision)
            case .deferred?, .preparing?, .ready?, .published?, .exhausted?:
                continue
            }
        }
        // Authorising work answers the observation; the next refusal starts the count again.
        if !planned.isEmpty { depthRefusals = 0 }
        return planned
    }

    /// Work for this revision started (or is about to). Idempotent: repeating the same attempt changes nothing, and
    /// a revision that is already ready, published or exhausted is never pulled back into work.
    ///
    /// The attempt index is the caller's statement of which attempt this is; the spend count the policy reads stays
    /// private and only ever grows, so a caller that always names attempt zero cannot retry forever.
    public func markPreparing(_ revision: OriginRevisionID, attempt: Int) {
        switch phases[revision] ?? .pending {
        case .published, .exhausted, .ready:
            return
        case .preparing(let current) where current == max(0, attempt):
            return
        case .pending, .deferred, .preparing:
            let index = max(0, attempt)
            spentAttempts[revision] = max(spentAttempts[revision] ?? 0, index)
            phases[revision] = .preparing(attempt: index)
        }
    }

    /// The window that started these attempts ended at its deadline without a decision, while their work is still
    /// owned by the prefetcher. They return to `.deferred` (nothing was decided, so no attempt is spent), which is
    /// what makes the completion that arrives later a **late** completion instead of an unobservable one.
    ///
    /// `outstanding` are the revisions whose work the prefetcher still owns: it outlived the window and will settle
    /// them, so they keep their slot until that outcome arrives. A revision this window marked `.preparing` that is
    /// **not** outstanding attempted nothing the prefetcher will answer for — it refused it (a cooling backoff, a
    /// revision already settled) — and returns to waiting without holding capacity.
    public func windowClosed(_ revisions: [OriginRevisionID], outstanding: Set<OriginRevisionID> = []) {
        let retryAt = clock() + retryDelay(afterSpent: 1)
        for revision in revisions {
            guard case .preparing? = phases[revision] else { continue }
            phases[revision] = .deferred(retryAt: retryAt)
            if outstanding.contains(revision) { self.outstanding.insert(revision) }
        }
    }

    /// One attempt's conclusion. Idempotent, and accepted even for a revision no `markPreparing` announced (the
    /// prefetch may conclude before its record exists). Returns `false` when nothing changed, so a caller can state
    /// the discard — `.published` and `.exhausted` ignore every later settlement, and a prepared presentation is
    /// never taken back.
    @discardableResult
    public func settle(_ revision: OriginRevisionID, outcome: SettleOutcome, persistedBytes: Int = 0) -> Bool {
        let current = phases[revision] ?? .pending
        switch current {
        case .published, .exhausted, .ready:
            // Ready is settled too: its bytes are on disk and publication may already be reading them. Nothing
            // unsettles it — not a slower failure, not a duplicate completion.
            return false
        case .pending, .preparing, .deferred:
            // Whatever the attempt concluded, its slot is answerable from here on.
            outstanding.remove(revision)
            switch outcome {
            case .prepared(let hasImage):
                let wasPreparing: Bool = if case .preparing = current { true } else { false }
                phases[revision] = .ready(hasImage: hasImage)
                // The budget reads what the revisions **still in the reserve** hold. Nothing unsettles a ready
                // revision, so its share is written once; `markPublished`/exhaustion hands it back.
                let bytes = max(0, persistedBytes)
                retainedBytesByRevision[revision] = bytes
                retainedBytes += bytes
                if !wasPreparing { lateCompletions += 1 }
                return true
            case .transientFailure:
                // PM-028A §2 rule 1: the attempt is spent; the last one exhausts instead of retrying forever.
                let spent = (spentAttempts[revision] ?? 0) + 1
                spentAttempts[revision] = spent
                if spent < maxAttempts {
                    phases[revision] = .deferred(retryAt: clock() + retryDelay(afterSpent: spent))
                } else {
                    phases[revision] = .exhausted(.attemptsSpent)
                    releaseRetainedBytes(revision)
                }
                return true
            case .definitiveFailure:
                // Rule 2: declared media that cannot be prepared is final on the first answer, and spending attempts
                // on it would delay the rest of the same offer.
                phases[revision] = .exhausted(.mediaInvalid)
                releaseRetainedBytes(revision)
                return true
            case .conditionsUnavailable:
                // Rule 3: nothing was attempted, so nothing is spent; the first backoff bounds the next ask.
                phases[revision] = .deferred(retryAt: clock() + retryDelay(afterSpent: 1))
                return true
            }
        }
    }

    /// The revision left in an edition. A ready revision becomes `.published`; anything else that was still waiting
    /// to compete was published through another path and is `.exhausted(.superseded)` — one publication per
    /// revision, and a published revision never comes back to the reserve.
    ///
    /// Leaving the reserve releases that revision's share of the persisted-byte budget (PM-028A §4.2 governs
    /// prepared-but-unpublished asset): the file stays exactly where the existing retention rules put it, and the
    /// reserve stops counting it, so a long session cannot fill the budget with cards the reader already has.
    public func markPublished(_ revision: OriginRevisionID) {
        // A publication is the drain the depth policy waits for: the observation that nothing can be placed ends
        // here, whatever the revision's own phase was.
        depthRefusals = 0
        outstanding.remove(revision)
        switch phases[revision] ?? .pending {
        case .ready(let hasImage):
            phases[revision] = .published
            if reconsidered.remove(revision) != nil {
                reconsideredPublished += 1
                if hasImage { reconsideredWithImage += 1 }
            }
            releaseRetainedBytes(revision)
        case .published, .exhausted:
            return
        case .pending, .preparing, .deferred:
            phases[revision] = .exhausted(.superseded)
            reconsidered.remove(revision)
            releaseRetainedBytes(revision)
        }
    }

    /// The revisions a durable deferral page offered this cycle: stories the one-way walk skipped while their media
    /// was pending, which only reconsideration can bring back (PM-028A/PM-029). Marking is session-scoped and only
    /// ever feeds the two comparison counters; no decision reads it.
    public func noteReconsidered(_ revisions: [OriginRevisionID]) {
        for revision in revisions {
            // A revision the reserve already published cannot be "recovered and published" a second time.
            if case .published? = phases[revision] { continue }
            reconsidered.insert(revision)
        }
    }

    /// Hands a revision's retained share back to the budget. The persisted asset is untouched: eviction belongs to
    /// the existing retention rules, never to this accounting.
    private func releaseRetainedBytes(_ revision: OriginRevisionID) {
        guard let bytes = retainedBytesByRevision.removeValue(forKey: revision) else { return }
        retainedBytes = max(0, retainedBytes - bytes)
    }

    public func markPublished(_ revisions: [OriginRevisionID]) {
        for revision in revisions { markPublished(revision) }
    }

    /// The explicit phase of one revision; `.pending` for one this reserve was never told about.
    public func phase(of revision: OriginRevisionID) -> Phase {
        phases[revision] ?? .pending
    }

    public func snapshot() -> Snapshot {
        var ready = 0, preparing = 0, pending = 0, deferred = 0, exhausted = 0, published = 0
        for phase in phases.values {
            switch phase {
            case .pending: pending += 1
            case .preparing: preparing += 1
            case .ready: ready += 1
            case .deferred: deferred += 1
            case .exhausted: exhausted += 1
            case .published: published += 1
            }
        }
        return Snapshot(ready: ready, preparing: preparing, pending: pending, deferred: deferred,
            exhausted: exhausted, published: published, persistedBytes: retainedBytes,
            lateCompletions: lateCompletions, reconsideredPublished: reconsideredPublished,
            reconsideredWithImage: reconsideredWithImage, outstanding: outstanding.count)
    }

    /// The delay that follows the attempt that spent count `spent` (one-based). A revision whose failures outlast
    /// the stated curve keeps using its longest delay instead of inventing a new one; an empty curve retries at once.
    private func retryDelay(afterSpent spent: Int) -> Double {
        guard !retryDelays.isEmpty else { return 0 }
        return retryDelays[min(max(0, spent - 1), retryDelays.count - 1)]
    }
}
