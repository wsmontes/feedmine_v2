# A jornada de reabertura: o feed aparece imediatamente, sem tela de carregamento no meio

**Data:** 2026-10-15/16 · **Autor:** agente `ReopenJourney` (tarefa delegada pelo agente principal)

> **Nota de revisão (2026-10-16, agente `ReopenBoundaryOwner`).** Este relatório descreve a **primeira entrega**
> da branch `fix/reopen-journey` (commit `3e6c54b6`) e é mantido como está naquilo que ela mediu: a asserção do
> critério, o controle frio e a ausência da superfície de espera na reabertura morna seguem válidos e são citados
> pelo teste que os afirma. O que **mudou** na segunda entrega, na mesma branch, é a fronteira
> restauração↔descoberta: o §3 item 3 ("o pool é resolvido … nesta linha em vez de numa passagem destacada") e o
> residual do §5 ("num perfil que peça uma leitura pesada do catálogo, essa leitura passa a estar no caminho do
> primeiro quadro") descrevem o estado que a segunda entrega **corrigiu** — a leitura do pool saiu do caminho
> síncrono do arranque morno e passou a ser adotada como fornecimento atrás da janela do leitor. Os números de
> §2 e de §3 foram medidos **com a leitura do pool dentro do intervalo morno**, e por isso não valem como
> descrição do que existe hoje; o §6 lista as linhas alteradas. A revisão de oráculo/critério não é deste
> trabalho. Ver `docs/reviews/2026-10-16-fronteira-restauracao-descoberta.md`.

**Pergunta que este relatório responde:** a doutrina do dono do produto faz da reabertura o critério principal
("**fechar e reabrir o app: o feed deve aparecer imediatamente**, do conteúdo pronto da interação anterior … sem
tela de carregamento no meio", `1.0-checklist.md:3131-3132`, reafirmado `:3220-3224`; o harness da V1 falhava o
próprio teste quando uma superfície de carregamento sobrevivia, `PersonaExplorationUITests.swift:386-388`). A V2
media **só a metade da identidade** — a âncora que volta — e **nenhum teste afirmava a ausência da tela de
carregamento**. Este relatório entrega essa metade: a asserção, o controle que prova que ela falha, e o menor
conserto de produto que a torna verdadeira.

## 0. Método, ambiente e limites (para poder desconfiar deste relatório)

| Item | Valor |
|---|---|
| Repositório | `feedmine_v2`, worktree `/private/tmp/fm-reopen`, branch `fix/reopen-journey` |
| Base | `3b020a15abafef5f5ca5bcdaf056e436a4b92166` (`main`), árvore limpa no início |
| Máquina | macOS 25.3.0 arm64 · Xcode 26.6 (17F113) · SDK iOS 26.5 |
| Simulador | **device próprio desta sessão**: `C2C4AD2B-CC59-4556-8746-403553BA65C8` ("FeedMine ReopenJourney", iPhone 17 Pro Max, iOS 26.5). Um device por sessão de UI test. O `84EA32E8` foi apagado a pedido do dono da rodada; o `7420F436` (fixture de migração) nunca foi tocado |
| Corpus / insumos | **fixtures do próprio app** (`FEEDMINE_USE_DEVELOPMENT_FEEDS=1`, `FEEDMINE_LOCAL_FEEDS=1`, `FEEDMINE_SKIP_ONBOARDING=1`) — sem RSS público e sem servidor. `bench/**`, o oráculo, o corpus congelado e os critérios **não foram tocados**; a única coisa copiada para a worktree foi `bench/corpus/profiles.json` (gitignored, exigido pela fase de recursos do alvo de testes) |
| Comandos | `xcodebuild build-for-testing` / `test-without-building` (destino acima) · `swift build` · `swift test --filter FeedMineRuntimeTests` · `git diff --check` |
| Rodadas descartadas (não são resultado) | 3 corridas mortas por **concorrência de device** (`Mach error -308`, "runner app uninstalled", `simctl shutdown all` de outro agente) e a instabilidade de disco do host. Foram descartadas e refeitas; só as corridas abaixo são citadas |

Nota de proveniência: as medições deste relatório foram feitas com **dois outros agentes compilando na mesma
máquina**. Os tempos absolutos são de um simulador carregado, não de um aparelho; o que este relatório afirma
como critério é a **ordem das superfícies** e a **ausência** da tela de espera, não um orçamento de milissegundos.

## 1. Por que a testemunha é o registro da própria app, e não uma amostra do teste

Um teste de UI **não consegue** medir essa metade: `XCUIApplication.launch()` só retorna quando o app chega ao
repouso, então a superfície de carregamento que viveu toda a transição de arranque é exatamente a que nenhuma
amostra posterior pode ver. A V1 documentou a própria janela cega no seu harness ("nothing before `launch()`
returned is observable from here"). Quem pode ver é o app.

A testemunha é `FeedLaunchWitness` (`Sources/FeedMineUI/FeedLaunchWitness.swift`, DEBUG, diagnóstico puro: nada lê
esse valor para decidir o que publicar — a mesma regra do `RunwayTrace`). Ela registra, no relógio do próprio
processo (armado no topo do `FeedMineApp.init`, então cada número lê-se como "milissegundos desde esta abertura"),
os dois fatos que o critério compara:

- **as superfícies de espera**: o progresso do arranque do host (`launch-progress`) e a superfície de ausência do
  feed com o estado de trabalho que ela declara (`absence:idle`, `absence:preparing`, …) — o primeiro instante, o
  último e quantas passagens as carregaram;
- **a primeira passagem de desenho que carregou cartas prontas do leitor**, com o instante e a contagem.

Três razões para ser esta a testemunha certa, e não um *proxy*:

1. **É da app, no passo em que o fato é verdade.** Quem **declara** o ramo é o host: `FeedMineApp` decide entre o
   seu próprio progresso, a ausência do feed e as cartas — e ele decide com os mesmos valores que a tela lê
   (`composition.association`, `hasSelectedSources`, `store.renderedItems`, `store.state.work`). O ramo lido e o
   ramo desenhado são **uma decisão só**; a testemunha não dá uma segunda opinião sobre ela, apenas a anota. E o
   lugar é o certo por uma razão medida: a fronteira congelada `U14` (abaixo) proíbe efeitos escondidos dentro dos
   módulos de UI — a testemunha **não pertence** lá.
2. **A ordem é o critério, e os dois instantes são o mesmo relógio.** "Houve tela de carregamento antes do feed" é
   então uma comparação (`first_wait_ms < first_cards_ms`), não uma opinião; a janela (`last_wait_ms`) mostra por
   quanto tempo o leitor a viu.
3. **O registro guarda um só valor por fato.** Depois de uma medição ter mostrado o que acontece quando os dois
   campos são independentes (`cards=17` ao lado de `first_cards_ms=n/a`), cada fato é escrito de uma vez
   (instante + o que era), e o relógio não pode mais ser capturado depois da leitura que o usa.

**O limite que a testemunha tem, dito em voz alta.** Ela é tomada na avaliação do corpo do host, não no commit de
pixels: um passo de atualização substituído antes de ser desenhado poderia, em princípio, ser contado. O que ela
prova está dito com esse limite: no arranque morno o app **nunca escolheu** desenhar uma superfície de espera —
o primeiro ramo que ele declarou já era o das cartas —, e o controle frio mostra que ela sabe contar uma quando
ela existe. A metade no formato da V1 é afirmada também, na superfície que o leitor percebe: com o app já ocioso,
**nenhuma** superfície de espera está na árvore de acessibilidade (`feed-loading-surface`, `feed-launch-progress`).

**O que a fronteira congelada corrigiu neste trabalho.** A primeira versão da testemunha marcava o fato de dentro
dos módulos de UI (`.onAppear` em `FeedScreen`/`FeedLoadingView`). A bateria do pacote reprovou-a — e o fez
corretamente:

```
FeedScreenRenderingTests.swift:1338: error: testU14UIBoundaryHasNoProductionImportsOrHiddenEffects :
    XCTAssertFalse failed - FeedScreen.swift: .onAppear
FeedScreenRenderingTests.swift:1339: error: testU14UIBoundaryHasNoProductionImportsOrHiddenEffects :
    XCTAssertFalse failed - FeedLoadingView.swift: .onAppear
	 Executed 18 tests, with 2 failures (0 unexpected) in 9.322 (9.325) seconds
```

O `testU14UIBoundaryHasNoProductionImportsOrHiddenEffects` já proibia `Task`, `.task`, `.onAppear`, `.onDisappear`,
`Timer`, `sleep`, `@State` e afins nesses arquivos, e ele está certo: a UI não é lugar de efeito. A testemunha
passou a ser do **host** (que já decide o ramo), e dos módulos de UI sobrou apenas o que é apresentação: o
identificador `feed-loading-surface` na superfície de ausência. `swift test --filter FeedScreenRenderingTests`
volta verde (18/18).

## 2. A asserção nova e o seu controle

**Teste:** `FeedMineUITests.testWarmRelaunchShowsTheFeedWithoutRenderingAWaitSurface`
(`FeedMineApp/FeedMineAppTests/FeedMineUITests.swift`, alvo `FeedMineUITests`).

Ele faz uma jornada inteira: contêiner novo (frio) → lê conteúdo → aplica um filtro (para o contexto nomear algo
que a descoberta tenha de procurar) → um gesto real de rolagem → fecha → **relança o mesmo contêiner com a rede
bloqueada** (o que volta só pode ser o que a interação anterior tornou pronto localmente, INV-11). As duas
corridas — a fria e a morna — são julgadas pela **mesma função** (`reopenCriterionViolations`), que devolve todas
as violações: nada de cartas prontas, superfície de espera antes do feed, superfície de espera ainda em tela com
o app ocioso.

### 2.1 O controle frio, dentro do teste (as duas corridas)

Um contêiner que nunca rodou não tem conteúdo pronto: a superfície de espera é a coisa honesta a mostrar
(doutrina, item 1: "a primeira abertura pode ser lenta — é para isso que existe a tela de carregamento"). Ela
**tem de violar** o critério, ou a testemunha não está dizendo nada. As corridas violaram, como deviam — a fria
de cada execução, sem e com o conserto de produto:

```
# ANTES do conserto (lançamento frio)
REOPEN_WITNESS cold record=wait_passes=4 kind=launch-progress first_wait_ms=1083 last_wait_ms=1561 cards=12 first_cards_ms=2233
REOPEN_WITNESS cold verdict=violated violations=a loading surface was drawn before the feed: 4 pass(es) of launch-progress over 1083…1561 ms, cards at 2233 ms

# DEPOIS do conserto (lançamento frio)
REOPEN_WITNESS cold record=wait_passes=4 kind=launch-progress first_wait_ms=1707 last_wait_ms=2626 cards=12 first_cards_ms=3549
REOPEN_WITNESS cold verdict=violated violations=a loading surface was drawn before the feed: 4 pass(es) of launch-progress over 1707…2626 ms, cards at 3549 ms
```

### 2.2 A metade morna: **falha antes, passa depois** (as duas saídas cruas)

**Antes** — a mesma jornada, com a testemunha e o teste, e **sem** o conserto de produto (o caminho de arranque
como está na `main`):

```
REOPEN_WITNESS warm record=wait_passes=3 kind=launch-progress first_wait_ms=634 last_wait_ms=1029 cards=17 first_cards_ms=1278
REOPEN_WITNESS warm launch_returned_ms=3490 (XCTest's idle bound on the same launch; the app's own first_cards_ms is in the record)
REOPEN_WITNESS warm verdict=violated violations=a loading surface was drawn before the feed: 3 pass(es) of launch-progress over 634…1029 ms, cards at 1278 ms
FeedMineUITests.swift:1034: error: XCTAssertTrue failed - a warm relaunch must satisfy the reopen criterion — record=wait_passes=3 kind=launch-progress first_wait_ms=634 last_wait_ms=1029 cards=17 first_cards_ms=1278 violations=["a loading surface was drawn before the feed: 3 pass(es) of launch-progress over 634…1029 ms, cards at 1278 ms"]
	 Executed 1 test, with 1 failure (0 unexpected) in 37.799 (37.801) seconds
```

**Depois** — mesma jornada, mesmo device, mesma configuração, com o conserto:

```
REOPEN_WITNESS warm record=wait_passes=0 kind=none first_wait_ms=n/a last_wait_ms=n/a cards=14 first_cards_ms=1931
REOPEN_WITNESS warm launch_returned_ms=5641 (XCTest's idle bound on the same launch; the app's own first_cards_ms is in the record)
REOPEN_WITNESS warm verdict=satisfied violations=none
	 Executed 1 test, with 0 failures (0 unexpected) in 48.485 (48.489) seconds
```

A resposta honesta à pergunta da tarefa é, portanto: **hoje o app mostrava algo na reabertura morna** — o progresso
de arranque do host (`launch-progress`) ficava em tela de 634 ms a 1029 ms, com o primeiro card só a 1278 ms — e a
entrega é a **prova mais o menor conserto**, com o controle a mostrar que a asserção não é vazia: ela **falhava**
nesta jornada antes do conserto e passa depois dele, no mesmo device e com a mesma medição. Uma nota de leitura: a
contagem de cartas restauradas varia entre execuções (14 e 17 medidas) com o que a interação anterior deixou
durável — o que o critério mede é a **ordem** e a **ausência**, nunca um número fixo de cartas.

## 3. O conserto (produto) e o invariante que o serve

**Invariante:** INV-07 — "**a warm launch is local**: restore session/publication → materialize the window, no
network" (`docs/architecture/PRODUCT_INVARIANTS.md`). Se o arranque morno é local, ele **cabe antes do primeiro
quadro**; e se o leitor não pode perceber trabalho de backend, nada pode ser desenhado entre a tela de arranque do
sistema e o feed dele. Era isso que faltava: a associação — e com ela a janela do leitor — era construída dentro de
uma `Task`, publicada já com o campo de visão desenhado, e a instalação da apresentação chegava depois, por um
salto de ator. O leitor via o progresso do host e, em seguida, a superfície de ausência.

O conserto tem três partes, e nenhuma delas inventa um caminho paralelo:

1. **Uma única implementação da restauração, fora do ator** (`Sources/FeedMineRuntime/FeedSession.swift`,
   `FeedCheckpointProjection`). A leitura do checkpoint e a projeção da janela — com a banda de pixels residentes
   e a proveniência da projeção — vivem agora numa função que **não** é do ator, e as admissões `.initial`/`.restore`
   do próprio ator chamam essa mesma função. Não há uma segunda restauração a divergir da primeira: a associação
   morna usa a mesma. De passagem, o mapa `reusable` que o caminho antigo construía a partir de `state?.presentation`
   saiu: as duas admissões que chegam ali recusam correr com uma apresentação admitida, logo aquele mapa era sempre
   vazio.
2. **`FeedSession` aceita uma janela pronta** (`WarmStart`, `init(..., warmStart:)`): a sessão adota o estado, a
   sequência de projeção e os pixels liberados que a projeção produziu, e marca a apresentação inicial como
   admitida — exatamente o que teria acontecido na admissão `.initial`. A `FeedSession.warmStart(...)` é a porta
   síncrona da mesma projeção.
3. **A composição constrói a associação antes do primeiro quadro** quando o leitor tem uma janela durável
   (`AppComposition.init` → `hasDurableWindow()` → `warmAssociation()`; `FeedAssociation.init` projeta e **instala**),
   e `launch()` passa a ativar o que já existe em vez de construir de novo. Nesta entrega o pool de descoberta era
   resolvido pelo **mesmo** cálculo de antes (`discoveryPool`), chamado nesta linha em vez de numa passagem
   destacada, e essa chamada ficava **entre a tela de lançamento e o feed do leitor** — 2,5–2,8 s de leitura do
   catálogo de 118 MB no caminho do primeiro quadro. A segunda entrega da branch removeu essa chamada do caminho
   síncrono e passou a adotar o pool **atrás** da janela (`AppComposition.launch()` →
   `FeedAssociation.adopt(_:)`, que materializa as entradas pelo mesmo dono que materializa uma página examinada);
   o número `first_cards_ms` que aparece mais abaixo, portanto, **inclui** aquela leitura e não descreve o estado
   de hoje.

O diff é: `FeedSession.swift` +149/−61, `AppComposition.swift` +142/−?, e mais o que é testemunha (abaixo).

**Custo no arranque frio, medido (pedido explícito do dono da rodada).** Um arranque sem nada durável **não**
entra nesse caminho: o gate é `hasDurableWindow()` — duas leituras de uma linha (`SessionStore.checkpoint()` e
`checkpoint(for:)`) sobre o banco que a composição já abriu — e o resto é o código de antes, sem alteração. Medido
nas corridas do controle frio (que é exatamente esse caso, contêiner novo), como superfície de espera / primeiro
card: **1083 / 2233 ms** sem o conserto e **1707 / 3549 ms** com ele. A corrida sem o conserto foi ~35% mais rápida
**em tudo** — inclusive no que não mudou —, que é o ruído desta máquina compartilhada, e é por isso que este
relatório compara ordens e não milissegundos. O único custo que este conserto acrescenta ao arranque frio são as
duas leituras de uma linha.

**O tempo que a janela morna levava nesta entrega.** O registro da app disse `first_cards_ms=1931` na execução
final (1278 ms antes do conserto; 1368 e 2101 ms em execuções anteriores): o primeiro quadro, **já com as cartas do
leitor**, chegava 1,3–2,1 s depois do arranque do processo, e o número incluía todo o trabalho local do arranque
(a verificação do catálogo no `init` da composição, **a leitura do pool do perfil** — 2,5–2,8 s nos perfis pesados
— a construção da associação, a projeção do checkpoint com a decodificação da banda). Essa leitura do pool deixou de
estar nesse caminho na segunda entrega da branch: o mesmo intervalo passou a conter só o trabalho local do arranque
e a leitura foi para trás da janela. Os números acima ficam, portanto, como **histórico da primeira entrega**, e não
como descrição do estado entregue hoje (`docs/reviews/2026-10-16-fronteira-restauracao-descoberta.md` traz a medição
da fronteira nova). O contraste que interessa, medido **na mesma execução**: no arranque frio o primeiro quadro (que
não trazia nada) chegou a 1707 ms, e o primeiro card só a 3549 ms. O valor absoluto é grande (a V1 media 234 ms num
aparelho) e o orçamento é assunto de outra medição, de preferência no aparelho.

## 4. O que é testemunha e o que é produto (separação pedida pelo dono da rodada)

| Camada | Arquivos | O que serve |
|---|---|---|
| **Testemunha** (DEBUG, diagnóstico) | `Sources/FeedMineUI/FeedLaunchWitness.swift` (novo) · `FeedMineApp/FeedMineApp/FeedMineApp.swift` (armar o relógio, declarar o ramo de cada passagem do host, publicar `feed-launch-record`) · `FeedMineUI/FeedLoadingView.swift` (só o identificador `feed-loading-surface`) | tornar observável o que nenhuma amostra de UI test pode ver. Não decide nada: o host declara o ramo que **já decidiu**, e nada lê o record para escolher o que desenhar |
| **Asserção** | `FeedMineApp/FeedMineAppTests/FeedMineUITests.swift` (o teste, `reopenCriterionViolations`, `launchRecord`) | afirma o critério e o controle dele |
| **Produto** | `Sources/FeedMineRuntime/FeedSession.swift` · `FeedMineApp/FeedMineApp/AppComposition.swift` | INV-07: a janela do leitor existe antes do primeiro quadro |

## 5. O que foi deliberadamente deixado de lado

- **A identidade da âncora** continua afirmada pelo teste que já existia
  (`testAForcedCloseReopensOnTheCardTheReaderWasReading`); este trabalho não a duplica.
- **A descoberta não mudou de dono** — e **mudou de lugar**, na segunda entrega da branch. O pool continua a ser
  resolvido para o mesmo perfil, com o mesmo limite, pelo mesmo cálculo (`discoveryPool`); o que mudou é *onde* a
  leitura acontece no arranque morno. Nesta entrega ela estava **na linha, antes do primeiro quadro** — o residual
  registado aqui, e corretamente: um perfil que pedisse uma leitura pesada do catálogo (2,5–2,8 s contra os 118 MB)
  pagava esse tempo **entre a tela de lançamento e o feed**, que é o lugar que o critério proíbe. A segunda entrega
  removeu a leitura do caminho síncrono: ela é liberada depois de a janela do leitor estar em tela, roda na passagem
  destacada de sempre e é **adotada como fornecimento** pelo mesmo dono que materializa uma página examinada. Ver
  `docs/reviews/2026-10-16-fronteira-restauracao-descoberta.md`.
- **Nada em `bench/**`, no oráculo, no corpus ou nos critérios congelados** foi tocado; nenhum gate foi rodado e
  nenhum veredito de B01–B06 é afirmado aqui.
- **A superfície de ausência ganhou um identificador** (`feed-loading-surface`) e um contêiner de acessibilidade
  (`.accessibilityElement(children: .contain)`) — é a metade no formato da V1 ("uma superfície que tem de ser
  nomeável para que se possa afirmar a sua ausência"), no mesmo padrão que `feed-end-of-content` e
  `feed-empty-state` já usam.
- **Um `Thread.sleep(2)` antes do fechamento** e nenhuma asserção sobre os contadores do driver: numa janela
  filtrada que caiba no campo de visão não há oportunidade nenhuma a completar, e o critério não depende disso
  (o contador é impresso como evidência).

## 6. Comandos e execuções (as linhas exatas)

```
$ git diff --check                     → limpo (nenhuma linha com espaço em branco no fim, nenhum marcador)

$ swift build                          → EXIT 0

$ swift test                           → EXIT 0
	 Executed 1399 tests, with 3 tests skipped and 0 failures (0 unexpected) in 102.532 (102.820) seconds
   (a bateria do pacote inteira; a única reprovação que este trabalho produziu foi a fronteira `U14`, §1)

$ swift test --filter FeedMineRuntimeTests     → EXIT 0
	 Executed 170 tests, with 0 failures (0 unexpected) in 18.297 (18.327) seconds
   (inclui FeedSessionCheckpointTests 21/21, FeedSessionWarmRestoreTests 4/4,
    ProjectionDecodeMeasurementTests 2/2 — a semântica que a extração da restauração toca)

$ swift test --filter FeedScreenRenderingTests → EXIT 0
	 Executed 18 tests, with 0 failures (0 unexpected) in 6.271 (6.274) seconds
   (a fronteira `U14`, que a primeira versão da testemunha reprovava — §1)

$ xcodebuild build-for-testing -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
    -destination 'platform=iOS Simulator,id=C2C4AD2B-CC59-4556-8746-403553BA65C8' \
    -derivedDataPath /private/tmp/fm-reopen-derived                     → EXIT 0

$ xcodebuild test-without-building ... -parallel-testing-enabled NO \
    -only-testing:FeedMineUITests/FeedMineUITests/testWarmRelaunchShowsTheFeedWithoutRenderingAWaitSurface
   sem o conserto de produto:  Executed 1 test, with 1 failure  (unexpected 0) in 37.799 s
   com o conserto de produto:  Executed 1 test, with 0 failures (unexpected 0) in 48.485 s
```

Evidências brutas (logs completos do `xcodebuild`/`swift test`):

| Arquivo | O que é |
|---|---|
| `/private/tmp/fm-reopen-before2.log` | a jornada **falhando** sem o conserto de produto (o registro morno com a superfície de espera) |
| `/private/tmp/fm-reopen-final3.log` | a mesma jornada **passando** com o conserto |
| `/private/tmp/fm-swift-test-all2.log` | `swift test` completo (1399 testes, 0 falhas) |
| `/private/tmp/fm-boundary.log` | a fronteira `U14` verde |

Hashes (sha-256) do estado entregue **nesta primeira entrega** (`3e6c54b6`), para conferir sem reabrir o diff —
duas destas linhas **não** valem para o estado de hoje: `AppComposition.swift` e `FeedMineUITests.swift` mudaram na
segunda entrega da mesma branch (a fronteira restauração↔descoberta), e os hashes de `FeedSession.swift`,
`FeedLaunchWitness.swift`, `FeedLoadingView.swift` e `FeedMineApp.swift` seguem válidos:

```
cfaa03fd97df897e494e9108b15fb3bf081e0669e9d2e184d5e681847fffaad6  Sources/FeedMineUI/FeedLaunchWitness.swift
cb7e25b82c1750c4e4b53b9156ed4d7f340f9c0bdd875cf5fe1ee7badeee4487  Sources/FeedMineUI/FeedLoadingView.swift
1bf7637cf1a01e10a562387db8f2692018d66b6b6e670701add99b820749eb76  Sources/FeedMineRuntime/FeedSession.swift
b055607fefef1206005466cd92759418f322a5d8b861dd6d2cb3faf1c941797c  FeedMineApp/FeedMineApp/FeedMineApp.swift
4d3586ff2b57de883b70e1c4f1ad3db546d670f50d8305afa92b8f6dba4991e9  FeedMineApp/FeedMineApp/AppComposition.swift  (primeira entrega; superado)
fe73926827d8743d4d3d1fb7a8b06343c1a43c76261f6cd800aad4be3c87339e  FeedMineApp/FeedMineAppTests/FeedMineUITests.swift  (primeira entrega; superado)
```

Base: `3b020a15abafef5f5ca5bcdaf056e436a4b92166` (`main`), branch `fix/reopen-journey`.
Efeitos locais: o device próprio `C2C4AD2B` foi apagado no fim desta sessão; o `84EA32E8` já havia sido apagado a
pedido do dono da rodada; o `7420F436` (fixture de migração) nunca foi tocado.
