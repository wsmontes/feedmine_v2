import Foundation
import GRDB
import FeedMineDomain

extension SessionStore {
    /// One activation of the existing SessionStore authority. Returning A after B rotates the token,
    /// so callbacks from A's retired association cannot overwrite the newly active position.
    public struct BindingActivation: Hashable, Sendable {
        public let bindingID: UUID
        public let token: UUID
    }

    public func activateBinding(_ bindingID: UUID) throws -> BindingActivation {
        try database.write { db in
            let id = PersistenceValueCoding.uuid(bindingID)
            guard let binding = try Row.fetchOne(db, sql: "SELECT * FROM reader_history_bindings WHERE id = ?",
                arguments: [id]) else { throw SessionStoreError.missingHistoryBinding }
            if let current = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1") {
                try Self.persistContext(Self.checkpoint(current), in: db)
            }
            if let editionID = try PublicationRecordFields(binding).optionalUUID("active_edition_id") {
                try Self.seedBindingCheckpoint(bindingID: bindingID, editionID: FeedEditionID(rawValue: editionID), in: db)
            }
            let active = BindingActivation(bindingID: bindingID, token: UUID())
            try db.execute(sql: "DELETE FROM session_checkpoint WHERE singleton_id = 1")
            try db.execute(sql: """
                INSERT INTO session_reader_binding(singleton_id, binding_id, activation_token) VALUES (1, ?, ?)
                ON CONFLICT(singleton_id) DO UPDATE SET binding_id = excluded.binding_id,
                    activation_token = excluded.activation_token
                """, arguments: [id, PersistenceValueCoding.uuid(active.token)])
            // Decode before copying: corrupt owned state must not become a blank unrestricted session.
            _ = try Self.ownedCheckpoint(bindingID: bindingID, in: db)
            try db.execute(sql: """
                INSERT INTO session_checkpoint(singleton_id, edition_id, card_id, anchor_placement, updated_at, anchor_top_delta, anchor_height)
                SELECT 1, c.edition_id, c.card_id, c.anchor_placement, c.updated_at, c.anchor_top_delta, c.anchor_height
                FROM reader_history_checkpoints c JOIN reader_history_bindings b
                    ON b.id = c.binding_id AND b.active_edition_id = c.edition_id WHERE b.id = ?
                """, arguments: [id])
            return active
        }
    }

    public func checkpoint(bindingID: UUID) throws -> CheckpointRecord? {
        try database.read { try Self.ownedCheckpoint(bindingID: bindingID, in: $0) }
    }

    static func ownedCheckpoint(bindingID: UUID, in db: Database) throws -> CheckpointRecord? {
        let id = PersistenceValueCoding.uuid(bindingID)
        guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_history_bindings WHERE id = ?)",
            arguments: [id]) == true else { throw SessionStoreError.missingHistoryBinding }
        guard let row = try Row.fetchOne(db, sql: """
            SELECT c.* FROM reader_history_checkpoints c JOIN reader_history_bindings b
                ON b.id = c.binding_id AND b.active_edition_id = c.edition_id WHERE b.id = ?
            """, arguments: [id]) else { return nil }
        return try checkpoint(row)
    }

    static func requireActivation(_ active: BindingActivation?, in db: Database) throws {
        let row = try Row.fetchOne(db, sql: "SELECT * FROM session_reader_binding WHERE singleton_id = 1")
        guard let active else {
            guard row == nil else { throw SessionStoreError.staleHistoryBinding }
            return
        }
        guard let row else { throw SessionStoreError.staleHistoryBinding }
        let fields = PublicationRecordFields(row)
        guard try fields.uuid("binding_id") == active.bindingID,
            try fields.uuid("activation_token") == active.token else { throw SessionStoreError.staleHistoryBinding }
    }

    static func requireCheckpointOwner(editionID: FeedEditionID, activation: BindingActivation?, in db: Database) throws {
        try requireActivation(activation, in: db)
        let edition = PersistenceValueCoding.uuid(editionID.rawValue)
        guard let activation else {
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_history_editions WHERE edition_id = ?)",
                arguments: [edition]) == false else { throw SessionStoreError.staleHistoryBinding }
            return
        }
        guard try Bool.fetchOne(db, sql: """
            SELECT EXISTS(SELECT 1 FROM reader_history_editions e JOIN reader_history_bindings b ON b.id = e.binding_id
                WHERE e.edition_id = ? AND b.id = ? AND b.active_edition_id = e.edition_id)
            """, arguments: [edition, PersistenceValueCoding.uuid(activation.bindingID)]) == true else {
            throw SessionStoreError.staleHistoryBinding
        }
    }

    static func persistOwned(_ checkpoint: CheckpointRecord, bindingID: UUID, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO reader_history_checkpoints(binding_id, edition_id, card_id, anchor_placement, updated_at, anchor_top_delta, anchor_height)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(binding_id, edition_id) DO UPDATE SET card_id = excluded.card_id,
                anchor_placement = excluded.anchor_placement, updated_at = excluded.updated_at,
                anchor_top_delta = excluded.anchor_top_delta, anchor_height = excluded.anchor_height
            """, arguments: [PersistenceValueCoding.uuid(bindingID), PersistenceValueCoding.uuid(checkpoint.editionID.rawValue),
                PersistenceValueCoding.uuid(checkpoint.cardID.rawValue), checkpoint.anchorPlacement,
                checkpoint.updatedAt.timeIntervalSince1970, checkpoint.topDelta, checkpoint.cardHeight])
    }

    static func seedBindingCheckpoint(bindingID: UUID, editionID: FeedEditionID, in db: Database) throws {
        let binding = PersistenceValueCoding.uuid(bindingID), edition = PersistenceValueCoding.uuid(editionID.rawValue)
        guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_history_checkpoints WHERE binding_id = ? AND edition_id = ?)",
            arguments: [binding, edition]) == false else { return }
        let row = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE edition_id = ?", arguments: [edition])
            ?? Row.fetchOne(db, sql: "SELECT * FROM context_checkpoints WHERE edition_id = ? ORDER BY updated_at DESC LIMIT 1", arguments: [edition])
        if let row { try persistOwned(checkpoint(row), bindingID: bindingID, in: db) }
    }
}
