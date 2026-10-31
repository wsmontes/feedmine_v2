# FeedMine V2 — Plano de implementação: fluidez, capacidade e entregas

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans para executar por tarefa; usar superpowers:subagent-driven-development somente se escolhido pelo responsável. Passos com `- [ ]` registram trabalho ainda não executado.

**Goal:** manter a leitura local estável enquanto aquisição, preparação, seleção e persistência progridem com folga, fechando as lacunas funcionais levantadas em 17/out.

**Architecture:** preservar supply canônico, publicação imutável, FeedSession, RunwayController e seus coordenadores. Retirar produção do caminho visual; permitir progresso por resultado durável, com trabalho limitado e prioridades atualizáveis. A UI instala valores prontos; nenhum novo motor paralelo.

**Tech Stack:** Swift, SwiftUI, structured concurrency/actors, GRDB/SQLite, XCTest/XCUITest, instrumentos e benchmark existentes.

**Spec:** `docs/product/PRODUCT_NORTH_STAR.md`, `docs/architecture/PRODUCT_INVARIANTS.md`, decisões e PRDs vigentes; estudos `docs/reviews/FEEDMINE_{INTENTIONS_VS_DELIVERIES,SCROLL_ARCHITECTURAL_STUDY,BACKEND_HEADROOM_KERNEL_AUDIT}_2026-10-17.md`. As chaves nessa última notação representam os três arquivos separados.

## 1. Base, alcance e autoridade

Inspeção estática em 17/out/2026, Victoria. Main: `5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`. Candidata examinada: `integration/51@8fcfe37` (build 51). Comparação local: 74 arquivos, 3.676 inserções, 289 remoções entre main e candidata. Nenhum build, teste, benchmark ou perfil de desempenho foi executado para este plano. Resultados anteriores continuam históricos, não certificam esta árvore.

Lidos como contexto os anexos Blueprint v0.3/v0.4, Runtime V2, Sobre o FeedMine e estudo de diferenciação. O estudo de mercado não determina implementação nem foi revalidado como pesquisa atual. Para detalhes executáveis, prevalecem decisões de produto vigentes no repositório e instruções atuais do dono; o plano não reabre arquitetura por causa de um rascunho antigo.

Este é o roteiro conjunto solicitado, com entregas separáveis. Não é autorização para implementar tudo de uma vez, alterar a régua de aceite ou publicar release. O monitor publica documentação; produção permanece em branches de implementação.

### Global Constraints

- UI consome apresentação local pronta. Captura mínima e layout nativo continuam no MainActor; SQL, decode, seleção e produção não pertencem ao callback visual nem à instalação da lista.
- `async` não demonstra isolamento. Cada caminho deve declarar seu executor/ator e não carregar trabalho síncrono pesado de volta à UI.
- Publicação congela identidade, conteúdo, ordem e geometria. Readiness tardia não muda uma ocorrência publicada; cancelamento não substitui validação de escopo.
- Preservar transação de admissão + checkpoint, single-flight por alvo, CAS/fences existentes e escritor serial do SQLite.
- Sem quotas fixas de fontes/cards como estratégia. Limites de segurança e transporte permanecem; capacidade e retenção respondem a fatos de consumo e recursos.
- Preservar explicitamente a emenda de 17/out em `CONTINUOUS_FEED_RUNWAY_DESIGN.md`: oportunidade de foreground a cada **≥ 10 s**, apenas ativo/visível; teto de **2000 cartas** como guarda de memória. Não usar nenhum dos dois como alvo de abastecimento nem remover silenciosamente a decisão do dono.
- Não criar outra fila genérica, scheduler, cache, seletor, geração ou runtime. Estado derivado mínimo só dentro do owner responsável e com invalidação definida.
- Não modificar `bench/` ou seu avaliador para acomodar implementação. Novos testes de capacidade vivem em `Tests/` e evidências em `docs/reviews/evidence/`.
- Conferir os estudos Apple existentes (`docs/research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md`, F21/F23/F24). Nada pressupõe execução contínua quando iOS suspende o app.

### Review Focus

1. Retorno rápido sobre cards cujos pixels foram liberados: não expor slot vazio, retirar card visível nem saltar âncora (T3).
2. Resultado antigo termina depois de A→B→A: reutilizar bytes válidos, não instalar apresentação da sessão errada (T4/T7).
3. Uma fonte nunca responde e um callback fica suspenso: outras fontes e publicação continuam, filas permanecem limitadas (T4/T5).
4. Disco cheio, arquivo removido e morte do processo entre commits: não perder bookmark, contexto confirmado ou posição prometida (T7/T8).
5. Oferta homogênea, metadados ausentes ou rede offline: não inventar diversidade, novidade ou disponibilidade, nem rodar em loop (T6/T10/T12).

## 2. O que mudou desde os pareceres

| Tema | Evidência na candidata | Decisão do plano |
|---|---|---|
| Aprendizagem no foreground | `RunwayController.swift:291` retorna se scope é o mesmo | Preservar e testar pelo caminho de composição; não reimplementar |
| Downgrade de mídia publicada | `PresentationCard.swift`, `isRenderReady` e projeção já não convertem imagem em texto | Achado antigo parcialmente resolvido; revisar residência/readmissão em T3 |
| Aquisição de apenas dois alvos | `AppComposition.swift:2190` usa `CollectionLaunchSettings`; default de plano 48, teto executor 8 | Não repetir o diagnóstico literal antigo; falta adaptação e independência entre estágios |
| Slot aguardando callback | `AcquisitionCoordinator.swift:153–171`, `onResult` antecede reposição | Continua aberto, T4 |
| Driver aguarda rodada HTTP | `FeedRunwayDriver.swift`, `driveCausalEffects` aguarda `executeAcquisition` | Continua aberto, T4 |
| Mídia antes de slice | Mesmo driver aguarda `prepareMedia` antes de `localProductionSlice.run` | Continua aberto, T5 |
| Trabalho na fronteira UI | `AppComposition.swift:1842–1847` cria Task por observação; `:2757` consulta bookmarks no install | Continua aberto, T2 |
| Descoberta percorre histórico | `ReaderDiscoveryTraversal.swift`, `advance/adopt/targets/connector` percorrem páginas sob lock | Continua aberto, T6 |
| Busca literal | `CandidateProvider.swift:84–93` procura query inteira | Continua aberto, T9 |
| Neutral vira exclusão | Agora localizado em `ReaderDiscoveryPool.swift:53–65`, ramo else de `.more` | Continua aberto; corrigir o owner atual, T9 |
| Fluidez, filtros, salvos | Melhorias presentes na candidata | Validar integração e completar jornadas, sem cherry-pick repetido |

**Diagnóstico:** há progresso real, mas mais paralelismo dentro de cada peça não remove as esperas entre peças. A solução é separar disponibilidade de recursos, conclusão durável e publicação; não simplesmente aumentar 48 ou 8.

## 3. Contrato de execução desejado

| Owner | Entrada | Trabalho permitido | Saída |
|---|---|---|---|
| FeedScreen/FeedScreenStore | Gesto, posição, ação explícita | Captura pequena; apresentação local | Observação com identidade/posição e intenção |
| FeedSession | Observação/admissão válida | Posição, projeção, durabilidade sob seu isolamento | Snapshot coerente e posição confirmada |
| RunwayController/FeedRunwayDriver | Consumo, supply/readiness/recursos alterados | Planejar trabalho limitado e ordenar efeitos por escopo | Intents para owners existentes |
| AcquisitionCoordinator | Plano elegível | Rede concorrente limitada; admissão transacional | Resultado durável individual, sem esperar rodada |
| MediaPrefetcher | Prioridades de candidatos | Preparação/decodificação fora da UI | Readiness por item; itens prontos ficam elegíveis |
| SelectionEngine/LocalProductionSlice | Supply pronto + política + histórico | Selecionar/ordenar futuro, publicar append | PublicationReceipt imutável |
| Instalação UI | Projeção e metadados prontos | Validar identidade e trocar valor necessário | Desenho sem I/O |

Rede não espera decode; publicação de A não espera HTTP de B; pronto não espera pendente. Commit durável continua serial quando a consistência exigir. Uma troca de filtro altera a prioridade futura e a autorização de instalação, não apaga supply ou bytes reutilizáveis.

Não confundir três reservas: candidatos locais, publicações duráveis e pixels residentes. Milhares de candidatos não exigem milhares de bitmaps em RAM. Para qualquer destino que a UI possa revelar imediatamente, sua apresentação deve estar pronta antes da exposição — não apenas após o callback do viewport.

## 4. Sequência e gates

`T1 → T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10 → T11 → T12` é a ordem recomendada de integração. T6 pode ser desenvolvido após T4; T8/T9 não exigem conclusão editorial de T10. Integração continua serial para não disputar os mesmos owners.

- **G1, após T3:** gesto isolado de trabalho de produção e apresentação visual íntegra.
- **G2, após T6:** aquisição/preparo/publicação progridem independentemente e com orçamento adaptativo.
- **G3, após T11:** contextos, offline, controles e descoberta cumprem suas promessas.
- **G4, T12:** candidata única validada em jornadas reais e benchmark congelado.

Cada tarefa termina com um commit próprio; separar teste vermelho e correção quando o fluxo vigente exigir. Não iniciar nova arquitetura enquanto uma tarefa está aberta sem bloqueio identificado. Ao falhar gate, corrigir a causa nesse owner; não criar mecanismo compensatório em outro.

### T1 — Fixar a candidata e reconciliar o que já existe

**Arquivos:** criar `docs/reviews/2026-10-17-v2-plan-execution.md`; revisar `Tests/FeedMineRuntimeTests/RenderReadyAdmissionTests.swift`, `Tests/FeedMineCompositionTests/FeedRunwayDriverTests.swift`, `FeedMineApp/FeedMineAppTests/CompositionTests.swift` e regressões existentes de runway.

**Interfaces:** consome os SHAs acima; produz uma base de implementação registrada, com cada correção classificada como presente/ausente/validada. Nenhuma API nova.

- [ ] Registrar HEAD, ancestrais relevantes e alterações locais do implementador; comparar novamente com main e integration/51 antes de editar.
- [ ] Executar os testes existentes de render-ready, runway, filtros e salvos na candidata; não atribuir falha ambiental ao produto.
- [ ] Acrescentar teste de composição apenas se faltar: consumo conhecido → inativo → foreground mesmo scope conserva aprendizagem; mudar scope reseta. O teste deve passar pelo host real, não chamar apenas `activate`.
- [ ] Registrar quais testes já passam e quais defeitos permanecem. O downgrade antigo não deve ser recriado para produzir vermelho.
- [ ] Commit: `docs(plan): reconcile build 51 and preserve verified fixes`.

### T2 — Retirar trabalho da fronteira do scroll

**Modificar:** `Sources/FeedMineUI/{FeedScreen,FeedScreenStore,FeedNativeViewport,FeedInteractionPresentation}.swift`, `Sources/FeedMineRuntime/FeedPresentationSnapshot.swift`, `Sources/FeedMineComposition/FeedPresentationHandoff.swift`, `FeedMineApp/FeedMineApp/AppComposition.swift`.
**Testar:** `Tests/ArchitectureSmokeTests/{FeedViewportCaptureTests,FeedScreenStoreTests}.swift`, `FeedMineApp/FeedMineAppTests/CompositionTests.swift`.

**Interfaces:** manter `FeedRunwayDriver.submitViewport` e sua evidência causal. O contrato da observação carrega identidade de projeção/escopo e âncora; membership completo deve ser preparado quando a lista muda, não copiado por evento. O payload instalado deve trazer bookmarks coerentes, preparados pelo owner existente fora do MainActor.

- [ ] Criar regressões `testScrollIngressDoesNotAwaitProducer` e `testInstallDoesNotReadDatabase`: suspender produção/armazenamento por barreira controlada e demonstrar que captura/instalação pronta não os invocam.
- [ ] Criar `testMovingObservationsRemainBoundedAndPreserveRest`: rajada de posições com consumidor bloqueado; manter última posição e fatos semânticos de repouso/background/exposição necessários. Não descartar avanço real usado pelo runway.
- [ ] Verificar vermelho e registrar a cadeia callback → store → composição → sessão → install, com isolamento efetivo de cada chamada.
- [ ] Substituir Task por callback por um único consumo de observações pendentes no owner existente. Coalescer somente posições substituíveis; não construir fila ilimitada nem timer. Preservar sequência/proveniência atuais e checkpoints.
- [ ] Preparar membership/bookmarks e diferenças materiais fora da UI. Remover SQL de `FeedAssociation.install`; mover a leitura, não adicionar um segundo cache de bookmarks. Atualizações de bookmarks concorrentes precisam invalidar a projeção antiga pela autoridade existente.
- [ ] Verificar que posição sem mudança material não invalida a lista; não suprimir o handoff que sustenta produção, erro já registrado no código.
- [ ] Executar `swift test --filter FeedViewportCaptureTests` e `swift test --filter FeedScreenStoreTests`, testes de composição pelo Xcode e jornada de gesto/deceleração/acessibilidade. Commit: `fix(ui): isolate scroll observation and ready projection installation`.

### T3 — Garantir pixels antes da exposição, inclusive na volta

**Modificar:** `Sources/FeedMineRuntime/{FeedSession,PresentationCard}.swift`, caminho de residência/preparo de mídia existente; UI só onde a superfície navegável precisa refletir a prontidão.
**Testar:** `Tests/FeedMineRuntimeTests/{RenderReadyAdmissionTests,FeedSessionViewportTests}.swift`, XCUITest do feed.

**Interfaces:** preservar `PresentationCard.isRenderReady` e `FeedSession.admitPresentation(_:)`; residência não altera payload publicado. O destino exposto pela UI exige pixels preparados, com geometria congelada.

- [ ] Reproduzir com `testReverseExposurePrecedesViewportCallback`: admitir imagens, avançar até liberar pixels, reverter rapidamente antes do processamento de viewport. Verificar apresentação no instante de exposição, não apenas após `submitViewport`.
- [ ] Criar `testMissingAssetDoesNotRemoveVisibleAnchor`: remover arquivo local depois da publicação; preservar identidade, posição e geometria do conteúdo ainda apresentado.
- [ ] Corrigir `boundedResidency`: não tratar uma lista com bitmaps liberados como inteiramente pronta para desenho. Manter a região visível/atingível protegida e preparar readmissão fora da UI; recorte de memória só em fronteira segura, com âncora e acesso ao histórico preservados.
- [ ] Não usar `next.filter` de cards indisponíveis como solução para conteúdo já visível; não mover a âncora nem descrever placeholder como render-ready. Se o destino histórico estiver irrecuperável, conservar a leitura atual e declarar indisponibilidade na transição, sem reescrever publicação.
- [ ] Exercitar scroll reverso, salto programático, VoiceOver e pressão de memória. Uma banda preditiva sozinha não comprova prontidão para salto arbitrário: controlar a transição e testar o destino.
- [ ] Executar `swift test --filter RenderReadyAdmissionTests` e `swift test --filter FeedSessionViewportTests`, mais jornada visual em Release. Commit: `fix(runtime): preserve ready presentation across residency transitions`.

### T4 — Desacoplar aquisição de callbacks e do fim da rodada

**Modificar:** `Sources/FeedMineAcquisition/AcquisitionCoordinator.swift`, `Sources/FeedMineComposition/{RunwayAcquisitionCycle,FeedRunwayDriver,ColdFeedBootstrap}.swift`.
**Testar:** `Tests/FeedMineAcquisitionTests/AcquisitionCoordinatorTests.swift`, `Tests/FeedMineCompositionTests/{RunwayAcquisitionCycleTests,FeedRunwayDriverTests,ColdFeedBootstrapTests}.swift`.

**Interfaces:** preservar resultados em ordem de plano de `executeConcurrently(_:operation:trace:onResult:)` e single-flight; `onResult` informa conclusão durável individual. Uma única execução causal continua autorizando publicação; atividade de rede pode permanecer em andamento enquanto essa execução reconsidera fatos novos.

- [ ] Criar `testBlockedResultConsumerDoesNotStopOtherEligibleTargets`: A conclui, seu consumidor suspende, B aguarda rede; C e D progridem dentro do orçamento. O caso precisa ir além de apenas repor uma vaga antes de bloquear novamente em `group.next()`.
- [ ] Criar `testFastSourcePublishesWhileSlowSourceIsPending`: controlar B por continuação, admitir A e exigir publicação de A antes de liberar B. Sem sleeps usados como oráculo.
- [ ] Acrescentar cancelamento, erro fatal, callback duplicado e troca de edição entre admissão e publicação; exigir uma execução por target e nenhuma publicação duplicada/obsoleta.
- [ ] Separar coleta de conclusões/ocupação de slots do consumo editorial. Processamento caro sai do callback; entregar fatos pequenos ao owner existente, com quantidade pendente limitada pela capacidade autorizada. Não lançar tasks editoriais sem limite por resultado.
- [ ] No driver, permitir reconsideração de supply durável durante atividade de aquisição sem iniciar dois loops concorrentes de publicação. A conclusão total fecha a rodada, mas não é pré-condição para selecionar A.
- [ ] Preservar checkpoint transacional, cancelamento estruturado e contabilização de erros. Desligar a sessão encerra/retira autorização de trabalho pendente; resultados canônicos válidos podem permanecer úteis.
- [ ] Executar as quatro classes de teste citadas com `swift test --filter <Classe>`. Commit: `fix(composition): advance durable results independently of acquisition rounds`.

### T5 — Publicar prontos sem barreira de mídia

**Modificar:** `Sources/FeedMineRuntime/{MediaPrefetcher,LocalProductionSlice}.swift`, `Sources/FeedMineComposition/{FeedRunwayDriver,ColdFeedBootstrap}.swift`.
**Testar:** classes existentes de MediaPrefetcher, ColdFeedBootstrap e FeedRunwayDriver.

**Interfaces:** `FeedRunwayDriver.noteMediaReadinessChanged()` reaproveitado como fato; `LocalProductionSlice.run` seleciona somente oferta elegível/pronta. Pendentes conservam identidade e voltam a ser reconsiderados mesmo se o cursor editorial já avançou.

- [ ] Criar `testReadyCandidatePublishesBeforeUnrelatedMediaCompletes`: uma imagem travada, outra pronta e um texto editorialmente legítimo; os prontos podem avançar antes da travada, respeitando política.
- [ ] Criar `testLateReadyCandidateIsReconsideredOnce`: terminar a mídia após a passagem do cursor; candidato não some nem duplica. Repetir evento de readiness não duplica segmento.
- [ ] Retirar espera pela janela inteira da condição de executar slice. Preparo segue pelo MediaPrefetcher existente; readiness atual determina elegibilidade. Não converter candidato com mídia pendente em texto para contornar o teste.
- [ ] Usar reset/reconsideração existente do runway para oferta recém-pronta; impedir starvation de pendentes que se tornaram prontos e de candidatos mais antigos.
- [ ] Executar testes das três classes e combinar com T4: HTTP lento e decode lento simultaneamente não bloqueiam publicação pronta. Commit: `fix(media): make ready candidates independently publishable`.

### T6 — Capacidade adaptativa e descoberta com custo limitado

**Modificar:** `Sources/FeedMineComposition/{CollectionLaunchSettings,ReaderDiscoveryTraversal,FeedRunwayDriver}.swift`, `Sources/FeedMineAcquisition/AcquisitionPlanner.swift`, montagem de recursos em `AppComposition.swift`.
**Testar:** `Tests/FeedMineCompositionTests/ReaderDiscoveryPoolTests.swift`, `Tests/FeedMineAcquisitionTests/AcquisitionPlannerTests.swift`; criar `Tests/FeedMineCompositionTests/PipelineHeadroomTests.swift`.

**Interfaces:** manter `AcquisitionPlanningResources` como autorização por oportunidade; `CollectionLaunchSettings` fornece bootstrap/teto operacional, não estratégia permanente. Medições existentes de latência/consumo e condições de recurso alimentam o mesmo planner.

- [ ] Criar testes que, com mesma oferta, aumentem trabalho autorizado quando existe folga e reduzam-no sob pressão; assertar também justiça, não apenas contagem de tarefas.
- [ ] Corrigir traversal para não reconstruir `Set(pages.flatMap...)` nem procurar conector por todo o histórico a cada oportunidade. Manter índice derivado por target no mesmo owner, atualizado somente após instalação válida e invalidado com catálogo/autoridade.
- [ ] Retirar materialização/SQL do lock de coordenação; reservar trabalho sob identidade atual, materializar fora e validar novamente ao instalar. Não introduzir contador de geração se fingerprint/identidade existente resolve.
- [ ] Testar promoção/revogação do catálogo durante materialização e adoção duplicada; nenhum alvo removido pode reaparecer por resultado atrasado.
- [ ] Ajustar orçamento por demanda, latência, throughput útil e pressão observada. Não substituir 48 por outro número fixo; manter teto operacional documentado enquanto não houver evidência para alterá-lo. Rede e CPU têm custos diferentes.
- [ ] Auditar transações de admissão/publicação: mover parsing/decode e preparação independente para fora da transação; não remover atomicidade para elevar throughput.
- [ ] Executar testes do planner/traversal e consultas de escala existentes. Medir trabalho examinado por nova página e tamanho de filas, além de tempo; falha deve revelar custo crescente com histórico sem necessidade.
- [ ] Commit: `perf(runtime): adapt work budgets and bound discovery coordination`.

### T7 — Prioridades, continuidade e reutilização A→B→A

**Modificar:** `AppComposition.swift`, `FeedRunwayDriver.swift`, `FeedSession.swift` e owners existentes de contexto/retenção, somente onde a prova falhar.
**Testar:** `CompositionTests.swift`, `FeedPresentationHandoffTests.swift`, `FeedRunwayDriverTests.swift`.

**Interfaces:** contexto/edição/revisão existentes autorizam recibos e reaproveitamento; `publicationConcluded` valida no owner que modifica o estado, evitando intervalo entre leitura de scope e mutação.

- [ ] Criar `testContextSwitchUnderLoadReusesCanonicalWork`: A com downloads em andamento → B → A. Verificar bytes reutilizados, nenhuma nova aquisição só para repetir bytes válidos e retorno à edição/posição válida.
- [ ] Forçar conclusão invertida e recibo tardio na fronteira de publicação; teste deve chegar ao ponto da fence com recibo que seria aceito sem ela, não falhar antes por outra razão.
- [ ] Persistir confirmação do filtro antes da troca reconhecida; distinguir falha de gravação e falha de ativação posterior. UI mostra intenção pendente sem afirmar sucesso falso.
- [ ] Dar prioridade ao contexto ativo nos owners existentes; conservar trabalho útil dos outros conforme recursos. Cancelar trabalho sem utilidade, não toda aquisição compartilhada.
- [ ] Com usuário parado, conclusões de supply/readiness/publicação mantêm progresso sem exigir gesto ou esperar cadência. Sob oferta esgotada, cessar trabalho até fato novo; nenhum busy-loop.
- [ ] Exercitar retorno de background, morte do processo e offline. Commit: `fix(context): preserve useful work and scope-safe transitions`.

### T8 — Salvos e recuperação offline completos

**Modificar se necessário:** `Sources/FeedMineComposition/{SavedMediaCoordinator,ReaderLibraryCoordinator}.swift`, `Sources/FeedMinePersistence/SavedMediaAvailabilityStore.swift`, retenção e apresentação da biblioteca.
**Testar:** `SavedMediaCoordinatorTests.swift`, `SavedMediaAvailabilityStoreTests.swift`, `FeedMineApp/FeedMineAppTests/ReadingCompositionTests.swift`.

**Interfaces:** bookmark e disponibilidade de bytes são fatos distintos; as raízes de retenção existentes protegem recursos salvos. Não criar outra cópia do modelo de card.

- [ ] Testar salvar → terminar preparação → fechar processo → limpar apenas cache descartável → offline → reabrir; validar texto, imagem e ações efetivamente prometidos.
- [ ] Testar falta de espaço, falha de download, arquivo ausente, retry e mesmo salvo em duas caixas. Remover uma referência não remove bytes ainda retidos por outra.
- [ ] Testar que manutenção não expulsa conteúdo salvo nem a apresentação em uso. Falha parcial conserva bookmark e informa disponibilidade verdadeira.
- [ ] Corrigir apenas lacunas comprovadas na candidata; reutilizar implementação de salvos já integrada.
- [ ] Executar classes citadas e jornada no dispositivo. Commit: `fix(library): complete durable saved-content recovery`.

### T9 — Controles que significam o que a interface diz

**Modificar:** `Sources/FeedMineComposition/ReaderDiscoveryPool.swift`, `Sources/FeedMineDomain/FeedContext.swift`, `Sources/FeedMineEditorial/CandidateProvider.swift`, `Sources/FeedMineUI/FeedScreenStore.swift`, `AppComposition.swift`, owners de settings/library existentes.
**Testar:** `ReaderDiscoveryPoolTests.swift`, testes de CandidateProvider e `CompositionTests.swift`.

**Interfaces:** uma interpretação de expressão de busca, compartilhada pelo contexto/consulta/preset. Salvar preset continua usando `ReaderLibraryCoordinator.savePreset`; não introduzir SearchEngine paralelo.

- [ ] Testar `.more/.less/.neutral` persistidos: neutral não exclui, inclusive em dados antigos. Corrigir ramo de `ReaderDiscoveryProfile` que trata todo não-more como exclusão.
- [ ] Testar a matriz completa de combinações de mídia, evitando que selecionar duas seja interpretado como todas; separar namespaces editorial/assunto e retorno ao estado neutro.
- [ ] Fixar a gramática já descrita na revisão de busca: positivos em AND, prefixo `-` exclui, hífen interno é texto, comparação sem distinção de case/diacríticos, só negativos não inicia busca. Positivos podem aparecer em campos diferentes do mesmo candidato.
- [ ] Implementar uma expressão de domínio usada por CandidateProvider e validação da UI; preservar significado dos presets antigos por migração/compatibilidade explícita, não alteração silenciosa da string persistida.
- [ ] Encaminhar Cancelar como retorno ao contexto completo anterior, incluindo âncora; voltar do artigo recupera a consulta. Não assumir main como origem.
- [ ] Ligar escopos a resultados reais de fontes/salvos/conteúdo local, com tipo e destino honestos; erro ao salvar ou ativar pesquisa não pode desaparecer em `try?`.
- [ ] Testar busca salva offline após relaunch, conclusão invertida e falha de disco. Commit por subentrega: preferências; expressão; navegação/escopos. Cada uma com teste próprio.

### T10 — Diversidade editorial entre segmentos

**Modificar:** `Sources/FeedMineEditorial/{SelectionEngine,SourceAlternation,CandidateProvider}.swift`, entrada de contexto editorial no `LocalProductionSlice.swift`.
**Testar:** `Tests/FeedMineEditorialTests/SelectionEngineTests.swift`, caracterizações temáticas/temporais existentes.

**Interfaces:** seleção permanece pura e determinística com seed/contexto explícitos; recebe histórico editorial suficiente do final publicado, sem consultar UI nem reordenar segmentos antigos.

- [ ] Mapear fatos canônicos para fonte/provedor, assunto da história, geografia, formato, exposição e natureza temporal; marcar ausente/ambíguo. Categoria da fonte não vira assunto de toda história.
- [ ] Criar corpus rotulado com alternativas reais e pares de segmentos. Prova distingue alternância só de SourceID de variedade multidimensional e detecta repetição nas emendas.
- [ ] No seletor existente, após elegibilidade e relevância aprovadas, usar desempate por menor repetição recente nas dimensões conhecidas; preservar ordem determinística e justiça. Não fabricar pesos/percentuais da V1. Se uma regra de relevância conflitante exigir nova decisão de produto, isolar esse ponto, não reinventar o motor.
- [ ] Usar tempo declarado legítimo; `observedAt` não certifica novidade. Ausência de alternativas permite oferta homogênea honesta, não exclusão interminável.
- [ ] Verificar que novo supply/readiness/filtro só muda seleção futura; hash/ordem dos segmentos anteriores permanecem iguais. Executar testes editoriais e B02 vigente na integração. Commit: `feat(editorial): preserve multidimensional diversity across publication seams`.

### T11 — Fechar primeira experiência, navegação e catálogo

**Modificar onde houver lacuna:** `ColdFeedBootstrap.swift`, `AppComposition.swift`, `Sources/FeedMineUI/Reader/ReaderShell.swift`, owners `CatalogUpdater`, `CatalogInstallation` e `ReaderActionCoordinator`.
**Testar:** `ColdFeedBootstrapTests.swift`, `CatalogUpdaterTests.swift`, `CatalogInstallationTests.swift`, `ReadingCompositionTests.swift` e UI tests existentes.

**Interfaces:** loading consome `ColdFeedEvidence` real; Ver fonte abre contexto interno da fonte; catálogo novo é ativado atomicamente pelo owner existente e só influencia trabalho futuro.

- [ ] Instalação limpa: fontes reais lentas/rápidas, falha de rede, idioma do onboarding, gravação de boas-vindas falhando. Mostrar progresso real e saída recuperável; primeira publicação não encerra abastecimento.
- [ ] Ver fonte abre lista interna; ação explícita de site abre URL. Corpo local parcial/sem URL apresenta disponibilidade verdadeira; retornar preserva posição.
- [ ] Exercitar atualização válida/inválida de catálogo, interrupção, rollback e reabertura offline. Preservar fontes pessoais, memberships e dados de leitura; snapshot novo não reescreve história.
- [ ] Reutilizar pesquisas Apple de scene/background/proteção de arquivos. Testar cancelamento por expiração de concessão e retomada em foreground; nenhuma continuidade depende de BGTask ocorrer em horário exato.
- [ ] Validar locale explícito em testes de texto; identificadores de máquina não localizados; opções de idioma por IDs estáveis; Dynamic Type e VoiceOver na candidata resultante.
- [ ] Commit separado para cada defeito reproduzido; não criar alteração cosmética se a jornada já passar.

### T12 — Provar folga, simplificar e certificar a candidata

**Arquivos:** `Tests/FeedMineCompositionTests/PipelineHeadroomTests.swift` criado em T6; atualizar registro de execução de T1; evidências em `docs/reviews/evidence/2026-10-17-v2-plan/`. Instrumentos existentes fora de bench; nenhuma alteração de oráculo.

**Interfaces:** cenário oferece demanda e recursos explicitamente, observa conclusões reais por estágio e consumo do leitor. Números abaixo são carga de laboratório, nunca defaults de produção.

- [ ] Usar catálogo de 1.000+ fontes, 10.000+ candidatos e 100 fontes simuladas independentes, com latências controladas, repetidos, falhas e mídia variável. Comparar também consultas de 100.000 linhas já existentes.
- [ ] Medir separadamente admitidos/s, candidatos examinados/s, preparados/s e publicados/s; calcular throughput útil em relação à demanda correspondente. Meta: 10× de folga nos estágios locais testáveis sob condições declaradas, sem equivaler 30 candidatos examinados a 30 cards publicados.
- [ ] Para referência de consumo de 1 card/s e rajadas de 3 cards/s, testar carga local correspondente de 10×; registrar gargalo se não cumprir, sem reduzir meta silenciosamente. Rede pública tem prova separada e não recebe SLA artificial de 10×.
- [ ] Verificar limites de memória/filas, latência p95 e proteção da UI sob produtores ativos. Oferta infinita simulada não pode mascarar seleção ruim ou impossibilidade de reposição real.
- [ ] Rodar casos A pronto/B suspenso, decode pendente, filtro A→B→A, reverse-scroll, foreground e offline, tanto isoladamente quanto na candidata final. Ausência de trace/frames em Release = NOT_MEASURED; instrumento precisa ler o arquivo real e correlacionar a janela do gesto.
- [ ] Comparar scroll de apresentação local com produtores pausados/ativos e inspecionar stacks de engasgos restantes. A redução de um percentual não encerra defeito perceptível; esta prova confirma isolamento, não decide se SQL deve sair da UI.
- [ ] Consolidar mecanismos substituídos pelos passos anteriores: remover call sites mortos, timers/tasks redundantes, testes que só espelham implementação e helpers duplicados, mediante referência/prova. Não usar meta de linhas removidas e não apagar regressões de produto.
- [ ] Executar B01–B06 conforme benchmark congelado, incluindo duração integral e B06 físico. Registrar SHA/build, dispositivo/OS, corpus, hash de avaliador, logs/xcresult e resultado por cláusula. Falta de execução permanece NOT_RUN.
- [ ] Commit: `test(acceptance): record integrated runway and headroom evidence`. Merge/release somente pelo fluxo autorizado; o plano em si não declara aplicativo corrigido.

## 5. Comandos de verificação e regra de execução

No Mac do implementador, a partir da raiz da candidata:

```bash
git rev-parse HEAD
git status --short
swift test --filter AcquisitionCoordinatorTests
swift test --filter FeedRunwayDriverTests
swift test --filter RenderReadyAdmissionTests
swift test --filter SavedMediaCoordinatorTests
git diff --check
```

Usar a classe específica indicada em cada tarefa em vez de repetir toda a suíte a cada passo. Os nomes de testes novos acima são contratos propostos, não testes existentes. Teste vermelho deve falhar pela asserção do defeito, não por build quebrado. Teste já verde que cobre o contrato é preservado e a tarefa se limita à lacuna restante.

Para composição/UI, usar o scheme `FeedMine` do projeto `FeedMineApp/FeedMineApp.xcodeproj`, destino disponível obtido no Mac e os comandos vigentes em `docs/IOS_RUN.md`; não copiar UUID histórico. Guardar `.xcresult` por tarefa. Executar a suíte ampla uma vez na candidata reconciliada e ampliar testes apenas por risco concreto/gate obrigatório.

## 6. Matriz de cobertura e encerramento

| Problema/intenção | Entrega |
|---|---|
| Engasgo, observações O(n), SQL na instalação, Task por callback | T2 |
| Publicação imutável, readmissão sem pixels e retorno rápido | T1/T3 |
| K-02/K-03: callback/rodada prendendo trabalho independente | T4 |
| K-04: barreira de mídia | T5 |
| K-01/K-05/K-08: capacidade, traversal e transações | T6 |
| K-09: progresso sem gesto e aprendizagem preservada | T1/T4/T7 |
| K-10: custo editorial e diversidade real | T6/T10/T12 |
| Filtros, fences, A→B→A e prioridade futura | T7 |
| Salvos, retenção, reinício e falha de disco | T8 |
| Busca/presets, neutral, combinações de mídia e erros de ação | T9 |
| Interleave V1: transferir comportamento, não runtime legado | T10 |
| Primeira abertura, leitura/Ver fonte, catálogo e limites iOS | T11 |
| Locale/acessibilidade, falsos verdes e árvore integrada | T11/T12 |
| Folga 10×, continuidade sustentada, simplicidade e release | T12 |

**Registro obrigatório por tarefa:** `SHA inicial | defeito/prova vermelha | alteração | prova verde | jornada melhorada | pendência | SHA final`. Não registrar “concluído” só porque existe commit.

O próximo trabalho concreto é T1→T2→T3. Não elevar paralelismo antes de preservar UI e residência; depois liberar progressão entre estágios e somente então exigir a folga de capacidade. O sucesso final é o leitor continuar lendo enquanto o motor trabalha — com histórico estável, mudança de contexto barata e retorno offline verdadeiro.
