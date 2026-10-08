# Implementation order

```text
Phase 0 — Architecture scaffold
Phase 1 — Domain models
Phase 2 — Local persistence

Phase 2 does not implement durable FeedEdition/FeedSegment/PublishedCard
storage unless the Publication/Persistence boundary has first been closed.

Content persistence and basic local infrastructure may proceed independently.

Phase 3 — Syndication acquisition
Phase 4 — Canonical admission
Phase 5 — Editorial selection
Phase 6 — Media preparation
Phase 7 — Immutable publication

Publication/Persistence representation boundary must be explicitly resolved
before durable publication history is implemented.

Phase 8 — Feed session
Phase 9 — Adaptive runway
Phase 10 — SwiftUI presentation
Phase 11 — First-launch bootstrap UX
Phase 12 — Background preparation
Phase 13 — Context switching/reuse
Phase 14 — Other product surfaces
Phase 15 — Migration/import from FeedMine legacy where required
Phase 16 — Hardening and release
```

> uma phase não deve adicionar um segundo mecanismo para uma responsabilidade que uma phase anterior já possui.


Phase 0 — complete

Phase 1A — complete

Phase 1B — complete

Persistence Discovery — complete

Phase 2A — runtime persistence lifecycle — complete

Phase 2B — publication identity and exact restore semantics — complete

Phase 2C — frozen PublishedCard baseline — complete

Phase 2D — publication/session relational schema design — complete

Phase 2E — exact offline restore storage — complete

Phase 2F — semantic publication history + FeedWindow — complete

Phase 2G — complete

Phase 2H — complete

Phase 2I — complete

Phase 3A — canonical local supply design gate — complete

Phase 3B1 — canonical supply schema — complete

Phase 3B2 — atomic canonical ContentStore — complete

Phase 3B3 — bounded candidate window — complete (3B3A functional + 3B3B scale/query-plan proof)

Phase 3C — complete

Phase 3D — Selection architecture gate — complete

Phase 3E — pure deterministic baseline Selection — complete

Phase 3F — Publication boundary architecture gate — complete

Phase 3G1 — bounded publication tail — complete

Phase 3G2 — immutable PublicationCoordinator — complete

Phase 3G — complete

Phase 3H — Media + publication preparation architecture gate — complete (design only)

Phase 3I1 — canonical MediaCandidate facts — complete

Phase 3I2 — durable content-addressed local assets — complete

Phase 3I3 — local preparation + publication preparation integration — complete

Phase 3I — complete

Phase 3J — continuous feed production + adaptive runway architecture gate — complete (design only)

Phase 3K1 — bounded exposure + ready-runway history facts — complete

Phase 3K2 — one bounded local production slice — complete

Phase 3K3 — adaptive policy + minimal controller — complete

Viewport movement remains memory-local. An explicit current-position checkpoint operation supplies durability; app lifecycle timing and automatic checkpoint policy remain deferred.

Phases 2G–2I close the local publication/session vertical slice. Phase 3A precedes network acquisition because acquisition needs a canonical authority to admit into; its design gate is [CANONICAL_SUPPLY_DESIGN.md](CANONICAL_SUPPLY_DESIGN.md). Phase 3B1 completed the schema; Phase 3B2 implemented atomic ContentStore changes and exact reads. Phase 3B3 completed bounded candidate windows with 10k/100k evidence sizes, projection-index keyset range/seek and membership-index probes. Source sparsity does not cause refill scanning; no page size or wall-clock SLA is frozen. Phase 3C implements Editorial Candidate and CandidateProvider for Main + Source structural supply. Search remains deferred pending canonical FTS and fails explicitly before a storage window. Each provider call performs exactly one bounded ContentStore window, preserving caller capacity, order, examined count, exhaustion and an Editorial-owned progress cursor. CandidateProvider does not execute FeedPlan policy versions. Phase 3E Selection executes the explicitly supplied matching baseline policy. The macro phase numbering above remains unchanged.

Phase 3D is design only: [SELECTION_DESIGN.md](SELECTION_DESIGN.md) records operator-provided legacy evidence and the deliberate inversion to one caller-supplied finite CandidateSupplyWindow. Selection executes one matching ResolvedSelectionPolicy with explicit no-op eligibility/scoring/exposure and recencyDescending sequencing, preserving honest supply facts. Phase 3E is complete with pure unit tests: no I/O, no refill, no target count, no history/exposure, no scoring weights and no acquisition. Phase 3F now records the design-only Publication boundary; Phase 3G implementation is complete.

Phase 3F is design only: [PUBLICATION_DESIGN.md](PUBLICATION_DESIGN.md) separates Selection intent from ready-to-freeze PublicationCardDraft values. PublicationCoordinator preserves aligned editorial order, construct history from explicit IDs/times/seeds, atomically create Edition + Segment 0 and refuse stale append tails. Preparation/enrichment stays upstream; visibility stays in Runtime/Session. Phase 3G is complete: the indexed-tail append avoids a full-history scan, Coordinator performs no media preparation, automatic retry or global active-Edition discovery, and text-only is a valid prepared baseline. Runtime/Session continues to decide Edition visibility. Phase 3H closes the design-only Media and publication preparation boundary in [MEDIA_DESIGN.md](MEDIA_DESIGN.md). Media returns prepared local facts; pure Runtime PublicationPreparation now combines them with Selection and explicit aligned presentation inputs into PublicationCardDraft values. Publication owns RenderContract and freezes history; Media never depends on Publication. Phases 3I1 canonical media facts, 3I2 durable local assets and 3I3 local/publication preparation are complete; Phase 3I is complete.

Phase 3I1 implements nominal candidate identity, exact declared visual/image facts and a complete ordered immutable revision-owned collection, atomic canonical admission and historical reads with replay/conflict/corruption/rollback proofs. Its justified fifth canonical table does not change the four-table selection hot path or join CandidateProvider. Phase 3I2 now materializes exact local bytes as durable content-addressed files with stable sha256:<hex> keys, pre-store measured image metadata and authenticated/re-inspected local reads. File/directory-sync failure, concurrent idempotency and reopen are proven without DB metadata, transforms, cache or network. Phase 3I3 now implements single-candidate local MediaPreparation and pure Runtime publication-draft assembly. textOnly needs no media result, image presentation requires usable exact-revision facts and explicit hero/thumbnail layout, and unavailable/unsuitable never silently fall back. Actual asset metadata determines the image contract; preparation never executes publication. Keep these ownership boundaries separate. Remote acquisition, HTTP, retries, timers, decoded cache, retention/eviction, audio/video download policy, renderer materialization remain deferred; adaptive policy and minimal controller are now implemented in 3K3. Phase 3I3 implementation is complete. MediaResolver/MediaPolicy, FeedSession production orchestration, Runway media demand, UI loading, retention and network remain deferred; no next implementation phase has started.

Phase 3J is design only: [CONTINUOUS_FEED_RUNWAY_DESIGN.md](CONTINUOUS_FEED_RUNWAY_DESIGN.md) freezes presentation-window versus published-ready stock, measured adaptive coverage, episode-local structural cursors and same-Edition exact-OriginRevisionID automatic repetition suppression. New supply can restart at head with bounded history exposure; empty nonexhausted windows never authorize remote demand. RunwayController is the sole local in-flight intent owner; explicit resolved plan/policy enters each separate bounded slice. Normal replenishment appends current Edition without moving the anchor. Completed 3K1 bounded exposure/ready-ahead facts and query-plan proof. Completed 3K2 one local slice. Completed 3K3 adaptive pure policy/minimal coalescing controller. Completed 3K4 semantic AcquisitionDemand after factual local exhaustion and exact post-settle ready measurement. Planner, coordinator, connectors, network, UI, background wiring and retention remain deferred. The 3J design gate itself authorized no implementation; the reviewed 3K1–3K4 gates now provide the completed implementations.

3K1 implements only PublicationHistory semantic facts and narrow PublicationStore mechanics: same-Edition exact-OriginRevisionID exposure from supplied IDs, ready-ahead exact/atLeast stock and bounded logical same/backward/forwardExact/forwardBeyondProbe measurements. The pre-index plan justified one appended publication-exposure-index-v1 migration with one (origin_revision_id, segment_id) index and no tables/columns. Ready-ahead/advance use existing ordering indexes and a shared probe+1 witness budget. Migration preservation, 10k query plans, immutable tail observations and close/reopen head-request facts are proven. No durable production cursor, exposure table/generation, Runtime or Selection behavior is introduced. Phase 3K2 — one bounded local production slice — complete

Phase 3K3 — adaptive policy + minimal controller — complete.

3K2 implements one append-only LocalProductionSlice with explicit resolved plan/policy, cursor, work bound and caller preparation. Editorial owns exact ordered SelectionExposureSnapshot coverage and excludePublishedRevisions execution by OriginRevisionID. Same-Edition history exposure now observes tail identity in the same read snapshot; automatic append revalidates that identity inside the writer transaction, refusing stale history without retry. Generic append remains available. Zero-selected nonexhausted is successful structural progress; thrown preparation/publication/stale errors leave cursor advancement to the caller only after later success. No schema or package graph change. Acquisition/network, FeedPlanResolver, FeedSession production wiring remain deferred; Runway policy/controller/sampling are implemented in 3K3. Phase 3K3 — adaptive policy + minimal controller — complete.


### 3K3 completion record

Phase 3K1 — complete

Phase 3K2 — complete

Phase 3K3 — adaptive policy + minimal controller — complete

Phase 3K4 — semantic AcquisitionDemand handoff — complete

> Runway health is coverage over measured consumption and replenishment latency, not a fixed number of cards.

> RunwayController owns operational intent, not feed history or presentation.

> Observation submission is memory-only.

> One local slice may be in flight for the active scope.

> Completing one slice may authorize another separate slice, but no method loops until runway is full.

> Unknown coverage never becomes healthy merely because a probe ceiling was reached.

> No timer drives replenishment.

RunwayPolicy evaluates explicit measured r/L facts with `ceil(r * L * safetyFactor)` and, while previously pressured, `ceil(r * (L * safetyFactor + releaseMarginSeconds))`. It introduces no fixed card/page target. Exact ready stock is compared directly; saturated stock remains a lower bound. A lower bound insufficient to prove coverage requests a separate larger bounded ready probe before local work. Reaching the resource ceiling preserves unknown coverage. Known zero rate and exact-zero/tail intent retain factual logical pressure without inventing a positive rate.

RunwayController receives caller-supplied monotonic logical RunwayObservation separately from ViewportObservation. It performs no I/O and executes no LocalProductionSlice. The actor reserves one exact local intent before returning it and coalesces concurrent observations to the latest. History requests and slice intents are executed by a future composition owner. High-water prevents reread counting; same/backward contribute zero, exact advance supplies measured rate, and beyond-probe clears consumption to unknown. Recent samples are bounded, use maximum rate, and reset across explicitly reported inactive consumption gaps.

Successful replenishment uses bounded nearest-rank p95 samples. Its end-to-end latency spans intermediate zero-yield slices and scheduling gaps until publication; exhausted zero/failure/cancellation contributes no fake zero latency. Only successful outcomes update the dispatched lane cursor. Supply changes reopen exhaustion or coalesce one head reset. Fresh head and older progress alternate bounded opportunities so repeated signals cannot starve older work; a completed fresh exhausted walk supersedes older progress. No durable cursor, generation counter, task queue or timer exists.

Unknown bootstrap belongs to one unchanged observation opportunity and reopens on new observation or supply change; factual exact-zero pressure can authorize successive separate bounded slices. Failures do not auto-retry. Measurements must match the latest observation and semantic history scope; completions must match the reserved intent and receipt scope before any mutation. Publication invalidates ready facts while preserving observation anchor/high-water; the next ready measurement stays around that same anchor. Pure actor tests require no database.

FeedSession wiring, publishedTailAdvanced and Acquisition execution remain deferred. AcquisitionDemand is now the semantic handoff described below; no external execution/network, background scheduling, UI, schema or package change is introduced.


### 3K4 completion record

Phase 3K1 — complete

Phase 3K2 — complete

Phase 3K3 — complete

Phase 3K4 — semantic AcquisitionDemand handoff — complete

Phase 3K — complete

> AcquisitionDemand is semantic pressure for more canonical supply. It is not an external fetch command.

> Remote demand is emitted only after bounded local-first production has genuinely exhausted the current structural walk and pressure remains after settlement.

> Empty nonexhausted local work is progress, not remote shortage.

> Unknown runway coverage never authorizes remote acquisition.

> A local production/storage/preparation failure is not evidence that remote supply is needed.

> Admission of new local supply invalidates remote-shortage evidence and reopens local-first consideration.

> One outstanding semantic demand is coalesced; acknowledgment never creates an automatic re-demand loop.

AcquisitionDemand lives in Acquisition, not Runtime. Its exact fields are ContextKey, EditorialRevisionID, readerContinuation purpose, coverageDeficit(requiredCards) or logicalTailPressure, and ExhaustedLocalSupply with nonnegative exact readyCards. A deficit requires requiredCards > readyCards and > 0; logical pressure introduces no artificial count. The value contains no Edition, occurrence identity, URL, source, protocol command or external work quantity. Runtime wraps it with RunwayScope solely for operational ownership and stale acknowledgement checks.

RunwayController requires completed structural local exhaustion, no in-flight local work, no head lane/pending supply reset, no local failure and known pressure before handoff. Every exhausted completion invalidates ready facts, including zero-yield completion. Reconsider first requests a post-settle measurement around the unchanged anchor. Only exact current ready stock proves shortage; healthy/unknown coverage and saturated stock never escalate. A bounded larger ready probe may obtain exact evidence; logical pressure may probe to the explicit ceiling and remains unproven if still saturated there.

Local-first is mandatory whenever a lane can progress. Successful local progress, new observation, inactive consumption, scope replacement/deactivation, changed accepted ready amount and supply admission invalidate remembered shortage ownership. Admission preserves 3K3 head restart/fairness and reopens local consideration. Failed local execution does not imply remote shortage. One outstanding semantic intent is reserved before returning; repeated reconsiderations coalesce, exact acknowledgement moves it to internal suppression, and unchanged facts cannot immediately re-demand. A stale or superseded acknowledgement is rejected without mutation. No durable demand state, identifier/generation, queue or attempt counter exists.

This phase implements no planner, frontier, target, coordinator, connector or network execution. FeedSession wiring and background/UI work remain separate future gates. No next phase is started.


## Phase 3L — Acquisition contracts design gate

Phase 3L — acquisition contracts + durable target architecture gate — complete (design only): [ACQUISITION_DESIGN.md](ACQUISITION_DESIGN.md). Phase 3K is complete; semantic demand/ack is implemented, external acquisition remains scaffold. This gate changes exactly four architecture docs, no Swift/tests/package/schema.

Reviewed future order, each requiring its own implementation authorization:

1. **3M1 — durable target/checkpoint authority.** Nominal Domain TargetID, Acquisition semantic target, one Persistence runtime acquisition_targets table and exact read/update/revoke APIs. Reopen/config/generation/state/CAS envelope proofs. No content admission/planner/connector/catalog/network.
2. **3M2 — protocol-free batch + transactional Admission.** External identity resolution, canonical replay/current/membership/media commands and checkpoint CAS in one writer transaction reusing ContentStore's internal write body. Prove stale generation/revoke/CAS refusal, exact replay, conflicts and full checkpoint/content rollback, selectableSupplyChanged. Fake values only; no connector/planner.
3. **3M3 — pure bounded planner.** Demand + explicitly eligible finite target snapshots + caller resource capacities/active facts → immutable finite plan or explicit disposition. No DB, default budgets, persistent frontier, coordinator or network.
4. **3M4 — FeedConnector + fake finite/continuous coordinator.** Small common pull contract and deterministic event-controlled fixtures. One target execution shared across current demands; batch routes through Admission; durable validity remains the late-result authority. No HTTP, retry, timers/backoff or per-Source actors.
5. **3M5 — fake supply-loop integration.** Composition harness accepts ownership before exact Runway ack; bounded plan/fake batch/admission receipt → scope-aware local-supply change → next separate LocalProductionSlice. No production FeedSession wiring, UI, Syndication/network or background timer.

Phase 3M1 — durable target/checkpoint authority — complete. Phase 3M2 — complete; Phase 3M3–3M5 — not started. These gates deliberately separate durable transaction authority, pure planning and concurrent connector execution. Fake contracts do not require catalog.sqlite or SourceBinding persistence; actual binding-to-target materialization is a separate integration gate.

After 3M: **3N — Syndication architecture/implementation** (real HTTP/FeedKit, validators/translation and reviewed connector-specific configuration), then **Runtime/FeedSession/Composition wiring** with the now-real supply loop, then **UI/default runtime migration**. 3M5's explicit fake composition proof does not require moving production FeedSession wiring ahead of Syndication. Bootstrap stays a separate finite future consumer of the same Target/Connector/Batch/Admission contracts, with explicit budgets; no new purpose or BootstrapPlan implementation is started.


## Phase 3M1 completion record

Phase 3L — complete

Phase 3M1 — durable target/checkpoint authority — complete

At the 3M1 completion gate, Phase 3M2 was not started; it is now complete as recorded below.

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

At the 3M1 gate, AcquisitionBatch and canonical Admission were deferred alongside planner/frontier/coordinator/connector/fakes, batch ledger, SupplyGeneration, leaseEpoch/bindingRevision stamp, network/catalog/SourceBinding persistence and Runtime wiring. The standalone 3M1 CAS is authority only; the shared canonical/checkpoint transaction is implemented by the 3M2 completion record below.

## Phase 3M2 — protocol-free batch and transactional admission

Phase 3M1 — complete

Phase 3M2 — protocol-free batch + transactional admission — complete

Phase 3M3 — not started

> Connector translation finishes before Admission.

> Admission allocates and resolves FeedMine canonical identities; connectors never manufacture OriginRecordID, OriginRevisionID or MediaCandidateID.

> Target validation, canonical mutation and checkpoint advancement are one semantic runtime.sqlite transaction.

> Exact replay reuses canonical identity and never manufactures a new revision merely because observedAt changed.

> A replay of an already historical version never moves the current pointer backward.

> A failed or refused batch changes neither canonical supply nor checkpoint.

> selectableSupplyChanged reports candidate-visible committed supply change, not observation activity.

AcquisitionBatch.swift owns validated immutable protocol-free observation, membership and ordered media claims, the explicit target ID/generation/expected checkpoint revision stamp, optional checkpoint and committed AdmissionReceipt. No connector supplies OriginRecordID, OriginRevisionID or MediaCandidateID; no protocol-specific values, membership removal, batch ID/fingerprint/ledger or provider registry cross this boundary. Nonfinite dates, wrong identity roles, byte-distinct version connectors, duplicate SourceIDs and malformed media URLs/dimensions are refused without normalizing opaque strings. Empty observations require an explicit checkpoint; checkpoint-only batches are supported.

AdmissionPolicy.swift owns ordered semantic preflight (including explicit refusal of unversioned historical observations) and exact mapping to neutral Persistence commands. It makes one AcquisitionAdmissionStore.admit call, with no SQL, target/canonical reads, transport or retry. AcquisitionAdmissionStore owns exactly one RuntimeDatabase.write transaction: require target, validate enabled state/generation/checkpoint revision, defensively preflight every observation, resolve/apply observations in order, compare supply facts, install an explicit checkpoint and return the receipt. Existing target and ContentStore errors propagate. ContentStore gains only internal transaction-scoped identity/current/media reads and wrappers around its byte-exact equality functions; apply(_:in:) remains the single canonical mutation body. No public GRDB API or Persistence→Acquisition dependency is added.

Persistence resolves the exact external object tuple to a stable FeedMine UUID record identity and the origin+version tuple to its immutable revision. A known version reuses the stored revision ID, observedAt and ordered media IDs; ContentStore retains authority over payload/media replay conflicts. New versions and collections receive fresh local UUIDs. A known historical version cannot replace a different current revision even with makeCurrent; it can become current when no competing current exists. No opaque-version ordering is inferred. New historical-only versions preserve the current pointer and projection.

For an unversioned makeCurrent observation, byte-exact payload and ordered media equality with a current unversioned revision reuse its IDs and immutable observedAt. Later local observation time only updates origin and claimed membership observation facts. Changed representation receives a new UUID revision and fresh media IDs, preserving old history; a versioned current followed by an unversioned observation always creates a distinct revision. No synthetic external version/hash is introduced. Unversioned historical is structurally representable but explicitly unsupported by both semantic preflight and mechanical admission.

Nil nextCheckpoint preserves its envelope and revision exactly. An explicit checkpoint increments checkpoint revision exactly once, even when identical, without changing target generation. Content and checkpoint are committed together; a later canonical/media failure or checkpoint overflow rolls back all earlier canonical changes and checkpoint effects. Lost-receipt redelivery with an obsolete checkpoint revision is refused before content, without a batch ledger.

selectableSupplyChanged captures each affected origin before its first change and compares after all observations. Absent selection_supply is one absent fact; a present row includes revision ID, sort date/basis and the current membership SourceID set. It ignores membership kind, first/last observation times and origin lastObservedAt. New selectable origins, projection removal, current revision/sort changes and new source eligibility report true. Exact replay, unchanged historical insertion, kind-only/timestamp-only updates, nonselectable membership updates and checkpoint-only batches report false. No persisted fingerprint, global SupplyGeneration, Runtime callback or Composition wiring is introduced.

Real temporary database tests prove semantic mapping/validation, durable exact reopen, target fences, canonical and media replay/conflicts, unversioned changes, historical current-pointer rules, multi-observation rollback, test-trigger media storage failure, checkpoint overflow, lost receipt and candidate-visible receipts. Schema objects and ordered migration history remain identical across Admission. Phase 3M2 adds zero migrations, tables, columns or indexes. Package.swift and target authority are unchanged. Planner, Coordinator, FeedConnector, fake connectors, Syndication, network, catalog, SourceBinding persistence and Runtime integration remain deferred; 3M3 is not started.
