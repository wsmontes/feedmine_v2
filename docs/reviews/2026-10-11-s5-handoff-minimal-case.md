# Caso mínimo — S5 (restauração) — para o dono do caminho de restauração

Escrito a pedido do Codex (rodada 7, item 2) pela sessão que conduz a frente de UX. **Não é uma claim**: é um
caso a encaminhar, com o que já foi medido. O defeito continua **aberto no aceite integrado** até o
responsável responder; esta sessão não alterou nenhuma linha do caminho de restauração.

## Sintoma

`FeedMineApp/FeedMineAppTests/CompositionTests.swift::testS5OfflineReopenRestoresEditionWithFreshProvenance`
afirma `restored.window == snapshot.window` ("a reabertura mostra exatamente o que o leitor deixou") e falha:

```
XCTAssertEqual failed: (restored.window) is not equal to (snapshot.window)
```

Medições desta sessão, em duas corridas independentes:

|Fato|Valor|
|---|---|
|Cards na janela do leitor (antes de fechar)|**17** (= 1 âncora + 16 de avanço)|
|Cards na janela restaurada|**9** (com o crescimento automático desligado nesse caminho) / **11** (com ele ligado, antes da correção da rodada 6)|
|Âncora|**idêntica** nas duas janelas (mesmo `PublicationCardID`)|
|Edição e contexto|idênticos|

## O que já está excluído

1. **Não é a consulta de janela.** `PublicationStore.cards(editionID:around:backwardCapacity:forwardCapacity:)`
   filtra e ordena por `(s.ordinal, c.ordinal)` sobre a edição inteira
   (`Sources/FeedMinePersistence/PublicationStore.swift:540-544`) — não há corte por segmento.
   Provado no store real da corrida: com a âncora em `(segmento 0, card 0)` numa edição `1 + 1 + 20`, a mesma
   consulta devolve **21 cards** seguintes.
2. **Não é o crescimento automático desta frente.** `FeedPresentationAdmission.publishedGrowth` é inerte no
   caminho de restauração (`FeedMineApp/FeedMineApp/AppComposition.swift`, `launch()`: o crescimento só é
   iniciado quando `restored == nil`), e a falha persiste com ele desligado ali.
3. **Não é a árvore de UI.** O caso é de composição/runtime; não envolve gesto, layout nem a superfície.

## Onde a diferença nasce (hipótese, não medida)

17 = 1 + 16 e 9 = 1 + 8 sugerem que a **restauração pede a janela com uma capacidade diferente** da que
produziu a janela original (ou a pede a partir de outro cursor). A consulta responde 21 no mesmo estado, então
o insumo está lá; o que difere é a **chamada** — `PublicationHistory.restore(backwardCapacity:forwardCapacity:)`
→ `window(editionID:around:backwardCapacity:forwardCapacity:)` — não a materialização.

## Como reproduzir

```
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'platform=iOS Simulator,id=<booted>' -parallel-testing-enabled NO \
  -only-testing:FeedMineAppTests/CompositionTests/testS5OfflineReopenRestoresEditionWithFreshProvenance
```

## Estado do encaminhamento

- Caso registrado também no protocolo do repositório: `docs/superpowers/handoffs/PARALLEL_SESSION_HANDOFF.md`,
  seção *Claims* (bloco "R7 — cross-session handoff").
- **Sem canal direto** com a sessão responsável: não existe IPC entre sessões nesta máquina; o registro no
  handoff é o meio de contato que o próprio repositório define. Portanto **não há status de correção a
  relatar** — ele fica "encaminhado, sem resposta" até alguém que possua aquele caminho se manifestar.
- O que o aceite integrado precisa: ou o S5 fica verde, ou o critério muda explicitamente (o PO já disse que
  uma janela menor ao reabrir é aceitável **desde que** o conteúdo publicado continue alcançável — o que esta
  sessão verificou: `testReopenKeepsPublishedCardsReachable` e `testRealCatalogueCardsStayReachableByScrolling`
  passam).
