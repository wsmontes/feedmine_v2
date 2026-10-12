# K-04 — Revisão final do PR #3 (FeedMine V2) · ÁREA A — núcleo não-UI

**Diff:** `origin/main...bd74e575` · checkout `C:\workspace\feedmine_v2-int` (detached em `bd74e575`)
**Escopo lido:** `Sources/FeedMineRuntime`, `FeedMineComposition`, `FeedMinePublication`, `FeedMinePersistence`,
`FeedMineSyndication`, `FeedMineAcquisition`, `FeedMineDomain`, `FeedMineEditorial`, `Package.swift`
**Sem toolchain Swift** — nada compilado nem executado. Revisão estática de leitura, confrontada com INV/PD/B01–B06,
os achados de 2026-10-11 e a ordem da coordenação (KIRO.md §4/§5/§7).
**Modo:** só bloqueios de merge (P0/P1). Estilo não reportado.

## Veredito

**Nenhuma objeção P0.** Não encontrei bloqueio concreto para o merge nas quatro prioridades de Área A.

As quatro mecânicas que o PR introduz endereçam diretamente achados abertos da base remota e preservam os invariantes
que os revisores de 2026-10-11 marcaram como corretos:

- **FeedSession (prioridade 1):** o teto total da janela passa a valer nas duas direções (`boundedToTotalWindow`),
  resolvendo R2 (crescimento sem poda). Backward não marca visto nem faz checkpoint, âncora/ordem/identidade
  preservadas, e nenhum caminho consulta a rede.
- **Descoberta + catálogo PD-10 (prioridade 2):** instalação atômica por ponteiro, SHA-256 verificado **antes** de
  compilar e **antes** de ativar, rollback preserva o snapshot anterior, e o store runtime (dados pessoais) nunca é
  nomeado nesse caminho.
- **Migrações (prioridade 3):** uma única migração nova, aditiva, tabela-folha sem FK — sem risco a dados.
- **Rede e concorrência (prioridade 4):** `NetworkHostPolicy.isPubliclyRoutable` aplicado no host inicial **e** no
  host final após redirect em `FeedDiscoveryTransport`; teto de bytes imposto durante o streaming; grupos de task
  com largura limitada e deadline. Fecha a lacuna que E3-01 tinha em mídia, agora também para discovery.

Abaixo, as observações P1/P2 que valem como insumo, não como bloqueio, e os limites do que li.

---

## Prioridade 1 — FeedSession

### Confirmado correto (não retrabalhar)

1. **Teto total real (`items.count ≤ B+1+F`).** `boundedToTotalWindow` (`FeedSession.swift:170-176`) corta em volta
   da âncora: `first = max(0, anchorIndex - backwardCapacity)`, `last = min(count-1, anchorIndex + forwardCapacity)`.
   Aplicado em `admitForwardScroll` (`:146-149`), `admitBackwardScroll` (`:210-213`) e `admitPublishedGrowth`
   (`:245-248`). A janela resultante tem no máximo `backwardCapacity + 1 + forwardCapacity` itens, com a âncora
   dentro de `first...last` por construção. Resolve R2 (runway.md: `window.items` crescia sem poda de cabeça).

2. **Backward sem `markSeen`/checkpoint.** `admitBackwardScroll` (`:188-227`) não chama `markSeen` nem
   `saveCursor`; só `admitForwardScroll` herda o `markSeen` que `submitViewport` (`:76`) já fez sobre a âncora
   corrente. Em `FeedRunwayDriver.submitViewport` (`:143-150`) a ordem é `session.submitViewport` → depois
   `.backwardScroll`, logo os cards pré-anexados abaixo da cabeça **não** entram como vistos. Conforme a exigência.

3. **Gatilho backward exige a cabeça.** `admitsBackwardContent == (self == .backward)`
   (`FeedPresentationAdmission.swift:66-68`) e o guard `allowed = max(0, backwardCapacity - anchorIndex); guard
   allowed > 0` (`FeedSession.swift:196-197`): quando a âncora já está a `backwardCapacity` cards da cabeça, o
   prepend é no-op. O read é centrado na cabeça (`head.id`), `dropLast()` remove a própria cabeça e `.suffix(allowed)`
   mantém os cards mais próximos dela — o próximo passo para trás, não o fim da história.

4. **Identidade/ordem/âncora preservadas e deduplicação.** Backward e growth filtram por `admitted = Set(items.map(\.id))`
   antes de anexar; a âncora é relida de `current.presentation.window.anchor` e reusada no `FeedWindowSnapshot`; o
   guard `current.presentation.window.anchor == observation.anchor` (`:189`) impede que um gesto antigo reinstale uma
   posição que um gesto mais novo já deixou — igual ao forward.

5. **Proveniência.** `projectWindow` (`:289-298`) só emite nova posição de proveniência quando a projeção efetiva
   muda; janela idêntica retém a proveniência exata. Growth é no-op quando nada novo é publicado
   (`guard items.count < allowed`, `:242`; `guard !extensionCards.isEmpty`, `:252`).

6. **Sem rede no caminho.** As três admissões leem só de `publicationHistory.window(...)` (store local). Confere com
   a leitura offline que o PR declara (inventário: 17 visíveis → 9 ao reabrir → 8 mais antigos antes inalcançáveis).

### P1 — observação (não bloqueia)

- **`admitPublishedGrowth` depende de um chamador fora de Área A.** O caso é disparado em
  `AppComposition.swift:2142` (`admitPresentation(.publishedGrowth)`), fora deste escopo. Dentro de Área A o caso é
  autoconsistente e inerte sem chamador. Não é defeito; registro porque a prova de que "o primeiro open mostra o que
  o store já publicou" (R4/F05) vive num arquivo de UI/app que esta revisão não cobre — a validação de ponta a ponta
  precisa do B05 no Mac.

---

## Prioridade 2 — Descoberta e catálogo PD-10

### Confirmado correto

7. **Atomicidade da ativação.** `CatalogInstallation.install(manifest:catalogue:)`
   (`CatalogInstallation.swift`): bundled é verificado no lugar; fetched é copiado sob o fingerprint via
   `replace(file:with:)`/`write(data:to:)`, que escrevem num `.incoming` e fazem `replaceItemAt`/`moveItem` — o
   leitor nunca vê um arquivo meio-escrito. O ponteiro `active.json` só é escrito **depois** que manifesto e
   catálogo estão no lugar; o `previous.json` recebe o ponteiro anterior antes.

8. **Validação SHA antes de construir e antes de ativar.** `installOffer(...)` verifica cada OPML por tamanho **e**
   SHA-256 (`CatalogManifest.validate(_:payload:)`) **antes** do `build`, e verifica o artefato compilado
   (`validate(_:catalogue:)`) **antes** de ativar. SHA é streaming em blocos de 1 MiB (`sha256(ofFile:)`), nunca
   carrega o catálogo inteiro. Em `CatalogUpdater.install`, a ordem é download → verificação completa → compilar em
   staging → declarar o artefato medido → `installOffer` reverifica. Confere com PD-10 e a release criterion 1.

9. **Dados pessoais intocados.** O cabeçalho de `CatalogInstallation` e `CatalogUpdater` declara, e o código cumpre:
   nada em `CatalogInstallation`/`CatalogUpdater`/`CatalogManifest`/`CatalogSyncPolicy` abre, escreve ou nomeia
   `runtime.sqlite`. O diretório do catálogo é `<appDirectory>/catalogue`, "beside — never inside" o runtime DB. Uma
   fonte que o catálogo público remove continua do leitor em `reader_imported_sources` (separação PD-10).

10. **Rollback em falha.** Qualquer refusal retorna `.rejected` e deixa `active`/`previous` como estavam, com a razão
    no ledger (`reject(...)`). `rollback()` reaplica o `previous` e nunca apaga o snapshot que substitui. Downgrade de
    revisão (`revisionNotNewer`) e colisão (`revisionCollision`) são recusados, nunca aplicados.

11. **Discovery determinística e limitada.** `ReaderDiscoveryBuilder.page` lê em ordem de chave estável, com
    `examinedCapacity` + 1 para detectar exaustão; cursor valida profile/mediaKinds/revisão do arquivo
    (`cursorScopeMismatch`). `ReaderDiscoveryTraversal.advance` registra o snapshot antes de comprometer o cursor e
    **não suspende sob o lock** (`NSLock`), então lookup de conector e página não correm entre si. Discovery não
    revive fonte revogada: `guard target.state == .enabled` em `advanceDiscovery` e `skippingRevokedDiscovery`.

### P1 — observação (não bloqueia, insumo para a prova no Mac)

- **`ReaderDiscoveryTraversal` é `@unchecked Sendable` com estado mutável sob `NSLock`.** A disciplina está correta
  (toda leitura/escrita de `cursor`/`finished`/`discovered`/`pages` passa pelo lock, e `advance` não suspende
  dentro dele). O risco é de manutenção, não um defeito atual: qualquer caminho futuro que leia esses campos fora do
  lock reabre corrida. Não bloqueia; vale um comentário de invariante ou um teste de concorrência no Mac.

---

## Prioridade 3 — Migrações novas (RuntimeMigrations)

### Confirmado correto

12. **Migração única e aditiva, sem FK, sem transformação de dados.**
    `RuntimeMigrations.swift:514-527` registra `reader-playback-positions-v1`: `CREATE TABLE
    reader_playback_positions (card_id TEXT PRIMARY KEY, position REAL NOT NULL, duration REAL, updated_at REAL
    NOT NULL, CHECK (position >= 0))`. Não há `foreign key`, não há `INSERT SELECT`/`DROP`/`RENAME`, não toca tabela
    existente. Nenhum dado preexistente é lido ou movido — a origem (V1 `UserDefaults`) não é migrada, só a tabela é
    criada. Não reabre o risco A03 (reconstrução de tabela com FK), que K-07 já tinha retirado como não-defeito.
    `PlaybackPositionStore` usa upsert `ON CONFLICT(card_id)` e `max(0, position)`, coerente com o `CHECK`.

---

## Prioridade 4 — Segurança de rede e concorrência

### Confirmado correto

13. **Host policy no edge de discovery, ida e redirect.** `URLSessionFeedDiscoveryTransport.send`
    (`FeedDiscoveryTransport.swift`): `guard NetworkHostPolicy.isPubliclyRoutable(host)` no host inicial **e**
    `guard !isPubliclyRoutable(finalHost)` no `http.url?.host` após a resposta — redirect para host privado é
    recusado e **o corpo nunca é lido**. Fecha, para discovery, o mesmo buraco que E3-01 apontou em syndication.
    `SyndicationHTTP.swift` não foi tocado neste PR (não está no diff), então a correção K-01 já mergeada em
    `main` continua valendo; não há regressão aqui.

14. **Teto de bytes imposto durante o streaming.** `FeedDiscoveryTransport.send` recusa por `Content-Length` quando
    anunciado e, independentemente disso, aborta no laço `for try await chunk` quando `body.count > byteCeiling`
    (`tooLarge`) — nunca trunca depois do corpo já estar em memória. `FeedLinkResolver.Budget` carrega os tetos de
    V1 (page 256 KB, probe 64 KB, channel 512 KB, lookup 1 MB) e deadlines.

15. **Concorrência limitada e com deadline.** `FeedLinkResolver.resolveAll` mantém no máximo
    `resolutionConcurrency` em voo; `firstServingFeed` usa um filho de deadline em `withTaskGroup`, `cancelAll()` no
    primeiro match ou no deadline, e encerra quando todos os candidatos responderam (não paga o deadline à toa).
    Autorização de origem nunca deriva de endpoint de catálogo/OPML (`SyndicationAcquisitionSnapshot` cabeçalho e
    `ReaderSourceIdentity.entry` recusa não-http, sem host, ou com userinfo).

16. **Readiness antes do ranking (fecha R1/E3-02 e evita a armadilha E3-03).**
    `SelectionEngine.select` filtra `readyEligible` **antes** de ordenar/alternar (`SelectionEngine.swift:112-127`),
    então uma história ainda em preparação de mídia "não consome cota de fonte, separador ou posição" — a adjacência
    de SourceID (PD-4) não é reaberta. `SelectionReadinessSnapshot.init?` exige que o índice de prontidão seja
    subconjunto exato das revisões pedidas; `readinessCoverageMismatch` barra divergência. `FeedRunwayDriver` passa
    o **mesmo** índice (`MediaReadiness`) à preparação e à prontidão (F06-A), que é a correção que impede o card
    text-only permanente.

### P2 — observação (não bloqueia)

- **`FeedLinkResolver` resolve endereços relativos/alternate em `feedURL` que só são checados contra host policy
  no fetch posterior.** `declaredFeeds`/`discoverFeeds` montam `feedURL` a partir de `<link rel=alternate>` e dos
  common paths; esses passam pelo `transport` (que checa host) durante o probe, e o endereço adotado será buscado
  depois por syndication, que tem a própria política (K-01). Não há bypass. Registro só porque a garantia depende de
  o fetch de produção manter `publicOnly` — já verificado em `main` por K-01, mas é a junção que fecha o ciclo e ela
  está fora deste diff.

---

## O que não li / limites

- **Sem compilação nem execução** (sem toolchain Swift nesta máquina). Tudo acima é leitura estática; invariantes de
  runtime (B01–B06), ordenação real e comportamento offline precisam do Mac. Não declaro PASS de nenhum gate.
- **Fora do escopo de Área A, não lidos aqui:** `FeedMineApp/*` (incl. `AppComposition.swift:2142`, o chamador de
  `publishedGrowth`, e a ligação da leitura local), `Sources/FeedMineUI/*` (incl. `FeedScreen.swift`, que hospeda o
  slot e o motion forward/backward), `Sources/FeedMineMedia/*`, `scripts/*`, `bench/*`, `docs/*` e todos os `Tests/*`.
  A prova de ponta a ponta de backward/growth (B05 return/reopen) vive nesses alvos.
- **`AcquisitionCoordinator.swift`:** o `--stat` do diff atribuiu ~64 linhas, mas `git diff` de conteúdo veio vazio
  nas duas tentativas — tratei como sem mudança efetiva de lógica (provável contexto/rename). Se houver mudança real,
  não a avaliei.
- **Arquivos de Área A lidos só por diff (não li o corpo inteiro atual):** `CatalogUpdateChannel.swift`,
  `CatalogCompiler.swift`, `CatalogOPMLScan.swift`, `CatalogValues.swift`, `FeedLinkInput.swift`,
  `ReaderDiscoveryTraversal`→`AcquisitionTargetAuthority`, `LegacyCatalogReader` (métodos `sources`/`node`/
  `sourceKeys`/`metadata`), `MediaPrefetcher`, `RunwayAcquisitionCycle`, `LocalProductionSlice`,
  `InitialProductionSlice`, `PublicationCoordinator`, `ReaderExport`, `ReaderPlaybackPositions*`,
  `SourceManagementCoordinator`, `OPMLDocument`, `FeedRecipeDefinition`, `ReaderSettings`, `ReaderFilter`,
  `ReaderLibraryStore`, `content_filter_templates.json`. Li o diff de cada um que estava no stat; onde a mudança era
  pequena/aditiva não abri o arquivo atual completo.
- **`NetworkHostPolicy.isPubliclyRoutable`** não foi re-lido aqui (não está no diff); confio na verificação de
  2026-10-11 que marcou IP decimal/octal/hex e IPv6 mapeado como corretos. Rebinding de DNS continua fora de alcance,
  como já documentado.
- **Confronto com a árvore local do OMP:** não tenho acesso a ela; comparei contra `origin/main`. Se o OMP tiver
  tocado algum destes arquivos localmente, o merge precisa reconfrontar antes de integrar.
