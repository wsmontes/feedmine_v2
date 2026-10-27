# PD-5 × cauda oculta: a Edição publicada deixou de ser reescrita (2026-10-26)

Relatório durável da correção P0 no checkout `feedmine_v2`, branch `product/nf04-tail-truth`, base `9b746e9e`.
Nada empurrado, mesclado, publicado ou enviado. `bench/**`, `DiscoveryBenchmarkTests.swift`, `tools/b03-pacing`,
`corpus`, manifestos, o par do catálogo e `capacity-ready.json` não foram tocados. Nenhum simulador foi apagado
(`simctl erase`/`delete`) e nenhum banco, trace ou `xcresult` alheio foi removido.

## Veredito

**Defeito confirmado e corrigido no owner de persistência.** `PublicationStore.succeedTail` apagava de
`published_cards`/`feed_segments` o sufixo de uma Edition **já publicada** — arquivando-o em
`retired_published_cards`/`retired_feed_segments` — e inseria no mesmo ordinal um segmento novo com a revisão
mais recente. As linhas eram de fato publicadas, não candidatas nem reserva: são `published_cards` da Edition
ativa, lidas por `PublicationStore.cards(editionID:around:)`, por `PublicationHistory.restore` e pela janela do
leitor.

A hipótese de trabalho estava correta em substância e precisa em um ponto: **a linha antiga não é destruída** —
ela é movida para as tabelas `retired_*`, que `PublicationStore.card(id:)`, `mediaLocator` e `sourceDisplayName`
continuam lendo. O que muda é a Edition: a ocorrência publicada sai da sequência e outra entra no mesmo lugar.
O leitor que rola até aquela posição, ou reabre o app, vê `E2` onde havia `E1`. É exatamente o que PD-5 regra 4
e INV-17 proíbem ("whether the user has seen the card or not"; "inclusive se ela ainda não foi vista").

## Requisito aplicável (lido nas autoridades, não inferido do código)

- `PRODUCT_DECISIONS_2026-10-09.md` **PD-5 regra 4** (revisão de 2026-10-10): a partir da publicação,
  occurrence ID, texto/ação selecionada, layout e contrato de mídia são imutáveis **tenha o leitor visto ou
  não**; "a published text-only card cannot silently acquire a hero image"; "late media alone never rewrites
  history"; uma edição legítima posterior pode publicar ocorrência nova.
- PD-5, parágrafo final: **"Supersedes the old permission to re-prepare published-but-unseen cards while the app
  is inactive."** É a autoridade que fecha o conflito com PD-1 regra 2 — e é posterior.
- `PRODUCT_INVARIANTS.md` **INV-17**, último parágrafo: conteúdo e contrato visual imutáveis a partir da
  publicação, inclusive antes da exposição; ordem/geometria protegidas após admissão.
- `docs/superpowers/specs/2026-10-09-successor-tail.md` (T5) é de 2026-10-09, **um dia antes** da revisão do
  PD-5 que revogou a permissão. Não é autoridade concorrente.

**Precedência e escopo da leitura (registro único, feito aqui).** O texto das duas autoridades **não** foi
alterado: `PRODUCT_DECISIONS_2026-10-09.md` e `PRODUCT_INVARIANTS.md` voltaram exatamente ao conteúdo de
`9b746e9e`, e a nota que esta lane havia acrescentado sob PD-5/INV-17 foi removida para preservar as autoridades
originais. A leitura aplicada é esta e vive só neste documento:

1. PD-5, na revisão de **2026-10-10**, é **posterior** a PD-1 regra 2 e declara-se supersessor em texto
   ("Supersedes the old permission to re-prepare published-but-unseen cards while the app is inactive").
   INV-17, no último parágrafo, diz a mesma coisa de forma independente ("inclusive se ela ainda não foi vista").
   Onde os dois textos se encontram, vence o posterior.
2. **Escopo do estreitamento — declarado, não negado.** PD-5 estreita PD-1 regra 2: a condição "ainda não
   **vista**" deixa de autorizar o trabalho de re-preparação; o que resta é "ainda não **publicada**". Isto **é**
   uma mudança de critério no ponto de encontro, não uma reafirmação ("nenhum critério mudou" seria falso).
   Fora desse ponto, PD-1 regra 2 continua válida como escrita: no máximo uma ocorrência futura por origin.
3. Consequência operacional única: uma ocorrência **publicada** é imutável em ID, texto/ação, layout, contrato de
   mídia e ordinal, tenha o leitor visto ou não; uma edição material dela é **retida** enquanto está à frente do
   leitor e nasce como ocorrência **nova**, em segmento posterior, quando ela deixa de estar. Nada é suprimido
   para sempre.

O spec `docs/superpowers/specs/2026-10-09-successor-tail.md` (T5) mantém a nota de supersessão no topo: é de
2026-10-09, anterior à revisão que revogou a permissão, e o texto abaixo da nota é histórico.

## Causa (cadeia completa)

| Elo | Arquivo | Papel no defeito |
|---|---|---|
| Gatilho | `FeedMineApp/FeedMineApp/AppComposition.swift` `background()` | com `active && !visible`, pedia `hiddenTail(editionID:protectingThrough: última carta admitida)` e chamava `maintainTail` |
| Owner de runtime | `Sources/FeedMineRuntime/HiddenTailMaintenance.swift` | relia a cauda publicada, reselecionava as mesmas origins na revisão mais recente, fazia prefetch/prepare e chamava a sucessão; aplicava quando **qualquer** carta mudou de revisão ou `mediaKey` |
| Owner de publicação | `Sources/FeedMinePublication/PublicationCoordinator.swift:succeedTail` | traduzia a seleção e delegava ao store |
| Escritor | `Sources/FeedMinePersistence/PublicationStore+History.swift:succeedTail` | arquivava e **apagava** o sufixo de `published_cards`/`feed_segments`, inseria o segmento novo no mesmo ordinal |

As cercas existentes (`visible == 0`, geração do lease, `high_water`, admissão protegida, bookmark/usage no
sufixo) impediam tocar no **prefixo visto/admitido** — por isso B04/B05 não mediam o defeito. A faixa
"publicada e não vista" era justamente a que PD-5 declara sagrada.

## Prova red (HEAD `9b746e9e`, antes da correção)

Sonda temporária (não commitada) publicando duas cartas — `seen` (âncora/checkpoint) e `E1` (publicada, nunca
exposta) —, entregando a edição material `E2` e executando **o mesmo caminho que o app executa em background**
(`PublicationStore.hiddenTail` → `HiddenTailMaintenance.run`):

```
PROBE before: ["26D16DD5/seen", "4C037915/E1"]
PROBE maintenance result: applied
PROBE after: ["26D16DD5/seen", "CD776318/E2"]
error: XCTAssertEqual failed: ("[26D16DD5-…, CD776318-…]") is not equal to ("[26D16DD5-…, 4C037915-…]")
       - the Edition must keep the published occurrence
error: XCTAssertEqual failed: ("[Optional("seen"), Optional("E2")]") is not equal to ("[Optional("seen"), Optional("E1")]")
       - published text must not be rewritten
```

`E1` saiu da Edition, `E2` entrou no mesmo ordinal, `result == .applied`, checkpoint/âncora intactos. A isso
somavam-se os testes que **pinavam** o defeito como intencional: `PublicationHiddenTailLeaseTests` (2),
`SessionStoreTests.testUnseenSuccessionArchivesOldValuesAndRollsBackOnIdentityConflict`,
`PublicationMediaUseTests` (1 asserção) e `EditedArticleRecurrenceTests.testHiddenTailUsesLatestEditAndRestoresSeenPrefix`.

## Correção: o mecanismo foi retirado, não cercado

`PD-5` revogou a permissão inteira; não havia uso legítimo restante de uma API que reescreve o sufixo publicado.
Um guard que só devolvesse erro deixaria o caminho vivo, pagando seleção de 256 candidatas, prefetch de mídia e
`prepare` em background para depois recusar. Removido:

- `PublicationStore`: `succeedTail`, `TailSuccessionResult`, `HiddenTailLease`, `hiddenTail`, `seenMaterial`,
  `setVisibility` (a visibilidade só existia para revogar o lease);
- `PublicationCoordinator.succeedTail`;
- `FeedMineRuntime/HiddenTailMaintenance.swift` (arquivo inteiro) — o único trabalho que ele fazia era a sucessão;
- `AppComposition`: a propriedade `maintainTail`, a closure que a montava (incluindo o `reserve.markPublished`
  que servia à sucessão), a chamada em `background()` e as três escritas de `setVisibility` (restore, foreground,
  close);
- testes cujo assunto era o mecanismo, com o motivo registrado abaixo.

Preservado, sem caminho paralelo novo: **`PublicationStore.appendSegment`** (append-only) e o caminho de produção
existente que o usa — `LocalProductionSlice` → `PublicationCoordinator.append(expectingTailCardID:recurrence:)`.
É ele que já publica uma edição material como ocorrência nova (`PublicationOriginRecurrence.whenMaterialChanged`)
e que recusa duplicata de material igual. Nenhum ledger, scheduler ou tabela de história foi criado; as tabelas
`retired_*` e as leituras delas permanecem porque guardam linhas históricas de builds anteriores (e a migração
não pode ser reescrita).

## Comportamento depois da correção

| Situação | Antes | Depois |
|---|---|---|
| Ocorrência publicada, **vista** | preservada | preservada |
| Ocorrência publicada, **não vista**, chega edição material | apagada da Edition e substituída no mesmo ordinal | **preservada em todos os campos e no ordinal**; a edição é retida |
| Ocorrência publicada, não vista, chega só mídia (text-only → com imagem) | substituída (aquisição silenciosa de hero image) | preservada; mídia tardia não reescreve nada |
| Candidato **nunca publicado** | publicado normalmente | publicado normalmente (provado no teste novo, no mesmo turno em que a edição é retida) |
| Edição material depois que a ocorrência deixou de estar à frente do leitor | reescrita (ou escolha ambígua) | nova ocorrência, novo `PublicationCardID`, segmento posterior; a antiga fica intacta |
| Edição material de material **igual** | recusada por "allSatisfy" | recusada pelo guard de `appendSegment` (`duplicateOriginInEdition`) |

A revisão não é suprimida para sempre: enquanto a ocorrência publicada está à frente do leitor, PD-1 regra 2
manda não criar uma segunda ocorrência futura; quando ela deixa de estar (o leitor passa por ela), a revisão
entra pelo append e gera ocorrência nova. É o estado medido no teste novo.

## Testes

Novo, causal e permanente — `EditedArticleRecurrenceTests.testPublishedUnseenOccurrenceIsImmutableAndTheEditWaitsForAFutureSegment`:

1. primeira Edition publica `seen` + `E1`, com checkpoint/âncora em `seen` e `E1` publicada e à frente do leitor
   (afirmado por `exposure(...).unseenOriginIDs`);
2. snapshot de **todas** as cartas vivas da Edition, do primeiro segmento e do checkpoint;
3. `E2` (edição material) e uma história nunca publicada;
4. produção com o leitor ainda antes de `E1`: publica a história nova, **retém** `E2`, e a carta `E1` permanece
   idêntica em todos os campos (comparação de `CardRecord` inteiro), no mesmo ordinal, com o primeiro segmento
   e o checkpoint inalterados;
5. **relaunch**: `PublicationHistory.restore` mostra `seen, E1, late` — a revisão do card é `e1`, não `e2`;
6. o leitor vê `E1` (`markSeen`), então a produção publica `E2` como ocorrência **nova** (ID diferente,
   `originRevisionID == e2`), com ordem `seen, E1, late, E2` e `E1` ainda idêntica; segmento inicial e
   checkpoint inalterados.

### Regressão de app: o owner do ciclo de vida (executada)

`CompositionTests.testPD5PublishedUnseenTailSurvivesTheLifecycleAndALaterEditBecomesANewOccurrence`
(`FeedMineApp/FeedMineAppTests/CompositionTests.swift`). Existe porque `swift test` **não compila** o app
(`Package.swift` não tem target para `AppComposition`): até esta rodada, a sucessão podia voltar inteira pelo
`background()` e a suíte de 1740 testes passava verde. O teste afirma o contrato público, não a API removida.

1. **Premissa medida, não suposta.** A fonte lenta é retida: o bootstrap publica **só a âncora**. Liberada, o
   suprimento publica cartas **à frente** do leitor; o teste pergunta ao store quais origins pedidas estão
   `unseenOriginIDs` e **falha com diagnóstico** quando o conjunto é vazio, quando a alvo não é uma linha
   publicada ou quando ela é a própria âncora. Nada de "unseen" inventado e nenhuma policy ajustada para passar.
2. **Snapshot** das linhas publicadas ao redor da âncora (`PublicationStore.cards(around:backward:forward:)`, o
   `CardRecord` inteiro: id, origin/revision, título, texto, layout, mídia, ordinal), do **primeiro segmento** e da
   posição do leitor por **identidade de cursor** — `editionID`, `cardID`, `anchorPlacement`. Ficam de fora, de
   propósito, `updatedAt` (instante da escrita: todo re-checkpoint legítimo o move) e `topDelta`/`cardHeight`
   (medida de layout: `SessionCursor.swift:46-47` diz que Dynamic Type, largura e disponibilidade de mídia mudam
   layout, não a identidade do cursor; restore/foreground regravam com medição nova). Comparar qualquer um deles
   reprovaria por remedição legítima, não por defeito — foi o que aconteceu na primeira versão (`green3`).
3. **Edição material** da ocorrência publicada e não vista (`ContentStore`, `expectedCurrent` = a revisão publicada).
4. **`background()` + `foreground()`** no owner real: prefixo publicado idêntico, primeiro segmento inalterado,
   posição do leitor inalterada, mesma associação e mesma projeção (`sequenceID`).
5. **Relaunch** em processo novo sobre o mesmo container: mesmas linhas publicadas na mesma ordem, mesmo checkpoint
   por identidade, âncora restaurada é a do leitor, e `PublicationHistory.restore` devolve a **revisão publicada**.
6. **Produção depois do relaunch**: o leitor vê a ocorrência (`markSeen`) e chega à cauda admitida
   (`explicitTailApproach`); a história nunca publicada é publicada, a edição material nasce como **ocorrência
   nova** no fim (ID novo, `originRevisionID` da edição), a publicada continua idêntica no mesmo ordinal e o
   primeiro segmento nunca é reescrito.

O desfecho medido é: **depois do relaunch e da oportunidade de cauda, a história nova e a recorrência estavam
publicadas**; e a comparação controlada mostra que a oportunidade é o que separa os dois estados — `green4` e
`green5` rodam o mesmo cenário e diferem **só** nela, e sem ela nada foi publicado em 90 s. O teste não carimba a
ordem interna (a publicação pode ter caído no próprio `launch()` do relaunch); ele afirma o desfecho. O *motivo*
interno — foreground estacionário mede 0 cartas/s, o `RunwayPolicy` responde `healthy` e a caminhada de candidatos
só publica o que examinou desde o cursor durável — é **leitura de código** (`CompositionTests` ~:783,
`CandidateProvider.candidates(for:after:)`), não medição desta rodada. O que é medição desta rodada é o par acima.

Reescritos/deletados, com justificativa (autoridade posterior, não conveniência):

| Teste | Ação | Por quê |
|---|---|---|
| `EditedArticleRecurrenceTests.testHiddenTailUsesLatestEditAndRestoresSeenPrefix` | substituído pelo acima | fixava a reescrita (`["seen","E3"]`) como intencional; PD-5 a proíbe |
| `FeedMinePersistenceTests/PublicationHiddenTailLeaseTests.swift` | removido | os dois testes existiam para a sucessão (`K-14`) |
| `SessionStoreTests.testUnseenSuccessionArchivesOldValuesAndRollsBackOnIdentityConflict` | removido | assunto era arquivamento/rollback da sucessão |
| `SessionStoreTests.testSeenHighWaterDoesNotRewindAndHiddenLeaseIsRevokedByForeground` | renomeado/reescrito para `testSeenHighWaterDoesNotRewind` | preserva a propriedade real (high water não recua; ver a carta não remove nem reordena nada) e perde só o lease, que não existe |
| `PublicationMediaUseTests.testSharedBookmarkSurvivesReopenAndProtectsUnseenTail` | renomeado `testSharedBookmarkSurvivesReopen`; asserção de sucessão removida | bookmark continua coberto; "protege a cauda" dependia do mecanismo |

## Verificação executada

| Comando | Resultado |
|---|---|
| `swift test --filter "EditedArticleRecurrenceTests\|SessionStoreTests\|PublicationMediaUseTests"` | 10 testes, 0 falhas |
| `swift test` (pacote completo) | **1740 testes, 1 pulado, 0 falhas** (111,6 s) |
| `xcodebuild -project FeedMineApp.xcodeproj -scheme FeedMine -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/FeedMineApp-elrtsjoinadyscatutssffaaecyb build` | **BUILD SUCCEEDED** (AppComposition compila após as remoções) |
| `xcodebuild test … -only-testing:FeedMineAppTests/CompositionTests/testPD5PublishedUnseenTailSurvives… -collect-test-diagnostics never -resultBundlePath /tmp/pd5-lifecycle-green5.xcresult` | **TEST SUCCEEDED**, 1 teste, 0 falhas (1,046 s) |
| o mesmo comando, mais `-only-testing:…/testS1SameSessionStoreAcrossViewportRefreshAndLifecycle` (`green6`) | **TEST SUCCEEDED**, 2 testes, 0 falhas (1,613 s) — a regressão PD-5 roda **duas vezes** verde e o andaime S1 continua verde |
| o mesmo comando de novo, depois de restringir a comparação do checkpoint a `editionID`/`cardID`/`anchorPlacement` (`green7`) | **TEST SUCCEEDED**, 2 testes, 0 falhas — as medições de layout não são identidade |

Simulador e DerivedData: `iPhone 17 Pro Max` (`220FD546-…`), DerivedData default
`FeedMineApp-elrtsjoinadyscatutssffaaecyb` reusado; `-collect-test-diagnostics never` é opção suportada do
`xcodebuild` desta máquina (`xcodebuild -help`: `on-failure|never`) e foi usada por orçamento de disco — ela muda
**apenas** a coleta de diagnóstico em falha, não assertions, critérios nem resultados. Logs, `xcresult` e saída
completa preservados em `/tmp/pd5-lifecycle-green{1..6}.*`.

## Negativos e limitações (honestos)

- Passe de limpeza `f5d3e087` corrigiu os comentários que ainda descreviam o mecanismo removido
  (`LocalProductionSlice`, `PendingMediaReconsideration`, `PreparedReserve`, três notas em `AppComposition`, a
  proveniência da janela de 256 em `SourceDiversityContractTests`). Nenhuma linha executável mudou; só o
  `swift build --build-tests` + 37 testes dos arquivos tocados foram rodados depois dele, então o
  **BUILD SUCCEEDED** do app target vale para o código do commit `399a0dd1` e não é uma segunda medição.
- **Não** foi rodado o bench (`bench/**` é proibido nesta tarefa) e **não** há alegação de PASS de B03/B04/B05. A
  correção só pode deixar a história publicada mais estável; não foi medida por gate.
- **Não** foi executado teste de UI nem em dispositivo, e **nenhum gate** foi rodado. A prova é de pacote +
  compilação do app + o alvo de testes do app (`CompositionTests`, executado duas vezes verde nesta rodada).
- **O red de app contra o mecanismo antigo não foi executado**, e isto é limite medido, não escolha de conveniência:
  reintroduzi-lo exige restaurar quatro fontes de `9b746e9e` (`PublicationStore+History.swift`,
  `PublicationCoordinator.swift`, `HiddenTailMaintenance.swift` e os ~5.000 linhas de `AppComposition.swift`) e
  dois rebuilds completos do app; o orçamento de disco (≈0,8 GiB) e de tempo desta rodada não comporta. O que está
  medido é o **writer** (arquivar em `retired_*`, `DELETE FROM published_cards`/`feed_segments`, insert no mesmo
  ordinal) e o **gatilho por leitura de código** (`background()` → `hiddenTail` → `HiddenTailMaintenance`). O teste
  novo afirma o contrato que aquele writer viola — igualdade do `CardRecord` inteiro e do primeiro segmento — então
  uma reintrodução pelo `background()` o reprova; isso é detecção por construção, **não** uma corrida vermelha.
- **Tentativas desta rodada, registradas.** `green1`/`green2`: erros de compilação do próprio teste (sombra do nome
  `root`; `FeedWindow` não tem `items`, tem `cards`). `green3`: premissa `unseenOriginIDs` vazia com a âncora movida
  para o topo (o high water já estava adiante — mover a âncora não "desvê"), igualdade do checkpoint inteiro presa
  em `updatedAt`, e `grown[before.count]` num array que **não** cresceu (crash em vez de diagnóstico); a coleta de
  diagnóstico morreu com `No space left on device`. Correções: premissa selecionada **do conjunto medido** de não
  vistas com falha explícita, identidade do checkpoint por campos, `dropFirst(...).first` + `XCTUnwrap` em vez de
  índice, e `-collect-test-diagnostics never`. `green4`: todas as premissas e o ciclo de vida passaram; a produção
  não veio de `refreshFromTheReader()` (foreground estacionário) — corrigido para a oportunidade da cauda admitida.
  `green5`/`green6`: verdes. **Nenhuma linha de produção foi alterada nesta rodada**; as correções foram no teste.
- Disco no fim da rodada: ≈0,78 GiB livres. Nenhum cache, log, `xcresult`, banco, trace, backup ou simulador foi
  apagado; apenas os `xcresult`/logs desta própria rodada foram criados.
- As tabelas `retired_published_cards`/`retired_feed_segments` e as colunas `edition_reading_state.visible`/
  `generation` continuam no schema (migração é histórico imutável). Precisão medida, que corrige a versão anterior
  deste documento: **`visible` não tem mais escritor** (`setVisibility` foi removido), mas `generation` **continua
  sendo escrito** — `PublicationStore+History.swift:34` faz `generation = generation + 1` em `markSeen`, e o
  `INSERT` de `:42` grava `1`. Nenhuma das duas colunas tem **leitor** no código. Bancos existentes com linhas
  arquivadas seguem legíveis por `card(id:)`/`mediaLocator`, como antes.
- **Bancos de builds anteriores não são restaurados.** Uma Edition já mutilada em dispositivo (linha antiga em
  `retired_*`, carta nova no mesmo ordinal) continua mostrando a revisão nova: não há informação para devolver o
  ordinal original. A correção impede mutação futura; não desfaz a passada.
- A sonda red **não** executou `AppComposition.background()`: `Package.swift` não tem target para o app, e a sonda
  chamava diretamente `PublicationStore.hiddenTail(editionID:)` e `HiddenTailMaintenance.run(...)` — a camada de
  pacote que o `background()` chamava. A reachability em produção é leitura de código (`AppComposition.swift:4791`
  e `:4818` na base `9b746e9e`), não medição ponta a ponta. O teste de app desta rodada é o que passou a exercer
  esse owner.
- A prova red usa uma sonda descartável contra a API que deixou de existir; o teste permanente afirma o
  comportamento final (imutabilidade + ocorrência futura). Não é possível manter um teste que chame a API
  removida — a alternativa (manter a API só para poder testá-la) reintroduziria o footgun.
- A árvore ficou com ~0,5 GiB livres após compilar o app; nenhum cache foi apagado e nenhum build concorrente foi
  iniciado.
