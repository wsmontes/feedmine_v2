// Owns: one bounded preparation opportunity for Publication's authorized hidden suffix.
// Does not own: seen state, visibility authority, downloads, or history replacement.
import Foundation
import FeedMineDomain
import FeedMinePersistence
import FeedMineEditorial
import FeedMinePublication

public struct HiddenTailMaintenance: Sendable {
    private let database: RuntimeDatabase
    public init(database: RuntimeDatabase) { self.database = database }

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
        let drafts = try PublicationPreparation.drafts(selection: selection, inputs: prepared.inputs)
        let latest = Dictionary(uniqueKeysWithValues: drafts.map { ($0.origin.originRecordID, $0) })
        if future.allSatisfy({ old in
            guard let new = latest[old.originRecordID] else { return false }
            return old.originRevisionID == new.origin.originRevisionID && old.mediaKey == new.media.primary?.key.rawValue
        }) { return .ineligible }
        return try PublicationCoordinator(database: database).succeedTail(.init(selection: selection, drafts: drafts,
            editionID: lease.editionID, segmentID: FeedSegmentID(), segmentSeed: 1, segmentCreatedAt: Date(),
            cardIDs: prepared.cardIDs, originRecurrence: .whenMaterialChanged), lease: lease)
    }
}
