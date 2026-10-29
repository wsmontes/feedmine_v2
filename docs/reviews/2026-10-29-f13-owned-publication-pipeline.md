# F13 — owned publication pipeline — 2026-10-29

Base `fdbd4c10`. PublicationCoordinator and initial/local Runtime requests now carry the captured ownership expectation through preparation into all four guarded writer paths. Retired ownership propagates as staleHistoryBinding without retry or activation reacquisition. **Semantic PublicationHistory/FeedSession restoration and native owner/root injection remain pending; R4 host remains FAIL.** No expected failures removed.

First publication carries the complete BindingPublicationExpectation; append carries BindingActivation. Existing default-nil unbound callers remain compatible; active bound ownership is still enforced by the writer. Tests exercise positive and stale first/initial/append/tail paths, plus real production initial+append and context changes inside preparation. Previous frozen cards/owned positions remain unchanged after rejection; the newer empty reader retains its activation.

## Verification

- RED: absent transport fields/initializer arguments, exit 1, no capacity interruption.
- Focused coordinator/production GREEN: **28 tests, zero failures**.
- First full package run: **1813 tests, one skipped, three assertion failures**, exit 1. Two PublicationRunwayStore tests explicitly listed the old schema/migration history and had not been updated for the two history migrations. Their preserved-data/behavior checks passed.
- Updated only the explicit migration list and exact additive schema set: four literal tables and six autoindexes. Kept exact equality, prior object definitions, indexes and row-preservation checks; did not filter out new objects or derive expected definitions from the migrated database.
- Schema/coordinator/production verification: **40 tests, zero failures**.
- Final **complete macOS Debug Swift package suite: 1813 tests, one skipped, zero failures**, exit 0, no capacity interruption; 109.132 seconds reported by XCTest. The skipped reference-catalogue comparison requires FEEDMINE_REFERENCE_FEEDS_ROOT and FEEDMINE_REFERENCE_CATALOG and remains unproven. Counts overlap; do not add them.
- Independent review found no actionable transport issue and confirmed the schema-oracle literals/autoindices match the migrations without weakening earlier assertions.
- `git diff --check` passed. No actual iOS/native host or benchmark acceptance claim.

Optional integration coverage still includes nil metadata rejection through these wrappers while bound, and explicit non-nil expectedActiveEditionID transport. The backend has direct nil-bypass/rollover tests; native revision/gesture tests remain required. This checkpoint is not a complete bound FeedSession: its history boundary must carry the same activation before native injection.

Evidence: r4-owned-pipeline-* under docs/reviews/evidence/2026-10-27-source-exclusions. Exact commands/results/capacity observations, byte-verified gzip logs and final code/test-executable hashes are retained. The original failing full run remains marked failed. Functional tests use -gnone, one job and a monitored 300 MiB reserve; iOS 700 MiB and benchmark 3 GiB guards are unchanged. Capacity recovered externally; no data/product cleanup was performed by this slice.

The preceding P2 clearing bug was corrected in fdbd4c10 and independently confirmed resolved (see 2026-10-29-f13-checkpoint-clear-rollover.md). Next: owned semantic restoration/save, cold/live binding injection, native logical/history wiring, ambiguity recovery and real R4/relaunch/UI/F13 acceptance.
