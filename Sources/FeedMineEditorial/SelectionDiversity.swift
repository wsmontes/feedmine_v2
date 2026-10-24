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

public enum SelectionDiversityDimension: CaseIterable, Hashable, Sendable {
    case source
    case provider
    case subjects
}

public struct SelectionDiversityContext: Hashable, Sendable {
    /// Newest first, bounded by the caller. Empty is not a context (nil is). v5 comparator input.
    public let recent: [EditorialDiversityFact]
    /// Newest first, complete active-Edition positions for v6, including nil holes for cards without facts.
    /// Empty for the preserved v5 initializer.
    public let publishedPositions: [EditorialDiversityFact?]

    public init?(recent: [EditorialDiversityFact]) {
        guard !recent.isEmpty else { return nil }
        self.recent = recent
        self.publishedPositions = []
    }

    public init?(publishedPositions: [EditorialDiversityFact?]) {
        guard !publishedPositions.isEmpty else { return nil }
        self.recent = []
        self.publishedPositions = publishedPositions
    }

    /// The dimensions this **set** of candidates all know. A dimension known by only some of them is excluded for
    /// the whole comparison: absence can neither invent novelty nor invent repetition, and the order stays a total,
    /// transitive preorder instead of changing its rules from pair to pair.
    public func comparableDimensions(for candidates: [Candidate]) -> [SelectionDiversityDimension] {
        SelectionDiversityDimension.allCases.filter { dimension in
            !candidates.isEmpty && candidates.allSatisfy { repetition(of: $0, dimension) != nil }
        }
    }

    /// A fixed-width key over the comparable dimensions. Lower is less repeated. It is computed identically for
    /// every candidate in the group, so comparing keys lexicographically is consistent under permutation.
    public func repetitionKey(for candidate: Candidate,
        dimensions: [SelectionDiversityDimension]) -> [Int]? {
        var values: [Int] = []
        values.reserveCapacity(dimensions.count)
        for dimension in dimensions {
            guard let value = repetition(of: candidate, dimension) else { return nil }
            values.append(value)
        }
        return values.isEmpty ? nil : values
    }

    private func repetition(of candidate: Candidate, _ dimension: SelectionDiversityDimension) -> Int? {
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
