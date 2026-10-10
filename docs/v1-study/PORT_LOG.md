# v1 → v2 port log

Changes that bring v1 lessons (`docs/v1-study/`) and product decisions
(`docs/product/PRODUCT_DECISIONS_2026-10-09.md`) into v2 code.

**Historical status of rounds 1–3: written without a compiler.** These changes have not been built or tested; there is no
Swift toolchain on the machine where they were written. Local compilation/validation has now begun; see `docs/reviews/OMP_VALIDATION_2026-10-09.md`. Before building on any of this, run
`swift build && swift test` and fix whatever fails.

| Commit | Change | Lesson / decision | Tests added |
| --- | --- | --- | --- |
| `5d11c8e` | `.gitignore` for SwiftPM/Xcode artifacts (`Package.resolved` stays committed) | PD-7, review L2 | — |
| `5d90da4` | Readable text decodes the complete HTML 4.01 named entity table (`HTMLNamedEntities.swift`) instead of 18 entries | IN-6 (v1 fixed this twice) | `PublishedTextNormalizationTests.testH5bCompleteHTML4NamedEntities` |
| `796fddf` | Future `authoredAt`/`modifiedAt` clamped to `observedAt`; version identity keeps the claimed value | IN-4, review M12 | `SyndicationTranslatorTests.test26` |
| `292fea0` | https → http redirect refused (`invalidRedirectTarget`, already an operational failure) | IN-2, review M13 | `SyndicationHTTPTests.test07b` |
| `8cfc531` | Card-visual admission rules (`SyndicationMediaLocator.swift`) and more image sources. See "Media admission" below. | MD, IN quirks 4–8 | `SyndicationTranslatorTests.test27`–`test31`; `test22`/`test23` dimensions raised above the 150 px logo rule |
| `5a0149d` | Link-derived item identity normalized (`SyndicationItemIdentity.swift`): host case, `www.`, scheme, default port, trailing slash, fragment, tracking/session params. guid/id values and the opening link are unchanged. | IN-3, PD-1 rule 1 | `SyndicationTranslatorTests.test02`, `test02b` |
| `9ae4b72` | `MediaPolicy`, `MediaResolver` and `MediaRetention` as pure values. See "Media policy and retention" below. | PD-6, MD lessons 4–8 | `MediaPolicyResolverTests` (10) |
| `ee99228` | PD-4 source alternation via a new sequencing behavior. See "PD-4 source alternation" below. | PD-4, FP-11, CE-5 | `SelectionEngineTests.testPD4*` (5) |

## Details

**Media admission (`8cfc531`).**
- Relative, protocol-relative and `&amp;`-escaped locators resolve against the item link.
- Not admitted: tracking pixels, spacers, avatars, emoji, share buttons, favicons, sized variants ≤150 px, SVG, audio/video/PDF/HTML, and malformed nested schemes.
- New image sources: `media:content`, `media:group`, image enclosures (RSS and Atom), JSON image attachments, and the first content image in item HTML (aware of lazy `data-*` attributes and `srcset`, preferring ≥960 w).
- Duplicate locators collapse to one candidate.

**Media policy and retention (`9ae4b72`).**
- Pixel targets come from slot width × screen scale.
- Economy mode turns on under Low Power Mode, serious or critical thermal state, or a constrained or expensive network path.
- Byte budget = measured throughput × the runway's wait budget, capped by safety ceilings.
- The resolver picks the smallest candidate that fills the slot. If there is none, the card is a designed text-only card.
- Disk budget is derived from free space. Eviction order: far-future unseen, seen long ago, seen recently, near-future. Bookmarked media is never evicted.

**PD-4 source alternation (`ee99228`).**
- New sequencing behavior `.recencyAlternatingSources`.
- Candidates now carry their source memberships.
- The Edition tail counts as the previous card, so alternation holds across segments.
- A card that cannot be placed is held, and the supply cursor rewinds so it is considered again later.
- Single-source contexts are exempt.
- The app uses sequencing policy v2 for new Editions.

## Round 2 — 2026-10-09 (all fronts, still uncompiled)

| Commit | Change | Lesson / decision | Tests added |
| --- | --- | --- | --- |
| `fdafa3a` | The translator's version identity is the claimed date plus a SHA-256 fingerprint of the material content. An edit under an unchanged `updated`/`date_modified` is a new version and is no longer rejected forever. | PD-1, H1 follow-up 1 | `SyndicationTranslatorTests.test32` |
| `4996497` | New exposure behavior `.excludePublishedMaterial`: an edited article (collapsed title or text differs) reappears as a new card. `PublicationStore` enforces this in the append transaction. 3R5 behavior is unchanged under `.excludePublishedRevisions`. The app uses exposure policy v2. | PD-1 (amends 3R5) | `EditedArticleRecurrenceTests` |
| `e7d94b6` | Per-target backoff: delay doubles from the request timeout and is capped; one success clears it; cooling targets are skipped during planning. `executeConcurrently` runs a sliding window that refills on each completion (cores-sized in the app, 1 by default). | H2 residuals 2–3, IN-8 | `AcquisitionBackoffConcurrencyTests` |
| `b9eaca2` | M6: `forwardBeyondProbe` records a lower-bound rate instead of wiping samples. M7: a failed local slice becomes retryable after a doubling delay, and the app schedules that opportunity. M2/M5 were already solved by the driver's single-owner causal execution. | M6, M7 | `RunwayControllerTests` (M6 assertion and a new retry test) |
| `d36d25e` | End-to-end card images. See "Card images" below. | PD-5, PD-6, M15, MD-1/2/5/6 | `MediaPrefetcherTests` |
| `71f3440` | First-launch preparation built from real evidence. See "First-launch preparation" below. | PD-3, M17, INV-06 | `PreparationProgressTests` |
| `55481ec` | Tidying while the app is not visible: `MediaHousekeeping` plus `MediaTidy`. It completes media for the next cards and evicts down to the free-space-derived budget, keeping the visible window last. Published cards are never rewritten. | PD-5, PD-6 rule 3 | `MediaHousekeepingTests` |
| `251e1da` | v1 catalog import. See "v1 catalog import" below. | PD-2, CE-1 | `LegacyCatalogReaderTests`, `LegacyCatalogImportTests` |

**Card images (`d36d25e`).**
- `MediaPrefetcher` is the single media owner. It resolves the supply head with `MediaResolver`, downloads with a byte ceiling, materializes, and picks hero or thumbnail from the measured pixels.
- `MediaReadiness` feeds the `prepare` closure, so every card is either a real image or designed text-only.
- `FeedSession` decodes local assets at slot size. `FeedCardView` keeps a fixed slot height using the frozen aspect ratio.
- `MediaHTTPFetcher` handles transport. The app supplies device-measured conditions.

**First-launch preparation (`71f3440`).**
- `PreparationProgress` holds the sources, admitted headlines and a measured time estimate; `ColdFeedBootstrap` emits the evidence.
- `FeedPreparationView` shows a headline deck and source chips, with Reduce Motion support.
- `FeedWorkBadge` shows pending or failed work while cards stay visible.

**v1 catalog import (`251e1da`).**
- `LegacyCatalogReader` reads `catalog.sqlite` read-only.
- `LegacyCatalogImport` derives deterministic v8 UUIDs from the v1 canonical key.
- The app follows the bundled catalog's defaults when the file is present.

A static audit of all round-2 commits found no compile or test-consistency defects. That audit is not a build.

### Known gaps at round 2 (status 2026-10-09: all addressed — successor tail and PD-1 rule 2 by Codex T5, catalog by release asset, source choice by T4)
- **PD-5, unseen published cards.** Already-published but unseen cards are not re-prepared with late media. That requires a Publication successor-tail mechanism; until then, late media improves only future cards.
- **PD-1 rule 2** (at most one unseen future occurrence per origin) is not enforced.
- **PD-2 catalog file.** The 118 MB `catalog.sqlite` is not in this repo. Bundle it (LFS) or download it, then add it to the app's Copy Bundle Resources.
- **PD-2 onboarding.** Source choice and onboarding are not built. The app registers at most 64 default catalog sources.

## Round 3 — 2026-10-09 (comparative review F01–F16, uncompiled)

Commits `5906b9a` through `f0fa2ef`; the per-finding status table is in `docs/reviews/CODE_REVIEW_COMPARATIVO_2026-10-09.md` (Resposta).

Additional device checks:
11. **Slow image.** Block one image URL so it never answers. The first screen still appears within about 5 s, and that card is text-only (F03).
12. **Flaky image host.** Images return after the network recovers; they are not stuck as text-only (F04).
13. **Stationary reader.** After launch, leave the app idle. Published cards ahead keep growing to the 16-card reserve (F01).
14. **One slow feed.** The first screen appears as soon as the fast feed answers (F06).
15. **All feeds failing, then recovering.** Content arrives with no gesture (F08, F16).
16. **Background during a scheduled retry.** No work runs while hidden (F09).
17. **Tap a card.** The article opens in Safari (F10).
## Device test checklist (needs a Mac and an iPhone)

Run `swift build && swift test` first. Then on device:

1. **Cold first launch.** The preparation screen shows real source names and headlines arriving and is not a progress bar. The first screen has no two adjacent cards from the same source (PD-4).
2. **Images.**
   - Cards are hero, thumbnail or designed text-only. None show an empty image.
   - Scroll for a while: card heights never jump.
   - Slow network: more text-only cards, no stalls.
3. **Late image.** Put the app in the background and reopen it. Visible cards are unchanged (PD-5) and later cards gain images.
4. **Edited article.** Edit an item in a test feed (same guid/date, new text) and refresh. The article appears again as a new card further down (PD-1).
5. **Broken feed.** Add an unreachable feed. Other feeds still arrive and the broken one stops being retried every cycle (H2 backoff).
6. **Fast scroll.** The runway keeps up (M6). Airplane mode mid-scroll, then back: work resumes without a new gesture (M7 retry).
7. **Low Power Mode, Low Data Mode, little free space.** Smaller images; media disk use shrinks after backgrounding (PD-6 tidy).
8. **Reduce Motion.** The preparation screen stops its drift. VoiceOver reads one summary.
9. **Catalog bundled.** Feeds come from the catalog defaults; relaunch keeps the same sources (stable UUIDs).
10. **Logs.** Check `tidy evicted=… reclaimed=… budget=…` on backgrounding.

## Next candidates (round-2 list; successor tail, PD-1 rule 2 and source choice/search are done; taxonomy browsing and diversity beyond PD-4 are not started)

- Publication successor-tail mechanism, to re-prepare unseen published cards while the app is not visible (PD-5).
- PD-1 rule 2 (one unseen future occurrence per origin).
- Onboarding / source choice over the v1 catalog (PD-2), and taxonomy/search over catalog nodes.
- Diversity beyond source alternation (provider spacing, editorial quality from catalog `quality_score`).


## Fechamento Codex — 2026-10-09

Branch `codex/omp-plan-execution`, código `f8eb67e`: fontes/contextos/busca local persistidos, cauda não vista transacional e bookmarks/uso de mídia integrados. Pacote final: 827 testes, zero falhas. Release no simulador compilou; resultados iOS e limitações estão em [relatório OMP/Codex](../reviews/OMP_VALIDATION_2026-10-09.md). (Histórico: o catálogo estava em LFS com upload recusado. Desde `8c31b83` é o asset da release `catalog-v1`, instalado por `scripts/fetch-catalog.sh`; clone limpo verificado pelo OMP na rodada 4.) iPhone 14 Plus/15 indisponíveis; checklist físico e energia/térmica permanecem pendentes.

## Round 4 — 2026-10-09 (integration after Codex, uncompiled)

- `main` fast-forwarded to `codex/omp-plan-execution` (`9503a5a`); Codex's 827/0 package and 15+3 iOS results apply to `f8eb67e`.
- `8c31b83` F02: the catalog is the asset of release `catalog-v1` (sha256 `c2ae483a…`, 117,940,224 bytes, verified after upload). `scripts/fetch-catalog.sh` downloads and verifies it. LFS is no longer used. Existing checkouts lose the tracked file on pull and must run the script once.
- `e78786e` catalog search ranks by title prefix, then `quality_score`, then key (test added, not run).
- Still open, needs a product decision: diversity beyond PD-4 (provider spacing, `quality_score` in editorial selection) and taxonomy browsing over catalog nodes. Not started, so no ranking is invented without a defined meaning.
- Still open, needs hardware: the physical checklist above, plus energy, thermal and memory measurements.

## Round 5 — 2026-10-09 (OMP round-4 findings, uncompiled)

Answers `docs/reviews/OMP_ROUND4_VERIFICATION_2026-10-09.md`:
- **C1 (major).** Saved keys missing from the catalog are dropped. If none survive, the app falls back to the starter set, and a source context for a dropped source resets to main. `preferences` is assigned before anything can throw. New test `testSavedKeysMissingFromCatalogAreRepairedNotFatal`.
- **C4.** The same set of sources in another order is the same selection, so the version is not bumped (test added).
- **K4/K6.** Search order is v1's catalog sort key: title prefix, `default_enabled`, `quality_score` descending, then title. The test now discriminates DESC from ASC. The reader-contexts spec records this as search order, not feed ranking.
- **K7.** `fetch-catalog.sh` checks for `shasum`/`sha256sum` and `curl` before downloading.
- **K2/K3.** The doc drift is fixed.
- **Not done here:**
  - D1 (first screen 100% BBC, NPR/Guardian never fetched while idle) needs the repro the report describes. It is also a product question.
  - C2, C3, C5–C9 are Codex-slice items.
  - FTS5 search is optional; the measured gain is in the report.
- **R15** (ChatGPT review `FeedMine_V1_vs_V2_Code_Review_Comparativo`), commit `555a656`. `NetworkHostPolicy` refuses loopback, LAN, link-local, metadata and numeric-shorthand hosts at media admission, before each fetch, on every redirect and on the final URL. Tests added. A DNS name that resolves to a private address is not covered.
- **ChatGPT review, other open items.** R01 overlaps D1. R16 (AppComposition size) is a refactor that needs a compiler. R09 (estimate quality) and test-only gaps are R04, R06–R08, R11 and R13.

## T1 — 2026-10-09 (V1 frontend transfer, inventory only)

Plan: `docs/superpowers/plans/2026-10-09-transferencia-frontend-v1-v2.md` (T1 of T1–T12).

- **New:** [`UI_TRANSFER_MATRIX.md`](UI_TRANSFER_MATRIX.md) — every V1 surface/control with the symbol that
  implements it, the service it touches, its V2 destination and the delivery (T4–T11) that carries it.
  Sections: shell/header/menu/search (24 rows), cards (5), filters (5), sources/catalog (8), collections/
  bookmarks (5), reader/media/share (5), settings/import-export (8), onboarding (9 + 4 orphans), appearance (4).
  V1 orphans (`StoryDuelScene`, `StoryDuelCard`, `ChoiceFeedbackOverlay`, `ConfidenceProgressView`,
  `FeedScreen.SourceSearchDetailView`) are recorded as **not** transferred; the only DEBUG-only control is the
  catalog-explore button plus `CompactDebugInfo`.
- **New:** [`../reviews/V1_UI_REFERENCE.md`](../reviews/V1_UI_REFERENCE.md) — checkout revisions (V1 `712a6ba`
  + the comment-only dirty `Views/FeedScreen.swift`; V2 `372f4c5`), the V1 build command that succeeded
  (Xcode 26.6, iPhone 17 Pro Max simulator), the observed conditions (viewport, locale, launch args, data
  origin) and four recorded limitations.
- **Evidence:** `docs/evidence/v1-ui/` (git-ignored, reproducible) — feed portrait light, feed landscape,
  in-app article reader, `nightMode` state.
- **Limitations recorded, not hidden:** V1's `TestConfiguration` fixture vocabulary (`-fixture-profile`,
  `-fixed-theme`, `-network-profile`) is parsed but never read by the app, so the reference content is
  persisted real content, not an injected fixture; system dark appearance does not drive V1's palette
  (`CircadianEngine` + `nightMode` do); menu/filter/lens screenshots could not be taken by pointer automation
  inside the Simulator window and are deferred to the V2 UI tests of T5/T6.
- **No code changed by T1.** No row is `validado`; every row is `inventariado` until a delivery proves the
  flow.

## T2 — 2026-10-09 (production separated from admission)

Plan task T2. Codex reviewed the design before the commit (`Replicate stable Feedmine 1 UI` thread) and
three of its findings changed the implementation.

**The defect, measured.** At `372f4c5` the reader's list could change with no gesture:
`FeedRunwayDriver.driveCausalEffects` called `session.refreshCurrentPresentation()` after a published local
slice, and `AppComposition.foreground()` called it on every return to the app. Pre-change evidence: with the
T2 working tree stashed, `swift test --filter FeedSessionRunwayTests` passed **including**
`test03RefreshAppendsLocalViewPreservingAnchorAndCapacities` — a test that asserts a stationary reader's
presented window grows from 2 to 3 cards after production. That test is gone; the behavior it pinned is the
behavior this task removes.

**What changed.**

| Area | Change |
| --- | --- |
| `Sources/FeedMineRuntime/FeedPresentationAdmission.swift` (new) | `FeedPresentationBounds` (backward/forward capacity + optional context key) and the three admissions `.initial(bounds)`, `.forwardScroll(ViewportObservation)`, `.restore(bounds)`; `RunwayActivity.admitsForwardContent` = `forward` \| `explicitTailApproach` |
| `FeedSession` | `admitPresentation(_:)` is the only path that changes the admitted list. `.initial` installs once per session (`hasAdmittedInitial`), `.restore` only when no presentation exists, `.forwardScroll` appends published cards after the admitted tail, bounded by the frozen forward capacity, and refuses an observation that is no longer the reader's current anchor. Bounds are validated at installation and frozen in `FeedSessionState` (negative capacities throw `FeedSessionError.invalidMaterializationBounds` before any state is read). `submitViewport` now only records: `markSeen` plus an anchor move inside the admitted items, no window read. `refreshCurrentPresentation` and the capacity parameters of `restoreLocalPresentation` are deleted (no callers remain). |
| `FeedRunwayDriver` | The published branch of `.runLocalSlice` no longer refreshes. `submitViewport` records, submits the runway observation, admits only for a forward activity, then drives. `restoreAndActivate` restores with the plan's **own** context key instead of a global checkpoint. |
| `ColdFeedBootstrap` | Installs the first presentation through `.initial(bounds)` for the plan's context; no capacity parameters left in its API. |
| `AppComposition` | `FeedAssociation` holds frozen `bounds`; `launch()` admits `.initial`, `foreground()` drives production only and admits `.restore` only when no presentation exists. |
| `FeedPresentationSnapshot` | `FeedSessionError.invalidMaterializationBounds`. |

**Codex review, applied.** (a) An old forward event could admit after production finished, installing a
stale anchor — fixed by the anchor-currency guard plus admitting *before* awaiting production, so a gesture
reveals only what was already ready and the cards it produces wait for the next genuine scroll. (b)
`forwardCapacity / 4` was a demand heuristic in the wrong layer — removed; the UI reports genuine movement,
the session enforces currency, append-only order and batch size. (c) Decoded-image residency still grows
with the admitted list — `PresentationCard` strongly owns its `CGImage`; that policy belongs to T3 and is
recorded there, not silently accepted. Codex found no cold-bootstrap widening path and no other production
path that can change the list.

**Tests.** New `FeedPresentationAdmissionTests` (7 cases): stationary preparation does not extend the list
while the reserve grows; retry/recovery/repeat-initial are inert; the initial admission is not repeated; a
forward scroll admits only the ready prefix in order; a stationary observation moves the anchor without
changing items; a backward observation does not admit; recovery without a checkpoint installs nothing.
~20 existing tests that pinned the removed "production rematerializes the window" physics were migrated to
the new contract, keeping their original subject; the two that encoded a session-level context switch
(`testR15`, `testP6`) were rewritten to the model the app actually uses — one session per context — and now
prove that a suspended opportunity cannot touch another context's presentation, edition or checkpoint.

**Verification.** `swift build` clean; `swift test` **849 tests, 0 failures**; iOS build
`xcodebuild -scheme FeedMine -destination 'platform=iOS Simulator,id=8871DCF5…' CODE_SIGNING_ALLOWED=NO build`
→ **BUILD SUCCEEDED**. Docs updated in the same commit (`RUNTIME_PRESENTATION_CONTRACT`, `FILE_RESPONSIBILITIES`,
`ACQUISITION_DESIGN`, `IMPLEMENTATION_ORDER`) — no architecture doc mentions the deleted APIs.