//
// File: PlaybackPositionStore.swift
// Module: FeedMinePersistence
//
// Responsibility:
// Where the reader stopped listening: one position per published card, durable, small and written often. V1 kept
// this in `UserDefaults` (`lastPodcastPosition.<id>`); V2 keeps it beside the rest of the reader's own state, and
// the value's *semantics* — when a position is worth restoring, when completion clears it — belong to the player
// that produces it, not here.
//
// Does not own: playing anything (the app's player), the resume threshold (Runtime's protocol description) or
// which card is playable (Publication).
import Foundation
import GRDB
import FeedMineDomain

public struct ReaderPlaybackPosition: Hashable, Sendable {
    public let cardID: PublicationCardID
    public let position: TimeInterval
    public let duration: TimeInterval?

    public init(cardID: PublicationCardID, position: TimeInterval, duration: TimeInterval?) {
        self.cardID = cardID; self.position = position; self.duration = duration
    }
}

public struct PlaybackPositionStore: Sendable {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    /// Writes (or overwrites) the position for one card. A negative position is refused by the schema; a zero
    /// position is a position like any other, and the player decides whether it is worth keeping.
    public func save(_ position: TimeInterval, duration: TimeInterval?, for cardID: PublicationCardID,
        at date: Date = Date()) throws {
        let card = PersistenceValueCoding.uuid(cardID.rawValue)
        let time = try PersistenceValueCoding.date(date, field: "updated_at")
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO reader_playback_positions (card_id, position, duration, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(card_id) DO UPDATE SET position = excluded.position,
                    duration = excluded.duration, updated_at = excluded.updated_at
                """, arguments: [card, max(0, position), duration, time])
        }
    }

    public func position(for cardID: PublicationCardID) throws -> ReaderPlaybackPosition? {
        let card = PersistenceValueCoding.uuid(cardID.rawValue)
        return try database.read { db in
            try Row.fetchOne(db, sql: """
                SELECT card_id, position, duration FROM reader_playback_positions WHERE card_id = ?
                """, arguments: [card]).map { row in
                ReaderPlaybackPosition(cardID: cardID, position: row["position"], duration: row["duration"])
            }
        }
    }

    /// Forgets one card's position — what completion and an explicit "start over" do.
    public func clear(for cardID: PublicationCardID) throws {
        let card = PersistenceValueCoding.uuid(cardID.rawValue)
        try database.write { db in
            try db.execute(sql: "DELETE FROM reader_playback_positions WHERE card_id = ?", arguments: [card])
        }
    }
}
