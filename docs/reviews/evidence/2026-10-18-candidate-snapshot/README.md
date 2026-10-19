# Candidata identificada — 2026-10-19 (final; correções P1/P2 pós-relatório Codex)

Árvore de produto desta rodada. Não é um commit nem uma aprovação de publicação: é a fotografia que permite
reproduzir os mesmos bytes e conferir cada veredito.

## Identidade

- `identity.txt`: branch `codex/v2-fluidez-capacidade`, `HEAD b0b961a0`, **63** arquivos rastreados modificados,
  11 não rastreados. **Diff completo `a2abcb72…`; produto `367d08e3…`.**
- `assets.sha256`: hashes dos assets ignorados pelo git — catálogo embutido (117.993.472 B), corpus congelado,
  manifestos do benchmark. Sem eles, o mesmo `HEAD` pode ser outro produto.
- `candidate.patch`: `git diff --binary HEAD` — aplicado a um worktree limpo em `b0b961a0`, reproduz
  **exatamente** o diff `a2abcb72…` (e o produto `367d08e3…`).
- `candidate-assets.tgz`: catálogo embutido + `catalog.manifest.json` + `bench/corpus/` inteiro; a extração confere
  com `assets.sha256` (`catalog.sqlite e6da170e…`, `items.json 4bb683a7…`, `corpus/catalog.sqlite 1f642eaa…`).
- `archive.sha256`: hashes do patch (`a2abcb72…`) e do tarball.
- **Os gates B01–B05 NÃO descrevem este produto.** Eles rodaram no produto `dc63a761…`; esta rodada mudou
  `FeedScreen`, `FeedScreenStore`, `AppComposition` e `FeedSavedListView` (busca, escopo e apresentação de mídia).
  O diff atual é `a2abcb72…`; a suíte de pacote foi reexecutada nele (**1.513 testes, 1 skip, 0 falhas**), assim
  como os bundles afetados (`FeedMineAppTests` e os testes de UI focais). B01–B05 precisam ser reexecutados antes de
  qualquer alegação de gate sobre estes bytes.

## Correções desta rodada (pós-relatório Codex)

1. **P1 busca visível**: `beginUnifiedSearch` reabre a superfície e restaura o termo; `FeedScreen` monta o shell
   quando `isSearching` mesmo com janela de feed vazia; `AppComposition` inicia a busca antes do launch do feed.
2. **P2 paginação**: páginas de artigo/fonte validam o token da página antes de mesclar (mesmo termo reiniciado
   rejeita página antiga).
3. **P2 escopo**: `changeSearchScope` grava a chave antes de mudar; escrita recusada restaura o escopo e mostra erro.
4. **P2 mídia salva**: falha de preparação chega à linha (`.failed` na sessão) e ao retry; a lista republica após
   cada preparação.
5. **E07 destinos**: `.savedCard` e `.article(cardID:nil)` executados com resultados reais.
6. **E08 purge offline**: `ready` é demovido para `pending` quando o asset desaparece e o app reabre offline.
7. **E03 offset fechado**: retorno distante medido em **16,0 pt** com critério 16±1 (PASS, 631,9 s).
8. **Medição**: janela de gesto declarada; o resumo do braço "depois" foi corrigido para 28/1.678, 2 misses
   (0,12%), pior 33,6 ms; trace completo 32/1.912, 4 misses (0,21%), pior 107,4 ms (primeira janela de aquecimento,
   agora explícita).

### Suítes reexecutadas nesta árvore (`a2abcb72…`)

- **Pacote Swift:** **1.513 testes, 1 skip, 0 falhas** (127,3 s).
- **Bundle `FeedMineAppTests`:** **158 testes, 0 falhas** (303,0 s), incluindo `testRefusedScopeWrite…`,
  `testRefusedSavedMediaWrite…`, `testReaderSearchShowsRealTypedSections` e
  `testOfflinePurgeDemotesReady…` no pacote.
- **UI focal:** `testT12SearchSubmitsAndReopensOfflineAsTheSameSurface` **PASS** (18,7 s);
  `testTenMinuteRestKeepsTheCardThroughLateSupplyAndADistantReturn` **PASS** (631,9 s, offset 16,0 pt).
- **Não reexecutados nesta árvore:** suíte UI completa (75 testes), B01–B05 e B06. Os vereditos B01–B05 acima são
  do produto anterior `dc63a761…` e não são transferidos.

## Correções anteriores da candidata (contexto)

1. **Origem autorizada nas páginas de descoberta** (`SyndicationAcquisitionSnapshot.discoverySnapshot`).
   Antes: no transporte local do benchmark, cada página materializada depois do snapshot da associação voltava a
   `publicOnly`; todo alvo descoberto nelas era recusado como `nonPublicHost` antes de qualquer HTTP. Medido na
   corrida anterior: 475 alvos, apenas **120** fontes alcançadas, 873 candidatos, oferta esgotada no minuto ~11.
   Depois: **475/475** fontes com HTTP 200 e 1.932–2.422 candidatos. Regressão discriminante em
   `SyndicationAcquisitionSnapshotTests.testK05DiscoveryPageConnectorKeepsAuthorizedBenchmarkOrigin`
   (vermelho `remoteResponse`/zero chamadas → verde `.batch`/uma chamada).
2. **Evento de checkpoint perdido no trace (B05)** (`AppComposition.report(checkpoint:)`).
   A linha em `context_checkpoints` era durável, mas o evento `position_checkpoint` ficava no buffer do trace quando
   o app era encerrado; o oráculo exige o evento. `flush()` após o registro; B05 voltou a PASS com as sete medidas
   verdadeiras e o evento presente.
3. **Resposta dada durante a construção da associação** (`AppComposition.association(contextKey:)`).
   O perfil de discovery era capturado antes do `await discoveryRead` e nunca relido; a associação final usava os
   interesses anteriores à resposta. Agora o perfil é relido (até 2 passadas) quando a resposta chega nessa janela.
   Os três `testAnswerDuring…TransitionIsApplied` passam; no HEAD eles também passavam (a janela mudou com o WIP).
4. **Teste desatualizado da versão de sequenciamento**: esperava 3, o WIP declara 5 (R17/A8). Corrigido para 5.
5. **U2 (leitor no app)**: o fixture padrão é um teaser (abre o site); o teste esperava `webViews` mesmo quando o
   leitor local é o caminho correto. Agora declara `FEEDMINE_FIXTURE_TEXT=longSummary` e aceita leitor local **ou**
   site. Passa em 28,8 s.
6. **E07 — diversidade persistida → engine**: novo
   `LocalProductionSliceTests.testPersistedDiversityFactsSurviveRestorationAndDriveTheEngineOrder` (publica, relê
   `recentDiversity` de um segundo `RuntimeDatabase` sobre o mesmo diretório, e prova que o contexto restaurado
   inverte a ordem; sem contexto a ordem é a recência).
7. **E07 — expressão negativa executada**: `testSavedSearchReopensWithSameExpressionAndScopeOffline` agora executa
   `fixture -19` sobre as autoridades locais: "Published fixture 11" presente, "Published fixture 19" ausente.
8. **E08 — escrita de disponibilidade de mídia salva não pode ser silenciosa** (`SavedMediaCoordinator`).
   `try?` devolvia `.ready`/`.pending` mesmo quando o registro em `saved_media_availability` falhava, e a
   preparação seguia. Agora `recordState` informa se a escrita ficou durável: `textOnly`/`ready` viram `.failed` e
   um `pending` recusado **não inicia** a preparação. Prova discriminante:
   `testRefusedAvailabilityWriteReturnsFailureAndPromisesNothing` (trigger `BEFORE INSERT` aborta a escrita) —
   contra o HEAD falhou com `ready != failed` e uma chamada de fetch; com a correção passa, sem fetch e sem linha.
9. **E06 — instrumento de cold start separado da descoberta** (`testReopenMeasurementColdAndWarm…`).
   A abertura medida herdava um perfil de descoberta que aponta para fontes do catálogo publicado; com o transporte
   recusado, nada publicava e o instrumento registrava `wait_passes=79, cards=0, first_cards_ms=n/a` por >6 min.
   Com `FEEDMINE_DISABLE_DISCOVERY=1` nas duas aberturas do exercício (fixtures locais respondem), a medição existe:
   **cold 1.188–1.314 ms** (4 passagens de `launch-progress` entre 519–948 ms) e **warm 793–884 ms**, com 85 cartas
   alcançáveis. O teste passou; a superfície de progresso na abertura fria permanece como observação.

## Matriz B01–B05 no diff `f5092e6f` (produto idêntico ao atual `9de88262`)

| Gate | Run | Veredito | Números |
|---|---|---|---|
| B01 A+B | `bench/run/20261019T041638Z` | **PASS** | 475 registradas, 974 contatadas (dois perfis), 95 fontes publicadas, 200 cartas |
| B02 | `bench/run/20261019T042513Z` | **PASS** | 200/200 relevantes, 76–103 fontes, máxima 4,5%, 0 adjacências, 0 duplicatas |
| B03 `--full-trace` | `bench/run/20261019T043856Z` | **PASS** | **3.398 avanços** (≥1.800), 0 duplicatas, 0 adjacências, **0 paradas ≥1 s**, 2.309 candidatos medidos, **475/475 fontes HTTP 200** |
| B04 | `bench/run/20261019T043138Z` | **PASS** | 255 instalações, 0 violações, 0 instáveis; protocolo completo (convite oferecido, resposta/desfazer/esconder); `b04-idle-stable` `not-measurable` |
| B05 | `bench/run/20261019T043521Z` | **PASS** | 7/7 medidas verdadeiras; salvo, âncora, A→B→A, reopen, offline e posição durável com evento no trace |
| B06 | — | **NOT_RUN / BLOCKED** | `xcrun xctrace list devices` lista o iPhone como **Offline**; nenhuma medição física feita |

## Suítes

- **Pacote Swift:** `swift-package-tests-final3.log` — **1.509 testes, 1 skip, 0 falhas** (126 s), incluindo o teste
  de edição antiga (v4) com fatos restaurados.
- **Bundle `FeedMineAppTests` (app host):** **156 testes, 0 falhas** (`run-final7-apptests.log`), incluindo as
  continuações de artigo e de fontes pelo host, as falhas explícitas de `.saved` e `.content`, e a abertura de
  resultado de fonte.
- **Bundle `FeedMineUITests`:** **75 testes, 9 skips, 11 asserções falhas em 5 testes** (`run-final3.log`). O reopen
  agora **passa** com o instrumento corrigido (cold 1.188 ms / warm 884 ms). Verde: 47 da classe
  `FeedMineUITests` (U2 incluído), `ArticleReadingDiagnosis` (1 skip justificado), `CardImageJourney`,
  `EndOfContent`, `FluidityJourney`, `ReadingSurface` (exceto os 4 de site), `AddFeed`, `CatalogueUpdate`,
  `BackgroundRefresh`. Classes vermelhas e classificação:
  - catálogo/rede reais (4 asserções em `EditorialOfferBudget`, 3 em `RealCatalogueCardsStayReachable`):
    **infraestrutura** — o perfil Brasil do catálogo publicado não entrega oferta no orçamento;
  - `SafariViewService` (3 testes de site, 4 asserções): **plataforma** — chrome não exposto; reproduzido no HEAD
    `b0b961a0`.
  `<br>`U2 agora exercita o leitor **local** (`longSummary`); o contrato de fechar o leitor **de site** via
  `SFSafariViewController` não é coberto por ele e permanece nas 3 falhas de plataforma acima — não são equivalentes.

## E03 — repouso e retorno distante (**PARCIAL**)

`../2026-10-18-e03-rest/README.md`. Exercício dedicado (gated por `TEST_RUNNER_FEEDMINE_LONG_REST=1`): repouso de
10 min estável (início/5 min/10 min, ±1 pt), chegada tardia sem gesto, rolagem distante e retorno por identidade.
Delta observado no retorno: **16,0 pt** — exatamente a margem de conteúdo de `NativeFeedTargets.padding`, registrada
como decisão do dono, não como violação; **o critério de offset não está fechado a ±1 pt** e o exercício aceita até
20 pt para não esconder o valor. Não cobertos: pressão de memória real e asset indisponível (referenciados a
`CardImageJourney`/B04). Em configuração diferente (40 itens, atraso 30 s) a janela ficou com uma única carta por
>15 min; achado registrado, causa não isolada.

## E07/E08 — cobertura e impedimentos

`../2026-10-18-e07-e08/README.md`. Cobertura mapeada por teste, com nível (unidade/SQLite/composição/app real).
Corrigido nesta iteração: a escrita de `saved_media_availability` deixou de ser silenciosa (red→green com trigger).
Fechados também: diversidade restaurada→engine (v5), edição antiga v4 e paginação do host (artigo e fonte).
Gaps mantidos: relançamento de processo para busca (a tentativa de UI foi medida e retirada — `onSubmit` não expôs
a superfície de resultados); falhas de `.saved`/`.content`; cancelamento em voo; abertura de resultado; BGTask real;
force quit durante preparação de mídia; purge real do sistema; disco realmente cheio; apresentação do `.failed` de
escrita na UI.

## E06 — acessibilidade e instalação limpa

Verde na suíte: iPad paisagem/retrato (4 pt), Dynamic Type de leitura e de controles de carta, rotação mantendo a
carta admitida, idioma da interface, primeira execução e instalação limpa com transporte bloqueado (70 s), warm
relaunch sem superfície de espera.
Aberto: **VoiceOver falado** (nenhuma captura de áudio/árvore falada). O **cold start está medido para a condição
sem descoberta** (`FEEDMINE_DISABLE_DISCOVERY=1` nas duas aberturas do exercício), com o relógio do processo
(`FeedLaunchWitness`):
- **cold:** primeira carta em **1.188–1.314 ms**, com 4 passagens de `launch-progress` entre 519–948 ms;
- **warm:** primeira carta em **793–884 ms**, zero passagens de progresso;
- 85 cartas alcançáveis no histórico do exercício.

**Não é a mesma condição do stall:** com perfil de descoberta respondido e transporte bloqueado (`LOCAL_FEEDS` cobre
só os dev feeds; o resto cai em `BLOCK_RSS_NETWORK`), a abertura ficou `wait_passes=79`, `cards=0`,
`first_cards_ms=n/a` por 389 s e mostrou "Não foi possível conectar…". Isso é **incapacidade da fixture de cobrir o
perfil respondido**, não o cold start medido acima. A superfície de progresso fria (~0,5–0,9 s) permanece como
observação de produto.

## Limites

- Árvore de trabalho: 62 arquivos rastreados modificados, 11 não rastreados. Nenhum commit, push, merge ou release.
- `bench/corpus/` e `catalog.sqlite` são ignorados; os hashes em `assets.sha256` são o que os prende.
- Uma corrida posterior em árvore alterada pode carregar outros bytes apesar do mesmo `HEAD`.
