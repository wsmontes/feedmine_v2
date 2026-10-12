# Plano — leitura local no FeedMine (aprovado pelo arquiteto, decidido pelo PO)

Origem: decisão do PO (`2026-10-11-reading-decision.md`, A+B aprovada, extração integral **fora do escopo**) e o
desenho aprovado pelo arquiteto em 2026-10-11: "leitura local do conteúdo armazenado, com fonte, título, data e
acesso ao site, **usando os componentes e a persistência existentes**".

## Comportamentos (os quatro do arquiteto)

1. **Corpo armazenado** (`body_text` presente): abre o **leitor local**. A presença de `body_text` **não comprova
   completude** — quando não houver garantia de origem, a superfície diz que o conteúdo é **parcial**.
2. **Resumo substancial**: leitura local, identificada como **"Resumo fornecido pela fonte"**, com **3.000
   caracteres** como parâmetro de abertura — e **sem** associá-lo ao artigo completo.
3. **Resumo curto ou texto ausente**: ação principal **"Ler no site"**, direto no navegador interno, **sem tela
   intermediária**.
4. **No leitor local**: **"Abrir no site" no cabeçalho e ao final**, sem duplicar o texto já mostrado.

## Requisitos da superfície

- Respeita **Dynamic Type** (inclusive fonte Grande) e permite **seleção de texto**.
- Funciona **sem rede**: renderiza só o que já está no store.
- **Renderizar ou abrir o leitor não dispara aquisição, extração nem preenchimento de cache** — invariante de
  produto; a única requisição ao site é a **explícita** ("Ler no site"/"Abrir no site"), separada do trabalho
  autônomo do feed.
- Preserva **a associação, o mesmo card e a posição** ao abrir e fechar. A medição anterior **não vale** para a
  superfície nova: a validação de posição é **repetida** nela.

## Verificação (o que tem de ser executado)

|Prova|Como|
|---|---|
|Fixture com **corpo**, **resumo longo**, **resumo curto** e **ausência de texto**|feed de fixture do app, uma variante para cada caso|
|Metadados corretos (fonte, título, data)|leitura da árvore de acessibilidade da superfície|
|Leitor **não** causa aquisição/extração/cache|contagem de revision/marcações antes e depois de abrir e fechar|
|Fonte **Grande**|lançamento com a preferência de acessibilidade em tamanho grande|
|**Sem rede de verdade**|o conteúdo local continua legível com a rede indisponível|
|Posição preservada na **superfície nova**|medida própria: cartão ancorado + marcador do produto|

## Arquivos realmente tocados (coordenados no canal antes de editar)

|Arquivo|Mudança|
|---|---|
|`Sources/FeedMineUI/Reader/FeedReadingDecision.swift`|**novo** — a regra pura (corpo > resumo ≥3.000 > site; nada quando não há nem texto nem endereço) e o valor do que a leitura local mostra|
|`Sources/FeedMineUI/Reader/FeedReadingSurface.swift`|**novo** — a superfície de leitura local|
|`FeedMineApp/FeedMineApp/AppComposition.swift`|o toque do cartão passa a resolver *onde* se lê; `onReading` separado de `onExternalURL`|
|`FeedMineApp/FeedMineApp/FeedMineApp.swift`|`ReaderPage` com dois casos (site / local) e a apresentação de ambos pela mesma pilha|
|`FeedMineApp/FeedMineApp/TrustedFeeds.swift`|**aditivo** — variantes de texto na fixture do app (`FEEDMINE_FIXTURE_TEXT`) e o feed JSON|
|`FeedMineApp/FeedMineAppTests/CompositionTests.swift`|**aditivo** — o transporte controlado registra as requisições e serve a forma pedida (payload padrão byte-idêntico)|
|`FeedMineApp/FeedMineAppTests/ReadingCompositionTests.swift`|**novo** — as provas em processo|
|`FeedMineApp/FeedMineAppTests/ReadingSurfaceUITests.swift`|**novo** — a aceitação no aparelho|
|`FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj`|registro dos dois arquivos de teste do alvo do app|

Correção ao plano original: `Sources/FeedMineUI/` e `Tests/` entram pelo **glob do SwiftPM** — não precisam de
`pbxproj` (era o único motivo pelo qual ele estava previsto). E `Sources/FeedMineComposition/` **não** foi tocado: a
resolução do alvo de leitura vive na composição do app, onde o cartão e o store já se encontram.

## Fora do escopo (declarado)

Buscar e extrair o texto integral do artigo, cache próprio de artigo, segunda arquitetura de conteúdo, e qualquer
aquisição disparada pela leitura.
