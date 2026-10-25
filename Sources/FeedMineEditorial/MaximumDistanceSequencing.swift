// Owns: the pure v6 per-choice order over an already base-ordered candidate array.
// Does not own: retrieval, readiness, persistence, weights or publication.
//
// At each choice: filter PD-4-compatible candidates (unless this is a source-only context, which exempts only
// PD-4), then eliminate set-wise by TYPE → SUBJECTS → SOURCE. A known key never seen is infinity; unknown is
// neutral (retained, never infinity) and never disables the known-vs-known comparison. The nearest prior
// occurrence of any source/subject key is used. Weights/recency/IDs are only the final stable tie because the
// input is the existing base order. The chosen fact updates the nearest distances before the next choice.
import Foundation
import FeedMineDomain

enum MaximumDistanceSequencing {
    private struct Facts {
        let type: EditorialMediaKind?
        let subjects: Set<String>
        let sources: Set<SourceID>
    }

    static func sequence(_ ordered: [Candidate], positions: [EditorialDiversityFact?],
        after neighbor: SelectionNeighbor?, singleSourceContext: Bool) -> (placed: [Candidate], held: [Candidate]) {
        let facts = ordered.map { candidate in
            Facts(type: candidate.mediaKind,
                subjects: Set(candidate.topics.identities.map(\.key)),
                sources: candidate.sourceIDs)
        }

        // Newest first. relative position index + 1 is the distance from the current choice; nil holes count.
        var typeSeen: [EditorialMediaKind: Int] = [:]
        var subjectSeen: [String: Int] = [:]
        var sourceSeen: [SourceID: Int] = [:]
        for (index, position) in positions.enumerated() {
            guard let position else { continue }
            let relative = -1 - index
            if let kind = position.mediaKind, typeSeen[kind] == nil { typeSeen[kind] = relative }
            for subject in position.subjects where subjectSeen[subject] == nil {
                subjectSeen[subject] = relative
            }
            for source in position.sourceIDs where sourceSeen[source] == nil {
                sourceSeen[source] = relative
            }
        }

        var previous = neighbor
        if previous == nil, let first = positions.first, let fact = first {
            previous = SelectionNeighbor(sourceIDs: Set(fact.sourceIDs), providerID: fact.providerID)
        }

        var remaining = Array(ordered.indices)
        var placed: [Candidate] = []
        var current = 0
        while !remaining.isEmpty {
            let compatible = singleSourceContext ? remaining : remaining.filter {
                SourceAlternation.compatible(previous, ordered[$0])
            }
            guard !compatible.isEmpty else { break }

            var pool = compatible
            for dimension in 0..<3 {
                let scored = pool.map { index in
                    (index, distance(facts[index], dimension: dimension, current: current,
                        typeSeen: typeSeen, subjectSeen: subjectSeen, sourceSeen: sourceSeen))
                }
                let known = scored.compactMap { $0.1 }
                guard let maximum = known.max() else { continue }
                pool = scored.filter { $0.1 == nil || $0.1 == maximum }.map(\.0)
            }
            guard let chosenIndex = pool.first else { break }
            let chosen = ordered[chosenIndex]
            placed.append(chosen)
            remaining.removeAll { $0 == chosenIndex }
            previous = SelectionNeighbor(sourceIDs: chosen.sourceIDs, providerID: chosen.providerID)

            let chosenFacts = facts[chosenIndex]
            if let kind = chosenFacts.type { typeSeen[kind] = current }
            for subject in chosenFacts.subjects { subjectSeen[subject] = current }
            for source in chosenFacts.sources { sourceSeen[source] = current }
            current += 1
        }
        return (placed, remaining.map { ordered[$0] })
    }

    private static func distance(_ facts: Facts, dimension: Int, current: Int,
        typeSeen: [EditorialMediaKind: Int], subjectSeen: [String: Int],
        sourceSeen: [SourceID: Int]) -> Int? {
        switch dimension {
        case 0:
            guard let kind = facts.type, let last = typeSeen[kind] else { return facts.type == nil ? nil : Int.max }
            return current - last
        case 1:
            guard !facts.subjects.isEmpty else { return nil }
            guard let last = facts.subjects.compactMap({ subjectSeen[$0] }).max() else { return Int.max }
            return current - last
        default:
            guard !facts.sources.isEmpty else { return nil }
            guard let last = facts.sources.compactMap({ sourceSeen[$0] }).max() else { return Int.max }
            return current - last
        }
    }
}
