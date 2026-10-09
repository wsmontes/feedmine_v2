# v1 study — UI, app composition, main-thread state, testing, CI, release

Static review of FeedMine v1 (`C:\workspace\feedmine-dev`, iOS 18.0, Swift 6, SwiftUI +
GRDB + FeedKit) to inform v2 (`C:\workspace\feedmine_v2`). No Swift toolchain here; every
claim below is cited to a file:line read during this session. v2 docs read first:
`ARCHITECTURE.md`, `RUNTIME_PRESENTATION_CONTRACT.md` (§8–§14), `FILE_RESPONSIBILITIES.md`,
`reviews/CODE_REVIEW_2026-10-08.md`.

## 1. Scope — files with LOC

| v1 file | LOC | Role |
| --- | ---: | --- |
| `feedmine/feedmineApp.swift` | 239 | `@main App`, `WindowGroup`, bg scheduler, URL handling, UITest flags, `TapTrace` |
| `feedmine/ContentView.swift` | 10 | Unused thin wrapper (own `FeedLoader`, not the App's) |
| `feedmine/Views/FeedScreen.swift` | 1891 | Root screen: feed, search, filters, scroll, states, lifecycle |
| `feedmine/Views/FeedItemView.swift` | 128 | Card tap/gesture owner |
| `feedmine/Views/FeedItemCardView.swift` | 533 | Card rendering |
| `feedmine/Views/FeedEmptyStateView.swift` | 215 | Empty/loading/no-results/no-sources surface |
| `feedmine/Services/FeedLoader.swift` | 1701 | `@Observable` MainActor view model; viewport index owner |
| `feedmine/Services/FeedStore.swift` | 8293 | MainActor god-store (GRDB, reservoir, prep, search…) |
| `feedmine/Services/FeedMineSignposts.swift` | 133 | `OSSignposter` interval registry for XCTest metrics |
| `feedmine/Services/DesignTokens.swift` | 176 | OKLCH color primitives → semantic → component tokens |
| `feedmine/Services/LocaleManager.swift` | 119 | 39-language picker over `AppleLanguages` |
| `feedmine/Services/WhatsNewManager.swift` | 171 | New-item carousel pool |
| `feedmine/Services/ShakeHandler.swift` | 27 | `UIViewControllerRepresentable` shake→refresh |
| `feedmine/Services/TestConfiguration.swift` | 192 | Typed launch-arg config |
| `feedmine/Services/AppSettings.swift` | 165 | `Keys` + `Settings` UserDefaults registry |
| `feedmine/Services/Log.swift` | 9 | 5 `OSLog` categories |
| `feedmineTests/FeedStoreTests.swift` | 3957 | Unit tests (size smell) |
| `feedmineUITests/PersonaExplorationUITests.swift` | 919 | Screenshot/journey harness |
| `.github/workflows/ios-ci.yml` | — | 2 jobs: fast identity test + full ReleaseValidation plan |
| `project.yml` / `Makefile` / `TestPlans/*.xctestplan` | — | Build config (reference), device/sim build+test, 5 plans |

## 2. How v1 works (concise)

`FeedmineApp` (`feedmineApp.swift:72`) owns five `@State` services and injects them via
`.environment(...)` into a single root `FeedScreen()`. There is no composition-root type; DI
is `@Environment` + singletons (`.shared`) + direct construction. `FeedScreen` reads one
`@Observable` `FeedLoader`, which fronts the 8293-LOC `FeedStore`. The feed body
(`FeedScreen.swift:875`) is a `ScrollViewReader` → `ScrollView` → `LazyVStack` of `Section`
(`loader.dateSections`) → `FeedItemView`, each `.id(item.id)`. Display is gated by
`loader.feedDisplayPhase` (`.preparing/.ready/.empty/.failed`, `FeedScreen.swift:110-128`).

## 3. Code review findings

| ID | Sev | Location | Mechanism | Effect |
| --- | --- | --- | --- | --- |
| UI-1 | — | `FeedScreen.swift:884-897`, `917-921`; `FeedLoader.swift:610-628` | Viewport captured by `.onAppear`→`noteVisibleIndex(for:)`, `.onScrollVisibilityChange(threshold:0.5)` (iOS 18) for seen-marking, and `.onScrollGeometryChange { geo.contentOffset.y }` (iOS 18) for header collapse. Position **restored** by persisting `lastScrollItemID` on `.background` (`:1318`) and `proxy.scrollTo` on cold start (`:925-931`, `startScreen` `:1017`). | Working viewport capture on iOS 18 — the capability v2 M14/§3Q5 calls deferred |
| UI-2 | M | `FeedLoader.swift:621-628` | `noteVisibleIndex(for:)` does `filteredItems.firstIndex(where:)` — O(n) per `onAppear`; guarded by a 1-item cache (`_lastNoteVisibleID`) and an index fast-path (`:614`) added after a "snap to 0 → premature trim" review finding. | Scroll-time O(n) scans; fragile index semantics tied to trimming |
| UI-3 | H | `feedmineApp.swift:120-233` | Cross-cutting flow (import result, open-source, import-completed) is routed through `NotificationCenter` userInfo dicts, consumed in `FeedScreen` (`observedScreen` `onReceive` chain `:160-210`). Stringly-typed, no single owner. | Hidden coupling; hard to test; the ignored-tap class (UI-5) lives in this event-delivery seam |
| UI-4 | M | `FeedScreen.swift` whole file (1891 LOC); `FeedStore.swift` (8293); `FeedLoader.swift` (1701) | One screen owns feed+search+filters+collections+smart-feeds+lifecycle+scroll; one store owns persistence+reservoir+prep+search. | Change-risk concentration; the exact monolith v2 ARCHITECTURE forbids |
| UI-5 | H | `FeedItemView.swift:53-71` | Card tap is a bare `.onTapGesture` on a `VStack` with `.contentShape(Rectangle())` applied one level up in `FeedScreen` (`:891`). A journey hit a hittable, visible card where the tap produced no reader and no `card tap` log. | Intermittent dead taps; required a window-level `TapTrace` observer to diagnose |
| UI-6 | M | `feedmineApp.swift:88` + `ContentView.swift:1-10` | `FeedmineApp` renders `FeedScreen()` directly; `ContentView` (unused) builds its **own** second `FeedLoader`. | Dead code that, if wired, would double-instantiate the store |
| UI-7 | L | `AppSettings.swift:36` | `Settings.d` is `nonisolated(unsafe) let UserDefaults`; `TestConfiguration.active` is `nonisolated(unsafe) var` (`:131`). | Documented single-write/launch, but unchecked shared mutable state under Swift 6 strict concurrency |
| UI-8 | M | `FeedScreen.swift:66-83` (`emptyMode`) | Empty-vs-loading decision reads ~7 loader flags (`hasActiveFilters`, `isPreparingFilteredComposition`, `loadingState`, `isUrgentFetching`…). | Correct behavior (comment at `:80` documents a real "empty screens for no reason" fix) but the logic is a flag soup |

## 4. What worked (keep the idea)

- **Phase-gated display, feed never blanks on rebuild.** `FeedScreen.swift:112-117`: in
  `.preparing where !items.isEmpty` it keeps `feedScrollView` instead of swapping to a loader,
  with a comment that swapping "would blank a feed the user is already reading." v2's
  `FeedPresentationState` already encodes this (snapshot+pending keeps the window).
- **"Feed is sacred" scroll restore.** Restore is one-shot and gated by `userHasScrolled`
  (`FeedScreen.swift:925`, `startScreen:1012-1018`); foreground deliberately does **not**
  restore (`handleScenePhase:1301-1310`, comment "SwiftUI already preserves the position").
  This maps cleanly to v2's memory-local viewport + explicit-checkpoint model (RUNTIME §8–§9).
- **Prepared-card pipeline to avoid jank.** v1 migrated from reactive `CachedAsyncImage` to
  resolving media *before* a card enters the feed (`docs/.../2026-07-29-prepared-feed-architecture.md:5`,
  `cards-resolvidos-antes-de-aparecer.md`). This is why v2 has a `PresentationCard` with layout
  decided upstream — keep the "resolve before render" rule.
- **Signpost registry for performance tests.** `FeedMineSignposts.swift` gives stable
  `StaticString` interval names for `XCTOSSignpostMetric` (`FirstCardRender`, `TimelineFirstPage`…).
- **Typed launch config.** `TestConfiguration.swift` replaced scattered
  `ProcessInfo…contains(...)` with one parsed value; profiles (`empty/typical/heavy`),
  network sim, fixed date/theme, locale override.
- **Three-layer design tokens.** `DesignTokens.swift` OKLCH primitive → semantic → component
  tokens; views reference only semantic/component tokens.
- **Accessibility as an automated gate.** `AccessibilityAuditTests.swift` runs
  `performAccessibilityAudit()` on timeline, onboarding, catalog, filter, settings, loading,
  empty, and an RTL (Arabic) launch; `continueAfterFailure = true` collects all issues.
- **Catalog/editorial CI that actually asserts data.** `editorial-ci.yml` rebuilds the
  catalog, runs `PRAGMA quick_check`, validates the manifest against the Swift schema, and
  fails on LFS pointers — no `|| true`.

## 5. What failed and why (root causes)

- **Monolith by accretion.** `FeedStore.swift` reached 8293 LOC and `FeedScreen.swift` 1891
  because every feature landed in the existing owner. The `project.yml:9` warning ("do NOT
  regenerate the .xcodeproj") shows the build itself became a hand-maintained artifact — a
  symptom of no module boundaries. Root cause: no compiler-enforced ownership (v2 fixes this
  with 10 targets + `DEPENDENCY_RULES`).
- **Viewport coupled to trimming.** `noteVisibleIndex` feeds both load-more and buffer
  `trim(currentVisibleIndex:)` (`FeedStore.swift:2300,2837`; `Reservoir.swift:127-138`). A
  mis-recorded index 0 caused premature trimming, which is why the O(n) guard and index
  fast-path exist (`FeedLoader.swift:614-628`). One observation drove two unrelated policies.
- **Event delivery via NotificationCenter → undiagnosable dead taps.** The ignored-tap miss
  (UI-5) could not be localized from logs alone; v1 had to add `TapTrace`
  (`feedmineApp.swift:160-233`) and a non-retrying journey assertion
  (`PersonaExplorationUITests.swift:40-55`) to prove whether the touch reached the window.
  Root cause: tap handling spread across a bare gesture, an outer `contentShape`, and sheets.
- **UI tests mostly prove "did not crash", not behavior.** `ScrollPerformanceTests.swift`,
  `HitchRatioTests.swift` and `LaunchPerformanceTests.swift` assert `app.exists` /
  `waitForExistence` after swipes, with `guard timeline.exists else { return }` escape hatches
  that pass when the element is absent. These are brittle/low-signal: they tolerate an empty
  feed and never measure the hitch ratio named in the file.
- **Tests that caught real bugs were the small, assertive ones.**
  `CardIdentityStabilityTests.swift` (captures id order, refreshes, asserts same order — the
  mis-tap/reorder pain point) and `FeedStoreTests` cold-path `recordWait` instrumentation
  (`:30-45`, logged a real 18.6 s stall) produced actionable findings. `FeedStoreTests.swift`
  at 3957 LOC is itself a smell: one unit file carrying store + wait helpers (its own header
  at `:18` notes `Support/TestHelpers.swift` was never in the target).
- **iOS CI never built the UI/perf tests.** `ios-ci.yml` runs only `feedmineTests` /
  `FeedMine-ReleaseValidation`; the UI, performance, usability and accessibility suites are
  device/manual (`Makefile` `test-ui-device`, `PhysicalDeviceTesting.md`). Automated signal
  stopped at unit tests.

## 6. Applying to v2

### Lesson A — Viewport capture is available on v2's targets (UI-1, UI-2)
- **v2 file:** `Sources/FeedMineUI/FeedScreen.swift`, `FeedScreenStore.swift`;
  `Sources/FeedMineRuntime/ViewportObservation.swift`.
- **Current state:** `FeedScreen` renders `ScrollView/LazyVStack/ForEach` and emits **no**
  observation; §3Q5 records deferral, M14 says scroll is disconnected from the runway, and the
  premise is that richer scroll APIs "require macOS 15/iOS 18".
- **Correction (verified):** on **iOS** the APIs v1 ships are available at **18.0**, which v2
  already targets. v1 uses `.onScrollVisibilityChange(threshold:)` (`FeedScreen.swift:887`) and
  `.onScrollGeometryChange { geo.contentOffset.y }` (`:917`) today. Only the macOS side is
  gated (v2 targets macOS 14; `ScrollPosition`/phase/geometry need macOS 15). So the deferral
  is a macOS-only limitation, not an iOS one.
- **Recommendation (concrete):** emit viewport without new platform floors —
  ```swift
  // In FeedScreen, over the LazyVStack:
  @State private var topVisibleID: PublicationCardID?
  // ...
  .onScrollTargetVisibilityChange(idType: PublicationCardID.self) { visible in   // iOS 18
      guard let first = visible.first, first != topVisibleID else { return }
      topVisibleID = first
      store.submitViewport(
          ViewportObservation(anchor: PresentationAnchor(cardID: first, placement: .top)),
          activity: .reading)
  }
  ```
  Gate the macOS-15-only richer path behind `#if os(macOS)` / `if #available(macOS 15, *)`;
  keep an iOS-18 `scrollPosition(id:)`/visibility path as the baseline. Mirror v1's rules:
  one-shot restore only, never move the feed on foreground, debounce by comparing to the last
  anchor. Do **not** reuse one observation to drive trimming (v1's UI-2 bug) — Runtime owns
  window capacity separately.
- **Review IDs:** M14, §3Q5. **Priority:** High (first producer for INV-03/04).

### Lesson B — Add CI (L4, L2, L3)
- **v2 file:** new `.github/workflows/ci.yml`, new `.gitignore`, commit `Package.resolved`.
- **Current state:** no CI; ~13k LOC of tests never run automatically; no `.gitignore`/`Package.resolved`.
- **Recommendation (concrete):**
  ```yaml
  name: CI
  on: { push: { branches: [main] }, pull_request: {} }
  jobs:
    build-test:
      runs-on: macos-15        # Xcode 16 / Swift 6, has iOS 18 SDK + macOS 14 target
      steps:
        - uses: actions/checkout@v4
        - run: swift build -v
        - run: swift test -v    # add --enable-code-coverage once stable
  ```
  Because v2 is a pure SwiftPM package (no `.xcodeproj`), `swift build`/`swift test` on
  `macos-15` runs the whole graph headlessly — simpler than v1's `xcodebuild -testPlan`. Commit
  `.gitignore` (`.build/`, `.swiftpm/`, `*.xcuserstate`) and `Package.resolved` so GRDB 7.11.1 /
  FeedKit 10.9.4 are pinned (they are `exact:` in `Package.swift`, but the resolved graph must be
  in VCS for reproducible CI). **Priority:** High (L4), Medium (L2/L3).

### Lesson C — Test strategy: assertive-small over tolerant-UI
- **v2 file:** `Tests/ArchitectureSmokeTests/FeedScreenRenderingTests.swift` (exists, strong),
  future `Tests/FeedMineUITests` (none today).
- **Current state:** v2 already has the right instinct — `FeedScreenRenderingTests` uses
  `NSHostingView` + Vision OCR to assert visible text/order headlessly (17 tests, U1–U15).
- **Recommendation:** (1) Keep headless render+OCR as the primary UI gate — it is deterministic
  and CI-runnable, unlike v1's XCUITest swipe-and-pray. (2) Port v1's **CardIdentityStability**
  idea as a Runtime/Publication test: same Edition after tail-append keeps occurrence order
  (RUNTIME §10). (3) Adopt v1's `FeedMineSignposts` + `recordWait`-style stall logging for the
  acquisition/runway loops. (4) Avoid v1's `guard element.exists else { return }` escape hatches
  and 3957-LOC test files — split by behavior; a test that can pass when the subject is absent is
  worse than none. **Review IDs:** M14, M17. **Priority:** Medium.

### Lesson D — Keep a composition root; kill dead wrappers (UI-3, UI-6)
- **v2 file:** `Sources/FeedMineComposition/FeedMineBootstrap.swift` (scaffold),
  `FeedPresentationHandoff.swift` (done), `FeedScreenStore.swift`.
- **Current state:** v2 already centralizes construction in `FeedMineBootstrap` and does
  snapshot/viewport handoff via `FeedPresentationHandoff` (stateless) — this directly fixes v1's
  NotificationCenter seam (UI-3). Keep it; do not add an event bus. Ensure there is exactly one
  `FeedScreenStore` and no `ContentView`-style second graph (v1 UI-6). **Priority:** Medium.

### Lesson E — Honest empty/loading/error states (UI-8, M17)
- **v2 file:** `Sources/FeedMineUI/FeedLoadingView.swift`, `FeedScreen.swift`.
- **Current state:** `FeedLoadingView` switches on `Work { idle/pending/unavailable/deferred/failed }`;
  `FeedScreen` shows it only when `presentation == nil`. M17: once a presentation exists, `work`
  is ignored (no in-feed pending/failed indicator).
- **Recommendation:** adopt v1's distinction between "no sources", "fetching N of M", and "no
  results" (`FeedEmptyStateView.swift:3-7`, `FeedScreen.swift:66-83`) as explicit `Work`/empty
  cases rather than nil, so a finite-window edge never reads as global-empty (already a v2
  invariant). Add a non-blocking in-feed indicator for `pending/failed` when a window is present
  (v1 shows a top `ProgressView` during refresh, `FeedEmptyStateView.swift:21`). **Priority:** Medium.

### Lesson F — Localization & accessibility are launch-blocking, automate them
- **v2 file:** `FeedCardView.swift` (uses `Text(verbatim:)` + hardcoded PT labels "Autoria/Modificado/Observado").
- **Current state:** v1 shipped 39 languages via `LocaleManager` + `CFBundleLocalizations`
  (`project.yml`) and an RTL audit test; v2 strings are hardcoded Portuguese literals.
- **Recommendation:** move UI strings to a String Catalog early (v1's
  `Resources/Localizable.xcstrings`), keep `Text(verbatim:)` only for user content, and add a
  `performAccessibilityAudit()`-equivalent to the headless render tests. **Priority:** Medium.

## 7. Open questions for the product owner

1. **macOS parity:** is macOS a real target, or iOS-first? If iOS-first, the §3Q5 viewport
   deferral is unnecessary now (iOS 18 has the APIs); if macOS must match, is raising the floor
   to macOS 15 acceptable to unblock full scroll/runway coupling?
2. **Edited-but-unversioned content (H1/H3):** v1's "feed is sacred" meant a card never moved or
   duplicated on refresh (CardIdentityStability). Should an edited RSS item be a new card, an
   in-place update, or ignored? This decides viewport-restore identity in v2.
3. **Refresh affordance:** v1 had pull-to-refresh + shake-to-refresh (`ShakeHandler`,
   `FeedScreen.swift:909`). Does v2's "user navigates local history, not the internet" thesis keep
   a manual refresh gesture, or is replenishment fully implicit via the runway?
4. **In-feed work indicator (M17):** when a window is visible and background work is pending or
   failed, should the UI surface anything, and how prominent?
5. **Language scope at 1.0:** match v1's 39 locales, or ship a smaller set and grow? This sets how
   early the String Catalog + pseudoloc gate must exist.

---

### 10-line summary
1. v1 ships on **iOS 18.0** and already captures/restores viewport via `.onScrollVisibilityChange`
   and `.onScrollGeometryChange` (`FeedScreen.swift:887,917`) — not deferred as v2 §3Q5/M14 imply.
2. The deferral premise is **macOS-only**: richer scroll APIs need macOS 15; v2 targets macOS 14,
   but iOS 18 has what's needed, so iOS viewport can be wired now (Lesson A, snippet provided).
3. v1 restore is one-shot, gated by `userHasScrolled`, and never fires on foreground
   ("feed is sacred") — maps to v2's memory-local viewport + explicit checkpoint (RUNTIME §8–§9).
4. v1's jank defense was resolving media **before** cards appear (prepared-card pipeline); keep
   this "resolve-before-render" rule — it is why v2 has an upstream `PresentationCard`.
5. v1's phase-gated display keeps the feed on screen during rebuild; v2 `FeedPresentationState`
   already encodes it. Honest empty states exist but v2 ignores `work` once a window shows (M17).
6. Root failures: a 8293-LOC `FeedStore` + 1891-LOC `FeedScreen` monolith, viewport coupled to
   trimming (UI-2), and NotificationCenter event delivery that produced undiagnosable dead taps (UI-5).
7. Tests that caught real bugs were small and assertive (CardIdentityStability, `recordWait`
   stall logging); XCUITest scroll/launch tests mostly assert "didn't crash" and are brittle.
8. **CI gap (L4):** v1's iOS CI ran only unit tests; v2 has none — add a `macos-15` `swift build`
   + `swift test` workflow, plus `.gitignore` and committed `Package.resolved` (L2/L3).
9. Keep v1 wins: typed `TestConfiguration`, `FeedMineSignposts`, OKLCH design tokens, automated
   accessibility+RTL audits, and the assertive editorial CI that validates data not just builds.
10. v2's `FeedMineBootstrap`/`FeedPresentationHandoff` already fix v1's DI/event seam — keep the
    single composition root, add viewport emission, CI, and localization, and ask PO Q1–Q5 first.
