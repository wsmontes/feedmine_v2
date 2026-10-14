# Module map

> **DOC CORRECTION — mapa de ownership atual (2026-10-10).** Este arquivo descreve limites entre módulos, não progresso de implementação na Phase 1A. `Package.swift` hoje inclui GRDB (Persistence) e FeedKit (Syndication); a frase antiga "no imports" não corresponde ao código. A autoridade editorial do catálogo gerenciado é [wawasoft/feed-repository](https://github.com/wawasoft/feed-repository), mas a leitura de seu snapshot local e a aquisição de conteúdo têm owners distintos ([PD-10](../product/PRODUCT_DECISIONS_2026-10-09.md), [INV-18](PRODUCT_INVARIANTS.md)). Não transformar os status históricos abaixo em novos subsistemas.

## FeedMineDomain

- purpose: Canonical semantic vocabulary. Phase 1A originally established identities/source/content; current Domain contains the subsequently implemented intent, context, plan, media-candidate and reader values as well. Phase labels here are provenance, not a claim that other Domain files remain scaffolds.
- owns: Identifiers, context, intent, plans, sources, content, media evidence, interaction offers; shared conservative readable-text conversion (`ReadablePublicationText`) and the `HTMLNamedEntities` table. K-15 moved both from Editorial to Domain so Syndication and Editorial share one implementation without a forbidden dependency.
- does not own: I/O, persistence, protocol implementations or UI.
- allowed imports: Swift standard library and Foundation value types (UUID, Date, URL); no other FeedMine module.
- downstream consumers: FeedMinePersistence, FeedMineAcquisition, FeedMineSyndication, FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineUI, FeedMineComposition.

## FeedMinePersistence

- purpose: Local durability and queries.
- owns: Storage mechanics and local durability; database lifecycle, schema evolution and content/publication/session storage subject to the publication representation gate.
- does not own: Publication semantics, parallel publication models, networking or editorial decisions.
- allowed imports: FeedMineDomain. Package dependency reality is documented in `Package.swift`; this is a module-boundary map, not a scaffold-status report.
- downstream consumers: FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineComposition.

## FeedMineAcquisition

- purpose: Production and admission of canonical supply.
- owns: Connector boundary, demand planning, bounded bootstrap, admission and acquisition coordination.
- does not own: Publication or editorial ordering.
- allowed imports: FeedMineDomain, FeedMinePersistence. Package dependency reality is documented in `Package.swift`; this is a module-boundary map, not a scaffold-status report.
- downstream consumers: FeedMineSyndication, FeedMineRuntime, FeedMineComposition.

## FeedMineSyndication

- purpose: First concrete external connector.
- owns: RSS/Atom/JSON Feed translation and specific HTTP behavior.
- does not own: Persistence, editorial selection or general HTTP frameworks.
- allowed imports: FeedMineDomain, FeedMineAcquisition. Package dependency reality is documented in `Package.swift`; this is a module-boundary map, not a scaffold-status report.
- downstream consumers: FeedMineComposition.

## FeedMineEditorial

- purpose: Selection for future publication from local supply.
- owns: Plan resolution, candidate retrieval, editorial policy and deterministic selection. Uses Domain's `ReadablePublicationText`; it no longer owns that converter or `HTMLNamedEntities`.
- does not own: Connectors, protocol SDK/JSON, media preparation or publication.
- allowed imports: FeedMineDomain, FeedMinePersistence. Package dependency reality is documented in `Package.swift`; this is a module-boundary map, not a scaffold-status report.
- downstream consumers: FeedMinePublication, FeedMineRuntime, FeedMineComposition.

## FeedMineMedia

- purpose: Local resource preparation.
- owns: Media suitability, choice/quality/cost, assets and image materialization.
- does not own: Publication or SwiftUI rendering.
- allowed imports: FeedMineDomain, FeedMinePersistence. Package dependency reality is documented in `Package.swift`; this is a module-boundary map, not a scaffold-status report.
- downstream consumers: FeedMinePublication, FeedMineRuntime, FeedMineComposition.

## FeedMinePublication

- purpose: Immutable local published history.
- owns: PublishedCard, FeedEdition, FeedSegment and publication semantics; render contracts, windows and publication coordination.
- does not own: Acquisition, protocol parsing or remote media resolution.
- allowed imports: FeedMineDomain, FeedMinePersistence, FeedMineEditorial, FeedMineMedia. Package dependency reality is documented in `Package.swift`; this is a module-boundary map, not a scaffold-status report.
- downstream consumers: FeedMineRuntime, FeedMineComposition.

## FeedMineRuntime

- purpose: Consumption, runway and service coordination.
- owns: Projection from published state to presentation-facing state (PresentationCard); session state/transitions/effects, UI boundary, local snapshots, viewport, adaptive demand, interactions and background entry.
- does not own: SQL, HTTP, concrete connectors, SwiftUI or monolithic feed ownership.
- allowed imports: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication. Package dependency reality is documented in `Package.swift`; this is a module-boundary map, not a scaffold-status report.
- downstream consumers: FeedMineUI, FeedMineComposition.

## FeedMineUI

- purpose: Local presentation and semantic user input.
- consumes: PresentationCard through FeedPresentationSnapshot via FeedSessionUI.
- does not consume: PublishedCard directly.
- owns: Screen bridge, feed/card/loading presentation and input forwarding.
- does not own: Feed production, database, acquisition, selection, remote media or publication.
- allowed imports: FeedMineDomain, FeedMineRuntime. Package dependency reality is documented in `Package.swift`; this is a module-boundary map, not a scaffold-status report.
- downstream consumers: FeedMineComposition.

## FeedMineComposition

- purpose: Only composition root.
- owns: Explicit concrete dependency wiring and ordered object graph construction.
- does not own: Product logic, dynamic DI containers or global service location.
- allowed imports: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineSyndication, FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineUI. Package dependency reality is documented in `Package.swift`; this is a module-boundary map, not a scaffold-status report.
- downstream consumers: Application composition entry only; no FeedMine module.
