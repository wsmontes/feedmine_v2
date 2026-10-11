# FeedMine V2 — Diretriz de execução para o agente
**Data:** 2026-10-11  
**Destino:** agente autônomo trabalhando na V2  
**Tipo:** handoff operacional e ordem de execução. **Não** é novo PRD, benchmark, proposta arquitetural ou autorização para redefinir critérios.

## Mandato

**Pare de otimizar a aparência de progresso e feche a promessa central do produto.** O FeedMine V2 deve permitir descobrir a internet aberta sem configurar fontes manualmente, ler um feed contínuo construído a partir de supply local preparada, mudar de contexto sem perder trabalho reaproveitável e voltar offline à mesma leitura. Rede, mídia e trabalho especulativo não podem interromper ou reescrever o que já está visível.

**Execute, não produza outro plano como entrega final.** Leia a autoridade vigente, inspecione o código/HEAD e os artefatos brutos, corrija o menor fluxo de produção responsável pelo comportamento, rode os testes que forem possíveis e entregue commits mais evidência. Autonomia é pressuposta: não peça aprovação para etapas já exigidas no benchmark.

### Hierarquia obrigatória

1. [Norte do produto](PRODUCT_NORTH_STAR.md).
2. [Decisões PD-1 a PD-10](PRODUCT_DECISIONS_2026-10-09.md), sobretudo PD-4, PD-5, PD-8, PD-9 e PD-10.
3. [Invariantes](../architecture/PRODUCT_INVARIANTS.md) e [benchmark congelado B01–B06](DISCOVERY_ACCEPTANCE_BENCHMARK.md).
4. [Arquitetura atual](../architecture/ARCHITECTURE.md) e ownership real no código.
5. [Auditoria de consistência](../reviews/DOCUMENTATION_CONSISTENCY_AUDIT_2026-10-10.md) para distinguir documentação histórica de normas atuais.

Planos de fases, estudos de transferência da V1 e relatórios antigos **não** revogam essa hierarquia. O backlog de “ouro da V1” não substitui a resolução da experiência central.

## Condição operacional: você está sozinho, mas não sem instrumentos

**Você é o agente executor autônomo. Não há uma equipe humana aguardando para programar, depurar, medir ou revisar por você. Neste momento você NÃO dispõe de um iPhone físico para testes, mas dispõe de um Mac com o simulador iOS/Xcode, do Codex e do próprio ChatGPT acessível pelo navegador. Use esses recursos de modo ativo — não como motivo para parar nem como promessa de que outro agente terminará o trabalho.**

- **Simulador/Xcode:** principal laboratório de execução agora. Faça builds, testes de integração e XCUI, instalações limpas e relaunch, fluxos completos de scroll e navegação, falhas de rede reproduzíveis, capturas de tela/vídeo, logs, traces e xcresult. Automatize o benchmark externo fiel sempre que o ambiente permitir. Inspecione o app funcionando, não apenas o resultado de testes de componentes. Não atribua ao simulador medidas de bateria, térmica ou comportamento de memória que exigem aparelho físico.
- **Codex:** use como apoio concreto de implementação, revisão independente de diffs, elaboração/inspeção de testes e identificação de concorrência, regressões e simplificações. Delegar uma análise não transfere responsabilidade: examine as alterações, integre conscientemente e execute as provas. Evite que dois agentes criem correções paralelas para a mesma responsabilidade.
- **ChatGPT pelo navegador:** use quando uma segunda análise ajudar a destravar decisões de arquitetura, interpretação dos invariantes, causa-raiz ou revisão crítica do comportamento. Forneça contexto, trechos de código e evidências concretas; peça objeções e alternativas mínimas, não mais um plano abstrato. Uma resposta do ChatGPT não constitui teste nem aprovação de produto.
- **Autonomia de ponta a ponta:** decida o próximo defeito de maior impacto, investigue, edite, teste, corrija, registre a evidência e faça commit/push. Não pare para solicitar ao dono do produto autorização, recursos, revisão de implementação ou escolha entre alternativas técnicas que já cabem no contrato vigente. Não produza apenas relatórios enquanto ainda há defeitos reproduzíveis corrigíveis.
- **Limite factual do hardware:** marque **B06 NOT_RUN** quanto à validação obrigatória em iPhone físico e registre exatamente quais medidas faltam. **Isso não autoriza declarar B06 PASS nem release aprovada.** Também não justifica bloquear B01–B05, builds, correções de produto, long-run no simulador, preparação da instrumentação ou quaisquer outras provas possíveis. Quando só a etapa física restar, entregue tudo que é verificável e documente o bloqueio específico em vez de ficar inativo.
- **Se uma ferramenta falhar:** use os demais recursos disponíveis e continue no menor fluxo verificável; reporte impedimentos concretos e reproduzíveis sem presumir que outro participante vai executá-los. A falta de iPhone físico é uma restrição conhecida, não uma solicitação recorrente ao usuário.

**Regra prática:** esgote o que pode ser construído, visto e provado autonomamente no simulador e no repositório antes de classificar qualquer trabalho como bloqueado por aparelho físico. Preserve a régua B01–B06 integralmente.

## Estado inicial que deve ser verificado, não presumido

**Repositório:** wsmontes/feedmine_v2, branch main. O último HEAD observado nesta consulta foi d55fa6f (documentação, 2026-10-10); **releia o HEAD ao iniciar**. Os últimos commits observados tratam principalmente de documentação de produto e estudos V1, não de correção funcional do feed.

**Evidência técnica registrada:** suíte histórica do pacote com 827 testes verdes e suíte iOS com 15 integração + 3 XCUI verdes em um commit anterior. Isso **não** certifica a build atual nem os gates de aceitação do produto.

**Problema de produto documentado:** ensaio anterior terminou perto de quatro minutos/135 cards partindo de quatro fontes selecionadas, apesar de um catálogo de 77.443 fontes. A execução de 30 minutos de consumo efetivo (B03) **não foi provada**.

**Catálogo:** o asset instalado pelo script atual vem da release catalog-v1/V1; a fonte autoritativa declarada é [wawasoft/feed-repository](https://github.com/wawasoft/feed-repository). Empacotamento a partir da revisão pública validada e atualização oportunista/atômica não estavam comprovados em main no último relatório.

**B05 — informação nova do dono do produto, 2026-10-11:** foi relatado **PASS canônico** do teste de continuidade A→B→A, reopen, salvos e offline, corrida bench/run/20261011T174133Z, com cláusulas b05-reopen-keeps-saved, b05-reopen-preserves-anchor, b05-return-preserves-anchor, b05-offline-shows-local e b05-offline-cards verdadeiras. O hash do driver de execução foi relatado como ad68a59d… e igual ao EVALUATOR.sha256 congelado. Existe um PASS antigo, corrida 165305Z, com hash 071c7a76…, anterior à correção do driver: **não é evidência canônica**.

**Ação imediata para B05:** localizar a corrida e validar manifesto, hash inteiro, driver, build/commit e oráculos. Se tudo confirmar, atualizar a matriz de evidências e **não gastar o próximo ciclo reimplementando B05**. Se artefatos estiverem só no Mac local e inacessíveis, registrar “PASS relatado pelo owner; ainda não verificado no checkout”, nunca inventar verificação nem rebaixar o relato. **“P0 fechado” neste checkpoint não significa que B01–B06 passaram.**

Os status do benchmark de 2026-10-10 eram B01–B06 NOT_RUN como provas integrais, com testes parciais existentes. Tratar como baseline documental **anterior** ao relato canônico de B05; descobrir qualquer outra execução mais recente antes de declarar status atualizado.

## Ordem de trabalho: fechar jornadas, não multiplicar componentes

### E0 — Fazer inventário mínimo de evidências e descobrir o ponto de trabalho

- Comparar main, branch em execução e commits ainda não integrados; não sobrescrever trabalho concorrente. Localizar resultados brutos B01–B06, runner, hashes, logs e últimos cenários executados.
- Escrever **uma única matriz viva** com gate, resultado PASS/FAIL/NOT_RUN/BLOCKED, commit/build, corpus, oráculo, local da prova e bloqueador factual.
- Diferenciar defeito reproduzido, prova ainda ausente e resultado reportado mas não verificável. Não gastar um ciclo apenas regenerando documentos.

**Concluído quando:** há uma baseline verificável, e o próximo defeito funcional prioritário está apontado para um owner de código concreto.

### E1 — Resolver a descoberta de fontes, não somente o ranking das quatro iniciais (B01/F01)

- Investigar o percurso catálogo elegível → seleção de targets → contato real → admissão → fontes contribuintes. Confirmar se TrustedFeeds.swift / starter set e o acquisition planner limitam indevidamente a exploração.
- Resolver progressão de **todo o catálogo elegível**, com idiomas explícitos como elegibilidade estrita, fontes novas descobertas continuamente, prioridade relativa/fairness e respeito às restrições do aparelho. Não trocar quatro fontes por cinquenta fontes fixas.
- Fazer idiomas e lugares iniciais funcionarem e permitir que **dois interesses sejam declarados dentro do feed**, sem onboarding temático obrigatório. O feed neutro já deve ser útil; respostas explícitas mudam a descoberta futura e devem poder ser desfeitas.
- **Separadamente**, cumprir PD-10: usar revisão pública validada do catálogo no bundle de release; comparar manifesto em oportunidade legítima de launch/foreground (~24 h desde verificação bem-sucedida); aplicar novas fontes, remoções, redirects e metadados por staging + validação + ativação atômica, sem bloquear primeira apresentação nem tocar em salvos/história pessoal. Não confundir atualização de catálogo com execução da exploração progressiva.

**Prova esperada:** B01 integral com corpus externo congelado; no cenário rico, ≥50 fontes efetivamente incluídas no conjunto elegível de aquisição e ≥20 fontes contribuintes nos primeiros 300 cards; diferenças explicáveis após as preferências. Os números são **condições de benchmark**, nunca limites fixos do runtime.

### E2 — Resolver abastecimento contínuo, cauda e filas sem bloqueio (B03/F05 e PD-5/PD-9)

- Rastrear no aplicativo real as transições entre supply adquirida, admitida, pronta, publicada e apresentada. Localizar a causa de starvation e do fim artificial; distinguir “acabou o conjunto de quatro fontes” de “acabou todo conteúdo elegível”.
- O runtime deve continuar adquirindo, selecionando e preparando **depois** da primeira tela, antecipando consumo e adaptando a reserva à velocidade de avanço, latência de reposição, disponibilidade de fontes, recursos e permissão do iOS. Scroll **não** deve disparar diretamente um fetch síncrono nem acordar um pipeline parado.
- Revisar AppComposition.swift (reserveCards: 16 foi apontado na auditoria) e gargalos de seleção/runway como **hipóteses**, não assumir que aumentar esse número corrige o problema. Não criar cotas permanentes, periodicidade arbitrária ou uma segunda fila/segundo scheduler.
- Um candidato pendente de imagem, link, texto, decode ou outra preparação **sai imediatamente da oportunidade atual de publicação**, não bloqueia o cursor nem reserva posição; preserva identidade e trabalho útil para avaliação futura. Temporariamente lento **não** vira text-only por timeout. Link definitivamente inválido não vira card “clicável” falso.
- A seleção respeita PD-4: nenhuma adjacência da mesma SourceID, inclusive na borda dos segmentos; em contexto de fonte única há exceção. Media completion não ordena o feed.
- Manter segmentos publicados imutáveis e o prefixo visível sagrado. Download tardio ou background não pode mudar layout, posição, texto, ordem ou ação já publicados.

**Prova esperada:** B03 completo, com **30 minutos de avanços efetivos a 1 card/s e rajadas de 3 cards/s por 20 s a cada 5 min**, sem fim artificial nem interrupção ≥1 s por falta de runway em corpus com oferta suficiente. Registrar taxas, fontes contactadas, backlog e distância/pressão da reserva durante todo o trace. Corrigir B04 sobre estabilidade física durante execução e idle de 10 minutos; teste só de IDs em memória não basta.

### E3 — Fechar qualidade editorial e interação essencial (B02/B04, F02/F06/F08)

- Publicar 200 cards **após** os dois interesses explícitos: ≥80% de relevância com rótulos externos, ≥20 fontes, nenhuma acima de 15%, zero adjacências de SourceID e zero duplicata canônica indevida no mesmo contexto.
- Garantir que abrir artigo, retornar à âncora, salvar, recuperar offline e mudar A→B→A não dependam de conteúdo remoto em tempo de scroll ou descartem edição válida.
- Validar visualmente apresentação real: mídia preparada ou text-only justificável, geometria estável, texto legível, progresso inicial com fontes/títulos reais. Corrigir somente o necessário para a jornada passar, reutilizando owners já existentes.

**Prova esperada:** B02 e B04 integrais, mantendo a evidência já confirmada de B05.

### E4 — Certificação de release (B06 e matriz completa)

- Preparar fixture de aceitação **fora do aplicativo**, com ≥300 fontes elegíveis por perfil e ≥5.000 itens distintos, transporte externo com falhas e atrasos, hashes e traces congelados antes de testar a build candidata. Não preencher SQLite diretamente nem inventar um algoritmo especial para o benchmark. Se fixture ainda não existir, construir o mínimo fiel necessário e registrar o que falta.
- Rodar B01–B06 sobre **o mesmo commit/build candidato**, com relatórios brutos. B06 exige iPhone físico real, incluindo sessão longa, memória, CPU, térmica, energia e hitches; simulador não é waiver.
- Se um aparelho ou insumo não estiver disponível, marcar BLOCKED/NOT_RUN com a razão, continuar os testes e correções possíveis e **não** anunciar release pronta.

**Pronto para release** significa **seis gates integrais PASS** na baseline vigente, mais PD-10 comprovado. “Swift tests verdes”, “UI portada”, “fiz um test run menor” ou “quase passou” não são estados equivalentes.

## Restrições para evitar regressões arquiteturais

- Uma responsabilidade, um owner. Reutilizar AcquisitionCoordinator, Selection/Editorial, MediaPreparation, PublicationCoordinator, FeedSession, Persistence e UI bridge existentes. Eliminar duplicações ao tocar nesses fluxos, sem iniciar rewrite geral.
- Sem novo cache, cron, timer, task supervisor, state machine, generation token ou fallback paralelo **por conveniência**. Justificar qualquer mecanismo novo por um invariante falhando que não pode ser atendido no owner atual.
- UI apresenta snapshots locais; não decide seleção, faz SQL, inicia aquisição ou resolve imagem remota. Não deixar callbacks assíncronos reescreverem história já publicada.
- Não fazer pontuação técnica de disponibilidade HTTP virar “qualidade editorial”. Não fingir que ampliar lote melhora cobertura de fontes.
- Não modificar oráculos, duração, corpus, driver, hashes ou critérios congelados para obter PASS. Não transformar teste unitário em substituto de jornada real.
- Antes de modificar arquivos, conferir HEAD e trabalho concorrente. Fazer commits pequenos por **comportamento observado**; registrar evidência junto com a alteração, sem escrever dezenas de PRDs adicionais. Seguir verificações de build/test/diff aplicáveis antes do push.

## Formato mínimo de cada entrega do agente

1. **Qual comportamento estava quebrado:** reprodução e prova concreta, com trace ou evidência observável.
2. **Causa e correção:** owner de código responsável e mudança mínima, com caminho de arquivo/commit.
3. **Validação realizada:** comando/build, ambiente, corpus, hashes, logs, status sem ambiguidade.
4. **Próximo bloqueador:** uma prioridade de produto, não uma lista de vinte tarefas periféricas.

**Prioridade absoluta até segunda ordem:** (1) fonte/catálogo elegível e descoberta real, (2) runway infinito dentro da oferta disponível, (3) preparação sem head-of-line blocking e apresentação imutável, (4) prova completa dos seis gates. Não desviar para polimento opcional, migração cosmética da V1, novos estudos, contagem de testes ou micro-otimização antes de o usuário conseguir simplesmente **abrir, descobrir e continuar lendo**.
