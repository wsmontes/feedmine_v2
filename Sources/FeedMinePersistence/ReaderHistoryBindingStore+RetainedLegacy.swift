import Foundation
import GRDB
import FeedMineDomain

extension ReaderHistoryBindingStore {
    struct RetainedLegacyStatement {
        let point: SessionStore.CheckpointRecord
        let resolvedEditionID: FeedEditionID
    }

    static func retainedLegacyStatements(in db: Database) throws -> [RetainedLegacyStatement] {
        try Row.fetchAll(db, sql: """
            SELECT * FROM reader_history_legacy_checkpoints
            ORDER BY resolved_edition_id COLLATE BINARY, updated_at, card_id COLLATE BINARY, id COLLATE BINARY
            """).map { row in
                RetainedLegacyStatement(point: try SessionStore.checkpoint(row),
                    resolvedEditionID: FeedEditionID(rawValue: try PublicationRecordFields(row).uuid("resolved_edition_id")))
            }
    }

    /// Preserve every known unowned statement before activation can refile the singleton over a
    /// different per-context statement. Original fields and observed card ownership remain separate.
    static func retainLegacyCheckpoints(in db: Database) throws {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM session_checkpoint")
            + Row.fetchAll(db, sql: "SELECT * FROM context_checkpoints")
        var retained = try retainedLegacyStatements(in: db)
        for row in rows {
            let point = try SessionStore.checkpoint(row)
            let known = Set(retained.filter { $0.point == point }.map(\.resolvedEditionID))
            let editionID: FeedEditionID
            if let located = try PublicationStore.location(ofCard: point.cardID, in: db) {
                guard known.isEmpty || known == [located.editionID] else { throw Failure.corruption }
                editionID = located.editionID
            } else if !known.isEmpty {
                guard known.count == 1, let recorded = known.first else { throw Failure.corruption }
                editionID = recorded
            } else { editionID = point.editionID }
            guard try String.fetchOne(db, sql: "SELECT binding_id FROM reader_history_editions WHERE edition_id = ?",
                arguments: [PersistenceValueCoding.uuid(editionID.rawValue)]) == nil else { continue }
            guard !retained.contains(where: { $0.point == point && $0.resolvedEditionID == editionID }) else { continue }
            try db.execute(sql: """
                INSERT INTO reader_history_legacy_checkpoints
                    (id, resolved_edition_id, edition_id, card_id, anchor_placement, updated_at, anchor_top_delta, anchor_height)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [PersistenceValueCoding.uuid(UUID()), PersistenceValueCoding.uuid(editionID.rawValue),
                    PersistenceValueCoding.uuid(point.editionID.rawValue), PersistenceValueCoding.uuid(point.cardID.rawValue),
                    point.anchorPlacement, point.updatedAt.timeIntervalSince1970, point.topDelta, point.cardHeight])
            retained.append(.init(point: point, resolvedEditionID: editionID))
        }
    }
}
