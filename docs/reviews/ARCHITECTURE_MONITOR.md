# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 046 · Vancouver, 30/10/2026, 21:45 PDT.** Parecer independente consultivo; **não** certificação de release. O OMP deve executar `git fetch origin monitor/architecture` e ler este arquivo explicitamente. Não há notificação automática dos executores.

## 1. Memória, janela incremental, fontes e SHAs

**Memória persistente lida antes da investigação:** revisão 045 em `monitor/architecture@8c1e9e246ebc1f40408e4012d66e9d3c45d05d7a`, blob `95880b202373e178cf6f4c92dddb63c6c1bf049f`. **Janela:** 30/out, 19:42–21:45 PDT (31/out, 02:42–04:45 UTC). Inspeção via conector GitHub: relatório anterior, arquivos normativos, PRs, diffs, branches, issues e **jobs/logs reais** de GitHub Actions; sem checkout Mac, XCTest próprio, iPhone ou benchmark executado pelo monitor.

**Mudanças relevantes:** oito novos PRs draft, [#19](https://github.com/wsmontes/feedmine_v2/pull/19) a [#26](https://github.com/wsmontes/feedmine_v2/pull/26), e [issue #18](https://github.com/wsmontes/feedmine_v2/issues/18) aberta. A [#17](https://github.com/wsmontes/feedmine_v2/pull/17) **não avançou**: `93e6cbbee11d48d4b22cd5645f6586304ee36c4a`. `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48` segue idêntica, sem merge. Os PRs novos são **linhas empilhadas**, não oito soluções independentes nem release integrada.

**Heads novos verificados (GitHub):** #19 `7b3018d3` (runner Safari); #20 `e02879b1` (primeira ligação física ready-only); #21 `267e121f` (runs disjuntos); #22 `3bc00208` (prepend/rollback); #23 `c7f54745` (checkpoint inicial ≠ exposição); #24 `91dc980f` (fixtures); #25 `67e8d4cf` (restore ≠ exposição); #26 `29153ea2` (fence durável). Stack visual: #16 `72d067bf` → #17 `93e6cbbe` → #20 `e02879b1` → #21 `267e121f` → #22 `3bc00208` → branch intermediária `fix/p0-ios-handshake-fixture-lifetime-20261030` → #23 → #24 → #25 → #26. O #19 é experimento isolado sobre main.

**Outros HEADs sem avanço, confirmados:** F13 #6 `c0392741`, render-ready #8 `83f05671`, transições #9 `3e863a1c`, Safari #10 `f4f041c0`, #11 `9bd7b345`, #12 `95b894f7`, #13 `cf2ce6a8`, #14 `e02a69ae`, #15 `18ad774b`. Também idênticas por comparação: `product/reserve-20261024@a8814282`, `product/integrity-20261024@031b27d3`, `codex/feedmine-next-internal@d6a05266`, `integration/chatgpt@8203d439`, `integration/main-into-app-line@09a6e3a4`, `release/build-56@cede37f6`, `integration/candidate@1b990306`. **Candidata histórica não é candidata atual.** A busca de branches foi paginada; branches antigas não foram tratadas como trabalho ativo.

**Autoridade normativa relida em main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [decisões PD-1–PD-10](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [regra absoluta render-ready](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md) e [README/handoff](https://github.com/wsmontes/feedmine_v2/blob/main/README.md#L1-L8). `main` e esses documentos não mudaram; não substituir decisões atuais por blueprints antigos.

## 2. Resumo executivo: progresso real e lacuna de produto

**Avanço importante, mas parcial:** #20 finalmente altera `FeedScreenStore`, `FeedInteractionPresentation` e `FeedScreen` para instalar **somente um run contíguo de células com pixels prontos**, mantendo o histórico lógico separado. Isto resolve, **no caminho inicial experimental e por inspeção de código**, a falha apontada na 045 de simplesmente entregar `window.items` cru à UI. Não resolve a jornada completa: sem ponte física medida entre runs, um hero ausente divide a leitura em trechos inacessíveis, e uma âncora durável sem pixels pode deixar **nenhuma célula montada**. Proteção contra placeholder não pode virar fim artificial ou tela vazia.

**Segundo avanço conceitual importante:** #23–#26 separam três fatos antes indevidamente confundidos: (a) posição durável, (b) exposição visual efetiva, (c) prefixo publicado que não pode ser substituído. Isso reduz o risco de declarar uma carta como vista apenas porque foi salva/restaurada e evita que a manutenção de cauda reescreva a posição preservada. A migração é aditiva. **Ainda não há validação Apple verde no HEAD #25 ou #26**, nem prova de rollback físico/scroll real.

**Evidência Apple verificada, inclusive falha:** [run #41168369874](https://github.com/wsmontes/feedmine_v2/actions/runs/41168369874), HEAD #24, **job concluído SUCCESS** com etapa de suíte SwiftPM iOS concluída SUCCESS; logs consultados mostram testes sem falha na execução. [run #41169117939](https://github.com/wsmontes/feedmine_v2/actions/runs/41169117939), SHA **`c45f7967`** de #25, **job concluído FAILURE**: `RenderReadyAdmissionContractTests.testMissingLocalHeroPixelsRemainLogicalButAreDeferredOnRestoreAndWarmStart`, linha 111, esperava `HiddenTailLease` não nulo. O HEAD posterior #25 `67e8d4cf` altera a expectativa para nil, e o HEAD #26 contém **exatamente o mesmo blob de teste corrigido**; não há novo run comprovado nesses HEADs. A #26 **não possui workflow específico de CI**. Não confundir green do pai com green do filho, nem falha da versão antiga com falha demonstrada da versão corrigida.

**Parecer de release: NÃO APROVADA.** [P0 #7](https://github.com/wsmontes/feedmine_v2/issues/7) aberta; B03 FAIL histórico (~5,70 s) sem nova medição; B06 NOT_RUN; R4 integral NÃO ACEITO; [Safari #18](https://github.com/wsmontes/feedmine_v2/issues/18) aberta, sem A/B medido; redirect privado ainda não vetado antes da conexão. Sem uma árvore única contendo F13 + visual + persistência + transições + Safari, nenhuma prova de experiência integrada pode ser inferida.

## 3. Achados priorizados — fatos, hipóteses, consequência e ação mínima

### P0-01 — Ready-only chegou à UI experimental, mas a navegação entre trechos continua bloqueada (PARCIALMENTE RESOLVIDO)

**Fato comprovado em código:** [#20, `FeedReadyWindowOwnership.swift:25–43`](https://github.com/wsmontes/feedmine_v2/blob/e02879b1/Sources/FeedMineUI/FeedReadyWindowOwnership.swift#L25-L43) seleciona somente o run pronto contíguo contendo a âncora; se a âncora não estiver pronta, retorna nil. [`FeedScreenStore.swift:137–189`](https://github.com/wsmontes/feedmine_v2/blob/e02879b1/Sources/FeedMineUI/FeedScreenStore.swift#L137-L189) mantém histórico lógico, mas publica `renderedItems = next?.cards ?? []` quando muda o escopo; no mesmo escopo aceita apenas `nextIDs.starts(with: previousIDs)` e conserva a janela anterior em prepend/trim/reentrada. [`FeedInteractionPresentation.swift:11–18, 44–61`](https://github.com/wsmontes/feedmine_v2/blob/e02879b1/Sources/FeedMineUI/FeedInteractionPresentation.swift#L11-L61) empresta células físicas prontas durante gestos. [`FeedScreen.swift:86–108`](https://github.com/wsmontes/feedmine_v2/blob/e02879b1/Sources/FeedMineUI/FeedScreen.swift#L86-L108) efetivamente desenha essas células; [`FeedScreen.swift:205–219`](https://github.com/wsmontes/feedmine_v2/blob/e02879b1/Sources/FeedMineUI/FeedScreen.swift#L205-L219) não anuncia fim quando a janela física termina antes do histórico lógico. **É um progresso de código, não teste de UX aprovado.**

**Consequência/risco (inferência direta do fluxo, sem reprodução iOS):** com histórico `[texto A, hero sem pixels, texto B]`, a janela A não alcança B; se o checkpoint aponta para hero deferred, o primeiro desenho pode ficar vazio. Isto preserva imutabilidade e evita placeholders, mas ainda viola a promessa de leitura contínua e reabertura útil. **Owner:** instalar um único handoff físico medido e reidratação local por banda; não achatar gaps, inventar altura, pular ID ou forçar uma nova sessão. Provar 750→1→750, anchor deferred, normal/held, crescimento e scroll simultâneo.

### P1-01 — Witness físico e rollback exigidos; testes novos ainda não conectam o host (ABERTO)

**Fato:** [#21, `FeedReadyWindowOwnershipTests.swift:53–128`](https://github.com/wsmontes/feedmine_v2/blob/267e121f/Tests/FeedMineCompositionTests/FeedReadyWindowOwnershipTests.swift#L53-L128) rejeita passagem entre dois runs sem carta visível comum. [#22, `FeedNativeReadyWindowHandshakeTests.swift:49–148`](https://github.com/wsmontes/feedmine_v2/blob/3bc00208/Tests/ArchitectureSmokeTests/FeedNativeReadyWindowHandshakeTests.swift#L49-L148) exige correção única de offset para prepend sobreposto e, no cancelamento, restauração de IDs **e** offset originais. O [ownership da #20:46–49](https://github.com/wsmontes/feedmine_v2/blob/e02879b1/Sources/FeedMineUI/FeedReadyWindowOwnership.swift#L46-L49) ainda descreve adaptador futuro; a UI real não invoca a transação de swap. Testes são contratos adicionados, não comprovação de execução nesses heads.

**Hipótese/risco:** introduzir um segundo writer de offset ou confirmar antes de geometria real fará o leitor saltar ou perder a carta, sobretudo durante gesto. **Owner:** uma única autoridade de scroll, witness do mesmo UUID/frame antes/depois, gesto idle, rollback físico no cancelamento. Medir no simulador e guardar `.xcresult`/trace; não ampliar máquinas de estado sem ligá-las à view.

### P1-02 — Checkpoint, exposição e prefixo protegido finalmente separados (NOVO, código promissor; gate aberto)

**Fato:** [#23, `SessionStore.swift:58–77`](https://github.com/wsmontes/feedmine_v2/blob/c7f54745/Sources/FeedMinePersistence/SessionStore.swift#L58-L77) deixa de marcar a primeira carta como vista ao persistir checkpoint inicial. [#25, `FeedSession.swift:447–471`](https://github.com/wsmontes/feedmine_v2/blob/67e8d4cf/Sources/FeedMineRuntime/FeedSession.swift#L447-L471) deixa de chamar `markSeen` em projeção de restore/warmStart; a observação aceita em [`FeedSession.swift:189–195`](https://github.com/wsmontes/feedmine_v2/blob/67e8d4cf/Sources/FeedMineRuntime/FeedSession.swift#L189-L195) continua o caminho de exposição. [#26, `SessionStore.swift:35–53, 58–77`](https://github.com/wsmontes/feedmine_v2/blob/29153ea2/Sources/FeedMinePersistence/SessionStore.swift#L35-L77) passa a proteger a posição durável sem criar high-water visto. [`PublicationStore+History.swift:60–125`](https://github.com/wsmontes/feedmine_v2/blob/29153ea2/Sources/FeedMinePersistence/PublicationStore+History.swift#L60-L125) aplica fence monotônico, invalida lease ao avançar e calcula cauda protegida. [`RuntimeMigrations.swift:562–586`](https://github.com/wsmontes/feedmine_v2/blob/29153ea2/Sources/FeedMinePersistence/RuntimeMigrations.swift#L562-L586) cria `edition_position_protection` e backfill do checkpoint mais avançado por edição sem apagar dados.

**Consequência positiva:** salvar/restaurar não infla artificialmente leitura vista, e o histórico salvo não vira cauda substituível por engano. **Limite:** bancos legados podem ter high-water falsamente criado no passado; a migração não consegue reconstruir sua proveniência. **Hipótese a testar:** outros caminhos diretos de checkpoint/editorial podem precisar da mesma fronteira; nenhum PASS de migração com base legada real foi visto para #26. **Owner:** preservar o desenho com três fatos, rodar migração sobre cópia de banco antigo e validar cauda, bookmarks, coleções, fontes, posições em múltiplos contextos e crash/rollback. Evitar segundo store ou policy paralela.

### P1-03 — Apple XCTest: base verde, filho vermelho em fixture e correção ainda não reexecutada (NOVO, fato observado)

**Evidência real, não apenas descrição de PR:** [#23 run #41167819796](https://github.com/wsmontes/feedmine_v2/actions/runs/41167819796) **FAIL**, duas fixtures de exposição/montagem; [#24 run #41168369874](https://github.com/wsmontes/feedmine_v2/actions/runs/41168369874) **SUCCESS** após alinhamento dos testes. [#25 run #41169117939](https://github.com/wsmontes/feedmine_v2/actions/runs/41169117939) **FAIL** no SHA `c45f7967`, teste `RenderReadyAdmissionContractTests.swift:111`, porque ainda exigia `HiddenTailLease` após restore que corretamente não marca seen. [Diff da correção no HEAD #25](https://github.com/wsmontes/feedmine_v2/compare/c45f79678970a4ea2ff0a3b004f7d1aaa3ec9e80...67e8d4cf2b402fb465968796ae763699aa962bec) muda a asserção para nil; leitura dos blobs confirmou o **mesmo conteúdo corrigido** no HEAD #26. `compare(#25 atual,#26)` retorna `diverged` (8 ahead, 1 behind) por ancestralidade, **não** ausência material desse fix no arquivo. Nenhum job Apple verificado para `67e8d4cf` ou `29153ea2`.

**Owner:** não promover o PASS do #24 para #25/#26; executar suíte iOS no SHA final #26, guardar logs e `.xcresult`, investigar quaisquer novos FAILs sem afrouxar contratos. O runner não substitui app real com catálogo íntegro e testes de geometria.

### P1-04 — F13, transições, Safari, filtros e dados pessoais continuam separados (ABERTO)

**Fato:** #6 F13, #9 concorrência/falhas, #13 hipótese `.overFullScreen` e #20–#26 ready/persistência ainda não compõem um HEAD único. [#19, `scripts/run-browser-return-ab.sh:1–99`](https://github.com/wsmontes/feedmine_v2/blob/7b3018d3/scripts/run-browser-return-ab.sh#L1-L99) prepara comparação reprodutível de [#10](https://github.com/wsmontes/feedmine_v2/pull/10) contra [#13](https://github.com/wsmontes/feedmine_v2/pull/13), fixa SHA dos braços, exige catálogo real/manifesto e mesmo simulador; **não há execução A/B comprovada**. [Issue #18](https://github.com/wsmontes/feedmine_v2/issues/18) é regressão histórica relatada, não falha atual reproduzida. **Risco:** cherry-pick mecânico pode reintroduzir encerramento de A antes de B, perda de posição, filtros destrutivos, estado offline inconsistente ou ownership duplicado. **Owner:** integrar sobre composição F13, sem segunda fila/cache/timer/retry; testar A→B→A sob SQLite fault, Safari 3x com UUID/frame ±1 pt, publicação concorrente, reabertura offline e persistência de salvos/coleções/fontes.

### P0-02 — Runway adaptativa B03 (ABERTO, FAIL histórico)

[B03 vigente](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L68-L90): 30 min de **avanços efetivos**, 1 card/s com rajadas 3/s, zero fim artificial e zero espera visível ≥1 s por falta de reserva em corpus elegível. O FAIL histórico ~5,70 s não foi revogado por novo trace. Uma janela render-ready curta pode agravar essa experiência. **Owner:** rodar avaliador externo congelado no SHA integrado, com B04/B05, logs brutos e IDs realmente consumidos; não confundir teste unitário de janela com B03.

### P0-03 — Redirect público→privado ainda pode conectar antes de vetar (ABERTO)

[`FeedDiscoveryTransport.swift:75–90` na main](https://github.com/wsmontes/feedmine_v2/blob/fb8e65ff/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) valida destino após `URLSession.bytes(for:)`, que pode seguir redirecionamento antes da validação. **Fato de ordem do código; exploração não observada.** **Owner:** validar cada salto antes da conexão e provar zero conexões privadas com fixture público→privado.

### P2 — CI, documentação e release packaging (ABERTO)

#20–#22 incluem contratos sem execução Apple verificada nesta revisão; #23–#25 possuem evidências **específicas de SHA**, com FAIL e PASS distintos; #26 não possui workflow branch-specific. A presença de workflow não certifica testes, app build, catálogo PD-10 ou benchmark. Não houve alterações de docs normativas na main, nem release nova. **PD-10/INV-18** continuam exigindo manifesto/catálogo versionado e prova de entrega, não apenas `swift test`. B06 permanece NOT_RUN. Nenhuma evidência de iPhone físico ou aprovação de release.

## 4. Provas mínimas no Mac — comandos sugeridos, NÃO EXECUTADOS PELO MONITOR

```bash
git fetch origin main monitor/architecture \
  product/nf04-tail-truth fix/atomic-viewport-readiness-20261030 \
  experiment/ready-physical-first-install-20261030 \
  fix/restore-projection-no-false-seen-20261030 fix/durable-position-fence-20261030 \
  chore/browser-return-ab-runner-20261030
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git diff --check origin/fix/restore-projection-no-false-seen-20261030..origin/fix/durable-position-fence-20261030
# Heads divergem na ancestralidade; comparar conteúdo real, não inferir perda do fixture:
git diff origin/fix/restore-projection-no-false-seen-20261030 origin/fix/durable-position-fence-20261030 -- Tests/FeedMineRuntimeTests/RenderReadyAdmissionContractTests.swift
git worktree add --detach /tmp/feedmine-monitor-046 origin/fix/durable-position-fence-20261030
cd /tmp/feedmine-monitor-046
swift package describe
xcodebuild -list -json
swift test --filter RenderReadyAdmissionContractTests
swift test --filter SessionStoreTests
swift test --filter RuntimeMigrationRebuildTests
swift test --filter FeedNativeReadyWindowHandshakeTests
swift test
xcrun simctl list devices available
# Confirmar scheme e UDID reais; gravar .xcresult no SHA exato:
xcodebuild test -scheme FeedMine-Package -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine046.xcresult CODE_SIGNING_ALLOWED=NO
# App real requer catálogo de produto válido (catalog.sqlite + manifesto), não fixture do benchmark.
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=<UDID>' CODE_SIGNING_ALLOWED=NO build
# Testar no app integrado: hero ausente entre dois textos, âncora deferred, 750→1→750,
# prepend sobreposto, gesto ativo, rollback de offset, Safari A/B, A→B sob falha,
# offline relaunch, salvos/coleções/fontes, publicação simultânea.
# Runner Safari #19, após provisionar par de catálogo real:
# scripts/run-browser-return-ab.sh /path/catalog.sqlite /path/catalog.manifest.json <UDID> /tmp/safari-ab-046
# Em árvore INTEGRADA, com avaliador externo congelado e logs:
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
```

**Aceitação:** imagem sem pixels jamais entra normal/held; trechos prontos separados continuam navegáveis sem salto/blank artificial; visual exposure só após viewport real; checkpoint preservado e protegido sem falso seen; rollback físico reproduz mesmo UUID/offset; filtros, Safari, offline e dados pessoais persistem; B03 passa na régua congelada. Se faltar prova: NOT_RUN; se falhar: FAIL, com logs.

## 5. Memória compacta para a próxima execução / OMP

- **Últimos monitores:** 042 `d4c3c5c1` → 043 `53d43097` → 044 `d069a366` → 045 `8c1e9e24` → **046 (este documento)**.
- **SHAs verificados:** main `fb8e65ff`; #6 `c0392741`; #8 `83f05671`; #9 `3e863a1c`; #10 `f4f041c0`; #13 `cf2ce6a8`; #16 `72d067bf`; #17 `93e6cbbe`; **#19 `7b3018d3`, #20 `e02879b1`, #21 `267e121f`, #22 `3bc00208`, #23 `c7f54745`, #24 `91dc980f`, #25 `67e8d4cf`, #26 `29153ea2`**.
- **Resolvido parcialmente:** ready-only alcança primeira janela física na #20; primeira publicação, restore e cursor deixam de simular exposição na stack #23–#26; fence monotônico novo protege histórico salvo. **Não resolvido:** reentrada entre runs, âncora sem pixels, handoff físico/rollback, R4 integral, B03, B06, redirects, Safari, integração F13, offline e persistência end-to-end.
- **Evidência Apple:** #23 run `41167819796` FAIL; #24 `41168369874` PASS; #25 SHA `c45f7967` run `41169117939` FAIL (fixture de `hiddenTail`); #25 HEAD `67e8d4cf` e #26 HEAD `29153ea2` **SEM PASS observado**.
- **Ação imediata para o owner:** fechar navegação física ready-only com witness/rollback e provar no iOS; validar stack #26 em Apple; integrar com F13 sem regressões; executar Safari A/B e B03 na árvore única. Não investir em novos mecanismos paralelos sem primeiro entregar a jornada.
- **Handoff explícito:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. O monitor é consultivo e não alterou main, código, testes, benchmarks, scripts, coordenação, issues ou PRs.
