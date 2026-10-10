# U1 — V1 visual identity and V2 navigation shell (review)

Executed on this machine. BASE `7bfe18a` (`origin/main`), branch `omp/u1-v1-visual-shell`.
The gate spec came from the ChatGPT architect; the OMP executed it because the implementing agent
(Codex) was out of quota until 19:04, and every proof below is from a command run here.

## 1. What changed

| File | Change |
|---|---|
| `Sources/FeedMineUI/FeedDesignTokens.swift` | **new** — the single token authority |
| `Sources/FeedMineUI/FeedCardView.swift` | tokens; `@ScaledMetric` thumbnail; vertical arrangement at accessibility sizes |
| `Sources/FeedMineUI/FeedScreen.swift` | token spacing; readable-column frame; tokenised work badge |
| `Sources/FeedMineUI/FeedLoadingView.swift` | wordmark branding above the factual work text; tokens |
| `Sources/FeedMineUI/FeedPreparationView.swift` | symbol branding; tokens for spacing/radius/typography/tints |
| `FeedMineApp/FeedMineApp.swift` | typed `ReaderDestination` model replacing the sources boolean; inline title at accessibility sizes |
| `FeedMineApp/FeedMineAppTests/CompositionTests.swift` | U1 asset-resolution and palette-adaptation proofs |
| `FeedMineApp/FeedMineAppTests/FeedMineUITests.swift` | U1 session/reading-point proof; wide-layout proof |
| `FeedMineApp/FeedMineApp/Assets.xcassets/*.imageset` | nine reviewed V1 imagesets imported |
| `Sources/FeedMineUI/FeedSourcePicker.swift` | untouched (already a plain system list) |

Nothing outside the allowlist changed. Verified by diff, not by test results:

```
$ git status --porcelain
 M FeedMineApp/FeedMineApp.swift
 M FeedMineApp/FeedMineAppTests/CompositionTests.swift
 M FeedMineApp/FeedMineAppTests/FeedMineUITests.swift
 M Sources/FeedMineUI/FeedCardView.swift
 M Sources/FeedMineUI/FeedLoadingView.swift
 M Sources/FeedMineUI/FeedPreparationView.swift
 M Sources/FeedMineUI/FeedScreen.swift
?? .../Assets.xcassets/{Wordmark-Light,Wordmark-Dark,Symbol-Gradient,Symbol-Ink,Splash-Dark,
     Placeholder-{Article,Podcast,Forum,Video}}.imageset/
?? Sources/FeedMineUI/FeedDesignTokens.swift
$ git diff --name-only -- Sources/FeedMine{Runtime,Acquisition,Publication,Editorial,Persistence,Media,Composition,Domain,Syndication} Package.swift Package.resolved | wc -l
0
$ git diff --name-only -- FeedMineApp/FeedMineApp/Info.plist FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj | wc -l
0
```

`FeedScreenStore.swift`, `FeedPresentationState.swift` and the `FeedVisualCapture` logic are
untouched; `AppComposition.swift` is untouched.

## 2. V1 decisions actually implemented

PORT (self-contained assets): the nine imagesets, with the exact filenames from the V1
`Contents.json` manifests.

ADAPT: design tokens (one lean role set, not the two V1 systems); wordmark/symbol placement on the
absence and preparation surfaces; card and chrome visual language; navigation shell as a typed
destination model in the app host.

SKIP: `CircadianEngine` (clock-driven typography, spacing, radius and palette mutation — a product
behaviour change, not a better solution); its singleton and a parallel token system; the black
`nightOverlay` standing in for dark mode; shake-to-refresh; the V1 monolithic `FeedScreen`
(2 444 lines managing sheets, filters, playback and settings); `MiniPlayerBar`/`FullPlayerView`
(the V2 product scope excludes audio/video); the curated-feed onboarding (no recipe engine in V2);
`AppIcon-Dark` activation.

**AppIcon-Dark decision (recorded as required): SKIP.** The V1 dark icon is not connected to its own
build, and the current V2 icon is already validated through TestFlight for iPhone and iPad.
`ASSETCATALOG_COMPILER_APPICON_NAME` is unchanged, no alternate-icon entitlement was added, and no
icon-switching UI exists. The imageset was not imported.

## 3. Token contract (U1-A)

One file, roles only: `Spacing` (tight/compact/normal/card/section/page/deck), `Radius`
(media/card/overlay), `Typography` (pageTitle, cardTitleFeatured, cardTitle, body, label, badge,
metadata — all Dynamic Type styles), `Palette` (cardSurface, mediaPlaceholder, secondaryText,
accent, statusPositive, statusCaution, shadow) and `Measurement` (compactThumbnailBase,
readableContentWidth, headlineDeckWidth, sourceCloudWidth, deckSymbolWidth, wordmarkWidth).
`AssetName` holds the exact catalog names.

Why it avoids the V1 systems: there is no singleton, no clock input, and no appearance override.
`FeedDesignTokens.swift` contains no `Date(`, no `Calendar`, no hour lookup — the grep returns
nothing — so nothing can invalidate the feed on a time boundary. V1's `PaletteFamily`/period idea is
not ported; only semantic, appearance-adaptive colors are used, which is why the same code serves
light and dark without an overlay.

## 4. U1-P1 … U1-P10 results

| Proof | Result | Evidence |
|---|---|---|
| P1 single token authority | PASS | one `FeedDesignTokens.swift`; no `CircadianEngine`/`ThemeManager`/`AppearanceCoordinator` in the module (only a comment naming what was not ported); `testU1TokenPaletteAdaptsToAppearanceWithoutAnOverlay` resolves `cardSurface`, `mediaPlaceholder`, `.primary` and `accent` under `.light` and `.dark` trait collections and asserts they differ |
| P2 exact asset resolution | PASS | `testU1ApprovedBrandingAssetsResolveFromTheApplicationBundle`: all nine approved names resolve from the app bundle; constructed names (`Placeholder-Article-amber`, `Placeholder-Video-blue`, `Wordmark-Light-Dark`) resolve to nil; the distribution icon is still `AppIcon`/`AppIcon60x60` and `AppIcon76x76@2x~ipad` is still in the bundle; `xcrun assetutil --info Assets.car` lists exactly the ten names |
| P3 existing navigation behaviour | PASS | `testContextNavigationAndSourcePickerOffline` (identifiers `reader-contexts`, `reader-sources`, `reader-local-search`, `source-choice-*`, `native-viewport-delivery`) still green; no placeholder destinations exist; the sheet now comes from the typed `ReaderDestination` enum |
| P4 association identity | PASS | `testU1ChromeAndAppearancePreserveAssociationAndReadingPoint`: after a swipe, presenting and dismissing the sources sheet and switching the system appearance leave the DEBUG delivery counters identical (a rebuilt association would reset them to 0) and keep the same topmost card identifier |
| P5 presentation fence | PASS | `FeedScreenStore`/`FeedPresentationState` untouched; the S7/S12 fence tests stay green |
| P6 Dynamic Type | PASS | AX5 screenshot shows scaled card text with no clipping; the large navigation title clipped to “FeedMir”, so the app host now uses the inline title at accessibility sizes — re-captured screenshot shows “FeedMine” complete |
| P7 Reduce Motion | PASS | the motion surface is unchanged: 7 animation-related lines in `FeedPreparationView` (pre-existing, gated on `accessibilityReduceMotion`) and 0 in `FeedScreen`/`FeedCardView`/`FeedLoadingView`, before and after; U1 adds no animation, timer or clock state |
| P8 iPad layout | PASS | `testU1iPadLayoutPortraitAndLandscape` on iPad Pro 11-inch (M5) portrait + landscape: cards stay within the window and the readable column, and rotation leaves `backward=0`; landscape screenshot shows the centred ~700 pt column |
| P9 runtime unchanged | PASS | the diff-scope commands in §1: zero lines in every runtime module, both package manifests, the project file and `Info.plist` |
| P10 architecture and regression | PASS | S12/U14 green; 842 package tests; 18 app unit tests; 5 UI tests on iPhone 16 and 5 on iPad Pro 11-inch, all 0 failures |

## 5. Commands and results

```
swift build                                   → Build complete
swift test                                    → Executed 842 tests, with 0 failures
xcodebuild … -destination iPhone 16 test      → Executed 18 tests, with 0 failures   (FeedMineAppTests)
                                              → Executed  5 tests, with 0 failures   (FeedMineUITests)
xcodebuild … -destination "iPad Pro 11-inch (M5)" -only-testing:FeedMineUITests test
                                              → Executed  5 tests, with 0 failures
xcrun assetutil --info FeedMine.app/Assets.car → AppIcon, Placeholder-{Article,Forum,Podcast,Video},
                                                 Splash-Dark, Symbol-Gradient, Symbol-Ink,
                                                 Wordmark-Dark, Wordmark-Light
```

iOS test totals: 18 unit + 5 UI = 23, all green on both device families.

## 6. Visual evidence

`~/Documents/feedmine-evidence/2026-10-09/u1/`

| File | What it shows |
|---|---|
| `u1-iphone-dynamictype-ax5.png` | AX5 text sizes with the inline title intact and no clipped toolbar label |
| `u1-wide-portrait.png` | iPad portrait, readable column, cards inside the window |
| `u1-wide-landscape.png` | iPad landscape, centred ~700 pt column instead of a stretched feed |

## 7. Known limitations

- **Appearance switching cannot be shown on this simulator.** `xcrun simctl ui <device> appearance
  dark` reports `dark`, but no app changes appearance: the system Settings app also stayed light on
  the same iOS 26.5 runtime, so this is a runtime limitation, not an app defect. Appearance
  adaptation is therefore proven by trait resolution (§4, P1) and by the absence of any appearance
  override in the app or project, not by a dark screenshot.
- **Reader-scaled thumbnail vs decode slot.** The row thumbnail now scales with the reader's text
  size while the Runtime still decodes at its 88 pt slot, so the image can be softer at large text
  sizes. Changing decode policy is explicitly outside this gate; reported instead.
- **Hero images on iPad are decoded at phone width.** `DeviceMediaConditions` still derives
  `heroPointWidth` from the screen width, so a 700 pt column receives a wider (not narrower) bitmap:
  correct but slightly wasteful. Also outside this gate.
- The `Placeholder-*`, `Splash-Dark` and `Symbol-Ink` imagesets are imported as reviewed branding
  resources but are not rendered: `PresentationCard` carries no content-type or media-kind fact, and
  the gate forbids fabricating one or showing podcast/video imagery for an unknown type.
- `FeedSessionUI.swift` remains dead scaffolding in the module (pre-existing).

## 8. Recommendation

Suitable for U1 integration: the feed engine behaves exactly as before (P4/P5/P9), the visual system
is one adaptive token authority with no clock, and the shell is a typed destination model in the app
host. U2 can build the reader, saved articles and richer source management on this shell without
redesigning it.
