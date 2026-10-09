# FeedMine v1 — Project History & Lessons Learned

> Static documentation archaeology of FeedMine v1 (`C:\workspace\feedmine-dev`) to inform v2
> (`C:\workspace\feedmine_v2`). No build performed. Evidence = git history + v1 docs; v2 claims
> cite v2 `ARCHITECTURE.md` / `PRODUCT_INVARIANTS.md` / `CODE_REVIEW_2026-10-08.md`.

## 1. Scope

- **Commits examined:** 1010, from **2026-06-30** (`2f765be1` "Add feedmine design spec") to **2026-09-17** (`b5c2f59c` "record the build 17 delivery").
- **Commit cadence:** 2026-06 = 13, **2026-07 = 878**, 2026-08 = 74, 2026-09 = 45. July was a ~29 commits/day sprint; the whole project is <3 months old.
- **Remote branches:** 17 live `origin/*` + 2 `upstream/*`; audit (`technical-quality-audit-2026-08-03.md` §9) counted 54 branches and a 3.0 GB `.git` at its snapshot.
- **"fix" commits:** 418 of 1010 subjects contain `fix` (~41%). `perf` 59, `crash` 9, `revert` 4, `regress` 2.
- **Docs read:** `technical-quality-audit-2026-08-03.md`; `release/HANDOFF.md`; `code-review-testflight-build-16.md`; `superpowers/specs/2026-07-07-feed-architecture-v2-design.md`; `superpowers/specs/2026-07-29-feedmine-prepared-feed-architecture.md`; `superpowers/plans/2026-08-04-feedstore-decomposition.md`; `superpowers/plans/identity-impact-report.md`; `UnifiedSelectionArchitecture-RemainingChecklist.md`. Skimmed: full `docs/` tree (5 `code-review-*.md`, ~30 superpowers specs/plans, roadmap).
- **v2 docs read:** `architecture/ARCHITECTURE.md`, `architecture/PRODUCT_INVARIANTS.md`, `reviews/CODE_REVIEW_2026-10-08.md` (+ status update @ `6116113`).

## 2. Timeline — architectural pivots

| Date | Pivot | Evidence |
|---|---|---|
| 2026-06-30 | Project born as "infinite feed prototype": reservoir buffer + interleave, in-memory. | `2f765be1`, `65678a53`, `3e98d2b1`; `dce45ff9` (2026-07-01) "add FeedLoader with reservoir, buffer management". |
| 2026-07-07 | **Pivot 1 — SQLite/GRDB persistence.** `PersistenceManager` (plist) dropped; 3 SQLite DBs, entropy scheduler, persistent search, FTS5. `FeedStore` created as data owner. | `caa9e2c3` add GRDB 7.4.0; `952d8cad` "create FeedStore with GRDB schema v1"; `1301ba61` "create Reservoir extracted from FeedLoader"; `1bf5728f` "merge: feed architecture v2"; spec `2026-07-07-feed-architecture-v2-design.md`. |
| 2026-07-13 | "Onda 3" first attempt to decompose FeedStore + DI. | `9341cef5` "refactor: Onda 3 — decompose FeedStore, DI, zero print()". |
| 2026-07-15 | **Pivot 2 — Taxonomy.** Single category filter replaced by hierarchical multi-select taxonomy tree built from OPML; language filter added. ~30 commits in one day. | `3eb815a2`…`c1e268e2` (all 2026-07-15); `7fdb680c` "replace single category filter with multi-select taxonomy node filter"; `616aef9e` later removes `TaxonomyTreeView` added hours earlier. |
| 2026-07-29 | **Pivot 3 — Prepared-feed pipeline.** 9-phase plan: cards made render-ready before publication; `CardPreparationCoordinator`, `FeedRunwayController`, `MediaAssetStore`. Enabled by default behind flag. | `30afc720`/`6185fc4d` docs; `1f7fca63` Phase 1 models; `6de1a427` Phase 3; `ad213030` Phase 7; `ab8ce4eb` Phase 8-9 "enable by default"; `81dda55e` "consolidate … single-path publication". |
| 2026-07-30 → 08-03 | **Pivot 4 — Unified Selection Engine, built then abandoned.** 60-test engine (Phases 0-7) landed 07-30/31; checklist "64/64 complete" (`f4954c2c`). Then ~13K lines deleted in `09acf5ea` (2026-08-03) **without ever compiling** (audit §2.1). | `b8d9edf7`, `eaca8082`, `fafe0016`, `f4954c2c`; audit §2.1 + §risk-matrix; `UnifiedSelectionArchitecture-RemainingChecklist.md` (58/64 pending at abandonment). |
| 2026-08-03 | Technical quality audit: "sound architecture but technical debt at an alarming rate." | `technical-quality-audit-2026-08-03.md`. |
| 2026-08-04 | **Pivot 5 — FeedStore decomposition (restart).** Phase 1 extracts `FeedDisplayState`; commit records **210 references still to migrate**. | `ee09a323` plan; `623cf0e6` "Phase 1 — extract FeedDisplayState". |
| 2026-09-15→17 | **Release 1.0 hardening + TestFlight builds 16/17.** Catalog http→https rewrite, LFS for `catalog.sqlite`, container-hygiene test fixes. Build 16 uploaded `VALID`. | `17a0051a`, `3adc2b49`, `b5c2f59c`; `release/HANDOFF.md`. |
| 2026-09-17 | **Regression review of build 16** diagnoses the prepared pipeline never achieved its invariants; recommends a concentrated rewrite — effectively the seed for v2. | `5d4a31d8`; `code-review-testflight-build-16.md`. |

## 3. Why v1 became complex and confusing

**Root cause A — the FeedStore god object.** `FeedStore.swift` is **8,293 lines today** (7,204 at the 08-03 audit), 4.4× the next file (`FeedScreen.swift` 1,891). Churn: **224 commits touch FeedStore, 188 FeedLoader, 122 FeedScreen** — the three most-changed files by far (`git log --name-only`). The audit (§3) lists ~30 `// MARK:` responsibilities inside it: db, registry, scheduler, reservoir, fetch, prefetch, filters, taxonomy, presets, collections, smart feeds, bookmarks, search, migration, maintenance, podcast counts, background refresh. Consequence recorded in the audit: "every change touches FeedStore," integration testing "almost impossible," 25+ public observable properties. Four separate docs asked for its decomposition before it was attempted (audit §3.2).

**Root cause B — three competing feed pipelines coexisting.** The build-16 review (§P1 "duas arquiteturas") enumerates `ReadyCardQueue` + legacy reservoir publishing + prepared `CardPreparationCoordinator`, gated at runtime by `preparedFeedPipelineEnabled` and scattered `if usePreparedPipeline` branches. It cites real bugs this duality caused: startup draining the whole reservoir because async `visibleItems` stayed 0; legacy `cardQueue` overwriting `visibleCards`; feed truncated to 20 cards (July), and the legacy path leaving `visibleItems` empty when the reservoir had items (August). A **fourth** pipeline (Unified Selection Engine) was built and deleted in the same window (`09acf5ea`).

**Root cause C — half-done migrations.** (1) FeedEngine/`catalog.sqlite` was built as a second data stack but "não alimenta a tela principal — dois caminhos de dados coexistem" (audit §2.1, §5). (2) Unified Selection: `UnifiedSelectionArchitecture-RemainingChecklist.md` ends **6 done / 58 pending** then the engine was deleted. (3) FeedStore decomposition `623cf0e6` left **210 references to migrate**; the 09-15 WIP snapshot then added 563 / removed 160 lines back into FeedStore (build-16 review §P1 "refatoração começou mas não terminou"). (4) `image_url = ''` used as a permanent "no image" sentinel conflating timeout/404/offline/no-image (prepared-feed spec §7.1). (5) `SourceScheduler` deprecated for `AdaptiveScheduler` but legacy code left in (audit §2.1).

**Root cause D — churn velocity outran quality gates.** 878 commits in July; code added and removed within hours (audit §1: "13K lines of Selection Engine deleted in one commit, never compiled"). CI ran **only `CatalogIdentityContractTests`** — 1 of 30 test classes (audit §8.1); Makefile masked failures with `|| true`; `pbxproj` edited by hand (every new Swift file = ~200-line diff), so merges across 17+ branches were fragile. Nothing caught regressions in FeedStore/FeedLoader/views.

**Root cause E — view-layer bloat mirrors the store.** `FeedScreen.swift` ~1,766–1,880 lines with ~40 `@State` properties and a fragile sheet chain (audit §4). Media state (`visibleCardsGeneration`) was wired into structural caches (`filteredItems`, `dateSections`), so a late image upgrade re-invalidated feed structure during scroll — the build-16 review's structural explanation for scroll stalls (§P0 "scroll travando").

**Root cause F — Python tooling debt in parallel.** 185 scripts, 8 versions of `discover_artist_blogs` (`v2/v3/v4/broad/batch/fast/zero`), two `fetch_all_feeds`, from incomplete refactors (audit §6.2). Cross-language identity contract (Swift `OPMLParser.normalizeURL` ↔ Python) duplicated in two places over 77,443 sources (audit §2.2).

## 4. Recurring bug classes

| Bug class | Count/estimate | Example commits | Root cause |
|---|---|---|---|
| Reservoir / interleave ordering & stability | ~30 (reservoir churn 30 commits; many "fix(Reservoir)") | `2fb10e49` stop reordering during scroll; `fc244773` preserve order on cap; `c50a9918` clamp to avoid `removeFirst` crash; `d66eb664` dedup before every interleave | Diversity/ordering lived as mutable Reservoir state re-run on many paths; no single immutable editorial sequence (build-16 review §P0 "diversidade no lugar errado"). |
| Filter / taxonomy pipeline | 94 subjects match `filter` | `fix/filter-pipeline-applyFilters` branch; `2527b902` rebuild cache in restoreFilters; `c1e268e2` invalidate cache on source-count change; `10126746` empty-state race | Global stateful `applyFilters` + manually-invalidated caches across region/taxonomy/language/preset generations. |
| Image / media resolution & display | 62 subjects match `image` | `edab5219` "Revert aggressive image slot collapse"; `50a16d6c` delete dead `withImageResolutionFailed`; prepared-feed spec §7.1 (`image_url=''` sentinel) | Image work started by the view (`CachedAsyncImage`), no single-flight, transient failures written as permanent. |
| Card display / published-state mutation | 56 subjects match `card`/`display` | build-16 review §P0.1 (text-only→hero in-place upgrade); `19828893` delete dead `prefetchWhatsNewImages` | Published cards mutated after publication; media generation invalidated structural generation. |
| Preset / selection / toggle round-trip | 55 subjects match | `fix/collection-preset-roundtrip` branch; `07ac558d` clear memory on toggle; `e97e1d22` re-enabled region items return to reservoir | Preset multipliers were the only priority source; empty dict for `.everything/.lastClicked/.smartFeed` (build-16 review §P1 quality). |
| Pipeline duality regressions | ≥6 named in build-16 review §P1 | `81dda55e` consolidate single-path; `9bfe5f9b` "prepared pipeline is the only production path" | Two/three pipelines writing the same visible state. |
| Startup / warm-start / cold-start | ~17 `scroll/pagination/infinite` + HANDOFF cold-start 28.5 s | `13c8ac63` persist terminal card decision for warm start; build-16 review §P0 cold-start `prefix(20)` fallback | Warm start restored `FeedItem`, not prepared cards; cold start published incomplete runway after 12 s deadline. |
| Reverts / rollbacks | 4 reverts, 2 regress | `e5248108` GRDB revert cleanup; `df16394f` roll back artist-blog OPML; `edab5219`; `0a6365d5` revert unrelated changes | High velocity, broad-blast changes without gates. |

## 5. Product & release learnings worth preserving

- **"Feed is sacred" is the product's north star.** Prepared-feed spec §2.7 and build-16 review make it the top invariant: no reordering near the user, no head removal, no scroll jump, no changing published IDs, stability > novelty. v2 encodes this as INV-08/09.
- **Stability beats freshness on reopen.** Build-16 review: "40 old fully-prepared unseen cards are more valuable for the initial experience than 5 freshly-downloaded incomplete ones."
- **Editorial order must be independent of media/CDN speed** (prepared-feed spec §2.1). A slow server must never move or drop an item.
- **Breadth/diversity at the head of the feed is the product promise** (build-16 review §P0): √n regional fairness (feed-arch-v2 §3), provider spacing, country spreading.
- **Measured performance targets to carry forward (from `release/HANDOFF.md`, build 16 on iPhone 16):** warm relaunch loading surface **234 ms** (page restored from disk, no refetch); cold first install **28.5 s** for 20 cards off network (empty SQLite); unit gate **460 tests, 0 failures × 3 runs** (107–110 s); interleave-1000 ~326 ms. Filter case A measured **8.19 s blank** when the page is cleared — the known lever is *don't clear a prepared page*, not query tuning.
- **Release-engineering lessons (HANDOFF, hard-won):** certify a journey by a required **basename set**, not a file count; **clean the simulator container between runs** (inherited container caused a 37 s wait vs 0.3 s); a readiness gate that **expires before the app is ready fabricates surfaces** (budget raised 30 s→150 s); measure rendered pixels not accessibility trees; a wall-clock `sleep` samples the network not the app; serialize device + build with a real lock. **Every TestFlight upload must carry an unambiguous SHA/tag** — build 16 could not be mapped to a commit (review "Observação sobre o build 16").
- **Identity contract held under change:** `identity-impact-report.md` — 77,443 sources, 0 changed/collided/rejected across the 08-03 fixes; validated by `CatalogIdentityContractTests` (the one test CI actually ran). Cross-language canonicalization is worth keeping, with vectors.
- **Catalog hygiene:** `catalog.sqlite` (118 MB) belongs in Git LFS; http→https rewrite of 3,666 URLs / 117 files before shipping (HANDOFF).

## 6. v1 problems vs v2

| v1 problem | v2 prevents? | How (v2 cite) | Still needed |
|---|---|---|---|
| God object (8.3K-line FeedStore) | **Yes (by rule)** | ARCHITECTURE "Clean rewrite": "Não criar FeedStore, FeedRuntime monolítico…"; 10 production modules with one owner each; size alarms (FeedSession <300, SelectionEngine <400). INV-12. | Enforce alarms in review; `RunwayController` already 409 LOC vs 300 alarm (CODE_REVIEW M22). |
| Multiple competing pipelines + feature flags | **Yes (by rule)** | INV-14 "No hidden alternate pipelines"; ARCHITECTURE "Não há runtime de compatibilidade, caminhos alternativos ou pipeline de background separado." | Hold the line; resist a "search pipeline" exception (CODE_REVIEW M18 `.search` throws). |
| Half-done migrations / two data paths | **Partial** | Single Swift Package, one composition root (FeedMineComposition); INV-12 one owner. | Phase gating is active but most modules are still scaffolds; PublicationStore representation deliberately unresolved (ARCHITECTURE), so the hardest migration is still ahead. |
| Published cards mutated after publication (text-only→hero) | **Yes** | INV-08 immutable published history; INV-09 background work doesn't disturb visible history; Publication→Presentation boundary ("PublishedCard is a frozen snapshot"). | Keep media changes out of structural generation when media lands (CODE_REVIEW M15: media pipeline still absent). |
| Diversity/ordering as mutable Reservoir state | **Partial** | FeedMineEditorial `SelectionEngine` is the single owner of order; build-16's "EditorialSequencer" idea realized as a module. | No explicit automated diversity assertion on final output yet; H3 duplicate-card bug open (CODE_REVIEW H3). |
| Image work started by the view / no single-flight | **Yes (by rule)** | INV-02 "SwiftUI nunca inicia acquisition / resolve mídia remota"; INV-01 local presentation; FeedMineMedia owns preparation. | Media pipeline unimplemented (CODE_REVIEW M15); UI can't render images yet. |
| `image_url=''` sentinel conflating failure types | **Partial** | Admission/translation boundary (INV-13); schema-level invariants praised (CODE_REVIEW Strengths). | No resolution-state table equivalent yet; retention/eviction deferred (M10). |
| Scroll triggers fetch/pagination | **Yes (by rule)** | INV-03 "Scroll is observation"; INV-04 adaptive runway; RunwayController emits demand. | **Not wired:** `FeedScreen` never calls `submitViewport` (CODE_REVIEW M14) — invariant has no producer yet. |
| Warm start restores items, not prepared feed | **Yes (by design)** | INV-07 warm launch is local: restore session/publication → materialize window, no network; immutable publication history. | PublicationStore persistence representation still unresolved (ARCHITECTURE phase gate). |
| CI runs 1/30 test classes; masked failures | **Partial/No** | Clean rewrite, 11 test targets reported (CODE_REVIEW L1). | **No CI** (CODE_REVIEW L4): ~13K LOC of tests never run automatically; no `.gitignore`/`Package.resolved` (L2/L3). |
| Manual pbxproj, fragile merges | **Yes** | Single SwiftPM `Package.swift`, Swift tools 6.0, no `.xcodeproj`. | Add `.gitignore`, commit `Package.resolved` (CODE_REVIEW L2/L3). |
| Python tooling debt (8 script versions), 118 MB in git | **N/A (out of scope)** | v2 is a Swift package only; no catalog tooling re-imported. | Decide v2's supply/connector source strategy (FeedConnector, still no API — ARCHITECTURE). |
| One failing feed stalls everything | **No (new, same shape)** | — | CODE_REVIEW H1 (poison batch) + H2 (one target aborts all; sequential, no backoff) are open in v2. |

## 7. Process lessons

- **What helped:** spec-driven development — every pivot had a design + plan doc (`superpowers/specs` + `plans`), and the 08-03 audit and 2026-09-17 build-16 review are high-quality, evidence-based artifacts that correctly diagnosed root causes rather than symptoms. The one test wired into CI (`CatalogIdentityContractTests`) protected the most load-bearing contract (77,443 sources, 0 drift). The HANDOFF discipline of recording every measurement with its commit prevented re-deriving results.
- **What hurt:** (1) **Velocity without gates** — 878 July commits, CI covering 1/30 classes, `|| true` in the Makefile; large speculative builds (Unified Selection Engine, ~13K lines) merged and deleted without ever compiling. (2) **Decomposition deferred repeatedly** — four docs asked to split FeedStore; it kept growing (7,204→8,293). (3) **Fixing symptoms inside a coupled graph** — build-16 review explicitly warns the team was doing "remendos em cima de remendos" and that touching timeouts/source-counts/reservoir size would just produce "mais uma rodada de regressões." (4) **Doc drift** — README said 34,243 sources vs 88,084 actual (audit §9.1); v2 is already repeating this (CODE_REVIEW L1: README/ARCHITECTURE claims contradict the code). (5) **Mixed PT/EN docs** with no rule (audit §9.1). (6) **No build↔TestFlight SHA traceability** (build-16 review).
- **Transferable rule for v2:** the biggest single win would have been enforcing CI + size alarms *from day one*; v2's invariants encode the architecture well but **CODE_REVIEW L4 shows CI still absent** — the exact gap that let v1 erode.

## 8. Open questions for the product owner

1. **Edited unversioned revision = new card or same card?** v1 never settled this; v2 CODE_REVIEW H3 needs an explicit `PRODUCT_INVARIANTS` ruling before Editorial exclusion is correct.
2. **Cold-start contract:** v1 shipped a 12 s "publish `prefix(20)`" fallback the review called wrong. Is a longer honest loading screen (INV-06) acceptable to users, and what is the max tolerable cold-start time (v1 measured 28.5 s)?
3. **Supply source for v2:** v1 carried a 118 MB precompiled catalog + 185 Python scripts. Does v2 re-use that catalog, re-implement discovery, or go pure-RSS-at-runtime? `FeedConnector` has no API yet (ARCHITECTURE).
4. **Diversity as a testable invariant:** should v2 add an automated assertion that the final editorial sequence rejects N consecutive same-provider cards when alternatives exist (build-16 review acceptance criterion)?
5. **Media/retention policy:** v2 has no media pipeline (M15) and no eviction (M10). What are the image size/dimension limits (v1 hardened to reject >12 MB) and the local retention window (v1 used 30 days + permanent for read/bookmarked)?
6. **TestFlight traceability + CI:** will every v2 upload carry a Git SHA/tag, and will CI (`swift build`/`swift test`) be mandatory before merge (CODE_REVIEW L4)?
7. **Fairness/resilience:** v2 H1/H2 (one bad feed stalls all, no backoff/parallelism) are the v1 "secame tudo" problem reborn — accept per-target isolation + bounded parallelism as a requirement now?

---

### 10-line summary
1. v1 is a <3-month, 1010-commit project (2026-06-30→09-17); July alone had 878 commits and 41% of all commit subjects say "fix".
2. The core failure is a 8.3K-line `FeedStore` god object — the most-churned file (224 commits), holding ~30 responsibilities.
3. Up to **four feed pipelines** coexisted; the Unified Selection Engine (~13K lines) was built then deleted (`09acf5ea`) without compiling.
4. Migrations were chronically half-done: FeedEngine never fed the UI, decomposition left 210 refs, `image_url=''` conflated failures.
5. Velocity outran gates: CI ran 1 of 30 test classes, Makefile `|| true`, hand-edited pbxproj across 17+ branches.
6. Top recurring bug classes: reservoir ordering (~30), filters/taxonomy (94), image/media (62), card mutation (56), preset/toggle (55).
7. Worth preserving: "feed is sacred," stability>novelty on reopen, √n regional fairness, warm-relaunch 234 ms, identity contract 0-drift over 77,443 sources, HANDOFF release discipline.
8. v2's invariants (INV-01/02/03/07/08/09/12/14) prevent most structural v1 problems *by rule* — god object, alternate pipelines, scroll-triggered fetch, mutable published cards.
9. v2 does **not** yet address: no CI (L4), scroll not wired to runway (M14), no media pipeline (M15), and H1/H2 revive the "one bad feed stalls all" class.
10. Biggest transferable lesson: enforce CI + size alarms + build↔SHA traceability from day one — the gap that let v1 erode is still open in v2.
