# F13 — word-policy selection and commit pipeline — 2026-10-28

Base: `c3c1f010`. This advances the planned R4 fix; **native host R4 remains FAIL**. ColdFeedBootstrap/FeedRunwayDriver do not yet capture the new word snapshot, and historical binding/root identity changes remain pending. Existing R4 expected failures are unchanged.

## Implemented behavior

PublicationCoordinator transports the immutable word snapshot through all four guarded writer paths. Initial and local production requests use its effective words for preparation and structural selection, forward it to commit and map stale-policy rejection to their own errors. CandidateProvider replaces only the frozen filter's word field when explicitly given an effective override; all other criteria and the frozen context/revision remain intact. Nil preserves existing behavior. Callers must include true contextual words in the supplied snapshot; the legacy frozen key is not treated as provenance for that split.

Media reoffer resolves candidate existence/current revision with other criteria intact, then applies the current word mask separately. A temporarily masked ready candidate remains in the bounded queue; missing/superseded candidates keep their original settlement behavior. Source projection and PD-4 are unchanged.

## Evidence

- RED: missing coordinator/request interfaces, exit 1, no capacity interruption.
- Implemented focused run and final strengthened run: **38 tests, zero failures**, exit 0, no interruption.
- Final affected-suite compatibility run: **91 tests, zero failures**, exit 0, no interruption. This includes the 38; counts must not be added. Command uses --skip-build against the final rebuilt executable.
- Independent review found no actionable correctness issue. Its negative-language coverage suggestion was addressed by adding a Portuguese candidate under an English filter. The explicit override still admits only English; a snapshot carrying true contextual words blocks it as required.
- `git diff --check` passed. No full-package, iOS host or UX13 acceptance is claimed.

Production proofs cover first/preparation word masking, removal allowing unpublished supply, unchanged frozen first card/checkpoint, stale changes during both first/append preparation, unchanged Edition context metadata, four coordinator writer guards, and a ready media skip retained while masked then published on removal. These are real SQLite/local production integration tests, not user gestures or process relaunch.

Exact commands, exit codes and capacity observations are in r4-word-pipeline-*.json. Logs are losslessly gzip-compressed with verified bytes; code/executable/log hashes are in r4-word-pipeline-provenance.json. These macOS Debug functional tests retain the 300 MiB monitor. Standard benchmark and iOS reserves are unchanged. No historical data or product was deleted for this slice; capacity-ready.json remains unrelated and untouched.

Next: inject a stable localized descriptor and true contextual key into cold/live opportunity capture, including preparation/reoffers and semantic generation invalidation. Then implement durable history ownership and root continuity, remove expected failures only after actual host GREEN, and run the remaining F13 acceptance journeys/gates.
