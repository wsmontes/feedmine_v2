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

## T3 — 2026-10-09 (scroll admits; existing content does not move)

Plan task T3. Consumes the T2 boundary.

**What changed.**

| Area | Change |
| --- | --- |
| `Sources/FeedMineUI/Reader/FeedScrollPosition.swift` (new) | The reader's transient visual position: one reference card, the offset inside it (clamped to the card's own height), the placement. UI state only — it decides nothing and is never persisted; the session keeps admission authority. |
| `FeedMineUI/FeedScreen.swift` | Work feedback moved from a variable `safeAreaInset(edge: .bottom)` (analysis §4: it changed the scroll viewport height while work ran) to an `.overlay(alignment: .bottom)` of the constant `Measurement.workFeedbackHeight` that does not take touches. `FeedVisualCapture.position` exposes the reference card and offset. |
| `Sources/FeedMineRuntime/FeedPresentationAdmission.swift` | `admitsForwardContent` is now **`.explicitTailApproach` only** — real forward movement *and* the need to extend. A forward scroll inside already-admitted history, a stationary settle, a backward gesture and a layout change never admit. |
| `FeedSession` | Decoded pixels became bounded **residency**: only cards inside the frozen bounds around the reader keep their bitmap; cards outside release it (`releasingDecodedImage()`) and are re-decoded from the same local asset when the reader returns. Identity, order, layout, aspect ratio, text and action are untouched — the slot's geometry is frozen, so releasing pixels can never move a card, and a card published with an image slot is never redefined as text-only. `releasedImageCards` keeps the release explicit, so a genuinely missing asset is not retried on every observation. |
| `PresentationCard` | Internal `withDecodedImage(_:)` / `releasingDecodedImage()` and public `isImageBearing`, so residency is a distinct concern from the card's identity. |

**Tests.** New `ScrollAdmissionTests` (3): a layout change cannot admit (and a stale anchor cannot either); backward navigation never exposes an unadmitted card and re-entering admitted history is not a new admission; decoded-image residency is bounded around the reader while layout and aspect ratio stay frozen and returning re-decodes the same asset. New driver test `test25BackwardAndStationaryActivitiesDoNotAdmit` proves the direction gate at the composition boundary. New capture tests `testTS3VisualPositionDescribesTheReferenceCardOnly` and `testTS3ScrollPositionClampsAndRejectsNonFiniteInput`. New iOS UI test `testT3ScrollAdmitsWithoutMovingTheReadingPoint`: real swipes, then the top card's identity and its viewport offset are compared across completed production, a background/foreground cycle and backward navigation, `accuracy: 1`.

**Verification (executed).** `swift build` clean; `swift test` **855 tests, 0 failures**; iOS build succeeded; and
`xcodebuild … -only-testing:FeedMineUITests/FeedMineUITests/testT3ScrollAdmitsWithoutMovingTheReadingPoint test`
→ **TEST SUCCEEDED** (33 s on the iPhone 17 Pro Max simulator, iOS 26.5).

**Still open in the media policy (recorded, not silently accepted).** Verified guarantee: releasing pixels never
changes geometry or identity, and returning re-decodes the same asset. Not verified: zero flicker during an
arbitrary-speed reverse scroll — a bitmap that is released and not yet re-decoded renders the frozen
placeholder. Codex's recommendation for that case (rematerialize a historical render window only when its images
are ready) is the next step if the device measurement in T12 shows it matters.

## T4 — 2026-10-09 (V1 card layouts and visual system)

Plan task T4. First visual transfer of the plan: the reader's card composition and its appearance now come from
V1's code, not from an approximation.

**What was copied.**

| V1 source | V2 destination | Notes |
| --- | --- | --- |
| `Services/DesignTokens.swift` + the pure values of `Services/CircadianEngine.swift` | `Sources/FeedMineUI/Appearance/ReaderAppearance.swift` | `ReaderPeriod` (palette period), `ReaderPaletteFamily`, `ReaderFontStyle`, `ReaderFontRole`, `ReaderTypeScale` and one immutable `ReaderAppearance`. Palette accents and page tints are V1's exact hex strings, exposed by `accentHex(for:)`/`pageTintHex(for:)` so the copied values are assertable; metrics (padding 14–22, gap 10–18, radius 10–16), the HIG tracking table and the per-role sizes are V1's. **Not copied:** the hourly timer and the `@Observable` singleton — an appearance change is now an explicit host input, never a clock. |
| `Views/FeedItemCardView.swift` | `Sources/FeedMineUI/Cards/FeedItemCardView.swift` | Portrait card (hero slot → source row → title → excerpt → date), the landscape band, the left accent bar, the bookmark in the slot / inline on text-only cards, the code-drawn audio placeholder, the media overlay, the badges, the relative/short date rule and the `.ultraThinMaterial` overlay bookmark. |
| `Views/FeedItemView.swift`, `Views/FeedItemRowView.swift` | `Sources/FeedMineUI/Cards/FeedItemView.swift`, `FeedItemRowView.swift` | Card/row selection by size class (`ReaderItemLayout` also allows forcing one), the compact row, and the tap that opens the occurrence. |
| `UIPasteboard` / `UIActivityViewController` / `UIApplication.open` / `BookmarkBoxContextMenu` inside V1's card | **not copied** | They leave as one `ReaderCardActionEvent` (`ReaderCardAction`: open, save, viewSource, addSourceToCollection, copyLink, share, openMedia) and are executed outside UI (T5/T9). |
| `Views/FeedScreen.swift` card region | `Sources/FeedMineUI/FeedScreen.swift` | `FeedCardView` is **deleted**; the screen renders `FeedItemView` and forwards `store.perform(_:)`. |

**Action gating (new).** `FeedScreenStore` has no `onOpen`/`onBookmark` pair any more: it has
`availableActions` plus one `onAction`. The card renders only actions the host declares it can execute, so a
transferred control can never be a dead one while T5–T11 land. Today `AppComposition.readerCardActions =
[.open, .save]` — the app host’s two working flows.

**Differences from V1, recorded, not hidden.**
1. `providerDisplayName` and the timestamp-kind label (`Autoria`/`Modificado`/`Observado`) are **not** drawn: V1's
   card shows the date alone. The fields stay in `PresentationCard` for the surfaces that use them.
2. The left accent bar uses the palette accent. V1 tinted it per *catalog category*, which V2 does not carry on a
   card yet (T7 brings the taxonomy).
3. Badges are limited to `Podcast` (derived from `primaryActionKind == .mediaPlayback`); V1 also had `Video`,
   `New` and a duration label, which need semantic fields the V2 projection does not have yet. Adding them is a
   **T4 remainder**, explicitly not faked.
4. The hero placeholder uses the asset names that exist in the bundle (`Placeholder-Article`). V1 looked up a
   palette-suffixed name (`Placeholder-Article-amber`) that no asset catalog in the checkout defines — which is
   why its hero slots render blank, visible in the T1 reference screenshots.
5. No `GeometryReader`: the slot is a frozen-aspect `Rectangle` mold with the image as an overlay, so the card's
   height never depends on what the slot holds.

**Tests.** New `FeedCardTransferTests` (6): the copied palette/metrics/typography/tracking values; period-driven
weight and spacing; a card renders its frozen fields and invents nothing; an image slot keeps its geometry when
pixels are released; read/saved change chrome only; every menu action is gated on `availableActions` and the
renderer contains no `URLSession`/`UIImage`/`UIPasteboard`/`UIActivityViewController`. `FeedScreenRenderingTests`
U1–U3/timestamp/narrow-width were migrated to the ported card (provider and timestamp-kind assertions inverted
on purpose); U14's boundary list now covers the new card files; `FeedScreenStoreTests` migrated the store's
"forwards identity only" test to `perform(_:)` and the new stored-property set.

**Verification (executed).** `swift build` clean; `swift test` **861 tests, 0 failures**; iOS build
`xcodebuild … build` → **BUILD SUCCEEDED**; the app installed and launched on the iPhone 17 Pro Max simulator,
and `docs/evidence/v1-ui/t4-v2-ported-card.png` shows the ported card with real content (source row, two-line
title, `2 days ago`, accent bar, slot-sized placeholder, overlay bookmark). Caveat recorded honestly: that capture
is veiled/dimmed by the current simulator display state, so it is **structural** evidence — a colour-fidelity
side-by-side against `feed-portrait-light.png` is still owed, and is now part of T4's remainder together with the
badge/category fields.

## T5 — 2026-10-09 (V1 reader shell, header, menus and search)

Plan task T5. The reader's chrome is now V1's: the V2 navigation toolbar is gone.

**What was copied.**

| V1 source | V2 destination | Notes |
| --- | --- | --- |
| `Views/FeedScreen.swift` `compactHeader` (502–653) | `Sources/FeedMineUI/Reader/ReaderHeader.swift` | Floating header: status chip slot, search / bookmarks / filter buttons and the ellipsis menu, `.ultraThinMaterial` background, bottom divider and the lens slot. V1's `headerButtonStyle` (44×44, accent-tinted circle) is `ReaderHeaderButton`; V1's identifiers (`search-button`, `bookmark-boxes-button`, `filter-button`, `more-menu`) are kept. |
| V1's ellipsis menu (556–635) | `ReaderMenu.swift` + `ReaderNavigation.swift` | All 14 V1 items as values (`ReaderMenuEntry.standard`), with V1's labels, SF Symbols, destructive roles and grouping. |
| V1's search bar (655–716) | `ReaderShell.swift` `searchBar` | Field, submit, explicit cancel; the surface closes without touching the feed. |
| `Views/ToastView.swift` + V1's toast lifetime (1097–1119) | `Feedback/ToastView.swift` | Black capsule, 2 s, spring 0.35/0.8, 100 pt above the bottom; non-interactive. |
| `Views/ClipboardBanner.swift` | `Feedback/ClipboardBanner.swift` | Add / dismiss; the pasteboard check stays with the host (T10 owns import). |
| `Views/FeedScreen.swift` composition (`feedTopPadding`, `ZStack` + `HeaderHeightKey`) | `ReaderShell.swift` | The shell measures **its own** chrome with a layout preference and pads the content by exactly that; production can never open, close or resize it (T3/T5 rule). |

**Removed from V2:** the navigation toolbar (Feed context menu, Salvos, Fontes and the bottom search
field) and the U3 context bar. The context switcher survives as the header's status chip menu — the one
working V2 flow that has no V1 equivalent yet; T6 replaces it with V1's filter/preset surfaces. The chip
states the active context with the identifiers the U3 flow already used (`reader-contexts`,
`reader-context-label`, `reader-context-clear`), so no flow was lost.

**One owner for each decision.** `FeedScreenStore` gained the shell's state and intents: `isSearching`,
`searchQuery`, `toast`, `filterCount` (0 until T6), `bookmarkBoxActive` (false until T8),
`availableDestinations`, and `toggleSearch`/`submitSearch`/`cancelSearch`/`navigate(to:)`/`showToast`/
`dismissToast`. `menuEntries` is computed from `availableDestinations ∩ ReaderMenuEntry.standard`, so the
overflow menu can only show what the host can present. `AppComposition.readerDestinations` is
`[.sources, .bookmarkBoxes]` today; the host presents the source sheet and the saved list, and
`AppComposition.onNavigate` is the single presentation switch.

**Tests.** New `ReaderShellTests` (6): the menu offers exactly the available destinations in V1's order and
never repeats an identity; the search surface reports one submission and starts no work; navigation to an
unavailable destination is refused in the store; feedback is host-owned; the shell measures only its own
chrome and references no production type; the V1 control identifiers, 44×44 style and the non-geometric
work feedback are asserted structurally. New iOS UI test
`testT5HeaderChromeAndCardGesturesReachRealFlows`: V1's controls exist and the V2 toolbar does not; the menu
offers `Fontes` but not `Ajustes` (unimplemented) nor `Copiar link` (unavailable action); the source sheet
opens and closes; the search surface opens and cancels; a long press reaches the card menu, saving lands in
the saved list reached from the header, and a plain tap still opens the card (no gesture swallowed). The
three existing UI tests that used the removed toolbar were migrated to the header (`reader-sources` →
`more-menu` + `Fontes`, `reader-saved` → `bookmark-boxes-button`, the U3 context bar → the chip menu).

**Measured defect fixed during the transfer.** An `accessibilityIdentifier` on the search bar's container
overrode its children's identifiers, making the field and the cancel button unreachable to XCUITest; the
container now uses `accessibilityElement(children: .contain)` with no identifier of its own.

**Verification (executed).** `swift build` clean; `swift test` **867 tests, 0 failures**; iOS build
**BUILD SUCCEEDED**; `-only-testing:…/testT5HeaderChromeAndCardGesturesReachRealFlows` → **TEST SUCCEEDED**;
the three migrated UI tests → **TEST SUCCEEDED**.

## T6 — 2026-10-09 (filters and context identity): design approved, first step landed

Plan task T6. Codex reviewed the four open design questions and the answers are committed as the
specification the implementation follows: `docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md`.

**Decisions taken (Codex review, 2026-10-09).**
1. **Honest intermediate delivery**: enforce in the supply what canonical data already answers — language,
   source membership and keyword exclusions — and make every unsupported criterion (region, taxonomy, content
   type, and mood *until its rule lands*) **visibly unavailable** rather than accepted and silently ignored. A
   filter may never apply to drawn cards only. T7's *metadata import/query* support is pulled forward; full T7
   need not precede T6.
2. **V1's dismiss-applies sheet wins.** V1 has no Cancel: the sheet hydrates a draft on appear and commits the
   dirty parts on `onDisappear` (`Views/FilterSheetView.swift:220-297`, `presetIsDirty`/`overlayFiltersAreDirty`
   separate). The plan's "apply/cancel/reset" row is corrected in place, with the reason and evidence.
3. Filters live in the **context identity**, so each combination keeps its own checkpoint and A→B→A recovers
   A's position; canonical persistence must migrate from the reduced `main|source|query` key to the full key
   (evidence in the spec: `SessionStore.swift:125`, `:133`).
4. Expiry is a *pending* fact in persisted preferences; a clock check never changes the active plan or the
   presentation, and an explicit transition resolves it (`AppComposition.swift:358` is where revision
   compatibility is checked today).

**Landed in this step.** `Sources/FeedMineDomain/ReaderFilter.swift`: `ReaderFilter` (regions, taxonomy nodes,
languages, content type, mood, exclusions) with canonical, order-independent identity text; `ReaderContentType`
and `ReaderMood` with V1's raw values, icons and — for mood — V1's exact keyword rule
(`FeedLoader.MoodFilter.matches`, 286–305), which is what makes mood honestly enforceable without catalog
metadata; `ReaderContentExclusions` (normalized, never expires; enabled-with-no-rules is a preference and does
not change identity, so a no-op action cannot force a context transition); `ReaderSearchScope`; `ReaderPresetID`.
New `ReaderFilterTests` (9): equivalent selections share one identity and one encoded form, the default filter is
unrestricted and stable, every criterion changes identity, the mood rule reproduces V1, the content-type and mood
vocabularies match V1, exclusions normalize and carry no expiry, preset identity is payload-free, search scope
semantics, and a Codable round-trip.

**Verified.** `swift test` **876 tests, 0 failures**.

**Step 2 landed.** `ContextKey` (`Sources/FeedMineDomain/FeedContext.swift`) is now the *whole* request:
`identitySchemaVersion`, `surface`, `preset` (`ReaderPresetID`), the normalized `filter` and (for a search) its
`searchScope`. Every field defaults to "the plain surface", so `ContextKey(request:)` is byte-identical to the
pre-T6 identity and existing checkpoints keep matching; a scope passed on a non-search surface is dropped, not
carried. `canonicalIdentity` is the deterministic opaque text durable identifiers must store, and **equality is
identity** — `==`/`hash` compare that text, so a reordered set, an enabled-but-empty exclusion set or a stray
scope collapse to one key instead of forking the reader's history. `surfaceIdentity` keeps the reduced
`main|source|query` form the checkpoint columns have always used, for the migration step. New
`ContextIdentityTests` (7): the default surface matches the pre-filter identity exactly, equivalent filters share
one identity, every part of the key is load-bearing (including that enabled-with-no-rules is a no-op), a search
keeps its exact query and its scope, a **legacy key with only a request decodes to the default surface**, the
full identity round-trips, and `FeedContext.key` stays the default-surface convenience.

**Verified.** `swift test` **883 tests, 0 failures**.

**Step 2b landed.** `Sources/FeedMineUI/Filters/ReaderFilterDraft.swift`: the selection the reader is editing,
kept apart from the applied one, with V1's exact editing rules (toggling a language, selecting the current
content type or mood clears it, preset and overlay criteria are independent), a `base`/`basePreset` pair that
detects a *stale* draft when the applied context moved beneath it, `revert()` (hydrate again) and `clearAll()`
(V1's "Clear All Filters", which clears this sheet's criteria and the region/taxonomy selections it reaches but
**not** content exclusions — those live on their own surface and never expire). `availableCriteria` is the T6
honesty gate: a criterion the supply cannot enforce is refused by the draft instead of being accepted and
silently ignored. New `ReaderFilterDraftTests` (6): a hydrated draft is clean and keeps untouched criteria;
editing is what makes `applied` differ; revert and clear-all are distinct and exclusions survive; unavailable
criteria are refused while the available one applies; a draft whose applied selection moved is stale; preset and
criteria stay independent.

**Verified.** `swift test` **889 tests, 0 failures**.

**Step 3 landed — the durable identity (spec §6 steps 1–4).**
- Migration `reader-context-identity-v1`: `feed_editions` gains `context_identity` (the canonical text used for
  matching) and `context_key_json` (the same key as sorted-keys JSON, the reversible form); `context_checkpoints`
  is **rebuilt** keyed by `context_identity`, because the old reduced `context_key` was its primary key and
  cannot hold two filtered contexts of one surface (the reduced text is kept for one release).
- Backfill, in Swift so the identity keeps exactly one implementation (`RuntimeMigrations
  .backfillEditionContextIdentities` / `.backfillCheckpointContextIdentities`, both idempotent and called by the
  migration): a row written before T6 acquires the **default-surface** identity of the surface it recorded, which
  is what preserves pre-T6 main/source/search history instead of orphaning it; the tests assert the checkpoint is
  then still found under that identity and that a second run changes nothing.
- Write path: `PublicationStore.editionValues` derives both columns from
  `edition.editorialRevision.contextKey`; `decodeEdition` restores the exact key from the JSON and falls back to
  the recorded surface for a pre-migration row.
- Lookups: `SessionStore.activateContext(_ key:)` / `checkpoint(for key:)` match on the identity (request-based
  overloads kept as the default-surface convenience), `persistContext` files a checkpoint under its Edition's
  identity and refuses to file a row without one, and `PublicationHistory.restore(..., contextKey:)` looks up by
  the whole key.

New `ContextIdentityPersistenceTests` (4): an Edition round-trips a *filtered* key in both persisted forms; two
filters on the same surface keep separate checkpoints and neither collides with the plain surface; the backfill
gives a pre-T6 row its surface identity, preserves its position and is idempotent; restore by a filtered identity
finds that context's window while an identity that never had a position finds none.

**Schema-catalogue tests updated in the same commit** (they pin the migration list and the table definitions):
`AvailabilityPrecedenceTests`, `PublicationRunwayStoreTests` (the migration catalogue, the rebuilt-definition
normalization and its 3R5 fixture, which is now written with raw SQL because it deliberately targets the
*historical* schema while the store writes the newest columns) and `MediaCandidateSchemaTests` (the additive
columns are excluded from the whole-row dump and asserted directly, including that the backfill filled them).

**Verified.** `swift test` **893 tests, 0 failures**.

**Step 4 landed — enforcement in the supply.** `FeedContext` now carries the whole identity (surface, preset,
filter, scope; the defaults are the plain surface), so a plan can describe a filtered context. `ReaderFilterCriterion`
moved to Domain with `enforceable = [.preset, .languages, .mood]` — the criteria today's canonical data can
answer. New `ReaderFilterEligibility` (Editorial) decides one candidate: a language criterion compares the
primary subtag (`pt-BR` satisfies `pt`) and **fails** a candidate with no language rather than passing it by
default; mood uses V1's keyword rule over the headline; keyword exclusions hide by headline or summary and never
expire; a restricted source set excludes a candidate that belongs only to other sources; and a criterion outside
`enforced` is **never consulted**, so the honesty rule holds in both directions (the UI refuses to set it, the
supply must not pretend to answer it). `CandidateProvider.candidates(for:after:examinedCapacity:originIDs:)`
applies that eligibility to the window it builds, which is where the plan requires a filter to act — never on
already-drawn cards. New `ReaderFilterEligibilityTests` (6).

**Verified.** `swift test` **899 tests, 0 failures**.

**Step 5 landed — the selection is persisted as the whole identity.** `ReaderPreferencesStore.Record` carries
`activeContextKey: ContextKey` (with `activeContext` kept as the surface convenience), `setContext(_ key:)`
writes it, and `read` accepts **both** shapes that have ever lived in that column: a row written since T6 (the
key), and a pre-T6 row (the bare `FeedContextRequest`, which becomes the default surface of the request it
recorded). No migration was needed for this column — the legacy payload is detected by decoding, not by a
version column. `ReaderPreferencesStoreTests` gains a case for the whole-identity round trip, the
equivalent-selection case, the search scope, and the legacy row.

**Verified.** `swift test` **900 tests, 0 failures**.

**Step 8 landed — the transition is reachable end to end.** `FeedAssociation` now takes the whole
`ContextKey` (not a surface request): it builds `FeedContext(key:)` and the editorial revision from it, activates
the checkpoint by identity and restores by identity, so a filtered context gets its own Edition *and* its own
position — the revision id itself derives from the key JSON, so two filters never share an edition. The app keeps
`currentContextKey` and gained `applyFilter(_:preset:)`: persist the identity, then rebuild the association (an
explicit transition, never a production-side effect). The header's filter button opens V1's sheet, whose `Done`
applies through that path and closes only after it succeeded.

**Three defects the UI test caught, all fixed.**
1. The app offered **every** criterion (`Set(ReaderFilterCriterion.allCases)`) while the supply could answer only
   preset/language/mood — i.e. it offered controls that would be accepted and ignored. It now passes
   `ReaderFilterCriterion.enforceable`, and the test asserts content type and topics are *absent* while the
   language list (257 real codes) is present.
2. The sheet's store was created **while the parent rendered**, so the sheet received an orphan store and its
   edits never reached the host. The sheet now builds its own store from value inputs in its initializer, and its
   `Done` applies before the host closes it.
3. A `Button` with `.buttonStyle(.plain)` inside a `List` only hits its label's drawn area, so a row's spacer
   swallowed the tap — measured as "Clear All never enabled after tapping a language". The row labels now carry
   `.contentShape(Rectangle())`.

New iOS UI test `testT6FilterSheetOpensAppliesAndKeepsTheReader`: the sheet opens, offers only enforceable
criteria, a row tap edits the draft (Clear All enables), `Done` closes it, and the reader keeps its feed after the
transition.

**Step 7 landed — the sheet itself.** `Sources/FeedMineUI/Filters/FilterSheetView.swift` copies V1's
`FilterSheetView` order and controls: Clear All, the preset picker (V1's "Everything"/"Last clicked" plus whatever
named presets the host offers; T8 brings collections/smart/curated), the Countries link, content-type buttons, the
topic link with its selection count, the language list with the declared enabled counts, the mood buttons, and
Done. `languageRows` is a value so the list is testable without a store, and the draft's `availableCriteria`
decides **which sections are drawn at all** — a criterion this build cannot enforce is not offered and then
ignored. Two recorded differences from V1: the language row shows no flag (V1's `LanguageInfo` carried one from
its own table; the catalog has only codes, and a two-letter *language* code is not a country — the first attempt
here rendered 🇪🇳 for "en", which is exactly the invented data the rule forbids), and closing the sheet is still
the apply (V1's `onDisappear`, exercised by the store's `dismiss()`).

**Step 6 landed — one moment turns a draft into the applied selection.** New `ReaderFilterStore` (UI): it holds
the applied selection and the draft, forwards the sheet's edits, and has exactly one applying path.
`dismiss()` is that path (V1: the sheet has no Cancel, it commits the dirty parts when it goes away);
a clean draft applies nothing; a **stale** draft (the applied selection moved beneath it) is refused instead of
overwriting a context the reader is no longer editing; a host failure leaves the draft intact so the reader can
retry; `revert()` discards the edits and re-hydrates from the *currently applied* selection, which is also what
clears staleness; and `hydrate` is how a foreign change arrives (a dirty draft is kept and marked stale rather
than thrown away silently). New `ReaderFilterStoreTests` (5).

**Verified.** `swift test` **905 tests, 0 failures**.

**Everything above is now landed and measured**: the sheet (step 7), the reachable transition through
`applyFilter` (step 8) and the A→B→A / stale-callback behaviour (step 9, app-level test
`testT6FilterTransitionKeepsContextsSeparateAndStaleCallbackInert`: A advances and checkpoints, a filter builds B
with its own association and edition, returning to A **offline** recovers A's edition *and* its anchor, and the
retired association cannot install into the active store — `.projectionSequenceMismatch`).

**Step 10 landed — the filter lens.** `ReaderFilter.activeCriteria` (Domain) states the criteria that are set and
`removing(_:)` returns the filter without exactly one of them (removing something absent is a no-op, so a chip can
never invent a change). `Sources/FeedMineUI/Filters/ReaderFilterLens.swift` copies V1's `FilterLensBar`: one chip
per active criterion in V1's order (preset, search, region, content type, topic, language, mood), each removing
its own, a swipe that reports a dismissal instead of deciding it, and no bar at all on a plain surface.
`ReaderFilterLens.chips(...)` is a value, so the bar is testable without a store, and the app draws it from the
*applied* identity — a removal goes through the same `applyFilter` transition as the sheet. The T6 UI test now
also asserts the end-to-end chip: apply a language, the chip appears, tapping it clears that criterion and the
reader survives.

**Step 11 landed — expiry.** `ReaderFilterExpiry` (Domain) is V1's `filterAutoExpire` + `filterSetAt` as one
value: a four-hour window, `expiresAt()`, `isExpired(at:)` (a *pending* fact, not an action) and
`resolving(_:at:)`, which drops the overlay groups (region, taxonomy, language, content type, mood) while
**content exclusions survive** — exactly the set V1's rule covered and the one it left alone. `renewed(at:)`
restarts the window without changing whether the rule is on. Persisted with the reader's preferences
(migration `reader-filter-expiry-v1`: two columns beside `active_context`; a fresh row is on and has nothing
set); **not** part of the context identity, because a deadline is not identity. `AppComposition.applyFilter`
renews the record when an overlay selection is applied and keeps `startsAt = nil` for a selection that only
excludes, and `resolvedFilter(at:)` is consulted by `selectContext` and by the transition path — only an
explicit transition can apply a pending expiry, and no clock ever touches the active presentation.

**Step 12 landed — the compatibility predicate.** `FeedAssociation.mayShow(_:for:selectionVersion:)` is now the
single decision before a restored Edition is reused, and it asks for the **whole identity first** (the
revision's `contextKey` must equal the key the reader is on) before the selection and eligibility policy
versions. Before this, a checkpoint filed under a different filter but with matching versions would have been
shown — the silent swap the review named. Tested by `testT6RevisionCompatibilityRequiresTheWholeIdentity`: a
foreign filter refused, the plain identity refused for a filtered one, older selection/eligibility versions
refused, and an *equivalent* selection accepted as the same identity.

**Verified.** `swift test` **924 tests, 0 failures**; iOS build **SUCCEEDED**; the T6 UI test → **TEST
SUCCEEDED**; the app-level T6 transition and revision tests → **TEST SUCCEEDED**.

**Remaining for T6**: the full preset picker, which needs T8's named presets.



## T7 — 2026-10-09 (catalog metadata: the values T6's sheet and T7's source management need)

First slice of T7, done from the *measured* bundled snapshot rather than from the plan's prose; brief and the
schema facts are in `docs/superpowers/specs/2026-10-10-t7-catalog-metadata-queries.md`.

`LegacyCatalogReader` (read-only, one connection per call, never migrated or written) gained the three metadata
families as values — no GRDB types leave Persistence:

- **`languages()`** → `LegacyCatalogLanguageRecord` (code, enabled, total, `primarySubtag`, `isUndeclared`), ordered
  by enabled count descending with the undeclared bucket **last**. Measured on the shipped asset: 257 distinct
  codes, `und` 26,644 enabled / 27,741 total, `en` 15,820 / 17,962. This is exactly what T6's sheet needs for its
  language list, and it confirms the primary-subtag rule the eligibility check already applies.
- **`nodes(parentID:after:limit:)`** → `LegacyCatalogNodePage` (nodes, `nextCursor`, `exhausted`), ordered by the
  index the catalogue ships (`parent_id, name COLLATE NOCASE, id`) and paged with a **one-row lookahead**, so
  `exhausted` is truthful instead of "the page was full".
- **`sectionNodes()`**, **`countries(after:limit:)`**, **`node(id:)`/`node(key:)`**, **`ancestors(ofNodeID:)`** and
  **`matchingNodes(query:limit:)`** (literal, escaped, indexed). Measured shape: 18 root sections (the 19th `kind = 0`
  node is the root itself), 101 countries (`kind = 1`), 6,330 topic leaves (`kind = 3`), so countries are a real
  subtree and no second region source is invented.

New `LegacyCatalogMetadataTests` (5): the language list's order and counts plus the undeclared buckets; the tree
walk section → country → topic; stable paging with a truthful `exhausted`; the breadcrumb and literal search
(`%` is a literal, never a pattern); and the **real 117 MB asset**, where the measured counts, the 18 sections, the
101 countries, the 257 codes and `und`'s 26,644 enabled sources are asserted directly (the test skips with a clear
message if the release asset is absent).

**Verified.** `swift test` **910 tests, 0 failures**, including the assertions against the bundled catalogue.

Second slice: `Sources/FeedMineComposition/SourceManagementCoordinator.swift` — the UI-facing surface over that
reader. It hands out **values only** (`CatalogLanguageSummary`, `CatalogNodeSummary` with `section`/`country`/
`topic`, `CatalogPage` with a cursor and a truthful `exhausted`, `CatalogSourceSummary` whose identity is the
catalog *key* and never the integer), states a **typed absence** (`SourceManagementError.catalogUnavailable`)
when the release asset is missing instead of pretending an empty tree, and persists a selection change through the
reader's own preferences (`setSelection` → `ReaderPreferencesStore.updateSources`, returning the selection
version that fences restore, so reordering the same set is not a new selection). New
`SourceManagementCoordinatorTests` (2): values-only plus the typed absence plus the undeclared-language label;
and selection persistence with the version semantics.

Third slice: the data a country/region screen needs. `LegacyCatalogReader.sources(inNode:after:limit:)` pages a
node's placed sources in the catalogue's own order for that node (`idx_catalog_placement_node_order`) with a
`(sort_order, source_id)` cursor — not a global row id a catalog rebuild could move — plus a truthful `exhausted`
via the same one-row lookahead; `sourceKeys(inNode:ceiling:)` returns a node's keys for a bulk change. The
coordinator exposes both as values (`CatalogPage<CatalogSourceSummary, CatalogSourceCursor>`, its page cursor now
generic) and gained `setEnabled(nodeID:enabled:)`, which merges a node's keys into the reader's own selection
through `ReaderPreferencesStore` and returns the new version (V1's "whole region on/off"). `nodeByKey(_:)` lets a
caller navigate by stable key.

New tests extend `SourceManagementCoordinatorTests` (3 total): a node's sources keep the catalogue's order and page
by placement position; a bulk enable merges and versions, re-enabling is not a new version, a bulk disable removes
exactly the node's sources and keeps the reader's others.

**The parity item above is closed** (seventh slice). V1 allowed *zero* selected sources and stated it with its own
surface; V2 refused at `ReaderPreferencesStore.validate`. Both moved together:

- `validate` now refuses only **malformed** sets (duplicates, blanks) — emptiness is a state, and
  `testEmptySelectionIsAStateAndNotAMalformedRecord` proves it persists, versions, keeps the surface the reader
  was on, and that a refused write is still atomic.
- `SourceManagementCoordinator.setEnabled(nodeID:enabled:)` may empty the selection; the test now ends with the
  last node disabled, the selection empty, and the same node re-enabled from there.
- `FeedSourcesEmptyStateView` (UI) ports V1's `FeedEmptyStateView` for this mode: the accent circle with
  `globe.americas.fill`, the title, the description and the one prominent action, with V1's own layout metrics
  (title `.title3` bold, `maxWidth: 360`, `lineLimit(3)`, `minimumScaleFactor(0.82)`; the action `.frame(maxWidth:
  200)` and `.controlSize(.large)`), identifier `feed-empty-state` / `feed-empty-title` as V1 had it. `FeedScreen`
  draws it **ahead of** the preparation surface and ahead of the feed, because nothing is being prepared.
- **Two deliberate differences from V1, recorded.** (1) The copy is Portuguese, like every other ported view
  (`Todos os países`, `Países`, `Concluir`), not V1's English literal. (2) V1's description sent the reader to
  *Filters*; in V2 the country/topic *selection* lives in source management and a filter criterion cannot add
  content to an empty selection, so the action opens **Fontes** and says so.
- The app now reads `hasSelectedSources` from the **persisted selection**, and a selection the reader emptied is
  no longer silently repaired at launch: the old fallback (`if resolved.isEmpty { resolved = feeds }`) is now
  gated on the saved selection having had sources at all — it repairs keys that vanished from the catalogue, not a
  choice of none.
- Evidence: `swift test` **925 tests, 0 failures**; the new
  `testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack` (real simulator) launches with
  `FEEDMINE_EMPTY_SELECTION=1`, sees V1's surface, proves **no feed and no "Preparando"** are drawn, opens
  *Fontes* from the surface's own button, returns to the empty surface, and gets the feed back by enabling one
  source.

**Eighth slice — the source surface itself, wired end to end** (matrix rows 200/201/203/204/205).

- `SourceCatalogBackend` (Composition) is the single place where the surface's protocol (UI) meets the catalog
  coordinator: values in, values out, ids translated at that boundary and nowhere above it. Proven against a
  **real catalog file and a real preferences database** (`SourceCatalogBackendTests`), not a recording double:
  sections, countries, a node's children and sources in the catalogue's own order, one child-key read per level,
  the search (still scoped to text sources, as V1 had it), and both writes reaching the reader's own selection —
  including an emptied one.
- `SourceManagementView` (UI) is V1's `SourceManagementView` shell: the catalog's sections with a whole-section
  toggle, the way into the country list, and the stated enabled count with V1's footer semantics.
  **Deliberate differences recorded:** V1 drew one flat list of every category and source at once plus a health
  column and an OPML import/export section; V2 draws the levels the catalog has (this entry → country list → a
  node's own sources, all ported), the health column waits for the runtime's own availability read, and
  import/export belongs to T10 — none of the three is drawn as a dead control. V1's "N of M sources" is replaced
  by the enabled count, which the persisted selection makes exact; a total would double-count sources the
  catalog places under several nodes.
- `NodeSourcesView` (UI) is V1's `CountryDetailScreen`/`RegionDetailScreen` — the same screen twice — as one
  view over V2's single node model: the node's children (V1's "Regions" section, each row drilling further or
  toggling the whole sub-tree with `childKeys`, one read per level) and the node's own sources grouped into
  sections by the catalog's **media kind**, because V2's catalog has no category column (V1 grouped by the free
  `FeedSource.category` string). The grouping, the section titles/icons and the child label are values, so the
  layout is testable without a store.
- Adopting the change: the source surface writes the selection through the coordinator, and the app re-reads it
  **when the surface closes** (`adoptSelectionChange`) — looking at the list is not a selection change, an
  emptied selection is adopted as a state, and only a real change rebuilds the association (with the
  single-source rule `toggleSource` already had).
- Evidence: `swift test` **928 tests, 0 failures**; iOS build **SUCCEEDED**; and the ported path is exercised in
  the simulator by `testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack`, which now walks the empty surface
  → *Fontes* (shell, enabled count) → *Todos os países* → a country's toggle → the sheet closing → **the feed
  back**.

**Ninth slice — the health column** (matrix row 200's health check).

- `AcquisitionCoordinator.healthSnapshot()` states what the runtime measured per target: the consecutive failure
  count and, while it is cooling, the monotonic deadline of that window. A target never attempted is **absent**,
  never reported healthy — that is the whole reason the read returns a dictionary instead of a default state.
  Tested in `testHealthSnapshotStatesFailuresAndCoolingDeadlines` (absence, first failure and its deadline, the
  failure surviving its own window, the doubling on the second).
- The value crosses the boundary as `CatalogSourceHealth` (Runtime), the store carries it per catalog key, and
  V1's own badge is drawn beside the source's title (`N falhas`, in red) — only for sources the runtime
  attempted. The shell states V1's summary ("N/M sources responding") as the failing count over what was
  observed.
- **Two deliberate differences from V1, recorded.** (1) V1 probed every URL with its own `URLSession` from the
  view and drew a staleness badge from its registry's observation age. V2 reads the acquisition coordinator's own
  record — a source is probed by acquisition, so a probe button would be a control that changes nothing, and the
  health column states only what was measured. "Test All Sources" is therefore **not ported**; the reader's
  equivalent is the refresh the feed already performs. (2) V1's staleness badge has no V2 counterpart in this
  slice: the per-target last-observation read does not exist yet, and a column that never fires is worse than
  none.
- Evidence: `swift test` **931 tests, 0 failures**; iOS build **SUCCEEDED**.

**One T7 row is deliberately ordered last, not dropped (matrix row 201, `CatalogExploreView`).** V1 drew that
surface behind `#if DEBUG` (row 68 records the same gate for its header button): a paginated developer browser
with a details sheet, not a reader surface. It is scheduled into T12's parity sweep — after the reader-facing
deliveries (T8–T11), so a developer tool never occupies the place of a user-facing port — and it is listed as its
own task so it cannot be lost. Everything the reader sees under *Fontes* is delivered and proven above.

Fourth slice: the surface the T7 views bind to. The catalog **values moved to Runtime** (`CatalogValues.swift`) —
UI imports Runtime and must never import Composition, so values cannot live next to the coordinator that produces
them. New `SourceManagementStore` (UI) is observable values plus intents over a `SourceManagementBackend`
protocol the composition implements: `load()` (languages, sections, countries, selection), `open(_:)` (a node's
level, breadcrumb and own sources), `search(_:)`/`clearSearch()`, `toggle(_:)` and `setEnabled(_:enabled:)`. A
missing catalog is a **stated state**, not an empty tree, and a refused change never leaves an optimistic
selection on screen — the shown selection is always the one the backend accepted. New
`SourceManagementStoreTests` (4) with a recording backend that can be told to fail.

Fifth slice — the first ported view: `Sources/FeedMineUI/Sources/CountriesListView.swift`, V1's
`CountriesListScreen` layout on top of the store (flag + name + "N feeds" + a per-country toggle, an
"All countries" row, a footer with the totals, and the done control), with `CountryRow` as a rendering value so
the layout is testable without a store. `LegacyCatalogReader.sourceKeysByNode(kind:)` returns every country's own
keys in **one** read and the store holds that map, so a row can state "enabled" only when *all* of its sources are
selected — one query per list, not one per row. Two deliberate differences from V1 are recorded: the toggle binds
to the store's *accepted* selection (V1 flipped optimistically and deferred the write with
`DispatchQueue.main.async`), and the flag is derived from the catalog's own `countries/<code>` key shape with a
globe fallback (a two-letter slug outside that shape is not claimed to be a country).

Sixth slice — the topic browser, which turned out to belong to **T6's sheet, not to source management**: V1's
`TaxonomyBrowseView` called `loader.toggleNode`, i.e. it selected a *filter criterion*, while `SourceManagementView`
toggled sources. Ported as `Sources/FeedMineUI/Filters/TaxonomyBrowseView.swift` from
`Views/TaxonomyBrowseView.swift`: per-level drill-down with checkmarks, the "All in <category>" row, a root-level
search with V1's 300 ms courtesy delay and a breadcrumb under each hit, and a `done` control whose value states
how many topics are selected. It binds to `ReaderFilterStore` (`select(taxonomyNodeIDs:)`), so a chosen topic is
part of the filter's identity, and to a new `TaxonomyTreeBackend` protocol for the tree (values only). Rows are
`TaxonomyNodeRow` values carrying the **catalog key** — the draft stores keys, so a selected topic survives a
catalog rebuild that renumbers node ids — with `TaxonomyBrowseView.rows(nodes:selected:breadcrumbs:)` testable
without a store. One deliberate difference from V1: a row with children both selects and opens in V1 (a
`NavigationLink` wrapping a toggle); here the row selects and a chevron opens the level, because a link that also
writes state swallows the tap.

**Still open in T7**: the remaining source-management/exploration views (V1's
`SourceManagementView`, `CatalogExploreView`, `TaxonomyBrowseView`, country/region screens) — including that
empty state — the catalog health check (`testHealth`, which needs the acquisition transport and its own slice), and
the offline/scale UI tests.

**Verified.** `swift test` **920 tests, 0 failures**; iOS build **SUCCEEDED**;
`-only-testing:FeedMineUITests/FeedMineUITests/testT6FilterSheetOpensAppliesAndKeepsTheReader test` →
**TEST SUCCEEDED**.

## T8 — 2026-10-09 (collections, bookmark boxes and saved presets)

Executed in three parts: what the reader's library *is* (Domain + storage), what V1's own database gives it
(the legacy import), and the surfaces.

**The library itself.** `ReaderBookmarkList`, `ReaderCollection` and `ReaderPreset` (Domain) state identity,
naming and ordering. A box holds published *card occurrences* (a bookmark marks a card, never a source), a
collection holds catalog keys, and a preset is a **whole T6 `ContextKey`** under a name — including the search
scope it was born from — with `presetID` naming itself (`.smartFeed(id)` / `.curatedFeed(id)`), so activating
one is an ordinary context transition. There is no second feed engine behind a preset: that was the plan's
condition and the reason the identity model needed nothing new.

- Migration `reader-library-v1`: `reader_bookmark_lists`, `reader_bookmark_memberships` (PK `(list_id, card_id)`,
  cascade), `reader_collections`, `reader_collection_memberships` (PK `(collection_id, source_key)`, cascade),
  `reader_presets` (`kind`, `context_key` BLOB). V2's one implicit bookmarked set
  (`publication_bookmarks`) is folded into the default box and the old table is **dropped** — one source of
  truth, proven by `testTheLegacyBookmarkSetBecomesTheDefaultBox`, which rebuilds the pre-T8 shape and reopens.
- `ReaderLibraryStore` (Persistence): CRUD, reorder, membership, and `apply(ReaderLibraryImport)` which performs
  a whole import in **one** transaction. `testARefusedWriteLeavesNoPartialState` proves a refused write leaves
  nothing behind; `testSeveralBoxesHoldTheSameCardAndAnEmptyBoxIsAState`, `testCollectionsGroupSourcesAndDeletingOneKeepsThem`
  and `testLibrarySurvivesReopen` carry the rest of T8's acceptance.
- `ReaderLibraryCoordinator` (Composition) is the UI-facing boundary, and it owns the two product operations V1
  offered from a context: `collectSources(named:sourceKeys:)` (atomic) and `savePreset(named:kind:from:)`, which
  rewrites the stored key so it names its own preset.
- The reader's *preferred* box (V1's `preferredBookmarkListID`, where a new bookmark lands) is a preference, not
  identity: `reader-preferences` gained the column (migration `reader-preferred-box-v1`), a preference for a box
  that does not exist is refused, and the card control writes it (`PublicationStore.toggleBookmark(cardID:in:at:)`).

**The legacy import.** `LegacyUserStateReader` (Persistence) opens V1's `user.sqlite` **read-only** and hands out
records; `LegacyUserStateImport` (Composition) maps them with an explicit, stable id map (`v1:list:<id>`,
`v1:collection:<id>`, `v1:smart:<id>`). What it carries: every non-default box (name and order), every
collection with its members, and every smart feed whose definition a T6 key can express — required terms → the
search, excluded terms and keywords → the content exclusions, `includeSources/Contents` → the search scope,
region/taxonomy/languages/contentType/mood → the filter (V2's enums use V1's own strings verbatim).
What it deliberately does not carry, and *reports* instead of approximating: V1's bookmarked articles (their
`item_id` names an object V2 has no referent for — the boxes keep their names and the items cannot come),
curated feeds (profile weights and recipes have no V2 counterpart; T11 owns curation), a smart feed's
source-collection scope (V2's identity has no collection-scoped request), and V1's persistent-search lists (no
V1 UI ever created one). `testImportCarriesBoxesCollectionsAndSmartFeedsOnce` runs the import twice — nothing
duplicates — and asserts the V1 file is **byte-identical** afterwards.

**The surfaces.** `BookmarkBoxesView` + `BookmarkBoxesStore` + `BookmarkBoxesBackend` port V1's
`BookmarkBoxesView`: the all-saved row, one row per box with its count, bold + checkmark for the preferred box,
swipe actions (Padrão / Renomear / Apagar), drag reorder, the New Box alert and the Reorder mode, with V1's
error discipline (a refused write reloads what the database has instead of keeping the screen's version).
`CollectionsView` + `CollectionsStore` + `CollectionsBackend` port `CollectionManagementView` and
`SourceCollectionDetailView`: V1's empty state, create/rename/delete/reorder, the footer that states that
deleting a collection removes only the playlist, a member list with its own removal, and "Abrir o feed da
coleção" — which opens a session over exactly that collection's sources with `.collection(id)` as its preset,
**without touching the reader's selection** (V1's collection feed behaved the same way).
T6's filter sheet now receives the reader's own presets as rows (`FilterPresetRow.key`): V1's two plain entries
first, then curated presets, then collections and smart bookmarks, and choosing a saved one is an immediate
activation of its stored key. The reader's overflow menu offers V1's conditional entries again —
"Reunir estas fontes" (a search or ≥2 criteria) and "Salvar como marcador inteligente" (a committed search) —
plus "Excluir marcador inteligente" when the reader is on one of their own presets; saving a smart bookmark
**switches to it**, as V1 did (`setActivePreset(.smartFeed)`).

**Deliberate differences, recorded.** (1) V1's box row tap made the feed show that box (its `lastClicked`
preset over `selectedBookmarkListID`) and it carried two marks; V2's row opens the box's own saved list and the
checkmark is the box a new bookmark lands in — a box as a *reading surface* needs a presentation source over
the publication store, which T9 owns. (2) V1 let the reader change which box is "default" as well as
"preferred"; V2 keeps `saved` as the default box and the preference decides where saves land. (3) A collection
member's row shows the feed's host: V1 printed a `title_snapshot` that could go stale, and the catalog is there
to state it. (4) V1's `AddSourceToCollectionSheet` (adding a source to a collection from the source surface) is
not ported yet — membership is currently set from a card result's own action and from the legacy import.
(5) A card cannot be moved between boxes from the card itself: the reader changes the preferred box, or removes
a card from a box in that box's list.

**Verified.** `swift test` **952 tests, 0 failures**; iOS build **SUCCEEDED**; and three simulator tests:
`testBookmarkBoxesManageAndOpenTheirOwnList` (default box, New Box, opening an empty box, surviving a reopen),
`testCollectionsManageAndReachThePresetPicker` (V1's empty state, create, the detail's feed action, and the
collection appearing in the filter sheet's picker) and
`testT8ASavedPresetIsOfferedAndActivatesItsOwnContext` (saving a search as a smart bookmark switches the session
to the saved identity, and the row carries the whole key).

## T9 — 2026-10-09 (reader, media and sharing): first part, the action targets

**`ReaderActionCoordinator` (Composition)** resolves what a card action *means*, from the occurrence itself, and
hands the host a typed target: `.externalURL`, `.copiedText`, `.share(ReaderSharePayload)`, `.media`. Nothing in
it opens a URL, touches a pasteboard, presents a sheet or starts a player.

- V1's share item was the link alone (`ShareLink(item: URL(item.url))`): `ReaderSharePayload.text` is the URL,
  and `subject` carries the two facts V1 composed for its social card (title, source) for a sheet's own line.
- **The occurrence's frozen target, proven:** `testAnEditedArticleDoesNotChangeWhatACardOpens` publishes a card,
  then publishes the *same origin* under a new revision and a new target in a later edition, and shows the first
  card still opens, copies and shares the target it was published with.
- **No invented fallback, proven:** a card without an external target reports `.actionUnavailable`, a card that
  does not exist reports `.cardNotFound`, and a card that *claims* an external target while carrying none cannot
  even be published (`PublicationStore.validateCard` refuses it), so the coordinator's "unusable reference"
  branch is defensive rather than reachable.
- `viewSource` is deliberately **not** the article's URL: V1's "View Source" opens the card's *source*, which
  needs the catalog and the target-to-principal mapping. The coordinator refuses it, and the app resolves it
  (`sourcePage(for:)`: the card's source id names one of this session's trusted feeds, whose principal is the
  catalog key → the catalog's own `site_url`), stating a failure when any link of that chain is missing.
- Media reads the kind the pipeline states: `PublicationStore` already validates a `mediaPlayback` action kind
  with a URL, so `openMedia` resolves exactly for cards marked that way and for no others.
  **Recorded gap:** today's syndication keeps image enclosures only (`SyndicationMediaLocator.isImageMIMEType`)
  and `media_candidates` is image-only by schema, so no real card carries `mediaPlayback` yet. The action is
  honest about the card it is given; the pipeline that produces such a card, the player and the mini player are
  the rest of T9.

**The app (host) executes them, and the platform surfaces live there:** `PlatformPasteboard` (the clipboard) and
`ActivityView` (the share sheet, presented from the app, never from a renderer). `viewSource`, `copyLink` and
`share` are enabled for cards now, `open`/`save` already were, and `openMedia` states that no playable media
exists in this build instead of opening a player on nothing.

**Verified.** `swift test` **956 tests, 0 failures**; iOS build **SUCCEEDED**; and
`testCardCopiesItsOwnLinkAndStatesIt` (real simulator) opens a card's own menu, taps *Copiar link*, and sees the
reader told that the link is on the clipboard — the whole chain, renderer → app → coordinator → pasteboard.

### T9, second part — the storage a playable payload needs

V2 could not carry audio or video at all: `media_candidates` said `role = 'cardVisual'` and
`media_class = 'image'` in its own CHECK constraints, and the syndication translator kept image enclosures only.
So V1's `mediaPlayback` action had nothing to resolve. This step gives the pipeline the vocabulary and the
storage; the translator claim, the player and the surfaces are the next ones.

- `MediaCandidateRole` gained `playback` and `MediaCandidateClass` gained `audio`/`video`, with the pairing
  stated once (`image → cardVisual`, `audio`/`video` → `playback`) so the storage check and the translator
  cannot disagree.
- Migration `media-playback-candidate-v1` rebuilds `media_candidates` (SQLite cannot relax a CHECK in place)
  with that vocabulary, the same ordinal/dimension rules, and a **partial unique index** that allows at most one
  playable payload per revision — a card has one primary action, and two playable targets would be a choice
  nobody made.
- Every read that means "the card's visual" now says so (`media_class = 'image'`): `PublicationStore`'s
  primary-locator read and its three joins, and `ContentStore`'s material-identity read — the material key is
  about the image, so a playable row can never change what makes a card material.
- A rebuilt table keeps its constraint index only under a new internal name (SQLite does not rename
  autoindexes), which the historical schema test now states rather than tripping over, and
  `MediaCandidateSchemaTests` checks the new partial index's own shape instead of an index count.

**Verified.** `swift test` **956 tests, 0 failures**; iOS build **SUCCEEDED**.

**Remaining for T9:** the syndication claim for an audio/video enclosure, the readiness/read path that carries
the playable locator to the card, the app's `prepare` choosing `.mediaPlayback` for it (V1's tap-to-play
precedence), the player (a platform adapter, AVFoundation, outside the package), the mini player with its
reserved area, and their surfaces and tests.

### T9, third part — playback: the payload, the player and the bar

- **The pipeline carries it end to end.** The syndication translator now keeps a feed's audio/video enclosure as
  the occurrence's own `playback` claim (RSS/RDF via `itunes:image` + the single enclosure a podcast item has,
  Atom and JSON Feed via their enclosure links/attachments), after the visuals so it never takes the card's
  ordinal 0. `ContentStore.playbackCandidate(revision:)` reads it back, and the app's `prepare` states V1's
  precedence in one line: an episode plays from the enclosure its feed declared, every other card opens its
  article. `MediaCandidateClass.playback(forMIME:)` is the one place that decides what a MIME type *is*, so the
  translator, the storage check and the player cannot disagree.
  A subtlety worth recording: `SyndicationMediaLocator.resolve` refuses audio/video containers because they
  cannot be raster *card visuals*. That rule is right for a visual and wrong for a payload, so the resolver now
  takes `allowingPlayableMedia:` — the default keeps V1's card-visual rule exactly, and only the playback claim
  passes true.
- **The player is a protocol, the framework is an adapter.** `ReaderMediaPlaying` (Runtime) states what the
  composition may ask of a player; `MediaPlaybackAdapter` (app) is the only file in the app that imports
  AVFoundation (`AVPlayer`, a periodic time observer, the item's own failure status, iOS's playback session so
  an episode survives the silent switch). The app-wide player is deliberate: V1 kept playing across a context
  change, a sheet and the reader closing, and a per-association player could not.
- **The bar.** `MiniPlayerBar` draws `ReaderMediaState` in a **constant** 56 pt height whatever it states —
  playing, paused, loading or failed — so reporting playback can never move a card (T3's rule, restated for
  media). It is hosted in the app's shell as a bottom `safeAreaInset` and, as V1 did, inside the reader so an
  episode stays controllable while reading. `FullPlayerView` carries V1's two 15-second skips, a scrub with
  V1's own `m:ss` clock, and the error, when there is one, in the reader's words.
- **V1's card tap behaviour, in one place:** tapping the card that is playing pauses it, tapping it again
  resumes, and tapping another starts that one. Tapping the media area of a playable card already emitted
  `openMedia` (the UI's `isAudio == .mediaPlayback` port), and a card without a payload is *reported* — the
  coordinator asks the player to state the refusal, so the message lives where V1's `lastPlaybackError` did.
- **Deliberate difference from V1's reader, recorded.** V1 read articles in a raw `WKWebView` with its own
  loading bar and an explicit "open in Safari" link. V2 reads with `SFSafariViewController` (U2's decision: no
  web engine of our own to maintain), whose close control, reader mode and share sheet cover V1's close button
  and its share; the explicit Safari link and the loading bar have no counterpart there, and the playback bar
  V1 drew inside the reader is ported into the same place.

**Verified.** The suites that carry this work, each run green in isolation: syndication translator **34/34**
(including the new podcast/video/PDF cases), media candidate storage **4/4** (round-trip, one-playback-per-
revision by index, the pairing rules), action coordinator **4/4**, media coordinator **4/4** (toggle semantics,
a card with nothing to play, the surface intents, progress and the clock). Simulator: `testCardCopiesItsOwnLink
AndStatesIt` and `testMiniPlayerStatesPlaybackWithoutMovingTheFeed` (the hook plays a real silent WAV through
the real AVFoundation adapter; the bar measures 56 pt playing and paused, the feed never grows, the full player
carries both skips and closing returns) — both **TEST SUCCEEDED**.

**A note on the machine, recorded because it cost real time — and because it found a real defect.** The *whole*
package suite began exiting non-zero with `signal code 11` in the test bundle while every individual suite passed
alone, and the crashing test *differed between runs* (first `FeedMineRuntimeTests.LocalProductionSliceTests`,
then `FeedMineMediaTests.MediaPolicyResolverTests`). Zero assertions failed in any of those runs; the machine was
out of resources (`/System/Volumes/Data` at **100%**, swap at 5.8 GB of 7 GB), which is what a bundle dying in
allocation looks like.

Clearing the build cache to test that explanation exposed something the cache had been hiding:
`Tests/FeedMinePersistenceTests/ContextIdentityPersistenceTests.swift` imports `FeedMinePublication` while the
target never declared it, so a clean checkout could not build the test bundle at all. `Package.swift` now
declares it, and the suite was re-run from a clean build: **962 tests, 0 failures**, `Test Suite 'All tests'
passed`, exit 0.

**Remaining for T9:** nothing of its acceptance — the reader, the media and the share flows are ported and
proven. The DEBUG-only catalog explorer stays ordered into T12, and the two recorded differences above (V1's
Safari link/loading bar; a box as a reading surface needs T9's presentation source, still open from T8).

## T10 — 2026-10-10 (preferences, addresses, import and export): first part, the values and the tools

**The reader's preferences as one value.** `ReaderSettings` (Domain) is a versioned envelope of every preference
V1 kept in `UserDefaults` that this build honours: the appearance (`circadianPaletteOn`, `paletteFamily`,
`circadianTypographyOn`, `fontStyle`, `fontSize`, `nightMode`) and the behaviour (`prefetchImages`,
`contentFiltersEnabled`, `filterAutoExpire`), plus `hasSeenOnboarding` for T11 — each with V1's own default. The
migration (`ReaderSettingsMigration.fromLegacy`) maps V1's keys by name and **carries every key it does not
understand verbatim** (`carriedLegacyKeys`), including V1's own keys that belong to another delivery, which are
named in `ReaderSettingsLegacyKey.notPorted` so the migration is honest about what it leaves alone.
Storage is one nullable column (`reader-settings-v1`): a row written before it reads as V1's defaults, and the
four-hour filter rule keeps the column T6 gave it — the read composes it back into the value, so that fact has
one home and the two can never disagree.

**A feed's two addresses.** `FeedAddress` copies V1's `OPMLParser.normalizeURL` / `requestURL` rules (which are
also what built the shipped catalog's keys): entities repaired, host validated before the port and lowercased
with `www.` stripped, identity always `https`, default ports dropped, **every** trailing slash removed, and the
query **filtered** — `utm_*`, `fbclid`, `token`, `signature`, `x-amz-*` and the rest of V1's list name a visit,
not a feed. The request address keeps the original scheme, `www.`, ports, slashes and the whole query, because
that is what makes a signed feed fetchable. `FeedAddressTests` states each of those, including that two
spellings of one feed collapse to one identity.

**OPML as a value.** `OPMLDocument` parses a file into a preview (V1's rules: an outline with `xmlUrl` is a feed,
one without is a category that may nest, the first occurrence wins a duplicate and the address it carried is kept
verbatim) and writes one back. It reports what it will not import — an outline with no address, a category that
leads nowhere — instead of shrinking the file in silence, and a file that is not XML is an error, not an empty
preview. `OPMLDocumentTests` covers nesting, repeats, unicode titles and addresses, malformed input and a full
round trip.

**Import is two steps, and its commit is atomic.** `ReaderImportExportCoordinator.previewImport` writes nothing
(proven: the selection and the imported-sources table are untouched), and `commitImport` writes the feeds, their
addresses and the reader's selection in **one transaction**, keyed by identity — so the same file twice adds
nothing and the selection only gains a version when it actually changed. An imported feed is not in the shipped
catalog, so its address lives in `reader_imported_sources` (migration `reader-imported-sources-v1`), which is
where a session can find what to fetch.

**Export writes a local file.** V1's scopes reduced to what V2 actually has — the reader's selection, a
collection, a saved box (the sources its cards came from) — and V1's formats: OPML, JSON, CSV, Markdown, HTML,
plain text, share link and social card, with V1's own labels and symbols. An empty scope is reported rather than
written as an empty file.

**Verified.** `swift test` **987 tests, 0 failures**, exit 0 (the four earlier failures were the schema
catalogues, which now list the two migrations); the new suites: settings migration **6/6**, feed address **8/8**,
OPML document **5/5**, import/export **6/6**.

**Remaining for T10:** the settings *surface* (V1's `SettingsSheetView` sections: appearance, idioma,
circadian, desempenho, leitura, armazenamento, sobre), the app deriving `ReaderAppearance` from the settings and
the clock (today it passes the default and the hour never moves the palette), V1's String Catalog, and the UI
wiring for import (file importer → preview → commit) and export (scope × format → share/save).
