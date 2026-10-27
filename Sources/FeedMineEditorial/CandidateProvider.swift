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

    /// A caller that composes one window out of several sources of candidates (the Runtime re-offers stories a
    /// one-way walk passed) states the examined count and cursor of the walk that produced them, so progress stays
    /// that walk's own fact and the composed candidates claim no position in it.
    public init(candidates: [Candidate], examinedCount: Int, nextCursor: CandidateSupplyCursor?,
        exhausted: Bool) {
        self.candidates = candidates
        self.examinedCount = examinedCount
        self.nextCursor = nextCursor
        self.exhausted = exhausted
    }
}

public enum CandidateProviderError: Error, Equatable, Sendable {
    case searchContextUnavailable
}

public struct CandidateProvider: Sendable {
    private let contentStore: ContentStore

    public init(contentStore: ContentStore) { self.contentStore = contentStore }

    /// Uses only the plan context. Editorial policy versions are not executed in 3C.
    public func candidates(for plan: FeedPlan, after cursor: CandidateSupplyCursor?, examinedCapacity: Int,
        sourceScoped: Bool = false, operation: FeedReplenishmentOperationID? = nil, consult: String = "slice",
        trace: ReplenishmentTrace? = nil) throws -> CandidateSupplyWindow {
        try candidates(for: plan, after: cursor, examinedCapacity: examinedCapacity,
            sourceScoped: sourceScoped, operation: operation, consult: consult, trace: trace,
            excludingSourceIDs: [])
    }

    public func candidates(for plan: FeedPlan, after cursor: CandidateSupplyCursor?, examinedCapacity: Int,
        sourceScoped: Bool = false, operation: FeedReplenishmentOperationID? = nil, consult: String = "slice",
        trace: ReplenishmentTrace? = nil, excludingSourceIDs: Set<SourceID>) throws -> CandidateSupplyWindow {
        try candidates(for: plan, after: cursor, examinedCapacity: examinedCapacity, originIDs: nil,
            sourceScoped: sourceScoped, operation: operation, consult: consult, trace: trace,
            excludingSourceIDs: excludingSourceIDs)
    }

    public func candidates(for plan: FeedPlan, after cursor: CandidateSupplyCursor?,
        examinedCapacity: Int, originIDs: [OriginRecordID]?, sourceScoped: Bool = false,
        operation: FeedReplenishmentOperationID? = nil,
        consult: String = "slice", trace: ReplenishmentTrace? = nil) throws -> CandidateSupplyWindow {
        try candidates(for: plan, after: cursor, examinedCapacity: examinedCapacity, originIDs: originIDs,
            sourceScoped: sourceScoped, operation: operation, consult: consult, trace: trace,
            excludingSourceIDs: [])
    }

    public func candidates(for plan: FeedPlan, after cursor: CandidateSupplyCursor?,
        examinedCapacity: Int, originIDs: [OriginRecordID]?, sourceScoped: Bool = false,
        operation: FeedReplenishmentOperationID? = nil,
        consult: String = "slice", trace: ReplenishmentTrace? = nil,
        excludingSourceIDs: Set<SourceID>) throws -> CandidateSupplyWindow {
        let sourceID: SourceID?
        switch plan.context.request {
        case .main: sourceID = nil
        case .source(let id): sourceID = id
        case .search: sourceID = nil
        }
        let contentCursor = cursor.map {
            ContentStore.CandidateCursor(sortDate: $0.sortDate, originRecordID: $0.originRecordID)
        }
        let window: ContentStore.CandidateWindow
        if sourceScoped, let sourceID, originIDs == nil {
            window = try contentStore.sourceCandidateWindow(sourceID: sourceID,
                after: contentCursor, examinedCapacity: examinedCapacity)
        } else {
            window = try contentStore.candidateWindow(sourceID: sourceID,
                after: contentCursor, examinedCapacity: examinedCapacity, originIDs: originIDs)
        }
        // T6: the supply is where a filter is enforced (plan:147 — never on already-drawn cards). Only the
        // criteria this build can answer are consulted, and a missing fact never satisfies one.
        let eligibility = ReaderFilterEligibility(filter: plan.context.key.filter)
        var candidates = window.records.compactMap { record -> Candidate? in
            var sources = Set(record.sourceIDs)
            if !excludingSourceIDs.isEmpty {
                // Another membership cannot turn a story from an excluded source context into a
                // publication by an unrelated source. Main/search retain their existing scope.
                if let sourceID { sources.formIntersection([sourceID]) }
                sources.subtract(excludingSourceIDs)
                guard record.sourceIDs.isEmpty || !sources.isEmpty else { return nil }
            }
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
                // TX-05D: the evidence is reconstructed from canonical supply — the subjects the story's
                // own document declared, as acquisition recorded them — and never from the Source's
                // taxonomy, the catalogue or the story's text. Absence stays absence, and ordering still
                // reads `timestamp`.
                topics: CandidateTopicEvidence(record.declaredSubjects),
                language: record.language, providerID: record.providerID, sourceIDs: sources,
                primaryMediaLocator: record.primaryMediaLocator, primaryLink: record.primaryLink,
                declaredBody: record.declaredBody, bodyObserved: record.bodyObserved,
                mediaKind: record.mediaKind)
        }.filter { eligibility.admits($0) }
        if case .search(let search) = plan.context.request {
            switch search.semantics {
            case .legacyLiteral:
                // The stored, pre-grammar meaning: one literal substring over headline or summary, exactly as it
                // was always read. A legacy query is never reinterpreted by the new grammar.
                let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
                candidates = candidates.filter { candidate in
                    [candidate.headline, candidate.summary].compactMap { $0 }.contains {
                        $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive],
                            locale: Locale(identifier: "en_US_POSIX")) != nil
                    }
                }
            case .termsV1:
                // R14: the domain's own expression reads the same query the UI wrote.
                guard let expression = search.expression else { candidates = []; break }
                candidates = candidates.filter { candidate in
                    expression.matches(fields: [candidate.headline, candidate.summary].compactMap { $0 })
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
