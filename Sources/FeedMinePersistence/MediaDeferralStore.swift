//
// File: MediaDeferralStore.swift
// Module: FeedMinePersistence
//
// Responsibility:
//   Durable state of the stories an Edition's one-way walk skipped while their media was pending.
//
// Does not own:
//   Readiness, selection, publication or media work. A row only states that the story at its current revision was
//   deferred by that Edition's opportunity; whether it may be published is decided by the existing slice, selection
//   and exposure rules.
//
// Why this lives on `selection_supply` instead of a queue: the skip is a property of a supply row, and supply is
// already the durable authority the walk advances through. Storing it there means a new process finds every skip
// without a second walk, and there is no queue whose cap or lifetime can become product eligibility. The page an
// opportunity reads is bounded (`ceiling`), but a row is rotated, never evicted by that bound.
//

import Foundation
import GRDB
import FeedMineDomain

public struct MediaDeferralRecord: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let originRecordID: OriginRecordID
    public let originRevisionID: OriginRevisionID

    public init(editionID: FeedEditionID, originRecordID: OriginRecordID,
        originRevisionID: OriginRevisionID) {
        self.editionID = editionID
        self.originRecordID = originRecordID
        self.originRevisionID = originRevisionID
    }
}

public struct MediaDeferralStore: Sendable {
    private let database: RuntimeDatabase

    public init(database: RuntimeDatabase) { self.database = database }

    /// Records every deferral in one write. A row already deferred at the same revision keeps its first instant
    /// and its rotation position; a newer revision is a different story and starts from zero. A record whose
    /// supply row is gone or has a different current revision is not created: there is nothing to defer.
    public func record(_ records: [MediaDeferralRecord], at date: Date) throws {
        guard !records.isEmpty else { return }
        let time = try PersistenceValueCoding.date(date, field: "media_deferred_at")
        try database.write { db in
            for record in records {
                try db.execute(sql: """
                    UPDATE selection_supply SET
                        media_deferred_edition_id = ?,
                        media_offered_at = CASE WHEN origin_revision_id = ?
                            THEN media_offered_at ELSE NULL END,
                        media_deferred_at = CASE WHEN origin_revision_id = ?
                            THEN COALESCE(media_deferred_at, ?) ELSE ? END
                    WHERE origin_record_id = ? AND origin_revision_id = ?
                    """, arguments: [PersistenceValueCoding.uuid(record.editionID.rawValue),
                        PersistenceValueCoding.uuid(record.originRevisionID.rawValue),
                        PersistenceValueCoding.uuid(record.originRevisionID.rawValue), time, time,
                        PersistenceValueCoding.uuid(record.originRecordID.rawValue),
                        PersistenceValueCoding.uuid(record.originRevisionID.rawValue)])
            }
        }
    }

    /// Clears the deferral of stories that are definitively settled. Phrased as the revision it was recorded for:
    /// a newer revision's deferral is never cleared by the old one's settlement.
    public func forget(_ records: [MediaDeferralRecord]) throws {
        guard !records.isEmpty else { return }
        try database.write { db in
            for record in records {
                try db.execute(sql: """
                    UPDATE selection_supply SET
                        media_deferred_edition_id = NULL, media_deferred_at = NULL, media_offered_at = NULL
                    WHERE origin_record_id = ? AND origin_revision_id = ?
                        AND media_deferred_edition_id = ?
                    """, arguments: [PersistenceValueCoding.uuid(record.originRecordID.rawValue),
                        PersistenceValueCoding.uuid(record.originRevisionID.rawValue),
                        PersistenceValueCoding.uuid(record.editionID.rawValue)])
            }
        }
    }

    /// One bounded page of `editionID`'s deferred rows, longest-waiting first: never-offered rows before offered
    /// ones, then the oldest offer, then the oldest deferral. When `offerAt` is non-nil the page is rotated by
    /// stamping those rows, so the next opportunity sees the rows behind them instead of the same prefix forever.
    /// The rotation is a work bound, not an eligibility decision: every row is still returned eventually.
    public func page(editionID: FeedEditionID, limit: Int, offerAt date: Date?) throws -> [MediaDeferralRecord] {
        guard limit > 0 else { return [] }
        let edition = PersistenceValueCoding.uuid(editionID.rawValue)
        let read: @Sendable (Database) throws -> [MediaDeferralRecord] = { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT origin_record_id, origin_revision_id FROM selection_supply
                WHERE media_deferred_edition_id = ?
                ORDER BY media_offered_at IS NOT NULL,
                    COALESCE(media_offered_at, 0), COALESCE(media_deferred_at, 0), origin_record_id
                LIMIT ?
                """, arguments: [edition, limit])
            return try rows.map { row in
                let origin: String = row["origin_record_id"]
                let revision: String = row["origin_revision_id"]
                return MediaDeferralRecord(editionID: editionID,
                    originRecordID: OriginRecordID(rawValue: try PersistenceValueCoding.uuid(
                        origin, field: "origin_record_id")),
                    originRevisionID: OriginRevisionID(rawValue: try PersistenceValueCoding.uuid(
                        revision, field: "origin_revision_id")))
            }
        }
        guard let date else { return try database.read(read) }
        let time = try PersistenceValueCoding.date(date, field: "media_offered_at")
        return try database.write { db in
            let records = try read(db)
            for record in records {
                try db.execute(sql: """
                    UPDATE selection_supply SET media_offered_at = ?
                    WHERE origin_record_id = ? AND origin_revision_id = ? AND media_deferred_edition_id = ?
                    """, arguments: [time, PersistenceValueCoding.uuid(record.originRecordID.rawValue),
                        PersistenceValueCoding.uuid(record.originRevisionID.rawValue), edition])
            }
            return records
        }
    }

    /// How many rows are deferred, for one Edition when given. Diagnostics and tests only; no decision reads it.
    public func count(editionID: FeedEditionID? = nil) throws -> Int {
        try database.read { db in
            if let editionID {
                return try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM selection_supply WHERE media_deferred_edition_id = ?
                    """, arguments: [PersistenceValueCoding.uuid(editionID.rawValue)]) ?? 0
            }
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM selection_supply WHERE media_deferred_edition_id IS NOT NULL
                """) ?? 0
        }
    }
}
