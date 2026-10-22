// Owns: durable current-supply deferrals for each resumable Edition (PD-9/F06).
// Does not own: readiness, selection, publication, downloads or scheduling.
// One association per Edition/origin; withdrawal cascades and revision replacement retires it. The table row, not
// an in-memory queue, is the authority: the page bounds work per opportunity, never eligibility. (The owner's D12 is
// image ageing, a different decision; this work is PD-9/F06 and must not be labelled D12.)
import Foundation
import GRDB
import FeedMineDomain

public struct MediaDeferralRecord: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let originRecordID: OriginRecordID
    public let originRevisionID: OriginRevisionID

    public init(editionID: FeedEditionID, originRecordID: OriginRecordID, originRevisionID: OriginRevisionID) {
        self.editionID = editionID
        self.originRecordID = originRecordID
        self.originRevisionID = originRevisionID
    }
}

public struct MediaDeferralStore: Sendable {
    private let database: RuntimeDatabase
    public init(database: RuntimeDatabase) { self.database = database }

    /// Admission and offers use the same time ordering: new arrivals cannot jump ahead of older offers forever.
    /// Repeated examination keeps the first instant and the place in the rotation. A newer revision is a different
    /// story, so it replaces the association and starts from zero. Nothing is written when the supply row is gone or
    /// no longer at the deferred revision: there is nothing to defer.
    public func record(_ records: [MediaDeferralRecord], at date: Date) throws {
        guard !records.isEmpty else { return }
        let time = try PersistenceValueCoding.date(date, field: "media_deferral.turn_at")
        try database.write { db in
            for record in records {
                try db.execute(sql: """
                    INSERT INTO selection_supply_media_deferrals
                        (edition_id, origin_record_id, origin_revision_id, turn_at)
                    SELECT ?, origin_record_id, origin_revision_id, ? FROM selection_supply
                    WHERE origin_record_id = ? AND origin_revision_id = ?
                    ON CONFLICT(edition_id, origin_record_id) DO UPDATE SET
                        origin_revision_id = excluded.origin_revision_id,
                        turn_at = excluded.turn_at
                    WHERE selection_supply_media_deferrals.origin_revision_id <> excluded.origin_revision_id
                    """, arguments: [PersistenceValueCoding.uuid(record.editionID.rawValue), time,
                        PersistenceValueCoding.uuid(record.originRecordID.rawValue),
                        PersistenceValueCoding.uuid(record.originRevisionID.rawValue)])
            }
        }
    }

    public func forget(_ records: [MediaDeferralRecord]) throws {
        guard !records.isEmpty else { return }
        try database.write { db in
            for record in records {
                try db.execute(sql: """
                    DELETE FROM selection_supply_media_deferrals
                    WHERE edition_id = ? AND origin_record_id = ? AND origin_revision_id = ?
                    """, arguments: [PersistenceValueCoding.uuid(record.editionID.rawValue),
                        PersistenceValueCoding.uuid(record.originRecordID.rawValue),
                        PersistenceValueCoding.uuid(record.originRevisionID.rawValue)])
            }
        }
    }

    /// Indexed bounded page. Read-only preparation observes the same turn that the slice subsequently offers.
    public func page(editionID: FeedEditionID, limit: Int, offerAt date: Date?) throws -> [MediaDeferralRecord] {
        guard limit > 0 else { return [] }
        let edition = PersistenceValueCoding.uuid(editionID.rawValue)
        let read: @Sendable (Database) throws -> [MediaDeferralRecord] = { db in
            try Row.fetchAll(db, sql: """
                SELECT origin_record_id, origin_revision_id FROM selection_supply_media_deferrals
                WHERE edition_id = ? ORDER BY turn_at, origin_record_id LIMIT ?
                """, arguments: [edition, limit]).map { row in
                    let origin: String = row["origin_record_id"], revision: String = row["origin_revision_id"]
                    return MediaDeferralRecord(editionID: editionID,
                        originRecordID: .init(rawValue: try PersistenceValueCoding.uuid(origin, field: "origin_record_id")),
                        originRevisionID: .init(rawValue: try PersistenceValueCoding.uuid(revision, field: "origin_revision_id")))
                }
        }
        guard let date else { return try database.read(read) }
        let time = try PersistenceValueCoding.date(date, field: "media_deferral.turn_at")
        return try database.write { db in
            let records = try read(db)
            for record in records {
                try db.execute(sql: """
                    UPDATE selection_supply_media_deferrals SET turn_at = ?
                    WHERE edition_id = ? AND origin_record_id = ? AND origin_revision_id = ?
                    """, arguments: [time, edition, PersistenceValueCoding.uuid(record.originRecordID.rawValue),
                        PersistenceValueCoding.uuid(record.originRevisionID.rawValue)])
            }
            return records
        }
    }

    public func count(editionID: FeedEditionID? = nil) throws -> Int {
        try database.read { db in
            if let editionID {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM selection_supply_media_deferrals WHERE edition_id = ?",
                    arguments: [PersistenceValueCoding.uuid(editionID.rawValue)]) ?? 0
            }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM selection_supply_media_deferrals") ?? 0
        }
    }
}
