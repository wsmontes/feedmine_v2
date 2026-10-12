# Leitura de artigo — diagnóstico medido (2026-10-11)

**Ordem que originou este documento (arquiteto, canal do Codex):** "Próxima prioridade de UX: leitura de um artigo
real. Faça diagnóstico, sem alterar código: abra artigos reais de tipos distintos; observe transição, retorno ao
feed e preservação da posição; provoque link indisponível e falha de conexão; avalie fonte, título, ações e
acessibilidade; **leve ao PO uma proposta para a experiência de leitura**." E o método, na resposta seguinte:
"**Mantenha a instrumentação isolada do produto e traga os fatos antes da proposta ao PO.**"

**Instrumentação:** `FeedMineApp/FeedMineAppTests/ArticleReadingDiagnosisUITests.swift`, no alvo de testes
`FeedMineUITests`. **Zero mudança no produto** — nenhum arquivo de `Sources/` ou do app foi tocado; o teste
observa, mede e anexa capturas.

## 1. O que acontece quando o leitor abre um artigo (medido, no aparelho físico)

Namespace real de aceitação (`3E1B4C1A-…`, 173 cartões publicados). Cartão ancorado: `892695AB-…`, "Вечность во
взгляде. 2021 год" (35photo.ru) — um cartão **visível**, dentro do viewport.

|Evento|Medido|
|---|---|
|Toque na manchete → superfície do leitor|**0,07 s** (sondado a cada 0,2 s, não é espera do teste)|
|Superfície apresentada|`SFSafariViewController`: `Close`, `URL`/'Address', `PageFormatOptions`, `StopButton`|
|Endereço carregado|`35photo.ru` — a **URL real** da fonte|
|Fechar → feed de volta|**0,12 s**|
|Posição ao voltar|**mesmo cartão, delta 0,0 pt**; o cartão no topo continua sendo o mesmo|
|Estado de leitura do produto|`edition_reading_state.high_water_card_id` **inalterado** (mesmo id; `generation` 92→93)|

Conclusão factual: **a transição e a volta estão boas**. Abre instantaneamente, fecha instantaneamente e devolve o
leitor exatamente onde estava — confirmado em dois níveis, a posição em pixels do cartão ancorado (delta 0,0 pt) e
o próprio marcador do produto (`high_water_card_id`).

## 2. O que o leitor vê dentro do artigo

- A superfície é do **Safari**, não do app: barra com `Close`, o endereço, "Format Options" e "Reload"/"Stop".
- **Idioma — medido e corrigido:** o app é localizado (`en.lproj` + `pt-BR.lproj`) e segue o idioma do aparelho;
  este aparelho está em inglês, então app e leitor aparecem em inglês, coerentemente. A primeira versão deste
  documento afirmou "chrome em inglês num app em português" — **era falso** e está corrigido aqui.
- O conteúdo do artigo traz o chrome do site (na página real medida antes, o Substack mostrou `Subscribe`,
  `Sign in` e o rodapé do blog): quem define tipografia, controles e o que aparece é o site, não o app.
- A acessibilidade do conteúdo vem do próprio site: o texto e os controles da página aparecem na árvore
  (`StaticText`/`Button`), mas quem os define é o site, não o app.

## 3. O que o cartão oferece hoje (árvore de acessibilidade, medida)

- O cartão é um `Other` com identificador **UUID** (`892695AB-…`), com a imagem `Placeholder-Article` (a mídia do
  cartão ainda é o marcador — frente própria, não é defeito desta frente).
- O controle que **abre** o artigo é um `Button` **sem identificador**, cujo rótulo é a manchete composta:
  "Вечность во взгляде. 2021 год, Nikolay Smolyak publish photo, 5 hours ago" (título + fonte + idade).
- O botão de favorito é `card.bookmark`, com valor `bookmarked`/`not bookmarked` — e vem **antes** do controle de
  abrir na ordem da árvore.
- Consequência de acessibilidade: quem lê a tela pelo botão de abrir ouve título, fonte e idade juntos; é bom. Mas
  o botão de abrir **não tem identificador** — só o de favorito tem.

## 4. O que acontece quando o artigo não pode ser buscado

Fonte do caso: o próprio feed de fixture do app (`FEEDMINE_ADD_FEED_FIXTURE=1`), cujos itens apontam para
`https://site.feedmine.test/story-N` — e o `URLProtocol` da fixture responde apenas `/`, `/feed.xml` e `/alt-site/`
(`TrustedFeeds.swift:190-193`), então o nome **não resolve**. É "link indisponível" de verdade, com o web view
real, e não um link sintético inventado pelo teste.

Medido (3 cartões de fixture publicados, o primeiro aberto):

|Evento|Medido|
|---|---|
|Superfície aparece|**0,10 s** — mesmo com o endereço sem destino|
|Endereço na barra|`site.feedmine.test`|
|Área da página|`Can't Open Page` — **"Safari can't open the page because the server can't be found."**|
|Barra inferior|`Back` e `Forward` **desabilitados**, `Share`, **`Open in Safari`**|
|Volta ao feed|mesmo cartão, **delta 0,0 pt**|

O que isso diz do produto: **a falha é narrada pelo Safari, não pelo FeedMine** — a frase que o leitor lê é do
Safari; o app não oferece recuperação nenhuma (nem "tentar de novo", nem "este artigo está guardado aqui", que é
exatamente o que ele poderia dizer quando tem o texto — ver §5).

## 5. O que o app já guarda do artigo (medido no banco real do aparelho)

`runtime.sqlite` do namespace de aceitação, puxado do aparelho (`devicectl device copy from`):

|Medida|Valor|
|---|---|
|Revisões de conteúdo|3.403|
|Com **corpo** (`body_text` não vazio)|**0**|
|Com resumo (`summary`)|3.139|
|Resumo: tamanho médio|681 caracteres|
|Resumo: maior|51.122 caracteres|
|Cartões publicados|173|

Distribuição do resumo nas 3.403 revisões: 1.375 com ≤200 caracteres, 1.351 com 201–800, 279 com 801–3.000,
**134 com 3.000+**, 264 sem resumo.

Nos **173 cartões publicados**: 74 com ≤200, 37 com 201–800, 12 com 801–3.000, **22 com 3.000+**, 28 sem resumo —
ou seja **34 cartões (20%) já carregam texto suficiente para uma leitura dentro do app**, e mais 49 carregam ao
menos um parágrafo.

O que o produto guarda por edição: `edition_reading_state(edition_id, high_water_card_id, visible, generation)` —
a posição é **o cartão no topo**, não um deslocamento em pixels.

## 6. Onde isso vive no código

|Peça|Arquivo:linha|Fato|
|---|---|---|
|O leitor|`FeedMineApp/FeedMineApp/InAppBrowser.swift:18-21`|`SFSafariViewController(url:configuration:)`, com `preferredControlTintColor` do app|
|O que o leitor é|`FeedMineApp/FeedMineApp/FeedMineApp.swift:46`|`ReaderPage` é `{ let url: URL }` — "no storage handle, and no URL ever crosses back"|
|Quem abre|`Sources/FeedMineUI/Cards/FeedItemCardView.swift:98` vs `:324`|`Button { emit(.open) }` (sem identificador) e `Button { emit(.save) }` (`card.bookmark`)|
|O que é guardado|`Sources/FeedMineDomain/Content.swift:118-119`|`summary: String?`, `bodyText: String?`|
|De onde vem o corpo|`Sources/FeedMineSyndication/SyndicationTranslator.swift:139`|`body: item.contentText` — o corpo só existe quando o feed o publica|
|Busca em texto|`Sources/FeedMinePersistence/CatalogCompiler.swift:541`|tabela **FTS5** sobre o conteúdo guardado|

## 7. Correções que este diagnóstico fez em si mesmo

Nada aqui vale sem isto: a primeira passada mediu três coisas erradas e este documento é a correção.

1. **"Tempo de transição" era um `sleep` do teste** (6,4 s), não a latência do leitor. Agora é sondado: **0,07 s**.
2. **O caso "offline" não estava offline**: `FEEDMINE_BLOCK_RSS_NETWORK` bloqueia o transporte **RSS do app**, não
   a rede do web view — a página veio do cache e as duas árvores (online e "offline") saíram idênticas. Substituído
   pela fixture com nome que não resolve (§4).
3. **A âncora vinha da árvore inteira**, incluindo cartões fora do viewport; a primeira medição de "posição ao
   voltar" (−1243,9 → 653,3 pt) media um toque que o leitor não fez. Com âncora visível: **delta 0,0 pt**.
4. Efeito colateral honesto: `card.buttons.firstMatch` é o botão de **favorito** (vem primeiro na árvore). A
   primeira passada marcou um cartão em vez de abrir o artigo. O cartão foi **desmarcado pela superfície do próprio
   app** e o banco confirma `reader_bookmark_memberships = 0` — o namespace está como foi encontrado.
