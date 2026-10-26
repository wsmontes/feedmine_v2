# F12/UX12-B — abrir o feed de uma fonte a partir da linha da taxonomia (25/10/2026)

Requisito: `docs/product/F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md` — R1 (tocar a origem leva ao destino
declarado), R4 (habilitar é opcional e é do toggle), UX12-B (o feed de S contém **somente** memberships legítimas
de S) e o “Ouro V1 — abrir uma Source, não só ativar um toggle” (G01/G08/G09). O mapa de produto registrava a
lacuna: “a linha de fonte na taxonomia oferece toggle, sem ação própria de abrir seu feed”.

## O que mudou

| Arquivo | Mudança |
|---|---|
| `Sources/FeedMineUI/Sources/NodeSourcesView.swift` | `NodeSourceRowView` ganha `onOpen` opcional: quando existe destino, o trecho de título vira um `Button` (`node-source-<key>`); sem destino, nenhum controle é desenhado. O `Toggle` (`node-source-toggle-<key>`) permanece irmão, com área própria |
| `FeedMineApp/FeedMineApp/AppComposition.swift` | `openSourceFeed(forKey:)`: adota a seleção pendente (os toggles do sheet são duráveis), casa a **chave do catálogo** com o `TrustedFeed` resolvido pelo próprio owner e seleciona `.source(sourceID)`. Devolve `false` quando a chave não está na seleção — sem derivar identidade e sem cair no feed principal |
| `FeedMineApp/FeedMineApp/FeedMineApp.swift` | **só** o call site da superfície de Fontes passa `onOpenSource` — o sheet de filtros mantém apenas a própria navegação, porque abrir uma fonte ali fecharia o sheet e descartaria o rascunho do leitor, fora do F12. O host **abre primeiro e fecha depois** (o `onDismiss` do sheet adota a seleção e marcaria `replacingSession`, recusando a transição legítima se as duas corressem juntas), preserva `sourcesPath` (reabrir volta ao mesmo nó) e, quando a chave selecionada não é resolvível, declara “Não foi possível abrir o feed desta fonte.” em vez de silêncio |

**Por que a fonte precisa estar na seleção:** `sessionState(for:)` converte `.source(id)` em `.main` quando a
fonte não está entre os feeds ativos. Abrir uma fonte fora da seleção mostraria o feed principal com o rótulo de
outra fonte — exatamente o “destino falso” que R1/S1 proíbem. Habilitar é o ato do toggle (R4); depois disso a
linha ganha o controle de abrir. Essa fronteira está registrada como lacuna de produto (contexto de fonte única
fora da seleção não existe), não como funcionalidade inventada.

## Validação executada

| Verificação | Resultado |
|---|---|
| Pacote: `swift build` | Build complete |
| Pacote: `SourceManagementStoreTests` + `FeedScreenRenderingTests` | 47 testes, 0 falhas |
| Oráculo UX12-B (membership) | já provado em `CandidateProviderTests.testSourceFilteringPreservesExaminedCountAndRelativeOrder`: com itens de a e de b no banco, `candidates(plan(.source(a)))` devolve somente a — nenhuma identidade é filtrada por título ou URL |
| App (simulador, integrado) | `CompositionTests.testF12SourceRowOpensTheSelectedSourceAndRefusesAKeyOutsideTheSelection` — **PASS**: chave fora da seleção devolve `false` e não mexe no contexto nem na seleção; chave selecionada leva a `.source(sourceID)` e a seleção permanece idêntica |
| UI (jornada) | `FeedMineUITests.testF12TheSourceRowOpensItsOwnFeedAndTheToggleDoesNot` — **SKIPPED com medição**, não PASS. No `FeedMine Reserve 1024` a árvore do sheet fica `Application`-only (app em foreground, `state=4`, inalterada aos 181 s). No **iPhone 17 ocioso** (device diferente, mesma jornada): o sheet abre (`sources-done` presente), mas **nenhuma linha do catálogo aparece em 90 s** — falha diferente, mesmo efeito. Controle positivo: jornadas **sem sheet** (`PortabilityJourneyUITests.testOnboardingComposerResetAndStartBroad` e a jornada `deferred`) passam no Reserve. Controle negativo: o teste **existente** `FeedMineUITests.testBookmarkBoxesManageAndOpenTheirOwnList` falha com o **mesmo sintoma de título/conteúdo do sheet ausente** (nav bar `Caixas de salvos` e `Salvos` ausentes) — e a árvore **não** estava vazia ali: o campo de texto do alerta apareceu (`Emoji`, `dictate`). Ou seja, o que se mede é a ausência do título/conteúdo do sheet, não “sheet sem árvore alguma”. |

A jornada preservada (`FeedMineUITests.testF12TheSourceRowOpensItsOwnFeedAndTheToggleDoesNot`, dentro da mesma
classe dos helpers comprovados — `scrollIntoView` com `app.tables`, e o toggle como `app.switches`, não botão)
descreve o fluxo completo: superfície vazia → Fontes → seção → nó real do catálogo → linha da fonte (sem controle
enquanto não selecionada) → toggle sem navegar → linha abre o feed → rótulo do contexto é o nome da fonte → cartas
só daquela fonte → reabrir Fontes volta ao mesmo nó. Verificada nesta árvore: **compila e skipa** com a medição
acima (`1 skipped, 0 failures`).

## Limites

- **A prova de UI não é PASS.** O skip carrega a medição; nenhuma asserção foi trocada por existência de
  `Application`.
- O feed de fonte fora da seleção não existe no modelo de sessão (documentado acima); não foi inventado.
- Nada de gates, oráculo, limiar, corpus ou driver foi tocado. B03 continua FAIL mecânico, alheio a esta entrega.
- Não há alegação de UX12 completo: UX12-A/C/D seguem sem prova nesta rodada.
- Artefatos externos: `/tmp/nf04-r7-apptest3.log`, `/tmp/nf04-r7-ui4.log`, `/tmp/nf04-r7-sheetcontrol.log`,
  `/tmp/nf04-r7-dd` (derived data, descartável).

## Rodada 8 — a fonte catalogada **não selecionada** (requisito integral)

A rodada 7 abria somente fontes já selecionadas, e a limitação de `sessionState` (`.source` fora da seleção vira
`.main`) havia sido tratada como regra. Não é: R1 (tocar a origem leva ao destino), R4 (habilitar é opcional) e S1
(abrir não reabilita endpoint nem substitui a Edition) pedem a fonte catalogada **mesmo desabilitada**.

| Requisito | Implementação | Prova |
|---|---|---|
| identidade canônica, sem invenção | `AppComposition.catalogueFeed(forKey:)` resolve a chave pelo dono (`TrustedFeed.resolveAvailable` sobre o catálogo ativo); nada é derivado, nada é casado por título/URL | teste de app resolve a mesma chave por `LegacyCatalogReader` + `LegacyCatalogImport` e compara o `SourceID` |
| abrir sem habilitar endpoint / alterar seleção | `openSourceContext` mantém `feeds` = seleção do leitor; só o **filtro** passa a ser a fonte. Nenhum target/registro é criado para ela | `sourceKeys` idêntico antes/depois; `composition.feeds` idêntico; `selectContext(.source:)` continua recusando a mesma fonte |
| só memberships locais da fonte | elegibilidade da sessão inclui **apenas** a fonte do contexto (`AppComposition` policy: `eligible ∪ {contextSource}`); a janela de candidatos já é *source-scoped* | duas memberships semeadas (S e outra); publica a de S e **nenhuma** da outra |
| vazio/erro honestos | sem supply local a sessão apresenta a ausência (`.unavailable`), sem cair no feed principal | UI (jornada, quando o sheet expõe linhas) verifica a superfície de ausência e a ausência de outras fontes |
| botão e toggle independentes, também desabilitada | `NodeSourcesView` desenha o controle sempre que o host tem destino (não exige `isSelected`); o toggle segue irmão | teste de app abre com a fonte fora da seleção; a jornada de UI afirma o controle com o switch em `0` |
| retorno/nó/contexto preservados | `sourcesPath` não é limpo; o host abre antes de fechar (o dismiss não disputa `replacingSession`) | UI (quando executável); app test afirma o contexto após a recusa da rota comum |

**Validação executada (candidata):** `CompositionTests.testF12OpensAnUnselectedCatalogueSourceWithOnlyItsLocalMemberships`
— **PASS** (0,79 s): contexto `.source(sourceID)`, nunca `.main`; seleção e feeds inalterados; carta publicada só da
fonte S; a outra fonte semeada não aparece. `testF12RefusesAnUnresolvableKeyAndOpensTheSelectedSource` — **PASS**.

**Controle base × candidata (device e configuração idênticos):** o teste **pré-existente**
`testCleanInstallPresentsTheBundledCatalogueSourceWithTransportBlocked` foi executado na candidata e na base
`dde275fa` (worktree isolado `/tmp/feedmine-base-dde275fa`, assets não versionados copiados do checkout principal,
depois removido). **As duas árvores falham nas mesmas linhas (215/224/226)**: a asserção de locale espera pt-BR num
device em inglês e a superfície de Fontes não lista as seções. Causa medida no container do app: a instalação
recusa a revisão 5 obtida da rede por `sha256 mismatch` (`quarantine.jsonl`) e serve o catálogo empacotado em modo
degradado; o sheet não expõe as linhas em nenhuma das árvores. **Isso não é F12 e não é regressão da candidata.**

**Limites declarados, sem aceite:**
- A jornada de UI segue **skipada** com a medição (compila; `1 skipped, 0 failures`). Skip **não** é aceite: a
  prova de UI da abertura não selecionada continua pendente enquanto o sheet não expuser as linhas. ~~o próximo
  passo é o modo degradado do catálogo (`hasCatalog`/fallback empacotado)~~ **SUPERADO em 25/10:** o modo degradado
  foi corrigido (`7b201f7b`), as linhas são desenhadas e há captura antes/depois abaixo; o que resta é só a árvore
  do sheet no cliente de UI.
- ~~**Relançamento:** abrir grava o contexto da fonte; num novo launch, `sessionState` (sem o flag explícito) ainda
  converte `.source` fora da seleção em `.main`. Isso é uma lacuna conhecida do caminho de launch, **não** coberta
  por esta rodada.~~ **SUPERADO em 25/10 (rodada 8, continuação):** init, launch, warm e rebuilds passam
  `allowsSourceOutsideSelection` para uma chave `.source`, e a segunda composição no mesmo contêiner mantém o
  contexto (`7b201f7b`, `2c091bea`). O texto fica pelo histórico; vale a continuação abaixo.
- `capacity-ready.json` preservado; nenhum gate/oráculo/limiar/corpus tocado; B03 segue FAIL mecânico.

## Rodada 8 (continuação) — a causa do sheet era **produto**, e foi corrigida

A suspeita anterior (catálogo degradado) foi fechada com artefato visual, sem XCTest e sem depender da árvore AX:
o app foi lançado no Reserve com namespace novo e `SKIP_ONBOARDING=1`, e o teste de diagnóstico capturou a tela
com `XCTAttachment(screenshot:)`. A captura mostrou **“The source catalogue isn't available.”** e nenhuma seção —
enquanto o feed lia o catálogo empacotado. Logo, a ausência de linhas era estado de produto, não do harness.

**Causa:** `SourceManagementCoordinator.catalog` só usava `installation.activeSnapshot()` (snapshot verificado).
Com a revisão remota rejeitada por `sha256 mismatch`, não havia snapshot verificado, e a superfície declarava o
catálogo indisponível embora a composição servisse o **catálogo empacotado em modo degradado** (o próprio ledger
diz “serving the bundled catalogue unverified”).

**Correção (owner existente, sem catálogo alternativo):** sem snapshot verificado, o coordenador lê o
`bundledCatalogue` do build (o mesmo que a composição já serve), e `hasCatalog` passa a ser verdadeiro. A
verificação continua sendo um fato declarado no ledger, não um motivo para esconder a árvore (R2).

**Provas:**
- captura antes/depois: `2026-10-25-sources-unavailable-before-fix.png` (indisponível) e
  `2026-10-25-sources-sections-after-fix.png` (“Sections (18)”, Arts & Culture … Countries 63.894 feeds);
- `CompositionTests.testF12DegradedCatalogueStillExposesTheBundledTree` — **PASS** (diretório sem snapshot
  verificado: `hasCatalog` verdadeiro e a seção `15-nature-animals` presente);
- o **relançamento** deixou de cair em `main`: o init agora carrega o contexto persistido com o mesmo flag do
  open, e `testF12OpensAnUnselectedCatalogueSourceWithOnlyItsLocalMemberships` verifica uma nova composição no
  mesmo diretório (contexto `.source(id)`, seleção e feeds inalterados) — **PASS**.

~~**O que continua fora de alcance:** a **árvore de acessibilidade do sheet** neste device/runtime continua
Application-only mesmo com as linhas desenhadas (medido pelo mesmo diagnóstico). A jornada de UI segue skipada com
essa medição; a interação e o conteúdo estão provados no nível de app e a tela está provada por captura. Skip não
é aceite e está registrado como tal.~~ **SUPERADO em 25/10 (rodada 10):** a jornada **PASSA** com a árvore viva; a
falha de cartas era o estado vazio de seleção (`hasSources`), não o harness. Ver “Rodada 10” abaixo.

## Rodada 10 — o corpo da fonte desabilitada era o **estado vazio** (25/10, noite)

A falha de `testF12TheSourceRowOpensItsOwnFeedAndTheToggleDoesNot` (0 cartas depois de abrir a fonte) foi
**atribuída a produto com o snapshot AX do próprio instante da falha**, exportado do `.xcresult`
(`xcresulttool export attachments`), não por inferência:

| Fato no snapshot | Valor |
|---|---|
| chip de contexto | `reader-context-label` = **BBC News** (o destino é o certo) |
| corpo | `feed-empty-state`, `feed-empty-title` = **“Nenhuma fonte habilitada”** e `feed-empty-action` = “Escolher fontes” |
| registro de lançamento | `feed-launch-record … cards=6 first_cards_ms=64561 content_bottom=811 viewport_height=800 render_ready_cards=4` |
| entrega de viewport | `native-viewport-delivery … received=0` |

**Causa:** `AppComposition.hasSelectedSources` derivava de `feeds` (a seleção do leitor, vazia depois de desabilitar
S). `FeedScreen` escolhe a superfície pelo `hasSources`; com `false` ele desenha o estado vazio de seleção e **nunca
renderiza** a Edition restaurada — embora o estado da apresentação tivesse as 6 cartas (o teste de app e o banco do
próprio run concordam: duas edições de fonte, 6 cartas cada, e o checkpoint nomeando a âncora da edição reaberta).
O app test passava porque lê o **estado**; a view era o elo que faltava.

**Correção:** uma propriedade própria da superfície, `surfaceHasSources = hasSelectedSources ||
currentContextKey.request.isSource`, é passada nos **três** pontos que decidem a tela
(`FeedScreen(hasSources:)`, `noteFirstScreenAppeared(hasSources:)` e o `launchBranch` DEBUG, que promete ser a
mesma decisão da tela). `hasSelectedSources` continua respondendo
somente sobre a **seleção** (a primeira execução com `feeds: []` segue falsa). Nada de seleção, endpoint ou
Edition foi tocado.

**Provas executadas (device `39EA1733`, derived data `/tmp/nf04-r10-dd`):**
- `FeedMineUITests.testF12TheSourceRowOpensItsOwnFeedAndTheToggleDoesNot` — **PASS (478 s)** com a asserção estrita
  `waitForCards(1) > 0`; nenhum skip foi reintroduzido.
- `CompositionTests.testF12OpensAnUnselectedCatalogueSourceWithOnlyItsLocalMemberships`,
  `…testF12ReopeningADisabledSourceShowsItsAlreadyPublishedCards` (substituído na rodada 11 por
  `…testF12EmptySelectionOpensTheDisabledSourceWithNamedCards`, que parte de seleção vazia e exige D2),
  `…testF12ReturningFromASourceKeepsTheEditionsIdentity`,
  `…testSavedKeysMissingFromCatalogRemainSelectedWithoutVersionBump` — **PASS**.
- `…testDiscoveryFeedsAReaderWhoChoseNothing` e `…testTheExplicitAllLanguagesAnswerReachesDiscovery` — **PASS**
  (a mudança de `hasSources` não altera o leitor de `main`).
- Pacote: `swift test` **1722 testes, 1 skip, 0 falhas**. App: 197 testes, **9 falhas em 7 métodos, todas
  pré-existentes** (abaixo).

**Correção de atribuição:** a hipótese anterior de “perda de árvore AX” cabia à `debugDescription` de um app já em
teardown; no instante em que as 0 cartas foram medidas a árvore estava viva (o chip foi encontrado na linha anterior).
A falha era o estado vazio. O skip que eu havia condicionado a árvore ausente foi **removido**.

**Regra de launch refinada:** honrar `.source` fora da seleção só quando o leitor **já tem Edition** ali
(`PublicationStore.hasEdition(contextSourceID:)`); uma chave salva que não resolve nada é reparada para `main`
(PD10-P0D D1), como o teste de chaves ausentes exige. Um resultado inesperado da rodada: o primeiro `openSourceFeed`
de uma fonte fora da seleção não tem Edition ainda e **não** passa por essa regra (o caminho explícito o permite);
do segundo em diante, a Edition é o fato durável que sustenta o relançamento.

**Pendência do dono, medida e não consertada — o asset local é que está defasado:** `Resources` está **limpo no
HEAD** (`git status --short` e `git diff HEAD` vazios). O `catalog.manifest.json` commitado (25/10 07:32) declara
`sha256 1825fdae…` e `bytes 117993472`; o `catalog.sqlite` é **insumo local gitignored** de 16/10 com
`sha256 e6da170e…`. O HEAD não é defeituoso — o par local é que não casa, e o app **rejeita** e degrada, como deve.
`scripts/fetch-catalog.sh` é um stub que **recusa** (`exit 2`) e indica `scripts/bootstrap_catalog.py` com o
compilador V1 SHA-256 fixado; produzir o asset declarado está fora desta rodada. As 6 falhas de catálogo da suíte
(`testBundledCatalogHasRealBytes…`, 3×`testPD10…`, `CatalogueUpdateAccept…`) são estado local, não regressão; não se
regenera o manifesto nem se relaxa o teste para “passar”.

**A falha de reserva (`testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates`, 1 vs 17) é pré-existente:**
reproduzida com os meus 7 arquivos substituídos pelas versões do HEAD (`50,9 s`, mesma linha 647) — não é regressão
desta rodada. A branch `product/churn-20261025` (`0e7a35ee`) ativa o runway na primeira apresentação do bootstrap e é
o próximo passo provável, mas não foi mesclada nem alterada aqui.

## Rodada 11 — D2, o par de catálogo e o que continua vermelho (26/10)

### D1 continua sendo `surfaceHasSources`; D2 ganhou **um** dono de nome

A rodada 10 fechou D1 com `surfaceHasSources = hasSelectedSources || isSource` lido nos três pontos da superfície.
D2 (as cartas publicadas no contexto de fonte fora da seleção gravavam `source_display_name = NULL`) não estava
corrigido naquela árvore: o mapa de nomes continuava sendo só `supply`, e o chip usava memória de sessão
(`contextSource`), que não existe num relançamento.

O conserto integrado tem **um** dono, `AppComposition.sourceContextDisplayName`, consultado pelo chip **e** entregue
à sessão:

1. um feed vivo que nomeie a fonte (a seleção ou a coleção em leitura);
2. a linha do catálogo que o leitor abriu nesta sessão (`contextSource`, sem segundo lookup);
3. depois de um relançamento, a **atribuição que o próprio feed publicou** para aquela fonte
   (`PublicationStore.publishedSourceDisplayName(sourceID:)`, uma linha indexada em `published_cards`, depois
   `retired_published_cards`). Nada de varrer o catálogo de 77k no launch (INV-07).

`FeedAssociation.presentationNames(supply:contextKey:contextSourceDisplayName:)` acrescenta a fonte do contexto
**apenas ao mapa de atribuição**. `supply`, `registrations`, elegibilidade, `acquisition_targets` e endpoints não
mudaram: abrir a fonte continua sem habilitar nada, e o teste afirma a identidade do target antes/depois.

### Regressão nova, com controle vermelho

`CompositionTests.testF12EmptySelectionOpensTheDisabledSourceWithNamedCards` parte de `feeds: []`, habilita S pelo
owner da superfície (`SourceManagementCoordinator.setSourceEnabled`), espera a publicação, captura o target,
desabilita S, e então abre a linha. Afirma, na ordem em que o produto decide: `.main` com seleção vazia continua
`surfaceHasSources == false` (o controle honesto de T7/F02); a abertura não escreve seleção nem muda o target;
`hasSelectedSources == false` **e** `surfaceHasSources == true` (D1); ≥1 carta sem `refreshFromTheReader`/`retryNow`,
somente a fonte S, e `sourceDisplayName == "BBC News"` em **todas** as cartas publicadas (D2); então relança no mesmo
container com `feeds: []` e exige contexto `.source`, o mesmo nome no chip e nas cartas restauradas.

| Execução | Resultado |
|---|---|
| árvore final | **PASS** (0,56 s) |
| controle vermelho (D1 revertido a `hasSelectedSources`, mapa de nomes só de `supply`, sem fallback persistido) | **5 falhas**: D1 na abertura, as 17 cartas com `nil`, `surfaceHasSources` no relançamento, nome `nil` vs `BBC News`, e as cartas restauradas sem nome |
| árvore restaurada | **PASS** outra vez, no lote de 14 abaixo |

### Jornada de UI estrita, sem skip

`FeedMineUITests.testF12TheSourceRowOpensItsOwnFeedAndTheToggleDoesNot` — **PASS (472,63 s)** no device
`39EA1733` com o par de catálogo do build 56 (482,96 s com o par antigo do build 55). As cláusulas que antes aceitavam vazio agora exigem: ≥1 carta depois de abrir a fonte desabilitada
**e** ≥1 carta depois do relançamento; a atribuição é lida **dentro do nó da carta** (`cardCarries("BBC News")`), não
pelo `staticTexts["BBC News"]` que casa o chip; o chip do relançamento é exigido `BBC News` (não mais `"Uma fonte"`).
O helper de rolagem continua tentando `tables` **e** `collectionViews` antes do swipe do app (runtime iOS 26 expõe a
lista do sheet como collection). `NodeSourcesView` mantém `onClose` no próprio nó (`node-sources-done`), e a jornada
prova que reabrir a superfície volta ao **mesmo** nó.

### O par de catálogo do build 56 existe e foi instalado (com uma correção de rota)

**Sintoma:** este checkout trazia o descritor commitado em `55c097ab` (`sha256 4cc9cba6…`, que declara
`catalogue 1825fdae…`) ao lado de um `catalog.sqlite` gitignored `e6da170e…`. Esse `.sqlite` é o par do
**build 55** (o IPA de release já distribuído), anterior ao descritor; o app recusava o par em execução
e seis testes de catálogo falhavam.

**Varredura que decidiu (e o erro que ela corrigiu):** a primeira tentativa desta rodada procurou os
bytes só em `~/Documents`, `/tmp` e DerivedData, não achou `1825fdae` e instalou o par antigo,
reescrevendo `CATALOG.md`. Isso estava **errado**: a varredura não cobria `~/.codex/worktrees`. A
varredura correta (`~/.codex/worktrees`, `~/Documents`, `/tmp`, `~/Desktop`, `~/Downloads`,
`~/Library/Developer/Xcode/Archives`) encontrou **55** arquivos `catalog.sqlite`; **33** com o
tamanho esperado (117.993.472 B) foram hasheados; **11** são `1825fdae…`:
`feedmine-bisect`, `-bisect-base`, `-bisect-pre`, `-bisect-reader`, `-churn`, `-reserve2`, e — em
`feedmine-reader-position` e `feedmine-reserve` — `Resources`, staging e `.xcarchive`. Os outros 22
desse tamanho são `e6da170e…` (build 55). O commit errado foi revertido (`22e2716c`).

**Par verdadeiro, com proveniência do próprio pipeline:**
`~/.codex/worktrees/feedmine-reserve/feedmine_v2/build/catalog-bootstrap` — `state.json` registra
`catalog.sqlite 1825fdae…` (117.993.472 B), descritor `4cc9cba6…` (byte-idêntico ao commitado),
`build-report.json cf885af7…`, `builtAt 2026-10-24T19:06:40Z`, compilador `build_catalog.py
e3c9fcf2…` + `catalog_identity.py 2a83b833…` (Python 3.11.1), árvore `846b1720…` e manifesto público
`2a4f754f…` (revisão 5).

**Instalação:** o `.sqlite` e o descritor foram copiados para `Resources` (o descritor não mudou em
relação ao commit, porque o commit já era o certo) e `scripts/bootstrap_catalog.py` foi rodado com os
hashes pinados neste checkout: o gate de idempotência respondeu *“reused: catalog.sqlite compiled at
2026-10-24T19:06:40Z”*, o descritor saiu **inalterado**, e `state.json`/`provenance.json` foram
reescritos pelo próprio script com os caminhos deste workspace — sem recompilar e sem trocar checksum.

**Verificação:** `scripts/verify_catalog_release.py preflight --head <SHA>` →
`P0C preflight verified: revision 5 / manifest 2a4f754f… / sqlite 1825fdae…` (exit 0); metadata do
banco `schema_version=2`, `catalog_version=1792868795281916`, 77.443 fontes, 6.450 nós, 77.443
placements. Backup do par antigo (build 55) e do staging anterior:
`/tmp/feedmine-omp-final-integration/catalog-bootstrap-repair/pre-repair/` e `…/e6da17-staging/`.

As 6 falhas de catálogo da rodada 10 eram **deste par**, e não regressão: com o par do build 56
passam `testBundledCatalogHasRealBytesAndStableBoundedDefaults`,
`testPD10StandardPublicAuthorityChecksFirstForegroundAfterLocalPaint`,
`testPD10RelaunchRespects23And25HourWindowAndConsistent304`,
`testPD10FailedInstallNeverPersistsTheOfferedETag`,
`testPD10B1B3ForegroundActivatesSixWithoutChangingCompletePublishedPresentation` e
`CatalogueUpdateAcceptTests.testForegroundAcceptsTheAuthoritiesNewerRevisionWithoutTouchingTheReadersStore`.

### D2 no banco do run real

A jornada de UI deixou, no container do próprio app (copiado para
`/tmp/feedmine-omp-final-integration/ui-journey-runtime-truepair/`), a prova persistida de D2:

```
reader_preferences: request.source(3714853F…), source_keys = []
feed_editions:     2 edições de contexto `source`
published_cards:   12 cartas — todas source_display_name = "BBC News", todas do source 3714853f…
```

Ou seja: com a seleção vazia, as cartas publicadas **na fonte desabilitada** carregam o nome, em duas
gerações (antes e depois do relançamento) — o `NULL` medido no diagnóstico original não aparece.

**Fronteira de confiança do fallback bundled (reavaliada):** `SourceManagementCoordinator` só cai para
`installation.bundledCatalogue` quando não há snapshot verificado, e esse caminho lê um recurso do **próprio bundle
assinado** — o mesmo que a composição já serve, com `kind: "degraded"` escrito no ledger por
`CatalogInstallation.degraded(_:)`. A verificação não é afrouxada: `bootstrap()` continua tentando
`installBundled()` com `CatalogManifest.validate(manifest, catalogue:)` e recusa (registrando) quando não casa; o
fallback apenas deixa de esconder a árvore quando a verificação não produziu snapshot. Ele não concede autoridade de
aquisição: habilitar fonte continua sendo o ato durável do leitor + registro de target. Com o par reparado, o caminho
degradado deixa de ser o normal deste build.

### O vermelho que sobra: reserva, caracterizado e **não** verde

`testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates` (1 carta vs 17 exigidas):

| Medição | Resultado |
|---|---|
| isolado, árvore final (6 execuções: 5 antes da instrumentação, 1 depois) | **FAIL** 1 vs 17 em todas |
| suíte de app completa, **par de catálogo do build 56** (o commitado) | **197 testes, 1 falha — exatamente este caso** |
| suíte de app completa, par errado do build 55 (medida intermediária, descartada) | PASS — o catálogo degradado mudava a ordem de aquisição e **mascarava** o caso |
| sonda em `LocalProductionSlice.run` (removida) | `structural=24 window=24 eligible=24 ready=24 publishedInWindow=1 cursor=false` |
| sonda de uma segunda oportunidade (removida) | `after-first=1`, `after-second=1`, **sem** segunda linha de slice local |

Mecanismo medido: a primeira publicação do bootstrap coloca **1** carta de uma fonte (PD-4: duas cartas adjacentes da
mesma fonte são proibidas, e a janela só oferecia essa fonte); após a liberação da segunda fonte, a slice local
examina uma janela de 24 candidatos de **uma** fonte com o tail da edição na mesma fonte, e `MaximumDistanceSequencing`
(v6) não coloca nada; o runway passa a ver `ready_cards=0`, pede rede, recebe `up_to_date`, e a oportunidade seguinte
**não emite slice local** — a janela fica em 1. O desfecho depende de qual fonte tem as linhas mais novas (ordem de
aquisição, diferença de microssegundos) — e o par de catálogo errado bastava para mudar essa ordem e
fazer a suíte passar. Com o par correto, isolado e suíte concordam no vermelho.

Não é aceitável declarar verde: a decisão que falta é de **planejamento do runway** (depois de uma slice que não
coloca nada, continuar a página local seguinte enquanto a caminhada não estiver exausta e houver suprimento pronto,
em vez de ir à rede e parar), camada que governa B03 — cuja classificação o dono mandou não mexer nesta tarefa.
Nenhum gate, driver, corpus, limiar ou teste foi alterado para mascarar isso.
