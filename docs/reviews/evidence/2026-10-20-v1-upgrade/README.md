# V1 → V2 upgrade rehearsal (decision D7-A) — 2026-10-20

Two runs against the same simulator device, second run on a fresh (erased) container and the fixes
from `7c0fed41` + `3a1f72a7`:

- **Run A — the as-specified layout, attempted again with no workaround.** V1's data at
  `Library/Application Support/Feedmine`, V2 Release installed over the same bundle id. **It still
  cannot reach the upgrade**, and the measurement below says why: inside the app's sandbox the
  directory lookup is case-exact and creating the case-variant of an existing directory fails with
  `EIO`. Details in `run-a-as-specified.txt`.
- **Run B — the case-collapsed shape the fix was written for.** V2's own `Application Support/FeedMine`
  holds the store and V1's `user.sqlite`; the upgrade runs, and the receipt's `source_path` shows the
  new `applicationSupport/user.sqlite` candidate is what found V1's file. This is the run whose
  artifacts sit at the top level of this directory.

## History of this evidence directory

The first rehearsal (commit `e98e47dc`, still in git history) ran the upgrade through
`Documents/user.sqlite`, V2's other documented candidate, because the shipped layout failed on this
host. That run's diagnosis — "the two spellings collide and the app cannot see the case variant" — was
right about the symptom and incomplete about the cause: it did not separate the *container* from the
*case*, and it did not measure the failing call. Both are measured now:

| question | measurement |
|---|---|
| Does `simctl install` change the data container? | **Yes.** `FA41F31E-0FA8-4777-9C8D-7FD07058131F` → `0C601A5B-880F-4E81-9856-A0BE2726DC38`. |
| Does the data survive that change? | **Yes.** All six files of V1's directory hash identically in the new container, before any launch. The UUID change is therefore not what breaks run A. |
| Is the host volume case-insensitive? | **Yes.** `stat` returns one inode for `FeedMine`, `Feedmine`, `FEEDMINE`. |
| Is the app's view the same? | **No.** In the app's process: `contentsOfDirectory` → `["Feedmine"]`, `fileExists("…/Feedmine/user.sqlite")` → **true**, `fileExists("…/FeedMine")` → **false**, and `createDirectory("…/FeedMine")` fails with `NSCocoaErrorDomain 512` / `NSPOSIXErrorDomain 5` (EIO). |

So the earlier fallback was justified, but for a sharper reason than "the container moved": V2's own
store path is unusable while the sibling exists under the other spelling, and no candidate-list change
can reach the upgrade because the failure is in `RuntimeDatabase`, before `LegacyV1Upgrade` runs.

## What was built

| | source | result |
|---|---|---|
| V1 | `_legacy_feedmine_v1`, `feedmine.xcodeproj` scheme `feedmine`, Debug / iphonesimulator | BUILD SUCCEEDED |
| V2 | product worktree HEAD `3a1f72a7`, `FeedMineApp/FeedMineApp.xcodeproj` scheme `FeedMine`, **Release** / iphonesimulator | BUILD SUCCEEDED |

V2 Release keeps `com.feedmine.app`, so it installs into V1's container. Both applications were built
from source; nothing here is schema-only. The product tree was additionally dirty with a sibling's
in-flight edits (`FeedItemCardView.swift`, `MiniPlayerBar.swift`, `project.pbxproj`, untracked
`FeedMediaJourneyUITests.swift`) and the binary was built from that tree.

V1's database was created by V1's own binary (`v1_bookmarks … v11_user_operation`), then seeded with
`sqlite3` using V1's shipped DDL and only the columns the V2 reader selects
(`Sources/FeedMinePersistence/LegacyUserStateReader.swift`). Inserted: `imported_source` 3 (one
`enabled = 0`), `bookmark_list` 2 (V1's default `Favorites` + `Leituras longas`), `bookmark_item` 2,
`bookmark_snapshot` 2, `source_collection` 1, `source_collection_member` 2.

## Where the directory ends up, and how the candidate found it

- **Run A:** on disk the directory is spelled **`Feedmine`** (V1 created it). V2 asks for `FeedMine`;
  it cannot create or open it, and fails before the upgrade.
- **Run B:** on disk the directory is spelled **`FeedMine`**, created by V2's own store. V1's
  `user.sqlite` sits inside it — the case-collapsed shape. The candidate list does not find it through
  a sibling: the receipt's `source_path` is
  `…/Library/Application Support/FeedMine/user.sqlite`, i.e. the `applicationSupport/user.sqlite` entry
  added in `3a1f72a7`, and `LegacyV1Upgrade` reads V1's schema from there unchanged.

## Result (Run B)

`reader_legacy_upgrade`: `status completed`, `ran_at 1792522460.08012`, boxes **1**, sources **3**,
selected **2**, collections **1**, collection members **2**.

Skips recorded with the receipt: `savedArticles / notImportedInThisBuild / 2`. `smartFeeds` and
`curatedFeeds` are 0 (V1 had none).

| category | V1 had | V2 has |
|---|---|---|
| personal sources | 3 (one disabled) | 3 rows: `…/ciencia/feed.xml`, `…/tecnologia/feed`, `…/arquivo/feed`; the two enabled ones are in the selection, the disabled one is preserved and not selected |
| browser boxes | default `Favorites` + `Leituras longas` | `saved` (V2's own default) + `v1:list:2` "Leituras longas"; the default is not duplicated; `reader_bookmark_memberships` = 0 because saved articles are not imported in this build |
| collections | 1 with 2 members | `v1:collection:1` "Ciência e Tecnologia" with 2 memberships, keyed by V1's `source_identity` |

V1's files (`user.sqlite`, `-wal`, `-shm`): `diff before.sha256 after.sha256` is empty, exit 0 —
byte-identical after the upgrade. Second launch: receipt and every count identical, no duplicated row.

## The notice — seen, but not dismissable

The alert is now drawn: `screenshot.png` is a real frame of the simulator screen showing

> **Da versão anterior**
> Importados da versão anterior: caixas 1, fontes 3, coleções 1. Ainda inacessíveis nesta versão:
> artigos salvos 2, marcadores inteligentes 0, feeds curados 0. Eles permanecem no arquivo original
> da versão anterior.
> **[Entendi]**

and the accessibility tree carries the same title and button. The old silent-consumption defect is
gone: `notice_presented` is **0** and stays 0, so the receipt is not marked presented behind the
reader's back.

What is still missing: the alert survives about one second and is then torn down by SwiftUI when the
reader surface swaps from "Looking for more news…" to "Couldn't connect." (the seeded hosts do not
resolve). Because the host view disappears, the reader's tap never lands: four acknowledgement attempts
fired within ~0.3 s of the alert appearing (AX press twice, window click at the button's frame position
twice) all left `notice_presented` at 0. **Acceptance "the reader sees it and dismisses it, with the
flag flipping only on that tap" is therefore half met: seeing is proven, dismissing is not reachable in
this state.**

## Files

| file | what |
|---|---|
| `before.sha256` / `after.sha256` / `diff.txt` | V1's three files, before and after Run B (diff empty, exit 0) |
| `receipt.json` | raw `sqlite3 -json`: receipt, skips, counts, imported sources, boxes, collections, members, selection |
| `notice.txt` | the AX tree of the alert, the exact copy, and the acknowledgement measurement |
| `screenshot.png` | the alert as drawn (Run B) |
| `run-a-as-specified.txt` | Run A: what was done, the container UUIDs, the exact error, V1 files unchanged |
| `run-a-as-specified-failure.png` | Run A's screen: "Não foi possível carregar suas fontes." |
| `run-b-collapsed/` | Run B extras: the notice frame and the raw lldb transcripts |
| `case-collision-lldb.log` | first rehearsal's in-app filesystem probe (kept for continuity) |
| `commands.txt` | every command, in order |

## What this does NOT prove

- **Not the as-specified same-directory layout.** Run A shows it is unreachable on this host; the
  upgrade was proven through the case-collapsed candidate instead. Whether a device (case-sensitive
  filesystem, two distinct directories) behaves as designed is untested here.
- **Not the notice's acceptance.** It is drawn but torn down before it can be dismissed; nothing here
  shows a reader acknowledging it, and nothing shows what a second launch does after an
  acknowledgement.
- **Not real users' V1 databases.** One synthetic database, seeded to the shapes the reader selects:
  no unusual schema, no corrupt file, no permission or read-only case, no large library.
- **Not a device or an iOS upgrade path.** Simulator only, no signing, no App Store install-over.
- **Not the declined data.** Saved articles (2), smart feeds and curated feeds are reported, not
  imported.
- **Not concurrency or interruption.** One import, one relaunch, no kill during the import.
- **Not the other runtime categories** (feed content, editions, media, session checkpoints).
