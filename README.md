# FeedMine

FeedMine é um feed reader local-first/offline-first, sem servidor próprio de conteúdo. Conteúdo externo alimentará supply local; a UI navegará história local já publicada.

Este repositório é um clean rewrite com arquitetura modular em dez targets Swift, sem dependências externas. Status: **architecture scaffold**; APIs e comportamento de produção estão intencionalmente ausentes.

Veja a [arquitetura](docs/architecture/ARCHITECTURE.md).

Verificação: `swift package describe`, `swift build`, `swift test` e `git diff --check`. O target de testes adicional verifica somente a compilação do grafo.
