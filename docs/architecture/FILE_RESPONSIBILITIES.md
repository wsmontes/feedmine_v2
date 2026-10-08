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
| FeedMineAcquisition | AcquisitionPlanner.swift | Converter demanda por supply em trabalho de acquisition priorizado e bounded. | HTTP execution or editorial ordering |
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

Phase 3J — complete (design only): [CONTINUOUS_FEED_RUNWAY_DESIGN.md](CONTINUOUS_FEED_RUNWAY_DESIGN.md). Future narrow Persistence reads provide capped ready-ahead positions and window-bounded exact-revision publication presence through Publication semantic boundaries. Runtime supplies exposure facts to pure Editorial Selection; CandidateProvider remains structural. Future LocalProductionSlice performs at most one provider call, one Selection and one publication action from explicit resolved context/preparation inputs. FeedSession retains presentation, anchor and explicit checkpoint; append notifications preserve current Edition/position. Runway observations and in-flight state stay outside presentation snapshots. AcquisitionPlanner owns frontier planning and AcquisitionCoordinator owns external execution downstream; neither enters Runway. 3K1–3K3 are complete; 3K4 semantic handoff is complete; Phase 3K is complete.

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
