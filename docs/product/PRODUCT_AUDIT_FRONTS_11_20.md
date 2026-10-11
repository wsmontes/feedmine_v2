# FeedMine V2 — Segunda onda de auditoria de produto: F11–F20

**Data-base:** 2026-10-10  
**Status:** proposta de dez frentes adicionais, fundamentada em inspeção dos repositórios [V1](https://github.com/wsmontes/feedmine-dev) e [V2](https://github.com/wsmontes/feedmine_v2) e na [matriz V1→V2](../v1-study/UI_TRANSFER_MATRIX.md). **Não é certificação funcional e não comprova execução de testes.**  
**Escopo:** nove frentes com centro de gravidade em UI/UX (F11–F19) e uma frente transversal de retorno/lifecycle (F20).  
**Precedência:** [North Star](PRODUCT_NORTH_STAR.md), [PD-1…10](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md) e [auditoria F01–F10](PRODUCT_AUDIT_10_FRONTS.md).

## Por que novas frentes?

As primeiras dez frentes já cobrem descoberta, onboarding, ingestão, curadoria, runway, cards, filtros, biblioteca, offline e release, **em nível de sistema/jornada principal**. Esta segunda onda investiga **interações específicas** que a V1 possuía e que a V2 ainda não demonstra integralmente, embora possua parte das estruturas necessárias.

**Não confundir:**
- **Código existente** com jornada observada;
- **teste isolado aprovado** com UX de ponta a ponta;
- **diferença aceita na transferência** com decisão permanente de produto;
- **comportamento antigo da V1** com comportamento que deve necessariamente voltar.

Cada frente nova é um *deep dive* com fronteira explícita em relação à F01–F10; não se cria engine, cache, scheduler, store ou pipeline paralelo para acomodar a interface. A UI só exprime intenção e exibe resultados admitidos; Runtime/Session/owners existentes executam trabalho. A exploração do catálogo e a capacidade de runway permanecem progressivas e relativas, sem cotas arbitrárias. B01–B06 permanecem inalterados.

## Panorama e prioridade sugerida

| Frente | Tema | Ênfase | V1: evidência | Lacuna V2 a investigar | Prioridade |
| --- | --- | --- | --- | --- | --- |
| **F11** | Busca unificada e exploração dos resultados | **UI/UX** | `FeedScreen.unifiedSearchPanel` | Busca contextual existe; painel integrado não foi transferido | P1 |
| **F12** | Descoberta navegável de fontes, países e taxonomia | **UI/UX** | `SourceFeedView`, `TaxonomyBrowseView`, detalhes de país/região | Backend e telas parciais; navegação ponta a ponta não demonstrada | P1 |
| **F13** | Controle negativo explícito e editor de filtros de conteúdo | **UI/UX** | `ContentFilterView`, templates, regras próprias | Elegibilidade implementada; editor visual de regras ausente | P1 |
| **F14** | Leitor embutido, destinos e retorno | **UI/UX** | `ArticleReaderView`/WKWebView, Safari, progresso | V2 usa SFSafariViewController; controles/fluxo e teste do card abertos pendentes | P1 |
| **F15** | Jornada de áudio e podcasts | **UI/UX** | `MiniPlayerBar`, `FullPlayerView`, `AudioPlayerManager` | Miniplayer demonstrado; persistência de posição e lifecycle sem prova | P1/P2 |
| **F16** | Biblioteca pessoal: fluxos de organização e Smart Feeds | **UI/UX** | bookmark boxes, source collections, presets | Caixas/presets têm testes; picker, superfícies de leitura e refresh não integralmente provados | P1 |
| **F17** | Idiomas da interface, leitura inclusiva e identidade visual | **UI/UX** | `LocaleManager`, String Catalog, circadian/night, RTL | V2 não trouxe escolha de idioma; ativos/RTL/visual não comprovados | P1 |
| **F18** | Adicionar fonte e portabilidade de dados sem atrito | **UI/UX** | `AddFeedView`, `ClipboardBanner`, `OPMLParser`, `ExportView` | Import/export parcialmente cobertos; URL-colada/clipboard/coleta na coleção não comprovados | P2 |
| **F19** | Compartilhamento de descobertas e feedback útil | **UI/UX** | `ShareCardImageView`, `StatsShareCard`, menus, toast | Link/copy existem; arte compartilhável não foi portada por decisão registrada | P2/decisão |
| **F20** | Retorno ao app: novidades, lifecycle e sinais de continuidade | **Produto + runtime/UX** | `WhatsNewManager`, lifecycle, badge, persistência de áudio | Mecanismos V1 não equivalem a contrato V2 demonstrado; risco de romper FeedEdition | P1/P2 |

Prioridade é de **investigação e documentação**, não compromisso de implementação.

---

## F11 — Busca unificada e resultados navegáveis [UI/UX]

**Promessa:** a pessoa digita uma curiosidade e encontra **conteúdo, fontes e itens já guardados**, entende a diferença entre cada resultado e pode aprofundar sem perder o feed de origem.

**V1 verificada:** [`Views/FeedScreen.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/FeedScreen.swift) tem `unifiedSearchPanel` (fontes/salvos/itens locais), toggles de escopo *Sources/Contents*, termos/chips e ações de abrir fonte/artigo. A matriz registra que o painel `ReaderSearchResults` não foi desenhado na V2, embora o campo de busca e o contexto de pesquisa tenham sido transferidos.

**Investigação:** diferenciar buscar **fontes** de buscar **histórias**; resultados locais vs. necessidade explícita de exploração externa; estados vazios por escopo; termos inclusivos/excludentes; abrir fonte, abrir artigo, salvar, voltar à query e voltar exatamente ao feed/contexto anterior. Não presumir busca remota universal.

**Oráculo/aceite:** corpus conhecido com source e article homônimos, dois escopos e salvos; os resultados mostram tipos/destinos corretos, cada ação abre o objeto certo, cancelar mantém contexto/âncora e nenhum resultado é inventado ou reutilizado de uma query antiga. Telas e vídeo de execução com teclado, cancelamento e retorno.

**Fronteira:** F07 continua dono da semântica de `ContextKey`/filtros; F11 decide a experiência humana de **resultados e navegação**. Não criar segundo search engine.

**PRD de especificação:** [PRD F11](F11_UNIFIED_SEARCH_RESULTS_UX_PRD.md).

## F12 — Explorar fonte, país, região e taxonomia [UI/UX]

**Promessa:** de qualquer história descoberta, alcançar a origem editorial, navegar assuntos/países e escolher seguir/deixar de seguir uma fonte, sem exigir URL RSS.

**V1 verificada:** [`TaxonomyBrowseView.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/TaxonomyBrowseView.swift), [`CollectionManagementView.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/CollectionManagementView.swift) (`SourceFeedView` e feed de coleção), `CountryDetailScreen`, `RegionDetailScreen`. A matriz indica que V2 tem `NodeSourcesView`, `CountriesListView`, `TaxonomyBrowseView` e backend, mas não comprova entrada real no feed de uma fonte nem vários níveis de detalhe por gesto.

**Investigação:** rotas card→fonte→feed da fonte, busca/filtragem do catálogo, breadcrumbs, categorias com hierarquia, números/estado de seleção, fontes sem conteúdo disponível, falhas de origem, relação Provider vs. Source e retorno ao card original.

**Oráculo/aceite:** percorrer fonte → país → região → assunto → fonte e voltar, offline e online; alternar follow sem alterar retroativamente cards existentes; uma fonte individual apresenta apenas conteúdo pertencente a ela; nenhum componente de View executa network ou resolve mídia remotamente.

**Fronteira:** F01 é **cobertura automática do catálogo**; F12 é **orientação e manipulação da descoberta pela pessoa**. Não reintroduzir o browser DEBUG-only da V1 por conveniência.

**PRD de especificação:** [PRD F12](F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md).

## F13 — Exclusões explícitas, bloqueios e editor de filtros [UI/UX]

**Promessa:** a pessoa controla o que **não quer ver** com regras explicáveis, editáveis e reversíveis; nenhuma exclusão vaza para o feed sem uma escolha consciente.

**V1 verificada:** [`ContentFilterView.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/ContentFilterView.swift) contém templates, criar regra por palavra-chave, habilitar/desabilitar e excluir customizações. V2 preserva `ReaderFilter` e regras de elegibilidade, mas a matriz diz que só o switch principal está desenhado; o editor não está.

**Investigação:** diferenciação entre filtro temporário de contexto, exclusão durável, preferência negativa no feed inicial (F02) e mute de Source/Provider; previsibilidade de AND/OR/escopo, preview do efeito, false positives, remover/desfazer, estado vazio honesto e persistência.

**Oráculo/aceite:** criar exclusão, verificar artigo conhecido excluído **de novas seleções**, reativá-lo ao remover a regra, reiniciar e confirmar persistência; um filtro não reescreve publicação já visível, nem abre exceção ao idioma rígido. Dar explicação legível do motivo da ausência de resultados sem revelar estado interno.

**Fronteira:** F07 define filtros e identidade editorial; F13 define **controle negativo compreensível** e seu editor. Evitar duas engines de exclusão.

**PRD de especificação:** [PRD F13](F13_CONTENT_CONTROL_EXCLUSIONS_UX_PRD.md).

## F14 — Experiência de ler, abrir e retornar [UI/UX]

**Promessa:** tocar uma história leva a uma leitura efetiva, dentro de navegação previsível, com destino reconhecível; voltar preserva a posição e a intenção original.

**V1 verificada:** [`ArticleReaderView.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/ArticleReaderView.swift) usava WKWebView, título da origem, progresso, fechar e abrir no Safari, incluindo mini-player. A V2 usa [`InAppBrowser.swift`](https://github.com/wsmontes/feedmine_v2/blob/main/FeedMineApp/FeedMineApp/InAppBrowser.swift) (`SFSafariViewController`), diferença aceita, mas sem teste executado de abrir artigo segundo a matriz.

**Investigação:** targetURL congelada, taps confiáveis, URL inválida/paywall/404, links externos, indicação de carga, navegação interna/external Safari, saída/retorno, mini-player, reabertura de salvos e retomada do feed com âncora. Não assumir que duplicar controles WKWebView seja solução: avaliar experiência nativa V2.

**Oráculo/aceite:** tap no card real abre URL do card, sem dead tap; voltar fecha corretamente e restaura identidade/posição; falha de página não destrói feed; deep link não apresenta outro artigo; visita não bloqueia write de histórico.

**Fronteira:** F03 verifica a **validade do conteúdo/destino** e F08 as ações; F14 verifica **reader/navigation UX**.

**PRD de especificação:** [PRD F14](F14_READER_LINK_NAVIGATION_UX_PRD.md).

## F15 — Podcasts e consumo de áudio contínuo [UI/UX]

**Promessa:** tocar episódio, ouvir, navegar por outras histórias e retomar sem perder controle nem posição temporal.

**V1 verificada:** [`MiniPlayerBar.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/MiniPlayerBar.swift) com mini/full player, progresso, seek ±15 e ações do episódio; [`AudioPlayerManager.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Services/AudioPlayerManager.swift) com posição salva. V2 tem `MiniPlayerBar`, `ReaderMediaCoordinator` e adapter AVFoundation; a matriz considera mini/full player exercitados, mas persistência da posição não comprovada.

**Investigação:** áudio real, URLs/capabilities de podcast, artwork local vs. mídia remota deliberada, play/pause/seek, interrupção de áudio, lock screen/background permitidos, fechar/abrir player, sessão desligada, reabrir app, navegar para fonte e bookmarks.

**Oráculo/aceite:** tocar episódio real, avançar tempo, sair para outro contexto, suspender/relançar e retomar episódio/posição conforme contrato definido; áudio não faz feed rolar, não exige baixar episódio inteiro para publicar card e não aciona rede só pela renderização.

**Fronteira:** F06 decide prontidão e geometria do card; F15 decide **reprodução explícita** e continuidade de experiência.

**PRD de especificação:** [PRD F15](F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md).

## F16 — Organização pessoal, caixas e feeds salvos [UI/UX]

**Promessa:** salvar é encontrar depois: bookmarks, múltiplas caixas, coleções de fontes e feeds inteligentes aparecem como destinos de leitura consistentes, não só como linhas salvas em SQLite.

**V1 verificada:** [`BookmarkBoxesView.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/BookmarkBoxesView.swift), [`CollectionManagementView.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/CollectionManagementView.swift), `BookmarkBoxPickerView` e `FeedPreset`. V2 tem stores e UI para listas e coleções; a matriz não comprova picker a partir do card, caixa como superfície de leitura nem políticas de atualização dos Smart Feeds.

**Investigação:** criar/renomear/reordenar/deletar, adicionar a múltiplas caixas, salvar a partir do card/reader, abrir caixa/coleção como `FeedPlan`, mover/retirar source sem excluir conteúdo pessoal, manter estados vazio e default box, persistir smart feed e revisar suas regras/refresh.

**Oráculo/aceite:** mesmo artigo em duas caixas, edição de uma não afeta a outra; abrir caixa ou coleção mostra conteúdos corretos, cartões acionáveis e retorno preservado; alternar feed principal → coleção → principal reutiliza contexto válido; excluir uma coleção não apaga Sources/salvos; restart conserva nomes/membership.

**Fronteira:** F08 garante *ações* e estado durável; F16 garante **navegação e modelo mental da biblioteca pessoal**.

**PRD de especificação:** [PRD F16](F16_PERSONAL_LIBRARY_SMART_FEEDS_UX_PRD.md).

## F17 — Idioma da interface, aparência e leitura inclusiva [UI/UX]

**Promessa:** FeedMine é legível e usável no idioma e nas condições visuais da pessoa, distinguindo **idioma do conteúdo adquirido** de **idioma da interface**.

**V1 verificada:** [`LocaleManager.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Services/LocaleManager.swift) listava 39 opções, incluía árabe e hebraico, e `SettingsSheetView` oferecia escolha/restart; design circadiano/tipografia/night em `CircadianEngine`. V2 porta tokens, preferências e `ReaderAppearance`, mas `ReaderSettingsView` registra explicitamente ausência de picker de idioma e de String Catalog; ativos/fontes, RTL e fidelidade visual não foram provados.

**Investigação:** tradução de UI e estado de idioma, suporte real de l10n vs. escolhas anunciadas, fallback, RTL, Dynamic Type, VoiceOver, contraste e redução de movimento, night/circadian sem reposicionar cards, seleção de idioma de conteúdo independente da tradução de botões. Não prometer 39 idiomas sem cobertura real.

**Oráculo/aceite:** mudar idioma suportado e relançar; explorar busca, onboarding, filtros, reader, ações, saved e estados de erro em locale escolhido; RTL navegável e texto ampliado com âncora estável. Evidência visual light/dark/night e locale com fontes reais; falhas registradas por superfície.

**Fronteira:** F10 valida acessibilidade/recursos para release; F17 especifica a **experiência de apresentação e linguagem**. Não copiar timer circadiano/singleton da V1.

**PRD de especificação:** [PRD F17](F17_LOCALIZATION_APPEARANCE_ACCESSIBILITY_UX_PRD.md).

## F18 — Entrada manual de fontes e portabilidade [UI/UX + interoperabilidade]

**Promessa:** copiar uma URL ou importar OPML vira uma escolha clara e verificável, não um fluxo técnico de parsing; exportações permitem sair com os dados pessoais.

**V1 verificada:** [`AddFeedView.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/AddFeedView.swift) possuía URL paste, clipboard, preview, confirmação e adicionar à coleção; `ClipboardBanner`, `InputParser`, `OPMLParser`, `ExportView`. V2 comprova parte do pipeline import/export e preview, mas não tela de colar URL nem os gestos Add/Dismiss do banner.

**Investigação:** input URL/feed/site/múltiplos URLs/OPML, dedupe, redirect e request URL distinto da identidade editorial, validação e prévia sem persistência acidental, falhas parciais, importação para coleção, permissão de clipboard, exportação roundtrip e arquivo corrupto.

**Oráculo/aceite:** copiar URL → abrir app → adicionar à coleção certa → ver Source na coleção sem duplicação; OPML com repetição/errors mostra contagem verdadeira e importa válidos sem descartar toda a operação; exportar/voltar a importar preserva fontes e organização dentro do formato suportado; cancelar não escreve.

**Fronteira:** F01 é fonte gerenciada automaticamente; F18 é **interoperabilidade por iniciativa do usuário**; F09 protege durabilidade. Não exigir importação antes de primeiro feed.

**PRD de especificação:** [PRD F18](F18_ADD_FEED_CLIPBOARD_OPML_PORTABILITY_PRD.md).

## F19 — Compartilhar descobertas com contexto [UI/UX]

**Promessa:** compartilhar a notícia ou a fonte é direto; destino, título, atribuição e mídia comunicados são corretos e não dependem de downloads no renderer.

**V1 verificada:** [`ShareCardImageView.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/ShareCardImageView.swift) renderizava imagem compartilhável; [`StatsShareCard.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Views/StatsShareCard.swift) gerava cartão de estatísticas; menu oferecia link/copy/share/open Safari. A V2 trouxe cópia/link, mas a matriz registra imagem/stats como **diferenças aceitas, não portadas**.

**Investigação:** proposta real de valor de compartilhar imagem vs. URL, preview com texto/atribuição consistentes, privacidade de métricas pessoais, falha de rede, textos sem imagem, provenance/source correta, affordances habilitadas apenas quando a ação existe.

**Oráculo/aceite:** share/copy de artigo, podcast e source em test fixtures; payload aponta para conteúdo correto e preserva título/attribution. **Não exigir** retorno de share-as-image e stats antes de decisão explícita de produto; avaliar custo/benefício e documentar **manter de fora** quando apropriado.

**Fronteira:** F08 garante roteamento básico das ações; F19 decide a **qualidade e o alcance do compartilhamento**.

**PRD de especificação:** [PRD F19](F19_SHARING_DISCOVERY_UX_PRD.md).

## F20 — Retorno, novidades e transições de ciclo de vida [Produto + UX/runtime]

**Promessa:** ao voltar ao FeedMine, o leitor reconhece o que já estava lendo, percebe novidades reais sem perder a posição e não confunde *história antiga* com *conteúdo recém-adquirido*.

**V1 verificada:** [`WhatsNewManager.swift`](https://github.com/wsmontes/feedmine-dev/blob/main/feedmine/Services/WhatsNewManager.swift) mantinha candidatos a "What's New" e baseline da última vez, com carousel/booster; `FeedScreen.handleScenePhase` persistia scroll/áudio e atualizava badge. A matriz não comprova na V2 execução de badge/scene-phase nem equivalência com o recurso de novidades.

**Investigação:** diferença entre atualização do **supply** e do **feed publicado**; sinal discreto "novas histórias" sem inserir/reordenar no viewport; retorno de background/force-quit/offline e cold bootstrap; o que conta como novidade por contexto e por feed; notificações/badge só quando houver benefício demonstrável; handoff para áudio/salvos.

**Oráculo/aceite:** entrar em contexto A, ler até card X, ir ao background, adquirir novos registros, voltar a X sem jump; sinalizar nova Edition disponível quando apropriado, com ação clara e não intrusiva; offline mantém publicação anterior; retorno repetido não fabrica "novas" nem duplica exposição.

**Fronteira:** F05 garante runway durante consumo e F09 restore técnico; F20 define **a experiência de voltar e perceber novidade**. **Não portar** `whatsNewThreshold=10`, booster `prefix(30)`, timers ou segunda seleção da V1: eram mecanismos antigos, não invariantes de produto.

**PRD de especificação:** [PRD F20](F20_RETURN_FRESHNESS_LIFECYCLE_PRD.md).

---

## Contrato de documentação por frente

Cada PRD F11–F20 deverá conter a mesma estrutura da primeira onda: `PROMESSA`, `EVIDÊNCIA V1` (arquivo/função/fluxo real), `V2 COMPROVADA` (código e teste executado com hash/ambiente), `LACUNA/DECISÃO`, `JORNADA E ORÁCULO`, `CRITÉRIOS DE ACEITE`, `FRONTEIRA/OWNER EXISTENTE`, `NÃO-OBJETIVOS`, `RISCO RESIDUAL` e `RESULTADO` (PASS/FAIL/NOT_RUN/BLOCKED).

**Sequência recomendada:** F11 → F12 → F13 → F14 → F16 → F15 → F17 → F18 → F20 → F19. Agrupar mudanças de código só quando um mesmo owner do fluxo justificar; as frentes continuam testes de produto independentes. Nenhuma decisão sobre deixar de fora um recurso da V1 deve ser revertida implicitamente por um agente.

**Tratamento de evidência:** há três níveis a registrar separadamente: (a) interface/serviço existe; (b) teste automatizado executou um cenário específico; (c) pessoa percorreu a jornada real e observou o resultado. Nos documentos atuais, `validado` da matriz de transferência frequentemente significa (a) ou (b), **não** necessariamente (c). O corpus e a revisão do GitHub mudam; verificar `main` atual no início de cada frente.

**Não-objetivos transversais:** transferir órfãos conhecidos da V1 (`StoryDuelScene`, `SourceSearchDetailView`), recriar `FeedStore`/bus de eventos, acrescentar network ao renderer, reproduzir cotas mágicas de novos cards, reabrir o onboarding obrigatório ou declarar PASS por screenshots sem interação verificável.

## Índice dos dez PRDs — especificações de produto/UX

Este mapa de investigação está conectado ao [mapa de impactos, gargalos e benchmarks UX11–UX20](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md). Cada frente agora possui seu **PRD de comportamento observável**, separado da implementação:

- [F11 — Busca unificada e resultados](F11_UNIFIED_SEARCH_RESULTS_UX_PRD.md)
- [F12 — Explorar fontes, regiões e assuntos](F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md)
- [F13 — Filtros de conteúdo e exclusões](F13_CONTENT_CONTROL_EXCLUSIONS_UX_PRD.md)
- [F14 — Leitor integrado e retorno](F14_READER_LINK_NAVIGATION_UX_PRD.md)
- [F15 — Podcasts e áudio](F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md)
- [F16 — Biblioteca pessoal e Smart Feeds](F16_PERSONAL_LIBRARY_SMART_FEEDS_UX_PRD.md)
- [F17 — Idioma, aparência e acessibilidade](F17_LOCALIZATION_APPEARANCE_ACCESSIBILITY_UX_PRD.md)
- [F18 — Adicionar fontes e portabilidade](F18_ADD_FEED_CLIPBOARD_OPML_PORTABILITY_PRD.md)
- [F19 — Compartilhar descobertas](F19_SHARING_DISCOVERY_UX_PRD.md)
- [F20 — Retorno, novidades e ciclo de vida](F20_RETURN_FRESHNESS_LIFECYCLE_PRD.md)

**Nota:** os dez PRDs de especificação estão criados; suas **provas de UX ainda não foram executadas**. O contrato B01–B06 continua inalterado.
