# Gates e integração de branches — rodada de 2026-10-14

Levantamento executado localmente (Mac do arquiteto), papel **executor de verificação**: apenas medição.
Nenhum commit, nenhum push, nenhuma alteração de produto, de `bench/`, do driver, do corpus, dos critérios
ou dos hashes congelados. Este arquivo está **não commitado** em `main`.

## 1. Cabeçalho

|Item|Valor|
|---|---|
|Data/hora|2026-10-14, 14:20–16:41 (hora local, UTC-07:00)|
|Repo|`/Users/wagnermontes/Documents/GitHub/feedmine_v2`|
|`main` no início / no fim|`efefd1930b8566151e3cf17483a9fbcf5d9bcf24` → `72af6f1e4d4cd1e0d61717358f343083fbe874b0`|
|Toolchain|Xcode 26.6 (17F113)|
|Simulador de benchmark|`FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE)` — o dispositivo dedicado; nenhum run toca o simulador compartilhado|
|Worktree de verificação|`/tmp/fm-verify`|
|Logs brutos|`/tmp/fm-verify-logs/`|
|Evidência versionada|`docs/reviews/evidence/2026-10-15-candidate-1b990306/` (B01/B02/B04/B05) e `docs/reviews/evidence/2026-10-15-g18f/` (G-18F) — publicados porque `/tmp` é descartável e `bench/run/` é gitignored|
|Relatórios das rodadas por tarefa|`/tmp/fm-verify/report.md`, `gates-round2.md`, `gates-round3.md`, `gates-round4.md`, `gates-round5.md`, `gates-round6.md`, `gates-round9.md`|

Congelamento vigente — `bench/EVALUATOR.sha256` (6 entradas), conferido em cada corrida de gate:

```
966276836b6edf55f555ae25c0c15d5c23185c4894a43e92be24ea10ca0c0b3f  bench/run.sh
57804e0bc354c26fe6010ae4070e9232ab2202dfb809a239f0fc468c68bce8b7  bench/oracle.py
783966adb737e275a42d69f3af60676b2917273f25d250f691b33c477f4b8e3e  bench/serve.py
3c28c8388ef0e1f30739052aa7ac58c4645f2d6f96e9e16ce59ac99e7f68efb7  bench/build_corpus.py
0894b314f40529c2f2680546595cb61b8972d441a59ef6c9d71252bce7e29220  bench/expand.py
08739fd38064019ed4042dba6bc912323b5b1efcbfc2358c6d81efb8db4aa496  FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift
```

`bench/MANIFEST.sha256` (2 314 linhas) cobre os insumos do corpus; cabeçalho e as entradas maiores:

```
3c28c8388ef0…  build_corpus.py          783966adb737…  serve.py            964d4e3361f0…  README.md
1f642eaaf393a95b632ecea339139f9fdf04d7292193cf112f3c46b8a64b3bc8  corpus/catalog.sqlite
4bb683a728ca2ffa99dbc7d47918ee008ee28e113d4cb2b7ee60b47182694cde  corpus/items.json
24109941fee198e0ffb0b914fb9f23d01b0509ffcf7ffe691020b2c9ce0738f9  corpus/profiles.json
17cfac3a8574e460262623697f693e9aae6e5f5d91a6e829f12bbf00661cb961  corpus/sources.json
95e0ebda5ad889c187dbbf9dd9f27745a5e651a24ba0b143bcedb6a1d50b7504  corpus/criteria.json
e35d61c4ef84fdf909203ab0364d2e568d363190d99b0ab143715a8e8e0f123f  corpus/media.pack
```
(+ 2 305 feeds em `corpus/feeds/`). Cada corrida de gate registrou `manifest: OK` e `evaluator: OK`.

## 2. `main` avançou — R3, R4 e D2 integrados

Comandos executados (integração **somente** com as três branches aprovadas — sem K-14, sem K-10, sem K-15):

```
cd /Users/wagnermontes/Documents/GitHub/feedmine_v2
git fetch origin
git switch -c integration/r3-r4-d2 efefd193
git merge --no-ff origin/chatgpt/r3-preserve-consumption-runway -m "Merge origin/chatgpt/r3-preserve-consumption-runway"
git merge --no-ff origin/chatgpt/r4-frozen-editorial-boundary   -m "Merge origin/chatgpt/r4-frozen-editorial-boundary"
git merge --no-ff origin/chatgpt/d2-strict-acquisition-language -m "Merge origin/chatgpt/d2-strict-acquisition-language"
```

Três merges limpos pela estratégia `ort`, **zero conflitos**, `git status --porcelain` vazio ao fim de cada um.
SHAs das branches preservados por merge (nenhum rebase, nenhum squash):

|Merge|commit de merge|branch integrada (SHA)|
|---|---|---|
|R3|`e93083ba`|`9fb199e28d474b1d508256a346553e04bd77810a`|
|R4|`3ccd632c`|`944e6678d74664b04f73ed2990562c636582bef2`|
|D2|**`72af6f1e4d4cd1e0d61717358f343083fbe874b0`**|`c90a67daee34ffbcd7907ca55abfcec58a1fa750`|

Verificação no worktree apontado para `integration/r3-r4-d2`:

|Comando|exit|linha medida|
|---|---|---|
|`swift build`|0|`Build complete! (7.53s)`|
|`swift test`|0|**`Executed 1292 tests, with 1 test skipped and 0 failures (0 unexpected) in 47.332 (47.470) seconds`**|
|`git diff --check`|0|saída vazia|

Reconciliação de contagem: `1285` (BASE `efefd193`) **+1** (R3) **+1** (R4) **+5** (D2) = **1292** — exatamente
o delta medido de casos executados. Artefato bruto: `git log --oneline --graph` da branch
`integration/r3-r4-d2`; log da suíte em `/tmp/fm-verify-logs/integration.test.log`.

Guards conferidos antes do avanço: `main` local == `origin/main` == `efefd193`, árvore limpa
(`git status --porcelain` vazio). O fast-forward publicado foi
**`efefd193..72af6f1e  main -> main`** (executado pelo orquestrador omp sob verdict explícito do
arquiteto e com os guards acima conferidos; eu **não** rodei o push — medi o estado resultante:
`main` == `origin/main` == `72af6f1e`).

**`integration/chatgpt` @ `8203d439` NÃO foi promovida.** Fatos medidos: `git merge-base --is-ancestor
8203d439 main` retorna **1** (não é ancestral); o documento que registra a invalidação da corrida de B03
dessa branch — `docs/reviews/2026-10-14-chatgpt-branch-integration.md` — **existe apenas nessa branch**
(`ls` em `main`: *No such file or directory*); a corrida `bench/run/20261014T200700Z` nasceu sob disco
cheio e não é evidência (ver §4); e a branch continha K-14 (depois retido por ownership) junto das três
aprovadas, com K-10 ainda sem o ajuste de fronteira.

## 3. Gates no HEAD `efefd193` — veredictos e artefatos

|Gate|Veredito|Artefato bruto|`identity.txt`|
|---|---|---|---|
|B01|**PASS**|`bench/run/20261014T195740Z`|`commit: efefd193…`, `dirty: 0 files`|
|B02|**PASS**|`bench/run/20261014T192902Z`|`commit: efefd193…`, `dirty: 0 files`|
|B04|**PASS**|`bench/run/20261014T214403Z`|`commit: efefd193…`, `dirty: 0 files`|
|B05|**PASS**|`bench/run/20261014T193624Z`|`commit: efefd193…`, `dirty: 0 files`|

B04 foi corrido nesta rodada (`scripts/run-discovery-benchmark.sh --gate B04`, exit 0). As duas cláusulas
de `B04.verdict.json` estão `pass: true`; a cláusula 2 traz `instalacoes: 229`, `cartas: 75` e
`violacoes: {head_forward: 0, shrunk: 0, tail_back: 0, holes: 0}`. O run anterior, `20261014T182000Z`,
era **NOT_RUN** (`b04-idle-stable` = `not-measurable`, cláusula com `pass: null`) — o run novo fecha com PASS.

## 4. B03 — **nenhuma evidência válida** em `efefd193` nem em `main` = `72af6f1e`

Existem duas corridas de B03 e **nenhuma** produz veredito utilizável:

**(a) `bench/run/20261014T200700Z` — inválida por disco cheio.** Produzida com **155 MB livres**; a decisão
de descartá-la está registrada em `docs/reviews/2026-10-14-chatgpt-branch-integration.md`, que existe
apenas em `integration/chatgpt` @ `8203d439`. **O veredito dela não é citado aqui nem deve ser usado.**

**(b) `bench/run/20261014T214843Z` e `bench/run/20261014T225053Z` — abortadas, sem veredito (exit 6).**
Nos dois casos o teste de UI passou e o runner falhou **depois**, na verificação pós-corrida do
identificador instalado. Frase literal do artefato:

```
FAIL (B03/A): no app is installed as com.feedmine.development.benchmark on FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE, dedicated to the benchmark)
  the instrumented build is installed under that exclusive identifier and nowhere else, so the app
  under test did not come from this run's rewrite (see the identifier comment above); the gate log:
    t =  1854.81s Tear Down
```

O que o teste de UI mediu antes do aborto (verde, mas **sem veredito do gate**):

```
Test Case '-[FeedMineUITests.DiscoveryBenchmarkTests testB03ThirtyMinuteRunway]' passed (1882.934 seconds).   # 20261014T214843Z
Test Case '-[FeedMineUITests.DiscoveryBenchmarkTests testB03ThirtyMinuteRunway]' passed (1885.028 seconds).   # 20261014T225053Z
```

Nenhum dos dois stamps contém `B03.verdict.json`, `B03.json`, `report.md` ou `B03-A.png`. As fases que o
app gravou (`B03-A.phases`, 185 B em cada) estão transcritas como **fato**, sem tratá-las como medida de
comportamento:

|`20261014T214843Z`|`20261014T225053Z`|
|---|---|
|`neutral`|`neutral`|
|`answered:90_countries/brazil/news-current-affairs/world-news`|`answered:90_countries/brazil/health-wellness/mental-health`|
|`answered:90_countries/brazil/health-wellness/mental-health`|`answered:90_countries/brazil/news-current-affairs/world-news`|
|`thematic-attempted`|`thematic-attempted`|
|`hide-stable:true`|`hide-stable:true`|
|`hide-frames:438->438`|`hide-frames:157->157`|

> **Conclusão, sem rodeio: hoje não existe, em `efefd193` nem em `main` = `72af6f1e`, uma medida válida de
> continuidade do B03.** O estado é **BLOCKED** (não FAIL). Retomar exige **≥ 8 GB livres** no início e a
> corrida sozinha.

## 5. Incidente de disco (reincidente) e a regra operacional que sai dele

Consumidores medidos:

|Consumidor|Tamanho medido|Observação|
|---|---|---|
|Spool de anexos do simulador `…/Devices/16DA3DB5…/data/Containers/Data/InternalDaemon/<uuid>/tmp/Attachments/`|**5,87 GB** (1ª limpeza) e **5,1 GB** (2ª) — com um único arquivo de **2,99 GB** (e a cópia `.sb-…` do sandbox)|É spool temporário do XCTest alimentado pelo `--full-trace`; fica **fora** do repositório|
|`bench/run/<stamp>/derived`|**1,0–1,3 GB por corrida**|Cache de build; o runner o apaga ao fim de uma corrida boa|
|`~/Library/Developer/Xcode/DerivedData/`|~**1,5 GB** em três diretórios (`FeedMineApp-*`, `ModuleCache.noindex`, `SDKStatCaches.noindex`)|Cache do Xcode|

Removido, em cada limpeza: o spool de anexos, os `derived/` das corridas abortadas e os caches do Xcode.
Preservado sempre: `report.md`, `*.verdict.json`, `*.json`, `*.log`, `*.phases`, `*.png`, `identity.txt`,
`inputs.sha256` e os `runtime.sqlite` de todas as corridas — a evidência que conta está fora de
`bench/run/` (que é gitignored) ou preservada dentro dele.

Estado do repositório depois de toda a limpeza: `git status --porcelain` **vazio**. Espaço após a última
higiene: **5,3 GB livres**.

**Regra operacional medida:** verificação de branch (build/teste em worktree) e corrida de gate **não**
podem rodar ao mesmo tempo — a corrida de gate mede comportamento do app (stalls, frames) e disputa
disco; o worktree consome ~1 GB de `.build`. Medir `df -h /` **antes e depois** de cada etapa; abaixo de
**3 GB** o próprio runner recusa e abaixo de **~7 GB** uma corrida `--full-trace` termina sem espaço.

## 6. Branches de worker — verificação por git e por suíte

|Branch (SHA)|Arquivos no diff vs `efefd193`|`swift build`|`swift test`|`git diff --check`|
|---|---|---|---|---|
|`chatgpt/k-15-body` `cbc146e5`|23 (`1282 insertions(+), 183 deletions(-)`) — `func test` **+16 / −0**|0|**`Executed 1300 tests, with 1 test skipped and 0 failures`**|vazio|
|`chatgpt/k-14-hidden-tail` `ffd0f799`|2 (`PublicationStore.swift`, `PublicationHiddenTailLeaseTests.swift`) — `65 insertions(+), 4 deletions(-)`|0|**`Executed 1287 tests, with 1 test skipped and 0 failures`**|vazio|
|`chatgpt/k10-composition-a01-a02-a05` `3a34ab9f`|2 (`AppComposition.swift`, `AppTests/CompositionTests.swift`)|pacote 0; **app não compila** (abaixo)|n/a (o app é pré-requisito)|vazio|
|`integration/k14-k10` `a14e638f`|4 (`346 insertions(+), 50 deletions(-)`)|0|**`Executed 1287 tests, with 1 test skipped and 0 failures`**|vazio|

**K-15** — o único item que faltava era o teste de alvo do app, e ele foi medido:
`xcodebuild test … -only-testing:FeedMineAppTests/ReadingCompositionTests` → exit **65**,
`Executed 7 tests, with 1 failure (0 unexpected) in 4.417 (4.421) seconds`. A contagem é **7** (a classe
está no target). O caso que o próprio K-15 adiciona,
`testK15EnrichedLegacyRevisionBodyAppearsInReadingWithoutChangingPublishedCard`, **passou**; o único caso
vermelho, `testAStillRenderedCardOpensAfterCanonicalPruningButAStaleOwnerCannot`
(`ReadingCompositionTests.swift:174: XCTAssertFalse failed`), **também falha na BASE** (`efefd193`,
`Executed 6 tests, with 1 failure`, mesma asserção em `:173`) — é pré-existente, não regressão.
Os dois casos antes vermelhos no pacote passam isolados
(`swift test --filter testK15LegacyRSSFirstBodyIsEnrichmentNotNewRevision` → `Executed 1 test, with 0 failures`;
`--filter test3R5MeasureOriginExposureOnExistingIndexes` → `Executed 1 test, with 0 failures`).

**K-14** — as duas provas pedidas: `git diff --stat` fecha em **exatamente 2 arquivos** (os dois exigidos)
e `git diff efefd193...HEAD -- FeedMineApp/FeedMineApp/AppComposition.swift` tem **0 linhas** (o ownership
voltou ao K-10).

**K-10** — **não compila sozinho**, e esse é o acoplamento que o arquiteto exigiu provar:
`swift build` (pacote) dá exit **0** e `Build complete! (4.46s)` — **fato surpresa registrado**: o comando
prescrito não mede o acoplamento, porque `AppComposition.swift` pertence ao **alvo do app**, que o pacote
SwiftPM não compila. A prova decisiva, no mesmo SHA:

```
xcodebuild build -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine …   # exit 65
/tmp/fm-verify/FeedMineApp/FeedMineApp/AppComposition.swift:2627:178: error: extra argument 'protectingThrough' in call
Testing failed:  Extra argument 'protectingThrough' in call — Testing cancelled because the build failed.
```

**`integration/k14-k10`** (K-14 + K-10 juntos) — pacote verde (acima) e a suíte de app exigida:

|Medição da suíte `CompositionTests`|exit|totais|casos que falharam|
|---|---|---|---|
|1ª (15:39)|65|`Executed 53 tests, with 5 failures (0 unexpected) in 193.762 (193.781) seconds`|**três**: `testA02MediaSourcesAndPlaybackPositionsShareRetainedDatabase` (`:1764 XCTAssertNil failed: "O catálogo de fontes não está disponível."`, `:1765 ("[]") is not equal to ("["bbc-world", "bbc-science"]")`) **+** os dois pré-existentes|
|2ª (15:47)|65|`Executed 53 tests, with 3 failures (0 unexpected) in 197.196 (197.215) seconds`|**dois**: apenas `testLongNavigationKeepsTheForwardReserveBoundedAndEverythingReachable` (`129 > 25`) e `testS5OfflineReopenRestoresEditionWithFreshProvenance` (`17` não `> 17` + `XCTAssertFalse`) — **coincide com o esperado pelo arquiteto**|

Triagem do `testA02` que apareceu só na 1ª medição: **isolado na mesma árvore combinada, ele passou**
(exit 0, `Executed 1 test, with 0 failures`); no K-10 `3a34ab9f` isolado ele **não chega a rodar** (o app
não compila: o erro `protectingThrough` acima). Portanto `testA02` é **intermitente** nestas medições, e
não há causa determinística identificada além do acoplamento de compilação.

## 7. C-01 — os dois casos de `CompositionTests` já falhavam na BASE

|Árvore|Comando|exit|totais|casos vermelhos|
|---|---|---|---|---|
|BASE `efefd193`|`xcodebuild test … -only-testing:FeedMineAppTests/CompositionTests`|65|`Executed 48 tests, with 3 failures (0 unexpected) in 186.827 (186.846) seconds`|`testLongNavigation…` e `testS5OfflineReopen…`|
|k10 `b2f2c56a`|idem|65|`Executed 53 tests, with 3 failures (0 unexpected) in 188.746 (188.765) seconds`|os **mesmos dois**|

Asserções literais:

```
BASE efefd193:  CompositionTests.swift:1084: XCTAssertLessThanOrEqual failed: ("129") is greater than ("25") - a janela instalada já respeita o teto
                CompositionTests.swift:943: XCTAssertGreaterThan failed: ("17") is not greater than ("18") - pedir a cauda offline tem de trazer conteúdo ALÉM do recorte restaurado (18 cartas na restauração, 17 depois)
                CompositionTests.swift:946: XCTAssertFalse failed - e tem de ser carta que a restauração não trazia — senão não houve navegação nenhuma
k10 b2f2c56a:   CompositionTests.swift:1085: XCTAssertLessThanOrEqual failed: ("129") is greater than ("25")
                CompositionTests.swift:944: XCTAssertGreaterThan failed: ("17") is not greater than ("17")
                CompositionTests.swift:947: XCTAssertFalse failed
Recorte de 2 casos (mesmo comando, só os dois), BASE: "Executed 2 tests, with 3 failures"; integração R3/R4/D2: "Executed 2 tests, with 3 failures" (mesmas linhas 1084/943/946; 130 > 25).
```

**Conclusão: não é regressão de branch.** Os dois casos falham igualmente na BASE e nas branches que
tocam outros módulos; a contagem que varia (129 vs 130 cartas instaladas) varia entre execuções da mesma
árvore. É **triagem**: assertion obsoleta versus decisão de produto (a decisão vigente preserva o
histórico anterior, o que invalida literalmente `window.items.count <= 25` e a exigência de
**crescimento** na reabertura).

O gate **C-01** foi aberto para isso, com ALLOWLIST de um único arquivo. Medição da branch entregue
(`chatgpt/c01-composition-regressions` = `2bd5a7e4cf454346416838d53ef7f97b3b846aff`):

|Prova|Resultado|
|---|---|
|`git diff --stat 72af6f1e...2bd5a7e4`|**1 arquivo** — `FeedMineApp/FeedMineAppTests/CompositionTests.swift`, `55 insertions(+), 36 deletions(-)` (dentro da allowlist)|
|`swift build` / `swift test` / `git diff --check`|0 / **`Executed 1292 tests, with 1 test skipped and 0 failures`** (igual ao `main`) / vazio|
|`xcodebuild test … -only-testing:FeedMineAppTests/CompositionTests`|exit **0**, **`Executed 48 tests, with 0 failures (0 unexpected) in 175.502 (175.520) seconds`**, `** TEST SUCCEEDED **` — os dois casos agora **passam** e nenhum outro passou a falhar|
|`print` da nova asserção (transcrito)|`C01 long navigation: restored=129 behind=112 ahead=16`<br>`C01 S5: editionDistinct=19 previouslyAdmitted=17 restoredAdmitted=17 afterBackward=17 returnedAdmitted=19; snapshot != geometric viewport`|

(Registro de ambiente: o **primeiro** `xcodebuild test` dessa etapa, com o simulador em `Shutdown`,
terminou exit 65 **sem executar teste** — `Test crashed with signal term before establishing connection`;
após `simctl boot` explícito, a repetição mediu exit 0 e 48/0. A falha era de bootstrap, não da branch.)

## 8. B06 — `NOT_RUN` (sem iPhone físico)

`xcrun xctrace list devices` (medido nesta rodada):

```
== Devices Offline ==
Wagner's Apple Watch (10.6.2) (00008006-0010749A3E00C02E)
iPhone (129) (26.5.2) (00008120-000260903ED1A01E)
iPhone (18.6.2) (00008110-00067D861486201E)
```

Os dois iPhones estão **Offline** → **B06 = NOT_RUN**, sem waiver de simulador. `scripts/b06-evidence.sh`
@ `6c696f83` passa `bash -n` **exit 0** na árvore do worktree e no blob `82efa2a6594f0472083efba087bbd677e4d40d72`
(701 linhas, via `git show … | bash -n -`); o diff da branch contra a BASE é **um** arquivo
(`scripts/b06-evidence.sh`, `701 insertions(+)`) e **não** toca `bench/`. O primeiro passo quando o
aparelho conectar é o `--validate` de 60 s.

## 9. Pendências honestas

- **B03 sem medida válida** — BLOCKED por espaço; exige ≥ 8 GB livres e a corrida sozinha. Nenhuma das
  três corridas existentes (`200700Z`, `214843Z`, `225053Z`) serve como medida de continuidade.
- **B06 bloqueado** por ausência de iPhone físico (dois aparelhos `Offline`).
- **`ReadingCompositionTests`**: medido; o único caso vermelho é pré-existente na BASE.
- **`CompositionTests` no `integration/k14-k10`**: medido duas vezes; a 1ª teve um caso intermitente
  (`testA02`) e a 2ª fechou nos dois casos pré-existentes. `testA02` isolado passa na mesma árvore.
- **C-01 (`2bd5a7e4`)**: medido verde (48/0) e **não integrado** — aguarda verdict do arquiteto.
- **Branches não promovidas**: K-14 (`ffd0f799`), K-10 (`3a34ab9f`), K-15 (`cbc146e5`),
  `integration/k14-k10` (`a14e638f`). `main` = `72af6f1e` contém **R3, R4 e D2 e nada além disso**.
- **`integration/chatgpt` @ `8203d439`** não é ancestral de `main` e não deve ser citada como base de nada.
- **Candidato completo** (`integration/candidate` = `1b990306`) construído e medido depois deste relatório
  — ver a seção 10.
- **Candidato montado e medido, mas NÃO promovido**: nenhum `--ff-only`, nenhum push; `main` = `72af6f1e`
  (local e `origin`) contém R3/R4/D2 e **não** K-14/K-10/C-01/K-15.
- **Intermitência de `testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates` EM ABERTO**: 2 falhas
  em 3 execuções completas do **mesmo conteúdo** (`3626238f…`) e passa isolado — não atribuível a branch
  (seção 12).
- **B03 e B06 não viram PASS implícito**: B03 segue `BLOCKED` por espaço (exige ≥ 8 GB livres e a corrida
  sozinha) e B06 segue `NOT_RUN` por ausência de iPhone físico. Nenhum dos dois tem artefato bruto de
  veredito nesta rodada.

## 10. Atualização — composição completa (candidato `1b990306`)

Depois deste relatório, o arquiteto autorizou a composição completa e ela foi construída e medida
(`/tmp/fm-verify/gates-candidate.md`, evidência em `/tmp/fm-verify-logs/cand.*`):

```
git switch -c integration/candidate 72af6f1e
+ K-14 ffd0f799 → 45b2e03a   + K-10 3a34ab9f → 8c6be6e5
+ C-01 2bd5a7e4 → b0334875   + K-15 cbc146e5 → 1b990306   (= 1b9903067b52614863de682eb9a3a7e2407fdb02)
```

|Suíte|BASE `efefd193`|`main` `72af6f1e`|candidato `1b990306`|
|---|---|---|---|
|pacote|`1285 tests, 4 skipped, 0 failures`|`1292 tests, 1 skipped, 0 failures`|`1309 tests, 1 skipped, 0 failures` (= 1292+2+15)|
|`CompositionTests`|`48 tests, 3 failures`|`48 tests, 3 failures`|`53 tests, **1 failure**`|
|`ReadingCompositionTests`|`6 tests, 1 failure`|`6 tests, 1 failure`|`7 tests, 1 failure` (a pré-existente)|

Sem conflitos de merge (os dois pares previstos foram auto-mesclados). **Sobrou uma falha que não existe
na BASE nem no `main`**: `testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates`
(`CompositionTests.swift:180`, `("18") is not equal to ("17") - Anchor plus a sixteen-card idle reserve`),
reproduzida 2 de 2 vezes, com a asserção inalterada e nenhuma das cinco branches tocando o caso. Os dois
casos do C-01 e os cinco do K-10 passam. `main` **não** foi movido.

> **CORREÇÃO (mesmo dia, 17:52) — a frase "reproduzida 2 de 2 vezes" acima está SUPERADA.** O mesmo objeto
> de árvore do candidato (`3626238f…`) produziu depois uma execução da suíte **inteira verde**
> (`Executed 53 tests, with 0 failures`, árvore `291f1e8f`). O caso é **intermitente na suíte completa** e
> **não se atribui a branch**: ver a seção 12, que é a leitura vigente. Nada aqui deve ser lido como
> "falha determinística do candidato".

## 11. Candidato consolidado `1b990306`

Composição autorizada pelo arquiteto, quatro `--no-ff` sobre `main`, **com zero conflito de texto** (os
dois pares previstos — `CompositionTests.swift` K-10×C-01 e `PublicationStore.swift` K-14×K-15 — foram
**auto-mesclados** pelo git, `Auto-merging …` em ambos; fato de merge, não atestado de compatibilidade):

```
git switch -c integration/candidate 72af6f1e
+ K-14 ffd0f799 → 45b2e03a   + K-10 3a34ab9f → 8c6be6e5
+ C-01 2bd5a7e4 → b0334875   + K-15 cbc146e5 → 1b990306
```

|Item|Medida|
|---|---|
|**SHA do candidato**|**`1b9903067b52614863de682eb9a3a7e2407fdb02`**|
|Objeto de árvore|`3626238f8872267eb0c08f5c2f4860998a6a7afd`|
|Escopo vs `main`|`26 files changed, 1683 insertions(+), 269 deletions(-)` — todos das cinco branches|
|`swift build` / `swift test` / `git diff --check`|0 / **`Executed 1309 tests, with 1 test skipped and 0 failures (0 unexpected) in 49.123 (49.265) seconds`** / 0 (vazio)|
|Reconciliação do pacote|`main` 1292 + K-14 **2** + K-15 **15** = **1309** ✔|
|`CompositionTests`|`53 tests` = 48 da BASE + 5 do K-10|
|`ReadingCompositionTests`|`7 tests`, com **só** a falha pré-existente da BASE|
|`main` movido?|**NÃO** — `main` == `origin/main` == `72af6f1e` antes e depois; nenhum `--ff-only`, nenhum push|

Tabela BASE × `main` × candidato (todas as três colunas medidas; a coluna `main` foi medida com as duas
suítes de app: `02a71366…` para `CompositionTests` e `827ffdf6…` para `ReadingCompositionTests`):

|Suíte|BASE `efefd193`|`main` `72af6f1e`|candidato `1b990306`|
|---|---|---|---|
|pacote|`1285 tests, 4 skipped, 0 failures`¹|`1292 tests, 1 skipped, 0 failures`|`1309 tests, 1 skipped, 0 failures`|
|`CompositionTests`|`48 tests, 3 failures`|`48 tests, 3 failures`|`53 tests, 1 failure` (intermitente — §12)|
|`ReadingCompositionTests`|`6 tests, 1 failure`|`6 tests, 1 failure`|`7 tests, 1 failure` (a pré-existente)|

¹ medido antes de `bench/corpus/` existir no worktree; daí 4 *skips* em vez de 1.

## 12. A intermitência de `testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates`

Asserção literal (idêntica em todas as execuções vermelhas):

```
CompositionTests.swift:180: error: -[FeedMineAppTests.CompositionTests testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates]
  XCTAssertEqual failed: ("18") is not equal to ("17") - Anchor plus a sixteen-card idle reserve
```

Placar do **mesmo conteúdo** (`3626238f…`):

|Execução|Árvore|Comando|Resultado|
|---|---|---|---|
|17:03/17:05 (2 medições)|`1b990306`|suíte completa|**vermelha** — `53 tests, with 1 failure` (esse caso)|
|17:41|`1b990306`|só esse caso (`-only-testing:`)|**verde** — `Executed 1 test, with 0 failures`|
|17:52|`291f1e8f`|suíte completa|**verde** — `Executed 53 tests, with 0 failures`|

Prova de que é o mesmo conteúdo (só o grafo de merges difere):

```
$ git rev-parse 1b990306^{tree} 291f1e8f^{tree}
3626238f8872267eb0c08f5c2f4860998a6a7afd
3626238f8872267eb0c08f5c2f4860998a6a7afd
$ git diff 1b990306 291f1e8f | wc -l
0
```

Isolamentos medidos que **não** reproduzem a falha (`swift build`/`swift test`/`git diff --check` = 0/0/0 e
suíte `CompositionTests` com `48 tests, 3 failures` — apenas os dois casos pré-existentes da BASE):

|Árvore|SHA|`testFastFeed…`|
|---|---|---|
|`main` + K-15 (`integration/main-k15`)|`f1fbf797`|passa|
|`main` + K-14 (`integration/main-k14`)|`49891a5a`|passa|
|`main` + K-15 + K-14 (`integration/main-k15-k14`)|`a2d7d535`|passa|
|`main` + K-14 + K-10 + K-15 (`integration/main-k14-k10-k15` = `integration/main-k15-k14-k10`)|`9a03df5b`|passa|
|`main` + K-14 + K-10 + K-15 + C-01 (`integration/main-k15-k14-k10-c01`)|`291f1e8f`|passa (suíte `53 tests, 0 failures`)|

**Conclusão honesta:** o caso **não se atribui a nenhuma branch** (nem a C-01, cujas edições são só de
arquivo de teste, nem a K-10/K-14/K-15). Ele é **intermitente na suíte completa desse conteúdo**: 2
execuções vermelhas de 3 completas, e passa quando isolado. **Nenhum PASS foi declarado** e **nenhum
`--ff-only`** foi feito.

Artefatos brutos: `/tmp/fm-verify-logs/cand.composition.log` (`e1ae1eb1…`),
`cand.composition2.log` (`a28a687a…`), `cand.fastfeed-isolated.log` (`079e32c0…`),
`trio-c01.composition.log` (`c38b4d3e…`), `mk15.composition.log` (`f02840b8…`),
`mk14.composition.log` (`8845ce29…`), `mk15k14.composition.log` (`cf11805b…`),
`mk14k10k15.composition.log` (`68fba292…`).

## 13. Duas armadilhas de método (medidas nesta rodada)

1. **`git diff A...B` (três pontos) mente quando há múltiplas bases de merge.** Comparando o candidato com
   a árvore trio+C-01, o três-pontos reportou **26 arquivos / 1628 insertions** onde o dois-pontos dá
   **0 linhas** — e o git avisa, na própria saída:
   `warning: 1b990306...291f1e8f: multiple merge bases, using 2bd5a7e4cf454346416838d53ef7f97b3b846aff`.
   Para comparar árvores integradas use `git diff A B` (dois pontos) ou compare `git rev-parse A^{tree} B^{tree}`.
2. **Caso que passa isolado e falha na suíte completa não é regressão de produção** — é intermitência de
   suíte. Foi exatamente esse contraste (`Executed 1 test, with 0 failures` isolado × `53 tests, 1 failure`
   em suíte, no mesmo commit) que mostrou que o caso não pertencia a nenhuma branch.

## 14. G-18F — caracterização da intermitência: **FLAKY — ROOT CAUSE UNDETERMINED**

Gate autorizado pelo arquiteto (ChatGPT, thread *Verificação de branches e gates*) com ALLOWLIST de um único
arquivo de teste e DO-NOT-MODIFY sobre produção, `bench/`, migrations, `Package.swift` e os demais testes.

### 14.1 Instrumentação entregue e conferida

|Item|Medida|
|---|---|
|Branch|`origin/chatgpt/g18f-reserve-diagnosis`|
|Commit|`4a05a182026b7cef0627c4b2a579b9d56d03df4f`|
|Base|`1b9903067b52614863de682eb9a3a7e2407fdb02`|
|`git diff --stat 1b990306 4a05a18`|**1 arquivo** — `FeedMineApp/FeedMineAppTests/CompositionTests.swift`, `69 insertions(+), 3 deletions(-)`|
|Produção tocada|**nenhuma** (`-- Sources FeedMineApp/FeedMineApp bench Package.swift` → vazio)|
|As 3 deleções|assinatura de `produceAndAdmit`, a linha `guard let anchor = … else { return }` e a chamada `try await produceAndAdmit(association)` — nenhuma asserção|
|Asserção do caso|intacta: `XCTAssertEqual(cards.count, 17, "Anchor plus a sixteen-card idle reserve")` (agora na linha 246, deslocada pela instrumentação)|

A instrumentação captura um retrato da apresentação em seis momentos (antes/depois de `driver.drive`,
antes/depois de `explicitTailApproach`, e nos limites de `produceAndAdmit`) e **imprime só no fim da
sequência** — a impressão entre as etapas perturbaria a própria corrida que se quer medir.

### 14.2 Medições — 15 execuções, 15 verdes, zero reproduções

Todas seriais, no simulador dedicado `FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE)`, com
`-only-testing:FeedMineAppTests/CompositionTests`:

|Etapa|Árvore|Execuções|Resultado|Logs brutos|
|---|---|---|---|---|
|Linha de base, sem instrumentação|`1b990306`|4|4× `53 tests, with 0 failures`|`/tmp/fm-verify-logs/g18f-baseline-run{1..4}.log`|
|Instrumentada, ociosa|`1b990306`+inst.|6|6× `53 tests, with 0 failures`|`/tmp/fm-verify-logs/g18f-instr-run{1..6}.log`|
|Instrumentada, **carga induzida**|`1b990306`+inst.|5|5× `53 tests, with 0 failures`|`/tmp/fm-verify-logs/g18f-load-run{1..5}.log`|

> **Durabilidade:** `/tmp` é descartável, então os extratos filtrados dessas 15 execuções (linhas `[G18F]`,
> asserção, vereditos por caso) estão versionados em `docs/reviews/evidence/2026-10-15-g18f/`, junto com
> tamanho, contagem de linhas e **SHA-256 de cada log completo** e as janelas decisivas (vermelho × verde ×
> isolado). É de lá que este relatório passa a citar.

A carga induzida foi `yes > /dev/null` em 4 dos 10 núcleos, ligada antes e desligada depois (confirmado com
`pgrep`). Ela **quase não afetou os tempos** — 187–200 s sob carga contra 177–185 s ociosos —, ou seja: o
experimento mede sensibilidade à pressão de CPU e **não** reproduz a concorrência de builds, simulador e
disco das falhas originais. Registrado como está, sem vender a condição como equivalente.

### 14.3 O que os registros mostram no caminho verde (verbatim, `g18f-instr-run1.log`)

```
phase=after launch / before produceAndAdmit count=17 anchorIndex=0  anchorPresent=1 behind=0  ahead=16
phase=before driver.drive                  count=17 anchorIndex=0  anchorPresent=1 behind=0  ahead=16
phase=after driver.drive                   count=17 anchorIndex=0  anchorPresent=1 behind=0  ahead=16
phase=before explicitTailApproach          count=17 anchorIndex=0  anchorPresent=1 behind=0  ahead=16 opportunityIndex=16
phase=after explicitTailApproach           count=17 anchorIndex=16 anchorPresent=1 behind=16 ahead=0  added=[] removed=[]
phase=after produceAndAdmit                count=17 anchorIndex=16 anchorPresent=1 behind=16 ahead=0  added=[] removed=[]
```

Leitura literal: no verde, `explicitTailApproach` **não admite cartão nenhum** — move a âncora para o cartão
que já era a cauda (índice 16), a reserva à frente cai a 0, e a contagem permanece 17. `added=[]` e
`removed=[]` em todas as fases após a primeira.

### 14.4 O caminho vermelho conhecido (sem instrumentação)

`cand.composition.log` (17:03) e `cand.composition2.log` (17:05), mesma árvore `1b990306`, suíte completa,
**duas falhas de três execuções** — enquanto a máquina rodava outros builds e suítes em paralelo:

```
[composition] published growth: admitted 1 -> 17
[composition] installed cards=17 … order=2
[composition] viewport forwarded activity=explicitTailApproach anchor=…
[composition] installed cards=18 … order=4     <-- admissão extra
[composition] settled position checkpoint anchor=… placement=top window=20s
CompositionTests.swift:180: XCTAssertEqual failed: ("18") is not equal to ("17") - Anchor plus a sixteen-card idle reserve
```

Interpretação conservadora: a mesma operação admitiu **um** cartão a mais nessa corrida. A causa não foi
identificada — a instrumentação não chegou a capturar nenhuma execução vermelha.

### 14.5 Fechamento

- Estado registrado: **FLAKY — ROOT CAUSE UNDETERMINED**, com o risco residual declarado (duas falhas
  conhecidas em execução concorrente; 15 execuções sem reprodução).
- **Nada foi modificado**: asserção de 17 intacta, runtime intocado, e o commit `4a05a18` **não** entra no
  candidato — é evidência da investigação, não alteração destinada a `main`.
- Nenhum PASS foi declarado para o caso; nenhum `--ff-only` foi feito.
- Superioridade do método registrada pelo arquiteto: não perseguir indefinidamente uma intermitência
  irreproduzível, mas também não trocar a prova de continuidade do feed por uma suíte XCTest verde.

## 15. Certificação no candidato `1b990306` — B01, B02, B04 e B05: **PASS (4 de 4)**

Autorização do arquiteto: os quatro gates deviam ser medidos **no SHA exato** do candidato, em worktree
limpo em `/tmp`, com `dirty: 0 files`, `bench/MANIFEST.sha256` e `bench/EVALUATOR.sha256` conferidos no
início de cada gate, corpus/driver/oráculo congelados, corridas seriais sem build concorrente, artefatos
preservados e espaço medido antes de cada corrida.

```
git worktree add --detach /tmp/fm-gate-cand 1b9903067b52614863de682eb9a3a7e2407fdb02
cp -R /tmp/fm-verify/bench/corpus /tmp/fm-gate-cand/bench/corpus     # bench/corpus é gitignored (89 MB)
cd /tmp/fm-gate-cand && shasum -a 256 -c bench/EVALUATOR.sha256      # 6/6 OK
cd /tmp/fm-gate-cand/bench && shasum -a 256 -c MANIFEST.sha256       # 2314 OK, 0 falhas
scripts/run-discovery-benchmark.sh --gate B01 --profile A --profile B
scripts/run-discovery-benchmark.sh --gate B02
scripts/run-discovery-benchmark.sh --gate B04
scripts/run-discovery-benchmark.sh --gate B05
```

As invocações são idênticas às que produziram os PASS da BASE `efefd193` (B01 nas duas fases; B02/B04/B05 no
perfil A, o default), de modo que os vereditos são comparáveis entre árvores.

|Gate|Stamp|Veredito|Cláusulas (todas `pass: true`)|Artefato bruto|
|---|---|---|---|---|
|B01|`20261015T061907Z`|**PASS**|5/5 — jornada nos dois perfis (A `hide-frames 224->224`, B `167->167`); não depende das quatro fontes padrão (`[]`); **237** fontes no conjunto de aquisição; **32** fontes nos primeiros 300 cards; perfis diferem (A=237, B=365, iguais=0)|`B01.verdict.json`, `B01-A/B.log`, `B01-A.png`|
|B02|`20261015T062751Z`|**PASS**|5/5 — 200/200 cards relevantes; **40** fontes distintas; concentração **0,045**; **0** pares consecutivos da mesma fonte; **0** duplicatas canônicas|`B02.verdict.json`, `B02-A.log`|
|B04|`20261015T063457Z`|**PASS**|2/2 — protocolo caminhado (18 marcadores); nada se moveu/reordenou/retratou: instalações **223**, cartas **75**, violações `{head_forward 0, shrunk 0, tail_back 0, holes 0}`; `b04-idle-stable = not-measurable`|`B04.verdict.json`, `B04-A.log`, `B04-A.png`|
|B05|`20261015T063945Z`|**PASS**|2/2 — protocolo caminhado (salvar, A→B→A, reabrir, offline); zero perda silenciosa de estado|`B05.verdict.json`, `B05-A.log`|

Identidade de cada stamp (medida, não presumida): `commit: 1b9903067b52614863de682eb9a3a7e2407fdb02`,
`dirty: 0 files`, `evaluator.check` 6/6 OK, `manifest.check` 2314 OK / 0 falhas.

> **Durabilidade:** `bench/run/` é gitignored, então os quatro vereditos passaram a viver no repositório em
> **`docs/reviews/evidence/2026-10-15-candidate-1b990306/<GATE>/`** — `B0X.verdict.json`, `B0X.json`,
> `B0X-A/B.phases`, os PNG das jornadas, `identity.txt`, `report.md`, `evaluator.check`, `manifest.check` e
> `inputs.sha256`, publicados em `d964a41f`. Os caminhos em `/tmp/fm-gate-cand/…` que aparecem acima são os
> **stamps originais** de onde cada arquivo foi copiado byte a byte.

### 15.1 Tentativa abortada de B01 (não é medição) — causa: recurso ausente, não disco

O primeiro stamp da campanha, `20261015T061717Z`, morreu em **`** TEST BUILD FAILED **`** com **dois**
erros no mesmo build:

```
Ld /tmp/fm-gate-cand/bench/run/20261015T061717Z/derived/Build/Products/Debug-iphonesimulator/FeedMine.app/__preview.dylib
Command Ld failed with a nonzero exit code
CpResource … /tmp/fm-gate-cand/FeedMineApp/FeedMineApp/Resources/catalog.sqlite (in target 'FeedMine')
error: The file “catalog.sqlite” couldn’t be opened because there is no such file.
```

A primeira versão deste relatório atribuiu a falha a "pressão de disco". **Está errado, e a correção vem do
próprio artefato:** a busca por `No space left`, `errno=28`, `write() failed`, `Disk full` e `ENOSPC` em
`20261015T061717Z/build.log` (4 409 linhas) devolve **0 ocorrências de cada**. A causa medida é outra: o
alvo `FeedMine` copia um recurso **gitignored** (`FeedMineApp/FeedMineApp/Resources/catalog.sqlite`, asset de
release obtido fora do git) que **não existe em worktree recém-criado** — o build morre até alguém colocar o
arquivo. Depois de colocá-lo, a corrida `20261015T061907Z` (B01 PASS) foi em frente.

Cópia usada na árvore de medição, identificada por hash:

|Item|Valor|
|---|---|
|Arquivo|`/tmp/fm-gate-cand/FeedMineApp/FeedMineApp/Resources/catalog.sqlite`|
|SHA-256|`72f066227958b482f365c88dd58320e75bc9ade9268b4e2ddaac9173908ecf71`|
|Tamanho|117 993 472 B|
|Origem|cópia do mesmo arquivo de `…/feedmine_v2/FeedMineApp/FeedMineApp/Resources/catalog.sqlite` (SHA-256 idêntico), colocada na árvore às 23:18|

> **Ressalva de método que fica registrada:** esse recurso é **invisível** para `identity.txt` (`dirty: 0
> files` não vê arquivo ignorado) e para `bench/MANIFEST.sha256`/`inputs.sha256` — nenhum dos três o cobre.
> Qualquer reprodução futura em worktree limpo vai bater na mesma parede até o arquivo ser colocado, e a
> procedência dele não é verificada pelo runner. É um furo de infraestrutura do harness, **não** das
> medições: os quatro vereditos PASS continuam válidos, porque o catálogo que o app usa em execução é o do
> corpus, verificado por MANIFEST e conferido por descritor em `bench/run.sh` (a cópia do bundle é só
> insumo de build).

### 15.2 O que continua aberto

|Gate|Estado|Razão medida|
|---|---|---|
|B03|**BLOCKED — DISK**|Máquina com **5,7 GB** livres; a corrida `--full-trace` exige ≥8 GB (o spool de anexos do XCTest chega a ~5,9 GB durante a corrida). Nenhuma tentativa foi feita para "driblar" o limiar.|
|B06|**NOT_RUN — DEVICES OFFLINE**|Os dois iPhones seguem `Offline`; simulador **não** é waiver.|

`main` estava em `72af6f1e` **no momento em que os quatro gate foram medidos**; a promoção para `1b990306`
verdictada pelo arquiteto está registrada na §16 e foi executada depois — leia as duas seções em sequência,
não em contradição. **Nenhum `--ff-only` é feito sem verdict explícito**, e a certificação de release
depende de B03 válido e B06 executado.

## 16. Promoção para `main` — **executada**

Verdict do arquiteto (ChatGPT, thread *Verificação de branches e gates*): *"Autorizo o fast-forward de main
para 1b9903067b52614863de682eb9a3a7e2407fdb02"*, com a separação explícita entre **integração técnica**
(aprovada) e **certificação de release** (bloqueada por B03/B06).

Pré-requisito de publicação (regra do projeto) medido na árvore da medição, `/tmp/fm-gate-cand` @ `1b990306`:

|Comando|Resultado literal|
|---|---|
|`swift build`|exit 0 — `Build complete!`|
|`swift test`|`Executed 1309 tests, with 1 test skipped and 0 failures (0 unexpected) in 46.856 (46.997) seconds`|
|`git diff --check`|saída vazia|

O caso pulado é `CatalogCompilerReferenceTests.testCompiledTreeMatchesTheReferenceCatalogueRowForRow`,
pulado por faltarem as variáveis `FEEDMINE_REFERENCE_*` — não é falha.

Guards conferidos antes do push: `main` local == `origin/main` == `72af6f1e`, árvore limpa (apenas este
relatório, untracked), e `git merge-base --is-ancestor 72af6f1e 1b990306` = verdadeiro (fast-forward puro).

```
git push origin main
   72af6f1e..1b990306  main -> main
```

Verificação posterior, medida por `git ls-remote`: `refs/heads/main` = `1b9903067b52614863de682eb9a3a7e2407fdb02`,
igual a `main` local. Nenhum `--force`, nenhum rebase, nenhum squash: os SHAs das cinco branches
(K-14 `ffd0f799`, K-10 `3a34ab9f`, C-01 `2bd5a7e4`, K-15 `cbc146e5`) e das três já em `main` (R3 `9fb199e2`,
R4 `944e6678`, D2 `c90a67da`) permanecem intactos no histórico.

**O que a promoção NÃO significa:** certificação de release. Continuam abertos B03 (**BLOCKED — DISK**) e
B06 (**NOT_RUN — DEVICES OFFLINE**), e o commit diagnóstico `4a05a18` **não** entrou em `main` — fica como
evidência do G-18F.

### 16.1 Higiene de disco para o B03 — meta não atingida

O arquiteto exigiu **10–12 GB livres** antes de tentar o B03 e autorizou apenas caches comprovadamente
regeneráveis. Apagados, com tamanho medido antes: `~/Library/Caches/org.swift.swiftpm` 239 MB,
`~/Library/Caches/Google` 223 MB, `~/Library/Caches/bun` 108 MB, `~/Library/Caches/GeoServices` 51 MB,
`~/.npm` 354 MB, `~/.bun` 391 MB, `~/.gradle` 277 MB, `~/.local/share/uv` 294 MB, `~/.omp/puppeteer` 346 MB —
somando ~2,3 GB. **Disco: 5,7 GB → 7,0 GB livres.**

Ficaram de fora, de propósito, dois candidatos grandes **em uso por processos vivos**:
`~/.cache/codex-runtimes` 1,56 GB (há um `codex app-server` rodando, pid 76951, da extensão ChatGPT do VS Code)
e `~/Library/Caches/com.microsoft.VSCode.ShipIt` 1,4 GB (VS Code aberto, ShipIt ativo). Juntos somariam
+2,96 GB → ~10,0 GB. Nenhum simulador, evidência, histórico ou arquivo pessoal foi tocado.

**B03 segue BLOCKED — DISK**, pela condição que o próprio arquiteto fixou: não se repete uma corrida de 31
minutos com risco conhecido de invalidação ambiental.
