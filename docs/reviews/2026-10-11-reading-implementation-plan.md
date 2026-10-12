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

## Arquivos compartilhados que esta frente toca

Coordenação no canal antes de editar (o handoff determina que edição concorrente não é liberada sozinha):

- `Sources/FeedMineUI/Reader/` (superfície nova)
- `Sources/FeedMineComposition/` (resolução do alvo de leitura do cartão)
- `FeedMineApp/FeedMineApp/FeedMineApp.swift` (pilha de apresentação)
- `FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj` (registro dos arquivos novos)

## Fora do escopo (declarado)

Buscar e extrair o texto integral do artigo, cache próprio de artigo, segunda arquitetura de conteúdo, e qualquer
aquisição disparada pela leitura.
