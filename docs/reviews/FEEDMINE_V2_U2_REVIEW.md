# U2 — reading journey (review)

Executed on this machine. BASE `c2f6cbc` (after U1 and the build-24 bump), branch
`omp/u2-reading-journey`. The architect (ChatGPT) defined U2 as "in-app article reading, a saved
surface and richer source management, reusing V1's visual code where it is simple and connecting
every action to the V2 authorities". Its own channel was unavailable while this ran — the omp browser
relay returned `extension rpc 'send' timed out after 20000ms` for every call and the Codex desktop
window refused input with `AxFailed: copying AXwindows failed` — so OMP operationalised that
definition into the gate and executed it, keeping every acceptance rule the architect fixed.

## 1. What changed

| File | Change |
|---|---|
| `FeedMineApp/FeedMineApp/InAppBrowser.swift` | **new** — `SFSafariViewController` in a representable, with the delegate that closes it |
| `FeedMineApp/FeedMineApp/AppComposition.swift` | the open path hands the resolved URL to the host; bounded saved-article read; `openSaved` without the window guard |
| `FeedMineApp/FeedMineApp/FeedMineApp.swift` | one sheet enum (`sources` / `reader`), a pushed `Salvos` screen, toolbar entry, reader wiring |
| `Sources/FeedMineUI/FeedSavedListView.swift` | **new** — `FeedSavedArticle` value + list with rows, identifier `saved-article-<uuid>` |
| `Sources/FeedMineUI/FeedSourcePicker.swift` | selected-first ordering, selection count header, empty state |
| `FeedMineApp/FeedMineAppTests/{CompositionTests,FeedMineUITests}.swift` | U2 proofs, plus a `<link>` in the fixture RSS |

Nothing outside the allowlist changed: zero diff lines in every package module, in both manifests,
in `Info.plist`, in the asset catalog and in the release scripts. The only project-file change is the
membership entry for the new app-target file (`InAppBrowser.swift` needed
`PBXFileReference`/`PBXBuildFile`/group/`PBXSourcesBuildPhase`, since this project has no
synchronised groups).

## 2. V1 decisions actually implemented

ADAPT `ArticleReaderView`: the V1 reader is a custom `WKWebView` with its own progress bar on top of
Safari. The architect preferred "a lean SafariServices integration; custom WKWebView only if there is
a real need", so the URL goes to `SFSafariViewController` — reader mode, share, translation and
security updates come from the system, and the app keeps no web engine. The URL is resolved by the
composition and reaches the host as a callback; a view never sees it.

ADAPT `BookmarkBoxesView`/`BookmarkBoxPickerView`: the V1 box manager is bound to `FeedLoader`'s
`bookmarkLists`. V2 has one bookmark authority, so U2 lists the existing bookmarks instead of
importing a second model. No box/groups, no reorder, no swipe actions — those are U4.

PORT the picker pattern: the V1 source management had per-source toggles with deferred pending
state. U2 keeps the V2 picker's identifiers and callbacks and adds only selection-first order, a
count and an empty state. No health check (that is a network feature) and no OPML.

SKIP: the V1 mini player (product scope excludes audio/video), collections, the catalog explorer and
export — all U4, and all dependent on contracts that do not exist yet.

## 3. Contracts

Reader: `AppComposition.open(_:)` keeps its window guard and its action check; `openSaved(_:)` skips
only the window guard, because a saved article may sit outside the window, and still requires
`primaryActionKind == "externalURL"` plus a parseable reference from published history. Both call the
host through `onExternalURL`; the app host presents `InAppBrowser`.

Saved: ids come from `PublicationStore.bookmarkedCardIDs()`, rows from `card(id:)`, ordered by
published timestamp descending with the id as a tiebreak, capped at 200. No new table, no migration,
no second authority. `FeedSavedArticle` carries no storage handle and no URL.

Presentation: a single `.sheet(item:)` switches between the sources sheet and the reader, so a second
sheet modifier can never shadow the first; `Salvos` is pushed on the existing navigation stack, so the
reader covers the list and closing it returns to it.

## 4. Results

| Proof | Result | Evidence |
|---|---|---|
| P1 in-app reader | PASS | `testU2SavedListAndInAppReaderPreserveTheSession`: the row opens the reader and `app.webViews` appears in-app; closing it returns to the list |
| P2 saved surface | PASS | same test: long-press → "Salvar artigo" → the row `saved-article-<uuid>` is listed with title and source; the unit test asserts removal clears the list |
| P3 open a saved article | PASS | `testU2SavedArticlesUseTheBookmarkAuthorityAndOpenOutsideTheWindow`: `openSaved` resolves the frozen URL of a card outside the presented window; the feed guard is untouched |
| P4 identity | PASS | same UI test: after reader → back, the delivery counters are identical to before opening the list; the U1 proof still covers the sheet and appearance |
| P5 sources | PASS | count header `source-selection-count`, selected-first order, empty state, no HTTP in the view; existing persistence test still green |
| P6 boundary | PASS | `swift test` 842/0 with S12/U14 green; the new FeedMineUI file contains none of the forbidden tokens; zero diff in the protected modules |
| P7 regression | PASS | iOS: 19 unit + 6 UI tests, 0 failures, iPhone 16 / iOS 26.5; package 842/0 |

```
swift build                    → Build complete
swift test                     → Executed 842 tests, with 0 failures
xcodebuild … iPhone 16 test    → Executed 19 tests, with 0 failures (FeedMineAppTests)
                               → Executed  6 tests, with 0 failures (FeedMineUITests)
```

One test-fixture fix was needed: the shared `FixtureTransport` RSS had no `<link>`, so no fixture
card carried an external action and the saved-article proof could not resolve a URL. The fixture now
publishes `<link>https://fixture.invalid/story-N</link>`, which is closer to real feeds; every
pre-existing test that uses it still passes.

## 5. Known limitations

- The reader is `SFSafariViewController`, so it is the system's UI, not a styled reader. Offline
  reading of extracted text is explicitly not part of U2.
- The saved list is bounded at 200 rows and reads one card per id; a large bookmark set would need a
  bounded query, which is a Persistence change and therefore out of this gate.
- `Salvos` shows no per-row bookmark affordance yet: removal happens from the feed's card menu. U4
  can add per-row actions.
- The V1 share-card and export surfaces are not ported (U4).

## 6. Recommendation

Suitable for integration: the three surfaces are wired to the existing authorities, the feed engine
is untouched, and the architect's acceptance rules hold under executed proof. Build 25 carries U2.
