# Suíte UI — 2026-10-18 (E05)

## Comando e ambiente

```
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,id=3AEA0B45-0BE6-49F1-8BAB-2591B13BBE7A' \
  -derivedDataPath /tmp/feedmine-ui-suite-derived -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

Simulador **FeedMine UI ptBR** (`3AEA0B45…`, `AppleLanguages = pt-BR`). O locale importa: a primeira
execução desta rodada usou o simulador do benchmark (`en-CA`) e produziu **56 falhas** em testes que procuram
texto em português (`run-enca-wrong-simulator.log`). O mesmo comando no simulador ptBR reproduz a matriz do
plano.

## Resultado antes das correções

74 testes, 8 skips, **16 asserções falhas em 11 testes** (`run.log`):

| Teste | Falhas | Causa classificada |
|---|---|---|
| `CompositionTests.testAnswerDuring{Context,Preset,Replace}TransitionIsApplied` | 3 | **Defeito real (WIP)**: a resposta dada durante a construção da associação não era lida antes do perfil de discovery — a associação final usava o perfil anterior |
| `CompositionTests.testFreshSessionDeclaresSupplyShareSequencing…` | 1 | **Teste desatualizado**: o WIP elevou a versão de sequenciamento para 5 (R17/A8); o teste ainda esperava 3 |
| `EditorialOfferBudgetUITests.testTheOfferBudgetHoldsOnTheRealCatalogue` | 4 | **Instrumento**: o teste não respondeu o composer, então o perfil persistido ficou vazio (`languages=[]`, `topicPreferences={}`, `source_keys=[]`) e a app mostrou corretamente `feed-empty-state` / "Nenhuma fonte habilitada" — não é falta de perfil Brasil nem de rede (`run-final3.log` 34852-35901) |
| `FeedMineUITests.testRealCatalogueCardsStayReachableByScrolling` | 3 | **Instrumento**: o chip do Brasil não estava na árvore (as regiões são `LazyVGrid`, o chip fica abaixo da dobra) e o teste caiu silenciosamente em `composer-region-90_countries/algeria` — o catálogo publicado tem 0 fontes `pt` sob a Argélia e 390 sob o Brasil, então nada era publicado (`run-final3.log` 38818-40119) |
| `FeedMineUITests.testReopenMeasurementColdAndWarmWithTheOnboardingAlreadyConcluded` | 3 | **Pré-existente**: a segunda abertura não apresenta o feed (mesma falha na suíte de 10:27, anterior ao WIP atual) |
| `FeedMineUITests.testU2SavedListAndInAppReaderPreserveTheSession` | 2 | **Instrumento**: o fixture padrão é um teaser (abre o site); o teste esperava `webViews` mesmo quando o leitor local é o caminho correto |
| `ReadingSurfaceUITests.testACardWithoutTextOpensTheSite` | 1 | **Plataforma**: `SFSafariViewController` não expõe o controle Close — **reproduzido no HEAD b0b961a0**, então não é regressão do WIP |
| `ReadingSurfaceUITests.testATeaserOpensTheSiteWithNoIntermediateScreen` | 1 | idem |
| `ReadingSurfaceUITests.testOpeningTheSiteFromTheLocalReader…` | 2 | idem |

## Correções aplicadas

1. `AppComposition.association(contextKey:)`: depois do `await discoveryRead`, o perfil é relido; se a resposta
   chegou durante a leitura, a leitura é refeita para o perfil atual (limite de 2 passadas). Os três testes de
   resposta durante transição passam.
2. `CompositionTests`: versão de sequenciamento esperada de 3 → 5, com a razão R17/A8.
3. `testU2…`: declara `FEEDMINE_FIXTURE_TEXT=longSummary` (leitor local determinístico, `reading.close`) e aceita
   leitor local **ou** site como "abriu dentro do app". Passa em 28,8 s.

## Ainda vermelho, explicitamente

- Catálogo/rede reais (2 testes): a classificação anterior ("o perfil Brasil do catálogo publicado não entrega
  cartas") não se sustenta na leitura dos próprios logs. No teste do orçamento o composer **nunca foi respondido**:
  o teste tocou "Abrir meu feed" em t+8 s e o perfil persistido ficou vazio, de modo que a app mostrou
  `feed-empty-state` por desenho. No teste de rolagem o chip do Brasil não estava na árvore (regiões em
  `LazyVGrid`, abaixo da dobra) e o código caiu em `composer-region-90_countries/algeria`, que não tem fonte `pt`.
  É defeito de instrumento, não de rede: os dois testes passaram a responder idioma e lugar e a selecionar o Brasil
  pelo identificador do catálogo (`composer-region-90_countries/brazil`), após rolar a superfície até o chip existir.
  O teste do orçamento passa a provar a cadeia no registro da própria app (`runtime.sqlite` da execução):
  `languages` contém `pt`, `topicPreferences["topic:90_countries/brazil"] == more`, `acquisition_targets > 0` e
  `acquisition_target_sources > 0` — **antes** de exigir publicação.
  **Escopo do que isso valida:** a correção dos instrumentos com um perfil explícito (idioma + Brasil) não valida o
  produto sob um perfil arbitrário do catálogo real — por exemplo, o primeiro país da lista, ou um perfil vazio.
  Aquilo que os dois testes medem é a cadeia com uma resposta explícita; a robustez do produto para qualquer perfil
  do catálogo publicado continua sem medição própria.
- **Defeito de produto encontrado por esse caminho (corrigido em 2026-10-20):** "Mostrar sugestões do FeedMine" na
  página de preferências não valia para a sessão corrente. O "esconder" no feed grava pelo composition
  (`setEditorialTipsHidden`), que guarda um snapshot de `ReaderSettings` para o caminho de render por card; a
  preferência reabilitava pelo backend da página (`ReaderSettingsBackendAdapter.update`), que escrevia só no banco.
  `FeedMineApp.swift:939` combina `editorialTipsHidden || composition.editorialTipsHidden`, então o snapshot
  obsoleto (`true`) fazia `EditorialInvitationCadence.decision` devolver `.hidden` para todo card até o próximo
  lançamento — nenhuma oferta voltava, independentemente da distância lida. O conserto é no caminho de escrita: o
  adapter avisa o composition com o valor **armazenado** (`ReaderSettingsCoordinator.swift`), e o composition
  atualiza o snapshot e limpa o cache de respostas por assunto (`AppComposition.makeReaderSettingsStore`). O teste
  determinístico `CompositionTests.testASettingsWriteThroughTheSurfaceReachesWhatTheFeedReads` falha sem o aviso
  (2 asserções) e passa com ele.
- Chrome do Safari (3 testes): o controle pertence ao `SafariViewService`; a árvore do app não o expõe nesta
  máquina. Reproduzido no HEAD, logo é ambiente/plataforma.
- `testReopenMeasurement…`: falha anterior ao WIP e à correção; permanece aberta com a causa não isolada.

## Execuções direcionadas depois das correções

- 4 testes de `CompositionTests`: **PASS** (21,9 s).
- `testU2SavedListAndInAppReaderPreserveTheSession`: **PASS** (28,8 s).

## Resultado final da suíte (`run-final3.log`, diff `9de88262`)

Terceira execução completa, agora com o instrumento de cold start isolado da descoberta: **`FeedMineAppTests` —
151 testes, 0 falhas**; **`FeedMineUITests` — 75 testes, 9 skips, 11 asserções falhas em 5 testes**. O
`testReopenMeasurementColdAndWarm…` **passou** (cold 1.188 ms, warm 884 ms); restam apenas os dois testes de
catálogo real e os três de site. O bundle `FeedMineAppTests` foi reexecutado depois, com os testes de paginação do
host, `.saved`/`.content` e abertura de resultado: **156/0** (`run-final7-apptests`), no mesmo produto; o bundle de
UI não mudou desde `run-final3`.

| Teste | Falhas | Estado |
|---|---|---|
| `EditorialOfferBudgetUITests.testTheOfferBudgetHoldsOnTheRealCatalogue` | 4 | **Instrumento** (classificação corrigida em 2026-10-20): o teste nunca respondeu o composer, o perfil persistido ficou vazio e a app mostrou `feed-empty-state` — não era "perfil Brasil sem cartas". Com o composer respondido (idioma + Brasil) e a cadeia provada em `runtime.sqlite`, o teste expôs um **defeito de produto** (reabilitar as sugestões pela página não valia na sessão corrente), corrigido no caminho de escrita das preferências. Reexecução focal: **PASS, 311,8 s**. |
| `FeedMineUITests.testRealCatalogueCardsStayReachableByScrolling` | 3 | **Instrumento**: o chip do Brasil não estava na árvore e o teste caiu em `composer-region-90_countries/algeria` (0 fontes `pt`), não no perfil real Brasil. Agora seleciona `composer-region-90_countries/brazil` por rolagem, sem fallback. Reexecução focal: **PASS, 36,9 s**. |
| `ReadingSurfaceUITests.testACardWithoutTextOpensTheSite` | 1 | **BLOCKED (plataforma)**: chrome do `SafariViewService` ausente — reproduzido no HEAD |
| `ReadingSurfaceUITests.testATeaserOpensTheSiteWithNoIntermediateScreen` | 1 | idem |
| `ReadingSurfaceUITests.testOpeningTheSiteFromTheLocalReader…` | 2 | idem |

Todo o resto passou: 47 testes em `FeedMineUITests` (U2 incluído), `CompositionTests` inteiro nos 151 de `FeedMineAppTests`, `ArticleReadingDiagnosis` (com 1 skip justificado), `CardImageJourney`, `EndOfContent`, `FluidityJourney`, `ReadingSurface` (4 falhas de site acima), `AddFeed`, `CatalogueUpdate`, `BackgroundRefresh`.

Reexecução focal de 2026-10-20 (bundle `/private/tmp/fm-ui-fix-20261020T004756.xcresult`, comando no cabeçalho com `-resultBundlePath`): os dois testes de catálogo real **PASS** — orçamento em 311,8 s e rolagem em 36,9 s. A linha do registro da app no primeiro é
`PROFILE_PERSISTED languages=["pt"] place=topic:90_countries/brazil=more acquisition_targets=120 eligible_sources=120`;
o segundo imprime `BRAZIL_SELECTED identifier=composer-region-90_countries/brazil selected=true`.

**Reopen (medido e classificado):** a falha anterior não era produto nem "feed ausente". O registro dizia
`wait_passes=79 kind=launch-progress … cards=0` por 389 s, com `feed-loading-surface` e "Não foi possível conectar.
Não conseguimos buscar novas histórias agora." A segunda abertura respondia idioma/lugar, então o perfil de
descoberta apontava para fontes reais do catálogo; `LOCAL_FEEDS` cobre apenas os dev feeds e `BLOCK_RSS_NETWORK`
derruba o resto — **a fixture não cobria o perfil respondido**. Com o instrumento desligando a descoberta nas duas
aberturas medidas (`FEEDMINE_DISABLE_DISCOVERY=1`), a medição existe e o teste **passa**: cold 1.188 ms / warm
884 ms, 85 cartas. A variante com perfil de descoberta + transporte bloqueado continua sendo o stall medido
(`cards=0`, 389 s) — condições diferentes, não equivalentes.
