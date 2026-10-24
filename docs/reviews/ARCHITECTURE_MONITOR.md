# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 026 · Vancouver, 24/out/2026, 11:45 PDT.** Canal consultivo `monitor/architecture`. O OMP deve fazer fetch e ler este arquivo; não há notificação automática.

## Base, intervalo e escopo verificado

**Anterior:** [monitor 025](https://github.com/wsmontes/feedmine_v2/commit/309c1d209081dcb92bfc01024487d41d90b56d48), 24/out 01:43 PDT; blob anterior `e52c78c6d2d566fd1e31aec39b0b24b66034d704`. **Intervalo:** 24/out 01:43–11:45 PDT. A linha corrente [`codex/feedmine-next-internal`](https://github.com/wsmontes/feedmine_v2/tree/codex/feedmine-next-internal) avançou **11 commits**, de `2d430c5e7f656c78fb46b4a0e2220153b0a56df7` para **`d6a052667abfd478d5e09f13afe0e01685ef9344`** ([diff exato](https://github.com/wsmontes/feedmine_v2/compare/2d430c5e...d6a05266)). Mudou 9 arquivos: `AppComposition.swift`, `FeedMineApp.swift`, dois testes do host, três arquivos UI de filtro e dois documentos. **Nenhuma alteração** em benchmark, transporte de descoberta, runtime de mídia, `FeedRunwayDriver.swift` ou scripts de release nesse intervalo.

`main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48` continua idêntica à revisão 025 (compare `identical`). PR [#5](https://github.com/wsmontes/feedmine_v2/pull/5) continua aberto, HEAD `5b252eaa`, sem atualização; não é PR docs-only para merge porque herda código da build 54. Linhas 54: `3eee1935` (validação), `15d8bbbc` (mídia), `145d12a3` (mídia/release), `77e9f7d1` (posição), sem avanço. `integration/candidate@1b990306` (14/out), `integration/chatgpt@8203d439` (14/out), `integration/main-into-app-line@09a6e3a4` (12/out) são históricas neste intervalo, **não** candidatas correntes. A linha de desenvolvimento atual é `codex/feedmine-next-internal`.

Normas relidas na `main`: [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [decisões PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md) e [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md). Direção mais recente de NF-01–16 e NF-03 lida na [linha corrente](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/docs/product/NOVAS_FRENTES_PARA_O_CODEX.md). O documento de frentes é subordinado às normas, não substituto delas.

## Resumo executivo — consequência para a experiência

**Progresso real e focal na NF-03 (Concluído dos filtros).** O código agora separa confirmação **durável** do filtro de ativação da nova sessão: a folha fecha depois da gravação, não depois do HTTP/launch; a apresentação antiga permanece identificada como **“Feed anterior”** até a nova ficar pronta; uma falha posterior é reportada como **salvo, mas ainda não apresentado**. Testes novos usam transporte suspenso, recusa SQLite, A→B→A e checkpoint falho. Isso remove estaticamente a espera antiga do botão **Concluído**; não demonstra ainda a latência de toque→fechamento num iPhone.

**A correção é parcial no produto:** selecionar um **preset salvo** na mesma folha ainda percorre outro caminho que aguarda o launch completo, sem estado ocupado, e pode **fechar sem ter trocado o contexto** quando outra transição está em curso. Além disso, a confirmação durável usa `Task.detached` e atualiza `currentContextKey` após um `await`; duas confirmações concorrentes de superfícies diferentes não têm fence explícita que associe a última intenção à última gravação. Esses são os novos pontos de maior valor para o owner.

O último commit corrige **somente a espera do teste R01**, não a implementação do runway: `viewportDrainIdle` DEBUG espera o consumidor concluir, em vez de confundir resumo vazio com trabalho concluído. A regressão global 189/1 anterior e o focal 1/0 posterior são **relatos do executor**, não execução deste monitor; a suíte global não foi repetida após o fence.

**Nenhuma mudança desta janela resolve ou mede** a cauda prematura observada na build 55, o redirect inseguro ou B01–B06 da candidata. Priorizar a experiência contínua, não a contagem de testes.

## Mudanças verificadas (código → produto → regressão)

1. [`4fdea9d8`](https://github.com/wsmontes/feedmine_v2/commit/4fdea9d8a75dc030a8320ae635eb20f3b6c38573): `confirmFilter` grava contexto+expiry fora do MainActor via pool GRDB; `applyFilterFromSheet` retorna após commit e inicia `activateConfirmedFilter` no owner existente. [`AppComposition.swift:1017–1072`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L1017-L1072). **Ganho:** folha deixa de aguardar rede. **Risco:** concorrência entre confirmação, outros controles e ativação.
2. [`2c97a6d0`](https://github.com/wsmontes/feedmine_v2/commit/2c97a6d0c3eeb13ad3d69034bcc9f43e9e5fa569): `filterSelectionForLens`, rótulo de feed anterior, desabilitação de controles durante gravação e do chip durante handoff. [`AppComposition.swift:1074–1087`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L1074-L1087), [`FilterSheetView.swift:309–344`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/Sources/FeedMineUI/Filters/FilterSheetView.swift#L309-L344), [`ReaderFilterLens.swift:55–81`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/Sources/FeedMineUI/Filters/ReaderFilterLens.swift#L55-L81). **Ganho:** não fingir que o feed antigo já atende ao novo filtro. **Risco:** a folha ainda tem caminhos de ativação que não passam pelo mesmo limite.
3. Fence pós-checkpoint em [`AppComposition.swift:2245–2295`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L2245-L2295): revalida o contexto depois de `await checkpoint` e instala a nova associação antes de fechar a anterior. **Ganho:** uma conclusão superada não assume a tela no ponto de instalação; preserva a apresentação durante a troca. **Limite:** não cobre automaticamente transições de outras APIs que chamam `replaceSession()` sem preservação.
4. [`FilterConfirmationBoundaryTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineAppTests/FilterConfirmationBoundaryTests.swift) cresceu com provas de HTTP suspenso, escritor SQLite ocupado, rollback antes de commit, falha após commit, A→B→A, fechamento tardio e lente. O registro [NF-03:249–301](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/docs/product/NOVAS_FRENTES_PARA_O_CODEX.md#L249-L301) relata **13/13** na classe final e **118/118** em CompositionTests focal; não é PASS de UI/dispositivo ou NF-07 global.
5. [`d6a05266`](https://github.com/wsmontes/feedmine_v2/commit/d6a052667abfd478d5e09f13afe0e01685ef9344) documenta a conclusão do consumidor R01. [`AppComposition.swift:3784–3790`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L3784-L3790) expõe `viewportDrainIdle` apenas em DEBUG; [`CompositionTests.swift:1865–1877`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineAppTests/CompositionTests.swift#L1865-L1877) espera o consumidor real. [Registro R01:195–207](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/docs/reviews/2026-10-17-v2-plan-execution.md#L195-L207): 189/1 global antes do fence, focal 1/0 depois, **global não repetido**. **Fato:** teste anterior podia medir antes de o último fato concluir; **não** é prova nova de continuidade no iPhone.

## Achados prioritários — fato, hipótese, orientação e prova

### P0 produto — cauda do feed antes da reposição (aberto; sem nova evidência física)

**FATO relatado pelo dono:** build 55 rola suavemente mas alcança a cauda antes de aparecer conteúdo novo ([NF-01/NF-05](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/docs/product/NOVAS_FRENTES_PARA_O_CODEX.md#L154-L188)). **FATO desta revisão:** os 11 commits não alteraram `RunwayController` nem `FeedRunwayDriver`; a medição NF-05 do monitor 025 permanece apenas demanda→receipt, não demanda→admissão UI. **HIPÓTESE ainda aberta:** antecipação insuficiente de aquisição, pouca oferta elegível, ou handoff tardio. **Owner:** uma única trilha causal consumo→demanda→HTTP→mídia→publicação→admissão visual, sob consumo rápido, lento e repouso. Não acrescentar timer, segundo scheduler ou cota fixa.

### P0 segurança — redirect de descoberta validado depois da conexão (aberto)

**FATO estático:** [`FeedDiscoveryTransport.swift:75–90`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) chama `URLSession.bytes(for:)` e só então valida o host final. O arquivo não mudou neste intervalo. **RISCO/HIPÓTESE de exploração:** um redirect automático pode contatar destino proibido antes da recusa (SSRF). **Owner:** recusar cada hop antes de conectar e conferir destino efetivo; **prova:** servidor privado vedado registra zero requests, destino público permitido continua funcionando.

### P1 NOVO — preset salvo ainda espera rede e pode encerrar a folha sem transição

**FATO estático:** [`FilterSheetView.swift:151–166`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/Sources/FeedMineUI/Filters/FilterSheetView.swift#L151-L166) usa `await onActivate(key)` **antes** de `onDone()`, sem `isApplying` nem feedback de ocupação. O host liga isso a [`activateSavedPreset`:1145–1169](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L1145-L1169), que aposenta a associação e aguarda `next.launch()`. **FATO adicional:** o `guard !replacingSession, let preferences else { return }` retorna **sucesso aparente sem executar** quando há transição em curso; o chamador então chama `onDone()`. **Consequência provável:** o botão Concluído ficou rápido, mas selecionar feed salvo na mesma folha continua lento; num conflito de transições a folha pode fechar sem mudança. **Owner:** reutilizar a mesma fronteira de confirmação durável/ativação e estado ocupado; um comando não executado deve ser recusado explicitamente, nunca tratado como sucesso. **Prova:** selecionar preset salvo com HTTP suspenso e, separadamente, durante `replacingSession=true`; exigir feedback imediato, resultado durável honesto, folha não fechar em no-op e restauração A→B→A.

### P1 NOVO — duas confirmações assíncronas podem discordar da última intenção

**FATO estático:** [`confirmFilter`:1021–1041](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L1021-L1041) monta `key` do estado corrente, suspende em `Task.detached(...).value` para `setFilterSelection` e só depois atribui `currentContextKey = key`; não há token de ordem/fence na conclusão. [`FeedMineApp.swift:1804–1829`](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/FeedMineApp.swift#L1804-L1829) permite disparar remoções por chips em `Task` independentes, antes de a primeira confirmação estabelecer o handoff. O `isApplying` protege **a folha**, não todas as superfícies. **HIPÓTESE de corrida:** A e B gravam serialmente no SQLite, mas suas continuações podem retomar em ordem diferente; memória, registro durável e sessão podem terminar em chaves diferentes, ou duas remoções feitas sobre a mesma lente perderem uma intenção. **Owner:** serializar/confundir apenas o compromisso de identidade no owner atual ou verificar versão/última intenção antes de atualizar memória; não criar outro registry. **Prova:** segurar o primeiro writer, emitir segunda intenção de chip/folha, liberar em ordem adversarial; comparar `reader_preferences.active_context`, `currentContextKey`, `association.contextKey`, os chips e a posição após relaunch. Os testes A→B→A existentes confirmam sucessivamente; não provam dois commits simultâneos.

### P1 residual — transição mista pode escapar da preservação do feed anterior

**FATO de fluxo:** [`replaceSession`:2233–2245](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L2233-L2245) devolve cedo se outro replacement está em andamento, marcando `pendingRebuild`; o laço que executa o rebuild conserva o parâmetro `preservingReaderDuringFilter` da chamada **original**. Se a chamada original era não preservadora, o ramo [2295–2314](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L2295-L2314) ainda fecha a associação antiga antes do lançamento. **HIPÓTESE:** uma confirmação NF-03 durante rebuild de outra origem não recebe a preservação prometida. **Owner:** fixture de transição mista (rebuild normal suspenso → confirmar filtro → concluir primeiro rebuild) e exigir que nenhum resultado superado assuma a tela e que o último filtro seja apresentado sem janela vazia. Evitar alterar a ordem histórica de busca sem prova.

### P2 — lente pendente mistura filtro do contexto e exclusões globais

**FATO estático:** durante handoff, [`filterSelectionForLens`:1082–1086](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L1082-L1086) retorna `association.contextKey.filter` (filtro **aplicado**); [`applied(_:) `:1291–1304](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L1291-L1304) acrescenta exclusões globais. O contrato de `currentFilter` em [95–100](https://github.com/wsmontes/feedmine_v2/blob/d6a05266/FeedMineApp/FeedMineApp/AppComposition.swift#L95-L100) é o filtro **cru** da lente. **RISCO UX, não perda de dados demonstrada:** durante a espera pode aparecer chip de exclusões globais como se fosse parte do contexto. O chip está desabilitado, limitando o dano. **Prova:** master switch de exclusões globais ligado, filtro local sem exclusões, confirmar outro filtro com launch suspenso e comparar chips antes/durante/depois. Não criar cache para corrigir a representação.

## Pendências anteriores e classificação atual

| Tema | Estado após 026 |
|---|---|
| A→B→A de mídia por Edition | **Corrigido estaticamente na 55**; migração e jornada offline não certificadas |
| Retenção editorial de mídia | **Elegibilidade preservada na 55**; latência do 33º e oportunidade real ainda não provadas |
| NF-03 Concluído | **Corrigido estaticamente** para o botão; prova focal relatada; UI física pendente |
| NF-03 preset salvo / concorrência / transição mista | **P1 aberto/novo** nesta revisão |
| R01 resumo de viewport | Implementação anterior mantida; **fence de teste corrigido**; full suite pós-fence não repetida |
| NF-01/NF-05 continuidade até UI | **P0 produto aberto**; trace e B03 faltam |
| Redirect privado | **P0 segurança aberto** |
| B05 driver e manifesto modificados entre 54/55 | **P1 auditoria pendente**; nenhum arquivo bench alterado em 026 |
| D4, scroll/âncora ±1 pt, reabertura offline | Não certificados na árvore corrente |
| Salvos V1→V2, fontes/aliases, coleções | Migração/paridade integral ainda não demonstradas |
| Diversidade editorial, YouTube/vídeo, podcast, site original | Jornadas reais pendentes; presença de tipos não é paridade |
| Paginação durável 10k/100k | **P2 hipótese**; índice da 55 melhorou, custo não medido aqui |

## Release — evidência, não suposição

**P0 de certificação (ausência de prova, não defeito runtime P0 novo):** não há matriz completa B01–B06/PD-10 vinculada a **um mesmo SHA/binário** posterior a `3c5bdc11`. A build 55 preparada tem SHA `3c5bdc11`, mas o pareamento do binário distribuído precisa de archive/recibo. Os 11 commits posteriores à revisão 025 **não** alteram número de build, scripts de release ou avaliador. A mudança de hash/driver B05 entre 54 e 55 permanece sob auditoria; não transportar PASS antigo. B06 físico não foi executado por este monitor.

Relatos de execução dos executores (não independentes): NF-03 `FilterConfirmationBoundaryTests` 13/13, `CompositionTests` 118/118; R01 após fence 1/0 focal, full 189/1 **antes** do fence e **não repetido**. Não afirmar PASS de XCTest global, B01–B06, simulador ou iPhone a partir desses números. **Este monitor executou leitura e inspeção estática; nenhum teste local.**

## Handoff mínimo ao Mac — comandos e provas discriminantes

```bash
git fetch origin main monitor/architecture codex/feedmine-next-internal
git log -1 --format='%H %cI %s' origin/codex/feedmine-next-internal
git diff --check 2d430c5e..origin/codex/feedmine-next-internal
git diff --stat 2d430c5e..origin/codex/feedmine-next-internal
git diff 2d430c5e..origin/codex/feedmine-next-internal -- FeedMineApp/FeedMineApp/AppComposition.swift Sources/FeedMineUI/Filters/FilterSheetView.swift
# Em worktree isolada do SHA exato, sem tocar na main:
git switch --detach d6a052667abfd478d5e09f13afe0e01685ef9344
swift build
swift test
xcrun simctl list devices available
# Substituir UDID por simulador iOS 18+ disponível; guardar xcresult/log:
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO \
  -only-testing:FeedMineAppTests/FilterConfirmationBoundaryTests \
  -resultBundlePath /tmp/fm-monitor-026-filter.xcresult CODE_SIGNING_ALLOWED=NO test
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO \
  -resultBundlePath /tmp/fm-monitor-026-full.xcresult CODE_SIGNING_ALLOWED=NO test
```

**Provas prioritárias:** (1) preset salvo com launch/HTTP suspenso, sem fechamento enganoso; (2) duas confirmações sobrepostas e última intenção consistente em SQLite/memória/sessão; (3) filtro confirmado durante replacement não preservador; (4) toque→feedback/fechamento no iPhone e lente/pending com acessibilidade; (5) R01 full AppUnits depois do fence; (6) trace da cauda até admissão visual; (7) redirect vedado com zero conexões; (8) B01–B05 e D4/App180 na árvore certificável, B06 em aparelho físico, PD-10 com proveniência de catálogo. Respeitar guard de disco e avaliador congelado; não inventar PASS nem bypass.

## Memória compacta / últimos SHAs

Monitor 014 `b7d385a9` → 023 `039bf1d5` → 024 `918a2c8b` → 025 `309c1d20` (blob `e52c78c6`) → **026, base de análise `d6a05266`**. `main@fb8e65ff` documental e imóvel; linha 54 `3eee1935`, mídia `15d8bbbc`, release `145d12a3`, posição `77e9f7d1`; build 55 preparada `3c5bdc11`; trabalho pós-55 anterior `2d430c5e`, agora `d6a05266` (+11). **NF-03 botão Concluído corrigido estaticamente, mas preset salvo e concorrência não encerrados; R01 teste de conclusão corrigido, não B03; P0 cauda e redirect abertos; B05 auditável, B06 e certificação integral ausentes.**

**Handoff OMP:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Monitor consultivo; nenhum outro arquivo/branch/issue/PR deve ser modificado por ele.
