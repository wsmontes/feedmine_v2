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
