# Continuous feed production + adaptive runway — Phase 3J

## 1. Scope

Design only. This gate closes the continuous local-production ownership model; it changes no Swift, tests, package graph or schema. 3J policy/controller/production value names below remain proposed future surfaces. The bounded Publication history facts described in the 3K1 completion record below are now implemented APIs. 3J design base: Phase 3I3, `2778291ef462ca33e56567bbb0322ee4b3c39355`. Phase 3J — complete. Phase 3K1 — bounded exposure + ready-runway history facts — complete. Phase 3K2 — one bounded local production slice — complete. Phase 3K3 — adaptive policy + minimal controller — complete. 3K1 implementation base: `31f409528eb16f1ef300716824e7656464d863c5`.

> The reader consumes stable local history while FeedMine continuously and adaptively prepares future local supply.

> Running out of published local runway is a product failure even if every individual subsystem is technically healthy.

> Scroll reports consumption pressure. It never commands fetching.

> Local canonical supply is consumed before remote acquisition demand is escalated.

The chosen baseline is measured ready-ahead coverage, separate bounded local slices, episode-local structural progress, and exact-revision automatic repetition suppression within the target Edition. Remote execution is downstream and deferred.

## 2. Current completed local pipeline

Canonical ContentStore admits immutable OriginRevision and MediaCandidate facts. CandidateProvider performs one caller-bounded structural query for Main or Source, preserving examined count, cursor and exhaustion; Search fails explicitly until its separate canonical FTS gate. Pure SelectionEngine receives one finite CandidateSupplyWindow and an explicit matching FeedPlan/ResolvedSelectionPolicy. Its 3E exposure behavior is currently no-op, not the future repetition rule described here.

MediaPreparation accepts one candidate and explicit local bytes/key/unavailable input, returning actual usable asset facts or semantic unavailable/unsuitable; corruption/storage errors propagate. Pure Runtime PublicationPreparation preserves Selection order, exact text/time and explicit presentation decisions. PublicationCoordinator alone creates or appends immutable history with caller-supplied IDs, seeds and times; its transactional tail validation remains authoritative.

FeedSession restores retained local presentation, owns logical anchor movement and saves only explicit checkpoint milestones. Existing ViewportObservation remains a logical PresentationAnchor only. RunwayPolicy and RunwayController now implement the 3K3 boundaries below; FeedPlanResolver remains a scaffold. No existing API is silently reinterpreted by this design.

## 3. Legacy evidence: preserve/reject

Directed read-only review: `wsmontes/feedmine-dev`, branch `fix/release-1.0-final-hardening`, pinned commit `712a6ba93c6a8ab28c3b3c0e2b2777d1e3341d0c`. Only the nine requested files were fetched; no code was copied or legacy repository mutated. Paths below are relative to `Packages/FeedRuntimeV2/`.

| Reviewed file | Concrete evidence | Decision |
| --- | --- | --- |
| Sources/FeedRuntime/Runway/RunwayController.swift | `observeViewport` uses estimator/cached offer; `refreshOfferIfStale` is separate. `pending` coalesces per Edition. Controller also owns offer cache, generation, attempts, tasks, tail states and ResourceGovernor. | Preserve cheap observations, coalescing and separate work; reject the composite actor and its retry/cache/generation machinery. |
| Sources/FeedRuntime/Runway/RunwayEstimator.swift | Separate stocks and unobserved availability; bounded latency samples and nearest-rank p95. `observe` computes distance from `materializedTailOrdinal` and uses pixel speed. | Preserve measured cost and stock separation. Reject window tail as ready runway and UIKit speed as domain pressure. |
| Sources/FeedRuntime/Runway/RunwayPolicy.swift | Pure hysteresis decisions, explicit buffer bounds; baseline comfortableDistance 24, demandDistance 8, itemLimitPerRefill 24, maximumRefillAttempts 3 and deadline 10,000 ms. | Preserve pure policy/explicit physical ceilings/hysteresis. Reject fixed card health targets, page semantics, refill deadline and attempt-count architecture. |
| Sources/FeedRuntime/Acquisition/SourceDemandLedger.swift | Endpoint-keyed led/shared/servedFresh grants, in-flight claims and freshness windows across producers, including backgroundDrip. | Preserve avoiding duplicate work as an invariant; reject endpoint ledger/freshness machinery in semantic Runtime demand. Target sharing belongs downstream. |
| Sources/FeedRuntime/Session/FeedSessionReducer.swift | `viewportChanged` shifts window and emits a coalesced replenish effect; refresh has a separate pending operation. Composition installs an Edition and materializes first cards. | Preserve logical position and deferred effects. Reject materialized-tail replenishment trigger and composition-driven position reset for normal append. |
| Sources/FeedRuntime/Session/RuntimeFeedSessionComposer.swift | `compose` acquires before Selection, consults supplyGeneration and active Edition, and `opening` maps both refresh and replenishment to successor. Comments describe repeated successor creation at idle launch. | Reject acquisition-first order, global active lookup, generation guard and successor-per-refill. Keep explicit prepared publication and visible predecessor during work as the new invariant, not a claim about all legacy paths. |
| Tests/FeedRuntimeTests/RunwayControllerTests.swift | `testScrollObservationPathNeverAwaitsSelectionNetworkOrDecode`, `testAFlingStartsExactlyOneRefillForTheEdition`, `testNoSupplyDoesNotLoopOrEraseHistory`, cancellation/buffer tests; failure test fixes three attempts. | Preserve cheap path, shared intent, honest failure and finite resource work. Reject page/checkpoint continuation as canonical exposure and fixed retry degradation. |
| Tests/FeedRuntimeTests/RunwayEstimatorTests.swift | Five stocks never summed; unobserved differs from empty; recent p95 changes pressure; reversal and anchor-preserving window-shift tests. | Preserve facts, uncertainty and reversal behavior; reject materialized-window distance and pixel-speed baseline. |
| Tests/FeedRuntimeTests/RunwayPolicyTests.swift | Pure thresholds/hysteresis, budget validation and fixed baseline expectations. | Preserve deterministic decision tests; reject freezing those baseline numbers as product health. |

The reviewed controller exposes an external refill port, but its implementation is outside the directed files: local-before-network and a unified background execution pipeline are not proven by that port or by the ledger's purpose enum. They are explicit new requirements below. Reject supply/exposure generation counters, giant tail state machines, hidden repository walks and PublicationToken/Epoch-era assumptions as baseline; no concrete invariant here requires them. Durable occurrence identity and current Coordinator semantics replace that older framing.

## 4. Presentation window vs ready runway vs canonical supply

Presentation window (`FeedWindow` / `FeedPresentationSnapshot`) is a disposable finite materialization around the anchor. `forwardCapacity` and `backwardCapacity` are only materialization bounds: neither desired runway, refill size, page size nor acquisition target. Never equate forwardCapacity with “keep this many cards ready”.

Published ready runway is the already-published, local, presentation-ready occurrences strictly ahead of the logical anchor in the visible Edition. Anchor placement alone does not change the count; the anchor card is excluded conservatively. Canonical OriginRevision/Candidate facts may become publication but are not runway. In-flight preparation also is not ready stock. Counts of these stocks are never added together.

Image occurrences qualify only through the explicit usable-local-image publication contract; text-only needs no media asset. Durable assets currently have no retention/eviction, and corrupt or missing published assets are integrity/storage failures, never silently counted as successfully revalidated images. A ready-stock history read does not decode/read every asset file; it relies on the durable publication/local-asset invariant and separately reported integrity failures.

## 5. Adaptive runway measurement

Future Publication semantic boundary exposes a narrow ready-ahead observation for explicit Edition + anchor card + caller-supplied probe bound. Persistence resolves anchor membership/position and enumerates only occurrence positions strictly after `(segmentOrdinal, cardOrdinal)` in publication order. Return `ReadyAheadFacts(editionID, anchorID, observedTail, amount)` where amount is `exact(n)` below the bound or `atLeast(bound)` when saturated. Unknown/read failure is distinct from exact zero. No PublishedCard payload/full-history Set or current FeedWindow count is required.

Minimum 3K1 gate: prove a bounded range seek across the existing `(edition_id, ordinal)` segment and `(segment_id, ordinal)` card indexes, selecting positions only, stop at the probe bound, one consistent read snapshot. Avoid reusing window materialization's whole-Edition segment validation. Explain/query-plan evidence must exclude walking historical prefix or sorting all history on each pressure signal. Add only a justified narrow index if this cannot be proven; no new runway table or denormalized generation is pre-authorized. Exact unlimited COUNT is not the baseline. A saturated observation is sufficient when its lower bound exceeds the policy coverage requirement; otherwise request a larger policy-bounded probe in separate work. A resource ceiling that prevents proving coverage returns uncertainty, not healthy runway.

Proposed pure `RunwayPolicy.evaluate(RunwayFacts, RunwayPolicyInputs)`:

- `ConsumptionFacts`: active same-Edition forward occurrence advances divided by explicit monotonic elapsed active seconds; stationary samples contribute elapsed time, reversals contribute zero new forward consumption, and a high-water position prevents counting rereads. Session/context switches and inactive gaps reset sampling. Unknown measurement is explicit.
- `ReplenishmentFacts`: bounded recent successful local episode-to-durable-append durations, including scheduling wait, zero-yield intermediate slices, preparation and storage, plus output counts; p95 duration is nearest-rank over a caller-bounded sample count. Failure/cancellation is a separate fact, not zero latency.
- `ReadyAheadFacts`: exact stock or saturated lower bound and its explicit anchor/tail association.
- `LocalEpisodeFacts`: cursor, windows/examined/selected/published counts, structural exhaustion, pending supply-change flag, deferred preparation facts and error, if any; availability is observed, not guessed from canonical archive size.
- `InFlightFacts`: active local intent, elapsed duration and work scope. Output is not promised ready stock; it suppresses duplicate dispatch.
- `ResourceFacts`: explicit permission for work, examined-candidate budget, local-byte budget and probe ceiling supplied by composition/resource scheduling.

For known observations let `r` be maximum forward cards/second among a bounded recent sample window (conservative observed burst rate); `L` be measured p95 end-to-end local replenishment seconds. Coverage requirement `D = ceil(r * L * safetyFactor)`. SafetyFactor >= 1 and a release margin in seconds are explicit policy inputs justified by latency variability and hysteresis. Enter pressure when exact stock < D; leave only with stock >= ceil(r * (L * safetyFactor + releaseMarginSeconds)). For r = 0 use explicit logical tail-approach/empty-stock pressure, not a fake positive rate. No fixed minimum card stock is introduced.

Example arithmetic only, not tuning: r=2 and L=3 require six cards before safety margin; r=4 or L=6 doubles that requirement. Same card count can thus be healthy or insufficient. A physical ceiling can bound admitted work/probe, but cannot redefine an unmet coverage requirement as healthy. No “always keep 20”, “refill 50”, “fetch three pages” or “200 cards buys time”.

Unknown rate/latency yields `coverageUnknown`: when the reader reports forward intent or stock is empty, permit one bounded local slice to establish facts, then reconsider on completion or another semantic change. Unknown facts never authorize remote escalation by themselves. Replenishment failure plus forward/empty pressure remains unsatisfied pressure with error, not an infinite retry. Resource denial defers dispatch while retaining pressure. Hysteresis's previous decision is an explicit input, not hidden mutable policy state. Time is supplied measurement/scheduling context; no periodic refresh timer is the engine.

## 6. Consumption/replenishment observations

Choose separate future `RunwayObservation(editionID, anchor, sampledAtMonotonic, activity)` with activity forward/stationary/backward/explicit-tail-approach, reported as logical consumption intent. No pixels, UIKit velocity or load-more command. Existing ViewportObservation stays unchanged. Runway observation submission is memory-only: retain latest accepted intent and coalesce a pending reconsideration. It performs no storage, CandidateProvider, Selection, media, publication or Acquisition work synchronously.

Asynchronous measurement work resolves accepted logical positions and crossed occurrence counts against immutable history, separately from submission; exact bounded sample data or explicit unknown enters ConsumptionFacts. For a jump exceeding the supplied counting budget, do not invent a speed from the truncated count: mark rate unknown and tail pressure explicit. Invalid/stale observations cannot overwrite current scope; placement changes do not count new consumption. Monotonic intervals <= 0 are rejected. Bounded samples belong to Runtime operational observation ownership, never the presentation snapshot.

> No viewport observation directly performs storage, selection, publication or network work.

This describes the new production-pressure path. Existing Phase 2H FeedSession.submitViewport may still read retained publication solely to materialize its local window; this gate neither removes that established read nor adds production I/O to it. No production measurement query is inserted into that call.

## 7. Local production slice

Future LocalProductionSlice receives explicit resolved production context: FeedPlan, matching ResolvedSelectionPolicy, target Edition/action, episode cursor, examined work budget, explicit prepared attribution/actions and presentation choices/local media inputs, caller-owned IDs/seeds/times and cancellation opportunity. RunwayController cannot resolve user policy/catalog, synthesize EditorialRevision or derive behavior from opaque PolicyVersion. FeedPlanResolver stays scaffold until real inputs and consumer are gated; no internal PolicyVersion(1), CatalogGeneration(1) or magic recency plan.

One invocation: at most ONE CandidateProvider.candidates call, bounded history exposure snapshot for those candidate revision IDs, ONE SelectionEngine.select call with explicit exposure facts, preparation of that result, and at most ONE Coordinator append/create action. Future Selection exposure eligibility needs a reviewed explicit input; it remains pure and does not drive history reads. Normal visible runway uses append only. Create is an explicit initial/transition request, not a refill fallback. All preparation inputs must align; no hidden canonical join/resolver is introduced to fill missing facts.

Explicit presentation policy chooses textOnly or local image before preparation. textOnly is ready without speculative remote media. A required image must be usable and exact-revision matched; unavailable/unsuitable propagates as unprepared work, never hidden text-only fallback. Baseline slice is all-or-nothing for its finite selected result on preparation failure, retaining an explicit bounded deferred-preparation fact. Future policy can choose otherwise only in a reviewed gate. Exact Selection order and frozen history remain unchanged.

Return progress and publication outcome separately. Advance cursor only after successful publication or an explicitly successful zero-selected slice; preparation/storage failure retains previous progress for retry/reconsideration at a later semantic opportunity. No inner refill, retry, candidate-collection resolution, “while short”, “until N” or multi-window while loop. Scheduler yields between slices for cancellation/resource fairness.

> Selection receives one finite CandidateSupplyWindow and never drives the walk.

> Repeated local supply work is orchestrated as separate bounded slices, never as an internal Selection refill loop.

## 8. Candidate cursor lifetime

> CandidateSupplyCursor is bounded scan progress, not durable exposure history.

It means “where one bounded structural scan can continue.” It is not already-published, seen, permanently consumed, durable feed tail or acquisition checkpoint. Freeze episode-local/ephemeral lifetime: nil → C1 → C2 → exhausted across separate bounded invocations. Restart begins nil. Context/editorial revision change discards progress; explicit supply-advanced signal schedules a head reconsideration. No forever-per-Edition cursor or production-cursor table.

In-flight slice completes/cancels before reset; a coalesced pending head restart cannot be lost to its completion. Local runtime intent identity only correlates work; no durable generation counter is needed. This cursor is structural ordering, while publication tail is immutable occurrence ordering; never substitute one for the other.

## 9. Exposure identity/scope

Freeze exact OriginRevisionID within the same target FeedEditionID, counting committed publication, not actual viewport visibility/read tracking. Automatic continuous append suppresses a revision already published anywhere in that Edition. OriginRecordID would wrongly suppress a new upstream revision; PublicationCardID is unique per occurrence and cannot suppress repeated canonical content. Manual/future special republication remains possible only by explicit policy/action outside automatic runway suppression; do not impose a global storage uniqueness constraint on revision identity.

Scope alternatives: same ContextKey across lineage would require lineage authority and might prevent explicit refresh from legitimately rebuilding; EditorialRevision alone crosses independent Editions; global reader history would wrongly suppress Source content because Main published it. Same Edition is the minimal durable scope. Refresh/new editorial policy creates an explicitly prepared successor whose fresh Edition scope can publish the same revision. Main and Source Editions are independent, even for shared content. Reusing an existing Edition preserves its exact scope; reuse implementation is deferred. Changing resolved policy within an existing Edition must obey the immutable matching editorial revision, not silently alter append semantics.

For only the distinct IDs in ONE supplied candidate window, request a bounded batch history membership query scoped to explicit Edition. Persistence returns mechanical committed presence; Publication names the history fact; Runtime supplies `ExposureSnapshot(editionID, requestedRevisionIDs, publishedRevisionIDs)` explicitly to future Editorial Selection. Missing coverage/read error is an error, never “not exposed”. No full-history scan/Set; no hidden filtering in CandidateProvider, ContentStore candidateWindow or selection_supply.

Minimum 3K1 exposure gate: narrow revision-ID index on published_cards only if query-plan proof requires it, with segment→Edition membership validation and batch size bounded by supplied window. Probe supplied IDs, not every card in the Edition. No exposure table/generation. Serialized automatic production for one target Edition plus fresh lookup before each slice prevents two automatic workers publishing the same revision concurrently; unrelated explicit manual publication has different semantics. A concurrent external append invalidates facts and requires separate reconsideration, not blind retry with stale selection.

## 10. New-supply reconsideration

> New canonical supply may appear ahead of an old scan cursor, so continuous production must be able to reconsider the structural head without automatically republishing old revisions.

Proof scenario: episode at C2 has published revisions A/B. Admission adds N at head and emits local canonical supply changed. Controller sets pending head reconsideration; after current slice settles, discard cursor/exhaustion and start nil. The new finite window includes N and perhaps A/B. Bounded exposure snapshot rejects A/B, permits N, and next bounded slice advances structural progress. No durable supply-generation counter is required. Continuous admissions coalesce one head reconsideration; scheduling must also permit an older-progress slice between head resets to avoid starving the older walk. The one owner retains the suspended episode cursor transiently for that fairness turn; no two slices run concurrently.

Restart restores stable published history, starts a new head episode and uses durable scoped history membership to reject old revisions. Missed process-local admission events are covered by restart and explicit activation reconsideration. Exhausted episodes are reopened by admission completion, activation or explicit context/revision changes, not polling. A supply signal concurrent with a scan prevents treating that scan's end as final evidence for escalation until a fresh head episode settles.

## 11. Local exhaustion semantics

> A local supply window that yields no publishable candidates is not exhaustion unless its structural window says exhausted.

Zero selected with exhausted=false means structural progress can continue: sparsity/exposure may explain the empty result. Schedule another separate bounded slice only while pressure and resource permission remain, with a cancellation/yield boundary; never fetch immediately. An episode reaches factual structural end only when CandidateSupplyWindow.exhausted=true, and retains that observation with its explicit scope. Exhausted is not permanent end-of-internet.

Structural exhaustion alone is not proof of unavailable local publication: settle successful local append and remeasure ready stock. Required-image preparation pending/failure, unresolved presentation facts, history read error or storage/publication failure is local blockage, not shortage evidence. Once the complete walk has ended without unresolved local work and fresh ready stock still cannot satisfy known pressure, local supply is genuinely insufficient for that observed resolved context. No out-of-budget slice is relabeled exhaustion. Source sparsity can require many separately scheduled slices; scheduler does not hide them inside Selection/provider.

## 12. AcquisitionDemand boundary

Emit only if all facts hold: explicit current resolved context/Edition; persistent pressure from measured coverage or explicit forward tail approach with insufficient ready stock; current head-reconsidered structural episode ended exhausted=true; no pending supply-change restart; no uncommitted/deferred usable local result or local preparation/storage error; no local slice in flight; and post-completion ready measurement still insufficient. Coalesce an outstanding demand for that scope/purpose until downstream acknowledgement or relevant fact change. An empty current nonexhausted window, unknown stock or failed storage cannot emit demand.

Proposed AcquisitionDemand contains ContextKey, EditorialRevisionID, purpose (reader continuation or speculative preparation), semantic urgency/coverage deficit, and evidence of current local structural exhaustion/ready stock. It contains no URL, RSS page, Mastodon max_id, HTTP request or connector command. Physical work budgets may constrain downstream planning, never masquerade as requested pages.

> Runway demand is semantic pressure. Acquisition planning and connector execution are separate downstream responsibilities.

Runway → semantic demand; AcquisitionPlanner → bounded prioritized AcquisitionFrontier; AcquisitionCoordinator → external execution. Runway builds no frontier. Local order is published ready stock → canonical local supply → explicitly available local preparation → AcquisitionDemand. Actual planner, coordinator, connectors, HTTP, network media and retries are not authorized by 3J or the next local slice.

## 13. Session / Edition append behavior

> Normal runway replenishment appends future history to the visible Edition; it does not replace the Edition.

Commit new tail segment durably via Coordinator, then future semantic `publishedTailAdvanced(editionID, receipt)` goes to Runtime/session. Receipt is invalidation/append evidence, not a second publication authority. Session accepts it only for its current Edition, preserves exact anchor/placement and capacities, and may subsequently rematerialize retained local history at that same logical anchor. No forced scroll, reorder, removal, automatic checkpoint or successor swap; failure keeps prior presentation. Tail notification is outside FeedPresentationSnapshot. Existing explicit checkpoint milestone behavior remains intact.

Refresh/context/editorial transitions are separate: prepare/publish successor durably, retain predecessor presentation during work/failure, then explicit successful session swap. No Edition replacement per refill; no global active-Edition discovery in the producer. Stale old-Edition completion may retain its durably committed history but cannot swap or move current presentation.

## 14. Concurrency and in-flight ownership

Choose RunwayController as sole minimal Runtime owner of active local production intent, latest coalesced pressure, episode progress, pending supply reset and bounded measurements for the explicitly active resolved scope. FeedSession owns only presentation/anchor/checkpoint. UI submits intent; AcquisitionCoordinator owns downstream external execution only. Do not duplicate local in-flight state in these owners or create a giant single-flight actor/service locator.

One local slice in flight for the active target Edition. Observation only replaces latest pressure/pending bit; scheduling work reserves the intent before dispatch. Completion clears it, merges pending supply reset, and reevaluates current facts before scheduling at most one subsequent slice as a separate opportunity. No task per scroll event, internal retry loop, offer cache across every Edition, attempt counter or timer. Same-Edition external append requires remeasurement/exposure reread; stale tail rejection remains transactional authority. Context/revision switch cancels or waits for the existing slice's settle boundary before a new active slice; results tagged with old scope cannot update active facts. IDs are transient correlation, not persistence epochs/generations.

## 15. Background and context behavior

OS background opportunity is an explicit resource/scheduling opportunity for the same policy, LocalProductionSlice, semantic AcquisitionDemand and Coordinator. It uses explicit context, existing history and bounded resource permission; there is no BackgroundFeedProducerV2, second Selection pipeline or permanent background timer. Without fresh active consumption use explicit unknown/prior measured facts, not fabricated velocity. Wiring/OS integration remains deferred.

Context activation/restoration reconsiders structural head and uses that Edition's exposure; Main never inherits Source/global repetition suppression. Context reuse implementation is deferred. A background append does not transfer visible ownership. Background acquisition unavailable leaves demand unsatisfied and local history valid.

## 16. Failure semantics

| Fact | Meaning / response |
| --- | --- |
| Zero selected, nonexhausted | Progress, not shortage; another separately scheduled slice may continue. |
| Structural exhausted | Current walk ended; settle local work/remeasure before demand; admission can reopen it. |
| Storage/history/publication failure | Error; prior history/runway remains valid; no fake exhaustion or automatic retry. |
| Media unavailable/unsuitable | Explicit policy may already choose textOnly; required image blocks that result, never hidden fallback. |
| Acquisition unavailable | Semantic pressure remains unsatisfied; no fake cards or repeated scroll-triggered requests. |
| Resource/cancellation boundary | Preserve committed history; uncommitted work is not ready stock; reconsider only on explicit opportunity. |

Keep these as small facts/results, not a giant tail state machine. Presentation gains no tailState, runwayState, refreshState or generation placeholders. Separate operational diagnostics can report ready-ahead, windows/candidates examined, exposure-suppressed, cards published, exhaustion reached, demands emitted, in-flight intent, latency and consumption. Metrics verify behavior but are never correctness authority; publication/storage facts and explicit policy decisions are.

## 17. Explicitly deferred behavior

Actual AcquisitionPlanner/Coordinator, connector execution/network/HTTP, remote media acquisition, MediaResolver/MediaPolicy, retries/cache/deadlines, sophisticated editorial policy, context-switch reuse implementation, background scheduling wiring, UI, first-launch UX and asset retention are deferred. FeedPlanResolver implementation, lifecycle auto-checkpointing, production FeedSession wiring and execution of Runway intents are not started here. No production cursor/generation/exposure table or UI operational placeholder is introduced.

## 18. 3K implementation gates

1. **3K1 — exposure/progress + ready-runway facts.** Freeze explicit same-Edition exact-revision exposure and pure facts; implement only narrow bounded history membership and capped ready-ahead mechanical reads through semantic Publication boundaries. Prove anchor membership, ordered seek, saturated/zero/unknown distinction, query plans under large history, new revision versus repeated revision, and fresh head restart/reopen semantics. Review minimal index necessity before migration. No production execution, full-history scan or durable production cursor. Define bounded logical consumption-position measurements before controller wiring.
2. **3K2 — one bounded local production slice.** Explicit plan/matching policy and presentation/prepared inputs; one provider window → bounded exposure → one pure Selection → explicit local preparation → at most one append/create. Gate future explicit Selection exposure input and transactional/serial ownership assumptions. Prove zero nonexhausted progress, all-or-nothing failure, exact ordering, image refusal without fallback, unchanged earlier history, one provider call and no refill/network loop. Caller controls IDs/times and cursor continuation. No Acquisition or FeedPlanResolver implementation.
3. **3K3 — adaptive RunwayPolicy / minimal RunwayController.** Pure known/unknown coverage arithmetic, explicitly measured rates/latency, hysteresis and resource bounds; sole in-flight local intent owner, coalesced observations, episode/head fairness and separate slice scheduling. Prove r/L adaptation, saturated probe conservatism, reversals, stale completion, pending supply reset, cheap observation and anchor-preserving append. No connector work, timer/refill attempts or remote dispatch. Scope of session notification wiring requires this gate's review.
4. **3K4 — semantic AcquisitionDemand handoff.** Prove persistent post-settle pressure + completed structural exhaustion + no pending local work/reset/error; define acknowledgement/coalescing value boundary. Tests must reject empty nonexhausted, unknown facts and publication failure; admission reopens local-first consideration. No planner/frontier construction, coordinator, connector or network execution.

3K1 is now complete; 3K3 is complete; 3K4 semantic handoff is now complete, without external execution.

### 3K1 completion record

PublicationHistory now exposes readyAhead, exposure and forwardAdvance as immutable semantic facts; Persistence alone owns mechanical positions/SQL. ReadyAheadAmount is exact(n) when the tail is reached within the explicit bound, otherwise atLeast(bound) with a bound+1 witness. Anchor is excluded and exact observed tail/anchor/count share one read snapshot. Existing Edition/Segment and Segment/Card ordering indexes serve bounded seeks; only anchor/tail schemas are checked, without full-history audit or payload materialization. Later segments are visited by LIMIT 1 range seeks and cards consume one shared probe+1 budget; empty crossed segments fail instead of allowing an unbounded empty walk.

Exposure is exact OriginRevisionID membership in the explicitly supplied FeedEditionID, for supplied IDs only. PublicationHistory rejects duplicate requests without deduplication; unique empty requests still validate Edition existence. No exposure eligibility policy is executed. The base query plan reached cards through Edition/Segments; publication-exposure-index-v1 therefore adds only published_cards_origin_revision_segment(origin_revision_id, segment_id). The actual query explicitly uses that covering index and stops at the first same-Edition occurrence. No table, column, uniqueness constraint, exposure ledger or generation was added. Repeated explicit occurrences remain allowed and new revisions remain distinct.

PublicationAdvanceFacts returns same, backward, forwardExact(n) or forwardBeyondProbe(bound), counting positions strictly after source through destination inclusively. Positions stay inside Persistence. Beyond-probe is unknown exact distance, never a rate. One read snapshot and ordering-index seeks avoid OFFSET, global sort, full payload and unlimited count. A 10,000-occurrence/100-segment fixture proves planner shape without timing assertions; migration tests preserve existing history/checkpoint and all old schema definitions. Reopen facts for requested N/A/B retain committed A/B and leave N absent, without executing CandidateProvider or Selection and without a durable production cursor.

Publication history can report what is durably published; it does not decide what Editorial should exclude. Ready runway is measured from immutable published occurrence order, never from FeedWindow capacity. Bounded history observation must not become proportional to retained history size. 3K1 did not implement Runtime/Editorial behavior. 3K2 now supplies explicit Editorial exposure and one append-only Runtime slice; Runway policy and minimal intent ownership are implemented in 3K3; Acquisition remains unimplemented.

### 3K2 completion record

Phase 3K1 — complete. Phase 3K2 — one bounded local production slice — complete. Phase 3K3 — adaptive policy + minimal controller — complete.

Editorial SelectionExposureSnapshot validates a unique ordered request and published subset with a public failable initializer. Explicit excludePublishedRevisions behavior requires exact candidate-revision coverage, filters exact OriginRevisionID before sequencing and preserves the supplied examinedCount/nextCursor/exhausted unchanged. The existing no-exposure call delegates to one implementation; none rejects a supplied snapshot. Nominal policy mismatch and duplicate OriginRecordID remain the first validations. Editorial imports no Publication/history dependency and derives no behavior from PolicyVersion.

PublicationStore now has one mechanical exposure API returning ExposureRecord; the former equivalent publishedRevisionIDs API is replaced, not retained. PublicationHistory exposure maps exact target Edition, observedTailCardID, requested IDs and committed subset. Tail occurrence and membership share one SQLite read snapshot, even for an empty request, using existing tail ordering indexes and the 3K1 revision index without payload/full-history reads. Same target FeedEditionID is the exposure scope source.

Expected-tail append overloads on Store and Coordinator share their respective single private append paths with generic callers. In the serialized writer transaction, expected-tail append reads/validates actual tail schema and last occurrence identity, rejects staleHistoryExpectation before accepting the incoming ordinal/inserts, and commits Segment/cards atomically. TailRecord remains ordinal-only. A Coordinator that has already observed a newer ordinal still cannot publish with stale exposure. Generic append remains unchanged; no token/generation, reselection, renumbering or automatic retry is introduced.

LocalProductionSlice is a concrete synchronous Sendable value over CandidateProvider, SelectionEngine, PublicationHistory and PublicationCoordinator. Caller supplies resolved FeedPlan/matching ResolvedSelectionPolicy, explicit existing Edition, ephemeral cursor/work bound, segment ID/seed/time and one local preparation closure. Automatic production requires excludePublishedRevisions. One provider window → one exposure read → one pure Selection → at most one caller preparation → pure PublicationPreparation → at most one expected-tail append. The slice does not query media facts, choose presentation/media, create Edition, discover active/latest Edition or inspect runway health.

LocalPreparedPublication supplies explicit aligned inputs/card IDs; all attribution/actions/image results come from the caller. Cursor remains caller-owned ephemeral progress. Zero selected, including nonexhausted windows, returns advancedWithoutPublication without preparation/append. Only a successfully returned LocalProductionSliceOutcome permits advancing the episode cursor. Preparation, storage/publication and stale-history errors propagate without successful progress or hidden durable cursor writes; unexpected nothingToPublish after nonempty Selection is inconsistentPublicationOutcome.

> One local production slice does bounded work and returns honest progress. It never tries to “fill the runway” by looping internally.

> Automatic continuous production must not republish an OriginRevision already committed in the target Edition.

> Exposure facts are stale if the Edition tail changed before commit; stale work is rejected, never silently retried.

> Caller may advance episode progress only from a successfully returned LocalProductionSliceOutcome.

Real-database tests prove bounded single-window output/order/IDs/progress, head restart suppressing old revisions, new revision of an old origin, zero-selected structural progress, same-cursor reconsideration after failure, unavailable image refusal and explicit textOnly success, and deterministic append during preparation rejecting stale work without retry. 3K2 introduced no schema/package change, Acquisition/network, FeedSession wiring or Runway controller/sampling. 3K3 adaptive policy and minimal controller are now complete; 3K4 semantic handoff is now complete; acquisition execution remains deferred.


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


## Phase 3R2 — finite acquisition failure isolation

RunwayAcquisitionCycle acknowledges its controller-owned intent before external work, preserves every settled target result, signals each confirmed supply change through the existing noteLocalSupplyChanged API, and continues planned targets after typed operational failures. Fatal structural errors still abort; effective cancellation stops later work. No RunwayController or driver production change was made.

The cycle and cold bootstrap use the same injected AcquisitionCoordinator for atomic ephemeral selection-position ownership. Planner remains pure and explicit; no parallel execution, scheduler, automatic retry, timer, backoff or persisted fairness state was added. The cold presentation contract and handoff are unchanged: successful first publication is visually successful despite another source's operational failure.

Driver regression fixtures deliberately contain two eligible Main targets A/B. With capacity one, the existing controller may emit successive distinct intents after confirmed local publication changes ready-ahead facts. Before 3R2, repeated selection of A replayed its document and stopped before B. After 3R2, controlled pulls observe A at ready-ahead 0, B at 1, and final A replay at 2; with one seeded local item these facts are 1/2/3. B contributes exactly one additional canonical revision and one appended segment. Tests verify both targets' eligibility, exact canonical-to-published revision correspondence, absence of duplicate appended revisions, original cards, unchanged anchors/Edition, exact HTTP counts (A twice, B once), and quiescence on another drive with unchanged facts. This is existing controller-owned reconsideration after factual supply/publication, not a new retry policy or a second cold acquisition round.

## D1 — Selected-source acquisition coverage

Published depth and selected-target acquisition coverage are independent. AppComposition
supplies an explicit `selectedSourceCoverage` demand to its existing FeedRunwayDriver.
This demand has no ExhaustedLocalSupply: a healthy local runway is not exhaustion.
Depth-only compositions retain their original contract. Runtime still owns depth policy;
no reserve inflation or second source-alternation algorithm is introduced.

When depth effects settle, the same causal driver asks RunwayAcquisitionCycle to plan
unattempted eligible targets through the existing AcquisitionPlanner/Coordinator. Its
mechanical `selectionAfter` rotation, target single-flight and work bounds are retained.
Actual coordinator settlements, including 304/empty/repeated/failure, establish a transient
target-generation coverage fact. Checkpoints alone cannot represent these outcomes.
The coordinator is the sole owner of this fact for the composition association's lifetime;
cold and active-session work share it. No persisted counter or migration is needed.

Each causal completion may authorize the next bounded plan while useful uncovered work
remains. The finite set is the authorized target generations in the selected snapshot,
not a card quota. Shared bindings cause one target execution. Cooling/resource-denied
or conflicting work settles the current drive without polling; a legitimate later drive
can reconsider pending targets. Cancellation stops continuation. Successful supply follows
the existing scoped notification/local production path; Editorial still owns PD-4 across
segment boundaries. A new association receives a new coverage opportunity; this is not
persistent freshness state or a periodic fetch policy.

BASE reproduction (`0c53fac`): four authorized sources/targets, capacity two, first pair
provides more than reserve 16. Stationary measured depth is healthy, yet connector entry
and terminal journal contain only targets 1/2. Regression failed with three coverage
assertions; the same regression passes with all four actual pulls/terminals after D1.
Evidence: `~/Documents/feedmine-evidence/2026-10-09/d1/red.txt` and `green-initial.txt`.
