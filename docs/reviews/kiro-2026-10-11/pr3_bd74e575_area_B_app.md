# Revisão K-04 final — PR #3 FeedMine V2 — ÁREA B (app e UI)

**Diff:** `origin/main...bd74e575` em `C:\workspace\feedmine_v2-int` (detached em `bd74e575`; `origin/main` = `71531c7`).
**Escopo lido:** `FeedMineApp/FeedMineApp/*.swift`, `FeedMineApp.xcodeproj/project.pbxproj`, `Sources/FeedMineUI/**`.
**Toolchain Swift:** ausente — nada compilado nem executado. Achados são leitura estática.

## Veredito

**Nenhum bloqueio P0/P1 para o merge na Área B.** As cinco prioridades do pedido foram verificadas e estão
corretas ou já resolvidas nesta árvore. Há **1 achado P2** (lacuna de instrumentação, não de produto) e **2
observações informativas**. Nada aqui, por si, deve impedir o merge do PR #3.

---

## Prioridade (1) — Autorização de origem DEBUG em `FeedAssociation.init`

**Correto. Sem objeção.** `AppComposition.swift:1823-1870`.

- **Vem só do que a execução declara:** a origem é lida de `FEEDMINE_BENCH_TRANSPORT_ORIGIN` (env do launch), **não**
  de `registrations`/catálogo. O comentário `:1808-1816` registra explicitamente a correção do arquiteto ("deriving
  the set from `registrations` means deriving it from the catalogue, which is untrusted input"). O runner confirma a
  mesma variável: `bench/run.sh:59-70` exporta `FEEDMINE_BENCH_TRANSPORT_ORIGIN` e aborta sem ela.
- **Recusa, não sanitiza:** `AppComposition.swift:1845-1853` — `compactMap` que rejeita o endpoint inteiro se tiver
  `path` não vazio, `query`, `fragment`, `user`/`password`, sem esquema http(s), sem host ou **sem porta**
  (`parts.port != nil`). Não há limpeza de componente: valor que não é origem exata é descartado inteiro.
- **Presente e inválida falha com diagnóstico sem o valor bruto:**
  - não parseável como URL → `AppComposition.swift:1835` loga `"transport origin declared but unparseable as a URL;
    authorizing nothing (value withheld)"` (sem o valor);
  - presente mas não vira origem usável → `AppComposition.swift:1855-1861` loga a exigência (esquema/host/porta, sem
    path/query/fragment/credenciais) **sem repetir o valor**.
  - O sink de log (`AppComposition.swift:30-34`) é `#if DEBUG` e usa `privacy: .public` apenas sobre strings fixas; os
    call sites nunca passam o valor declarado.
  - Observação: é "fail-soft" (autoriza nada e segue), não "fail-fast" (abort/throw). Para benchmark isso é o
    comportamento certo — origem inválida simplesmente não autoriza host privado, e o produto nunca depende dela. Não
    é objeção.
- **Sob `#if DEBUG` em compilação:** sim. `AppComposition.swift:1823/1862/1865` — ramo `#else` zera
  (`authorizedNonPublicOrigins: [URL] = []`). Confirmado no `.pbxproj`: a config **Release** do alvo do app
  (`project.pbxproj`, XCBuildConfiguration `...025`) **não** tem `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`; só a
  Debug (`...024`) tem. Em Release o código não é compilado e nenhuma origem não pública é autorizada.
- `SyndicationAuthorizedOrigin(origin) != nil` (`:1852`) é a segunda barreira (recusa host público); K-01/K-05 já
  mergeados em `main` cobrem esse tipo.

## Prioridade (2) — Traço `FEEDMINE_TRACE_CAPTURE`

**Flag e dados: corretos. Before/after de IDs de janela: parcial — ver P2-01 abaixo.**

- **Desligado por padrão, só DEBUG:** `FeedScreen.swift:241-247` — `static let tracesCapture =
  ProcessInfo...["FEEDMINE_TRACE_CAPTURE"] == "1"`, inteiramente dentro de `#if DEBUG`. Os call sites por carta
  (`FeedScreen.swift:313-319`) só gravam quando `Self.tracesCapture` é verdadeiro. Em operação normal nada é pago.
- **Não loga dados sensíveis:** o traço registra UUID do card, `frameY`, `offset`, `height`, `activity`, âncora —
  geometria e identidade de card, sem conteúdo de artigo, sem credenciais, sem PII. `RunwayTrace.record` grava `event`
  + `fields` strings fornecidas pelo chamador; os chamadores só passam contagens, IDs e timestamps
  (`AppComposition.swift:1210-1214`, `:2095-2105`).
- **IDs da janela antes/depois de cada instalação:** ver **P2-01**.

## Prioridade (3) — UI com SQL/aquisição/rede no corpo de view; main-thread blocking

**Sem objeção.**

- **Nenhum SQL/rede no corpo de view.** As chamadas a `RuntimeDatabase(...)`, `PublicationStore(...)`, `URLSession`
  estão todas em `AppComposition.swift` (owner de composição), não em `body` de View. As Views em `Sources/FeedMineUI`
  não constroem `RuntimeDatabase`, `PublicationStore` nem `URLSession` (grep vazio).
- **`recordWindowFacts`** roda em `.task(id:...window)` (`FeedMineApp.swift:189-191`), fora do render, e é aritmética
  pura em memória: `editorialSubject` (`AppComposition.swift:1239-1243`) só consulta `association.feeds`/`.discovery`
  e o dict em memória `discoverySubjects`; `composition.recordWindowFacts` (`:1209-1215`) só formata strings para o
  traço. **Sem leitura de banco por carta** (fecha a hipótese K06-1 do review anterior — o comentário em
  `FeedMineApp.swift:806-807` descreve exatamente essa correção).
- **`DispatchQueue.main.sync`** só em `AppComposition.swift:2450` (`DeviceMediaConditions.current`), e guardado por
  `if Thread.isMainThread { return ... }` (`:2449`): só salta para a main quando chamado **fora** dela (amostragem de
  política de mídia em thread de fundo). Não pode travar a main por si. O outro `.sync` é `writer.sync {}` em
  `RunwayTrace.flushAndWait()` (`:140`), caminho de teste, não de produto.

## Prioridade (4) — Leitura local (`FeedReadingDecision`/`FeedReadingSurface`): nenhuma aquisição pelo leitor

**Correto. Sem objeção.**

- `FeedReadingDecision.swift` é valor puro: `target(body:summary:...)` decide corpo > resumo ≥3.000 caracteres > site,
  sem I/O, sem URLSession, sem store. `nil` quando não há texto nem endereço (`:84`). Limite de 3.000 é só para
  **abrir** o leitor, nunca afirma completude (`isPartial` default `true`).
- `FeedReadingSurface.swift` só renderiza o valor e emite callbacks `onOpenSite`/`onClose`. Não há `URLSession`,
  banco, aquisição nem prefetch. A única requisição ao site é o callback explícito (`:footer`, `:header`), que satisfaz
  o invariante do arquiteto "renderizar o leitor não dispara aquisição".
- Conteúdo parcial é sempre marcado ("Conteúdo parcial: o artigo completo está no site.", `:origin`); resumo é rotulado
  como resumo. Dynamic Type via tokens tipográficos, seleção de texto habilitada.

## Prioridade (5) — K06-2 (slot de oferta) e edição/âncora em A→B→A

**Ambos resolvidos nesta árvore. Sem objeção.**

- **K06-2 / K06-3 (slot de oferta):** `FeedScreen.swift:86-114` (iOS 18) e `:131-139` (macOS 14) — card + linha
  editorial ficam dentro de um `Group` que é **um** filho do `ForEach`/`LazyVStack`. A linha editorial é
  `editorial?(card, index, previous)` devolvendo `AnyView?`; **ausente → nada é emitido**, então não há filho de
  altura 0 e **nenhum `Spacing.section` fantasma** quando a oferta está escondida — o defeito K06-2 confirmado em
  `main` está corrigido. A linha editorial **nunca** é item de `window.items`: `observeCard`/`isLast`
  (`FeedScreen.swift:106-107`) só rodam sobre a geometria do `FeedItemView`, logo a linha não é âncora e não dispara
  `isLast` (fecha K06-3). O closure de produto devolve `nil` corretamente quando não há oferta verdadeira
  (`FeedMineApp.swift:690/700/708/714/724/726/739`, `presented(...)` → `:769` devolve `nil` sem `slotHeight`).
- **A→B→A:** `toggleSource`/`selectContext`/`applyFilter` (`AppComposition.swift:426-493`) seguem a ordem
  checkpoint → close → `association=nil` → persistir seleção → reconstruir, cada um sob guarda `replacingSession`
  (`:427-429`, `:461-462`). O invariante está no comentário `:483-485`: "A→B→A finds A's own checkpoint and no old
  callback can install into B." `checkpointCurrentPosition(at:)` é chamado **antes** de retirar a associação
  (`:435`, `:466`). A lacuna K06-5 (teste B05 com uma resposta entre A e B) é cobertura de teste faltante apontada no
  review anterior, **não** um defeito de código visível aqui.

---

## Achados

### P2-01 — Traço de instalação registra identidade da janela só DEPOIS do install (sem "antes")
- **Severidade:** P2 (instrumentação, não produto).
- **Arquivo:linha:** `FeedMineApp/FeedMineApp/AppComposition.swift:2089-2106` (`func install`).
- **Trecho:**
  ```swift
  func install(_ received: FeedPresentationState) throws {
      guard active else { throw ... }
      try store.install(received)                 // já mutou o estado
      store.installBookmarks(...)
      if let snapshot = store.state.presentation {  // lê SÓ o depois
          trace?.record("admitted", [... "edition": ..., "head": ..., "tail": ..., "anchor": ...])
      }
  }
  ```
- **Por que (não) bloqueia:** a prioridade (2) do pedido quer o traço registrando os IDs da janela **antes e depois**
  de cada instalação, para distinguir reinstalação/projeção de mutação real de IDs. Hoje só o estado **pós-install** é
  gravado numa linha `admitted` — o `received` que entra não é amostrado antes de `store.install`. O oráculo ainda
  pode comparar `admitted` consecutivos entre si, mas uma única instalação não carrega o par antes/depois numa linha.
  **Não bloqueia o merge:** o cabeçalho do próprio `RunwayTrace.swift:16-17` declara que o traço é evidência, não
  política ("Nothing reads this to choose what to publish"); nenhuma decisão de produto depende disso.
- **Correção mínima:** antes de `try store.install(received)`, capturar `let before = store.state.presentation` e
  incluir no `record` os IDs do `before` (`before?.editionID`, `before?.window.anchor.cardID`, head/tail) ao lado dos
  do `snapshot`, para que uma linha distinga reinstalação (IDs iguais) de mutação (IDs diferentes).

### OBS-02 — Comentário cita variável de ambiente com nome diferente do código
- **Severidade:** informativo (comentário obsoleto; não afeta compilação nem comportamento).
- **Arquivo:linha:** `FeedMineApp/FeedMineApp/AppComposition.swift:1814`.
- **Trecho:** `//   * the benchmark transport's origin, named by the run itself (`FEEDMINE_BENCH_TRANSPORT_HOST`, ...`
- **Por quê:** o código lê `FEEDMINE_BENCH_TRANSPORT_ORIGIN` (`:1830`) e o runner exporta `FEEDMINE_BENCH_TRANSPORT_ORIGIN`
  (`bench/run.sh:70`). O comentário fala em `..._HOST`, nome que não existe em lugar nenhum do repo. Risco: confundir o
  operador. **Correção mínima:** trocar `_HOST` por `_ORIGIN` no comentário.

### OBS-03 — `trace` é construído sempre (lazy), mesmo em Release
- **Severidade:** informativo.
- **Arquivo:linha:** `FeedMineApp/FeedMineApp/AppComposition.swift:66` — `lazy var trace: RunwayTrace? =
  RunwayTrace(directory: directory)`.
- **Por quê:** diferente do `FEEDMINE_TRACE_CAPTURE` (que é a origem de *volume* de log, e esse sim é DEBUG-only em
  `FeedScreen`), o sink `RunwayTrace` não é gated por flag nem por `#if DEBUG`: `record`/`admitted`/`window` são
  gravados em Release também, num arquivo `trace.jsonl` capado em 40.000 linhas (`RunwayTrace.swift:26`). Os dados são
  não sensíveis (IDs/geometria/contagens) e o volume é baixo (as linhas por install/window, não por frame). **Não é
  objeção** — fica registrado porque o pedido pergunta sobre "desligado por padrão": a captura de *alto volume* por
  carta está desligada; o traço de milestones (install/window) está sempre ligado por desenho (evidência de F05).
  Se o produto quiser zero escrita em Release, gatear a atribuição do `lazy var` por `#if DEBUG || FEEDMINE_BENCHMARK`.

---

## O que não li / limites

- **Sem toolchain Swift:** nada foi compilado ou executado. Todos os achados são leitura estática; o comportamento em
  runtime (deadlock real do `main.sync`, custo real do traço, geometria do slot no device) precisa de validação no Mac.
- **`### Decisao Codex — 2026-10-12 03:32`:** essa seção **não existe** no `coordination/KIRO.md` deste checkout
  (`bd74e575`) nem é adicionada pelo diff do PR (`git diff ... -- coordination/KIRO.md` vazio; `grep` por "03:32" e
  "Decisao Codex — 2026-10-12" sem resultado). Li todas as seções presentes do KIRO.md, incluindo a última entrada do
  log de checagens (`2026-10-12 00:37`, HEAD `e84b5b1`) e as coordenações Codex até `21:32 PDT`. **Não pude confrontar
  a "ordem da coordenação" dessa decisão específica porque ela não está nesta árvore.**
- **Li em cheio:** `FeedReadingDecision.swift`, `FeedReadingSurface.swift`, `RunwayTrace.swift`, o bloco de
  autorização de origem (`AppComposition.swift:1790-1880`), `install`/`recordWindowFacts`/`editorialSubject`
  (`:1209-1243`, `:2089-2106`), a estrutura do slot editorial em `FeedScreen.swift:83-147`, o trecho A→B→A
  (`AppComposition.swift:420-500`), o diff do `.pbxproj` (adições), e os call sites do traço em `FeedScreen.swift`.
- **Li parcialmente / não li em cheio:** `FeedMineApp.swift` fora dos trechos citados (314 linhas no diff; li o
  closure `editorialInvitation` por grep + o host do `recordWindowFacts`); `AppComposition.swift` tem +1292 linhas e
  li as regiões das cinco prioridades, não o arquivo inteiro; `MediaPlaybackAdapter.swift`, `TrustedFeeds.swift`,
  `EditorialInvitationCadence.swift`, `FeedEditorialInvitationView.swift`, `ReaderDiscoveryControls.swift`,
  `ReaderContentFilterView.swift`, `ReaderAddFeedViews.swift`, `FilterSheetView.swift`, `ReaderOnboardingView.swift`
  **não** foram lidos linha a linha (fora das cinco prioridades nomeadas; grep de SQL/rede/`main.sync` cobriu-os para
  os riscos da prioridade 3, e nada apareceu).
- **Não verifiquei** se o runner externo do benchmark (fora do repo) serve a origem exatamente no formato
  `scheme://host:port` que o filtro exige — se não servir, o benchmark autoriza nada (fail-soft), o que é seguro para
  produto mas pode surpreender o operador.
