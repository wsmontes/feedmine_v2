# Validação da candidata pós-reserva — 25/out/2026

Branch `product/reserve-20261024`, topo `ca532f25`
(GitHub: https://github.com/wsmontes/feedmine_v2/tree/product/reserve-20261024).

## Gates (corpus congelado, instrumento corrigido, uma invocação por gate)

| Gate | Veredicto | Evidência |
|---|---|---|
| B01 (A+B) | **PASS** | 767 fontes no conjunto de aquisição (A), 511 (B), zero iguais; 52 distintas nos primeiros 300 cards |
| B02 (A+B) | **PASS** | 200/200 cards relevantes; 47 fontes; maior fonte 4%; 0 pares consecutivos da mesma fonte; 0 duplicatas canônicas |
| B03 (A+B, 30 min, full trace) | **FAIL** — 1 cláusula | 3.405 avanços, 0 repetição, 0 PD-4, prontidão registrada; **7 paradas de ≥1 s** |
| B04 (A+B) | **PASS** | 262 instalações, 0 head_forward, 0 encolhimento, 0 recuo de cauda, 0 buracos |
| B05 (A+B) | **PASS** | contexto B alcançado, volta a A, âncora preservada, offline local, salvo sobrevive |
| B06 (físico) | **NOT_RUN** | iPhone 14 Plus pareado, mas **bloqueado** ("Unlock iPhone to Continue"); sem desbloqueio não há execução |

### B03 — o que está medido

As sete paradas não vêm da profundidade da reserva. Três corridas, mesmo tree, só o limite de publicação diferente:
16 → 6 paradas, 32 → 7, 48 → 8 (3.405 / 3.393 / 3.424 avanços). Duas hipóteses refutadas com número, não com opinião.

O que o traço mostra: **seis das sete paradas são um único evento de ~3 s** (avanços em epochs
1792910048,6–1792910051,8, contados uma vez por avanço que caiu dentro do hiccup) e **uma parada isolada em 30:22**
(epoch 1792911859,2). Nas janelas há centenas de `editorial_refusal` com `tooSoon(cardsRemaining: 4)` — o app está
examinando e recusando a oferta do F02 enquanto o leitor avança, e a admissão só chega junto com a publicação
seguinte, 1–2 s depois. As duas ocorrências caem dentro de rajadas sintéticas de 3 cartas/s; nenhuma é no meio do
regime permanente.

**Onde a parada nasce (medido nos três traços, A e B):** em toda janela de parada, `candidate` (publicação) = **0** e
`window` (instalação da lista admitida) = **0** — não há material novo para admitir. Não é render: os quadros seguem
a 39–60 fps nas mesmas janelas, com o pior quadro entre 96 e 194 ms, nunca ~1 s. Não é fatia lenta: as 175 fatias do
traço têm mediana **215 ms**, p99 **291 ms** e máxima **340 ms**. Ou seja, a pausa é **cadência de admissão sob a
rajada de 3 avanços/s**: o leitor avança mais rápido do que uma nova admissão chega quando nenhuma publicação está em
voo. O limite de publicação por oportunidade não muda isso (16/32/48 → 6/7/8 paradas), e elevar o piso da reserva
publicada de 32 para 64 (a rajada documentada consome 60 cartas em 20 s) também não: **6 paradas**, contra 7 no piso
32. Quatro valores refutados com número, o que é coerente com a leitura de que o problema é o intervalo entre
publicações num instante específico, não o alvo nem o tamanho do lote.

Em todas as corridas as paradas são **um único aglomerado de ~3 s no começo do traço** (nesta última, todas as 6
entre 1792929550,8 e 1792929553,8), contadas uma vez por avanço que caiu dentro dele; em duas corridas houve também
uma parada isolada no fim da janela. Nenhuma no meio do regime permanente.

**O intervalo medido tem nome (traço de piso 64):** o bootstrap frio publica **12 cartas em t=10,04 s** e admite a
lista em 10,23 s; a **primeira fatia do próprio runway só é pedida em t=15,93 s** (`required 64, ready 10`). Entre
10,9 s e 15,9 s não há publicação, admissão nem pedido de fatia — o leitor consome as 12 cartas do bootstrap a 3/s e
fica sem nada. O aglomerado do B03 é esse **vão de entrega bootstrap → runway** (~5,9 s), não regime permanente, e por
isso nenhum parâmetro de steady state (limite por oportunidade 16/32/48, piso 32/64) o moveu. A correção seguinte
pertence a esse handoff, não à reserva nem ao limite de lote.

Tentativa medida e revertida: acordar o runway explicitamente após a publicação do bootstrap
(`noteLocalSupplyCommitted`). O pedido de fatia **continuou em 15,94 s** e as paradas continuaram 6 — porque
`reconsider` devolve `.none` sem `latestObservation`, e a primeira observação só existe quando a janela é
apresentada e medida. O vão não é falta de aviso: é a **cadência de observação após a primeira apresentação**.

### B03 — diagnóstico do ingresso após a primeira apresentação

No traço `bench/run/20261025T123146Z`, usando `host_started.mono` como origem:
primeiros `candidate` em **10,055 s**, primeira instalação `admitted` em **10,243 s**,
primeiro `window` com 12 cartas em **10,368 s**, primeira `replenishment_requested`
em **15,941 s** (ready 10). Há eventos `advance` desde **11,682 s**; portanto a
presença de callback do viewport não prova que o controlador já recebeu uma observação válida.

O encadeamento no código explica o intervalo: `ColdFeedBootstrap.run` entrega
`.published(snapshot)` dentro de `executeConcurrently`, mas só retorna depois do
conjunto de fontes. `FeedAssociation.receive(.published)` instala a apresentação;
`launch()` só chama `driver.activateCurrentPresentation` depois de `cold.run`
retornar. É essa ativação que ativa o scope e submete a observação estacionária.
O primeiro layout pronto não submete viewport estacionário (`FeedPositionRequest.apply`,
`.ready`); reconciliações visuais também retornam antes de alimentar o runway.
A oportunidade periódica espera 10 s e `foreground()` retorna durante `launching`.
Já `finishViewport` não ativa o scope: um gesto anterior à ativação não substitui o handoff.

A intervenção mínima é entregar a ativação existente junto da primeira apresentação
instalada, sem aguardar as fontes lentas, e preservar a projeção corrente quando o
bootstrap finalmente retornar (seu snapshot inicial pode ter ficado antigo).
Não há motivo medido para alterar reserva, lote, piso, PD-4 ou prontidão de imagem.
O teste de integração do app deve manter uma fonte suspensa e exigir observação e
avaliação do runway dentro de 1 s da instalação, sem gesto nem tick periódico.
Essa hipótese ainda requer nova medição B03 no simulador do dono.

Implementação nesta sessão: `receive(.published)` ativa a apresentação e dirige o runway
logo após instalar e marcar a publicação, usando `activateCurrentPresentation`. O retorno
tardio do bootstrap recebe a projeção corrente da sessão, preservando qualquer crescimento.
Não foi adicionada espera nem alterado o intervalo periódico de foreground.

Verificação: `swift build` passou; `swift test` passou com **1.716 testes, 1 skipped,
0 falhas**. O parse Swift do host e de `CompositionTests.swift` passou. O novo
`testFirstPresentationDrivesRunwayBeforeHeldBootstrapFinishes` pertence ao alvo iOS:
foi escrito, mas **não executado** (a restrição desta sessão exclui `xcodebuild` e
simulador; o SwiftPM não compila o host). Portanto o orçamento de 1 s e o resultado B03
ainda não são uma medição pós-correção. `bench/**` não foi alterado.

## Medição no catálogo real (180 s, contêiner novo, English, rede pública)

| Métrica | Base congelada | Reserva sem limite | Candidata |
|---|---|---|---|
| Publicadas | 629 | 1.068 | **1.159** |
| Com imagem | 64 (10,2%) | 447 (41,8%) | **488 (42,1%)** |
| Chaves de mídia | 49 | 311 | **323** |
| `ready-image` no traço | 121 | 627 | **488** |
| `Media/sha256` | 51 · 12,0 MB | 316 · 314,7 MB | **324 · 335,4 MB** |
| Distância de fonte (média/mín) | 16,8 / 2 | 23,2 / 2 | **22,5 / 2** |
| Distância de tipo (média/mín) | 1,955 / 1 | 1,966 / 1 | **1,954 / 1** |
| PD-4 adjacências | 0 | 0 | **0** |
| Cartas sem a imagem declarada | 0 | 0 | **0** |

## Limites do instrumento (não do produto)

- Gates só valem **uma invocação por gate**: a mesma árvore, com B01+B02+B04+B05 na mesma invocação, devolveu
  B01/B02 NOT_RUN e B04 FAIL; executados separadamente, todos PASS. Registrado para não confundir com produto.
- No corpus, a prontidão mostra `preparados 0 / texto 3054`: o fetcher de mídia recusa host não público e a
  autorização do benchmark cobre feeds, não mídia. Os gates validam admissão, ordem e estabilidade; imagem é
  validada pela medição no catálogo real.

## Auditoria de superfícies e vídeo em uso real (25/out)

**Vídeo, feed real (`feeds.twit.tv/twit_video_hd.xml`, rede pública):** 2 cartas publicadas, ambas com selo **Vídeo**;
nenhum `card.play` e nenhum "Tocar" no frame (D2); tocar abre o navegador in-app no link do próprio item, destino
casado por host (`twit.tv`) e manchete do leitor igual à do item. O caminho de identidade de vídeo funciona ponta a
ponta. O que a janela de 180 s no catálogo público não mostrou foi uma **carta** de vídeo — a fila não chegou a essas
fontes.

**Retorno do navegador — resolvido como defeito de instrumento, produto medido PASS.** A cláusula "a mesma carta no
mesmo frame" falhava porque o fechamento do site por `tap` de acessibilidade **não fecha o Safari modal**: o controle
`Close` resolve na árvore do app hospedeiro e o Safari continua na tela. Medido com instrumentação temporária: depois
do toque, o controle de URL do Safari e o `webView` seguem presentes por 30 s, enquanto toda consulta de árvore
responde em 90–250 ms. Bisseção: a *medição* quebrou em `67d78212` (apresentação modal do site; o pai `3eee1935`
passa em 39 s); `d6ef2452`, `c24c3e15`, `031b27d3`, `1f4f0ee8` e `cb282bcf` falham igual — o produto não é o autor.

Correção no instrumento (`VideoCardJourneyUITests.closeReader`): fechar com um **toque real por coordenada** no frame
do controle, com espera própria pelo desaparecimento do Safari; a asserção não mudou. Resultado: `restored=true`, duas
corridas seguidas de **36,7 s**. Duas tentativas anteriores no produto (suspender a produção ao abrir o site; manter o
leitor ao fechar) foram revertidas por não mudarem nada — o produto já estava correto.

**Cobertura de controles:** 127 dos 199 `accessibilityIdentifier` da UI são referenciados por testes; os 72 restantes
incluem templates interpolados (idiomas, regiões, tipos de mídia) e folhas secundárias. Provados em execução: feed,
leitor, menu, adicionar feed, navegador e a carta de vídeo.

## Aberto (produto)

1. **B03 — paradas de 1 s contadas pelo oráculo.** Run `20261025T132433Z` (`0e7a35ee`): **2 paradas** (1,17 s e 1,27 s) em 3.409 avanços. A leitura do traço (§B03 abaixo) mostra que as duas são **re-admissões da mesma lista** — `cards`, `head` e `tail` idênticos, só a âncora mudou — e que o buffer de 16 cartas à frente nunca se esgota (maior intervalo sem conteúdo novo em regime: 3,26 s). Portanto, **neste run não há parada visível por falta de runway**; o proxy do oráculo conta cadência de admissão. A cláusula continua FAIL mecânico (oráculo, limiar, corpus e driver intocados); a arbitragem entre o texto da cláusula e o proxy é do dono. O run anterior (piso 32/64) media o mesmo fenômeno com 6–7 paradas, e o limite por oportunidade já foi refutado (16/32/48 → 6/7/8).
2. **Volume de publicação**: 1.159 cartas em 180 s contra 68–80 históricos. `HiddenTailMaintenance` seleciona sem
   limite (`examinedCapacity: 256`) e a taxa de oportunidades é alta (≈3,1 fatias/s no traço real). O campo
   `coverage` gravado nas requisições **não é contraditório nem mentiroso**: `RunwayPolicy.evaluate` devolve
   `hold` para `healthy`, mas existe uma segunda autorização — a *fresh supply opportunity*
   (`RunwayController.swift`, ramo `freshSupplyOpportunity`) — que concede **uma** fatia justamente quando a
   política diz `hold`. O traço registrava a cobertura mas não o gatilho. Em 25/10 a requisição passou a carregar
   `trigger: fresh_supply | policy` (instrumentação aditiva, com testes), então a leitura deixa de exigir o
   código. A causa verificada do volume continua sendo a cauda oculta sem limite mais a taxa de oportunidades.
3. **Primeira tela** toda de áudio (4 fontes); primeira imagem pronta a 13,0 s, primeira publicação a 5,7 s.
4. **Vídeo**: 14 claims `playback/video`, nenhuma carta publicada na janela.
5. **Armazenamento**: 335 MB de mídia em 3 min; teto de retenção é decisão de produto.
6. **Build 57**: não preparado — B03 vermelho, B06 bloqueado por aparelho travado, autorização não dada.
7. **P1 residual (não fechado)**: o lote de desbloqueio é limitado a `targetDepth + 16`; se as 16 revisões extras
   também forem incompatíveis com a cauda por PD-4, a preparação para ali e só a aquisição pode trazer outra fonte.
   É o limite decidido (o PM proibiu preparação ilimitada), mas não é prova de liveness — fica registrado como
   pendência, não como "P1 resolvido".

## B03 — o que as 2 paradas do run `20261025T132433Z` são, medidas

> Registro local autorizado nesta sessão (sem push/merge): a instrumentação `trigger` foi commitada em `f7832caf` e a correção da superfície NF-04 em `7a87e035`; a jornada de app em `a5c3573d`. **B03 continua FAIL mecânico** — nada aqui o reclassifica.

Análise somente-leitura do `trace.jsonl` do próprio contêiner da corrida (`0e7a35ee`, `--full-trace`). O oráculo selado conta `advance → próximo admitted ≥ 1,0 s` (`bench/oracle.py`), sem distinguir atividade nem o que a admissão mudou.

| Fato medido | Valor |
|---|---|
| Avanços / por atividade | 3.409 (forward 2.730, stationary 669, backward 10) |
| Paradas pelo oráculo | 2 (1,17 s e 1,27 s) — ambas `forward` |
| O que a admissão seguinte mudou | **nada**: `cards`, `head` e `tail` idênticos à admissão anterior; só a `anchor` mudou |
| Quando a admissão acontece | **só quando o leitor alcança a cauda admitida**: `RunwayActivity.admitsForwardContent` é `self == .explicitTailApproach` (`FeedPresentationAdmission.swift:79-86`) e é o único portão do gesto em `FeedRunwayDriver.swift:427`. Avanço **dentro** do histórico já admitido, settle estacionário, gesto para trás e mudança de layout não admitem nada |
| Buffer à frente | `forwardWindowCards = 16` (`AppComposition.swift:2766`); a poda preserva a cabeça e corta os **mais antigos** (`FeedSession.swift:424-455`), nunca a reserva à frente; `admitForwardScroll` só estende (capacidade = 16 − à frente; `FeedSession.swift:367-395`) |
| Intervalo sem mudança de conteúdo (≥60 s, forward) | n=2.670: p50 0,118 s · p99 0,941 s · **máx 3,26 s**; 25 intervalos ≥1 s |
| Cartas admitidas **à frente** da âncora em cada avanço (medido) | 3.409/3.409 avanços mapeados ao banco do run (`feed_segments.ordinal` + `published_cards.ordinal`): mínimo **6**, p1 13, p50 **15**, máximo 17; **nenhum** avanço com ≤2, nenhum com 0 |
| Cartas à frente nas 2 paradas | **15** (gap 1,17 s) e **14** (gap 1,27 s) — e o mínimo entre todos os avanços com gap ≥1 s é **14** |
| Intervalo sem mudança de conteúdo nas 2 paradas | 1,301 s e 1,599 s |
| Quadros nas janelas | 40–54 frames/s; pior quadro 101–157 ms |

Uma parada visível por falta de runway exigiria esgotar 16 cartas à frente — cerca de 16 s consumindo a 1 card/s. O maior intervalo sem conteúdo novo em regime é 3,26 s, e as duas paradas são re-admissões da mesma lista (conteúdo idêntico; só a âncora mudou). **Conclusão (no modelo de admissão, não na tela):** em nenhum dos 3.409 avanços a âncora estava na cauda — as duas paradas tinham 14–15 cartas **admitidas** à frente (medido; 16 antes do avanço, valor que confirma o limite de poda). Numa parada por falta de runway, a cauda admitida coincide com a âncora; **estas duas não são isso**. O que resta não medido: que essas 14–15 cartas estivessem efetivamente **renderizadas** naquele instante — os `frames` (40–54 fps, pior 101–157 ms) são indício, não prova de conteúdo na tela. **B03 segue FAIL mecânico.** O proxy conta cadência de admissão — inclusive eventos que nada acrescentam — e o texto da cláusula pede "paralisação visível … causada por falta de runway". O veredito do gate segue **FAIL mecânico**; nada aqui o reclassifica.

**Por que nenhum avanço precisou admitir:** `.explicitTailApproach` é produzido quando a carta desenhada **é a última carta admitida** (`FeedVisualCapture.swift:505-515`; `FeedScreen` passa `isLast: window.items.last?.id == card.id`), e é o único portão do gesto (`FeedPresentationAdmission.swift:79-86` → `FeedRunwayDriver.swift:427`). No run há **zero** avanços com essa atividade (forward 2.730, stationary 669, backward 10): o leitor nunca alcançou a cauda, porque a lista cresce pelo caminho do runtime, `.publishedGrowth` (`FeedPresentationAdmission.swift:63-70`), limitado pelas 16 cartas à frente. As 8.879 admissões do run são, portanto, **cadência de publicação**, não de gesto.

Método do ordinal: as cartas do trace foram mapeadas ao banco do próprio run (zero não mapeadas) e ordenadas por `feed_segments.ordinal` + `published_cards.ordinal`; "à frente" = ordinal da cauda admitida − ordinal da âncora do avanço, na admissão que cobria o instante. Não é estimativa agregada.
