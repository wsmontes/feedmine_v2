# Rodada 10 — inventário das alterações (2026-10-11)

Para **revisão e integração segura**. Cada entrada diz **o que mudou**, **onde** (símbolo/linha de âncora) e **por
quê**. Aviso de contexto: a árvore de trabalho está **63 commits atrás de `origin/main`** e carrega trabalho
não-commitado de sessões anteriores; por isso este inventário é **narrativo** (o que *esta* rodada mudou) e não um
diff contra `HEAD` — um diff contra `HEAD` misturaria trabalho de terceiros.

## Arquivos novos

### `Sources/FeedMineUI/EditorialInvitationCadence.swift` (~200 linhas)
- `EditorialExposureLedger` (linha ~26): `count`, `expose(_:)`, `wasExposed(_:)`. O orçamento conta **cards que o
  app realmente apresentou**, por identidade — uma janela renderizada não é uma exposição.
- `EditorialInvitationCadence` (linha ~54): `Budget` (4 / 12 / 2 / 96 / 4), `Refusal`, sessões **por `ContextKey`**
  (voltar a um contexto visitado **retoma**, não renova), `HostedOffer { subject, isCompact }` (linha ~92) — a
  forma viaja com a oferta —, alturas medidas (`remember(height:of:isCompact:)`, `height(of:)`,
  `slotHeight(of:isCompact:)`, linha ~188: o slot **nunca** é zero quando alguma forma já foi vista), e as
  transições `decision`, `offered`, `answered`, `reenabled`, `setHidden`, `beginSession`.

### `FeedMineApp/FeedMineAppTests/EditorialOfferBudgetUITests.swift` (novo)
O teste de aceitação no aparelho: leitor novo por corrida, portão da primeira execução, fonte no maior tamanho,
leitura contínua e os sete passos (oferta completa → oferta compacta menor → responder/desfazer sem mover →
esconder sem anunciar → nada oferecido enquanto escondido → reativar → preferência após reabrir), com as capturas
por passo e a asserção de conjunto (nenhum card se move).

### Documentos
`2026-10-11-round10-alternative-a-plan.md`, `...-evidence.md`, `...-consolidated-report.md`, este inventário; e
`PD-11` em `docs/product/PRODUCT_DECISIONS_2026-10-09.md` (a linguagem de "Menos de X", registrada como P1).

## Arquivos existentes alterados

### `Sources/FeedMineUI/FeedEditorialInvitationView.swift`
`isCompact: Bool = false` no `init`; o ramo **compacto** (título + ações, sem a pergunta longa nem a consequência);
a linha de ações extraída (`actions`) para as duas formas não divergirem no que fazem.

### `Sources/FeedMineUI/Settings/ReaderDiscoveryPreferencesView.swift`
`editorialTipsSection` (linha ~109) com o interruptor `discovery-editorial-tips` — "Mostrar sugestões do
FeedMine" — na página de preferências **existente**, com legenda; persistido por `store.update`.

### `FeedMineApp/FeedMineApp/AppComposition.swift`
|Onde|O que|
|---|---|
|linha ~50|`@ObservationIgnored let editorialExposure = EditorialExposureLedger()` — **um** ledger por composição (app), para que reconstruir a sessão não pareça um leitor que nunca leu|
|linha ~1067|a associação recebe o ledger **compartilhado** e o `discoveryProfile` de que o pool foi construído|
|linha ~1435 (`viewport(_:activity:)`)|`editorialExposure.expose(observation.anchor.cardID)` — a **única** fonte de "card exposto"|
|linha ~1206 / ~1215|`recordWindowFacts(..., traversed:, offersShown:)` e a linha de trace `editorial_offer`|
|linha ~1176 (`voteOnTopic`)|**não** chama mais `replaceSession()` (era o que movia o leitor); escoa o trace; e, se uma construção **já está em curso**, marca `pendingRebuild` para ela ler a resposta|
|linha ~1330 (`refreshFromTheReader`)|refresh explícito do leitor: reconstrói **apenas** quando o perfil armazenado mudou|
|linha ~1381 / ~1545|`FeedAssociation.editorialExposure` e `.discoveryProfile` (novos campos, injetados)|

### `FeedMineApp/FeedMineApp/FeedMineApp.swift`
`cadence = EditorialInvitationCadence()` substitui a caixa local; `editorialInvitation` (linha ~660) decide pelo
orçamento, recusa oferta em card **já exposto**, escolhe a forma e chama `presented`; `presented` (linha ~726)
desenha **nada** quando escondido (slot pela forma medida); `invitation` (linha ~747) leva a forma hospedada e as
ações para `cadence.answered`/`setHidden`; `recordWindowFacts` (linha ~780) leva `traversed`/`offersShown`;
`onChange` em `settingsStore?.settings.editorialTipsHidden` chama `cadence.reenabled` (linha ~511); `onTryAgain`
passa a chamar `composition.refreshFromTheReader()`.

### `FeedMineApp/FeedMineAppTests/CompositionTests.swift`
Três testes novos e um reforçado: `testTheAnswerIsConsumedWhenTheNextSessionOfTheContextIsBuilt` (linha ~929),
`testAnExplicitRefreshHonoursAnAnswerGivenAfterTheSessionWasBuilt` (~968) e
`testAnsweringInTheFeedChangesDiscoveryWithoutMovingTheReader` (~1012, agora exige **a mesma associação** depois de
responder).

### `FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj`
O arquivo de teste novo entrou no alvo **`FeedMineUITests`** (o projeto é mantido à mão, sem grupos
sincronizados): quatro entradas coordenadas — `PBXFileReference`, `PBXBuildFile`, `children` do grupo e a fase de
fontes do alvo.

## Arquivos congelados do benchmark (avaliador re-congelado, autorizado)

### `FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift`
O driver acompanha o card **por identidade**; registra **três resultados** de estabilidade (estável / instável /
não medível com motivo); prepara a cena com o bloco **acima** do leitor; repete a medição quando o card sai do
alcance — e **a repetição é o fato**; `bringIntoView` pede **na tela**, não "na árvore"; o B04 roda a jornada
**sem esconder as sugestões** e **sem gastar as ofertas** que ele vai medir; o background é medido no **mesmo
card**.

### `bench/oracle.py`
`gate_b04` julga os três resultados: `false` = falha; **`not-measurable` = gate incompleto** (`pass: None`, nunca
PASS); `true` em tudo = PASS. O estado relata as três contagens.

### `bench/EVALUATOR.sha256`
Re-congelado (duas vezes) por causa do driver e do oráculo; os seis arquivos verificam `OK`. **O critério de
produto não mudou.**
