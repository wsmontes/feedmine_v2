# Transferência do frontend V1 → V2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Execução pelo agente principal; delegação somente mediante autorização explícita. Este pedido entrega o plano, não inicia a implementação.

**Goal:** Entregar o Feedmine com a UI e as interações do V1, reaproveitando seu código, sobre o backend sustentável do V2 e com admissão de novos cards controlada pelo scroll.

**Architecture:** Copiar layouts e controles do V1 por superfície, substituindo dependências de `FeedLoader`/`FeedStore` por valores de apresentação e ações tipadas. Aquisição, mídia, seleção e persistência continuam com os donos existentes do V2. A sessão distingue reserva produzida de conteúdo admitido no scroll; produção não altera automaticamente a apresentação ativa.

**Tech Stack:** Swift 6, SwiftUI, iOS 18+, SwiftPM; GRDB 7.11.1 em Persistence e FeedKit 10.9.4 em Syndication. Manter compilação do pacote para macOS 14; integrações UIKit/WebKit/AVFoundation específicas ficam condicionadas à plataforma.

**Spec:** `docs/reviews/2026-10-09-v1-ui-and-scroll-barrier-analysis.md`, instruções do usuário nesta conversa e `docs/product/PRODUCT_DECISIONS_2026-10-09.md`. A instrução atual de paridade da UI prevalece sobre decisões anteriores de redesenhá-la.

## Global Constraints

- V1 fonte: `/Users/wagnermontes/Documents/GitHub/feedmine`, commit de referência `712a6ba93c6a8ab28c3b3c0e2b2777d1e3341d0c`; conferir alterações locais antes de copiar. Não modificar esse checkout.
- V2 destino: `/Users/wagnermontes/Documents/GitHub/feedmine_v2`; referência inicial `372f4c5`. Conferir HEAD e alterações existentes antes de executar.
- Copiar código visual do V1. Alterar somente integração, separação de responsabilidades e correções necessárias à estabilidade/acessibilidade, registrando diferenças.
- UI consome Domain/Runtime. Nenhuma View acessa banco, connector, aquisição, seleção ou AssetStore.
- Não copiar `FeedStore.swift`, `FeedLoader.swift`, Reservoir, schedulers ou outro motor paralelo para obter compatibilidade.
- Depois da carga inicial, somente avanço real do scroll autoriza admissão de novos cards. Aquisição, decode, retry e foreground abastecem a reserva.
- Card admitido conserva identidade, ordem, conteúdo, mídia e estrutura. Salvar/marcar lido pode mudar affordances sem mudar sua altura.
- Apresentação ativa não é reconstruída por temporizador de aparência. Preservar opções visuais do V1; congelar valores estruturais por sessão e aplicar mudanças explícitas de preferência de modo controlado.
- Manter alternância de fontes, publicação de edições materiais e orçamento de mídia conforme PD-1/PD-4/PD-5/PD-6.
- Migrações são aditivas e versionadas. Não abrir a base do V1 com o migrator do V2; importação explícita usa cópia e leitura compatível.
- Não remover menus ou substituir funções por botões sem ação. Uma superfície só é transferida quando seu fluxo funciona.
- Não publicar TestFlight nem substituir o build no aparelho durante a execução sem pedido correspondente. Cada entrega pode ser compilada e validada localmente.
- Sem CI hospedada ou PR obrigatório; verificações locais e documentação no mesmo commit da implementação.

## Review Focus

1. Preparação/retry/foreground terminam com leitor parado: lista, frames e deslocamento ficam idênticos — T2/T3/T12.
2. Scroll longo em ambos os sentidos e card mais alto que a tela: âncora e deslocamento dentro do card sobrevivem à gestão de memória — T3/T12.
3. Filtros A→B→A com requests antigos em voo: retorno local correto, sem contaminação e sem perder posição — T6/T12.
4. Coleções/salvos/preferências existentes e migração interrompida: dados preservados, importação idempotente e retomável — T7/T8/T10.
5. Fontes sem imagem, mídia inválida, Dynamic Type e Reduce Motion: layout final útil, ações acessíveis e ausência de saltos — T4/T9/T11/T12.

## Estratégia e fronteira de escopo

Este é o plano mestre de transferência, com entregas sequenciais. T1–T6 fecham a leitura principal; T7–T11 fecham a paridade funcional restante; T12 certifica o conjunto. Não declarar a transferência inteira concluída após T6.

Cada entrega termina com build utilizável, testes relevantes e commit próprio. Quando um controle revela uma dependência adicional, inventariá-la na tarefa responsável; não puxar o monólito para fazer a View compilar. O inventário de T1 determina a lista completa de ações alcançáveis, inclusive controles condicionais; nenhuma pode desaparecer silenciosamente.

Os nomes de novas APIs abaixo são contratos propostos, não APIs já existentes. Tipos novos devem ser definidos na tarefa indicada; consumidores posteriores usam os mesmos nomes.

## Mapa de transferência

Origens relativas a `V1/feedmine/`; destinos relativos à raiz do V2.

| Origem V1 | Destino V2 | Entrega |
| --- | --- | --- |
| `Services/DesignTokens.swift`, valores puros de `CircadianEngine.swift`, assets/fontes/localizações | `Sources/FeedMineUI/Appearance/`, recursos do app | T4/T10 |
| `Views/FeedItemCardView.swift`, `FeedItemView.swift`, `FeedItemRowView.swift` | `Sources/FeedMineUI/Cards/`; substituir renderer atual | T4 |
| `Views/FeedScreen.swift`: header, menu, busca, lens, seções, gestos | `Sources/FeedMineUI/Reader/`; integrar ao `FeedScreen.swift` | T5/T6 |
| `FilterSheetView.swift`, `ContentFilterView.swift`, `TaxonomyChipBar.swift` | `Sources/FeedMineUI/Filters/` | T6 |
| `SourceManagementView.swift`, `CatalogExploreView.swift`, `TaxonomyBrowseView.swift`, telas Country/Region | `Sources/FeedMineUI/Sources/` | T7 |
| `CollectionManagementView.swift`, `BookmarkBoxesView.swift`, `BookmarkBoxPickerView.swift` | `Sources/FeedMineUI/Collections/`, `Bookmarks/` | T8 |
| `ArticleReaderView.swift`, `MiniPlayerBar.swift`, `ShareCardImageView.swift`, `StatsShareCard.swift` | Views em UI; integrações de plataforma em Composition | T9 |
| `SettingsSheetView.swift`, `ToastView.swift`, `ClipboardBanner.swift` | `Sources/FeedMineUI/Settings/`, `Feedback/` | T5/T10 |
| `AddFeedView.swift`, `ExportView.swift`, `Services/OPMLParser.swift` | UI/ImportExport; operações em Composition/Persistence | T10 |
| `CuratedOnboardingView.swift`, `CuratedFeedInspectorView.swift`, `OnboardingTipsView.swift`, `Views/Onboarding/*` | `Sources/FeedMineUI/Onboarding/` | T11 |
| `Models/FeedRecipeDefinition.swift`, `CuratedFeed.swift`, `Services/FeedRecipeResolver.swift`, `CuratedPreferenceEngine.swift` | Domain/Editorial/Persistence, conforme responsabilidade | T8/T11 |

Modelos legados não atravessam o boundary por conveniência. Copiar valores e algoritmos puros úteis, mantendo as identidades UUID do V2 e mapeando chaves V1 de forma estável.

## T1 — Inventário executável e referência de paridade

**Files:** criar `docs/v1-study/UI_TRANSFER_MATRIX.md`, `docs/reviews/V1_UI_REFERENCE.md`; ampliar `docs/v1-study/PORT_LOG.md`. Ler as origens da tabela, app do V1 e dependências chamadas por cada ação.

**Interfaces:** matriz com `surface`, `v1Path`, `v1Symbol`, `v1Revision`, `v2Path`, `dataDependencies`, `actions`, `proof`, `status`. Status: `inventariado`, `em transferência`, `validado`; ação faltante mantém status incompleto.

- [ ] Registrar SHA, alterações locais e condições de build de ambos os checkouts; não descartar trabalho existente.
- [ ] Enumerar todos os caminhos do menu, context menus, filtros, presets e settings, inclusive opções condicionais e debug; mapear cada ação para T4–T11.
- [ ] Registrar screenshots V1 em claro/escuro, retrato/paisagem, com/sem imagem, filtro ativo, menu aberto e fonte longa. Usar conteúdo local fixo e mesma preferência visual para comparação.
- [ ] Registrar em `V1_UI_REFERENCE.md` os valores efetivos do tema, dispositivo, viewport, tamanho de fonte, locale e origem dos dados. Screenshots ficam em diretório de evidências, sem mídia volumosa no Git.
- [ ] Traçar para cada View o que é layout reaproveitável, serviço necessário e efeito externo. Registrar operações de compartilhamento, player, notificações/deep links e importação presentes na UI alcançável.
- [ ] Verificar que cada controle tem destino e prova; commit `docs: map V1 frontend transfer and parity evidence`.

**Aceite:** outra pessoa consegue localizar o código original de qualquer controle e identificar a entrega responsável. Falha de build V1 não vira aprovação visual: documentar a limitação e obter referência utilizável antes do gate de paridade.

## T2 — Separar produção de admissão visual

**Files:** modificar `Sources/FeedMineRuntime/FeedSession.swift`, `FeedSessionState.swift`, `Sources/FeedMineComposition/FeedRunwayDriver.swift`, `FeedMineApp/FeedMineApp/AppComposition.swift`; criar `Sources/FeedMineRuntime/FeedPresentationAdmission.swift`, `Tests/FeedMineRuntimeTests/FeedPresentationAdmissionTests.swift`; ampliar `Tests/FeedMineCompositionTests/FeedRunwayDriverTests.swift`.

**Interfaces:** `FeedPresentationAdmission` descreve `.initial`, `.forwardScroll(ViewportObservation)`, `.restore`; `FeedSession.admitPresentation(_ admission: FeedPresentationAdmission) throws -> FeedPresentationSnapshot?`. Produção conserva `currentPresentation()`; nunca chama admissão. `.initial` só instala a primeira apresentação de uma associação; `.restore` só recupera uma associação sem apresentação ativa. Preservar `submitViewport` como registro de observação e exposição, separando-o da extensão da lista.

- [ ] Criar `testPreparationWhileStationaryDoesNotExtendPresentation`: fixar snapshot, produzir outro segmento e verificar igualdade de IDs, conteúdo e proveniência apresentados; `readyAhead` deve crescer.
- [ ] Criar `testRetryAndForegroundDoNotAdmitCards` e `testInitialAdmissionIsNotRepeated`: novos resultados não alteram apresentação ativa; primeira apresentação continua possível.
- [ ] Rodar os testes novos e registrar falha comportamental no fluxo atual antes da alteração.
- [ ] Remover a chamada de refresh visual no caminho de produção; manter publicação e medição da reserva. Restringir refresh/restore para que foreground não amplie uma lista já admitida.
- [ ] Fazer o driver retornar o snapshot ativo quando há só produção; callbacks de progresso mudam somente estado de trabalho. Manter fences de contexto e proveniência.
- [ ] Rodar `swift test --filter FeedPresentationAdmissionTests`, `swift test --filter FeedRunwayDriverTests` e testes de warm restore/cold bootstrap; commit `fix: keep background production outside reader presentation`.

**Aceite:** reserva cresce com leitor parado sem inserir cards na lista; nenhum segundo owner persistente de histórico ou publicação.

## T3 — Scroll libera o próximo prefixo sem mover conteúdo existente

**Files:** modificar `FeedSession.swift`, `FeedSessionState.swift`, `Sources/FeedMineUI/FeedScreen.swift`; criar `Sources/FeedMineUI/Reader/FeedScrollPosition.swift`, `Tests/FeedMineRuntimeTests/ScrollAdmissionTests.swift`; ampliar `Tests/ArchitectureSmokeTests/FeedViewportCaptureTests.swift`, `FeedMineApp/FeedMineAppTests/FeedMineUITests.swift`.

**Interfaces:** consumir T2. `FeedScrollPosition` guarda ID de referência e deslocamento visual relativo dentro do card, apenas como estado transitório de UI. A autoridade de admissão continua na sessão. `.forwardScroll` é emitido somente com movimento real para frente e necessidade de prolongar conteúdo; stationary/backward/layout não estendem o limite de admissão. Reentrada de histórico já admitido não é nova admissão.

- [ ] Criar `testForwardScrollAdmitsOnlyReadyPrefix`, `testLayoutChangeCannotAdmit`, `testBackwardNavigationDoesNotExposeFuture`: verificar ordem, ausência de duplicação e prefixo anterior intacto.
- [ ] Rodar e comprovar as falhas antes de implementar o gate no caminho de `submitViewport`/driver.
- [ ] Substituir a reconstrução da lista em torno de cada âncora por uma fronteira de admissão monotônica na sessão. Ler histórico admitido sob demanda; não manter bitmaps de todo o feed em memória.
- [ ] Preservar posição física em descarte/rematerialização: usar medição de conteúdo removido e restauração do deslocamento relativo. Se a janela não puder provar preservação, manter IDs/estrutura admitida e limitar inicialmente só imagens decodificadas; não introduzir trimming que cause salto.
- [ ] Mover feedback de trabalho de `safeAreaInset` variável para overlay que não recebe toques ou área de altura constante. Congelar espaço estrutural do header durante atualização de trabalho.
- [ ] UI test com gesto nativo: parar no meio de um card alto, concluir produção, voltar de background e comparar ID/frame/offset; diferença máxima de 1 ponto após estabilização de layout no mesmo viewport.
- [ ] Rodar testes de captura/admissão e scroll iOS em ambos os sentidos; commit `fix: admit prepared cards through stable native scrolling`.

**Aceite:** gesto revela cards prontos; retorno para cima preserva acesso ao histórico; status de trabalho não muda a geometria do feed. Giro de tela/tamanho de fonte é uma mudança explícita de layout e deve preservar a referência do leitor.

## T4 — Copiar o design e os cards do V1

**Files:** origens da tabela; criar `Sources/FeedMineUI/Cards/FeedItemCardView.swift`, `FeedItemView.swift`, `FeedItemRowView.swift`, `Sources/FeedMineUI/Appearance/ReaderAppearance.swift`; modificar `FeedCardView.swift`, `FeedDesignTokens.swift`, `Sources/FeedMineRuntime/PresentationCard.swift` e projeção/publicação correspondente quando faltar metadata; ampliar `Tests/ArchitectureSmokeTests/FeedScreenRenderingTests.swift`.

**Interfaces:** `ReaderAppearance` é um valor imutável com paleta, fontes, radius, padding e gap copiados do V1. `FeedItemCardView(card: PresentationCard, appearance: ReaderAppearance, isRead: Bool, isBookmarked: Bool, onAction: (ReaderCardAction) -> Void)`. Definir `ReaderCardAction` em UI com `.open`, `.save`, `.viewSource`, `.addSourceToCollection`, `.copyLink`, `.share`, `.openMedia`; cada ação carrega `PublicationCardID`. URLs são resolvidas fora da View.

- [ ] Copiar o código de composição portrait/landscape, source row, títulos, excerpt, bordas, overlays e context menus; preservar valores e regras visuais do V1. Registrar origem/símbolo/revisão no PORT_LOG.
- [ ] Adaptar `FeedItem`/`CardMediaSlot`/affordances para `PresentationCard`; acrescentar campos semânticos realmente necessários, como categoria, idioma e affordances de mídia, com testes da projeção congelada. Não buscar metadata do catálogo a cada render.
- [ ] Testar card sem imagem, placeholder final, imagem local, texto longo e action indisponível; renderer não solicita rede nem decode e salvar/lido não muda frame.
- [ ] Resolver valores de `CircadianEngine` sem copiar singleton/timer para os cards. Manter aparência escolhida e congelar métricas estruturais durante leitura.
- [ ] Copiar assets/fontes/localizações utilizados; verificar nomes, recursos empacotados e disponibilidade nas plataformas.
- [ ] Comparar screenshots com T1 sob os mesmos dados e preferências; conferir Dynamic Type e paisagem; rodar rendering/projection tests e build iOS; commit `feat: port V1 card layouts and visual system`.

**Aceite:** card visualmente fiel ao V1, sem downloads disparados pela View e sem promoção tardia de mídia.

## T5 — Copiar shell, cabeçalho, menus e busca

**Files:** origem `Views/FeedScreen.swift`, `ToastView.swift`, `ClipboardBanner.swift`; criar `Sources/FeedMineUI/Reader/ReaderShell.swift`, `ReaderHeader.swift`, `ReaderMenu.swift`, `ReaderNavigation.swift`, `Feedback/ToastView.swift`, `Feedback/ClipboardBanner.swift`; modificar `FeedMineApp.swift`, `FeedScreen.swift`, `FeedScreenStore.swift`; ampliar `CompositionTests.swift` e `FeedMineUITests.swift`.

**Interfaces:** `ReaderDestination` enum em UI cobre as superfícies da matriz T1. `ReaderShell` recebe store, aparência e callback `onNavigate: (ReaderDestination) -> Void`. Composition executa ações de card de T4; host mantém uma apresentação modal tipada. Estado dos menus não controla produção.

- [ ] Testar tap no card, long press, salvar, copiar e navegação modal consecutiva; nenhuma ação pode ser engolida por gesto sobreposto.
- [ ] Copiar header, menu e busca do V1 em componentes focados, conservando organização, símbolos, labels e animações previstas; retirar a toolbar simplificada equivalente do V2.
- [ ] Ligar destinos já implementados; ativar os demais juntamente com suas entregas T6–T11. Não expor caminhos temporários como versão final de paridade.
- [ ] Preservar animação explícita do header ligada ao scroll; resultado de rede/preparação não abre/fecha header ou lens.
- [ ] Conferir menu condicional, botão voltar, teclado, cancelamento de busca e feedback de copiar; rodar UI tests e atualizar matriz; commit `feat: port V1 reader shell and navigation`.

**Aceite:** mesma organização do frontend V1; transições mantêm feed e posição sob modais.

## T6 — Portar filtros e identidade dos contextos

**Files:** origens `FilterSheetView.swift`, `ContentFilterView.swift`, `TaxonomyChipBar.swift`, `Models/ContentFilter.swift`; criar `Sources/FeedMineDomain/ReaderFilter.swift`, `Sources/FeedMineUI/Filters/{FilterSheetView,ContentFilterView,TaxonomyChipBar,ReaderFilterStore}.swift`; modificar `FeedContext.swift`, `ReaderPreferencesStore.swift`, `RuntimeMigrations.swift`, `CandidateProvider.swift`, política editorial e `AppComposition.swift`; criar `Tests/FeedMineEditorialTests/ReaderFilterTests.swift`, ampliar testes de preferências/contextos.

**Interfaces:** `ReaderFilter` valor Codable/Hashable contém os critérios existentes no V1 inventariados em T1. Definir `ReaderFilterDraft` em UI, separado da seleção aplicada. `ReaderFilterStore.apply(_ draft: ReaderFilterDraft) async throws`; salvar e ativar um único pedido lógico. O desenho aprovado (formas de `ContextKey`/`ReaderFilter`/`ReaderFilterDraft`/`EditorialRevision`, onde cada estado mora, os testes exigidos e a correção do apply/cancel) está em `docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md` — executar por ele. ContextKey inclui filtros normalizados, preset e escopo de busca; editorial revision inclui versão efetiva da política e preferências.

- [ ] Testar apply/dismiss-applies/reset: editar draft não muda feed; **fechar o sheet aplica** (V1 não tem Cancel — `Views/FilterSheetView.swift:220-297`, com `presetIsDirty`/`overlayFiltersAreDirty` separados; correção registrada em `docs/superpowers/specs/2026-10-09-reader-filters-and-context-identity.md` §5); aplicar equivale a uma transição; fechar sem editar conserva seleção e posição.
- [ ] Testar idiomas, tipos, mood e taxonomia com fixtures reais de metadata; ausência de metadata não pode satisfazer um critério por invenção. Copiar semântica V1, incluindo combinação dos critérios.
- [ ] Testar A→B→A offline e callback atrasado de A durante B; contextos equivalentes por ordem dos sets têm mesma chave.
- [ ] Rodar testes novos para expor ausência de suporte e depois ampliar domínio, persistência/migração e resolução editorial; não aplicar filtro só sobre os cards já desenhados.
- [ ] Copiar controles e lens; ligar presets que T8/T11 fornecerão por IDs tipados. Preservar semântica de auto-expiração sem mudar cards da sessão por timer: expiração fica pendente até transição explícita de contexto.
- [ ] Rodar testes editorial/preferences/contexto e UI apply/cancel/reset; commit `feat: port V1 filters with durable context identity`.

**Aceite:** filtros funcionam no supply, têm o comportamento do V1 e não contaminam a apresentação ativa com callbacks de outro contexto.

## T7 — Catálogo, taxonomia e gestão de fontes

**Files:** origens de Sources na tabela e `Services/TaxonomyStore.swift`; criar Views correspondentes em `Sources/FeedMineUI/Sources/`, `Sources/FeedMineComposition/SourceManagementCoordinator.swift`, `Sources/FeedMinePersistence/SourceManagementStore.swift`; modificar importador de catálogo, preferências e migrações; criar `Tests/FeedMineCompositionTests/SourceManagementTests.swift`.

**Interfaces:** `SourceManagementCoordinator.search(_ query: String) async throws -> [SourceSummary]`, `setEnabled(_ id: SourceID, enabled: Bool) async throws`, `testHealth(_ ids: [SourceID]) async throws -> [SourceHealthResult]`. Definir valores UI-facing em Runtime, sem GRDB/connector expostos. Consultas taxonômicas paginadas por pai/cursor.

- [ ] Testar busca em catálogo grande, idiomas/país/região/categoria, enable/disable persistente e mapa de IDs estável; nenhuma enumeração completa do catálogo na main thread por frame.
- [ ] Testar seleção de zero fontes como estado explícito com UI do V1; não impor a regra atual “ao menos uma” se ela impedir paridade. Cancelamento de health test termina trabalho e preserva seleção.
- [ ] Copiar Views e queries puras úteis; mover saúde/acesso ao catálogo para o coordinator e stores; aquisição mantém scheduler/backoff existentes.
- [ ] Migrar metadados de taxonomia ausentes com importação idempotente, sem atribuir UUID novo a fonte já importada.
- [ ] Rodar testes escala/import/preferences e UI descoberta→fonte→feed; commit `feat: port V1 catalog and source management`.

**Aceite:** navegação de catálogo fiel e utilizável; seleção/offline funcionam; feed por fonte usa sessão do V2.

## T8 — Coleções, caixas de salvos e presets persistentes

**Files:** origens Collection/Bookmark na tabela e modelos associados; criar `Sources/FeedMineDomain/ReaderCollection.swift`, `ReaderBookmarkList.swift`, `ReaderPreset.swift`; stores específicos em Persistence, `Sources/FeedMineComposition/ReaderLibraryCoordinator.swift`, Views em Collections/Bookmarks; ampliar `RuntimeMigrations.swift` e testes de persistência/composição.

**Interfaces:** `ReaderLibraryCoordinator` executa `createCollection(name:)`, `renameCollection(id:name:)`, `setMembership(sourceID:collectionID:included:)`, `createBookmarkList(name:)`, `setBookmarkMembership(cardID:listID:included:)`, `activatePreset(_ preset: ReaderPreset)`; funções mutadoras `async throws`, criação retorna IDs definidos em Domain. Ordenação persistida e migração legada com mapa de IDs explícito.

- [ ] Criar testes CRUD, reordenação, caixa vazia, múltiplas caixas, apagar coleção sem apagar fonte/artigo e reabrir offline; falha transacional não deixa memberships parciais.
- [ ] Copiar regras de caixas/coleções e layouts, separando os feeds embutidos da View legada para sessões V2.
- [ ] Implementar tabelas e mappings, mantendo bookmark por ocorrência e referências à publicação congelada; não substituir UUID por IDs V1.
- [ ] Transferir Smart Bookmark/presets da busca e suas regras de persistência; ativação usa identidade de T6 e não outro motor de feed.
- [ ] Testar importação legada repetida/interrompida em cópia da base; duplicatas não aparecem e a origem permanece intacta.
- [ ] Rodar testes library/persistence e UI salvar→caixa→abrir→retornar; atualizar matriz; commit `feat: port V1 collections bookmarks and presets`.

**Aceite:** menus de organização executam ações reais, dados sobrevivem ao relaunch e retorno conserva posição.

## T9 — Leitor, mídia e compartilhamento

**Files:** origens Article/MiniPlayer/Share na tabela e `Services/AudioPlayerManager.swift`; criar UI correspondente e `Sources/FeedMineComposition/ReaderActionCoordinator.swift`, `ReaderMediaCoordinator.swift`; integrar `InteractionCoordinator.swift`, `InAppBrowser.swift` e host; criar testes de ações no app/composição.

**Interfaces:** `ReaderActionCoordinator.perform(_ action: ReaderCardAction) async throws`; resolver URL/payload a partir de PublicationCardID e ação congelada. Player com `play(cardID:) async throws`, `pause()`, estado UI-facing em Runtime. UIKit share/pasteboard e AVFoundation ficam em adapters de plataforma fora dos renderers.

- [ ] Testar abrir/copy/share usam target da ocorrência, mesmo se artigo canônico mudou; ação ausente não dispara fallback inventado.
- [ ] Copiar reader e player UI; ligar play/pause/retorno e falhas de mídia sem crescimento do card. Se necessário acrescentar suporte real à ação `mediaPlayback` antes de habilitá-la.
- [ ] Copiar templates de share; exportar artefato final local com dados reais. Testes não enviam mensagens nem publicam conteúdo.
- [ ] Testar gesto de imagem versus artigo, modal após modal, reader fechado e mini player com área reservada estável; Reduce Motion conserva funcionalidade.
- [ ] Rodar UI/actions tests e build iOS; commit `feat: port V1 article media and share flows`.

**Aceite:** artigo/player/share têm comportamento V1 e não introduzem rede ou resolução no card renderer.

## T10 — Preferências, idiomas, importação e exportação

**Files:** origens Settings/AddFeed/Export, `Services/{AppSettings,LocaleManager,OPMLParser}.swift`, recursos de localização; criar UI em Settings/ImportExport, `Sources/FeedMineDomain/ReaderSettings.swift`, `Sources/FeedMineComposition/ReaderSettingsCoordinator.swift`, `ReaderImportExportCoordinator.swift`; modificar stores/migrações e resources; testes de parser/import/settings.

**Interfaces:** settings persistem via `update(_ settings: ReaderSettings) async throws`. Importação em duas etapas: `previewImport(_ data: Data) async throws -> ReaderImportPreview`, `commitImport(_ preview: ReaderImportPreview) async throws -> ReaderImportResult`; exportação `export(_ request: ReaderExportRequest) async throws -> URL` retorna arquivo local. Tipos novos em Domain/Runtime conforme valor semântico versus projeção.

- [ ] Testar fontes duplicadas, OPML malformado, aninhado, unicode e cancelamento antes do commit; commit atômico e idempotente. Copiar parser puro se sua semântica passar os vetores de identidade V2.
- [ ] Testar export/import roundtrip para os formatos e escopos existentes no V1, incluindo coleção e caixa; preservar identidade URL/request URL e memberships.
- [ ] Copiar settings/localizações; manter todas as opções inventariadas, incluindo família de paleta, fonte, night mode e prefetch. Separar comportamento estrutural da aparência; mudanças por relógio não alteram o feed ativo.
- [ ] Migrar preferências legadas por chave com versão e defaults conhecidos; testar retomada e preservar dados se uma chave desconhecida existir.
- [ ] Ligar ações destrutivas com confirmação da UI do V1 e transações específicas; testes de reset não tocam dados pessoais reais.
- [ ] Rodar parser/settings/migration tests e UI configurações/import preview/export; commit `feat: port V1 settings and import export tools`.

**Aceite:** preferências funcionais, traduções preservadas e import/export produz arquivos utilizáveis sem recriar os serviços monolíticos.

## T11 — Onboarding, curadoria e estados de preparação

**Files:** origens Onboarding/Curated da tabela; copiar valores puros de recipe/preferences para Domain/Editorial; criar `Sources/FeedMineComposition/CuratedFeedCoordinator.swift`, persistência dedicada e UI Onboarding; integrar `FeedPreparationView.swift`, `PreparationProgress.swift`, `ColdFeedBootstrap.swift`; testes de receita/curadoria/composição/UI.

**Interfaces:** `CuratedFeedCoordinator.save(_ recipe: FeedRecipeDefinition) async throws -> ReaderPreset`, `inspect(_ preset: ReaderPreset) async throws -> CuratedFeedSummary`. Copiar e adaptar `FeedRecipeDefinition` para identidades V2; resolução de receita fica em Editorial, não na View. UI de preparação consome evidências reais de Runtime.

- [ ] Testar welcome→escolhas→duelos→salvar→feed, editar recipe e excluir curated preset; progressão/valores iguais ao V1 para as mesmas escolhas.
- [ ] Copiar cenas, controles, transições e onboarding tips; substituir chamadas ao loader por coordinator e prefs persistidas.
- [ ] Transferir resolução pura de receitas com testes determinísticos; preservar alternância de fontes e versões de política/contexto.
- [ ] Remover downloads de imagens dentro das Views portadas, inclusive ilustrações que mostram conteúdo real: receber assets preparados e evidências reais, sem headlines fictícias.
- [ ] Testar rede lenta/offline, cancelar/reiniciar e Reduce Motion; preparação concluída com feed ativo não muda a lista nem o viewport.
- [ ] Rodar recipe/cold/preparation tests e UI onboarding; commit `feat: port V1 curated onboarding and preparation experience`.

**Aceite:** primeira experiência e curadoria preservadas, sem animações alimentadas por dados fabricados e sem carregar outro motor editorial.

## T12 — Paridade completa, estabilidade física e retirada das duplicações

**Files:** criar `docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md`; atualizar matriz, PORT_LOG, README/IOS_RUN; ampliar `FeedMineUITests.swift`, `CompositionTests.swift`, testes de admissão; remover renderers/rotas substituídos e adapters temporários sem consumidores.

**Interfaces:** relatório por tarefa/superfície com SHA, comando, resultado, artefatos e diferenças aceitas. Um teste unitário não certifica estabilidade física; o gate exige gestos nativos e evidência no aparelho.

- [ ] Percorrer cada ação de T1 e marcar como validada apenas com fluxo funcional e comparação visual. Diferença funcional pendente impede declarar paridade total.
- [ ] Executar cenário integrado determinístico: fonte lenta, decode atrasado, material edit, retry e foreground enquanto o leitor está parado; snapshot/frame/offset permanecem estáveis e reserva cresce.
- [ ] Executar scroll nativo longo para baixo/cima, card alto, abertura/retorno de modal, A→B→A, teclado, rotação e Dynamic Type. Medir offset antes/depois das atualizações sem gesto, tolerância de 1 ponto no viewport inalterado.
- [ ] Em iPhone físico, observar 10 minutos parado e 30 minutos de scroll com redes heterogêneas; registrar memória/CPU/hitches e orçamento de mídia. Sem crescimento monotônico de memória nos últimos 20 minutos; não manter imagens decodificadas de todo o histórico.
- [ ] Verificar offline/relaunch com fonte/filtro/coleção/caixa e posição, importação interrompida e atualização de uma base V2 anterior; nenhum dado descartado.
- [ ] Remover código visual substituído e compatibilidade temporária, conferir ausência de FeedStore/FeedLoader legados e de I/O em Views; atualizar responsabilidade/imports reais dos arquivos alterados.
- [ ] Rodar regressão do pacote, build/test iOS e `git diff --check`; registrar resultados sem declarar checks não executados; commit `test: verify V1 frontend parity and stable scroll admission`.

**Aceite final:** UI V1 portada e funcional; reserva autônoma; novos cards admitidos pelo scroll; posição e estrutura preservadas; serviços menores com um dono por responsabilidade.

## Comandos de validação

Executar primeiro o filtro de teste da tarefa. Depois da entrega integrada, na raiz do V2:

```sh
swift build
swift test
git diff --check
xcrun simctl list devices available
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -showdestinations
```

Escolher UUID iOS 18+ real do resultado acima. `SIMULATOR_UUID` é variável da execução, não valor fixo deste plano. Usar result bundle novo por rodada:

```sh
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination "platform=iOS Simulator,id=$SIMULATOR_UUID" -derivedDataPath /tmp/feedmine-transfer-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination "platform=iOS Simulator,id=$SIMULATOR_UUID" -derivedDataPath /tmp/feedmine-transfer-derived -resultBundlePath "$TRANSFER_RESULT_BUNDLE" -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Conferir catálogo empacotado antes do build conforme README. Imagens e fixtures ficam locais aos testes para não depender de RSS público. Commits incluem apenas arquivos da entrega e docs correspondentes; verificar diff staged antes de confirmar.

## Marcos e revisão do plano

- **M1: T1–T3:** contrato de estabilidade demonstrado antes da transferência visual.
- **M2: T4–T6:** feed principal com design, menus e filtros do V1.
- **M3: T7–T10:** catálogo, biblioteca, leitor e ferramentas completos.
- **M4: T11–T12:** onboarding/curadoria e paridade integral validada.

Sem estimativa de dias antes do inventário e da reprodução física de T2/T3. As dependências faltantes de catálogo, presets, mídia e importação são trabalho explícito do plano; não podem ser ocultadas como “só adaptar a View”.

Autorrevisão: requisitos do usuário mapeados; todas as famílias de Views identificadas têm entrega; barreira separa publicação de admissão; T3 cobre navegação para trás e custo de memória; cinco riscos de Review Focus possuem provas; APIs novas identificadas como propostas; decisão de aparência preserva opções V1 e congela estrutura; macOS e migrações incluídos. T1 fecha o inventário fino de controles condicionais antes da execução das transferências.
