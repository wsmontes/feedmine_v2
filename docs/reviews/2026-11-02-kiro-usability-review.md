# Revisão de usabilidade (código, sem simulador) — 2026-11-02

Base: `origin/main` `2eca5b4`. Tudo aqui vem de leitura de código; nada foi executado em simulador
ou aparelho. **V** = caminho completo lido; **S** = suspeita (um elo não lido ou depende de runtime).

## 1. Botões e ações que não funcionam ou falham calados

| # | Sev | O que o leitor vê | Evidência | |
|---|---|---|---|---|
| B1 | Alta | "Excluir feed curado" e "Excluir marcador inteligente" aparecem sempre. Num marcador inteligente, "Excluir feed curado" apaga o marcador; num feed comum, "Excluir" não faz nada e não diz nada | `AppComposition.swift:2984-2986` (destinos incondicionais), `:1560-1569` (`deleteCurrentPreset` apaga o preset atual, seja qual for, ou retorna), `FeedMineApp.swift:778-781` (mesma ação para os dois, `try?`) | V |
| B2 | Alta | "Abrir o capô do feed curado" e "Salvar como marcador inteligente" aparecem em todo contexto, inclusive sem feed curado e sem busca | `AppComposition.swift:2984-2986`; `FeedScreenStore.hasCommittedSearch` existe e não é usado | V |
| B3 | Média | Colar links depois de uma prévia pendente: "Adicionar" adiciona só o lote antigo e apaga o colado | `ReaderAddFeedViews.swift:141-145` (`pasteFromClipboard` não zera `pendingProposal`, ao contrário de `setInput` `:133-139`), `:176-178` | V |
| B4 | Média | Alertas de erro de Ajustes, Filtros de conteúdo, Coleções e Caixas: "OK" não limpa o erro | `set: { _ in }` em `BookmarkBoxesView.swift:113`, `CollectionsView.swift:132`, `ReaderContentFilterView.swift:299`, `ReaderSettingsView.swift:122` | V (efeito exato: S) |
| B5 | Média | Erros silenciosos (`try?`): reunir fontes (abre Coleções mesmo sem criar), salvar marcador, excluir preset, abrir feed da coleção, abrir preset salvo, criar feed nos ajustes | `FeedMineApp.swift:781,792-796`, `:701-707`, `:717-720` | V |
| B6 | Média | Alternar fontes/países que falha volta atrás sem mensagem; "Todos os países" sem progresso | `SourceManagementStore` define `errorMessage`/`isLoading`; nenhuma das views de fontes os lê (0 ocorrências) | V |
| B7 | Média | Tocar num salvo (ou resultado de busca) sem texto nem URL usável não faz nada | `AppComposition.swift:3243-3252` (`guard ... else { return }` sem toast) | V |
| B8 | Média | Exportar: "Salvar arquivo" e "Compartilhar" fazem a mesma coisa; falha de escrita não aparece | `FeedMineApp.swift:1763-1764` | V |
| B9 | Baixa | Lupa ("Fechar busca") e "Cancelar" fecham a busca de formas diferentes; pela lupa, resultados antigos reaparecem e o contexto de origem pode não ser restaurado | `FeedScreenStore.toggleSearch` vs `cancelSearch` | V (restauração: S) |

## 2. Becos sem saída

| # | Sev | Situação | Evidência | |
|---|---|---|---|---|
| D1 | Alta | Falha de inicialização (catálogo local ou seleção de fontes) mostra só uma frase numa tela vazia: sem botão, sem cabeçalho, sem tentar de novo. Só matando o app | `FeedMineApp.swift:561-562` `Text(failure).padding()` | V |
| D2 | Média | Sem cards: estado `.failed` mostra a mensagem crua sem ação; "Descobrindo histórias…" não tem ação nem limite (comentário registra >7 min medidos) | `FeedLoadingView` `recoveryActions` (`default: EmptyView()`) | V |
| D3 | Média | Filtro com rascunho desatualizado: "Salvar" falha para sempre com mensagem genérica; `revert()` existe e nenhuma UI chama | `ReaderFilterStore.swift:80-83,111-114,135`; `FeedMineApp.swift:394-395` | V (frequência: S) |
| D4 | Média | Coleção vazia diz "Adicione fontes a partir de um card…" sem botão; "Abrir o feed" fica desabilitado | `CollectionsView.swift:204,212-215` | V |
| D5 | Média | Leitor de recuperação de histórico: tudo cinza e cards mortos; a explicação só existe para VoiceOver; a única saída é um item dentro do "⋯" | `FeedMineApp.swift:552-556` (`readingIsPaused: true`), `ReaderHeader.swift:183` | V |
| D6 | Média | Falha ao salvar o onboarding: a capa já fechou e nada a reabre | `FeedMineApp.swift:1510-1517` | V (recálculo posterior: S) |
| D7 | Baixa | Lista de salvos: falha de leitura pede "reabra" sem botão de tentar de novo | `FeedSavedListView.swift:83-90` | V |

## 3. Perturbações no feed

| # | Sev | Sintoma | Evidência | |
|---|---|---|---|---|
| F1 | Alta | A lista física para de crescer e o fim do feed some: o leitor bate num "fundo" sem spinner nem "Você chegou ao fim" | `FeedScreenStore.install` (só aceita extensão por append); `FeedScreen.endOfContentBlock` só desenha se o último físico == último lógico; `workFeedback` só com lista vazia | V (já no handoff anterior; linha de branches `native-*` trabalhando) |
| F2 | Alta | Ao trocar de contexto/edição, se a imagem da âncora ainda não decodificou, a tela volta para "Descobrindo histórias…" mesmo com conteúdo pronto | `FeedReadyVisualWindow.initial` retorna nil para âncora não pronta; `install` instala `[]` | V (mecanismo) |
| F3 | Média | Blocos editoriais "FeedMine sugere" entram na célula de um card possivelmente visível quando a rolagem para, empurrando o conteúdo | `FeedMineApp.swift:1534-1600` (só `index > anchorIndex` e não exposto) | S |
| F4 | Média | "Voltar ao início" vai ao topo do que está montado, não ao início do histórico; às vezes não faz nada | `FeedScreen` `onReturnToStart` (`items.first`), `FeedPositionRequest.apply` | V |
| F5 | Baixa | Card já lido nunca aparece como lido (estilo existe, nunca é passado) | `FeedScreen` constrói `FeedItemView` sem `isRead:` (0 ocorrências) | V |
| F6 | Baixa | Compacto do convite editorial escreve "FeedMine sugere" duas vezes | `FeedEditorialInvitationView.swift` ~50 e ~72 | V |

## 4. Funcionalidades básicas faltando

| # | Sev | Falta | Evidência | |
|---|---|---|---|---|
| M1 | Alta | Puxar para atualizar, ou qualquer atualização com cards na tela (offline ou falha só se recupera com a lista vazia) | 0 ocorrências de `refreshable`; "Tentar novamente" só em `FeedLoadingView` | V |
| M2 | Alta | Remover um item da lista de Salvos (sem swipe, menu ou botão); só dá para desmarcar pelo card no feed | `FeedSavedListView.swift` (0 `swipeActions`/`onDelete`/`contextMenu`) | V |
| M3 | Média | Fechar o mini player: fica na tela pelo resto da sessão, inclusive depois de "Não foi possível tocar" | `MiniPlayerBar` só tem tocar/abrir; `stopMedia()` não tem chamador na UI | V |
| M4 | Média | Player cheio mostra erro e "Carregando…" juntos para sempre quando a mídia falha | `MiniPlayerBar.swift` `scrub` com `duration == nil` | V |
| M5 | Média | Leitor local sem compartilhar, copiar link, salvar ou tamanho de texto | `FeedReadingSurface.swift` (só fechar / Site / Abrir no site) | V |
| M6 | Média | Busca nas fontes (catálogo/países); a busca do store existe e nenhuma view usa | `SourceManagementStore.search` sem chamador nas views | V |
| M7 | Média | Mover salvo entre caixas; confirmar ao apagar caixa (Coleções confirmam, Caixas não) | `BookmarkBoxesView.swift` swipe "Apagar" direto | V |
| M8 | Baixa | Lista de Salvos limitada a 200 sem aviso | `AppComposition.swift:3304,3313,3337` | V |
| M9 | Baixa | Restaurar padrões nos Ajustes; escolher fonte fixa (só com tipografia adaptativa ligada) | `ReaderSettingsView.swift:180` | V |
| M10 | Baixa | Compartilhar visível no card (só no toque longo); no iPad em lista, salvar só no toque longo | `FeedItemCardView`/`FeedItemView` | V |

## 5. Texto e acessibilidade

- Humor no filtro aparece em inglês ("Serious", "Fun", "Technical", "Inspiring"); os chips de tipo também ("Articles", "Videos", "Podcasts"): `FilterSheetView.swift:276`, `ReaderFilterLens.swift:117,130` usam `rawValue` de `ReaderFilter.swift:22-48`. **V**
- "carta" no lugar de "card": `AppComposition.swift:3030` ("Esta carta não declara uma fonte") e `:5248` ("Não foi possível abrir esta carta"). **V**
- VoiceOver em inglês: `accessibilityValue("selected"/"not selected")` em `NodeSourcesView`, `CountriesListView`, `FilterSheetView`, `TaxonomyBrowseView`. **V**
- Badge de filtros e ponto de caixa ativa não entram no rótulo de VoiceOver (`ReaderHeader.swift:110-131`). **V**
- Dois botões "Concluir" lado a lado ao reordenar caixas (`BookmarkBoxesView.swift:76-89`); "Concluir" em Países volta, em Nós aplica e fecha (`FeedMineApp.swift:357-365`). **V**

## Corrigido em relação aos relatórios intermediários

Os acentos ("Nao", "coleçao", "possível") estão corretos no código: eram artefato da saída do console
do Windows. Arquivos verificados como UTF-8 válido; o único problema de texto real é "carta".

## O que está bem (V)

Botões do cabeçalho com 44×44 e rótulos; todas as folhas têm saída (botão ou gesto); capa de
preparação tem limite de tempo; estado "sem fontes" com ação; fim de conteúdo sem cards com
"Explore outros assuntos" e "Ampliar fontes"; `.unavailable`/`.unreachable`/`.deferred` sem cards
oferecem "Tentar novamente"; lista congelada sob o dedo durante o gesto; altura do hero fixa pela
proporção (imagem tardia não move o texto); áudio em segundo plano, controles da tela bloqueada,
pausa em interrupção e retomada de posição; Safari interno volta à superfície de origem; prévia antes
de importar; confirmação antes de excluir fonte e coleção.

## Ordem sugerida de correção

1. D1 (tela de falha com "Tentar novamente" e acesso a Fontes/Ajustes).
2. B1 + B2 (destinos de preset condicionados ao contexto; ação de excluir por tipo).
3. M1 (`.refreshable` chamando `refreshFromTheReader`) e retry com cards na tela.
4. M2 (swipe "Remover dos salvos" na lista).
5. F1/F2 — dependem da linha `native-*` em andamento e de simulador.
6. B3–B8, D2–D4, M3/M4: correções pequenas e locais.
7. Textos e acessibilidade.
