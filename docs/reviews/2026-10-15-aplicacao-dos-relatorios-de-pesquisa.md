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
| NN-06 | `chatgpt/nn06-opportunistic-bg-refresh` | `BGAppRefreshTask` única, `BGTaskSchedulerPermittedIdentifiers` + `fetch`, reuso de `syncCatalogueIfDue(installNewRevisions: false)`, single-flight e cancelamento cooperativo | `swift build` 0 · `swift test` **1361 testes, 4 skipped, 0 falhas** · suíte nova 4/0 |
| NN-07 | `omp/nn07-accessibility` | `card.open` nomeado, rótulos de salvar com as palavras do menu, ação acessível "Tocar" para mídia, decoração oculta, badge escalado por `@ScaledMetric`; defeito **estrutural** corrigido no primeiro contato: na BASE a manchete era `Text(verbatim: "")` com o texto real pendurado em `.overlay` sobre um placeholder sem área própria (`ReaderOnboardingView.swift:135-147`) — o código sustenta o defeito de construção; se isso resultava em pixels visíveis depende de execução e está sendo medido | `swift build` 0 · `swift test` **1357 testes, 4 skipped, 0 falhas** (os 2 testes novos são do alvo do app e não são compilados por `swift test`) |
| NN-08 | `omp/nn08-onboarding-opml` | Ação "Importar OPML" no primeiro contato pelo mesmo fileImporter/preview/commit do gerenciamento de fontes; o gate se retira e volta; cancelar não escreve nem conclui | a preencher |

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

Caminho: `main` → branch `integration/apply-reports-2026-10-15` (criada de `801f017d`) recebe os
cinco merges; `main` avança por `--ff-only` para o topo dela depois do verdict. Verificação de
pré-publicação planejada sobre a árvore integrada: `swift build`, `swift test`, `git diff --check`.

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

## 4. Achados que ficam para a próxima rodada

- **TX-05** só é implementável quando existir contrato de fato temático por história *antes* de
  Selection; introduzi-lo exige um gate próprio (fora da allowlist aprovada).
- **TX-07** documenta uma divergência real de F03: `SelectionEngine` ordena pelo valor da data sem
  distinguir `CandidateTimestampKind.authored` de `.observed` — uma história sem data de publicação,
  observada hoje, ultrapassa uma notícia publicada ontem.
- **TX-11 (residual)**: o chip de nível do controle de descoberta
  (`ReaderDiscoveryControls.swift:203-213` via `FeedRecommendationDefinition.topicLabel`) ainda
  mostra "Menos" para o mesmo `.less` que a ação do convite agora declara como exclusão — é
  exatamente a "distinção futura" que PD-11 difere.
- **NN-06**: o arquivo `Sources/FeedMineRuntime/BackgroundFeedRefresh.swift` perdeu o cabeçalho
  estrutural (`File/Module/Owns/Does not own`) que os arquivos implementados do módulo mantêm
  (`FeedSession.swift:1-4`, `RunwayController.swift:1`). Desvio de forma, não de comportamento —
  decidir se a integração exige restaurá-lo.
