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

Phase 3M1 — durable target/checkpoint authority — complete. Phase 3M2 — complete; Phase 3M3 — complete; Phase 3M4 — complete; At the 3M4 completion gate, Phase 3M5 was not started; it is now complete as recorded below.. These gates deliberately separate durable transaction authority, pure planning and concurrent connector execution. Fake contracts do not require catalog.sqlite or SourceBinding persistence; actual binding-to-target materialization is a separate integration gate.

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

At the 3M2 completion gate, Phase 3M3 was not started; it is now complete as recorded below.

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

Real temporary database tests prove semantic mapping/validation, durable exact reopen, target fences, canonical and media replay/conflicts, unversioned changes, historical current-pointer rules, multi-observation rollback, test-trigger media storage failure, checkpoint overflow, lost receipt and candidate-visible receipts. Schema objects and ordered migration history remain identical across Admission. Phase 3M2 adds zero migrations, tables, columns or indexes. Package.swift and target authority are unchanged. At the 3M2 completion gate, Planner, Coordinator, FeedConnector, fake connectors, Syndication, network, catalog, SourceBinding persistence and Runtime integration were deferred. The pure Planner is now implemented by the 3M3 record below; the other boundaries remain deferred.

## Phase 3M3 — pure bounded acquisition planner

Phase 3M1 — complete

Phase 3M2 — complete

Phase 3M3 — pure bounded planner — complete

At the 3M3 completion gate, Phase 3M4 was not started; it is now complete as recorded below.

> Eligibility is an input to the Planner, not something the Planner discovers.

> Acquisition pressure determines why work is needed; it does not determine page size, target count, batch count, observation count or byte budget.

> Planner output is finite because caller-supplied resources are finite.

> Existing same-generation external work may be joined instead of duplicated.

> An old-generation active execution blocks replacement work for that target until it settles; cancellation is not correctness.

> Planner has no persistent frontier or mutable state.

AcquisitionPlanner.swift now owns the concrete static pure plan API, immutable AcquisitionActiveExecution, AcquisitionPlanningResources, AcquisitionWorkBounds, AcquisitionPlannedWork, AcquisitionPlan and explicit result/disposition/error values. The only production dependency is FeedMineDomain. Each call consumes explicit current inputs with no I/O, target authority lookup, database, catalog, Source traversal, clock, randomness or connector/Admission execution. No state is consumed between calls and no cursor, queue or persistent frontier is introduced.

Eligibility and target priority order are supplied upstream. All duplicate target and active facts are validated before filtering or capacity decisions. Byte-exact identical target snapshots coalesce at their first occurrence; any conflicting generation, state, connector kind, checkpoint revision or checkpoint envelope rejects with inconsistentEligibleTarget. Exact active generations coalesce per TargetID; conflicting generations reject with inconsistentActiveExecution. These are caller-contract errors, separate from planning dispositions. Revoked targets never produce work. Both start and joinActive carry the original complete target snapshot, including its checkpoint, without reconstruction or freshness prioritization.

Caller-supplied targetWorkCapacity limits total start + joinActive entries. All four resource capacities accept zero, reject negatives and have no defaults. A new start requires strictly positive batchCapacityPerNewExecution, observationCapacityPerBatch and byteCapacityPerBatch; its work bounds are exactly those caller values. Same-generation active work produces joinActive without allocating new execution bounds, including when any/all new-work capacities are zero. A join still consumes a target work entry. A different-generation active execution blocks replacement on that target; the scan may continue to later eligible targets without cancellation or concurrent replacement.

Supplied order remains priority: an earlier startable target stays before a later join even if joining would be cheaper. Targets are never reordered by active status, connector, UUID, checkpoint presence/revision/blob/version or pressure. AcquisitionDemand is preserved in the plan; requiredCards, readyCards and logicalTailPressure never size physical work. No synthetic work quantity, product/page/runway target, retry, deadline or default capacity is inferred.

The planner returns a finite immutable nonempty plan whenever work exists, including valid partial plans despite skipped targets. Otherwise zero enabled targets yields noEligibleTargets; enabled targets with zero total target capacity yield resourceDenied. After scanning, observed new-work resource denial takes precedence over activeGenerationConflict when work is empty; neither disposition implies permanent external exhaustion. AcquisitionPlan construction is fileprivate and requires nonempty work.

AcquisitionPlannerTests uses value-only inputs without a database and covers all 24 numbered cases: order/capacity/filtering, zero resources and join semantics, generation conflicts, duplicate contracts, exact snapshots/bounds, pressure independence and repeatability. Additional validation tests cover negative/zero values and byte-distinct opaque snapshot facts. Package.swift, Persistence/schema, Batch, Admission, Coordinator, FeedConnector, Runtime and Composition are unchanged. At the 3M3 completion gate, Coordinator behavior and connector protocols/fakes/execution were deferred. The bounded shared execution boundary is now implemented by the 3M4 record below; network and Runtime acknowledgement/wiring remain deferred.

## Phase 3M4 — bounded connector and shared target coordinator

Phase 3M1 — complete

Phase 3M2 — complete

Phase 3M3 — complete

Phase 3M4 — bounded connector + shared target coordinator — complete

At the 3M4 completion gate, Phase 3M5 was not started; it is now complete as recorded below.

> FeedConnector is pull-driven: one bounded pull produces at most one protocol-free event.

> A connector cannot advance to the next batch through the Coordinator until Admission has settled the previous batch.

> One external execution exists per AcquisitionTargetID at a time.

> Same-target same-generation callers share the existing execution rather than duplicate work.

> Different-generation replacement work does not run concurrently with an older execution.

> Durable target generation and checkpoint CAS remain the late-result correctness authority.

> Cancellation or disconnection ends the current execution opportunity; neither schedules a retry.

> Coordinator owns transient execution sharing, not durable target state, canonical state, planning or publication.

FeedConnector.swift now owns the Sendable pull protocol, immutable validated FeedConnectorPull and exact protocol-free batch/finished/upToDate/cancelled/disconnected events. One async pull returns one event; no AsyncSequence, AsyncStream, subscription, queue, write/publish capability or protocol-specific transport type is added. Requests carry target ID/generation, current durable checkpoint/revision and strictly positive observation/byte capacities. Batch transportByteCount is factual and transient; it is never persisted.

AcquisitionCoordinator.swift now owns one actor and a transient TargetID→generation/shared Task map. Its execute API accepts one AcquisitionPlannedWork, never a whole AcquisitionPlan. A new start resolves the caller-supplied target→connector association, creates exactly one shared Task and reserves its in-flight entry before awaiting. Same-generation starts and joinActive await the original Task without increasing its bounds; only the creator removes ownership after result/error settlement. Missing joins fail explicitly rather than creating work. Different-generation work is refused while the old Task remains, including after durable reconfiguration; replacement may begin in a separate opportunity after settlement and cleanup. activeExecutions exposes one stable fact per target, sorted only for snapshot stability. No production connector registry, ConnectorKind switch, waiter queue, execution queue, planning/frontier state or extra epoch is introduced.

Before every pull the worker rereads AcquisitionTargetAuthority, fencing missing/revoked/stale-generation or byte-distinct connector snapshots. It builds the request from the current durable checkpoint, not the original planned checkpoint. Each returned batch is checked for nonnegative transport bytes, byte and observation capacities and exact issued target/generation/checkpoint-revision stamp before real AdmissionPolicy runs. Admission completes synchronously and durably before the next pull rereads authority; pull 2 therefore observes the checkpoint committed by pull 1. Admission and arbitrary connector errors propagate without another pull. A late old-generation batch passes request validation but is refused by durable target generation/checkpoint CAS in Admission, without a coordinator correctness epoch.

Successful admitted batches, including checkpoint-only batches and accepted exact replays, count against the exact supplied batchCapacity. Receipts remain ordered and bounded by that capacity. At capacityReached no extra pull is made to discover a terminal event. Result selectableSupplyChanged is the aggregate of committed receipts. finished, upToDate, disconnected and cancelled end the execution without Admission or durable target-state mutation; connector CancellationError maps to cancelled while preserving already committed receipts. No automatic retry, reconnect, timer, deadline, backoff or replay heuristic exists.

FakeFiniteConnector and FakeContinuousConnector are test-only actors. The finite fixture owns its script and consumes at most one step per pull, building batches with the exact request stamp. The continuous fixture stores at most one pending step and one waiting pull continuation: offer delivers to a waiter or fills the empty slot, and refuses a second buffered event. Explicit test continuations prove waiting and sharing without polling, sleeps, timers, network or a background producer. Fixtures own target→script mapping, supplied through the coordinator initializer; no registry enters production.

AcquisitionCoordinatorTests uses real temporary RuntimeDatabase, real target authority and real AdmissionPolicy. All 30 numbered proofs cover checkpoint chaining, capacity and terminal/error handling, pre-Admission bounds/stamps, checkpoint-only receipts, concurrent sharing, late-result refusal/replacement, durable fences and continuous one-slot backpressure. Additional tests cover pull value validation and preservation of committed receipts on CancellationError. Planner, Admission, Persistence/schema and Package.swift are unchanged. At the 3M4 completion gate, plan traversal and Runtime/Acquisition handoff remained deferred to 3M5. That bounded Composition handoff is now implemented in the 3M5 record below; production fakes, Syndication/network and FeedSession integration remain deferred.

## Phase 3M5 — Runtime/Acquisition supply loop

Phase 3M1 — complete

Phase 3M2 — complete

Phase 3M3 — complete

Phase 3M4 — complete

Phase 3M5 — Runtime/Acquisition fake supply loop — complete

Phase 3M — complete

Phase 3N — not started at the 3M5 completion gate; see the 3N1 record below.

> Composition owns the handoff between Runtime intent and Acquisition execution; neither module imports the other to perform that handoff.

> Merely observing RunwayAcquisitionIntent is not acknowledgement.

> A bounded plan is acknowledged before its execution begins because Composition has accepted ownership of that finite work.

> Resource denial or an old-generation execution conflict is not acceptance; the Runtime intent remains outstanding.

> No eligible target is an explicit currently-unserviceable acceptance and may be acknowledged without external execution.

> Successful external work does not itself reset the local walk. Only committed candidate-visible supply change does.

> Every selectable supply change is signalled back to the exact Runway scope that requested it when that scope is still active.

> Admission committed under an obsolete Runtime scope remains valid canonical supply; stale Runtime notification never rolls it back.

> Completion, failure, disconnection or acknowledgement never schedules an automatic retry or another Runway pass.

> The integration owner never calls RunwayController.reconsider on its own.

RunwayAcquisitionCycle.swift is the single new production owner in Composition. It is a concrete Sendable value over RunwayController and AcquisitionCoordinator, with typed executed/acceptedUnavailable/deferred outcomes and only its staleIntent error. Each run first compares the exact outstanding Runtime intent before any planning, takes one active-execution snapshot, calls the pure Planner once with explicit caller eligibility/resources and performs no target/catalog/Source discovery or database access. No existing production file or module dependency changes.

noEligibleTargets is acknowledged as accepted unavailable for these current inputs, without implying permanent exhaustion. resourceDenied and activeGenerationConflict defer without acknowledgement, preserving the exact outstanding intent for a future explicit caller input change. A finite nonempty plan is acknowledged before any execution; a stale acknowledgement propagates and cannot start work. Composition traverses the complete plan sequentially in supplied order, awaiting one coordinator work item at a time. No parallel scheduler, TaskGroup, internal replan or automatic retry is introduced.

After each successful execution result, ordered results are retained and committed selectableSupplyChanged immediately signals noteLocalSupplyChanged with the requesting intent.scope before advancing to later work. False results cause no signal. Multiple changing targets signal separately, permitting Runtime to coalesce a head reset if a caller-owned local slice has started between results. noActiveScope and scopeMismatch notification failures alone are ignored: global canonical Admission remains committed and no arbitrary replacement scope is signalled. Other errors propagate. A later target failure neither undoes prior canonical commits/signals nor recreates/acknowledges demand or schedules another pass.

The owner imports only Acquisition and Runtime. It never calls reconsider, local production, candidate queries or publication, and owns no registry, database/catalog, defaults, clock, Task, timer, polling or background loop. Its sole loop walks the finite Planner work array. FeedSession/UI integration, real Syndication/network, catalog/SourceBinding mapping and concurrent target scheduling remain deferred; 3N was not started at that gate; see the 3N1 record below.

The exact FeedMineCompositionTests target is added with Composition, Domain, Persistence, Acquisition, Editorial, Publication and Runtime dependencies only. Its one test file uses real temporary runtime storage, target authority, Planner, Coordinator, Admission, RunwayController, PublicationHistory, PublicationCoordinator and LocalProductionSlice, with a local one-slot test connector and explicit event controls. Existing tests remain unchanged.

The full-loop proof creates one Edition/anchor, measures real ready-ahead zero, runs a real exhausted local slice, emits real Runway demand, admits a fake external batch transactionally, and observes a canonical candidate while publication still has one segment. The supply signal reopens local-first; only the test caller then reconsiders and runs the next real LocalProductionSlice, appending a second segment to the same Edition referencing the admitted revision. The original history/Edition remains intact; Acquisition itself publishes nothing.

Tests also prove acknowledgement before first pull, accepted unavailable, resource/conflict deferral, reuse of the same intent after an explicit resource change, stale-gate precedence over invalid Planner inputs, checkpoint-only/exact-replay non-reset, error-after-ack without redemand, prior commits/signals surviving later error, obsolete/deactivated scope notification safety, separate immediate signals and sequential settled plan traversal. Numbered test 7 (the snapshot-to-ack race) is omitted under the contract's explicit exception: no deterministic insertion point exists without a production synchronization hook. No such hook is added; stale-intent proof and existing Runway stale-ack tests remain authority. Numbered test 13 is proven through real Runway state, not a production journal/hook.


## Phase 3N1 — Syndication configuration, checkpoint and translation

Phase 3M — complete

Phase 3N1 — Syndication configuration/checkpoint/translation — complete

Phase 3N2 — Syndication HTTP + concrete FeedConnector — not started at the 3N1 gate; see the 3N2 record below.

> FeedKit objects exist only inside FeedMineSyndication.
>
> Syndication translation ends at AcquisitionObservation; Admission and every downstream module remain protocol-blind.
>
> Syndication identity is explicit declared identity, never a hash-generated canonical identity.
>
> Feed item processing is caller-bounded and does not refill past rejected items.
>
> Target configuration is connector-specific and does not enter acquisition_targets.
>
> Syndication checkpoint bytes are opaque to Acquisition core.
>
> No HTTP behavior is implemented in 3N1.

Package.swift pins FeedKit exactly to 10.9.4 and links it only to FeedMineSyndication in production. GRDB remains exactly 7.11.1, confined to Persistence in production. FeedMineSyndicationTests adds no external dependency. FeedKit models never enter public signatures, Acquisition, Admission or downstream modules.

SyndicationConnector.swift owns SyndicationTargetConfiguration only: explicit TargetID, exact endpoint URL and ordered nonempty membership claims with unique SourceID. Endpoints require HTTP/HTTPS, a nonempty host and no embedded credentials. Configuration remains outside runtime.sqlite and acquisition_targets; generation and checkpoint are not duplicated. The configuration owner must fence durable target generation before changing endpoint or membership mapping. No concrete FeedConnector, registry or Composition wiring is introduced.

SyndicationTranslator.swift synchronously calls Feed(data: data) on already available, unmodified bytes. It accepts finite caller observedAt, nonnegative startIndex and positive itemCapacity. FeedKit parses the document; canonical translation examines only min(itemCapacity, declaredItemCount - startIndex) declared positions, without pretranslating the other items. Each rejected item consumes its position and never triggers refill. Returned nextItemIndex is the next declared position or nil at exhaustion; start-at-end returns an exhausted empty slice and start-beyond-end is invalid. Parser errors become parseFailed without leaking FeedKit errors. Item-level missingStableIdentity and invalidCanonicalObservation apply only after the parser materializes an item.

External identity namespaces start with syndication:<lowercase TargetID UUID>. RSS prefers exact nonempty GUID then link, with rss-guid/rss-link suffixes; RDF uses the same baseline with rdf-guid/rdf-link. Atom prefers exact ID then the first nonempty href with absent rel or case-insensitive alternate rel, with atom-id/atom-link. No title, date, index, endpoint, SourceID or hash generates object identity. Opaque strings are preserved without trimming, lowercasing or URL normalization.

JSON Feed object identity requires its declared item `id`.
FeedKit 10.9.4 enforces this required JSON Feed field during parsing.
FeedMine does not synthesize a replacement identity from url/external_url.
The sole JSON object namespace is json-id, with the exact FeedKit-delivered value. JSON Feed url/external_url remain primary-link candidates only. Missing required JSON Feed id is a parser-level parseFailed, not an item-level missingStableIdentity rejection.

Parser-level structural failures remain document failures. In particular, FeedKit 10.9.4 treats missing JSON Feed id as a document parse failure because JSON Feed declares the field required. FeedMine does not preprocess or reparsed invalid JSON to manufacture item identity.

RSS/RDF remain unversioned; pubDate is authoredAt, never a version identity. Atom updated produces atom-updated, and JSON Feed date_modified remains the only baseline explicit version identity (json-modified). Version values use String(date.timeIntervalSinceReferenceDate.bitPattern, radix: 16), with role version; url/external_url never become version identity. JSON object identity, modified-date version and primary link are independent.

Observations are makeCurrent/available, preserve caller observedAt and exact ordered membership claims, and leave providerID/searchProjection nil. RSS/RDF map title, description and pubDate; only RSS maps channel language. Atom maps title, summary text, published and updated. JSON maps title, summary, contentText, datePublished, dateModified and item language; contentHtml never enters bodyText. Primary links require HTTP/HTTPS and a host: RSS/RDF link, first eligible Atom alternate link, or JSON url else externalURL. Invalid opaque links may remain object identities while primaryLink is nil.

Media claims are cardVisual/image, with no inferred MIME or fetched bytes. RSS/RDF iTunes image comes first, then ordered Media thumbnails; Atom uses ordered Media thumbnails; JSON image precedes bannerImage. Invalid media declarations are skipped without rejecting the item. Thumbnail dimensions survive only when both parse as positive integers; otherwise both are nil. URLs require HTTP/HTTPS and a host. No media deduplication or preparation is performed here.

SyndicationHTTP.swift owns only SyndicationCheckpointState and its codec. Optional nonempty exact ETag and Last-Modified strings are opaque validators. The connector-owned partial position requires a nonempty documentFingerprint with positive nextItemIndex, or nil fingerprint with index zero. Custom Codable decoding enforces the same invariants as construction. The codec uses sorted-key JSON, serializationSchema 1 and exact connectorVersion feedmine-syndication/1-feedkit/10.9.4 inside the existing opaque AcquisitionCheckpoint envelope. Incompatible schema/version and malformed state throw typed errors and never silently reset. Empty state has nil validators/fingerprint and index zero; no endpoint/query is stored and no envelope is proposed merely for emptiness.

Future 3N2 owns HTTP fetching, conditional validators, status/304 handling and redirect execution. It must match a body's fingerprint before resuming the partial index and restart at zero for a changed body, then submit translation and checkpoint through the existing batch/admission boundary. None of that execution exists in 3N1. No request, network initializer, retry, timer, backoff, catalog, SourceBinding persistence, FeedSession or Runtime/Composition integration is added.

The two new test files cover all 36 numbered cases with local inline bytes only. They prove the four formats, declared-position bounds without refill, exact configuration/identity/version/link mapping, media ordering/dimensions and checkpoint invariants/compatibility. Amendment A replaces JSON identity fallback with document-level missing-id refusal and separately proves primary-link preference/fallback on valid declared-id items. No existing test, schema or downstream production file changes.


## Phase 3N2 — bounded Syndication HTTP connector

Phase 3M — complete

Phase 3N1 — complete

Phase 3N2 — Syndication HTTP + concrete FeedConnector — complete

Phase 3N — complete

Post-3N production Runtime/FeedSession/Composition wiring — not started at the 3N2 gate; the 3O1 bridge below leaves the 3O2 driver deferred.

> SyndicationConnector performs one bounded external opportunity per FeedConnector pull.
>
> The exact FeedConnector byte capacity bounds the response body while it is being received, not only after full buffering.
>
> Conditional validators are sent only at a document boundary, never while a partial document still needs its body.
>
> A partial document resumes only when the newly fetched body fingerprint exactly matches the checkpoint fingerprint; otherwise translation restarts from declared item index zero.
>
> Validators never travel across a redirect hop.
>
> Validators obtained from a redirected final resource are not persisted because the current checkpoint schema intentionally does not persist validator-origin endpoint identity.
>
> A valid 304 requires that the exact request which received it was conditional.
>
> SyndicationConnector proposes checkpoints; Admission remains the only durable checkpoint authority.
>
> Network, parsing and translation failure never advances the checkpoint.
>
> No HTTP status schedules another attempt.

SyndicationConnector.swift now owns the concrete immutable Sendable FeedConnector. SyndicationTargetConfiguration remains unchanged: no generation, checkpoint or mutable cache is added. Public construction takes explicit configuration, caller-owned URLSession, nonnegative redirectCapacity and injected clock. An internal initializer accepts the single narrow SyndicationHTTPTransport seam for deterministic tests; no public transport framework is introduced.

Each pull first fences TargetID, decodes the opaque checkpoint (or uses empty state), and validates a finite injected observedAt before external work. Generation and checkpointRevision remain exactly the Acquisition request stamp. One logical bounded GET returns one batch or upToDate; Syndication does not synthesize finished, disconnected or cancelled events. Network cancellation propagates as CancellationError for the existing Coordinator cancellation handling. No durable target or checkpoint write, Admission call, candidate query or publication occurs here.

SyndicationHTTP.swift preserves the 3N1 checkpoint state/codec/schema exactly and adds the connector-specific HTTP hop, client and real URLSession transport. The transport uses the supplied session's bytes(for:delegate:) stream, never full-body data(for:), data(from:) or remote FeedKit initialization. Its accumulator checks every byte before append, never grows beyond bodyByteCapacity, and cancels the underlying task on overflow. A nonnegative declared Content-Length may refuse early; received-byte enforcement remains authoritative. Non-200 response bodies are not intentionally accumulated. Non-HTTP responses have a typed error; underlying network errors propagate, with only URLError.cancelled normalized to CancellationError. URLSession lifecycle and configuration remain caller-owned; no shared singleton is constructed.

The HTTP client owns finite manual traversal bounded by explicit redirectCapacity. Each request is GET at the exact configured endpoint initially, with reloadIgnoringLocalCacheData, no body, endpoint rewrite or FeedMine credential mechanism. The task delegate refuses automatic redirects. Only 301, 302, 303, 307 and 308 are followed; Location must be nonempty and resolvable against the current URL, and every destination requires HTTP/HTTPS, a host and no user/password. Zero capacity refuses the first redirect without another transport call. Requests rebuilt after every redirect carry no conditional validators, even for relative or same-host hops. The configured endpoint is never mutated or persisted as a redirect destination.

At a document boundary only (nil fingerprint, index zero), exact ETag and Last-Modified checkpoint strings become If-None-Match and If-Modified-Since. Partial continuation is always unconditional because it needs the body. A 304 is upToDate only if that exact hop sent at least one validator; unconditional, partial or redirected 304 throws notModifiedWithoutConditionalRequest. It proposes no checkpoint and performs no CAS. Only 200 is document success; every other status is unexpectedStatus unless it is one of the explicit redirects. No status handling adds retry classification, Retry-After, reconnect, backoff or another scheduled opportunity.

Exact accepted response bytes receive a SHA-256 continuation fingerprint encoded sha256:<64 lowercase hex>. This fingerprint is connector continuation only, never canonical object/version/media/batch identity. An exact fingerprint match resumes the durable declared-item index; a changed body starts at zero without an intermediate reset write. The unchanged SyndicationTranslator receives exact body, caller configuration, injected observedAt and observationCapacity as declared-position itemCapacity. Rejected positions consume capacity and never refill. Body bytes, parsed feeds, translations, redirect endpoints and validator maps are not retained across pulls.

Direct 200 validators become exact candidate checkpoint validators; any redirected final validators are discarded because the frozen checkpoint has no validator-origin endpoint. A partial result proposes the new fingerprint and next declared index; a fully consumed result clears fingerprint/index to nil/zero. State equal to the decoded old state produces no checkpoint proposal. An actual clear of stale validators or an old partial position encodes empty state through Admission, while meaningless initial empty state does not manufacture a batch. Checkpoint schema remains 1 and connectorVersion remains feedmine-syndication/1-feedkit/10.9.4; no endpoint, retry time, status, cookie or body field is added.

Nonempty observations with or without a delta, and checkpoint-only deltas, produce an AcquisitionBatch with the exact request targetID, targetGeneration and expectedCheckpointRevision. Zero observations and zero delta return upToDate. Emitted batch transportByteCount is exact final body.count, excluding redirect bodies and declared lengths. Parser/translation/HTTP failure returns no proposal. JSON empty ID remains materialized then item-level missingStableIdentity rejection; JSON missing ID remains parser-level parseFailed. No URL fallback, JSON preprocessing or Translator modification is added.

SyndicationHTTPTests and SyndicationConnectorTests cover all 40 numbered proofs using scripted narrow I/O and local URLProtocol fixtures only. The real-session tests demonstrate exact byte limit, first excess-byte refusal, incremental open-body cancellation before a remaining chunk, refusal of automatic redirects and cancellation normalization. Connector proofs cover exact clock/stamp/byte count, direct versus redirected validators, SHA-256 reference value, three-slice continuation, changed-body restart, checkpoint clears/delta suppression, parser failures, target/checkpoint fences and JSON identity semantics. No internet, sleep or timers are used. The two existing Syndication test files and all downstream production/tests remain unchanged.

Catalog, SourceBinding persistence/materialization, eligibility discovery, Runtime scheduling, FeedSession/Composition/UI integration, refresh/background work, host scheduling and media downloading remain deferred to later reviewed gates. No schema, migration, Package.swift dependency or Runtime/Composition wiring changes in 3N2. The next production-wiring gate is not started.


## Phase 3O1 — production Syndication target bridge

Phase 3N — complete

Phase 3O1 — explicit SourceBinding→Target production bridge — complete

Phase 3O2 — production Runway/FeedSession driver — not started at the 3O1 gate; see the amended 3O2 record below.

Persistent catalog/target reconciliation — not started

> SourceBinding is declarative editorial authorization; AcquisitionTarget is operational work identity.
>
> AcquisitionTargetID remains explicit FeedMine-owned identity and is never derived from SourceBindingID, SourceID or endpoint.
>
> Multiple SourceBindings may share one AcquisitionTarget.
>
> One SourceBinding may participate in multiple AcquisitionTargets.
>
> Connector configuration becomes usable only when its explicit generation stamp matches the durable AcquisitionTarget generation.
>
> A configuration change must be fenced by durable target reconfiguration before the new snapshot becomes visible.
>
> The bridge never mutates durable target authority.
>
> Missing or stale durable target state is an error, never silently converted into noEligibleTargets.
>
> Revoked durable targets are simply not eligible.
>
> Connector resolution is configuration lookup, not eligibility discovery or scheduling.
>
> Reconstructing a stateless SyndicationConnector does not lose acquisition state because continuation lives in the durable opaque checkpoint.

SyndicationAcquisitionSnapshot.swift is the single new production owner in Composition. It imports Foundation, Domain, Persistence, Acquisition and Syndication only; it has no Runtime, Publication or Editorial dependency. It bridges a caller-supplied current declarative configuration snapshot to the already-existing durable target authority and real Syndication connector. No existing production file, package graph, schema or migration changes.

SyndicationTargetRegistration is an immutable Hashable/Sendable value with exactly explicit targetID, positive targetGeneration, endpoint and ordered bindings. Target IDs are caller-supplied and never derived from endpoint, SourceBindingID, SourceID, external principal or hash. Current registrations require nonempty enabled Syndication bindings, with unique BindingID and SourceID within each target; invalid duplicates are rejected rather than deduplicated. The same binding may occur in registrations for different targets, and multiple bindings may share one target, preserving many-to-many capability without a global binding uniqueness restriction.

Each binding materializes one AcquisitionMembershipClaim with its SourceID and kind direct, in exact binding order. Binding ID, binding generation, aliases and external principal do not become membership identity. Registration reuses SyndicationTargetConfiguration validation for HTTP/HTTPS, nonempty host and absent embedded credentials. Its generation is a configuration stamp claiming the durable target generation, not an independent authority or automatic increment.

SyndicationAcquisitionSnapshot is an immutable Sendable caller-owned value storing database, ordered registrations, caller-owned URLSession, explicit nonnegative redirect capacity and injected clock. Duplicate TargetID and negative redirect capacity throw typed initialization errors. It is neither a registry singleton nor an actor, mutable catalog owner, cache, service locator or scheduler. Declarative changes require a new snapshot; no add/remove/update/refresh API exists.

eligibleTargets(for:) selects relevant registrations in supplied order, then reads each current target only through AcquisitionTargetAuthority.target(id:). Main considers all registrations; source filters by binding SourceID and preserves relative order. Search throws searchContextUnavailable before authority reads, rather than returning falsely empty eligibility that could acknowledge unserviceable demand. Missing durable target, stale configuration generation or connector-kind mismatch throws; no previously collected partial result is returned. Revoked durable targets with matching configuration are skipped. Enabled targets are returned exactly as read, including current checkpointRevision and opaque checkpoint; the bridge never reconstructs operational target state from declarations. Underlying target-store/database failures propagate unchanged.

connector(for:) performs synchronous configuration lookup without I/O or authority reads. Only known exact TargetID/generation, enabled state and Syndication connector kind resolve to a newly constructed real stateless SyndicationConnector using registration-derived direct memberships, supplied session, redirect capacity and clock. Unknown, stale, revoked or wrong-kind targets resolve nil under the existing Coordinator resolver contract; Coordinator retains missingConnector handling. makeCoordinator() only constructs AcquisitionCoordinator with the supplied database and this exact resolver. It performs no planning, target mutation or Runtime orchestration.

Configuration changes follow a durable fence: a snapshot stamped N stays current while the caller determines a change; the caller explicitly reconfigures AcquisitionTargetAuthority and commits generation N+1; only then does it publish a new endpoint/binding snapshot stamped N+1. Publishing new configuration first and bumping generation later is forbidden. The old snapshot's eligibility throws staleConfigurationGeneration after the durable advance, rather than silently becoming noEligible. Already in-flight work relies on the existing Coordinator durable generation reread and Admission generation CAS; no extra cancellation generation or mechanism is added.

Target existence remains a precondition. This bridge never calls register, reconfigure, revoke, enable or compareAndSwapCheckpoint, and introduces no automatic target registration/reconfiguration. It creates no catalog.sqlite, source/source_bindings/target_mapping/connector_config table or cross-store materialization. Persistent catalog and target reconciliation require a separate reviewed transition gate. The next 3O2 gate may wire this snapshot into production Runway/FeedSession orchestration; that driver, UI integration, background refresh, retry/timer and media download are not started here.

SyndicationAcquisitionSnapshotTests covers all 23 numbered proofs, including the preferred old-snapshot Coordinator fence. Real temporary RuntimeDatabase, local deterministic URLSession/URLProtocol, actual Syndication RSS translation, snapshot.makeCoordinator() and real Admission prove direct source membership candidate visibility. Ordered membership claims are checked on the real snapshot-resolved connector. A shared target executes once and makes the same admitted OriginRecord visible under both bound Sources. Repeated stateless connector resolution resumes the durable opaque partial checkpoint without advancing authority merely by resolution/pull. No manual SyndicationTargetConfiguration, live internet, sleep, timers or production test hooks are required.


## Phase 3O2 — production Runway / FeedSession driver

Phase 3N — complete

Phase 3O1 — complete

Phase 3O2 — production Runway / FeedSession driver — complete

Cold-start first Edition / bootstrap — not started

FeedSessionUI / FeedScreenStore wiring — not started

Persistent catalog / target reconciliation — not started

> FeedSession owns local presentation state; it does not execute Runway, Selection, Publication or Acquisition.
>
> RunwayController remains the sole owner of runway policy and operational progress.
>
> FeedRunwayDriver executes RunwayController actions; it does not invent its own scheduling policy.
>
> The driver has no timer, retry policy, background cadence or fixed number of cards/actions.
>
> One explicit drive opportunity follows causal Runway actions until the controller becomes quiescent or explicitly defers external work.
>
> Publication history measurements come from committed PublicationHistory, never from the finite FeedSession presentation window.
>
> Local publication appends history first; FeedSession then rematerializes its current local projection without moving its anchor or durable checkpoint.
>
> Acquisition changes canonical supply only; LocalProductionSlice remains the only path in this driver that appends feed history.
>
> A restored Edition is never replaced merely because its runway needs replenishment.
>
> All production identifiers, preparation decisions and resource capacities remain explicit caller inputs.
>
> FeedSession presentation-window boundaries never fabricate reader intent. The end of a finite materialized window is not the end of committed publication history.
>
> Session restoration is quiescent until semantic consumption input or another explicit caller opportunity gives RunwayController actionable intent.

FeedSessionState retains one new internal editorialRevisionID fact from the exact restored Edition, solely to expose currentRunwayScope without a lookup. Viewport replacement and local rematerialization preserve it. FeedPresentationSnapshot and UI presentation gain no editorial, runway, network, loading or duplicate checkpoint facts. FeedSession still executes no Selection, Publication production or Acquisition work.

FeedSession.refreshCurrentPresentation rematerializes through PublicationHistory.window using exact Edition, memory-local anchor card/placement and original backward/forward capacities. It constructs the new projection before replacing state, so read/mapping failure preserves the old installed presentation and propagates. It does not save a cursor, call SessionStore or create a checkpoint milestone. No-state scope/refresh returns nil. This is local projection refresh after a committed append, not an explicit successor-Edition refresh intent.

SyndicationAcquisitionSnapshot adds only an internal runtimeDatabase getter so Composition constructs PublicationHistory and LocalProductionSlice over the exact same database as Acquisition target authority and Coordinator. No public storage access, SQL or target mutation is exposed. All existing registration/eligibility/connector semantics remain unchanged.

FeedRunwayDriver is a Composition actor over FeedSession, RunwayController, FeedPlan, ResolvedSelectionPolicy, the immutable Syndication snapshot, PublicationHistory, LocalProductionSlice, RunwayAcquisitionCycle and three caller closures: monotonicNow, makeSegmentIdentity and prepare. It stores no second state machine, queue, cursor, generation, pending actions, retry state or coverage policy. FeedRunwaySegmentIdentity has exact caller-supplied segment ID, seed and finite creation date; FeedRunwayDriverResources carries explicit RunwayResourceFacts and AcquisitionPlanningResources with no defaults. Initialization checks policy context only; full policy/revision compatibility remains Selection authority. Current session context and editorial revision must match the plan before effects; underlying owner errors propagate.

restoreAndActivate installs the saved local presentation first, validates scope, activates Runway and submits an initial stationary observation. No checkpoint means nil and Runway deactivation, with no HTTP, local publication or cold Edition creation. activateCurrentPresentation has the same baseline for an already-restored session. Under Amendment B, stationary activation without prior consumption facts legitimately measures and quiesces without work. Restoration never fabricates forward or explicitTailApproach intent from finite window first/last/count/capacities.

submitViewport first lets FeedSession accept or ignore the logical viewport. An unknown/unretained anchor that was not accepted returns the existing projection without observation or drive. An exact same anchor is still valid semantic input: caller-supplied activity and monotonic time become a new RunwayObservation even without presentation movement. One explicit same-anchor explicitTailApproach opportunity can drive the complete causal replenishment path after quiescent local restore. No UI geometry or presentation-window tail inference enters the driver.

Every iteration of the sole causal drive loop starts with RunwayController.reconsider using exact caller resources and injected monotonic time. There is no maximum action/iteration/card count or independent driver pressure calculation. none returns current FeedSession presentation. measure reads committed PublicationHistory.readyAhead and, when requested, forwardAdvance, then accepts the exact measurement into Runway. Presentation capacity and item indices never substitute for committed runway or consumption facts.

For a local intent, the caller supplies one segment identity. The driver passes exact intent Edition, continuation cursor and examined capacity plus plan/policy to the unchanged LocalProductionSlice and caller preparation closure. Successful outcome completes Runway with an injected completion time. Published output then refreshes FeedSession's current projection after the durable append; advancedWithoutPublication does not refresh. Failure handling attempts failLocalSlice with cancelled for CancellationError or failed otherwise, then propagates the original operation error if failure recording succeeds. No local failure starts an Acquisition fallback or automatic second attempt.

For Acquisition, current targets come solely from SyndicationAcquisitionSnapshot.eligibleTargets(for: plan.context), then the unchanged RunwayAcquisitionCycle plans/executes/acknowledges. Committed selectable supply change returns the controller to local-first decisions; Acquisition never publishes feed history. Executed without supply change, acceptedUnavailable or deferred returns current presentation without redemand. A later explicit drive opportunity first reuses the exact outstanding controller-owned deferred intent: reconsider intentionally does not emit the same outstanding intent twice. This resumes resource denial without storing another pending action, creating a new demand or submitting an artificial viewport observation. Eligibility/execution failure propagates with existing pre-ack/accepted ownership semantics and never undoes canonical commits.

markConsumptionInactive delegates only to Runway; deactivate delegates only to Runway deactivation. Both preserve the visible FeedSession projection. No driver task, timer, polling, network client, SQL, card-ID generation, direct wall-clock call or presentation constructor is introduced. Production RunwayController, RunwayPolicy, LocalProductionSlice, RunwayAcquisitionCycle, Syndication, Publication and Package.swift remain unchanged.

FeedSessionRunwayTests proves exact restored scope, revision-preserving viewport movement, same-window append rematerialization/capacities, unchanged durable checkpoint and nil behavior without restore. FeedRunwayDriverTests covers all 24 numbered cases plus finite caller segment-time validation. The amended full-loop proof first restores with zero HTTP, then one same-anchor semantic tail call uses real committed measurements, local exhaustion, SourceBinding/Target bridge, bounded local HTTP fixture, transactional Admission, canonical reset and real LocalProductionSlice append to the same Edition. No manual internal execution occurs in that full-loop call. A suspended response proves saved history stays visible; the local-first test proves local content is committed/projected before releasing remote bytes.

The thin-window proof establishes real replenishment latency and committed forward consumption, then presents only the anchor while committed history still has many ready cards. Same-anchor tail input remains healthy according to measured controller facts and causes no HTTP; window end never becomes a claimed committed history tail. Source-context tests use two real registered targets and prove only the matching binding's connector executes. Search boundary testing seeds exhausted-local controller facts because local CandidateProvider search remains unavailable, then verifies the bridge's searchContextUnavailable and retained pre-ack demand. Failure, cancellation, deferred resumption, context/revision fences, unknown viewport, committed advancement, inactivity and same-Edition quiescence are also covered with local deterministic fixtures, without sleeps/timers or live internet.

Cold first-Edition bootstrap, BootstrapPlan, persistent catalog/target reconciliation, UI reducer/effects/store wiring, background cadence, retry/backoff, media network download and successor-Edition refresh remain separate future gates. The next gate is not started.

## Phase 3P1 — Atomic first Edition from local supply (complete)

Phase 3O2 is complete. Warm restore remains the preferred path. With no restorable session, InitialProductionSlice owns exactly one caller-requested bounded local attempt over existing canonical supply. It uses the same FeedPlan, resolved Selection policy, caller-supplied preparation and immutable Publication machinery as continuous production. Its candidate cursor starts nil, examined capacity is explicit, and Selection's factual progress is returned unchanged. Empty selection creates no history or checkpoint and never invokes preparation.

The first Edition, Segment 0, its cards and the first durable session checkpoint become visible atomically.

Cold local publication examines one bounded candidate window and never refills internally.

The first Edition uses the same FeedPlan, resolved Selection policy, Publication preparation and immutable Publication machinery as later feed work.

A new Edition begins with an empty Edition-scoped exposure set; exposure from another Edition never suppresses its first Segment.

PublicationCoordinator remains the semantic producer of FeedEdition / FeedSegment / PublishedCard history.

Persistence owns the single mechanical transaction that combines first publication with initial session durability.

Initial publication never creates or executes AcquisitionDemand.

Failure at any point leaves neither the new Edition nor its initial checkpoint.

Existing saved session state is never silently replaced by cold bootstrap.

Automatic excludePublishedRevisions exposure policy is required. The new Edition receives an exact exposure snapshot for the candidate window with no published revisions; no prior Edition exposure is queried. A revision in another Edition remains eligible for the new first Segment. The caller supplies every Edition/Segment/card identity, seed, schema version, date, placement and preparation input; the slice generates no identifiers or clock readings.

PublicationCoordinator.InitialCreateRequest wraps the existing CreateRequest, explicit placement and checkpoint date. Shared semantic preparation freezes the Edition, Segment 0 and cards. The first supplied published card ID becomes the initial SessionCursor anchor; callers cannot nominate an unrelated anchor. Empty semantic publication performs no store write. Existing PublicationPersistenceMapping encodes all publication records and the cursor.

PublicationStore.createEdition and createInitialEdition share one mechanical first-publication transaction body. Normal createEdition remains a single non-session transaction. createInitialEdition validates Segment 0's Edition/ordinal and checkpoint Edition/card relation, then uses one writer transaction for history insertion followed by SessionStore.insertInitialCheckpoint. The internal initial helper validates placement, finite time and actual Edition/card membership, rejects any existing checkpoint with checkpointAlreadyExists, and uses INSERT without upsert. Failure at this final step rolls back Edition, segment and cards, preserving any old checkpoint. Normal saveCheckpoint retains its explicit milestone/upsert semantics. No migration, table, index or column changes.

The two new real-database test suites cover four-fact success, relation rejection, final-checkpoint rollback, preserved existing session, normal non-session creation, bounded selection/progress/exhaustion, immediate PublicationHistory.restore, caller first-card anchoring, preparation failure, exposure policy and prior-Edition independence. No separate saveCursor follows initial publication.

At the 3P1 boundary, bounded remote bootstrap and FeedSession installation were deferred. Phase 3P2 now completes that finite composition path as recorded below. 3P1 itself introduces no Acquisition or network work. FeedSessionUI / FeedScreenStore wiring and persistent catalog / target reconciliation remain not started.

## Phase 3P2 — bounded cold bootstrap acquisition (complete)

Phase 3P1 — complete

Phase 3P2 — bounded cold bootstrap acquisition — complete

Cold initial presentation path — complete through FeedSession installation

FeedSessionUI / FeedScreenStore wiring — not started

Persistent catalog / target reconciliation — not started

The implemented explicit-call order is local initial slice → exhaustion-only Acquisition planning → one sequential finite plan → selectable-change-only second initial slice → atomic checkpoint restore into FeedSession → stop. Warm restore remains caller/FeedRunwayDriver responsibility. The next gate is not started.

`initialPublication` is a semantic purpose distinct from `readerContinuation`. AcquisitionDemand accepts only continuation with coverageDeficit/logicalTailPressure, or initialPublication with initialPublication pressure and factual readyCards == 0. The zero is absence of published runway, never a publication target. BootstrapPlan carries that exhausted-local demand plus explicit AcquisitionPlanningResources; it discovers no targets and schedules no work.

ColdFeedBootstrap checks that FeedSession has no installed presentation, then invokes one bounded InitialProductionSlice. Existing durable checkpoints remain fenced by the unchanged 3P1 transaction; there is no hidden warm restore. A first local success installs FeedSession from the atomic checkpoint and stops. A first nonexhausted local miss preserves progress as localWorkRemaining and never triggers eligibility or network. Only proven local structural exhaustion permits the initial-publication demand.

Eligible targets come from SyndicationAcquisitionSnapshot. Bootstrap reads the injected coordinator's active executions once, calls the existing AcquisitionPlanner once, and traverses one finite acquisition plan once sequentially. There are no Runway acknowledgement semantics. noEligibleTargets returns unavailable; resourceDenied and activeGenerationConflict return deferred with the original exhausted progress. Underlying eligibility, connector, admission, preparation and publication errors propagate without wrapping or recovery. Earlier committed target Admission survives a later error; errors never start a local publication attempt automatically.

The aggregate selectableSupplyChanged fact gates the second local attempt. If false, the first exhausted progress and exact ordered results are returned without local reassessment. If true, exactly one second InitialProductionSlice receives the same request and first-Edition identity, starting selection at the canonical head. Its no-publication progress is returned whether exhausted or not. Bounds are at most two initial local attempts and at most one Acquisition planning/execution opportunity per explicit call. No target card count, page size, timer/deadline, retry, Bootstrap cursor/state machine, background work or parallel scheduler is introduced.

The external composition creates and owns AcquisitionCoordinator and injects it through init(session:plan:policy:acquisition:coordinator:prepare:). ColdFeedBootstrap never fabricates a coordinator. The composition guarantees that coordinator, snapshot and InitialProductionSlice operate over the same runtimeDatabase; no identity-validation mechanism or additional owner is introduced. InitialProductionSlice is constructed from acquisition.runtimeDatabase. The bootstrap imports Publication only for PublicationSchemaVersion and AnchorPlacement value types; it never calls Publication producers/stores directly.

Caller-supplied Edition/Segment IDs, seeds, schema version, three finite dates and anchor placement survive the acquisition gap unchanged. Preparation owns card IDs. Atomic initial publication remains the sole first-Edition creation path. Success invokes only FeedSession.restoreLocalPresentation to install the exact new Edition and requested finite window capacities, without another checkpoint write. Bootstrap stops after the first visible presentation; FeedRunwayDriver owns steady-state thereafter.

C6 establishes real G1 work in the injected coordinator with a local URLProtocol request suspended on an AsyncStream signal. It advances durable authority to G2, then publishes a coherent G2 registration/snapshot. That snapshot supplies G2 eligibility while the same coordinator still reports G1 active. Both the pure planner proof and ColdFeedBootstrap return activeGenerationConflict, rather than staleConfigurationGeneration. No replacement request executes. Releasing G1 proves the existing Admission generation fence rejects its batch with staleGeneration(expected: 1, actual: 2), leaves canonical supply/checkpoint unchanged and removes the active execution. No sleeps, production hooks or private-state access are used.

BootstrapPlanTests proves all six demand/plan contracts. ColdFeedBootstrapTests covers C1–C22 with real temporary RuntimeDatabase, FeedSession, local slices, target authority, snapshot, planner, coordinator, Syndication/URLSession/local URLProtocol, transactional Admission and durable publication/session history. The full cold-loop test calls only bootstrap.run after configuration. Additional proofs cover all three finite dates, context validation, exact restore identity, a nonexhausted second miss and static finite control flow. UpToDate/checkpoint-only tests introduce independent canonical supply during transport, proving that absence of an acquisition selectable-change receipt prevents a second local attempt even when it could publish.

No schema, migration, package, Persistence, Runtime, Editorial, Media, Publication, Syndication, Runway or UI implementation changes are part of 3P2. Loading/skeleton UI, FeedScreenStore wiring, persistent catalog, target reconciliation, background refresh, media network preparation and successor Edition refresh remain unstarted. The next gate is not started.

### Core invariants

Cold bootstrap is a finite bridge to the first usable Edition, never an alternate permanent feed-production strategy.

Existing canonical local supply is always attempted before external acquisition.

External bootstrap acquisition is legal only after the bounded local structural attempt reports exhaustion.

A bounded local attempt that made no publication but did not prove exhaustion never triggers remote work.

Bootstrap acquisition has an explicit semantic purpose distinct from reader continuation.

Bootstrap has no target card count, page size, timer, deadline or retry loop.

External acquisition changes canonical supply only; InitialProductionSlice remains the only cold-bootstrap path that creates the first Edition.

After acquisition changes selectable supply, bootstrap restarts local selection from the canonical head exactly once.

A bootstrap call never performs a second acquisition round.

The durable first Edition/session transaction remains the publication authority introduced in 3P1.

## Phase 3Q1 — shared AcquisitionCoordinator ownership (complete)

Phase 3Q1 — implemented and verified. External composition creates and owns one AcquisitionCoordinator per shared lifetime and injects that same instance into ColdFeedBootstrap and FeedRunwayDriver. Coordinator, SyndicationAcquisitionSnapshot and local production use the same RuntimeDatabase; that relationship remains a composition responsibility without artificial database-identity checks. FeedRunwayDriver now requires coordinator: AcquisitionCoordinator and passes it unchanged to RunwayAcquisitionCycle. Neither consumer constructs its own coordinator or offers a factory-calling initializer. SyndicationAcquisitionSnapshot.makeCoordinator() remains the explicit external creation point.

Ownership alone changes: restoreAndActivate, activateCurrentPresentation, submitViewport and drive retain their existing behavior. RunwayController remains authority for pending intents, acknowledgements and progression; AcquisitionPlanner retains generation/eligibility/conflict rules, and durable stores retain transactional authority. Cold bootstrap remains finite. No schema, migration, publication/checkpoint semantics, generation policy, UI, catalog, timer, retry, cache, fallback, scheduler or additional ownership mechanism changes.

FeedRunwayDriverTests adapts its two existing initializer callsites and adds Q1/Q2/Q4. Q1 passes the fixture's single real coordinator to both consumers, observes cold work through it and hands the resulting same-database presentation to the driver. Q2 suspends real G1 transport, durably reconfigures to G2, then publishes coherent G2 eligibility. Cold and the driver receive the same still-active coordinator; the driver preserves the pending intent and starts no replacement request. The existing RunwayAcquisitionCycle returns deferred(activeGenerationConflict) for that exact intent with the same coordinator. Releasing G1 proves Admission still rejects staleGeneration(expected: 1, actual: 2). No stale-configuration rejection substitutes for the active conflict, and no sleeps, polling or production hooks are used. Q4 checks that both consumer source files contain no coordinator factory/construction. Existing Runway suites and the unchanged ColdFeedBootstrapTests, including C6, are rerun.

Sequence completed: 3P2 atomic cold presentation installation → 3Q1 shared acquisition ownership. Presentation/UI composition remains a later reviewed gate and is not started. This phase introduces no application container or UI wiring.

## Phase 3Q2 — feed presentation state boundary (complete)

Discovery confirmed that FeedScreenStore, FeedScreen, FeedCardView and FeedLoadingView are scaffolds. FeedSessionUI is also a scaffold; existing Runtime snapshots/cards/anchors and ViewportObservation already implement the published presentation and viewport contracts. The concrete gap was a UI-consumable absence/work/failure state that preserves an existing presentation.

FeedPresentationState is the sole new UI production value, over an optional unchanged Runtime snapshot and explicit caller work facts. Pending, unavailable, deferred and failed retain the snapshot; a new same-Edition/context window preserves exact published order and the supplied anchor, while identity replacement is rejected. Finite window edges never declare global exhaustion. No store, effects, UI production strategy or autonomous work is added. [The presentation contract](RUNTIME_PRESENTATION_CONTRACT.md#11-feed-presentation-state-boundary--phase-3q2) records the API and state meanings.

FeedPresentationStateTests adds 12 real-snapshot state tests under the existing ArchitectureSmokeTests target, without manifest changes. T10 reruns cold bootstrap, driver and Runtime regressions. Phase 3Q2 completes only the presentation state boundary; FeedSessionUI / FeedScreenStore execution wiring, SwiftUI rendering, navigation, persistent catalog, target reconciliation and successor Edition refresh remain unstarted. The next gate is not started.

## Phase 3Q3 — explicit presentation handoff and viewport bridge (complete)

Discovery confirmed that Runtime already creates snapshots, cold and continuous owners already execute production, and FeedPresentationState already provides exact reception/work reporting. Composition lacked only typed result interpretation and explicit viewport forwarding. FeedPresentationHandoff closes that gap with stateless functions; it introduces no instance, stored state, coordinator, history, cursor, scheduler or new presentation model.

Warm/continuous snapshots are delivered unchanged; nil preserves the complete prior state. Cold and Acquisition outcomes map only factual settled work conditions, with published cold snapshots received before reporting idle. Acquired selectable supply alone is not visual success. Viewport forwarding invokes the existing driver once with exact observation/activity/resources; Runtime retains movement, capacities, anchor and production authority. Errors propagate, and callers can report failure without discarding presentation. [The handoff contract](RUNTIME_PRESENTATION_CONTRACT.md#12-explicit-presentation-handoff-and-viewport-bridge--phase-3q3) specifies these mappings.

FeedPresentationHandoffTests adds 16 focused real-component and pure-mapping tests; H12 reruns cold bootstrap, driver, UI state and Runtime suites. Package/schema, UI, Runtime, Acquisition, Publication and all existing production owners are unchanged. Phase 3Q3 completes presentation handoff only; FeedScreenStore/FeedSessionUI wiring, SwiftUI rendering, navigation and background/successor work remain future gates. The next gate is not started.


## Phase 3Q4 — minimal MainActor feed screen store (complete)

Discovery confirmed that FeedScreenStore was only a scaffold, while FeedPresentationState and FeedPresentationHandoff already implement the state and delivery contracts. The remaining gap was native screen observability and explicit semantic input returning to external composition. Swift 6 and the existing iOS 18/macOS 14 platform declarations support Observation without package changes.

FeedScreenStore is now a MainActor Observable class holding exactly one FeedPresentationState. install(_) uses receiving(_) and reporting(_) for existing identity/work semantics; a missing snapshot cannot clear visible content, and invalid Edition/context delivery fails before observable mutation. submitViewport(_:activity:) synchronously forwards exact Runtime values to an injected MainActor callback. No external operation is automatically started, and the store owns no Runtime session, resources or parallel semantic state.

Composition can create the store, compute warm/cold/continuous state through FeedPresentationHandoff, install it, receive a user viewport callback, explicitly invoke the existing driver handoff and return its state. That execution and async lifecycle remain external; this phase implements the narrow observable/intent contract only. FeedMineUI does not import Composition or any production/storage modules. ArchitectureSmokeTests already supports the integration fixtures.

FeedScreenStoreTests adds 15 tests covering S1–S13 plus no-snapshot preservation across all work conditions. Real temporary publication and FeedSession provide snapshots; withObservationTracking demonstrates actual synchronous observation without sleep or polling. S14 preserves the existing state/handoff/cold/driver and Runtime regressions. Exactly one production file and the three authorized documents change. FeedScreen, FeedCardView, FeedLoadingView, complete application wiring and the next gate remain unstarted.
