# Rodada de 2026-10-15 (2ª) — build 47 no TestFlight interno e as jornadas de usuário

Este relatório cobre a rodada que produziu a **build 1.0 (47)** no TestFlight interno, o primeiro pass de jornada no
iPhone físico e três estudos que mudaram a ordem de trabalho do projeto. Cada número abaixo foi medido nesta rodada;
onde algo não foi executado, o texto diz `NOT_RUN` e a razão.

## 1. Ambiente e insumos

| Item | Valor |
|---|---|
| Repositório | `/Users/wagnermontes/Documents/GitHub/feedmine_v2` |
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
