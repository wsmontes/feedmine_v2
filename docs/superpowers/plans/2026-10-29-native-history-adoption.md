# Native history adoption implementation plan

> Native execution using superpowers:executing-plans. Existing approved design: global-word-continuity-design. User requested autonomous execution.

Goal: wire native context selection/history ownership and current word policy while preserving frozen reading. No R4 success from package-only evidence.

## Task 1 — explicit durable checkpoint evidence during legacy adoption

Existing adoption seeds only by the statement's Edition column. Native card-authoritative restoration must be able to supply the original durable statement when the card belongs to the adopted Edition but the column is inconsistent.

Add optional original checkpoint evidence to ReaderHistoryBindingStore.Adoption. Inside the existing ownership transaction, verify the exact statement remains in the singleton or legacy context row, verify the durable live/retired card resolves to the adopted Edition (unknown card requires the declared Edition), and copy into owned history with only Edition corrected. Preserve source rows, timestamp, placement and offset. Reject stale/fabricated/foreign evidence atomically. Existing no-evidence callers retain behavior; established adoption replay remains idempotent and never overwrites newer positions.

- [x] RED tests: mismatched column, stale/foreign statement rollback, retained-context evidence, fabricated/unknown anchor rejection and idempotent replay.
- [x] Implement, focused GREEN, independent review and evidence.

The stronger archived-card test exposed redundant legacy refiling during activation. Skip it only when the target binding already retains the exact card-authoritatively corrected statement; preserve all other paths. See docs/reviews/2026-10-29-f13-legacy-checkpoint-adoption.md.

## Task 2 — native association integration

Audit all association.contextKey consumers. Separate logical intent from frozen publication key; choose legacy candidate using actual card Edition, exact raw/current-forward match and compatibility. Ambiguous evidence preserves presentation, pauses future publication and exposes explicit recoverable choices. Use persisted runtime namespace for collision isolation. Supply one captured activation to history/cold/live; supply current word policy built from raw contextual exclusions. Globals trigger current opportunity reconsideration without replacing reader. Preserve explicit criteria A→B→A.

- [ ] Implement native resolution and ambiguity recovery with tests.
- [ ] Inject bindings/policy; actual iOS R4 ordinary assertions, relaunch and explicit-context tests.
- [ ] UI pt/en large text, stable tail and remaining acceptance gates.

R4 native remains FAIL until actual host evidence. No expected failure removed in Task 1.

## Task 2a — inspect legacy candidates before native activation

Native NF03 prepares a replacement while the previous reader is displayed and checkpoints the old reader before installation. Candidate discovery must not activate ownership or rotate tokens. Add a read-only inventory on ReaderHistoryBindingStore returning every unowned Edition matching the raw key or its known current forward union. Return the original durable point when available, resolving its card's live/retired Edition; distinguish the active singleton candidate. Keep multiple candidates, deterministic ordering and no newest-Edition guess. Existing owned Editions are excluded. Strict snapshot/context validation must occur in the same read snapshot. No global-word subtraction. Native compatibility and ambiguity decisions remain at the host boundary.

- [x] RED inventory tests: exact/forward, active card-authoritative candidate, multiple retained histories, exclusion of owned history/collision, stale snapshot, no ownership/activation/checkpoint mutation.
- [x] Implement inventory, verify (32/0) and independent review. See docs/reviews/2026-10-29-f13-legacy-history-inventory.md.
- [ ] Consume inventory in native root with handoff/ambiguity recovery.
