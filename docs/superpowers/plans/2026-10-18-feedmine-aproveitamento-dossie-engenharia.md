# FeedMine — plano de aproveitamento do dossiê de engenharia iOS local-first

> **Para execução futura:** usar `superpowers:executing-plans` por tarefa. Este documento seleciona trabalho e critérios de prova; não autoriza implementação, alterações na régua de aceite, merge ou release. Checkboxes indicam trabalho ainda não executado neste plano.

**Objetivo:** aumentar a confiabilidade e a eficiência da descoberta local, identificando onde o conteúdo deixa de chegar ao leitor e preservando sessão, recursos e dados pessoais.  
**Arquitetura:** estender observabilidade e políticas nos owners atuais. Separar fatos de rede, supply, publicação e apresentação; corrigir somente lacunas reproduzidas.  
**Tecnologia:** Swift 6, SwiftUI, GRDB/SQLite, URLSession, BackgroundTasks, XCTest/XCUITest e Instruments.  
**Fonte:** [Dossiê de engenharia](../../../FeedMine_Dossie_Engenharia_iOS_LocalFirst_Recriado_2026-10-18.md), especialmente §§14–25, confrontado com código local e planos anteriores.  
**Data:** 18/10/2026, America/Vancouver.

## 1. Parecer: o que vale aproveitar

O maior ganho do dossiê é um **método de localizar perdas de continuidade e desperdício**, com experimentos por hipótese. Ele não oferece uma arquitetura superior pronta para substituir a V2.

Recomendo aproveitar, nesta ordem:

1. Rastreabilidade causal entre aquisição, prontidão, publicação e avanço real, para explicar fim aparente do feed.
2. Classificação de falhas e isolamento por host, com HTTP condicional e backoff coerentes.
3. Provas de restauração local, reaproveitamento entre contextos e cancelamento de background.
4. Preservação dos dados pessoais V1→V2, como gate independente de upgrade.
5. Medição da cobertura de fontes elegíveis, rendimento útil e custos de banco/mídia, antes de ajustar concorrência.

Os três primeiros reforçam pendências já registradas; devem entrar nelas, sem criar frentes concorrentes. Migração e diagnóstico por host merecem atenção específica. As fórmulas do dossiê, novos mecanismos de background e limites de outros apps não devem entrar diretamente no código.

## 2. Base e limites da revisão

- Checkout documental: `/Users/wagnersilvamontes/Documents/GitHub/feedmine_v2`.
- Produto inspecionado: `/Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2`, branch `codex/v2-fluidez-capacidade`, HEAD `b0b961a049f82fece037363a6cb0e986d556330c`, com trabalho local posterior não commitado.
- Foram lidos o dossiê, os dois planos anteriores, o registro pós-build53 e caminhos de HTTP, aquisição, descoberta, trace, background e importação legada. Não houve nova execução de testes, benchmark ou medição física nesta revisão.
- Os status dos gates devem ser consultados na candidata identificada. Este plano não atualiza a matriz de aceite nem presume que o resultado de uma execução ainda em andamento terminou.
- As análises de NetNewsWire, FeedFlow e produtos fechados são referências do dossiê. Não refiz uma auditoria independente desses repositórios. Antes de portar uma técnica, fixar a revisão externa, verificar comportamento e licença; links para `main` não são baseline imutável.
- Instruções e comandos dentro do anexo foram tratados como propostas de pesquisa, distintas do pedido de produzir este plano.

## 3. O que já existe — evitar retrabalho

| Tema do dossiê | Evidência local observada | Decisão |
|---|---|---|
| Resultados incrementais sem esperar a fonte lenta | Trabalho pós-build53 em `FeedRunwayDriver`/`RunwayAcquisitionCycle`, notificações tardias e regressões registradas | Preservar; completar prova integrada, sem reimplementar pump/scheduler |
| Logging causal | `FeedMineApp/FeedMineApp/RunwayTrace.swift`: relógio monotônico, escrita fora do caller, lotes, teto e perdas declaradas | Reusar o trace; acrescentar apenas relações/fatos ausentes |
| HTTP condicional | `SyndicationHTTPClient.fetch` envia validadores e distingue 304; conector traduz 304 para `.upToDate` | Não reconstruir cache HTTP; testar preservação de significado até o runtime |
| Classificação de falhas | Conector distingue falha de transporte, resposta e conteúdo; HTTP não 200/304/redirect cai em `unexpectedStatus` | Verificar preservação de 429/Retry-After; a leitura atual não comprova coordenação por host |
| Backoff | `AcquisitionCoordinator` mantém falhas por target e aplica política de atraso | Não confundir com política compartilhada por host; criar reprodução antes de mudar |
| Descoberta progressiva | `ReaderDiscoveryTraversal.advanceDiscovery`, índices e materialização existentes | Medir oportunidades/cobertura; não montar segundo explorador |
| Background | Registro de `BGAppRefreshTask`, `expirationHandler` e `BackgroundFeedRefresh.run` | Testar o wiring do host; não criar engine própria de background |
| Migração pessoal | `LegacyUserStateImport` importa parte da biblioteca; comentário explicita exclusão de artigos salvos V1 | Não afirmar preservação completa: conferir gate específico e recuperação dos dados |
| Migração já especificada | `docs/product/MIG-V1V2-B_migracao_pessoal_spec.md` escolhe preservação com legado recuperável | O dossiê não reabre “migrar ou começar limpo”; executar/reconciliar a decisão existente |
| Desempenho visual | Correção local de consulta de idiomas com A/B Release já registrada | Preservar; não iniciar otimização genérica de SQLite a partir de hipótese histórica |

O importador legado é um achado de **cobertura incompleta identificada no código**, não prova de perda ocorrida em um aparelho. A coordenação de 429 por host é uma **lacuna a investigar**, não uma falha operacional já reproduzida. Os demais itens também devem manter essa distinção.

## 4. Priorização por retorno, custo e risco

Classificações relativas, sem estimativas de calendário: baixo = localizado; médio = múltiplos caminhos e integração; alto = plataforma, migração ou causa incerta. Não há dados para calcular ROI financeiro.

| Frente | Benefício / aderência | Esforço e custo recorrente | Risco | Destino |
|---|---|---|---|---|
| D01 — Evidência causal mínima | Muito alto / alta | Médio; baixo com eventos limitados | Instrumentação alterar a medição ou expor dados pessoais | Fazer primeiro, somente onde o trace atual não responde |
| D02 — Fim aparente e semântica de oferta | Muito alto / alta | Médio–alto, conforme causa | Corrigir o owner errado ou esconder starvation com UI | Integrar à pendência de B03 |
| D03 — HTTP e isolamento por host | Alto / alta | Médio; tende a reduzir tráfego inútil | Backoff global, retry agressivo ou perda de validadores | Testar agora; implementar somente diferença comprovada |
| D04 — Local restore/contextos/background | Muito alto / alta | Médio; baixo | Cancelamento descartar supply útil ou callback antigo contaminar UI | Completar jornadas existentes |
| D05 — Migração pessoal | Muito alto / alta para upgrade | Alto; manutenção de compatibilidade | Perda de salvos/coleções ou identidades falsas | Bloqueador da distribuição como upgrade de V1 |
| D06 — Cobertura exploratória | Alto / alta | Médio; orçamento de rede precisa ser controlado | Favorecer apenas fontes rápidas ou gastar sem relevância | Medir depois da continuidade; corrigir exclusão estrutural se encontrada |
| D07 — Rendimento, SQLite e recursos | Médio–alto / alta | Médio–alto; economia potencial | Micro-otimização prematura e nova complexidade | Intervenção condicionada a perfil causal |
| Novos schedulers, servidor agregador ou refresh completo | Retorno não demonstrado / baixa neste estágio | Alto / alto | Viola proposta e duplica responsabilidades | Não adotar |
| BGContinuedProcessingTask para crawling | Retorno não demonstrado / baixa | Médio–alto / manutenção por versão | Usar API fora do caso e compatibilidade do mínimo iOS 18 | Adiar; nenhuma dependência para continuidade do feed |

## 5. Restrições globais e foco da revisão

Preservar publicação imutável, histórico, dados pessoais, identidade de contexto, transações de admissão/checkpoint e limites de trabalho. Não alterar benchmark/corpus/oráculo para produzir PASS. Código e testes novos devem ficar fora de `bench/`. Não usar timer de UI, `loadMore` paralelo, `scrollTo` compensatório ou descarte de histórico como substituto de correção causal.

Os cinco casos de revisão obrigatórios, distribuídos nas tarefas abaixo, são: fonte saudável convivendo com 429 do mesmo host de outras fontes; fato durável tardio de A durante B; ausência de internet com edição local válida; migração interrompida com WAL/snapshots; e gesto sob pressão de banco/memória. A cobertura precisa verificar resultado e efeitos indevidos, não só retorno de métodos.

## 6. D01 — Completar evidência causal sem criar outra telemetria

**Origem:** dossiê §§18/19; amplia E01/E02/E09 do plano de pendências.

**Arquivos de partida:** `FeedMineApp/FeedMineApp/RunwayTrace.swift`, `FeedFrameMeter.swift`, `AppComposition.swift`; `Sources/FeedMineComposition/FeedRunwayDriver.swift`, `RunwayAcquisitionCycle.swift`; instrumentos em `instruments/` e scripts existentes. Não modificar todos por padrão: localizar primeiro o evento ausente.

**Entrada → saída:** eventos e IDs existentes → linha de tempo correlacionável, com relógio, perdas e proveniência explícitos. Instrumentação não decide política de produto.

- [ ] Mapear eventos disponíveis para aquisição, admissão, readiness, publicação, sessão e instalação. Produzir uma tabela de campos ausentes que impedem responder uma pergunta concreta.
- [ ] Correlacionar pelos IDs existentes de operação/target/revisão/edição; quando faltar relação, estender o evento atual. O mesmo item pode participar de várias operações: não exigir uma cadeia artificialmente linear nem um ID global para tudo.
- [ ] Acrescentar apenas os campos indispensáveis: quantidades úteis adiante, motivo de suspensão/recusa e vínculo com publicação/apresentação. Usar relógio monotônico do produtor; não subtrair timestamps de host/simulador sem âncora válida.
- [ ] Verificar encoding, teto e `trace_truncated` com o teste existente ou regressão focal do host. URL, consulta de busca e conteúdo pessoal não entram em exportação pública em claro.
- [ ] Comparar o mesmo roteiro com coleta ligada/desligada; registrar custo e perdas. Se o instrumento muda o sintoma, reduzir coleta antes de inferir causa.

**Pronto:** uma falha concreta pode ser localizada por estágio com trace limitado e artefatos identificados; nenhuma necessidade de dashboard, novo banco ou logging por pixel.

## 7. D02 — Explicar o fim aparente e corrigir somente a fronteira responsável

**Origem:** §§14/18.1/20/21; integra E02/E03, sem abrir outro projeto de runway.

**Arquivos/testes:** `FeedRunwayDriver`, `RunwayAcquisitionCycle`, `FeedSession`, `RunwayController`, `RunwayPolicy`; `Tests/FeedMineCompositionTests/FeedRunwayDriverTests.swift`, `RunwayAcquisitionCycleTests.swift`, `Tests/FeedMineRuntimeTests/RunwayControllerTests.swift` e jornada nativa vigente.

**Entrada → saída:** oferta, cursores e posição reais → motivo verificável para esperar, continuar ou comunicar escassez. Janela vazia não comprova esgotamento global.

- [ ] Aproveitar o último resultado terminal válido de B03 e seus artefatos. Não reiniciar ensaio longo apenas porque há um novo relatório.
- [ ] No instante da ruptura, verificar nesta ordem: publicado adiante → pronto elegível → supply examinável → mídia recuperável → fontes elegíveis ainda não tentadas → execução/backoff/recursos. Registrar também quando o trace não permite concluir.
- [ ] Criar reprodução focal da fronteira suspeita, com fonte lenta e fonte saudável independentes. Exigir segunda oportunidade após o drain, sem gesto artificial para acordar a produção.
- [ ] Se reproduzido, corrigir no owner correspondente, provar vermelho/verde e repetir a jornada. Se não reproduzido, registrar hipótese refutada ou insuficiente, sem “conserto preventivo”.
- [ ] Reexecutar B03 pela trilha congelada: 30 min, avanços distintos, ritmos/rajadas e oferta prevista no benchmark. Não substituir por contagem de gestos enviados.

**Pronto:** continuidade aprovada ou impedimento explícito com causa/artefato; nenhuma mensagem terminal baseada apenas em timeout ou limite de consulta. Não tratar “zero pausa ≥1 s” como compensação para avanços faltantes.

## 8. D03 — Auditar HTTP condicional e contenção por host

**Origem:** NetNewsWire no dossiê §§3/20 E13/E18. A técnica externa ainda deve ser conferida em revisão fixada se for usada como referência de implementação.

**Arquivos/testes:** `Sources/FeedMineSyndication/SyndicationHTTP.swift`, `SyndicationConnector.swift`, checkpoint existente; `Sources/FeedMineAcquisition/AcquisitionCoordinator.swift`, `AcquisitionBackoff.swift`; `Tests/FeedMineSyndicationTests/SyndicationHTTPTests.swift`, `SyndicationConnectorTests.swift`, `Tests/FeedMineAcquisitionTests/AcquisitionBackoffConcurrencyTests.swift`.

**Entrada → saída:** resposta HTTP e falha operacional → fato específico de atualização/erro e elegibilidade de tentativa, preservando isolamento de outras origens. Não duplicar a política de retry em conector, aquisição e UI.

- [ ] Conferir testes existentes de ETag/Last-Modified, 304 condicional/inválido, 200 vazio/repetido, 5xx, timeout e cancelamento. Completar apenas casos sem prova discriminante.
- [ ] Reproduzir A e B no mesmo host com 429/Retry-After, e C em outro host saudável. Observar novos starts, retries e publicação de C; distinguir trabalhos já autorizados de novos starts.
- [ ] Verificar se status e cabeçalhos necessários sobrevivem ao transporte/conector. Hoje 429 passa pelo caminho genérico de status inesperado; isso não prova suporte ao prazo informado pelo servidor.
- [ ] Se houver lacuna, definir no owner atual o alcance da contenção e a normalização da chave de host/origem, incluindo porta e redirects conforme o caso. Fixar tratamento de Retry-After ausente, inválido, em segundos ou data, e limite operacional seguro; não escolher esses valores copiando NetNewsWire.
- [ ] Preservar proteções de host público, redirects e limite de bytes. 304 não vira nova história nem “fim do feed”; erro de transporte não vira sucesso de aquisição.

**Pronto:** hosts saudáveis continuam produtivos, novos starts respeitam a política comprovada e as retentativas não amplificam falhas. Se o comportamento atual já atender, entregar evidência e encerrar sem nova política.

## 9. D04 — Provar reutilização, retorno offline e expiração no host

**Origem:** §§10/18.3–5/20 E05–09; complementa E03/E06/E08 do plano anterior.

**Arquivos/testes:** `FeedMineApp.swift`, `AppComposition.swift`, `Sources/FeedMineRuntime/BackgroundFeedRefresh.swift`, `FeedSession.swift`, driver; `Tests/FeedMineRuntimeTests/BackgroundFeedRefreshTests.swift`, testes de driver e `FeedMineApp/FeedMineAppTests/CompositionTests.swift`/UI.

- [ ] Executar A→B→A com callback de A tardio: B conserva sua apresentação; conteúdo canônico válido pode persistir e servir no retorno a A. Contar rede, edição, âncora e assets reutilizados.
- [ ] Encerrar o processo e relançar realmente offline com edição/recursos conhecidos. Observar primeira janela útil, bitmap e posição; nenhuma resposta de rede é pré-requisito para mostrar o que já está local.
- [ ] Expirar/cancelar a oportunidade do BGTask durante rede, preparo e transação. No host, verificar conclusão da tarefa uma vez, bloqueio de novos starts e reentrada sem duplicação. Teste puro de `BackgroundFeedRefresh.run` não encerra o wiring do aplicativo.
- [ ] Exercitar áudio ativo, retorno do artigo, Dynamic Type e pressão de memória nos percursos relevantes. Reusar as provas existentes e acrescentar somente o evento que faltou.

**Pronto:** IDs, offset e dados pessoais preservados; interrupção não exige scheduler próprio nem promessa de periodicidade do iOS. Sessão de download em background e processamento do feed são capacidades diferentes [A1, A2].

## 10. D05 — Fechar preservação pessoal V1→V2 no gate já especificado

**Origem:** §18.6/20 E10. Prioridade P0 para distribuir V2 como atualização de uma instalação V1; independente de B01–B06.

**Spec vigente:** [MIG-V1V2-B](../../product/MIG-V1V2-B_migracao_pessoal_spec.md). Sua opção B já determina preservação e legado recuperável. O documento tem base/branch/allowlist e protocolo próprios: este plano não os substitui nem autoriza rebase/execução em base diferente.

**Arquivos de partida:** `LegacyUserStateReader`, `LegacyUserStateImport`, `ReaderLibraryStore`, superfícies de salvos e testes constantes da allowlist da spec. Não criar `PublicationCardID` para fingir que um artigo V1 já era uma ocorrência V2.

- [ ] Reconciliar a entrega existente do gate e sua integração na candidata. Não assumir que ausência no checkout atual significa inexistência em outra branch; localizar SHA/evidências antes de implementar.
- [ ] Inventariar salvos/snapshots, caixas, coleções, fontes importadas/ativação, presets, preferências e posições nas autoridades reais. Incluir UserDefaults e leitura consistente com WAL; trabalhar em cópias de teste.
- [ ] Comparar o inventário com o relatório do importador atual. Cada categoria termina como migrada, preservada recuperável, irresolvida com motivo ou falha — nunca silenciosamente descartada.
- [ ] Completar lacunas dentro da spec: preservação durável na V2, mapeamento determinístico e recibo transacional/idempotente; nenhuma mudança na origem V1 nem no histórico publicado.
- [ ] Fazer upgrade sobre a mesma instalação de teste povoada, relançar offline, abrir salvos, repetir importação e injetar falha antes do commit. Provar recuperação e ausência de duplicação.

**Pronto:** evidência por categoria e gate MIG-V1V2-B encerrado conforme a spec. Manter o arquivo V1 no disco sem torná-lo recuperável na V2 não satisfaz preservação. Testes de migração do schema V2 não substituem upgrade entre produtos.

## 11. D06/D07 — Medir exploração e eficiência antes de otimizar

**Origem:** §§14/15/18.7–10; complementa capacidade e catálogo já implementados.

**Arquivos/testes:** `Sources/FeedMineComposition/ReaderDiscoveryTraversal.swift`, `ReaderDiscoveryPool.swift`, `StageBudgetPolicy.swift`; aquisição/preparação existentes; consultas em `FeedMinePersistence`. Testes `ReaderDiscoveryTraversalTests`, `PipelineHeadroomTests`, `ContentStoreCandidateWindowScaleTests` e instrumentos de jornada.

- [ ] **D06:** em corpus conhecido e oportunidades finitas, separar elegíveis, nunca tentadas, tentadas, produtivas e em backoff, por contexto/host. Observar cobertura enquanto runway está saudável; não usar o total bruto do catálogo como denominador de elegibilidade.
- [ ] Demonstrar que novas fontes recebem oportunidades, inclusive lentas ou temporariamente falhas após recuperação. Uma execução finita não prova cobertura eventual universal. Só ajustar prioridade se houver exclusão estrutural reproduzida.
- [ ] **D07:** medir respostas → itens novos → elegíveis → preparados → publicados → admitidos, deduplicando identidade/revisão e atribuindo corretamente reuso entre operações. Registrar bytes e decode separadamente.
- [ ] Comparar datasets pequeno/grande e gesto ativo/repouso: consultas críticas, planos, duração de escrita, espera/locks, tamanho WAL e frames. Não mudar WAL, índices, batch ou checkpoint sem perfil causal.
- [ ] Aplicar pressão de RAM/disco/térmica e modos de economia no aparelho. Trabalho especulativo cede sem perder dados pessoais ou renegociar card publicado. A distância visual pronta e a velocidade observada são sinais diagnósticos, não uma fórmula obrigatória nova de reserva.
- [ ] Se um custo dominante for confirmado, escolher uma alteração mínima, comparar antes/depois no mesmo roteiro e retirar mecanismo redundante somente com substituição provada.

**Pronto:** melhoria mensurada de continuidade/custo sem reduzir diversidade, cobertura ou estabilidade. Se não houver gargalo demonstrado, a entrega é a evidência e nenhuma refatoração.

## 12. Sequência e relação com os planos existentes

| Ordem | Entrega | Dependência / condição de avanço |
|---|---|---|
| 1 | Reconciliação da candidata + D01 mínimo | Reaproveitar o snapshot/artefatos do executor; não disputar a worktree ativa |
| 2 | D02 e D03 focais | Diagnosticar continuidade e HTTP; só corrigir falhas reproduzidas |
| 3 | D04 e D05 | Completar provas no host e preservação de upgrade; D05 não precisa esperar otimização de throughput |
| 4 | D06/D07 | Medir eficiência depois de continuidade, ou antes apenas quando necessário para localizar a causa de D02 |
| 5 | Certificação consolidada | Mesma candidata identificada, gates aplicáveis e evidência física; mudança posterior exige reavaliar provas afetadas |

Este plano **complementa** o [estado e pendências](2026-10-18-feedmine-estado-atual-e-pendencias.md). Os IDs Dxx evitam colisão com E01–E10 daquele plano e com E01–E20 do dossiê. As melhorias de interface/mídia continuam no [plano dos estudos](2026-10-18-feedmine-aproveitamento-dos-estudos.md); não devem gerar um segundo roteiro de infraestrutura.

## 13. O que fica de fora

Não adotar os números de 500 tarefas/uma conexão por host de outro app como configuração ótima. Não migrar para backend agregador, refresh global obrigatório, milhares de downloads em background, cache por funcionalidade ou nova engine de feed. Não trocar o modelo de publicação por timeline mutável para imitar concorrentes.

`BGContinuedProcessingTask` pode ser avaliado futuramente para trabalho explícito iniciado pelo usuário, com disponibilidade e fallback adequados ao mínimo iOS 18; não é pré-requisito para descoberta ou correção de B03 [A2]. Fórmulas de risco de reposição e yield do dossiê entram primeiro como análise, com tratamento de repouso e amostras insuficientes; não como política automática.

## 14. Critério de encerramento e fontes

Cada tarefa deve terminar com: base/SHA e bytes relevantes, pergunta, resultado PASS/FAIL/NOT_RUN/BLOCKED, causa confirmada ou desconhecida, artefato e decisão. Correção exige reprodução discriminante e prova da jornada pertinente. Uma hipótese refutada encerra a investigação correspondente sem obrigar alteração de código.

**Resultado esperado:** menor incerteza sobre continuidade, rede e preservação; correções pequenas nos owners existentes; nenhuma certificação baseada apenas em analogias com outros aplicativos.

Fontes externas primárias verificadas em 18/10/2026:

- **A1 —** [Apple: Downloading files in the background](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background?changes=latest_minor): transferências administradas pelo sistema, limites e overhead por tarefa; a recomendação de menos transferências maiores não implica poder combinar feeds de hosts independentes.
- **A2 —** [Apple WWDC25: Finish tasks in the background](https://developer.apple.com/videos/play/wwdc2025/227/): distinguir tarefas de continuidade de trabalho iniciado pelo usuário de atualização oportunista e transferência de arquivos.

As demais comparações externas permanecem atribuídas ao dossiê, com suas ressalvas de evidência. Este trabalho produziu apenas o plano; não executou os experimentos nem alterou código de produção.
