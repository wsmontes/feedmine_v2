# V1 → V2 upgrade rehearsal (decision D7-A) — 2026-10-20

Latest run: **`67d49c86`**, as-specified layout. The store opens inside V1's `Feedmine`, the upgrade runs,
and the notice is now presented in its own window: visible at 3 s and still up at ~13 s with no tap, and
dismissed by a real pointer click that flips `notice_presented` to 1 and only that. Runs 1–4 are kept below.

## Run 5 — as specified, at `67d49c86` (this run)

Built from a **pristine worktree at the commit** (`git worktree add --detach … 67d49c86`): the shared
worktree was being edited by a sibling mid-build (an untracked `PageImageOutcome.swift` and a matching
`MediaPrefetcher` edit appeared at 12:42 and broke the first build). The gitignored build input
`FeedMineApp/FeedMineApp/Resources/catalog.sqlite` was copied into it; no source was changed.

| step | result |
|---|---|
| V1 built from source, launched | directory **`Feedmine`**, container `CDC95D40…` |
| seeded | `imported_source` 3 (one `enabled = 0`), `bookmark_list` 2, `bookmark_item` 2, `bookmark_snapshot` 2, `source_collection` 1, `source_collection_member` 2 |
| V2 Release installed over `com.feedmine.app` | container → `33991340…`; all six V1 files hash-identically after the move |
| store | one entry in `Application Support` (`Feedmine`), one `runtime.sqlite`, beside `user.sqlite` |
| receipt | `completed`, `ran_at 1792525861.949945`, boxes **1**, sources **3**, selected **2**, collections **1**, members **2** |
| `source_path` | `…/Application Support/Feedmine/user.sqlite` |
| skip | `savedArticles / notImportedInThisBuild / 2` |
| V1 files | identical (`user.sqlite d53eadde…`, `-wal` empty, `-shm fd4c9fda…`) |

### The notice — accepted

- **Painted at ≥2 s and retained.** `run-5-notice-window/notice-at-3s.png` and
  `…/notice-still-up-at-13s-no-tap.png` are the same frame, ten seconds apart, with no tap in between: the
  alert sits in its own window above the onboarding surface.
- **Copy** (from the screen): "Da versão anterior" / "Importados da versão anterior: caixas 1, fontes 3,
  coleções 1. Ainda inacessíveis nesta versão: artigos salvos 2, marcadores inteligentes 0, feeds curados
  0. Eles permanecem no arquivo original da versão anterior." / "Entendi".
- **Flag without a tap:** `notice_presented` = **0** at 3 s and at 13 s.
- **Hittable:** a pointer click at pixels (455, 1230) of the window frame — the centre of the Entendi bar,
  measured in `run-5-notice-window/window-frame-with-alert.png` — flipped it to **1**.
- **After the tap:** `run-5-notice-window/after-tap-window-gone.png` shows the notice window gone and the
  onboarding surface restored; `ax(all: true)` then exposes its controls (Close, Build my feed, Start
  broad, Import OPML).
- **Second launch:** `run-5-notice-window/second-launch-no-notice.png` — no notice, receipt and every count
  identical, `notice_presented` stays 1.

AX note: the notice lives in its own `UIWindow`, so the Simulator's accessibility bridge does not expose
its elements — no "Entendi" appears in `ax(all: true)` while it is on screen. Hittability was therefore
proven with pointer input, not with an AX press.

## History

- **Run 4 (`03fab3ab`)** — store isolation correct under the volume gate (one directory, one store), but
  the UIKit alert was painted ~0.6 s and the reader's layer covered "Entendi"; the flag stayed 0 with and
  without taps. `run-4-volume-gated/`.
- **Run 3 (`c7c850af`)** — store opened inside `Feedmine`, upgrade ran, SwiftUI alert behind the reader
  surface. `run-3-application-support/`.
- **Run 2 (`3a1f72a7`)** — as-specified blocked before the upgrade by `createDirectory("…/FeedMine")` →
  `NSCocoaErrorDomain 512` / `POSIX 5`; the upgrade was proven through the case-collapsed shape.
  `run-a-as-specified.txt`, `run-a-lldb-*.log`.
- **Run 1 (`e98e47dc`)** — same blocker, unmeasured; upgrade run through `Documents/user.sqlite`.
  Artifacts in git; `rehearsal-1-documents/` keeps the screenshot.

## What was built

| | source | result |
|---|---|---|
| V1 | `_legacy_feedmine_v1`, scheme `feedmine`, Debug / iphonesimulator | BUILD SUCCEEDED |
| V2 | pristine worktree at `67d49c86`, scheme `FeedMine`, **Release** | BUILD SUCCEEDED |

V2 Release keeps `com.feedmine.app`, so it installs into V1's container. V1's database was created by V1's
own binary (`v1_bookmarks … v11_user_operation`) and seeded with `sqlite3` using V1's shipped DDL and only
the columns the V2 reader selects (`Sources/FeedMinePersistence/LegacyUserStateReader.swift`).

## Result detail (Run 5)

| category | V1 had | V2 has |
|---|---|---|
| personal sources | 3 (one disabled) | 3 rows — `…/ciencia/feed.xml`, `…/tecnologia/feed`, `…/arquivo/feed`; the two enabled ones are selected, the disabled one preserved and not selected |
| browser boxes | default `Favorites` + `Leituras longas` | `saved` (V2's own default) + `v1:list:2` "Leituras longas"; the default is not duplicated; `reader_bookmark_memberships` = 0 because saved articles are not imported in this build |
| collections | 1 with 2 members | `v1:collection:1` "Ciência e Tecnologia" with 2 memberships, keyed by V1's `source_identity` |

## Files

| file | what |
|---|---|
| `before.sha256` / `after.sha256` / `diff.txt` | V1's files before and after Run 5 |
| `receipt.json` | raw queries: receipt, skips, counts, sources, boxes, collections, members, containers, notice timings |
| `notice.txt` | the notice copy, the timings, the click that recorded it |
| `screenshot.png` | the notice as drawn (Run 5) |
| `run-5-notice-window/` | notice at 3 s, still up at 13 s, window frame used for the click, after-tap, second launch |
| `run-4-volume-gated/`, `run-3-application-support/`, `run-a-*`, `case-collision-lldb.log` | the earlier runs |
| `rehearsal-1-documents/` | the only Run 1 artifact kept locally |
| `commands.txt` | every command of Run 5 |

## What this does NOT prove

- **Not a phone.** The simulator volume is case-insensitive, so the store's gated fallback reused V1's
  directory; on a device the two spellings are distinct and the "exact spelling wins" branch is untested.
- **Not real users' V1 databases.** One synthetic database seeded to the shapes the reader selects.
- **Not an iOS upgrade path.** No signing, no App Store install-over, no earlier OS.
- **Not the declined data.** Saved articles (2), smart feeds and curated feeds are reported, not imported.
- **Not concurrency or interruption.** One import, one acknowledgement, then a relaunch.
- **Not the other runtime categories** (feed content, editions, media, session checkpoints).
