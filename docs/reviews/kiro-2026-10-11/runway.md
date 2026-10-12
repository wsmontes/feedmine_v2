# Revisão E2 — Runway / Abastecimento contínuo e publicação

**Repositório:** feedmine_v2-kiro, branch main, HEAD aefa19f (declarado; não verificado via git nesta máquina Windows sem toolchain).
**Método:** leitura estática apenas. Nenhum arquivo do repositório foi modificado. Sem build, sem `swift test`, sem simulador — não pude *executar* nenhum cenário; todas as reproduções abaixo são derivadas por leitura e marcadas como tal.
**Área:** E2 (B03/F05, PD-5/PD-8/PD-9, INV-04/05/08/09/17). Arquivos lidos integralmente: `FeedRunwayDriver.swift`, `RunwayController.swift`, `RunwayPolicy.swift`, `RunwayAcquisitionCycle.swift`, `FeedSession.swift`, `FeedPresentationAdmission.swift`, `LocalProductionSlice.swift`, `InitialProductionSlice.swift`, `MediaPrefetcher.swift`, `PublicationCoordinator.swift`, `PublicationStore.swift`, `PublicationHistory.swift`, `HiddenTailMaintenance.swift`, `ColdFeedBootstrap.swift`, `FeedPresentationHandoff.swift`, `FeedScreenStore.swift`, `FeedScreen.swift` (captura visual), e a seção runway/`resources`/`FeedAssociation` de `AppComposition.swift`.

Confirmado por leitura e **não** classificado como defeito: INV-02/INV-03 (UI só observa — `FeedScreenStore.submitViewport` apenas chama `onViewport`; nenhum `fetch`/SQL/connector no caminho de UI); o `drive()` 3R7 reentrante (claim antes da primeira suspensão + bit `reconsiderRequested`); a admissão só-forward (`admitsForwardContent == (self == .explicitTailApproach)`); a unicidade transacional de origem em `PublicationStore.appendSegment`.

Ordenado por impacto. 15 achados no máximo; aqui vão 9 com evidência citável (preferi densidade de evidência a volume).

---

## R1 — Candidato com mídia ainda não preparada é publicado como text-only (não sai da fila) — **P0**

**Severidade:** P0 — viola INV-17, PD-5 regra 1-2, PD-9 diretamente no owner de publicação.
**Status:** **já conhecido** como P1 em `DOCUMENTATION_CONSISTENCY_AUDIT_2026-10-10.md` item 3 ("`MediaPrefetcher.presentation(for:)` pode representar como `.textOnly` mídia apenas ainda não preparada, levando à publicação indevida"). Elevo a P0 e documento a mecânica exata e o caminho de dado, que o audit não detalhou.

**Arquivo:linha / trecho:**

`Sources/FeedMineRuntime/MediaPrefetcher.swift` (classe `MediaReadiness`):
```swift
public func presentation(for revision: OriginRevisionID) -> PublicationPresentation {
    guard let value = prepared(revision) else { return .textOnly }   // <-- não-settled ⇒ textOnly
    switch value.fit { ... }
}
```
`prepared(_:)` só retorna não-nil para revisões que já passaram por `record(_:_:)` (settle). Uma revisão **em download / in-flight / nunca tentada** retorna `nil` ⇒ `.textOnly`.

`FeedMineApp/FeedMineApp/AppComposition.swift` (closure `prepare`, usada por `LocalProductionSlice`/`InitialProductionSlice`/`ColdFeedBootstrap`):
```swift
presentation: readiness.presentation(for: candidate.originRevisionID)
```
Essa `PublicationPresentation` vira o draft e é **publicada** por `PublicationCoordinator.append`/`createEdition` dentro do mesmo slice.

**Por que é defeito:** INV-17 e PD-5/PD-9 exigem que uma história cuja mídia esperada ainda está chegando **saia imediatamente da fila de publicação atual** — não ocupe posição, não seja degradada. Aqui o pipeline faz o oposto: a seleção escolhe o candidato, o `prepare` o projeta como text-only (porque a imagem ainda não settled dentro da janela `mediaWait = timeout/4`), e `coordinator.append` o **congela como text-only imutável** (INV-08). PD-5 regra 2 é explícita: text-only é decisão editorial baseada em evidência, "nunca saída automática de um número fixo de tentativas" — e aqui é exatamente saída automática por *deadline fixo de ¼ do timeout*.

**Mecânica do deadline (confirma que é tempo, não evidência):** em `FeedRunwayDriver.driveCausalEffects`, ramo `.runLocalSlice`:
```swift
if let prepareMedia {
    await prepareMedia(try await nextEditorialRevisions(...))   // deadline = now + timeout/4
}
...
let outcome = try localProductionSlice.run(request, prepare: prepare)  // lê readiness AGORA
```
`prepareMedia` (AppComposition) é `media.prefetch(revisions, deadline: now + mediaWait)` com `mediaWait = configuration.timeoutIntervalForRequest / 4`. `MediaPrefetcher.prefetch` retorna no deadline mesmo com downloads inacabados (`firstOf(work, orSeconds:)`), deixando-os `inFlight`. O slice então lê `readiness` imediatamente: tudo que não baixou em `timeout/4` → `.textOnly` publicado.

**Cenário de reprodução (por leitura; não executado):** fonte com imagem hero legítima mas host de imagem lento (> `timeout/4`, p.ex. CDN com 3 s e timeout 8 s ⇒ janela 2 s). O card é publicado text-only permanentemente. Quando a imagem termina de baixar 1 s depois, `readiness` passa a ter o asset, mas o card já está congelado text-only em `published_cards` — INV-08 impede corrigir. PD-5 regra 4: "a published text-only card cannot silently acquire a hero image" — ou seja, a degradação é definitiva e indevida.

**Correção mínima proposta:** separar "não pronto" de "decididamente text-only" **antes da seleção**, no owner existente, sem segundo scheduler. `MediaReadiness` já distingui-los: `isSettled(revision)` é verdadeiro só após decisão (asset usável *ou* `settle(revision, nil)` por falha definitiva). A correção é fazer a seleção/preparação **excluir da fila atual** revisões com dependência de mídia esperada e `!isSettled` (pendente), publicando as prontas; a revisão pendente permanece em supply e volta à seleção quando `isSettled`. Introduzir um método `MediaReadiness.readinessState(revision) -> {ready(fit), designedTextOnly, pending}` e, no `CandidateProvider`/`SelectionEngine` já existentes, tratar `pending` como *não elegível para esta oportunidade* (igual ao que PD-5 chama de "sai da fila"). **Não** fazer filtro pós-seleção ingênuo que quebre PD-4/cursor (o audit alerta exatamente contra isso) — a exclusão tem de ocorrer na formação da janela de candidatos, antes de a ordem ser decidida.

**Teste que provaria:** corpus com (a) card imagem-rápida, (b) card imagem-lenta (> deadline), (c) card legitimamente sem imagem. Publicar a primeira oportunidade e assertar: (a) presente com `.image`, (c) presente `.textOnly`, (b) **ausente** do segmento publicado (não text-only, não reservou ordinal); após a imagem de (b) settled, nova oportunidade publica (b) com `.image` num segmento posterior, respeitando PD-4. Hoje o teste equivalente passaria com (b) publicado text-only — provando a violação.

**O que não pude verificar:** se `SelectionEngine`/`CandidateProvider` (módulo `FeedMineEditorial`, cujos fontes não localizei no checkout — `glob Sources/FeedMineEditorial/**` retornou vazio) oferecem um ponto de injeção de elegibilidade por prontidão de mídia. A correção pressupõe que oferecem; precisa inspeção desse módulo.

---

## R2 — Lista admitida cresce de forma monotônica e ilimitada (sem poda de cabeça) — **P1**

**Severidade:** P1 — ameaça B04 (estabilidade física / idle 10 min) e sessão longa B03 (30 min). Não viola INV-08 (imutabilidade), mas contraria INV-16/PD-8 (adaptação a pressão de memória) na prática.
**Status:** **novo** (não encontrado em CODE_REVIEW_*, OMP_*, DOCUMENTATION_CONSISTENCY_AUDIT, F05/F06; o audit só menciona `reserveCards: 16`, não o crescimento da lista admitida).

**Arquivo:linha / trecho — `Sources/FeedMineRuntime/FeedSession.swift`, `admitForwardScroll`:**
```swift
let items = current.presentation.window.items
...
let extensionCards = published.cards.dropFirst().filter { !admitted.contains($0.id) }
    .prefix(current.bounds.forwardCapacity)
    .map { PresentationCard(publishedCard: $0, decoder: imageDecoder) }
guard !extensionCards.isEmpty else { return current.presentation }
let (bounded, _) = try boundedResidency(items: items + extensionCards, ...)   // <-- items + extensão
guard let window = FeedWindowSnapshot(items: bounded, anchor: observation.anchor) else { ... }
```
A cada `.explicitTailApproach`, a lista nova é `items + extensionCards`. Nada remove itens da **cabeça** (backward). `boundedResidency` só libera *bitmaps decodificados* fora de `bounds` (`releasingDecodedImage()`), preservando o descritor `PresentationCard` de **todos** os itens:
```swift
if item.image != nil { nextReleased.insert(item.id) }
return item.releasingDecodedImage()   // mantém o card, solta só os pixels
```

**Por que é defeito:** em B03 (30 min a 1 card/s + rajadas 3 cards/s) o leitor avança ~1.800–2.500 cards. A projeção presente (`FeedPresentationSnapshot.window.items`) e o `ForEach` do SwiftUI crescem monotônica­mente para milhares de `PresentationCard`. Mesmo com bitmaps liberados, cada descritor retém strings de título/texto e metadados; a árvore de views lazy do SwiftUI acumula identidade para todos. INV-16/PD-8 exigem que "pressão real reduz trabalho especulativo" e que memória/retenção se adaptem — manter a janela admitida inteira residente contradiz isso e é candidato direto a hitch/termo de memória no idle de 10 min do B04. A âncora e o backward útil (`bounds.backwardCapacity = 8`) são tudo o que o leitor pode alcançar sem gesto; a cauda arbitrariamente longa atrás da âncora não serve a leitura imediata.

**Cenário de reprodução (por leitura; não executado):** scroll forward contínuo por 30 min. `window.items.count` cresce 1:1 com cards vistos; nunca diminui ao recuar porque o recuo só re-decodifica dentro de bounds, sem recriar a lista menor.

**Correção mínima proposta:** ao estender em `admitForwardScroll`, podar a **cabeça** da lista admitida mantendo um colchão ≥ `bounds.backwardCapacity` (p.ex. um fator pequeno dele) antes da âncora, análogo ao que `boundedResidency` já calcula (`first = max(0, anchorIndex - bounds.backwardCapacity)`). Os cards podados continuam em história publicada (`PublicationHistory.window`) e são re-materializáveis em recuo via `installFromCheckpoint`/`window(around:)` — portanto a poda não viola INV-08/09 nem perde posição (a âncora e o cursor são duráveis). Isso é poda da *projeção de apresentação*, não da história.

**Teste que provaria:** simular N=3.000 `.explicitTailApproach` sequenciais e assertar `currentPresentation().window.items.count` limitado por `backwardCapacity + forwardCapacity + folga` constante, e que um recuo subsequente ainda materializa os cards atrás (via re-janela), com geometria/ordem idênticas. Hoje o count seria ~3.000.

**O que não pude verificar:** o custo real de memória por `PresentationCard` e se a UI (`FeedScreen`) já limita a renderização independentemente — não medi (sem simulador). O crescimento da estrutura em `FeedSession` é, porém, verificável no código.

---

## R3 — `markConsumptionInactive` zera o histórico de consumo/latência a cada background; runway reaprende do zero e pode exibir fim artificial no retorno — **P1**

**Severidade:** P1 — contribui para "fim artificial"/starvation percebido (F05/B03) e contraria INV-05 (trabalho continua) na transição foreground.
**Status:** **novo** (não citado nos reviews; F05 lista `reserveCards`/`mediaWait`/escopo de cobertura, não a perda de amostras no background).

**Arquivo:linha / trecho — `Sources/FeedMineRuntime/RunwayController.swift`:**
```swift
public func markConsumptionInactive() {
    invalidateAcquisitionDemand()
    latestObservation = nil
    lastMeasuredObservation = nil
    readyAhead = nil
    highWater = nil
    consumptionSamples = []     // <-- taxa de consumo medida descartada
    bootstrapObservation = nil
}
```
Chamado em `AppComposition.FeedAssociation.background()` via `await driver.markConsumptionInactive()`. (Latência `latencySamples` sobrevive — só `consumptionSamples` e observação são zeradas.)

**Por que é defeito:** `RunwayPolicy.evaluate` deriva o *threshold* de cobertura de `rate (cards/s) × latency`. Com `consumptionSamples == []`, `consumption.cardsPerSecond == nil` ⇒ no ramo final a cobertura cai em `.unknown`/`.logicalPressure` conforme `readyAmount`, e a ação depende de `unknownBootstrapAvailable` + intenção forward. Resultado: após cada ida ao background e volta, o controlador **esquece quão rápido o leitor lia** e precisa re-medir via `.measure` antes de voltar a dimensionar o runway. Em um leitor que alternava app/leitura (comum em 30 min), isso repetidamente rebaixa a antecipação para o piso `reserveCards`, podendo produzir a paralisação ≥1 s que B03 proíbe quando a reposição é lenta, porque o controlador descarta justamente a evidência (rate) que justificaria encher mais à frente. INV-16/PD-8: a adaptação deve usar "métricas já medidas" — descartá-las a cada background é o contrário.

**Cenário de reprodução (por leitura; não executado):** leitor a 1 card/s por 2 min (amostras cheias) → background 20 s → foreground. No retorno, `consumption.cardsPerSecond == nil`; o primeiro `reconsider` após `activate`/`drive` não tem rate; o runway dimensiona só pela reserva fixa até novas medições chegarem.

**Correção mínima proposta:** não zerar `consumptionSamples` em `markConsumptionInactive`. A invalidação da *observação corrente* (anchor/readyAhead/highWater) é correta para não medir advance através de um gap de tempo inválido; mas a **janela de taxas de consumo** é um histórico recente adaptativo (bounded por `consumptionSampleLimit = 8`) e deveria persistir pela transição, exatamente como `latencySamples` já persiste. Alternativa conservadora: envelhecer/decair as amostras em vez de descartá-las. Em qualquer caso, garantir que o primeiro `advance` após o retorno **não** compute uma taxa espúria por `elapsed` atravessando o background — isso já está protegido porque `highWater`/`lastMeasuredObservation` são re-estabelecidos (o primeiro measurement pós-retorno vira baseline, não um advance).

**Teste que provaria:** encher `consumptionSamples`, chamar `markConsumptionInactive`, reativar e assertar que a cobertura ainda enxerga a taxa anterior (threshold > reserva) sem precisar de novo advance; e que o primeiro advance pós-retorno não injeta rate inválida. Hoje `snapshot().consumption.cardsPerSecond` seria `nil` logo após `markConsumptionInactive`.

**O que não pude verificar:** se, no fluxo real, o `activateCurrentPresentation` pós-retorno compensa isso rápido o suficiente para não gerar paralisação visível — depende de latência de rede real (sem simulador não medi).

---

## R4 — PD-4 na borda de segmento depende de memberships *atuais* da cauda, não da `SourceID` *congelada* publicada — **P1**

**Severidade:** P1 — risco de adjacência de mesma `SourceID` na junção entre segmentos (PD-4 regra 1 "applies across segment boundaries").
**Status:** **novo quanto à borda de segmento.** `R1_EDITORIAL_DIAGNOSIS.md` cobre PD-4 *dentro* de uma seleção e a questão de display-name duplicado; não analisa a atribuição do vizinho de borda via memberships mutáveis.

**Arquivo:linha / trecho — `Sources/FeedMineRuntime/LocalProductionSlice.swift`, `neighbor(editionID:tail:)`:**
```swift
var sources = Set(try contentStore.memberships(originRecordID: card.origin.originRecordID).map(\.sourceID))
if let frozen = card.origin.sourceID { sources.insert(frozen) }
return SelectionNeighbor(sourceIDs: sources, providerID: card.origin.providerID)
```
O vizinho (último card do segmento anterior) é descrito pela **união** das memberships *correntes* da origem **mais** a `sourceID` congelada. Esse `SourceID`-set alimenta a alternância PD-4 do novo segmento (`SelectionEngine.select(..., after: neighbor)`).

**Por que é potencial defeito:** a atribuição *publicada* de um card é a `sourceID` **congelada** nele (`PublishedOrigin.sourceID`, usada para o teste de adjacência no sequenciamento, conforme `prepare` em AppComposition que escolhe uma única `source`). Mas, para a borda, o código inclui também as memberships *atuais* da origem, que podem ter **mudado** desde a publicação (nova revisão do catálogo PD-10 adiciona/remove memberships; INV-18 permite reclassificação). Dois efeitos:
1. Se a `sourceID` congelada do card de cauda **não** estiver mais nas memberships correntes (fonte removida/migrada), o conjunto ainda a inclui (`sources.insert(frozen)`), o que é correto. OK nesse sentido.
2. Porém o conjunto fica **mais largo** que a atribuição real publicada (inclui todas as memberships atuais). Isso *proíbe demais* — pode rejeitar um card cuja `SourceID` publicada seria diferente da do vizinho, por coincidir com uma membership atual que **não** é a atribuição visível do vizinho. Resultado: não é adjacência falsa (seguro para o leitor), mas é **restrição espúria** que reduz runway na borda (PD-4 regra 2 manda segurar o card e pedir aquisição) — contribui para starvation artificial sob supply estreita, que é o alvo do E2.

O risco **inverso** (adjacência real) aparece se a atribuição publicada escolhida em `prepare` (a primeira `source` com nome conhecido, `names[$0] != nil`) divergir do conjunto de borda de modo que o `SelectionEngine` compare contra um set que **não contém** a `SourceID` que o próximo card efetivamente exibirá — mas aqui o novo card também é atribuído por `prepare`, logo a comparação de alternância do *engine* usa o critério do engine, não o de `prepare`. **Não pude confirmar** que o critério de `SourceID` do `SelectionEngine` é idêntico ao da projeção `prepare` (a escolha "primeira source com displayName" em `prepare` pode diferir da que o engine usa para alternar). Se divergirem, há caminho para adjacência visível de mesma fonte na borda.

**Cenário (por leitura; não executado):** origem com 2 memberships S1,S2. Engine alterna por membership-set; `prepare` fixa o display para S1. Segmento anterior termina num card cuja projeção exibe S1 mas cujo set de borda reportado inclui {S1,S2}. Próximo segmento seleciona um card de origem com memberships {S2} — engine o aceita (S2 ∉ … depende da regra), mas sua projeção `prepare` também exibe S2 → ok; porém se a projeção da cauda tivesse exibido S2 e o engine tivesse alternado por S1, veríamos S2,S2.

**Correção mínima proposta:** a borda PD-4 deve usar **exatamente a mesma atribuição que será/foi exibida** — a `SourceID` congelada única do card de cauda (`card.origin.sourceID`), não a união de memberships correntes. Alinhar `neighbor()` para reportar o mesmo critério singular que `prepare`/engine usam para publicar e alternar. Em contexto fonte-única, a exceção PD-4 (regra 4) já se aplica.

**Teste que provaria:** publicar segmento A terminando num card de origem multi-membership (atribuição congelada S1); mudar memberships da origem para incluir S3; forçar novo segmento; assertar que a decisão de alternância usa {S1} (congelado) e que a sequência publicada final tem `maxrun == 1` por `SourceID` *publicada* na borda, inclusive após reclassificação de catálogo. Também assertar paridade entre a `SourceID` escolhida por `prepare` e a usada pelo engine para alternância.

**O que não pude verificar:** o critério exato de alternância do `SelectionEngine` e se ele consome `SourceID` única ou set — fontes de `FeedMineEditorial` não presentes/localizáveis no checkout. **Este achado é condicional a essa inspeção.**

---

## R5 — `reserveCards: 16` fixo governa o piso de antecipação como número mágico — **P2**

**Severidade:** P2 — contraria INV-04/INV-16/PD-8 ("número não pode representar a lógica conceitual").
**Status:** **já conhecido** — `FeedMine_V1_vs_V2_Code_Review_Comparativo_2026-10-09.md` item 2, `F05_RUNWAY_CONTINUITY_DIAGNOSIS_2026-10-10.md` item 2, `DOCUMENTATION_CONSISTENCY_AUDIT_2026-10-10.md` item 3. Incluído por completude de área; não reivindico originalidade.

**Arquivo:linha / trecho — `FeedMineApp/FeedMineApp/AppComposition.swift`, `static var resources`:**
```swift
.init(localWorkAllowed: true, examinedCandidateCapacity: 32,
    readyProbeBound: 32, readyProbeCeiling: 256, forwardAdvanceProbeBound: 256,
    reserveCards: 16)!
```
`RunwayPolicy.evaluate` usa `reserveCards` como piso: quando `readyAmount < reserve`, força `.pressured(requiredCards: reserve)` mesmo com leitor estacionário/sem amostras. O valor é fixado em `16`, igual ao `forwardCapacity` da janela.

**Por que é defeito (de política, não de segurança):** PD-8/INV-16 permitem limites físicos por operação, mas proíbem um número permanente como *estratégia*. Com rede lenta e consumo alto, 16 cards podem não cobrir a janela de reposição; com rede rápida e leitor voraz, 16 pode ser subdimensionado para evitar paralisação. O piso deveria derivar de `rate × p95 × safety` (que o policy já calcula) e só usar `reserveCards` como *limite de segurança*, não como alvo. Nota: elevar o número não corrige — F05 alerta explicitamente contra "assumir que aumentar esse número corrige".

**Correção mínima proposta:** manter `reserveCards` apenas como teto/segurança; derivar o piso efetivo da própria avaliação de cobertura (threshold medido), de modo que, com amostras presentes, o piso seja o `threshold` e, sem amostras, um bootstrap pequeno — sem travar em 16. Sem segundo scheduler; a lógica já vive em `RunwayPolicy`.

**Teste que provaria:** com `rate=3 cards/s`, `p95=10 s`, `safety=1.2`, o threshold = ceil(36) = 36 > 16; assertar que a cobertura exige ~36, não 16. Hoje o piso continua 16 quando `readyAmount` cai abaixo dele independentemente da taxa.

**O que não pude verificar:** impacto real em B03 (sem execução).

---

## R6 — `drive()` reentrante não propaga erros estruturais ao chamador reentrante — **P2**

**Severidade:** P2 — correção/observabilidade; pode mascarar `sessionContextMismatch`/cancelamento num chamador concorrente.
**Status:** **novo**.

**Arquivo:linha / trecho — `Sources/FeedMineComposition/FeedRunwayDriver.swift`, `drive`:**
```swift
public func drive(resources: ...) async throws -> FeedPresentationSnapshot? {
    if causalExecution != nil {
        causalExecution?.resources = resources
        causalExecution?.reconsiderRequested = true
        return await session.currentPresentation()   // <-- retorna sucesso sem rodar nem lançar
    }
    ...
}
```
Um chamador reentrante (p.ex. `foreground()` enquanto um `submitViewport` ainda está no drain) recebe a apresentação atual como se tivesse "funcionado", mas o trabalho é feito pelo owner atual sob o escopo *dele*. Se o owner atual depois falhar com erro estrutural ou for cancelado, o chamador reentrante já retornou sucesso.

**Por que é defeito:** 3R7 documenta que reentrância "pode registrar observações e ler a apresentação corrente imediatamente" — então o retorno antecipado é *por design*. O problema é apenas que um erro do owner não é observável pelo reentrante, o que para E2 significa que um `foreground()` pode reportar `.idle`/apresentação enquanto o pass causal real abortou (contexto mudou), sem reagendar. Em prática, `scheduleLocalRetryIfNeeded` no `foreground`/`viewport` cobre a maioria dos casos; por isso P2.

**Correção mínima proposta:** nenhuma mudança de arquitetura; documentar o contrato (o reentrante não é dono dos efeitos e não observa seu resultado) e garantir que todo caminho reentrante chame `scheduleLocalRetryIfNeeded()` depois (hoje `viewport` e `foreground` o fazem; confirmar que qualquer novo chamador reentrante também o faça).

**Teste que provaria:** disparar `drive` reentrante enquanto o owner falha com `sessionContextMismatch`; assertar que o sistema reagenda uma oportunidade em vez de ficar parado. (Testes 3R7 cobrem o owner, não o observador reentrante.)

**O que não pude verificar:** se há chamador reentrante real além de `viewport`/`foreground` (não exaustivamente rastreado).

---

## R7 — `HiddenTailMaintenance` em background pode reescrever a cauda não-vista usando mídia/texto preparados sob o mesmo deadline de R1 — **P2**

**Severidade:** P2 — interação com R1; sucessão de cauda troca cards por versões "materialmente diferentes" cuja diferença pode ser só mídia que *agora* baixou, enquanto a versão anterior foi congelada text-only por timeout.
**Status:** **novo** (a mecânica de borda com R1 não está nos reviews).

**Arquivo:linha / trecho — `Sources/FeedMineRuntime/HiddenTailMaintenance.swift`:**
```swift
if future.allSatisfy({ old in
    guard let new = latest[old.originRecordID] else { return false }
    return old.originRevisionID == new.origin.originRevisionID && old.mediaKey == new.media.primary?.key.rawValue
}) { return .ineligible }
return try PublicationCoordinator(database:).succeedTail(.init(... originRecurrence: .whenMaterialChanged), lease: lease)
```
A sucessão só é inelegível se **toda** a cauda futura tiver revisão e `mediaKey` iguais. Ou seja, se um card da cauda havia sido congelado **text-only** por R1 (deadline) e agora a mídia settled (`new.media.primary` presente), `old.mediaKey (nil) != new (key)` ⇒ **elegível** ⇒ `succeedTail` reescreve a cauda não-vista com o card agora com imagem.

**Por que é ambíguo/defeito:** isso *parece* desejável (recupera a imagem perdida por R1), e PD-5 permite nova ocorrência numa Edition posterior — mas aqui é `succeedTail` **arquivando e substituindo** o segmento não-visto da *mesma* Edition. O contrato 3R6/`succeedTail` protege visível/visto (checa `visible==0`, `generation`, bookmarks/usage no sufixo). O defeito real é que isso só existe para *compensar* R1: se R1 for corrigido (pendente sai da fila em vez de virar text-only), este caminho deixa de ser necessário para mídia e seu critério de materialidade (incluir `mediaKey`) continua válido só para edição real do publisher. **Recomendo tratar R1 primeiro**; depois reavaliar se a diferença-por-`mediaKey` em `HiddenTailMaintenance` ainda se justifica ou se mascara a correção.

**Correção mínima proposta:** depende de R1. Sem R1 corrigido, não mexer (está protegido quanto a visível/visto). Com R1 corrigido, manter `mediaKey` na materialidade apenas para troca de imagem *declarada pelo publisher* (ordinal-0 canônico mudou), não para "a imagem finalmente baixou".

**Teste que provaria:** cauda não-vista com card text-only por timeout; settle da imagem; rodar background `maintainTail`; hoje reescreve. Após R1, o card nunca teria sido publicado text-only, então o cenário não ocorre.

**O que não pude verificar:** execução real do caminho de background (sem simulador).

---

## R8 — Cobertura de fontes selecionadas (`selectedSourceCoverage`) roda a cada drain mesmo com runway saudável, mas limitada a `eligibleTargets(for: context)` = fontes já selecionadas — **P2**

**Severidade:** P2 — não é bug de runway; é o limite de descoberta (fronteira E1/E2) que impede B03 de provar "acabou todo conteúdo elegível" vs "acabou as fontes selecionadas".
**Status:** **já conhecido** — F05 item 4-5 e audit item 2 descrevem o universo estreito. Incluo porque toca diretamente o "fim artificial" do E2.

**Arquivo:linha / trecho — `Sources/FeedMineComposition/FeedRunwayDriver.swift`:**
```swift
let targets = try acquisition.eligibleTargets(for: plan.context)
let outcome = try await acquisitionCycle.run(intent, eligibleTargets: targets, ..., preferUnattempted: selectedSourceCoverage != nil)
```
e em `AppComposition`: `acquisition` é `SyndicationAcquisitionSnapshot` construído só a partir de `feeds` (o starter set). `eligibleTargets` nunca excede as fontes registradas no snapshot.

**Por que é defeito de produto (E2):** B03 exige distinguir fim de "quatro fontes" de fim de "todo conteúdo elegível" (diretriz E2). Como `eligibleTargets` = fontes selecionadas registradas, quando elas se esgotam o runway **termina** — fim artificial relativo ao catálogo de 77.443. A cobertura progressiva de PD-8/INV-16 não é alcançável no runway porque o universo de alvos é fechado na construção da associação. Isso é causa-raiz plausível do ensaio "4 min/135 cards".

**Correção mínima proposta:** fora do escopo de "correção mínima no owner de runway" — pertence a E1 (planner/elegibilidade de catálogo). O runway em si está correto ao parar quando `eligibleTargets` esgota; a falha é o *conjunto* de targets. Registrar como dependência E1, não patch no `FeedRunwayDriver`.

**Teste que provaria:** B03 em corpus ≥5.000 itens / ≥300 fontes elegíveis; assertar ≥20 fontes contribuintes e ausência de fim antes dos 30 min. Hoje termina ao esgotar o starter set.

**O que não pude verificar:** `TrustedFeeds.swift`/planner de catálogo (E1) — fora da minha área e não lido integralmente.

---

## R9 — `prefetchSupplyHead` e o `prepareMedia` do driver podem preparar mídia de candidatos que a seleção **não** vai publicar (desperdício sob pressão) — **P2**

**Severidade:** P2 — eficiência/PD-6 sob pressão; não corrompe estado.
**Status:** **novo**.

**Arquivo:linha / trecho — `FeedRunwayDriver.nextEditorialRevisions` vs `MediaPrefetcher.prefetchSupplyHead`:**
`nextEditorialRevisions` já filtra origens publicadas/unseen — bom. Mas `MediaPrefetcher.prefetchSupplyHead(limit:)` (usado por `background()` tidy e por `cold prepareMedia`) usa `contentStore.candidateWindow(sourceID: nil, after: nil, examinedCapacity: limit)` — a **cabeça bruta** de supply, sem o filtro editorial de exposição/PD-4. Em uma Edition já com história, parte dessa cabeça já foi publicada e não será de novo, mas sua mídia é baixada (consumindo o `downloadByteBudget` de PD-6).

**Por que é defeito:** PD-6/PD-8 exigem gastar o budget de mídia no que a sessão realmente vai apresentar, priorizando o leitor. Baixar mídia de candidatos já publicados/não-elegíveis desperdiça banda/disco sob pressão. O caminho do *driver* (`prepareRunwayMedia` ← `nextEditorialRevisions`) está correto; o caminho `prefetchSupplyHead` do cold/tidy não aplica o mesmo filtro.

**Correção mínima proposta:** no cold/tidy, alimentar `prefetch(_ ordered:)` com as revisões que a seleção efetivamente escolheria (reutilizar `nextEditorialRevisions`/`CandidateProvider` + exposição), em vez de `prefetchSupplyHead` bruto. Owner existente (`MediaPrefetcher.prefetch` já aceita lista ordenada).

**Teste que provaria:** Edition com metade da cabeça já publicada; chamar o prefetch de background; assertar que só revisões não publicadas e elegíveis entram em `inFlight`. Hoje a cabeça inteira entra.

**O que não pude verificar:** `ContentStore.candidateWindow` semântica exata (módulo persistence/editorial não lido integralmente).

---

## Resumo e priorização

| ID | Sev | Novo/Conhecido | Invariante/PD | Essência |
|----|-----|----------------|---------------|----------|
| R1 | P0 | conhecido (audit §3) — elevado e detalhado | INV-17, PD-5, PD-9 | mídia não-settled publicada como text-only imutável (deadline `timeout/4`), não sai da fila |
| R2 | P1 | **novo** | INV-16, PD-8, B04 | lista admitida cresce ilimitadamente (sem poda de cabeça) |
| R3 | P1 | **novo** | INV-05, INV-16, PD-8 | `markConsumptionInactive` descarta taxa de consumo a cada background |
| R4 | P1 | **novo** (borda) | PD-4 regra 1 | alternância de borda usa memberships atuais, não `SourceID` congelada |
| R5 | P2 | conhecido | INV-04/16, PD-8 | `reserveCards:16` como política, não limite de segurança |
| R6 | P2 | **novo** | 3R7 contrato | erro do owner invisível ao chamador reentrante de `drive` |
| R7 | P2 | **novo** | PD-5/INV-08 (via R1) | sucessão de cauda reescreve por "mídia que baixou" — artefato de R1 |
| R8 | P2 | conhecido | PD-8, INV-16 | universo de alvos fechado no starter set → fim artificial (dependência E1) |
| R9 | P2 | **novo** | PD-6, PD-8 | prefetch de background baixa mídia de candidatos não elegíveis |

**Maior impacto para destravar E2/B03:** R1 (publicação indevida text-only / head-of-line) e R8 (universo fechado) são as causas plausíveis do fim artificial; R2/R3 ameaçam B04 e sessão longa. R1 é o único P0 e está no owner de publicação/preparação — corrigível sem segundo pipeline.

## Limites desta revisão (explícito)

- **Sem execução:** nenhuma reprodução foi *rodada*; todas são derivadas por leitura do código citado. Sem Swift toolchain/simulador nesta máquina Windows.
- **Módulo `FeedMineEditorial` não lido:** `SelectionEngine`, `CandidateProvider`, `candidateWindow` e o critério exato de alternância PD-4 não estavam localizáveis no checkout (`glob Sources/FeedMineEditorial/**` vazio). R1 (ponto de injeção de elegibilidade), R4 (critério de `SourceID`) e R9 (semântica de janela) são **condicionais** a essa inspeção.
- **Starter set / planner de catálogo (E1):** não lido; R8 referenciado a partir de F05/audit, não re-verificado no código de E1.
- **HEAD:** aefa19f é o declarado; não confirmei via git (sem toolchain). Linhas citadas por conteúdo, não por número absoluto, onde o arquivo é longo.
