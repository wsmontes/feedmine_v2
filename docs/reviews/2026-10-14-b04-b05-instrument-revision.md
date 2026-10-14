# Revisão do avaliador: o B04 mede a lista admitida, o B05 o registro durável (2026-10-14)

**Tipo:** revisão do congelamento — `bench/oracle.py` **e** o driver de aceitação
(`FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift`). Autorizada pelo dono do produto na mesma
sessão, com quatro controlos medidos nos insumos existentes **antes** de aplicar.

**Commit do produto medido:** `55ab7125` (o mesmo do fix do produto abaixo). O produto não muda aqui.

## O que obrigou a revisão

`55ab7125` corrigiu um defeito de produto real: o `ColdFeedBootstrap` chamava `attemptFirstPublication`
**sem** `keepsAdmittedHead` nas duas retentativas pós-aquisição (o parâmetro tinha default `false`), e como
`.initial` instala uma vez por sessão, a lista admitida ficava aparada em torno do leitor pelo resto da sessão.
Medido: em `a9d37c12` a cabeça admitida andava de `idx 0` a `idx 15`; em `55ab7125` ela fica em `idx 0` nas
236 instalações e a lista cresce (1→51).

Com a cabeça conservada — a decisão do dono de 2026-10-13 — **duas medições do driver congelado deixaram de
medir o que pretendiam**, e nenhuma delas por defeito do produto:

| Medição | Sintoma | Prova |
|---|---|---|
| `b04-idle-stable` | `not-measurable: card-absent` numa carta **admitida mas não desenhada** | 236/236 instalações com a cabeça na primeira carta da edição; a enumerar do driver não a lista |
| `b05-saved` | `false` com o salvamento **existindo** | `reader_bookmark_memberships` = 1 linha (`126C1A86`, índice 0) enquanto `b05-anchor-before` era `BF12004E` (índice 13) |

A causa física do B05 foi medida no log: o controle estava a **y = −793 pt** (duas tentativas "Not hittable"),
o XCTest rolou o feed para alcançá-lo, e o toque caiu na **primeira carta desenhada** — que passou a ser a
cabeça da edição. Os `position_checkpoint` do trace registram `idx 0` no instante do salvamento e `idx 8` logo
depois, **enquanto o `b05-anchor-before` do próprio driver, gravado no mesmo instante, dizia `idx 13`**: os dois
registros não coincidem, e o que o dado sustenta é mais estreito — a app registrou a posição **resultante
daquele arrasto**, e quem moveu o leitor foi o instrumento. É por isso que a correção é do driver, e não uma
razão para desqualificar a medida.

## O que muda

### 1. `gate_b04` — a cláusula passa a ser medida pela lista admitida

`admitted_series()`/`admitted_violations()` leem os eventos `admitted` do trace contra a ordem real das cartas
no `runtime.sqlite` (ordinal do segmento, depois ordinal da carta — nunca um identificador) e contam, por edição
e por sessão, o que a cláusula proíbe: `head_forward` (uma carta acima do leitor foi retirada), `tail_back`,
`shrunk` e `holes` (a lista deixou de ser o prefixo contíguo que afirma ser). As medições do driver continuam
**reportadas**; um `false` dele continua **falhando** o portão; um `not-measurable` deixa de torná-lo incompleto,
porque o instrumento da cláusula é agora a lista que a app instalou.

### 2. `gate_b05` — a cláusula ganha uma segunda testemunha, e nada é rebaixado

A cláusula passa a ser julgada por **duas testemunhas**, e é **mais estrita** do que era:

- **todas** as medidas do driver continuam valendo — `b05-saved`, `b05-reopen-keeps-saved`,
  `b05-reopen-preserves-anchor` inclusive; só `b05-anchor-before` fica fora do portão, porque é identidade e
  não veredito (o oráculo já fazia assim);
- **acrescenta-se** o registro durável do app: o salvamento tem de existir **e** ser da carta que o driver
  nomeou (`reader_bookmark_memberships`), e a app tem de ter deixado posição durável depois do percurso
  (`context_checkpoints` + o `position_checkpoint` final do trace).

A segunda testemunha é o que o driver, sozinho, não conseguia responder: `card.bookmark` é o **mesmo**
identificador em toda carta (nota do próprio driver em `DiscoveryBenchmarkTests.swift:104-108`), então uma
varredura da árvore pode dizer "algo está salvo" sem dizer **qual**. E as leituras posicionais voltam a ser
legítimas porque o driver deixou de arrastar o feed: a carta é nomeada antes do toque e o controle é procurado
**dentro dela**, de modo que o XCTest não precisa rolar a lista para alcançá-lo — que era a causa física do
`b05-saved:false` (controle a 793 pt acima da viewport). Se a corrida nova, com o driver escopado, ainda
mostrar `b05-reopen-preserves-anchor:false`, isso é achado de produto e vai ser investigado — não desqualificado
como medida.

### 3. Driver — o salvamento passa a nomear a carta

A carta é **nomeada primeiro** (`presentedCard`) e o controle é procurado **dentro dela** por identidade, com a
consulta escopada que o próprio repositório já usa (`ArticleReadingDiagnosisUITests.swift:547`). Mesma cláusula,
mesmo limiar: só a identidade deixa de ser ambígua, e o toque deixa de arrastar o feed.

## Controlos, medidos antes de aplicar

| Corrida | Cláusula | Instrumento anterior | Instrumento novo |
|---|---|---|---|
| `20261014T083321Z` (a9d37c12, cabeça podada) | B04 | NOT_RUN | **FAIL** — 188 `head_forward`, 25 `tail_back`, 1 `shrunk` |
| `20261014T182000Z` (55ab7125, cabeça conservada) | B04 | NOT_RUN | **PASS** — 0 violações, 236 instalações |
| `20261014T141639Z` (salvo = carta nomeada) | B05 | PASS | **PASS** |
| `20261014T180639Z` (salvo = outra carta) | B05 | FAIL | **FAIL** — "o salvamento durável não é da carta que o driver nomeou" |

## O que fica preservado

`bench/revisions/EVALUATOR-pre-b04b05.sha256` (o congelamento anterior inteiro), `oracle-pre-b04b05.py`
(SHA-256 `bc8813a6…`) e `driver-pre-b05-save.swift`, ambos verbatim. A revisão anterior da ordem do UUID
(`oracle-pre-fix.py`, `EVALUATOR-pre-fix.sha256`, `injected-control.sqlite`) fica intacta.
`bench/MANIFEST.sha256` (corpus, `serve.py`, `build_corpus.py`, README) **não** muda — ele não cobre oráculo
nem driver.

**Vereditos anteriores não são comparáveis aos novos:** eles foram medidos com instrumento que não separava
"não desenhada" de "não admitida", nem "o salvamento da carta X" de "algum salvamento".

## O que precisa ser re-rodado

**B01, B02, B03, B04 e B05**, no mesmo commit de produto (`55ab7125`), sob o congelamento novo, com árvore limpa.
A corrida `20261014T181035Z` do B01 registrou `dirty: 2 files` (dois sidecars de SQLite criados ao abrir o
controle congelado) e precisa ser repetida; as demais corridas daquele ciclo mediram um instrumento que já não
vigora.
