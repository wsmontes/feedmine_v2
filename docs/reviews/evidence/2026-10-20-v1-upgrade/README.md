# V1 → V2 upgrade rehearsal (decision D7-A) — 2026-10-20

Latest run: **`c7c850af`**, the as-specified layout, no rename, no move, no deletion. The store now opens
inside V1's own `Application Support/Feedmine` directory and the upgrade runs; the notice is drawn but
still cannot be acknowledged. Details below, with the two earlier runs kept as history.

## Run 3 — as specified, at `c7c850af` (this run)

| step | result |
|---|---|
| V1 built from source, launched, container created | directory on disk **`Feedmine`** (V1's spelling) |
| seeded | `imported_source` 3 (one `enabled = 0`), `bookmark_list` 2, `bookmark_item` 2, `bookmark_snapshot` 2, `source_collection` 1, `source_collection_member` 2 |
| V2 Release installed over `com.feedmine.app` | container `5008052D…` → `EEAF13CE…`; the data moves with it (all seven files hash-identically after the install) |
| first launch | **no failure surface**: "Não foi possível carregar suas fontes." is gone. `runtime.sqlite`, `runtime.sqlite-wal` and `runtime.sqlite-shm` appear **inside `Application Support/Feedmine`**, beside `user.sqlite` |
| receipt | `status completed`, `ran_at 1792523778.805289`, boxes **1**, sources **3**, selected **2**, collections **1**, members **2** |
| `source_path` | `…/Application Support/Feedmine/user.sqlite` — the **sibling** candidate, V1's own directory, exactly as intended |
| skip | `savedArticles / notImportedInThisBuild / 2` |
| V1 files | `before.sha256` → `after.sha256` identical for `user.sqlite` (`c3f08b44…`), `-wal` (empty), `-shm` (`fd4c9fda…`) |
| second launch | `ran_at` and every count identical across ~10 launches; no duplicated row |

Because the store and V1's database now share one directory, the upgrade no longer needs the
case-collapsed candidate nor the Documents fallback: the sibling `Feedmine/user.sqlite` is what the
receipt names.

### The notice: drawn, but behind the reader surface, and unacknowledgeable

`run-3-application-support/notice-drawn.png` shows the alert with the exact copy; the AX tree carries
"Da versão anterior" and the "Entendi" button. But `run-3-application-support/notice-behind-surface.png`
(0.45 s after launch) shows the reader's own surface painted **over** the alert, and by 0.95 s the
reader's "Try again" button sits on the same pixels as "Entendi". The alert fades within ~1 s.

- Pointer clicks at the Entendi bar, calibrated from those frames and issued at eight moments between
  0.18 s and 1.22 s after launch, all landed on "Try again" (click delivery itself was verified: a click
  there does restart the load).
- `win.find("Entendi")` returned no element in a 22 s AX poll at 0.1 s intervals.
- `notice_presented` stayed **0** throughout: nothing was acknowledged, and nothing was recorded without
  a tap either.

Acceptance "the reader sees the notice and dismisses it, with the flag flipping only on that tap" is
**not met**: seeing is proven, dismissing is not reachable while the alert is below the content.

## History

### Run 2 — `3a1f72a7`, as-specified attempted, blocked before the upgrade

V1's `Feedmine` existed; V2's `RuntimeDatabase` asked for `FeedMine` and the app sandbox refused:
`fileExists("…/Feedmine/user.sqlite")` = true, `fileExists("…/FeedMine")` = false,
`createDirectory("…/FeedMine")` → `NSCocoaErrorDomain 512` / `NSPOSIXErrorDomain 5` (EIO). The app showed
"Não foi possível carregar suas fontes." and wrote nothing. The container UUID changed on install, but
the data hashed identically across the move, so the container was not the cause. Full record:
`run-a-as-specified.txt`, `run-a-lldb-filesystem.log`, `run-a-as-specified-failure.png`.

The upgrade itself was then proven through the case-collapsed shape (V2's `FeedMine` holding the store
and V1's `user.sqlite`), with `source_path` naming `applicationSupport/user.sqlite`. That is the run whose
notice first appeared; it lived ~1 s and was torn down by the reader swap.

### Run 1 — first rehearsal (git `e98e47dc`)

Same blocker, not yet measured precisely; the upgrade was run through `Documents/user.sqlite`, V2's other
documented candidate. Its artifacts are in git at `e98e47dc`; only the V1 screenshot is kept locally in
`rehearsal-1-documents/`.

## What was built

| | source | result |
|---|---|---|
| V1 | `_legacy_feedmine_v1`, `feedmine.xcodeproj` scheme `feedmine`, Debug / iphonesimulator | BUILD SUCCEEDED |
| V2 | product worktree HEAD `c7c850af`, `FeedMineApp/FeedMineApp.xcodeproj` scheme `FeedMine`, **Release** | BUILD SUCCEEDED |

V2 Release keeps `com.feedmine.app`, so it installs into V1's container. The product tree was dirty with
a sibling's in-flight work (16 files: `PublicationStore*`, `RuntimeMigrations`, `PublicationCardDraft`,
`PublicationCoordinator`, `PresentationCard`, `PublicationPreparation`, `FeedItemCardView`,
`FeedItemRowView`, two test files, `AppComposition.swift`, and the untracked
`FeedMediaJourneyUITests.swift`); the Release binary was built from that tree. None of those edits touch
the upgrade path or the notice.

V1's database was created by V1's own binary (`v1_bookmarks … v11_user_operation`) and then seeded with
`sqlite3` using V1's shipped DDL and only the columns the V2 reader selects
(`Sources/FeedMinePersistence/LegacyUserStateReader.swift`). No table was invented.

## Result detail (Run 3)

| category | V1 had | V2 has |
|---|---|---|
| personal sources | 3 (one disabled) | 3 rows — `…/ciencia/feed.xml`, `…/tecnologia/feed`, `…/arquivo/feed`; the two enabled ones are in the selection, the disabled one is preserved and not selected |
| browser boxes | default `Favorites` + `Leituras longas` | `saved` (V2's own default) + `v1:list:2` "Leituras longas"; the default is not duplicated; `reader_bookmark_memberships` = 0 because saved articles are not imported in this build |
| collections | 1 with 2 members | `v1:collection:1` "Ciência e Tecnologia" with 2 memberships, keyed by V1's `source_identity` |

## Files

| file | what |
|---|---|
| `before.sha256` / `after.sha256` / `diff.txt` | V1's files before and after Run 3 |
| `receipt.json` | raw `sqlite3 -json`: receipt, skips, counts, sources, boxes, collections, members, container UUIDs |
| `notice.txt` | the alert's AX tree, the exact copy, and the measurements showing it cannot be dismissed |
| `screenshot.png` | the alert as drawn (Run 3) |
| `run-3-application-support/` | the alert frame and the frame showing the reader surface painted over it |
| `run-a-as-specified.txt`, `run-a-*.png`, `run-a-lldb-*.log` | Run 2's blocked attempt, with the measured EIO |
| `case-collision-lldb.log` | Run 1's in-app filesystem probe |
| `rehearsal-1-documents/` | the only Run 1 artifact kept locally |
| `commands.txt` | every command of Run 3 |

## What this does NOT prove

- **Not the notice's acceptance.** It is drawn but sits below the reader surface; no tap reaches it and
  `notice_presented` never becomes 1. Nothing here shows a second launch after an acknowledgement.
- **Not real users' V1 databases.** One synthetic database seeded to the shapes the reader selects: no
  unusual schema, corrupt file, permission case or large library.
- **Not a device or an iOS upgrade path.** Simulator only, iOS 26.5, no signing, no App Store install-over,
  no real-device filesystem.
- **Not the declined data.** Saved articles (2), smart feeds and curated feeds are reported, not imported.
- **Not concurrency or interruption.** One import, then relaunches; no kill during the import, no
  crash-restart, no partial write.
- **Not the other runtime categories** (feed content, editions, media, session checkpoints).
