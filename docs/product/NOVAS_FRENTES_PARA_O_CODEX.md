# Novas frentes para o Codex — FeedMine V2

**Estado:** ABERTO — documento vivo de investigação, implementação e contraditório técnico  
**Iniciado em:** 2026-10-23  
**Dono da priorização:** produto/arquitetura FeedMine  
**Contribuidores esperados:** Codex, revisores independentes e testes em dispositivo  
**Escopo:** relato da build 55, continuidade do runtime, **paridade V1→V2** e **visão de FeedMine como interface multimídia contínua da internet aberta**  
**Próxima revisão:** pelo Codex, após identificar a build 55, auditar NF-07–NF-12 e investigar/contradizer NF-13–NF-16, inclusive políticas reais de terceiros

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

## 0.1. Ampliação de mandato — revisão de 2026-10-23

**Nova direção explícita do dono:** os sintomas da build 55 são exemplos, não os limites do diagnóstico. O Codex deve investigar o **produto inteiro**, inclusive superfícies que ainda não foram exercitadas no TestFlight. O padrão é comparar jornadas reais da V1 e V2, consultar as especificações/experimentos da V1, ler o código das duas versões, entender as decisões atuais e devolver propostas corrigíveis no documento.

**Nova regra transversal (proposta de produto a testar):** toda interação visível — toque, mudança de controle, navegação, arraste, confirmação, play/pause, bookmark, salvar, importar, aplicar filtros, buscar, abrir artigo — **precisa responder visualmente no próprio ciclo de interação**, independentemente de trabalho de disco/rede/seleção/preparação. Operações longas devem ser comandadas assincronamente pelo owner competente, com espera e estado de resultado honestos quando fizerem sentido. **Não** mostrar tela modal de espera para toda ação, nem usar animação de “sucesso” antes de commit durável. Local e UI podem atualizar estado visual sincronicamente; não é necessário criar `Task` artificial para toda mutação trivial. Veja NF-07 (autoridade transversal) e NF-03 (caso de regressão nos filtros).

**Patrimônio V1:** `wsmontes/feedmine-dev`, sua árvore `docs/superpowers/specs/` e `docs/superpowers/plans/`, além de código em `feedmine/Views/`, `feedmine/Services/` e `feedmine/Models/`. O repositório V2 contém `docs/v1-study/` e especificações F01–F27, já documentando várias diferenças. **Essas fontes são material obrigatório de revisão, não ordens para portar mecanicamente bugs, duplicações e timers antigos.**

**Lacuna-chave:** vídeo/YouTube não apareceu ao leitor na build 55; podcast tem comparação desfavorável com a V1; artigos eram mais agradáveis de abrir/fechar na V1; e a V2 ainda não transmite uma linguagem de design suficientemente consistente. **Visão ampliada em 23/10:** vídeo inline→flutuante, leitura simultânea, podcast em áudio prioritário e futura web rádio, sem substituir a página original dos publicadores. Não confundir presença de classes e badges com funcionalidade real de descoberta, publicação e consumo.

## 0.2. Novo norte de produto: interface multimídia contínua da internet aberta

**[DIREÇÃO EXPLÍCITA DO DONO, 2026-10-23]** FeedMine não deve ser apenas um leitor de resumos ou uma fila de links. É uma **interface multimídia de feed infinito** para conteúdos vivos da internet aberta. A pessoa pode consumir diferentes formatos de maneira concomitante: assistir a vídeo, ouvir um podcast/rádio e continuar descobrindo ou lendo páginas. O trabalho de descoberta e preparação existe para sustentar essa liberdade, não para reconstruir ou substituir a experiência dos publicadores.

- **Vídeo:** um vídeo iniciado conscientemente no card deve poder continuar em uma janela flutuante **visível** quando o card sai da viewport. A pessoa continua rolando, abre outros cards ou artigos e pode voltar ao vídeo sem reiniciar, quando a plataforma e a fonte permitirem.
- **Áudio:** quando a pessoa inicia um podcast durante a exibição de vídeo, o vídeo deve preferencialmente permanecer visível **mudo** e o podcast assumir a função de áudio principal. A futura web rádio obedece à mesma coordenação. Não presumir que várias fontes sonoras devam tocar simultaneamente por padrão.
- **Web original primeiro:** tocar artigo/blog abre **por padrão a página real do publicador**, com seus recursos, links, apresentação e publicidade; leitura simplificada/sem distrações é **uma escolha explícita do usuário**, não a transformação automática de todo conteúdo. Preservar origem e monetização, sem afirmar que toda renderização de RSS offline equivale a scraping.
- **Navegação separada da reprodução:** abrir/fechar artigos, trocar filtros, navegar no feed e voltar de uma folha não deve destruir uma reprodução já iniciada. Sempre oferecer controles óbvios para pausar, silenciar, fechar e escolher o áudio, com comportamento honesto quando a fonte não permitir coexistência.
- **Tudo subordinado à fluidez:** a reprodução não pode reintroduzir I/O, decoder ou trabalho de rede no gesto de scroll, nem iniciar automaticamente múltiplos players remotos num feed com milhares de cards.
- **Plataformas e direitos importam:** implementar somente as modalidades e combinações permitidas por YouTube/iOS/publicadores. Quando uma interação não puder ser oferecida, comunicar a limitação e usar alternativa fiel (abrir a fonte, pausar ou manter o áudio), sem burlá-la.

Esta visão **altera a prioridade e o contrato de abertura**, mas **não certifica** que YouTube PiP, vídeo sobre artigos nem vídeo+música sejam factíveis em toda origem ou hardware. As NF-13–NF-16 são provas e decisões pendentes.

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
10. **UI responsiva em qualquer superfície:** evento de interface recebe reconhecimento síncrono e barato; eventual comando de domínio assíncrono não ocupa o MainActor nem bloqueia o gesto. Dar feedback de *em processamento*, *salvo*, *ativado* ou *falhou* conforme evidência verdadeira, sem spinner obrigatório universal, sem tela de espera que destrua o contexto.
11. **Paridade de experiência V1→V2:** trazer os comportamentos úteis (visual, navegação, fontes, podcasts, vídeo) sem ressuscitar arquiteturas concorrentes; uma mudança de tecnologia precisa justificar qualquer perda de UX.
12. **Variedade é multidimensional e audiovisual:** prover descoberta por provedor, assunto, geografia, idioma, gênero, tipo de mídia, temporalidade e fontes desconhecidas, preservando relevância e controles explícitos, desde que haja oferta elegível.
13. **Coexistência com um só dono por modalidade:** cards são apresentação descartável; reprodução iniciada é sessão durável enquanto o usuário quiser e a origem permitir. Coordenar áudio/vídeo no host e composição existentes, não recriar players por célula.
14. **Conteúdo de origem como primeiro destino:** preferir navegação real do publicador e preservar anúncios/links/identidade; abstrações locais são alternativas explícitas, fallback offline ou material de preview corretamente identificado.
15. **Hierarquia documental:** este backlog é subordinado a `docs/product/PRODUCT_NORTH_STAR.md`, `docs/product/PRODUCT_DECISIONS_2026-10-09.md`, `docs/architecture/PRODUCT_INVARIANTS.md`, decisões posteriores aplicáveis e especificações de release.

## 2. Mapa de frentes

| ID | Prioridade inicial | Sintoma / objetivo | Estado inicial |
|---|---|---|---|
| NF-01 | **P0** | Runway acaba antes da chegada de cards novos | Aberta; investigar causa dominante |
| NF-02 | **P1** | Mistura de fontes, provedores e assuntos não parece diversa | Aberta; caracterizar oferta versus sequenciamento |
| NF-03 | **P1** | Concluído dos filtros só reage depois de operação longa | Caminho bloqueante confirmado no código 54; 55 pendente |
| NF-04 | **P1** | Espera e fim do feed têm mensagens ambíguas | Semântica e apresentação divergentes no código 54; 55 pendente |
| NF-05 | **P0, habilitadora de NF-01** | Métrica de reposição não representa toda a jornada | Hipótese estrutural, requer instrumentação |
| NF-06 | **P2, exploratória** | Aproveitamento de rede, cache HTTP e prioridade de trabalho | Inventariar antes de alterar |
| NF-07 | **P0, transversal** | Toda superfície reconhece comandos imediatamente; trabalho longo é assíncrono | **Nova**; varrer o app inteiro |
| NF-08 | **P1, transversal** | Identidade visual/glass da V1, botões, componentes e design system da V2 | **Nova**; auditoria V1/V2 |
| NF-09 | **P1** | Variedade editorial e de formatos com conhecimento V1 + código aberto Twitter/X | **Nova**; estudo comparativo com replay |
| NF-10 | **P1** | Abrir artigos/blogs e voltar com gesto natural, preservando o feed | **Nova**; comparar reader da V1 com o host V2 |
| NF-11 | **P1** | Podcasts: descoberta, reprodução, controles, continuidade e retorno | **Nova**; paridade funcional com V1 |
| NF-12 | **P1** | YouTube/vídeos: não aparecem no TestFlight; cadeia completa e jornada de teste | Aberta; diagnóstico de disponibilidade + consumo |
| NF-13 | **P1, prova técnica** | Vídeo iniciado no card → janela flutuante persistente → retorno inline | **Nova**; elegibilidade iOS/YouTube e protótipo real |
| NF-14 | **P1, contrato de experiência** | Podcast/rádio como áudio principal; vídeo pode permanecer mudo e visível | **Nova**; arbitragem entre modalidades sem dois owners |
| NF-15 | **P0 de direção / P1 de execução** | Artigos e blogs abrem o site original por padrão; modo leitura é opt-in | **Nova**; rever política de FeedReadingDecision e leitor |
| NF-16 | **Direção transversal** | Multimídia contínua: conteúdo vivo, navegação e playback independentes | **Nova**; decisões de produto e teste integrado |

**Ordenação de execução sugerida:** NF-05/NF-01 em conjunto; estabelecer NF-07 como contrato e auditar primeiro NF-03; em seguida NF-04, NF-10/NF-12 (jornadas visíveis ausentes), NF-08 (auditoria de design), NF-02/NF-09 (corpus e algoritmos) e NF-11/NF-13–NF-16 (multimídia, navegação e áudio). Isso **não** congela a priorização: comparar o custo, impacto e riscos reais antes de alocar workers. O Codex pode propor outra ordem com evidência.

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

## NF-03 — Concluído dos filtros: caso discriminante da regra global NF-07

**[DISPOSITIVO]** O botão de confirmação demora a agir. **Este é apenas um caso da exigência global NF-07; não basta corrigir o botão Concluído e declarar a experiência responsiva.**

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
| 2026-10-23 | NF-07…NF-12 | `feedmine-dev/main`, documentos V1 e V2; referência 54 | Mandato expandido pelo dono; **sem prova de paridade em aparelho** | Seções novas + inventário V1/V2 | Criar matriz transversal e contraditório; nenhum patch de runtime | ABERTO |
| 2026-10-23 | NF-13…NF-16 | V1 ArticleReaderView + V2 Reader/Media 54; documentação Apple/YouTube | Nova visão de produto; **viabilidade parcial, não comprovada integralmente** | Seções novas e regras de cada plataforma | Prototipar e validar antes de assumir PiP/overlays | ABERTO |

### Histórico de revisões

- **2026-10-23 — v0.1:** primeira versão. Consolidado o relato da build 55, as evidências lidas da build 54, alternativas técnicas e perguntas adversariais. Criado espaço explícito para refutação pelo Codex.
- **2026-10-23 — v0.2:** ampliado de incidentes de build para auditoria transversal de produto; regra universal de feedback imediato, design/glass da V1, variedade e pesquisas Twitter/X, leitor por gesto, paridade de podcasts e descoberta/consumo YouTube.
- **2026-10-23 — v0.3:** novo norte de interface multimídia contínua; vídeo inline→flutuante, coordenação com podcast/rádio, leitura do publicador original por padrão e modo leitura opt-in. NF-13–NF-16 com limites de YouTube/iOS e provas físicas, sem patches de runtime. Acrescentadas NF-07–NF-12 com evidências de V1 e limites de prova da V2.
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



## NF-07 — Contrato transversal de resposta imediata para TODA interação

**[REQUISITO DO DONO]** Nenhuma interação de UI pode esperar processamento para **reconhecer** a ação. Toda operação potencialmente lenta é comandada para execução assíncrona, fora do caminho síncrono do gesto; a interface acompanha estados reais e usa uma apresentação de processamento **quando necessária**. A NF-03 é apenas um sintoma.

**[PESQUISA EXTERNA]** Apple, *Explore concurrency in SwiftUI* (WWDC25): callbacks de ação SwiftUI são síncronos para mudanças visuais imediatas; manter lógica pesada separada. Apple, *Improving app responsiveness*: `Task` criado na View pode herdar `MainActor`, portanto `Task { ... }` não prova que computação pesada saiu da thread principal. Fontes: <https://developer.apple.com/videos/play/wwdc2025/266/> e <https://developer.apple.com/documentation/xcode/improving-app-responsiveness>.

**[ALTERNATIVA DE CONTRATO, sujeito a correção do Codex]**

1. **Evento → resposta visível síncrona:** estado de pressionado/selecionado, abertura da folha, foco, feedback háptico apropriado ou estado “salvando”, conforme semântica da ação.
2. **Comando → owner existente:** UI emite intenção/valor identificável; disco, banco, rede, aquisição, reconstrução, parsing e processamento executam sem bloquear renderização ou gestures, respeitando isolamento de Swift/Swift 6. Não basta envolver trabalho pesado `@MainActor` em `Task`.
3. **Resultado diferenciado:** reconhecer toque ≠ declarar operação concluída; `pending`, `committed`, `presented`, `failed` só aparecem onde são necessários e verdadeiros. Persistência crítica falhou → não mostrar confirmação de sucesso.
4. **Espera contextual:** indicador discreto na superfície para operação que permite interação contínua; tela de progresso somente quando realmente inevitável; nunca prender o leitor num spinner sem cancelamento/saída quando houver alternativa segura. Em processamento lento, mostrar *o que* está acontecendo; não inventar porcentagem.
5. **Sobreposição e obsolescência:** taps repetidos, navegação durante processamento, A→B→A, cancelamento e retorno de background têm semântica definida; resultados superados não assumem o contexto novo.
6. **Geometria estável:** feedback, banners, placeholders e barras de espera não deslocam a âncora do feed nem bloqueiam controles já presentes.
7. **Acessibilidade:** VoiceOver anuncia estados relevantes; Dynamic Type, Reduce Motion, alto contraste, hit targets e `accessibilityIdentifier` não são prejudicados.

**[AUDITORIA EXIGIDA]** Criar matriz por **superfície + interação** (não apenas por View), incluindo: primeiro uso, feed, header e menus, abrir card, artigos e retorno, filtro, busca, presets, biblioteca, bookmark, coleções, fontes, ajustes/toggles, importar/exportar, compartilhar, podcast, vídeo, erros/retry e navegação entre abas/sheets. Para cada gesto: `evento → resposta visível imediata → comando/owner → sinal de processamento → commit/efeito → erro/cancelamento → retorno`. Distinguir ações reversíveis e irreversíveis, e preferência durável de alteração de apresentação.

**[CÓDIGO A CONSULTAR]** `FeedMineApp/FeedMineApp/FeedMineApp.swift`, `AppComposition.swift`, `Sources/FeedMineUI/Reader/*`, `Filters/*`, `Settings/*`, `Bookmarks/*`, `Collections/*`, `Sources/*`, `Cards/*`, `Sources/FeedMineUI/Feedback/*`. No código 54, NF-03 apresenta um `await replaceSession()` no caminho de confirmação visual.

**[PROVA]** Testes por ação injetando I/O **suspenso** no owner relevante e verificando que o feedback visual e a navegação permitida ocorrem antes da liberação; depois liberar e verificar sucesso/fracasso correto. Instrumentar toque→primeiro frame útil no aparelho e detectar bloqueios `MainActor`; teste de ausência de salto/scroll, VoiceOver e dupla interação. Não passar o teste apenas com ambiente local tão rápido que esconda a dependência.

**[REJEITAR]** “Resolver” com um overlay modal em todos os taps, um `Task` que continua pesado no MainActor, otimização artificial do banco ou confirmação otimista de escrita durável não concluída.

**Status Codex:** NOVA FRENTE TRANSVERSAL; NÃO AUDITADA.

## NF-08 — Identidade visual V1→V2, glass e biblioteca coerente de controles

**[DISPOSITIVO / DIREÇÃO DO DONO]** A V1 transmitia linguagem *glass*; a V2 não entrega a mesma impressão e seus botões parecem inconsistentes ou fora de padrão.

**[FATOS DE CÓDIGO/DOCUMENTO, não um julgamento de aparência final]**

- V1: `feedmine/Views/FeedScreen.swift` usa `.ultraThinMaterial` no mini-player, header e controles de busca; `feedmine/Views/ArticleReaderView.swift` usa material translúcido no chrome; `FeedItemCardView.swift` usa material em controles sobre imagem.
- V1: `feedmine/Services/DesignTokens.swift` tem cores OKLCH, papéis semânticos e tokens de componentes. A V1 documenta identidade visual em `docs/superpowers/specs/2026-07-04-circadian-design-system.md` e design de cards em `2026-07-04-moment-card-design.md`.
- V2: `Sources/FeedMineUI/FeedDesignTokens.swift` já é **única autoridade de tokens**; `Reader/ReaderHeader.swift` já reproduz botão circular 44×44 e `.ultraThinMaterial`; `Media/MiniPlayerBar.swift` também usa material. Logo, **não** afirmar que não existe vidro, nem criar um segundo DesignTokens.
- O próprio comentário dos tokens V2 rejeita a oscilação automática de raio, tipografia e geometria por relógio da V1. **Não** portar indiscriminadamente o `CircadianEngine`: sua aparência pode inspirar valores/paletas, mas a transição temporal não pode destruir composição publicada, acessibilidade ou scroll.
- `docs/v1-study/UI_TRANSFER_MATRIX.md`, `05-ui-app-quality.md`, `V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md` e `docs/product/F17_LOCALIZATION_APPEARANCE_ACCESSIBILITY_UX_PRD.md` já documentam contratos e diferenças; a matriz precisa ser atualizada por comportamento real.

**[INVESTIGAR]** Construir inventário visual V1/V2 por superfície, capturas lado a lado com **mesmo cenário** (não snapshots antigos sem contexto): header, botões primários/secundários/destrutivos, icons, menus, filtros, busca, chips, cards e controles de mídia, sheets, alertas, seleção, loading, lista vazia, configurações, onboarding, bibliotecas, leitor de artigo e mini-player. Anotar materiais, elevação, gradientes, sombras, bordas, cantos, hit targets, espaçamento, densidade, hierarquia tipográfica, haptics, estados pressed/disabled/progress/success/fail, transições e consistência.

**[ALTERNATIVA]** Consolidar papéis de componente **dentro** dos tokens V2 existentes e reutilizar estilos coerentes entre superfícies. Manter distinção de conteúdo e chrome; material/glass preferencialmente em navegação e controles, não atrás de texto cuja legibilidade cairia. Reavaliar se glass puramente cosmético compete com estabilidade, desempenho e percepção de mídia.

**[PLATAFORMA]** V1 usa materiais SwiftUI disponíveis no alvo iOS 18. O *Liquid Glass* do iOS 26 é uma evolução da plataforma, **não** sinônimo obrigatório do glass da V1 nem API que se possa aplicar sem disponibilidade/target/teste. Se optar por suporte específico a iOS 26, usar feature availability e comportamento compatível para iOS 18/19. Consultar HIG/SwiftUI atuais, Reduce Transparency, Reduce Motion e VoiceOver.

**[PROVA]** Série de jornadas no aparelho e capturas comparáveis, checagem de acessibilidade/alto contraste/Dynamic Type, identificação de botões sem feedback e hit targets inadequados. Verificar custo de animações e blur nos frames. Critério não é “ficou mais transparente”: é clareza, consistência, ação óbvia, estética intencional e ausência de regressão de scroll.

**Status Codex:** NOVA FRENTE; PARIDADE VISUAL NÃO COMPROVADA.

## NF-09 — Ciência editorial da V1 + lições concretas do código aberto Twitter/X

**[DIREÇÃO DO DONO]** Diversidade não é só alternância de fontes. Recuperar anos de tentativa/erro da V1 sobre mistura de interesses, notícias/evergreen, geografia, idioma, origem editorial, formatos, podcasts e vídeos; aprender com pipelines de produção abertos, sem importar objetivo de engajamento ou arquitetura de servidor.

**[FONTES V1 OBRIGATÓRIAS]**

- `feedmine/Services/FeedStore.swift`: `interleaveImpl`, `interleaveByTypeCategoryImpl`, `spreadForFreshnessImpl`, `frontLoadUniqueProvidersImpl`, versão real desses símbolos a confirmar.
- `feedmine/Services/EditorialSequencer.swift`, `Reservoir.swift`, `CuratedPreferenceEngine.swift`, `FeedRecipeResolver.swift`, `PresetScorer.swift` e facetas do catálogo.
- `docs/product/2026-10-17-interleave-v1-parity-direction.md`: direção vigente para diversidade multidimensional *antes* da publicação, sem reembaralhar histórico.
- `docs/v1-study/04-catalog-editorial.md`, `V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md` (G04) e `docs/reviews/R1_EDITORIAL_DIAGNOSIS.md`: separar sucesso antigo, documentação de intenção e hipóteses novas.

**[FONTES EXTERNAS VERIFICADAS, para estudo de código em profundidade]**

1. <https://github.com/twitter/the-algorithm/blob/main/home-mixer/README.md> — pipeline histórico *candidate generation → feature hydration → scoring/ranking → filtering/heuristics → mixing → serving*, incluindo *author diversity*, *content balance*, deduplicação e itens já vistos. Há também `product-mixer/`. É fonte arquitetural, não especificação do FeedMine.
2. <https://github.com/xai-org/x-algorithm> — implementação pública posterior da família X; `home-mixer/` e `candidate-pipeline/` separam retrieval, hidratação, filtros, ranking, blending; `vm-ranker/` descreve reranking com **determinantal point process** para reduzir similaridade entre vizinhos. O README descreve módulos e objetivos; **o Codex deve ler o código dos módulos relevantes antes de fazer alegações de algoritmo ou propor adaptação**.
3. Respeitar licenças e proveniência; **reaproveitar princípios, não copiar código** sem análise de licença, dependências, custo e compatibilidade com um app local-first.

**[QUESTÕES DE PESQUISA]** O que as fontes abertas ensinam sobre separar *candidate supply*, elegibilidade, ranking e diversidade? Como evitar que poucos provedores dominem o feed mesmo quando a oferta chega assimetricamente? Como balancear formatos/assuntos sem apagar preferências, rotular assuntos inventados ou introduzir um modelo opaco de engajamento? Como aplicar reranking que não degrada novidade, qualidade e explicabilidade? A sequência publicada permanece fixa? Qual estado de exposição é mínimo e já existe?

**[ANTÍ-PADRÕES]** Importar um pesado modelo de embeddings por reflexo; contar tap, salvar ou abertura como “voto” implícito (contrato F02); regular o feed por métricas artificiais que forçam monotonia; confundir descoberta de conteúdo de fora da rede com trilha dependente de perfis sociais; observar apenas fonte ID sem provedor/editoria/idioma/mídia.

**[PROVA]** Mesmo corpus real da V1/V2, com alternativas e ausência delas, comparar origens, assuntos, geografia, tipo de mídia, temporalidade, redundância visual, frescor, starvation e preferências. Medir da aquisição até o publicado, para distinguir pobreza da oferta de erro de sequenciamento. O teste editorial só é persuasivo se houver leitura exploratória sem roteiro; não transformar um escore numérico em proxy de boa descoberta.

**Status Codex:** NOVA FRENTE DE PESQUISA; ALGORITMOS TWITTER/X AINDA NÃO REVISADOS LINHA A LINHA.

## NF-10 — Abrir e fechar artigos/blogs com UX da V1 (ver nova decisão NF-15)

**[DISPOSITIVO / DIREÇÃO]** A V1 abre artigo/blog numa superfície acima do feed que a pessoa pode dispensar deslizando, naturalmente; o fluxo atual da V2 é percebido como pior.

**[V1 — código e especificação]** `wsmontes/feedmine-dev/feedmine/Views/ArticleReaderView.swift` usa `WKWebView` com progresso, fechamento explícito, ação externa de Safari e material translúcido. `feedmine/Views/FeedScreen.swift` apresenta `.sheet(item: $articleItem)`. Contrato do documento V1 `docs/superpowers/specs/2026-07-01-in-app-reader-design.md`: **toque no card → sheet com conteúdo web real → deslizar para baixo e voltar ao feed**, sem tela intermediária.

**[V2 — código da referência 54]** `FeedMineApp/FeedMineApp/InAppBrowser.swift` usa `SFSafariViewController`; `FeedMineApp.swift` mantém uma pilha tipada de superfícies e a lógica `pushReader`/`finishReader`; `Sources/FeedMineUI/Reader/FeedReadingSurface.swift` oferece leitura local, com abertura opcional do site. A F14 (`docs/product/F14_READER_LINK_NAVIGATION_UX_PRD.md`) registra explicitamente troca de WKWebView por SafariServices como **decisão anterior aceita**, mas **não** como prova de jornada de abrir/deslizar/voltar.

**[INVESTIGAR ANTES DE DECIDIR]** Comparar a apresentação real das duas versões: swipe-down interativo, close/voltar, conteúdo carregando, progresso, gestos dentro de WebView, links aninhados, Safari externo, share, erro/paywall, cookies/segurança e retorno com âncora e filtros intactos. Separar **tecnologia do navegador** da **experiência do container**: `SFSafariViewController` não é, por si, justificativa para perder um gesto natural. Reavaliar a decisão U2/F14 com evidência e impacto técnico se for preciso alterá-la, sem decidir automaticamente “voltar ao WKWebView”.

**[PROVA]** Card de blog real → abrir sem tela intermediária → ler/navegar → fechar por gesto **e** por controle → mesmo card/posição/estado da superfície que iniciou. Repetir para reader interno, site indisponível, site com mídia e artigo aberto a partir de uma lista salva. Se swipe-down exigir arranjo especial, testar conflitos com scroll vertical da página.

**Status Codex:** PARIDADE COMPORTAMENTAL NÃO COMPROVADA NA V2; TESTAR NO APARELHO. **NF-15 substitui a premissa de leitura local automática para artigo com URL válida; o Codex deve revisar F14/U-reading, sem descartar acesso offline a dados legítimos.**

## NF-11 — Podcasts: experiência completa, da descoberta à retomada

**[DIREÇÃO DO DONO]** A V1 entrega uma experiência de podcast mais avançada que a percebida na V2.

**[FATOS V1]** `feedmine/Services/AudioPlayerManager.swift` emprega `AVPlayer`, sessão de áudio, posição salva, interrupções/rotas e comandos de mídia; `feedmine/Views/MiniPlayerBar.swift` traz mini/full player, seek ±15 segundos e scrub. A V1 também tem pesquisa de fontes de podcasts em `docs/superpowers/specs/2026-07-08-national-podcast-youtube-discovery-design.md`, que relata um experimento Bolívia bem-sucedido para podcasts **naquela árvore e cenário** (não prova cobertura global atual).

**[FATOS V2-54]** `Sources/FeedMineUI/Media/MiniPlayerBar.swift` já oferece mini/full player e controles; `FeedMineApp/FeedMineApp/MediaPlaybackAdapter.swift` implementa ponte de playback; `docs/product/F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md` registra cobertura parcial e **NOT_RUN** para jornada UX15 integral. Logo, não afirmar que podcast foi inteiramente omitido nem que há paridade.

**[AUDITORIA DE PONTA A PONTA]** Quais feeds realmente geram episódios elegíveis? Enclosure/URL/identidade/artwork são preservados? Card expõe controle de play na geometria pronta? Mini-player abre sem interromper scroll? Play/pause/scrub/±15, estado de buffering, erros de URL, AirPlay/controles remotos, troca de fone, interrupção, background, relançamento e retomada de episódio/posição funcionam? A interface guarda consistência entre bar e player expandido? A navegação artigo→feed interfere no áudio?

**[PROVA]** Jornada real com episódio e URL verificáveis, mais fixture offline para o card; play → navegar pelo feed → abrir artigo → background/interrupção → retomar → relançar e recuperar episódio/posição. Capturar `NOT_RUN` explicitamente em casos sem aparelho ou sem sessão válida. Não baixar episódio completo só para admitir card; o play é uma ação explícita.

**Status Codex:** COMPONENTES PRESENTES; PARIDADE V1 E LIFECYCLE SEM PROVA NA BUILD 55. **NF-14 complementa com coordenação explícita de áudio em multimídia (vídeo/podcast/rádio).**

## NF-12 — YouTube/vídeo deve existir na experiência, não apenas em enums e badges

**[DISPOSITIVO]** Não apareceram vídeos na V2 do TestFlight para testar. **Isso é um defeito de experiência a investigar, mesmo que o parser ou um badge sejam perfeitos.**

**[FATOS E LIMITES]**

- V1: `feedmine/Models/FeedItem.swift` reconhece URLs YouTube `watch`, `youtu.be`, `shorts`, extrai ID validando domínio e compõe miniatura; `feedmine/Views/FeedItemCardView.swift` distingue badge Video. Isso **não** prova que o player estivesse embutido ou que toda aquisição encontrasse vídeos.
- Estudo V1 `docs/superpowers/specs/2026-07-08-national-podcast-youtube-discovery-design.md`: `youtube.com/feeds/videos.xml?channel_id=...` é Atom válido; descoberta de canal foi implementada mecanicamente, mas **adiada** após um experimento com retorno zero de canais bolivianos sob filtro de nacionalidade estrito. O texto aponta problema do *seed* de descoberta, não ausência de suporte do YouTube como protocolo. A saída de zero daquele cenário não deve ser extrapolada para todos os países.
- V2 referência 54: `Sources/FeedMineDomain/MediaCandidate.swift` tem `.video`; `Sources/FeedMineUI/Cards/MediaIdentityBadge.swift` tem label “Vídeo”; `Sources/FeedMineUI/Cards/FeedItemCardView.swift` usa `card.identifiesVideo` para badge. **Um badge possível não é prova** de alimentação real, publicação, player ou presença no feed.
- `docs/product/F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md` é áudio; **não** deduzir suporte a YouTube desta spec.

**[MAPEAR A CADEIA INTEIRA]** (1) fontes YouTube conhecidas no catálogo compilado; (2) URL de feed Atom de canal válido; (3) feed selecionado/descoberto pelo contexto; (4) fetch HTTP com resultados; (5) tradução Atom → origem/revisão/link/media candidate; (6) elegibilidade e filtros de conteúdo/mídia; (7) candidato ready e seleção editorial; (8) card publicado com título/canal/miniatura/badge adequados; (9) destino de consumo verdadeiro — abrir YouTube in-app, externo ou player autorizado — com saída/retorno coerentes; (10) controle e observabilidade. Identificar **a primeira fronteira onde a oferta some**.

**[ALTERNATIVAS A ESTUDAR]** Usar feeds Atom públicos de canais previamente conhecidos (sem chave), descoberta ancorada nas fontes já catalogadas e mapeamento seguro `channel_id` ↔ URL. Examinar limitações de rede, disponibilidade de miniaturas, ToS, embed/webview e direitos; não iniciar autoplay, não adivinhar IDs, não fazer scraping frágil como dependência obrigatória. Decidir contrato de visualização pela experiência e condições permitidas, não simplesmente tratar vídeo como imagem ou podcast.

**[PROVA OBRIGATÓRIA]** Fixture determinística com episódios de vídeo de canais reais e feed Atom, seguida de sessão física/Release com pelo menos um vídeo **efetivamente visível, clicável e consumível**, saída/retorno corretos, sem degradação de scroll nem oferta marcada erroneamente como esgotada. Definir separadamente caso de YouTube indisponível por conectividade/fonte. Fazer teste com seleção ampla e também com filtro de mídia; conteúdo de teste não deve ser uma carta fake que só comprova o badge.

**Status Codex:** AUSÊNCIA OBSERVADA NA BUILD 55; CAUSA NÃO DIAGNOSTICADA. **NF-13 complementa com o experimento de playback inline→flutuante, sujeito aos termos do YouTube.**

## 5. Método de auditoria V1→V2 para as novas frentes

O Codex deve usar esta **matriz preenchível** (uma linha por jornada, não por existência de classe) e expandi-la sem duplicar `UI_TRANSFER_MATRIX.md`:

| Jornada | Fonte/contrato V1 | Código/UX V2 atual | Teste físico 55 | Lacuna atribuída a | Veredito/próxima ação |
|---|---|---|---|---|---|
| Qualquer toque com I/O suspenso | V1 e Apple SwiftUI | Auditar comandos nas superfícies V2 | NÃO MEDIDO | owner do gesto / MainActor / espera do backend | NF-07 |
| Controles/glass/consistência | DesignTokens, circadian design, views V1 | FeedDesignTokens, ReaderHeader, cada superfície | RELATO: INCONSISTENTE | design system / implementação | NF-08 |
| Sequência de fontes/formatos | Interleave, EditorialSequencer, Reservoir, estudos V1 | SelectionEngine, SourceAlternation, descoberta | RELATO: VARIEDADE RUIM | oferta / elegibilidade / sequenciamento | NF-02/NF-09 |
| Blog → swipe-down → mesmo feed | ArticleReaderView + spec 2026-07-01 | InAppBrowser + ReaderPage host + F14 | RELATO: EXPERIÊNCIA PIOR | container/gesto/reader | NF-10 |
| Podcast → background → retomada | AudioPlayerManager + MiniPlayerBar | MediaPlaybackAdapter + Mini/Full + F15 | A TESTAR | descoberta / player / posição / lifecycle | NF-11 |
| YouTube Atom → card → vídeo | FeedItem URL/thumbnail; descoberta adiada | MediaCandidate.video + badge | NÃO APARECEU | catálogo→rede→parser→editorial→UI→consumo | NF-12 |
| Vídeo inline → fora da viewport → flutuante → retorno | Revisar estudo alegado pela V1; nenhum spec de PiP identificado nesta leitura | Card isAudio + identifiesVideo; nenhum player YouTube verificado | NÃO TESTADO | ciclo de vida do player / YouTube e iOS | NF-13 |
| Vídeo mudo + podcast audível + artigo/scroll | V1 AudioPlayerManager / mini-player | MediaPlaybackAdapter / host | NÃO TESTADO | prioridades de áudio / superfície | NF-14/NF-16 |
| Artigo abre site original por padrão | V1 ArticleReaderView WKWebView | FeedReadingDecision prioriza local em certos casos | REGRA NOVA | decisão de leitura | NF-15 |

**Regras da matriz:** marcar `V1: código`, `V1: spec`, `V1: medido` separadamente; registrar **data + SHA** para ambos os repos e **build física**; mostrar por que o caminho final é melhor, igual ou inferior. Componentes presentes nunca bastam para PASS. Decisão V1→V2 anterior não é imutável quando o aparelho revela regressão, mas sua substituição deve ser fundamentada e registrada. Não criar mais de uma fonte da verdade de runtime para viabilizar a auditoria.



## NF-13 — Vídeo no card que acompanha o leitor em janela flutuante

**[DIREÇÃO DO DONO]** A pessoa dá play em um vídeo no card. Enquanto ele está à vista, o vídeo ocupa o card como numa página web. Ao rolar até o card sair da viewport, **o mesmo vídeo** segue num miniplayer flutuante; pode continuar vendo outras cartas, abrir um blog e retornar. Ao voltar ao card, o player pode voltar à posição inline, sem perder o tempo de reprodução.

**[FATOS DE PLATAFORMA, confirmados em fontes primárias em 2026-10-23]**

- YouTube: [IFrame Player API](https://developers.google.com/youtube/iframe_api_reference) permite player incorporado, `playsinline=1`, `playVideo/pauseVideo/mute/unMute`; [parâmetros](https://developers.google.com/youtube/player_parameters). **Não é um arquivo AVPlayer que possamos baixar/decodificar arbitrariamente.**
- YouTube: [Required Minimum Functionality](https://developers.google.com/youtube/terms/required-minimum-functionality) exige viewport **mínimo 200×200**, controles suficientemente legíveis, Referer/identidade do cliente num WebView, sem cobrir qualquer parte do player/controles, e proíbe autoplay fora da visibilidade elegível ou múltiplos players YouTube simultaneamente em autoplay. O mínimo de 200×200 significa que um “mini-player 16:9” de 180×101 **não** cumpre essa regra; testar ergonomia real no iPhone.
- YouTube: [Developer Policies](https://developers.google.com/youtube/terms/developer-policies), [compliance guide](https://developers.google.com/youtube/terms/developer-policies-guide) proíbem player escondido/em background fora da tela vista, separação de faixas e modificação de anúncios. **Um player flutuante verdadeiramente visível dentro do FeedMine é uma hipótese de uso incorporado a verificar; PiP do sistema para YouTube não está automaticamente autorizado/garantido.** Não tratar “minimizado, mas rodando em outro lugar” como permitido.
- Apple: [AVKit/PiP](https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-standard-player) é mecanismo real para vídeo que o app controla via AVPlayer; **isso não transforma um iframe YouTube num AVPlayer**. [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) é host permitido para embed e precisa ser testado no dispositivo.
- Apple: [SFSafariViewController](https://developer.apple.com/documentation/safariservices/sfsafariviewcontroller/) **não pode ser escondido/obscurecido** por overlays arbitrários. Assim o miniplayer acima de artigos não será automaticamente viável com o leitor externo atual, mesmo se funcionar no feed.

**[ALTERNATIVA ARQUITETURAL CANDIDATA]** Video player é uma **sessão com identidade própria no host** (mídia escolhida, estado/tempo, origem, volume, término), não uma `WKWebView` filha de uma célula `LazyVStack` que é desmontada com scroll. O card publicado mantém conteúdo/geometry imutáveis e apenas oferece o *slot* inline e o comando de play. O host pode alternar **apresentação** da mesma sessão entre o slot inline e a área flutuante. Verificar primeiro se reparenting/mudança de constraints de WKWebView interrompe o iframe; possivelmente é melhor manter instância única em camada estável e alterar apenas sua posição, sem recriar view nem iniciar segunda sessão. Evitar dois players simultâneos/duplicação de áudio por mudança de layout.

**[UX A DECIDIR]** Transição pela visibilidade comprovada da viewport (evento, sem polling periódico); modo flutuante somente se houve play **voluntário**; não cobrir botões, legendas, menus ou anúncios; arrastar/recolher/fechar com gestos acessíveis e dimensões conformes; silenciar/retomar áudio; política de interação quando abre artigo, filtro ou sheet; o vídeo continua quando a tela está bloqueada? **YouTube: não presumir que sim.** Não aceitar reprodução sem player visível conforme política. Fluxo mantém âncora e a fluidez do feed.

**[PROVA BLOQUEANTE]** Protótipo com player YouTube **oficial** e iPhone físico: origem/referrer corretos, primeiro play inline, saída da viewport e dock visível, preservação de tempo e stream, retorno ao slot, troca de rota e artigo real aberto em reader compatível, controles/anúncios intactos, reconexão e vídeo sem embed permitido. Medir frames, GPU, memória, rede, bateria e interações. **Não** declarar PASS apenas porque um MP4 próprio funciona no AVKit PiP. Pedir revisão de compliance a YouTube caso a modalidade flutuante gere ambiguidade.

**[DOCUMENTO A RECUPERAR]** O dono recorda estudo anterior sobre **vídeo dentro do card**. Esta rodada verificou specs V1 (`docs/superpowers/specs/`), estudo `2026-07-08-national-podcast-youtube-discovery-design.md` e código de cards, mas **ainda não encontrou um documento específico comprovando player YouTube inline**. Codex deve buscar em `feedmine-dev` branches, histórico, outros documentos e PRs e registrar o link/SHA real; **não inventar que já está pronto**.

**Status Codex:** REQUISITO DE UX + VIABILIDADE TÉCNICA PARCIAL; PROVA DE YOUTUBE FLUTUANTE PENDENTE.

## NF-14 — Áudio prioritário e coexistência de vídeo, podcast e rádio

**[DIREÇÃO]** Ao tocar podcast enquanto vê vídeo, o podcast começa a tocar e **o vídeo continua visível e mudo**. O usuário pode continuar rolando e abrir artigos. Mais tarde, o mesmo princípio deve funcionar com web rádio.

**[SUPORTE CONFIRMADO E LIMITES]**

- [YouTube IFrame API](https://developers.google.com/youtube/iframe_api_reference) documenta `mute()`, `unMute()`, `isMuted()`: silenciar o **player oficial** é diferente de extrair ou manipular a faixa de áudio.
- Apple `AVAudioSession` tem [mixWithOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers) e regras de [duckOthers](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/duckothers), mas essas opções descrevem mistura/interrupção de **sessões de áudio**, não garantem que duas fontes distintas no mesmo app se misturem como queremos. Não usar ducking contínuo inadequado para simular prioridade de podcast.
- V2 `FeedMineApp/FeedMineApp/MediaPlaybackAdapter.swift` tem AVPlayer e sessão `.playback`/`.spokenAudio`; áudio de vídeo YouTube via WebKit é outro mecanismo, a validar em hardware.
- Regras do YouTube proíbem separação/extração de faixas e background escondido, não um controle de mute documentado em si. **Se coexistência exigir burlar player ou mantê-lo escondido, essa modalidade não será implementada assim.**

**[POLÍTICA PROPOSTA PARA DECISÃO]** **Uma fonte sonora principal de cada vez**, coexistindo com **até um vídeo visível**. Vídeo com som → o usuário inicia podcast → pedir ao player YouTube mute por API; iniciar podcast; o vídeo continua reproduzindo imagem **se permitido e visível**. Podcast → rádio: rádio substitui áudio principal e podcast pausa (ou vice-versa), com escolha explícita. Ao parar podcast, o vídeo **permanece mudo até o usuário pedir som**, evitando explosão súbita de volume. Ao pedir unmute com podcast tocando, oferecer transição clara de áudio principal (por exemplo, pausar podcast) em vez de mixar vozes sem consentimento. Registrar preferência somente se for pedido pelo usuário; não inferir intenção por autoplay.

**[OWNER]** A composição/host atual coordena intenção/seleção entre modalidades. `MediaPlaybackAdapter` continua owner de áudio nativo; vídeo web mantém sua própria instância técnica quando necessário; um único contrato mínimo de foco de áudio coordena ambos. **Não** criar três schedulers ou states paralelos. Separar `displayPosition` de `playbackSession`, sem transformar `PresentationCard` em objeto mutável de mídia.

**[PROVA]** Vídeo com áudio → tocar podcast (vídeo visivelmente continua, som de YouTube cessa, podcast audível) → abrir blog original → rolar → pausar podcast → nenhum unmute surpresa → retomar vídeo com som explicitamente. Interrupção telefônica, Bluetooth, AirPlay, fones desconectados, baixo consumo e rede restrita; vídeo incompatível pode pausar com aviso. Validar com player YouTube real e com stream próprio separadamente.

**Status Codex:** POLÍTICA DE PRODUTO PROPOSTA; TESTES DE COEXISTÊNCIA WEBKIT+AVFOUNDATION NÃO EXECUTADOS.

## NF-15 — Web original como default; modo leitura simplificado por escolha

**[DIREÇÃO EXPLÍCITA DO DONO]** O FeedMine apresenta a **página original viva**: editor, layout, navegação, publicidade, mídias, links e eventuais assinaturas/paywalls pertencem ao publicador. O app não existe para remover publicidade por padrão nem entregar automaticamente uma cópia “limpa” do artigo; pode oferecer “Modo leitura” como opção acionada **pelo usuário**. Resumos/teasers são instrumentos de descoberta, não substitutos obrigatórios do acesso ao site.

**[ACHADO MATERIAL NO CÓDIGO V2 REFERÊNCIA 54]** `Sources/FeedMineUI/Reader/FeedReadingDecision.swift` escolhe `.local` **automaticamente** quando o feed forneceu `body` com texto, ou `summary` com ao menos **3.000 caracteres**; só escolhe `.site(URL)` no caminho de resumo curto com URL ou de ausência de texto local. `FeedMineApp/FeedMineApp/FeedMineApp.swift` usa esse destino em `composition.onReading` e abre `FeedReadingSurface` ou `InAppBrowser`. **Isto diverge do novo norte de produto para artigos com URL válida.** Importante: estes fluxos são primariamente texto que a fonte já forneceu em RSS/Atom, não evidência de scraping do site e remoção de anúncios. `ReadablePublicationText.swift` converte marcação em texto; não qualificar como violação legal automaticamente.

**[ALTERNATIVA DE CONTRATO]**

1. **Toque primário em artigo/link com site válido → site original no leitor interno.** Conteúdo do publicador permanece a fonte; não inventar versão total da história.
2. Ação explícita **“Modo leitura”**, se houver tecnologia e permissões adequadas; pode oferecer abertura no Safari/Reader quando possível. `SFSafariViewController` oferece controle nativo de Reader conforme plataforma; `config.entersReaderIfAvailable=false` no código atual **não** ativa automaticamente o modo Reader. `WKWebView` não oferece por si um Reader idêntico, exige avaliação separada se escolhido para permitir miniplayer persistente.
3. Preservar texto/resumo que a própria fonte enviou e conteúdo pessoal/offline já armazenado. **Sem URL disponível ou rede offline** pode haver *fallback identificado*: “Texto publicado pela fonte”/“Resumo fornecido pela fonte”, sem fingir página original, sem confundir com extração.
4. Não bloquear anúncios, scripts e navegação do publicador como padrão. Segurança e privacidade continuam aplicáveis (links maliciosos, permissões, transparência de dados, consentimento); respeitar escolhas do usuário e plataforma.
5. Custos atuais de “extraction/clean reading” precisam ser medidos: o que o runtime efetivamente busca, como é acionado, quanto custa e quem usa? Não manter uma etapa cara para renderização de artigos por padrão, mas **não apagar código ou dados** sem identificar contratos legítimos, indexação, biblioteca e offline.
6. Revisar `docs/product/F14_READER_LINK_NAVIGATION_UX_PRD.md`, `FeedReadingDecision`, `FeedReadingSurface`, `U-reading` e a decisão `U2` de `SFSafariViewController`, **sem** assumir que preservar site força uma tecnologia específica. A V1 `feedmine/Views/ArticleReaderView.swift` usava `WKWebView` direto + folha descartável, sem extrair a página.

**[CONFLITO DE PRODUTO A RESOLVER]** Abrir `SFSafariViewController` como modal pode impedir exibir miniplayer sobre o artigo (ver NF-13). Se migrar a apresentação do site para `WKWebView` a fim de coexistir com vídeo, documentar quais capacidades do SafariServices foram perdidas (Reader, cookies, security UI, consentimento, links) e como atender os requisitos sem esconder a página do publicador ou adicionar um browser inseguro.

**[PROVA]** Artigo com full RSS body + URL válida → tap deve abrir site real, não texto local; resumo de >3.000 caracteres + URL → site; site offline ou ausente → alternativa local explicitamente identificada; acionamento de modo leitor apenas sob pedido; anúncios e mídia web aparecem conforme site; swipe para voltar preserva o feed; vídeo flutuante sobre artigo somente se player e reader permitirem. Registrar erros HTTP e bloqueios em vez de atribuir falha ao site ou fazer fallback enganoso.

**Status Codex:** CONFLITO DE POLÍTICA DE LEITURA CONFIRMADO NO CÓDIGO 54; PROPOSTA DE PRODUTO NOVA; BUILD 55 A VERIFICAR.

## NF-16 — Visão integrada: feed infinito como hub de multimídia viva

**[NORTE, não feature isolada]** A principal unidade do FeedMine não é a tela de leitura nem o player: é a **sessão de descoberta e consumo**. A pessoa continua dentro da internet aberta, não dentro de uma cópia estática feita pelo app. Texto web, áudio, podcast, vídeo, futuras rádios e exploração podem se sobrepor em uma experiência fluida quando a origem permitir.

**[JORNADA EXPLORATÓRIA REAL]** Abrir FeedMine → descobrir vídeo YouTube → tocar inline → continuar rolando com vídeo visível em dock → abrir blog original em sheet sem perder vídeo/âncora → voltar → tocar podcast → podcast audível e vídeo mudo, ainda visível → continuar rolando → alternar áudio principal → fechar mídia e continuar de onde estava. Rádio web entra depois no papel de áudio principal. Não confundir potencial de coexistência com exigência de **três áudios simultâneos**: a proposta mantém **uma fonte sonora principal por vez**.

**[DESENHO ARQUITETURAL A VALIDAR]** Publicação e scroll continuam independentes. Interação explícita cria ou ativa sessão de reprodução no host; o renderer não é owner de rede nem AVPlayer nem WKWebView de longa duração. Um comando responde na UI imediatamente (NF-07); a composição coordena media focus e apresentação do conteúdo sem mutation retroativa de edição publicada; os players preservam as próprias fronteiras de tecnologia e plataforma. **Implementar passo a passo** e evitar criar uma segunda app architecture apenas para mídia.

**[ORDEM DE PROVAS]** A) usuário consegue acessar um vídeo do catálogo com origem real (NF-12); B) play YouTube inline e contrato de retorno (NF-13); C) continuidade visível após saída do card, sem reload e sob termos (NF-13); D) artigo original + vídeo visível com apresentação permitida (NF-10/NF-15); E) podcast audível com vídeo mudo (NF-11/NF-14); F) rádio web como terceira modalidade — **futura**, após A–E. Avaliar iPhone pequeno, iPad, Accessibility, performance/energia e integridade publicitária. Sem garantia artificial de background do iOS.

**[INSTRUÇÃO AO CODEX]** Corrigir qualquer ideia aqui que contradiga API, política, uso real ou invariantes. Se o YouTube não permitir algum modo, separar a restrição do desejo editorial; propor fallback fiel e perguntar apenas quando houver decisão de produto sem prova suficiente. Não afirmar “PiP do YouTube funciona” a partir de teste de AVKit com MP4 próprio.

**Status Codex:** DIREÇÃO APROVADA PELO DONO; EXECUÇÃO E VIABILIDADE DE CADA MODALIDADE AINDA ABERTAS.


---

**Regra final deste documento:** uma correção vale quando melhora a jornada real do leitor sem comprometer as invariantes do produto. O Codex deve nos corrigir sempre que a evidência pedir — inclusive se a correção for remover uma sugestão deste arquivo.
