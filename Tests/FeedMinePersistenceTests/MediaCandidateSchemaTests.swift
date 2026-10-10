import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class MediaCandidateSchemaTests: XCTestCase {
    private func key() -> String { UUID().uuidString.lowercased() }
    private func insertRevision(_ database: RuntimeDatabase) throws -> String {
        let origin = key(), revision = key()
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO origin_records (id, object_connector_kind, object_namespace, object_value,
                    object_role, availability, first_observed_at, last_observed_at)
                VALUES (?, 'test', 'objects', ?, 'object', 'available', 1, 1)
                """, arguments: [origin, origin])
            try db.execute(sql: "INSERT INTO origin_revisions (id, origin_record_id, observed_at) VALUES (?, ?, 1)", arguments: [revision, origin])
        }
        return revision
    }
    private func insertCandidate(_ database: RuntimeDatabase, revision: String, ordinal: Int = 0,
        role: String = "cardVisual", mediaClass: String = "image", width: Int? = nil, height: Int? = nil) throws {
        let id = key()
        try database.write { db in
            try db.execute(sql: """
                INSERT INTO media_candidates (id, origin_revision_id, ordinal, role, media_class,
                    remote_locator, declared_pixel_width, declared_pixel_height)
                VALUES (?, ?, ?, ?, ?, 'https://example.test/image', ?, ?)
                """, arguments: [id, revision, ordinal, role, mediaClass, width, height])
        }
    }
    private func constraint(_ body: () throws -> Void, kind: String) {
        XCTAssertThrowsError(try body()) {
            guard case let RuntimeDatabaseError.storage(code, message) = $0 else {
                return XCTFail("Expected SQLite constraint error, got \($0)")
            }
            XCTAssertEqual(code & 0xff, 19)
            XCTAssertTrue(message.contains(kind), message)
        }
    }

    func testMigrationCreatesMediaTableAndOnlyConstraintIndexes() throws {
        let database = try StorageFixture.database(self)
        try database.read { db in
            XCTAssertTrue(try db.tableExists("media_candidates"))
            XCTAssertEqual(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations WHERE identifier = 'canonical-media-candidates-v1'"), ["canonical-media-candidates-v1"])
            let indexes = try Row.fetchAll(db, sql: "PRAGMA index_list('media_candidates')")
            XCTAssertEqual(indexes.count, 3)
            XCTAssertEqual(Set(indexes.map { $0["origin"] as String }), ["pk", "u", "c"], "the third is the playback index")
            // T9: at most one playable payload per revision, and the index says so itself.
            let playback = try XCTUnwrap(indexes.first { ($0["name"] as String) == "media_candidates_one_playback" })
            XCTAssertEqual(playback["partial"] as Int, 1)
            XCTAssertEqual(try Row.fetchAll(db, sql: "PRAGMA index_info('media_candidates_one_playback')")
                .map { $0["name"] as String }, ["origin_revision_id"])
            let orderedIndex = try XCTUnwrap(indexes.first { ($0["origin"] as String) == "u" })
            let name: String = orderedIndex["name"]
            let fields = try Row.fetchAll(db, sql: "PRAGMA index_info('\(name)')").map { $0["name"] as String }
            XCTAssertEqual(fields, ["origin_revision_id", "ordinal"])
            let plan = try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN SELECT * FROM media_candidates WHERE origin_revision_id = ? ORDER BY ordinal ASC", arguments: ["revision"])
                .map { $0["detail"] as String }.joined(separator: "\n")
            XCTAssertTrue(plan.contains("SEARCH media_candidates USING INDEX \(name)"), plan)
            XCTAssertFalse(plan.contains("TEMP B-TREE"), plan)
            let foreignKeys = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list('media_candidates')")
            XCTAssertEqual(foreignKeys.count, 1)
            XCTAssertEqual(foreignKeys[0]["table"] as String, "origin_revisions")
            XCTAssertEqual(foreignKeys[0]["from"] as String, "origin_revision_id")
            XCTAssertEqual(foreignKeys[0]["to"] as String, "id")
            XCTAssertEqual(foreignKeys[0]["on_delete"] as String, "NO ACTION")
            XCTAssertEqual(foreignKeys[0]["on_update"] as String, "NO ACTION")
        }
    }

    /// T9: a revision can carry one playable payload beside its visual, the pairing rule holds, and at most one
    /// playable payload exists per revision (the partial index says so, not the caller's discipline).
    func testAPlayablePayloadLivesBesideTheVisualAndOnlyOnce() throws {
        let database = try StorageFixture.database(self), revision = try insertRevision(database)
        try insertCandidate(database, revision: revision, ordinal: 0)
        try insertCandidate(database, revision: revision, ordinal: 1, role: "playback", mediaClass: "audio")
        let store = ContentStore(database: database)
        let playable = try XCTUnwrap(try store.playbackCandidate(originRevisionID: OriginRevisionID(rawValue: try XCTUnwrap(UUID(uuidString: revision)))))
        XCTAssertEqual(playable.role, .playback)
        XCTAssertEqual(playable.mediaClass, .audio)
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: OriginRevisionID(rawValue: try XCTUnwrap(UUID(uuidString: revision))))?.count, 2,
            "the visual and the payload are both there, and the payload is not the visual")
        // A second playable payload for the same revision is refused by the index itself.
        constraint({ try insertCandidate(database, revision: revision, ordinal: 2, role: "playback", mediaClass: "video") },
            kind: "UNIQUE")
        // A class cannot claim a role it cannot serve.
        constraint({ try insertCandidate(database, revision: revision, ordinal: 3, role: "cardVisual", mediaClass: "audio") },
            kind: "CHECK")
        constraint({ try insertCandidate(database, revision: revision, ordinal: 4, role: "playback", mediaClass: "image") },
            kind: "CHECK")
        constraint({ try insertCandidate(database, revision: revision, ordinal: 5, role: "playback", mediaClass: "pdf") },
            kind: "CHECK")
    }

    func testRevisionForeignKeyOrdinalBaselineAndDimensionsAreEnforced() throws {
        let database = try StorageFixture.database(self), revision = try insertRevision(database)
        constraint({ try insertCandidate(database, revision: key()) }, kind: "FOREIGN KEY")
        constraint({ try insertCandidate(database, revision: revision, ordinal: -1) }, kind: "CHECK")
        for role in ["image", "cardvisual", "audio"] {
            constraint({ try insertCandidate(database, revision: revision, role: role) }, kind: "CHECK")
        }
        for mediaClass in ["Image", "audio", "video"] {
            constraint({ try insertCandidate(database, revision: revision, mediaClass: mediaClass) }, kind: "CHECK")
        }
        for (width, height) in [(1, nil), (nil, 1), (0, 1), (1, 0), (-1, 1), (1, -1)] as [(Int?, Int?)] {
            constraint({ try insertCandidate(database, revision: revision, width: width, height: height) }, kind: "CHECK")
        }
        try insertCandidate(database, revision: revision)
        constraint({ try insertCandidate(database, revision: revision) }, kind: "UNIQUE")
        try insertCandidate(database, revision: revision, ordinal: 1, width: 200, height: 100)
        constraint({ try database.write { try $0.execute(sql: "DELETE FROM origin_revisions WHERE id = ?", arguments: [revision]) } }, kind: "FOREIGN KEY")
        XCTAssertEqual(try database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM media_candidates") }, 2)
    }

    func testUpgradePreservesExistingDataAndPreMediaRevisionIsEmptyImmutableCollection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let location = RuntimeDatabaseLocation(directory: root)
        let origin = OriginRecordID(), revision = OriginRevisionID(), source = SourceID()
        let o = origin.rawValue.uuidString.lowercased(), r = revision.rawValue.uuidString.lowercased()
        let edition = key(), segment = key(), card = key()
        let tables = ["origin_records", "origin_revisions", "source_memberships", "selection_supply", "feed_editions", "feed_segments", "published_cards", "session_checkpoint"]
        let before: [[[DatabaseValue]]], schemaBefore: Set<String>
        do {
            let queue = try DatabaseQueue(path: location.databaseURL.path)
            try RuntimeMigrations.current.migrate(queue, upTo: "canonical-supply-v1")
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO origin_records (id, object_connector_kind, object_namespace, object_value,
                        object_role, availability, first_observed_at, last_observed_at)
                    VALUES (?, 'test', 'objects', 'old', 'object', 'available', 1, 1)
                    """, arguments: [o])
                try db.execute(sql: "INSERT INTO origin_revisions (id, origin_record_id, headline, observed_at) VALUES (?, ?, 'old text', 1)", arguments: [r, o])
                try db.execute(sql: "UPDATE origin_records SET current_revision_id = ?", arguments: [r])
                try db.execute(sql: "INSERT INTO source_memberships VALUES (?, ?, 'direct', 1, 1)", arguments: [o, source.rawValue.uuidString.lowercased()])
                try db.execute(sql: "INSERT INTO selection_supply VALUES (?, ?, 1, 'observedFallback')", arguments: [o, r])
                try db.execute(sql: """
                    INSERT INTO feed_editions (id, editorial_revision_id, context_kind, catalog_generation,
                        user_selection_version, eligibility_policy_version, scoring_policy_version,
                        sequencing_policy_version, exposure_policy_version, selection_schema_version,
                        publication_schema_version, selection_seed, created_at)
                    VALUES (?, ?, 'main', 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)
                    """, arguments: [edition, EditorialRevisionID().rawValue.uuidString.lowercased()])
                try db.execute(sql: "INSERT INTO feed_segments VALUES (?, ?, 0, 1, 1, 1)", arguments: [segment, edition])
                try db.execute(sql: """
                    INSERT INTO published_cards (id, segment_id, ordinal, origin_record_id, origin_revision_id,
                        title, render_layout) VALUES (?, ?, 0, ?, ?, 'Frozen', 'textOnly')
                    """, arguments: [card, segment, o, r])
                try db.execute(sql: "INSERT INTO session_checkpoint VALUES (1, ?, ?, 'top', 1)", arguments: [edition, card])
            }
            before = try queue.read { db in
                try tables.map { table in try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY 1").map { $0.map { $0.1 } } }
            }
            schemaBefore = try queue.read { db in Set(try String.fetchAll(db, sql: "SELECT type || ':' || name FROM sqlite_schema")) }
        }
        let database = try RuntimeDatabase(location: location), store = ContentStore(database: database)
        let after = try database.read { db in
            // Additive columns are compared explicitly below, not through the whole-row dump: T6 added the
            // context identity to feed_editions and the availability column predates it.
            try tables.map { table in try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY 1").map { row in
                row.filter { column in
                    if table == "origin_records" { return column.0 != "availability_observed_at" }
                    if table == "feed_editions" { return column.0 != "context_identity" && column.0 != "context_key_json" }
                    return true
                }.map { $0.1 }
            } }
        }
        XCTAssertEqual(after, before) // Every preexisting value remains exact; the additive column is checked separately.
        XCTAssertEqual(try database.read { try Double.fetchOne($0,sql: "SELECT availability_observed_at FROM origin_records") },1)
        // T6: the pre-existing Edition acquires the default-surface identity of the context it recorded.
        XCTAssertEqual(try database.read { try String.fetchOne($0, sql: "SELECT context_identity FROM feed_editions") },
            ContextKey(request: .main).canonicalIdentity)
        let schemaAfter = try database.read { db in Set(try String.fetchAll(db, sql: "SELECT type || ':' || name FROM sqlite_schema")) }
        XCTAssertTrue(Set(["table:media_candidates", "index:sqlite_autoindex_media_candidates_1", "index:sqlite_autoindex_media_candidates_2"]).isSubset(of: schemaAfter.subtracting(schemaBefore)))
        XCTAssertTrue(schemaBefore.isSubset(of: schemaAfter))
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: revision), [])
        let oldRevision = try XCTUnwrap(store.originRevision(id: revision))
        let object = try XCTUnwrap(store.originRecord(id: origin)).externalObjectIdentity
        let candidate = try XCTUnwrap(MediaCandidate(id: MediaCandidateID(), originRevisionID: revision,
            role: .cardVisual, mediaClass: .image, remoteURL: URL(string: "https://example.test/image")!,
            declaredMimeType: nil, declaredPixelWidth: nil, declaredPixelHeight: nil))
        for media in [[], [candidate]] {
            let change = ContentStore.CanonicalChange(recordID: origin, externalObjectIdentity: object,
                revision: oldRevision, mediaCandidates: media, availability: .available,
                observedAt: Date(timeIntervalSince1970: 1), expectedCurrent: .revision(revision),
                currentUpdate: .useSuppliedRevision, membershipMutations: [])
            if media.isEmpty { try store.commitCanonicalChange(change) }
            else {
                XCTAssertThrowsError(try store.commitCanonicalChange(change)) {
                    XCTAssertEqual($0 as? ContentStoreError, .mediaCandidateCollectionConflict(revision))
                }
            }
        }
        XCTAssertEqual(try store.mediaCandidates(originRevisionID: revision), [])
    }
}
