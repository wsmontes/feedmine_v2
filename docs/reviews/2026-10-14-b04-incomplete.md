# B04 INCOMPLETO — a medida do ócio não foi possível (2026-10-14)

Corrida `bench/run/20261014T083321Z`, commit `a9d37c1254957f42d6ce57c39101d52573bae2f8`,
`dirty: 0 files`, corpus e oráculo congelados, device dedicado `FeedMine Bench`.

## Veredito: NOT_RUN (gate incompleto, nunca PASS)

| Cláusula | Resultado |
|---|---|
| o protocolo de B04 foi caminhado (âncora, convite, ócio, rotação, background) | PASS — 17 medidas registradas |
| nada do que o leitor já tinha se moveu, reordenou ou retratou | **INCOMPLETO** — 6 `true`, 1 `not-measurable` |

Medidas verdadeiras: `b04-after-answer-stable`, `b04-after-answer-order`, `b04-after-undo-stable`,
`b04-after-hide-stable`, `b04-rotation-holds`, `b04-background-stable`. Cada uma delas com os
quadros antes→depois (383→383, 170→170) e sem nenhuma instável.

A que não pôde ser medida:

```
b04-idle-stable:not-measurable
b04-idle-frames:card-absent(on-screen=92C31437-…,1A35D8F5-…)
```

## O que `not-measurable` significa aqui, e por que não é PASS

O oráculo congela três valores possíveis para cada medida — `true`, `false` e `not-measurable` — e
trata `not-measurable` como **gate incompleto**. Um quadro que nunca chegou (`-9999`) não demonstra
movimento nem comprova estabilidade, então não pode ser lido como passe.

A razão é precisa e distingue dois fatos diferentes: a carta está **ausente da árvore** (este caso),
e não *presente mas sem layout*. O driver, antes de medir, traz a carta de volta à tela com até 8
swipes em cada direção (`bringIntoView`) e **nunca substitui** a carta que está seguindo por outra;
ele registra o motivo quando isso falha.

Leitura do traço da própria corrida: 132 s, 92 avanços, 78 janelas, e as âncoras mudando em
sequência nos últimos segundos — os swipes do próprio `bringIntoView`. O leitor já havia andado
além do alcance que o protocolo consegue percorrer de volta, então a carta seguida deixou de ser
instanciada pela lista.

**Não é regressão desta rodada:** o documento de entrega de 2026-10-13 já registrava B04 `NOT_RUN`
(corrida `20261012T081619Z`). B04 nunca foi fechado.

## O que fecharia B04

Ou o produto mantém recuperável a carta que o leitor seguia (a política `keepsAdmittedHead` conserva
o **dado** acima do leitor, mas a lista instancia só perto da viewport — ausente da árvore não é o
mesmo que removido do feed), ou o protocolo do driver precisaria de mais alcance — e o driver é
**congelado**, então a decisão é do produto, não do teste. Isso exige investigação própria, com uma
sonda que publique as identidades da janela antes e depois de 12 s de ócio, e está na fila.

## O que esta corrida NÃO prova

- Nada sobre memória, energia, térmica ou hitches (isso é B06, em aparelho físico).
- Nada sobre a frequência de convites: a corrida colocou 1 oferta e registrou 2 respostas em 132 s.

## Leitura fina: o caminho exato do `not-measurable`

O driver mede `b04-after-hide-stable` com a carta **em `y=383` — dentro da viewport** (`0,122`–`440,956`).
Na sequência, o bloco do ócio faz: se a carta não está na tela, traz de volta; senão mede o quadro
antes, dorme **12 s sem nenhum input**, e mede de novo. O motivo registrado é `card-absent`, que só
vem do segundo caminho: **a carta estava lá antes do sono e não estava na árvore depois dele**.

Isso muda a leitura de "o driver não achou a carta" para "**a carta saiu de onde estava durante 12 s
sem input**" — que é precisamente o fato que a cláusula 2 existe para negar (`nada do que o leitor já
tinha se moveu`). O gate não o pontua porque a carta **sai da árvore** em vez de se mover: ausente não
é `false`, é `not-measurable`.

## A janela não é o problema

Contando o traço das três corridas (`window.cards` = tamanho da lista desenhada):

| Corrida | `cards` (máx) | percorridos |
|---|---:|---:|
| B03 (30 min) | **811** | 866 |
| B01 perfil A | 127 | 167 |
| B01 perfil B | 238 | 232 |
| B04 | 26 | 33 |

A janela cresce com o leitor — a cabeça admitida é conservada, e `card-absent` não é dado removido.
O que falta é saber **por que** a carta desce/sai durante o ócio: uma sonda que publique as
identidades da janela e o quadro da carta antes e depois dos 12 s decide entre "a lista rolou sob o
leitor" e "a lista foi reconstruída". Está na fila, e é a próxima investigação depois do estado de
fim de conteúdo.
