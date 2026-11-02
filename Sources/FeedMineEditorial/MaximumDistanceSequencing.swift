// Owns: the pure v6/v7 per-choice order over an already base-ordered candidate array.
// Does not own: retrieval, readiness, persistence, weights or publication.
//
// At each choice: filter PD-4-compatible candidates (unless this is a source-only context, which exempts only
// PD-4), then eliminate set-wise by TYPE → SUBJECTS → SOURCE. A known key never seen is infinity; unknown is
// neutral (retained, never infinity) and never disables the known-vs-known comparison. The nearest prior
// occurrence of any source/subject key is used. Weights/recency/IDs are only the final stable tie because the
// input is the existing base order. The chosen fact updates the nearest distances before the next choice.
//
// v7 (`sourceShareWindow != nil`) adds one elimination **before** the type: keep only the candidates whose
// source has the smallest share of the last `sourceShareWindow` positions (V1's least-used provider rule,
// feedmine-dev EditorialSequencer). v6 alone let one source of a rare type win every other choice — measured
// in docs/reviews/evidence/2026-11-02-v6-sequencing-sim: one podcast among 20 text feeds took 25 of the first
// 50 cards under v6 and 3 under v7. The share counts the window as positions (nil holes occupy a slot and
// count no source), the share of a multi-source candidate is its most-used source, and a candidate with no
// source is neutral exactly as an unknown type is. The window is bounded so a source that joins a long
// Edition catches up in a few cards instead of owning the feed until its lifetime count reaches the others.
import Foundation
import FeedMineDomain

enum MaximumDistanceSequencing {
    /// v7: how many of the most recent positions the source share is read from.
    static let sourceShareWindow = 32

    private struct Facts {
        let type: EditorialMediaKind?
        let subjects: Set<String>
        let sources: Set<SourceID>
    }

    static func sequence(_ ordered: [Candidate], positions: [EditorialDiversityFact?],
        after neighbor: SelectionNeighbor?, singleSourceContext: Bool,
        sourceShareWindow: Int? = nil) -> (placed: [Candidate], held: [Candidate]) {
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

        // v7: the sliding window of recent positions, oldest first, and how often each source occurs in it.
        let shareWindow = sourceShareWindow.flatMap { $0 > 0 ? $0 : nil }
        var recentSources: [Set<SourceID>] = []
        var sourceUsage: [SourceID: Int] = [:]
        if let shareWindow {
            for position in positions.prefix(shareWindow).reversed() {
                let sources = Set(position?.sourceIDs ?? [])
                recentSources.append(sources)
                for source in sources { sourceUsage[source, default: 0] += 1 }
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
            if shareWindow != nil {
                let shares = pool.map { index in (index, share(facts[index], usage: sourceUsage)) }
                if let lowest = shares.compactMap(\.1).min() {
                    pool = shares.filter { $0.1 == nil || $0.1 == lowest }.map(\.0)
                }
            }
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
            if let shareWindow {
                recentSources.append(chosenFacts.sources)
                for source in chosenFacts.sources { sourceUsage[source, default: 0] += 1 }
                if recentSources.count > shareWindow {
                    for source in recentSources.removeFirst() {
                        let left = (sourceUsage[source] ?? 1) - 1
                        sourceUsage[source] = left > 0 ? left : nil
                    }
                }
            }
            current += 1
        }
        return (placed, remaining.map { ordered[$0] })
    }

    /// v7: the share a candidate's sources hold in the recent window — its most-used source, so a story carried
    /// by a dominant feed is not let in through a second, quieter membership. No source is unknown (neutral).
    private static func share(_ facts: Facts, usage: [SourceID: Int]) -> Int? {
        guard !facts.sources.isEmpty else { return nil }
        return facts.sources.map { usage[$0] ?? 0 }.max()
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
