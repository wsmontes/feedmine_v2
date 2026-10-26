# NF-04 — superfície `deferred` e o retry que age (25/10/2026)

Registro da correção e da prova. Requisito normativo: NF-04 em
`docs/product/NOVAS_FRENTES_PARA_O_CODEX.md` — a cauda declara o trabalho **verdadeiro**; um estado adiado
("Aguardando nova oportunidade") não pode afirmar busca em andamento nem prometer instante de retry, e só pode
oferecer ação que realmente tente de novo. Ver também o mapa de produto, jornadas 1–2.

## O que mudou

| Arquivo | Mudança |
|---|---|
| `Sources/FeedMineUI/FeedLoadingView.swift` | `.deferred` diz “Aguardando nova oportunidade” + “Nada está sendo buscado agora.” (antes: “Procurando mais novidades…” e “Vamos tentar novamente em instantes.”); `recoveryActions` passa a oferecer só “Tentar novamente” para `.deferred` |
| `FeedMineApp/FeedMineApp/Resources/Localizable.xcstrings` | entram as duas chaves novas (pt-BR e en); saem as duas frases aposentadas |
| `Sources/FeedMineRuntime/RunwayController.swift` | `replenishment_requested` grava `trigger: fresh_supply \| policy` — instrumentação aditiva; nenhuma mudança de decisão |
| `FeedMineApp/FeedMineApp/TrustedFeeds.swift`, `AppComposition.swift` | hook **DEBUG** `FEEDMINE_DEFER_FIRST_FEED_ATTEMPT`: reporta a ausência real do launch como tentativa adiada; o próprio retry o consome (`allowRecovery`) |
| `FeedMineAppTests/CompositionTests.swift` | `DeferredWorkSurfaceTests`: hospeda a view num `UIHostingController` e lê os **pixels** no simulador (Vision, locale pt-BR fixo) |
| `FeedMineAppTests/FeedVisibleExperienceUITests.swift` | jornada de duas aberturas: superfície adiada → toque em “Tentar novamente” → conteúdo |

## Validação executada

| Verificação | Resultado |
|---|---|
| Suíte do pacote (SwiftPM) | 1.722 testes, 1 skip, 0 falhas (na rodada em que a correção de UI entrou) |
| Renderização discriminante | vermelho no topo anterior (`0e7a35ee`): “Procurando mais novidades...” aparece; verde após |
| Catálogo embarcado | `FeedTailWordingTests`: as duas frases novas resolvem em pt-BR e en; as aposentadas não voltam |
| App/simulador (pixels) | `TEST SUCCEEDED` — “Aguardando nova oportunidade”, “Nada está sendo buscado agora.”, “Tentar novamente”, sem “procurando” |
| Controle de harness | `PortabilityJourneyUITests.testOnboardingComposerResetAndStartBroad` **PASS** no mesmo device (AX funciona) |
| XCUITest da jornada | **PASS** (34–35 s) — `before_cards=0`, `card_count_after_retry=11`, `loading_surface_after_retry=false`, app em foreground |
| Release | `xcodebuild -configuration Release build` **BUILD SUCCEEDED** (o hook é `#if DEBUG`) |
| Controller do runway | `RunwayControllerTests` 34/34, incluindo o gatilho gravado em cada caminho |

Evidência da corrida (JSON do próprio teste):

```json
{"app_state":"4","before_cards":0,"card_count_after_retry":11,"deferred_at_ms":14782,
 "loading_surface_after_retry":false,"recovered_at_ms":33327,
 "title":"Aguardando nova oportunidade","test":"deferred-surface-retry"}
```

Artefatos externos ao repositório (não copiados aqui): `/tmp/nf04-r6-deferred.log`,
`/tmp/nf04-r6-deferred.xcresult`, `/tmp/nf04-r5-deferred2.log`, `/tmp/nf04-r5-control.log`.

## Como repetir a jornada

```sh
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,id=<device>' -derivedDataPath /tmp/nf04-dd \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:FeedMineUITests/FeedVisibleExperienceUITests/testDeferredSurfaceStatesTheWaitAndItsRetryBringsContent test
```

Abertura 1 (perfil sem publicar): `FEEDMINE_ONBOARDING=1`, `BLOCK_RSS_NETWORK=1`, `DISABLE_DISCOVERY=1`,
`EMPTY_FEEDS=1`, `LOCAL_FEEDS=1`, `USE_DEVELOPMENT_FEEDS=1`, `FIXTURE_ITEMS=12`.
Abertura 2 (mesma namespace): `SKIP_ONBOARDING=1`, `BLOCK_RSS_NETWORK=0`, `EMPTY_FEEDS=0`,
`FAIL_FIRST_FEED_ATTEMPT=1`, `DEFER_FIRST_FEED_ATTEMPT=1`.

## Checkpoint

Commitado nesta branch por autorização plena do usuário na sessão de 25/10, **sem push/merge/deploy**: `7a87e035` (superfície), `f7832caf` (gatilho do trace), `a5c3573d` (jornada de app + hook DEBUG), este registro no commit de documentação. A nota anterior, em relatórios de trabalho, de que o commit aguardava autorização deixou de valer.

## Limites (não ler como aprovação)

- **B03 continua FAIL mecânico.** A análise das duas paradas mediu, por ordinal do banco do próprio run, 14–15
  cartas **admitidas** à frente (16 antes do avanço); isso mostra que elas não são falta de runway **no modelo de
  admissão**. Não está medido que essas cartas estivessem **renderizadas** na tela — `frames` (40–54 fps, pior
  101–157 ms) é indício, não prova. O texto da cláusula e o proxy numérico seguem para arbitragem do dono.
- **Não é PASS global de NF-04.** A prova cobre a superfície `deferred` e sua ação; os demais estados da tabela
  (aquisição ativa, preparo durável, falha de transporte com cards) continuam no alcance dos testes anteriores.
- Suíte UI completa não foi reexecutada; a jornada nova é o único XCUITest desta entrega além do controle.
- Onde o chip tem um único slot (contexto de fonte/busca), o estado de trabalho não aparece — decisão de slot do
  NF-03, não corrigida aqui.
- O hook `FEEDMINE_DEFER_FIRST_FEED_ATTEMPT` é suporte de teste: `#if DEBUG`, inerte sem a flag, consumido pelo
  retry; nenhum caminho de produto o lê.
