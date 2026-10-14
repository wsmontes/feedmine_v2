# B01 PASS no HEAD, e o deadlock que parava o feed (2026-10-14)

Commit verificado: `326bb45cb28befa95b60992416adee9208d4aac5` (`dirty files: 0`), corpus e oráculo
congelados, dispositivo dedicado `FeedMine Bench`. Corrida `bench/run/20261014T071443Z`.

## O que estava quebrado

`C4edf3bc` (o desacoplamento da lista, 2026-10-13) trocou o significado de `NativeFeedViewport.presented`:
antes era o valor que a view **seguia** — `capture.interaction.presentation(for: store)`, ou seja a janela
**segurada** durante um gesto — e passou a ser `store.state.presentation`, a **publicada**.

`matchesScope` continuou comparando `interaction.presentation(for: store)?.window == presented.window`.
Durante um gesto, `presentation(for:)` devolve a janela segurada (edição, contexto e sequência ainda batem),
enquanto `presented` já é a publicada: a **primeira atualização de janela** que chega durante o gesto torna a
comparação falsa para todo o resto do hold. E a saída do hold (o ramo `phase == .idle` do
`onScrollPhaseChange`) mora **atrás daquele mesmo guard** — logo nunca executa. O hold não termina, o
`onScrollGeometryChange` também é rejeitado (`scopeRejections`), e sobra só o caminho por card, que depende de
`motion.geometry` (congelado). O leitor rola, a tela anda, e **o backend nunca fica sabendo**: sem posição não
há reposição, o feed publica o bootstrap e para.

Medido com o reprodutor determinístico
`FeedMineUITests/ArticleReadingDiagnosisUITests/testFastFlingWindowChangesDoNotWriteIntoAnActiveGesture`
(8 flings rápidos, `FEEDMINE_TRACE_CAPTURE=1`, fixture de 95 cards) — antes × depois da correção:

| Contador | antes | depois |
|---|---:|---:|
| `emits` / `submits` | 1 / 1 | **45 / 45** |
| `deferredWindows` | 1 | **36** |
| `geom` (callbacks de geometria do scroll) | 10 | 750 |
| `probes` / `guards` / `cards` | 72 / 72 / 72 | 10.986 / 10.986 / 10.739 |
| `geomEvents` / `phaseEvents` | 10 / 4 | 720 / 33 |
| `installs` (tentadas/aceitas/rejeitadas) | 13/13/0 | 122/122/0 |
| `activeWrites` · `activeWindows` · `activeLayoutStep` | 0 · 0 · 0 | **0 · 0 · 0** |
| `corrections` / `residual` / `visualResidual` | 0 / 0 / 0 | 7 / **0.000000** / **0.000000** |

Os três zeros e o resíduo zero são o contrato de estabilidade que a fluidez exige: nada é escrito no offset
nativo durante o gesto, a janela desenhada não muda sob o dedo e nenhum card salta.

## Correção

`e78b691a` — uma linha: `presented` volta a ser `capture.interaction.presentation(for: store)`, **ainda lida
dentro do modificador**. O motivo do desacoplamento continua preservado: quem reavalia por avanço é o
modificador (barato), não o corpo da lista, que desenha os itens publicados.

`326bb45c` — a cadência de convites aprovada pelo PO: a **primeira** resposta da sessão volta o próximo
intervalo ao primeiro convite (4 cards) em vez do intervalo base (12). Da segunda em diante vale o intervalo
base, para que um leitor que responde a cada convite continue lendo um feed e não preenchendo um questionário.
Teto de 4 ofertas por sessão, um assunto por oferta e uma colocação por vez seguem valendo. Motivo medido na
corrida anterior: a segunda oferta só era apresentada aos 19 cards, ~54 s depois da primeira, enquanto o
percurso congelado procura a segunda por cerca de 30 s de leitura e desiste.

## Prova: B01 A+B PASS

| Cláusula | Antes (`6e9b02d8`) | Agora (`326bb45c`) |
|---|---|---|
| 1 — jornada nas duas fases, nos dois perfis | NOT_RUN (nenhum assunto) | **PASS** — A: `world-news`, `family-parenting`; B: `software-computing`, `earth-life-sciences` |
| 2 — não depende das quatro fontes padrão | PASS | PASS (`[]`) |
| 3 — ≥50 fontes no conjunto de aquisição | PASS (180) | PASS (**271**) |
| 4 — ≥20 fontes contribuindo nos primeiros 300 cards | **FAIL (5)** | **PASS (40)** |
| 5 — outro perfil muda o conjunto | PASS | PASS (a:271 b:365, iguais:0) |

Estados: 271 registradas · 298 consultadas · **40 contribuindo** · **202 cards publicados**
(antes: 180 · 240 · 5 · 34). Fases do perfil A: `neutral`, `answered:world-news`,
`answered:home-living/family-parenting`, `thematic-attempted`, `hide-stable:true`, `hide-frames:234->234`.

Evidência: `docs/reviews/evidence/2026-10-14-b01-pass/` (`B01.json`, `report.md`, fases de A e B,
`identity.txt`). Suíte do pacote no mesmo commit: **1.255 testes, 1 skipped, 0 falhas**.

## O que isto NÃO prova

- **B02, B03, B04, B05, B06 seguem NOT_RUN** nesta baseline. B03 (30 minutos de avanço contínuo) nunca foi
  executado nesta máquina e é o próximo da fila; B06 exige iPhone físico (memória, energia, térmica, hitches).
- 202 cards publicados é a medida do percurso de B01 (primeiros 300), não da capacidade de sustentar 30
  minutos: a oferta contínua é exatamente o que B03 mede.
- O ganho de cadência foi provado em regra (testes de unidade) e no percurso congelado; a frequência agregada
  de ofertas num trace longo ainda não foi medida.
