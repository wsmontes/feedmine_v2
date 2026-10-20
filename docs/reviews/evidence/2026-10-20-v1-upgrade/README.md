# V1 → V2 upgrade rehearsal (decision D7-A) — 2026-10-20

Latest run: **`03fab3ab`**, as-specified layout, no rename, no move, no deletion. The store opens inside
V1's own `Feedmine` directory and the upgrade runs; the notice is drawn by UIKit but still does not
survive and cannot be acknowledged. Runs 1–3 are kept below.

## Run 4 — as specified, at `03fab3ab` (this run)

| step | result |
|---|---|
| volume probe | `/tmp/Abc` resolves as `abc`, and the simulator's `Devices` directory likewise → **case-insensitive** |
| V1 built from source, launched | directory on disk **`Feedmine`** (V1's spelling), container `845159A5…` |
| seeded | `imported_source` 3 (one `enabled = 0`), `bookmark_list` 2, `bookmark_item` 2, `bookmark_snapshot` 2, `source_collection` 1, `source_collection_member` 2 |
| V2 Release installed over `com.feedmine.app` | container → `67A965C9…`; all seven V1 files hash-identically after the move |
| first launch | no failure surface. `Application Support` holds **one** entry, `Feedmine`; inside it `runtime.sqlite`, `-wal`, `-shm` sit beside `user.sqlite`; `find … -name runtime.sqlite` → **1** |
| receipt | `completed`, `ran_at 1792524829.018832`, boxes **1**, sources **3**, selected **2**, collections **1**, members **2** |
| `source_path` | `…/Application Support/Feedmine/user.sqlite` — the sibling candidate |
| skip | `savedArticles / notImportedInThisBuild / 2` |
| V1 files | identical (`user.sqlite 4ef31d75…`, `-wal` empty, `-shm fd4c9fda…`) |
| repeat launches | `ran_at` and every count identical across ~6 launches, no duplicated row |

**Why the store opened inside `Feedmine`.** The exact spelling `FeedMine` cannot be created on this
volume while `Feedmine` exists (the sandbox answered `NSCocoaErrorDomain 512` / `POSIX 5`, measured in
run 2), and the volume reports itself case-insensitive — the probe above. `RuntimeDatabase` therefore
took its gated fallback and reused the existing variant. No second store was created: the `FeedMine`
path resolves to the same directory, which is why one `ls` entry and one `runtime.sqlite` are the whole
inventory.

### The notice: drawn by UIKit, still not usable

`run-4-volume-gated/notice-painted.png` shows the UIKit alert with the exact copy, and — in the same
frame — the reader's own text painted over it ("Going after what's worth reading", "As primeiras
manchetes aparecem aqui"). `ax(all: true)` lists the alert (title, body, "Entendi") at 1.21 s and again
at 2.0 s.

But the screen at ≥2 s has no alert: `run-4-volume-gated/no-alert-at-5s-no-tap.png` (≈5 s, no tap) and
`…-second-shot.png` (≈8 s) show only the reader's "Couldn't connect.". The burst after launch shows the
alert painted at ~0.3–0.6 s and gone from ~0.9 s.

The flag behaves correctly in one direction and not the other: `notice_presented` = **0** on a launch
with no tap, and still **0** after an AX press on "Entendi" at 1.21 s and a calibrated window click at
0.35 s. The tap never reaches the button.

Acceptance "the alert stays ≥2 s, Entendi is hittable and the flag flips only on that tap" is **not
met**: the flag does not flip without a tap (right), and it does not flip with one either, because the
presentation is short-lived and under the reader's layer.

## History

- **Run 3 (`c7c850af`)** — store opened inside `Feedmine` and the upgrade ran, but the SwiftUI alert was
  painted behind the reader surface, visible under a second, with every calibrated click landing on
  "Try again". `run-3-application-support/`.
- **Run 2 (`3a1f72a7`)** — as-specified blocked before the upgrade: `createDirectory("…/FeedMine")` →
  `NSCocoaErrorDomain 512` / `POSIX 5` while `Feedmine` existed; the upgrade was then proven through the
  case-collapsed shape. `run-a-as-specified.txt`, `run-a-lldb-*.log`, `run-a-as-specified-failure.png`.
- **Run 1 (`e98e47dc`)** — same blocker, unmeasured; the upgrade ran through `Documents/user.sqlite`.
  Artifacts remain in git; `rehearsal-1-documents/` keeps the screenshot.

## What was built

| | source | result |
|---|---|---|
| V1 | `_legacy_feedmine_v1`, scheme `feedmine`, Debug / iphonesimulator | BUILD SUCCEEDED |
| V2 | product worktree HEAD `03fab3ab`, scheme `FeedMine`, **Release** | BUILD SUCCEEDED |

V2 Release keeps `com.feedmine.app` so it installs into V1's container. The working tree was **clean**
at build time — this binary is exactly `03fab3ab`.

V1's database was created by V1's own binary (`v1_bookmarks … v11_user_operation`) and seeded with
`sqlite3` using V1's shipped DDL and only the columns the V2 reader selects
(`Sources/FeedMinePersistence/LegacyUserStateReader.swift`).

## Result detail (Run 4)

| category | V1 had | V2 has |
|---|---|---|
| personal sources | 3 (one disabled) | 3 rows — `…/ciencia/feed.xml`, `…/tecnologia/feed`, `…/arquivo/feed`; the two enabled ones are selected, the disabled one preserved and not selected |
| browser boxes | default `Favorites` + `Leituras longas` | `saved` (V2's own default) + `v1:list:2` "Leituras longas"; the default is not duplicated; `reader_bookmark_memberships` = 0 because saved articles are not imported in this build |
| collections | 1 with 2 members | `v1:collection:1` "Ciência e Tecnologia" with 2 memberships, keyed by V1's `source_identity` |

## Files

| file | what |
|---|---|
| `before.sha256` / `after.sha256` / `diff.txt` | V1's files before and after Run 4 |
| `receipt.json` | raw queries: receipt, skips, counts, sources, boxes, collections, members, container UUIDs, volume probe, store inventory |
| `notice.txt` | the alert's copy and AX tree, the 2 s screen, and the flag values with and without a tap |
| `screenshot.png` | the UIKit alert as drawn (Run 4) |
| `run-4-volume-gated/` | alert painted, and the 5 s / 8 s frames with no alert |
| `run-3-application-support/`, `run-a-*`, `case-collision-lldb.log` | the earlier runs' evidence |
| `rehearsal-1-documents/` | the only Run 1 artifact kept locally |
| `commands.txt` | every command of Run 4 |

## What this does NOT prove

- **Not the notice's acceptance.** It is drawn but not retained and not hittable; no tap is recorded and
  no second launch after an acknowledgement exists.
- **Not a phone.** The simulator volume is case-insensitive, so the fallback ran; on a device the two
  spellings are distinct directories and this run says nothing about that path. The gated fallback's
  "exact spelling wins on a case-sensitive volume" branch is untested here.
- **Not real users' V1 databases.** One synthetic database seeded to the shapes the reader selects.
- **Not an iOS upgrade path.** No signing, no App Store install-over, no earlier OS.
- **Not the declined data.** Saved articles (2), smart feeds and curated feeds are reported, not imported.
- **Not concurrency or interruption.** One import, then relaunches.
- **Not the other runtime categories** (feed content, editions, media, session checkpoints).
