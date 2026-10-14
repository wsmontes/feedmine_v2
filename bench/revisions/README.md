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
