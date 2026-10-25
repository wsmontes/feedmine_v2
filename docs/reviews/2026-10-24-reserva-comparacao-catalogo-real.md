# Comparação única no catálogo real — reserva preparada (PM-028A/PM-029)

Data: 24/out/2026. Candidata: `a2675129`+ (`product/reserve-20261024`, v6 + reserva + identidade de vídeo).
Base de comparação: `stock-english-before-v6` (mesma máquina, mesmo simulador iPhone 17 Pro Max / iOS 26.5,
contêiner novo, English, catálogo publicado revision 5, rede pública, 180 s de observação após abrir o feed).

## Como a candidata foi medida

- Build Debug do app com o par de catálogo verificado (`catalog.sqlite` sha256 `1825fdae…`, o mesmo da base).
- Simulador novo `FeedMine Reserve 1024` (39EA1733), namespace novo `512CC3D7…`, app desinstalado antes.
- Jornada por XCUITest: `welcome-shape` → compositor (English já marcado, nenhum outro idioma/lugar) →
  `composer-open-feed` → 180 s de feed com rede real. Teste passou em 188,6 s.
- Captura depois do teste: `runtime.sqlite`, `trace.jsonl` e `Media/` do contêiner.
- Análise: `/tmp/analyze_queue.py` (validado contra a evidência congelada: reproduz 629/64/49, tipo 1,955/mín 1,
  fonte 41/16,804/mín 2, PD-4 zero antes de ser usado na candidata).

## Resultado

| Métrica (180 s) | Antes (pré-v6) | Candidata | Δ |
|---|---|---|---|
| Cartas publicadas | 629 | **1.068** | +70% |
| Cartas com imagem | 64 (10,2%) | **447 (41,9%)** | 7,0× |
| Chaves de mídia distintas | 49 | **311** | 6,3× |
| Arquivos em `Media/sha256` | 51 · 12,0 MB | **316 · 314,7 MB** | 6,2× / 26× |
| Revisões com `ready-image` no traço | 121 | **627** | 5,2× |
| Transições `media_ready` | 61 | **446** | 7,3× |
| Distância de fonte (média / mínima) | 16,8 / 2 | **23,2 / 2** | melhor |
| Fontes distintas na fila | 41 | **77** | 1,9× |
| Distância de tipo (média / mínima) | 1,955 / 1 | **1,966 / 1** | igual (oferta limita) |
| PD-4: pares adjacentes da mesma fonte | 0 | **0** | preservado |
| Publicadas sem a imagem declarada | 0 | **0** | preservado |
| Segmentos / cartas por segmento (máx, mediana) | 162 / 24 · 3 | **295 / 28 · 2** | rajada por segmento igual |

Contadores da reserva (última linha `reserve_depth` do traço):

| Campo | Valor |
|---|---|
| `late_completions` | **423** |
| `reconsidered_published` | **960** |
| `reconsidered_with_image` | **411** |
| `persisted_bytes` (retidos pela reserva, não publicados) | 18.219.952 |
| `deferred` / `preparing` / `exhausted` | 69 / 148 / 2 |

## Os três discriminantes do PM, no catálogo real

1. **Imagem rápida**: `MediaPrefetcher` + `PreparedReserve` preparam dentro da janela e a carta é publicada na
   mesma fatia — coberto por `testFastImageIsPreparedInsideTheWindowAndSelectedAtOnce`.
2. **Imagem lenta**: 423 conclusões tardias chegaram depois do prazo da fatia e entraram na reserva; 411 cartas
   publicadas com imagem passaram pela reconsideração durável (`reconsidered_with_image`), exatamente o caminho
   que o PM pediu para provar. Teste: `testSlowImageCompletesAfterTheDeadlineAndJoinsTheNextOffer`.
3. **Imagem indisponível**: 5 revisões assentaram `unavailable`/definitivo; nenhuma bloqueou as outras da mesma
   oferta; zero carta publicada sem a imagem declarada. Teste:
   `testUnavailableImageExhaustsWithoutBlockingTheRestOfTheOffer`.

## O que a candidata não demonstra (declarado)

- **Primeira tela**: este run não mediu geometria de D4; ele prova publicação, não preenchimento do viewport.
- **Vídeo na fila**: o tradutor agora admite `media:content` de vídeo (14 claims `playback/video` gravadas no
  banco da execução), mas **nenhuma carta de vídeo foi publicada em 180 s** — as fontes com vídeo não chegaram à
  frente da fila nessa janela. A correção está no caminho; o efeito na fila ainda não está demonstrado.
- **Custo**: 314,7 MB de mídia baixada em 3 min (26× a base) e 316 arquivos. O orçamento da reserva conta só o
  que está preparado e não publicado (18,2 MB); o que já foi publicado segue as regras de retenção existentes.
  Isso é custo real de rede/armazenamento e precisa de decisão de produto/retenção, não de mais medição.
- **Diversidade de tipo**: a média não se move com esta oferta (498 áudio : 131 sem mídia : 0 vídeo). A conclusão
  do replay de 629 cartas continua valendo: o limite é a composição da oferta, não o comparador.
- Variação entre execuções: uma corrida por braço; os números de imagem são grandes demais para serem ruído
  (7×), mas a contagem de publicadas (629 → 1.068) mistura mais material pronto com a duração das fatias.
