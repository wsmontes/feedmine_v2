# F13 — logical ownership of frozen history — 2026-10-28

Base `23b74bb0`. Additive binding/adoption primitives now preserve the distinction between a raw logical context and an old frozen publication key. **Publication attachment/checkpoint restoration/native injection are not wired yet; R4 remains FAIL in the host.** No expected failure was removed.

The migration adds reader_history_bindings and reader_history_editions without updating old Edition, card, segment, save or checkpoint rows. A unique Edition owner and unique stable runtime namespace prevent two explicit contexts from borrowing the same reading history. A composite foreign key requires the active Edition to belong to that binding.

Exact adoption requires matching raw/frozen criteria. Legacy word adoption rebuilds the frozen key forward from known raw criteria and a current effective-word snapshot, checking the actual Edition and durable policy inside the same transaction. It never subtracts present-day global words from historical keys to infer their origin. Incompatible, stale, missing or already-owned candidates roll back. Established ownership/provenance remains idempotent after later global settings changes; it is no longer a policy inference. Candidate selection/compatibility checks and the ambiguity recovery UI remain future caller responsibilities.

Fresh contexts normally retain their canonical namespace. If an old adopted union already owns that namespace, a fresh distinct context gets a persisted discriminator and no active Edition. A legacy adoption cannot silently change an already-established namespace or active Edition. This conservative conflict is surfaced to the future resolver/recovery flow rather than merging history.

## Verification

- RED: missing planned store APIs, exit 1, no capacity interruption.
- Initial focused implementation: five tests passed.
- Strengthened focused run: **six tests, zero failures**, exit 0, no interruption.
- Compatibility run: **43 tests, zero failures**, exit 0, no interruption. Includes binding tests plus migration reopen/failure, populated-database rebuild, publication/checkpoint and source/word-guard suites. It uses the final rebuilt executable with --skip-build. Counts overlap and must not be added.
- Independent review found no actionable correctness issues. The suggested established-adoption replay, direct cross-owner FK rejection, separate Edition/namespace collision and active-replacement rejection are all covered in the strengthened tests.
- `git diff --check` passed. Not a whole-package or iOS/native acceptance claim.

Assertions retain frozen Edition/CardRecords/segments, bookmark, active and scoped checkpoint values; check provenance bytes after a settings change; verify rollback leaves no binding on failed claims; reopen a fresh binding through another connection; and prove SQL itself rejects a cross-owner active pointer. Existing populated migration/rebuild tests pass, including their integrity/foreign-key preservation checks.

Exact commands/results/capacity observations are in r4-history-binding-*.json. Verified gzip logs and final code/executable hashes are recorded in r4-history-binding-provenance.json. These macOS Debug tests use -gnone, one job and the 300 MiB monitored reserve. No data/products were deleted in this slice. The 3 GiB benchmark and 700 MiB iOS guards remain unchanged; the current free capacity is below the iOS guard, so no iOS build was launched.

Next: bind first publication atomically, update owned checkpoints, restore by owned Edition and explicit binding activation. Then native root identity/injection and legacy ambiguity recovery, actual iOS continuity and remaining F13 journeys/gates. Unrelated capacity-ready.json remains untouched.
