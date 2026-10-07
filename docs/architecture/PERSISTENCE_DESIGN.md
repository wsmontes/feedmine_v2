# Persistence design — Phase 2A

## 1. Frozen physical topology

- `catalog.sqlite`: replaceable, read-mostly, independently generated catalog.
- `runtime.sqlite`: non-replaceable semantic runtime state, including durable user state.
- Asset filesystem: media bytes, with durable metadata intended for runtime storage later.

Phase 2A implements runtime lifecycle only. Catalog and asset storage remain unimplemented. No code or schema from the historical project is copied.

## 2. Runtime database lifecycle

RuntimeDatabaseLocation receives a directory and derives the canonical filename `runtime.sqlite`. The optional Application Support helper adds `FeedMine` to a caller-supplied root without global filesystem lookup.

RuntimeDatabase creates its parent directory, opens one GRDB DatabasePool and applies RuntimeMigrations. Its public initializer exposes only location and FileManager; internal migration injection is available to tests. The pool is private, and all properties are immutable. The wrapper has checked Sendable conformance because the selected GRDB DatabasePool already conforms to Sendable and serializes connection access. There is no fallback mode, second database path or automatic rebuilding.

## 3. Failure contract

Database unavailable is not empty database. Database failure is not first launch.

Directory creation failure throws `couldNotCreateDirectory`, including path and message. SQLite open/migration/read/write/checkpoint failures throw `storage`, preserving the SQLite extended result code and message. The primary SQLite category can be recovered from the low byte of the extended code. Other opening/migration failures throw `open`, including database path and message. Non-SQLite errors from internal read/write operation bodies propagate unchanged.

No failure becomes nil, an empty collection, a success flag or a new empty store. There is no in-memory fallback, retry state machine, disk reclaim or recovery implementation. Future Runtime/UI consumers decide degraded, read-only, blocked or recoverable presentation.

## 4. Migration authority

RuntimeMigrations is the single schema-evolution owner. Its internal current migrator registers the empty `runtime-foundation-v1` migration. GRDB's `grdb_migrations` bookkeeping is the authority; there is no separate metadata/schema-version table or user_version counter. Erase-on-schema-change is explicitly disabled both in the current migration configuration and when an internally supplied migrator is opened.

Tests verify reopen retains one foundation entry, and a failing test-only migration cannot erase a previously durable sentinel or commit its partial deletion. Production migrations create no domain tables.

## 5. WAL and concurrency

The persistent DatabasePool establishes WAL in its default journal configuration. Configuration.foreignKeysEnabled is explicitly true and applies to both writer and reader connections; no additional prepareDatabase hook is needed. Tests verify reader/writer foreign key settings, a real constraint error and journal_mode=WAL.

Reader count and busy handling retain GRDB defaults. No timeout, reader-count limit or maintenance cadence is frozen as a product policy. Writes use GRDB transactions and roll back if the operation throws.

checkpointWAL requires an explicit passive/full/restart/truncate mode. It runs on the serialized writer outside a transaction and returns SQLite's three actual PRAGMA columns as integers: busy, logFrames and checkpointedFrames. A query returning a busy result is not converted into an assertion of success. Checkpointing has no timer, scheduler, retry or background policy.

## 6. GRDB boundary

The only external dependency is official GRDB.swift, pinned exactly to 7.11.1. Only FeedMinePersistence and the SQLite-specific Persistence tests depend on its product. Inter-module FeedMine edges remain unchanged.

DatabasePool is private. Scoped read/write helpers and the GRDB migrator are internal. RuntimeMigrations is a public ownership namespace with no public GRDB-valued surface. No public Persistence API requires Database, DatabasePool or DatabaseMigrator. Tests import GRDB solely to issue/inspect SQLite statements and inject a failing migration; all databases are temporary on-disk databases.

The package declares macOS 10.15 and iOS 13 minimums required by the dependency. The root manifest remains tools 6.0; GRDB 7.11.1 itself requires a Swift 6.1 or newer compiler. Validation uses Swift 6.3.3. These are dependency compatibility floors, not product runtime tuning.

References: [official release](https://github.com/groue/GRDB.swift/releases/tag/v7.11.1), [versioned package manifest](https://github.com/groue/GRDB.swift/blob/v7.11.1/Package.swift), [DatabasePool configuration and Sendable conformance](https://github.com/groue/GRDB.swift/blob/v7.11.1/GRDB/Core/DatabasePool.swift), [foreign-key connection setup](https://github.com/groue/GRDB.swift/blob/v7.11.1/GRDB/Core/Database.swift).

## 7. What is intentionally absent

ContentStore, PublicationStore and SessionStore remain scaffolds. There are no source, origin, bookmark, read-state, publication, session, acquisition, search/FTS or selection-supply tables. Catalog, assets, retention, backup, read-only/degraded modes, repositories, database facades and protocols are unimplemented. Test sentinel/parent/child/checkpoint tables exist only in isolated test databases.

## 8. Next schema slice

Future slices must explicitly design their domain storage and atomicity boundaries before adding migrations. Local persistence as a whole is not complete. This task ends at the runtime physical lifecycle and failure contract; it does not implement the next user-state, canonical supply, catalog or publication slice.
