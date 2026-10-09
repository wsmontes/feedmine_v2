# FeedMine — revisão comparativa de código: `feedmine-dev` × `feedmine_v2`

**Data de referência:** 9 de outubro de 2026.  
**V1:** [`wsmontes/feedmine-dev`](https://github.com/wsmontes/feedmine-dev/tree/b5c2f59c55babb672c81dd978d201f98c5909934), `main@b5c2f59c55babb672c81dd978d201f98c5909934` (18 set. 2026).  
**V2:** [`wsmontes/feedmine_v2`](https://github.com/wsmontes/feedmine_v2/tree/880191fc9a7156ad4e5c89da1012da67d9e9a151), `main@880191fc9a7156ad4e5c89da1012da67d9e9a151` (9 out. 2026).  
**Método:** inspeção remota das árvores completas, dos códigos críticos de ambos os repositórios, das declarações e rotas de dezenas de arquivos Swift do V1, dos módulos centrais do V2, dos testes exemplares e da documentação de arquitetura/execução. O apêndice é um **inventário individual com mapa funcional**, não uma alegação de inspeção integral linha-a-linha de todo arquivo. Sem checkout executável local, não rodei Swift/Xcode, profiler nem testes em dispositivo. Distingo **implementação observada**, **teste relatado** e **hipótese a medir**. Arquivos de dados binários, milhares de OPMLs, scripts do corpus e fixtures não foram submetidos a auditoria de conteúdo individual.

## A. Resultado executivo

**A V2 é uma fundação técnica mais coerente; o V1 ainda é um produto funcionalmente muito maior.** A arquitetura nova corrige a centralização extrema de `FeedStore`/`FeedLoader`/`FeedScreen`, separa aquisição, seleção, publicação imutável e leitura local, usa histórico transacional e possui mídia local antes do render. O V1 possui seleção editorial, catálogo navegável, importação OPML, pesquisa local, filtros, coleção/playlist de fontes, podcasts, bookmarks organizados, exportação, idioma, onboarding e mecanismos de validação de release que a UI V2 ainda não oferece.

**Armadilha:** portar cada serviço V1 reintroduziria duplicidade, estado concorrente e caches paralelos. A migração adequada é preservar *capacidade e semântica* na arquitetura V2, não copiar os antigos subsistemas.

| Métrica da árvore do GitHub | `feedmine-dev` | `feedmine_v2` |
| --- | ---: | ---: |
| Entradas totais | 2.388 | 285 |
| Arquivos Swift | 177 | 199 |
| Repositório | V1, com grande corpus e tooling editorial | V2, módulos SwiftPM e testes especializados |
| Execução comprovada nesta revisão | Não | Não |
| Execução relatada em docs do repo | Build 17 e métricas de dispositivo no V1 | 827 testes Swift sem falhas; 15 testes app + 3 XCUI em simulador **para `f8eb67e`**; HEAD posterior contém commits ainda não comprovados pelas mesmas evidências |

### Decisão de produto

1. **Manter** a arquitetura canônica → seleção → publicação → sessão → UI da V2.
2. **Fechar a runway adaptativa real:** o novo piso `reserveCards` é avanço, mas está configurado por uma capacidade de janela de 16 cards, não por cobertura visual, consumo variável e latência de aquisição/preparação do usuário. Tratar piso como proteção, não como prova de feed infinito.
3. **Restaurar funcionalidades V1 de maior valor:** curadoria inicial, escolha ampla de fontes/taxonomia, múltiplos contextos, bookmarks/coleções, OPML import/export, pesquisa e mídias específicas.
4. **Eliminar o risco de regressões no fluxo inteiro:** testes Swift passando são evidência de contratos, mas não substituem provas de sessão prolongada, cold/warm/offline, troca de contexto e aparelho real.

## B. Funcionalidades do produto — mapa de paridade

| Capacidade | V1 (código) | V2 em `880191f` | Decisão |
| --- | --- | --- | --- |
| RSS/Atom/JSON Feed | `RSSFetcher`, `FeedHTTPSync` | `SyndicationConnector`, `SyndicationHTTP`, `SyndicationTranslator` | **Reimplementado**; manter semânticas de formatos/validadores, testar feeds reais |
| Catálogo de 88 mil fontes | `OPMLParser`, `SQLiteCatalogStore`, tooling editorial | `LegacyCatalogReader`, `LegacyCatalogImport`, asset de release + `fetch-catalog.sh` | **Parcial:** leitura/consulta e seleção inicial; compilação/update/taxonomia UI ausentes |
| Atualização remota de catálogo assinado | `CatalogUpdateService` | Não encontrei serviço equivalente em Runtime/composição | **Não portado**; decidir atualização a partir da distribuição v2 |
| Escolha de fontes | `SourceRegistry`, `SourceManagementView` | `ReaderPreferencesStore`, `FeedSourcePicker`, `TrustedFeed.resolve` | **Parcial:** busca/seleção de fontes implementada; gestão profunda não |
| Filtros de região, tópico, idioma, formato, humor, keyword | `FeedLoader`, `FeedStore`, `FilterSheetView`, `ContentFilterStore` | ".main"/".source" e fontes selecionadas; busca local limitada | **Lacuna de produto** |
| Feed composto por score/editorial preferências | `CuratedPreferenceEngine`, `PresetScorer`, `FeedRecipeResolver` | `SelectionEngine` (source alternation, recency) | **Parcial:** diversidade simples, personalização V1 ausente |
| Onboarding com escolhas/duelos | `CuratedOnboardingView` e `Views/Onboarding/*` | `FeedPreparationView` (loading, não onboarding) | **Não portado** |
| Fonte única e coleção de fontes | `SourceCollectionFeedView`, smart feeds | `.source`, `.main`, preferências persistidas | **Parcial:** coleção customizada não implementada |
| Busca conteúdo/artigos FTS5 | `SearchEngine`, User DB, local records | contexto `.search` local e busca de fontes; conferir escopo/UX | **Parcial:** sem busca unificada V1 ou termos avançados |
| Bookmarks | `BookmarkStore`, listas e buscas salvas | bookmark card em `PublicationStore`, UI de toggle | **Parcial:** pin simples existe, listas/gestão/export ausentes |
| Leitura de artigo | `ArticleReaderView` WKWebView | abrir URL congelada externamente pelo app | **Parcial:** navegação funciona, leitor integrado ausente |
| Podcasts/audio playback | `AudioPlayerManager`, `MiniPlayerBar` | tipo de ação/media no modelo, sem player funcional | **Não portado** |
| Vídeo, fórum, múltiplos formatos | `MediaKind`, RSS extraction, UI badges | catálogo inicial seleciona 4 fontes text RSS | **Não portado no produto** |
| Imagens locais prontas | `MediaAssetStore`, card preparation, múltiplos caches | `MediaPrefetcher`, `AssetStore`, `PresentationImageDecoder` | **Reimplementado com fronteiras melhores** |
| Atualização de card após mídia tardia | V1 mutava e sofria layout jumps | V2 publicação congelada; hidden-tail lease enquanto invisível | **V2 superior conceitualmente; validar tela visível** |
| Feed contínuo sem fim prematuro | V1 reservatório + diversos schedulers, falhas observadas | V2 runway com piso + métricas e produção local | **Ainda exige teste de produto**; piso fixo não equivale a adaptatividade plena |
| Reuso após troca de filtros | V1 cache por assinatura de filtro, histórico de bugs | V2 Editions por contexto, checkpoint, seleção versionada | **V2 melhor desenho; testar A→B→A e alterações rápidas** |
| Exportar/Importar OPML/backup/CSV | `ImportPipeline`, `ExportEngine`, Views | sem fluxo de UI correspondente | **Não portado** |
| Acessibilidade, idiomas, tema | `LocaleManager`, `DesignTokens`, `CircadianEngine`, UITests | labels básicos, Reduce Motion no loading | **Parcial** |
| Observabilidade/lançamento | `FeedMineSignposts`, planos/XCUITest | testes especializados, logs e doc OMP | **Parcial:** prova real de performance ainda depende de simulador/aparelho |

## C. Achados de code review — ordenados por impacto

### R01 — P0 / Lacuna de produto — O piso da runway ainda está acoplado a 16 cards de janela

**V1:** `feedmine/Services/FeedRunwayController.swift`, `RunwayPolicy.swift`, `AdaptiveScheduler.swift`, `CardPreparationCoordinator.swift`, `Reservoir.swift`. **V2:** `Sources/FeedMineRuntime/RunwayPolicy.swift` e `FeedMineApp/FeedMineApp/AppComposition.swift` (`resources`). O V2 introduziu `reserveCards` para suprir a falta de pressão com leitor estacionário; o app fixa esse piso pelo `forwardCapacity` da apresentação (16), enquanto a política de consumo usa cards/segundo × p95 local. Isso é claramente superior ao estado pré-revisão, mas ainda não prova reserva suficiente para cards de alturas diferentes, imagens pesadas, fontes lentas ou leitores rápidos. Os limites de janela são legítimos; **usar o mesmo número como garantia de cobertura do produto não é**. Medir cobertura visual (altura restante / viewport), velocidade efetiva e custos de reabastecimento, sem criar outro pipeline. Prova: scroll prolongado com fontes de latência variável, sem atingir tail prematuramente.

### R02 — P0 / Paridade de produto — V2 ainda não substitui o leitor V1 em capacidades centrais

`AudioPlayerManager`, `MiniPlayerBar`, `ImportPipeline`, `ExportEngine`, `BookmarkStore` com listas, `ContentFilterStore`, `CuratedPreferenceEngine`, `SearchEngine` unificado e UI de catálogo/taxonomia não têm equivalentes finais no V2. Isso não significa portar sua implementação: é preciso definir recorte de release. Se release V2 prometer podcasts/filtragem/coleções como V1, há perda funcional comprovável. Se V2 for um MVP de notícias RSS, formalizar recorte, não camuflar como paridade.

### R03 — P1 / Escalabilidade — A seleção de fontes ainda não representa o corpus amplo

O release catalog completo é distribuído externamente (asset de 117.940.224 bytes (~118 MB), checksum SHA-256 e script `scripts/fetch-catalog.sh`), não embutido no git. `TrustedFeed.catalog` monta um starter set com quatro URLs predefinidas; `FeedSourcePicker` consulta o banco mediante busca textual. A escolha ampla de fontes existe como operação, mas não como experiência editorial completa de explorar a taxonomia, identificar regiões/línguas/categorias e selecionar diversidade contextual. **Não repetir o V1 carregando dezenas de milhares de fontes na MainActor**. O catálogo deve operar como índice local, ativando um subconjunto operacional por contexto.

### R04 — P1 / Lifecycle e contexto — evitar descarte de trabalho útil em alterações rápidas

V1: `FeedDisplayState.cacheVisiblePageIfNeeded/restoreCachedPage`, `PreparedPageRestoration`; houve bugs de cache vinculado à página errada e reconstrução após filter switch. V2: `ReaderPreferencesStore`/`SessionStore` persistem seleção e checkpoints por contexto, `AppComposition.selectContext` retira a associação atual e instancia outra, e `HiddenTailMaintenance` autoriza trocas de cauda não vista por lease. Há testes relatados de A→B→A. Ainda é preciso medir switching rápido durante HTTP/mídia pendente: não destruir o supply canônico nem cards publicados reutilizáveis; não permitir callback antigo alterar a nova apresentação; preservar contexto recente sem reprocessamento gratuito.

### R05 — P1 / Mídia — V2 remove concorrência de caches, mas precisa provar economia após relançamento

O V1 possuía ao mesmo tempo `ImageCache`, `DiskImageCache`, `MemoryImageCache`, `ImageLoader`, `ImagePrefetcher`, `ImageResolutionQueue`, `MediaAssetStore` e resoluções em `FeedStore`, com ownership conflitante. V2 consolida download/preparation em `MediaPrefetcher`/`AssetStore`, decoding de apresentação em `FeedSession`. **Conquista arquitetural real.** Porém `MediaReadiness` é um índice em memória (mapa por `OriginRevisionID`); após recriar a associação, a preparação de revisions futuras pode precisar buscar de novo mídia previamente persistida se a correspondência remota→asset não estiver disponível. Validar com contagem de requests; não criar cache redundante antes de medir.

### R06 — P1 / Paridade RSS e mídia — a V1 tratava audio/video/enclosures com mais riqueza

`feedmine/Services/RSSFetcher.swift` extrai enclosures, autores, categorias, links alternativos, podcast durations, WebSub e valida áudio. V2 `SyndicationTranslator` preserva texto e candidatos visuais, mas a apresentação de `mediaPlayback` e player não fecha o fluxo. Garantir que adicionar esses tipos ocorra pela mesma fronteira Connector→Domain→Publication, não por um segundo feed pipeline.

### R07 — P1 / Busca — catálogo local não é a busca unificada do V1

`feedmine/Services/SearchEngine.swift` implementava termos, itens salvos, fontes e local cache com FTS; V2 possui lookup por texto de catálogo e caminho `.search` de conteúdo local, mas não entrega a mesma UI para todos os escopos, operadores e buscas persistentes. A decisão de produto deve diferenciar: escolher uma fonte, procurar conteúdo e filtrar feed. São três operações diferentes; não misturar responsabilidades na UI nem no Connector.

### R08 — P1 / Identidade e republicação — respeitar versão material, mídias e seen high-water

O V1 tinha bugs de GUID, links com tracking, variação de datas e mídia tardia; o V2 tem `ContentLocatorIdentity`, `MaterialContentIdentity`, `SelectionExposure`, Transactional Publication e `HiddenTailMaintenance`. Essa é a direção correta. Testar replay idempotente, link tracking vs link significativo, mesmo GUID/data com texto editado, mídia principal mudada, edição repetida antes de ser vista e mudança de membership/disponibilidade durante uma lease. O uso de origens/memberships e a proibição de mudar seen cards são invariantes superiores às heurísticas antigas.

### R09 — P1 / Cold start — prova de primeira tela não depende mais do feed mais lento; medir experiência real

`ColdFeedBootstrap` agora emite `.published` quando uma fonte contribui e a primeira publicação elegível se completa, embora o aggregate fetch possa continuar. `AppComposition` recebe a evidência e instala cedo. Há resultados relatados em simulator. Persistem perguntas de produto: quanto tempo até card realmente visual, quantas fontes contribuem, mídia preparada, tempo de UI, operação offline; nenhum timeout fixo representa isso sozinho. O loading V2 com evidências reais é avanço, mas a estimativa de término ainda usa média simples de settle e não prontidão editorial.

### R10 — P1 / Escolha de arquitetura — componentes V1 não devem ser migrados como estão

`FeedStore.swift` (~8.293 linhas), `FeedLoader.swift` (~1.701), `FeedScreen.swift` (~1.891), `CuratedPreferenceEngine.swift` (~1.104) acumulavam regras de múltiplos owners. `Reservoir` reordenava candidatos e `EditorialSequencer` fazia reparo de diversidade, violando owner único. V2 usa `SelectionEngine` e `SourceAlternation`. Recuperar diversidade, tópicos e relevância como política *dentro* de Editorial; não importar `Reservoir`, não reintroduzir `NotificationCenter` para comandos, não acumular flags de loading nem múltiplos stores.

### R11 — P2 / SQL e memória — avaliar custo de queries com 77 mil fontes e supply volumoso

No V1, `FeedStore`, `SQLiteCatalogStore`, `SourceRegistry` e `TaxonomyStore` tiveram reparos de consultas e tarefas pesadas na MainActor. V2 tem SQLite/GRDB em Persistence, índices por origem, janela canônica e pesquisa de catálogo por título/prefix/quality score. O V2 afirma provas de 100 mil registros com paginação por índice; ainda é teste, não perfil do dispositivo. Medir N+1 por item, tamanho do bundle, memória de materialização, custo do rescan de favoritos e latência de abertura de fonte; evitar varredura global para um único contexto filtrado.

### R12 — P2 / Release — evidência testada não cobre integralmente HEAD atual

`docs/reviews/OMP_VALIDATION_2026-10-09.md` registra `swift test`: **827/0**, testes iOS **15 integração + 3 XCUI/0** no **commit `f8eb67e`**, e Release simulador. O HEAD `880191f` acrescenta distribuição de catálogo como asset assinado por checksum, ranking de busca de fonte e docs. O repositório diz explicitamente que o último round ainda não foi recompilado/testado após essas alterações. Antes de TestFlight: executar `scripts/fetch-catalog.sh`, verificação de SHA/tamanho, testes Swift + iOS em clone limpo, comparação de release bundle, scroll prolongado no iPhone e memória/energia/térmica.

### R13 — P2 / Testes e UX — preservar asserts fortes e ampliar jornadas

O V1 tinha testes abrangentes de catálogo, performance, filtros, scroll, acessibilidade e persona, mas também planos que executavam subconjuntos e testes tolerantes que podiam passar sem exercitar a UI. O V2 tem mais testes Swift especializados e proteção transacional; faltam provas em aparelho real e jornadas de usuário completas. O gate adequado mistura invariantes puras com cenários integrados que realmente navegam, salvam, trocam contexto, vão offline e voltam, sem `guard exists else return` escondendo ausência da funcionalidade.

### R14 — P2 / Operação de catálogo — distribuição não equivale a ciclo de atualização

V1 `CatalogUpdateService` verificava manifesto assinado, staged download e ativação segura do catálogo. V2 usa um asset de release e script de preparação do checkout; isso cobre a construção/distribuição inicial, **não** uma atualização de catálogo em runtime. Como não há servidor próprio, atualizar via releases/remotos públicos é conceitualmente possível, mas deve preservar rollback, assinatura/checksum e identidade de fontes. Não introduzir auto-atualização sem decisão de produto.

## D. Contratos de migração que devem ser testados

| Cenário | Invariante | V1 de referência | V2 de destino |
| --- | --- | --- | --- |
| 90 min de scroll com latência variável | Nunca chegar ao fim por falta de produção evitável; sem reordenar visível | `Reservoir`, `AdaptiveScheduler`, `FeedRunwayController` | `RunwayController`, `RunwayPolicy`, `FeedRunwayDriver` |
| Parar de rolar por 2 min | Reserva prepara sem depender de novo gesto, dentro de recurso real | Schedulers e prep não tinham owner único | `reserveCards` + driver, expansão adaptativa pendente |
| Mudar A→B→A | Mesmo histórico e ponto de leitura, sem re-fetch gratuito | filtro/page-cache | `ReaderPreferencesStore`, `SessionStore`, `FeedSession` |
| Abrir online, relançar offline | Janela local se apresenta antes de HTTP | `FeedDisplayState`, `PreparedPageRestoration` | `FeedSession.restoreLocalPresentation` |
| Fonte 404/timeout e outra rápida | Rápida não bloqueada; backoff da ruim | `RSSFetcher.fetchAll`, `AdaptiveScheduler` | `AcquisitionCoordinator`, `AcquisitionBackoff`, cold callbacks |
| Alterar título e mídia sob mesmo GUID/data | Republicação material, sem duplicação indevida | `FeedItem.generateID` | `ContentLocatorIdentity`, `MaterialContentIdentity`, `PublicationStore` |
| Media chega depois de texto | Card visto imutável; future tail pode melhorar sem salto | `CardPreparationCoordinator` upgrade tardio | `HiddenTailMaintenance` + lease + `FeedSession` |
| Fonte exclusiva com poucas notícias | Em `.source`, não exigir alternância impossível | Source feed V1 | `SelectionEngine.isSingleSource` |
| Milhares de fontes disponíveis | Seleção limitada e justa, sem carregar tudo | `SQLiteCatalogStore`, `SourceRegistry` | `LegacyCatalogReader`, `TrustedFeeds`, acquisition planner |
| Podcast com enclosure | Playback, retomar, lock-screen e posição | `AudioPlayerManager`, `MiniPlayerBar` | A implementar no mesmo Domain/Runtime, sem pipeline secundária |
| OPML export→import | IDs estáveis, URLs assinadas preservadas | `OPMLParser`, `ImportPipeline`, `ExportEngine` | A implementar sobre catálogo + reader preferences |
| Background com baixa memória | Não perturbar tela nem destruir bookmarks | caches antigos/mutações difíceis | `MediaTidy`, `MediaRetention`, stored media usage |

## E. Inventário V1 → V2, arquivo por arquivo

Esta matriz contém os arquivos Swift de **produção** do V1, classificados pela responsabilidade atual: **Reestruturado** = comportamento/conceito transformado em módulo novo; **Parcial** = parte da função entregue; **Ausente** = ainda não exposto como capacidade correspondente; **Substituído** = mecanismo antigo não deve voltar; **Scaffold** = superfície ainda não executável. Cada linha aponta para o arquivo V1 e para o destino lógico V2 quando existente. A análise profunda focaliza as rotas críticas; para arquivos de UI auxiliares a classificação é de *paridade da função*, não acusação de bug.

### E.1 — App e modelo de conteúdo

| Arquivo no V1 | Migração | Destino/correspondente V2 | Observação específica |
|---|---|---|---|

| [`ContentView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/ContentView.swift) | Legado não migrar | [`FeedMineApp.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineApp/FeedMineApp.swift) | Wrapper morto no V1; não recriar segunda composição |

| [`feedmineApp.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/feedmineApp.swift) | Reestruturado | [`FeedMineApp.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineApp/FeedMineApp.swift) | App root com cinco serviços, notificações e lifecycle virou AppComposition explícita |

| [`ActiveSearch.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/ActiveSearch.swift) | Ausente | — | Busca persistente V1 ainda sem produto V2 |

| [`BookmarkList.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/BookmarkList.swift) | Parcial | [`PublicationStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/PublicationStore.swift) | Bookmark simples portado; listas não |

| [`ContentFilter.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/ContentFilter.swift) | Ausente | — | Filtros keyword/template e contadores não portados |

| [`Country.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/Country.swift) | Ausente | — | Geografia e catálogo por país não representados na UI V2 |

| [`CuratedFeed.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/CuratedFeed.swift) | Ausente | [`EditorialPolicy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/EditorialPolicy.swift) | Perfis de aprendizado/duelos não portados |

| [`FeedCardPresentation.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedCardPresentation.swift) | Reestruturado | [`PresentationCard.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PresentationCard.swift) | Valor de apresentação imutável e imagem local no V2 |

| [`FeedFetchBatch.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedFetchBatch.swift) | Reestruturado | [`AcquisitionBatch.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionBatch.swift) | Lotes com admission/receipts transacionais |

| [`FeedFetchResult.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedFetchResult.swift) | Reestruturado | [`AcquisitionCoordinator.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionCoordinator.swift) | Resultado de execução por alvo |

| [`FeedItem.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedItem.swift) | Reestruturado | [`Content.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/Content.swift) | Monólito de item de feed separado em OriginRecord/Revision/Publication |

| [`FeedPresentationContext.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedPresentationContext.swift) | Reestruturado | [`FeedContext.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/FeedContext.swift) | Contextos com Edition e cursor persistidos |

| [`FeedPreset.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedPreset.swift) | Ausente | [`EditorialPolicy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/EditorialPolicy.swift) | Smart feed e presets editoriais ausentes |

| [`FeedRecipeDefinition.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedRecipeDefinition.swift) | Ausente | — | Preferências por tema/media não portadas |

| [`FeedSource.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedSource.swift) | Reestruturado | [`Source.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/Source.swift) | Fonte e permissões/memberships explícitas |

| [`FetchOutcome.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FetchOutcome.swift) | Reestruturado | [`AcquisitionModels.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionModels.swift) | Resultado operacional de fonte no coordinator |

| [`HTTPValidators.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/HTTPValidators.swift) | Reestruturado | [`SyndicationHTTP.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineSyndication/SyndicationHTTP.swift) | Conditional GET/checkpoint sob Connector |

| [`ImageResolutionRecord.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/ImageResolutionRecord.swift) | Reestruturado | [`PublishedMedia.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/PublishedMedia.swift) | Mídia por key/asset, sem reescrever card visível |

| [`OPMLParseResult.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/OPMLParseResult.swift) | Ausente | — | Importação OPML de usuário ausente |

| [`OnboardingSeed.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/OnboardingSeed.swift) | Ausente | — | Sem preferência inicial/intenção V1 |

| [`PreparedFeedCard.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/PreparedFeedCard.swift) | Reestruturado | [`PublicationPreparation.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PublicationPreparation.swift) | Preparação antes da publicação, não cache separado mutável |

| [`Region.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/Region.swift) | Ausente | — | Navegação e seleção geográfica não expostas |

| [`TaxonomyNode.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/TaxonomyNode.swift) | Parcial | [`LegacyCatalogReader.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/LegacyCatalogReader.swift) | Nós de catálogo consultáveis, sem experiência V1 de taxonomia |

### E.2 — FeedEngine e catálogo

| Arquivo no V1 | Migração | Destino/correspondente V2 | Observação específica |
|---|---|---|---|

| [`CatalogBrowserViewModel.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/CatalogBrowserViewModel.swift) | Ausente | [`FeedSourcePicker.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedSourcePicker.swift) | Picker textual não substitui navegação hierárquica |

| [`CatalogIdentity.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/CatalogIdentity.swift) | Reestruturado | [`LegacyCatalogImport.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/LegacyCatalogImport.swift) | SHA-256 namespace UUID estável; precisa vetores de equivalência |

| [`CatalogInput.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/CatalogInput.swift) | Ausente | — | Compilação de catálogo não roda no V2 |

| [`CatalogModels.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/CatalogModels.swift) | Parcial | [`LegacyCatalogReader.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/LegacyCatalogReader.swift) | Registro fonte, sem timeline/browse DTO completo |

| [`CatalogProtocols.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/CatalogProtocols.swift) | Parcial | [`LegacyCatalogReader.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/LegacyCatalogReader.swift) | Contratos do V1 de browse/compile/timeline não transpostos integralmente |

| [`Identities.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/Identities.swift) | Reestruturado | [`FeedIdentifiers.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/FeedIdentifiers.swift) | Identidades tipadas, revisar crosswalk |

| [`OPMLCatalogScanner.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/OPMLCatalogScanner.swift) | Ausente | — | Scans e construção OPML ficam no tooling externo, não Runtime V2 |

| [`Pagination.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/Pagination.swift) | Reestruturado | [`LegacyCatalogReader.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/LegacyCatalogReader.swift) | Paginação limitada e cursor; diferentes schemas |

| [`SQLiteCatalogStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/SQLiteCatalogStore.swift) | Parcial | [`LegacyCatalogReader.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/LegacyCatalogReader.swift) | V2 read-only + search parcial; compilador/browse hierárquico não portados |

### E.3 — Services — pipeline, scheduling e publicação

| Arquivo no V1 | Migração | Destino/correspondente V2 | Observação específica |
|---|---|---|---|

| [`AdaptiveScheduler.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/AdaptiveScheduler.swift) | Reestruturado | [`AcquisitionPlanner.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionPlanner.swift) | Backoff/justiça distribuídos entre Planner/Coordinator; qualidade/cadência V1 ausentes |

| [`AsyncLimiter.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/AsyncLimiter.swift) | Reestruturado | [`AcquisitionCoordinator.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionCoordinator.swift) | Bounded concorrência de operações por target |

| [`BackgroundRefreshService.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/BackgroundRefreshService.swift) | Scaffold | [`BackgroundFeedRefresh.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/BackgroundFeedRefresh.swift) | Entrada de background ainda declarativa no V2 |

| [`CardPreparationCoordinator.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CardPreparationCoordinator.swift) | Reestruturado | [`MediaPrefetcher.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/MediaPrefetcher.swift) | Owner media e Publication separados; não copiar waiters/late upgrade V1 |

| [`CardPreparationPipeline.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CardPreparationPipeline.swift) | Reestruturado | [`PublicationPreparation.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PublicationPreparation.swift) | Preparação congelada ao publicar |

| [`EditorialSequencer.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/EditorialSequencer.swift) | Reestruturado | [`SourceAlternation.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/SourceAlternation.swift) | Regra central V2 por Source; evitar reparo downstream |

| [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Reestruturado | [`FeedSession.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/FeedSession.swift) | Janela/revisão local por Edition, em vez de page cache mutável |

| [`FeedHTTPSync.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedHTTPSync.swift) | Reestruturado | [`SyndicationHTTP.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineSyndication/SyndicationHTTP.swift) | Requests limitadas, redirects validados, conditional fetch |

| [`FeedLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedLoader.swift) | Reestruturado | [`FeedScreenStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedScreenStore.swift) | ViewModel grande reduzido; funcionalidades espalhadas/ausentes |

| [`FeedMetrics.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedMetrics.swift) | Parcial | [`RunwayController.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/RunwayController.swift) | Modelo de métricas implícito; signposts menos ricos |

| [`FeedMineSignposts.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedMineSignposts.swift) | Ausente | — | OSSignposter e métricas XCTest V1 não recuperadas em forma equivalente |

| [`FeedRecipeResolver.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedRecipeResolver.swift) | Ausente | [`FeedPlanResolver.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/FeedPlanResolver.swift) | Resolver V2 é fronteira, não receita personalizada V1 |

| [`FeedRunwayController.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedRunwayController.swift) | Reestruturado | [`RunwayController.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/RunwayController.swift) | Runway sobre história local; piso atual não basta para provar infinito adaptativo |

| [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Substituído | [`ContentStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/ContentStore.swift) | God store foi dividido entre 8+ módulos; manter essa separação |

| [`PreparedPageRestoration.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/PreparedPageRestoration.swift) | Reestruturado | [`FeedSession.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/FeedSession.swift) | Restore Edition/window sem cache semântico adicional |

| [`PresetScorer.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/PresetScorer.swift) | Ausente | [`SelectionEngine.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/SelectionEngine.swift) | Scoring V2 ainda equal; pesos curados não portados |

| [`ReadyCardQueue.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ReadyCardQueue.swift) | Substituído | [`PublicationHistory.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/PublicationHistory.swift) | Autoridade é história publicada, não segunda fila semântica |

| [`Reservoir.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/Reservoir.swift) | Substituído | [`SelectionEngine.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/SelectionEngine.swift) | Não portar reservoir: ordering, dedup e trim estavam misturados |

| [`RSSFetcher.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/RSSFetcher.swift) | Parcial | [`SyndicationTranslator.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineSyndication/SyndicationTranslator.swift) | Texto RSS/Atom/JSON sim; podcast/áudio/WebSub sem produto equivalente |

| [`RunwayMetrics.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/RunwayMetrics.swift) | Reestruturado | [`RunwayPolicy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/RunwayPolicy.swift) | Consumo+replenishment local; métricas de produto faltam |

| [`RunwayPolicy.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/RunwayPolicy.swift) | Reestruturado | [`RunwayPolicy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/RunwayPolicy.swift) | Pure policy nova; incorporar geometria real e latência fim-a-fim |

| [`SourceScheduler.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/SourceScheduler.swift) | Substituído | [`AcquisitionPlanner.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionPlanner.swift) | Eliminar mecanismo concorrente com AdaptiveScheduler do V1 |

### E.4 — Services — mídia, usuário, catálogo e discovery

| Arquivo no V1 | Migração | Destino/correspondente V2 | Observação específica |
|---|---|---|---|

| [`AppSettings.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/AppSettings.swift) | Parcial | [`ReaderPreferencesStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/ReaderPreferencesStore.swift) | Fontes/contexto persistidos; controles extensos ausentes |

| [`AudioPlayerManager.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/AudioPlayerManager.swift) | Ausente | — | Playback podcast, sessão AVAudio e posição não portados |

| [`BookmarkStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/BookmarkStore.swift) | Parcial | [`PublicationStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/PublicationStore.swift) | Toggle pin/uso de mídia, sem listas/busca persistente |

| [`CatalogUpdateService.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CatalogUpdateService.swift) | Ausente | [`fetch-catalog.sh`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/scripts/fetch-catalog.sh) | Script instala bundle no desenvolvimento; sem atualização assinada dentro do app |

| [`CircadianEngine.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CircadianEngine.swift) | Ausente | — | Tema/typography adaptativa de horário ausente |

| [`CuratedPreferenceEngine.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CuratedPreferenceEngine.swift) | Ausente | [`EditorialPolicy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/EditorialPolicy.swift) | Onboarding aprendizado/curadoria ausente |

| [`DesignTokens.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/DesignTokens.swift) | Ausente | [`FeedCardView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedCardView.swift) | UI v2 ainda sem sistema visual semântico equivalente |

| [`DiskImageCache.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/DiskImageCache.swift) | Substituído | [`AssetStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/AssetStore.swift) | Uma autoridade de asset local por hash |

| [`ExportEngine.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ExportEngine.swift) | Ausente | — | Backup, OPML, CSV, HTML, Markdown export ausentes |

| [`FeedEngineCatalogDiagnostics.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedEngineCatalogDiagnostics.swift) | Ausente | — | Diagnósticos do catálogo V1 não integrados |

| [`ImageCache.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImageCache.swift) | Substituído | [`MediaPrefetcher.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/MediaPrefetcher.swift) | Não portar ArticleImageResolver paralelo por padrão |

| [`ImageLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImageLoader.swift) | Substituído | [`PresentationImage.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PresentationImage.swift) | Decode local pré-UI na V2 |

| [`ImagePrefetcher.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImagePrefetcher.swift) | Substituído | [`MediaPrefetcher.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/MediaPrefetcher.swift) | Single-flight de mídia, não pipeline adicional |

| [`ImageResolutionQueue.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImageResolutionQueue.swift) | Substituído | [`MediaPrefetcher.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/MediaPrefetcher.swift) | Não migrar fila de polling/estado duplicado; testar retry durável |

| [`ImportFileStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImportFileStore.swift) | Ausente | — | Acesso a documento/import do usuário ausente |

| [`ImportPipeline.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImportPipeline.swift) | Ausente | — | OPML/URLs/feed discovery e import de usuário ausentes |

| [`InputParser.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/InputParser.swift) | Ausente | — | Classificação de URL livre ausente |

| [`LocaleManager.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/LocaleManager.swift) | Ausente | — | Seletor de idiomas/RTL avançado ausente |

| [`Log.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/Log.swift) | Reestruturado | [`AppComposition.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineApp/AppComposition.swift) | OSLog no app; observabilidade de produto ainda parcial |

| [`MediaAssetStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/MediaAssetStore.swift) | Substituído | [`AssetStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/AssetStore.swift) | Unificar download/asset, segurança antes do decode |

| [`MemoryImageCache.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/MemoryImageCache.swift) | Substituído | [`PresentationImage.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PresentationImage.swift) | Sem segundo cache semântico; medir re-decodes |

| [`NetworkMonitor.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/NetworkMonitor.swift) | Reestruturado | [`AppComposition.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineApp/AppComposition.swift) | NWPathMonitor em DeviceMediaConditions/NetworkPathObserver |

| [`OPMLParser.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/OPMLParser.swift) | Parcial | [`LegacyCatalogReader.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/LegacyCatalogReader.swift) | Catálogo SQLite presente; parser/import OPML de usuário não |

| [`SearchEngine.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/SearchEngine.swift) | Parcial | [`CandidateProvider.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/CandidateProvider.swift) | Busca local V2 e source search não formam ainda busca unificada FTS V1 |

| [`ShakeHandler.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ShakeHandler.swift) | Ausente | — | Gestos shake/refresh dispensáveis |

| [`SourceRegistry.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/SourceRegistry.swift) | Parcial | [`ReaderPreferencesStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/ReaderPreferencesStore.swift) | Subset selecionado funciona; toggle região/categoria/taxonomia não |

| [`TaxonomyStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/TaxonomyStore.swift) | Ausente | [`LegacyCatalogReader.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/LegacyCatalogReader.swift) | Nós existentes no catálogo; árvore/seleção/filtro UI ausentes |

| [`TestConfiguration.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/TestConfiguration.swift) | Parcial | [`AppComposition.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineApp/AppComposition.swift) | Flags debug existem; harness typed V1 mais rico |

| [`URLResolver.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/URLResolver.swift) | Ausente | — | Site/podcast/YouTube/GitHub discovery não portados |

| [`UserStateStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/UserStateStore.swift) | Parcial | [`ReaderPreferencesStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/ReaderPreferencesStore.swift) | Separação de preferências e bookmarks; smart feeds, collections, import não |

| [`WhatsNewManager.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/WhatsNewManager.swift) | Ausente | — | Experiência de novidades não portou |

### E.5 — Views — interface principal

| Arquivo no V1 | Migração | Destino/correspondente V2 | Observação específica |
|---|---|---|---|

| [`AddFeedView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/AddFeedView.swift) | Ausente | [`FeedSourcePicker.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedSourcePicker.swift) | Buscar fontes no catálogo não equivale adicionar URL/descobrir feed |

| [`ArticleReaderView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/ArticleReaderView.swift) | Parcial | [`AppComposition.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineApp/AppComposition.swift) | Safari externo; leitor WKWebView interno não portado |

| [`BookmarkBoxPickerView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/BookmarkBoxPickerView.swift) | Ausente | — | Seleção de lista de bookmark não portada |

| [`BookmarkBoxesView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/BookmarkBoxesView.swift) | Ausente | — | Gerenciamento/listagem de bookmarks ausente |

| [`CatalogExploreView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/CatalogExploreView.swift) | Ausente | [`FeedSourcePicker.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedSourcePicker.swift) | Sem browse hierárquico e detalhes avançados |

| [`ClipboardBanner.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/ClipboardBanner.swift) | Ausente | — | Conveniente; não essencial ao runway |

| [`CollectionManagementView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/CollectionManagementView.swift) | Ausente | — | Coleções/playlist e source feed UI não portados |

| [`ContentFilterView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/ContentFilterView.swift) | Ausente | — | Filtros de palavra e templates não portados |

| [`CountriesListScreen.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/CountriesListScreen.swift) | Ausente | — | Browse por países não portado |

| [`CountryDetailScreen.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/CountryDetailScreen.swift) | Ausente | — | Detalhe regional não portado |

| [`CuratedFeedInspectorView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/CuratedFeedInspectorView.swift) | Ausente | — | Editor/inspector de perfil não portado |

| [`CuratedOnboardingView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/CuratedOnboardingView.swift) | Ausente | [`FeedPreparationView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedPreparationView.swift) | Tela de preparação não substitui onboarding editorial |

| [`ExportView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/ExportView.swift) | Ausente | — | UI de export/backup não portada |

| [`FeedEmptyStateView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedEmptyStateView.swift) | Parcial | [`FeedLoadingView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedLoadingView.swift) | Estados base existem, vazios contextuais V1 mais ricos |

| [`FeedItemCardView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemCardView.swift) | Reestruturado | [`FeedCardView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedCardView.swift) | Cards novos imóveis; customização visual de V1 não portada |

| [`FeedItemRowView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemRowView.swift) | Ausente | [`FeedCardView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedCardView.swift) | Layout lista alternativo ausente |

| [`FeedItemView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemView.swift) | Reestruturado | [`FeedCardView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedCardView.swift) | Card tap via identidade, sem gesto irreproduzível do V1 |

| [`FeedScreen.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedScreen.swift) | Reestruturado | [`FeedScreen.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedScreen.swift) | UI feed/viewport existe, busca+filtros+coleções não |

| [`FilterSheetView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FilterSheetView.swift) | Ausente | — | Filtros e lens UI não portados |

| [`MiniPlayerBar.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/MiniPlayerBar.swift) | Ausente | — | Podcast player não portado |

| [`OnboardingTipsView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/OnboardingTipsView.swift) | Ausente | — | Dicas/onboarding auxiliar não portado |

| [`PreparedCardImage.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/PreparedCardImage.swift) | Reestruturado | [`PresentationImage.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PresentationImage.swift) | Render local sem HTTP na UI |

| [`RegionDetailScreen.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/RegionDetailScreen.swift) | Ausente | — | Browse região não portado |

| [`SettingsSheetView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/SettingsSheetView.swift) | Ausente | — | Preferências globais e aparência não portadas |

| [`ShareCardImageView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/ShareCardImageView.swift) | Ausente | — | Compartilhamento visual não portado |

| [`SourceManagementView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/SourceManagementView.swift) | Parcial | [`FeedSourcePicker.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedSourcePicker.swift) | Picker simples, sem health/tipo/região/teste OPML |

| [`StatsShareCard.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/StatsShareCard.swift) | Ausente | — | Compartilhamento de estatísticas não portado |

| [`TaxonomyBrowseView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/TaxonomyBrowseView.swift) | Ausente | — | Taxonomia navegável não portada |

| [`TaxonomyChipBar.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/TaxonomyChipBar.swift) | Ausente | — | Chips contextuais não portados |

| [`ToastView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/ToastView.swift) | Ausente | — | UX acessória ausente |

### E.6 — Views — onboarding editorial

| Arquivo no V1 | Migração | Destino/correspondente V2 | Observação específica |
|---|---|---|---|

| [`ChoiceFeedbackOverlay.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/ChoiceFeedbackOverlay.swift) | Ausente | — | Feedback de escolha inteligente não portado |

| [`ConfidenceProgressView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/ConfidenceProgressView.swift) | Ausente | — | Confiança no perfil curado não portada |

| [`DiscoverySlider.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/DiscoverySlider.swift) | Ausente | — | Controle exploração/editoria não portado |

| [`EditorialBalanceControl.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/EditorialBalanceControl.swift) | Ausente | — | Peso editorial explícito não portado |

| [`FeedComposerScene.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/FeedComposerScene.swift) | Ausente | — | Compositor de perfil de conteúdo não portado |

| [`FlowLayout.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/FlowLayout.swift) | Ausente | — | Layout auxiliar; migrar somente se necessário |

| [`LanguageSelectionControl.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/LanguageSelectionControl.swift) | Ausente | — | Preferência de idiomas não portada |

| [`MediaTypeToggles.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/MediaTypeToggles.swift) | Ausente | — | Tipos audio/video/news não portados |

| [`StoryDuelCard.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/StoryDuelCard.swift) | Ausente | — | Card de comparação de notícias não portado |

| [`StoryDuelScene.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/StoryDuelScene.swift) | Ausente | — | Fluxo de duelos não portado |

| [`TopicPreferenceRow.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/TopicPreferenceRow.swift) | Ausente | — | Preferência por tópico não portada |

| [`WelcomeScene.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/Onboarding/WelcomeScene.swift) | Ausente | [`FeedPreparationView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedPreparationView.swift) | Tela inicial de preparo não substitui onboarding de preferência |

### E.7 — Scripts Swift do V1

| Arquivo no V1 | Migração | Destino/correspondente V2 | Observação específica |
|---|---|---|---|

| [`import-opml.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/scripts/import-opml.swift) | Ausente | — | Importador CLI V1; tooling do catálogo V2 fica fora do runtime |

| [`sign_manifest.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/scripts/sign_manifest.swift) | Ausente | [`fetch-catalog.sh`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/scripts/fetch-catalog.sh) | Assinatura/manifesto original trocado por hash explícito release |

**Total de entradas individuais V1 neste inventário:** 129 arquivos Swift de produção/scripts. Excluídos da matriz: suites de testes, fixtures, dados e recursos do catálogo, tratados em seções específicas abaixo.

## F. Inventário V2 → V1, arquivo por arquivo

A tabela inversa evita dois erros comuns: declarar “ausente” um recurso do V1 que foi dividido em vários módulos do V2 e, no sentido oposto, confundir um *tipo ou scaffold* V2 com a funcionalidade V1 completa. Cada linha abaixo indica o **papel do arquivo V2** e um ancestral funcional representativo (quando existe). São associações semânticas, não equivalência linha-a-linha.

### F.1 — App + composition

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`AppComposition.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineApp/AppComposition.swift) | [`FeedLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedLoader.swift) | Fachada de sessão/associação, seleção persistida, lifecycle, media/Runway; ainda longa; verificar ownership ao expandir UI |

| [`FeedMineApp.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineApp/FeedMineApp.swift) | [`feedmineApp.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/feedmineApp.swift) | App root reduzido, NavigationStack e source picker; muito menos lógica SwiftUI |

| [`TrustedFeeds.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineApp/TrustedFeeds.swift) | [`SourceRegistry.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/SourceRegistry.swift) | Resolver catálogo/4 starter sources + importados; não é taxonomia completa |

| [`ColdFeedBootstrap.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/ColdFeedBootstrap.swift) | [`FeedLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedLoader.swift) | Cold local/primeira publicação por callback sem esperar o target mais lento |

| [`FeedMineBootstrap.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/FeedMineBootstrap.swift) | — (novo) | Fronteira de bootstrap; verificar se ainda scaffold sem duplicar ColdFeedBootstrap |

| [`FeedMineEnvironment.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/FeedMineEnvironment.swift) | — (novo) | Injeção de ambiente; revisar uso real antes de ampliar |

| [`FeedPresentationHandoff.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/FeedPresentationHandoff.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Conversão de outcomes em apresentação, sem criar autoridade concorrente |

| [`FeedRunwayDriver.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/FeedRunwayDriver.swift) | [`FeedRunwayController.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedRunwayController.swift) | Executor causal único, mede/produz/adquire; vigiar caminho hot e awaits |

| [`LegacyCatalogImport.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/LegacyCatalogImport.swift) | [`CatalogIdentity.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/CatalogIdentity.swift) | Mapeamento estável de fonte V1 para V2 e source grants |

| [`MediaHTTPFetcher.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/MediaHTTPFetcher.swift) | [`MediaAssetStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/MediaAssetStore.swift) | Um transporte de imagem com limite de bytes; não duplicar URLSession |

| [`RunwayAcquisitionCycle.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/RunwayAcquisitionCycle.swift) | [`AdaptiveScheduler.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/AdaptiveScheduler.swift) | Handoff demanda de Runway para Acquisition, com cooldown/notify |

| [`SyndicationAcquisitionSnapshot.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineComposition/SyndicationAcquisitionSnapshot.swift) | [`SourceRegistry.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/SourceRegistry.swift) | Registrations/authority e connector por target |

### F.2 — FeedMineDomain

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`ConnectorOperationalFailure.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/ConnectorOperationalFailure.swift) | [`FetchOutcome.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FetchOutcome.swift) | Vocabulário de falha operacional separado de erro de integridade |

| [`Content.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/Content.swift) | [`FeedItem.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedItem.swift) | Origem/revisão/estado canônico sem overload de flags de UI |

| [`ContentLocatorIdentity.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/ContentLocatorIdentity.swift) | [`FeedItem.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedItem.swift) | Normalização de locator; preservar identidade distinta da URL aberta |

| [`FeedContext.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/FeedContext.swift) | [`FeedPresentationContext.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedPresentationContext.swift) | Identidade estável de contexto main/source/search |

| [`FeedIdentifiers.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/FeedIdentifiers.swift) | [`Identities.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/Identities.swift) | IDs fortemente tipados e por domínios |

| [`FeedIntent.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/FeedIntent.swift) | [`FeedPreset.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedPreset.swift) | Intent sem regime de preferências V1 completo |

| [`FeedPlan.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/FeedPlan.swift) | [`FeedRecipeDefinition.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedRecipeDefinition.swift) | Plan/Revision editorial imutáveis e versionados |

| [`InteractionOffer.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/InteractionOffer.swift) | [`FeedItem.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedItem.swift) | Modelo de ação; integração de app ainda restrita a URLs |

| [`MaterialContentIdentity.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/MaterialContentIdentity.swift) | [`FeedItem.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedItem.swift) | Semântica material compartilhada por seleção e publicação |

| [`MediaCandidate.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/MediaCandidate.swift) | [`ImageResolutionRecord.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/ImageResolutionRecord.swift) | Factos de candidatos visuais canônicos, sem download |

| [`Source.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineDomain/Source.swift) | [`FeedSource.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedSource.swift) | Fonte, binding, autoridade de membership |

### F.3 — FeedMineAcquisition

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`AcquisitionBackoff.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionBackoff.swift) | [`AdaptiveScheduler.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/AdaptiveScheduler.swift) | Cooldown por target puro e limitado |

| [`AcquisitionBatch.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionBatch.swift) | [`FeedFetchBatch.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedFetchBatch.swift) | Lote de observações + claims admitidas |

| [`AcquisitionCoordinator.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionCoordinator.swift) | [`RSSFetcher.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/RSSFetcher.swift) | Um owner de execução, dedupe, concorrência e batch admission |

| [`AcquisitionModels.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionModels.swift) | [`FetchOutcome.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FetchOutcome.swift) | Demanda, resultado e stop operacional |

| [`AcquisitionPlanner.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionPlanner.swift) | [`SourceScheduler.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/SourceScheduler.swift) | Planejamento bounded/round-robin de sources elegíveis |

| [`AcquisitionTarget.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AcquisitionTarget.swift) | [`FeedSource.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedSource.swift) | Unidade de aquisição distinta de Source semântica |

| [`AdmissionPolicy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/AdmissionPolicy.swift) | [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Autoridade de admission separada do transport |

| [`BootstrapPlan.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/BootstrapPlan.swift) | [`FeedLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedLoader.swift) | Demanda inicial quando não há oferta local |

| [`FeedConnector.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineAcquisition/FeedConnector.swift) | [`CatalogProtocols.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/CatalogProtocols.swift) | Contrato extensível de aquisição para RSS/novos protocolos |

### F.4 — FeedMineEditorial

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`Candidate.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/Candidate.swift) | [`FeedItem.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedItem.swift) | Projeção seletiva de revisão e memberships |

| [`CandidateProvider.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/CandidateProvider.swift) | [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Consulta canônica para seleção; revisar query cost e filtros |

| [`EditorialPolicy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/EditorialPolicy.swift) | [`PresetScorer.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/PresetScorer.swift) | Scoring igual por enquanto, não pesos do V1 |

| [`FeedPlanResolver.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/FeedPlanResolver.swift) | [`FeedRecipeResolver.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedRecipeResolver.swift) | Resolver estrutural; profiles V1 ainda não |

| [`HTMLNamedEntities.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/HTMLNamedEntities.swift) | [`RSSFetcher.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/RSSFetcher.swift) | Decodificação de entidades HTML textual |

| [`SelectionEngine.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/SelectionEngine.swift) | [`Reservoir.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/Reservoir.swift) | Um owner de ordenação/exposição/material |

| [`SelectionExposure.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/SelectionExposure.swift) | [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Identidade material de origens já publicadas |

| [`SourceAlternation.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineEditorial/SourceAlternation.swift) | [`EditorialSequencer.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/EditorialSequencer.swift) | Alternância por Source, sem reparo downstream |

### F.5 — FeedMineMedia

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`AssetStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/AssetStore.swift) | [`MediaAssetStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/MediaAssetStore.swift) | Conteúdo local endereçado por SHA-256, fsync e renomeação exclusiva |

| [`ImageMaterializer.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/ImageMaterializer.swift) | [`ImageLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImageLoader.swift) | Inspeção de imagem, materialização e recuperação |

| [`MediaHousekeeping.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/MediaHousekeeping.swift) | [`DiskImageCache.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/DiskImageCache.swift) | Inventário/eliminação; sem seleção editorial |

| [`MediaPolicy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/MediaPolicy.swift) | [`ImageCache.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImageCache.swift) | Policy recursos: rede, baixa energia, térmica, pixels, tamanho |

| [`MediaPreparation.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/MediaPreparation.swift) | [`CardPreparationPipeline.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CardPreparationPipeline.swift) | Fatos de preparação a partir de bytes ou asset local |

| [`MediaResolver.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/MediaResolver.swift) | [`ImageCache.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImageCache.swift) | Escolha entre candidatos visuais admissíveis por dispositivo |

| [`MediaRetention.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/MediaRetention.swift) | [`MediaAssetStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/MediaAssetStore.swift) | Classe eviction, proteger bookmarks e seen |

| [`PublishedMedia.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineMedia/PublishedMedia.swift) | [`PreparedFeedCard.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/PreparedFeedCard.swift) | Chaves/contrato sem imagem remota na UI |

### F.6 — FeedMinePersistence

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`AcquisitionAdmissionStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/AcquisitionAdmissionStore.swift) | [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Admission transacional e checkpoint coesos |

| [`AcquisitionTargetStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/AcquisitionTargetStore.swift) | [`SourceRegistry.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/SourceRegistry.swift) | Target grants, geração/revocação |

| [`ContentStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/ContentStore.swift) | [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Canônico, seleção_supply, memberships, candidateWindow |

| [`LegacyCatalogReader.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/LegacyCatalogReader.swift) | [`SQLiteCatalogStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/FeedEngine/SQLiteCatalogStore.swift) | Leitura read-only de catálogo V1, lookup e search ranqueada |

| [`PersistenceValueCoding.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/PersistenceValueCoding.swift) | [`UserStateStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/UserStateStore.swift) | Codificação centralizada de valores DB |

| [`PublicationStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/PublicationStore.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Editions/segments/cards imutáveis e successor tail autorizado |

| [`ReaderPreferencesStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/ReaderPreferencesStore.swift) | [`AppSettings.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/AppSettings.swift) | Fontes escolhidas, versão e contexto atual duráveis |

| [`RuntimeDatabase.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/RuntimeDatabase.swift) | [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Instância SQLite, conexão e localização local |

| [`RuntimeMigrations.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/RuntimeMigrations.swift) | [`UserStateStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/UserStateStore.swift) | Migrações tipadas do runtime, sem importar DB V1 em bloco |

| [`SessionStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePersistence/SessionStore.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Cursor/contexts e high-water/seen |

### F.7 — FeedMinePublication

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`FeedEdition.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/FeedEdition.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Identidade editorial da sequência publicada |

| [`FeedSegment.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/FeedSegment.swift) | [`Reservoir.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/Reservoir.swift) | Segmentos append-only, não batches arbitrários visíveis |

| [`FeedWindow.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/FeedWindow.swift) | [`ReadyCardQueue.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ReadyCardQueue.swift) | Janela finita em história durável |

| [`PublicationCardDraft.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/PublicationCardDraft.swift) | [`PreparedFeedCard.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/PreparedFeedCard.swift) | Draft 1:1 com candidato, sem surpresa na publicação |

| [`PublicationCoordinator.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/PublicationCoordinator.swift) | [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Autoridade de criação/append/sucessão transacional |

| [`PublicationHistory.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/PublicationHistory.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Restore/readyAhead/advance/seen |

| [`PublicationPersistenceMapping.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/PublicationPersistenceMapping.swift) | [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Conversões Publication↔Persistence explícitas |

| [`PublicationRunwayFacts.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/PublicationRunwayFacts.swift) | [`RunwayMetrics.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/RunwayMetrics.swift) | Facts exatos e probes da reserva |

| [`PublishedCard.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/PublishedCard.swift) | [`FeedCardPresentation.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedCardPresentation.swift) | Valor de card histórico com mídia/ação congelados |

| [`PublishedOrigin.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/PublishedOrigin.swift) | [`FeedItem.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedItem.swift) | Proveniência congelada com SourceID |

| [`PublishedPrimaryAction.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/PublishedPrimaryAction.swift) | [`FeedItemView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemView.swift) | Tipo/alvo de ação separado, leitura pelo card ID |

| [`RenderContract.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/RenderContract.swift) | [`PreparedFeedCard.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/PreparedFeedCard.swift) | Layout/proporção fixos na história |

| [`SessionCursor.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMinePublication/SessionCursor.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Cursor lógico independente de altura/scroll |

### F.8 — FeedMineRuntime

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`BackgroundFeedRefresh.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/BackgroundFeedRefresh.swift) | [`BackgroundRefreshService.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/BackgroundRefreshService.swift) | Scaffold: oportunidade background, não pipeline independente |

| [`FeedPresentationSnapshot.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/FeedPresentationSnapshot.swift) | [`FeedCardPresentation.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedCardPresentation.swift) | Janela local pronta com provenance monotônica |

| [`FeedSession.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/FeedSession.swift) | [`FeedLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedLoader.swift) | Owner sessão/posição e projeção de janela |

| [`FeedSessionEffects.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/FeedSessionEffects.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Abstração auxiliar: revisar utilização real |

| [`FeedSessionReducer.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/FeedSessionReducer.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Abstração auxiliar: evitar segundo estado autoritativo |

| [`FeedSessionState.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/FeedSessionState.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Estado de sessão sem flag soup do V1 |

| [`FeedSessionUI.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/FeedSessionUI.swift) | [`FeedScreen.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedScreen.swift) | Interpretação Runtime/UI: verificar scaffold |

| [`HiddenTailMaintenance.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/HiddenTailMaintenance.swift) | [`CardPreparationCoordinator.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CardPreparationCoordinator.swift) | Substitui cauda não vista sob lease, sem mudar seen history |

| [`InitialProductionSlice.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/InitialProductionSlice.swift) | [`FeedStore.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedStore.swift) | Publicação inicial bounded por candidatos |

| [`InteractionCoordinator.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/InteractionCoordinator.swift) | [`FeedItemView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemView.swift) | Surface de ações; implementação real de abrir URL fica no App |

| [`LocalProductionSlice.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/LocalProductionSlice.swift) | [`Reservoir.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/Reservoir.swift) | Slice editorial append com fences |

| [`MediaPrefetcher.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/MediaPrefetcher.swift) | [`ImagePrefetcher.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImagePrefetcher.swift) | Owner único de prefetch/download/preparo remoto |

| [`MediaTidy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/MediaTidy.swift) | [`DiskImageCache.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/DiskImageCache.swift) | Trabalho enquanto tela não visível e eviction por uso |

| [`PreparationProgress.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PreparationProgress.swift) | [`FeedEmptyStateView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedEmptyStateView.swift) | Evidências reais de aquisição para loading |

| [`PresentationCard.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PresentationCard.swift) | [`FeedCardPresentation.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedCardPresentation.swift) | Card imutável com image/key/action kind |

| [`PresentationImage.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PresentationImage.swift) | [`ImageLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImageLoader.swift) | Thumbnailing ImageIO local, não HTTP por UI |

| [`PublicationPreparation.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/PublicationPreparation.swift) | [`CardPreparationPipeline.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/CardPreparationPipeline.swift) | Converte inputs selecionados em drafts |

| [`RunwayController.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/RunwayController.swift) | [`FeedRunwayController.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedRunwayController.swift) | Actor de state machine adaptativa, fatos/retry |

| [`RunwayPolicy.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/RunwayPolicy.swift) | [`RunwayPolicy.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/RunwayPolicy.swift) | Pure coverage + piso + consumo/latência |

| [`ViewportObservation.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineRuntime/ViewportObservation.swift) | [`FeedLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedLoader.swift) | Viewport como observação sem mutar história |

### F.9 — FeedMineSyndication

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`SyndicationConnector.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineSyndication/SyndicationConnector.swift) | [`RSSFetcher.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/RSSFetcher.swift) | Connector paging/checkpoint para RSS Atom JSON |

| [`SyndicationHTTP.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineSyndication/SyndicationHTTP.swift) | [`FeedHTTPSync.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedHTTPSync.swift) | HTTP limitado, conditional requests/redirect |

| [`SyndicationItemIdentity.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineSyndication/SyndicationItemIdentity.swift) | [`FeedItem.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Models/FeedItem.swift) | Compat adapter para identidade de links |

| [`SyndicationMediaLocator.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineSyndication/SyndicationMediaLocator.swift) | [`ImageCache.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/ImageCache.swift) | Candidatos RSS/HTML visuais, filtros decorativos |

| [`SyndicationTranslator.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineSyndication/SyndicationTranslator.swift) | [`RSSFetcher.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/RSSFetcher.swift) | Normalização de itens, mídia, datas, identidade |

### F.10 — FeedMineUI

| Arquivo V2 | Relacionado no V1 | Responsabilidade / julgamento |
|---|---|---|

| [`FeedCardView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedCardView.swift) | [`FeedItemCardView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedItemCardView.swift) | Hero/thumbnail/text-only, action callbacks, bookmark; UI V1 mais sofisticada |

| [`FeedLoadingView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedLoadingView.swift) | [`FeedEmptyStateView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedEmptyStateView.swift) | Estados honestos pending/unavailable/deferred/failed |

| [`FeedPreparationView.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedPreparationView.swift) | [`CuratedOnboardingView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/CuratedOnboardingView.swift) | Tela de preparo, não onboarding editorial V1 |

| [`FeedPresentationState.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedPresentationState.swift) | [`FeedDisplayState.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedDisplayState.swift) | Snapshot+work protegidos de projeções antigas |

| [`FeedScreen.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedScreen.swift) | [`FeedScreen.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/FeedScreen.swift) | Scroll nativo, geometry/phase/proof, sem filtros avançados |

| [`FeedScreenStore.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedScreenStore.swift) | [`FeedLoader.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Services/FeedLoader.swift) | Store pequeno somente para estado/handoff UI |

| [`FeedSourcePicker.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Sources/FeedMineUI/FeedSourcePicker.swift) | [`SourceManagementView.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmine/Views/SourceManagementView.swift) | Seleção e busca no catálogo; UI taxonomia ausente |

**Total de entradas individuais V2 inventariadas:** 103 arquivos Swift de produção. A matriz distingue *responsabilidade* de *paridade do produto*: nenhuma linha “ancestral V1” significa que todas as funções do arquivo antigo foram portadas.

## G. Inventário de testes e evidência (arquivo a arquivo por objetivo nominal)

**Importante:** os nomes abaixo foram conferidos na árvore; a descrição indica o *domínio alvo* inferível pelo próprio nome, **não é prova de que cada teste foi individualmente lido, executado ou está correto**. Nos pontos críticos foram lidos exemplos (V1: integração/provas de UI documentadas no estudo V1; V2: `CompositionTests`, `MediaPrefetcherTests`, `LegacyCatalogImportTests` e docs de validação). O release exige execução do conjunto relevante no HEAD e provas de dispositivo.

### G.1 — V1: 48 arquivos de testes/infraestrutura

| Arquivo | Família estimada | Uso como referência para V2 |
|---|---|---|

| [`AdaptiveSchedulerTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/AdaptiveSchedulerTests.swift) | Comportamento de domínio/integrado | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`CardPreparationCoordinatorTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/CardPreparationCoordinatorTests.swift) | Mídia/preparação | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`CardPresentationTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/CardPresentationTests.swift) | Comportamento de domínio/integrado | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`CatalogBrowserViewModelTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/CatalogBrowserViewModelTests.swift) | Catálogo/editorial/preferências | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`CatalogIdentityContractTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/CatalogIdentityContractTests.swift) | Catálogo/editorial/preferências | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`ContentCollectionTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/ContentCollectionTests.swift) | Comportamento de domínio/integrado | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`ContentDistributionTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/ContentDistributionTests.swift) | Comportamento de domínio/integrado | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`ContentVarietyDiagnostics.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/ContentVarietyDiagnostics.swift) | Comportamento de domínio/integrado | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`CuratedPreferenceEngineTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/CuratedPreferenceEngineTests.swift) | Catálogo/editorial/preferências | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`DatabasePerformanceTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/DatabasePerformanceTests.swift) | Persistência/publicação | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedComposerPreviewTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/FeedComposerPreviewTests.swift) | Comportamento de domínio/integrado | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedDisplayStateTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/FeedDisplayStateTests.swift) | Runway/apresentação | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedEngineBoundaryTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/FeedEngineBoundaryTests.swift) | Comportamento de domínio/integrado | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedLoaderCacheTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/FeedLoaderCacheTests.swift) | Runway/apresentação | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedPreviewPipelineTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/FeedPreviewPipelineTests.swift) | Comportamento de domínio/integrado | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedRecipeDefinitionTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/FeedRecipeDefinitionTests.swift) | Catálogo/editorial/preferências | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedRecipeResolverTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/FeedRecipeResolverTests.swift) | Catálogo/editorial/preferências | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedStoreTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/FeedStoreTests.swift) | Persistência/publicação | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FilterPerformanceTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/FilterPerformanceTests.swift) | Catálogo/editorial/preferências | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`HTTPValidatorsTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/HTTPValidatorsTests.swift) | Aquisição/rede | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`CatalogPerformanceTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Performance/CatalogPerformanceTests.swift) | Performance/scale | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedParsingPerformanceTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Performance/FeedParsingPerformanceTests.swift) | Performance/scale | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`GoldenFeedTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Performance/GoldenFeedTests.swift) | Performance/scale | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`LargeCatalogMemoryTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Performance/LargeCatalogMemoryTests.swift) | Performance/scale | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`MigrationTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Performance/MigrationTests.swift) | Performance/scale | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`PersistencePerformanceTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Performance/PersistencePerformanceTests.swift) | Performance/scale | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`SearchPerformanceTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Performance/SearchPerformanceTests.swift) | Performance/scale | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`TestInfrastructureValidationTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Performance/TestInfrastructureValidationTests.swift) | Performance/scale | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`TimelineAssemblyPerformanceTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Performance/TimelineAssemblyPerformanceTests.swift) | Performance/scale | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`ReadyCardQueueTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/ReadyCardQueueTests.swift) | Runway/apresentação | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`ReservoirTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/ReservoirTests.swift) | Runway/apresentação | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`SQLiteCatalogStoreTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/SQLiteCatalogStoreTests.swift) | Catálogo/editorial/preferências | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`SourceSchedulerTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/SourceSchedulerTests.swift) | Aquisição/rede | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`TestHelpers.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/Support/TestHelpers.swift) | Infraestrutura/fixture de teste | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`TaxonomyStoreTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineTests/TaxonomyStoreTests.swift) | Catálogo/editorial/preferências | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`AccessibilityAuditTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Accessibility/AccessibilityAuditTests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedmineFilterUITests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/FeedmineFilterUITests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`FeedmineUITests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/FeedmineUITests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`ConcurrentRefreshTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Performance/ConcurrentRefreshTests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`DumpStateTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Performance/DumpStateTests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`HitchRatioTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Performance/HitchRatioTests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`LaunchPerformanceTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Performance/LaunchPerformanceTests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`ScrollPerformanceTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Performance/ScrollPerformanceTests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`PersonaExplorationUITests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/PersonaExplorationUITests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`AppLauncher.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Support/AppLauncher.swift) | Infraestrutura/fixture de teste | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`ScreenObjects.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Support/ScreenObjects.swift) | Infraestrutura/fixture de teste | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`CardIdentityStabilityTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Usability/CardIdentityStabilityTests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

| [`UsabilityJourneyTests.swift`](https://github.com/wsmontes/feedmine-dev/blob/b5c2f59c55babb672c81dd978d201f98c5909934/feedmineUITests/Usability/UsabilityJourneyTests.swift) | Jornada/UI/acessibilidade | Portar as invariantes do cenário, não necessariamente o harness anterior |

### G.2 — V2: 95 arquivos de testes/fixtures

| Arquivo | Família estimada | Ponto de atenção |
|---|---|---|

| [`CompositionTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineAppTests/CompositionTests.swift) | Comportamento de domínio/integrado | Cobertura simulador relatada em f8eb67e; repetir em HEAD |

| [`FeedMineUITests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/FeedMineApp/FeedMineAppTests/FeedMineUITests.swift) | Jornada/UI/acessibilidade | Cobertura simulador relatada em f8eb67e; repetir em HEAD |

| [`ArchitectureSmokeTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/ArchitectureSmokeTests/ArchitectureSmokeTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`EditedArticleRecurrenceTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/ArchitectureSmokeTests/EditedArticleRecurrenceTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedPresentationStateTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/ArchitectureSmokeTests/FeedPresentationStateTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedScreenRenderingTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/ArchitectureSmokeTests/FeedScreenRenderingTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedScreenStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/ArchitectureSmokeTests/FeedScreenStoreTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedViewportCaptureTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/ArchitectureSmokeTests/FeedViewportCaptureTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`OriginExposureIntegrationTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/ArchitectureSmokeTests/OriginExposureIntegrationTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PresentationProjectionOrderingTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/ArchitectureSmokeTests/PresentationProjectionOrderingTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ReadablePublishedTextIntegrationTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/ArchitectureSmokeTests/ReadablePublishedTextIntegrationTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`AcquisitionBackoffConcurrencyTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineAcquisitionTests/AcquisitionBackoffConcurrencyTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`AcquisitionCoordinatorTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineAcquisitionTests/AcquisitionCoordinatorTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`AcquisitionPlannerTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineAcquisitionTests/AcquisitionPlannerTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`AcquisitionTargetTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineAcquisitionTests/AcquisitionTargetTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`AdmissionPolicyTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineAcquisitionTests/AdmissionPolicyTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`BootstrapPlanTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineAcquisitionTests/BootstrapPlanTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FakeContinuousConnector.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineAcquisitionTests/FakeContinuousConnector.swift) | Infraestrutura/fixture de teste | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FakeFiniteConnector.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineAcquisitionTests/FakeFiniteConnector.swift) | Infraestrutura/fixture de teste | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ColdFeedBootstrapTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineCompositionTests/ColdFeedBootstrapTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedPresentationHandoffTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineCompositionTests/FeedPresentationHandoffTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedRunwayDriverTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineCompositionTests/FeedRunwayDriverTests.swift) | Runway/apresentação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`LegacyCatalogImportTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineCompositionTests/LegacyCatalogImportTests.swift) | Catálogo/editorial/preferências | Validação no HEAD após catálogo/release e cenário real de produto |

| [`MembershipAuthorityIntegrationTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineCompositionTests/MembershipAuthorityIntegrationTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`RunwayAcquisitionCycleTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineCompositionTests/RunwayAcquisitionCycleTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`SyndicationAcquisitionSnapshotTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineCompositionTests/SyndicationAcquisitionSnapshotTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ContentTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineDomainTests/ContentTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ContextTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineDomainTests/ContextTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedIntentTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineDomainTests/FeedIntentTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedPlanTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineDomainTests/FeedPlanTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`IdentifierTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineDomainTests/IdentifierTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`MediaCandidateTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineDomainTests/MediaCandidateTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`SourceTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineDomainTests/SourceTests.swift) | Catálogo/editorial/preferências | Validação no HEAD após catálogo/release e cenário real de produto |

| [`CandidateProviderTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineEditorialTests/CandidateProviderTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`SelectionEngineTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineEditorialTests/SelectionEngineTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`AssetStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineMediaTests/AssetStoreTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ImageMaterializerTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineMediaTests/ImageMaterializerTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`MediaHousekeepingTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineMediaTests/MediaHousekeepingTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`MediaPolicyResolverTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineMediaTests/MediaPolicyResolverTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`MediaPreparationTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineMediaTests/MediaPreparationTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`AcquisitionAdmissionStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/AcquisitionAdmissionStoreTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`AcquisitionTargetStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/AcquisitionTargetStoreTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`AvailabilityPrecedenceTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/AvailabilityPrecedenceTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`CanonicalSupplySchemaTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/CanonicalSupplySchemaTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ContentStoreCandidateWindowScaleTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/ContentStoreCandidateWindowScaleTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ContentStoreCandidateWindowTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/ContentStoreCandidateWindowTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ContentStoreMediaCandidateTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/ContentStoreMediaCandidateTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ContentStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/ContentStoreTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`InitialPublicationAtomicityTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/InitialPublicationAtomicityTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`LegacyCatalogReaderTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/LegacyCatalogReaderTests.swift) | Catálogo/editorial/preferências | Validação no HEAD após catálogo/release e cenário real de produto |

| [`MediaCandidateSchemaTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/MediaCandidateSchemaTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationMediaUseTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/PublicationMediaUseTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationRunwayStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/PublicationRunwayStoreTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationSchemaTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/PublicationSchemaTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/PublicationStoreTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ReaderPreferencesStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/ReaderPreferencesStoreTests.swift) | Catálogo/editorial/preferências | Cobrir seleção/edição de fontes, A→B→A e mudanças rápidas |

| [`RuntimeDatabaseTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/RuntimeDatabaseTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`RuntimeMigrationTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/RuntimeMigrationTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`SessionStoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePersistenceTests/SessionStoreTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedEditionTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/FeedEditionTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedSegmentTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/FeedSegmentTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedWindowTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/FeedWindowTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`OfflineRestorePersistenceTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/OfflineRestorePersistenceTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationCoordinatorTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/PublicationCoordinatorTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationHistoryTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/PublicationHistoryTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationIdentityTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/PublicationIdentityTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationPersistenceMappingTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/PublicationPersistenceMappingTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationRunwayFactsTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/PublicationRunwayFactsTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublishedCardTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/PublishedCardTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublishedMediaTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/PublishedMediaTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublishedOriginTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/PublishedOriginTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`RenderContractTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/RenderContractTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`SessionCursorTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMinePublicationTests/SessionCursorTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedSessionCheckpointTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/FeedSessionCheckpointTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedSessionRunwayTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/FeedSessionRunwayTests.swift) | Runway/apresentação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedSessionViewportTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/FeedSessionViewportTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`FeedSessionWarmRestoreTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/FeedSessionWarmRestoreTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`InitialProductionSliceTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/InitialProductionSliceTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`LocalProductionSliceTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/LocalProductionSliceTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`MediaPrefetcherTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/MediaPrefetcherTests.swift) | Mídia/preparação | Cobrir deadline, falha temporária e reuso após relançamento |

| [`MediaTidyFactsTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/MediaTidyFactsTests.swift) | Mídia/preparação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PreparationProgressTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/PreparationProgressTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PresentationProjectionTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/PresentationProjectionTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ProjectionDecodeMeasurementTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/ProjectionDecodeMeasurementTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublicationPreparationTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/PublicationPreparationTests.swift) | Persistência/publicação | Validação no HEAD após catálogo/release e cenário real de produto |

| [`PublishedTextNormalizationTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/PublishedTextNormalizationTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`RunwayControllerTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/RunwayControllerTests.swift) | Runway/apresentação | Cobrir reserva visual/latência real, não apenas quantidade de cards |

| [`RunwayPolicyTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineRuntimeTests/RunwayPolicyTests.swift) | Runway/apresentação | Cobrir reserva visual/latência real, não apenas quantidade de cards |

| [`CompletedDocumentFingerprintTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineSyndicationTests/CompletedDocumentFingerprintTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ExecutionDocumentReuseTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineSyndicationTests/ExecutionDocumentReuseTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`ResidualOperationalFailureTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineSyndicationTests/ResidualOperationalFailureTests.swift) | Comportamento de domínio/integrado | Validação no HEAD após catálogo/release e cenário real de produto |

| [`SyndicationCheckpointTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineSyndicationTests/SyndicationCheckpointTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`SyndicationConnectorTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineSyndicationTests/SyndicationConnectorTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`SyndicationHTTPTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineSyndicationTests/SyndicationHTTPTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

| [`SyndicationTranslatorTests.swift`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/Tests/FeedMineSyndicationTests/SyndicationTranslatorTests.swift) | Aquisição/rede | Validação no HEAD após catálogo/release e cenário real de produto |

### G.3 — O que falta testar de ponta a ponta

- **Long-scroll test:** 90 minutos de leitura simulada/real com requests lentas, alternância por fonte, pausas, navegação reversa e nenhuma cauda prematura evitável.
- **No-network warm relaunch:** recuperar a janela e o cursor sem requerer HTTP, mesmo que a fonte mude de disponibilidade.
- **A→B→A sob concorrência:** trocar contexto durante DNS/HTTP/mídia pendente e retornar sem repovoar o que estava válido.
- **Catalog release smoke:** clone limpo, `scripts/fetch-catalog.sh`, SHA-256, bundle Xcode, quatro starters, consulta de fonte e erro explícito no Release sem arquivo.
- **Format coverage:** RSS, Atom, JSON feeds, imagens, enclosures audio/vídeo, conteúdo HTML malformado, datas no futuro, GUID instável e redirects.
- **Accessibility & energy:** tamanho dinâmico de fonte, VoiceOver, Reduce Motion, RTL e consumo de bateria/memória/CPU em iPhone físico. Não inferir estes resultados do SwiftPM/macOS.

## H. Segurança e borda de rede — achado adicional

**R15 — P1 segurança/privacidade, validar e corrigir:** `SyndicationMediaLocator.resolve()` aceita URLs externas `http(s)` com host não vazio sem rejeitar loopback, IP privado e endereços link-local; `MediaHTTPFetcher.fetch()` faz request normal por `URLSession` e só verifica downgrade HTTPS→HTTP na **resposta** (depois de a conexão/redirect ter ocorrido). Assim uma fonte RSS não confiável pode induzir o app a tentar carregar uma URL local/intranet ou seguir redirects problemáticos. Não há prova neste review de exploração ou exposição de dados, mas a falta de política de destino antes da conexão é observável no código. Ideal: vetar esquemas/destinos privados na admissão de mídia e em cada redirect, respeitando o modelo de segurança e sem prometer defesa contra DNS rebinding sem verificação pós-conexão. Provar com fixtures loopback, IP privado e redirect; o problema é especialmente relevante em redes corporativas/domésticas. Não copiar o resolver V1 indiscriminadamente.

**R16 — P2 arquitetura:** `FeedMineApp/FeedMineApp/AppComposition.swift` já tem ~667 linhas e concentra lifecycle, seleção de fontes, política de mídia, retries, bookmarks, opening, cold evidence e montagem. Ainda é menor e menos autoritativo que o God Store V1, mas merece **simplificação de wiring**, com ownership explícito; evitar que volte a ser um `FeedStore` disfarçado. Só extrair depois de mapear responsabilidade real, não criar camadas cerimoniais.

## I. Plano para concluir o V2 sem reconstruir o V1

| Prioridade | Entrega | Critério de aceite | Não fazer |
|---|---|---|---|
| 0 | Validar HEAD `880191f` em clone limpo | Asset hash + Swift build/test + Xcode integration/XCUI, screenshot + log | Tomar 827/0 de `f8eb67e` como prova do HEAD |
| 1 | Teste comportamental de runway + refinamento adaptativo | Reserva suficiente em pontos/tempo, sem chegar ao fim evitável | Usar `16 cards` como definição de infinito; segundo scheduler |
| 2 | Reduzir superfície de rede insegura | Fontes externas não abrem destinos privados/redirects perigosos | Filtro só por extensão de imagem |
| 3 | Escolha/taxonomia e UX básica de navegação | Usuário encontra e segue fontes entre 77k+ sem carregar tudo | Copiar SourceRegistry/TaxonomyStore gigantes do V1 |
| 4 | Filtros reais com preservação de contextos | Aplicar língua/tópico/formato e A→B→A sem invalidar trabalho compatível | Destruir Edition/reconstruir a cada toggle |
| 5 | Bookmarks e import/export OPML | Dados portáveis e leitura offline por lista | Portar UserStateStore monolítico |
| 6 | Podcasts e player quando fizer parte do release scope | Enclosure validado, play/pause, resume, lock screen | Segundo RSS pipeline |
| 7 | Editorial de qualidade | Scoring/dedup/diversidade baseado em fatos e revisões estáveis | Reservatório mutável + sequencer reparando depois |
| 8 | UI e confiabilidade | Acessibilidade, visual system, estados reais, hardware/energia | Cosmetic micro-optimization enquanto feed acaba |

## J. Veredito

**V2 vence em:** isolamento e testes de contratos, transações, identidade, imutabilidade, fronteiras de rede/UI, eliminação de mecanismos concorrentes e recuperação local bem modelada. **V1 vence em:** amplitude de produto, descoberta/importação, navegação do catálogo, criação de perfis, filtros, bookmarking avançado, podcasts, exportabilidade, tema/locale e UI final de leitor. **Nenhum deles sozinho prova a experiência-alvo de um feed infinito proativamente abastecido durante uso prolongado e com fontes externas lentas.**

Minha recomendação é usar o V1 como **especificação comportamental e coleção de fixtures**, e o V2 como **base de implementação**. Tratar as tabelas deste relatório como mapa de migração, não como ordem para portar tudo. O próximo incremento deve ser delimitado por uma propriedade de produto que o usuário realmente perceberá.

### Limites e fontes da revisão

- Os arquivos foram obtidos pelo conector GitHub dos commits congelados acima. Não houve build local neste ambiente, benchmark, download do asset do catálogo nem revisão individual dos ~2.000 arquivos de dados/recursos do V1. O inventário por arquivo é **semântico e rastreável**, com links para cada caminho; não equivale a uma validação exaustiva do corpo de cada arquivo. Foram lidas com mais profundidade as rotas da composição, runway, aquisição, seleção, catálogo, mídia, publicação e principais serviços V1.
- Referências complementares no próprio V2: [`docs/v1-study/`](https://github.com/wsmontes/feedmine_v2/tree/880191fc9a7156ad4e5c89da1012da67d9e9a151/docs/v1-study), [`docs/product/PRODUCT_DECISIONS_2026-10-09.md`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [`docs/reviews/OMP_VALIDATION_2026-10-09.md`](https://github.com/wsmontes/feedmine_v2/blob/880191fc9a7156ad4e5c89da1012da67d9e9a151/docs/reviews/OMP_VALIDATION_2026-10-09.md).
- **Contagem de catálogo:** o README V1 anuncia **88.084 fontes normalizadas**; a validação do bundle relatada no V2 menciona **77.443 registros/fonte** no catálogo concreto testado. Esses valores pertencem a artefatos/escopos diferentes e não devem ser tratados como sinônimos sem consulta SQL ao arquivo de release.
