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
//   Domain tables, duplicate schema counters, recovery, database lifecycle or catalog.
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
//   Phase 2A foundation migration only; no domain schema.
//

import GRDB

public enum RuntimeMigrations {
    static var current: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false
        migrator.registerMigration("runtime-foundation-v1") { _ in
            // Establish authority and bookkeeping without creating domain tables.
        }
        return migrator
    }
}
