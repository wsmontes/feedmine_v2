# B03 — duas execuções de validação após a correção de continuidade (2026-10-26)

Relatório durável das execuções locais de 2026-10-26 no checkout `feedmine_v2`, branch `product/nf04-tail-truth`.
Nada empurrado, mesclado, publicado, arquivado ou enviado ao TestFlight.

## Veredito: NOT_RUN nas duas execuções (não FAIL, não PASS)

| corrida | veredito | avanços | cartas | fontes | admitidas | janela final |
|---|---|---|---|---|---|---|
| `bench/run/20261026T085541Z` | **NOT_RUN** | **0** | 726 | 130 | 374 | 17 (âncora na cabeça, 16 à frente) |
| `bench/run/20261026T100032Z` | **NOT_RUN** | **0** | 713 | 123 | 419 | 17 (âncora na cabeça, 16 à frente) |

Cláusulas (idênticas nas duas): "1.800 s de avanço" = `null`; "zero repetição" = 0 → `true`; "zero pares
consecutivos da mesma fonte" = 0 → `true`; "zero paralisação ≥1 s" = `null`; "prontidão de cada candidato" =
726/713 candidatos, 0 pendentes, todos `textOnly` → `true`.

A trilha exigida **nunca começou** nas duas vezes. O proxy mecânico de paralisação (avanço sem admissão em 1 s)
**não ganhou dado**: a questão anterior permanece aberta, não revalidada. Isto não é PASS, não é FAIL e não é
evidência a favor ou contra `6b0497f5`; as cartas publicadas não são resultado de B03.

Motivo da medição: `6b0497f5` mudou o insumo do gate (a ingestão durável do cold bootstrap declara o fato local ao
driver por `onDurableSupply` → `noteLocalSupplyFact()`, antes do guard de primeira publicação), e o último B03
registrado era FAIL mecânico — que não era decisão humana de congelar classificação.

## Por que houve uma segunda execução

A primeira travou no runner. Para não transformar um travamento único em diagnóstico, a segunda foi rodada como
teste de **determinismo**, com regra de parada fixada antes de começar: se a assinatura congelasse na espera da
`ScrollView` por mais de 10 min, encerrar e registrar. As duas correram no mesmo SHA, mesmo corpus, mesmo runner
congelado, mesmo perfil (A), com namespaces distintos. O resultado foi registrado como veio; nenhuma repetição
buscava "verde".

## Estado medido antes do travamento (comum às duas)

Instalação limpa com o corpus do build 56: o app publica e apresenta a primeira tela com cartas reais do corpus
(`B03-A.png` nas duas corridas), e continua produzindo depois dela. `manifest: OK`, `evaluator: OK`,
`packaged labels: OK`, par do corpus injetado (`sourceCount 2305`), transporte `127.0.0.1:8757` (767 e 761
requisições nos `server.log`). Traço do app sem truncamento (`trace_truncated: null`).

## Impedimento real (determinístico nas duas)

Em ambas o motorista para no **mesmo ponto**: `t = 13.8–14.2 s`, dentro de
`app.scrollViews.firstMatch.waitForExistence(timeout: 180)` (`DiscoveryBenchmarkTests.swift:542`); a etapa seguinte
é `record("neutral", to: phases)` (`:544`), e o arquivo de fases fica **0 byte**; nenhum swipe é registrado e o
traço do app nunca recebe um evento `advance`.

Na primeira execução, três `sample` do processo `FeedMineUITests` mostram a main thread parada em
`DiscoveryBenchmarkTests.record(_:to:)` → `FileHandle(forWritingTo:)` → `_NSOpenFileDescriptor` → **`open(2)`**, por
46 minutos, com o app vivo e publicando. A segunda reproduziu o mesmo congelamento (passos de teste parados em
03:05:2x local; encerrada ~60 min depois), com novo namespace.

### Controles executados

- `open(O_WRONLY)` do mesmo inode `B03-A.phases` **pelo host**: 0,000 s.
- `simctl spawn` escrevendo um arquivo novo no mesmo diretório de corrida: **sucesso** (arquivo criado; `rc=127`
  apenas porque `date`/`cat` não existem no runtime). Não há negação geral de escrita do simulador no host.
- `log show` 09:05–09:20Z para `FeedMine`/`FeedMineUITests-Runner`: **nenhuma** negação de sandbox/TCC registrada.
- `report.md` renderiza corretamente porque `bench/oracle.py:673` escreve `$OUT/<gate>.json`; não há artefato de
  runner a registrar nesse ponto.
- Analisador de traço com controle sintético: conta parada **com** runway à frente e não confunde ausência de
  admissão com falta de oferta.

**Não estabelecido:** a causa no kernel do bloqueio de `open`. O que está provado é onde ele ocorre, que se repete
em duas execuções independentes, e que não é negação de acesso nem falta de espaço. O app nunca foi o bloqueio.

## Próxima correção nomeada (não aplicada, agora obrigatória antes de novo B03)

O caminho correto já existe no modo aparelho: registro de fases dentro do container do runner + anexo no result
bundle, extraído pelo `run.sh`. No simulador o driver ainda escreve um caminho do host — a operação que travou.

1. Gravar o registro de fases no diretório temporário do runner nos **dois** modos e anexá-lo; nenhuma escrita do
   processo do simulador em caminho do host.
2. `bench/run.sh`: extrair o anexo também no ramo de simulador, com o mesmo código do ramo de aparelho.
3. Fazer `record(_:to:)` incapaz de consumir o gate: escrita local e limitada, sem depender de caminho externo.

É correção de instrumento: não muda critério, limiar, corpus, duração nem driver de bench. Uma terceira execução sem
essa correção apenas reproduz o travamento; ela não é medição.

## Cobertura

Cumprido: instalação limpa com ≥5.000 elegíveis (perfil A tem 6.885), corpus e avaliador congelados conferidos,
`--full-trace` ligado, primeira tela com conteúdo real, produção continuando depois dela, oráculo congelado aplicado
sobre os artefatos, classificação registrada, duas execuções independentes.

Não cumprido: os 1.800 s de avanços efetivos, o padrão 1 card/s com rajadas, zero paralisação, o proxy mecânico,
perfil B, F06 e B06. Nada disso pode ser inferido do que foi medido.

## Artefatos

- `bench/run/20261026T085541Z/` e `bench/run/20261026T100032Z/`: `report.md`, `B03.verdict.json`, `B03.json`,
  `B03-A.log`, `B03-A.png`, `B03-A.phases` (0 byte, evidência), `container/`, `server.log`, `build.log`,
  `identity.txt`, `inputs.sha256`, `manifest.check`, `evaluator.check`, `totals.json`.
- Limite honesto: o `run.sh` apaga `$OUT/derived` no fim (limpeza documentada do próprio runner), e com ela o
  `.xcresult` das duas execuções. O detalhe do XCUITest além de `B03-A.log` não sobreviveu.
- Preservados em `/tmp`: `feedmine-b03-preserved-20261026T085541Z/`, `feedmine-b03-final-20261026T085541Z/`,
  `feedmine-b03-retry-preserved-20261026T100032Z/`, `b03-hang-screen.png`, `b03-runner-sample.txt`,
  `feedmine-b03-disk.log`, `feedmine-b03-disk-retry.log`, `feedmine-b03-analyze.py`, `b03-wedge-watch.py`.

## Estado do repositório e higiene

- HEAD `547d7d80` sobre `a57cf489`/`6b0497f5`, base `8a12524b`; árvore rastreada limpa, só `capacity-ready.json`
  não rastreado e intocado. `bench/**` byte-idêntico antes e depois das duas corridas (digest de árvore
  `aabe02e6…`); oráculo, `run.sh`, `serve.py` e driver iguais a `bench/EVALUATOR.sha256`; par de catálogo do produto
  `1825fdae…`/`4cc9cba6…` inalterado. `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md` não foi editado (seu SHA é a
  procedência congelada em `bench/corpus/criteria.json`); o registro de aceitação que ele cita
  (`docs/evidence/ACCEPTANCE_RECORD.md`) não existe nesta árvore.
- Disco: 10,84 GB antes da 1ª; 8,19 GB antes da 2ª; mínimo amostrado 6,79 GB; 8,55 GB no fim. Reclamada apenas
  DerivedData regenerável da nossa linhagem, com logs e bundles anteriores preservados. Nenhum simulador, banco,
  trace, xcresult, backup ou artefato alheio apagado; o device criado pelo runner ficou desligado, não apagado; o
  bundle do produto nunca foi instalado.
