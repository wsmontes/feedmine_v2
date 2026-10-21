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
/// Bound, stated: `ceiling` rows per work page, and one page per reconsideration opportunity. That is a work
/// bound, never eligibility: a pass advances page by page inside the one authorization that stated the readiness
/// fact, and stops at the first page holding a presentable revision, so a row behind the page is reached by the
/// same opportunity. A row leaves only when its skip is definitively settled: published, no longer in supply,
/// superseded, filtered out, or decided with no presentation at all.
public final class PendingMediaReconsideration: @unchecked Sendable {
    /// How many deferred rows one page of a pass reads. Operational, not a product limit.
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

    /// One page of the current pass.
    public struct ReviewPage: Sendable {
        public let entries: [Entry]
        /// Where the pass continues; nil when this page ended the durable queue.
        public let next: MediaDeferralCursor?
    }

    private let lock = NSLock()
    public let ceiling: Int
    private let store: MediaDeferralStore
    /// Position inside the current pass, and the Edition that pass belongs to. The rows are durable; this only says
    /// which one the same owner reads next, so an opportunity that stops early leaves every row where it was.
    private var reviewCursor: MediaDeferralCursor?
    private var reviewEdition: FeedEditionID?

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
    /// pass order: re-recording the same skip must not let one long-pending story outlive every entry behind it.
    public func remember(_ entries: some Sequence<Entry>, at date: Date = Date()) throws {
        let records = entries.map { entry in
            MediaDeferralRecord(editionID: entry.editionID, originRecordID: entry.originRecordID,
                originRevisionID: entry.originRevisionID)
        }
        guard !records.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        try store.record(records, at: date)
    }

    /// Starts a new pass from the first durable row. A readiness fact is the trigger: the new fact must be able to
    /// see rows the previous pass already passed, otherwise a story that became ready just behind the last page
    /// would wait for a pass that never restarts.
    public func beginReviewPass() {
        lock.lock(); defer { lock.unlock() }
        reviewCursor = nil
        reviewEdition = nil
    }

    /// One bounded page of the current pass, in deferral order. The caller reviews this page and reports whether the
    /// pass continues; no other reader and no other walk is involved.
    public func reviewPage(for editionID: FeedEditionID) throws -> ReviewPage {
        lock.lock(); defer { lock.unlock() }
        if reviewEdition != editionID {
            reviewCursor = nil
            reviewEdition = editionID
        }
        let page = try store.passPage(editionID: editionID, limit: ceiling, after: reviewCursor)
        reviewCursor = page.next
        return ReviewPage(entries: page.records.map {
            Entry(editionID: $0.editionID, originRecordID: $0.originRecordID,
                originRevisionID: $0.originRevisionID)
        }, next: page.next)
    }

    /// The media opportunity's preparation page: the same rows, rotating, so successive drives prepare the rows
    /// behind the last page instead of the same prefix forever. A relaunch has no readiness facts, so this rotation
    /// is what lets preparation reach every deferred story again. Preparation is not an offer and never evicts.
    public func pendingEntries(for editionID: FeedEditionID, limit: Int, at date: Date = Date()) throws -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return try store.page(editionID: editionID, limit: limit, offerAt: date).map {
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
        /// True when this page ended without a presentable revision while rows remained behind it: the same
        /// authorization still owes the next page.
        var continues = false
    }

    /// The stories the one-way walk already passed whose media became ready since.
    ///
    /// Ordering rule, and why it was chosen: the queue is offered longest-waiting first, and those candidates join
    /// the window **after** the structural ones. The queue's only claim is that a skipped story may be selected at
    /// all; where it lands is the editorial sequencing's decision (recency, diversity, PD-4), which orders the
    /// window's candidates and does not read their array position. Appending rather than interleaving is what keeps
    /// the structural window's own count and cursor the facts the opportunity reports: a re-offer can publish a card
    /// or leave the queue, but it can never move the walk or take the position of a candidate the walk produced.
    /// There is no quota and no mixing rule: one page of the durable pass is reviewed here, and every presentable
    /// revision in it is offered to the one selection. A page that ends without a presentable revision reports the
    /// continuation instead of turning the page: the same authorized opportunity owes the rows behind it.
    static func reconsider(provider: CandidateProvider, plan: FeedPlan, editionID: FeedEditionID,
        structural: CandidateSupplyWindow, readiness: MediaReadiness?,
        reoffer: PendingMediaReconsideration?) throws -> Reconsidered {
        guard let readiness, let reoffer else { return Reconsidered() }
        let page = try reoffer.reviewPage(for: editionID)
        guard !page.entries.isEmpty else { return Reconsidered() }
        // One complete decision per row, taken under the index's own lock. Reading the presentation snapshot and
        // then asking about settlement let a media transition land between the two reads: the row was absent from
        // the snapshot, decided a moment later, and erased as if its image could never be presented.
        var decisions: [(entry: PendingMediaReconsideration.Entry, decision: MediaReadinessDecision)] = []
        decisions.reserveCapacity(page.entries.count)
        for entry in page.entries {
            decisions.append((entry, readiness.decision(for: entry.originRevisionID)))
        }
        // A pending row is not gone: only a revision whose media was decided with no presentation at all can never
        // become a card under this identity, so only that one leaves the durable memory here.
        reoffer.forget(decisions.filter { $0.decision == .decidedWithoutPresentation }.map { $0.entry })
        let ready = decisions.filter { $0.decision == .presentable }.map { $0.entry }
        var result = Reconsidered()
        result.continues = ready.isEmpty && page.next != nil
        guard !ready.isEmpty else { return result }
        let resolution = try resolve(ready, provider: provider, plan: plan)
        // Superseded, withdrawn or filtered out: these skips can never be published under the identity the queue
        // remembers, so they are stated as gone instead of being carried into every future opportunity.
        reoffer.forget(resolution.gone)
        let structuralOrigins = Set(structural.candidates.map(\.originRecordID))
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
                readiness.decision(for: candidate.originRevisionID) == .pending else { continue }
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
