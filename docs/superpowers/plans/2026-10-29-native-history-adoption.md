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

## Task 2b — native logical identity / frozen publication identity split

FeedAssociation gains immutable logicalContextKey, defaulting to its publication context for direct/legacy constructors. AppComposition passes raw session.key independently of the current applied publication key. Audit context intent comparisons (warm discovery guard, filter confirmation/pending/lens, saved preset no-op, supersession and install guards) to use logical identity. Menu context facts use logical criteria; history/editorial policy/bounds keep the frozen publication key.

- [x] Native RED: editing globals without changing raw criteria must not report a filter handoff pending or confirm an unchanged raw filter as a new context transition.
- [x] Implement identity split and audit consumers; actual native iOS validation: 34 distinct tests, zero unexpected failures (known strict R4 reproducer retained).
- [x] Independent review of native identity/policy wiring resumed after usage limit; no actionable findings. See docs/reviews/2026-10-29-f13-reader-preparation.md.

This does not yet change reapplyReaderFilters or activate bindings. The existing native R4 expected failures must remain until the whole reading-continuity path is wired and proven.

Dependency discovered during the intent-guard audit: changing install/supersession guards to logical equality is safe only when publications independently capture current word policy. This slice therefore supplies one immutable catalogue/raw-context descriptor to both native cold/live owners. Direct constructors retain the default nil behavior. New native cold test keeps the same owner/frozen union, disables globals and verifies effective rules through real publication, including overlapping contextual words.

## Task 2c — prepare a replacement without retiring the presented reader

The actual NF03 tests require preparation/acquisition while the old reader stays live, and checkpoint refusal after that preparation must leave the same old association active. Moving the checkpoint before preparation is not equivalent. Activating B in its constructor would retire A prematurely.

Extend the existing SessionStore authority with per-binding retained preparation records and at most one selected preparation token. This is publication/read authority for the hidden candidate, not a second display owner. Capture the predecessor activation as a promotion fence. A prepared Edition pointer is separate from reader_history_bindings.active_edition_id, including for a same-binding revision rollover. Initial publication/append may use the selected preparation, writing only owned history; active checkpoint/clear and direct markSeen remain current-reader-only. PublicationHistory may project prepared history without recording it as seen. Promotion verifies the predecessor and selected token, preserves A's latest point, installs B's pointer/checkpoint and makes the same captured token current atomically. Cancellation/supersession revokes preparation authority but retains its explicit candidate Edition/point for a later retry; do not burn hidden published supply or guess the latest Edition.

A new additive reader-history-preparation-v1 migration stores per-binding prepared Edition, presence, token, selected bit and predecessor binding/token pair; unique partial index enforces one selected preparation. Existing immediate activation/context switches revoke selected preparation authority. Normal no-token/active APIs retain strict behavior.

- [x] RED transactional tests for prepare/publish/read without moving A; A checkpoint after preparation; promotion; cancellation/supersession; same-binding rollover; rollback; retained retry; stale predecessor.
- [x] Implement prepared owner transport at Persistence/PublicationHistory; 55 affected/0, full1844/one skip/0 plus later cold-pipeline1/0. Independent review and retarget followup completed. See docs/reviews/2026-10-29-f13-reader-preparation.md.
- [ ] Native NF03 consumes the prepared handle, checkpoints A after next.launch, promotes synchronously immediately before installation, cancels obsolete/failed handles. Initial/ordinary switches may immediately promote. Native binding selection/ambiguity UI and R4 ordinary assertions still required.

Task2c stronger checks required base_edition_id fencing and token rotation on explicit reset. Callers must capture the returned reset handle before constructing the reader/owners. A retained candidate is resumed only while its base Edition still matches; consumed preparation metadata is cleared on promotion, without deleting Edition/checkpoint history.

## Task 2d — consume prepared bindings in the native host

For raw logical input, reuse its existing binding, otherwise inspect exact/current-forward unowned candidates. Prefer a compatible active statement; retain ambiguity as a typed failure before ownership writes (explicit More-menu recovery still required). New first Editions use raw criteria. A restored Edition keeps its frozen key/revision. Prepared compatibility resets must capture the returned token. Root uses the binding's runtime namespace for collision salt and discovery-walk cache isolation.

NF03 constructs/launches with a prepared handle; the previous viewport remains authorized. At cutover freeze/drain the prior viewport ingress, checkpoint it, refresh only the hidden prepared projection from the final point when needed, validate latest raw intent, then promote synchronously immediately before assignment. Resume old ingress and cancel prepared handle on failure/supersession. Other initial/ordinary transitions may promote during synchronous construction. Closing a candidate cancels only its own prepared handle.

Global rules invoke the existing semantic eligibility notification instead of replacement. Native R4 strict failures may be removed only after actual host execution shows they are now unexpectedly passing, then ordinary assertions must pass. Legacy ambiguity recovery/UI, unresolved-policy recovery and remaining acceptance are still required, not certified by the unambiguous path.

- [x] Native RED ownership/global edit/composition recreation; hidden-only refresh RED. Real OS process relaunch remains open.
- [x] Wire binding selection, constructor/history/cold/live, NF03 promotion and namespace.
- [x] Actual native tests; R4 ordinary oracle, legacy adoption/collision and existing handoff tests; independent review. See docs/reviews/2026-10-30-f13-native-history-binding.md.
