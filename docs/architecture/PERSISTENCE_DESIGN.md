# Persistence design — local publication/session and canonical supply schema

## 1. Frozen physical topology

- `catalog.sqlite`: replaceable, read-mostly, independently generated catalog.
- `runtime.sqlite`: non-replaceable semantic runtime state, including durable user state.
- Asset filesystem: media bytes, with durable metadata intended for runtime storage later.

Phase 2A implements runtime lifecycle; Phase 2E adds the first publication/session storage slice; Phase 3B1 completes the approved four-table canonical supply schema; Phase 3B2 implements atomic canonical ContentStore changes and exact reads. Catalog and asset storage remain unimplemented. No code or schema from the historical project is copied.

## 2. Runtime database lifecycle

RuntimeDatabaseLocation receives a directory and derives the canonical filename `runtime.sqlite`. The optional Application Support helper adds `FeedMine` to a caller-supplied root without global filesystem lookup.

RuntimeDatabase creates its parent directory, opens one GRDB DatabasePool and applies RuntimeMigrations. Its public initializer exposes only location and FileManager; internal migration injection is available to tests. The pool is private, and all properties are immutable. The wrapper has checked Sendable conformance because the selected GRDB DatabasePool already conforms to Sendable and serializes connection access. There is no fallback mode, second database path or automatic rebuilding.

## 3. Failure contract

Database unavailable is not empty database. Database failure is not first launch.

Directory creation failure throws `couldNotCreateDirectory`, including path and message. SQLite open/migration/read/write/checkpoint failures throw `storage`, preserving the SQLite extended result code and message. The primary SQLite category can be recovered from the low byte of the extended code. Other opening/migration failures throw `open`, including database path and message. Non-SQLite errors from internal read/write operation bodies propagate unchanged.

No failure becomes nil, an empty collection, a success flag or a new empty store. There is no in-memory fallback, retry state machine, disk reclaim or recovery implementation. Future Runtime/UI consumers implement the first-release failure presentation specified below; recovery capabilities remain future work.

## 4. Migration authority

RuntimeMigrations is the single schema-evolution owner. Its internal current migrator preserves the empty `runtime-foundation-v1` migration, followed by `publication-restore-v1` and then `canonical-supply-v1`. GRDB's `grdb_migrations` bookkeeping is the authority; there is no separate metadata/schema-version table or user_version counter. Erase-on-schema-change is explicitly disabled both in the current migration configuration and when an internally supplied migrator is opened.

Tests verify foundation exists exactly once, full applied history survives reopen unchanged, and a failing test-only migration cannot erase a previously durable sentinel or advance committed migration history. publication-restore-v1 creates exactly feed_editions, feed_segments, published_cards and session_checkpoint. canonical-supply-v1 adds exactly origin_records, origin_revisions, source_memberships and selection_supply with structural identity uniqueness, same-origin composite FKs, enum/version checks and the descending supply ordering index. No currentness trigger, cascade or SET NULL action is added.

## 5. WAL and concurrency

The persistent DatabasePool establishes WAL in its default journal configuration. Configuration.foreignKeysEnabled is explicitly true and applies to both writer and reader connections; no additional prepareDatabase hook is needed. Tests verify reader/writer foreign key settings, a real constraint error and journal_mode=WAL.

Reader count and busy handling retain GRDB defaults. No timeout, reader-count limit or maintenance cadence is frozen as a product policy. Writes use GRDB transactions and roll back if the operation throws.

checkpointWAL requires an explicit passive/full/restart/truncate mode. It runs on the serialized writer outside a transaction and returns SQLite's three actual PRAGMA columns as integers: busy, logFrames and checkpointedFrames. A query returning a busy result is not converted into an assertion of success. Checkpointing has no timer, scheduler, retry or background policy.

## 6. GRDB boundary

The only external dependency is official GRDB.swift, pinned exactly to 7.11.1. Only FeedMinePersistence and the SQLite-specific Persistence tests depend on its product. Inter-module FeedMine edges remain unchanged.

DatabasePool is private. Scoped read/write helpers and the GRDB migrator are internal. RuntimeMigrations is a public ownership namespace with no public GRDB-valued surface. No public Persistence API requires Database, DatabasePool or DatabaseMigrator. Tests import GRDB solely to issue/inspect SQLite statements and inject a failing migration; all databases are temporary on-disk databases.

GRDB may support older operating systems, but FeedMine intentionally declares its own product/development floors:

- iOS 18+ — product baseline; the first-release product target is iPhone.
- macOS 14+ — development/package-test baseline, not a first-release product surface.

Dependency minimums do not determine FeedMine product minimums. The root manifest remains tools 6.0; GRDB 7.11.1 itself requires a Swift 6.1 or newer compiler. Validation uses Swift 6.3.3.

References: [official release](https://github.com/groue/GRDB.swift/releases/tag/v7.11.1), [versioned package manifest](https://github.com/groue/GRDB.swift/blob/v7.11.1/Package.swift), [DatabasePool configuration and Sendable conformance](https://github.com/groue/GRDB.swift/blob/v7.11.1/GRDB/Core/DatabasePool.swift), [foreign-key connection setup](https://github.com/groue/GRDB.swift/blob/v7.11.1/GRDB/Core/Database.swift).

## 7. What is intentionally absent

ContentStore is a concrete Sendable struct implementing atomic canonical changes and exact record/revision/current/membership reads. PublicationStore and SessionStore implement immutable publication history and one logical checkpoint through mechanical records; semantic mapping belongs to FeedMinePublication. ContentStore validates command shape, exact identities and expected-current state; it preserves immutable revision payloads and synchronizes membership/current/availability with selection_supply in a single RuntimeDatabase.write transaction. Neutral PersistenceValueCodingError is translated at store boundaries, preserving PublicationStore public errors without changing SessionStore. Phase 3B3 bounded candidate queries remain deferred. There are no source/provider metadata, bookmark, read-state, acquisition or search/FTS tables. Catalog, assets, retention, backup, read-only/degraded modes, repositories, database facades and protocols are unimplemented. Test sentinel/parent/child/checkpoint tables exist only in isolated test databases.

## 8. Next schema slice

The local session/publication vertical slice is complete through Phase 2I: exact restore, actor-owned current state, memory-local viewport movement and explicit session checkpoint durability without canonical supply, catalog or network. Local persistence as a whole is not complete. The next persistence slice is canonical local supply. Its approved implementation gate is [CANONICAL_SUPPLY_DESIGN.md](CANONICAL_SUPPLY_DESIGN.md): four domain tables, immutable revisions, same-origin current-pointer integrity, atomic current-supply projection and bounded examined-work queries. Phase 3B1 is complete with the canonical migration and schema integrity tests. Phase 3B2 is complete with atomic ContentStore writes, exact reads and real SQLite rollback tests; Phase 3B3 bounded candidate queries remain deferred. User-state, catalog, assets and retention remain future slices requiring explicit storage and atomicity design.

Phase 2C closes the baseline semantic PublishedCard payload. Publication/session schema design: [PERSISTENCE_PUBLICATION_SCHEMA.md](PERSISTENCE_PUBLICATION_SCHEMA.md). Phase 2D designed the first domain schema; Phase 2E implements its migration, concrete stores and internal semantic mapping. Phase 2E is complete and incorporated into main. Phase 2B defines publication identity and exact logical restore semantics only; see [Publication restore contract](PUBLICATION_RESTORE_CONTRACT.md).

## 9. Restore-first product contract

The following product decisions are frozen contracts for future slices. Phase 2A closure documented them; Phase 2E now implements durable publication/session storage and exact reopen restoration, without Runtime/UI execution.

> The first complete persistence-driven FeedMine experience is exact warm/offline restoration of previously published local history.

```text
previously published FeedEdition
        ↓
session/card anchor persisted
        ↓
application terminates
        ↓
network unavailable
        ↓
application launches
        ↓
runtime.sqlite opens
        ↓
same retained Edition restored
        ↓
same publication ordering
        ↓
window restored around same PublicationCard
        ↓
feed presented without network/catalog/acquisition
```

While the required Edition is retained, exact restore means:

- Same Edition identity.
- Same published ordering.
- Same PublicationCard anchor.
- Same surrounding published history.

Restore does not mean running Selection again to produce something similar, or finding approximately the same upstream content. Visual geometry may change; editorial history may not.

Warm/offline first presentation does not depend on network, catalog refresh, a connector, acquisition, selection or remote image download. It conceptually depends on:

- ContextKey.
- FeedEdition identity.
- Published immutable history.
- SessionCursor/card anchor.
- Presentation-ready frozen card data.
- Local user-state overlays when applicable.

Phase 2E persists the frozen history and logical cursor values. Phases 2G–2I implement local Runtime presentation, current session ownership, memory-local viewport movement and an explicit checkpoint operation. Application lifecycle wiring, UI implementation and local user-state overlays remain deferred.

## 10. Bookmark contract

> Bookmark is durable user state and must remain semantically presentable after reconstructible canonical content disappears.

A future Bookmark must preserve a snapshot sufficient to represent the saved item, conceptually including:

- Stable subject/origin identity.
- Headline/title.
- Presented excerpt/text.
- Attribution.
- Target link when known.
- Authored/published timestamp when known.
- Media identity/metadata sufficient for media or a deterministic placeholder.
- savedAt.

Bookmark does not automatically imply full article archival, permanent image-byte retention, retention of the entire FeedEdition or retention of the entire OriginRevision. Bookmark storage is not implemented in Phase 2A.

## 11. Seen / Read / Opened / Consumed contract

- **Seen / Exposure:** evidence of actual viewport visibility.
- **Read:** durable user-visible state.
- **Opened:** explicit user interaction opening primary content.
- **Consumed:** policy projection derived from exposure/open/read facts.

Frozen rules:

- Appearing in the SwiftUI tree does not mean Seen.
- Prefetched content below the viewport does not mean Seen.
- Viewport exposure alone does not mean Read.
- Explicit Mark as Read sets Read.
- Open sets Read.
- Mark as Unread does not erase historical exposure/consumption facts.
- Consumed is not stored as one timeless absolute boolean truth.

Exposure/read storage remains unimplemented in this phase.

## 12. Source identity contract

SourceID is FeedMine-owned. It is not derived from URL, endpoint, connector identity or catalog row position.

Future catalog integration requires a persistent source registry/manifest with IDs stable across catalog generations. This registry is not implemented now.

If a Source created/imported by the user later corresponds to a catalog Source, do not silently replace identity or auto-merge IDs. Preserve both identities and allow future explicit association/equivalence. Association is not implemented now.

## 13. Local content search baseline

The first content search covers current locally available canonical searchable supply via future runtime FTS.

It does not initially include all historical revisions, all old PublishedCards, evicted publication history or remote connector search. Catalog search remains separate. Bookmark search may be a future surface. This contract does not add search/FTS storage or implementation.

## 14. Database failure — first release

If runtime.sqlite cannot open safely, the first release presents an explicit failure state with Retry. It must not present an empty first launch, use a memory fallback or automatically reset the database.

The first release does not require backup restore UI, database repair UI or full database export UI. These capabilities remain future work. Phase 2A closure documents this presentation contract without implementing UI or retry behavior.
