# A largura da primeira passagem de aquisição (cold start)

Branch `perf/cold-start-width`, a partir de `main` (`37633bb3`). Todos os números abaixo são deste commit.

## O que muda

`FeedAssociation` passa a ter duas larguras, não uma:

- `steadyWorkCapacity = 2` — a largura de sempre, a da runway depois que a tela tem cartas. Não muda.
- `initialWorkCapacity = 8` — a largura da **primeira** passagem, a única que o `ColdFeedBootstrap` faz antes de
  qualquer carta existir. Configurável por execução em Debug (`FEEDMINE_INITIAL_WORK_CAPACITY=<n>`), para que a
  medição seja repetível sem rebuild. O default **8** é o valor que a tabela abaixo sustenta.

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

### Tempo até 1 / 5 / 10 cartas (ms, relógio do processo)

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

## Default

`initialWorkCapacity = 8`. É a largura que atinge dez cartas em menos de 3 s nas três corridas e tem a menor
dispersão; 16 é descartada por ser mais lenta neste host, e 48 não é adotada por não haver medição que a sustente.

## Regressões (contagens verbatim)

| suíte | resultado |
|---|---|
| `swift test --filter FeedMineCompositionTests` | 341 testes, 0 falhas |
| `ColdFeedBootstrapTests.testC23ColdPassContactsExactlyTheStatedWidth` (nova) | 1 teste, 0 falhas |
| `swift test --filter FeedMineAcquisitionTests` | 87 testes, 0 falhas |
| `swift test --filter 'FeedMineRuntimeTests.*Runway'` | 47 testes, 0 falhas |
| `ColdStartWidthConfigurationTests` (app, 3 casos) | 3 testes, 0 falhas |
| `FeedMineUITests/testContextNavigationAndSourcePickerOffline` (jornada que chega ao feed) | 1 teste, 0 falhas (63,006 s; ela relança com a rede bloqueada e exige o feed de novo) |
