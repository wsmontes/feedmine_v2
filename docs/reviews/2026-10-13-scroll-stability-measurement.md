# Scroll: por que a V1 é estável e o que a V2 mede

Data: 2026-10-13. Origem: pergunta do dono do produto — *"a V1 tem scroll estável"*. Este documento responde
com o mecanismo e com número; não altera oráculo, corpus nem critério de gate.

## 1. A diferença de mecanismo (V1 × V2)

| | V1 (`wsmontes/feedmine-dev`) | V2 (atual) |
|---|---|---|
| Container | `ScrollViewReader > ScrollView > LazyVStack` (`feedmine/Views/FeedScreen.swift:947-950`) | `ScrollView > LazyVStack` + modificador de viewport (`Sources/FeedMineUI/FeedScreen.swift:83-135`) |
| Lista renderizada | **página inteira publicada**, cap 300 | **janela admitida em torno da âncora**: `backwardWindowCards = 8`, `forwardWindowCards = 16` (`FeedMineApp/FeedMineApp/AppComposition.swift:1665-1666`) |
| Poda | **só a cauda**; a cabeça nunca é removida (`feedmine/Services/Reservoir.swift:127-148` — o comentário registra que remover o início deslocaria o offset) | a cabeça é podada conforme o leitor avança (`Sources/FeedMineRuntime/FeedSession.swift:187-197`) |
| Escrita de offset | **nenhuma**. Nenhum `scrollPosition(id:)`, nenhum `setContentOffset`; o único scroll programático é um restore one-shot no cold start (`feedmine/Views/FeedScreen.swift:1072`, guardado por `onChange(of: scrollTargetID)` + `userHasScrolled`/`didRestoreScroll`) | **correção de offset por geometria** para esconder o deslocamento causado pela poda: `FeedWindowOffsetCorrection` + `setContentOffset(animated: false)` (`Sources/FeedMineUI/FeedNativeScrollOffset.swift:146`), suprimida durante gesto (`:145 guard !nativeGestureActive`) |
| Binding de posição | ausente | `.scrollPosition(id:)` de duas vias, derivado de `capture.positionID ?? presented.window.anchor.cardID` (`FeedScreen.swift:446-450`) |
| Observer por card | `onScrollVisibilityChange` (Bool), **nunca geometria** (`feedmine/Views/FeedScreen.swift:993`) | `onGeometryChange` por card alimentando a correção (`FeedScreen.swift:97-104`) |
| Fase de scroll | nenhuma API de fase (`onScrollPhaseChange`/`isDragging` ausente) | `onScrollPhaseChange` com `invalidateLayout()` em vários ramos (`FeedScreen.swift:477-516`) |

Resumo em uma frase: **a V1 nunca muda o conteúdo acima do leitor; a V2 muda (poda a cabeça) e compensa com
escrita de offset.** É o preço da janela limitada — e o mecanismo que a V1 deliberadamente recusou.

## 2. O que a V2 mede de fato (simulador, iOS 26.5, fixture de 95 cards)

Prova: `FeedMineUITests/ArticleReadingDiagnosisUITests/testFastFlingWindowChangesDoNotWriteIntoAnActiveGesture`
(`FEEDMINE_LOCAL_FEEDS=1`, `FEEDMINE_TRACE_CAPTURE=1`, `FEEDMINE_FIXTURE_ITEMS=95`, 8 `swipeUp(velocity: .fast)`),
lendo o label DEBUG `feed-window-proof`.

| Contador | ledger observável (build 33) | ledger não observável (build 32) |
|---|---:|---:|
| `deferredWindows` (mudanças de janela durante o gesto) | 18 | 14 |
| `corrections` aplicadas | 2 | 1 |
| `residual` / `visualResidual` (deslocamento do card retido) | 0,000 / 0,000 pt | 0,000 / 0,000 pt |
| `activeWrites` (escrita de offset durante gesto) | **0** | **0** |
| `activeWindows` / `activeLayoutSteps` / `activeLayoutStep` | 0 / 0 / 0,000 pt | 0 / 0 / 0,000 pt |
| `surfaceEvals` (reavaliações da superfície, contador novo) | 12 → 34 | 10 → 27 |

Leituras:

1. **Nada é escrito durante o gesto** e **nada pula** (`activeLayoutStep = 0`): o contrato de estabilidade da V2
   é medido e se mantém.
2. A poda da cabeça acontece (até 18 mudanças de janela deferidas por 8 flings) e custa **1–2 correções**, com
   **resíduo zero** — a compensação é exata neste cenário.
3. O custo do ledger observável (o delta de hoje, build 33) é **≈ +5 reavaliações da superfície por 8 flings**
   (34 vs 27, com ±2 de variação na contagem inicial): real, modesto, e **não** é mecanismo de instabilidade.
4. A superfície reavalia ~1 vez por card percorrido — não é uma tempestade.

## 3. Conclusão honesta

No simulador, o scroll da V2 **não reproduz** a sensação descrita: nenhuma escrita durante o gesto, correção
com resíduo zero, ~1 reavaliação por card. A diferença estrutural com a V1 existe e é a poda da cabeça, mas o
custo medido dela é invisível neste cenário.

O que continua **sem medição** (e portanto não pode ser descartado):

- **Aparelho físico**: hitches, CPU, térmica e memória. É o **B06**, que nunca foi executado — o simulador não
  tem throttling térmico nem a mesma GPU, e é no iPhone que a sensação foi relatada.
- **Reaplicação da posição pelo SwiftUI** a partir do binding `.scrollPosition(id:)`: nenhum contador atual
  cobre uma escrita *interna* do SwiftUI (o caso estacionário está coberto por
  `testWindowUpdateDoesNotShiftAStableVisibleCardWhileStopped`, mas não o caso durante deceleração).

Próximo passo com valor: **B06** no iPhone do dono (hitches/CPU/térmica/memória), com o mesmo percurso A/B da
build 32 contra a 33 para isolar o delta do ledger — que a medição acima já mostra pequeno.

## 4. Instrumentação acrescentada

`FeedNativeWindowProof` (DEBUG) passou a publicar `surfaceEvals` — quantas vezes a superfície do feed se
reavaliou no processo — e o teste de fling imprime os contadores (sem os IDs) no seu log, para que a próxima
comparação seja uma medida, não uma opinião.
