# FeedMine V2 — Pesquisa Apple: interface, ciclo de vida e confiabilidade

**Data:** 2026-10-10. **Fonte:** documentação primária Apple Developer/Human Interface Guidelines. **Status:** investigação documental; implementação e benchmarks continuam sem certificação nesta pesquisa.

## Motivação e decisão de escopo
A plataforma iOS é uma participante ativa do runtime: bloqueia tela, suspende cenas, pode terminar processos, limita background execution, protege arquivos, purga caches, altera condições de rede e limita memória/energia. A UI precisa continuar honesta e funcional ao redor desses comportamentos. O FeedMine não usa servidor próprio e não pode 'simular' um daemon que roda sempre; a experiência deve derivar de **publicação local imutável, store/Session com dono claro, aquisição oportunista e recuperação durável**.

As 20 frentes anteriores continuam como autoridade das jornadas. Criamos **sete deep dives de plataforma**, F21–F27, com cenários verificáveis e owner existente: não são sete engines novos. O mapa de impactos e PRDs atuais recebem links para não duplicar regras.

## Matriz Apple → V2

| Frente | Questão que precisa ser provada | Frentes existentes | Prioridade |
|---|---|---|---|
| [F21 — Ciclo de vida da cena e continuidade da sessão](../product/F21_IOS_SCENE_SESSION_CONTINUITY_PRD.md) | Foco, suspensão e reinício preservam a sessão? | F06, F09, F20 | P0 |
| [F22 — Rede variável, uso offline e conectividade explicável](../product/F22_NETWORK_OFFLINE_CONSTRAINED_UX_PRD.md) | Offline/rede restrita continuam a leitura e priorizam rede? | F01, F03, F05, F09, F13 | P0 |
| [F23 — Execução limitada em background e transferências](../product/F23_BACKGROUND_EXECUTION_TRANSFERS_PRD.md) | Background é oportunista e consistente, sem falsas promessas? | F01, F03, F05, F09, F15, F20 | P0 |
| [F24 — Durabilidade local, proteção de arquivos e recuperação](../product/F24_IOS_STORAGE_PROTECTION_RECOVERY_PRD.md) | Arquivos e dados sobrevivem a purge, kill e disco cheio? | F01, F08, F09, F10, F18 | P0 |
| [F25 — SwiftUI estável sob mudanças assíncronas](../product/F25_SWIFTUI_PRESENTATION_STABILITY_UX_PRD.md) | A apresentação nunca salta nem bloqueia a MainActor? | F02, F05, F06, F07, F14, F17 | P0 |
| [F26 — Integrações iOS: leitura, links, arquivos, compartilhamento e áudio](../product/F26_IOS_SYSTEM_INTEGRATIONS_PRD.md) | Integrações nativas preservam publicação e retorno? | F08, F14, F15, F18, F19, F20 | P1 |
| [F27 — Pressão de recursos, desempenho e evidência física](../product/F27_DEVICE_PRESSURE_PERFORMANCE_EVIDENCE_PRD.md) | Resource pressure degrada custo, não a experiência? | F05, F06, F09, F10, F17, F23 | P0 |

## Quatro distinções que mudam a implementação

1. **`ScenePhase.inactive` / `.background` ≠ execução contínua:** o app pode sair de foco antes de ser suspenso. Eventos não autorizam destruir FeedSession, o estado durável é obrigatório.
2. **`BGAppRefreshTask` ≠ cron:** scheduler não garante hora, frequência ou duração de feed scraping. Background `URLSession` transfere **arquivos**, não mantém pipelines RSS/stream arbitrários vivos; force quit invalida expectativa de relaunch automático. Referências: [Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app), [background(withIdentifier:)](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background%28withidentifier%3A%29).
3. **`URLCache` ≠ publicação/asset local:** caches HTTP e `Caches` são purgáveis. `Application Support` e backups/file protection precisam respeitar classes de durabilidade. Referências: [Accessing Cached Data](https://developer.apple.com/documentation/foundation/accessing-cached-data), [Using the File System Effectively](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively).
4. **`@SceneStorage` ≠ checkpoint confiável:** Apple não garante quando o scene state será persistido. FeedEdition + PublishedCardID continuam autoridade. Referência: [SceneStorage](https://developer.apple.com/documentation/swiftui/scenestorage).

## Evidência exigida (black-box + diagnósticos)

- **Jornada 1:** instalação limpa → primeiras histórias reais → scroll prolongado 30 min → background/foreground → mesma história. B01/B03 continuam obrigatórios.
- **Jornada 2:** card em leitura parado 10 min + downloads/metadata chegando + rotação/Dynamic Type → zero salto involuntário. B04 e F06.
- **Jornada 3:** offline, Low Data Mode, Wi‑Fi→celular, HTTP host lento/falho → feed local intocado, tail honesto, reposição futura. F03/F05/F09/F22.
- **Jornada 4:** OS kill/force quit/sem execução background, reiniciar offline → checkpoint/bookmarks íntegros; não prometer updates regulares. F09/F20/F21/F23/F24.
- **Jornada 5:** falta de disco/cache purge/locked device/primeiro unlock → retenção correta e nenhuma publicação parcial. F09/F24.
- **Jornada 6:** compartilhar, importar OPML, leitor web, áudio/ligação/retorno → ação correta e continuidade do contexto. F14/F15/F18/F19/F26.
- **Jornada 7:** Energy/SwiftUI/Hitches/Instruments em aparelho real sob carga; capturar custo e sintomas junto de logs de decisões, sem alterar benchmarks. F10/F25/F27.

## Orientação para os agentes

Implementar apenas depois de confrontar PRD e código atual; preferir remover caminhos paralelos antes de inventar Store, governor, timer ou cache. Apple sugere APIs, não governa o modelo editorial. Configurações do projeto (Background Modes, Associated Domains, file protection) devem ser inspecionadas antes de serem alteradas. Onde a API não serve à necessidade da V2, registrar 'não aplicável' em vez de adotá-la.

## Referências Apple primárias — leitura inicial

- [ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase) / [Restoring State with SwiftUI](https://developer.apple.com/documentation/swiftui/restoring-your-app-s-state-with-swiftui)
- [Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) / [Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- [URLSessionConfiguration](https://developer.apple.com/documentation/foundation/urlsessionconfiguration) / [NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)
- [Using File System Effectively](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively) / [File Protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/completeuntilfirstuserauthentication)
- [Understanding SwiftUI Performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance) / [Improving App Responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [Analyzing Battery Use](https://developer.apple.com/documentation/xcode/analyzing-your-app-s-battery-use) / [Reducing Terminations](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app)

Bibliografia específica e os testes detalhados estão em cada F21–F27.
