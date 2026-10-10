// Owns: PD-4 source alternation over an already-ordered candidate sequence, and the pacing rule that
//        decides which compatible source is served next.
// Does not own: retrieval, ranking/recency, exposure or publication.
//
// PD-4 (product rule): two consecutive cards from the same source are forbidden, including across
// segment boundaries; fetch or media speed must never degrade the shuffle. v1 enforced diversity
// twice (Reservoir interleave + EditorialSequencer repair, FP-11/CE-5); here it has one owner.
//
// R1/R2 (2026-10-10): alternation alone is not distribution. Measured on a real run, a 32-candidate
// window holding 12 sources published cards from 5 of them before repeating one, and a third of the
// segment came from a single feed. v1's `EditorialSequencer.sequence` asked instead how many cards each
// provider had already been served, and that question is restored here.
//
// Known cost, measured: serving the scarce sources first spends the separators PD-4 needs later, so a
// window places fewer cards than it could (102 candidates: 75 placed, 27 held; the same window under a
// proportional rule places 84). Held cards are not lost — the caller's cursor rewinds to the earliest
// of them, so they are reconsidered with the next window's supply — and the published prefix, which is
// what the reader sees, is what this rule is for. A proportional alternative is recorded in
// docs/reviews/R1_EDITORIAL_DIAGNOSIS.md (§ R2) for the product decision that owns this trade-off.

import Foundation
import FeedMineDomain

/// Attribution facts of the card that immediately precedes the next segment.
public struct SelectionNeighbor: Hashable, Sendable {
    public let sourceIDs: Set<SourceID>
    public let providerID: ProviderID?

    public init(sourceIDs: Set<SourceID>, providerID: ProviderID?) {
        self.sourceIDs = sourceIDs
        self.providerID = providerID
    }
}

enum SourceAlternation {
    /// Two cards may be adjacent when they share no known source. Unknown facts (empty source
    /// sets) never constrain. Provider is not a PD-4 criterion.
    static func compatible(_ previous: SelectionNeighbor?, _ next: Candidate) -> Bool {
        guard let previous else { return true }
        return previous.sourceIDs.isDisjoint(with: next.sourceIDs)
    }

    /// Sequencing v2: greedy stable alternation — at each position take the earliest candidate (in the
    /// given priority order) compatible with the previous card. Kept because an Edition published under
    /// v2 is restored with its own revision and must keep the behavior it was published with.
    static func apply(_ ordered: [Candidate], after neighbor: SelectionNeighbor?) -> (placed: [Candidate], held: [Candidate]) {
        var remaining = ordered
        var placed: [Candidate] = []
        var previous = neighbor
        while let index = remaining.firstIndex(where: { compatible(previous, $0) }) {
            let next = remaining.remove(at: index)
            placed.append(next)
            previous = SelectionNeighbor(sourceIDs: next.sourceIDs, providerID: next.providerID)
        }
        return (placed, remaining)
    }

    /// What this candidate's sources have already been served in this window, and what the window offers
    /// them — counted only over the sources this context selected. A candidate may carry memberships the
    /// reader never selected; those must not invent representativeness (R2 review, 2026-10-10). PD-4 keeps
    /// using the candidate's full source set: every source it carries still constrains adjacency.
    /// A candidate carrying several counted sources is judged by the mean of their fractions, and placing it
    /// is accounted to each of them — one candidate is placed once and never duplicated. Counts belong to
    /// this call only: the window, not the Edition, is the unit.
    private static func supplyShare(_ candidate: Candidate, counted: Set<SourceID>?, served: [SourceID: Int],
        offered: [SourceID: Int], servedUnknown: Int, offeredUnknown: Int) -> Double {
        guard let counted else {
            guard !candidate.sourceIDs.isEmpty else {
                return offeredUnknown == 0 ? 0 : Double(servedUnknown) / Double(offeredUnknown)
            }
            return meanShare(of: candidate.sourceIDs, served: served, offered: offered)
        }
        let sources = candidate.sourceIDs.intersection(counted)
        // With a selected-source policy every candidate survived the eligibility filter by intersecting the
        // selection, so this is never empty in practice; an unconstrained window falls back to its own count.
        guard !sources.isEmpty else { return offeredUnknown == 0 ? 0 : Double(servedUnknown) / Double(offeredUnknown) }
        return meanShare(of: sources, served: served, offered: offered)
    }

    private static func meanShare(of sources: Set<SourceID>, served: [SourceID: Int], offered: [SourceID: Int]) -> Double {
        let total = sources.reduce(0.0) { partial, source in
            guard let available = offered[source], available > 0 else { return partial }
            return partial + Double(served[source] ?? 0) / Double(available)
        }
        return total / Double(sources.count)
    }

    /// Sequencing v3 (R2-D1): scarcity-aware proportional alternation. At each position take the
    /// compatible candidate whose sources have consumed the smallest share of what this window offers
    /// them — not the smallest number of cards, which spends the scarce sources early and leaves the
    /// surplus of a prolific source without the separators PD-4 needs. Ties go to the earliest position
    /// in the given priority order, so recency decides which candidate of a source is used and which
    /// source wins a tie; ratios of small integers make the comparison reproducible for a given window.
    /// Candidates that cannot be placed without repeating a source are held back, never published
    /// adjacent (PD-4 rule 2); the caller's cursor rewinds to the earliest held candidate, so a held
    /// card is reconsidered with the next window's supply instead of being dropped.
    ///
    /// `countingSources` is the context's selected-source set: only those participate in the share
    /// accounting. `nil` means the window is unconstrained and every source it carries counts.
    static func applyBySupplyShare(_ ordered: [Candidate], after neighbor: SelectionNeighbor?,
        countingSources: Set<SourceID>? = nil) -> (placed: [Candidate], held: [Candidate]) {
        var remaining = ordered
        var placed: [Candidate] = []
        var previous = neighbor
        var servedBySource: [SourceID: Int] = [:]
        var servedUnknown = 0
        var offeredBySource: [SourceID: Int] = [:]
        var offeredUnknown = 0
        for candidate in ordered {
            let sources = countingSources.map { candidate.sourceIDs.intersection($0) } ?? candidate.sourceIDs
            if sources.isEmpty {
                offeredUnknown += 1
            } else {
                for source in sources { offeredBySource[source, default: 0] += 1 }
            }
        }
        while true {
            var chosen: Int?
            var chosenShare = Double.infinity
            for index in remaining.indices {
                let candidate = remaining[index]
                guard compatible(previous, candidate) else { continue }
                let share = supplyShare(candidate, counted: countingSources, served: servedBySource,
                    offered: offeredBySource, servedUnknown: servedUnknown, offeredUnknown: offeredUnknown)
                if share < chosenShare {
                    chosen = index
                    chosenShare = share
                }
            }
            guard let index = chosen else { break }
            let next = remaining.remove(at: index)
            placed.append(next)
            let sources = countingSources.map { next.sourceIDs.intersection($0) } ?? next.sourceIDs
            if sources.isEmpty {
                servedUnknown += 1
            } else {
                for source in sources { servedBySource[source, default: 0] += 1 }
            }
            previous = SelectionNeighbor(sourceIDs: next.sourceIDs, providerID: next.providerID)
        }
        return (placed, remaining)
    }
}
