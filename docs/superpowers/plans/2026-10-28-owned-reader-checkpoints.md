# Owned Reader Checkpoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans, native execution.

**Goal:** Commit first-publication ownership and preserve isolated, fenced reader positions through A→B→A.

**Architecture:** Extend SessionStore's existing active-session authority with a durable binding/activation token and per-owned-Edition checkpoints. All first-publication membership/checkpoint changes share the existing PublicationStore transaction. Existing unbound paths keep their behavior when no bound activation is active. No new scheduler/display authority.

**Tech Stack:** Swift/GRDB/SQLite/XCTest.

**Spec:** `docs/superpowers/specs/2026-10-28-global-word-continuity-design.md`.

## Constraints / review focus

Frozen rows and legacy scoped checkpoints stay intact. Per-Edition ownership prevents union-key collisions. Fresh activation tokens fence earlier A callbacks after A→B→A. Explicit current binding/Edition checks precede every guarded write. Nil legacy writes must not bypass an active bound owner. Adoption seeds from exact owned Edition checkpoint; never borrow by a colliding logical key. New tables are additive and backfill only already-established memberships.

## Task 1 — transaction and position boundary

Files: RuntimeMigrations.swift, SessionStore.swift, new SessionStore+HistoryBinding.swift, ReaderHistoryBindingStore.swift, PublicationStore+Writing.swift; new ReaderHistoryCheckpointTests.swift.

Interfaces:
- SessionStore.BindingActivation (readonly bindingID/token UUIDs); `activateBinding(_ bindingID: UUID) throws -> BindingActivation`, `checkpoint(bindingID:) throws -> CheckpointRecord?`.
- `saveCheckpoint(_:bindingActivation:)` default nil; initial insert internal helper accepts same optional token.
- Add SessionStoreError.missingHistoryBinding/staleHistoryBinding.
- PublicationStore.BindingPublicationExpectation(activation:expectedActiveEditionID:), second value defaults nil.
- Guarded first/initial writers add optional `bindingPublication`; guarded append writers add optional `bindingActivation`. Validate active token and expected current Edition, then attach new raw-context Edition and active pointer in the same transaction. Initial owned checkpoint is inserted after attachment in that transaction. Append requires actual Edition to be current and owned.
- `reader_history_checkpoints`: primary key(binding_id,edition_id), composite ownership FK; same semantic checkpoint fields, no card FK so neighbour restore remains possible.
- `session_reader_binding`: singleton active binding/token; extends SessionStore activation, never changes user intent/preferences. Legacy activateContext explicitly clears it; stale guarded calls then fail.
- Save owned positions to owned table only; do not overwrite a colliding legacy context_checkpoints row. checkpoint(for raw key) prefers a known binding and never falls back to another history when that binding is empty.
- Activation saves current durable point, seeds missing adopted position from matching Edition singleton/scoped checkpoint, clears singleton, installs the chosen owned point and rotates token atomically. Seed on new adoption and migration of existing memberships. Invalid/stale operations roll back without marking cards seen or changing another position.

- [x] Write tests for first-publication atomic ownership/checkpoint, rollback after late invalid placement, legacy collision isolation, A→B→A and stale callbacks, guarded append, nil bypass rejection.
- [x] Run RED; implement and run focused tests to GREEN.
- [x] Existing binding/migration/publication/session and owner compatibility tests; diff check/evidence/local checkpoint.
- [ ] Independent review: dispatched, unavailable due to reviewer usage limit; remains pending.

Next: transport expectations through coordinator/runtime, restore semantic history by owned Edition without crossing bindings, native root wiring and ambiguity UI. R4 remains FAIL until actual host continuity and reopen proofs; no expected failures are removed by this task.
