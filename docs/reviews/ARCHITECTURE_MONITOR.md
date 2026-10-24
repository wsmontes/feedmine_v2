# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 025 · Vancouver, 24/out/2026, 01:43 PDT.** Canal consultivo `monitor/architecture`. O OMP deve fazer fetch e ler este arquivo; nenhuma notificação automática.

## Base e intervalo verificado

Anterior: [monitor 024](https://github.com/wsmontes/feedmine_v2/commit/918a2c8bd6abd210176bc7cb42cb59a4ff71b7b7), 23/out 23:39 PDT. Intervalo: 23/out 23:39 → 24/out 01:43 PDT. **Novidade relevante:** a linha de trabalho `codex/feedmine-next-internal@2d430c5e7f656c78fb46b4a0e2220153b0a56df7` foi identificada e examinada; HEAD de 23/out 23:57 PDT. A revisão anterior acompanhava só as linhas 54. Esta branch descende de `3eee19350ccb3fdf8392162694620d875fe041fa` por **138 commits** e inclui `3c5bdc11f74def3998e2f1710634df15eceaf421` (commit `chore(ios): prepare TestFlight build 55`, 23/out 20:59 PDT), mais **15 commits posteriores**: [diff 54→linha atual](https://github.com/wsmontes/feedmine_v2/compare/3eee1935...2d430c5e), [diff build 55→linha atual](https://github.com/wsmontes/feedmine_v2/compare/3c5bdc11...2d430c5e). **SHA do código preparado para build 55 agora identificado; identidade binária distribuída/TestFlight ainda depende de recibo/archive verificado.** Não atribuir os 15 commits posteriores ao aplicativo no aparelho.

`main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48` não avançou desde 024 (compare: identical). Linhas 54 `15d8bbbc` (mídia), `3eee1935` (validação), `145d12a3` (mídia/release) e `77e9f7d1` (posição) também estão idênticas aos SHAs registrados. PR [#5](https://github.com/wsmontes/feedmine_v2/pull/5) permanece aberto, HEAD `5b252eaa`; contém código herdado e não deve ser mesclado como docs-only. Branches `omp/u1`, `omp/u2`, `fix/filter-confirmation-boundary` e `release/export-signing-flags` têm commits de 10–17/out, não são trabalho corrente. A branch `codex/feedmine-next-internal` é a nova linha corrente relevante; `main` permanece documental.

Normas relidas em `main`: [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), além de [NF-01–NF-16 na linha atual](https://github.com/wsmontes/feedmine_v2/blob/2d430c5e/docs/product/NOVAS_FRENTES_PARA_O_CODEX.md). Nenhum XCTest, simulador, iPhone ou benchmark foi executado **por este monitor**.

## Resumo executivo — consequência de produto

**A revisão 024 subestimava o avanço técnico já existente na linha 55.** O código preparado para a build 55 contém nova persistência de adiamentos **por Edition**, rotação durável e testes de A→B→A/reabertura. Isso resolve estaticamente o defeito estrutural de sobrescrever a Edition A ao registrar B, antes classificado P1. A retenção editorial também deixa o adiamento elegível para oportunidades futuras. Entretanto, o produto **ainda foi observado alcançando a cauda no iPhone** (relato do dono, não medição B03), e o código posterior à 55 ainda não foi certificado nem distribuído.

A linha pós-55 implementa uma medição NF-05 **demanda de aquisição → primeiro receipt de publicação**, incluindo rede/preparo, em `RunwayController` + `FeedRunwayDriver`; evita uma segunda política/scheduler. Há teste forte com HTTP e preparação suspensos e teste de cancelamento/scope. O próprio registro executor informa 120 testes focais e 1.645 testes Swift, 1 skip e 0 falhas; **evidência declarada no commit/documento, não execução independente nem PASS de B01–B06**. O P0 de segurança de redirecionamentos segue intacto na linha atual. O contrato congelado do benchmark exige cautela: o driver B05 foi alterado e seu hash regravado entre 54 e 55, exigindo revisão independente e reexecução, nunca herdar um PASS antigo.

## Achados com prioridade, prova e orientação mínima

### P0 produto — runway ainda pode acabar antes de chegar material (observação física; causa aberta)

**FATO relatado:** build 55 rola suavemente, mas a cauda aparece antes da reposição; [NF-01/NF-05](https://github.com/wsmontes/feedmine_v2/blob/2d430c5e/docs/product/NOVAS_FRENTES_PARA_O_CODEX.md#L152-L188). **FATO estático novo:** os [15 commits pós-55](https://github.com/wsmontes/feedmine_v2/compare/3c5bdc11...2d430c5e) alteram `RunwayController`, `FeedRunwayDriver` e testes para medir a duração até publicação. [RunwayController.swift:242–290](https://github.com/wsmontes/feedmine_v2/blob/2d430c5e/Sources/FeedMineRuntime/RunwayController.swift#L242-L290), [RunwayController.swift:539–549](https://github.com/wsmontes/feedmine_v2/blob/2d430c5e/Sources/FeedMineRuntime/RunwayController.swift#L539-L549), [FeedRunwayDriver.swift:447–486](https://github.com/wsmontes/feedmine_v2/blob/2d430c5e/Sources/FeedMineComposition/FeedRunwayDriver.swift#L447-L486), [teste forte:658–716](https://github.com/wsmontes/feedmine_v2/blob/2d430c5e/Tests/FeedMineCompositionTests/FeedRunwayDriverTests.swift#L658-L716). **HIPÓTESE:** medir latência real permitirá pedir aquisição mais cedo; não prova que o primeiro ciclo de rede seja antecipado. A primeira aquisição ainda começa com p95 local e o receipt não mede admissão/visibilidade UI. **Orientação:** medir na MESMA candidata demanda→HTTP→oferta→mídia→receipt→admissão visível, sob consumo rápido/lento/parado e rede suspensa, preservando scroll local. Não aumentar lotes ou adicionar timer/cache para disfarçar a cauda.

### P0 segurança — redirect pode conectar antes da recusa (aberto, comprovado estaticamente)

[FeedDiscoveryTransport.swift:69–101](https://github.com/wsmontes/feedmine_v2/blob/2d430c5e/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L69-L101) continua com `URLSession.bytes(for:)` antes de validar host final; nenhum delegate pré-redirecionamento foi identificado. **FATO:** validação pós-conexão. **HIPÓTESE:** destino vedado pode receber conexão em redirect automático (SSRF). **Owner:** bloquear cada hop antes de conexão e validar destino efetivo, sem confiar só em nome textual. **Prova:** servidor local vedado contabiliza zero requests após redirect; caso público permitido funciona.

### P1 resolvido estaticamente — adiamento A→B→A não sobrescreve mais Edition A

[MediaDeferralStore.swift:32–49](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/Sources/FeedMinePersistence/MediaDeferralStore.swift#L32-L49) usa conflito por `(edition_id, origin_record_id)`; [migração v2:665–693](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/Sources/FeedMinePersistence/RuntimeMigrations.swift#L665-L693) copia a associação antiga; [testes:50–64,124–144](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/Tests/FeedMinePersistenceTests/MediaDeferralStoreTests.swift#L50-L64) cobrem duas Editions e reabertura. **FATO:** o antigo esquema de uma Edition por origem foi substituído e testes discriminantes foram adicionados. **Limite:** não equivale a jornada UI B05 nem prova de migração em banco real da build distribuída. **Orientação:** executar migração de banco antigo, A→B→A com imagem tardia e relaunch offline, verificando publicação e posição.

### P1 reclassificado — retenção editorial mantém elegibilidade, mas latência da página 33 não está provada

[PendingMediaReconsideration.swift:118–155](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/Sources/FeedMineRuntime/PendingMediaReconsideration.swift#L118-L155) lê página rotativa de 32; [LocalProductionSlice.swift:154–195](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/Sources/FeedMineRuntime/LocalProductionSlice.swift#L154-L195) só esquece o efetivamente publicado, não o retido; [testes:1070–1114,1164–1204](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/Tests/FeedMineRuntimeTests/LocalProductionSliceTests.swift#L1070-L1114) verificam reoferta em oportunidades posteriores. **FATO:** a perda permanente por `ready.isEmpty` da linha 54 não se aplica mais; a chance é preservada. **RESIDUAL/HIPÓTESE:** 33º pronto atrás de 32 retidos não é necessariamente examinado na mesma oportunidade, e a latência de nova oportunidade sob runway saudável não foi medida. **Orientação:** testar tempo até 33º com única transição e cadence foreground, sem exigir varredura ilimitada nem declarar starvation sem reprodução.

### P1 UX — Concluído do filtro ainda aguarda reconstrução na 55

[FilterSheetView.swift:313–321](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/Sources/FeedMineUI/Filters/FilterSheetView.swift#L313-L321) aguarda `store.apply()` antes de `onDone()`; [AppComposition.swift:1007–1026](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/FeedMineApp/FeedMineApp/AppComposition.swift#L1007-L1026) grava duravelmente e aguarda `replaceSession()`, que aguarda [`next.launch()`:2183–2207](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/FeedMineApp/FeedMineApp/AppComposition.swift#L2183-L2207). **FATO:** encadeamento de espera confirmado no código da 55; **HIPÓTESE:** causa exata da lentidão percebida no aparelho. **Owner:** feedback no toque, commit durável honesto e fechamento sem esperar aquisição/launch remoto; manter erro de gravação visível. **Prova:** launch/HTTP suspenso após commit, falha de persistência, A→B→A e dois toques rápidos.

### P1 integridade de aceitação — driver B05 e manifesto congelado mudaram entre 54 e 55

**FATO verificado por diff:** `FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift` ganhou ~362 linhas e alterou o caminho B05, substituindo o antigo percurso via “Salvos” por configuração de segunda fonte/contexto via UI, navegação A→B→A e novos waits. [Comparação 54→55](https://github.com/wsmontes/feedmine_v2/compare/3eee1935...3c5bdc11); [driver B05:248–390](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift#L248-L390), [B05:894–980](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift#L894-L980). `bench/EVALUATOR.sha256` trocou o hash deste driver de `08739fd3…` para `e411f8fc…`; os hashes de `bench/run.sh`, `oracle.py`, `serve.py`, `build_corpus.py`, `expand.py` ficaram iguais. **RISCO:** embora as mudanças pareçam corrigir uma prova antes vacuamente verde, não são a MESMA régua congelada: [contrato §1–2](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L15-L23) exige avaliador independente, sem alteração para favorecer a candidata. **Orientação:** auditar o diff como reparo de falso verde, comparar requisitos B05 antes/depois e preservar artefatos/hashes de ambos; reexecutar B05 com referência aprovada, sem transportar PASS histórico. Não alterar oráculos para obter verde.

### P1/P2 residuais — produto e release

**P1:** posição/âncora ±1 pt e D4 não certificados na candidata atual; salvos V1→V2, diversidade, vídeo/YouTube e web original como destino padrão ainda exigem jornada real; sem declarar paridade com V1 por presença de modelos. **P2:** [índice novo](https://github.com/wsmontes/feedmine_v2/blob/3c5bdc11/Sources/FeedMinePersistence/RuntimeMigrations.swift#L665-L679) agora acompanha `edition_id, turn_at, origin_record_id`; custo de 10k/100k não foi medido por este monitor. Outros P1 de 023/024 (primeira tela, preferências concorrentes, aliases, timestamps duplicados) permanecem **não encerrados**, mas não devem ser repetidos como defeitos confirmados na 55 sem verificar caminhos atuais.

## Release — não certificar pelo número de testes

O documento NF-05 da linha atual relata **120 regressões focais e 1.645 testes Swift (1 skip, zero falhas)**, além de mutação temporária do código revertida; são **relatos de execução do executor**, não verificação deste monitor. [Registro: NF-05](https://github.com/wsmontes/feedmine_v2/blob/2d430c5e/docs/product/NOVAS_FRENTES_PARA_O_CODEX.md#L290-L324). A mesma fonte declara **B01–B04/App180/D4/surface live NOT_RUN**, B06 NOT_RUN e B05 histórico não transferível. Guard `bench/run.sh:130–134` exige 3 GiB livres; executor relatou ~0,9 GiB e **não contornou** o guard. Esta é uma condição de máquina reportada, não medição independente. Nenhum novo TestFlight pós-55 demonstrado; commit pós-55 não é release. **P0 certificação:** B01–B06 e PD-10 da mesma árvore/build continuam sem matriz verificável.

## Handoff: comandos/provas no Mac

```bash
git fetch origin main monitor/architecture codex/feedmine-next-internal codex/direction-validation-20261021
git log -1 --format='%H %cI %s' origin/codex/feedmine-next-internal
git log --oneline 3c5bdc11..origin/codex/feedmine-next-internal
git diff --stat 3c5bdc11..origin/codex/feedmine-next-internal
git diff 3eee1935 3c5bdc11 -- bench/EVALUATOR.sha256 FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift # auditar B05
git diff --check 3c5bdc11..origin/codex/feedmine-next-internal
# No checkout do candidato, após verificar espaço livre sem bypass do guard:
swift build
swift test
swift test --filter 'FeedRunwayDriverTests|RunwayControllerTests|MediaDeferralStoreTests|LocalProductionSliceTests'
# Rodar B01–B05, App180, D4 e surface live; B06 no iPhone físico,
# todos na MESMA árvore, corpus/oráculos autorizados, com logs/xcresult/hash.
```

Provas decisivas: (1) obter archive/TestFlight que vincule build 55 a `3c5bdc11`; (2) trace causal e2e até **admissão UI** e cauda sob consumo; (3) redirect vedado com zero requests; (4) A→B→A/relaunch/migração de deferral; (5) paginação editorial com 33º e tempo de oportunidade; (6) filtro com launch suspenso; (7) auditoria independente do driver B05 e execução congelada. Preservar identidade/posição, fontes/coleções/salvos e supply local; não criar scheduler, cache, fila, timer ou retry paralelo.

## Memória compacta / SHAs

Histórico: monitor 014 `b7d385a9`; 023 `039bf1d5` (consolidou 015–022); 024 `918a2c8b` (`main@fb8e65ff`, NF-01–16). Linha 54 `3eee1935`, mídia `15d8bbbc`, mídia/release `145d12a3`, posição `77e9f7d1`. **025:** `main@fb8e65ff` e linhas 54 inalteradas; linha 55 identificada `3c5bdc11`; trabalho pós-55 `codex/feedmine-next-internal@2d430c5e` (15 commits após 55). A→B→A **corrigido estaticamente** na 55; retenção editorial **preserva elegibilidade**, sem prova de latência; NF-05 pós-55 **parcial e não distribuído**; SSRF e filtro seguem abertos; B05 driver/hash alterados; certificação integral ausente.

**Handoff OMP:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Monitor consultivo; nenhuma alteração em main, código, testes, benchmark, scripts, coordenação, issues ou PRs.
