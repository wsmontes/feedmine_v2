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
cresce — `head_forward`, `tail_back`, `shrunk`, `holes`); `gate_b05` passa a medir no **registro
durável** do app (`reader_bookmark_memberships` guarda a carta que o driver nomeou; o par de
`position_checkpoint` diz onde a app pousou), e três leituras posicionais do driver
(`b05-saved`, `b05-reopen-keeps-saved`, `b05-reopen-preserves-anchor`) ficam **reportadas**, com o
limite declarado: B05 prova que o estado durável não se perdeu, não que o reposicionamento é exato ao
card. O driver passa a **nomear a carta antes de salvar** e a pedir o controle dentro dela.

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
