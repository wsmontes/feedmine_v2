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
// without a second walk, and there is no queue whose cap or lifetime can become product eligibility. Two bounded
// readers exist: the pass (`passPage`, read-only, cursor-ordered) that a reconsideration opportunity walks one page
// at a time, and the rotating preparation page (`page`) that lets media work reach the rows behind the last one.
// Neither bound evicts a row.
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

/// Where a pass over the deferred rows continues: the deferral instant and the origin of the last row read.
/// The durable order is `(media_deferred_at, origin_record_id)`, so this cursor names a position in that order
/// without repeating a row and without any state of its own.
public struct MediaDeferralCursor: Hashable, Sendable {
    public let deferredAt: Date
    public let originRecordID: OriginRecordID

    public init(deferredAt: Date, originRecordID: OriginRecordID) {
        self.deferredAt = deferredAt
        self.originRecordID = originRecordID
    }
}

/// One bounded page of a pass; `next` is where the same reader continues, or nil when the page ended the queue.
public struct MediaDeferralPassPage: Sendable {
    public let records: [MediaDeferralRecord]
    public let next: MediaDeferralCursor?

    public init(records: [MediaDeferralRecord], next: MediaDeferralCursor?) {
        self.records = records
        self.next = next
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

    /// One bounded page of `editionID`'s deferred rows, longest-waiting first. The page rotates the rows it returns
    /// so the next preparation sees the rows behind them: preparation is a work bound, not an eligibility decision,
    /// and a row is never evicted by it.
    public func page(editionID: FeedEditionID, limit: Int, offerAt date: Date) throws -> [MediaDeferralRecord] {
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

    /// One read-only page of the durable pass, ordered by the deferral itself (`media_deferred_at`, then origin).
    /// Nothing is stamped: the pass is a review of rows that already exist, and a consumer that stops early leaves
    /// every row exactly where it was. `next` is the cursor of the last row of a page that has rows behind it; nil
    /// means this page ended the queue, so a caller never pays a second read for an empty page.
    public func passPage(editionID: FeedEditionID, limit: Int,
        after cursor: MediaDeferralCursor?) throws -> MediaDeferralPassPage {
        guard limit > 0, limit < Int.max else { return MediaDeferralPassPage(records: [], next: nil) }
        let edition = PersistenceValueCoding.uuid(editionID.rawValue)
        var sql = """
            SELECT origin_record_id, origin_revision_id, COALESCE(media_deferred_at, 0) AS deferred_at
            FROM selection_supply WHERE media_deferred_edition_id = ?
            """
        var arguments: [DatabaseValue] = [edition.databaseValue]
        if let cursor {
            let deferredAt = try PersistenceValueCoding.date(cursor.deferredAt, field: "media_deferral_cursor")
            sql += """
                 AND (COALESCE(media_deferred_at, 0) > ?
                      OR (COALESCE(media_deferred_at, 0) = ? AND origin_record_id > ?))
                """
            arguments.append(deferredAt.databaseValue)
            arguments.append(deferredAt.databaseValue)
            arguments.append(PersistenceValueCoding.uuid(cursor.originRecordID.rawValue).databaseValue)
        }
        sql += " ORDER BY COALESCE(media_deferred_at, 0), origin_record_id LIMIT ?"
        // One row past the page answers "are there rows behind it?" without a second read or an empty page.
        arguments.append((limit + 1).databaseValue)
        // The reader runs on a database queue: hand it values, never the mutable builders. Database values are the
        // point where the binding is already resolved, so the non-failable initializer states it without an optional.
        let query = sql
        let boundArguments = StatementArguments(arguments)
        return try database.read { db in
            let rows = try Row.fetchAll(db, sql: query, arguments: boundArguments)
            var records: [MediaDeferralRecord] = []
            var last: MediaDeferralCursor?
            for row in rows.prefix(limit) {
                let origin: String = row["origin_record_id"]
                let revision: String = row["origin_revision_id"]
                let deferred: Double = row["deferred_at"]
                let originRecordID = OriginRecordID(rawValue: try PersistenceValueCoding.uuid(
                    origin, field: "origin_record_id"))
                let deferredAt = try PersistenceValueCoding.date(deferred, field: "media_deferred_at")
                records.append(MediaDeferralRecord(editionID: editionID, originRecordID: originRecordID,
                    originRevisionID: OriginRevisionID(rawValue: try PersistenceValueCoding.uuid(
                        revision, field: "origin_revision_id"))))
                last = MediaDeferralCursor(deferredAt: deferredAt, originRecordID: originRecordID)
            }
            return MediaDeferralPassPage(records: records, next: rows.count > limit ? last : nil)
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
