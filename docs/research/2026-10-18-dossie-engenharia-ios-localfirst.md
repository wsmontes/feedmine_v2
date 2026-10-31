# FeedMine — Engenharia de feeds em larga escala no iOS

## Benchmark de arquiteturas reais, coordenação UI–runtime–banco–background e roteiro de evidências

**Relatório técnico e de produto | 18 de outubro de 2026 | Revisão 1.0**
**Objeto:** FeedMine V2, leitor local-first/offline-first que descobre conteúdo de milhares de fontes externas sem servidor próprio de agregação.
**Status:** pesquisa externa + leitura de documentação/código + hipóteses e plano de investigação. **Não** é laudo de performance medido no Mac nem aprovação de release.
**Decisões de projeto:** preservar a arquitetura vigente, não multiplicar caches, filas, schedulers ou gerações; testar comportamento observável antes de otimizar uma operação isolada.

> **Tese:** o desafio raro do FeedMine não é apenas fazer HTTP paralelo ou renderizar uma lista rápida. É transformar latências heterogêneas de milhares de fontes em uma **reserva local de histórias apresentáveis**, preservando um histórico editorial estável e uma interface independente da execução. Produtos próximos resolvem pedaços desse problema; nenhum benchmark público inspecionado demonstrou a combinação exata e na mesma escala operacional.

### Convenção de evidência

- **[CÓDIGO]:** comportamento identificado em arquivo publicamente auditável (link incluído); não implica teste de execução neste relatório.
- **[OFICIAL]:** documentação de fabricante, App Store, nota de release ou suporte; descreve intenção ou comportamento anunciado, não arquitetura interna comprovada.
- **[FEEDMINE]:** Blueprint v0.4, F05/F06/PRDs e trechos do repositório FeedMine V2; separar especificação de aceite real.
- **[INFERÊNCIA]:** dedução técnica plausível, não evidência da implementação de terceiros.
- **[PROPOSTA]:** decisão possível para o FeedMine, não mudança já feita nem arquitetura ratificada.
- **[DESCONHECIDO]:** dado indisponível, benchmark não medido ou mecanismo interno não público.

**Nota de escopo temporal:** exemplos de código foram consultados na branch padrão pública em 18/10/2026. Arquivos podem mudar. Os caminhos e os respectivos repositórios são a âncora auditável; links para a branch `main` não são pin de versão. Não atribuí aos fabricantes quantidade de fontes, SLA de atualização, consumo de memória ou limite de throughput que não publicaram.

---

# 1. Resumo executivo

Os melhores comparadores encontrados são **NetNewsWire, FeedFlow, feeeed, Reeder, Tapestry, NewsBlur, lire e GoodLinks**. Acrescentei **Omnivore (histórico)** como contraprova importante: é aberto e oferece leitura offline, mas seu serviço dependeu de backend próprio e hoje é self-hosted; por isso não é um modelo para a aquisição no telefone. A pesquisa avalia também os mecanismos Apple que, na prática, limitam toda a estratégia.

**Conclusões principais:**

1. **NetNewsWire** é o exemplo mais útil de implementação Swift auditável para URLSession, concorrência operacional, HTTP 304/429, condicionais, progresso por fonte e BGAppRefreshTask. Não demonstra um runway editorial adaptativo; seus limites estáticos servem à proteção de I/O, não à garantia de infinitude.
2. **FeedFlow** é o melhor contraponto de pipeline cross-platform com SQLite, `flatMapMerge(concurrency=...)`, cache HTTP, pré-busca de conteúdo e sincronização seletiva. Seu fluxo local acumula resultados para inserção posterior; um lote completo não pode se tornar pré-requisito para publicar resultados independentes no FeedMine.
3. **feeeed** é a comparação de produto mais direta: declara processamento e privacidade no dispositivo, múltiplos tipos de fonte, modo offline e descoberta personalizada. Sua implementação interna não é aberta. Seria errado atribuir ao app uma política específica de filas, reservas ou banco.
4. **Reeder (novo)** explicita uma distinção útil entre buscar conteúdo diretamente e sincronizar somente estado pessoal/posição via iCloud; a timeline é centrada em posição, não em zerar contadores de unread.
5. **Tapestry** prova um modelo de conectores protocol-specific que entregam itens normalizados à timeline. Seu repositório contém a API e os conectores, **não** a implementação completa do app.
6. **NewsBlur 15** documenta uma grande melhoria de UI: cache aparece antes da rede; thumbnails e texto são preparados antes do scroll; resultados entram incrementalmente sem reconstruir a lista. Mas a coleta remota se apoia em infraestrutura de servidor — comparação correta para apresentação, não aquisição local.
7. **lire/GoodLinks** ajudam na obtenção de texto completo, leitura e persistência offline. Não comprovam exploração contínua de milhares de fontes independentes.
8. **Apple iOS** não oferece execução permanente garantida em background para um crawler local. `BGAppRefreshTask`, `BGProcessingTask`, background `URLSession` e `BGContinuedProcessingTask` têm finalidades e restrições distintas. Não criar produto que dependa de dezenas de milhares de tarefas disparadas em background.

**O FeedMine já está melhor orientado que uma arquitetura RSS convencional em uma dimensão:** o Blueprint v0.4 formaliza aquisição, admissão, supply canônico, seleção, preparação de mídia, publicação imutável e sessão de leitura. Mas a existência de módulos e testes não prova continuidade real, estabilidade física ou cobertura do catálogo. A prioridade é comprovar as invariantes, identificar a etapa que perde a reserva e simplificar o que concorre com os owners atuais.

## 1.1. Decisão proposta em uma frase

**Não transplantar arquiteturas de concorrentes.** Auditar as fronteiras existentes do FeedMine com instrumentos equivalentes aos dos melhores projetos abertos, eliminar bloqueios globais e demonstrar num iPhone que a UI permanece local enquanto o runtime amplia a oferta sem fim artificial.

## 1.2. Matriz rápida

| Produto | Aquisição direta no iOS | Offline / banco local | Código para auditar | Melhor aprendizado | Restrição de comparabilidade |
|---|---|---|---|---|---|
| NetNewsWire | Sim, modo local | Sim | Swift aberto | HTTP, falhas por host, progressão, BGTask | Feed de assinaturas; não catálogo exploratório |
| FeedFlow | Sim, modo local | Sim, SQLDelight/SQLite | KMP + SwiftUI abertos | Concorrência limitada, merge, persistência | Acumulação em lote de parte da aquisição |
| feeeed | Declaradamente no aparelho | Sim, modo offline | Não encontrei runtime aberto | UX de descoberta local e heterogênea | Interior de pipeline desconhecido |
| Reeder (novo) | Sim, conteúdo direto | Sim; iCloud para dados selecionados | Fechado | Posição da timeline e separação de estado pessoal | Não demonstra busca em catálogo amplo |
| Tapestry | Por conectores no app | Persistência declarada | API/conectores; app fechado | Canonicalização por plugin | Timeline de fontes explicitamente seguidas |
| NewsBlur 15 | Em grande parte mediada por servidor | Sim, cache de histórias | Código amplo disponível | UI desacoplada de aquisição | Vantagem de backend próprio |
| lire | Sim, modo standalone | Sim, texto completo | Fechado | Extração e cache de artigos | Escala de fontes não pública |
| GoodLinks | URLs salvas pelo usuário | Sim | Fechado | Texto offline e limpeza | Não há descoberta distribuída contínua |
| Omnivore (histórico) | Cliente de backend/self-host | Sim | iOS e servidor abertos | Modelo offline e estado do leitor | Não é referência de runtime local sem servidor |

---

# 2. O que exatamente torna o problema do FeedMine diferente

Em um agregador com backend próprio, o servidor pode visitar milhares de origens, armazenar o corpus, deduplicar e ordenar. O iPhone recebe uma API rápida que contém aquilo que já foi produzido. No FeedMine, as fontes externas são descobertas e consultadas em runtime, a produção acontece no próprio dispositivo e a UI não pode pagar o custo da rede no momento do scroll.

O problema contém cinco relógios independentes: **tempo humano de consumo, latência de cada fonte, custo de preparação editorial/mídia, custo de transações no armazenamento, e oportunidades de execução do iOS**. Concorrência elevada num deles não sincroniza automaticamente os outros.

Uma arquitetura só será adequada quando responder conjuntamente:

- **Consumo:** quão depressa uma pessoa desloca o viewport e que trabalho visual efetivamente exige?
- **Oferta:** quantos cards locais, elegíveis e apresentáveis existem na frente da âncora, não apenas quantas URLs foram coletadas?
- **Reposição:** qual a distribuição observada do tempo *até conteúdo publicado*, incluindo fonte, parser, banco, seleção, mídia e commit?
- **Exploração:** novas fontes do catálogo continuam recebendo oportunidades enquanto a reserva está saudável?
- **Durabilidade:** filtro, leitura externa, background e relançamento preservam edição, cards, posição e dados pessoais?

**Antipadrão central:** `HTTP completou` → `supply pronto` → `feed abastecido`. Essas três afirmações são diferentes. Um 304 é sucesso de transporte sem conteúdo novo; uma fonte 200 pode entregar zero itens válidos; dez itens no banco podem não oferecer uma história apresentável; dez cards preparados atrás da âncora não são dez cards adiante.

## 2.1. Proibição prática de falsas garantias

Não é válido afirmar que “20 cards compram 20 segundos”, nem que “10 requisições simultâneas bastam”, sem medir velocidade, distribuição de alturas, latência p95/p99 e rendimento por fonte. Tamanhos finitos de batch e proteção de RAM/rede são necessários; **não** se convertem em horizonte editorial fixo.

## 2.2. Comparações justas e injustas

Comparar NetNewsWire e FeedFlow diretamente com o FeedMine é justo para HTTP, erro, parsing e banco. Comparar NewsBlur com o FeedMine é justo para scroll e cache local, mas injusto para custo de origem sem normalizar a presença de seu servidor. Comparar feeeed e Reeder é justo para experiência local e privacidade, porém não para afirmações sobre atores, SQLite, número máximo de fontes ou scheduling interno. Comparar Tapestry é justo para a fronteira de conectores, não para inferir seu mecanismo de publicação.

---

# 3. NetNewsWire: estudo de código real no iOS

**Fontes principais [CÓDIGO]:**
- [Modules/RSWeb/Sources/RSWeb/DownloadSession.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/Modules/RSWeb/Sources/RSWeb/DownloadSession.swift)
- [Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift)
- [Modules/Account/Sources/Account/AccountManager.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/Modules/Account/Sources/Account/AccountManager.swift)
- [Modules/Account/Sources/Account/CombinedRefreshProgress.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/Modules/Account/Sources/Account/CombinedRefreshProgress.swift)
- [iOS/AppDelegate.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/iOS/AppDelegate.swift)

## 3.1. Conexões e tarefas

`DownloadSession` possui sets de tarefas pendentes e em andamento, fila de URLs, mapa tarefa→informação, URLs de uma sessão, redirecionamentos e registros de respostas 429/4xx. Para a `URLSessionConfiguration.ephemeral`, o código estabelece `httpMaximumConnectionsPerHost = 1`, timeouts de requisição/recurso e política sem cache HTTP local da sessão. Faz sentido porque a aplicação mantém condicionalidade e histórico de fontes em outro lugar.

A classe impõe **um máximo operacional de 500 tarefas pendentes** antes de enfileirar outras URLs. Esse número não deve ser transplantado para o FeedMine: é uma escolha daquele downloader para conter materialização de tarefas, não a reserva da timeline. Testar impacto por domínio e concentração de requisições antes de escolher um limite adaptativo.

O retorno de HTTP 429 é tratado por host. O código guarda a indicação de aguardar e cancela tarefas da mesma origem; respostas 4xx não 429 recebem tratamento temporário distinto. Ele também redireciona permanentemente URLs quando apropriado e controla ciclos de redirecionamento.

**Lição:** rate limiting e backoff precisam ter alcance de **origem remota**, não disparar espera global. Um host lento ou temporariamente indisponível não deve parar outros conectores nem a publicação de candidatos saudáveis.

## 3.2. Condicionais e falhas sem confusão de estados

`LocalAccountRefresher` usa o estado por feed para fornecer `ETag`/`Last-Modified`; reconhece `304 Not Modified`, status HTTP inválidos, hashes de conteúdo repetidos e falhas reais de transporte. Há proteção para não atualizar a data de checagem em erros de conectividade, permitindo nova oportunidade legítima em vez de registrar sucesso falso.

Há inclusive uma correção histórica pragmática: os validadores condicionais muito antigos podem ser descartados porque alguns servidores mal configurados respondem 304 indevidamente. E os intervalos mínimos são sensíveis a `Cache-Control` e exceções de domínios. São políticas do produto, não uma lei geral sobre RSS.

**Lição:** elegibilidade de nova consulta deve derivar de observações reais: validade de cache, falha de transporte, rendimento, política do host e prioridade de demanda; nunca apenas do último disparo da fila.

## 3.3. Parsing e banco

Quando há dados novos, o código inicia parsing e atualiza artigos. Controla explicitamente `outstandingParseTasks` e só declara refresh completo quando download **e** parsing terminaram. Seu registro de atividade associa tentativas às fontes e mantém contagens de feeds ignorados/erro, artigos novos e artigos atualizados.

Uma fonte pode concluir sem ter dado material publicável, e o relatório global pode ainda estar aberto por outra fonte. Essa distinção é relevante para o FeedMine, cuja `AcquisitionBatch` passa por admissão e por seleção editorial antes de gerar um `PublishedCard`.

## 3.4. Concorrência entre contas e progresso consolidado

`AccountManager.refreshAll` usa `withTaskGroup` para atualizar contas ativas concorrentemente. `CombinedRefreshProgress` resume o estado das contas e evita retroceder contadores de tarefas concluídas durante um ciclo. Isso entrega feedback de operações, mas não deve ser confundido com progresso em direção ao infinito editorial.

**Proposta FeedMine:** métricas de aquisição podem ser agregadas para diagnóstico, mas o sinal dominante de produto deve ser `quantidade/distância de apresentação pronta à frente` junto da `taxa/latência de reposição`. Um indicador global “fontes consultadas 18/77.000” é pouco útil para o leitor.

## 3.5. Background real

O `AppDelegate` registra `BGAppRefreshTask`, submete uma nova oportunidade com `earliestBeginDate` e instala `expirationHandler` para cancelamento. O sistema decide quando executar. O app também reorganiza conexões ao retomar, explicitamente para evitar sessões cujos sockets ficaram inválidos durante suspensão.

**Lição:** o owner da aquisição deve suportar interrupção e reentrada. A notificação de retorno da rede não deve duplicar trabalho em andamento nem perder fatos já persistidos.

## 3.6. O que copiar e o que evitar

| Adotar como princípio | Não copiar sem teste |
|---|---|
| Estado HTTP por fonte/host e tratamento de 304/429 | `httpMaximumConnectionsPerHost = 1` para todos os conectores indiscriminadamente |
| Diferenciar download, parse e artigo válido | Limite global `500` como garantia de throughput ou runway |
| Evitar avançar freshness em erro de conexão | Exceções de host escritas para os servidores do NetNewsWire |
| Responder a suspensão/reentrada | Mesmo scheduler de refresh e mesma arquitetura de contas |
| Diagnóstico causal por tentativa e fonte | Expor número bruto de tarefas como prova de UX |

---

# 4. FeedFlow: banco, concorrência limitada e pipeline de sincronização

**Fontes [CÓDIGO]:**
- [FeedFetcherRepository.kt](https://github.com/prof18/feed-flow/blob/main/shared/src/commonMain/kotlin/com/prof18/feedflow/shared/domain/feed/FeedFetcherRepository.kt)
- [FeedSyncRepository.kt](https://github.com/prof18/feed-flow/blob/main/shared/src/commonMain/kotlin/com/prof18/feedflow/shared/domain/feedsync/FeedSyncRepository.kt)
- [FeedSyncIosWorker.kt](https://github.com/prof18/feed-flow/blob/main/shared/src/iosMain/kotlin/com/prof18/feedflow/shared/domain/feedsync/FeedSyncIosWorker.kt)
- [CLOUD_SYNC_ARCHITECTURE.md](https://github.com/prof18/feed-flow/blob/main/docs/CLOUD_SYNC_ARCHITECTURE.md)

## 4.1. Aquisição concorrente limitada

`FeedFetcherRepository.fetchFeedsWithRssParser` recupera as fontes locais, respeita filtro, publica o estado de leitura anterior quando cabível e processa as fontes via Kotlin Flow. O pipeline usa `flatMapMerge(concurrency = getNumberOfConcurrentParsingRequests())`, `withTimeout`, resultados tipados e metadados de cache HTTP. Fontes que falham podem ser marcadas individualmente, sem converter toda a rodada em um erro único.

Isso é diretamente comparável ao trabalho de `RunwayAcquisitionCycle`: existe oportunidade de aquisição paralela, mas cada resultado precisa preservar sua identidade e falha próprias.

## 4.2. Limitação de granularidade

Na rota estudada, resultados válidos são acumulados em `allFeedItems`; após o fluxo de fontes, são inseridos em banco. Essa estratégia pode ser eficiente para um refresh convencional, mas **[INFERÊNCIA]** aumenta a espera para exposição dos resultados *daquela rodada*, se a publicação depender do insert final. Não significa que a UI do FeedFlow fique bloqueada — ela já pode estar mostrando conteúdo local. Também não é prova de que cada implementação do FeedFlow usa esse mesmo caminho.

**Para o FeedMine:** preservar a admissão transacional incremental já modelada. Operações de lote podem reduzir custo de commit, mas não devem introduzir barreira artificial de conclusão de todas as fontes antes do primeiro `PublishedCard` legítimo. Medir custo de commit/contenda; não multiplicar commits sem observar benefício.

## 4.3. Sincronização de dados pessoais é outra dimensão

O FeedFlow oferece backend local e sincronização opcional por Dropbox, Google Drive ou iCloud. O documento de arquitetura declara dois conjuntos separados: o banco principal do app, com artigos e dados de leitura, e um snapshot menor transferível, com fontes, categorias e flags. O iOS usa um worker com `Mutex`, sessão, mudanças pendentes e revisão de upload. Existem verificações para impedir que um snapshot remoto substitua mudanças locais posteriores.

**Lição:** conteúdo recompilável a partir de origens não deve ter a mesma política de durabilidade de salvos, fontes escolhidas, coleções e posições pessoais. Essa separação é aplicável mesmo se o FeedMine continuar 100% local, sem implementar sync em nuvem.

## 4.4. Risco observado no paralelo com FeedMine

O uso de um `fetchMutex` e de estados globais como `isFeedSyncDone` funciona na lógica do FeedFlow, mas um FeedMine de múltiplos contextos não pode depender de uma variável genérica para decidir validade de recibo. Recibos devem ser confrontados com a identidade de edição/contexto relevante e preservados quando são legitimamente reutilizáveis; não introduzir fences indiscriminadas que causem starvation.

---

# 5. feeeed: referência local-first de produto, não código auditável

A App Store do feeeed declara funcionamento privado e no dispositivo, sem servidor próprio ou conta; suporta websites, Reddit, canais YouTube, Mastodon, Threads, conteúdo offline e descoberta de novas fontes. Isso é uma afirmação oficial do produto, **não** comprova que todo recurso opcional de IA ou integração jamais use serviços externos; a verificação técnica exige testes de rede por recurso.

A experiência é importante por tentar unir uma quantidade heterogênea de formatos numa timeline consumível. Mas não foram encontrados contratos públicos suficientes para conhecer suas tabelas, versionamento, concorrência por host, tamanho de buffer, uso de background ou número de fontes visitadas por minuto.

**Experimentos que valem fazer com feeeed no iPhone:** (i) instalar sem rede e depois conectar; (ii) adicionar dezenas/centenas de fontes de latências distintas; (iii) alternar listas e navegar de volta; (iv) observar perda/reconstrução de scroll quando notícias novas chegam; (v) avaliar consumo de dados, bateria e disco; (vi) distinguir modo de navegação online de conteúdo offline real. Os resultados seriam evidência empírica de produto, não prova do algoritmo interno.

**O que não concluir:** que feeeed descobre sozinho todo um catálogo com dezenas de milhares de fontes ou mantém milhares de downloads HTTP simultâneos. O marketing público não contém essa medição.

---

# 6. Reeder: aquisição direta e posição como unidade de continuidade

O Reeder contemporâneo (não confundir com Reeder Classic) publica que o conteúdo é obtido diretamente das fontes e o iCloud sincroniza principalmente inscrições, itens marcados e posição da timeline. Sua UX não obriga o usuário a concluir uma caixa de entrada de unread; ele pode retornar ao ponto guardado ou navegar para o presente.

Notas públicas detalham recursos de diagnóstico para tempos de atualização por feed e correções para ordenação de itens atrasados, datas iguais e posição salva. Esses problemas mostram que mesmo um leitor que segue fontes conhecidas enfrenta timestamps não confiáveis e mudanças remotas fora de ordem.

**Aplicações FeedMine:**

- Salvar posição com identidade do card + offset lógico/físico justificado, não “índice 143”.
- Diferenciar entrada de novos itens de rematerialização do histórico já visto.
- Distinguir posição da timeline, posição de artigo, bookmark e continuidade de playback — quatro tipos de estado diferentes.
- Tratar a data publicada como metadado de fonte, não verdade causal sobre a ordem de admissão.
- Incluir nas medições, por fonte, latência/erro/quantidade de conteúdo *aproveitado* e não só download.

**Desconhecido:** schema de armazenamento, scheduler de fetch, política de cache e política de consumo de energia. Não atribuir estrutura interna por analogia.

---

# 7. Tapestry: conectores e fronteira de normalização

O repositório do Tapestry declara expressamente que **não contém o código do aplicativo**. Contém documentação/API e exemplos de conectores em JavaScript, escritos pelos criadores para transformar RSS, APIs e outros sistemas em itens da timeline.

O tutorial exige identificador único URI e data para um item. Um conector possui configuração e `plugin.js`, cujo `load()` devolve fatos para que a aplicação decida a apresentação. Isso confirma a utilidade de **normalizar primeiro e renderizar depois**.

**Correspondência com FeedMine:** `Connector → AcquisitionBatch → transactional Admission → OriginRecord/OriginRevision + SourceMembership + MediaCandidate → Selection → MediaPreparation → Publication → FeedSession → Snapshot → SwiftUI`.

**Risco a evitar:** não transportar URLs brutas e heurísticas de uma API para `FeedItemView`. Nem tornar o JavaScript de plugins um pré-requisito para o FeedMine — tal decisão ampliaria sandboxing, governança, permissões e testes sem necessidade comprovada.

---

# 8. NewsBlur 15: estudo da apresentação independente da rede

A nota de lançamento de **03/10/2026** descreve como a versão 15 do NewsBlur iOS corrigiu reconstruções completas de listas ao acrescentar novas histórias, preparou thumbnails/textos antes do scroll e passou a apresentar conteúdo em cache enquanto a atualização remota ocorre. O desenvolvedor relatou diminuição do tempo de abrir uma lista grande e corrigiu defeitos de limpeza que mantinham cache indevidamente.

**Fonte [OFICIAL]:** https://blog.newsblur.com/2026/10/03/newsblur-15-for-ios/

Os números publicados são medições do próprio autor, não ensaio independente. A grande limitação para nossa comparação é o servidor NewsBlur, que já coleta feeds antes do aplicativo solicitar. Mesmo assim, os *sintomas de UI* são análogos: hitches ao estender listas, artigo piscando em branco, tarefas de mídia avançando tarde, cache indisponível quando deveria estar reutilizável e interrupções no retorno.

**Lição FeedMine:** a UI recebe uma janela local de valores estáveis; persistência, decodificação e replenishment não devem provocar rediferença editorial nem refazer em massa os bodies do SwiftUI. A solução não é “deixar o backend mais rápido” e sim não colocar custo do backend no caminho crítico do gesto.

---

# 9. lire, GoodLinks e Omnivore: comparadores complementares

**lire [OFICIAL]:** leitor RSS com extração de artigos completos, caching offline e suporte standalone. Sua especialidade é conseguir uma representação textual utilizável apesar de feeds incompletos. Bom benchmark para o custo/risco de extração secundária de HTML, não prova de aquisição exploratória massiva.

**GoodLinks [OFICIAL]:** transforma links salvos em leitura estruturada, preserva texto e opcionalmente imagens para uso offline, oferece limpeza e retém marcas pessoais. Bom para política de retensão e distinção entre recurso externo e materialização offline. Não tenta descobrir milhões de artigos continuamente.

**Omnivore [CÓDIGO/HISTÓRICO]:** é um exemplo aberto de app iOS com leitura offline, highlights e backend/servidor, mas a aplicação em nuvem foi descontinuada em novembro de 2024; hoje o projeto se descreve como self-hosted. Não tratá-lo como concorrente operacional atual nem como validação de ausência de servidor. O valor é estudar o modelo de biblioteca e sincronização offline, com cuidado quanto ao escopo temporal do código.

---

# 10. Apple iOS: o que background realmente significa

**Fontes oficiais:**
- https://developer.apple.com/documentation/backgroundtasks
- https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask
- https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app
- https://developer.apple.com/documentation/foundation/downloading-files-in-the-background
- https://developer.apple.com/videos/play/wwdc2025/306/

| Tecnologia | Pode ajudar com | Não garante |
|---|---|---|
| `BGAppRefreshTask` | Oportunidades curtas de buscar atualizações | Periodicidade exata, duração longa ou execução a cada X minutos |
| `BGProcessingTask` | Processamento/atualização mais longa quando sistema concede recurso | CPU e rede contínuas, não interrupção, execução enquanto usuário interage |
| `URLSession` em background | Download/upload de arquivos gerenciado pelo sistema; retorno por delegate | Rodar livremente parsing/seleção/publicação durante toda a transferência |
| `BGContinuedProcessingTask` | Continuar ação longa iniciada explicitamente em foreground, se elegível | Agente de crawling especulativo e eterno |
| Foreground `URLSession` | Requisições paralelas e responsivas sob controle do app | Sobreviver integralmente à suspensão sem reentrada |

A Apple alerta que tarefas de `URLSession` background têm overhead próprio e desencoraja programar **milhares** de transferências independentes como estratégia habitual; recomenda combinar transferências quando isso é possível. Num feed multiorigem sem servidor, combinar requisições HTTP em um download maior geralmente não é possível sem mudar o modelo de produto. Isso reforça o papel principal do **foreground produtivo + banco local durável**, com background oportunista.

`BGProcessingTask` pode ser terminado pelo sistema. Há também a nuance de que tarefas dessa categoria tipicamente rodam quando o dispositivo está ocioso; o sistema pode interrompê-las quando a pessoa volta a usá-lo. Qualquer trabalho de banco precisa ser reentrante e seguro diante dessa interrupção.

### 10.1. Procedimento correto de retorno

1. Antes de suspender: preservar o estado já confirmado e cancelar/pausar oportunidades indevidas sem inventar uma conclusão de conteúdo.
2. Durante a oportunidade de background: trabalhar sobre as autoridades existentes, apenas no intervalo permitido e sempre aceitar interrupção.
3. Na volta: mostrar a sessão local pronta primeiro; restabelecer conexões quando necessário; preservar histórico publicado, posição, dados pessoais e contexto anterior.
4. Só depois: reavaliar prioridade de abastecimento, cobertura de catálogo e custos de recursos.

### 10.2. Implicação de produto

**A promessa não pode ser “o FeedMine continuou minerando toda a internet enquanto o iPhone estava bloqueado”.** A promessa sustentável é “ao retornar, vejo imediatamente o que já estava preparado; quando posso continuar lendo, o app antecipa e amplia a oferta sem interromper o gesto”.

---
# 11. Confronto formal com o Blueprint v0.4 do FeedMine

**Fonte [FEEDMINE]:** `FeedMine Feed Runtime — Unified Architecture Blueprint v0.4`, 17/09/2026, anexo ao projeto; e `FeedMine Feed Runtime V2` (especificação técnica derivada). Complemento com PRDs e código do repositório público. O blueprint descreve autoridade arquitetural pretendida; não prova que todas as etapas estão corretas hoje.

## 11.1. Linha de produção e responsabilidade

```text
FONTES EXTERNAS / PROTOCOLOS HETEROGÊNEOS
             │
             ▼
         Connectors
             │  fatos versionados, não views
             ▼
      AcquisitionBatch
             │
             ▼
  Admission transacional + checkpoint
             │
             ▼
Canonical Supply: OriginRecord, OriginRevision,
SourceMembership, Provider, MediaCandidate, InteractionOffer
             │
             ▼
Selection por FeedPlan e contexto
             │
             ▼
MediaPreparation: decisão local de slot/assets
             │
             ▼
PublicationCoordinator: FeedEdition + FeedSegments
             │                  IMUTÁVEIS
             ▼
FeedSession: admissão, âncora, janela e runway
             │
             ▼
FeedPresentationSnapshot local, finito, estável
             │
             ▼
FeedScreenStore → SwiftUI
```

**O que não deve atravessar fronteiras:**

- `FeedScreen` não conhece URL de endpoint, cronograma de retry, `URLSession` ou `loadMore`.
- `Selection` não entende detalhes de Mastodon, YouTube, RSS ou autenticação de cada conector.
- `MediaPreparation` decide apresentação local; a view não resolve imagem remota.
- `PublicationCardID` identifica a ocorrência publicada; timestamps e URLs externos não substituem essa identidade.
- Refresh/edição upstream geram novas observações/revisões, mas não reescrevem o card publicado na posição atual.
- `FeedSession` é autoridade da admissão e da âncora. Renderização ou callbacks tardios não autorizam mudança editorial.

## 11.2. O que o código da V2 já apresenta

**[CÓDIGO/FEEDMINE — observação estrutural, não teste físico]:**

| Componente | Evidência lida | Papel preservado |
|---|---|---|
| `RunwayController.swift` | `RunwayScope`, `RunwayObservation`, atividades e medição, intents de aquisição/produção | Traduzir consumo em necessidade operacional |
| `FeedPresentationSnapshot.swift` | `FeedProjectionProvenance`, `FeedWindowSnapshot`, `PresentationAnchor`, IDs/contexto/edição | Contrato local da janela para UI |
| `FeedScreen.swift` | `LazyVStack`, IDs estáveis, medição de geometria e `submitViewport` | Interface informa observação; não executa aquisição |
| `FeedItemCardView.swift` | Slots dimensionados, imagem local e ações tipadas | Apresentação estável e interações |
| `ReaderShell.swift` | Cabeçalho como UI, store como origem de intenções | Separar chrome do runtime |
| `AppComposition.swift` | Owner de composição mencionado nas revisões e PRDs | Ligar pipeline a UI, sem virar segundo motor |

Links de referência:
- https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineRuntime/RunwayController.swift
- https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineRuntime/FeedPresentationSnapshot.swift
- https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedScreen.swift
- https://github.com/wsmontes/feedmine_v2/blob/main/FeedMineApp/FeedMineApp/AppComposition.swift

## 11.3. O que os próprios documentos dizem que **não está demonstrado**

O PRD **F05**, revisão de 10/10/2026, não é um PASS. Registra como problemas potenciais a composição com limites estáticos de janela/reserva (`8 atrás`, `16 à frente`, `reserveCards: 16`, `examinedCandidateCapacity: 32` na revisão observada), a necessidade de verificar elasticidade real, a extensão do catálogo efetivamente visitada e o tratamento de mídia pendente que pode virar texto puro antes de existir prova de impossibilidade.

Esses valores são **constatações da revisão histórica**, não afirmação de que o HEAD atual mantém exatamente os mesmos números. A verificação deve consultar o commit candidato que será medido no Mac.

O F06 registra explicitamente que `MediaReadiness.presentation(for:)` pode escolher `.textOnly` para uma imagem ainda não pronta; isso conflita potencialmente com a regra de suspender candidatos recuperáveis sem transformar falha temporária em decisão editorial definitiva. O teste integral B04 em iPhone físico não estava demonstrado naquele registro.

O diagnóstico F05 aponta ainda que o trabalho de cobertura `selectedSourceCoverage` se concentra em fontes selecionadas pela sessão. Isso **não equivale** a provar exploração progressiva do catálogo global. O catálogo pode ser vasto, mas um cursor de seleção estreito ainda pode revisitar os mesmos alvos indefinidamente.

**Regra de análise:** repetir essas verificações no estado presente do código antes de criar bugs novos; usar os PRDs como hipóteses/sinais, não como substitutos da leitura do HEAD.

---

# 12. Invariantes de produto que dominam otimizações locais

| Invariante | Como falha no mundo real | Evidência necessária |
|---|---|---|
| Feed não termina artificialmente | Reserva se esgota embora haja milhares de fontes elegíveis | Percurso longo com rastreamento de identidade e conteúdo elegível |
| Scroll não espera HTTP | Célula/anchor depende de nova URL ou parse | Instrumentos correlacionados entre swipe, body e rede |
| Histórico publicado não muda | Arribo tardio substitui imagem, texto, ordem ou geometria | IDs, hashes, bounds e anchor antes/depois |
| Contexto A retorna intacto | A→B descarta trabalho ou reabre no topo | Revisitar A com BD, editionID, anchor, pixels e ações |
| Falha é local, não global | 429 de um host causa “sem conteúdo” no feed inteiro | Ledger de tentativas por host e razão de escassez |
| Apresentação local sobreviverá offline | Reabertura mostra spinner apesar de cards locais | Kill/reopen offline com primeiro paint gravado |
| Decisão do usuário é durável | Salvos/fontes/posições somem após migração | Snapshot e round-trip de estado pessoal |
| Mídia não invade o renderer | `AsyncImage`/player chama rede na célula | Trace de rede ligado a lifecycle e card |
| Exploração continua com runway saudável | Aplicativo repete poucas fontes e jamais visita outras | Cobertura cumulativa de alvos elegíveis |
| Pressão reduz trabalho especulativo | Decoding/SQLite em paralelo rouba frames do scroll | Instruments + métricas memória/thermal/disk |

**A hierarquia de correção** começa por starvation, falso fim, perda de dados, saltos no feed e bloqueio da UI. Reduzir uma consulta de 5s para 4s é secundário se o usuário continua vendo fim de conteúdo ou perdendo posição.

---

# 13. Onde os produtos externos oferecem uma técnica transferível

## 13.1. Fila de HTTP vs. runway editorial

**NetNewsWire:** fila finita de tarefas protege o downloader. **FeedMine:** runway é demanda editorial antecipada e deve incorporar velocidade de consumo, altura dos cards, latência de reposição e contingência. Uma fila de rede pode ter limite operacional independente, mas não pode representar o “fim do feed”.

## 13.2. Data freshness vs. content readiness

**FeedFlow/NetNewsWire:** validade de cache HTTP, 304 e sucesso de parsing. **FeedMine:** ainda exige seleção de história, decisão de mídia, validade do destino, publicação e admissão. Métrica de `feeds fetched` não é métrica de `cards ready`.

## 13.3. Banco transacional vs. apresentação estável

**FeedFlow:** transações e merge de fontes/flags. **FeedMine:** há ainda `FeedEdition`, segmentos imutáveis, histórico publicado e janela admitida. Otimizar `INSERT` não pode descartar esse compromisso de estabilidade.

## 13.4. Scroll progressivo vs. mutation do conjunto visible

**NewsBlur 15:** inserção incremental e preparação antecipada. **FeedMine:** o conjunto visível tem uma barreira adicional: a publicação é imutável e o prefixo admitido conserva âncora/geometria. O resultado de trabalho de fundo não tem permissão para aparecer arbitrariamente no meio da janela.

## 13.5. Conector vs. forma de leitura

**Tapestry:** conector fornece o item normalizado, a timeline o mostra. **FeedMine:** a admissão normaliza antes de Selection e a mídia é preparada antes da publicação. Se o renderer sabe que uma notícia veio de RSS ou Mastodon para decidir como buscar metadados, a fronteira já foi violada.

---

# 14. A questão central da escala: qual é o recurso realmente escasso?

A discussão deve distinguir pelo menos sete capacidades: (a) sockets/HTTP por host, (b) slots de parsing, (c) escritor SQLite, (d) CPU de seleção, (e) decodificação de imagem, (f) bytes de armazenamento, (g) tempo MainActor para renderizar views. Elas têm custos diferentes e não devem ser representadas por um único “máximo de 20 tarefas”.

**Modelo conceitual [PROPOSTA, para medição e não como novo scheduler]:**

```text
runway_time_coverage = ready_visual_distance_ahead / observed_visual_scroll_speed

replenishment_risk = replenishment_latency_p95 / max(runway_time_coverage, epsilon)

editorial_yield = new_presentation_ready_cards / eligible_acquisition_attempts
```

A primeira é uma aproximação; deve tratar viewport parado separadamente e não dividir ingenuamente por zero. A segunda não fornece SLA, apenas sinal relativo para priorizar trabalho. A terceira ajuda a distinguir uma rodada rica de uma rodada que consulta milhares de fontes vazias.

**Não impor fórmula acima diretamente ao código.** O F05 já pede avaliação de demanda com fatos; o próximo passo é medir se a política existente faz essa separação adequadamente. Reaproveitar o `RunwayController` e o `RunwayPolicy` atuais.

## 14.1. Efeito de cauda longa

Considere fontes com latências de 100 ms, 1 s, 10 s e 60 s, além de hosts que devolvem 429 e conteúdo repetido. Esperar o grupo inteiro faz a latência da rodada se aproximar da fonte mais lenta. Admitir fatos por fonte permite publicar candidatos saudáveis assim que o pipeline completo deles estiver pronto.

**Ainda assim, incrementalidade irrestrita pode ser cara:** commits minúsculos constantes podem provocar contenda no WAL e muitas projeções UI. O objetivo é **não depender do fim do lote**, sem obrigar uma transação por linha nem uma notificação SwiftUI por item.

## 14.2. Custo de catálogo

Um catálogo grande não implica que cada visita a cada fonte deva ocorrer imediatamente. O problema exige explorar progressivamente o conjunto elegível ao longo do uso, respeitando relevância, idioma, qualidade, atividade, custo e oportunidade; proteger continuidade da sessão atual sem esquecer a cobertura global. O F05 proíbe uma shortlist fechada que deixa fontes elegíveis nunca consultadas.

A política ideal de exploração depende de fatos ainda não medidos: atividade da fonte, densidade de candidatos novos, distribuição de hosts, sucesso de mídia e tempo total até publicação. Não há como declarar um `fan-out` ótimo de forma responsável apenas com documentação ou analogia.

---

# 15. Banco de dados: integridade, concorrência e custo de publicação

O Blueprint v0.4 distingue **catálogo** de **runtime** e indica SQLite como autoridade local. A organização física pode evoluir, mas o princípio não muda: dados pessoais/duráveis não podem depender de caches reconstruíveis e publicação não pode virar mutação retroativa.

## 15.1. Perguntas fundamentais sobre SQLite na V2

- O leitor consulta o banco ao longo do gesto ou somente recebe `FeedPresentationSnapshot` já materializado?
- Existem transações de escrita que seguram locks ou atrasam leituras de apresentação?
- O escritor utiliza WAL, tamanho de batches e checkpoints compatíveis com os períodos de scroll ativo?
- Quais índices servem `next eligible candidate`, `edition segments`, `source identity`, `anchor restore` e `media status`?
- O banco cresce com retenção antiga; quanto custa reabrir A→B→A quando há milhares de segmentos e revisões?
- Dados pessoais são duráveis por sua própria raiz de retenção (saved, collections, follows, positions, presets)?
- A migração V1→V2 preserva conteúdos insubstituíveis ou apenas os arquivos antigos no disco?

**Sem evidência:** não atribuir gargalos ao SQLite. Primeiro correlacionar o bloqueio físico com transação/statement, percentil e lock. Uma operação demorada pode estar fora do banco: parsing, layout, imagem, instrumentação DEBUG ou reconciliação de viewport.

## 15.2. Hipóteses arquiteturais a testar

| Hipótese | Sinal de confirmação | Ação mínima preferível |
|---|---|---|
| Escritas longas durante scroll causam hitch | Time Profiler + SQLite busy/duração alinhados aos frames perdidos | Ajustar granularidade/limite do owner de escrita existente |
| Leitura do feed dispara query repetida | SQL trace com mesmo viewport e mesmas linhas | Materializar uma vez no snapshot; não criar cache paralelo |
| Reabertura offline consulta fonte remota antes de restaurar | Primeiro paint depois de HTTP | Corrigir ordem de restauração local no owner atual |
| Revisão de item atualiza card publicado | IDs iguais mas payload/hash/bounds mudam | Preservar imutabilidade e republicar só nova ocorrência válida |
| Reconciliação de contextos destrói supply reutilizável | Regressão A→B→A com mesma fonte reacquirida | Consertar ownership/retention em vez de novo cache |

---

# 16. UI/SwiftUI: medir a experiência, não apenas cronômetros do backend

A Apple publicou orientações específicas em *Optimize SwiftUI performance with Instruments* (WWDC25) e *Understanding and improving SwiftUI performance*. Recomenda usar SwiftUI instrument com Time Profiler e Hitches para identificar bodies demorados, atualizações excessivas, operações de layout e custo fora da UI.

No FeedMine, as provas devem unir:

1. **Gesto físico:** swipe nativo e posição real, não apenas driver lógico.
2. **Rendering:** quantidade/duração de recomputações do `FeedScreen`/`FeedItemView`, item identity e tempo de frame.
3. **Origem do evento:** `refresh`, `admission`, `publication`, `decode`, `filter`, `background` ou `playback`.
4. **Efeito visual:** IDs, ordem, retângulos, anchor com offset, blank frame, clipping, salto.
5. **Uso de recurso:** memória, disco, CPU, rede, thermal state, Low Data Mode.

A recomendação não é observar o viewport via polling fixo. O `FeedScreen` já possui captura geométrica e submissão de observações; instrumentar pontos causais existentes evitando o custo de log em cada pixel do scroll. A telemetria não pode criar o hitch que pretende medir.

### 16.1. Medidas de UX que interessam mais que tempo médio de refresh

- Tempo até **primeira história real publicável** em instalação limpa.
- Tempo até **primeira apresentação local** em relançamento offline.
- Distância de runway pronta à frente no momento em que o usuário acelera.
- Número de casos em que há oferta elegível no banco/catálogo mas o feed expõe estado terminal.
- Falhas de preservação física de âncora por ação (imagem chega, background, edição, filtro, rotação, mídia).
- Número/razão de stories recuperáveis descartadas ou repetidamente suspensas.
- Quantas fontes distintas receberam oportunidade no percurso prolongado, não só as fontes rápidas.
- Frames perdidos/hitches e correlação com trabalho do runtime.

---

# 17. Mapeamento dos riscos reais — sem diagnóstico precipitado

| Risco | Severidade | Evidência disponível | Verificação que falta |
|---|---|---|---|
| Starvation ou fim artificial | P0 | F05 exige B03 real; aponta limitação potencial de reserva/cobertura | Journey real no commit alvo com corpus amplo |
| Falso “sem conteúdo” após falha local | P0 | Separação semântica exigida em F05/F06 | Trace erro→oferta→estado UI |
| Cards publicados mudam após decode/update | P0 | Blueprint proíbe; F06 aponta transição prematura para text-only | Hash/bounds/anchor no dispositivo |
| Presets/filtros destroem trabalho reutilizável | P0/P1 | Contrato F05-R8 | A→B→A com métricas de reuse e restore |
| Desempenho de UI perturbado por trabalho de fundo | P0/P1 | Perfis de app e investigação da Apple | Instruments (SwiftUI, Hitches, CPU, SQLite, memória) |
| Cobertura da internet fica confinada à shortlist | P0/P1 | F05 sinaliza `selectedSourceCoverage` vs catálogo global | Contagem de alvos elegíveis/contactados ao longo da sessão |
| Banco cresce/retém inadequadamente | P1 | Arquitetura prevê raízes de retenção | Estatísticas de tamanho, WAL, tempo de reabertura |
| Background tratado como servidor persistente | P1 | Apple documenta limites | Simulador+dispositivo: expiração, cold reopen, offline |
| Estado pessoal V1→V2 não migrado | P0 de dados | Decisão/PRD de portabilidade exige preservação | Inventário completo e teste de migração em instalação real |
| Diagnóstico confunde benchmark com aceitação | P1 | PRDs distinguem NOT_RUN de PASS | Livro de provas com resultado e aparelho identificado |

---
# 18. O que ainda precisamos saber — inventário de incertezas e provas necessárias

Esta seção é parte essencial do relatório. A pesquisa de concorrentes não substitui a evidência do FeedMine rodando no Mac e no iPhone. A informação que falta foi agrupada por **decisão que ela desbloqueia**, **fonte da prova** e **interpretação alternativa**. Nenhuma pergunta abaixo implica que exista um defeito sem medição.

## 18.1. P0 — O feed acaba por escassez verdadeira ou por limite do nosso pipeline?

**Pergunta:** quando a interface chega ao final aparente da lista, existem histórias elegíveis ainda não examinadas, já adquiridas, já selecionadas, preparáveis ou publicáveis?

**Precisamos observar na mesma linha do tempo:**

1. `ContextKey`, `FeedEditionID`, `PublicationCardID` âncora, último card admitido e último publicado.
2. Quantidade e distância visual de cards **prontos adiante**; não apenas contagem total da edição.
3. Cursor de supply efetivamente examinado; itens elegíveis além dele; categorias de exclusão.
4. Candidatos suspensos por mídia, link, texto, conteúdo repetido ou regra editorial — com razão recuperável/irrecuperável.
5. Aquisição ativa, capacidade disponível, origens aguardando rede/backoff e última publicação efetiva.
6. O motivo exato pelo qual a apresentação oferece um footer de exaustão ou um aviso de indisponibilidade.

**Prova necessária:** jornada B03/F05-01 com corpus elegível rotulado, velocidade variável e inspeção causal no instante de cada ruptura. Se a origem ainda tem histórias válidas e o frontend mostra fim, classificar **falso fim**. Se supply está presente mas não se transforma em edição, investigar Selection/MediaPreparation/Publication; se o material está publicado mas não admitido, investigar FeedSession e observações de avanço. Não reduzir tudo a “fetch lento”.

**Decisão dependente:** corrigir o owner que perdeu a continuidade, sem criar outro `loadMore`, feed paralelo ou contador de tentativas.

## 18.2. P0 — Qual parte do refresh gera um bloqueio perceptível?

**Pergunta:** hitches coincidem com HTTP, parsing, transformação de modelo, transação SQLite, decode, publicação, projeção ou layout SwiftUI?

**Precisamos de:** trace unificado de CPU/main thread e SwiftUI Hitches/Updates, instrumento de gravação SQLite e eventos causais do runtime. Marcar início/fim de eventos existentes com correlação `operationID`, **sem instrumentar cada frame** e sem mover execução de UI para outro thread sem diagnosticar o custo real.

**Interpretações possíveis:**

- CPU de parsing em executor compartilhado consome largura de banda de CPU e afeta frame, mesmo sem executar no `MainActor`.
- Uso de `MainActor` em callback rápido é barato isoladamente, mas a frequência e volume de payloads podem causar bloqueio agregado.
- Transação curta pode ser saudável; notificação repetida de muitos diffs pode ser o custo real.
- Atraso de imagens pode coincidir com hitch sem causá-lo: é necessário correlacionar stacks e intervalos.

**Decisão dependente:** simplificar o caminho causador ou introduzir batching de notificações com base em fatos de publicação, nunca suppressão arbitrária por timer.

## 18.3. P0 — Filtros e contextos preservam a produção reaproveitável?

**Pergunta:** no percurso A→B→A, o retorno reconstrói tudo ou reaproveita a edição publicada, supply canônico, recursos visuais, resultados de seleção e âncora conforme validade?

**Precisamos de:** identidade de A/B/A, IDs de edições, hashes de recursos, contagens de rede, candidatos reciclados e tempo de primeira apresentação local após retorno. Incluir callback tardio legítimo de A enquanto B está ativo e callback obsoleto que não poderia alterar B.

**Cuidado:** bloquear um recibo só porque seu `editionID` não é o atualmente visível pode ser correto para a UI de B e **incorreto** se também impede persistência de conteúdo canônico reutilizável em A. Medir o local da recusa e a autoridade de cada recibo.

**Decisão dependente:** reduzir invalidação excessiva, confirmar fences no nível semântico certo e preservar trabalho útil sem segundo cache.

## 18.4. P0 — Cards e posição permanecem fisicamente estáveis?

**Pergunta:** chegada de imagem, refresh, publicação na cauda, playback, mudança de aparência, retorno do browser e background mudam pixels/ordem/bounds de cards admitidos sem decisão do leitor?

**Precisamos de:** ID e bounds físicos do card âncora e de vizinhos, offset em relação ao viewport, identidade do contrato visual e imagem usada, antes/depois do evento; vídeo da tela em iPhone real. Uma igualdade de IDs, sozinha, não demonstra ausência de salto.

**Decisão dependente:** corrigir a origem de mutação ou layout. Não fazer `scrollTo` compensatório como resposta padrão a uma arquitetura que não preservou geometria.

## 18.5. P0 — Retorno offline ocorre antes de qualquer rede?

**Pergunta:** após fechar a aplicação durante uma sessão válida, o app relançado offline reapresenta a edição local, card e âncora corretos, sem spinner que dependa de HTTP?

**Precisamos de:** instalação identificada, edição e assets no disco, momento da primeira janela útil, motivo de eventual tela de preparação e chamadas de rede até o primeiro paint. Distinguir relançamento genuíno de mera volta do background.

**Decisão dependente:** corrigir ordem de inicialização/restauração, não criar captura redundante de snapshots.

## 18.6. P0 — Dados pessoais sobrevivem à V1→V2?

**Pergunta:** quais tabelas, diretórios, chaves e identificadores de V1 guardam salvos, boxes, coleções, subscriptions, posições, presets e preferências; quais são importados e quais permanecem apenas fisicamente no dispositivo?

**Precisamos de:** inventário de fontes de dados V1, transformação para o esquema V2 e teste de upgrade com backup de uma instalação povoada, incluindo rollback seguro quando importação parcial falha. Dados pessoais não são “recriáveis” pelo crawler.

**Decisão dependente:** aprovação explícita da estratégia de migração ou comunicação de início limpo; o relatório não assume que uma delas já foi aprovada.

## 18.7. P1 — O catálogo amplo recebe oportunidades reais?

**Pergunta:** o runtime está consultando fontes novas progressivamente além do conjunto já selecionado/habilitado, ou a cobertura converge para uma shortlist perpetuamente repetida?

**Precisamos de:** população total elegível por idioma/lugar, fontes nunca tentadas, tentadas com sucesso, em backoff e produtivas; curva de cobertura por sessão, separada de refresh de favoritas; distribuição por host. Diferenciar catálogo de ~77 mil entradas do conjunto elegível para o contexto atual.

**Decisão dependente:** ajustar prioridades existentes de descoberta quando runway está saudável, não criar pipeline exploratório paralelo.

## 18.8. P1 — Quanto trabalho é útil e quanto é desperdiçado?

**Perguntas:** qual a taxa `respostas→novos itens→candidatos elegíveis→cards preparados→cards publicados`; que porcentagem de mídia baixada nunca chega a uma apresentação; quais contextos retidos são revisitados; o que é refeito sem necessidade?

**Precisamos de:** contagens por estágio com mesma operação/candidatos, bytes por classe, CPU de decode e padrões de reentrada. Bytes de mídia não devem ser somados a um indicador enganoso de progresso de artigos.

**Decisão dependente:** deslocar orçamento para trabalho de maior retorno observável. Não inventar cache de mídia adicional se a residência/identidade já é resolvida pelo owner atual.

## 18.9. P1 — Em que situações o banco é gargalo?

**Perguntas:** há escritas longas, varreduras grandes, índices ausentes, WAL que cresce, checkpoints durante interação, leitura repetida por layout, transações de pequena granularidade em excesso?

**Precisamos de:** explain plan de consultas críticas, durações e contagem de transações, tamanho do banco/WAL, filas de escrita, tempos de reopen em datasets pequenos e grandes, stacks em Instruments. Sem essas medições, “otimizar SQLite” é apenas uma hipótese.

## 18.10. P1 — Como recursos físicos alteram o comportamento?

**Perguntas:** sob Low Power Mode, Low Data Mode, pressão de memória, disco cheio e thermal throttling, o FeedMine reduz trabalho especulativo antes de prejudicar o leitor? O que faz com imagens decodificadas afastadas da janela sem perder referências? Quais ações persistem quando o iOS suspende a aplicação?

**Precisamos de:** série de testes em dispositivo, memgraph/heap, taxas de rede, transições de foreground/background, resposta a cancelamento e reabertura. O simulador não substitui comportamento de RAM, energia e iOS scheduler em hardware real.

---

# 19. Protocolo de evidências: como coletar informação suficiente para decidir

## 19.1. Um registro causal por operação, não uma chuva de logs

Uma linha de evento de produção deveria associar os fatos mínimos:

```text
timestamp_monotonic
operation_id
context_key / edition_id (se aplicável)
source_id / acquisition_target_id (se aplicável)
candidate_id / origin_revision_id (se aplicável)
stage
start_or_end
result_kind (304, 200, timeout, bad_feed, suspended_media, published...)
item_count / useful_card_count / bytes (quando relevante)
```

Esse é um **modelo de observação**, não uma tabela nova nem prescrição de substituir os tipos do repositório. Emitir apenas em fronteiras causais existentes, via logging/instrumentação local, quando necessário e sem dados sensíveis de URLs do usuário em exportações públicas. Comparar intervalos por `operation_id` de ponta a ponta.

Eventos recomendados: `acquisition_started/completed`, `parse_completed`, `admission_committed`, `selection_completed`, `media_ready/deferred`, `publication_committed`, `session_admitted`, `snapshot_installed`, `viewport_advanced`, `scope_changed`, `background_entered`, `local_restored`.

**NÃO** criar temporizadores para coletar amostras se a mesma informação já é observável nos eventos do produto.

## 19.2. Caderno de ensaio reproduzível

Em cada execução, registrar:

| Campo | Conteúdo necessário |
|---|---|
| Build | SHA Git completo + árvore + branch; dirty/clean; scheme e flags DEBUG |
| Dispositivo | Modelo, versão de iOS, simulador ou aparelho real |
| Dados | Corpus / fixture versionado, hashes, contagem de itens válidos e fontes elegíveis |
| Estado inicial | Cold/warm/offline, edição existente, posição e bytes locais |
| Rede | Wi-Fi/celular, condição de latência/perda, hosts simulados e reais |
| Jornada | Ações reproduzíveis, duração, ritmo de scroll, filtros e background |
| Observação | Trace de pipeline, Instruments, IDs, posição física, telas gravadas |
| Resultado | PASS / FAIL / NOT_RUN / BLOCKED, asserção e causa confirmada ou desconhecida |

Guardar um **exemplo mínimo de falha** com artefatos que permitam repetição. Os dados de teste não devem depender da disponibilidade de um website real para provar a lógica determinística; usar rede real como ensaio complementar da variabilidade externa.

## 19.3. Comandos de coleta no Mac — exemplos a validar, não execuções deste relatório

As instruções abaixo são um roteiro, não uma afirmação de que rodei o repositório. Usar o Xcode e simulador realmente instalados e conferir os nomes de targets. Reproduzir primeiro a régua de aceitação que já está congelada.

```bash
# Identificar o código efetivamente testado
 git status --short
 git rev-parse HEAD
 git rev-parse HEAD^{tree}

# Descobrir schemes e simuladores disponíveis
 xcodebuild -list -project FeedMineApp/FeedMineApp.xcodeproj
 xcrun simctl list devices available

# Executar a suíte package, quando compatível com o ambiente
 swift test

# Execução dirigida de um teste existente: confirmar nome real antes
 xcodebuild test \
   -project FeedMineApp/FeedMineApp.xcodeproj \
   -scheme FeedMine \
   -destination 'platform=iOS Simulator,name=iPhone 16' \
   -only-testing:FeedMineAppTests/CompositionTests
```

A identificação `iPhone 16` é **exemplo** e deve ser substituída pelo dispositivo/simulador disponível. Alguns testes exigem uma configuração específica e execução no Mac; não declarar sucesso se apenas compilou. A régua `bench/` permanece congelada.

Para análise de frames, utilizar Instruments/Xcode — SwiftUI, Time Profiler, Hitches e métricas de memória. Instrumentação de SQLite precisa respeitar a API e o banco que o runtime efetivamente usa, sem logging agressivo de cada statement durante os testes visuais.

---

# 20. Experimentos prioritários: matriz de perguntas → prova → interpretação

| ID | Prioridade | Experimento | Resultado inequívoco esperado | Se falhar, onde investigar primeiro |
|---|---|---|---|---|
| E01 | P0 | Consumir 30 min com corpus ≥5.000 elegíveis, ritmos e rajadas de F05 | Sem fim artificial; IDs distintos; UI fluida | RunwayController, candidate cursor, publication, session admission |
| E02 | P0 | Primeira fonte retida por mídia lenta; outras fontes respondem | Cards válidos seguem publicando; pendente recuperável permanece no supply | MediaReadiness, preparation, admission queue |
| E03 | P0 | Rede falha num host, outro responde | Sem erro global de escassez; segundo host continua | Acquisition result taxonomy / UI work state |
| E04 | P0 | Edição de artigo já admitido | Card lido e geometria não mudam; nova ocorrência conforme contrato | PublicationStore, projection, visual cache |
| E05 | P0 | Navegação A→B→A com callback tardio | Contexto B não contaminado; A reaproveitado e restaurado | Session scope / publication receipt / retention |
| E06 | P0 | App em background durante reposição + reentrada offline | Primeiro paint local sem depender de rede; progresso preservado | lifecycle composition / restore path |
| E07 | P0 | Trocar filtro com áudio ativo + retornar | Player continua, âncora preservada | ReaderMediaCoordinator / shell / session |
| E08 | P0 | Abrir artigo real e voltar após nova publicação | Mesmo card, offset e ordem; artigo correto | F14 reader routing / scroll geometry |
| E09 | P0 | Aumentar Dynamic Type, girar, reabrir | Layout acessível sem invalidar edição | ReaderAppearance / card geometry |
| E10 | P0 | Atualização V1 com biblioteca povoada | Salvos/coleções/fontes/posições preservados segundo decisão | Migration/ReaderLibraryStore |
| E11 | P1 | Alternar consumo lento e rajadas | Demanda alterada conforme medições; sem páginas mágicas | RunwayPolicy inputs / controller |
| E12 | P1 | Runway saudável por longo período | Novas fontes elegíveis continuam recebendo oportunidade | Discovery/catalog → targets → acquisition |
| E13 | P1 | Mix de HTTP 304/429/5xx/timeout | Classificação individual e backoff por origem | Connectors / HTTP state |
| E14 | P1 | SQLite pequeno versus grande sob scroll | Correlacionar I/O, locks e hitches sem suposições | DB query plans / write granularity |
| E15 | P1 | Pressão de RAM/CPU/Low Data | Trabalho especulativo cede à apresentação; sem mídia visual renegociada | Governor/broker/preparation |
| E16 | P1 | Mesmo card aparece em contextos diferentes | Identidade canônica preservada; ocorrências publicadas independentes | Domain identity / PublicationCardID |
| E17 | P1 | Reabrir A após B com assets úteis em disco | Não refaz download/decode sem motivo verificável | media residency and retention |
| E18 | P1 | Múltiplas fontes do mesmo host com 429 | Respeita host e não bloqueia domínios distintos | origin policy and connector contracts |
| E19 | P2 | Rendimento de artigos sem imagem versus imagem lenta | Texto puro legítimo; mídia recuperável não vira ausência definitiva | media readiness semantics |
| E20 | P2 | Falhas depois de commit parcial / crash | Dados duráveis continuam íntegros; sem ocorrências duplicadas | transactional admission / persistence |

**Regra do ensaio:** um PASS exige comportamento observável e identificação do código testado. Testes unitários e mocks podem provar invariantes locais, mas não são prova de fluidez física ou continuidade com latências reais. Não redefinir os critérios congelados para facilitar a aprovação.

---

# 21. Diagnóstico por sintomas: árvore de decisão

## 21.1. “O feed terminou”

```text
Há cards publicados à frente da âncora?
  SIM → admissão / observação de viewport / snapshot / scroll
  NÃO → existem candidatos elegíveis e prontos?
    SIM → seleção / publication coordinator / limites de janela
    NÃO → há supply canônico ainda examinável?
      SIM → readiness, filtros, cursor, política editorial
      NÃO → fontes elegíveis ainda não exploradas?
        SIM → acquisition coverage / prioridade / backoff
        NÃO → considerar escassez realmente demonstrada
```

**O que não fazer:** transformar um limite de consulta em “fim da internet” ou instalar um botão manual `loadMore` para esconder a causa de starvation.

## 21.2. “Apareceu alerta de falta de conteúdo e depois voltou conteúdo”

Verificar se o alerta foi emitido após timeout de uma operação, depois de uma janela local vazia, ou após prova de exaustão de todo o universo elegível. O primeiro e o segundo não sustentam o terceiro. Se ainda havia aquisições em andamento, pendentes recuperáveis ou cursor adiante, o estado terminal foi emitido cedo demais.

**O que não fazer:** introduzir um timer de “esperar mais 2 segundos” na UI. Corrigir a semântica do estado no owner que conhece a prova de escassez.

## 21.3. “Pequenos saltos durante scroll”

Separar: (a) mudança de IDs/ordem; (b) mudança de bounds ou reserva de mídia; (c) scroll offset compensatório; (d) trabalho pesado na main; (e) conteúdo overlay entrando/saindo e alterando geometria; (f) expansão/admissão da janela que perturba a âncora. Executar vídeo e snapshots físicos antes de alterar a máquina de estados.

**O que não fazer:** adicionar `.id(UUID())`, múltiplos `scrollTo`, timers de debounce ou aumentar indiscriminadamente o número de cards retidos.

## 21.4. “Filtro parece recarregar tudo”

Verificar quais trabalhos são **necessariamente específicos do contexto** (seleção e nova edição) e quais são reutilizáveis (fonte já adquirida, origem canônica, mídia preparada, contexto recente válido). Observar revalidação de scope e callbacks tardios. A fronteira correta precisa impedir mutação do contexto atual sem descartar trabalho aproveitável em armazenamento global.

## 21.5. “Backend atrapalha UI mesmo quando não publica”

Investigar saturação de CPU, pressão de memória, decode fora da prioridade visual, checkpoints de banco, notificações de progresso e recomposição de layout. O fato de uma tarefa estar em `Task.detached` ou executor de background não impede que ela concorra por recursos físicos com a UI.

---

# 22. Plano de investigação e intervenção, em ordem de retorno de produto

## Fase A — Reproduzir e classificar, sem modificar comportamento

**Objetivo:** confirmar ou refutar quatro problemas P0: fim artificial, falso alerta, salto físico e destruição de contexto reutilizável.

**Trabalho:** capturar baseline no commit fixo, selecionar corpus amplo, executar E01–E06 e ligar eventos de runtime às medições físicas. Instalar somente observabilidade mínima nos owners existentes quando faltar prova. Se a instrumentação alterar significativamente o comportamento, reduzir o seu custo antes da análise.

**Entrega:** matriz de cenários com PASS/FAIL/NOT_RUN/BLOCKED, timeline causal e ponto de decisão observado. Não abrir simultaneamente múltiplas frentes de arquitetura com causas ainda incertas.

## Fase B — Correções P0 localizadas nos owners

**Objetivo:** eliminar bloqueios e estados incorretos comprovados.

**Ordem sugerida:** (1) semântica de oferta/fim; (2) admissão e progressão; (3) recepção de recibos sem starvation; (4) geometria/âncora; (5) reutilização de contextos. Cada correção deve trazer uma prova de regressão que falhava antes e passar depois, junto com repetição da jornada física relevante.

**Preferência arquitetural:** remover caminhos concorrentes ou donos duplicados; evitar compensações na UI para deficiências de seleção/publicação.

## Fase C — Eficiência e escala, depois da continuidade

**Objetivo:** tornar o sistema mais econômico sem recriar a falha.

Medir custo por card publicável, taxa de produção sob latência variável, reutilização A→B→A, cobertura exploratória, custo de transação e energia. Ajustar políticas existentes, priorizando os sinais que realmente afetam runway visual e diversidade. Só considerar novas camadas quando houver uma impossibilidade demonstrada com ownership atual.

## Fase D — Verificação de background e portabilidade

**Objetivo:** comprovar retomada sem depender do scheduler do iOS e garantir dados pessoais. Exercitar expiração de BGTask, cold launch offline, upgrade V1→V2, arquivo de origem removido, storage pressure e restauração após cancelamento.

**Condição de fechamento:** comportamento de produto demonstrado no dispositivo e consistência de dados comprovada, não apenas bateria de testes unitários verde.

---

# 23. O que não vamos importar dos concorrentes

1. **Backend agregador próprio.** NewsBlur resolve muitos problemas deslocando trabalho ao servidor. FeedMine assume outro custo operacional, deliberadamente. Não introduzir serviço de conteúdo por comparação ingênua de performance.
2. **Refresh completo como unidade de disponibilidade.** FeedFlow e leitores convencionais podem apresentar resultados de rodadas mais agregadas. FeedMine precisa trabalhar progressivamente sempre que há fatos publicáveis, não esperar a fonte mais lenta.
3. **Counters como qualidade de experiência.** `100 feeds checked` é telemetria, não compromisso de runway. A UI depende de histórias já apresentáveis e geometria estável.
4. **Um cache para cada nova feature.** Preservar uma fonte única de identidade, versões de mídia e durabilidade; duplicação de cache encarece invalidação e provoca regressões A→B→A.
5. **Background persistente fictício.** Não disfarçar limitações de iOS com timers, notificações silenciosas como garantia ou milhares de transferências agendadas.
6. **Limites do código alheio como parâmetros ótimos.** Conexões por host, tamanho do lote e intervalos de refresh são escolhas situadas; medir política do FeedMine antes de mexer.
7. **Estado terminal por ausência em janela finita.** Falta na janela local não prova exaustão de supply, catálogo ou internet.
8. **Versão nova sem preservar biblioteca pessoal.** Dados recompiláveis podem ser recapturados; coleções, fontes escolhidas, posições e salvos exigem migração ou decisão explícita e comunicada.

---

# 24. Perguntas que uma próxima auditoria de código deve responder com `file:line`

Estas são perguntas **para investigação**, não alegações de defeito atual. Ler o commit alvo e documentar caller, owner, teste e observação física.

| Área | Pergunta concreta | Onde começar no FeedMine |
|---|---|---|
| Demanda | Quais sinais fazem `RunwayController` pedir reposição ou exploração? | `Sources/FeedMineRuntime/RunwayController.swift`, `RunwayPolicy` |
| Produção | Qual o primeiro ponto em que cada candidato saudável pode ser persistido? | `FeedRunwayDriver`, `RunwayAcquisitionCycle`, admission |
| Readiness | O candidato pendente é suspenso sem envenenar o lote? | `MediaReadiness`, `MediaPreparation`, selection |
| Receipts | A edição/contexto antigos podem completar persistência reutilizável sem alterar UI atual? | `AppComposition.swift`, publication receipt handling |
| Publicação | Existe algum caminho que reescreve payload de card admitido? | `PublicationStore`, `PublicationCoordinator` |
| Projeção | O snapshot é finito, local, estável e atualizado apenas após mudança causal legítima? | `FeedPresentationSnapshot.swift`, `FeedSession` |
| UI | Quem altera a âncora física quando cards entram no fim? | `Sources/FeedMineUI/FeedScreen.swift`, `ReaderShell.swift` |
| Banco | Quem grava durante scroll e quando as transações são fechadas? | `FeedMinePersistence`, acesso SQLite |
| Mídia | A política de decode segue o viewport ou refaz pixels inutilmente? | `MediaPrefetcher`, media broker/decoder |
| Catálogo | Fontes nunca tentadas ganham oportunidade com runway saudável? | Discovery/catalog resolver e acquisition targets |
| Retorno | Em que instante o app decide renderizar o restaurado versus preparar algo novo? | lifecycle/composition/restore |
| Background | Quais tarefas podem ser retomadas, canceladas e reconhecidas idempotentemente? | iOS app lifecycle / background task callers |
| Dados pessoais | Qual operação migra V1 e como rollback preserva dados? | migrations, `ReaderLibraryStore`, documentação V1 |

**Formato mínimo de achado:** `item → veredito → arquivo:linha → evidência de execução ou código → implicação de produto → correção mínima`. Distinguir **falha comprovada**, **risco latente**, **lacuna de teste** e **comportamento intencional**.

---

# 25. Critérios de decisão para mudanças arquiteturais

Antes de introduzir fila, actor, geração, scheduler, mecanismo de fallback ou tabela adicional, responder:

1. Qual invariante de produto está sendo violada **agora**, com prova reproduzível?
2. Por que o owner atual não pode garantir a invariante?
3. Onde a correção mínima pode ocorrer, sem transferir conhecimento de protocolo para UI?
4. Como a solução preserva trabalho de outros contextos e dados pessoais?
5. O que acontece se a operação for suspensa, cancelada ou retornar fora de ordem?
6. Quais métricas indicam melhoria real do scroll, runway e aproveitamento, além de um teste unitário?
7. Qual mecanismo redundante pode ser removido depois da mudança?

Se as respostas não justificam uma nova camada, preferir consolidar a existente. A simplificação é um resultado arquitetural legítimo.

---

# 26. Referências verificáveis e trilha de leitura

## 26.1. Código aberto, prioridade 1

**NetNewsWire** (código Swift iOS/macOS):

- [Repository](https://github.com/Ranchero-Software/NetNewsWire)
- [DownloadSession.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/Modules/RSWeb/Sources/RSWeb/DownloadSession.swift) — tarefa, 429, 4xx, por host, conditional GET, progresso.
- [LocalAccountRefresher.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/Modules/Account/Sources/Account/LocalAccount/LocalAccountRefresher.swift) — recência, parse, artigo novo/atualizado, falha individual.
- [AccountManager.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/Modules/Account/Sources/Account/AccountManager.swift) — `withTaskGroup` entre contas.
- [CombinedRefreshProgress.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/Modules/Account/Sources/Account/CombinedRefreshProgress.swift) — progresso agregado.
- [AppDelegate.swift](https://github.com/Ranchero-Software/NetNewsWire/blob/main/iOS/AppDelegate.swift) — BGAppRefreshTask e cancelamento.

**FeedFlow** (Kotlin Multiplatform + iOS SwiftUI):

- [Repository](https://github.com/prof18/feed-flow)
- [FeedFetcherRepository.kt](https://github.com/prof18/feed-flow/blob/main/shared/src/commonMain/kotlin/com/prof18/feedflow/shared/domain/feed/FeedFetcherRepository.kt) — `flatMapMerge`, cache HTTP e batch.
- [FeedSyncIosWorker.kt](https://github.com/prof18/feed-flow/blob/main/shared/src/iosMain/kotlin/com/prof18/feedflow/shared/domain/feedsync/FeedSyncIosWorker.kt) — sincronização, `Mutex`, persistência de intenção.
- [CLOUD_SYNC_ARCHITECTURE.md](https://github.com/prof18/feed-flow/blob/main/docs/CLOUD_SYNC_ARCHITECTURE.md) — distinção entre banco do app e estado pessoal sincronizado.

**Tapestry**:

- [The Iconfactory/Tapestry](https://github.com/TheIconfactory/Tapestry) — API e conectores; **não** o runtime completo.

## 26.2. Produtos e informações oficiais

- [feeeed](https://apps.apple.com/ca/app/feeeed-rss-reader-and-more/id1600187490) — descrição de privacidade, modo offline e conteúdo heterogêneo.
- [Reeder](https://apps.apple.com/ca/app/reeder/id6475002485) — leitura e acompanhamento de origens.
- [NewsBlur](https://newsblur.com/) — serviço e cliente iOS; release iOS 15 e notas de performance devem ser consultadas no site/blog oficial.
- [lire](https://lireapp.com/) — full-text RSS.
- [GoodLinks](https://goodlinks.app/) — leitura offline de artigos salvos.
- [Omnivore](https://github.com/omnivore-app/omnivore) — estudo histórico de cliente+backend, não equivalência local-only.

## 26.3. Apple

- [BackgroundTasks](https://developer.apple.com/documentation/backgroundtasks) — BGAppRefreshTask, BGProcessingTask e políticas do sistema.
- [URLSessionConfiguration.background](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)) — sessões de transferência administradas pelo sistema.
- [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask) — continuidade de tarefa iniciada pelo usuário, não crawler permanente.
- [SwiftUI — otimização](https://developer.apple.com/documentation/swiftui/understanding-and-improving-swiftui-performance) — instrumentação de recomposição e layout.
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines) — padrões de leitura, feedback e acessibilidade.

## 26.4. Documentos vigentes do FeedMine (autoridade de produto)

- [Product North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md)
- [Decisões de produto](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md)
- [F05 — Continuidade do feed](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F05_CONTINUOUS_RUNWAY_PRODUCT_PRD.md)
- [F06 — Card readiness](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F06_SACRED_FEED_CARD_READINESS_PRD.md)
- [Benchmark de aceite](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md)
- [Responsabilidades de arquivos](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/FILE_RESPONSIBILITIES.md)
- [FeedPresentationSnapshot](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineRuntime/FeedPresentationSnapshot.swift)
- [RunwayController](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineRuntime/RunwayController.swift)
- [FeedScreen](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedScreen.swift)

**Referência arquitetural de trabalho:** *FeedMine Feed Runtime — Unified Architecture Blueprint v0.4* (documento do projeto). O Blueprint orienta a comparação; mudanças efetivas precisam respeitar os PRDs/decisões mais recentes e a implementação inspecionada no commit alvo.

---

# 27. Parecer final

Os aplicativos analisados demonstram técnicas valiosas, mas **não uma solução pronta para transplantar** ao FeedMine. NetNewsWire fornece o caso mais rico de rede/refresh Swift auditável. FeedFlow fornece contraste para concorrência e persistência. feeeed e Reeder comprovam uma proposta local-first orientada ao usuário sem revelar detalhes internos suficientes para imitação arquitetural. Tapestry explicita a fronteira de conectores. NewsBlur oferece resultados expressivos de performance de UI, mas com agregação remota. Apple delimita as oportunidades de background.

O FeedMine já especifica a linha de produção necessária e a autoridade local da apresentação. O gargalo decisivo a investigar não é “quanto tempo demora consultar um feed RSS”, e sim **qual etapa, nas condições reais de consumo, deixa a reserva de histórias publicáveis cair abaixo da demanda ou perturba uma história já entregue ao leitor**.

Portanto, o caminho recomendado é: **provar o comportamento com medições causais, corrigir as fronteiras existentes, preservar a durabilidade e só depois otimizar.** As seções 18–24 compõem o roteiro executável para essa próxima auditoria. Este relatório não declara PASS de nenhum cenário que não tenha sido executado no iPhone/Mac identificado.
