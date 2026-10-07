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
//   Phase 2A foundation plus Phase 2E publication-restore-v1 domain schema.
//

import GRDB

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
        return migrator
    }
}
