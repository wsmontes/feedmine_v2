import Foundation
import GRDB
import FeedMineDomain

extension SessionStore {
    /// A hidden replacement may publish/read its own history while the presented reader keeps its token.
    /// The selected preparation and its predecessor are durable fences, never permission to save a viewport.
    public func prepareBinding(_ bindingID: UUID) throws -> BindingActivation {
        try database.write { db in
            let id = PersistenceValueCoding.uuid(bindingID)
            guard let binding = try Row.fetchOne(db, sql: "SELECT * FROM reader_history_bindings WHERE id = ?", arguments: [id]) else {
                throw SessionStoreError.missingHistoryBinding
            }
            let previous = try Row.fetchOne(db, sql: "SELECT * FROM reader_history_preparations WHERE binding_id = ?", arguments: [id])
            let base = try PublicationRecordFields(binding).optionalUUID("active_edition_id")
            let priorBase = try previous.flatMap { try PublicationRecordFields($0).optionalUUID("base_edition_id") }
            let candidate = try previous.flatMap { try PublicationRecordFields($0).optionalUUID("edition_id") }
            var editionID = ((priorBase == base ? candidate : nil) ?? base).map { FeedEditionID(rawValue: $0) }
            if let declared = editionID, let point = try Self.ownedCheckpoint(bindingID: bindingID, editionID: declared, in: db),
                let location = try PublicationStore.location(ofCard: point.cardID, in: db), location.editionID != declared {
                guard try Self.isOwned(location.editionID, by: bindingID, in: db) else { throw SessionStoreError.invalidMembership }
                let corrected = CheckpointRecord(editionID: location.editionID, cardID: point.cardID,
                    anchorPlacement: point.anchorPlacement, updatedAt: point.updatedAt, topDelta: point.topDelta, cardHeight: point.cardHeight)
                try Self.persistOwned(corrected, bindingID: bindingID, in: db)
                editionID = location.editionID
            }
            let point = try editionID.flatMap { try Self.ownedCheckpoint(bindingID: bindingID, editionID: $0, in: db) }
            let current = try Row.fetchOne(db, sql: "SELECT * FROM session_reader_binding WHERE singleton_id = 1")
            let currentFields = current.map(PublicationRecordFields.init)
            let token = UUID()
            try db.execute(sql: "UPDATE reader_history_preparations SET selected = 0 WHERE selected = 1")
            try db.execute(sql: """
                INSERT INTO reader_history_preparations(binding_id, edition_id, base_edition_id, checkpoint_present, activation_token,
                    selected, replacing_binding_id, replacing_activation_token) VALUES (?, ?, ?, ?, ?, 1, ?, ?)
                ON CONFLICT(binding_id) DO UPDATE SET edition_id = excluded.edition_id, base_edition_id = excluded.base_edition_id,
                    checkpoint_present = excluded.checkpoint_present, activation_token = excluded.activation_token,
                    selected = 1, replacing_binding_id = excluded.replacing_binding_id,
                    replacing_activation_token = excluded.replacing_activation_token
                """, arguments: [id, editionID.map { PersistenceValueCoding.uuid($0.rawValue) }, base.map(PersistenceValueCoding.uuid), point == nil ? 0 : 1,
                    PersistenceValueCoding.uuid(token), currentFields?.optionalString("binding_id"),
                    currentFields?.optionalString("activation_token")])
            return BindingActivation(bindingID: bindingID, token: token)
        }
    }

    /// Explicit compatibility decision; nil starts fresh without erasing history. Retargeting returns
    /// a new captured handle so an older A callback cannot regain authority after A→empty→A.
    public func resetPreparedBinding(_ handle: BindingActivation, editionID: FeedEditionID?) throws -> BindingActivation {
        try database.write { db in
            _ = try Self.requirePreparation(handle, in: db)
            if let editionID, try !Self.isOwned(editionID, by: handle.bindingID, in: db) { throw SessionStoreError.invalidMembership }
            let point = try editionID.flatMap { try Self.ownedCheckpoint(bindingID: handle.bindingID, editionID: $0, in: db) }
            let token = UUID()
            try db.execute(sql: "UPDATE reader_history_preparations SET edition_id = ?, checkpoint_present = ?, activation_token = ? WHERE binding_id = ?",
                arguments: [editionID.map { PersistenceValueCoding.uuid($0.rawValue) }, point == nil ? 0 : 1,
                    PersistenceValueCoding.uuid(token), PersistenceValueCoding.uuid(handle.bindingID)])
            return BindingActivation(bindingID: handle.bindingID, token: token)
        }
    }

    @discardableResult
    public func cancelPreparedBinding(_ handle: BindingActivation) throws -> Bool {
        try database.write { db in
            try db.execute(sql: "UPDATE reader_history_preparations SET selected = 0 WHERE binding_id = ? AND activation_token = ? AND selected = 1",
                arguments: [PersistenceValueCoding.uuid(handle.bindingID), PersistenceValueCoding.uuid(handle.token)])
            return db.changesCount == 1
        }
    }

    public func isPreparedBinding(_ handle: BindingActivation) throws -> Bool {
        try database.read { db in
            if try Self.isCurrentActivation(handle, in: db) { return false }
            _ = try Self.requirePreparation(handle, in: db)
            return true
        }
    }

    /// The same captured token becomes current. No callback reacquires authority during this cutover.
    public func promotePreparedBinding(_ handle: BindingActivation) throws {
        try database.write { db in
            let prepared = try Self.requirePreparation(handle, in: db), fields = PublicationRecordFields(prepared)
            let editionID = try fields.optionalUUID("edition_id").map { FeedEditionID(rawValue: $0) }
            let present = try fields.integer("checkpoint_present") == 1
            let target = try editionID.flatMap { try Self.ownedCheckpoint(bindingID: handle.bindingID, editionID: $0, in: db) }
            if let current = try Row.fetchOne(db, sql: "SELECT * FROM session_reader_binding WHERE singleton_id = 1") {
                let active = PublicationRecordFields(current)
                if try active.integer("checkpoint_present") == 1,
                    let point = try Self.ownedCheckpoint(bindingID: active.uuid("binding_id"), in: db) {
                    try Self.persistOwned(point, bindingID: active.uuid("binding_id"), in: db)
                }
            } else if let row = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1") {
                let point = try Self.checkpoint(row)
                let corrected = try PublicationStore.location(ofCard: point.cardID, in: db).map {
                    CheckpointRecord(editionID: $0.editionID, cardID: point.cardID, anchorPlacement: point.anchorPlacement,
                        updatedAt: point.updatedAt, topDelta: point.topDelta, cardHeight: point.cardHeight)
                }
                if corrected == nil || corrected != target { try Self.persistContext(point, in: db) }
            }
            let id = PersistenceValueCoding.uuid(handle.bindingID)
            try db.execute(sql: "UPDATE reader_history_bindings SET active_edition_id = ? WHERE id = ?",
                arguments: [editionID.map { PersistenceValueCoding.uuid($0.rawValue) }, id])
            try db.execute(sql: "DELETE FROM session_checkpoint WHERE singleton_id = 1")
            try db.execute(sql: """
                INSERT INTO session_reader_binding(singleton_id, binding_id, activation_token, checkpoint_present) VALUES (1, ?, ?, ?)
                ON CONFLICT(singleton_id) DO UPDATE SET binding_id = excluded.binding_id,
                    activation_token = excluded.activation_token, checkpoint_present = excluded.checkpoint_present
                """, arguments: [id, PersistenceValueCoding.uuid(handle.token), present ? 1 : 0])
            if present {
                try db.execute(sql: """
                    INSERT INTO session_checkpoint(singleton_id, edition_id, card_id, anchor_placement, updated_at, anchor_top_delta, anchor_height)
                    SELECT 1, c.edition_id, c.card_id, c.anchor_placement, c.updated_at, c.anchor_top_delta, c.anchor_height
                    FROM reader_history_checkpoints c JOIN published_cards p ON p.id = c.card_id
                    JOIN feed_segments s ON s.id = p.segment_id AND s.edition_id = c.edition_id
                    WHERE c.binding_id = ? AND c.edition_id = ?
                    """, arguments: [id, editionID.map { PersistenceValueCoding.uuid($0.rawValue) }])
                if let target, try Self.member(db, editionID: target.editionID, cardID: target.cardID) {
                    try PublicationStore.markSeen(editionID: target.editionID, cardID: target.cardID, in: db)
                }
            }
            try db.execute(sql: "UPDATE reader_history_preparations SET selected = 0, edition_id = NULL, checkpoint_present = 0 WHERE binding_id = ?",
                arguments: [id])
        }
    }

    static func isCurrentActivation(_ handle: BindingActivation, in db: Database) throws -> Bool {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM session_reader_binding WHERE singleton_id = 1") else { return false }
        let fields = PublicationRecordFields(row)
        return try fields.uuid("binding_id") == handle.bindingID && fields.uuid("activation_token") == handle.token
    }

    static func requirePreparation(_ handle: BindingActivation, in db: Database) throws -> Row {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM reader_history_preparations WHERE binding_id = ? AND activation_token = ? AND selected = 1",
            arguments: [PersistenceValueCoding.uuid(handle.bindingID), PersistenceValueCoding.uuid(handle.token)]) else {
            throw SessionStoreError.staleHistoryBinding
        }
        let fields = PublicationRecordFields(row)
        let base = try String.fetchOne(db, sql: "SELECT active_edition_id FROM reader_history_bindings WHERE id = ?",
            arguments: [PersistenceValueCoding.uuid(handle.bindingID)])
        guard try fields.optionalString("base_edition_id") == base else { throw SessionStoreError.staleHistoryBinding }
        let current = try Row.fetchOne(db, sql: "SELECT * FROM session_reader_binding WHERE singleton_id = 1")
        let active = current.map(PublicationRecordFields.init)
        guard try fields.optionalString("replacing_binding_id") == active?.optionalString("binding_id"),
            try fields.optionalString("replacing_activation_token") == active?.optionalString("activation_token") else {
            throw SessionStoreError.staleHistoryBinding
        }
        return row
    }

    static func requirePublicationActivation(_ handle: BindingActivation?, in db: Database) throws {
        guard let handle else { try requireActivation(nil, in: db); return }
        if try isCurrentActivation(handle, in: db) { return }
        _ = try requirePreparation(handle, in: db)
    }

    static func scopedEdition(_ handle: BindingActivation, in db: Database) throws -> FeedEditionID? {
        let row: Row
        let field: String
        if try isCurrentActivation(handle, in: db) {
            guard let current = try Row.fetchOne(db, sql: "SELECT * FROM reader_history_bindings WHERE id = ?",
                arguments: [PersistenceValueCoding.uuid(handle.bindingID)]) else { throw SessionStoreError.missingHistoryBinding }
            row = current; field = "active_edition_id"
        } else { row = try requirePreparation(handle, in: db); field = "edition_id" }
        return try PublicationRecordFields(row).optionalUUID(field).map { FeedEditionID(rawValue: $0) }
    }

    static func ownedCheckpoint(bindingID: UUID, editionID: FeedEditionID, in db: Database) throws -> CheckpointRecord? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM reader_history_checkpoints WHERE binding_id = ? AND edition_id = ?",
            arguments: [PersistenceValueCoding.uuid(bindingID), PersistenceValueCoding.uuid(editionID.rawValue)]) else { return nil }
        return try checkpoint(row)
    }

    static func isOwned(_ editionID: FeedEditionID, by bindingID: UUID, in db: Database) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM reader_history_editions WHERE binding_id = ? AND edition_id = ?)",
            arguments: [PersistenceValueCoding.uuid(bindingID), PersistenceValueCoding.uuid(editionID.rawValue)]) == true
    }
}
