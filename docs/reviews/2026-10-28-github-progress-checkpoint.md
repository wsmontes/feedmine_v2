# GitHub progress checkpoint — 2026-10-28

## Atualização — histórico semântico, 2026-10-29

Restauração/salvamento por ownership e transporte pelos owners frio/ativo implementados e revisados. Suíte completa: **1824 testes, um ignorado, zero falhas**; foco final: 145/0. Migração aditiva preserva anchors arquivados/desconhecidos e limpeza explícita, sem remover FKs. [Relatório](2026-10-29-f13-owned-semantic-history.md).

R4 nativo continua FAIL. Injeção na composição nativa, recuperação de históricos ambíguos e aceitação iOS/relaunch/UI permanecem pendentes. PR em rascunho.

## Atualização — 2026-10-29

O transporte de ownership pelo coordenador/Runtime foi implementado e revisado. A revisão independente pendente foi retomada: um P2 de limpeza após rollover foi reproduzido e corrigido em fdbd4c10; o revisor confirmou a resolução.

Validação atual: suíte completa do pacote Swift em macOS Debug, **1813 testes, um ignorado e zero falhas**. O teste ignorado exige o catálogo de referência externo. A primeira execução completa revelou inventários de schema antigos; foram atualizados explicitamente, com igualdade exata e preservação das verificações anteriores.

Relatório atual: [2026-10-29-f13-owned-publication-pipeline.md](2026-10-29-f13-owned-publication-pipeline.md). R4 no host continua FAIL; faltam restauração semântica, injeção nos owners/composição nativa, recuperação de históricos ambíguos e aceitação iOS/relaunch/UI. O PR permanece em rascunho.

## Checkpoint original — 2026-10-28

User requested publishing local progress. Branch: `product/nf04-tail-truth`; base: remote `main`. Publish the accumulated branch as a **draft**, preserving its history without merging it into main or rewriting remote commits.

Recent progress:

- Source-exclusion controls and fixed-size recovery route, with previous actual iOS control/tail evidence recorded in their reports.
- Strict effective-word snapshots, transactional publication guards, selection/preparation/coordinator transport and reversible media reoffer.
- Cold/live opportunity capture and semantic traversal reset.
- Additive logical-context ownership of frozen Editions, safe legacy adoption and collision isolation.
- Atomic first-publication ownership/checkpoints, independent owned positions and activation-token fencing.

Latest combined affected-suite validation: **243 tests, zero failures** on macOS Debug; not a new full-package or actual iOS run. Evidence: `docs/reviews/2026-10-28-f13-owned-reader-checkpoints.md` and adjacent manifests/log hashes. Earlier reports retain the exact scopes of their own validations.

R4 remains **FAIL in the native host**. Remaining work includes expectation transport, owned semantic restoration, native composition/history wiring, legacy ambiguity recovery, relaunch/UI acceptance and other F13 gates. B03 remains FAIL and B06 NOT_RUN. B02/B04/B05 and broader acceptance are not certified by this checkpoint.

The last independent-review attempt returned no review due to usage limits; the latest checkpoint received local review/tests and remains a draft. The independent reviews completed for preceding slices are documented separately.

Unrelated untracked `capacity-ready.json` is intentionally excluded. Historical databases, local products and gitignored evidence are not being uploaded merely because they exist; versioned reports contain the evidence/restore references. The GitHub PR description should link this file and identify the published head.
