// Owns: pure baseline policy execution, total ordering and preserved supply facts.
// Does not own: retrieval, policy resolution or published history.

import Foundation
import FeedMineDomain

public enum SelectionError: Error, Equatable, Sendable {
    case policyMismatch
    case duplicateCandidateIdentity
    case exposureRequired
    case unexpectedExposure
    case exposureCoverageMismatch
}

public struct SelectionSupplyReport: Hashable, Sendable {
    public let examinedCount: Int
    public let nextCursor: CandidateSupplyCursor?
    public let exhausted: Bool

    public init(examinedCount: Int, nextCursor: CandidateSupplyCursor?, exhausted: Bool) {
        self.examinedCount = examinedCount
        self.nextCursor = nextCursor
        self.exhausted = exhausted
    }
}

public struct SelectionResult: Hashable, Sendable {
    public let editorialRevision: EditorialRevision
    public let orderedCandidates: [Candidate]
    public let supplyReport: SelectionSupplyReport

    public init(editorialRevision: EditorialRevision, orderedCandidates: [Candidate], supplyReport: SelectionSupplyReport) {
        self.editorialRevision = editorialRevision
        self.orderedCandidates = orderedCandidates
        self.supplyReport = supplyReport
    }
}

public struct SelectionEngine: Sendable {
    public init() {}

    public func select(plan: FeedPlan, policy: ResolvedSelectionPolicy,
        window: CandidateSupplyWindow) throws -> SelectionResult {
        try select(plan: plan, policy: policy, window: window, exposure: nil)
    }

    public func select(plan: FeedPlan, policy: ResolvedSelectionPolicy,
        window: CandidateSupplyWindow, exposure: SelectionExposureSnapshot?) throws -> SelectionResult {
        try select(plan: plan, policy: policy, window: window, exposure: exposure, after: nil)
    }

    /// `after` is the card that will precede this selection in history (the Edition tail), so
    /// PD-4 alternation also holds across segment boundaries.
    public func select(plan: FeedPlan, policy: ResolvedSelectionPolicy,
        window: CandidateSupplyWindow, exposure: SelectionExposureSnapshot?,
        after neighbor: SelectionNeighbor?) throws -> SelectionResult {
        guard policy.matches(plan.revision) else { throw SelectionError.policyMismatch }
        guard Set(window.candidates.map(\.originRecordID)).count == window.candidates.count else {
            throw SelectionError.duplicateCandidateIdentity
        }
        // Baseline no-ops are explicit executable behavior, not inferred versions.
        let sourceEligible: [Candidate]
        switch policy.eligibility {
        case .structuralOnly: sourceEligible = window.candidates
        case .selectedSources(let selected):
            sourceEligible = window.candidates.filter { !Set($0.sourceIDs).isDisjoint(with: selected) }
        }
        // T11: a curated feed's ranking. The weights are the session's own source identities; a candidate
        // carrying several sources takes the strongest of them, because a card is admitted once and the reader
        // asked for the kind of source it came from most strongly.
        let weights: [SourceID: Double]
        switch policy.scoring {
        case .equal: weights = [:]
        case .weighted(let values): weights = values
        }
        let eligible: [Candidate]
        switch policy.exposure {
        case .none:
            guard exposure == nil else { throw SelectionError.unexpectedExposure }
            eligible = sourceEligible
        case .excludePublishedRevisions:
            guard let exposure else { throw SelectionError.exposureRequired }
            guard exposure.requestedOriginIDs == window.candidates.map(\.originRecordID) else {
                throw SelectionError.exposureCoverageMismatch
            }
            eligible = sourceEligible.filter { !exposure.publishedOriginIDs.contains($0.originRecordID) }
        case .excludePublishedMaterial:
            guard let exposure else { throw SelectionError.exposureRequired }
            guard exposure.requestedOriginIDs == window.candidates.map(\.originRecordID) else {
                throw SelectionError.exposureCoverageMismatch
            }
            eligible = sourceEligible.filter { !exposure.alreadyPublished($0) }
        }
        /// The weight a candidate carries: the strongest of its sources' recipe weights, or 1 when the session
        /// is not weighting at all.
        func weight(_ candidate: Candidate) -> Double {
            guard !weights.isEmpty else { return 1 }
            return candidate.sourceIDs.compactMap { weights[$0] }.max() ?? 1
        }
        let ordered: [Candidate]
        switch policy.sequencing {
        case .recencyDescending, .recencyAlternatingSources, .recencyAlternatingSourcesBySupplyShare,
             .recencyAlternatingSourcesByWeightedSupplyShare:
            ordered = eligible.sorted { left, right in
                let leftWeight = weight(left), rightWeight = weight(right)
                if leftWeight != rightWeight { return leftWeight > rightWeight }
                if left.timestamp.value != right.timestamp.value {
                    return left.timestamp.value > right.timestamp.value
                }
                let leftOrigin = left.originRecordID.rawValue.uuidString.lowercased()
                let rightOrigin = right.originRecordID.rawValue.uuidString.lowercased()
                if leftOrigin != rightOrigin { return leftOrigin > rightOrigin }
                return left.originRevisionID.rawValue.uuidString.lowercased()
                    > right.originRevisionID.rawValue.uuidString.lowercased()
            }
        }
        // PD-4: a single-source context is exempt by definition; other contexts alternate when the
        // resolved sequencing behavior says so (a behavior change is a new EditorialRevision, and an
        // Edition restored from disk keeps the behavior its revision names).
        // The supply-share accounting counts only the sources this context selected: a candidate may carry
        // memberships the reader never asked for, and those must not invent representativeness. PD-4 keeps
        // using the candidate's full source set.
        let countedSources: Set<SourceID>?
        switch policy.eligibility {
        case .structuralOnly: countedSources = nil
        case .selectedSources(let selected): countedSources = selected
        }
        let alternated: (placed: [Candidate], held: [Candidate])
        if Self.isSingleSource(plan.context.request) {
            alternated = (ordered, [])
        } else {
            switch policy.sequencing {
            case .recencyAlternatingSources:
                alternated = SourceAlternation.apply(ordered, after: neighbor)
            case .recencyAlternatingSourcesBySupplyShare:
                alternated = SourceAlternation.applyBySupplyShare(ordered, after: neighbor,
                    countingSources: countedSources)
            case .recencyAlternatingSourcesByWeightedSupplyShare:
                alternated = SourceAlternation.applyByWeightedSupplyShare(ordered, after: neighbor,
                    countingSources: countedSources, weights: weights)
            case .recencyDescending:
                alternated = (ordered, [])
            }
        }
        return SelectionResult(editorialRevision: plan.revision, orderedCandidates: alternated.placed,
            supplyReport: Self.report(window: window, held: alternated.held, placedAny: !alternated.placed.isEmpty))
    }

    private static func isSingleSource(_ request: FeedContextRequest) -> Bool {
        if case .source = request { return true }
        return false
    }

    /// Held candidates must stay reachable. When something was placed, progress is guaranteed (the
    /// placed origins become published and excluded), so the cursor rewinds to just before the
    /// earliest held candidate and the next slice reconsiders it. When nothing could be placed, the
    /// cursor advances normally so supply of other sources is examined (or acquisition is demanded
    /// on exhaustion) instead of looping on the same window.
    private static func report(window: CandidateSupplyWindow, held: [Candidate], placedAny: Bool) -> SelectionSupplyReport {
        let unchanged = SelectionSupplyReport(examinedCount: window.examinedCount, nextCursor: window.nextCursor,
            exhausted: window.exhausted)
        guard placedAny, !held.isEmpty else { return unchanged }
        let heldIDs = Set(held.map(\.originRecordID))
        guard let earliest = window.candidates.firstIndex(where: { heldIDs.contains($0.originRecordID) }) else { return unchanged }
        let rewound = earliest == 0 ? nil : window.candidates[earliest - 1]
        return SelectionSupplyReport(examinedCount: window.examinedCount,
            nextCursor: rewound.map { CandidateSupplyCursor(sortDate: $0.timestamp.value, originRecordID: $0.originRecordID) },
            exhausted: false)
    }
}
