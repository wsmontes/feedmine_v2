# K-13 — triagem estática (2026-10-11, main@c084dad)

Feita só por leitura de código, sem execução Swift. Cada item diz o que está confirmado e o que ainda é hipótese.

## T-1 `testASavedBoxExportsItsSavedArticlesAndNotTheirSources` → **decisão de produto, não bug de código**

A asserção que falha é `XCTAssertFalse(csv.contains("title,url,identity,category"))`. O que a provoca:

- `Sources/FeedMineRuntime/ReaderExport.swift` (`case bookmarkBox`): o próprio contrato diz *"One saved box: the sources the cards in it came from."*
- `Sources/FeedMineComposition/ReaderImportExportCoordinator.swift`, `entries(for: .bookmarkBox)`: transforma cada card salvo em `ReaderImportEntry` da **fonte** (`FeedAddress.identity("https://" + host)`). `csv(entries:)` sempre escreve o cabeçalho `title,url,identity,category`.

O teste é local, do OMP, e não existe no remoto. Ele exige o oposto: uma caixa exporta os **artigos salvos**. Código e teste seguem especificações diferentes. Antes de mexer, o PO precisa decidir:

- (a) **Caixa exporta artigos**: novo formato de entrada com título do card, link (`primaryActionReference`), fonte e data em que foi salvo. Isso muda os 8 formatos para o escopo `.bookmarkBox` e o contrato em `ReaderExport.swift`.
- (b) **Caixa exporta fontes**, como está: o teste local está errado.

Só a V1 e o PRD F16/F18 podem desempatar; eu não decido. Com a decisão tomada, a correção cabe em `ReaderImportExportCoordinator` e `ReaderExport`, sem tocar no AppComposition.

## T-2 `testS5OfflineReopenRestoresEditionWithFreshProvenance` → **hipótese principal, não confirmada**

Falha em `XCTAssertEqual(restored.window, snapshot.window)`.

**H1, mais provável: a janela em memória cresce para trás e o restore corta em 8.**
- `FeedSession.admitForwardScroll` faz `items + extensionCards` e nunca poda a cabeça (achado R2).
- O restore (`installFromCheckpoint` → `publicationHistory.restore(backwardCapacity: 8, forwardCapacity: 16)`, `AppComposition.swift:963/1016`) monta só 8 cards antes da âncora.
- Se, quando o teste tira o snapshot, houver mais de 8 itens antes da âncora (`produceAndAdmit` usa `items.last` como âncora; se o `drive()` já tiver admitido a janela inicial de até 17 cards, a âncora fica no índice 16), o restore devolve uma janela menor. Mesmo `editionID`, janela diferente: exatamente o sintoma relatado.
- **Consequência de produto, se H1 se confirmar:** depois de reabrir, o leitor não consegue voltar acima de 8 cards, porque `FeedSession` só estende para frente. Isso pesa em B05 ("voltar à mesma leitura").

**H2: cauda reescrita no background.** Detalhes em T-3. No fixture deste teste não há imagens e as revisões não mudam, então `HiddenTailMaintenance` deve retornar `.ineligible`. Pouco provável aqui.

**Diagnóstico que separa H1 de H2 (uma execução no Mac, sem mudar o código de produto):** antes da asserção, imprimir

```swift
print("S5 snapshot", snapshot.window.items.count, snapshot.window.items.firstIndex { $0.id == snapshot.window.anchor.cardID } ?? -1)
print("S5 restored", restored.window.items.count, restored.window.items.firstIndex { $0.id == restored.window.anchor.cardID } ?? -1)
print("S5 same ids after anchor", Array(snapshot.window.items.drop { $0.id != snapshot.window.anchor.cardID }.map(\.id)) == Array(restored.window.items.drop { $0.id != restored.window.anchor.cardID }.map(\.id)))
```

Leitura do resultado:
- Índice da âncora > 8 no snapshot, = 8 no restaurado, e os ids depois da âncora iguais: H1 confirmada. Decidir então entre teste e produto: comparar só a âncora e o que vem depois, ou dar ao restore a mesma cabeça admitida.
- Ids depois da âncora diferentes: H2.

## T-3 (achado novo) a cauda "oculta" inclui cards já admitidos e desenhados

- `FeedAssociation.background()` (`AppComposition.swift` ~1340) pega `PublicationStore.hiddenTail(editionID:)`. O lease usa `highWaterCardID` = `edition_reading_state.high_water_card_id`, que só avança por `markSeen`, isto é, pela **âncora** do viewport.
- `HiddenTailMaintenance.run` considera substituíveis todos os cards depois desse high-water. Mas os cards admitidos **abaixo da âncora** (até `forwardCapacity` = 16) já estão no `LazyVStack`, e com âncora `.top` os primeiros deles estão **na tela**.
- Quando a mídia de um desses cards termina no `tidy` do background (o caminho R1: publicado text-only porque a mídia ainda estava em voo), `old.mediaKey != new.media.primary?.key` e a cauda é substituída. Ao reabrir, cards que o leitor via mudam de layout. Ao voltar sem relaunch, a sessão em memória segura ids de cards arquivados.
- **Viola** INV-08 (publicado imutável para o leitor), B04 (estabilidade física) e a própria nota do código ("Seen and visible cards are never changed").
- **Correção mínima proposta:** o lease protege até o **último card admitido**, não só até o último visto. `hiddenTail(editionID:protectingThrough:)` em `PublicationStore` (Persistence, livre) usa o maior entre o high-water e o card informado. `background()` passa `store.state.presentation?.window.items.last?.id`. Esse ponto está em AppComposition, um owner quente (K-10), então só como patch no handoff.
- **Teste que provaria:** publicar com mídia pendente, admitir 16 cards abaixo da âncora, completar a mídia no `tidy`, chamar `background()` e verificar que os ids e layouts dos 16 admitidos não mudam.
- Severidade: **P1** (B04/B05). É interação com R1, que vai sumir em grande parte quando R1 for corrigido (K-11), mas a regra do lease vale por si.

## Pedidos/ações

- T-1: aguardo decisão do PO, (a) ou (b).
- T-2: peço ao Mac o diagnóstico acima.
- T-3: proponho **K-14**, `PublicationStore.hiddenTail(protectingThrough:)` com teste de Persistence, mais um patch de 1 linha para AppComposition no handoff do K-10. Não implemento antes de autorização.
