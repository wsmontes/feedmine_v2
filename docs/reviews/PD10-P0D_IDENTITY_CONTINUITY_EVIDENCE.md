# PD10-P0D — Identity Continuity Evidence

Date: 2026-10-15. Gate branch: chatgpt/pd10-p0d-personal-identity-continuity.
Base: main at 9f93bc29ec734e2f12fe3641b63a118acf2126a9 (P0B integrated, native-green before P0D). Rebased single-parent commit; original P0D prototype ac08bfaaf7e51a6c713a4e32866745b6b5c43cfb is superseded.
Spec: docs/product/PD10-P0D_continuidade_identidade_pessoal_spec.md at 1dafd144.
**Execution status of this amended candidate: NOT_RUN.** The immediately preceding
candidate a17d27e71b6ae6f7c8ce33ab5af9fa746420d236 failed native `swift build`
at `LegacyCatalogImport.swift:68` and `ReaderDiscoveryPool.swift:130`: the function-value
reference to a two-parameter function cannot satisfy `compactMap`'s single-argument
closure even with a default argument. The amendment restores the original one-argument
`LegacyCatalogImport.entry(_:) -> LegacyCatalogEntry?` as the only function of that
name and adds `entryWithIdentityKey(_:identityKey:)` exclusively for explicit P0D
identity anchoring. The test invocation and app callers now use the distinct name.
No changes to `ReaderDiscoveryPool.swift`. A Mac rerun of build, tests and app suite
is required; none is claimed to pass on the amended candidate.
The code and fixtures below are implementation evidence, not a claimed PASS.

## Required implementation sequence

1. The destructive startup write was removed **first**, alongside a native regression in
   FeedMineApp/FeedMineApp/AppComposition.swift:220-233 and
   FeedMineApp/FeedMineAppTests/CompositionTests.swift:446.
   In particular, catalog availability no longer calls preferences.updateSources(...) and
   does not substitute unrelated starter feeds for missing persisted keys.
2. Only after preparing that fix and test was persistent identity justified: a former
   managed/imported source otherwise changes SourceID/TargetID/BindingID namespace on catalog
   removal; and two distinct canonical keys with verifiable continuity cannot be represented
   durably by a single unversioned source_keys value. One additive table is introduced
   (RuntimeMigrations.swift:548): reader_source_identity. No cache, timer, import pipeline,
   scheduler, sync worker, new database or retry mechanism was added.

## Authority boundaries

- Durable selection: reader_preferences.source_keys; never overwritten by catalog resolution.
- Historic operational owner/anchor: reader_source_identity, on the existing runtime.sqlite
  writer. The first resolved namespace is pinned idempotently (ReaderLibraryStore.swift:105).
- Explicit verified alias: VerifiedSourceAlias (ReaderLibraryStore.swift:27) compares *two local
  compiled catalog readers* with distinct increasing declared revisions, disappearance of the
  old key, arrival of the new key, unchanged exact fetch endpoint and media class, and
  uniqueness of that endpoint in both catalogs. Titles, host matches, apparent redirects and
  fuzzy URL similarity are **not** accepted as proof.
- The public manifest does not carry an alias map. There is deliberately **no automatic A→B
  inference or reconciliation triggered by catalog refresh**. Without verified evidence the
  old personal key survives unresolved. The explicit proof API is not a general claim that
  the public authority publishes verifiable aliases.
- Runtime representation: TrustedFeeds.swift:65 chooses at most one active feed per personal
  anchor and uses the originally established Source/Target/Binding ID namespace. A managed
  endpoint can change for future work; imported endpoint and title stay in the personal table.
- Historical occurrences, boxes, reading state, checkpoints and presets are not rewritten.
  Proven alias reconciliation updates only reader_source_identity and collection source
  memberships in one RuntimeDatabase.write transaction (ReaderLibraryStore.swift:122).
  Aliases remain directional/finite: existing anchor conflicts and reverse cycles are refused.
- OPML import matches an **already proven exact request endpoint**, never merely host/title,
  before reconciling a newly canonicalized import key (ReaderLibraryStore.swift:180).
  Selection and collection writes use the same personal anchor. Export prefers personal
  request_url, then verified request_url, then the old literal unaliased URL.

## D1–D10 audit

Status legend: NOT_RUN = test written/referenced but native result not yet available;
PARCIAL = a known requirement still lacks authoritative public alias proof or complete integration-test coverage.
No unexecuted test is labeled ATENDE.

| Contract | Status | Proof / discriminating assertion |
| --- | --- | --- |
| D1 — source selection durable | NOT_RUN on D1 amendment | AppComposition.swift:220 preserves missing startup keys; toggleSource uses incremental changeSources for the chosen source only. CompositionTests.testSavedKeysMissingFromCatalogRemainSelectedWithoutVersionBump checks startup; testPD10P0DDisablingAvailableSourceKeepsMissingSelectionThroughReopen additionally covers A/B/C → B unavailable → disable A → durable B/C, version +1 and reopen |
| D2 — verified canonical alias | PARCIAL | ReaderLibraryStore.swift:27 & :122, ReaderLibraryStoreTests.swift:275 and :359: A→B, exactly one anchor, missing evidence and ambiguous endpoints rejected; real public manifest supplies no alias claims |
| D3 — single durable relation | NOT_RUN | RuntimeMigrations.swift:548 one additive table; ReaderLibraryStore.swift:90/:105/:122 plus ReaderLibraryStoreTests.swift:275/359; source/anchor/current and fingerprint survive reopen |
| D4 — import + managed duplicate | PARCIAL | TrustedFeeds.swift:65; CompositionTests.swift:472 checks native imported/catalog identity, a single active source, stable Source/Target/Binding IDs without catalog. P0B activation now reconciled and covered by an unexecuted native test; full unresolved-choice UI coverage remains unmeasured |
| D5 — endpoint does not own identity | NOT_RUN | ReaderSourceIdentityTests.swift:103 proves same canonical key -> same Source/Target/Binding despite changed signed request URL, different key stays different |
| D6 — collections and selection | NOT_RUN | ReaderLibraryStore.swift:122/:529; ReaderLibraryStoreTests.swift:275 asserts same collection ID, one membership, original source selection and version |
| D7 — published/saved state untouchable | NOT_RUN | ReaderLibraryStoreTests.swift:275/:387 compare actual published row values, bookmarked card IDs and original card record before/after success and aborted transaction |
| D8 — atomic and idempotent | NOT_RUN | ReaderLibraryStore.swift:122; ReaderLibraryStoreTests.swift:275/:387 verifies second run false and a failing DELETE trigger rolls back both link writes and memberships |
| D9 — offline reopen | PARCIAL | ReaderLibraryStoreTests.swift:275 reopens the *same disk database* with links, membership, saved card and selection; CompositionTests.swift:472 tests catalog-less resolution with imported endpoint. Live installed revision activation now has a native fixture test (NOT_RUN); rollback and post-install offline cold reopen remain unmeasured |
| D10 — OPML round-trip | PARCIAL | ReaderLibraryStore.swift:180/:370; ReaderLibraryStoreTests.swift:275 imports twice with B and OPML-derived alternate key but retains one source; ReaderImportExportCoordinator.swift entries prefers persisted personal/verified endpoint; existing ReaderImportExportCoordinatorTests.testExportingOPMLRoundTripsThroughTheImporter checks normal export/import. End-to-end alias OPML export/re-import remains unmeasured on native Mac |

## Deterministic P1–P16 proof inventory

All fixtures are local; ReaderLibraryStoreTests.identityCatalog builds two independent SQLite
catalog readers declaring revisions 5 and 6 (and negative revision 4 / reverse revision 7).
The catalog tables and metadata are authored by the test. **No public HTTP is used.**

| Case | Test / assertion | State |
| --- | --- | --- |
| P1 | CompositionTests.testSavedKeysMissingFromCatalogRemainSelectedWithoutVersionBump — exact source_keys, version | NOT_RUN |
| P2 | ReaderLibraryStoreTests.testPD10P0DAliasAcrossTwoCompiledRevisionsKeepsPersonalStateAndReopens — A→B, pinned A | NOT_RUN |
| P3 | ReaderLibraryStoreTests.testPD10P0DUnprovenAmbiguousAndConflictingAliasesFailClosed — mismatched fetch endpoint | NOT_RUN |
| P4 | same — B/C share endpoint => refused | NOT_RUN |
| P5 | same — preexisting independent B and reverse cycle refused | NOT_RUN |
| P6 | CompositionTests.testPD10P0DImportedManagedIdentityRemainsSingleAndAvailableOffline — one active ID | NOT_RUN |
| P7 | same — no catalog, imported request endpoint and old managed IDs | NOT_RUN |
| P8 | ReaderSourceIdentityTests.testPD10P0DEndpointChangesCannotChangeManagedSourceIdentity | NOT_RUN |
| P9 | ReaderLibraryStoreTests.testPD10P0DAliasAcrossTwoCompiledRevisionsKeepsPersonalStateAndReopens — collection old key and same ID | NOT_RUN |
| P10 | same — published row and saved card values unchanged | NOT_RUN |
| P11 | ReaderLibraryStoreTests.testPD10P0DRollbackOnMembershipErrorKeepsAliasesAndCardsUnchanged — abort after insert | NOT_RUN |
| P12 | first alias test — second reconciliation false, repeated imports no new rows | NOT_RUN |
| P13 | first alias test — reopen the same disk SQLite; native composition overlap test — relaunch | NOT_RUN |
| P14 | first alias test — import B twice and OPML-canonicalized identity against verified endpoint | NOT_RUN |
| P15 | ReaderImportExportCoordinatorTests.testExportingOPMLRoundTripsThroughTheImporter + first alias test — signed endpoint preserved; combined native end-to-end alias export not yet tested | PARCIAL |
| P16 | Persistence snapshot comparison and CompositionTests.testPD10P0DLiveCatalogActivationPreservesPersonalIdentity (P0B live activation retains published state and new association identity) | NOT_RUN |

## Integration reconciliation: P0B merged in main 9f93bc29

P0B's mutable `catalogueSnapshot` and computed `catalogueURL`, verified activation, foreground
nonblocking sync, source search fingerprint fence, discovery fingerprint pools and snapshot-specific
new association remain intact. PD10-P0D fixes the still-destructive startup
`preferences.updateSources(resolved.map(...))` first, replacing the retired acceptance assertion
with a durable-selection regression. An unavailable source never becomes an unrelated starter feed;
nor does `adoptSelectionChange` resurrect selectedFeeds after an explicit removal.

Only then, one additive `reader_source_identity` table supplies stable historic ID authority.
`adoptActivatedCatalogue` preserves P0B's snapshot installation and existing association, but
resolves *future* selected feeds with persisted identity links, pins newly established owners and
logs any resolution failure without deleting durable reader preferences or rolling back the
verified catalog. `collectionFeeds`, source management lookup and explicit toggle also respect
the same source identity; the already running association and displayed publication are untouched.

The new `testPD10P0DLiveCatalogActivationPreservesPersonalIdentity` exercises the P0B
standard-public-URL revision-5→6 fixture: a source both managed and imported disappears from
the managed revision; the current presentation remains unchanged, the later rebuilt association
retains SourceID/TargetID/BindingID and uses the imported endpoint, preferences and selection
version remain unchanged. Its native status is NOT_RUN pending the Mac executor.

No changes to P0B-owned protected `ReaderPreferencesStore.swift`,
`SourceManagementCoordinator.swift`, installation/updater, discovery worker, source-management UI,
runway, acquisition or published history. The 9f93bc29 P0B baseline tests were reported green by
the architect; this implementation does not claim the rebased branch passed them.

## Native build diagnostic and allowlisted amendment

The native executor reported a genuine Swift type error, not a disk failure, for the
original P0D prototype's two-argument function reference. Specifically:
`LegacyCatalogImport.entries(...)` uses `page.compactMap(entry)` and the unchanged
`ReaderDiscoveryPool.swift` uses `.compactMap(LegacyCatalogImport.entry)`.
Both require the original one-argument function value. A defaulted second argument
does not satisfy that type. The corrective amendment keeps exactly one `entry`
function, with one argument; identity-aware callers invoke the differently named
`entryWithIdentityKey`. No overloads and no changes outside the spec allowlist.
The only native evidence so far is build failure on the **superseded** SHA
`a17d27e7`; all acceptance statuses for the replacement remain NOT_RUN.

## Mac native evidence on superseded candidate af770ff6

The Mac executor supplied results for commit `af770ff63cd02807384126f57cd1c9bc1a3c510d`
(tree `1000fd21`). `swift build` completed successfully (81.18 s). Targeted
package filters passed: ReaderLibraryStoreTests 12/0, ReaderSourceIdentityTests
6/0, ReaderImportExportCoordinatorTests 6/0, RuntimeMigrationTests 2/0.
The full `swift test` executed 1,357 tests with one skipped and **four assertion
failures in three tests**, all exact migration/schema snapshots, not feed-behavior failures:

- `AvailabilityPrecedenceTests.swift:74`: final migration identifier still expected
  `content-fingerprint-generation-v2`, but the new final identifier is
  `reader-source-identity-v1`.
- `PublicationRunwayStoreTests.swift:244`: exact applied migration list lacked
  the final `reader-source-identity-v1`.
- `PublicationRunwayStoreTests.swift:435,438`: both exact schema differences lacked
  three *declared* additions: `reader_source_identity` table, its implicit TEXT-PK
  `sqlite_autoindex_reader_source_identity_1`, and
  `reader_source_identity_current` index.

The architect authorized changes limited to these **four assertions** in the two
test files outside the original allowlist. This amendment updates only their expected
values and adds the precise CREATE TABLE/INDEX definitions to the two existing exact
set comparisons. It does not replace equality with subset/contains, alter any other
assertion, change production schema, or touch bench/protected files.

**New amended candidate: native status NOT_RUN.** No test PASS is inferred from
the superseded candidate. App suite results were pending when this amendment was made.

## D1 semantic acceptance correction (architect-authorized)

The architect withheld acceptance on `0ced0444` despite 62 green native app
tests: they had not covered the reader's incremental removal of an available
source while another persisted source was temporarily unavailable.
`AppComposition.toggleSource` previously rebuilt the entire persisted selection
from `selectedFeeds`, which contains only resolved sources. That meant the
A/B/C → B unavailable → disable A sequence stored only C instead of B,C.
The corrected path uses the existing `ReaderPreferencesStore.changeSources`
(one transactional operation) with just the toggled key, retaining other persisted
keys and incrementing the selection version exactly once. No new cache,
scheduler, fallback or other selection path was changed.

`CompositionTests.testPD10P0DDisablingAvailableSourceKeepsMissingSelectionThroughReopen`
starts with three selectable sources, removes B from the supplied operational
authority after persistence, checks retained A/B/C and unchanged version,
disables A through the real composition, checks durable B/C and version +1,
and reopens with B still unavailable to check persistence again.

By express authorization, `AvailabilityPrecedenceTests.swift:74` no longer asserts
an incidental final migration identifier. Its behavioral backfill assertions
remain; both exact schema drift sets and the exact migration history list in
`PublicationRunwayStoreTests.swift` are **unchanged**. The debug-only
`FEEDMINE_EMPTY_SELECTION` absolute-replacement evidence path is untouched.

**Amended candidate D1 status: NOT_RUN** (`swift build`, `swift test`,
targeted D1 native regression, and full `CompositionTests` require Mac
verification). The 62 green tests on the previous SHA cannot establish D1.

## Rebase verification

Parent/base must be exactly `9f93bc29ec734e2f12fe3641b63a118acf2126a9`.
The delta touches the original eleven §4-allowlisted files plus the two specifically
authorized migration/schema-test files (thirteen total). The eight nonconflicting
production/test paths are reused verbatim from the isolated P0D prototype; AppComposition
and CompositionTests are hand-reconciled with P0B rather than copied over its changes.
No bench/ or protected file is modified. Compare the resulting branch to the base, not
the obsolete `bb8a94f8` prototype base.

## Deviations / limitations

- The manifest publishes no authoritative alias evidence. The explicit proof entrypoint
  works with two locally revisioned compiled readers, not an automatic verified installation
  ledger or signed public alias declaration. This is a deliberate *fail-closed* limitation,
  not a claim that all historic key changes are automatically recovered.
- The runtime sqlite authority can pin identities once the source has been resolved. A key
  never previously resolved/pinned and absent from both catalog and imported library remains
  unresolved, rather than being assigned a speculative namespace.
- Native source-management UI from integrated P0B is outside the allowlist. AppComposition
  search results now resolve against established personal identities, but full acceptance coverage
  of unresolved selections in the UI is still unmeasured.
- The local test SQLite catalogs reproduce the compiled schema and revision metadata; they are
  deterministic fixtures, **not** a test of public manifest signature/hash installation.
- No native build or test was executed here. Only textual/connector-side review was possible.

## Validation requested from Mac executor

After the single branch commit, record HEAD SHA, tree SHA, workspace/disk availability,
exit codes, cases executed, skipped and failures. Run serially:

- git diff --check 9f93bc29..HEAD
- swift build
- swift test --filter ReaderLibraryStoreTests
- swift test --filter ReaderSourceIdentityTests
- swift test --filter ReaderImportExportCoordinatorTests
- swift test --filter RuntimeMigrationTests
- swift test (whole package)
- xcodebuild app/test scheme targeting FeedMineAppTests/CompositionTests with the same simulator
  and local fixtures, including the three PD10-P0D native cases and P0B activation regressions
- Regressions covering publication, cold restore and P0B on this rebased branch

Do not declare PASS from compilation alone. Stop after publishing the isolated branch;
independent native review of the rebased P0B/P0D composition precedes integration.
