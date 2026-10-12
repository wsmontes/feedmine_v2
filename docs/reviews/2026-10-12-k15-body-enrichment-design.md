# K-15 — desenho: corpo (RSS/Atom) sem inventar edições nem churn de cards

Encomendado pelo arquiteto: "prepare um desenho para RSS/Atom que trate **proveniência**, **compatibilidade do
fingerprint** e **requisição de itens existentes**. Precisamos distinguir **enriquecimento pelo parser** de **edição
material feita pela fonte**, preservando cards publicados." Sem código: isto é um desenho.

## O que está medido (base do problema)

|Fato|Medida|
|---|---|
|Hoje `bodyText` só é preenchido em **JSON Feed**|`SyndicationTranslator.rss` passa `summary: item.description` e **nenhum** `body`; o ramo Atom idem (`summary: item.summary?.text`)|
|Consequência no catálogo real|**`body_text` vazio em todas as 3.403 revisões** do namespace real; 3.139 têm resumo; 22 dos 173 cards publicados têm 3.000+ caracteres **no resumo** (A List Apart publica o artigo inteiro em `<description>`)|
|O corpo participa da identidade material|`observation(...)` monta `materialVersion` com `materialFingerprint(title:summary:body:link:media:)`|

**Conclusão que governa o desenho:** se passarmos a preencher `body` a partir de `<content:encoded>`/`<content>`,
**toda revisão já admitida ganha uma versão nova** — 3.403 edições espúrias, cada uma republishando um card. Isso
não é um efeito colateral aceitável; é o problema a resolver.

## A distinção que o desenho precisa sustentar

1. **Enriquecimento pelo parser** — os **mesmos bytes** da fonte, lidos melhor (ontem não líamos
   `<content:encoded>`; hoje lemos). O conteúdo declarado não mudou → **não pode** mudar a identidade material.
2. **Edição material feita pela fonte** — a fonte mudou o que publicou. → **deve** gerar versão nova, e o card
   publicado deve refletir a edição (é o comportamento atual, e ele está certo).

Hoje o fingerprint trata os dois casos igual, porque só olha o *valor* dos campos. O desenho tem de olhar também
**de onde o valor veio**.

## Forma recomendada

### 1. Proveniência por campo, não por revisão

Registrar, por revisão, **qual elemento do feed** produziu cada campo de texto:

```
textProvenance: [.headline: .sourceElement("title"),
                 .summary:  .sourceElement("description"),
                 .body:     .sourceElement("content:encoded")   // ou .absent, ou .parserDerived(...)]
```

- `.sourceElement(x)` = a fonte declarou aquele campo naquele elemento.
- `.parserDerived(x)` = nós derivamos (ex.: texto extraído de HTML do `description`) — é **nosso**, não da fonte.
- `.absent` = a fonte não declarou nada ali.

Isso resolve dois problemas de uma vez: o fingerprint (abaixo) e a honestidade que o PO exigiu ("conteúdo parcial
nunca apresentado como completo") — porque o **leitor** pode dizer "texto publicado pela fonte" apenas quando a
proveniência é `sourceElement`, e "conteúdo preparado pelo FeedMine" quando é `parserDerived`.

### 2. Fingerprint material: identidade do que a fonte declarou

**Regra proposta:** o fingerprint material passa a ser calculado sobre **(elemento declarado, valor)** dos campos de
texto, e **não** sobre o valor de `body` isoladamente:

- `content:encoded` presente → o corpo passa a fazer parte do material **como material da fonte**;
- `content:encoded` ausente ontem e presente hoje **com os mesmos bytes de feed** → o fingerprint muda **apenas se
  o elemento declarado mudou**; preencher um campo que a fonte sempre declarou é um **mesmo material** lido melhor →
  **não** gera versão.

Concretamente: a versão material é uma função de `(title, summary, body, link, media)` **junto com** um
`fingerprintGeneration` — o número da régua. Revisões admitidas sob a geração 1 mantêm sua identidade **gravada**
(não recalculada); a geração 2 vale para revisões novas. É o mesmo padrão que a rodada 10 já usou para versionar
comportamento (a versão de política é um contador persistido, não um hash), e evita exatamente a classe de defeito
que a rodada 10 pagou caro para corrigir.

**Compatibilidade:** nada é recalculado para trás. `origin_revisions` mantém o `external_version_identity` que já
tem; a geração só entra no cálculo de **observações novas**.

### 3. Requisição de itens existentes (o backfill) — explícita, limitada e sem republish

Não existe documento cru guardado: para enriquecer 3.403 revisões é preciso **buscar de novo** o feed. Logo:

- O backfill é uma **aquisição deliberada** (uma frente própria, com seu próprio orçamento e sua própria
  cadência), **nunca** um efeito de renderizar ou de abrir o leitor — a invariante que a frente de leitura acabou de
  provar (zero requisições ao abrir o leitor) continua valendo.
- Ele **grava corpo como enriquecimento**, chaveado por `(revision, campo)`, **sem** tocar `external_version_identity`
  e **sem** criar `published_cards` novos. Card publicado é sagrado: nenhum card novo, nenhuma reordenação, nenhuma
  mudança de edição.
- É **retomável e limitado**: por feed, por lote, com registro do que já foi tentado (sucesso, ausência de corpo,
  falha), para não repetir 3.403 buscas a cada boot.
- Respeita o que já existe: `NetworkHostPolicy`/K-01 (nenhum host privado por padrão), o teto de redirect, e o
  `bodyByteCapacity`.

### 4. O que **não** fazer

- Preencher `body` a partir de `<description>` quando `<content:encoded>` não existe: isso transformaria o resumo
  (que já é lido como resumo) em "corpo", e o leitor passaria a rotular como texto da fonte algo que é resumo dela.
  A lista real dos 22 cards mostra por que a distinção importa: o A List Apart põe o artigo inteiro no
  `description` — é `sourceElement("description")`, e continua sendo rotulado como resumo, como o arquiteto fixou.
- Recalcular fingerprint de linha gravada.
- Enriquecer durante a publicação normal (o parser só registra o que veio; a busca do corpo é a frente do backfill).

## Verificação que este desenho exige (antes de codar)

|Prova|Como|
|---|---|
|Enriquecer **não** cria versão nova|admitir com `<content:encoded>` ausente, enriquecer, e afirmar que `external_version_identity` da revisão não muda e que nenhum `published_cards` novo aparece|
|Edição material **cria** versão nova|os mesmos bytes com `<content:encoded>` **alterado** (e sem `updated`) → versão nova, e o card reflete|
|Proveniência alimenta o rótulo do leitor|um corpo `sourceElement` aparece como "Texto publicado pela fonte"; um `parserDerived` **não**|
|Backfill é limitado e retomável|interromper no meio e retomar: cada feed tentado uma vez, nenhuma republicação|
|Compatibilidade|uma base com revisões da geração 1 continua legível e as identidades gravadas continuam válidas|

## Custos e risco residual

- A regra 2 tem um limite honesto: uma edição da fonte **que só mude o corpo e não toque em `updated`/`date_modified`**
  deixa de ser detectada como edição. É o preço de não confundir enriquecimento com edição — e é mitigável olhando
  `content:encoded` *declarado* (mudança de valor com elemento declarado nos dois lados ainda é edição).
- O backfill gasta rede em nome do leitor: precisa de orçamento explícito e de visibilidade (o mesmo tipo de
  contabilidade que a rodada 10 fez para as ofertas editoriais).
