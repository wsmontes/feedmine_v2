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
        guard policy.matches(plan.revision) else { throw SelectionError.policyMismatch }
        guard Set(window.candidates.map(\.originRecordID)).count == window.candidates.count else {
            throw SelectionError.duplicateCandidateIdentity
        }
        // Baseline no-ops are explicit executable behavior, not inferred versions.
        switch policy.eligibility { case .structuralOnly: break }
        switch policy.scoring { case .equal: break }
        let eligible: [Candidate]
        switch policy.exposure {
        case .none:
            guard exposure == nil else { throw SelectionError.unexpectedExposure }
            eligible = window.candidates
        case .excludePublishedRevisions:
            guard let exposure else { throw SelectionError.exposureRequired }
            guard exposure.requestedOriginIDs == window.candidates.map(\.originRecordID) else {
                throw SelectionError.exposureCoverageMismatch
            }
            eligible = window.candidates.filter { !exposure.publishedOriginIDs.contains($0.originRecordID) }
        }
        let ordered: [Candidate]
        switch policy.sequencing {
        case .recencyDescending:
            ordered = eligible.sorted { left, right in
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
        return SelectionResult(editorialRevision: plan.revision, orderedCandidates: ordered,
            supplyReport: SelectionSupplyReport(examinedCount: window.examinedCount,
                nextCursor: window.nextCursor, exhausted: window.exhausted))
    }
}
