// Owns: the durable memory of stories a publication opportunity skipped because their media was still pending.
// Does not own: readiness facts, selection order, publication or scheduling.

import Foundation
import FeedMineDomain
import FeedMineEditorial
import FeedMinePersistence

/// The structural walk is one-way. `LocalProductionSlice` states it: examination advances through supply and a
/// revision it passed is never examined again by that cursor. A story whose media was still pending when the walk
/// passed it therefore never reaches selection again — measured in production: 1,508 revisions reached ready-image,
/// 29 were published, and none of the 1,508 had a sort date ahead of the published cursor.
///
/// This type is the one memory of that skip, and it lives in durable supply (`MediaDeferralStore`). It is not a
/// second walk: an entry only restores the *possibility* of selection for a story the walk already judged
/// unexaminable. Selection's own rules (recency, diversity, source alternation, exposure, PD-4) still decide what is
/// placed; nothing here ranks, mixes or reserves a position.
///
/// Bound, stated: `ceiling` entries per opportunity. That is a work page, never eligibility — the store rotates the
/// page by the oldest admission/offer so continuous arrivals cannot starve an older revision. Every association
/// survives a relaunch. A row leaves only when its skip is definitively settled: published, no longer in supply,
/// superseded, filtered out, or decided with no presentation at all.
public final class PendingMediaReconsideration: @unchecked Sendable {
    /// How many deferred rows one opportunity offers. Operational, not a product limit.
    public static let defaultCeiling = 32

    /// One story a publication opportunity could not select because its media was pending.
    public struct Entry: Hashable, Sendable {
        /// The Edition whose walk skipped it. An entry outlives that walk only as long as that Edition owns it.
        public let editionID: FeedEditionID
        public let originRecordID: OriginRecordID
        /// The revision the skip was about: a newer revision of the same origin is a different story.
        public let originRevisionID: OriginRevisionID

        public init(editionID: FeedEditionID, originRecordID: OriginRecordID,
            originRevisionID: OriginRevisionID) {
            self.editionID = editionID
            self.originRecordID = originRecordID
            self.originRevisionID = originRevisionID
        }
    }

    private let lock = NSLock()
    public let ceiling: Int
    private let store: MediaDeferralStore

    public init(database: RuntimeDatabase, ceiling: Int = PendingMediaReconsideration.defaultCeiling) {
        self.ceiling = max(1, ceiling)
        store = MediaDeferralStore(database: database)
    }

    /// Every deferred row across Editions. Diagnostics and tests only; no decision reads it.
    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return (try? store.count()) ?? 0
    }

    /// Records every skip in one write. A revision already deferred keeps its first instant and its place in the
    /// rotation: re-recording the same skip must not let one long-pending story outlive every entry behind it.
    public func remember(_ entries: some Sequence<Entry>, at date: Date = Date()) throws {
        let records = entries.map { entry in
            MediaDeferralRecord(editionID: entry.editionID, originRecordID: entry.originRecordID,
                originRevisionID: entry.originRevisionID)
        }
        guard !records.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        try store.record(records, at: date)
    }

    /// One bounded work page of `editionID`'s deferred rows, longest-waiting first, rotated so the next opportunity
    /// sees the rows behind this page. The page is the only quantity the opportunity is charged for.
    public func entries(for editionID: FeedEditionID, at date: Date = Date()) throws -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return try store.page(editionID: editionID, limit: ceiling, offerAt: date).map {
            Entry(editionID: $0.editionID, originRecordID: $0.originRecordID,
                originRevisionID: $0.originRevisionID)
        }
    }

    /// The same rows without rotating them: the media opportunity uses this to prepare deferred stories (including
    /// after a relaunch) without consuming their place in the offer rotation.
    public func pendingEntries(for editionID: FeedEditionID, limit: Int) throws -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return try store.page(editionID: editionID, limit: limit, offerAt: nil).map {
            Entry(editionID: $0.editionID, originRecordID: $0.originRecordID,
                originRevisionID: $0.originRevisionID)
        }
    }

    /// Drops entries an opportunity has definitively settled: published, no longer in supply, superseded, or
    /// decided with no presentation. A forgotten entry is not offered again; the story is reachable only through
    /// whatever supply rule brings it back. Best effort on purpose: failing to forget can only cause another
    /// offer, which selection and exposure reject; it must never fail a publication that already committed.
    public func forget(_ entries: some Sequence<Entry>) {
        let records = entries.map { entry in
            MediaDeferralRecord(editionID: entry.editionID, originRecordID: entry.originRecordID,
                originRevisionID: entry.originRevisionID)
        }
        guard !records.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        try? store.forget(records)
    }
}

/// The one implementation of "what did this walk skip, and what may it offer now" — used by the first Edition and by
/// every later local slice, so both read the same durable rows by the same rules.
enum MediaSkippedSupply {
    struct Reconsidered {
        var candidates: [Candidate] = []
        var considered: [PendingMediaReconsideration.Entry] = []
    }

    /// The stories the one-way walk already passed whose media became ready since.
    ///
    /// Ordering rule, and why it was chosen: the store page is offered longest-waiting first, and those candidates
    /// are placed **before** the structural ones in the window (array position is not the decision: SelectionEngine
    /// orders every candidate by its own total comparator, and it does not read array position). The queue's only
    /// claim is that a skipped story may be selected at all; where it lands is the editorial sequencing's decision
    /// (recency, diversity, PD-4). Keeping the reconsidered set in its own slot is what keeps the structural
    /// window's own count and cursor the facts the opportunity reports: a re-offer can publish a card or leave the
    /// queue, but it can never move the walk or take the position of a candidate the walk produced. There is no
    /// quota and no mixing rule: the bound is the store's page, and everything ready in it is offered to the one
    /// selection.
    static func reconsider(provider: CandidateProvider, plan: FeedPlan, editionID: FeedEditionID,
        structural: CandidateSupplyWindow, readiness: MediaReadiness?,
        reoffer: PendingMediaReconsideration?) throws -> Reconsidered {
        guard let readiness, let reoffer else { return Reconsidered() }
        let queued = try reoffer.entries(for: editionID)
        guard !queued.isEmpty else { return Reconsidered() }
        let presentations = readiness.presentations(for: queued.map(\.originRevisionID))
        // A queued revision with no presentation is still pending: it stays queued for a later opportunity. One
        // whose media was *decided* without a presentation (a declared image that could not be prepared) can never
        // become a card under this identity, so it leaves the durable memory instead of being retried forever.
        let decidedWithoutPresentation = queued.filter {
            presentations[$0.originRevisionID] == nil && readiness.isSettled($0.originRevisionID)
        }
        reoffer.forget(decidedWithoutPresentation)
        let ready = queued.filter { presentations[$0.originRevisionID] != nil }
        guard !ready.isEmpty else { return Reconsidered() }
        let resolution = try resolve(ready, provider: provider, plan: plan)
        // Superseded, withdrawn or filtered out: these skips can never be published under the identity the queue
        // remembers, so they are stated as gone instead of being carried into every future opportunity.
        reoffer.forget(resolution.gone)
        let structuralOrigins = Set(structural.candidates.map(\.originRecordID))
        var result = Reconsidered()
        for (entry, candidate) in resolution.ready {
            result.considered.append(entry)
            // When the walk still holds the origin, its candidate is the one that participates; the entry was not
            // a skip after all.
            guard !structuralOrigins.contains(entry.originRecordID) else { continue }
            result.candidates.append(candidate)
        }
        return result
    }

    /// Records, once per opportunity, the stories this walk could not offer for want of media. A revision whose
    /// media was *decided* (prepared, declared text, or definitively unavailable) is never remembered: only a
    /// pending decision can still turn into a presentation, and only that transition reopens the queue.
    static func remember(structural: CandidateSupplyWindow, editionID: FeedEditionID,
        publishedOriginIDs: Set<OriginRecordID>, readiness: MediaReadiness?,
        reoffer: PendingMediaReconsideration?) throws {
        guard let readiness, let reoffer else { return }
        var entries: [PendingMediaReconsideration.Entry] = []
        for candidate in structural.candidates {
            guard !publishedOriginIDs.contains(candidate.originRecordID),
                !readiness.isSettled(candidate.originRevisionID) else { continue }
            entries.append(.init(editionID: editionID,
                originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID))
        }
        try reoffer.remember(entries)
    }

    struct Resolution {
        /// Ready entries still carried by supply at the revision that was skipped, in queue order.
        let ready: [(entry: PendingMediaReconsideration.Entry, candidate: Candidate)]
        /// Entries that can never be published under this identity: the revision is no longer the origin's
        /// current one (expired), the origin left supply, or this context's filters exclude it.
        let gone: [PendingMediaReconsideration.Entry]
    }

    static func resolve(_ entries: [PendingMediaReconsideration.Entry], provider: CandidateProvider,
        plan: FeedPlan) throws -> Resolution {
        guard !entries.isEmpty else { return Resolution(ready: [], gone: []) }
        // The bounded exact lookup the hidden tail already uses: the walk's cursor is not involved, so the skip is
        // resolved without moving — or rewinding — any structural position.
        let window = try provider.candidates(for: plan, after: nil, examinedCapacity: entries.count,
            originIDs: entries.map(\.originRecordID))
        let byOrigin = Dictionary(uniqueKeysWithValues: window.candidates.map { ($0.originRecordID, $0) })
        var ready: [(entry: PendingMediaReconsideration.Entry, candidate: Candidate)] = []
        var gone: [PendingMediaReconsideration.Entry] = []
        for entry in entries {
            guard let candidate = byOrigin[entry.originRecordID],
                candidate.originRevisionID == entry.originRevisionID else {
                gone.append(entry)
                continue
            }
            ready.append((entry, candidate))
        }
        return Resolution(ready: ready, gone: gone)
    }
}
