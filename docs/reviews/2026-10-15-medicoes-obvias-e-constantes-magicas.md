# Medições óbvias ancoradas na jornada — e as constantes mágicas que podem ser apagadas

**Data:** 2026-10-15. **Revisor:** agente `ObviousBench` (tarefa delegada pelo ORCH). **Números:** `arquivo:linha`
do repositório `/Users/wagnermontes/Documents/GitHub/feedmine_v2` **naquela data** — a régua congelada muda por
protocolo, e uma linha citada aqui pode não ser a mesma linha amanhã.

**Natureza:** revisão de leitura. Nada foi executado além de leitura de arquivos e `shasum -a 256 -c`
(verificação de hashes, somente leitura). Nenhum arquivo de `bench/**`, oráculo, critério, corpus ou código de
produto foi tocado para escrever isto.

---

## 0. Inventário revisado, e o que está congelado

**Avaliador (fonte de verdade dos gates):** `bench/oracle.py` (682 l.), `bench/run.sh` (591 l.),
`bench/corpus/criteria.json`, `bench/expand.py` (76 l.), `bench/serve.py`, `bench/README.md`, `bench/REFERENCE.md`;
contrato em `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md`; proposta antiga em
`docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK_PROPOSAL.md` (declara-se substituída, 3 linhas).

**Verificação feita na sessão (leitura):** `shasum -a 256 -c bench/EVALUATOR.sha256` → **6/6 OK**, cobrindo
`bench/run.sh`, `bench/oracle.py`, `bench/serve.py`, `bench/build_corpus.py`, `bench/expand.py` e
`FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift`.

**Duas contradições documentais que a proposta precisa herdar corrigidas:**

1. `docs/evidence/ACCEPTANCE_RECORD.md` (item "o que continua aberto") afirmava que *"uma cláusula do oráculo
   passa medindo nada… **Não corrigida ainda de propósito**"* e que *"a régua que mede a expansão não está
   congelada"*. O estado atual do repositório diz o contrário: a não-vacuidade **está** implementada em
   `bench/oracle.py:357-378` (sem candidatos examinados o veredito é `None`, não `PASS`) e `bench/expand.py`
   **está** congelado (`bench/EVALUATOR.sha256:5`). O registro foi corrigido com data e proveniência pelo ORCH em
   **2026-10-15**, como o §5.1 deste relatório pediu — ver a nota final.
2. `bench/REFERENCE.md` mantém o histórico de revisões do avaliador (v2, v3, correção de B05, preservação do
   traço) — é a única fonte que explica *por que* cada limiar existe. Qualquer proposta de limiar novo tem de ser
   escrita lá no mesmo formato, senão vira limiar sem história.

**Estudos:** `docs/v1-study/05-ui-app-quality.md` (constantes de watermark da V1, lição sobre testes tolerantes),
`docs/v1-study/06-history-lessons.md` §5 (alvos medidos da V1), `docs/v1-study/01-feed-pipeline.md` (FP-7/FP-9),
`docs/v1-study/02-ingestion-network.md`, `docs/v1-study/03-media.md`.

**Comparativos:** `docs/reviews/CODE_REVIEW_COMPARATIVO_2026-10-09.md` (F01–F16, critérios de aceite por achado),
`docs/research/deep-research-report-v1-v2-gap-audit-2026-10-13.md` (tabela final `Métrica | Medida recomendada |
Critério`), `docs/research/deep-research-report-ui-fluidity-v1-b5c2f59-2026-10-13.md` (as três métricas
não-probabilísticas), `docs/reviews/F06_COMPARATIVE_FEED_STABILITY_RESEARCH_2026-10-10.md`,
`docs/reviews/2026-10-13-scroll-stability-measurement.md`,
`docs/reviews/2026-10-15-runway-deficit-medido-e-oportunidade.md`.

---

## 1. A régua: o que torna uma medição *óbvia* em vez de interpretativa

Três perguntas, aplicadas a cada medição proposta:

| # | Pergunta | Se a resposta for "sim" |
|---|---|---|
| Q1 | O observável é um **fato do que o leitor viu/percorreu** (card desenhado, avanço, posição reaberta) e não um proxy interno (contador de chamada, reavaliação de `body`)? | medição ancorada na jornada |
| Q2 | O veredito é **binário** — 0/1, igualdade de identidade, conjunto vazio — sem um número escolhido por alguém? | medição não-interpretativa |
| Q3 | É possível mudar o número de aceitação **sem tocar no produto** e inverter o veredito? | então é interpretativa: o número tem de sair da cláusula |

O próprio relatório de fluidez fixou essa distinção antes desta revisão, em
`deep-research-report-ui-fluidity-v1-b5c2f59-2026-10-13.md:762`: *"Os valores de performance — p95, p99 e limites
de memória — devem ser derivados do baseline em devices reais, não escolhidos arbitrariamente. Já a correção
lógica de stale/terminal publication pode e deve ser binária."* E fixou o formato do veredito absoluto em
`:768-775` (`emptyTerminalThenContent == 0`).

Duas medições do benchmark atual **falham Q2** — e é por isso que existem no lugar das óbvias:

- **B02 "≥80% dos 200 cards relevantes"** (`bench/oracle.py:275`): um leitor pode receber 159/200 cards fora do
  perfil e PASS. A jornada equivalente — "todo card desenhado tem uma ação primária resolvível e pertence ao que
  foi declarado" — é binária e não precisa de percentual.
- **B03 "zero paralisação ≥1 s"** (`bench/oracle.py:354`): o 1,0 s é escolhido; a regra *"o leitor avançou e o app
  não ganhou nada novo"* é binária. A fração de 1 s é o que permite "30 minutos aprovados com exceção".

E o oráculo já **aprendeu na própria carne** por que vaciedade é o pior defeito (`bench/oracle.py:357-378`,
comentário: *"this clause returned PASS with 871 candidates and 0/0/0 labels"*). Essa regra — cláusula sem medida
= `NOT_RUN`, nunca `PASS` — deve valer para **todas** as medições novas.

---

## 2. Medições propostas (âncora: jornada → observável → veredito)

Cada linha diz **o que já existe hoje** no repositório, porque quase nada abaixo exige instrumentação nova: o
`ReplenishmentTrace` (`Sources/FeedMineDomain/ReplenishmentTrace.swift`) já declara o vocabulário
(`replenishment_requested` / `replenishment_arrived` / `replenishment_concluded` / `trace_truncated`) e o host já
grava `admitted`, `advance`, `window`, `editorial_offer`, `editorial_refusal`, `position_checkpoint`,
`position_kept_exact`, `frames`, `runway_completed`
(`FeedMineApp/FeedMineApp/AppComposition.swift:1337-1379,2346-2349,2578-2579,2631-2632,2689-2693`).

| # | Jornada | Observável (fato bruto) | Evidência já existente | Veredito | Substitui |
|---|---|---|---|---|---|
| **M1** | *Abrir o app* | Transições de superfície na **mesma geração**: `empty → conteúdo` (contagem de cartas desenhadas > 0 depois de a superfície ter declarado vazio) | trace `window`/`admitted`; UI: `FeedMineAppTests/EndOfContentUITests.swift`, `FeedMineUITests.swift:201` (`testCleanInstallPresentsTheBundledCatalogueSourceWithTransportBlocked`) | `empty_then_content == 0` (o número do relatório de fluidez, `:677-680`) | `waitForExistence(timeout: 180)` como prova de que o app abriu (`DiscoveryBenchmarkTests.swift:318`) |
| **M2** | *A primeira tela tem história* | Toda carta admitida tem `source_id` conhecido **e** referência de ação primária resolvível | já é cláusula parcial em `bench/oracle.py:285-287` (`lane < len(published)` ⇒ FAIL) | `cards_sem_fonte == 0` e `cards_sem_destino == 0` | a média de relevância de B02 |
| **M3** | *Rolar* | Cada `advance` do trace atinge **card distinto novo** (identidade comparada com as já vistas) | trace `advance` (`AppComposition.swift:2578`) + ordem do leitor (`bench/oracle.py:98`) | `repetições == 0`, `avanços == cartas_distintas` | `len(advances) >= 1_800` (`bench/oracle.py:362`) |
| **M4** | *Rolar com mídia chegando* | Nada **acima** da âncora muda: cabeça da lista instalada, ordem e cauda | `admitted_series` / `admitted_violations` (`bench/oracle.py:381-452`) — hoje já julga sobre o registro do próprio app, não do driver | `head_forward == 0 ∧ shrunk == 0 ∧ tail_back == 0 ∧ holes == 0` | as medições `b04-*-stable` do driver (`DiscoveryBenchmarkTests.swift:512-518`), que são leitura posicional de XCUI |
| **M5** | *As imagens aparecem* | Toda carta com mídia **declarada** é desenhada com asset local; as demais, desenhadas text-only **por desenho** (`MediaPolicy.fit`, `Sources/FeedMineMedia/MediaPolicy.swift:129-131`) | `MediaPrefetcher` + `MediaReadiness`; teste de suspensão citado em `ACCEPTANCE_RECORD.md` | `cards_com_imagem_faltando == 0` (a "imagem faltando" é o estado que PD-5 proíbe) | nada: hoje não há medição de jornada para isto (o `ACCEPTANCE_RECORD.md` diz explicitamente que o PASS do B03 **não prova** F06-A/F06-B) |
| **M6** | *Chegar ao fim* | O fim de feed só aparece com `supply local esgotado` verdadeiro | `FeedEndOfContentView`, `EndOfContentUITests.swift:33` | `fins_com_supply_disponível == 0` | o `1_800 avanços` como proxy de "não acabou" |
| **M7** | *Fechar e reabrir* | A âncora reaberta **é** a âncora gravada (`context_checkpoints` + último `position_checkpoint`) | `durable_position` (`bench/oracle.py:521-547`) + `b05-reopen-preserves-anchor` | igualdade de identidade: `âncora_gravada == primeira_carta_desenhada` | as esperas de 30–60 s e os `Thread.sleep` do driver (`DiscoveryBenchmarkTests.swift:697-707`) |
| **M8** | *Sem rede* | Com transporte bloqueado (`FEEDMINE_BLOCK_RSS_NETWORK=1`), há história local legível e a carta salva abre | `FeedMineUITests.swift:791` (`testOfflineRelaunchKeepsFilterSavedCardAndFeed`), `ReadingSurfaceUITests.swift:90` (`testStoredContentIsReadableWithTheDeviceActuallyOffline`) | `cards_locais > 0 ∧ carta_salva_abre` | — (já é binário; só precisa entrar no relatório de aceitação como cláusula, não como screenshot) |
| **M9** | *Primeiro uso sem assinatura* | Conjunto de aquisição ≠ as quatro fontes padrão | `STARTER_KEYS` e cláusula `bench/oracle.py:195-198` | `fontes_padrão == único conjunto ⇒ FAIL` (já é binário) | — |
| **M10** | *Rolar rápido* | Série de frames: `frames, late, bad, severe, worst_ms, budget_ms` por segundo | `FeedMineApp/FeedMineApp/FeedFrameMeter.swift` (já em produção no host) | **relatar a série; sem limiar** — o limiar é baseline de aparelho, não critério | o adjetivo "fluid" sem número |
| **M11** | *Deixar o app aberto 30 min* | Fontes **novas no fim** das janelas (não no começo) | `bench/expand.py` (congelado) | `last_window_new > 0` — é a condição de aceitação que o próprio `ACCEPTANCE_RECORD.md` já escreveu | o `distinct_sources` total |
| **M12** | *Abrir o app (tempo)* | p50/p95 de `launch → primeiro card admitido`, carimbado **pelo app** (o trace grava no instante medido: `ReplenishmentTrace.swift`, cabeçalho) | não existe hoje; a V1 tem os alvos (`docs/v1-study/06-history-lessons.md:64`: 234 ms quente / 28,5 s frio para 20 cards) | p50/p95 de ≥30 execuções, comparados entre builds | `timeout: 180` como invisibilidade do problema |

**Ordenação por valor (o que escrever primeiro):** M1, M3, M7, M5, M6, M2, M4, M8, M12, M11, M10, M9.

M1/M3/M7 são as três que o dono do produto descreve com as próprias palavras ("o app abre", "as imagens
aparecem", "volta onde eu estava") e as três que hoje só têm `waitForExistence` com timeout generoso ou leitura
posicional do driver.

---

## 3. Constantes mágicas

### 3.1 Deletáveis **agora** — produto, host e instrumentação (sem tocar em nada congelado)

| Constante | Onde | Valor | O que a substitui |
|---|---|---|---|
| `backwardWindowCards` / `forwardWindowCards` | `FeedMineApp/FeedMineApp/AppComposition.swift:1861-1862` | `8` / `16` | capacidade derivada do viewport medido + velocidade (a própria `FeedPresentationBounds` já é passada como valor; o literal é que é arbitrário) |
| `runwayMinimumReserveCards` | `AppComposition.swift:1869` | `32` | já há uma fórmula medida (`RunwayPolicy`, `p95 × safetyFactor + releaseMargin`) — o piso só deveria existir **antes** da primeira amostra (é o que o próprio comentário em `:1864-1868` admite) |
| `examinedCandidateCapacity: 32, readyProbeBound: 32, readyProbeCeiling: 256, forwardAdvanceProbeBound: 256` | `AppComposition.swift:1910-1911` | 32/32/256/256 | limites operacionais (INV-04 permite), mas os **quatro** são o mesmo tipo de número e dois são o mesmo valor: derivar de `forwardWindowCards` + limite de trabalho, como `reserveCards` já faz (`:1916`) |
| `safetyFactor: 1.2`, `releaseMarginSeconds: 2` | `AppComposition.swift:2146-2147` | 1,2 / 2 s | `releaseMarginSeconds` deve sair da p95 medida; `1,2` só se justifica como margem operacional declarada — hoje é literal |
| `consumptionSampleLimit: 8, replenishmentSampleLimit: 8` | `AppComposition.swift:2148-2150` | 8 / 8 | derivar de janela temporal (últimos N segundos), não de N amostras |
| `localRetryBaseSeconds: 1` | `AppComposition.swift:2151` | 1 s | já derivável do tempo de uma operação local medida |
| `mediaWaitBootstrapSeconds = 5.0` | `AppComposition.swift:2252` | 5 s | aceitável **apenas** como bootstrap declarado (o comentário o declara); depois da primeira amostra é `mediaWaitSeconds` (`:2254-2258`) — ou seja, é uma constante de partida, e deve ser a **única** com esse estatuto |
| `backgroundAllowanceSanityCeiling = 600` | `AppComposition.swift:2243` | 600 s | não é estratégia (o comentário diz isso); é teto de sanidade e pode ficar — mas é candidato a sair se `backgroundTimeRemaining` já se comporta |
| `growthFollowUpAttempts = 8`, `growthFollowUpSeconds = 0.75` | `AppComposition.swift:2380-2381` | 8 / 0,75 s | polling; o próprio projeto proíbe timer por conveniência (regra 7) — substituir por evento de publicação |
| `coldRetryFallbackSeconds: Double = 20` | `AppComposition.swift:2500` | 20 s | já é derivado de `configuration.timeoutIntervalForRequest` na linha anterior (`:2113`); o literal `20` é uma segunda fonte |
| `supplyHeadLimit: 32` | `AppComposition.swift:2769` | 32 | mesmo número de `examinedCandidateCapacity`; uma fonte só |
| `maximumDownloadBytes: 12_000_000`, `maximumPixelSide: 12_000`, `maximumPixelCount: 50_000_000` | `AppComposition.swift:2866-2867` | 12 MB / 12k px / 50 MP | são tetos de segurança de decoder e **devem** ficar — mas os três são o mesmo tipo de número: declarar a origem única (o estudo da V1 fixa "12 MB hardened", `docs/v1-study/06-history-lessons.md:100`) |
| `config.timeoutIntervalForRequest = 20` | `AppComposition.swift:172` | 20 s | teto operacional; hoje é também o base do backoff (`:2087-2088`) — um número fazendo três papéis |
| buckets `×1.5 / ×2 / ×3` e `1000.0/60.0` | `FeedMineApp/FeedMineApp/FeedFrameMeter.swift` | 1,5/2/3 e 16,67 ms | o próprio arquivo já lê o orçamento do display (`link.targetTimestamp - link.timestamp`, com piso `1/120`); o `flush` volta para `1000/60` — **duas** definições de orçamento no mesmo arquivo; e os buckets devem virar `hitch_duration` do Instruments (que `scripts/b06-evidence.sh` já exporta) |
| `transientRetryBaseSeconds: Double = 30` | `Sources/FeedMineRuntime/MediaPrefetcher.swift:123` | 30 s | derivar do orçamento de espera de mídia medido |
| `headlineCapacity: Int = 12` | `Sources/FeedMineRuntime/PreparationProgress.swift:32` | 12 | capacidade de exibição, não de política |
| `lookupByteCeiling = 1_000_000`, `requestTimeout: TimeInterval = 8`, `probeTimeout = 5`, `discoveryDeadline = 8`, `resolutionConcurrency = 5`, `probeConcurrency = 3` | `Sources/FeedMineSyndication/FeedLinkResolver.swift:75-80` | 1 MB / 8 s / 5 s / 8 s / 5 / 3 | 8 s aparece três vezes com três nomes; concorrência de 5 e 3 competem com `max(2, cores)` usado no resto do app (`AppComposition.swift:2090,2104`) |
| `ceiling: Int = 5_000` / `20_000` / `16` | `Sources/FeedMinePersistence/LegacyCatalogReader.swift:294,329,527` | 5000 / 20000 / 16 | tetos de consulta legítimos (bounded), mas **duplicados** em `SourceManagementCoordinator.swift:141,150` (500 e 20 000) — mesma decisão em dois arquivos |
| `while candidates.count < limit * 4`, `limit: 500`, `min(perTopicCeiling, keyCeiling)` | `Sources/FeedMineComposition/ReaderDiscoveryPool.swift:150-151,164-165` | ×4 / 500 | o `* 4` é fator arbitrário de compensação; substituir por "até fechar o limite ou esgotar a página" |
| `localWindowCapacity: Int = 8` | `Sources/FeedMineComposition/ColdFeedBootstrap.swift:44` | 8 | mesmo 8 da janela de apresentação — uma fonte só |
| `EditorialInvitationCadence.Budget` | `Sources/FeedMineUI/EditorialInvitationCadence.swift:71-72` | `4 / 12 / 2 / 96 / 4` | **este é o caso-limite**: o comentário (`:57-58`) admite que os números existem para caber no passo do driver de aceitação — ou seja, uma constante de avaliação virou comportamento de produto. Ou o produto deriva o intervalo de exposição real medida, ou o número é declarado critério (e então vai para `criteria.json`, não para o default do produto) |
| `exponent = Double(min(count - 1, 62))` | `Sources/FeedMineAcquisition/AcquisitionBackoff.swift:22` | 62 | teto numérico para não estourar `pow`; declarar como limite de representação, não de backoff |
| `if index == 0 \|\| index == 8` | `Sources/FeedMineUI/Reader/ReaderHeader.swift:139` | 8 | divisor desenhado a cada 8 itens sem nome e sem dono |
| tolerâncias do driver: `steps: Int = 8` (`:174`), `0..<20` (`:202`), `swipes: Int = 30` (`:238`), `0..<8` (`:296`), `0..<6` (`:315`), `0..<12` (`:336`), `walked < 20` (`:356`), `deadline 120` (`:426`), `240` (`:624`), `frame.height > 40` (`:602`), `prefix(3)` (`:605`), `Thread.sleep 0.4/0.5/1.5/2/2.5/3/4/5/12` (`:186,212,225,349,358,366,386,401,481,490,499,543,562,567,577,579,663,673,677,680,697,707,717,767`) | `FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift` | vários | cada `sleep` é uma aposta de latência; substituir por **espera de condição** (`XCTNSPredicateExpectation`, já usado em `:704-706`). Isto não é cosmético: um `sleep` de 3 s pode transformar "o app não publicou" em "o app publicou depois" |
| `overflow` no warm-up e na validação | `scripts/b06-evidence.sh:245` (`+300`), `:391-392` (`-5`) | 300 s / 5 s | aquecimento de 300 s para "tendência" e tolerância de 5 s na janela; derivar do `record_seconds` declarado |
| `UNITS = {… 'kb':1000, 'kib':1024 …}` | `scripts/b06-evidence.sh:163-164` | — | não é constante mágica (é conversão), mas é o ponto onde uma unidade errada vira um número plausível — manter e **não** simplificar |

**Não são constantes a apagar** (para evitar a poda errada): tokens de design
(`Sources/FeedMineUI/FeedDesignTokens.swift`: 6/8/12/16/16/24/28 pt e raios 8/12/14) são decisão visual com nome;
tetos de segurança de mídia (`MediaSafetyCeilings`) são limite de recurso; `max(2, activeProcessorCount)`
(`AppComposition.swift:2090,2104`) é limite derivado do aparelho, não magic.

### 3.2 Congeladas — **não** deletáveis sem o protocolo de revisão (`bench/revisions/` + `EVALUATOR.sha256` novo + controle positivo)

Estas são régua, não código. Apagá-las muda o que se mede e invalida a comparabilidade de todos os vereditos já
registrados:

| Constante | Onde | Papel |
|---|---|---|
| `STARTER_KEYS` (4 URLs BBC/NPR/Guardian) | `bench/oracle.py:35-39` | nomeia o que a descoberta não pode depender |
| `≥50` fontes no conjunto de aquisição | `bench/oracle.py:204` | limiar de B01 |
| `[:300]` primeiros cards + `≥20` fontes | `bench/oracle.py:174,210` | limiar de B01 |
| `[:200]` + `≥80%` + `≥20` + `≤15%` | `bench/oracle.py:245,275,277,279` | limiares de B02 |
| `1_800` avanços | `bench/oracle.py:362` | limiar de B03 |
| `≥1.0 s` de paralisação | `bench/oracle.py:354` | definição de B03 |
| `2147483647` (sentinela de `COALESCE`) | `bench/oracle.py:98,406` | ordem do leitor |
| baseline 1 card/s, burst 3/20 s a cada 300 s, 1800 s, 2000–2040 avanços | `bench/corpus/criteria.json` (`trace`) e `DISCOVERY_ACCEPTANCE_BENCHMARK.md` §3-B03 | forma do trace |
| `window_seconds = 300.0` | `bench/expand.py:26` | janela da expansão |
| `FREE_KB < 3145728` (3 GB) | `bench/run.sh:131` | recusa de disco (justificada por medição: `:126-129`) |
| porta `8757` | `bench/run.sh:65,368,374,376` | endereço do transporte |
| `sleep 1` antes do `/totals` | `bench/run.sh:381` | espera do servidor; único `sleep` do runner e candidato legítimo a virar espera de prontidão |

**Proposta para as de 3.2:** não apagar. Para as que falham Q2 (`≥80%`, `≥20`, `≤15%`, `1_800`, `≥1 s`), o caminho
correto é o que já foi usado em 2026-10-14 para a adjacência: **medição nova ao lado da antiga**, com controle
positivo injetado, ambos descritos em `bench/revisions/`, e a nota de que os vereditos antigos não são
comparáveis. Isso é decisão de arquiteto, não deste relatório.

### 3.3 Constantes duplicadas — o defeito barato de corrigir

| Número | Cópias | Risco |
|---|---|---|
| 30 min / 300 s / burst 3 / 20 s / 1 por s | `bench/corpus/criteria.json` **·** `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md` §3-B03 **·** `DiscoveryBenchmarkTests.swift:756-758` (`elapsed.truncatingRemainder(dividingBy: 300) < 20`, `advances = inBurst ? 3 : 1`) | o driver **reimplementa** o critério; mudar o documento não muda o trace |
| 300 s | `bench/expand.py:26` **·** `scripts/b06-evidence.sh:245` | duas janelas de 5 min com sentidos diferentes |
| 8 e 16 | `AppComposition.swift:1861-1862` **·** `ColdFeedBootstrap.swift:44` **·** teste de reserva `CompositionTests.swift:1788` (`acima do teto de 16`) | o teste fixa o literal em vez de ler a fonte |
| 20 000 / 500 | `LegacyCatalogReader.swift:294,329` **·** `SourceManagementCoordinator.swift:141,150` | idem |
| 5 s (resume de playback) | `PlaybackTests.swift:96` cita "V1's own five seconds" | critério herdado sem dono no código V2 |

---

## 4. Onde a bateria hoje mede nada, ou tolera a ausência do sujeito

1. **Vaciedade já corrigida e congelada** (`bench/oracle.py:357-378`; `bench/expand.py` em
   `bench/EVALUATOR.sha256:5`) — o registro (`ACCEPTANCE_RECORD.md`) dizia o contrário e foi corrigido pelo ORCH
   em 2026-10-15, com data e proveniência. Este parágrafo existe para que ninguém decida sobre a versão velha.
2. **Escapes tolerantes nos testes de jornada V2** — o padrão existe:
   `FeedMineAppTests/EditorialOfferBudgetUITests.swift:137` (`guard feed.exists else { return }`) retorna sem
   asserção prévia. Onde o `guard` vem **depois** de um `XCTAssert` (ex.: `FeedMineUITests.swift:940-957`) não há
   defeito; onde vem antes, o teste passa com o sujeito ausente — exatamente o vício que a própria análise da V1
   condenou (`docs/v1-study/05-ui-app-quality.md:102-105`: *"`guard timeline.exists else { return }` … toleram um
   feed vazio"*).
3. **`waitForExistence(timeout: 180)`** como prova de que o app abriu (`DiscoveryBenchmarkTests.swift:318`) e
   `timeout: 120` em dezenas de esperas: o timeout não mede nada, só espera.
4. **B04/B05 mediram-se pelo driver antes de se medirem pelo app** — já corrigido no oráculo
   (`oracle.py:381-452` e `:521-547`); a lição vale para todo medidor novo: **a testemunha é o registro durável do
   app, não a leitura da árvore de acessibilidade.**

---

## 5. O que fazer, em ordem, e o que isso custa

1. **Corrigir os registros velhos** (`docs/evidence/ACCEPTANCE_RECORD.md`) — feito pelo ORCH em 2026-10-15.
2. **Implementar M1, M3, M7, M5, M6 e M2** como cláusulas de jornada lidas do trace e do banco do app — **sem
   mexer em `bench/oracle.py`**: são um instrumento novo em `bench/` (como `expand.py` foi), com hash próprio. Se
   um instrumento novo pode nascer com hash próprio sem tocar no oráculo é, hoje, **proposta em avaliação** pelo
   arquiteto — não decisão tomada (ver nota final).
3. **Deletar as constantes de 3.1** em PRs pequenos, cada uma com a fonte que a substitui
   (derivada/medida/declarada) — começando pelas duplicatas de 3.3, que são a maior fonte de divergência
   silenciosa.
4. **Só então** propor a substituição de limiares congelados (3.2), pelo protocolo de `bench/revisions/` com
   controle positivo.

A tese, em uma linha: **nenhuma das doze medições propostas precisa de um número novo; quatro delas precisam de um
número a menos.** O que falta hoje não é régua — é olhar para o que o leitor viu, e não para o que o driver
conseguiu consultar.

---

## 6. Notas posteriores (2026-10-15, depois deste relatório)

1. **Instrumento novo de jornada em `bench/` com hash próprio, sem tocar no oráculo:** o arquiteto (ChatGPT)
   sinalizou essa direção, mas **ainda está pendente de confirmação explícita dele** — trate como **proposta em
   avaliação**, não como decidido. Até a confirmação, o §5.2 permanece uma proposta.
2. **Vaciedade e congelamento do instrumento de expansão — fato consumado:** a verificação de não-vacuidade
   **já está** implementada em `bench/oracle.py:357-378` (`if candidates else None`) e `bench/expand.py` **já
   está** congelado em `bench/EVALUATOR.sha256:5`. Conferido por leitura, e o registro
   `docs/evidence/ACCEPTANCE_RECORD.md` foi corrigido pelo ORCH em **2026-10-15** com data e proveniência, como o
   §5.1 pedia. Quem ler o registro antes dessa correção lê informação velha.
