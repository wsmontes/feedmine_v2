# Canonical local supply design — Phase 3A

## 1. Scope

Phase 3A closed this design contract. Phase 3B1 is complete with the approved schema through canonical-supply-v1, registered after publication-restore-v1. Phase 3B2 implements atomic ContentStore changes and exact canonical reads. Phase 3B3 is complete with bounded canonical candidate windows and scale/query-plan evidence. CandidateProvider, Selection, AdmissionPolicy and network acquisition remain deferred. The existing publication/session vertical slice is complete through Phase 2I: retained publication → restore → current actor-owned presentation → memory-local viewport movement → explicit logical checkpoint milestone.

The next local path is canonical supply → Editorial CandidateProvider → SelectionEngine → PublicationCoordinator → immutable Edition/Segment. This design concerns the first storage boundary only. Its baseline adds exactly four domain tables to runtime.sqlite: origin_records, origin_revisions, source_memberships and selection_supply. The existing publication/session tables and GRDB migration bookkeeping remain unchanged. Indexes and constraints are not additional domain tables. No fifth table is necessary for the invariants below; a demonstrated need for one must be reported as a blocker before implementation.

## 2. Legacy evidence: keep/reject

Read-only evidence: wsmontes/feedmine-dev, branch fix/release-1.0-final-hardening, inspected commit 712a6ba93c6a8ab28c3b3c0e2b2777d1e3341d0c. Paths below are relative to Packages/FeedRuntimeV2. These are observations of the old implementation, not code or schema imported into the new repository.

| Evidence | Behavior retained | Mechanisms rejected |
| --- | --- | --- |
| Sources/FeedStorage/Admission/AdmissionEngine.swift | One canonical commit is transactional; revision insertion, current-pointer movement and supply refresh occur within the same write. Checkpoint progress eventually belongs in the transaction admitting what it represents. | Large admission engine, AcquisitionTarget, ledger, batch fingerprint, receipts, evidence storage and runtime generations. |
| Tests/FeedStorageTests/AdmissionTests.swift | Historical-only revisions do not replace current; advancing current does not overwrite previous payload; version collisions are not overwritten; failure after revision insertion rolls back durable effects, including after reopen. | Integer identities, payload digests as identity authority and connector-specific instructions. |
| Sources/FeedStorage/Selection/SelectionSupplyRepository.swift | A key window is fixed before eligibility; unavailable origins are excluded; candidate reads use canonical data without decoding protocol/raw evidence. | Legacy SupplyCandidate DTO, source/provider tables, media/relation expansion, user-state and compatibility projections. |
| Tests/FeedStorageTests/SelectionSupplyRepositoryTests.swift | Keyset walks do not repeat rows in unchanged supply; examined rows are bounded; source membership controls eligibility; fallback sort time is explicitly identified; connector evidence does not affect the read. | Legacy source enablement policy, external stable-key scheme and fixed request defaults. |
| Sources/FeedStorage/Selection/CanonicalSearchRepository.swift and Tests/FeedStorageTests/CanonicalSearchRepositoryTests.swift | Search follows current revisions and forgets superseded hot text; canonical reads need no connector evidence. | FTS implementation, compatibility maps, URL-derived source identity, default result/excerpt constants and media joins. |
| Tests/FeedStorageTests/SelectionQueryPlanTests.swift, additionally inspected for scale evidence | 10,000/100,000-row fixtures require a supply key seek and report examined rows; biased supply and a dominant prefix do not justify scanning all supply. | Old integer-primary-key access path, scan-budget constants and exponential scan policy. |

The new Domain was reread in Content.swift and Source.swift. Persistence Discovery supplies topology, scale and authority context; Persistence Design supplies existing coding/lifecycle rules. Earlier discovery's broader prospective schema is not the baseline migration authorization: this narrower four-table consumer gate takes precedence for Phase 3B.

## 3. Canonical authority model

OriginRecord + its immutable current OriginRevision + SourceMemberships are canonical authority. OriginRecord is the FeedMine-owned identity anchor for an external object. Its current pointer describes future candidate supply, never previously published history. Revision payloads remain immutable whether current or historical.

selection_supply is a reconstructible hot local read model, with exactly one row for each structurally selectable origin. It is not a parallel cache authority. Rebuilding it from retained canonical facts restores the same projection; correctness never depends on a reconciliation worker. Normal canonical writes refresh affected projections in the same transaction.

For this baseline, structural selectability means: availability is available or updated, currentRevisionID is non-null and valid, and at least one membership exists. Both direct and derived memberships qualify; further Editorial policy is not invented here. removed, revoked and unknown are explicitly non-selectable. An available origin without a current revision or without membership remains canonical but has no supply row. Unknown does not silently mean available.

## 4. Baseline schema graph

```text
origin_records.id ← origin_revisions.origin_record_id
origin_records.(id, current_revision_id)
    → origin_revisions.(origin_record_id, id) [nullable current pointer]
origin_records.id ← source_memberships.origin_record_id
origin_revisions.(origin_record_id, id)
    ← selection_supply.(origin_record_id, origin_revision_id)
```

All four tables live in runtime.sqlite. No physical foreign key targets catalog.sqlite, Source or Provider tables. SourceID and ProviderID are opaque Domain IDs. There is no canonical-payload FK added to existing published_cards: frozen publication payload does not require canonical retention.

Every required ID/text field below is NOT NULL unless marked optional. Enum values use Domain raw strings with the explicitly listed CHECK constraints. Foreign keys use ON UPDATE NO ACTION and ON DELETE NO ACTION, immediate unless explicitly stated otherwise. Child access paths described below are indexed.

## 5. origin_records

| Column | Representation and responsibility |
| --- | --- |
| id | UUID TEXT primary key, OriginRecordID. |
| object_connector_kind | Exact ConnectorKind.rawValue TEXT; open vocabulary. |
| object_namespace | Exact external namespace TEXT. |
| object_value | Exact external value TEXT. |
| object_role | TEXT constrained to 'object'. |
| current_revision_id | Optional UUID TEXT, OriginRevisionID. |
| availability | TEXT constrained to available/updated/removed/revoked/unknown. |
| first_observed_at | Finite Unix REAL, immutable initial observation time. |
| last_observed_at | Finite Unix REAL, supplied accepted observation time. |

UNIQUE(object_connector_kind, object_namespace, object_value, object_role), with BINARY collation on all external identity text. OriginRecord requires role .object in this accepted storage slice even though Domain's general ExternalIdentity initializer permits other roles. Principal/alias/lookup identities are not silently converted into objects.

Same external tuple resolves the existing FeedMine ID. A caller supplying a different ID for that tuple, or changing the external tuple of an existing ID, must receive an identity conflict, never REPLACE or silent reassignment. No URL, hash, case-folding or trim is an identity authority.

Only current_revision_id, availability and last_observed_at may change for an existing record through the atomic command. first_observed_at and external identity remain unchanged. The store accepts finite supplied dates; it does not manufacture a clock or upstream precedence policy. A new record is inserted with a null current pointer before inserting its revision.

## 6. origin_revisions

| Column | Representation |
| --- | --- |
| id | UUID TEXT primary key, OriginRevisionID. |
| origin_record_id | UUID TEXT, immediate FK to origin_records(id). |
| version_connector_kind | Optional exact TEXT. |
| version_namespace | Optional exact TEXT. |
| version_value | Optional exact TEXT. |
| version_role | Optional TEXT; when present constrained to 'version'. |
| headline | Optional TEXT. |
| summary | Optional TEXT. |
| body_text | Optional TEXT. |
| authored_at | Optional finite Unix REAL. |
| modified_at | Optional finite Unix REAL. |
| observed_at | Required finite Unix REAL, FeedMine observation time. |
| language | Optional TEXT. |
| primary_link | Optional TEXT preserving accepted URL.absoluteString. |
| search_projection | Optional TEXT preserving the accepted Domain value; no FTS table. |
| provider_id | Optional UUID TEXT, opaque ProviderID with no catalog FK. |

The four version identity columns are either all null or all non-null, enforced with a CHECK. A present version has role .version; accepted-write validation checks its connector matches the owning record's connector. No version is synthesized when upstream supplies none.

UNIQUE(origin_record_id, id) supports the current-pointer composite FK and ordered per-origin history lookup. A partial unique index on (origin_record_id, version_connector_kind, version_namespace, version_value, version_role), restricted to a present version, resolves versions within their owning object. Version identifiers may be reused by different objects; they are not global identities. BINARY equality preserves the exact tuple. Unversioned revisions are distinguished by their supplied FeedMine UUID; no dedup hash or invented revision ordinal is added.

Same RevisionID with any different field, including observation time, is conflict/corruption. Exact existing ID/value may be accepted as an unchanged revision. A present version tuple already bound to another RevisionID must resolve to its existing ID before the write, or fail as a conflict; no payload overwrite is permitted. Comparison covers every nullable/scalar Domain field, with nil and empty text distinct. No public mutation/update API for revision payload exists; use insertion and exact read, not UPDATE or INSERT OR REPLACE. Changed accepted content needs a new revision identity. Historical insertion alone does not move current.

## 7. source_memberships

| Column | Representation |
| --- | --- |
| origin_record_id | UUID TEXT, FK to origin_records(id). |
| source_id | UUID TEXT, opaque SourceID. |
| membership_kind | TEXT constrained to direct/derived. |
| first_observed_at | Finite Unix REAL. |
| last_observed_at | Finite Unix REAL. |

PRIMARY KEY(origin_record_id, source_id). This baseline stores one current membership relationship per origin/source pair; kind describes that relationship, not parallel provenance entries. A valid canonical command may change kind or last observation, add or explicitly remove a membership. It preserves the pair's initial observation while that relationship remains. Removing/readding a relationship may supply a new first observation; membership event history is outside this slice.

The primary key supports existence checks and deterministic membership reads by origin and source. No Source metadata, endpoint, binding, enablement flag or acquisition provenance is stored. Multiple Sources can include the same OriginRecord without duplicating the origin or its revision. Source display data and enablement come from their future owners; the caller's optional SourceID constraint expresses current query eligibility.

## 8. selection_supply

The smallest baseline projection has four columns:

| Column | Query justification |
| --- | --- |
| origin_record_id | UUID TEXT primary key; at most one hot row per origin. |
| origin_revision_id | UUID TEXT; exact current payload lookup without loading history. |
| sort_date | Finite Unix REAL; indexed deterministic candidate traversal. |
| sort_date_basis | TEXT constrained to authored/observedFallback; preserves fallback meaning. |

Composite FK(origin_record_id, origin_revision_id) references origin_revisions(origin_record_id, id). The commit command additionally verifies this revision equals origin_records.current_revision_id and the origin satisfies structural selectability before installing the row. The same-origin FK alone does not prove currentness; atomic refresh and its assertions own that requirement.

Supply ordering index: (sort_date DESC, origin_record_id DESC), using canonical UUID TEXT BINARY ordering as the unique tiebreaker. This order is deterministic; UUID order is not claimed to be chronological. The only duplicated payload scalar is sort_date, necessary to seek this ordering without sorting all revision rows. sort_date_basis is necessary to distinguish a fallback from authorship. No SourceID arrays/blob or duplicated source/provider display data are included. Headline, summary, language and ProviderID can be point-read from the at-most-window current revisions after eligibility. bodyText, searchProjection and the entire revision graph are not loaded for candidate discovery.

Storage/query baseline: sort_date is authored_at when present, otherwise observed_at. sort_date_basis states authored or observedFallback accordingly. authored_at remains null when unknown. This is a documented baseline read ordering, not Selection ranking or a false authorship claim; changing that baseline later requires explicit projection rebuild/design review. No policy engine or additional version counter is implemented in this phase.

Pointer/availability/membership changes refresh the affected row even if the recomputed row is unchanged. Losing the last qualifying membership removes it; gaining membership may create it. removed/revoked/unknown deletes the projection in the same commit. Old revisions remain untouched.

## 9. Identity and representation rules

Reuse the existing PersistenceValueCoding convention: UUID-backed IDs are canonical lowercase UUID TEXT; dates are finite Unix REAL; any future ordered UInt64 must fit checked SQLite INTEGER. These four tables need no new ordered counter. Reject malformed/non-finite representations rather than silently normalizing or falling back.

External identity equality is the structural connector kind + namespace + value + role tuple. Preserve case, whitespace, URL spelling and namespace/value bytes accepted by Domain/the future admission boundary. ConnectorKind is an open string, not a hard-coded connector enum. Content remains structured columns, never canonical_payload JSON, revision_blob, attributes or metadata JSON.

Optional SourceID/ProviderID lookup failure cannot make the runtime IDs unreadable. Source/provider tables and cross-database FKs are absent. Future publication attribution may be nil without a display directory. FeedMine-owned SourceID is never derived from a URL, catalog row or hash.

## 10. Current-revision integrity

Proposed relational constraint in origin_records:

```sql
FOREIGN KEY (id, current_revision_id)
REFERENCES origin_revisions (origin_record_id, id)
ON UPDATE NO ACTION ON DELETE NO ACTION
```

The parent pair is explicitly UNIQUE in origin_revisions, with matching collation. A null current_revision_id permits initial record insertion; a non-null pointer must reference that same origin. Insert the record with null pointer, then its immutable revision, then move current. Accidental deletion of a current revision fails. These composite-key/null semantics follow [SQLite foreign-key documentation](https://www.sqlite.org/foreignkeys.html).

No automatic cascades, SET NULL or REPLACE encode retention. Deleting an origin with revisions or memberships fails. Future deletion must explicitly remove its supply row and memberships, clear/change its current pointer, remove eligible revisions, then remove the anchor only if future retention rules permit. No delete/retention command is implemented in this slice.

## 11. Atomic canonical commit

One concrete ContentStore write command, inside one RuntimeDatabase write transaction:

1. Resolve and validate exact FeedMine/external identities and the supplied expected current pointer for existing records, including explicit expected nil. Reject conflicts before committing any change.
2. Insert a new OriginRecord with null current pointer, or validate immutable fields of an existing record.
3. Insert the new immutable OriginRevision, or validate an exact existing revision; reject identity/payload/version conflicts.
4. Apply explicit membership additions, changes and removals.
5. Move current to the explicitly requested revision if appropriate, and apply accepted availability/last-observation updates. The request distinguishes historical-only insertion from setting/clearing current; storage does not infer upstream freshness from timestamps.
6. Refresh selection_supply for the affected origin from the transaction's canonical facts. Assert same-origin/current pointer and eligibility, and compute the documented sort pair.
7. Commit, or throw and roll back everything.

An expected-pointer mismatch rejects the whole command rather than committing an unintended partial update. The caller may explicitly request no pointer change for a historical revision. Multi-origin command support and upstream precedence policy are not required by the first one-origin slice.

Projection refresh is part of the write, not deferred worker work. Lost projection may be explicitly rebuilt from authority in a controlled atomic maintenance transaction; this design does not add a scheduler. Database failure propagates under the existing factual Persistence error contract.

AcquisitionTarget, connector checkpoint, receipt, raw evidence and batch fingerprint are excluded. Future Acquisition must encompass this canonical mutation in its wider transaction so a checkpoint never advances beyond admitted semantic content. The store's internal canonical-write helper must permit that future shared transaction without nested independent commits; no external transaction API or Acquisition schema is added now.

## 12. Bounded candidate query

Inputs: optional one SourceID eligibility constraint, optional exclusive deterministic cursor (sort_date, origin_record_id), and a caller-supplied positive examined capacity W. No default page size or fixed product count. Invalid capacity or cursor representation throws.

Within one read snapshot, first seek the ordering index and fetch at most W supply keys, before filtering by Source. Illustrative query shape, not executable migration code:

```sql
SELECT origin_record_id, origin_revision_id, sort_date, sort_date_basis
FROM selection_supply
WHERE (sort_date, origin_record_id) < (:after_date, :after_origin)
ORDER BY sort_date DESC, origin_record_id DESC
LIMIT :examined_capacity;
```

The first-window variant omits the cursor predicate. The tuple is exclusive in the descending order; [SQLite row-value documentation](https://www.sqlite.org/rowvalue.html) describes lexicographic comparisons. The implementation gate must verify an ordering-index seek and absence of an unbounded sort/scan for subsequent windows; it must not assume a query plan from the SQL's appearance.

For each bounded window key, Source eligibility uses an indexed EXISTS point lookup in source_memberships on (origin_record_id, source_id). With no Source constraint, structural membership is already guaranteed by supply refresh; a defensive existence check can seek the origin prefix and stop at the first membership. Do not join a whole Source membership set before LIMIT. Do not expand all memberships of each candidate in this hot read. If one membership ID is needed, the requested Source or first SourceID in primary-key order can be returned with an indexed single-row lookup; Editorial still owns its meaning.

After eligibility, point-read only needed candidate scalars from the indexed current revisions. CandidateWindow reports eligible narrow records, examinedCount (pre-filter window count), and nextCursor from the LAST EXAMINED row, including when no candidate passed. Fewer than W examined rows means the snapshot was exhausted; exactly W may require a subsequent empty window to confirm exhaustion. Never advance from only the last returned candidate, drop eligible rows to another result cap, or implicitly refill a sparse window.

This bounds visited supply entries by W and membership/revision probes by a constant multiple of W, plus index seeks; it does not promise constant B-tree depth, payload bytes or wall-clock latency. Single indexed existence probes avoid unbounded membership fanout. Exact memberships(originRecordID:) is a separate explicit graph read, not the candidate path. CandidateProvider must also bound cumulative examined work if it requests multiple windows; an unlimited refill loop defeats the contract. Text byte budgets await a concrete consumer, rather than claiming W bounds arbitrarily large text.

No OFFSET, load-all-supply read, filtered LIMIT that searches indefinitely for matches, or raw connector decoding is proposed. Rare-source windows may be empty and still have a progress cursor. Source filtering uses memberships only, never SourceID arrays in supply.

All steps of one window share a read snapshot. Ordering/current supply can change between calls; cursors are seek positions, not a cross-call frozen supply guarantee. A future consumer requiring a consistent multi-window selection must perform those bounded reads under one scoped read snapshot. No generation counter or scheduler is introduced.

Phase 3B query verification must use 10k/100k fixtures, ties, sparse Source matches, high membership fanout, noncurrent revisions and biased supply. Measure examined entries and execution plans; a small result array or fast timing alone is insufficient. Those sizes are test evidence, not production window constants.

## 13. Persistence ↔ Editorial boundary

Future ContentStore is a concrete mechanical storage type, not a protocol hierarchy or second canonical Domain. Its smallest operations are conceptually:

- commitCanonicalChange: atomic accepted facts, explicit membership changes and current-pointer instruction, with factual conflict/failure reporting.
- originRecord(id:), originRevision(id:): exact accepted facts; missing is nil, malformed/unreadable throws.
- currentRevision(originRecordID:): exact same-origin current revision, optional when no record/current pointer; inconsistent state throws.
- memberships(originRecordID:): explicit relationships in deterministic SourceID order.
- candidateWindow: bounded current-supply read as defined above, with examined count and progress cursor.

Names may adapt to existing conventions; exact read, atomic write and bounded current query are fixed responsibilities. No generic CRUD, public revision-update API or broad repository facade. Persistence returns Domain values where they already exist or narrow mechanical records/cursor metadata; it does not create another canonical content semantics layer.

FeedMineEditorial.CandidateProvider will consume ContentStore/mechanical canonical reads and construct Editorial Candidate values. SelectionEngine never receives Persistence rows. Persistence owns mechanics; Editorial owns eligibility/ranking/Candidate semantics. Catalog lookup, clustering, media preparation and network are not implicit candidate retrieval steps.

## 14. Failure behavior

| Scenario | Required outcome |
| --- | --- |
| Crash/throw before canonical commit | No partial record, revision, membership, pointer or projection mutation survives reopen. |
| Revision inserted, pointer update fails | Whole write rolls back, including the revision insertion. |
| Pointer names another origin's revision | Composite FK rejects; write rolls back. |
| Same RevisionID with different payload | Conflict/corruption; no overwrite or successful partial commit. |
| Present external version tuple conflicts | Existing revision must be resolved exactly or command fails. |
| Expected current pointer is stale | Whole command rejected; no silent pointer movement. |
| removed/revoked/unknown | Supply row disappears atomically with availability update. |
| Last membership removed | Supply row disappears in the same transaction. |
| Projection refresh fails | Canonical transaction rolls back. |
| Catalog/display directory unavailable | IDs and canonical rows remain readable; display attribution may be absent. |
| Current advances V1 → V2 | V1 stays immutable historical payload; hot supply points to V2 only. |
| Current revision accidentally deleted | FK prevents deletion; no automatic fallback. |
| Query/storage failure | Throw; never report an empty successful candidate window. |

## 15. Retention implications

Retention implementation and columns are deferred. Old noncurrent revision payloads are generally reclaimable later when future roots allow it. OriginRecord identity anchors can outlive payloads. PublishedCard freezes its presentable payload, so retained publication does not require retaining canonical V1 or depend on canonical deletion cascades. No retention priority, protection, pins, expiry, last-access timestamp or bookmark pin is added here. Future retention uses explicit deletes in explicit order, with its own reviewed roots and failure contract.

## 16. Explicitly deferred schema

No baseline sources, providers or source_bindings table; catalog has its separate lifecycle and user-created Source durability requires its own consumer slice. No content_relations, content_entities or content_clusters; first local retrieval does not yet consume reply/repost/clustering semantics. No media_candidates or interaction_offers. No bookmarks/read/opened/consumed/collections or legacy user-state projections. No AcquisitionTarget/checkpoint/batch/evidence/fingerprint/ledger tables. No runtime generation table.

Canonical FTS is justified for future SearchContext but absent from Phase 3B. When introduced, index only current selectable/current revision text, update it atomically with canonical current state, and do not keep historical revisions in hot FTS merely for completeness. Retaining searchProjection in the revision preserves the existing Domain fact without adding an index now.

No content JSON blob, compatibility/import table, connector parsing, network, automatic maintenance or retention columns. None of the deferred Domain types forces a table before a concrete consumer exists.

## 17. Phase 3B implementation gate

Phase 3B1 implements exactly the four domain tables and the stated schema constraints/access paths. CanonicalSupplySchemaTests verify migration/reopen, exact object uniqueness, complete version identities and per-origin version uniqueness, membership/sort enums, same-origin current/supply foreign keys and current-revision deletion protection. PublicationSchemaTests now protect the four Publication tables without assuming they are the entire runtime schema. No currentness trigger was introduced by 3B1. Phase 3B2 is complete: ContentStore validates exact identities and expected-current state, preserves immutable revisions, and updates membership/current/availability/supply in one transaction. ContentStoreTests cover exact reads after close/reopen, historical-only revisions, replay/conflicts, availability/membership/current transitions and real INSERT/UPDATE projection-trigger rollback after reopen. The shared scalar codec now has neutral errors, translated by each store; PublicationStore behavior and SessionStore remain unchanged. Phase 3B3 is complete: functional candidate-window tests and scale/query-plan tests prove the bounded Persistence read path. The broader implementation gate is recorded below:

1. Create UUID OriginRecord R, immutable V1, membership R → S, make V1 current, close/reopen, and find exactly R/V1 through a bounded local query without catalog/network.
2. Insert V2 and move current explicitly. Query yields R/V2; exact V1 read remains unchanged. Existing frozen publication referencing V1 remains untouched.
3. Reject foreign-origin current pointers, mutation of an existing RevisionID, structural identity conflicts, partial version tuples and invalid representations. Missing optional text/date/ProviderID stays missing.
4. Roll back revision/pointer/membership/projection effects on real mid-write failure and after reopen. Test availability and membership transitions against supply in the same transaction.
5. Prove reconstructible projection equals authority; no worker is needed for normal correctness.
6. Prove indexed keyset examined-work bounds with 10k/100k rows, ties and selective Source constraints. Bounded-window accounting must include rejected entries, and the cursor must progress across empty eligible results.
7. Preserve the existing publication/session vertical slice and Persistence conventions, with no new catalog FK or changes to existing Domain/publication identities.

If any invariant requires a fifth domain table or an unbounded hot query, stop and report the blocker; do not expand the baseline by convenience. ContentStore/CandidateProvider implementation, network admission, FTS, relations, media, retention and user state remain outside Phase 3B1.

### Phase 3B3 closure evidence

Phase 3B1 — schema complete. Phase 3B2 — atomic ContentStore + exact reads complete. Phase 3B3 — bounded candidate window complete, through functional 3B3A and scale/query-plan proof 3B3B.

ContentStoreCandidateWindowScaleTests populate real migrated SQLite tables directly in one writer transaction with prepared statements and foreign keys enabled. The 10k/100k populations are evidence sizes, not product limits. Tests cover small caller-supplied capacities, deterministic UUID/date ties, exclusive keyset progress, middle/tail windows, a three-membership Source behind a large unmatched prefix, high membership fanout and historical revision volume. Source sparsity does not provoke refill scanning; an empty eligible batch still advances from the last examined row.

EXPLAIN QUERY PLAN confirms first-window ordering and keyset range/seek use selection_supply_order without a temporary ORDER BY B-tree. Requested-source and any-membership existence probes use the existing membership PK/index, including its origin prefix. No new index or migration was needed, and 3B3B changed no production code. No page size or wall-clock SLA was frozen; these tests are correctness/workload evidence, not benchmarks. No multi-window refill policy was introduced. CandidateProvider remains deferred.
