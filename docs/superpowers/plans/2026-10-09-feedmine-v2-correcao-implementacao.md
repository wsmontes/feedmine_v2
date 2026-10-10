# FeedMine V2 — Plano completo de correção e implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Delegação exige autorização explícita do usuário. Este documento autoriza planejamento; sua execução é uma etapa posterior.

**Goal:** Fechar o fluxo adquirir → preparar → publicar → manter reserva adaptativa → apresentar localmente → observar consumo → adaptar produção, com mídia, diversidade, contextos reutilizáveis e evidência integrada de operação no iPhone.

**Architecture:** Evoluir os owners existentes, preservando SQLite como autoridade, Publication como histórico imutável e FeedRunwayDriver como único executor dos efeitos causais de abastecimento. Manter separados supply canônico, reserva publicada e janela visual. A composição conecta políticas, recursos e eventos reais; SwiftUI consome apenas projeções e assets locais.

**Tech Stack:** Swift 6, SwiftUI, Observation, actors, SQLite/GRDB 7.11.1, FeedKit 10.9.4, URLSession, ImageIO, XCTest e XCUITest. Deployment do pacote: iOS 18/macOS 14; captura nativa disponível em iOS 18/macOS 15.

**Spec:** `docs/architecture/PRODUCT_INVARIANTS.md`, `MEDIA_DESIGN.md`, `CONTINUOUS_FEED_RUNWAY_DESIGN.md`, `SELECTION_DESIGN.md`, `RUNTIME_PRESENTATION_CONTRACT.md`, `PUBLICATION_RESTORE_CONTRACT.md`, todos em `docs/architecture/`. Entrada adicional: revisão fornecida pelo usuário, datada de 9/10/2026, base a259e96d. Decisões novas propostas estão explícitas abaixo e devem ser conciliadas com esses contratos antes da implementação correspondente.

## 1. Base verificada e limites

Inspeção local em 9/10/2026:

- HEAD: `a259e96`, commit da integração iOS. Branch local: `phase/3r11a-media-acquisition-durable-asset`, acompanhando `origin/main` na inspeção.
- Há alterações não commitadas em `ImageMaterializer.swift`, `MediaPolicy.swift`, `MediaResolver.swift`, mais `MediaAcquisition.swift` e seus testes novos. Existem `.build/` e `Package.resolved` não rastreados. Não remover, sobrescrever ou incorporar indiscriminadamente.
- `AppComposition` usa duas fontes BBC, contexto `.main`, seleção estrutural/equal/recency e preparação exclusivamente `.textOnly`.
- `PresentationCard` expõe layout/aspect ratio, mas não o asset visual. `FeedCardView` renderiza texto. Corrigir apenas a View não fecha a cadeia de mídia.
- `prepare` nos fluxos Cold/Driver é síncrono. Aquisição remota assíncrona precisa ocorrer fora dessa fronteira e fora de transações SQLite.
- `FeedRunwayDriver` já possui drain causal e reconsideração coalescida. O problema é a política e os gatilhos de continuação, não ausência total de loop.
- `RunwayPolicy` pode considerar taxa zero saudável e só iniciar bootstrap desconhecido quando há intenção/tail. Isso conflita com preparação antecipada após a primeira apresentação.
- Cold oferece uma oportunidade finita e foreground tenta novamente; não há continuação autônoma completa sem apresentação.
- Os limites 8/16 são materialização, não tamanho total da reserva durável. O plano não transforma essa janela em meta de abastecimento.
- `ResolvedSelectionPolicy` implementa apenas comportamentos baseline; diversidade não é um parâmetro pronto a ligar.
- `FeedContextRequest` já suporta main/source/search. Catálogo persistido e composição de múltiplos contextos precisam de implementação.

Não foram executados testes, build, simulador ou profiling durante este planejamento. Os números históricos de testes são referência documental, não resultado atual. Não houve consulta ao GitHub nem validação de endpoints remotos.

## 2. Global Constraints

- INV-01: A UI apresenta estado local.
- INV-02: SwiftUI nunca inicia acquisition, chama connector, consulta banco diretamente, resolve mídia remota, implementa retries ou pagination de protocolo.
- INV-03: Scroll é observação, não comando de fetch.
- INV-04: Reserva adaptativa; números são limites operacionais, nunca a estratégia conceitual.
- INV-05: Preparação continua após os primeiros cards enquanto houver benefício e orçamento.
- INV-07: Warm launch local, antes de HTTP, seleção ou download novo.
- INV-08/09: Publicação imutável; trabalho futuro não reordena nem enriquece silenciosamente cards já publicados.
- INV-10: Mudança de contexto redireciona prioridade e preserva trabalho local válido.
- INV-11: Offline aproveita dados locais; rede é reposição.
- INV-12/14: Um owner por responsabilidade e um pipeline. Não criar segundo scheduler/reserva/selector.
- INV-13: Sem tipos de protocolo após connector/admission.
- INV-15: Sem refatoração genérica ou abstrações sem consumidor.
- No máximo uma ocorrência por OriginRecordID por Edition, inclusive após nova revisão ou mídia tardia.
- Preservar provenance do Runtime; nenhuma sequência criada na UI, nenhum contador persistido como ordem de projeção.
- Assets duráveis antes de referenciados; corrupção/I/O não se convertem silenciosamente em download ou sucesso.
- Manter grafo acíclico e dependências existentes. Media não depende de Publication; UI não acessa Persistence/Acquisition.
- Migrações aditivas, preservando bases existentes; sem apagar runtime.sqlite para fazer testes passarem.
- Nenhum timer periódico de fetch. Espera pontual por deadline de disponibilidade é permitida somente se pertence à política existente, é cancelável e evita busy loop.

## 3. Review Focus

1. Fontes lentas, 304, payload repetido e falhas parciais: produzir com o restante, parar quando não há progresso e retomar por evento/deadline legítimo (T5/T6/T7).
2. Background/troca de contexto enquanto HTTP ou mídia estão suspensos: preservar commits canônicos válidos e impedir publicação/instalação no escopo errado (T3/T5/T10).
3. Asset ausente, corrompido, imagem enorme ou armazenamento cheio: manter apresentação histórica estável e reportar falha sem refetch no renderer (T2/T4/T11).
4. Scroll concorrente, backward, Dynamic Type e mudança de geometria: aceitar a projeção mais nova, não fabricar direção e não usar medida de outra janela (T4/T8/T12).
5. Base antiga, preferências alteradas e retorno A→B→A offline: restaurar apenas Edition compatível, preservar dados e não comparar sequências de sessões distintas (T7/T9/T10).

## 4. Decisões de produto propostas

O escopo de fechamento é leitor RSS/Atom/JSON Feed já suportado pelo connector, com imagens estáticas, abrir artigo, seleção de fontes, filtros main/source e busca local. Não inclui novos protocolos, conta/sync remoto, recomendação por ML, player de áudio/vídeo ou catálogo remoto com backend.

Catálogo de release: arquivo confiável versionado e importado para SQLite, com IDs estáveis, provider, nome, idioma/categoria e endpoint. O conteúdo definitivo do catálogo exige curadoria de endpoints; não inventar uma lista grande nem validar fontes apenas pelo número. Preferências do usuário são persistidas e não alteram autoridade por observações externas.

Política editorial inicial: elegibilidade por fontes habilitadas/contexto, disponibilidade canônica e conteúdo legível; recência como sinal verificável e diversidade de providers como regra suave. Não criar score de qualidade sem dados que o sustentem. Se apenas um provider estiver disponível, permitir conteúdo útil.

Mídia ausente antes da publicação: publicar texto quando isso evita bloquear a primeira apresentação e o orçamento de preparação terminou. Mídia tardia serve publicações futuras, sem reescrever a ocorrência atual. Asset de imagem previamente publicada ausente: placeholder com a geometria congelada e erro de integridade separado.

Abastecimento parado: ausência de movimento não prova reserva suficiente. Fazer preparação inicial prospectiva com capacidade finita; adaptar a meta após medidas reais. Um teto operacional não é a definição de saudável. Quando não há progresso, encerrar a oportunidade e aguardar mudança relevante ou deadline do planner.

## 5. Sequência e dependências

| Entrega | Tarefas | Depende de | Saída verificável |
|---|---|---|---|
| Base | T1 | — | Baseline e trabalho local preservado |
| Mídia | T2–T4 | T1 | Imagem adquirida, publicada e exibida localmente |
| Continuidade | T5–T6 | T1; integrar mídia de T3 | Preparação sem scroll e Cold recuperável |
| Catálogo | T7 | T1 | Fontes e preferências duráveis |
| Geometria/recursos | T8 | T4–T5 | Política informada por fatos visuais e device |
| Editorial | T9 | T7 | Seleção determinística diversificada |
| Contextos | T10 | T6–T7–T9 | Troca e reutilização compatível |
| UI e operação | T11 | T4–T6–T10 | Leitor utilizável e estados claros |
| Release | T12 | Todas | Evidência integrada e decisão de release |

Implementar sequencialmente em incrementos pequenos. Cada tarefa tem ciclo red/green, commit com escopo explícito e revisão do diff. T1 é preservação/diagnóstico, não requer teste artificial. Cada entrega deve atualizar sua documentação arquitetural e IOS_RUN com resultados reais, sem copiar contagens históricas.

## 6. Tarefas de implementação

### T1 — Preservação e baseline

**Files:** alterações locais de Media acima; `Package.resolved`, `.gitignore`, `docs/IOS_RUN.md`. Não alterar regras de ignore sem conferir o padrão atual.

**Interfaces:** nenhuma mudança de produção. Produz inventário do diff e relatório de baseline utilizável pelas demais tarefas.

- [ ] Registrar HEAD, status, diffs rastreados e cópia dos arquivos não rastreados necessários em diretório de evidência fora do repo. Não usar reset/clean/stash indiscriminado.
- [ ] Ler alterações 3R11-A e testes; distinguir implementação, artefatos de build e lockfile. Preservar o trabalho antes de criar worktree: novo worktree não copia alterações locais.
- [ ] Executar `swift package describe`, `swift build`, `swift test` e build iOS nos comandos da seção 8. Registrar resultados e falhas ambientais separadamente.
- [ ] Se houver falha, reproduzir e diagnosticar antes de expandir escopo. Não excluir teste para obter baseline verde.
- [ ] Criar branch `codex/feedmine-v2-product-closure` somente na execução, a partir de base preservada; salvar o incremento local revisado em commit específico. Não commit automático de `.build/` nem de arquivos sem revisão.

**Aceite:** todo trabalho local recuperável e baseline documentado; nenhuma alegação de prontidão.

### T2 — Finalizar mídia 3R11-A: transporte e asset durável

**Files:** modificar `Sources/FeedMineMedia/{MediaAcquisition,MediaPolicy,MediaResolver,ImageMaterializer,AssetStore}.swift`; testar `Tests/FeedMineMediaTests/{MediaAcquisitionTests,MediaPreparationTests,AssetStoreTests}.swift`.

**Interfaces:** preservar `MediaAcquisition.acquire(_ resolved: ResolvedMediaCandidate) async throws -> MediaAcquisitionResult`, `MediaPreparation.prepare(candidate:input:)` e `ImageMaterializer.bytes(for:)`. Consome a mesma URLSession do RSS, sem outro transporte normal.

- [ ] Adicionar regressões para cancelamento antes/durante request, redirects proibidos, body sem Content-Length acima do limite, HTTP não 2xx, MIME declarado divergente, truncamento e dimensões enormes. Verificar zero asset utilizável após falha.
- [ ] Rodar `swift test --filter FeedMineMediaTests` e registrar falha nova antes de corrigir.
- [ ] Concluir revisão da implementação local: validação de destino a cada redirect, limite durante streaming, continuação resolvida uma vez, inspeção dos bytes e escrita durável. Definir limite explícito de pixels antes de decode na futura projeção.
- [ ] Testar reopen com bytes exatos, key por conteúdo, ausência/corrupção, falha de escrita/sync e idempotência. Documentar limite de evidência de peer/DNS sem prometer proteção que URLSession não comprova.
- [ ] Rodar suíte de mídia e regressão afetada; commit isolado `feat: complete bounded durable image acquisition`.

**Aceite:** aquisição limitada e cancelável; usable implica asset local durável; falhas de integridade continuam tipadas.

### T3 — Conectar preparação antecipada à publicação

**Files:** criar `Sources/FeedMineComposition/SelectedPublicationPreparation.swift`; modificar `FeedRunwayDriver.swift`, `ColdFeedBootstrap.swift`, `Sources/FeedMineRuntime/{LocalProductionSlice,InitialProductionSlice}.swift`, `FeedMineApp/FeedMineApp/AppComposition.swift`; testes novos `Tests/FeedMineCompositionTests/SelectedPublicationPreparationTests.swift`, existentes Cold/Driver; `Package.swift` apenas se os testes exigirem import Media.

**Interfaces propostas:** `SelectedPublicationPreparation.prepare(_ selection: SelectionResult) async throws -> LocalPreparedPublication`. O closure de preparação em Cold/Driver recebe assinatura assíncrona equivalente. Separar seleção e commit nos slices existentes para que nenhum await ocorra em transação SQLite. O coordinator de Publication conserva a validação selection/draft e a autoridade de commit.

- [ ] Criar testes com candidatos de revisões exatas, imagem válida, ausência, erro de transporte, corrupção e mídia de outra revisão. Verificar draft image somente com usable; textOnly quando orçamento visual termina; erros estruturais não mascarados.
- [ ] Rodar `swift test --filter SelectedPublicationPreparationTests`, comprovar falha.
- [ ] Ler `ContentStore.mediaCandidates(originRevisionID:)` por revisão selecionada; escolha determinística na ordem admitida. Limitar tentativas, bytes, duração e concorrência por oportunidade, fornecidos explicitamente pela composição.
- [ ] Integrar await antes do commit, revalidar escopo/cancelamento depois dele e manter os fences atuais. Reutilizar resultado local durante a oportunidade; não criar pipeline/scheduler de mídia paralelo.
- [ ] Preencher proveniência/nome/ação somente a partir de fatos canônicos e catálogo confiável. Não publicar nil indiscriminadamente nem consultar a revisão atual no lugar da selecionada.
- [ ] Testar atraso de mídia com contexto aposentado, falha parcial e texto já publicado seguido de mídia tardia: nenhuma alteração histórica/duplicação. Rodar testes Cold/Driver/Publication; commit `feat: prepare selected media before immutable publication`.

**Aceite:** app produz imagem local real; primeira apresentação pode progredir com texto; latência de mídia entra no custo de reposição.

### T4 — Projeção e renderização local de imagem

**Files:** modificar `Sources/FeedMineRuntime/{PresentationCard,FeedPresentationSnapshot,FeedSessionUI}.swift`, `Sources/FeedMineUI/{FeedCardView,FeedScreenStore,FeedScreen}.swift`; criar `Sources/FeedMineRuntime/LocalImageProjection.swift`; testar `Tests/FeedMineRuntimeTests/PresentationProjectionTests.swift`, `FeedMineApp/FeedMineAppTests/FeedMineUITests.swift`.

**Interfaces propostas:** valor `PresentationImage` contendo representação local preparada e estado disponível/indisponível, sem URL remota, exposto por `PresentationCard.image`. `LocalImageProjection` lê por PublishedMediaKey e produz decode/downsample limitado fora da main thread. Bytes/decode não passam a alterar identidade ou ordem editorial. Definir representação Sendable compatível com Swift 6 antes de adicioná-la à projeção; se for preciso cache, usar somente um cache de decode limitado, distinto da autoridade durável.

- [ ] Testar layout/aspect congelados, reopen com zero HTTP, asset ausente/corrompido, limite de pixels e descarte ao mudar janela.
- [ ] Rodar testes de projeção e comprovar falha nova.
- [ ] Materializar somente a janela necessária; aplicar resultado apenas se card/key/escopo ainda coincidem. Preservar provenance e anchor ao atualizar disponibilidade visual.
- [ ] Renderizar hero/thumbnail e placeholder determinístico com espaço estável; impedir decode grande no body. Não usar AsyncImage remoto.
- [ ] Testar scroll/Dynamic Type/orientação sem falsa observação de movimento e relaunch offline com imagem. Rodar teste iOS; commit `feat: render bounded local card images`.

**Aceite:** cards visuais funcionam sem rede; decode e memória limitados pela janela, sem deslocamento inesperado do anchor.

### T5 — Política prospectiva e continuação causal

**Files:** modificar `Sources/FeedMineRuntime/{RunwayPolicy,RunwayController}.swift`, `Sources/FeedMineComposition/{FeedRunwayDriver,RunwayAcquisitionCycle}.swift`; testes existentes RunwayPolicy/Controller/Driver/AcquisitionCycle.

**Interfaces:** ampliar fatos existentes com estado de preparação prospectiva e orçamento da oportunidade, sem outra autoridade. `FeedRunwayDriver.drive(resources:)` permanece entrada única. Política distingue cobertura saudável comprovada, desconhecida, preparo inicial e bloqueio real.

- [ ] Criar testes `stationaryActivationBuildsProspectiveReserve`, `zeroRateDoesNotProveHealthy`, `completionReconsidersWithoutViewport`, `noProgressSettlesWithoutSpin`, `reentrantDriveDoesNotDuplicateHTTP`.
- [ ] Rodar filtros RunwayPolicy/FeedRunwayDriver e registrar falhas.
- [ ] Introduzir bootstrap prospectivo limitado quando consumo/latência são desconhecidos. Não inventar taxa de leitura como medida; usar limite operacional explicitamente identificado, calibrável após T12.
- [ ] Reconsiderar após publicação, aquisição/admission, preparação, mudança de recursos e ativação. Preservar `causalExecution`, coalescência e fences de Edition/contexto.
- [ ] Encerrar quando meta satisfeita, orçamento esgotado, fontes inelegíveis ou ausência de progresso. Considerar receipts/cursor/novos origins/publicações, não apenas sucesso HTTP, como evidência de progresso.
- [ ] Não retentar deferred repetidamente no drain. Reativar por mudança de disponibilidade/recursos ou deadline real do planner, sem ticker periódico. Cancelar espera quando escopo é encerrado.
- [ ] Testar 304, payload repetido, rede ruim, resourceDenied, contexto trocado e background em voo. Rodar regressão; commit `fix: sustain proactive bounded runway production`.

**Aceite:** após primeiros cards, reserva cresce sem gesto enquanto útil; nenhuma aquisição simultânea duplicada ou loop sem progresso.

### T6 — Cold start com continuação e estados recuperáveis

**Files:** modificar `ColdFeedBootstrap.swift`, `FeedPresentationHandoff.swift`, `FeedMineApp/FeedMineApp/AppComposition.swift`, `Sources/FeedMineUI/{FeedLoadingView,FeedPresentationState}.swift`; testes Cold/Composition e iOS CompositionTests.

**Interfaces propostas:** `ColdFeedBootstrapContinuation` preserva identidade da primeira Edition e progresso local finito entre oportunidades; `run` passa a devolver outcome e continuação quando necessário. Esse valor pertence ao fluxo Cold existente, não a outro scheduler. Quando houver apresentação, handoff definitivo ao mesmo Driver.

- [ ] Testar banco vazio com primeira oportunidade sem publicação e segunda suficiente; localWorkRemaining com cursor; deferred seguido de disponibilidade; sem fontes; todas falhando; cancelamento.
- [ ] Comprovar falhas nos testes Cold.
- [ ] Manter identidade/cursor do trabalho incompleto, continuar ao terminar trabalho útil ou ao receber evento legítimo; não gerar Edition diferente a cada tentativa.
- [ ] Exibir preparando/aguardando rede/sem fontes/sem conteúdo/falha recuperável com retry explícito somente nos casos realmente bloqueados. Relatar progresso observado, sem percentual inventado.
- [ ] Provar tela aberta chega ao primeiro feed sem foreground/scroll quando supply se torna disponível. Rodar Cold e app; commit `fix: resume cold bootstrap from meaningful progress`.

**Aceite:** ausência temporária não vira beco sem saída; bloqueios reais são claros e não geram busy loop.

### T7 — Catálogo e preferências duráveis

**Files:** criar `Sources/FeedMineDomain/SourceCatalog.swift`, `Sources/FeedMinePersistence/SourceCatalogStore.swift`, `Sources/FeedMineComposition/SourceCatalogConfiguration.swift`, `FeedMineApp/FeedMineApp/Resources/SourceCatalog.json`; modificar `RuntimeMigrations.swift`, `TrustedFeeds.swift`, `AppComposition.swift`, projeto Xcode para resource; criar testes CatalogStore/CatalogConfiguration.

**Interfaces propostas:** `SourceCatalogStore.importCatalog(_:)`, `setEnabled(_:sourceID:)`, `snapshot()`. Snapshot contém geração do catálogo, versão de preferências e fontes selecionadas. IDs tipados existentes para Source/Provider/Target/Binding. Configuração de endpoints permanece Composition/Acquisition, nunca FeedContext.

- [ ] Testar import idempotente, IDs duplicados, endpoint inválido, update de metadados, preferências preservadas, remoção/revogação e migração de banco anterior.
- [ ] Provar falhas novas antes de implementar.
- [ ] Criar migração aditiva para catálogo/preferências e import transacional. Migrar os dois IDs BBC existentes sem duplicar targets/origins. Ausência de fonte nova não apaga histórico.
- [ ] Conciliar registro/reconfigure com `AcquisitionTargetAuthority`; snapshots immutable do connector mudam apenas por configuração confiável. Compartilhar coordinator na aplicação.
- [ ] Substituir default de desenvolvimento por catálogo versionado; manter conjunto pequeno apenas em testes. Validar endpoints por integração externa separada e registrar data/resultado antes do release.
- [ ] Testar fairness e falha de um target sem bloquear demais, usando 100/1.000 targets sintéticos. Nenhum download de todos por launch. Commit `feat: persist source catalog and user selection`.

**Aceite:** catálogo extensível e seleção persistida, volume de trabalho limitado e IDs históricos preservados.

### T8 — Geometria e recursos reais

**Files:** modificar `Sources/FeedMineRuntime/{ViewportObservation,RunwayPolicy,RunwayController}.swift`, `Sources/FeedMineUI/FeedScreen.swift`, `AppComposition.swift`; criar `Sources/FeedMineComposition/FeedResourcePolicy.swift`; testes Viewport/Runway e UI nativa.

**Interfaces propostas:** adicionar `ViewportCoverageFacts` opcionais: distância restante materializada e velocidade visual observadas no mesmo escopo/janela. `FeedResourcePolicy` produz recursos Cold/Driver a partir de lifecycle, conectividade, low power, thermal e pressão de memória; não executa produção.

- [ ] Testar 16 cards curtos/longos com fatos visuais diferentes; viewport desconhecido não equivale a exaustão; medida antiga/resize inválida; consumo parado ainda permite preparo prospectivo.
- [ ] Rodar testes e registrar falha.
- [ ] Usar geometria como sinal complementar: janela local finita não comprova tail durável. Não estimar pixel-height de toda reserva não materializada como se fosse medido.
- [ ] Aplicar budgets por evento do device, reduzir decode/concorrência sob pressão e pausar trabalho novo em background conforme limites iOS. Checkpoint local sempre; não prometer execução contínua com app suspenso.
- [ ] Se background refresh for incluído, integrar `BackgroundFeedRefresh.swift` e o mesmo pipeline sob autorização do OS, com expiration/cancelamento, sem segundo executor. Não torná-lo necessário para continuidade em foreground.
- [ ] Testar resume e ausência de burst após foreground; commit `feat: adapt runway to visual and device resource facts`.

**Aceite:** recursos e fatos visuais influenciam decisões sem violar a distinção janela/reserva ou inventar medidas.

### T9 — Seleção editorial de produção

**Files:** modificar `Sources/FeedMineEditorial/{EditorialPolicy,SelectionEngine,CandidateProvider}.swift`, `Sources/FeedMineDomain/FeedPlan.swift`, `AppComposition.swift`; criar `Sources/FeedMineComposition/EditorialPolicyResolution.swift`; testes Editorial e ArchitectureSmoke.

**Interfaces propostas:** `EditorialPolicyResolution.resolve(context:catalog:) -> (EditorialRevision, ResolvedSelectionPolicy)`. Identidade/versionamento inclui catálogo e preferências efetivos. Ampliar enums da política apenas com comportamentos implementados/testados.

- [ ] Testar fontes habilitadas, source context, busca local, disponibilidade removida/revogada, texto vazio e empate determinístico.
- [ ] Testar distribuição com providers abundantes/desbalanceados/único; diversidade é suave, não pode esvaziar feed válido.
- [ ] Comprovar falhas e implementar elegibilidade antes de score/sequência. Usar recência e interleaving determinístico por provider; desempate por identidade e seed existente.
- [ ] Resolver diversidade com histórico recente limitado da Edition para não reiniciar a distribuição a cada segmento; query bounded, sem estado paralelo de exposição.
- [ ] Versionar alteração de política. Nova configuração produz trabalho futuro compatível; não reordenar segmentos já publicados.
- [ ] Testar quotas de examinação/cursor e exclusão por origin na Edition. Rodar Editorial/Publication/ArchitectureSmoke; commit `feat: resolve deterministic diverse editorial policy`.

**Aceite:** política real, reprodutível, com diversidade observável e comportamento útil sob supply limitado.

### T10 — Contextos e reutilização de Editions

**Files:** criar `Sources/FeedMineComposition/FeedContextCoordinator.swift`; modificar `AppComposition.swift`, `Sources/FeedMinePersistence/{SessionStore,PublicationStore}.swift`, `Sources/FeedMinePublication/PublicationHistory.swift`, `Sources/FeedMineRuntime/FeedSession.swift`, `FeedPresentationHandoff.swift`; testes ContextCoordinator/restore/iOS CompositionTests.

**Interfaces propostas:** `FeedContextCoordinator.activate(_ request: FeedContextRequest) async throws -> FeedPresentationSnapshot?`. Mantém uma associação ativa de apresentação; snapshots/cursors dos contextos ficam duráveis. `PublicationHistory.restoreCompatible(contextKey:editorialRevision:backwardCapacity:forwardCapacity:)` busca Edition compatível explicitamente, sem restore global ambíguo.

- [ ] Testar A→B→A, retorno offline, cursor anterior, mesmo contexto com preferências mudadas, ausência de Edition compatível e HTTP atrasado de A.
- [ ] Rodar testes novos e provar falha.
- [ ] Definir compatibilidade por ContextKey, EditorialRevision e publication schema; mesma chave não basta. Preservar Edition antiga quando contexto muda, mas impedir restore sob política incompatível.
- [ ] Checkpoint/deactivate associação anterior, priorizar destino e restaurar local antes de produzir. Se criar nova Session, criar novo Store e sequência; não instalar no Store anterior.
- [ ] Reutilizar banco, transport e AcquisitionCoordinator no escopo da aplicação. Drivers por associação não viram executores concorrentes: apenas associação ativa inicia trabalho; trabalho canônico em voo conserva sua autoridade/fences.
- [ ] Persistir último contexto e posição; evitar cache de associações ilimitado. Testar 100 trocas com cardinalidade de objetos vivos limitada. Commit `feat: restore compatible feed contexts without discarding history`.

**Aceite:** volta a contexto válido é local, sem reconstrução ou perda de posição; callbacks antigos não contaminam destino.

### T11 — Fechar interface e operação local

**Files:** modificar `Sources/FeedMineUI/{FeedScreen,FeedCardView,FeedLoadingView,FeedScreenStore}.swift`, `Sources/FeedMineRuntime/{InteractionCoordinator,FeedSessionUI}.swift`, `AppComposition.swift`; criar `FeedMineApp/FeedMineApp/SourceSelectionView.swift`; testes iOS Composition/UITests.

**Interfaces:** ações UI enviam PublicationCardID ao InteractionCoordinator; target resolvido a partir da publicação congelada, entregue ao handler de abertura da aplicação. Controles de contexto/preferências passam por T7/T10, sem acesso a banco na View.

- [ ] Testar abrir artigo válido, card sem ação, URL rejeitada, source toggle persistente, busca vazia/sem resultados, retry recuperável e offline com histórico navegável.
- [ ] Comprovar falhas e implementar abrir artigo, seleção de fontes, main/source/search e feedback de estados. Falha de reposição não substitui feed já disponível por tela vazia.
- [ ] Conferir VoiceOver, Dynamic Type máximo, contraste, landscape, touch targets e títulos extensos. Texto canônico normalizado permanece responsabilidade de CandidateProvider.
- [ ] Instrumentar eventos úteis: causa de oportunidade, custo de reposição, resultado de mídia, readyAhead, orçamento e motivo de parada. Não logar payloads/URLs sensíveis indiscriminadamente.
- [ ] Definir retenção conservadora: nesta entrega não evictar assets referenciados pelo histórico restaurável. Medir crescimento e impor limite a novas preparações; garbage collection só após consulta autoritativa de referências e política explícita, em incremento próprio se necessário.
- [ ] Rodar UI/integridade e commit `feat: complete local reader controls and recovery states`.

**Aceite:** leitura, abertura, filtro e recuperação utilizáveis; imagens/persistência não crescem sem controle de novas admissões.

### T12 — Integração, desempenho e gate de release

**Files:** criar `Tests/FeedMineCompositionTests/ContinuousFeedIntegrationTests.swift`; ampliar `FeedMineApp/FeedMineAppTests/{CompositionTests,FeedMineUITests}.swift`; criar `docs/reviews/FEEDMINE_V2_RELEASE_EVIDENCE.md`; atualizar IOS_RUN e IMPLEMENTATION_ORDER.

**Interfaces:** harness de testes usa clock controlado, transporte controlado e banco real em diretório temporário. Dublês somente nos testes. A prova de gesto nativo não chama submitViewport diretamente.

- [ ] Criar testes integrados: cold→primeiro conteúdo→reserva sem gesto; scroll longo com reposição; fontes lentas/304/falhas; mídia lenta; offline/reopen; A→B→A; stale callback; cancelamento/resourceDenied; migração de base anterior.
- [ ] Validar 30 minutos de consumo simulado e 100 trocas de contexto sem duplicação de origins por Edition, alterações históricas ou crescimento de tasks pendentes. Testes determinísticos não exigem rede pública.
- [ ] Rodar regressão completa, build/test iOS serial e smoke de feeds reais separado. Registrar `.xcresult`, screenshots, logs e queries read-only com mesmas Edition/origins/cursors.
- [ ] Medir em iPhone físico release: scroll 30 minutos, leitura parada 10 minutos, background/foreground, offline e mídia heterogênea. Registrar dispositivo/OS, RSS, assets, memória, CPU, energia, tempo de primeira apresentação e latência p95 de reposição.
- [ ] Critérios funcionais obrigatórios: reserva cresce parada quando supply/budget permitem; sem spin sem progresso; restore antes de request; nenhum fetch no renderer; contexto antigo não instala; zero ocorrência duplicada; texto continua útil quando mídia falha.
- [ ] Critérios iniciais de performance propostos: nenhum hitch de trabalho de rede/decode na main thread; imagens limitadas à janela e cache configurado; memória residente sem crescimento monotônico nas últimas 20 das 30 min. Meta de warm restore p95 ≤ 1 s em dispositivo de referência, excluindo launch do OS. Registrar resultados; alterar metas somente por decisão documentada, não para ocultar falha.
- [ ] Fazer revisão final do branch/diff e migrações, sem refatoração de escopo aberto. Revisão independente somente se autorizada. Commit de evidência e PR de cada entrega; integração/release exigem decisão posterior.

**Aceite:** todas as entregas verdes e relatório reproduzível. Falha funcional bloqueia release. Métrica sem medição continua pendente, não aprovada.

## 7. Matriz de cobertura do relatório

| Achado | Correção | Prova |
|---|---|---|
| P0 abastecimento sem autonomia | T5/T8 | Reserva parada; eventos; no-progress; recursos |
| P0 duas fontes fixas | T7/T9 | Catálogo persistido, fairness, diversidade |
| P0 mídia não chega ao card | T2/T3/T4 | Download→asset→draft→reopen→imagem sem HTTP |
| P1 Cold sem continuação | T6 | Primeira oportunidade insuficiente; segunda automática |
| P1 editorial provisório | T9 | Elegibilidade, interleaving, versionamento |
| P1 geometria/capacidade | T4/T8 | Alturas variáveis; janela != reserva; resize |
| P1 filtros/contextos | T10/T11 | A→B→A offline, compatibilidade, cursor |
| Concorrência e apresentação | T3/T5/T10/T12 | HTTP suspenso + nova projeção + callback antigo |
| Offline/energia/memória/escala | T7/T8/T11/T12 | Restore, budgets, cardinalidade e profiling |

## 8. Comandos e evidências

Na raiz do repositório, executar filtros da tarefa antes da regressão:

```sh
swift package describe
swift build
swift test --filter FeedMineMediaTests
swift test --filter RunwayPolicyTests
swift test --filter FeedRunwayDriverTests
swift test --filter ColdFeedBootstrapTests
swift test
xcrun simctl list devices available
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -showdestinations
```

Escolher um simulador disponível iOS 18+ pelo resultado acima, sem reutilizar cegamente UUID histórico:

```sh
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=<UUID confirmado>' -derivedDataPath /tmp/feedmine-v2-closure-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=<UUID confirmado>' -derivedDataPath /tmp/feedmine-v2-closure-derived -resultBundlePath /tmp/feedmine-v2-closure-<entrega>.xcresult -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
git diff --check
```

Os placeholders dos comandos são valores ambientais que devem ser substituídos após descoberta, não requisitos de produto pendentes. Usar resultBundlePath novo por execução. Armazenar artefatos fora do repo; versionar o relatório com comandos, resultados e caminhos de evidência. Testes de protocolo devem usar fixtures aceitas e falhas controladas; indisponibilidade de BBC não invalida o teste determinístico nem pode ser ignorada no smoke externo.

## 9. Riscos e decisões antes da implementação correspondente

- **Preparação assíncrona:** maior mudança de interface. Separar await de transação/commit e testar stale scope antes de expandir catálogo.
- **Representação visual Sendable:** fechar contrato de decode/projeção em T4 com compilação Swift 6; nenhuma dependência UI→Media/Persistence para facilitar render.
- **Catálogo:** lista final e metadados são curadoria, não algoritmo. T7 entrega capacidade; T12 exige fontes reais validadas e diversidade observada.
- **Busca:** baseline local por título/summary, com escopo canônico limitado e paginação por cursor. Sem busca remota ou promessa de indexação global. Otimizar query/index somente após plano de execução e medição.
- **Retenção:** histórico e assets são autoridades distintas. Eviction sem referências autoritativas quebra offline; começar com limites de novo trabalho, medir, e não declarar armazenamento indefinidamente resolvido.
- **Suspensão iOS:** nenhuma política mantém app executando contra o OS. Continuidade prometida em foreground; background é oportunidade concedida, com checkpoint/expiration.
- **Cronograma:** não estimar dias antes do baseline e do gate T3/T4. Replanejar por evidência ao fim de cada entrega; não abrir novas fases de arquitetura sem necessidade concreta.

## 10. Critério final e handoff

Este plano está completo como proposta de correção e implementação, não como certificação de release. A implementação começa por T1 e fecha entregas na ordem da seção 5. Revisar novas decisões de contrato com o usuário antes de implementá-las, apresentando alterações concretas da entrega, sem pedir autorização para cada rotina já incluída no escopo aprovado.

Release exige: gates funcionais T1–T12, suites/package/app verdes, migrações preservadas, testes de gesto real, evidência offline/mídia/contextos, profiling físico e revisão final sem bloqueadores. Não basta somar testes unitários ou confirmar que existem módulos.

Autorrevisão do plano: todos os P0/P1 mapeados; cinco riscos do Review Focus atribuídos a testes; mídia async antes de commit; janela distinta de reserva; catálogo distinto de autoridade; política e Edition versionadas; nenhum owner paralelo ou timer periódico; limites e metas propostas identificados como decisões novas.
