# FeedMine architecture

## Tese central

FeedMine é local-first/offline-first, sem servidor próprio de conteúdo. Sistemas externos repõem supply em runtime. Quando o usuário move o dedo, ele navega conteúdo local já publicado; ele não pilota a internet.

## Canonical pipeline

```text
External Systems
        ↓
Connectors
        ↓
Acquisition
        ↓
Canonical Local Supply
        ↓
Editorial Selection
        ↓
Media Preparation
        ↓
Publication
        ↓
Immutable Feed History
        ↓
Feed Session
        ↓
Presentation Snapshot
        ↓
UI
```

Acquisition adquire evidence externa e coordena admission. Supply é conteúdo canônico durável e consultável localmente, ainda sem promessa de aparecer no feed. Selection escolhe e ordena candidatos dessa supply. Media preparation transforma evidência de mídia em recursos locais que satisfazem o presentation contract. Publication congela essa seleção preparada em história imutável. Session é dona do consumo, restauração, intenções e observações. Presentation é um snapshot finito, local e imediatamente renderizável pela UI.

## Module graph

As arestas abaixo significam dependências diretas de compilação, não fluxo de dados.

```text
FeedMineDomain -> (none)
FeedMinePersistence -> FeedMineDomain
FeedMineAcquisition -> FeedMineDomain, FeedMinePersistence
FeedMineSyndication -> FeedMineDomain, FeedMineAcquisition
FeedMineEditorial -> FeedMineDomain, FeedMinePersistence
FeedMineMedia -> FeedMineDomain, FeedMinePersistence
FeedMinePublication -> FeedMineDomain, FeedMinePersistence, FeedMineEditorial, FeedMineMedia
FeedMineRuntime -> FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication
FeedMineUI -> FeedMineDomain, FeedMineRuntime
FeedMineComposition -> FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineSyndication, FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineUI
```

Há exatamente dez targets de produção e dois targets de testes: ArchitectureSmokeTests e FeedMineDomainTests. Um único Swift Package usa Swift tools 6.0, sem dependências externas. Phase 1A implementa somente os value models canônicos em FeedIdentifiers.swift, Source.swift e Content.swift; os outros arquivos permanecem scaffolds. FeedMineDomain may depend on Swift standard library and Foundation value types. It does not depend on another FeedMine module. Veja [Domain model](DOMAIN_MODEL.md).

## Local presentation and immutable publication

A UI navega uma janela bounded de história publicada; memória limitada não limita a extensão da história. Warm launch restaura publicação e sessão e materializa uma janela local sem esperar rede, refresh de catálogo, download ou nova seleção. Offline usa o melhor estado local disponível. No primeiro launch sem supply suficiente, preparação pode legitimamente levar tempo e deverá mostrar evidência e progresso reais.

PublishedCard é um snapshot congelado, não uma projeção viva de OriginRecord. FeedSegment é ordenado e imutável. Nova acquisition modifica supply e publicação futuras, sem reordenar segmentos antigos. FeedEdition pode ter sucessoras quando a realidade editorial muda. A durabilidade publicada independe de evidence bruta temporária. Background prepara capacidade futura sem perturbar história visível.

## Publication / presentation boundary

```text
Publication
    │
    │ immutable publication semantics
    ▼
PublishedCard
    │
    │ Runtime projection
    ▼
PresentationCard
    │
    ▼
FeedPresentationSnapshot
    │
    ▼
FeedSessionUI
    │
    ▼
FeedScreenStore
    │
    ▼
FeedCardView
```

Publication models are not UI models.

PresentationCard is a projection, not a second source of truth.

PublishedCard permanece estado da história publicada interna e imutável. Runtime projeta esse estado em PresentationCard local, finito e presentation-ready. FeedPresentationSnapshot apresenta esses valores pela superfície FeedSessionUI. A UI conhece PresentationCard, não PublishedCard, e não realiza a tradução. Alterações do ambiente de apresentação podem mudar a projeção sem mudar a história publicada.

## Publication / persistence boundary

FeedMinePublication owns publication semantics: PublishedCard, FeedEdition and FeedSegment.

FeedMinePersistence owns storage mechanics and local durability. Persistence must not create a parallel publication domain.

A representação concreta para armazenar a história publicada permanece intencionalmente não resolvida na Phase 0. Nenhuma API ou representação de PublicationStore pode ser implementada antes da escolha explícita de uma estratégia compatível com as dependências. O [phase gate](DEPENDENCY_RULES.md#publicationpersistence-boundary-gate) proíbe DTOs de publicação, repository protocols, novas arestas e movimentação de modelos entre módulos. Não há mudança no grafo nesta correção.

## Adaptive runway

Scroll emite ViewportObservation, nunca loadMore ou fetchNextPage. RunwayController compara runway publicado, supply local, observação e condições operacionais e emite demanda futura. RunwayPolicy responde a velocidade de consumo, quantidade disponível, custo de acquisition, rede, background, mídia, histórico recente, contexto editorial, memória, energia e capacidade do device. Quantidades podem limitar operação, mas fixed page sizes, timers ou thresholds fixos não definem a estratégia. Após os primeiros cards, preparação continua enquanto houver benefício e orçamento. Mudanças de contexto repriorizam trabalho futuro e preservam trabalho local reutilizável quando válido.

## Confined connectors

FeedConnector pertence a Acquisition. FeedMineSyndication será sua primeira implementação concreta, confinando RSS, Atom, JSON Feed e HTTP específico. A tradução/admission encerra representações específicas de protocolo; Selection, Publication, Session e UI recebem conceitos canônicos. Selection não busca candidatos remotamente: supply insuficiente gera demanda upstream. Publication não resolve mídia remota. A UI consome a superfície Runtime e não importa Publication para renderizar presentation cards.

## Composition root

FeedMineComposition é o único composition root e o único lugar que conhece o conjunto das implementações concretas. FeedMineEnvironment fará composição explícita por initializer. FeedMineBootstrap construirá database → stores → connector → acquisition → editorial → media → publication → runtime/session → screen store. Não existe framework de DI, container dinâmico ou service locator global. Nenhum módulo depende de Composition.

## Clean rewrite and simplicity

Existe apenas FeedMine nos nomes de produção. O projeto histórico não é base arquitetural; nenhum código foi copiado. Não há runtime de compatibilidade, caminhos alternativos ou pipeline de background separado. Cada responsabilidade possui um único owner. Não criar FeedStore, FeedRuntime monolítico, event bus, registries, managers genéricos ou protocols por testability. FeedConnector é a única boundary de protocol autorizada, ainda sem declaração de API nesta phase.

Alarmes de tamanho futuros: FeedSession idealmente < 300 LOC; FeedSessionReducer < 500; SelectionEngine < 400; PublicationCoordinator < 400; RunwayController < 300. São sinais para revisar ownership, não limites mecânicos nem justificativa para divisão artificial.

## Architecture references

- [Product invariants](PRODUCT_INVARIANTS.md)
- [Module map](MODULE_MAP.md)
- [Dependency rules](DEPENDENCY_RULES.md)
- [File responsibilities](FILE_RESPONSIBILITIES.md)
- [Implementation order](IMPLEMENTATION_ORDER.md)
