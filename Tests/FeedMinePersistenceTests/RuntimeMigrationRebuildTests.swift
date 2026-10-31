//
// File: RuntimeMigrationRebuildTests.swift
// Module: FeedMinePersistenceTests
//
// Responsibility:
//   Kiro K-07 (re-check of review finding A03): the two table rebuilds in RuntimeMigrations —
//   `reader-context-identity-v1` (context_checkpoints) and `media-playback-candidate-v1` (media_candidates) —
//   run on a populated database without losing or altering a row, keep foreign keys and indexes, and leave
//   foreign_key_check / integrity_check clean.
//
// Finding status: A03 claimed the rebuilds ran with foreign keys enabled. GRDB 7 registers migrations with
//   `foreignKeyChecks: .deferred` by default (foreign keys off during the migration, checked before commit),
//   and both rebuilt tables are leaf children (nothing references them). A03 is not a defect; this test keeps
//   the data-preservation guarantee executable so a future rebuild cannot regress it silently.
//
// Allowed dependencies:
//   FeedMinePersistence, FeedMineDomain, Foundation, XCTest and GRDB for SQLite-specific checks.
//

import Foundation
import XCTest
import GRDB
import FeedMineDomain
@testable import FeedMinePersistence

final class RuntimeMigrationRebuildTests: XCTestCase {
    private func key() -> String { UUID().uuidString.lowercased() }

    func testTableRebuildsPreserveCheckpointsMediaAndBookmarksOnPopulatedDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let location = RuntimeDatabaseLocation(directory: root)

        let o1 = key(), o2 = key(), r1 = key(), r2 = key()
        let sourceUUID = UUID(), source = sourceUUID.uuidString.lowercased()
        let mainEdition = key(), sourceEdition = key()
        let mainCards = [key(), key()], sourceCards = [key(), key()]
        let mediaSelect = "SELECT * FROM media_candidates ORDER BY id"
        let checkpointSelect = """
            SELECT context_key, edition_id, card_id, anchor_placement, updated_at FROM context_checkpoints ORDER BY context_key
            """
        let mediaBefore: [[DatabaseValue]], checkpointsBefore: [[DatabaseValue]], cardsBefore: [[DatabaseValue]]
        do {
            let queue = try DatabaseQueue(path: location.databaseURL.path)
            // Stop right before the first rebuild, then write the kind of rows a real reader already has.
            try RuntimeMigrations.current.migrate(queue, upTo: "publication-media-use-v1")
            try queue.write { db in
                for (origin, revision) in [(o1, r1), (o2, r2)] {
                    try db.execute(sql: """
                        INSERT INTO origin_records (id, object_connector_kind, object_namespace, object_value,
                            object_role, availability, first_observed_at, last_observed_at)
                        VALUES (?, 'syndication', 'objects', ?, 'object', 'available', 1, 2)
                        """, arguments: [origin, origin])
                    try db.execute(sql: "INSERT INTO origin_revisions (id, origin_record_id, headline, observed_at) VALUES (?, ?, 'h', 1)",
                        arguments: [revision, origin])
                    try db.execute(sql: "UPDATE origin_records SET current_revision_id = ? WHERE id = ?", arguments: [revision, origin])
                    try db.execute(sql: "INSERT INTO source_memberships VALUES (?, ?, 'direct', 1, 1)", arguments: [origin, source])
                    try db.execute(sql: "INSERT INTO selection_supply VALUES (?, ?, 1, 'observedFallback')", arguments: [origin, revision])
                }
                // Card visuals with and without declared dimensions, across two revisions.
                try db.execute(sql: """
                    INSERT INTO media_candidates VALUES
                        (?, ?, 0, 'cardVisual', 'image', 'https://img.example/a.jpg', 'image/jpeg', 1200, 800),
                        (?, ?, 1, 'cardVisual', 'image', 'https://img.example/b.jpg', NULL, NULL, NULL),
                        (?, ?, 0, 'cardVisual', 'image', 'https://img.example/c.png', 'image/png', 640, 640)
                    """, arguments: [key(), r1, key(), r1, key(), r2])
                for (edition, kind, contextSource) in [(mainEdition, "main", nil), (sourceEdition, "source", source)] as [(String, String, String?)] {
                    try db.execute(sql: """
                        INSERT INTO feed_editions (id, editorial_revision_id, context_kind, context_source_id,
                            catalog_generation, user_selection_version, eligibility_policy_version, scoring_policy_version,
                            sequencing_policy_version, exposure_policy_version, selection_schema_version,
                            publication_schema_version, selection_seed, created_at)
                        VALUES (?, ?, ?, ?, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)
                        """, arguments: [edition, key(), kind, contextSource])
                }
                for (edition, cards) in [(mainEdition, mainCards), (sourceEdition, sourceCards)] {
                    let segment = key()
                    try db.execute(sql: "INSERT INTO feed_segments VALUES (?, ?, 0, 1, 1, 1)", arguments: [segment, edition])
                    for (ordinal, (card, origin, revision)) in [(cards[0], o1, r1), (cards[1], o2, r2)].enumerated() {
                        try db.execute(sql: """
                            INSERT INTO published_cards (id, segment_id, ordinal, origin_record_id, origin_revision_id,
                                title, media_key, media_pixel_width, media_pixel_height, render_layout, render_media_aspect_ratio)
                            VALUES (?, ?, ?, ?, ?, 'Frozen', 'k', 1200, 800, 'hero', 1.5)
                            """, arguments: [card, segment, ordinal, origin, revision])
                    }
                }
                // The reader's position in two contexts (B05: reopen and return must find them again).
                try db.execute(sql: "INSERT INTO context_checkpoints VALUES ('main', ?, ?, 'top', 10)",
                    arguments: [mainEdition, mainCards[1]])
                try db.execute(sql: "INSERT INTO context_checkpoints VALUES (?, ?, ?, 'center', 11)",
                    arguments: ["source:" + source, sourceEdition, sourceCards[0]])
                try db.execute(sql: "INSERT INTO edition_reading_state VALUES (?, ?, 1, 1)", arguments: [mainEdition, mainCards[1]])
                try db.execute(sql: "INSERT INTO publication_bookmarks VALUES (?, 12)", arguments: [mainCards[0]])
            }
            let rows: @Sendable (Database, String) throws -> [[DatabaseValue]] = { db, sql in
                try Row.fetchAll(db, sql: sql).map { $0.map { $0.1 } }
            }
            mediaBefore = try queue.read { try rows($0, mediaSelect) }
            checkpointsBefore = try queue.read { try rows($0, checkpointSelect) }
            cardsBefore = try queue.read { try rows($0, "SELECT id, segment_id, ordinal, origin_record_id, origin_revision_id, source_id, provider_id, source_display_name, provider_display_name, content_entity_id, content_cluster_id, title, primary_text, timestamp_value, timestamp_kind, media_key, media_pixel_width, media_pixel_height, media_mime_type, render_layout, render_media_aspect_ratio, primary_action_kind, primary_action_reference FROM published_cards ORDER BY id") }
            XCTAssertEqual(mediaBefore.count, 3)
            XCTAssertEqual(checkpointsBefore.count, 2)
        }

        // Production path: RuntimeDatabase applies every remaining migration, including both rebuilds.
        let database = try RuntimeDatabase(location: location)
        let defaultBox = ReaderBookmarkList.defaultID
        let after = try database.read { db -> [String: [[DatabaseValue]]] in
            let rows: (String) throws -> [[DatabaseValue]] = { sql in try Row.fetchAll(db, sql: sql).map { $0.map { $0.1 } } }
            return [
                "media": try rows(mediaSelect),
                "checkpoints": try rows(checkpointSelect),
                "cards": try rows("SELECT id, segment_id, ordinal, origin_record_id, origin_revision_id, source_id, provider_id, source_display_name, provider_display_name, content_entity_id, content_cluster_id, title, primary_text, timestamp_value, timestamp_kind, media_key, media_pixel_width, media_pixel_height, media_mime_type, render_layout, render_media_aspect_ratio, primary_action_kind, primary_action_reference FROM published_cards ORDER BY id"),
                "bookmarks": try rows("SELECT card_id, added_at FROM reader_bookmark_memberships WHERE list_id = '\(defaultBox)'"),
                "fk": try rows("PRAGMA foreign_key_check"),
            ]
        }
        XCTAssertEqual(after["media"], mediaBefore, "media_candidates rebuild must keep every row exactly")
        XCTAssertEqual(after["checkpoints"], checkpointsBefore, "context_checkpoints rebuild must keep every reader position")
        XCTAssertEqual(after["cards"], cardsBefore)
        XCTAssertEqual(after["bookmarks"], [[mainCards[0].databaseValue, 12.0.databaseValue]])
        XCTAssertEqual(after["fk"], [])

        try database.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
            // Each checkpoint is now filed under its Edition's full context identity.
            let identities = try Row.fetchAll(db, sql: "SELECT context_key, context_identity, context_key_json FROM context_checkpoints")
            XCTAssertEqual(identities.count, 2)
            for row in identities {
                let identity: String = row["context_identity"], json: String = row["context_key_json"]
                XCTAssertFalse(identity.isEmpty); XCTAssertFalse(json.isEmpty)
            }
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT context_identity FROM context_checkpoints WHERE context_key = 'main'"),
                ContextKey(request: .main).canonicalIdentity)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT context_identity FROM context_checkpoints WHERE context_key = ?",
                arguments: ["source:" + source]), ContextKey(request: .source(SourceID(rawValue: sourceUUID))).canonicalIdentity)
            // The additive cursor fence migration must retain both legacy
            // contexts' published positions, without rewriting older seen rows.
            XCTAssertEqual(try String.fetchOne(db, sql:
                "SELECT protected_card_id FROM edition_position_protection WHERE edition_id = ?",
                arguments: [mainEdition]), mainCards[1])
            XCTAssertEqual(try String.fetchOne(db, sql:
                "SELECT protected_card_id FROM edition_position_protection WHERE edition_id = ?",
                arguments: [sourceEdition]), sourceCards[0])
            XCTAssertEqual(try String.fetchOne(db, sql:
                "SELECT high_water_card_id FROM edition_reading_state WHERE edition_id = ?",
                arguments: [mainEdition]), mainCards[1])
            // Rebuilt tables keep their constraints, references and the new playback index.
            let indexes = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_schema WHERE type = 'index' AND tbl_name = 'media_candidates'"))
            XCTAssertTrue(indexes.contains("media_candidates_one_playback"))
            XCTAssertEqual(Set(try String.fetchAll(db, sql: "SELECT \"table\" FROM pragma_foreign_key_list('media_candidates')")),
                ["origin_revisions"])
            XCTAssertEqual(Set(try String.fetchAll(db, sql: "SELECT \"table\" FROM pragma_foreign_key_list('context_checkpoints')")),
                ["feed_editions", "published_cards"])
        }
    }
}
