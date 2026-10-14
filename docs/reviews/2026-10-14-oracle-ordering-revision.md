# Revisão do avaliador: a adjacência de mesma fonte passa a ser medida na ordem do leitor (2026-10-14)

**Tipo:** nova revisão congelada do avaliador. **Aprovada pelo PO** com três condições: manter a
exigência de zero adjacências, provar que o oráculo corrigido **detecta** uma violação numa fronteira
real, e preservar hashes, insumos e vereditos anteriores com esta nota.

**Commit do produto medido:** `3e9704d78f208810be584c9a93a0448260d03b` (build 44). O commit do
produto **não** mudou; o que muda é o avaliador.

## O defeito

`bench/oracle.py` ordenava os segmentos por `segment_id` — um **UUID v4 aleatório** — em vez do
ordinal do segmento (`feed_segments.ordinal`), que é a ordem em que o leitor os atravessa. Dois
lugares:

1. `cards()`: `ORDER BY c.segment_id, c.ordinal`.
2. `gate_b03()`: reagrupava e reordenava por `segment_id` por conta própria — de modo que corrigir só
   a consulta **não mudava nada** (medido: o veredito continuou FAIL com a consulta já corrigida).

Efeitos, em 29 bancos de corrida:

| Portão | Falha na ordem antiga | Falha na ordem nova |
|---|---|---|
| B03 — conjunto inteiro | **13 de 29** | **0 de 29** |
| B02 — 200 primeiros | **11 de 29** | **0 de 29** |

Sem contraexemplo. O B02 media `run["cards"][:200]`, isto é, os 200 primeiros na ordem do UUID — nem
a adjacência nem *qual* conjunto de 200 correspondiam ao que o leitor vê (medido: 59 fontes distintas
na ordem do UUID contra 40 na do leitor nos mesmos dados; as duas muito acima das 20 exigidas).
No B01, as "fontes distintas nos primeiros 300 cards" iam de 52–93 para 48–56 — a medida corrigida é
mais estrita e segue passando.

O defeito é de **mão dupla**: com uma violação injetada numa fronteira real (o primeiro card do
segmento de ordinal 1 recebeu o `source_id` do último card do segmento de ordinal 0), o avaliador
antigo reporta **PASS** no B02 — cego à violação que existe — enquanto o corrigido a acusa nos dois
portões.

## A intenção do benchmark

`docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md:62` — *"Zero pares de cards consecutivos da mesma
fonte em contexto multi-fonte (PD-4), **incluindo fronteiras de segmentos**"*. A cláusula segue
valendo; as fronteiras que o leitor cruza são as dos segmentos **na ordem em que ele os encontra**.

## A mudança

```python
# cards(): o segmento que o leitor atravessa manda na ordem, não o identificador aleatório
LEFT JOIN feed_segments s ON s.id = c.segment_id
ORDER BY COALESCE(s.ordinal, 2147483647), c.ordinal, c.segment_id

# gate_b03(): não reordenar por segment_id; medir sobre a ordem recebida
ordered = published
```

Nenhum limiar mudou: as cláusulas continuam exigindo **zero**.

## Prova sobre o mesmo dado

| Corrida | Antes | Depois |
|---|---|---|
| `20261014T133639Z` (B03) | FAIL — adjacência 1 | **PASS** — 5 cláusulas PASS, adjacência 0 |
| `20261014T140959Z` (B02) | FAIL — adjacência 1 | **PASS** — 5 cláusulas PASS, adjacência 0 |
| `bench/revisions/injected-control.sqlite` (B02) | PASS — **cego** | **FAIL** — adjacência 2 |
| `bench/revisions/injected-control.sqlite` (B03) | FAIL — 2 | **FAIL** — 2 |

## O que fica preservado

- `bench/revisions/EVALUATOR-pre-fix.sha256` — o congelamento anterior, inteiro.
- `bench/revisions/oracle-pre-fix.py` — o oráculo anterior, verbatim, SHA-256
  `cfa1a8d5db25938ecb4c29deba8510c8666df6b9c251c18f060edef5b8550496` (o hash que aquele congelamento
  exigia).
- `bench/revisions/injected-control.sqlite` — o controle positivo.
- Os vereditos anteriores, em `bench/run/*`, **não são apagados** e **não são comparáveis** aos novos:
  eles mediram outras fronteiras.
- `bench/MANIFEST.sha256` (corpus, `serve.py`, `build_corpus.py`, README) **não muda**.

## O que muda no congelamento

`bench/EVALUATOR.sha256` ganha o hash novo de `bench/oracle.py`
(`bc8813a630668e0ac85a53752c9296881f2c1fec7088bb154cc4787e6431553b`). Os outros cinco arquivos
congelados (`run.sh`, `serve.py`, `build_corpus.py`, `expand.py`, `DiscoveryBenchmarkTests.swift`)
ficam intactos.

## O que precisa ser re-rodado

B01, B02, B03 e B05 sob o novo congelamento, no mesmo commit de produto (`3e9704d7`), para a
certificação valer numa revisão só.

## Reprodução

```bash
R=bench/run/20261014T133639Z
DB="$(ls -d "$R"/container/Library/Application\ Support/FeedMine/*/runtime.sqlite | head -1)"

python3 bench/revisions/oracle-pre-fix.py --run "$R" --corpus bench/corpus --database "$DB" --gate B03   # FAIL
python3 bench/oracle.py                    --run "$R" --corpus bench/corpus --database "$DB" --gate B03   # PASS

# controle positivo, sobre o arquivo injetado
python3 bench/revisions/oracle-pre-fix.py --run "$R" --corpus bench/corpus --database bench/revisions/injected-control.sqlite --gate B02  # PASS (cego)
python3 bench/oracle.py                    --run "$R" --corpus bench/corpus --database bench/revisions/injected-control.sqlite --gate B02  # FAIL (detecta)
```

## Limite declarado

Esta revisão corrige uma medição; ela **não** é melhoria de produto e **não** muda o que o leitor
vive. O cliente registrou que a continuidade funcional está aprovada pelos números da build 44 e que
o portão que resta é o percurso de 200 cards distintos num iPhone real.
