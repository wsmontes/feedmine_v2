# UI transfer matrix — V1 frontend → V2

Task T1 of `docs/superpowers/plans/2026-10-09-transferencia-frontend-v1-v2.md`.
Spec: `docs/reviews/2026-10-09-v1-ui-and-scroll-barrier-analysis.md`,
`docs/product/PRODUCT_DECISIONS_2026-10-09.md`.

Purpose: **any control visible in V1 can be located here, with the symbol that
implements it and the delivery (T4–T11) that must carry it into V2.** A control
whose row says `incompleto` has no destination yet and blocks a parity claim.

## How to read this

| Column | Meaning |
| --- | --- |
| `surface` | The user-facing surface (screen region, sheet, modal). |
| `v1Path` | File in `/Users/wagnermontes/Documents/GitHub/feedmine` (relative to `feedmine/`). |
| `v1Symbol` | Type/function/property that renders or executes it, with the line range observed. |
| `v1Revision` | `712a6ba` unless the V1 working tree differs at that file (see `V1_UI_REFERENCE.md`). |
| `actions` | Every reachable action with its trigger, execute symbol and the service it touches. |
| `dataDependencies` | What the surface reads; V2 must supply this without a View touching storage/network. |
| `v2Path (delivery)` | Destination component and the plan task that owns it. |
| `proof` | Evidence for the row: a source citation today; an artifact (screenshot/test/command) once validated. |
| `status` | `inventariado` (located, not started) · `em transferência` · `validado`. |

Status vocabulary is the plan's. **Flipped by T12 (2026-10-10)** against the executed record in
`docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md`: of the 100 rows, **49 `validado`**, **43 `em transferência`**
and **8 `inventariado`** (the counters at the end of each section add up to those). A row is `validado` only
where the evidence doc records an executed test, UI test or command that covers that row, named in `proof`; a row
whose delivery landed but whose control has no proof of its own is `em transferência`; a row left `inventariado`
is one V2 deliberately does not carry (DEBUG-only UI, an unreachable V1 surface, or an accepted difference —
§10). **No row claims visual parity**: the screenshot comparison was not executed, so every `proof` that touches
a visual surface says so, and each `shot` citation is the V1 reference only.

### Evidence classes used in `proof`

- `src` — a citation into the V1 checkout (`path:symbol:line`), verified by reading the file.
- `shot` — `docs/evidence/v1-ui/<file>.png`, captured under the conditions in `V1_UI_REFERENCE.md`. These are
  **V1 references**: no V2 screenshot was compared against them (see §11 and the evidence doc's "Not executed").
- `test` — a V2 test, added by the delivery that claims the row.
- `uitest` — a V2 UI test that taps the real control.

---

## 0. Facts fixed with this inventory

| Fact | Value |
| --- | --- |
| V1 revision | `712a6ba` + comment-only dirty `feedmine/Views/FeedScreen.swift` (see reference doc) |
| V1 screen root | `Views/FeedScreen.swift` — 2445 lines, one `ZStack` with a **floating** header overlay (no `safeAreaInset`) |
| V2 revision at T1 | `372f4c5` |
| V2 UI today | `Sources/FeedMineUI` (9 files, ~1024 lines): `FeedScreen`, `FeedCardView`, `FeedDesignTokens`, `FeedPreparationView`, `FeedSourcePicker`, `FeedSavedListView`, `FeedPresentationState`, `FeedScreenStore`, `FeedLoadingView` |
| Transfer rule | V1 layout code is copied; integration/data come from V2 `Domain`/`Runtime`/`Composition`. No `FeedStore`/`FeedLoader`/`Reservoir` copy. |

---

## 1. Reader shell — `FeedScreen.swift`

**T5 state (2026-10-09).** The shell, the header, the overflow menu, the search bar and the feedback views
are transferred (`Sources/FeedMineUI/Reader/**`, `Feedback/**`); the V2 navigation toolbar and the U3 context
bar are gone. Rows below therefore read: **`em transferência`** for the header controls, the menu vocabulary
and the search bar; **`inventariado`** for everything whose *flow* arrives later — the lens bar (T6), the
unified search results panel (T6), the destination sheets the host cannot present yet (T7–T11) and the DEBUG
catalog button (not transferred). The menu *values* exist for all 14 V1 items; the host renders only the ones
it implements, so `Fontes` and the bookmark boxes are live today and the rest are not shown rather than dead.

**Flipped by T12 (2026-10-10).** The per-row `status` values below are the T12 state, not this T5 one: where an
executed UI test taps the control (the bookmark boxes button, the filter button, the overflow menu and the
destinations it offers) or where a named package test asserts the row's own subject (the search surface's
submission state, the header's identifiers, the shell's own measurement) the row is now `validado`; everything
else stays `em transferência`, and the rows V2 does not carry stay `inventariado`.

### 1.1 Header (floating overlay)

| surface | v1Path | v1Symbol | actions | dataDependencies | v2Path (delivery) | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Compact header (chip + 4 buttons) | `Views/FeedScreen.swift` | `compactHeader` 502–653; background `.ultraThinMaterial` + `Divider` 0.3 at 638–644; `readHeaderHeight` via `HeaderHeightKey` 1595/1618 | see rows below | `runtime.sessionChipStatement`, `runtime.sessionLoadingStatement`, `loader.activeFilterCount`, `loader.selectedBookmarkListID` | `Sources/FeedMineUI/Reader/ReaderHeader.swift` (**T5**) | test `ReaderShellTests.testHeaderControlsAndFeedbackAreTheV1Ones` (the four V1 ids present, 44×44, `.ultraThinMaterial`) + `testShellMeasuresOnlyItsOwnChrome`; the chip and three of the four buttons are tapped by the uitests named in the rows below (the search toggle is not); `shot feed-portrait-light.png` is the V1 reference, no V2 diff executed | em transferência |
| Search toggle | idem | 518–531 | `magnifyingglass` → `applySearchScopeToLoader()`, `isSearching=true`, `searchFocused=true`; when searching `magnifyingglass.circle.fill` → `closeSearch()` | `loader.searchQuery` | `ReaderHeader` + `ReaderNavigation` (**T5**) | test `ReaderShellTests.testSearchSurfaceReportsOneSubmissionAndStartsNoWork` (one submission, `cancelSearch` clears the query, no work started) + `testHeaderControlsAndFeedbackAreTheV1Ones` (`search-button` present) + uitest `testT12KeyboardSearchKeepsTheReadingPointAndRestoresIt` (taps `search-button`, raises the field, cancels it) — the V1 search-open shot is missing and no V2 diff was made | `validado` |
| Bookmark boxes | idem | 532–544 | `bookmark`/`bookmark.fill` + 6 pt dot when `selectedBookmarkListID != nil` → `showBookmarks=true`, haptic `.light` | `loader.selectedBookmarkListID` | `BookmarkBoxesView` (**T8**) + `ReaderHeader` (**T5**) | uitest `testBookmarkBoxesManageAndOpenTheirOwnList` taps `bookmark-boxes-button` (create a box, open it, reopen it) + `BookmarkBoxesBackendTests` (6); no screenshot diff | validado |
| Filters | idem | `filterButton` 911–933 | `line.3.horizontal.decrease` + badge when `activeFilterCount > 0` → `showFilters=true`, haptic | `loader.activeFilterCount` | `FilterSheetView` (**T6**) + `ReaderHeader` (**T5**) | uitest `testT6FilterSheetOpensAppliesAndKeepsTheReader` and `testOfflineRelaunchKeepsFilterSavedCardAndFeed` both tap `filter-button`; test `ReaderFilterStoreTests`; no screenshot diff | validado |
| Catalog explore (**DEBUG only**) | idem | 547–555 | `books.vertical` → `showCatalogExplore=true` | `CatalogBrowserViewModel` | `Sources/FeedMineUI/Sources/CatalogExploreView.swift` (**T7**) | not transferred — accepted difference: V1's paginated browser is DEBUG-only (evidence doc, "The DEBUG-only catalogue explorer"); no such file exists in V2 (§10 records the decision) | inventariado |
| Ellipsis menu | idem | `Menu` 556–635 | see 1.2 | `loader.activePreset` family, `loader.presentationContext` | `ReaderMenu` (**T5**) | uitest `testContextNavigationAndSourcePickerOffline`, `testCollectionsManageAndReachThePresetPicker`, `testSettingsReachTheirControlsAndSurviveReopening` and `testImportPreviewCommitsAndExportPreviews` all tap `more-menu` and navigate; test `ReaderShellTests.testMenuShowsOnlyDestinationsTheHostCanPresent` (only presented destinations render, 14 V1 entries exist as values); no screenshot diff | validado |
| Debug info (DEBUG) | idem | `CompactDebugInfo` 508; triple-tap toggle 1851–1861 (`showDebugBar` `@AppStorage`, gate 62–68) | replaces the chip with counters | debug counters | **not transferred** (debug-only; keep V2's DEBUG overlay) — recorded, not a parity gap | not transferred — §10 records the decision; no V2 counterpart | inventariado |

### 1.2 Ellipsis menu items (conditional paths included)

**T5:** all 14 items exist as `ReaderMenuEntry` values with V1's labels, symbols, roles and grouping
(`Sources/FeedMineUI/Reader/ReaderNavigation.swift`). `FeedScreenStore.menuEntries` renders
`availableDestinations ∩ standard`, and `AppComposition.readerDestinations = [.sources, .bookmarkBoxes]`
today, so only those two are reachable; each remaining item joins when its delivery lands (T7 sources/catalog,
T8 collections/bookmarks/presets, T10 add-feed/export/import, T11 curation).

| action | trigger condition | symbol/icon | executes | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- |
| Create Curated Feed | always | `wand.and.stars` | `showCuratedOnboarding=true` | T11 | test `CuratedFeedCoordinatorTests.testSavingResolvesTheIdentityAndKeepsTheRecipe` + app `testT11ACuratedFeedRanksByItsRecipeAndEditingChangesTheBehaviorVersion` (the recipe governs the session); the menu entry itself is not tapped (the T11 uitest enters through the onboarding gate); no screenshot diff | em transferência |
| Open Curated Feed hood | `activePreset.isCuratedFeed` | `slider.horizontal.3` | `showCuratedInspector=true` | T11 | uitest `testOnboardingWelcomeComposerAndSave` taps "Abrir o capô do feed curado" and asserts `hood-badge`/`hood-privacy` + `CuratedFeedCoordinatorTests.testInspectingStatesTheReadersOwnAnswers`; no screenshot diff | validado |
| Delete Curated Feed | `activePreset.isCuratedFeed` | `trash` (destructive) | `showDeleteCuratedFeedConfirmation=true` | T11 | test `CuratedFeedCoordinatorTests.testDeletingAFeedLeavesTheSelectionAlone`; the confirmation alert is not tapped by any executed uitest; no screenshot diff | em transferência |
| Save as Smart Bookmark | `isSearching && hasCommittedSearch && scope allows` | `sparkles.rectangle.stack` | `prepareSmartFeedFromSearch()` 1206–1213 → `createSmartFeedFromSearch` 1215–1234 → `loader.createSmartFeed` + `setActivePreset(.smartFeed)` + `closeSearch()` | T6/T8 (preset identity) | app `testT8ASavedPresetIsOfferedAndActivatesItsOwnContext` (a search context saved under a name, offered with its whole identity, activated) + `ReaderLibraryCoordinatorTests.testSavingAContextMakesItsKeyNameItsOwnPreset`; the menu entry is not tapped on screen; no screenshot diff | em transferência |
| Collect these sources | `hasCommittedSearch \|\| activeFilterCount >= 2` | `folder.badge.plus` | `prepareCollectionFromContext()` 1174–1186 → alert → `createCollectionFromContext` 1188–1204 → `loader.createSourceCollection` + `addSource` | T8 | app `testT8ASavedPresetIsOfferedAndActivatesItsOwnContext` (collects the context's sources) + `ReaderLibraryCoordinatorTests.testCollectingSourcesFillsOneCollectionAndKeepsTheSelection`; the alert path is not tapped on screen; no screenshot diff | em transferência |
| Export collection | `collectionID != nil` | `square.and.arrow.up` | `showCollectionExport=true` → `CollectionOPMLExportView` 1516–1577 (ShareLink) | T10 | test `ReaderImportExportCoordinatorTests.testEveryFormatWritesItsOwnDocumentAndACollectionExportsItsMembers`; the collection's own export entry is not opened by an executed uitest (T10's uitest exports from the reader menu); no screenshot diff | em transferência |
| Import to collection | `collectionID != nil` | `square.and.arrow.down` | `showCollectionImporter=true` (`.fileImporter` xml/opml 421–426) → `handleCollectionImport` 1260–1304 | T10 | test `ReaderImportExportCoordinatorTests.testThePreviewWritesNothing`, `testCommitSelectsAndIsIdempotent`; the collection importer's file picker is not exercised on screen (T10's uitest imports from the sources screen); no screenshot diff | em transferência |
| Add feed to collection | `collectionID != nil` | `link.badge.plus` | `showAddFeed=true` with target collection | T10 | not drawn as its own sheet (T10 state: membership is set from a card's action, the collection detail's removal and an import); `ReaderLibraryCoordinatorTests.testCollectingSourcesFillsOneCollectionAndKeepsTheSelection` covers the write; no screenshot diff | em transferência |
| Delete Smart Bookmark | `activePreset.isSmartFeed` | `trash` | `showDeleteSmartFeedConfirmation=true` → `deleteActiveSmartFeed` 1236–1246 | T8 | `ReaderLibraryStoreTests.testPresetsRoundTripTheirIdentityAndAreKindOrdered` and `CuratedFeedCoordinatorTests.testDeletingAFeedLeavesTheSelectionAlone` cover preset deletion; the confirmation alert is not tapped on screen; the entry is offered only on one of the reader's own presets (T8 state); no screenshot diff | em transferência |
| Add Feed | always | `plus.circle` | `showAddFeed=true` | T10 | not drawn as a menu entry (T8/T10 state); the import surface is proven on screen by uitest `testImportPreviewCommitsAndExportPreviews` (`import-summary`, `import-confirm`, the "Importadas 1" toast) + `ReaderImportExportCoordinatorTests` (6); no screenshot diff | em transferência |
| Export | always | `square.and.arrow.up` | `showExport=true` | T10 | uitest `testImportPreviewCommitsAndExportPreviews` taps "Exportar" (`export-scope-selection`, `export-share`, `export-preview`) + `ReaderImportExportCoordinatorTests` (6); no screenshot diff | validado |
| Source Collections | always | `rectangle.stack.fill` | `showCollections=true` | T8 | uitest `testCollectionsManageAndReachThePresetPicker` (`collections-empty`, `collections.new`, detail, `collection.openFeed`) + `ReaderLibraryStoreTests.testCollectionsGroupSourcesAndDeletingOneKeepsThem`; no screenshot diff | validado |
| Sources | always | `antenna.radiowaves.left.and.right` | `showSources=true` | T7 | uitest `testContextNavigationAndSourcePickerOffline` taps "Fontes" (`source-choice-*`, "Concluir") + uitest `testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack`; test `SourceManagementCoordinatorTests`, `SourceManagementStoreTests`; no screenshot diff | validado |
| Settings | always | `gearshape` | `showSettings=true` | T10 | uitest `testSettingsReachTheirControlsAndSurviveReopening` taps "Ajustes" and writes/re-reads two preferences + `ReaderSettingsCoordinatorTests` (5); no screenshot diff | validado |

### 1.3 Search bar and unified search panel

**T5:** the search *surface* (field, submit, explicit cancel) is transferred and a submission still becomes the
same search context the toolbar field used to submit; the results panel stays `inventariado` (T6 owns search as
a context with results).

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Search bar | `Views/FeedScreen.swift` | `searchBar` 655–716; `TextField` id `unified-search-field`; chips id `search-term-tags` | Return → `commitSearchDraft()` 1318–1334 → `loader.submitSearchTerms`; `+` `plus.circle.fill` → same; `Cancel` → `closeSearch()` 1306–1312; chip `xmark` → `removeSearchTerm(term)` 722–732; toggles Sources/Contents (`checkmark.square.fill`/`square`) 776–791 bind `searchIncludesSources`/`searchIncludesContents` (277/283) → resubmit; `searchActivityLine` 735–766 is status-only | `loader.searchQuery`, `submittedSearchTerms`, `searchIncludesSources/Contents`, `isSearchLoading/Scanning`, `searchScannedSourceCount` | `ReaderSearchBar` (**T5**), search context (**T6**) | test `ReaderShellTests.testSearchSurfaceReportsOneSubmissionAndStartsNoWork` (one submission; `cancelSearch` clears the query; no work started) + `testHeaderControlsAndFeedbackAreTheV1Ones` (`search-button`) + uitest `testT12KeyboardSearchKeepsTheReadingPointAndRestoresIt` (taps the field, types a query, asserts the feed's counters do not move, cancels and asserts the reader is restored); no screenshot diff | `validado` |
| Unified results panel | idem | `unifiedSearchPanel` 793–864; id `unified-search-results`; top padding = `headerHeight + searchControlsHeight` 862 | row tap → `searchFocused=false` + `selectedSource = source.sourceReference` (812–816); context menu `View Source` (819–823) → same; `Add Source to Collection` (824–826) → `sourceToCollect`; saved/local row tap → `loader.markAsClicked(id)` + `articleItem = item` (884–889) | `loader.unifiedSearchResults` (sources/savedItems/localItems) | `ReaderSearchResults` (**T5**), search semantics (**T6**) | no such surface exists: there is no `ReaderSearchResults` symbol in `Sources/FeedMineUI` and no executed test covers a unified results panel; T6 owns search as a context with results — not delivered | inventariado |

### 1.4 Feed content, sections and scroll

**T5:** the chrome no longer changes the feed's geometry — the header is measured by the shell itself
(`ReaderHeaderHeightKey`) and the work feedback is a constant-height non-interactive overlay (T3). The
scroll-driven lens state and the lens bar remain `inventariado` for T6.

| surface | v1Path | v1Symbol | actions / behaviour | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Content branch selection | `Views/FeedScreen.swift` | `screenContent` 129–188; branches 139–155 | `persistenceUnavailable` → `ContentUnavailableView` id `persistent-store-unavailable`; searching → `unifiedSearchPanel`; runtime session → `sessionFeedContent` 197–228; else `legacyFeedContent` 229–251 | `loader.persistenceUnavailable`, `runtime.sessionSurface`, `loader.feedDisplayPhase` | `ReaderShell` + V2 `FeedScreen` (**T5**); V2 has no legacy branch | test `ReaderShellTests.testShellMeasuresOnlyItsOwnChrome` (the shell references no store, production or `URLSession`) + the executed T12 audit (`Sources/FeedMineUI` has neither `FeedStore`/`FeedLoader` nor any I/O); the states themselves are not exercised per branch; `shot feed-portrait-light.png` is the V1 reference, no V2 diff | em transferência |
| Feed scroll view | idem | `feedScrollView` 946–1078 | `LazyVStack(spacing: engine.cardGap)`; ForEach sections → `FeedItemView` 975–1012; section header when `showsHeader` 1018; `EmptyFilterView` 1026; `EndOfFeedFooterView` 1033 (`checkmark.circle`, inert); `.refreshable` 1049 → `runtime.refresh()`; `.padding(.top, feedTopPadding)` 1047 | `runtime.presentation.sections/rows` | `Reader/FeedScrollView` sequence (**T3/T5**) | uitest `testNativeSwipeReachesRealRunwayAndReverseNavigation` (a real swipe completes a real driver opportunity) + `testNativeScrollRotationAndDynamicTypeKeepTheAdmittedCardInPlace` (six swipes each way, rotation) + `testOfflineRelaunchKeepsFilterSavedCardAndFeed`; shots `feed-portrait-light.png`/`feed-landscape.png` are the V1 reference, no V2 diff executed | validado |
| Header geometry coupling | idem | `feedTopPadding` 478–481 = `max(48, headerHeight) + (isSearching ? searchControlsHeight : (isFilterLensVisible ? 20 : 0))` | content padding tracks measured header height (`HeaderHeightKey`/`SearchControlsHeightKey` 1595–1633) | measured heights | `ReaderShell` (**T5**); V2 must not use variable `safeAreaInset` (analysis §4, T3) | test `ReaderShellTests.testShellMeasuresOnlyItsOwnChrome` (`onPreferenceChange(ReaderHeaderHeightKey.self)`, `headerHeight = height`) + `testHeaderControlsAndFeedbackAreTheV1Ones` (FeedScreen has no `safeAreaInset`); no screenshot diff | validado |
| Scroll-driven header/lens state | idem | `handleScrollOffset` 1373–1388; `revealFilterLens`/`collapseFilterLens`/`scheduleFilterLensCollapse` (4 s auto-collapse)/`dismissFilterLensForCurrentSelection`/`handleFilterLensContentChange` 1390–1452 | scroll offset > 40 sets `userHasScrolled`; delta > 8 → collapse; delta < −8 → reveal; only when `hasFilterLensContent && !isSearching && !dismissed` | scroll geometry + `loader.activeFilterCount` | `ReaderHeader`/`FilterLensBar` (**T5/T6**) | the collapse/reveal rule and the 4 s auto-collapse have no executed proof: the T12 gesture test asserts the admitted card does not move, not the lens state; no screenshot diff | em transferência |
| Viewport reporting | idem | `handleViewportChanged` 1359–1370; card visibility 993–1012 with `MainFeedRuntime.cardVisibilityThreshold` | `runtime.viewportChanged(visibleItemIDs:)`, `loader.noteViewport(lastVisibleOrdinal:)`, `runtime.cardBecameVisible(itemID:)` | visible IDs + ordinals | **Bridges to V2** `FeedScreenStore.onViewport` → driver (**T3**); semantics change: V2 admits by forward scroll only | uitest `testNativeSwipeReachesRealRunwayAndReverseNavigation` ("received=0 completed=0 backward=0" before the gesture; a swipe completes one; a reverse gesture reaches the same driver) + `FeedRunwayDriverTests`; `TransferScenarioTests.testT12ContentArrivingWhileTheReaderIsStillLeavesTheirCardsInPlace` (only a gesture reaches the host; a stale projection is refused); no screenshot diff | validado |
| Shake to refresh | idem | `ShakeDetector` 167–174 | runtime session → `runtime.refresh()`; legacy → `loader.shakeToRefresh()` | motion | **T5** (keep gesture) or explicit "not transferred" decision | not transferred: no `ShakeDetector` exists in `Sources/FeedMineUI`; the decision remains open (§10, owner T5) | inventariado |
| Empty states | idem | `emptyMode` 82–120, `FeedEmptyStateView` 381 lines | lanes: no sources enabled / fetching(topic, fetched, total) / no results / generic; actions `Open Filters`, `Refresh Now` | `loader` counters, `TaxonomyStore.node.feedCount` | `Sources/FeedMineUI/Reader/EmptyState` (**T5**) | uitest `testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack` proves the no-sources lane on screen (`feed-empty-title` = "Nenhuma fonte habilitada", `feed-empty-action` → sources); the fetching / no-results / generic lanes have no executed proof; no screenshot diff | em transferência |
| First-run loading | idem | `InitialFeedLoadingView` 2244–2377 (`StartupSignalView` TimelineView, 13 capsules 5 pt, `.drawingGroup()`, `.disabled(true)`) | inert animation while preparing | runway counters | `FeedPreparationView` (V2 exists; parity check in **T11**) | test `PreparationProgressTests` (`testQuietHTTPSuccessIsNotPreparationReadiness`, `testSourcesHeadlinesAndMeasuredEstimate`) proves the progress facts; the loading view's shape/animation parity has no executed proof; no screenshot diff | em transferência |
| Filter lens bar | `Views/TaxonomyChipBar.swift` | `FilterLensBar` + `FilterLensChip` (199 lines) | swipe up/side (`DragGesture` min 16) 76–88 → `onDismiss` → `dismissFilterLensForCurrentSelection`; chips: preset `preset.icon` → `loader.setActivePreset(.everything)` 24–32; search `magnifyingglass` → `clearSubmittedSearch` 37–42; region `globe.americas.fill` → `clearRegionFilter` 45–50; type → `loader.selectContentType(contentType)` 53–58; topic `tag.fill` → `loader.toggleNode(id)` 61–68; language `character.bubble.fill` → `loader.toggleLanguage(code)` 69–78; mood `mood.icon` → `loader.selectMood(mood)` 79–86 | active filter summary | `Sources/FeedMineUI/Filters/ReaderFilterLens.swift` (**T6**) | uitest `testT6FilterSheetOpensAppliesAndKeepsTheReader` taps a `lens-chip-language-*` chip and that criterion clears + `ReaderFilterStoreTests.testLensChipsMirrorTheAppliedSelection`; the swipe-up dismissal has no executed proof; no screenshot diff | validado |

### 1.5 Modal stack (17 presentations)

`screenWithSheets` 358–472. One destination each; V2 replaces the 11 booleans with one
typed presentation (plan T5). **T12 note:** this table has no `proof` column, so each row states its class and
what it covers inside the `status` cell.

| state variable | presentation | v2 destination | status |
| --- | --- | --- | --- |
| `articleItem` | `ArticleReaderView` (`.sheet(item)`) 360–367 | T9 | `em transferência` — T9 delivered the article open as `InAppBrowser` (`SFSafariViewController`, U2 decision); no executed uitest opens an article (T9's evidence names the card-copy and mini-player tests); `shot article-reader-inapp.png` is the V1 reference, no V2 diff; V1's loading bar and explicit Safari link have no counterpart |
| `selectedSource` | `SourceFeedView` 368 | T7 | `em transferência` — the source surfaces (management, countries, node levels) are proven (`testContextNavigationAndSourcePickerOffline`, `testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack`, `SourceManagementStoreTests`), but no executed test opens a source's own feed |
| `sourceToCollect` | `AddSourceToCollectionSheet` 369 | T8 | `em transferência` — the sheet is not drawn: membership is set from a card's action, the collection detail's removal and an import (T8/T10 state); `ReaderLibraryCoordinatorTests.testCollectingSourcesFillsOneCollectionAndKeepsTheSelection` covers the write |
| `showSettings` | `SettingsSheetView` 370 | T10 | `validado` — uitest `testSettingsReachTheirControlsAndSurviveReopening` opens `Ajustes` and writes/re-reads two preferences; `ReaderSettingsCoordinatorTests` (5); no screenshot diff |
| `showSources` | `SourceManagementView` 371 | T7 | `validado` — uitest `testContextNavigationAndSourcePickerOffline` and `testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack` (`sources-open-countries`, `country-toggle-*`, `sources-enabled-count`, `countries-done`); `SourceManagementStoreTests`; no screenshot diff |
| `showFilters` | `FilterSheetView` 372 | T6 | `validado` — uitest `testT6FilterSheetOpensAppliesAndKeepsTheReader` (`filter-done`, `language-*`, `filter-clear-all`) + `ReaderFilterStoreTests`; no screenshot diff |
| `showBookmarks` | `BookmarkBoxesView` 373 | T8 | `validado` — uitest `testBookmarkBoxesManageAndOpenTheirOwnList` (create, open, reopen); `BookmarkBoxesBackendTests` (6); no screenshot diff |
| `showAddFeed` | `AddFeedView(targetCollectionID:targetCollectionName:)` 374–379 | T10 | `em transferência` — not drawn as its own sheet (T8/T10 state); the import surface is proven on screen by uitest `testImportPreviewCommitsAndExportPreviews`; no screenshot diff |
| `showCollections` | `CollectionManagementView` 380 | T8 | `validado` — uitest `testCollectionsManageAndReachThePresetPicker` (empty state, create, detail, `collection.openFeed`); `ReaderLibraryStoreTests.testCollectionsGroupSourcesAndDeletingOneKeepsThem`; no screenshot diff |
| `showExport` | `ExportView` 381 | T10 | `validado` — uitest `testImportPreviewCommitsAndExportPreviews` taps "Exportar" (`export-scope-selection`, `export-share`, `export-preview`); `ReaderImportExportCoordinatorTests` (6); no screenshot diff |
| `showCuratedOnboarding` | `.fullScreenCover` → `CuratedOnboardingView(isFirstRun:false)` 382–393 | T11 | `validado` — uitest `testOnboardingWelcomeComposerAndSave` runs welcome → composer → save (entered from the onboarding gate; the menu's own entry is not tapped); `CuratedFeedCoordinatorTests` (6); no screenshot diff |
| `showCuratedInspector` | `CuratedFeedInspectorView(curatedFeedID)` 394–398 | T11 | `validado` — uitest `testOnboardingWelcomeComposerAndSave` opens the hood (`hood-badge`, `hood-privacy`, `hood-close`); `CuratedFeedCoordinatorTests.testInspectingStatesTheReadersOwnAnswers`; no screenshot diff |
| `showCollectionExport` | `CollectionOPMLExportView` 399–406 | T10 | `em transferência` — `ReaderImportExportCoordinatorTests.testEveryFormatWritesItsOwnDocumentAndACollectionExportsItsMembers`; the collection export sheet is not opened by an executed uitest; no screenshot diff |
| `showCatalogExplore` | `CatalogExploreView(repository)` 407–418 | T7 | `inventariado` — not transferred: DEBUG-only browser (evidence doc, "The DEBUG-only catalogue explorer"); no `CatalogExploreView` exists in `Sources/FeedMineUI` (§10 records the decision) |
| `showCollectionImporter` | `.fileImporter` (xml/opml) 421–426 | T10 | `em transferência` — `ReaderImportExportCoordinatorTests.testThePreviewWritesNothing`, `testCommitSelectsAndIsIdempotent`; the collection importer's file picker is not exercised on screen (T10's uitest imports from the sources screen); no screenshot diff |
| `showCreateCollectionPrompt` | `.alert` + TextField 427–434 | T8 | `validado` — uitest `testCollectionsManageAndReachThePresetPicker` taps `collections.new`, types a name and taps `Criar`; `ReaderLibraryStoreTests.testCollectionOrderingAndNamingBehaveLikeBoxes`; no screenshot diff |
| `showCreateSmartFeedPrompt` | `.alert` + TextField 435–442 | T6/T8 | `em transferência` — app `testT8ASavedPresetIsOfferedAndActivatesItsOwnContext` saves a search context as a preset through the host; the alert path is not tapped on screen |
| `showDeleteSmartFeedConfirmation` | `.alert` 443–450 | T8 | `em transferência` — `ReaderLibraryStoreTests.testPresetsRoundTripTheirIdentityAndAreKindOrdered` covers the store's preset deletion; the confirmation alert is not tapped on screen |
| `showDeleteCuratedFeedConfirmation` | `.alert` 451–458 | T11 | `em transferência` — `CuratedFeedCoordinatorTests.testDeletingAFeedLeavesTheSelectionAlone`; the confirmation alert is not tapped on screen |
| `nightMode` | overlay 420 (1121–1123: black 0.35, ignoresSafeArea, no hit testing) | T10 | `em transferência` — uitest `testSettingsReachTheirControlsAndSurviveReopening` toggles `settings-night-mode` and re-reads it; `ReaderSettingsCoordinatorTests.testTurningTheClockOffAndNightModeOverride`; the 0.35 overlay itself has no visual proof (`shot night-portrait.png` is the V1 reference, no V2 diff) |

Section totals: **shell 52 rows** (§1.1 7, §1.2 14, §1.3 2, §1.4 9, §1.5 20) — after T12: **23 `validado`**,
**24 `em transferência`**, **5 `inventariado`** (the DEBUG-only catalogue button, the DEBUG debug bar, the
unified search results panel, the shake gesture, and the DEBUG catalogue-explorer sheet).

---

## 2. Cards

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Hero/thumbnail card | `Views/FeedItemCardView.swift` (557) | `FeedItemCardView`; band layout portrait/landscape; `cardOverlays`; `cardContextMenu` | context menu: bookmark/BookmarkBox (`BookmarkBoxContextMenu` 352–390 → `runtime.toggleBookmark(itemID:)` 391–411/455–478), `View Source` `rectangle.stack`, `Add Source to Collection` `rectangle.stack.badge.plus`, `Copy Link` `doc.on.doc`, `Share as Image` `photo.artframe`, `Open in Safari` `safari` (http/https only) 536–544, `Share` `square.and.arrow.up` | `PreparedFeedCard`/`mediaSlot` (already-resolved media), read state, source/category | `Sources/FeedMineUI/Cards/FeedItemCardView.swift` (**T4**) + `ReaderCardAction` (**T4**) + execution (**T9**) | test `FeedCardTransferTests.testCardRendersFrozenFieldsAndNeverInventsText`, `testUnavailableActionsAreNotRendered` (every menu action gated on `availableActions`), `testReadAndBookmarkStatesDoNotChangeCardStructure`; the card's own menu reaches the clipboard in uitest `testCardCopiesItsOwnLinkAndStatesIt`; `shot t4-v2-ported-card.png` is structural only (colour fidelity owed, `PORT_LOG.md` §T4) and no V1/V2 diff was made; bookmark / view source / share-as-image / open-in-Safari / share are not tapped on screen | em transferência |
| Card wrapper / gestures | `Views/FeedItemView.swift` (218) | `FeedItemView` 36–120 | tap → `performCardAction` 76–88 (`CardActionBridge`/`MainFeedRuntime`); media-slot tap → audio playback via `AudioPlayerManager` 36–41/66; row context menu incl. `ShareLink(item.url)` 118–120 | item + runtime action bridge | `Cards/FeedItemView.swift` (**T4**), actions (**T9**) | uitest `testCardCopiesItsOwnLinkAndStatesIt` long-presses a card and takes `Copiar link` (the "Link copiado" toast states it), so the gesture reaches the host; `ReaderActionCoordinatorTests` (4) proves open/copy/share resolve from the occurrence's frozen fields; the tap → article and the media-slot tap have no executed uitest; no screenshot diff | em transferência |
| Compact row | `Views/FeedItemRowView.swift` (125) | `FeedItemRowView` | no own menu; row rendering only | `mediaSlot` | `Cards/FeedItemRowView.swift` (**T4**) | `FeedCardTransferTests` covers the shared composition, but no executed test draws the compact row specifically; no screenshot diff | em transferência |
| Card media contract | `Models/PreparedFeedCard.swift`, `Models/FeedCardPresentation.swift` (deprecated bridge) | `PlaceholderKind`, `ResolvedImageAsset`, `RenderReadyMedia`, `PreparedCardLayout`, `PreparedFeedCard` | — (values) | frozen slot geometry + resolved asset | `Sources/FeedMineRuntime/PresentationCard.swift` (exists) + `Cards/**` (**T4**) | test `FeedCardTransferTests.testImageSlotKeepsFrozenGeometryWithoutDecodedPixels` (frozen slot ratio; releasing the pixels never changes the layout) + `testCardRendersFrozenFieldsAndNeverInventsText`; no screenshot diff | validado |
| Item model helpers | `Models/FeedItem.swift` (481) | `bestImageURL`, `youTubeThumbnailURL`, `canResolveArticleImage`, `hasPotentialImage`, `audioPlaybackURL`, `isPodcast`, `isTimeless`, `durationFormatted` | URL/audio resolution used by cards and player | item metadata | `FeedMineDomain`/`Runtime` values as needed (**T4/T9**) | no executed test targets these V1 helpers; V2 resolves media in `FeedMineMedia.MediaResolver`/`FeedMineRuntime`, and the slot contract is proven by `FeedCardTransferTests.testImageSlotKeepsFrozenGeometryWithoutDecodedPixels`; per-helper parity (YouTube thumbnails, duration formatting, timeless/podcast flags) is unproven | em transferência |

Section totals: **5 rows** — after T12: **1 `validado`**, **4 `em transferência`** (T4 ported the composition,
the row and the wrapper to `Sources/FeedMineUI/Cards/`; the action executions stay in T9). Transferred in
`4e304fa`…`12d4b65` line of work, see `PORT_LOG.md` §T4. Still open on these rows: the tap → article gesture, the media-slot tap and the compact row on screen, the semantic fields V1 badges/category need (T4 remainder, T7
taxonomy) and the colour-fidelity comparison.

**Rule carried into T4:** the card renderer never
downloads or decodes (V1 already had no download inside the card; only
`ShareCardImageView`, `MiniPlayerBar/FullPlayerView`, `StoryDuelCard` and
`SourceFeedView`/`SourceCollectionFeedView` did, i.e. §6/§8).

---

## 3. Filters

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Filter sheet | `Views/FilterSheetView.swift` (297) | `FilterSheetView` — local draft of preset/content-type/language/mood; **commits on `onDisappear`** (`applyFilterDraft`/`setActivePreset`), so a dismissed sheet still applies | set/clear each criterion; Done; dismiss | countries/topics/languages/mood lists; `FiltersStore` state in `FeedStore` | `Sources/FeedMineUI/Filters/FilterSheetView.swift` + `ReaderFilterDraft`/`ReaderFilterStore` (**T6**) | uitest `testT6FilterSheetOpensAppliesAndKeepsTheReader` (opens from `filter-button`, edits the draft, `filter-done` commits and the reader keeps the feed) + `ReaderFilterStoreTests.testDismissAppliesTheDirtyPartsExactlyOnce`, `testStaleDraftIsRefused`; V2 makes apply/cancel explicit; no screenshot diff | validado |
| Content filter view | `Views/ContentFilterView.swift` (222) | `ContentFilterView` | master toggle; templates; add custom rule (`+` alert); swipe-to-delete | `ContentFilterStore` (singleton) | `Filters/**` + `ReaderFilter` (**T6**) | V2 keeps only the master preference (`ReaderSettings.contentFiltersEnabled`, drawn as a switch in `SettingsSheetView`); the rule editor (templates, custom rules, swipe-to-delete) is not drawn; the rules themselves are proven by `ReaderFilterTests.testExclusionsNormalizeAndNeverExpire` and `ReaderFilterEligibilityTests.testExclusionsHideByHeadlineOrSummary`; no screenshot diff | em transferência |
| Content filter model/store | `Models/ContentFilter.swift` (197) | `ContentFilter`, `ContentFilterTemplate`, `ContentFilterStore` (`@MainActor @Observable` singleton, JSON in Documents) | excludes items by keyword; applied in filtering **and** ingestion (`recordHit`); declared to RuntimeV2 as mandatory filter | keyword rules | `FeedMineDomain.ReaderFilter` + persistence (**T6**) | test `ReaderFilterTests.testExclusionsNormalizeAndNeverExpire` (V1's exclusion rules, normalized, never expiring) + `ReaderFilterEligibilityTests.testExclusionsHideByHeadlineOrSummary` (the exclusions are consulted while candidates are produced, `ReaderFilterEligibility` in `CandidateProvider`) + `ReaderFilterStoreTests`; V1's separate `recordHit` cache is not reproduced as such; no screenshot diff | validado |
| Filter lens chips | `Views/TaxonomyChipBar.swift` | see §1.4 row | remove one criterion per chip | active criteria | `Filters/ReaderFilterLens.swift` (**T6**) | uitest `testT6FilterSheetOpensAppliesAndKeepsTheReader` taps a `lens-chip-language-*` chip and that criterion clears + `ReaderFilterStoreTests.testLensChipsMirrorTheAppliedSelection`; no screenshot diff | validado |
| Filter semantics (V1 behavior to copy) | `Services/FeedStore.swift` (`applyFilters`/`applyFiltersAsync`) | criteria are combined in **series (AND)**; exclusion caches per item (mood, content filter) keyed on filter state; auto-expiry (4 h) exists for region/taxonomy/type/mood/language but **not** for content filters | — | — | `ReaderFilter` + editorial/context identity (**T6**) | test `ReaderFilterTests` (`testActiveCriteriaAndRemovalTouchExactlyOneCriterion`, `testExpiryIsPendingAndResolvesOnlyTheOverlaySelection`, `testExclusionsNormalizeAndNeverExpire`, `testMoodRulesReproduceV1`, `testContentTypeVocabularyMatchesV1`) + `ContextIdentityPersistenceTests` + app `testT6FilterTransitionKeepsContextsSeparateAndStaleCallbackInert`; no screenshot diff | validado |

Section totals: **5 rows** — after T12: **4 `validado`**, **1 `em transferência`** (the content-filter rule
editor is not drawn). Open V2 questions recorded for T6: the V1 sheet has
no Cancel (draft commits on disappear) — V2's `ReaderFilterStore.apply(_:)` must make
apply/cancel explicit; and content filters currently have no auto-expiry.

---

## 4. Sources, catalog and taxonomy

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Source management | `Views/SourceManagementView.swift` (313) | `SourceManagementView` | category toggle → `loader.setCategoryEnabled`; source toggle → `loader.toggleSource`; health check → `URLSession` per URL; OPML import → `OPMLParser.parseImportedFile` + `loader.addSources`; `NavigationLink` → `ExportView` | `SourceRegistry`, category tree | `Sources/FeedMineUI/Sources/SourceManagementView.swift` + `SourceManagementCoordinator` (**T7**) | uitest `testContextNavigationAndSourcePickerOffline` + `testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack` (country list, toggles, enabled count, done) + `SourceManagementStoreTests` (`testHealthReachesTheRowsAndTheSummary`) + `SourceManagementCoordinatorTests`; no screenshot diff | validado |
| Catalog explorer | `Views/CatalogExploreView.swift` (369) | `CatalogExploreView` over `CatalogBrowserViewModel`/`FeedEngineProtocol` | paginated browse; search; details sheet | catalog pages | `Sources/CatalogExploreView.swift` (**T7**) | not transferred: V1's paginated developer browser is DEBUG-only (evidence doc, "The DEBUG-only catalogue explorer"); the reader-facing catalogue surfaces it fronted are covered by `LegacyCatalogMetadataTests`, `SourceCatalogBackendTests` and `SourceManagementStoreTests.testSearchTrimsAndClears`; no V2 file exists | inventariado |
| Taxonomy browser | `Views/TaxonomyBrowseView.swift` (202) | `TaxonomyBrowseView` | `TaxonomyStore.shared.children/search/ancestors`; `loader.toggleNode` | taxonomy tree | `Sources/FeedMineUI/Filters/TaxonomyBrowseView.swift` (**T7**) | `Filters/TaxonomyBrowseView.swift` exists and `ReaderFilterStoreTests.testTaxonomyRowsAreValuesAndSelectionIsFilterState` proves the rows and the selection; no executed test opens the browser on screen; no screenshot diff | em transferência |
| Countries list | `Views/CountriesListScreen.swift` (101) | `CountriesListScreen` | `loader.setAllCountriesEnabled`; `setRegionEnabled`; navigate to detail | `CountryStore` | `Sources/FeedMineUI/Sources/CountriesListView.swift` (**T7**) | uitest `testEmptySelectionStatesItsOwnSurfaceAndOffersTheWayBack` opens `sources-open-countries`, toggles a `country-toggle-*` and taps `countries-done`; `SourceManagementStoreTests.testCountryRowsCarryFlagCountAndState`; no screenshot diff | validado |
| Country detail | `Views/CountryDetailScreen.swift` (126) | `CountryDetailScreen` | `loader.countryFeeds`; `setRegionEnabled`; `toggleSource` | country metadata + feeds | `Sources/**` (**T7**) | `SourceManagementStoreTests.testOpeningANodeShowsItsLevelBreadcrumbAndSources` + `testNodeSectionsAndSubNodeStateComeFromTheLevel`; V2 merges V1's country and region detail into `Sources/FeedMineUI/Sources/NodeSourcesView.swift`; no executed uitest opens the detail level; no screenshot diff | em transferência |
| Region detail | `Views/RegionDetailScreen.swift` (98) | `RegionDetailScreen` | `loader.regionFeeds`, `requestRegionEnabled`, `regionToggleState`, `toggleSource` | region metadata | `Sources/**` (**T7**) | `NodeSourcesView.swift` is V1's country and region detail merged (V1's own comment: "the same screen twice"); `SourceManagementStoreTests.testNodeSectionsAndSubNodeStateComeFromTheLevel`; no executed uitest opens a region level; no screenshot diff | em transferência |
| Source feed view | `Views/CollectionManagementView.swift` (SourceFeedView/SourceCollectionFeedView) | `ImageLoader.resolveImage` **network** inside the view | open source feed; list items with resolved images | source items | `Sources/**` (**T7**) — **must not** keep image downloads in the View (T7/T4 rule) | the executed T12 audit proves `Sources/FeedMineUI` performs no I/O (no `URLSession` in the package), so the network-in-view rule is met; `SourceCatalogBackendTests`; no executed test opens a source's own feed (see §1.5); no screenshot diff | em transferência |
| Taxonomy store | `Services/TaxonomyStore.swift` (811) | `TaxonomyStore.shared` | children/search/ancestors queries | taxonomy sqlite | `SourceManagementCoordinator` + persistence (**T7**) | `LegacyCatalogMetadataTests` + `SourceManagementCoordinatorTests` + `SourceManagementStoreTests` cover the node queries; V2 keeps no V1-style `TaxonomyStore` singleton (the coordinator plus persistence own it); no screenshot diff | em transferência |

Section totals: **8 rows** — after T12: **2 `validado`**, **5 `em transferência`**, **1 `inventariado`** (the
DEBUG-only catalogue browser). Open V2 questions for T7: V1's "zero sources
selected" state must be preserved (T7 explicitly overrides V2's "at least one source"
rule if it blocks parity), and V1's `sourceID` is a truncated 32-bit hash
(`CatalogIdentity.swift:55`) — V2 IDs stay UUIDs with a recorded mapping (PD-2).

---

## 5. Collections and bookmarks

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Collection management | `Views/CollectionManagementView.swift` (720) | `CollectionManagementView`, `SourceCollectionDetailView`, `AddSourceToCollectionSheet` | CRUD + reorder `SourceCollection`; add sources; open collection feed | `SourceCollection` model + `loader` | `Sources/FeedMineUI/Collections/**` + `ReaderLibraryCoordinator` (**T8**) | uitest `testCollectionsManageAndReachThePresetPicker` (empty state, create, detail, `collection.openFeed`) + `ReaderLibraryStoreTests.testCollectionsGroupSourcesAndDeletingOneKeepsThem`, `testCollectionOrderingAndNamingBehaveLikeBoxes`; `AddSourceToCollectionSheet` is not drawn (see §1.5); no screenshot diff | validado |
| Bookmark boxes | `Views/BookmarkBoxesView.swift` (183) | `BookmarkBoxesView` | `loadBookmarkLists`; create/rename/delete/reorder; refresh; select active list; set default | `BookmarkList`, `BookmarkStore` | `Sources/FeedMineUI/Bookmarks/**` (**T8**) | uitest `testBookmarkBoxesManageAndOpenTheirOwnList` (create, open, reopen) + `BookmarkBoxesBackendTests` (6) + `ReaderLibraryStoreTests.testTheDefaultBoxExistsAndIsTheOnlyUndeletableOne`; a box as a *reading surface* waits for a presentation source (T8 accepted difference); no screenshot diff | validado |
| Bookmark box picker | `Views/BookmarkBoxPickerView.swift` (67) | `BookmarkBoxContextMenu`, `BookmarkBoxPickerView` | `loader.toggleBookmark(itemID, listID:)` | bookmark lists | `Bookmarks/**` (**T8**) | `BookmarkBoxesBackendTests.testIntentsReachTheBackendAndARefusalIsVisible` proves the toggle/box write; the picker and its context menu are not tapped by an executed uitest (T9's card test copies a link); no screenshot diff | em transferência |
| Bookmark model | `Models/BookmarkList.swift` (16) | `BookmarkList` | pure value (id/name/isDefault/itemCount/search*) | — | `FeedMineDomain.ReaderBookmarkList` (**T8**) | `ReaderLibraryStoreTests` (9) (`testSeveralBoxesHoldTheSameCardAndAnEmptyBoxIsAState`, `testNamingAndOrderingRules`, `testTheLegacyBookmarkSetBecomesTheDefaultBox`) + `LegacyUserStateImportTests` (3); no screenshot diff | validado |
| Presets / smart feeds | `Models/FeedPreset.swift` (521) | `FeedPreset`, `PresetSelector` (incl. `.curatedFeed`), `SmartFeedDefinition`, `SmartFeed`, refresh policies | activate/delete preset; smart-feed creation from search | preset store | `FeedMineDomain.ReaderPreset` + `ReaderFilterStore` identity (**T6/T8**) | `ReaderLibraryStoreTests.testPresetsRoundTripTheirIdentityAndAreKindOrdered` + app `testT8ASavedPresetIsOfferedAndActivatesItsOwnContext` (V1's two plain entries first; a saved preset activates its stored key); the refresh policies have no executed proof; no screenshot diff | em transferência |

Section totals: **5 rows** — after T12: **3 `validado`**, **2 `em transferência`** (the box picker and the preset
refresh policies have no proof of their own).

---

## 6. Reader, media, sharing

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Article reader | `Views/ArticleReaderView.swift` (113) | `ArticleReaderView`, `ArticleWebView` (WKWebView) | open article; open in Safari; close | frozen target URL | V2 `InAppBrowser` exists (`FeedMineApp/InAppBrowser.swift`); port V1 reader chrome + mini player host (**T9**) | `InAppBrowser` (SFSafariViewController, U2 decision) covers V1's close/reader/share; no executed uitest opens an article (T9's evidence names the card-copy and mini-player tests); `shot article-reader-inapp.png` is the V1 reference, no V2 diff; recorded difference: V1's loading bar and explicit Safari link have no counterpart | em transferência |
| Mini player / full player | `Views/MiniPlayerBar.swift` (282) | `MiniPlayerBar`, `FullPlayerView` over `AudioPlayerManager` (AVFoundation) | play/pause, close/stop, scrubber commit, seek ±15, `Done`, context menu (BookmarkBox, View Source, Add Source to Collection, Copy Link, ShareLink); `CachedAsyncImage` artwork (**network in view**) | playback state, item audio URL | `FeedMineUI` views + `ReaderMediaCoordinator` (**T9**) | uitest `testMiniPlayerStatesPlaybackWithoutMovingTheFeed` (constant 56 pt playing and paused, `mini-player-toggle`, the full player's two ±15 skips and its close) + `ReaderMediaCoordinatorTests` (4); no screenshot diff | validado |
| Share as image | `Views/ShareCardImageView.swift` (106) | `ShareCardImageView`, `renderCardAsImage` (`ImageRenderer` + `UIActivityViewController`) | render card image; share | card + `CachedAsyncImage` (**network in view**) | `FeedMineUI` view + platform adapter in Composition (**T9**) | not ported (T9 accepted difference: V2 cards draw decoded locals, so there is no rendered-card artifact to share); the link share is delivered and proven by uitest `testCardCopiesItsOwnLinkAndStatesIt` | inventariado |
| Stats share card | `Views/StatsShareCard.swift` (125) | `StatsShareCard` (`ImageRenderer`) | share stats | `FeedMetrics` | `FeedMineUI` view (**T9**), data from Runtime | not ported (T10 state: V1's "Share" section is not drawn and V2 keeps no rendered stats card); no executed proof | inventariado |
| Audio player service | `Services/AudioPlayerManager.swift` (497) | `AudioPlayerManager.shared` | play/pause/seek/save position | AVFoundation | `ReaderMediaCoordinator` + platform adapter (**T9**) | `ReaderMediaCoordinatorTests` (4) (`testTappingTheSameCardTogglesAndAnotherStarts`, `testSurfaceIntentsReachThePlayerAndProgressIsAValue`) + uitest `testMiniPlayerStatesPlaybackWithoutMovingTheFeed` (the real AVFoundation adapter, `FeedMineApp/MediaPlaybackAdapter.swift`); saving the playback position has no executed proof; no screenshot diff | em transferência |

Section totals: **5 rows** — after T12: **1 `validado`**, **2 `em transferência`**, **2 `inventariado`** (image
share and the stats card, both accepted differences). Rule for T9: `UIActivityViewController`,
`UIPasteboard` and AVFoundation stay in platform adapters outside the renderers.

---

## 7. Settings, feedback, import/export

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Settings sheet | `Views/SettingsSheetView.swift` (436) | `SettingsSheetView` | font size; language; circadian palette + typography on/off; palette family; font style; performance/prefetch; night mode; filter auto-expire; navigate to content filters; data (export/reset); share stats; about; feedback | `@AppStorage` keys in `Services/AppSettings.swift`; `LocaleManager`; `CircadianEngine` | `Sources/FeedMineUI/Settings/ReaderSettingsView.swift` + `ReaderSettings` (**T10**) | uitest `testSettingsReachTheirControlsAndSurviveReopening` (`settings-circadian-palette`, `settings-prefetch`, `settings-night-mode`, `settings-done`; values re-read after reopening) + `ReaderSettingsCoordinatorTests` (5); recorded differences: no Language, Reading Data or Share sections; no screenshot diff | validado |
| Toast | `Views/ToastView.swift` (21) | `ToastView` | none (caller-driven; auto-dismiss 2 s, black 0.8 capsule, bottom 100, spring 0.35/0.8 — FeedScreen 1097–1119) | message + symbol | `Sources/FeedMineUI/Feedback/ToastView.swift` (**T5**) | test `ReaderShellTests.testToastIsHostOwned` + uitest `testCardCopiesItsOwnLinkAndStatesIt` asserts the "Link copiado" toast on screen; no screenshot diff | validado |
| Clipboard banner | `Views/ClipboardBanner.swift` (119) | `ClipboardBanner` | `checkClipboard`; `autoCheck()`; Add / Dismiss | pasteboard + `InputParser` | `Feedback/ClipboardBanner.swift` (**T5**, import action T10) | `Feedback/ClipboardBanner.swift` exists, but no executed test covers `checkClipboard`/Add/Dismiss; no screenshot diff | em transferência |
| Add feed | `Views/AddFeedView.swift` (455) | `AddFeedView` | input parse (`InputParser`/`URLResolver`); preview; confirm; `loader.importFeeds`/`importOPML`/`addSourceURLs`; collection target; clipboard; posts `feedImportCompleted` | parse + import pipeline | `Sources/FeedMineUI/ImportExport/AddFeedView.swift` + `ReaderImportExportCoordinator` (**T10**) | the import surface is proven on screen by uitest `testImportPreviewCommitsAndExportPreviews` (`import-summary`, `import-confirm`, the "Importadas 1" toast) + `ReaderImportExportCoordinatorTests` (6); the address-paste Add Feed sheet is not drawn (T8/T10 state); no screenshot diff | em transferência |
| Export | `Views/ExportView.swift` (406) | `ExportView` with `ExportScope`/`ExportFormat` | preview (sample) → `generateExportData`; share/save/copy (activity controller / pasteboard) | export engine | `ImportExport/ExportView.swift` (**T10**) | uitest `testImportPreviewCommitsAndExportPreviews` (`export-scope-selection`, `export-share`, `export-preview`) + `ReaderImportExportCoordinatorTests.testEveryFormatWritesItsOwnDocumentAndACollectionExportsItsMembers`; no screenshot diff | validado |
| OPML parser | `Services/OPMLParser.swift` (867) | `parseImportedFile`, `parseAll`, `deduplicate`, `mediaKind`, `normalizeURL`/`requestURL` | pure parsing | XML | `FeedMineDomain`/Persistence (**T10**) — copy only if its semantics pass V2 identity vectors | `OPMLDocumentTests` (5) + `FeedAddressTests` (8) + `ReaderImportExportCoordinatorTests.testExportingOPMLRoundTripsThroughTheImporter`, `testRepeatsInTheFileAreCountedNotImported`; no screenshot diff | validado |
| Settings keys/services | `Services/AppSettings.swift`, `Services/LocaleManager.swift` | `Keys`/`Settings` registry; `LocaleManager.shared` + 39 languages | typed get/set; language resolution | UserDefaults | `ReaderSettings` + stores (**T10**) | `ReaderSettingsTests` (6) (`testDefaultsAreV1sOwn`, `testLegacyPreferencesAreCarriedByKey`) + `ReaderSettingsCoordinatorTests` (5); V1's `LocaleManager` and its 39 languages are not ported (T10 difference: no catalog); no screenshot diff | validado |
| Settings actions in FeedScreen | `Views/FeedScreen.swift` | `handleScenePhase` 1467–1482, `updateBadge` 1455–1458, `handleWillEnterForeground` 1486–1491 | badge count (`UNUserNotificationCenter.setBadgeCount`); persist `lastScrollItemID`; background scheduler; audio position save | notifications + scene phase | `ReaderSettings`/app host (**T10**) | `FeedMineRuntime/BackgroundFeedRefresh.swift` and `AppComposition` own cold-start/foreground recovery, but no executed test covers the badge/scene-phase/notification actions (the evidence doc records `CompositionTests` as 6-of-20 failing at their first supply assertion and claims none of them); no screenshot diff | em transferência |

Section totals: **8 rows** — after T12: **5 `validado`**, **3 `em transferência`** (the clipboard banner, the
address-paste Add Feed sheet, and the badge/scene-phase actions).

---

## 8. Onboarding and curation

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Onboarding gate | `Views/OnboardingTipsView.swift` (38) | `OnboardingTipsView` (`@AppStorage hasSeenOnboarding`) | presents `CuratedOnboardingView(isFirstRun:true)`; on save posts `onboardingDidSaveCuratedFeed` | flag + notification | `Sources/FeedMineUI/Onboarding/**` (**T11**) | uitest `testOnboardingWelcomeComposerAndSave` proves the gate (Welcome is presented; after the save `welcome-headline` is gone) + `AppComposition.needsOnboarding`; no screenshot diff | validado |
| Curated onboarding | `Views/CuratedOnboardingView.swift` (527) | `CuratedOnboardingView` (welcome/composer stages), `CuratedProfileControls`, `CuratedBackdrop` (`ImageCache.diskImage`, no network) | resolve recipe via `FeedRecipeResolver.effectiveProfile`; persist `loader.createCuratedFeed`/`setActivePreset`; reset; start broad; open my feed | recipe + choices | `Onboarding/**` + `CuratedFeedCoordinator` (**T11**) | uitest `testOnboardingWelcomeComposerAndSave` (welcome → composer → `composer-open-feed`) + `CuratedFeedCoordinatorTests` (6) + app `testT11ACuratedFeedRanksByItsRecipeAndEditingChangesTheBehaviorVersion`; no screenshot diff | validado |
| Welcome scene | `Views/Onboarding/WelcomeScene.swift` (196) | `WelcomeScene` | renders real cards (`loader.items.prefix(6)`) as a cascade; CTAs "Shape my feed" / "Start broad" | real items | `Onboarding/WelcomeScene.swift` (**T11**) | uitest `testOnboardingWelcomeComposerAndSave` (`welcome-headline`, `welcome-body`, `welcome-trust`, `welcome-shape`); recorded difference: the cascade shows the reader's own published cards (T11); no screenshot diff | validado |
| Composer scene | `Views/Onboarding/FeedComposerScene.swift` (352) | `FeedComposerScene` | live preview cards via `loader.previewCuratedCards` (coalesced 100 ms) + controls; footer Reset / Start broad / Open my feed | preview items | `Onboarding/FeedComposerScene.swift` (**T11**) | uitest `testOnboardingWelcomeComposerAndSave` (`composer-subtitle`, `composer-discovery`, `composer-open-feed`); recorded difference: the preview shows the reader's published cards in published order (T11); no screenshot diff | validado |
| Composer controls | `Views/Onboarding/{DiscoverySlider,EditorialBalanceControl,LanguageSelectionControl,MediaTypeToggles,TopicPreferenceRow,FlowLayout}.swift` | see file names | discovery slider 0…1; editorial balance (less/balanced/more per style); language chips + searchable grid (min 1); media-type toggles (article/podcast/video); topic cycle Normal→More→Less; wrap layout | choice values | `Onboarding/**` (**T11**) | uitest `testOnboardingWelcomeComposerAndSave` (discovery slider, a `composer-topic-*` cycles and its label follows, `composer-media-podcast`, `composer-language-*`); no screenshot diff | validado |
| Curated inspector | `Views/CuratedFeedInspectorView.swift` (413) | `CuratedFeedInspectorView` ("open hood") | edit name/languages/weights/learning; `loader.loadCuratedFeeds`/`updateCuratedFeed`/`setActivePreset` | curated feed definition | `Onboarding/**` (**T11**) | uitest `testOnboardingWelcomeComposerAndSave` opens the hood (`hood-badge`, `hood-privacy`, `hood-close`) + `CuratedFeedCoordinatorTests.testInspectingStatesTheReadersOwnAnswers`, `testEditingRewritesBothTheRecipeAndTheIdentity` + app `testT11A…` (the recipe revision is a counter, bumped on every edit); no screenshot diff | validado |
| Recipe model/resolver | `Models/FeedRecipeDefinition.swift` (122), `Services/FeedRecipeResolver.swift` (69), `Services/CuratedPreferenceEngine.swift` (1103) | `PreferenceLevel`, `MediaType`, `FeedRecipeDefinition`, `neutral(languages:)`, `effectiveProfile` | pure resolution of a recipe into a profile | catalog facets | `FeedMineDomain`/`FeedMineEditorial` (**T11**) | `FeedRecipeDefinitionTests` (8) + `FeedRecipeResolutionTests` (7) + `WeightedScoringTests` (3); no screenshot diff | validado |
| Curated models | `Models/CuratedFeed.swift` (366), `Models/OnboardingSeed.swift` (81) | `CuratedFeed`, `CuratedProfileDefinition`, `CuratedChoiceOutcome`, `CuratedEvidence`, `CuratedTopic`, `CuratedEditorialStyle`, `curatedFeatureDisplayName`, `OnboardingIntent`, `OnboardingSeed` | values | — | Domain/Editorial/Persistence (**T8/T11**) | `FeedRecipeDefinitionTests` (8) (`testNeutralRecipeIsV1sOwn`, `testTheSummaryStatesTheReadersOwnAnswersStrongestFirst`) + `CuratedFeedCoordinatorTests` (6) + app `testT11ACuratedFeedRanksByItsRecipeAndEditingChangesTheBehaviorVersion` (the persisted revision is a counter, `reader_presets.recipe_revision`); no screenshot diff | validado |

### 8.1 Orphans — present in V1, unreachable (recorded, **not** transferred)

| file | evidence |
| --- | --- |
| `Views/Onboarding/StoryDuelScene.swift` (110), `StoryDuelCard.swift` (92, `CachedAsyncImage`) | no references in the repo; the composer no longer routes to a duel |
| `Views/Onboarding/ChoiceFeedbackOverlay.swift` (79), `ConfidenceProgressView.swift` (52) | no references outside their own files |
| `FeedScreen.SourceSearchDetailView` (1966–2044) | defines `toggleSource`/`ShareLink` but is never instantiated |

These rows exist so nobody "restores" a surface the product dropped, and so a parity
auditor does not count them as missing. V2 does not implement them.

Section totals: **8 rows** — after T12: **8 `validado`**. The orphan table above is recorded, not transferred.

---

## 9. Appearance system

| surface | v1Path | v1Symbol | content | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- |
| Design tokens | `Services/DesignTokens.swift` (187) | `PrimitiveColor`, `SemanticColor`, `ComponentToken`, `Color(oklchL:)`, `Color(hex:)` — pure/static | palettes, semantic colors, component values | `Sources/FeedMineUI/Appearance/ReaderAppearance.swift` (**T4**) replacing `FeedDesignTokens.swift` | test `FeedCardTransferTests.testAppearanceCopiesV1PaletteMetricsAndTypography` (V1's exact hex values, padding/gap/radius per period, tracking) + `testAppearancePeriodDrivesWeightAndSpacing`; no screenshot diff | validado |
| Circadian palette/typography | `Services/CircadianEngine.swift` (362) | `CircadianPeriod`, `PaletteFamily`, `FontStyle`, `FontRole`, `CircadianEngine.shared` (hourly timer + UserDefaults) | period → palette family + fonts; `pageBackground`, `accent`, `cardGap`, `cardPadding`, `cardRadius`, `font(for:size:)`, `activeFontWeight`, `refresh()` | `Appearance/**` pure values (**T4**); the timer/singleton is **not** copied; "presentation is not rebuilt by an appearance timer" (plan constraint) | test `FeedCardTransferTests.testAppearancePeriodDrivesWeightAndSpacing` (the period supplies the title weight and the letter spacing) + `testAppearanceCopiesV1PaletteMetricsAndTypography`; no screenshot diff | validado |
| Assets / fonts / localization | V1 app bundle (`feedmine_brand_assets/`, `Resources/`) | assets, font files, localized strings | — | V2 app resources (**T4/T10**); check names and platform availability | no executed proof: asset/font/locale names and platform availability were not verified (T4 remainder); the T12 audit only proves the UI package owns no platform I/O; no screenshot diff | em transferência |
| Night mode | `Services/AppSettings.swift` `Keys.nightMode`; `FeedScreen` overlay 1121–1123 | black 0.35 overlay, ignores safe area, no hit testing | — | `Appearance/**` (**T10**) | uitest `testSettingsReachTheirControlsAndSurviveReopening` toggles `settings-night-mode` and re-reads it after reopening + `ReaderSettingsCoordinatorTests.testTurningTheClockOffAndNightModeOverride`; the black-0.35 overlay itself has no visual proof (`shot night-portrait.png` is the V1 reference, no V2 diff) | em transferência |

Section totals: **4 rows** — after T12: **2 `validado`**, **2 `em transferência`** (T4 ported the tokens, the palette/typography values and the
metrics into `Sources/FeedMineUI/Appearance/ReaderAppearance.swift`; the singleton and its hourly timer are not
copied). The asset/font/locale copy and the night-mode behaviour remain for T10.

---

## 10. Actions with no destination yet (the list that blocks parity)

The plan requires that no control disappear silently. Every V1 action currently has a
destination **except** the following, which are explicitly *not* transferred and are
listed so the omission is a decision, not a loss:

| V1 action | Why it is not transferred | Decision owner |
| --- | --- | --- |
| `Explorar Catálogo` header button and `CompactDebugInfo` | DEBUG-only UI | Watermark: keep V2's DEBUG overlay (T5 documents it) |
| `SourceSearchDetailView` (orphan) | unreachable in V1 | none — dead code |
| `StoryDuelScene`/`StoryDuelCard`/`ChoiceFeedbackOverlay`/`ConfidenceProgressView` | unreachable in V1 | T11 records them as orphans |
| V1 `legacyFeedContent` branch (FeedLoader-driven display phases) | V2 has one runtime; the branch is the engine being replaced | T5 |
| `ShakeDetector` refresh | not yet decided for V2 | T5 (keep or drop with a written reason) |

Everything else in sections 1–9 is assigned to a delivery.

## 11. Verification of this matrix

- Symbols and line numbers were read from the V1 checkout with `read` over the whole
  file (`FeedScreen.swift` in ranges 1–2444) and per-file reads for the delegate
  components; the per-file inventories behind this matrix were produced by three
  read-only scouts and are consistent with the source citations above.
- Screenshots: `docs/evidence/v1-ui/` under the conditions in
  `docs/reviews/V1_UI_REFERENCE.md` (V1 build succeeded; iPhone 17 Pro Max, iOS 26.5).
- **This matrix is a location/provenance artifact, not a visual approval.** No row
  becomes `validado` without a V2 test (`test`/`uitest`) proving the flow plus, for
  visual surfaces, a V2 screenshot compared against the V1 reference.
- **Flipped by T12 (2026-10-10).** The visually-conditional half of that rule never
  happened: the evidence doc records the screenshot comparison as **"Not executed as a
  screenshot diff"**. No row therefore claims visual parity; a row is `validado` on the
  executed, named tests the evidence doc records for it (`test`/`uitest`/command), and
  every `proof` that touches a visual surface says the comparison is missing. Counts:
  **47 `validado`**, **45 `em transferência`**, **8 `inventariado`**.

**T8 state (2026-10-09).** The library rows are delivered as surfaces over the reader's own storage; the
executed evidence is in `PORT_LOG.md` under T8.

- **Bookmark boxes** (line 66): `ReaderHeader` draws the box control with V1's `bookmark`/`bookmark.fill` and
  opens `BookmarkBoxesView` — the all-saved row, one row per box with its count, the preferred box bold and
  checked, swipe actions (Padrão / Renomear / Apagar), drag reorder, the New Box alert and the Reorder mode.
  The box's own contents open as a saved list. **Deliberate difference:** V1's row tap made the feed show that
  box (its `lastClicked` preset over `selectedBookmarkListID`); a box *as a reading surface* waits for T9's
  presentation source over the publication store.
- **Save as Smart Bookmark** (line 85): the entry exists, is offered only inside a committed search (V1's own
  condition), asks for a name, stores the current `ContextKey` under it with the key naming its own preset, and
  **switches to it** — V1's `setActivePreset(.smartFeed)` + `closeSearch()`.
- **Collect these sources** (line 86): the entry exists, is offered inside a search or with ≥2 applied criteria,
  and creates a collection holding the sources the reader's context is over, in one transaction.
- **Delete Smart Bookmark** (line 90): the entry exists and is offered only when the reader is on one of their
  own presets; deleting returns the surface to the plain one.
- **Source Collections** (line 93): `CollectionsView` + its detail port V1's list and `SourceCollectionDetailView`
  — V1's empty state, create/rename/delete/reorder, the footer stating that deleting removes only the playlist,
  member removal, and "Abrir o feed da coleção", which runs a session over exactly those sources without
  touching the reader's selection.
- **Saved presets in the filter sheet** (line 67's `FilterSheetView`): the preset picker receives V1's two plain
  entries plus the reader's curated presets, collections and smart bookmarks, in V1's picker order; choosing a
  saved one activates its stored key.
- **Still T10's:** export/import a collection (lines 88, 89, 91) and "Add Feed" (line 92) — the entries exist in
  `ReaderMenuEntry.standard` and are not offered until those deliveries land, so no dead control is drawn.

**T9 state (2026-10-09).** The reader, the media and the share flows are ported; the executed evidence is in
`PORT_LOG.md` under T9.

- **Article reading**: V2 opens the card's own frozen target in `SFSafariViewController` (U2's decision, no web
  engine of our own), which covers V1's close control, reader mode and share. **Recorded difference:** V1's
  `ArticleReaderView` also drew a loading bar and an explicit `safari` link; those have no counterpart in that
  controller. V1's own detail — the reader keeps the playback bar visible — is ported.
- **Card actions**: `ReaderActionCoordinator` resolves open / view source / copy link / share / media **from the
  occurrence's own frozen fields**, proven against an article re-published under a new revision (the earlier
  card keeps its own target), and an action a card does not carry is reported rather than replaced. "View
  source" opens the card's *source* — resolved through the catalog — not the article's URL.
- **Share**: V1 shared the link itself (`ShareLink(item: URL)`), and so does V2; the image-specific share
  (`renderCardAsImage` + `UIActivityViewController`, "share as image") is **not** ported: V2's cards draw decoded
  locals and have no rendered-card artifact to share, so no control is offered for it.
- **Playback**: a feed's audio/video enclosure is carried as the occurrence's own payload, the card states
  `mediaPlayback`, and tapping it plays through V1's own card behaviour (same card toggles, another starts). The
  mini player reserves a **constant** 56 pt and draws position/length/errors; the full player carries V1's two
  15-second skips, a scrub and its `m:ss` clock.
- **Image versus article gesture**: the media area of a playable card emits `openMedia` and the rest of the card
  opens the article — V1's `onImageTap` rule, with the same condition (`primaryActionKind == .mediaPlayback`).

**T10 state (2026-10-10).** Settings, import and export are delivered as surfaces over the values and
coordinators recorded in `PORT_LOG.md` under T10.

- **Settings** (the reader menu's *Ajustes*): V1's sections — appearance with the text size, "Design circadiano"
  with the two clock rules plus the palette family and font style, performance with image preloading, reading
  with night mode, the four-hour rule and the content filters, the library size, and about. **Recorded
  differences:** no "Language" section (V2 has no catalog of its own yet, and a picker that changes nothing
  would be a dead control), no "Reading Data"/"Share" sections (V1 stated counts from its own registry and shared
  a rendered stats card; V2 keeps neither).
- **Export** (line 91's entry, and "Export collection" from T8): scope × format over the lists V2 has, a preview
  of the document, and a share/save of the file itself.
- **Import**: the sources screen's "Importar OPML" (line 200's own row in V1) and the collection importer's
  entry open a file picker over `.xml`/`opml`; a preview states what the file offers, what it repeats and what it
  cannot use, and only the confirmation writes — atomically and idempotently.
- **Still T8/T10's own open item:** "Add Feed to Collection" (V1's `AddFeedToCollectionSheet`, the menu's
  `addFeed` entry) is not drawn: membership is set from a card's own action, the collection detail's removal,
  and an import.