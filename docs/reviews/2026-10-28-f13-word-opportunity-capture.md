# F13 — word-policy opportunity capture — 2026-10-28

Base `b8bc334e`. Cold/live Composition owners can now receive the immutable localized capture policy and read current durable words at each opportunity. **AppComposition injection and history binding remain pending; native host R4 remains FAIL.** Existing R4 expectations are unchanged.

ReaderWordExclusionPolicy resolves the locale/template descriptor once and captures preferences strictly for each opportunity. Driver preparation, queued media preparation and local commit use the same captured value. Changes to effective words or resolved sources reopen the existing runway generation and late-fact executor. The source notification remains compatible and forwards to the content-policy notification. An equivalent masked policy does not reset the controller. Initialization/notification snapshots are deduplication only; authoritative opportunity capture still throws on errors.

Cold bootstrap captures before choosing its local cursor. A semantic word change resets a retained partial walk; a stale preparation/commit is reconsidered through the existing bounded retry path. Both owners retain nil-policy behavior for existing callers; no context/Edition metadata, acquisition authority, scheduler or PD-4 changes.

## Verification

- RED: absent planned policy/initializer APIs, exit 1, no capacity interruption.
- Initial focused run: three new owner tests passed.
- Strengthened focused run: five tests, zero failures; includes a nonnil cold partial cursor and live preparation-time mutation.
- Final affected suites (ColdFeedBootstrapTests, FeedRunwayDriverTests, SourceExclusionProductionTests, ReaderContentFilterPolicyTests): **136 tests, zero failures**, exit 0, no interruption. Includes the five tests above; do not add the counts. It reuses the final rebuilt executable with --skip-build.
- Independent review: no must-fix findings. Added its suggested partial-cursor proof and live preparation-race proof; added effective-equivalence no-reset assertions. No product edits after the review.
- `git diff --check` passed. This is not whole-package, iOS/native-root or UX13 acceptance.

The live removal proof exhausts a masked walk, removes the rule, obtains one receipt and preserves Edition, anchor, first frozen card and checkpoint; further work does not duplicate the new card. The cold partial proof would publish the wrong origin without rewinding to the masked head. Preparation races reject the stale first/live card; no stale history appears. The live race case blocks all matching future local supply, so it proves safe rejection/reconsideration, not eventual publication of a different eligible candidate. The independent removal proof supplies the positive eventual-publication case.

Corrupt-settings owner-specific tests and equivalent active-template-choice owner tests remain useful follow-up coverage; strict corruption handling and effective template equivalence already have lower-level snapshot/writer proofs. No additional owner-specific claim is made for those inputs here.

Exact commands/capacity observations are in r4-word-capture-*.json. Verified gzip logs and final code/executable hashes are recorded in r4-word-capture-provenance.json. Tests used macOS Debug -gnone, one job, a 300 MiB monitored floor. Standard 3 GiB benchmark and 700 MiB iOS guards remain unchanged. No data or products were deleted in this slice; unrelated capacity-ready.json is untouched.

Next: inject this capture policy from AppComposition using raw logical contextual words and its immutable catalogue descriptor, then implement designed durable history binding/root continuity and real iOS acceptance. Never derive word provenance by subtracting globals from frozen history. Remaining source/F13 journeys and B02/B04/B05 are still open; B03 FAIL and B06 NOT_RUN are unchanged.
