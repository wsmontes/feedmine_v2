# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 050 · Vancouver, 01/11/2026, ~18:45 PST (UTC−08).** Parecer consultivo, **não certificação de release**. O OMP deve executar `git fetch origin monitor/architecture` e ler este arquivo: não existe notificação automática aos executores.

## 1. Base, memória e escopo

**Memória persistente lida primeiro:** [revisão 049](https://github.com/wsmontes/feedmine_v2/blob/f563ca6d06e095c23ee613da6772ed99e55d889c/docs/reviews/ARCHITECTURE_MONITOR.md), branch `monitor/architecture@f563ca6d06e095c23ee613da6772ed99e55d889c`, blob anterior `1d5a22497f16e80240ea09127bb85ffa17147d93`. **Intervalo incremental:** desde a revisão 049 (31/out ~11:39 PDT) até 01/nov ~18:45 PST, incluindo a mudança de horário de verão. A consulta de CI cobriu os runs novos até [#41375292900](https://github.com/wsmontes/feedmine_v2/actions/runs/41375292900), encerrado 01/nov ~18:09 PST (02/nov 02:09 UTC); PR #37 atualizado 01/nov ~18:20 PST.

**Main:** `2eca5b4f925141e5fdd3653e523c3663972d4310` — [compare anterior...main](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...main) retornou **identical: zero commits, zero arquivos**, inclusive docs. `integration/main-consolidated-20261030` continua no mesmo SHA. Branches antigas `integration/candidate`, `integration/main-into-app-line`, `integration/chatgpt`, `release/build-56` não são candidatas novas; não confundir branches de CI com integração/release. A listagem atual retornou 209 branches e **oito PRs abertos, todos draft**: #29, #30, #31, #33, #34, #35 (HEADs anteriores inalterados), **#36 `7afa2571d1b197e89dc179887fde7fa47d408f24` e #37 `b671147cc2deadf6441ed18e1c3906615e0bb0a6`**. #36 tem base no #35; #37 tem base no #36, não diretamente na main. Issues #7, #18, #27, #32 seguem abertas, sem novas alterações de estado. Nenhum PR foi integrado.

**Normas relidas na main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/PRODUCT_INVARIANTS.md), [arquitetura](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/ARCHITECTURE.md), [dependências](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/DEPENDENCY_RULES.md), [B01–B06](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [render-ready](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/2026-10-17-render-ready-admission-rule.md) e [README/handoff](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/README.md). Sem mudanças normativas na main. O norte continua descoberta da internet aberta, feed contínuo, runway relativa, pixels prontos **antes** de admissão, scroll local estável, filtros reutilizáveis, retorno offline e persistência pessoal; nenhuma prova de componente isolado substitui B03–B06 e PD-10.

## 2. Resumo executivo e consequência para o leitor

**Avanço verificável: o novo diagnóstico Apple separou o problema de visibilidade da ordem de inicialização do writer nativo.** O [PR #36](https://github.com/wsmontes/feedmine_v2/pull/36) testa callbacks SwiftUI de *staging* num host reduzido: a janela semântica [B,C,D] é proposta, a janela física [A,B,C] não se move e a proposta é revogada quando chega uma atualização append-only. [Actions #41371378500](https://github.com/wsmontes/feedmine_v2/actions/runs/41371378500) executou **1 XCTest iOS Simulator, 1 PASS, 0 FAIL** no SHA temporário `b9504a1c`, com o **mesmo blob do teste** do HEAD #36, mas patches #30/#34 e workflow de CI. Isso **não** é PASS da main, do #36 isolado, nem da troca física.

O [PR #37](https://github.com/wsmontes/feedmine_v2/pull/37) adiciona teste do **FeedScreen real** em `UIHostingController`, mais contadores **DEBUG** no único `FeedNativeScrollOffset`. O [run #41375292900](https://github.com/wsmontes/feedmine_v2/actions/runs/41375292900), SHA combinado `4092170619d19fd6264de3e7dd69d482dc40c5e0`, executou **2 XCTest: 1 PASS (host reduzido), 1 FAIL (FeedScreen real, duas assertions)**. A falha contém uma discriminação concreta: `probeEntries=9`, `probeGuards=9`, `cardObservations=9`, **`beforeBinding=9`, `afterBinding=0`, `outsideViewport=0`**, `nativeScrollAttached=true` ao verificar. O card comum B **estava dentro da viewport**: `frame=(0,174,358,158)`, altura 720, offset 0. Portanto, **na fixture**, a falta de B em `observedVisibleCardIDs` não se explica por estar fora da tela; todas as amostras foram entregues **antes** da associação da UIScrollView. A vinculação existe depois, mas não houve nova amostra. Este é um fato de instrumentação/ordem de callbacks, **não prova de que o leitor real perde posição**, nem prova de que um mecanismo de handoff físico já existe.

Os arquivos de teste e de instrumentação do run combinado possuem **blobs idênticos** ao HEAD #37: `FeedNativeStageHostTests.swift@a5a09d66d1df764ff65b2244a0ac4c1f8ddfb3ee`, `FeedNativeScrollOffset.swift@4d07e42dae2018ec0f93744314d80cc88bd3a0af`. Os commits divergem porque a branch de CI também contém #30/#34/workflow. Os runs intermediários [#41373007651](https://github.com/wsmontes/feedmine_v2/actions/runs/41373007651) e [#41374123758](https://github.com/wsmontes/feedmine_v2/actions/runs/41374123758) já tinham 1 PASS/1 FAIL; o último **refinou a causa da assertion**. O corpo do PR #37 ainda descreve o último run como iniciado; prevalece o log concluído.

**Parecer: RELEASE NÃO APROVADA.** A main não mudou, não há swap físico [A,B,C]→[B,C,D], B03 no SHA integrado, veto de redirect antes da conexão, catálogo de release, retorno Safari, reabertura offline ou B06 físico aceitos. Os testes novos tornam o próximo passo mais preciso, mas não mudam o bloqueio de produto.

## 3. Achados priorizados: fato, hipótese, risco, ação mínima

### P0-01 — Handoff físico render-ready ainda não implementado (ABERTO)

**Fato:** [`FeedScreenStore.swift:304–329`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreenStore.swift#L304-L329) só troca automaticamente IDs físicos se a nova janela começa com os IDs antigos; senão conserva a antiga. [`FeedScreen.swift:158–211`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreen.swift#L158-L211) desenha `renderedItems` e mede células reais. O [RED macOS #41226687119](https://github.com/wsmontes/feedmine_v2/actions/runs/41226687119) reproduziu a não substituição física. #35 apenas faz stage; #36 prova callbacks de stage; #37 testa o host e observa uma limitação de medição inicial. **Nenhum dos três publica a janela provisória, mede witness pós-layout e conclui commit/rollback.**

**Risco de produto (inferência):** em trim/prepend/reentrada, o leitor pode ficar preso a uma janela física velha apesar de haver material pronto; possível buraco/estagnação no scroll, mas frequência no iPhone ainda não medida. **Ação mínima:** resolver a obtenção de prova nativa **pós-binding** no mesmo host, depois implementar `begin` em idle com card comum medido, publicação provisória dos IDs no mesmo `LazyVStack`, medição pós-layout e correção pelo **único writer**, `commit` por recibo, ou rollback físico de IDs/offset com quitação antes de nova tentativa. Gesto cancela, não adia; não criar segunda fila, timer, cache ou writer. Tornar o RED físico GREEN **no SHA exato**, depois provar em iOS e gesto real.

### P1-01 — Ordem de callback de geometria vs binding nativo (NOVO; RED REFINADO)

**Fato no teste do host real:** [`FeedNativeStageHostTests.swift:118–214`](https://github.com/wsmontes/feedmine_v2/blob/b671147cc2deadf6441ed18e1c3906615e0bb0a6/Tests/ArchitectureSmokeTests/FeedNativeStageHostTests.swift#L118-L214), assertions ~183/198, [run #41375292900](https://github.com/wsmontes/feedmine_v2/actions/runs/41375292900): B geometricamente visível, 9/9 provas antes da vinculação, 0 depois. [`FeedNativeScrollOffset.swift:125–210` no #37](https://github.com/wsmontes/feedmine_v2/blob/b671147cc2deadf6441ed18e1c3906615e0bb0a6/Sources/FeedMineUI/FeedNativeScrollOffset.swift#L125-L210) registra amostras DEBUG; [`FeedNativeScrollOffset.swift:339–363` na main](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedNativeScrollOffset.swift#L339-L363) vincula a scroll view em `didMoveToWindow/layoutSubviews`; [`FeedScreen.swift:175–230`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreen.swift#L175-L230) recebe `onGeometryChange`. **Fato:** a prova B é válida como geometria da fixture, mas não foi observada **com writer já vinculado**; `nativeScrollAttached=true` no fim não altera o passado.

**Hipótese delimitada:** o `onGeometryChange` pode não repetir o mesmo valor quando a UIView nativa finalmente se vincula, deixando o teste sem prova pós-binding até outra mudança legítima. Não inferir automaticamente falha em todos os cenários de produção. **Ação mínima:** no Mac, criar ensaio discriminante de vínculo tardio e de scroll/layout subsequente, provar `afterBinding>0` e B visível sem evento de leitura sintético; se necessário, fazer uma re-medição legítima **depois** do vínculo, no mesmo dono e escopo, não reaproveitar geometria anterior como se fosse prova fresca, nem chamar `observe` manualmente para fabricar aceitação. Repetir com a mesma UIScrollView, gesto e cancelamento. O RED não deve ser “corrigido” retirando a assertion.

### P0-02 — B03/runway e estabilidade física no HEAD integrado (ABERTO)

**Fato:** [benchmark B03](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) documenta **PASS histórico em 20/out** no commit `4baf9045` (3.157 avanços/30 min, zero paradas ≥1 s); **não** há prova nova B03 do `main@2eca5b4f` ou da árvore #35–#37. B04/B05 precisam cobrir a janela física e o leitor real, não só staging. **Risco:** supply lógico pronto não garante card desenhado disponível. **Ação:** depois do GREEN físico, executar B03 30 min com corpus/runner/oráculo congelados, avanços reais/IDs desenhados, offset e pausas, mais B04/B05 no mesmo SHA; não transformar histórico em PASS atual.

### P0-03 — Redirect público→privado verificado só depois de `session.bytes` (ABERTO)

**Fato estático:** [`FeedDiscoveryTransport.swift:69–91`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L69-L91) valida o host final após iniciar `session.bytes(for:)`. **Hipótese de risco:** redirect automático pode conectar a destino privado antes do veto; **não foi demonstrada exploração**. **Ação:** política de redirect no delegate antes de seguir, com teste público→privado que prove **zero conexão** privada. Não confundir recusa do corpo após conexão com prevenção da conexão.

### P1-02 — Persistência, Safari, filtros, catálogo e gates Apple do app (ABERTO)

**Fatos anteriores ainda válidos:** [PR #30](https://github.com/wsmontes/feedmine_v2/pull/30) corrige compilação Swift 6, [PR #34](https://github.com/wsmontes/feedmine_v2/pull/34) corrige fixture case-insensitive, [PR #31](https://github.com/wsmontes/feedmine_v2/pull/31) distingue checkpoint de exposição editorial. [Run #41225997714](https://github.com/wsmontes/feedmine_v2/actions/runs/41225997714) teve 1.887 PASS/4 skipped em branch combinada, **não na main**. [Consolidação](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md) relata 17 falhas de 229 testes do app; não há evidência de resolução. [Issue #18](https://github.com/wsmontes/feedmine_v2/issues/18) Safari e [#7](https://github.com/wsmontes/feedmine_v2/issues/7) pixels render-ready continuam abertas. PD-10 exige par de catálogo/manifesto íntegro e proveniência, não apenas suite SwiftPM.

**Ação mínima:** owner integrar pequenos patches pelo fluxo normal, rodar app real com catálogo validado no SHA final; verificar Safari cardID/±1pt, A→B→A reutilizando trabalho, reabertura offline, salvos/coleções/fontes e importação V1 real, sem produção dependente de rede para scroll.

### P2 — Instrumentação e confiança de CI (PARCIAL)

#36 é **somente teste**; #37 muda **somente teste + DEBUG** ([diff #36](https://github.com/wsmontes/feedmine_v2/pull/36/files), [diff #37](https://github.com/wsmontes/feedmine_v2/pull/37/files)). Os contadores DEBUG e mapa de última prova estão limitados a IDs da janela física para o mapa; verificar se a instrumentação não afeta observação/performance em longas sessões. [CI #41371378500](https://github.com/wsmontes/feedmine_v2/actions/runs/41371378500) PASS 1 teste de staging; [CI #41375292900](https://github.com/wsmontes/feedmine_v2/actions/runs/41375292900) FAIL 1/2 no host real; ambos em **branches temporárias combinadas**. Não há PASS de XCTest, iPhone físico ou benchmark para a candidata de release. B06 foi tentado historicamente em 20/out, mas **INCOMPLETE**; no SHA atual **NOT_RUN**.

## 4. Provas necessárias no Mac — NÃO EXECUTADAS POR ESTE MONITOR

~~~bash
git fetch origin main monitor/architecture \
  test/native-stage-host-callback-20261101 \
  test/feed-screen-native-proof-20261102 \
  ci/native-stage-host-validation-20261101 \
  ci/native-host-nonprefix-red-20261031
git rev-parse origin/main
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git diff --check origin/main..origin/test/feed-screen-native-proof-20261102
xcrun simctl list devices available

# Reproduzir o RED do FeedScreen real com patches de compilação #30/#34,
# exatamente na branch de CI; NÃO esperar verde:
git worktree add --detach /tmp/fm-monitor-050-host 4092170619d19fd6264de3e7dd69d482dc40c5e0
cd /tmp/fm-monitor-050-host
xcodebuild test -scheme FeedMine-Package \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO \
  -only-testing:ArchitectureSmokeTests/FeedNativeStageHostTests \
  -resultBundlePath /tmp/FeedMine050Host.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/FeedMine050Host.xcresult

# Gate seguinte: nova prova de geometria APÓS o binding da mesma UIScrollView,
# depois [A,B,C] -> [B,C,D] com commit/rollback medidos e sem gesto ativo.
# Não tratar callback anterior ao binding como recibo pós-layout.

# Gate final no SHA de integração, com catálogo de produto verificável:
scripts/verify_product_catalogue.sh "$(xcrun simctl get_app_container booted com.feedmine.development app)"
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/FeedMine050App.xcresult CODE_SIGNING_ALLOWED=NO
scripts/run-browser-return-ab.sh --help
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
# Repetir B04/B05, B06 no iPhone físico prescrito, mantendo corpus/oráculos.
~~~

**Critério de liberação:** feed contínuo sem esgotamento artificial; runway preparada enquanto o leitor consome; pixels locais decodificados antes de admissão; IDs físicos, posição e offset preservados em trim, gesto, Safari e retorno; A→B→A sem perda de trabalho; estado pessoal offline durável; redirects privados vetados **antes** de conexão; B01–B06 e PD-10 comprovados na mesma candidata. `NOT_RUN` não é `PASS`.

## 5. Memória compacta para a próxima revisão / handoff OMP

- **Última revisão anterior:** 049, `monitor/architecture@f563ca6d`, blob `1d5a2249`. Histórico 043 `53d43097` → 044 `d069a366` → 045 `8c1e9e24` → 046 `13ef6baa` → 047 `b8b942e2` → 048 `4fa767d7` → 049 `f563ca6d`. **Esta é a revisão 050**.
- **Main e integração:** `2eca5b4f` inalteradas. **PRs draft:** #29 `d8e7e5ea`, #30 `beffb21d`, #31 `aecd6748`, #33 `393e0bc9`, #34 `9e9ab275`, #35 `4f7040ef`, **#36 `7afa2571`**, **#37 `b671147c`**. #36 empilhado sobre #35; #37 sobre #36. Issues #7/#18/#27/#32 abertas.
- **Novas provas:** #41371378500 1/1 PASS staging em CI combinado `b9504a1c`; #41373007651 1/2 FAIL host real; #41374123758 1/2 FAIL, 9 callbacks sem witness; **#41375292900 1/2 FAIL** no CI `40921706`: `beforeBinding=9, afterBinding=0`, B visível. Blobs do teste/instrumentação **iguais** ao HEAD #37. Não houve mudança da lógica produtiva.
- **Resolvido nesta revisão:** a ambiguidade **da fixture** sobre B fora da viewport foi eliminada; a falha de assert está ligada à ordem de binding/callbacks. **Não resolvido:** prova nativa fresca pós-binding, handoff físico/rollback, B03/B04/B05 no HEAD, redirects, 17 falhas do app, catálogo PD-10, Safari, offline/salvos/fontes, B06 físico.
- **Owner:** primeiro discriminar medição pós-binding e obter GREEN real sem enfraquecer o teste; depois concluir swap físico com único writer; só então aceitar experiência e release. Não adicionar timers, caches, filas, retries ou ownership paralelos.
- **Handoff explícito:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Monitor consultivo: não altera main, código, testes, benchmarks, scripts, coordenação, issues ou PRs.
