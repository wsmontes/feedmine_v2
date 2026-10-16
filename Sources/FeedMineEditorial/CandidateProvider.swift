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
    public func candidates(for plan: FeedPlan, after cursor: CandidateSupplyCursor?, examinedCapacity: Int,
        operation: FeedReplenishmentOperationID? = nil, consult: String = "slice",
        trace: ReplenishmentTrace? = nil) throws -> CandidateSupplyWindow {
        try candidates(for: plan, after: cursor, examinedCapacity: examinedCapacity, originIDs: nil,
            operation: operation, consult: consult, trace: trace)
    }

    public func candidates(for plan: FeedPlan, after cursor: CandidateSupplyCursor?,
        examinedCapacity: Int, originIDs: [OriginRecordID]?, operation: FeedReplenishmentOperationID? = nil,
        consult: String = "slice", trace: ReplenishmentTrace? = nil) throws -> CandidateSupplyWindow {
        let sourceID: SourceID?
        switch plan.context.request {
        case .main: sourceID = nil
        case .source(let id): sourceID = id
        case .search: sourceID = nil
        }
        let window = try contentStore.candidateWindow(sourceID: sourceID,
            after: cursor.map { ContentStore.CandidateCursor(sortDate: $0.sortDate, originRecordID: $0.originRecordID) },
            examinedCapacity: examinedCapacity, originIDs: originIDs)
        // T6: the supply is where a filter is enforced (plan:147 — never on already-drawn cards). Only the
        // criteria this build can answer are consulted, and a missing fact never satisfies one.
        let eligibility = ReaderFilterEligibility(filter: plan.context.key.filter)
        var candidates = window.records.map { record in
            let kind: CandidateTimestampKind
            switch record.sortDateBasis {
            case .authored: kind = .authored
            case .observedFallback: kind = .observed
            }
            return Candidate(originRecordID: record.originRecordID, originRevisionID: record.originRevisionID,
                headline: record.headline.map(ReadablePublicationText.convert), summary: record.summary.map(ReadablePublicationText.convert),
                timestamp: CandidateTimestamp(value: record.sortDate, kind: kind),
                // TX-07D: the evidence is reconstructed from canonical supply, not restated from the
                // ordering key. `record.authoredAt` is the accepted publication instant (and is nil when
                // the origin declared none), `modifiedAt` is the accepted change instant, and
                // `observedAt` is FeedMine's own observation. The original declaration is transient and not
                // persisted, so an accepted instant equal to the observation instant is reported by the
                // evidence as ambiguous rather than as a declared date. Ordering still reads `timestamp`.
                temporal: CandidateTemporalEvidence(observedAt: record.observedAt,
                    acceptedAuthoredAt: record.authoredAt, acceptedModifiedAt: record.modifiedAt),
                language: record.language, providerID: record.providerID, sourceIDs: Set(record.sourceIDs),
                primaryMediaLocator: record.primaryMediaLocator, primaryLink: record.primaryLink,
                declaredBody: record.declaredBody, bodyObserved: record.bodyObserved)
        }.filter { eligibility.admits($0) }
        if case .search(let search) = plan.context.request {
            let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
            candidates = candidates.filter { candidate in
                [candidate.headline, candidate.summary].compactMap { $0 }.contains {
                    $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) != nil
                }
            }
        }
        let supply = CandidateSupplyWindow(candidates: candidates, examinedCount: window.examinedCount,
            nextCursor: window.nextCursor.map { CandidateSupplyCursor(sortDate: $0.sortDate, originRecordID: $0.originRecordID) },
            exhausted: window.exhausted)
        // The instant this consult returned, stated where it happened: the quantity it produced and whether the
        // walk it was bounded to was exhausted. An empty window is an outcome, not silence — and so is a full one.
        if let operation, let trace {
            trace.record(ReplenishmentEvent.arrived, ["op": operation.described, "kind": "local",
                "consult": consult, "result": "window", "candidates": String(supply.candidates.count),
                "examined": String(supply.examinedCount), "exhausted": supply.exhausted ? "true" : "false"])
        }
        return supply
    }
}
