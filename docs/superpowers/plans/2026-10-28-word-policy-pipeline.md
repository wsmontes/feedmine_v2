# Word Policy Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans, native execution.

**Goal:** Carry effective word snapshots through selection, preparation, media reoffer and coordinator commit.

**Architecture:** Optional immutable snapshots on existing requests preserve legacy callers. CandidateProvider accepts an optional effective exclusion override without altering FeedPlan/context identity. The same snapshot reaches guarded writers. A global mask on a ready media skip retains the queue entry for a later unmasked opportunity.

**Tech Stack:** Swift/XCTest and existing module boundaries.

**Spec:** `docs/superpowers/specs/2026-10-28-global-word-continuity-design.md`.

## Constraints / review focus

No published-row or frozen-key changes. PD-4 unchanged. Nil snapshots retain existing context-filter behavior. Explicit snapshot words replace the frozen filter's word field only (other criteria remain); the descriptor must include true contextual words. Media candidates excluded only by the current word override stay queued; genuinely missing/superseded candidates still leave the queue. Source membership projection remains unchanged. No claim of native host continuity until actual opportunity capture/binding is wired.

## Task 1 — transport and enforcement

Files: PublicationCoordinator.swift; InitialProductionSlice.swift; LocalProductionSlice.swift; CandidateProvider.swift; PendingMediaReconsideration.swift. Tests: PublicationCoordinatorTests.swift and SourceExclusionProductionTests.swift (reuse its private production fixture).

Interfaces:
- CreateRequest/AppendRequest guarded initializers add default-nil `expectedWordExclusions: ReaderWordExclusionSnapshot?`; store and forward to all four writer paths.
- Initial/LocalProductionSlice.Request add optional `wordExclusions: ReaderWordExclusionSnapshot? = nil`. Both map store staleWordExclusions to their own corresponding errors; transport snapshot to coordinator.
- Guarded CandidateProvider overloads add default-nil `wordExclusions: ReaderContentExclusions?`; replace only filter.exclusions before eligibility. First preparation and actual selection use the same request snapshot.
- MediaSkippedSupply.reconsider/resolve add default-nil effective word override. For a supplied override, resolve exact candidates with frozen word field disabled, retain other criteria, then temporarily mask effective words after source projection, retaining masked queue entries.

- [x] Write coordinator stale-snapshot tests for first/initial/append/tail paths.
- [x] Write pipeline tests for word-blocked first/preparation, removal reoffer, mutation during preparation with atomic stale rejection, legacy frozen-word override, and reversible ready media skip.
- [x] Run RED and inspect missing API failures.
- [x] Implement and run focused publication/production/policy tests to GREEN.
- [x] Independent review, preservation/provenance evidence, diff check and commit.

Native ColdFeedBootstrap/FeedRunwayDriver capture and generation invalidation, plus historical binding and root-key changes, remain the next integration. Do not remove R4 expectations or claim UX13 PASS in this slice.
