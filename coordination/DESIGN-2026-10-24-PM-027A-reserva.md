# Desenho — PM‑027A: profundidade da oferta preparada (reserva de cartas completas)

Autor: OMP · 24/out/2026 · base `546ba74f` + WIP v6 no worktree `feedmine-reader-position`

## 1. O que está medido hoje (não é opinião)

| Camada | Valor medido | Onde |
|---|---|---|
| Revisões estruturais no supply | 4.036 | `NOVAS_FRENTES_PARA_O_CODEX.md:238-254` |
| Revisões que **declaram** imagem | 2.488 (61,6%) | idem |
| Revisões que chegaram a `ready-image` | **66** (2,6% das que declaram) | idem |
| Ativos gravados em `Media/sha256` | 51 arquivos / 12,0 MB | idem |
| Cartas publicadas com imagem | 64 de 629 (10,2%) | idem |
| Cartas publicadas **sem** a imagem declarada | **0** | idem — regra de integridade cumprida |
| Profundidade examinada por fatia | 32 candidatos | `AppComposition.swift:2087` |
| Tolerância de preparação | 5 s bootstrap; p95×1,2+2 s; teto = timeout do transporte | `AppComposition.swift:2352-2359` |
| Concorrência de download | `max(2, núcleos/2)` global | `AppComposition.swift:2288` |
| Prontidão (`ready`) | **só em memória**, recriada por associação | `MediaReadiness`, `AppComposition.swift:2279` |
| Candidato pendente | suspenso antes do ranking; cursor volta ao mais antigo retido | `SelectionEngine.swift:113-116,181-191` |

Conclusão factual: **a integridade está certa e o volume está errado.** A oferta declarada é 2.488; o estoque preparado é 66. O gargalo é *quantas cartas completas existem no momento da seleção*, não a política de prazo (que já não publica carta sem a imagem declarada).

## 2. Por que a arquitetura atual não acumula reserva

1. Cada fatia prepara **exatamente** a janela examinada (`FeedRunwayDriver` `.runLocalSlice`): 32 revisões, com prazo de parede.
2. O que não assenta no prazo é suspenso; o cursor volta ao mais antigo retido (`SelectionEngine.report`), então há retentativa — mas cada retentativa **reprepara a mesma janela de 32** e para no mesmo prazo.
3. A prontidão mora em memória e o prefetch não é unido depois do prazo (`MediaPrefetcher.prefetch` retorna no prazo, o `Task` continua solto): o trabalho que termina tarde **não entra em nenhuma seleção**, porque o cursor já passou.
4. Não existe conceito de “estoque preparado à frente do cursor”. O `readyAhead` do runway conta cartas **publicadas** à frente do leitor, não cartas **preparadas e não publicadas**.

Logo: aumentar prazo só move o ponto de corte; o que falta é **profundidade preparada** e **reaproveitamento do trabalho que termina tarde**.

## 3. Desenho proposto

### 3.1 Reserva de apresentações preparadas (novo componente)

`PreparedReserve` — ator de sessão, em `Sources/FeedMineRuntime`:

- `presentations: [OriginRevisionID: PreparedPresentation]` (a mesma forma que `MediaReadiness` devolve).
- `pending: [OriginRevisionID: Attempt]` com `attempts`, `nextEligibleAt`, `lastFailure`.
- `targetDepth` (cartas preparadas **elegíveis** à frente do cursor), `byteBudget`, `countBudget`.
- API: `admit(window:)`, `ready(upTo:)`, `replenish()`, `evict()`, `snapshot()`.

`MediaReadiness` continua sendo o dono do fato “preparado”; a reserva é o **índice + política** por cima (não duplica o dado binário).

### 3.2 Fluxo novo da fatia

1. **Examinar mais longe que se publica.** A consulta de supply passa a examinar `preparationDepth` (proposto **128**) em vez de 32; a seleção continua publicando o que está pronto.
2. **Preparar sem prazo de fatia.** O `prefetch` da janela de preparação recebe um `MediaPreparationOpportunity` com prazo **de operação** (o mesmo p95×1,2+2), mas o driver **não** considera o trabalho perdido: o `Task` do prefetcher entrega na reserva quando termina (`onPrepared`), mesmo depois do prazo.
3. **Publicar do que está pronto, na ordem editorial.** A seleção roda sobre `reserve.ready ∩ janela`; cartas pendentes continuam suspensas e o cursor volta como hoje.
4. **Reposição contínua.** Ao fim da fatia, `replenish()` examina a continuação do cursor até `targetDepth` prontas ou até esgotar o orçamento. Roda em background, sem bloquear a publicação.
5. **Retentativa limitada.** `attempts > 3` ou falha definitiva → `.unavailable` honesto (sem carta inventada). Backoff 1 s, 4 s, 16 s.

### 3.3 Orçamentos finitos (não é abundância infinita)

| Recurso | Limite proposto | Como |
|---|---|---|
| Downloads simultâneos | `max(2, núcleos/2)` — **inalterado** | `concurrentDownloadLimit` |
| Bytes por imagem | orçamento medido (taxa × janela) — inalterado | `DeviceMediaConditions.policy` |
| Bytes de ativos preparados | 96 MB com LRU (evict só o que não foi publicado) | `MediaTidy` + reserva |
| Cartas preparadas | `targetDepth` 96 + histerese (repõe abaixo de 64) | reserva |
| Tentativas por revisão | 3 | reserva |
| Trabalho por ciclo | 1 reposição em voo, cancelável | ator |

### 3.4 Onde o código muda

| Arquivo | Mudança |
|---|---|
| `FeedMineApp/FeedMineApp/AppComposition.swift:2087` | `examinedCandidateCapacity` 32 → 128 (parâmetro nomeado `preparationDepth`) |
| `Sources/FeedMineRuntime/MediaPrefetcher.swift` | callback `onPrepared(revision, presentation)`; `prefetch` não descarta o que termina depois do prazo |
| `Sources/FeedMineRuntime/PreparedReserve.swift` (novo) | índice, tentativas, orçamentos, reposição |
| `Sources/FeedMineComposition/FeedRunwayDriver.swift` (`.runLocalSlice`) | seleciona do que está pronto; agenda `replenish()` ao concluir |
| `Sources/FeedMineRuntime/LocalProductionSlice.swift:107-164` | prontidão passa a vir da reserva (união), não só do snapshot da fatia |
| `Sources/FeedMineMedia/AssetStore.swift` / `MediaTidy` | teto de bytes da reserva + LRU |
| `docs/reviews/…` | métricas novas no traço: `reserve_depth`, `ready_image`, `deadline_cut`, `published_with_image` |

**Não muda**: v2–v5 do sequenciamento, alinhamento `inputs × cardIDs`, regra “nunca publicar sem a imagem declarada”, oráculo do benchmark.

### 3.5 Aceitação (uma execução, contêiner limpo, catálogo publicado)

Antes/depois na fila publicada:

1. `ready-image` ≥ 4× o atual (66 → ≥ 264) e ativos em `Media/sha256` proporcional.
2. Cartas publicadas com imagem ≥ 2× (64/629 → ≥ 128/629) **sem** publicar nenhuma carta sem a imagem declarada.
3. Distribuição de tipo: mínimo de distância de tipo ≥ 2 **quando a oferta permitir** (áudio segue maioria; a meta é deixar de repetir a cada 2 cartas).
4. PD-4: zero pares adjacentes da mesma fonte.
5. Primeira tela e tempo até a primeira carta sem regressão (medido, não inferido).
6. Suíte do pacote e alvo nativo verdes.

## 4. O que este desenho **não** resolve (e fica declarado)

- **Composição do catálogo**: 936 áudio / 488 sem mídia / 1 vídeo em 1.425 cartas. Nenhuma permutação cria distância de tipo que a oferta não tem. Isso é curadoria/aquisição (fontes visuais e de vídeo), frente separada.
- **Durabilidade da prontidão**: relançar rebaixa tudo. Fase 2 (tabela `prepared_presentations`) fica fora desta entrega para não misturar dois riscos.
- **Vídeo**: 1 carta de vídeo no catálogo publicado; é problema de oferta, não de sequenciador.
