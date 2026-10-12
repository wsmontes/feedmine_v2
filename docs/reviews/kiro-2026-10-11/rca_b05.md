# RCA B05 — duas falhas vermelhas em `CompositionTests` (análise estática, só leitura)

Checkout: `C:\workspace\feedmine_v2-int` @ `d86d3f9` (`integration/main-into-app-line`). Sem toolchain Swift;
nenhuma linha do repositório foi alterada. Todas as afirmações vêm de leitura de código citada por arquivo:linha.

## Resposta direta

**São duas causas distintas, não uma causa comum.** O executor errou ao juntá-las.

- **Teste 2 (`testS5OfflineReopenRestoresEditionWithFreshProvenance`, :705):** é a hipótese **H1** confirmada — a
  janela em memória cresce para frente (até 17) mas o restore rematerializa com `backward 8 / forward 16` em torno
  da âncora, que é a **cauda** da janela crescida; sobra `8 + âncora + 0 = 9`. **Mesma edição, janela menor.**
- **Teste 1 (`testK06AnsweringInABetweenAAndBKeepsTheWindowAndTheSaves`, :646):** **não** é H1 e **não** é a
  resposta mudando identidade. É um **defeito de construção do teste**: ele responde e salva num contexto
  (`.main`, o que `launch()` abre) e "volta" para **outro** contexto (`.source(dev[0])`). São `ContextKey`
  diferentes, logo edições diferentes por construção — a asserção de `editionID` igual é impossível de passar,
  independentemente do produto.

As duas só se parecem na superfície (ambas comparam `restored.window`/`editionID` com um snapshot). O mecanismo é
diferente: a 2 é a capacidade de rematerialização; a 1 é a identidade do contexto comparado.

---

## Teste 2 — `testS5OfflineReopenRestoresEditionWithFreshProvenance` (:705)

### O que o teste compara e quando tira o snapshot
`CompositionTests.swift:705-731`:
1. `launch()` → `old`; `produceAndAdmit(old)` (:85-92) **dirige e admite** uma janela larga;
2. `snapshot = old.store.state.presentation` (:712) — tirado **depois** da janela já crescida;
3. `old.background()` + `old.close()`; transporte passa a rejeitar; novo `AppComposition` reabre offline;
4. asserções (:727-730): `editionID` igual, `provenance.sequenceID` diferente, **`restored.window == snapshot.window`**.

### Cadeia causal (H1, confirmada por leitura + a medição já registrada 17→9)
1. `produceAndAdmit` (`CompositionTests.swift:88-91`) usa **`window.items.last` como âncora** e chama
   `viewport(..., activity: .explicitTailApproach)`. Esse é o único activity que
   `RunwayActivity.admitsForwardContent` aceita (`FeedRunwayDriver.submitViewport`, `FeedRunwayDriver.swift`
   bloco `if activity.admitsForwardContent { … .forwardScroll }`), então entra em
   `FeedSession.admitForwardScroll` (`FeedSession.swift`), que faz `items + extensionCards` e **nunca poda a
   cabeça**. A janela do snapshot fica com 1 âncora + até 16 à frente ⇒ **17 cards**, com a âncora atrás da cauda.
2. No reabrir offline, `FeedAssociation.launch()` (`AppComposition.swift:2111`) chama
   `session.admitPresentation(.initial(bounds))` → `installFromCheckpoint(bounds)` (`FeedSession.swift`), e
   `bounds` vem de `presentationBounds` com **`backwardWindowCards = 8` / `forwardWindowCards = 16`**
   (`AppComposition.swift:1659-1667`).
3. `installFromCheckpoint` chama `publicationHistory.restore(backwardCapacity: 8, forwardCapacity: 16, …)`
   (`FeedSession.swift`, método `installFromCheckpoint`), que materializa a janela **em torno da âncora do
   checkpoint** (`PublicationHistory.restore` → `window(editionID:around:backwardCapacity:forwardCapacity:)`,
   `PublicationHistory.swift`). O checkpoint guarda só `cardID + placement` (`SessionStore.CheckpointRecord`,
   `SessionStore.swift:22-30`; `checkpointCurrentPosition` grava só a âncora, `FeedSession.swift` fim do arquivo).
4. A âncora salva é a **cauda** (passo 1). Em torno dela: `backward 8 + âncora + forward 0 = 9` cards. A consulta
   `PublicationStore.cards(...)` corta por capacidade, não por segmento (`PublicationStore.swift:540-544`), então
   o conteúdo existe — o que muda é a **capacidade pedida vs. a janela que havia sido admitida**.
5. `restored.window` (9) ≠ `snapshot.window` (17): a asserção `:729` falha. `editionID` continua igual porque
   `installFromCheckpoint` reusa a edição do checkpoint; `provenance.sequenceID` muda porque é um
   `FeedSession` novo (`projectionSequenceID = UUID()`, `FeedSession.swift:16`). Isso casa exatamente com os
   dois sucessos (`editionID` igual, `sequenceID` diferente) e o único vermelho (`window`).

Medição já registrada que fecha H1: `docs/reviews/2026-10-11-s5-handoff-minimal-case.md` (17 cards antes de fechar,
9 ao restaurar, âncora idêntica, edição idêntica) e `docs/superpowers/handoffs/PARALLEL_SESSION_HANDOFF.md:94`
("restores 9, anchor identical, window query returns 21").

### O que descarta as alternativas
- **Não é a consulta de janela (corte por segmento):** `PublicationStore.cards` ordena/filtra por
  `(s.ordinal, c.ordinal)` sobre a edição inteira (`PublicationStore.swift:540-544`); o minimal-case mediu 21
  cards devolvidos no mesmo estado. Descartado por medição + leitura.
- **Não é o crescimento automático desta frente (H1b):** `FeedAssociation.launch()` só chama
  `startGrowthFollowUp()` quando `restored == nil` (`AppComposition.swift:2150-2152`,
  comentário "R5: growth belongs to a *fresh* presentation. A reopen shows exactly what the reader left (S5)").
  No reabrir, `restored != nil`, logo não cresce. A falha persiste com ele desligado — já medido.
- **Não é reescrita da cauda no background (H2 / `HiddenTailMaintenance`):** o fixture do S5 não tem mídia e as
  revisões não mudam, então `tidy`/`maintainTail` (`AppComposition.swift` `background()`) não substitui cards. H2
  é a questão separada **T-3/K-14** do triage, não a causa do S5. Descartada para este teste.

### Correção mínima proposta (owner certo, sem cache/fila/estado paralelo)
O defeito é de **capacidade de rematerialização no retorno**, não de dado perdido. Duas formas, ambas no caminho
de restauração e preservando a proveniência nova que o próprio S5 exige (`sequenceID` diferente):

- **Opção A (produto, preferida se o PO quer "mesma janela"):** no restore, materializar em torno da âncora com
  capacidade suficiente para **reconter a janela que foi admitida**, não um teto fixo de 8/16. Como o checkpoint
  não guarda o tamanho da janela, a correção honesta é materializar `backward` igual à distância da âncora ao
  topo da janela admitida — e isso exige persistir essa distância (ou a âncora **do topo**) no checkpoint. Owner:
  `SessionStore.CheckpointRecord` + `PublicationHistory.restore` (ambos em Persistence/Publication, módulos
  livres). **Custo:** mudança de esquema + migração; é a única forma de "mesma janela" sem reconstruir.
- **Opção B (barato, alinhado ao veredito do PO):** **afrouxar o teste** para o critério que o PO já aceitou —
  continuidade da âncora + alcançabilidade por scroll — em vez de igualdade estrutural da janela. Ver a seção de
  design abaixo: o PO decidiu em `docs/reviews/2026-10-11-round5-acceptance.md:134` que "uma janela menor
  rematerializada é aceitável" desde que todo card publicado siga alcançável (`testReopenKeepsPublishedCardsReachable`,
  que **passa**). Nesse enquadramento, `XCTAssertEqual(restored.window, snapshot.window)` (:729) está exigindo
  mais do que o produto promete; trocar por asserção de âncora igual + prefixo/sufixo alcançável.

Recomendação: **B** é a correção mínima correta **somente se** um teste de alcance **para trás**, a partir da âncora restaurada, provar que todo card do snapshot continua alcançável. Ver `coordination/KIRO.md`, Kiro 01:45: pela leitura não existe admissão para trás (`FeedPresentationAdmission`), e `testReopenKeepsPublishedCardsReachable` só rola para frente, então esse teste provavelmente **falha**. Nesse caso vale **A** (persistir o topo da janela no checkpoint) ou uma admissão para trás, como decisão de arquitetura.

### Diagnóstico de 1–3 prints que confirma no Mac
Antes da asserção `:729`:
```swift
print("S5 snapshot", snapshot.window.items.count,
    snapshot.window.items.firstIndex { $0.id == snapshot.window.anchor.cardID } ?? -1)
print("S5 restored", restored.window.items.count,
    restored.window.items.firstIndex { $0.id == restored.window.anchor.cardID } ?? -1)
print("S5 tail-equal",
    Array(snapshot.window.items.drop { $0.id != snapshot.window.anchor.cardID }.map(\.id))
    == Array(restored.window.items.drop { $0.id != restored.window.anchor.cardID }.map(\.id)))
```
Leitura: `snapshot≈17` com âncora em índice alto, `restored≈9` com âncora em índice 8, âncora idêntica e `tail`
igual ⇒ H1 confirmada (capacidade), não H2 (conteúdo trocado).

### Confiança
**Alta** para a cadeia causal (leitura direta + duas medições independentes já registradas no repositório). A
escolha de correção A vs. B é decisão de produto, não de diagnóstico.

---

## Teste 1 — `testK06AnsweringInABetweenAAndBKeepsTheWindowAndTheSaves` (:646)

### O que o teste faz (leitura integral, :646-677)
1. `root()` com `feeds: TrustedFeed.development` — **duas** fontes (`TrustedFeeds.swift:31-38`: bbc-world,
   bbc-science).
2. `root.launch()` → `a = root.association`. **Qual é o contexto de `a`?** `AppComposition.init`
   (`AppComposition.swift:216`) usa `currentContextKey = saved.activeContextKey`, e
   `ReaderPreferencesStore.initialize` com várias fontes grava `activeContextKey: ContextKey(request: .main)`
   (`ReaderPreferencesStore.swift:37`). **Logo `a` é o contexto `.main`.**
3. `aSnapshot = a.store.state.presentation`; `aCard = aSnapshot.window.items.first`.
4. salva (`toggleBookmark`), posiciona (`viewport(aCard, .forward)`), **responde** `voteOnTopic(.more)` (:659).
5. vai a **B** = `selectContext(.source(dev[1]))` (:664); volta "a A" = `selectContext(.source(dev[0]))` (:667).
6. exige `restored.editionID == aSnapshot.editionID` (:672) e `restored.window == aSnapshot.window` (:674).

### Cadeia causal mais provável — defeito de construção do teste
O "A" em que o leitor respondeu/salvou é **`.main`** (passo 2). O "voltar a A" é **`.source(dev[0])`** (passo 5).
São `ContextKey` distintos:
- `ContextKey.canonicalIdentity` inclui o `surfaceIdentity` (`"main"` vs `"source:<uuid>"`), `FeedContext.swift:106-120`.
- A identidade da edição (`EditorialRevision.id`) é derivada do `contextKey` em JSON (`AppComposition.swift:1831-1838`),
  e o `FeedEditionID` do cold bootstrap é **sorteado por construção** (`FeedEditionID()` em
  `AppComposition.swift:2124`), só estável se o restore reusar a edição salva.
- `.source(dev[0])` **nunca teve checkpoint** (ninguém o visitou antes), então `history.restore(contextKey:)`
  devolve `nil` (`PublicationHistory.restore` → `sessionStore.checkpoint(for:)` sem linha), `admitPresentation(.initial)`
  devolve `nil` e o `launch()` faz **cold bootstrap de uma edição nova** com `FeedEditionID` novo.

⇒ `restored.editionID` (de `.source(dev[0])`) **nunca** poderá ser igual a `aSnapshot.editionID` (de `.main`). A
asserção `:672` falha por construção; a `:674` falha pela mesma razão (edição diferente ⇒ janela de outra edição).

### Por que descarto cada hipótese do pedido
- **(a) a resposta muda uma versão checada por `mayShow` ou a identidade do `ContextKey`:** **descartada.**
  `voteOnTopic` escreve **só** `settings.discoveryProfile.topicPreferences` (`AppComposition.swift`, corpo de
  `voteOnTopic`). O `discoveryProfile` **não** entra em `applied(key)`: `applied(_:filter)` só dobra
  `readerExclusions()` no filtro (`AppComposition.swift:637-640`), e `readerExclusions()` lê
  `ReaderContentFilterPolicy.exclusions`, que depende de `contentFilterRules / contentFilterTemplates /
  contentFiltersEnabled` — **nunca** de `discoveryProfile` (`ReaderContentFilterPolicy.swift`, `exclusions`). Logo
  a resposta não muda `canonicalIdentity`. E `mayShow` compara só versões de política e o `contextKey`
  (`AppComposition.swift:1673-1680`); o voto não mexe em `selectionVersion` nem no `scoring` (que para
  preset `.everything` é fixo `(.equal, 1)`, `scoring(for:)` em `AppComposition.swift:1023-1033`). Para o
  contexto correto, `mayShow` passaria e o checkpoint **não** seria limpo.
- **(b) o checkpoint é salvo sob uma identidade e lido sob outra:** **descartada como mecanismo de produto.**
  A edição grava `context_identity = contextKey.canonicalIdentity` (`PublicationStore.swift:886`), e
  `SessionStore` lê/escreve `context_checkpoints` por `key.canonicalIdentity` (`SessionStore.swift:100-101,
  124-125, 132-133, 160-166`). As duas pontas usam a **mesma** função. A "mudança de identidade" aqui não vem do
  produto — vem do teste comparar `.main` com `.source(dev[0])`.
- **(c) a sessão reconstruída descarta o checkpoint quando o pool de descoberta muda:** **descartada.** O pool de
  descoberta (`discoveryFeeds/discoveryProfile`, `AppComposition.swift:1105-1152`) alimenta a seleção, não a
  identidade do contexto nem do checkpoint; e `activateContext`/`restore` são keyed por `canonicalIdentity`, que
  não contém o profile. Mudar o profile não limpa `context_checkpoints`.
- **(d) outra — esta é a causa:** o teste navega para um `ContextKey` diferente daquele onde agiu.

### O produto está correto neste ponto?
Pelo caminho que o teste *pretendia* exercer (A→B→A no **mesmo** contexto), o produto **restaura** por desenho:
`association(contextKey:)` → `init` → `activateContext(key)` + `history.restore(contextKey: key)`
(`AppComposition.swift:1726-1739`), e o `selectContext` grava o checkpoint do contexto que sai antes de trocar
(`checkpointCurrentPosition`, `AppComposition.swift:436/464`). Não há evidência estática de que um A→B→A no
mesmo contexto reconstrua a edição. (Isto **não** foi executado; é leitura.)

### Correção mínima proposta (owner certo)
É **teste**, não produto. Owner: `FeedMineAppTests/CompositionTests.swift`. Fazer o "ir a B / voltar a A"
usar o **mesmo** `ContextKey` do `a`:
- Ou abrir A explicitamente como `.source(dev[0])` **antes** do snapshot
  (`try await root.selectContext(.source(dev[0]))` logo após `launch()`), e então B = `.source(dev[1])`, volta =
  `.source(dev[0])`;
- Ou manter A = `.main` e voltar com `selectContext(request:)` para `.main` (há sobrecarga; o guard de
  `selectContext` em `.main` já é no-op quando nada muda, `AppComposition.swift:459-460`, então use um B real e
  volte a `.main`).

Sem novo cache/fila/estado paralelo; preserva a proveniência nova (o restore sempre projeta `sequenceID` próprio,
`FeedSession.projectWindow`). A invariante que o teste quer provar (voltar reaproveita edição+janela; salvos e
nível sobrevivem) é legítima e deve continuar — ela só precisa comparar o mesmo contexto.

### Diagnóstico de 1–3 prints que confirma no Mac
Antes das asserções `:672-674`:
```swift
print("K06 a.contextKey", a.contextKey.canonicalIdentity)
print("K06 back.contextKey", back.contextKey.canonicalIdentity)
print("K06 editions", aSnapshot.editionID, restored.editionID)
```
Se `a.contextKey` = `…|main|…` e `back.contextKey` = `…|source:…|…` (diferentes), e as edições diferem ⇒
construção do teste confirmada. (Se, ao corrigir o teste para o mesmo contexto, ainda falhar, aí sim é produto —
mas o pedido pede separar a causa, e a causa atual é o contexto comparado.)

### Confiança
**Alta** para "contextos diferentes" (identidade do contexto e default `.main` lidos diretamente em
`ReaderPreferencesStore.swift:37` e `FeedContext.swift`). **Média-alta** para "o produto restaura corretamente no
mesmo contexto" — isto é leitura, não execução; o print acima no caminho corrigido fecharia.

---

## Design: ao voltar ao convite, deve-se criar edição nova? (a tensão citada)

**Não deve criar edição nova. Voltar a um contexto já visitado deve retomar a edição e a âncora daquele contexto.**
Não há tensão real entre as duas regras — elas governam coisas diferentes.

- **"Preferência consumida na próxima sessão do contexto"** (round 10, adendo do arquiteto,
  `docs/reviews/2026-10-11-round10-alternative-a-plan.md` §10): governa **o voto/descoberta**. A resposta é
  preferência sobre descoberta futura; por isso `voteOnTopic` **não reconstrói a sessão** e a preferência só
  alcança a seleção "na próxima sessão construída para aquele contexto". Explicitamente **não** mexe em edição,
  janela ou ordem.
- **B05 return-preserves-anchor** (`docs/reviews/2026-10-11-round10-alternative-a-plan.md` R8 e §4;
  `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md:90-96`, "Obrigatório: A reaproveita edição, posição e trabalho
  local ainda válido, sem reconstrução inútil; B não contamina A"): governa **o retorno ao mesmo `ContextKey`** —
  retoma, não renova, não reconstrói.

Como o voto escreve `discoveryProfile`, que **não** faz parte do `ContextKey` nem da identidade da edição (provado
acima em §(a)/(b)), responder em A e voltar a A **não** pode, por desenho, trocar a edição de A. As duas regras
coexistem: a preferência fica guardada e entra na **próxima** vez que uma sessão daquele contexto for **construída
do zero** (p.ex. após `replaceSession` por filtro, ou numa reabertura em que o checkpoint não aplique); um simples
**retorno** não é "construir do zero" — é retomar.

Decide a questão, com citação:
- `round10-alternative-a-plan.md` R8: *"Nova sessão não reinicia por foreground, por reconstrução interna, nem por
  voltar a um contexto já visitado; sessões são guardadas por `ContextKey`; voltar a uma retoma o que o leitor
  deixou."*
- §4 (correção vinculante do arquiteto): *"voltar a um contexto já lido devolve exatamente o que o leitor deixou
  lá."*
- Benchmark B05 (`DISCOVERY_ACCEPTANCE_BENCHMARK.md:94`): *"A reaproveita edição, posição e trabalho local ainda
  válido, sem reconstrução inútil."*

Nota sobre a janela (relevante ao teste 2): o PO já decidiu em
`docs/reviews/2026-10-11-round5-acceptance.md:134` que **uma janela menor rematerializada ao reabrir é aceitável**
desde que todo card publicado continue alcançável por scroll (`testReopenKeepsPublishedCardsReachable`, que passa).
Ou seja: a **âncora e a edição** têm de sobreviver (B05); o **tamanho exato da janela** não é uma promessa de
produto. Isso é o que justifica a Opção B como correção mínima do teste 2.

---

## Resumo das correções e owners

| Teste | Causa | Severidade | Owner da correção | Correção mínima |
|---|---|---|---|---|
| S5 (:705) | capacidade de rematerialização (8/16) < janela admitida (17); H1 | real, mas de *tamanho de janela*, não de perda de edição/âncora | teste (`CompositionTests`) **ou** Persistence/Publication | B: afrouxar `:729` para âncora+alcançabilidade (veredito PO round5); A só se o PO exigir janela idêntica (esquema+migração) |
| K06 (:646) | teste compara `.main` (onde agiu) com `.source(dev[0])` (volta) | defeito de teste | teste (`CompositionTests`) | tornar B/volta o mesmo `ContextKey` de `a` |

Nenhuma correção precisa tocar `AppComposition` (owner quente, K-10). Nenhuma introduz cache/fila/estado paralelo.
Ambas preservam a proveniência nova que o S5 exige (`sequenceID` sempre próprio em `FeedSession.projectWindow`).
