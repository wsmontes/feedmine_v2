# FeedMine Persistence Discovery

Research baseline:
- New repository: wsmontes/feedmine_v2
- New base: main at 109dec35884cb6a1a2f0f11da031bfb80a21ebd4
- Legacy evidence repository: wsmontes/feedmine-dev
- Legacy branch inspected: fix/release-1.0-final-hardening, head observed during this research: 712a6ba93c6a8ab28c3b3c0e2b2777d1e3341d0c
- Research date: 2026-10-07

This document is architectural discovery. It intentionally contains no final SQL schema, no final column list, no migration, and no production implementation.

# 1. Executive conclusion

FeedMine needs two SQLite databases, not three:

1. catalog.sqlite — replaceable/read-mostly product catalog and source-discovery snapshot.
2. runtime.sqlite — all non-replaceable local runtime facts, including durable user state.
3. asset filesystem — content-addressed media bytes with database metadata in runtime.sqlite.

This is Option B from the investigation brief.

The strongest reason is not performance. It is atomicity and lifecycle. The legacy split between content/runtime state and user.sqlite repeatedly created mirrors, projections, reconciliation jobs and retention races. Bookmarks, bookmark snapshots, retention pins and user-state projections could disagree because they lived in different databases and could not participate in one SQLite transaction. Keeping durable user state inside runtime.sqlite removes an entire class of coordination failure while still allowing reconstructible supply to be evicted independently.

catalog.sqlite should stay separate because its lifecycle is genuinely different. The legacy catalog currently contains 77,443 sources, 6,450 taxonomy nodes and 77,443 placements in a roughly 118 MB generated SQLite snapshot compiled from 118 OPML files. It can be built separately and atomically replaced. Runtime/user state cannot be treated that way.

SQLite remains the correct storage engine. GRDB remains the simplest justified choice. It gives FeedMine direct SQLite semantics, DatabasePool, WAL, migrations, FTS5 access, typed errors and transaction control without forcing an object-graph persistence model. Raw SQLite adds plumbing without adding useful control. SwiftData/Core Data hide or complicate exactly the details FeedMine needs to control: multi-fact atomic admission, FTS projections, deterministic indexed reads, explicit WAL/failure behavior, query plans and retention SQL.

The publication/persistence boundary can be closed without moving publication semantics into Persistence and without adding a dependency edge. FeedMinePublication remains the sole semantic owner of FeedEdition, FeedSegment and PublishedCard. FeedMinePersistence may expose concrete mechanical publication storage commands/snapshots that contain only already-frozen scalar/domain identifiers and have no editorial behavior. Publication constructs and validates semantic history; Persistence serializes/reads it. Those mechanical values are not a second publication domain and must not be used by Runtime/UI directly.

Do we now know enough to design the database? YES.

We know enough to freeze database count, technology, lifecycle/failure rules, durability classes, atomicity boundaries, query shapes, retention roots and the Publication/Persistence representation strategy before writing SQL. Exact table/column/index choices remain the next design step.

# 2. Product storage requirements

The storage design exists to preserve product behavior, not to mirror module names.

Storage invariants derived from the new product contract and the observed legacy failures:

- S-01 — Warm launch never waits for network when a usable local publication exists.
- S-02 — Persistent-store failure never masquerades as an empty first launch.
- S-03 — Refresh never resets unrelated user state.
- S-04 — Eviction of reconstructible content never destroys durable user state.
- S-05 — Published history is never silently rewritten by upstream mutation.
- S-06 — Acquisition checkpoint never advances beyond admitted semantic content.
- S-07 — A retained published card remains presentable after canonical/raw supply eviction.
- S-08 — Context change reprioritizes work but does not gratuitously destroy reusable previous work.
- S-09 — Background maintenance never changes visible history unexpectedly.
- S-10 — Disk pressure degrades safely by shedding reconstructible/bounded data before semantic user state.
- S-11 — A bookmark is semantically complete enough to survive the disappearance of its source content row.
- S-12 — Durable user state has exactly one authority. Derived read models may exist, but there is no second writable mirror.
- S-13 — User-visible read state survives canonical payload eviction. Click/consumption history has an explicit independent retention policy.
- S-14 — Admission validity is decided at commit time. Cancellation is only an optimization.
- S-15 — Publication commits and acquisition admission are domain transactions, not generic batched telemetry writes.
- S-16 — Runtime database open/migration failure is observable and blocks unsafe mutation; no silent volatile fallback is permitted.
- S-17 — Catalog replacement cannot invalidate already-published attribution/history or erase user selection state.
- S-18 — No retention decision may become less protective because a protection-root read failed. Root failure is fail-closed.
- S-19 — No correctness invariant depends on an actor, in-memory cache, timer or task surviving process death.
- S-20 — Reusable work is represented by durable structures FeedMine already needs: publication, canonical supply, prepared media and session checkpoints. No separate ContextCache is introduced.

Order-of-magnitude planning evidence:

| Quantity | Planning order | Evidence / reasoning |
|---|---:|---|
| Catalog Sources | 10^5 | Legacy generated catalog has 77,443 sources. |
| Catalog SQLite size | 10^8 bytes | Legacy catalog manifest reports 117,956,608 bytes including FTS/metadata. |
| Simultaneously useful acquisition targets | 10^2–10^3 | Runtime must use a bounded frontier rather than all ~77k catalog sources. |
| OriginRecords admitted per active day | 10^3–10^4 | Hundreds/thousands of active source observations plus continuous replenishment; exact value is workload-dependent. |
| Retained OriginRecords | 10^4–10^5 typical, possibly 10^6 stress | Legacy tests explicitly exercise 10k–100k local content; new runtime should remain bounded. |
| OriginRevisions/day | 10^3–10^4 | Usually one accepted revision per newly observed object plus a smaller update fraction. |
| Source memberships/origin | 1–10 | Usually one/few memberships; architecture explicitly allows many-to-many. |
| Relations/origin | 0–10 | Sparse editorial relations are expected; should not drive hot-path cost. |
| Canonical text + current-search material | 10^8 bytes at 10^5 records | Text and FTS can be a major fraction of runtime storage; indexing all historical revisions would multiply this unnecessarily. |
| Media candidate metadata | 10^4–10^5 rows | Zero/few candidates per current revision. Bytes live outside SQLite. |
| Published cards/active hour | 10^2–10^3 | Product target is a continuously prepared runway, potentially hundreds of ready cards. |
| Published cards/active day | 10^3–10^4 | Depends on user activity and context switching. |
| Recent reusable contexts | 10^0–10^1 normally | Retention should be budget/usefulness-based, not fixed-count architecture. |
| Exposure events/day | 10^3–10^4 active use | Viewport-derived history is high volume and therefore bounded/batched. |

These are sizing bands, not product limits or magic thresholds.

# 3. Evidence from legacy FeedMine

The legacy code is production evidence, not architecture to copy.

Observed scale:
- FeedStore.swift is 9,262 lines on the inspected branch and owns orchestration, persistence, filtering, history, startup, retention, publication-adjacent state and multiple compatibility paths.
- FeedRuntimeV2/FeedStorage contains 21 Swift source files.
- PublicationRepository.swift is 1,558 lines.
- RetentionCoordinator.swift is 1,052 lines.
- UserStateStore.swift is 1,451 lines.
- BookmarkStore.swift is 688 lines.
- The generated catalog contains 77,443 sources and is approximately 118 MB.

## KEEP / REJECT / INVESTIGATE

| Legacy decision | Classification | Reason |
|---|---|---|
| SQLite as authoritative store for persistent facts | KEEP | Fits local-first/offline-first product and exact transaction/query needs. |
| GRDB DatabasePool for runtime | KEEP concept | Concurrent reads + serialized SQLite writes are appropriate. Exact reader count is tuning. |
| WAL | KEEP | Correct for local concurrent reads/writes. |
| foreign_keys = ON on every connection | KEEP | Integrity should be enforced in storage, not merely comments. |
| eraseDatabaseOnSchemaChange = false | KEEP | Runtime/user state must never disappear because schema changed. |
| No silent in-memory fallback | KEEP | Directly fixes P-01 failure class. |
| Preserve SQLite result code, including disk-full | KEEP | Needed for safe degradation policy. |
| Explicit admission transaction + checkpoint CAS | KEEP concept | Strong product invariant S-06. |
| Explicit publication transaction + tail/token revalidation | KEEP concept | Strong product invariant S-05/S-15. |
| Current-selectable read projection | KEEP concept | Proven useful for bounded hot-path selection. |
| Canonical current-revision FTS projection | KEEP concept | Correct search lifecycle; historical revisions need not all remain indexed. |
| Session checkpoint using logical card identity, not pixels | KEEP concept | Warm restore requirement. |
| Exposure facts plus a derived projection | KEEP concept, simplify | Facts/projection can be atomic in one DB; do not add cross-DB mirrors. |
| Three physical SQLite stores | REJECT | user.sqlite separation created cross-DB authority/mirror bugs. |
| URL-derived 32-bit Source identity | REJECT | New SourceID is FeedMine-owned and must remain stable across endpoint/catalog change. |
| User-state projection as a bridge between authorities | REJECT in new architecture | With one runtime/user DB, selection can read the authority or an in-DB reconstructible projection. |
| Legacy content bookmark pin mirror | REJECT | Bookmark protection must not depend on a separately synchronized mirror. |
| FeedStore as broad owner | REJECT | Violates one-owner-per-responsibility. |
| Production/legacy alternate feed paths | REJECT | Violates INV-14. |
| Large generic retention coordinator with many compatibility cases | REIMPLEMENT CONCEPT | Protection-root and class ideas remain; implementation should follow the new durability model, not legacy tables. |
| WAL checkpoint return handling | CHANGE | Legacy code reads the first result column and can report busy as success. |
| Fixed maximumReaderCount = 4 | NEEDS EVIDENCE | Safe implementation detail, not a product invariant. |
| Weekly VACUUM on shared queue | DROP | Legacy behavior can block user-facing DB work and requires large free space. Maintenance must be workload/pressure-aware. |
| Full runtime backup policy | INVESTIGATE | WAL-aware backup is required, but legacy RuntimeDatabase only exposes checkpoint behavior, not a complete product backup policy. |

## Legacy code classification

Preference: reimplement concept, not code.

| Component | Classification | New-use lesson |
|---|---|---|
| RuntimeDatabase | REIMPLEMENT CONCEPT | Pool/WAL/FK/error semantics are sound; simplify and fix checkpoint reporting. |
| RuntimeMigrations | REIMPLEMENT CONCEPT | Keep explicit migrations and non-erasing behavior; schema itself is not reusable. |
| AcquisitionTargetStore | REIMPLEMENT CONCEPT | Target generation/checkpoint durability remains necessary. |
| AdmissionEngine | REIMPLEMENT CONCEPT | Preserve one atomic admission unit and stale-work rejection. |
| AdmissionLedger | REIMPLEMENT CONCEPT selectively | Receipts/evidence are useful for idempotency/debug but should be bounded. |
| SourceRegistry | DISCARD implementation / REIMPLEMENT identity concept | Old URL-derived identity is incompatible with new SourceID. |
| LegacyMappingStore | MIGRATION REFERENCE ONLY | Needed only for Phase 15 import/bridge. |
| MediaCandidateRepository | REIMPLEMENT CONCEPT | Exact immutable revision -> candidates query remains useful. |
| PublicationRepository | DISCARD implementation / REIMPLEMENT CONCEPT | Six-table aggregate accumulated storage, publication, restore, asset and diagnostic responsibilities. |
| SelectionSupplyRepository | REIMPLEMENT CONCEPT | Bounded projection + keyset access is strong evidence. |
| CanonicalSearchRepository | REIMPLEMENT CONCEPT | Current-revision FTS read model is justified. |
| ExposureStore | REIMPLEMENT CONCEPT | Atomic fact + projection is useful; simplify scopes/retention around current product needs. |
| SessionCheckpointStore | REIMPLEMENT CONCEPT | Warm restore contract is valid. |
| UserStateProjectionStore | DISCARD | It existed because user authority was in another DB. |
| RetentionPolicy/Coordinator | REIMPLEMENT CONCEPT | Durability classes/protection roots remain; remove compatibility complexity. |
| Diagnostics/Recovery helpers | REIMPLEMENT SELECTIVELY | Only diagnostics that prove product invariants should survive. |
| UserStateStore | MIGRATION REFERENCE + REIMPLEMENT CONCEPT | User-owned state must survive, but not in a separate physical DB. |
| BookmarkStore | MIGRATION REFERENCE + REIMPLEMENT CONCEPT | One authoritative bookmark transaction with snapshot; no mirror pin. |
| FeedStore | DISCARD AS ARCHITECTURE | Mine product requirements only. |
| SQLiteCatalogStore/compiler | REIMPLEMENT CONCEPT | Generated/replaceable read-mostly SQLite snapshot is a good lifecycle. |
| CatalogUpdateService | REIMPLEMENT CONCEPT selectively | Atomic staging/replacement is correct for catalog only. |
| build_catalog.py | REIMPLEMENT/REUSE LOGIC ONLY AFTER IDENTITY REVIEW | Build pipeline is useful evidence; old source-ID derivation must not survive. |

COPY: ideally none.

## Legacy performance evidence classification

| Test group | Classification | Evidence retained |
|---|---|---|
| DatabasePerformanceTests | useful evidence mixed with implementation noise | 1k/5k writes, filtering end-to-end, local FTS; host I/O variability shows brittle wall-clock thresholds are weak correctness gates. |
| PersistencePerformanceTests | implementation-specific evidence | Store open and 5k batch costs are useful workload shapes, not architecture. |
| CatalogPerformanceTests | useful evidence | 10k catalog/content search and paginated reads show expected scale. |
| LargeCatalogMemoryTests | useful scale evidence; old memory result is implementation noise | 10k/50k/100k datasets are relevant; ~425 MB at 10k reflects old pipeline, not a new budget. |
| FeedStorageTests | strong correctness evidence | Real on-disk tests for WAL/FK, 10k/100k bounded selection, admission rollback, crash termination, publication atomicity and retention roots. |

# 4. Existing Runtime V2 storage inventory

The old Runtime V2 is much closer to the new conceptual model than FeedStore, but it still reflects migration constraints and a three-store world.

| Component | Fact persisted / queried | Why it existed | What breaks if lost | Reconstructible/bounded? | New architecture |
|---|---|---|---|---|---|
| RuntimeDatabase | SQLite lifecycle, metadata | Single durable runtime authority | All runtime durability unavailable | No | REIMPLEMENT |
| RuntimeMigrations | schema evolution | Durable upgrades | App cannot safely open state | No | REIMPLEMENT |
| AcquisitionTargetStore | target state/generation/checkpoint | Resume and reject stale work | Duplicate/gap/replay errors | Configuration/checkpoint durable | REIMPLEMENT |
| AdmissionEngine | accepted records/revisions/memberships/relations/media/offers/checkpoint | Atomic external->canonical boundary | Semantic gaps or stale mutation | Canonical payload partly evictable; checkpoint not | REIMPLEMENT |
| AdmissionLedger | batch receipts/evidence | Idempotency/debug/replay | Duplicate processing/debug loss | Receipts/evidence bounded | REIMPLEMENT selectively |
| SourceRegistry | runtime Source rows | Stable membership keys | Membership cannot resolve | Source identity must be durable | REIMPLEMENT with new identity |
| LegacyMappingStore | old ID/source mapping | Migration compatibility | Legacy import/bridge fails | Migration-only | DROP after migration |
| MediaCandidateRepository | candidates for exact revision | Media preparation | No media preparation input | Reconstructible from canonical revision/evidence | REIMPLEMENT |
| SelectionSupplyRepository | current-selectable projection | Cheap bounded selection | Hot-path joins become complex/expensive | Reconstructible | REIMPLEMENT |
| CanonicalSearchRepository | current-revision FTS | Local content search | Search unavailable/slower | Reconstructible | REIMPLEMENT |
| PublicationRepository | edition/segment/card/assets/media prep + activation/restore/integrity | Immutable published history | Warm restore/history lost | Published history durable per retention; some asset bytes evictable | REIMPLEMENT split by ownership |
| ExposureFactStore | exposure facts | History semantics | Seen/consumed policies lose evidence | Bounded operational history | REIMPLEMENT |
| HistoryProjectionStore | current history projection | Fast exclusions/overlays | Selection/history slower | Reconstructible from retained facts, or directly writable if policy chooses | REIMPLEMENT only if needed |
| SessionCheckpointStore | context/edition/card anchor | Warm restore | Launch must select/rebuild | Durable while session/context retained | REIMPLEMENT |
| UserStateProjectionStore | mirror of user.sqlite | Let runtime query external authority | Runtime and authority diverge | Reconstructible mirror | DISCARD |
| RetentionPolicyStore | limits | Bounded local storage | Unbounded growth | Durable configuration | REIMPLEMENT |
| RetentionCoordinator | GC account/roots | Enforce budgets safely | Disk growth or semantic deletion | Coordination ephemeral; GC ledger bounded | REIMPLEMENT smaller |
| Recovery/Diagnostics | failure seeds/metrics | Rehearsal/debug | Harder diagnosis | Bounded | Selective |

Old PublicationRepository grew because it legitimately needed one atomic publication commit but also became the owner of: edition lifecycle, activation swap, card serialization, asset-version creation, published asset references, media-preparation persistence, canonical-content reads, restore materialization, occurrence history, integrity checks and orphan-asset queries. The new design should preserve the single atomic publication transaction while moving semantic composition to FeedMinePublication and asset byte lifecycle to FeedMineMedia/Persistence.

Old SelectionSupplyRepository provides strong evidence for a small current-selectable projection. Its 10k and 100k query-plan tests prove a bounded primary-key/keyset window can avoid scanning the full supply. The projection is justified as a reconstructible operational index, not a second canonical authority.

# 5. Legacy persistence failures and lessons

The existing persistence review identified 13 concrete failures.

| ID | OLD FAILURE | USER IMPACT | ROOT ARCHITECTURAL CAUSE | NEW ARCHITECTURE INVARIANT |
|---|---|---|---|---|
| P-01 | Any FeedStore open failure could fall back to empty in-memory state. | Bookmarks/collections/read state appeared erased; new writes disappeared on exit. | Availability was preferred over truthful durability state. | S-02/S-16: no silent volatile fallback; storage failure is explicit blocked/degraded state. |
| P-02 | Content refresh overwrote all feed_item columns and reset read/clicked/consumed. | Previously read/clicked items became unread/unseen. | User state lived in mutable content rows. | S-03/S-04: content mutation cannot update independent user-state facts. |
| P-03 | Retention swallowed bookmark-authority read failure and used a possibly stale projection. | GC could delete content supporting a saved item. | Protection root depended on another DB and fail-open fallback. | S-18: root read failure is fail-closed; single user-state authority in same DB. |
| P-04 | Some bookmark paths wrote no snapshot/pin. | Saved item disappeared after content eviction. | Bookmark semantic survival depended on reconstructible content and mirror synchronization. | S-11: bookmark + minimum durable snapshot/protection identity commit atomically. |
| P-05 | Protected editions were counted against max retained editions. | More unprotected history purged than policy intended. | Retention selection mixed roots and quota accounting. | Protected objects are removed from candidate accounting before budgets are applied. |
| P-06 | Bookmark toggle read then wrote across await with a fresh operation ID. | Double tap/reentrancy could leave wrong bookmark state. | Toggle semantics were not atomic/idempotent. | Explicit desired state or atomic read-modify-write with stable operation identity. |
| P-07 | User list reconciliation used hydrated content and swallowed authority errors. | Saved membership could vanish from runtime projection; green reconciliation could do nothing. | Projection was coupled to content existence and cross-DB best-effort replay. | Durable membership is authoritative and content-independent; no bridge when same DB. |
| P-08 | Retention protected bookmark/smart feed/source history but not read/clicked/consumed semantics; bookmark protection used mirror. | User history disappeared and bookmarks could lose content. | User history was embedded in evictable content and protection used stale mirror state. | S-04/S-13: history/state rows have independent lifecycle. |
| P-09 | Weekly VACUUM ran on the shared serialized content queue. | Search/bookmark/feed reads could freeze for seconds/minutes. | Heavy maintenance shared the interaction path and used a time-based blanket policy. | Maintenance is resource/need-driven and never blocks presentation-critical work. |
| P-10 | Missing default bookmark list fell back to numeric ID 1 and cached it. | Pin sync could fail or target wrong list. | Failure was converted into guessed state. | Missing authority data is an error/invariant violation, never a guessed ID. |
| P-11 | WAL checkpoint read the busy flag as the result and could report success while WAL remained. | Disk growth hidden by false diagnostics. | Storage result shape was collapsed incorrectly. | Checkpoint contract records busy/log/checkpointed status truthfully. |
| P-12 | Migration deleted placeholder feed rows based on content-DB bookmark mirror. | User-bookmarked item could be deleted during migration. | Migration trusted a non-authoritative mirror. | Migrations touching semantic data consult the authority in the same DB/transaction or do not delete. |
| P-13 | Bookmark write errors were swallowed. | User taps appeared to randomly do nothing. | User-action durability failure was treated as no-op. | Durable user action reports failure and preserves previous state; never silent. |

Classification counts used in the final status:
- Persistence failures analyzed: 13.
- User-state survival/authority issues: 9 (P-01, P-02, P-03, P-04, P-06, P-07, P-08, P-10, P-12/P-13 are both user-state related; the conservative count groups migration/write-feedback as one reliability class).
- Retention/space-management issues: 6 (P-03, P-04, P-05, P-08, P-09, P-11; P-12 also intersects migration/retention but is counted primarily as authority/migration).

# 6. Fact ownership matrix

| Fact | Semantic owner | Writer | Readers | Durability | Reconstructible? | Transaction relationships |
|---|---|---|---|---|---|---|
| Source | FeedMineDomain/product catalog semantics | Catalog build or explicit user-source action | Planning, UI source surfaces, acquisition planner | Catalog snapshot; user-created source durable | Catalog source yes from shipped snapshot; user-created no | User enablement is separate user state |
| Provider | FeedMineDomain/catalog semantics | Catalog/admission attribution | Selection, publication | Catalog/canonical | Usually reconstructible | Frozen into publication attribution when displayed |
| SourceBinding | Acquisition/catalog boundary | Catalog build or user-source config | Acquisition planner/admission | Declarative durable | Rebuildable for catalog sources | Binding generation validates admission |
| CatalogGeneration | Catalog lifecycle | Catalog activation | FeedPlan/editorial revision resolver | Durable snapshot metadata | Yes from active catalog | Captured into EditorialRevision, never cross-DB transaction |
| OriginRecord | Canonical identity | Admission | Selection, search, media, user-history resolution | Canonical identity anchor | Payload may be reconstructible; identity must survive while referenced | Current revision update with revision admission |
| OriginRevision | Canonical content | Admission | Selection, search, media, publication composition | Canonical local supply | Yes unless protected | Immutable insert + optional current pointer change |
| ExternalIdentity | Admission/connector boundary | Admission | Identity resolution/migration/debug | Identity anchor/evidence | Depends on external system; keep while referenced | Must resolve idempotently with OriginRecord |
| SourceMembership | Canonical supply | Admission | Selection/source view | Canonical local supply | Yes | Same admission transaction as observation |
| ContentRelation | Canonical supply | Admission | Selection/threading/clustering | Canonical local supply | Yes | Same admission transaction |
| ContentEntity | Domain identity/equivalence | Identity process/admission-derived work | Selection/publication | Bounded canonical relation | Usually rebuildable if evidence remains | No destructive merge |
| ContentCluster | Editorial soft relation | Derived canonical processing | Sequencing | Bounded/reconstructible | Yes | Versioned relation update/replace |
| MediaCandidate | Canonical media evidence | Admission/translator | Media preparation | Canonical local supply | Yes | Same admission transaction |
| InteractionOffer | Canonical capability | Admission/translator | Publication/interaction coordinator | Canonical/bounded | Often reconstructible | Freeze required published action handle if retained |
| AcquisitionTarget | Acquisition | Acquisition planner/configuration | Coordinator/admission | Durable operational config | Reconstructible partly from bindings, but current state/checkpoint not | Generation/state with checkpoint validation |
| checkpoint | Connector-owned semantics persisted by Acquisition | Admission | Connector/coordinator | Durable operational progress | No | Atomic with admitted content it represents |
| FeedPlan | Editorial | Resolver | Selection/publication | Usually reconstructible config | Yes | EditorialRevision identity must be persisted with Edition |
| EditorialRevision | Editorial identity | Resolver | Publication/session/restore | Durable when referenced by Edition | Reconstructible only if exact version inputs remain | Edition belongs to exact revision |
| FeedEdition | Publication | PublicationCoordinator | Session/restore/retention | Durable published history under policy | No while retained | Created/activated atomically with first usable segment as policy defines |
| FeedSegment | Publication | PublicationCoordinator | Session/window | Durable published history | No while retained | Append atomically with cards |
| PublishedCard | Publication | PublicationCoordinator through Persistence | Session/presentation/history | Durable published history | No while retained | Atomic segment commit; frozen payload |
| SessionCursor | Runtime session semantics | FeedSession | Warm restore | Durable checkpoint | No | Must name retained Edition/card consistently |
| Exposure | Runtime/history semantics | Exposure pipeline | Selection/history policy | Bounded operational history | No, but can expire | Fact + any projection atomically |
| bookmark | User-state semantics | User action | UI, selection, retention | Durable user state | No | Desired state + snapshot/subject identity atomically |
| read state | User-state/history semantics | User action/session policy | UI/selection | Durable user-visible state | No | Independent of content payload |
| clicked state/history | User history | Card-open action | Last-clicked surface/history | Bounded user-visible history | No | Event/state independent of content payload |
| consumed state/history | Exposure/history policy | Exposure projection | Selection | Bounded operational history | Derivable if exposure facts retained; otherwise projection is authority for window | Same transaction as triggering facts if both stored |
| collection membership | User-state semantics | User action | Context resolver/selection/UI | Durable user state | No | Atomic membership operation |
| prepared media | Media | MediaPreparation | Publication | Reconstructible/bounded | Yes | DB metadata only after crash-safe file materialization |
| asset metadata | Media/Persistence | Asset store | Materializer/publication/retention | Identity durable while referenced; bytes evictable | Metadata partly reconstructible from file/hash | File rename then DB reference; orphan file is safe |
| user source enablement/preferences | User-state semantics | User action | FeedPlan/acquisition planning | Durable user state | No | Never written into replaceable catalog |
| selection_supply projection | Persistence read model | Admission/current-revision changes | Selection | Reconstructible cache/index | Yes | Updated in same transaction as current canonical state |
| canonical FTS projection | Persistence search read model | Admission/current-revision changes | Search | Reconstructible cache/index | Yes | Updated consistently with current revision |
| published media identity | Publication | PublicationCoordinator | Presentation/materializer | Durable with published card | No while card retained | Frozen in publication; byte file may later be absent |

# 7. Durability classification

## Durable user state

Survives indefinitely until explicit user action or an explicit product history policy:
- bookmarks;
- bookmark semantic snapshots/minimum subject identity;
- collection/list membership;
- explicit source enablement/follow state;
- explicit preferences;
- user-created/imported source definitions that are not recoverable from the product catalog;
- user-visible read/unread state.

Durable user state is never cascaded from canonical content or publication deletion.

## Durable published history

Durable while protected by publication/session/context-retention policy:
- FeedEdition identity and EditorialRevision identity;
- FeedSegment ordering;
- PublishedCard frozen payload;
- PublishedOrigin/frozen attribution;
- Published media identity and render contract;
- session checkpoint/cursor to retained publication.

Published history may be bounded, but upstream mutation cannot rewrite it.

## Canonical local supply

Locally authoritative while retained, but generally reacquirable:
- OriginRecord identity and availability;
- OriginRevision payloads;
- memberships;
- relations;
- provider attribution;
- MediaCandidate;
- InteractionOffer;
- current-revision pointer.

Important distinction: evicting an old revision is much safer than evicting the minimal OriginRecord/external-identity anchor referenced by durable/bounded user history. Payload and identity-anchor retention need not be identical.

## Bounded operational history

- exposure facts;
- clicked/open history;
- consumed projections/history;
- target health/failures;
- admission receipts;
- connector evidence;
- diagnostics;
- GC run history;
- recent superseded editions not otherwise protected.

## Reconstructible cache/index

- selection_supply;
- current-revision FTS;
- catalog compiled SQLite from its authoritative catalog source package;
- speculative media/preparation;
- decoded images;
- derived histograms/runway estimates;
- nonessential thumbnails when original remote media can be reacquired for future publication.

## Ephemeral coordination

Never persisted for correctness:
- Task handles/cancellation;
- active acquisition leases;
- active publication single-flight;
- scroll velocity/EWMA accumulator;
- current pressure state;
- in-flight image decode;
- transient retry scheduling;
- SessionStamp/publication admission token if it can be regenerated from durable state;
- MainActor presentation generation ordering.

# 8. Query inventory

No final indexes are selected here. The table describes required query shapes.

| Query | Frequency | Latency sensitivity | Expected cardinality | Ordering | Exact consistency? | Physical implication |
|---|---|---|---|---|---|---|
| Current eligible supply for context | Per publication/replenishment, not per frame | High (< tens of ms target) | Read bounded pool from 10^4–10^5 supply | Deterministic eligibility/base rank/keyset | Snapshot consistency sufficient | Small current-supply projection justified |
| Current revision for origins | Admission/publication/search | High | 1–hundreds | By OriginRecord ID | Yes at commit | Direct current pointer |
| Items belonging to Source | Source view/context selection | Medium-high | 10^2–10^4 retained | Usually authored/observed desc | Snapshot | Membership relation query |
| Items matching local content search | User initiated | High | FTS returns tens/hundreds from 10^4–10^5 | Relevance/newest deterministic | Snapshot | FTS only on current searchable projection |
| Catalog source search | User initiated | High | FTS over ~10^5 Sources | Relevance + stable tiebreak | Snapshot | Separate catalog FTS |
| Provider diversity inputs | Each selection composition | High | Candidate pool only (10^2 order) | None | Same candidate snapshot | Provider ID on hot projection or cheap secondary read |
| Cluster/entity relationships for candidates | Each selection composition | High | Sparse edges around bounded pool | Stable IDs | Same snapshot | Relation query must not expand whole graph |
| Published cards after/baround cursor | Scroll window shift | Very high | Tens/hundreds from potentially thousands | absolute publication ordinal | Yes for retained Edition | Range query over immutable history |
| Restore Edition/session | Launch/context return | Very high | 1 checkpoint + finite window | exact card/ordinal | Yes | One local transaction/snapshot; no selection/network |
| Exposure/history exclusion checks | Selection + UI overlays | High | Bounded history keys | Scope + recency | Policy-specific | Projection may be justified |
| Bookmark/read overlay | Presentation/selection | High | IDs in visible/candidate window | None | User authority | Query authority directly; no cross-DB mirror |
| Bookmark protection/snapshot | Retention + user surface | Correctness > latency | User bookmarks, usually small/medium | None | Yes | Same DB as retention decision |
| Acquisition target + checkpoint | Every acquisition operation/batch | High correctness | 1 target | generation/revision | Yes | Single snapshot/read before admission |
| External identity resolution | Admission | High throughput | One/few keys per observation | namespace/scope/value | Yes | Uniqueness + full-key collision verification |
| Media candidates for exact revision | Preparation | Medium-high | 0–few | connector-declared position | Snapshot | Revision-keyed query |
| Recent reusable Edition for ContextKey | Launch/context switch | High | Few editions/context | newest compatible | Yes | ContextKey + compatibility lookup |
| Retention candidates | Maintenance only | Low interaction sensitivity | potentially 10^4–10^5 | age/size/ordinal | Root snapshot must be exact | Run off presentation path in bounded chunks |

Legacy query-plan tests are strong evidence that candidate retrieval must bound examined rows, not merely LIMIT output rows. They test 10,000 and 100,000 selection_supply rows and require a primary-key seek rather than an unqualified scan.

# 9. Atomicity matrix

| Operation | Facts involved | Atomic requirement | Crash consequence if not atomic |
|---|---|---|---|
| Admit acquisition batch | Origin identity, revisions, memberships, relations, media/offers, current pointer, selection/FTS projection, receipt, checkpoint | One SQLite transaction when checkpoint represents the batch | Checkpoint may skip uncommitted content; partial canonical graph; stale projection |
| Revision becomes current | immutable revision + OriginRecord currentRevision + current supply/search projections | Same transaction | Selection/search disagree about current content |
| Revoke/disable target generation | target state/generation | Single durable update before stale result may commit | Old work can mutate new configuration |
| Publish segment | Edition tail/state, Segment, PublishedCards, frozen attribution/media refs | One transaction with tail/token/revision revalidation | Partial segment/history or late stale composition |
| Activate successor Edition | first usable successor history + active context pointer/state | Atomic visibility swap | Empty/half-built visible history |
| Bookmark desired state | bookmark state + durable snapshot/minimum subject identity + optional operation id | One transaction | Bookmark exists without survivable representation or vice versa |
| Collection membership | membership + operation/version if used | One transaction | UI/context selection disagrees after crash |
| Read state change | durable read state + operation/version if used | One transaction | Reopen can contradict user action |
| Exposure batch | exposure facts + derived history projection if both stored | Same transaction | Projection disagrees with facts |
| Session checkpoint | ContextKey + EditionID + PublicationCardID/anchor + revision compatibility info | One transaction | Cursor points outside retained/current edition |
| Asset materialization | verified temp bytes -> atomic rename; then DB metadata/ref | Cross-filesystem atomicity is impossible; use crash-safe ordering | Crash after rename produces orphan file (safe/collectable); DB must not require bytes for semantic history |
| Retention delete | candidates + protection roots + quota accounting | Candidate/root decision and DB deletions in same write snapshot | Deletes newly protected semantic state |
| Migration | schema + data transform | GRDB/SQLite migration transaction where possible; no erase fallback | Half-migrated semantic store |

# 10. Crash/failure semantics

Persistent-store failure is a product state, not permission to invent an empty store.

## Open/migration failure

- Do not create or switch to an in-memory substitute.
- If a safe read-only open is possible, runtime may enter degraded/read-only state.
- If the database cannot be safely read, feed mutation is blocked and the failure is explicit.
- Never erase/recreate runtime.sqlite automatically on schema mismatch.
- catalog.sqlite may be replaced/rebuilt because it is replaceable; runtime.sqlite may not.

## Disk full

- Existing committed publication/user state remains authoritative.
- New critical writes fail with a typed storage-full condition.
- Runtime may reclaim only explicitly reconstructible/bounded classes.
- It may then retry the original user/domain operation according to the owning operation, not through a generic infinite retry state machine.
- Never delete bookmarks, collections, read state or the active/checkpointed publication simply to make a write succeed.
- Asset bytes and connector evidence are early reclamation candidates.

## Database busy/locked

- Configure a bounded busy policy appropriate to iOS local use.
- Preserve the real error when the bound is exceeded.
- Do not convert lock/busy into empty results.
- Long maintenance must not monopolize the interaction database.

## Migration failure

- Migration is all-or-nothing where SQLite supports it.
- Pre-migration WAL-aware backup is appropriate for risky/destructive migrations.
- Failure leaves the previous durable file intact or the app blocked, never a fresh empty runtime.
- Unknown tables/data are not dropped simply because the current version does not recognize them.

## Checkpoint/WAL

- Checkpoint result must preserve SQLite's busy/log/checkpointed values.
- A busy checkpoint is not success.
- WAL checkpoint is maintenance, not semantic GC.

## Backup

- A runtime backup must use SQLite/GRDB backup semantics or a WAL-aware consistent copy.
- catalog.sqlite does not require semantic backup because it is replaceable.
- Asset bytes can follow their durability class; published identity remains in runtime.sqlite even when bytes are evicted.

Storage contract states:
- normal: read/write available;
- degraded: existing history readable, some nonessential writes/work suspended;
- read-only: durable state can be presented but mutation is refused;
- blocked: store cannot be trusted/opened; no fake first-launch state;
- recoverable: a specific reclaim/retry/reopen action is available without semantic deletion.

# 11. Retention and protection roots

Retention is part of database design because it determines which relationships may safely be deleted.

Principles:
1. Durable user state is never a child of reconstructible supply.
2. Published payload is self-contained enough that an OriginRevision may expire without rewriting a retained card.
3. Bookmark is self-contained enough that a whole FeedEdition does not need to be retained merely because one published card was saved.
4. Protection-root reads are fail-closed.
5. Protected rows are removed from quota candidate accounting before count/byte limits are applied.
6. No cascade from connector evidence/raw supply reaches publication or user state.
7. Identity anchors may outlive large content payloads when bounded/durable history still references the logical object.
8. Retention is budget/age/root-driven, not fixed page-count logic.

Protection roots:
- currently active Edition;
- every Edition named by a live SessionCursor/checkpoint;
- Editions retained as recent reusable ContextKey work under explicit policy;
- durable user objects only for their own snapshot/identity, not necessarily their source Edition;
- exact revision only if a still-live durable object truly needs the revision and did not freeze enough data;
- asset metadata referenced by retained publication;
- action state still needed by a retained published action.

Likely reclaim order under pressure:
1. decoded in-memory cache (not DB retention);
2. orphan/temp asset files;
3. speculative/unpublished media bytes;
4. connector evidence/raw payload;
5. old exposure detail/diagnostics according to history policy;
6. superseded unprotected Editions;
7. noncurrent unprotected OriginRevisions;
8. unprotected canonical payload/current supply according to local supply budgets;
9. published asset bytes whose card can render deterministically without them.

Never automatic-GC:
- bookmarks;
- collections/list membership;
- explicit preferences/source enablement;
- user-visible read state;
- the semantic snapshot necessary to show a saved item.

# 12. Warm-start persistence requirements

Minimum required for:

launch -> restore -> present local feed

## Required for presentation

- runtime.sqlite opens successfully;
- ContextKey of the restorable context;
- retained FeedEdition identity and its EditorialRevision identity;
- immutable PublishedCard payload/order for the local FeedWindow;
- SessionCursor/anchor naming a PublicationCard, not pixel offset;
- render contract/presentation inputs frozen by publication;
- published media identity;
- local asset bytes when retained, otherwise enough metadata for deterministic placeholder;
- user-state overlays that are visible on the card (bookmark/read) or a cheap local query for them.

No network, connector, fresh catalog, selection or image download is required.

## Useful for replenishment after first paint

- current OriginRecord/revision supply;
- selection_supply;
- canonical FTS;
- media preparation state;
- AcquisitionTarget/checkpoint;
- active catalog snapshot;
- recent context editions;
- bounded exposure/history projection.

These begin helping after presentation is already available.

## Not required for warm presentation

- connector raw evidence;
- remote catalog update;
- live source health;
- full historical revision chain;
- speculative assets;
- diagnostics;
- acquisition work already in progress before the last process died.

# 13. Context reuse persistence requirements

ContextKey is intentionally semantic and reusable. Persistence should exploit that without creating a new cache layer.

Natural reusable structures:
- retained Edition(s) keyed by ContextKey + EditorialRevision;
- per-context SessionCursor/checkpoint;
- canonical local supply shared across contexts;
- media preparation shared by exact OriginRevision/media identity;
- current selection/search projections shared across plans.

Recently prepared work that is worth persisting:
- published runway already committed as an Edition;
- session anchor for recent contexts;
- reusable prepared asset metadata/bytes under media budget.

Work that should not be persisted merely for reuse:
- SelectionEngine internal candidate arrays;
- current greedy-sequencer loop state;
- scroll velocity;
- RunwayEstimator memoization that is cheap to rebuild;
- Task/in-flight state;
- a separate ContextCache.

Context change:
1. mark new context as highest future-work priority;
2. try a compatible retained Edition for the new ContextKey;
3. otherwise use shared local supply to publish;
4. acquire only if local supply cannot satisfy the publication gate;
5. retain the previous context according to reuse/storage policy, not destroy it synchronously.

Compatibility is editorial, not visual. Render environment change rematerializes presentation without creating new history.

# 14. Search/indexing requirements

Two FTS indexes are justified because there are two different searchable corpora with different lifecycles:

1. catalog FTS in catalog.sqlite for Source/catalog discovery.
2. canonical content FTS in runtime.sqlite for current locally admitted content.

They should not be merged.

Canonical FTS requirements:
- index current selectable/current revision only;
- include headline/summary and a deliberate search projection;
- body text may participate when product search requires it, but full body indexing cost must be measured because 10^5 records can put text+FTS in the 10^8-byte class;
- superseded revisions do not remain in the hot FTS merely for historical completeness;
- search never decodes connector JSON/raw evidence;
- FTS projection is reconstructible from retained canonical current content;
- exact current revision switch and FTS update belong to the same admission transaction.

Catalog FTS remains replaceable with the catalog snapshot and may index title/description/tags/language/media/path as the old compiler already demonstrates.

Remote connector search, if ever added as a product feature, is a separate acquisition capability and must not silently replace local SearchContext semantics.

# 15. Catalog lifecycle analysis

Legacy evidence strongly supports a physically separate catalog.

Current legacy catalog facts:
- generated from 118 OPML files;
- 77,443 Sources;
- 6,450 nodes;
- 77,443 placements;
- approximately 118 MB SQLite snapshot;
- contains FTS;
- compiler writes a temporary database and atomically replaces the target;
- managed catalog updater stages a new snapshot and swaps current/backup directories.

The catalog is therefore:
- read-mostly;
- generated/shipped/managed;
- independently verifiable;
- replaceable as a file;
- substantially larger than the set of Sources an installation actively uses.

New Source semantics change one critical detail: SourceID must be FeedMine-owned and stable across catalog generations/endpoint changes. The old 32-bit hash of canonical URL must not be reused. The catalog build system must receive/preserve stable SourceIDs explicitly.

Recommended conceptual catalog contents:
- Source discovery metadata;
- Provider directory metadata used for discovery/attribution lookup;
- declarative shipped SourceBinding definitions;
- taxonomy/language/region/category descriptors;
- catalog placements/quality metadata;
- catalog FTS;
- CatalogGeneration.

Does not belong in replaceable catalog:
- user enabled/followed state;
- bookmarks;
- collections;
- acquisition checkpoints;
- target health;
- published history;
- user-created custom source state unless it is separately durable and cannot be rebuilt.

SourceBinding location:
- declarative shipped binding definition: catalog;
- runtime AcquisitionTarget/materialized operational configuration, generation stamp and checkpoint: runtime.

Catalog and runtime do not require cross-database atomic commit. EditorialRevision captures the catalog generation used to resolve a FeedPlan, and publication freezes attribution. A passive catalog replacement therefore cannot mutate visible history.

# 16. Runtime supply lifecycle analysis

Canonical runtime supply is bounded and mutable only in future-facing ways.

Lifecycle:
external observation
-> admission
-> OriginRecord identity resolution
-> immutable OriginRevision insert
-> membership/relation/media/offer facts
-> possible currentRevision change
-> current selection/search projection update
-> checkpoint advance
-> commit

Old AdmissionEngine proves the value of this atomic shape and real crash tests confirm checkpoint/content consistency after process termination.

Selection hot path:
- Do not rebuild a large normalized graph for every segment.
- Maintain a narrow reconstructible current-selection projection.
- Query a bounded keyset/window and then score/sequence a bounded candidate pool in memory.
- Old tests at 10k and 100k selection_supply rows show this shape can stay bounded and use a primary-key seek.

OriginRevision retention:
- current revision is retained while its record is active/current;
- exact revision may be protected by an operation in progress only until that operation revalidates/commits;
- retained publication does not require canonical revision payload because it freezes the published values;
- durable bookmark should not require canonical revision payload if its snapshot is complete;
- old revisions may therefore be removed under policy when no independent root requires them.

OriginRecord identity is different from OriginRevision payload. A minimal identity anchor may need to outlive evicted revisions while read/history/user-state still refers to the logical external object.

# 17. User-state lifecycle analysis

Legacy authority today:
- user.sqlite is canonical for bookmark identity and other user-owned state.
- feedmine.sqlite contains content and also legacy bookmark pin mirrors.
- Runtime V2 adds user_state_projection/user_list_membership mirrors so selection can see user state.

This is exactly the architecture that generated P-03/P-04/P-07/P-08/P-10/P-12 classes of failure.

Recommended new lifecycle:
- one authority in runtime.sqlite;
- user-state writes are transactions in that database;
- selection either reads the authority directly for the bounded candidate set or uses a reconstructible in-DB projection updated in the same transaction;
- no cross-database reconciliation worker;
- no content-table bookmark pin mirror.

Bookmarks:
- bookmark desired state is authoritative;
- bookmark stores a minimum durable semantic snapshot/subject identity sufficient to render a saved-item placeholder/card after supply eviction;
- snapshot and bookmark state commit atomically;
- bookmark deletion is explicit user action, not retention;
- bookmark need not pin the entire Edition or raw OriginRevision if its snapshot is sufficient.

Read/clicked/consumed:
- read/unread is user-visible state and should be durable independent of payload eviction;
- clicked/open history is user-visible when Last Clicked or similar surface exists, but can have an explicit bounded retention window;
- consumed/exposure history is operational and bounded;
- none of these should be columns on an evictable canonical content row.

Collections/smart feeds:
- explicit collection definitions and memberships are durable user state;
- materialized content membership may be reconstructible when definition-based, but explicit user filing is not;
- SmartFeed result caches are reconstructible and must not become authority.

# 18. Publication persistence analysis

Publication is the most important boundary to keep semantically clean.

Legacy PublicationRepository owns six primary publication/media tables and also performs:
- begin/discard Edition;
- append validation;
- token/epoch/revision/tail validation;
- Segment insert;
- PublishedCard insert;
- asset version/reference insert;
- media preparation upsert;
- successor activation/supersession;
- active/latest Edition reads;
- full restore;
- recent occurrence history;
- canonical content lookup;
- integrity report;
- orphan asset queries.

Why it grew: some of these are legitimately one atomic publication transaction, but storage mechanics, publication semantics, media persistence, restore mapping and diagnostics were concentrated in one repository.

New boundary resolution:

FeedMinePublication owns:
- what an Edition/Segment/Card means;
- whether a candidate is publishable;
- frozen text/attribution/action/media/render semantics;
- ordering;
- PublicationToken/epoch validity;
- single-flight and composition;
- successor rules.

FeedMinePersistence owns:
- the database transaction;
- serialization of already-frozen values;
- uniqueness/integrity constraints;
- range reads of retained history;
- durable active/superseded state;
- storage-level corruption errors.

Dependency-safe representation strategy:
- FeedMinePersistence may define concrete mechanical PublicationStore command/snapshot values.
- They contain scalar fields and FeedMineDomain identifiers only.
- They have no selection, sequencing, activation policy, rendering policy or editorial behavior.
- FeedMinePublication maps semantic PublishedCard/FeedSegment/FeedEdition to/from these mechanical values.
- Those values are private to the Publication/Persistence boundary and never become Runtime/UI models.
- No repository protocol is needed merely for testability; use one concrete store.

This resolves the Publication/Persistence boundary gate without adding Persistence -> Publication and without creating a parallel publication domain.

Required atomic publication commit:
- re-read exact Edition state/tail;
- validate expected publication token/revision;
- revalidate exact canonical revisions/eligibility needed by policy;
- append one Segment;
- append all frozen cards and durable media identities;
- update tail/activation state if appropriate;
- commit or change nothing.

PublishedCard should remain deliberately denormalized enough for a window read to be local and independent of canonical supply.

# 19. Database-boundary options

| Criterion | Option A: catalog + runtime + user | Option B: catalog + runtime incl. user | Option C: one feedmine.sqlite |
|---|---|---|---|
| Catalog atomic replacement | Excellent | Excellent | Poor; replacement would threaten runtime/user state |
| User-state safety | Physically isolated, but coordination fragile | Strong; same transaction as related runtime facts | Strong unless catalog rebuild/migration is mishandled |
| Bookmark + snapshot atomicity | Yes inside user DB, but runtime protection remains cross-DB | Yes, and retention sees same authority | Yes |
| Selection sees user state | Needs bridge/projection/reconciliation | Direct/in-DB projection | Direct |
| Retention roots | Cross-DB read/fail-closed complexity | Same DB snapshot | Same DB snapshot |
| Admission/publication atomicity | Good in runtime | Good in runtime | Good |
| Cross-database transactions | Frequent user/runtime coordination | Catalog only; no semantic cross-DB transaction required | None |
| Warm startup | Must open user + runtime | One semantic runtime open + optional catalog later | One large store; catalog can add open/migration coupling |
| Backup | User DB easy but runtime relationships split | One consistent semantic backup | Catalog bloat included unless special handling |
| Catalog rebuild risk | Isolated | Isolated | High |
| Migration risk | Three schemas + bridge evolution | Two schemas, no user bridge | One very large mixed-lifecycle schema |
| Complexity | Highest | Lowest justified | Superficially simple but mixes incompatible lifecycles |
| Testing | Cross-store failure matrix large | Smaller atomic tests | Catalog/runtime interaction tests become larger |
| Recommendation | Reject | RECOMMEND | Reject |

Option B is the simplest design that respects both lifecycle separation and atomic user/runtime semantics.

# 20. Technology options

## SQLite + GRDB

Recommendation: use.

Reasons:
- direct SQL/FTS5/query-plan control;
- exact transactions for admission/publication/user-state;
- DatabasePool supports concurrent readers and WAL-oriented use;
- foreign-key enforcement and migration tooling;
- typed exposure of SQLite errors/result codes;
- Swift 6 support in current GRDB generation;
- no need to invent a persistence abstraction over SQLite.

The new implementation should not blindly copy old RuntimeDatabase tuning. maximumReaderCount, busy timeout, checkpoint cadence and synchronous mode are measurements/configuration, not frozen architecture.

GRDB remains the simplest justified choice.

## Raw SQLite

Reject as default.

It would preserve all capabilities, but FeedMine would have to rebuild:
- connection serialization/pooling;
- statement/row mapping;
- migration framework;
- typed Swift error wrappers;
- safe concurrent access conventions;
- backup/checkpoint conveniences.

There is no concrete requirement that GRDB blocks, so raw SQLite would add code without simplifying product behavior.

## SwiftData

Reject for the runtime baseline.

SwiftData is a model-container/object persistence framework with managed schema/migration behavior. FeedMine needs precise control of:
- FTS5;
- bounded SQL query shapes and query plans;
- multi-table atomic admission/publication;
- WAL/checkpoint/failure semantics;
- explicit denormalized projections;
- retention deletes and root joins;
- SQLite result codes.

Using SwiftData would move critical behavior behind a higher-level persistence model while FeedMine still needs direct SQLite-level operations.

## Core Data

Reject for the runtime baseline.

Core Data is mature, but its object graph/change tracking/persistent-store abstraction is not solving FeedMine's main problem. Exact SQL/FTS/query-shape/retention control would become less direct, and FeedMine does not need identity/faulting/object-lifecycle machinery to model immutable revisions and append-only publication.

## Other wrappers

No realistic alternative currently provides a concrete simplification over GRDB for this workload. Re-evaluate only if a specific missing GRDB capability is found, not for framework variety.

# 21. Recommended direction

Freeze the following architecture before SQL:

Physical storage:
- catalog.sqlite
- runtime.sqlite including durable user state
- content-addressed asset filesystem

Technology:
- SQLite through GRDB.

Authority:
- catalog.sqlite is replaceable product/catalog authority for shipped source discovery metadata.
- runtime.sqlite is the non-replaceable authority for runtime facts and user state.
- actors are authority only for ephemeral coordination.
- asset filesystem stores bytes; runtime.sqlite stores durable asset identity/metadata.

Read models:
- normalized canonical facts remain authority;
- a small current selectable-supply projection is justified;
- current canonical content FTS is justified;
- catalog FTS remains separate;
- projections are reconstructible and updated atomically with their source fact when necessary.

Publication:
- immutable append-only history;
- self-contained frozen cards;
- mechanical Persistence representation, semantic Publication ownership;
- local range/window reads.

User state:
- no separate user.sqlite in the new architecture;
- no user-state bridge/projection between databases;
- bookmark + snapshot atomic;
- read/history survives canonical payload eviction according to its own durability class.

Failure:
- no silent fallback;
- no automatic erase/rebuild of runtime.sqlite;
- disk-full path sheds reconstructible data before semantic state;
- root failures fail closed.

Quality gate:

Do we now know enough to design the database? YES.

Decisions that can be frozen before SQL are listed in section 24.

# 22. Explicitly rejected directions

- Copying FeedStorage schema/code from FeedMine legacy.
- Recreating FeedStore responsibilities in a new Persistence service.
- Three SQLite databases merely because old architecture had catalog/runtime/user.
- Storing durable user state on canonical content rows.
- Cross-database bookmark pins or user-state mirrors.
- Silent in-memory fallback on open/migration failure.
- Auto-erasing runtime DB when schema changes.
- Treating catalog.sqlite as mutable user state.
- One giant SQLite database containing the replaceable 118 MB catalog and non-replaceable user/runtime facts.
- SwiftData/Core Data as the main runtime persistence layer.
- Raw SQLite without a concrete GRDB blocker.
- Indexing all historical OriginRevisions in hot FTS.
- Persisting ContextCache/RunwayEstimator/selection candidate arrays.
- Retaining an entire Edition only because a bookmark lacks its own snapshot.
- Fixed-card-count retention or runway policy.
- Time-based weekly VACUUM as architectural maintenance.
- PublicationStore inventing a second PublishedCard/FeedEdition semantic model.
- Persistence depending on FeedMinePublication.
- Protocol JSON/raw evidence in selection/publication/presentation hot paths.
- URL-derived SourceID.
- Retention fail-open behavior when bookmark/user-state roots cannot be read.

# 23. Open questions

These questions do not block database architecture, but should be answered while converting conceptual groups into schema.

1. Stable catalog SourceID assignment: where is the durable explicit SourceID authored so rebuilds across catalog generations preserve identity without URL-derived hashing?
2. User-created/imported Source storage: exact relationship between a catalog Source and a user-owned custom Source when the same external principal is discovered later.
3. Read-state subject key: whether durable read state references retained OriginRecord identity, a stable external subject identity, or a dedicated storage subject key.
4. Click/Last Clicked retention: exact user-visible history horizon and whether explicit user actions can pin entries.
5. Exposure detail retention: how long raw dwell/viewport facts remain after a compact projection is sufficient.
6. Body FTS: whether full bodyText is required or searchProjection can cap/index a deliberate subset.
7. Connector evidence retention: per-connector diagnostic/replay needs and byte ceilings.
8. Exact recent-context reuse policy: budget/recency/usefulness inputs, without turning a number into the architecture.
9. Published asset byte retention: when a retained card may fall back from exact bytes to deterministic placeholder.
10. Action handle durability: which published interactions require long-lived opaque connector state.
11. Backup product contract: whether the app needs user-visible export/restore beyond crash-safe local durability.
12. Migration/import scope from legacy FeedMine: which user-owned objects need one-time import and which old caches/history can be discarded.
13. Busy-timeout/checkpoint tuning: measured values after real iOS workload tests.
14. Whether a history projection is worth storing or querying bounded facts directly is sufficient for initial release.
15. Whether old noncurrent OriginRevisions need any audit/replay window beyond roots and connector-specific evidence policy.

# 24. Decisions safe to freeze now

1. Two SQLite databases: catalog.sqlite + runtime.sqlite; user state is inside runtime.sqlite.
2. Asset bytes are outside SQLite in a content-addressed filesystem.
3. SQLite is the storage engine.
4. GRDB is the Swift persistence library unless a concrete blocker appears.
5. Runtime uses WAL and foreign keys.
6. RuntimeDatabase never silently falls back to memory.
7. Runtime schema changes never use erase-on-change behavior.
8. catalog.sqlite is replaceable; runtime.sqlite is not.
9. Durable user state never depends on evictable canonical payload for semantic survival.
10. Bookmark writes include their survivable snapshot/subject identity atomically.
11. Read state is independent of canonical content rows.
12. Admission content + represented checkpoint progress is one transaction.
13. OriginRevision is immutable; current revision is future-facing.
14. Current selection projection is reconstructible, not authoritative.
15. Canonical content FTS indexes current/searchable supply, not the whole revision history.
16. Catalog FTS is separate from runtime content FTS.
17. Publication is append-only and immutable after commit.
18. Retained PublishedCard is self-contained enough to survive raw/canonical revision eviction.
19. FeedMinePublication owns publication semantics; Persistence owns storage mechanics.
20. Publication/Persistence uses concrete mechanical storage values, not a parallel semantic domain and not a repository-protocol hierarchy.
21. Session restore identifies ContextKey + Edition + PublicationCard/anchor, not pixel offsets.
22. Context reuse uses persisted Edition/supply/media/checkpoint structures; no ContextCache.
23. Retention root reads fail closed.
24. Protected objects are removed from retention quota candidate counts before limits.
25. Actors/tasks/caches are never correctness authorities.
26. No protocol-specific payload is decoded after admission for Selection/Publication/Presentation.
27. SourceID is FeedMine-owned and stable across endpoint/catalog changes; old URL hash identity is rejected.
28. Heavy maintenance cannot run as a blanket interaction-blocking timer job.

# 25. Decisions that must remain open

Do not freeze yet:
- final tables;
- final column names/types;
- final indexes;
- foreign-key graph details;
- exact user-state subject key representation;
- exact storage representation of external opaque identities;
- exact publication mechanical DTO fields;
- exact denormalization level of PublishedCard storage;
- exact retention durations/byte budgets/counts;
- exact number of retained recent contexts;
- exact candidate window/pool values;
- exact DatabasePool reader count;
- exact busy timeout;
- exact WAL checkpoint cadence/mode;
- exact FTS tokenizer/column set/body policy;
- exact backup cadence/product UX;
- exact asset byte budgets;
- exact exposure projection strategy;
- exact legacy import mechanics.

These choices need schema-level design or measurement, not architectural speculation.

# 26. Proposed implementation sequence

Each slice should have one owner, one responsibility and invariant tests. Do not implement the next slice by adding a parallel path.

Persistence 1 — physical lifecycle and failure contract
- Add GRDB.
- Implement catalog/runtime opening boundary.
- RuntimeDatabase: WAL, foreign keys, typed storage errors, migrations, no erase/fallback.
- Add open/reopen/disk-full/busy/migration/checkpoint tests.
- No domain tables beyond migration metadata needed to prove lifecycle.

Persistence 2 — durable user-state authority
- Define the user-state storage concepts required by current product: bookmark, snapshot/subject identity, read state, explicit collection membership/preferences.
- Keep all in runtime.sqlite.
- Prove bookmark survives canonical content deletion.
- No bridge/mirror.

Persistence 3 — canonical identity/revision + admission transaction
- Persist Source/runtime binding references needed operationally, OriginRecord identity anchors, immutable OriginRevision and canonical relations.
- Implement target/checkpoint.
- Commit admission + checkpoint atomically.
- Prove stale generation/checkpoint cannot mutate supply and crash cannot advance checkpoint past content.

Persistence 4 — current supply/search read models
- Add reconstructible current selection projection.
- Add current canonical FTS.
- Prove rebuildability and bounded candidate query plans at 10^4–10^5 rows.
- Do not optimize beyond measured query needs.

Persistence 5 — catalog integration
- Implement catalog.sqlite reader lifecycle and CatalogGeneration.
- Resolve stable SourceID authoring.
- Keep user enablement out of catalog.
- Prove catalog replacement does not invalidate runtime/user state or retained publication.

Persistence 6 — publication storage boundary
- Implement the mechanical PublicationStore representation selected in section 18.
- Keep FeedMinePublication semantic models and rules as sole owner.
- Atomic Edition/Segment/PublishedCard commit and successor activation.
- Prove restore without canonical supply/network.

Persistence 7 — session restore and context reuse
- Persist ContextKey/Edition/card anchor checkpoints.
- Restore local window.
- Keep recent context publications reusable through retention policy, without a separate cache.

Persistence 8 — media asset durability
- Content-addressed files.
- Temp -> verify -> atomic rename -> DB metadata.
- Published media identity survives byte eviction.
- Prove orphan cleanup and deterministic placeholder behavior.

Persistence 9 — exposure/history
- Persist only facts/projections required by current policy.
- Batch noncritical writes.
- Keep read/clicked/consumed lifecycle explicit and independent from canonical payload.

Persistence 10 — retention
- Implement durability-class GC from the new relationships, not the legacy coordinator.
- Fail closed on roots.
- Exercise disk pressure, protected editions, bookmarks, identity anchors, connector evidence and assets.
- No weekly blanket VACUUM timer.

Persistence 11 — legacy import
- Only after new authorities are stable.
- Import durable user-owned data that must survive migration.
- Treat legacy feed/cache/runtime rows as migration evidence, not architecture.
- Remove migration code after compatibility window where practical.

No production implementation should start from copying FeedStorage. The schema design that follows this discovery should translate these facts, query shapes, atomic boundaries and lifecycles into the smallest relational representation that satisfies them.
