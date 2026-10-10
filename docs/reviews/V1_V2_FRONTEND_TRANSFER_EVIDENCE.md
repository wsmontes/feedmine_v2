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
DEBUG-only catalogue explorer, recorded above).

## The integrated scenario (T12, item 3)

`TransferScenarioTests.testT12ContentArrivingWhileTheReaderIsStillLeavesTheirCardsInPlace` — **1 test, 0
failures**. While the reader is still, four kinds of arrival land in order: a slow source finally publishing (the
reserve grows behind them), a decode arriving late (the same frozen cards), an edit to an article already read
(its own new occurrence, appended), and a foreground reporting work. Asserted: the admitted prefix is the same
cards in the same order with the same content, the reserve grew, the edit arrived at the end, a *stale
projection* is refused outright, and only a gesture reaches the host. The frame/offset half of the same promise
is proven where it can be measured — `FeedPresentationAdmission`'s own tests, `FeedScreenStoreTests`'
invariance, and the simulator test below.

## Native gestures, rotation and Dynamic Type (T12, item 4)

`testNativeScrollRotationAndDynamicTypeKeepTheAdmittedCardInPlace` — **TEST SUCCEEDED** (simulator, launch
argument `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXL`): six swipes down, six
back, a real driver opportunity published in both directions, a rotation to landscape and back whose delivered
counters do not change, and the feed still readable throughout.

`testNativeSwipeReachesRealRunwayAndReverseNavigation` — **TEST SUCCEEDED** (the T3 gesture test that already
existed): the first delivery is `received=0 completed=0 backward=0`, i.e. restore and layout are not a user
observation, and a swipe is what completes one.

## Offline and relaunch (T12, item 6)

`testOfflineRelaunchKeepsFilterSavedCardAndFeed` — **TEST SUCCEEDED**: a filter applied, a card saved, then the
app terminated and relaunched **with the network blocked**; the feed the reader had is still readable, the saved
list opens, and the filter is still applied. The state that survives there is the reader's own: preferences,
selection, library and published history.

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

## Not executed, and why

| Plan item | State |
|---|---|
| `CompositionTests` as one run (20 tests) | **6 of 20 fail, and none of them is claimed above.** Measured 2026-10-10: 13 pass; `testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates` (reserve 1 ≠ 17), `testS1SameSessionStoreAcrossViewportRefreshAndLifecycle`, `testS2DelayedResultAndS7AtomicWorkRejection`, `testS5OfflineReopenRestoresEditionWithFreshProvenance`, `testS6NewerReverseProjectionAccepted` and `testMainSourceMainRestoresPositionOfflineAndRejectsOldAssociation` fail at their *first* supply assertion — the fixture run admits the anchor card and no second one. The committed HEAD cannot run them either: its test target does not compile (`saveCuratedFeed` returns `ReaderPreset?` while the committed test treats it as non-optional), so no green baseline exists to compare against. Two causes were measured and **disproved** on 2026-10-10: the fixture items lack a `pubDate`, and their links point at `fixture.invalid` instead of the feed's own host (`-only-testing` the two representative tests, both still failing). The admitted-and-prepared supply is where the next diagnostic belongs. Every claim in this document is per test, because that is how the runs were made. |
| Physical iPhone: 10 minutes idle + 30 minutes of scrolling, memory/CPU/hitches and media budget | **Not executed.** No physical device is attached to this machine; the plan's own validation section asks for a simulator UUID for everything else. Needs the reader's device. |
| Visual comparison by screenshots, surface by surface | **Not executed as a screenshot diff.** The UI tests assert structure, identifiers, labels and one geometry (the mini player's 56 pt); no pixel comparison was made. |
| 30-minute scroll budget on heterogeneous networks | **Not executed.** The deterministic, short-horizon scenario is the substitute that was run; long-horizon behaviour is the physical-device item above. |

Anything not listed as executed above has no claim attached to it.
