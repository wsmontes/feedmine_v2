# v1 → v2 port log

> **DOC CORRECTION — inventário de transferência V1 ≠ backlog/catálogo vigente (2026-10-10).** O status de itens `addressed`, `done` ou `validado` refere-se à **transferência técnica registrada nas datas respectivas**, não à validação de produto das 10 frentes. A entrega do `catalog.sqlite` pela release `catalog-v1` não implementa sincronização com [wawasoft/feed-repository](https://github.com/wawasoft/feed-repository), exigida para release em [PD-10](../product/PRODUCT_DECISIONS_2026-10-09.md)/[INV-18](../architecture/PRODUCT_INVARIANTS.md). Regras atuais de F02 (feed inicial, idiomas/lugares antes de votos temáticos), F05 (runway sem fim artificial) e F06 (pendência fora da fila, histórico imutável) prevalecem sobre paridade mecânica da V1. Preservar este log como trilha de execução, não reabrir automaticamente tarefas antigas.


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
| `Views/FeedScreen.swift` composition (`feedTopPadding`, `ZStack` + `HeaderHeightKey`) | `ReaderShell.swift` | The shell measures **its own** chrome with a layout preference and pads the content by exactly that; production can never open, close or resize it (T3/T5 rule). |

**Removed from V2:** the navigation toolbar (Feed context menu, Salvos, Fontes and the bottom search
field) and the U3 context bar. The context switcher survives as the header's status chip menu — the one
working V2 flow that has no V1 equivalent yet; T6 replaces it with V1's filter/preset surfaces. The chip
states the active context with the identifiers the U3 flow already used (`reader-contexts`,
`reader-context-label`, `reader-context-clear`), so no flow was lost.

**Ported and then removed — the clipboard banner.** `Views/ClipboardBanner.swift` was ported as
`Feedback/ClipboardBanner.swift` and **removed** on 2026-10-16 (architect's decision: remove it, do not
wire it). It never had a call site in V2 — nothing on screen ever built it — so it was a surface the
reader could not reach and a `checkClipboard()`/Add/Dismiss flow no test could exercise. What stays, and
was not touched, is the add-feed sheet's own paste: the reader's field and paste button
(`Sources/FeedMineUI/Tools/ReaderAddFeedViews.swift:239` `add-feed-input`, `:248-253` `add-feed-paste`)
over the closure the host injects (`:120-126`; `FeedMineApp/FeedMineApp/AppComposition.swift:1064-1068`)
— the view never reads the pasteboard itself. The sheet is exercised end to end by
`testAddFeedByLinkDiscoversAddsAndReadsIt`, which types the address; the paste **button** itself has no
executed test, and that gap is recorded rather than claimed. The removal is recorded with its evidence in
`docs/reviews/2026-10-16-superficies-honestas.md`.

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

### T10, second part — the settings surface and the appearance it implies

- **The surface.** `ReaderSettingsView` + `ReaderSettingsStore` port V1's `SettingsSheetView`: "Aparência" with
  the text size, "Design circadiano" with the two clock rules, the palette family and the font style (each picker
  offered only while its rule is on), V1's footer stating the hour it is on now, "Desempenho" with image
  preloading, "Leitura" with night mode, the four-hour filter rule and the content filters, the library file's
  size under "Armazenamento" and an "Sobre" section. A refused write states what happened **and** reloads what
  the backend has, which is V1's own lesson about a failed write that looked like a success.
  **Recorded differences:** V1's "Language" section is not drawn (V2 has no catalog of its own yet, and a picker
  that changes nothing would be a dead control), nor its "Reading Data"/"Share" sections (V1 stated counts from
  its own registry and shared a rendered stats card; V2 keeps neither — the same reason T9 records for the
  image share).
- **The appearance is derived, never stored.** `ReaderSettingsCoordinator.appearance(at:calendar:)` reads the
  reader's preferences and the hour the caller states: the two clock rules decide whether the hour is read at
  all, `nightMode` pins the night palette as V1's override did, and an unknown palette family, font style or
  type scale falls back to V1's default instead of inventing one. The app re-derives it at launch, when the
  reader changes something and when it comes back to the foreground — and never rebuilds a session for it, so a
  clock moving the palette cannot move the reader to another feed (the plan's own rule, and the reason the
  appearance is not part of any identity).
- **The app finally draws with it.** Until now the app passed `ReaderAppearance.standard` to every surface, so
  the clock never moved anything; `FeedScreen` now receives the derived appearance, which is what makes the
  preferences visible.

**The localization asked for by the plan is deliberately not re-keyed, and this is the reason.** V1's strings
live in one `Resources/Localizable.xcstrings` catalog keyed by **English source strings** (39 languages). V2's
copy is its own — Portuguese, matching the product's current language — and every one of its strings already goes
through `String(localized:)`, so the *infrastructure* is V1's. Copying the catalog verbatim would translate
nothing (no key matches), and re-keying V2's copy to V1's English would change the app's language for the reader
who has it today. Preserving V1's *translations* is therefore a product i18n decision with its own key strategy,
not a file copy, and it is recorded rather than half-done.

**Verified.** `swift test` **992 tests, 0 failures**; the new suite: settings and the appearance derivation
**5/5** (the clock's five periods, turning the clock off, night mode pinning, unknown values falling back, and
the surface store's acceptance discipline); iOS build **SUCCEEDED**; and
`testSettingsReachTheirControlsAndSurviveReopening` (real simulator) opens *Ajustes* from the reader's own menu,
finds V1's sections, writes two preferences and reads them back after closing and reopening the surface —
**TEST SUCCEEDED**.

### T10, third part — the tools' surfaces

- **`ReaderImportPreviewView`** is V1's two-step import on screen: the file's own title, one row per feed (with
  its category path), the summary line V1 printed ("N fontes · N repetidas · N ignoradas"), and the entries it
  will not use with their reason. "Importar" is the only thing that writes; "Cancelar" is free, and the package
  tests prove it: the preview touches neither the selection nor the imported-sources table.
- **`ReaderExportView`** is V1's `ExportView`: the scopes V2 has (the reader's sources, every collection, every
  box), V1's formats with its own labels and symbols, a preview of the document the choice would write, and the
  two actions on it. Sharing carries the **file** (so "Salvar em Arquivos" comes with the same sheet); V1's
  separate "copy" of the preview is not drawn, and the reason is recorded here rather than left implied.
- **The app drives both**: the reader's menu opens the export sheet and the sources screen gained V1's own
  "Importar OPML" row (V1 imported from that very screen), which is a `.fileImporter` over `.xml`/`opml` — the
  kinds V1's own Info.plist registered — reading the file and showing the preview before anything is written.
  The scene now says which export it is and keeps the preview text, so a change of scope or format re-produces
  the document without writing one.
- **Evidence in the simulator, end to end:** `testImportPreviewCommitsAndExportPreviews` launches with a fixture
  whose file holds one usable feed, one repeat of it and one unusable address; the preview states exactly that
  (1 entry, 1 repeat, 1 rejection, "1 fontes · 1 repetidas · 1 ignoradas"), the confirmation **writes it through
  the real database** and the app states what it did ("Importadas 1 …"), and the export sheet then shows a scope,
  the share action and a document preview — **TEST SUCCEEDED**.

**T10 is complete** as far as the plan's acceptance goes: preferences are functional (the appearance follows the
reader's rules and the clock, and never the feed), import produces usable sources with their addresses kept,
export produces usable files in V1's formats and scopes, and none of it is a monolithic service: each piece is a
value, a coordinator or a view with its own tests.

## T11 — 2026-10-10 (onboarding, curadoria e preparação): first part, o que o V1 é de fato

**O reconhecimento corrigiu o próprio plano.** O texto do T11 pede "welcome→escolhas→duelos→salvar", mas o
checkout do V1 tem um onboarding de **dois estágios** (Welcome → Composer) e o código dos duelos
(`StoryDuelScene`, `CuratedOnboardingSession`, `OnboardingSeed`, `applyOnboardingTopics`,
`curatedOnboardingCandidates`) está **sem callers de produção**. Portar os duelos seria portar código morto — e a
paridade que o plano exige ("progressão/valores iguais ao V1 para as mesmas escolhas") é a do fluxo vivo. Decisão
registrada: **Welcome → Composer**, sem duelos.

**A receita é um valor de V2, com as chaves do V1.** `FeedRecipeDefinition` (Domain) traz idiomas (subtag
primária, minúscula, ordenada), `discoveryLevel` 0…1 com `neutral` em 0.55, preferências de tópico e de
editorial, os tipos de mídia, `adjustFromOpens` e `modelVersion` — e o vocabulário de chaves que o V1 usa
(`topic:…`, `region:…`, `media:…`, `editorial:…`, `nature:…`), que é o que faz uma receita guardada continuar
significando o mesmo. Duas assimetrias do V1 estão preservadas e testadas: uma resposta pesa **±1,5** e "normal"
pesa **zero**; e um tipo de mídia que o leitor **removeu** pesa **−3**, enquanto os tipos que ele manteve não
pesam nada. `CuratedFeedSummary` é o "capô" como valor: as respostas que o leitor realmente deu, mais fortes
primeiro.

**A preparação já estava entregue — e é honesta.** `FeedPreparationView` (PD-3) mostra fontes contatadas, fontes
que trouxeram novidades, **manchetes realmente admitidas** e cards preparados, com o movimento vindo desses fatos
e desligado sob Reduce Motion; `PreparationProgressTests` cobre os fatos. O V1 faz o mesmo (contadores e nomes de
fontes reais, sem manchete fabricada). E a auditoria das views portadas confirma a regra da T11 por construção:
**nenhum** `URLSession`, `Data(contentsOf:)`, `AsyncImage` ou `ImageLoader` em `Sources/FeedMineUI` — o único
"placeholder" é o desenho de áudio do V1, sem headline.

**Decisões que o reconhecimento obrigou, registradas antes de escrever código:**
- **Um artefato, não dois.** O V1 persiste `definition_json` (perfil efetivo, aprendido) **e** `recipe_json`
  (explícito) e os mescla no ranqueamento. O V2 não aprende de duelos (ver acima) nem de aberturas ainda, então
  o perfil efetivo *é* a receita: um artefato por preset curado. `adjustFromOpens` fica como a promessa que ele é,
  não como comportamento fingido.
- **`editorial:*` precisa de dois campos do catálogo.** O V1 deriva as chaves editoriais de uma heurística de
  texto/domínio (`editorialAssessment(for:)`) sobre título, descrição, tags e host da fonte. O registro do
  catálogo do V2 hoje expõe chave, título, `request_url`, `site_url`, idioma, tipo de mídia, qualidade, default e
  nós — **não** descrição, tags nem host. As colunas existem na tabela; a leitura é que não as traz. Sem elas o
  controle "Source balance" do Composer seria um peso que nunca casa com nada — um controle morto. Acrescentar os
  dois campos ao registro é o primeiro passo da próxima fatia.
- **Codificação de mídia**: mantida a do resolvedor do V1 (`media:text`/`media:audio`/`media:video`, exclusão em
  −3, sem peso na inclusão).
- **Alvo de primeira tela**: o V1 não inventa um alvo no lane do runtime e o V2 também não; a preparação do V2
  afirma apenas o que mediu.

**Verified.** `swift test` **1000 tests, 0 failures**, exit 0; a nova suíte: receita **8/8** (normalização de
idiomas, clamp de discovery, conjunto vazio de mídia como "todos", as duas assimetrias de peso, os critérios de
filtro, o resumo ordenado, envelope parcial e round trip).

### T11, second part — o catálogo dá os fatos, o Editorial resolve a receita

- **Os dois (agora três) campos que faltavam.** O registro do catálogo passou a expor descrição, host de
  exibição, tags, `nature` e `activity`. Sem eles a avaliação editorial do V1 não teria o que ler e o controle
  "Source balance" seria um peso que nunca casa.
- **`FeedEditorialAssessment` (Editorial)** é o `editorialAssessment(for:)` do V1: as mesmas listas de sinais
  (mastheads reconhecidos, institucional, especialista, comercial, agregador, títulos/hosts genéricos — dados de
  curadoria do V1, copiados verbatim), a mesma fórmula
  `qualidade·0.30 + autoridade·0.42 + atividade·0.18 + direto·0.10`, o mesmo piso de evidência por classe, e as
  mesmas chaves (`editorial:reference|specialist|distinctive`). Lê os fatos do catálogo do V2, não os do V1.
- **`FeedRecipeResolution` (Editorial, puro)** é o `sourceMultiplier` do V1:
  `exp(Σ peso·(0.25+confiança·0.75)·scopeScale · 0.19 · (1 − discovery·0.42)) · (0.9 + qualidade/100·0.2)`,
  clampado em 0.42…3. As chaves de uma fonte saem do que o catálogo diz: suas colocações (`topic:`/`region:`),
  seu tipo de mídia, suas naturezas editoriais, sua `nature` e seu escopo — e `scope:` entra pela metade, como no
  V1. **O guard do V1 está preservado:** uma fonte que a taxonomia não coloca em lugar nenhum pesa exatamente 1,
  sem nem o ajuste de qualidade, porque a receita não tem o que dizer sobre ela. Sem evidência aprendida a
  confiança é zero e o peso mantém o piso de 0.25 — quando o V2 aprender com aberturas, é esse termo que cresce.
- **Testes determinísticos** (`FeedRecipeResolutionTests`, 7): os valores calculados à mão (1.1002 para `.more`,
  0.9831 para `.less`), o achatamento por discovery, o tipo removido caindo abaixo do centro, a janela de
  qualidade, o meio peso do escopo regional, o guard da fonte sem colocação, o filtro que a receita declara e a
  regra de nomear do V1.

**Remaining for T11:** o `CuratedFeedCoordinator` (`save`/`inspect`/`update`) com a receita persistida ao lado do
preset e os multiplicadores ligados ao `ResolvedSelectionPolicy` da sessão; as duas cenas (Welcome e Composer,
com o preview de cards reais e os controles exatos do V1) e o capô; e a evidência de UI.

### T11, third part — a feed the reader shapes, and the ranking it produces

- **The ranking reaches the session.** `ScoringBehavior` gained `.weighted([SourceID: Double])`: the engine ranks
  by the reader's own recipe, a card taking the strongest of its sources' weights, and a session that is not
  weighting keeps ordering by recency exactly as before (`WeightedScoringTests`, 3). The app resolves a curated
  context's recipe against the **catalogue's own facts** (`feedFacts()`: placements, media kind, nature, quality
  and the editorial assessment) and maps catalog keys onto the session's `SourceID`s.
- **A recipe edit is a new behaviour.** The scoring policy version is derived from the recipe itself (an FNV-1a
  over its canonical JSON), so an edited feed keeps its identity — the reader stays where they are — while an
  Edition published under the old recipe is never reused. The app-level test proves both: the session's policy is
  `.weighted`, its version equals the recipe's, and editing the recipe changes it.
- **The coordinator and storage.** `CuratedFeedCoordinator.save/inspect/update/delete` over the recipe persisted
  with the preset (`reader-curated-recipe-v1`: a nullable column, so a smart bookmark carries none and a curated
  feed's deletion takes both). `CuratedFeedCoordinatorTests` covers save (the identity is the preset plus the
  criteria the recipe states — the weights are *not* identity), inspect, edit, delete, the multipliers and the
  naming rule.
- **The two scenes.** `ReaderOnboardingView` is V1's **Welcome → Composer**, with its own copy, the card cascade
  (the reader's real cards, or abstract panels — never a fabricated headline), the trust badges, the two CTAs,
  and the Composer's exact controls: language chips (the last one cannot be removed), the Discovery slider with
  V1's own "Focused/Exploratory" ends and no percentage, the Source balance rows with their three editorial keys,
  the topic rows cycling normal → more → less, the media toggles, and the pinned footer (Reset / Start broad /
  Open my feed). **The duel scenes are deliberately not ported**: V1 keeps them in the repo with no production
  caller.
- **The hood.** `CuratedFeedInspectorView` is V1's "open hood": the badge and its promise, the editable name, the
  three metrics, the reader's own answers strongest first, languages and media kinds, discovery with the hour,
  the privacy note word for word — and the two actions, editing the controls and deleting the feed.
  **Recorded difference:** V1 drew sliders over its *learned* weights with a confidence label; V2 has no
  evidence yet, so the hood lists the answers instead of inventing a confidence.
- **The gate.** The app shows the onboarding when the reader has not met it (`hasSeenOnboarding`, T10's
  preference) or when a UI test asks for it, and a saved recipe is stored, activated and closes the gate.

**Verified.** `swift test` **1016 tests, 0 failures**; iOS build **SUCCEEDED**; and
`testOnboardingWelcomeComposerAndSave` (real simulator) walks the whole flow — the welcome scene with V1's words
and badges, the Composer with its sliders, chips, a topic cycling its answer and a media toggle, saving and
opening the feed, and then the hood with its badge, its privacy note and its close — **TEST SUCCEEDED**; the
app-level curated-session test also **TEST SUCCEEDED**.

**Known, recorded gaps for T12:** V1's Composer preview ranks the reader's own cards by the recipe being shaped;
V2's shows the reader's own cards in their published order (no preview pipeline is invented for it). V1's
"Re-watch intro" setting is not drawn — the gate is reachable through the menu's own "Criar feed curado", which
is V1's other entry point.

## Aceite do T12 — 2026-10-10

O arquiteto aceitou a transferência V1 → V2 para o marco interno: **`T12 — ACCEPTED WITH DOCUMENTED EXCEPTIONS`**.
Portão medido: pacote **1017/0**; `CompositionTests` **24/0**; `FeedMineUITests` **22/0** numa corrida do scheme
(o texto do arquiteto cita 21 porque foi escrito antes do vigésimo segundo teste, o do bar de playback vivo).
Comparação visual completa: as quatro referências do V1 e as três superfícies que ele acrescentou, estas contra
capturas do **próprio V1** feitas no segundo simulador — contagens conferidas (Argélia 537, Angola 326,
Argentina 1411). Soak no simulador medido: ~4 min de scroll real, pico de RSS 347 MB e estável em 302 MB nos
últimos 20 min, com o mesmo card de checkpoint antes e depois de terminar + relançar.

Ressalvas documentadas, **nenhuma delas bloqueante**: validação em aparelho físico indisponível (os dois iPhones
conhecidos estão `unavailable`) e o soak de 30 min, que naquela rodada ficou incompleto pela oferta finita dos
quatro feeds iniciais — **cumprido depois, na segunda rodada registrada no fim deste arquivo**.
As duas diferenças cosméticas da lista de países — bandeiras do V1 trocadas por um ícone de globo e o
chevron de "entrar" não desenhado — foram aceitas como observação de baixa prioridade, sem gate.

O trabalho de desempenho e escala com muitas fontes fica como **obrigação pré-publicação**, e o arquiteto fixou
a forma dele: conjunto amplo selecionado **pelo fluxo legítimo do aplicativo** (a cascata de países já
comprovada), namespace persistente de teste, Runtime real, scroll prolongado medindo runway, memória, hitches,
CPU, continuidade e ausência de duplicações, registrando à parte qualquer esgotamento legítimo de conteúdo.

### Segunda rodada do soak — 2026-10-10: a duração cumprida

Rodada com a dupla que o arquiteto nomeou, não um substituto artesanal: `scripts/soak.py`, que roda a preparação
opt-in **pelas próprias superfícies do app** (menu → Fontes → Países → alternador da Argentina, com o teste
exigindo `value == "selected"`) e depois amostra a cada 30 s o **processo** FeedMine (RSS, CPU pelo caminho do
executável) e o banco do Runtime, transmitindo o log do app em paralelo. Build Debug, namespace persistente
`B50A0000-…030`. Em contêiner novo, a preparação deixou **1415 alvos** — a subárvore argentina escolhida por
cliques na superfície entregue, nada escrito no banco à mão.

| Janela | O que foi medido |
|---|---|
| 30 minutos (09:05→09:35 locais) | 61 amostras de 30 s, **0 erros, um único PID**, `elapsed 1800,01 s`. RSS 13 MB no lançamento → pico **376 MB** → **290 MB** no fim; últimos 10 min dentro de 290–329 MB, **sem crescimento monotônico**. CPU mediana **1,30 %** (máx 98,5 %, a rajada de lançamento). Conteúdo: 54 → 81 cards, 1 858 → 10 104 origens, 3 segmentos. |
| Scroll contínuo | **766 arrastadas** nos cinco blocos com contador (164/163/163/162/114) mais um primeiro bloco de 5 min cujo contador o teto de 300 s por célula do harness encerrou antes do relatório. Cada bloco comparou quadros consecutivos: 19–22 telas distintas e **nunca três quadros idênticos seguidos** — sem travamento, tela branca ou fim artificial. |
| Integridade | `duplicate_revisions_per_segment = 0` e `duplicate_card_ids = 0` em todas as amostras, reconferidos após o relançamento; checkpoint em **61 de 61** amostras; no ciclo do próprio `soak.py` (fundo → terminar → relançar) voltou o **mesmo checkpoint** — `same_restart_checkpoint: true`, `failures: []`, saída 0. O log do app (5,6 MB) traz as admissões da costura (`installed cards=17/25/31 …`) e um único evento que não é admissão: recusa ATS (`NSURLErrorDomain -1022`) de um recurso não-HTTPS entre as 1415 fontes. |

**Desvios desta rodada, ditos em vez de escondidos.** (1) O teto de 300 s por célula encerrou o primeiro bloco
antes do contador, então o primeiro minuto dos 30 correu sem arrastadas; os 29 restantes foram contínuos. (2) A
ferramenta precisou de dois reparos para rodar nesta máquina: `simctl launch --terminate-running-process` falha
aqui com `FBSOpenApplicationServiceErrorDomain code=4` (a flag chega a ser reportada como id do bundle) sempre que
o app não está rodando, então ela agora para o app explicitamente e lança simples; e uma rodada de preparação
deixa `com.feedmine.development` registrado num estado que `simctl launch` recusa, exigindo reinstalação da mesma
build antes de amostrar. (3) **Hitches continuam não medidos** — a ferramenta declara isso e nomeia o Instruments
Animation Hitches; o que a rodada acrescenta é o log do app acima, cobrindo a janela inteira.

## Defasagens pós-T12 — 2026-10-10 (fonte por link, filtros de conteúdo, player)

O T12 fechou a transferência do frontend. Uma revisão de produto contra o código encontrou oito defasagens
reais restantes; esta rodada fecha as **três de severidade alta**, na ordem em que a revisão as pôs: adicionar
fontes por link, filtros pessoais de conteúdo, e o player de podcasts. As outras cinco (exportar artigos salvos,
estado de lido, idioma da interface, importar OPML para uma coleção, compartilhar como imagem) ficam registradas
como estão na revisão, sem trabalho iniciado.

### A — Uma fonte a partir de um link

**O defeito que apareceu primeiro, e que não estava na revisão.** O caminho de importação que já existia — o
"Importar OPML" que a matriz dava como validado — gravava as fontes em `reader_imported_sources` e juntava as
chaves na seleção (`ReaderLibraryStore.commitImport`), mas `TrustedFeed.resolveAvailable` só consultava o
`catalog.sqlite` empacotado. Uma chave importada era **descartada**: a fonte entrava na seleção e nunca era
buscada, logo não gerava card nenhum. O mesmo buraco impediria qualquer link colado de funcionar.

- **Identidades do leitor** (`ReaderSourceIdentity`, Composition): Source/Target/Binding determinísticos por
  SHA-256 sobre a chave canônica, em namespaces próprios (`feedmine.reader-source.*`), com o binding declarando
  esse namespace (`TrustedFeed.principalNamespace`). A ordem de autoridade é **catálogo → fontes do leitor →
  lista da sessão**: uma chave que o catálogo carrega mantém as identidades dele mesmo quando o leitor a importa
  (um OPML cheio de feeds populares não pode cunhar uma segunda identidade por feed), e a escolha não depende do
  que a sessão por acaso carregou primeiro — é o mesmo em todo lançamento.
- **Descoberta** (`FeedMineSyndication`): `FeedLinkInput` (extração com `NSDataDetector` + passo por tokens,
  vocabulário de esquema fechado, classificação ordenada com casa exata ou subdomínio) e `FeedLinkResolver`
  (sondagem HEAD e ranged, `link rel=alternate` com endereços relativos resolvidos, caminhos comuns 3-a-3 sob
  deadline, YouTube/GitHub/Apple Podcasts), sobre um `FeedDiscoveryTransport` com teto de bytes **em streaming**
  e guarda de host público (a mesma `NetworkHostPolicy` que a mídia usa).
- **Tela** (`ReaderAddFeedView`): campo, colar do clipboard, pré-visualização (acima de cinco feeds o V1 pedia
  confirmação), coleção de destino e criação de coleção — com as duas entradas de menu do V1 ("Adicionar feed" e
  "Adicionar feed à coleção", esta só no contexto de uma coleção, como destino próprio).
- **Arquivo atômico**: `commitImport` passou a aceitar a coleção de destino e grava fontes, seleção e associações
  **na mesma transação**; uma coleção que não existe recusa a escrita inteira, em vez de deixar o leitor com
  feeds que ele julgava estar numa coleção.

**Duas correções que vieram de fora.** A revisão do arquiteto (ChatGPT) apontou (P1) que a autoridade dependia
da sessão e (P2) que o arquivamento em coleção não era atômico; ambas estão corrigidas acima, cada uma com
teste próprio. Antes disso, dois defeitos meus foram pegos pelos **meus próprios testes**: a ordem de extração
não era a do texto e o deadline da descoberta não cancelava as sondagens em voo (10 s em vez de 0,3 s).

**Provado.** `FeedLinkInputTests` (3) e `FeedLinkResolverTests` (10, transporte falso, incluindo o deadline e o
teto de bytes); `AddFeedTests` (7, no alvo do app, sobre o runtime real: link → descoberta → persistência →
seleção → endpoint → aquisição → card; relançamento com as mesmas identidades; duplicata; endereço sem feed;
coleção de destino; arquivamento inválido que não escreve nada; autoridade independente da sessão); uitest
`testAddFeedByLinkDiscoversAddsAndReadsIt` (no simulador, partindo de zero fontes: colar, adicionar, ver o card,
relançar e continuar vendo). Todo o fixture é servido pelo próprio app — nenhum teste toca a rede.

### B — Filtros de conteúdo

O motor já existia (`ReaderContentExclusions`, consultado em `CandidateProvider`) e o interruptor dos Ajustes
gravava uma preferência que **ninguém lia**; não havia superfície para escrever regra nenhuma.

- As regras passaram a viver nas **preferências do leitor** (`ReaderSettings.contentFilterRules` e
  `contentFilterTemplates`), como no V1, e não na lente: por isso valem em toda superfície — inclusive no feed de
  uma coleção, que nascia com filtro irrestrito e teria perdido as exclusões.
- **O portão mestre desativa a aplicação sem apagar nada**: `ReaderContentFilterPolicy` é uma função pura, e com
  o interruptor desligado as exclusões efetivas ficam vazias enquanto as regras continuam guardadas e visíveis.
- **Os modelos são o ficheiro do V1** (`content_filter_templates.json`, 6 modelos e 33 idiomas) agora como
  recurso do pacote; nomes e palavras resolvem-se como no V1 (idioma do leitor, idioma base, e inglês sempre).
- **Tela nova** (`ReaderContentFilterView`, em Ajustes → "Filtros de conteúdo"): interruptor com rodapé que diz o
  que ele faz, os seis modelos com a contagem de regras de cada um, e as palavras do leitor (adicionar por
  vírgulas, apagar por swipe). A sessão é reconstruída quando o que ela esconde muda.

**Diferença registada.** No V1 cada filtro próprio tinha nome e interruptor individual, e um contador de "itens
ocultos hoje" contado na ingestão; no V2 uma palavra é uma regra (é o que a aplicação usa) e não há contador,
porque o V2 não conta acertos ao admitir candidatos. Digo em vez de fingir.

**Provado.** `ReaderContentFilterPolicyTests` (6: resolução por idioma, regras + modelos, o portão que mascara
sem apagar, conjunto vazio não é critério, aplicar preserva a lente, o catálogo é o ficheiro do V1);
`ContentFilterTests` (2, no app: uma regra que casa com tudo não publica nada e o portão desligado devolve o
feed com a regra ainda guardada; um modelo ligado esconde o que as suas palavras casam e desligá-lo não toca nas
palavras do leitor); uitest `testContentFilterSurfaceListsTemplatesAndKeepsTheRules`.

### C — Player de podcasts

O V1 tinha um player global (`AudioPlayerManager`, 498 linhas) com tudo o que um leitor de podcasts espera; o V2
tinha reprodução dentro da sessão e nada disto: sem Now Playing, sem comandos remotos, sem tratamento de
interrupção nem de rota, sem posição guardada, e sem `UIBackgroundModes` — o áudio morria ao bloquear a tela.

- `MediaPlaybackAdapter` é o `AudioPlayerManager` **portado**: sessão de áudio
  (`.playback`/`.spokenAudio`/`.longFormAudio`, ativada ao tocar), `MPNowPlayingInfoCenter` (título, duração,
  taxa, URL do ativo e a chave privada do card), `MPRemoteCommandCenter` (play só se não está tocando, pause só
  se está, toggle, ±15 s com `preferredIntervals`, `changePlaybackPosition`, next/previous desligados),
  interrupção de chamada (pausa; retoma quando o sistema diz `shouldResume`) e retirada dos fones (pausa).
- **Posição por episódio**: tabela nova `reader_playback_positions` (migração aditiva), escrita a cada 5 s de
  reprodução e ao sair de cena, restaurada só acima do limiar do V1 (5 s) e meio segundo depois de o item estar
  pronto; o fim do episódio limpa a posição e o marcador de concluído, e voltar atrás torna o episódio retomável.
- `UIBackgroundModes=audio` declarado no Info.plist do app.

**Provado.** `PlaybackTests` (8, no app, com áudio real — um WAV silencioso escrito pelo teste — e o AVPlayer
real: estado e dicionário do lock screen, retomada acima do limiar e não abaixo, interrupção que pausa e retoma
com `shouldResume`, fones retirados que pausam, fim que limpa a posição e seek para trás que a devolve, replay
que recomeça e replay no meio que não reinicia, comandos ligados e desligados como no V1, teardown que limpa o
item e o lock screen); `PlaybackPositionStoreTests` (5), `ReaderPlaybackPositionRulesTests` (1),
`ReaderPlaybackPositionsAdapterTests` (2); uitest `testPlaybackResumesWhereTheReaderLeftIt` (toca, sai do app,
volta, e o player cheio declara a posição retomada).

**Limite honesto.** A continuidade na tela bloqueada e os comandos de fone **não** foram observados de ponta a
ponta: o que o simulador prova é que o episódio segue tocando fora de cena (sessão e background mode
declarados) e que a posição volta. Isso exige aparelho físico, e fica dito como pendência, não como feito.

### Portão desta rodada

`swift test` **1066/0**; alvo do app (`FeedMineAppTests`) **44/0**; uitests novos no simulador: 3 (fonte por
link, filtros, retomada) — todos verdes, além dos que já existiam. Quatro asserções de inventário de migração
foram atualizadas porque a migração nova passa a ser a última (`reader-playback-positions-v1`) e a tabela nova
entra na lista de objetos do esquema; nenhuma delas mudou de comportamento.

### Revisão adversarial das três fatias (2026-10-10, mesma rodada)

A mesma revisão que apontou as duas correções de A (autoridade independente da sessão; arquivamento em coleção
atômico) encontrou, ao revisar C e B, **quatro defeitos no player e uma regressão nos filtros**. Todos foram
corrigidos com teste próprio:

1. **A restauração atrasada atropelava um seek do leitor.** A restauração espera meio segundo e o item ficar
   pronto; se o leitor buscasse nesse intervalo, voltava para a posição lembrada. Agora um `interactionRevision`
   conta as interações do leitor: um seek dele abandona a restauração pendente. `testAReadersSeekAbandonsAPendingRestore`.
2. **Trocar de episódio não gravava a posição do anterior.** `play(_:)` substituía o item sem salvar; o avanço
   desde a última gravação periódica (até cinco segundos) era perdido. Agora salva antes de substituir, com o
   mesmo guard de conclusão. `testSwitchingEpisodesSavesThePositionOfTheOneLeft` (A → B → A, sem pausa nem stop).
3. **Um evento de fim alheio podia concluir o episódio atual.** O observer era registrado com `object: nil`;
   um evento atrasado do episódio anterior limpava a posição do atual. Agora o observer é por item, com a
   geração conferida. `testAForeignOrLateEndEventCannotCompleteTheCurrentEpisode`. (Os testes antigos publicavam
   a notificação com objeto `nil`, o que reforçava o defeito em vez de verificar a associação; agora publicam
   com o item do próprio player, como o sistema faz.)
4. **Um seek pendente podia escrever no episódio seguinte.** `seek(to:)` suspende no `await player.seek(...)` e
   depois atualizava e salvava sem conferir item e geração. Agora captura ambos antes e confere depois; o mesmo
   guard vale para o callback de falha do item.

E a regressão de B:

5. **As exclusões de um contexto eram apagadas.** `applied(_:)` **substituía** todas as exclusões pelas globais,
   o que apagaria na aplicação as palavras próprias de um marcador inteligente — inclusive as que
   `LegacyUserStateImport` preservou (`excludedSearchTerms`/`excludedKeywords`), fazendo um marcador importado
   mostrar justamente o que excluía. Agora as duas somam-se (`ReaderContentFilterPolicy.combining`) e o portão
   mestre mascara **apenas** a metade global. `testAContextsOwnExclusionsSurviveTheGlobalGate` (app, alternando o
   portão) + `testAContextsOwnExclusionsSurviveTheGlobalGate` na política pura.

**Diferença registada, não corrigida nesta rodada:** o lock screen não publica arte do episódio. O V1 publicava
a imagem do seu cache; o `ReaderMediaItem` do V2 não carrega imagem local. Uma correção pede uma referência
opcional à imagem que o slot do card já materializou, publicada só se item e geração ainda coincidirem, sem
download nenhum no player. Severidade baixa, registada para depois das corridas — e o **nome do programa** no
Now Playing, que faltava, foi acrescentado nesta rodada (artista, como no V1).

## Contrato de aceitação vigente e o primeiro passo de F01 — 2026-10-10 (noite)

**O produto mudou de régua e isto está refletido no trabalho, não só lido.** O Product Owner subiu ao `main`, nesta
ordem: o **norte de produto** (descoberta antes de assinatura), o **benchmark de aceitação B01–B06** (contrato
operacional vigente, execução autônoma, sem redução de critérios), o **mapa das dez frentes** e, por fim, o
**PRD de F02** (o onboarding *é* o feed, com convites editoriais contextuais — o Welcome → Composer deixa de ser a
porta de entrada). O que segue é o estado executado contra essa régua.

### 1. Revisão adversarial da rodada anterior: seis defeitos corrigidos

Quatro no player (restauração atrasada atropelando um seek do leitor; troca de episódio sem gravar a posição do
anterior; evento de fim não amarrado ao seu item; seek pendente escrevendo no episódio seguinte), um nos filtros
(as exclusões de um contexto eram substituídas pelas globais, apagando na aplicação as palavras de um marcador
importado) e dois que um revisor independente de outra família de modelo encontrou no meu próprio código de A:
a folha de adicionar feed **entupia** depois de uma colagem falhada, e os **modelos de filtro resolviam sempre em
inglês** (`Bundle.module` não tem localizações). Todos com teste próprio; o registro detalhado está acima, na
secção "Revisão adversarial". Também nesta rodada: candidatos que a fronteira de identidade recusaria (link
não-web, credenciais) passam a ser recusados no preview; o chip da lente deixa de poder mexer nas regras globais;
os chips do Composer dizem o seu estado à tecnologia assistiva.

### 2. O corpus e o avaliador do benchmark (fora do código de produção)

- `bench/build_corpus.py` gera o corpus a partir do catálogo real empacotado, lendo as suas próprias etiquetas.
  Medido: **2.305 fontes** (A elegível 942, B 1.123), **15.917 itens** (A 6.885, B 8.112), **270 pares duplicados
  entre publicadores** e **75 revisões materiais** (PD-1), mistura de protocolos (RSS 1.285, Atom 587, JSON Feed
  433), classes de comportamento (normal 1.622, lento 287, intermitente 265, timeout 131), 75 documentos vazios,
  231 fontes com mídia lenta; mídia congelada em `media.pack`. Determinismo verificado: um `--rebuild` produz
  bytes idênticos (só os dois carimbos `generated_at` mudam, como o esquema pede).
- `bench/serve.py` é o transporte local (127.0.0.1:8757): serve cada documento e a mídia, reproduz atrasos e
  falhas, responde a HEAD/Range/condicional (304/206/416), registra **cada requisição** em JSON e publica os
  totais do corpus em `/totals` — o avaliador aprende os totais antes de qualquer execução.
- `bench/oracle.py` julga **só o que a execução deixou**: o log do transporte (fontes contactadas), o banco do
  app (cartas publicadas, atribuição, ordinais) e as etiquetas do corpus. Ele recalcula a identidade da fonte a
  partir da chave (SHA-256 sobre o namespace do catálogo) em vez de perguntar ao app, e traz os limiares de B01 e
  B02 escritos à mão (80%, 20 fontes, 15%) com o SHA-256 do documento do benchmark registrado nos critérios.
- `bench/run.sh` é o runner: verifica `MANIFEST.sha256` **e** `EVALUATOR.sha256` e **recusa correr** se o corpus
  ou o próprio avaliador mudaram desde o congelamento; registra a identidade da execução (commit, árvore suja,
  dispositivo, iOS, hashes dos insumos); constrói o app como um leitor o receberia; troca o catálogo e declara a
  exceção de rede local **no bundle construído** (nada no código de produção); sobe o transporte; dirige a
  jornada pelo app real; e escreve `bench/run/<stamp>/report.md` com a matriz de cláusulas.
- `FeedMineAppTests/DiscoveryBenchmarkTests.swift` é o driver (alvo de UI, fora do app): caminha a jornada com
  gestos nativos e **não julga nada**. Ele não encurta o trace de B03 (1.800 avanços a 1/s, rajadas de 3/s por
  20 s a cada 5 min) e não permite que uma variável de ambiente o encurte.

### 3. F01 — descoberta automática de fontes (a promessa do produto, medida)

- `ReaderDiscoveryPool` (Composition): um perfil (idiomas + nós de tópico do catálogo) resolve um **pool**
  determinístico de fontes do catálogo empacotado, filtrado pelas etiquetas do próprio catálogo (idioma,
  colocação em subárvore, tipo de mídia) e ordenado por qualidade e chave. Um perfil vazio não descobre nada.
- A sessão passou a ser construída sobre **seleção + pool** (`FeedAssociation.init(discovery:)`): as fontes
  descobertas são registradas como alvos e entram na elegibilidade, e **nada é escrito na seleção do leitor** —
  a tela de fontes continua dizendo exatamente o que ele escolheu. Um contexto sem perfil (sem receita curada e
  sem critérios de lente) não descobre nada, como antes.
- Perfil vem do **estado real**: uma receita curada (idiomas + `topic:` com "mais") ou os critérios da lente
  (idiomas, regiões, tópicos). O Composer ganhou o controle de **região** que B01 exige e que a V1 não tinha,
  respondendo no vocabulário que a receita já usava (`topic:90_countries/<país>`) — sem campo novo, sem esquema
  novo, e com o estado do chip exposto à acessibilidade.
- **Medido no catálogo real**: um perfil `pt` + Brasil + atualidades coloca **≥50 fontes** no conjunto de
  aquisição sem nenhuma escolha manual, todas elegíveis para a sessão (`CompositionTests
  .testAProfileOfInterestsSuppliesSourcesTheReaderNeverNamed`). O pool em si tem cinco testes próprios (filtro
  por idioma e tópico, determinismo, perfil vazio, idioma sem fontes, teto com ordem de qualidade).

### 4. O que muda agora, por contrato: F02

O PRD de F02 **substitui** a porta de entrada que a V2 herdou da V1: a pessoa entra no feed, e os interesses são
declarados dentro dele por convites editoriais contextuais ("Quero mais disso" / "Não é minha praia"), com
desfazer, com "Preferências de descoberta" para os controles avançados, e sem questionário obrigatório. O
Composer atual é, portanto, um gate que precisa sair — e a jornada que o driver de B01 caminha hoje (Composer)
terá de ser re-escrita para a experiência do PRD antes que B01 possa ser julgado contra ela.

**Estado honesto:** o pool de F01 é o que dá substância à promessa (variedade real de fontes sem escolha manual)
e já está implementado e medido; a camada editorial do feed, os votos e a primeira abertura sem Composer **não
estão implementados**. Nenhum gate B01–B06 foi declarado PASS nesta rodada.

### 5. A primeira execução do driver de aceitação — o que ela encontrou

O benchmark passou a rodar de fato nesta rodada (o runner recusou a primeira tentativa por não levar o ambiente
até o processo de teste: `xcodebuild` **não** encaminha o ambiente de quem o invoca, e o driver lê
`FEEDMINE_BENCHMARK`; a variável precisa do prefixo `TEST_RUNNER_`). Com isso corrigido, a jornada foi caminhada
pelo app real, e o que ela mediu foi:

|Observação do driver |Defeito real |Correção |
|---|---|---|
|"o Composer não oferece o interesse `04-technology-science`" |o identificador do chip levava o prefixo do cofre (`composer-topic-topic:04-technology-science`), não a chave do catálogo que o benchmark nomeia |o identificador passou a ser a chave do nó, sem o `topic:` que a receita guarda |
|"o Composer não oferece a região `90_countries/brazil`" |o controle de lugares existia e **não estava montado** — nenhuma tela oferecia a escolha que B01 exige |montado, e agora aceita **mais de um lugar** ("idiomas e lugares" é a resposta que o PRD pede) |
|`Unable to perform work on main run loop: process main thread busy for 30.0s` |a consulta de descoberta rodava na **main actor**: o catálogo embarcado tem **118 MB** e um perfil de primeira execução lê milhares de chaves |medido antes da correção: **2,78 s** para `pt` + `90_countries/brazil` + `01-news-current-affairs`, **2,54 s** para só `pt`, 0,26 s para um único tópico — agora a consulta roda fora da main actor (`Task.detached`), com o resultado ainda cacheado por perfil |

O caminho que o runner percorre está inteiro: o corpus é verificado pelo manifesto, o avaliador pelo seu próprio
hash, o app é construído como um leitor o receberia, o transporte é próprio, e sem veredito o gate sai **NOT_RUN**
(o relatório da rodada registra a identidade dos insumos e a conclusão). A jornada, porém, mudou hoje: o product
owner alinhou B01/B02 ao PRD de F02 — os dois assuntos são declarados **dentro do feed**, não no Composer — então
as rodadas desta noite valem como baseline do app anterior, não como veredito.

### 6. O que está implementado, e o que ainda não está

Implementado e provado nesta rodada: o perfil de descoberta **do leitor** vive nas preferências
(`ReaderSettings.discoveryProfile`, comportamento, nunca identidade), a consulta de descoberta o lê em primeiro
lugar (receita curada e critérios de lente vêm depois), "menos desse assunto" é **exclusão** no pool (e não
remove a fonte que também serve a um assunto pedido), e existe uma página **Preferências de descoberta** nos
ajustes com os mesmos controles da primeira execução — um único conjunto de controles (`ReaderDiscoveryControls`)
serve as duas telas, para que não possam divergir. Não implementado: os convites editoriais dentro do feed, o
voto que os responde, o desfazer, esconder as dicas e a primeira abertura sem o Composer como portão.

### 7. F02 (b) implementado: a primeira abertura entra no feed

A jornada que o benchmark agora exige está no app: **Welcome → idiomas e lugares → feed**, com **nenhuma pergunta
temática antes da descoberta**. O passo da primeira execução usa o mesmo conjunto de controles que os ajustes
(`ReaderDiscoveryControls`, escopo `.firstRun` = idiomas e lugares; `.full` = também profundidade, equilíbrio,
assuntos e tipos de conteúdo), e as respostas viram **preferência** (`settings.discoveryProfile`) — comportamento,
nunca identidade: a sessão é reconstruída e **restaura** a posição do leitor, porque a chave do contexto não muda.

O que a mudança desloca, dito em voz alta:

- `autoName` saiu da tela: a primeira execução **não cria feed nenhum para ativar** e não pede nome. O papel da
  view perdeu o `String`/`Bool` antigos (`onSave(recipe)`).
- **O feed curado (T11) ficou sem porta de entrada na UI.** O Composer era o único criador de presets
  (`saveCuratedFeed` só é chamado por teste hoje), então o "capô do feed curado" só é alcançável quando um preset
  já existe. Não é um detalhe de teste: é uma superfície de produto que a mudança deixou órfã e precisa de decisão
  (uma ação na biblioteca, ou um "criar feed com estas regras" nas preferências).
- O relatório do benchmark ganhou o que a revisão exigiu: **três estados separados** (fontes no conjunto de
  aquisição, fontes efetivamente buscadas, fontes que chegaram aos cards — mais os cards publicados), e o driver
  **registra as fases que caminhou** (`neutral`, `thematic`) num arquivo que o avaliador lê; sem a fase temática,
  as cláusulas de B02 são **NOT_RUN**, nunca PASS, e B01 fica **NOT_RUN** como o revisor determinou.

### 8. F02 (a): o feed se apresenta, e o leitor responde dentro dele

Implementado nesta rodada, com prova executada:

- **Convite editorial no feed** (`FeedEditorialInvitationView`, hospedado pelo app através do parâmetro
  `editorial` do `FeedScreen` — o mesmo padrão do chip de status e da lente): aparece a cada seis cards, **nunca**
  sobre uma fonte que o leitor escolheu (o convite é sobre descoberta, e a descoberta é o que o app fez), e só
  para assuntos que o catálogo nomeia. As ações dizem o que fazem ("Mais desse assunto" / "Menos desse assunto"),
  a consequência está escrita ao lado, e **desfazer** fica onde a pergunta estava. Esconder as dicas é imediato e
  é preferência (`settings.editorialTipsHidden`).
- **O voto é uma preferência, não uma identidade**: `voteOnTopic` grava no perfil de descoberta e reconstrói a
  sessão; como a chave do contexto não muda, a reconstrução **restaura** o que o leitor estava lendo. Provado por
  teste: depois de responder "mais" num assunto, o `editionID` apresentado é **o mesmo** e o conjunto de fontes
  descobertas muda; "menos" é uma exclusão; desfazer remove a resposta (e `neutral` não é um terceiro estado
  guardado — é a ausência dela).
- **A porta do feed curado voltou**, onde o revisor indicou: nas Preferências de descoberta, com nome, criando um
  preset **sem ativá-lo** e sem deslocar a leitura, oferecendo "Abrir feed" depois. A biblioteca continua sendo
  onde os feeds criados se encontram.
- **A primeira execução entra no feed imediatamente**: a capa se fecha antes da consulta ao catálogo (medida em
  segundos), em vez de segurar o leitor numa tela de espera.
- **O runner agora nomeia o perfil** (`TEST_RUNNER_FEEDMINE_BENCH_PROFILE`): sem isso, as duas passagens de B01
  rodariam o mesmo perfil e a cláusula "outro perfil muda as fontes consultadas" seria falsa por construção. O
  perfil B do PRD acrescenta **uma resposta negativa e uma reversão**, que o driver executa pelas superfícies
  reais.

### 9. A regressão que eu mesmo introduzi, e o que o simulador "travado" era

Duas coisas medidas nesta rodada, sem maquiar nenhuma:

1. **O app não estava travado: o driver estava dirigindo ele.** A evidência na tela: conteúdo real (BBC Science,
   BBC World) com os contadores internos avançando (`received=15 completed=15`) enquanto a jornada de aceitação
   percorria o feed. Quem olha o simulador durante uma execução vê um app que não responde a toques porque os
   toques são do teste.
2. **Mas havia um custo real, meu, no caminho:** ao nomear os assuntos, o app abria o catálogo embarcado
   (**118 MB**) **uma vez por chave de nó** — cada abertura é um SQLite novo — e isso rodava **na main actor**, no
   meio da montagem do pool. Foi introduzido na mesma rodada em que consertei a consulta fora da main actor, ou
   seja: o conserto de um caminho deixou o caminho vizinho pior. Corrigido: a resolução de nomes passou para o
   **mesmo passo destacado** da consulta, com **um** leitor e um teto de chaves.
3. **A primeira execução não pode mandar o leitor escolher fontes.** `hasSelectedSources` só olhava a seleção
   persistida: quem acabou de responder idiomas e lugares via, por alguns segundos, a tela de "escolha fontes" —
   conselho que deixou de ser verdade no instante em que a descoberta ganhou um perfil. A superfície agora
   pergunta se a descoberta tem com que trabalhar (seleção **ou** pool **ou** respostas). O banco continua
   intocado: descoberta nunca se escreve na seleção do leitor.

A régua do benchmark também ganhou registro próprio: `bench/REFERENCE.md` diz, em tabela, por que o hash do
avaliador mudou (jornada vigente, três estados, fases caminhadas, perfil nomeado pelo runner) e que o **corpus
não mudou** — os totais medidos continuam valendo.

### 10. O benchmark pegou um defeito que nenhum teste de unidade pegaria

A primeira execução de B01 com a jornada vigente deu números reais e três defeitos — dois do avaliador, **um do
app**:

|O que a execução mostrou|Onde estava|
|---|---|
|perfil A: **zero convites** em 552 s de feed, com 122 fontes no conjunto de aquisição e 98 contribuindo|**app**: os assuntos eram resolvidos por uma fatia de 64 **chaves ordenadas**, e o perfil A é país-escopado — suas fontes vivem em chaves profundas (`90_countries/brazil/religion-spirituality/religion`), que a fatia alfabética deixava de fora. Cobertura por **entrada**, não por fatia, e o assunto oferecido é a colocação mais **rasa** (o leitor recebe "Religion", não o caminho inteiro)|
|perfil B: consultadas **0** fontes|**avaliador**: as duas passagens compartilham um servidor e **um** log; `server-b.log` nunca existiu. A cláusula passou a comparar os **conjuntos de aquisição** (por banco, por construção)|
|as fases caminhadas não apareceram|**avaliador**: `OUT` era **relativo** e o caminho foi entregue a um processo com outro diretório de trabalho — o arquivo de fases nunca era escrito, e "não caminhada" lia igual a "não existe". `OUT` agora é absoluto|

A quarta correção saiu do mesmo exame: o mapeamento carta→fonte era um **acesso ao banco dentro de render**
(custo por quadro e uma consulta que pode falhar em silêncio). Passou a ser um mapa atualizado **quando a janela
muda**.

O que já estava provado nessa execução, medido pelo avaliador: **122 fontes distintas** no conjunto de aquisição
(≥50 ✓), **98** contribuindo com os primeiros 300 cards (≥20 ✓), e nenhuma dependência das quatro fontes padrão ✓.

### 11. F05/F06: a instrumentação que faltava, e o que ela já mostra

O F05 pede, antes de qualquer correção, **instrumentar o percurso existente** — cobertura ao longo das
oportunidades, prontidão por candidato, admissões, avanços do leitor e intervalos sem conteúdo. O app não tinha
onde uma execução pudesse ler isso: agora tem um **traço** (`RunwayTrace`), um objeto JSON por linha, ao lado do
banco do runtime, com teto de linhas. Ele registra:

|Evento|O que afirma|
|---|---|
|`admitted`|o que a tela do leitor ganhou, e quando (cards, edição, sequência, ordem)|
|`advance`|o avanço do leitor, com a atividade e a âncora — o gesto que autoriza apresentação|
|`runway_completed`|uma oportunidade de runway concluída|
|`candidate`|a prontidão de **cada** candidato examinado: `prepared`, `textOnly` ou **`pending`**|

O último é o achado do F06 tornado medível, e eu confirmei no código antes de escrever: `MediaReadiness
.presentation(for:)` responde `.textOnly` quando a imagem ainda não está pronta — pendência vira decisão
editorial. O traço agora separa as três situações, e `isSettled` (o fato de a mídia ter sido **decidida**) passou
a ser público justamente para que o host possa dizer a verdade em vez de adivinhar.

O avaliador passou a ler o traço no B03: conta avanços efetivos, mede a **paralisação visível** com a regra
declarada ("avanço sem admissão em 1 s") e publica a distribuição de prontidão dos candidatos. O corpus e os
limiares não mudaram.

### 12. A prova geométrica: medir a âncora, não "o primeiro card na tela"

A primeira execução limpa de B01 trouxe `hide-stable:false` com `frames 372->264` — 108 pt de deslocamento ao
esconder as dicas. Isso é exatamente o que o revisor avisou que não podia acontecer, então eu fui atrás antes de
tratar como defeito:

- O bloco do convite fica **depois** de cada sexto card. Ao esconder, o que está **abaixo** dele sobe — inevitável
  num feed linear, e **não** é o leitor se movendo.
- A medida, porém, pegava "o primeiro card clicável na tela", que nesse momento era justamente o que estava
  abaixo do bloco removido. A regra certa é a **âncora**: o card do topo, aquele em que o leitor está.

O driver passou a medir a âncora (o card visível com o menor topo dentro do viewport) e o registro de fases diz
qual dos dois fatos ocorreu. A distinção importa: "o conteúdo abaixo se reacomoda" é geometria de lista; "o leitor
foi deslocado" é violação de B04. Medir o segundo quando se quer o primeiro é o tipo de prova que passa a mentir
sozinha.

### 13. O traço derrubou o app — e o que isso ensina

O primeiro B01 com a instrumentação morreu com `SIGABRT` nos dois perfis, ~35 s depois de começar. O relatório
de crash no simulador apontou o culpado em três linhas: `JSONSerialization` → `_writeJSONValue` →
`__cxa_throw`. Ou seja: **`JSONSerialization` levanta exceção Objective-C para valores que não consegue
escrever, e `try?` não pega exceção Objective-C**. O `guard let ... = try? JSONSerialization.data(...)` que eu
escrevi protegia contra erro Swift e não contra exceção — o app abortava em vez de perder uma linha de traço.

Correção: o traço passou a ser `Codable` (`JSONEncoder`, que devolve erro Swift e o `try?` pega como qualquer
outro) com um mapa de campos `[String: String]`. Um valor que não se escreve deixa de ser uma bomba.

Duas lições que ficam escritas:

1. **Instrumentação não pode mudar o comportamento do que se mede.** Um traço que derruba o app é pior do que não
   ter traço, e a falha foi minha, não do código medido.
2. Um `try?` num `JSONSerialization` é um contrato mal lido: em Swift, pegar `Error` não é pegar exceção de
   Objective-C. Quando o valor vem de fora do mundo Swift — ou de um mapa heterogêneo —, o codificador deve ser
   o `JSONEncoder`.

### 14. B01 PASS — e as duas coisas que ele ainda escondia

O B01 fechou **PASS** com todas as cláusulas, e com a prova geométrica na medida certa: `hide-stable:true`,
`frames 130->130` — esconder o convite não move a âncora. Os números separados, como o revisor pediu: **122**
fontes no conjunto de aquisição, **321** efetivamente buscadas, **43** chegando aos cards de **305** publicados.

Mas a execução revelou duas coisas que o gate ainda escondia, e as duas foram corrigidas:

1. **O convite estava num relógio, não no conteúdo.** "Um a cada seis cards" oferecia o mesmo assunto
   repetidamente: no perfil B o driver declarou **um** assunto e nunca encontrou um segundo, porque os convites do
   assunto já respondido voltavam no estado "respondido" e nenhum outro aparecia. A regra agora é onde o feed
   **muda de assunto** (o assunto do card difere do card anterior, e o leitor já leu os primeiros). É o que o PRD
   descreve — convite contextual — e é o que faz a variedade existir por construção, não por sorte de cadência.
   Um assunto respondido **nesta sessão** mantém o bloco (é onde vive o "desfazer"); um respondido antes não é
   perguntado de novo.
2. **O gate lia as fases de um perfil só.** A cláusula da jornada olhava o registro de A; B podia parar na
   primeira resposta e o veredito não mudava. Agora a cláusula exige as duas fases **nos dois perfis** — um
   protocolo que não rodou não pode passar por omissão.

### 15. O traço resolveu o mistério: o app oferecia, o driver passava por cima

O B01 voltou a mostrar a fase temática sem respostas, e agora havia o traço para explicar. Os números, do próprio
app:

|Fato no traço|Valor|
|---|---|
|convites **oferecidos**|**37.925**|
|convites recusados por já respondidos|0|
|cards sem assunto no catálogo|822|
|assuntos distintos oferecidos|economia, política, livros, interesses gerais, videogames, …|

Ou seja: a superfície estava funcionando, e o driver — que procura por botões `feed-invitation-more-*` — não
achava nenhum. A causa não estava no app: o driver andava **uma tela inteira por swipe**, e um convite que fica
*entre* duas telas nunca aparece em nenhuma consulta. A medida é que estava errada — e é a terceira vez nesta
rodada que o defeito era meu, não do que eu estava medindo.

Duas correções:

1. **Driver:** a busca passa a andar **meia tela** por vez (`swipeUp(velocity: .slow)`), então um convite entre
   duas telas ainda aparece numa das consultas.
2. **App (produto, não medida):** convites passam a ser ocasionais de verdade — a cada mudança de assunto, com um
   **mínimo de quatro cards** desde o último. Sem esse teto, a regra "onde o feed muda de assunto" oferecia um
   convite a cada card de assunto diferente, o que o PRD recusa ("convites ocasionais", nunca em cima da leitura).

Registrado também o que o revisor pediu para não se perder: a **execução defeituosa do runner fica preservada**
(ela não aprova B01, e o conserto do avaliador vai em versão nova com hash, em `bench/REFERENCE.md`). Corpus,
critérios e limiares não foram alterados em nenhum momento — o que mudou no avaliador foram *medições novas* das
fases, dos três estados e da prontidão, não a régua.

### 16. Instrumentação dentro do render: o defeito que fez o driver expirar

A caçada ao convite que "não aparecia" terminou em dois defeitos **meus**, ambos na instrumentação, ambos no
caminho mais sensível do app:

1. **Codificar dentro do corpo da view.** Para saber por que o driver não achava convite, eu gravei cada decisão
   no traço — e a decisão é tomada enquanto o feed é desenhado. O app ofereceu 37.925 convites numa execução, e
   cada oferta passou por `JSONEncoder` **na thread que desenha**, mesmo quando o teto do arquivo já tinha sido
   atingido (o teto era verificado *depois* de codificar). Resultado: "Timed out while evaluating UI query" — o
   app parecia travado. Correção: o teto é conferido **antes** de codificar, e a instrumentação de decisão saiu do
   corpo da view (ela já tinha servido: provou os 37.925 convites).
2. **Escrever `@State` dentro do corpo da view.** A cadência ("pelo menos quatro cards desde o último convite")
   era um `@State` que eu atribuía durante o desenho — comportamento indefinido em SwiftUI, e candidato direto ao
   mesmo churn. Agora é uma caixa (tipo de referência) que não invalida a view.

A lição, escrita uma segunda vez porque eu a repeti: **instrumentação não pode entrar no caminho que ela mede.**
A primeira vez foi I/O síncrono na main actor; agora foi codificação por render e mutação de estado no corpo. As
três eram minhas, e nenhuma estava no código que eu estava auditando.

### 17. Cadência por índice dentro de um corpo de view: o convite que nunca aparecia

Depois de tirar a instrumentação do render, os cards voltaram (83 fontes contribuindo) — e a árvore de
acessibilidade, agora impressa quando a busca falha, mostrou o que nenhuma inferência mostrava: **zero elementos
`feed-invitation`, e doze `card.bookmark`**. O app *dizia* que oferecia e o feed não tinha nenhum.

A causa era a cadência: eu guardava "o índice do último convite" e exigia quatro cards de distância. Um corpo de
view pode ser avaliado **em qualquer ordem** — e avaliado mais de uma vez — então o índice "último" pulava para o
fim e suprimia praticamente todos os convites. Troquei por uma regra que não depende de ordem: **um convite por
assunto por sessão**. É ocasional por construção, e é o que o PRD quer.

A lição vale para qualquer superfície: **estado de decisão que vive dentro do render precisa ser independente da
ordem das chamadas.** Índice não é; conjunto de assuntos é.

### 18. A causa raiz: o app semeava uma seleção que o leitor nunca escolheu

O traço fechou o caso em uma linha. Eu gravei, a cada mudança de janela, os fatos de que o convite depende:

```
{'cards': '17', 'resolved_sources': '17', 'with_subject': '0', 'known_subjects': '120'}
```

Cento e vinte assuntos conhecidos, dezessete cards com fonte resolvida, **zero** cards cujo assunto o feed pudesse
perguntar. As fontes dos cards não estavam no conjunto descoberto — e a razão estava no arranque: em build de
desenvolvimento sem o interruptor de feeds locais, `TrustedFeed.catalogOrDevelopment(limit: 64)` fazia o app adotar
**as 64 primeiras entradas do catálogo como a seleção do leitor**. Não é um detalhe de teste: é exatamente o que o
benchmark chama de falha típica — *"o app exibe cards bonitos mas consulta somente a lista estática de quatro
feeds"* — e contraria F02, onde o leitor entra no feed sem escolher fonte nenhuma.

Correção: `AppComposition` começa **sem seleção** (`feeds: []`). O catálogo é o que a descoberta lê (F01); não é
lista deassinatura. Com seleção vazia, a superfície do feed passa a existir quando a descoberta tem com que
trabalhar (o conserto de `hasSelectedSources` desta mesma rodada) e os cards passam a vir de fontes que o app
procurou — que é o que faz um convite editorial ter sentido.

O interruptor `FEEDMINE_USE_DEVELOPMENT_FEEDS` continua para os testes de UI que precisam dos quatro feeds locais,
e `TrustedFeed.catalog(limit:)` continua existindo para quem quer ler o catálogo por conta própria.

### 19. O defeito que ficou registrado: com seleção vazia, o app não publica nada

Tentei a correção que o F02/B01 pedem — **uma instalação limpa sem seleção inicial** — e a medi. O resultado foi
inequívoco e ruim:

|Medida (execução `bench/run/20261011T021645Z`)|Valor|
|---|---|
|fontes registradas no conjunto de aquisição|**0**|
|cards publicados|**0**|
|eventos no traço do app|**0**|
|estado da tela que o driver encontrou|**nenhuma `ScrollView`** em 180 s|

Ou seja: hoje a descoberta **só registra o seu pool junto de uma seleção não vazia** — o app que o leitor recebe
na primeira execução é alimentado pelas primeiras entradas do catálogo, não pela descoberta. Isso é exatamente a
falha típica que B01 nomeia ("o app exibe cards bonitos mas consulta somente a lista estática de quatro feeds") e
contradiz F02 (o leitor entra no feed sem escolher fonte).

A correção foi **revertida** para não deixar a árvore pior do que estava: um app que não publica nada é uma
regressão, não um progresso. O achado fica registrado com as medidas acima, e a direção certa é conhecida —
remover a seleção inicial **junto** com o conserto da descoberta, provando os dois com o mesmo teste: sem seleção,
o pool registra e o feed publica; com o leitor escolhendo, nada muda.

**Próxima tarefa, com o critério de aceitação escrito acima:** fazer a descoberta registrar e alimentar o feed
quando a seleção é vazia, e então remover o default.

### 20. A causa da causa: seleção vazia era tratada como falha fatal

O §19 registrou o sintoma (com seleção vazia: 0 registradas, 0 publicados). Um teste de composição que reproduz a
condição em três segundos encontrou a causa em duas linhas:

```swift
if feeds.isEmpty { startupFailure = "Não foi possível carregar o catálogo local de fontes." }
else { /* toda a ligação do app: banco, preferências, sessão */ }
```

Um leitor que não escolheu fonte era indistinguível de um catálogo ausente — e, pior, a seleção vazia **pulava
toda a inicialização**. O app não publicava porque não existia sessão.

Correção: a falha fica reservada ao que ela nomeia — **catálogo ilegível** (`Bundle.main.url(...) == nil`) — e a
seleção vazia segue o caminho normal, com o feed alimentado pela descoberta e, quando não houver com que trabalhar,
a superfície de fontes vazias dizendo exatamente isso.

Provado por `CompositionTests.testDiscoveryFeedsAReaderWhoChoseNothing`, que é agora o critério de aceitação desta
correção: leitor sem seleção, respostas de idioma e lugar, **≥50 fontes descobertas**, superfície de feed
disponível e **publicação real**. Com ele passando, o default de seleção inicial foi removido: instalação limpa
começa sem nada escolhido, que é o que F02 e B01 pedem.

### 21. O card passou a dizer de que fonte veio

A última medida apontou o que faltava: com o feed alimentado pela descoberta, **772 de 772 cards** tinham assunto
resolvido — e ainda assim a árvore de acessibilidade não continha nenhum convite. O convite não era oferecido
porque a decisão de render consultava um mapa (`cardSources`) que era preenchido por uma `task` de janela — e um
mapa que pode estar vazio é uma decisão que pode não acontecer, sem que nada diga por quê. Pior: preenchê-lo
custava uma leitura de banco por card.

A correção tira o intermediário: **o próprio `PresentationCard` carrega o `sourceID`** que a publicação congelou
(`publishedCard.origin.sourceID`). A superfície que quer falar *sobre a fonte que o leitor está lendo* — o convite
de F02 — passa a perguntar ao card, e não ao banco. Sem mapa, sem task, sem corrida: a decisão depende só do valor
que está na frente dela.

Isso também fecha uma pendência antiga do convite: o `with_subject` medido no traço (772/772) e a decisão de
render passam a olhar exatamente a mesma coisa.

### 22. Revisão arquitetural do Codex para F06-A (aceita)

Pedi ao Codex (janela aberta, projeto `Feedmine V2`, revisão somente-leitura) o desenho mínimo para F06-A. Ele
respondeu em 41 s, com arquivo e função. O desenho, tal como aceito:

1. **Prontidão é um fato atômico.** A leitura do estado de prontidão de uma revisão deve ser atômica sob o mesmo
   lock; o deadline de `prefetch` encerra a espera do chamador — **não autoriza degradação**. `MediaPrefetcher.prepare`
   já conserva pendências transitórias e trabalho em voo; é daí que o fato deve sair, não de um segundo mecanismo.
2. **A suspensão entra em `LocalProductionSlice.run`**, entre obter os candidatos/exposição e `SelectionEngine.select`:
   tirar um retrato de prontidão para a janela examinada e permitir à seleção apenas candidatos com apresentação
   legítima. A forma mais limpa é **passar os fatos de prontidão como entrada da seleção**, mantendo a janela
   estrutural original; em `SelectionEngine`, a restrição entra **antes de ordenar** e antes de `SourceAlternation`.
   Editorial continua dono único da ordem; Runtime/Media decide se existe apresentação.
   **Não apagar registros, não marcar exposição, não reservar `PublicationCardID`, posição ou ordinal para os
   suspensos** — é isso que garante que o pendente volta a concorrer em igualdade quando houver apresentação.
3. **`AppComposition.prepare` monta somente a seleção pronta**, preservando o alinhamento candidato → input → ID
   exigido por `PublicationPreparation.drafts`; a decisão de apresentação usada na preparação tem de ser a **mesma**
   do retrato que autorizou a seleção — pendência não pode reaparecer como fallback silencioso.
4. **Se nenhum candidato pronto puder ser colocado, o resultado é `advancedWithoutPublication` com progresso
   estrutural válido** — sucesso de exame, não falha de publicação.

A prova mínima (F06-A) que o Codex e o product owner concordam em exigir: o **primeiro candidato nunca prontifica**
e todos os seguintes prontos avançam, sem bloquear fila nem reservar ordinal; quando a mídia do primeiro chega, ele
**volta a concorrer na seleção futura**, sem alterar os cards anteriores.

### 23. Codex revisou o F02 e achou seis defeitos reais (todos no meu código)

A revisão foi pedida em paralelo (projeto `Feedmine V2`, somente-leitura). Ela não elogiou: enumerou o que estava
errado, com arquivo e função. Concordo com todos e ficam como tarefa:

1. **O bloco da resposta pode desaparecer.** `cadence.offered` guarda o assunto oferecido e a avalição seguinte
   devolve `nil` para ele — ou seja, depois de responder, o bloco que contém **"Desfazer"** deixa de ser renderizado.
   O certo é um **vínculo estável assunto → card anfitrião**: o render consulta essa decisão, não a recalcula.
2. **"Descoberto" não exclui "escolhido pelo leitor".** `discoverySubjects` acumula por `merge` e
   `editorialSubject(for:)` consulta só esse mapa: uma fonte que o leitor escolheu — ou que a descoberta achou sob
   um **perfil anterior** — pode receber convite. Falta validar a proveniência válida para a associação atual e a
   precedência da escolha explícita.
3. **Respostas rápidas podem se perder.** `voteOnTopic` grava e aguarda `replaceSession`, que **retorna imediato**
   quando `replacingSession` já está ativo: a segunda resposta fica persistida sem integrar a associação que está
   sendo construída. A reconstrução precisa reler a versão mais recente e reconciliar.
4. **Falhas ficam invisíveis.** `try?` no salvamento e na reconstrução permite a UI mostrar um voto que não foi
   persistido ou aplicado. O resultado tem de ser observável; desfazer tem de refletir o resultado real.
5. **Assunto da fonte não prova assunto do artigo.** `subjects(in:)` escolhe a colocação mais **rasa** do catálogo
   (país, categoria ampla). O convite precisa formular essa associação honestamente, sem afirmar que a matéria é
   sobre aquele tema.
6. **120 fontes continuam sendo teto do pool.** `discoverySourceLimit` + cache por perfil, sem paginação
   progressiva, deixam a promessa de exploração contínua (PD-8) em aberto.

O Codex também completou o desenho de F06-A com um caminho que eu não tinha listado: **`InitialProductionSlice` e
`ColdFeedBootstrap`** — o filtro de prontidão precisa valer **também na primeira edição**, e `InitialProductionSlice.run`
consulta sempre `after: nil`, então uma primeira janela inteiramente pendente pode impedir que candidatos prontos
depois dela sejam alcançados. A correção mínima completa passa a permitir continuar o exame inicial **pelo cursor
devolvido**, sem reservar edição publicada nem posição.

### 24. F06-A implementado — em dois lados, em paralelo

O Codex implementou o desenho dele no Runtime e eu fechei a parte 3 (a composição), com escopo separado e sem
colisão. O que ficou:

**Lado Runtime/Editorial (Codex):**
- `MediaReadiness.presentation(for:)` passou a devolver **opcional**: `nil` é *não pronta* (suspensa), `.textOnly`
  só quando a decisão foi tomada sem imagem utilizável. Nada de impaciência virando decisão editorial.
- `MediaReadiness.presentations(for:)` — **um retrato atômico** para a oportunidade de publicação, sob o mesmo lock.
- `LocalProductionSlice` recebe o índice (`init(database:readiness:)`), monta um `SelectionReadinessSnapshot` e
  **exige cobertura** (`readinessCoverageMismatch` se o retrato não cobrir o que foi pedido — falha alta em vez de
  candidato suspenso passando como pronto).
- `SelectionEngine.select(..., readiness:)` — os fatos entram **antes de ordenar** e antes de `SourceAlternation`.

**Lado host (eu):**
- `FeedRunwayDriver` recebe o **mesmo** índice e o repassa ao slice (a nota do Codex: dois pontos de vista sobre o
  que está pronto é como um suspenso vira card de texto).
- `AppComposition.prepare` lê o retrato **uma vez** e publica **apenas a seleção pronta**, gerando `cardIDs` na
  mesma proporção — nada de `PublicationCardID`, ordinal ou posição reservados para quem está suspenso.

**Prova:** `swift test --filter FeedMineRuntimeTests` → **124 testes, 0 falhas**, incluindo o caso novo de F06-A.

### 25. O convite não existe para a tecnologia assistiva — e é isso que trava B01

Depois de calibrar o toque (duas tentativas de coordenada), o resultado não mudou: **as respostas guardadas do
leitor continuam vazias** e a árvore de acessibilidade, impressa pelo próprio driver quando a busca falha, **não
tem um único elemento do bloco**. Não é o driver: é o **produto**.

O bloco do convite usa `.accessibilityElement(children: .contain)` com um identificador no contêiner, e o efeito
medido é que os botões *dentro* dele não aparecem para quem consulta a árvore — o que significa que **um leitor
com VoiceOver não consegue responder ao convite**. A correção certa não é ensinar o driver a tocar em coordenadas
(era o que eu estava fazendo): é **a superfície expor suas ações** como elementos de verdade, com rótulo e
consequência. Isso satisfaz F17, satisfaz o próprio benchmark e devolve ao B01 a fase que ficou presa.

Próxima tarefa nesta frente, com critério: os dois botões do convite existem na árvore com identificador e rótulo,
e o driver responde pelas ações — nunca por adivinhação de pixel.

### 26. Julgamento e voz: o veredito do B01 e a redação honesta do convite

Pedidos ao revisor de produto (thread separada, somente-leitura). Ele julgou **B01 = NOT_RUN** na execução
`20261011T022258Z` — e foi além do que eu perguntei: "**4 fontes nos primeiros 300 cards, contra o mínimo de 20,
é FAIL nessa cláusula**. O agregador dá precedência a uma cláusula falsa sobre uma ausente: essa execução
posterior pode ser FAIL **mesmo com a jornada NOT_RUN**. Não se deve retroagir esse resultado para a execução
anterior." Ou seja: **a fome causada pelo F06-A é um FAIL de produto**, e corrigi-la é obrigatório — não basta
deixar a jornada como NOT_RUN. E: "correção implementada não é PASS; somente uma nova execução que demonstre os
critérios pode sustentá-lo".

E deu a **redação final** do convite, porque o assunto oferecido é como o *catálogo arquiva a fonte*, não o tema da
matéria:

- Título: **"FeedMine sugere"**
- Pergunta: **"No nosso catálogo, esta fonte está em {assunto}. Quer explorar mais fontes desse grupo?"**
- Botões: **"Mais de {assunto}"** / **"Menos de {assunto}"**
- Consequência: **"Sua resposta orienta a busca por mais ou menos fontes desse grupo nas próximas descobertas. Você
  pode mudar de ideia."**

Aplicado na tela. A redação atribui a classificação ao FeedMine, diz o que a resposta altera e não afirma que a
matéria trata daquele assunto — exatamente o furo que o Codex apontou.

### 27. A correção da fome, do Codex, e o que ela move

O Codex implementou a continuação do exame inicial (o caminho que ele mesmo apontou): **112 linhas** em
`ColdFeedBootstrap.swift` (+96), `InitialProductionSlice.swift` (+34) e `LocalProductionSlice.swift` (+19). A
suíte de runtime foi de 124 para **126 testes, 0 falhas** — ele acrescentou as duas provas da fome.

O que a correção significa, em produto: com o F06-A, um candidato sem apresentação legítima **sai da fila pronta**
— certo — mas o exame não podia ficar preso na cabeça pendente, senão o feed **passava fome**: medido, as fontes
contribuintes caíram de ~80 para **4**, e o revisor de produto classificou isso como **FAIL da cláusula ≥20**
(mesmo com a jornada NOT_RUN). A correção permite continuar o exame pelo cursor devolvido, sem reservar edição
publicada nem posição — ou seja, o pendente sai do caminho crítico **e** os prontos atrás dele são alcançados.

### 28. Fechando dois achados do Codex no F02

**Achado 3 — a segunda resposta rápida se perdia.** `replaceSession()` retornava cedo quando já havia reconstrução em
voo: a resposta ficava **persistida sem ser aplicada**. Agora a reconstrução em andamento é **repetida** ao terminar
(`pendingRebuild`), relendo as preferências — o que o leitor respondeu é o que a sessão lê, não o que as
preferências continham quando a reconstrução começou.

**Achado 4 — a falha ficava invisível.** `try?` no salvamento e na reconstrução permitia à tela mostrar uma resposta
que nunca foi persistida ou aplicada. Agora `voteOnTopic` devolve se a resposta está **de fato** em vigor, registra
`answer_failed` com o estágio (`persist`/`apply`) ou `answer_applied` no traço, e a superfície **retira a resposta
mostrada** quando ela não foi aplicada. O leitor vê o que o app realmente tem.

Ficam abertos, do mesmo review, dois itens: **o teto de 120 fontes do pool** (paginação progressiva — PD-8/F01/F05) e
a validação de que o assunto do convite não vira afirmação sobre a matéria (feito na redação, pelo revisor de
produto).

### 29. O convite responde — e o que faltava era o meu filtro

A execução `20261011T042201Z` fechou a fase temática **do lado do app**: o driver tocou
`feed-invitation-more-90_countries/brazil/health-wellness/mental-health` — pelo **elemento de acessibilidade**, não por
coordenada — e as preferências guardadas do leitor provam o resto:

```
{"topic:90_countries/brazil/health-wellness/mental-health":"more","topic:90_countries/brazil":"more"}
```

Ou seja: o conserto de acessibilidade (o bloco deixar de declarar-se um elemento e passar a expor as suas ações)
**funcionou de ponta a ponta** — o mesmo caminho que um leitor com VoiceOver usa. O que ainda dizia "nenhum assunto
declarado" era o **meu oráculo**: ele excluía qualquer nó **sob** o lugar respondido na primeira execução
(`node.startswith(place + "/")`), e todos os assuntos do perfil A vivem sob `90_countries/brazil`. O filtro passou a
excluir **apenas o lugar exato** — um nó mais profundo é uma resposta dada no feed, não a resposta do primeiro passo.

O driver também deixou de adivinhar pixel: a segunda resposta é buscada **por ação**, andando telas até vinte vezes
antes de desistir — e desistir é registrar, não travar. A cláusula da jornada agora é julgada pelo oráculo a partir
das respostas guardadas, com as fases apenas como trilha.

### 30. B01: a jornada fecha e a fome some — uma passagem limpa de perfil A

Execução `20261011T042536Z`, perfil A, corpus e limiares congelados:

|Cláusula|Medido|Veredito|
|---|---|---|
|jornada vigente nas duas fases|fase neutra + **duas respostas dentro do feed** (lidas das preferências do leitor)|**PASS**|
|não depende das quatro fontes padrão|nenhuma das 4 contribui|PASS|
|≥50 fontes distintas no conjunto de aquisição|120|PASS|
|≥20 fontes distintas nos primeiros 300 cards|**47** (era 4 com a fome)|PASS|
|outro perfil muda o conjunto|segunda passagem não executada nesta rodada|NOT_RUN|

**Três coisas ficaram provadas juntas:** o app alimenta um leitor que não escolheu fonte nenhuma (descoberta), o
convite é respondido **pela ação acessível** e a resposta é persistida, e a correção de continuação do exame
(Codex) tira o pendente do caminho crítico **sem** matar a reposição: 47 fontes distintas contribuindo, contra 4
quando o exame ficava preso na cabeça.

Falta a segunda passagem (perfil B) para o veredito completo — e o B03 de 30 minutos, onde a fome, se existir,
aparece como paralisação mensurável.

### 31. B01 — PASS, com as cinco cláusulas, nos dois perfis

Execução `20261011T042958Z`, corpus e limiares congelados, jornada vigente:

|Cláusula|Medido|Veredito|
|---|---|---|
|jornada vigente nas duas fases, nos dois perfis|fase neutra + **duas respostas dentro do feed** (`health-wellness/mental-health`, `news-current-affairs/world-news`), lidas das preferências do leitor|**PASS**|
|não depende das quatro fontes padrão|nenhuma das 4 contribui|PASS|
|≥50 fontes no conjunto de aquisição|120|PASS|
|≥20 fontes nos primeiros 300 cards|**47**|PASS|
|outro perfil muda o conjunto|A 120 × B 178, **zero** em comum|PASS|

**Veredito: PASS.** É a primeira passagem completa do B01 sob a jornada que o product owner fixou em 2026-10-10 —
e ela sustenta três fatos que hoje estão no app: uma instalação sem seleção recebe feed pela descoberta (F01/F02),
o convite é respondido **pela ação acessível** e a resposta vira preferência sem mover a leitura, e a suspensão de
pendentes (F06-A) não mata a reposição quando o exame avança pelo cursor.

### 32. B03 — PASS, trinta minutos de runway com o traço aberto

Execução `bench/run/20261011T043906Z`, perfil A, corpus e limiares congelados, `--full-trace`:

|Cláusula|Medido|Veredito|
|---|---|---|
|trinta minutos de avanço com oferta suficiente|**7.558 avanços efetivos** (mínimo 1.800)|PASS|
|zero repetição para disfarçar falta de oferta|0|PASS|
|zero pares consecutivos da mesma fonte no trace inteiro|0|PASS|
|**zero paralisação visível ≥1 s por falta de runway**|**0 paradas** (regra declarada: avanço sem admissão em 1 s)|PASS|
|prontidão de cada candidato registrada|**871 candidatos — 871 `preparados`, 0 pendentes, 0 texto**|PASS|

O traço da execução, aberto: 7.558 `advance`, 7.565 `admitted`, 7.558 `runway_completed`, 871 `candidate`, 3.362
estados de janela — e **2 `answer_applied`**, as respostas do leitor aplicadas durante o próprio trace.

**Distinção que o revisor exigiu, mantida:** o que está acima é **falha observada** — e aqui ela é *zero*: nenhuma
parada, nenhuma repetição, nenhuma adjacência. O **diagnóstico** de qualquer parada futura teria de vir do traço,
não da minha opinião; o traço agora registra **transições** (mídia que fica pronta, uma vez por revisão) e
**suspensões com motivo**, o que permite separar "faltou apresentação legítima" de "faltou oferta".

Um defeito **meu** foi encontrado ao ler o resultado: o oráculo lia a prontidão na chave errada do evento e fazia
871 candidatos parecerem uma distribuição de zeros. Corrigido e re-julgado sobre a **mesma** execução — os 871
`preparados` são agora o que o traço sempre dizia.

### 33. B04 — o defeito que o revisor previu: esconder o convite movia a âncora

O revisor de produto foi explícito antes de eu medir: "a remoção explícita do convite precisa **preservar a
âncora**". O B02 mediu exatamente a violação: `hide-stable:false`, `hide-frames:302->174` — **128 pt** de
deslocamento quando as dicas são escondidas, porque as linhas que saem do feed estão **acima** da âncora e tudo
abaixo sobe.

Correção: a superfície que remove linhas **devolve o leitor ao lugar**. O `FeedScreenStore` passou a guardar a
âncora do último viewport entregue (`lastAnchor` — o mesmo `ViewportObservation.anchor.cardID` que o runtime já
usa), o `FeedScreen` ganhou um `ScrollViewReader` com `anchorToRestore`, e o host, ao esconder as dicas, nomeia a
âncora. Não é compensar altura nem pintar espaço vazio: é dizer onde o leitor estava.

O protocolo de **B04** também passou a existir como gate: o driver mede a âncora e a ordem admitida antes e depois
de responder, desfazer e esconder um convite, depois de 12 s de ócio com o leitor parado (imagem tardia), e depois
de rotação e de background/retorno; o oráculo julga **as medidas**, nunca a opinião do driver — e sem medição o
gate é NOT_RUN.

### 34. B04 — PASS: o feed apresentado sobrevive ao que o leitor não pediu

Execução `bench/run/20261011T053723Z`, perfil A, corpus e limiares congelados, gate **B04** (novo):

|Cláusula|Medido|Veredito|
|---|---|---|
|o protocolo de B04 foi caminhado|âncora, convite, ócio, rotação e background medidos e registrados|PASS|
|**nada do que o leitor já tinha se moveu, reordenou ou retratou**|`idle-stable: **true**` (imagem tardia com o leitor parado) · `rotation-holds: **true**` (contadores do próprio app inalterados pela rotação) · `background-holds: **true**` (volta do background no mesmo lugar) · **0 falhas**|**PASS**|

A rotação é medida como este projeto já a provava (T12): pelos **contadores de viewport que o app publica**, não
pela identidade do card no topo — uma re-layout legítima muda o que cabe na tela, e exigir o mesmo card no topo
seria medir a coisa errada (foi o que a primeira versão da minha asserção fazia).

Com isso, os três gates que o revisor de produto priorizou estão com evidência: **B01 PASS, B03 PASS, B04 PASS**.
Falta **B02** (relevância/variedade sobre 200 cards, com a passagem B agora corrigida para dar a resposta negativa
*enquanto o convite a oferece*), **B05** e o registro de **B06** sem aparelho físico.

### 35. B02 — PASS: relevância, variedade e identidade editorial

Execução `bench/run/20261011T060053Z` (perfis A e B), corpus e limiares congelados. Julgado sobre **as respostas
guardadas** do leitor, como o B01 — não sobre um nome de fase no registro:

|Cláusula|Medido|Veredito|
|---|---|---|
|≥80% dos 200 cards correspondem ao perfil|**200 de 200**|PASS|
|≥20 fontes distintas|**66**|PASS|
|nenhuma fonte >15%|**4,5%**|PASS|
|zero pares consecutivos da mesma fonte|0|PASS|
|zero duplicatas de artigo canônico|0|PASS|

As duas passagens fecharam a fase temática (A: saúde mental e world-news; B: software-computing e earth-life-sciences),
e o perfil B registrou `negative:not-offered` — a resposta negativa do PRD **não foi oferecida** depois de duas
respostas positivas. Fica registrado como fato, não como falha: o protocolo de F02 prevê os votos, e o benchmark não
exige a negativa em B02.

### 36. A âncora ao esconder: `302->302`

Três tentativas, a terceira certa. As duas primeiras tentaram **restaurar** a posição depois de remover as linhas
(`ScrollViewReader` e depois `scrollPosition`) e nenhuma segurou: o card ancorado continuou se deslocando 128 pt nas
medições (`302->174`). A terceira mudou a abordagem — **ocultar sem remover**: o bloco do convite continua ocupando o
seu lugar, invisível e sem receber toque (`.opacity(0).allowsHitTesting(false)`), e a decisão de *quem* recebe um
convite passou a ser independente de as dicas estarem visíveis. A geometria não é restaurada porque **nunca muda**.

Medido na execução `bench/run/20261011T061901Z`: `hide-stable:true`, **`hide-frames:302->302`** — deslocamento zero.
E a restauração por rolagem foi **removida**, junto com o `lastAnchor` do store: dois mecanismos para o mesmo
problema é como se fica com nenhum.

Lição de desenho: quando uma superfície muda o *conteúdo* acima do leitor, a resposta certa é não mudar a
**geometria** — não é reagir depois medindo quanto se deslocou.

### 37. B05 — PASS: nada se perde em silêncio

Execução `bench/run/20261011T062326Z`, perfil A, corpus e limiares congelados, gate **B05** (novo):

|Medida registrada pelo driver|Valor|
|---|---|
|a história salva sobrevive|`b05-saved: true`|
|A → B (outro contexto) alcançado|`b05-context-b-reached: true`|
|**volta a A preserva a âncora**|`b05-return-preserves-anchor: true`|
|**reabrir o app preserva a âncora**|`b05-reopen-preserves-anchor: true`|
|reabrir mantém a história salva|`b05-reopen-keeps-saved: true`|
|**rede cortada ainda mostra história local**|`b05-offline-shows-local: true` · `b05-offline-cards: true`|
|falhas|**0**|

O corte de rede é **real**: a segunda abertura roda com `FEEDMINE_BLOCK_RSS_NETWORK=1`, a configuração de falha de
transporte do próprio app — **sem conector falso**. O oráculo julga as medidas do driver e exige que todas sejam
verdadeiras; sem medição, o gate é NOT_RUN.

### 38. O quadro dos gates, medido

|Gate|Veredito|Execução|
|---|---|---|
|B01 — descoberta sem assinatura|**PASS** (5 cláusulas, A e B)|`20261011T042958Z`|
|B02 — relevância, variedade, identidade|**PASS** (200/200, 66 fontes, 4,5% máx.)|`20261011T060053Z`|
|B03 — runway de 30 minutos|**PASS** (7.558 avanços, 0 paradas)|`20261011T043906Z`|
|B04 — o feed apresentado é sagrado|**PASS** (idle, rotação, background, 0 falhas)|`20261011T053723Z`|
|B05 — A→B→A, reabertura, offline, salvos|**PASS** (8 medidas, 0 falhas)|`20261011T062326Z`|
|B06 — escala no aparelho físico|**NOT_RUN** — sem dispositivo; não bloqueia os outros nem vira PASS por omissão|—|

### 39. B03 pegou um crash meu — a mesma armadilha de ObjC, repetida

O B03 rodou com a paginação do Codex no código e **falhou em 333 avanços** (mínimo 1.800). O gate estava certo: o
teste morreu aos 193 s, em pleno loop de trinta minutos, e o relatório de crash do simulador apontou
`_NSFileHandleRaiseOperationExceptionWhileReading` → `-[NSConcreteFileHandle writeData:]` → `objc_exception_throw`.

É o **meu traço**, e é a **mesma classe de defeito** que eu já tinha consertado hoje com `JSONSerialization`:
`NSFileHandle.write` **levanta exceção Objective-C** quando o handle não é utilizável, e `try?` não pega exceção
Objective-C. A versão anterior abria e fechava um handle **por lote** — e o handle de um lote não servia para o
seguinte, derrubando o app no meio de um trace de trinta minutos.

Correção: **um handle só**, criado na fila serial do traço, usado ali e **nunca fechado** até o processo terminar.
Um handle que não é fechado não cai nessa armadilha.

O que fica medido: o benchmark não valida só o app — ele derrubou o meu instrumento, exatamente onde o instrumento
atrapalha o que mede. É a terceira vez nesta rodada que a instrumentação foi o defeito (I/O na main actor,
codificação por render, e agora o handle por lote). A regra que eu devia ter escrito na primeira vez e escrevo
agora, com três exemplos: **nenhuma API que levanta exceção Objective-C entra num caminho de instrumentação.**

### 40. O gate falhou por falta de disco, não de conteúdo — e o meu conserto anterior era o do lugar errado

O B03 com o handle único morreu de novo, agora aos 228 s, com o **mesmo** símbolo:
`specialized closure #1 in RunwayTrace.write(_:)` → `-[NSConcreteFileHandle writeData:]` →
`_NSFileHandleRaiseOperationExceptionWhileReading`. A diferença é que desta vez o relatório de crash dizia mais, e o
`df` disse o resto: **464 MB livres**. O volume do host estava cheio.

A cadeia inteira, medida:

1. Duas corridas anteriores deixaram seus bundles `xcresult` em `bench/run/*/derived` (1,7 GB + 963 MB). O
   `bench/run.sh` já apaga o `derived/` no fim de cada corrida — mas aqueles dois diretórios eram anteriores a esse
   conserto, então o resíduo ficou.
2. Com o volume quase cheio, a escrita do traço falhou com **ENOSPC**, e `NSFileHandle.write` **levanta exceção
   Objective-C** em erro de syscall — `try?` não pega.
3. O app abortou no meio do trace; o teste viu `com.feedmine.development is not running`; o oráculo leu 397 avanços
   e o gate saiu **FAIL por falta de disco**.

Três correções, cada uma na sua camada:

|onde|o quê|
|---|---|
|`RunwayTrace.write`|`handle.write(contentsOf:)` e `seekToEnd()` — os métodos que **lançam erro Swift** em vez de exceção ObjC. Evidência pode perder uma linha; o feed não pode morrer por causa dela.|
|`DiscoveryBenchmarkTests.record`|idem: o driver do teste escrevia com a mesma API que levanta exceção — um disco cheio derrubaria o runner inteiro em vez de perder uma linha de fase.|
|`bench/run.sh` §1c|**preflight de disco**: recusa a corrida abaixo de 3 GB livres, com o motivo medido escrito no script. Um gate não pode julgar o feed quando o juiz está sem espaço.|

O `bench/EVALUATOR.sha256` foi **regenerado** — e vale registrar que ele fez o trabalho dele: a corrida seguinte foi
**REFUSED** (*"the evaluator's own files changed"*) porque eu havia editado o driver congelado. Um avaliador que
recusa a própria edição do avaliador é o comportamento certo.

Nota honesta sobre o conserto anterior (§39): eu tratei o handle único como causa quando ele era só o mensageiro. O
handle único era uma melhora real (sem corrida entre abrir/fechar), mas **não** removia a exceção — só a API que
lança remove. A lição fica mais afiada: *"não usar API que levanta exceção ObjC"* não é conselho de estilo; é a
diferença entre perder uma linha de evidência e perder a corrida.

### 41. `mediaWait` deixa de ser fração do timeout e passa a ser derivada (§5.3 / PD-6)

O F05 §5.3 pede limites **por operação**, tirados de fatos já medidos. O host tinha:

```swift
let mediaWait = configuration.timeoutIntervalForRequest / 4   // ~15 s, sem relação com o runway
```

Os três usos (`maintainTail`, `prepareRunwayMedia`, `prepareMedia`) passaram a chamar
`FeedAssociation.mediaWaitSeconds(p95Replenishment:inputs:transportCeiling:)`, que é função **pura** (por isso
testável) e usa exatamente o mesmo fato de que a reserva é feita:

- medido: `p95 × safetyFactor + releaseMarginSeconds` — a p95 do *reabastecimento* é a latência medida por host
  (PD-6 lista "measured throughput and latency per host" entre os insumos), e o fator/margem já são escolhas de
  política do runway;
- não medido (cold start, antes de qualquer amostra): a tolerância declarada do run (5 s), nunca um pedaço do
  timeout de transporte;
- teto: `timeoutIntervalForRequest` fica como **limite operacional** — PD-6 regra 4 permite explicitamente tetos
  operacionais, o que ele não permite é a *estratégia* ser um número configurado.

Por que isso importa no produto e não é cosmética: a suspensão **remove** o candidato pendente da seleção
(`SelectionEngine`: `readyEligible` filtra por prontidão; "pending stories consume no source share, separator or
position"), então a janela de mídia decide *quando a fatia tenta* — e a medida R3 mostra que a primeira edição saiu
com 17 cards (9 thumb + 8 text-only) depois de uma janela de **0,39 s**. Ou seja: o teto nunca foi o que produzia o
resultado; ele só precisa não atrapalhar, e agora sai do runway em vez de um `/4`.

### 42. A paginação existe na biblioteca e **ainda não está ligada no host** — o B03 em curso mede o app sem ela

Estado verificado na árvore de hoje, não no relato do Codex:

- `Sources/FeedMineComposition/ReaderDiscoveryPool.swift:84` — `ReaderDiscoveryBuilder.page(for:after:examinedCapacity:)`
  é o caminho com cursor. O próprio `pool(for:limit:)` está documentado como **"Compatibility preview only. Active
  associations should retain and advance `page` cursors."** — e é exatamente ele que o host usa hoje
  (`AppComposition.swift:885`, dentro do `Task.detached` que monta "a fatia fixa").
- `ReaderDiscoveryTraversal` (mesma pasta) mantém `cursor`/`discovered`/`pages` por associação e perfil, avança uma
  página por vez e materializa cada página como snapshot; `SyndicationAcquisitionSnapshot(discovery:)` +
  `advanceDiscovery(for:examinedCapacity:)` são as portas por onde os drivers a alcançam, e os dois drivers
  (`ColdFeedBootstrap`, `FeedRunwayDriver`) já aceitam `onDiscoveryPage:`.

**Os quatro pontos que faltam no host** (o que o Codex listou, conferido na API):

1. Construir **uma** `ReaderDiscoveryTraversal` por associação/perfil e passá-la como `discovery:` ao snapshot de
   aquisição (`AppComposition.swift:1468`) — hoje o parâmetro nem é usado.
2. Passar `onDiscoveryPage:` aos **dois** drivers (`FeedRunwayDriver` e `ColdFeedBootstrap`) para atualizar os mapas
   de nomes/assuntos que a preparação consulta.
3. Trocar a fatia fixa (`pool(for:limit:)` em 885) pelo avanço de página com cursor.
4. Recriar a travessia quando perfil ou catálogo mudarem, mantendo o mesmo coordinator e as oportunidades existentes.

Consequência que importa para a evidência: **o B03 que rodou (397 avanços) e o B03 em curso medem o app com a
paginação inerte** — o ganho de universo só pode aparecer depois dos quatro pontos acima. Registrar isso aqui é o
que impede a leitura errada de "a paginação não ajudou".

Ponto de cuidado para quando eu ligar: onde o catálogo aparece é o bundle (`Bundle.main.url(forResource:
"catalog", withExtension: "sqlite")`), e o `bench/run.sh` **copia o corpus para dentro do bundle** — então a
travessia pagina o corpus do benchmark na corrida e o catálogo de produção no app. É a mesma porta, sem ramo
especial.

### 43. O remoto andou 63 commits de documentação — e um deles é um critério de release

Conferido em 2026-10-10 (o local não tem nada à frente do remoto; está 63 atrás):

|o que|onde|
|---|---|
|`F11`–`F20` (UX de produto) e `F21`–`F27` (plataforma iOS), com o catálogo de pesquisa primária|`docs/product/`, em `origin/main`|
|Garimpo V1→V2 com **G01–G15**, prioridades e a sequência recomendada|`docs/v1-study/V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md`|
|Briefs executáveis e "o que NÃO transportar"|`docs/product/V1_GOLD_IMPLEMENTATION_BRIEFS_2026-10-10.md`, `docs/v1-study/V1_GOLD_DO_NOT_PORT_2026-10-10.md`|

Duas consequências que mudam prioridade:

1. **G09 é P0 e bloqueia release**: disciplina de publicação externa (autoridade, reconciliação, quarentena) e
   "bloquear release se catálogo não validado" (F01/PD-10). Se o passo seguinte for TestFlight — e o app target
   existe agora, ao contrário do que a nota antiga de release dizia —, G09 vem **antes** de aceitar revisão pública.
2. **O critério de aceite de qualquer Gxx é o mesmo que eu venho usando**: `NOT_RUN | PASS | FAIL | BLOCKED`, com
   commit testado, corpus, aparelho/iOS, cenário por **gestos reais**, IDs de card/source/contexto, capturas/traces e
   as regressões B03/B04/B05 associadas. Arquivo Swift presente ou README "implemented" **não** é PASS de produto.

Reconciliação: **não** feita agora de propósito. A árvore tem 80 arquivos sujos e `docs/v1-study/PORT_LOG.md` foi
tocado **dos dois lados**, então não se faz fast-forward nem merge no meio de uma medida de gate em curso. O
procedimento, quando o B03 entregar e os testes rodarem: ler o que quiser direto do remoto (`git show
origin/main:<path>`, que é o que usei aqui, sem tocar na árvore), e só então reconciliar com a árvore limpa —
resolvendo o `PORT_LOG.md` preservando as duas metades.

### 44. Correção do §42: a paginação **não** estava inerte — o pool é que foi reescrito para paginar

O §42 afirmou que "o B03 mede o app com a paginação inerte" e que "o ganho só pode aparecer depois dos quatro pontos
no host". **A segunda metade está errada**, e a evidência estava a um comando de distância:

- `Sources/FeedMineComposition/ReaderDiscoveryPool.swift` é **novo e não commitado** (`??`). O `pool(for:limit:)` que
  o host chama foi **reescrito para caminhar o catálogo em páginas** (`while candidates.count < limit * 4`, lendo de
  500 em 500 com `reader.sources(after: cursor, limit: 500, …)`), em vez de uma leitura limitada única. O ganho
  entrou pelo **call site que já existia** (`AppComposition.swift:885`), sem nenhum dos quatro pontos.
- Medido nos **meus** artefatos (não na tabela que a outra sessão relatou): três B01 recentes registram
  `states/published_sources` = **45, 45, 47** fontes publicadas, contra o requisito "≥20 fontes distintas contribuem
  com os primeiros 300 cards". Os `contacted_sources` começam em ordem alfabética (`96fm.com.br`, `aasnova.org`,
  `ablogtowatch.com`), que é a assinatura da leitura em ordem de chave página a página.

O que **continua** verdadeiro no §42, e é o que falta: a `ReaderDiscoveryTraversal` — o cursor que **cresce durante a
sessão**, página após página, e que Codex desenhou para ser compartilhada pelos dois drivers — **não está ligada**.
O que o pool dá é o universo do cold start; o que a travessia dá é a **progressão** (o item aberto do registro de
aceitação: "o ganho ao longo do tempo"). E o contrato que o Codex fixou agora tem uma consequência de escopo que eu
não tinha lido corretamente: `policyIncludingDiscovery(basePolicy)` e as chamadas antes do slice vivem em
`Sources/FeedMineComposition/` — **lane dele**; a minha metade é a construção da travessia por associação, os
**mapas vivos** que a preparação consulta (em vez do `names` capturado no init) e a recriação na troca de
perfil/catálogo.

Lição de método, curta: eu deduzi "inerte" de não ter visto o wiring no host, quando o arquivo que a torna ativa
estava **não commitado** — `git status --porcelain` (que eu já tinha rodado) mostrava o `??` e eu não o li com o peso
que ele tinha.

### 45. A metade do host na paginação progressiva — e um gap que ninguém tinha visto na primeira tela

Contrato fixado pelo Codex (opção 3 da minha pergunta): a política base continua sendo **o que o leitor escolheu**, a
autorização para alvos recém-descobertos fica **dentro do snapshot** de aquisição, e os drivers ganham
`policyIncludingDiscovery(basePolicy)` antes do slice (lane dele). O que eu liguei no host:

|mudança|por quê|
|---|---|
|`LiveSourceNames` (caixa com lock) + a preparação lendo `names.current`|a descoberta encontra fontes **enquanto o leitor lê**; uma closure que capturou o dicionário da construção publicaria esses cards com atribuição inventada — ou com a URL do principal no lugar do nome|
|`onDiscoveryPage` ligado nos **dois** drivers, mesclando os nomes|é o único efeito do callback: metadados. Não mexe na política, não publica, não agenda aquisição|
|`ReaderDiscoveryTraversal` criada e **lembrada por perfil**|cursor é progresso. Recriar a cada associação voltaria sempre à primeira página — exatamente o "ganho ao longo do tempo" que este trabalho existe para produzir|
|`discovery:` passado ao `SyndicationAcquisitionSnapshot`|é onde os alvos registrados por `advanceDiscovery` viram elegíveis, sem tocar na política resolvida|

**O gap da primeira tela.** O `ColdFeedBootstrap` ganhou `readiness` e `prepareWindowMedia` na tarefa do F06-A, e o
host **não passava nenhum dos dois**: sem fatos de suspensão, todo candidato examinado era elegível e uma história
com imagem pendente podia ser publicada como card sem a mídia que o PD-5 promete. Agora os dois são passados — e o
hook da janela é a **mesma closure** que o driver usa, o que faz a primeira tela e o feed vivo lerem um orçamento só
(`mediaWaitSeconds`). O `prepareMedia` legado (e o `headProvider` que só ele usava) foi apagado: com o hook de
janela, aquele caminho não é alcançado.

**Estado dos três itens do (c)**, com o que falta dito por nome:

1. **Espera de mídia** — derivada e implementada (`p95 × safetyFactor + releaseMarginSeconds`, com o teto de
   transporte só como teto e 5 s só como bootstrap declarado). Falta a corrida que mede.
2. **Reserva** — `RunwayPolicy` deriva `R = ceil(v × (1,2 × p95 + margem))` e o `reserveCards` caiu para
   **bootstrap-only** (Codex), com o valor de bootstrap derivado da janela de apresentação no host. Falta a corrida
   que mede.
3. **Paginação do pool** — a travessia existe e a minha metade está na árvore; a ligação de `policyIncludingDiscovery`
   nos drivers é a outra metade. Falta compilar, testar e medir o alcance ao longo do tempo (o B03 com
   `--full-trace` é o instrumento).

**O que está bloqueando a verificação**: um B03 de trinta minutos rodando no simulador. Compilar ou testar em
paralelo contamina a cláusula que ele mede ("zero paralisação visível ≥1 s"), então a bateria espera — e a cláusula
de prontidão do oráculo, que passa medindo nada, só pode ser corrigida depois que essa corrida morrer.

### 46. O norte de produto valida o que foi feito hoje — e cobra o que falta

Lido `docs/product/PRODUCT_NORTH_STAR.md` (a identidade do produto). Três frases que decidem prioridade, e como cada uma
bate com o trabalho desta rodada:

|norte|o que ele exige|onde isso está|
|---|---|---|
|"Tudo que regula volume, ritmo e retenção deve ser **adaptativo e relativo a fatos observáveis**... vale transversalmente para descoberta, aquisição, seleção, **preparação de mídia, runway**, apresentação, memória, rede, disco, persistência e manutenção"|a espera de mídia e a reserva saem de fatos medidos, não de configuração|§41 (espera derivada da p95 medida) e §45 (reserva derivada; 16 só bootstrap)|
|"**Sem números mágicos como estratégia de produto**... Limiares congelados do benchmark são provas de aceitação, **não** cotas do runtime"|`timeoutIntervalForRequest / 4` e o 16 como piso permanente são defeitos de estratégia|os dois removidos hoje|
|"**exploração progressiva e capacidade relativa**: o catálogo completo é um universo a explorar **progressivamente**... prioridade menor não pode significar esquecimento indefinido"|a paginação **progressiva** não é melhoria opcional, é a promessa|é exatamente o que a travessia com cursor produz — e por que a metade do host (§45) existe|

**O que o norte cobra e eu ainda não fiz**: o orçamento de bytes da camada de mídia. `MediaDeviceConditions.policy`
passa `waitBudgetSeconds: 5` com o comentário *"o que o runway já tolera para uma requisição de feed"* — ou seja, o
comentário aponta para um valor que agora **é** derivado (a janela que eu implementei), e o número continua fixo. Dois
números para a mesma coisa é o que o PD-6 e o norte proíbem: a próxima correção é a camada de mídia ler a **mesma**
tolerância derivada, e o orçamento de bytes (medido × espera) seguir junto. Não foi feito ainda porque muda o tamanho
de imagem que a camada de mídia aceita — comportamento que precisa de corrida para ser afirmado, e a bateria de
verificação está na fila esperando o simulador.

### 47. Duas correções do instrumento, prontas para aplicar (não aplicadas: há corrida viva)

**1. A convenção de prontidão no traço (feito agora, inerte para a corrida viva).** `AppComposition.prepare` escrevia
`"readiness": presented ? "prepared" : "pending"` enquanto o resto do app tem `readinessLabel` com **três** valores
(`prepared` com imagem, `textOnly` por decisão, `pending` nada ainda). Consequência medida: o balde `textOnly` do
oráculo é **inalcançável** — um card publicado como texto por decisão era registrado como `prepared`. Passou a usar
`Self.readinessLabel(...)`: uma convenção só. O fato de estar presente continua no **nome do evento** (`candidate` /
`suspended`) e no campo `reason`, que é onde ele pertence.

**2. A cláusula vácua do oráculo (NÃO aplicado — `bench/oracle.py` está congelado e uma corrida viva teve o
manifesto verificado no início).** Hoje, em `gate_b03`:

```python
"pass": True if candidates else None,
```

que passa sempre que **qualquer** candidato existir, sem nunca exigir que os rótulos cubram os candidatos. Foi assim
que `20261011T043906Z` saiu **PASS** com `candidatos: 871, pendentes: 0, texto: 0, preparados: 0`. O patch, para
aplicar junto com a regeneração de `bench/EVALUATOR.sha256`:

```python
"pass": (candidates.count("pending") + candidates.count("textOnly") + candidates.count("prepared") == len(candidates))
        if candidates else None,
```

Sem candidatos examinados, o veredito é **NOT_RUN** (`None`), que é a regra declarada do próprio registro: "nenhuma
cláusula ausente ou não medida vira PASS". Com examinados e rótulos faltando, é **FAIL** — o gate mediu e achou um
buraco, o que é diferente de não ter medido. As duas correções têm de entrar **juntas**: a convenção só vira medição
quando existe cláusula que a confere.

### 48. F06-G cumprido: um fato medido governa a espera **e** os bytes

O §46 dizia que `MediaDeviceConditions.policy` passava `waitBudgetSeconds: 5` com o comentário "o que o runway já
tolera para uma requisição de feed" — dois números para o mesmo fato, contra o PD-6 e o norte de produto. O F06
torna isso **prova de aceitação**, não limpeza: **F06-G** exige "políticas de rede e mídia mudam com **recursos
observados**, sem quantidades arbitrárias".

O que foi feito:

|peça|antes|agora|
|---|---|---|
|orçamento de bytes de uma imagem|`waitBudgetSeconds: 5` literal, dentro do `policy`|parâmetro obrigatório: quem chama **está** o valor|
|quem calcula o valor|ninguém|a janela (`mediaWaitSeconds`), a partir da p95 medida, do fator e da margem da política|
|como chega|—|`LiveValue<Double>`: a janela publica, o `conditions` lê **na hora** (o `policy` é síncrono e re-executado por download)|
|bootstrap (sem amostra)|5 espalhado|`Self.mediaWaitBootstrapSeconds`, declarado uma vez e usado pela janela **e** pelo orçamento|

`LiveValue<Value>` substitui o `LiveSourceNames` que eu tinha escrito minutos antes — duas caixas com a mesma forma era
duplicação, e `update(_:)` dá o read-modify-write atômico que os nomes precisam. O que se ganha é uma frase só: **um
fato medido governa quanto tempo a preparação pode esperar e quantos bytes uma imagem pode custar.**

**Sobra um `/4`, e ele não é troco:** `tidyWaitSeconds = configuration.timeoutIntervalForRequest / 4` (a espera da
limpeza de mídia). É limite de **manutenção**, não de operação de card, e derivá-lo pede uma decisão própria — do que
ele se protege e contra o que ele compete. Fica nomeado, não varrido para debaixo do tapete.

**Nota de verificação**: mudar o orçamento de bytes muda o que a camada de mídia aceita baixar, então isso **precisa
de corrida** para ser afirmado — entra na mesma fila dos outros (o B03 vivo é o primeiro).

### 49. O último `/4` também saiu — e com ele veio um achado incômodo

O `/4` que sobrava era o orçamento da **limpeza de mídia** em background (`tidyWaitSeconds`), usado como deadline do
`tidy.run(...)`. Ele não protegia nada que um número arbitrário devesse proteger: o que a limpeza precisa é **quanto
tempo o sistema vai realmente conceder** enquanto a tela está apagada, e isso é **observável**: `UIApplication`
reporta `backgroundTimeRemaining`.

A derivação, sem constante nova de estratégia:

- **orçamento** = `backgroundTimeRemaining − tolerância de uma operação de mídia`, com piso 0. A margem que impede o
  tidy de ser morto no meio de uma evicção é **a mesma tolerância** que o pipeline de mídia já usa (um dono, não dois
  números).
- **relatório inutilizável** (fora do background o próprio sistema documenta o valor como sem sentido — ele devolve
  `greatestFiniteMagnitude`): a tolerância é o teto. Um teto de sanidade de 600 s separa "minutos, como o iOS concede"
  de "sentinela" — teto operacional, que o PD-6 regra 4 permite, e que não decide nada sobre o feed.
- o caminho sem UIKit usa o mesmo sentinela, então a resposta é a mesma.

**O achado**: sem uma `beginBackgroundTask`, o tempo que o iOS reporta depois de a tela apagar é **pequeno** — alguns
segundos, não os 15 s que o `/4` fingia. Ou seja, o número antigo não era só arbitrário: ele era **ficção inofensiva**
(quando o app é suspenso, o trabalho assíncrono para de qualquer forma). Consequência honesta da mudança: a limpeza
passa a fazer **o que o sistema permite**, que pode ser menos do que ela fazia enquanto ninguém olhava. O caminho para
a limpeza voltar a ter tempo é a **F23 (execução em background e transferências)**, que existe nas specs de plataforma
no remoto — `beginBackgroundTask` é o fato observável que falta, e ele é do produto, não do instrumento.

### 50. O ganho ao longo do tempo foi medido — e é **zero** na corrida que passou

O item aberto do registro de aceitação dizia que "o ganho *de universo* ainda não foi medido pelo benchmark — as
cláusulas atuais olham os primeiros 300 cards, não o alcance ao longo do tempo". Ele pode ser medido **num artefato que
já existe**, sem corrida nova: o log de transporte do B03 que passou (`bench/run/20261011T043906Z/server.log`) tem o
tempo de cada contato, e o instrumento `bench/expand.py` agrupa primeiros contatos em janelas de 5 minutos.

Medido, com o insumo conferido antes da conclusão:

|o que|valor|
|---|---|
|cobertura do log|**30,5 min** (o gate inteiro, não um pedaço)|
|linhas com `t_ms`|1.756|
|fontes distintas contatadas|**120**|
|janela do primeiro contato de todas elas|**0 → 1,2 min**|
|fontes com primeiro contato **depois** dos 5 min|**0**|

Leitura honesta: aquele feed se manteve saudável por trinta minutos (7.558 avanços, zero paralisação) **usando o
universo que já tinha**, e **parou de descobrir** no primeiro minuto. Isso não contradiz o PASS do B03 — as cláusulas
dele medem runway, repetição, adjacência e prontidão, não expansão — mas é exatamente a diferença entre "o feed não
morreu" e a promessa do norte de produto: *"o catálogo completo é um universo a explorar **progressivamente**...
prioridade menor não pode significar esquecimento indefinido"*.

Causa nomeada, e ela é conhecida: a `ReaderDiscoveryTraversal` **não estava ligada** quando aquela corrida foi
construída (§42, corrigido no §44 — o pool paginou, a travessia não). O que este número faz é dar **linha de base
medida** para a comparação que vem: depois do wiring, a mesma leitura tem de mostrar janelas com contato novo no fim,
não só no começo. Se continuar em 120 com zero depois de 5 min, o wiring não resolveu e o problema é outro.

Consequência para o registro: aquele item **sai de "não medido"** e passa a "medido, negativo, com causa e com a
condição de aceitação escrita".

#### A linha de base, refinada: dentro de **um** contexto a expansão é zero; entre contextos ela é total

Rodando o mesmo instrumento sobre as outras corridas, a imagem fica mais útil do que "não cresce":

|corrida|gate|fontes distintas|janelas|
|---|---|---|---|
|`043906Z`|B03, 30 min, contexto único|**120**|1 — tudo na janela 0|
|`062823Z`|B01|298|1|
|`062326Z`|B05|74|1|
|`053723Z`|B04|120|1|
|`060053Z`|B02 (jornada de **duas fases**)|**298**|**2** — 139 na janela 0, **+159 na janela 1**|

O B02 é o contra-exemplo que importa: ele **contata fontes novas depois dos cinco minutos**. Mas o que ele faz nesse
intervalo é **responder o segundo tema** — ou seja, um **perfil novo**, um pool novo, um universo novo. A conclusão
afiada é esta:

- **entre contextos/perfis**, o universo muda inteiro (159 fontes novas de uma vez);
- **dentro de um contexto**, ele é **plano**: 28 minutos de leitura no B03 sem uma descoberta nova.

Isso é exatamente o que a travessia progressiva existe para mudar, e por isso a condição de aceitação do próximo
número fica mais específica: **contato novo na janela do fim, dentro do mesmo contexto** — não a troca de universo que
uma resposta temática produz.

#### O que a corrida em curso **não** pode medir (escrito antes de ver o número)

Conferido nos chamadores: **os dois drivers já chamam** `advanceDiscovery` — `ColdFeedBootstrap` (linha 164) e
`FeedRunwayDriver` (linha 161). Ou seja, a metade que faltava era só a do host (travessia por associação, `discovery:`
no snapshot, mapas vivos), e ela está feita. Duas consequências que precisam estar escritas **antes** de o próximo
veredito sair:

1. **A corrida `065200Z`, que está no ar agora, foi construída ANTES do wiring do host.** Se o log dela mostrar 120
   fontes planas (como o `043906Z`), isso é **esperado** e **não** é evidência contra a travessia: o binário dela não
   tem a travessia ligada. O que ela verifica é outra coisa — que o app sobrevive 30 minutos sem abortar depois das
   correções de evidência (ENOSPC).
2. **O teste da travessia é a corrida seguinte**, e ele é mensurável sem a parte de elegibilidade: o instrumento lê
   **contatos** no log de transporte, não cards selecionados. A `policyIncludingDiscovery` (lane do Codex) decide
   **quais** fontes descobertas podem virar card; a **descoberta** — que é o que `expand.py` mede — acontece pelo
   `advanceDiscovery`, que já está chamado. Então a condição de aceitação ("contato novo nas janelas do fim, dentro do
   mesmo contexto") pode ser julgada assim que o wiring compilar e uma corrida rodar, sem esperar a outra metade.

### 51. Duas verificações de integridade, feitas antes de virarem problema

**O corpus congelado está intacto**: `shasum -c bench/MANIFEST.sha256` sai com **exit 0**, **2.314 hashes OK** e **0
falhas** — inclusive os 2.3 mil arquivos de feed. As minhas limpezas de disco (DerivedData, caches, bundles
`xcresult` supersedidos) não tocaram nada do que o avaliador congela. O que eu apaguei foi: produtos de build
reconstruíveis e os `derived/` das duas corridas antigas — e essas duas nunca foram citadas como prova de nada.

**E uma lacuna que só importa no dia em que importa**: `bench/expand.py` — a ferramenta que mede a expansão
progressiva — **não está em nenhum dos dois manifestos**. `MANIFEST.sha256` congela o corpus e o servidor;
`EVALUATOR.sha256` congela o `run.sh`, o `oracle.py`, o `build_corpus.py` e o driver de UI. O instrumento que produz o
número **de fora** do veredito ficou de fora dos dois.

Enquanto ele é só leitura comparativa, tudo bem. No momento em que o número de expansão virar **cláusula** — e o §50
já escreveu a condição de aceitação nesses termos —, a régua que produz o número tem de estar congelada junto com o
oráculo, senão vale a frase que este benchmark existe para impedir: um instrumento editável citando um resultado
imutável. Fica anotado **antes** de virar cláusula, não depois.

#### A previsão, escrita antes de medir

Conferido no código, não suposto:

- `FeedRunwayDriver.drive(...)` avança **uma página de catálogo por oportunidade** (`advanceDiscovery`, fora do dreno
  causal) — e um B03 chama `drive` a cada avanço do leitor, ou seja, dezenas de vezes por minuto;
- `discoveryExaminedCapacity` tem **default 120** e o host **não** o sobrescreve: cada página examina 120 chaves de
  catálogo e admite as que casam com o perfil;
- o universo elegível do corpus é **942 fontes (perfil A)** e **1.123 (perfil B)**;
- `ColdFeedBootstrap` avança a mesma travessia pelo mesmo caminho.

**Previsão para a corrida seguinte (com o wiring ligado), medida pelo mesmo `expand.py`:** centenas de fontes distintas,
não 120 — com **contato novo nas janelas do fim**, não só na primeira. A ordem de grandeza é o universo elegível: se o
perfil A admite ~942 fontes, um feed que examina 120 chaves por oportunidade e tem centenas de oportunidades em trinta
minutos deve atravessar boa parte disso.

**Se em vez disso continuar em ~120 planas**, o diagnóstico já está escrito, e nenhum deles é "a travessia não serve":

1. `discovery:` chega `nil` ao snapshot — e aí a primeira coisa a conferir é se o catálogo está no bundle
   (`Bundle.main.url(forResource: "catalog", withExtension: "sqlite")`) e se o perfil não está vazio;
2. a travessia avança mas o callback não chega — `onDiscoveryPage` é opcional em ambos os drivers;
3. a autorização nova não vira **card** — que é a parte da elegibilidade, lane do Codex, e que **não** afeta a
   contagem de **contatos** (a descoberta é medida antes disso).

Escrever a previsão antes é o que dá sentido à medida depois: sem ela, "melhorou" e "não mudou" são opinião.

#### O mecanismo que faz a previsão do §52 plausível, conferido no código

Não é só "a travessia avança": existe **onde** esse avanço vira contato. Em `FeedRunwayDriver.driveCausalEffects`, quando o
runway não pede nada (`case .none` — ou seja, quando o leitor está mais lento que a oferta), o driver chama
`acquisitionCycle.runCoverage(demand, scope:eligibleTargets:resources:)` com
`eligibleTargets = acquisition.eligibleTargets(for: plan.context)`. E os alvos elegíveis do snapshot são, por
construção, os **registrados** — estáticos e os que a travessia materializou.

Ou seja: **a folga real do runway é gasta em aquisição exploratória**, exatamente o que o norte de produto manda ("usar
folga real para aquisição exploratória e retenção adicional", "a prioridade determina ordem e frequência, não uma cota
permanente"). Com a travessia ligada, cada página examinada amplia o conjunto elegível, e a próxima folga contata o que
apareceu.

Isso fecha a cadeia inteira do lado da medição: **página → registros → alvos elegíveis → contato na folga → primeira
coluna nova no `expand.py`**. Se a corrida seguinte continuar plana, o rompimento está em um elo nomeado — e nenhum
deles é "a ideia não funciona".

### 53. O achado do §49 não é um problema novo: a F23 já tem a resposta, e ela é mais estreita do que parece

Lido `docs/product/F23_BACKGROUND_EXECUTION_TRANSFERS_PRD.md` (existe no remoto, entre as specs de plataforma). Ela
define o que o iOS realmente permite, com a documentação oficial citada:

> `beginBackgroundTask`: tempo adicional **limitado** para concluir gravação/commit iniciado, com expiration e
> chamada balanceada de `endBackgroundTask`; **não permite manter a aquisição rodando indefinidamente**.

Isso responde ao §49 com precisão, e me impede de resolver o problema errado: o que a limpeza de mídia precisa **não** é
um pedido de tempo extra para trabalhar mais — é **concluir o que já começou** (a evicção e o commit em andamento)
dentro do tempo que o sistema concede, com `expiration` tratada e `endBackgroundTask` balanceado. A aquisição
exploratória continua sendo trabalho de primeiro plano e de folga de runway, onde ela já vive.

Também fica claro por que o `/4` antigo era pior do que eu escrevi no §49: ele não só era arbitrário — ele **não
obtinha tempo nenhum**. Um número não pede extensão ao sistema; `beginBackgroundTask` pede, e é o pedido (não o número)
que muda o que a limpeza consegue fazer.

Entra na fila como item de produto (F23), com a prova que ela mesma exige: cenários verificáveis de conclusão e
expiration, e chamada balanceada — não "funcionou mais rápido".

### 54. A sequência pós-gate, fixada pelo Codex — e o passo 1 é o que eu ia esquecer

Mensagem dele na thread dos gates, literal: *"Até o B03 terminar, preserve a corrida e o avaliador: sem compilação,
testes ou alteração de `bench/oracle.py`."* Depois:

1. **Guardar o veredito e o full trace da corrida.**
2. Integrar `policyIncludingDiscovery`, preservando a travessia por perfil e os mapas vivos.
3. Corrigir a cláusula de prontidão para retornar **NOT_RUN quando não houver registros**, e regenerar o manifesto.
4. Rodar a bateria, **incluindo suspensão no bootstrap e avanço dos candidatos seguintes quando o primeiro estiver
   pendente** — que é a prova de aceitação do F06-A, não um teste qualquer.

E a leitura dele da corrida em curso: *"mede o estado anterior à integração restante. Pode comprovar ganhos já
presentes, mas a aceitação final precisa verificar também o código que ainda vai entrar."* É a mesma ressalva que eu
escrevi no §52, dita pelo outro lado da mesa.

**O passo 1 é meu erro evitado.** O traço completo vive no container do app no simulador. A próxima corrida faz
instalação limpa e **apaga o container** — inclusive o traço que o oráculo lê. Salvar cópia do `trace.jsonl` (e do
veredito) dentro do diretório da corrida é o primeiro passo, **antes** de qualquer build, e é o tipo de coisa que só
parece óbvia depois de perdida. O `run.sh` já apaga o `derived/` no fim; o traço, não — ele mora fora do diretório da
corrida.

### 55. O veredito da corrida `065200Z`: PASS, e a previsão cumpriu-se ao pé da letra

```
PASS | trinta minutos de avanço com oferta suficiente        | 4570
PASS | zero repetição para disfarçar falta de oferta          | 0
PASS | zero pares consecutivos da mesma fonte no trace inteiro | 0
PASS | zero paralisação visível ≥1 s por falta de runway      | {"paradas": 0}
PASS | a prontidão de cada candidato foi registrada           | 874 candidatos, 0 pendentes, 874 preparados
```

**O que este PASS prova**: as correções de evidência valem — trinta minutos sem abortar, depois de duas corridas que
morreram aos 193 s e aos 228 s. O ENOSPC era o assassino; a API que lança é a correção; o preflight de 3 GB é a
prevenção.

**O que ele não prova, e eu escrevi isso antes de vê-lo**: a expansão ficou em **120 fontes, todas na primeira janela,
zero depois dos cinco minutos** — idêntica à linha de base. Eu registrei no §52 que a build desta corrida é anterior
ao wiring do host, então *"se mostrar 120 planas, isso é esperado e não é evidência contra a travessia"*. Cumpriu-se
ao pé da letra, incluindo o `texto: 0` (a convenção de três estados também é posterior a esta build). Nenhum dos dois
números pode ser lido como veredito sobre a paginação — nem a favor, nem contra.

**Passo 1 da sequência, cumprido**: o traço está salvo em `bench/run/20261011T065200Z/trace.jsonl` (17.167 linhas),
copiado do namespace `F0ACAAC0-…` que o próprio `report.md` identifica. Sem isso ele morreria na próxima instalação
limpa.

**E um erro de instrumento meu, que quase custou o passo 1**: o `find` do macOS (BSD) **não aceita `-newermt` com
string humana** — o predicado falha em silêncio, e eu já tinha me apoiado nele duas vezes hoje (inclusive para dizer
"nenhum arquivo mudou em 30 minutos"). Corrigido o método: o traço agora se identifica pelo **caminho que o relatório
imprime**, não por adivinhação de tempo. `-newermt` só com carimbo `date -v-…`, ou não usar.

### 56. O preço da limpeza de disco: cache de pacotes vai embora junto

Para o B03 caber, eu apaguei `~/Library/Developer/Xcode/DerivedData/*` e `~/Library/Caches/*`. Os 2 GB vieram — e
junto veio o cache de dependências: um `xcodebuild -list` ficou **300 s preso em "Fetching from
github.com/nmdias/FeedKit"** e morreu por timeout.

Conferido depois, para não confundir causa com coincidência:

|o que|estado|
|---|---|
|rede para o GitHub|**HTTP 200 em 1,2 s** — não é a rede|
|cache de repositórios do SwiftPM|`FeedKit-5732c527`, `GRDB.swift-dd0599db` presentes|
|checkouts no repo|`.build/checkouts/FeedKit`, `.build/checkouts/GRDB.swift` presentes|
|`Package.resolved`|feedkit 10.9.4, grdb.swift 7.11.1|

Conclusão: a troca foi **espaço por re-resolução de pacotes**. O `swift test` do pacote resolve do cache local (que a
própria bateria repovoou); o `xcodebuild` com `-derivedDataPath` novo re-clona para o seu `SourcePackages`, alguns
segundos com a latência medida. O **benchmark** não quebra por isso — `run.sh` já usava `-derivedDataPath "$OUT/derived"`
novo a cada corrida e os builds anteriores levaram ~2 min. Mas fica registrado o que se paga: quando o disco for o
gargalo de novo, a limpeza de `DerivedData` custa um clone, e a de `manifests` custaria o próprio avaliador.

### 57. Duas regras de Swift que a bateria pegou — e que eu tinha levantado e descartado rápido demais

A bateria de verificação parou na compilação do app, com o texto literal:

```
AppComposition.swift:1680:55: error: covariant 'Self' type cannot be referenced from a default argument expression
AppComposition.swift:1680:35: error: main actor-isolated default value in a nonisolated context
```

As duas eram minhas, e as duas vinham da mesma linha:

```swift
nonisolated static func mediaWaitSeconds(..., bootstrap: Double = Self.mediaWaitBootstrapSeconds) -> Double
```

**Regra 1**: valor de argumento padrão **não aceita `Self`**. O padrão é avaliado *no ponto da chamada*, então o nome
tem de ser o tipo concreto (`FeedAssociation.mediaWaitBootstrapSeconds`).

**Regra 2**: o mesmo padrão também não aceita valor isolado ao main actor — uma constante `static let` de uma classe
`@MainActor` é isolada, e a função é `nonisolated`. A constante passa a ser `nonisolated static let` (é um `Double`,
`Sendable`, não toca estado).

O que eu escrevi antes do erro, na revisão: *"default arguments referencing `Self.` in a static method: allowed?"* — eu
levantei a dúvida em uma linha, respondi "hmm" e segui. A bateria custou quatro minutos e respondeu com o compilador.
A anotação honesta é essa: a dúvida certa, feita no momento certo, e abandonada por preguiça de abrir o build.

### 58. O defeito que o meu wiring introduziu: um cache que preservava progresso estava preservando recursos mortos

O §45 escreveu, com todas as letras, por que a travessia de descoberta é lembrada **por perfil**: *"cursor é progresso.
Recriar a cada associação voltaria sempre à primeira página — exatamente o ganho ao longo do tempo que este trabalho
existe para produzir."* A decisão estava certa no que queria guardar e **errada no que acabou guardando junto**.

A cadeia, medida pelo Codex antes de eu terminar de explicá-la:

1. O cache de travessias sobrevive à associação — isso é o objetivo.
2. A travessia guarda **snapshots de páginas** (`pages`), e cada snapshot carrega o `URLSession` **da associação que o
   materializou**.
3. Quando aquela associação fecha, `close()` **invalida** a sessão dela.
4. Consequência (a): um `Task` criado nessa sessão morta estoura
   `Task created in a session that has been invalidated` — que é o **T11** que a bateria acusou.
5. Consequência (b), pior porque é silenciosa: *"a associação nova, configurada **offline**, adquiria dados **pelo
   transporte antigo das páginas retidas**"*. Não era só uma exceção — era leitura pelo recurso errado, que é o tipo de
   defeito que passa despercebido por revisão de código e por teste de unidade.

Correção do Codex: *"corrigi a resolução dos conectores para usar o transporte atual, **preservando registros e cursor
da travessia**"* — isto é, exatamente a decisão (B) que ele tinha condicionado a uma prova: **reter o cursor e os
registros, não o material**.

**A lição, que vale mais que o defeito**: um cache criado para preservar **progresso** precisa declarar o que é
progresso e o que é **recurso emprestado**. Progresso é cursor, contagem, identidade. Recurso é sessão, conexão,
handle, buffer — ele pertence à associação que o abriu e morre com ela. Guardar os dois no mesmo lugar cria um defeito
que só aparece quando a associação *muda*, e a mudança é justamente o que o cache existe para sobreviver.

E a evidência de que valeu a pena ter a bateria rodando o app inteiro: nenhuma das minhas verificações de sintaxe,
nenhum `swiftc -parse`, nenhuma leitura de código teria produzido este achado. Ele apareceu porque o app foi
**executado** — duas vezes, uma sem a correção e uma com.

### 59. Compilar enquanto o outro agente escreve — o mesmo erro, do outro lado

Eu exigi do Codex: *"não rode `swift test` nem `xcodebuild` agora; a bateria compila `Sources/`, e uma edição no meio produziria um erro fantasma"*.
Ele obedeceu à risca, duas vezes, e esperou o meu aviso. Então eu liberei a árvore e **rodei a bateria enquanto ele editava** — e coletei
exatamente o fantasma que eu tinha descrito:

```
Tests/FeedMineCompositionTests/ColdFeedBootstrapTests.swift:534: error: cannot find 'MediaPreparationOpportunity' in scope
                                                              error: extra argument 'makeMediaOpportunity' in call
```

O teste dele já referenciava um tipo que a fonte ainda não tinha: estado transitório do trabalho em voo, não defeito. Junto veio
`testAnswerDuringReplaceSessionIsApplied` falhando ("a associação final tem de ler a resposta recebida durante a construção") — que é
**a lacuna de reconstrução que ele mesmo nomeou** e estava consertando naquele instante.

**O que a corrida ainda provou, e vale**: o **T11 desapareceu** da lista de falhas. O conserto de resolução de conectores — usar o
transporte atual em vez do retido nas páginas — fechou a exceção de sessão invalida. Esse pedaço é medição legítima.

**A regra que fica, escrita nos dois sentidos**: uma árvore só é compilável por um de cada vez. Não basta eu pedir silêncio enquanto
compilo; tenho de dar silêncio enquanto ele escreve. Coordenação unilateral não é coordenação — é a mesma corrida de sempre, com o
papel trocado. O procedimento adotado: **eu aviso quando a árvore estiver limpa, ele avisa quando terminar de escrever, e nenhum dos
dois compila no intervalo do outro.**

### 60. A régua da expansão entrou no manifesto — antes de virar cláusula, não depois

O §51 tinha anotado a lacuna: `bench/expand.py`, o instrumento que produz o número de expansão, **não estava em nenhum
dos dois manifestos**. E o §50 tinha escrito a condição de aceitação em termos desse número — "contato novo nas janelas
do fim, dentro do mesmo contexto". Ou seja: um número citado como critério, medido por uma régua editável.

Feito agora, com a janela limpa (ninguém compilando, nenhum gate rodando):

```
6ae844b6…  bench/run.sh
978910e5…  bench/oracle.py
783966ad…  bench/serve.py
3c28c838…  bench/build_corpus.py
0894b314…  bench/expand.py          ← a régua
83e9c65e…  FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift

shasum -a 256 -c bench/EVALUATOR.sha256 → 6/6 OK
```

A partir daqui vale a mesma disciplina do oráculo: **editar o `expand.py` exige regenerar o manifesto**, e o
`run.sh` recusa a corrida se ele não bater. Antes disso, eu podia — sem má intenção e sem aviso — mudar a janela de
5 minutos, o `t/1000` ou a definição de "primeiro contato", e citar a linha de base de 120 fontes como se fosse
comparável. Agora não: a régua e o resultado vão juntos, ou nenhum dos dois vale.

### 61. A reconciliação do `origin/main` está medida — e é mecânica

O §43 deixou "reconciliar com a árvore limpa" como pendência de limite de fase, com o risco nomeado mas não medido. Medi agora,
sem tocar em nada:

|o que|quantidade|
|---|---|
|arquivos que o remoto mudou (`HEAD..origin/main`)|58|
|arquivos sujos nesta árvore|83|
|**interseção — o risco real**|**4**|

Os quatro: `Package.swift`, `docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md`, `docs/v1-study/PORT_LOG.md`,
`docs/v1-study/UI_TRANSFER_MATRIX.md`. Três são documentos; **um é código**, e é o único que exigia cuidado:

- **remoto**: mudou o **comentário de status** do topo (linha ~22) — *"Architecture scaffold only"* → *"Production package
  manifest: os dez módulos e seus alvos de teste estão implementados"*, com a ressalva de que a autoridade é PD-10/INV-18;
- **esta árvore**: mudou o **manifesto** (linha ~62) — `FeedMineComposition` ganhou `resources: [.process("Resources")]`.

**Regiões diferentes, nenhuma sobreposição de intenção** → o merge é mecânico. E o `PORT_LOG` já tem a forma da resolução
decidida no §43: preservar as duas metades (as entradas do remoto são uma correção de doc que cita PD-10/INV-18 e vale manter
literalmente).

Conclusão honesta: o item **não** está bloqueado por dificuldade, está bloqueado por **sequência** — reconciliar com 81 arquivos sujos
significa arrastar trabalho em voo (o do Codex incluído) para dentro de um merge. Fica para o fim do ciclo, quando a árvore puder
parar de se mexer por alguns minutos.

### 62. A barra do brief de V1-gold é a mesma que esta sessão já vinha segurando

Lido `docs/product/V1_GOLD_IMPLEMENTATION_BRIEFS_2026-10-10.md` (remoto). Três coisas dele importam para o próximo ciclo, e as três
confirmam decisões tomadas hoje — o que é útil saber *antes* de começar, não depois:

**A regra de execução**: *"Cada item é uma jornada de usuário, não módulo Swift. Antes de alterar código, identificar se já há fluxo
correspondente e executá-lo; fechar a **lacuna mais curta** no owner existente. Se já estiver operante, registrar evidência e
encerrar a tarefa sem reescrever."* É a disciplina que produziu os cinco vereditos: nenhuma camada nova, nenhum owner duplicado, e o
trabalho de hoje no wiring fechou lacunas no `ColdFeedBootstrap` e no `FeedRunwayDriver` em vez de criar um terceiro caminho.

**A barra de "Done de uma mudança"** tem cinco itens, e o quinto é o que dói: *"inconsistências são FAIL/NOT_RUN, não 'validado' por
código"*. É exatamente a luta do oráculo que passava medindo nada (§47) — e vale notar que hoje essa barra foi **excedida** num ponto:
a cláusula de prontidão não só deixou de virar PASS vacuamente, como o instrumento que produz a linha de base de expansão entrou no
manifesto do avaliador (§60), coisa que a barra não exige e que o benchmark precisava.

**O recorte S5 (G09 + G10)** — catálogo público confiável, o que **bloqueia release** — está escrito de forma executável:
pré-condição é *"manifest com SHA/schema e corpus de aliases/redirects/quarantine"*; o gesto é instalar/reabrir com snapshot válido,
oportunidade de atualização válida e **outra inválida**; o resultado é *"revisão pública é a autoridade; falha preserva último
snapshot válido e dados pessoais"*; e a evidência é revision, hashes, IDs canônicos, quarantine ledger e teste offline/manifest
inválido. O brief também diz o que **não** fazer, na mesma frase: *"não roda discovery via Python no aparelho"*.

Nada foi escrito como documento novo: o brief já existe no remoto, e a regra do projeto é não produzir documentação sem pedido. O
que este §62 registra é a leitura — para que o próximo ciclo comece por S5 sabendo que ele **não** é uma reescrita, e sim a
reconciliação de um catálogo com a autoridade que já existe (`wawasoft/feed-repository`, PD-10/INV-18).

### 63. G09 do lado do app: a lacuna é real, e isso é boa notícia

A primeira regra do brief de V1-gold é anterior a qualquer código: *"Antes de alterar código, identificar se já há fluxo correspondente e
executá-lo... Se já estiver operante, registrar evidência e encerrar a tarefa sem reescrever."* Checado, antes de planejar:

|o que o S5 exige|o que existe hoje|
|---|---|
|manifest do catálogo com **SHA e schema**|**nada** — a palavra não aparece em nenhum arquivo Swift de `Sources/` ou `FeedMineApp/`|
|quarentena / ledger de quarentena|**nada**|
|reconciliação com a autoridade pública|**nada** (o único "reconcile" no código é `unreconciled legacy target`, do lado de aquisição, que é outra coisa)|
|identidade do catálogo|**existe em parte**: `catalogGeneration` (carimbo na edição e no plano) e `catalogRevision` do `ReaderDiscoveryBuilder` — mas este último é *path + tamanho + mtime do arquivo local*, não a revisão/hash da fonte pública|

Conclusão: **a metade do app do G09 é lacuna, não reimplementação.** O app não recusa catálogo inválido porque não tem manifest para
validar. O trabalho é:

1. um **manifest** para o catálogo que o app carrega (revision, hash, schema) — com o `catalogGeneration` existente servindo de semente
   para a identidade, em vez de inventar uma segunda;
2. um passo de instalação/reconciliação que **rejeita manifest inválido e preserva o último snapshot válido e os dados pessoais** —
   que é a frase literal do resultado esperado no brief;
3. a prova que o brief exige: **teste offline com manifest inválido**, mais revision, hashes e IDs canônicos.

E o que o brief proíbe, na mesma frase: *"não roda discovery via Python no aparelho"* — a preparação e a quarentena são de ferramenta
externa (`wawasoft/feed-repository`), o app só consome o que foi validado.

Sem escrever documento novo: o brief existe, e a lacuna agora está medida em vez de suposta.

### 64. O censo do traço: o gate que passou **não** exercitou a suspensão — e ninguém deve inferir F06 do PASS

Analisados os 17.167 eventos do traço salvo em `bench/run/20261011T065200Z/trace.jsonl` (30 minutos com `--full-trace`):

|evento|quantidade|
|---|---|
|`admitted`|4.577|
|`advance`|4.570|
|`runway_completed`|4.570|
|`window`|2.574|
|`candidate`|874|
|`answer_applied`|2|

E o essencial, que só aparece quando se olha a prontidão em vez do volume:

- **prontidão**: `prepared` × 874 — todos preparados;
- **suspensões**: **zero**;
- **transições `media_ready`**: **zero**.

**O que isso significa**: naquele ambiente (transporte local, mídia rápida), nenhum candidato ficou com imagem pendente. A regra
central do F06 — *"um candidato escolhido que ainda não pode oferecer experiência válida sai imediatamente da fila pronta"* — **não foi
exercitada uma única vez**. Consequência que precisa estar escrita antes de alguém citar o PASS:

- o B03 que passou prova **runway, repetição, adjacência, paralisações e registro de prontidão**;
- ele **não** prova F06-A (aviso: pendente fora da fila, os seguintes avançando) nem F06-B (a imagem lenta chega e o candidato volta);
- a prova dessas duas é **cenário dirigido**, e é o que o Codex está escrevendo
  (`testScopedPendingMediaResumesFiniteWindowsWithoutReservingPublication` e o par que ele adicionou em `ColdFeedBootstrapTests`).

Também é a primeira medição do gênero que fica comparável: com a convenção de três estados agora na árvore (§57), o próximo traço
distingue `prepared` de `textOnly` de `pending` — e aí "zero suspensões" deixa de poder ser confundido com "nenhum texto por decisão".

### 65. Pre-flight de corrida: a receita, e uma instabilidade que quase me custou o traço

O `run.sh` já recusa corrida abaixo de 3 GB (§43), mas falta a receita de **como chegar lá** — e foi ela que achou 0,9 GB livres hoje,
com a próxima corrida condenada a nem começar. Ordem de limpeza, do mais seguro ao mais arriscado, com o que cada passo custa:

|passo|libera|o que custa|
|---|---|---|
|`/tmp/fm-battery`, `/tmp/fm-*-dd`, `git worktree remove`|**2,1 GB**|nada — DerivedData de bancada e um worktree de baseline|
|lixo do `.git` (`tmp_pack*`, `tmp_obj*`, que o próprio `git count-objects -vH` chama de *garbage*)|**426 MB**|nada — operações interrompidas; o git recria o que precisar|
|namespaces antigos do app no simulador|**1,1 GB**|nada — cada corrida instala limpo e cria namespace novo; o que vale (relatório, log de transporte, traço copiado) já está no diretório da corrida|
|`~/Library/Developer/Xcode/DerivedData`|1,1 GB|um clone de pacote na próxima compilação (§56)|
|`~/Library/Caches`|2,6 GB|o mesmo, um pouco mais|

Resultado de hoje, em ordem: 0,9 → 3,0 → 3,4 → **3,8 GB**, com o preflight passando com 3910 MB.

**E a instabilidade que apareceu no caminho.** O container do app **muda de ID**: era `488852F1…` quando eu inspecionei, virou
`1FD16594…` depois — porque o meu próprio `xcodebuild test` do baseline **reinstalou o app**. Consequência prática, e a razão de eu
ter falhado no primeiro `find` do §55: o caminho de container que o relatório imprime **não é estável entre execuções**, e guardá-lo
para "usar depois" é uma armadilha. A única forma robusta é a que funcionou: **no instante em que a corrida termina, ler o caminho do
banco no `report.md` e copiar o traço de lá** — sem consultar container lembrado, sem adivinhar por tempo (`-newermt` no BSD não
existe, §55).

Nada disso é sobre o produto. É sobre a diferença entre um gate que roda e um gate que morre por infraestrutura — que foi o tema de
duas corridas hoje.

### 66. O aparelho está pareado — e o caminho não é a janela do Xcode

O erro do Xcode era explícito: *"iPhone is not available because it is **unpaired**. Pair with the device in the Xcode Devices
Window"*. Dois gestos do usuário no aparelho (confiar no computador) não mudaram nada — e eles *têm* de ser feitos, mas não eram o
que faltava.

O que faltava era o **registro de pareamento para desenvolvimento**, e ele tem verbo próprio:

```
$ xcrun devicectl manage pair --device 00008110-00067D861486201E
Paired with device:
Name     Hostname                  Identifier                             State                 Model
iPhone   iPhone.coredevice.local   BBA4F656-A5EA-5D81-934E-E484ED71B8E2   available (paired)    iPhone14,8
```

Antes, o `-showdestinations` dizia `error: … unpaired`; depois, a mesma linha vira **destino utilizável** sem erro nenhum. Três
lições que custaram tentativa e erro, e que valem para a próxima máquina:

1. **`available` no `devicectl list devices` não significa pareado.** Ele aparece como `available` com `transport: wired` mesmo
   quando o Xcode recusa o aparelho por falta de pareamento. O sinal que vale é o do **destino de build**, não o do listador.
2. **`ddiServicesAvailable: false` e `tunnel: disconnected` antes de qualquer sessão são estado normal**, não sintoma: o Developer
   Disk Image é montado sob demanda na primeira interação real (`install`, `launch`), e o `osVersionNumber` também só aparece
   depois. Eu quase diagnostiquei "DDI não montado" como causa quando era consequência.
3. **O pareamento não precisa da interface do Xcode.** `devicectl manage pair` faz o mesmo, em 0,3 s, e é o caminho preferível num
   host sem janela — o usuário não precisa tocar em nada além do que já tocou.

Os perfis de provisionamento com este UDID **já existiam** (quatro deles): conta, time e registro do aparelho estavam prontos, e o
que faltava era só o vínculo local. Vale checar isso primeiro na próxima vez — separa "problema de conta" de "problema de máquina".

### 67. O caminho de aparelho tem um requisito que o simulador não tem: **a assinatura**

O build para o iPhone passou de primeira (`BUILD SUCCEEDED`, 68 s, `-destination platform=iOS,id=00008110-…`,
`-allowProvisioningUpdates`). A instalação **não**:

```
xcrun devicectl device install app --device … FeedMine.app
  LegacyErrorString = ApplicationVerificationFailed
  FunctionName = +[MICodeSigningVerifier _validateSignatureAndCopyInfoForURL:withOptions:error:]
```

O `codesign -dvvv` no bundle denunciou a causa em uma linha: **`Info.plist=not bound`**. O harness — que no simulador
injeta o catálogo e o ATS **depois** do build — estava mutando um bundle **já assinado**. No simulador isso é invisível
(não há verificação de assinatura); no aparelho é fatal.

**Regra que passa a valer para o caminho de aparelho: toda mutação do bundle depois do build exige re-assinatura.** A
injeção em si (copiar `catalog.sqlite`, ajustar o `Info.plist`) está certa; o que falta é fechá-la com os entitlements
que o *próprio build* gerou:

```
codesign -d --entitlements :- "$APP" > /tmp/ent.plist      # antes de mutar — get-task-allow e application-identifier vêm daqui
cp bench/device/catalog.sqlite "$APP/catalog.sqlite"        # a injeção do avaliador
plutil -replace NSAppTransportSecurity -json '{"NSAllowsArbitraryLoads":true}' "$APP/Info.plist"
codesign --force --sign "Apple Development: wmontes@gmail.com (BU5227WFYX)" --entitlements /tmp/ent.plist "$APP"
```

Herança do `codesign` sem `--entitlements` **não** serve: sem `application-identifier` e `get-task-allow` o perfil deixa
de casar e o erro é o mesmo.

Duas coisas que o diagnóstico também firmou, e que valem contra a intuição:

- **O Developer Mode deste aparelho está `enabled`** e o `ddiServicesAvailable` está `True`, o túnel `connected`, o
  pareamento `paired` — ou seja, os três sinais que §66 previu como necessários estão todos satisfeitos, e o que
  faltava era só o pareamento. (§66 previu `ddi: false` como estado normal; ele virou `true` na primeira sessão real
  com o aparelho, como previsto.)
- **O perfil embutido é um wildcard de time** (`iOS Team Provisioning Profile: *`, `955573A4YH.*`, desenvolvimento,
  válido até 2027-06-07, com o UDID entre os dois dispositivos provisionados). Assinatura automática resolveu conta,
  App ID e dispositivo sem nenhuma configuração manual — o que faltava não era credencial, era ordem de operações.

A variante de catálogo para aparelho (`bench/device/catalog.sqlite`) tem **apenas** `request_url` rehostado de
`127.0.0.1:8757` para o IP do Mac: 2.305 linhas, zero loopback restante, e **`declared_url` intacta nas 2.305** — a
identidade das fontes não foi tocada. O catálogo congelado mantém o hash `1f642eaa`, igual ao do manifesto. O servidor
escutava só em loopback por default, mas `serve.py` **já tinha `--host`**: `python3 bench/serve.py --host 0.0.0.0`
responde HTTP 200 tanto em `127.0.0.1:8757` quanto em `192.168.1.76:8757`.

### 68. O caminho de aparelho está **provado positivo** — e o que ele mostrou

Depois de parear (§66) e de corrigir a assinatura (§67), a cadeia inteira executou **no iPhone 14 Plus físico**:

```
xcrun devicectl device install app   → installationURL: …/FeedMine.app/
xcrun devicectl device process launch → Launched application with com.feedmine.development bundle identifier
xcodebuild test -destination "platform=iOS,id=00008110-00067D861486201E" \
  -only-testing:FeedMineUITests/FeedMineUITests/testFirstRunCollectsLanguagesAndPlacesAndEntersTheFeed
  → Test Case '…testFirstRunCollectsLanguagesAndPlacesAndEntersTheFeed' passed (39.131 seconds)
  → ** TEST SUCCEEDED **
```

Não é "o app abre": é **o driver de UI do próprio projeto dirigindo o app com gestos reais num aparelho físico**, e a
jornada de primeira execução passando. Os dois obstáculos que impediam isso eram alheios ao app — alvos de teste sem
`DEVELOPMENT_TEAM` (que no simulador nunca aparece como erro, e no aparelho é fatal) e a mutação do bundle depois da
assinatura (§67). Ambos corrigidos na árvore.

A captura anexada pelo teste (`v2-first-run`, extraída do `.xcresult`) mostra a tela do aparelho: logotipo da folha,
controles de busca/marcador/lista, e um card real — **"Blind Guys Chat"**, chip *Podcast*, **"#155: Straight to
heaven"**, a descrição da fonte e a data — em resolução 1284×2778, que é iPhone 14 Plus, não simulador. A barra de
diagnóstico traz `received=0 completed=0`: **a primeira tela é descoberta local, sem rede**. Isso é a arquitetura do
produto funcionando no aparelho, e separa duas coisas que é fácil confundir:

- **descoberta local** — provada no aparelho, sem rede alguma;
- **busca de fonte pela rede** — é o que a variante de transporte existe para medir, e é o que falta para o B06
  propriamente dito.

`xcodebuild test` num destino físico **re-assina o bundle sozinho** (o build é de `xcodebuild`), então a injeção manual
do §67 vale para o ciclo `install`/`launch` direto, não para o ciclo de teste.

### 69. O caminho de aparelho do B06, e o que ele mudou no avaliador

O B06 deixou de ser "não executável". A sequência medida, ponta a ponta, num iPhone 14 Plus físico:

1. **Pareamento** (`xcrun devicectl manage pair --device <udid>`). O erro do Xcode dizia *"unpaired"* enquanto o
   `devicectl list devices` já mostrava `available` — o listador não é o sinal, o **destino de build** é (§66).
2. **Assinatura**: `xcodebuild build-for-testing -destination "platform=iOS,id:<udid>"` passou de primeira;
   a **instalação** não, com `ApplicationVerificationFailed` e `Info.plist=not bound`. A causa era minha: o
   harness injeta catálogo e ATS **depois** do build, e isso invalida a assinatura. Num aparelho é fatal; no
   simulador nunca aparece. O runner agora re-assina com os entitlements que o próprio build gerou (§67).
3. **Driver rodando no aparelho**: `testFirstRunCollectsLanguagesAndPlacesAndEntersTheFeed` passou em 39,1 s.
4. **O corpus não chega ao aparelho por loopback** — loopback de um aparelho não é o loopback do Mac. Daí a
   variante de transporte (§68 e `bench/transport_variant.py`), autorizada pelo arquiteto com quatro ajustes,
   todos implementados e provados por reversibilidade.
5. **O sandbox que quase me custou uma decisão errada**: eu ia pedir ao arquiteto para decidir onde colocar 3,7 MB
   de corpus, porque o driver roda no processo do **test runner** e não pode ler o container do app sob teste.
   Antes de perguntar, medi: o driver usa o corpus para **uma única coisa**, `profiles.json` — os rótulos que ele
   responde ao Composer — e esse arquivo é o único insumo do oráculo que a transformação **não** tocou (hash
   idêntico). O alvo de teste agora carrega `profiles.json` como recurso (quatro partes coordenadas no
   `project.pbxproj`, verificado com `xcodebuild -list`, não com `plutil`) e o driver o resolve do próprio bundle.
   **Um caminho para os dois modos**, em vez de dois que diferiam exatamente onde o benchmark mede.

### 70. O disco é um insumo do benchmark, e ele se esgota sozinho

A primeira tentativa de rodar o B01 foi **recusada em 0,66 s**: *"the host volume has 295 MB free; a gate needs
about 3 GB"*. A recusa está certa por desenho — 464 MB livres já fizeram o app abortar aos 228 s de um gate de
trinta minutos, e isso leria como FAIL por falta de espaço, não de conteúdo — e **não se afrouxa o limite**; libera-se
espaço. O que ocupava, medido:

|onde|quanto|o que é|
|---|---|---|
|`bench/run/<stamp>/derived`|**990 MB**|build de uma corrida que **eu matei** — ela nunca chegou ao passo que limpa o próprio `derived`|
|`/tmp/fm-dd`|969 MB|derived data da minha sessão|
|`~/Library/Developer/CoreSimulator/Devices/<um só>`|**6,0 GB**|o volume de dados do iPhone 17 Pro Max, **`Booted`** pela bateria em curso — intocável|
|`~/Library/Caches`|331 MB|caches gerais|

Lição de operação: **corrida interrompida deixa produto de build para trás**, e é o maior resíduo do harness —
`rm -rf bench/run/*/derived` para quem não chegou ao fim. E `xcrun simctl delete unavailable` não libera nada
quando o volume grande é de um aparelho **em uso**: ali a ordem é esperar, não apagar.

### 71. A bateria na árvore de trabalho: 23 de 27 testes de UI falham, e a causa é uma linha

Medido na árvore de trabalho (HEAD `609ced6` + 47 arquivos modificados). Os números, com os comandos que os produzem,
porque o "baseline de 68" que estava registrado não correspondia ao comando do esquema:

|suíte|comando|resultado|
|---|---|---|
|pacote|`swift test`|**1103 de 1103**, zero falhas|
|unidade do app|`xcodebuild test … -scheme FeedMine` (bundle `FeedMineAppTests`)|**68 de 68**, zero falhas|
|benchmark|mesmo comando (bundle `FeedMineUITests`, `DiscoveryBenchmarkTests`)|5 de 5 **skipped** — opt-in, correto|
|UI do produto|mesmo comando (bundle `FeedMineUITests`)|**23 de 27 falham** (3 passam, 1 skip)|

**O esquema executa três bundles, não um.** O baseline registrado de "68 testes, 0 falhas" corresponde exatamente ao
bundle unitário, então não pode ter saído deste comando sem filtro — os logs de evidência de hoje foram todos obtidos
com `-only-testing` (41 e 7 testes), e nenhum deles exercitou `FeedMineUITests`. Isso vale corrigir no registro: o
número de 68 está certo como *unidade*, e não como *app*.

**A causa única, verificada linha a linha:**

- No HEAD, `AppComposition.init` traz `feeds: [TrustedFeed] = TrustedFeed.catalogOrDevelopment(limit: 64)`.
- Na árvore de trabalho, `AppComposition.swift:123` traz `feeds: [TrustedFeed] = []`.
- `catalogOrDevelopment` **não tem mais nenhum chamador** — só a definição. Era ela que lia
  `FEEDMINE_USE_DEVELOPMENT_FEEDS=1`, a única via pela qual os testes de UI obtinham conteúdo.
- `FeedMineApp.swift:10` constrói `AppComposition()` sem argumentos: o default decide com que fontes o leitor inicia.
- Com zero fontes não há card, e as 23 falhas morrem todas na **primeira** asserção, esperando 45–60 s por um
  `ScrollView` do feed. Os 3 que passam são exatamente os que não precisam de feed publicado de imediato: o que roda
  o onboarding e preenche o perfil, o do fixture de add-feed, e o da superfície de seleção vazia.

**O benchmark não é afetado por isso, e a distinção importa:** o driver do benchmark anda o onboarding e a
descoberta, não as fontes confiáveis. A corrida em aparelho de hoje mediu **188 fontes** no conjunto de aquisição,
vindas do catálogo injetado, com zero fontes confiáveis configuradas. Quem ficou vermelho foi a suíte de UI do
produto. Se "o app inicia sem fontes confiáveis" é decisão de produto da V2 — a descoberta substituindo o que a V1
chamava de fontes confiáveis — então os 23 testes estão velhos e precisam ser re-apontados para o caminho de
descoberta; se é estado transitório da escrita em voo, ninguém toca e se aguarda.

### 72. Os 23 testes de UI: o defeito era mais estreito do que a minha leitura

Eu propus ao arquiteto duas saídas — "é decisão de produto, então os 23 testes migram para a descoberta" ou "é estado
transitório, ninguém toca". Ele recusou as duas, e com razão: o defeito não é a arquitetura, é **uma ligação
perdida**. A configuração explícita de fixtures (`FEEDMINE_USE_DEVELOPMENT_FEEDS=1`) perdeu seu consumidor, e é isso
que deixou 23 testes sem conteúdo.

A correção, na forma que ele prescreveu:

- `AppComposition()` continua **sem seleção inicial** — a decisão F02/B01 permanece, e o comentário que a documenta
  ganhou a exceção explícita;
- `TrustedFeed.developmentSelection` restaura a injeção **somente em DEBUG e mediante a flag**;
- e ela é deliberadamente **não o catálogo**: restaurar a chamada antiga (`catalogOrDevelopment`) teria semeado o
  catálogo como seleção do leitor, que é literalmente a falha que o B01 nomeia — "o app exibe cards bonitos mas
  consulta somente a lista estática de quatro feeds". Uma flag de teste não pode reintroduzir o default que o próprio
  comentário proíbe. `catalogOrDevelopment` ficou sem chamador e foi removida.

**Nenhum selo precisou ser recongelado, e isso está medido, não suposto:** `MANIFEST.sha256` não cita nenhum arquivo
de `FeedMineApp/` (zero ocorrências), e `EVALUATOR.sha256` cobre o driver do benchmark
(`DiscoveryBenchmarkTests.swift`) e os instrumentos, não `AppComposition.swift` nem `TrustedFeeds.swift`. Os dois
selos verificam íntegros depois da mudança.

### 73. A bateria depois da correção: 23 falhas viram 2

Reexecutada na árvore com a ligação restaurada, com os comandos do esquema (que executa **três** bundles):

|suíte|antes|depois|
|---|---|---|
|`swift test`|1103 / 0 falhas|**1103 / 0 falhas**|
|`FeedMineAppTests`|68 / 0 falhas|**68 / 0 falhas**|
|`FeedMineUITests`|27 executados, **3 passando, 23 falhando**, 1 skip|27 executados, **24 passando, 2 falhando**, 1 skip|
|`DiscoveryBenchmarkTests`|5 skipped|5 skipped (opt-in, correto)|

A ligação de fixtures moveu **21 dos 23**. As duas que sobraram **já falhavam antes** da correção, então não vêm dela, e
são de causa própria — ambas com o mesmo cheiro, produto refatorado e teste parado, mas uma delas não me permite
concluir:

1. **`testOfflineRelaunchKeepsFilterSavedCardAndFeed` (linha 592)** espera `app.buttons["Salvar artigo"]` depois de
   pressionar o card. A lista de elementos da falha mostra o que existe ali: `identifier: 'card.bookmark', label:
   'Bookmark'`. O app **tem** "Salvar artigo" — em `Sources/FeedMineUI/Cards/FeedItemView.swift:80`, que é a linha de
   lista; o **card** foi refatorado para `FeedItemCardView` e expõe `card.bookmark` (linha 286). Leitura: expectativa
   velha contra o card novo.
2. **`testT6FilterSheetOpensAppliesAndKeepsTheReader` (linha 1192)** afirma que um chip da lente **não** é alcançável, e
   ele é. Aqui **não concluo**: `ReaderFilterLens.swift` mudou, e o comentário da linha 78 documenta uma interação
   *medida* sobre `lens-chip-*` e alcançabilidade. Pode ser expectativa velha — ou pode ser a única coisa ainda pegando
   uma regressão real. Não toco enquanto não souber qual das duas.

Essa distinção é o ponto: 21 falhas eram uma ligação perdida, com conserto óbvio; estas duas exigem saber se o produto
regrediu ou se o teste ficou para trás, e essa pergunta tem dono.

### 74. As duas falhas que sobraram: o arquiteto derrubou o meu diagnóstico nas duas

O §73 registra a minha leitura — "as duas são produto refatorado e teste parado". **Estava errada nas duas**, e o
arquiteto mostrou por quê. O registro fica com a correção, porque um diagnóstico errado que ninguém corrige é pior do
que nenhum.

**1. O menu do card existe, e o problema é o long press.** Eu vi `card.bookmark` na lista de elementos da falha e
concluí que a superfície tinha sido substituída. Não foi: `FeedItemCardView` **também** tem um `contextMenu` com
"Salvar artigo" (linhas ~337-341), e `card.bookmark` é **outro** controle. A presença de um não prova a ausência do
outro — e eu tratei correlação como substituição. A pergunta que eu devia ter feito é a que ele fez: **por que o long
press não abriu o menu?** Isso continua **aberto**, e é uma pergunta sobre o produto, não sobre o teste.

Para este teste — que mede persistência, não o menu — ele autorizou usar `card.bookmark` **dentro do card
identificado**, confirmando o estado e mantendo a verificação depois de reabrir. Feito, e mais forte do que estava:
o teste agora compara o `value` (`not bookmarked` → `bookmarked`) em vez de apenas tocar e seguir.

**2. A espera estava errada, não a exigência.** Eu li "o chip não é alcançável" como expectativa velha. O teste não
exige inalcançabilidade: exige que o chip **desapareça** quando o critério é removido — e para isso usava
`XCTAssertFalse(lensChip.waitForExistence(timeout: 5))`, que devolve **verdadeiro de imediato** enquanto o elemento
ainda existe. Uma asserção invertida construída sobre `waitForExistence` passa no instante em que a transição começa,
não quando ela termina. O mesmo defeito estava na espera do `filter-done`. Corrigidos com um auxiliar novo,
`waitForAbsence`, que espera a ausência de verdade — a exigência de remoção ficou intacta.

**3. E a ressalva dele é a parte que mais importa.** O registro de falha trazia também *"Failed to not hittable:
Button … 'lens-chip-language-en'"* — ou seja um **`tap()`** falhou por o chip não ser alcançável. Ele avisou: *"se o
erro for durante `tap()` por falta de alcançabilidade, essa correção não o explica nem resolve"*. Está certo, e por
isso o `tap()` ficou **como está**: um toque simples. Se ele voltar a falhar, é achado sobre o produto, e não algo que
se contorna com toque por coordenada — que é justamente como o `pressCard` contorna o mesmo problema no card, e que
aqui esconderia a resposta.

**Varredura, não conserto:** o anti-padrão `XCTAssertFalse(….waitForExistence(…))` aparece em **mais 2 lugares** neste
arquivo (um deles a linha 921). Não os toquei — estão fora do que foi autorizado — mas os dois são o mesmo defeito e
vão morder na mesma forma. Os `XCTAssertFalse(….exists)` que aparecem ao lado são corretos: `.exists` é instantâneo e
afirma o estado de agora, que é o que uma asserção negativa deve fazer.

**Adendo, mesmo dia, segunda vez.** Enchi o disco de novo — 121 MB livres — e desta vez o resíduo era meu: quatro
diretórios de build de verificações de UI (`/tmp/fm-fixcheck`, `fm-t6check`, `fm-t6check2`, `fm-rerun-app`), um
gigabyte cada. O `derived` de uma verificação de UI é tão descartável quanto o de uma corrida, e eu não os removi
porque cada um parecia pequeno quando o criei.

E a lição de §70 ganhou a metade que faltava. Quando o volume grande de um simulador está em uso, a ordem é esperar —
isso continua valendo. **Quando nada o está usando, a ordem é `xcrun simctl erase`**: 6,1 GB voltaram a 140 MB, sem
remover o aparelho (que é o que `delete` faria, e que obrigaria o Xcode a recriá-lo por nome on-demand). Medido:
121 MB → 4,3 GB livres, com uma chamada de `shutdown all` e um `erase`.

Sequência que funciona, para a próxima vez: (1) `rm -rf /tmp/fm-*` dos meus próprios builds; (2) `rm -rf
bench/run/*/derived` das corridas que morreram antes do passo 7; (3) `simctl shutdown all` e `erase` do simulador
grande **quando ninguém o usa**; (4) conferir `df` antes de disparar a corrida, porque o runner recusa em 3 GB e a
recusa chega em menos de um segundo.

### 75. Os 95,83 s da folha de filtros: medida, e defeito de produto

O §74 registrou "parada, não espera". A instrumentação dos oito passos aguardados — entrada, saída e erro em cada um,
feita por um subagente pelo método do arquiteto — mostrou que era **espera, e finita, e longa**:

|medida|valor|
|---|---|
|`activateCurrentPresentation`|**+95,253 s** (retorna; a cadeia completa e a folha fecha a 95,83 s do toque)|
|onde|`FeedRunwayDriver.drive()` → ramo `case .none:`: com `selectedSourceCoverage != nil`, **cada viagem** chama `acquisitionCycle.runCoverage(...)` e o laço drena todo o conjunto elegível antes de retornar|
|escala|`eligibleTargets = 167`, 2 alvos por viagem, **75 viagens / 142 buscas em 96 s**, 30 falhas, ~11 em voo|
|por que só depois do filtro|com `language=en` o pool de descoberta vira **120 fontes do catálogo com URLs remotas reais**; `FEEDMINE_LOCAL_FEEDS` só serve as 4 fixtures. Sem filtro o `drive` saiu em 3 viagens e 0,06 s|

**Veredicto do arquiteto:** há uma costura, e o fechamento **não** deve aguardar a drenagem inteira. "Aplicado" significa
identidade persistida, associação nova instalada e estado de apresentação coerente com o filtro — a construção da
associação leva 37,6 ms e isso basta para fechar. A aquisição continua depois, numa tarefa **pertencente à associação**,
com cancelamento ao fechar ou substituir a sessão, tratamento de erros e proteção contra publicações de uma associação
retirada. *"Não basta envolver o `launch()` atual numa Task solta."* E: *"ser finita não torna essa espera aceitável"*.

A costura fica na lane de composição/runtime; este trabalho não altera a drenagem para contornar o teste. Até a
correção, **o teste fica falhando com a medida registrada** — 95,83 s, e não uma espera inventada.

Erros meus no caminho, para não se repetirem: eu chamei isso de "parada" (era drenagem), propus espera longa como
acomodação (o arquiteto recusou: *"não aumente o timeout"*), e li a linha de falha de ontem como sendo do chip quando
era do fechamento da folha. As três correções vieram do contraditório, não de mim.

### 76. A disputa de gestos: causa, correção e as três provas

O §71 registrou dois sintomas sem causa: o bookmark com frame de 44×44 e ainda inalcançável, e o long press que não
abria o menu do card. A causa é uma só, e estava numa camada:

```swift
// FeedItemView, o wrapper que envolve o card
.accessibilityElement(children: .contain)
.accessibilityIdentifier(card.id.rawValue.uuidString)
.contentShape(Rectangle())        // o retângulo inteiro
.onTapGesture { emit(.open) }     // responde acima de tudo
```

Um `contentShape` do retângulo inteiro somado a um gesto de toque, **acima** dos controles internos. Era essa camada
que engolia o toque do bookmark e o long press do menu. A correção é estrutural, na forma que o arquiteto desenhou, e
não por prioridade de gesto — ele recusou explicitamente `highPriorityGesture` e "o card inteiro num Button", porque
os dois *mantêm* a disputa em vez de eliminá-la:

- o wrapper perde `contentShape` e o gesto, mantendo `.contain` e o identificador da ocorrência;
- `openingSurface` envolve **só** a superfície que abre o artigo; `contentSurface` (retrato) e `landscapeContent`
  (band) usam;
- o hero ganhou gesto próprio (mídia para áudio, artigo para o resto), porque a camada de cima não responde mais;
- bookmark, mídia e `contextMenu` são **irmãos** dessas superfícies;
- a linha compacta recebeu a ação de abertura **no wrapper**, e por gesto, não por Button: a objeção a gestos é que
  eles envolvem controles e roubam toques, e a linha não tem controle nenhum.

**Erro meu no caminho, medido:** a primeira versão embrulhou a linha num `Button` e alargou o card para **730,25 pt**
no passo de paisagem do iPad, contra o limite de 704 (700 de coluna legível + 4). O teste que passava passou a
falhar, e o `git`-antes/depois foi o que atribuiu a regressão a mim. Gesto próprio da linha: a geometria não muda.

As três provas, todas por teste que já existia:

|prova|teste|resultado|
|---|---|---|
|o long press **abre o menu** do card|`testT5HeaderChromeAndCardGestures…`|**PASS** — `Press … for 1.2 seconds` → o botão "Salvar artigo" aparece → é tocado|
|o bookmark é **alcançável e funcional**, sem filtro contaminando|`testFirstRunCollectsLanguagesAndPlaces…`|**PASS** — toca `card.bookmark` no caminho de primeira execução|
|a geometria do iPad **continua** correta|`testU1iPadLayoutPortraitAndLandscape`|**PASS** depois da correção do Button|
|o conteúdo abre e rola|`testT3ScrollAdmitsWithoutMovingTheReadingPoint`|**PASS**|
|a mídia age por conta própria|`testMiniPlayerStatesPlaybackWithoutMovingTheFeed`|**PASS**|

A única falha que sobrou na contraprova é a do teste de persistência offline, e ela é **consequência** do defeito dos
95 s, não do controle: o toque falha com `Computed hit point {-1, -1}` porque a folha de filtros ainda está aberta
por cima do card. Medir o bookmark ali seria medir o outro defeito.

### 77. Preparação do B06: o que falta, o que existe, e as duas dependências humanas

O protocolo (linha 98) é explícito sobre o que o B06 exige, e eu tinha mapeado menos do que ele pede:

> **Entrada:** executar **B03 também num iPhone físico** de referência compatível com o mínimo suportado, em sessões de
> grande volume; repetir no aparelho-alvo atual. **Obrigatório:** sem crash, terminação por memória, travamento de
> interface ≥1 segundo, vazamento de recurso com crescimento sustentado não explicado ou salto/duplicação de cards.
> **Coletar RSS do processo, CPU, memória, energia/térmica, frame hitches e tempo de scroll**; reportar picos e tendência
> após aquecimento. **NOT_RUN** se não houver aparelho. **Simulador não aprova esse gate.**

**O que o harness coleta hoje: nada disso.** A varredura por RSS/CPU/thermal/energy/hitch em `bench/run.sh`,
`bench/oracle.py` e no driver não encontra uma ocorrência. A coleta é a lacuna, e ela é nova — não uma correção.

**O que existe, verificado agora:**

|peça|estado|
|---|---|
|`xctrace` vendo o aparelho|**sim**: `iPhone (18.6.2) (00008110-00067D861486201E)` na seção `== Devices ==`|
|template para RSS/CPU/memória|**Activity Monitor**|
|template para frame hitches|**Animation Hitches**|
|template para energia|**Power Profiler**|
|o segundo aparelho que o B06 exige|`iPhone (129)` **iOS 26.5.2**, hoje **offline** (`00008120-000260903ED1A01E`)|
|o caminho de aparelho do runner|**provado hoje** (pareamento, injeção, re-assinatura, instalação, execução, banco de volta, oráculo)|

Uma correção de método que vale registrar: numa primeira sondagem eu concluí que o `xctrace` **não** via o iPhone, e a
conclusão era **minha**, não da ferramenta — eu tinha truncado a saída com `head -5` e cortado justamente a linha do
aparelho, que vem depois de uma seção que eu não sabia existir. Conclusão sobre ausência exige leitura inteira.

**O que falta construir, em ordem:**
1. **A coleta**: `xctrace record --device <udid> --template "Activity Monitor"` (e as gravações equivalentes para
   hitches e energia) lançada **junto** com a corrida de aparelho, com os resultados guardados no diretório da corrida
   e citados pelo relatório. Um template próprio que junte os três canais é preferível a três gravações, porque as
   três precisam ser **da mesma passagem**.
2. **B03 no aparelho** (a metade que o B06 herda): o runner sabe rodar B03, e o modo aparelho está provado; o que
   falta é a passagem de 30 minutos num iPhone — que é tempo, não engenharia.
3. **Uma janela que não morra**: trinta minutos de scroll contínuo com a tela acesa exige que o aparelho não bloqueie
   nem durma. Isso é decisão de configuração do aparelho, não do app.

**As duas dependências humanas, registradas e não bloqueantes:**
- **o toque na permissão de Rede Local**, na primeira busca do app pela LAN (sem ela a falha é silenciosa);
- **conectar o segundo iPhone** (`iPhone 129`, iOS 26.5.2), que hoje está offline e é o "aparelho-alvo atual" que o
  B06 manda repetir.

Nenhuma das duas bloqueia o resto: as provas de simulador, o S5 e os gates B01–B05 seguem sem elas.

### 78. S5 do lado do app: o manifesto entrou, e a PD-10 é mais exigente que o resumo do brief

Base: `609ced6d` nesta árvore; `d55fa6f1` em `origin/main` (o brief e a PD-10 são lidos do remoto, não copiados).

O §63 mediu a lacuna do G09 do lado do app. Esta sessão a fechou, e a primeira coisa que o trabalho corrigiu foi a
*leitura*, não o código: o brief descreve o gesto de S5 (instalar/reabrir, atualização válida e outra inválida), mas a
decisão **PD-10** (`docs/product/PRODUCT_DECISIONS_2026-10-09.md`, remoto, §"PD-10 — Repositório público é a
autoridade do catálogo gerenciado") fixa sete critérios de release que o resumo não carrega. Três deles mudaram o
desenho:

- **revisão monotônica**: `manifest.json` do repositório público traz `revision` como contador; revisão igual **não**
  provoca substituição, revisão menor é oferta velha e nunca regride o snapshot. O app **não** tem identidade
  paralela: o carimbo continua sendo o `catalogGeneration` derivado de `catalog_metadata.catalog_version`, que o
  `LegacyCatalogReader` agora reporta (`metadata()`).
- **esquema, inventário, tamanho e SHA-256 antes de construir**: cada OPML declarado é conferido por tamanho e
  checksum **antes** do passo de compilação; só depois de validação completa o snapshot é ativado. Um erro de rede,
  arquivo, esquema, integridade, compilação ou ativação preserva o snapshot anterior — o mesmo formato que o canal
  remoto do V1 já usava (`CatalogUpdateManifest`, `activate` com backup/rollback), agora do lado V2.
- **separação catálogo substituível × dados pessoais**: o dono instala num diretório próprio e **nunca** abre o
  `runtime.sqlite`. Isso é a frase do critério 6, e está provada por teste com os **bytes** do banco pessoal
  comparados antes e depois de uma rejeição.

**O que entrou** (`Sources/FeedMineComposition/`, sem camada nova: os quatro arquivos são o dono e seus valores):
`CatalogManifest` (o shape publicado, validado antes de qualquer leitura de bytes), `CatalogInstallation` (verificação,
ativação atômica, rollback e o ledger), `CatalogSyncPolicy` (a decisão das ~24 h e a regra de revisão monotônica como
valores puros) e `CatalogUpdateChannel` (um GET condicional, sem scheduler). O descritor que o build embarca,
`catalog.manifest.json`, viaja como recurso do módulo — a revisão pública (5), `sourceCount` (77.443) e o SHA-256 do
catálogo empacotado (`c2ae483a…`), que é o mesmo já registrado em `FeedMineApp/Resources/CATALOG.md`.

**O que ficou de fora, e por quê** — as duas restrições que o arquiteto confirmou vinculam o desenho:

1. **Sem segundo pipeline de aquisição nem scheduler paralelo.** Não há `Task`, timer, loop nem polling no dono; o
   canal faz um GET e devolve os bytes. Um *fetch* não é um pipeline, e nada foi conectado ao `launch()` do app.
2. **Fora da barreira de primeira apresentação.** A instalação do snapshot empacotado é **in-place** (o arquivo já
   está onde deve estar; nenhuma cópia de 118 MB) e o `installBundled` devolve o snapshot ativo sem reler o catálogo
   quando a revisão não mudou — então uma abertura quente não re-hasheia o asset. Mesmo assim, **o passo de verificação
   não foi ligado ao `AppComposition` nesta sessão**: ligá-lo em `launch()` faria a primeira apresentação pagar o
   hash de 118 MB, e ligá-lo em background seria o scheduler que a restrição 1 proíbe. A ligação é uma decisão de
   produto, e está declarada como pendente em vez de assumida.

**Prova**: 40 testes novos, todos passando; a suíte do pacote foi de **1103 → 1143 testes, 0 falhas**. O ledger
(`quarantine.jsonl`) é lido por `CatalogInstallation.ledger()` — revision, fingerprint, resultado, motivo e classe —
e é o que o relatório de preparação externo imprime. **O que não foi testado contra a realidade**: o conteúdo de
`wawasoft/feed-repository` (o manifesto público é citado pelo *contrato* do PD-10, não verificado byte a byte aqui) e o
canal de rede (nenhuma requisição real é feita nos testes). A remoção de fonte que apaga dado pessoal, a ativação em
aparelho e a verificação vencida disparada pelo host ficam para a ligação.

### 78. A execução documentada da build atual: B02 e B04 passam, B05 falha numa cláusula, B01 espera o perfil B

Corrida `bench/run/20261011T155701Z`, **12,6 minutos**, build atual, corpus congelado servido localmente, simulador
iPhone 17 Pro Max, transporte `127.0.0.1:8757`, commit `609ced6d`, 96 arquivos sujos (registrados na proveniência).

**O enquadramento importa, e o arquiteto corrigiu o meu:** isto **não** é a primeira execução de B01–B05 — há
vereditos medidos nos artefatos anteriores, e chamá-la de primeira apagaria prova que existe. É a execução documentada
**da build atual**, que verifica o estado corrente sem apagar nem ampliar o alcance das provas anteriores.

|gate|veredicto|cláusulas|
|---|---|---|
|B01|**NOT_RUN**|4 passam, 0 falham, 1 sem veredicto — "outro perfil muda as fontes consultadas" exige o perfil B, que não foi pedido|
|B02|**PASS**|5 de 5|
|B04|**PASS**|2 de 2, incluindo "nada do que o leitor já tinha se moveu, reordenou ou retratou"|
|B05|**FAIL**|1 passa, 1 falha|

**O estado do B01, que é mais informativo que o rótulo NOT_RUN:** 308 fontes no conjunto de aquisição, **88
efetivamente buscadas**, **67 chegando aos cards**, **388 cards publicados**. E a distinção que o arquiteto repetiu,
que vale como regra: **isso não é B01 PASS.** Infraestrutura validada, comportamento observado e contrato aprovado
são três coisas.

**O FAIL do B05 é de uma cláusula só, e ela é precisa:** `b05-reopen-keeps-saved: false`. O protocolo inteiro foi
caminhado — salvar, A→B→A, reabrir, offline — e todas as outras medidas passam (`b05-anchor-before`,
`b05-return-preserves-anchor`, `b05-reopen-preserves-anchor`, `b05-offline-shows-local`, `b05-offline-cards`,
`b05-saved`). O que falha é a **persistência do salvo depois de reabrir**: o leitor salva um card, o app reabre, e o
salvo não está lá. É defeito de produto, é de gate, e é reproduzível — o teste `testOfflineRelaunchKeeps…` cobre o
mesmo comportamento e já vinha falhando por outra razão (a folha de 95 s), o que significa que a metade de
persistência dele **nunca chegou a ser exercitada**.

### 79. O FAIL do B05: o estado é durável, a tela é que nasce sem ele

A cláusula que falha é uma só — `b05-reopen-keeps-saved: false` — e o caminho até a causa passou por duas hipóteses
**erradas**, o que vale registrar porque as duas eram atraentes:

1. *"a persistência perdeu o salvo"* — **falsa**. O banco da corrida tem `reader_bookmark_memberships` com **1 linha**;
2. *"o id do card mudou, a edição reaberta apresentou o mesmo artigo com identidade nova"* — **falsa**. O `card_id`
   salvo existe em `published_cards`, e não há fork de edição.

**A causa é uma linha que nunca roda no arranque.** A tela pergunta ao store:

```swift
isBookmarked: store.bookmarkedIDs.contains(card.id)   // FeedScreen.swift:82 e :125
```

e `installBookmarks` — o único método que preenche esse conjunto — tem **um único chamador**:

```swift
private func toggleBookmark(_ cardID: PublicationCardID) {
    ...
    store.installBookmarks(try publication.bookmarkedCardIDs())   // AppComposition.swift:1270
}
```

Ou seja: o conjunto de salvos é instalado **quando o leitor salva algo**, e **nunca quando o app abre**. O
`PublicationStore.bookmarkedCardIDs()` existe e lê `SELECT DISTINCT card_id FROM reader_bookmark_memberships`; ninguém
o chama no arranque. Consequência exata: o dado é durável, a *lista* de salvos funciona (ela lê o banco), e os
**cards nascem sem estado** — que é o que a cláusula do B05 mede.

Isso também explica por que o teste de UI que cobre o mesmo comportamento nunca pegou: ele verifica a lista de salvos
(`saved-article-*`), não o glifo do card, e a metade dele que reabre o app morria antes no defeito dos 95 s.

**Nota de método:** a primeira leitura do grep me fez concluir que a semeadura existia, porque vi
`store.installBookmarks(try publication.bookmarkedCardIDs())` e não olhei em que função ela estava. A linha certa e a
função errada. Ler a linha e concluir sobre o fluxo é o mesmo erro de antes, em outra roupa.

**CORREÇÃO do §79, no mesmo dia.** A conclusão "o conjunto de salvos nunca é semeado no arranque" está **errada**, e o
erro é o mesmo de sempre: vi a linha e não olhei a função. Há **dois** chamadores de `installBookmarks`, e o segundo
está exatamente no caminho de arranque:

```swift
// AppComposition.swift:1756, dentro de FeedAssociation.install(_ received: FeedPresentationState)
func install(_ received: FeedPresentationState) throws {
    guard active else { throw FeedPresentationStateError.projectionSequenceMismatch }
    try store.install(received)
    store.installBookmarks(try PublicationStore(database: database).bookmarkedCardIDs())   // <-- aqui
```

Ele roda **toda vez que uma apresentação é instalada**, inclusive numa reabertura. Ou seja: a semeadura acontece; o
defeito do B05 está em outro lugar, e o que sobrou de pé do §79 é apenas a parte medida: o dado é durável (1 linha em
`reader_bookmark_memberships`), o `card_id` salvo existe em `published_cards` (sem fork de identidade), e os cards
leem `store.bookmarkedIDs.contains(card.id)`.

Candidatos que **não** foram excluídos, e que precisam de medida, não de leitura:
1. a apresentação instala os cards com ids de um espaço diferente do `PublicationCardID` que o conjunto guarda;
2. o `install` roda, mas o card medido pelo driver pertence a uma janela apresentada antes dele;
3. os dois `installBookmarks` competem, e o segundo sobrescreve com um conjunto lido de outra sessão.

**Terceira repetição do mesmo erro de método nesta sessão** — e vale como regra dura, porque os três casos custaram
tempo: *linha vista não é fluxo entendido*, e *saída truncada não é ausência*. Os três: o `xctrace` que "não via" o
iPhone (era `head -5`), o `installBookmarks` que "só existia no toggle" (era `head -10`), e agora a semeadura que "não
existia no arranque" (era leitura sem contexto). Nas três, a ferramenta estava certa e a leitura estava curta.

### 80. O lost update no cano do projeto, e a recuperação medida

**O que aconteceu.** Dois escritores, um arquivo, uma janela. O agente do catálogo encontrou `RunwayTrace.swift`
sem entrada de compilação (defeito real: o build falhava com cinco `cannot find type 'RunwayTrace' in scope`) e
corrigiu, com as quatro partes coordenadas. Só que ele leu o arquivo **antes** da minha escrita e gravou a versão
dele **depois** — o padrão clássico de lost update. O resultado medido pelo `git diff` e pela comparação com uma base
guardada: o arquivo perdeu **oito declarações** — quatro pares de arquivos de teste (`…003F/40`, `…43/44`, `…45/46`,
`…47/48`) e o **par original do `RunwayTrace`** (`…00F7/…00F8`) — além do meu recurso `profiles.json`.

O detalhe que corrige o diagnóstico: **o `RunwayTrace` já tinha entrada de build na base**. O agente corrigiu um
sintoma de um arquivo já danificado, não a causa. A causa é a escrita concorrente.

**O que impediu o pior.** Uma cópia que eu tinha feito antes de editar o arquivo pela primeira vez
(`cp $P /tmp/pbxproj.bak`). A recuperação foi restaurar a base e reaplicar **só** as duas coisas que importam: o time
nos alvos de teste (quatro configurações) e o recurso `profiles.json` (quatro partes). O par do agente virou
duplicata na base e foi descartado.

**Verificação, não declaração.** Três medições depois da restauração:

|o que|resultado|
|---|---|
|o parser abre o projeto|`Targets: FeedMine, FeedMineAppTests, FeedMineUITests`|
|a build compila|`** TEST BUILD SUCCEEDED **`|
|o recurso aterrissa no bundle|`FeedMineUITests-Runner.app/PlugIns/FeedMineUITests.xctest/profiles.json`|
|a suíte do pacote|`Executed 1149 tests, with 0 failures` (baseline anterior: 1103)|

**Regra que passa a valer:** `project.pbxproj` é arquivo de **um escritor por vez**, e cada membro exige **quatro
partes coordenadas** — referência, build file, entrada no grupo e entrada na fase. Acrescentar sem conferir o que já
está lá custou uma corrida de benchmark quebrada e uma hora de recuperação. O agente concordou em não tocar mais nele.

**Terceira repetição do erro de leitura truncada, na mesma sessão.** `head -5` escondeu o iPhone do `xctrace`;
`head -10` escondeu o segundo chamador de `installBookmarks`; e agora um `tail -12` escondeu o resumo do XCTest atrás
do resumo do swift-testing. Os três foram resolvidos lendo de novo, com o filtro certo. A regra não é "cuidado com
grep": é **filtrar pelo que se quer saber, nunca pelo que se espera ver por último**.

### 81. G09 inspecionado: o canal público existe, e a ponte com ele não

O arquiteto condicionou o endosso do escopo a ler a PD-10 e o estado do repositório público. A PD-10 eu localizei
(§, remoto, `docs/product/PRODUCT_DECISIONS_2026-10-09.md:170`); o repositório eu inspecionei agora.

**`github.com/wawasoft/feed-repository`** existe, é público, MIT, mantido pela Wawasoft. O README descreve o fluxo da
PD-10 **palavra por palavra**: renderiza do último snapshot local válido, checa `manifest.json` em segundo plano,
copia revisão nova para staging, confere **cada OPML contra SHA-256 e tamanho**, reconstrói e valida o catálogo
SQLite/FTS, e **só então** ativa atomicamente — com falha de rede/XML/checksum/compilação/ativação deixando o
snapshot anterior intacto. E a regra de remoção: sai do catálogo gerenciado, fica em importados, salvos, histórico e
coleções. E: *"Do not edit a published revision in place; any catalog change must receive a higher revision."*

**O manifesto real, lido do raw:** `fileCount 118`, `generatedAt 2026-08-03T23:35:34Z`, **`revision 5`**,
`schemaVersion 1`, `sourceCount 77443`. Os 77.443 são exatamente o número que a PD-10 cita, e o formato casa campo
por campo com o `CatalogManifest` que o agente escreveu — incluindo o `supportedSchemaVersion = 1`.

**A lacuna que isso revela, e é de release:** o `catalog.sqlite` que o app embarca **não vem do canal público**. Vem
de um asset de release **deste** repo, tag `catalog-v1`, com SHA-256 fixo em `scripts/fetch-catalog.sh` — um catálogo
da V1. A PD-10 exige "snapshot verificável correspondente a uma **revisão pública conhecida**", e um catálogo V1 não
tem revisão pública a declarar. **É por isso que o descritor embarcado não existe**: não há revisão pública para
colocar nele. A ausência não era esquecimento do agente; era uma dependência não resolvida.

**Quem produz o descritor:** o README diz — o *publisher*, que sincroniza `Feeds/`, incrementa a revisão, calcula os
hashes e "writes the same bootstrap manifest into the next app build". E ele mora no **repositório da aplicação de
origem**. Neste repo não há `publish_catalog_update.py`; o candidato é o legado, que tem os scripts Python de
catálogo.

**Estado do G09, em três partes:** o lado do app está construído e verde (1149 testes, 0 falhas); o canal público
existe e está especificado; **falta a ponte entre os dois** — o publisher e o bootstrap — e ela não é trabalho de
Swift. Push para o catálogo público é ação externa e consequente, e não é minha para tomar.

### 82. A derivação do catálogo embarcado **não** se sustenta, e isso define a ponte

O arquiteto escreveu a proibição antes de eu tentar: *"não basta acrescentar 'revision 5' ao SQLite antigo sem provar sua
derivação."* Medi, e ele estava certo.

Comparação da árvore de OPMLs da V1 (`feedmine/feedmine/Resources/Feeds`, 118 arquivos) contra o manifesto publicado
(`wawasoft/feed-repository`, `main`, revisão 5), entrada por entrada — tamanho **e** SHA-256:

|resultado|contagem|
|---|---|
|idênticos|**1**|
|ausentes|0|
|divergentes (todos por tamanho)|**117**|

Os locais são **maiores**, com deltas pequenos e não uniformes (+59, +52, +20, +18, +15 bytes nos primeiros). Isso não é
formatação nem serialização: é uma revisão **diferente** da mesma árvore. O `catalog.sqlite` embarcado tem **77.443
fontes**, exatamente o `sourceCount` da revisão 5 — a contagem coincide, o conteúdo não. **Correspondência de número
não é correspondência de derivação.**

**O que o scout estabeleceu, e que torna a ponte barata:**

1. O compilador legado (`feedmine/scripts/build_catalog.py`) escreve **o mesmo esquema** que a V2 lê:
   `LegacyCatalogReader.supportedSchemaVersion = 2`, e o builder carimba `schema_version = "2"` com as tabelas
   `catalog_metadata`/`catalog_node`/`catalog_source`/`catalog_placement`. **Nenhuma divergência de tabela ou coluna.**
2. A identidade de fonte é um contrato **entre linguagens** (`scripts/catalog_identity.py`, `IDENTITY_CONTRACT_VERSION=2`),
   compartilhado pelo builder e pelo lado Swift.
3. A **única** incompatibilidade está no empacotamento: o manifesto do canal lista só os 118 OPMLs, e o caminho de
   instalação da V2 exige que ele declare **também uma entrada `.sqlite`**.
4. O manifesto publicado **não tem assinatura**, e a PD-10 proíbe inventar uma garantia que o canal não oferece.

**A ponte, na ordem que a medição impõe:** buscar o manifesto publicado e seus 118 OPMLs; conferir cada um contra o
manifesto (tamanho e SHA-256); rodar o compilador legado **sobre essa árvore publicada** — não sobre a local; gerar o
descritor embarcado com as 118 entradas **mais** a entrada do `catalog.sqlite`; empacotar **antes da assinatura**; e
provar, no bundle construído, a primeira abertura offline. Assim a proveniência é **provada por construção**, e não
declarada.

### 83. A ponte construída: catálogo derivado da revisão 5, com proveniência por construção

A prova de derivação falhou (§82: 1 de 118 OPMLs locais bate com o manifesto publicado). Então a ponte não podia partir
da árvore local. Partiu da publicada, e a ordem foi a que a PD-10 exige — **verificar o inventário antes de construir**:

|passo|resultado|
|---|---|
|buscar a árvore publicada (118 OPMLs)|**118 de 118 íntegros**, byte e SHA-256, zero divergentes, 62.373.804 bytes|
|identidade da árvore conferida|`76561622e78a7ca8`|
|compilar com o builder legado|**17,4 s**|
|relatório do build|`file_count 118`, **`source_count 77443`**, `node_count 6450`, `placement_count 77443`, `failed_file_count 0`, `duplicate_occurrence_count 0`, `invalid_source_count 0`|
|tamanho do catálogo produzido|117.993.472 bytes — **diferente** do embarcado (117.940.224), como a medição anterior já dizia|

Os números da saída **coincidem com o manifesto publicado**: 118 arquivos, 77.443 fontes. A proveniência aqui **não é
declarada, é construída** — a entrada foi conferida arquivo por arquivo contra o manifesto da revisão 5, e a saída
declara os mesmos totais. É a diferença entre dizer "este SQLite veio da revisão 5" e *tê-lo feito da revisão 5*.

E o custo surpreendeu: **17 segundos**, com o compilador legado reusado **sem alteração** — o scout tinha razão em
dizer que não há divergência de esquema, só de empacotamento.

**O que falta na ponte, na ordem:** gerar o **descritor embarcado** com as 118 entradas de OPML **mais** a entrada do
`catalog.sqlite` (bytes e SHA-256 do artefato recém-construído, `revision 5`, `schemaVersion 1`, `sourceCount 77443`);
empacotar **antes da assinatura**; e provar, **no bundle construído**, a primeira abertura offline. Cada um desses
passos tem um critério de release da PD-10 atrás dele.

### 84. O par catálogo + descritor está fechado, e a identidade é provada

O pipeline deixou em staging (`build/catalog-bootstrap/`, ignorado pelo git) o par que a PD-10 exige. Verificado agora,
contra as condições que o **validador da V2** de fato confere:

|condição|medido|
|---|---|
|`catalog_source` / `catalog_node` / `catalog_placement`|**77.443** / 6.450 / **77.443** linhas|
|`schema_version` carimbado no catálogo|**`'2'`** — igual ao `supportedCatalogSchemaVersion` do leitor|
|`sha256` declarado no descritor|**idêntico** ao do arquivo em disco (`72f06622…`)|
|forma do descritor|chaves `fileCount`/`files`/`generatedAt`/`revision`/`schemaVersion`/`sourceCount`, 119 entradas, todas com `path`/`bytes`/`sha256`|
|`revision` / `schemaVersion` / `sourceCount`|5 / 1 / 77443 — iguais ao manifesto publicado|
|`generatedAt`|**carimbado do manifesto publicado**, não inventado na hora da build|

O que **ainda não** está provado, e a distinção importa: nenhuma linha de Swift consumiu esse par. As condições acima
são as que o código *verifica*, e elas passam — mas **a prova de que o app usa o snapshot e o descritor só existe no
bundle construído**, e essa parte o arquiteto marcou corretamente como hipótese minha até ser demonstrada.

Falta, e cada passo exige a máquina quieta:

1. colocar o par no bundle **antes da assinatura** (substituindo o asset `catalog-v1`, que o próprio pipeline declara
   não descrever), com a entrada correspondente no `project.pbxproj` — quatro partes, arquivo de escritor único;
2. `scripts/fetch-catalog.sh` fica **obsoleto** nesse mesmo movimento: ele baixa o asset antigo com checksum fixo, e
   depois do bootstrap o caminho é o pipeline;
3. provar no bundle construído: o descritor empacotado, sua correspondência com o catálogo empacotado, e a primeira
   abertura funcionando **offline**.

**Nota ao §84, mesma hora.** O descritor ganhou o que o arquiteto pediu para não o deixar parecer cópia do
manifesto público: um bloco `derivedFrom` com a URL e o **sha256 real** do manifesto publicado, `revision` e
`opmlEntries: 118`; e um `role` em cada entrada — `opml` nas 118, `catalogue` na derivada. O `fileCount` continua
119, e o catálogo **não** foi regenerado.

O achado que vale mais: o descritor **fazia parte do portão de reuso**, então mudar sua forma obrigaria uma
recompilação e um novo checksum do catálogo — o oposto do que foi pedido. A causa foi corrigida: o portão passou a ser
apenas as saídas do compilador, e o descritor é derivado delas e reescrito de forma determinística. Consequência
verificada: `catalog.sqlite` e `build-report.json` mantiveram os checksums anteriores.

E a tolerância do decodificador foi verificada por inspeção, não presumida: `CatalogManifest` e `CatalogUpdateChannel`
não declaram `CodingKeys` nem `init(from:)`, então chaves desconhecidas são ignoradas e a igualdade de manifesto que
sustenta "revisão igual não substitui" não muda.

### 85. O FAIL do B05 é uma corrida do driver, não um salvo perdido

O §79 registrou quatro hipóteses falsificadas. A caçada instrumentada fechou o caso, e o resultado inverte o
enquadramento: **o salvo nunca se perdeu.**

**A medida decisiva**, de uma execução com o retrato instrumentado (`bench/run/20261011T164938Z`, que **passou**):

```
INSTALL-ENTRY  presented=-1 setBefore=0
INSTALL-SEED   set=1 presented=15 hits=1        <- o conjunto TEM o id, e a janela também
DECIDE 16207CF6=true  set=1
VIEW   16207CF6=true                            <- o card DO FEED, construído com TRUE
...
VIEW   16207CF6=false                           <- o MESMO id, construído de novo, e SEM nenhum DECIDE
```

A segunda construção não vem do feed: vem de `ReaderOnboardingView.swift:121` (`cardCascade`) e `:247`
(`previewZone`), que chamam `FeedItemView(card:appearance:isBookmarked: false, availableActions: [])` — **falso fixo**,
e com `availableActions` vazio o card **nem desenha controle de salvar**. As medições da mesma janela confirmam:
`previews=6 previewHasSaved=true`.

**A causa:** o relançamento do driver passa `FEEDMINE_ONBOARDING=1`, e o portão de primeira execução é apresentado
como `fullScreenCover` (`FeedMineApp.swift:441-443`). A cláusula acaba medindo se o botão do *feed* continua
alcançável **por baixo dessa cobertura** — corrida entre a consulta do driver e a apresentação do portão.

**A prova de que é corrida, e não perda:** a execução instrumentada **passou** (`b05-reopen-keeps-saved:true`), e a
execução que falhou tem outra diferença de porte — primeira abertura de **6 minutos / 19 segmentos** contra 39–43
cards de todas as execuções do agente. A cláusula é **instável**, e a instabilidade resolve em favor do produto quando
o tempo muda.

**O que isso significa, e não significa:** o produto está correto neste ponto — o dado é durável, o conjunto é semeado,
e o card do feed é construído com o estado certo. O que está errado é a **medição**: um gate que passa ou falha
conforme o tempo da cobertura é um gate que não mede o que diz medir. Decidir se a correção é no driver (o
relançamento não deveria forçar o portão) ou no produto (o portão não deveria cobrir o feed já restaurado) é decisão do
arquiteto, e nenhuma das duas se faz sem mudar artefato congelado — o driver está no `EVALUATOR.sha256`.

### 86. O par está no bundle, e o descritor descreve o arquivo que está ao lado dele

O bootstrap chegou ao bundle. O catálogo derivado da revisão 5 substituiu o asset `catalog-v1`, e o descritor foi
empacotado junto — antes da assinatura, como o arquiteto exigiu.

**Primeiro item da lista de prova dele, medido no bundle construído** (`** TEST BUILD SUCCEEDED **`):

|extraído de `FeedMine.app`|valor|
|---|---|
|`catalog.sqlite`|117.993.472 bytes, `sha256 72f066227958b482`|
|`catalog.manifest.json`|24.253 bytes, `sha256 5169715ad08b3727`|
|o descritor declara vs o arquivo ao lado|**correspondem**|
|`revision` declarada|**5**|
|papel da entrada do catálogo|`catalogue`|
|`derivedFrom.manifestSha256`|`2a4f754f8a8e839e…` (o manifesto publicado real)|

**Um erro meu no caminho, e vale registrar porque é o mesmo tipo de sempre:** a referência no projeto apontava
`catalog.manifest.json` quando o arquivo está em `Resources/catalog.manifest.json` — eu copiei o padrão do irmão
errado. O build recusou com uma linha exata (*"The file catalog.manifest.json couldn't be opened because there is no
such file"*), e a correção foi de uma palavra. O detalhe que confirma a troca do catálogo: **mesmo com o build
falhando, o `catalog.sqlite` dentro do app já era o novo** (117.993.472 / `72f06622…`) — a troca passou, faltava o par.

**O que falta da prova**, e é a metade mais difícil: os itens 2 e 3 da lista do arquiteto — instalação limpa **sem
snapshot anterior** e com **transporte realmente bloqueado** apresentando o feed a partir desse par, e o app
identificando a **revisão 5** como snapshot ativo com a verificação vencida **não bloqueando** a apresentação. Os
testes do pacote cobrem a *mecânica* com fixtures; a prova **de ponta a ponta no app construído** ainda não existe, e
o próprio arquiteto a marcou como a parte que ainda é hipótese.

E `scripts/fetch-catalog.sh` fica **obsoleto** neste mesmo movimento: ele baixa o asset antigo com checksum fixo, e o
caminho agora é o pipeline.

### 87. A cláusula do B05 é declaração de medição inválida, e o arquiteto fixou o procedimento

**Decisão do arquiteto:** a correção é no **driver**, abrindo uma nova revisão do avaliador — removendo a imposição de
onboarding **na reabertura**, preservando-a na **instalação inicial** que mede essa jornada. Razão: a evidência separa
os fatos (o salvo está persistido; o card restaurado recebe `true`; a cláusula consulta uma superfície coberta por um
portão **imposto pelo harness**), e *"alterar o produto para satisfazer essa consulta não seria justificado"*.

**O que isso NÃO autoriza:** mudar o instrumento congelado e reaproveitar a corrida. O procedimento que ele fixou:

1. preservar os artefatos e registrar a cláusula afetada como **medição inválida**, *sem convertê-la retroativamente
   em PASS*;
2. documentar a correção, revisar o diff e **recongelar o avaliador** antes da próxima corrida;
3. **reexecutar o B05 inteiro**, mantendo as exigências de identidade do salvo, reabertura e bloqueio real de
   transporte — e o driver deve **identificar a superfície do leitor antes de consultar seu controle**.

**Registro proposto por ele, e é este que vale** (literal):

> Correção de medição: a reabertura de B05 forçava onboarding e consultava o feed sob uma cobertura, produzindo
> resultado dependente do timing. A instrumentação demonstrou o estado salvo presente e aplicado ao card restaurado.
> A nova revisão remove essa imposição apenas da reabertura, sem alterar os critérios de persistência. Resultados
> anteriores da cláusula afetada não são reutilizados.

E a ressalva que impede a correção de virar desculpa: **se o portão aparecer numa reabertura sem imposição do harness,
é achado de produto, separado.** A cláusula afetada, portanto, não fica "amarela": ela fica **inválida como medida**,
e o B05 será medido de novo inteiro.

**Consequência prática para o `bench/run.sh` e o driver:** o relançamento de B05 não deve impor `FEEDMINE_ONBOARDING=1`,
e a consulta do controle do card deve ser precedida da identificação da superfície do leitor. Ambos são mudanças
deliberadas em artefato selado — vão com a documentação, o diff revisado e o recongelamento, nunca como ajuste
silencioso.

### 88. G09 está construído e **não consumido** — medido, não suposto

O scout verificou as fatias V1-gold contra o **código**, e o achado que importa é uma ausência: o dono do lado do app
para G09/G10 — `CatalogManifest`, `CatalogInstallation`, `CatalogSyncPolicy`, `CatalogUpdateChannel` — **está
construído e verde, e não tem nenhum chamador em produção**. O app continua abrindo o `catalog.sqlite` embarcado
direto (`AppComposition.swift:101, 239, 595`), então **não há caminho de verificação no arranque nem de atualização**.

É exatamente a hipótese que o arquiteto marcou — *"a integração precisa demonstrar que o app realmente usa o snapshot e
seu descritor"* — agora com a medida do lado oposto: o app **não usa**. O par está empacotado e provado dentro do
bundle; o consumidor é que falta.

**E há uma contradição interna junto dela.** Existem **dois descritores**, e eles discordam:

|descritor|declara|
|---|---|
|`FeedMineApp/FeedMineApp/Resources/catalog.manifest.json` (o do app)|revisão 5, 77.443 fontes, `fileCount 119`, catálogo `72f06622…` / 117.993.472 B|
|`Sources/FeedMineComposition/Resources/catalog.manifest.json` (o do módulo)|revisão 5, `fileCount 1`, catálogo `c2ae483a…` / 117.940.224 B — **o asset V1 antigo**|

`CatalogInstallation.init(appDirectory:)` mistura os dois — cataloga do `.main` e descritor do `.module`. Os números
abaixo do empacotamento estão certos e o módulo carrega uma cópia vencida.

**O resto do mapa, medido:** **G05** não implementa busca por token, negação ou escopo — a consulta é uma substring
literal sobre título e resumo (`Sources/FeedMineEditorial/CandidateProvider.swift:65-71`), e `searchScope` nunca é
consumido; **G01** (exploração de fontes dentro do app e ação card→coleção) não começou, com `.addSourceToCollection`
definido na UI e recusado pelo host (`ReaderActionCoordinator.swift:78-82`); **G07/G14** segue o bloqueador dos 95 s
(`FeedRunwayDriver.swift:300-306`); **G02–G04, G11–G13 e G15** estão em grande parte presentes.

**A próxima fatia, pela régua que o conselheiro fixou** — bloqueador de release primeiro: é **S5/G09**, e o que falta
nele é a **ligação**, que é fina e já desenhada. Não é reescrever a fatia; é fazer o app usar o que ele já empacota.

### 89. A auditoria dos sete critérios da PD-10: uma causa, sete lacunas

Dois agentes independentes chegaram ao mesmo lugar por caminhos diferentes — o scout das fatias e a auditoria da PD-10
— e o resultado converge: **o dono do lado do app para o catálogo gerenciado está construído, verde e sem chamador.**
A varredura é literal: `CatalogInstallation`, `CatalogUpdateChannel`, `CatalogSyncPolicy` e `.bootstrap(` não aparecem
em nenhum ponto de produção em `FeedMineApp` nem em `Sources`; o que existe são definições e testes. A raiz da
composição lê `Bundle.main`'s `catalog.sqlite` **direto em oito lugares** (`AppComposition.swift` 101, 166, 239, 595,
787, 853, 890, 919, 1255).

|critério da PD-10|evidência hoje|estado|
|---|---|---|
|1 release embarca snapshot verificável|medição no bundle construído (§86)|**provado**|
|2 local primeiro, inclusive offline|black-box existe e passa, mas pelo caminho de leitura direto, **não pelo dono da PD-10**|parcial|
|3 revisão igual não substitui|teste de mecanismo com fixture|parcial|
|4 adição/remoção reflete só no gerenciado|—|**sem evidência**|
|5 manifesto inválido mantém a última cópia|teste de mecanismo|parcial|
|6 dados pessoais intactos|teste de mecanismo|parcial|
|7 verificação vencida disparada sem bloquear|a *decisão* é testada; **o disparo não existe**|parcial|

**A distinção que a auditoria fixa, e que o projeto exige em palavras:** "Done de uma mudança" pede **teste unitário
para a semântica E prova black-box da jornada que realmente é ofertada**. Os 39 testes de catálogo são excelentes como
*unidade*; nenhum deles prova a jornada, porque a jornada não chama esse código.

**Três inconsistências de dívida, deixadas pelo meu próprio cutover de hoje:**

1. `Sources/FeedMineComposition/Resources/catalog.manifest.json` (o descritor do **módulo**) ainda declara o asset V1
   — `fileCount 1`, `c2ae483a…`, 117.940.224 B — enquanto o do app declara o reconstruído;
2. `Tests/FeedMineCompositionTests/CatalogManifestTests.swift:41-56` **afirma** o asset V1 antigo como o descritor
   embarcado — ou seja, o teste passou a fixar o estado que eu aposentei;
3. `FeedMineApp/FeedMineApp/Resources/CATALOG.md` e o corpus do benchmark ainda descrevem o asset antigo.

**Consequência para a próxima sessão, e é uma frase:** ligar o app ao dono que ele já tem resolve os critérios 2–7 de
uma vez, e reconciliar os três lugares acima é parte da mesma mudança — não trabalho separado.

### 90. O plano da ligação: onde plugar, em que ordem, e a pré-condição da prova

O scout devolveu o plano com arquivo e linha. O essencial, para a próxima sessão não redescobrir:

**1. O dono é `AppComposition.init`, no topo, antes da linha 166.** É o composition root único e já é `@MainActor`;
`CatalogInstallation.bootstrap()` é síncrono e local (sem rede, sem scheduler), então cabe em `init`. Os outros
candidatos foram recusados com razão: `FeedMineApp.swift:480` (antes de `launch()`) é **tarde demais**, porque `init`
já resolveu `feeds` na linha 187 pelo catálogo antigo, e view não é dona; `FeedMineBootstrap.swift` é scaffold sem API
e criar ali seria **camada nova por conveniência**; tipo novo, proibido.

**2. O estado que a mudança acrescenta não é camada, é valor:** um `catalogueURL: URL?` preenchido em `init`. Os
**nove** sítios que hoje re-derivam `Bundle.main` (`AppComposition.swift:101, 166, 239, 595, 787, 853, 890, 919, 1255`)
passam a ler esse valor, e `TrustedFeeds.swift:89-92` recebe a URL **por parâmetro**.

**3. A ordem:** instalação antes de `:166`; `:166` passa a checar o **resultado da instalação**; `:187` resolve pelo
snapshot; os sítios posteriores leem o mesmo valor com **comportamento idêntico**. E uma decisão explícita: a
**oportunidade de atualização** (`CatalogSyncPolicy` + `CatalogUpdateChannel`) **não entra em `init` nem na barreira de
primeira apresentação** — é decisão separada, para `foreground()`.

**4. A reconciliação, e ela é pré-requisito da prova:** o descritor do **app** está correto; o do **módulo**
(`Sources/FeedMineComposition/Resources/catalog.manifest.json`) está vencido com o asset V1. Quem o lê hoje: só
`CatalogManifestTests.swift:45` e o `CatalogInstallation.init(appDirectory:)`, que mistura `catalogueBundle: .main` com
`descriptorBundle: .module`. O do módulo **deve desaparecer**, com o teste passando a um fixture próprio (os helpers
`makeCatalogue`/`manifestData` já existem em `CatalogInstallationTests`). E `fetch-catalog.sh` e
`FeedMineApp/Resources/CATALOG.md:5` são limpeza do mesmo movimento.

**A pré-condição, que é o achado mais útil do plano:** *sem* a reconciliação, `bootstrap()` cai no **caminho
degradado** e grava `deferred` ("serving the bundled catalogue unverified") em vez de `bootstrapped` — e a prova
falharia **por configuração, não por comportamento**. Um teste que afirmasse "revisão ativa 5" seria um falso negativo
que parece defeito de produto.

**5. A prova, e onde o estado mora:** ledger em `<appDirectory>/catalogue/quarantine.jsonl`, cada linha um
`CatalogRevisionRecord` com `revision`, `fingerprint`, `outcome` (`bootstrapped|activated|rejected|deferred`), `reason`,
`kind`, `at`; ponteiro ativo em `<appDirectory>/catalogue/active.json` (`CatalogPointer.cataloguePath`). O teste:
reaproveitar `testCleanInstallPresentsTheBundledCatalogueSourceWithTransportBlocked` (`FeedMineUITests.swift:196`) e
depois asserir, no ledger, último registro com `revision == 5` e `outcome == "bootstrapped"`, e `cataloguePath`
terminando no `catalog.sqlite` do bundle.

### 91. Existe um `## B05 — PASS` na árvore que **não** é um PASS

A matriz de distância até a release exigida pelo conselheiro encontrou, ao varrer as corridas, uma
`bench/run/20261011T165305Z` com **`B05 — PASS`** e todas as medidas verdadeiras. E levantou a dúvida certa: ou eu
estava desatualizado, ou aquela corrida não era canônica.

**A canonicidade tem resposta objetiva, e ela é não.** Cada corrida registra, no seu próprio `inputs.sha256`, o hash do
driver que usou:

|o que|valor|
|---|---|
|driver que a corrida `165305Z` usou|`071c7a768d2569ad…`|
|driver **depois da correção** (hoje)|`ad68a59d…`|
|mtime do driver corrigido|**10:01:38** local|
|mtime do `EVALUATOR.sha256` regerado|10:01:48|
|quando a corrida rodou|**16:53:05Z = 09:53 local** — **oito minutos antes**|

Aquela corrida é uma das reexecuções instrumentadas do caçador, com o driver **anterior** à correção. Ela prova o que
o caçador precisava provar — que o salvo não se perdia e que a cláusula era dependente de tempo — e **não** serve como
veredito do gate. O PASS do B05 continua **não emitido** na build atual, e é isso que a reexecução canônica vai decidir.

**Lição de método, e vale para a próxima sessão:** um veredito só é canônico se a corrida que o produziu verificou a
revisão **vigente** do avaliador. Comparar o `inputs.sha256` da corrida com o `EVALUATOR.sha256` de agora é meia dúzia
de linhas e resolve a dúvida que o relatório não responde — o `evaluator.check` só imprime `OK`, nunca o hash.

**E o que a matriz entregou como quadro:** B02 e B04 PASS na build atual; B01 NOT_RUN por falta do perfil B (estado
medido 308/88/67/388); **B03 sem medida na build atual** — o último PASS é de `043906Z`, anterior à mudança da política
de runway, e o próprio registro de aceitação o declara *stale*; B05 esperando a reexecução canônica; B06 NOT_RUN. Na
PD-10: **um critério provado**, cinco parciais por falta de ligação e **um sem evidência** (o quarto — adição/remoção/
edição refletida só no catálogo gerenciado e em trabalho futuro).

### 92. A prova black-box: o par é real no bundle, e **não** é o que o app usa

O agente escreveu um teste de ponta a ponta e o rodou três vezes. **Passou** (`** TEST SUCCEEDED **`, 64,5 s): instalação
limpa, namespace nunca escrito, `FEEDMINE_BLOCK_RSS_NETWORK=1` **antes** do lançamento, e a fonte escolhida **pela
própria superfície do app** — não por flag.

|medida|valor|
|---|---|
|da instalação limpa à primeira superfície|**4,9 s** (com o transporte bloqueado)|
|da seleção do leitor ao primeiro card|**7,2 s**|
|o que os cards publicados dizem|`source_display_name = "BBC News"` — o título **do catálogo**|

O último número é a discriminação: o documento servido se chama "BBC Science", e a lista de development feeds (não
usada) também diria "BBC Science". Um card que se atribui a **"BBC News"** só pode ter obtido a atribuição **pelo
catálogo empacotado**.

**E o critério 3 da lista do arquiteto não é asseverável — o que é a resposta correta, não um fracasso do teste.** O
app **não tem caminho de runtime que leia o descritor ou o ledger**: `CatalogInstallation.bootstrap()`/`installBundled()`
não têm chamador, então nenhum `<runtime>/catalogue/quarantine.jsonl` e nenhum `active.json` é escrito, e
`catalog.manifest.json` **nunca é aberto** por código de app. A revisão 5 existe no descritor e em nenhum lugar em
runtime. A verificação vencida também não é exercida, porque não há disparo para vencer — e a apresentação não
bloquear é provada por outro caminho: **4,9 s com o transporte bloqueado**.

**Três achados que os testes de mecanismo não podiam dar:**

1. **O catálogo carrega fontes, não artigos** — 77.443 fontes, zero artigos; todo card exige busca. Uma instalação
   limpa sem fonte escolhida apresenta sua superfície vazia em ~5 s e não publica card. Isso é **comportamento
   desenhado** (F02/B01, "nenhuma seleção inicial"), não defeito.
2. **Medição guardada da primeira versão do teste:** ligar a seção inteira "Nature & Animals" — **348 chaves** — com o
   transporte bloqueado **não publicou card em 900 s**. Banco daquela corrida: 188 alvos registrados, **0 origens**,
   **0 cards publicados**, e a tela ainda em *"Preparando seu feed. Conversando com 2 fontes."* A única fonte que o
   transporte local responde está na **posição 111 das 348** selecionadas, e cada busca bloqueada paga o timeout de
   20 s do app, com cerca de duas em voo. É comportamento observado e vale como medida — não como veredito de gate.
3. **Defeito de UI achado e não corrigido** (não era do escopo dele): uma linha de **seção** na folha de fontes nunca
   declara a seleção que acabou de fazer. `SourceManagementStore.isNodeEnabled` lê `countryKeys`/`nodeChildKeys`, e
   `load()` nunca preenche as chaves de seção raiz — então o switch de "Nature & Animals" leu `0` e ficou `0` enquanto
   o toque habilitou de fato as 348 chaves. Linhas de fonte individual e de país se declaram corretamente.

**Fronteira respeitada, e verificada por ele:** só `FeedMineAppTests/FeedMineUITests.swift` foi tocado; `bench/`, o
`project.pbxproj` e o driver ficaram intactos, e `shasum -c bench/EVALUATOR.sha256` verifica **OK** em todos os selados.

### 93. B05 fechado: PASS canônico na build atual

Reexecução completa, com o driver corrigido e o `EVALUATOR.sha256` regerado. Corrida `bench/run/20261011T174133Z`.

```
verdict: PASS
  True | o protocolo de B05 foi caminhado (salvar, A→B→A, reabrir, offline)
  True | zero perda silenciosa de estado      <- a cláusula que falhava, com falhas: []
```

`b05-reopen-keeps-saved: true`, `b05-reopen-preserves-anchor: true`, `b05-return-preserves-anchor: true`,
`b05-offline-shows-local: true`, `b05-offline-cards: true` — todas as medidas verdadeiras, nenhuma falha.

**Canonicidade conferida antes de chamar de PASS**, pela disciplina que a §91 estabeleceu — a corrida registra o hash do
driver que usou, e ele bate com o selo vigente e com o arquivo em disco:

|onde|hash do driver|
|---|---|
|`inputs.sha256` da corrida|`ad68a59d…`|
|`bench/EVALUATOR.sha256` (vigente)|`ad68a59d…`|
|arquivo em disco|`ad68a59d…`|

E o selo do corpus (`bench/MANIFEST.sha256`) verifica. O que isso encerra: a cláusula que falhava era **medição
inválida** — o relançamento forçava o portão de primeira execução e a consulta media uma superfície coberta —, a
correção foi no driver, e a medição de agora é a prova. **O PASS anterior (`165305Z`) continua não sendo PASS**, pelos
oito minutos de diferença no hash; este é.

### 94. A ligação do catálogo está feita — **e ainda não compila**

O plano do §90 virou código, por um agente que trabalhou com a proibição explícita de compilar (o gate B03 estava
medindo paralisações ao mesmo tempo). **Status honesto: escrita, não verificada.** Compilar é o primeiro passo depois
que o B03 terminar.

**Sete arquivos:**

|arquivo|o que mudou|
|---|---|
|`CatalogInstallation.swift`|`init(appDirectory:)` passa `descriptorBundle: .main` em vez de `.module`|
|`AppComposition.swift`|`catalogueURL` guardado no `init`; `bootstrap()` chamado antes de qualquer leitura; a linha 166 testa o resultado da instalação; os nove sítios leem o valor guardado|
|`TrustedFeeds.swift`|`resolveAvailable` ganha o parâmetro `catalogueURL:` — **sem default**, para obrigar cada chamador a decidir|
|`CompositionTests.swift`, `AddFeedTests.swift`|os dois chamadores app passam a URL que já usavam|
|`CatalogManifestTests.swift`|o teste deixa de fixar o asset V1 e passa a construir fixture e exercitar `decode`/`validate`|
|`Resources/catalog.manifest.json` (do módulo)|**deletado**|

**A causa que o agente nomeou, e que era a armadilha prevista:** com `catalogueBundle: .main` e
`descriptorBundle: .module`, a verificação comparava o descritor **V1 do módulo** contra o catálogo **reconstruído do
app** — rejeição garantida, e o `bootstrap()` cairia sempre no caminho degradado registrando `deferred`. Um teste que
afirmasse "revisão ativa 5" seria um falso negativo que parece defeito de produto.

**O que ainda não está provado, e é a metade que importa:** que isso compila, que o `bootstrap()` registra
`bootstrapped` com `revision 5` no ledger, e que a jornada do app passa a exercitar o dono. Os critérios 2–7 da PD-10
dependem exatamente dessas três coisas.

### 95. B03: 4126 avanços, zero repetição — e **uma** paralisação de 1,56 s derruba o gate

Corrida `bench/run/20261011T174453Z`, 1828 s (30,5 min), `--full-trace`. Veredito: **FAIL**, por uma cláusula.

|cláusula|medido|esperado|veredicto|
|---|---|---|---|
|trinta minutos de avanço com oferta suficiente|**4126**|1.800|pass|
|zero repetição para disfarçar falta de oferta|0|0|pass|
|zero pares consecutivos da mesma fonte no trace|0|0|pass|
|**zero paralisação visível ≥1 s por falta de runway**|**1**|0|**FAIL**|
|prontidão de cada candidato registrada|2146 (todos texto, 0 pendentes)|—|pass|

**Onde a parada está, e onde não está.** Reproduzi a regra do oráculo sobre o `trace.jsonl` do app (16937 eventos,
4126 avanços, 4133 admissões) e ela dá **exatamente 1** — bate com o veredito. A parada é em **t+343,77 s**, com
**1,56 s** até a próxima admissão. A primeira admissão acontece em t−1,23 s, **antes** do primeiro avanço, então **não
há parada de arranque**: ela é no meio do feed, e o excedente sobre a barra é de **0,56 s**.

**A tensão que precisa de decisão antes de virar defeito de produto:** a cláusula diz *"zero paralisação visível ≥1 s
**por falta de runway**"*, e a regra implementada conta **qualquer** avanço sem admissão em 1 s. As duas coisas não são
a mesma: uma admissão **lenta** e uma **ausência de oferta** produzem o mesmo número. O corpus declara 231
`slow_media_sources` e classes de falha (`intermittent` 265, `slow` 287, `timeout` 131) — ou seja, atraso simulado é
parte do material. E a prontidão registrada diz **2146 candidatos, todos texto, 0 preparados**, o que é consequência do
ambiente local (sem mídia real), não do app.

O oráculo é congelado e o dado é o dado — a medição vale. O que **não** está estabelecido é se "falta de runway" e
"admissão lenta" devem contar igual. Isso muda o que a próxima correção é: consertar o abastecimento do feed, ou
reconhecer que a régua mede duas coisas diferentes com um número só.

### 96. O veredicto do B03 na régua, e um furo do harness: o traço bruto não é preservado

**O arquiteto decidiu a régua, e decidiu contra a saída fácil.** Admissão lenta e ausência de oferta **contam igual**,
desde que tenham impedido o leitor de avançar para conteúdo pronto por ≥1 s: *"ter candidatos no pool não basta —
oferta que ainda depende de admissão não é runway disponível ao leitor. Os atrasos do corpus fazem parte do desafio,
não são uma exceção à régua."* Não autorizou descontar "admissão lenta" nem elevar a barra.

**Mas ele achou uma nuance que eu não tinha visto, e ela é do oráculo:** *"1,56 s até a próxima admissão não prova,
sozinho, paralisação visível. Conferi o oráculo: ele procura a admissão seguinte a cada avanço, **sem verificar se já
havia um próximo card admitido e alcançável**."* Se havia oferta utilizável e só a reposição demorou, é **falso
positivo do instrumento** — e corrigir exige diff documentado, nova revisão congelada e nova corrida, nunca ajuste
silencioso. Se o leitor ficou **sem** próximo card, é **falha de produto**, inclusive com admissão lenta como causa.

**O procedimento que ele fixou:** preservar o FAIL como está, e examinar a janela de t+343,77 s perguntando se havia
próximo card pronto e alcançável, e se o gesto avançou, ficou bloqueado ou mostrou preparação.

**O furo que impede isso agora:** o `trace.jsonl` do app vive no container de dados do simulador, e o runner **não o
copia para o diretório da corrida** — o oráculo o lê no lugar. O app foi reinstalado pelos testes que rodaram depois, e
**o traço daquela corrida não existe mais**. A pergunta do arquiteto não tem mais de onde ser respondida neste run.

É precisamente o que o conselheiro exigiu preservar (*"preservar build SHA, hashes, trace bruto e classificação de cada
cláusula"*), e o que **falta no harness**: o diretório da corrida guarda `report.md`, os verdicts, `phases`, a captura
e a identidade — mas não o traço bruto, que é a evidência de todas as cláusulas de continuidade. O caminho de aparelho
já puxa o banco de volta; o caminho de simulador **lê o traço no lugar e o perde quando o container é substituído**.

**Consequência:** a atribuição da paralisação precisa de **nova corrida** com o traço copiado para o run, e a cópia é
mudança no `bench/run.sh` — arquivo selado, logo com documentação, diff e recongelamento.

### 97. A ligação está provada, e a dívida que ela cria

**O app agora usa o dono que ele já empacotava.** Compila, e as duas metades da prova passaram:

|onde|resultado|
|---|---|
|compilação|`** TEST BUILD SUCCEEDED **`|
|suíte do pacote|**1149 testes, 0 falhas** (o teste do descritor reescrito passou)|
|black-box com a ligação|**passou**, 64,4 s — o app apresenta o par empacotado com o transporte bloqueado|
|a asserção vencida do bundle|**corrigida na forma certa**, e passando|

**Dois erros meus no caminho, ambos de escopo.** O primeiro: o agente editou um sítio de `sourcePage` que pertence a
`FeedAssociation`, não a `AppComposition` — o valor existia na outra classe. A correção seguiu o idioma do próprio
plano: o `FeedAssociation` **recebe** `catalogueURL` no construtor, **sem default**, para que esquecer seja erro alto e
não silêncio. O segundo: a asserção de `CompositionTests.swift:188` fixava o hash do asset V1. Trocar por outro literal
seria repetir o defeito — o teste passou a verificar a **propriedade da PD-10**: o arquivo que o app carrega é o que o
descritor dele declara, com o tamanho real e a contagem vinda do descritor. Ele sobrevive a um re-bootstrap legítimo e
continua pegando um arquivo errado.

**A dívida que a mudança cria, e é do conselheiro a regra:** *"se o código mudar … haverá necessidade de verificar que
o comportamento continua válido. Os seis PASS de release precisam se referir a uma candidata coerente."* O B05 canônico
foi medido **antes** desta ligação. Ele precisa ser remedido na build que agora existe, e o B03 também — este último
pedindo primeiro o conserto do harness, porque **o traço bruto não é preservado** (§96) e sem ele a atribuição da
paralisação de 1,56 s não tem de onde ser respondida.

**O que ainda falta na PD-10, medido:** o critério 4 (adição/remoção/edição refletida só no catálogo gerenciado e em
trabalho futuro) segue **sem evidência**, e a oportunidade de atualização — `CatalogSyncPolicy` + `CatalogUpdateChannel`
no `foreground`, fora da barreira de primeira apresentação — é o próximo passo para que a identidade da revisão
**governe** de fato, que é o que o conselheiro exigiu, e não apenas seja registrada.

### 98. A ligação está viva, o ledger prova — e o harness injeta metade de um par

O B05 remedido na candidata nova **passou** (corrida `20261011T182906Z`, todas as medidas verdadeiras), e o traço
aparece **dentro da corrida** — os dois consertos de hoje funcionam. Mas o que a corrida revelou é outra coisa:
apareceu um diretório `catalogue/` no container do app, e dentro dele o ledger.

```
{revision: 5, outcome: rejected, reason: "size mismatch for catalog.sqlite:
                                         declared 117993472, present 3719168", kind: payload}
{revision: null, outcome: deferred, reason: "serving the bundled catalogue unverified:
                                         no verified snapshot is installed", kind: degraded}
```

**O que isso prova, e é muito:** o `bootstrap()` **roda no app de verdade**; o ledger é escrito; a **recusa** funciona;
e o **modo degradado é declarado**, não fingido — *"serving the bundled catalogue unverified"*. É a primeira vez que o
caminho de rejeição da PD-10 executa de ponta a ponta, e ele executou sem ninguém pedir.

**O que isso expõe:** o runner **injeta** `bench/corpus/catalog.sqlite` (3.719.168 bytes) sobre o bundle do app,
enquanto o descritor declara o catálogo do bootstrap (117.993.472). O app recusa **com razão** — os dois números não
são o mesmo artefato. **O harness injeta metade de um par.**

E é uma convergência, não uma coincidência: o pipeline do bootstrap já tinha escrito, no seu próprio fecho, que *"o
descritor e o catálogo que ele declara são um par: instalar um sem o outro falha a verificação"*. A ligação passou a
**exigir** isso — e o harness era o lado que injetava só metade.

**Consequência para a próxima mudança, e é no `bench/run.sh`:** quando ele substitui o catálogo do bundle, precisa
substituir **o par** — o `catalog.sqlite` do corpus e um descritor que o declare, com os bytes e o SHA-256 reais. Sem
isso, **todo** gate passa a rodar com o app em modo degradado, e a PD-10 fica com o seu dono recusando em todas as
corridas. Nenhum critério muda; é a harness que tem de dizer a verdade sobre o que injeta.

### 99. A identidade governa — os quatro caminhos da PD-10, medidos no app real

O ledger do `CatalogInstallation` escreveu, em três corridas de B05 no mesmo dia, os quatro estados que a PD-10
descreve. Não foram simulados num teste: foram o app fazendo o que ele faz, com o insumo do benchmark.

|corrida|o que o ledger registrou|o que isso prova|
|---|---|---|
|`20261011T182906Z` (injeção de metade do par)|`rejected`, `size mismatch for catalog.sqlite: declared 117993472, present 3719168`|**a recusa** — o par incompleto é detectado pelo tamanho, antes de qualquer uso|
|a mesma|`deferred`, `serving the bundled catalogue unverified`|**o degradado declarado** — não finge; diz o que está servindo e que não é verificado|
|`20261011T183318Z` (após o conserto do runner)|`bootstrapped`, `revision 5 verified and activated`|**a instalação** — o par conferido e ativado|

**A frase que responde ao conselheiro é a última:** `revision 5 verified and activated`. Ele exigiu que a identidade da
revisão **governasse** instalação, atualização, rejeição e preservação — e não que houvesse um log dizendo
`revision=5`. A revisão veio do **descritor**, foi conferida contra o **arquivo**, e o resultado foi **ativado**. É a
diferença entre registrar uma identidade e obedecer a ela.

**O que isso custou para descobrir:** nada além de ter ligado o app ao dono que ele já empacotava. Nas duas corridas de
hoje o `bootstrap()` rodou sozinho, sem ninguém pedir, e nas duas disse a verdade — inclusive quando a verdade era
"recusei". Um sistema que só sabe dizer "instalei" não serve para julgar um catálogo; este disse três coisas
diferentes em três condições diferentes, e todas as três estavam certas.

**O que continua aberto na PD-10:** o critério 4 (adição, remoção e edição refletidas só no catálogo gerenciado e em
trabalho futuro) segue **sem evidência** — o que existe agora é a instalação governada, não a atualização. O gatilho
que falta é a oportunidade de sincronização no foreground, fora da barreira de primeira apresentação, e é o próximo
passo da fila.

### 100. A paralisação de 1,7 s: o traço respondeu, e a resposta não é falta de oferta

O B03 correu inteiro com o traço preservado (corrida `20261011T183832Z`, 32,4 min, 16.994 eventos). O veredicto é
**FAIL** em uma cláusula, e é a mesma de antes — uma paralisação. A diferença é que agora ela tem de onde ser
explicada, e a explicação **não** é a que a suspeita supunha.

**Onde:** `t+244,80 s`, com 1,712 s até a admissão seguinte — no meio do feed, 3.490 admissões ainda por vir, e o
último avanço da corrida admite 0,13 s depois de si mesmo. Não é artefato de borda.

**A janela, crua:**

```
t+244.02 ADVANCE anchor 3BE37957 forward   t+244.04 ADMITTED   t+244.17 WINDOW cards=143 resolved=143
t+244.12 ADVANCE anchor DD0A49D6 forward   t+244.14 ADMITTED   t+244.17 WINDOW
t+244.38 ADVANCE anchor BC35C2DD forward   t+244.40 ADMITTED   t+244.43 WINDOW
t+244.72 ADMITTED cards=143
t+244.80 ADVANCE anchor 5BFC604C forward   ← 1,69 s sem admissão, sem janela, sem candidato
t+246.49 ADVANCE anchor 5BFC604C stationary
t+246.51 ADMITTED                          t+246.54 WINDOW cards=143 resolved=143
```

**Os três números que decidem a questão:**

|pergunta do arquiteto|medida|resposta|
|---|---|---|
|havia próximo card pronto e alcançável?|`WINDOW cards=143 resolved=143 known=120`, **idêntico** antes e depois|**havia** — o runway estava cheio|
|havia algo sendo preparado?|`readiness: textOnly` em **2.115 de 2.115** candidatos; `preparados: 0`|**nada** — num corpus sem mídia, prontos não é trabalho pendente|
|o leitor estava sem oferta?|o avanço de `244,80` e o de `246,49` têm o **mesmo anchor** (`5BFC604C`); a admissão chega 0,02 s depois do segundo|**não** — a transição é que demorou|

**Conclusão, e ela muda a peça a consertar:** a parada é de **apresentação**, não de abastecimento. Com runway cheio e
nada a preparar, o app levou 1,7 s para apresentar a transição entre dois avanços sobre o mesmo anchor. Isso não é a
régua medindo duas coisas — é o produto mesmo —, e o conserto é de renderização, não de suprimento.

**Uma nota sobre a régua, para quem for mexer nela:** a regra do oráculo (`bench/oracle.py:343-348`) conta como parada
qualquer avanço que **não tenha admissão seguinte**, inclusive o último da corrida. Nesta corrida isso não disparou por
sorte — o último avanço ganhou uma admissão 0,13 s depois —, mas numa corrida que termine logo após um avanço ele
produziria uma parada falsa. Fica registrado; não foi alterado, porque a corrida de hoje não precisou disso e mudar a
régua para acomodar o produto é o que o conselheiro proibiu.

### 101. A oportunidade de atualização está ligada, e o ledger prova em duas linhas

O último item aberto da PD-10 foi entregue: `CatalogSyncPolicy` e `CatalogUpdateChannel` deixaram de ser tipos que
ninguém consultava. `AppComposition.foreground()` passa a chamar a oportunidade — **fora da barreira de primeira
apresentação**, como o plano exigiu — e a prova não é compilação, é o que o app escreveu quando rodou.

**Duas linhas no ledger, de um lançamento real no simulador** (`com.feedmine.development`, 8 s de vida):

```
{revision: 5,    outcome: "bootstrapped", reason: "revision 5 verified and activated"}
{revision: null, outcome: "deferred",     reason: "verified 0s ago; nothing due", kind: "policy"}
```

A primeira é a instalação. **A segunda é a oportunidade**: a política foi consultada, o recorde durável foi lido, e
ela decidiu **não** fazer a requisição — a janela de um dia, funcionando. `sync.json` ficou com
`{"verifiedRevision": 5, "verifiedAt": …}`. A suíte de UI inteira (33 testes, 0 falhas) rodou com isso ligado.

**Os quatro caminhos da PD-10, todos medidos no app real:**

|caminho|onde foi medido|evidência|
|---|---|---|
|instalação|B05, B03 e lançamento direto|`bootstrapped` — *revision 5 verified and activated*|
|recusa|B05 antes do conserto do runner|`rejected` — *size mismatch for catalog.sqlite*|
|degradado declarado|a mesma corrida|`deferred` — *serving the bundled catalogue unverified*|
|**política**|lançamento direto, hoje|`deferred` / `kind: policy` — *verified 0s ago; nothing due*|

**Três defeitos meus no caminho, todos pegos pelo compilador ou pela execução, nenhum escondido:**
1. `reference to captured var 'record' in concurrently-executing code` — as closures do canal são `@Sendable`, e eu
   guardava o validador num `var` capturado. **O arquivo virou a caixa**, que é onde ele tinha de terminar de
   qualquer forma.
2. `call to main actor-isolated local function 'readRecord()'` — funções locais herdam o isolamento de main actor e as
   closures rodam fora dele. Viraram closures `@Sendable` com captura explícita do que é `Sendable`.
3. **Um defeito que eu encontrei antes de rodar e que seria silencioso:** o `storeETag` grava o validador **durante**
   o fetch, e o recorde em mãos fora lido **antes**. Escrever a cópia velha de volta apagaria o ETag, e toda
   verificação seguinte viraria um GET completo. O `commit` passou a preservar o validador que a autoridade entregou
   em pleno voo.

**O que continua aberto, e nomeado no próprio registro:** o caminho da **payload**. O canal busca o manifesto; baixar
a árvore OPML e **compilá-la** em um `catalog.sqlite` não existe no pacote nem no app (`grep` por `Compiler|compile(`
em `Sources/` volta vazio). Uma oferta aceita é registrada como lacuna declarada, nunca como revisão aplicada — e é
por isso que o critério 4 da PD-10 (adição, remoção e edição refletidas no catálogo gerenciado) **ainda não tem
evidência**.

### 102. O arquiteto decidiu: o desenho do caminho de payload, e uma correção no meu registro

Levei ao arquiteto as duas coisas: a atribuição da paralisação e o desenho do caminho de payload da PD-10. Ele
respondeu às duas, e a segunda com um desenho fechado.

**Sobre a paralisação — ele mantém os dois bloqueadores, e distingue:**
> "A transição de filtro bloqueia a interação visual aguardando drenagem de aquisição. O B03 esgota a oferta utilizável
> antes da reposição. Desacoplar o fechamento da folha resolve o primeiro; **não garante** abastecimento contínuo."

E pediu o que eu ainda não tinha medido: **localizar quando a reposição foi solicitada, quando chegaram os dados e
quando foram admitidos** — isso separa *disparo tardio*, *aquisição lenta* e *publicação retida até completar um
bloco*. O deslocamento temporal da ocorrência (244,80 s hoje, 343,77 s antes) **não exclui** causa no mesmo caminho de
código. A solução que ele quer: **reposição antecipada e incremental, governada pelo consumo e pela latência medidos,
sem exigir drenagem integral para disponibilizar oferta pronta.**

**Sobre o payload — o desenho, e é para os dois ambientes:**
> "A PD-10 exige atualização **no aparelho** a partir dos OPMLs publicados; um compilador só no release não satisfaz
> adições, remoções e edições entre versões de app."

1. **Um compilador Swift reutilizável** transforma a árvore OPML validada no esquema SQLite/FTS consumido pelo app.
2. **No aparelho:** download e validação integral precedem a compilação em *staging*. A validação do SQLite precede a
   **ativação atômica**; qualquer falha **preserva o snapshot anterior**.
3. **No release:** uma ferramenta usa esse **mesmo** compilador para produzir o bootstrap; o script orquestra.
4. **A substituição alcança apenas o catálogo gerenciado e trabalho futuro** — identidade local, dados pessoais e cards
   publicados são preservados.
5. **Aviso explícito:** "O bootstrap legado já produz contínua util e com evidência de referência. **Não o transforme
   numa segunda implementação permanente com regras diferentes.**"

**E a correção do meu registro, que é um defeito real:** *"'revision 5 verified and activated' precisa identificar se
foi bootstrap ou atualização remota. Ativar o bundle não comprova o critério 4."* O `Outcome` do ledger **já** separa
(`bootstrapped` no arranque, `activated` numa revisão buscada), mas o **`reason` diz a mesma frase nos dois casos** —
então a distinção existe no dado e desaparece na leitura. Isso é consertável e é a próxima mudança pequena.

**O que ele endossa:** *"Enquanto falta download → compilação → ativação de uma revisão nova, G09 continua parcialmente
comprovado; **aceitar a oferta e registrar a lacuna é correto**."* A escolha de projetar a lacuna declarada em vez de
fingir uma revisão aplicada está correta — e continua correta enquanto o compilador não existir.

**Consertado e provado no mesmo dia.** O `reason` passou a nomear a procedência e o `kind` a separá-la (`bootstrap`/`update`). Um lançamento limpo no simulador (`simctl uninstall` antes, para o ledger não ter história) escreveu:

```
{revision: 5,    outcome: "bootstrapped", kind: "bootstrap", reason: "revision 5 verified from the copy this build ships"}
{revision: null, outcome: "deferred",     kind: "policy",    reason: "verified 0s ago; nothing due"}
```

Uma revisão **buscada** diria `kind: "update"` e *"verified from a fetched payload and activated"*. A distinção que o arquiteto pediu não estava faltando no dado — `bootstrapped` e `activated` já eram valores distintos — mas sumia na frase, e agora não some. 24 testes do pacote verdes, app compilando, nenhum teste fixava a frase antiga.

### 103. O compilador: a V1 tem dois, e só um é o certo — o outro é a armadilha

O recon do CompileContract respondeu a pergunta que eu ia responder errado. A V1 tem **duas** implementações de
compilador de catálogo, e elas **divergem**:

| onde | o que é | schema |
|---|---|---|
| `feedmine/scripts/build_catalog.py` | **o builder Python, build-time** — é este que produz o `catalog.sqlite` empacotado, e o `scripts/bootstrap_catalog.py` da V2 o chama como `DEFAULT_COMPILER` | o schema real (coluna `type`, sem `contact_*`) |
| `feedmine/FeedEngine/SQLiteCatalogStore.swift` | compilador Swift in-app, GRDB — **"di fatto solo diagnostica DEBUG"** | divergente do empacotado |

**Portar a versão Swift seria exatamente** o que o arquiteto proibiu: *"não o transforme numa segunda implementação
permanente com regras diferentes"*. O alvo do port são as **regras** do builder Python — DDL em `~346-411`, derivação
de metadados em `~202-278`, ids via `stable_uint32` em `~85-101`, `metadata` em `~519-530`.

**O contrato é mais estreito do que eu supunha.** Ele está em `Sources/FeedMinePersistence/LegacyCatalogReader.swift`
(GRDB 7.11.1, leitura read-only):

- **obrigatórias:** `catalog_source`, `catalog_node`, `catalog_placement` — sem elas, `.unsupportedSchema`;
- **opcional, mas lida:** `catalog_metadata`;
- `supportedSchemaVersion = 2`;
- **o FTS (`catalog_source_fts`) NÃO é lido pela V2 hoje.** Pode ser produzido; não é o que quebra.

**E o `bench/build_corpus.py` não é compilador nenhum** — ele copia DDL e linhas do catálogo real, e por isso o schema
dele é o do builder Python. Isso explica por que o corpus e a referência concordam: não há duas regras, há uma só,
copiada.

**A cadeia real, para não ser redescoberta:** OPML tree → `build_catalog.py` (Python, build-time) → `catalog.sqlite`
(schema_version=2, 77.443 fontes, 6.450 nós) → `LegacyCatalogReader` → app. O `bootstrap_catalog.py` baixa os 118 OPML
do manifest público, **verifica bytes+sha256 de cada um antes de construir**, invoca o compilador legado como
subprocesso, compara o build-report com o manifest, e só então empacota a coleta+descritor.

**Bibliotecas, decidido:** o pacote já usa **GRDB 7.11.1** (só o alvo `FeedMinePersistence`) e **FeedKit 10.9.4**; FTS5
vem habilitado por padrão no GRDB desde a 6.7.0, sobre o SQLite do sistema. Não existe biblioteca madura de
OPML→catálogo pesquisável. Escrever o compilador é o caminho certo — mantendo o GRDB.

### 104. A cadeia de reposição, mapeada — e a minha hipótese estava errada

O recon devolveu a cadeia inteira com arquivo e linha, e corrigiu o que eu havia dito ao arquiteto.

```
leitor rola → FeedHostAssociation.viewport → FeedPresentationHandoff.submitViewport
           → FeedRunwayDriver.submitViewport → drive/driveCausalEffects
           → RunwayController.reconsider                      ← PONTO ÚNICO DE DECISÃO
                 ├─ .runLocalSlice      → CandidateProvider.candidates (SQLite)
                 │                         → PublicationCoordinator.append (um FeedSegment atômico)
                 └─ .requestAcquisition → connector.pull (bytes) → AdmissionPolicy.admit (pool durável)
```

**Os três pontos que o arquiteto pediu, e são exatamente três:**

| pergunta | ponto | arquivo:linha |
|---|---|---|
| quando a reposição foi **solicitada** | `RunwayController.reconsider` — o retorno `.runLocalSlice`/`.requestAcquisition` | `Sources/FeedMineRuntime/RunwayController.swift:281` |
| quando os dados **chegaram** | `connector.pull` → `.batch` (rede); `CandidateProvider.candidates` (local) | `AcquisitionCoordinator.swift:259`, `CandidateProvider.swift:39` |
| quando foram **admitidos** | `AdmissionPolicy.admit`; `PublicationCoordinator.append`; e a instalação do segmento que já gera `admitted` | `AdmissionPolicy.swift:15`, `PublicationCoordinator.swift:~205` |

**O que o trace grava hoje:** `candidate`/readiness, `admitted`, `advance`, `window`, `runway_completed` — **nada no
tempo do pedido nem no da chegada**. O único contador de latência é `RunwayController.latencySamples` →
`ReplenishmentFacts.p95Seconds`, e **só cobre fatias locais**.

**A correção, e é contra mim:** eu disse ao arquiteto que os intervalos de 40 a 158 s entre blocos de candidatos eram
**aquisição em blocos por edição**. O código diz outra coisa. A granularidade é **por fatia** — um `FeedSegment` por
`LocalProductionSlice.run` — governada pelo `RunwayPolicy` de cobertura **e pela espera de preparação de mídia**. Não é
batching de edição. Isso muda a causa provável do esgotamento: não é a edição chegando tarde, é a política de cobertura
e a preparação decidindo quando publicar o próximo bloco.

**O trace é host-only** (`RunwayTrace`, `FeedMineApp/RunwayTrace.swift`): batching de 64, teto de 40.000 linhas, JSON no
thread do chamador e I/O numa fila serial `.utility`. Acrescentar eventos ali é barato — e a injeção por closure
`@Sendable` já existe como precedente no `AppComposition`.

### 105. O compilador existe, e foi construído pelas regras certas

A peça que faltava para a PD-10 está no pacote. Dois arquivos novos em `Sources/FeedMinePersistence/`, ~1.100 linhas,
mais dois de teste:

| arquivo | o que é |
|---|---|
| `CatalogOPMLScan.swift` | as regras de **entrada** do builder: slug, display_name, semantic_path_name, media_kind por arquivo/URL, folder_nodes, extract_language, validação do `xmlUrl`, contadores |
| `CatalogCompiler.swift` | a API e a publicação: `compile(feedsRoot:staging:) -> CatalogCompilationReport`, o DDL v1 verbatim, uma transação GRDB, verificação e substituição atômica |

**A escolha de origem foi a certa.** As regras vêm do builder **Python** (`feedmine/scripts/build_catalog.py`), não do
compilador Swift da V1 — que é DEBUG-only e divergente. O risco que o arquiteto nomeou (*"não o transforme numa segunda
implementação permanente com regras diferentes"*) foi evitado antes de custar qualquer coisa, porque o recon o achou
primeiro.

**Uma divergência real foi encontrada e fechada:** o gate `valid_http_url` do builder não existia no V2. Sem ele,
compilador e builder discordam sobre o que é fonte e o que cai em `invalid_source_count`. Entrou como
`FeedAddress.isValidHTTPURL(_:)`, e `validHost` deixou de ser `private` para haver **um** predicado de host, não dois.

**Publicação, e é onde o arquiteto foi literalmente obedecido:** o chamador escolhe o *staging*; o compilador escreve
`.<nome>.tmp` ao lado e chama **`rename(2)` cru**, com `withUnsafeFileSystemRepresentation` — a substituição atômica,
como o `os.replace` do builder. Antes do rename: `PRAGMA integrity_check` igual a `ok`, `foreign_key_check` vazio,
contagens de `catalog_source`/`node`/`placement`/`metadata` contra o build, e o FTS coberto por `count == sources`
**mais um `MATCH` real** — não a mera presença da tabela. O catálogo ativo nunca é tocado por este tipo.

**Verificação independente, e não a alegação do agente** (que eu repeti com o meu próprio comando):
`swift build` limpo, e **`swift test` → 1164 testes, 1 skipped, 0 falhas** (eram 1149 antes destes arquivos: +15). Os
14 testes novos incluem os que importam:

- `testCompiledCatalogueIsReadByLegacyCatalogReaderWithoutChanges` — compilador e leitor concordam, sem mudar o leitor;
- `testDerivationsMatchTheReferenceBuilder` — **10 ids de fonte e 12 de nó como literais que o builder Python produziu
  para a mesma fixture**, mais a regra (`stableIdentifier == sha256(key)[:4]` big-endian, zero remapeado para 1, raiz
  como sentinela 0);
- `testPublicationReplacesTheDestinationAtomically`, `testIdentityCollapseIsRefusedAndNothingIsPublished`;
- `testFullTextIndexIsProducedAndQueryable` — `MATCH` em title, host e path.

**O que ainda falta para o critério 4:** a ligação. O compilador produz o catálogo; ninguém ainda o chama a partir do
`foreground()`, e o download da payload OPML (os 118 arquivos do manifest) continua não construído — hoje uma oferta
aceita ainda é registrada como lacuna declarada. O próximo passo tem desenho fechado: baixar, validar, compilar em
staging, ativar atomicamente.

### 106. O arquiteto autorizou a instrumentação e a especificou — e corrigiu outra suposição minha

Resposta dele, e ela fecha o desenho:

> "a) Sim, autorizado instrumentar os três pontos. A correção de granularidade muda a hipótese: vamos medir o percurso
> de cada fatia, sem atribuir os intervalos à edição.
> b) **Registre a chegada também no caminho local. Não presuma que consulta e publicação colapsam: seleção,
> preparação e append podem separá-las. Um intervalo quase zero é resultado útil.**"

**A correção é contra mim de novo:** eu perguntei se, no caminho local, "chegou" e "admitido" colapsam, e propus
registrar só no caminho de rede. Ele recusou a premissa — seleção, preparação e append podem separá-los, e um intervalo
quase zero é informação, não ruído.

**O desenho, e é preciso:**

- **Identificador de correlação por operação e relógio monotônico.**
- **Pedido:** a decisão de `reconsider`, com o tipo (local ou rede) e os fatos de cobertura usados.
- **Chegada:** o retorno da consulta ou do pull, com quantidade e resultado — **inclusive vazio, falha e cancelamento**.
- **Conclusão:** admissão no pool **ou** publicação do segmento, **distinguindo explicitamente esses destinos**.
- **Preservar o `admitted` atual como evidência da instalação no host.** Admissão no pool **não equivale** a oferta
  publicada e alcançável; correlacionar o segmento publicado com essa instalação mede também esse intervalo.
- **Instrumentação opcional**, sem alterar decisões nem acrescentar I/O síncrono ao caminho crítico.
- **Registrar truncamento e descarte de eventos.** O motivo: *"silêncio pode parecer ausência de trabalho."*

Esse último item é o mais afiado da lista e eu não o teria escrito. Hoje o `RunwayTrace` tem `batchSize 64` e
`lineCeiling 40_000`: um contador que estoura em silêncio produziria uma corrida que parece sem eventos — e o oráculo
leria isso como ausência de trabalho, não como perda de evidência. Sem registrar o descarte, a métrica mente por
omissão.

**A ordem de implementação:** primeiro o `PayloadWiring` (baixar e ligar o compilador), porque os dois tocam
`AppComposition.swift` e precisam de um dono de integração só; depois a instrumentação, que já tem desenho fechado.

### 107. A ligação feita: baixar → validar → compilar em staging → ativar (o §105 deixou de valer)

O `PayloadWiring` fechou a ligação que o §105 nomeou como faltante. Nada de compilador novo: o `CatalogCompiler`
existente é **chamado**, e o `installOffer` continua sendo quem valida e ativa.

| responsabilidade | onde ficou | o que faz |
|---|---|---|
| baixar + verificar a payload | `CatalogUpdateChannel.download(_:into:)` | uma requisição por OPML declarado, sob o caminho declarado, e a verificação por `CatalogManifest.validate(_:payload:)` (bytes + sha256) **antes** de qualquer compilação |
| a raiz que o compilador recebe | a mesma função (`feedsRoot(of:under:)`) | o diretório comum mais fundo que contém todos os OPML declarados (`Feeds/` no manifesto publicado): derivado da declaração, não fixado no código |
| o descritor do que foi construído no aparelho | `CatalogManifest.declaringCompiledCatalogue(at:)` | o inventário publicado + uma entrada para o `catalog.sqlite` recém-produzido, medida do artefato — a mesma declaração de duas camadas que o `bootstrap_catalog.py` escreve no release |
| a ordem inteira | `CatalogUpdater.install(_:)` (novo arquivo) | baixar → verificar → compilar em staging → declarar → `installOffer` (reverifica a payload, valida o artefato por bytes/digest, o esquema e o `sourceCount` contra o manifesto) → ativação atômica. Falha em qualquer passo preserva o snapshot e escreve o motivo no ledger |
| o gancho | `AppComposition.syncCatalogueIfDue()` | o ramo `.accept` virou uma chamada; a mensagem de lacuna deixou de existir |

Duas decisões que foram escolhas, e não obviedades:

- **Um `.sqlite` no inventário publicado é recusado** (`invalidDeclaration`), como o `bootstrap_catalog.py` já fazia:
  este build compila a árvore que verificou, e aceitar o banco da autoridade seria instalar um snapshot que nada no
  aparelho construiu.
- **Falha de transporte e payload divergente são coisas diferentes:** sem resposta nenhuma é `.unavailable` (nada
  verificado, o snapshot não se move, linha `deferred`/`kind: network`); bytes que chegaram e não batem com a
  declaração — arquivo não servido, tamanho errado, digest errado — é `rejected`, nomeado.

**Provado com servidor HTTP real em loopback** (não um stub de sessão):
`Tests/FeedMineCompositionTests/CatalogAuthorityServer.swift` (fixture), `CatalogPayloadChannelTests.swift` (9 testes)
e `CatalogUpdaterTests.swift` (5). O de ponta a ponta
`testAnAcceptedOfferIsDownloadedVerifiedCompiledAndActivated` faz o GET do manifesto, decide `.accept(6)`, roda o
caminho inteiro e afirma: o catálogo ativo é lido pelo `LegacyCatalogReader` sem mudanças (4 fontes, `matchingSources`
devolvendo *Alpha News*), o ledger registra `kind: "update"` com *"revision 6 verified from a fetched payload and
activated"* (não `bootstrap`), o `runtime.sqlite` fica byte a byte idêntico, e o diretório de trabalho é removido.

**O caso do digest errado é asserção, não comentário:** o teste serve os mesmos bytes com um bit invertido (mesmo
tamanho, então quem recusa é o digest) e prova que **nada** foi ativado — `active.json` byte a byte igual, a listagem
de `snapshots/` inalterada, a revisão ativa ainda 5 com o mesmo fingerprint, o catálogo anterior ainda legível, e a
linha `rejected`/`kind: payload` no ledger.

**Verificação:** `swift build` limpo; `swift test` → **1178 testes, 1 skipped, 0 falhas** (eram 1164: +14).

**O que NÃO ficou provado, e é honesto listar:** (1) o gancho do `AppComposition` (o ramo `.accept`, seis linhas) não
é exercitado pelo `swift test` — o alvo do app não está no pacote; o que está provado é o tipo que ele chama. (2) A
comparação de revisão igual **depois** de uma atualização: o manifesto ativo passa a ser o descritor derivado (com a
entrada `.sqlite`) e o público é OPML-only, então `CatalogOffer.decide` vê declarações diferentes na mesma revisão e
responde `.collision` em vez de `.upToDate`. É o mesmo comportamento que o app já tem hoje contra o descritor
empacotado (revisão 5 ativa vs. pública 5) — não é defeito novo — mas fica registrado, porque é política selada
(`CatalogSyncPolicy`) e esta tarefa não a tocou.

### 107. O caminho de atualização da PD-10 está completo

O que faltava entre "o compilador existe" e "o critério 4 tem evidência" foi fechado, e a lacuna declarada **deixou de
existir** — a mensagem foi deletada, junto do parágrafo de doc-comment que a justificava.

**Onde cada responsabilidade ficou:**

| passo | onde | o que faz |
|---|---|---|
| baixar + verificar | `CatalogUpdateChannel.download(_:into:)` | uma requisição por OPML declarado, escrita sob o caminho declarado; **bytes+sha256 antes de a compilação existir no caminho** |
| raiz de feeds | a mesma função | **derivada** — o diretório comum mais profundo dos OPML declarados, não fixada no código |
| descritor do artefato | `CatalogManifest.declaringCompiledCatalogue(at:)` | inventário publicado + 1 entrada `.sqlite` medida — a mesma forma de duas camadas do `bootstrap_catalog.py` |
| ordem e falha | `CatalogUpdater.install(_:)` | download → compilar em staging → declarar → `installOffer`; **falha em qualquer passo preserva o snapshot e escreve o motivo no ledger** |
| dono do ledger | `CatalogInstallation.reject(_:...)` (agora público) | o updater grava as linhas dele, a instalação as dela — **um dono por linha** |
| gancho | `AppComposition.syncCatalogueIfDue()` ramo `.accept` | **uma chamada** |

**Provas, e são por asserção, não por comentário.** Um servidor HTTP/1.1 real em socket serve o manifesto e a payload:

- **e2e:** o manifesto é buscado pela mesma channel → `.accept(6)` → o caminho inteiro. O `LegacyCatalogReader` lê o
  catálogo ativo sem mudanças; **`ledger == [bootstrapped/bootstrap, activated/update]`** com
  `reason: "revision 6 verified from a fetched payload and activated"` — a procedência que o arquiteto exigiu,
  funcionando; e `runtime.sqlite` fica **byte a byte idêntico** (dados locais preservados).
- **digest errado:** o servidor serve os mesmos bytes com um bit invertido — mesmo tamanho, então quem recusa é o
  digest. `checksumMismatch` nomeado, `active.json` byte a byte igual, a listagem de snapshots inalterada,
  `activeSnapshot()` ainda revisão 5 com o mesmo fingerprint, o catálogo anterior ainda legível, e o ledger terminando
  em `rejected/payload`. **Nada foi ativado.**
- **degradação:** autoridade derrubada entre manifesto e payload → `.unavailable`, snapshot intacto, linha
  `deferred/network`. Manifesto 404 → `.unavailable`, nada escrito além da linha de bootstrap.
- **segurança:** um `path` com `../` é recusado como `unsafePath` **sem escrever nada fora** do destino.

**Minha verificação, porque alegação de agente não é prova:** `swift test` → **1178 testes, 1 skipped, 0 falhas** (eram
1164: +14), e — o que o próprio agente apontou como não feito — **`xcodebuild build` do app: BUILD SUCCEEDED**, que é o
alvo onde o gancho vive e que o pacote SPM sozinho não compila.

**O que segue NÃO provado, dito com todas as letras:** o gancho do `AppComposition` compila, mas não foi *exercitado em
execução*. O caminho está provado no tipo que ele chama, com socket real; falta rodá-lo no app de verdade. É o próximo
buraco honesto desta cadeia.

### 108. A cadeia de reposição instrumentada: pedido, chegada e destino, com um id por operação

O §104 mapeou os três pontos e o §106 registrou a autorização e o desenho. Está implementado, e é **opcional**: sem
trace ligado nada muda, nenhuma decisão lê o que ele escreve, e nenhum I/O entra no caminho crítico (o sink só
codifica e enfileira; a escrita sempre foi assíncrona numa fila serial `.utility`).

**O que entra no trace, e com que nomes de campo.**

| evento | onde nasce | campos |
|---|---|---|
| `replenishment_requested` | `RunwayController.reconsider`, nos dois retornos que pedem reposição (`.runLocalSlice`, `.requestAcquisition`) | `op`, `kind` (`local`/`network`), `edition`, `surface`, `coverage` (+`required_cards`), `ready` (+`ready_cards`/`ready_bound`), `lane` + `examined_capacity` (local), `pressure` + `local_supply` (rede) |
| `replenishment_arrived` | `CandidateProvider.candidates` (local; `consult` = `slice`/`preparation`) e o retorno de `connector.pull` em `AcquisitionCoordinator.run` (rede; `attempt` = n-ésima tentativa) | `op`, `kind`, `result`, `candidates`/`examined`/`exhausted` (local); `observations`/`bytes`/`target`/`generation`/`failure` (rede) |
| `replenishment_concluded` | a admissão no pool (`AdmissionPolicy.admit`, chamada por `AcquisitionCoordinator.run`) e a publicação do segmento (`PublicationCoordinator.append`) | `op`, `destination` (`pool_admission`/`segment_publication`) e os fatos do destino: `observations`/`rejected`/`checkpoint_advanced`/`selectable_supply_changed`; `edition`/`segment`/`ordinal`/`cards`/`head`/`tail` |
| `trace_truncated` | o próprio `RunwayTrace` | `reason` (`line_ceiling`/`encoding`/`flush_total`), `ceiling`, `dropped_by_ceiling`, `dropped_by_encoding`, `dropped_by_write`, `written` |

**Onde o id nasce.** Em `reconsider`, no instante da decisão, e viaja dentro do `RunwayLocalSliceIntent` /
`RunwayAcquisitionIntent` — o único veículo que chega ao executor com o resto dos fatos daquela decisão. Os campos
`operation` são **evidência, não identidade**: `==` e `hash` continuam comparando só o que as decisões comparavam
(escopo+lane+capacidade+instante; escopo+demanda). Sem isso, um id novo a cada chamada faria
`lastAcknowledgedAcquisitionIntent` deixar de casar e a mesma demanda viraria uma aquisição nova a cada oportunidade —
um instrumento que muda o que mede. Há teste para essa invariante.

**Como o opcional atravessa os módulos.** O port vive em `FeedMineDomain` (`ReplenishmentTrace`, um closure
`@Sendable`; `FeedReplenishmentOperationID`; o vocabulário dos eventos) porque é o único módulo que os quatro donos
importam. Nenhum módulo do pacote conhece o `RunwayTrace` do host: o `AppComposition` constrói **um** adapter
(`ReplenishmentTrace { trace.record($0, $1) }`) e o entrega ao `RunwayController` e ao `FeedRunwayDriver`, que o
repassa a `RunwayAcquisitionCycle`, `LocalProductionSlice`, `PublicationCoordinator` e `CandidateProvider`. Sem trace
o valor é `nil`, e cada ponto é um `if let trace`. `ColdFeedBootstrap` e o caminho de cobertura por fonte escolhida
ficaram **fora**: eles não passam por `reconsider`, logo não abrem operação — a autorização nomeia um pedido, e
inventar um segundo seria medir outra coisa.

**Como ler a atribuição.** Cada linha traz `at` (relógio de parede, o que o oráculo já lê) e `mono` (uptime
monotônico). Os intervalos se medem em `mono`, porque parede pode saltar. Três intervalos: **pedido→chegada** (disparo
e aquisição), **chegada→conclusão** (seleção/preparação/append no local; validação e admissão na rede) e
**pedido→conclusão**. No caminho de rede a conclusão é a **admissão no pool**, que não é oferta alcançável: quem
publica é uma operação *local* posterior, e a instalação no host continua sendo o `admitted` de sempre — que agora
também carrega `head`/`tail`/`anchor` (ids de cartão), para poder ser casado com o `head`/`tail` do segmento
publicado. Uma fatia local que não publica nada aparece como pedido+chegada com `candidates`/`exhausted` e **sem**
conclusão: o desenho não inventa um terceiro destino que a autorização não nomeou.

**Descarte registrado.** `record` conta o que o teto recusou, o que não conseguiu codificar e o que não conseguiu
escrever, e escreve `trace_truncated` na primeira perda e no `flush` com os totais. O limite, dito: se o destino
nunca voltar a ser gravável, o próprio anúncio é o que não pousa.

**O que NÃO ficou provado.**
- O gancho do `AppComposition` compila (`xcodebuild build`) e o teste do teto roda no alvo do app, mas a cadeia
  inteira **em execução** no app real (uma rolagem que produza pedido→chegada→conclusão no `trace.jsonl` do sandbox)
  não foi exercitada aqui; o que está provado são os tipos e os pontos que ela chama, com SQLite e um conector de
  teste reais.
- `dropped_by_write` é contado e reportado na próxima escrita que pousa, mas não tem teste ponta a ponta: a falha que
  ele conta é justamente a que impede o anúncio de pousar.
- A correlação segmento publicado ↔ instalação no host é por ids de cartão, não por chave estrangeira: o
  `FeedPresentationSnapshot` não carrega o `segmentID`.

### 109. O ramo `.accept` rodou dentro do app — e o critério 4 tem evidência

O buraco que o §107 nomeou (`o ramo compila mas nunca executou`) está fechado. `CatalogueUpdateAcceptTests` exercita
o app real contra uma autoridade local de **revisão 6** e passa nas três asserções:

| o que | como foi provado |
|---|---|
| a instalação aconteceu | `ledger() == [bootstrapped/bootstrap/rev 5, activated/kind "update"/rev 6]`, com a frase exata *"revision 6 verified from a fetched payload and activated"* — e **sem linha `deferred`**, provando que a passagem consultou em vez de pular |
| o catálogo mudou | `activeSnapshot()` → revisão 6, `sourceCount` 4, fingerprint igual ao SHA-256 do arquivo que o ponteiro nomeia; o `LegacyCatalogReader` lê. **Controle negativo incluído:** a cópia empacotada (rev 5 / 77.443) é outro arquivo e continua legível |
| os dados locais ficaram | `runtime.sqlite` byte a byte idêntico, `ReaderPreferencesStore.load()` o mesmo |

**A prova de rede é o log do próprio servidor**, não a URL que o app recebeu: a autoridade registra os caminhos que
respondeu (`manifest.json`, `Feeds/noticias.opml`, `Feeds/programas.opml`). É o princípio do oráculo aplicado a um teste
de app.

**E ele explicou por que o ramo era inalcançável**, ligando com o que já estava medido: o `syncCatalogueIfDue` reescreve
`verifiedAt` com `Date()` a cada arranque que encontra snapshot ativo, então com a janela respeitada a decisão é
`.skip` — exatamente o skip que o §101 registrou. Nomear outra autoridade também declara que a janela/ETag/revisão
gravada sobre o canal **publicado** não decide esta passagem.

**A costura, verificada por mim:** `statedCatalogueAuthority()` é o único leitor de `FEEDMINE_CATALOGUE_AUTHORITY`, e o
corpo está sob `#if DEBUG`; em Release compila para `return nil`, então nenhuma variável de ambiente, argumento de
lançamento ou preferência pode apontar o app para outro lugar. A condição vem de
`SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)"` nas configurações Debug.

**O limite honesto, que o autor do teste declarou e eu aceito:** a comparação byte a byte só é significativa porque o
teste não publica nada e fecha a associação — `FeedAssociation.foreground()` escreve no store do leitor por conta
própria (visibilidade de edição, publicação do driver), então a asserção mede exatamente a metade sob teste: a passagem
de atualização, que escreve só sob `catalogue/`. Não foi afrouxada; o ruído foi tirado da janela medida.

**O que isso ainda NÃO é:** uma atualização vinda da autoridade **real**. A `wawasoft/feed-repository` publica a revisão
5, que é a ativa, então em produção o app responde `.upToDate`. O mecanismo está provado ponta a ponta; a primeira
atualização de verdade acontece quando a autoridade publicar uma revisão 6 — e publicar isso não é meu.

### 110. O release evidence ledger, e o que ele descobriu sobre identidade

Criado `docs/v1-study/RELEASE_EVIDENCE.md`, que era o pedido do conselheiro — as provas do projeto vinham sendo obtidas
em condições diferentes e nada respondia se a candidata atual satisfaz todos os contratos.

**O que ele descobriu, e não é bonito:** o `commit` **não identifica** a build sob teste. `HEAD` está em `609ced6d`
desde antes do trabalho de hoje, com **117 arquivos sujos** (57 modificados, 60 novos) — compilador, ligação,
oportunidade de atualização, caminho de payload e instrumentação, tudo não commitado. Duas corridas com o mesmo
`commit` podem ter medido árvores diferentes, e o `dirty: N` que o runner grava não distingue *quais* bytes mudaram.

**A identidade que serve é de conteúdo**, e não custa nada: `git stash create` devolve um hash que endereça a árvore
inteira, sem tocar no índice nem no worktree. A candidata corrente é `609ced6d` + `12ab36166b9b…`.

**Pendência aberta e nomeada:** o `bench/run.sh` precisa gravar esse hash no `identity.txt`. Enquanto não gravar, uma
corrida lançada por outro caminho não é atribuível a uma árvore — foi por isso que o disco me recusou duas corridas
hoje e eu quase não percebi que estava comparando coisas incomparáveis.

**A conclusão honesta que o ledger registra:** as corridas de B05 e B03 que existem foram feitas em árvores anteriores.
Entre elas e agora entraram cinco mudanças grandes, nenhuma medida por um gate de release. Então **os PASS desta tabela
não podem ser apresentados como evidência de release** — são PASS históricos. As remedições na árvore corrente estão em
curso.

**E uma ferramenta que o runner tem e eu não sabia que valia registrar:** ele se **recusa** a rodar sem disco
(`REFUSED: the host volume has 2775 MB free; a gate needs about 3 GB`). Preferir não medir a medir mal é a mesma
disciplina que o oráculo segue no veredicto, e vale para a mesma razão.
