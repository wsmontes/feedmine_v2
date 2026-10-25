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

O que o traço mostra: **seis das sete paradas caem nos primeiros 15 s** (a rajada inicial do replay, 3 avanços/s) e
uma em 30:22. Nas janelas há centenas de `editorial_refusal` com `tooSoon(cardsRemaining: 4)` — o app está examinando
e recusando a oferta do F02 enquanto o leitor avança, e a admissão só chega junto com a publicação seguinte, 1–2 s
depois. Fica registrado com o traço; a correção exige instrumentar a cadência de publicação na rajada inicial.

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

## Aberto (produto)

1. **B03 — 7 paradas de 1 s**, concentradas na rajada inicial; mecanismo traçado, correção não feita.
2. **Volume de publicação**: 1.159 cartas em 180 s contra 68–80 históricos. `HiddenTailMaintenance` seleciona sem
   limite (`examinedCapacity: 256`) e 551 das 578 requisições locais ocorreram com cobertura `healthy`.
3. **Primeira tela** toda de áudio (4 fontes); primeira imagem pronta a 13,0 s, primeira publicação a 5,7 s.
4. **Vídeo**: 14 claims `playback/video`, nenhuma carta publicada na janela.
5. **Armazenamento**: 335 MB de mídia em 3 min; teto de retenção é decisão de produto.
6. **Build 57**: não preparado — B03 vermelho, B06 bloqueado por aparelho travado, autorização não dada.
