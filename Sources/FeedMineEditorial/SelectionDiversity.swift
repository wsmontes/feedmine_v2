// File: SelectionDiversity.swift
// Module: FeedMineEditorial
//
// Responsibility:
// R17: the recent published facts a diversity tie-break reads, and the deterministic cost that compares a
// candidate with them. Only facts the publication actually froze are used: source, provider and the story's own
// declared subjects. Geography and format are not available in this build and are treated as unknown — never
// invented from the Source's category, the headline or the latest canonical revision.
//
// Does not own: selection order, publication or persistence.
import Foundation
import FeedMineDomain

public struct SelectionDiversityContext: Hashable, Sendable {
    /// Newest first, bounded by the caller. Empty is not a context (nil is).
    public let recent: [EditorialDiversityFact]

    public init?(recent: [EditorialDiversityFact]) {
        guard !recent.isEmpty else { return nil }
        self.recent = recent
    }

    /// Whether `left` repeats the recent window less than `right`. Each dimension is compared only when **both**
    /// candidates know it: an unknown dimension is skipped, so missing metadata can neither invent novelty nor
    /// invent repetition. Newer facts weigh more (linear over the window's position).
    func isLessRepeated(_ left: Candidate, than right: Candidate) -> Bool? {
        for dimension in Dimension.allCases {
            guard let leftValue = repetition(of: left, dimension),
                let rightValue = repetition(of: right, dimension) else { continue }
            if leftValue != rightValue { return leftValue < rightValue }
        }
        return nil
    }

    private enum Dimension: CaseIterable { case source, provider, subjects }

    private func repetition(of candidate: Candidate, _ dimension: Dimension) -> Int? {
        switch dimension {
        case .source:
            guard !candidate.sourceIDs.isEmpty else { return nil }
        case .provider:
            guard candidate.providerID != nil else { return nil }
        case .subjects:
            guard !candidate.topics.isAbsent else { return nil }
        }
        let subjects = Set(candidate.topics.identities.map(\.key))
        var total = 0
        for (index, fact) in recent.enumerated() {
            let weight = recent.count - index
            switch dimension {
            case .source:
                if !candidate.sourceIDs.isDisjoint(with: Set(fact.sourceIDs)) { total += weight }
            case .provider:
                if let provider = candidate.providerID, provider == fact.providerID { total += weight }
            case .subjects:
                total += subjects.intersection(Set(fact.subjects)).count * weight
            }
        }
        return total
    }
}
