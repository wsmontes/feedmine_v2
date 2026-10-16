# Jornadas de usuário exigidas pela V1 × o que a V2 entrega e o que a bateria cobre

**Data:** 2026-10-15 · **Autor:** agente `V1Journeys` (tarefa delegada pelo agente principal)
**Pergunta que este relatório responde:** quais jornadas visíveis ao usuário os documentos da V1 exigem, o que a V2
faz hoje em cada uma e — o ponto que o dono do produto pediu — **quais dessas jornadas não têm nenhum teste de
jornada** (um teste que abre o app e observa o resultado visível).

## 0. Método, ambiente e limites (para poder desconfiar deste relatório)

| Item | Valor |
|---|---|
| Repositório V2 | `/Users/<user>/Documents/GitHub/feedmine_v2`, `HEAD = 2cb61bbba94d7dc0854fcc1316d79602cf78cc72` (branch `main`), **árvore limpa** no momento da leitura |
| Repositório V1 | `/Users/<user>/Documents/GitHub/feedmine`, `HEAD = 712a6ba93c6a8ab28c3b3c0e2b2777d1e3341d0c`, branch `fix/release-1.0-final-hardening`, **árvore suja com 27 arquivos** (a condição que `docs/reviews/V1_UI_REFERENCE.md:6-11` já registra). Nenhum dos arquivos citados neste relatório está entre os sujos: as citações do V1 são documentos em `docs/` e dois arquivos de teste em `feedmineUITests/` |
| Comandos | só leitura: `read`, `grep`, `glob`, `git rev-parse`/`git status` (2 execuções). **Nenhum build, nenhum teste, nenhuma instalação** — por instrução da tarefa |
| Identidade | `git rev-parse HEAD` nos dois repositórios (acima). Os números de linha deste relatório valem para essas duas revisões e para as árvores sujas descritas |
| Corpus | os benchmarks `B01`–`B05` citados foram executados em `bench/run/20261011T*` e estão registrados em `docs/evidence/ACCEPTANCE_RECORD.md`; **este relatório não executou nenhum deles** |

Convenção: toda afirmação tem `arquivo:linha`; citações são **verbatim** no idioma do documento.

## 1. Checklist das jornadas que os documentos da V1 exigem

### 1.1 A doutrina do produto — declarada pelo dono como critério de aceitação

`/Users/<user>/Documents/GitHub/feedmine/docs/release/1.0-checklist.md:3114`:

> **Product doctrine (user, verbatim intent) — this is the acceptance criterion, not a suggestion**

> **The front must be calm and stable; the backend must be a hurricane.**

Os nove itens (`:3118-3132`), cada um e a jornada que ele obriga:

| # | Citação (verbatim) | `1.0-checklist.md` | Jornada exigida |
|---|---|---|---|
| 1 | "The first open **may** be slow — that is what the loading screen is for, as are radical filter changes." | `:3118` | abrir o app pela primeira vez; a tela de carregamento existe e é legítima |
| 2 | "The loading screen must be **dynamic and progressive**, showing **what is happening**." | `:3119` | a preparação declara o que está acontecendo (não uma barra opaca) |
| 3 | "**As soon as there is content to show, leave the loading screen and show the feed.**" | `:3120` | primeira tela com cards: a espera termina quando há conteúdo |
| 4 | "**The feed is sacred.** It only ever contains *ready* content: card assembled, image showing, everything pretty and in order. No broken image, no content moving on its own, no scroll jank, no reordering. The feed changes **only when the user wants it to change**." | `:3121-3123` | imagem aparecendo **no card**, sem imagem quebrada, sem movimento/reordenação por trabalho de fundo |
| 5 | "**The feed is infinite.** Once it appears and the user scrolls, the next content must already be ready to enter, entering without jerks and without disturbing the experience." | `:3124-3125` | rolagem contínua: o próximo card já está pronto |
| 6 | "Facing the user: stable and calm. In the backend: fast, multitasking, and **self-guaranteeing for any situation**." | `:3126` | estabilidade do que está na tela sob trabalho concorrente |
| 7 | "The database fills as fast as possible with content **first inside the current filtering**; once that is complete it keeps preparing for **anything that could be asked for**." | `:3127-3128` | baixar conteúdo: enche o contexto atual e continua preparando o futuro |
| 8 | "Given enough time, a filter change updates **only from what is already there** — ready cards, all pretty — and the background then starts adjusting to the new reality." | `:3129-3130` | troca de filtro: A→B com banco preparado não mostra tela vazia |
| 9 | "**Close and reopen the app: the feed must appear immediately**, from the ready content of the previous interaction. \"Nobody opens Instagram and waits for Instagram to find content.\"" | `:3131-3132` | reabrir o app: o feed aparece imediatamente, do conteúdo já preparado |

O dono **reafirmou** dois desses itens depois, e o documento os registra:

- `1.0-checklist.md:3220-3224`: "**Reprioritisation: the reopen criterion is the headline** … The user restated the acceptance criteria directly: **close and reopen the app, the feed must appear immediately**, from the ready content of the previous interaction, with no loading screen; and a filter change with a prepared database must render only from what is already there, ready cards, no loading, no reordering."
- `1.0-checklist.md:3410-3411`: "**Item 9 as written stays OPEN**, because it reads \"the feed must appear immediately … with no loading screen\" and only its ready-content half is measured".

### 1.2 As jornadas certificadas por basename (o portão de release da V1)

O harness de jornada da V1 (`feedmineUITests/PersonaExplorationUITests.swift`) declara-se como evidência, não como visita:
`:14-17`:

> "The tour navigates broadly and saves evidence, but it is not evidence-free: the surfaces it *promises* are asserted (the reader pair; a warm reopen that shows cards with no loading screen) …"

As 17 superfícies obrigatórias, na ordem do arquivo: `01-main-feed` (`:55`), `02-main-feed-scrolled` (`:62`),
`03-article-reader` (`:88`), `04-article-scrolled` (`:94`), `05-filter-sheet` (`:139`), `06-filter-sheet-scrolled`
(`:142`), `07-search-screen` (`:152`), `08-search-results` (`:158`), `09-more-menu` (`:170`),
`10-more-menu-scrolled` (`:173`), `11-settings` (`:206`), `12-settings-scrolled` (`:209`), `13-add-feed` (`:223`),
`14-browse-topics` (`:242`), `15-topics-scrolled` (`:245`), `16-context-menu` (`:260`), `17-reopen` (`:359`).
O passo do reopen é narrado como o critério principal em `:265-267`: "**11. Reopen — the headline acceptance
criterion: close and reopen the app and the feed is already there, from the page the previous interaction
persisted, with no loading screen in between.** The 16 surfaces above never relaunch, so this had never been measured."
E o próprio teste falha quando uma superfície de carregamento sobrevive ao reopen: `:386-388`
("the criterion is a warm start with no loading screen in between").

O resultado certificado está em `docs/release/HANDOFF.md:66`: "**User journey** `testCaptureAllScreens`: **17/17
required surfaces, 0 absent** (basename set `01-main-feed` … `17-reopen`)". E a regra de certificação, que é a
lição que o dono carrega para a V2, em `HANDOFF.md:119-123`: "**Certify a journey by its required basename set,
never by a file count** — and let that set *decide the exit status* … both acceptance scripts exit 1 on any missing
required surface". Complemento de instrumentação medido: `HANDOFF.md:130-132` ("A readiness gate that expires
before the app is ready fabricates surfaces") e `1.0-checklist.md:3245-3247` ("cold install — no `simctl uninstall`
or reinstall between the two launches (that would report the opposite of the doctrine)").

### 1.3 As doze jornadas P0 de usabilidade (UX-001…UX-012)

`docs/quality/FeedMine-Validation-Report.md:171`: "**Phase 5 (Usability Regression Tests):** Implement 12 P0 journey
tests (UX-001 through UX-012)". Os resultados registrados (`:193-198`) nomeiam seis delas:

> `| UX-001 (First opening) | ❌ FAIL | Onboarding flow variation — topics screen not always present |`
> `| UX-003 (Search & follow) | ✅ PASS | Search UI accessible from main feed |`
> `| UX-004 (Context preservation) | ✅ PASS | Filter button confirms feed context preserved |`
> `| UX-007 (Podcast playback) | ✅ PASS | Mini-player area exists, app responsive without audio |`
> `| UX-009 (Offline usage) | ✅ PASS | Offline launch shows defined UI (no crash) |`
> `| UX-012 (Empty state) | ❌ FAIL | App lost connection (possible crash on repeated launch) |`

As definições com orçamento estão no próprio teste, `feedmineUITests/Usability/UsabilityJourneyTests.swift`,
no formato "Tarefa → Estado inicial → Intenção → Ações → Estado final → Orçamento":

| Jornada | Citação | Linha |
|---|---|---|
| UX-001 primeira abertura até conteúdo utilizável | "Tarefa: Abrir o app pela primeira vez e encontrar conteúdo utilizável. … Orçamento: ≤5 ações discricionárias antes de encontrar conteúdo." | `:29-33` |
| UX-003 buscar uma fonte conhecida | "Tarefa: Buscar uma fonte conhecida e ver resultados. … Orçamento: ≤4 ações após digitar a consulta." | `:53-57` |
| UX-004 consumir e voltar sem perder contexto | "Tarefa: Abrir um conteúdo e voltar sem perder posição. … Budget: 1 ação para abrir, 1 para voltar." | `:80-84` |
| UX-007 playback de podcast mantém o contexto | "Tarefa: Verificar que controles de áudio existem e são acessíveis. … Budget: Player deve ser alcançável a partir do feed." | `:111-115` |
| UX-009 uso offline | "Tarefa: Usar o app offline com conteúdo previamente carregado. … Budget: Abrir app e navegar sem rede." | `:146-150` |
| UX-012 estado vazio honesto | "Tarefa: Entender por que está vazio e encontrar uma saída. … Budget: Explicação visível e ação clara disponível." | `:170-174` |

As outras seis (`UX-002`, `005`, `006`, `008`, `010`, `011`) são declaradas como parte do mesmo conjunto de 12 P0 em
`FeedMine-Validation-Report.md:171`, mas **as suas definições não estão versionadas neste repositório** — o grep por
`UX-0\d\d` em todo o repo V1 só encontra o relatório de validação e este arquivo de teste. Isso é um limite de
evidência, registrado aqui: para `UX-002/005/006/008/010/011` existe o número, não o enunciado.

### 1.4 Jornadas exigidas por outros documentos da V1

| Jornada | Citação (verbatim) | Fonte |
|---|---|---|
| Card entra no feed **resolvido** (imagem final, placeholder final ou layout sem imagem) | "Garantir que todo card entre no feed em um estado visual definitivo. Quando o card se tornar visível, ele já deve possuir uma destas apresentações: * imagem final carregada; * placeholder final; * layout sem imagem. Depois de publicado no feed, o card não deve: * iniciar downloads; * trocar placeholder por imagem; * substituir uma imagem por outra de melhor qualidade; * alterar seu layout por causa do resultado de uma requisição." | `docs/cards-resolvidos-antes-de-aparecer.md:7-18` (V1) |
| Feed abre direto num fluxo vertical contínuo, carregando por posição de rolagem | "Feedmine is an RSS reader that opens directly into a continuous vertical feed. Article cards scroll vertically with automatic content loading triggered by scroll position." | `docs/superpowers/specs/2026-06-30-feedmine-infinite-feed-design.md:10` (V1) |
| Toque no card abre o artigo inteiro, sem tela intermediária | "Tap on any card opens the full article in a sheet via WKWebView. The card in the feed IS the preview — no intermediate screen." | `docs/superpowers/specs/2026-07-01-in-app-reader-design.md:8` (V1) |
| Aceitação do leitor in-app | "- Tap card → sheet opens with full article via WKWebView\n- Sheet dismisses by swiping down" | `…/2026-07-01-in-app-reader-design.md:67-70` (V1) |
| Canais de entrada de feed (colar/partilhar/URL scheme) | "2.1 \| Canais de importação \| Pipeline pronto. Implementar: paste URL, share sheet, URL scheme" | `docs/roadmap.md:33` (V1) |
| Modo escuro | "2.2 \| Dark mode \| Palettes só claras. Adicionar variantes escuras ou forçar `.preferredColorScheme(.light)`" | `docs/roadmap.md:34` (V1) |
| Primeiro uso guiado (não 101 países desligados sem explicação) | "2.3 \| Onboarding \| Primeiro uso com 101 países OFF sem explicação. Guiar o user" | `docs/roadmap.md:35` (V1) |
| Trabalho de fundo só acrescenta abaixo do prefixo visível | "**Append-only background work.** This is the rule that delivers \"no updates appearing on screen\". Background work may only *append below* the displayed prefix; only a user action (filter, preset, refresh, shake) may replace what is visible." | `1.0-checklist.md:774-776` (V1) |
| Tela de conteúdo/download legível e atraente | "**Content/downloads screen.** Make the in-progress state legible and attractive: what is being fetched, from where, how far along, and what is already available." | `1.0-checklist.md:783-784` (V1) |
| Página da fonte com histórico local, sem substituir a composição do feed | "Ela precisa usar o mesmo conceito do feed principal, mas em uma sessão independente." + "O source não deve substituir a composição editorial do feed principal." | `docs/code-review-filtros-shake-source.md:297,325` (V1) |
| "View Source" tem de passar pelo pipeline de imagens | "# 3. \"View Source\" ignora o pipeline de imagens" | `docs/code-review-filtros-shake-source.md:198` (V1) |
| Troca de filtro não pode mostrar um card sozinho / tela vazia | "# 1. Troca de filtro mostra um card sozinho" | `docs/code-review-filtros-shake-source.md:24` (V1) |
| Estado vazio só quando é verdadeiramente vazio | "`FeedEmptyStateView` só pode ser mostrada quando:" | `docs/code-review-filtros-shake-source.md:184` (V1) |
| Promessas ao usuário no release | "FeedMine is a local-first RSS, podcast, YouTube, video, and forum reader. It does not require an account. Users can add their own feeds or choose sources from the bundled catalog. The app fetches public feed URLs directly and stores reading state locally." | `docs/AppStoreSubmission.md:51-54` (V1) |
| Nenhum botão morto no app que embarca | "Remove or hide any UI affordance whose implementation is knowingly non-functional in the shipping configuration; do not ship dead buttons." | `docs/release/1.0-application-closure-plan.md:30` (V1) |
| Aparelho físico como parte da operação de teste | "Este documento descreve como um agente (Codex, Claude ou uma pessoa no Terminal) compila o FeedMine, instala no iPhone conectado e opera o app por meio de testes" | `docs/PhysicalDeviceTesting.md:4-5` (V1) |

### 1.5 Onde a própria V2 registra essas exigências da V1 (e as metas medidas)

O estudo da V1 dentro da V2 repete as mesmas exigências e fixa **metas numéricas medidas** — cito porque o dono as
usa como referência de "o que a V1 já fazia":

| Exigência / medida | Citação | Fonte (V2) |
|---|---|---|
| Feed sagrado é a promessa nº 1 | "**\"Feed is sacred.\"** No reorder near the reader, no head removal, no scroll jump, published IDs never change. \| It is the top product promise, and the v1 build-16 review traces the main regressions to breaking it." | `docs/v1-study/00-README.md:47` |
| Metas de performance a carregar | "**Measured targets** \| Warm relaunch 234 ms, cold first install 28.5 s for 20 cards (both iPhone 16, build 16)." | `docs/v1-study/00-README.md:54` |
| Disciplina de release | "**Release discipline** \| Every build maps to a SHA, clean container between runs, journeys certified by basename set." | `docs/v1-study/00-README.md:55` |
| Metas medidas (detalhe) | "**Measured performance targets to carry forward (from `release/HANDOFF.md`, build 16 on iPhone 16):** warm relaunch loading surface **234 ms** (page restored from disk, no refetch); cold first install **28.5 s** for 20 cards off network (empty SQLite) … Filter case A measured **8.19 s blank** when the page is cleared — the known lever is *don't clear a prepared page*, not query tuning." | `docs/v1-study/06-history-lessons.md:64` |
| Card terminal antes da publicação | "**Terminal card before publication.** The core thesis of `docs/cards-resolvidos-antes-de-aparecer.md`: a card enters the feed only in a final visual state (image / placeholder / text-only); no post-insertion downloads, no placeholder→image swap." | `docs/v1-study/01-feed-pipeline.md:87-89` |
| O que a V1 quebrou e a V2 não pode repetir | "**In-place media mutation shipped and shifted layout.** Build-5 finding 1 documents a published text card growing a 16:9 hero slot when a late download arrived, over a reading user." | `docs/v1-study/01-feed-pipeline.md:120-121` |

### 1.6 A exigência do lado V2 que incide sobre as mesmas jornadas

Estas não são exigências da V1, são as que **hoje** regem a V2; entram na tabela de lacunas porque é contra elas que
uma jornada sem teste fica descoberta.

- `docs/product/PRODUCT_NORTH_STAR.md:70-81` — §4 "Comportamentos perceptíveis que precisam ser preservados", itens 1–8
  (primeira abertura honesta `:74`, começar ≠ terminar `:75`, scroll contínuo `:76`, "**O feed visível não se move
  sozinho**" `:77`, mudar de ideia é barato `:78`, melhor estado local primeiro `:79`, escassez com clareza `:80`,
  "**O conteúdo merece boa apresentação.** Imagem, texto, mídia e origem … Falta de imagem não deve transformar um
  card em uma composição quebrada." `:81`), e `:119-121` ("Ao avaliar V2, teste jornadas completas, não apenas
  componentes isolados").
- `docs/architecture/PRODUCT_INVARIANTS.md` — INV-03 scroll é observação `:22`, INV-05 trabalho continua depois da
  primeira apresentação `:68`, INV-06 primeira abertura pode demorar `:76`, INV-07 warm launch é local `:84`,
  INV-08 história publicada imutável `:103`, INV-09 background não perturba o visível `:109`, INV-10 troca de contexto
  não destrói `:115`, INV-11 offline é condição de primeira classe `:124`, INV-17 candidato pendente sai da fila `:174`.
- `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md` — B01 `:41`, B02 `:55`, B03 `:68`, B04 `:82`, B05 `:90`, B06 `:98`,
  com a regra de que "NOT_RUN ou BLOCKED **não** equivalem a PASS" (`:12-16`) e a matriz de veredictos atuais em
  `docs/evidence/ACCEPTANCE_RECORD.md:14-21`.
- `docs/product/F27_DEVICE_PRESSURE_PERFORMANCE_EVIDENCE_PRD.md:15-18,22-26` — UX27-A…F, inclusive "**UX27-C:** CPU/thermal
  pressure: comparar hitches e taxa de requests antes/depois" e "simulador é útil para testes determinísticos; energia,
  jetsam, proteção de arquivos e decisão do scheduler exigem aparelho real. Não declarar B06 PASS sem execução física."

## 2. O que a V2 faz hoje (implementação verificada)

Cada linha foi confirmada abrindo o arquivo na revisão `2cb61bbb`.

| Jornada | Onde a V2 implementa hoje | Comportamento observável |
|---|---|---|
| Abrir o app | `FeedMineApp/FeedMineApp/FeedMineApp.swift:14` (`@main struct FeedMineApp`), `:23` (init constrói `AppComposition`), `AppComposition.swift:258` (`launch`) | o app sobe, constrói a composição e, sem associação, mostra "Abrindo feed local" (`FeedMineApp.swift:275`) |
| Onboarding | `FeedMineApp.swift:843` (`onboardingCover`), `:418` (`.fullScreenCover(isPresented:$showsOnboarding)`), `Sources/FeedMineUI/Onboarding/ReaderOnboardingView.swift:64` | 1º launch coberto por Welcome→Composer; as respostas viram o perfil de descoberta |
| Feed aparecendo | `Sources/FeedMineUI/FeedScreen.swift:48`, `FeedScreenStore.swift:161` (`renderedItems`), `FeedLoadingView.swift:29/67` | lista `renderedItems` em `LazyVStack` (`FeedScreen.swift:88`); antes disso, superfície de trabalho/preparação |
| Imagens/mídia no card | `Sources/FeedMineUI/Cards/FeedItemCardView.swift:226` (`heroSlot`), `:245-247` (`decodedImage`: `if let cgImage = card.image?.cgImage { Image(decorative:) }`), `Sources/FeedMineRuntime/PresentationCard.swift:85` (`isImageBearing`), `Sources/FeedMineMedia/MediaResolver.swift:26`, `Sources/FeedMineRuntime/MediaPrefetcher.swift:148` | o card desenha o bitmap já decodificado sobre um placeholder do mesmo tamanho; a escolha do candidato e o download ficam fora da view |
| Download / runway entre segmentos | `Sources/FeedMineComposition/FeedRunwayDriver.swift:135` (`submitViewport`) / `:171` (`.forwardScroll`), `Sources/FeedMineRuntime/RunwayController.swift:283`, `RunwayAcquisitionCycle.swift:37`, `AppComposition.swift:1619` | cada observação de viewport alimenta o runway; a lista admitida só cresce por admissão forward |
| Leitura do artigo | `FeedMineApp.swift:827` (`InAppBrowser(url:)`) / `:830` (`FeedReadingSurface`), `InAppBrowser.swift:17` (SFSafariViewController), `Sources/FeedMineUI/Reader/FeedReadingSurface.swift:33`, `AppComposition.swift:1781/1795` | texto guardado abre a superfície local de leitura; senão, a página no controlador in-app; fechar volta à origem |
| Rolagem | `Sources/FeedMineUI/FeedNativeScrollOffset.swift:17`, `FeedWindowOffsetCorrection.swift:10/33`, `FeedMineApp/FeedFrameMeter.swift:23-30` (CADisplayLink) | rolagem nativa + correção de offset; um medidor de quadros escreve o *hitch ratio* no traço do app (`FeedFrameMeter.swift:57`) |
| Background→foreground | `FeedMineApp.swift:581` (`.onChange(of: phase)`), `AppComposition.swift:282` (`foreground`) / `:464` (`background`) | ao voltar, re-deriva a aparência e chama `foreground()` (sincroniza catálogo e restaura se necessário) |
| Reabrir / restaurar | `Sources/FeedMineRuntime/FeedSession.swift:340` (`installFromCheckpoint`), `FeedPresentationAdmission.swift:72` (`.restore`), `FeedRunwayDriver.swift:112` (`restoreAndActivate`), `AppComposition.swift:2709` | sem apresentação em memória, reinstala a janela do checkpoint durável (edição+cursor+âncora) |
| Salvar / bookmarks | `AppComposition.swift:1696` (`toggleBookmark`) / `:1629` (`.save`), `Sources/FeedMineUI/Bookmarks/BookmarkBoxesView.swift:42`, `FeedSavedListView.swift:31` | o toggle grava no box preferido; caixas e lista de salvos são superfícies próprias |
| Adicionar feed | `FeedMineApp.swift:1108-1111` (`addFeedSheet`→`ReaderAddFeedView`), `Tools/ReaderAddFeedViews.swift:208/141/251`, `AppComposition.swift:986-993` (pasteboard), `FeedMineApp.swift:450/1139` (`fileImporter`→OPML) | colar endereços → resolver → prévia → adicionar; OPML pelo picker. **O banner automático de clipboard não está ligado** (`Feedback/ClipboardBanner.swift:10` existe sem nenhum call site; ver §5) |
| Filtros | `FeedMineApp.swift:337` (folha), `Sources/FeedMineUI/Filters/FilterSheetView.swift:79/136`, `AppComposition.swift:591` (`applyFilter`) | a folha escolhe preset/tipo/tópicos/idioma/humor; sair aplica reconstruindo a sessão |
| Busca | `Sources/FeedMineUI/FeedScreenStore.swift:96` (`submitSearch`), `ReaderShell.swift:89-90`, `AppComposition.swift:144` | submeter um termo troca o contexto para `.search` |
| Fontes / países | `Sources/FeedMineUI/Sources/SourceManagementView.swift:47`, `CountriesListView.swift:58`, `NodeSourcesView.swift:130`, `AppComposition.swift:1100` | superfície Fontes com seções, toggles, entrada para Países e para as fontes de um nó |
| Aparência / modo noturno | `Sources/FeedMineUI/Appearance/ReaderAppearance.swift:14`, `AppComposition.swift:1017`, `FeedMineApp.swift:581-590`, `Settings/ReaderSettingsView.swift:206-210` | paleta derivada de hora + preferências; re-derivada ao voltar do background |
| Compartilhar / exportar | `FeedMineApp/FeedMineApp/PlatformSurfaces.swift:30/39`, `FeedMineApp.swift:454/1073`, `AppComposition.swift:961` | a ação de share abre `UIActivityViewController` com a URL; exportar abre a folha escopo×formato com prévia |
| Ajustes | `FeedMineApp.swift:367-405`, `Sources/FeedMineUI/Settings/ReaderSettingsView.swift:83` | tamanho de texto, seguir o relógio, pré-carregar imagens, modo noturno, filtros de conteúdo, armazenamento, sobre |
| Playback | `FeedMineApp/FeedMineApp/MediaPlaybackAdapter.swift:35`, `Sources/FeedMineUI/Media/MiniPlayerBar.swift:22/29/98`, `AppComposition.swift:1034` | tocar o card inicia/toggle o episódio; barra de altura fixa e player completo; posição salva no background (`:467`) |
| Pressão de armazenamento | `AppComposition.swift:2769` (`tidy.run` só com o app invisível), `Sources/FeedMineRuntime/MediaTidy.swift:14`, `FeedMineMedia/MediaRetention.swift:43`, `MediaHousekeeping.swift:18`, `ReaderSettingsView.swift:90` | em background inventaria a mídia, calcula orçamento pelo espaço livre e evicta; **não há superfície para o leitor quando o disco aperta** |

## 3. Tabela de lacunas por jornada: V2 × teste de jornada

**Como ler a coluna de teste.** A V2 tem **dois** targets de teste no Xcode, e a separação não é a do diretório
(as 13 fontes vivem no mesmo grupo `FeedMineApp/FeedMineAppTests/`):

- `FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj:102` → `name = FeedMineAppTests … productType = "com.apple.product-type.bundle.unit-test"` (7 fontes, fase `:95`)
- `FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj:110` → `name = FeedMineUITests … productType = "com.apple.product-type.bundle.ui-testing"` (6 fontes, fase `:103`)
- Os 10 targets do pacote SwiftPM (`Tests/**`, 159 arquivos `.swift`) **não lançam o app**: um grep por
  `XCUIApplication|launchArguments|XCUIDevice|screenshot|Process()` em `Tests/**` não devolve nenhum resultado.

Portanto "teste de jornada" aqui = teste do target `FeedMineUITests`. Uma fonte de cautela medida: **nenhum teste da
V2 compara pixels** (grep por `pngRepresentation|CGImage|imageRep|pixel|XCUIScreenshot|screenshot.image` em
`FeedMineApp/FeedMineAppTests` não devolve nada); todo `XCTAttachment(screenshot:)` é anexo de evidência, nunca
asserção. Todas as asserções de jornada são árvore de acessibilidade, texto e geometria de `frame`.

| # | Jornada | Exigida por | V2 faz? | Teste de jornada? | Só unit/componente? | Veredito |
|---|---|---|---|---|---|---|
| J01 | Abrir o app e chegar à casca | doutrina 1/3 `:3118,3120`; `00-README.md:47` | sim | **sim** — `FeedMineUITests.swift:56/201/615/1240/1271` (e os 41 testes do arquivo) | — | coberto |
| J02 | Onboarding (idiomas/lugares, sem tópicos obrigatórios) | `F02` + B01 `:43`; V1 `roadmap.md:35` | sim | **sim** — `FeedMineUITests.swift:585/615/674/1917/1964`; `DiscoveryBenchmarkTests.swift:419` (gated) | `CuratedFeedCoordinatorTests` | coberto |
| J03 | Primeiros cards / preparação honesta | doutrina 2/3 `:3119-3120`; INV-06 `:76` | sim | **sim** — `FeedMineUITests.swift:1201/1271/1392` | `PreparationProgressTests` | coberto (mas `:1271` é vermelho por decisão — ver §5) |
| J04 | **Imagens/mídia aparecendo no card** | doutrina 4 `:3121-3123`; `cards-resolvidos…:7-18`; `01-feed-pipeline.md:87-89`; NORTE `:81` | sim | **NÃO** — nenhum teste afirma imagem desenhada; o corpus dá imagens (`bench/serve.py:18` serve `/m/<uid>` PNG/MP3/MP4) e o gate B04 só **registra** geometria (`DiscoveryBenchmarkTests.swift:525-551`) | sim: `Tests/ArchitectureSmokeTests/FeedCardTransferTests.swift:59-76` (`isImageBearing`, slot congelado), `Tests/FeedMineRuntimeTests/ScrollAdmissionTests.swift:258-262`, `Tests/FeedMineRuntimeTests/MediaDeclaredDimensionTests.swift`, `Tests/FeedMineMediaTests/*` (bytes sintéticos) | **lacuna** |
| J05 | Baixar conteúdo / runway contínuo | doutrina 5/7 `:3124,3127`; B03 `:68` | sim | **parcial**: `FeedMineUITests.swift:1392` (publicação tardia enche a janela sem gesto), `:941` (swipe chega ao runway), `DiscoveryBenchmarkTests.swift:741` (**pulado** sem `FEEDMINE_BENCH_FULL_TRACE=1` `:743-744`) | `RunwayControllerTests`, `FeedSessionRunwayTests`, `MeasuredRunwayReserveTests` | coberto (o B03 de 30 min só por `bench/run.sh`) |
| J06 | Ler artigo (leitor local / no site) | `2026-07-01-in-app-reader-design.md:8,67-70`; UX-004 `:80-84` | sim | **sim** — `ReadingSurfaceUITests.swift:90/153/183/193/203/211/221/245/271`; `ArticleReadingDiagnosisUITests.swift:455/490`; `FeedMineUITests.swift:1053/1417` | `ReadingCompositionTests`, `ReaderHostTests` | coberto |
| J07 | Rolagem contínua, sem travas nem saltos | doutrina 4/5 `:3121-3125`; NORTE `:76`; INV-03 `:22` | sim | **parcial** — `FeedMineUITests.swift:749/941/1155` e `ArticleReadingDiagnosisUITests.swift:185/233/238` asseguram *estabilidade de posição/identidade*, **não fluidez medida** | `ScrollAdmissionTests`, `FeedSessionViewportTests` | **lacuna de fluidez** (nenhum teste de *hitch*) |
| J08 | Background→foreground | doutrina 6 `:3126`; INV-09 `:109`; B04 `:82-84` | sim | **sim** — `FeedMineUITests.swift:966/1007/1155` (`XCUIDevice.shared.press(.home)` + `app.activate()` em `:986-987`,`:1176-1177`,`:1223-1224`); `DiscoveryBenchmarkTests.swift:578-585` | `CompositionTests.swift:230/261/1240-1241` | coberto |
| J09 | Fechar e reabrir: feed imediato, sem tela de carregamento | doutrina 9 `:3131-3132` e a reafirmação `:3220-3224`; `PersonaExplorationUITests.swift:265-267,386-388`; INV-07 `:84` | sim | **sim, mas mais fraco que o critério da V1** — `FeedMineUITests.swift:895` (reabre no card que o leitor lia), `:791` (relançar offline mantém filtro/salvo/feed), `:1315` (cards publicados continuam alcançáveis) | `FeedSessionWarmRestoreTests`, `OfflineRestorePersistenceTests` | coberto em identidade; **a metade "sem tela de carregamento" não é afirmada por nenhum teste V2** (o V1 falhava o teste quando ela aparecia) |
| J10 | Offline de verdade | UX-009 `:146-150`; INV-11 `:124`; B05 `:90-96` | sim | **sim** — `ReadingSurfaceUITests.swift:90` (modo avião verificado em `:105-112`), `FeedMineUITests.swift:56/201/966`; `DiscoveryBenchmarkTests.swift:718-728` | `OfflineRestorePersistenceTests` | coberto |
| J11 | Salvar/bookmarks e caixas | UX-004; V1 `durable-user-actions-report.md:11` | sim | **sim** — `FeedMineUITests.swift:283/850/1053`; `ArticleReadingDiagnosisUITests.swift:544`; B05 salva (`DiscoveryBenchmarkTests.swift:664`) | `ReaderLibraryStoreTests`, `BookmarkBoxesBackendTests` | coberto |
| J12 | Adicionar feed (colar link / clipboard / OPML) | `roadmap.md:33`; `1.0-checklist.md:774-776` (append-only) | sim, **sem o banner automático** | **sim para link e OPML** — `FeedMineUITests.swift:1493` (colar, adicionar, ler, sobrevive a relançar), `:674` (OPML); `AddFeedTests.swift:40/104` (nível de módulo) | `AddFeedTests`, `FeedLinkResolverTests` (SPM) | **lacuna parcial**: o banner de clipboard existe sem call site e sem teste (§5) |
| J13 | Filtros / troca de contexto A→B→A | doutrina 8 `:3129-3130`; `code-review-filtros-shake-source.md:24`; INV-10 `:115` | sim | **sim** — `FeedMineUITests.swift:1711` (folha aplica), `:1113` (contexto visível/limpável), `:791` (filtro sobrevive a relançar); B05 A→B→A (`DiscoveryBenchmarkTests.swift:637`) | `ReaderFilterStoreTests`, `ContentFilterTests.swift:50/76/110/143` | coberto |
| J14 | Busca | UX-003 `:53-57`; `PersonaExplorationUITests.swift:152,158` | sim | **sim** — `FeedMineUITests.swift:1812` (digitar não move contadores, cancelar restaura), `:1417` | `ReaderShellTests` | coberto |
| J15 | Fontes / países / página da fonte | `code-review-filtros-shake-source.md:198,297,325` | sim (a "View Source" existe) | **sim para a árvore de fontes** — `FeedMineUITests.swift:56/124`; `ArticleReadingDiagnosisUITests.swift:53` | `SourceManagementStoreTests`, `SourceCatalogBackendTests` | coberto; a jornada "abrir a fonte de um card e ver o histórico dela" é exercida em `FeedMineUITests.swift:1417` |
| J16 | Aparência / modo noturno / Dynamic Type / idioma | `roadmap.md:34`; doutrina 4 `:3121` ("everything pretty") | sim | **parcial** — `FeedMineUITests.swift:1007` (aparência escura não troca associação nem âncora), `:429/471` (valor do switch), `:749` (Accessibility XL), `:1964` (idioma do device), `:1785` (iPad) | `ReaderSettingsTests`, `CompositionTests.swift:1905-1906` (resolve tokens, "instead of by a screenshot") | **lacuna visual**: nenhuma asserção de pixel/cor |
| J17 | Compartilhar / exportar / importar | V1 matriz `UI_TRANSFER_MATRIX.md:277-278` (superfícies Export/Add feed); `roadmap.md:33` (canais de importação); F26 UX26-B `:26`; `1.0-application-closure-plan.md:30` | sim | **parcial** — `FeedMineUITests.swift:539` (prévia de import/export), `:366` (copiar link + toast); o botão de **share** existe e é conferido só por `exists` (`FeedMineUITests.swift:567`), nunca tocado | `ReaderImportExportCoordinatorTests`, `OPMLDocumentTests` | **lacuna**: o share sheet real não é exercido ponta a ponta |
| J18 | Ajustes | V1 matriz `UI_TRANSFER_MATRIX.md:274` (a folha `SettingsSheetView` com as suas seções); `roadmap.md:34` | sim | **sim** — `FeedMineUITests.swift:429/471` | `ReaderSettingsCoordinatorTests`, `ReaderSettingsTests` (SPM) | coberto |
| J19 | Playback (mini player, full player, lock screen, fone) | UX-007 `:111-115`; F26 UX26-E `:27` ("reproduzir podcast, trocar de aplicativo, bloquear tela, receber ligação, mudar rota Bluetooth e retornar à mesma posição") | sim | **parcial** — `FeedMineUITests.swift:393` (barra de 56 pt sem mover o feed), `:1619` (retoma onde parou), `:1849` (barra viva no leitor); **lock screen/fone declaradamente fora do simulador** (comentário citado pelo inventário em `FeedMineUITests.swift:1613-1617`) | `PlaybackTests.swift:203-212` (MPRemoteCommandCenter), `ReaderMediaCoordinatorTests` | **lacuna em aparelho**: comandos de lock screen/fone só por unit |
| J20 | **Pressão de armazenamento / recuperação** | INV-16 `:182`; F27 UX27-D `:24` | parcial (housekeeping em background; sem superfície de recuperação) | **NÃO** — nenhum teste; a única menção é um comentário sobre ENOSPC em `DiscoveryBenchmarkTests.swift:250-251` | `Tests/FeedMineMediaTests/MediaHousekeepingTests.swift`, `Tests/FeedMineRuntimeTests/MediaTidyFactsTests.swift` | **lacuna** |
| J21 | **Escala e fluidez no aparelho físico** | B06 `:98-101`; `PhysicalDeviceTesting.md:4-5`; F27 `:15-18` | instrumentação existe (`FeedFrameMeter.swift:57` escreve `frames/late/bad/severe/worst_ms` por segundo no traço) | **NÃO** — nenhum teste lê o *hitch ratio*; `scripts/soak.py:363` declara `"hitches": "Not measured"`; `bench/run.sh:87` aceita só `B01|B02|B03` na ajuda e o B06 segue **NOT_RUN** (`docs/evidence/ACCEPTANCE_RECORD.md:21`) | `RunwayPolicyTests`, `MeasuredRunwayReserveTests` (política, não quadros) | **lacuna** |
| J22 | Catálogo público: reabrir com revisão nova sem tocar no que é do leitor | PD-10 e INV-18 `:192-195`; `ACCEPTANCE_RECORD.md` critérios (1)–(7) | sim | **sim** — `CompositionTests.swift:343/383/432/459/480/526/561` (autoridade, janela de 23/25 h, 304, ativação) e `CatalogueUpdateAcceptTests.swift:213` (revisão 6 sobre socket real, leitor intacto) | — | coberto **no nível de composição** (não abre a UI) |

## 4. As jornadas SEM teste de jornada — lista ordenada

Ordenada por (a) quanto a jornada é promessa explícita do produto, e (b) o quanto custa cobri-la.

### 1. Imagens/mídia aparecendo no card — nenhuma asserção de que uma imagem foi desenhada

- **Exigência:** doutrina item 4 ("card assembled, **image showing** … No broken image") `1.0-checklist.md:3121-3123`;
  `cards-resolvidos-antes-de-aparecer.md:7-18`; `docs/v1-study/01-feed-pipeline.md:87-89`; NORTE `:81`.
- **V2 hoje:** o card desenha `card.image?.cgImage` sobre um slot de geometria congelada
  (`FeedItemCardView.swift:226/245-247`); o pipeline vive fora da view (`MediaResolver.swift:26`,
  `MediaPrefetcher.swift:148`).
- **Cobertura existente:** só componente — `FeedCardTransferTests.swift:59-76` (slot congelado, `isImageBearing`),
  `ScrollAdmissionTests.swift:258-262` (residência de bitmaps), `Tests/FeedMineMediaTests/*` (bytes sintéticos), e o
  gate B04 que **registra** geometria sem asserção (`DiscoveryBenchmarkTests.swift:525-551`).
- **Como construir o teste:** usar o corpus congelado, que **já serve imagens** (`bench/serve.py:18`: `GET /m/<uid>`
  com PNG/MP3/MP4), ou criar um host de fixture de imagem; rolar até um card com slot de imagem e **medir pixels**
  dentro do retângulo do slot (a suíte atual nunca compara pixels) afirmando (i) que a fração de tinta é de imagem e
  não do placeholder, e (ii) que a altura do card não muda depois — é a metade "no broken image / no content moving"
  que hoje não tem prova. A V1 tinha o equivalente: `PersonaExplorationUITests.swift:78-101` media pixels para
  dizer se o corpo do artigo renderizou ("screenshot → 60×60 grid → ink fraction ≥ 0.06", `HANDOFF.md:135-136`).
- **Nota de fixture:** as fontes de desenvolvimento da V2 são `mediaKind: "text"` (`FeedMineApp/TrustedFeeds.swift:99`)
  e não há hook de imagem de fixture (só `FEEDMINE_FIXTURE_ITEMS` em `:295` e `FEEDMINE_MEDIA_SIMULATION` para áudio,
  `FeedMineApp.swift:567`). Ou seja: hoje uma jornada de imagem **não é construível** sem tocar em `TrustedFeeds`
  ou apontar para o corpus do bench.

### 2. Fluidez da rolagem medida (hitch ratio) — a instrumentação existe, o teste não

- **Exigência:** doutrina 4 ("no scroll jank") `:3121-3123` e 5 ("without jerks") `:3124-3125`; B06 `:98-101`;
  F27 UX27-C `F27_…:23`.
- **V2 hoje:** `FeedFrameMeter` mede quadro a quadro e escreve uma linha por segundo no traço do app
  (`FeedFrameMeter.swift:23-30`, flush em `:57`), e `AppComposition.swift:2317` liga o medidor.
- **Cobertura existente:** nenhuma asserção. `scripts/soak.py:363` grava `"hitches": "Not measured; record separately
  with Instruments Animation Hitches"`; `scripts/b06-evidence.sh:302-304` exige o template Animation Hitches; o
  veredicto do B06 continua **NOT_RUN** (`ACCEPTANCE_RECORD.md:21`).
- **Como construir o teste:** (i) de forma barata e determinística no simulador, um teste de jornada que rola N
  segundos e lê os contadores que o próprio app já publica no traço (o mesmo padrão de `feed-window-proof` usado em
  `ArticleReadingDiagnosisUITests.swift:202`), afirmando um teto declarado de `(late+bad+severe)/frames`; (ii) no
  aparelho, o protocolo do B06 com Instruments (RSS, CPU, memória, energia/térmica, hitches, tempo de scroll), que é
  o que `scripts/b06-evidence.sh` já sabe orquestrar.

### 3. Pressão de armazenamento e recuperação — nenhum teste e nenhuma superfície

- **Exigência:** INV-16 `:182` (todo subsistema adapta a disco/memória a fatos observáveis); F27 UX27-D `:24`
  ("disco quase cheio + remoção de cache e reinício offline: preservar livros, sessões e conteúdo protegido").
- **V2 hoje:** a limpeza roda só com o app invisível (`AppComposition.swift:2769`) e evicta por orçamento
  (`MediaTidy.swift:14`, `MediaRetention.swift:43`); **não há superfície de estado/recuperação** para o leitor.
- **Cobertura existente:** unit de housekeeping (`Tests/FeedMineMediaTests/MediaHousekeepingTests.swift`,
  `Tests/FeedMineRuntimeTests/MediaTidyFactsTests.swift`); nenhum teste de jornada e nenhum teste que simule ENOSPC
  ou volume cheio.
- **Como construir o teste:** preencher o container (`bench/run.sh:130-134` já recusa abaixo de 3 GB e registra o
  caso real de ENOSPC em `bench/run.sh:125-129`), abrir o app, e afirmar que o feed visível, os salvos e o
  checkpoint sobrevivem; mais um caso de disco cheio com app em background, medindo o conjunto que a retenção
  protege (`MediaRetention.evictions(... protectedKeys:)`, `MediaTidy.swift:55-57`).

### 4. Compartilhar de fato (share sheet acionado) — o controle existe, o fluxo não é exercido

- **Exigência:** `AppStoreSubmission.md:51-54` (partilhar o que se leu) e `1.0-application-closure-plan.md:30`
  ("do not ship dead buttons", o inverso: um botão que existe tem de funcionar).
- **V2 hoje:** `PlatformSurfaces.swift:30/39` (`SharedLink` → `UIActivityViewController`), apresentado em
  `FeedMineApp.swift:454`.
- **Cobertura existente:** `FeedMineUITests.swift:539` toca `export-share`… **não**: o teste abre a prévia de export
  (`export-preview`) e o inventário registra que `export-share` "só existe, nunca é tocado" nestes testes (a matriz
  da V1 registra o mesmo estado, `docs/v1-study/UI_TRANSFER_MATRIX.md:278`); `testCardCopiesItsOwnLinkAndStatesIt`
  (`FeedMineUITests.swift:366`) cobre **copiar link**, não o share sheet.
- **Como construir o teste:** após abrir a folha de export, tocar `export-share` e afirmar que a superfície de
  compartilhamento apareceu e voltou (o `UIActivityViewController` do sistema é observável por `app.otherElements`
  ou pela mudança de estado de primeiro plano), ou mover o share para um adapter de plataforma e asseverar a
  apresentação como `ReaderHostTests.swift:91-108` já faz para o leitor.

### 5. Aparência / modo noturno como resultado visual

- **Exigência:** `roadmap.md:34` (modo escuro) e doutrina 4 ("everything pretty") `:3121`.
- **V2 hoje:** `ReaderAppearance.swift:14` (período) + `AppComposition.swift:1017` (paleta corrente) e re-derivação
  ao voltar (`FeedMineApp.swift:581-590`).
- **Cobertura existente:** só o **valor** do switch (`FeedMineUITests.swift:451,458`) e a estabilidade de associação
  (`:1007`, `:1041` anexa `u1-dark-appearance` como evidência, não asserção). O próprio `CompositionTests.swift:1905-1906`
  declara a escolha: "appearance adaptation is proven by resolving the tokens under both trait collections instead of
  by a screenshot".
- **Como construir o teste:** captura em duas aparências e compara a luminância média da região de fundo do feed
  (asserção de pixel, que hoje não existe em nenhum lugar da suíte), com a mesma técnica de grade/ink que a V1 usava.

### 6. Playback em lock screen / fones no aparelho

- **Exigência:** UX-007 `:111-115`; `PhysicalDeviceTesting.md:4-5`; F27 `:15-18`.
- **Cobertura existente:** `PlaybackTests.swift:203-212` (`MPRemoteCommandCenter`, com duplo) — componente; o
  comentário do teste de UI declara que esses comandos exigem aparelho (citado pelo inventário em
  `FeedMineUITests.swift:1613-1617`).
- **Como construir o teste:** roteiro de aparelho (o `PhysicalDeviceTesting.md` da V1 dá o procedimento com
  `devicectl`), com play/pause/±15 s pelo centro de controle e o estado do `MPNowPlayingInfoCenter` observado.

### 7. Banner de clipboard (jornada exigida, hoje invisível)

- **Exigência:** `roadmap.md:33` ("paste URL, share sheet"; o "clipboard" aparece como canal entregue em
  `roadmap.md:117`: "✅ completo (parser, resolver, UI, clipboard, collections, URL scheme)") e `1.0-checklist.md:774-776`.
- **V2 hoje:** `Sources/FeedMineUI/Feedback/ClipboardBanner.swift:10` define a superfície, e o cabeçalho diz
  "the host detects the link (T10 owns import) and states it here", **mas não há nenhum call site** — a parte viva é o
  paste manual dentro da folha de adicionar feed (`Tools/ReaderAddFeedViews.swift:141/251`). A matriz da V1 registra o
  mesmo: "Clipboard banner … no executed test covers `checkClipboard`/Add/Dismiss" (`UI_TRANSFER_MATRIX.md:276`).
- **Como construir o teste:** com um pasteboard preparado pelo host, abrir o app e afirmar que o banner aparece com
  o link, que "Adicionar" resolve e leva à prévia, e que "Dispensar" o remove — hoje seria um teste vermelho até a
  ligação existir.

### 8. Primeira execução no catálogo embarcado com expansão sem gesto — teste existe, é vermelho por decisão

- **Exigência:** doutrina 2/3/7 `:3119-3120,3127-3128`; INV-04/INV-05.
- **Estado:** `FeedMineUITests.swift:1271` (`testFirstRunOverTheRealCatalogueExpandsWithoutAGesture`) documenta o
  defeito R5 e **deixa a expectativa falhar** (citado pelo inventário em `:1296-1308`). Um teste vermelho declarado
  não é cobertura verde.

### 9. Soak/escala persistente — teste existe, pulado por padrão

- `FeedMineUITests.swift:10` (`testPreparePersistentScaleSoakThroughCountryCascade`) com `throw XCTSkip` em `:12-13`
  sem `FEEDMINE_PREPARE_SCALE_SOAK=1`; `scripts/soak.py:25-26` acrescenta que hitches "require a separate Instruments
  Animation Hitches recording of this process".

### 10. Os gates B01–B05 como jornada — existem, mas fora de `swift test`/Xcode

- `DiscoveryBenchmarkTests.swift:33-34` pula tudo sem `FEEDMINE_BENCHMARK`; o B03 exige
  `FEEDMINE_BENCH_FULL_TRACE=1` (`:743-744`). Uma invocação normal da suíte não corre nenhum deles; quem os corre é
  `bench/run.sh` (`:386-395`). O B06 é **NOT_RUN** (`ACCEPTANCE_RECORD.md:21`) e o aparelho físico existe mas não foi
  usado.

## 5. Contradições, drift e limitações honestas

1. **Duas fontes discordam sobre a jornada de leitura.** `docs/v1-study/UI_TRANSFER_MATRIX.md:258` diz
   "**no executed uitest opens an article** (T9's evidence names the card-copy and mini-player tests)" para a linha
   "Article reader"; hoje existem nove testes de jornada que abrem o artigo (`ReadingSurfaceUITests.swift:90-271`) e
   dois de diagnóstico (`ArticleReadingDiagnosisUITests.swift:455,490`). A matriz é um documento **histórico** com
   status datados de 2026-10-10 (`UI_TRANSFER_MATRIX.md:2-3` registra a correção de escopo); para fins de lacuna, a
   evidência são os arquivos de teste, não a matriz.
2. **A V1 e a V2 discordam sobre o que cabe no simulador.** A V1 certificava a jornada inteira em simulador
   (`HANDOFF.md:66`) **e** exigia aparelho físico para performance (`docs/quality/FeedMine-Test-Architecture.md:170`
   "requires physical device"); a V2 tem a mesma divisão (`F27:17`) e, na prática, **não executou** a metade física
   (B06 NOT_RUN) nem leva comandos de lock screen a teste de jornada.
3. **Uma cláusula do oráculo do benchmark mede nada — por decisão, não por esquecimento.** `ACCEPTANCE_RECORD.md:84-88`:
   em `043906Z`, "a prontidão de cada candidato foi registrada" saiu **PASS** com `candidatos: 871, pendentes: 0,
   texto: 0, preparados: 0`; a condição de não-vacuidade falta e a correção foi adiada porque o avaliador está
   congelado em `bench/EVALUATOR.sha256`. Consequência para este relatório: **um PASS do B03 não é prova de que a
   preparação de cada candidato foi observada**.
4. **O PASS do B03 não prova as cláusulas de mídia pendente.** `ACCEPTANCE_RECORD.md:49-53` ("O censo do traço de
   `065200Z` … mostra `prepared × 874`, **zero suspensões** e **zero transições de mídia** — ou seja, naquele
   ambiente a regra de suspensão do F06 nunca foi exercitada, e o PASS do B03 não prova F06-A nem F06-B").
5. **A expansão progressiva do catálogo está medida e é zero.** `ACCEPTANCE_RECORD.md:78-83`: no log do B03 que
   passou, as 120 fontes contatadas têm o primeiro contato entre 0 e 1,2 min — "**zero** fontes novas depois dos
   5 min". Ou seja: a jornada de 30 minutos prova runway, não descoberta progressiva (que é PD-8).
6. **Nenhum teste compara pixels.** Ver §3. Isso não invalida as jornadas cobertas (elas afirmam texto, identidade e
   geometria, que é o que o produto promete sobre *estabilidade*), mas significa que "imagem apareceu" e "a
   aparência mudou" são **inobserváveis** pela bateria atual.
7. **Bug de nomenclatura que engana quem lê o repositório:** o target de UI test **é** `FeedMineUITests`
   (`project.pbxproj:110`), mas 13 arquivos-fonte vivem na pasta `FeedMineAppTests/`, incluindo os 7 do target de
   unit test. Quem olhar só o diretório conclui que não há testes de jornada — há 64
   (41 em `FeedMineUITests.swift` + 9 em `ReadingSurfaceUITests.swift` + 7 em `ArticleReadingDiagnosisUITests.swift`
   + 5 em `DiscoveryBenchmarkTests.swift` + 1 em `EndOfContentUITests.swift` + 1 em `EditorialOfferBudgetUITests.swift`).
8. **O banner de clipboard** (item 7 da §4) é o único caso encontrado de superfície declarada "entregue" num
   documento (`roadmap.md:117`) que na V2 existe sem nenhum call site; `1.0-application-closure-plan.md:30` proíbe
   exatamente esse estado ("do not ship dead buttons").

## 6. Resposta curta ao dono do produto

- A bateria da V2 **cobre como jornada** 15 das 22 jornadas levantadas: abrir, onboarding, primeira tela, reabrir,
  offline, ler artigo, ler salvo, salvar/caixas, adicionar feed por link e OPML, filtros e A→B→A, busca, fontes/países,
  ajustes, compartilhar link, exportar/importar prévia, background→foreground e a atualização do catálogo público.
- O que **não** tem nenhum teste de jornada, em ordem de importância: **imagem aparecendo no card** (1),
  **fluidez medida por quadros** (2), **pressão de armazenamento e recuperação** (3), **share sheet de fato** (4),
  **aparência como resultado visual** (5), **lock screen/fones no aparelho** (6), **banner de clipboard** (7).
- E o que existe mas **não conta como cobertura**: a primeira execução no catálogo embarcado (teste vermelho por
  decisão, item 8), o soak de escala (pulado por padrão, 9) e os gates B01–B05 (só por `bench/run.sh`; B06 NOT_RUN, 10).
- Onde a bateria é grande e mesmo assim a lacuna é real: mídia tem **testes de componente** (bytes → placeholder →
  slot congelado) e zero testemunho de tela; rolagem tem **asserções de estabilidade** e nenhum número de quadros.
  É a diferença entre "o método foi chamado" e "o leitor viu", a mesma que o contrato do benchmark proíbe
  (`DISCOVERY_ACCEPTANCE_BENCHMARK.md:12-16`: "não marcar 'o método foi chamado' como prova de 'o leitor recebeu
  conteúdo'").
