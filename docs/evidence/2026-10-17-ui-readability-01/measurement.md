# UI-READABILITY-01 — measurements before and after

Status: **evidence**. The captures and numbers below are what was rendered and read; the fix is route A of the
architect's verdict (2026-10-17) — 1.0 declares one light presentation — not dark mode.

## 1. The defect, as the architect captured it

| Fact | Value |
| --- | --- |
| Capture | `dark-appearance.png`, 1206 × 2622 px (3× scale, 402 × 874 pt) |
| Candidate | `1e638170` — the frozen 1.0 candidate, before this branch's fix |
| Device | simulator `FeedMine UI ptBR`, iOS 26.5 |
| Device appearance | **dark** (`xcrun simctl ui … appearance dark`) |
| App appearance period | `.night` (00:56, `followsClock`), palette `warmEarth` |
| Surface | the feed shell's sources-empty state: `.title3` bold heading over `pageTintHex(for: .night)` |

Pixel method: the capture was read as raw sRGB. The first band of pure-white pixels in the content column (the
"Nenhuma fonte habilitada" heading) is rows **1463–1508**; row 1509 is already background, so the band holds text
and background only. The modal colour of that band is the page: **`(240, 235, 228)`** = `#F0EBE4` (40 187 px,
matching `pageTintHex(for: .night)`). The second cluster is the text: **`(255, 255, 255)`** (11 933 px). WCAG 2.x
relative luminance is computed on linearised sRGB channels (`c/255`; `c/12.92` if `c ≤ 0.04045`, else
`((c+0.055)/1.055)^2.4`), weights `0.2126 R + 0.7152 G + 0.0722 B`, and the ratio is
`(L_lighter + 0.05) / (L_darker + 0.05)`.

```
L(background) = 0.83543      L(text) = 1.00000
ratio = (1.00000 + 0.05) / (0.83543 + 0.05) = 1.186  →  1.19:1
```

The heading is 20 pt bold — "large" by WCAG's wide definition — so even the lenient bar is 3:1, and **1.19:1 fails
it**. The cause is systemic, not local: `ReaderPaletteFamily.pageTintHex(for:)` is a fixed light value per period
and every surface painting it pairs it with `.foregroundStyle(.primary)`, which resolves to white in a dark
environment.

## 2. The same method, on the real surfaces, by the UI test

`FeedMineUITests/AppearanceLegibilityUITests` samples the running app's own capture (`XCUIScreenshot`) with the same
two-colour method, implemented in the test: the **background** is the region's modal colour (32 levels per channel,
so a stray glyph or a control's tint cannot stand in for the page) and the **ink** is the mean of the region's
extreme 1% — the side farthest from the background, because the defect made the text *lighter* than the page and the
fix makes it darker; a sampler that only looked for dark ink reported 1.00:1 on the pre-fix tree and would have
missed the defect. Cross-checked against PIL on the exported captures: the same regions, the same modal colours.

Surfaces sampled: the first feed card's title band (`.primary` over the card surface), the local reading surface's
headline and body (`.primary` over `pageBackground`), and the settings sheet's title (`.primary` over the sheet's
page). All are normal-size text; the bar is WCAG AA 4.5:1.

### Pre-fix tree, device in dark appearance — **fails** (`Executed 1 test, with 4 failures`)

| Surface | Background | Text | Contrast |
| --- | --- | --- | --- |
| feed card title | `#EEE6DF` (L=0.8010) | `#FFFFFF` (L=1.0000) | **1.23:1** |
| reading headline | `#F0EBE4` (L=0.8356) | `#FFFFFF` (L=1.0000) | **1.19:1** |
| reading body | `#F0EBE4` (L=0.8356) | `#FFFFFF` (L=1.0000) | **1.19:1** |
| settings sheet title | `#F0EBE4` (L=0.8355) | `#FFFFFF` (L=1.0000) | **1.19:1** |

Captures: `feed-dark-before.png`, `reading-dark-before.png`, `sheet-dark-before.png`.

### After the fix, device in dark appearance — **passes** (`Executed 1 test, with 0 failures`)

| Surface | Background | Text | Contrast |
| --- | --- | --- | --- |
| feed card title | `#EEE6DF` (L=0.8009) | `#000000` (L=0.0000) | **17.02:1** |
| reading headline | `#F0EBE4` (L=0.8354) | `#000000` (L=0.0000) | **17.71:1** |
| reading body | `#F0EBE4` (L=0.8354) | `#000000` (L=0.0000) | **17.71:1** |
| settings sheet title | `#F0EBE4` (L=0.8354) | `#000000` (L=0.0000) | **17.71:1** |

Captures: `feed-dark-after.png`, `reading-dark-after.png`, `sheet-dark-after.png`.

### After the fix, device in light appearance — **passes** (`Executed 1 test, with 0 failures`)

Identical to the dark run, surface by surface (feed 17.02:1; reading headline, body and sheet title 17.71:1), which
is the property route A declares: the same light presentation in both appearances. Capture: `feed-light-after.png`.

The test also asserts that every sampled background is light (L ≥ 0.5), so a surface that kept a dark environment
while its page tint stayed light cannot pass by contrast alone.

## 3. The environment was verified independently of the app

`xcrun simctl ui <device> appearance` was set and read back, and the simulator's own Settings app was captured in
both states: `#1C1C1E` as its modal colour in dark, `#FFFFFF` in light. The switch reaches a system app, so "the
device was dark" is not an assumption the capture rests on. (This contradicts the older note in `docs/IOS_RUN.md`
that `simctl ui appearance` did not reach apps on this runtime.)

## 4. Every period, not only the one the capture happened to be in

`pageTintHex(for:)` is a fixed table, and the light presentation resolves `.primary` to the system's black label,
so the worst case is the darkest tint — measured at runtime in `.night`, above, at 17.71:1. The other three are
lighter, so their contrast can only be higher:

| Period(s) | `pageTintHex` | Relative luminance | Contrast against `#000000` |
| --- | --- | --- | --- |
| dawn, morning | `#FAF8F5` | 0.9405 | 19.81:1 |
| afternoon | `#F8F5F0` | 0.9155 | 19.31:1 |
| evening | `#F5F0E8` | 0.8756 | 18.51:1 |
| night | `#F0EBE4` | 0.8354 | 17.71:1 |

No period is illegible after the pin, and no tint was changed.

## 5. What the fix does not touch

`pageTintHex` values, `ReaderAppearance`, every card, every layout, the admission/window/viewport path and the
navigation model are unchanged. The production diff is `FeedMineApp/FeedMineApp/FeedMineApp.swift` alone — the
presentation's appearance, declared where the presentation is made. No palette, no second authority, no dark mode.

## 6. The gate's eight surfaces — all eight measured or declared

The acceptance gate enumerates eight surfaces: feed, reading, cards, settings, sources, saved, collections and
filters. Sections 2–3 measured the first four. This section measures the other four, in the same run's own pixels,
and states for every one of the eight what is sampled and what, if anything, rests on the construction.

### 6.1 What is sampled, and how the "before" was obtained

`FeedMineUITests/AppearanceLegibilityUITests` gained
`testTheSourceSavedCollectionAndFilterSurfacesAreLegibleWithTheDeviceInDarkAppearance`: one launch, four sheets
reached by the navigation the suite's own journeys already use — header menu → "Fontes"
(`testContextNavigationAndSourcePickerOffline`), `bookmark-boxes-button` → "Caixas de salvos"
(`testBookmarkBoxesManageAndOpenTheirOwnList`), header menu → "Coleções de fontes"
(`testCollectionsManageAndReachThePresetPicker`), `filter-button` → "Filtros"
(`testT6FilterSheetOpensAppliesAndKeepsTheReader`). Each sheet's own title band is sampled with the existing
sampler (modal colour = background, mean of the extreme 1% on the side farthest from it = ink, WCAG 2.x relative
luminance); the filter sheet adds the first criterion row's name, because its inline title is drawn with the
platform's own ink and would not answer for the sheet's `.primary` content.

The "before" column is the **pre-fix tree itself**, not a re-argument: a worktree at `1e638170` whose
`FeedMineApp/FeedMineApp/FeedMineApp.swift` hashes to `91e2dfe8…` — exactly that commit's blob — with only the new
test file and its `project.pbxproj` membership copied in, and the two gitignored build inputs copied byte for byte
(`Resources/catalog.sqlite` sha256 `e6da170e…`, `bench/corpus/profiles.json` sha256 `24109941…`). No production
file was reverted on the branch.

Device: simulator `FeedMine UI ptBR` (3AEA0B45-0BE6-49F1-8BAB-2591B13BBE7A), iOS 26.5. `xcrun simctl ui …
appearance` was set and read back (`dark`, then `light`) before each run.

### 6.2 Per-surface ratios — device in dark appearance, then light

| Gate surface | Sampled text | Background / ink, dark, **pre-fix** | dark, after | light, after |
| --- | --- | --- | --- | --- |
| feed (and its cards) | first card's title band | `#EEE6DF` / `#FFFFFF` — **1.23:1** | `#EEE6DF` / `#000000` — **17.02:1** | 17.02:1 |
| reading | local reading headline | `#F0EBE4` / `#FFFFFF` — **1.19:1** | `#F0EBE4` / `#000000` — **17.71:1** | 17.71:1 |
| reading | local reading body | `#F0EBE4` / `#FFFFFF` — **1.19:1** | `#F0EBE4` / `#000000` — **17.71:1** | 17.71:1 |
| settings | sheet title | `#F0EBE4` / `#FFFFFF` — **1.19:1** | `#F0EBE4` / `#000000` — **17.71:1** | 17.71:1 |
| **sources** | "Fontes" title band | `#FAF8F5` / `#FFFFFF` — **1.06:1** | `#FAF8F5` / `#000000` — **19.81:1** | 19.81:1 |
| **saved** | "Caixas de salvos" title band | `#FAF8F5` / `#FFFFFF` — **1.06:1** | `#FAF8F5` / `#000000` — **19.81:1** | 19.81:1 |
| **collections** | "Coleções de fontes" title band | `#FAF8F5` / `#FFFFFF` — **1.06:1** | `#FAF8F5` / `#000000` — **19.81:1** | 19.81:1 |
| **filters** | "Filtros" inline title band | `#FAF8F5` / `#000000` — 19.81:1 (already legible) | `#FAF8F5` / `#000000` — **19.81:1** | 19.81:1 |
| **filters** | first criterion row's name | row material `#2C2C2E` / `#FFFFFF` — 13.94:1 but L=0.0253 → **fails the light-presentation bar** | row `#FFFFFF` / `#000000` — **21.00:1**, L=0.9999 | 21.00:1 |

Two facts the numbers state on their own:

- The sources, saved and collections titles are the same defect on three more presentations: white `.primary` over
  the light page tint. The fix reaches all three.
- The filter sheet's *inline* title was already black in the pre-fix tree (the platform draws it), and its *rows*
  were a dark material under white text — a second appearance on a surface whose page was light. After the
  declaration the row is `#FFFFFF` under black text; the same assertion (page luminance ≥ 0.5 **and** ≥ 4.5:1) is
  what turns that around.

### 6.3 Executed counts, verbatim

```
pre-fix tree, dark:  Executed 1 test, with 4 failures (0 unexpected) in 36.687 (36.688) seconds
after, dark:         Executed 2 tests, with 0 failures (0 unexpected) in 55.915 (55.917) seconds
after, light:        Executed 2 tests, with 0 failures (0 unexpected) in 55.001 (55.003) seconds
```

The four pre-fix failures are the three 1.06:1 titles and the filter row's dark material; every other assertion in
that run passed, so the red is the surfaces' and not the harness's. In both after runs all nine sampled pairs
passed in both appearances, and the light run is surface-for-surface identical to the dark one — the property route
A declares.

### 6.4 The construction, for what is not sampled

No surface was skipped for being unreachable: all four were reached and measured. What is *not* sampled on them is
their bodies (the rows below each title), and that rests on one declaration, not on a second authority:

- `FeedMineApp/FeedMineApp/FeedMineApp.swift:633` — `.preferredColorScheme(.light)` on the window's content. Every
  SwiftUI presentation the window draws (these four sheets among them) inherits it; none of
  `SourceManagementView`, `BookmarkBoxesView`, `CollectionsView`, `FilterSheetView` declares an appearance or a
  colour scheme of its own, and each paints `appearance.pageBackground` with `.primary`/`.secondary`.
- `FeedMineApp.swift:789-798` — the only `UIHostingController` the app presents through UIKit (the reader) sets
  `overrideUserInterfaceStyle = .light` where that presentation is made.
- There is no `UIWindow(` anywhere in `Sources/` or `FeedMineApp/FeedMineApp`: there is no second window whose
  style could differ from the one the declaration is on.

So the eight surfaces are: feed, cards, reading and settings sampled (sections 2–3); sources, saved, collections
and filters sampled here; and the body content of each sheet covered by the declaration above.
