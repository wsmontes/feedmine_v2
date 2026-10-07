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

Somente as arestas do grafo em ARCHITECTURE.md são permitidas. Nenhum módulo depende de FeedMineComposition. Imports transitivos não autorizam violar esse grafo; os arquivos de produção deste scaffold não possuem imports. UI consome presentation cards pelo boundary Runtime, sem importar Publication diretamente. Persistence registra durabilidade de publicação sem depender de tipos de Publication. As APIs para esses boundaries serão definidas nas phases futuras.
