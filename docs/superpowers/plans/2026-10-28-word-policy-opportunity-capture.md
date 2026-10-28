# Word Policy Opportunity Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans, native execution.

**Goal:** Make cold/live publication owners capture strict current word snapshots and invalidate stale local traversal without replacing a reader.

**Architecture:** A Sendable ReaderWordExclusionPolicy value owns the immutable localized template descriptor, true contextual exclusions and existing database reference. Cold and live owners optionally receive this capture value, use the same snapshot for preparation/selection/commit and retain existing acquisition authority/scheduler.

**Tech Stack:** Swift/XCTest, existing Composition/Runtime/Persistence interfaces.

**Spec:** `docs/superpowers/specs/2026-10-28-global-word-continuity-design.md`.

## Constraints and review focus

No new reader or history identity. No change to acquisition authority or PD-4. Nil policy preserves existing callers. Strict errors must not become unrestricted publication. Semantic equality alone resets traversal; display labels and equivalent template choices do not. Cold retries stay within remaining local-window budget. Native AppComposition injection and history binding are separate pending integration, so this slice cannot claim R4 PASS.

## Task 1

Files: new Composition/ReaderWordExclusionPolicy.swift; FeedRunwayDriver.swift; ColdFeedBootstrap.swift. Tests: FeedRunwayDriverTests.swift and ColdFeedBootstrapTests.swift.

Interfaces:
- `ReaderWordExclusionPolicy(database:templates:context:languages:)`, with context default disabled and languages preferred; resolves template descriptors once. `capture() throws -> ReaderWordExclusionSnapshot` delegates to strict preferences snapshot.
- Optional default-nil `wordPolicy` parameter on both owner initializers.
- Driver tracks last effective exclusions for dedup only. Add `noteContentExclusionsChanged() async`; existing source notification forwards to it. Compare effective words and resolved sources, use existing runway noteSourceExclusionsChanged generation reset, clear pending measurement, schedule the existing late opportunity. Every local-slice opportunity strictly captures again; changes detected without notification also restart before preparation. Snapshot feeds structural and queued preparation plus request commit. Handle staleWordExclusions like staleSourceExclusions.
- Cold captures before choosing traversal cursor. Authority resets cursor when effective words change; request uses that exact snapshot. Handle staleWordExclusions with existing bounded restart path.

- [x] Add live word removal test adapted from actual source-removal journey, proving exhaustion, same Edition/anchor/checkpoint, one new publication, no duplicate and unchanged-policy no-op.
- [x] Add cold same-owner mask/removal test and preparation-race stale-policy retry test.
- [x] Run actual RED for absent APIs; implement, run focused owner tests plus existing pipeline tests to GREEN.
- [x] Independent review, diff check, evidence/provenance and local commit.

Next: pass the immutable capture policy from AppComposition using raw session criteria, then additive history binding/root continuity. Do not infer contextual word provenance from legacy frozen union keys. Actual iOS compilation and acceptance remain required for app injection.
