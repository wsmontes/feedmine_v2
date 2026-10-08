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

RuntimeMigrations is the single schema-evolution owner. Its internal current migrator preserves the empty `runtime-foundation-v1` migration, followed by `publication-restore-v1` then `canonical-supply-v1` and `canonical-media-candidates-v1`. GRDB's `grdb_migrations` bookkeeping is the authority; there is no separate metadata/schema-version table or user_version counter. Erase-on-schema-change is explicitly disabled both in the current migration configuration and when an internally supplied migrator is opened.

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

ContentStore is a concrete Sendable struct implementing atomic canonical changes, exact record/revision/current/membership reads and bounded narrow candidate windows. PublicationStore and SessionStore implement immutable publication history and one logical checkpoint through mechanical records; semantic mapping belongs to FeedMinePublication. ContentStore validates command shape, exact identities and expected-current state; it preserves immutable revision payloads and synchronizes membership/current/availability with selection_supply in a single RuntimeDatabase.write transaction. Neutral PersistenceValueCodingError is translated at store boundaries, preserving PublicationStore public errors without changing SessionStore. Phase 3B3 bounded candidate windows are complete; CandidateProvider remains deferred. There are no source/provider metadata, bookmark, read-state, acquisition or search/FTS tables. Catalog, assets, retention, backup, read-only/degraded modes, repositories, database facades and protocols are unimplemented. Test sentinel/parent/child/checkpoint tables exist only in isolated test databases.

## 8. Next schema slice

The local session/publication vertical slice is complete through Phase 2I: exact restore, actor-owned current state, memory-local viewport movement and explicit session checkpoint durability without canonical supply, catalog or network. Local persistence as a whole is not complete. The next persistence slice is canonical local supply. Its approved implementation gate is [CANONICAL_SUPPLY_DESIGN.md](CANONICAL_SUPPLY_DESIGN.md): four domain tables, immutable revisions, same-origin current-pointer integrity, atomic current-supply projection and bounded examined-work queries. Phase 3B1 is complete with the canonical migration and schema integrity tests. Phase 3B2 is complete with atomic ContentStore writes, exact reads and real SQLite rollback tests; Phase 3B3 bounded candidate windows are complete; CandidateProvider remains deferred. User-state, catalog, assets and retention remain future slices requiring explicit storage and atomicity design.

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

Phase 3B3 closes the canonical candidate Persistence path: one read snapshot fixes a caller-bounded selection_supply window before source eligibility and narrow current-revision hydration. The first/keyset queries use selection_supply_order without temporary ORDER BY sorting, and existence probes use the membership PK/index prefix. Functional and 10k/100k fixture tests cover sparse Source progress without refill, fanout, history and tail exhaustion. These populations are evidence sizes; no page size, wall-clock SLA or accumulated multi-window policy is frozen. Phase 3B1 schema and Phase 3B2 atomic ContentStore/exact reads are complete; CandidateProvider remains deferred. Scale closure required no production or schema changes.

## Phase 3I1 — canonical media facts

Phase 3H — complete. Phase 3I1 — canonical MediaCandidate facts — complete. runtime.sqlite gains exactly one structured-semantic table, media_candidates, through the additive canonical-media-candidates-v1 migration. This fifth canonical table is justified by an exact Media consumer; the original four 3A tables remain the canonical supply selection hot path. No candidateWindow/projection or CandidateProvider media join changes. Old migrations and non-erasing configuration remain intact.

CanonicalChange requires explicit complete ordered mediaCandidates, including [] when absent, with no hidden default. OriginRevision and its immutable ordered collection commit in one existing RuntimeDatabase.write transaction with canonical membership/current/availability/projection changes. IDs are caller-owned, not locator or asset identities. Wrong owners/duplicate IDs fail before writes. Existing revision payload conflicts are preserved; byte-exact same-ID fact conflicts precede ordered collection conflicts. Old pre-media revisions become immutable empty collections without backfill.

The revision FK uses NO ACTION, ordinals are nonnegative/unique per revision and the baseline role/class/dimension constraints are enforced. The unique autoindex supports exact ordered historical reads; no extra index or asset/preparation table exists. The public revision read uses one snapshot, distinguishes missing from empty, verifies contiguous ordinals and validates exact locator/UUID/semantic reconstruction. No public lookup by candidate ID or live-current media API is added. Migration tests preserve publication/canonical/session data; trigger tests prove full rollback for new origin and existing origin V2 failure after reopen. Local filesystem asset identity/materialization remains 3I2; network remains deferred.


## Phase 3L — future acquisition target/admission authority

Phase 3L — complete (design only): [ACQUISITION_DESIGN.md](ACQUISITION_DESIGN.md). No acquisition schema is implemented by 3L; no source catalog tables are authorized by 3L.

Preserve physical topology: catalog.sqlite is replaceable/read-mostly future catalog; runtime.sqlite is nonreplaceable semantic runtime plus future acquisition target/checkpoint authority. Catalog remains unimplemented. Current runtime publication/session, canonical supply and media candidate tables remain unchanged.

Future 3M1 direction is one acquisition_targets row per nominal FeedMine UUID target ID, connector kind, generation, enabled/revoked state, checkpoint revision and optional opaque checkpoint envelope (blob/schema/connector version). No generic URL/host/endpoint/configuration columns, source/provider/binding registry, fetching/failed/finished state, lease epoch, batch ledger or SupplyGeneration. Target sharing is independent of Source/Binding identity. Config/authorization changes fence old work by advancing target generation; checkpoint changes use their own monotonic CAS revision. Final SQL/types/migration are a later reviewed gate.

Future 3M2 Admission loads the exact enabled target, validates generation and checkpoint expectation, resolves external object/version identities, invokes the existing ContentStore canonical write body, refreshes supply and advances a supplied checkpoint in ONE RuntimeDatabase writer transaction. Refusal/failure rolls back every canonical/checkpoint effect. Three separately committed target-validation/content-write/checkpoint calls are forbidden. Acquisition → Persistence remains the dependency; Persistence does not import Acquisition, and GRDB remains internal.

ContentStore already has internal apply(_:in:) without a nested transaction. A single concrete Persistence admission operation over mechanical commands can reuse it, with internal transactional identity resolution; any extraction replaces that body with one shared internal helper, never a second canonical writer or Repository protocol. Unique external object/version tuples recover stored FeedMine record/revision IDs; exact immutable revision/media replay preserves payload and IDs. Lost-response replay after checkpoint advancement is refused by old CAS, without duplicated effects. No batch ledger is justified by this supported baseline; ambiguous historical unversioned deduplication remains unsupported pending a separate evidence-backed gate.

Future catalog/SourceBinding integration fences runtime targets BEFORE obsolete semantics may commit; Admission does not join catalog.sqlite or require a cross-database transaction. Connector-specific configuration/eligibility is upstream and reconstructible, while target validity/checkpoint survive restart. Fake target snapshots permit 3M without catalog persistence. A committed receipt reports checkpointAdvanced/selectableSupplyChanged, not a global generation; Composition notifies relevant Runtime scopes. No Target store, migration, Batch, Admission, connector or network code is introduced by this design.


## Phase 3M1 completion record

Phase 3L — complete

Phase 3M1 — durable target/checkpoint authority — complete

Phase 3M2 — not started

> AcquisitionTarget is durable operational work identity, not Source identity, Binding identity or endpoint identity.

> Target generation fences obsolete work. Checkpoint revision fences obsolete resumption proposals.

> Target validity and connector checkpoint survive restart without depending on catalog.sqlite.

> A checkpoint is opaque to FeedMine core.

> 3M1 creates authority only. It does not acquire or admit content.

Implemented Domain UUID-backed nominal AcquisitionTargetID follows the existing identity conventions; configuration changes preserve ID. AcquisitionTarget.swift owns enabled/revoked semantic state, opaque AcquisitionCheckpoint, exact Target snapshot and concrete AcquisitionTargetAuthority mapping over Persistence. No duplicated error taxonomy, SQL or lookup policy enters Acquisition; factual AcquisitionTargetStore errors propagate.

Persistence adds exactly acquisition-target-authority-v1 after publication-exposure-index-v1, with one acquisition_targets table and no explicit index beyond the primary-key autoindex. Ordered columns: id, connector_kind, generation, state, checkpoint_revision, checkpoint_blob, checkpoint_schema, checkpoint_connector_version. No previous migration, canonical/publication schema, FK, source relation, endpoint/configuration column or separate checkpoint table changes. Non-erasing migration preserves old schema objects and durable sentinel bytes.

Registration starts generation 1, enabled, checkpoint revision 0 and all checkpoint fields absent. Duplicate ID refuses replacement. A present empty Data checkpoint remains distinct from absent after reopen. Envelope schema is positive and version/kind UTF-8 is nonempty without normalization; exact bytes/schema/version survive mapping and persistence. Reads require canonical lowercase UUID, actual SQLite integer counters and actual BLOB checkpoint storage; malformed persisted types report field-specific corruption instead of coercion.

Explicit reconfigure asserts semantic configuration changed and always advances generation once, even for the same connector kind; durable state stays unchanged. Preserve leaves checkpoint/revision unchanged; clear advances revision only when a checkpoint was present; replace advances revision only when envelope bytes/schema/version differ exactly. Revoke/enable advance generation only on actual state transition, preserving checkpoint. Repeated matching-state requests return unchanged; stale expectations refuse before mutation.

Enabled-target checkpoint CAS validates state, generation and revision inside one writer transaction, then installs an explicit envelope and advances checkpoint revision exactly once EVEN if identical. It cannot clear and never changes generation. Both durable counters fit checked Int64 storage; an increment at Int64.max refuses without wraparound. A reconfiguration needing checkpoint-revision overflow also refuses the entire generation/config change atomically. Internal read/stamp/checkpoint primitives take Persistence-owned Database for later reuse; no public GRDB/callback transaction surface or content Admission exists.

Two real temporary on-disk suites cover exact migration/constraints, registration, reopen, state/config fencing, stale/no-write behavior, identical CAS, exact version bytes, representation/corruption and overflow rollback. Package.swift adds only FeedMineAcquisitionTests with Acquisition/Domain/Persistence dependencies; production graph is unchanged. No existing test is modified and no brittle global schema-count/delta equality is introduced.

No AcquisitionBatch, canonical mutation/Admission, planner/frontier/coordinator/connector/fakes, batch ledger, SupplyGeneration, leaseEpoch/bindingRevision stamp, network/catalog/SourceBinding persistence or Runtime wiring is implemented. 3M2 checkpoint + canonical Admission remains a separate reviewed gate; the standalone CAS here is authority only, not a substitute for that future shared content transaction.
