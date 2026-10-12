# Inventário da integração — o que é desta frente e o que veio antes (2026-10-12)

Ordem do arquiteto: "discriminar no inventário o trabalho anterior e as mudanças desta frente". Isto é para o
revisor do PR #3 (`integration/main-into-app-line`), que tem **189 arquivos** e não pode ser lido como se tudo fosse
de uma sessão.

## Por que o PR é grande

A linha do app estava **60+ commits atrás** do `main` e carregava trabalho **não commitado de sessões anteriores**
(77 arquivos modificados e ~80 caminhos novos, medidos no início desta frente). Para publicar uma versão no
TestFlight — ordem do usuário — a árvore precisava ser **reproduzível a partir de um commit**: o script de release
recusa árvore suja, e um binário que mapeia para nenhum SHA não serve como evidência. Então o commit de release
(`ba0866da`) incorporou a árvore inteira. **Nada foi reescrito para caber no PR**, e isto discrimina as partes.

## Desta frente (autoria OMP, 2026-10-12)

**Novos**

|Arquivo|O que é|
|---|---|
|`Sources/FeedMineUI/Reader/FeedReadingDecision.swift`|a regra de onde se lê (corpo > resumo ≥3.000 > site) e o valor do que a leitura local mostra|
|`Sources/FeedMineUI/Reader/FeedReadingSurface.swift`|a superfície de leitura local|
|`FeedMineApp/FeedMineAppTests/ArticleReadingDiagnosisUITests.swift`|o diagnóstico (instrumento, sem tocar no produto)|
|`FeedMineApp/FeedMineAppTests/ReadingCompositionTests.swift`|provas em processo da leitura local|
|`FeedMineApp/FeedMineAppTests/ReadingSurfaceUITests.swift`|aceitação da leitura no aparelho/Simulador|
|`docs/reviews/2026-10-1*.md`|plano, diagnóstico, proposta, decisão, evidência, parecer, roteiro offline, desenho do K-15|

**Modificados por esta frente (e o que exatamente)**

|Arquivo|Mudança desta frente|
|---|---|
|`FeedMineApp/FeedMineApp/AppComposition.swift`|`onReading`/`readingTarget` (o toque resolve onde se lê) e a **ligação K-01/K-05** (a raiz autoriza as origens não públicas que a execução busca; Release, zero)|
|`FeedMineApp/FeedMineApp/FeedMineApp.swift`|`ReaderPage` com dois casos (site/local), `readerBody`, o closure `editorialInvitation` e o `presented` do K06-2 (ausência devolve `nil`)|
|`FeedMineApp/FeedMineApp/TrustedFeeds.swift`|aditivo: variantes de texto na fixture (`FEEDMINE_FIXTURE_TEXT`) e o feed JSON no `DevelopmentLocalFeeds`|
|`FeedMineApp/FeedMineAppTests/CompositionTests.swift`|o transporte controlado passa a registrar requisições e servir a forma pedida; e os testes desta frente (par da ligação, três gêmeos do ida-e-volta, ajuste do S5)|
|`FeedMineApp/FeedMineAppTests/EditorialOfferBudgetUITests.swift`|a nota de instrumento do K06-2 (o braço que a geometria não mede)|
|`FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj`|registro de três arquivos de teste|
|`FeedMineApp/FeedMineApp/Info.plist`|número de build (27 → 29)|
|`.gitignore`|artefatos do bench (corridas, corpus gerado, device) e `__pycache__`|

## Trabalho anterior (não desta frente)

Todo o resto dos 189 arquivos: `Sources/FeedMine*` (composição, persistência, runtime, sindicação, editorial),
`Tests/FeedMine*`, `bench/`, `docs/v1-study/`, `docs/product/`, `scripts/`, `FeedMineApp` (a maior parte) e
`README.md`/`CATALOG.md`. **Eu não sou o autor** e não reescrevi nada disso: commitei a árvore como estava para que a
build publicada mapeasse para um SHA. Duas exceções que eu **toquei** nesses arquivos, ambas aditivas e nomeadas
acima: os fixtures em `TrustedFeeds.swift` e o transporte em `CompositionTests.swift`.

## Como verificar esta discriminação

- `git show --stat 8274d0c7` (o commit de release): o que eu adicionei nesta frente está nos caminhos acima;
- `git log --format='%h %s' -12 integration/main-into-app-line`: a série de commits **assinados por esta frente**
  (`fix(acquisition)`, `fix(feed/leitura)`, `test(feed)`, `docs(kiro)`, `merge:`), cada um com o seu escopo;
- os documentos `docs/reviews/kiro-2026-10-11/*` são do **Kiro** (revisão), e `k06_review_response.md` é desta
  frente.
