# FeedMine V2 — evidence for the TestFlight milestone (2026-10-09)

Executed on this machine; every number below comes from a command run in this session, not from
earlier reports. Machine: macOS 26.3, arm64, Xcode 26.6 (17F113), Swift 6.3.3, iPhone 16 simulator
with iOS 26.5.

## 1. Baseline when packaging started

| Check | Command | Result |
|---|---|---|
| Package build | `swift build` | PASS |
| Package tests | `swift test` | **831 tests / 0 failures** (19,6 s) |
| iOS app build | `xcodebuild -scheme FeedMine -sdk iphonesimulator build` | exit 0 |
| iOS app tests | `xcodebuild test` | **16 integration + 3 XCUI / 0 failures** |
| Repository | `origin/main` | `1fd3d3b`, local == origin |

## 2. What blocked a distribution build

| Gap | Evidence |
|---|---|
| Bundle identifier `com.feedmine.development` | `project.pbxproj` build settings |
| No app icon: no asset catalog in the project | `find FeedMineApp -name '*.xcassets'` → nothing |
| No privacy manifest | no `PrivacyInfo.xcprivacy` in the app target |
| No git pairing in the binary | no shell-script phase, no `FeedmineGitSHA` |
| No export/upload configuration | no `ExportOptions.plist`, no release script |

Required-reason APIs the app actually calls: `FileTimestamp` (`MediaHousekeeping` reads
`contentModificationDate`), `DiskSpace` (`volumeAvailableCapacityForImportantUsage` decides media
admission, concurrency and cleanup), `SystemBootTime` (`ProcessInfo.systemUptime`, 16 call sites).
No `UserDefaults`.

## 3. Packaging delivered (commit `f97c467`, extended by `0c53fac`)

- `FeedMineApp/FeedMineApp/Assets.xcassets/AppIcon.appiconset` — the product icon reused from the V1
  app, plus iPad 152×152 and 167×167 generated from the 1024 marketing PNG (which has no alpha).
- `FeedMineApp/FeedMineApp/PrivacyInfo.xcprivacy` — FileTimestamp `C617.1`, DiskSpace `E174.1`,
  SystemBootTime `35F9.1`; no collected data, no tracking.
- Release: `PRODUCT_BUNDLE_IDENTIFIER = com.feedmine.app` (existing App Store Connect record
  "Feedmine", ID 6793279758, SKU feedmine-ios-2026), `DEVELOPMENT_TEAM = 955573A4YH`,
  `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. Debug keeps `com.feedmine.development`.
- `ITSAppUsesNonExemptEncryption = false` (HTTPS only). `CFBundleVersion` 22 then 23.
- `scripts/generate_build_info.sh` runs as the app target's last build phase and writes
  `FeedmineGitSHA` / `FeedmineGitBranch` / `FeedmineBuildDate` into the built `Info.plist`.
- `scripts/release-testflight.sh`: refuses a dirty tree, a missing catalog or a missing API key;
  archives Release for `generic/platform=iOS`; aborts when the archived SHA differs from `HEAD` or
  the bundle id is not `com.feedmine.app`; uploads with the App Store Connect key; creates the local
  annotated tag `ios/<version>-build.<build>-<sha>` (never pushes it).
- `scripts/ExportOptions.plist`: `app-store-connect`, `destination: upload`, team `955573A4YH`.

## 4. Build 22 — pipeline validation

First attempt was rejected by App Store Connect:

> Invalid bundle. The "UIInterfaceOrientationPortrait, UIInterfaceOrientationLandscapeLeft,
> UIInterfaceOrientationLandscapeRight" orientations were provided for the
> UISupportedInterfaceOrientations Info.plist key in the com.feedmine.app bundle, but you need to
> include all of the "UIInterfaceOrientationPortrait, UIInterfaceOrientationPortraitUpsideDown,
> UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight" orientations to support
> iPad multitasking.

`TARGETED_DEVICE_FAMILY` is `1,2`, so the iPad rule applies. Commit `0c53fac` adds
`UIInterfaceOrientationPortraitUpsideDown`. Final run:

```
archived: bundle=com.feedmine.app version=1.0 build=22 sha=0c53fac
PAIRING OK: TestFlight build 1.0 (22) = 0c53fac85a4ff1ca9646aa774258b591b9c890dc
Uploaded FeedMine
tag ios/1.0-build.22-0c53fac created (local, not pushed)
```

App Store Connect (build `1e22539a-4fe1-4a76-b800-a04a798ed4af`): `processingState = VALID`,
`expired = false`, `minOsVersion = 18.0`, `internalBuildState = IN_BETA_TESTING`
(`externalBuildState = READY_FOR_BETA_SUBMISSION`, i.e. external testers also need Apple's beta
app review).

Archive verified before upload: icon (`Assets.car`, `AppIcon60x60@2x.png`,
`AppIcon76x76@2x~ipad.png`), `PrivacyInfo.xcprivacy`, `GRDB_GRDB.bundle/PrivacyInfo.xcprivacy`,
`catalog.sqlite` (117 940 224 bytes), `FeedmineGitSHA`, signed with `TeamIdentifier = 955573A4YH`.
The Release binary contains zero occurrences of `FEEDMINE_USE_DEVELOPMENT_FEEDS`, so no Debug-only
configuration survived into the archive.

## 5. D1 — selected-source acquisition coverage

Defect reproduced at the packaging base (fresh namespace, bundled catalog, four starter-set sources,
no gesture for ~6 minutes): 1 Edition, 2 segments, 26 published cards all attributed "BBC News",
64 origins, and only **2 of 4** acquisition targets with a checkpoint. NPR and Guardian had
`checkpoint_revision = 0` and no blob, while both endpoints answered (NPR 200; Guardian 301 → 200).
Cause: `AcquisitionPlanner` walks eligible targets in registration order and stops at
`targetWorkCapacity` (2); the first two satisfied `reserveCards = 16`, so a healthy runway produced
no further demand and the rotation never advanced. The defect was one of coverage, not retry.

Fix: branch `codex/fix-d1-selected-source-coverage` (commits `2dfb5f4`, `5b3c17e`), implemented by
Codex against the spec the ChatGPT architect wrote after that reproduction, then verified here.
Coverage is modelled as an explicit demand without claiming local exhaustion; the coordinator keeps
transient settled-target facts (including empty/304/failure, which checkpoints cannot represent);
the existing planner/coordinator/drain are reused. Architecture recorded in
`docs/architecture/CONTINUOUS_FEED_RUNWAY_DESIGN.md`.

Verification of the gate, all executed:

| Check | Result |
|---|---|
| Scope | 8 files, all inside the spec's allowlist; `Package.swift`, `Package.resolved`, `project.pbxproj`, `RuntimeMigrations.swift` → 0 diff lines |
| `git diff --check` | clean |
| Tests removed | none; 11 new tests named for proofs P1–P8 |
| Codex RED evidence | `red.txt` (BASE: 3 failures, "2" ≠ "4"), `proofs-green.txt` (11/0), `red-pd4-base.txt` (separate BASE checkout, same RED with the production `recencyAlternatingSources` policy) |
| Static | no Timer/sleep/scheduler/poll/retry added in production code |
| Package suite | **842 tests / 0 failures** (BASE 831, +11) |
| iOS suite on the branch | 16 integration + 3 XCUI / 0 failures |
| Package + iOS suites on integrated main | 842/0 and 19/0 |

End-to-end, production path, reader idle (~4 min), no gesture: **all 4 targets** checkpointed,
origins 64 → 106, memberships per source 32/32/32/10 — NPR and Guardian admitted canonical supply.
Published cards stayed 26 and all "BBC News", which matches the contract the architect fixed:
coverage is not publication, and the reserve was already satisfied.
Evidence: `~/Documents/feedmine-evidence/2026-10-09/testflight/d1-before-*` (before) and
`~/Documents/feedmine-evidence/2026-10-09/d1/` (Codex RED/GREEN).

Real feed advance (real swipes on the simulator, current code): 9 segments, **112 published cards**,
112 distinct origins (no duplicate occurrence per Edition), 4 distinct source IDs used, and
**0 PD-4 adjacency violations**. Attribution: BBC News 66, "World news | The Guardian" 36,
"NPR Topics: News" 10. So the coverage fix has a visible product effect as soon as the reader moves,
and the screen shows a Guardian card.

## 6. Build 23 — first product candidate

`CHATGPT: BINDING: APPROVED — FF main ← 5b3c17e, provided main remains at the agreed BASE`
(main was `0c53fac` at that moment, so the condition held). Integrated by fast-forward, then
`CFBundleVersion` 22 → 23 (`e7d56d0`) and `.gitignore` for the local `.superpowers/` agent workspace
(`a283953`, which the release script correctly refused as dirty before that).

```
archived: bundle=com.feedmine.app version=1.0 build=23 sha=a283953
PAIRING OK: TestFlight build 1.0 (23) = a2839539155ead9a333439b9bac320c63bd4014c
Uploaded FeedMine
tag ios/1.0-build.23-a283953 created (local, not pushed)
```

Both tags are local by design; the commits are on `origin/main`.

## 7. Open after this milestone

- F11–F14 (decode/CPU/memory/energy on hardware) remain **unexecuted**: `xcrun devicectl list
  devices` reports the iPhone 14 Plus and iPhone 15 as unavailable. Unexecuted is not failed.
- The architect recorded a non-blocking scalability caveat for public release: `targetWorkCapacity`
  bounds each plan, not the number of plans one `drive()` may run, so with hundreds of selected
  sources a single activation could keep acquiring. Fine at the four-source starter set; needs an
  adaptive operational budget before wide source selection ships.
- The two BBC catalog entries share the frozen display name "BBC News", so even correct PD-4
  alternation can look like a single newsroom. Separate presentation question.
- External TestFlight testers additionally need Apple's beta app review.
- User directive for the next increment: reuse as much of the V1 app's interface/UX solutions as
  possible, where each is genuinely the best solution, while keeping V2's rule that SwiftUI renders
  local projections only.

## 8. Update over V1 — integrity gate, verified

The architect asked for this before distributing V2 as an update to existing users, because V1 and V2
share the bundle identifier `com.feedmine.app`.

**Verified by code, and encoded as a test** (`testUpdateOverV1NeverSharesTheRuntimeStore`):

| | Store path (relative to the app's Application Support) | Owner |
|---|---|---|
| V1 (`feedmine-dev`) | `Feedmine/RuntimeV2/runtime-v2.sqlite` (+ `shadow/`, legacy `user.sqlite` and `feedmine.sqlite`) | `Packages/FeedRuntimeV2/Sources/FeedStorage/RuntimeDatabase.swift` |
| V2 | `FeedMine/runtime.sqlite` | `Sources/FeedMinePersistence/RuntimeDatabase.swift` |

The directory names differ (`Feedmine` vs `FeedMine`) **and** the depth differs, so the two files
cannot coincide even on a case-insensitive volume. V2 therefore never opens, and never migrates in
place, a database written by V1.

**Consequence, stated plainly:** installing V2 over V1 leaves V1's files on disk untouched, but V2
does not read them. The V1 library — chosen sources, bookmarks, reading history — is not carried
over; V2 starts from its bundled catalogue and the starter set. The V1 app has never shipped from the
App Store (its 1.0 sits in `PREPARE_FOR_SUBMISSION`), so today's exposure is limited to testers who
installed V1's TestFlight builds of the same record.

**Decision needed (not taken here):** either accept a clean start for the first V2 release and say so
in the TestFlight notes, or build an importer that reads V1's `runtime-v2.sqlite` and legacy
`user.sqlite` and seeds V2's runtime. The importer is a real migration project (foreign schema, two
legacy stores), so it is not part of U1–U4; it needs an explicit decision because it changes what
existing testers keep.
