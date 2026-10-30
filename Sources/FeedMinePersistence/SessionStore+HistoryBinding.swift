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
            try ReaderHistoryBindingStore.retainLegacyCheckpoints(in: db)
            try db.execute(sql: "UPDATE reader_history_preparations SET selected = 0 WHERE selected = 1")
            if let current = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1") {
                let point = try Self.checkpoint(current)
                let retained = try Self.ownedCheckpoint(bindingID: bindingID, in: db)
                let located = try PublicationStore.location(ofCard: point.cardID, in: db)
                let corrected = located.map { location in
                    CheckpointRecord(editionID: location.editionID, cardID: point.cardID,
                        anchorPlacement: point.anchorPlacement, updatedAt: point.updatedAt,
                        topDelta: point.topDelta, cardHeight: point.cardHeight)
                }
                // Explicit adoption may already retain this exact card-authoritative statement.
                // Re-filing its inconsistent legacy Edition would fail for an archived card (or
                // pollute an unrelated context). No source history needs rewriting in that case.
                if corrected == nil || corrected != retained {
                    try Self.persistContext(point, in: db)
                }
            }
            if let editionID = try PublicationRecordFields(binding).optionalUUID("active_edition_id") {
                try Self.seedBindingCheckpoint(bindingID: bindingID, editionID: FeedEditionID(rawValue: editionID), in: db)
            }
            try Self.reconcileOwnedEdition(bindingID: bindingID, in: db)
            let restoredPoint = try Self.ownedCheckpoint(bindingID: bindingID, in: db)
            let active = BindingActivation(bindingID: bindingID, token: UUID())
            try db.execute(sql: "DELETE FROM session_checkpoint WHERE singleton_id = 1")
            try db.execute(sql: """
                INSERT INTO session_reader_binding(singleton_id, binding_id, activation_token, checkpoint_present) VALUES (1, ?, ?, ?)
                ON CONFLICT(singleton_id) DO UPDATE SET binding_id = excluded.binding_id,
                    activation_token = excluded.activation_token, checkpoint_present = excluded.checkpoint_present
                """, arguments: [id, PersistenceValueCoding.uuid(active.token), restoredPoint == nil ? 0 : 1])
            // Retained archived/unknown anchors stay in owned history; only live cards fit the legacy FK.
            try db.execute(sql: """
                INSERT INTO session_checkpoint(singleton_id, edition_id, card_id, anchor_placement, updated_at, anchor_top_delta, anchor_height)
                SELECT 1, c.edition_id, c.card_id, c.anchor_placement, c.updated_at, c.anchor_top_delta, c.anchor_height
                FROM reader_history_checkpoints c JOIN reader_history_bindings b
                    ON b.id = c.binding_id AND b.active_edition_id = c.edition_id
                JOIN published_cards p ON p.id = c.card_id JOIN feed_segments s ON s.id = p.segment_id AND s.edition_id = c.edition_id
                WHERE b.id = ?
                """, arguments: [id])
            return active
        }
    }

    public func checkpoint(bindingID: UUID) throws -> CheckpointRecord? {
        try database.read { try Self.ownedCheckpoint(bindingID: bindingID, in: $0) }
    }

    /// An active reader handle never falls back to another context's singleton.
    public func checkpoint(bindingActivation: BindingActivation, contextKey: ContextKey? = nil) throws -> CheckpointRecord? {
        try database.read { db in
            try Self.requirePublicationActivation(bindingActivation, in: db)
            let editionID = try Self.scopedEdition(bindingActivation, in: db)
            if let contextKey {
                guard let row = try Row.fetchOne(db, sql: """
                    SELECT b.logical_identity, e.context_identity AS publication_identity
                    FROM reader_history_bindings b LEFT JOIN feed_editions e ON e.id = ? WHERE b.id = ?
                    """, arguments: [editionID.map { PersistenceValueCoding.uuid($0.rawValue) },
                        PersistenceValueCoding.uuid(bindingActivation.bindingID)]) else { throw SessionStoreError.missingHistoryBinding }
                let fields = PublicationRecordFields(row)
                guard try fields.string("logical_identity") == contextKey.canonicalIdentity
                    || fields.optionalString("publication_identity") == contextKey.canonicalIdentity else {
                    throw SessionStoreError.staleHistoryBinding
                }
            }
            let present: Bool
            if try Self.isCurrentActivation(bindingActivation, in: db) {
                present = try Bool.fetchOne(db, sql: "SELECT checkpoint_present FROM session_reader_binding WHERE singleton_id = 1") == true
            } else {
                present = try PublicationRecordFields(Self.requirePreparation(bindingActivation, in: db)).integer("checkpoint_present") == 1
            }
            guard present, let editionID else { return nil }
            return try Self.ownedCheckpoint(bindingID: bindingActivation.bindingID, editionID: editionID, in: db)
        }
    }

    public func validateBinding(_ activation: BindingActivation, editionID: FeedEditionID) throws {
        try database.read { try Self.requireCheckpointOwner(editionID: editionID, activation: activation, allowsPreparation: true, in: $0) }
    }

    /// A card's actual Edition is authoritative only inside this already-established reader owner.
    /// This runs during explicit activation, not as an implicit side effect of a history read.
    private static func reconcileOwnedEdition(bindingID: UUID, in db: Database) throws {
        guard let saved = try ownedCheckpoint(bindingID: bindingID, in: db),
            let located = try PublicationStore.location(ofCard: saved.cardID, in: db) else { return }
        guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_history_editions WHERE binding_id = ? AND edition_id = ?)",
            arguments: [PersistenceValueCoding.uuid(bindingID), PersistenceValueCoding.uuid(located.editionID.rawValue)]) == true else {
            throw SessionStoreError.invalidMembership
        }
        guard saved.editionID != located.editionID else { return }
        let corrected = CheckpointRecord(editionID: located.editionID, cardID: saved.cardID,
            anchorPlacement: saved.anchorPlacement, updatedAt: saved.updatedAt,
            topDelta: saved.topDelta, cardHeight: saved.cardHeight)
        try persistOwned(corrected, bindingID: bindingID, in: db)
        try db.execute(sql: "UPDATE reader_history_bindings SET active_edition_id = ? WHERE id = ?",
            arguments: [PersistenceValueCoding.uuid(located.editionID.rawValue), PersistenceValueCoding.uuid(bindingID)])
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

    static func requireCheckpointOwner(editionID: FeedEditionID, activation: BindingActivation?,
        allowsPreparation: Bool = false, in db: Database) throws {
        if allowsPreparation { try requirePublicationActivation(activation, in: db) }
        else { try requireActivation(activation, in: db) }
        guard let activation else {
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_history_editions WHERE edition_id = ?)",
                arguments: [PersistenceValueCoding.uuid(editionID.rawValue)]) == false else { throw SessionStoreError.staleHistoryBinding }
            return
        }
        guard try scopedEdition(activation, in: db) == editionID,
            try isOwned(editionID, by: activation.bindingID, in: db) else { throw SessionStoreError.staleHistoryBinding }
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
