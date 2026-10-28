# Word Publication Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution in the existing checkout.

**Goal:** Reject stale effective word policies atomically at first/append publication, without changing frozen context identities.

**Architecture:** Domain owns a resolved-template value and deterministic effective snapshot. Composition translates localized catalogue data into that value. Persistence re-resolves durable settings against the same immutable descriptor in the publication transaction. Existing overloads remain compatible with nil expectations; native opportunity capture is a subsequent integration task, not a claim made by this slice.

**Tech Stack:** Swift, GRDB/SQLite, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-28-global-word-continuity-design.md`.

## Constraints and review focus

Published rows and context identities stay immutable; PD-4 and benchmark reserves stay unchanged. Context words survive master-off. Corrupt preferences and missing active templates throw. Equivalent effective unions remain publishable. Snapshot carries resolved words, never UI labels or locale-dependent callbacks; locale resolution happens once in Composition. No Persistence → Composition dependency.

## Task 1: shared snapshot and transaction guard

Files: new `Sources/FeedMineDomain/ReaderWordExclusionSnapshot.swift`; existing `ReaderContentFilterPolicy.swift`, `ReaderPreferencesStore.swift`, `PublicationStore.swift`, `PublicationStore+Writing.swift`; new `Tests/FeedMinePersistenceTests/PublicationWordExclusionTests.swift`.

Interfaces:
- `ReaderWordTemplateRules(key: String, rules: [String])`: Hashable/Sendable normalized words.
- `ReaderWordExclusionSnapshot(settings: ReaderSettings, templates: [ReaderWordTemplateRules], context: ReaderContentExclusions = .disabled) throws`: immutable descriptor/context/effective `exclusions`; nested `ResolutionError` duplicateTemplate/missingTemplates. `matches(settings:) throws -> Bool` compares effective union under the same descriptor. Disabled master skips catalogue validation. Duplicate validation is deterministic and includes unselected keys when templates are selected.
- Composition strict resolver delegates to this domain implementation; preserve its existing public error name via typealias.
- `ReaderPreferencesStore.wordExclusionSnapshot(templates:context:) throws` uses strict settings_json decoding, with absent row meaning standard preferences. Transaction helper reads the same settings. Refactor existing source snapshot to share strict decoding.
- Add optional default-nil `expectedWordExclusions` to the four guarded PublicationStore overloads (create, initial create, append, tail-checked append), propagate through private append and validate at the start of each transaction. Throw `PublicationStoreError.staleWordExclusions` on changed semantic policy; decoding/resolution errors propagate. Nil preserves legacy callers.

- [x] Write atomic rejection tests for first/initial and both append paths; normal assertions prove no partial rows or checkpoint changes. Add equivalent policy, contextual overlap/master, missing template and corrupt-settings tests.
- [x] Run filtered package tests to actual RED (missing interfaces), inspect errors.
- [x] Implement shared resolver/snapshot and guards; run new persistence tests plus existing source-policy and Composition policy tests to GREEN.
- [x] Independent review, diff check, record commands and code hashes, commit tested slice.

## Next integration task

PublicationCoordinator First/Append requests must carry and forward the optional snapshot. LocalProductionSlice and cold bootstrap must carry it through preparation/provider selection/commit. Existing runtime owner captures current policy and invalidates stale prepared work. This requires the separate history-ownership plan before replacing folded keys in AppComposition; do not switch production identity or remove R4 expected failures prematurely.
