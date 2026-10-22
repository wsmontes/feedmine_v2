# FeedMine V2 — Plano completo de implementação do trabalho restante

> **For agentic workers:** REQUIRED SUB-SKILL: usar `superpowers:executing-plans` para implementar sequencialmente, tarefa por tarefa. Este documento é um plano, não prova de execução. Passos `- [ ]` são pendentes. Não reimplementar T1 nem a otimização de membership já entregue. Não encerrar a execução após uma subentrega sem registrar precisamente o que falta.

**Goal:** completar o isolamento da leitura, a progressão independente do pipeline, a capacidade adaptativa e as jornadas de contexto, busca e offline; validar uma única candidata com evidência real.

**Architecture:** preservar supply canônico, publicação imutável, FeedSession, RunwayController, FeedRunwayDriver, AcquisitionCoordinator, MediaPrefetcher e os coordenadores atuais. Observações visuais entregam fatos pequenos; os owners existentes preparam apresentação/metadados e reconsideram resultados duráveis. Um único executor causal continua autorizando publicação, enquanto rede e mídia progridem sem barreiras de rodada.

**Tech Stack:** Swift 6, SwiftUI, actors/structured concurrency, GRDB/SQLite, XCTest/XCUITest, Xcode e instrumentos existentes. Sem dependência nova prevista.

**Spec:** `2026-10-17-v2-fluidez-capacidade-entregas.md`; `docs/product/PRODUCT_NORTH_STAR.md`; `docs/architecture/PRODUCT_INVARIANTS.md`; `docs/architecture/CONTINUOUS_FEED_RUNWAY_DESIGN.md`; decisões/PRDs vigentes de busca, biblioteca, mídia, catálogo e plataforma. Este plano detalha o restante do roteiro original, sem substituir suas restrições ou reduzir seus gates.

## 1. Base verificada e limite deste documento

Base de implementação: **`bc6a38dc2e16072fb82dc17071d100534d070a8a`**, branch `codex/v2-fluidez-capacidade`, worktree `/Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2`.

| Parte original | Situação efetivamente comprovada | Tratamento aqui |
|---|---|---|
| T1 — reconciliação | Commit `ba4f0aa7`; base 51 comparada e testes executados | Preservar; corrigir premissas vermelhas em R00 |
| T2 — membership | Commit `bc6a38dc`; Set preparado na janela, compartilhado pelas evidências; igualdade/hash ignoram estado derivado | Preservar; completar ingresso e instalação em R01–R02 |
| T2 restante | Tasks por callback e SQL na instalação continuam | R01–R02 |
| T3–T12 | Não implementados por esta execução; correções anteriores da candidata continuam existindo | R03–R23, com verificação antes de alterar |

Evidência anterior, que deve ser conservada:

- `swift test`: 1.445 testes, zero falhas; 3 ignorados na árvore final por artefatos locais ausentes. Não chamar skips de aprovação.
- 75 regressões de viewport/store/admissão: zero falhas.
- Nova regressão `testForegroundPreservesLearnedConsumptionAndContextChangeStartsFresh`: PASS pelo host iOS, incluindo inactive → background → foreground e troca de contexto.
- Host iOS: 80 testes, **quatro asserções falhas em três casos**. Repetição na candidata sem as alterações reproduziu as mesmas falhas.
- `testATemplateTheReaderTurnsOnHidesWhatItsWordsMatch` passou com `-testLanguage en -testRegion US`; falha no ambiente português por esperar uma regra quando o fixture oferece português mais inglês.
- As outras três asserções pertencem a dois testes de segunda publicação/recibo; suas premissas não chegaram ao comportamento que queriam testar.
- Nenhum G1–G4 nem B01–B06 foi certificado por esta execução.

Registro: `docs/reviews/2026-10-17-v2-plan-execution.md`. Logs comprimidos e hashes: `docs/reviews/evidence/2026-10-17-v2-plan/manifest.json`. Os `.xcresult` registrados ficam fora do Git; verificar disponibilidade antes de reutilizar.

As três revisões com nomes `FEEDMINE_{INTENTIONS_VS_DELIVERIES,SCROLL_ARCHITECTURAL_STUDY,BACKEND_HEADROOM_KERNEL_AUDIT}_2026-10-17.md` não foram encontradas nos checkouts inspecionados. Não tratá-las como lidas. O roteiro original, o código, os PRDs acessíveis e as evidências são a base executável. Uma revisão recuperada posteriormente deve ser reconciliada por diferenças explícitas.

## 2. Global Constraints

- UI instala apresentação local pronta; SQL, parsing, decode, seleção e produção ficam fora do callback visual e do MainActor. Declarar executor/ator em cada caminho: `async` sozinho não comprova isolamento.
- Preservar publicação: identidade, conteúdo, ordem e geometria de ocorrências publicadas não mudam por readiness tardia.
- Preservar admissão + checkpoint transacionais, escritor serial SQLite, single-flight, CAS e fences de contexto/edição/revisão/proveniência existentes.
- Não criar outro runtime, seletor, cache semântico, fila genérica, scheduler, geração de aquisição ou motor de busca. Estado derivado mínimo pertence ao owner atual e declara invalidação.
- Preservar a oportunidade foreground a cada **≥ 10 s**, somente ativo/visível, e o teto de **2000 cartas** como guarda de memória. Nenhum dos dois vira alvo de abastecimento.
- 48 é bootstrap de planejamento; 8 é teto operacional de execução existente. Não trocar números fixos por outros como estratégia de capacidade. Limites operacionais continuam necessários e documentados.
- Separar candidatos locais, publicações duráveis e pixels residentes. Não resolver prontidão mantendo todos os bitmaps do histórico em RAM.
- Não expor imagem sem pixels, reclassificá-la como texto, filtrar card visível indisponível nem mover a âncora para simular sucesso.
- Trabalho válido de A pode continuar útil em A→B→A; autorização de instalar depende do contexto vigente. Cancelamento não substitui fences.
- Não alterar `bench/`, scripts avaliadores, corpus congelado ou limiares para acomodar implementação. Cargas novas ficam em `Tests/`; evidências em `docs/reviews/evidence/`.
- Background é oportunidade limitada pelo iOS; nenhuma promessa depende de BGTask ocorrer em hora exata ou de execução contínua durante suspensão.
- Não alterar banco/container pessoal, TestFlight ou dados de produção durante ensaios. Usar namespaces de teste e os scripts existentes.
- Merge, push compartilhado e release continuam fora da execução automática deste plano.

## 3. Review Focus

1. Reversão, VoiceOver ou salto chegam antes do callback do viewport: destino precisa estar pronto **no instante de exposição**; teste em R03/R04.
2. Conclusão antiga e bookmark confirmado intercalam com A→B→A: bytes válidos sobrevivem, mas apresentação/metadados antigos não sobrescrevem o estado confirmado; R02/R11.
3. HTTP e consumidor suspensos simultaneamente: outros alvos e publicações continuam sem tarefas/fila ilimitadas; R05–R07.
4. Disco cheio, purge e morte entre commits: bookmark/contexto/posição confirmados sobrevivem; R02/R11/R12/R14.
5. Oferta homogênea, metadados ausentes ou offline: não fabricar diversidade/novidade, omitir fatos de disponibilidade nem girar em loop; R09/R17/R18/R22.

## 4. Ordem de implementação e gates

Integração serial:

`R00 → R01 → R02 → R03 → R04 → G1 → R05 → R06 → R07 → R08 → R09 → R10 → G2 → R11 → R12 → R13 → R14 → R15 → R16 → R17 → R18 → R19 → R20 → R21 → G3 → R22 → R23 → G4`.

R08 pode ser desenvolvido após R06; R12–R16 não dependem da conclusão editorial de R17. Isso não autoriza duas alterações concorrentes em `AppComposition.swift` ou nos mesmos owners. Usar uma candidata integrada por gate.

| Gate | Condição de saída |
|---|---|
| G1 | Ingresso limitado; instalação sem I/O; prontidão anterior à exposição; nenhuma perda de âncora em reversão/salto/acessibilidade |
| G2 | Conclusões individuais alimentam publicação; HTTP/mídia pendentes não barram prontos; descoberta e recursos com custo limitado |
| G3 | Contextos, filtros, salvos, busca, diversidade, primeiro uso, navegação e catálogo cumprem suas jornadas |
| G4 | Candidata única com capacidade medida e B01–B06 executados ou impedimentos explicitamente registrados; release só passa quando todos os requisitos obrigatórios passam |

## 5. Convenções de execução e verificação

### Preparação sem repetir a implementação anterior

- Conferir `git rev-parse HEAD`, `git status --short`, `git log` e o registro de execução. Se HEAD avançou, reconciliar o diff antes de aplicar tarefas; não assumir que este plano descreve arquivos já alterados depois da base.
- Procurar e ler `AGENTS.md` aplicáveis. Reutilizar a worktree vinculada a esta execução; não trabalhar na branch documental por engano.
- Obter destino atual com `xcodebuild -showdestinations -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine`. Nome correto do target de unitários: **FeedMineAppTests**.
- Verificar espaço antes de builds; reutilizar DerivedData desta execução. Não apagar caches/worktrees alheios.
- Preparar catálogo de produto e recursos locais ignorados pelo Git conforme `docs/IOS_RUN.md`; copiar bytes verificados sem regenerar/editar o benchmark. Registrar hashes dos arquivos locais utilizados.

### Comandos padrão

Da worktree da candidata, usar destino e diretório de evidências escolhidos na execução:

```sh
swift test --filter NomeDaClasse
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination "$FEEDMINE_TEST_DESTINATION" \
  -derivedDataPath "$FEEDMINE_DERIVED_DATA" \
  -resultBundlePath "$FEEDMINE_RESULT_BUNDLE" \
  -parallel-testing-enabled NO -testLanguage en -testRegion US \
  CODE_SIGNING_ALLOWED=NO -only-testing:FeedMineAppTests/NomeDaClasse test
git diff --check
```

As variáveis acima são argumentos da execução, não defaults do produto. Cada `.xcresult` deve ter caminho novo. Rodar testes de português separadamente com idioma/região declarados e asserções correspondentes. Nunca inferir o locale pelo nome do simulador.

### Receita obrigatória de cada tarefa

Os passos abaixo se aplicam a cada R00–R23; os blocos de cada tarefa fixam os casos e comandos específicos.

1. `- [ ]` Ler interfaces e os testes existentes; registrar SHA inicial e premissas. Aproveitar caso já verde que realmente exercita o contrato.
2. `- [ ]` Escrever os testes discriminantes indicados. Compilar os seams mínimos necessários e obter **FAIL por asserção do defeito**, não por símbolo inexistente, timeout arbitrário ou erro de build. Fixtures/gates ficam no target de testes.
3. `- [ ]` Executar o comando da tarefa; guardar log do vermelho. Se o caso já passar, registrar como comportamento presente, sem recriar o defeito.
4. `- [ ]` Alterar apenas os owners indicados; preservar interfaces explicitamente mantidas. Os nomes novos abaixo são **interfaces propostas**, não alegações de APIs existentes.
5. `- [ ]` Executar novamente o comando; esperado **zero falhas**, nenhum caso omitido. Para testes causais, suspender/liberar por continuação/barreira e verificar antes da liberação; timeout serve somente como watchdog.
6. `- [ ]` Rodar regressões afetadas, `git diff --check` e a jornada quando indicada. Não repetir suíte ampla por hábito; executá-la no fechamento dos gates e após risco integrado concreto.
7. `- [ ]` Commit da tarefa e registro: `SHA inicial | vermelho/presente | alteração | verde | jornada | pendências | SHA final`.

Não marcar tarefa completa apenas porque existe commit. Se um teste falha antes do cenário-alvo, corrigir a premissa; não registrar o fence ou a jornada como aprovado.

## 6. Mapa de arquivos e responsabilidades

| Owner/arquivos | Responsabilidade no restante |
|---|---|
| `Sources/FeedMineUI/{FeedScreenStore,FeedNativeViewport,FeedInteractionPresentation}.swift` | Captura pequena, intenção e transição visual pronta; sem produção |
| `Sources/FeedMineRuntime/{FeedPresentationSnapshot,FeedSession,PresentationCard}.swift` | Projeção, evidência, posição, admissão e residência segura |
| `Sources/FeedMineComposition/FeedPresentationHandoff.swift`, `FeedMineApp/FeedMineApp/AppComposition.swift` | Pacote pronto de instalação, ciclo de vida e destinatário da fence |
| `Sources/FeedMineAcquisition/{AcquisitionCoordinator,AcquisitionPlanner}.swift` | Single-flight, rede limitada, resultados duráveis e autorização de trabalho |
| `Sources/FeedMineComposition/{RunwayAcquisitionCycle,FeedRunwayDriver,ColdFeedBootstrap}.swift` | Progresso causal único entre estágios |
| `Sources/FeedMineRuntime/{MediaPrefetcher,LocalProductionSlice}.swift` | Preparo por prioridade e seleção de oferta pronta |
| `Sources/FeedMineComposition/{ReaderDiscoveryTraversal,CollectionLaunchSettings}.swift` | Travessia, índices derivados e bootstrap/teto operacional |
| `Sources/FeedMineComposition/{ReaderLibraryCoordinator,SavedMediaCoordinator}.swift`, stores atuais | Biblioteca e promessa offline com a autoridade existente |
| `Sources/FeedMineDomain/FeedContext.swift`, `Sources/FeedMineEditorial/CandidateProvider.swift` | Expressão e identidade de busca, consulta local consistente |
| `Sources/FeedMineEditorial/{SelectionEngine,SourceAlternation}.swift` | Diversidade determinística da seleção futura |
| `Sources/FeedMineComposition/{CatalogUpdater,CatalogInstallation,ReaderActionCoordinator}.swift` | Ativação de catálogo e ações honestas de leitura |
| `Tests/`, `FeedMineApp/FeedMineAppTests/`, `docs/reviews/evidence/` | Regressões, jornadas e prova; nenhuma produção paralela de teste |

## 7. Tarefas restantes

### R00 — Tornar discriminantes as provas ainda vermelhas (resíduo de T1)

**Files:** modificar `FeedMineApp/FeedMineAppTests/{CompositionTests,ContentFilterTests}.swift` somente onde a investigação comprovar fixture/premissa incorreta; owners de aquisição/publicação apenas se surgir defeito real. Atualizar o registro de execução.

**Interfaces:** preservar `driver.activateCurrentPresentation(resources:)`, `PublicationRelay`, `publicationConcluded` e a política de cooldown. Os testes devem obter um `PublicationReceipt` real antes de avaliar instalação/fence.

- [ ] Reproduzir os dois testes de segunda publicação isoladamente na base atual; rastrear payload recebido, fingerprint, geração, cooldown, supply admitido e segmentos. Separar conteúdo que não chegou de conteúdo que não publicou.
- [ ] No teste de crescimento, afirmar que a segunda resposta difere da primeira, que os candidatos novos foram admitidos e que o segmento/recibo existe antes da asserção visual. Se um desses fatos falhar, corrigir sua causa nesse owner; não contornar cooldown com sleeps ou retries ilimitados.
- [ ] No teste de recibo superado, produzir e reter um recibo legítimo de A, instalar B e só então entregar o recibo de A; exigir que edição, cards e âncora de B permaneçam iguais. Uma mutação removendo a fence precisa tornar a asserção vermelha.
- [ ] Executar o teste do template em inglês e português explicitamente. A expectativa é uma regra no fixture inglês e duas no fixture bilíngue português; não remover palavras válidas para tornar o teste verde.

**Verificação:** Xcode `CompositionTests/testAPublicationConcludedAfterTheFollowUpWindowGrowsTheAdmittedWindow`, `CompositionTests/testAReceiptForASupersededEditionDoesNotGrowTheCurrentEditionsWindow` e `ContentFilterTests`; esperado: cenários atingem as premissas e zero falhas nos dois locales previstos.

**Commit:** `test(composition): make publication and locale regressions discriminating`. Se houver conserto de produto, commit separado nomeando a causa comprovada.

### R01 — Ingresso de observações com trabalho pendente limitado (restante T2)

**Files:** `AppComposition.swift`, `FeedScreenStore.swift`, `FeedPresentationSnapshot.swift`, `FeedPresentationHandoff.swift`; testes em `CompositionTests.swift`, `FeedScreenStoreTests.swift`, `FeedViewportCaptureTests.swift`.

**Interfaces:** manter `FeedRunwayDriver.submitViewport` e proveniência de `RenderedViewportEvidence`. O Set de membership já entregue continua preparado por janela. O owner de composição recebe fatos sem criar uma Task por callback.

- [ ] Criar `testScrollIngressDoesNotAwaitProducer`: suspender aquisição/produção, enviar observação e comprovar retorno da captura antes de liberar o produtor.
- [ ] Criar `testMovingObservationsRemainBoundedAndPreserveRest`: consumidor suspenso, rajada de avanços, reversão e repouso; exigir trabalho pendente limitado, última posição correta, high-water real, exposição dos cards realmente vistos e repouso persistível.
- [ ] Acrescentar `testCoalescingPreservesCapturedConsumptionTiming`: usar relógio controlado; coalescer não pode transformar tempo de drenagem em velocidade do gesto.
- [ ] Substituir Tasks por callback por um único consumo pendente no `FeedAssociation` existente. Manter um resumo finito dos fatos substituíveis e dos semânticos necessários; não simplesmente conservar o último evento e perder avanço/repouso/exposição.
- [ ] Capturar tempo monotônico e identidade no ingresso quando necessários à medição; validar contra scope e sequência vigentes na entrega. Preparar qualquer índice posicional junto da janela, nunca por evento.
- [ ] Fechamento/background encerra autorização de produção e conserva a posição prometida. Nenhum evento de associação aposentada entra na nova.

**Verificação:** `swift test --filter FeedScreenStoreTests`, `swift test --filter FeedViewportCaptureTests`; Xcode `CompositionTests` com as três regressões novas. Esperado: captura conclui com produtor bloqueado e pendências não crescem com o tamanho da rajada.

**Commit:** `fix(ui): bound viewport ingress without losing semantic facts`.

### R02 — Instalação de apresentação e bookmarks sem I/O (restante T2)

**Files:** `FeedPresentationHandoff.swift`, `FeedScreenStore.swift`, `AppComposition.swift`, `ReaderLibraryCoordinator.swift`, stores de bookmarks existentes. Testes: `FeedPresentationHandoffTests.swift`, `FeedScreenStoreTests.swift`, `CompositionTests.swift`.

**Interfaces propostas:** um valor `PreparedFeedInstallation` no handoff contém `state: FeedPresentationState`, `bookmarkedIDs: Set<PublicationCardID>` e a base de bookmarks/identidade observada na preparação. `FeedAssociation.install(_ prepared: PreparedFeedInstallation) throws` apenas valida e instala valores. Relatos de work sem nova projeção reutilizam metadados prontos.

- [ ] Criar `testInstallDoesNotReadDatabase`: preparar o pacote, suspender o armazenamento por um seam do teste e instalar; a instalação deve concluir sem chamar storage/preparador.
- [ ] Criar `testOldBookmarkPreparationCannotUndoConfirmedToggle`: preparar A, confirmar salvar/remover e entregar A depois; o estado confirmado vence. Repetir com duas caixas, exclusão de caixa e conclusão invertida.
- [ ] Mover leitura de bookmarks e cálculo de diferenças para o executor do owner existente fora do MainActor. Centralizar a entrega de mutações confirmadas da biblioteca no mesmo caminho de composição.
- [ ] Validar a base capturada contra o estado confirmado vigente, além da proveniência da projeção. Pacote antigo não pode sobrescrever bookmarks atualizados. Repreparar quando necessário; não criar cache independente nem contador de geração de aquisição.
- [ ] Remover SQL de `install` e o workaround `bookmarksReadFor` quando não tiver mais função. Não atualizar primeiro uma parte observável e depois lançar erro na outra.
- [ ] Verificar que posição sem diferença material não republica a lista, mas conserva o handoff que alimenta runway/produção.

**Verificação:** `swift test --filter FeedPresentationHandoffTests`, `swift test --filter FeedScreenStoreTests`; Xcode `CompositionTests` com as duas regressões. Esperado: zero leituras durante instalação, rejeição preserva estado inteiro e toggle confirmado não regride.

**Commit:** `fix(ui): install prepared projection metadata without database reads`.

### R03 — Preservar pixels e âncora na reversão (T3, primeira entrega)

**Files:** `FeedSession.swift`, `PresentationCard.swift`, `FeedInteractionPresentation.swift`, `FeedNativeViewport.swift`; testes `RenderReadyAdmissionTests.swift`, `FeedSessionViewportTests.swift`, `CardImageJourneyUITests.swift`.

**Interfaces:** preservar `PresentationCard.isRenderReady` e `FeedSession.admitPresentation(_:)`. Residência continua separada do payload durável.

- [ ] Criar `testReverseExposurePrecedesViewportCallback`: soltar pixels de região antiga, reverter antes de entregar viewport ao runtime e observar a superfície no instante da exposição. Assertar imagem real, identidade e geometria; não apenas estado após o callback.
- [ ] Criar `testMissingAssetDoesNotRemoveVisibleAnchor`: remover arquivo depois da publicação; o card ainda apresentado, sua âncora e dimensões permanecem.
- [ ] Reconciliar o teste antigo `testACardReturningToThePixelBandIsReconstructedBeforeItIsDrawn`, que atualmente aceita excluir uma identidade após falha de reconstrução. Novo aceite exige preservar o que está visível e controlar a transição para o destino indisponível.
- [ ] Proteger pixels de toda região que a superfície pode revelar imediatamente. Readmissão prepara decode fora da UI e só libera exposição com destino pronto. A simples banda preditiva não é a prova.

**Verificação:** `swift test --filter RenderReadyAdmissionTests`, `swift test --filter FeedSessionViewportTests`; Xcode `CardImageJourneyUITests`, caso reversão em Release. Esperado: zero slot vazio, nenhuma remoção visível ou salto de âncora.

**Commit:** `fix(runtime): preserve ready pixels across reverse exposure`.

### R04 — Histórico, saltos e pressão de memória com transição segura (T3, fechamento)

**Files:** mesmos owners de R03 e caminho de residência existente; testes em `FeedSessionViewportTests.swift`, `FeedViewportCaptureTests.swift` e UI tests de imagem/acessibilidade.

**Interfaces:** navegação imediata só alcança região pronta; destinos além dela passam pela admissão existente antes de se tornarem navegáveis. Histórico durável continua acessível; teto de 2000 preservado como guarda.

- [ ] Criar `testProgrammaticJumpWaitsForReadyDestination`, `testVoiceOverNavigationNeverExposesReleasedPixels` e `testMemoryPressurePreservesCurrentReading`.
- [ ] Integrar uma fronteira de transição à superfície nativa: salto/retorno para fora da região pronta solicita preparo, conserva a leitura atual e só aplica a posição quando a sessão entrega o destino pronto. Se o destino é irrecuperável, comunicar indisponibilidade sem reescrever publicação.
- [ ] Liberar pixels apenas após a região deixar de ser imediatamente revelável e fora de um gesto que a usa. Não conservar todos os bitmaps como solução; medir bytes residentes.
- [ ] Exercitar histórico extenso, reversões rápidas repetidas, Dynamic Type, VoiceOver, salto arbitrário e arquivo ausente. Provar preservação geométrica no desenho, não por contagem de IDs apenas.

**Verificação:** testes de R03 mais os três casos novos; jornada Release com pressão de memória e trace correlacionado. **G1 só fecha após R01–R04 passarem.**

**Commit:** `fix(ui): gate historical navigation on ready presentation`.

### R05 — Coordenador de aquisição independente do consumidor de resultados (T4, primeira entrega)

**Files:** `AcquisitionCoordinator.swift`; `AcquisitionCoordinatorTests.swift`.

**Interfaces:** preservar `executeConcurrently(_:operation:trace:onResult:) async throws -> [AcquisitionExecutionResult]`, resultado final na ordem do plano, single-flight e erros tipados. Conclusão durável do target antecede a notificação editorial.

- [ ] Criar `testBlockedResultConsumerDoesNotStopOtherEligibleTargets`: A termina e seu consumidor suspende; B continua na rede; C e D precisam iniciar/concluir dentro da autorização. Exigir progresso além de uma única reposição antecipada.
- [ ] Testar erro fatal, cancelamento, callback duplicado, joins de single-flight e ordem final diferente da ordem de término.
- [ ] Separar reposição/coleta de rede do consumo de notificações, com trabalho filho estruturado e backlog limitado pelo plano/capacidade autorizada. Não lançar Task editorial ilimitada por resultado.
- [ ] Parar novos starts após cancelamento/fatal e drenar/cancelar filhos conforme contrato; não perder contabilidade de resultados já duráveis.

**Verificação:** `swift test --filter AcquisitionCoordinatorTests`; esperado: C/D progridem antes da liberação do consumidor, teto de sockets respeitado, uma execução por target e erro não ocultado.

**Commit:** `fix(acquisition): decouple network slots from result consumption`.

### R06 — Driver publica resultado durável antes do fim da rodada (T4, fechamento)

**Files:** `RunwayAcquisitionCycle.swift`, `FeedRunwayDriver.swift`, `ColdFeedBootstrap.swift`; testes homônimos.

**Interfaces:** manter o único `causalExecution` do driver. A rodada tem atividade de aquisição em andamento e fatos de conclusão individual; seu encerramento total não autoriza sozinho nem bloqueia a seleção local.

- [ ] Criar `testFastSourcePublishesWhileSlowSourceIsPending` no driver e no cold bootstrap: liberar A, segurar B, exigir recibo e primeira instalação de A antes de liberar B.
- [ ] Criar `testDurableResultAfterEditionSwitchDoesNotPublishIntoOldScope`; preservar supply válido, rejeitar instalação/recibo antigo e não duplicar publicação.
- [ ] Entregar fatos pequenos de supply durável ao owner existente para reconsideração durante aquisição. Manter um único loop de publicação; chamadas reentrantes apenas atualizam fatos/prioridades.
- [ ] Cobrir close, cancelamento, erro de admissão e fim da rodada. Preservar admissão/checkpoint atômicos e os resultados finais exigidos pelos callers.

**Verificação:** `swift test --filter RunwayAcquisitionCycleTests`, `FeedRunwayDriverTests`, `ColdFeedBootstrapTests` e R05. Esperado: A publicada com B suspensa e nenhum executor causal duplicado.

**Commit:** `fix(composition): publish durable results before round completion`.

### R07 — Preparação de mídia sem barreira para candidatos prontos (T5)

**Files:** `MediaPrefetcher.swift`, `LocalProductionSlice.swift`, `FeedRunwayDriver.swift`, `ColdFeedBootstrap.swift`; testes existentes desses owners.

**Interfaces:** reaproveitar `noteMediaReadinessChanged()` e `SelectionReadinessSnapshot`; manter `LocalProductionSlice.run(_:prepare:)` selecionando só oferta pronta/elegível.

- [ ] Criar `testReadyCandidatePublishesBeforeUnrelatedMediaCompletes`, `testLateReadyCandidateIsReconsideredOnce` e `testReadinessFailureDoesNotCreateRetrySpin`.
- [ ] Segurar decode de A, deixar imagem B e texto legitimamente declarado prontos; B/texto publicam antes de A. Não aceitar conversão de A pendente para texto.
- [ ] Retirar `await prepareMedia(...)` da condição necessária para executar o slice. MediaPrefetcher recebe prioridades e mantém seu single-flight; readiness individual acorda a reconsideração existente.
- [ ] Cobrir cursor que passou por A: A volta a ser examinada quando pronta, sem sumir ou duplicar após notificações repetidas. Sem varredura infinita de pendentes.
- [ ] Combinar HTTP suspenso, decode suspenso, fonte rápida e cancelamento de contexto no mesmo ensaio.

**Verificação:** `swift test --filter MediaPrefetcherTests`, `LocalProductionSliceTests`, `FeedRunwayDriverTests`, `ColdFeedBootstrapTests`; esperado: recibo pronto antes da liberação dos dois bloqueios e nenhuma duplicação.

**Commit:** `fix(media): publish ready supply without preparation barriers`.

### R08 — Descoberta sem percorrer todo o histórico sob lock (T6, primeira entrega)

**Files:** `ReaderDiscoveryTraversal.swift`, `SyndicationAcquisitionSnapshot.swift`; `ReaderDiscoveryPoolTests.swift` e novo `Tests/FeedMineCompositionTests/ReaderDiscoveryTraversalTests.swift`.

**Interfaces:** preservar `advance`, `adopt`, resolução de targets/connectors e identidade de catálogo/autoridade. Índices por target pertencem à mesma travessia e são invalidados junto dela.

- [ ] Criar `testConnectorLookupDoesNotScanPriorPages`, `testDuplicateAdoptionDoesNotRematerializeTarget` e `testCatalogueRevocationDuringMaterializationCannotReinstallTarget`.
- [ ] Substituir `Set(pages.flatMap...)` e lookup linear repetido por índices derivados atualizados na instalação válida da página.
- [ ] Reservar a oportunidade sob identidade atual; materializar catálogo/SQL fora do lock; revalidar fingerprint e autoridade antes de instalar. Exceção/cancelamento libera a reserva sem avançar cursor indevidamente.
- [ ] Testar atualização de catálogo, adoção concorrente, revogação, falha de materialização e retomada. Não adicionar contador de geração quando a identidade existente basta.

**Verificação:** `swift test --filter ReaderDiscoveryTraversalTests`, `ReaderDiscoveryPoolTests`. Esperado: lookup/coordenação não crescem com páginas históricas; zero alvo revogado readmitido.

**Commit:** `perf(discovery): index targets and bound traversal critical sections`.

### R09 — Orçamentos adaptativos por estágio (T6, segunda entrega)

**Files:** `CollectionLaunchSettings.swift`, `AcquisitionPlanner.swift`, `FeedRunwayDriver.swift`, montagem de resources em `AppComposition.swift`; testes `AcquisitionPlannerTests.swift`, `CollectionLaunchAndOrderingTests.swift`; criar `Tests/FeedMineCompositionTests/PipelineHeadroomTests.swift`.

**Interfaces:** `AcquisitionPlanningResources` continua autorização explícita por oportunidade. Bootstrap/teto operacional não substituem fatos medidos de consumo, reposição e pressão. Rede e preparo local recebem orçamentos distintos.

- [ ] Criar `testAvailableResourcesIncreaseUsefulWork`, `testPressureReducesWorkWithoutStarvingEligibleTargets`, `testExhaustedSupplyWaitsForNewFacts` e `testForegroundCadenceAndCardGuardRemainOperationalBounds`.
- [ ] Com demanda idêntica, comparar recursos disponíveis/pressionados e progressão de targets ao longo de oportunidades; assertar justiça e trabalho útil, não só tarefas criadas.
- [ ] Adaptar usando medidas já disponíveis; dados ausentes usam bootstrap documentado, nunca latência inventada. Reduzir trabalho sob pressão de CPU/memória/rede/disco/energia efetivamente observada.
- [ ] Manter 48/8 onde representam bootstrap/teto; qualquer revisão do teto exige evidência separada. Não criar quota permanente de fontes nem busy-loop com oferta vazia.

**Verificação:** classes citadas mais `PipelineHeadroomTests`; esperado: resposta relativa a recursos, limites respeitados e avanço de elegíveis após oportunidades suficientes no cenário controlado.

**Commit:** `perf(runtime): adapt stage budgets to demand and measured resources`.

### R10 — Transações curtas sem perder atomicidade (fechamento T6)

**Files:** caminhos de admissão em `Sources/FeedMineAcquisition/` e publicação em `Sources/FeedMinePublication/`, somente nos trechos comprovadamente caros; testes existentes de atomicidade; `PipelineHeadroomTests.swift`.

**Interfaces:** admissão/checkpoint e append/publication receipt continuam atômicos. Parsing, decode e preparação independente ficam antes da transação; verificação dependente de autoridade fica dentro dela.

- [ ] Medir duração/espera do escritor sob aquisição e publicação simultâneas; identificar trabalho síncrono dentro da transação antes de mover código.
- [ ] Criar `testAdmissionFailureRollsBackSupplyAndCheckpoint`, `testPublicationFailureLeavesNoPartialSegment` e `testConcurrentDurableStagesPreserveWriterConsistency` nos targets dos owners correspondentes, reutilizando regressões equivalentes existentes.
- [ ] Mover somente trabalho puro/preparatório comprovado; revalidar autoridade dentro do commit. Não paralelizar escritores SQLite nem remover constraints para throughput.

**Verificação:** classes de atomicidade efetivamente tocadas, `PipelineHeadroomTests`, suíte Swift no gate. **G2 exige R05–R10 verdes e demonstração conjunta de rede/mídia/publicação independentes.**

**Commit:** `perf(persistence): shorten durable transactions without weakening fences` ou registro de comportamento já presente, se nenhuma alteração for necessária.

### R11 — A→B→A, prioridades e confirmação durável (T7)

**Files:** `AppComposition.swift`, `FeedRunwayDriver.swift`, `FeedSession.swift`; testes `CompositionTests.swift`, `FilterConfirmationBoundaryTests.swift`, `FeedPresentationHandoffTests.swift`, `FeedRunwayDriverTests.swift`.

**Interfaces:** contexto/edição/revisão/proveniência existentes autorizam o destinatário. Confirmação persistente precede sucesso reconhecido na UI; recibo é revalidado no ponto da mutação.

- [ ] Criar `testContextSwitchUnderLoadReusesCanonicalWork`, `testLateReceiptIsRejectedAtInstallationBoundary`, `testConfirmedFilterSurvivesActivationFailureAndRelaunch` e `testProgressWithStationaryReaderDoesNotWaitForCadence`.
- [ ] Reordenar conclusões em A→B→A com bytes válidos já admitidos/preparados; exigir reaproveitamento, edição/posição corretas e nenhuma aquisição apenas para repetir bytes utilizáveis.
- [ ] Preservar os quatro testes de confirmação já verdes; ampliar para falha de disco antes do commit e falha de ativação depois dele, com mensagem/recuperação diferentes.
- [ ] Atualizar prioridade futura nos owners atuais; cancelar apenas trabalho sem utilidade. Supply/readiness novos acordam produção imediatamente, enquanto ausência de fatos novos deixa o sistema quieto.
- [ ] Repetir com background, relaunch e offline. Assegurar que a nova prova do recibo de R00 continua atingindo a fence real.

**Verificação:** classes citadas e jornada de contexto no host; esperado: zero projeção estrangeira, intenção confirmada durável e posição restaurada.

**Commit:** `fix(context): preserve reusable work and durable scope transitions`.

### R12 — Salvos, retenção e recuperação offline (T8)

**Files:** `SavedMediaCoordinator.swift`, `ReaderLibraryCoordinator.swift`, `SavedMediaAvailabilityStore.swift`, `Sources/FeedMineMedia/MediaRetention.swift`, `MediaTidy.swift`, apresentação de biblioteca somente onde falhar. Testes existentes de salvos/stores e `ReadingCompositionTests.swift`.

**Interfaces:** bookmark é intenção durável; disponibilidade descreve bytes efetivamente presentes. Retenção continua usando raízes existentes, sem outro modelo de card.

- [ ] Criar/completar `testSavedContentSurvivesRelaunchAndDisposableCachePurge`, `testRemovingOneBookmarkBoxKeepsSharedSavedAssets`, `testDiskFailurePreservesBookmarkAndReportsPartialAvailability` e `testMaintenanceProtectsVisibleAndSavedContent`.
- [ ] Salvar, terminar preparo, fechar processo, remover apenas cache descartável e reabrir offline: verificar texto, imagem e ação prometidos. Link não significa corpo completo baixado.
- [ ] Cobrir disco cheio, download falho, arquivo removido, retry e duas caixas. Remover uma referência não remove bytes retidos por outra; falha parcial não apaga bookmark.
- [ ] Corrigir só lacunas reproduzidas: a candidata já possui implementação e regressões de salvos.

**Verificação:** `SavedMediaCoordinatorTests`, `SavedMediaAvailabilityStoreTests`, `MediaTidyFactsTests`; Xcode `ReadingCompositionTests` e jornada offline no dispositivo.

**Commit:** `fix(library): complete saved-content durability and offline recovery` ou registro de contratos já aprovados.

### R13 — Neutralidade, namespaces e combinações de mídia (T9, preferências)

**Files:** `ReaderDiscoveryPool.swift`, mapeamento de receita/filtros existente, `ReaderFilterStore.swift`; testes `ReaderDiscoveryPoolTests.swift`, `ReaderFilterStoreTests.swift` e testes de elegibilidade/editorial existentes.

**Interfaces:** `.more` orienta interesse, `.less` aplica o contrato de redução/exclusão vigente e `.neutral` não vira exclusão. Namespaces de assunto e editorial continuam distintos.

- [ ] Criar `testNeutralPreferenceDoesNotExcludePersistedTopic`, `testEditorialAndTopicKeysDoNotCollide` e `testEveryMediaSelectionCombinationKeepsItsMeaning`.
- [ ] Exercitar receitas persistidas antigas e transições more→neutral, less→neutral, neutral→more; o ramo `else` atual de não-more não pode continuar excluindo neutral.
- [ ] Testar todas as combinações do enum real de mídia, inclusive vazio, individual, pares e todos; pares não equivalem a todos. Preservar semântica declarada do estado vazio.

**Verificação:** classes citadas; esperado: round-trip de persistência e elegibilidade correspondem exatamente às escolhas.

**Commit:** `fix(preferences): preserve neutrality and exact media selections`.

### R14 — Expressão de busca única e compatibilidade persistida (T9, expressão)

**Files:** criar `Sources/FeedMineDomain/SearchExpression.swift` e `Tests/FeedMineDomainTests/SearchExpressionTests.swift`; modificar `FeedContext.swift`, `CandidateProvider.swift`, persistência/migrações de contexto/preset somente para compatibilidade explícita; testes `CandidateProviderTests.swift` e de presets existentes.

**Interfaces propostas:** `SearchExpression.init(query: String)`, `var canSearch: Bool`, `func matches(fields: [String]) -> Bool`; `SearchSemantics: String, Codable, Sendable` com `.legacyLiteral` e `.termsV1`; `SearchContext.init?(query: String, semantics: SearchSemantics = .termsV1)` e `let semantics: SearchSemantics`. O domínio interpreta; provider e UI consomem a mesma expressão. `SearchContext.query` preserva o texto original. Não criar SearchEngine.

- [ ] Casos: `astronomia ciência` exige ambos os positivos, inclusive título+resumo separados; `astronomia -astrologia` exclui; `teoria-de-cordas` mantém hífen interno; case/diacríticos não distinguem; só negativos não inicia busca; `-` isolado não cria consulta válida sozinho.
- [ ] Exemplo discriminante: título `Astronomia`, resumo `Ciência aberta`, expressão `astronomia ciência -astrologia`: verdadeiro; inserir `astrologia` num campo: falso.
- [ ] Manter gramática delimitada ao contrato aprovado; não inventar aspas, OR, pesos ou operadores adicionais.
- [ ] Introduzir modo/versão semântica persistida quando necessário para distinguir consultas legadas literais de novas expressões. Ausência do marcador decodifica como `.legacyLiteral`; novas consultas gravam `.termsV1`. A codificação do legado omite o marcador para preservar sua representação/identidade anterior; a nova semântica participa explicitamente de igualdade, hash e identidade. Não modificar silenciosamente `query` nem invalidar ContextKey antigo.
- [ ] Testar contexto/preset legado, nova expressão, relaunch offline e rollback de migração falha. Persistência e UI não podem interpretar a mesma consulta com parsers distintos.

**Verificação:** `SearchExpressionTests`, `CandidateProviderTests`, testes de contexto/preset/migração tocados. Esperado: todos os exemplos e fixtures legados preservam seu significado declarado.

**Commit:** `feat(search): share query expressions with explicit legacy compatibility`.

### R15 — Cancelar/retornar busca e erros de ação recuperáveis (T9, navegação)

**Files:** `FeedScreenStore.swift`, `ReaderShell.swift`, `AppComposition.swift`, `ReaderLibraryCoordinator.swift`; testes `FeedScreenStoreTests.swift`, `CompositionTests.swift`, `ReadingCompositionTests.swift`.

**Interfaces:** adicionar callback de intenção de cancelar ao Store; composição conserva origem completa (ContextKey, edição e posição prometida), usando a sessão/checkpoint existente. `savePreset` continua a autoridade de gravação.

- [ ] Criar `testCancelSearchRestoresExactPreviousContextAndAnchor`, `testReturningFromArticleRestoresSearch` e `testSavedSearchFailureDistinguishesWriteFromActivation`.
- [ ] Origem pode ser fonte, coleção, preset ou filtro; não presumir main. Cancelar duas vezes não restaura origem errada nem perde checkpoint.
- [ ] Remover `try?` dos caminhos de salvar/ativar busca; comunicar separadamente não gravado, gravado mas não ativado e ativo. Retry reutiliza a intenção confirmada e não duplica preset.
- [ ] Testar gravação falha, ativação falha após confirmação, conclusão invertida e relaunch offline.

**Verificação:** classes citadas e jornada UI busca→artigo→voltar→cancelar. Esperado: identidade/posição completas restauradas e mensagem compatível com o commit efetivo.

**Commit:** `fix(search): restore search origins and report durable action outcomes`.

### R16 — Escopos e resultados locais unificados reais (T9, escopos)

**Files:** `AppComposition.swift`, `ReaderShell.swift`, os backends existentes de catálogo/biblioteca/conteúdo; novos tipos de resultado de apresentação no módulo UI se necessários; testes `CompositionTests.swift`, `ReadingCompositionTests.swift` e backends tocados.

**Interfaces:** `ReaderSearchScope`/`ContextKey` existentes decidem o universo; tipos de resultado distinguem fonte, salvo e artigo local e encaminham ao destino real. Compartilhar `SearchExpression` de R14; sem segundo motor ou cópia dos dados canônicos.

- [ ] Criar `testSearchScopesReturnOnlyTheirRealResultKinds`, `testStaleSearchCompletionCannotReplaceNewScope` e `testSavedSearchReopensWithSameExpressionAndScopeOffline`.
- [ ] Conectar a barra do leitor às consultas reais de fontes/salvos/conteúdo local previstas por F11/F16. Busca de gestão de fontes sozinha não certifica busca unificada.
- [ ] Mostrar vazio/indisponibilidade reais; navegar a fonte abre fonte, salvo abre ocorrência salva e artigo abre leitura. Não apresentar resultado não consultado.
- [ ] Testar troca de termo/escopo durante consultas suspensas, origem filtrada, erro de catálogo e offline.

**Verificação:** testes citados, testes de backends e jornada completa F11/F16. Esperado: resultados tipados corretos, zero substituição obsoleta e escopo persistido.

**Commit:** `feat(search): connect explicit scopes to local result authorities`.

### R17 — Diversidade multidimensional nas emendas de segmentos (T10)

**Files:** `CandidateProvider.swift`, `SelectionEngine.swift`, `SourceAlternation.swift`, `LocalProductionSlice.swift`; tipos/registros de publicação e `RuntimeMigrations.swift` para congelar os fatos editoriais necessários; testes `SelectionEngineTests.swift`, caracterizações temáticas/temporais, `SourceDiversityContractTests.swift` e round-trip de publicação/migração.

**Interfaces:** seletor puro, seed/contexto explícitos; estender o contexto editorial/neighbor existente para receber fatos do final publicado. Propor `SelectionDiversityContext` no módulo Editorial e argumento opcional `diversity: SelectionDiversityContext? = nil` no overload completo de `select`; nil mantém o comportamento anterior. Congelar na publicação apenas os fatos efetivamente usados pela decisão, com campos opcionais/versionados. Campos desconhecidos ficam desconhecidos, sem consulta à UI.

- [ ] Criar corpus rotulado e `testDiversityUsesKnownDimensionsAcrossPublicationSeams`, `testHomogeneousSupplyRemainsPublishable`, `testMissingMetadataDoesNotInventNovelty` e `testNewSupplyNeverChangesPublishedSegmentHashes`.
- [ ] Mapear fatos legítimos de fonte/provedor, assunto da história, geografia, formato, exposição e temporalidade; categoria da fonte não vira assunto da história e `observedAt` não certifica novidade.
- [ ] Persistir os fatos editoriais mínimos usados nas novas publicações pelo owner de publicação, na mesma transação do segmento. Histórico antigo sem esses fatos continua com desconhecido; não reconstruir assunto/geografia de uma ocorrência antiga a partir da revisão canônica mais recente. Testar migração, relaunch e round-trip, preservando bytes/ordem/payload antigos.
- [ ] Depois de elegibilidade e relevância vigentes, desempatar por menor repetição recente das dimensões conhecidas no contexto editorial. Introduzir versão explícita de sequencing para o novo comportamento: preservar versões 1–4 da base, reservar 5 somente após conferir que continua livre na execução e fazer a composição criar revisão editorial compatível com ela. Uma versão desconhecida não recebe comportamento novo implicitamente. Preservar determinismo e justiça; não fabricar percentuais/pesos V1.
- [ ] Alternativas insuficientes permitem oferta homogênea honesta. Não excluir indefinidamente para alcançar variedade inexistente.
- [ ] Testar dois ou mais segmentos, seam com repetição, fatos ausentes e seed idêntica. Decisão nova que altere precedência de relevância exige revisão do contrato antes de implementação daquela regra.

**Verificação:** `swift test --filter SelectionEngineTests`, `SourceDiversityContractTests`, caracterizações afetadas e classes de publicação/migração tocadas; B02 na candidata integrada em R23. Relaunch deve conservar os fatos novos e tratar o histórico legado como desconhecido.

**Commit:** `feat(editorial): maintain factual diversity across publication seams`.

### R18 — Primeira experiência e abastecimento após primeiro card (parte T11)

**Files:** `ColdFeedBootstrap.swift`, `AppComposition.swift`, onboarding/superfícies de loading existentes; `ColdFeedBootstrapTests.swift`, `CompositionTests.swift` e UI tests de primeira abertura.

**Interfaces:** loading consome `ColdFeedEvidence` real; primeira publicação encerra espera inicial, não abastecimento. Preferências de idioma usam IDs estáveis.

- [ ] Criar `testFirstPublicationDoesNotEndSupplyProgress`, `testFirstLaunchFailureHasRecoverableExit` e `testWelcomePersistenceFailureDoesNotClaimCompletedOnboarding`.
- [ ] Exercitar fontes rápidas/lentas, nenhuma resposta, offline, conteúdo vazio e falha de gravar boas-vindas; distinguir ausência de histórias de falha de transporte.
- [ ] Mostrar progresso sustentado por fatos reais, saída recuperável e escolhas de idioma efetivas. Preservar primeira apresentação enquanto chegam novas fontes.

**Verificação:** `ColdFeedBootstrapTests`, Xcode `CompositionTests` e UI de instalação limpa com configuração explícita. Esperado: nenhum progresso inventado, primeira imagem/texto prontos e pipeline continua após primeira instalação.

**Commit:** `fix(onboarding): preserve factual startup and continuing supply`.

### R19 — Ver fonte interno e ações de leitura honestas (parte T11)

**Files:** `AppComposition.swift`, `ReaderActionCoordinator.swift`, `ReaderShell.swift` e superfícies de leitura; `ReaderActionCoordinatorTests.swift`, `ReadingCompositionTests.swift`, `ReadingSurfaceUITests.swift`.

**Interfaces:** Ver fonte seleciona contexto interno de fonte; ação explícita de site abre URL. Resolver referência congelada continua responsabilidade do coordenador existente.

- [ ] Criar `testViewSourceOpensInternalSourceContext`, `testExplicitWebsiteActionOpensDeclaredURL` e `testPartialLocalArticlePreservesHonestAvailabilityAndReturnPosition`.
- [ ] Corrigir o ramo atual que usa `sourcePage`/URL como destino de Ver fonte; manter a ação de site distinta.
- [ ] Testar corpo parcial/completo, sem URL, URL inválida, mídia indisponível e retorno ao feed/à busca de origem sem perder posição.

**Verificação:** classes citadas e jornada de abrir/voltar; esperado: destino corresponde ao nome da ação, nenhuma disponibilidade falsa e zero deslocamento indevido na volta.

**Commit:** `fix(reader): open internal source context and preserve honest actions`.

### R20 — Catálogo atômico e concessões limitadas do iOS (parte T11)

**Files:** `CatalogUpdater.swift`, `CatalogInstallation.swift`, `AppComposition.swift`, handlers de background existentes; testes `CatalogUpdaterTests.swift`, `CatalogInstallationTests.swift`, `CatalogueUpdateAcceptTests.swift` e composição.

**Interfaces:** snapshot de catálogo ativo troca atomicamente no owner atual; só altera trabalho futuro. Fontes pessoais, memberships, leitura e publicações não são substituídas pelo catálogo.

- [ ] Criar/completar `testCatalogueInterruptionKeepsPreviousActiveSnapshot`, `testCatalogueActivationPreservesPersonalSourcesAndReadingHistory` e `testBackgroundGrantExpiryCancelsWorkAndForegroundResumesSafely`.
- [ ] Testar manifesto/payload inválidos, interrupção entre staging/ativação, rollback, offline e atualização durante travessia/materialização de R08.
- [ ] Respeitar scene/background, expiração e proteção de arquivos segundo F21/F23/F24; não depender de janela exata de BGTask. Confirmar retomada e checkpoint após cancelamento.

**Verificação:** classes citadas; host com transporte controlado; casos físicos de expiração/proteção em R23. Esperado: ou snapshot anterior íntegro ou novo íntegro, nunca catálogo misturado e nenhuma perda pessoal.

**Commit:** `fix(catalog): preserve atomic activation across lifecycle interruption` ou registro das jornadas já aprovadas.

### R21 — Locale, acessibilidade e composição das jornadas (fechamento T11)

**Files:** somente superfícies com defeito comprovado; `ContentFilterTests.swift`, `AppearanceLegibilityUITests.swift`, `ReadingSurfaceUITests.swift`, `FluidityJourneyUITests.swift` e testes de onboarding/controle existentes.

**Interfaces:** IDs de máquina não localizados; linguagem de conteúdo e texto localizado são fatos distintos. Dynamic Type/VoiceOver usam as transições prontas de R04.

- [ ] Declarar idioma/região em todos os ensaios que dependem de texto e garantir fixtures de um ou vários idiomas intencionais. Preservar a prova bilíngue de R00.
- [ ] Exercitar tamanhos de texto suportados, foco de VoiceOver, filtros/busca/salvos e navegação programática sem slot vazio ou perda de posição.
- [ ] Executar jornadas compostas: onboarding→leitura→busca→salvar→trocar contexto→background→relaunch offline. Corrigir só defeitos reproduzidos.

**Verificação:** classes UI citadas, unitários afetados e suíte ampla da candidata. **G3 fecha apenas com R11–R21 aprovadas e sem as premissas vermelhas de R00.**

**Commit:** `test(journeys): verify localized accessible reader continuity` e commits de correção separados por causa.

### R22 — Folga real por estágio e proteção da UI (parte T12)

**Files:** `PipelineHeadroomTests.swift`, suporte de testes dentro de `Tests/FeedMineCompositionTests/` e instrumentos existentes fora de `bench/`; evidências em `docs/reviews/evidence/2026-10-17-v2-plan/`.

**Interfaces:** carga declara recursos/demanda; métricas vêm de conclusões reais por estágio, sem contar candidato examinado como card publicado.

- [ ] Cenário com **1.000+ fontes**, **10.000+ candidatos**, **100 fontes simuladas independentes**, repetidos/falhas/mídia e latências controladas. Comparar com `ContentStoreCandidateWindowScaleTests` de **100.000 linhas**.
- [ ] Medir separadamente admitidos/s, examinados/s, preparados/s e publicados/s, latência p95, filas, tarefas e bytes residentes. Registrar duração, hardware/OS, corpus, condições e denominadores.
- [ ] Para consumo de **1 card/s** e rajadas de **3 cards/s**, testar capacidade local correspondente a **10×**: demanda local útil de referência 10/30 cards/s onde o estágio produz cards. Para estágios com outra unidade, declarar a conversão pelo rendimento útil observado, nunca equivalência implícita.
- [ ] Criar `testFastSourcePublishesWithHTTPAndDecodeSuspended`, `testUsefulLocalThroughputHasTenfoldHeadroomUnderDeclaredResources` e `testPipelineQueuesAndResidentMemoryRemainBounded`.
- [ ] Comparar scroll local com produtores pausados/ativos; correlacionar trace Release e janela real dos gestos, inspecionar stacks de hitches. Sem trace/frames: **NOT_MEASURED**.
- [ ] Registrar gargalo se a meta não for atingida; corrigir no owner causal, sem reduzir meta, adulterar corpus ou aumentar quotas fixas. Rede pública recebe prova separada, sem SLA artificial de 10×.

**Verificação:** `PipelineHeadroomTests`, `ContentStoreCandidateWindowScaleTests`, jornadas Release/Instrumentos. Esperado: métricas por estágio sustentam a conclusão, backlog/RAM limitados e leitura protegida durante produção.

**Commit:** `test(capacity): record measured useful pipeline headroom`.

### R23 — Simplificação, candidata única e aceitação congelada (fechamento T12)

**Files:** owners com mecanismos efetivamente substituídos por R01–R22; registro de execução e evidências. `bench/` permanece intacto.

**Interfaces:** preservar regressões de produto, rastreabilidade por SHA/build e evaluator congelado. Remover mecanismo só com call sites e substituição comprovados.

- [ ] Remover Tasks/timers/call sites mortos, helpers duplicados e testes que só espelham implementação, após referência e prova; nenhuma meta artificial de linhas removidas.
- [ ] Congelar candidata integrada; executar suíte ampla, build de app, testes unitários/integração e UI aplicáveis. Novo conserto exige repetir apenas ensaios invalidados e registrar novo SHA.
- [ ] Executar B01–B06 conforme documento vigente, com hashes de avaliador/corpus e duração integral. B03 exige **30 minutos de avanços efetivos**, **1 card/s**, rajadas de até **3 cards/s por 20 s a cada 5 min**; quatro minutos ou app parado não equivalem ao teste.
- [ ] Executar B06 em aparelho físico compatível, além do simulador. Registrar dispositivo/OS, build, namespace, logs, xcresult, trace real, recursos e resultado por cláusula.
- [ ] Repetir A pronto/B suspenso, decode pendente, A→B→A, reversão, foreground e offline na mesma candidata. Confirmar hashes/ordem da publicação antiga.
- [ ] Revisão independente da branch completa contra spec, Review Focus e decisões registradas; corrigir achados importantes com reprodução e nova prova. Registrar limites da revisão.
- [ ] Produzir matriz PASS/FAIL/NOT_RUN/BLOCKED/NOT_MEASURED por gate e cláusula. Sem físico ou evidência obrigatória, trabalho local pode estar implementado, mas a certificação/release permanece aberta.

**Verificação:** comandos oficiais de `docs/IOS_RUN.md`, `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md` e harness congelado, sem inventar flags ou reduzir duração. `git diff --check`; confirmar que `git diff <base> -- bench/` é vazio.

**Commit:** `test(acceptance): record integrated runway and headroom evidence`.

## 8. Matriz de cobertura do roteiro original

| Requisito original | Entrega restante | Evidência de encerramento |
|---|---|---|
| T1 — reconciliação e preservação | Já entregue; R00 resolve premissas residuais | Registros anteriores preservados, cenários realmente atingidos |
| T2 — fronteira do scroll | Membership entregue; R01–R02 restantes | Captura limitada, sem perda semântica; instalação sem I/O |
| T3 — pixels antes da exposição | R03–R04 | Reversão, salto e VoiceOver antes de callback; pressão de RAM |
| T4 — callbacks/rodada independentes | R05–R06 | C/D progridem; A publica com B suspensa |
| T5 — readiness independente | R07 | Prontos publicam, tardio é reconsiderado uma vez |
| T6 — capacidade/traversal/transações | R08–R10 e R22 | Custo limitado, justiça, atomicidade e throughput útil |
| T7 — contextos e prioridades | R11 | A→B→A, fences no destinatário e confirmação durável |
| T8 — salvos e offline | R12 | Relaunch/purge/offline, duas caixas e falha de disco |
| T9 — controles/busca | R13–R16 | Neutral, matriz mídia, expressão/compatibilidade, origem e escopos |
| T10 — diversidade | R17 | Corpus factual e seams determinísticas; B02 |
| T11 — primeira experiência/navegação/catálogo | R18–R21 | Jornada composta, atomicidade e limites iOS |
| T12 — capacidade/aceitação/simplicidade | R22–R23 | 10× declarado e B01–B06 na candidata integrada |

## 9. Definição de conclusão e passagem para execução

O plano cobre todo o restante conhecido na base indicada. **Nenhuma R00–R23 está marcada como executada por este documento.**

Implementação concluída exige contratos de R00–R21 verdes na candidata integrada, limites e folga de R22 comprovados sob condições declaradas, mecanismos substituídos consolidados e achados importantes da revisão resolvidos. Aceitação de produto exige adicionalmente G1–G4 e todas as cláusulas obrigatórias de B01–B06 comprovadas. Ausência de aparelho, corpus ou trace nunca vira PASS.

Primeira unidade executável: **R00 → R01 → R02**, preservando os commits já existentes. Próxima: **R03 → R04 → G1**. Só depois elevar independência/capacidade com R05–R10.

Este pedido cria o plano do restante. A execução futura deve partir da branch/base reconciliada, usar o registro persistente e percorrer as tarefas até os critérios de conclusão, sem repetir T1 ou tratar a subentrega de membership como T2 inteira.
