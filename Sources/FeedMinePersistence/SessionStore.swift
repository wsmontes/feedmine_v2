// File: SessionStore.swift
// Module: FeedMinePersistence
// Owns: one durable logical checkpoint and transactional membership validation.
// Does not own: SessionCursor semantics, pixels, context duplication or runtime transitions.

import Foundation
import GRDB
import FeedMineDomain

public enum SessionStoreError: Error, Equatable, Sendable {
    case checkpointAlreadyExists
    case invalidPlacement
    case invalidMembership
    case corruption(String)
    case invalidRepresentation(String)
}

public struct SessionStore: Sendable {
    private let database: RuntimeDatabase
    public init(database: RuntimeDatabase) { self.database = database }

    public struct CheckpointRecord: Hashable, Sendable {
        public let editionID: FeedEditionID
        public let cardID: PublicationCardID
        public let anchorPlacement: String
        public let updatedAt: Date
        public init(editionID: FeedEditionID, cardID: PublicationCardID, anchorPlacement: String, updatedAt: Date) {
            self.editionID = editionID
            self.cardID = cardID
            self.anchorPlacement = anchorPlacement
            self.updatedAt = updatedAt
        }
    }

    public func saveCheckpoint(_ checkpoint: CheckpointRecord) throws {
        try database.write { db in
            guard ["top", "center"].contains(checkpoint.anchorPlacement) else { throw SessionStoreError.invalidPlacement }
            guard try Self.member(db, editionID: checkpoint.editionID, cardID: checkpoint.cardID) else { throw SessionStoreError.invalidMembership }
            let time: Double
            do { time = try PersistenceValueCoding.date(checkpoint.updatedAt, field: "updated_at") }
            catch { throw SessionStoreError.invalidRepresentation("updated_at") }
            try db.execute(sql: """
                INSERT INTO session_checkpoint (singleton_id, edition_id, card_id, anchor_placement, updated_at)
                VALUES (1, ?, ?, ?, ?)
                ON CONFLICT(singleton_id) DO UPDATE SET edition_id = excluded.edition_id,
                    card_id = excluded.card_id, anchor_placement = excluded.anchor_placement, updated_at = excluded.updated_at
                """, arguments: [PersistenceValueCoding.uuid(checkpoint.editionID.rawValue),
                    PersistenceValueCoding.uuid(checkpoint.cardID.rawValue), checkpoint.anchorPlacement, time])
            try Self.persistContext(checkpoint, in: db)
            try PublicationStore.markSeen(editionID: checkpoint.editionID, cardID: checkpoint.cardID, in: db)
        }
    }

    /// Inserts the first durable position inside the first-publication transaction.
    static func insertInitialCheckpoint(_ checkpoint: CheckpointRecord, in db: Database) throws {
        guard ["top", "center"].contains(checkpoint.anchorPlacement) else { throw SessionStoreError.invalidPlacement }
        guard try member(db, editionID: checkpoint.editionID, cardID: checkpoint.cardID) else { throw SessionStoreError.invalidMembership }
        let time: Double
        do { time = try PersistenceValueCoding.date(checkpoint.updatedAt, field: "updated_at") }
        catch { throw SessionStoreError.invalidRepresentation("updated_at") }
        guard try Int.fetchOne(db, sql: "SELECT count(*) FROM session_checkpoint") == 0 else {
            throw SessionStoreError.checkpointAlreadyExists
        }
        try db.execute(sql: """
            INSERT INTO session_checkpoint (singleton_id, edition_id, card_id, anchor_placement, updated_at)
            VALUES (1, ?, ?, ?, ?)
            """, arguments: [PersistenceValueCoding.uuid(checkpoint.editionID.rawValue),
                PersistenceValueCoding.uuid(checkpoint.cardID.rawValue), checkpoint.anchorPlacement, time])
        try persistContext(checkpoint, in: db)
        try PublicationStore.markSeen(editionID: checkpoint.editionID, cardID: checkpoint.cardID, in: db)
    }

    public func checkpoint() throws -> CheckpointRecord? {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1") else { return nil }
            do {
                let fields = PublicationRecordFields(row)
                let edition = FeedEditionID(rawValue: try fields.uuid("edition_id"))
                let card = PublicationCardID(rawValue: try fields.uuid("card_id"))
                let placement = try fields.string("anchor_placement")
                guard ["top", "center"].contains(placement), try Self.member(db, editionID: edition, cardID: card) else {
                    throw SessionStoreError.corruption("checkpoint membership/placement")
                }
                return CheckpointRecord(editionID: edition, cardID: card, anchorPlacement: placement, updatedAt: try fields.date("updated_at"))
            } catch let error as PublicationStoreError {
                throw SessionStoreError.corruption("checkpoint representation: \(error)")
            }
        }
    }

    /// Selects the saved position for a logical context *identity* (T6: the whole key — surface, preset,
    /// filter and search scope — so two filtered contexts of the same surface never share a position).
    /// Old history/checkpoints remain retained.
    public func activateContext(_ key: ContextKey) throws {
        try database.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1") {
                try Self.persistContext(Self.decode(row, in: db), in: db)
            }
            try db.execute(sql: "DELETE FROM session_checkpoint WHERE singleton_id = 1")
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM context_checkpoints WHERE context_identity = ?",
                arguments: [key.canonicalIdentity]) {
                let saved = try Self.decode(row, in: db)
                try db.execute(sql: "INSERT INTO session_checkpoint VALUES (1, ?, ?, ?, ?)", arguments: [
                    PersistenceValueCoding.uuid(saved.editionID.rawValue), PersistenceValueCoding.uuid(saved.cardID.rawValue),
                    saved.anchorPlacement, saved.updatedAt.timeIntervalSince1970])
            }
        }
    }

    public func clearActiveCheckpoint() throws {
        try database.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM session_checkpoint WHERE singleton_id = 1") {
                try Self.persistContext(Self.decode(row, in: db), in: db)
            }
            try db.execute(sql: "DELETE FROM session_checkpoint WHERE singleton_id = 1")
        }
    }

    /// Drops the saved position of one context identity. Used when the *behaviour* of that identity changed —
    /// an edited recipe, a new policy — because a position inside an Edition published under the old behaviour
    /// is not a position in what the reader now reads.
    public func clearCheckpoint(for key: ContextKey) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM context_checkpoints WHERE context_identity = ?",
                arguments: [key.canonicalIdentity])
        }
    }

    /// The saved position of a context identity, or nil when that identity never had one.
    public func checkpoint(for key: ContextKey) throws -> CheckpointRecord? {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM context_checkpoints WHERE context_identity = ?",
                arguments: [key.canonicalIdentity]) else { return nil }
            return try Self.decode(row, in: db)
        }
    }

    /// Surface-only convenience: the plain, unfiltered context of that request.
    public func activateContext(_ request: FeedContextRequest) throws {
        try activateContext(ContextKey(request: request))
    }

    public func checkpoint(for request: FeedContextRequest) throws -> CheckpointRecord? {
        try checkpoint(for: ContextKey(request: request))
    }

    private static func contextIdentifier(_ request: FeedContextRequest) -> String {
        switch request {
        case .main: "main"
        case .source(let source): "source:" + PersistenceValueCoding.uuid(source.rawValue)
        case .search(let search): "search:" + search.query
        }
    }

    private static func persistContext(_ checkpoint: CheckpointRecord, in db: Database) throws {
        // The identity comes from the Edition (one implementation of it, in `ContextKey`); the reduced
        // `context_key` text is still written for one release so an older build can read this database.
        // A row without an identity cannot be filed: it is skipped rather than merged into another context.
        try db.execute(sql: """
            INSERT INTO context_checkpoints(context_identity, context_key, context_key_json, edition_id, card_id, anchor_placement, updated_at)
            SELECT e.context_identity,
                CASE e.context_kind WHEN 'main' THEN 'main' WHEN 'source' THEN 'source:' || e.context_source_id
                    WHEN 'search' THEN 'search:' || e.context_search_query END,
                e.context_key_json, e.id, ?, ?, ? FROM feed_editions e
            WHERE e.id = ? AND e.context_identity <> ''
            ON CONFLICT(context_identity) DO UPDATE SET context_key = excluded.context_key,
                context_key_json = excluded.context_key_json, edition_id = excluded.edition_id,
                card_id = excluded.card_id, anchor_placement = excluded.anchor_placement,
                updated_at = excluded.updated_at
            """, arguments: [PersistenceValueCoding.uuid(checkpoint.cardID.rawValue), checkpoint.anchorPlacement,
                checkpoint.updatedAt.timeIntervalSince1970, PersistenceValueCoding.uuid(checkpoint.editionID.rawValue)])
    }

    private static func decode(_ row: Row, in db: Database) throws -> CheckpointRecord {
        let fields = PublicationRecordFields(row)
        let edition = FeedEditionID(rawValue: try fields.uuid("edition_id"))
        let card = PublicationCardID(rawValue: try fields.uuid("card_id"))
        let placement = try fields.string("anchor_placement")
        guard ["top", "center"].contains(placement), try member(db, editionID: edition, cardID: card) else {
            throw SessionStoreError.corruption("context checkpoint membership/placement")
        }
        return CheckpointRecord(editionID: edition, cardID: card, anchorPlacement: placement, updatedAt: try fields.date("updated_at"))
    }

    private static func member(_ db: Database, editionID: FeedEditionID, cardID: PublicationCardID) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS(SELECT 1 FROM published_cards c
                JOIN feed_segments s ON s.id = c.segment_id JOIN feed_editions e ON e.id = s.edition_id
                WHERE c.id = ? AND e.id = ?)
            """, arguments: [PersistenceValueCoding.uuid(cardID.rawValue), PersistenceValueCoding.uuid(editionID.rawValue)]) == true
    }
}
