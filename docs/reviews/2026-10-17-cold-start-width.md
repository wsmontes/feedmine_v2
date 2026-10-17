# A largura da primeira passagem de aquisição (cold start)

Branch `perf/cold-start-width`, a partir de `main` (`37633bb3`). Todos os números abaixo são deste commit.

## O que muda

`FeedAssociation` passa a ter duas larguras, não uma:

- `steadyWorkCapacity = 2` — a largura de sempre, a da runway depois que a tela tem cartas. Não muda.
- `initialWorkCapacity = 8` — a largura da **primeira** passagem, a única que o `ColdFeedBootstrap` faz antes de
  qualquer carta existir. Configurável por execução em Debug (`FEEDMINE_INITIAL_WORK_CAPACITY=<n>`), para que a
  medição seja repetível sem rebuild. O default **8** é o valor que a tabela abaixo sustenta e que uma segunda
  medição, **pareada** (`2,8 | 8,2 | 2,8`) e com a regra de decisão fixada antes de rodar, confirmou.

Os dois caminhos são construídos pelo mesmo `acquisition(targetWorkCapacity:)`, então nenhuma outra capacidade
(observações por lote, bytes por lote, lote por execução) pode divergir entre eles.

Teto físico que a largura declarada não remove: o coordenador executa em janela deslizante de
`max(2, activeProcessorCount)` alvos. Neste Mac (8 cores) a janela é **8**; uma largura declarada de 16 é atendida em
duas ondas de 8, e a medição mostra que ela fica **mais lenta** que 8. A proposta de 48 da especificação, neste
hardware, seria no máximo 8 em voo a cada instante.

## Instrumento

`FeedLaunchWitness` (`Sources/FeedMineUI`), já usado pelas jornadas de reabertura, passa a registrar os instantes em
que a janela desenhada atingiu **1, 5 e 10 cartas** (`cards1_ms`, `cards5_ms`, `cards10_ms`), no relógio armado no
topo de `FeedMineApp.init` ("milissegundos desde esta abertura"). A jornada
`ColdStartWidthUITests.testColdLaunchRecordsTimeToFirstFiveAndTenCards` lê esse registro e imprime uma linha
`COLDSTART`; ela falha se a abertura medida não chegar a dez cartas.

## Protocolo e condições

- simulador `FeedMine UI ptBR`, `3AEA0B45-0BE6-49F1-8BAB-2591B13BBE7A`, único simulador ligado;
- **instalação nova** (`simctl uninstall com.feedmine.development`) e **namespace novo** em cada corrida;
- transporte local do próprio app (`FEEDMINE_LOCAL_FEEDS=1`): nenhuma RSS pública é contatada;
- 18 fontes elegíveis: as duas de desenvolvimento mais `FEEDMINE_FIXTURE_FANOUT=16`, **uma carta por fonte**, cada
  resposta com atraso declarado de 250 ms (`FEEDMINE_FIXTURE_LATENCY_MS`);
- 3 corridas por largura (2 controle, 8, 16), `sysctl -n vm.loadavg` antes e depois de cada uma;
- nenhum `xcodebuild`/`swift-frontend` de outro agente durante a janela de medição.

Uma corrida (`16`, a terceira original) foi **descartada por contaminação**: load1 8.24 antes e 10.85 depois, acima do
limite declarado de ~8; foi refeita com load1 6.37/5.77. Nenhum número descartado aparece nas tabelas.

### Primeira medição — tempo até 1 / 5 / 10 cartas (ms, relógio do processo)

| largura | corrida | 1 carta | 5 cartas | 10 cartas | load1 antes → depois |
|---|---:|---:|---:|---:|---|
| 2 (controle) | 1 | 2354 | 3157 | 3793 | 3.76 → 4.42 |
| 2 | 2 | 2118 | 2900 | 3480 | 4.55 → 4.46 |
| 2 | 3 | 2109 | 2884 | 3455 | 4.46 → 5.00 |
| **8** | 1 | 2157 | 2586 | 2867 | 4.76 → 5.52 |
| **8** | 2 | 2137 | 2561 | 2848 | 5.52 → 5.51 |
| **8** | 3 | 2174 | 2609 | 2889 | 5.51 → 7.49 |
| 16 | 1 | 2073 | 2876 | 2876 | 7.49 → 7.01 |
| 16 | 2 | 2121 | 2947 | 2947 | 7.01 → 8.24 |
| 16 | 3 (refeita) | 2155 | 2928 | 2928 | 6.37 → 5.77 |

### Medianas e dispersão por largura

| largura | 1 carta (mediana / amplitude) | 5 cartas (mediana / amplitude) | 10 cartas (mediana / amplitude) |
|---|---:|---:|---:|
| 2 | **2118** / 245 | **2900** / 273 | **3480** / 338 |
| 8 | **2157** / 37 | **2586** / 48 | **2867** / 41 |
| 16 | **2117** / 82 | **2928** / 71 | **2928** / 71 |

Leitura: a primeira carta não melhora com a largura (≈2,1 s é o custo de abertura; a diferença de 39 ms entre 2 e 8 é
ruído). As cartas 5 e 10 melhoram porque a primeira passagem deixa de ser o gargalo: 10 cartas caem de 3 480 ms para
2 867 ms (−613 ms, −17,6%), e a amplitude cai de 338 ms para 41 ms — o ganho não triplica a dispersão, ele a reduz.
16 não melhora 8: a janela do coordenador já é 8, e a segunda onda adiciona trabalho (2 928 ms, 61 ms pior na
mediana).

**A largura 2 já cumpre “≥10 cartas em ≤3 s”?** Não neste fixture: as três corridas do controle ficaram em
3 455–3 793 ms. A largura 8 cumpre nas três (2 848–2 889 ms). O alargamento é justificado pelo número, não pela
especificação.

Esta primeira passagem comparou grupos e não intercalou a ordem; é o que a seção seguinte corrige. Os números dela
não são reaproveitados na decisão — servem só para escolher 8 (e descartar 16) antes de se testar 2 contra 8.

## Segunda medição: pares (regra fixada antes de rodar)

A primeira passagem comparou **grupos** (três corridas de 2, depois três de 8), e a crítica é justa: os grupos não
foram intercalados, de modo que uma deriva monotônica do host (carga, caches, térmica) se confunde com o efeito da
largura. A segunda medição **emparelha** as corridas e não muda mais nada.

- Seis corridas, alternando **dentro** do par e **entre** pares: `2, 8 | 8, 2 | 2, 8`. Nenhuma das larguras ocupa
  sempre a primeira posição, então nenhuma herda vantagem de aquecimento nem de deriva.
- Cada corrida continua sendo instalação nova e namespace novo, o mesmo fixture (18 fontes, uma carta cada, 250 ms) e
  o mesmo simulador, e cada uma registra `vm.loadavg` antes e depois.
- Para cada par: **diferença emparelhada** `cards10_ms(8) − cards10_ms(2)` (e o mesmo para 1 e 5 cartas).

**Regra de decisão (fixada antes de qualquer corrida pareada):**

1. Se as três diferenças emparelhadas de 10 cartas tiverem **o mesmo sinal** e a **menor diferença absoluta** for
   maior que a **maior amplitude (max−min) das duas corridas daquele par**, a largura vencedora está estabelecida.
2. Caso contrário — sinais divergentes, ou alguma diferença dentro do ruído do próprio par — o resultado é
   **INCONCLUSIVE** e o default volta a **2**, com a tabela e a regra registradas neste documento.

A regra não tem cláusula de desempate: empate ou dúvida resolvem para 2, a largura que já existia.

Com **uma corrida por braço**, um par não tem amplitude interna (max−min de dois pontos é a própria diferença, e a
regra viraria “diferença > diferença”, insatisfazível por construção). A amplitude que este documento sempre reportou é
a de **cada largura** nas suas três corridas; é essa que a regra compara com a diferença emparelhada.

### Série A — contínua (seis corridas em sequência, 11:39–11:40)

| par | ordem | largura | 1 carta | 5 cartas | 10 cartas | load1 antes → depois |
|---|---|---|---:|---:|---:|---|
| 1 | 1º | **2** | 2303 | 3091 | **3666** | 2.80 → 13.90 |
| 1 | 2º | **8** | 2253 | 2626 | **2904** | 13.90 → 15.99 |
| 2 | 1º | **8** | 2149 | 2569 | **2852** | 15.99 → 16.66 |
| 2 | 2º | **2** | 2094 | 2859 | **3431** | 16.66 → 18.26 |
| 3 | 1º | **2** | 2110 | 2894 | **3489** | 18.26 → 18.81 |
| 3 | 2º | **8** | 2106 | 2546 | **2830** | 18.81 → 16.38 |

Nenhum `xcodebuild`/`swift-frontend` de outro agente apareceu em nenhuma amostra (verificado antes e depois de cada
corrida). O load1 sobe de 2,80 para ~18 **por causa da própria série**: cada `xcodebuild` + lançamento do runner deixa
um pico que ainda não decaiu quando a corrida seguinte começa. Foi por isso que a série foi repetida com espera (série
B), e a decisão é tomada sobre a série B.

### Série B — assentada (cada corrida só começa com load1 < 5 e sem build alheio, 11:42–11:43)

| par | ordem | largura | 1 carta | 5 cartas | 10 cartas | load1 antes → depois |
|---|---|---|---:|---:|---:|---|
| 1 | 1º | **2** | 2113 | 2890 | **3473** | 4.86 → 4.56 |
| 1 | 2º | **8** | 2131 | 2566 | **2845** | 4.56 → 4.71 |
| 2 | 1º | **8** | 2074 | 2500 | **2790** | 4.71 → 5.13 |
| 2 | 2º | **2** | 2115 | 2902 | **3482** | 4.80 → 4.51 |
| 3 | 1º | **2** | 2092 | 2877 | **3445** | 4.51 → 5.23 |
| 3 | 2º | **8** | 2057 | 2474 | **2760** | 4.96 → 5.20 |

### Diferenças emparelhadas `8 − 2`

| par | A: 1 / 5 / 10 cartas | B: 1 / 5 / 10 cartas |
|---|---|---|
| 1 | −50 / −465 / **−762** | +18 / −324 / **−628** |
| 2 | +55 / −290 / **−579** | −41 / −402 / **−692** |
| 3 | −4 / −348 / **−659** | −35 / −403 / **−685** |

Amplitude por largura nas três corridas: série A — 2: 235 ms, 8: 74 ms; série B — 2: 37 ms, 8: 85 ms.

### Decisão

| critério | A | B |
|---|---|---|
| as três diferenças de 10 cartas têm o mesmo sinal? | sim, todas negativas (8 mais rápida) | sim, todas negativas |
| menor diferença absoluta | 579 ms | 628 ms |
| maior amplitude da largura no mesmo par | 235 ms | 85 ms |
| menor diferença > amplitude? | **sim** (579 > 235) | **sim** (628 > 85) |
| veredito | 8 | 8 |

A largura **8** está estabelecida pelas duas séries, e a série assentada — a única em que todas as corridas começaram
no regime declarado — é a que decide: 628 ms de vantagem mínima contra 85 ms de ruído. O sinal também não é artefato de
ordem: 8 venceu tanto correndo primeiro (pares 1 e 2 da série B) quanto correndo depois (par 3), e a primeira carta
segue sem diferença (|diferença| ≤ 41 ms, sinal trocando entre os pares).

## Default

`initialWorkCapacity = 8` — **mantido** depois da medição pareada, que era o ponto em aberto. A regra fixada antes
de rodar foi satisfeita nas duas séries: nas seis corridas de 10 cartas a diferença `8 − 2` foi negativa em todos os
pares, e a menor diferença (628 ms na série assentada, 579 ms na contínua) ficou muito acima da maior amplitude de
qualquer largura no mesmo par (85 ms e 235 ms). Nenhuma revisão do default foi necessária: 2 continua sendo a largura
do regime estável, 16 continua descartada por ser mais lenta neste host, e 48 continua sem medição que a sustente.

**Métrica da especificação (10 cartas ≤ 3 s), medida:** a largura 2 **não** cumpre — 3 431–3 666 ms na série A e
3 445–3 482 ms na série B, seis corridas, nenhuma abaixo de 3 s. A largura 8 cumpre nas seis: 2 760–2 904 ms, com
**margem mínima de 96 ms** contra os 3 000 ms (a corrida mais lenta, 2 904 ms, foi a segunda da série contínua). A
margem é apertada por construção — 250 ms de atraso declarado por fonte com 18 fontes —, mas é positiva em todas as
corridas, e é o próprio alargamento que a cria: sem ele o controle erra o alvo por 431–666 ms.

## Regressões (contagens verbatim, refeitas nesta passagem)

| suíte | resultado |
|---|---|
| `swift test --filter FeedMineCompositionTests` | 341 testes, 0 falhas |
| `ColdFeedBootstrapTests.testC23ColdPassContactsExactlyTheStatedWidth` (nova) | 1 teste, 0 falhas |
| `swift test --filter FeedMineAcquisitionTests` | 87 testes, 0 falhas |
| `swift test --filter 'FeedMineRuntimeTests.*Runway'` | 47 testes, 0 falhas |
| `-only-testing:FeedMineAppTests/ColdStartWidthConfigurationTests` (app, 3 casos) | 3 testes, 0 falhas |
| `-only-testing:FeedMineUITests/FeedMineUITests/testContextNavigationAndSourcePickerOffline` (jornada que chega ao feed) | 1 teste, 0 falhas (63,138 s; ela relança com a rede bloqueada e exige o feed de novo) |

Nota de repetição: esse último seletor precisa do alvo **e** da classe (`FeedMineUITests/FeedMineUITests/...`). Com
só `FeedMineUITests/testContextNavigationAndSourcePickerOffline` o `xcodebuild` executa **0 testes** e ainda imprime
`** TEST EXECUTE SUCCEEDED **` — silêncio que se lê como aprovação; a contagem na tabela é a da linha "Executed".
