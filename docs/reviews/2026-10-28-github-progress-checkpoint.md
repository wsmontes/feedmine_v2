# GitHub progress checkpoint — 2026-10-28

## Atualização — integração nativa, 2026-10-30

Bindings/preparação agora consumidos pelo host, com promoção NF03 após drain/checkpoint e isolamento de namespaces. Mudanças globais preservam a associação apresentada. **Oráculo R4 conhecido passou com assertions ordinárias**, sem wrappers de falha esperada. Pacote completo: **1846 testes, um ignorado, zero falhas**. Nativo: **42 testes distintos, zero falhas**, revisão independente concluída. [Relatório e limites](2026-10-30-f13-native-history-binding.md).

F13/aceitação completa continuam abertos: recuperação explícita de ambiguidades com leitura anterior apresentada, política não resolvida, relaunch real e jornadas UI ainda pendentes. As seções abaixo registram checkpoints históricos e são supersedidas por esta atualização no escopo descrito.


## Atualização — preparação antes da troca de autoridade, 2026-10-29

O pipeline pode publicar/projetar uma candidata oculta sem retirar de A a autoridade de salvar posição. Promoção atômica, cancelamento, retomada explícita e fences de predecessor/Edition de base/token implementados. Revisão independente e followup concluídos. **1844 testes completos, um ignorado, zero falhas**; foco55/0 e teste frio adicional1/0 (adição posterior só em teste). [Relatório](2026-10-29-f13-reader-preparation.md).

A revisão nativa antes limitada por quota também foi concluída sem achados acionáveis. AppComposition ainda precisa consumir a preparação e resolver seleção/ambiguidades/namespace; R4 continua FAIL e aceitação iOS/UI/relaunch permanece pendente.

## Atualização — identidade lógica nativa, 2026-10-29

FeedAssociation separa critérios lógicos da identidade congelada. Corrigidos handoff pendente e confirmação desnecessária após editar apenas palavras globais; a lente pendente usa critérios contextuais originais. Os owners frio/ativo nativos agora capturam a política estrita de palavras por oportunidade. Prova real de primeira publicação, bloqueio/reversão futura e transições: **34 testes nativos distintos, zero falhas inesperadas**, incluindo o oráculo R4 com suas falhas esperadas mantidas. [Relatório](2026-10-29-f13-native-logical-identity.md).

R4 continua FAIL; reapplyReaderFilters ainda reconstrói o reader. Ownership/ativação nativa, ambiguidades e aceitação UI/relaunch permanecem pendentes. A tentativa de revisão independente desta etapa encontrou limite de uso e não produziu revisão. PR em rascunho.

## Atualização — inventário antes de ativação, 2026-10-29

Consulta somente leitura de todos os históricos raw/current-forward sem proprietário, com evidência de posição original resolvida pelo card e sem escolher automaticamente a Edition mais recente. Cobertura atual: **32 testes afetados, zero falhas**, revisão independente sem achados pendentes. Última suíte completa: 1829/um ignorado/0 no checkpoint anterior 589f3470. [Relatório](2026-10-29-f13-legacy-history-inventory.md).

A consulta ainda não está consumida na composição nativa. Handoff NF03, recuperação de ambiguidades e R4/iOS permanecem pendentes.

## Atualização — adoção legada, 2026-10-29

A adoção pode receber o checkpoint original e validar sua evidência durável na transação. A Edition real do card prevalece sobre a coluna inconsistente, preservando data/offset. Corrigida também falha de FK ao ativar card arquivado já retido no vínculo. Revisão independente concluída; suíte completa **1829 testes, um ignorado, zero falhas**. [Relatório](2026-10-29-f13-legacy-checkpoint-adoption.md).

A composição nativa ainda não usa este novo caminho. R4 permanece FAIL; recuperação de ambiguidades e aceitação iOS continuam pendentes.

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
