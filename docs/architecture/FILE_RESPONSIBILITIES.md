# File responsibilities

| Module | File | Responsibility | Explicitly does not own |
| --- | --- | --- | --- |
| FeedMineDomain | FeedIdentifiers.swift | Definir o local conceitual futuro de identificadores estáveis pertencentes ao domínio FeedMine. | Endpoint identity, protocol-specific identity or transport-derived ID generation |
| FeedMineDomain | FeedContext.swift | Representar o contexto editorial solicitado pelo usuário. | Acquisition, network, database, UI navigation or connector metadata |
| FeedMineDomain | FeedIntent.swift | Representar intenções semânticas emitidas pelo usuário/UI. | Intent execution, networking or persistence |
| FeedMineDomain | FeedPlan.swift | Representar uma política editorial resolvida para um contexto. | Policy execution, fetching or UI queries |
| FeedMineDomain | Source.swift | Definir os conceitos canônicos futuros: | Endpoint identity, acquisition targets or transport execution |
| FeedMineDomain | Content.swift | Local conceitual dos modelos canônicos de conteúdo aceitos após admission. | FeedKit models, XML, Mastodon models, ATProto records, Nostr events or downstream raw protocol JSON |
| FeedMineDomain | MediaCandidate.swift | Representar evidência/candidatos de mídia associados a conteúdo canônico. | Rendered images, SwiftUI Image, downloaded assets or publication media identity |
| FeedMineDomain | InteractionOffer.swift | Representar ações semanticamente disponíveis para um item. | Action execution or SDK-specific action objects |
| FeedMinePersistence | RuntimeDatabase.swift | Futuro owner do database local e lifecycle da conexão. | Database implementation or selection of GRDB, CoreData or SwiftData in this phase |
| FeedMinePersistence | RuntimeMigrations.swift | Local único para evolução versionada do schema persistente futuro. | Current migrations, database lifecycle or product migration runtime |
| FeedMinePersistence | ContentStore.swift | API concreta futura para persistir/consultar canonical local supply. | Scoring, selection, publication or networking |
| FeedMinePersistence | PublicationStore.swift | Durabilidade de história publicada. | Editorial selection, production of segments or network operations |
| FeedMinePersistence | SessionStore.swift | Persistir estado necessário para restauração exata ou semanticamente válida de sessão. | Transient UI state or session transition decisions |
| FeedMineAcquisition | FeedConnector.swift | Boundary protocol entre FeedMine acquisition e implementações de sistemas externos. | Concrete protocol implementation, selection, publication or universal plugin frameworks |
| FeedMineAcquisition | AcquisitionModels.swift | Concentrar os value types pequenos usados por acquisition. | Source identity, protocol SDK models or published cards |
| FeedMineAcquisition | BootstrapPlan.swift | Representar trabalho bounded necessário para produzir supply inicial suficiente quando ainda não há runway utilizável. | Permanent runway strategy or bootstrap UI |
| FeedMineAcquisition | AdmissionPolicy.swift | Definir o gate entre evidence trazida por connector e canonical local supply. | Editorial selection or protocol transport |
| FeedMineAcquisition | AcquisitionPlanner.swift | Converter demanda por supply em trabalho de acquisition priorizado e bounded. | HTTP execution or editorial ordering |
| FeedMineAcquisition | AcquisitionCoordinator.swift | Executar/coordenar acquisition planejada usando `FeedConnector`. | Publication, editorial ordering or direct scroll responses |
| FeedMineSyndication | SyndicationConnector.swift | Implementação futura de `FeedConnector` para feeds de syndication. | Editorial selection, persistence or a general product transport framework |
| FeedMineSyndication | SyndicationTranslator.swift | Traduzir objetos externos de syndication para os modelos canônicos aceitos pela acquisition/admission boundary. | Downstream protocol representations or editorial decisions |
| FeedMineSyndication | SyndicationHTTP.swift | Detalhes HTTP específicos de syndication. | Universal HTTP framework, publication or UI media resolution |
| FeedMineEditorial | FeedPlanResolver.swift | Converter `FeedContext` + user policy/configuration em `FeedPlan`. | External system queries or acquisition execution |
| FeedMineEditorial | Candidate.swift | Representar uma origin/revision elegível sendo considerada para publicação. | PublishedCard snapshots or protocol evidence |
| FeedMineEditorial | CandidateProvider.swift | Consultar local supply para obter candidatos coerentes com `FeedPlan`. | Remote acquisition, protocol parsing or final selection |
| FeedMineEditorial | EditorialPolicy.swift | Local explícito para políticas editoriais puras: | Fetching, publication or renderer behavior |
| FeedMineEditorial | SelectionEngine.swift | Transformar candidatos + FeedPlan + exposure history em sequência editorial determinística futura. | Connector calls, protocol semantics or fetching on insufficient supply |
| FeedMineMedia | MediaPreparation.swift | Coordenar preparação necessária para que conteúdo selecionado cumpra seu presentation contract. | Card publication, selection or SwiftUI rendering |
| FeedMineMedia | MediaResolver.swift | Resolver qual MediaCandidate pode satisfazer a apresentação. | SwiftUI objects, editorial selection or published history |
| FeedMineMedia | MediaPolicy.swift | Regras de escolha/qualidade/custo da mídia. | Renderer behavior, editorial ranking or publication |
| FeedMineMedia | AssetStore.swift | Store futuro de assets locais materializados. | Card publication, UI downloads or content supply queries |
| FeedMineMedia | ImageMaterializer.swift | Future boundary para transformar media bytes/resources em representação local pronta para uso. | SwiftUI render-time work or publication |
| FeedMinePublication | PublishedCard.swift | Snapshot semântico congelado de um card publicado. | Live OriginRecord projections or retrospective upstream changes |
| FeedMinePublication | RenderContract.swift | Definir quais recursos um PublishedCard precisa garantir para ser apresentável. | Renderer implementation, acquisition or remote resolution |
| FeedMinePublication | FeedEdition.swift | Representar uma sequência/versionamento coerente de publicação para determinado contexto/revision. | Silent rewriting of a published edition |
| FeedMinePublication | FeedSegment.swift | Bloco imutável e ordenado de PublishedCards. | Silent reordering of existing history |
| FeedMinePublication | FeedWindow.swift | Representar uma janela local bounded sobre história publicada. | Acquisition pagination or limits on total feed history |
| FeedMinePublication | PublicationCoordinator.swift | Converter uma sequência editorial preparada + media-ready em novos FeedSegments imutáveis. | Acquisition, protocol parsing, remote media resolution or direct UI updates |
| FeedMineRuntime | FeedSession.swift | Owner de uma sessão de consumo. | SQL, HTTP, SwiftUI or ownership of all feed services |
| FeedMineRuntime | FeedSessionState.swift | Value state completo necessário para reduzir eventos de sessão. | Scattered independent flags, I/O or UI rendering |
| FeedMineRuntime | FeedSessionUI.swift | Boundary mínima consumível pela camada UI. | Exposed acquisition, publication or storage internals |
| FeedMineRuntime | FeedSessionReducer.swift | Pure transition logic: | I/O, networking or database execution |
| FeedMineRuntime | FeedSessionEffects.swift | Definir semanticamente efeitos que o reducer pode solicitar. | Connector-specific commands or effect execution |
| FeedMineRuntime | FeedPresentationSnapshot.swift | Snapshot finito e local que a UI pode renderizar imediatamente. | Network requirements or remote resource resolution |
| FeedMineRuntime | ViewportObservation.swift | Descrever o que o usuário está vendo/consumindo. | loadMore commands or protocol pagination |
| FeedMineRuntime | RunwayPolicy.swift | Política adaptativa que decide o quanto precisamos estar à frente. | Fixed page size or periodic fetch strategies as conceptual runway |
| FeedMineRuntime | RunwayController.swift | Comparar runway disponível com runway desejável e emitir demanda futura. | Direct scroll-to-connector fetching or editorial selection |
| FeedMineRuntime | InteractionCoordinator.swift | Executar semanticamente ações oferecidas por `InteractionOffer`. | Feed production or exposed protocol-specific commands |
| FeedMineRuntime | BackgroundFeedRefresh.swift | Entrada para oportunidades de execução em background. | Secondary background pipeline or visible history mutation |
| FeedMineUI | FeedScreenStore.swift | Bridge `@MainActor` futura entre `FeedSessionUI` e SwiftUI. | Business logic, acquisition, publication or persistence |
| FeedMineUI | FeedScreen.swift | Root SwiftUI da experiência de feed. | Feed production, database access or network operations |
| FeedMineUI | FeedCardView.swift | Renderizar um `PublishedCard`/presentation card já pronto. | Image downloads, URL resolution, connectors, SQL or acquisition |
| FeedMineUI | FeedLoadingView.swift | Superfície futura de cold/first bootstrap. | Fake progress or execution of bootstrap acquisition |
| FeedMineComposition | FeedMineEnvironment.swift | Representar a composição explícita das dependências necessárias ao aplicativo. | Dynamic containers, global service locators or product policy |
| FeedMineComposition | FeedMineBootstrap.swift | Construir o object graph inicial em ordem explícita. | Product logic or service execution |
| FeedMine package manifest | Package.swift | Declare products and the exact target graph. | Runtime behavior or application composition. |
| ArchitectureSmokeTests | ArchitectureSmokeTests.swift | Import all ten modules to prove the package graph compiles. | Behavior tests, mocks or fixtures. |
