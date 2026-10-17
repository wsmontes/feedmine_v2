# FeedMine V2 — Auditoria de capacidade e acoplamento do backend (“kernel de velocidade”)

**Revisão externa · 17/out/2026 · base inspecionada `main@5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`.**

**Tipo de evidência:** inspeção estática de código e documentação vigente, com leitura dos owners de descoberta, aquisição, execução, mídia, seleção, publicação, sessão, runway, persistência e fronteira UI. Foram examinados os caminhos representativos e seus contratos; **não** é auditoria exaustiva de cada método nem perfil de CPU/SQL/rede. Não rodei build, teste nem Instruments. Classificações abaixo distinguem **fato no código**, **risco arquitetural** e **hipótese de custo**; números de capacidade simulada são **propostas de prova**, não observações. O diagnóstico de scroll mais específico está em [estudo paralelo](FEEDMINE_SCROLL_ARCHITECTURAL_STUDY_2026-10-17.md).

## 1. Mandato do produto: folga de ordem de grandeza

**Intenção explicitada pelo dono:** o leitor não deveria operar perto do limite da máquina que o alimenta. Uma UI que consome dezenas/centenas de cards precisa ser sustentada por um backend capaz de lidar com milhares de candidatos e muitas fontes e preparações independentes. O objetivo desejado é **capacidade de processamento da ordem de 10× a demanda relevante**, com interfaces que não aguardam trabalho de produção e com prioridades alteradas rapidamente por decisões do leitor.

**Interpretar 10× como meta de folga verificável por estágio e numa configuração controlada**, não como:
- manter 10× a janela do leitor em RAM, baixar 10× mídia, abrir exatamente 100 conexões ou exigir 10× throughput de feeds públicos que não entregam esse volume;
- prometer que iOS executará aquisição ilimitada quando suspende o aplicativo;
- criar outra fila/scheduler/cache/kernel concorrente para implementar os mesmos owners;
- definir novos números mágicos permanentes (`INV-16` e `PD-8` explicitamente proíbem quotas fixas como estratégia).

**Três capacidades distintas:**
1. **Throughput sustentado:** candidatos/s (admitidos, selecionados, preparados, publicados) sob carga de teste sintética e recursos permitidos; medir estágios separadamente para não confundir 10 mil *registrados* com 10 mil *prontos*.
2. **Resiliência à latência:** uma fonte, mídia, transação ou consulta lenta não segura o progresso dos trabalhos independentes nem o primeiro prefixo válido do leitor.
3. **Folga do runway:** stock *já publicado e render-ready* em relação ao ritmo do leitor e ao p95 de preparação. Manter adaptativamente `D ≈ r × L × margem`, acrescido de segurança compatível com recursos e diversidade; a meta de 10× do *motor* não se traduz automaticamente em 10× cards exibidos.

**Regra qualitativa:** backlog grande deve custar apenas metadados/bytes locais baratos onde aplicável; a banda próxima ao viewport merece pixels e consumo de RAM. O custo por oportunidade/callback tem de ser controlado e não crescer com toda a história. Em mudança de filtro, **reavaliar política/contexto e reusar supply, downloads, conteúdo e edições válidas**; nunca destruir tudo “para refazer rápido” se o trabalho anterior continua reutilizável (INV-10).

As regras já constam em [Norte](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [F05-R2/R5/R6/R7](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F05_CONTINUOUS_RUNWAY_PRODUCT_PRD.md), [INV-01–05, 10, 12, 14–16](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [PD-5/6/8/9](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md). Esta nota não muda esses contratos.

## 2. Arquitetura existente — o que preservar

```text
   Interação/UI local (consome cards prontos; emite fato breve)
                |                  ^ recibo pronto e coerente
                v                  |
   FeedSession + RunwayController + FeedRunwayDriver (owners atuais)
                |  pressão/escopo/identidade
                v
   AcqPlanner -> AcqCoordinator -> conectores RSS/HTTP
       | resultados/batches admitidos (duráveis)
       v
   ContentStore / catálogo canônico -> CandidateProvider
       |                              |
       +-----------------> SelectionEngine + exposure
                                      |
                   MediaPrefetcher/readiness + preparar texto
                                      |
                    PublicationCoordinator/Store (append imutável)
                                      |
                             Runway publicado local
                                      |
                    projeção limitada/admissão pelo leitor
```

**Não está tudo errado.** Já existem: `URLSession` async, coordinator de alvos com `inFlight` por target, `withThrowingTaskGroup` de aquisição, MediaPrefetcher com tarefas concorrentes/single-flight, GRDB `DatabasePool` com WAL, keyset queries, identidade imutável de publicação, ator do runway, driver com ownership causal e hold visual. Há [teste de ContentStore com 10.000 e 100.000 linhas](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Tests/FeedMinePersistenceTests/ContentStoreCandidateWindowScaleTests.swift#L96-L168); isso demonstra **existência de provas locais de escala de consulta**, não throughput do pipeline inteiro nem resultados executados nesta rodada.

**Problema central observado:** paralelismo dentro das peças, mas barreiras e ciclos seriais entre peças. A CPU pode estar ociosa enquanto espera um evento de admissão, uma janela de mídia, o fim de uma rodada finita ou um callback. Escala por estágio e independência entre estágios ainda não são garantidas end-to-end.

## 3. Gargalos e acoplamentos encontrados

### K-01 — Capacidade de aquisição por oportunidade menor que a capacidade do executor

**FATO / P1 / owner:** `FeedAssociation.resources`, `AcquisitionPlanner`.

- [`AppComposition.swift:2086–2096`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L2086-L2096) configura `targetWorkCapacity: 2`, `batchCapacityPerNewExecution: 1`, `observationCapacityPerBatch: 32`, `byteCapacityPerBatch: 1_000_000`, embora [o coordenador](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L2266-L2276) tenha limite concorrente `max(2, activeProcessorCount)`.
- [`AcquisitionPlanner.swift:113–135`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineAcquisition/AcquisitionPlanner.swift#L113-L135) seleciona no máximo `resources.targetWorkCapacity` alvos numa rodada. **Dois por oportunidade**, não duas fontes para sempre.

**Consequência:** a janela executora pode ficar subutilizada mesmo com recursos de rede/CPU disponíveis. Byte cap é importante para segurança; **não** simplesmente removê-lo. **Correção:** usar o dono de planejamento existente para dimensionar permissões/planos por demanda real, latência, throughput, energia/rede e pressão de runway, mantendo os limites de segurança de batch/bytes e justiça entre fontes. Verificar progresso com alvos lentos e rápidos; não substituir 2 por outro número fixo.

### K-02 — Callback de resultado segura a reposição de vagas da janela de aquisição

**FATO / P1 / owner:** `AcquisitionCoordinator`.

Em [`AcquisitionCoordinator.swift:143–169`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineAcquisition/AcquisitionCoordinator.swift#L143-L169), `executeConcurrently` aguarda `group.next()`, então `await onResult(result)` **antes** de chamar `startMore()`. No [cold bootstrap](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/ColdFeedBootstrap.swift#L216-L234), o callback pode executar `attemptFirstPublication`, inclusive preparo de mídia e seleção, antes de devolver controle ao reabastecimento dos slots de aquisição.

**Consequência plausível:** fetchs independentes deixam de ocupar vagas enquanto o processador do resultado decide a primeira publicação. **Separar** “resultado durável recebido; vaga liberada para próximo alvo” de “efeitos de composição desse resultado” pela fronteira existente; sem perder ordenação de resultados, cancelamento, fences e single-flight por alvo. Isto não exige segundo scheduler. Prova discriminante: segurar o callback de uma fonte concluída e verificar se outro alvo pode começar quando há slot livre, sem lançar duas execuções do mesmo alvo.

### K-03 — Uma execução causal do driver pode aguardar o ciclo inteiro de HTTP

**FATO + INFERÊNCIA / P1 / owner:** `FeedRunwayDriver` e `RunwayAcquisitionCycle`.

[`FeedRunwayDriver.swift:202–255`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/FeedRunwayDriver.swift#L202-L255) contém um único `causalExecution`; oportunidades entrantes são coalescidas. Em [`driveCausalEffects`/:267–358](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/FeedRunwayDriver.swift#L265-L358), a ação `.requestAcquisition` **aguarda** `executeAcquisition`, que retorna após [`executeConcurrently`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/RunwayAcquisitionCycle.swift#L63-L71) concluir a rodada. Callbacks sinalizam mudança de supply ao runway, mas o próprio driver causal só reexamina seus próximos efeitos após sair do `await`.

**Risco:** uma fonte lenta pode alongar a rodada enquanto supply de outra fonte já está durável e poderia abastecer publicação futura. Coalescência correta de estado **não equivale** a progresso independente dos estágios. **Correção candidata:** preservar um único owner causal/escopo, mas permitir reconsideração nos fatos duráveis de *cada* resultado em lugar de fazer a próxima seleção depender da conclusão de todo o lote. Não executar dois `drive` concorrentes para solucionar: isso quebraria ownership e poderia duplicar publicação. Provar que “fonte A pronta, fonte B ainda suspensa” produz cards de A sem esperar B, mantendo fairness.

### K-04 — Preparação de mídia na fronteira de seleção ainda pode formar barreira temporal

**FATO / RISCO P1 / owners:** `ColdFeedBootstrap`, `FeedRunwayDriver`, `MediaPrefetcher`.

No [`ColdFeedBootstrap.swift:246–278`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/ColdFeedBootstrap.swift#L246-L278), a próxima janela passa por `await prepareWindowMedia(revisions)` **antes** de executar `initialProductionSlice.run`; no [driver/:318–337](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/FeedRunwayDriver.swift#L318-L337), um slice também espera `prepareMedia` antes de seleção/publicação. A preparação [tem janela de tolerância e continua em background após deadline](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineRuntime/MediaPrefetcher.swift#L151-L203), o que **mitiga** a espera, mas não dispensa examinar sua consequência na liberação de cards que já estão prontos.

**Risco:** o item lento pode atrasar a reconsideração da janela com itens rápidos, até o orçamento expirar. **Correção:** pronto é elegível imediatamente; pendente sai da fila atual sem perder identidade no supply; transições futuras de readiness reabrem a oportunidade correta. Reusar `MediaReadiness` e os mesmos owners. Não reduzir timeout só para ocultar a barreira; não admitir imagem sem pixels decodificados nem converter publicação congelada em texto como fallback.

### K-05 — Travessia de catálogo faz trabalho proporcional ao histórico de páginas

**FATO / RISCO DE ESCALA P1 / owner:** `ReaderDiscoveryTraversal`.

[`ReaderDiscoveryTraversal.swift:98–137`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/ReaderDiscoveryTraversal.swift#L98-L137) monta `known = Set(pages.flatMap { $0.entries }.map(\.targetID))` **dentro de lock** a cada `advance`/`adopt` e chama `materialize(additions)` ainda sob esse lock. [`:144–174`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/ReaderDiscoveryTraversal.swift#L144-L174) percorre páginas para montar targets/health e buscar um conector por `page.entries.contains(where:)`.

**Consequência assintótica:** reconsideração repetida sobre páginas acumuladas pode passar de aproximadamente linear por página a custo **quadrático no número de páginas ao longo da jornada**, sob carga de milhares de fontes, mesmo que cada página seja limitada. **Correção:** manter consulta/identidade de alvos preparados no owner canônico já existente, ou um índice derivado *no mesmo owner* apenas se indispensável; não replicar uma autoridade. Não realizar materialização/DB/network sob lock de estrutura de coordenação quando possível; preservar atomicidade de instalação/revogação através da autoridade atual. Testar custo da página N e da página 1 com milhares de fontes, inclusive promoção do catálogo.

### K-06 — MainActor recebe instalação com consulta SQLite síncrona

**FATO / P0 DE FRONTEIRA / owners:** `FeedAssociation`/biblioteca.

[`AppComposition.swift:2623–2636`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L2623-L2636): `FeedAssociation` é `@MainActor`; em mudança de `window.ids` chama sincronamente `PublicationStore(database: database).bookmarkedCardIDs()`. Não significa SQLite em *todo* frame; significa **I/O de disco na fronteira de atualização da cena**. `RuntimeDatabase` usa GRDB `DatabasePool` WAL, mas [`read/write`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMinePersistence/RuntimeDatabase.swift#L123-L139) são chamadas síncronas para seus callers.

**Correção:** preparar bookmarks/projeções com a janela fora do `MainActor` pelo dono existente, entregar valor coerente e instalar sem bloquear desenho. Não adicionar cache mutável da biblioteca só para fugir do I/O.

### K-07 — Observações visuais ainda transportam janelas inteiras e acordam composição

**FATO / P1 DE FRONTEIRA / owners:** `FeedScreenStore`, `FeedPresentationSnapshot`, `FeedAssociation`.

[`FeedScreen.swift:113–140`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineUI/FeedScreen.swift#L113-L140) faz busca linear em `renderedItems` no callback. [`FeedPresentationSnapshot.swift:133–139`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineRuntime/FeedPresentationSnapshot.swift#L133-L139) verifica `window.items.contains` e gera `admittedIDs: window.items.map(\.id)` na evidência. [`AppComposition.swift:1788–1794`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L1788-L1794) cria `Task` por callback que volta a `viewport` isolado no `MainActor`; `FeedScreenStore.install` compara arrays renderizados.

**Consequência:** o próximo frame não aguarda explicitamente fetch, mas a UI paga trabalho e enfileiramento de composição proporcional à atividade. **Correção:** observações pequenas com scope/seq/âncora/direção; consumidores fora da UI interpretam e processam. Prevenir task por frame e coalescer apenas fatos intermediários substituíveis, nunca repouso durável, posição necessária ou fencing de edição. Evitar “otimizar” removendo instalações vitais ao runway. Ver [estudo da fluidez](FEEDMINE_SCROLL_ARCHITECTURAL_STUDY_2026-10-17.md).

### K-08 — Serialização correta da persistência não deve virar serialização de rede/mídia

**FATO + INVESTIGAÇÃO P1 / owners:** `AdmissionPolicy`, `PublicationCoordinator`, `RuntimeDatabase`.

[`AcquisitionCoordinator.swift:257–305`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineAcquisition/AcquisitionCoordinator.swift#L257-L305): por target, cada `pull` é seguido de `admission.admit(batch)` síncrono e durável antes do próximo pull (o checkpoint atualizado protege replay). `RuntimeDatabase` usa pool com **escritor serial** correto para ACID.

**Não chamar isso de bug sem prova.** A transação única e a ordem por checkpoint são invariantes, mas consultas, parsing, seleção e download independentes não precisam aguardar serialização fora de sua etapa de commit. Investigar filas de espera por escrita/duração de transações e quantidade de trabalho não transacional executado dentro delas, sem múltiplos writers concorrentes e sem abrir mão de CAS/idempotência.

### K-09 — Oportunidades causais, não velocidade constante

**FATO / RISCO FUNCIONAL P1 / owners:** `FeedRunwayDriver`, `RunwayController`.

[`FeedRunwayDriver.swift:202–265`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/FeedRunwayDriver.swift#L202-L265) associa **uma página de catálogo por oportunidade do caller**. A proteção impede descoberta infinita sem recursos e preserva a progressão; mas também cria dependência potencial da quantidade de oportunidades enquanto o leitor está parado e o runway está saudável. [`RunwayController.swift:283–305`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineRuntime/RunwayController.swift#L283-L305) reseta medições de consumo/latência em `activate(scope)`, inclusive reativação da mesma Edition no foreground.

**Risco:** processamento futuro subaproveita folga enquanto a tela está estável ou perde adaptação aprendida. **Provar** se receipts de aquisição, catálogo, mídia, publicação, foreground e recursos dão novas oportunidades suficientes sem gesto. Proatividade significa progredir por **fatos conclusivos e permissão de recursos**, não timer de polling ou busy-loop; preservar aprendizagem no mesmo scope.

### K-10 — Operações editoriais por janela: potencial custo, não gargalo certificado

**FATO / HIPÓTESE DE ESCALA P2:** `SelectionEngine.select` valida arrays e [ordena candidatos por janela](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineEditorial/SelectionEngine.swift#L69-L169); `LocalProductionSlice.run` consulta janela → exposure → readiness → seleção → append **numa chamada síncrona finita** ([`LocalProductionSlice.swift:92–139`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineRuntime/LocalProductionSlice.swift#L92-L139)). São responsabilidades bem separadas, mas uma etapa pode bloquear a próxima localmente.

**Não recomendar portar um motor editorial paralelo ou cachear tudo.** Demonstrar custo por mil candidatos, uso de CPU, persistência e distribuição temática/formato/geografia nas emendas dos segmentos. O defeito editorial atual conhecido é **paridade multidimensional**, não prova de que `sorted` está lento ([diretriz de 17/out](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-interleave-v1-parity-direction.md)).

## 4. Kernel de velocidade: comportamento desejado sem “novo kernel”

**O kernel deve ser uma disciplina do runtime existente**, não mais um framework.

```text
EVENTOS: leitor mudou prioridade | supply foi admitido | mídia pronta |
         publicação concluída | capacidade de recurso mudou | foreground

        v (input minúsculo, não bloqueante, com context/edition)
OWNERS EXISTENTES reavaliam demandas e prioridades:
 - preservar viewport/edição atual enquanto contexto novo é preparado
 - proteger o runway imediato e mídia necessária à banda de leitura
 - explorar catálogo quando há folga real, mesmo sem gesto
 - fazer rede, mídia, seleção e leituras locais progredirem independentemente
 - transações finais curtas e idempotentes, com stamps/fences
        v
RESULTADO PREPARADO (deixa supply canonical reaproveitável)
        v
PUBLICAÇÃO DURÁVEL E IMUTÁVEL
        v
ENTREGA MATERIAL CURTA À UI (nunca bloqueia o gesto)
```

### Propriedades necessárias

1. **Sobreposição de estágios (pipeline):** enquanto B baixa mídia, C pode adquirir outro feed, A pode selecionar candidatos já prontos e D pode publicar. **Nunca** exigir que todos os targets de uma rodada terminem para fazer uso da parte já concluída. O domínio de consistência da *ocorrência individual* continua respeitado.
2. **Prioridades por necessidade, não por fila nova:** (a) manter conteúdo pronto à frente e banda de leitura; (b) resolver candidatos promissores pendentes; (c) ampliar cobertura do catálogo quando houver folga. Essas são classes de prioridade nos owners já existentes, não três subsistemas.
3. **Feedback adaptativo:** consumo observado, latências por etapa, trabalho já preparado, atraso de I/O, recursos (CPU, RAM, disco, bateria, térmica, rede). Se margem real existir, aproveitar; se pressionar, reduzir especulação **antes** de perturbar a leitura.
4. **Mudança de filtros:** nova identidade/prioridade editorial → recalcular a composição *futura* no contexto novo, preservar história e âncora anterior, descartar apenas efeitos obsoletos por escopo; **reusar** candidatos canônicos, imagens/blobs, catálogos, publicações/posições de outros contextos quando válidos. A→B→A não é reconstrução do mundo.
5. **Isolamento físico:** MainActor faz captura/layout/instalação mínima. Acq/Media/Editorial/Persistence trabalham independentemente com limites seguros, sem `await` do produtor no caminho de scroll e sem `Task` por observação de frame.
6. **Sem amplificação de trabalho:** mesma mídia/target não é baixada duas vezes simultaneamente; sinal substituído não dispara novo trabalho; callbacks de readiness são leves; uma falha não provoca tempestade de retries; nunca usar uma fila infinita.
7. **iOS real:** background executa somente quando permitido. Priorizar trabalho útil local, checkpoints e reutilização ao reabrir, sem fingir servidor de conteúdo ou execução ilimitada quando suspenso.

## 5. Provar folga de 10× sem contaminar os gates de produto

Criar ensaio **diagnóstico separado e não normativo**, sem tocar em `bench/` nem inventar PASS oficial. Usar fontes/latências sintéticas controladas, com mesma semântica de integração e bancos reais, e registrar dados de CPU/rede/I/O. Distanciar quantidade cadastrada da quantidade efetivamente admitida/visualizável.

| Dimensão | Experimento com folga (exemplos de escala, **não** quotas de runtime) | Falha que discrimina |
|---|---|---|
| Aquisição | centenas de feeds falsos independentes, parte lenta/bloqueada, parte rápida, milhares de observações | Slots ociosos, alvo lento segurando callback/rodada, fetch duplicado |
| Catálogo | 1.000, 10.000 e mais sources examinadas progressivamente | Custo de página N cresce com todas as anteriores; lock impede avanço |
| Conteúdo local | ≥10.000 candidatos/revisões no banco; percorrer muitas janelas e filtros | Full scan, O(N²), falta de progresso, cursor falso |
| Preparação | milhares de decisões texto/mídia, dezenas de fetchs lentos/falhos e prontos | Foto lenta atrasa texto pronto ou consome orçamento de candidatos independente |
| Publicação | vários segmentos/edições e 10× a taxa de consumo **sintética** em candidatos que existem localmente | Writer/seleção criam acúmulo, duplicidade, reshuffle de histórico |
| Prioridade | A→B→A durante downloads, filtro invertido, rede perdida, foreground | Trabalho descartado desnecessariamente, retorno bloqueado, callback obsoleto admitido |
| UI | scroll rápido de grande edição *já preparada* com produtores trabalhando | MainActor espera SQLite, decode, seleção, atualização da lista por evento |

**Referência externa de carga, não tuning do runtime:** B03 já exercita consumo de 1 card/s com rajadas de 3 cards/s. Um laboratório sintético pode exigir estágios locais capazes de processar uma ordem de grandeza além disso (por exemplo 30 decisões de candidatos/s em condições permitidas) **sem** afirmar que 30 cards de imagem precisam ser publicados por segundo numa rede real. Para cada etapa, medir taxa ofertada, taxa concluída, backlog, p50/p95, tempo bloqueado e uso de recursos; preservar capacidade de atender o leitor sob concorrência.

**Dois testes mais discriminantes antes de otimizar:**
- *A conclui, B fica suspenso:* A entrega bytes/batch; B nunca responde; um terceiro alvo disponível deve iniciar e A deve contribuir para candidatos/publicação sem depender de B.
- *Filtrar sob carga:* centenas de trabalhos elegíveis em preparação; selecionar contexto B e retornar a A não deve rebaixar UI, desintegrar o catálogo ou repetir download de bytes canônicos. Cada contexto só admite seus recibos; história anterior preservada.

**Atenção ao método:** usar testes para refutar essas invariantes de arquitetura; não passar semanas explorando percentuais para decidir se esperas proibidas são aceitáveis. Uma vez removidas as barreiras, medir para certificar throughput/ausência de engasgo e localizar apenas custos restantes.

## 6. Sequência de implementação recomendada (pequena, verificável)

**Gate 0 — preservar correções válidas e bloquear regressões:** reconciliar `fix/deferral-invalidates-list` e não integrar conversão `hero→textOnly` da branch `fix/render-ready-admission` enquanto conflitar com PD-5/INV-17. Prova de identidade e layout é inegociável.

**Gate 1 — desacoplar a UI:** tirar I/O síncrono do `FeedAssociation.install`, trabalho O(n) por evento visual e processamento por `Task @MainActor`, usando os owners existentes. Prova: scroll sobre snapshot local com produtor suspenso não engasga; posição/checkpoint intactos.

**Gate 2 — liberar paralelismo já existente:** desvincular preenchimento de slot de aquisição do callback `onResult`; reexaminar o efeito causal por resultado durável, sem aguardar o target mais lento; não aumentar limites antes de corrigir o bloqueio lógico. Prova: três targets (rápido/lento/rápido), progressão entre conclusões, single-flight e cancelamento.

**Gate 3 — tornar capacidade realmente adaptativa:** substituir `targetWorkCapacity: 2` e regras operacionais que reduzem indevidamente oportunidades por decisão do mesmo planner a partir de recursos/pressão, respeitando quotas de rede/bytes/potência. Rever acoplamento de `prepareMedia` à janela inteira, priorizar itens prontos. Prova: throughput escala quando há folga, recua quando recursos apertam e não deixa runway acabar.

**Gate 4 — escala de descoberta e seleção:** remover reconstrução de todas as páginas sob lock e procura por conector por scan de páginas; usar identidade canônica. Medir janela 1 vs N com milhares de fontes. Só otimizar seleção/SQL adicionalmente quando prova indicar custo; os testes de 100k linhas no ContentStore são ponto positivo.

**Gate 5 — integração/aceite:** juntar árvore final, executar estresse controlado, B01–B05 e B06 no aparelho conforme régua congelada, com medição de CPU/I/O/hitches e jornadas offline, contextos e grande leitura. Não concluir “kernel pronto” por benchmark sintético que não alimenta o leitor real.

**Quem modifica:** owners do OMP nas classes existentes, com worktrees isoladas; o monitor só registra recomendações. Para cada gate: `branch/SHA | falha anterior demonstrada | correção | efeito na jornada | evidência no Mac/iPhone | riscos`.

## 7. Conclusão

**O FeedMine já tem boas peças. O que falta é fazer o conjunto trabalhar como pipeline, não como uma sequência de permissões que atravessa uma etapa de cada vez.** O valor de um backend “10×” é manter folga operacional e independência dos estágios, não apenas consumir CPU ou fazer muito mais requisições. O iPhone não deveria sentir quando o motor encontra uma fonte lenta, muda prioridade, gera thumbnails ou escreve uma transação — desde que a janela pronta e sua identidade continuem protegidas.

**Status desta auditoria:** documentação de achados e plano; **nenhum código alterado, nenhum gate executado, nenhum ganho de velocidade alegado**. A implementação precisa comprovar as propriedades contra a **`main` ou candidata de integração efetiva**, não apenas em branches separadas.
