# F13 — strict word-policy resolver — 2026-10-28

This checkpoint implements the first policy-resolution slice of the R4 design. The host regression remains **FAIL**; publication/history wiring and UI acceptance remain pending.

Design: `docs/superpowers/specs/2026-10-28-global-word-continuity-design.md`.
Plan: `docs/superpowers/plans/2026-10-28-global-word-policy-resolution.md`.
Fresh builder check: “nothing important left”. Choices about implementation and ambiguity recovery are executor decisions under the user's autonomous continuation instruction.

The strict resolver must reject unresolved active templates and duplicate catalogue definitions, preserve context words with global master-off, and yield normalized equivalent policy independently of display labels/rule order. Existing nonthrowing entry points stay unchanged until transactional publication guards and durable history ownership are ready. No R4 expected failure is removed by this slice.

Validation uses a filtered macOS Debug package run with `-gnone`, one compiler job, index store disabled and a monitored 300 MiB free-space floor. This limited functional check does not change the standard benchmark's 3 GiB reserve or the iOS tests' 700 MiB reserve. Initial unprivileged invocation failed to write the compiler cache; that infrastructure failure is not counted as RED.

RED: monitored compilation failed solely because `resolvedExclusions`/`ResolutionError` did not yet exist (exit 1); no capacity interruption. GREEN: 13 tests passed, exit 0. Independent code review found no actionable correctness issues. Its optional order/duplicate coverage was added: final **14 tests, 0 failures**, exit 0, no capacity interruption. Minimum observed free space in the final run: 460070912 bytes. `git diff --check` passed.

Logs are losslessly gzip-compressed and verified byte-for-byte. The `r4-strict-policy-*.json` reports contain exact commands, exit codes and capacity observations; `r4-strict-policy-provenance.json` records code/log SHA-256 and scope. These are filtered package tests, not a new full-package or iOS run. The last full package result remains 1777 tests/1 skip/0 failures on the preceding source production checkpoint. Historical databases, products and completed results are retained; `capacity-ready.json` is unrelated and untouched.
