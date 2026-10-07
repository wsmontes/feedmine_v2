# Dependency rules

Todas as dependências abaixo são PROIBIDAS. Os nomes abreviados designam os respectivos módulos FeedMine.

```text
FeedMineDomain → qualquer outro módulo FeedMine

FeedMinePersistence → Acquisition
FeedMinePersistence → Editorial
FeedMinePersistence → Media
FeedMinePersistence → Publication
FeedMinePersistence → Runtime
FeedMinePersistence → UI

FeedMineAcquisition → Syndication
FeedMineAcquisition → Editorial
FeedMineAcquisition → Publication
FeedMineAcquisition → Runtime
FeedMineAcquisition → UI

FeedMineSyndication → Persistence
FeedMineSyndication → Editorial
FeedMineSyndication → Publication
FeedMineSyndication → Runtime
FeedMineSyndication → UI

FeedMineEditorial → Connector implementation
FeedMineEditorial → Syndication
FeedMineEditorial → Media
FeedMineEditorial → Publication
FeedMineEditorial → UI

FeedMineMedia → Publication
FeedMineMedia → Runtime
FeedMineMedia → UI

FeedMinePublication → Acquisition
FeedMinePublication → Syndication
FeedMinePublication → Runtime
FeedMinePublication → UI

FeedMineRuntime → Syndication
FeedMineRuntime → UI

FeedMineUI → Persistence
FeedMineUI → Acquisition
FeedMineUI → Syndication
FeedMineUI → Editorial
FeedMineUI → Media
FeedMineUI → Publication
```

```text
SwiftUI → Connector          PROIBIDO
SwiftUI → Database           PROIBIDO
SwiftUI → Acquisition        PROIBIDO
SwiftUI → Selection          PROIBIDO
SwiftUI → AssetStore         PROIBIDO

Selection → Connector        PROIBIDO
Selection → Protocol SDK     PROIBIDO
Selection → Protocol JSON    PROIBIDO

Publication → Connector      PROIBIDO
Publication → Network        PROIBIDO

Media → Publication          PROIBIDO

Acquisition → Publication    PROIBIDO
```

Somente as arestas do grafo em ARCHITECTURE.md são permitidas. Nenhum módulo depende de FeedMineComposition. Imports transitivos não autorizam violar esse grafo; os arquivos de produção deste scaffold não possuem imports. UI consome PresentationCard através de FeedPresentationSnapshot pelo boundary Runtime, sem importar Publication diretamente. Persistence registra durabilidade de publicação sem depender de tipos de Publication. As APIs para esses boundaries serão definidas nas phases futuras.

# Publication/Persistence boundary gate

FeedMinePublication owns publication semantics.

FeedMinePersistence owns storage mechanics.

Persistence must not create a parallel publication domain.

The representation boundary required to durably store FeedEdition,
FeedSegment and PublishedCard is intentionally not designed in Phase 0.

Before implementation of durable publication storage, the architecture
must explicitly select a dependency-safe representation strategy.

Until that decision exists:

- PublicationStore remains scaffold-only;
- no publication persistence DTOs are authorized;
- no publication repository protocol is authorized;
- no dependency edge may be added;
- no publication model may be moved between modules.
