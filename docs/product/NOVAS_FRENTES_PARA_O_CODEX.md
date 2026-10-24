# Novas frentes para o Codex — FeedMine V2

**Estado:** ABERTO — documento vivo de investigação, implementação e contraditório técnico  
**Iniciado em:** 2026-10-23  
**Dono da priorização:** produto/arquitetura FeedMine  
**Contribuidores esperados:** Codex, revisores independentes e testes em dispositivo  
**Escopo inicial:** relato de uso da build 55 do TestFlight e investigação de código da linha da build 54  
**Próxima revisão:** pelo Codex, após identificar o commit efetivamente distribuído na build 55

> Este arquivo é um **backlog investigativo corrigível**, não um oráculo, uma ordem de implementar todas as sugestões nem uma revisão que substitua as decisões vigentes. O Codex deve **corrigir este próprio documento** quando código, medições ou testes contradisserem suas hipóteses; não deve apenas concordar com ele. Novas frentes podem ser acrescentadas sem reescrever a história. A prioridade é a experiência de uso real.

## 0. Por que abrir estas frentes

**Observação direta do dono em iPhone físico com TestFlight build 55 (2026-10-23):**

1. **Rolagem:** muito lisa. Ganho a preservar; não reintroduzir trabalho síncrono no gesto.
2. **Mistura editorial:** ruim na percepção do leitor.
3. **Continuidade:** novos conteúdos chegam tarde; o leitor alcança o fim do feed.
4. **Responsividade de superfícies:** o botão **Concluído** dos filtros demora a agir; deveria responder imediatamente.
5. **Comunicação na cauda:** a espera é confusa; não se sabe se novos conteúdos estão vindo.

Esse conjunto é um relato de produto, **não** uma medição instrumentada nem prova da causa de cada sintoma.

**Proveniência do código:** a análise que originou o documento leu o commit `3eee19350ccb3fdf8392162694620d875fe041fa` (linha identificada como build 54 em `docs/reviews/CODE_REVIEW_build54_2026-10-22.md` na branch `kiro/review-build54`). No momento da consulta, `main` ainda declarava `CFBundleVersion=49`, e `codex/v2-fluidez-capacidade` declarava 54. **Não foi identificado o SHA exato da build 55.** Não atribuir automaticamente qualquer detalhe do código 54 à 55.

**Primeiro dever do Codex:** localizar a proveniência da build 55 (tag, archive, commit, release script ou evidência do Mac), comparar seus caminhos relevantes com `3eee193` e atualizar os achados abaixo com o estado real. Se não existir correspondência verificável, registrar `BUILD 55 NÃO MAPEADA` e não alegar prova de implementação.

### Convenção de evidências

- **[DISPOSITIVO]** percepção ou medição no aparelho, com build e condições declaradas.
- **[CÓDIGO-54]** leitura verificável de `3eee193`; não é confirmação da 55.
- **[REVISÃO]** achado de outro revisor, ainda sujeito a contraprova.
- **[HIPÓTESE]** explicação plausível, não demonstrada pela medição causal.
- **[ALTERNATIVA]** solução candidata, não instrução obrigatória.
- **[VALIDADO]** reproduzido e validado na árvore nomeada, com teste/trace e ambiente.
- **[REFUTADO]** hipótese contrária às evidências, com motivo e referência.

O Codex deve converter cada hipótese em confirmado, parcialmente confirmado ou refutado **in situ**. Ao mudar uma conclusão, preservar uma entrada curta no histórico de revisões, não manter duas verdades paralelas.

## 1. Princípios e limites que todas as frentes devem preservar

1. **Feed contínuo:** oferta disponível e capacidade suficiente não podem resultar em uma cauda artificial que depende de o usuário alcançar o fim para continuar.
2. **Rolagem sagrada:** não piorar a fluidez já observada; scroll/viewport registram fatos de maneira barata e retornam, sem aguardar rede, disco, seleção ou mídia.
3. **Local-first de verdade:** usar publicação preparada e persistida antes de adquirir; antecipar trabalho externo quando a capacidade local prevista não sustentar o consumo. *Prioridade ao local* não significa necessariamente *serializar toda a rede atrás do esgotamento local*.
4. **Cards prontos antes de admitir:** mídia declarada conforme política, ou apresentação text-only legitimamente pronta; não publicar uma promessa de layout incompleta.
5. **Identidade e imutabilidade:** preservar a ordem já publicada, posição, contexto, histórico pessoal e uso offline; edições antigas guardam a versão de sequenciamento sob a qual foram criadas.
6. **Capacidade adaptativa:** não substituir a análise por “32, 100 ou 500 cards bastam”. Quantidade renderizada, estoque preparado, distância visual e custos de produção são grandezas distintas.
7. **Sem camadas por reflexo:** preferir os owners existentes (`FeedSession`, `RunwayController`, `FeedRunwayDriver`, `AcquisitionCoordinator`, `SelectionEngine`, `FeedAssociation`). Não somar cache, scheduler, timer, retry, geração ou state machine sem provar por que os atuais não atendem.
8. **Evidência acima de verde cosmético:** respeitar os gates B01–B06 e `bench/` congelado; testes unitários aprovados não substituem jornada no aparelho nem provam ausência de fim artificial.
9. **Limites iOS:** trabalho no foreground pode ser proativo; background depende de oportunidades concedidas pelo SO. Não prometer aquisição permanente em background.
10. **Hierarquia documental:** este backlog é subordinado a `docs/product/PRODUCT_NORTH_STAR.md`, `docs/product/PRODUCT_DECISIONS_2026-10-09.md`, `docs/architecture/PRODUCT_INVARIANTS.md`, decisões posteriores aplicáveis e especificações de release.

## 2. Mapa de frentes

| ID | Prioridade inicial | Sintoma / objetivo | Estado inicial |
|---|---|---|---|
| NF-01 | **P0** | Runway acaba antes da chegada de cards novos | Aberta; investigar causa dominante |
| NF-02 | **P1** | Mistura de fontes, provedores e assuntos não parece diversa | Aberta; caracterizar oferta versus sequenciamento |
| NF-03 | **P1** | Concluído dos filtros só reage depois de operação longa | Caminho bloqueante confirmado no código 54; 55 pendente |
| NF-04 | **P1** | Espera e fim do feed têm mensagens ambíguas | Semântica e apresentação divergentes no código 54; 55 pendente |
| NF-05 | **P0, habilitadora de NF-01** | Métrica de reposição não representa toda a jornada | Hipótese estrutural, requer instrumentação |
| NF-06 | **P2, exploratória** | Aproveitamento de rede, cache HTTP e prioridade de trabalho | Inventariar antes de alterar |

**Ordenação de execução sugerida:** NF-05/NF-01 em conjunto; NF-03 e NF-04; NF-02 com corpus real. O Codex pode propor outra ordem baseada em evidência, registrando por quê.

## NF-01 — Continuidade real: aquisição e preparação antes da cauda

**[DISPOSITIVO]** A rolagem permanece fluida, mas o usuário chega ao fim; a reposição aparece tarde.

**[CÓDIGO-54] Caminhos de leitura:**

- `Sources/FeedMineRuntime/RunwayController.swift`: `acquisitionIntentIfEligible(coverage:)` (por volta de 255–269) exige `localSupplyExhausted`, ausência de fatia em voo e ausência de falha local para emitir aquela demanda de aquisição.
- `Sources/FeedMineRuntime/RunwayPolicy.swift`: `evaluate` calcula cobertura a partir de taxa estimada, latência P95, margem e reserva mínima.
- `Sources/FeedMineComposition/FeedRunwayDriver.swift`: `driveCausalEffects`, `executeAcquisition`, oportunidade de fatos duráveis tardios e `publishedGrowth` no host.
- `Sources/FeedMineComposition/ForegroundDriveCadence.swift`: oferece uma oportunidade em foreground com intervalo mínimo de 10 segundos; verificar se é complemento ou gargalo no fluxo observado.
- `Sources/FeedMineRuntime/FeedSession.swift`: distinguir janela admitida/renderizada da oferta publicada e da oferta ainda elegível.
- `FeedMineApp/FeedMineApp/AppComposition.swift`: `runwayMinimumReserveCards = 32` e `forwardWindowCards = 16` no código 54; **não interpretar esses números como garantia de continuidade**.

**[HIPÓTESES a testar separadamente]**

1. A aquisição que deveria evitar o déficit só é autorizada depois de trabalho local infrutífero.
2. O cálculo de cobertura considera uma latência de produção curta demais para necessidades que exigem rede + preparação + publicação.
3. A oferta canônica é ampla, mas a oferta *elegível e pronta* é pequena, por filtros, mídia, descoberta ou seleção.
4. Uma publicação pronta chega, mas sua admissão na janela visível não acontece a tempo (fence/receipt/posição ou handoff).
5. Fontes externas estão de fato indisponíveis, em cooldown ou insuficientes; isso **não** deve ser mascarado como falha do runway.

**[ALTERNATIVA preferida a investigar]** Antecipação orientada por **tempo de runway utilizável**: comparar consumo provável até a cauda (preferir distância visual ou uma proxy justificada) com custo observado de chegar a um novo card apresentável. Usar dados locais primeiro, mas autorizar aquisição externa na mesma estrutura quando a produção local prevista não fecha o déficit; sem duplicar pipeline. A quantidade preparada deve adaptar-se ao consumo, latência, recursos, disponibilidade e contexto. Não alterar indiscriminadamente o piso 32.

**Perguntas para o Codex:**

- Qual caminho exato leva de observação de viewport → pressão → aquisição → publicação → ampliação da lista na **build 55**?
- Em que ponto o runway podia antecipar trabalho e não o fez? A autorização local-first é o gargalo ou está correta para a oferta real?
- O `ForegroundDriveCadence` restringe a antecipação mesmo havendo eventos causais? Há oportunidade já existente que dispense polling?
- O algoritmo confunde “não pronto”, “localmente esgotado”, “sem elegibilidade”, “requisição adiada” e “fim real”?
- Há regressão em cards publicados, porém não admitidos? Existe fence recusando recibos legítimos?

**Teste discriminante:** jornada com rede controlada/HTTP suspenso, catálogo com oferta real elegível, leitor consumindo a velocidades variadas, instrumentando reserva/latência e momento da primeira necessidade externa. Distinguir (a) oferta suficiente/capacidade suficiente — **não pode atingir fim artificial** — de (b) oferta insuficiente, rede indisponível ou throttling legítimo — deve comunicar a condição verdadeira. Verificar preservação de posição e frames.

**Risco:** antecipação sem orçamento consome bateria/rede, disputa banco/mídia e piora scroll. Qualquer autorização deve respeitar o mesmo `StageBudgetPolicy`/`AcquisitionCoordinator`.

**Status Codex:** PENDENTE DE CONTRADITÓRIO.

## NF-02 — Diversidade editorial percebida, não somente alternância de IDs

**[DISPOSITIVO]** “Embaralhamento dos conteúdos está ruim.” Ainda faltam sequência concreta e perfil de fontes da build 55.

**[CÓDIGO-54] Caminhos de leitura:**

- `Sources/FeedMineEditorial/SelectionEngine.swift`: pesos antes dos desempates de diversidade; versão de sequenciamento 5; seleção de candidatos ready.
- `Sources/FeedMineEditorial/SourceAlternation.swift`: `compatible` exige fontes disjuntas (`SourceID`), mas não provedores disjuntos; `applyBySupplyShare` / weighted trabalham sobre a oferta da janela.
- `Sources/FeedMineEditorial/SelectionDiversity.swift`: `source`, `provider`, `subjects`; a comparabilidade depende dos metadados dos candidatos em cada grupo.
- `FeedMineApp/FeedMineApp/AppComposition.swift`: construção de `EditorialRevision`, scoring/seleção v5 e congelamento de contexto.
- `docs/reviews/R1_EDITORIAL_DIAGNOSIS.md`: análise **histórica**, incluindo 23 cards visualmente “BBC News” provenientes de IDs diferentes; **não** é medição da build 55.

**[HIPÓTESES]**

1. Muitos `SourceID` diferentes representam um mesmo provedor/nome editorial; a regra formal passa, a percepção falha.
2. A descoberta/acquisição entrega poucas fontes quando o primeiro segmento é publicado; nenhum sequenciador cria variedade ausente.
3. A janela examinada limita opções e contabiliza proporcionalidade somente dentro dela.
4. Pesos/editorial e metadados parciais reduzem a influência da diversidade recente.
5. Candidatos elegíveis mas ainda não-ready podem ser ultrapassados pelo cursor: `SelectionEngine.report(window:held:placedAny:)` só reconsidera certos candidatos held (achado P1-5 de `CODE_REVIEW_build54_2026-10-22.md`); confirmar se o retorno à prontidão já tem outro caminho que fecha essa lacuna.

**[ALTERNATIVAS, não decisões]** Comparar a versão atual com *weighted fair scheduling* entre fontes/provedores, repetição histórica entre segmentos e uma penalidade tipo *maximal marginal relevance* para redundância de assunto, sempre condicionadas à oferta efetiva. Verificar a paridade útil da V1 (`Reservoir`/`EditorialSequencer`) sem restaurar owners concorrentes, aleatoriedade opaca nem desrespeitar preferências. Não introduzir embeddings/LLM como pré-requisito.

**O que medir:** para um prefixo real de sessão (por exemplo, 100 cards como **amostra de diagnóstico**, jamais tamanho de página de runtime), registrar `SourceID`, `ProviderID`, nome editorial exibido, assuntos, scoring, ordem de chegada e tempo de prontidão. Comparar distribuição **disponível → elegível → ready → selecionada → publicada**. Medir concentração por provedor, máximos de sequência, redundância de assunto, recência, cobertura de origem e aproveitamento de candidatos. Separar “oferta pobre” de “sequenciador pobre”.

**Teste discriminante:** replay determinístico da MESMA oferta sob política anterior e candidata, com casos de múltiplas fontes do mesmo provedor, pesos divergentes, metadados faltantes, apenas uma fonte e candidato não-ready que fica ready depois. Medir regressão de relevância e starvation, não apenas diversidade estatística. Um teste humano exploratório deve verificar se a diferença é perceptível.

**Não negociável:** a ordenação de edições já publicadas é imutável. Se a semântica mudar, versionar a política e preservar restauração.

**Status Codex:** PENDENTE DE CONTRADITÓRIO.

## NF-03 — Concluído dos filtros deve reconhecer o toque imediatamente

**[DISPOSITIVO]** O botão de confirmação demora a agir.

**[CÓDIGO-54] Encadeamento observado:**

1. `Sources/FeedMineUI/Filters/FilterSheetView.swift`: botão `Concluído` aguarda `store.apply()` antes de `onDone()`.
2. `Sources/FeedMineUI/Filters/ReaderFilterStore.swift`: `apply` aguarda `onApply(filter,preset)`.
3. `FeedMineApp/FeedMineApp/AppComposition.swift`: `applyFilter` faz escrita durável e depois `await replaceSession()`; `replaceSession` encerra a associação anterior e aguarda `next.launch()`, potencialmente incluindo aquisição.
4. `FeedMineApp/FeedMineApp/FeedMineApp.swift`: sheet usa `onApply: composition.applyFilter` e `onDone: popSurface`.

Esse caminho estabelece dependência de **resposta visual** na reconstrução completa; não prova por si só bloqueio da thread principal. Comparar com a 55.

**[ALTERNATIVA]** Separar os compromissos sem inventar segunda fonte de verdade:

- Toque: reconhecimento visual síncrono; evitar duplo envio.
- Persistência: confirmar a seleção **duravelmente** antes de declarar sucesso.
- Apresentação: após persistir, dispensar sheet e continuar transição por owner existente, sem esperar HTTP/novo feed pronto.
- Handoff: conservar apresentação anterior como **anterior** até que a nova seja válida; não exibi-la como se já respeitasse o filtro novo. Avaliar com o produto a transição/rotulagem correta.
- Falha: se a persistência recusar, manter draft/folha e reportar o erro; se ativação falhar após salvar, dizer claramente “salvo, mas ainda não apresentado”, com ação recuperável.
- Concorrência: A→B→A e toques rápidos não podem deixar resultado velho assumir a tela nem perder preferência mais recente.

**Perguntas ao Codex:** qual é o mínimo para quebrar a espera da UI sem violar o contrato durável? `replaceSession()` precisa necessariamente aposentar a anterior antes de existir apresentação substituta? Existe caminho de reaproveitamento de contexto que hoje é destruído desnecessariamente?

**Teste discriminante:** injetar uma fonte/launch suspenso após persistir a preferência e afirmar que feedback e fechamento ocorreram **sem resolver** essa suspensão; caso de falha de gravação mantém folha aberta; A→B→A prova última seleção e nenhuma publicação superada. Testar no aparelho a latência toque→feedback e toque→fechamento. Testes não podem passar apenas porque a fixture desabilitou a rede sem bloquear a fronteira relevante.

**Status Codex:** BLOQUEIO DE FLUXO CONFIRMADO EM CÓDIGO-54; IMPLEMENTAÇÃO-55 NÃO VERIFICADA.

## NF-04 — A cauda deve comunicar o trabalho verdadeiro

**[DISPOSITIVO]** A pessoa não sabe se conteúdo novo realmente está vindo.

**[CÓDIGO-54]**

- `Sources/FeedMineUI/FeedPresentationState.swift`: `Work` distingue `.idle`, `.pending`, `.preparing`, `.deferred`, `.unavailable`, `.unreachable`, `.failed` e `.endOfContent`.
- `Sources/FeedMineUI/FeedScreenChrome.swift`: `FeedWorkBadge` mostra `.pending`/`.preparing`, mas não `.deferred`, mesmo com cards disponíveis.
- `Sources/FeedMineUI/FeedLoadingView.swift`: para `.deferred`, texto “Procurando mais novidades…”, embora uma aquisição ativa não seja necessariamente comprovada.
- `Sources/FeedMineComposition/FeedPresentationHandoff.swift`: faz a projeção de outcomes para `Work`.
- `Sources/FeedMineComposition/FeedEligibleOffer.swift`: declaração de fim requer `noEligibleTargets`, local exausto, nenhuma operação pendente e nada pronto adiante. Não inferir fim de uma janela momentaneamente vazia.

**[ALTERNATIVA]** Usar o **estado real dos owners existentes** para uma apresentação discreta na cauda, sem bloquear a lista nem deslocar a posição:

| Evidência real | Texto possível | O que não afirmar |
|---|---|---|
| Aquisição ativa | “Buscando novas histórias” | Que virão artigos elegíveis |
| Material durável aguardando preparo/publicação | “Preparando novas histórias” | Que a mídia está pronta se não estiver |
| Adiada/sem aquisição ativa confirmada | “Aguardando nova oportunidade” | “Procurando agora” |
| Falha de transporte efetiva | “Sem conexão para buscar novidades” | “Não existem histórias” |
| Oferta elegível comprovadamente esgotada | “Você chegou ao fim do disponível nesta seleção” | “Buscando” |

**Design:** manter os cards já admitidos; informar estado na cauda, inclusive com cards visíveis quando necessário. Não inventar percentual, cronômetro ou número de fontes “trabalhando”. Quantidades reais só se os contadores forem verdadeiros e coerentes com a promessa. Não oferecer botão inerte ou ação que não faz o que diz.

**Teste discriminante:** cada condição do pipeline precisa produzir exatamente o texto correspondente; diferenciar rede bloqueada, cooldown, preparo local, aquisição ativa, nenhuma fonte elegível e publicação tardia. Não mostrar “fim” antes da prova; retirar a mensagem de fim quando crescimento legítimo ocorrer. A rolagem e a âncora devem ficar estáveis sob mudanças no estado da cauda.

**Status Codex:** SEMÂNTICA APARENTEMENTE INCONSISTENTE EM CÓDIGO-54; VALIDAR NA 55.

## NF-05 — Latência de ponta a ponta, não apenas fatia local

**[CÓDIGO-54]** `RunwayController.completeLocalSlice` acumula latência de fatias que publicaram; `RunwayPolicy.evaluate` usa `runwayP95(latencySamples)` com velocidade de consumo e margem. `RunwayController.consumption` usa `consumptionSamples.max()`. Não está demonstrado que esse P95 represente demanda→primeiro card pronto quando a reposição exige rede.

**[HIPÓTESE]** O sistema pode declarar runway saudável ao modelar uma fase mais curta que o caminho crítico real; ou uma amostra de velocidade máxima pode tornar a estimativa instável. Confirmar com traço causal da 55, sem confundir latência local com e2e.

**[ALTERNATIVA]** Instrumentar a operação **existente**, sem outro estado de controle: observação/pressão → solicitação → autorização de rede (se houver) → primeira oferta durável → elegibilidade → readiness → publicação → admissão UI. Registrar separadamente casos 100% locais, casos que exigem rede, operações sem novos cards, cooldown, erros e resultados tardios. Medir duração e2e real, não somar P95 de etapas paralelas. Usar o instrumento de trace já existente; `OSSignposter`/Instruments é opção para perfis temporais iOS.

**Decisão a partir de dados:** comparar consumo restante estimado (idealmente distância visual + taxa observada, sob incerteza) com latência e2e suficiente para uma reposição. Examinar suavização (EWMA) versus máximo de amostras; nenhuma troca sem teste mostrando melhora em bursts e retomada após repouso. Não produzir uma segunda política paralela.

**Teste discriminante:** rede lenta mas bem-sucedida, rede com resposta vazia, fonte suspensa, dados já locais, alta velocidade de scroll, leitor parado, retorno de background; separar **tempo até novas cartas úteis** de tempo bruto de requisição. Acompanhar frames/energia e pressão de armazenamento.

**Status Codex:** HIPÓTESE FORTE; SEM PROVA CAUSAL NA BUILD 55.

## NF-06 — Trabalhos complementares sem novos subsistemas

**[EXPLORATÓRIA]** Inspecionar antes de modificar: `ETag`/`If-None-Match`, `Last-Modified`/`If-Modified-Since`, respostas 304, reuse do conteúdo canônico local, deduplicação de requests, prioridade de aquisição que sustenta a cauda versus enriquecimento oportunista. Não colocar `URLCache` ou novo armazenamento apenas porque é técnica conhecida; verificar o que os conectores já fazem. Respeitar restrições de `BGTaskScheduler` no iOS.

**Status Codex:** NÃO AUTORIZA IMPLEMENTAÇÃO SEM DIAGNÓSTICO.

## 3. Protocolo de correção pelo Codex

**Instrução explícita ao Codex:** você está autorizado e convidado a discordar deste documento. Faça a revisão **no próprio arquivo**, atualize os trechos refutados e registre uma entrada no histórico abaixo. Não crie um segundo plano rival ou um relatório que obrigue o dono a reconciliar verdades conflitantes.

1. **Fixar a árvore real.** Preencher commit da build 55, HEAD examinado, data, origem da evidência e diferenças relevantes com 54. Dizer quando não houver acesso ao binário/código exato.
2. **Auditar cada frente.** Marcar `CONFIRMADA`, `PARCIAL`, `REFUTADA` ou `INCONCLUSIVA`; fornecer `arquivo:linha`, teste/log/fixture e a explicação de causalidade. Leitura de código não substitui reprodução.
3. **Corrigir afirmações e prioridades.** Se uma hipótese estiver errada, corrigir o texto principal e explicar a contraprova no histórico. Se duas frentes forem o mesmo problema, consolidar; se uma solução introduzir complexidade que não compra invariantes, rejeitá-la.
4. **Propor mudança mínima no owner real.** Apresentar alternativa A (mínima), riscos, efeitos colaterais e motivo para não escolher uma reescrita. Não adicionar estado, fila, timer, cache ou retry sem necessidade comprovada.
5. **Definir prova antes do patch.** Preferir teste vermelho discriminante e jornada que impeçam falsos verdes. Separar medições de simulator, Release e dispositivo físico; `B06` depende do aparelho.
6. **Atualizar conforme progride.** Para cada frente, manter estado, SHA da mudança, experimento, resultado observado, regressões, custo e próxima ação. Não escrever `PASS` baseado apenas em compilação ou leitura.
7. **Preservar direção de produto.** A rolagem hoje fluida não deve retroceder; o feed não pode terminar artificialmente; filtros não podem fingir confirmação; espera não pode prometer o que o backend não sabe.

### Registro operacional — Codex deve preencher

| Data | Frente | Commit/build investigado | Veredito | Evidência (arquivo:linha, teste/trace) | Mudança proposta ou realizada | Estado |
|---|---|---|---|---|---|---|
| 2026-10-23 | NF-01…NF-06 | Código de referência `3eee193`; relato TestFlight 55 | Diagnóstico inicial, **não** validação 55 | Ver seções acima | Pesquisa/hipóteses; nenhum patch de runtime | ABERTO |

### Histórico de revisões

- **2026-10-23 — v0.1:** primeira versão. Consolidado o relato da build 55, as evidências lidas da build 54, alternativas técnicas e perguntas adversariais. Criado espaço explícito para refutação pelo Codex.
- **Próxima entrada:** Codex: proveniência da 55 e revisão/refutação das frentes, com referências.

## 4. Leituras e artefatos que devem prevalecer

**No repositório:**

- `docs/product/PRODUCT_NORTH_STAR.md` — experiência de descoberta, continuidade local-first e capacidade adaptativa.
- `docs/product/PRODUCT_DECISIONS_2026-10-09.md` — decisões de produto; verificar emendas posteriores.
- `docs/architecture/PRODUCT_INVARIANTS.md` e `docs/architecture/CONTINUOUS_FEED_RUNWAY_DESIGN.md`.
- `docs/reviews/R1_EDITORIAL_DIAGNOSIS.md` — diagnóstico histórico de diversidade V1/V2, **não** evidência de regressão da 55.
- `docs/reviews/CODE_REVIEW_build54_2026-10-22.md` na branch `kiro/review-build54` — revisão adversarial de 54 e achado do candidato não-ready.
- `docs/reviews/2026-10-18-v2-execucao-pos-build53.md` — evidências e limitações em uma árvore anterior.
- `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md`, `docs/evidence/ACCEPTANCE_RECORD.md` e `bench/` — consultar sem editar a régua congelada.

**Referências técnicas para verificar, não copiar cegamente:** buffering preditivo (ex.: AVPlayer), fairness/Deficit Round Robin, diversificação MMR, observabilidade com Instruments/OSSignposter e princípios de status visível do Nielsen Norman Group. Sua aplicabilidade **não equivale a prova** no FeedMine; buscar documentação primária e comparar custos e restrições antes de implementar.

---

**Regra final deste documento:** uma correção vale quando melhora a jornada real do leitor sem comprometer as invariantes do produto. O Codex deve nos corrigir sempre que a evidência pedir — inclusive se a correção for remover uma sugestão deste arquivo.
