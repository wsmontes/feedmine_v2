# K-06 — Revisão estática do pacote da rodada 10 (FeedMine V2, Swift/iOS)

**Escopo:** revisão estática, somente leitura, dos hunks que o inventário
(`docs/reviews/2026-10-11-round10-changes-inventory.md`) atribui à rodada 10, no patch
`round10-code-diff.patch`. Sem toolchain Swift: nada foi compilado nem executado. Nenhum arquivo do
repositório foi modificado.

**Base de contexto:** `main` do worktree `feedmine_v2-kiro` (63 commits atrás de `origin/main`),
`PRODUCT_INVARIANTS.md`, `PRODUCT_DECISIONS_2026-10-09.md`, `DISCOVERY_ACCEPTANCE_BENCHMARK.md`,
`coordination/KIRO.md` §6.

**Convenção:** cada achado traz `[confirmado por leitura]` ou `[hipótese]`. "Linha do patch" = linha
dentro de `round10-code-diff.patch`; "linha do arquivo" quando o hunk a declara.

---

## Limitação estrutural desta revisão (ler antes dos achados)

Os pontos obrigatórios **2 e 3** da seção 6 do KIRO.md perguntam sobre o **slot escondido dentro do
`LazyVStack(spacing:)`** e sobre o slot virar **âncora/`isLast`**. A resposta honesta é que **não
consigo separar nem confirmar isso pelo pacote entregue**, porque o arquivo que desenha o slot **não
está no patch**:

- `FeedMineApp.swift` (rodada 10) passa um closure novo `editorial:` para a tela do feed:
  `editorial: { card, index, previous in editorialInvitation(...) }` (patch ~2807–2815) e
  `.task(id: association.store.state.presentation?.window) { recordWindowFacts(of: association) }`.
- Mas `Sources/FeedMineUI/FeedScreen.swift` em `main` **não tem** parâmetro `editorial:`,
  `onTryAgain:` nem `onAdjustInterests:` em `FeedScreen.init` (confirmado por leitura: `FeedScreen.swift`
  linhas 24–34 só aceitam `store/appearance/statusChip/lens/hasSources/onChooseSources`), e o
  `LazyVStack` em `FeedScreen.swift:70` e `:106` só renderiza `FeedItemView(card:)` dentro de
  `ForEach(presentation.window.items)` — **não há slot editorial**.
- Logo existe uma versão modificada de `FeedScreen.swift` (ou de `ReaderShell`) **na árvore da rodada
  10 que não foi incluída no patch nem nomeada no inventário**. É nela que vivem: (a) onde o slot entra
  no `LazyVStack`; (b) como o "nada" é desenhado em relação ao `spacing: Spacing.section`; (c) se o
  slot participa de `capture.observeCard(... isLast:)` e de `anchor.cardID`.

**Consequência:** os achados K06-2 e K06-3 abaixo são **hipóteses não confirmáveis com este pacote** e
exigem o arquivo que falta. O inventário diz que os arquivos novos da UI são
`EditorialInvitationCadence.swift`, `FeedEditorialInvitationView.swift` e
`ReaderDiscoveryPreferencesView.swift` — nenhum deles é a tela do feed que hospeda o slot.

---

## Achados

### K06-1 — [confirmado por leitura] P1 — `recordWindowFacts` dispara aquisição de catálogo e leitura de banco no corpo da view (`.task` sobre `window`)
- **Arquivo:** `FeedMineApp.swift`, patch ~2812–2815 (`.task(id: ...window) { recordWindowFacts(of:) }`)
  e ~3080–3089 (`recordWindowFacts(of:)`); encadeia em `AppComposition.editorialSubject(for:in:)`
  (patch ~1996–2004) que chama, por fonte, `discoverySubjects[...]` — porém o caminho de montagem de
  `discoverySubjects` (`subjects(in:catalogURL:)`, patch ~2080–2110) abre
  `LegacyCatalogReader(catalogURL:)` e `reader.node(key:)`.
- **Trecho:**
  ```swift
  let withSubject = resolved.filter { composition.editorialSubject(for: $0, in: association) != nil }.count
  ```
- **Por que é defeito:** `editorialSubject` em si só lê o dicionário `discoverySubjects` já computado
  (barato). Isso está **correto**. O risco é que `recordWindowFacts` roda a **cada mudança de
  `window`** (inclusive durante o burst de `startGrowthFollowUp`, que muda a janela várias vezes em
  <1 s). Se cada chamada reitera o `filter` sobre todas as fontes resolvidas é O(cards) por mudança de
  janela — aceitável — **desde que** `discoverySubjects` já esteja populado. Não vi defeito de SQL na
  view: a leitura de catálogo é feita fora do render (em `discoveryFeeds`, detached). INV-02 é
  respeitado. **Rebaixo este item de "UI faz SQL" para P1 de custo**: confirmar que
  `.task(id: window)` não re-executa trabalho pesado em cada passo do `growthFollowUp`.
- **Cenário:** B03 (30 min). A cada admissão de crescimento a janela muda; `recordWindowFacts` roda.
- **Correção mínima:** nenhuma de corretude; se o profiling no iPhone mostrar custo, coalescer por
  `window.anchor`/contagem em vez de identidade de `window`.
- **Teste que provaria:** instrumentar contagem de chamadas de `recordWindowFacts` numa corrida B03 e
  afirmar que é O(mudanças editoriais), não O(bursts).

### K06-2 — [hipótese — não confirmável com este pacote] P1 — slot escondido pode receber `Spacing.section` dos dois lados dentro do `LazyVStack`
- **Arquivo:** desenho do slot **ausente do patch**; contexto em `FeedScreen.swift:70`
  (`LazyVStack(alignment: .leading, spacing: FeedDesignTokens.Spacing.section)`) e no `presented(...)`
  de `FeedMineApp.swift` (patch ~2900–2915) que, escondido, retorna
  `AnyView(Color.clear.frame(height: cadence.slotHeight(...) ?? 0))`.
- **Trecho (parte visível):**
  ```swift
  return AnyView(Color.clear.frame(height: cadence.slotHeight(of: card, isCompact: isCompact) ?? 0))
  ```
- **Por que é defeito potencial (B04 — "o feed apresentado é sagrado"):** se o slot é **uma linha
  própria do `ForEach`/`LazyVStack`**, o `spacing: Spacing.section` é aplicado **antes e depois** dessa
  linha. Um slot escondido com altura exata do bloco **ainda insere 1× `Spacing.section` de vão
  adicional** entre o card anterior e o próximo — isto é, esconder não devolve exatamente a geometria
  de "sem bloco", e o leitor vê um vão a mais. A medição 189,08→189,08 / 154,08→154,08 pt do OMP prova
  que **o card âncora não se moveu**, não que o vão não existe (a âncora é o topo; o vão fica *abaixo*
  dela). Se, ao contrário, o bloco é um **modifier/overlay dentro da célula do card** (não uma linha do
  stack), não há vão duplo — e é por isso que preciso do arquivo.
- **Cenário:** fonte Grande, bloco oferecido e depois escondido; medir a distância
  `card_anterior.maxY → card_seguinte.minY` com e sem o slot.
- **Correção mínima (se confirmado):** o bloco (oferecido **e** escondido) deve ser renderizado
  **dentro da célula do card host**, não como item irmão no `LazyVStack`; ou, se for item do stack,
  colapsar também o `spacing` do slot escondido (p.ex. agrupar card+bloco numa só linha). Não desenhar
  "nada" com `Color.clear.frame(height: 0)` como linha do stack quando `slotHeight == nil`.
- **Teste que provaria:** UITest medindo `next.minY - prev.maxY` em três estados (sem oferta /
  oferta visível / oferta escondida); o estado escondido deve igualar o "sem oferta", não "oferta +
  spacing". O `EditorialOfferBudgetUITests.assertNothingMoved` **não** cobre isso: ele compara
  `minY` de cards por identidade entre antes/depois do *hide*, mas o vão extra existe tanto antes
  quanto depois do hide (o bloco visível já o tinha), então o delta é 0 e o teste passa mesmo com vão
  duplo permanente.

### K06-3 — [hipótese — não confirmável com este pacote] P1 — slot (oferta ou escondido) como âncora de viewport ou gatilho de `isLast`
- **Arquivo:** captura em `FeedScreen.swift:76–96` (`observeCard(proof, isLast: ...last?.id == proof.cardID)`)
  e `NativeFeedViewport.scrollPosition(id:)` (`FeedScreen.swift:~305`); desenho do slot **ausente**.
- **Por que é defeito potencial (B05 return/reopen, 3R9/3R10):** a captura só emite viewport para
  `proof.cardID` que pertença a `window.items` (`FeedScreen.swift:84`), e `window.items` são
  `PublicationCard`s. **Se** o slot editorial for inserido como um item sintético de `window.items` (ou
  carregar um `cardID` que não é de card publicado), ele poderia: (a) virar `anchor.cardID` para
  restaurar posição (B05 `return-preserves-anchor`/`reopen-keeps-saved`), e um slot de altura 0 seria
  âncora degenerada; (b) disparar `isLast` cedo se fosse o último item. **Se** o slot for puramente
  visual (dentro da célula do card, fora de `window.items`), o problema não existe — e o código de
  `editorialExposure.expose(observation.anchor.cardID)` (AppComposition, patch ~2193–2196) assume que
  a âncora é sempre um card real (o `wasExposed(card.id)` usa `PresentationCard.id`). O design
  declarado ("o bloco fica *depois* da célula do card") sugere que o slot **não** é item de
  `window.items`, o que seria correto — mas não posso confirmar sem o arquivo.
- **Cenário:** B05 — responder/esconder perto do fim do feed; reabrir; a âncora restaurada deve ser um
  card real, nunca o slot.
- **Correção mínima (se confirmado):** manter o slot **fora** de `window.items` e de
  `capture.observeCard`; `anchor.cardID` nunca pode ser a identidade de um bloco editorial.
- **Teste que provaria:** afirmar que, com um bloco visível como último elemento, `isLast` só é
  verdadeiro para o último `PublicationCardID`, e que o checkpoint de B05 nunca grava a identidade do
  slot.

### K06-4 — [confirmado por leitura] P2 (comportamento declarado, não bug) — orçamento por `cards_traversed` é high-water por identidade; relaunch zera; A→B→A acumula
- **Arquivo:** `EditorialInvitationCadence.swift` (`EditorialExposureLedger`, patch ~26–48) e
  `AppComposition` (`@ObservationIgnored let editorialExposure = EditorialExposureLedger()`, patch
  ~1067; `editorialExposure.expose(observation.anchor.cardID)` em `viewport`, patch ~2193–2196).
- **Trecho:**
  ```swift
  private var seen: Set<PublicationCardID> = []
  public var count: Int { seen.count }
  public func expose(_ cardID: PublicationCardID) { seen.insert(cardID) }
  ```
- **Comportamento confirmado:**
  1. **High-water por exposição:** `count` é cardinalidade de um `Set` de identidades. Voltar o scroll
     e repassar os mesmos cards **não** reconta — correto, atende "cards realmente expostos".
  2. **A→B→A e rebuild interno:** o ledger é **único por `AppComposition`** (app-scoped) e **nunca é
     resetado**; é passado por referência à `FeedAssociation` (`let editorialExposure`, patch ~1395).
     Responder reconstrói a sessão mas **não** zera o teto: o `Set` sobrevive à troca de associação.
     As sessões de orçamento (`sessions: [ContextKey: Session]`) são por `ContextKey` e `beginSession`
     é no-op quando `key == sessionKey` (patch ~155–160), então voltar a um contexto **retoma** a
     sessão (teto gasto continua gasto). **Correto** quanto ao exigido pela seção 6 (A→B→A/rebuild não
     zeram o teto).
  3. **Relaunch:** novo processo → novo `AppComposition` → novo `EditorialExposureLedger` →
     `count` volta a 0 e `sessions` vazio. O teto por sessão **reinicia** no relaunch. O KIRO.md
     registra explicitamente que isso depende da **definição de sessão do PO** — portanto **apenas
     relato**, não classifico como defeito.
- **Por que não é bug:** a coordenação (Codex 20:32) diz que persistência de teto no relaunch não é
  critério novo sem decisão do PO. Correto por construção para A→B→A e rebuild; relaunch é decisão
  pendente de produto.
- **Teste que provaria:** unit em `EditorialInvitationCadence` + `EditorialExposureLedger` com
  sequência expose(A),expose(B),expose(A) → count==2; e `beginSession(X)`, gastar cap, `beginSession(Y)`,
  `beginSession(X)` → cap de X continua gasto. (O relaunch exigiria persistir o ledger — não existe
  migração/persistência dele; ver K06-7.)

### K06-5 — [hipótese — parcialmente confirmável] P1 — responder entre A e B e B05 (return-preserves-anchor / reopen-keeps-saved)
- **Arquivo:** `AppComposition.voteOnTopic` (patch ~2037–2060) **não** chama `replaceSession` (correto,
  foi o que movia o leitor); `refreshFromTheReader` (patch ~1660–1672) reconstrói **apenas** se o
  perfil armazenado mudou; `replaceSession` agora é loop com `pendingRebuild` (patch ~1676–1700).
- **Por que pode afetar B05:** o ponto 5 pede: responder em A, ir a B, voltar a A — B05
  `return-preserves-anchor` e `reopen-keeps-saved` devem continuar verdadeiros **depois** de uma
  resposta. Pela leitura:
  - Responder em A **não** reconstrói A (`voteOnTopic` só persiste + marca `pendingRebuild` se já
    houver rebuild em curso). Logo a edição/âncora de A não se mexe no ato de responder. **[confirmado]**
  - Ir a B e **voltar a A** passa por `selectContext`/`activateSavedPreset`, que chamam `association(...)`
    e, no fim, `if pendingRebuild { replaceSession() }` (patch ~473–480, ~565–572). Voltar a A
    reconstrói A a partir do checkpoint. O comentário do próprio código em
    `testAnsweringInTheFeedChangesDiscoveryWithoutMovingTheReader` reconhece que o checkpoint "carries
    no offset inside the card" (patch ~) — mas isso é no caminho de responder, não no de voltar.
    **Não há no pacote um teste B05 com uma resposta entre A e B**; o UITest de orçamento não cobre
    A→B→A. **[hipótese]**
- **Cenário:** driver B05 com `vote` entre A e B; afirmar que ao voltar a A a âncora/edição são as
  mesmas e os salvos sobrevivem.
- **Correção mínima:** nenhuma proposta sem reproduzir; se a volta a A re-ancorar, o checkpoint
  precisa carregar o offset dentro do card (mesma causa-raiz já descrita no código).
- **Teste que provaria:** estender o oráculo/driver B05 com uma resposta entre A e B e checar
  `b05-return-preserves-anchor` e `reopen-keeps-saved` ainda `true`.

### K06-6 — [confirmado por leitura] P1 — mudança do oráculo B04/B03/B05: "não medível" nunca vira PASS, mas pode mascarar gate incompleto como "quase lá"
- **Arquivo:** `bench/oracle.py` — `gate_b04` (patch ~, linhas do arquivo ~360–400), `gate_b03`
  (candidate readiness, ~), `gate_b05` (~), e `verdict()` (`NOT_RUN` se algum `pass is None`).
- **Trecho (B04):**
  ```python
  unstable = sorted(name for name, value in stability.items() if value == "false")
  unmeasurable = sorted(name for name, value in stability.items() if value not in ("true","false"))
  ...
  "pass": (not unstable) if stability and not unmeasurable else None,
  ```
- **Análise da pergunta da seção 6 ("estável/instável/não medível pode transformar falha em PASS?"):**
  - **Não transforma FAIL em PASS.** `verdict()` retorna `FAIL` se *qualquer* clause é `False`; só
    retorna `PASS` se **nenhuma** é `False` **e nenhuma** é `None`. Um `not-measurable` força
    `pass=None` → `NOT_RUN`, nunca PASS. `unstable` (`value=="false"`) força `pass=False` → FAIL.
    **[confirmado]**
  - **Risco real = gate incompleto apresentado como aprovado por quem lê rápido.** Em `gate_b04`, se
    **todas** as medidas forem `not-measurable`, `stability` é não vazio, `unmeasurable` é não vazio →
    `pass=None` → NOT_RUN. Correto. Mas a clause 1 ("o protocolo foi caminhado") retorna
    `True if facts else None`: basta **existirem** chaves `b04-*` no registro de fases para a clause 1
    passar, mesmo que todas as medidas de estabilidade sejam não medíveis. Então o relatório mostra
    "protocolo caminhado: PASS" + "estabilidade: NOT_RUN" → **verdict NOT_RUN** (correto), mas o
    primeiro `pass:true` pode ser lido como "B04 quase passou". É **gate incompleto**, não FAIL
    mascarado — consistente com o que o inventário declara.
  - **B03 readiness (a regressão citada no próprio arquivo):** o comentário admite que a versão
    anterior retornava PASS com 871 candidatos e rótulos 0/0/0 por ler a chave errada. A correção
    (`candidates` lê `fields.readiness`) e a regra ("sem candidato → None; com candidato, todos
    precisam de rótulo senão FAIL") estão **corretas por leitura** e fecham a brecha de "PASS medindo
    nada". **[confirmado]**
- **Por que ainda vale registrar (B04 do benchmark):** o `DISCOVERY_ACCEPTANCE_BENCHMARK.md` §1 proíbe
  o agente de reclassificar BLOCKED/NOT_RUN como PASS. O oráculo respeita isso. A mudança de régua
  autorizada (três resultados em vez de dois) **enfraquece a cobertura** (um fato não medível deixa de
  reprovar), mas **não** afrouxa o critério de PASS. Isso é exatamente o que o inventário diz
  ("torna o gate incompleto, nunca PASS"). **Conclusão: a mudança não transforma falha em PASS; torna o
  gate incompleto quando a medição não pode ser tomada.**
- **Teste que provaria:** rodar `oracle.py --gate B04` com um `.phases` só de `b04-*:not-measurable`
  → verdict NOT_RUN; com um `b04-*:false` → FAIL; com todos `true` → PASS. Idem B03 com
  candidate sem `readiness` → clause FAIL.

### K06-7 — [confirmado por leitura] P2 — estado persistido sem migração: `editorialTipsHidden` em `ReaderSettings` (sem evidência de migração no pacote)
- **Arquivo:** `ReaderDiscoveryPreferencesView.swift` grava `store.update { $0.editorialTipsHidden = ... }`
  (patch ~500–510); `FeedMineApp.swift` lê `settingsStore?.settings.editorialTipsHidden` em `onChange`
  (patch ~505–511); `AppComposition.editorialTipsHidden`/`setEditorialTipsHidden` (patch ~2111–2120).
- **Por que é risco (B05 "zero perda silenciosa de estado"):** `editorialTipsHidden` é um campo novo de
  `ReaderSettings`, persistido como `settings_json` (o oráculo lê `reader_preferences.settings_json`).
  Se `ReaderSettings` for `Codable` com default para chave ausente, uma base V1/V2 anterior decodifica
  sem o campo (default `false`) — seguro. **Mas o pacote não inclui `ReaderSettings` nem a migração**,
  então não posso confirmar que o decode tolera a chave ausente (se for `decodeIfPresent`/default, ok;
  se for `decode` obrigatório, uma base antiga quebra o load → `hasSelectedSources`/startup).
- **Cenário:** atualizar sobre uma base com `settings_json` sem `editorialTipsHidden` /
  `discoveryProfile.topicPreferences` expandido.
- **Correção mínima:** garantir `decodeIfPresent` + default em `ReaderSettings` para os campos novos
  (`editorialTipsHidden`, chaves de `discoveryProfile`), ou migração aditiva.
- **Teste que provaria:** decodificar um `settings_json` legado (sem os campos novos) e afirmar load
  bem-sucedido com defaults; é um teste de Persistence, fora deste pacote.

### K06-8 — [REBAIXADO pelo Kiro após conferir o corpo: hipótese P2] — corrida `@MainActor`/`Task` em `voteOnTopic` + `inFeedAnswers` (estado otimista revertido fora de ordem)
- **Arquivo:** `FeedMineApp.invitation(...)` closures `onVote`/`onUndo` (patch ~3040–3065).
- **Trecho:**
  ```swift
  onVote: { level in
      inFeedAnswers[subject.nodeKey] = level
      cadence.answered(subject: subject.nodeKey)
      Task {
          if await composition.voteOnTopic(nodeKey: subject.nodeKey, level: level) == false {
              inFeedAnswers[subject.nodeKey] = nil
          }
      }
  },
  onUndo: {
      inFeedAnswers[subject.nodeKey] = nil
      Task { if await composition.voteOnTopic(..., level: .neutral) == false { inFeedAnswers[...] = nil } }
  }
  ```
- **Por que é defeito potencial (corrida @MainActor):** `inFeedAnswers` é `@State` escrito no corpo das
  closures e dentro de `Task`s não ordenadas. Toque rápido **votar → desfazer** cria dois `Task`s
  concorrentes sobre `voteOnTopic` (ambos `@MainActor`, serializados no actor, mas a **ordem de
  retomada** não é garantida). Sequência possível: `onVote` grava `.more` otimista + Task V; `onUndo`
  grava `nil` otimista + Task U (persiste `.neutral`→remove). Se V retomar **depois** de U, V persiste
  `.more` por último → `inFeedAnswers` mostra `nil` (otimista do undo) mas o banco fica `.more`:
  divergência tela×banco, que é exatamente o que a "finding 4" do próprio código quis evitar. O
  tratamento de falha só reverte em `== false`; não há reconciliação quando ambos `== true` fora de
  ordem.
- **Cenário:** responder e desfazer em sequência rápida (o UITest faz tap no bloco e depois no undo com
  `settledTap`, o que mitiga, mas não prova ausência de corrida sob toque humano rápido).
- **Correção mínima:** serializar por assunto (um `Task` por `nodeKey`, cancelando o anterior) ou
  reconciliar `inFeedAnswers[nodeKey]` com o valor realmente persistido ao fim de cada `Task` (ler de
  volta `declaredLevel(forNode:)` e espelhar), em vez de só reverter em falha.
- **Teste que provaria:** teste de composição disparando `voteOnTopic(.more)` e `voteOnTopic(.neutral)`
  em ordem invertida de retomada e afirmando que `declaredLevel` e `inFeedAnswers` convergem.

> **Nota do Kiro (conferido no patch):** `voteOnTopic` não tem nenhum `await` antes de `preferences.setSettings`: `load`, mutação e persistência são síncronas no MainActor. Cada `Task` roda até o fim sem suspender, então V e U não se intercalam e a ordem de persistência segue a ordem de enfileiramento no main actor. Com o código atual a divergência tela×banco **não** ocorre. Vira risco real se `voteOnTopic` ganhar um ponto de suspensão antes de persistir. Nesse caso a correção mínima é serializar por `subject` (última intenção vence).

### K06-9 — [confirmado por leitura] P2 — `pendingRebuild` só é reparado quando há rebuild em curso; resposta fora de rebuild não agenda nada (correto), mas `voteOnTopic` depende de ordem com `replaceSession`
- **Arquivo:** `voteOnTopic` (`if replacingSession { pendingRebuild = true }`, patch ~2058) e
  `replaceSession` (`guard !replacingSession else { pendingRebuild = true; return }`, patch ~1676) +
  loop `repeat { pendingRebuild = false; ... } while pendingRebuild` (patch ~1690–1700).
- **Por que registrar (hipótese contida):** o laço de `replaceSession` lê o perfil **de novo** a cada
  volta via `association(contextKey:)` → `discoveryProfile(for:)` (lê `preferences`). Como `voteOnTopic`
  persiste **antes** de setar `pendingRebuild`, a volta seguinte do laço vê o valor novo. **Correto por
  leitura.** O risco residual: `voteOnTopic` grava e seta `pendingRebuild=true` **entre** o
  `pendingRebuild=false` e o `association(...)` da volta corrente — nesse caso a volta corrente **já**
  pega o valor novo (persistido) e o `pendingRebuild=true` força **mais uma** volta redundante (relê o
  mesmo perfil, reconstrói de novo). Não é incorreto, mas é **uma reconstrução extra** → custo e, em
  B04/B05, uma troca de associação a mais do que o necessário.
- **Correção mínima:** na volta do laço, comparar o perfil consumido com o atual e sair se igual
  (`refreshFromTheReader` já faz esse tipo de comparação; `replaceSession` não).
- **Teste que provaria:** contar reconstruções quando duas respostas chegam durante um rebuild; esperar
  no máximo 2, não 3.

### K06-10 — [confirmado por leitura] P2 — `.environment(\.locale, CatalogLanguageNaming.interfaceLocale)` aplicado no topo pode divergir do idioma usado pelos `accessibilityIdentifier`/labels dos testes
- **Arquivo:** `FeedMineApp.swift` (patch ~513–516).
- **Por que registrar:** o `EditorialOfferBudgetUITests` já contorna isso aceitando PT/EN
  (`labelled("Grande","Large")`, `labelled("FeedMine sugere","FeedMine suggests")`). Isso é **correto**
  e evidencia que o idioma de interface é resolvido do device, não fixo. Sem defeito; registro como
  **verificado correto** (o teste não depende de copy, usa `accessibilityIdentifier`). Mencionado só
  porque toca "estado persistido/locale" — não há migração envolvida.

---

## Verificado como correto (não retrabalhar)

- **`EditorialExposureLedger` high-water por identidade** (`Set<PublicationCardID>`): voltar o scroll
  não infla a contagem. **[confirmado]** (K06-4.1)
- **`voteOnTopic` não chama mais `replaceSession`**: responder não reconstrói a sessão do contexto
  atual; a edição/âncora não é retirada no ato de responder. Coberto por
  `testAnsweringInTheFeedChangesDiscoveryWithoutMovingTheReader` (exige `after === association` e que a
  janela antiga seja prefixo da nova). **[confirmado]**
- **`refreshFromTheReader` reconstrói só se o perfil mudou**; senão `retryNow()` (sem troca de sessão).
  **[confirmado]**
- **`editorialSubject(for:in:)` só oferece para fontes descobertas, nunca para as escolhidas pelo
  leitor** (`!association.feeds.contains` + `association.discovery.contains`). Fecha a "finding 2".
  **[confirmado]** — teste `testAnInvitationIsOnlyOfferedForDiscoveredSources`.
- **`subjects(in:)` cobre por entrada (`entries.prefix(ceiling)`), não por fatia de chaves ordenadas**:
  evita o viés que escondia um perfil inteiro. **[confirmado]**
- **Oráculo: `not-measurable` nunca é PASS; `verdict()` é FAIL se qualquer clause `False`, NOT_RUN se
  qualquer `None`.** A mudança de régua não converte falha em PASS. **[confirmado]** (K06-6)
- **Oráculo B03 readiness lê `fields.readiness` e exige rótulo em todo candidato examinado** (corrige a
  regressão de "PASS medindo nada"). **[confirmado]**
- **`discoveryFeeds`/`subjects` rodam detached (`Task.detached(priority:.userInitiated)`), fora do
  main actor** — INV-02/custo de abrir o catálogo de 118 MB fora do render. **[confirmado]**
- **`editorialExposure.expose` é gravado em `viewport(_:)` antes do handoff** (a exposição é fato do
  leitor, independente do lado de publicação). **[confirmado]**
- **pbxproj:** `EditorialOfferBudgetUITests` e `DiscoveryBenchmarkTests` entram no alvo
  `FeedMineUITests` (fase de fontes `…036`), coerente com uso de `XCUIApplication`; os arquivos de
  unit (`AddFeed/ContentFilter/Playback/CatalogueUpdateAccept`) entram no alvo `FeedMineAppTests`
  (fase `…02E`). Quatro entradas coordenadas por arquivo, como o inventário descreve. **[confirmado]**
- **Acessibilidade do bloco:** `FeedEditorialInvitationView` não declara elemento de acessibilidade
  próprio (os botões são os elementos); o esconder desenha `Color.clear` (nada), não
  `accessibilityHidden`. Coerente com a lição medida ("accessibilityHidden deixava 2 títulos na
  árvore"). **[confirmado por leitura do view; o comportamento em árvore depende da tela ausente]**

---

## Resumo (5 linhas)

1. **Pontos obrigatórios 2 e 3 (slot no `LazyVStack`, slot como âncora/`isLast`) não são confirmáveis**:
   a tela que hospeda o slot (`FeedScreen`/`ReaderShell` modificado) **não está no patch** — K06-2 e
   K06-3 ficam como hipóteses e exigem esse arquivo.
2. **Ponto 4 (orçamento por `cards_traversed`)**: confirmado high-water por identidade; A→B→A e rebuild
   interno **não** zeram o teto; **relaunch zera** (decisão de sessão do PO — apenas relatado).
3. **Ponto 5 (resposta entre A e B / B05)**: responder não reconstrói a sessão atual (confirmado), mas
   **não há teste A→B→A com resposta** no pacote; B05 return/reopen com voto permanece hipótese.
4. **Ponto do oráculo**: a mudança "estável/instável/não medível" **não transforma FAIL em PASS** —
   `not-measurable` força NOT_RUN; o efeito real é **gate incompleto**, como declarado.
5. **Novos achados P1 de código**: corrida votar/desfazer sobre `inFeedAnswers`+`Task` (K06-8) e custo
   de `recordWindowFacts` em `.task(id: window)` durante bursts (K06-1); P2: `editorialTipsHidden` sem
   migração confirmável (K06-7) e reconstrução extra no laço de `replaceSession` (K06-9).
