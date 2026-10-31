# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 044 · Vancouver, 30/10/2026, 17:38 PDT.** Parecer consultivo independente, **não** certificação de release. O OMP precisa executar `git fetch origin monitor/architecture` e ler este documento; nenhum executor é notificado automaticamente.

## 1. Base verificada, intervalo e autoridade

**Memória persistente lida primeiro:** revisão 043, `monitor/architecture@53d43097e47b193d6cf880852e763f3012c1df41`, blob `dc84ac44661bed3fbf5c8e76745069a3c58d2292`. **Janela incremental:** 30/out/2026, 15:44–17:38 PDT. **Mudança relevante:** dois PRs draft novos, [#16](https://github.com/wsmontes/feedmine_v2/pull/16) e [#17](https://github.com/wsmontes/feedmine_v2/pull/17), concentrados na P0 [Issue #7](https://github.com/wsmontes/feedmine_v2/issues/7), com código de Runtime e regressões. Nenhuma mudança normativa ou merge em main foi encontrada. Revisão por conector GitHub, sem checkout local nem execução Apple.

**HEADs lidos e comparados:** `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48` (idêntica à 043); [#16](https://github.com/wsmontes/feedmine_v2/compare/main...test/render-ready-restore-contract-20261030) `test/render-ready-restore-contract-20261030@72d067bf47dabd5f81509cb0ed0795085aa3ce98` (6 commits, 2 arquivos novos de testes); [#17](https://github.com/wsmontes/feedmine_v2/compare/test/render-ready-restore-contract-20261030...fix/atomic-viewport-readiness-20261030) `fix/atomic-viewport-readiness-20261030@ba1fc08843cde016a3bd5bc5d5d12862966250ad` (**stacked sobre #16**, 25 commits e 13 arquivos no diff com a base #16; 31 commits exclusivos de main, não integrados). A HEAD #17 avançou durante esta leitura: `a2dea06b` → `84142028` (teste do índice) → `ba1fc088` (implementação do índice). **Este parecer inclui o último desses commits**, sem presumir que a branch ficará congelada depois das 17:38.

**Sem avanço desde a 043, comparações antigo→ref `identical`:** F13 [#6](https://github.com/wsmontes/feedmine_v2/pull/6) `c0392741`; render-ready [#8](https://github.com/wsmontes/feedmine_v2/pull/8) `83f05671`; transições [#9](https://github.com/wsmontes/feedmine_v2/pull/9) `3e863a1c`; Safari [#10](https://github.com/wsmontes/feedmine_v2/pull/10) `f4f041c0`, [#11](https://github.com/wsmontes/feedmine_v2/pull/11) `9bd7b345`, [#12](https://github.com/wsmontes/feedmine_v2/pull/12) `95b894f7`, [#13](https://github.com/wsmontes/feedmine_v2/pull/13) `cf2ce6a8`, [#14](https://github.com/wsmontes/feedmine_v2/pull/14) `e02a69ae`, [#15](https://github.com/wsmontes/feedmine_v2/pull/15) `18ad774b`; reserve `a8814282`, integrity `031b27d3`, next `d6a05266`, integration/chatgpt `8203d439`, integration/main-into-app-line `09a6e3a4`, release/build-56 `cede37f6`, integration/candidate `1b990306` (**histórica**, não candidata atual), monitor `53d43097`. Busca paginada de branches retornou 185 nomes; a atividade nova pertence às branches de #16/#17, não às fases antigas.

**Autoridade relida na main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [decisões PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz 11/10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [arquitetura](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/ARCHITECTURE.md), [auditoria de consistência](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/DOCUMENTATION_CONSISTENCY_AUDIT_2026-10-10.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) e [regra absoluta render-ready](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md). Blueprints históricos não revogam essas decisões. O [README:3](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/README.md#L1-L5) confirma o handoff consultivo. #16/#17 não alteram docs normativos, benchmarks ou scripts.

## 2. Resumo executivo — consequência perceptível

**Progresso de correção parcial, NÃO fechamento da P0.** #17 move o registro durável de leitura (`markSeen`) para depois da preparação falível do retorno ao viewport; preserva âncora, posição/proveniência, marcadores de pixels e ordinal de evidência quando um hero histórico não pode ser decodificado. Também estende a transação aos caminhos de forward/backward/published growth, restringe decodificação à faixa local e impede que uma identidade histórica sem pixels emita prova de viewport. Isso reduz risco de marcar como lido um card que nunca pôde ser mostrado, e protege retry com a mesma identidade. **Fato de código, não teste Apple executado.**

**A fronteira decisiva continua violada por código:** a janela lógica ainda pode conter hero sem bitmap e a UI normal/held continua copiando/desenhando esses itens. Um predicado `isRenderReady` ou um índice lógico de slots **não** equivale a impedir a admissão visual. O novo `FeedVisualRailIndex` (commit `ba1fc088`) é somente índice read-only, explicitamente sem adaptador SwiftUI, geometria ou política de reentrada. O teste de handoff exige ready-only nas duas superfícies, mas o código atual ainda não satisfaz a asserção. Portanto **P0 #7 ABERTO**, apesar do avanço real de atomicidade.

**Release NÃO APROVADA.** B03 segue FAIL histórico; B06 NOT_RUN; R4 completo não aceito. A regressão Safari/posição ainda requer A/B executado; F13, #9, #13 e #16/#17 não foram reunidos em uma árvore testada. Não houve XCTest, simulador, iPhone, benchmark ou CI comprovado nesta revisão. HEAD `ba1fc088`: zero status contexts e zero runs acionados por PR retornados pelo conector (essa consulta não certifica ausência de toda execução externa).

## 3. Achados priorizados — fatos, hipóteses e ação mínima

### P0-01 — Contrato render-ready ainda não atravessa a fronteira Runtime→UI (ABERTO)

**Fato comprovado por leitura:** [FeedSession.swift:447–499](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineRuntime/FeedSession.swift#L447-L499) mantém a janela histórica, decodifica apenas a banda e preserva descritores de imagem sem bitmap fora dela; o restore pode devolver um anchor image-bearing sem pixels, apenas deixa de chamar `markSeen` nesse caso ([linhas 463–475](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineRuntime/FeedSession.swift#L463-L475)). [FeedScreenStore.swift:137–161](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineUI/FeedScreenStore.swift#L137-L161) ainda copia `presentation.window.items` diretamente para `renderedItems`; [FeedInteractionPresentation.swift:44–48](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineUI/FeedInteractionPresentation.swift#L44-L48) devolve a janela held crua; [FeedScreen.swift:82–99](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineUI/FeedScreen.swift#L82-L99) monta células para todos esses itens. O novo guard de geometria em [FeedScreen.swift:110–122](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineUI/FeedScreen.swift#L110-L122) **impede emitir prova**, não impede desenhar a célula. O fallback de [FeedItemCardView.swift](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineUI/Cards/FeedItemCardView.swift) ainda existe. [RenderReadyVisualHandoffContractTests.swift:224–248](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Tests/FeedMineCompositionTests/RenderReadyVisualHandoffContractTests.swift#L224-L248) exige as duas superfícies ready-only: **RED esperado estaticamente, não RED observado em XCTest**.

**Consequência:** imagem histórica sem bytes pode continuar como card incompleto/placeholder na lista, mesmo sem evidência de scroll. **Orientação mínima:** um único owner de admissão visual, derivado do snapshot lógico com a mesma política para normal e held, antes de instalar a UI; manter história, IDs, ordem, checkpoint e navegação reversa, sem filtrar a lista física ingenuamente ou criar cache/queue/timer paralelo. Provar missing hero entre textos prontos, hero real decodificado e retorno 750→1→750. **Não** declarar #7 resolvida por apenas rejeitar `RenderedViewportEvidence`.

### P1-01 — Atomicidade do retorno histórico e das extensões melhorou (PARCIALMENTE RESOLVIDO, prova pendente)

**Fato comprovado:** [FeedSession.swift:135–201](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineRuntime/FeedSession.swift#L135-L201) propõe janela e banda sem consumir ordinal/estado; só depois de validar pixels do alvo, construir proveniência e persistir `markSeen` instala o journal e a nova posição. [Linhas 220–279](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineRuntime/FeedSession.swift#L220-L279) unificam preparação/commit de extensões e redecodificam a banda local. [RenderReadyHistoryReturnTests.swift:115–164](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Tests/FeedMineRuntimeTests/RenderReadyHistoryReturnTests.swift#L115-L164) exige não consumir o mesmo ordinal após falha e conseguir retornar depois de repor o arquivo. [RenderReadyCheckpointExposureContractTests.swift](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Tests/FeedMineRuntimeTests/RenderReadyCheckpointExposureContractTests.swift) cobre watermark e overflow. #16 adiciona contratos de restore/warmStart com hero ausente e texto pronto.

**Limite/risco:** os testes são fonte versionada; relatos de harness Swift 6 isolado em Linux no PR #17 **não** são build do módulo FeedMine, XCTest, prova de transação SQLite em macOS ou medição B05. A política de visual admission não foi fechada. O loop de [proposeBoundedResidency:229–239](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineRuntime/FeedSession.swift#L229-L239) ainda examina índices da janela inteira antes de atuar na banda: custo potencial crescente sob histórico longo, **hipótese de impacto**, não regressão medida. **Owner:** executar contratos de restore, viewport, extensão, SQLite e B05 em Mac, guardar resultados brutos; só otimizar após trace real de consumo.

### P1-02 — Índice virtual histórico/visual existe, mas ainda não é apresentação (ABERTO)

**Fato:** [FeedVisualRailIndex.swift:1–75](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Sources/FeedMineRuntime/FeedVisualRailIndex.swift#L1-L75) classifica slots `ready`/`deferred`, mantém índices/âncora lógica e oferece slice de banda sem I/O nem altura inventada. [FeedVisualRailIndexTests.swift:29–99](https://github.com/wsmontes/feedmine_v2/blob/ba1fc088/Tests/FeedMineRuntimeTests/FeedVisualRailIndexTests.swift#L29-L99) descreve siblings, checkpoint não desenhável, gesto held e 1000 posições lógicas. A implementação foi adicionada **depois** do teste na mesma branch, portanto o diagnóstico transitório “tipo inexistente” não se aplica ao HEAD `ba1fc088`. **Não há uso desse índice em FeedScreenStore/FeedScreen/held no diff**; não há altura, offset, adapter ou reentrada implementados.

**Risco inferido:** usar apenas `filter(isRenderReady)` na `LazyVStack` colapsaria a geometria histórica, enquanto placeholders violariam a regra. **Owner:** integrar um rail visual com posições/offset estáveis e reidratação local de banda; provar continuidade sob dedo, volta profunda, scroll idêntico após reabertura e ausência de card incompleto. Não multiplicar owners de scroll/sessão.

### P1-03 — Safari/retorno exato ainda sem experimento executado (ABERTO)

**Fato:** [#10](https://github.com/wsmontes/feedmine_v2/pull/10) exige o mesmo UUID e frame ±1 pt; [#13](https://github.com/wsmontes/feedmine_v2/pull/13) propõe `.overFullScreen` em vez de `.fullScreen`; [#14](https://github.com/wsmontes/feedmine_v2/pull/14) instrumenta scroll/window/âncora; [#15](https://github.com/wsmontes/feedmine_v2/pull/15) prepara A/B de três repetições. Todos esses HEADs ficaram idênticos à revisão 043. Nenhuma prova de execução iOS nova. **Hipótese:** preservar a hierarquia UIKit evita remount, mas não exclui deriva de janela/âncora. **Owner:** executar controle e experimento no mesmo simulador, preservar `.xcresult`, vídeo, UUID, frame e offset; só portar a correção demonstrada para a linha integrada.

### P1-04 — Integração/ownership e reabertura A→B→A continuam pendentes (ABERTO)

**Fato:** #17 é stacked sobre #16, ambos sobre main antiga; #6 F13 (`c0392741`) contém handoff/recuperação; #9 (`3e863a1c`) tem testes e controle de falhas de transição; #13 Safari e #8 render-ready são outras árvores. Nenhuma árvore reúne todas as garantias. **Risco:** juntar patches mecanicamente cria estados, retries e owners paralelos e pode destruir posição, salvos/coleções/fontes ou runway. **Owner:** uma única composição F13, portar regressões discriminantes e o menor patch que passou em Mac; testar falha SQLite durante A→B, retorno B→A, troca de filtros sem perder material, reabertura offline, salvos e gesto ativo. Não mesclar toda instrumentação de diagnóstico como produção.

### P0-02 — B03/runway adaptativa (ABERTO, FAIL histórico não revogado)

O [benchmark B03:68–80](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L68-L80) exige **30 minutos de avanços efetivos**, 1 card/s e rajadas 3/s, sem paralisação visível ≥1 s por falta de reserva nem fim artificial com supply elegível. O FAIL histórico de aproximadamente 5,70 s permanece; #16/#17 não mediram o pipeline end-to-end. **Owner:** executar corpus/trace/oráculo congelados na árvore integrada; preservar dados brutos, B04/B05 no mesmo SHA, sem alterar critérios nem chamar teste unitário de PASS de produto.

### P0-03 — Redirect privado validado após conexão (ABERTO, inalterado)

[FeedDiscoveryTransport.swift:75–90](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) valida destino final depois de `URLSession.bytes(for:)`, que pode seguir redirecionamento antes do veto. **Risco inferido, não exploração observada:** conexão a destino privado antes da rejeição. **Owner:** validar cada salto antes da conexão; teste público→privado com prova de zero conexões privadas.

### P2 — Evidência e release (ABERTO)

**Sem PASS novo comprovado.** #16/#17 não têm status contexts ou workflow runs de PR retornados nos HEADs consultados; não executei Xcode, XCTest, simulador, iPhone, benchmark, nem certifiquei logs Apple. Os 25 checks de um modelo isolado Swift/Linux relatados no PR #17 são somente abstração; testes novos de composição, offset, rail e watermark **não foram observados em XCTest**. R4 completo NÃO ACEITO; B03 FAIL histórico; B06 NOT_RUN; B01/B02/B04/B05 sem novo PASS integrado; PD-10/INV-18 requerem prova de catálogo empacotado e reconciliação; TestFlight interno antigo não certifica este SHA. **Release pública NÃO APROVADA.**

## 4. Provas/comandos mínimos no Mac — NÃO EXECUTADOS AQUI

```bash
git fetch origin main monitor/architecture test/render-ready-restore-contract-20261030 fix/atomic-viewport-readiness-20261030 product/nf04-tail-truth chatgpt/render-ready-contract-red-01 audit/session-transition-failure-probe-20261030 audit/browser-return-identity-regression-20261030 experiment/reader-host-over-full-screen-20261030 diagnostic/safari-viewport-probe-20261030
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git diff --check origin/main..origin/fix/atomic-viewport-readiness-20261030
git worktree add --detach /tmp/fm-render-17 origin/fix/atomic-viewport-readiness-20261030
cd /tmp/fm-render-17
swift test --filter RenderReadyAdmissionContractTests
swift test --filter RenderReadyHistoryReturnTests
swift test --filter RenderReadyVisualHandoffContractTests
swift test --filter RenderReadyCheckpointExposureContractTests
swift test --filter FeedVisualRailIndexTests
swift test --filter RenderReadyOffsetContractTests
swift test --filter FeedSessionViewportTests
swift test
xcrun simctl list devices available
# Em worktrees isolados #10 e #13, mesmo UDID/fixture/build, repetir 3x
# FeedMineUITests/ReadingSurfaceUITests/testClosingSitePreservesScrolledCardIdentityAndFrameWithDeepHistory
# com xcodebuild build-for-testing/test-without-building e -resultBundlePath único.
# Guardar logs, xcresult, UUID, minY/maxY, screenshots e vídeo.
# Repetir na árvore integrada F13, com publicação simultânea, A→B→A e relaunch offline.
# Rodar B03 no avaliador externo congelado, sem editar corpus, driver, trace ou oráculo:
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
```

**Critério de saída:** falta de pixels não atravessa UI normal **nem** held; histórico completo e reentrada profunda continuam alcançáveis sem placeholder ou salto; tentativa rejeitada não altera `markSeen`, âncora ou ordinal; hero real mantém pixels/identidade; 30 minutos de consumo B03 sem lacuna; sem regressão em filtros, offline e salvos. Se falhar, registrar FAIL e preservar o `.xcresult`, não enfraquecer a régua.

## 5. Memória compacta para próxima revisão

- **Monitor:** 039 `2464c5dc` → 040 `e3524bcf` → 041 `5842ce1c` → 042 `d4c3c5c1` → 043 `53d43097` → **044 (este documento)**; blob anterior `dc84ac44`.
- **Base estável:** main `fb8e65ff`; #6 F13 `c0392741`; #8 render `83f05671`; #9 transições `3e863a1c`; #10 `f4f041c0`; #11 `9bd7b345`; #12 `95b894f7`; #13 `cf2ce6a8`; #14 `e02a69ae`; #15 `18ad774b`; reserve `a8814282`; integrity `031b27d3`; next `d6a05266`; release `cede37f6`.
- **Novos ativos:** #16 `72d067bf` (contratos RED previstos, XCTest não executado); #17 `ba1fc088` (transação viewport, guard de prova, índice virtual; stacked, não integração). Revisar HEAD novamente no próximo ciclo: houve commits durante esta leitura.
- **Resolvido parcialmente:** evitar consumo de exposição/ordinal em retorno de imagem sem pixels, transação das extensões, índice lógico pronto em código. **Não resolvido:** admissão visual real, held, geometria/offset e reentrada; Safari, B03, redirect, R4 integral, integração, offline, salvos/coleções/fontes e PD-10 end-to-end.
- **Gates:** #7 P0 ABERTO; B03 FAIL histórico; R4 NÃO ACEITO; B06 NOT_RUN; release NÃO APROVADA. Sem novo PASS Apple.
- **Handoff:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Consultivo; o monitor não modifica main, código, testes, benchmarks, scripts, coordenação, issues ou PRs.
