# Revisões do avaliador

Esta pasta guarda o que uma revisão congelada **substituiu**, para que a substituição seja auditável
sem tocar no congelamento vigente.

## 2026-10-14 — a adjacência de mesma fonte passou a ser medida na ordem do leitor

**Motivo:** `cards()` ordenava os cards por `segment_id` (um UUID v4 aleatório) e `gate_b03()`
re-agrupava por `segment_id` por conta própria. As cláusulas de "zero pares consecutivos da mesma
fonte" — e, no B02 e no B01, as de "os primeiros N cards" — passaram a depender de um sorteio de
identificadores em vez do comportamento do produto.

**Medido, em 29 bancos de corrida (`bench/run/*/…/runtime.sqlite`):**

| Portão | Falha na ordem antiga | Falha na ordem nova |
|---|---|---|
| B03 — conjunto inteiro | 13 de 29 | 0 de 29 |
| B02 — 200 primeiros | 11 de 29 | 0 de 29 |

**Controle positivo** (`injected-control.sqlite`, uma cópia de corrida real com o `source_id` do
primeiro card do segmento de ordinal 1 trocado pelo do último card do segmento de ordinal 0):
o avaliador antigo reporta **PASS** no B02 (cego à violação), o novo reporta **FAIL** nos dois
portões (adjacência 2). A correção fortalece a medida; nenhum limiar mudou.

**O que está aqui:**

| Arquivo | O que é |
|---|---|
| `EVALUATOR-pre-fix.sha256` | o congelamento anterior, inteiro |
| `oracle-pre-fix.py` | o oráculo anterior, verbatim — SHA-256 `cfa1a8d5db25938ecb4c29deba8510c8666df6b9c251c18f060edef5b8550496`, que é o hash que aquele congelamento exigia |
| `injected-control.sqlite` | a cópia com a violação injetada numa fronteira real, para o controle positivo |

O congelamento vigente é `bench/EVALUATOR.sha256`, cuja linha de `bench/oracle.py` passou a
`bc8813a630668e0ac85a53752c9296881f2c1fec7088bb154cc4787e6431553b`. `bench/MANIFEST.sha256`
(corpus, `serve.py`, `build_corpus.py`, README) **não** mudou: ele não cobre o oráculo.

**A nota humana da revisão** — o defeito, a reprodução e a decisão — está em
`docs/reviews/2026-10-14-oracle-ordering-revision.md`.

**Vereditos anteriores:** preservados em `bench/run/*` e **não comparáveis** aos novos. Uma corrida
que leu FAIL sob a ordem antiga não comprova defeito do produto; uma que leu PASS também não era
prova, porque a ordem antiga media outras fronteiras.


## 2026-10-14 — o B04 mede a lista admitida, e o B05 o registro durável

**Motivo:** o commit `55ab7125` corrigiu um defeito de produto (o `ColdFeedBootstrap` perdia
`keepsAdmittedHead` nas duas retentativas pós-aquisição, e a lista admitida ficava aparada em torno do
leitor). Com a cabeça conservada — a decisão do dono de 2026-10-13 — duas medições do driver deixaram
de medir o que pretendiam, nenhuma delas por defeito do produto:

- `b04-idle-stable` lia `not-measurable: card-absent` numa carta **admitida mas não desenhada** (236 de
  236 instalações com a cabeça na primeira carta da edição, lista crescendo até 51 cartas; o
  `bringIntoView` do driver alcança 8 swipes e o leitor já atravessara centenas);
- `b05-saved` lia `false` com o salvamento **existindo** no banco: `card.bookmark` é o mesmo
  identificador em toda carta, e o `firstMatch` resolveu para a primeira carta desenhada — que passou a
  ser a cabeça da edição. Medido: o controle estava 793 pt acima da viewport, o XCTest rolou o feed
  para alcançá-lo e o salvamento caiu na cabeça (`126C1A86`, índice 0) em vez da carta seguida
  (`BF12004E`, índice 13).

**O que muda:** `gate_b04` passa a medir a cláusula na **lista admitida** que o trace registra
(`admitted_series`/`admitted_violations`: cabeça na primeira carta da edição, lista contígua e que só
cresce — `head_forward`, `tail_back`, `shrunk`, `holes`); `gate_b05` passa a julgar por **duas
testemunhas**: todos os fatos que o driver mediu continuam valendo (só `b05-anchor-before` fica fora,
porque é identidade e não veredito) **e** o registro durável do app tem de guardar a carta que o driver
nomeou, com posição durável depois do percurso. Nada foi rebaixado: a cláusula ficou **mais estrita**.
O driver passa a **nomear a carta antes de salvar** e a pedir o controle dentro dela — sem isso o toque
ficava 793 pt acima da viewport, o XCTest rolava o feed para alcançá-lo e o salvamento caía na primeira
carta desenhada.

**Controlos, medidos antes de aplicar:**

| Corrida | Cláusula | Instrumento anterior | Instrumento novo |
|---|---|---|---|
| `20261014T083321Z` (a9d37c12, cabeça podada) | B04 | NOT_RUN | **FAIL** — 188 `head_forward`, 25 `tail_back`, 1 `shrunk` |
| `20261014T182000Z` (55ab7125, cabeça conservada) | B04 | NOT_RUN | **PASS** — 0 violações, 236 instalações |
| `20261014T141639Z` (salvo = carta nomeada) | B05 | PASS | **PASS** |
| `20261014T180639Z` (salvo = outra carta) | B05 | FAIL | **FAIL** — "o salvamento durável não é da carta que o driver nomeou" |

**O que está aqui:**

| Arquivo | O que é |
|---|---|
| `EVALUATOR-pre-b04b05.sha256` | o congelamento anterior, inteiro |
| `oracle-pre-b04b05.py` | o oráculo anterior, verbatim — SHA-256 `bc8813a6…` |
| `driver-pre-b05-save.swift` | o driver anterior, verbatim |

O congelamento vigente é `bench/EVALUATOR.sha256`. `bench/MANIFEST.sha256` (corpus, `serve.py`,
`build_corpus.py`, README) **não** muda.

**A nota humana da revisão** está em `docs/reviews/2026-10-14-b04-b05-instrument-revision.md`.

**Vereditos anteriores:** preservados em `bench/run/*` e **não comparáveis** aos novos.

## 2026-10-26 — o registro de fases sai do caminho do host, nos dois modos

**Motivo:** `bench/run.sh` pré-criava `$OUT/<gate>-<profile>.phases` no Mac e passava o caminho ao
runner por `TEST_RUNNER_FEEDMINE_BENCH_PHASES`, **só** no modo simulador. Nas duas execuções de B03 de
2026-10-26 (`20261026T085541Z`, `20261026T100032Z`) o **primeiro** `record` da jornada bloqueou dentro
de `open(2)` nesse arquivo do host, na main thread, por 46 minutos: nenhum swipe, nenhum `advance`,
veredito NOT_RUN nas duas. O modo aparelho nunca teve essa escrita — o driver escreve no próprio
container e o `tearDown` anexa ao result bundle. A correção faz desse o único transporte; a razão no
kernel do bloqueio **não** está estabelecida (ver a nota).

**O que muda:** o driver não honra mais caminho vindo do ambiente e cria o próprio registro;
`run.sh` extrai o anexo **nos dois modos com o mesmo código** e registra o que o transporte fez em
`<gate>-<profile>.transport.log`; sem anexo não há `.phases` (NOT_RUN, nunca PASS). O `.xcresult` de
cada portão passa a ser movido para `$OUT/<gate>-<profile>.xcresult` antes da limpeza de `derived` —
antes ele era apagado junto, e as duas corridas travadas perderam o único relato do runner.

**Nada da régua muda:** `oracle.py`, `serve.py`, `corpus/**` (incluindo `criteria.json`), `device/**`
e `MANIFEST.sha256` ficam byte a byte; nenhum critério, limiar, duração ou gesto foi tocado.

**O que está aqui:**

| Arquivo | O que é |
|---|---|
| `EVALUATOR-pre-phases-transport.sha256` | o congelamento anterior, inteiro |
| `run-pre-phases-transport.sh` | o `run.sh` anterior, verbatim — SHA-256 `966276836b6edf55f555ae25c0c15d5c23185c4894a43e92be24ea10ca0c0b3f`, que é o hash que aquele congelamento exigia |
| `driver-pre-phases-transport.swift` | o driver anterior, verbatim — SHA-256 `e411f8fcdc8c738c937ec2ffd2b0929436ec42edd8ff6f134156ea55421476de` |

O congelamento vigente é `bench/EVALUATOR.sha256`: `bench/run.sh` →
`b027007d0fc7b2e3cb097b3f36e062738592f025bfb68b3f2bbb21fb30160b80`, driver →
`c3ae03a40d6c03353fad25f8aaa7891a33cc62bdbc8e6bb6bcf5893de8eaac7e`. `bench/MANIFEST.sha256` não
muda (ele não cobre o `run.sh` nem o driver).

**A nota humana da revisão** está em `docs/reviews/2026-10-26-b03-instrument-transport.md`.

**Vereditos anteriores:** preservados em `bench/run/*`. As duas corridas de 2026-10-26 são **NOT_RUN**
de instrumento — não são FAIL nem PASS do produto, e não são comparáveis a uma execução corrigida.
