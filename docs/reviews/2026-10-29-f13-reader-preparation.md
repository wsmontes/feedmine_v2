# F13 — prepare/publish before native reader-authority cutover

Previous goal turn: progress (native logical identity and strict word-policy wiring, b1d248bf/8d385a95). Current work inspected the actual NF03 transition and its tests: the old association remains live/writable while the replacement prepares and launches. Moving the old checkpoint before acquisition, or activating the new binding in the constructor, would change that contract.

## Implemented authority boundary

The existing SessionStore authority now supports a selected hidden preparation, with a per-binding retained candidate. Its captured handle permits publication and semantic projection of that candidate, while the current reader keeps its own activation and remains the only owner allowed to save/clear a viewport or directly mark seen. There is still one displayed reader. PublicationHistory suppresses the hidden projection’s seen event after validating its scope; direct store markSeen remains current-only.

The additive reader-history-preparation-v1 table records the candidate Edition/presence/token, the target binding’s base Edition, selected bit and predecessor activation. A unique partial index permits one selected preparation. Composite FKs constrain both candidate/base Editions to the same binding. Existing schema/data/indices remain checked by exact migration inventories; no FK is disabled in production.

Initial publication and append accept the selected prepared handle through existing transport/writers. A hidden first checkpoint is stored only in owned history. A prepared Edition pointer remains separate from the binding’s active pointer, including same-binding rollover. No active singleton or current position is overwritten. Atomic promotion verifies selected token, predecessor token and base Edition, retains the current reader’s latest point, switches Edition/presence/physical live-card checkpoint, and makes that same captured handle current. Archived/unknown statements stay representable in owned history.

Cancellation/supersession revoke preparation authority but retain its explicit candidate for retry. A consumed preparation cannot rewind a later active rollover. Immediate legacy/context/binding activation revokes selected preparation authority. Explicit reset/retarget returns a new handle/token; older handles do not revive after A→empty→A. Background work never reacquires authority.

## Evidence

Evidence prefix: evidence/2026-10-27-source-exclusions/r4-reader-preparation-*.

- Initial RED: APIs missing; first GREEN: five transactional tests passed.
- Neighbour suite: 52/0, including exact migration/schema definitions and prepared semantic projection.
- Stronger rollover test found three real failures: a newer current Edition did not obsolete the previous same-binding candidate. The base Edition fence fixed promotion and retained retry. One intermediate build needed a missing try on strict field decoding; retained as failed evidence.
- Stronger retarget test found two real failures: returning to the old Edition with the same token revived an old append callback. Reset now rotates and returns the handle. The old callback and empty-stage handle reject; the new handle restores the retained candidate.
- Final affected suite: **55 tests, zero failures**, exit 0. Includes real FeedSession restore-before-promotion / checkpoint-after-promotion behavior, active checkpoint continuity, prepared append, cancellation/supersession, atomic promotion rollback, stale handles, archived history, and schema upgrade neighbours.
- Final full macOS Debug package: **1844 tests, one skipped, zero failures**, exit 0, no capacity interruption. The ignored reference comparison requires FEEDMINE_REFERENCE_FEEDS_ROOT / FEEDMINE_REFERENCE_CATALOG.
- A subsequent test-only addition verified the real ColdFeedBootstrap→Runtime→writer→FeedSession prepared pipeline: **one test, zero failures**, no HTTP. It projects before promotion without active viewport authority, then checkpoints through the same promoted handle. Production sources are unchanged from the full run; the full-run executable hash was captured before rebuilding the extra test. Do not call this a single full 1845-test execution.

Independent read-only review covered the full preparation boundary and returned no actionable findings. The later retarget fix received a second read-only review with no remaining findings. The previously quota-limited review of native commit b1d248bf was also resumed successfully; no actionable issue in logical/frozen identity separation or word-policy wiring. No builds were delegated to reviewers.

## Still required

AppComposition does not yet consume prepared ownership. Native NF03 must prepare the candidate handle, cancel obsolete/failed handles, checkpoint/freeze the last prior viewport at cutover, reconcile the candidate projection as necessary and promote synchronously immediately before installation. Initial/ordinary switches may promote immediately. Legacy exact/forward selection, runtime namespace collision isolation and ambiguous-history recovery must be wired into that path. No R4 expected failure was removed.

R4 remains FAIL in the actual native host. This package evidence does not certify native relaunch/UI, pt/en large-text stable tail or benchmark gates. B02/B04/B05 remain open, B03 FAIL and B06 NOT_RUN unchanged. The full autonomous improvement objective remains active.
