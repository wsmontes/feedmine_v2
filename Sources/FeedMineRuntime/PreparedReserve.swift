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
/// only (`persistedBytes`, the size of the materialised asset the revision already has on disk). It holds no
/// decoded-image memory and no in-flight download: those two belong to `MediaReadiness` and `MediaPrefetcher`, and
/// counting them here would be a second, diverging measurement of the same work.
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
        /// The assets this reserve's revisions retain on disk, as reported by their settlements.
        public let persistedBytes: Int
        /// Settles `.prepared` that arrived for a revision that was not `.preparing`: completions past a window.
        public let lateCompletions: Int

        public init(ready: Int, preparing: Int, pending: Int, deferred: Int, exhausted: Int, published: Int,
            persistedBytes: Int, lateCompletions: Int) {
            self.ready = ready
            self.preparing = preparing
            self.pending = pending
            self.deferred = deferred
            self.exhausted = exhausted
            self.published = published
            self.persistedBytes = persistedBytes
            self.lateCompletions = lateCompletions
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
    private var retainedBytes = 0
    private var lateCompletions = 0
    /// Hysteresis latch: set when topping up begins, cleared when the target depth is reached. Kept in the actor
    /// because the band has no meaning between two independent calls.
    private var refilling = false

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
    public func plan(offer: [OriginRevisionID]) -> [OriginRevisionID] {
        let readyCount = phases.values.reduce(into: 0) { count, phase in
            if case .ready = phase { count += 1 }
        }
        guard readyCount < targetDepth else {
            refilling = false
            return []
        }
        // The budget refuses new work. `.pending` stays `.pending`, so the revision is reconsidered when room exists.
        guard retainedBytes < persistedByteBudget else { return [] }
        // Hysteresis: while the reserve is in its dead band and no top-up is under way, this opportunity adds nothing.
        guard refilling || readyCount <= lowWaterMark else { return [] }
        refilling = true
        let now = clock()
        var planned: [OriginRevisionID] = []
        var seen = Set<OriginRevisionID>()
        for revision in offer {
            guard readyCount + planned.count < targetDepth else { break }
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
    public func windowClosed(_ revisions: [OriginRevisionID]) {
        let retryAt = clock() + retryDelay(afterSpent: 1)
        for revision in revisions {
            guard case .preparing? = phases[revision] else { continue }
            phases[revision] = .deferred(retryAt: retryAt)
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
            switch outcome {
            case .prepared(let hasImage):
                let wasPreparing: Bool = if case .preparing = current { true } else { false }
                phases[revision] = .ready(hasImage: hasImage)
                retainedBytes += max(0, persistedBytes)
                if !wasPreparing { lateCompletions += 1 }
                return true
            case .transientFailure:
                // PM-028A §2 rule 1: the attempt is spent; the last one exhausts instead of retrying forever.
                let spent = (spentAttempts[revision] ?? 0) + 1
                spentAttempts[revision] = spent
                phases[revision] = spent < maxAttempts
                    ? .deferred(retryAt: clock() + retryDelay(afterSpent: spent))
                    : .exhausted(.attemptsSpent)
                return true
            case .definitiveFailure:
                // Rule 2: declared media that cannot be prepared is final on the first answer, and spending attempts
                // on it would delay the rest of the same offer.
                phases[revision] = .exhausted(.mediaInvalid)
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
    public func markPublished(_ revision: OriginRevisionID) {
        switch phases[revision] ?? .pending {
        case .ready:
            phases[revision] = .published
        case .published, .exhausted:
            return
        case .pending, .preparing, .deferred:
            phases[revision] = .exhausted(.superseded)
        }
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
            lateCompletions: lateCompletions)
    }

    /// The delay that follows the attempt that spent count `spent` (one-based). A revision whose failures outlast
    /// the stated curve keeps using its longest delay instead of inventing a new one; an empty curve retries at once.
    private func retryDelay(afterSpent spent: Int) -> Double {
        guard !retryDelays.isEmpty else { return 0 }
        return retryDelays[min(max(0, spent - 1), retryDelays.count - 1)]
    }
}
