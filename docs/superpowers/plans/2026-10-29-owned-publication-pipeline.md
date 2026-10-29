# Owned Publication Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans, native execution.

**Goal:** Carry activation/publication expectations intact through Runtime preparation and PublicationCoordinator into guarded writer transactions.

**Architecture:** Extend existing optional request metadata; no new owner or token acquisition. First publication carries BindingPublicationExpectation, append carries BindingActivation. Retired requests fail with SessionStoreError.staleHistoryBinding without automatically obtaining another reader's activation.

**Tech Stack:** Swift/XCTest and existing Persistence/Publication/Runtime boundaries.

**Spec:** `docs/superpowers/specs/2026-10-28-global-word-continuity-design.md`.

## Constraints / review focus

All four coordinator writer paths forward ownership metadata. Preparation cannot drop the captured activation. Nil unbound callers remain compatible, but cannot bypass a bound owner. No published/context key, policy, source alternation, scheduler or acquisition changes. R4/native restore remains pending.

## Task 1

Files: PublicationCoordinator.swift, InitialProductionSlice.swift, LocalProductionSlice.swift; PublicationCoordinatorTests.swift and SourceExclusionProductionTests.swift. PublicationRunwayStoreTests.swift updates its exact migration/schema inventory for the two newly registered history migrations; old definitions/data/index checks remain exact.

- CreateRequest guarded initializer/property adds default-nil `bindingPublication: PublicationStore.BindingPublicationExpectation?`.
- AppendRequest guarded initializer/property adds default-nil `bindingActivation: SessionStore.BindingActivation?`.
- InitialProductionSlice.Request adds optional bindingPublication; LocalProductionSlice.Request optional bindingActivation. Forward values without recapture or remapping retired ownership into retryable policy changes.

- [x] Tests: coordinator valid/stale first+initial writers, valid/stale append+tail writers; production initial+append owned success; activation change inside preparation rejects first/append atomically and preserves previous owned history/position.
- [x] Actual RED; implement and run focused tests to GREEN.
- [x] Independent review; affected-suite compatibility, diff check, evidence and commit.

Next: PublicationHistory/FeedSession owned restore and save; then cold/live owner and native composition injection. Do not expose a complete bound FeedSession claim until its history boundary carries the same activation. No R4 expected failure removed.
