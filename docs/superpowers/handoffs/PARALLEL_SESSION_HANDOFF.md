# Handoff — parallel OMP session in `feedmine_v2`

Written by the session that owns the transfer plan
(`docs/superpowers/plans/2026-10-09-transferencia-frontend-v1-v2.md`) on 2026-10-09.
**Read this before editing anything in this repository.**

## 1. Where the work stands

| Task | State | Commit |
| --- | --- | --- |
| T1 inventory (`docs/v1-study/UI_TRANSFER_MATRIX.md`, `docs/reviews/V1_UI_REFERENCE.md`) | done | `3533151` |
| T2 production vs admission (`FeedPresentationAdmission`) | done | `4e304fa` |
| T3 scroll admits without moving content (native UI test green) | done | `12d4b65` |
| T4 V1 card layouts + visual system (`Sources/FeedMineUI/Cards/**`, `Appearance/`) | done | `bb8e33e` |
| T5 shell/header/menu/search | **in progress in the other session** | — |
| T6–T12 | not started | — |

Last verified state at `bb8e33e`: `swift build` clean, `swift test` **861 tests, 0 failures**, iOS
`xcodebuild … CODE_SIGNING_ALLOWED=NO build` → BUILD SUCCEEDED, and
`-only-testing:FeedMineUITests/FeedMineUITests/testT3ScrollAdmitsWithoutMovingTheReadingPoint test` → TEST
SUCCEEDED.

## 2. Claim protocol (this is the point of this file)

1. **Append** one line to the "Claims" section below **before** you start editing:
   `- T<n> — claimed by <session label> at <date time> (<short description>)`.
2. Do not work on a task that is already claimed by someone else.
3. **Hot files** — announce in your claim line before touching any of them:
   `FeedMineApp/FeedMineApp/AppComposition.swift`, `Sources/FeedMineUI/FeedScreen.swift`,
   `Sources/FeedMineComposition/FeedRunwayDriver.swift`, `Sources/FeedMineRuntime/FeedSession.swift`,
   `Sources/FeedMineRuntime/PresentationCard.swift`, `docs/v1-study/PORT_LOG.md`.
4. Commit per task with the message the plan gives that task. Never `git push`. Never `git stash` or
   `git checkout -- .` on a tree you did not verify: the other session may have uncommitted work.
5. Verification before every commit: `swift build && swift test`; for UI work also the iOS build and, when
   the task has a UI test, the `-only-testing:` run. Report the executed numbers in the commit body or in
   `docs/v1-study/PORT_LOG.md`.

### Claims

- T5 — claimed by the plan-owner session at 2026-10-09 (shell/header/menu/search, then T6).
- **Open offer to the parallel session:** take **T10** (settings, locale, import/export). It is the most
  isolated remaining task: new files in `FeedMineDomain`/`FeedMineComposition`/`FeedMineUI`, its own tests, and
  only a small `AppComposition` wiring edit. If you are already mid-task, say so in a claim line and keep it;
  if you would rather stay read-only, take the **T12 review** instead (audit T2–T4 against the plan's Review
  Focus list, write findings under `docs/reviews/`, change no code).

## 3. Contracts you must not break

These are consumed by already-committed code and tests; changing them means migrating every call site in the
same commit.

- **Admission** (`Sources/FeedMineRuntime/FeedPresentationAdmission.swift`): `FeedSession.admitPresentation(_:)`
  with `.initial(bounds)`, `.forwardScroll(ViewportObservation)`, `.restore(bounds)`. Production never admits.
  `RunwayActivity.admitsForwardContent == .explicitTailApproach` only. `submitViewport` records position and
  bounds decoded-image residency; it never extends the list.
- **Card surface** (`Sources/FeedMineUI/Cards/**`): `FeedItemCardView(card:appearance:isRead:isBookmarked:
  isInBookmarkBox:availableActions:onAction:)` and `FeedItemView` with the same shape plus
  `layout: ReaderItemLayout`. Every interaction is one `ReaderCardActionEvent`; no URL, pasteboard, player or
  share sheet inside `FeedMineUI`.
- **Store** (`FeedScreenStore`): `availableActions` + one `onAction`; `perform(_ event:)` forwards only for an
  admitted occurrence and only for an available action. There is no `onOpen`/`onBookmark` pair any more.
- **Appearance** (`Sources/FeedMineUI/Appearance/ReaderAppearance.swift`): immutable value (`period`,
  `paletteFamily`, `fontStyle`, `typeScale`) with computed palette/metrics/fonts. No clock, no singleton: a
  presentation is never rebuilt because time passed.
- **UI boundary tests** (`Tests/ArchitectureSmokeTests/FeedScreenRenderingTests.swift` U14,
  `FeedScreenStoreTests` S11/S12) enforce: `FeedMineUI` imports no production module, no `URLSession`/`Task`/
  `Timer`/`GeometryReader`/`@State` in the reader files, one `@State` in `FeedScreen`, one presentation value
  in the store. Read them before adding anything to `FeedMineUI`.

## 4. Independent slices that do not collide with T5/T6

Pick one and claim it. Each is a whole plan task with its own files, tests and commit message.

| Task | Own files (nobody else touches these while you own it) | Watch out |
| --- | --- | --- |
| **T10** settings, locale, import/export | `Sources/FeedMineDomain/ReaderSettings.swift`, `Sources/FeedMineComposition/ReaderSettingsCoordinator.swift`, `ReaderImportExportCoordinator.swift`, `Sources/FeedMineUI/Settings/**`, `Sources/FeedMineUI/ImportExport/**`, ports of `Services/{AppSettings,LocaleManager,OPMLParser}.swift`, `Tests/FeedMineDomainTests/ReaderSettingsTests.swift`, `Tests/FeedMineCompositionTests/ReaderImportExportTests.swift` | `AppComposition` wiring is hot — append a claim line and keep the edit minimal |
| **T8** collections, bookmark lists, presets | `Sources/FeedMineDomain/{ReaderCollection,ReaderBookmarkList,ReaderPreset}.swift`, stores in `Sources/FeedMinePersistence/**`, `Sources/FeedMineComposition/ReaderLibraryCoordinator.swift`, `Sources/FeedMineUI/Collections/**`, `Bookmarks/**`, `RuntimeMigrations.swift`, tests | migrations are additive and versioned; never open a V1 database with the V2 migrator |
| **T7** catalog/taxonomy/sources | `Sources/FeedMineUI/Sources/**`, `Sources/FeedMineComposition/SourceManagementCoordinator.swift`, `Sources/FeedMinePersistence/SourceManagementStore.swift`, catalog importer, tests | V1 `sourceID` is a 32-bit hash — map to stable V2 UUIDs, never reuse the number |
| **T12 review (read-only)** | nothing | independently audit T2–T4 against the plan's *Review Focus* list (stable stationary reader, long scroll both directions, A→B→A filters, interrupted migration, no-image/Dynamic Type/Reduce Motion) and write the findings into `docs/reviews/` — most valuable of all if you are unsure what to take |

## 5. Rules that were already expensive to learn here

- `models.yml`/config changes need a new process; `omp` reads them at boot.
- The V1 checkout is a read-only reference: never modify or format it.
- `docs/evidence/` is git-ignored on purpose (T1 reference screenshots). Do not commit binary media.
- No hosted CI: the local `swift build && swift test` is the only gate, and it must be **executed**, not
  claimed.
- Deleting a control is not parity: if a surface is not transferable yet, record it in
  `docs/v1-study/UI_TRANSFER_MATRIX.md` with its owner task instead of dropping it.
