# Global Word Policy Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Execution is native in the existing checkout under the user's autonomous continuation instruction.

**Goal:** Provide deterministic, strict resolution of global words before wiring the R4 publication guard.

**Architecture:** Add a throwing resolver alongside the existing compatibility API in ReaderContentFilterPolicy. It combines context-owned exclusions with current global settings and rejects unresolved active templates. Existing production entry points stay unchanged until the transactional guard and history ownership are ready.

**Tech Stack:** Swift, XCTest, existing FeedMineDomain and FeedMineComposition modules.

**Spec:** `docs/superpowers/specs/2026-10-28-global-word-continuity-design.md`.

## Global Constraints

- Published cards and revisions remain immutable; source alternation PD-4 remains mandatory.
- Context words always contribute independently of the global master.
- No historical keyword subtraction, identity/version bump or benchmark reserve change.
- This slice alone does not fix R4 and must not remove the strict expected failures.

## Review Focus

- A disabled global master with an unknown template must still retain context words.
- Duplicate template definitions must throw deterministically, never trap.
- Missing selected templates must not silently become unrestricted publication.
- Template display-label changes must not change the effective policy.
- Explicit words without selected templates must work with an empty catalogue.

## Task 1 — strict effective resolver

Files: modify `Sources/FeedMineComposition/ReaderContentFilterPolicy.swift` and `Tests/FeedMineCompositionTests/ReaderContentFilterPolicyTests.swift`.

Interface: `ReaderContentFilterPolicy.resolvedExclusions(settings:templates:context:languages:) throws -> ReaderContentExclusions`; context defaults to `.disabled`, languages to preferred languages. Add nested public `ResolutionError: Error, Equatable` cases `duplicateTemplate(String)` and `missingTemplates([String])`. Missing IDs are unique and sorted. Validate duplicates only when the global gate is enabled and at least one template is selected; duplicate catalogue keys make that selected-catalogue resolution invalid even if the duplicated key is unselected. Gate-off never consults catalogue data. Leave existing nonthrowing helpers unchanged for compatibility; new publication guard will use strict API.

- [x] Add tests for missing selected template, duplicate catalogue key, gate-off with malformed catalogue/context overlap, normalized template+own+global union, and equal policy after template-label/order changes.
- [x] Run filtered package tests and record RED due to absent interface.
- [x] Implement the resolver using an explicit checked dictionary, existing normalization/rules language behavior and `combining(context:global:)`.
- [x] Run filtered package tests to GREEN; preserve command, exit code and relevant test summary.
- [x] Review diff and obtain independent review. Commit only tested files and evidence.

## Following slices (not implemented by this plan)

1. Transactional policy snapshot: add strict settings snapshot in ReaderPreferencesStore; transport resolved expectation beside ProductionSourceExclusions through CandidateProvider, LocalProductionSlice and ColdFeedBootstrap; guard PublicationStore first/append in their transaction. Tests must reject stale policy atomically and cover semantic equality.
2. History ownership: additive RuntimeMigrations and binding store, Edition membership/checkpoints plus PublicationHistory restore overload. Tests must establish collision isolation, idempotent adoption, A→B→A, immutable old rows and stale-callback protection before AppComposition changes.
3. Native wiring and ambiguity recovery: separate logical/published keys, preserve active reader on global changes, generalize fixed-size recovery, replace R4 expected failures with normal assertions only after actual iOS GREEN. Validate future X/Y, relaunch and pt/en large-text tail geometry.

Each following slice needs its own exact-interface plan after inspecting current owner/transaction APIs; do not invent unused binding scaffolding in Task 1. Remaining F13 gates remain open.
