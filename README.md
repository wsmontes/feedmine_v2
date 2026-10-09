# FeedMine

FeedMine é um feed reader local-first/offline-first, sem servidor próprio. O pacote Swift contém dez módulos; o aplicativo iOS separado usa esses módulos por referência local.

Abra `FeedMineApp/FeedMineApp.xcodeproj`, selecione o scheme compartilhado **FeedMine** e um simulador iOS 18 ou posterior. Não é necessário configurar uma equipe para compilar no simulador. Para um dispositivo físico, configure sua assinatura de desenvolvimento no Xcode.

O aplicativo restaura publicação local antes de qualquer aquisição. Sem história publicada, usa ColdFeedBootstrap, preparação com evidências reais e publicação incremental. O Runway mantém reserva local, e a mídia é preparada antecipadamente para cards com imagem local ou layout text-only. Cards com link abrem o artigo. O catálogo V1 e a escolha de fontes/contextos estão em implementação; consulte o relatório de validação para separar código integrado de comportamento comprovado.

A rodada atual é verificada localmente, sem CI hospedada. Resultados e limitações ficam em [validação OMP/Codex](docs/reviews/OMP_VALIDATION_2026-10-09.md).

Veja [execução iOS](docs/IOS_RUN.md) e [arquitetura](docs/architecture/ARCHITECTURE.md). Verificação do pacote: `swift package describe`, `swift build`, `swift test`, `git diff --check`.
