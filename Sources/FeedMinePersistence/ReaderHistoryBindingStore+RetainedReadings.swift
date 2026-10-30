import Foundation
import GRDB
import FeedMineDomain

extension ReaderHistoryBindingStore {
    public struct RetainedReading: Hashable, Sendable {
        public let edition: PublicationStore.EditionRecord
        public let owner: Record?
        /// Original statements remain distinct; actual active position precedes retained statements.
        public let checkpoints: [LegacyCheckpoint]
        /// A database fact, not permission to publish or evidence that the reader saw this Edition.
        public let isSelectedPreparation: Bool
    }

    /// All committed reading histories in one read snapshot, independent of current criteria/policy.
    /// This does not select, adopt, activate or rank histories by recency.
    public func retainedReadings() throws -> [RetainedReading] {
        try database.read { db in
            let editions = try Row.fetchAll(db, sql: "SELECT * FROM feed_editions ORDER BY id COLLATE BINARY")
                .map(PublicationStore.decodeEdition)
            let bindings = try Row.fetchAll(db, sql: "SELECT * FROM reader_history_bindings")
                .map(Self.decodeRecord)
            var bindingByID: [UUID: Record] = [:]
            for binding in bindings {
                guard bindingByID.updateValue(binding, forKey: binding.id) == nil else { throw Failure.corruption }
            }
            var ownerByEdition: [FeedEditionID: Record] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT binding_id, edition_id FROM reader_history_editions") {
                let fields = PublicationRecordFields(row)
                guard let owner = try bindingByID[fields.uuid("binding_id")] else { throw Failure.corruption }
                ownerByEdition[FeedEditionID(rawValue: try fields.uuid("edition_id"))] = owner
            }
            let physical = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1")
                .map(SessionStore.checkpoint)
            let active: SessionStore.CheckpointRecord?
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM session_reader_binding WHERE singleton_id = 1") {
                let fields = PublicationRecordFields(row)
                if try fields.integer("checkpoint_present") == 1 {
                    guard let point = try SessionStore.ownedCheckpoint(bindingID: fields.uuid("binding_id"), in: db)
                    else { throw Failure.corruption }
                    active = point
                } else { active = nil }
            } else { active = physical }
            let owned = try Row.fetchAll(db, sql: "SELECT * FROM reader_history_checkpoints ORDER BY binding_id COLLATE BINARY, edition_id COLLATE BINARY")
            var ownedByPoint: [SessionStore.CheckpointRecord: Set<UUID>] = [:]
            for row in owned {
                ownedByPoint[try SessionStore.checkpoint(row), default: []]
                    .insert(try PublicationRecordFields(row).uuid("binding_id"))
            }
            let legacy = try Row.fetchAll(db, sql: "SELECT * FROM context_checkpoints ORDER BY context_identity COLLATE BINARY")
                .map(SessionStore.checkpoint)
            let preserved = try Self.retainedLegacyStatements(in: db)
            let known = Dictionary(grouping: preserved, by: \.point)
            let points = (active.map { [$0] } ?? []) + (physical.map { [$0] } ?? [])
                + (try owned.map(SessionStore.checkpoint)) + legacy + preserved.map(\.point)
            var seen = Set<SessionStore.CheckpointRecord>()
            var checkpoints: [FeedEditionID: [LegacyCheckpoint]] = [:]
            for point in points where seen.insert(point).inserted {
                let editionID: FeedEditionID
                if let located = try PublicationStore.location(ofCard: point.cardID, in: db) { editionID = located.editionID }
                else if let evidence = known[point] {
                    let resolved = Set(evidence.map(\.resolvedEditionID))
                    guard resolved.count == 1, let recorded = resolved.first else { throw Failure.corruption }
                    editionID = recorded
                } else { editionID = point.editionID }
                if let expectedOwners = ownedByPoint[point] {
                    guard let owner = ownerByEdition[editionID], expectedOwners == [owner.id] else { throw Failure.corruption }
                }
                checkpoints[editionID, default: []].append(.init(point: point, isActive: point == active))
            }
            let selected = try Row.fetchAll(db, sql: "SELECT edition_id FROM reader_history_preparations WHERE selected = 1 AND edition_id IS NOT NULL")
            let preparedIDs = try Set(selected.map { FeedEditionID(rawValue: try PublicationRecordFields($0).uuid("edition_id")) })
            return editions.map { edition in
                RetainedReading(edition: edition, owner: ownerByEdition[edition.id],
                    checkpoints: checkpoints[edition.id] ?? [], isSelectedPreparation: preparedIDs.contains(edition.id))
            }
        }
    }
}
