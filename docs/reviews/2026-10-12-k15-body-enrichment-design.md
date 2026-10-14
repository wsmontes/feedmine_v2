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


## K-15 implementation — 2026-10-14

Fingerprint policy migration \`content-fingerprint-generation-v2\` persists generation
2 in \`content_fingerprint_policy\` and labels all preexisting immutable
\`origin_revisions\` generation 1 with an additive DEFAULT 1 column. Existing
\`external_version_identity\` values remain byte-exact. For RSS and Atom,
new observations are generation 2; Atom carries both the generation-2 identity and
the exact legacy generation-1 identity to reconcile already admitted versions.
JSON Feed remains generation 1 because its projection was already complete.

The first new parser observation of a generation-1 revision whose original
title/summary/attribution/metadata/media still match is recorded as an
\`origin_revision_body_enrichment\` (revision ID, source element, readable body).
This is a separately keyed, immutable baseline and does not update the prior
\`origin_revisions\` body or version, current revision, published cards or edition.
Repeated identical acquisition is idempotent. A generation-2 observation with
no declared body also records an explicit `absent` baseline (nullable body); if the
publisher later adds that element, it is a material edit rather than a first parser
enrichment. When the source later changes the body relative to either baseline,
the normal admission path inserts a generation-2 revision. A changed headline, summary or media follows the existing revision path.

Provenance is stored as the declaring source element (\`content:encoded\` or
\`content\`), while plain text is derived with the common Domain tokenizer.
The old reader does not claim to have a complete copy before the enrichment is
available. No background backfill runner was added; ordinary bounded acquisition
may enrich data it encounters. Exhaustive historical reacquisition, with budgets
and resumable progress, remains distinct release work, not a side effect of UI.

Risk limit: an unchanged historical XML body cannot be distinguished from
a body edit made before its first generation-2 observation. Therefore the first
observed body is baselined, not treated as an edit; subsequent changes are
detectable. That is the information-theoretic limit of not storing original XML.

Estimated raw storage if 3,403 entries each carry 5–20 KiB of readable text:
17–68 MiB, before SQLite page/index overhead. This is not a corpus measurement.


## K-15 follow-up — publisher identity and local reading (2026-10-14)

- **Material occurrence identity:** `MaterialContentIdentity.key` retains the exact historic
  three-component key for legacy revisions whose body has not been reobserved.
  Generation-2 observations (including absence) and generation-1 revisions with
  an observed enrichment baseline add an explicit body-state component. The same calculation
  is used by `CandidateProvider` / `SelectionExposureSnapshot`, both
  `PublicationStore` material queries (exposure and hidden-tail history), and
  the append guard. A title/summary/media-identical publisher edit to a
  declared body can now produce a new occurrence only under an Edition policy
  that already allows `.whenMaterialChanged`, and never if an old occurrence
  remains ahead of the reader. Existing published payloads, actions, layout,
  order and persisted version identities are unchanged. Comparison keys are
  derived from the currently known provenance without rewriting history.
  Bounded candidate queries project only declared or enriched material.
- **Reader projection:** `ContentStore.originRevision(id:)` overlays the separate
  immutable enrichment's body only for public reading when the canonical revision
  has no body. Admission/version-conflict logic still uses private canonical reads;
  the old `origin_revisions` row is never updated. The existing
  `FeedAssociation.readingTarget` then presents `.sourceBody` with its existing
  label "Texto publicado pela fonte", marks it partial, and preserves the
  publisher URL. The displayed published card and its stored action do not change.
  The field `source_element` records the RSS/Atom declaring element.
- **Atom literal semantics:** `type="text"`, absent `type` and `text/plain`
  preserve escaped markup as literal characters, normalizing whitespace only.
  HTML/XHTML alone use Domain's shared HTML-to-readable-text converter.
  Remote and binary content do not populate `bodyText`.

**Deliberately out of scope:** exhaustive, budgeted, resumable historical
backfill. Only normally revisited records are enriched through existing
acquisition. Forcing historical reacquisition here would add another workload
owner and might interrupt the visible feed; no new scheduler, queue, cache,
retry engine, or migration-time network fetch was introduced.

## K-15 cross-generation recurrence correction (2026-10-14)

Material comparison distinguishes three factual body states: `unknown` for a
generation-1 revision that has never been reobserved, `absent` when a generation-2
observation explicitly found no declared content, and `declared(text)` for an
observed source body. A generation-1 `origin_revision_body_enrichment` baseline
(including its explicit `absent` row) is evidence for this comparison; only
the comparison key is derived anew. Neither a historical revision nor a published
card's persisted identity, action or layout is rewritten.

`CandidateProvider`, `SelectionExposureSnapshot`, `PublicationStore.exposure`,
`PublicationStore.seenMaterial`, and the append guard now use the same
three-state key. Consequently, unchanged body A following an Atom `updated`
change does not republish, while removal after an observed A or an intermediate
A-to-B edit is material. Full historical backfill remains explicitly separate.
