# FeedMine V2 — benchmark independente de aceitação do produto (baseline 1.0)

**Estado: CONTRATO OPERACIONAL VIGENTE. Sem aprovação humana pendente para começar ou continuar o trabalho.**  
**Tipo:** contrato de aceitação *black-box* da experiência, não um plano de arquitetura.  
**Norma de leitura:** [Norte de produto](PRODUCT_NORTH_STAR.md); [decisões vinculantes](PRODUCT_DECISIONS_2026-10-09.md); [invariantes](../architecture/PRODUCT_INVARIANTS.md).

> **Pergunta única:** alguém consegue abrir o FeedMine, escolher interesses e explorar conteúdo relevante da internet aberta continuamente, inclusive de fontes desconhecidas, sem configurar manualmente uma lista de feeds e sem o aplicativo acabar prematuramente ou mexer na leitura?

Este benchmark é deliberadamente **mais exigente que a validação técnica de componentes**. Seu objetivo é detectar quando uma implementação satisfaz testes locais mas deixa de entregar a promessa do produto.

## Nota transversal sobre capacidade adaptativa e cobertura do catálogo (2026-10-10)

[PD-8](PRODUCT_DECISIONS_2026-10-09.md) exige exploração progressiva de todas as fontes elegíveis ao longo de oportunidades reais, sem cotas permanentes, e orçamentos adaptados a consumo, rede, memória, disco, energia e condições do sistema. **Os números de B01–B06 são condições fixas de avaliação, não tamanhos de lote, limites do feed ou quotas do runtime.** Como diagnóstico complementar, a equipe deve registrar progressão de fontes elegíveis/contatadas ao longo de oportunidades, comportamento sob condições ricas e pressionadas e aproveitamento de armazenamento local. Essa observação **não altera, substitui, enfraquece ou declara aprovados** os gates congelados abaixo. Uma execução finita não prova cobertura eventual de todas as fontes; evidenciar tendência e ausência de exclusão estrutural, sem prometer recursos ilimitados do iOS.

## 1. Regra de autoridade: o agente implementa; não redefine o sucesso

- **Autonomia é obrigatória.** O agente deve tratar os critérios já escritos como contrato de trabalho: planejar, implementar, construir o avaliador, executar, corrigir e reavaliar por iniciativa própria, sem perguntar se pode começar, continuar, alterar código ou rodar um teste. Não há etapa de aprovação intermediária nem espera pela resposta do product owner.
- O agente executor pode alterar código, otimizações e testes unitários, mas **não** critérios, duração, composição do corpus, oráculos, trace de consumo, parâmetros de rede, classificação de resultados ou exclusões de cenários para alcançar um PASS.
- **Fidelidade é obrigatória.** O agente não tem autoridade para mudar a régua, reduzir duração/volume, trocar um teste ponta a ponta por um unitário, descartar um cenário difícil ou reclassificar FAIL/NOT_RUN/BLOCKED como PASS. Uma eventual instrução futura **espontânea e explícita do usuário** pode substituir requisitos; o agente **não deve solicitar nem esperar** essa instrução para continuar trabalhando com o contrato vigente. **Falhou → corrigir o produto e repetir sem alterar a régua.**
- O avaliador deve operar **fora do código de produção que está sendo avaliado**. No mínimo: fixture, manifesto SHA-256, driver de interação e oráculos em artefatos separados, congelados antes da execução da build candidata. O agente pode **criar autonomamente** essa infraestrutura, mas não pode editá-la para favorecer uma build depois de observar falhas. Uma cópia/hashes externos ao patch de produção permitem revisão independente; apenas estar no mesmo repositório não garante independência.
- Não aceitar alterações de fixture ou do runner originadas do patch de implementação; executá-lo contra a referência congelada. Sem CI hospedada obrigatório: pode rodar localmente em máquina macOS com Xcode e em aparelho físico, usando evidências reproduzíveis.
- **PASS / FAIL / NOT_RUN / BLOCKED** são os únicos resultados de um gate. NOT_RUN ou BLOCKED **não** equivalem a PASS. Se um recurso não está acessível (por exemplo, iPhone físico), registrar NOT_RUN/BLOCKED, continuar todas as demais provas e melhorias possíveis autonomamente e deixar o risco explícito. Nunca pedir aprovação para simplesmente prosseguir. Um marco técnico interno pode estar concluído sem que o produto tenha passado no benchmark; isso **não** autoriza declarar a release pública aprovada.
- Não trocar testes de experiência por equivalentes de componente; não marcar "o método foi chamado" como prova de "o leitor recebeu conteúdo".

## 2. Preparação do corpus e do avaliador

Dois ambientes obrigatórios, com papéis distintos:

**A. Corpus de aceitação determinístico, desconhecido do agente durante o desenvolvimento.**  
Catálogo e conteúdo capturados a partir de fontes reais e anonimizados/redistribuídos conforme licenças, servidos por um transporte local de teste **externo ao aplicativo**, que reproduz protocolos, atrasos e falhas. Sem mock da lógica do FeedMine, sem inserir cards diretamente no SQLite, sem pré-instalar história publicada. O aplicativo real percorre: catálogo → resolução de fontes → aquisição → admissão → seleção → mídia → publicação → sessão → UI.

Pré-condições explícitas desta versão do corpus: **pelo menos 300 fontes elegíveis para cada perfil principal e 5.000 itens distintos elegíveis**, com metadados rotulados independentemente (tema, idioma, região, fonte, artigo canônico, revisão material, mídia). Incluir fontes rápidas e lentas, RSS/Atom/JSON Feed quando suportados, duplicatas entre publicadores, respostas vazias, falhas intermitentes e mídia lenta. O corpus deve revelar seus totais ao avaliador antes da execução — não ao pipeline por uma rota especial. A preparação do corpus ainda precisa ser implementada; **não alegar que já existe**.

**B. Ensaio live com internet e catálogo de produção.**  
Mesma jornada feita por uma pessoa no app, em aparelho físico com redes reais. Serve para detectar compatibilidade, latência, curadoria e limites que fixtures não revelam. Não substitui A, porque sites reais podem ficar indisponíveis. Deve registrar se um fim de feed é genuíno ou ocorreu apesar de haver conteúdo elegível.

Em ambos, congelar a versão do aplicativo, commit, build, catálogo, perfil, corpus, traces, rede, device, iOS, critérios e horário. Registrar eventos e resultados brutos para auditoria. Um algoritmo alternativo criado exclusivamente para o benchmark invalida a prova.

## 3. Gates P0: todos obrigatórios, nenhum compensado por média ou nota global

### B01 — Descoberta sem assinatura (o verdadeiro primeiro uso)

**Alinhamento de jornada (decisão expressa do product owner, 2026-10-10):** o teste mantém os mesmos limiares de quantidade, duração, diversidade e relevância, mas os dois assuntos agora são **expressos no feed**, depois da orientação inicial de idiomas e lugares; ver [PRD F02](F02_DISCOVERY_FEED_ONBOARDING_PRD.md).

**Entrada:** instalação limpa; catálogo disponível; onboarding curto com **múltiplos idiomas e lugares de interesse**; o usuário entra no feed **sem escolher assuntos previamente** e declara **dois interesses temáticos por respostas explícitas dentro do próprio feed**; **zero seleção manual de fontes, zero OPML**. A fase neutra inicial e a fase após as duas respostas devem ser observadas separadamente.

**Obrigatório:**
- A experiência produz um feed útil a partir do catálogo, sem depender exclusivamente das quatro fontes padrão nem exigir "Fontes → adicionar" como etapa escondida.
- No cenário rico do corpus, **pelo menos 50 fontes distintas entram automaticamente no conjunto de aquisição elegível**, e **pelo menos 20 fontes distintas contribuem com os primeiros 300 cards**. Esses valores são condições do *teste de capacidade de descoberta*, não quotas ou lotes fixos do runtime.
- As escolhas de **idiomas e lugares** orientam a descoberta inicial, sem confundir idioma com país ou origem do publicador com assunto geográfico da matéria. As **duas preferências temáticas declaradas no feed** alteram efetivamente a busca futura de fontes e o conteúdo; repetir a jornada com outro perfil muda a seleção de modo explicável.
- O onboarding apresenta evidência real durante a preparação e não fabrica títulos, imagens nem progresso. **O primeiro feed, antes de qualquer voto temático, já deve ter artigos íntegros e atraentes de fontes editorialmente defensáveis, incluindo referências reconhecidas e fontes independentes/especializadas de qualidade; o score técnico do catálogo não basta como prova de credibilidade.**

**FAIL típico:** o app exibe cards bonitos mas consulta somente a lista estática de quatro feeds; a receita apenas reordena essa lista.

### B02 — Relevância, variedade e identidade editorial

**Entrada:** o mesmo corpus rotulado, conjunto de **200 cards publicados após as duas preferências temáticas explícitas no feed** sob perfil com múltiplas fontes elegíveis; observar separadamente o feed neutro anterior. Os limiares de B02 permanecem inalterados.

**Obrigatório:**
- **≥80% dos 200 cards** correspondem aos interesses/idiomas declarados **na etapa de preferências temáticas explícitas**, de acordo com o rótulo externo congelado; a distribuição de relevância por assunto/idioma é publicada junto do resultado. **Não exigir relevância a temas ainda não declarados no feed inicial neutro.**
- **≥20 fontes distintas** aparecem; nenhuma fonte representa **>15%** dos cards quando o corpus oferece alternativas.
- **Zero pares de cards consecutivos da mesma fonte** em contexto multi-fonte (PD-4), incluindo fronteiras de segmentos.
- **Zero duplicatas de artigo canônico** apresentadas como descobertas novas na mesma edição; uma edição material segue a decisão PD-1 e é contada separadamente.
- Nunca inflar diversidade com nomes falsos, reatribuição fictícia de fonte ou repetição de cards para preencher a contagem.

**Observação:** os limiares de 80%, 20 e 15% fazem parte desta baseline fixa. Eles não podem ser recalibrados depois de ver os resultados da implementação. Se falhar, corrigir o produto ou registrar o FAIL.

### B03 — Runway real: 30 minutos de consumo, não 30 minutos com app aberto

**Entrada:** instalação limpa em contexto rico com ≥5.000 itens elegíveis; replay externo de **30 minutos de avanços efetivos**, a **1 card por segundo**, com rajadas de até **3 cards por segundo durante 20 segundos a cada 5 minutos**, usando gestos/scroll nativos. Fontes rápidas e lentas, aquisição variável e mídia tardia. O corpus deve ter oferta suficiente para o trace inteiro.

**Obrigatório:**
- Cada avanço previsto pela trilha alcança o próximo card distinto; o total de cards efetivamente consumidos deve corresponder ao trace, não a um contador de gestos disparados.
- **Zero fim artificial de feed**, tela vazia, retorno ao início, repetição para disfarçar falta de supply ou loading que substitua a história visível enquanto ainda há conteúdo elegível disponível.
- **Zero paralisação visível ≥1 segundo causada por falta de runway**, no ambiente controlado desta baseline do benchmark.
- Produção continua preparando conteúdo depois da primeira tela. Registrar ao longo do tempo: cards preparados/publicados/admitidos, runway disponível, novas fontes contactadas, taxas de aquisição/consumo, mídia, pedidos upstream e latências.
- Se o aplicativo para em 4 minutos, **FAIL**, não "30 minutos aprovados com exceção".
- Se o corpus ou runner não suporta a trilha completa, **BLOCKED/NOT_RUN**; nunca reduzir o trace para caber na implementação.

**Importante:** 30 minutos e o padrão de interação são *exigência de ensaio*, não timer de aquisição nem tamanho fixo de página para o produto. O runway permanece adaptativo.

### B04 — O feed apresentado é sagrado

**Entrada:** durante uma leitura real, suspender/liberar fontes lentas, completar downloads de imagens, receber atualização de artigo e eventos de foreground. Repetir também com leitor parado por 10 minutos.

**Obrigatório:** nenhuma produção em background altera silenciosamente o prefixo admitido, IDs, ordem, geometria de cards apresentados ou deslocamento do leitor. Novos cards ficam preparados para oportunidade legítima de avanço; nenhum callback de rede sozinho amplia a lista visual. Mudança editorial explícita pode fazer transição deliberada sem deixar callback antigo interferir.

**Oráculo:** snapshots de IDs e bounds, âncora visual/offset e registro dos eventos reais — não somente chamadas de método. **Zero alteração indevida**.

### B05 — A → B → A, memória local e volta offline

**Entrada:** selecionar A, explorar, ir para B e voltar a A; suspender/reabrir o app; cortar rede; abrir um salvo; retomar a leitura.

**Obrigatório:** A reaproveita edição, posição e trabalho local ainda válido, sem reconstrução inútil; B não contamina A; rede fora do ar não impede mostrar história local; itens salvos sobrevivem; voltar ao app não desloca o card atual. Um fim offline *real*, ao consumir toda a oferta local, deve ser comunicado sem apagar o histórico.

**Oráculo:** identidade da publicação e posição persistida, eventos de rede e leitura observável. **Zero perda silenciosa de estado**.

### B06 — Escala e estabilidade no aparelho físico

**Entrada:** executar B03 também num iPhone físico de referência compatível com o mínimo suportado, em sessões de grande volume; repetir no aparelho-alvo atual. Conservar o corpus e registrar recursos.

**Obrigatório:** sem crash, terminação por memória, travamento de interface ≥1 segundo, vazamento de recurso com crescimento sustentado não explicado durante uso prolongado ou salto/duplicação de cards. Coletar RSS do processo, CPU, memória, energia/térmica, frame hitches e tempo de scroll; reportar picos e tendência após aquecimento. Não inventar limites adicionais de memória/energia para obter PASS nem usar a ausência desses números como motivo para interromper o trabalho. Medir e relatar recursos e tendências; critérios adicionais só passam a valer se uma instrução posterior do usuário os definir explicitamente.

**NOT_RUN** se não houver aparelho. Simulador não aprova esse gate.

## 4. Relatório obrigatório por execução

Um relatório único para cada build, com:

1. **Identidade imutável da execução:** commit/SHA, configuração e hashes externos de catálogo/corpus/runner, dispositivo, rede, perfis e janela temporal.
2. **Matriz B01–B06:** PASS/FAIL/NOT_RUN/BLOCKED com resultado observado, expectativa congelada, artefato de evidência e motivo do desvio.
3. **Provas de ponta a ponta:** fluxo de onboarding, fontes selecionadas automaticamente, quantidade de fontes efetivamente contactadas/contribuintes, relevância, diversidade, cards originais, runway por minuto, avanço real, continuidade visual, restauração e recursos.
4. **Sinais de manipulação:** mudança no runner/fixture/oráculos; pré-povoamento do banco; seleção manual de feeds não autorizada; limitação de catalog query ou fonte; trace encurtado; repetição sintética; mock do componente avaliado; ajustes ocultos por build flag.
5. **Conclusão:** release liberada somente se **todos** os gates P0 estiverem PASS nesta baseline do benchmark. Um relatório honesto pode terminar em FAIL; ele é muito mais útil que um PASS falso.

## 5. Estado inicial honesto da V2 em 2026-10-10

O [registro atual de validação](../reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md) prova avanços de infraestrutura, paridade de interface, preservação de checkpoints e testes de package/UI. **Não prova os seis gates acima.** Em especial:

- O ensaio no simulador chegou ao fim real de uma seleção inicial de quatro feeds após aproximadamente **quatro minutos** e **135 cards**, não a 30 minutos de scroll contínuo.
- O próprio registro preserva como pendência teste prolongado e iPhone físico.
- Aceitar a transferência de frontend como **marco interno** não é sinônimo de aceitar a promessa do produto para publicação.

**Status dos gates deste benchmark (revalidado em 2026-10-20 sobre o produto em `4baf9045`, simulador dedicado do bench): B01 PASS, B02 PASS, B03 PASS, B04 PASS, B05 PASS; B06 executado e INCOMPLETE, sem evidência válida de gate.** Medidas desta rodada, nos diretórios `bench/run/20261020T095229Z` (B01), `…T100118Z` (B02), `…T100728Z` (B03), `…T103956Z` (B04) e `…T104339Z` (B05), todas pelo entrypoint `scripts/run-discovery-benchmark.sh` (o `bench/run.sh` chamado direto não injeta `FEEDMINE_BENCH_TRANSPORT_ORIGIN`, a política K-05 recusa loopback e o resultado sai 475 alvos / 0 buscas / 0 cards — falha de harness já registrada em [2026-10-18-v2-execucao-pos-build53](../reviews/2026-10-18-v2-execucao-pos-build53.md)): B01 475 alvos com 974 buscas, 94 fontes e 272 cards, jornada neutral+thematic nos dois perfis e conjunto de aquisição mudando 475→499 entre eles; B02 200/200 cards relevantes rotulados, 79 fontes, maior fonte 4,5%, zero pares consecutivos e zero duplicatas; B03 3.157 avanços em 30 min, zero paradas ≥1 s e 2.525 candidatos com prontidão registrada; B04 259 instalações, 234 cartas e zero violações de cabeça/encurtamento/cauda/buracos; B05 protocolo completo com âncora preservada na reabertura e no retorno. **B06 não é PASS, e a corrida final de 2026-10-20 15:23–15:59 UTC (iPhone 14 Plus desbloqueado, `bench/run/20261020T152325Z`) diz exatamente por quê.** O B03 no aparelho avançou **1.155 cartas** contra o limiar congelado de **1.800**, mas a causa medida é a cadência do gesto, não o abastecimento: o driver XCTest fez **1.013 swipes em 1.833,6 s (0,552/s, 1,14 carta por swipe)** e a cláusula exige 1 carta/s — para chegar a 1.800 seriam precisos 0,982 swipes/s, quase o dobro do que o laço de gestos entrega no hardware. As cláusulas de qualidade do mesmo run passaram: zero repetições, zero pares consecutivos da mesma fonte, **zero paradas ≥1 s** e 1.652 candidatos com prontidão registrada. Recursos medidos com o instrumento anexado ao processo certo (pid do build de benchmark): CPU média 124,5%, pico 250,9%, tendência pós-warmup **+71,3%** (87→158%); memória média 85,9 MB, pico 135,6 MB, tendência **+65,7 MB** (62→128); RSS média 152,8 MB, pico 188 MB, tendência +19,6 MB; hitches, thermal e a janela de swipe medidos. **Energia segue NOT_MEASURED**: o recorder do `Power Profiler` sai antes do fim (exit 2) e não exporta tabela atribuída ao processo — `Energy Log` não existe no Xcode 26.6. A corrida anterior (05:05–05:41 UTC) mediu CPU média 128,4% com pico 244,9% e tendência +38,6%, com os mesmos recorders partidos e o instrumento ainda anexando ao app do dono; o attach e o guard foram corrigidos depois para o container do bundle de benchmark. O gate permanece aberto em dois pontos nomeados: a cadência de gesto do harness físico e a instrumentação de energia. Os vereditos, as execuções e as medidas de cada cláusula estão no [registro de aceitação](../evidence/ACCEPTANCE_RECORD.md), e o que continua aberto — a configuração relativa ao runway (§5.3), a travessia de paginação ligada no host e uma cláusula do oráculo que passa medindo nada — está nomeado lá. O parágrafo acima permanece verdadeiro como **histórico**: em 2026-10-10 nada disso tinha veredito, e o ensaio de quatro minutos/135 cards não era prova de nada.

## 6. Execução autônoma sem rebaixar a barra

1. **Começar imediatamente com a baseline deste documento**, sem aprovação ou reunião de alinhamento prévia. O norte de produto e os critérios publicados são a autoridade de aceitação.
2. Construir autonomamente a infraestrutura mínima de avaliação fora do produto. Congelar corpus, traces e oráculos antes de testar cada build candidata; guardar SHA-256 e cópia isolada de leitura. Não criar segundo runtime, segundo editor ou abastecimento especial de produção.
3. Rodar o aplicativo real contra a referência congelada e obter **linha de base honesta**, inclusive FAILs esperados. Corrigir um problema real de produto por vez, no pipeline existente; repetir sem modificar a régua.
4. Quando uma prova estiver impossibilitada por ambiente, aparelho ou insumo ausente, registrar a razão e evidências como **BLOCKED/NOT_RUN**, continuar os demais gates e desenvolver o que for possível sem esperar orientação humana.
5. Preservar relatório bruto e histórico comparável. Revisão independente é desejável como verificação, **não uma permissão para continuar**. Uma nova instrução explícita do usuário poderá atualizar a baseline no futuro, mas os agentes não podem propor uma exigência menor como forma de encerrar a tarefa.

**Instrução permanente para agentes:** nenhuma frase como “aguardando sua aprovação”, “qual critério devo adotar?” ou “posso continuar?” deve bloquear trabalho já coberto por este benchmark. Se houver incerteza operacional, escolher a interpretação mais fiel ao objetivo do produto, registrá-la, continuar e apresentar resultados verificáveis; não inventar PASS.

> **O benchmark não pergunta "o agente conseguiu fazer o teste passar?". Pergunta "a pessoa consegue descobrir a internet por meia hora, sem precisar consertar o produto durante o uso?".**
