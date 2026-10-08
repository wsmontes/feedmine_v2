// Owns: context mapping and one bounded local structural supply window per call.
// Does not own: selection/policy execution, source filtering mechanics or acquisition.

import Foundation
import FeedMineDomain
import FeedMinePersistence

public struct CandidateSupplyCursor: Hashable, Sendable {
    public let sortDate: Date
    public let originRecordID: OriginRecordID

    public init(sortDate: Date, originRecordID: OriginRecordID) {
        self.sortDate = sortDate
        self.originRecordID = originRecordID
    }
}

public struct CandidateSupplyWindow: Hashable, Sendable {
    public let candidates: [Candidate]
    public let examinedCount: Int
    public let nextCursor: CandidateSupplyCursor?
    public let exhausted: Bool
}

public enum CandidateProviderError: Error, Equatable, Sendable {
    case searchContextUnavailable
}

public struct CandidateProvider: Sendable {
    private let contentStore: ContentStore

    public init(contentStore: ContentStore) { self.contentStore = contentStore }

    /// Uses only the plan context. Editorial policy versions are not executed in 3C.
    public func candidates(for plan: FeedPlan, after cursor: CandidateSupplyCursor?,
        examinedCapacity: Int) throws -> CandidateSupplyWindow {
        let sourceID: SourceID?
        switch plan.context.request {
        case .main: sourceID = nil
        case .source(let id): sourceID = id
        case .search: throw CandidateProviderError.searchContextUnavailable
        }
        let window = try contentStore.candidateWindow(sourceID: sourceID,
            after: cursor.map { ContentStore.CandidateCursor(sortDate: $0.sortDate, originRecordID: $0.originRecordID) },
            examinedCapacity: examinedCapacity)
        let candidates = window.records.map { record in
            let kind: CandidateTimestampKind
            switch record.sortDateBasis {
            case .authored: kind = .authored
            case .observedFallback: kind = .observed
            }
            return Candidate(originRecordID: record.originRecordID, originRevisionID: record.originRevisionID,
                headline: record.headline, summary: record.summary,
                timestamp: CandidateTimestamp(value: record.sortDate, kind: kind),
                language: record.language, providerID: record.providerID)
        }
        return CandidateSupplyWindow(candidates: candidates, examinedCount: window.examinedCount,
            nextCursor: window.nextCursor.map { CandidateSupplyCursor(sortDate: $0.sortDate, originRecordID: $0.originRecordID) },
            exhausted: window.exhausted)
    }
}
