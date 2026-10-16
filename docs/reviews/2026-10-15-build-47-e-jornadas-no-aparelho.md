# Rodada de 2026-10-15 (2ª) — build 47 no TestFlight interno e as jornadas de usuário

Este relatório cobre a rodada que produziu a **build 1.0 (47)** no TestFlight interno, o primeiro pass de jornada no
iPhone físico e três estudos que mudaram a ordem de trabalho do projeto. Cada número abaixo foi medido nesta rodada;
onde algo não foi executado, o texto diz `NOT_RUN` e a razão.

## 1. Ambiente e insumos

| Item | Valor |
|---|---|
| Repositório | `/Users/<user>/Documents/GitHub/feedmine_v2` |
| `main` ao fim da rodada | `3b020a15` (árvore limpa, igual a `origin/main`) |
| Base da build 47 | `f7c505d6` (branch `release/1.0-build.47`) |
| Aparelho físico | iPhone 14 Plus, `xcrun devicectl` id `BBA4F656-A5EA-5D81-934E-E484ED71B8E2` |
| Simulador de trabalho | `84EA32E8-0E25-47E9-8E99-BA1EB2265257` (o de `7420F436…` é fixture de migração de outro executor e **não foi tocado**) |
| Ferramenta de release | `scripts/release-testflight.sh` (exige árvore limpa, valida o par do catálogo antes e depois, carimba o SHA dentro do archive) |
| Chave ASC | `H3U55Z9WZ7` / issuer `0e1bd229-…-7bf989859bcc`, chave em `~/.appstoreconnect/private_keys/` |

## 2. Build 47 — publicação interna confirmada

```
== archiving 1.0 (47) from f7c505d6 ==
archived: bundle=com.feedmine.app version=1.0 build=47 sha=f7c505d6
PAIRING OK: TestFlight build 1.0 (47) = f7c505d6fba6e4c615bf5982ed82469fbb7b0b2e
Uploaded FeedMine
BUILD 1.0 (47) = f7c505d6fba6e4c615bf5982ed82469fbb7b0b2e  (tag ios/1.0-build.47-f7c505d6)
RELEASE_EXIT=0
```

Confirmação **do lado da Apple**, por consulta somente-leitura à API do App Store Connect (não do script):

```
build 47  state=VALID  expired=False  uploaded=2026-10-15T22:52:00-07:00
```

O que a build 47 carrega além da 46: a resolução do filtro sobreposto vencido no arranque (`b88d3f80`), a reposição
nascendo do déficit medido e o foreground como oportunidade (`90120ab1`), o host do leitor como uma página e uma
apresentação (`2cb61bbb`) e a correção da asserção de janela presa a tempo (`2718eb3f`).

## 3. Jornada no iPhone físico — o que o dono pediu, medido

Pass com o bundle de desenvolvimento (`com.feedmine.development`), catálogo público, **7 minutos de uso normal**,
nenhum gesto dirigido. Nada foi construído para o pass: o app já estava compilado.

| Pergunta do dono | Medida |
|---|---|
| O programa abre? | sim; `catalogue/sync.json` carimbado **no instante do lançamento** (`verifiedAt` = 813822286,84 ≈ 22:44:46); 1 edição, 11 segmentos |
| Imagens aparecem? | **40 cards: 19 `hero` + 21 `thumbnail`, 0 `textOnly`**; **40/40 com `media_key` e dimensões**; 147 blobs = **27.282.790 B** em `Media/sha256/`; **40/40 cards publicados com o blob no disco** |
| Conteúdos baixam? | **307 origens admitidas, 178 alvos registrados, 15 fontes responderam**; fontes que publicaram: `I Want to be Her!` 17, `diaspora diaries` 8, `aBlogtoWatch` 8, `Новые фотографии сайта 35photo` 7 |
| Estável? | PD-4: **0 pares adjacentes da mesma fonte** em 11 segmentos; os 40 cards **sobreviveram a um kill abrupto** (WAL não checkpointado) |
| Fluido? | `frames_total=31479  late=5  bad=0  severe=25  pior frame=377,9 ms` |
| Console | 529 linhas, **523 de telemetria de quadro**, e **zero** linhas sobre aquisição, fontes contatadas ou mídia preparada |

**Limite honesto:** o pass rodou contra o bundle de **desenvolvimento**; o app do dono no aparelho é
`com.feedmine.app` (1.0, build 44) e **não foi tocado** — nem `uninstall`, nem `erase`, nem leitura do contêiner dele.
Comparar o pass com um lançamento de produção exige instalar a 47 pelo TestFlight e repetir.

**Capturas de tela: `NOT_RUN`.** Não existe janela de espelhamento do aparelho neste Mac e `idevicescreenshot`
recusa (`Could not start screenshotr service`, mesmo com a imagem de desenvolvedor montada). A evidência visual
possível hoje é o censo do contêiner; a instrumentação para tornar o console diagnosticável foi comissionada.

**Armadilhas de `devicectl` medidas** (custaram tentativa e erro e estão registradas para o próximo): `install app`
exige caminho terminando em `.app` (senão `CoreDeviceError 3002`); `copy from --destination` exige **arquivo**, não
diretório (`error 11001`); `terminate` aceita só `--pid`; o `runtime.sqlite` só é legível junto do `-wal`
(4 KB no principal contra 832 KB no WAL) — `pragma wal_checkpoint(TRUNCATE)` na cópia é obrigatório.

## 4. Os dois controles inertes do leitor — corrigidos e provados no aparelho

O dono relatou que "Fechar" e "Abrir no site" não faziam nada. Um reconhecimento read-only localizou o mecanismo no
`ReaderHost.Coordinator`: (a) `close` era capturado fraco enquanto o corpo do app recria o host, e a dispensa só
acontecia `if controller.presentingViewController != nil`; (b) "Abrir no site" **empilhava** uma segunda página
`.reader` e `show` gravava `shown`/`presented` **antes** de saber se o `present` correu, com guarda de re-render que
devolvia cedo — um único `present` recusado deixava a página impossível de apresentar até o app morrer. NN-07 foi
inocentado (diff vazio em `Sources/FeedMineUI/Reader`).

Prova no **aparelho físico**, com o app lançado:

```
testABodyIsReadLocallyWithItsSourceHeadlineDateAndExit      passed (13.172 s)
testOpeningTheSiteFromTheLocalReaderIsAnExplicitRequestAndComesBackToTheFeed  passed (11.707 s)
Executed 2 tests, with 0 failures
```

No simulador, as mesmas duas jornadas mais as suítes do alvo do app: `CompositionTests` 64/0, `ReaderHostTests` 6/0
e as duas jornadas de UI — 72 casos, 0 falhas. A asserção de janela que estava presa a tempo foi medida antes e
depois: 17 numa execução e 18 noutra, com a âncora na última carta e `ahead=0` nas duas leituras — o número oscila
com a antecipação que a lane já admitiu, e o teto de 16 à frente é estrutural (`FeedSession.swift:233-235`).

## 5. Três estudos (todos com `arquivo:linha`, nenhum build/teste executado)

1. **`docs/reviews/2026-10-15-jornadas-de-usuario-v1-vs-v2.md`** (398 linhas) — as jornadas que os documentos da V1
   exigem (citações verbatim), o que a V2 faz hoje e **quais não têm testemunho**: a bateria cobre 15 de 22 como
   jornada, 4 são parciais e **8 não têm nada**. Razão estrutural: **nenhum teste da V2 compara pixels** — mídia tem
   testes de componente e zero testemunho de tela; rolagem tem asserções de estabilidade e nenhum número de quadro.
   Ordem: imagem aparecendo, fluidez por quadros, pressão de armazenamento, share sheet, aparência visual, lock
   screen/fones no aparelho, banner de clipboard (existe **sem call site**), BGAppRefresh concedido.
2. **Estrutura** (audit em `agent://SimplifyAudit2`) — `AppComposition.swift` **2.915 linhas** (um `init` de 302
   linhas), `FeedMineApp.swift` 1.320, `PublicationStore.swift` 1.166; 11 famílias de duplicação com veredicto; 5
   planos de split com faixas exatas; e **8 arquivos de scaffold com 322 linhas e zero declarações** (grep provado).
   O arquiteto **não autorizou** os splits grandes agora e restringiu a deduplicação ao que é local.
3. **Benchmarks óbvios** (audit em `agent://ObviousBench`) — a régua em três perguntas (âncora na jornada, veredito
   binário, e "se dá para inverter o veredito mudando um número sem tocar no produto, o número sai da cláusula"); 12
   medições de jornada que usam o traço que o app **já** grava; duas cláusulas atuais falham a régua (B02 `≥80%` de
   200 cards; B03 `≥1 s` escolhido); e a separação das constantes mágicas entre código (apagável), duplicadas e
   **régua congelada** (não se apaga sem o protocolo de revisão).

## 6. Outros agentes

- **Arquiteto (ChatGPT)**: verdict **BUILD 47 ACEITA como publicação TestFlight interna**; scaffolds e deduplicação
  local autorizados em branches próprias; splits grandes recusados agora; build 48 = **R5, imagem visível, reabertura
  sem loading, fluidez observada**; instrumentação de aparelho autorizada; e a correção da minha hipótese — R5 e PD-8
  **não** se fundem sem prova, porque R5 já tem conteúdo publicado que não chega à tela.
- **Codex (aplicativo, via `codex` app)**: diagnóstico do PD-8 entregue em `/tmp/pd8-diagnostico.md` — contesta a
  premissa histórica (o código atual já pagina a descoberta; a corrida de 2026-10-11 é **INDETERMINADA** sem a build
  e os artefatos dela) e localiza uma lacuna concreta: oportunidade recebida **durante a aquisição** reconsidera o
  runway **sem renovar o exame do catálogo** (`FeedRunwayDriver.swift:189-193` contra `:211-229`), e a cobertura não
  retenta falha da mesma geração (`RunwayAcquisitionCycle.swift:82-86`). Desarmou também uma armadilha do instrumento
  congelado: `expand.py:last_window_new > 0` dá **PASS falso**, porque ele só cria buckets com primeiras ocorrências.
- **Pesquisa (ChatGPT)**: a API da Apple para engasgo é **`XCTHitchMetric`**; o orçamento fixo de 60 Hz está errado
  em telas ProMotion; e prova de imagem exige duas metades (`XCUIScreenshotProviding`; existir na árvore de
  acessibilidade não prova pixel desenhado, e achar pixel no retângulo não prova que é a imagem certa).

**Registro corrigido**: `docs/evidence/ACCEPTANCE_RECORD.md` afirmava que a não-vacuidade do oráculo não fora
corrigida e que `bench/expand.py` não estava congelado. Ambos são falsos hoje — verificado por leitura em
`bench/oracle.py:357-378` (a cláusula fecha em `if candidates else None`) e em `bench/EVALUATOR.sha256:5`
(`shasum -a 256 -c` fecha 6/6 OK). O registro foi corrigido com data e proveniência.

## 7. O que esta rodada **não** prova

- A build 47 **não** foi instalada por tester nenhum; a instalação, a certificação externa e o B06 continuam provas
  distintas. O B06 segue `NOT_RUN`.
- O pass de jornada mediu o bundle de desenvolvimento, não o de produção.
- Nenhuma captura de tela do aparelho; a evidência de "imagem apareceu" é o censo do contêiner (blob presente por
  card), não o pixel desenhado — a asserção de pixel é justamente a lacuna que a build 48 ataca.
- Os 25 quadros severos estão medidos, não explicados.

## 8. Correção de proveniência: o R5 não estava aberto, e o comentário que dizia isso foi corrigido

Dois artefatos **documentais** descreviam um passado como se fosse o presente, e os dois foram corrigidos nesta
rodada com data, evidência e proveniência. O primeiro foi `docs/evidence/ACCEPTANCE_RECORD.md` (§6). O segundo é o
comentário de `testFirstRunOverTheRealCatalogueExpandsWithoutAGesture`, que declarava o defeito R5 aberto e a
expectativa "deliberately left FAILING".

**O que eu verifiquei por leitura direta, e não por relato:**

1. **A consulta não para na fronteira do segmento.** `Sources/FeedMinePersistence/PublicationStore.swift:608-615`
   monta o universo como `feed_segments s JOIN published_cards c` com `WHERE s.edition_id = ?` e avanço por
   `(s.ordinal, c.ordinal) > (?, ?)` — sem filtro de segmento. A explicação que o comentário dava era falsa.
2. **O defeito foi fechado em 2026-10-11.**
   `docs/reviews/2026-10-11-round6-cross-segment-materialisation.md:42-53` registra o traço cru do crescimento
   espontâneo (`admitted 1 -> 1`, `1 -> 2`, `2 -> 17`) e o teste **PASS em 16,9 s, sem gesto**
   (`received=0 completed=0 backward=0`), com a frase "O defeito P0 da rodada 5 está fechado". O gatilho é
   `startGrowthFollowUp()`: cadeia **limitada** (8 tentativas, 0,75 s entre elas) iniciada no fato da publicação.
3. **O que sobra como fragilidade é o acoplamento a polling**: a continuação do crescimento termina quando o
   contador acaba (`AppComposition.swift:2380-2407`), e `.settled` só reinicia a cadeia quando muda *supply* —
   e supply adquirida não é publicação (no bootstrap o `.settled` sai antes da tentativa de publicação,
   `ColdFeedBootstrap.swift:220-229`). São exatamente duas das constantes mágicas que o estudo de benchmarks
   listou para apagar.

O arquiteto **retratou o verdict anterior** que tratava o R5 como P0 comprovadamente aberto, e autorizou a correção
do comentário (documentação apenas, preservando corpo executável, asserções e timeouts, sem afirmar PASS novo antes
da medição desta revisão). O comentário foi corrigido citando o relatório R6, a consulta e a data.

**A execução nesta revisão fechou, e o teste PASSA:**

```
Test Case '-[FeedMineUITests.FeedMineUITests testFirstRunOverTheRealCatalogueExpandsWithoutAGesture]' started.
Test Case '-[FeedMineUITests.FeedMineUITests testFirstRunOverTheRealCatalogueExpandsWithoutAGesture]' passed (33.019 seconds).
EXIT=0
```

Método: dispositivo de simulador **criado para a medição e apagado antes dela** (o cenário de primeira execução exige contêiner limpo), alvo `FeedMineUITests`, árvore em `3b020a15` (a `main` de então, que é a revisão que a build 47 carrega — o comentário corrigido não altera o executável). O teste levou 33,0 s contra os 16,9 s do R6: o crescimento aconteceu, com folga confortável dentro do timeout de 60 s da asserção. **Não há regressão**, e a causa já refutada (fronteira de segmento) não foi reaberta.

## 9. PD-8: o que o diagnóstico do Codex sustenta, e o que eu conferi no código

O Codex (aplicativo, leitura somente, sem build) entregou o diagnóstico em `/tmp/pd8-diagnostico.md`. Duas
afirmações dele foram **verificadas por mim**, linha por linha:

1. **A oportunidade coalescida não renova o exame do catálogo.** `FeedRunwayDriver.drive` marca
   `reconsiderRequested` e retorna quando já há execução causal em curso (`:189-193`), e o laço que reconsidera
   (`while true { … if reconsiderRequested { continue } }`, `:224-229`) fica **depois** do `advanceDiscovery`
   (`:211-220`). O próprio código declara a fronteira como deliberada: *"One catalogue page per caller opportunity,
   outside the causal drain. Coverage may settle this page through the existing planner; it cannot load the next
   page here."* — ou seja, é contrato escrito, não descuido, e a decisão passa a ser sobre o fluxo de oportunidades
   e não sobre "renovar o exame".
2. **A cobertura não retenta falha da mesma geração.** `RunwayAcquisitionCycle.runCoverage` filtra
   `settled[$0.id] != $0.generation` (`:75-79`): uma vez que a geração de um alvo foi *settled* — e qualquer
   resultado não cancelado a marca, **inclusive falha operacional** (`AcquisitionCoordinator.swift:171-177`) —, a
   cobertura nunca a retenta. O caminho de déficit pode, porque filtra apenas `cooling`
   (`runway`/`runCoverage`: `available = eligibleTargets.filter { !cooling.contains($0.id) }`).

O Codex contesta, com razão, a premissa histórica: o código **atual** já pagina a descoberta, e atribuir a parada de
2026-10-11 ao código de hoje é **INDETERMINADO** sem a build e os artefatos daquela corrida. Ele também desarmou uma
armadilha do instrumento congelado: `bench/expand.py:last_window_new > 0` dá **PASS falso**, porque o instrumento só
cria buckets que contêm primeiras ocorrências (`expand.py:47-57`) — se todas caírem no primeiro minuto, a "última
janela" dele **é** a primeira. É o argumento decisivo para o instrumento novo de jornada nascer com hash próprio em
vez de editar o oráculo.

## 10. O gargalo que não estava previsto: o disco, e o runtime watchOS de 8,1 GB

Sete agentes compilando ao mesmo tempo levaram o volume a **898 MB livres**. O sintoma apareceu do jeito que a
regra do projeto prevê: uma corrida de UI test morreu com `Executed 0 tests` e *"Restarting after unexpected exit,
crash, or test timeout"* — **ENOSPC**, não defeito. O próprio agente que a rodou se recusou a tratá-la como
resultado, e essa recusa está certa: um veredito produzido faminto se descarta, não se relata. Eu já tinha
interrompido uma medição minha pelo mesmo motivo (o build frio do alvo de UI não chegou a rodar teste nenhum).

**A causa raiz não era cache de build: era um runtime que ninguém usa.** `xcrun simctl runtime list` mostrava dois
volumes — iOS 26.5 (em uso) e **watchOS 26.5, 8,1 GB**. Nenhum device watchOS existe nesta máquina (a seção watchOS
do `simctl list devices` está vazia) e o projeto é iOS-only (três targets: `FeedMine`, `FeedMineAppTests`,
`FeedMineUITests`), então o volume era peso morto re-baixável. Removido com o caminho suportado
(`xcrun simctl runtime delete 1D0A0B46-472A-418C-9311-EBBABA87C776`), o disco foi de 3,2 GB para **7,4 GB**.

**Regra operacional que sai daqui** (para a próxima rodada, e ela vai ter várias): antes de comissionar mais de três
agentes que compilam, medir o disco e checar `simctl runtime list`; e **nunca** deixar um build de gate ou de medida
competir com builds de agentes — foi exatamente assim que uma medição morreu em 2026-10-14 e de novo agora.

## 11. Livro-razão das branches desta rodada

Nenhuma destas foi mergeada na `main`: cada uma espera verdict do arquiteto (a `main` só avança por fast-forward
com verdict explícito). A coluna "verifiquei" diz o que **eu** rodei, não o que o agente relatou.

| Branch | Commit | Base | O que é | Verifiquei |
|---|---|---|---|---|
| `refactor/scaffold-purge` | `32f4ff34` | `4e405995` | oito arquivos comment-only removidos; intenção em `docs/architecture/SCAFFOLDS.md`; seis docs atualizados | `swift build` + `swift test` → **1399 testes, 3 skipped, 0 falhas**; `diff --check` limpo; `bench/` intocado |
| `fix/image-journey` | `9698346b` | `4e405995` | a lacuna nº 1: fixture de mídia (forma nova, default `off`) + asserção de pixel com controle | o alvo de UI: **2 testes, 0 falhas** (jornada 58,9 s; controle sem mídia 9,2 s) |
| `fix/reopen-journey` | `3e6c54b6` | `3b020a15` | o critério de cabeçalho da V1: testemunha no host + asserção que distingue frio de morno | `swift test` **1399/3 skipped/0 falhas**; fronteira U14 **18/0**; o teste novo **passa (40,3 s)** |
| `refactor/dedup-sweep` | `c25acf57` (WIP) | `4e405995` | F6/F7/F8/F9/F11 + `#if DEBUG` das três escritas de contador | **não** — WIP preservado, parado por disco; reverificar ao retomar |
| `fix/fluidity-journey` | `a7cc70a7` (WIP) | `2202cdd8` | jornada de fluidez com teto derivado de linha de base medida | **não** — WIP; agente novo retomando do commit |
| `feat/device-journey-instrument` | `951a208a` (WIP) | `2202cdd8` | resumo de jornada no console + `scripts/device-journey.sh` | **não** — WIP; agente novo retomando do commit |
| `fix/honest-surfaces` | `cbd9060c` (WIP) | `48c01010` | remoção do banner de clipboard (superfície morta) + jornada do share | **não** — WIP, aguardando verdict sobre remover ou ligar o banner |

Duas notas de integração que o diff engana: as branches nascidas de `4e405995` e `3b020a15` **aparecem** apagando
relatórios desta rodada, mas só porque nasceram antes de eu commitá-los — o cherry-pick de cada commit único na
`main` resolve sem arrastar deleção nenhuma. E as duas nascidas de `2202cdd8` carregam o bump `CFBundleVersion 47`
da branch de release; o cherry-pick precisa deixar o bump fora.
