# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 051 · Vancouver, 02/11/2026, 10:48 PST (UTC−08).** Parecer consultivo, **não certificação de release**. O OMP deve fazer `git fetch origin monitor/architecture` e ler este documento; o monitor não notifica automaticamente executores.

## 1. Base, memória e intervalo

**Memória persistente lida primeiro:** [revisão 050](https://github.com/wsmontes/feedmine_v2/blob/992721f954d86e1ed8270e630a3b275ebb71f954/docs/reviews/ARCHITECTURE_MONITOR.md), `monitor/architecture@992721f954d86e1ed8270e630a3b275ebb71f954`, blob `11de388864a1757fd1a028b2912ece782570cfb0`. **Intervalo incremental:** após a revisão 050, 01/11/2026 ~18:45 PST, até este registro em 02/11/2026. Foram inspecionados commits, diffs, documentação e GitHub Actions surgidos nesse intervalo, além dos bloqueios carregados.

**`main`:** `2eca5b4f925141e5fdd3653e523c3663972d4310`. [Compare 050...main](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...main): `identical`, **zero commits/arquivos**, inclusive docs. `integration/main-consolidated-20261030` também idêntica à main. Os **oito PRs abertos continuam draft e sem mudança de HEAD**: #29 `d8e7e5ea`, #30 `beffb21d`, #31 `aecd6748`, #33 `393e0bc9`, #34 `9e9ab275`, #35 `4f7040ef`, #36 `7afa2571` (sobre #35), #37 `b671147c` (sobre #36). Issues #7, #18, #27, #32 abertas. A consulta paginada encontrou **283 refs de branches**; diferenças de contagem em relação a consultas anteriores não provam, sozinhas, criação recente. Branches históricas `integration/candidate`, `release/build-56` etc. não foram promovidas a candidatas atuais.

**Nova linha de trabalho ativa e relevante:** [`kiro/review-fixes-20261102`](https://github.com/wsmontes/feedmine_v2/tree/kiro/review-fixes-20261102) em `b610bf7d661bd53e378e6d6640deff498afbca42`, último commit em **02/11 18:35:53 UTC (10:35 PST)**. [Compare main...kiro](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...b610bf7d661bd53e378e6d6640deff498afbca42): **10 commits à frente, 0 atrás, 13 caminhos afetados** (incluindo dois scripts com mudança só de modo e dois novos relatórios). **Não existe PR aberto para essa branch** na consulta atual; é trabalho não integrado, não candidata de release aprovada. O [handoff próprio da branch](https://github.com/wsmontes/feedmine_v2/blob/b610bf7d/docs/reviews/2026-11-02-kiro-review-handoff.md) declara ambiente Windows sem toolchain Swift.

**Normas atuais conferidas na main:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_NORTH_STAR.md), [decisões PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz executora](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/PRODUCT_INVARIANTS.md), [arquitetura](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/ARCHITECTURE.md), [dependências](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/DEPENDENCY_RULES.md), [B01–B06](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [regra render-ready](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/2026-10-17-render-ready-admission-rule.md) e [README/handoff](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/README.md). Como a main é idêntica, não há mudança normativa. Não usar blueprints históricos para reduzir a promessa de feed contínuo, runway relativa, pixels locais prontos, scroll independente da rede, filtros reutilizáveis, reabertura offline e persistência pessoal.

## 2. Resumo executivo: avanço real, mas CI vermelho

**Mudança relevante:** a nova branch Kiro contém correções pequenas e localizadas em residência de imagens, salto pendente após falha de reconstrução, proteção contra migração de banco de versão futura, assinatura de release, Swift 6/fixture e um workflow de CI. Contém ainda uma [revisão estática de usabilidade](https://github.com/wsmontes/feedmine_v2/blob/b610bf7d/docs/reviews/2026-11-02-kiro-usability-review.md) com defeitos de jornada que merecem triagem, **não observação em simulador**.

**Nova evidência Apple, discriminante:** [Actions #41497618804](https://github.com/wsmontes/feedmine_v2/actions/runs/41497618804), executado em **`146915e5d7b68d2386590687dfcd102a51bd0a6f`**, terminou **FAIL** em 02/11 18:17:39 UTC. Xcode 16.4 / Swift 6.1.2 / iPhone SE 3ª geração iOS Simulator 26.2, macOS 15.8.2. `FeedMine-Package`: **1.886 PASS, 2 FAIL, 4 skipped**. As duas falhas são:
- [`CanonicalSupplySchemaTests.swift:193`](https://github.com/wsmontes/feedmine_v2/blob/146915e5/Tests/FeedMinePersistenceTests/CanonicalSupplySchemaTests.swift#L186-L194): `PRAGMA index_xinfo('selection_supply_order')` devolveu lista de chaves vazia onde o teste esperava `sort_date:1` e `origin_record_id:1`.
- [`PublicationStoreTests.swift:360–365`](https://github.com/wsmontes/feedmine_v2/blob/146915e5/Tests/FeedMinePersistenceTests/PublicationStoreTests.swift#L349-L367): índice composto esperado não foi encontrado; `EXPLAIN QUERY PLAN` indicou `sqlite_autoindex_feed_segments_2 (edition_id=?)`.

**Comparação importante:** [Actions #41225997714](https://github.com/wsmontes/feedmine_v2/actions/runs/41225997714), em branch combinada anterior, tinha **1.887 PASS, 0 FAIL, 4 skipped no mesmo Xcode 16.4 e simulador iOS 26.2**. Portanto, não é suficiente atribuir os dois REDs a “ambiente iOS diferente”. A origem ainda não foi isolada; a mudança de ordem do migrator é **hipótese de investigação**, não causa provada. No run novo, o teste `ScrollAdmissionTests.testRefusedObservationStillCommitsTheResidencyItDecided` **PASS** (log do job `125456570720`). Os blobs de `FeedSession.swift`, `RuntimeDatabase.swift` e do teste de residência são **idênticos** entre `146915e5` e o HEAD Kiro `b610bf7d`. Isso sustenta o avanço **daquele teste**, não a aprovação do pacote.

O segundo job, **contratos de scripts de release**, falhou no mesmo run: `test-export-signing-flags.sh` saiu com código 8 porque a fixture não carimbava `FeedmineGitBranch` (valor `absent`), abortando antes do export. O commit posterior [`0c50dfd`](https://github.com/wsmontes/feedmine_v2/commit/0c50dfd3cbd3480a12509f521ed8b53a13abd8e0) ajustou o stub e acrescentou uma prova estática; o handoff relata 13/13 casos em Git Bash com shims, **não no macOS nativo**. O workflow final agora só dispara em `main` ou PR destinado à `main`, de modo que **não há novo run do HEAD `b610bf7d`**. Não tratar a correção posterior como CI verde.

**Parecer: RELEASE NÃO APROVADA.** Os P0 comportamentais da revisão 050 continuam; a nova linha Kiro é promissora, mas não resolve a troca física de células nem prova B03, B04/B05, catálogo PD-10, Safari, offline ou B06 na candidata. O pacote Apple tem duas falhas novas de aceitação e a branch ainda não tem PR.

## 3. Mudanças verificadas e consequência de produto

### Correções Kiro (fatos de diff, não aprovação integrada)

1. **Residência e prova visual:** [`87c8117`](https://github.com/wsmontes/feedmine_v2/commit/87c8117c70a0601aec32aff36d0272216b6ca45c), [`FeedSession.swift:218–263`](https://github.com/wsmontes/feedmine_v2/blob/b610bf7d/Sources/FeedMineRuntime/FeedSession.swift#L218-L263), agora executa `boundedResidency` e instala sua projeção mesmo quando a âncora observada não está render-ready, preservando âncora anterior e evitando `markSeen`. **Fato:** teste novo PASS no run `146915e5`; **risco a verificar:** em retorno offline e observações recusadas, nenhuma mudança indevida de posição/exposição, e o livro de pixels não diverge da janela publicada. Não equivale a handoff físico.
2. **Salto após imagem indisponível:** [`e3871fd`](https://github.com/wsmontes/feedmine_v2/commit/e3871fd274992ed7ef72c26020199f5a428dc7bd), [`FeedNativeViewport.swift:213–225`](https://github.com/wsmontes/feedmine_v2/blob/b610bf7d/Sources/FeedMineUI/FeedNativeViewport.swift#L213-L225), restaura `onChange(of: unavailableImageCardIDs)` para reavaliar salto pendente. **Fato de código; hipótese de benefício:** evita espera infinita quando a reconstrução local falha sem mudar a janela. Exige jornada real de falha/retorno.
3. **Banco de dados de build futuro:** [`028a2ba`](https://github.com/wsmontes/feedmine_v2/commit/028a2ba6aaf3c2f63231b287d44163fb1bb15682), [`RuntimeDatabase.swift:171–194`](https://github.com/wsmontes/feedmine_v2/blob/b610bf7d/Sources/FeedMinePersistence/RuntimeDatabase.swift#L171-L194), move o veto de migrações desconhecidas para **antes** de `migrate(pool)`. **Fato:** melhora a ordem de proteção pretendida. **Não comprovado:** ausência de escrita em todos os cenários de downgrade; investigar também os dois REDs de índice com ensaio diferencial.
4. **Release/CI:** [`2b9fae4`](https://github.com/wsmontes/feedmine_v2/commit/2b9fae4aed21c1f7030e439aa89be9d3b37ddd70) faz archive e export usar uma única definição de flags de assinatura ([`release-testflight.sh:173–225`](https://github.com/wsmontes/feedmine_v2/blob/b610bf7d/scripts/release-testflight.sh#L173-L225)); [`0c50dfd`](https://github.com/wsmontes/feedmine_v2/commit/0c50dfd3cbd3480a12509f521ed8b53a13abd8e0) repara a fixture e restringe triggers; [`feedmine-main-package.yml`](https://github.com/wsmontes/feedmine_v2/blob/b610bf7d/.github/workflows/feedmine-main-package.yml) propõe gate de pacote e scripts. **Fato:** um run intermediário vermelho; **não há run do HEAD atual**. Nenhum desses scripts certifica catálogo ou build de distribuição.
5. **Swift 6/fixture:** Kiro incorpora patches equivalentes aos PRs #30/#34, sem que isso altere o estado draft dos PRs. Não confundir cópias cherry-picked com merge dos PRs ou com aprovação da main.

### Nova documentação de usabilidade: usar como inventário de hipóteses priorizadas

A [revisão Kiro](https://github.com/wsmontes/feedmine_v2/blob/b610bf7d/docs/reviews/2026-11-02-kiro-usability-review.md) é explicitamente **inspeção de código, sem simulador**. Dois achados têm suporte estático independente nesta revisão: [`FeedMineApp.swift:561–562`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/FeedMineApp/FeedMineApp/FeedMineApp.swift#L561-L562) mostra só `Text(failure)` se falhar a inicialização (**D1**, sem ação de recuperação nessa tela); [`FeedMineApp.swift:778–796`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/FeedMineApp/FeedMineApp/FeedMineApp.swift#L778-L796) usa o mesmo `deleteCurrentPreset` para dois tipos e `try?` em ações (**B1/B5**, potencial falha silenciosa). Os efeitos completos, frequência e gravidade em dispositivo **não foram medidos**. O documento também lista F1 (fim físico congelado), F2 (âncora não pronta), M1 (refresh ausente) e M2 (remoção de salvos) — não transformar sua marca “V” em teste de UX.

## 4. Achados por severidade, evidência, risco e ação mínima

### P0-01 — Handoff físico não prefixado e feed que aparenta acabar (ABERTO; não resolvido por Kiro)

**Fato:** [`FeedScreenStore.swift:304–329` na main](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreenStore.swift#L304-L329) só substitui a janela física se `nextIDs.starts(with: previousIDs)`; caso contrário mantém `[A,B,C]` mesmo com projeção `[B,C,D]`. [RED macOS #41226687119](https://github.com/wsmontes/feedmine_v2/actions/runs/41226687119) e [host real #41375292900](https://github.com/wsmontes/feedmine_v2/actions/runs/41375292900) continuam as provas discriminantes. #35 faz staging, #36 prova callbacks reduzidos, #37 diagnostica **9 provas geométricas antes do binding e 0 depois**, B dentro da viewport. **Nenhum commit Kiro altera o swap físico.** A revisão de usabilidade nova reforça o risco, mas não acrescenta medição real de uso.

**Risco (inferência):** runway sem células novas, fim silencioso e retenção de imagens velhas, violando o feed contínuo e a apresentação local. **Owner:** obter prova geométrica fresca pós-binding da mesma UIScrollView; implementar begin/publicação provisória de IDs/medição pós-layout/commit ou rollback pelo **único writer nativo**, sem timer, fila, cache ou dono paralelo. Gesto cancela; medir ID comum, offset e estabilidade no host real. Só considerar resolvido com GREEN físico no SHA e B03/B04/B05.

### P0-02 — B03/runway e experiência integrada (ABERTO)

**Fato:** [B03](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) tem PASS histórico em `4baf9045` (20/out, 3.157 avanços/30 min), **não** no `main@2eca5b4f`, Kiro ou pilha #35–#37. B04/B05 também não têm prova atual de janela física, A→B→A e retorno offline. **Ação:** após o handoff, rodar 30 minutos de consumo real com corpus/driver/oráculo congelados, medir pausas, pixels, IDs físicos, offset e ausência de trabalho de rede na apresentação; repetir B04/B05 na mesma candidata. Não aceitar apenas XCTest de staging.

### P0-03 — Redirect público→privado validado depois da conexão (ABERTO)

**Fato estático:** [`FeedDiscoveryTransport.swift:75–91`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L91) chama `session.bytes(for:)` antes de validar host do URL final. **Hipótese de segurança:** redirect pode alcançar host privado antes do veto; não há exploração demonstrada. **Ação:** delegate de redirecionamento com veto **antes** de seguir; teste público→privado que prove zero conexão privada.

### P1-01 — CI novo falhou em dois contratos SQLite (NOVO, ABERTO)

**Fato:** [run #41497618804](https://github.com/wsmontes/feedmine_v2/actions/runs/41497618804) falhou em `CanonicalSupplySchemaTests:193` e `PublicationStoreTests:360,365`. O teste novo de residência PASS, mas o pacote total está RED. **Hipótese:** diferença de ordem de migração/inspeção de schema introduzida por `028a2ba` pode influenciar a observação dos índices; **não comprovado**, não editar asserts ou índices por palpite. **Ação mínima:** no mesmo Xcode/simulador, comparar `main@2eca5b4f`, parent de `028a2ba`, `146915e5` e `b610bf7d`; registrar `PRAGMA index_list`, `index_xinfo`, `sqlite_master` e `EXPLAIN QUERY PLAN`. Só então decidir correção de schema, conexão ou teste. Risco: aceitar banco com índices ausentes ou descartar falha real como cosmética.

### P1-02 — Retorno offline, residência e salto após mídia perdida (PARCIAL; prova de componente)

**Fato:** patch Kiro de `FeedSession` e teste discriminante PASS em `146915e5`, sem mudança de blob até `b610bf7d`; observer de `unavailableImageCardIDs` restaurado. **Ainda falta:** teste no host/app para salto que não fica esperando, âncora que não se move, nenhuma exposição sintética, volta offline, imagens reconstruídas, salvos/coleções/fontes duráveis. **Risco:** corrigir o livro de residência sem corrigir a janela física ou provocar atualização visual indevida. Ação: teste de jornada com mídia removida e reabertura, depois suíte app e B05.

### P1-03 — Falha de inicialização sem recuperação e ações de preset silenciosas (NOVO; estático)

**Fato:** [`FeedMineApp.swift:561–562`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/FeedMineApp/FeedMineApp/FeedMineApp.swift#L561-L562) renderiza somente erro textual; [`:778–796`](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/FeedMineApp/FeedMineApp/FeedMineApp.swift#L778-L796) usa `try?` e a mesma ação de exclusão para dois contextos. **Hipótese de impacto:** leitor sem caminho de recuperação ou feedback; validar cenários antes de expandir escopo. **Owner:** depois dos P0, teste de falha de bootstrap e de presets por tipo; adicionar ação de recuperação e mensagem explícita no dono existente, sem nova máquina de estados.

### P1-04 — Catálogo, Safari, filtros, persistência e 17 falhas históricas do app (ABERTO)

**Fatos anteriores:** [relatório de consolidação](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md) documenta 17 falhas no alvo do app; [issue #18](https://github.com/wsmontes/feedmine_v2/issues/18) Safari e [#7](https://github.com/wsmontes/feedmine_v2/issues/7) render-ready seguem abertas. CI de pacote **não** cobre app de distribuição, catálogo íntegro PD-10, importação V1, filtros A→B→A ou persistência de salvos/coleções/fontes. Nenhuma aceitação nova comprovada. **Owner:** integração pequena e controlada, catálogo manifesto+SQLite validado, testes app e jornada offline com identidade/posição preservadas.

### P2 — Scripts de release, observabilidade e hardware (PARCIAL)

O teste de assinatura foi corrigido **depois** do run vermelho, sem rerun no HEAD. O CI proposto dispara em main/PR main, não faz gate de app/catálogo/iPhone. **B06 físico continua NOT_RUN/INCOMPLETE, nunca PASS.** O relatório Kiro de usabilidade é valioso para triagem, mas não deve competir com o handoff físico. Não há nova prova de iPhone físico ou benchmark nesta revisão.

## 5. Comandos e provas para o Mac — NÃO EXECUTADOS POR ESTE MONITOR

~~~bash
git fetch origin main monitor/architecture kiro/review-fixes-20261102 \
  fix/native-ready-handoff-staging-20261031 \
  test/native-stage-host-callback-20261101 test/feed-screen-native-proof-20261102
git rev-parse origin/main origin/kiro/review-fixes-20261102
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git diff --check origin/main...origin/kiro/review-fixes-20261102
git diff --stat origin/main...origin/kiro/review-fixes-20261102
xcrun simctl list devices available

# Reproduzir a árvore Kiro exata, não a main nem o SHA intermediário do CI:
git worktree add --detach /tmp/fm-monitor-051-kiro b610bf7d661bd53e378e6d6640deff498afbca42
cd /tmp/fm-monitor-051-kiro
bash scripts/test-export-signing-flags.sh
python3 -m unittest discover -s Tests/ReleaseScripts -p 'test_*.py' -v

# Isolar os dois REDs SQLite e confirmar a prova de residência:
xcodebuild test -scheme FeedMine-Package \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO \
  -only-testing:FeedMinePersistenceTests/CanonicalSupplySchemaTests/testMembershipAndSortBasisConstraintsAndOrderingIndex \
  -only-testing:FeedMinePersistenceTests/PublicationStoreTests/testTailQueryUsesExistingEditionOrdinalIndexWithoutTemporaryOrder \
  -only-testing:FeedMineRuntimeTests/ScrollAdmissionTests/testRefusedObservationStillCommitsTheResidencyItDecided \
  -resultBundlePath /tmp/FeedMine051Focused.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/FeedMine051Focused.xcresult

# Se os índices falharem, comparar o mesmo teste no 2eca5b4, antes/depois de 028a2ba,
# com PRAGMA index_list/index_xinfo/sqlite_master e EXPLAIN QUERY PLAN brutos.
# Depois, no HEAD de integração escolhido, executar suíte completa de pacote e app:
xcodebuild test -scheme FeedMine-Package \
  -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO \
  -resultBundlePath /tmp/FeedMine051Package.xcresult CODE_SIGNING_ALLOWED=NO
scripts/verify_product_catalogue.sh "$(xcrun simctl get_app_container booted com.feedmine.development app)"
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO \
  -resultBundlePath /tmp/FeedMine051App.xcresult CODE_SIGNING_ALLOWED=NO
scripts/run-browser-return-ab.sh --help
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
# Repetir B04/B05, catálogo PD-10 e B06 no iPhone físico prescrito.
~~~

**Critério de release:** feed contínuo e runway adaptativa sem esgotamento artificial; mídia local pronta antes de entrar na apresentação; identidade/offset/scroll estáveis sob trim, filtros, gesto, Safari e offline; estado pessoal durável; um dono por responsabilidade; redirect privado vetado antes da conexão; B01–B06 e PD-10 na mesma candidata. `NOT_RUN` ou CI de componente não é `PASS` de produto.

## 6. Memória compacta / handoff para próxima revisão

- **Anterior:** revisão 050, `monitor@992721f9`, blob `11de3888`. Histórico 047 `b8b942e2` → 048 `4fa767d7` → 049 `f563ca6d` → 050 `992721f9` → **051 (esta)**.
- **Main/integração:** `2eca5b4f` inalterada; PRs #29–#31/#33–#37 draft e HEADs anteriores; issues #7/#18/#27/#32 abertas.
- **Nova branch ativa:** `kiro/review-fixes-20261102@b610bf7d`, 10 commits desde main; docs de handoff/usabilidade e patches em FeedSession, FeedNativeViewport, RuntimeDatabase, assinatura e CI; **sem PR, sem merge**.
- **Nova prova Apple:** run `41497618804` em `146915e5`, **1886 PASS/2 FAIL/4 skipped**, REDs SQLite em `CanonicalSupplySchemaTests:193` e `PublicationStoreTests:360,365`. Novo teste de residência PASS. Job de scripts FAIL por stub antigo; `0c50dfd` posterior corrige stub, **sem rerun do HEAD**. Mesmo Xcode/simulador do run verde `41225997714`.
- **P0 não resolvidos:** swap físico [A,B,C]→[B,C,D], B03/B04/B05 no integrado, redirect pré-conexão. **P1:** dois REDs SQLite, app/PD-10/Safari/offline, UX de bootstrap/presets. **B06 NOT_RUN**. A evidência #37 de 9 provas pré-binding/0 pós-binding permanece.
- **Resolvido/avançado com limite:** código Kiro corrige dois caminhos de residência/salto e ordem de veto de migração; teste de residência PASS em SHA intermediário. **Não comprovado:** regressão zero no app, suite verde do HEAD, swap físico, release.
- **Próximo owner:** (1) isolar REDs de SQLite no Mac e validar patches Kiro no HEAD; (2) concluir handoff físico com único writer e teste real; (3) executar B03/B04/B05, app/PD-10/offline/Safari, B06 físico. Não criar caches, filas, timers, retries ou ownership paralelos.
- **Handoff obrigatório:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. O monitor não altera main, código, testes, benchmarks, scripts, coordenação, issues ou PRs.
