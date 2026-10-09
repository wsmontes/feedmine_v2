# FeedMine

FeedMine é um feed reader local-first/offline-first, sem servidor próprio. O pacote Swift contém dez módulos; o aplicativo iOS separado usa esses módulos por referência local.

Abra `FeedMineApp/FeedMineApp.xcodeproj`, selecione o scheme compartilhado **FeedMine** e um simulador iOS 18 ou posterior. Não é necessário configurar uma equipe para compilar no simulador. Para um dispositivo físico, configure sua assinatura de desenvolvimento no Xcode.

O aplicativo restaura publicação local antes de qualquer aquisição. Sem história publicada, usa ColdFeedBootstrap com dois feeds BBC declarativos e identidades estáveis. A captura nativa está ligada ao Runway real e foi verificada com swipeUp/swipeDown no simulador. A 3R10/3R10-N é entregue na branch para revisão, sem integração em main. Imagens permanecem fora deste gate.

Veja [execução iOS](docs/IOS_RUN.md) e [arquitetura](docs/architecture/ARCHITECTURE.md). Verificação do pacote: `swift package describe`, `swift build`, `swift test`, `git diff --check`.
