# F13 — owned semantic history, 2026-10-29

This checkpoint connects binding-owned semantic history to PublicationHistory, FeedSession and the cold/live publication owners. Captured activations fence restore, window reads, cursor saves and seen milestones; retired handles cannot regain authority after A→B→A. Context reads accept the logical identity or the active frozen publication identity without borrowing another history.

Activation repairs a mismatched Edition column only when the durable card belongs to another Edition already owned by the same binding. Other-owned and unowned cards reject atomically. Archived/unknown anchors retain the original statement, date and offset; neighbour fallback does not attach that offset to another card. The additive reader-history-active-position-v1 migration records active presence separately, preserving the legacy card foreign key and distinguishing an explicit clear from retained history.

ColdFeedBootstrap forwards opaque Runtime ownership metadata; FeedRunwayDriver forwards its supplied activation without recapturing it. Default nil callers retain legacy behavior. Native AppComposition selection/injection and ambiguous legacy adoption remain pending.

Independent read-only reviews covered ownership semantics, activation rollback, migration/presence, schema fixtures, owner transport and the final Runtime boundary. No actionable findings remained. The static bootstrap boundary test was preserved.

## Validation ledger

Evidence lives in evidence/2026-10-27-source-exclusions/r4-owned-history-*. Original RED/failed attempts remain preserved. Initial failures exposed missing APIs, fixture mistakes, the archived-anchor foreign-key limitation, an old-schema fixture decoder and the direct Persistence type at the bootstrap boundary. Fixes preserve exact schema inventories and the static architecture assertion.

Final focused runtime-boundary run: 145 tests, zero failures, exit 0. Full-package result is recorded below after terminal verification. Neither package validation nor reviewer approval certifies native R4.

R4 remains FAIL in the native host. Relaunch/UI/gesture acceptance and remaining F13 gates are pending. B02/B04/B05 remain open, B03 FAIL and B06 NOT_RUN. No native expected failure was removed. The PR remains draft; unrelated capacity-ready.json is excluded.

Final full package: **1824 tests, one skipped, zero failures**, exit 0, no disk-budget interruption. The skipped catalogue comparison requires FEEDMINE_REFERENCE_FEEDS_ROOT and FEEDMINE_REFERENCE_CATALOG. Full run used the focused run’s rebuilt executable.
