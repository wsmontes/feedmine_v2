//
// File: SavedMediaAvailabilityStore.swift
// Module: FeedMinePersistence
//
// Responsibility:
// The durable availability of a saved occurrence's content: one row per saved published card, written by the
// owner that attempted the preparation and read by the saved surface.
//
// Does not own:
// Downloads, decoding or eviction policy. A card's availability is a fact about this store, not a function of
// what happens to be resident when a list is drawn — and it never rewrites `published_cards`.
//
// Owner directive 2026-10-17 §2: the link (a `reader_bookmark_memberships` row) and the availability of the
// content are different promises. This table states the second one, including the failure that must stay
// visible (`failed`, `insufficientSpace`) without deleting the first.

import Foundation
import GRDB
import FeedMineDomain

public struct SavedMediaAvailabilityRecord: Hashable, Sendable {
    public let cardID: PublicationCardID
    public let availability: SavedMediaAvailability
    public let updatedAt: Date
    /// How many preparation attempts produced this state. Zero means "recorded, not attempted yet".
    public let attempts: Int

    public init(cardID: PublicationCardID, availability: SavedMediaAvailability, updatedAt: Date, attempts: Int) {
        self.cardID = cardID
        self.availability = availability
        self.updatedAt = updatedAt
        self.attempts = attempts
    }
}

public struct SavedMediaAvailabilityStore: Sendable {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    /// Records the outcome of an observation or an attempt. One row per card, replaced in place: availability
    /// is a state, not a log, and the published occurrence it belongs to is never touched.
    ///
    /// `attempted` counts a preparation that actually ran; a save that merely records `pending` does not.
    public func record(cardID: PublicationCardID, availability: SavedMediaAvailability, at date: Date,
        attempted: Bool = false) throws {
        let key = PersistenceValueCoding.uuid(cardID.rawValue)
        let time = try PersistenceValueCoding.date(date, field: "updated_at")
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO saved_media_availability (card_id, availability, updated_at, attempts)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(card_id) DO UPDATE SET
                    availability = excluded.availability,
                    updated_at = excluded.updated_at,
                    attempts = saved_media_availability.attempts + excluded.attempts
                """, arguments: [key, availability.rawValue, time, attempted ? 1 : 0])
        }
    }

    public func availability(cardID: PublicationCardID) throws -> SavedMediaAvailabilityRecord? {
        let key = PersistenceValueCoding.uuid(cardID.rawValue)
        return try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM saved_media_availability WHERE card_id = ?",
                arguments: [key]) else { return nil }
            return try Self.decode(row)
        }
    }

    /// Every recorded availability, in one read — the saved surface's own query, never one per row.
    public func availabilities() throws -> [PublicationCardID: SavedMediaAvailabilityRecord] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM saved_media_availability")
            var records: [PublicationCardID: SavedMediaAvailabilityRecord] = [:]
            for row in rows {
                let record = try Self.decode(row)
                records[record.cardID] = record
            }
            return records
        }
    }

    /// The link is gone: its availability has no owner. Only rows for cards in no box are removed, so a card
    /// removed from one box but kept in another keeps its state.
    @discardableResult
    public func clearUnsaved() throws -> Int {
        try database.write { db in
            try db.execute(sql: """
                DELETE FROM saved_media_availability WHERE card_id NOT IN
                    (SELECT card_id FROM reader_bookmark_memberships)
                """)
            return db.changesCount
        }
    }

    public func clear(cardID: PublicationCardID) throws {
        let key = PersistenceValueCoding.uuid(cardID.rawValue)
        try database.write { db in
            try db.execute(sql: "DELETE FROM saved_media_availability WHERE card_id = ?", arguments: [key])
        }
    }

    /// Saved cards for the resume pass, least recently updated first. Every membership is included, even one
    /// without a recorded row (a save written outside the coordinator's path, e.g. an import): such a card claims
    /// nothing, and the pass is what gives it the availability it can actually open. `ready` is included on
    /// purpose too: a durable claim is re-verified when the app gets the chance, so an asset lost behind the
    /// store's back is demoted instead of being reported as available forever.
    public func savedCardIDs(limit: Int) throws -> [PublicationCardID] {
        guard limit > 0 else { return [] }
        return try database.read { db in
            try String.fetchAll(db, sql: """
                SELECT b.card_id FROM reader_bookmark_memberships b
                LEFT JOIN saved_media_availability a ON a.card_id = b.card_id
                GROUP BY b.card_id
                ORDER BY COALESCE(MIN(a.updated_at), MIN(b.added_at)), b.card_id
                LIMIT ?
                """, arguments: [limit]).map {
                    PublicationCardID(rawValue: try PublicationValueCoding.uuid($0, field: "card_id"))
                }
        }
    }

    private static func decode(_ row: Row) throws -> SavedMediaAvailabilityRecord {
        let raw: String = row["availability"]
        guard let availability = SavedMediaAvailability(rawValue: raw) else {
            throw PersistenceValueCodingError.corruption("saved media availability")
        }
        return SavedMediaAvailabilityRecord(
            cardID: PublicationCardID(rawValue: try PublicationValueCoding.uuid(row["card_id"], field: "card_id")),
            availability: availability,
            updatedAt: try PersistenceValueCoding.date(row["updated_at"], field: "updated_at"),
            attempts: row["attempts"])
    }
}
