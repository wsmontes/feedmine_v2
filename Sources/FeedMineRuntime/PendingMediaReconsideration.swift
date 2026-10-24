// Owns: the bounded memory of stories a publication opportunity skipped because their media was still pending.
// Does not own: readiness facts, selection order, publication or scheduling.

import Foundation
import FeedMineDomain
import FeedMineEditorial

/// The structural walk is one-way. `LocalProductionSlice` states it: examination advances through supply and a
/// revision it passed is never examined again by that cursor. A story whose media was still pending when the walk
/// passed it therefore never reaches selection again — measured in production: 1,508 revisions reached ready-image,
/// 29 were published, and none of the 1,508 had a sort date ahead of the published cursor.
///
/// This queue is the one memory of that skip. It is deliberately finite, and it is not a second walk: an entry only
/// restores the *possibility* of selection for a story the walk already judged unexaminable. Selection's own rules
/// (recency, diversity, source alternation, exposure, PD-4) still decide what is placed; nothing here ranks, mixes
/// or reserves a position.
///
/// Bound, stated: `defaultCeiling` entries. An entry whose media never settles is evicted by the skips that follow
/// it — the queue keeps the most recent skips, because readiness is what reopens the queue and the media work that
/// can still settle is the work most recently examined.
public final class PendingMediaReconsideration: @unchecked Sendable {
    /// The stated ceiling. A finite queue is what keeps the re-offer from becoming an unbounded second supply: at
    /// most this many stories can be re-offered per Edition, however long the media pipeline runs.
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
    /// Oldest skip first: the entry that has waited longest is the one the ceiling would otherwise make
    /// permanently unreachable, so it is offered first.
    private var queue: [Entry] = []

    public init(ceiling: Int = PendingMediaReconsideration.defaultCeiling) {
        self.ceiling = max(1, ceiling)
    }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return queue.count
    }

    /// Records one skip. A revision already queued keeps its place: the first skip is when the story became
    /// unreachable, and re-recording the same skip must not refresh its position (that would let one long-pending
    /// story outlive every entry behind it).
    public func remember(_ entry: Entry) {
        lock.lock(); defer { lock.unlock() }
        // One association serves one Edition at a time: anything queued by another Edition belongs to a walk this
        // process no longer runs, so it is dead weight the ceiling must not carry.
        queue.removeAll { $0.editionID != entry.editionID }
        guard !queue.contains(entry) else { return }
        while queue.count >= ceiling { queue.removeFirst() }
        queue.append(entry)
    }

    /// The entries `editionID` may still re-offer, oldest skip first.
    ///
    /// Entries belonging to another Edition are discarded here: an Edition only publishes through its own walk, and
    /// a walk this process no longer serves cannot offer them. That is the "exhausted Edition" case — the queue
    /// keeps no reachability for a publication that no longer exists.
    public func entries(for editionID: FeedEditionID) -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        queue.removeAll { $0.editionID != editionID }
        return queue
    }

    /// Drops entries an opportunity has settled: published, no longer in supply, superseded, filtered out, or
    /// already judged by selection. A forgotten entry is not offered again; the story is reachable only through
    /// whatever supply rule brings it back.
    public func forget(_ entries: some Sequence<Entry>) {
        let dropped = Set(entries)
        guard !dropped.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        queue.removeAll { dropped.contains($0) }
    }
}

/// The one implementation of "what did this walk skip, and what may it offer now" — used by the first Edition and by
/// every later local slice, so both read the same queue by the same rules.
enum MediaSkippedSupply {
    struct Reconsidered {
        var candidates: [Candidate] = []
        var considered: [PendingMediaReconsideration.Entry] = []
    }

    /// The stories the one-way walk already passed whose media became ready since.
    ///
    /// Ordering rule, and why it was chosen: the queue is offered oldest skip first, and those candidates join the
    /// window **after** the structural ones. The queue's only claim is that a skipped story may be selected at all;
    /// where it lands is the editorial sequencing's decision (recency, diversity, PD-4), which orders the window's
    /// candidates and does not read their array position. Appending rather than interleaving is what keeps the
    /// structural window's own count and cursor the facts the opportunity reports: a re-offer can publish a card or
    /// leave the queue, but it can never move the walk or take the position of a candidate the walk produced. There
    /// is no quota and no mixing rule: the bound is the queue's ceiling, and everything ready is offered to the one
    /// selection.
    static func reconsider(provider: CandidateProvider, plan: FeedPlan, editionID: FeedEditionID,
        structural: CandidateSupplyWindow, readiness: MediaReadiness?,
        reoffer: PendingMediaReconsideration?) throws -> Reconsidered {
        guard let readiness, let reoffer else { return Reconsidered() }
        let queued = reoffer.entries(for: editionID)
        guard !queued.isEmpty else { return Reconsidered() }
        let presentations = readiness.presentations(for: queued.map(\.originRevisionID))
        // A queued revision with no presentation is still pending: it stays queued for a later opportunity.
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
        reoffer: PendingMediaReconsideration?) {
        guard let readiness, let reoffer else { return }
        for candidate in structural.candidates {
            guard !publishedOriginIDs.contains(candidate.originRecordID),
                !readiness.isSettled(candidate.originRevisionID) else { continue }
            reoffer.remember(.init(editionID: editionID,
                originRecordID: candidate.originRecordID, originRevisionID: candidate.originRevisionID))
        }
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
