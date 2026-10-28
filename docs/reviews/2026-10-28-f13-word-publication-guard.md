# F13 — transactional word-policy guard — 2026-10-28

Base `cdb06e63`. R4 remains **FAIL in the native host**: this slice establishes the shared snapshot and guarded database writers; coordinator/opportunity capture and reader-history ownership are pending. No existing R4 expected failure is removed.

The same Domain resolver now computes Composition's strict effective words and the snapshot checked against durable settings inside PublicationStore's existing transactions. Localized template descriptors contain normalized words, not display labels or catalogue IO. Context-owned words stay independent of the global master. Effective-equivalent template substitutions/master changes may commit; missing active templates, corrupt settings and stale effective words cannot fail open.

Four guarded entry points check before any mutation: create, create with initial checkpoint, append, tail-checked append. Existing callers without expectations retain their compatibility behavior. New tests prove rejected writes leave no Edition/CardRecord/segment/checkpoint fragments and preserve admitted rows/position on append rejection.

## Validation and review

- Initial RED: new tests could not compile because the planned snapshot/guard interfaces did not exist; exit 1, no capacity interruption.
- First implemented run: 22 tests executed, two failures in one new test. The test incorrectly expected segments() on a missing Edition to return empty; that API correctly throws missingEdition. Replaced with a direct zero-row SQL assertion, retaining the no-partial-history requirement. Production code unchanged by that test correction.
- Focused corrected run: 23 tests, zero failures, exit 0.
- Independent review: no actionable correctness findings. Its suggested template-equivalence isolation was implemented; contextual overlap/master-off now has a separate case.
- Broad Persistence/coordinator compatibility attempt: interrupted by the 300 MiB monitor, exit -2; **not a suite PASS**. Historical data and its log retained.
- A targeted affected-API check with the compiled executable and --skip-build: 66 tests, zero failures, exit 0, no interruption. This is not the whole Persistence suite.

Final isolated-template recompile: **23 tests, zero failures**, exit 0, no interruption. Final affected-API replay on that rebuilt executable: **66 tests, zero failures**, exit 0, no interruption. These are overlapping sets, not 89 distinct tests. Minimum observed free space in the final replay: 440332288 bytes. `git diff --check` passed. Commands/exit codes/capacity reports are in `r4-word-guard-*.json`; verified gzip logs and final code/executable hashes are recorded in `r4-word-guard-provenance.json`. No new full-package or iOS acceptance is claimed.

## Capacity and preservation

The existing 3 GiB benchmark and 700 MiB iOS reserves are unchanged. These filtered macOS Debug tests use a monitored 300 MiB floor. After the interrupted broad run, an escalated process check found no swift-test, test executable or swift-frontend remaining; only the regenerable 239 MiB package ModuleCache was removed. Products, results and historical databases were retained.

Before the final test-only recompile, the prior package dSYM was archived losslessly and every file hash checked before removing the original directory. The executable is retained; the archive and restore command are recorded in r4-word-guard-symbol-archive.json. This preserves the symbols while freeing space; it does not strip or replace a historical product without a restore path.

Next work: carry the snapshot through PublicationCoordinator and native opportunity selection/preparation/commit, then implement the designed durable history binding and actual host continuity fix. Source acceptance and other F13 gates remain open.
