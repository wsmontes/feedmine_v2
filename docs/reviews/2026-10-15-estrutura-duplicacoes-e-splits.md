# Estrutura, duplicações e splits — estudo do repositorio feedmine_v2

- **Data:** 2026-10-15
- **Autor:** agente `SimplifyAudit2` (tarefa delegada pelo ORCH)
- **Alcance:** `Sources/` (10 módulos SwiftPM) + `FeedMineApp/FeedMineApp/` (alvo de app). Testes não entram nas contagens de tamanho.
- **Nota de validade:** todos os números de linha valem **para esta data e para a revisão em que foram medidos**. Merge, rebase ou edição movem linhas; antes de executar qualquer split, reconte as faixas.
- **Método:** sem shell disponível, a contagem saiu do próprio leitor de arquivo (`read <arquivo>:99999-`, que responde `Line 99999 is beyond end of file (N lines total)`); a estrutura interna e as duplicações, por `grep` com regex ancorada em indentação. Nada foi editado, buildado ou executado.

---

# Estado após a decisão de arquitetura (leia antes de executar qualquer coisa)

Este documento nasceu como estudo. Depois dele, o arquiteto decidiu, e as duas decisões mudam o que pode ser executado:

1. **Os splits grandes foram RECUSADOS agora.** Texto do arquiteto: *"não autorizar agora a divisão extensiva de AppComposition.swift ou PublicationStore.swift por tamanho. O benefício precisa justificar o risco de interferir nas jornadas que acabaram de ser recuperadas."* Portanto o **§3 deste documento é PLANO DE MANUTENÇÃO, não ordem de execução**. Nada de `AppComposition.swift`, `FeedMineApp.swift`, `PublicationStore.swift`, `ContentStore.swift` ou `FeedScreen.swift` deve ser dividido por causa deste relatório. As faixas e contagens ficam registradas para quando — e se — a divisão for autorizada, para que ninguém precise remedir.

2. **A deduplicação autorizada é apenas a local.** Autorizadas: **F6, F7, F8, F9, F11** e o embrulho `#if DEBUG` das três escritas de contador (§4.2). **F2, F3, F4 e F5 ficam de fora** por regra explícita do arquiteto (*"não criar helper compartilhado entre módulos só porque duas funções se parecem"*). A discordância técnica está registrada na seção **Divergência**, no fim, sem alterar o veredito.

---

# 1. Tamanhos

## 1.1 Os 20 maiores (`Sources/` + `FeedMineApp/`, sem testes)

| # | arquivo | linhas | alvo |
|---|---|---|---|
| 1 | `FeedMineApp/FeedMineApp/AppComposition.swift` | **2915** | app (xcodeproj) |
| 2 | `FeedMineApp/FeedMineApp/FeedMineApp.swift` | **1320** | app (xcodeproj) |
| 3 | `Sources/FeedMinePersistence/PublicationStore.swift` | **1166** | FeedMinePersistence |
| 4 | `Sources/FeedMinePersistence/ContentStore.swift` | **821** | FeedMinePersistence |
| 5 | `Sources/FeedMineUI/FeedScreen.swift` | **807** | FeedMineUI |
| 6 | `Sources/FeedMinePersistence/ReaderLibraryStore.swift` | **694** | FeedMinePersistence |
| 7 | `Sources/FeedMinePersistence/RuntimeMigrations.swift` | **607** | FeedMinePersistence |
| 8 | `Sources/FeedMineRuntime/FeedSession.swift` | **585** | FeedMineRuntime |
| 9 | `Sources/FeedMineRuntime/RunwayController.swift` | **580** | FeedMineRuntime |
| 10 | `Sources/FeedMinePersistence/LegacyCatalogReader.swift` | **576** | FeedMinePersistence |
| 11 | `Sources/FeedMineComposition/CatalogInstallation.swift` | **561** | FeedMineComposition |
| 12 | `Sources/FeedMinePersistence/CatalogCompiler.swift` | **559** | FeedMinePersistence |
| 13 | `Sources/FeedMineDomain/Content.swift` | **558** | FeedMineDomain |
| 14 | `Sources/FeedMinePersistence/CatalogOPMLScan.swift` | **546** | FeedMinePersistence |
| 15 | `FeedMineApp/FeedMineApp/MediaPlaybackAdapter.swift` | **511** | app |
| 16 | `Sources/FeedMineUI/Cards/FeedItemCardView.swift` | **490** | FeedMineUI |
| 17 | `Sources/FeedMineUI/Tools/ReaderAddFeedViews.swift` | **435** | FeedMineUI |
| 18 | `FeedMineApp/FeedMineApp/TrustedFeeds.swift` | **426** | app |
| 19 | `Sources/FeedMinePersistence/AcquisitionAdmissionStore.swift` | **410** | FeedMinePersistence |
| 20 | `Sources/FeedMineSyndication/FeedLinkResolver.swift` | **403** | FeedMineSyndication |

Fronteira dos seguintes (para não haver dúvida sobre o corte): `UI/Onboarding/ReaderOnboardingView.swift` 400 · `Composition/ReaderImportExportCoordinator.swift` 385 · `Composition/FeedRunwayDriver.swift` 373 · `UI/Filters/FilterSheetView.swift` 366 · `UI/Sources/SourceManagementStore.swift` 345 · `UI/Onboarding/ReaderDiscoveryControls.swift` 275 · `Runtime/CatalogValues.swift` 270 · `UI/Settings/ReaderContentFilterView.swift` 269.

Sete dos vinte são **FeedMinePersistence**: 1166 + 821 + 694 + 607 + 576 + 559 + 546 + 410 = 5379 linhas em oito arquivos. É o módulo mais concentrado do repositório.

## 1.2 Estrutura interna dos 5 maiores

**1. `AppComposition.swift` — 2915 linhas, 6 tipos, 0 `extension`, 0 `// MARK:`**

- `AppComposition` (classe, `:21`–`:1555`) = **1535 linhas**, ~78 métodos. Blocos: props `:21–103`; `connecting(_:)` `:105–128`; `filterLanguages`/`preferredBookmarkListID`/`submitSearch` `:129–147`; `init` `:148–287` (**140 linhas**); `backgroundRefreshOpportunity` `:294–412` (**119**); autoridade/ledger do catálogo `:305–462`; `background` `:463–470`; `searchSources` `:472–515`; transições de contexto/filtro `:517–683`; *todos* os `make*Store` e handles de biblioteca `:687–1029` (**343**); intents de mídia `:1034–1045`; hook DEBUG de playback `:1046–1075`; discovery (pool, cache `:1493–1515`, traversal, profile) `:1157–1355`; editorial/trace `:1356–1489`.
- `FeedAssociation` (classe, `:1556`–`:2826`) = **1271 linhas**, ~85 métodos. Dentro dele, **`init` de `:1920` a `:2221` = 302 linhas** — a maior função do repositório: registra targets, monta `URLSession`, `SyndicationAcquisitionSnapshot`, `AcquisitionBackoffPolicy`, `MediaPrefetcher`, `RunwayController`, `ColdFeedBootstrap` e `CandidateProvider` num único corpo `:1934–2220`.
- Tipos de apoio no fim: `DeviceMediaConditions` `:2828–2871`, `NetworkPathObserver` `:2873–2897`, `EvidenceRelay` `:2899–2905`, `LiveValue` `:2907–2915`.

**2. `FeedMineApp.swift` — 1320 linhas, 1 tipo raiz + 8 tipos aninhados, 0 `extension`**

`@main struct FeedMineApp: App` `:13–1320` contendo: `registerBackgroundRefresh` `:34–58`; `requestBackgroundRefresh` `:60–70`; enums `SheetSurface` `:73–96`, `ReaderPage` `:99–102`, `AppSurface` `:111–114`, `LibraryPrompt` `:208–227`, `LibraryRoute` `:229–232`, `SourceRoute` `:235–238`; `var body` `:240–621` (**382 linhas**); `ReaderHost: UIViewControllerRepresentable` `:623–1035` (**413 linhas**, com `WindowReaderPresentation` `:668–710` e `Coordinator` `:712–1035`); import/export e helpers `:1036–1320`.

**3. `PublicationStore.swift` — 1166 linhas, 4 tipos, 0 `extension`**

`PublicationStoreError` `:11–24`; `PublicationStore` `:26–1094` (**1069 linhas, ~67 funcs**); `PublicationRecordFields` `:1096–1138` (decoder de linha); `PublicationValueCoding` `:1140–1166` (tradutor de erro). Faixas internas: ciclo de vida de edição/segmento `:151–330`; hidden tail `:331–428`; leituras do leitor/bookmarks/media usage `:430–508`; janelas (`tail`, `cards(around:)`, `readyAhead`, `exposure`, `forwardAdvance`) `:500–807`; codecs/história `:809–1066`.

**4. `ContentStore.swift` — 821 linhas, 3 tipos, 0 `extension`**

`ContentStoreError` `:8–19`; `ContentStore` `:21–771` (**751 linhas, ~53 funcs**); `ContentFields` `:773–822`. Faixas: candidate window `:79–250`; leituras admission-scoped `:252–313`; mutação canônica (`apply`, `applyMemberships`, `applyAvailability`) `:321–441`; leituras públicas `:443–507`; validação + codecs `:509–771`.

**5. `FeedScreen.swift` — 807 linhas, 14 tipos, 0 `extension`**

`FeedScreen` (View) `:10–209`; `FeedFlowCounters` `:211–218`; `EditorialSlot` `:221–229`; `FeedWorkFeedback` `:234–241`; `FeedWorkBadge` `:244–258`; `BadgeStyle` `:260–268`; `FeedVisualGeometry` `:271–283`; `FeedVisualEvent` `:285–288`; `FeedVisualCardGeometry` `:291–297`; `FeedVisualMotion` `:308–349`; `FeedVisualCapture` `:352–619` (**268 linhas**); `NativeFeedViewport` `:621–801`; `NativeFeedTargets` `:803–807`.

---

# 2. Duplicações (11 famílias, com veredito)

### F1 — `ISO8601DateFormatter` (6 cópias, 3 regras)

| site | regra |
|---|---|
| `Sources/FeedMineComposition/CatalogInstallation.swift:518-522` | `.withInternetDateTime`, formatter alocado por chamada |
| `Sources/FeedMineComposition/ReaderImportExportCoordinator.swift:229-231` | idem, mas com `:`→`-` (nome de arquivo) |
| `Sources/FeedMineComposition/ReaderImportExportCoordinator.swift:237-240` | idem (CSV); formatter reusado no loop |
| `Sources/FeedMineComposition/ReaderImportExportCoordinator.swift:328-329` | idem (JSON de export) |
| `Sources/FeedMineDomain/OPMLDocument.swift:111-112` | idem (`dateCreated` do OPML) |
| `FeedMineApp/FeedMineApp/AppComposition.swift:345-346` | idem (ledger do catálogo) |

**Veredito: unificar.** Dono: `Sources/FeedMineDomain/Timestamps.swift` (arquivo novo) com um `ISO8601DateFormatter` estático e duas funções (`internet(_:)`, `fileNameSafe(_:)`). `FeedMineDomain` já é dependência dos dez alvos (`Package.swift`), logo **nenhuma mudança no `Package.swift`**. Ganho colateral: cinco alocações de formatter por evento de catálogo/export deixam de existir.

### F2 — SHA-256 → hex (7 cópias) — **FORA DE ESCOPO NESTA RODADA**

`CatalogManifest.swift:232` (streaming, mantém o loop `:226–231`) · `AssetStore.swift:108-110` · `ReaderLibraryStore.swift:66-68` · `SyndicationHTTP.swift:260-262` (`"sha256:" +`) · `SyndicationTranslator.swift:260-262` (trunca em 8 bytes) · `CatalogOPMLScan.swift:149-152` (trunca em 4 bytes) · `LegacyCatalogImport.swift:34-38` (digest → UUID). Todos escrevem o mesmo `.map { String(format: "%02x", $0) }.joined()`.

**Veredito técnico: unificar a formatação, não o hash** (dono `Sources/FeedMineDomain/ContentDigest.swift`, `static func hex<S: Sequence>(_ bytes: S) -> String`; os sítios com prefixo/truncamento compõem sobre `hex`). **Veredito vigente: não executar** — ver Divergência.

### F3 — JSON canônico (`sortedKeys`) — **FORA DE ESCOPO NESTA RODADA**

`FeedMineDomain/Content.swift:382-386` · `FeedMineDomain/FeedContext.swift:125-129` (ambos `canonicalJSON`, byte-idênticos) · `FeedMineSyndication/SyndicationHTTP.swift:49-53`; e, com `prettyPrinted + sortedKeys`, `FeedMineComposition/CatalogManifest.swift:81` e `FeedMinePersistence/CatalogCompiler.swift:91-94`.

**Veredito técnico: unificar apenas os três primeiros** em `Sources/FeedMineDomain/JSONCoding.swift` (`static func canonical<T: Encodable>(_ value: T) -> Data?`). **`CatalogManifest`/`CatalogCompiler` devem ficar intactos em qualquer cenário**: o texto gerado por eles é hasheado e declarado (`bytes`/`sha256` por entrada — `CatalogManifest.swift:29-40, 97-105`), portanto mudar `outputFormatting` mudaria os digests gravados e a proveniência do catálogo. Duplicação aqui é mais barata que uma revisão de oráculo. **Veredito vigente: não executar** — ver Divergência.

### F4 — Decoders de linha duplicados (94 linhas de API paralela) — **FORA DE ESCOPO NESTA RODADA**

`PublicationStore.swift:1096-1138` (`PublicationRecordFields`, 43 linhas) × `ContentStore.swift:773-822` (`ContentFields`, 50 linhas): mesma superfície — `init(_ row: Row)`, `optionalString`, `string`, `integer`/`optionalInt`, `optionalDate`, `uuid`, `optionalUUID` — diferindo apenas no **tipo de erro** lançado (`PublicationStoreError.corruption` × `ContentStoreError.corruption`).

**Veredito técnico: unificar num único dono** — `Sources/FeedMinePersistence/PersistenceRowFields.swift` (novo, ~60 linhas), parametrizado por uma closure de erro de corrupção; os dois tipos privados somem. Mesmo alvo (`FeedMinePersistence`), sem `Package.swift`. **Veredito vigente: não executar** — ver Divergência.

### F5 — Wrappers de tradução de erro — **FORA DE ESCOPO NESTA RODADA**

`ContentStore.swift:510-519` (`Self.coding { }`, 35+ usos) × `PublicationStore.swift:1141-1165` (`PublicationValueCoding.translate` + 5 wrappers tipados, 8 usos). Mesmo mapeamento `PersistenceValueCodingError → erro do store`, escrito duas vezes.

**Veredito técnico: unificar** num único `PersistenceValueCoding.translating(_:to:)` em `Sources/FeedMinePersistence/PersistenceValueCoding.swift` (arquivo existente), deixando `ContentStore.coding` e `PublicationValueCoding` como adaptadores de 3 linhas. O ganho real não é LOC: é tornar impossível os dois stores divergirem no mapeamento. **Veredito vigente: não executar** — ver Divergência.

### F6 — Instalação atômica de arquivo (intra-arquivo) — **AUTORIZADA**

`CatalogInstallation.swift:533-543` (`replace(file:with:)`) × `:545-560` (`write(data:to:)`): os dois criam diretório, escrevem num temporário (`<nome>.incoming` × `url.temp`) e terminam em `replaceItemAt` ou `moveItem` com o mesmo if/else.

**Veredito: fundir numa só** `install(source: URL?, data: Data?, at: URL)` — 28 → ~18 linhas, removendo o risco de os dois caminhos divergirem na ordem de validação (é exatamente aí que o comentário `:548` documenta uma rejeição determinística de diretório no lugar do ponteiro).

### F7 — Instalação de `URLProtocol` de fixture — **AUTORIZADA**

`TrustedFeeds.swift:153-157` e `:259-263` são **byte-idênticos** exceto pela classe (`AddFeedFixtureProtocol` × `LocalFeedProtocol`). `DevelopmentNetworkBlock.apply` `:420-425` é outro mecanismo (proxy) e não é cópia.

**Veredito: unificar** os dois primeiros num `static func install(_ protocolClass: URLProtocol.Type, in URLSessionConfiguration)` no mesmo arquivo. Alvo app: não cria arquivo novo, logo não mexe no `pbxproj`.

### F8 — Validação da chave de mídia — **AUTORIZADA**

`AssetStore.swift:100-106` (`parse`: prefixo `"sha256:"` + 64 chars `0-9a-f`) × `MediaHousekeeping.swift:30-32` (`name.count == 64` + alfabeto hex). Mesma regra sobre representações diferentes (chave × nome de arquivo).

**Veredito: unificar** em `PublishedMediaKey` (`Sources/FeedMineMedia/PublishedMedia.swift`): `static func digest(fileName:) -> String?` e `var isValid`. Ambos os call sites vivem no alvo `FeedMineMedia`; hoje nada garante que os dois alfabetos continuem coincidindo se um mudar.

### F9 — Boilerplate de `URLSessionConfiguration` nos testes (12 cópias) — **AUTORIZADA**

`FeedMineAppTests/CompositionTests.swift:174-176, 313-317, 1170-1174, 1381-1384, 1546-1548, 1648-1651, 1741-1744, 2254-2257, 2322-2326`; `CatalogueUpdateAcceptTests.swift:239-243`; `ContentFilterTests.swift:25-29`; `ReadingCompositionTests.swift:88-92`. O mesmo bloco `ephemeral` + `protocolClasses` + `timeoutIntervalForRequest` + construção de `AppComposition`.

**Veredito: unificar** numa fábrica em `FeedMineAppTests/` (`fixtureComposition(protocols:timeout:feeds:directory:)`). Não toca produção.

### F10 — Datas de exibição/export

`FeedItemCardView.swift:467-489` (`relativeFormatter` + `shortDateFormatter` + `formatted(_:)`) × `ReaderImportExportCoordinator.swift:300-306` (`mediumDate`).

**Veredito: deixar como está.** Estilos diferentes (`.short` relativo × `.medium`), módulos incompatíveis na direção natural (`FeedMineUI` só depende de `FeedMineDomain` + `FeedMineRuntime`), e um helper compartilhado exigiria expor superfície pública em `Domain` para economizar 6 linhas. Não compensa.

### F11 — Loops de consulta "chunk no limite de parâmetros" (intra-arquivo) — **AUTORIZADA**

`PublicationStore.swift:722-757` (`publishedMaterial`) × `:758-780` (`publishedOrigins`): os dois fazem `keys = Array(Set(ids)).map{...}`, `capacity = db.maximumStatementArgumentCount - 1` e chunking idêntico.

**Veredito: fundir** num privado `chunked(_ keys:in:)` no mesmo arquivo (após um eventual split: `PublicationStore+Coding.swift`). ~59 → ~40 linhas.

---

# 3. Splits propostos — **PLANO DE MANUTENÇÃO, NÃO ORDEM**

> **Aviso:** o arquiteto **recusou** os splits por tamanho nesta rodada (ver "Estado após a decisão", item 1). Esta seção existe para que a medição não se perca e para que uma futura autorização não exija remedir. Nada aqui deve ser executado agora.

Regras de execução (valem para qualquer autorização futura):

- **Nenhum split exige módulo novo.** Todos os arquivos novos caem no alvo que já contém o original.
- Para os dois arquivos do **alvo app**, o projeto é um `.xcodeproj` com membros explícitos: `FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj` lista um `PBXFileReference` por arquivo `.swift`. Cada arquivo novo precisa entrar no `pbxproj` e no grupo do alvo.
- Membros `private` não são visíveis de outro arquivo. Mover métodos para `extension` em arquivo separado exige rebaixar `private` → `internal` nos membros que cruzam. Onde é obrigatório, está anotado.

## 3.1 `AppComposition.swift` (2915 → 10 arquivos)

| arquivo | conteúdo | linhas |
|---|---|---|
| `AppComposition.swift` (fica) | props `:21–103`, `connecting` `:105–128`, `filterLanguages`/`preferredBookmarkListID`/`submitSearch` `:129–147`, `init` `:148–287`, `background` `:463–470` | ~**275** |
| `AppComposition+Catalogue.swift` | `backgroundRefreshOpportunity` `:288–412`, `adoptActivatedCatalogue` `:413–444`, `statedCatalogueAuthority` `:445–462` | 175 |
| `AppComposition+Context.swift` | `searchSources` `:471–515`, `presetAfterSelectionChange` `:516–524`, `toggleSource` `:522–558`, `selectContext` `:559–589`, `applyFilter` `:590–600`, `filterExpiry`/`resolvedFilter`/`transitionFilter` `:601–624`, `presetRows` `:625–653`, `activateSavedPreset` `:654–683` | 213 |
| `AppComposition+Library.swift` | handles `:684–723`, filtros aplicados `:724–760`, collections/presets `:761–804`, sessão de coleção `:805–864`, onboarding `:865–945`, import/export `:946–1029` | 346 |
| `AppComposition+Media.swift` | intents `:1030–1045`, hook DEBUG `:1046–1075`, coordinator de mídia `:1076–1086`, `reapplyReaderFilters` `:1087–1099`, source store/health/`adoptSelectionChange` `:1100–1156` | 127 |
| `AppComposition+Discovery.swift` | `scoring` `:1157–1176`, `feedFacts` `:1177–1196`, `association(contextKey:)` `:1197–1227`, `discoveryTraversal` `:1228–1239`, `discoveryFeeds` `:1240–1276`, `discoveryProfile`/`namesAnything` `:1277–1292`, `DiscoveryCacheKey`/`DiscoveryWalkKey` `:1493–1515` | ~199 |
| `AppComposition+Editorial.swift` | `voteOnTopic` `:1326–1355`, `record*` `:1356–1392`, settings/`declaredLevel` `:1393–1422`, `editorialSubject`/tips `:1423–1456`, `subjects`/`nodeKey`/`trustedFeed` `:1457–1489`, `refreshFromTheReader` `:1526`, `replaceSession` `:1535–1555` | ~200 |
| `FeedAssociation.swift` (fica: tipo + props + `readerCardActions`/`readerDestinations` `:1557–1642`) | declaração e constantes | ~90 |
| `FeedAssociation+Actions.swift` | `perform` `:1643–1681`, `sourcePage` `:1682–1695`, `toggleBookmark` `:1696–1705`, `refreshMenuDestinations` `:1706–1751`, `supply` `:1752–1763`, `open`/`openSaved`/`read`/`readingTarget`/`resolvedExternalURL`/`present` `:1764–1824`, `savedArticles` `:1825–1877`, `presentationBounds` `:1878–1887`, `mayShow` `:1888–1899`, `sequencingBehavior` `:1900–1910` | ~302 |
| `FeedAssociation+Media.swift` | `tidyAllowanceSeconds` `:2234–2252`, `mediaWaitSeconds` `:2254–2262`, `prepare` `:2263–2299`, `readinessLabel` `:2300–2319` | 87 |
| `FeedAssociation+Runway.swift` | `install` `:2321–2362`, growth `:2363–2436`, `retryNow`/`launch` `:2438–2500`, retry local `:2501–2523`, `viewport` `:2560–2660`, posição `:2661–2698`, `foreground`/`background`/`close` `:2699–2789`, `reportFailure`/`isConnectionFailure`/`log` `:2790–2826` | ~370 |
| `AppSupportTypes.swift` | `DeviceMediaConditions` `:2828–2871`, `NetworkPathObserver` `:2873–2897`, `EvidenceRelay` `:2899–2905`, `LiveValue` `:2907–2915` | 89 |

**O que fica no arquivo original e não pode sair:** as *stored properties* de `AppComposition` (`:21–103`, `:703`, `:726`, `:1497`, `:1515`) e de `FeedAssociation` (`:1557–1594`, `:2363–2365`) — propriedades armazenadas não podem ser declaradas em `extension`. Por isso o residual é ~275 + ~90 e não 60.

**Maior ganho do pacote:** o `init` de `FeedAssociation` (`:1920–2221`, 302 linhas) permanece, mas passa a ser o único bloco grande do arquivo. Decompor esse `init` em três fábricas privadas (`makeAcquisition`, `makeMedia`, `makeRunway`) é o passo seguinte natural e **não** deve ser feito junto com o split mecânico: muda ordem de construção e de efeitos colaterais, logo é mudança de comportamento, não movimentação de código.

## 3.2 `FeedMineApp.swift` (1320 → 4 arquivos)

| arquivo | conteúdo | linhas |
|---|---|---|
| `FeedMineApp.swift` (fica) | `:13–72`, `:115–207` (estado de superfícies), `:240–621` (`body`), `:1259–1320` | ~**535** |
| `AppRoutes.swift` | `extension FeedMineApp { enum SheetSurface :73–96; enum ReaderPage :99–102; enum AppSurface :111–114; enum LibraryRoute :229–232; enum SourceRoute :235–238 }` | ~42 |
| `ReaderHostView.swift` | `struct ReaderHost` `:623–1035`, com `WindowReaderPresentation` `:668–710` e `Coordinator` `:712–1035` | 413 |
| `AppImportExport.swift` | `:1036–1258`: `completeOnboarding`, `deviceLanguage`, `targetCollectionName`/`collectionPresetID`, `writtenExport`, `readImportedFile`, `presentOnboardingImportIfPending`, `resumeOnboardingAfterImport`, `onboardingImportFixtureURL`, `importSummary`, `associationStoreToast`, `importableTypes`, `boxID`, `signature`, `switchContext` | ~223 |

**Anotado, não proposto:** `LibraryPrompt` `:208–227` é `private` — movê-lo exige rebaixar para `internal`. E `body` (`:240–621`, 382 linhas) só reduz de verdade quando cada sheet virar view nomeada; isso é refatoração com risco de comportamento de apresentação, fora do escopo mecânico.

**Preservação obrigatória de nomes qualificados:** `FeedMineApp.ReaderPage` e `FeedMineApp.ReaderHost` são usados por `FeedMineAppTests/ReaderHostTests.swift:20-21,187,191,199`. Declarar os tipos **dentro de `extension FeedMineApp`** mantém `FeedMineApp.ReaderHost` válido sem tocar nos testes.

## 3.3 `PublicationStore.swift` (1166 → 6 arquivos, alvo FeedMinePersistence)

| arquivo | faixa | linhas |
|---|---|---|
| `PublicationStore.swift` (fica: erro `:11–24` + tipo `:26–150`) | | ~**196** |
| `PublicationStore+Editions.swift` | `:151–330` (create/append/insert/markSeen/setVisibility) | 180 |
| `PublicationStore+HiddenTail.swift` | `:331–429` (`hiddenTail`, `succeedTail`, `seenMaterial`) | 98 |
| `PublicationStore+Reader.swift` | `:430–508` (`mediaLocator`, bookmarks, `mediaUsage`) | 80 |
| `PublicationStore+Windows.swift` | `:500–807` (`tail`, `edition`, `card`, `segments`, `cards`, `readyAhead`, `exposure`, `forwardAdvance`) | 308 |
| `PublicationStore+Coding.swift` | `:809–1066` (história/probe/posições, `validate*`, `insert*`, arrays de colunas, decoders) + `PublicationValueCoding` `:1140–1166` | ~320 |

`private` → `internal` obrigatório em `insert`, `publishedMaterial`, `publishedOrigins` e nos estáticos de `history*`. Se F4 fosse aplicado, `PublicationRecordFields` `:1096–1138` deixaria de existir aqui.

## 3.4 `ContentStore.swift` (821 → 6 arquivos, alvo FeedMinePersistence)

| arquivo | faixa | linhas |
|---|---|---|
| `ContentStore.swift` (fica: `:8–78`) | | ~**72** |
| `ContentStore+Candidates.swift` | `:79–250` | 172 |
| `ContentStore+AdmissionReads.swift` | `:252–313` | 62 |
| `ContentStore+Mutation.swift` | `:321–441` | 121 |
| `ContentStore+Reads.swift` | `:443–507` | 65 |
| `ContentStore+Coding.swift` | `:509–771` (+ `ContentFields` `:773–822` se F4 não for feito) | 263 |

## 3.5 `FeedScreen.swift` (807 → 4 arquivos, alvo FeedMineUI)

| arquivo | faixa | linhas |
|---|---|---|
| `FeedScreen.swift` (fica: `struct FeedScreen` + `body`) | `:10–209` | **200** |
| `FeedScreenChrome.swift` | `:211–268` (`FeedFlowCounters`, `EditorialSlot`, `FeedWorkFeedback`, `FeedWorkBadge`, `BadgeStyle`) | 58 |
| `FeedVisualCapture.swift` | `:271–619` (`FeedVisualGeometry`, `FeedVisualEvent`, `FeedVisualCardGeometry`, `FeedVisualMotion`, `FeedVisualCapture`) | 349 |
| `FeedNativeViewport.swift` | `:621–807` (`NativeFeedViewport`, `NativeFeedTargets`) | 187 |

`BadgeStyle` `:260` e `NativeFeedViewport` `:623` são `private` **no escopo de arquivo** → precisam virar `internal`. `FeedVisualCapture` já é referenciado de fora (`FeedScreen.swift:33`, `FeedNativeScrollOffset.swift:199-200`, `Tests/ArchitectureSmokeTests/FeedViewportCaptureTests.swift:743-745`) — mover não quebra nada. Os nomes novos são coerentes com os vizinhos já existentes (`FeedNativeScrollOffset.swift`, `FeedInteractionPresentation.swift`, `FeedWindowOffsetCorrection.swift`).

---

# 4. Simplificações e exclusões, com prova

## 4.1 Oito arquivos-comentário sem uma única declaração (322 linhas, 0 código)

`Sources/FeedMineComposition/FeedMineBootstrap.swift` (48) · `FeedMineComposition/FeedMineEnvironment.swift` (34) · `FeedMineDomain/InteractionOffer.swift` (45) · `FeedMineEditorial/FeedPlanResolver.swift` (32) · `FeedMineRuntime/FeedSessionEffects.swift` (42) · `FeedMineRuntime/FeedSessionReducer.swift` (41) · `FeedMineRuntime/FeedSessionUI.swift` (46) · `FeedMineRuntime/InteractionCoordinator.swift` (34). Todos terminam com `// Status: Architecture scaffold only. Production behavior is intentionally absent.` (linha 24 em cada).

**Prova 1 (nenhuma declaração):** `grep '^\s*(import|public|internal|struct|enum|class|actor|extension|func|let|var|@)'` sobre os 8 arquivos → **"No matches found"**.

**Prova 2 (nenhuma referência):** `grep 'FeedMineBootstrap|FeedMineEnvironment|InteractionOffer|FeedPlanResolver|FeedSessionEffects|FeedSessionReducer|FeedSessionUI|InteractionCoordinator'` sobre `Sources/`, `FeedMineApp/`, `Tests/` e `Package.swift` → as **únicas** ocorrências são os cabeçalhos dos próprios arquivos.

**Veredito: deletar** — mas a operação é maior que `rm`, e isso precisa estar no plano:

1. `docs/architecture/FILE_RESPONSIBILITIES.md:15, 32, 59, 60, 61, 67, 73, 74` tem uma linha por arquivo;
2. `docs/architecture/ARCHITECTURE.md:110` e `:149` os citam como camadas/alarmes de tamanho;
3. `docs/architecture/DOMAIN_MODEL.md:95`, `SELECTION_DESIGN.md:59, 217` e `CONTINUOUS_FEED_RUNWAY_DESIGN.md:30, 91` os tratam como "future owner";
4. `docs/reviews/CODE_REVIEW_2026-10-08.md:227-229` já os lista como *"Still scaffold"* e `docs/reviews/FEEDMINE_V2_U1_REVIEW.md:138` diz literalmente *"`FeedSessionUI.swift` remains dead scaffolding in the module"*;
5. os 8 arquivos são membros compilados do `FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj` (visível em `docs/evidence/2026-10-11-ux-diagnosis/R3-uitest.log:3517-3530, 3558-3571, 4080-4088`).

Se a intenção de arquitetura (o mapa "quem será dono de quê") deve sobreviver, o caminho é mover o texto para `docs/architecture/SCAFFOLDS.md` e apagar os `.swift`: a informação é comentário, e comentário pertence a docs.

## 4.2 Escritas incondicionais de contadores que só um traço DEBUG lê — **AUTORIZADA**

`FeedFlowCounters` (`FeedScreen.swift:211-218`) tem os três valores escritos **sem `#if DEBUG`** em `AppComposition.swift:2322, 2324, 2325` (a cada install de apresentação), e é **lido num único lugar**: `FeedNativeScrollOffset.swift:199-200`, dentro do rótulo de diagnóstico governado por `FeedVisualCapture.tracesCapture` (`FeedScreen.swift:366`, ligado por `FEEDMINE_TRACE_CAPTURE=1`).

**Veredito: envolver as três escritas em `#if DEBUG`** — o produto não paga nada por um instrumento desligado.

## 4.3 Fronteiras DEBUG espalhadas por `AppComposition.swift`

Quinze blocos `#if DEBUG` no mesmo arquivo: `:31–33`, `:164–169`, `:173–186`, `:216–222`, `:296–298`, `:457–461`, `:1046–1075`, `:1853–1857`, `:2036–2077`, `:2339–2344`, `:2417–2429`, `:2572–2574`, `:2624–2627`, `:2765–2766`, `:2819–2821`.

**Veredito: não mexer agora.** Concentrá-los exigiria expor estado interno a um arquivo `+Debug` (relaxando `private` em ~8 propriedades) para ganho estético; e o bloco `:2036–2077` (autorização de origens não públicas, exigência do arquiteto na revisão do PR #3) é código de segurança que se beneficia de estar visível onde é usado. O único sub-bloco que vale mover, por ser autocontido, é `:1046–1075` (playback simulado + `writeSilentWavefile`, 30 linhas) para `AppComposition+Debug.swift`.

---

# 5. Ordem de execução sugerida

Válida para o escopo **autorizado**:

1. **Deletar/mover os 8 scaffolds** (§4.1) + ajustar as seis docs listadas. Independente de todo o resto.
2. **Deduplicação local:** F7, F9, F11, F6, F8 (§2) — sem mudança de assinatura pública observável. F11 e F6 são intra-arquivo; F7 vive no alvo app (sem arquivo novo, sem `pbxproj`); F8 vive em `FeedMineMedia`.
3. **§4.2** — embrulho `#if DEBUG` das três escritas de `FeedFlowCounters`.

**Fora desta rodada (aguardando autorização explícita):** F2, F3, F4, F5 e todos os splits do §3.

---

# Divergência

Registro técnico onde discordo da decisão vigente. **Não muda o veredito** — nada aqui deve ser executado sem autorização do arquiteto.

### Divirjo de deixar F2 fora

A regra "não criar helper compartilhado entre módulos só porque duas funções se parecem" é correta contra abstração cosmética, mas F2 não é semelhança: é **o mesmo digest escrito sete vezes**, e há casos em que as cópias *já divergiram* em formato — `SyndicationHTTP.swift:260-262` e `CatalogManifest.swift:102` produzem a forma **prefixada** `"sha256:" + …` (é uma chave de identidade persistida: `AssetStore.swift:38` grava a chave como `"sha256:" + digest`, e `MediaHousekeeping.swift:32` reconstrói a mesma chave a partir do nome do arquivo), enquanto `ReaderLibraryStore.swift:66-68` e `SyndicationTranslator.swift:260-262` produzem hex **puro**. Isto é, a duplicação já produziu duas convenções conviventes, e o custo de uma divergência acidental não é cosmético: muda a identidade de um asset de mídia ou o fingerprint de um checkpoint. Um `hex()` de duas linhas em `FeedMineDomain` não é uma abstração nova — é a única forma de a convenção ter um dono. Ainda assim, aceito que adiar é defensável: nenhuma das sete cópias está errada hoje, e o risco é latente, não ativo.

### Divirjo parcialmente de deixar F3 fora

Mesma análise, com um argumento a mais e um a menos. A mais: `Content.swift:382-390` e `FeedContext.swift:125-129` são **byte-idênticos** e ambos alimentam identidade canônica (o `canonicalText` de `Content` é conferido na releitura em `:408-412`; o `canonicalJSON` de `ContextKey` é a identidade do checkpoint). Duas cópias idênticas de uma função de canonicalização de identidade são exatamente o tipo de par que precisa de dono único. A menos: ninguém tocou na formatação por acidente ainda, e o risco de mexer em `CatalogManifest`/`CatalogCompiler` — que eu já recomendo isolar em qualquer cenário — é real. Adiar é o conservador correto; registro apenas que o par Content/FeedContext é mais forte que "duas funções parecidas".

### Divirjo de deixar F4/F5 fora **nesta** ordem

F4 e F5 não são sobre juntar funções parecidas: são sobre **duas implementações do mesmo mapeamento de erro**, e é onde a duplicação pode esconder um bug de comportamento. `ContentStore.swift:510-519` e `PublicationStore.swift:1141-1165` traduzem o mesmo `PersistenceValueCodingError` para erros de store diferentes; e `PublicationRecordFields` × `ContentFields` decidem o mesmo conjunto de regras de decodificação (null vs tipo errado vs fora de faixa) com dois códigos independentes. Se os dois divergirem, o sintoma é um store aceitar uma linha que o outro recusa — silencioso, e num caminho de persistência. Concordo em **não fazer agora**, se a prioridade é não mexer em nada que toque as jornadas recém-recuperadas: `PublicationStore.swift` e `ContentStore.swift` são, por definição, arquivos que a execução das jornadas atravessa. Mas registro que, dos quatro adiados, F4/F5 são os de maior valor por linha mudada — e que o momento natural para eles é **antes** de qualquer split de store (§3.3/§3.4), nunca depois, senão a duplicação é propagada para dois arquivos de cada lado.
