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
        return migrator
    }
}
