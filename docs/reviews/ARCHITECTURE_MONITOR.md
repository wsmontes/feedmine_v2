# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 045 · Vancouver, 30/10/2026, 19:42 PDT.** Parecer consultivo independente, **não** certificação de release. O OMP precisa fazer `git fetch origin monitor/architecture` e ler este arquivo; não há notificação automática aos agentes.

## 1. Base, intervalo e autoridade

**Memória persistente lida primeiro:** revisão 044, `monitor/architecture@d069a366bf450d2a2f7aede7c55dc46c5b95ed1e`, blob `b852c3345af2809f9e4f4a637a95c512b7a1034d`. **Janela incremental:** 30/out/2026, 17:38–19:42 PDT. Inspeção por conector GitHub, sem checkout local nem execução Apple. **Mudança relevante:** [PR #17](https://github.com/wsmontes/feedmine_v2/pull/17) avançou **54 commits** (`ba1fc08843cde016a3bd5bc5d5d12862966250ad` → `93e6cbbee11d48d4b22cd5645f6586304ee36c4a`), em 13 arquivos: cinco fontes de produção, sete arquivos de testes e um workflow. [Diff incremental exato](https://github.com/wsmontes/feedmine_v2/compare/ba1fc08843cde016a3bd5bc5d5d12862966250ad...93e6cbbee11d48d4b22cd5645f6586304ee36c4a). O PR continua **draft e stacked sobre #16**, não sobre a main.

**HEADs verificados:** `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48` (inalterada); #16 `72d067bf` (inalterado); #17 `93e6cbbe` (novo); #6 F13 `c0392741`, #8 render-ready `83f05671`, #9 transições `3e863a1c`, #10 `f4f041c0`, #11 `9bd7b345`, #12 `95b894f7`, #13 `cf2ce6a8`, #14 `e02a69ae`, #15 `18ad774b` (todos sem avanço desde 044 por metadados e/ou comparações). `product/reserve-20261024@a8814282`, `product/integrity-20261024@031b27d3`, `codex/feedmine-next-internal@d6a05266`, `integration/chatgpt@8203d439`, `integration/main-into-app-line@09a6e3a4`, `release/build-56@cede37f6`, `integration/candidate@1b990306` e monitor anterior também sem avanço por comparação. `integration/candidate` é linha histórica, **não** evidência de candidato atual. Busca dos PRs abertos retornou #5–#17 relevantes, sem PR novo após #17; [Issue #7](https://github.com/wsmontes/feedmine_v2/issues/7) segue aberta. Branches antigas não foram interpretadas como trabalho corrente.

**Normas relidas na main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução 11/10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [regra absoluta render-ready](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md) e [README de handoff](https://github.com/wsmontes/feedmine_v2/blob/main/README.md#L1-L8). Os documentos normativos da main não mudaram. Decisões atuais prevalecem sobre blueprints antigos.

## 2. Resumo executivo — o que o leitor recebe

**Avanço de arquitetura, não correção visível entregue.** #17 criou um plano de janela com trechos prontos e diferidos, ownership de uma janela física contínua, handshake provisório com `UIScrollView`, prova de geometria, recibo de correção única e obrigação de rollback físico. O desenho evita inventar alturas de cards sem pixels, evita colapsar gaps sem prova e tenta impedir saltos ao trocar uma janela pronta por outra. É progresso relevante em identidade/posição e compatibilidade com B05.

**Mas a fronteira Runtime→UI continua inalterada:** `FeedScreenStore.install` ainda copia a janela lógica inteira, o caminho held ainda devolve a janela crua, e `FeedScreen` ainda desenha ambas. Os novos componentes são explicitamente uma **seam para host futuro**; não há ligação à lista real nem execução de uma transação de swap no app. A P0 de admissão render-ready **não foi resolvida**. A regra de produto não permite admitir um hero com bitmap ausente, mesmo que a geometria permaneça estável ou a prova de viewport seja recusada.

**Release NÃO APROVADA:** B03 FAIL histórico não revogado; B06 NOT_RUN; R4 completo NÃO ACEITO; sem integração de F13, transições, Safari e #17 em uma árvore validada. O commit mais recente adiciona workflow de iOS em branch isolada, **não um PASS**. Consulta de status contexts do HEAD #17 retornou `[]`; a consulta do conector para runs **acionados por PR** também retornou `[]`, mas ela não cobre conclusivamente os runs de `push` do novo workflow. Nenhum XCTest, simulador, iPhone ou benchmark foi executado por este monitor.

## 3. Achados e ações mínimas

### P0-01 — Admissão visual ainda entrega hero sem pixels à UI (ABERTO; fato de código)

[FeedScreenStore.swift:137–161](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedScreenStore.swift#L137-L161) continua atribuindo `presentationState.presentation?.window.items` a `renderedItems` sem fronteira ready-only. [FeedInteractionPresentation.swift:44–48](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedInteractionPresentation.swift#L44-L48) ainda devolve `held.window.items`. [FeedScreen.swift:82–99](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedScreen.swift#L82-L99) desenha essa lista com `ForEach`; [linhas 114–122](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedScreen.swift#L114-L122) barram apenas a evidência de viewport para card não pronto, **não a célula**. O [contrato de composição:251–275](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Tests/FeedMineCompositionTests/RenderReadyVisualHandoffContractTests.swift#L251-L275) ainda exige ready-only tanto na superfície normal como held; **RED é previsão estática, não execução XCTest observada**.

**Consequência:** um hero histórico sem pixels pode permanecer visível como apresentação incompleta; um guard de scroll não cura o produto. **Owner:** conectar a admissão visual ao host efetivo em uma única fronteira; nenhum card image-bearing sem pixels atravessa normal/held, preservando ID, ordem, checkpoint e reentrada local. Não usar `filter(isRenderReady)` como correção ingênua que altera offsets, nem manter todo histórico decodificado. Provar caso hero ausente entre dois textos prontos, hero PNG real, gesto ativo e volta 750→1→750. **P0 #7 ABERTO.**

### P1-01 — Plano lógico de trechos prontos e diferidos (NOVO, implementado como modelo; UI pendente)

**Fato:** [FeedVisualWindowPlan.swift:28–82](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineRuntime/FeedVisualWindowPlan.swift#L28-L82) constrói segmentos `ready/deferred` preservando índices e âncora lógica; [linhas 84–90](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineRuntime/FeedVisualWindowPlan.swift#L84-L90) só liberam `contiguousReadyCards` quando existe um único run pronto. [FeedReadyWindowOwnership.swift:14–28](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedReadyWindowOwnership.swift#L14-L28) rejeita uma janela que não satisfaça essa condição. [FeedVisualWindowPlanTests.swift:27–68](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Tests/FeedMineRuntimeTests/FeedVisualWindowPlanTests.swift#L27-L68) especifica gaps e banda limitada; **teste presente, execução não verificada**.

**Hipótese/risco:** sem adaptador de reidratação e navegação entre runs, a recusa correta de desenhar um gap pode virar um leitor que não consegue alcançar cards anteriores ou que fica numa janela curta. O contrato de composição quer manter dois textos prontos ao redor do hero ausente; isso requer resolver explicitamente a relação entre ordem lógica e geometria física, não achatar o gap. **Owner:** primeiro instalar o run pronto efetivo e a reentrada local por banda com geometria real; provar que os textos continuam acessíveis e que o histórico não encolhe. Evitar segundo ledger de alturas, cache, fila ou owner de scroll.

### P1-02 — Handoff nativo tokenizado e rollback (NOVO, parcialmente implementado; integração pendente)

**Fato:** [FeedReadyWindowOwnership.swift:78–149](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedReadyWindowOwnership.swift#L78-L149) separa installed/pending/provisional, exige sequência/posição e confirma com testemunha medida; [FeedNativeReadyWindowHandshake.swift:73–135](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedNativeReadyWindowHandshake.swift#L73-L135) vincula o mesmo token à correção nativa e só comita após a posição real concordar. [Linhas 137–199](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedNativeReadyWindowHandshake.swift#L137-L199) registram dívida de rollback e exigem a lista/offset antigos medidos antes de nova troca. [FeedNativeScrollOffset.swift:66–107](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedNativeScrollOffset.swift#L66-L107) cria recibo de correção, não segundo escritor de offset. [FeedNativeReadyWindowHandshakeTests.swift:52–119](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Tests/ArchitectureSmokeTests/FeedNativeReadyWindowHandshakeTests.swift#L52-L119) exercitam o modelo com `UIScrollView` isolada.

**Limite comprovado:** os comentários do próprio [ownership:30–33](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedReadyWindowOwnership.swift#L30-L33) e [handshake:41–43](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/Sources/FeedMineUI/FeedNativeReadyWindowHandshake.swift#L41-L43) dizem que ainda **não** há swap da `LazyVStack`; `FeedScreen` continua no caminho antigo. O teste simula `UIScrollView` sem a hierarquia real do app. **Risco inferido:** rollback lógico sem restaurar as células físicas e o offset pode deixar a leitura saltada, mesmo com token correto. **Owner:** implementar um único host de apresentação que capture o witness antes/depois, retenha A durante gesto e só confirme B após layout e correção; em cancelamento, provar rollback físico com mesmo UUID/frame/offset. Não expandir o protocolo de estado sem integrar a superfície real.

### P1-03 — R4, Safari, filtros e integração ainda sem prova na mesma árvore (ABERTO)

**Fato:** #17 permanece stacked em #16 e separado do [F13 #6](https://github.com/wsmontes/feedmine_v2/pull/6), [transições #9](https://github.com/wsmontes/feedmine_v2/pull/9), [Safari #13](https://github.com/wsmontes/feedmine_v2/pull/13) e [render-ready #8](https://github.com/wsmontes/feedmine_v2/pull/8). Os PRs #10–#15 de retorno ao navegador, captura e A/B não avançaram. Não há prova integrada de A→B→A sob falha SQLite, troca de filtros sem destruir trabalho, posição/identidade após Safari, relaunch offline e persistência de salvos/coleções/fontes. **Risco:** integração mecânica introduzir ownership, retry ou offset concorrentes. **Owner:** partir da composição F13, transportar apenas os contratos e patches mínimos comprovados; testar navegação e runway enquanto a publicação acontece, com histórico/salvos preservados. O A/B Safari exige mesmo simulador, 3 repetições, UUID/frame ±1 pt e `.xcresult`; a hipótese `.overFullScreen` não está aprovada.

### P0-02 — Continuidade B03/runway adaptativa (ABERTO, FAIL histórico)

O [contrato B03](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L68-L90) exige 30 min de avanços efetivos a 1 card/s e rajadas 3/s, sem fim artificial nem parada visível ≥1 s por falta de reserva com supply elegível. O FAIL histórico de ~5,70 s não foi revogado por execução equivalente; testes de janela não medem a aquisição/seleção/preparação/apresentação end-to-end. **Owner:** corpus e driver externos congelados na árvore integrada, trace e logs brutos, B04/B05 no mesmo SHA; não alterar régua.

### P0-03 — Redirect privado validado após conexão (ABERTO, inalterado)

[FeedDiscoveryTransport.swift:75–90](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) verifica o destino depois de `URLSession.bytes(for:)`, que pode seguir redirects antes do veto. **Risco inferido, não exploração observada:** conexão privada antes da validação. **Owner:** vetar cada salto antes da conexão e provar público→privado com zero conexões privadas.

### P2 — Workflow Apple criado, mas sem evidência de execução (NOVO, prova pendente)

**Fato:** [workflow:1–20](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/.github/workflows/feedmine-pr17-ios-validation.yml#L1-L20) dispara em `push` apenas na branch isolada; [linhas 59–96](https://github.com/wsmontes/feedmine_v2/blob/93e6cbbe/.github/workflows/feedmine-pr17-ios-validation.yml#L59-L96) tentam listar schemes, executar `FeedMine-Package` no simulador, compilar o app e guardar `.xcresult`. O commit [93e6cbbe](https://github.com/wsmontes/feedmine_v2/commit/93e6cbbee11d48d4b22cd5645f6586304ee36c4a) foi confirmado por leitura. **Não há PASS confirmado:** status contexts `[]`, runs de evento PR `[]`; a consulta do conector **não cobre push**, e a existência do YAML não confirma que o scheme foi encontrado ou o workflow disparou. **Hipótese de execução:** `xcodebuild -list -json` e o scheme SwiftPM precisam ser verificados no runner; se falhar, registrar a causa em vez de marcar testes verdes. O workflow não executa B03, Safari A/B nem jornada física.

**Gates:** #7 P0 ABERTO; R4 completo NÃO ACEITO; B03 FAIL histórico; B06 NOT_RUN; B01/B02/B04/B05 sem novo PASS integrado; PD-10/INV-18 ainda exigem prova end-to-end do catálogo versionado. **Release pública NÃO APROVADA.**

## 4. Provas e comandos mínimos no Mac — NÃO EXECUTADOS PELO MONITOR

```bash
git fetch origin main monitor/architecture test/render-ready-restore-contract-20261030 fix/atomic-viewport-readiness-20261030 product/nf04-tail-truth audit/session-transition-failure-probe-20261030 experiment/reader-host-over-full-screen-20261030
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git diff --check ba1fc08843cde016a3bd5bc5d5d12862966250ad..origin/fix/atomic-viewport-readiness-20261030
git worktree add --detach /tmp/feedmine-pr17-045 origin/fix/atomic-viewport-readiness-20261030
cd /tmp/feedmine-pr17-045
swift package describe
xcodebuild -list -json
swift test --filter FeedVisualWindowPlanTests
swift test --filter FeedReadyWindowOwnershipTests
swift test --filter RenderReadyVisualHandoffContractTests
swift test --filter RenderReadyHistoryReturnTests
swift test --filter RenderReadyCheckpointExposureContractTests
swift test
xcrun simctl list devices available
# Escolher UDID iOS disponível e confirmar scheme real via xcodebuild -list:
xcodebuild test -scheme FeedMine-Package -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMinePR17-045.xcresult CODE_SIGNING_ALLOWED=NO
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=<UDID>' CODE_SIGNING_ALLOWED=NO build
# Repetir a prova no app REAL integrado: normal/held, hero ausente/real,
# retorno profundo, gesto ativo, Safari 3x A/B, falha A→B, relaunch offline,
# salvos/coleções/fontes e publicação simultânea; guardar xcresult/vídeo/UUID/offset.
# Em árvore integrada e com avaliador externo congelado:
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
```

**Critério de saída:** nenhum card incompleto chega à UI normal/held; não se perde ID, ordem, posição nem geometria durante gesto, falha ou reentrada; ausência de pixels não consome exposição; B03 passa integralmente com logs externos e sem alteração de fixture; filtros, offline e dados pessoais persistem. Se a execução não existir, marcar NOT_RUN; se falhar, preservar FAIL e logs.

## 5. Memória compacta e handoff

- **Revisões monitor:** 039 `2464c5dc` → 040 `e3524bcf` → 041 `5842ce1c` → 042 `d4c3c5c1` → 043 `53d43097` → 044 `d069a366` → **045 (este arquivo)**.
- **SHA base:** main `fb8e65ff`; #6 `c0392741`; #8 `83f05671`; #9 `3e863a1c`; #10 `f4f041c0`; #11 `9bd7b345`; #12 `95b894f7`; #13 `cf2ce6a8`; #14 `e02a69ae`; #15 `18ad774b`; #16 `72d067bf`; **#17 `93e6cbbe`** (54 commits desde 044). Reserve `a8814282`, integrity `031b27d3`, next `d6a05266`, release `cede37f6`, integration/candidate `1b990306` históricos/inalterados.
- **Parcialmente resolvido:** transação de viewport e marcador de pixels da 044; agora existem modelo de runs, ownership provisório, recibo nativo e dívida de rollback **em código e testes**, não na UI real.
- **Ainda aberto:** render-ready efetivo, reentrada e geometria física, Safari A/B, R4 integral, B03, redirects, integração F13, offline, filtros, salvos/coleções/fontes, PD-10 end-to-end. Nenhum novo PASS Apple observado.
- **Handoff obrigatório:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. O monitor é consultivo; não modifica main, código, testes, benchmarks, scripts, coordenação, issues ou PRs.
