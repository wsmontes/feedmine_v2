# FeedMine V2 — dez frentes de auditoria pelo olhar do usuário

**Estado:** mapa de investigação e execução da V2; nenhuma aprovação humana pendente para iniciar ou continuar.  
**Data-base:** 2026-10-10. Este é um mapa de **hipóteses e evidências**, não certificação de release.  
**Autoridade:** [Norte de produto](PRODUCT_NORTH_STAR.md), [Decisões de produto](PRODUCT_DECISIONS_2026-10-09.md), [Invariantes](../architecture/PRODUCT_INVARIANTS.md) e [Benchmark vigente](DISCOVERY_ACCEPTANCE_BENCHMARK.md).

## Objetivo

Revisar **dez experiências observáveis**, uma de cada vez, para responder:

1. **Promessa:** o que a pessoa veio conseguir?
2. **Realidade:** o que a V2 realmente entrega, demonstrado em código e execução? O que ainda é só desenho?
3. **Quebra:** onde a jornada falha ou exige conhecimento/configuração que o produto deveria poupar?
4. **Causa:** qual responsabilidade existente está desconectada, insuficiente ou duplicada?
5. **Correção mínima:** como consertar com os donos já existentes, sem novo motor/cache/scheduler por conveniência?
6. **Prova de aceitação:** qual jornada de ponta a ponta falharia antes e deve passar depois, sem mudar a régua?

As frentes são **fatias da experiência**, não times, módulos Swift nem autorização para dez arquiteturas paralelas. Cada frente pode envolver vários módulos, mas cada responsabilidade continua tendo um dono claro.

## As dez frentes, na ordem de investigação

### F01 — Descoberta automática de fontes e alcance do catálogo
**Promessa:** escolher interesses e encontrar coisas de fontes desconhecidas, sem configurar RSS.  
**Jornada/oráculo:** instalação limpa; selecionar assuntos/idiomas/região; observar fontes descobertas, fontes efetivamente contactadas e fontes contribuintes sem seleção manual. Aplicar integralmente B01 do benchmark vigente.  
**Evidência inicial:** catálogo embarcado com 77.443 fontes; composição atual inicia de uma seleção padrão pequena; a receita curada pontua fontes já resolvidas. O teste do simulador registrou seleção inicial de quatro fontes.  
**Risco principal:** catálogo como ferramenta manual de administração, em vez de universo editorial abastecido automaticamente.  
**Direção da correção:** resolver elegibilidade e expansão de fontes a partir do catálogo/contexto no caminho existente de aquisição; não portar o scheduler da V1 nem criar um segundo selecionador.  
**Situação:** **diagnóstico inicial feito; correção e teste B01 ainda não comprovados**.

### F02 — Primeira abertura, onboarding e tempo até a primeira descoberta
**Promessa:** uma pessoa que não conhece RSS escolhe seus interesses, vê preparação honesta e começa a explorar.  
**Jornada/oráculo:** instalação limpa sem dados locais; Welcome → Composer → interesses → primeiro conteúdo real; comparar diferentes idiomas, rede lenta, fontes vazias e retorno após falha. Medir tempo até o primeiro card legível, utilidade dos primeiros cards e proveniência real de toda informação mostrada na preparação.  
**Evidência inicial:** existe onboarding em duas etapas, ColdFeedBootstrap e tela de progresso baseada em fatos do pipeline; testes validaram componentes e o fluxo básico.  
**Risco a verificar:** Composer parecer personalizado sem ampliar as fontes de acordo com interesses; primeira tela depender de somente poucos feeds; progressos tecnicamente verdadeiros mas pouco envolventes.  
**Aceite:** o usuário obtém material coerente sem ter que ir à tela de Fontes, e não há título, imagem nem progresso inventados.

### F03 — Aquisição, frescor e integridade das histórias
**Promessa:** o conteúdo de diferentes sites realmente chega, é recente, é legível e pode ser aberto.  
**Jornada/oráculo:** corpus externo de feeds RSS, Atom e JSON Feed com redirects, charset, HTML em resumo, datas estranhas, documentos grandes, falhas, feeds lentos, atualizações materiais e múltiplos links para o mesmo artigo. Rastrear ingestão → identidade → texto → publicação → link aberto.  
**Evidência inicial:** o código contém Syndication/Acquisition, tradução para Candidate, proteção de identidade, texto legível e casos de integração; isso não prova cobertura da heterogeneidade das dezenas de milhares de fontes.  
**Risco a verificar:** fontes selecionadas que nunca contribuem, bloqueio por fontes defeituosas, cards ilegíveis/obsoletos, artigos não abríveis e duplicações canônicas.  
**Aceite:** falha isolada não interrompe fontes saudáveis; nenhuma perda silenciosa de histórias elegíveis e nenhuma publicação inválida.

### F04 — Curadoria, relevância, variedade e controle editorial
**Promessa:** histórias pertinentes e surpreendentes, sem monotonia de um único publicador.  
**Jornada/oráculo:** perfis com interesses diferentes sobre corpus rotulado; inspecionar a sequência publicada, diversidade de fontes, assuntos, idiomas, duplicações e edições de artigos. Aplicar B02, PD-1 e PD-4.  
**Evidência inicial:** SelectionEngine implementa elegibilidade, pesos e alternância, inclusive fronteiras de segmentos; testes demonstram comportamento de componentes.  
**Risco a verificar:** curadoria atuar apenas como reordenação de uma seleção insuficiente; métricas de ordenação verdes sem relevância percebida; itens elegíveis presos atrás de outros.  
**Aceite:** o perfil altera a descoberta de modo demonstrável, preservando alternância e relevância sem fabricar diversidade.

### F05 — Continuidade, antecipação e recuperação do runway
**Promessa:** o leitor percorre um feed fluido, enquanto o próximo conteúdo é preparado antecipadamente.  
**Jornada/oráculo:** execução controlada com oferta elegível suficiente, 30 minutos de avanço real e rajadas de consumo; medir reserva publicada/admitida ao longo do tempo, consumo, produção, hitches, sinais de pressão e recuperação após rede lenta. Aplicar B03 integralmente.  
**Evidência inicial:** RunwayController mede consumo e reposição; FeedSession separa publicado de admitido. O ensaio anterior navegou ~4 minutos/~135 cards antes de esgotar a oferta escolhida; **30 minutos não foram demonstrados**.  
**Risco principal:** abastecimento insuficiente ou dependente de gesto apesar de catálogo abundante; confundir tempo de app aberto com avanço efetivo.  
**Aceite:** sem fim artificial, cards repetidos, interrupções indevidas ou retrocesso de posição sob oferta comprovadamente disponível.

### F06 — Cards, mídia, estabilidade visual e legibilidade
**Promessa:** a apresentação é boa o bastante para querer continuar lendo; o feed não pula sozinho.  
**Jornada/oráculo:** cards com imagem válida, imagem ausente, texto longo, mídia lenta, atualizações de fonte, fontes extremas, Dynamic Type, retrato/paisagem e leitura parada por 10 minutos. Conferir identidade, ordenação, geometria física, deslocamento visual, contraste e acessibilidade; aplicar B04 e PD-5/PD-6.  
**Evidência inicial:** houve transferência de componentes da V1 e comparações visuais sem equivalência pixel a pixel; mídia preparada e layout text-only existem.  
**Risco a verificar:** jitter, salto de scroll, decode/memória durante uso prolongado, telas coerentes em teste mas pouco legíveis no aparelho.  
**Aceite:** nenhum efeito de background muda o que já foi apresentado; cards permanecem legíveis sem depender de imagem.

### F07 — Busca, filtros, assuntos e troca de contexto
**Promessa:** mudar a curiosidade rapidamente sem perder o que já estava preparado ou sendo lido.  
**Jornada/oráculo:** pesquisar, combinar filtros, salvar preset, alternar A → B → A e alterar idioma/região; verificar conteúdos específicos, identidade dos contextos, posição, reaproveitamento do trabalho, ausência de callbacks cruzados e ação de desfazer/limpar.  
**Evidência inicial:** há filtros, ContextKey, presets, pesquisa e testes de navegação/contextos; a experiência ponta a ponta de troca rápida sob aquisição lenta ainda precisa ser observada.  
**Risco a verificar:** reconstrução desnecessária, sessão destruída quando muda um filtro, filtros sem efeito real na aquisição, resultados de contexto anterior contaminando o atual.  
**Aceite:** contexto muda prioridade do trabalho futuro, não destrói gratuitamente estado local útil.

### F08 — Leitura, ações e biblioteca pessoal
**Promessa:** descobrir é só o começo: abrir a história, voltar, salvar e reencontrar devem funcionar.  
**Jornada/oráculo:** abrir card real dentro do app, retornar à posição, salvar/remover, usar caixas e coleções, compartilhar/copiar, importar/exportar; quando houver episódio, testar áudio real em vez de apenas simulação.  
**Evidência inicial:** leitor via SFSafariViewController, bookmarks, caixas, coleções, ações, share e importação/exportação estão ligados em diferentes graus; documentação registra diferenças aceitas da V1.  
**Risco a verificar:** controle visual que abre destino diferente do esperado, mídia declarada sem reprodução efetiva, saved/library que não recupera o artigo correto, leitura interrompida ao voltar.  
**Aceite:** toda ação oferecida realiza a ação prometida no conteúdo correto, e o leitor retorna ao mesmo ponto.

### F09 — Persistência local, offline e reabertura
**Promessa:** o que já foi adquirido pertence à experiência do usuário e está disponível sem rede.  
**Jornada/oráculo:** iniciar com conexão, consumir/salvar, colocar offline, navegar em dados locais, matar/reabrir processo, restaurar contexto/âncora/estado de salvos e depois recuperar a rede. Aplicar B05 (em conjunto com F07/F08).  
**Evidência inicial:** a V2 implementa SQLite local, checkpoint e restauração antes de HTTP; teste anterior recuperou a mesma identidade de card depois de relançar.  
**Risco a verificar:** perda silenciosa após troca de contexto, invalidação exagerada, histórico não recuperável, assets que deixam de existir offline, diferenças entre suspensão e encerramento.  
**Aceite:** valor local tem precedência sobre rede; limites offline genuínos são comunicados, não disfarçados.

### F10 — Escala, recursos, acessibilidade e prontidão para publicar
**Promessa:** a experiência continua utilizável em aparelhos e condições reais, não somente no simulador de desenvolvimento.  
**Jornada/oráculo:** reproduzir F05/F06/F09 em iPhones físicos representativos, sob rede rápida/lenta, armazenamento limitado, memória pressionada, Low Power Mode e uso prolongado; verificar VoiceOver, textos ampliados, localidades suportadas, permissões/privacidade, erros visíveis, distribuição de release e crash-free behavior. Aplicar B06 e auditoria de release.  
**Evidência inicial:** testes de simulador e amostragem de CPU/RSS existem; relatório registra que validação prolongada no aparelho físico **não foi executada**.  
**Risco a verificar:** crescimento de recursos com milhares de cards, travamentos e consumo de energia, diferenças reais do iOS, acessibilidade ou fluxo de release incompleto.  
**Aceite:** nenhum release PASS sem evidência física exigida pelo benchmark; BLOCKED/NOT_RUN são relatados sem interromper as demais frentes.

## Como executar, uma frente por vez

1. **Leitura de evidências:** identificar promessas, implementação de `main`, testes realmente executados, pendências e divergências. Não assumir que o relatório antigo ainda descreve o código atual.
2. **Reprodução pelo usuário:** testar a jornada concreta ponta a ponta, sem injetar cards manualmente nem reduzir entradas para caberem no código.
3. **Diagnóstico:** separar defeito confirmado, risco plausível e falta de validação. Explicar causa e donos já existentes.
4. **Correção enxuta:** reparar no fluxo atual; evitar caminhos concorrentes, timers, quotas de cards, camadas ou estados redundantes.
5. **Verificação:** rodar a mesma prova sem alterar o oráculo, mais regressão relevante; guardar resultados e limitações.
6. **Registro final por frente:** `PROMESSA`, `COMPROVADO`, `QUEBRA`, `CAUSA`, `SOLUÇÃO`, `EVIDÊNCIA`, `RESULTADO` (PASS/FAIL/NOT_RUN/BLOCKED) e `RISCO RESIDUAL`.

**Não há gate de aprovação humana entre passos.** O executor prossegue até a melhor conclusão verificável e deixa as exceções explícitas, sem redefinir o sucesso. A ordem pode se adaptar a dependências reais de engenharia, mas não serve de desculpa para perder de vista F01 e F05.

**Atenção:** não criar dez benchmarks incompatíveis. Os gates B01–B06 do [benchmark vigente](DISCOVERY_ACCEPTANCE_BENCHMARK.md) são **transversais** e mantêm seus próprios critérios; esta matriz organiza **onde investigar**, não modifica a régua.

## Linha de base e transparência (2026-10-10)

- **F01:** já existe um diagnóstico inicial e um benchmark; falta prova de implementação corrigida.
- **F02–F04, F06–F09:** existem componentes e testes parciais; auditorias de produto completas destas frentes **ainda não foram executadas nesta matriz**.
- **F05:** execução anterior insuficiente para o critério de 30 minutos; **não é PASS**.
- **F10:** ensaio obrigatório em iPhone físico ainda **NOT_RUN**.

Fontes primárias para iniciar: [matriz de transferência V1/V2](../v1-study/UI_TRANSFER_MATRIX.md), [registro de evidências](../reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md), [decisões PD-1..7](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [arquitetura](../architecture/ARCHITECTURE.md).

> **Regra final:** cada frente deve melhorar uma experiência que o usuário percebe. Se o resultado for apenas mais testes verdes sem uma jornada melhor, a frente não está aprovada.
