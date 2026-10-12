# B04 — antes e depois da ligação K-01/K-05 (medido, 2026-10-12)

O arquiteto recusou "K-01/K-05 estão no merge" como prova da ligação. Ele estava certo: a ligação não existia, e o
gate B04 mediu a consequência.

## Antes (corpus local inalcançável)

```
run 20261012T080348Z
"clauses": [
  { "clause": "o protocolo de B04 foi caminhado (âncora, convite, ócio, rotação, background)",
    "observed": null, "pass": null },
  { "clause": "nada do que o leitor já tinha se moveu, reordenou ou retratou",
    "observed": { "medidas": {}, "instaveis": [], "nao_mediveis": [] }, "pass": null }
]
```
**Nenhuma medição.** O protocolo não foi caminhado porque o app não conseguia buscar o corpus que o próprio runner
serve localmente: nenhum ponto do app passava origem autorizada, e o padrão `publicOnly` do K-01 recusava o host.

## Depois (a raiz autoriza a origem dos endpoints que esta execução busca)

```
run 20261012T081619Z
## B04 — NOT_RUN
- PASS — o protocolo de B04 foi caminhado (âncora, convite, ócio, rotação, background)
  observed: ["b04-anchor0", "b04-background-frames", "b04-background-same-topmost",
             "b04-background-stable", "b04-idle-frames", "b04-idle-stable",
             "b04-invitation", "b04-rotation-counters", "b04-rotation-holds"]
- NOT_RUN — nada do que o leitor já tinha se moveu, reordenou ou retratou
  observed: {"medidas": {"b04-idle-stable": "not-measurable",
                         "b04-rotation-holds": "true",
                         "b04-background-stable": "true"},
             "instaveis": [], "nao_mediveis": ["b04-idle-stable"]}
```

O protocolo **passou a ser caminhado** e **duas das três medidas estão estáveis** (`rotation-holds`,
`background-stable`) com **uma não medível** (`idle-stable`) — o que deixa o gate **NOT_RUN**, nunca FAIL e nunca
PASS. É a regra que o oráculo declara e o Kiro confirmou por leitura (K06-6): não medível torna o gate incompleto.

## A diferença que fica aberta (não é da correção)

O registro da rodada 10 (`UI_TRANSFER_MATRIX.md` §9) traz **B04 PASS, 2 de 2**. Agora `idle-stable` sai
`not-measurable`. Ou o ócio deixou de ser observável nestas condições de corrida, ou a régua do instrumento mudou
entre as duas execuções — é uma pergunta de instrumento, separada da ligação, e vale ser olhada antes de tratar o
gate como fechado.
