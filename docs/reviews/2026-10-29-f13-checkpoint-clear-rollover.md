# F13 — checkpoint clearing after Edition rollover — 2026-10-29

Base `124edecc`. The resumed independent review identified a P2: a same-binding Edition rollover retains its activation token, so clearActiveCheckpoint could accept a delayed A callback and remove B's singleton. Save/append already checked Edition ownership; clearing did not.

A formal RED reproduced the defect: five tests, two failures (clear accepted, B checkpoint lost). The fix adds expectedEditionID. Bound callers must supply it; the clearing transaction validates the live activation, current owned Edition and actual singleton before preserving/removing any point. Legacy unbound calls retain their previous behavior. Valid A/B clears work; owned historical positions remain saved.

Focused GREEN: five tests, zero failures. Combined affected suites: **243 tests, zero failures**, exit 0, no capacity interruption. Counts overlap. No full-package, native iOS or UX13 acceptance claim. The independent reviewer rechecked the fix, confirmed P2 resolved and reported no new finding in the correction. The previous checkpoint's pending review is now completed with this correction; its original report remains a historical record.

Exact commands/results/capacity, verified gzip logs and final source/executable hashes: r4-rollover-clear-* evidence in docs/reviews/evidence/2026-10-27-source-exclusions. Functional macOS Debug reserve remains 300 MiB; benchmark/iOS guards unchanged. No historical data/products removed.

R4 host remains FAIL. Next: transport binding expectations and restore/save semantic history with owned activation before native root wiring. No expected failures removed.
