# FeedMine V2 — Referências externas para F01–F20

**Data-base:** 2026-10-10. **Natureza:** levantamento técnico externo complementar aos PRDs; não prova implementação, não concede PASS nos benchmarks B01–B06 e não substitui [North Star](../product/PRODUCT_NORTH_STAR.md), [Decisões PD-1–PD-10](../product/PRODUCT_DECISIONS_2026-10-09.md), [Invariantes](../architecture/PRODUCT_INVARIANTS.md), [B01–B06](../product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [F01–F10](../product/PRODUCT_AUDIT_10_FRONTS.md) e [F11–F20](../product/PRODUCT_AUDIT_FRONTS_11_20.md).

Fontes primárias incluem Apple, SQLite, GitHub, RSS/Atom/JSON Feed e OPML. Os artigos de MMR/diversidade são pesquisa conceitual, não obrigação de usar determinado algoritmo. As APIs Apple exigem checagem de disponibilidade contra o deployment target.

## F01 — Descoberta automática de fontes e alcance do catálogo

**Uso no FeedMine:** Autoridade do catálogo público, expansão de fontes elegíveis e atualização sem bloquear a apresentação.

- [Catálogo público](https://github.com/wawasoft/feed-repository) — Verificar revisão pública e metadados.
- [GitHub Releases REST](https://docs.github.com/en/rest/releases) — Inspecionar releases e assets versionados.
- [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask) — Verificação oportunista do manifesto.
- [FileManager](https://developer.apple.com/documentation/foundation/filemanager) — Staging e substituição segura de arquivos.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F02 — Primeira abertura, onboarding e primeira descoberta

**Uso no FeedMine:** Começar pelo feed real, com escolhas opcionais e evidências honestas de preparação.

- [HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) — Evitar gate obrigatório de configuração.
- [HIG Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls) — Mostrar preferências no contexto de uso.
- [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) — Comunicar progresso real, não inventado.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F03 — Aquisição, frescor e integridade das histórias

**Uso no FeedMine:** Suportar variações de feed, revisões e identidades de origem.

- [RSS 2.0](https://www.rssboard.org/rss-specification) — GUID, datas, enclosures e parsing.
- [Atom RFC 4287](https://www.rfc-editor.org/info/rfc4287/) — ID, links e atualização Atom.
- [JSON Feed 1.1](https://www.jsonfeed.org/version/1.1/) — IDs, HTML/texto e timestamps.
- [HTTP RFC 9110](https://www.rfc-editor.org/rfc/rfc9110.html) — Conditional requests e semântica de HTTP.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F04 — Curadoria, relevância, variedade e controle editorial

**Uso no FeedMine:** Equilibrar diversidade de Provider e conteúdo, relevância e novidade.

- [MMR — Carbonell e Goldstein](https://doi.org/10.1145/290941.291025) — Diversidade e relevância na ordenação.
- [Topic Diversification — Ziegler et al.](https://doi.org/10.1145/1060745.1060754) — Diversidade intralista e satisfação.
- [SQLite FTS5](https://www.sqlite.org/fts5.html) — BM25 para busca lexical; não confundir com ranking editorial.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F05 — Continuidade, antecipação e recuperação do runway

**Uso no FeedMine:** Estimar demanda a partir de consumo real, latência e recursos; evitar fim artificial.

- [SwiftUI ScrollGeometry](https://developer.apple.com/documentation/swiftui/scrollgeometry) — Observar deslocamento e distância real à cauda.
- [MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit) — Medir hitches, launch e recursos.
- [URLSession Low Data Mode](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/allowsconstrainednetworkaccess) — Adaptar especulação à restrição de rede.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F06 — Cards, mídia, estabilidade visual e legibilidade

**Uso no FeedMine:** Preparar representação antes da publicação e preservar geometria e âncora.

- [Image I/O thumbnail](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex%28_%3A_%3A_%3A%29) — Downsampling local fora do MainActor.
- [HIG Collections](https://developer.apple.com/design/human-interface-guidelines/collections) — Layout legível e consistente.
- [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) — Dynamic Type, contraste e VoiceOver.
- [SwiftUI ScrollGeometry](https://developer.apple.com/documentation/swiftui/scrollgeometry) — Evidência física de âncora.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F07 — Busca, filtros, assuntos e troca de contexto

**Uso no FeedMine:** Busca indexada e A→B→A com contexto e posição preservados.

- [SwiftUI Search](https://developer.apple.com/documentation/swiftui/search) — Pesquisa, tokens e sugestões.
- [SQLite FTS5](https://www.sqlite.org/fts5.html) — Pesquisa local em corpus admitido.
- [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack) — Retornar ao contexto de leitura.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F08 — Leitura, ações e biblioteca pessoal

**Uso no FeedMine:** Ações sobre card e estado durável sem duplicar seleção.

- [SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller/) — Abrir links in-app e retornar.
- [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink) — Compartilhamento explícito nativo.
- [Apple File System](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively) — Distinguir estado pessoal de cache reconstruível.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F09 — Persistência local, offline e reabertura

**Uso no FeedMine:** Restauração local, atualização de catálogo e sobrevivência de dados duráveis.

- [SQLite WAL](https://www.sqlite.org/wal.html) — Transações e recuperação.
- [Apple File System](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively) — Retenção de dados vs. cache.
- [FileManager](https://developer.apple.com/documentation/foundation/filemanager) — Substituição validada de snapshots.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F10 — Escala, recursos, acessibilidade e prontidão para publicar

**Uso no FeedMine:** Prova em dispositivo real, recursos sob pressão e gates B01–B06.

- [MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit) — Métricas reais de performance.
- [Accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app) — Auditoria automatizada e manual.
- [URLSession Low Data Mode](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/allowsconstrainednetworkaccess) — Rede restrita.
- [App Store Guidelines](https://developer.apple.com/app-store/guidelines/) — Restrições externas do lançamento.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F11 — Busca unificada e exploração dos resultados

**Uso no FeedMine:** Interface de resultados por tipo com volta à query e ao feed.

- [HIG Searching](https://developer.apple.com/design/human-interface-guidelines/searching) — Busca compreensível e escopos claros.
- [Scoping a search operation](https://developer.apple.com/documentation/swiftui/scoping-a-search-operation) — Escopos de fontes, artigos e salvos.
- [SQLite FTS5](https://www.sqlite.org/fts5.html) — Snippet/highlight/ranking local.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F12 — Fontes, países, regiões e taxonomia navegáveis

**Uso no FeedMine:** Navegação card→Source→país/taxonomia com retorno correto.

- [HIG Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) — Hierarquia legível.
- [Understanding NavigationStack](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack) — Rotas estáveis.
- [HIG Collections](https://developer.apple.com/design/human-interface-guidelines/collections) — Quando usar visualização em grade.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F13 — Exclusões explícitas e editor de filtros

**Uso no FeedMine:** Controle negativo durável, reversível e explicável.

- [HIG Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields) — Tokens e escopos de restrição.
- [HIG Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) — Desfazer exclusões.
- [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) — Explicar efeitos e estados vazios.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F14 — Leitor embutido, destinos e retorno

**Uso no FeedMine:** Abrir destino certo e retornar à mesma história sem perda da posição.

- [SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller/) — Navegação web in-app.
- [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) — Controle explícito quando necessário.
- [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack) — Histórico de navegação.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F15 — Podcasts e reprodução contínua de áudio

**Uso no FeedMine:** Player com posição durável e retomada após interrupção.

- [AVPlayer](https://developer.apple.com/documentation/avfoundation/avplayer) — Streaming, seek e playback.
- [Monitoring playback progress](https://developer.apple.com/documentation/avfoundation/monitoring-playback-progress-in-your-app) — Persistir posição de reprodução.
- [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions) — Retomar após interrupção.
- [MPRemoteCommandCenter](https://developer.apple.com/documentation/mediaplayer/mpremotecommandcenter) — Comandos remotos.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F16 — Biblioteca pessoal, caixas e Smart Feeds

**Uso no FeedMine:** Navegação pessoal offline, sem segundo runtime de seleção.

- [HIG Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) — Organização e edição.
- [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack) — Navegação contextual.
- [SQLite FTS5](https://www.sqlite.org/fts5.html) — Consulta de salvos.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F17 — Idiomas, aparência e acessibilidade

**Uso no FeedMine:** Idioma de UI separado de idioma editorial; rematerialização sem nova Edition.

- [Xcode String Catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog) — Localização, pluralização e variantes.
- [HIG Right-to-left](https://developer.apple.com/design/human-interface-guidelines/right-to-left) — RTL correto.
- [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) — Dynamic Type e contraste.
- [Accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app) — Testes automatizados.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F18 — Adicionar fonte, clipboard, OPML e portabilidade

**Uso no FeedMine:** Import/export de fontes com distinção explícita entre OPML e backup de dados pessoais.

- [OPML 2.0](https://opml.org/spec2.opml) — Interoperabilidade de fontes.
- [UIPasteboard](https://developer.apple.com/documentation/uikit/uipasteboard) — Colar links por ação explícita.
- [Uniform Type Identifiers](https://developer.apple.com/documentation/uniformtypeidentifiers/) — Tipos dos arquivos importados.
- [SwiftUI File importer/exporter](https://developer.apple.com/documentation/swiftui/view-presentation) — UI nativa para arquivos.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F19 — Compartilhamento de descobertas e feedback

**Uso no FeedMine:** Compartilhar texto, link e atribuição da publicação congelada.

- [ShareLink](https://developer.apple.com/documentation/swiftui/sharelink) — Compartilhamento do sistema.
- [LPLinkMetadata](https://developer.apple.com/documentation/linkpresentation/lplinkmetadata) — Rich preview local.
- [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) — Confirmações discretas e acessíveis.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## F20 — Retorno ao app, novidades e lifecycle

**Uso no FeedMine:** Retomar Edition/cursor local antes de rede, mostrar novidades sem mutação silenciosa.

- [ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase) — Transições app ativo/inativo.
- [Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) — Trabalho oportunista de background.
- [MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit) — Medir experiência de retorno.
- [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) — Novidade real sem deslocar feed.

**Cuidado:** referências oferecem técnicas, não novos owners/pipelines; preservar a publicação imutável, o supply local reutilizável, o Runway adaptativo e os critérios de produto vigentes.

## Prioridade de leitura sugerida

F01 → F05 → F06 → F03 → F04 para a promessa de descoberta contínua; F09 → F10 para durabilidade/release; F02 → F07 → F11–F14 para experiência de exploração; F08 e F15–F20 para jornadas complementares. Essa é uma ordem de investigação, não uma ordem mandatória de código.
