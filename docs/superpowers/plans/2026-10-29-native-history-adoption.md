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

## Task 2e — immutable recovery presentation before a choice

Ruling: use an explicit read-only PublicationHistory over the captured durable statement, instead of constructing a legacy FeedAssociation (its constructor activates context and may clear incompatible history). This preserves card-authoritative restore/neighbour semantics while keeping selection separate from ownership. The preview does not save cursors or mark seen. It is scoped to the Edition resolved from its captured checkpoint; it never follows a later singleton change.

- [x] RED/GREEN explicit-checkpoint restore, independent of singleton, no position/seen/ownership mutation, foreign-Edition refusal. 21 affected/0; full1847/one skip/0; independent review clean. See docs/reviews/2026-10-30-f13-recovery-preview.md.
- [ ] Native recovery state captures original intent, compatible active/retained statements and a read-only presented reader. Pause future publication and keep recovery state through lifecycle.
- [ ] Explicit previous criteria adopts the complete frozen contextual key; current criteria opens a distinct owned history without deleting unowned histories. Retained readings remain selectable. Revalidate choice transactionally.
- [ ] Existing fixed-size More-menu and empty-reader recovery routes, pt/en and accessibility, ordinary host tests and actual large-text UI/tail proof.

No claim that preview plumbing alone fulfills ambiguity recovery. Native selection continues to fail safely until the full presentation/choice route consumes it.

Task2e host-state slice: ReaderHistoryRecovery captures the active statement on initial ambiguous/unresolved selection, without a FeedAssociation/publication owners. Uses local decoder/bounds/session/store and the same bounded viewport ingress with rendered evidence. UI is intentionally not connected until recovery choices work; startup failure stays unchanged. Native test covers retained window, no ownership/position mutation, no HTTP from lifecycle/filter callbacks and delayed viewport ordinal. Remaining: explicit choices and retained inventory, retirement at chosen-association installation, rendering/empty-reader/More-menu/pt-en/tail. See docs/reviews/2026-10-30-f13-native-recovery-reader.md.

## Task 2f — explicit recovery choices

Ruling: choosing current criteria resolves an existing logical binding or allocates a discriminator even when the legacy namespace is still unowned. Require the displayed active checkpoint to match in that writer transaction; a stale choice is an atomic no-op. Choosing previous criteria adopts the complete frozen key via existing exact-context checkpoint evidence. Neither operation subtracts words or deletes history.

Review ruling: criteria choice is a durable user intent, separate from activation. Commit binding/adoption and selected preferences in one transaction guarded by the displayed checkpoint and expected current criteria. Root immediately records selectedContextKey and keeps the preview while the prepared candidate launches. A later failure cancels/closes that candidate, retains saved intent and preview, and reports selectionStoredNotActivated; retry and a new composition honour the saved criteria. Promotion rechecks the exact legacy checkpoint in its writer before any mutation. Retire preview synchronously at installation and reject late callbacks. No await between promotion and association assignment.

- [x] Independent namespace RED/GREEN and stale-choice rollback; intent/adoption atomic rollback and final checkpoint fence.
- [x] Native previous/current criteria RED/GREEN at cutover, saved-intent failure/retry/composition recreation, final checkpoint fence and retired callbacks. Native20/0; package1849/one skip/0. Retention after future same-key checkpoints remains Task2g.
- [x] UI consumes previous/current criteria through fixed-size More-menu and empty-reader route; real PT previous/tail/cancel/process-relaunch and EN accessibilityXXXL current/process-relaunch journeys pass. Preview keeps the same disabled card controls so activation does not change card height. See docs/reviews/2026-10-30-f13-visible-recovery.md.
- [ ] Retained inventory selectable in native UI; absence-of-singleton and unresolved-policy recovery remain required.

## Task 2g — retain original recovery statements independently

Historical hypothesis (subsequently refuted by the owned-write regression): a new owned checkpoint might overwrite a legacy context row. The real reproduced problem is refiling singleton A over a distinct legacy context statement B during activation. Before exposing recovery actions, add durable retained original statements independent of the context singleton, without claiming/merging the old Edition. Extend the read-only inventory and transactional adoption evidence to include those originals. Preserve multiple statements without latest-Edition guesses; idempotent recovery retries must not duplicate them. Cover current selection followed by later checkpoints/relaunch, exact-key collisions, archived/unknown/misfiled cards, and stale evidence. Keep UI off until this and retained-reading selection work.

Task2g evidence correction: owned checkpoint writes already preserve the legacy context row (passing regression before changes); initial suspected overwrite was not real. Functional RED: distinct active A/context B under the same frozen key loses B when activation refiles A. Additive retained statements now capture every known unowned original + card-authoritative Edition before all three activation boundaries, as well as explicit resolution/adoption. Inventory/adoption consume them, repeat capture is idempotent and pinned unknown-card evidence stays coherent. Focus41/0, review/followup clean. Full/native verification recorded in docs/reviews/2026-10-30-f13-retained-legacy-statements.md when terminal. UI and sibling selection still open.

- [x] Task2g retention core: additive migration, original+observed Edition, all activation boundaries, inventory/adoption, dedup/rollback, damaged unknown-card evidence; focused41/0 and independent review/followup. Final package/native results in the report. Retained sibling selection and UI remain unchecked in Task2e/2f.

## Task 2h — retained readings inventory independent of current criteria

Read-only inventory lists each committed Edition with its frozen publication metadata, optional logical owner, all distinct original/owned statements, actual active-reader statement and selected-preparation fact. Includes siblings with identical keys and works when no active singleton exists or active position was explicitly cleared. Sort deterministically by identity, never select the newest Edition or infer word origin. A selected hidden preparation is not an active reader. No current word-policy resolution is needed to inspect frozen history.

- [x] RED/GREEN inventory across unowned/owned siblings, absent singleton, selected preparation, promotion and explicit clear; stable order and authority unchanged. Foco44/0; full1855/one skip/0, independent review/followup clean. See docs/reviews/2026-10-30-f13-retained-readings-inventory.md.
- [ ] Explicit retained selection including sibling Editions under one logical binding, stale-evidence checks, native host and recovery UI.

## Task 2i — prepare an explicitly selected owned Edition

Introduce a transactional preparation entry point taking the retained-reading snapshot, its exact owned checkpoint and the current reader activation. Revalidate Edition/owner metadata, checkpoint, membership and current token before revoking any preparation. Explicitly select that Edition rather than automatic retained/base choice. Do not move the binding active pointer or active checkpoint; current reader can still save its final point. Promotion uses existing predecessor/base/token fences and preserves A before installing B. Returning A restores its final point, not the point observed before B prepared.

- [x] Owned sibling A→B→A RED/GREEN and stale selection/token/checkpoint failures without revoking another pending candidate. Foco46/0, full1857/one skip/0, native Content20+NF0313=33/0; review/followup clean. See docs/reviews/2026-10-30-f13-owned-reading-selection.md.
- [ ] Native consumption and unowned retained selection into an existing logical binding; no implicit ownership or namespace sharing.

This primitive requires a current bound reader and a checkpoint already owned by the selected binding. Absence of a current binding, original-only points, unowned sibling adoption, per-history namespace compatibility and UI choices remain required work, not silently treated as a fresh context.
