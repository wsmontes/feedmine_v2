# Orçamento de convites: oferta contada quando o leitor alcança o card

Data: 2026-10-13. Build: `1.0 (33)` = `e0459944`. Corrige o bloqueador nomeado na entrega de produção
(2026-10-13): *"o ledger não é observável e a construção especulativa da view é contada como oferta mostrada"*.
Investigação e correção apenas onde o código apontava; nenhum oráculo, corpus, duração ou critério do
benchmark foi tocado.

## 1. Comportamento que estava quebrado

O orçamento de ofertas do F02 (round 10) tem como unidade declarada "cards the reader really passed". Na
prática, a oferta era **contada na construção da view**:

- `FeedMineApp.swift` avalia `cadence.offered(subject:on:cardsTraversed:isCompact:)` **dentro do corpo do card**,
  para cards à frente do leitor (`index > anchorIndex`), e o `LazyVStack` materializa uma margem à frente do
  viewport.
- `offered(…)` incrementava `offersShown`, fixava `lastOfferAt = cardsTraversed` (o contador de exposições *no
  momento do desenho*) e deixava `pendingSubject` pendente.
- Consequência: um bloco que o leitor nunca alcançou consumia o `sessionOfferCap` e antecipava o intervalo da
  próxima oferta; `ignoredOffers` podia crescer sem que ninguém tivesse deixado uma oferta sem resposta; e o
  trace (`editorial_offer`, `offers_shown`) lia ofertas que ninguém viu — a cláusula de frequência era
  inauditável.

Segunda metade do mesmo bloqueador: `EditorialExposureLedger` era `@ObservationIgnored` e não `@Observable`, então
o corpo que lê `editorialExposure.count`/`wasExposed(_:)` não reavaliava quando uma exposição nova chegava — a
elegibilidade ficava congelada até outra invalidação qualquer.

## 2. Causa e correção

Owner: `EditorialInvitationCadence` (`Sources/FeedMineUI/EditorialInvitationCadence.swift`) — nenhum mecanismo
novo, nenhum segundo scheduler, nenhum dono paralelo.

- `7160ffe1` (já escrita no worktree `codex/feed-layout-hang`, integrada): o ledger passa a ser `@Observable` e
  exposição repetida é no-op — a elegibilidade do convite acompanha a exposição real, sem invalidação espúria.
- `e0459944`: colocação e apresentação viram dois eventos.
  - `offered(subject:on:cardsTraversed:isCompact:)` **só coloca**: vincula o bloco ao host (a forma viaja com a
    oferta, como antes), gasta o sujeito e registra a colocação pendente. **Não** avança orçamento.
  - `presented(on:cardsTraversed:)` (novo) é o **único** lugar que avança `offersShown`, `ignoredOffers` e
    `lastOfferAt`. Ele só é chamado para o card em que a âncora da apresentação está — a posição real do leitor.
  - Uma colocação por vez (`Refusal.offerNotYetReached`) impede que uma passada de janela coloque um bloco por
    card elegível; uma colocação que o leitor não alcançou **expira** após um intervalo e devolve host e sujeito
    (uma oferta que ninguém encontrou não foi feita), reabilitando o sujeito para a posição correta.
  - O `editorial_offer` do trace passa a ser registrado na **apresentação**, com `offers_shown` já contado: a
    linha do trace volta a descrever o que foi desenhado.

## 3. Validação executada

| Prova | Comando / artefato | Resultado |
|---|---|---|
| Suíte do pacote | `swift test` | **1250 testes, 1 skipped, 0 falhas** (1246 antes; 4 novos) |
| Regras do orçamento | `swift test --filter EditorialInvitationCadenceTests` | **12/12** — inclusive os novos *"an unreached placement is not an offer shown"* (colocação não conta, expira e devolve o sujeito) e *"reaching the host card counts the offer exactly once"* (oscilação não conta duas vezes) |
| Nível de app (composição) | `xcodebuild test -only-testing:FeedMineAppTests/CompositionTests` (iOS 26.5, device `FeedMine`) | **48/48**, incluindo respostas na sessão seguinte do contexto e respostas de descoberta do leitor |
| Jornada nativa, catálogo real | `xcodebuild test -only-testing:FeedMineUITests/EditorialOfferBudgetUITests` | **PASS, 306,3 s** — primeira oferta cheia, segunda compacta alcançada **só pelo orçamento**, resposta preserva a posição, esconder sai da árvore de acessibilidade, escondido não oferta, reabilitar restaura |
| Build do app | `xcodebuild build` (Release implicitamente no archive) | **BUILD SUCCEEDED** / archive pareado abaixo |

Nota de ambiente: a suíte completa falhou uma vez com 760 erros `out of space` (volume raiz com <1 GB). Não é
regressão: os mesmos testes passaram após liberar espaço. O volume raiz é hoje o gargalo recorrente, e os
resíduos seguros (`/tmp/fm-*-derived`, `~/Library/Caches`) foram removidos.

## 4. Entrega ao TestFlight

`scripts/release-testflight.sh` com `ASC_KEY_ID=H3U55Z9WZ7`:

```
== archiving 1.0 (33) from e0459944 ==
archived: bundle=com.feedmine.app version=1.0 build=33 sha=e0459944
PAIRING OK: TestFlight build 1.0 (33) = e045994479e7e8237373be493b29440fecab7aab
Uploaded FeedMine
tag ios/1.0-build.33-e0459944 created (local, not pushed)
```

Estado Apple confirmado por API (`docs/reviews/evidence/2026-10-13-invitation-offer-accounting/testflight-status.jsonl`):

| Rota | Resultado |
|---|---|
| `builds/45cb12ab-51a1-4c63-8ac4-c41bc6e3ea2a` | versão **33**, `uploadedDate` 2026-10-13T19:45:00-07:00, `expired: false`, `processingState: **VALID**`, `APP_STORE_ELIGIBLE` |
| `builds/…/buildBetaDetail` | `internalBuildState: **IN_BETA_TESTING**`, `externalBuildState: READY_FOR_BETA_SUBMISSION`, `autoNotifyEnabled: true` |
| `betaGroups` | grupo interno **WawaTesters** com `hasAccessToAllBuilds: true` |

Ou seja: a build **1.0 (33)** está instalável pelo canal interno. A primeira consulta (imediatamente após o
upload) ainda não listava a 33 — o documento anterior dizia "enviada, processamento pendente" e é essa a
informação que agora fica corrigida, não antecipada.

Acesso instalável confirmado, **não** instalação observada: nenhuma sessão desta rodada viu a build 33 rodando
num iPhone físico do dono do produto.

## 5. O que isto NÃO prova

- **B01–B06 não foram reexecutados.** Este incremento não certifica gate algum; B03 (trace de 30 min) e B06
  (memória, energia, térmica, hitches em iPhone físico) seguem `NOT_RUN`.
- A cláusula de frequência de ofertas **num trace rico de 30 minutos** ainda não foi medida: a prova nativa cobre
  o percurso de aceitação do round 10, não a contagem agregada de `offers_shown` vs `cards_traversed` de B03.

## 6. Próximo bloqueador

**B03** — runway contínuo: 30 minutos de avanços efetivos (1 card/s e rajadas de 3 cards/s por 20 s a cada 5 min)
sem fim artificial, com `renderReadyAhead`/reserva registrados. Em seguida **B06**, que exige iPhone físico.

## 7. Relatórios externos arquivados

Os dois documentos que orientaram esta sessão estão em `docs/research/`, com proveniência no nome:
o diagnóstico de fluidez da V1 (`deep-research-report-ui-fluidity-v1-b5c2f59-2026-10-13.md`, snapshot
`b5c2f59` do repo legado `wsmontes/feedmine-dev`) e a auditoria de lacunas V1→V2
(`deep-research-report-v1-v2-gap-audit-2026-10-13.md`). O primeiro descreve o runtime da V1, que a V2
substituiu; o segundo tem backlog de produto que **não** revoga a ordem de execução vigente
(`docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md`: descoberta real, runway, preparação e gates).
