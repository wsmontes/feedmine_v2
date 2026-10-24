# Code Review — feedmine_v2 build 54

**Escopo:** diff completo `c6c62c8` (2026-10-12) → `3eee193` (2026-10-21, tag `ios/1.0-build.54`).
**Tamanho:** 90 arquivos novos, 98 modificados, 9 removidos, 1 movido (666 arquivos no total com docs/bench/scripts).
**Clone revisado:** `C:\workspace\feedmine_v2-kiro` @ `3eee193` (detached).
**Método:** leitura do diff real por subsistema. Achados confirmados contra o código no commit (arquivo:linha citados). **Não** foi possível compilar/rodar testes (host Windows sem toolchain Swift) — correctness vem de leitura, confirmar contra os testes indicados.

Comando para reproduzir qualquer trecho:
```
git -C C:\workspace\feedmine_v2-kiro show 3eee193:<path>
git -C C:\workspace\feedmine_v2-kiro diff c6c62c8 3eee193 -- <path>
```

---

## Contexto arquitetural (ler antes dos achados)

Os 8 arquivos deletados (`FeedSessionReducer`, `FeedSessionEffects`, `FeedSessionUI`, `InteractionCoordinator`, `FeedPlanResolver`, `FeedMineBootstrap`, `FeedMineEnvironment`, `InteractionOffer`) eram **scaffolds de documentação** ("Status: Architecture scaffold only. Production behavior is intentionally absent") — sem tipos, sem código. Portanto **não há regressão vinda das remoções**; esta build é a **primeira implementação real** do runtime, agora em modelo actor-based:

- `FeedSession` (actor) — dona da lista admitida; entrada única `admitPresentation(_:)` com 5 casos; append-only, nunca move o leitor.
- `RunwayController` (actor) + `RunwayPolicy` (enum puro) — a "transição pura" planejada sobrevive como `RunwayPolicy.evaluate`.
- `FeedRunwayDriver` (actor, +699) — executa efeitos; concentra a concorrência pesada.
- `FeedAssociation` (@MainActor, em `AppComposition.swift`) — ingress; o callback de scroll grava um fato e retorna, o trabalho pesado roda nos atores off-main.

"Scroll off the main actor" = o corpo da view deixou de ler a posição (passou a ler `store.renderedItems`), então um avanço não re-renderiza a lista. Correto e é a causa-raiz do engasgo de 2026-10-14 estar resolvido.

Severidade: **P0** = corrige antes do merge · **P1** = corrige nesta rodada · **P2** = follow-up.

---

## P0-1 — SSRF: redirect alcança host privado antes da validação

**Arquivo:** `Sources/FeedMineSyndication/FeedDiscoveryTransport.swift`, `URLSessionFeedDiscoveryTransport.send(_:)`.

O cabeçalho do arquivo promete: *"a redirect must not take it there either"*. A implementação **não cumpre**. O host é validado antes da chamada e de novo depois:

```swift
let (bytes, response) = try await session.bytes(for: urlRequest)
guard let http = response as? HTTPURLResponse else { throw .unreachable }
// A redirect that lands on a private host is refused after the fact: the body is never read.
if let finalHost = http.url?.host, !NetworkHostPolicy.isPubliclyRoutable(finalHost) {
    throw FeedDiscoveryTransportError.refused
}
```

`session.bytes(for:)` **segue os redirects automaticamente**. Quando o check pós-fato roda, a URLSession **já conectou e emitiu o request** para o host intermediário/final (ex.: redirect 302 para `http://169.254.169.254/...`, loopback ou LAN). O check só impede ler o corpo — a requisição ao host privado já aconteceu. É um SSRF explorável por endereço fornecido pelo leitor.

**Correção:** instalar um `URLSessionTaskDelegate.urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` que roda `NetworkHostPolicy.isPubliclyRoutable` em **cada hop** e cancela (chama `completionHandler(nil)`) antes de conectar, em vez de validar depois. Exige trocar a `URLSession` por uma com delegate (ou usar `URLSession(configuration:delegate:delegateQueue:)`).

**Limitação a documentar:** a policy checa a string do host, não o IP resolvido → **DNS rebinding** não é coberto. Aceitável como limitação declarada, mas colocar o comentário.

**Teste:** não existe teste de redirect no transport (o diff de Tests só tem `FeedLinkResolverTests`). Adicionar teste que um redirect para host privado é recusado **sem** ter emitido o request ao host privado (usar `URLProtocol` stub contando conexões).

---

## P0-2 — Observação não-monotônica vira banner "Falha ao atualizar o feed" em scroll normal

**Arquivos:**
- `Sources/FeedMineRuntime/RunwayController.swift:330-338` (`submitObservation`)
- `FeedMineApp/FeedMineApp/AppComposition.swift:3888` (`FeedAssociation.viewport`), catch final em `:3962-3971`, `reportFailure` em `:4217`, mensagem em `:4231`.

`submitObservation` lança quando o tempo não avança estritamente:

```swift
if let latestObservation, observation.sampledAt <= latestObservation.sampledAt {
    throw RunwayControllerError.nonMonotonicObservation
}
```

`FeedAssociation` carimba `sampledAt = ProcessInfo.processInfo.systemUptime` por callback. Dois fatos coalescidos no mesmo burst podem ler `systemUptime` **idêntico** → o segundo lança `.nonMonotonicObservation`. O `viewport()` tem **um único catch genérico**:

```swift
} catch {
    reportFailure(error)          // operation default = .feedRefresh
    if evidence?.isPositionReconciliation != true { await scheduleLocalRetryIfNeeded() }
}
```

e `reportFailure` com `.feedRefresh` não-transporte instala:

```swift
: .failed(message: String(localized: "Falha ao atualizar o feed"))   // :4231
```

Resultado: **scroll normal pode exibir banner de falha ao usuário.** Nota: `.staleMeasurement` provavelmente tem o mesmo destino — verificar.

**Correção (escolher uma):**
1. No drain de ingress, garantir `sampledAt` estritamente crescente (desempatar stamps iguais com o `ordinal` que `PendingViewportIngress.takeNext()` já tem, mas que hoje **não** é carregado para `RunwayObservation.sampledAt`); **ou**
2. em `submitObservation`, tratar `==` como no-op benigno (só lançar em `<`); **ou**
3. em `viewport()`, capturar `RunwayControllerError.nonMonotonicObservation` (e `.staleMeasurement`) e engolir como já se faz em outros pontos (`"obsolete early viewport projection rejected"`), sem `reportFailure`.

Preferir (1) ou (3): manter a monotonicidade como invariante real.

**Teste:** `CompositionTests` já tem o guarda D5 (`"Falha ao atualizar o feed"` só pode falar por feed refresh). Adicionar: dois `viewport` com `sampledAt` igual não produzem `.failed`.

---

## P0-3 — Controles de recuperação mortos no `FeedLoadingView`

**Arquivos:** `Sources/FeedMineUI/FeedLoadingView.swift` (`actions()`), callsite em `Sources/FeedMineUI/FeedScreen.swift`.

`FeedScreen` sempre passa wrappers não-nil (`{ onTryAgain() }`, `{ onAdjustInterests() }`) ao `FeedLoadingView`, cujo `actions()` renderiza o botão quando o closure é não-nil. Os defaults do host são no-op (`{}`), então os botões **"Tentar novamente" / "Ajustar interesses"** nas superfícies `.unavailable`/`.unreachable` **renderizam e não fazem nada** se o host não cabeou a ação — violando a regra do próprio projeto de "sem controle morto" (regra que `FeedEndOfContentView` respeita via opcionais).

**Correção:** passar `nil` quando o closure do host é o no-op default, espelhando o padrão de `FeedEndOfContentView` (closures opcionais → botão só existe se há ação).

---

## P1-1 — Primeira tela pode expor cedo (cobertura usa `.max()` sobre dict não podado)

**Arquivos:**
- `Sources/FeedMineUI/FeedScreenStore.swift:452` (`contentBottoms`), `:469-472` (`coverage`), `:483` (`record`), `:376` (`freeze`).
- `Sources/FeedMineUI/FeedFirstScreenGate.swift` (`FeedFirstScreenCoverage.coversViewport`).
- Alimentado por `FeedScreen.swift:161` (`noteFirstScreenLayout`, chamado **por card**).

```swift
// FeedScreenStore.swift
private var contentBottoms: [PublicationCardID: CGFloat] = [:]   // :452
var coverage: FeedFirstScreenCoverage? {
    guard let bottom = contentBottoms.values.max() else { return nil }      // :470
    return FeedFirstScreenCoverage(laidOutCards: contentBottoms.count,       // :471
        contentBottom: bottom, viewportHeight: ...)
}
func record(cardID:contentBottom:viewportHeight:) { contentBottoms[cardID] = contentBottom }  // :483
```

`contentBottoms` acumula uma entrada por card reportado e **só é podado no `freeze()`** (`:376`). Durante um primeiro layout com churn (cards entram e saem antes de estabilizar), o dict retém `contentBottom` de cards que já não estão na tela. `coverage` usa `.values.max()` → pode devolver o bottom de um card **que saiu**, satisfazendo `coversViewport` cedo demais → `FeedFirstScreenGate.surface` retorna `.reading` antes da tela estar realmente cheia, e `FeedLaunchWitness.noteFirstExposure` (`FeedScreenStore.swift:370`) grava `laidOutCards`/`contentBottom` inflados.

Nota de calibração: o resumo inicial falou em "append-only count" num tipo `FeedFirstScreenHold`; o nome/estrutura reais são os acima. O risco **existe**, mas a causa precisa é a ausência de poda de `contentBottoms` fora do freeze combinada com `.max()`.

**Correção:** podar `contentBottoms` para os cards atualmente renderizados antes de calcular `coverage` (interseção com `renderedItems`/janela), ou recomputar o dict a cada layout em vez de acumular. Garantir que `laidOutCards` conte apenas cards distintos presentes.

**Teste:** primeira janela com churn (inserir N cards, remover os K do topo antes de estabilizar) **não** deve expor a reading-surface até a geometria dos cards vivos cobrir o viewport.

---

## P1-2 — `ReaderDiscoveryPreferencesView`: lost-update sob toques rápidos

**Arquivo:** `Sources/FeedMineUI/Settings/ReaderDiscoveryPreferencesView.swift` (binding `profile`), `ReaderSettingsStore.update`.

```swift
private var profile: Binding<FeedRecipeDefinition> {
    Binding(get: { store.settings.discoveryProfile },
            set: { value in Task { await store.update { $0.discoveryProfile = value } } })
}
```

`ReaderDiscoveryControls` escreve snapshot cheio (`var next = get(); next.X = …; set(next)`). O `set` dispara um `Task` async; `update` faz `await backend.update(next); settings = try await backend.settings()`. Dois toques rápidos em controles diferentes: o `get` do toque B pode ler `settings` **antes** do readback de A → o snapshot de B não tem a edição de A → o `settings` final reflete só B. **Preferência silenciosamente descartada.** Tudo `@MainActor`, então não é data race/crash — é lost-update visível ao usuário.

Não afeta o F02 in-feed nem o Composer de primeira execução (mutam `@State` local síncrono e salvam uma vez).

**Correção:** aplicar `change` contra o `settings` **mais fresco no momento da execução** (o closure `$0` já faz isso — o problema é o `value` capturado). Reescrever para que o controle mande a *mutação*, não o snapshot: `store.update { $0.discoveryProfile.X = … }`; e/ou serializar as escritas (single-flight / coalescing).

---

## P1-3 — `RuntimeDatabase`: fallback case-insensitive não checa o código do erro

**Arquivo:** `Sources/FeedMinePersistence/RuntimeDatabase.swift` (convenience init).

O fallback que reutiliza um diretório irmão de case variante dispara em **qualquer** falha de `createDirectory` quando `!volumeIsCaseSensitive` e existe um irmão de case variante. O comentário diz que o gatilho é a colisão de case medida (`NSCocoaErrorDomain 512` / POSIX 5 `EIO`), mas o código **não inspeciona o código do erro**. Uma falha transitória/de permissão num volume case-insensitive com um irmão coincidente redireciona o store V2 para esse irmão — exatamente o "V2 abriu dentro dos dados do V1" que o design quer evitar.

**Correção:** gatear o fallback na inspeção do código de erro (EIO/512, no estilo de `AssetStore.isOutOfSpace`) antes de reusar a variante. (`volumeIsCaseSensitive` já tem default seguro/true quando desconhecido — ok.)

---

## P1-4 — Seleção não migra no `ReaderLibraryStore.reconcile`

**Arquivos:** `Sources/FeedMinePersistence/ReaderLibraryStore.swift` (`reconcile(_:)`), `Sources/FeedMinePersistence/ReaderPreferencesStore.swift`.

`reconcile` reescreve `reader_source_identity` e migra `reader_collection_memberships` de newKey→anchor(oldKey). Leituras de coleção resolvem pelo alias (`COALESCE(i.anchor_key, m.source_key)`). Mas a **seleção do leitor** (`reader_preferences.source_keys`, JSON) **não é migrada** e é lida por decode JSON puro, sem resolução de anchor. Se o leitor tinha `newKey` selecionado e o reconcile fixa anchor=`oldKey`, a seleção continua apontando para `newKey` aliased → seleção silenciosamente quebrada.

**Correção (uma):** migrar `source_keys` na **mesma transação** do `reconcile`; **ou** resolver a seleção via `reader_source_identity` na leitura; **ou** documentar e garantir a invariante de que a seleção só guarda anchor/catalog keys. Confirmar a invariante pretendida com o dono.

---

## P1-5 — Editorial: candidato elegível-mas-não-ready pode ser pulado

**Arquivo:** `Sources/FeedMineEditorial/SelectionEngine.swift` (`select(...)`, `report(window:held:placedAny:)`).

```swift
readyEligible = eligible.filter { readiness?.readyRevisionIDs.contains($0.originRevisionID) ?? true }
```

Ordenação/alternância operam em `readyEligible`. O rewind do cursor em `report` só protege os **held** (ready-mas-adiados). Um candidato elegível mas **não-ready** não é nem placed nem held; com `placedAny == true` o cursor avança (`nextCursor = window.nextCursor`) e pode passar de um candidato não-ready que está **antes** no window de um ready que foi placed. A reconsideração dele passa a depender do keyset voltar a ele numa passada posterior — se o cursor avançou além, só volta quando o window dá a volta. (Dedup/exposure usam `window.candidates` cheio — essa parte está correta; o problema é só **progresso para frente** de revisões suspensas/não-ready.)

**Correção:** confirmar com o dono do editorial que a preparação garante re-apresentação de não-ready dentro do mesmo window; **ou** fazer `report` tratar candidato não-ready como motivo de rewind.

---

## P2 (follow-ups)

- **`FeedRunwayDriver` é grande demais (actor +699)** com ~15 peças de estado late-fact/coverage/background enforçadas por convenção, sem máquina de estados explícita. Maior risco de manutenção de longo prazo. Extrair o ciclo de late-fact num tipo próprio com enum de estado. (`Sources/FeedMineComposition/FeedRunwayDriver.swift`)
- **Monitores não-estruturados vs retirement** (`FeedRunwayDriver.observeCoverageRound`/`observeBackgroundRound`): `deactivate()` invalida identidade/nilifica `backgroundRound` mas **não cancela** as `Task` observadoras; elas seguem aguardando `round.completion` num transporte invalidado. Confirmar que `close()` **aguarda/cancela** essas tasks, senão um ciclo activate/deactivate rápido acumula tasks vivas.
- **`FeedFlowCounters` é `nonisolated(unsafe) static var` público e NÃO-DEBUG** — main-actor na prática, mas embarca em release como aresta de corrida não checada. Tornar `@MainActor` ou documentar. (`FeedMineApp/FeedMineApp/AppComposition.swift:3333` e def.)
- **`refreshPresentedTop` tie-break** (`FeedVisualCapture.swift`): `.min { $0.value.top < $1.value.top }` sobre `Dictionary` — empates exatos de content-top resolvem por ordem de iteração indefinida e podem alternar `presentedTop` entre passadas. Adicionar chave secundária determinística (índice na janela).
- **`PublicationStore+History` archive por ordem posicional** (`:111`, `INSERT INTO retired_published_cards SELECT * FROM published_cards`): seguro hoje (ambas as tabelas recebem `ADD COLUMN` na mesma ordem — `diversity_facts` depois `media_identity`, migrations 591/592 e 626/627), mas frágil: um `ADD COLUMN` futuro numa só tabela corrompe o arquivo silenciosamente. Usar lista de colunas explícita.
- **`PublicationStore+Coding.optionalStringIfPresent`**: `try?` converte um `media_identity` **presente mas de tipo errado** em nil ("unknown") em vez de `.corruption` (diferente de `diversity_facts`, que lança). Separar "coluna ausente" (nil) de "presente mas tipo errado" (throw).
- **`LegacyUserStateReader.importedSources()`**: `enabled: (row["enabled"] as Int64) != 0` dá trap se a coluna existe mas o valor é NULL numa linha V1. Usar `(row["enabled"] as Int64?) ?? 1 != 0`.
- **`reader_playback_positions` sem FK** para `published_cards` (diferente de `saved_media_availability` com `ON DELETE CASCADE`): posições orfãm quando cards são retirados. Baixa prioridade, igual ao comportamento V1.
- **`ReaderSearchResultsStore.apply` e `applyAppended` são idênticos**; o split semântico não é enforçado no próprio store (a checagem query+scope vive só no `FeedScreenStore`). Colapsar ou enforçar.
- **i18n/plural**: `"\(template.ruleCount) palavras"` interpola número sem catálogo de plural → "1 palavras". Cosmético. (`ReaderContentFilterView`)

---

## Verificado e OK (não mexer — registrado para evitar retrabalho)

- **`setSourceEnabled` default lança** (`SourceManagementStore.swift:43-50`) — mas o backend de produção **implementa** o método (`SourceCatalogBackend.swift:78-80` → `SourceManagementCoordinator.setSourceEnabled` `:172`). O toggle de produção **não** quebra. (O resumo inicial marcou isto como bloqueador; não é.)
- **`observeCard` global-shift** (`FeedVisualCapture.swift`): o shift só se aplica quando a **mesma** carta reporta de novo com entrada prévia e `abs(moved - shift) <= 0.5`; há teste determinístico citado no comentário ("8 onde a tela mostra 6"). Não é o bug simples que o resumo sugeria — o risco residual é o tie-break de `refreshPresentedTop` (ver P2) e a poda de coverage (P1-1).
- **Migrations**: todas aditivas e ordenadas (append após as existentes); `eraseDatabaseOnSchemaChange=false` forçado; recibo de upgrade D7 escrito na mesma transação das linhas importadas; `recordLegacyUpgradeFailure` nunca sobrescreve recibo completo. Colunas nullable preservam história como "unknown".
- **Camada de mídia** (`AssetStore`/`MediaPolicy`/`MediaPreparation`): `isOutOfSpace` distingue `NSFileWriteOutOfSpaceError`/POSIX `ENOSPC`; `insufficientSpace` é outcome próprio; byte ceiling imposto durante o streaming, não depois.
- **Diversidade editorial** (`SelectionDiversity` + `SelectionEngine`): transitividade A9 correta (chaves de repetição largura-fixa por grupo de mesmo peso; peso domina; tie-break lexicográfico só quando ambos têm chave e diferem); gated por `sequencingPolicyVersion == 5` para preservar ordem de edições restauradas.
- **Stores token-gated**: `ReaderSearchResultsStore` (begin/apply/clear bumpam token; rejeitam completion de token antigo) + `FeedScreenStore` guardando query+scope — raça R16 fechada. `SourceManagementStore` leases monotônicos por tipo (last-writer-wins, não threading, tudo `@MainActor`).
- **Concorrência geral**: novos tipos majoritariamente value types `Sendable` com `let` imutável; closures novas em `AssetStore`/`MediaPreparation` são `@Sendable`; `FeedDiscoveryTransport` é `Sendable`. Helpers `@unchecked Sendable` com `NSLock` (`MediaReadiness`, `ResumeOnce`, `MediaFetchSettlement`, `PendingMediaReconsideration`) revisados: re-checam sob lock, sem double-resume/perda de continuation. Preferir actor em `PendingMediaReconsideration` (P2).
- **Fluxo de idioma no onboarding** (`ReaderOnboardingView`, `ReaderDiscoveryControls`): semântica "todas as línguas" (`languages=[]` + `hasLanguageAnswer=true`) vs "recipe antigo sem resposta" tratada corretamente em todas as camadas. **Mudança de comportamento a confirmar com produto:** remover a última língua agora leva ao conjunto vazio = "todas" (V1 bloqueava remover a última). Deliberado, mas é reversão semântica — confirmar intenção.
- **Add-feed** (`ReaderAddFeedStore`): proposta vazia não conta como confirmação (re-resolve em vez de no-op); separação de clipboard via closure `@MainActor`.
- **Filtros** (`FilterSheetView`/`ReaderFilterDraft`/`ReaderFilterStore`): normalização de código regional via `ReaderLanguageCode.choice` (`en-US`→`en`) consistente ponta a ponta; `ReaderFilterFailure` (persistence vs presentation) com mensagem própria. **Confirmar fora destes arquivos:** que `ReaderFilter` persiste/round-trips o novo `mediaTypes`.
- **a11y**: `ReaderHeader` label `Salvos`→`Abrir salvos` (desambigua do menu). `ReaderNavigation` ganhou `addFeedToCollection` e entrada `bookmark-boxes` → **confirmar que o switch de destino do host é exaustivo**.

---

## Checklist de merge

- [ ] P0-1 SSRF: delegate de redirect valida cada hop antes de conectar + teste.
- [ ] P0-2 non-monotonic: não emitir "Falha ao atualizar o feed" em scroll normal + teste.
- [ ] P0-3 FeedLoadingView: sem botão de recuperação morto (closures opcionais).
- [ ] P1-1 coverage: podar `contentBottoms` antes de calcular cobertura + teste de churn.
- [ ] P1-2 discovery prefs: eliminar lost-update (mutação, não snapshot).
- [ ] P1-3 RuntimeDatabase: gatear fallback no código de erro.
- [ ] P1-4 reconcile: migrar/resolver seleção.
- [ ] P1-5 editorial: garantir progresso de candidato não-ready.
- [ ] Confirmar: host trata `ReaderNavigation.addFeedToCollection`; `ReaderFilter` persiste `mediaTypes`; semântica "remover última língua = todas" é intencional.

_Gerado a partir do diff real em `3eee193`. Itens "Verificado e OK" foram lidos no código e não devem ser reabertos sem nova evidência._
