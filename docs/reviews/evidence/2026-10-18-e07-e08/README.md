# E07 (busca/diversidade) e E08 (durabilidade/lifecycle) — cobertura

Mapeamento por busca no repositório (referências `arquivo:linha` dos testes). Não é certificação: cada linha diz o
nível real da prova.

## E07 — busca e diversidade

### Coberto

| Critério | Prova | Nível |
|---|---|---|
| Dois bancos/relançamentos | `CompositionTests.swift:1128` `testSavedSearchReopensOfflineInSameScope`; `:996` `testSavedSearchReopensWithSameExpressionAndScopeOffline` | Composição + SQLite (reabertura in-process) |
| v5 e versões antigas | `SelectionDiversityTests.swift:53,73,93,122,136`; `CompositionTests.swift:2411,2474`; `PublicationStoreTests.swift:72` | Unidade + composição |
| Campos ausentes | `SearchExpressionTests.swift:14`; `LegacyCatalogReaderTests.swift:70`; `CandidateProviderTests.swift:72`; `SelectionDiversityTests.swift:93,136` | Unidade/SQLite |
| Negativos | `SearchExpressionTests.swift:14,38,53`; `LegacyCatalogReaderTests.swift:70`; **novo** `CompositionTests.testSavedSearchReopensWithSameExpressionAndScopeOffline` executa `fixture -19` sobre as autoridades locais: "Published fixture 11" presente, "Published fixture 19" ausente | SQLite + composição |
| Paginação de fontes/artigos | `LegacyCatalogReaderTests.swift:70,39,116`; `FeedScreenStoreTests.swift:299`; `CompositionTests.swift:1020` `testLocalMatchBeyondFirst400IsReachable` | SQLite + store |
| Erro parcial | `.catalogue`: `CompositionTests.swift:1054` `testSearchFailureIsNotEmptyResult`; `.saved`: `CompositionTests.testSearchSavedAuthorityFailureIsExplicitAndContentStillAnswers`; `.content`: `CompositionTests.testSearchContentAuthorityFailureIsExplicit` (tabela `selection_supply` removida; `failedAuthorities` contém `.content`); `FeedScreenStoreTests.swift:299` cobre a união de falhas | App host + SQLite real |
| Abertura de resultado | **novo** `CompositionTests.testOpeningASourceSearchResultSelectsThatSourceContext`: um resultado **sintético** com destino `.source` leva o leitor ao contexto daquela fonte; falta o mesmo para um resultado produzido pela busca real e para `.savedCard`/`.article` | App host |
| Cancelamento | `CompositionTests.swift:1153` `testCancelSearchRestoresExactPreviousContextAndAnchor`; `FeedMineUITests.swift:2564` (T12, app real) | Composição + app |
| Busca salva offline | `CompositionTests.swift:1128`; `:996` (nenhuma requisição da busca) | Composição |
| Integração P07–P10 | `CompositionTests.swift:945,996,1020,1054,1089,1111,1128,1153,1179,1241`; `PublicationStoreTests.swift:72`; `CompositionTests.swift:1601` | Mista |
| Diversidade persistida → engine (v5) | **novo** `LocalProductionSliceTests.testPersistedDiversityFactsSurviveRestorationAndDriveTheEngineOrder`: publica, relê `recentDiversity` de um segundo `RuntimeDatabase` sobre o mesmo diretório, compara com os fatos vivos, e prova que o contexto restaurado inverte a ordem (fonte nova antes da repetida) enquanto sem contexto a ordem é a recência | SQLite real + engine |
| Paginação de artigos (host) | **novo** `CompositionTests.testUnifiedSearchHostContinuationServesTheNextArticlePage`: `AppComposition.unifiedSearch(articleAfter:)` serve a página seguinte com o resultado mais antigo | App host + SQLite real |
| Paginação de fontes (host) | **novo** `CompositionTests.testUnifiedSearchHostSourcePageServesADisjointNextPage`: primeira página truncada (~40 fontes) e `sourcePage: 1` devolve conjunto disjunto — sobre o **catálogo publicado embutido no app**, não o corpus congelado do benchmark | App host + catálogo embutido |
| Edição antiga (v4) restaurada | **novo** `LocalProductionSliceTests.testRestoredDiversityFactsLeaveAnOlderSequencingEditionInRecencyOrder`: os mesmos fatos restaurados não mudam a ordem sob `sequencingPolicyVersion = 4`, enquanto sob 5 a fonte nova passa à frente | SQLite real + engine |

### Gaps mantidos

1. Relançamento **de processo** para busca: as provas reabrem o banco/composição, não o app (`XCUIApplication`).
2. ~~Edição antiga (v4) restaurada~~ — **fechado** pelo teste acima (v4 vs v5 sobre fatos lidos de um banco reaberto).
3. ~~Paginação do host~~ — **fechado** para artigo e fonte pelos dois testes de `CompositionTests` acima. O fim de
   universo (`nextCursor == nil` / `sourceTruncated == false`) continua provado só no leitor/store.
4. **Destino `.source`:** o **roteamento** `.source(principal:sourceID:)` está provado
   (`testOpeningASourceSearchResultSelectsThatSourceContext`), mas com um resultado **sintético**. Falta um resultado
   `.source` produzido pela busca real sobre o catálogo, e os destinos `.savedCard`/`.article` (link externo/toast)
   continuam sem prova.
5. ~~Falhas de `.saved`/`.content`~~ — **fechadas** pelos dois testes de `CompositionTests` acima. Falta apenas o
   retry/superfície de erro (`onRequestSearchAgain`).
6. Cancelamento **durante** a busca suspensa (`ReaderLocalSearch.run` usa `Task.detached`).
7. ~~Abertura de resultado de busca~~ — **fechada** para destino `.source`; `.savedCard`/`.article` continuam sem
   teste dedicado.

### Tentativa registrada: relançamento de processo para busca

Exercício de UI preparado para submeter `fixture`, encerrar o app, relançar com o transporte bloqueado e buscar de
novo. **Foi medido e retirado.** No primeiro passo, depois de `onSubmit` via `typeText("\n")`, a superfície
`reader-search-results` não apareceu (espera de 20 s) e a árvore AX de falha mostrava o feed comum — cards "BBC World
story 19/18", "BBC Science story 27", sem barra de busca. A asserção de título também estava errada para este
caminho: os títulos reais são **"BBC World story N"**, não "Published fixture 11". O teste foi removido em vez de
permanecer vermelho ou ser afrouxado; o diff congelado voltou a `1f8777c3…` depois da remoção. Consequência: o
caminho de submissão de busca pela UI não está provado; o gap 3 continua aberto e precisa de instrumentação (ou de
um fluxo de submissão explícito na superfície) antes de virar teste. O contrato de busca salva offline segue provado
em `CompositionTests:1128/996`; o que falta é o relançamento de **processo** pela UI.

## E08 — durabilidade e lifecycle

### Coberto (por critério, com nível)

- **Force quit:** `FeedMineUITests.swift:1201` (app real), `:1082` (offline real), `DiscoveryBenchmarkTests.swift:637`
  (B05); in-process: `CompositionTests.swift:1620`, `FeedSessionCheckpointTests.swift:304,552`,
  `ReaderLibraryStoreTests.swift:162`.
- **Purge de cache:** `SavedMediaCoordinatorTests.swift:167`, `CompositionTests.swift:1620`,
  `MediaTidyFactsTests.swift:9`, `MediaHousekeepingTests.swift:7,22`, `MediaPolicyResolverTests.swift:108`.
- **Disco cheio:** `SavedMediaCoordinatorTests.swift:320`, `AssetStoreTests.swift:133`, `MediaTidyFactsTests.swift:9`
  (injeção de `ENOSPC`/`insufficientSpace` ou `freeStorageBytes: 0`).
- **Salvo em duas caixas:** `SavedMediaAvailabilityStoreTests.swift:47`, `ReaderLibraryStoreTests.swift:38`,
  `CompositionTests.swift:1543`; UI só lista caixas (`FeedMineUITests.swift:283`).
- **Falha de gravação:** triggers reais de SQLite em `FilterConfirmationBoundaryTests.swift:55,90,125`,
  `CompositionTests.swift:1179,915`, `ReaderPreferencesStoreTests.swift:132`, `SessionStoreTests.swift:43`,
  `ReaderLibraryStoreTests.swift:187,387`; falhas de fs em `AssetStoreTests.swift:84,95,112,133`,
  `CatalogInstallationTests.swift:318,333`; rollback de admissão em `AcquisitionAdmissionStoreTests.swift:419` e
  `ContentStoreTests.swift:237,329`.
- **Grant expirado:** `FeedRunwayDriverTests.swift:825`; `BackgroundFeedRefreshTests.swift:13,40,54`.
- **BGTask do host:** só a **declaração** (`CompositionTests.swift:4386`).
- **Aposentadoria com mídia pendente:** `MediaPrefetcherTests.swift:130,157`, `FeedRunwayDriverTests.swift:288,899,958`,
  `AcquisitionCoordinatorTests.swift:554,577`.
- **Sem start não autorizado/perda silenciosa:** fences em `FeedRunwayDriverTests.swift:825`,
  `AcquisitionCoordinatorTests.swift:215–264`, `MediaPrefetcherTests.swift:130,157`, `BackgroundFeedRefreshTests.swift:13,40`;
  instalação tardia recusada em `CompositionTests.swift:2882,2316,4208`.

### Gaps mantidos como impedimentos

1. **Force quit durante preparação de mídia salva** e reabertura offline de um salvo **com mídia** (as provas usam
   novo handle in-process; os testes de app só afirmam bookmark/posição).
2. **Purge real do sistema** (container/eviction): as provas apagam arquivos/Caches à mão; nenhuma verifica a
   demotion de uma linha `ready` quando o asset desaparece com o app offline.
3. **Disco realmente cheio:** todas as provas injetam o erro.
4. ~~**Falha de gravação de `saved_media_availability`**~~ — **corrigido em 2026-10-19.**
   `SavedMediaCoordinator` registrava com `try?`: uma escrita recusada devolvia `.ready`/`.pending` sem linha
   durável e a preparação seguia. Agora `recordState` devolve se a escrita ficou durável; `textOnly`/`ready` viram
   `.failed` quando o registro falha, e `pending` recusado **não inicia** a preparação. Prova discriminante:
   `SavedMediaCoordinatorTests.testRefusedAvailabilityWriteReturnsFailureAndPromisesNothing` instala um trigger
   `BEFORE INSERT` que aborta toda escrita. Contra o HEAD (pré-correção) falhou com `ready != failed` e uma chamada
   de fetch; com a correção passa, sem fetch e sem linha. Suíte de composição: 8/8.
   Mantido: a superfície que **apresenta** o `.failed` de escrita (rótulo) não tem teste de UI.
5. **Integração de mídia salva no app** (toggle → `prepareSavedMedia`, rótulos "Mídia pendente"/"Somente texto").
6. **BGTask real:** `register`, `expirationHandler`, `setTaskCompleted` e os guardas de
   `backgroundRefreshOpportunity` exigem iOS físico.
7. **Fechamento do app com fetch/preparação em voo** (ordem retirement → settle → invalidate): só as fences de
   unidade são testadas.
8. **Tidy de mídia agendado** (`tidyAllowanceSeconds`).
9. **Duas caixas na superfície de salvos** (retenção provada só no store).
10. **SIGKILL no meio de transação** (as provas usam triggers de SQLite).

## Fechado ou estreitado em 2026-10-19 (rodada pós-Codex)

| Gap | Estado | Prova |
|---|---|---|
| E07.1 relançamento de **processo** pela UI | **FECHADO** | `FeedMineUITests.testT12SearchSubmitsAndReopensOfflineAsTheSameSurface`: digita `Fixture`, submete, vê `reader-search-results` + `reader-search-result-*`; termina o app, relança com `FEEDMINE_BLOCK_RSS_NETWORK=1` e vê a mesma página. PASS 18,7 s. |
| E07.4 `.savedCard`/`.article` | **FECHADO** | `CompositionTests.testReaderSearchShowsRealTypedSections` executa os dois destinos com resultados reais (carta salva → leitor; ocorrência sem carta publicada → link da revisão). |
| E07.5 retry/erro | **FECHADO** (store) | `FeedScreenStoreTests.testCancelInvalidatesInFlightCompletionAndRetryRestartsTheSearch` prova `failUnifiedSearch → requestSearchAgain` e a intenção única ao host. |
| E07.6 cancelamento em voo | **FECHADO** (store) | o mesmo teste: `cancelSearch` invalida a conclusão em voo (`applyUnifiedSearch == false`). |
| E08.2 purge real (eviction) | **ESTREITADO** | `SavedMediaCoordinatorTests.testOfflinePurgeDemotesReadyInsteadOfClaimingAvailable`: o arquivo é apagado atrás do app, a reabertura offline demove `ready → pending`, mantém o bookmark e não promete bytes ausentes. Ainda não é o evictor do sistema, é o mesmo efeito observável. |
| E08.4 apresentação do `.failed` | **FECHADO** | `CompositionTests.testRefusedSavedMediaWriteIsShownOnTheRowAndRetryRecordsTheOutcome`: escrita recusada → linha `.failed` na sessão, toast e retry; com escrita permitida, o estado durável vira `.failed`. `FeedScreenStoreTests.testSavedRowStatesSessionFailureInsteadOfStalePending` fixa o mapeamento. |
| E08.5 integração de mídia no app | **ESTREITADO** | o host republica a lista (`savedMediaRevision`) após cada preparação; os testes acima provam o caminho host, não um gesto de UI de mídia. |

Mantidos como impedimentos: force quit **no instante** da preparação (não agendável no XCUITest), disco realmente
cheio (encher 461 GB é destrutivo; as provas injetam `ENOSPC`), BGTask real (iPhone listado **Offline** por
`xctrace`; simulador não dispara BGAppRefresh), tidy agendado, duas caixas na UI e SIGKILL no meio de transação.
