# A fronteira restauração ↔ descoberta: o seed atrás da janela, e o que ele pode mudar

**Data:** 2026-10-16 · **Autor:** agente `ReopenBoundaryOwner` (tarefa delegada pelo agente principal)
**Branch:** `fix/reopen-journey`, worktree `/tmp/fm-reopen`, **base** `3e6c54b6` (`main` `3b020a15` + a primeira
entrega da reabertura)

**Pergunta que este relatório responde:** a primeira entrega da reabertura morna passou a ler o pool de descoberta
**na linha, antes do primeiro quadro**, para que a janela do leitor não esperasse por um salto de ator. Isso
resolveu a superfície de espera e criou três defeitos: (a) a adoção do pool era só editorial, então as fontes do
seed perdiam a função de fornecimento; (b) a consulta publicava assuntos num mapa da **composição**, escrito por
quem concluísse por último, então uma leitura do perfil anterior podia responder pelo perfil atual; (c) a prova
cold/warm proposta não comparava intervalos equivalentes. Este relatório entrega a fronteira corrigida, os dois
smokes que a provam (vermelho antes, verde depois), e a medição comparável — dizendo `não medido` onde não existe
instrumento, em vez de inventar número.

## 0. Método, ambiente e limites (para poder desconfiar deste relatório)

| Item | Valor |
|---|---|
| Repositório | `feedmine_v2`, worktree `/tmp/fm-reopen`, branch `fix/reopen-journey` |
| Base | `3e6c54b6` — a primeira entrega da reabertura (deste mesmo gate), filha de `3b020a15` (`main`) |
| Máquina | macOS 25.3.0 arm64 · Xcode 26.6 (17F113) · SDK iOS 26.5 |
| Simulador | device **desta sessão**: `A21D35C4-8358-4C43-BA11-29C2022A9DBF` ("FeedMine Boundary", iPhone 17 Pro Max, iOS 26.5). Os devices de outros agentes (`616105F9` Instrument, `7C4E3C51` Verify, `16DA3DB5` Bench) não foram usados nem desligados; o `7420F436` (fixture de migração) nunca foi tocado |
| Corpus / insumos | fixtures do próprio app (`FEEDMINE_USE_DEVELOPMENT_FEEDS=1`, `FEEDMINE_LOCAL_FEEDS=1`, `FEEDMINE_BLOCK_RSS_NETWORK=1`) e o catálogo que a build carrega (117 993 472 bytes). `bench/**`, o oráculo, o corpus congelado e os critérios **não foram tocados** |
| Comandos | `swift build` · `swift test` · `xcodebuild build-for-testing` / `test-without-building` (device acima) · `git diff --check` |
| Disco | ~2,7–3,6 GB livres durante a corrida (a máquina estava com builds de outro agente). Cada build medido antes; a corrida que produzisse `ENOSPC` seria descartada, não relatada |

**Fontes de outro dono.** A mudança toca seis arquivos (mais o relatório anterior e este):

| Arquivo | O que mudou |
|---|---|
| `FeedMineApp/FeedMineApp/AppComposition.swift` | o desenho todo deste gate (dono exclusivo deste agente) |
| `FeedMineApp/FeedMineApp/FeedMineApp.swift` | **uma linha**: o contador `known_subjects` do traço, porque o mapa de assuntos deixou de ser da composição e passou a ser da sessão |
| `Sources/FeedMineComposition/ReaderDiscoveryTraversal.swift` | a materialização de uma página foi extraída para um dono só (`materialization(of:)`) e a adoção de um pool entrou ao lado do exame, sem mover o cursor; `SyndicationAcquisitionSnapshot.adoptDiscovered` vive na extensão **deste mesmo arquivo** |
| `Sources/FeedMineComposition/SyndicationAcquisitionSnapshot.swift` | **intocado** |
| `Tests/FeedMineCompositionTests/ReaderDiscoveryPoolTests.swift` | o smoke de pacote do mesmo limite |
| `FeedMineApp/FeedMineAppTests/CompositionTests.swift` | os dois smokes do app e o portão determinístico |

`Sources/FeedMineRuntime/FeedRunwayDriver.swift` **não foi tocado** (outro owner), e `bench/**` também não.

## 1. Os três defeitos confirmados, com o ponto exato

1. **A adoção era editorial, não fornecimento** — e é um defeito que o diff **pendente** desta branch introduziu,
   não a base. Na base (`3e6c54b6`), o pool entrava na construção da sessão (`discovery:`), então as suas fontes
   eram registradas estaticamente no snapshot — o preço era a leitura síncrona no `init`. No diff pendente a
   leitura passou para trás da janela, mas `FeedAssociation.adopt(discovery:)` só acrescentava nomes ao mapa vivo e
   fontes à lista `discovery`: a aquisição e a **política efetiva** continuavam a ser derivadas apenas das páginas
   que a travessia materializa (`ReaderDiscoveryTraversal.liveSourceIDs()`, unida à política em
   `policyIncludingDiscovery`). Uma fonte que só existisse no pool do seed — fora da primeira página — não ficava
   elegível, não era adquirida e não entrava na política. A janela morna declarava descoberta e não fornecia nada
   dela.
2. **A consulta escrevia estado da composição.** `discoveryFeeds` — e, na base, `warmDiscoveryFeeds` também —
   terminava em `discoverySubjects = subjects`, um mapa **da composição** sobrescrito por qualquer leitura que
   concluísse por último (`3e6c54b6`, `AppComposition.swift:1340` no caminho assíncrono e `:1295` no morno; o mapa
   declarado em `:1490`, lido em `:1498`). Como `editorialSubject(for:in:)` consultava esse mapa, uma leitura
   preparada para o perfil A podia responder as ofertas da sessão que lê o perfil B (A→B, A concluindo por último);
   e o mesmo mapa alimentava o contador `known_subjects` do traço (`:1431`).
3. **A medição cold/warm proposta não era comparável.** A corrida "fria" da primeira tentativa levava o
   **onboarding dentro** do intervalo medido (o primeiro card só existe depois de o leitor percorrer o portão), e o
   número não separava preparação, espera e descoberta. Medir assim compara duas jornadas diferentes, não duas
   condições do mesmo arranque.

## 2. O que ficou (o desenho mínimo, passo a passo)

1. **O `init` morno não lê o catálogo.** `warmAssociation()` (`AppComposition.swift:1329-1335`) instala a janela a
   partir do checkpoint, como antes, e consulta apenas o **cache do processo** (`alreadyReadDiscovery`,
   `:1339-1342`): um arranque que não herdou nenhum pool simplesmente declara que ainda não tem descoberta.
2. **A oportunidade é liberada depois da janela.** A leitura sai em `launch()` (`:328-343`), que o host chama do
   seu próprio `task` (ver §4 para o que esse evento **comprova**).
3. **A consulta é um valor, não dois globais.** `DiscoveryRead` (perfil + fingerprint + entradas + assuntos) é o
   que `discoveryRead` (`:1365-1377`) devolve, e é o que o cache guarda — um mapa de assuntos da composição não
   existe mais; os assuntos vivem em `FeedAssociation.subjects`.
4. **Depois do `await`, antes de adotar:** este arranque ainda tem de ser o que lê (identidade, `active`, perfil e
   revisão do catálogo, e os dois fatos do próprio valor). Resultado obsoleto **continua válido no cache da sua
   chave** e não toca a associação ativa.
5. **A materialização é do mesmo dono.** `FeedAssociation.adopt(_:)` (`:2439-2455`) chama
   `SyndicationAcquisitionSnapshot.adoptDiscovered` (`ReaderDiscoveryTraversal.swift:193-196`), que faz a
   **mesma** materialização de uma página examinada (`materialization(of:)`, `:202-220`: alvo durável, cerca de
   geração, `enabled`, endpoint e idioma da entrada) e a entrega ao dono da travessia (`ReaderDiscoveryTraversal.adopt`,
   `:127-142`), que deduplica por alvo e **não move o cursor**.
6. **Só depois da materialização o que virou fornecimento é publicado** — nomes de exibição, a lista `discovery` e os
   assuntos, e só dessas fontes. A política **nominal** não é reescrita (ela diz o que o leitor escolheu); a
   política efetiva já inclui os IDs vivos da travessia. Nada é publicado, nenhuma aquisição é agendada, e a
   apresentação **não** é reinstalada pela adoção.

## 3. (a) O ponto exato onde a consulta pesada sai do caminho síncrono

**Antes** (base `3e6c54b6`): `AppComposition.init` → `association = try? warmAssociation()` →
`AppComposition.swift:1280` `let discovered = try warmDiscoveryFeeds(profile: profile)` → `:1292`
`Self.discoveryPool(profile:catalogueURL:)` **na thread que chama**. Essa linha fica entre a tela de lançamento e o
feed do leitor, e é ela que pagava os 2,5–2,8 s medidos para um perfil de primeira execução contra o catálogo de
118 MB.

**Depois** (este trabalho): `warmAssociation()` não chama mais nada que leia o catálogo —
`AppComposition.swift:1332-1333` passa `read: alreadyReadDiscovery(profile:)`, que só olha o cache. A leitura é
liberada em **`AppComposition.swift:328-343`**, dentro de `launch()`, depois de a associação (com a janela já
instalada por `FeedAssociation.init`) ter sido escolhida; a passagem pesada continua fora do main actor
(`liveDiscoveryQuery`, `:1621-1624`). O `await` que sobra no caminho síncrono é o do **cache** — um dicionário.

O caminho **frio** não mudou de propósito: `association(contextKey:)` continua a aguardar a leitura antes de
construir a sessão (`:1259`), porque ali existe uma superfície de preparação legítima (doutrina item 1). É
exatamente por isso que a medição de §6 mede as duas condições com o mesmo instrumento e começo/fim iguais.

## 4. (b) O evento que libera a descoberta: **INDETERMINADO** como "quadro apresentado"

O evento disponível hoje é a **avaliação do corpo** do host: `FeedMineApp.body` decide o ramo que está desenhando
(`launchBranch`, `FeedMineApp.swift:1344-1354`) e o declara à testemunha
(`FeedLaunchWitnessProof` → `FeedLaunchWitness.note`); o `launch()` da composição vem do `task` dessa mesma view
(`FeedMineApp.swift:583`). Isso **comprova** que o corpo foi avaliado com a janela do leitor como ramo — não
comprova que aquele quadro foi **apresentado** (composto e desenhado). Nada no caminho observa um commit de pixels,
e uma passagem cuja atualização é substituída antes de ser desenhada seria contada do mesmo jeito.

**Consequência para a alegação, dita em voz alta:** o que este trabalho pode afirmar é a metade fraca e verdadeira
— *nenhuma superfície de espera é desenhada entre a tela de lançamento e o feed do leitor*, que é o critério do
dono do produto — e **não** a metade forte ("a janela já estava apresentada quando a descoberta começou"). Esta
segunda fica **INDETERMINADO** com o instrumento atual. Para fechá-la seria preciso um sinal adjacente ao commit de
quadro (por exemplo a conclusão de uma transação de CATransaction para a janela do app), o que é instrumentação
nova e não foi inventada aqui.

## 5. (c) O que o smoke mostrou com a consulta suspensa e retomada fora de ordem

O instrumento é um `discoveryQuery` injetado (`AppComposition.init`) respondido por um portão determinístico
(`DiscoveryGate`, no alvo de testes): a composição **aguarda um valor**, então o teste decide quando cada leitura
conclui e em que ordem — sem `sleep`, sem timer, sem repetição. O produto não muda: sem injeção, a consulta é a
passagem destacada de sempre.

- **Smoke (a)** — `CompositionTests.testAWarmSeedOutsideTheWalkFirstPageIsSupplyOnlyIfTheAuthorityStillAllowsIt`:
  o leitor tem janela durável e perfil; a leitura sai e fica suspensa; **durante a suspensão** o alvo de uma das
  duas fontes que a leitura traz é revogado na autoridade durável; a leitura é respondida com as duas entradas (as
  duas a 300 e 301 posições do catálogo, muito depois de qualquer primeira página). O que se afirma depois:
  a revogada não é descoberta, não é elegível, não entra na política efetiva e não responde convite; a saudável é as
  três coisas, e o teste mostra **onde a travessia estava** quando a adoção aconteceu: a sua primeira página são os
  dois **primeiros** registros do catálogo e nenhum dos dois é a fonte que o pool trouxe (as duas fontes do seed
  estão a 300 e 301 posições). Que adotar um pool **não move** esse cursor é afirmado onde ele é observável sem um
  driver no meio — o smoke de pacote desta mesma fronteira. A janela e a âncora ficam exatamente o que eram.
- **Smoke (b)** — `CompositionTests.testAReadConcludingAfterTheReaderMovedChangesNothingOfTheSessionReadingNow`:
  a leitura do perfil A sai e fica suspensa; o leitor responde de novo (uma preferência) e a sessão é reconstruída
  (B, perfil próprio); a leitura de B conclui; **por último** conclui a de A, já com A aposentada. O que se afirma:
  B mantém o assunto que a **sua** leitura declarou (as duas leituras trazem a **mesma** fonte com assuntos
  diferentes — a colisão que um mapa da composição não sabia distinguir), o fornecimento de B é o de B, e A não é
  adotada nem ativada.
- **O controle, e o que ele mostra.** Os dois smokes rodaram **falhando** contra um estado deliberadamente
  ablacionado — `FeedAssociation.adopt(_:)` publicando o que a leitura trouxe **sem** materializar (o defeito (a)) e
  o `guard` depois do `await` **removido** (o defeito (b)) —, com os mesmos comandos e o mesmo device:
  `Executed 2 tests, with 5 failures (0 unexpected) in 8.070 (8.072) seconds` → `** TEST FAILED **`. As cinco
  reprovações são exatamente as cláusulas deste gate: em (a), "uma fonte que a autoridade revogou não é descoberta
  desta sessão" (l. 2821), "uma leitura atrás da janela é fornecimento: a fonte saudável é adquirível" (l. 2834) e a
  política efetiva (l. 2842); em (b), "uma leitura que chega depois de o leitor mudar não declara nada para A"
  (l. 2900) e "A não é adotada: não trouxe nada depois de ser aposentada" (l. 2901). Contra o estado entregue os
  mesmos dois testes passam (`Executed 2 tests, with 0 failures`). O arquivo foi restaurado ao **byte** do estado
  verde conferido (`sha-256 5169c50db155c7f190158020387f76d045ce657cf7ecd12abc7b79dc87edc2af`) e o diff conferido
  (`git diff --check` → EXIT 0).

## 6. Medição cold/warm comparável (e o que não é medido)

`FeedMineUITests.testReopenMeasurementColdAndWarmWithTheOnboardingAlreadyConcluded` faz três aberturas do **mesmo**
contêiner, e mede as duas últimas:

1. **não medida** — o leitor conhece o app e responde idioma e lugar; o transporte está recusado, nada publica, e
   por isso **não** sobra janela durável. Ela existe para que o onboarding esteja concluído **antes** das duas
   medições;
2. **fria, medida** — mesmo contêiner, sem janela durável, respostas no lugar, **nenhuma** superfície de onboarding
   (o transporte de fixtures responde agora, e é esta metade que carrega a leitura de descoberta do perfil);
3. **morna, medida** — o mesmo contêiner com a janela que a interação anterior deixou, rede bloqueada.

As duas medições usam o mesmo instrumento (`FeedLaunchWitness`), o mesmo começo (**construção do processo**) e o
mesmo fim (**a primeira passagem que carregou cartas prontas do leitor**). Precondições, impressas e **não**
cronometradas: o catálogo que a build carrega (117 993 472 bytes), as respostas que a primeira abertura dá no
compositor do onboarding (idioma e lugar), 120 itens por feed e o censo de cartas alcançáveis (> 20, exigido).

**A medição, na execução que passou** (o teste imprime tudo e afirma o que a tabela mostra):

| Metade | condição, como o **próprio registro** a declara | primeira passagem com cartas | cartas nessa passagem |
|---|---|---|---|
| **fria** (sem janela durável) | `kind=launch-progress`, 4 passagens, 730…1664 ms | **2262 ms** | 1 |
| **morna** (a janela que a interação anterior deixou) | `kind=none`, `wait_passes=0` | **1441 ms** | 57 |

Precondições impressas na mesma linha: catálogo de **117 993 472 bytes** (o arquivo do artefato, medido com
`stat`), as respostas que a primeira abertura deu no compositor do onboarding — idioma português e lugar Brasil,
ambos impressos como `true` porque os dois controles foram de fato encontrados e tocados —, **120 itens por feed**
e o censo de cartas alcançáveis = **57** (> 20, exigido pelo próprio teste).

Leitura dos números, com o limite desta máquina: numa execução anterior da mesma medição, na mesma sequência, o
morno deu `first_cards_ms=777` e o frio 3190 ms. A máquina é compartilhada (havia builds de outros agentes durante
estas corridas) e os absolutos variam; o que se compara é a **mesma execução** com o mesmo instrumento, o mesmo
começo e o mesmo fim — e a ordem e a ausência, que é o que o critério pede: no arranque frio há superfície de
espera (730…1664 ms) e o primeiro card chega a 2262 ms; no morno **nenhuma** superfície de espera é desenhada e as
cartas do leitor estão lá a 1441 ms. A diferença de cartas entre as duas metades não é um efeito da mudança: a
metade morna **restaura** as 57 cartas que a leitura da metade fria deixou prontas, e a fria está publicando a
primeira.

**A parcela da descoberta é `NÃO MEDIDA`.** Nenhum instrumento do processo cronometra a leitura do pool em
separado: a testemunha mede superfícies e o primeiro card, e depois desta mudança a leitura do pool acontece
**atrás** da janela, portanto fora do intervalo que essa testemunha delimita. Medir essa parcela exige
instrumentação nova (um fato a mais na testemunha ou um evento no traço) e não foi inventada aqui. O que o
relatório diz sobre o custo da leitura (2,5–2,8 s contra o catálogo de 118 MB) é **documentação pré-existente do
código**, não uma medição deste gate.

## 7. Comandos e execuções (as linhas exatas)

```
$ git diff --check                        → EXIT 0 (nenhuma linha com espaço em branco no fim, nenhum marcador)
$ git diff --stat 3e6c54b6 -- bench       → vazio (bench/ intocado)

$ swift build                             → EXIT 0
$ swift test                              → EXIT 0
	 Executed 1400 tests, with 3 tests skipped and 0 failures (0 unexpected) in 57.008 (57.153) seconds
   (a bateria do pacote inteira, na árvore entregue; inclui o smoke de pacote desta fronteira,
    ReaderDiscoveryPoolTests.testAPoolReadBesideTheWalkBecomesSupplyWithoutMovingTheCursor, 0.039 s)

$ xcodebuild build-for-testing -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
    -destination 'platform=iOS Simulator,id=A21D35C4-8358-4C43-BA11-29C2022A9DBF' \
    -derivedDataPath /tmp/fm-reopen-dd        → EXIT 0 (** TEST BUILD SUCCEEDED **)

$ xcodebuild test … -only-testing:FeedMineAppTests/CompositionTests/<os dois smokes>
	 Executed 2 tests, with 0 failures (0 unexpected) in 10.071 (10.075) seconds   → ** TEST SUCCEEDED **

$ xcodebuild test … -only-testing:FeedMineUITests/FeedMineUITests/testWarmRelaunchShowsTheFeedWithoutRenderingAWaitSurface
	 Executed 1 test, with 0 failures (0 unexpected) in 45.686 (45.691) seconds   → ** TEST SUCCEEDED **

$ xcodebuild test … -only-testing:FeedMineUITests/FeedMineUITests/testReopenMeasurementColdAndWarmWithTheOnboardingAlreadyConcluded
	 Executed 1 test, with 0 failures (0 unexpected) in 108.525 (108.527) seconds → ** TEST SUCCEEDED **

# CONTROLE: o mesmo comando dos smokes, contra o estado ablacionado (adoção sem materializar; guard do await fora)
$ xcodebuild test … -only-testing:FeedMineAppTests/CompositionTests/<os dois smokes>
	 Executed 2 tests, with 5 failures (0 unexpected) in 8.070 (8.072) seconds    → ** TEST FAILED **
$ cp /tmp/fm-green-AppComposition.swift FeedMineApp/FeedMineApp/AppComposition.swift   # reversão ao byte verde
$ shasum -a 256 FeedMineApp/FeedMineApp/AppComposition.swift
	5169c50db155c7f190158020387f76d045ce657cf7ecd12abc7b79dc87edc2af
```

Evidências brutas (logs completos do `xcodebuild`/`swift test`, todos em `/private/tmp/`):

| Arquivo | O que é |
|---|---|
| `fm-boundary-build-final.log` | `swift build` da árvore entregue (EXIT 0) |
| `fm-boundary-test-final.log` | `swift test` da árvore entregue (1400 testes, 0 falhas) |
| `fm-boundary-build2.log` | `build-for-testing` do alvo do app (** TEST BUILD SUCCEEDED **) |
| `fm-boundary-smokes-green4.log` | os dois smokes **passando** + a testemunha do portão |
| `fm-boundary-smokes-red.log` | os dois smokes **falhando** contra o estado ablacionado |
| `fm-boundary-crit3.log` | o teste de UI da reabertura (frio viola / morno satisfaz) |
| `fm-boundary-crit4b.log` | a medição comparável, com as precondições e os dois intervalos |

Hashes (sha-256) da árvore entregue, para conferir sem reabrir o diff:

```
5169c50db155c7f190158020387f76d045ce657cf7ecd12abc7b79dc87edc2af  FeedMineApp/FeedMineApp/AppComposition.swift
344c9b72743cc01bff35dbcb09d88640ec569c2327d1a2d3203107165e37b2cd  FeedMineApp/FeedMineApp/FeedMineApp.swift
5824cc36373a4bb65c6c54fe47bbd56bec1ad1f68af1414b60f241a70dbefdd9  FeedMineApp/FeedMineAppTests/CompositionTests.swift
9f6e17c3e5c8ed558f87912ce0c267de2c632866b0c2e803f8408a80187495c6  FeedMineApp/FeedMineAppTests/FeedMineUITests.swift
a24fcabd89d2978e8187d9e1e77c49d4618dffdbb4275ea781f358fe55b494cc  Sources/FeedMineComposition/ReaderDiscoveryTraversal.swift
da67d4649a20c0a712eb0692afc952e2f9da5eeb02eccddc0d6da9bceafdd2d5  Tests/FeedMineCompositionTests/ReaderDiscoveryPoolTests.swift
ca82090298887727aa2df0e7f75f1fed7d3f6ec581ce21fd5029132e57b3e1a7  docs/reviews/2026-10-15-jornada-de-reabertura-morna.md
```

Efeitos locais: o device desta sessão (`A21D35C4-8358-4C43-BA11-29C2022A9DBF`, "FeedMine Boundary") foi apagado no
fim; os devices de outros agentes (`616105F9`, `7C4E3C51`, `16DA3DB5`, `7420F436`) nunca foram tocados. O
`/tmp/fm-reopen-dd` (derived data desta sessão) fica em `/private/tmp` e pode ser apagado por qualquer um.

## 8. O que foi deliberadamente deixado de lado

- **A identidade da âncora** continua afirmada pelo teste que já existia
  (`testAForcedCloseReopensOnTheCardTheReaderWasReading`); este trabalho não a duplica.
- **O caminho frio continua aguardando a leitura** antes de construir a sessão
  (`AppComposition.swift:1259`): ali a superfície de preparação é legítima, e mudar isso seria outra decisão de
  produto.
- **A política nominal não é reescrita** pela adoção. O que muda é a política **efetiva**
  (`policyIncludingDiscovery`), que já une os IDs vivos da travessia — a mudança é o que entra na travessia, não
  uma segunda régua de elegibilidade.
- **Nada em `bench/**`, no oráculo, no corpus ou nos critérios congelados** foi tocado; nenhum gate B01–B06 foi
  rodado e nenhum veredito é afirmado aqui.
- **O evento que libera a descoberta não foi endurecido**: ver §4 — a alegação forte fica INDETERMINADO em vez de
  ser comprada com instrumentação nova dentro deste gate.
