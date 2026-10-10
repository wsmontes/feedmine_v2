# V1 UI reference — conditions, evidence and how to reproduce it

Task T1 of `docs/superpowers/plans/2026-10-09-transferencia-frontend-v1-v2.md`.
This file records the *conditions* under which the V1 frontend was observed, so any
later parity claim (T4–T12) can be checked against the same reference instead of a
memory of "how V1 looked". It is not a visual approval of the current V2 build.

## Checkouts and revisions

| Role | Path | Revision | Working tree |
| --- | --- | --- | --- |
| V1 source (read-only reference) | `/Users/wagnermontes/Documents/GitHub/feedmine` | `712a6ba93c6a8ab28c3b3c0e2b2777d1e3341d0c` | **dirty** — see below |
| V2 destination | `/Users/wagnermontes/Documents/GitHub/feedmine_v2` | `372f4c5cb6df5110e25f49b74f65a34ea507d5a6` | clean at T1 start; T1 adds only docs |

V1 local modifications present during T1 (recorded, not reverted, never modified):

| File | Size | Relevance to the transfer |
| --- | --- | --- |
| `feedmine/Views/FeedScreen.swift` | +2/−1 | Comment only, inside `CompactFeedContent` docs (line ~1693). No behavior. T5 may copy the file unconditionally. |
| `feedmine/Services/FeedStore.swift` | +201/−90 region | V2-runtime bridge work; never copied (the plan forbids porting `FeedStore`). |
| `feedmine/Services/FeedLoader.swift` | ±15 | Same. |
| `feedmine/Services/SourceRegistry.swift` | ±7 | Same. |
| `Packages/FeedRuntimeV2/**`, `feedmine/RuntimeV2/**`, other test files | — | V2 prototype inside V1; out of scope for the transfer. |

Commands used to establish this:

```sh
cd /Users/wagnermontes/Documents/GitHub/feedmine && git rev-parse HEAD && git status --porcelain
git diff --stat -- feedmine/Views feedmine/Models feedmine/Services
git diff -- feedmine/Views/FeedScreen.swift     # comment-only, verified
```

## Build conditions of the reference build

```sh
xcodebuild -project feedmine.xcodeproj -scheme feedmine \
  -destination "platform=iOS Simulator,id=8871DCF5-0C06-4C7C-88D2-7B3DC36E8284" \
  -derivedDataPath /tmp/feedmine-v1-derived CODE_SIGNING_ALLOWED=NO build
# → ** BUILD SUCCEEDED **  (Xcode 26.6 / 17F113, GRDB 7.4.0, FeedKit 9.1.2)
```

The `feedmine` scheme resolves `Packages/FeedRuntimeV2` as a **local** package; the
build above therefore compiles the dirty V1 tree, not the tag. This is why the
screenshots below are labeled with the dirty revision, not with `712a6ba` alone.

## Observed runtime conditions

| Item | Value |
| --- | --- |
| Device | iPhone 17 Pro Max simulator, iOS 26.5, `8871DCF5-0C06-4C7C-88D2-7B3DC36E8284` |
| Viewport | 440×956 pt, @3× (screenshots 1320×2868 px; landscape 2868×1320) |
| Orientation | portrait and landscape (landscape via Simulator ⌘→; the app supports all four orientations) |
| System appearance | light (system dark appearance does **not** change V1's palette — see limitations) |
| App appearance | `nightMode` UserDefaults (default `false`), `circadianPaletteOn` (default `true`) — V1's palette comes from `CircadianEngine` + these keys, not from `UIUserInterfaceStyle` |
| Locale | `-AppleLanguages (en)` |
| Launch arguments | `-ui-testing -UITestSkipOnboarding` (test vocabulary; used only to bypass the onboarding gate) |
| Dynamic Type | system default (no override) |
| Data origin | the simulator's persisted V1 store (source *All Articles on Seeking Alpha*, items dated Oct 07 2026, cards showing an empty media slot) plus live network acquisition |

## Evidence inventory

Directory `docs/evidence/v1-ui/` (not committed — see below):

| File | What it shows | Conditions |
| --- | --- | --- |
| `feed-portrait-light.png` | Reader root: floating compact header (`Feedmine · 4 of 71,234 sources wat…`, search / bookmarks / filter / ellipsis buttons), card with media slot, source row, headline, `2 days ago`, bookmark affordance | portrait, light, default appearance |
| `feed-landscape.png` | Same content in landscape: bands are laid out with the source row and text beside the media slot | landscape, light |
| `article-reader-inapp.png` | In-app article reader (WKWebView) opened from a card tap, with the publisher paywall rendered inside the in-app browser chrome | portrait, light |
| *(night)* | `nightMode=YES` dims/repaints the feed via V1's night overlay; captured as `night-portrait.png` in the same directory — the palette interaction is recorded as a limitation below | portrait, `nightMode=true` |

Reproduction:

```sh
U=8871DCF5-0C06-4C7C-88D2-7B3DC36E8284
xcrun simctl install $U /tmp/feedmine-v1-derived/Build/Products/Debug-iphonesimulator/feedmine.app
xcrun simctl ui $U appearance light
xcrun simctl launch $U com.feedmine.app -ui-testing -UITestSkipOnboarding -AppleLanguages "(en)"
sleep 12 && xcrun simctl io $U screenshot feed-portrait-light.png
# landscape
osascript -e 'tell application "Simulator" to activate' \
         -e 'tell application "System Events" to key code 124 using command down'
sleep 3 && xcrun simctl io $U screenshot feed-landscape-raw.png && sips -r 90 feed-landscape-raw.png --out feed-landscape.png
# night palette
xcrun simctl spawn $U defaults write com.feedmine.app nightMode -bool YES
```

`docs/evidence/` is git-ignored: the plan asks for screenshots outside the Git
history ("sem mídia volumosa no Git"), so the images live locally and are
reproducible from the commands above.

## Limitations recorded honestly

1. **No deterministic content.** V1's `TestConfiguration` parses `-fixture-profile`,
   `-fixture-seed`, `-fixed-theme`, `-network-profile` (`feedmine/Services/TestConfiguration.swift:86-107`)
   but the app only stores the value: `TestConfiguration.active` is assigned at
   `feedmine/feedmineApp.swift:218` and never read anywhere else in the target
   (`grep -rn "TestConfiguration.active" feedmine --include=*.swift` returns that single line).
   The fixture vocabulary is therefore **dead** in this checkout, and the reference
   screenshots use persisted real content rather than an injected fixture. Parity
   comparisons in T4/T5/T9/T10 must therefore compare *the same persisted content*
   (same source, same items) or accept a structural comparison.
2. **System dark appearance is not V1 dark mode.** Setting the simulator to dark
   left the feed visually identical, because V1's palette is `CircadianEngine` +
   `nightMode`/`paletteFamily` (`feedmine/Services/AppSettings.swift:20-26`,
   `feedmine/Services/CircadianEngine.swift`). The night evidence was produced by
   writing the `nightMode` default into the app container; it shows the overlay
   path, not a full dark palette. A faithful light/dark pair is a T4/T10
   deliverable, produced from the ported appearance system.
3. **Menu / filter / lens / sheet screenshots are missing.** These surfaces need
   taps inside the Simulator window. Pointer automation through the window was
   attempted twice and landed on the card instead of the header button (the first
   attempt opened the article reader, which is preserved as evidence above), so no
   filter-sheet or menu screenshot is claimed. Their content is inventoried from
   source in `docs/v1-study/UI_TRANSFER_MATRIX.md`, and the same surfaces must be
   captured as V2 screenshots during T5/T6, where the V2 UI test target can tap
   them reliably (`accessibilityIdentifier` is already used by V1's own UI tests).
4. **Data is network-backed.** Cards show an empty media slot because media for
   these items was not materialized in the V1 store at capture time; that state is
   useful (it is the "no image yet" look) but it is not a *designed* text-only
   card, so T4's text-only layout still needs its own comparison.
