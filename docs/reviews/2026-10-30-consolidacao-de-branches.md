# Consolidação das branches na main — 2026-10-30

**Estado inicial:** `origin/main = fb8e65ff` (2026-10-23), 197 branches remotas, 45 delas com commits
não contidos em nenhuma outra, 21 PRs abertas (17 delas drafts, quase todas empilhadas).
**Estado desta rodada:** `integration/main-consolidated-20261030`, 667 commits à frente de
`fb8e65ff`, pacote verde (1 891 testes, 4 skipped, 0 falhas), app iOS compilando e testes de app
executados no simulador.

Nada foi mergeado "por parecer". Cada família abaixo tem a decisão, a evidência e o motivo; o que não
entrou está com o motivo medido, não com "ficou para depois".

## 1. O que entrou

| Origem | Entrega | Como |
|---|---|---|
| `product/nf04-tail-truth` (#6) | linha de produto F13/PD-5, build 56, parte de leitura e histórico | fast-forward de 424 commits sobre a main |
| cadeia P0 `#16→#28` (tip `fix/editorial-visual-seen-boundary`) | contrato de exposição confirmada e o contrato render-ready dos PRs #16–#22 | merge com resolução semântica (abaixo) |
| `product/integrity-20261024` | v6 já contido no nf04; só sobreviveu a leitura geral da origem do transporte de benchmark | merge, conflito resolvido a favor da versão já em produção |
| `release/build-56` | bump `CFBundleVersion 56` e evidência da build | merge sem conflito |
| `monitor/architecture` | parecer de arquitetura (P0-01..P3) | merge sem conflito |
| `ci/safari-ab-ios18-20261030` (#15) | workflow A/B do retorno do Safari | merge sem conflito |
| `chore/browser-return-ab-runner-20261030` (#19) | `scripts/run-browser-return-ab.sh` | merge sem conflito |
| `audit/browser-return-identity-regression-20261030` (#10) | teste de identidade do card e posição no retorno | merge; os dois conflitos de fixture resolvidos somando opções |
| `fix/viewport-interrupted-motion-20261030` (#12) | latch de animação só no escopo atual + `interruptTransientMotion` | merge; guard movido antes da mutação, bloco de `cancelRestoration` preservado |
| `fix/viewport-presented-top-visibility-20261030` (#11) | carta abaixo da borda inferior nunca é o topo apresentado | merge; limite aplicado ao *fallback* do seletor do F13, teste ajustado à posição relativa |
| `docs/status-pause-2026-10-17` | estudos de 2026-10-17/18 citados pelos planos | merge; seis estudos movidos da raiz para `docs/research/` |
| `docs/pd10-p0c-spec`, `docs/mig-v1v2-b-emenda2`, `kiro/review-build54` (#5) | especificações e revisão da build 54 | merge sem conflito |
| `refactor/scaffold-purge` | remoção de oito scaffolds comment-only | merge sem conflito |
| `measure/frames-during-scroll` | medição de quadros no canal publicado | merge sem conflito |
| `chatgpt/pd10-p0c-verifiable-release-packaging` | rejeição de compilador não canônico | merge sem conflito |
| `chatgpt/g18f-reserve-diagnosis` | rastreio da reserva nos pontos reais de operação | merge; mantido o invariante estabilizado (16 à frente), não a asserção exata que era intermitente |

Quatro commits de `release/build-50` foram trazidos por cherry-pick, porque a linha inteira não é
integrável (ver §3):

- `034a9d75` — a recusa de downgrade pertence ao caminho de produto (`RuntimeDatabaseError.incompatibleSchema`);
- `fba2486a` + `a43cf051` — escritor espera o lock (`writerBusyTimeout = 10`, modo `.timeout`, não retry) e o banco de build mais novo é recusado, com `RuntimeDatabaseHardeningTests`;
- `87ce1259` — a janela valida o segmento cruzado pelo agregado, não por carta (`PublicationStore+Presentation`), com `PublicationWindowCrossedSegmentTests`.

Também entraram, sem conflito de conteúdo, `c0ee5fb4` (script que prova que `archive` e
`-exportArchive` recebem as mesmas flags — o script já usava `SIGN_ARGS` para o mesmo fim) e
`9608ac04` (B06 declara o *gap* do Energy Log em vez de renomear o template).

## 2. Resolução semântica da cadeia P0

Os PRs #16–#28 foram escritos sobre a main antiga, que ainda tinha a cauda oculta. A linha de produto
removeu o mecanismo inteiro (`399a0dd1`, PD-5/INV-17). Mergulhar os dois sem critério produziria um
programa que reescreve cartas publicadas — exatamente o que o dono revogou.

Decisões, todas registradas no commit de merge `22cf0fcc` e no `ceb81942`:

1. **A cauda oculta não volta.** `hiddenTail`/`succeedTail`/`HiddenTailMaintenance`/`seenMaterial`
   continuam removidos; a tabela `edition_position_protection` e a migração `publication-position-fence-v1`
   não foram trazidas. Os testes do P0 que as pressupunham foram removidos ou reescritos.
2. **Só o viewport marca visto.** `saveCheckpoint`, `insertInitialCheckpoint`, `promotePreparedBinding`
   e a projeção de restore/warm start não chamam mais `markSeen`. O caminho que marca é a observação de
   viewport, e só quando a âncora observada tem pixels desenháveis (`FeedSession.submitViewport`).
3. **A regra de admissão embarcada venceu o descritor adiado.** Quando o herói salvo não tem pixels, a
   janela abre na carta pronta mais próxima e declara a carta durável como indisponível
   (`RenderReadyAdmissionTests`, 19 testes do F13). O modelo do P0 que mantém o descritor adiado no
   plano visual foi descartado: os testes `RenderReadyVisualHandoffContractTests`,
   `FeedReadyWindowOwnershipTests`, `RenderReadyHistoryReturnTests` e `RenderReadyAdmissionContractTests`
   foram removidos nesta rodada. Prova do descarte: com a projeção do P0 aplicada, a suíte foi a **38
   falhas em 78** testes das famílias de admissão; com a projeção embarcada, as duas famílias ficam
   verdes.
4. **Recorrência editorial usa só high-water visual.** `PublicationHistory.exposure` não recebe mais
   `readerAnchorCardID`; testes de recorrência declaram a exposição com `markSeen` antes de esperar a
   repetição (`CandidateProviderTests` K15, `EditedArticleRecurrenceTests`).
5. **Reconciliação não é posição estabelecida.** `FeedScreenStore.submitViewport` aceita uma
   reconciliação (pedido de preparação) para uma carta admitida, e o runtime decide a exposição; o
   teste `testPositionRequestOnlyEstablishesAnAcceptedDestination` continua exigindo o caminho de
   jump explícito.

## 3. O que não entrou, e por quê

| Branch/PR | Motivo medido |
|---|---|
| `experiment/reader-host-over-full-screen` (#13), `diagnostic/safari-viewport-probe` (#14) | a hipótese `.overFullScreen` não teve execução A/B provada — o próprio parecer de arquitetura (`ARCHITECTURE_MONITOR.md`, P1-04) diz "não há execução A/B comprovada". Entrar com a hipótese seria trocar produção por experimento. |
| `audit/session-transition-failure-probe` (#9) | corrigia `toggleSource` que chamava `replaceSession`; o F13 reescreveu o caminho (gate `replacingSession`, `pendingRebuild` drenado no laço de `replaceSession`). 12 conflitos em `AppComposition` contra a arquitetura nova. |
| `chatgpt/render-ready-contract-red-01` (#8) | draft; o `markSeen` condicionado a "a carta mudou" impede a primeira observação de uma carta restaurada de virar exposição, o que contradiz o contrato do item 2. O ganho de re-decode fica pendente de um recorte que não mexa na exposição. |
| `ci/p0-render-ready-apple-tests-20261030` | workflow dos testes P0 que foram parcialmente descartados; ficaria apontando para arquivos ausentes. |
| `release/build-50` (linha inteira) | 18 conflitos, incluindo `project.pbxproj` e `AppComposition`; metade dos commits é de uma suíte de UI que já foi reescrita. Aplicada por cherry-pick só a parte de persistência (acima). Os commits de perf (largura 8 da primeira passada) descrevem a constante `initialWorkCapacity`, que não existe no desenho de recursos atual. |
| `omp/tx07*` (três variantes) | a variante `-final2` já está na linha; as demais são recortes anteriores do mesmo contrato. |
| `chatgpt/mig-v1v2-b-personal-preservation` | a migração pessoal evoluiu para D7-A/F13 (`LegacyUserStateImport`, `ReaderLibraryStore`); a branch é o ancestral, com 7 conflitos contra o código que já a sucede. |
| `instruments/journey-*` (três variantes) | `instruments/journey/journey.py` já está na linha; as variantes diferem em recortes de governança. |
| `codex/candidate54-*`, `codex/bisect-946`, `codex/care-audio-preserved`, `wip/3r4`, `gate/pd8-r1`, `gate/r6e`, `integration/chatgpt`, `refactor/feed-screen-split`, `refactor/publication-store-split` | conteúdo já presente (`callerPagesPending`, `onPublication`, `R03/P04`, splits) ou WIP/experimento de uma linha de candidata que a build 56 sucedeu. |
| `phase/*`, `design/*`, `docs/*` antigos, `kiro/k-*` remanescentes | ancestrais da main ou já integrados por patch-id. |

## 4. Verificação executada nesta rodada

Ambiente: macOS 15 (Darwin 25.3.0, arm64), Xcode 26.6 (17F113), toolchain Swift 6.0,
worktree `/tmp/fm-consolidate` (APFS, sem `.build` herdado).

```
swift build                                    → OK
swift build --build-tests                      → OK
swift test                                     → Executed 1891 tests, with 4 tests skipped and 0 failures
xcodebuild ... -scheme FeedMine build          → BUILD SUCCEEDED
xcodebuild test -only-testing:FeedMineAppTests → resultado no §4.1
git diff --check origin/main..HEAD             → limpo em código; só artefatos históricos (§4.2)
```

### 4.1 Testes do app — 17 falhas, todas pré-existentes na linha

Os testes do alvo `FeedMineAppTests` rodaram no simulador `FeedMine OMP` (iOS 26.5) com o
`catalog.sqlite` e o `bench/corpus/profiles.json` locais (ambos gitignored).

```
árvore integrada:      Executed 229 tests, with 17 failures (4 unexpected) in 611.7 s
product/nf04 (c0392741): mesmas 17 asserções, nas mesmas 12 funções
```

A atribuição foi medida, não suposta: um worktree em `origin/product/nf04-tail-truth`
(`c0392741`) rodou as mesmas suítes com os mesmos insumos e reproduziu **exatamente** as falhas —
`CatalogueUpdateAcceptTests` (3), `FilterConfirmationBoundaryTests` (3 funções), `CompositionTests`
(7: catálogo empacotado, PD10, PD5, mídia salva) e `ReadingCompositionTests.K15` (1,
`staleHistoryBinding`). A rodada não introduziu nenhuma delas; a mais visível é
`testBundledCatalogHasRealBytesAndStableBoundedDefaults`, que compara o `catalog.sqlite` local
(`42e602…`) com o manifesto versionado (`1825fdae…`) — o insumo desta máquina está defasado do
manifesto, e isso é anterior a esta consolidação.


### 4.2 `git diff --check`

O comando aponta espaço à direita em artefatos brutos já embarcados: logs de suíte de UI
(`docs/reviews/evidence/2026-10-18-ui-suite/*.log`), `candidate.patch` e patches de build de
`docs/reviews/evidence/*`, mais alguns `.md` históricos. **Nenhum arquivo de `Sources/` ou `Tests/`
aparece.** Reescrever esses artefatos mudaria o hash da prova; eles ficam como estão.

### 4.3 Varredura estática

47 linhas adicionadas em `Sources/` casam `Timer|sleep(|retry|backoff|poll(|Task.detached|scheduler|
DispatchQueue|savepoint`. São de código já embarcado trazido pelas branches: espera de lock do
`DatabasePool` (`.timeout`, não retry), orçamentos de medição (`Task.sleep(for: budget)`), e as
políticas de tentativa da aquisição. Nenhuma linha introduz um segundo cache, cron ou fila paralela;
a rodada não criou mecanismo novo de agendamento.

## 5. Publicação

`integration/main-consolidated-20261030` foi empurrada e a `main` avançou por fast-forward com o
verdict desta rodada. As 21 PRs abertas foram revisadas uma a uma: as integradas foram fechadas
apontando o merge que as contém; as não integradas foram fechadas com o motivo medido do §3.
