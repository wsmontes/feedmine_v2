# Acquisition contracts and durable target architecture

## 1. Scope and current state

Phase 3L — complete (design only). Base: Phase 3K4, `b77e8e3324bac7428207bfd9cc7af605c4cbc3b5`. This document chooses future boundaries; Target authority is now implemented by 3M1 as recorded below; Batch and Admission are now implemented by 3M2; Planner is now implemented by 3M3; The bounded Connector and shared Coordinator surfaces are now implemented by 3M4. No Swift, tests, package graph, schema or migration changes are authorized here. Phase 3M1 is now complete; Phase 3M2 is complete; Phase 3M3 is complete; Phase 3M4 is complete; Phase 3M5 is now complete as recorded below. See the completion record below for implemented authority.

Already implemented: AcquisitionDemand in Acquisition, RunwayAcquisitionIntent in Runtime, canonical ContentStore authority, Domain Source/SourceBinding, OriginRecord/immutable OriginRevision, and canonical MediaCandidate facts. AcquisitionPurpose currently has only readerContinuation. BootstrapPlan, SyndicationConnector, SyndicationTranslator and SyndicationHTTP are still scaffolds. AcquisitionCoordinator and FeedConnector now implement the 3M4 bounded shared execution boundary. AcquisitionPlanner now implements the 3M3 pure bounded planning boundary. AdmissionPolicy now implements the 3M2 semantic admission boundary.

At the 3L design base runtime.sqlite owned publication/session, canonical supply and media candidates, without AcquisitionTarget or checkpoint authority. 3M1 now adds target/checkpoint authority; there is still no batch ledger or source/binding registry. catalog.sqlite is not implemented. The path being designed is demand → pure planning → bounded target work → connector → protocol-free batch → transactional admission → canonical supply → semantic local-supply-changed fact. Acquisition does not choose Selection, prepare media or publish.

> Source is editorial identity. SourceBinding is declarative external association. AcquisitionTarget is operational work. They are not interchangeable.

> Acquisition increases future canonical supply. It never publishes feed history.

> Connector output becomes protocol-free before transactional admission.

> Cancellation is an optimization. Transactional admission is the stale-work correctness authority.

## 2. Source vs SourceBinding vs AcquisitionTarget

Source is a FeedMine editorial identity, not an endpoint. SourceBinding is declarative external association: SourceBindingID, SourceID, external principal, aliases, explicit generation and enabled/revoked authorization. Its connector kind is derived from the principal; it does not represent running work.

AcquisitionTarget is one durable operational work identity. It is neither SourceID nor SourceBindingID, a URL, catalog row, endpoint hash or connector namespace/value. A target can serve many Sources/Bindings; one binding can later materialize multiple targets (for example backfill and live). A shared relay/filter or operationally equivalent syndication target can be reused. The target primary key therefore cannot enforce one Source = one Target. Membership remains explicit observation claims; merely fetching a shared target enrolls content into no Source.

## 3. Durable target authority

**Q1 — durable facts.** Choose one future runtime.sqlite table, `acquisition_targets`, with one row per target. Conceptual fields: id, connector_kind, generation, state, checkpoint_revision, and optional checkpoint_blob/checkpoint_schema/checkpoint_connector_version. Checkpoint metadata is absent together when no checkpoint exists; a present envelope validates its schema/version even if the connector's blob is empty. The opaque envelope is the only allowed blob, not a generic target configuration payload. Exact SQL types/checks and migration names are a 3M1 implementation review concern.

Do not store endpoint URL, host, path, username, relay, feed_url or account fields here. Do not add source/provider/binding/catalog tables, diagnostic updated-at timestamps without a consumer, fetch status, leases, batch ledger or supply generation. No acquisition schema is implemented by 3L.

runtime.sqlite is nonreplaceable semantic runtime plus future target/checkpoint authority. catalog.sqlite stays a replaceable/read-mostly future catalog. Validity and resumption survive restart independently of reconstructible catalog information.

## 4. Target identity/generation/state

Choose a future UUID-backed nominal AcquisitionTargetID, FeedMine-owned, following existing nominal identity conventions. Place the identity in Domain so Persistence and Acquisition can refer to it without a dependency cycle; Acquisition owns its semantic Target value. ID allocation is explicit, never hash(URL), SourceID, SourceBindingID or an external tuple. Configuration changes keep the TargetID.

Baseline durable states are **enabled** and **revoked** only. Fetching, failure, cooldown, retrying, backoff, paused and finished are not durable target states. An authorization suspension uses revoked; explicit reauthorization uses enabled with a new generation.

**Q3 — generation events.** Semantic changes to represented transport configuration, authorization, external association/membership meaning, connector kind, or checkpoint compatibility advance the same target's generation atomically. Revocation and re-enablement also advance it so old work cannot become valid again. Repeating the same state/configuration is not an advance. No wraparound/reused generation is permitted; overflow must be refused. Only target generation and checkpoint revision are needed in the Acquisition authority baseline. Existing SourceBinding.generation remains declarative Domain data, not a second admission stamp/counter.

Checkpoint compatibility on reconfiguration is explicit: preserve a compatible envelope or clear/replace it in the same target update. Any checkpoint change advances checkpoint revision; generation does not reset either revision to zero. No leaseEpoch, bindingRevision, SupplyGeneration or second correctness epoch is proposed.

## 5. Checkpoint ownership and CAS

Checkpoint is connector-owned opaque resume state: blob, serialization schema and connector version. Core validates the envelope, stores it and returns it only to the matching connector; it never decodes protocol tokens. No checkpoint and a connector's explicitly empty checkpoint are distinct. No proposed next checkpoint means preserve the existing one.

> A checkpoint that describes admitted content advances in the same runtime.sqlite transaction as that admitted content.

**Q5 — atomic CAS.** Every batch carries target ID/generation and expected checkpoint revision. Inside the serialized writer transaction, require the exact enabled target, matching generation and matching checkpoint revision before canonical mutation. If a next checkpoint is supplied, install its envelope and advance revision once as part of that transaction. A checkpoint-only/empty-observation batch is legitimate and must follow the same checks. A refused or failed batch advances neither checkpoint nor content. A proposal using an old revision is refused, including a lost-response re-delivery after successful checkpoint advancement; it is not silently treated as an accepted new proposal.

Neither validate → committed content → committed checkpoint nor committed checkpoint → later content is permitted. No catalog/runtime cross-database transaction is required. Final CAS representation and typed failures belong to 3M1/3M2, without clocks/default retry policy.

## 6. Catalog/binding boundary

**Q2 — reconstructible facts.** Future catalog/binding integration supplies target eligibility for a context/revision, connector-specific configuration, sharing/materialization associations and declarative source/provider metadata. 3M fake tests explicitly supply eligible target snapshots and connector fixture mappings; they require no catalog.sqlite, binding store or endpoint discovery.

A separate integration gate will map SourceBinding to connector-specific target configuration. In that gate, configuration cannot be exposed to execution as current until runtime target authority has advanced generation or revoked obsolete work. Shared-target changes must fence the affected operational target, even when multiple bindings refer to it. Commit the runtime fence before enabling the changed mapping; an interrupted update may conservatively refuse work but cannot admit obsolete semantics. Admission reads only runtime target/canonical authority in its transaction and never joins catalog.sqlite. 3L does not decide Syndication endpoint representation or authorize any catalog tables.

## 7. Demand acknowledgement

**Q11 — exact acceptance point.** Acquisition accepts a semantic demand when its execution owner has either reserved a finite bounded plan (including joining an already owned same-target execution) or conclusively classified it as currently unserviceable with an explicit reason. Only after that acceptance result does Composition acknowledge the exact RunwayAcquisitionIntent. Merely observing the Runtime action is not acceptance. Acknowledgement means ownership, not successful network/content admission.

No eligible target is currently unserviceable; resource denied means work exists but cannot execute under current explicit permission. Neither implies permanent remote exhaustion. If Acquisition has not accepted responsibility, do not acknowledge; Runtime retains its coalesced outstanding intent. Acquisition does not import Runtime or accept the Runtime wrapper as its core contract.

Reconsideration is event-driven: explicit eligibility/configuration changes, new resource permission, user/reader semantic opportunities, and committed supply receipts permit a separate decision. An accepted unserviceable result is retained only as transient ownership/disposition, not a polling queue. Changed Acquisition inputs may cause its owner to evaluate a separate bounded plan for the accepted need; they do not manufacture Runtime supply arrival or repeatedly request acknowledgement. New Runway observations/supply changes retain 3K4 invalidation semantics. Completion, ack, failure or disconnect alone never schedule automatic re-demand/reconnect. No timer, sleep, attempt counter or retry loop is the bridge.

## 8. Planner and bounded work

**Q12 — minimal baseline.** A pure Planner accepts AcquisitionDemand, an explicitly eligible finite ordered collection of target snapshots, explicit physical resource permission/capacities, and current active target facts when needed for sharing. It returns one immutable finite AcquisitionPlan or an explicit currently-unserviceable/resource-denied disposition. The snapshot includes exact ID, connector kind, generation/state and checkpoint facts. Eligibility is upstream; Planner does not query stores, open catalog, traverse Sources, resolve endpoints or execute connectors.

Use supplied order and at most one work entry per target/generation; reject inconsistent duplicate snapshots rather than guess. Respect explicit target-work and batch/observation/byte capacities. A zero denied budget produces no execution. These are physical/privacy work bounds, not desired cards, page count or fetch quantities inferred from requiredCards. Do not freeze target counts, host counts, default budgets, clocks or deadline values. Host/request policy for real transport remains a later gate.

No persistent AcquisitionFrontier is needed: one immutable bounded plan plus transient active executions suffices for the fake consumer. No head/active/exploration classification or speculative purpose is copied. If continuous fake proofs reveal a genuinely missing transition, review it before adding a new owner/state machine.

## 9. FeedConnector boundary

FeedConnector will be one small Sendable protocol in the Acquisition boundary. Connector modules implement it using their own transport/configuration. Composition supplies the concrete connector association; generic Acquisition never switches on connector kind or discovers a registry. This is not UniversalPlugin, UniversalTransport or a network scheduling framework.

Direction: one bounded asynchronous pull/request accepts target work stamp, matching opaque checkpoint and explicit work bounds, and emits one protocol-free event: batch, finished, upToDate, cancelled or disconnected; connector failure is separately reported. Final signatures are a 3M4 gate. A pull permits backpressure: request the next event only after Admission settles the previous one and remaining explicit work capacity permits it. No unbounded stream queue or dropping unadmitted observations to advance a checkpoint. Fake connector fixtures own their target-to-script mapping; ID/kind/generation are sufficient without endpoint configuration.

## 10. AcquisitionBatch

A future immutable batch carries target identity/generation, expected checkpoint revision, a finite collection of protocol-free observations and an optional next checkpoint. Do not add mandatory batchID, fingerprint/ledger key, binding revision, lease epoch or closures by analogy with legacy.

Each observation groups external object identity, external version identity when known, canonical text/time/link/language facts, supported provider attribution, explicit membership claims and ordered media candidate claims. Translation completes before Admission. Only current Domain/storage consumers enter the baseline: no giant relation/entity/cluster/interaction-offer contract or raw evidence framework is imported. Provider attribution uses an explicitly supported ProviderID supplied by upstream facts; no provider registry is invented in runtime. Media claims describe declared candidates, not prepared/fetched bytes.

RSS/FeedKit objects, Mastodon types, ATProto records, Nostr events, GRDB rows and interpretation closures never cross Admission. Protocol-specific rules become explicit generic precedence facts (make accepted representation current versus historical-only); opaque external version strings are identities, not a globally ordered revision clock. Connector names external identities and claims; Admission allocates/resolves OriginRecordID, OriginRevisionID and MediaCandidateID. It never requires a connector to manufacture SQLite identities.

## 11. Transactional Admission

**Q9 — smallest API/refactor.** Acquisition owns semantic shape/precedence validation and orchestration. Persistence owns the actual writer transaction and final stale-work validation. The existing dependency Acquisition → Persistence is preserved; Persistence → Acquisition is forbidden. Introduce later one concrete Persistence admission operation over Persistence-owned mechanical records/commands (Domain IDs/values and neutral checkpoint envelope). Acquisition maps semantic observations to those commands; no public GRDB Database, callback transaction API or Repository protocol is needed.

The operation opens exactly one RuntimeDatabase.write transaction, resolves identities within that transaction, and invokes the existing `ContentStore.apply(_:in:)` canonical mutation body. That internal body already performs no nested transaction. Add only the necessary internal identity-resolution reads/mapping; if extracted for reuse, one internal shared helper replaces the body rather than introducing a second writer. Public commitCanonicalChange and wider admission share identical canonical validation, immutable payload/media replay, current pointer, membership and selection_supply refresh code.

**Q4 — admission authority.** Atomic sequence:

1. Load exact target; require enabled; compare target generation and expected checkpoint revision.
2. Resolve exact external object identity and existing/new FeedMine record.
3. Resolve/create/replay immutable revision and its complete ordered media collection.
4. Apply explicit admitted precedence/current-pointer expectations, availability and membership claims.
5. Refresh selection_supply via the existing writer.
6. Install a supplied checkpoint and advance its CAS revision.
7. Commit and return the factual receipt.

A batch may contain several observations; all are admitted or none are. Any identity/payload/current-state conflict, revocation, stale stamp, CAS mismatch or storage failure throws/refuses the complete transaction. Resolve expected current state from the transactional record, not an obsolete plan snapshot; validate the explicit precedence semantics there. No protocol parsing occurs in Persistence. No two/three committed Store operations can substitute for this one transaction.

## 12. Identity resolution and replay

**Q6 — stable canonical identities.** Use current BINARY structural external object uniqueness `(connector_kind, namespace, value, role)` to find the existing OriginRecordID. Allocate a FeedMine nominal UUID only if absent; never derive it from URL/hash/Source. For a known external version, use existing per-origin unique version tuple to recover the existing OriginRevisionID before invoking the canonical writer. A version reused on another object is distinct. Resolve media candidates from the existing revision's ordered collection on replay; allocate local IDs only for a genuinely new revision/candidate collection.

**Q7 — exact replay.** Known object/version plus identical admitted representation reuses stored record/revision/media IDs and immutable values. Compare all supplied semantic payload and ordered media facts, not just version spelling; different content for the same version is conflict, not overwrite. Preserve the stored immutable observedAt on repeat observation and use separately supplied time for OriginRecord.lastObservedAt/membership observation metadata. Exact replay does not move the current pointer back to an older version. Explicit historical-only insertion does not become current; changed representation uses a new version/revision under admitted precedence semantics. Local observation time alone is not a new content version.

When upstream has no version, use exact semantic equality with the current admitted representation (including media claims) to reuse the current revision; do not invent an external version/hash. A materially changed unversioned representation may create a new immutable UUID revision when explicitly eligible to become current. An ambiguous historical unversioned replay cannot be identified by the current schema's version index: refuse unsupported historical/ambiguous precedence in the first admission contract rather than promise durable historical deduplication or silently fabricate identity. 3M2 must freeze/tests these supported cases. A re-delivered batch after checkpoint advancement fails old checkpoint CAS, preserving state even if the caller lost its receipt.

**Q8 — no durable batch ledger baseline.** Canonical unique identity/version replay, target fencing and checkpoint CAS already preserve effects for the supported baseline. A lost response after commit yields an old CAS refusal, not a second content/checkpoint advance; replay without a checkpoint can reuse an exact admitted representation. There is no current consumer requiring recovery of a historical batch receipt or exact-once external side effect. Such a consumer, or historical unversioned event deduplication, would need a separate evidence-backed gate, not an automatic acquisition_batches/fingerprint table. No batch ledger is proposed here.

## 13. Stale work / revocation / cancellation

Generation 1 starts → target is revoked or config changes atomically to generation 2 → old result returns → writer transaction refuses generation/state before canonical/checkpoint writes. Timely cancellation is unnecessary to this proof. Admission must also reject stale expected checkpoint revision; a competing accepted batch cannot be silently overwritten.

Cancellation saves resources; it does not revoke durable authority, roll back committed history or permit stale content. Coordinator may request cancellation on config/revoke or absent consumers, but the durable fence remains sufficient even if the connector returns late. Cancellation alone, with still-current target/checkpoint, is not a different durable correctness epoch. No leaseEpoch is necessary.

## 14. Finite and continuous acquisition

**Q13 — one contract.** Finite emits one or more bounded batches then finished; continuous emits bounded batches until an explicitly controlled cancel/disconnect; backfill-to-live uses the same batch/checkpoint transition and later pulls. No Selection, Publication or Runway branch knows these transport modes. finished and upToDate are attempt results, not permanent target lifecycle states; a later explicit opportunity may legitimately revisit the target.

**Q14 — transient coordinator state.** One future coordinator actor owns active execution records keyed by target, generation, current consumer interests and remaining explicitly bounded plan work. Same target/current generation shares one execution across demands/contexts, not one actor per Source/catalog row. If old-generation execution is still unwinding, stop offering it to current consumers and await its settlement before starting a replacement; do not run two external executions for one target. Each next pull uses the durably admitted checkpoint revision; one pull's Admission settles before continuation.

Durable state is only target identity/kind/generation/enabled-or-revoked and checkpoint/CAS authority, alongside canonical content. No persisted fetching/failed/finished/frontier/lease or attempt usage is required. Memory interests disappear on restart; the next explicitly accepted plan resumes from durable checkpoint. No retry, backoff, jitter, periodic cadence, deadline machinery or automatic reconnect is in the first fake coordinator.

## 15. Supply-change handoff

**Q10 — receipt.** AdmissionReceipt direction: targetID, checkpointAdvanced and selectableSupplyChanged. The last fact is true only when candidate-visible structural supply materially differs after the committed transaction: projection/current selectable revision or relevant memberships, not solely last-observed timestamps or a replay. Compare affected origins' before/after candidate-visible projection and memberships inside the transaction, aggregated once per batch. No frozen diagnostic counters without consumers and no global SupplyGeneration.

Acquisition does not import Runtime or call RunwayController directly. Composition/execution owner observes committed receipt, determines relevant active scope(s) and calls noteLocalSupplyChanged with their exact scope. This clears outstanding/acknowledged shortage evidence, reopens local head consideration and preserves older progress fairness. A checkpoint-only or unchanged canonical replay need not notify supply change. Receipt is returned only after commit; failed/refused work never signals fake arrival. Admission never appends publication; a later separate LocalProductionSlice consumes newly visible canonical supply.

## 16. Failure semantics

| Fact | Meaning and effect |
| --- | --- |
| No eligible target | Demand accepted but currently unserviceable; not permanent Internet exhaustion. |
| Resource denied | Eligible work exists; explicit permission/capacity prevents execution now. |
| Connector failure/disconnect | This event admits nothing; earlier committed batches remain; no automatic retry/reconnect. |
| Connector upToDate/finished | Attempt result; no mutation without a batch, no permanent target tombstone. |
| Stale generation/revoked target | Admission refused before writes; cancellation timing irrelevant. |
| Checkpoint CAS mismatch | Refused; preserve actual checkpoint/canonical content; use a later explicit decision. |
| Canonical/precedence conflict | Entire batch refused/failed atomically, no payload overwrite or partial checkpoint. |
| Storage failure | No partial canonical/checkpoint commit; report failure, never empty supply. |

Transport or storage failure is not evidence that the Internet has no more content. Runway cannot turn these results into permanent remote exhaustion. Failure reporting and demand ownership are separate from successful selectableSupplyChanged.

## 17. Legacy evidence: preserve/reject

Read-only directed review: `wsmontes/feedmine-dev`, branch `fix/release-1.0-final-hardening`, commit `712a6ba93c6a8ab28c3b3c0e2b2777d1e3341d0c`. All nine requested files were read via git show; no working-tree code copied. Paths below are relative to `Packages/FeedRuntimeV2`.

| Reviewed file | Concrete evidence | Decision |
| --- | --- | --- |
| Sources/FeedDomain/Canonical/AcquisitionBatch.swift | AcquisitionObservation groups translated payload/claims; ConnectorCheckpoint is opaque; TargetStamp has generation, bindingRevision, leaseEpoch and checkpointRevision; ledgerID/fingerprint and receipt supplyGeneration add several mechanisms. | Preserve protocol-free grouped observations and checkpoint/CAS intent. Reject giant claims/evidence contract, batch ledger and parallel stamp counters. Choose nominal UUID target identity instead of its opaque String baseline. |
| Sources/FeedStorage/Admission/AcquisitionTargetStore.swift | register writes target + separate checkpoint rows; snapshot joins them; setState bumps lease epoch; binding revision independently changes. | Preserve durable validity and checkpoint snapshot, refuse late obsolete work. Simplify to one table, enabled/revoked, target generation plus checkpoint revision; no clock/configuration blob or lease epoch. This file evidences target storage, not a proof of the unreviewed legacy AdmissionEngine transaction. |
| Sources/FeedRuntime/Acquisition/AcquisitionPlanner.swift | Value planner reads explicit demand/frontier/usage; PurposeBudget baseline includes fixed counts/deadlines and items from deficit. | Preserve pure explicit-input bounded planning; reject default budgets, expanded purposes, desired fetch count and deadline policy. |
| Sources/FeedRuntime/Acquisition/AcquisitionFrontier.swift | Target separate from editorial identity; mutable ordered/running/finished state classifies head/active/exploration with default bounds. | Preserve operational target independence and sharing direction; use immutable finite plan instead of frontier/classification state. |
| Sources/FeedRuntime/Acquisition/AcquisitionCoordinator.swift | AcquisitionSource.pull returns batch/finished/upToDate/cancelled/disconnected; inFlight shares refill waiters by target; revoke leaves late work for Admission; runWorkItem includes usage/deadline loops and consecutive replay counter. | Preserve common finite/continuous pull boundary, same-target sharing and cancellation ≠ validity. Reject source adapter duplication, lease/accounting/frontier machinery and giant coordinator; future Admission transaction is explicitly required by this design. |
| Sources/FeedRuntime/Acquisition/AcquisitionBudgetPolicy.swift | Pure budget(baseline, conditions), network/resource denial and monotonic reductions; floors source/concurrency at one and carries deadline/speculation. | Preserve caller-supplied physical resource inputs and honest denial. Reject fixed floors/deadlines/speculative behavior without consumer. |
| Sources/FeedRuntime/Acquisition/SourceDemandLedger.swift | Endpoint-keyed inFlight/refilledAtMs, freshness window, grant led/shared/servedFresh and counters. | Preserve goal of sharing active work; reject second endpoint/freshness ledger and counter system. Target coordinator is the only external execution owner. |
| Tests/FeedRuntimeTests/FakeFiniteConnector.swift | Scripted pages, checkpoint proposals, replay/error and onPull hook for revoke/cancel without sleeping. | Preserve deterministic finite batch/finish and explicit event release, fake proof before network; no ledger/version-ladder infrastructure copied. |
| Tests/FeedRuntimeTests/FakeStreamingConnector.swift | Scripted burst/replay/olderRevision/discontinuity, bounded mailbox and continuation-based parked observation. | Preserve continuous/bounded backpressure and late-result proofs without wall-clock polling. Plan minimal explicit-control FakeContinuousConnector; no production task/mailbox framework copied. |

Rejected baseline: SourceDemandLedger, SupplyGeneration, leaseEpoch, bindingRevision + targetGeneration correctness stamps, persistent frontier, fixed head/active/exploration counts, default target budgets, attempt/replay counters, deadlines, retry/backoff/jitter/cadence, generic network scheduler, universal HTTP transport, giant coordinator and batch ledger. No present invariant needs an additional correctness counter.

## 18. Bootstrap relationship

Bootstrap is a separate future cold-start consumer, finite and ending once first presentation can be established from canonical/local publication. It must not become permanent feed strategy. It reuses Target/Connector/Batch/Admission, potentially with different explicit physical budgets. AcquisitionPurpose.readerContinuation remains the only implemented purpose; no .bootstrap is added and BootstrapPlan stays scaffold. No bootstrap implementation is required for 3M1/3M2 or fake contract proofs.

## 19. Explicitly deferred behavior

No TargetID/value/schema/checkpoint store, Batch/Observation/Admission code, Planner/Frontier/Coordinator/FeedConnector, fake connector or catalog integration is implemented by 3L. SourceBinding persistence/materialization is a separate explicit gate. Real Syndication endpoint representation, HTTP/URLSession/FeedKit, ETag/Last-Modified/redirects, network host/privacy policy, retry/backoff, background scheduling, UI, FeedSession wiring, raw evidence retention and external interaction execution remain deferred.

After 3M prefer 3N — Syndication architecture/implementation (real HTTP/FeedKit/validators/translation), then Runtime/FeedSession/Composition wiring with the real supply loop, then UI/default-runtime migration. The fake 3M5 composition harness is a contract proof and does not require production FeedSession wiring before Syndication.

## 20. 3M implementation gates

These are concrete future review gates, not authorization to start 3M.

| Gate | Scope and owner | Required proofs / exclusions |
| --- | --- | --- |
| 3M1 — durable target/checkpoint authority | Domain nominal UUID TargetID; Acquisition semantic Target; Persistence one runtime acquisition_targets table, exact register/read/config-update/revoke and checkpoint envelope/CAS authority. | Reopen preserves ID/kind/state/generation/checkpoint; same ID on config change; stale expected generation refused; revoke/re-enable fences old work. No content admission, planner, connector, catalog or network. |
| 3M2 — protocol-free batch + transactional admission | Acquisition minimal observations/stamp/precedence/receipt; one Persistence concrete writer operation reusing internal canonical writer; transactional external identity resolution and checkpoint CAS. | Exact version/current-unversioned replay, changed representation, no spurious media/revision IDs, stale generation, revoke → late batch, CAS conflict, multi-observation canonical conflict rollback and checkpoint rollback, empty checkpoint-only batch, factual selectable change. Reject unsupported ambiguous unversioned history. Fake values only; no connector execution/planner/catalog. |
| 3M3 — pure bounded planner | Demand + supplied eligible snapshots + explicit permission/work bounds (+ active facts) → immutable finite plan/disposition. | Deterministic supplied order, no duplicate target work, all work within explicit capacities, honest no-eligible vs resource-denied, active target sharing. No DB/coordinator/network/persistent frontier/default budgets. |
| 3M4 — FeedConnector + fake coordinator | Small single pull boundary; deterministic FakeFiniteConnector/FakeContinuousConnector; one coordinator actor owns per-target execution and routes batch to Admission. | Finite multi-batch/finish, continuous batch/batch/disconnect/cancel, same-target multiple demands share one execution, old result refused after revoke/config change, bounded backpressure, settled checkpoint passed to next pull, no sleeps/polling. No HTTP/retry/timer/backoff or per-Source actors. |
| 3M5 — fake supply-loop integration | Explicit composition harness: Runway intent → Acquisition ownership acceptance → exact ack → plan/fake execution → committed AdmissionReceipt → scope-aware noteLocalSupplyChanged → later LocalProductionSlice. | Admission changes canonical supply visible to next provider slice, shortage ownership cleared, local-first head/fairness resumes, scope-stale ack/notification refused, no publication inside Acquisition, no receipt on failure. Still no Syndication/network/UI/background timer/production FeedSession wiring. |

Do not combine gates when doing so mixes transaction, pure planning, external execution or presentation ownership. Phase 3M1 — durable target/checkpoint authority — complete. Phase 3M2 — complete; Phase 3M3 — complete; Phase 3M4 — complete; At the 3M4 completion gate, Phase 3M5 was not started; it is now complete as recorded below..


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

Phase 3N — not started

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

The owner imports only Acquisition and Runtime. It never calls reconsider, local production, candidate queries or publication, and owns no registry, database/catalog, defaults, clock, Task, timer, polling or background loop. Its sole loop walks the finite Planner work array. FeedSession/UI integration, real Syndication/network, catalog/SourceBinding mapping and concurrent target scheduling remain deferred; 3N is not started.

The exact FeedMineCompositionTests target is added with Composition, Domain, Persistence, Acquisition, Editorial, Publication and Runtime dependencies only. Its one test file uses real temporary runtime storage, target authority, Planner, Coordinator, Admission, RunwayController, PublicationHistory, PublicationCoordinator and LocalProductionSlice, with a local one-slot test connector and explicit event controls. Existing tests remain unchanged.

The full-loop proof creates one Edition/anchor, measures real ready-ahead zero, runs a real exhausted local slice, emits real Runway demand, admits a fake external batch transactionally, and observes a canonical candidate while publication still has one segment. The supply signal reopens local-first; only the test caller then reconsiders and runs the next real LocalProductionSlice, appending a second segment to the same Edition referencing the admitted revision. The original history/Edition remains intact; Acquisition itself publishes nothing.

Tests also prove acknowledgement before first pull, accepted unavailable, resource/conflict deferral, reuse of the same intent after an explicit resource change, stale-gate precedence over invalid Planner inputs, checkpoint-only/exact-replay non-reset, error-after-ack without redemand, prior commits/signals surviving later error, obsolete/deactivated scope notification safety, separate immediate signals and sequential settled plan traversal. Numbered test 7 (the snapshot-to-ack race) is omitted under the contract's explicit exception: no deterministic insertion point exists without a production synchronization hook. No such hook is added; stale-intent proof and existing Runway stale-ack tests remain authority. Numbered test 13 is proven through real Runway state, not a production journal/hook.
