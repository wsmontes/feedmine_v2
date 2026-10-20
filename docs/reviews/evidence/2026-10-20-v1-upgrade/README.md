# V1 → V2 upgrade rehearsal (decision D7-A) — 2026-10-20

Owner-mandated rehearsal of the V1→V2 first-launch upgrade shipped in `a0bfe812`.
Product tree under test: `.codex/worktrees/v2-fluidez-capacidade/feedmine_v2` @ `6b7c779a`
(the tree was dirty with a sibling's in-flight edits to `FeedItemCardView.swift`,
`MiniPlayerBar.swift`, `FeedMineApp.xcodeproj/project.pbxproj` and an untracked
`FeedMediaJourneyUITests.swift`; the Release binary below was built from that working tree).
Simulator: `FeedMine V1V2 Upgrade`, iPhone 17 / iOS 26.5, created for this rehearsal.

## What was built

**Both applications were built from source — nothing schema-only.**

| | source | command | result |
|---|---|---|---|
| V1 | `_legacy_feedmine_v1` (Xcode project `feedmine.xcodeproj`, scheme `feedmine`) | `xcodebuild … -configuration Debug -sdk iphonesimulator build` | BUILD SUCCEEDED (150 s) |
| V2 | `FeedMineApp/FeedMineApp.xcodeproj`, scheme `FeedMine` | `xcodebuild … -configuration Release -sdk iphonesimulator build` | BUILD SUCCEEDED (206 s) |

V2 **Release** was installed deliberately: it is the configuration that keeps
`CFBundleIdentifier = com.feedmine.app`, so it lands in V1's container (V2 Debug is
`com.feedmine.development` and would land in a container of its own).

V1's database was created by V1's own binary (its `v1_bookmarks … v11_user_operation`
migrations) and then seeded with `sqlite3` using V1's real DDL, restricted to the columns the
V2 reader selects (`Sources/FeedMinePersistence/LegacyUserStateReader.swift`). No table was
invented: the live schema was dumped with `.schema` before seeding. Note that the seeded
`bookmark_snapshot` uses V1's shipped columns (`title, url, source_title, source_url, excerpt,
media_url, authored_at, captured_at`); `docs/runtime-v2/adrs/ADR-004.md:174` describes an
older planned shape (`text_snapshot, media_ref, schema_version, authors`) that the shipped V1
migrations do not create, and the V2 importer never reads that table.

## Method

1. Created a clean simulator and booted it.
2. Built V1 from source, installed it, launched it, let it create
   `Library/Application Support/Feedmine/user.sqlite`, then terminated it.
3. Seeded that database: 3 personal sources (one `enabled = 0`), one non-default box with 2 items
   (`bookmark_list` + `bookmark_item` + `bookmark_snapshot`), one `source_collection` with 2 members.
   Inserted rows: `imported_source` 3, `bookmark_list` 2 (V1's own default `Favorites` + the new
   `Leituras longas`), `bookmark_item` 2, `bookmark_snapshot` 2, `source_collection` 1,
   `source_collection_member` 2.
4. Snapshot BEFORE: SHA-256 of every file V1 owns (`before.sha256`), and a byte copy of the
   directory.
5. Built V2 Release, installed it **over** the same bundle id (same app container), launched once,
   screenshot, and read the screen through the Simulator window's accessibility tree.
6. Snapshot AFTER (`after.sha256`), `diff.txt`, and the receipt/rows from
   `Application Support/FeedMine/runtime.sqlite` (`receipt.json`).
7. Launched a second time and compared the receipt and the row counts.

## The blocker this rehearsal found (same-directory layout)

The as-specified layout — V1's data at `Application Support/Feedmine`, V2's store at
`Application Support/FeedMine` — **cannot run on this host**, and the reason is measured, not
inferred:

- The host volume is case-insensitive: `stat` returns the same inode for `FeedMine` and
  `Feedmine`.
- The **app's own process is not**. Evaluated inside the running app with lldb
  (`case-collision-lldb.log`):
  `fileExists("…/Application Support/Feedmine/user.sqlite")` → **false**,
  `fileExists("…/Application Support/FeedMine/user.sqlite")` → **true**,
  `contentsOfDirectory("…/Application Support")` → `["FeedMine"]`.
- With the directory spelled `Feedmine`, V2 Release starts, writes **nothing**, and shows
  “Não foi possível carregar suas fontes.” (`AppComposition.swift:527`, the catch around the
  `RuntimeDatabase` construction): the store it is told to open is the case-variant that no
  longer resolves.
- Renaming the directory to `FeedMine` lets V2 start, but then
  `LegacyV1Upgrade.candidateUserStateURLs` first candidate (`…/Feedmine/user.sqlite`) is the
  case-variant that no longer resolves: the run reports **no legacy container** and writes no
  receipt.

Both directions were measured. On a case-sensitive device filesystem the two directories are
genuinely distinct and the design is unaffected; on this simulator they collide, so the
rehearsal was carried through V2's **second documented candidate**,
`Documents/user.sqlite` (V1's pre-1.0 location, `LegacyV1Upgrade.candidateUserStateURLs`).
The seeded `user.sqlite*` was moved there and the colliding `Application Support/Feedmine`
directory removed, before V2 was installed. Same app container, same bundle id, one launch.

## Result

First V2 launch, `reader_legacy_upgrade`:

| status | ran_at | boxes | sources | selected | collections | collection members |
|---|---|---|---|---|---|---|
| `completed` | 1792520884.351605 | 1 | 3 | 2 | 1 | 2 |

Skips recorded with the receipt: `savedArticles / notImportedInThisBuild / 2` (the two saved
articles stay in V1, as designed). `smartFeeds` and `curatedFeeds: 0` — V1 had none.

Imported per category (see `receipt.json`):

- **Sources** — 3 rows, canonical identity as key: `…/ciencia/feed.xml` (Ciência Hoje),
  `…/tecnologia/feed` (Tecnologia), `…/arquivo/feed` (Arquivo Desligado). Selection contains the
  two enabled ones only; the disabled one is preserved but not selected.
- **Boxes** — `saved` (V2's own default) + `v1:list:2` “Leituras longas”. V1's default box was
  not duplicated, as designed. `reader_bookmark_memberships` = 0: saved articles are not
  imported in this build and the receipt says so.
- **Collections** — `v1:collection:1` “Ciência e Tecnologia” with its 2 memberships, keyed by
  each source's V1 `source_identity` (not by its fetch URL).

Second launch: `ran_at` unchanged, every count unchanged, no row duplicated.

V1's files: `diff.txt` is empty and `diff` exits 0 — all seven files (including V1's own
`feedmine.sqlite` content cache and the WAL/SHM sidecars) are byte-identical before and after.
The V1 database is opened read-only and never rewritten, moved or deleted.

### Reader-facing notice

The notice is **not** presented. `notice_presented` was reset to 0 three times and flipped back
to 1 on every launch before the first screen was readable; the alert never appeared in the
accessibility tree (polled every 0.2 s, 12–15 s per launch) nor in any screenshot. The only
writer is `AppComposition.acknowledgeLegacyUpgradeNotice()`, reached from the alert binding's
`set(false)`: SwiftUI presents and tears the alert down in the same launch. The exact copy the
app would render for these counts, and the evidence for that claim, are in `notice.txt`.
This is a defect in the notice surface, not in the import.

## Files

| file | what |
|---|---|
| `before.sha256` / `after.sha256` | SHA-256 of every file in V1's data directory, before and after |
| `diff.txt` | `diff before.sha256 after.sha256` (empty, exit 0) |
| `receipt.json` | raw `sqlite3 -json` output: receipt, skips, counts, imported sources, boxes, collections, members, selection |
| `notice.txt` | what the reader saw, the exact notice copy, and why it was not visible |
| `screenshot.png` | V2 first screen after the upgrade |
| `v1-before.png` | V1 (built from source, seeded) before the upgrade |
| `case-collision-lldb.log` | raw lldb transcript proving the app cannot resolve the case-variant path |
| `commands.txt` | every command, in order, including the blocked same-directory attempt |

## What this does NOT prove

- **Not the shipped same-directory layout.** The upgrade was exercised through
  `Documents/user.sqlite`, because `Application Support/Feedmine` and
  `Application Support/FeedMine` collide on this host. The first candidate
  (`Application Support/Feedmine/user.sqlite`) was measured failing in both directions and is
  not proven to work anywhere.
- **Not any real user's V1 database.** One synthetic database, seeded to the shapes the reader
  selects. No user's library, no unusual schema, no corrupt file, no read-only/permission case,
  no oversized database.
- **Not a device, and not an iOS upgrade path.** Simulator only, iOS 26.5, no signing, no
  App Store install-over, no real-device filesystem, no upgrade from an earlier iOS.
- **Not data the importer declines.** Saved articles (skipped, count 2), smart feeds and curated
  feeds are reported, not imported; nothing here shows them surviving.
- **Not the notice.** It is not visible in this build (see above), so nothing here shows a
  reader reading it.
- **Not concurrency or interruption.** Exactly one launch sequence, one second launch, no
  kill during import, no repeated crash-restart, no partial write.
- **Not the other categories** the runtime owns (feed content, editions, media, session
  checkpoints); the rehearsal asserts nothing about them.
