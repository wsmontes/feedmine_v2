// Owns: one bounded preparation opportunity for Publication's authorized hidden suffix.
// Does not own: seen state, visibility authority, downloads, or history replacement.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication

public struct HiddenTailMaintenance: Sendable {
    private let database: RuntimeDatabase
    /// Optional evidence of the publication this maintenance concludes; nil records nothing. DEBUG-only at the
    /// point of recording.
    private let trace: ReplenishmentTrace?
    public init(database: RuntimeDatabase, trace: ReplenishmentTrace? = nil) {
        self.database = database
        self.trace = trace
    }

    public func run(plan: FeedPlan, policy: ResolvedSelectionPolicy, lease: PublicationStore.HiddenTailLease,
        examinedCapacity: Int, prefetch: @Sendable ([OriginRevisionID]) async -> Void,
        prepare: @Sendable (SelectionResult) throws -> LocalPreparedPublication) async throws -> PublicationStore.TailSuccessionResult {
        let store = PublicationStore(database: database)
        guard let edition = try store.edition(id: lease.editionID), edition.editorialRevision == plan.revision else { return .ineligible }
        let future = try store.cards(editionID: lease.editionID, around: lease.highWaterCardID,
            backwardCapacity: 0, forwardCapacity: examinedCapacity + 1).dropFirst()
        guard !future.isEmpty, future.count <= examinedCapacity else { return .ineligible }
        let content = ContentStore(database: database)
        let window = try CandidateProvider(contentStore: content).candidates(for: plan, after: nil, examinedCapacity: examinedCapacity, originIDs: future.map(\.originRecordID))
        let seen = try store.seenMaterial(lease: lease, originIDs: window.candidates.map(\.originRecordID))
        guard let exposure = SelectionExposureSnapshot(requestedOriginIDs: window.candidates.map(\.originRecordID),
            publishedOriginIDs: Set(seen.keys), publishedMaterialKeys: seen),
            let boundary = try store.card(id: lease.highWaterCardID) else { return .ineligible }
        var sources = Set(try content.memberships(originRecordID: boundary.originRecordID).map(\.sourceID))
        if let source = boundary.sourceID { sources.insert(source) }
        let selection = try SelectionEngine().select(plan: plan, policy: policy, window: window, exposure: exposure,
            after: SelectionNeighbor(sourceIDs: sources, providerID: boundary.providerID))
        let selected = Set(selection.orderedCandidates.map(\.originRecordID))
        // Every previous future origin must remain eligible; bounded exact lookup also works far behind the supply head.
        guard Set(future.map(\.originRecordID)).isSubset(of: selected) else { return .ineligible }
        await prefetch(selection.orderedCandidates.map(\.originRevisionID))
        let prepared = try prepare(selection)
        let plan = try PublicationPreparation.plan(selection: selection, publication: prepared)
        // A future card whose declared image is not prepared cannot be succeeded: leaving it out would change
        // the durable suffix, and publishing it as text would be the forbidden fallback.
        guard plan.drafts.count == selection.orderedCandidates.count else { return .ineligible }
        let latest = Dictionary(uniqueKeysWithValues: plan.drafts.map { ($0.origin.originRecordID, $0) })
        if future.allSatisfy({ old in
            guard let new = latest[old.originRecordID] else { return false }
            return old.originRevisionID == new.origin.originRevisionID && old.mediaKey == new.media.primary?.key.rawValue
        }) { return .ineligible }
        let result = try PublicationCoordinator(database: database).succeedTail(.init(selection: plan.selection,
            drafts: plan.drafts, editionID: lease.editionID, segmentID: FeedSegmentID(), segmentSeed: 1,
            segmentCreatedAt: Date(), cardIDs: plan.cardIDs, originRecurrence: .whenMaterialChanged), lease: lease)
        #if DEBUG
        if result == .applied { MediaPreparationTrace.recordPublished(plan.drafts, in: content, to: trace) }
        #endif
        return result
    }
}
