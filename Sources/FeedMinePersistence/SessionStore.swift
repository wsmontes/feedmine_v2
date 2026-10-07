// File: SessionStore.swift
// Module: FeedMinePersistence
// Owns: one durable logical checkpoint and transactional membership validation.
// Does not own: SessionCursor semantics, pixels, context duplication or runtime transitions.

import Foundation
import GRDB
import FeedMineDomain

public enum SessionStoreError: Error, Equatable, Sendable {
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
        }
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

    private static func member(_ db: Database, editionID: FeedEditionID, cardID: PublicationCardID) throws -> Bool {
        try Bool.fetchOne(db, sql: """
            SELECT EXISTS(SELECT 1 FROM published_cards c
                JOIN feed_segments s ON s.id = c.segment_id JOIN feed_editions e ON e.id = s.edition_id
                WHERE c.id = ? AND e.id = ?)
            """, arguments: [PersistenceValueCoding.uuid(cardID.rawValue), PersistenceValueCoding.uuid(editionID.rawValue)]) == true
    }
}
