# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 053 · Vancouver, 02/11/2026, ~14:39 PST (UTC−08).** Parecer consultivo: **RELEASE NÃO APROVADA**. O OMP precisa fazer fetch de `monitor/architecture` e ler este documento; o monitor não notifica executores.

## 1. Memória, intervalo, autoridade e base

**Primeiro passo:** lida a [revisão 052](https://github.com/wsmontes/feedmine_v2/blob/c37cc5e65e6c45d4cb9d7d5583d7606654fb48e3/docs/reviews/ARCHITECTURE_MONITOR.md), commit do monitor **c37cc5e65e6c45d4cb9d7d5583d7606654fb48e3**, blob **3617f86f45bf7dafbf12ef1c6449d56b1c13ae05**. **Intervalo:** 02/11/2026, 12:46–14:39 PST, desde o HEAD Kiro **9498d165f146ee3c3a40118ff5ddc2c7e45b28b9**.

- **main e integração consolidada:** `2eca5b4f925141e5fdd3653e523c3663972d4310`; [comparação main](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...main) `identical`, zero commits/arquivos, inclusive docs. `integration/main-consolidated-20261030` no mesmo SHA.
- **Trabalho corrente:** `kiro/review-fixes-20261102` **9498d165 → 48a69cb95158c4a340620fd5517cb89c823c3e56**, [diff incremental](https://github.com/wsmontes/feedmine_v2/compare/9498d165f146ee3c3a40118ff5ddc2c7e45b28b9...48a69cb95158c4a340620fd5517cb89c823c3e56): **8 commits / 26 arquivos**, dos quais docs, evidências simuladas, Swift e testes. [Diff contra main](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...48a69cb95158c4a340620fd5517cb89c823c3e56): **39 commits à frente / 0 atrás**. Último commit **22:09:29 UTC (14:09:29 PST)**. Branch ainda sem PR, sem integração e sem candidata certificada.
- **PRs ativos:** #29, #30, #31, #33, #34, #35, #36, #37 permanecem draft, mesmos HEADs; issues #7, #18, #27, #32 abertas. Branches de release/integração antigas não foram tratadas como candidatas correntes. Branches consultadas nas três páginas da API (100 + 100 + 83).
- **CI:** **36 runs** no repositório; o último ainda é [#41497618804](https://github.com/wsmontes/feedmine_v2/actions/runs/41497618804), FAIL no intermediário **146915e5**, pacote **1.886 PASS / 2 FAIL / 4 skipped**, scripts FAIL (evidência já lida na 051–052). **Nenhum run do HEAD 48a69cb9.** Não executei XCTest, simulador, iPhone, archive nem benchmark neste monitor.

**Normas atuais relidas na main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/PRODUCT_INVARIANTS.md), [arquitetura](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/ARCHITECTURE.md), [B01–B06](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) e [render-ready](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/2026-10-17-render-ready-admission-rule.md). Normas atuais prevalecem sobre blueprints e análises de branch.

## 2. Resumo executivo: diversidade editorial melhora no modelo, mas o feed real segue sem prova

**Avanço verificável no código:** sequenciamento **v7** passa a escolher fontes com menor presença nas últimas 32 posições antes de aplicar a distância v6 por tipo/assunto/fonte. O artefato de [simulação v7](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/docs/reviews/evidence/2026-11-02-v6-sequencing-sim/v7_output.txt) registra **3/50** para um podcast entre 20 feeds de texto, contra **25/50** no v6; o resultado é **de uma simulação Python registrada no repo**, não de XCTest/Swift executado ou uso real. Versão explícita 7 preserva semântica de Editions anteriores, quando restauradas.

**Outra mudança de produto:** leitor local e Safari agora usam painéis `.pageSheet` com gesto de arrastar para fechar. Teto nominal de corpo de feed passou de **1 MB para 4 MB**, mantendo degraus menores sob pressão. Imagens declaradamente decorativas são rejeitadas antes da preparação. São hipóteses razoáveis de melhor acesso a podcasts longos, menos cards bloqueados por beacons e retorno mais natural à leitura; **nenhuma foi validada em aparelho**.

**Achado crítico de produto:** [estudo novo de cenários](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/docs/reviews/2026-11-02-kiro-feed-scenarios-study.md) descreve primeira publicação influenciada pelo primeiro feed que traz supply, oferta global examinada antes de filtros e memória de exposição por Edition. Confirmei os mecanismos abaixo, mas **não aceito toda conclusão do estudo como fato**: ele foi escrito sobre a main, ainda descreve v6/1 MB e simplifica a descoberta como “só top-120”, embora exista também travessia paginada. A melhoria v7 corrige a distribuição *dentro da oferta disponível*, não a amplitude da oferta, a runway nem o handoff físico.

**Decisão:** não promover release nem integrar às cegas; validar a branch no Mac e atacar o bloqueio do feed real antes de micro-otimizações.

## 3. Alterações verificadas, consequência e riscos

1. **v7 / 4 commits de análise e implementação editorial.** [4b34adfa](https://github.com/wsmontes/feedmine_v2/commit/4b34adfa019ad464438f886fb4176efb67ae0309) acrescenta [MaximumDistanceSequencing.swift:23–25, 59–115](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineEditorial/MaximumDistanceSequencing.swift#L59-L115), ativa [SelectionEngine.swift:178–185](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineEditorial/SelectionEngine.swift#L178-L185) e [AppComposition.swift:3670–3697](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/FeedMineApp/FeedMineApp/AppComposition.swift#L3670-L3697). Novos [SourceShareSequencingTests](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Tests/FeedMineEditorialTests/SourceShareSequencingTests.swift) cobrem corpus controlado, PD-4, reentrada tardia, versionamento e determinismo; **não executados**. **Risco P1:** a participação por fonte antecede os pesos da receita; em feed curado, fontes preferidas podem perder sua prioridade efetiva, apesar de [SelectionEngine.swift:129–185](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineEditorial/SelectionEngine.swift#L129-L185) ordenar inicialmente por peso. É consequência lógica do algoritmo, não regressão observada; requer teste ponderado.
2. **Documento de feed real / diagnóstico independente a qualificar.** [ColdFeedBootstrap.swift:238–260](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineComposition/ColdFeedBootstrap.swift#L238-L260) tenta publicar quando uma aquisição traz supply; o resultado não espera cobertura ampla de fontes. [ContentStore.swift:118–145](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMinePersistence/ContentStore.swift#L118-L145) pagina por recência global e [CandidateProvider.swift:104–167](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineEditorial/CandidateProvider.swift#L104-L167) aplica elegibilidade depois da leitura estrutural. **Fatos de mecanismo**; primeira tela dominada, fome de filtro ou retorno de histórias vistas entre contextos são **riscos/hipóteses a medir** com corpus. Correção à análise Kiro: [ReaderDiscoveryPool.swift:150–185](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineComposition/ReaderDiscoveryPool.swift#L150-L185) implementa travessia paginada além do `pool(limit:)` de compatibilidade; [AppComposition.swift:2714–2724](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/FeedMineApp/FeedMineApp/AppComposition.swift#L2714-L2724) usa de fato o seed top-120. **Não declarar catálogo limitado permanentemente a 120 sem traçar ambos os caminhos.**
3. **Corpo do feed 4 MB.** [262409b0](https://github.com/wsmontes/feedmine_v2/commit/262409b04268951238597b4daa17cdb0a7f1d1ff), [StageBudgetPolicy.swift:101–139](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineComposition/StageBudgetPolicy.swift#L101-L139): nominal 4 MB, pressão séria 500 KB/crítica 250 KB. [PipelineHeadroomTests](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Tests/FeedMineCompositionTests/PipelineHeadroomTests.swift) alterado, sem run. **Risco P2:** oito respostas de 4 MB = até 32 MB de *corpos brutos*, sem incluir parsing/objetos; medir pico real e feeds de 1–4 MB, especialmente podcasts, no Mac/iPhone.
4. **Imagens decorativas na origem.** [f84f5204](https://github.com/wsmontes/feedmine_v2/commit/f84f520443fcb6fe3231fca43c753e07745673bb), [SyndicationMediaLocator.swift:82–88, 122–154](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineSyndication/SyndicationMediaLocator.swift#L122-L154) e [SyndicationTranslator.swift:282–291](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineSyndication/SyndicationTranslator.swift#L282-L291): beacons/ícones não viram promessa de imagem; candidatos sem imagem real podem tornar-se cards de texto legítimos. **Risco P2:** marcadores por substring (`doubleclick`, `/avatars/`) podem excluir imagem válida; mudança no fingerprint de mídia pode criar nova revisão para item antigo. Testar falsos positivos e PD-1/PD-5.
5. **Leitura/Safari em sheet.** [48a69cb9](https://github.com/wsmontes/feedmine_v2/commit/48a69cb95158c4a340620fd5517cb89c823c3e56), [FeedMineApp.swift:1362–1380, 1405–1420, 1519–1543](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/FeedMineApp/FeedMineApp/FeedMineApp.swift#L1519-L1543), [ReaderHostTests.swift](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/FeedMineApp/FeedMineAppTests/ReaderHostTests.swift): delegado de dismissal e testes com double. **Risco P1:** o gesto real, Safari empilhado sobre texto, retorno ao mesmo card/offset e callbacks concorrentes ainda não foram observados em UIKit/XCUI. Os testes novos chamam diretamente o delegate; não provam o gesto.
6. **Documentos/evidências de branch:** [revisão de diversidade](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/docs/reviews/2026-11-02-kiro-randomization-diversity-review.md), [cenários](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/docs/reviews/2026-11-02-kiro-feed-scenarios-study.md), [lições V1](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/docs/reviews/2026-11-02-kiro-v1-lessons.md) e [handoff](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/docs/reviews/2026-11-02-kiro-review-handoff.md). **Fato:** análises e artefatos adicionados. **Limite:** não são ADRs normativos, nem prova de iPhone/bench; handoff declara Swift não compilado na máquina autora.

## 4. Achados priorizados e estado

### P0-01 — Handoff físico não prefixado ainda bloqueia continuidade (ABERTO; fato de código)

[FeedScreenStore.swift:304–329](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreenStore.swift#L304-L329) exige `nextIDs.starts(with: previousIDs)`; `[A,B,C] → [B,C,D]` não troca a lista física. O novo diff Kiro não toca esse arquivo. [RED #41375292900](https://github.com/wsmontes/feedmine_v2/actions/runs/41375292900) continua com prova geométrica pré-binding (9) e pós-binding (0). **Risco:** feed parece esgotar, janela visual diverge da lógica. **Owner:** writer nativo único, prova geométrica real pós-binding, commit/rollback durante gesto, âncora, offset e identidade; não resolver com botão de retry.

### P0-02 — Runway/B03 e candidata integrada não aceitos (ABERTO)

A v7 melhora **ordem de oferta pronta**, não produção contínua nem pixels locais. [B03–B05](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) não foram executados na Kiro/HEAD integrado. **Owner:** após handoff, corpus/driver/oráculo congelados, B03 por 30 min com consumo real, rajadas, observação de rede/scroll, B04 A→B→A, B05 offline/reabertura e salvos, sem reescrever benchmark.

### P0-03 — Redirect público→privado (ABERTO; ordem comprovada, exploração não comprovada)

[FeedDiscoveryTransport.swift:75–91](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L91) chama `session.bytes(for:)` antes de validar o host final. **Owner:** veto antes da conexão, teste registrando **zero conexões** a destino privado; não apenas rejeitar o corpo após o redirecionamento.

### P1-01 — Primeira impressão/diversidade e filtros podem mascarar a oferta (NOVO; mecanismo confirmado, impacto não medido)

A primeira fonte pronta pode iniciar publicação ([ColdFeedBootstrap](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineComposition/ColdFeedBootstrap.swift#L238-L260)); janela global antes do filtro ([ContentStore](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMinePersistence/ContentStore.swift#L118-L145), [CandidateProvider](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineEditorial/CandidateProvider.swift#L104-L167)). **Hipóteses:** primeira tela pouco diversa; filtro estreito sinaliza escassez enquanto existe conteúdo elegível mais fundo. **Owner:** trace primeira tela com chegadas escalonadas, fontes distintas nos primeiros 12/50, temas, taxa de elegibilidade por página, avanço do cursor; só alterar política se reproduzido. Não impor K fixo ou timeout mágico como substituto da runway adaptativa.

### P1-02 — v7 pode neutralizar pesos de preferências (NOVO; inferência direta do algoritmo)

[MaximumDistanceSequencing.swift:82–95](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineEditorial/MaximumDistanceSequencing.swift#L82-L95) elimina fontes mais usadas **antes** do desempate por ordem ponderada ([SelectionEngine.swift:129–185](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/Sources/FeedMineEditorial/SelectionEngine.swift#L129-L185)). **Fato:** prioridade de share antecede peso; **hipótese:** feeds curados ficam igualmente distribuídos apesar de pesos diferentes. **Owner:** fixture com 3+ fontes e pesos distintos, medir participação/relevância em 50–200 cards e PD-4; decidir conscientemente o equilíbrio, sem reescrever Editions v6.

### P1-03 — Nova sheet não tem prova de gesto/retorno (NOVO; testes adicionados, não executados)

[ReaderHostTests](https://github.com/wsmontes/feedmine_v2/blob/48a69cb9/FeedMineApp/FeedMineAppTests/ReaderHostTests.swift) exercitam chamadas diretas do delegate; o gesto UIKit real e a permanência da janela subjacente não foram observados. **Owner:** XCUI arrastar grabber do texto e do Safari, fechar por botão, retorno à mesma `PublicationCardID` e offset, site sobre texto, leitura rolada, reabertura offline.

### P1-04 — SQLite, persistência, offline e qualidade de integração (ABERTO)

[Run #41497618804](https://github.com/wsmontes/feedmine_v2/actions/runs/41497618804) tem dois REDs SQLite ainda não isolados; não há CI novo. O risco de remoção parcial de “Todos os salvos” continua: [AppComposition.swift:3138–3155](https://github.com/wsmontes/feedmine_v2/blob/9498d165/FeedMineApp/FeedMineApp/AppComposition.swift#L3138-L3155) escreve membership por caixa sem transação abrangente visível no chamador; falha na segunda escrita não foi injetada. Safari, catálogo PD-10, filtros A→B→A, persistência de salvos/coleções/fontes, 17 falhas históricas do app e reabertura offline permanecem sem aceite atual na mesma candidata. **Owner:** reproduzir SQLite, falha parcial, suíte pacote+app, jornadas reais e catálogo antes de integrar.

### P2 — Memória/decoração/assinatura/B06 (ABERTO/NOT_RUN)

Teto 4 MB, regras de imagem e sheet exigem perf/memória, regressões de apresentação e script de assinatura no Mac. B06 em iPhone físico **NOT_RUN**, archive/export/TestFlight não comprovados no HEAD. Não priorizar cosmética sobre P0/P1.

## 5. Provas mínimas no Mac — COMANDOS NÃO EXECUTADOS

```bash
git fetch origin main monitor/architecture kiro/review-fixes-20261102
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git rev-parse origin/main origin/kiro/review-fixes-20261102
git diff --check 9498d165f146ee3c3a40118ff5ddc2c7e45b28b9..48a69cb95158c4a340620fd5517cb89c823c3e56
git diff --stat 9498d165f146ee3c3a40118ff5ddc2c7e45b28b9..48a69cb95158c4a340620fd5517cb89c823c3e56
git worktree add --detach /tmp/feedmine-monitor-053 48a69cb95158c4a340620fd5517cb89c823c3e56
cd /tmp/feedmine-monitor-053
xcrun simctl list devices available
# Substituir UDID; registrar logs e xcresult, não aceitar PASS presumido.
xcodebuild test -scheme FeedMine-Package -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine053Package.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/FeedMine053Package.xcresult
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine053App.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/FeedMine053App.xcresult
bash scripts/test-export-signing-flags.sh
python3 -m unittest discover -s Tests/ReleaseScripts -p 'test_*.py' -v
# Reproduzir SQLite: PRAGMA index_list/index_xinfo/sqlite_master/EXPLAIN QUERY PLAN.
# Testar v7 com pesos de receita, PD-4, corpus de 1 podcast + 20 fontes, multi-oportunidade.
# Testar feed 1–4 MB e pico de memória de 8 respostas; falsos positivos de imagem.
# UI: grabber texto/Safari, mesma âncora e offset após dismiss, offline e gesto em scroll.
# Primeiro launch: fontes distintas nos 12/50 primeiros, chegada escalonada, filtros estreitos.
# Injetar falha na segunda remoção de bookmark membership em 2 caixas.
# Só depois de integração/handoff: B03 30 min, B04, B05, catálogo PD-10.
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
# B06 requer iPhone físico e registro; NOT_RUN não equivale a PASS.
```

**Aceitação:** prova black-box na mesma candidata de feed contínuo sem fim artificial, runway adaptativa, pixels locais antes de admitir, posição/identidade/scroll estáveis, filtros sem perda de trabalho, reabertura offline, estado pessoal durável, catálogo íntegro e redirects seguros. Nenhuma suíte isolada substitui a jornada.

## 6. Memória compacta para próxima revisão / owner

- **Histórico monitor:** 050 `992721f9` → 051 `525b1be2` → 052 `c37cc5e6` (blob `3617f86f`) → **053 (este documento)**.
- **Últimos SHAs verificados:** main/integration `2eca5b4f`; Kiro `b610bf7d` → `9498d165` → **`48a69cb9`** (agora 39 commits à frente da main); #35 `4f7040ef`, #36 `7afa2571`, #37 `b671147c`; oito PRs draft, issues #7/#18/#27/#32 abertas.
- **CI:** 36 runs; último `41497618804` FAIL no `146915e5`, 1.886 PASS / 2 FAIL / 4 skipped + scripts FAIL; sem run do `48a69cb9`. Host real #37: 9 provas pré-binding, 0 pós-binding.
- **Resolvido no código da Kiro, não aceito em release:** v7 implementa source-share antes de distância; teto nominal 4 MB; filtro de beacons; sheet com delegate; melhorias UX anteriores. Simulação v7 3/50 é artefato offline, **não teste Swift executado**.
- **P0 abertos:** handoff físico, B03/B04/B05 integrado, redirect pré-conexão. **P1:** primeira tela/oferta/filtros, pesos v7, gesto sheet, SQLite, salvos parciais, Safari/PD-10/offline. **P2:** memória 4 MB, falsos positivos de imagem, assinatura e B06.
- **Owner — mínima sequência:** (1) compilar/testar Kiro e isolar SQLite + teste v7 ponderado + UI sheet; (2) fechar handoff nativo e posição; (3) B03/experiência real + filtros + catálogo/offline numa candidata única. Não criar ownership, caches, filas, timers ou retries paralelos.
- **Handoff:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. O monitor é consultivo; o OMP deve ler ativamente.
