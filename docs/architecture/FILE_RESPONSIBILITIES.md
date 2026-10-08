# File responsibilities

| Module | File | Responsibility | Explicitly does not own |
| --- | --- | --- | --- |
| FeedMineDomain | FeedIdentifiers.swift | Phase 1A implemented: seven nominal UUID IDs for source, provider, origin record/revision, source binding, content entity and cluster. Phase 1B adds EditorialRevisionID; Phase 2B adds cross-boundary FeedEditionID, FeedSegmentID and PublicationCardID; Phase 3I1 adds caller-supplied MediaCandidateID independent of locator/asset identity. Domain owns nominal identity only; semantic ContextKey belongs to FeedContext.swift. | Endpoint identity, protocol-specific identity or transport-derived ID generation |
| FeedMineDomain | FeedContext.swift | Phase 1B implementation: semantic reusable ContextKey/request and original non-whitespace SearchContext. | Acquisition, network, database, UI navigation or connector metadata |
| FeedMineDomain | FeedIntent.swift | Phase 1B implementation: feed-level changeContext and refresh semantic intentions only. | Intent execution, networking or persistence |
| FeedMineDomain | FeedPlan.swift | Phase 1B implementation: opaque policy/catalog/schema versions, context-bound EditorialRevision and validated context/revision FeedPlan association. | Policy execution, fetching or UI queries |
| FeedMineDomain | Source.swift | Phase 1A implemented: independent Source and Provider; ConnectorKind; declarative SourceBinding with principal-derived connector and consistent aliases; SourceBindingState. | Endpoint identity, acquisition targets or transport execution |
| FeedMineDomain | Content.swift | Phase 1A implemented: opaque ExternalIdentity owning connector kind; OriginRecord deriving that kind; immutable OriginRevision owning optional provider attribution; separate membership, relations, entity and cluster. | FeedKit models, XML, Mastodon models, ATProto records, Nostr events or downstream raw protocol JSON |
| FeedMineDomain | MediaCandidate.swift | Phase 3I1 implemented: immutable minimal cardVisual/image upstream facts and caller-owned MediaCandidateID tied to exact OriginRevision; HTTP(S) locator preserved and exact optional MIME/paired positive dimensions. | Prepared asset facts, raw connector representations, rendered images, SwiftUI Image, downloaded assets or publication media identity |
| FeedMineDomain | InteractionOffer.swift | Representar ações semanticamente disponíveis para um item. | Action execution or SDK-specific action objects |
| FeedMinePersistence | RuntimeDatabase.swift | Phase 2A implemented: physical runtime.sqlite location/lifecycle, DatabasePool, internal transactions, typed failures and explicit WAL checkpoints. | Domain CRUD/schema, catalog/assets, volatile fallback, retention, backup or retry policies. |
| FeedMinePersistence | RuntimeMigrations.swift | Phase 2A/2E implemented: non-erasing migration authority preserving runtime-foundation-v1 and adding publication-restore-v1 with exactly four publication/session tables, canonical-supply-v1 with four selection hot-path tables and canonical-media-candidates-v1 with one revision-owned media table. Old migrations unchanged; no extra media index. 3K1 adds only publication-exposure-index-v1 and the narrow revision/segment index. | Domain tables, duplicate schema counters, recovery or database lifecycle. |
| FeedMinePersistence | ContentStore.swift | Struct concreta: atomic canonical changes, immutable revisions, exact reads e refresh de selection_supply; 3B2 complete; 3I1 complete: atomic revision + explicit complete ordered immutable media-candidate collection, exact historical reads and typed replay/conflict/integrity validation; 3B3 complete: caller-bounded candidate window, source filtering after bound, projection-index keyset and narrow current payload in one snapshot. | Scoring, selection, publication or networking; future candidate admission never rewrites immutable revisions |
| FeedMinePersistence | PublicationStore.swift | Phase 2E implemented: explicit mechanical Edition/Segment/Card records, atomic immutable create/append, revision identity consistency and bounded keyset reads; 3G1 implemented a narrow mechanical Edition-tail read and removed the hot append full-history scan; write-transaction tail revalidation remains authoritative. 3K1 adds one-snapshot bounded ready-ahead/forward-position probes and supplied-revision same-Edition presence, without payload/full-history reads. | Publication semantics, Runtime/UI models, canonical joins, updates, deletes, caches or coordination |
| FeedMinePersistence | PersistenceValueCoding.swift | Phase 2E implemented: internal canonical UUID text, checked counters, seed bit-pattern and finite Unix date coding. | Domain behavior or generic persistence framework |
| FeedMinePersistence | SessionStore.swift | Phase 2E implemented: singleton logical checkpoint, membership validation on save/load and atomic checkpoint replacement. | Context/position duplication, pixels, SessionCursor semantics or Runtime transitions |
| FeedMineAcquisition | FeedConnector.swift | Boundary protocol entre FeedMine acquisition e implementações de sistemas externos. | Concrete protocol implementation, selection, publication or universal plugin frameworks |
| FeedMineAcquisition | AcquisitionModels.swift | 3K4 implemented: readerContinuation purpose, coverage/logical pressure, validated ExhaustedLocalSupply and semantic AcquisitionDemand keyed by context/revision. | Edition/card IDs, external fetch command, protocol values, source selection or execution |
| FeedMineAcquisition | BootstrapPlan.swift | Representar trabalho bounded necessário para produzir supply inicial suficiente quando ainda não há runway utilizável. | Permanent runway strategy or bootstrap UI |
| FeedMineAcquisition | AdmissionPolicy.swift | Definir o gate entre evidence trazida por connector e canonical local supply. | Editorial selection or protocol transport |
| FeedMineAcquisition | AcquisitionPlanner.swift | Pure finite plans/dispositions from supplied demand, ordered eligible targets, active facts and explicit resource capacities. | Eligibility discovery, persistent frontier, I/O or connector execution |
| FeedMineAcquisition | AcquisitionCoordinator.swift | Executar/coordenar acquisition planejada usando `FeedConnector`. | Publication, editorial ordering or direct scroll responses |
| FeedMineSyndication | SyndicationConnector.swift | Implementação futura de `FeedConnector` para feeds de syndication. | Editorial selection, persistence or a general product transport framework |
| FeedMineSyndication | SyndicationTranslator.swift | Traduzir objetos externos de syndication para os modelos canônicos aceitos pela acquisition/admission boundary. | Downstream protocol representations or editorial decisions |
| FeedMineSyndication | SyndicationHTTP.swift | Detalhes HTTP específicos de syndication. | Universal HTTP framework, publication or UI media resolution |
| FeedMineEditorial | FeedPlanResolver.swift | Future owner of resolving FeedPlan + matching ResolvedSelectionPolicy; identity and executable behavior remain separate. | External system queries or acquisition execution |
| FeedMineEditorial | Candidate.swift | Phase 3C implemented: Editorial Candidate identity, narrow content and explicit authored/observed timestamp semantics; imports Domain/Foundation only. | PublishedCard snapshots or protocol evidence |
| FeedMineEditorial | CandidateProvider.swift | Phase 3C implemented: stateless concrete CandidateProvider maps Main/Source context to exactly one bounded ContentStore window, preserving metadata and mapping an Editorial-owned cursor. | Remote acquisition, protocol parsing or final selection |
| FeedMineEditorial | EditorialPolicy.swift | Phase 3E implemented: one pure ResolvedSelectionPolicy value with nominal context/version guard and explicit baseline semantics; no policy services/registry. | Fetching, publication or renderer behavior |
| FeedMineEditorial | SelectionEngine.swift | Phase 3E implemented: pure execution of matching policy over one supplied CandidateSupplyWindow, duplicate-OriginRecordID rejection, explicit recency/durable-ID ordering and preserved supply facts. | Persistence imports/I/O, CandidateProvider calls, refill, target counts, exposure/history or acquisition |
| FeedMineMedia | MediaPreparation.swift | Phase 3I3 implemented: one explicit candidate plus bytes/local key/unavailable to Media-owned result with exact IDs and usable/unavailable/unsuitable state; only invalid image maps to unsuitable, storage/integrity failures propagate; remote locator inert. | Publication imports/values, RenderContract/layout choice, draft assembly, history, editorial reselection, network transport/frontier, deadlines, decoded cache or SwiftUI rendering |
| FeedMineMedia | MediaResolver.swift | Future local candidate suitability resolution within Media-owned preparation facts; no separate service required by 3H. | RenderContract choice, draft assembly, SwiftUI objects, editorial selection or published history |
| FeedMineMedia | MediaPolicy.swift | Future local media suitability rules, limited to concrete consumers. | Renderer/layout behavior, editorial ranking, publication or an independent network resource policy |
| FeedMineMedia | AssetStore.swift | Phase 3I2 implemented: internal exact-byte content-addressed file store, strict sha256:<hex> keys, sync-before-success, exclusive atomic install, authenticated existing/racing destinations and local reads; small factual LocalMediaAssetError. No SQLite metadata. | Public paths, image suitability/MIME/decoding, SQLite metadata, history, acquisition or retention policy |
| FeedMineMedia | ImageMaterializer.swift | Phase 3I2 implemented: synchronous image-container inspection before exact-byte storage; authenticated local re-inspection; LocalImageAsset with measured positive dimensions/MIME and key only. | Transforms, full pixel decode, candidate association, SwiftUI objects, HTTP, cache, Publication values or history |
| FeedMinePublication | PublishedCard.swift | Phase 2C implemented: immutable self-contained occurrence snapshot, exact optional PublishedText and explicitly typed PublishedTimestamp; rejects textOnly with primary media. | Live canonical/catalog joins, duplicated history metadata, Codable blobs or retrospective mutation |
| FeedMinePublication | PublishedOrigin.swift | Phase 2C implemented: historical origin/revision IDs, separate optional source/provider IDs and frozen attribution names. | Live attribution lookup or canonical payload |
| FeedMinePublication | PublishedPrimaryAction.swift | Phase 2C implemented: frozen externalURL/mediaPlayback targets or localContentDetail for the owning card. | Action execution, network behavior, connector write actions or occurrence identity |
| FeedMineMedia | PublishedMedia.swift | Phase 2C implemented: opaque local media key, validated optional paired dimensions, derived ratio and primary-only PublishedMediaSet. | Paths/remote URL identity, download, preparation, storage or alternate media variants |
| FeedMinePublication | RenderContract.swift | Phase 2C implemented: hero/thumbnail/textOnly slot structure and finite positive optional media aspect ratio for deterministic local presentation. | RenderEnvironment, renderer execution, acquisition or remote resolution |
| FeedMinePublication | FeedEdition.swift | Phase 2B implemented: immutable concrete history metadata, raw PublicationSchemaVersion and ContextKey derived from EditorialRevision. | Mutable segment collections, lifecycle flags, revision duplication or storage representation |
| FeedMinePublication | FeedSegment.swift | Phase 2B implemented: immutable nonempty ordered PublicationCardIDs, within-segment uniqueness and append metadata. | Cross-segment append validation, history mutation or card payload |
| FeedMinePublication | PublicationPersistenceMapping.swift | Phase 2E implemented: internal semantic value to/from explicit Persistence record mapping, preserving order and rejecting invalid reconstruction. | SQL, Runtime/UI API or Codable blobs |
| FeedMinePublication | SessionCursor.swift | Phase 2B implemented: persistible Edition/card occurrence logical position with top/center FeedWindowAnchor. | Pixels, restore execution, global SessionID or storage mechanics |
| FeedMinePublication | FeedWindow.swift | Phase 2F implemented: bounded immutable semantic projection, nonempty unique PublishedCards in supplied order and exact retained anchor. | Page size, total history count, mutation, acquisition pagination or limits on total feed history |
| FeedMinePublication | PublicationHistory.swift | Retained semantic history + explicit logical cursor durability boundary through private stores and internal mapping. | Mechanical record exposure, viewport-triggered checkpoint writes, publication, selection, retention, cache or Runtime session ownership |
| FeedMinePublication | PublicationCardDraft.swift | Phase 3G2 implemented: immutable ready-to-freeze semantic payload with text-only/media validation, without occurrence identity. | Preparation, selection, persistence rows or cursors |
| FeedMinePublication | PublicationCoordinator.swift | Phase 3G2 implemented: concrete synchronous sole history producer; validate SelectionResult/draft alignment and freeze already-prepared semantic values using explicit IDs/times/seeds, atomic first publication and explicit-target append. | Acquisition, protocol parsing, remote media resolution or direct UI updates |
| FeedMineRuntime | PublicationPreparation.swift | Phase 3I3 implemented: pure stateless drafts assembly with positional count/origin/revision/provider alignment, exact Selection text/time, explicit presentation and actual prepared image metadata. | Canonical/DB lookup, filesystem/network work, media resolution policy, automatic fallback, history execution, session or Runway integration |
| FeedMineRuntime | FeedSession.swift | Actor-owned current state, restore, memory-local viewport movement and explicit current-position checkpoint operation without state mutation. | Direct database/stores, async wrappers, reducer/effects, acquisition or full session coordination |
| FeedMineRuntime | FeedSessionState.swift | Explicit minimal local session value: presentation and supplied finite backward/forward capacities. | Duplicated context/Edition/anchor, I/O, product constants or UI rendering |
| FeedMineRuntime | ViewportObservation.swift | Logical anchor observation only; non-failable initializer. | Pixels, velocity/direction, load/fetch commands or exposure semantics |
| FeedMineRuntime | FeedSessionUI.swift | UI surface for FeedPresentationSnapshot / PresentationCard, FeedIntent input and ViewportObservation input. | PublishedCard, FeedSegment, FeedEdition, publication/acquisition coordinators or persistence stores exposure. |
| FeedMineRuntime | FeedSessionReducer.swift | Pure transition logic: | I/O, networking or database execution |
| FeedMineRuntime | FeedSessionEffects.swift | Definir semanticamente efeitos que o reducer pode solicitar. | Connector-specific commands or effect execution |
| FeedMineRuntime | FeedPresentationSnapshot.swift | Phase 2G implemented: immutable ContextKey/EditionID/window baseline, validated FeedWindowSnapshot and Runtime-owned PresentationAnchor; internal semantic restore projection. | Publication/Persistence/Media exposure, page/total counts, generation/phase/tail/refresh placeholders or mutable state |
| FeedMineRuntime | PresentationCard.swift | Phase 2G implemented: immutable UI-facing projection of frozen text, attribution, timestamp meaning, layout/ratio and action kind; internal PublishedCard projection. | Publication authority, persistence/cache, provenance IDs, media keys/bytes, action targets or execution |
| FeedMineRuntime | ViewportObservation.swift | Descrever o que o usuário está vendo/consumindo. | loadMore commands or protocol pagination |
| FeedMineRuntime | RunwayPolicy.swift | 3K3 implemented: pure measured r/L coverage, explicit safety/release hysteresis, exact/atLeast distinction, bounded probe requests and internal nearest-rank p95 helper. | Fixed page size or periodic fetch strategies as conceptual runway |
| FeedMineRuntime | RunwayController.swift | 3K3 implemented: actor owns one memory-local intent, high-water/recent consumption and latency samples, coalesced observations, episode/head fairness and failure/bootstrap gates; emits requests only. | Direct scroll-to-connector fetching or editorial selection |
| FeedMineRuntime | InteractionCoordinator.swift | Executar semanticamente ações oferecidas por `InteractionOffer`. | Feed production or exposed protocol-specific commands |
| FeedMineRuntime | BackgroundFeedRefresh.swift | Entrada para oportunidades de execução em background. | Secondary background pipeline or visible history mutation |
| FeedMineUI | FeedScreenStore.swift | Future @MainActor bridge receiving FeedPresentationSnapshot / PresentationCard through FeedSessionUI and forwarding semantic input. | Publication model translation, direct PublishedCard consumption or business logic. |
| FeedMineUI | FeedScreen.swift | Root SwiftUI da experiência de feed. | Feed production, database access or network operations |
| FeedMineUI | FeedCardView.swift | Renderizar um PresentationCard já local e presentation-ready. | Direct PublishedCard consumption, FeedMinePublication imports, remote media resolution, network, database, acquisition or connector access. |
| FeedMineUI | FeedLoadingView.swift | Superfície futura de cold/first bootstrap. | Fake progress or execution of bootstrap acquisition |
| FeedMineComposition | FeedMineEnvironment.swift | Representar a composição explícita das dependências necessárias ao aplicativo. | Dynamic containers, global service locators or product policy |
| FeedMineComposition | FeedMineBootstrap.swift | Construir o object graph inicial em ordem explícita. | Product logic or service execution |
| FeedMine package manifest | Package.swift | Declare products and the exact target graph. | Runtime behavior or application composition. |
| ArchitectureSmokeTests | ArchitectureSmokeTests.swift | Import all ten modules to prove the package graph compiles. | Behavior tests, mocks or fixtures. |

Phase 3B1 schema, 3B2 atomic ContentStore/exact reads and 3B3 bounded candidate windows are complete. ContentStoreCandidateWindowScaleTests own 10k/100k workload and query-plan evidence with real constraints, sparse-source progress without refill, membership fanout and historical volume. Evidence sizes freeze neither page size nor wall-clock SLA. The existing projection ordering index and membership PK/index serve the path; Phase 3C implements Main + Source structural supply through CandidateProvider. Search remains deferred pending canonical FTS and fails explicitly before storage work. Each call performs exactly one bounded ContentStore window without capacity adjustment or refill. CandidateProvider does not execute FeedPlan policy versions; Selection now executes the explicitly supplied matching baseline policy.

Phase 3D completed the design-only Selection gate; [SELECTION_DESIGN.md](SELECTION_DESIGN.md) defines ownership for the Phase 3E pure deterministic implementation. Selection accepts a finite supplied window and returns ordered Candidate values plus supply facts. Publication freezes later semantic selection into immutable history; Runtime / Runway determines future supply need; Acquisition fulfills that demand. Selection owns none of those downstream operations. Phase 3E pure deterministic baseline Selection is complete: no I/O, no refill, no target count, no history/exposure, no scoring weights and no acquisition. Advanced editorial behavior and subsequent gates remain deferred.

Phase 3F completed the design-only gate: [PUBLICATION_DESIGN.md](PUBLICATION_DESIGN.md). Phase 3H closes the upstream boundary in [MEDIA_DESIGN.md](MEDIA_DESIGN.md): Phase 3I3 pure Runtime PublicationPreparation now directly assembles immutable PublicationCardDraft values from SelectionResult, prepared local Media facts and other prepared presentation inputs, including attribution/display names, optional entity/cluster semantics and primary action. Runtime chooses the Publication-owned RenderContract; Media returns no Publication values and never depends on Publication. No DraftBuilder/factory/protocol hierarchy is introduced. Draft assembly does not produce published history. PublicationCoordinator performs no Selection, canonical/catalog enrichment, media resolution, network, reordering, refill, retry or session swap. Text-only arrives already prepared; late media affects only future publication. Runtime/Session owns visible Edition and future refresh swaps. Phase 3G1 bounded tail, 3G2 immutable Coordinator and Phase 3G are complete; 3H is design only and 3I1 canonical MediaCandidate facts and 3I2 durable content-addressed local assets are complete; Phase 3I3 — local preparation + publication preparation integration — complete. Phase 3I — complete. The justified fifth media_candidates table stays outside the four-table 3A selection hot path, without a CandidateProvider media join. 3I2 local materialization is complete without DB metadata or sidecars; 3I3 single-candidate local result association and pure draft assembly are complete; MediaResolver/MediaPolicy and FeedSession/Runway integration remain deferred; remote acquisition, cache and retention remain deferred.

FeedMineMediaTests now owns AssetStoreTests (known final-byte SHA-256 key, exact bytes, idempotency/concurrent install, corruption and deterministic required-sync failures) and ImageMaterializerTests (actual PNG container facts, invalid input before storage and authenticated reopen/local reads). Package.swift adds only that test target; production dependencies are unchanged. Phase 3I1 — complete. Phase 3I2 — durable content-addressed local assets — complete. Phase 3I3 — local preparation + publication preparation integration — complete. Phase 3I — complete.

MediaPreparationTests prove explicit local inputs, inert unreachable locator, actual versus declared metadata, unavailable/unsuitable states and propagated corruption/storage errors. PublicationPreparationTests prove text-only without media work, exact positional Selection payload/time, hero/thumbnail contracts from actual prepared facts, typed mismatch/unusable refusal without automatic fallback, and late-media future occurrence preserving earlier history after reopen. PublicationCoordinator remains the sole history producer. No production package dependency changed; Runtime tests compile with existing dependencies.

Phase 3J — complete (design only): [CONTINUOUS_FEED_RUNWAY_DESIGN.md](CONTINUOUS_FEED_RUNWAY_DESIGN.md). Future narrow Persistence reads provide capped ready-ahead positions and window-bounded exact-revision publication presence through Publication semantic boundaries. Runtime supplies exposure facts to pure Editorial Selection; CandidateProvider remains structural. Future LocalProductionSlice performs at most one provider call, one Selection and one publication action from explicit resolved context/preparation inputs. FeedSession retains presentation, anchor and explicit checkpoint; append notifications preserve current Edition/position. Runway observations and in-flight state stay outside presentation snapshots. AcquisitionPlanner now owns pure bounded planning over supplied snapshots/resources, without frontier state, and AcquisitionCoordinator retains future external execution ownership downstream; neither enters Runway. 3K1–3K3 are complete; 3K4 semantic handoff is complete; Phase 3K is complete.

Phase 3J — complete. Phase 3K1 — bounded exposure + ready-runway history facts — complete. Phase 3K2 — one bounded local production slice — complete. Phase 3K3 — adaptive policy + minimal controller — complete.

| Module | File | Responsibility | Explicitly does not own |
| --- | --- | --- | --- |
| FeedMinePublication | PublicationRunwayFacts.swift | Implemented immutable ReadyAheadFacts (exact/atLeast), PublishedExposureFacts (unique request and committed subset), PublicationAdvanceFacts (same/backward/exact/beyond). | Mechanical ordinals, Runway health, consumption rate, Editorial filtering or production state |

PublicationHistory delegates the three factual reads to PublicationStore, maps semantic values and rejects duplicate exposure requests. Persistence validates explicit Edition membership; exact OriginRevisionID scope stays same-Edition. Runtime/Editorial receive no new dependency or behavior. Existing ordering indexes serve ready-ahead/advance with probe+1 total positions; one narrow revision/segment index serves exposure. No new table/column, exposure generation/ledger or durable production cursor exists. 3K1 tests prove functional bounds, 10k query-plan seeks/no temporary order, old migration/data preservation and reopened N/A/B facts. Selection exposure filtering and LocalProductionSlice were completed in 3K2; minimal Runway policy/controller are completed in 3K3; Acquisition is not started.

Phase 3K1 — complete. Phase 3K2 — one bounded local production slice — complete. Phase 3K3 — adaptive policy + minimal controller — complete.

| Module | File | Responsibility | Explicitly does not own |
| --- | --- | --- | --- |
| FeedMineEditorial | SelectionExposure.swift | Validated unique ordered requested revision IDs and published subset; no Publication dependency. | History retrieval, occurrence IDs or storage |
| FeedMineRuntime | LocalProductionSlice.swift | One explicit bounded provider window, same-Edition tail-bound exposure, pure Selection, caller preparation, pure drafts assembly and at most one transactional expected-tail append; honest returned progress. | Create/successor/global Edition lookup, media resolution, internal refill/retry, durable cursor, Runway health, Acquisition/network or FeedSession visibility |

SelectionEngine now executes explicit excludePublishedRevisions only with exact supplied coverage; it preserves structural supply report and the none baseline. PublicationHistory maps tail-bound exposure facts from one mechanical Store exposure API. Store/Coordinator generic and expected-tail append share single private implementations; writer transaction validates observed tail identity and refuses staleHistoryExpectation before insertion. TailRecord remains ordinal-only. Caller owns prepared attribution/presentation/local media/action/card IDs and ephemeral cursor advancement only after successful outcome. Empty nonexhausted selection is successful progress without append. 3K2 introduced no schema, package graph, Acquisition, FeedSession/Runway controller or sampling change.


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


## Phase 3L — designed Acquisition boundaries

Phase 3L — complete (design only): [ACQUISITION_DESIGN.md](ACQUISITION_DESIGN.md). Phase 3M1 — durable target/checkpoint authority — complete. Phase 3M2 — complete; Phase 3M3 — complete; Phase 3M4–3M5 — not started. Proposed responsibilities below introduce no implementation/API/schema. Exactly ACQUISITION_DESIGN, PERSISTENCE_DESIGN, IMPLEMENTATION_ORDER and this document change.

| Owner / file direction | Future responsibility | Explicit exclusion |
| --- | --- | --- |
| FeedMineDomain / nominal identifiers | UUID-backed AcquisitionTargetID independent of editorial/external identity. | URL/hash-derived identity, operational execution or target schema. |
| FeedMineAcquisition / AcquisitionModels.swift | Existing semantic AcquisitionDemand stays implemented; future Target, minimal protocol-free Batch/Observation and receipt boundaries. | Edition/history, transport objects, connector-allocated canonical IDs, endpoint configuration, parallel epochs or batch ledger. |
| FeedMinePersistence / runtime target authority | One durable target/checkpoint table, generation/state and opaque checkpoint CAS; exact register/read/update/revoke; SQLite transaction mechanics. | Catalog tables, transport configuration, transient fetch state, Acquisition imports or public GRDB. |
| FeedMinePersistence / shared canonical writer | Reuse existing ContentStore.apply(_:in:) in one wider target-validation/canonical/checkpoint admission operation; transactional external identity resolution. | Second canonical writer, Repository hierarchy, separately committed content/checkpoint steps. |
| FeedMineAcquisition / AdmissionPolicy and orchestration | Semantic claim/precedence validation and mapping to concrete neutral Persistence commands; return committed selectableSupplyChanged. | SQLite ownership, protocol parsing, publication, Runtime calls, global SupplyGeneration. |
| FeedMineAcquisition / AcquisitionPlanner.swift | Pure supplied-demand/eligible-snapshot/resource-bounds input → immutable finite plan/disposition. | Catalog/DB lookup, default budgets, fixed desired cards, persistent frontier or head/active/exploration policy. |
| FeedMineAcquisition / FeedConnector.swift | Small common bounded asynchronous event boundary for finite/continuous connector implementations. | Universal transport/plugin registry or protocol-specific objects beyond translation. |
| FeedMineAcquisition / AcquisitionCoordinator.swift | Future single actor owns one external execution per target, shares same current generation across demands and submits batches to Admission. | Per-Source actors, durable leases/frontier, retry/timer/backoff, canonical writer or publication. |
| Connector modules / Syndication scaffolds | Later connector-specific config, transport and translation into protocol-free claims. | Current 3L/3M network implementation or endpoint columns in generic target authority. |
| FeedMineComposition / future execution owner | Acquisition ownership acceptance → exact Runtime acknowledgement; committed receipt → relevant scope-aware noteLocalSupplyChanged. | Acknowledging on observation alone, module cycles, fabricated supply arrival or direct Acquisition→Runtime dependency. |
| FeedMineRuntime / RunwayController.swift | Existing local-first pressure, demand coalescing and stale ack/scope authority; respond to future composition supply facts. | Connector execution, target scheduling, transactional admission or FeedSession wiring in 3L. |
| FeedMineAcquisition / BootstrapPlan.swift | Remains scaffold; later finite cold-start consumer reuses the same contracts with explicit budgets. | New bootstrap purpose now or permanent runway strategy. |

Target identity/generation/state and checkpoint/CAS are durable runtime authority; future catalog/binding mappings and connector configuration are separate reconstructible integration inputs. No cross catalog/runtime transaction. Cancelled obsolete work is refused by transactional generation/state/CAS validation even if it returns late. No ledger/leaseEpoch/bindingRevision admission stamp/SupplyGeneration is required. Fake finite and continuous contract proofs precede real Syndication; Admission increases canonical supply and never publishes history.


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

Phase 3M4 — not started

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

AcquisitionPlannerTests uses value-only inputs without a database and covers all 24 numbered cases: order/capacity/filtering, zero resources and join semantics, generation conflicts, duplicate contracts, exact snapshots/bounds, pressure independence and repeatability. Additional validation tests cover negative/zero values and byte-distinct opaque snapshot facts. Package.swift, Persistence/schema, Batch, Admission, Coordinator, FeedConnector, Runtime and Composition are unchanged. Coordinator behavior, connector protocols/fakes/execution, network and Runtime acknowledgement/wiring remain deferred; 3M4 is not started.
