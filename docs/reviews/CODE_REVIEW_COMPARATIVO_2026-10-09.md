# Code review comparativo — FeedMine V2

**Data:** 2026-10-09  
**Repositório:** [wsmontes/feedmine_v2](https://github.com/wsmontes/feedmine_v2)  
**Base anterior:** `a259e96d41d43e8e5657dffaa6d33ddd1d317fb3` (app iOS / composição inicial)  
**Revisado:** `1e53ed20aae3bf438a39f5c5ab748dec41ad7822` (`main`)  
**Diferença:** 21 commits, 75 arquivos alterados, sem divergência da base.  
**Natureza:** auditoria estática comparativa; **não foram executados Xcode, Swift build/test nem testes de dispositivo**. O [port log](../v1-study/PORT_LOG.md) declara que as alterações recentes ainda não haviam sido compiladas ou testadas no ambiente do autor. Este documento registra problemas e recomendações; não é um resultado de execução.

## Sumário executivo

Os 21 commits representam avanço real, especialmente na aquisição concorrente, mídia ponta a ponta, identidade do catálogo, alternância entre fontes e estados de preparação inicial. A arquitetura mantém boas fronteiras entre conteúdo canônico, seleção, publicação, sessão e UI. **O V2, porém, ainda não demonstra a invariante principal do produto: manter uma reserva local de conteúdo apresentável, proativamente abastecida e renovada antes de o usuário alcançar o fim do feed.**

A integração da mídia também introduziu problemas concretos de espera e recuperação que devem ser corrigidos antes de avaliar release. A prioridade é consolidar os owners existentes, não criar outro cache, scheduler ou pipeline.

### Comparativo com a revisão anterior

| Área | Em `a259e96` | Em `1e53ed2` | Avaliação |
| --- | --- | --- | --- |
| Imagens nos cards | Composição `.textOnly`, sem renderização | MediaPrefetcher, readiness, assets locais, decoding, hero/thumbnail | Integrado; comportamentos sob rede ruim pendentes |
| Fontes | Duas BBC fixas | Leitor/importador de `catalog.sqlite`, fallback BBC | Parcial; catálogo não incluído no repositório/projeto |
| Seleção | Recência simples | Alternância por `SourceID` | Melhoria real; faltam provas de escala |
| Aquisição | Execução sequencial | Sliding window concorrente e backoff por target | Melhoria real; retomada após cooldown ainda depende de oportunidades |
| Retry local | Sem retorno automático em falha | Retry com elegibilidade temporal | Parcial; lifecycle/estado de visibilidade precisam de ajuste |
| Cold start | Loading genérico | Progresso com fontes/manchetes reais | Melhor UX; ainda há bloqueio de primeira publicação |
| Edições de artigo | Exposição por origem/revision | Republicação por texto material | Parcial; mídia e limite de futuro não visto ausentes |
| Runway | Demanda predominantemente reativa | Política essencial mantida | Invariante principal ainda aberta |
| Filtros/contextos | Contexto `.main` | Mesmo contexto no app | Ainda não integrado |
| Qualidade verificável | Testes anteriores relatados | Novos testes escritos, não executados nesta rodada | Build e teste de iOS obrigatórios antes de release |

## Achados prioritários

A severidade P0 indica **bloqueador da experiência alvo**; P1 indica falha ou lacuna relevante; P2 indica performance/qualidade ou risco pendente. `Confirmado (código)` não significa que o sintoma foi medido num dispositivo.

### F01 — P0 — Ausência de abastecimento proativo sustentado

**Locais:** `Sources/FeedMineRuntime/RunwayPolicy.swift:94-135`; `Sources/FeedMineComposition/FeedRunwayDriver.swift:113-210`; `FeedMineApp/FeedMineApp/AppComposition.swift`.

**Evidência:** quando `consumption.cardsPerSecond == 0`, `RunwayPolicy.evaluate` pode classificar cobertura como `.healthy` independentemente de uma pequena reserva restante, salvo aproximação explícita do tail. Com taxa e latência desconhecidas, cobertura frequentemente permanece `.unknown`; o pedido de produção depende de intenção de avanço ou aproximação do fim. A composição aciona o driver principalmente em launch, viewport, foreground e retry local.

**Efeito:** um leitor parado pode não receber ampliação antecipada da reserva; o sistema reage à escassez, mas não comprova runway continuamente confortável.

**Critério de aceite:** com o usuário estacionário, supply local elegível e recursos disponíveis, a reserva aumenta até um patamar adaptativo; com scroll rápido e latência externa, o sistema reconsidera demanda antes de atingir tail, sem trabalho duplicado nem perturbação do trecho visível.

**Recomendação:** evoluir a política/controlador atuais para considerar reserva necessária mesmo sem amostras de consumo; usar velocidade e latência para modular urgência e capacidade, não como pré-condição única de produção. Não criar segundo Runway.

**Status:** confirmado (código); medir no simulador.

### F02 — P0 — Catálogo V1 ainda não está efetivamente empacotado

**Locais:** `FeedMineApp/FeedMineApp/TrustedFeeds.swift`; `Sources/FeedMineComposition/LegacyCatalogImport.swift`; `FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj`.

**Evidência:** `catalogOrDevelopment(limit: 64)` exige `Bundle.main.url(forResource:"catalog", withExtension:"sqlite")` e cai em `development` se não encontrar arquivo válido. Na árvore completa de `1e53ed2`, não há `catalog.sqlite` nem referência de recurso no projeto Xcode. Portanto, um build apenas desse checkout usa as duas fontes BBC.

**Efeito:** o leitor real não dispõe do catálogo amplo; o código de importação sozinho não resolve aquisição/diversidade.

**Critério de aceite:** build iOS recebe catálogo compatível, faz consulta real e seleciona fontes representativas; fallback de desenvolvimento não é silencioso num build destinado a usuários.

**Recomendação:** definir distribuição/recurso do catálogo e seleção contextual, sem registrar indiscriminadamente milhares de targets na inicialização.

**Status:** confirmado (árvore/projeto e fallback).

### F03 — P1 — Deadline de prefetch pode não encerrar a espera

**Local:** `Sources/FeedMineRuntime/MediaPrefetcher.swift`, `prefetchSupplyHead(limit:deadline:)`.

**Evidência:** o método cria um `Task` independente `work = Task { await self.prepareAll(revisions) }` e depois um `withTaskGroup` competindo `await work.value` com `Task.sleep`. Após a primeira conclusão, `group.cancelAll()` não garante cancelar `work` nem desbloquear o filho que aguarda seu `value`; ao sair do grupo, filhos precisam terminar. `FeedRunwayDriver` espera `prepareMedia` antes do slice.

**Efeito:** a preparação de mídia pode bloquear cold start/publicação muito além do `deadline` anunciado.

**Critério de aceite:** teste com fetch que não termina até sinal externo: o await do prefetch retorna dentro do prazo; downloads úteis podem prosseguir com ownership explícito, sem segurar a publicação.

**Status:** confirmado no padrão de concorrência; reproduzir teste de bloqueio.

### F04 — P1 — Falhas transitórias de mídia se tornam desistência definitiva na sessão

**Local:** `Sources/FeedMineRuntime/MediaPrefetcher.swift`, `prepare(_ revision:)`.

**Evidência:** após tentar todos os candidatos, inclusive aqueles cujo `fetch` lançou erro de rede, `readiness.record(revision, nil)` marca a revision como `settled`. `prefetchSupplyHead` filtra revisões settled. O teste `testAllCandidatesFailingIsDesignedTextOnlyAndNotRetried` consolida o caso, mas não distingue imagem comprovadamente inválida de timeout.

**Efeito:** uma imagem pode nunca voltar a ser considerada depois de erro temporário, embora a rede tenha se recuperado.

**Critério de aceite:** erros recuperáveis permitem nova oportunidade; ausência/invalidade definitiva continua produzindo card text-only sem tentativas intermináveis.

**Recomendação:** diferenciar resultado permanente de falha operacional usando a mesma política/owner de mídia; não introduzir cache paralelo.

**Status:** confirmado (código).

### F05 — P1 — Prefetch mira a cabeça global, não a próxima publicação editorial

**Local:** `Sources/FeedMineRuntime/MediaPrefetcher.swift`, consulta `contentStore.candidateWindow(sourceID: nil, after: nil, examinedCapacity: limit)`.

**Evidência:** todas as chamadas de prefetch usam a janela canônica global de até 32 registros, sem aplicar exposição da Edition, cursor editorial ou contexto ativo. Há revisões já publicadas e/ou inelegíveis que podem ocupar essa janela.

**Efeito:** downloads inúteis na cabeça global enquanto candidatos que serão publicados permanecem sem mídia preparada.

**Critério de aceite:** preparação antecipada é dirigida pelos próximos candidatos editoriais admissíveis e respeita prioridade da janela, sem acoplá-la à latência da UI.

**Status:** confirmado (código).

### F06 — P1 — Primeira publicação ainda espera o conjunto planejado de feeds

**Local:** `Sources/FeedMineComposition/ColdFeedBootstrap.swift:135-156`.

**Evidência:** `coordinator.executeConcurrently(acquisitionPlan.work)` melhora latência entre targets, mas `cold.run` aguarda seu término agregado antes de preparar mídia e criar a primeira Edition. A admissão parcial de uma fonte rápida não é imediatamente aproveitada para publicar.

**Efeito:** fonte lenta pode reter a primeira tela apesar de já existir supply suficiente.

**Critério de aceite:** primeira janela editorial válida é publicada com supply real suficiente sem esperar a fonte mais lenta, preservando alternância entre fontes e integridade transacional.

**Status:** confirmado (sequência de await).

### F07 — P1 — Republicação por mídia não corresponde integralmente à PD-1

**Locais:** `Sources/FeedMineSyndication/SyndicationTranslator.swift`, `materialFingerprint`; `Sources/FeedMineEditorial/SelectionExposure.swift`, `materialKey`; `Sources/FeedMinePersistence/PublicationStore.swift:200-248`.

**Evidência:** fingerprint da ingestão inclui URLs de mídia, mas chave de exposição/publicação compara apenas título e texto. Mudar apenas o visual principal pode criar nova revision sem permitir nova ocorrência, apesar de PD-1 considerar mudança da mídia principal material. PD-1 também requer, em regra distinta, no máximo uma ocorrência futura ainda não vista por origem; não há prova de tal limite na composição atual.

**Critério de aceite:** identidade material consistente desde admissão até publicação; mudança apenas de mídia editorial principal produz a ocorrência correta; edições sucessivas não enfileiram múltiplas ocorrências futuras para a mesma origem.

**Status:** confirmado (mismatch de chave); regra de ocorrência futura pendente.

### F08 — P1 — Cooldown sem retomada autônoma

**Locais:** `Sources/FeedMineAcquisition/AcquisitionCoordinator.swift`, `coolingTargetIDs`; `Sources/FeedMineComposition/RunwayAcquisitionCycle.swift`; `Sources/FeedMineRuntime/RunwayController.swift`.

**Evidência:** quando todos os targets elegíveis estão em cooldown, o planejador recebe lista filtrada vazia, devolve `.noEligibleTargets` e a demanda do Runway pode ser reconhecida como concluída. Não foi encontrada oportunidade agendada para reavaliar no fim do cooldown de aquisição.

**Efeito:** a rede pode melhorar sem que o supply seja atualizado até novo evento de leitura/foreground.

**Critério de aceite:** expiração de cooldown relevante pode provocar reconsideração da mesma demanda, sem spinning, tentativas contínuas ou segundo scheduler.

**Status:** risco sustentado pelo fluxo; testar cenário controlado.

### F09 — P1 — Retry local pode ser executado sem respeitar visibilidade

**Local:** `FeedMineApp/FeedMineApp/AppComposition.swift`, `scheduleLocalRetryIfNeeded`, `background`.

**Evidência:** a Task agendada para elegibilidade invoca `foreground()` após `Task.sleep`. O método `background()` faz checkpoint e tidy, mas não cancela explicitamente `retryTask` nem registra um estado de visibilidade que impeça o callback de tentar dirigir o Runway enquanto o app está em background.

**Efeito:** trabalho local pode disputar recursos com a transição de lifecycle, contrariando a regra de não perturbar a sessão visível.

**Critério de aceite:** oportunidades de retry respeitam o lifecycle real, sem produzir enquanto a associação não está autorizada a dirigir o feed.

**Status:** confirmado (código); comportamento real do SO pode limitar execução.

### F10 — P1 — Ações dos cards não estão integradas

**Locais:** `Sources/FeedMineRuntime/PresentationCard.swift`; `Sources/FeedMineUI/FeedCardView.swift`; `Sources/FeedMineRuntime/InteractionCoordinator.swift`.

**Evidência:** a UI apresenta `primaryActionKind`, mas `FeedCardView` não define interação que execute o alvo; no fluxo de composição examinado, `prepare` fornece `primaryAction: nil`.

**Efeito:** usuário não consegue abrir o artigo a partir do card nessa composição.

**Status:** confirmado (código); funcionalidade de produto pendente.

## Performance e riscos secundários

| ID | Gravidade | Observação | Critério |
| --- | --- | --- | --- |
| F11 | P2 | `FeedSession.project` rematerializa a janela e `PresentationImageDecoder` lê, autentica e decodifica assets locais antes de testar equivalência do snapshot. | Medir CPU/memória durante navegação de ida e volta; reutilizar se o custo justificar. |
| F12 | P2 | `MediaTidy` usa data de arquivo e janela visível como aproximações de prioridade, não fatos reais de seen/bookmarked/future. | Eviction guiada por uso e proteção de assets relevantes reais. |
| F13 | P2 | `PreparationProgress.estimatedRemainingSeconds` extrapola a média de conclusão de targets; não incorpora suficiente supply editorial ou velocidade de publicação. | Mensagens sobre prontidão refletem conteúdo apresentável, sem promessa implícita falsa. |
| F14 | P2 | `ContentStore.candidateWindow` mantém consultas por linha e filtragem de fonte após varredura global. | Medir consultas e latência com catálogo grande e contextos específicos. |
| F15 | P1 | UI/Composição continuam centradas em `FeedContext(request: .main)`. Pesquisa, seleção do usuário e reentrada em contextos preparados não estão expostas. | Trocar contexto sem destruir história nem trabalho reaproveitável; restaurar contexto anterior prontamente. |
| F16 | P1 | `ColdFeedBootstrap` ainda devolve resultados sem publicação após oportunidade finita; a composição depende de novas oportunidades explícitas de lifecycle. | Primeira execução recupera de indisponibilidade/transição de rede sem gesto ou relaunch. |

## Mudanças boas a preservar

1. **Uma única autoridade de aquisição** com `AcquisitionCoordinator.executeConcurrently`, limite operacional, compartilhamento por target e backoff.
2. **Identidades estáveis para o catálogo V1** usando namespace e SHA-256; a identidade não segue URL de request mutável.
3. **Alternância editorial em um único owner**, não espalhada por UI e mídia, respeitando cauda de segmentos.
4. **Publicação congelada**, imagens locais decodificadas no Runtime e slot de proporção estável na UI.
5. **Separação canônico/publicado/sessão** e checagem de proveniência que rejeita projeções antigas.
6. **Primeira tela com evidências reais** de aquisição, em vez de progresso fictício.

Não reescrever o RunwayController, não substituir a Persistence e não criar pipelines paralelas como resposta a estes achados.

## Lacunas de validação

- O repositório registra no port log que essa rodada foi escrita **sem compilador**; há novos testes, mas não há evidência de `swift build`/`swift test` executados para `1e53ed2`.
- Testes de mídia existentes provam happy path, ausência de imagem e offline; faltam bloqueio por deadline, falha transitória recuperável, redes intermitentes, reuso após relançamento e pressão de recursos.
- Falta demonstração integrada de scroll contínuo prolongado, diversidade com muitas fontes, retomada após cooldown, cold start parcial, filtros/contextos e consumo energético.
- Um teste verde que exige `settled` após qualquer falha de download não comprova a invariante de recuperação do usuário. Ajustar contrato e testes em conjunto.

## Ordem de execução recomendada

1. **Gate de compilação e integridade:** `swift build && swift test && git diff --check`; build do app e testes iOS no simulador; guardar resultado e commit testado.
2. **Corrigir a mídia antes da próxima feature:** deadline efetivo (F03), recuperação de falha temporária (F04), prioridade editorial do prefetch (F05), e provar apresentação imutável dos cards visíveis.
3. **Fechar a invariante de continuidade:** F01, F06, F08, F09 e F16. Ajustar owners/políticas existentes; medir runway local disponível versus consumo sob fontes lentas e rede variável.
4. **Completar produto utilizável:** catálogo empacotado (F02), ação de abertura (F10), filtros e reentrada de contextos (F15), consistência da republicação (F07).
5. **Otimizar por medição:** F11–F14; evitar cache, timers ou state machines adicionais sem necessidade comprovada.

## Veredito

**Houve avanço significativo e aproveitável nos 21 commits.** A V2 passou a ter imagens, aquisição concorrente, identidade do catálogo e mais regras editoriais. **Ainda não está pronta para release:** o ciclo de abastecimento proativo não está fechado e a nova integração de mídia não demonstra, por código, cumprir os prazos e a recuperação operacional prometidos. O plano é corrigir primeiro as invariantes do produto, preservando a arquitetura existente, e usar build/simulador para distinguir implementação provável de comportamento realmente confirmado.

**Links-base:** [compare no GitHub](https://github.com/wsmontes/feedmine_v2/compare/a259e96d41d43e8e5657dffaa6d33ddd1d317fb3...1e53ed20aae3bf438a39f5c5ab748dec41ad7822) · [decisões de produto](../product/PRODUCT_DECISIONS_2026-10-09.md) · [revisão anterior](CODE_REVIEW_2026-10-08.md).

---

## Resposta — `main` @ `f0fa2ef` (2026-10-09)

Corrigido sem compilador (ver [PORT_LOG](../v1-study/PORT_LOG.md), rodada 3). Os critérios de aceite ainda precisam de build, simulador e dispositivo.

| Achado | Status | Commit | O que mudou |
| --- | --- | --- | --- |
| F01 | Corrigido | `a964559` | `RunwayResourceFacts.reserveCards`: cobertura abaixo da reserva é pressão mesmo com leitor parado ou sem amostras; o app usa a janela à frente (16). |
| F02 | Pendente (decisão) | — | Catálogo de 118 MB fora do repo; precisa de LFS ou download e de Copy Bundle Resources. |
| F03 | Corrigido | `5906b9a` | O deadline libera o chamador via continuação única; o download continua sob o actor. |
| F04 | Corrigido | `5906b9a` | `MediaFetchFailure`: falha definitiva vira text-only; transitória volta a ser tentada com atraso crescente. |
| F05 | Corrigido | `c822f0c` | O driver passa os próximos candidatos editoriais (mesmo contexto e cursor, sem os já expostos). |
| F06 | Corrigido | `17f3300` | O primeiro feed que traz supply já tenta publicar, e o app instala na hora. |
| F07 | Corrigido | `dd4e29d` | A chave material inclui a mídia principal; origem com ocorrência à frente do leitor não entra de novo (PD-1 regra 2). |
| F08 | Corrigido | `a0c8f54` | Cooldown vira `deferred` sem consumir a intent; oportunidade única na expiração. |
| F09 | Corrigido | `7e04a9d` | Estado de visibilidade; o background cancela o retry. |
| F10 | Corrigido | `f0fa2ef` | O toque abre o artigo; só o `PublicationCardID` cruza a UI. |
| F11–F14 | Medir | — | Depende de medição no dispositivo. |
| F15 | Pendente | — | Contextos e filtros na UI. |
| F16 | Corrigido | `17f3300` | Cold start sem Edition reagenda `launch()` sozinho (expiração do cooldown ou um timeout de request). |

## Evidência executada — branch codex/omp-plan-execution

Esta atualização sucede o estado histórico acima. Referência: [relatório completo](OMP_VALIDATION_2026-10-09.md).

| Achados | Estado atual | Evidência/limite |
| --- | --- | --- |
| F01, F06, F08, F09, F16 | Verificados no simulador | Reserva parada, publicação parcial, retry autônomo e cancelamento em background. |
| F02 | Bundle local verificado; distribuição remota pendente | Catálogo real: 77.443 fontes, 117.940.224 bytes, checksum testado no bundle. Upload LFS bloqueado pela cota do GitHub. |
| F03–F05 | Regressões verificadas | Deadline suspenso, retry/permanência text-only e prefetch de candidatos explícitos. |
| F07 | Regressões verificadas | Tracking churn não republica; revisão material substitui futuro não visto com validação transacional. |
| F10 | Handler e identidade de abertura cobertos | Não equivale a prova de abertura externa no Safari em aparelho físico. |
| F11–F14 | Medidos no host/simulador; hardware pendente | Reuso de decode, consultas limitadas, progresso por supply e reserva calculada; energia/térmica do iPhone não medidas. |
| F15 | Implementado e verificado | Fontes persistidas, busca local e checkpoints A→B→A offline; bookmarks protegidos na retenção. |

PD-1/PD-3/PD-4/PD-5/PD-6 possuem regressões executadas; PD-2 funciona com catálogo local, mas depende de resolver distribuição LFS. PD-7: execução prosseguiu com commits/push; indisponibilidade dos aparelhos foi registrada sem declarar release pronta.

Atualização `8c31b83`: a distribuição do F02 foi resolvida sem LFS. O catálogo é o asset da release `catalog-v1`, com checksum conferido após o upload, e é instalado por `scripts/fetch-catalog.sh`. Falta só um build que confirme o bundle a partir de um clone limpo.