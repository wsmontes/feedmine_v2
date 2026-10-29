# Owned Semantic History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans, native execution.

**Goal:** Restore/save a binding-owned reader using its captured activation, preserving existing card/nearest-neighbour semantics without borrowing another binding's history.

**Architecture:** SessionStore supplies strict activation-scoped checkpoints. Activation repairs an inconsistent Edition column only when the durable card's actual Edition is already owned by that same binding; historical statement rows remain retained. PublicationHistory carries the activation through read validation, explicit cursor saves and seen milestones. Default nil behavior remains legacy/unbound.

**Tech Stack:** Swift, existing GRDB transaction boundary, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-28-global-word-continuity-design.md`.

## Constraints / decisions

- Card identity remains authoritative (NF03). Archived/unknown cards retain existing neighbour/unknown-position behavior and do not silently acquire a relative offset on another card.
- At activateBinding, if the saved card locates to a different owned Edition of the same binding, move the active pointer and copy that statement to that Edition's owned checkpoint in the same activation transaction. Keep the old statement/legacy rows, timestamp and card offset. Unknown card leaves the declared owned Edition unchanged for normal fallback.
- A located card in an unowned/other-binding Edition rejects activation; rollback retains the prior active reader/token. New legacy adoption must resolve ownership explicitly rather than infer it from a card in another history.
- Add optional `bindingActivation` to PublicationHistory initializer. All saved-position reads use it, validate optional contextKey against raw logical or actual active frozen publication identity, and never fall back to singleton/another key when empty.
- Reads validate the resolved Edition belongs to the current activation before/after window materialization; retired handles cannot restore/draw/save/mark another reader. Source/global eligibility never filters frozen cards.

## Interfaces/files

- RuntimeMigrations.swift: additive reader-history-active-position-v1 adds checkpoint_present to the activation marker, backfilled from the old singleton. Owned reads respect active presence; passive binding history retains the old point. Copy only live owned cards into the legacy singleton; never disable its FKs. Save/initial set presence; clear removes active presence without deleting history. PublicationRunwayStoreTests retains exact migration/schema enumeration.
- SessionStore+HistoryBinding.swift: `checkpoint(bindingActivation:contextKey:) throws`, `validateBinding(_:editionID:) throws`; activation repair helper.
- PublicationStore+Presentation.swift: extract existing location lookup into internal `location(ofCard:in:)` sharing identical public behavior.
- PublicationStore+History.swift: public markSeen adds optional bindingActivation and checks owner in the same writer transaction; static helper remains for already-guarded checkpoint writers.
- PublicationHistory.swift: optional captured activation; route savedCursor/restore/saveCursor/markSeen/window through scoped validation, preserving legacy nil callers.
- Tests: new PublicationOwnedHistoryTests; owned checkpoint activation repair/rollback tests. Verify exact restore/save, retained head, stale handles after A→B→A, wrong-key/window/seen rejection, same-binding mismatched Edition repair, cross-binding rollback, archived/unknown fallback.

- [x] Write RED tests for scoped restore/save and activation repair boundaries.
- [x] Implement; focused GREEN; independent review.
- [x] Affected-suite verification, diff/evidence/commit.

Native root selection/injection, legacy ambiguity recovery and real R4/iOS acceptance remain pending. No R4 expected failure removed.

## Task 2 — connect the existing cold/live owners

Decision: include owner transport now that the matching bound PublicationHistory exists, so the end-to-end FeedSession can checkpoint what it publishes. FeedRunwayDriver adds optional bindingActivation, constructs its auxiliary history with it and forwards the same value on each Local request. ColdFeedBootstrap adds optional opaque InitialProductionSlice.PublicationBinding and forwards it through Request.useBinding; Runtime unwraps the existing writer expectation, preserving the request API. This keeps the finite bootstrap independent of Persistence/store types. No token acquisition/retry is introduced; callers supply the bound FeedSession. Default nil preserves existing callers. Tests exercise cold publish→restore→checkpoint and live restore→append with unchanged position→checkpoint.

- [x] Owner tests RED, implement, GREEN; independent review of owner transport.
