# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 040 · Vancouver, 30/10/2026, 09:45 PDT.** Parecer consultivo, **não** aprovação de release. O OMP deve fazer `git fetch origin monitor/architecture` e ler este arquivo; nenhum executor recebe notificação automática.

## 1. Janela de análise, SHAs e autoridade

**Memória persistente lida antes da análise:** [revisão 039](https://github.com/wsmontes/feedmine_v2/commit/2464c5dc8d40ffbf94eb46d745b6266a8886e279), blob `32107d2ee44040eed63008acd1d7eb81163acb24`. Última conferência sem avanço: 30/out, 07:39 PDT. **Janela incremental:** `product/nf04-tail-truth@0cc46a4d6a265a1d0b57f95208ad60b2bf51658b` → **`3db33a6df2af970c587668e1c17fbaf3735929fd`**; [diff 0cc46a4d…3db33a6d](https://github.com/wsmontes/feedmine_v2/compare/0cc46a4d6a265a1d0b57f95208ad60b2bf51658b...3db33a6df2af970c587668e1c17fbaf3735929fd): **1 commit à frente, 0 atrás; 22 arquivos** (2 Swift, 2 documentos de andamento/relatório, 1 plano, evidências JSON/.gz). Commit [`3db33a6d` — feat(f13): prepare an explicitly selected owned reading](https://github.com/wsmontes/feedmine_v2/commit/3db33a6df2af970c587668e1c17fbaf3735929fd). Não houve alteração na `main`.

**Referências conferidas por comparação direta:** `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48`; PR [#6](https://github.com/wsmontes/feedmine_v2/pull/6) `product/nf04-tail-truth@3db33a6d` (draft); PR [#8](https://github.com/wsmontes/feedmine_v2/pull/8) `chatgpt/render-ready-contract-red-01@83f05671` (draft); `product/reserve-20261024@a8814282`; `product/integrity-20261024@031b27d3`; `codex/feedmine-next-internal@d6a05266`; `release/build-56@cede37f6`; `integration/chatgpt@8203d439`; `integration/main-into-app-line@09a6e3a4`; `integration/candidate@1b990306` (**histórica, não candidata ativa**). Todas as demais comparações de refs listadas retornaram `identical`. PR #5 é documentação antiga, sem atividade nova. Consulta a PRs abertos/fechados e à issue [#7](https://github.com/wsmontes/feedmine_v2/issues/7); sem evidência de outra linha nova ativa. A comparação PR #6→PR #8 aponta **422 commits exclusivos de F13 e 17 de render-ready**; divergência não prova conflito de merge.

**Autoridade normativa relida em main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [regra render-ready de 17/out](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md). O contrato de experiência tem precedência sobre planos antigos, checkpoints de executor e número de testes.

## 2. Resumo executivo — consequência para o leitor

**Avanço real e restrito:** o F13 adicionou `SessionStore.prepareRetainedReading`, que prepara **uma Edition retida já pertencente ao binding lógico** a partir de um snapshot e checkpoint exatos, mantendo o leitor A e seu último ponto sob autoridade até a promoção de B. Isso fecha parte do risco identificado na revisão 039: selecionar uma Edition irmã *owned* sem escolher arbitrariamente a mais recente ou mover prematuramente A. A seleção explícita recusa dados obsoletos e não revoga uma preparação existente quando a validação falha.

**Não é uma jornada de recuperação pronta.** A API nova **não tem consumidor no host**; o relatório do próprio executor reconhece que ela não cobre Edition *unowned*, ausência de predecessor bound, adoção/namespace legado, singleton ausente, UI, More-menu/empty-reader, relaunch real e aceitação. O preview e as escolhas anteriores continuam invisíveis para o usuário. R4 completo **NÃO ACEITO**. Não converter GREEN do store em PASS do produto.

**Release NÃO APROVADA:** P0 render-ready, B03/runway e redirect privado continuam abertos. B03 mantém FAIL histórico; B06 NOT_RUN; B02/B04/B05/PD-10 não têm novo PASS integrado. Não houve execução de testes, benchmark, XCUI ou iPhone **por este monitor**.

## 3. Achados classificados: fato, hipótese, impacto e correção mínima

### P1-01 — Seleção explícita de Edition *owned*: avanço comprovado no store; host ainda não consome (PARCIAL)

**Fato de código:** [SessionStore+HistoryPreparation.swift:11–35](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/Sources/FeedMinePersistence/SessionStore%2BHistoryPreparation.swift#L11-L35) exige ativação predecessora atual, owner e Edition idênticos ao snapshot, membership, checkpoint owned exato e ausência de preparação selecionada para a mesma Edition; tudo dentro de `database.write`. [Linhas 38–75](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/Sources/FeedMinePersistence/SessionStore%2BHistoryPreparation.swift#L38-L75) reutilizam a preparação normal e fixam `explicitEditionID`; recusam correção silenciosa para Edition diferente. O `active_edition_id` e token apresentados não mudam na preparação; a promoção continua no mecanismo anterior. [Testes:28–105](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/Tests/FeedMinePersistenceTests/ReaderHistoryPreparationTests.swift#L28-L105) cobrem seleção A→B→A e último checkpoint de A, token antigo, leitura unowned, candidato oculto, snapshot/owner e checkpoint obsoletos, preservação de preparação preexistente. [Relatório do executor](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/docs/reviews/2026-10-30-f13-owned-reading-selection.md) declara explicitamente **sem consumidor nativo**.

**Consequência/risco (inferência):** melhora a segurança da futura seleção de histórico irmão já owned, mas não oferece a escolha ao leitor. Uma UI conectada prematuramente a esta API para leituras unowned ou sem ativação atual pode falhar ou ocultar uma leitura recuperável. **Owner:** ligar este primitivo ao reader/associação existente somente no cenário owned; para unowned/singleton ausente, completar adoção/isolamento e revalidação antes de expor seleção. Provar A→B→A com último offset, cancelamento, rollback e falha de gravação; nenhum segundo owner, fila ou restore paralelo.

### P1-02 — Recuperação ambígua e transições de navegação ainda incompletas (ABERTO)

**Fato estático anterior, sem modificação no diff atual:** [AppComposition.swift:36–117](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/FeedMineApp/FeedMineApp/AppComposition.swift#L36-L117) tem reader local de recuperação; [2270–2336](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/FeedMineApp/FeedMineApp/AppComposition.swift#L2270-L2336) tem escolha transacional, mas a UI não mostra preview nem ações (limitação admitida nos relatórios F13). [selectContext:1142–1164](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/FeedMineApp/FeedMineApp/AppComposition.swift#L1142-L1164), [activateSavedPreset:1321–1360](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/FeedMineApp/FeedMineApp/AppComposition.swift#L1321-L1360) e [replaceSession:2805–2825](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/FeedMineApp/FeedMineApp/AppComposition.swift#L2805-L2825) conservam caminhos que encerram A antes de B estar pronto. **Hipótese de regressão:** falha de B, troca rápida ou relaunch offline pode deixar tela vazia/perder posição. **Owner:** completar o handoff preservador nos caminhos de navegação pertinentes, ligar preview/choices à UI existente e provar em simulador com processo encerrado/reaberto offline, pt/en/XXXL, duas Editions irmãs e singleton ausente. **Status:** R4 subset NF03 com GREEN registrado anteriormente; **R4 completo não aceito**.

### P0-01 — Admissão render-ready ainda violada (ABERTO)

**Fato estático:** [FeedSession.swift:437–485](https://github.com/wsmontes/feedmine_v2/blob/83f05671/Sources/FeedMineRuntime/FeedSession.swift#L437-L485) mantém história inteira na projeção, mas decodifica pixels só perto da âncora; [FeedScreenStore.swift:137–161](https://github.com/wsmontes/feedmine_v2/blob/83f05671/Sources/FeedMineUI/FeedScreenStore.swift#L137-L161) entrega a lista à UI. O próprio [PR #8](https://github.com/wsmontes/feedmine_v2/pull/8) admite RED. Contraria [admissão obrigatoriamente render-ready](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md). **Hipóteses de regressão:** filtrar IDs só na view desloca scroll; decodificar 750+ imagens simultaneamente aumenta RAM. **Owner:** separar história durável de janela de apresentação já pronta na fronteira Runtime→Presentation existente, preservar IDs/offset, provar 750→1→750 sem placeholder ou readmissão incompleta e sem fim falso; integrar F13 no mesmo SHA.

### P0-02 — Continuidade adaptativa B03 ainda sem aprovação integrada (ABERTO)

**Fato:** nenhum B03 novo acompanha o commit. O FAIL histórico (~5,70 s de pausa) não virou PASS. [Benchmark B03](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L90-L112) exige 30 minutos de consumo real a 1 card/s com rajadas de 3/s e zero pausas visíveis ≥1 s por falta de runway. **Owner:** executar corpus/driver congelados no app real após integração; registrar cards prontos/admitidos, supply, taxa de consumo, eventos monotônicos, fontes novas e frame/scroll; rodar B04/B05 no mesmo build. **Não** usar teste de persistência como prova de supply contínua.

### P0-03 — Redirect privado validado depois do contato potencial (ABERTO)

**Fato estático:** [FeedDiscoveryTransport.swift:75–102](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L102) valida host inicial, chama `session.bytes(for:)` (capaz de seguir redirect) e só depois examina host final. **Risco hipotético, sem exploração reproduzida:** destino privado pode ser contatado antes do veto. **Owner:** validar cada salto antes da conexão e provar público→privado com **zero conexões privadas**, sem retry/caminho alternativo.

### P2-01 — Evidência melhorou; cobertura continua limitada (ABERTO)

**Fato documental:** [relatório do commit](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/docs/reviews/2026-10-30-f13-owned-reading-selection.md) declara **46 testes focados, 0 falhas; 1.857 testes Swift macOS Debug, 0 falhas/1 ignorado; 33 testes nativos em simulador, 0 falhas** (20 ContentFilter + 13 FilterConfirmationBoundary). [JSON full](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/docs/reviews/evidence/2026-10-27-source-exclusions/recovery-owned-selection-full.json) informa `swift test --skip-build`, exit0 e ausência de interrupção por espaço; [JSON iOS](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/docs/reviews/evidence/2026-10-27-source-exclusions/recovery-owned-selection-native-tests.json) informa `xcodebuild test-without-building`, exit0, `.xcresult`, hashes de binários e escopo limitado; [manifesto](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/docs/reviews/evidence/2026-10-27-source-exclusions/recovery-owned-selection-manifest.json) guarda hashes de logs .gz. [RED](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/docs/reviews/evidence/2026-10-27-source-exclusions/recovery-owned-selection-red.json) exit1 por API ausente e [GREEN](https://github.com/wsmontes/feedmine_v2/blob/3db33a6d/docs/reviews/evidence/2026-10-27-source-exclusions/recovery-owned-selection-green.json) exit0. O build nativo foi feito sobre base `0cc46a4d` com patch de produção identificado por hash, não simplesmente o HEAD limpo; o relatório vincula os artefatos, mas o monitor **não reproduziu nem auditou integralmente os logs .gz/.xcresult**. Não somar execuções ou extrapolar para UI/relaunch. `get_commit_combined_status` retornou zero contexts e a consulta a workflows de PR retornou zero runs para `3db33a6d`; ausência de CI não invalida os artefatos locais, mas tampouco certifica o release.

**P2 de coordenação:** a descrição da PR #6 ainda inicia em `0cc46a4d`/1.855 testes, embora o HEAD agora seja `3db33a6d`/1.857; o documento de progresso foi atualizado. **Owner:** quando fizer o próximo handoff autorizado, atualizar o resumo da PR; este monitor **não edita PRs**.

### P1/P2 — Invariantes não certificadas na mesma árvore

**P1:** PD-4 alternância, PD-5/PD-9 imutabilidade visual, filtros sem destruir supply reutilizável, reserva/concor­rência, scroll e IDs, warm/offline, salvos/coleções/fontes, catálogo PD-10/INV-18, B02/B04/B05 continuam sem prova integrada recente. **P2:** custo de inventário, leitura independente de logs, medição física e B06. Não criar caches, timers, schedulers, retries, filas ou ownership paralelos para satisfazer testes locais.

## 4. Provas mínimas exigidas no Mac — NÃO EXECUTADAS PELO MONITOR

```bash
git fetch origin main monitor/architecture product/nf04-tail-truth chatgpt/render-ready-contract-red-01 release/build-56
git rev-parse origin/main origin/product/nf04-tail-truth origin/chatgpt/render-ready-contract-red-01 origin/monitor/architecture
git log --oneline 0cc46a4d6a265a1d0b57f95208ad60b2bf51658b..origin/product/nf04-tail-truth
git diff --check 0cc46a4d6a265a1d0b57f95208ad60b2bf51658b..origin/product/nf04-tail-truth
git diff --stat 0cc46a4d6a265a1d0b57f95208ad60b2bf51658b..origin/product/nf04-tail-truth
git worktree add --detach /tmp/feedmine-monitor-040 3db33a6df2af970c587668e1c17fbaf3735929fd
cd /tmp/feedmine-monitor-040
swift test --filter ReaderHistoryPreparationTests
swift test --filter ReaderHistoryBindingStoreTests
swift test --filter PublicationOwnedHistoryTests
swift test
xcodebuild -list -project FeedMineApp/FeedMineApp.xcodeproj
xcrun simctl list devices available
# Selecionar scheme e simulador reais; executar XCTest + XCUI, guardar .xcresult, logs e vídeo.
# Usar apenas driver e corpus B03/B04/B05 congelados; verificar opções do script antes de invocar:
test -x scripts/run-discovery-benchmark.sh && scripts/run-discovery-benchmark.sh --help
```

**Oráculos de experiência no MESMO SHA/build/corpus:** A visível enquanto B prepara; último offset A→B→A, tokens aposentados e falha/cancelamento; escolha owned e unowned com dois históricos irmãos e sem singleton; relaunch de processo sem rede; filtros e palavras globais sem reordenar história; 750→1→750 render-ready sem pulo; B03 por 30 min/rajadas e B04/B05, PD-4, reserva, dados pessoais e B06 físico. Guardar commit, build, corpus/hash, iOS/dispositivo, rede, timestamps, .xcresult, vídeo e trace monotônico. **Não mudar oráculos congelados.**

## 5. Memória compacta para a próxima execução

- **Monitor:** 035 `9cb92778` → 036 `6318fddb` → 037 `34b39a53` → 038 `33cedde0` → 039 `2464c5dc` → **040 (este arquivo)**. Último blob lido `32107d2e`. Histórico completo nos commits anteriores.
- **Últimos SHAs:** main `fb8e65ff`; F13 PR #6 **`3db33a6d`** (antes `0cc46a4d`); render-ready PR #8 `83f05671`; reserve `a8814282`; integrity `031b27d3`; next `d6a05266`; release/build-56 `cede37f6`; integration/chatgpt `8203d439`; integration/main-into-app-line `09a6e3a4`; candidate histórica `1b990306`; monitor anterior `2464c5dc`.
- **Resolvido/avançou nesta janela:** preparação explícita de Edition irmã **owned**, validação transacional de snapshot/owner/checkpoint/token e preservação de A; RED→GREEN e registros de testes. **Não** afirmar recuperação completa.
- **Pendências P0:** render-ready, B03/runway, redirect privado. **Pendências P1:** host/UI de recuperação, unowned/singleton ausente, navegação que fecha A antes de B, R4 completo/relaunch, integração PR #6/#8, filtros, scroll, reserva, dados pessoais, catálogo PD-10, PD-4. **P2:** artefatos de prova independentes, PR body defasado, B06 físico.
- **Gates:** R4 subset nativo GREEN registrado anteriormente; **R4 total NÃO ACEITO**; B03 FAIL histórico; B06 NOT_RUN; B02/B04/B05 sem novo PASS integrado; release NÃO APROVADA.
- **Próximo passo de maior valor:** integrar recuperação real à UI existente (owned/unowned com critérios e checkpoint), completar handoff sem tela vazia, integrar render-ready e provar B03 na árvore única. Corrigir redirect preventivo.
- **Handoff:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Monitor consultivo, sem mudança de código, main, testes, benchmarks, coordenação, issues ou PRs.
