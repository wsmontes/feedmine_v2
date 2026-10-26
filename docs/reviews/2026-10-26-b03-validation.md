# B03 — execução de validação após a correção de continuidade (2026-10-26)

Relatório durável da execução local de 2026-10-26 no checkout `feedmine_v2`, branch `product/nf04-tail-truth`.
Nada empurrado, mesclado ou publicado.

## Veredito: NOT_RUN (não FAIL, não PASS)

O oráculo congelado julgou a corrida `bench/run/20261026T085541Z` com **NOT_RUN**: a trilha exigida (1.800 s de
avanços efetivos) nunca começou — 0 eventos `advance`. As cláusulas de repetição (0), pares consecutivos da mesma
fonte (0) e prontidão dos candidatos (726 candidatos, todos `textOnly`) passaram; as duas cláusulas da trilha ficaram
`null` porque não há intervalo a medir. O proxy mecânico de paralisação (avanço sem admissão em 1 s) segue **sem dado
novo**; a questão anterior permanece aberta, não revalidada.

Motivo da medição: `6b0497f5` mudou o insumo do gate (a ingestão durável do cold bootstrap declara o fato local ao
driver por `onDurableSupply` → `noteLocalSupplyFact()`, antes do guard de primeira publicação). O último B03
registrado era FAIL mecânico, e isso não era decisão humana de congelar classificação nem proibição de corrigir
runtime.

## Estado medido

| Item | Valor |
|---|---|
| HEAD na corrida | `547d7d80` sobre `a57cf489`/`6b0497f5`, base `8a12524b`; árvore rastreada limpa |
| `bench/**` | byte-idêntico antes e depois; digest de árvore `aabe02e6…`; `git status -- bench` vazio |
| `bench/run.sh` / `bench/oracle.py` / driver | `96627683…` / `57804e0b…` / `e411f8fc…`, iguais a `bench/EVALUATOR.sha256` |
| corpus | `catalog.sqlite 1f642eaa…`, `items.json 4bb683a7…` |
| par de catálogo do produto | asset `1825fdae…` + descritor `4cc9cba6…`, hashes inalterados; nada recompilado |
| comando | `bench/run.sh --gate B03 --full-trace` (perfil A, device dedicado do runner) |
| publicado antes do travamento | 726 cartas, 130 fontes, 767 requisições; traço 08:59:28Z→09:55:49Z, sem truncamento |
| janela admitida final | 17 cartas, âncora na cabeça, **16 cartas de runway à frente** (fato do próprio run) |
| avanços | 0 de 1.800 s |

## Impedimento real

O motorista travou em `DiscoveryBenchmarkTests.record(_:to:)` → `FileHandle(forWritingTo:)` → **`open(2)`** sobre
`bench/run/20261026T085541Z/B03-A.phases`. Medido: `B03-A.log` para em `t = 14.18 s` (última checagem 09:09:42Z)
dentro da espera de 180 s pela `ScrollView` (`DiscoveryBenchmarkTests.swift:542`), sem nenhum swipe posterior; a
primeira escrita de fase do caminho B03 é `record("neutral", to: phases)` (`:544`) e o arquivo ficou 0 byte por 46
minutos; três `sample` do processo de teste mostram a main thread no `open`. O app seguiu vivo e publicando durante o
bloqueio (traço crescendo), e a captura mostra o feed com cartas — a superfície de leitura não era o bloqueio. O mesmo
inode é gravável pelo host em 0,000 s (`open(O_WRONLY)`), sem dono em `lsof`, sem contêiner iCloud para `~/Documents`
e com 7,8 GB livres.

**Causa no kernel: não estabelecida.** O caso não foi repetido para "tentar verde" e nenhum código foi contornado.
Após 46 minutos sem progresso, o runner foi terminado (`simctl terminate` do `FeedMineUITests.xctrunner`), o que
permitiu ao `run.sh` copiar o container, rodar o oráculo e fechar a corrida.

## Próxima correção nomeada (não aplicada)

O caminho correto já existe no modo aparelho (registro de fases dentro do container + anexo no result bundle,
extraído pelo runner). No simulador o driver ainda escreve um caminho do host — foi essa escrita que travou o gate.

1. Gravar o registro de fases no diretório temporário do runner nos **dois** modos e anexá-lo; nenhuma escrita do
   processo do simulador em caminho do host.
2. `bench/run.sh`: extrair o anexo também no ramo de simulador, com o mesmo código do ramo de aparelho.
3. Fazer `record(_:to:)` incapaz de consumir o gate: escrita local e limitada, sem depender de caminho externo.

É correção de instrumento, não de produto: não muda critério, limiar, corpus nem duração. Só depois dela uma nova
execução mede o runtime corrigido.

## O que esta corrida não mostra

Não prova B03 PASS nem F06; não revalida a paralisação mecânica; não cobre perfil B, jornadas de UI nem B06; não é
release. As 16 cartas de runway são o instante anterior à caminhada, não prova de bitmap/renderização.

## Artefatos

`bench/run/20261026T085541Z/` contém `report.md`, `B03.verdict.json`, `B03-A.log`, `B03-A.png`, `container/`,
`server.log`, `build.log`, `identity.txt`, `inputs.sha256` e as checagens de manifesto/avaliador. Limite honesto: o
`run.sh` apaga `$OUT/derived` no fim (limpeza documentada do runner) e com ela o `.xcresult` desta execução; o detalhe
do XCUITest além de `B03-A.log` não sobreviveu. O `sample` do runner e a captura foram preservados antes do
encerramento, junto do traço/banco (`/tmp/feedmine-b03-preserved-20261026T085541Z`,
`/tmp/feedmine-b03-final-20261026T085541Z`, `b03-runner-sample.txt`, `b03-hang-screen.png`, `feedmine-b03-disk.log`).

## Higiene

Disco: 10,84 GB antes do build, mínimo 7,83 GB durante, 8,49 GB no fim (piso de 8 GB verificado antes do build; o
runner recusa abaixo de 3 GB). Reclamada apenas DerivedData regenerável da nossa linhagem (`/tmp/omp-reserve-fix-dd`,
`/tmp/omp-head-dd`), com logs e result bundles anteriores preservados. Nenhum simulador, banco, trace, xcresult,
backup ou artefato de outra sessão foi apagado; o device criado pelo runner ficou desligado, não apagado. O bundle do
produto nunca foi instalado nesta corrida. `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md` não foi editado: seu
SHA-256 é citado em `bench/corpus/criteria.json` e alterá-lo invalidaria a procedência congelada.
