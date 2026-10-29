# F13 — legacy history inventory before native activation

Previous goal turn: progress (589f3470 fixed and published explicit legacy checkpoint adoption). This turn inspected the current native root and NF03 replacement flow. The previous association remains displayed while a candidate launches, and its checkpoint is saved before installation. Blindly activating a new binding in the constructor would retire that previous writer too soon. Native activation/handoff must therefore consume history evidence before changing authority.

## Implemented

ReaderHistoryBindingStore.legacyCandidates is a read-only inventory, under one GRDB read snapshot. It validates the supplied raw contextual exclusions and current effective-word snapshot, then returns all unowned Editions whose full key matches the raw context or its known current forward union. It never subtracts historical words or selects the newest Edition. Multiple Editions remain multiple. Frozen metadata is decoded and verified against its indexed identity projection.

Each candidate retains every distinct known original checkpoint statement. The active singleton precedes deterministic context-row order; equal statements are deduplicated with active evidence preserved. Card identity resolves the actual live/retired Edition; unknown cards retain the declared Edition. A wrongly projected context row is still inspected and assigned by its durable card, without editing the original statement. Existing owned Editions are excluded, including those belonging to another logical context. No binding, checkpoint, token or Edition is mutated.

The host must still decide compatibility and explicit ambiguity recovery, resolve ownership with the existing transactional adoption API, and coordinate authority cutover. This API is not yet consumed by AppComposition. Global-word native behavior and R4 remain unchanged/FAIL; no expected failure removed.

## Verification

Final affected suite: **32 tests, zero failures, exit 0**, no disk-budget interruption. Evidence: evidence/2026-10-27-source-exclusions/r4-legacy-inventory-*. The initial RED lacked the inventory API. The first implementation exposed a precedence error combining optional singleton and retained arrays; the distinct-statement assertion reproduced it and parentheses corrected it. The final tests cover exact/forward candidates, multiple Editions, retained-only positions, duplicate evidence, wrong Edition and context projection, archived/unknown anchors, owned exclusions, unexplained frozen words, stale policy, and unchanged authority/checkpoints. Existing adoption/checkpoint/PublicationHistory/FeedSession tests ran alongside them.

Independent read-only review covered correctness, ownership and final test coverage. No remaining actionable finding. The reviewer requested archive and separate retained-candidate tests, which were added. Query cost scales with the number of retained contexts and candidate Editions; native warm-launch acceptance remains required before claiming host performance.

The last full-package execution was **1829 tests, one skipped, zero failures at parent 589f3470**. It was not rerun for this opt-in read-only query; current evidence is the affected 32-test execution. Native iOS, UI/relaunch and benchmarks were not run in this slice.

## Remaining work

Native logical/publication key separation, binding selection/activation with NF03 failure recovery, collision-isolated runtime/discovery namespace, current word-policy injection, ambiguity menu/empty-reader recovery, and actual R4/relaunch/pt-en large-text stable-tail proof remain pending. B02/B04/B05 open, B03 FAIL, B06 NOT_RUN remain unchanged. The objective stays active; this checkpoint does not narrow completion to the inventory.
