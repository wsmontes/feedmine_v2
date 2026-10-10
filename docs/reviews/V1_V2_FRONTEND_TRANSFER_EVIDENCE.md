# V1 → V2 frontend transfer: executed evidence

One row per delivered surface. **Every row states a command that was actually run and its result**; a row that
says "not executed" was not run, and nothing here claims otherwise. Work package: T1–T12 of
`docs/superpowers/plans/2026-10-09-transferencia-frontend-v1-v2.md`; the narrative is in
`docs/v1-study/PORT_LOG.md`, the per-control inventory in `docs/v1-study/UI_TRANSFER_MATRIX.md`.

- Repository: `/Users/wagnermontes/Documents/GitHub/feedmine_v2`
- V1 reference: `/Users/wagnermontes/Documents/GitHub/feedmine@712a6ba9` (read-only throughout)
- Package suite: `swift test` → **1017 tests, 0 failures**, exit 0 (final regression)
- `git diff --check` → exit 0, no output
- iOS build: `xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination
  "platform=iOS Simulator,id=8871DCF5-0C06-4C7C-88D2-7B3DC36E8284" -derivedDataPath /tmp/fm-derived
  CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED**
- Simulator UI tests: run one at a time with `-only-testing:FeedMineAppTests/FeedMineUITests/<name>`; each result
  below is from its own run.

## Per-surface evidence

| Task | Surface | Behavioural evidence (command → result) | Visual evidence | Accepted difference |
|---|---|---|---|---|
| T2 | Production ≠ admission | `swift test --filter FeedPresentationAdmission*` ✓; the barrier's own tests in `FeedMineRuntimeTests` ✓ | — | none |
| T3 | Scroll admits the next prefix | `swift test --filter "FeedRunwayDriverTests\|SelectedSourceCoverageTests"` ✓; UI: `testNativeSwipeReachesRealRunwayAndReverseNavigation` ✓ TEST SUCCEEDED | card geometry asserted in the UI test (`native-viewport-delivery`) | none |
| T4 | Cards and visual identity | `FeedCardTransferTests` ✓; `FeedScreenRenderingTests` ✓ | UI tests render real cards | image *share* not ported (no rendered artifact; recorded in T9) |
| T5 | Shell, header, menu, search | `ReaderShellTests` ✓; UI `testContextNavigationAndSourcePickerOffline` ✓ | menu entries asserted by identifier | — |
| T6 | Filters and context identity | `ReaderFilterTests`, `ReaderFilterStoreTests`, `ContextIdentityPersistenceTests` ✓; UI `testT6FilterSheetOpensAppliesAndKeepsTheReader` ✓; app `testT6FilterTransitionKeepsContextsSeparateAndStaleCallbackInert` ✓ | lens chips asserted in the UI test | full preset picker arrives with T8 ✓ delivered |
| T7 | Catalog, taxonomy, source management | `LegacyCatalogMetadataTests`, `SourceCatalogBackendTests`, `SourceManagementCoordinatorTests`, `SourceManagementStoreTests` ✓ | UI `testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack` ✓ (shell → countries → toggle → feed back) | DEBUG-only catalogue explorer ordered into T12's sweep (recorded) |
| T8 | Boxes, collections, presets | `ReaderLibraryStoreTests` (9) ✓, `LegacyUserStateImportTests` (3) ✓, `ReaderLibraryCoordinatorTests` (3) ✓, `BookmarkBoxesBackendTests` (6) ✓; UI `testBookmarkBoxesManageAndOpenTheirOwnList` ✓, `testCollectionsManageAndReachThePresetPicker` ✓, app `testT8ASavedPresetIsOfferedAndActivatesItsOwnContext` ✓ | boxes/collections/picker asserted in the UI tests | a box as a *reading surface* waits for a presentation source; V1's `AddFeedToCollectionSheet` not drawn |
| T9 | Reader, media, share | `ReaderActionCoordinatorTests` (4) ✓, `ReaderMediaCoordinatorTests` (4) ✓, translator (34) ✓, media storage (4) ✓; UI `testCardCopiesItsOwnLinkAndStatesIt` ✓, `testMiniPlayerStatesPlaybackWithoutMovingTheFeed` ✓ | the mini player's 56 pt playing and paused, the feed unchanged | `SFSafariViewController` instead of V1's raw WKWebView (no Safari link/loading bar); image share not ported |
| T10 | Preferences, import, export | `ReaderSettingsTests` (6) ✓, `FeedAddressTests` (8) ✓, `OPMLDocumentTests` (5) ✓, `ReaderImportExportCoordinatorTests` (6) ✓, `ReaderSettingsCoordinatorTests` (5) ✓; UI `testSettingsReachTheirControlsAndSurviveReopening` ✓, `testImportPreviewCommitsAndExportPreviews` ✓ (real import through the database) | both sheets asserted in the UI tests | V1's Language section and its Reading Data/Share sections not drawn (no catalog, no rendered stats card) |
| T11 | Onboarding, curation, preparation | `FeedRecipeDefinitionTests` (8) ✓, `FeedRecipeResolutionTests` (7) ✓, `WeightedScoringTests` (3) ✓, `CuratedFeedCoordinatorTests` (6) ✓, `PreparationProgressTests` ✓; UI `testOnboardingWelcomeComposerAndSave` ✓; app `testT11ACuratedFeedRanksByItsRecipeAndEditingChangesTheBehaviorVersion` ✓ | the whole flow in one UI test: welcome → composer → save → hood | V1's duel scenes are dead code there and are not ported; the Composer preview shows the reader's own published cards in published order (V1 ranked them by the recipe being shaped) |

## The audit T12 asks for (item 7)

```
$ grep -rn "FeedStore\|FeedLoader" Sources/ FeedMineApp/FeedMineApp --include=*.swift
   → only two provenance COMMENTS in FeedMineDomain/ReaderFilter.swift naming V1's own vocabulary
$ grep -rn "URLSession\|Data(contentsOf:\|AVPlayer\|UIPasteboard\|UIActivityViewController" Sources/FeedMineUI
   → no matches: no surface in the UI package performs I/O or touches a platform framework
$ grep -rn "TODO\|FIXME\|HACK\|temporary\|deprecated" Sources/ FeedMineApp/FeedMineApp --include=*.swift
   → no markers; the "temporary" hits are a local media asset's temp file before an atomic rename
```

No replaced renderer, route or adapter remains: every surface either has a live caller or was never built (the
DEBUG-only catalogue explorer, recorded above). `docs/architecture/FILE_RESPONSIBILITIES.md` gained its Phase 4
section in this pass: one row per transferred surface, naming the files it owns and what it must not own, with
every path in the table checked to exist.

## The integrated scenario (T12, item 3)

`TransferScenarioTests.testT12ContentArrivingWhileTheReaderIsStillLeavesTheirCardsInPlace` — **1 test, 0
failures**. While the reader is still, four kinds of arrival land in order: a slow source finally publishing (the
reserve grows behind them), a decode arriving late (the same frozen cards), an edit to an article already read
(its own new occurrence, appended), and a foreground reporting work. Asserted: the admitted prefix is the same
cards in the same order with the same content, the reserve grew, the edit arrived at the end, a *stale
projection* is refused outright, and only a gesture reaches the host. The frame/offset half of the same promise
is proven where it can be measured — `FeedPresentationAdmission`'s own tests, `FeedScreenStoreTests`'
invariance, and the simulator test below.

## The unit-test harness and the forward-admission activity (2026-10-10)

Six `CompositionTests` cases asserted a window wider than the anchor card, and each failed on its first supply
assertion. The cause was the harness's activity, not the app: `RunwayActivity.admitsForwardContent` is true only
for `.explicitTailApproach`, so an observation sent with `.forward` records the position and never extends the
admitted list — while the real shell (`Sources/FeedMineUI/FeedScreen.swift`) already sends
`.explicitTailApproach` when the reader moves forward and the tail is visible, which is what makes cards arrive
as the reader reaches them. The harness now produces (one `driver.drive`) and then admits as a reader does, with
that activity: `1 anchor + 16 = 17`, the composition's own bounds. Evidence: the six tests plus
`testT12KeyboardSearchKeepsTheReadingPointAndRestoresIt` in one command → **TEST SUCCEEDED**; `swift test` → 1017
tests, 0 failures.

## Native gestures, rotation and Dynamic Type (T12, item 4)

`testNativeScrollRotationAndDynamicTypeKeepTheAdmittedCardInPlace` — **TEST SUCCEEDED** (simulator, launch
argument `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXL`): six swipes down, six
back, a real driver opportunity published in both directions, a rotation to landscape and back whose delivered
counters do not change, and the feed still readable throughout.

`testNativeSwipeReachesRealRunwayAndReverseNavigation` — **TEST SUCCEEDED** (the T3 gesture test that already
existed): the first delivery is `received=0 completed=0 backward=0`, i.e. restore and layout are not a user
observation, and a swipe is what completes one.

`testT12KeyboardSearchKeepsTheReadingPointAndRestoresIt` — **TEST SUCCEEDED** (added by this pass; the keyboard
scenario the plan lists and the T5 test did not cover, since T5 only opened and cancelled the search surface):
the reader's own search field takes a written query, the feed's published counters do not move while it is
written, and cancelling returns the same card to the same reader with the counters still unchanged.

## Offline and relaunch (T12, item 6)

`testOfflineRelaunchKeepsFilterSavedCardAndFeed` — **TEST SUCCEEDED**: a filter applied, a card saved, then the
app terminated and relaunched **with the network blocked**; the feed the reader had is still readable, the saved
list opens, and the filter is still applied. The state that survives there is the reader's own: preferences,
selection, library and published history.

An interrupted import discards nothing: `ReaderLibraryStore.commitImport` performs the entries **and** the
updated selection inside one `database.write` (`Sources/FeedMinePersistence/ReaderLibraryStore.swift:203`), so
SQLite either commits the whole import or leaves the previous state, and a malformed document throws before any
write at all (`OPMLDocumentTests.testMalformedInputThrows`). There is no fault-injection test for a killed
process; the atomicity above is the mechanism that makes one unnecessary.

## The DEBUG-only catalogue explorer, and why it is not ported

V1 drew a paginated developer browser (`Views/CatalogExploreView.swift`, 369 lines) behind `#if DEBUG` — its
own header button is gated the same way (T1's matrix row 68 records *"Catalog explore (**DEBUG only**)"*). V2
does not port it, and this is an accepted difference rather than an omission: it is a developer tool with no
reader-facing behaviour, its V1 form reads the old registry directly, and every reader-facing catalogue surface
it fronted is ported and proven above. If it is wanted, it is a self-contained addition over
`SourceManagementCoordinator`'s paging.

## Curated ranking: an edit is a new behaviour

Executed 2026-10-10 over `41ed1a5`, delivered as `bd3c4b9`. The recipe's ranking was right as a *value*
(`FeedRecipeResolutionTests`, `WeightedScoringTests`) but three links around it were not:

- one session construction site bypassed the curated decision, so a curated session ranked by the baseline;
- an edit that left the context key alone kept the running session's behaviour version, so an Edition published
  under the superseded recipe was still shown and restored;
- the behaviour version was a hash over the recipe, and the policy version contract rejects it (a counter).

The recipe now carries its own revision (`reader_presets.recipe_revision`, migration
`reader-curated-recipe-revision-v1`, bumped on every edit); an explicit transition happens when the identity
*or* the behaviour changes; and an Edition or saved position published under a superseded scoring policy is
neither shown nor restored (`AppComposition.mayShow(… scoringVersion:)`, `SessionStore.clearCheckpoint(for:)`).

Command → result:

- `xcodebuild … -only-testing:FeedMineAppTests/CompositionTests/testT11ACuratedFeedRanksByItsRecipeAndEditingChangesTheBehaviorVersion test`
  → **TEST SUCCEEDED**: the policy is `.weighted` over the node the recipe answered on, the revision goes 1 → 2,
  and the new session's scoring policy version follows it. Run in the same command: T6 identity, T8 preset and
  S3/S4 replacement — all **SUCCEEDED**.
- `swift test` → **1017 tests, 0 failures**.

## What the 2026-10-10 re-run found and repaired

Two defects made UI tests fail that this document had recorded as passing, and neither was the test's fault:

- **Destinations that were never offered.** `FeedMineApp/FeedMineApp/FeedMineApp.swift` already routes
  `.settings` (line 214) and `.export` (line 183) in its presentation switch, and
  `Sources/FeedMineUI/Reader/ReaderNavigation.swift` already declares the "Ajustes" and "Exportar" entries
  (lines 87 and 81) — but `AppComposition.readerDestinations` did not carry them, and the header menu renders
  exactly that set. T9's export and T10's settings were therefore unreachable for the reader. The set now
  includes `.export`, `.collectionExport` and `.settings`; V1's "add feed" and collection-import entries stay out
  because this host has no composer for either (an entry that opens the wrong surface is worse than one that is
  not offered). `testT5HeaderChromeAndCardGesturesReachRealFlows` had asserted the *opposite*
  (`XCTAssertFalse(app.buttons["Ajustes"].exists)`) — that assertion described the interim state, and it is
  replaced by the contract the build now meets.
- **Container identifiers swallowing their children.** On this toolchain (iOS 26.5 / Xcode 26.6),
  `.accessibilityIdentifier` on a SwiftUI *container* replaces the identifiers of everything inside it, so the
  onboarding surface, the mini player, the empty-selection state, the cards and the toast all reported the
  container's name. `Sources/FeedMineUI/Reader/ReaderShell.swift:102` already documents this and fixed it for the
  search bar; the same remedy (`.accessibilityElement(children: .contain)`) is applied to the other containers.

Verification so far, run by the person integrating the work rather than by the agent that made it: `swift test` →
**1017 tests, 0 failures**; and `testSettingsReachTheirControlsAndSurviveReopening`,
`testMiniPlayerStatesPlaybackWithoutMovingTheFeed`, `testU1iPadLayoutPortraitAndLandscape` and
`testT12KeyboardSearchKeepsTheReadingPointAndRestoresIt` → **4/4 passed**. The remaining UI tests are being
repaired one at a time, with the whole-target run as the acceptance.

Two further defects surfaced the same way — by running the flows the plan claims, not by reading them:

- **The library was reopened, and a failure to open was swallowed.** Every library action built a fresh
  `RuntimeDatabase` (a new pool, the migrations again, contended with the session's own connections) and the
  failure was taken by `try?`; the export then reported "nothing to export" with no error anywhere. The
  composition now memoizes one connection for every library surface
  (`FeedMineApp/FeedMineApp/AppComposition.swift`), and a failed open is not remembered, so the next action tries
  again.
- **Closing the reader dismissed the surface that presented it.** `InAppBrowser` called SwiftUI's `dismiss()`
  while the host still held the state the sheet was presented from, leaving a presentation whose item was still
  set; the browser now reports its own close (`onFinish`) and the host clears that state. Together with
  presenting the reader from the surface the reader is on, this is what makes "close the article, return to your
  saved list" the same behaviour V1 had.
- **A saved row was only tappable on its text.** A tap at the row's centre landed between the drawn lines, so
  the label's own hit region (the text) missed it and the row's action never ran; the label now declares the
  row's shape, exactly as the working card already did.
- **A country is a region tree, not a node.** V1's `SourceRegistry` cascaded a region toggle down the tree, and
  the shipped catalogue nests each country's sources under its topic leaves
  (`90_countries/algeria/sports/football`), so toggling the country's own placement enabled almost nothing. The
  catalogue backend now answers subtree queries for the country, its children and the toggle itself; the
  measured effect on the fixture catalogue was a country toggle writing 537 source keys.

The whole-scheme run then passed: `CompositionTests` **24 tests, 0 failures** and `FeedMineUITests` **21 tests,
0 failures** in one run, with `swift test` at **1017 tests, 0 failures** — the acceptance this document was
missing for the UI target.

## The architect's verdict on the two remaining items (2026-10-10)

Asked, in the conversation that owns WHAT for this project, whether the two items T12 cannot execute on this
machine may be satisfied by substitutes. The verdict: **execute both substitutes and close the task with an
explicit physical-device waiver.** Verbatim conditions it set:

- The soak must measure the **FeedMine process**, not the host's total memory, and record samples, peaks, trend
  and whether it stabilises after warm-up; CPU per process, plus visible freezes and hitches wherever there is
  instrumentation ("CPU amostrada isoladamente não comprova ausência de hitches").
- During the 30 minutes of scrolling there may be **no artificial end, blank screen, freeze, or repeated cards**
  used to mask a lack of supply.
- After the soak, integrity is checked: persistence, continuity of the reading point, published identities,
  duplications, PD-4.
- No arbitrary MB or CPU limit may be invented to fabricate a PASS; what is required is bounded use without a
  sustained growth trend, and a soak that grows without stabilising, hangs, or reaches the feed's end while
  eligible content should still be acquired **fails**.
- The visual comparison is **semantic and visual, not pixel by pixel** (hierarchy, spacing, typography, colours,
  affordances, sheet behaviour, legibility, consistency with V1's identity; different RSS content is not a visual
  regression), and it gains three surfaces beyond the four references: **Salvos**, **Fontes e catálogo**, and
  **Shell/Ajustes/Exportar**.
- Closing formula: `T12 — PASS WITH PHYSICAL-DEVICE WAIVER`, listing the package and app counts, the simulator
  soak, the comparison, and "residual risk retained for physical-device validation before public release".

Its own stated limitation, which this document repeats rather than hides: it could read the connected branch but
**not** the local commit or the T12 plan file, so the verdict approves the criteria and the substitutes as
described, and does not certify a read of the local state.

## The review the app channel returned (2026-10-10)

Codex, asked to review `dd63c1a` for real defects rather than style, returned three items; two are fixed and one
is under test:

- **[P1] "Exportar coleção" exported the general selection** (`FeedMineApp.swift:410`): the destination added to
  the menu took the same `.selection` request as plain "Exportar". An entry that opens the wrong document is worse
  than one that is not offered, so it is out of the offered set until a collection's own export exists on the
  collection's surface (`AppComposition.readerDestinations`).
- **[P2] the playback bar inside the reader held stale state** (`FeedMineApp.swift`: the host built its
  `rootView` once and the coordinator skipped updates for the same page). `testT12ReaderKeepsTheLivePlaybackBar`
  decided it: with the simulated episode playing, the reader is opened from a card and the bar is paused
  **inside** the reader, where the bar's own label must change from "Pausar" to "Tocar". It failed first
  (`XCTAssertEqual failed: ("Pausar") is not equal to ("Tocar")`) — the defect was real — and the host now
  re-renders the presented reader's content in place, with the playback as a token the parent reads, so the same
  reader keeps its state and updates live. The test passes.
- **a test guarantee replaced**: `FeedMineUITests.swift` swapped an assertion on `source-choice-*` rows for the
  shipped surface's own rows and enabled count. The picked rows belonged to `FeedSourcePicker`, which had no
  caller at all, so the dead view is removed and the value the app does use (`FeedSourceOption`) moved to its own
  file. The review's other half was satisfied in the scenario itself: the test now walks one level further —
  country list, a country's rows, then an **individual source's own toggle** (`node-source-toggle-*`) — so the
  scenario verifies a source choice, not only the levels above it.

## Not executed, and why

| Plan item | State |
|---|---|
| `CompositionTests` as one run (24 tests) | **24 tests, 0 failures** (2026-10-10, whole-scheme run). The six cases that failed here before failed on the harness's activity, not on the app: `.forward` observes and never admits, so the window held the anchor card alone. Each one now produces once and admits with `.explicitTailApproach`, the activity the real shell sends when the reader moves forward and the tail is visible. |
| `FeedMineUITests` as one run (21 tests) | **21 tests, 0 failures** (2026-10-10, whole-scheme run — the acceptance this round was aiming at; it was 16 failing before the repairs). The cause of the earlier failures was *not* shared simulator state: the app keeps no `UserDefaults` and every test already launches with its own `FEEDMINE_RUNTIME_NAMESPACE`. It was `.accessibilityIdentifier` on a SwiftUI *container* overriding its children's identifiers on this toolchain (iOS 26.5 / Xcode 26.6) — a defect the repository had already met and fixed once, for the search bar (`Sources/FeedMineUI/Reader/ReaderShell.swift:102`) — plus the destinations the menu was not offering, and the interaction and product defects listed below. |
| Physical iPhone: 10 minutes idle + 30 minutes of scrolling, memory/CPU/hitches and media budget | **Not executed.** No physical device is attached to this machine (`xcrun devicectl list devices`, 2026-10-10: two iPhones known, both `unavailable`); the plan's own validation section asks for a simulator UUID for everything else. Needs the reader's device. |
| Visual comparison by screenshots, surface by surface | **Not executed as a screenshot diff.** The UI tests assert structure, identifiers, labels and one geometry (the mini player's 56 pt); no pixel comparison was made. |
| 30-minute scroll budget on heterogeneous networks | **Not executed.** The deterministic, short-horizon scenario is the substitute that was run; long-horizon behaviour is the physical-device item above. |

Anything not listed as executed above has no claim attached to it.
