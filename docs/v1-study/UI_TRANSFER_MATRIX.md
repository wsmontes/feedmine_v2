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

Status vocabulary is the plan's. Every row in this document starts as
`inventariado`; the counters at the end of each section are the ones a later
delivery flips to `em transferência` / `validado`.

### Evidence classes used in `proof`

- `src` — a citation into the V1 checkout (`path:symbol:line`), verified by reading the file.
- `shot` — `docs/evidence/v1-ui/<file>.png`, captured under the conditions in `V1_UI_REFERENCE.md`.
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

### 1.1 Header (floating overlay)

| surface | v1Path | v1Symbol | actions | dataDependencies | v2Path (delivery) | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Compact header (chip + 4 buttons) | `Views/FeedScreen.swift` | `compactHeader` 502–653; background `.ultraThinMaterial` + `Divider` 0.3 at 638–644; `readHeaderHeight` via `HeaderHeightKey` 1595/1618 | see rows below | `runtime.sessionChipStatement`, `runtime.sessionLoadingStatement`, `loader.activeFilterCount`, `loader.selectedBookmarkListID` | `Sources/FeedMineUI/Reader/ReaderHeader.swift` (**T5**) | shot `feed-portrait-light.png`; src | inventariado |
| Search toggle | idem | 518–531 | `magnifyingglass` → `applySearchScopeToLoader()`, `isSearching=true`, `searchFocused=true`; when searching `magnifyingglass.circle.fill` → `closeSearch()` | `loader.searchQuery` | `ReaderHeader` + `ReaderNavigation` (**T5**) | src; shot (search open **missing**, see limitations) | inventariado |
| Bookmark boxes | idem | 532–544 | `bookmark`/`bookmark.fill` + 6 pt dot when `selectedBookmarkListID != nil` → `showBookmarks=true`, haptic `.light` | `loader.selectedBookmarkListID` | `BookmarkBoxesView` (**T8**) + `ReaderHeader` (**T5**) | src | inventariado |
| Filters | idem | `filterButton` 911–933 | `line.3.horizontal.decrease` + badge when `activeFilterCount > 0` → `showFilters=true`, haptic | `loader.activeFilterCount` | `FilterSheetView` (**T6**) + `ReaderHeader` (**T5**) | src | inventariado |
| Catalog explore (**DEBUG only**) | idem | 547–555 | `books.vertical` → `showCatalogExplore=true` | `CatalogBrowserViewModel` | `Sources/FeedMineUI/Sources/CatalogExploreView.swift` (**T7**) | src | inventariado |
| Ellipsis menu | idem | `Menu` 556–635 | see 1.2 | `loader.activePreset` family, `loader.presentationContext` | `ReaderMenu` (**T5**) | src | inventariado |
| Debug info (DEBUG) | idem | `CompactDebugInfo` 508; triple-tap toggle 1851–1861 (`showDebugBar` `@AppStorage`, gate 62–68) | replaces the chip with counters | debug counters | **not transferred** (debug-only; keep V2's DEBUG overlay) — recorded, not a parity gap | src | inventariado |

### 1.2 Ellipsis menu items (conditional paths included)

**T5:** all 14 items exist as `ReaderMenuEntry` values with V1's labels, symbols, roles and grouping
(`Sources/FeedMineUI/Reader/ReaderNavigation.swift`). `FeedScreenStore.menuEntries` renders
`availableDestinations ∩ standard`, and `AppComposition.readerDestinations = [.sources, .bookmarkBoxes]`
today, so only those two are reachable; each remaining item joins when its delivery lands (T7 sources/catalog,
T8 collections/bookmarks/presets, T10 add-feed/export/import, T11 curation).

| action | trigger condition | symbol/icon | executes | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- |
| Create Curated Feed | always | `wand.and.stars` | `showCuratedOnboarding=true` | T11 | src 556–561 | inventariado |
| Open Curated Feed hood | `activePreset.isCuratedFeed` | `slider.horizontal.3` | `showCuratedInspector=true` | T11 | src 562–567 | inventariado |
| Delete Curated Feed | `activePreset.isCuratedFeed` | `trash` (destructive) | `showDeleteCuratedFeedConfirmation=true` | T11 | src 568–573 | inventariado |
| Save as Smart Bookmark | `isSearching && hasCommittedSearch && scope allows` | `sparkles.rectangle.stack` | `prepareSmartFeedFromSearch()` 1206–1213 → `createSmartFeedFromSearch` 1215–1234 → `loader.createSmartFeed` + `setActivePreset(.smartFeed)` + `closeSearch()` | T6/T8 (preset identity) | src 576–581 | inventariado |
| Collect these sources | `hasCommittedSearch \|\| activeFilterCount >= 2` | `folder.badge.plus` | `prepareCollectionFromContext()` 1174–1186 → alert → `createCollectionFromContext` 1188–1204 → `loader.createSourceCollection` + `addSource` | T8 | src 584–586 | inventariado |
| Export collection | `collectionID != nil` | `square.and.arrow.up` | `showCollectionExport=true` → `CollectionOPMLExportView` 1516–1577 (ShareLink) | T10 | src 588–591 | inventariado |
| Import to collection | `collectionID != nil` | `square.and.arrow.down` | `showCollectionImporter=true` (`.fileImporter` xml/opml 421–426) → `handleCollectionImport` 1260–1304 | T10 | src 592–594 | inventariado |
| Add feed to collection | `collectionID != nil` | `link.badge.plus` | `showAddFeed=true` with target collection | T10 | src 595–604 | inventariado |
| Delete Smart Bookmark | `activePreset.isSmartFeed` | `trash` | `showDeleteSmartFeedConfirmation=true` → `deleteActiveSmartFeed` 1236–1246 | T8 | src 607–613 | inventariado |
| Add Feed | always | `plus.circle` | `showAddFeed=true` | T10 | src 615–618 | inventariado |
| Export | always | `square.and.arrow.up` | `showExport=true` | T10 | src 619–621 | inventariado |
| Source Collections | always | `rectangle.stack.fill` | `showCollections=true` | T8 | src 622–624 | inventariado |
| Sources | always | `antenna.radiowaves.left.and.right` | `showSources=true` | T7 | src 625–627 | inventariado |
| Settings | always | `gearshape` | `showSettings=true` | T10 | src 628–630 | inventariado |

### 1.3 Search bar and unified search panel

**T5:** the search *surface* (field, submit, explicit cancel) is transferred and a submission still becomes the
same search context the toolbar field used to submit; the results panel stays `inventariado` (T6 owns search as
a context with results).

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Search bar | `Views/FeedScreen.swift` | `searchBar` 655–716; `TextField` id `unified-search-field`; chips id `search-term-tags` | Return → `commitSearchDraft()` 1318–1334 → `loader.submitSearchTerms`; `+` `plus.circle.fill` → same; `Cancel` → `closeSearch()` 1306–1312; chip `xmark` → `removeSearchTerm(term)` 722–732; toggles Sources/Contents (`checkmark.square.fill`/`square`) 776–791 bind `searchIncludesSources`/`searchIncludesContents` (277/283) → resubmit; `searchActivityLine` 735–766 is status-only | `loader.searchQuery`, `submittedSearchTerms`, `searchIncludesSources/Contents`, `isSearchLoading/Scanning`, `searchScannedSourceCount` | `ReaderSearchBar` (**T5**), search context (**T6**) | src | inventariado |
| Unified results panel | idem | `unifiedSearchPanel` 793–864; id `unified-search-results`; top padding = `headerHeight + searchControlsHeight` 862 | row tap → `searchFocused=false` + `selectedSource = source.sourceReference` (812–816); context menu `View Source` (819–823) → same; `Add Source to Collection` (824–826) → `sourceToCollect`; saved/local row tap → `loader.markAsClicked(id)` + `articleItem = item` (884–889) | `loader.unifiedSearchResults` (sources/savedItems/localItems) | `ReaderSearchResults` (**T5**), search semantics (**T6**) | src | inventariado |

### 1.4 Feed content, sections and scroll

**T5:** the chrome no longer changes the feed's geometry — the header is measured by the shell itself
(`ReaderHeaderHeightKey`) and the work feedback is a constant-height non-interactive overlay (T3). The
scroll-driven lens state and the lens bar remain `inventariado` for T6.

| surface | v1Path | v1Symbol | actions / behaviour | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Content branch selection | `Views/FeedScreen.swift` | `screenContent` 129–188; branches 139–155 | `persistenceUnavailable` → `ContentUnavailableView` id `persistent-store-unavailable`; searching → `unifiedSearchPanel`; runtime session → `sessionFeedContent` 197–228; else `legacyFeedContent` 229–251 | `loader.persistenceUnavailable`, `runtime.sessionSurface`, `loader.feedDisplayPhase` | `ReaderShell` + V2 `FeedScreen` (**T5**); V2 has no legacy branch | shot `feed-portrait-light.png` | inventariado |
| Feed scroll view | idem | `feedScrollView` 946–1078 | `LazyVStack(spacing: engine.cardGap)`; ForEach sections → `FeedItemView` 975–1012; section header when `showsHeader` 1018; `EmptyFilterView` 1026; `EndOfFeedFooterView` 1033 (`checkmark.circle`, inert); `.refreshable` 1049 → `runtime.refresh()`; `.padding(.top, feedTopPadding)` 1047 | `runtime.presentation.sections/rows` | `Reader/FeedScrollView` sequence (**T3/T5**) | shot `feed-portrait-light.png`, `feed-landscape.png` | inventariado |
| Header geometry coupling | idem | `feedTopPadding` 478–481 = `max(48, headerHeight) + (isSearching ? searchControlsHeight : (isFilterLensVisible ? 20 : 0))` | content padding tracks measured header height (`HeaderHeightKey`/`SearchControlsHeightKey` 1595–1633) | measured heights | `ReaderShell` (**T5**); V2 must not use variable `safeAreaInset` (analysis §4, T3) | src | inventariado |
| Scroll-driven header/lens state | idem | `handleScrollOffset` 1373–1388; `revealFilterLens`/`collapseFilterLens`/`scheduleFilterLensCollapse` (4 s auto-collapse)/`dismissFilterLensForCurrentSelection`/`handleFilterLensContentChange` 1390–1452 | scroll offset > 40 sets `userHasScrolled`; delta > 8 → collapse; delta < −8 → reveal; only when `hasFilterLensContent && !isSearching && !dismissed` | scroll geometry + `loader.activeFilterCount` | `ReaderHeader`/`FilterLensBar` (**T5/T6**) | src | inventariado |
| Viewport reporting | idem | `handleViewportChanged` 1359–1370; card visibility 993–1012 with `MainFeedRuntime.cardVisibilityThreshold` | `runtime.viewportChanged(visibleItemIDs:)`, `loader.noteViewport(lastVisibleOrdinal:)`, `runtime.cardBecameVisible(itemID:)` | visible IDs + ordinals | **Bridges to V2** `FeedScreenStore.onViewport` → driver (**T3**); semantics change: V2 admits by forward scroll only | src; V2 `FeedScreen.swift` (`onScrollPhaseChange`/`onScrollGeometryChange`) | inventariado |
| Shake to refresh | idem | `ShakeDetector` 167–174 | runtime session → `runtime.refresh()`; legacy → `loader.shakeToRefresh()` | motion | **T5** (keep gesture) or explicit "not transferred" decision | src | inventariado |
| Empty states | idem | `emptyMode` 82–120, `FeedEmptyStateView` 381 lines | lanes: no sources enabled / fetching(topic, fetched, total) / no results / generic; actions `Open Filters`, `Refresh Now` | `loader` counters, `TaxonomyStore.node.feedCount` | `Sources/FeedMineUI/Reader/EmptyState` (**T5**) | src | inventariado |
| First-run loading | idem | `InitialFeedLoadingView` 2244–2377 (`StartupSignalView` TimelineView, 13 capsules 5 pt, `.drawingGroup()`, `.disabled(true)`) | inert animation while preparing | runway counters | `FeedPreparationView` (V2 exists; parity check in **T11**) | src | inventariado |
| Filter lens bar | `Views/TaxonomyChipBar.swift` | `FilterLensBar` + `FilterLensChip` (199 lines) | swipe up/side (`DragGesture` min 16) 76–88 → `onDismiss` → `dismissFilterLensForCurrentSelection`; chips: preset `preset.icon` → `loader.setActivePreset(.everything)` 24–32; search `magnifyingglass` → `clearSubmittedSearch` 37–42; region `globe.americas.fill` → `clearRegionFilter` 45–50; type → `loader.selectContentType(contentType)` 53–58; topic `tag.fill` → `loader.toggleNode(id)` 61–68; language `character.bubble.fill` → `loader.toggleLanguage(code)` 69–78; mood `mood.icon` → `loader.selectMood(mood)` 79–86 | active filter summary | `Sources/FeedMineUI/Filters/TaxonomyChipBar.swift` (**T6**) | src | inventariado |

### 1.5 Modal stack (17 presentations)

`screenWithSheets` 358–472. One destination each; V2 replaces the 11 booleans with one
typed presentation (plan T5).

| state variable | presentation | v2 destination | status |
| --- | --- | --- | --- |
| `articleItem` | `ArticleReaderView` (`.sheet(item)`) 360–367 | T9 | inventariado |
| `selectedSource` | `SourceFeedView` 368 | T7 | inventariado |
| `sourceToCollect` | `AddSourceToCollectionSheet` 369 | T8 | inventariado |
| `showSettings` | `SettingsSheetView` 370 | T10 | inventariado |
| `showSources` | `SourceManagementView` 371 | T7 | inventariado |
| `showFilters` | `FilterSheetView` 372 | T6 | inventariado |
| `showBookmarks` | `BookmarkBoxesView` 373 | T8 | inventariado |
| `showAddFeed` | `AddFeedView(targetCollectionID:targetCollectionName:)` 374–379 | T10 | inventariado |
| `showCollections` | `CollectionManagementView` 380 | T8 | inventariado |
| `showExport` | `ExportView` 381 | T10 | inventariado |
| `showCuratedOnboarding` | `.fullScreenCover` → `CuratedOnboardingView(isFirstRun:false)` 382–393 | T11 | inventariado |
| `showCuratedInspector` | `CuratedFeedInspectorView(curatedFeedID)` 394–398 | T11 | inventariado |
| `showCollectionExport` | `CollectionOPMLExportView` 399–406 | T10 | inventariado |
| `showCatalogExplore` | `CatalogExploreView(repository)` 407–418 | T7 | inventariado |
| `showCollectionImporter` | `.fileImporter` (xml/opml) 421–426 | T10 | inventariado |
| `showCreateCollectionPrompt` | `.alert` + TextField 427–434 | T8 | inventariado |
| `showCreateSmartFeedPrompt` | `.alert` + TextField 435–442 | T6/T8 | inventariado |
| `showDeleteSmartFeedConfirmation` | `.alert` 443–450 | T8 | inventariado |
| `showDeleteCuratedFeedConfirmation` | `.alert` 451–458 | T11 | inventariado |
| `nightMode` | overlay 420 (1121–1123: black 0.35, ignoresSafeArea, no hit testing) | T10 | inventariado |

Section totals: **shell 24 rows**, 0 started.

---

## 2. Cards

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Hero/thumbnail card | `Views/FeedItemCardView.swift` (557) | `FeedItemCardView`; band layout portrait/landscape; `cardOverlays`; `cardContextMenu` | context menu: bookmark/BookmarkBox (`BookmarkBoxContextMenu` 352–390 → `runtime.toggleBookmark(itemID:)` 391–411/455–478), `View Source` `rectangle.stack`, `Add Source to Collection` `rectangle.stack.badge.plus`, `Copy Link` `doc.on.doc`, `Share as Image` `photo.artframe`, `Open in Safari` `safari` (http/https only) 536–544, `Share` `square.and.arrow.up` | `PreparedFeedCard`/`mediaSlot` (already-resolved media), read state, source/category | `Sources/FeedMineUI/Cards/FeedItemCardView.swift` (**T4**) + `ReaderCardAction` (**T4**) + execution (**T9**) | shot `feed-portrait-light.png`, `feed-landscape.png`; src | inventariado |
| Card wrapper / gestures | `Views/FeedItemView.swift` (218) | `FeedItemView` 36–120 | tap → `performCardAction` 76–88 (`CardActionBridge`/`MainFeedRuntime`); media-slot tap → audio playback via `AudioPlayerManager` 36–41/66; row context menu incl. `ShareLink(item.url)` 118–120 | item + runtime action bridge | `Cards/FeedItemView.swift` (**T4**), actions (**T9**) | src | inventariado |
| Compact row | `Views/FeedItemRowView.swift` (125) | `FeedItemRowView` | no own menu; row rendering only | `mediaSlot` | `Cards/FeedItemRowView.swift` (**T4**) | src | inventariado |
| Card media contract | `Models/PreparedFeedCard.swift`, `Models/FeedCardPresentation.swift` (deprecated bridge) | `PlaceholderKind`, `ResolvedImageAsset`, `RenderReadyMedia`, `PreparedCardLayout`, `PreparedFeedCard` | — (values) | frozen slot geometry + resolved asset | `Sources/FeedMineRuntime/PresentationCard.swift` (exists) + `Cards/**` (**T4**) | src | inventariado |
| Item model helpers | `Models/FeedItem.swift` (481) | `bestImageURL`, `youTubeThumbnailURL`, `canResolveArticleImage`, `hasPotentialImage`, `audioPlaybackURL`, `isPodcast`, `isTimeless`, `durationFormatted` | URL/audio resolution used by cards and player | item metadata | `FeedMineDomain`/`Runtime` values as needed (**T4/T9**) | src | inventariado |

Section totals: **5 rows**, 4 `em transferência` (T4 ported the composition, the row and the wrapper to
`Sources/FeedMineUI/Cards/`; the action executions stay in T9). Transferred in `4e304fa`…`12d4b65` line of work,
see `PORT_LOG.md` §T4. Still open on these rows: the semantic fields V1 badges/category need (T4 remainder, T7
taxonomy) and the colour-fidelity comparison.

**Rule carried into T4:** the card renderer never
downloads or decodes (V1 already had no download inside the card; only
`ShareCardImageView`, `MiniPlayerBar/FullPlayerView`, `StoryDuelCard` and
`SourceFeedView`/`SourceCollectionFeedView` did, i.e. §6/§8).

---

## 3. Filters

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Filter sheet | `Views/FilterSheetView.swift` (297) | `FilterSheetView` — local draft of preset/content-type/language/mood; **commits on `onDisappear`** (`applyFilterDraft`/`setActivePreset`), so a dismissed sheet still applies | set/clear each criterion; Done; dismiss | countries/topics/languages/mood lists; `FiltersStore` state in `FeedStore` | `Sources/FeedMineUI/Filters/FilterSheetView.swift` + `ReaderFilterDraft`/`ReaderFilterStore` (**T6**) | src | inventariado |
| Content filter view | `Views/ContentFilterView.swift` (222) | `ContentFilterView` | master toggle; templates; add custom rule (`+` alert); swipe-to-delete | `ContentFilterStore` (singleton) | `Filters/**` + `ReaderFilter` (**T6**) | src | inventariado |
| Content filter model/store | `Models/ContentFilter.swift` (197) | `ContentFilter`, `ContentFilterTemplate`, `ContentFilterStore` (`@MainActor @Observable` singleton, JSON in Documents) | excludes items by keyword; applied in filtering **and** ingestion (`recordHit`); declared to RuntimeV2 as mandatory filter | keyword rules | `FeedMineDomain.ReaderFilter` + persistence (**T6**) | src | inventariado |
| Filter lens chips | `Views/TaxonomyChipBar.swift` | see §1.4 row | remove one criterion per chip | active criteria | `Filters/TaxonomyChipBar.swift` (**T6**) | src | inventariado |
| Filter semantics (V1 behavior to copy) | `Services/FeedStore.swift` (`applyFilters`/`applyFiltersAsync`) | criteria are combined in **series (AND)**; exclusion caches per item (mood, content filter) keyed on filter state; auto-expiry (4 h) exists for region/taxonomy/type/mood/language but **not** for content filters | — | — | `ReaderFilter` + editorial/context identity (**T6**) | src | inventariado |

Section totals: **5 rows**, 0 started. Open V2 questions recorded for T6: the V1 sheet has
no Cancel (draft commits on disappear) — V2's `ReaderFilterStore.apply(_:)` must make
apply/cancel explicit; and content filters currently have no auto-expiry.

---

## 4. Sources, catalog and taxonomy

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Source management | `Views/SourceManagementView.swift` (313) | `SourceManagementView` | category toggle → `loader.setCategoryEnabled`; source toggle → `loader.toggleSource`; health check → `URLSession` per URL; OPML import → `OPMLParser.parseImportedFile` + `loader.addSources`; `NavigationLink` → `ExportView` | `SourceRegistry`, category tree | `Sources/FeedMineUI/Sources/SourceManagementView.swift` + `SourceManagementCoordinator` (**T7**) | src | inventariado |
| Catalog explorer | `Views/CatalogExploreView.swift` (369) | `CatalogExploreView` over `CatalogBrowserViewModel`/`FeedEngineProtocol` | paginated browse; search; details sheet | catalog pages | `Sources/CatalogExploreView.swift` (**T7**) | src | inventariado |
| Taxonomy browser | `Views/TaxonomyBrowseView.swift` (202) | `TaxonomyBrowseView` | `TaxonomyStore.shared.children/search/ancestors`; `loader.toggleNode` | taxonomy tree | `Sources/TaxonomyBrowseView.swift` (**T7**) | src | inventariado |
| Countries list | `Views/CountriesListScreen.swift` (101) | `CountriesListScreen` | `loader.setAllCountriesEnabled`; `setRegionEnabled`; navigate to detail | `CountryStore` | `Sources/CountriesListScreen.swift` (**T7**) | src | inventariado |
| Country detail | `Views/CountryDetailScreen.swift` (126) | `CountryDetailScreen` | `loader.countryFeeds`; `setRegionEnabled`; `toggleSource` | country metadata + feeds | `Sources/**` (**T7**) | src | inventariado |
| Region detail | `Views/RegionDetailScreen.swift` (98) | `RegionDetailScreen` | `loader.regionFeeds`, `requestRegionEnabled`, `regionToggleState`, `toggleSource` | region metadata | `Sources/**` (**T7**) | src | inventariado |
| Source feed view | `Views/CollectionManagementView.swift` (SourceFeedView/SourceCollectionFeedView) | `ImageLoader.resolveImage` **network** inside the view | open source feed; list items with resolved images | source items | `Sources/**` (**T7**) — **must not** keep image downloads in the View (T7/T4 rule) | src | inventariado |
| Taxonomy store | `Services/TaxonomyStore.swift` (811) | `TaxonomyStore.shared` | children/search/ancestors queries | taxonomy sqlite | `SourceManagementCoordinator` + persistence (**T7**) | src | inventariado |

Section totals: **8 rows**, 0 started. Open V2 questions for T7: V1's "zero sources
selected" state must be preserved (T7 explicitly overrides V2's "at least one source"
rule if it blocks parity), and V1's `sourceID` is a truncated 32-bit hash
(`CatalogIdentity.swift:55`) — V2 IDs stay UUIDs with a recorded mapping (PD-2).

---

## 5. Collections and bookmarks

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Collection management | `Views/CollectionManagementView.swift` (720) | `CollectionManagementView`, `SourceCollectionDetailView`, `AddSourceToCollectionSheet` | CRUD + reorder `SourceCollection`; add sources; open collection feed | `SourceCollection` model + `loader` | `Sources/FeedMineUI/Collections/**` + `ReaderLibraryCoordinator` (**T8**) | src | inventariado |
| Bookmark boxes | `Views/BookmarkBoxesView.swift` (183) | `BookmarkBoxesView` | `loadBookmarkLists`; create/rename/delete/reorder; refresh; select active list; set default | `BookmarkList`, `BookmarkStore` | `Sources/FeedMineUI/Bookmarks/**` (**T8**) | src | inventariado |
| Bookmark box picker | `Views/BookmarkBoxPickerView.swift` (67) | `BookmarkBoxContextMenu`, `BookmarkBoxPickerView` | `loader.toggleBookmark(itemID, listID:)` | bookmark lists | `Bookmarks/**` (**T8**) | src | inventariado |
| Bookmark model | `Models/BookmarkList.swift` (16) | `BookmarkList` | pure value (id/name/isDefault/itemCount/search*) | — | `FeedMineDomain.ReaderBookmarkList` (**T8**) | src | inventariado |
| Presets / smart feeds | `Models/FeedPreset.swift` (521) | `FeedPreset`, `PresetSelector` (incl. `.curatedFeed`), `SmartFeedDefinition`, `SmartFeed`, refresh policies | activate/delete preset; smart-feed creation from search | preset store | `FeedMineDomain.ReaderPreset` + `ReaderFilterStore` identity (**T6/T8**) | src | inventariado |

Section totals: **5 rows**, 0 started.

---

## 6. Reader, media, sharing

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Article reader | `Views/ArticleReaderView.swift` (113) | `ArticleReaderView`, `ArticleWebView` (WKWebView) | open article; open in Safari; close | frozen target URL | V2 `InAppBrowser` exists (`FeedMineApp/InAppBrowser.swift`); port V1 reader chrome + mini player host (**T9**) | shot `article-reader-inapp.png` | inventariado |
| Mini player / full player | `Views/MiniPlayerBar.swift` (282) | `MiniPlayerBar`, `FullPlayerView` over `AudioPlayerManager` (AVFoundation) | play/pause, close/stop, scrubber commit, seek ±15, `Done`, context menu (BookmarkBox, View Source, Add Source to Collection, Copy Link, ShareLink); `CachedAsyncImage` artwork (**network in view**) | playback state, item audio URL | `FeedMineUI` views + `ReaderMediaCoordinator` (**T9**) | src | inventariado |
| Share as image | `Views/ShareCardImageView.swift` (106) | `ShareCardImageView`, `renderCardAsImage` (`ImageRenderer` + `UIActivityViewController`) | render card image; share | card + `CachedAsyncImage` (**network in view**) | `FeedMineUI` view + platform adapter in Composition (**T9**) | src | inventariado |
| Stats share card | `Views/StatsShareCard.swift` (125) | `StatsShareCard` (`ImageRenderer`) | share stats | `FeedMetrics` | `FeedMineUI` view (**T9**), data from Runtime | src | inventariado |
| Audio player service | `Services/AudioPlayerManager.swift` (497) | `AudioPlayerManager.shared` | play/pause/seek/save position | AVFoundation | `ReaderMediaCoordinator` + platform adapter (**T9**) | src | inventariado |

Section totals: **5 rows**, 0 started. Rule for T9: `UIActivityViewController`,
`UIPasteboard` and AVFoundation stay in platform adapters outside the renderers.

---

## 7. Settings, feedback, import/export

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Settings sheet | `Views/SettingsSheetView.swift` (436) | `SettingsSheetView` | font size; language; circadian palette + typography on/off; palette family; font style; performance/prefetch; night mode; filter auto-expire; navigate to content filters; data (export/reset); share stats; about; feedback | `@AppStorage` keys in `Services/AppSettings.swift`; `LocaleManager`; `CircadianEngine` | `Sources/FeedMineUI/Settings/SettingsSheetView.swift` + `ReaderSettings` (**T10**) | src | inventariado |
| Toast | `Views/ToastView.swift` (21) | `ToastView` | none (caller-driven; auto-dismiss 2 s, black 0.8 capsule, bottom 100, spring 0.35/0.8 — FeedScreen 1097–1119) | message + symbol | `Sources/FeedMineUI/Feedback/ToastView.swift` (**T5**) | src | inventariado |
| Clipboard banner | `Views/ClipboardBanner.swift` (119) | `ClipboardBanner` | `checkClipboard`; `autoCheck()`; Add / Dismiss | pasteboard + `InputParser` | `Feedback/ClipboardBanner.swift` (**T5**, import action T10) | src | inventariado |
| Add feed | `Views/AddFeedView.swift` (455) | `AddFeedView` | input parse (`InputParser`/`URLResolver`); preview; confirm; `loader.importFeeds`/`importOPML`/`addSourceURLs`; collection target; clipboard; posts `feedImportCompleted` | parse + import pipeline | `Sources/FeedMineUI/ImportExport/AddFeedView.swift` + `ReaderImportExportCoordinator` (**T10**) | src | inventariado |
| Export | `Views/ExportView.swift` (406) | `ExportView` with `ExportScope`/`ExportFormat` | preview (sample) → `generateExportData`; share/save/copy (activity controller / pasteboard) | export engine | `ImportExport/ExportView.swift` (**T10**) | src | inventariado |
| OPML parser | `Services/OPMLParser.swift` (867) | `parseImportedFile`, `parseAll`, `deduplicate`, `mediaKind`, `normalizeURL`/`requestURL` | pure parsing | XML | `FeedMineDomain`/Persistence (**T10**) — copy only if its semantics pass V2 identity vectors | src | inventariado |
| Settings keys/services | `Services/AppSettings.swift`, `Services/LocaleManager.swift` | `Keys`/`Settings` registry; `LocaleManager.shared` + 39 languages | typed get/set; language resolution | UserDefaults | `ReaderSettings` + stores (**T10**) | src | inventariado |
| Settings actions in FeedScreen | `Views/FeedScreen.swift` | `handleScenePhase` 1467–1482, `updateBadge` 1455–1458, `handleWillEnterForeground` 1486–1491 | badge count (`UNUserNotificationCenter.setBadgeCount`); persist `lastScrollItemID`; background scheduler; audio position save | notifications + scene phase | `ReaderSettings`/app host (**T10**) | src | inventariado |

Section totals: **8 rows**, 0 started.

---

## 8. Onboarding and curation

| surface | v1Path | v1Symbol | actions | data deps | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Onboarding gate | `Views/OnboardingTipsView.swift` (38) | `OnboardingTipsView` (`@AppStorage hasSeenOnboarding`) | presents `CuratedOnboardingView(isFirstRun:true)`; on save posts `onboardingDidSaveCuratedFeed` | flag + notification | `Sources/FeedMineUI/Onboarding/**` (**T11**) | src | inventariado |
| Curated onboarding | `Views/CuratedOnboardingView.swift` (527) | `CuratedOnboardingView` (welcome/composer stages), `CuratedProfileControls`, `CuratedBackdrop` (`ImageCache.diskImage`, no network) | resolve recipe via `FeedRecipeResolver.effectiveProfile`; persist `loader.createCuratedFeed`/`setActivePreset`; reset; start broad; open my feed | recipe + choices | `Onboarding/**` + `CuratedFeedCoordinator` (**T11**) | src | inventariado |
| Welcome scene | `Views/Onboarding/WelcomeScene.swift` (196) | `WelcomeScene` | renders real cards (`loader.items.prefix(6)`) as a cascade; CTAs "Shape my feed" / "Start broad" | real items | `Onboarding/WelcomeScene.swift` (**T11**) | src | inventariado |
| Composer scene | `Views/Onboarding/FeedComposerScene.swift` (352) | `FeedComposerScene` | live preview cards via `loader.previewCuratedCards` (coalesced 100 ms) + controls; footer Reset / Start broad / Open my feed | preview items | `Onboarding/FeedComposerScene.swift` (**T11**) | src | inventariado |
| Composer controls | `Views/Onboarding/{DiscoverySlider,EditorialBalanceControl,LanguageSelectionControl,MediaTypeToggles,TopicPreferenceRow,FlowLayout}.swift` | see file names | discovery slider 0…1; editorial balance (less/balanced/more per style); language chips + searchable grid (min 1); media-type toggles (article/podcast/video); topic cycle Normal→More→Less; wrap layout | choice values | `Onboarding/**` (**T11**) | src | inventariado |
| Curated inspector | `Views/CuratedFeedInspectorView.swift` (413) | `CuratedFeedInspectorView` ("open hood") | edit name/languages/weights/learning; `loader.loadCuratedFeeds`/`updateCuratedFeed`/`setActivePreset` | curated feed definition | `Onboarding/**` (**T11**) | src | inventariado |
| Recipe model/resolver | `Models/FeedRecipeDefinition.swift` (122), `Services/FeedRecipeResolver.swift` (69), `Services/CuratedPreferenceEngine.swift` (1103) | `PreferenceLevel`, `MediaType`, `FeedRecipeDefinition`, `neutral(languages:)`, `effectiveProfile` | pure resolution of a recipe into a profile | catalog facets | `FeedMineDomain`/`FeedMineEditorial` (**T11**) | src | inventariado |
| Curated models | `Models/CuratedFeed.swift` (366), `Models/OnboardingSeed.swift` (81) | `CuratedFeed`, `CuratedProfileDefinition`, `CuratedChoiceOutcome`, `CuratedEvidence`, `CuratedTopic`, `CuratedEditorialStyle`, `curatedFeatureDisplayName`, `OnboardingIntent`, `OnboardingSeed` | values | — | Domain/Editorial/Persistence (**T8/T11**) | src | inventariado |

### 8.1 Orphans — present in V1, unreachable (recorded, **not** transferred)

| file | evidence |
| --- | --- |
| `Views/Onboarding/StoryDuelScene.swift` (110), `StoryDuelCard.swift` (92, `CachedAsyncImage`) | no references in the repo; the composer no longer routes to a duel |
| `Views/Onboarding/ChoiceFeedbackOverlay.swift` (79), `ConfidenceProgressView.swift` (52) | no references outside their own files |
| `FeedScreen.SourceSearchDetailView` (1966–2044) | defines `toggleSource`/`ShareLink` but is never instantiated |

These rows exist so nobody "restores" a surface the product dropped, and so a parity
auditor does not count them as missing. V2 does not implement them.

Section totals: **9 rows**, 0 started; 4 orphans recorded.

---

## 9. Appearance system

| surface | v1Path | v1Symbol | content | v2 destination | proof | status |
| --- | --- | --- | --- | --- | --- | --- |
| Design tokens | `Services/DesignTokens.swift` (187) | `PrimitiveColor`, `SemanticColor`, `ComponentToken`, `Color(oklchL:)`, `Color(hex:)` — pure/static | palettes, semantic colors, component values | `Sources/FeedMineUI/Appearance/ReaderAppearance.swift` (**T4**) replacing `FeedDesignTokens.swift` | src | inventariado |
| Circadian palette/typography | `Services/CircadianEngine.swift` (362) | `CircadianPeriod`, `PaletteFamily`, `FontStyle`, `FontRole`, `CircadianEngine.shared` (hourly timer + UserDefaults) | period → palette family + fonts; `pageBackground`, `accent`, `cardGap`, `cardPadding`, `cardRadius`, `font(for:size:)`, `activeFontWeight`, `refresh()` | `Appearance/**` pure values (**T4**); the timer/singleton is **not** copied; "presentation is not rebuilt by an appearance timer" (plan constraint) | src | inventariado |
| Assets / fonts / localization | V1 app bundle (`feedmine_brand_assets/`, `Resources/`) | assets, font files, localized strings | — | V2 app resources (**T4/T10**); check names and platform availability | src | inventariado |
| Night mode | `Services/AppSettings.swift` `Keys.nightMode`; `FeedScreen` overlay 1121–1123 | black 0.35 overlay, ignores safe area, no hit testing | — | `Appearance/**` (**T10**) | shot `night-portrait.png` | inventariado |

Section totals: **4 rows**, 3 `em transferência` (T4 ported the tokens, the palette/typography values and the
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
