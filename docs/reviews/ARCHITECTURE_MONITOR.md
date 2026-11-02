# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 052 · Vancouver, 02/11/2026, 12:46 PST (UTC−08).** Parecer consultivo: **RELEASE NÃO APROVADA**. O OMP deve fazer fetch da branch de monitor e ler este arquivo; não há notificação automática aos executores.

## 1. Base verificada, intervalo e autoridade

**Memória persistente lida antes da inspeção:** [revisão 051](https://github.com/wsmontes/feedmine_v2/blob/525b1be25246f35d860ae4b92529582791f44f72/docs/reviews/ARCHITECTURE_MONITOR.md), branch monitor/architecture no commit **525b1be25246f35d860ae4b92529582791f44f72**, blob anterior **73d717e5d393707b7f20b4bc044009f02b4c3a68**. **Intervalo incremental:** 02/11/2026 10:48–12:46 PST, sobre os SHAs e pendências registrados na 051.

- **main:** **2eca5b4f925141e5fdd3653e523c3663972d4310**, [comparação com main](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...main) **identical**: 0 commits e 0 arquivos alterados, inclusive docs. **integration/main-consolidated-20261030** também permanece nesse SHA.
- **Trabalho ativo novo:** [kiro/review-fixes-20261102](https://github.com/wsmontes/feedmine_v2/tree/kiro/review-fixes-20261102) avançou de **b610bf7d661bd53e378e6d6640deff498afbca42** para **9498d165f146ee3c3a40118ff5ddc2c7e45b28b9**. [Diff incremental](https://github.com/wsmontes/feedmine_v2/compare/b610bf7d661bd53e378e6d6640deff498afbca42...9498d165f146ee3c3a40118ff5ddc2c7e45b28b9): **21 commits, 29 arquivos**, incluindo documentação. [Diff acumulado main...Kiro](https://github.com/wsmontes/feedmine_v2/compare/2eca5b4f925141e5fdd3653e523c3663972d4310...9498d165f146ee3c3a40118ff5ddc2c7e45b28b9): **31 commits à frente, 0 atrás, 41 arquivos**. Último commit às **19:17:01 UTC (11:17 PST)**. Sem PR aberto da Kiro, sem integração e sem release candidata certificada.
- **PRs abertos:** oito drafts sem novos HEADs: #29 d8e7e5ea, #30 beffb21d, #31 aecd6748, #33 393e0bc9, #34 9e9ab275, #35 4f7040ef, #36 7afa2571, #37 b671147c. Issues abertas: #7, #18, #27, #32. Branches históricas não são candidatas atuais.
- **CI:** 36 workflow runs registrados; o mais recente ainda é [#41497618804](https://github.com/wsmontes/feedmine_v2/actions/runs/41497618804), **FAIL**, SHA **146915e5d7b68d2386590687dfcd102a51bd0a6f**, 1.886 testes de pacote PASS / **2 FAIL** / 4 skipped e job de scripts FAIL. **Nenhum run novo do HEAD 9498d165**. Não executar XCTest, simulador, iPhone ou bench neste monitor.

**Documentos normativos lidos novamente na main, sem alteração de SHA da main:** [PRODUCT_NORTH_STAR](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_NORTH_STAR.md), [PRODUCT_DECISIONS PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [V2_AGENT_EXECUTION_DIRECTIVE](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [PRODUCT_INVARIANTS INV-01–INV-18](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/PRODUCT_INVARIANTS.md), [ARCHITECTURE](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/architecture/ARCHITECTURE.md), [B01–B06](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [regra render-ready](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/2026-10-17-render-ready-admission-rule.md). Prevalecem as decisões atuais, não blueprints históricos: feed contínuo, runway adaptativa, pixels locais prontos antes da apresentação, scroll independente da rede, troca de filtros sem perda de trabalho, reabertura offline e persistência pessoal. Sem caches/filas/timers/retries/ownership paralelos para mascarar problemas.

## 2. Resumo executivo — melhora de UX sem prova de integração

**Mudança relevante e verificável:** Kiro acrescentou uma rodada de **21 commits de UX e recuperação**, incluindo ação para falha de bootstrap, retry no fim da lista com cards, remoção de salvos, erros visíveis em fontes/coleções/presets, busca de fontes, confirmação de exclusão de caixas, filtro obsoleto, compartilhamento no leitor, controle de mídia, strings localizadas e [handoff atualizado](https://github.com/wsmontes/feedmine_v2/blob/9498d165/docs/reviews/2026-11-02-kiro-review-handoff.md). O próprio handoff declara **não compilado** no ambiente usado. Os únicos arquivos de teste alterados neste intervalo têm mudanças pontuais de expectativa/string; não há execução Apple nem prova black-box desta rodada.

**Consequência de produto (opinião fundamentada):** os novos controles tornam bloqueios e falhas mais recuperáveis, sobretudo em biblioteca e descoberta. Mas **um botão “Tentar novamente” no fim do feed não produz runway** e não corrige a retenção física da janela antiga. Os defeitos P0 de continuidade/scroll e de segurança continuam, e a nova UX amplia a superfície que precisa ser testada sem estabilizar o release.

**Limite da evidência:** diff e leitura estática comprovam o código e as strings; não comprovam compilação, acionamento real dos botões, persistência correta, ausência de regressão visual, fluidez, iPhone ou benchmark. Não interpretar o CI intermediário da revisão 051 como PASS do HEAD atual.

## 3. Mudanças verificadas e efeito provável

1. **Bootstrap, navegação e falhas antes silenciosas — avanço estático.** [727db59](https://github.com/wsmontes/feedmine_v2/commit/727db592d933d4f12d5ca8057f28771c3e0a1ee9) introduz [AppComposition.retryStartup, linhas 752–767](https://github.com/wsmontes/feedmine_v2/blob/9498d165/FeedMineApp/FeedMineApp/AppComposition.swift#L752-L767) e [StartupFailureView no host](https://github.com/wsmontes/feedmine_v2/blob/9498d165/FeedMineApp/FeedMineApp/FeedMineApp.swift#L584-L593). [02c79a4](https://github.com/wsmontes/feedmine_v2/commit/02c79a4869ea9b53fb2b918506751ede11e387ea) restringe ações destrutivas ao preset corrente. [69adf7a](https://github.com/wsmontes/feedmine_v2/commit/69adf7a85f623dc5fd40647ee984f39f520eab7f) torna falhas de biblioteca visíveis; [f078425](https://github.com/wsmontes/feedmine_v2/commit/f078425e80d4535e591fce5bcb7c90eee4f3da6b) reverte especificamente a alteração de fileMover, preservando a folha de compartilhamento testada. **Não há validação de jornada pós-mudança.**
2. **Fim de lista e recuperação — avanço de UX, não de runway.** [634d5f2](https://github.com/wsmontes/feedmine_v2/commit/634d5f2d32ac882711dc280665e937cee15778ad) adiciona [FeedScreen.tailRecoveryBlock:390–428](https://github.com/wsmontes/feedmine_v2/blob/9498d165/Sources/FeedMineUI/FeedScreen.swift#L390-L428) para .unreachable/.failed/.deferred/.unavailable, apenas depois do último card físico quando ele coincide com o último da janela lógica. O host conecta retry a [refreshFromTheReader](https://github.com/wsmontes/feedmine_v2/blob/9498d165/FeedMineApp/FeedMineApp/FeedMineApp.swift#L500-L515). **Risco a medir:** aparecimento/desaparecimento do bloco altera altura de conteúdo no fim, e não pode mover a âncora ou ser confundido com fim definitivo. [7f2195c](https://github.com/wsmontes/feedmine_v2/commit/7f2195c4c67a0133631fcfcfa170c71f555891c0) evita ações sem callback na recuperação pausada.
3. **Salvos/coleções/filtros/fontes — avanços de controle com risco de escrita.** [66bd469](https://github.com/wsmontes/feedmine_v2/commit/66bd469f616f2e6b9420e0ea8030a7706ca1ec2e) cria swipe/menu para remover salvos e retry da leitura; [a1372a7](https://github.com/wsmontes/feedmine_v2/commit/a1372a7aecec02d866ec368a767099184d5dc59a) ajusta observação de reload e gesto de exclusão de caixa; [4267a35](https://github.com/wsmontes/feedmine_v2/commit/4267a3582b280695c974214043cfa8846c1df45b) trata draft obsoleto; [7ca8549](https://github.com/wsmontes/feedmine_v2/commit/7ca8549768db6cb6154aab6786a70570595e7c8f) expõe busca no catálogo, usando o store já existente ([SourceManagementView:54–117](https://github.com/wsmontes/feedmine_v2/blob/9498d165/Sources/FeedMineUI/Sources/SourceManagementView.swift#L54-L117)). Não há evidência de perda de trabalho por troca de filtros, nem prova de que isso não ocorre.
4. **Outras melhorias de superfície:** [0684c03](https://github.com/wsmontes/feedmine_v2/commit/0684c0384fff34987cb86311b1ab87592eb25b06) fecha mini player; [755c0e0](https://github.com/wsmontes/feedmine_v2/commit/755c0e0af69b422f00da676d091c3af83162d93b) compartilha do leitor local; [9578627](https://github.com/wsmontes/feedmine_v2/commit/9578627018bed99284ffc7d34b8f07db542ffdea) localiza humor/tipo sem trocar raw values persistidos; [aac762a](https://github.com/wsmontes/feedmine_v2/commit/aac762ae6ec534239a5652b44dc85d0a9dd6c075) atualiza traduções. **Fato:** alteração de código/strings; **hipótese:** melhor compreensão/acessibilidade, ainda não medida.
5. **Documentação nova/alterada:** o [handoff Kiro](https://github.com/wsmontes/feedmine_v2/blob/9498d165/docs/reviews/2026-11-02-kiro-review-handoff.md) registra escopo, ressalvas e cenários a validar; não muda as normas da main nem substitui um run Apple.

## 4. Achados P0/P1/P2 e decisão de release

### P0-01 — Troca física não prefixada ainda retém a janela velha (ABERTO, comprovado estaticamente)

[FeedScreenStore.swift:304–329 na main](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineUI/FeedScreenStore.swift#L304-L329) só publica a nova janela física se nextIDs começa pelos previousIDs; [A,B,C]→[B,C,D] não conclui. O arquivo não foi alterado pela nova rodada (apenas toggleSearch). [RED macOS #41226687119](https://github.com/wsmontes/feedmine_v2/actions/runs/41226687119) e [RED do host real #41375292900](https://github.com/wsmontes/feedmine_v2/actions/runs/41375292900) permanecem; no segundo, nove provas geométricas pré-binding e zero pós-binding. **Risco inferido:** feed aparenta esgotar e scroll/posição se descolam da runway lógica. **Owner:** priorizar prova legítima pós-binding, swap físico pelo writer nativo existente, commit/rollback com gesto, identidade, offset e pixels. **Não declarar resolvido por tail retry.**

### P0-02 — B03 e experiência integrada não aceitas (ABERTO)

[B03/B04/B05](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) não foram executados na main atual, na Kiro ou na pilha #35–#37. PASS histórico B03 em outro SHA não é PASS aqui. **Owner:** após resolver handoff, executar B03 integral (30 min, driver/corpus/oráculo congelados), B04 troca A→B→A, B05 offline/retorno; medir ID, posição, pausas, pixels e preparação independente da rede. **Risco:** otimizar UI sem provar a promessa de continuidade.

### P0-03 — Redirect público→privado após conexão (ABERTO, risco de segurança hipotético)

[FeedDiscoveryTransport.swift:75–91](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L91) valida destino final depois de session.bytes(for:). **Fato de ordem de chamadas**, não exploração comprovada. **Owner:** veto de redirecionamento antes de seguir para host privado, teste com zero conexões ao destino bloqueado.

### P1-01 — CI SQLite vermelho continua sem isolamento (ABERTO, comprovado por CI)

[Run #41497618804](https://github.com/wsmontes/feedmine_v2/actions/runs/41497618804) em 146915e5: [CanonicalSupplySchemaTests:193](https://github.com/wsmontes/feedmine_v2/blob/146915e5/Tests/FeedMinePersistenceTests/CanonicalSupplySchemaTests.swift#L186-L194) e [PublicationStoreTests:360–365](https://github.com/wsmontes/feedmine_v2/blob/146915e5/Tests/FeedMinePersistenceTests/PublicationStoreTests.swift#L349-L367) falharam na verificação de índices/EXPLAIN. Run [#41225997714](https://github.com/wsmontes/feedmine_v2/actions/runs/41225997714) anterior passou no mesmo Xcode/simulador; causa **não isolada**. A hipótese de migração/ordem do schema continua hipótese. **Owner:** reproduzir comparativamente no Mac; não apagar asserts nem alegar CI verde.

### P1-02 — Remover de “Todos os salvos” executa várias escritas sem transação visível (NOVO; risco de persistência)

**Fato de código:** [AppComposition.swift:3138–3155](https://github.com/wsmontes/feedmine_v2/blob/9498d165/FeedMineApp/FeedMineApp/AppComposition.swift#L3138-L3155) obtém os IDs das caixas e executa um setBookmarkMembership por caixa em loop; não há transação envolvendo todo o conjunto **neste chamador**. A [swipe action](https://github.com/wsmontes/feedmine_v2/blob/9498d165/Sources/FeedMineUI/FeedSavedListView.swift#L120-L147) usa role destructive. **Hipótese de regressão:** se a segunda escrita falhar após a primeira, o artigo fica parcialmente removido, a UI pode animar a remoção antes da confirmação e o feedback genérico não distingue estado parcial. Não afirmar que o storage não oferece garantias internas sem examiná-lo; cada operação pode ser atômica individualmente. **Owner:** teste com artigo em duas caixas e falha injetada na segunda escrita; se reproduzir parcial, agrupar a operação no owner de persistência existente, sem novo mecanismo paralelo. Testar também o swipe quando o banco recusa escrita.

### P1-03 — Rodada UX ampla não compilada/testada no HEAD (NOVO, comprovado pela ausência de evidência)

**Fato:** 21 commits/29 arquivos; [handoff Kiro](https://github.com/wsmontes/feedmine_v2/blob/9498d165/docs/reviews/2026-11-02-kiro-review-handoff.md) declara ausência de compilação; último Actions é de SHA intermediário anterior. **Risco inferido:** apresentação de alertas, sheet replacement, busca assíncrona, alterações na altura do feed, leitura salva e navegação podem regredir sem falha de testes unitários. **Owner:** compilar HEAD, suíte pacote+app, UI tests de fontes, caixas, salvos, player, filtro obsoleto, bootstrap, tail recovery; comparar com a main. A busca introduz [debounce de 250 ms](https://github.com/wsmontes/feedmine_v2/blob/9498d165/Sources/FeedMineUI/Sources/SourceManagementView.swift#L63-L86): confirmar cancelamento e ausência de busca obsoleta, sem transformá-lo em scheduler de aquisição.

### P1-04 — Safari, catálogo PD-10, filtros e estado offline (ABERTO)

[Issue #18](https://github.com/wsmontes/feedmine_v2/issues/18) Safari, [#7](https://github.com/wsmontes/feedmine_v2/issues/7) prontidão visual e o [relatório de consolidação](https://github.com/wsmontes/feedmine_v2/blob/2eca5b4f/docs/reviews/2026-10-30-consolidacao-de-branches.md) com 17 falhas históricas do app não têm nova aceitação. Não há prova atual de catálogo íntegro, persistência de salvos/coleções/fontes, reabertura offline e filtros sem reconstrução desnecessária. **Owner:** validar tudo na mesma candidata integrada, não em branches isoladas.

### P2 — Scripts de release e dispositivo físico (PARCIAL/NOT_RUN)

O teste de assinatura do run intermediário falhou e o stub foi corrigido posteriormente na revisão 051, sem CI do HEAD atual. A Kiro não comprova archive/export distribuível, catálogo nem B06 em iPhone físico. **B06 NOT_RUN/INCOMPLETE, nunca PASS.** Evitar dar prioridade a ajustes cosméticos antes de resolver P0.

## 5. Comandos e provas no Mac — NÃO EXECUTADOS PELO MONITOR

~~~bash
git fetch origin main monitor/architecture kiro/review-fixes-20261102
git fetch origin fix/native-ready-handoff-staging-20261031 test/native-stage-host-callback-20261101 test/feed-screen-native-proof-20261102
git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md
git rev-parse origin/main origin/kiro/review-fixes-20261102
git diff --check b610bf7d661bd53e378e6d6640deff498afbca42..9498d165f146ee3c3a40118ff5ddc2c7e45b28b9
git diff --stat b610bf7d661bd53e378e6d6640deff498afbca42..9498d165f146ee3c3a40118ff5ddc2c7e45b28b9
xcrun simctl list devices available

git worktree add --detach /tmp/feedmine-monitor-052 9498d165f146ee3c3a40118ff5ddc2c7e45b28b9
cd /tmp/feedmine-monitor-052
bash scripts/test-export-signing-flags.sh
python3 -m unittest discover -s Tests/ReleaseScripts -p 'test_*.py' -v

# Substituir UDID pelo simulador disponível; gravar logs e .xcresult:
xcodebuild test -scheme FeedMine-Package -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine052Package.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/FeedMine052Package.xcresult
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/FeedMine052App.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool get test-results summary --path /tmp/FeedMine052App.xcresult

# Reproduzir os dois REDs SQLite em main, antes/depois de 028a2ba e HEAD Kiro.
# Coletar PRAGMA index_list, PRAGMA index_xinfo, sqlite_master, EXPLAIN QUERY PLAN.
# Injetar falha na segunda exclusão de membership de artigo salvo em duas caixas.
# Exercitar UI: bootstrap retry, filtros stale, busca fontes, caixas, salvos, mini player,
# tail recovery em .failed/.unreachable/.deferred/.unavailable, retorno Safari e offline.
# No SHA de integração após handoff físico: B03 30 min + B04/B05 + catálogo PD-10.
scripts/run-discovery-benchmark.sh --gate B03 --profile A --profile B
# B06 requer iPhone físico e evidência reproduzível; NOT_RUN não é PASS.
~~~

**Critério de aceite:** evidência reproduzível na **mesma candidata** de feed contínuo e runway adaptativa, pixels locais antes da admissão, scroll/identidade/posição estáveis, filtros A→B→A reutilizáveis, Safari, reabertura offline, estado pessoal durável, catálogo íntegro, redirects seguros, B01–B06 e ausência de donos paralelos. Sem alterar benchmarks para obter PASS.

## 6. Memória compacta / handoff

- **Últimos relatórios:** 050 monitor@992721f9 (blob 11de3888) → 051 monitor@525b1be2 (blob 73d717e5) → **052 (este arquivo)**. Histórico anterior 047 b8b942e2 → 048 4fa767d7 → 049 f563ca6d.
- **SHAs de trabalho:** main/integration **2eca5b4f**; Kiro anterior **b610bf7d**, atual **9498d165** (**+21 commits**, total **31 à frente de main**); #35 **4f7040ef**, #36 **7afa2571**, #37 **b671147c**. PRs #29–#31/#33–#37 draft sem mudança; issues #7/#18/#27/#32 abertas.
- **CI mais recente:** run **41497618804** em **146915e5**, pacote **1886 PASS/2 FAIL/4 skipped**, scripts FAIL; nenhum CI do HEAD Kiro 9498d165. Prova antiga de 9 medições pré-binding/0 pós-binding no host #37.
- **P0 pendentes:** handoff físico não prefixado; B03/B04/B05 na candidata; redirect pré-conexão. **P1:** SQLite vermelho, risco de remoção parcial de salvos, 21 commits de UX sem build, Safari/PD-10/offline/filtros. **P2:** release scripts e B06 físico NOT_RUN.
- **Avanços com limite:** Kiro 051 adicionou patches de residência/salto/downgrade/assinatura e um teste de residência PASS no SHA intermediário; Kiro 052 adicionou controles de recuperação e biblioteca. **Nenhum desses avanços foi aceito como release**, nem resolve o swap físico.
- **Próximo owner:** (1) validar/compilar HEAD Kiro e isolar SQLite, com teste de escrita parcial; (2) concluir writer nativo e host real; (3) executar gates black-box e app completo na mesma candidata. **Não criar mecanismos paralelos.**
- **Leitura obrigatória pelo OMP:** git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md. O monitor é consultivo e não envia aviso automático.
