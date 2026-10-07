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

Somente as arestas do grafo em ARCHITECTURE.md são permitidas. Nenhum módulo depende de FeedMineComposition. Imports transitivos não autorizam violar esse grafo. UI consome PresentationCard através de FeedPresentationSnapshot pelo boundary Runtime, sem importar Publication diretamente. Persistence registra durabilidade de publicação sem depender de tipos de Publication. PublicationHistory implementa o boundary semântico de leitura; Phase 2G implementa a projeção Runtime de apresentação.

# Publication/Persistence semantic boundary

Publication owns semantic values. Persistence owns mechanical records and storage, without depending on Publication or creating a parallel publication domain.

PublicationPersistenceMapping is internal to Publication. PublicationHistory is the concrete semantic read boundary over private PublicationStore and SessionStore instances. Runtime consumes Publication semantic values/boundaries; UI consumes Runtime projection only, with Domain identity and Foundation values.

The explicitly approved composition exception is FeedSession's public initializer accepting PublicationHistory. Presentation values and the restore result do not expose Publication, Persistence or Media types. UI never imports those modules or receives mechanical store records.

No dependency edge is added and no publication model is moved between modules.
