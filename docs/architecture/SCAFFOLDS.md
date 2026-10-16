# Scaffolds arquiteturais removidos (2026-10-15)

> **O que foi removido.** Oito arquivos `.swift` que continham **somente comentários**: 322 linhas
> somadas, **zero declarações** (nenhum `struct`, `class`, `enum`, `protocol`, `extension`, `actor`,
> `func`, `let`, `var` ou `typealias`) e zero linhas não-comentário/não-vazia. Nenhum produto, alvo,
> teste ou outro arquivo de código os referenciava.
>
> **Como eles eram compilados.** Não eram membros declarados de nada: os alvos SwiftPM descobrem
> fontes pelo diretório (`Sources/<Módulo>/`), e o `FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj`
> — mantido à mão, um objeto por linha — **nunca os listou** (nem como `PBXFileReference`, nem como
> `PBXBuildFile`, nem em `children` de grupo, nem em `PBXSourcesBuildPhase`). Removê-los não exigiu
> nenhuma edição de projeto.
>
> **Por que este documento existe.** O texto desses arquivos registrava intenção arquitetural: qual
> fronteira alguém pretendia construir e sob quais invariantes. A informação é útil; o arquivo que
> continha apenas ela, não. As seções abaixo preservam esse texto, **citado literalmente dos arquivos
> removidos**, um por arquivo, dizendo o que a fronteira deveria ser owner e que **nunca foi
> implementada**.
>
> **Conceito não é compromisso.** Nada aqui promete implementação. Cada seção declara que a fronteira
> não foi implementada e que nenhum tipo com aquele nome existe no código hoje.

## Sumário

| Arquivo removido | Módulo | Linhas | Intenção registrada |
| --- | --- | --- | --- |
| `FeedMineBootstrap.swift` | FeedMineComposition | 48 | Construir o object graph inicial em ordem explícita |
| `FeedMineEnvironment.swift` | FeedMineComposition | 34 | Composição explícita das dependências do aplicativo |
| `InteractionOffer.swift` | FeedMineDomain | 45 | Ações semanticamente disponíveis para um item |
| `FeedPlanResolver.swift` | FeedMineEditorial | 32 | Converter `FeedContext` + política do usuário em `FeedPlan` |
| `FeedSessionEffects.swift` | FeedMineRuntime | 42 | Efeitos que o reducer pode solicitar |
| `FeedSessionReducer.swift` | FeedMineRuntime | 41 | Transição pura `state + event → new state + effects` |
| `FeedSessionUI.swift` | FeedMineRuntime | 46 | Boundary mínima consumível pela camada UI |
| `InteractionCoordinator.swift` | FeedMineRuntime | 34 | Executar semanticamente ações de `InteractionOffer` |

Total: **322 linhas**, todas comentário.

## FeedMineBootstrap.swift (FeedMineComposition, 48 linhas)

**Intenção.** Construir o object graph inicial em ordem explícita. Texto original:

> Responsibility: Construir o object graph inicial em ordem explícita.
>
> Owns: Future ownership: Ordered construction: database, stores, connector, acquisition, editorial,
> media, publication, session, screen store.
>
> Does not own: Product logic or service execution.
>
> Allowed dependencies: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineSyndication,
> FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineUI. No imports are
> necessary in this scaffold.
>
> Architectural invariants: INV-12, INV-14; Bootstrap constructs the one object graph.
>
> Planned public surface: Ordered construction: database, stores, connector, acquisition, editorial,
> media, publication, session, screen store. Documentation only; no API is declared in this phase.
>
> Status: Architecture scaffold only. Production behavior is intentionally absent.

Notas de especificação do próprio arquivo: o exemplo conceitual futuro era
`database → stores → connector → acquisition → editorial → media → publication → runtime/session →
screen store`; "Bootstrap cria objetos" e "Bootstrap não contém lógica de produto".

**Removido em 2026-10-15.** Nenhum tipo `FeedMineBootstrap` existe no código. O módulo
`FeedMineComposition` contém as fronteiras implementadas (por exemplo `ColdFeedBootstrap.swift`,
`FeedPresentationHandoff.swift`, `FeedRunwayDriver.swift`) e o alvo de aplicação faz o wiring
concreto em `FeedMineApp/FeedMineApp/AppComposition.swift`.

## FeedMineEnvironment.swift (FeedMineComposition, 34 linhas)

**Intenção.** Representar a composição explícita das dependências necessárias ao aplicativo. Texto
original:

> Responsibility: Representar a composição explícita das dependências necessárias ao aplicativo.
>
> Owns: Future ownership: Explicit application dependency composition through simple initializers.
>
> Does not own: Dynamic containers, global service locators or product policy.
>
> Allowed dependencies: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineSyndication,
> FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineUI. No imports are
> necessary in this scaffold.
>
> Architectural invariants: INV-12, INV-15; Composition is explicit.
>
> Planned public surface: Explicit application dependency composition through simple initializers.
> Documentation only; no API is declared in this phase.
>
> Status: Architecture scaffold only. Production behavior is intentionally absent.

Notas de especificação do próprio arquivo: "Construção simples por initializer." e "Nada de container
dinâmico."

**Removido em 2026-10-15.** Nenhum tipo `FeedMineEnvironment` existe no código. A regra que o arquivo
registrava — composição explícita, sem container dinâmico — continua normativa em
[ARCHITECTURE.md](ARCHITECTURE.md) (seção *Composition root*).

## InteractionOffer.swift (FeedMineDomain, 45 linhas)

**Intenção.** Representar ações semanticamente disponíveis para um item. Texto original:

> Responsibility: Representar ações semanticamente disponíveis para um item.
>
> Owns: Future ownership: open, reply, repost, like, share, play semantic offers.
>
> Does not own: Action execution or SDK-specific action objects.
>
> Allowed dependencies: Swift standard library only; no FeedMine module imports. No imports are
> necessary in this scaffold.
>
> Architectural invariants: INV-13; Offered actions remain protocol-neutral.
>
> Planned public surface: open, reply, repost, like, share, play semantic offers. Documentation only;
> no API is declared in this phase.
>
> Status: Architecture scaffold only. Production behavior is intentionally absent.

Notas de especificação do próprio arquivo: as ofertas futuras seriam `open`, `reply`, `repost`, `like`,
`share`, `play`; o valor "does not execute ações" e "does not contain SDK-specific action objects".

**Removido em 2026-10-15.** Nenhum tipo `InteractionOffer` existe no código. A intenção permanece
apenas como registro: a superfície de ação de card/leitor hoje implementada é outra
(`Sources/FeedMineUI/FeedInteractionPresentation.swift` e os adapters do alvo de aplicação
`PlatformSurfaces.swift` / `InAppBrowser.swift`).

## FeedPlanResolver.swift (FeedMineEditorial, 32 linhas)

**Intenção.** Converter `FeedContext` + política/configuração do usuário em `FeedPlan`. Texto
original:

> Responsibility: Converter `FeedContext` + user policy/configuration em `FeedPlan`.
>
> Owns: Future ownership: Resolution of FeedContext and user policy/configuration into FeedPlan.
>
> Does not own: External system queries or acquisition execution.
>
> Allowed dependencies: FeedMineDomain, FeedMinePersistence. No imports are necessary in this
> scaffold.
>
> Architectural invariants: INV-12, INV-13; Editorial plans are protocol-neutral.
>
> Planned public surface: Resolution of FeedContext and user policy/configuration into FeedPlan.
> Documentation only; no API is declared in this phase.
>
> Status: Architecture scaffold only. Production behavior is intentionally absent.

Notas de especificação do próprio arquivo: "Does not query external systems."

**Removido em 2026-10-15.** Nenhum tipo `FeedPlanResolver` existe no código. A fronteira de resolver
`FeedPlan` junto com um `ResolvedSelectionPolicy` correspondente continua **não implementada**; quem a
cita hoje em [SELECTION_DESIGN.md](SELECTION_DESIGN.md) e
[CONTINUOUS_FEED_RUNWAY_DESIGN.md](CONTINUOUS_FEED_RUNWAY_DESIGN.md) aponta para este documento.

## FeedSessionEffects.swift (FeedMineRuntime, 42 linhas)

**Intenção.** Definir semanticamente os efeitos que o reducer pode solicitar. Texto original:

> Responsibility: Definir semanticamente efeitos que o reducer pode solicitar.
>
> Owns: Future ownership: Semantic restore publication, request publication, report runway demand,
> persist checkpoint and refresh context effects.
>
> Does not own: Connector-specific commands or effect execution.
>
> Allowed dependencies: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial,
> FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
>
> Architectural invariants: INV-13; Effects describe operational intent.
>
> Planned public surface: Semantic restore publication, request publication, report runway demand,
> persist checkpoint and refresh context effects. Documentation only; no API is declared in this
> phase.
>
> Status: Architecture scaffold only. Production behavior is intentionally absent.

Notas de especificação do próprio arquivo: efeitos futuros seriam `restore publication`,
`request publication`, `report runway demand`, `persist checkpoint` e `refresh context`; "Effects
descrevem intenção operacional" e "não devem carregar connector-specific commands".

**Removido em 2026-10-15.** Nenhum tipo `FeedSessionEffects` existe no código; nenhum reducer ou
vocabulário de efeitos foi implementado.

## FeedSessionReducer.swift (FeedMineRuntime, 41 linhas)

**Intenção.** Transição pura de estado, sem I/O. Texto original:

> Responsibility: Pure transition logic:
>
> Owns: Future ownership: Pure state + event to new state + effects transitions.
>
> Does not own: I/O, networking or database execution.
>
> Allowed dependencies: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial,
> FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
>
> Architectural invariants: INV-12; Transitions are pure.
>
> Planned public surface: Pure state + event to new state + effects transitions. Documentation only;
> no API is declared in this phase.
>
> Status: Architecture scaffold only. Production behavior is intentionally absent.

Notas de especificação do próprio arquivo: a transição era
`state + event → new state + effects`, "Sem I/O.", "Sem network.", "Sem database.".

**Removido em 2026-10-15.** Nenhum tipo `FeedSessionReducer` existe no código. O estado de sessão
implementado é `Sources/FeedMineRuntime/FeedSessionState.swift`, consumido diretamente pelo
`FeedSession` (actor) — não há indireção por reducer/efeitos.

## FeedSessionUI.swift (FeedMineRuntime, 46 linhas)

**Intenção.** Boundary mínima consumível pela camada UI. Texto original:

> Responsibility: Boundary mínima consumível pela camada UI.
>
> Owns: Future ownership: Minimal UI boundary for FeedPresentationSnapshot / PresentationCard,
> FeedIntent input and ViewportObservation input.
>
> Does not own: Exposed acquisition, publication or storage internals.
>
> Allowed dependencies: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial,
> FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
>
> Architectural invariants: INV-02, INV-03; UI observes local state and sends semantic input.
>
> Planned public surface: Minimal UI boundary for FeedPresentationSnapshot / PresentationCard,
> FeedIntent input and ViewportObservation input. Documentation only; no API is declared in this
> phase.
>
> Status: Architecture scaffold only. Production behavior is intentionally absent.

Notas de especificação do próprio arquivo: a superfície futura exporia somente presentation
snapshot stream/state, intents e viewport observations, e **não** exporia `PublishedCard`,
`FeedSegment`, `FeedEdition`, `PublicationCoordinator`, `AcquisitionCoordinator` ou stores de
persistência.

**Removido em 2026-10-15.** Nenhum tipo `FeedSessionUI` existe no código. A fronteira UI de fato
implementada é `Sources/FeedMineUI/FeedScreenStore.swift` sobre
`Sources/FeedMineRuntime/FeedPresentationSnapshot.swift` e
`Sources/FeedMineUI/FeedPresentationState.swift`; a UI consome `PresentationCard`, nunca
`PublishedCard`.

## InteractionCoordinator.swift (FeedMineRuntime, 34 linhas)

**Intenção.** Executar semanticamente as ações oferecidas por `InteractionOffer`. Texto original:

> Responsibility: Executar semanticamente ações oferecidas por `InteractionOffer`.
>
> Owns: Future ownership: Semantic execution of InteractionOffer actions through appropriate
> boundaries.
>
> Does not own: Feed production or exposed protocol-specific commands.
>
> Allowed dependencies: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial,
> FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
>
> Architectural invariants: INV-12, INV-13; Interaction stays separate from feed production.
>
> Planned public surface: Semantic execution of InteractionOffer actions through appropriate
> boundaries. Documentation only; no API is declared in this phase.
>
> Status: Architecture scaffold only. Production behavior is intentionally absent.

Notas de especificação do próprio arquivo: "A execução protocol-specific futura deve continuar atrás
de boundaries apropriadas." e "Não misturar interaction com feed production."

**Removido em 2026-10-15.** Nenhum tipo `InteractionCoordinator` existe no código. A execução de ação
do leitor hoje vive em `Sources/FeedMineComposition/ReaderActionCoordinator.swift` e nos adapters do
alvo de aplicação; a separação entre interação e produção de feed continua sendo a regra registrada
acima.

## Menções remanescentes em outros documentos

Estes documentos ainda citam um dos oito nomes. Os que são **registros históricos por fase** foram
deliberadamente preservados (mesma regra aplicada a `docs/reviews/**`): reescrevê-los falsificaria o
registro do que era verdade quando a fase foi concluída.

| Documento | Natureza | Tratamento |
| --- | --- | --- |
| `docs/reviews/**` | revisões e evidências datadas | preservado |
| `docs/architecture/IMPLEMENTATION_ORDER.md` | registros de fase (ex.: "FeedSessionUI / FeedScreenStore wiring — not started") | preservado |
| `docs/architecture/FILE_RESPONSIBILITIES.md` | linhas de tabela (retiradas) e registros de fase no corpo do documento | linha de responsabilidade retirada; registros de fase preservados |
| `docs/architecture/ACQUISITION_DESIGN.md` | registros de fase 3P1/3P2 | preservado |
| `docs/architecture/RUNTIME_PRESENTATION_CONTRACT.md` | §6 lista de "deliberately deferred" e registro da fase 3Q2 | preservado |
| `docs/architecture/MODULE_MAP.md` | mapa de fronteira de módulo que cita `FeedSessionUI` como caminho de consumo | preservado; a fronteira implementada é `FeedScreenStore` (ver acima) |
| `docs/architecture/PERSISTENCE_DISCOVERY.md` | tabela de descoberta sobre persistir a capacidade `InteractionOffer` | preservado: é proposta de design sobre o conceito, não citação de arquivo |
| `docs/product/F26_IOS_SYSTEM_INTEGRATIONS_PRD.md`, `docs/research/**` | PRD e pesquisa citam `InteractionCoordinator`/`InteractionOffer` como conceito | preservado |

Nenhum desses documentos descreve um arquivo existente; todos passam a ter este documento como
referência para o que esses nomes significavam.
