# F13 — atomic owned positions and activation fencing — 2026-10-28

Base `ed492b27`. First-publication ownership, active pointer and initial checkpoint can now commit in one transaction. Owned reader positions are isolated per binding/Edition; activation tokens fence callbacks from retired readers, including A→B→A. **Coordinator/runtime transport, semantic restore and native composition remain pending; R4 host remains FAIL.** Existing expected failures are unchanged.

The additive migration extends SessionStore's existing active-session authority with a bound activation token, plus an owned checkpoint table. It does not change user preferences or introduce a second display/scheduling owner. Adoption/migration seeds only from a matching explicitly owned Edition. Owned writes preserve original legacy scoped checkpoint rows instead of overwriting a colliding frozen key. A known empty binding never borrows another reader's old position.

First/initial writers validate activation and the expected active Edition before the transaction commits; membership is attached in that same transaction. A late invalid checkpoint rolls back Edition, cards, membership and pointer. Appends and checkpoint saves require the live activation and actual current owned Edition. Nil legacy writes cannot bypass an active bound session. clearActiveCheckpoint also requires the current token when bound; explicit legacy activateContext clears the bound activation, retiring guarded writers.

## Validation

- Initial RED: missing planned APIs, exit 1.
- First compile exposed a missing `try` on a throwing token decoder; corrected and then four focused tests passed.
- Self-review added a regression for an unscoped clearActiveCheckpoint call: formal RED with two assertions proved it cleared B. Added the activation guard; four focused tests passed.
- Final strengthened publication/checkpoint/migration set: **48 tests, zero failures**, exit 0, no capacity interruption. Includes the fifth new test for expected-Edition rollover and retained old position.
- Final combined affected suites: **243 tests, zero failures**, exit 0, no interruption, using the final rebuilt executable with --skip-build. These include the 48; do not add counts. Includes cold/live owners, initial/local production, coordinator, policy, migration, publication and checkpoint suites.
- `git diff --check` passed.
- An independent review was dispatched, but the reviewer failed because its usage limit was reached and returned no review. This checkpoint therefore has local review and test evidence, **not a completed independent review**. GitHub publication is a draft progress checkpoint.

These are filtered macOS Debug tests, not whole-package, actual iOS, black-box UX13 or benchmark acceptance. Logs preserve failed attempts as failed. Verified gzip logs, code/executable hashes and commands/capacity observations are in r4-owned-checkpoint-* evidence. Functional tests retain the 300 MiB monitored floor; iOS/benchmark reserves are unchanged. No historical data or products were removed.

Next: carry activation/publication expectations through coordinator/runtime; restore by owned Edition while retaining valid neighbour semantics and preventing cross-binding resolution; then native root injection/legacy ambiguity recovery and actual iOS proof. Bound callers must use the owned activation APIs; legacy scoped deletion is not the owned-history retirement mechanism. R4 and remaining F13 gates stay open.
