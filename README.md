# FeedMine

FeedMine é um feed reader local-first/offline-first, sem servidor próprio. O pacote Swift contém dez módulos; o aplicativo iOS separado usa esses módulos por referência local.

Abra `FeedMineApp/FeedMineApp.xcodeproj`, selecione o scheme compartilhado **FeedMine** e um simulador iOS 18 ou posterior. Não é necessário configurar uma equipe para compilar no simulador. Para um dispositivo físico, configure sua assinatura de desenvolvimento no Xcode.

O aplicativo restaura publicação local antes de qualquer aquisição. Sem história publicada, usa ColdFeedBootstrap, preparação com evidências reais e publicação incremental. O Runway mantém reserva local, e a mídia é preparada antecipadamente para cards com imagem local ou layout text-only. Cards com link abrem o artigo. O catálogo V1 (77.443 fontes) é empacotado no app a partir de um asset de release verificado; fontes selecionadas, contextos, busca local e bookmarks persistem offline. A manutenção da cauda preserva cards já vistos. Consulte o relatório de validação para resultados e pendências.

Antes de compilar um clone, execute `scripts/fetch-catalog.sh`. Ele baixa `catalog.sqlite` da release `catalog-v1`, confere tamanho e SHA-256 e instala em `FeedMineApp/FeedMineApp/Resources/` (arquivo ignorado pelo Git). Sem ele, o build falha em Copy Bundle Resources. Git LFS não é mais usado.

A rodada atual é verificada localmente, sem CI hospedada. Resultados e limitações ficam em [validação OMP/Codex](docs/reviews/OMP_VALIDATION_2026-10-09.md); a transferência do frontend V1 → V2 tem o seu próprio registro, superfície por superfície, em [evidência da transferência](docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md), com o inventário de controles em `docs/v1-study/UI_TRANSFER_MATRIX.md`.

Verificação do pacote: `swift package describe`, `swift build`, `swift test`, `git diff --check`. A suíte do app roda no simulador pelo scheme **FeedMine**; os testes de UI de um caso por vez com `-only-testing:FeedMineUITests/FeedMineUITests/<nome>` (é assim que a evidência de cada superfície foi produzida), e a corrida completa do scheme é o portão final.

Veja [execução iOS](docs/IOS_RUN.md) e [arquitetura](docs/architecture/ARCHITECTURE.md).
