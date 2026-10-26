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

**Precedência registrada** em `PRODUCT_DECISIONS_2026-10-09.md` (nota sob PD-5) e em `PRODUCT_INVARIANTS.md`
(INV-17), sem alterar critério algum: PD-5 vence; PD-1 regra 2 governa apenas **adicionar** ocorrências
(no máximo uma futura por origin, substituindo uma ocorrência ainda **não publicada**) e nunca autoriza
reescrever uma publicada. O spec T5 foi marcado como supersedido.

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

## Negativos e limitações (honestos)

- Passe de limpeza `f5d3e087` corrigiu os comentários que ainda descreviam o mecanismo removido
  (`LocalProductionSlice`, `PendingMediaReconsideration`, `PreparedReserve`, três notas em `AppComposition`, a
  proveniência da janela de 256 em `SourceDiversityContractTests`). Nenhuma linha executável mudou; só o
  `swift build --build-tests` + 37 testes dos arquivos tocados foram rodados depois dele, então o
  **BUILD SUCCEEDED** do app target vale para o código do commit `399a0dd1` e não é uma segunda medição.
- **Não** foi rodado o bench (`bench/**` é proibido nesta tarefa) e **não** há alegação de PASS de B03/B04/B05. A
  correção só pode deixar a história publicada mais estável; não foi medida por gate.
- **Não** foi executado teste de UI nem em dispositivo. A prova é de pacote + compilação do app.
- As tabelas `retired_published_cards`/`retired_feed_segments` e as colunas `edition_reading_state.visible`/
  `generation` continuam no schema (migração é histórico imutável) mas **não têm mais escritor** no código. Bancos
  existentes com linhas arquivadas seguem legíveis por `card(id:)`/`mediaLocator`, como antes.
- A prova red usa uma sonda descartável contra a API que deixou de existir; o teste permanente afirma o
  comportamento final (imutabilidade + ocorrência futura). Não é possível manter um teste que chame a API
  removida — a alternativa (manter a API só para poder testá-la) reintroduziria o footgun.
- A árvore ficou com ~0,5 GiB livres após compilar o app; nenhum cache foi apagado e nenhum build concorrente foi
  iniciado.
