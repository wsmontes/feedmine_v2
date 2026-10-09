// Owns: PD-4 source alternation over an already-ordered candidate sequence.
// Does not own: retrieval, ranking/recency, exposure or publication.
//
// PD-4 (product rule): two consecutive cards from the same source are forbidden, including across
// segment boundaries; fetch or media speed must never degrade the shuffle. v1 enforced diversity
// twice (Reservoir interleave + EditorialSequencer repair, FP-11/CE-5); here it has one owner.

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

    /// Greedy stable alternation: at each position take the earliest candidate (in the given
    /// priority order) compatible with the previous card. Candidates that cannot be placed without
    /// repeating a source are held back, never published adjacent (PD-4 rule 2).
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
}
