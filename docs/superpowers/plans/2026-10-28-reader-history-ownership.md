# Reader History Ownership Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans, native execution.

**Goal:** Persist unambiguous ownership of immutable Editions by raw logical contexts, including exact legacy word-union adoption.

**Architecture:** Add two tables and a Persistence store; no frozen Edition/context/checkpoint row is rewritten. Adoption validates a forward computation from known raw context plus current effective words, never subtracting words from history. Edition ownership and runtime namespace uniqueness are transactional.

**Tech Stack:** Swift, GRDB/SQLite, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-28-global-word-continuity-design.md`.

## Constraints / review focus

Logical keys and frozen publication keys are separate. Existing canonical identities/revision versions stay unchanged. Edition ownership is unique. Ambiguous/incompatible adoption throws and rolls back, never merges histories. Reopening identical intent returns the same binding. Active Edition must belong to its binding. Runtime namespace is stable: legacy adopts its frozen key namespace; fresh contexts use raw canonical namespace unless already owned, then a persisted UUID discriminator. No scheduler/reader/root behavior changes in this slice.

## Task 1 — additive binding and safe adoption

Files: RuntimeMigrations.swift; new Persistence/ReaderHistoryBindingStore.swift; new Tests/FeedMinePersistenceTests/ReaderHistoryBindingStoreTests.swift.

API:
- Store.Record: UUID id, logicalKey, runtimeNamespace, activeEditionID.
- Store.Adoption: editionID, publicationKey, evidence.
- Evidence: exactContext or legacyWords(ReaderWordExclusionSnapshot).
- `resolve(logicalKey:adopting:) throws -> Record`, default nil adoption; `binding(for:) throws -> Record?`.
- Error cases: missingEdition, incompatibleAdoption, staleAdoptionPolicy, editionAlreadyOwned, runtimeNamespaceAlreadyOwned, runtimeNamespaceConflict, activeEditionConflict, corruption.
- Exact adoption requires frozen key == raw logical key. Legacy adoption requires snapshot.context == raw contextual exclusions; rebuilding the raw key with snapshot.exclusions must equal the declared frozen key, which must match the actual Edition. For a new claim, the snapshot must still match preferences inside the adoption transaction. Replaying already-established ownership returns the original record/provenance without reinterpreting later settings. Persist provenance (effective/context words and resolved templates) for audit, not as future policy authority.
- `reader_history_bindings`: unique logical canonical identity + JSON, unique namespace, nullable active Edition FK to its own membership.
- `reader_history_editions`: unique Edition FK, owner FK, frozen publication-key JSON, exact/legacy provenance; unique owner+Edition pair for composite active FK.
- Existing active binding cannot be silently redirected. Adoption of an Edition/legacy namespace owned elsewhere throws; fresh distinct contexts may allocate a discriminator. Existing records and provenance remain immutable/idempotent.

- [x] Write tests for reopen/idempotence; exact and valid legacy adoption with frozen values/checkpoint/save unchanged; forward validation rejecting unknown origin; stale adoption policy rollback; ownership collision with same union; stable fresh namespace after collision.
- [x] Run RED for missing APIs, implement and run focused tests to GREEN.
- [x] Run existing migration/rebuild/publication tests appropriate to additive schema; independent review and diff check.
- [x] Record evidence and commit.

Next task: atomic first-publication membership + binding checkpoints, history restore by owned Edition and explicit activation. Then native composition injection, replacement/legacy ambiguity UX and actual iOS validation. This task does not fix R4 or remove expected failures.
