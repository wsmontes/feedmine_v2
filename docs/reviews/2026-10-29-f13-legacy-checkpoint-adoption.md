# F13 — explicit legacy checkpoint adoption

Previous goal turn: progress (171ac228 published and full suite verified). This turn inspected the native composition and found an outstanding integration boundary: legacy adoption seeded only by the checkpoint’s Edition column, while card identity must remain authoritative.

ReaderHistoryBindingStore.Adoption now optionally carries the original durable checkpoint. The existing writer transaction verifies exact equality against a persisted singleton or context row and resolves the card’s live/retired Edition. Only that Edition may be adopted. Unknown anchors retain their declared Edition; fabricated anchors/offsets and stale or foreign evidence reject atomically. Raw history, date, placement and offsets remain preserved. Established replay cannot rewind a newer owned checkpoint. Default no-evidence callers retain their previous behavior.

A strengthened archived-card test exposed a second real failure: after adoption, activation attempted to re-file the inconsistent source statement under its wrong Edition, failing the legacy card FK. Activation now skips that redundant filing only if the card-authoritatively corrected statement exactly equals the point already retained by the target binding. Any different statement still follows the existing path. Production FKs remain enabled; only the disposable damaged-legacy test connection disables them to reproduce prior corruption.

## Evidence and review

Evidence prefix: evidence/2026-10-27-source-exclusions/r4-legacy-checkpoint-*. Initial RED lacked the checkpoint parameter. Initial GREEN passed the new adoption tests. One enlarged-run fixture failed to compile due to using PolicyVersion for SelectionSchemaVersion; the fixture type was corrected. The strengthened archived-authority run then produced a real FK failure, followed by GREEN after the activation correction.

Final affected run: **28 tests, zero failures, exit 0**, no capacity interruption. Covers exact offset/date retention, mismatched Edition, replay after newer progress, stale/foreign evidence rollback, inactive context-only evidence, fabricated offsets/anchors, and pre-existing unknown/archived anchors. The archive case uses an incorrect declared Edition and therefore proves real retired-card lookup rather than fallback.

Independent read-only review found no actionable code issue. Reviewer requested stronger archive coverage; the resulting failure was fixed and re-reviewed with no remaining actionable finding.

## Remaining scope

Native selection/injection, runtime namespace isolation, ambiguous-history recovery, live word-policy notification and actual R4/relaunch/UI acceptance remain pending in the implementation plan. No native expected failure was removed. This API is deliberately not yet represented as an end-to-end R4 fix. B02/B04/B05 open, B03 FAIL and B06 NOT_RUN remain unchanged.

Final full macOS Debug package: **1829 tests, one skipped, zero failures**, exit 0, no disk-budget interruption. The skipped catalogue comparison still requires external FEEDMINE_REFERENCE_FEEDS_ROOT/FEEDMINE_REFERENCE_CATALOG. This is not native iOS or benchmark acceptance.
