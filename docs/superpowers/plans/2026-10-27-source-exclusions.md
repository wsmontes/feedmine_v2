# Source Exclusions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar exclusão durável explícita de fontes com publicação futura protegida, reversão e histórico intacto; manter a aceitação integral F13 aberta até suas jornadas completas.

**Architecture:** Settings JSON guarda identidades, Composition resolve aliases e alimenta o pipeline existente. A seleção retira memberships bloqueadas e o writer compara a política capturada dentro do commit. O runway reaproveita suas lanes para reconsiderar supply após mudança, sem trocar o leitor.

**Tech Stack:** Swift 6, SwiftUI, GRDB/SQLite; sem dependências novas.

**Spec:** `docs/superpowers/specs/2026-10-27-source-exclusions-design.md`.

## Global Constraints

- Não modificar migrações históricas, bench/corpus/driver/oráculo ou versões já congeladas.
- Não alterar contrato de mídia, teto da reserva ou alinhamento inputs × cardIDs.
- Não filtrar histórico/salvos, remover cartas nem inventar fonte por nome/URL.
- Source-only changes não entram em ContextKey nem criam Edition; preservar palavra contextual/global.
- Falha de leitura da regra não vira ausência de regra. Erro stale não vira falha de rede.
- Não distribuir build; validar capacidade antes de build iOS e preservar artefatos.

## Review Focus

- Origem canônica comum a A bloqueada e B permitida: atribuir B somente onde B pertence ao escopo (T2).
- Regra muda depois da seleção: writer recusa first Edition e append velhos sem avanço do cursor (T3/T4).
- Remover regra após o cursor passar pela fonte: reconsiderar desde a cabeça sem duplicar material (T4).
- Fonte removida/alias/importada: regra continua identificável/removível e não conflita por nome (T1/T2/T5).
- Switch com palavras globais: medir continuidade, não generalizar o caso de fonte para fechar F13 (T6).

## Workspace e estado

Base de desenho: `382edf73`. Tasks 1–3 implementadas e verificadas; tarefas 4–6 pendentes. Antes de executar,
verificar worktree/branch e estado atual. Reusar a branch de trabalho isolada se adequada; não copiar
build caches. Há pouco espaço; não abrir build iOS sem capacidade confirmada. Testes do pacote podem
reusar `.build/index-build` enquanto existir e couberem.

### Task 1: Regra durável e snapshot efetivo

**Files:** Create `Sources/FeedMineDomain/ReaderSourceExclusion.swift`; modify `Sources/FeedMineDomain/ReaderSettings.swift`; test `Tests/FeedMineDomainTests/ReaderSourceExclusionTests.swift` and `Tests/FeedMinePersistenceTests/ReaderPreferencesStoreTests.swift`.

**Interfaces:** Produces `ReaderSourceExclusion(sourceID: SourceID, displayName: String)`, `ReaderSettings.contentSourceExclusions: [ReaderSourceExclusion]` default `[]`, `ReaderSourceExclusionSnapshot(settings: ReaderSettings)` with `sourceIDs: Set<SourceID>` and `.unrestricted`. Snapshot includes only effective IDs (empty if master off); display names do not affect equality. Existing settings writes/readbacks persist the value without schema changes.

- [x] RED: old JSON decode returns `[]`; roundtrip preserves rule/name; duplicate SourceID collapses; two IDs named BBC remain distinct; master off masks but retains rules. Include `XCTAssertEqual(snapshot.sourceIDs, [])` when off and `XCTAssertEqual(before, renamed)` for name-only changes.
- [x] Implement normalized identity-based rules and optional old-data decoding; do not change signatures of existing ContextKeys.
- [x] GREEN: `swift test --scratch-path .build/index-build --disable-index-store --jobs 2 --filter 'ReaderSourceExclusion|ReaderPreferencesStore|ReaderSettings'`: new cases + existing cases pass.
- [x] Commit domain/settings change with test result.

### Task 2: One eligibility policy, correct surviving attribution

**Files:** Modify `Sources/FeedMineEditorial/CandidateProvider.swift`; create `Sources/FeedMineComposition/ReaderSourceExclusionPolicy.swift`; test `Tests/FeedMineEditorialTests/SourceExclusionSupplyTests.swift` and `Tests/FeedMineCompositionTests/ReaderSourceExclusionPolicyTests.swift`.

**Interfaces:** Consumes T1. Produces `ReaderSourceExclusionPolicy.sourceIDs(snapshot: ReaderSourceExclusionSnapshot, links: [String: ReaderLibraryStore.SourceLink]) -> Set<SourceID>` (includes each base ID plus verified alias IDs); provider overload adds `excludingSourceIDs: Set<SourceID>` default empty and preserves current scope/cursor behavior.

- [x] RED: A-only suppressed; A+B returns only B in principal scope B; context A cannot publish B; source-scoped aliases honor existing scope. For each, assert examinedCount/nextCursor unchanged. Assert candidate surviving sourceIDs equals `[B]` and its other fields equal original.
- [x] RED: imported/catalog identities, alias old/current both excluded, unknown identity excludes only itself; same display name does not merge rules.
- [x] Implement membership subtraction before selection. Context source scoping must be applied before subtraction; preserve current eligible-source restrictions and avoid empty-membership resurrection.
- [x] GREEN: `swift test --scratch-path .build/index-build --disable-index-store --jobs 2 --filter 'SourceExclusionSupply|ReaderSourceExclusionPolicy|CandidateProvider|ReaderFilterEligibility|SourceIdentityIndex'`: zero failures.
- [x] Commit policy/provider with tests.

### Task 3: Snapshot guard inside publication commit

**Files:** Modify `Sources/FeedMinePersistence/ReaderPreferencesStore.swift` (strict reader), `Sources/FeedMinePersistence/PublicationStore+Writing.swift`, `Sources/FeedMinePersistence/PublicationStore.swift` (errors), `Sources/FeedMinePublication/PublicationCoordinator.swift`; test `Tests/FeedMinePersistenceTests/PublicationSourceExclusionTests.swift`.

**Interfaces:** Consumes T1. Add optional `expectedSourceExclusions: ReaderSourceExclusionSnapshot? = nil` to createEdition/createInitialEdition/appendSegment public entry points and carry it through coordinator request values. Add `PublicationStoreError.staleSourceExclusions`. Writer decodes current preferences in its existing transaction and compares the effective snapshot before writing. Missing settings use `.standard`, unreadable settings throw. No nested database read from the transaction. Produces also `ReaderPreferencesStore.sourceExclusionSnapshot() throws -> ReaderSourceExclusionSnapshot`, backed by a strict internal projection shared with the writer; do not capture policy via tolerant `load()`.

- [x] RED: capture empty policy, persist A exclusion, try createInitialEdition and append with old expectation. Assert stale error, identical edition/segments/cards before and after; no partial first Edition. Add master off/on and name-only update cases.
- [x] Implement guard for all three writer entry paths, comparing semantic IDs only. Existing callers default to nil; production fiação in T4 must supply the guard.
- [x] GREEN: `swift test --scratch-path .build/index-build --disable-index-store --jobs 2 --filter 'PublicationSourceExclusion|PublicationCoordinator|SessionStore|EditedArticleRecurrence'`: zero failures.
- [x] Commit writer/coordinator with tests.

### Task 4: Production fiação, stale recovery and reconsideration

**Status:** build iOS aprovado e 9 ContentFilterTests executados no simulador; integração warm por nova composição, no-op vazio e 5 testes de produção aprovados. Controles/processo pt aprovados; publicação futura por gesto ainda aberta. Ver relatórios ios-validation e recovery-and-controls de 2026-10-28.

**Files:** Create `Sources/FeedMineRuntime/ProductionSourceExclusions.swift`; modify `Sources/FeedMineRuntime/InitialProductionSlice.swift`, `Sources/FeedMineRuntime/PendingMediaReconsideration.swift`, `Sources/FeedMineEditorial/CandidateProvider.swift` (shared projection), `Sources/FeedMineComposition/ReaderSourceExclusionPolicy.swift` (capture), `Sources/FeedMineRuntime/LocalProductionSlice.swift`, `Sources/FeedMineRuntime/RunwayController.swift`, `Sources/FeedMineComposition/FeedRunwayDriver.swift`, `Sources/FeedMineComposition/ColdFeedBootstrap.swift`, `FeedMineApp/FeedMineApp/AppComposition.swift`; add `Tests/FeedMineCompositionTests/SourceExclusionProductionTests.swift`, extend controller tests and `FeedMineApp/FeedMineAppTests/ContentFilterTests.swift`.

**Interfaces:** Consumes T1–T3. Add `RunwayController.noteSourceExclusionsChanged(scope: RunwayScope) throws` and `FeedRunwayDriver.noteSourceExclusionsChanged() async`. Controller invalidates prior local intent/completion, resets episode/head traversal under the same scope, and arms the existing fresh-supply opportunity; no new drain/scheduler. Driver snapshots policy from the existing settings DB, resolves aliases for provider/media windows and carries the original effective snapshot into publication. Cold bootstrap uses the same snapshot and commit expectation.

- [x] RED: rule changes with prepared work held at a barrier: old first/append rejected, cursor does not advance, existing reader scope/Edition/anchor/segments stay equal. New opportunity can publish B. Old completion must not overwrite new traversal progress.
- [x] RED: cursor already passed A; remove rule, notify policy fact, existing lane can publish A with new ID only if material was never published. Assert no duplicates after two more opportunities.
- [ ] RED: warm relaunch with rule restores published A unchanged but excludes new A; saved A still readable. Source-only edit never invokes session replacement. Cover empty source list as no-op.
- [x] Implement single snapshot per local opportunity and guard transport to first/append. Handle stale as reconsiderable local state, with no failure/retry timer invented. Do not silently skip a guard in media reoffer/head/cold paths.
- [x] GREEN: package production/controller tests; app ContentFilterTests compilados/executados separadamente (9/0, simulador iOS 26.5, Debug sem símbolos).
- [x] Commit runtime/composition wiring and tests (fc09ff88 e incrementos seguintes; correções do build iOS registradas no checkpoint atual).

### Task 5: Explicit source action, visible reversible rules and recovery

**Status:** incremento parcial: backend/store, seção removível pt/en, ação confirmada do catálogo e notificação de composição implementados; switch geral e recuperação de supply implementados/verificados no pacote; superfície/ação de importadas implementada; 9 testes app aprovados em iOS. Recuperação sem cartas coberta no pacote; com histórico usa chrome estável após RED de 117 pt. Jornada real pelo menu/editor/remoção e viewport aprovada em pt/en AX XXXL. Recuperação causal de supply e UX13 integral ainda pendentes.

**Files:** Modify `Sources/FeedMineUI/Settings/ReaderContentFilterView.swift`, `Sources/FeedMineComposition/ReaderContentFilterAdapter.swift`, `Sources/FeedMineUI/Sources/NodeSourcesView.swift`, source surface propagation (`SourceManagementView.swift`, `SourceManagementStore.swift` as needed), `FeedMineApp/FeedMineApp/FeedMineApp.swift`, `AppComposition.swift`, existing String Catalog; tests in `Tests/ArchitectureSmokeTests/ReaderContentFilterStoreTests.swift`, `Tests/FeedMineCompositionTests/ReaderContentFilterAdapterTests.swift` and app `ContentFilterTests.swift`.

**Interfaces:** Consumes T1/T4. Extend backend/state with `sourceExclusions: [ReaderSourceExclusion]` and `setSourceExclusions(_ rules: [ReaderSourceExclusion]) async throws`. Store adds/removes a known source rule; adapter writes only its settings field and notifies Composition before returning. Source UI receives `onExcludeSource` closure using existing row key/name; Composition resolves known authority to SourceID (no UUID entry, no name matching). Imported-source action uses its existing source surface/identity. Source-only callback invokes T4, not replaceSession.

- [ ] RED: adding A leaves selection/authority unchanged and states rule; removing A preserves word rules/templates; master off retains source list; rename/removal from catalog leaves understandable removable row. Simulated failed write restores durable state and shows error.
- [ ] Implement confirmation/action “Não publicar mais desta fonte”; existing filters show “Fontes excluídas”, remove action and master status. Add pt/en copy and stable AX identifiers. Add recovery action to source-filtered no-new-supply state without hiding historical cards or reporting network failure.
- [x] GREEN: UI-store/backend e app ContentFilterTests (9/0); importadas e autoridade catalog estabelecida testadas separadamente, nomes persistidos.
- [ ] Commit complete controls/fiação with validation scope stated.

### Task 6: End-to-end acceptance and current-state ledger

**Files:** Create `FeedMineApp/FeedMineAppTests/SourceExclusionJourneyUITests.swift`; evidence/report under `docs/reviews/` outside bench. Reuse fixture transport with independent labeled source A/B content, not benchmark corpus changes.

**Interfaces:** Consumes T1–T5. Produces case-by-case UX13 results with before/after publication sequences, candidate/build identity and screenshots/AX.

- [ ] RED/GREEN UI journey: publish A and B, exclude A by gesture, future publications B only while old full CardRecords/segments/saved A and anchor remain equal; remove rule and verify new A eligible; master off/on retains rules across relaunch and A→B→A. Test one canonical item shared by A/B.
- [ ] Exercise source action/section/recovery at pt/en and large type. Note ignored prompt or source-selection toggle creates no exclusion. Capture empty result with actual recovery target, not generic network state.
- [ ] Run existing keyword variants UX13-A/B alongside sources. Compare existing published sequence/history with words switched on/off; if current folding of globals into ContextKey violates R4, keep F13 open and record causal follow-up, not a weaker assertion. Source delivery is an increment, not a substitute for whole F13.
- [ ] Run full package once after final production edits; app tests and journeys on identified build. Cross B02/B04/B05 per PRD when capacity permits. Leave unavailable gates NOT_RUN/BLOCKED with actual cause; B03/B06 failures stand.
- [ ] Fresh whole-change review, fix actionable findings with RED/GREEN, preserve logs and source identities; commit. Do not publish a release.

## Self-review and handoff

Every design proof maps to T1–T6; domain/snapshot/coordinator names above are the interfaces later tasks consume.
Tasks 1–3 are complete; tasks 4–6 remain open. Native execution follows the user's autonomous-work instruction;
implementation should not dispatch per-task implementers. One final independent review remains required.

Current gates: the existing 9 iOS ContentFilterTests pass; an added R4 case records 8 strict known
issues (official 9 Passed / 1 ExpectedFailure), so word-history acceptance remains FAIL;
empty-list no-op and cold recovery preserve the association. Idle/provisional recovery renders without
a false search/end claim. Full package after AX grouping: 1777 tests, one skip, zero failures.
T6 controls/process and recovery editor/tail geometry now pass in pt/en AX XXXL.
Causal supply recovery, publication A/B/shared/context and word-history acceptance remain open.
Latest whole-change plus focused review found no confirmed P1/P2; final whole acceptance remains open. Standard benchmark
capacity guard remains 3 GiB. See docs/reviews/2026-10-28-f13-ios-validation.md.
The existing F13 keyword/history caveat is explicit in the design, T6, and final acceptance record; it is
not resolved by the source-only feature. This plan does not alter baseline criteria or authorize cleanup.

2026-10-28 recovery checkpoint: actual tail RED de 117 pt -> chrome action GREEN delta zero across five observations in pt/en AX XXXL; package 1777/1skip/0 and app 9/0 on identified final build. See docs/reviews/2026-10-28-f13-recovery-route.md.


2026-10-28 word-history finding: R4 integration FAIL. add/master-on lose presented reading and active
position; off/remove recover original baseline. Old 48 records/segments/save/context checkpoint intact.
Raw matrix: eight continuity assertions fail; strict individual expectations track them, never UX13 PASS.
Next causal follow-up must separate global publication policy from context criteria and preserve legacy
rule origins; no blind subtraction of globals from old Edition keys. See the word-history-r4 report.
