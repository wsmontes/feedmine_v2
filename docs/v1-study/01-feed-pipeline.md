# V1 study — Feed production / runtime core (area code: FP)

Static review of FeedMine v1 (`C:\workspace\feedmine-dev`). No Swift toolchain here; all claims
are from reading source, v1 docs and git history. Line numbers are `main` as checked out
2026-10-09. v2 counterparts read at the same time.

## 1. Scope

| File (v1, `feedmine/Services` unless noted) | LOC | Role |
| --- | --- | --- |
| `FeedStore.swift` | 8293 | `@MainActor @Observable` god object: DB, fetch, filter, publish, bookmarks, smart feeds, search, migration |
| `FeedLoader.swift` | 1517 | `@MainActor @Observable` view model over `FeedStore` (cached projections for the UI) |
| `FeedDisplayState.swift` | 613 | Extracted display state: `visibleItems`/`visibleCards`, generations, phase, page cache |
| `CardPreparationCoordinator.swift` | ~760 | Actor: ordered prep + contiguous-prefix promotion (replaced `ReadyCardQueue`) |
| `Reservoir.swift` | ~690 | `@MainActor` buffer: interleave, diversity, trim, cap |
| `AdaptiveScheduler.swift` | ~620 | `@MainActor` source scheduler (validators, cadence, backoff) |
| `SourceScheduler.swift` | ~430 | deprecated predecessor of `AdaptiveScheduler` (still in tree) |
| `FeedRunwayController.swift` | ~230 | actor: pressure-state machine (bootstrap/filling/cruising/…) |
| `RunwayPolicy.swift` | ~95 | fixed watermark struct (20/60/120/180 …) |
| `RunwayMetrics.swift` | ~55 | EMA counters, `estimatedRunwaySeconds` |
| `EditorialSequencer.swift` | ~175 | least-used round-robin provider diversity |
| `CardPreparationPipeline.swift` | ~230 | actor: bounded parallel media resolution (used by old `ReadyCardQueue`) |
| `ReadyCardQueue.swift` | ~165 | `@MainActor` first-gen publish gate (superseded by coordinator) |
| `PreparedPageRestoration.swift` | ~100 | pure warm-start card rebuild from stored projection |
| `FeedMetrics.swift` | ~75 | OSSignpost instrumentation |
| `Models/PreparedFeedCard.swift` | ~165 | terminal published card + media/layout enums |
| `Models/FeedCardPresentation.swift` | ~150 | legacy card type + migration bridge |
| `Models/FeedPresentationContext.swift` | ~45 | epoch/mode/generation identity for stale-task rejection |

Tests skimmed: `FeedStoreTests`, `FeedDisplayStateTests`, `ReservoirTests`, `ReadyCardQueueTests`,
`CardPreparationCoordinatorTests`, `AdaptiveSchedulerTests`, `SourceSchedulerTests`,
`FeedLoaderCacheTests`. Docs read in full: `docs/cards-resolvidos-antes-de-aparecer.md`,
`docs/release/review-feed-responsiveness-build-5.md`.

## 2. How v1 works

v1 is a live mutation pipeline on the `@MainActor`. `FeedStore` owns everything and pushes
rendered-ready cards into `FeedDisplayState`. There is no immutable published history: the feed
is a mutable `visibleItems`/`visibleCards` pair guarded by generation counters and an epoch.

```text
RSSFetcher → persistFetchedItems (SQLite) ──┐
AdaptiveScheduler picks sources             │  all on FeedStore @MainActor
reloadFromSQLite → balancedCandidatePool ───┤
            ↓                               │
Reservoir (interleave + diversity + cap)    │
            ↓                               │
EditorialSequencer.sequence (round-robin)   │
            ↓                               │
CardPreparationCoordinator (actor)          │  off-MainActor media resolve
  prepareItem → resolve → decode → store    │
  takeRenderReadyPrefix (contiguous)        │
            ↓                               │
FeedDisplayState.publishCards ──────────────┘
            ↓
FeedLoader (cached projections) → SwiftUI

FeedRunwayController (actor): reportViewport → evaluate() → coordinator.fillRunway(target)
  pressure state machine with fixed watermarks (RunwayPolicy)
```

Key properties: scroll calls `loadMoreIfNeeded` (`FeedStore.swift:2911`) — scroll *is* a load
trigger. Context identity (`FeedPresentationContext`, epoch) is carried to reject stale async
results, but not uniformly across every suspension point. The runway runs two parallel control
systems: the fixed-watermark `FeedRunwayController` and the entropy/deficit `AdaptiveScheduler`.

## 3. Code review findings

| ID | Sev | File:line | Mechanism | Effect |
| --- | --- | --- | --- | --- |
| FP-1 | H | `FeedStore.swift` whole file (8293 LOC) | One `@MainActor @Observable` class owns DB, fetch, scheduler bridge, filter, publish, bookmarks, smart feeds, search, OPML/taxonomy, migration (`migrate` is 7467–7959, 492 LOC; `start` 1800–2248; `applyUpdate` 2607–2868). | No single owner per responsibility; every concern shares mutable state and the MainActor. The whole build-5 review (10 of 11 findings) traces here. |
| FP-2 | H | `FeedStore.swift:584-651` `applyFiltersOffMain`, `buildFilterInput:739`, called from `applyFiltersAsync:799` and append `~2296` | `buildFilterInput` walks `registry.sources` (~77k entries) on the MainActor before the `Task.detached`. | Every append during scroll pays catalog-proportional MainActor work → scroll hitches. (Build-5 finding 2.) |
| FP-3 | H | `FeedStore.swift:1612-1792` `fetchColdStartRunway`/`startFirstLaunchBootstrapIfNeeded`; restore at `~1784` | Warm start restores the persisted page only *after* OPML, taxonomy, filters, preset, read-state and bookmarks hydrate. | Local content in DB still shows a spinner until full catalog init completes. Violates "warm launch is local". (Build-5 finding 3.) |
| FP-4 | H | `FeedStore.swift:2607-2868` `applyUpdate` + `FeedDisplayState.swift` phase coupling | A filter change sets `.refreshing` + `.preparing`; publication refuses to leave `.preparing` while `.refreshing`, waiting on `fetchNextBatch` for count/diversity. | Usable local cards hidden behind a loading screen while the network finishes. (Build-5 finding 5.) |
| FP-5 | H | `FeedStore.swift:2478-2593` `promotePreparedCards`; context re-read noted in build-5 finding 6 | Epoch/generation exist but not every suspension boundary re-validates them; promotion checks epoch before awaiting `commitPublished`, not again before mutating UI; seed writes arrays after a detached await without re-checking. | Stale-context results can leak into the current composition (reservoir, cards, order, phase). (Build-5 finding 6.) |
| FP-6 | H | `CardPreparationCoordinator.swift` `upgradeDeferredToHero` (deferred retry) vs build-5 finding 1 | Original build published a text-only card, then a late image callback swapped media to `.image`/`.hero` in place, changing card height. Now fixed: upgrade only refreshes the runway entry for the *next* composition (see comment at `upgradeDeferredToHero`). | Was: layout shift under a reading user. Verified the current code freezes the published presentation; this is a *fixed* H, kept as a lesson. |
| FP-7 | M | `FeedRunwayController.swift:135-168` `computePressure` + `RunwayPolicy.swift:5-33` | Pressure thresholds are hard constants: `renderReadyCount < 20`, `estimatedSeconds < 30`, watermarks 20/60/120/180, 200/400/600, 500/1000/1500. | Fixed numbers *are* the strategy, not an operational bound. Directly contradicts v2 INV-04. |
| FP-8 | M | `FeedStore.swift` has both `scheduler = AdaptiveScheduler()` (`:124` region) and `SourceScheduler` (deprecated, still compiled) | Two source-selection mechanisms; `SourceScheduler` marked `@available(*, deprecated)` but present. | Two owners of the same responsibility (scheduling). Violates one-owner. |
| FP-9 | M | `FeedRunwayController` (watermark state machine) + `AdaptiveScheduler` (entropy/deficit) + `Reservoir` (interleave) | Three independent control loops decide "how much to prepare / fetch / buffer" with no shared authority. | Overlapping, hard-to-reason runway logic; the exact "two mechanisms of runway" v2 INV-12 forbids. |
| FP-10 | M | `Models/FeedCardPresentation.swift` (whole) + `PreparedFeedCard.swift` + bridge `init(from:)` | Two parallel card types coexist "during migration"; `FeedCardPresentation` is `@unchecked Sendable` holding a `UIImage` by pointer identity. | Dual model + unsafe Sendable; migration never completed. Presentation model carries a live `UIImage`, blurring publication/presentation. |
| FP-11 | M | `Reservoir.swift` `interleaveImpl` + `spreadForFreshnessImpl` + `EditorialSequencer.sequence` | Diversity is enforced in two places: Reservoir interleave (country/provider/category spreading) and then EditorialSequencer repairs runs again. | Two diversity passes; EditorialSequencer's own header admits the Reservoir order "is not an invariant of what gets published". Redundant, order-dependent. |
| FP-12 | M | `CardPreparationCoordinator.swift` `handleMemoryPressure`, `prefixWaiters`, `inFlightIDs` token logic, `suspendForPrefixSignal`/`cancelPrefixWaiter` | Correctness depends on a web of hand-written continuation/token/epoch guards (comments cite a "double-resume fatal error" and "leaked suspended tasks" fixes). | High-risk concurrency; several fatal bugs already shipped and were patched here (commit `6a10c7a3`). |
| FP-13 | L | `FeedMetrics.swift:9` "legacy backend and the FeedEngine migration"; `FeedCardPresentation.swift:5` "After Phase 9, this file will be removed" | Dead migration scaffolding left in the production tree. | Confusing; two code paths implied that never collapsed. |

## 4. What worked (keep the idea)

- **Terminal card before publication.** The core thesis of `docs/cards-resolvidos-antes-de-aparecer.md`:
  a card enters the feed only in a final visual state (image / placeholder / text-only); no
  post-insertion downloads, no placeholder→image swap. Encoded in `ResolvedCardMedia`/`PreparedFeedCard`
  and the coordinator's `decodeToRenderReady`. Evidence: doc acceptance criteria 1–10; `PreparedFeedCard.swift:95`
  ("renders directly — no loading states").
- **Contiguous-prefix promotion.** `CardPreparationCoordinator` resolves out of order but only
  promotes a contiguous editorial prefix (`peekRenderReadyPrefix`/`commitPublished`), so a slow
  item at position 3 never lets position 4 jump ahead. Evidence: coordinator class doc + `commitPublished`
  verifying `actual == expectedIDs`. Keep as the ordering guarantee.
- **Immutable published presentation (eventually).** The deferred-image path (`upgradeDeferredToHero`)
  now keeps a late image for the *next* composition instead of mutating the visible card. This is
  exactly v2 INV-08/INV-09. Evidence: the method's own comment + build-5 finding 1 marked for fix.
- **Hard per-item deadline.** `raceWithDeadline` + `deadlineForIndex` tiers (6s/15s/30s) guarantee a
  stuck image URL degrades to a placeholder rather than stalling the batch. Evidence:
  `CardPreparationPipeline.swift` `deadlineForIndex`, coordinator `deadlineForIndex`.
- **Provider diversity on the first screen.** `frontLoadUniqueProvidersImpl` (Reservoir) and
  `EditorialSequencer` least-used round-robin give the first page breadth; EditorialSequencer's
  header documents two *failed* heuristics and why the final one wins — a rare, useful record.
- **Pure warm-start rebuild.** `PreparedPageRestoration` is a stateless transformation
  (`projection + assets → cards`) with a bounded concurrent decode (`mediaDecodeLimit = 30`), using
  `reduce(into:)` to survive duplicate IDs. Clean separation. Evidence: file header (review P1.4).

## 5. What failed and why

Root causes, with commits and the build-5 review as evidence:

- **The god object is the root failure.** `FeedStore` accreted DB, fetch, filter, publish and
  catalog maintenance on one MainActor class. The build-5 review's ordered fix list (its §"Ordem da
  solução") is really "unpick `FeedStore`": lock the publish contract, release local content,
  move catalog-proportional work off the MainActor. The late P0/P1 commits are all surgery on this
  one file: `13c8ac63` (P0.2 persist terminal decision), `f07ed726` (P0.3 publish a complete page),
  `2f4dcc33` (P0.5 one owner for order), `9bfe5f9b` (P1.3 single production path), `62e32bac`/`5d045822`
  (P1.4 page-cache ownership). Decomposition came late and partially.
- **In-place media mutation shipped and shifted layout.** Build-5 finding 1 documents a published
  text card growing a 16:9 hero slot when a late download arrived, over a reading user. Fixed by
  freezing the published presentation (`CardPreparationCoordinator` `upgradeDeferredToHero`, commit
  `136272e0` P0.4 "decouple card presentation from filtering invalidation").
- **Stale-context leakage.** Epoch/generation were added but not threaded through every suspension
  (build-5 finding 6). The fix pattern — carry one immutable context through the whole operation and
  re-validate after every await and immediately before every shared mutation — is only partly
  realized in v1. The coordinator's TOCTOU "atomic guard+write" helpers (`storeResolved`,
  `storeRenderReady`) are the mature form.
- **Reservoir instability.** Several commits exist purely to stop content shifting under the reader:
  re-interleaving on append/move/cap reordered upcoming items (`append`/`moveToVisible`/`capReservoir`
  comments: "content shifted under them right before a tap"). `trimBuffer` once permanently discarded
  tail items and dead-ended the feed mid-session (comment cites "review finding H3"; it now returns
  them to the reservoir front). Diversity/clustering was retuned repeatedly (`ad226ec0` window 3→10,
  `65d1da91` swap-guard, `327cf920` offload interleave off MainActor).
- **Fatal concurrency bugs.** Commit `6a10c7a3` ("double-resume crash, startup race, destructive
  peek, memory demotion") and `794375cc` ("divide-by-zero crash + 8 structural fixes") show the
  continuation/waiter machinery crashed in production before stabilizing.
- **Two schedulers, two runways.** `SourceScheduler` was deprecated in favor of `AdaptiveScheduler`
  but left compiled; `FeedRunwayController` (watermarks) and `AdaptiveScheduler` (entropy) never
  merged into one authority.

## 6. Applying to v2

Legend: v2 state confirmed by reading the cited v2 file.

- **FP-1 → avoid the god object (now).** v2 already splits ownership across `FeedMineRuntime`
  (`FeedSession.swift` ~130 LOC, `RunwayController.swift`), `FeedMinePublication`,
  `FeedMineEditorial`, `FeedMineComposition` (`FeedRunwayDriver.swift`, `ColdFeedBootstrap.swift`).
  ARCHITECTURE.md explicitly bans recreating `FeedStore`. **Already handled** — the lesson is to
  hold the line: watch the size alarms (RunwayController own-alarm 300 LOC; v2 review **M22** flags
  it already at 409). Keep `FeedSession < 300`.
- **FP-2 → keep catalog work off the actor (now).** v1's MainActor filter walk maps to v2
  Editorial/Persistence. v2 `CandidateProvider`/`ContentStore.candidateWindow` do candidate
  selection in Persistence, not on a UI actor. Current risk is cost, not placement: v2 review
  **M8/M9** (N-row window scan, N+1 queries). **Already handled structurally**; recommend keeping
  the source-scoped query path (M8) before scaling supply.
- **FP-3 → warm launch is local (now).** Maps to `FeedSession.restoreLocalPresentation`
  (`FeedSession.swift`) + `FeedRunwayDriver.restoreAndActivate`. Read confirms restore reads
  `publicationHistory` and installs a window with no network call; INV-07 is a first-class invariant.
  **Already handled** — guard it with a test that restore + first snapshot happens with the
  connector stubbed to fail (v2 already has `FeedSessionWarmRestoreTests`, `OfflineRestorePersistenceTests`).
- **FP-4 → separate "has a valid presentation" from "is fetching" (now).** v2 does this cleanly:
  `RunwayController` emits demand/acquisition intents while `FeedSession` owns the installed
  presentation independently. `FeedRunwayDriver.drive` returns the current presentation and continues
  acquisition in the background. **Already handled**; the one gap is the UI not surfacing pending/failed
  work (v2 review **M17**) — port v1's `FeedDisplayPhase` idea (ready vs preparing vs empty vs failed)
  into the presentation surface. Priority: before shipping the feed screen.
- **FP-5 → one immutable context through the operation (now).** v2's equivalent is `RunwayScope`
  (edition + contextKey + editorialRevisionID) validated on every controller entry
  (`RunwayController.submitObservation`/`acceptMeasurement` throw `scopeMismatch`/`staleMeasurement`),
  and `FeedRunwayDriver.validateCurrentScope` before each drive. This is the mature form of v1's
  epoch. **Already handled and stronger.** Watch actor reentrancy: v2 review **M2** (`submitViewport`
  interleaving `drive`) is the same class of bug v1 hit — serialize `drive` or treat supersession as
  "re-reconsider", not a thrown error to the UI.
- **FP-6 → published presentation is immutable (now).** v2 `PublishedCard` is a frozen snapshot and
  the UI consumes `PresentationCard` projections (RUNTIME_PRESENTATION_CONTRACT.md; INV-08).
  **Already handled by design.** Keep the rule that a late media result produces a *future* edition,
  never an in-place swap — relevant when the media pipeline lands (v2 review **M15**: no media pipeline
  yet; `PresentationCard` carries no media key). Priority: before the media feature.
- **FP-7/FP-9 → adaptive runway, no fixed watermarks (now).** v1's `RunwayPolicy` constants map to
  v2 `FeedMineRuntime/RunwayPolicy.swift`, which is already fact-driven: it computes a threshold from
  measured `cardsPerSecond`, p95 replenishment latency, safety factor and release margin, returning
  `healthy/pressured/logicalPressure/unknown` — numbers are operational bounds (`readyProbeBound`,
  `examinedCandidateCapacity`), not the strategy. **Already handled and is exactly the v2 improvement
  over v1.** Caveat: v2 review **M6** — `.forwardBeyondProbe` clears consumption samples (same "fastest
  reader gets weakest response" trap); treat it as a lower-bound rate. Priority: now.
- **FP-8 → one scheduler (now).** v2 has a single `AcquisitionPlanner`/`AcquisitionCoordinator`
  (`FeedMineAcquisition`); no deprecated twin. **Already handled.** Do not reintroduce a second
  demand path (INV-14 forbids it).
- **FP-10 → one card model (now).** v2 separates `PublishedCard` (Publication) from `PresentationCard`
  (Runtime) by contract, with no `@unchecked Sendable` UIImage. **Already handled.** Do not add a
  "legacy" bridge type; INV-14/INV-15.
- **FP-11 → one diversity owner (before the editorial feature).** v1 ran diversity in Reservoir and
  then re-repaired in EditorialSequencer. v2 maps to `FeedMineEditorial/SelectionEngine` +
  `EditorialPolicy`. Current v2 `SelectionEngine` is ~110 LOC and deterministic; keep *all* ordering
  there and never add a second interleave pass downstream. Carry over the EditorialSequencer lesson:
  "no repetition while alternatives exist", never manufacture diversity. Priority: before expanding
  editorial policy. Note v2 review **H3** (republication by revision) is the adjacent correctness
  issue in this module.
- **FP-12 → prefer structured concurrency over hand-rolled continuations (now).** v1's prefix-waiter
  box/token/epoch machinery caused double-resume and leak crashes. v2 `RunwayController` is a plain
  serialized actor with value-typed intents and no manual `CheckedContinuation`; `FeedRunwayDriver`
  uses a `while true` drive loop. **Already handled** — but v2 review **M5** (unbounded `drive` loop)
  and **M2** (reentrancy) are the residual risks; bound the loop and single-flight `drive`.
- **FP-13 → no migration scaffolding (now).** Keep the tree free of "legacy"/"Phase N removal"
  comments; v1's never collapsed. **Already handled**; just don't regress (v2 review **L1** notes docs
  drift already).

## 7. Open questions for the product owner

1. **Edited-but-unversioned revisions.** v1 would re-surface a changed RSS item; v2 review **H3**
   leaves "edited revision = new card" undecided. Is a publisher edit a new feed occurrence or a
   silent update of existing history? This drives both Editorial exclusion and Publication identity.
2. **Late media after publication.** v1 settled on "freeze the visible card, apply the better image
   next edition." Confirm v2 wants the same: a late/better image creates a *successor edition*, never
   mutates a visible card — even if the user never scrolls back to see it.
3. **First-screen breadth vs freshness.** v1 spent many commits forcing one-card-per-provider on the
   first page (`frontLoadUniqueProvidersImpl`, EditorialSequencer). Is "every provider on screen one"
   a product promise v2 must keep, or may Editorial favor freshness/quality when supply is thin?
4. **Runway "feel" targets.** v1 used explicit p95 goals (local first page ≤1s, tap ≤100ms,
   no >100ms MainActor hog). Should these become v2 acceptance criteria / tests, given the policy is
   now adaptive rather than fixed-watermark?
5. **Memory-pressure behavior.** v1 demoted distant render-ready cards back to disk and re-decoded on
   approach (`handleMemoryPressure`). v2 has no eviction yet (review **M10**). What is the intended
   bounded-memory behavior for a very long reading session?

---

## Top 10 findings (summary)

1. FP-1 (H): `FeedStore` is a 8293-LOC MainActor god object; v2 already avoids it — hold the line.
2. FP-6 (H, fixed in v1): in-place media mutation shifted a published card's layout under the reader.
3. FP-3/FP-4 (H): v1 hid valid local cards behind a spinner until full catalog init / network finished.
4. FP-5 (H): epoch/context not re-validated at every suspension → stale results leaked; v2 `RunwayScope` is the fix.
5. FP-7 (M): v1 runway strategy was fixed watermarks (20/60/120…); v2 adaptive `RunwayPolicy` is the key improvement.
6. FP-2 (M): catalog-proportional (~77k) filter work ran on the MainActor on every append.
7. FP-9 (M): three overlapping control loops (RunwayController + AdaptiveScheduler + Reservoir) — v2 has one.
8. FP-11 (M): diversity enforced twice (Reservoir + EditorialSequencer); keep one owner in Editorial.
9. FP-12 (M): hand-rolled continuation/waiter code crashed (double-resume, leaks) before stabilizing.
10. Keep: terminal-card-before-publish + contiguous-prefix promotion + immutable published presentation + hard per-item deadline.
