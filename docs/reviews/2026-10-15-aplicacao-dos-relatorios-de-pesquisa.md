# Aplicação dos dois relatórios de pesquisa ao FeedMine V2 — 2026-10-15

Rodada de aplicação dos relatórios *"O que o «The Algorithm» do Twitter/X ensina ao Feedmine"*
e *"Análise Comparativa: NetNewsWire vs Feedmine"* sobre `main @ 801f017dd3a65c19e47ae101f4a95de02457458c`.

**Ambiente:** macOS arm64 (darwin 25.3.0), Xcode 26.6, Swift 6.0, `wsmontes/feedmine_v2`.
**Método:** reconhecimento por leitura do código (agentes somente-leitura), parecer do arquiteto
(ChatGPT, pelo navegador, com leitura direta do GitHub na revisão congelada), implementação
paralela em worktrees isolados (um gate = uma branch = um commit sobre a BASE), verificação nativa
por comando executado.

## 1. Por que a maior parte dos dois relatórios é REJECT

Os dois relatórios foram escritos **sem conhecer o estado do FeedMine** ("assumindo que seu estado
atual não foi especificado"; "presumimos ser um leitor de feeds com código menos maduro"). O
primeiro passo da aplicação, portanto, não é implementar: é confrontar cada recomendação com o
código e com os invariantes congelados, e rejeitar com citação o que já existe ou contradiz o produto.

O parecer do arquiteto fixou o critério:

> APPLY = comportamento aprovado que pode ser incorporado ou completado sem criar um segundo
> mecanismo concorrente. PRESENTE = capacidade ou mecanismo já implementado. REJECT = mecanismo
> proposto incompatível com o produto, redundante ou sem evidência suficiente para justificar sua
> complexidade.

## 2. Matriz de estado (evidência por leitura)

### 2.1 Twitter/X ("The Algorithm")

| # | Recomendação | Estado | Evidência / veredito |
|---|---|---|---|
| 1 | Ledger unificado de impressões (`feed_request_id`, `candidate_source`, `rank_score`, `model_version`, outcome) | AUSENTE → **REJECT** | Nenhum match para impressão/request id/score em `Sources/`. Autoridade: INV-12/14/15/16, North Star |
| 2 | Candidate sources independentes | PARCIAL → **REJECT** | `Sources/FeedMineEditorial/CandidateProvider.swift:29` é o ponto único de obtenção; autoridade: INV-12/14 |
| 3 | Recuperação × ranking com contratos plugáveis | PARCIAL → **PRESENTE** | `CandidateProvider` → `ReaderFilterEligibility.admits(_:)` → `SelectionEngine` → `SourceAlternation`; `EditorialPolicy.swift:6` é enum fechado **de propósito** |
| 4 | Ranking multiobjetivo com pesos utilitários | PARCIAL → **REJECT** | Pesos existem por **fonte** (`EditorialPolicy.swift:8-13`), não por desfecho; não há dados rotulados |
| 5 | Pós-ranking: diversidade, cap por autor, fadiga | PARCIAL → **APPLY restrito** | PD-4 já tem dono e testes (`SourceDiversityContractTests`, 14 casos); diversidade **temática** exige fato inexistente → gate TX-05 |
| 6 | Política graduada ALLOW/DOWNRANK/LABEL | PARCIAL → **REJECT** | `ReaderFilterEligibility` é elegibilidade, não preferência suave; autoridade: F13 R1-R6, PD-11 |
| 7 | Frescor contextual (half-life, `age`) | AUSENTE → **APPLY** | Só `recencyDescending` global; F03 §2 exige peso contextual da idade → gate TX-07 |
| 8 | Feature registry declarativo | AUSENTE → **REJECT** | `Candidate`/`ResolvedSelectionPolicy`/`SourceFacts` já são contratos tipados; INV-15 |
| 9 | Infraestrutura de experimentação | AUSENTE → **REJECT** | PD-7/PD-8; testes determinísticos + benchmark já comparam políticas versionadas |
| 10 | Observabilidade por estágio | PARCIAL → **PRESENTE** | `ReplenishmentTrace` é porta injetável; `CandidateProvider` registra consultas |
| 11 | Feedback negativo de primeira classe | PARCIAL → **APPLY** | Exclusões duráveis existem; o que está **errado** é a redação do convite (PD-11) → gate TX-11 |
| 12 | Embeddings/ANN/two-tower | AUSENTE → **REJECT** | Sem evidência de necessidade; North Star §§4-5, INV-12/15/16 |

### 2.2 NetNewsWire

| # | Recomendação | Estado | Evidência / veredito |
|---|---|---|---|
| NN-01 | RSS, Atom, JSON Feed | PRESENTE | `SyndicationTranslator.swift:8` `case rss, rdf, atom, json`; FeedKit 10.9.4 |
| NN-02 | OPML import + export | PRESENTE | `OPMLDocument` + `ReaderImportExportCoordinator` (preview/commit/export), UI em `ReaderImportExportViews` |
| NN-03 | Offline-first + retomada | PRESENTE | GRDB em Persistence; `SyndicationCheckpointState`; `FeedSession.swift:246-248` |
| NN-04 | Erros e offline na UI | PRESENTE | `FeedLoadingView.swift:30-105` (`.unavailable`/`.deferred`/`.unreachable`) |
| NN-05 | Privacidade / execução local | PRESENTE | `PrivacyInfo.xcprivacy`: sem tracking, sem coleta, sem SDK de terceiros |
| NN-06 | BGTaskScheduler / BGAppRefreshTask | PARCIAL → **APPLY** | `Info.plist:33-36` só `audio`; `BackgroundFeedRefresh.swift` era scaffold; F23 prevê a oportunidade → gate NN-06 |
| NN-07 | Acessibilidade | PARCIAL → **APPLY** | VoiceOver/reduce-motion existem; **0** `keyboardShortcut`/`onKeyPress` e **0** `@ScaledMetric` → gate NN-07 |
| NN-08 | OPML no primeiro contato | PARCIAL → **APPLY** | Import existe em `SourceManagementView.swift:74`, o onboarding não o oferece → gate NN-08 |
| NN-09 | Sync em nuvem (CloudKit/Feedly/...) | **FORA-DE-ESCOPO** | `ARCHITECTURE.md:36` proíbe sincronizador paralelo; F24 exclui sincronização em nuvem |
| NN-10 | CI hospedado | **FORA-DE-ESCOPO** | PD-7 "No hosted CI"; `.github/` não existe por decisão |

## 3. Os seis gates autorizados e o que foi medido

| Gate | Branch | Entrega | Verificação nativa |
|---|---|---|---|
| TX-05 | — | **BLOCKED**: nenhum fato temático por história em `Candidate`/`CandidateRecord`/`origin_revisions`/`selection_supply`; inventar por palavra-chave ou taxonomia da fonte é proibido pela própria spec | não aplicável (nenhum commit) |
| TX-07 | `chatgpt/tx07-contextual-freshness` | **BLOCKED/parcial**: caracterização de F03 em teste novo; nenhum código de produção alterado | `swift build` 0 · `swift test` **1362 testes, 4 skipped, 0 falhas** · suíte nova `ContextualFreshnessCharacterizationTests` **5/0** |
| TX-11 | `omp/tx11-negative-feedback-copy` | Redação de PD-11 ("Não quero mais sobre X" / "Entendido. Vamos excluir X das próximas descobertas."), identificadores preservados | `swift build` 0 · `swift test` **1357 testes, 4 skipped, 0 falhas** (o gate não adiciona nem remove teste) |
| NN-06 | `chatgpt/nn06-opportunistic-bg-refresh` | `BGAppRefreshTask` única, `BGTaskSchedulerPermittedIdentifiers` + `fetch`, reuso de `syncCatalogueIfDue(installNewRevisions: false)`, single-flight e cancelamento cooperativo | `swift build` 0 · `swift test` **1361 testes, 4 skipped, 0 falhas** · suíte nova 4/0 · **alvo do app na árvore integrada**: `CompositionTests` **63/0** — o seletor casa por **classe**, então o caso novo do NN-06 **não** entra nessa conta; ele vive em `BackgroundRefreshCapabilityTests` e foi medido à parte: `-only-testing:FeedMineAppTests/BackgroundRefreshCapabilityTests` → **1/0**, `** TEST SUCCEEDED **` (é o que prova que a declaração no `Info.plist` vale e que o código de BG compila em Swift 6) |
| NN-07 | `omp/nn07-accessibility` | `card.open` nomeado, rótulos de salvar com as palavras do menu, ação acessível "Tocar" para mídia, decoração oculta, badge escalado por `@ScaledMetric`; **defeito medido, não afirmado** no primeiro contato: na BASE o elemento `welcome-headline` tem frame **0,0 × 14,0** (controle positivo, abaixo) — o texto real vinha pendurado em `.overlay` sobre um `Text(verbatim: "")` sem área própria; o gate fecha o P1 que a rodada 9 registrou (`docs/reviews/2026-10-11-round9-language-choice-and-localization.md:115-124`, cujas capturas vivem em `docs/evidence/`, pasta gitignored, e por isso não são artefato citável) | `swift build` 0 · `swift test` **1357 testes, 4 skipped, 0 falhas** (os 2 testes novos são do alvo do app) · **controle BASE**: `xcodebuild test -only-testing:FeedMineUITests/FeedMineUITests/testTheWelcomeHeadlineIsDrawnWhereTheReaderReadsIt` sobre BASE + o teste da branch → `Executed 1 test, with 2 failures`, `** TEST FAILED **`, largura 0,0 (log `docs/reviews/evidence/2026-10-15-aplicacao-dos-relatorios/nn07-base-control.log`) · **tratamento**: o mesmo teste na árvore integrada **passa** (`2/0` junto da jornada de OPML, `** TEST SUCCEEDED **`) — controle vermelho na BASE, verde depois, no mesmo caso |
| NN-08 | `omp/nn08-onboarding-opml` | Ação "Importar OPML" no primeiro contato pelo mesmo fileImporter/preview/commit do gerenciamento de fontes; o gate se retira e volta; cancelar não escreve nem conclui | `swift build` 0 · `swift test` **1357 testes, 3 skipped, 0 falhas** (o gate não adiciona teste de pacote: 1357 é a contagem da BASE; os 3 skipped são a paridade incompleta daquele worktree) · **alvo do app, executado pelo par**: `CompositionTests` **63/0** e `FeedMineUITests/testFirstRunImportsOPMLWithoutMakingItAPrerequisite` **1/0 em 46,2 s**, `** TEST SUCCEEDED **` (`docs/reviews/evidence/2026-10-15-aplicacao-dos-relatorios/nn08-composition-and-onboarding-journey.log`); a tentativa anterior falhou com `profiles.json` ausente — precondição de ambiente, não produto |

### 3.0 Comparabilidade das corridas em worktree (medida, não presumida)

`swift build`/`swift test` compilam **apenas as dez bibliotecas** (`Package.swift:56-95`); o alvo do
app (`FeedMineApp/FeedMineApp.xcodeproj`) é separado e **não** é exercitado por eles. Portanto:

- as linhas de `swift build`/`swift test` da tabela acima provam as mudanças em `Sources/`, **não**
  as mudanças em `FeedMineApp/` (NN-06: `FeedMineApp.swift`, `AppComposition.swift`, `Info.plist`,
  `CompositionTests.swift`; NN-07/NN-08: `FeedMineUITests.swift`, `ReadingSurfaceUITests.swift`) —
  a compilação do alvo do app é medida à parte, por `xcodebuild`;
- um worktree novo **não** tem `bench/corpus/catalog.sqlite` nem o catálogo empacotado
  (`FeedMineApp/FeedMineApp/Resources/catalog.sqlite`), então 3 testes que a `main` executa passam a
  ser pulados: `CatalogCompilerReferenceTests.swift:51` e `:81` e
  `LegacyCatalogMetadataTests.swift:120`. É a razão de todas as corridas acima relatarem
  **4 skipped** onde a `main` relata **1**: `1 + 3`. A aritmética de testes novos continua exata
  (`1357 + 4 = 1361` em NN-06; `1357 + 5 = 1362` em TX-07), mas o número não é comparável aos PASS
  já registrados sem devolver o corpus ao worktree — o que é feito na corrida da árvore integrada.

### 3.1 Ensaio de integração (executado, não presumido)

Os cinco commits partem da mesma BASE. A sobreposição real de arquivos é pequena e foi medida:

| Arquivo | Gates que o tocam |
|---|---|
| `Sources/FeedMineUI/Onboarding/ReaderOnboardingView.swift` | NN-07, NN-08 |
| `FeedMineApp/FeedMineAppTests/FeedMineUITests.swift` | NN-07, NN-08 |
| `FeedMineApp/FeedMineApp/FeedMineApp.swift` | NN-06, NN-08 |

Ensaio em worktree descartável (`/tmp/fm-merge2`, já removido), merge **commitado** a cada passo
(a primeira tentativa usou `--no-commit` e foi inválida: `MERGE_HEAD` não concluído faz o passo
seguinte virar no-op — o ensaio foi refeito por isso):

```
### 93ac5302 (NN-06)            exit=0 conflicts=0
### omp/nn08-onboarding-opml   exit=0 conflicts=0
### omp/nn07-accessibility     exit=0 conflicts=0
### omp/tx11-negative-feedback-copy exit=0 conflicts=0
### 7d33ede4 (TX-07)           exit=0 conflicts=0
```

Caminho: `main` → branch `integration/tx11-nn06-nn07-nn08-tx07-characterization` (criada de
`801f017d`) recebe os cinco merges; `main` avança por `--ff-only` para o topo dela depois do verdict.

**Verificação da árvore integrada (executada):**

| Passo | Comando | Resultado |
|---|---|---|
| árvore | `1f9042d4` (cinco merges, sem o relatório) | `swift build` 0 · `swift test` **1366 testes, 4 skipped, 0 falhas** · `git diff --check` vazio |
| árvore com o relatório e a evidência (a que se publica) | `1b41d492`, tree `a0f7c8f21689c10b88d8fccf646bcf8715686ab6` | `git diff --check 801f017d..HEAD` **0** · `swift build` 0 · `swift test` **1366 testes, 1 skipped, 0 falhas** · 20 arquivos contra a BASE, **0** em `bench/` |
| alvo do app, árvore integrada | `xcodebuild test … -only-testing:FeedMineAppTests/CompositionTests -only-testing:FeedMineUITests/FeedMineUITests/testTheWelcomeHeadlineIsDrawnWhereTheReaderReadsIt -only-testing:…/testFirstRunImportsOPMLWithoutMakingItAPrerequisite` sobre `/tmp/fm-integration` | `CompositionTests` **63/0**, as duas jornadas **2/0 em 41,6 s**, `** TEST SUCCEEDED **` — é o único artefato onde NN-06 e NN-08 coexistem em `FeedMineApp.swift`; log `integrated-tree-app-tests.log` (o seletor de `CompositionTests` é por **classe**: o caso novo do NN-06, em `BackgroundRefreshCapabilityTests`, não entra nessa conta, e foi medido à parte: **1/0**) |
| árvore PUBLICADA (TX-07D + TX-05D + o commit documental) | `acf8d5f7`, tree `b00e869c` (worktree com paridade de corpus restaurada) | `swift build` 0 · `swift test` **1397 testes, 1 skipped, 0 falhas** · `All tests passed` — o `1 skipped` é o da `main`, então o número é comparável aos PASS já registrados; log `published-tree-final.log` |

**Logs brutos desta rodada (persistidos no repo, nunca só em `/tmp`):**
`docs/reviews/evidence/2026-10-15-aplicacao-dos-relatorios/` — `fm-int-test-final.log` e
`fm-int-test-parity.log` (suíte do pacote na árvore integrada), `integrated-tree-app-tests.log`
(`CompositionTests` + as duas jornadas de UI na árvore integrada), `nn07-base-control.log` (controle
do NN-07 na BASE), `nn08-composition-and-onboarding-journey.log` (corrida do par no alvo do app) e
`app-target-build-precondition-peer.log` (a precondição de build ausente num worktree novo) e
`published-tree-final.log` (a verificação final na árvore publicada, com paridade de corpus).

**Transformação aplicada aos logs, declarada (o `git diff --check` do repo exige árvore sem espaço em
branco no fim de linha, e os logs de `xcodebuild` têm muitos):** removido apenas espaço/tab no fim de
cada linha; nenhum outro byte alterado. Cinco arquivos mudaram e dois não:

| Arquivo | bytes | SHA-256 (normalizado) |
|---|---|---|
| `nn07-base-control.log` | 818304 → 816158 | `ed6de407060f7ff4f9f999112924dda14b96f819c9435f6b52a3b47d1ccbd1b3` → `fb51d0d7ed9ddb567dad169d3e207ab8f9923932057739029a2eb7d21f76e517` |
| `integrated-tree-app-tests.log` | 2348203 → 2346057 | `a5c4479a9da53906680ad70c419e609332e56e96691783be18890d481facda4f` → `d8ff17c554b132c1136a458e3f200db1a46ed6d6b4f24b3f4f68da108c19138b` |
| `app-target-build-precondition-peer.log` | 228975 → 228841 | `7d4a3882fe8e5ad1432e13b61dd777c71a2d4f3c4260f80419b8542b66eea1fe` → `797f2aac5d330022353633f4205524a96e77aa6de7902170aa6271372dbf49de` |
| `nn08-composition-and-onboarding-journey.log` | 1671789 → 1671779 | `4ea9a1411fff51f55e72e07a7b7f0639f0c9c7b79c84d580cfec792a4f7a8dcf` → `af9fe2f4253009d2a346d8eb479f51b37396e7d6c69d37063d4ef0e2fea17159` |
| `fm-int-test-final.log` | 397937 → 397937 | `b192c414ea06e6ebb4fa8c5dab00fa9dc26a945aa1e113456ddd58d60e26ee2b` (inalterado) |
| `fm-int-test-parity.log` | 397937 → 397937 | `5a6e0fae2fba484a169fe4d3dbae892f423e1ac27d65817173499717356c8b3f` (inalterado) |
| `published-tree-final.log` | 450712 → 450710 | `ec054a463d05dc3f7e5a50ef2e637ae1f616f3a69e9b5a9c076e012ad0c062c7` → `d0b0300398d0da25841119c67c5843e6f3b450adf08da39a25cca9355b5960c9` |

**Redação de identificadores na ponta (2026-10-16) — leia junto com a tabela acima.** As colunas
`bytes` e `SHA-256 (normalizado)` descrevem os bytes **publicados antes da redação** de identificadores
pessoais (conta local anterior e identificadores de aparelho) aplicada à ponta do repositório público.
Quatro dos cinco arquivos alterados pela normalização — `nn07-base-control.log`,
`integrated-tree-app-tests.log`, `app-target-build-precondition-peer.log` e
`nn08-composition-and-onboarding-journey.log` — também foram redigidos, então nem o tamanho nem o hash
"depois" correspondem aos bytes atuais da ponta: o sha256 dos bytes publicados originais de cada um está
em `docs/reviews/evidence/REDACTION.md`. A normalização de espaço em branco continua sendo a única
alteração **anterior** à redação, e a comparação antes/depois das duas colunas permanece válida como
medição daquela transformação.

`fm-int-test-final.log` e `fm-int-test-parity.log` têm o mesmo tamanho por coincidência e **conteúdo
diferente** (`cmp` diverge no byte 1): são duas corridas distintas da mesma suíte (uma antes e uma
depois do commit do relatório), não uma cópia da outra.

Paridade de corpus exigiu **dois** artefatos, não um: `bench/corpus/` (89 MB) **e**
`FeedMineApp/FeedMineApp/Resources/catalog.sqlite` (118 MB). Sem o segundo,
`LegacyCatalogMetadataTests.swift:120` continua pulado; sem o primeiro, três testes pulam.

E os dois são **pré-requisito de build**, não só de teste. Medido, com artefato citável em
`docs/reviews/evidence/2026-10-15-aplicacao-dos-relatorios/app-target-build-precondition-peer.log`:
num worktree novo, onde os dois insumos são gitignored e portanto ausentes, o `xcodebuild test` morre
em `error: The file “profiles.json” couldn't be opened … (in target 'FeedMineUITests')`,
`Testing cancelled because the build failed` e `** TEST FAILED **` — sem executar um único teste.
A minha própria cadeia de alvo do app bateu na mesma classe de falha com o outro insumo
(`error: The file “catalog.sqlite” couldn't be opened`, `CpResource … FeedMine.app/catalog.sqlite`);
esse log foi sobrescrito pela repetição corrigida antes de ser copiado, então o que se cita dele é o
texto observado, e a prova durável da classe é o log do par. Em nenhum dos dois casos é falha de
teste: é **precondição de ambiente**. O par independente classificou igualmente `PRECONDITION`.

## 3.2 Veredito do arquiteto (2026-10-15)

| Gate | Veredito | Efeito |
|---|---|---|
| TX-05 | **CLOSED / BLOCKED / DEPENDENCY REQUIRED** — "não alterar SelectionEngine enquanto não existir um contrato upstream verificável. Não transformar taxonomia da fonte em identidade temática do artigo." | nenhum código; abre TX-05D |
| TX-07 | **CLOSED / BLOCKED / CHARACTERIZATION ACCEPTED** — "o commit 7d33ede4 é admissível à integração como evidência de comportamento atual, **não** como implementação de F03" | integra como evidência; abre TX-07D |
| TX-11, NN-06, NN-07, NN-08 | integração autorizada, "condicionada à validação da árvore integrada no Mac e à preservação da BASE congelada" | integração pelos quatro gates implementados |

Divisão que o arquiteto fixou para o frescor contextual, e que o gate original não podia cumprir sozinho:

> Corrigir a interpretação da data já disponível. Representar, quando comprovável, a natureza
> temporal da história para aplicar frescor contextual. **A primeira não deve depender da segunda.**
> Não precisamos construir um classificador de notícias para parar de tratar `observedAt` como
> `publishedAt`.

Dois gates novos, ambos a partir de `801f017d`, ficam autorizados e **não** bloqueiam a integração
acima: `chatgpt/tx05-story-topic-provenance` (contrato de evidência temática por história, com
`STOP` para BLOCKED se os protocolos não entregarem metadados suficientes) e
`chatgpt/tx07-temporal-evidence` (contrato temporal canônico: `authoredAt`/`modifiedAt`/`observedAt`
distintos, confiança separada de presença, natureza temporal explícita e nunca inferida de idade,
assunto, nome da fonte ou palavra do título).

## 3.3 Gates de dependência abertos pelo veredito

**TX-07D — `omp/tx07-temporal-evidence`, commit `7cf3f552` (um commit sobre `801f017d`, 13 arquivos,
todos na allowlist).** Estado do autor: **CONTRACT READY** para procedência temporal; **natureza
contextual UNKNOWN** — não provada e não fabricada. Sem migração, sem `bench/**`, sem tocar
`SelectionEngine`, `EditorialPolicy`, `SourceAlternation`, Publication/Runway ou `AppComposition`.

O que ele entrega: o clamp de datas futuras deixa de ser silencioso (a reivindicação crua da origem
viaja junto da observação, com uma única regra de aceitação `min(reivindicado, observado)`), o
admission recusa pares contraditórios, e `Candidate.temporal` passa a expor
`CandidateTemporalEvidence` (`observedAt`, autoria/modificação aceitas, `publicationDate`,
`inconsistencies`, `nature == .unknown`) reconstruída da oferta canônica — **sem** que nada consuma
isso para ordenar: `timestamp` continua como estava.

**Achado derivado da leitura do código (ainda não de execução):** `ContentStore.swift:734`
(`let date = revision.authoredAt ?? revision.observedAt`) alimenta
`ORDER BY sort_date DESC, origin_record_id DESC LIMIT ?` (`:84-85`, consumido em `:100`). Com 6
registros sem data observados num mesmo instante mais 1 história declarando publicação 365 dias
antes, uma janela de 6 examina 6 registros — **100 % `observedFallback`, nenhum com data de
publicação**; a história datada só entra quando o limite chega a 8 linhas examinadas (7 no total,
`exhausted=true`). É viés de janela examinada, não perda: o keyset continua caminhando até ela.

**Verificação nativa (executada pelo ORCH, reprova o gate):** `swift build` exit 0 ·
`swift test` → **`Executed 1374 tests, with 4 tests skipped and 2 failures (0 unexpected)`**. As duas
falhas são do teste novo do próprio gate,
`CandidateProviderTests.testMaterialEditKeepsTheDeclaredPublicationDateAndManufacturesNoNovelty`, e
ambas em `observedAt`: o candidato da **nova revisão** continua reportando a observação da **primeira**
admissão (`22:13:20` onde o teste injeta e espera `23:13:20`, delta exatamente o `3600 s` do fixture —
não é fuso). A outra metade do teste passou (ordenação `timestamp` inalterada,
`publicationDate == .declared(declared)`, `acceptedModifiedAt == nil`, troca de `originRevisionID`).
**O gate não está verde**: a correção foi devolvida ao implementador com o log literal e a exigência de
decidir, pelo esquema canônico, se o errado é a propagação ou a expectativa — reescrevendo o commit
único na mesma branch (que ainda não foi publicada).

**Não feito, com a razão no código:** a reivindicação clampada **não** é persistida — fazer isso exige
migração, e `Tests/FeedMinePersistenceTests/PublicationRunwayStoreTests.swift:244` fixa a lista
*exata e ordenada* de `grdb_migrations`, arquivo congelado e fora da allowlist; ordenação, cursor e
keyset ficaram intocados pela cláusula STOP, com a regra demonstrada só em teste; e natureza temporal
segue `unknown` porque não existe evidência nem regra de interpretação aprovada.

**Reconciliação e segundo veredito.** O gate foi reconciliado contra a `main` que o lote produziu
(branch nova, identidade nova: `omp/tx07d-temporal-evidence-recut`, commit `ebfa1289` sobre
`cca2bc4b`, 13 arquivos, allowlist inalterada). O cherry-pick colidiu em *add/add* em
`ContextualFreshnessCharacterizationTests.swift`, porque esse arquivo já existe na `main` desde o
TX-07; resolvido pela versão do gate depois de conferir que ela é superconjunto (9 testes contra 5,
os 5 originais presentes verbatim, o diff `114+/5−` sendo só cabeçalho) e que o cabeçalho novo
**preserva a ressalva não normativa** ("characterization, NOT implementation", "a test-only label must
never become an implicit classifier", "`observed` is an observation timestamp, NOT a publication
date"). Re-verificado na árvore vigente: `swift build` 0 · `swift test` **1378 testes, 4 skipped,
0 falhas** · `git diff --check` 0.

O arquiteto então **bloqueou a integração** dele por um defeito real de contrato, e não por grafo,
conflito ou verificação:

> O contrato novo ainda permite que uma declaração de publicação futura seja apresentada ao consumidor
> como uma data de publicação declarada no instante atual.

Caminho: o publicador declara 2100 → `SyndicationTranslator` aceita `min(declarado, observado)` →
`authoredAt = observedAt` → `CandidateProvider` recupera isso como `acceptedAuthoredAt` →
`publicationDate` devolve `.declared(observedAt)`. O próprio teste do gate
(`testF03ClampedDeclarationIsIndistinguishableFromADeclarationOfTheObservationInstant`) confirmava o
comportamento. Isso contraria a condição do gate *"data futura ou inconsistente não vira
automaticamente publicação válida de hoje"* e F03 §2. Correção autorizada, sem migração: quando
`acceptedAuthoredAt == observedAt` e a declaração original não está disponível, `publicationDate` deve
representar a **ambiguidade** (um terceiro caso no enum), o mesmo exame vale para `acceptedModifiedAt`,
e o contrato deve declarar que a declaração original é transitória e não sobrevive à persistência
atual. Sete provas adicionais foram exigidas. **`main` não avançou para `ebfa1289`.**

**Desfecho dos dois gates de dependência (2026-10-15).** Ambos foram reconciliados contra a árvore
vigente, verificados e integrados — cada um por `--ff-only` com verdict explícito, guardas conferidas
e `origin/main` verificado depois do push. `main` terminou em
`8faef1fa7e5714c8b52ce5fb419eb27cd2ad12d6`.

| Gate | Candidato aprovado | O que o verdict diz |
|---|---|---|
| TX-07D | `d589741e` | **APPROVED / CONTRACT READY** para procedência temporal. A regra ficou total e ordenada (ausente → `.absent`; estritamente anterior → `.declared`; igual → `.ambiguousAtObservation`; **posterior → `.absent`**, nunca `.declared`). O quarto caso `.unusable(Date)` foi **REJECT** — o bruto já distingue os dois fatos e INV-15 desaconselha ampliar o vocabulário |
| TX-05D | `8faef1fa` | **APPROVED / DECLARED-SUBJECT EVIDENCE READY**. Reutilização do slot `search_projection` **RATIFIED**, com escopo limitado: não é campo genérico, e uma futura busca textual que precise coexistir exige decisão de schema própria. Migração **REJECT FOR NOW**. Limitação Atom/FeedKit **ACCEPTED** como limite da dependência, sem parser paralelo |

O arquiteto exigiu, como commit documental separado e não bloqueante,
`docs/architecture/CANONICAL_SUPPLY_DESIGN.md` complementado: o slot pode carregar a representação
marcada e versionada das declarações temáticas, continua não material, só um dos dois usos o ocupa
por revisão, a hidratação de candidatos pode ler esse texto sem alterar índice nem keyset, revisões
históricas e valores opacos permanecem legíveis, e coexistência futura com busca textual exige decisão
própria. Isso está no commit que acompanha este registro.

**Limites registrados, não resolvidos aqui:** a identidade temática semântica entre vocabulários
diferentes **não** existe (o contrato entrega identidade verificável da *declaração*: superfície,
taxonomia declarada e texto normalizado); a diversidade temática na Selection continua sendo o gate
TX-05, não autorizado por esse verdict; e a prioridade indevida de `observedAt` na seleção, a
interação entre a ordenação da oferta e a janela limitada de candidatos e a natureza temporal da
história ficam para gates posteriores.

**TX-05D** fechou o ciclo na ordem que o arquiteto fixou (integração dos cinco → TX-07D → TX-05D):
implementado, reprovado na verificação nativa por uma falha do próprio teste (o **fixture** Atom, não o
tradutor), corrigido, reconciliado contra a árvore vigente, verificado com **1397 testes / 4 skipped /
0 falhas** e integrado em `8faef1fa`.

## 4. Veredito e integração (2026-10-15)

O arquiteto aprovou o lote e autorizou o avanço por `--ff-only`, com uma ressalva registrada e três
condições de conferência — todas cumpridas antes do merge.

| Gate | Veredito |
|---|---|
| TX-07 | **ACCEPTED / CHARACTERIZATION ONLY** — entra como evidência de comportamento atual; nenhuma política nova ativada |
| TX-11 | **APPROVED FOR INTEGRATION** |
| NN-06 | **APPROVED / UX23 NOT_RUN** — compilação Swift 6, capabilities e a classe `BackgroundRefreshCapabilityTests` verificadas; a execução efetiva concedida pelo iOS em aparelho físico **não** foi provada, e isso não bloqueia o código |
| NN-07 | **APPROVED** — "o controle vermelho na BASE e verde na árvore integrada … demonstra que o teste discrimina o defeito corrigido, em vez de apenas passar nas duas versões" |
| NN-08 | **APPROVED** |
| Cabeçalho estrutural do NN-06 | **ACCEPT AS IS** — restaurar agora criaria uma terceira árvore sem benefício comportamental; fica como limpeza documental não bloqueante |

**Identidades publicadas.** `main` avançou por `--ff-only` de `801f017d` para
`7a60595ede66749d434683ab63ecae0908124c8f` (tree `1445d84b2aee601d9edd000c5dcca8c91e4b8284`), e
`origin/main` confere com esse SHA. Guardas conferidas imediatamente antes: `origin/main` ainda em
`801f017d`, árvore local limpa, HEAD e tree da branch exatamente os aprovados, BASE ancestral da
integração, e o delta entre a árvore medida (`1b41d492`) e a publicada restrito a este relatório
(`1 arquivo, 12 inserções, 8 remoções`, zero código). Sem force push.

**Ressalva que permanece aberta:** a execução real de `BGAppRefreshTask` concedida pelo iOS
(UX23-A/B/E, expiração, execução negada, Background App Refresh desligado) exige aparelho físico e
segue `NOT_RUN`. Nada neste lote a declara aprovada.

**Fora deste lote, mas integrados depois:** TX-07D (reconciliado contra a `main` deste lote, aprovado e integrado em `d589741e`) e TX-05D (aprovado e integrado em `8faef1fa`) — ver o desfecho na seção 3.3.

## 5. Achados que ficam para a próxima rodada

- **TX-05** só é implementável quando existir contrato de fato temático por história *antes* de
  Selection; introduzi-lo exige um gate próprio (fora da allowlist aprovada).
- **TX-07** documenta uma divergência real de F03: `SelectionEngine` ordena pelo valor da data sem
  distinguir `CandidateTimestampKind.authored` de `.observed` — uma história sem data de publicação,
  observada hoje, ultrapassa uma notícia publicada ontem.
- **TX-11 (residual)**: o chip de nível do controle de descoberta
  (`ReaderDiscoveryControls.swift:203-213`, via `FeedRecipeDefinition.topicLabel` em
  `Sources/FeedMineDomain/FeedRecipeDefinition.swift:25`) ainda mostra "Menos" para o mesmo `.less`
  que a ação do convite agora declara como exclusão — é exatamente a "distinção futura" que PD-11
  difere, e por isso ficou fora da allowlist do gate.
- **NN-06**: o arquivo `Sources/FeedMineRuntime/BackgroundFeedRefresh.swift` perdeu o cabeçalho
  estrutural (`File/Module/Owns/Does not own`) que os arquivos implementados do módulo mantêm
  (`FeedSession.swift:1-4`, `RunwayController.swift:1`). Desvio de forma, não de comportamento —
  decidir se a integração exige restaurá-lo.
