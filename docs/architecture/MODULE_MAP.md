# Module map

## FeedMineDomain

- purpose: Canonical semantic vocabulary.
- owns: Identifiers, context, intent, plans, sources, content, media evidence, interaction offers.
- does not own: I/O, persistence, protocol implementations or UI.
- allowed imports: Swift standard library only; no other FeedMine module. No imports are used by production scaffolds.
- downstream consumers: FeedMinePersistence, FeedMineAcquisition, FeedMineSyndication, FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineUI, FeedMineComposition.

## FeedMinePersistence

- purpose: Local durability and queries.
- owns: Database lifecycle, schema evolution and content/publication/session storage.
- does not own: Networking or editorial decisions.
- allowed imports: FeedMineDomain. No imports are used by production scaffolds.
- downstream consumers: FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineComposition.

## FeedMineAcquisition

- purpose: Production and admission of canonical supply.
- owns: Connector boundary, demand planning, bounded bootstrap, admission and acquisition coordination.
- does not own: Publication or editorial ordering.
- allowed imports: FeedMineDomain, FeedMinePersistence. No imports are used by production scaffolds.
- downstream consumers: FeedMineSyndication, FeedMineRuntime, FeedMineComposition.

## FeedMineSyndication

- purpose: First concrete external connector.
- owns: RSS/Atom/JSON Feed translation and specific HTTP behavior.
- does not own: Persistence, editorial selection or general HTTP frameworks.
- allowed imports: FeedMineDomain, FeedMineAcquisition. No imports are used by production scaffolds.
- downstream consumers: FeedMineComposition.

## FeedMineEditorial

- purpose: Selection for future publication from local supply.
- owns: Plan resolution, candidate retrieval, editorial policy and deterministic selection.
- does not own: Connectors, protocol SDK/JSON, media preparation or publication.
- allowed imports: FeedMineDomain, FeedMinePersistence. No imports are used by production scaffolds.
- downstream consumers: FeedMinePublication, FeedMineRuntime, FeedMineComposition.

## FeedMineMedia

- purpose: Local resource preparation.
- owns: Media suitability, choice/quality/cost, assets and image materialization.
- does not own: Publication or SwiftUI rendering.
- allowed imports: FeedMineDomain, FeedMinePersistence. No imports are used by production scaffolds.
- downstream consumers: FeedMinePublication, FeedMineRuntime, FeedMineComposition.

## FeedMinePublication

- purpose: Immutable local published history.
- owns: Frozen cards, render contracts, editions, segments, windows and publication coordination.
- does not own: Acquisition, protocol parsing or remote media resolution.
- allowed imports: FeedMineDomain, FeedMinePersistence, FeedMineEditorial, FeedMineMedia. No imports are used by production scaffolds.
- downstream consumers: FeedMineRuntime, FeedMineComposition.

## FeedMineRuntime

- purpose: Consumption, runway and service coordination.
- owns: Session state/transitions/effects, UI boundary, local snapshots, viewport, adaptive demand, interactions and background entry.
- does not own: SQL, HTTP, concrete connectors, SwiftUI or monolithic feed ownership.
- allowed imports: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication. No imports are used by production scaffolds.
- downstream consumers: FeedMineUI, FeedMineComposition.

## FeedMineUI

- purpose: Local presentation and semantic user input.
- owns: Screen bridge, feed/card/loading presentation and input forwarding.
- does not own: Feed production, database, acquisition, selection, remote media or publication.
- allowed imports: FeedMineDomain, FeedMineRuntime. No imports are used by production scaffolds.
- downstream consumers: FeedMineComposition.

## FeedMineComposition

- purpose: Only composition root.
- owns: Explicit concrete dependency wiring and ordered object graph construction.
- does not own: Product logic, dynamic DI containers or global service location.
- allowed imports: FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineSyndication, FeedMineEditorial, FeedMineMedia, FeedMinePublication, FeedMineRuntime, FeedMineUI. No imports are used by production scaffolds.
- downstream consumers: Application composition entry only; no FeedMine module.
