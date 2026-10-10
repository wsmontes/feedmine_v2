//
// File: RuntimeMigrations.swift
// Module: FeedMinePersistence
//
// Responsibility:
//   Own sequential schema migration authority for the runtime database.
//
// Owns:
//   GRDB migration registration/bookkeeping and explicit non-erasing configuration.
//
// Does not own:
//   Domain CRUD, duplicate schema counters, recovery, database lifecycle or catalog.
//
// Allowed dependencies:
//   GRDB and FeedMineDomain; migrator details are internal to Persistence.
//
// Architectural invariants:
//   INV-12; one migration authority. Schema changes never erase runtime semantic state.
//
// Planned public surface:
//   RuntimeMigrations ownership namespace; its GRDB current migrator remains internal.
//
// Status:
//   Foundation, publication, canonical supply and canonical-media-candidates-v1 schema authority.
//

import Foundation
import GRDB
import FeedMineDomain

public enum RuntimeMigrations {
    static var current: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false
        migrator.registerMigration("runtime-foundation-v1") { _ in
            // Establish authority and bookkeeping without creating domain tables.
        }
        migrator.registerMigration("publication-restore-v1") { db in
            try db.execute(sql: """
                CREATE TABLE feed_editions (
                    id TEXT PRIMARY KEY NOT NULL,
                    editorial_revision_id TEXT NOT NULL,
                    context_kind TEXT NOT NULL,
                    context_source_id TEXT,
                    context_search_query TEXT,
                    catalog_generation INTEGER NOT NULL,
                    user_selection_version INTEGER NOT NULL,
                    eligibility_policy_version INTEGER NOT NULL,
                    scoring_policy_version INTEGER NOT NULL,
                    sequencing_policy_version INTEGER NOT NULL,
                    exposure_policy_version INTEGER NOT NULL,
                    selection_schema_version INTEGER NOT NULL,
                    publication_schema_version INTEGER NOT NULL,
                    selection_seed INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    CHECK (
                        (context_kind = 'main'
                            AND context_source_id IS NULL AND context_search_query IS NULL)
                        OR (context_kind = 'source'
                            AND context_source_id IS NOT NULL AND context_search_query IS NULL)
                        OR (context_kind = 'search'
                            AND context_source_id IS NULL AND context_search_query IS NOT NULL)
                    ),
                    CHECK (catalog_generation >= 0),
                    CHECK (user_selection_version >= 0),
                    CHECK (eligibility_policy_version >= 0),
                    CHECK (scoring_policy_version >= 0),
                    CHECK (sequencing_policy_version >= 0),
                    CHECK (exposure_policy_version >= 0),
                    CHECK (selection_schema_version >= 0),
                    CHECK (publication_schema_version >= 0)
                );

                CREATE TABLE feed_segments (
                    id TEXT PRIMARY KEY NOT NULL,
                    edition_id TEXT NOT NULL,
                    ordinal INTEGER NOT NULL,
                    segment_seed INTEGER NOT NULL,
                    publication_schema_version INTEGER NOT NULL,
                    created_at REAL NOT NULL,
                    FOREIGN KEY (edition_id) REFERENCES feed_editions(id) ON DELETE RESTRICT,
                    UNIQUE (edition_id, ordinal),
                    CHECK (ordinal >= 0),
                    CHECK (publication_schema_version >= 0)
                );

                CREATE TABLE published_cards (
                    id TEXT PRIMARY KEY NOT NULL,
                    segment_id TEXT NOT NULL,
                    ordinal INTEGER NOT NULL,
                    origin_record_id TEXT NOT NULL,
                    origin_revision_id TEXT NOT NULL,
                    source_id TEXT,
                    provider_id TEXT,
                    source_display_name TEXT,
                    provider_display_name TEXT,
                    content_entity_id TEXT,
                    content_cluster_id TEXT,
                    title TEXT,
                    primary_text TEXT,
                    timestamp_value REAL,
                    timestamp_kind TEXT,
                    media_key TEXT,
                    media_pixel_width INTEGER,
                    media_pixel_height INTEGER,
                    media_mime_type TEXT,
                    render_layout TEXT NOT NULL,
                    render_media_aspect_ratio REAL,
                    primary_action_kind TEXT,
                    primary_action_reference TEXT,
                    FOREIGN KEY (segment_id) REFERENCES feed_segments(id) ON DELETE RESTRICT,
                    UNIQUE (segment_id, ordinal),
                    CHECK (ordinal >= 0),
                    CHECK (
                        (timestamp_value IS NULL AND timestamp_kind IS NULL)
                        OR (timestamp_value IS NOT NULL AND timestamp_kind IS NOT NULL
                            AND timestamp_kind IN ('authored', 'modified', 'observed'))
                    ),
                    CHECK (
                        (media_key IS NULL AND media_pixel_width IS NULL
                            AND media_pixel_height IS NULL AND media_mime_type IS NULL)
                        OR (media_key IS NOT NULL AND media_key != ''
                            AND (
                                (media_pixel_width IS NULL AND media_pixel_height IS NULL)
                                OR (media_pixel_width IS NOT NULL AND media_pixel_height IS NOT NULL
                                    AND media_pixel_width > 0 AND media_pixel_height > 0)
                            ))
                    ),
                    CHECK (render_layout IN ('hero', 'thumbnail', 'textOnly')),
                    CHECK (render_media_aspect_ratio IS NULL OR render_media_aspect_ratio > 0),
                    CHECK (render_layout != 'textOnly'
                        OR (media_key IS NULL AND render_media_aspect_ratio IS NULL)),
                    CHECK (
                        (primary_action_kind IS NULL AND primary_action_reference IS NULL)
                        OR (primary_action_kind IS NOT NULL
                            AND primary_action_kind = 'localContentDetail'
                            AND primary_action_reference IS NULL)
                        OR (primary_action_kind IS NOT NULL
                            AND primary_action_kind IN ('externalURL', 'mediaPlayback')
                            AND primary_action_reference IS NOT NULL)
                    )
                );

                CREATE TABLE session_checkpoint (
                    singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
                    edition_id TEXT NOT NULL,
                    card_id TEXT NOT NULL,
                    anchor_placement TEXT NOT NULL,
                    updated_at REAL NOT NULL,
                    FOREIGN KEY (edition_id) REFERENCES feed_editions(id) ON DELETE RESTRICT,
                    FOREIGN KEY (card_id) REFERENCES published_cards(id) ON DELETE RESTRICT,
                    CHECK (anchor_placement IN ('top', 'center'))
                );
                """)
        }
        migrator.registerMigration("canonical-supply-v1") { db in
            try db.execute(sql: """
                CREATE TABLE origin_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    object_connector_kind TEXT COLLATE BINARY NOT NULL,
                    object_namespace TEXT COLLATE BINARY NOT NULL,
                    object_value TEXT COLLATE BINARY NOT NULL,
                    object_role TEXT COLLATE BINARY NOT NULL CHECK (object_role = 'object'),
                    current_revision_id TEXT,
                    availability TEXT NOT NULL CHECK (availability IN ('available', 'updated', 'removed', 'revoked', 'unknown')),
                    first_observed_at REAL NOT NULL,
                    last_observed_at REAL NOT NULL,
                    UNIQUE (object_connector_kind, object_namespace, object_value, object_role),
                    FOREIGN KEY (id, current_revision_id) REFERENCES origin_revisions(origin_record_id, id)
                        ON UPDATE NO ACTION ON DELETE NO ACTION
                );

                CREATE TABLE origin_revisions (
                    id TEXT PRIMARY KEY NOT NULL,
                    origin_record_id TEXT NOT NULL,
                    version_connector_kind TEXT COLLATE BINARY,
                    version_namespace TEXT COLLATE BINARY,
                    version_value TEXT COLLATE BINARY,
                    version_role TEXT COLLATE BINARY,
                    headline TEXT,
                    summary TEXT,
                    body_text TEXT,
                    authored_at REAL,
                    modified_at REAL,
                    observed_at REAL NOT NULL,
                    language TEXT,
                    primary_link TEXT,
                    search_projection TEXT,
                    provider_id TEXT,
                    FOREIGN KEY (origin_record_id) REFERENCES origin_records(id)
                        ON UPDATE NO ACTION ON DELETE NO ACTION,
                    UNIQUE (origin_record_id, id),
                    CHECK (
                        (version_connector_kind IS NULL AND version_namespace IS NULL
                            AND version_value IS NULL AND version_role IS NULL)
                        OR (version_connector_kind IS NOT NULL AND version_namespace IS NOT NULL
                            AND version_value IS NOT NULL AND version_role IS NOT NULL
                            AND version_role = 'version')
                    )
                );

                CREATE UNIQUE INDEX origin_revisions_version_identity
                    ON origin_revisions (origin_record_id, version_connector_kind, version_namespace, version_value, version_role)
                    WHERE version_connector_kind IS NOT NULL;

                CREATE TABLE source_memberships (
                    origin_record_id TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    membership_kind TEXT NOT NULL CHECK (membership_kind IN ('direct', 'derived')),
                    first_observed_at REAL NOT NULL,
                    last_observed_at REAL NOT NULL,
                    PRIMARY KEY (origin_record_id, source_id),
                    FOREIGN KEY (origin_record_id) REFERENCES origin_records(id)
                        ON UPDATE NO ACTION ON DELETE NO ACTION
                );

                CREATE TABLE selection_supply (
                    origin_record_id TEXT PRIMARY KEY NOT NULL,
                    origin_revision_id TEXT NOT NULL,
                    sort_date REAL NOT NULL,
                    sort_date_basis TEXT NOT NULL CHECK (sort_date_basis IN ('authored', 'observedFallback')),
                    FOREIGN KEY (origin_record_id, origin_revision_id) REFERENCES origin_revisions(origin_record_id, id)
                        ON UPDATE NO ACTION ON DELETE NO ACTION
                );

                CREATE INDEX selection_supply_order ON selection_supply (sort_date DESC, origin_record_id DESC);
                """)
        }
        migrator.registerMigration("canonical-media-candidates-v1") { db in
            try db.execute(sql: """
                CREATE TABLE media_candidates (
                    id TEXT PRIMARY KEY NOT NULL,
                    origin_revision_id TEXT NOT NULL,
                    ordinal INTEGER NOT NULL,
                    role TEXT COLLATE BINARY NOT NULL,
                    media_class TEXT COLLATE BINARY NOT NULL,
                    remote_locator TEXT COLLATE BINARY NOT NULL,
                    declared_mime_type TEXT COLLATE BINARY,
                    declared_pixel_width INTEGER,
                    declared_pixel_height INTEGER,
                    FOREIGN KEY (origin_revision_id) REFERENCES origin_revisions(id)
                        ON UPDATE NO ACTION ON DELETE NO ACTION,
                    UNIQUE (origin_revision_id, ordinal),
                    CHECK (ordinal >= 0),
                    CHECK (role = 'cardVisual'),
                    CHECK (media_class = 'image'),
                    CHECK (
                        (declared_pixel_width IS NULL AND declared_pixel_height IS NULL)
                        OR (declared_pixel_width IS NOT NULL AND declared_pixel_height IS NOT NULL
                            AND declared_pixel_width > 0 AND declared_pixel_height > 0)
                    )
                );
                """)
        }
        migrator.registerMigration("publication-exposure-index-v1") { db in
            try db.execute(sql: """
                CREATE INDEX published_cards_origin_revision_segment
                ON published_cards (origin_revision_id, segment_id);
                """)
        }
        migrator.registerMigration("acquisition-target-authority-v1") { db in
            try db.execute(sql: """
                CREATE TABLE acquisition_targets (
                    id TEXT PRIMARY KEY NOT NULL,
                    connector_kind TEXT COLLATE BINARY NOT NULL,
                    generation INTEGER NOT NULL,
                    state TEXT COLLATE BINARY NOT NULL,
                    checkpoint_revision INTEGER NOT NULL,
                    checkpoint_blob BLOB,
                    checkpoint_schema INTEGER,
                    checkpoint_connector_version TEXT COLLATE BINARY,
                    CHECK (length(connector_kind) > 0),
                    CHECK (generation >= 1),
                    CHECK (state IN ('enabled', 'revoked')),
                    CHECK (checkpoint_revision >= 0),
                    CHECK (
                        (checkpoint_blob IS NULL AND checkpoint_schema IS NULL
                            AND checkpoint_connector_version IS NULL)
                        OR
                        (checkpoint_blob IS NOT NULL AND checkpoint_schema IS NOT NULL
                            AND checkpoint_schema > 0 AND checkpoint_connector_version IS NOT NULL
                            AND length(checkpoint_connector_version) > 0 AND checkpoint_revision > 0)
                    )
                );
                """)
        }
        migrator.registerMigration("publication-origin-exposure-index-v1") { db in
            try db.execute(sql: """
                CREATE INDEX published_cards_origin_record_segment
                ON published_cards (origin_record_id, segment_id);
                """)
        }
        migrator.registerMigration("origin-availability-precedence-v1") { db in
            try db.execute(sql: """
                ALTER TABLE origin_records
                ADD COLUMN availability_observed_at REAL;
                UPDATE origin_records
                SET availability_observed_at = last_observed_at;
                """)
        }
        migrator.registerMigration("acquisition-target-sources-v1") { db in
            try db.execute(sql: """
                CREATE TABLE acquisition_target_sources (
                    target_id TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    generation INTEGER NOT NULL,
                    PRIMARY KEY (target_id, source_id),
                    FOREIGN KEY (target_id)
                        REFERENCES acquisition_targets(id)
                        ON DELETE CASCADE,
                    CHECK (generation >= 1)
                );
                """)
        }
        migrator.registerMigration("reader-contexts-v1") { db in
            try db.execute(sql: """
                CREATE TABLE reader_preferences (
                    singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
                    source_keys BLOB NOT NULL, selection_version INTEGER NOT NULL CHECK(selection_version >= 2),
                    active_context BLOB NOT NULL);
                CREATE TABLE context_checkpoints (
                    context_key TEXT PRIMARY KEY NOT NULL,
                    edition_id TEXT NOT NULL REFERENCES feed_editions(id),
                    card_id TEXT NOT NULL REFERENCES published_cards(id),
                    anchor_placement TEXT NOT NULL CHECK(anchor_placement IN ('top', 'center')),
                    updated_at REAL NOT NULL);
                INSERT INTO context_checkpoints SELECT
                    CASE e.context_kind WHEN 'main' THEN 'main'
                        WHEN 'source' THEN 'source:' || e.context_source_id
                        WHEN 'search' THEN 'search:' || e.context_search_query END,
                    c.edition_id, c.card_id, c.anchor_placement, c.updated_at
                    FROM session_checkpoint c JOIN feed_editions e ON e.id = c.edition_id;
                """)
        }
        migrator.registerMigration("publication-reading-state-v1") { db in
            try db.execute(sql: """
                CREATE TABLE edition_reading_state (
                    edition_id TEXT PRIMARY KEY REFERENCES feed_editions(id),
                    high_water_card_id TEXT NOT NULL REFERENCES published_cards(id),
                    visible INTEGER NOT NULL CHECK(visible IN (0,1)),
                    generation INTEGER NOT NULL CHECK(generation >= 1));
                INSERT INTO edition_reading_state SELECT edition_id, card_id, 1, 1 FROM context_checkpoints;
                CREATE TABLE retired_published_cards AS SELECT * FROM published_cards WHERE 0;
                CREATE UNIQUE INDEX retired_published_cards_id ON retired_published_cards(id);
                CREATE TABLE retired_feed_segments AS SELECT * FROM feed_segments WHERE 0;
                CREATE UNIQUE INDEX retired_feed_segments_id ON retired_feed_segments(id);
                """)
        }
        migrator.registerMigration("publication-media-use-v1") { db in
            try db.execute(sql: """
                CREATE TABLE publication_card_usage (card_id TEXT PRIMARY KEY REFERENCES published_cards(id), last_seen_at REAL NOT NULL);
                CREATE TABLE publication_bookmarks (card_id TEXT PRIMARY KEY REFERENCES published_cards(id), bookmarked_at REAL NOT NULL);
                INSERT INTO publication_card_usage SELECT card_id, updated_at FROM context_checkpoints;
                """)
        }
        migrator.registerMigration("reader-context-identity-v1") { db in
            // T6 step 1–3 (docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md §6):
            // an Edition states the whole context identity it belongs to, the durable form is reversible,
            // and a checkpoint is keyed by that identity instead of the reduced surface text.
            try db.execute(sql: """
                ALTER TABLE feed_editions ADD COLUMN context_identity TEXT NOT NULL DEFAULT '';
                ALTER TABLE feed_editions ADD COLUMN context_key_json TEXT NOT NULL DEFAULT '';
                """)
            try Self.backfillEditionContextIdentities(db)
            // The reduced `context_key` was the primary key, which cannot hold two filtered contexts of the
            // same surface; the identity becomes the key and the reduced text is kept for one release.
            try db.execute(sql: """
                CREATE TABLE context_checkpoints_v2 (
                    context_identity TEXT PRIMARY KEY NOT NULL,
                    context_key TEXT NOT NULL,
                    context_key_json TEXT NOT NULL,
                    edition_id TEXT NOT NULL REFERENCES feed_editions(id),
                    card_id TEXT NOT NULL REFERENCES published_cards(id),
                    anchor_placement TEXT NOT NULL CHECK(anchor_placement IN ('top', 'center')),
                    updated_at REAL NOT NULL);
                INSERT INTO context_checkpoints_v2 SELECT
                    (SELECT e.context_identity FROM feed_editions e WHERE e.id = c.edition_id),
                    c.context_key,
                    (SELECT e.context_key_json FROM feed_editions e WHERE e.id = c.edition_id),
                    c.edition_id, c.card_id, c.anchor_placement, c.updated_at
                    FROM context_checkpoints c
                    WHERE (SELECT e.context_identity FROM feed_editions e WHERE e.id = c.edition_id) IS NOT NULL
                        AND (SELECT e.context_identity FROM feed_editions e WHERE e.id = c.edition_id) <> '';
                DROP TABLE context_checkpoints;
                ALTER TABLE context_checkpoints_v2 RENAME TO context_checkpoints;
                """)
            try Self.backfillCheckpointContextIdentities(db)
        }
        migrator.registerMigration("reader-filter-expiry-v1") { db in
            // T6: the overlay selection's expiry lives with the reader's preferences — never in the context
            // identity (a deadline is not identity) and never applied by a clock.
            try db.execute(sql: """
                ALTER TABLE reader_preferences ADD COLUMN filter_auto_expire INTEGER NOT NULL DEFAULT 1;
                ALTER TABLE reader_preferences ADD COLUMN filter_set_at REAL;
                """)
        }
        migrator.registerMigration("reader-library-v1") { db in
            // T8: the reader's own library. V1 had named bookmark boxes, source collections and saved presets;
            // V2 had one implicit bookmarked set (`publication_bookmarks`), which is folded into the default
            // box here so nothing the reader saved is lost. Membership stays per published *occurrence*: a
            // bookmark marks a card, and a card id is never replaced by a catalog integer.
            try db.execute(sql: """
                CREATE TABLE reader_bookmark_lists (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT COLLATE BINARY NOT NULL,
                    position INTEGER NOT NULL
                );
                CREATE TABLE reader_bookmark_memberships (
                    list_id TEXT NOT NULL REFERENCES reader_bookmark_lists(id) ON DELETE CASCADE,
                    card_id TEXT NOT NULL REFERENCES published_cards(id),
                    added_at REAL NOT NULL,
                    PRIMARY KEY (list_id, card_id)
                );
                CREATE INDEX reader_bookmark_memberships_by_card ON reader_bookmark_memberships(card_id);
                CREATE TABLE reader_collections (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT COLLATE BINARY NOT NULL,
                    position INTEGER NOT NULL
                );
                CREATE TABLE reader_collection_memberships (
                    collection_id TEXT NOT NULL REFERENCES reader_collections(id) ON DELETE CASCADE,
                    source_key TEXT COLLATE BINARY NOT NULL,
                    added_at REAL NOT NULL,
                    PRIMARY KEY (collection_id, source_key)
                );
                CREATE TABLE reader_presets (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT COLLATE BINARY NOT NULL,
                    kind TEXT COLLATE BINARY NOT NULL CHECK (kind IN ('smartBookmark', 'curatedFeed')),
                    position INTEGER NOT NULL,
                    context_key BLOB NOT NULL
                );
                """)
            // V1's own default box, so the control on a card has somewhere to put a bookmark from the first tap.
            try db.execute(sql: "INSERT INTO reader_bookmark_lists (id, name, position) VALUES (?, ?, 0)",
                arguments: [ReaderBookmarkList.defaultID, ReaderBookmarkList.defaultList().name])
            try db.execute(sql: """
                INSERT INTO reader_bookmark_memberships (list_id, card_id, added_at)
                SELECT ?, card_id, bookmarked_at FROM publication_bookmarks
                """, arguments: [ReaderBookmarkList.defaultID])
            try db.execute(sql: "DROP TABLE publication_bookmarks")
        }
        migrator.registerMigration("reader-preferred-box-v1") { db in
            // V1 kept the box a new bookmark lands in beside the reader's other preferences, and it is a
            // *preference*, not identity: changing it must never move the reader to another surface.
            try db.execute(sql: "ALTER TABLE reader_preferences ADD COLUMN preferred_bookmark_list TEXT")
        }
        migrator.registerMigration("media-playback-candidate-v1") { db in
            // T9: a card can carry a *playable* payload as well as its visual (V1's enclosure for an audio or
            // video episode). The table's own vocabulary said "card visual / image" only, and SQLite cannot
            // relax a CHECK in place, so the table is rebuilt with the full vocabulary and a pairing rule: an
            // image is the card's visual, a playable class is its playback, and a row cannot claim a role its
            // class cannot serve. At most one playback per revision — a card has one primary action.
            try db.execute(sql: """
                CREATE TABLE media_candidates_v2 (
                    id TEXT PRIMARY KEY NOT NULL,
                    origin_revision_id TEXT NOT NULL,
                    ordinal INTEGER NOT NULL,
                    role TEXT COLLATE BINARY NOT NULL,
                    media_class TEXT COLLATE BINARY NOT NULL,
                    remote_locator TEXT COLLATE BINARY NOT NULL,
                    declared_mime_type TEXT COLLATE BINARY,
                    declared_pixel_width INTEGER,
                    declared_pixel_height INTEGER,
                    FOREIGN KEY (origin_revision_id) REFERENCES origin_revisions(id)
                        ON UPDATE NO ACTION ON DELETE NO ACTION,
                    UNIQUE (origin_revision_id, ordinal),
                    CHECK (ordinal >= 0),
                    CHECK (role IN ('cardVisual', 'playback')),
                    CHECK (media_class IN ('image', 'audio', 'video')),
                    CHECK ((media_class = 'image' AND role = 'cardVisual')
                        OR (media_class <> 'image' AND role = 'playback')),
                    CHECK (
                        (declared_pixel_width IS NULL AND declared_pixel_height IS NULL)
                        OR (declared_pixel_width IS NOT NULL AND declared_pixel_height IS NOT NULL
                            AND declared_pixel_width > 0 AND declared_pixel_height > 0)
                    )
                );
                INSERT INTO media_candidates_v2 SELECT * FROM media_candidates;
                DROP TABLE media_candidates;
                ALTER TABLE media_candidates_v2 RENAME TO media_candidates;
                CREATE UNIQUE INDEX media_candidates_one_playback
                    ON media_candidates(origin_revision_id) WHERE role = 'playback';
                """)
        }
        return migrator
    }

    /// Files every checkpoint under its Edition's identity. Idempotent, and separate from the migration so
    /// the backfill is testable and re-runnable.
    static func backfillCheckpointContextIdentities(_ db: Database) throws {
        try db.execute(sql: """
            UPDATE context_checkpoints SET
                context_identity = COALESCE((SELECT e.context_identity FROM feed_editions e
                    WHERE e.id = context_checkpoints.edition_id), ''),
                context_key_json = COALESCE((SELECT e.context_key_json FROM feed_editions e
                    WHERE e.id = context_checkpoints.edition_id), '')
            WHERE context_identity = '' OR context_key_json = ''
            """)
    }

    /// Gives every Edition written before T6 the *default-surface* identity of the surface it recorded.
    /// In Swift on purpose: the identity has exactly one implementation (`ContextKey`), never a second one
    /// re-derived in SQL. Idempotent — rows that already carry an identity are left alone.
    static func backfillEditionContextIdentities(_ db: Database) throws {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, context_kind, context_source_id, context_search_query FROM feed_editions
            WHERE context_identity = '' OR context_key_json = ''
            """)
        for row in rows {
            let kind: String = row["context_kind"]
            let source: String? = row["context_source_id"]
            let query: String? = row["context_search_query"]
            let request: FeedContextRequest
            switch kind {
            case "main": request = .main
            case "source":
                guard let source, let uuid = UUID(uuidString: source) else { continue }
                request = .source(SourceID(rawValue: uuid))
            case "search":
                guard let query, let search = SearchContext(query: query) else { continue }
                request = .search(search)
            default: continue
            }
            let key = ContextKey(request: request)
            guard let json = key.canonicalJSON() else { continue }
            try db.execute(sql: "UPDATE feed_editions SET context_identity = ?, context_key_json = ? WHERE id = ?",
                arguments: [key.canonicalIdentity, json, row["id"]])
        }
    }
}
