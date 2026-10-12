# Leitura local — evidência da implementação (2026-10-11)

Ordem: o arquiteto aprovou o desenho ("leitura local do conteúdo armazenado, com fonte, título, data e acesso ao
site, usando os componentes e a persistência existentes") e autorizou a implementação após registrar o plano e
coordenar os arquivos compartilhados. Plano: `2026-10-11-reading-implementation-plan.md`. Decisão do PO:
`2026-10-11-reading-decision.md` (A+B aprovada, extração integral fora do escopo).

## O que foi implementado

|Peça|Onde|
|---|---|
|A regra de onde se lê|`Sources/FeedMineUI/Reader/FeedReadingDecision.swift` — corpo > resumo ≥3.000 caracteres > site; nada quando não há texto nem endereço|
|A superfície de leitura|`Sources/FeedMineUI/Reader/FeedReadingSurface.swift` — fonte, manchete, data, rótulo de origem, nota de parcial, texto com Dynamic Type e seleção, "Abrir no site" no cabeçalho e no fim, fechar|
|O roteamento|`AppComposition.read`/`readingTarget` — resolve o alvo lendo o store; `onReading` (decisão do app) separado de `onExternalURL` (pedido **explícito** ao site)|
|A apresentação|`FeedMineApp.ReaderPage` com dois casos (`.site` / `.local`), a mesma pilha e o mesmo retorno|

Nenhuma linha toca aquisição, extração ou cache: a leitura é `PublicationStore.card(id:)` +
`ContentStore.originRevision(id:)` e mais nada.

## Verificação exigida pelo arquiteto, com o que foi medido

|Exigência|Prova executada|Resultado|
|---|---|---|
|Fixtures: corpo, resumo longo, resumo curto, ausência de texto|`ReadingCompositionTests` (4 provas em processo) + `ReadingSurfaceUITests` (7 no aparelho)|**verde**|
|Metadados corretos (fonte, título, data)|`reading.source` = "BBC …", `reading.headline` = "BBC … story N", `reading.date` presente — lidos da árvore de acessibilidade|**verde**|
|Nenhuma aquisição causada pelo leitor|por leitura: **zero** requisições no transporte controlado, **nada** publicado/substituído na janela, resposta idêntica na repetição|**verde**|
|Fonte Grande|`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`; o texto do artigo ocupa mais altura (medido, > 400 pt)|**verde**|
|Conectividade realmente indisponível|`FEEDMINE_BLOCK_RSS_NETWORK=1`: o app instala o proxy HTTPS fechado que um teste existente prova recusar conexões reais (erro 310) — e o texto local continua legível|**verde**|
|Diferir pedido explícito ao site do trabalho autônomo do feed|`onExternalURL` só é chamado por ação explícita e pela superfície; o caminho de decisão (`onReading`) é outro, e o teste prova zero requisições nele|**verde**|
|Repetir a validação de posição na superfície nova|cartão ancorado antes/depois de abrir e fechar o leitor local: **delta 0,0 pt**, mesmo cartão|**verde**|
|"Abrir no site" no cabeçalho e no fim, sem duplicar texto|`reading.open-site` **e** `reading.open-site-footer` presentes; o texto aparece uma vez|**verde**|

Números: `swift test --filter FeedReadingDecision` **7/7**; `ReadingCompositionTests` **4/4**;
`ReadingSurfaceUITests` **7/7 em 62 s**.

## Testes que já existiam: o que eu quebrei, o que já estava quebrado

Rodar o alvo `FeedMineAppTests` inteiro (76 testes) acusou **3 falhas**. Investiguei uma a uma, com medição:

|Teste|Com a minha alteração|Revertendo só as minhas edições de fixture|Veredito|
|---|---|---|---|
|`AddFeedTests.testAddingAFeedByLinkDiscoversStoresAndAcquiresIt`|**falhava**|**passava**|**era meu**|
|`CompositionTests.testASavedBoxExportsItsSavedArticlesAndNotTheirSources`|falhava|falhava|pré-existente nesta árvore|
|`CompositionTests.testS5OfflineReopenRestoresEditionWithFreshProvenance`|falhava|falhava|pré-existente nesta árvore|

**Correção (não remendo):** a maquinaria de formas de texto não pertence ao `AddFeedFixtureSite` — os testes de UI
passaram a usar o caminho de fixtures locais (`FEEDMINE_LOCAL_FEEDS`), que não tem passo de adicionar feed. Então
`AddFeedFixtureSite` voltou **byte a byte** ao que era (nenhuma linha minha) e as formas agora têm **uma dona só**:
`DevelopmentLocalFeeds`, ao lado do `jsonDocument` que serve o caso "corpo". Depois disso:

- `AddFeedTests` **9/9**; `ReadingCompositionTests` **4/4**; `ReadingSurfaceUITests` **7/7** (exit 0).
- As duas falhas de `CompositionTests` continuam, **nos dois casos** — não são desta frente. Registro aqui para que o
  arquiteto saiba que esta árvore de trabalho (com 321 linhas não commitadas em `TrustedFeeds.swift` e 565 em
  `CompositionTests.swift`, de sessões anteriores) tem falhas próprias, e que **não** são consequência da leitura.

**Rodada completa do alvo, depois da correção (ordem do arquiteto: "execute novamente o alvo completo para
confirmar que só elas permanecem"):** `FeedMineAppTests` — **76 testes, 2 falhas, 0 inesperadas** (115 s). As duas
são exatamente as pré-existentes acima; `AddFeedTests` **9/9** e `ReadingCompositionTests` **4/4** dentro da mesma
rodada. Confirmação medida, não argumentada.

## Alcance no catálogo real (medido no aparelho)

Dos **173 cartões publicados** no namespace real de aceitação, **22** têm 3.000+ caracteres guardados — quase todos
do **A List Apart**, que publica o artigo inteiro no RSS (21.629 a 31.629 caracteres por item), e alguns do *All
Things Linguistic*. Esses artigos passam a ser **legíveis dentro do app, sem rede**.

## Limites declarados (para não induzir conclusão errada)

1. **O ramo RSS da sindicação nunca preenche `body_text`** (`SyndicationTranslator.rss` passa só
   `summary: item.description`) — corpo só existe em JSON Feed. É a explicação medida de `body_text` ser zero em
   todo o catálogo real, e a razão de a fixture de corpo ter de servir um JSON Feed.
2. **Um resumo de 31.629 caracteres é rotulado "Resumo fornecido pela fonte"** — é o que a fonte entregou naquele
   campo. Não há como o app saber se aquilo é o artigo completo, e o desenho aprovado proíbe afirmá-lo.
3. **O bloqueio de rede do app não corta o Safari** (é o transporte do app, não o do sistema). Por isso a prova
   decisiva de "o leitor não busca nada" é a contagem de requisições (zero), não o bloqueio.
4. `body_text` **não** é garantia de completude, como o arquiteto fixou: a superfície diz que o conteúdo é parcial
   sempre que não há garantia de origem — e nunca há.
5. **No tamanho de acessibilidade máximo, o "Abrir no site" do cabeçalho trunca** para "Abrir…" (medido na
   captura `reading-large-text`): a ação continua disponível e a acessibilidade anuncia "Abrir no site", e o
   rodapé continua inteiro. Fica registrado como refinamento, não como defeito: o desenho exige as duas saídas, e
   as duas existem.
6. Capturas de tela da superfície estão anexadas ao resultado de `ReadingSurfaceUITests`
   (`reading-body`, `reading-back-in-the-feed`, `reading-large-text`, `reading-offline`,
   `reading-explicit-site`, `reading-back-to-the-text`).
