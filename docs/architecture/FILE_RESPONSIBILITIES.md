# File responsibilities

| Module | File | Responsibility | Explicitly does not own |
| --- | --- | --- | --- |
| FeedMineDomain | FeedIdentifiers.swift | Phase 1A implemented: seven nominal UUID IDs for source, provider, origin record/revision, source binding, content entity and cluster. Phase 1B adds EditorialRevisionID; semantic ContextKey belongs to FeedContext.swift. | Endpoint identity, protocol-specific identity or transport-derived ID generation |
| FeedMineDomain | FeedContext.swift | Phase 1B implementation: semantic reusable ContextKey/request and original non-whitespace SearchContext. | Acquisition, network, database, UI navigation or connector metadata |
| FeedMineDomain | FeedIntent.swift | Phase 1B implementation: feed-level changeContext and refresh semantic intentions only. | Intent execution, networking or persistence |
| FeedMineDomain | FeedPlan.swift | Phase 1B implementation: opaque policy/catalog/schema versions, context-bound EditorialRevision and validated context/revision FeedPlan association. | Policy execution, fetching or UI queries |
| FeedMineDomain | Source.swift | Phase 1A implemented: independent Source and Provider; ConnectorKind; declarative SourceBinding with principal-derived connector and consistent aliases; SourceBindingState. | Endpoint identity, acquisition targets or transport execution |
| FeedMineDomain | Content.swift | Phase 1A implemented: opaque ExternalIdentity owning connector kind; OriginRecord deriving that kind; immutable OriginRevision owning optional provider attribution; separate membership, relations, entity and cluster. | FeedKit models, XML, Mastodon models, ATProto records, Nostr events or downstream raw protocol JSON |
| FeedMineDomain | MediaCandidate.swift | Representar evidência/candidatos de mídia associados a conteúdo canônico. | Rendered images, SwiftUI Image, downloaded assets or publication media identity |
| FeedMineDomain | InteractionOffer.swift | Representar ações semanticamente disponíveis para um item. | Action execution or SDK-specific action objects |
| FeedMinePersistence | RuntimeDatabase.swift | Phase 2A implemented: physical runtime.sqlite location/lifecycle, DatabasePool, internal transactions, typed failures and explicit WAL checkpoints. | Domain CRUD/schema, catalog/assets, volatile fallback, retention, backup or retry policies. |
| FeedMinePersistence | RuntimeMigrations.swift | Phase 2A implemented: single non-erasing GRDB migration authority with empty runtime-foundation-v1 bookkeeping. | Domain tables, duplicate schema counters, recovery or database lifecycle. |
| FeedMinePersistence | ContentStore.swift | API concreta futura para persistir/consultar canonical local supply. | Scoring, selection, publication or networking |
| FeedMinePersistence | PublicationStore.swift | Future persistence mechanism for durable publication history; storage mechanics subject to the representation phase gate. | Publication semantics, parallel publication models or an API/storage representation before the gate is resolved. |
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
| FeedMinePublication | PublishedCard.swift | Frozen semantic snapshot of a published card; publication state owned by FeedMinePublication. | UI-facing presentation state, live OriginRecord projections or retrospective upstream changes. |
| FeedMinePublication | RenderContract.swift | Definir quais recursos um PublishedCard precisa garantir para ser apresentável. | Renderer implementation, acquisition or remote resolution |
| FeedMinePublication | FeedEdition.swift | Representar uma sequência/versionamento coerente de publicação para determinado contexto/revision. | Silent rewriting of a published edition |
| FeedMinePublication | FeedSegment.swift | Bloco imutável e ordenado de PublishedCards. | Silent reordering of existing history |
| FeedMinePublication | FeedWindow.swift | Representar uma janela local bounded sobre história publicada. | Acquisition pagination or limits on total feed history |
| FeedMinePublication | PublicationCoordinator.swift | Converter uma sequência editorial preparada + media-ready em novos FeedSegments imutáveis. | Acquisition, protocol parsing, remote media resolution or direct UI updates |
| FeedMineRuntime | FeedSession.swift | Owner de uma sessão de consumo. | SQL, HTTP, SwiftUI or ownership of all feed services |
| FeedMineRuntime | FeedSessionState.swift | Value state completo necessário para reduzir eventos de sessão. | Scattered independent flags, I/O or UI rendering |
| FeedMineRuntime | FeedSessionUI.swift | UI surface for FeedPresentationSnapshot / PresentationCard, FeedIntent input and ViewportObservation input. | PublishedCard, FeedSegment, FeedEdition, publication/acquisition coordinators or persistence stores exposure. |
| FeedMineRuntime | FeedSessionReducer.swift | Pure transition logic: | I/O, networking or database execution |
| FeedMineRuntime | FeedSessionEffects.swift | Definir semanticamente efeitos que o reducer pode solicitar. | Connector-specific commands or effect execution |
| FeedMineRuntime | FeedPresentationSnapshot.swift | Finite UI-facing projection of current local session state containing future PresentationCard values. | Direct PublishedCard exposure to FeedMineUI, network requirements or remote resolution. |
| FeedMineRuntime | PresentationCard.swift | Local, finite, presentation-ready projection of published history for FeedMineUI. | Publication identity/history, second source of truth, selection, acquisition, network, remote media or SwiftUI rendering. |
| FeedMineRuntime | ViewportObservation.swift | Descrever o que o usuário está vendo/consumindo. | loadMore commands or protocol pagination |
| FeedMineRuntime | RunwayPolicy.swift | Política adaptativa que decide o quanto precisamos estar à frente. | Fixed page size or periodic fetch strategies as conceptual runway |
| FeedMineRuntime | RunwayController.swift | Comparar runway disponível com runway desejável e emitir demanda futura. | Direct scroll-to-connector fetching or editorial selection |
| FeedMineRuntime | InteractionCoordinator.swift | Executar semanticamente ações oferecidas por `InteractionOffer`. | Feed production or exposed protocol-specific commands |
| FeedMineRuntime | BackgroundFeedRefresh.swift | Entrada para oportunidades de execução em background. | Secondary background pipeline or visible history mutation |
| FeedMineUI | FeedScreenStore.swift | Future @MainActor bridge receiving FeedPresentationSnapshot / PresentationCard through FeedSessionUI and forwarding semantic input. | Publication model translation, direct PublishedCard consumption or business logic. |
| FeedMineUI | FeedScreen.swift | Root SwiftUI da experiência de feed. | Feed production, database access or network operations |
| FeedMineUI | FeedCardView.swift | Renderizar um PresentationCard já local e presentation-ready. | Direct PublishedCard consumption, FeedMinePublication imports, remote media resolution, network, database, acquisition or connector access. |
| FeedMineUI | FeedLoadingView.swift | Superfície futura de cold/first bootstrap. | Fake progress or execution of bootstrap acquisition |
| FeedMineComposition | FeedMineEnvironment.swift | Representar a composição explícita das dependências necessárias ao aplicativo. | Dynamic containers, global service locators or product policy |
| FeedMineComposition | FeedMineBootstrap.swift | Construir o object graph inicial em ordem explícita. | Product logic or service execution |
| FeedMine package manifest | Package.swift | Declare products and the exact target graph. | Runtime behavior or application composition. |
| ArchitectureSmokeTests | ArchitectureSmokeTests.swift | Import all ten modules to prove the package graph compiles. | Behavior tests, mocks or fixtures. |
