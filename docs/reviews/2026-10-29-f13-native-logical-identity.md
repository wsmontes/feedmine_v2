# F13 — native logical identity and opportunity word policy

Previous goal turn: progress (f2be841f published read-only legacy candidate inspection). This slice changes the native AppComposition/FeedAssociation path, while leaving native binding activation and ambiguous-history recovery open.

## Result

FeedAssociation now retains immutable logicalContextKey separately from frozen contextKey. AppComposition supplies the raw persisted session key. Filter confirmation/no-op, pending handoff/lens, saved-preset no-op, warm discovery adoption, replacement supersession and installation guards compare explicit logical intent. Menu criteria/destinations use that intent, preventing global rules from leaking into a contextual edit or counting as criteria the reader explicitly selected. History, revision UUID/content, selection plan and presentation bounds continue using the frozen key.

Changing install guards to logical equality requires independent current-policy fencing. The native root therefore supplies its immutable template catalogue and raw contextual exclusions to one ReaderWordExclusionPolicy descriptor passed to both ColdFeedBootstrap and FeedRunwayDriver. Each actual opportunity re-reads strict settings and writers retain transactional stale-policy checks. Direct/legacy FeedAssociation constructors keep default nil policy and logical-key fallback behavior.

reapplyReaderFilters is intentionally still the old replacement path. Durable binding injection, authority cutover respecting NF03, collision namespace integration and legacy ambiguity recovery remain pending. The known R4 continuity oracle continues to reproduce its failures; no expected failure was removed and this slice does not claim R4 fixed.

## Native verification ledger

Evidence prefix: evidence/2026-10-27-source-exclusions/r4-native-logical-identity-*. Actual iOS simulator hosted XCTest, unit-only temporary scheme, Debug without symbols, reserve floor 700 MiB. This is not XCUI route/geometry, process-relaunch acceptance, benchmark or a full native test suite.

- RED build succeeded; the new unchanged-context test failed three actual assertions: globals incorrectly marked handoff pending, lens pending, and unchanged criteria confirmation returned true.
- GREEN ContentFilterTests: 13 tests, zero unexpected failures. Includes three new normal tests for no implicit transition, pending lens raw criteria, and real cold publication under current words despite frozen global union. Own-word overlap remains gated when global master is off. This class also includes the pre-existing strict expected-failure R4 reproducer (eight measured add/master-on symptoms), which still fails as expected.
- FilterConfirmationBoundaryTests: 13 tests, zero failures. Includes persistence refusal, recoverable presentation failure, A→B→A supersession and keeping the prior displayed reader until installation.
- New live-owner test first failed to publish allowed supply. Diagnostic run showed the planned predecessor and actual tail source were equal and PD4-compatible, disproving the initial tail-race hypothesis. The fixture directly inserted canonical rows but omitted noteLocalSupplyFact, unlike real acquisition receipts and the existing native source-rule test. Correcting that fixture contract made the live proof pass: one test, zero failures. Allowed B publishes once while A is word-excluded; removing the word publishes A once; frozen CardRecords/prefix and the same Edition/association survive. Source alternation was not changed.

Additional context/preset/restore checks are recorded after their terminal result below. Production binary hashes in the run records distinguish actual builds; only test code changed between the GREEN and final live build.

## Review and remaining scope

Independent code review was dispatched with a fresh context, but returned no review because of account usage limits. It is pending, not passed. Local diff/type checking and actual native tests are recorded separately; PR remains draft and unmerged.

R4 remains FAIL in the actual native host. Native ownership activation/handoff, ambiguous legacy criteria choices and retained-history access, future policy failure recovery UI, relaunch and pt/en large-text stable-tail acceptance remain required. B02/B04/B05 open, B03 FAIL and B06 NOT_RUN unchanged. The broader autonomous improvement goal remains active.

Final additional CompositionTests selection: **7 tests, zero failures**, exit 0. Covers context/filter round trips, stale callbacks, saved presets and answers arriving during context/preset/replacement construction. The four successful executions cover **34 distinct native tests with zero unexpected failures**, including the unchanged strict R4 reproducer. Their production app binary hash is identical; the final test bundle only adds the live proof/fixture correction. The last full macOS package run remains 1829/one skipped/0 at earlier 589f3470; no new full-package claim is made.
