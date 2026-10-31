# FeedMine V2 — Implementation Plan do restante após avaliação do build 53

> **For agentic workers:** usar `superpowers:executing-plans` para executar por tarefa, sequencialmente. Este plano é uma revisão do restante, não reinício de R00–R23. Checkboxes são trabalho pendente; nomes de testes novos são contratos propostos. Preservar trabalho já entregue e obter uma prova vermelha discriminante antes de corrigir cada lacuna.

**Goal:** corrigir as lacunas reabertas pela avaliação do build 53, conectar busca/diversidade e certificar uma única candidata nas jornadas e cargas exigidas.

**Architecture:** manter os owners atuais. Conclusões de rede/mídia acionam o executor causal existente; toda navegação passa pela prontidão; aposentar o transporte inclui todos os produtores que podem usá-lo. Busca consulta autoridades locais fora da UI; diversidade lê fatos congelados da publicação. Sem runtime, scheduler genérico, cache semântico ou motor de busca paralelo.

**Tech Stack:** Swift 6, SwiftUI, actors/structured concurrency, GRDB/SQLite, XCTest/XCUITest e instrumentos/harness existentes.

**Spec:** roteiro `2026-10-17-v2-fluidez-capacidade-entregas.md`; plano anterior `2026-10-17-v2-restante-implementacao.md`; `docs/product/PRODUCT_NORTH_STAR.md`, `docs/architecture/PRODUCT_INVARIANTS.md`, `CONTINUOUS_FEED_RUNWAY_DESIGN.md`, PRDs F11/F16/F21–F27 e benchmark congelado. Avaliação que fundamenta este plano: `docs/reviews/2026-10-18-v2-avaliacao-build53.md`.

## Base, escopo e decisões

Base: **`b0b961a049f82fece037363a6cb0e986d556330c`**, branch `codex/v2-fluidez-capacidade`, worktree `/Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2`. O checkout principal continua numa branch documental; não executar ali por engano.

25 commits e 59 arquivos avançaram desde o plano anterior. Preservar os contratos implementados de R00/R01/R02/R05/R08/R10–R15/R18/R19, corrigindo somente lacunas comprovadas. Reabrir partes de R03/R04/R06/R07/R09. R16 e R17 continuam parciais; R20 não se encerrou pelo rollback de preset; R21–R23 continuam sem aceite.

- A suíte Swift nova da auditoria passou: 1.481 executados, 3 ignorados, zero falhas. Isso não fecha jornada visual nem elimina os achados estáticos.
- O resultado novo de cinco testes nativos e seus artefatos estão na avaliação/manifesto da auditoria; consultar o resultado final, não inferir do agendamento.
- Há evidência histórica de 37 falhas/74 testes de UI, com seis skips. Não converter falha de fixture/ambiente em defeito de produto sem investigar, nem descartá-la sem prova.
- Decisão proposta para diversidade: garantir ordenação global consistente; não usar um comparador que muda de dimensões a cada par. Versões desconhecidas não recebem automaticamente o comportamento 5.
- Correção do escopo R20: catálogo substituível e runtime pessoal permanecem separados. **Não exigir uma transação SQLite única atravessando catálogo em arquivos e preferências pessoais.** A ativação do catálogo precisa de registro/pointer coerentes e recuperáveis no seu owner; transições de contexto têm contrato próprio de confirmação e recuperação.

## Global Constraints

- SQL, catálogo, leitura de volume, parsing, decode e produção fora do MainActor/callback visual; identificar o executor efetivo.
- Publicação congela identidade, conteúdo, ordem e geometria. Falha de pixel não remove card visível nem reescreve sua mídia como texto.
- Preservar single-flight, admissão+checkpoint e append transacionais, escritor SQLite serial, fences/CAS e ContextKey compatível.
- Preservar oportunidade foreground **≥10 s** somente ativo/visível e teto **2000 cartas** como guarda; não usá-los como metas de abastecimento.
- Preservar bootstrap 48/teto operacional 8 até evidência justificar revisão. Autorização explicitamente zero continua zero.
- Nenhuma Task ilimitada por evento/candidato; cada trabalho assíncrono tem owner, limite, autorização de novos starts e política de encerramento.
- Não alterar `bench/`, corpus ou avaliador congelados para obter aprovação. Novas cargas em `Tests/`; evidências fora do harness.
- Usar namespace de teste. Não apagar bancos/container pessoais, worktrees ou caches alheios.
- iOS pode suspender o processo; não prometer continuidade irrestrita ou horário exato de BGTask.
- Merge, push compartilhado e release não são etapas automáticas deste plano.

## Review Focus

1. Segunda conclusão chega depois que o primeiro drain retornou: publicar sem gesto/cadência — P02.
2. Close ocorre com fila de mídia maior que os slots ou connector ignora cancelamento: nenhum start usa URLSession invalidada — P01.
3. Voltar ao início, VoiceOver e reversão atingem bitmap liberado antes do callback: primeiro frame pronto; falha termina em indisponibilidade — P03/P04/P15.
4. Query válida está fora da primeira janela, tem negativos ou encontra storage indisponível: não confundir truncamento/falha com vazio — P07/P08.
5. Fatos editoriais ausentes, política desconhecida, morte durante ativação e falta de disco: ordem consistente, compatibilidade e recuperação verdadeiras — P09–P12.

## Ordem e gates

`P01 → P02 → P03 → P04 → P05 → P06 → P07 → P08 → P09 → P10 → P11 → P12 → P13 → P14 → P15 → P16`.

P07/P09/P11 são áreas separáveis após preservar os owners, mas integração continua serial nos arquivos compartilhados. Nenhum paralelismo editorial/publicação novo para acelerar o plano.

| Gate | Situação inicial | Condição de fechamento |
|---|---|---|
| G1 | Aberto | P03/P04/P05/P06 e jornadas P13/P15: navegação pronta, memória limitada e fronteira UI sem I/O |
| G2 | Reaberto | P01/P02/P05/P14: aposentadoria segura, acionamento tardio e capacidade adaptativa medida |
| G3 | Aberto | Busca ligada, diversidade durável, catálogo e jornadas P07–P13 completos |
| G4 | Aberto | Uma candidata com G1–G3, Release e B01–B06, incluindo físico e duração integral |

## Método para cada tarefa

1. Registrar HEAD/árvore e conferir se o código avançou. Se avançou, reconciliar antes de aplicar o plano.
2. Escrever as regressões indicadas nos targets dos owners; asserções devem alcançar a condição-alvo, com gates/continuações de teste. Timeout só é watchdog.
3. Rodar o filtro indicado: obter FAIL pela violação do contrato, não por build quebrado. Se já verde e discriminante, preservar e registrar comportamento presente.
4. Corrigir no owner indicado; executar o mesmo filtro e regressões afetadas. Esperado: zero falhas, nenhum caso excluído.
5. `git diff --check`; commit por entrega; registro `SHA inicial | vermelho/presente | alteração | verde | jornada | pendência | SHA final`.

Comandos base, da worktree de produto:

```sh
git rev-parse HEAD
git status --short
swift test --filter NomeDaClasse
xcodebuild -showdestinations -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination "$FEEDMINE_TEST_DESTINATION" -derivedDataPath "$FEEDMINE_DERIVED_DATA" \
  -resultBundlePath "$FEEDMINE_RESULT_BUNDLE" -parallel-testing-enabled NO \
  -testLanguage pt-BR -testRegion BR CODE_SIGNING_ALLOWED=NO \
  -only-testing:FeedMineAppTests/NomeDaClasse test
```

Obter destino atual e usar um `.xcresult` novo por rodada. A UI existente procura rótulos em pt-BR; casos ingleses exigem comando/expectativa próprios. Reutilizar DerivedData da execução, preparar recursos locais verificados e registrar hashes. Executar suíte ampla nos gates; não repetir 80 minutos de UI a cada mudança pequena.

## P01 — Aposentar todos os produtores antes de invalidar transporte

**Origem:** R05/R07/R20; achado A2. **Prioridade:** P1.

**Files:** `Sources/FeedMineAcquisition/AcquisitionCoordinator.swift`, `Sources/FeedMineRuntime/MediaPrefetcher.swift`, `Sources/FeedMineComposition/MediaPreparationOpportunity.swift`, `FeedRunwayDriver.swift`, `FeedMineApp/FeedMineApp/AppComposition.swift`; testes `AcquisitionCoordinatorTests`, `MediaPrefetcherTests`, `CompositionTests`.

**Interfaces:** manter `settleInFlight(budget:)` como resultado factual de drenagem, não autorização implícita para invalidar. MediaPrefetcher deve possuir seus trabalhos e uma operação explícita de aposentadoria que negue novos starts. `close()` coordena a vida do transporte compartilhado.

- [ ] Criar `testClosePreventsQueuedMediaFromStartingOnInvalidatedSession`: mais revisões que slots, primeira leva suspensa, close, liberação; nenhuma revisão seguinte acessa transporte inválido.
- [ ] Criar `testRetirementTimeoutDoesNotAuthorizeLateTransportStarts`: connector ignora cancelamento além do budget; o timeout não basta como fence.
- [ ] Rastrear trabalhos de mídia hoje lançados sem handle; negar novos starts no owner antes de drenar. Trabalho canônico válido já admitido pode permanecer; callbacks aposentados não publicam/instalam.
- [ ] Cobrir também plano de aquisição parcialmente iniciado e callback/result consumer suspenso. Invalidar somente quando o owner impedir novos usos; se houver lease de transporte remanescente, encerrá-la com política explícita e limitada.

**Verificação:** `swift test --filter AcquisitionCoordinatorTests`, `MediaPrefetcherTests`, Xcode `CompositionTests` para close e onboarding. **Aceite:** sem NSException, sem wait ilimitado, nenhum novo start após aposentadoria.

**Commit:** `fix(lifecycle): retire acquisition and media transport owners safely`.

## P02 — Acionar publicação por fatos tardios, com uma execução causal

**Origem:** R06/R07/R11; A1. **Prioridade:** P1. Depende de P01.

**Files:** `RunwayAcquisitionCycle.swift`, `FeedRunwayDriver.swift`, `MediaPreparationOpportunity.swift`, `AppComposition.swift`; testes `FeedRunwayDriverTests`, `ColdFeedBootstrapTests`, `MediaPrefetcherTests`.

**Interfaces:** preservar `RunwayAcquisitionRound`, notificação de supply/readiness e `causalExecution`. O owner conserva os recursos autorizados da oportunidade ativa; notificação reentra/coalesce no executor existente, não inicia outro loop concorrente.

- [ ] Criar `testSecondSourcePublishesAfterFirstDrainReturnedWithoutNewInput`: A publica, esperar retorno da oportunidade; só então liberar B. Exigir receipt de B antes de qualquer gesto/tick.
- [ ] Criar `testLateMediaReadinessPublishesAfterDrainWithoutCadence` e `testConcurrentLateFactsUseOneCausalPublisher`.
- [ ] Ligar conclusões posteriores ao primeiro yield e settlement/falha a uma reconsideração efetiva, com quantidade pendente limitada. Erro tardio não pode ficar guardado até um gesto futuro.
- [ ] Coalescer prioridades de mídia no MediaPrefetcher/owner atual em vez de uma Task ilimitada por slice. Medir máximo de trabalhos em cenário de rajada.
- [ ] Após deactivate/close ou troca de scope, fatos só atualizam o supply canônico permitido; nenhum acionamento reautoriza contexto aposentado.

**Verificação:** `FeedRunwayDriverTests`, `RunwayAcquisitionCycleTests`, `ColdFeedBootstrapTests`, `MediaPrefetcherTests`. **Aceite:** segunda fonte/mídia publica com usuário parado; contador de execução causal nunca excede um.

**Commit:** `fix(runway): drive late durable facts without gestures or cadence`.

## P03 — Uma fronteira de prontidão para todos os destinos

**Origem:** R03/R04; A3/A5. **Prioridade:** P1.

**Files:** `Sources/FeedMineUI/{FeedScreen,FeedNativeViewport,FeedVisualCapture,FeedInteractionPresentation}.swift`, `Sources/FeedMineRuntime/{FeedDestinationGate,FeedSession}.swift`; testes `RenderReadyAdmissionTests`, `FeedViewportCaptureTests`, `CardImageJourneyUITests` e UI de navegação.

**Interfaces:** o gate distingue pronto, preparando e preparo concluído indisponível sem depender de remover a carta. A sessão entrega fato explícito de falha/preparo do destino. Toda intenção de posição usa o mesmo caminho, inclusive Voltar ao início.

- [ ] Criar `testReturnToStartPreparesReleasedHeadBeforeApplyingPosition` usando a ação real da tela, não só o enum puro.
- [ ] Criar `testMissingDestinationAssetCompletesAsUnavailableWithoutRemovingCard`: remover asset, solicitar salto; encerrar pendingJump e informar falha mantendo identidade/âncora/geometria atuais.
- [ ] Auditar todas as atribuições a `capture.positionID` e navegação programática; impedir bypass do gate. Não supor que o setter de `scrollPosition` intercepta movimentos já ocorridos.
- [ ] Capturar primeiro frame do destino em reversão/VoiceOver com consumidor suspenso. Se a observação chega após exposição, controlar a transição antes dela pelo mecanismo nativo existente; uma nova banda preditiva não substitui a prova.

**Verificação:** classes Runtime/captura citadas e casos UI isolados com imagem real. **Aceite:** zero slot vazio no primeiro frame; destino irrecuperável termina de forma honesta e não gira/requisita indefinidamente.

**Commit:** `fix(navigation): enforce readiness across every destination path`.

## P04 — União real das bandas e decode limitado ao necessário

**Origem:** R03/R04; A4. **Prioridade:** P2.

**Files:** `FeedSession.swift`; `RenderReadyAdmissionTests`, `FeedSessionViewportTests` e ensaios de residência.

**Interfaces:** `boundedResidency` mantém a união de intervalos atual/anterior, e não o fecho convexo. Leitura e decode limitam-se aos IDs que efetivamente retornam; publicação fica intacta.

- [ ] Criar `testDistantJumpRetainsOnlyTwoDisjointBands` e `testDistantJumpDecodeDoesNotGrowWithDistance`. Para bandas sem sobreposição: `residentCount <= currentBand.count + previousBand.count`.
- [ ] Usar histórico com milhares de cartas/imagens; saltar extremos, contar bitmaps/decodes e repetir após trim de memória.
- [ ] Corrigir a proteção e a leitura do histórico para não reconstruírem o trecho entre as bandas. Não trocar isso por decode de toda a janela.
- [ ] Preservar P03, âncora, conteúdo/ordem e teto operacional de 2000 cartas.

**Verificação:** `RenderReadyAdmissionTests`, `FeedSessionViewportTests`, `ScrollAdmissionTests`; medir residência nos saltos. **Aceite:** custo de pixels não cresce com distância entre bandas.

**Commit:** `fix(residency): retain disjoint bands without decoding the gap`.

## P05 — Recursos adaptativos sem furar zero nem voltar I/O à UI

**Origem:** R01/R02/R09; A6. **Prioridade:** P2.

**Files:** `StageBudgetPolicy.swift`, `CollectionLaunchSettings.swift`, `AppComposition.swift`, testes `PipelineHeadroomTests`, `CollectionLaunchAndOrderingTests`, `CompositionTests`.

**Interfaces:** manter `StagePressureFacts`, `StageBudget`, recursos explícitos por oportunidade. Amostras de disco/capacidade vêm do executor do owner de recursos fora do MainActor, com invalidação por fatos; não introduzir polling genérico.

- [ ] Criar `testExplicitZeroAuthorizationRemainsZeroUnderEveryPressure`, `testResourceReadNeverPerformsFilesystemIOOnMainActor` e `testMeasuredUsefulCapacityChangesBudgetUnderSameSettings`.
- [ ] Preservar zero como negação. Justiça se aplica entre targets autorizados, não autoriza trabalho que o caller negou.
- [ ] Preparar fatos de recurso fora da UI; usar snapshot factual no ingresso/instalação. Perfilar as varreduras relacionadas à obtenção de recursos e preservar o membership preparado, sem reconstruí-lo por evento.
- [ ] Completar ajuste relativo a consumo, latência e rendimento útil; testar mesma configuração sob fatos diferentes. Bootstrap/tetos são fallback/segurança, não estratégia permanente. Dados ausentes permanecem desconhecidos.

**Verificação:** classes citadas; assertar ausência de I/O sob barreira de storage e comparar throughput/capacidade úteis. **Aceite:** zero preservado, recursos preparados e nenhum freeze de UI pelo getter de resources.

**Commit:** `fix(resources): preserve authorization and sample capacity off main actor`.

## P06 — Entregar metadados prontos pelo caminho real de instalação

**Origem:** restante R02; achado A10. **Prioridade:** P2.

**Files:** `PreparedFeedInstallation.swift`, `FeedPresentationHandoff.swift`, `AppComposition.swift`, `FeedScreenStore.swift`; testes `FeedPresentationHandoffTests`, `FeedScreenStoreTests`, `CompositionTests`.

**Interfaces:** preservar pacote e fence de `bookmarkMutationRevision`; o caller de produto prepara a metade de bookmarks antes de instalar nova apresentação. Relato só de work pode reutilizar metadados prontos. Nenhum segundo cache de bookmarks.

- [ ] Criar `testFirstProductionInstallationCarriesPreparedBookmarks`: usar launch/restore reais, não construir o pacote no teste; a primeira lista instalada já representa bookmarks duráveis.
- [ ] Criar `testBookmarkPreparationReadFailureIsNotSilentEmptyState` e preservar `testOldBookmarkPreparationCannotUndoConfirmedToggle` com conclusão invertida.
- [ ] Ligar a preparação fora do MainActor ao handoff real; hoje só testes constroem pacote com `bookmarks` e o overload de produto envia nil/agendando leitura depois.
- [ ] Não instalar um lado do pacote e só então tentar descobrir o outro. Falha de leitura preserva estado anterior ou apresenta recuperação explícita; não marcar vazio como confirmado.
- [ ] Evitar `BookmarkWindowKey` reconstruir todo o array de IDs por mudança apenas de posição: usar identidade/membership imutável já preparado, sem suprimir o handoff que alimenta o runway.

**Verificação:** classes citadas; gate de storage e uso real de launch/restore. **Aceite:** pacote preparado não é apenas fixture de teste, instalação não lê storage e metadados confirmados não regridem.

**Commit:** `fix(presentation): prepare bookmark metadata in the production handoff`.

## P07 — Backend de busca correto, paginável e com erro explícito

**Origem:** R14/R16; A7. **Prioridade:** P2.

**Files:** `FeedMineApp/FeedMineApp/ReaderSearchResults.swift`, `Sources/FeedMineDomain/ReaderSearchResults.swift`, `Sources/FeedMinePersistence/{LegacyCatalogReader,ContentStore*}.swift`, `SearchExpression.swift`; testes de catálogo/conteúdo e `CompositionTests`.

**Interfaces:** consulta assíncrona, executada fora do MainActor, consome `SearchContext`/semântica e scope completos; resultado distingue página completa/continuação e erro. Reutilizar o parser de expressão e autoridades existentes, sem segundo índice/motor.

- [ ] Criar `testSourceExpressionIsAppliedBeforeLiteralTruncation`, `testLocalMatchBeyondFirst400IsReachable`, `testSearchFailureIsNotEmptyResult` e `testUnifiedSearchPreservesLegacyLiteralSemantics`.
- [ ] Fontes: positivos em campos distintos, negativos, diacríticos e tags devem chegar à consulta. O LIKE da expressão inteira antes da interpretação não pode eliminar candidatos válidos.
- [ ] Artigos: preservar janela operacional limitada, mas permitir avançar por cursor até os resultados elegíveis; não tratar 400 como universo completo. Tornar a limitação/paginação observável.
- [ ] Salvos: consultar em lote, evitar uma leitura de card por ID quando a lista crescer. Não ocultar erro de banco/catálogo com `try?`.
- [ ] Preservar identidade/query de presets legados e origem real de cada resultado. Não prometer leitura de artigo sem card/corpo local navegável.

**Verificação:** `CandidateProviderTests`, `LegacyCatalogReaderTests`, testes de paginação e Xcode `CompositionTests`. **Aceite:** resultado fora da primeira janela é alcançável, gramática é consistente e falha não aparece como vazio.

**Commit:** `fix(search): query complete local scopes with bounded pages and explicit errors`.

## P08 — Conectar a superfície unificada ao leitor

**Origem:** restante R16 e jornadas R15. **Prioridade:** P2. Depende de P07.

**Files:** `ReaderShell.swift`, `ReaderSearchResultsStore.swift`, `FeedScreenStore.swift`, `FeedMineApp.swift`, `AppComposition.swift`; testes de Store, `CompositionTests`, `ReadingCompositionTests` e UI de busca.

**Interfaces:** `ReaderSearchResultsStore` continua dono apenas da apresentação/token. Host entrega páginas tipadas e executa destino pelos coordenadores existentes; nenhuma consulta síncrona no corpo da view.

- [ ] Criar `testReaderSearchShowsRealTypedSections`, `testNewTermOrScopeRejectsStaleUICompletion`, `testSearchResultDestinationsAndCancelRestoreOrigin` e `testSavedSearchReopensOfflineInSameScope`.
- [ ] Ligar submit/alteração de scope, loading, vazio, erro/retry e paginação à barra real. Resolver fonte não selecionada, salvo e artigo local; um enum de destino sem executor não conta como entrega.
- [ ] Fonte abre contexto interno; salvo/artigo abre o conteúdo real disponível. Voltar recupera consulta, cancelar recupera contexto/filtro/âncora anteriores. Preservar gravação versus ativação distinta de R15.

**Verificação:** testes de store/composição/leitura e jornada UI busca→resultado→voltar→cancelar, online/offline. **Aceite:** não restam apenas call sites de teste para busca unificada.

**Commit:** `feat(search): present unified local results in the reader`.

## P09 — Tornar o desempate editorial seguro antes de ativá-lo

**Origem:** parte R17; A8/A9. **Prioridade:** P2.

**Files:** `SelectionDiversity.swift`, `SelectionEngine.swift`, `SelectionDiversityTests.swift` e testes de política.

**Interfaces:** diversidade somente na versão explicitamente suportada (5 nesta base). Preservar versões 1–4 e tratar desconhecidas pelo contrato vigente. Mesmo peso/relevância deve produzir uma ordem estrita consistente.

- [ ] Criar `testUnknownSequencingVersionDoesNotEnableDiversity`, `testDiversityComparatorIsTransitiveWithMissingMetadata` e `testDiversityOrderIsInvariantAcrossInputPermutations`.
- [ ] Incluir o trio A/B/C descrito na avaliação e testar todas as permutações. Provar que não há ciclo `less(a,b) && less(b,c) && less(c,a)`.
- [ ] Substituir a escolha de dimensões por par por uma estratégia consistente para o conjunto de desempate. Proposta: dimensões comparáveis definidas para o grupo de mesma relevância, chave determinística e fallback estável; campo ausente não vira vantagem de novidade nem penalidade inventada.
- [ ] Sem contexto/fatos/alternativas, manter oferta publicável e ordenação legada. Registrar a decisão exata de desempate na política para revisão.

**Verificação:** `SelectionDiversityTests`, `SelectionEngineTests`, `SourceDiversityContractTests`, caracterizações temáticas/temporais. **Aceite:** versão desconhecida não ativa diversidade e a ordenação é consistente em oferta heterogênea/incompleta.

**Commit:** `fix(editorial): enforce explicit versions and consistent diversity ordering`.

## P10 — Persistir e ligar diversidade ao caminho real de publicação

**Origem:** restante R17. **Prioridade:** P2. Depende de P09.

**Files:** `EditorialDiversityFact.swift`, registros/coordenador/store de publicação, `RuntimeMigrations.swift`, `LocalProductionSlice.swift`, `AppComposition.swift`; testes de migração/publicação, `LocalProductionSliceTests` e editorial.

**Interfaces:** fatos mínimos opcionais/versionados congelados na mesma transação do segmento; histórico antigo desconhecido. `LocalProductionSlice` fornece `SelectionDiversityContext`; composição cria revisão da versão suportada, sem reescrever edições antigas.

- [ ] Criar `testPublicationFreezesEditorialFactsAtomically`, `testLegacyPublicationRemainsUnchangedWithoutDiversityFacts`, `testDiversityContextSurvivesRelaunch` e `testProductionActuallyPassesV5DiversityContext`.
- [ ] Não reconstruir assunto/provedor de ocorrência antiga usando a revisão canônica mais recente. Campos indisponíveis (geografia/formato) permanecem desconhecidos até haver autoridade legítima; não declarar cobertura dessas dimensões a partir de ausência.
- [ ] Testar seams entre segmentos, reabertura, homogêneo, falta de metadados e hash/ordem de segmentos anteriores. Ativar só o caminho que possui fatos coerentes e P09 verde.

**Verificação:** migração/store/publicação, `LocalProductionSliceTests`, editorial; B02 integrado em P16. **Aceite:** diversidade deixa de estar dormente e sobrevive a reinício sem alterar o passado.

**Commit:** `feat(editorial): wire durable publication diversity into production`.

## P11 — Ativação de catálogo recuperável e concorrência bem definida

**Origem:** R20 original, separado do conserto de preset já entregue. **Prioridade:** P2.

**Files:** `CatalogInstallation.swift`, `CatalogUpdater.swift`, stores/pointers de catálogo existentes e uso em `AppComposition.swift`; `CatalogInstallationTests`, `CatalogUpdaterTests`, `CatalogueUpdateAcceptTests`.

**Interfaces:** ativação no owner do catálogo produz uma decisão durável coerente de revisão/fingerprint/paths/contagens; registro/pointer recuperável é autoridade, auditoria adicional não inventa sucesso. Runtime pessoal permanece separado.

- [ ] Criar `testInterruptedActivationRestoresOneCoherentCatalogue`, `testConcurrentOffersCannotCommitOlderRevisionLast`, `testCatalogueAuditFailureDoesNotContradictActivePointer` e `testActivationPreservesPersonalSourcesAndHistory`.
- [ ] Examinar as escritas atuais de snapshot, previous/active pointer e ledger. Definir e testar o ponto de commit/recuperação entre elas, inclusive falha em cada escrita e morte real do processo.
- [ ] Serializar compare/commit no owner existente de forma efetiva entre os handles usados pelo app. Revalidar revisão e autoridade no commit, não apenas antes de materializar fora do lock.
- [ ] Repetir atualização/revogação enquanto a travessia R08 materializa. Catálogo novo altera futuras descobertas, não bookmarks, fontes pessoais ou publicação antiga.

**Verificação:** classes citadas; testes com dois handles, falha de I/O e reinício. **Aceite:** ativo antigo íntegro ou novo íntegro, sem híbrido; concorrência não instala revisão obsoleta.

**Commit:** `fix(catalog): commit recoverable catalogue activation outcomes`.

## P12 — Provar durabilidade e lifecycle no processo real

**Origem:** limites de R11/R12/R18/R20; F21/F23/F24. **Prioridade:** P2. Depende de P01/P02/P11.

**Files:** owners existentes de contexto, salvos e grants, apenas se a prova falhar; `CompositionTests`, `ReadingCompositionTests`, testes de mídia/retention e UI de relaunch.

**Interfaces:** confirmação durável precede reconhecimento; falha de ativação posterior é distinta de falha de gravação. Não aplicar o rollback de preset indiscriminadamente ao filtro já confirmado.

- [ ] Criar `testProcessDeathDuringPresetActivationRecoversDeclaredContext`, `testSavedArticleSurvivesForceQuitAndDisposableCachePurgeOffline` e `testGrantExpiryStopsNewStartsAndForegroundResumes`.
- [ ] Testar intenção confirmada, duas caixas, purge apenas de cache descartável, corpo parcial, arquivo removido e disco cheio. Novo handle no mesmo processo não substitui force quit/relaunch.
- [ ] Criar `testContextReturnCompletesWhileUnrelatedSourceIsStillSuspended`: concluir a navegação local antes de liberar a fonte alheia; timeout de rede não é mecanismo de conclusão. O caso atual passou em 61,248 s na auditoria e não prova esse contrato.
- [ ] A→B→A sob rede/mídia pendentes: reaproveitar bytes válidos, negar projeção antiga, conservar âncora; background não depende de grant num horário exato.
- [ ] Corrigir somente lacunas reproduzidas; preservar a implementação útil de salvos/controles e as provas existentes.

**Verificação:** pacote/composição relacionados e jornada de processo/dispositivo em namespace de teste. **Aceite:** bookmark, contexto e posição prometidos sobrevivem; disponibilidade não é inventada.

**Commit:** `test(durability): verify real process and grant interruption recovery`, com correções causais separadas.

## P13 — Resolver e classificar a suíte de UI vermelha

**Origem:** R21 e validação histórica com 37 falhas. **Prioridade:** P2.

**Files:** `ArticleReadingDiagnosisUITests.swift`, `FeedMineUITests.swift`, `AppearanceLegibilityUITests.swift`, `ReadingSurfaceUITests.swift`, casos de primeira abertura e suas superfícies reais. Confirmar o nome atual do arquivo/classe antes de editar.

**Interfaces:** pt-BR/BR explícitos onde a UI atual exige; IDs de máquina estáveis. Fixture, executor e produto são causas distintas, cada qual com evidência.

- [ ] Inventariar cada teste que falhou na corrida histórica: asserção, condição necessária, causa reproduzida, owner e evidência após correção. Não reportar 37 falhas como 37 defeitos distintos.
- [ ] Corrigir seletores ambíguos de “Salvar artigo” pelo card-alvo; fixture/catálogo/rede de testes devem ser declarados. Testes que exigem Modo Avião não podem passar simulando uma condição que não foi observada.
- [ ] Investigar largura iPad landscape 730>704 e gesto com salto sem deslocamento. Teste antigo que exige retirada de cards deve ser reconciliado à política vigente; não remover o contrato de posição, histórico ou pixels para esverdear.
- [ ] Repetir primeira experiência, fonte, busca, salvos, Dynamic Type e VoiceOver. Capturar estados e geometria necessários para distinguir fixture de falha do produto.

**Verificação:** casos UI isolados antes da suíte inteira; registrar PASS/FAIL/SKIP justificado por teste. **Aceite:** falhas essenciais resolvidas; indisponibilidade de infraestrutura obrigatória continua impedindo o gate correspondente.

**Commit:** `test(ui): reconcile fixtures and close reader journey failures`, com consertos de produto separados.

## P14 — Medir e completar headroom por estágio

**Origem:** R09/R10/R22. **Prioridade:** P2.

**Files:** `PipelineHeadroomTests.swift`, suporte de carga em `Tests/FeedMineCompositionTests/`, escala de persistence e instrumentos existentes fora de `bench/`.

**Interfaces:** medir admitidos/s, examinados/s, preparados/s e publicados/s separadamente, com demanda e recursos declarados. O ensaio atual de um append e uma admissão continua teste de consistência, não de throughput sustentado.

- [ ] Carga de **1.000+ fontes**, **10.000+ candidatos**, **100 fontes simuladas independentes**; comparar consultas de **100.000 linhas**. Incluir repetidos, falhas e mídia/latência variável.
- [ ] Criar `testUsefulStageHeadroomAtDeclaredDemand` e `testQueuesMemoryAndP95RemainBoundedWithSlowConsumers`.
- [ ] Referências: consumo **1 card/s**, rajadas **3 cards/s**; meta local **10×** nas unidades correspondentes. Para estágio que examina candidatos, declarar rendimento até card útil; não chamar 30 candidatos examinados de 30 publicados.
- [ ] Medir p95, backlog, Tasks, bytes residentes, tempo do escritor e demanda real. Comparar recursos disponíveis/pressionados na mesma configuração.
- [ ] Se a meta falhar, corrigir gargalo no owner ou registrar FAIL com causa; não elevar quotas fixas ou reduzir meta. Rede pública é ensaio distinto, sem SLA artificial de 10×.

**Verificação:** carga/escala e relatórios com corpus, hardware/OS, parâmetros, intervalos e contadores reais. **Aceite:** folga sustentada demonstrada; nenhum estágio mascara gargalo de outro.

**Commit:** `test(capacity): measure sustained useful stage headroom`.

## P15 — Validar exposição e fluidez em Release

**Origem:** G1, R03/R04/R21/R22. **Prioridade:** P2.

**Files:** scheme/configuração de teste somente se necessário, instrumentos existentes, jornadas de imagem/gesto/acessibilidade e evidências. Não alterar avaliador.

**Interfaces:** artefato precisa ser realmente Release e trace lido do arquivo real correlacionado à janela de gesto. `-configuration Release` com test action compilando Debug não certifica Release.

- [ ] Preparar rota verificável de build/execução Release; registrar SHA, configuração, flags, dispositivo e arquivo real de trace. Corrigir o bloqueio de instrumentação anterior sem afrouxar métricas.
- [ ] Exercitar reversão rápida, salto ao início, destino irrecuperável, VoiceOver, memória e produtores pausados/ativos. Medir primeiro frame e posição, não só enum `ready` em unitário.
- [ ] Comparar hitches, latência e stacks sob produção real. Ausência de frames/trace = NOT_MEASURED; percentual menor não encerra defeito perceptível.

**Verificação:** jornadas P03/P04/P13 na candidata Release; correlação de eventos/frames e inspeção de stacks. **Aceite:** G1 comprovado com desenho real e leitura protegida, sem extrapolar de Debug.

**Commit:** `test(release): record native exposure and responsiveness evidence`.

## P16 — Candidata única, simplificação comprovada e B01–B06

**Origem:** R23, G2–G4.

**Files:** registro novo de execução, evidências e owners onde mecanismos substituídos forem comprovados; `bench/` intacto.

**Interfaces:** uma candidata/SHA por avaliação; novo fix exige repetir os ensaios afetados e registrar a troca de SHA.

- [ ] Remover Tasks/timers/call sites mortos após provar substituição. Preservar regressões úteis e compatibilidade; nenhuma meta de linhas removidas.
- [ ] Rodar suíte Swift, nativos e UI aplicáveis, build e revisão independente da branch integrada. Achados importantes: vermelho→correção→verde.
- [ ] Executar B01–B06 pelo documento/harness congelados, com hashes de corpus/avaliador. B03: **30 minutos de avanços efetivos**, **1 card/s**, rajadas **3 cards/s por 20 s a cada 5 min**. App aberto/parado não satisfaz.
- [ ] B06 inclui iPhone físico compatível, corpus suficiente e recursos registrados. Repetir A→B→A, readiness tardio, memória e offline na mesma candidata.
- [ ] Consolidar uma única tabela atual G1–G4/B01–B06 com PASS/FAIL/NOT_RUN/BLOCKED/NOT_MEASURED e artefato por cláusula, preservando o histórico sem contradição de estado atual.
- [ ] Confirmar `git diff b0b961a0 -- bench/` vazio e árvore de evidências íntegra. Sem físico, corpus ou trace obrigatório, certificação fica aberta; não declarar aceite/release.

**Verificação:** `docs/IOS_RUN.md`, `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md`, comandos oficiais e revisão da candidata. **Aceite:** todos os contratos e requisitos obrigatórios têm prova correspondente, não apenas commit/teste nomeado.

**Commit:** `test(acceptance): certify integrated candidate with traceable evidence`.

## Cobertura do restante e definição de encerramento

| Parte antiga | Destino novo |
|---|---|
| R00/R13/R14 e correções úteis já entregues | Preservar; regressão final em P16 |
| R01/R02 | Preservar; recursos em P05, pacote pronto em P06 e desenho em P15 |
| R03/R04 | P03/P04/P15 |
| R05/R06/R07 | P01/P02 |
| R08 | Preservar; concorrência e catálogo em P11 |
| R09/R10 | P05/P14 |
| R11/R12/R15 | P08/P12/P13 |
| R16 | P07/P08 |
| R17 | P09/P10 |
| R18/R19 | Preservar; jornadas P12/P13/P15 |
| R20 | P01/P11/P12, respeitando separação catálogo/runtime |
| R21 | P13/P15 |
| R22 | P14/P15 |
| R23 | P16 |

A próxima execução começa por **P01/P02**, depois fecha **P03–P06**. Não começar pela superfície de busca ou pelo aumento de paralelismo enquanto aposentadoria, acionamento tardio e exposição ainda violarem contratos.

Conclusão de implementação e certificação são estados distintos. Não reabrir tudo indiscriminadamente; não considerar completo um owner só porque os testes atuais passam. Este documento é o plano do restante identificado na base avaliada, não alegação de execução das tarefas P01–P16.
