# Ver fonte — lista interna de conteúdo, não visita ao site

Data: 2026-10-17 (America/Vancouver).
Status: definição explicitamente reafirmada pelo dono e revisão estática autorizada para commit. Apenas documentação, sem alteração no app ou certificação de execução.
Base V2 inspecionada: `fd56930bec6d1eca19a81d8ac4a73705da26b3f9`.

## Definição do dono

**"Ver fonte" significa ver a lista de conteúdos daquela fonte dentro do Feedmine. Não significa visitar o site.**

São ações diferentes:

- Tocar no card abre a história/artigo correspondente pelo caminho de leitura vigente.
- Escolher **Ver fonte** abre a experiência interna da fonte e suas publicações.
- **Abrir site da fonte**, quando oferecido, abre o endereço externo de forma explícita. Não pode substituir silenciosamente Ver fonte.

## Contratos já existentes

Não criar outra especificação concorrente. Reutilizar:

- `docs/product/F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md`: origem inequívoca, exploração da fonte, escolha de assinatura opcional e retorno protegido; UX12-B exige somente memberships legítimas da fonte.
- `docs/product/F14_READER_LINK_NAVIGATION_UX_PRD.md`: destino correto e retorno ao mesmo card/contexto.
- `docs/product/V1_GOLD_IMPLEMENTATION_BRIEFS_2026-10-10.md`, S1, e `docs/v1-study/V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md`, G01: visita explícita com história local, sem ativação automática da fonte.
- V1 `editorial/feed-curation/source-experience.md`: visita pode atualizar fonte desativada/dormente e combinar resposta atual com histórico local; isso não é assinatura nem promessa de arquivo integral do site.
- Invariantes de publicação imutável, observação passiva e prontidão anterior à admissão, incluindo as diretrizes do dono publicadas em 17/out.

## Divergência atual identificada por código

V2 `FeedMineApp/FeedMineApp/AppComposition.swift`:

1. `FeedAssociation.perform`, ramo `action == .viewSource` (~1816–1827), resolve `sourcePage(for:)` e chama `present(url, cardID)`.
2. `sourcePage(for:)` (~1851–1860) lê a ocorrência publicada, procura a fonte em `feeds`, consulta o catálogo e devolve `record.siteURL`.
3. `present` (~1995–1998) encaminha o URL a `onExternalURL`. Esse caminho abre o site, não constrói uma lista interna da fonte.
4. A infraestrutura de contextos não resolve automaticamente a visita independente: `AppComposition.selectContext` (~634) recusa `.source` fora de `feeds`; `sessionState` (~882) reconcilia `.source` ausente do conjunto ativo para `.main`. Fonte selecionada e fonte explicitamente visitada não podem ser confundidas.

Isso é leitura do caminho executável, não reprodução de UI nesta sessão. Uma futura mudança de linhas/implementação exige revalidação dos símbolos contra o HEAD.

## Referência V1 e limites

V1 `feedmine/Views/FeedScreen.swift` apresenta `SourceFeedView` em folha independente. A implementação está em `feedmine/Views/CollectionManagementView.swift` (~337).

V1 `feedmine/Services/FeedStore.swift`, `loadSourceContent` (~7050), registra acesso explícito, resolve e busca a fonte, persiste itens retornados e relê história local; não habilita a fonte automaticamente nesse caminho. Isso sustenta a distinção comportamental visitar/assinar.

Não copiar a implementação inteira: `SourceFeedView.load` (~493) entrega o array completo de itens depois de `buildPresentations`; essa função prepara apresentações apenas para os primeiros 20 itens e dispara a preparação restante numa tarefa separada cujo resultado não é incorporado ali. Portanto, a V1 também não é prova de prontidão da lista completa. Recuperar seu comportamento de navegação, sem transportar essa lacuna, quotas, I/O na view ou segundo pipeline.

## Comportamento requerido

- Abrir uma fonte por card, catálogo, busca ou coleção deve resolver sua identidade correta e mostrar conteúdo dela, sem contaminação por outras fontes e sem redirecionamento silencioso ao feed principal.
- A visita não exige assinatura/habilitação nem altera a seleção automática. Fontes importadas e fontes descobertas também precisam de resolução legítima, sem depender exclusivamente de `siteURL` do catálogo.
- Aproveitar história local válida e permitir aquisição explícita pelo owner existente, inclusive para fonte desativada/dormente. Falha de conexão conserva o conteúdo local e informa o limite, sem apresentar falso vazio.
- Apresentar somente cards preparados: arquivo local e slot reservado não substituem imagem pronta para desenho. A preparação futura não modifica ocorrências já publicadas.
- "Conteúdo da fonte" significa itens expostos pelo endpoint e história retida localmente, não arquivo universal do site. Explicar o limite quando relevante; link para o site é uma ação complementar.
- Voltar recupera o feed principal, mesma edição/contexto, card e posição; trabalho da visita não substitui a composição que o leitor deixou.
- Usar os responsáveis existentes de identidade, aquisição, preparação, publicação e checkpoints. Uma experiência de navegação independente não autoriza um runtime paralelo.

## Verificação de implementação

O requisito já está definido; as provas devem verificar sua realização:

1. Ver fonte de um card abre lista interna da fonte; abrir artigo e abrir site continuam destinos distintos.
2. Fonte visitada tem histórico local, conteúdo remoto novo ou nenhum conteúdo, com estados honestos nos três casos, inclusive offline.
3. Fonte desativada permanece desativada após visita e nova abertura do app; nenhuma assinatura é criada implicitamente.
4. Fonte descoberta/importada não selecionada pode ser visitada sem se passar por outra fonte ou voltar silenciosamente ao main.
5. Nenhum card incompleto entra na apresentação da lista; mídia tardia não altera o que já foi publicado.
6. Retorno preserva leitura e resultados atrasados da visita não se instalam no contexto principal.

Não alterar benchmarks congelados para obter aprovação. Este commit não implementa a correção nem afirma testes executados no Mac/iPhone.
