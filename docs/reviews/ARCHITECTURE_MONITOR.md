# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 043 · Vancouver, 30/10/2026, 15:44 PDT.** Parecer externo consultivo, **não** certificação de release. O OMP precisa executar `git fetch origin monitor/architecture` e ler este arquivo; não existe notificação automática.

## 1. Base, janela e normas

**Memória persistente lida primeiro:** revisão 042, `monitor/architecture@d4c3c5c1f17c6f2a5adc783846e475b705ae13e4`, blob `857069708374f5b1820b4e435c2186b54949f0e7`. **Janela incremental:** 30/out/2026 13:38 → 15:44 PDT. Consultei PRs, branches, diffs, código, testes e workflow novos. **Mudança relevante:** seis PRs novos, [#10](https://github.com/wsmontes/feedmine_v2/pull/10) a [#15](https://github.com/wsmontes/feedmine_v2/pull/15), todos **draft**, dedicados à regressão de retorno do navegador, à posição visual e à instrumentação A/B. Nenhuma dessas mudanças foi incorporada à main ou à linha F13.

**HEADs novos (conferidos por API/diff):** #10 `audit/browser-return-identity-regression-20261030@f4f041c04c4502f8e43bce8bec72b841dbe01ebc` (5 commits, 1 arquivo de teste); #11 `fix/viewport-presented-top-visibility-20261030@9bd7b3452c6476c7221a4e1645ea898543f9b5d2` (2 commits, 2 arquivos); #12 `fix/viewport-interrupted-motion-20261030@95b894f75dba6b705858334e3e2c1f77fdf96142` (6 commits, 4 arquivos); #13 `experiment/reader-host-over-full-screen-20261030@cf2ce6a8045d5446abaf92a85a8da10c9f80b12c` (10 commits, 3 arquivos); #14 `diagnostic/safari-viewport-probe-20261030@e02a69ae2e0a1c381b3990e0088d7e330f4521b7` (20 commits em comparação com o HEAD atual #13, 3 arquivos); #15 `ci/safari-ab-ios18-20261030@18ad774bf16297b982870fc2164b10e9dd7d9dea` (9 commits, 1 workflow). [Diff #10](https://github.com/wsmontes/feedmine_v2/compare/main...audit/browser-return-identity-regression-20261030), [#11](https://github.com/wsmontes/feedmine_v2/compare/main...fix/viewport-presented-top-visibility-20261030), [#12](https://github.com/wsmontes/feedmine_v2/compare/main...fix/viewport-interrupted-motion-20261030), [#13](https://github.com/wsmontes/feedmine_v2/compare/main...experiment/reader-host-over-full-screen-20261030), [#14](https://github.com/wsmontes/feedmine_v2/compare/experiment/reader-host-over-full-screen-20261030...diagnostic/safari-viewport-probe-20261030), [#15](https://github.com/wsmontes/feedmine_v2/compare/main...ci/safari-ab-ios18-20261030).

**SHAs anteriores verificados por comparação real antigo→branch: 11/11 `identical`, zero commits:** `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48`; F13 [PR #6](https://github.com/wsmontes/feedmine_v2/pull/6) `c03927418ea28771d721763bdcaa3f21f3dab653`; render-ready [PR #8](https://github.com/wsmontes/feedmine_v2/pull/8) `83f05671bd54c603bb6052589ab3d921152c2df5`; transições [PR #9](https://github.com/wsmontes/feedmine_v2/pull/9) `3e863a1cfd065225262c6fcc2798370f6a7431ba`; reserve `a8814282`; integrity `031b27d3`; next `d6a05266`; integration/chatgpt `8203d439`; integration/main-into-app-line `09a6e3a4`; release/build-56 `cede37f6`; monitor `d4c3c5c1`. `integration/candidate@1b990306` é histórica, não candidata ativa. A busca de branches retornou 183 nomes; distinguir as seis frentes novas de branches antigas/inativas.

**Normas vigentes relidas na main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) e [regra render-ready de 17/10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md). A autoridade é a experiência atual; blueprints antigos não revogam essas regras. Incluídas alterações de docs no escopo: nenhum dos seis diffs incrementais modifica documentação normativa; #15 acrescenta workflow.

## 2. Resumo executivo — consequência de produto

**Avanço de diagnóstico, NÃO correção comprovada.** A regressão ao fechar o navegador interno passou a ter um oráculo útil: após oito flings sobre histórico local de 95 itens por fonte, o teste exige o **mesmo UUID e a mesma posição vertical ±1 ponto**, sem gesto corretivo. O experimento #13 muda uma única decisão funcional do UIKit, `.fullScreen` → `.overFullScreen`, para conservar a hierarquia do feed sob o navegador opaco. #14 instrumenta três hipóteses concorrentes: remontagem de `UIScrollView`, alteração da janela publicada e deriva da âncora/offset. #15 prepara comparação A/B no mesmo simulador com três repetições intercaladas. Isso aumenta a capacidade de descobrir a causa; **nenhum dos testes foi executado em iOS nesta janela**.

**O risco real continua:** o leitor pode voltar do navegador em outro card, com frame deslocado ou sem a carta que estava lendo. A main e o F13 ainda usam `.fullScreen`. #11 corrige um cursor potencialmente atribuído a carta futura fora da tela; #12 corrige estado de movimento transitório que sobrevive a `onDisappear`. Essas correções são separadas, não provas de que resolvem a regressão Safari. A experiência de scroll/identidade prevalece sobre o número de testes ou refinamentos da sonda.

**Release NÃO APROVADA.** P0 render-ready, B03/runway e redirects privados continuam abertos; R4 completo não aceito; B06 físico NOT_RUN. #6, #8, #9 e #10–#15 não formam uma árvore integrada. Os HEADs consultados de #10, #13, #14 e #15 não retornaram status contexts nem runs de workflow acionados por PR. O texto do #15 relata duas falhas de configuração de workflow em evento `push` sem jobs; isso **não** é resultado XCTest nem comprova que o workflow atual executa.

## 3. Achados priorizados — fato, hipótese, ação mínima

### P1-01 — Retorno do navegador perde identidade/posição: teste discriminante criado, defeito ainda ABERTO

**Fato de código:** [#10 ReadingSurfaceUITests.swift:253–319](https://github.com/wsmontes/feedmine_v2/blob/f4f041c0/FeedMineApp/FeedMineAppTests/ReadingSurfaceUITests.swift#L253-L319) percorre oito flings, exige mudança em relação à primeira carta, captura UUID/frame, abre URL de fixture, fecha o navegador e compara interseção do viewport, `minY` e `maxY` a 1 ponto. O teste anterior de retorno local→site também ficou mais estrito [linhas 399–420](https://github.com/wsmontes/feedmine_v2/blob/f4f041c0/FeedMineApp/FeedMineAppTests/ReadingSurfaceUITests.swift#L399-L420). O blob do arquivo de testes #10 e #13 é **idêntico**, `b94cfaa074dacf74c023427674ca9e10d4796ab3`, verificado via `fetch_file`. **Não executado**.

**Hipótese/risco:** a fixture de 95 itens e oito flings pode não reproduzir a cadência pública de mais de mil cartas que acompanhou o incidente anterior; o teste é necessário, mas não suficiente para validar a build real. **Owner:** executar controle #10 primeiro, guardar `.xcresult`, UUID/frame, screenshots e vídeo, depois reproduzir com publicação em background. Não declarar GREEN pelo simples retorno de alguma carta.

### P1-02 — `.fullScreen` desmonta potencialmente o viewport; `.overFullScreen` é hipótese experimental, NÃO ACEITA

**Fato:** [main FeedMineApp.swift:790](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/FeedMineApp/FeedMineApp/FeedMineApp.swift#L790) e [F13 FeedMineApp.swift:1284](https://github.com/wsmontes/feedmine_v2/blob/c0392741/FeedMineApp/FeedMineApp/FeedMineApp.swift#L1284) usam `.fullScreen`. [#13 FeedMineApp.swift:789–795](https://github.com/wsmontes/feedmine_v2/blob/cf2ce6a8/FeedMineApp/FeedMineApp/FeedMineApp.swift#L789-L795) usa `.overFullScreen` com fundo opaco. [#13 ReaderHostTests.swift:112–177](https://github.com/wsmontes/feedmine_v2/blob/cf2ce6a8/FeedMineApp/FeedMineAppTests/ReaderHostTests.swift#L112-L177) contém prova UIKit proposta com `UIScrollView`, janela e offset 615; o teste de interface compartilhado exige geometria da carta. **Fato documental:** UIKit distingue preservação da hierarquia no `overFullScreen`; isso não demonstra o comportamento do FeedScreen real.

**Hipótese:** manter a hierarquia elimina um mecanismo de remount e talvez o salto. **Risco de regressão:** apresentação, hit testing, aparência e lifecycle podem diferir; manter o feed montado não garante que a publicação/âncora não mudou. **Owner:** A/B no mesmo simulador, mesmas fontes/fixture, controle 3× e experimento 3×, com evidência visual e offset. Se ambos falharem, não incorporar a troca como solução; se controle falhar e experimento passar repetidamente, portar a mudança mínima à linha F13 e repetir o oráculo nela.

### P1-03 — Cursor de carta futura e estado de movimento obsoleto: correções estáticas separadas, PARCIAIS

**Fato:** [#11 FeedVisualCapture.swift:228–239](https://github.com/wsmontes/feedmine_v2/blob/9bd7b345/Sources/FeedMineUI/FeedVisualCapture.swift#L228-L239) passa a exigir `offset - 1 <= top < offset + reach`; a main só tinha limite inferior, podendo escolher uma carta medida abaixo da tela. [#11 teste:140–166](https://github.com/wsmontes/feedmine_v2/blob/9bd7b345/Tests/ArchitectureSmokeTests/FeedViewportCaptureTests.swift#L140-L166) documenta esse caso. [#12 FeedVisualCapture.swift:130–141](https://github.com/wsmontes/feedmine_v2/blob/95b894f7/Sources/FeedMineUI/FeedVisualCapture.swift#L130-L141) interrompe flags transitórias preservando identidade; [FeedNativeViewport.swift:60–69,164–172](https://github.com/wsmontes/feedmine_v2/blob/95b894f7/Sources/FeedMineUI/FeedNativeViewport.swift#L164-L172) chama isso em `onDisappear` e evita callback obsoleto antes de validar escopo. São patches com testes **versionados**, não executados no Xcode.

**Hipóteses a testar:** (a) quando uma carta alta começa acima do viewport e ainda o ocupa, o predicado de #11 pode deixar `presentedTop=nil`; não gravar carta futura é correto, mas ainda é preciso provar recuperação de posição em cards parcialmente visíveis; (b) apresentar UIKit `.fullScreen` pode não produzir exatamente o `onDisappear` esperado no instante crítico, então #12 não é necessariamente solução do browser-close. **Owner:** testar ambas as bordas geométricas, carta alta, offset persistido, modal e relaunch antes de mesclar; evitar novo owner de posição.

### P1-04 — Diagnóstico #14 é útil, mas mede após a transição e não é prova de correção (ABERTO)

**Fato:** [#14 FeedNativeScrollOffset.swift:272–346](https://github.com/wsmontes/feedmine_v2/blob/e02a69ae/Sources/FeedMineUI/FeedNativeScrollOffset.swift#L272-L346) expõe em DEBUG identidade do capture e do scroll, montagem, `windowSequence`/`windowRevision`, contagens, âncora e offset, com marcador final de integridade. [#14 ReadingSurfaceUITests.swift:282–388](https://github.com/wsmontes/feedmine_v2/blob/e02a69ae/FeedMineApp/FeedMineAppTests/ReadingSurfaceUITests.swift#L282-L388) preserva baseline antes do Safari, duas amostras pós-fechamento e árvore AX em falhas. Os refinamentos do #14 corrigiram referências nativas obsoletas e falsos positivos de diagnóstico incompleto, **sem execução UIKit/XCTest**.

**Limite observável:** `immediatelyAfter` é coletado **depois** de esperar o botão Close desaparecer; a desmontagem/remontagem durante o modal pode ter terminado antes da amostra. A consulta `diagnostic.exists` seguida de `diagnostic.value` continua sujeita a desaparecimento entre consultas. Além disso, a branch #14 está **divergente** do HEAD #13 (20 à frente, 1 atrás); o commit exclusivo do #13 é de attachment de métricas, portado ao método compartilhado de #14, mas a integração de branches não foi feita. **Owner:** tratar a sonda como instrumento de classificação, não solução; conferir baseline válida e fonte/commit de cada evidência, e priorizar executar em iOS em vez de ampliar a sonda indefinidamente.

### P1-05 — Workflow A/B preparado, mas ainda sem prova de execução (ABERTO)

**Fato:** [#15 .github/workflows/safari-ab-ios18.yml:1–204](https://github.com/wsmontes/feedmine_v2/blob/18ad774b/.github/workflows/safari-ab-ios18.yml#L1-L204) define trigger somente `pull_request: labeled` com `run-ios-safari` no próprio PR #15, checkout read-only, macOS 15/Xcode 16.4, iPhone 16/iOS 18.5, SHA congelado, checagem de blob de teste idêntico, `build-for-testing` isolado e 3× controle / 3× experimento intercalados / 1× diagnóstico. Registra `.xcresult` e valida que cada seleção executou **um teste**, não só exit0. [Commit final #15](https://github.com/wsmontes/feedmine_v2/commit/18ad774bf16297b982870fc2164b10e9dd7d9dea) confere o SHA do worktree. O PR relata duas falhas anteriores de configuração em `push`, sem jobs; não há execução macOS/XCTest comprovada.

**Risco:** um workflow existente em draft não é prova de build nem de compatibilidade real do runner/simulador; a fixture sintética ainda não reproduz publicação concorrente. **Owner:** acionar explicitamente quando pronto, verificar se o workflow inicia e compila, preservar inclusive falhas e comparar frames; não editar benchmark congelado nem reportar CI como PASS antes de inspecionar artefatos.

### P1-06 — Integração e ownership continuam o maior risco sistêmico (ABERTO)

**Fato:** as linhas #10–#13/#15 partem da main antiga, #14 é stacked sobre #13, enquanto #6 F13, #8 render-ready e #9 transições seguem independentes. Nenhum dos seis PRs novos integra preparação A→B, política render-ready ou gates B03/B04/B05 na mesma árvore. [#9 AppComposition.swift:814–855](https://github.com/wsmontes/feedmine_v2/blob/3e863a1c/FeedMineApp/FeedMineApp/AppComposition.swift#L814-L855) e [#6 AppComposition.swift:1187–1217](https://github.com/wsmontes/feedmine_v2/blob/c0392741/FeedMineApp/FeedMineApp/AppComposition.swift#L1187-L1217) continuam representando semânticas diferentes de transição. **Opinião técnica:** não somar todos os gates, retries e diagnósticos como mecanismos de produção. **Owner:** incorporar apenas o oráculo/patch que demonstrar benefício na árvore F13, manter uma autoridade de posição e sessão, portar os testes de falha #9 sem copiar um segundo controlador.

### P0-01 — Admissão render-ready (ABERTO, inalterado)

**Fato estático:** [#8 FeedSession.swift:437–485](https://github.com/wsmontes/feedmine_v2/blob/83f05671/Sources/FeedMineRuntime/FeedSession.swift#L437-L485) mantém histórico projetado com mídia decodificada somente perto da âncora, enquanto a lista histórica permanece apresentada; [FeedScreenStore.swift:137–161](https://github.com/wsmontes/feedmine_v2/blob/83f05671/Sources/FeedMineUI/FeedScreenStore.swift#L137-L161) consome essa projeção. A [regra vinculante](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md) exige pixels prontos **antes** de admissão. **Owner:** separar história durável de janela visual render-ready no owner existente; provar 750→1→750, mídia ausente e retorno sem placeholder. Não decodificar todo o histórico nem deslocar o trabalho para a View.

### P0-02 — B03/runway (ABERTO, FAIL histórico não revogado)

**Fato:** os novos PRs não executam o [B03 congelado](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L68-L80): 30 minutos de **avanços reais**, 1 card/s, rajadas 3/s, sem pausa visível ≥1 s por falta de runway nem fim artificial com oferta elegível. O FAIL histórico (~5,70 s de pausa) não é apagado por testes de Safari ou pela antiga tabela documental de PASS. **Owner:** medir a árvore integrada e preservar corpus/runner/oráculo/trace originais; B04/B05 no mesmo SHA.

### P0-03 — Redirect privado validado tarde (ABERTO, inalterado)

**Fato:** [FeedDiscoveryTransport.swift:75–90](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) verifica a URL inicial, permite `URLSession.bytes(for:)` seguir redirects e só então rejeita host final privado. **Risco inferido, não exploração demonstrada:** conexão privada pode ocorrer antes do veto. **Owner:** vetar cada salto antes de conectar, com prova público→privado e zero conexões privadas.

### P2 — Evidência/release (ABERTO)

Não executei XCTest, Xcode, simulador, iPhone nem benchmark. Os testes de #10–#14 estão em código; #15 é infraestrutura **não executada**. Os resultados de macOS/iOS versionados em #6 são históricos e não certificam estas branches. **R4 integral NÃO ACEITO; B03 FAIL histórico; B06 NOT_RUN; B02/B04/B05 sem PASS integrado novo; release NÃO APROVADA.** Persistem salvos/coleções/fontes, catálogo PD-10/INV-18, reabertura offline e estabilidade A→B→A como provas integradas pendentes.

## 4. Ordem mínima e comandos/provas no Mac — NÃO EXECUTADOS PELO MONITOR

**Prioridade:** (1) reproduzir retorno Safari no controle; (2) A/B #13 com UUID/frame e sonda #14; (3) portar somente solução demonstrada para F13 e repetir com publicação ativa; (4) unir testes de falha #9 sem duplicar ownership; (5) fechar render-ready e B03/B04/B05; (6) corrigir redirect e executar B06 físico. Não gastar a próxima rodada exclusivamente polindo o diagnóstico.

```bash
git fetch origin main monitor/architecture audit/browser-return-identity-regression-20261030 experiment/reader-host-over-full-screen-20261030 diagnostic/safari-viewport-probe-20261030 ci/safari-ab-ios18-20261030 product/nf04-tail-truth chatgpt/render-ready-contract-red-01 audit/session-transition-failure-probe-20261030
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git diff --check origin/main..origin/experiment/reader-host-over-full-screen-20261030
git worktree add --detach /tmp/fm-safari-control origin/audit/browser-return-identity-regression-20261030
git worktree add --detach /tmp/fm-safari-overlay origin/experiment/reader-host-over-full-screen-20261030
git worktree add --detach /tmp/fm-safari-diag origin/diagnostic/safari-viewport-probe-20261030
xcrun simctl list devices available
# Selecionar UDID iOS 18+; executar o MESMO teste de retorno 3x em cada
# worktree control/overlay, com build-for-testing e test-without-building,
# -resultBundlePath único por execução e -parallel-testing-enabled NO:
# FeedMineUITests/ReadingSurfaceUITests/testClosingSitePreservesScrolledCardIdentityAndFrameWithDeepHistory
# Em diag, rodar:
# FeedMineUITests/ReadingSurfaceUITests/testSafariViewportDiagnosisCapturesMountWindowAndAnchor
# Guardar logs, xcresult, screenshots, video, UUID, minY/maxY, offset nativo,
# windowSequence/windowRevision, captura AX e SHA do binário/fixture.
# Repetir na árvore integrada F13 com publicação concorrente e relaunch offline.
```

**Critérios observáveis:** controle versus experimento com mesmas cartas/frames, nenhum gesto corretivo, três repetições por braço; captura realmente montada e válida; o mesmo card visível no mesmo lugar ao fechar; ausência de alteração silenciosa de IDs, ordem e geometria sob publicação; nenhuma perda A→B→A ou de salvos offline; B03 completo no corpus congelado. Se um teste falhar, guardar evidência e classificar FAIL, não reduzir o oráculo.

## 5. Memória compacta para próxima execução

- **Monitor:** 037 `34b39a53` → 038 `33cedde0` → 039 `2464c5dc` → 040 `e3524bcf` → 041 `5842ce1c` → 042 `d4c3c5c1` → **043 (este documento)**. Blob anterior `85706970`.
- **Imóveis:** main `fb8e65ff`; F13 #6 `c0392741`; render #8 `83f05671`; audit transições #9 `3e863a1c`; reserve `a8814282`; integrity `031b27d3`; next `d6a05266`; release `cede37f6`; integration/chatgpt `8203d439`; integration/main-into-app-line `09a6e3a4`; candidate histórica `1b990306`.
- **Novos:** #10 `f4f041c0` teste retorno; #11 `9bd7b345` predicado viewport; #12 `95b894f7` reset motion; #13 `cf2ce6a8` overlay; #14 `e02a69ae` sonda stacked (20 ahead/1 behind #13); #15 `18ad774b` CI A/B opt-in. Todos draft, **sem XCTest iOS comprovado**. Teste compartilhado #10/#13 blob `b94cfaa0`.
- **Resolvido nesta janela:** existência de oráculo discriminante de identidade/frame e instrumentação capaz de separar hipóteses **em código**; não confundir com defeito resolvido. **Abertos:** browser-close real, P0 render-ready/B03/redirect, R4 integral, integração F13/#9/#13, offline/scroll/filtros/salvos, PD-10 e B06.
- **Gates:** R4 completo NÃO ACEITO; B03 FAIL histórico; B06 NOT_RUN; release NÃO APROVADA. Nenhum PASS novo de simulator/XCTest/benchmark nesta revisão.
- **Handoff:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Monitor consultivo; não altera main, código, testes, benchmarks, coordenação, issues nem PRs.
