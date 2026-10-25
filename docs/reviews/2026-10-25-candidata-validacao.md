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
voo. O limite de publicação por oportunidade não muda isso (16/32/48 → 6/7/8 paradas), o que é coerente: o problema
é o intervalo entre publicações, não o tamanho de cada uma.

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

1. **B03 — 7 paradas de 1 s** contadas pelo oráculo, que são **dois eventos**: um hiccup de ~3 s dentro da rajada
   sintética e uma parada isolada no fim da janela. Causa **medida**: cadência de admissão — em toda janela de parada
   há 0 publicações e 0 instalações de lista, as fatias terminam em ≤340 ms e os quadros seguem a 39–60 fps. Correção
   não feita; o limite por oportunidade já foi refutado (16/32/48 → 6/7/8).
2. **Volume de publicação**: 1.159 cartas em 180 s contra 68–80 históricos. `HiddenTailMaintenance` seleciona sem
   limite (`examinedCapacity: 256`) e a taxa de oportunidades é alta (≈3,1 fatias/s no traço real). O campo
   `coverage` registrado nessas requisições diz `healthy` em 520 de 532 casos com `ready: at_least(32)` — valor que,
   pela própria política, deveria resultar em `hold`; portanto **a instrumentação registra uma cobertura que não é a
   que produziu a ação**. Isso é um achado de instrumentação a investigar, não prova de que o runway esteja sadio
   pedindo fatia: a causa verificada do volume é a cauda oculta sem limite mais a taxa de oportunidades.
3. **Primeira tela** toda de áudio (4 fontes); primeira imagem pronta a 13,0 s, primeira publicação a 5,7 s.
4. **Vídeo**: 14 claims `playback/video`, nenhuma carta publicada na janela.
5. **Armazenamento**: 335 MB de mídia em 3 min; teto de retenção é decisão de produto.
6. **Build 57**: não preparado — B03 vermelho, B06 bloqueado por aparelho travado, autorização não dada.
7. **P1 residual (não fechado)**: o lote de desbloqueio é limitado a `targetDepth + 16`; se as 16 revisões extras
   também forem incompatíveis com a cauda por PD-4, a preparação para ali e só a aquisição pode trazer outra fonte.
   É o limite decidido (o PM proibiu preparação ilimitada), mas não é prova de liveness — fica registrado como
   pendência, não como "P1 resolvido".
