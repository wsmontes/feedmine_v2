# FeedMine V2 — avaliação da implementação até o build 53

Data: 18/out/2026, America/Vancouver. Pedido: avaliar o trabalho executado e planejar somente o restante. Esta avaliação não altera código de produção nem declara aceite de release.

## Base e método

- Checkout de produto avaliado: `/Users/wagnersilvamontes/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2`.
- HEAD: `b0b961a049f82fece037363a6cb0e986d556330c`, branch `codex/v2-fluidez-capacidade`, build 53. Árvore limpa na inspeção.
- Comparação: `bc6a38dc..b0b961a0`: 25 commits, 59 arquivos, 4.932 inserções e 248 remoções. Nenhuma diferença em `bench/` nesse intervalo.
- Inspeção dos commits, diff, owners, call sites, testes e registro `docs/reviews/2026-10-17-v2-plan-execution.md` da worktree de produto. Revisão independente somente leitura dos caminhos de aquisição, mídia, residência, instalação e aposentadoria.
- Nova execução da suíte Swift e verificação nativa focalizada. A suíte completa de UI e o benchmark não foram repetidos nesta auditoria.
- “Presente” abaixo significa implementação identificada no código; “validado em teste” não equivale a jornada visual/física aprovada. Falhas apontadas por leitura de call sites ainda exigem regressão executável antes da correção.

## Conclusão

Houve avanço substancial: ingresso limitado, instalação sem SQL direto, callbacks de aquisição desacoplados, primeira publicação antes da rodada completa, descoberta indexada, preferências neutras corrigidas, expressão de busca versionada, recuperação de salvos e ações internas de fonte.

A conclusão **não** é que só faltam R20–R23. R16 e R17 permanecem incompletas; a revisão também reabre partes de R03/R04, R06/R07 e R09. Alguns testes exercitam a decisão isolada, mas não todos os caminhos reais que deveriam passar por ela. G1–G4 continuam abertos nesta avaliação.

## Evidências e limites

| Verificação | Resultado | Alcance |
|---|---|---|
| `swift test`, nesta auditoria, HEAD build 53 | **1.481 executados, 3 ignorados, zero falhas**, exit 0; 110,69 s | Pacote; os três skips exigem catálogo/corpus de referência ausentes |
| Cinco testes focais do host iOS, nesta auditoria | **5/5, zero falhas**, exit 0; 62,87 s | Instalação, bookmark, tempo capturado, rollback de ativação e A→B→A; não é a suíte inteira |
| Unitários nativos anteriores, segundo registro | 140/140 no build 52; CompositionTests 89/89 na rodada posterior | Histórico; não reemitido como prova nova do build 53 |
| UI anterior, confirmado no log `/tmp/fm-v2-full-pt.log` | 74 executados, 6 ignorados, **37 falhas**, 4.814 s | Evidência histórica de não certificação; falhas incluem premissas de fixture/ambiente e possíveis defeitos reais, a separar |
| Release: pixels/gestos/hitches | **NOT_MEASURED nesta auditoria** | Unitários e Debug não provam frames em Release |
| B01–B06 no HEAD atual | **NOT_RUN nesta auditoria** | Nenhum resultado histórico certifica esta árvore |

Log novo de pacote: `docs/reviews/evidence/2026-10-18-build53-audit/package.log.gz`. Hashes, comandos, base e caminhos de `.xcresult` ficam no manifesto de evidências desta auditoria.

## Reconciliação de R00–R23

| Tarefa anterior | Estado observado | O que preservar / o que falta |
|---|---|---|
| R00 | Provas/premissas reconciliadas | Preservar correções de fixture e locale; não repetir a primeira reconciliação |
| R01 | Implementação presente e contratos focalizados | Ingresso finito e tempo capturado; completar proteção da UI contra I/O indireto de recursos |
| R02 | Parcial: SQL saiu de `install`; fence e leitura single-flight presentes | O pacote completo só é fornecido por testes; caller real agenda metadados depois. Completar P06 e custo de membership, sem outro cache |
| R03 | Proteção da banda anterior e preservação da identidade presentes | Reaberta: prova nativa anterior à exposição, sobretudo após trim de memória |
| R04 | Gate e pending jump presentes | Reaberta: bypass de Voltar ao início, destino irrecuperável e intervalo entre bandas |
| R05 | Pump de rede e consumidor separados, backlog limitado pelo plano finito | Preservar; integrar aposentadoria que cubra todos os starts/transporte |
| R06 | Primeira fonte pode publicar antes da lenta | Incompleta para resultados posteriores ao encerramento do drain: falta acionamento causal |
| R07 | Slice não espera o preparo inteiro no caminho de produto | Incompleta para wake tardio, ownership e quantidade de Tasks de preparo |
| R08 | Índices e materialização fora da seção crítica presentes | Preservar; repetir atualização/revogação de catálogo na integração |
| R09 | Redução por pressão presente | Parcial: tabelas fixas, sem dimensionamento por rendimento útil; autorização zero vira um; leitura de disco no MainActor |
| R10 | Ensaio de contenção e regressões de atomicidade presentes | Preservar; não confundir um append+uma admissão com prova de capacidade sustentada |
| R11 | Contratos A→B→A/confirmar filtros presentes | Preservar; dependem de resolver wake e aposentadoria; jornada física ainda falta |
| R12 | Salvos/duas referências/falha parcial cobertos em testes | Reabertura de handle não equivale a morte real de processo; falta prova offline/purge física |
| R13 | Neutral e combinações de mídia corrigidos | Preservar; verificar na candidata final, sem reimplementar |
| R14 | Expressão única e compatibilidade literal versionada presentes | Preservar; backend unificado de fontes ainda pré-filtra a expressão inteira como literal |
| R15 | Origem de busca e erros de persistência/ativação tratados na composição | Preservar; falta jornada visual integrada |
| R16 | Tipos, consultas locais e store de token presentes | Parcial: sem superfície conectada; consulta incompleta, síncrona e com erros silenciados |
| R17 | Tipos de fato e desempate puro presentes | Parcial/dormente: não persistido nem ligado; gate de versão amplo demais e comparador com risco de ciclo |
| R18 | Loading factual e continuidade inicial melhorados | Preservar; falta jornada de instalação limpa/acessibilidade na candidata |
| R19 | Ver fonte interno separado de abrir site | Preservar; incluir retorno e fonte não selecionada nos ensaios finais |
| R20 | Rollback de preset e espera de aquisição antes de invalidar transporte | Parcial: rollback de contexto não é ativação de catálogo; não cobre mídia nem todas as corridas de aposentadoria |
| R21 | Não encerrada | Triagem das 37 falhas de UI, locales, VoiceOver, Dynamic Type e jornadas compostas |
| R22 | Há testes nomeados de headroom, porém sem carga/meta completas | 5 testes atuais não medem 10× por estágio com a carga do plano |
| R23 | Não encerrada | Simplificação comprovada, candidata única, Release, revisão e B01–B06 físico |

## Achados prioritários confirmados por leitura dos call sites

Estes achados são estáticos; a auditoria não afirma que foram reproduzidos visualmente. Os testes propostos no novo plano devem transformar cada um em prova vermelha discriminante.

### A1 — P1: resultado durável/readiness tardio não inicia nova oportunidade

`RunwayAcquisitionCycle.swift:127–129` entrega o resultado e chama `noteLocalSupplyChanged`; `FeedRunwayDriver.swift:236–240` deixa de consumir a stream após o primeiro resultado útil. O monitor em `:261–266` apenas guarda estado de conclusão. A notificação de mídia em `:124–129` também atualiza fatos sem iniciar `drive` quando não há execução causal ativa.

Gatilho: A publica e o drain retorna; depois B admite supply ou termina mídia, com usuário parado. Não há chamada no caminho que garanta nova publicação imediatamente. O teste atual de fonte rápida verifica a primeira publicação enquanto a lenta espera; não exige a segunda após o retorno. **Plano P02.**

### A2 — P1: transporte pode ser invalidado com preparo de mídia ainda autorizado

`MediaPreparationOpportunity.request` cria uma Task sem handle no owner (`:23–26`). `MediaPrefetcher.prepareAll` abre revisões seguintes quando libera slots (`:235–245`). `FeedAssociation.close`, em `AppComposition.swift:3699–3716`, aguarda apenas `AcquisitionCoordinator.settleInFlight`, ignora seu Bool e invalida a URLSession compartilhada.

Gatilho: mais revisões que slots, primeira leva suspensa, close e liberação tardia. Não existe fence comum comprovada que impeça os próximos starts de mídia após invalidar a sessão. O timeout de aquisição também não prova ausência de starts posteriores. **Plano P01.**

### A3 — P1: Voltar ao início contorna a prontidão

`Sources/FeedMineUI/FeedScreen.swift:204` atribui `capture.positionID = items.first?.id` diretamente. Isso altera o valor lido pelo Binding; não chama seu setter e, portanto, não passa por `requestPosition` de `FeedNativeViewport`.

Gatilho: cabeça com bitmap liberado e ação Voltar ao início. O gate puro pode estar correto enquanto esse caminho expõe o destino sem preparar seus pixels. **Plano P03.**

### A4 — P2: proteção de duas bandas protege o intervalo inteiro

`FeedSession.swift:211–220` calcula `min(first, previous.lowerBound)...max(last, previous.upperBound)`. Isso é o intervalo que contém as bandas, e não sua união quando estão separadas. A reconstrução em `:231–235` também lê/decodifica o trecho intermediário.

Gatilho: salto entre extremos de histórico admitido. Memória/decode crescem com a distância, apesar de o comentário prometer no máximo duas bandas. **Plano P04.**

### A5 — P2: destino irrecuperável não encerra pending jump

`FeedSession.swift:239–244` preserva a carta e registra imagem irrecuperável. `FeedDestinationGate.readinessAfterPreparation` (`:35–40`) só declara indisponibilidade se a carta desapareceu; com identidade preservada e imagem nil, responde novamente `needsPreparation`. O switch em `FeedNativeViewport.swift:62–63` mantém o pending jump.

Gatilho: asset removido antes de preparar o destino. A preservação correta da identidade torna inalcançável o critério de falha escolhido pelo gate. **Plano P03.**

### A6 — P2: política de recursos viola autorização zero e mantém I/O de disco na UI

`StageBudgetPolicy.swift:85` usa `max(1, capacity)`, inclusive quando `initialParallelism` foi explicitamente zero. O contrato de `CollectionLaunchSettings` descreve zero como negação de recurso. Além disso, o getter `FeedAssociation.resources` chama `currentStagePressure`; esta executa `resourceValues` de volume sob o MainActor (`AppComposition.swift:2360–2375`).

A adaptação atual só reduz tabelas de bootstrap. `PipelineHeadroomTests.testAvailableResourcesIncreaseUsefulWork` compara configuração 1 versus 8; não demonstra adaptação a rendimento medido sob a mesma configuração. **Plano P05.**

### A7 — P2: busca unificada ainda perde resultados válidos e mascara falhas

`ReaderSearchResults.swift:23–68` é síncrono no host MainActor, usa `try?` e limita artigos à primeira janela de 400, sem expor continuação. Fontes passam antes por `matchingSources(query: term, limit: 40)`, cujo SQL procura a string inteira com LIKE (`LegacyCatalogReader.swift:466–477`). Aplicar a expressão depois não recupera linhas já descartadas pelo pré-filtro literal.

Gatilhos: positivos em campos diferentes; termo negativo; ocorrência após a primeira janela; falha de storage. O resultado pode parecer vazio/completo quando não é. Nenhum call site de produto conecta `unifiedSearch`/`ReaderSearchResultsStore` à superfície; os usos atuais são testes. **Plano P07/P08.**

### A8 — P2: versão editorial desconhecida recebe comportamento novo

`SelectionEngine.swift:126` usa `sequencingPolicyVersion >= 5`, contrariando o comentário imediatamente anterior e o contrato de versões explícitas. Versão 6/99 também recebe diversidade se houver contexto. **Plano P09 antes de habilitar v5.**

### A9 — P2: comparador de diversidade pode deixar de ser transitivo

`SelectionDiversityContext.isLessRepeated` pula dimensões por par quando um candidato não as conhece; `SelectionEngine.sorted` usa recência quando o par não desempata. Isso permite a seguinte contraexemplificação lógica, ainda sem teste Swift novo nesta auditoria:

- Mesma fonte para A/B/C e mesma relevância; histórico repete provedor P e assunto espaço.
- A: provedor P, assunto desconhecido, data 3. B: provedor Q, assunto espaço, data 2. C: provedor desconhecido, assunto oceano, data 1.
- B precede A por provedor; C precede B por assunto; A precede C por recência. Forma-se B < A < C < B.

`sorted` exige ordenação estrita consistente. Antes de ligar o comportamento em produção, criar testes de transitividade/permutação e corrigir a estratégia sem tratar ausência como novidade. **Plano P09.**

### A10 — P2: pacote completo de instalação só é exercitado pelos testes

A busca por `PreparedFeedInstallation(` encontra, em produto, somente `AppComposition.swift:2982`, sem a metade `bookmarks`; os pacotes com metadados são construídos em `CompositionTests.swift`. O overload real instala apresentação e agenda `scheduleBookmarkRefresh` depois. A primeira projeção pode aparecer com marcações vazias/anteriores e o erro dessa leitura é convertido em nil sem recuperação visível (`AppComposition.swift:3280–3285`).

SQL ter saído da função de instalação é uma melhoria real, mas não comprova o contrato de apresentação **com metadados previamente preparados** pelo caminho real. Completar o handoff mantendo a fence e sem criar outro cache. **Plano P06.**

## O que não deve ser refeito

Preservar commits, testes de regressão úteis, proveniência, Set de membership, ingresso finito, instalação sem SQL direto, pump da aquisição, índice da travessia, compatibilidade de busca, neutralidade, salvos e fonte interna. Corrigir caminhos/contratos ausentes nesses owners. Não criar um segundo runtime nem substituir o pipeline inteiro.

Observação de latência: `testContextSwitchUnderLoadReusesCanonicalWork` passou, mas levou **61,248 s** nesta rodada. O teste mantém a fonte suspensa até o fim e não exige que o retorno conclua antes do timeout de rede. Isso comprova asserções de edição/âncora, não mudança de contexto barata; P12 deve exigir conclusão enquanto a fonte alheia ainda está suspensa. A causa exata desse tempo requer trace, não foi declarada como reproduzida nesta auditoria.

O registro antigo contém estados cumulativos contraditórios: G1 foi chamado “fechado contratualmente” com Release NOT_RUN, e depois explicitamente reaberto após a UI vermelha. A próxima execução deve ter um resumo de estado atual por gate, preservando o histórico, sem inferir conclusão do último nome de commit.
