# FeedMine V2 — benchmark independente de aceitação do produto (proposta 0.1)

**Estado: PROPOSTA, AINDA NÃO APROVADA PELO PRODUCT OWNER.**  
**Tipo:** contrato de aceitação *black-box* da experiência, não um plano de arquitetura.  
**Norma de leitura:** [Norte de produto](PRODUCT_NORTH_STAR.md); [decisões vinculantes](PRODUCT_DECISIONS_2026-10-09.md); [invariantes](../architecture/PRODUCT_INVARIANTS.md).

> **Pergunta única:** alguém consegue abrir o FeedMine, escolher interesses e explorar conteúdo relevante da internet aberta continuamente, inclusive de fontes desconhecidas, sem configurar manualmente uma lista de feeds e sem o aplicativo acabar prematuramente ou mexer na leitura?

Este benchmark é deliberadamente **mais exigente que a validação técnica de componentes**. Seu objetivo é detectar quando uma implementação satisfaz testes locais mas deixa de entregar a promessa do produto.

## 1. Regra de autoridade: o agente implementa; não redefine o sucesso

- **Product owner aprova os critérios, corpus, versões e futuras alterações.** Este texto é uma proposta até essa aprovação.
- O agente executor pode alterar código, otimizações e testes unitários, mas **não** critérios, duração, composição do corpus, oráculos, trace de consumo, parâmetros de rede, classificação de resultados ou exclusões de cenários para alcançar um PASS.
- Uma mudança no benchmark exige decisão explícita registrada pelo product owner, com justificativa, diferença e histórico de versões. **Falhou → reduzimos a exigência** não é um caminho autorizado.
- O avaliador deve operar **fora do código de produção que está sendo avaliado**. No mínimo: fixture, manifesto SHA-256, driver de interação e oráculos mantidos em uma cópia controlada pelo product owner ou revisor independente. Um manifesto versionado no mesmo repositório facilita a consulta, mas **não protege de manipulação se o mesmo agente tiver permissão de escrita nele**.
- Não aceitar alterações de fixture ou do runner originadas do patch de implementação; executá-lo contra a referência congelada. Sem CI hospedada obrigatório: pode rodar localmente em máquina macOS com Xcode e em aparelho físico, usando evidências reproduzíveis.
- **PASS / FAIL / NOT_RUN / BLOCKED** são os únicos resultados de um gate. NOT_RUN ou BLOCKED **não** equivalem a PASS. Uma exceção pode encerrar um marco interno se expressamente autorizada, **mas não aprova a release pública**.
- Não trocar testes de experiência por equivalentes de componente; não marcar "o método foi chamado" como prova de "o leitor recebeu conteúdo".

## 2. Preparação do corpus e do avaliador

Dois ambientes obrigatórios, com papéis distintos:

**A. Corpus de aceitação determinístico, desconhecido do agente durante o desenvolvimento.**  
Catálogo e conteúdo capturados a partir de fontes reais e anonimizados/redistribuídos conforme licenças, servidos por um transporte local de teste **externo ao aplicativo**, que reproduz protocolos, atrasos e falhas. Sem mock da lógica do FeedMine, sem inserir cards diretamente no SQLite, sem pré-instalar história publicada. O aplicativo real percorre: catálogo → resolução de fontes → aquisição → admissão → seleção → mídia → publicação → sessão → UI.

Pré-condições explícitas da versão proposta do corpus: **pelo menos 300 fontes elegíveis para cada perfil principal e 5.000 itens distintos elegíveis**, com metadados rotulados independentemente (tema, idioma, região, fonte, artigo canônico, revisão material, mídia). Incluir fontes rápidas e lentas, RSS/Atom/JSON Feed quando suportados, duplicatas entre publicadores, respostas vazias, falhas intermitentes e mídia lenta. O corpus deve revelar seus totais ao avaliador antes da execução — não ao pipeline por uma rota especial. A preparação do corpus ainda precisa ser implementada; **não alegar que já existe**.

**B. Ensaio live com internet e catálogo de produção.**  
Mesma jornada feita por uma pessoa no app, em aparelho físico com redes reais. Serve para detectar compatibilidade, latência, curadoria e limites que fixtures não revelam. Não substitui A, porque sites reais podem ficar indisponíveis. Deve registrar se um fim de feed é genuíno ou ocorreu apesar de haver conteúdo elegível.

Em ambos, congelar a versão do aplicativo, commit, build, catálogo, perfil, corpus, traces, rede, device, iOS, critérios e horário. Registrar eventos e resultados brutos para auditoria. Um algoritmo alternativo criado exclusivamente para o benchmark invalida a prova.

## 3. Gates P0: todos obrigatórios, nenhum compensado por média ou nota global

### B01 — Descoberta sem assinatura (o verdadeiro primeiro uso)

**Entrada:** instalação limpa; catálogo disponível; usuário escolhe dois interesses, um conjunto explícito de idiomas e uma região; **zero seleção manual de fontes, zero OPML**.

**Obrigatório:**
- A experiência produz um feed útil a partir do catálogo, sem depender exclusivamente das quatro fontes padrão nem exigir "Fontes → adicionar" como etapa escondida.
- No cenário rico do corpus, **pelo menos 50 fontes distintas entram automaticamente no conjunto de aquisição elegível**, e **pelo menos 20 fontes distintas contribuem com os primeiros 300 cards**. Esses valores são condições do *teste de capacidade de descoberta*, não quotas ou lotes fixos do runtime.
- A escolha de idioma/assunto efetivamente altera o conteúdo e as fontes consultadas; repetir a jornada com outro perfil muda a seleção de modo explicável.
- O onboarding apresenta evidência real durante a preparação e não fabrica títulos, imagens nem progresso.

**FAIL típico:** o app exibe cards bonitos mas consulta somente a lista estática de quatro feeds; a receita apenas reordena essa lista.

### B02 — Relevância, variedade e identidade editorial

**Entrada:** o mesmo corpus rotulado, primeiro conjunto de 200 cards publicados sob um perfil com múltiplas fontes elegíveis.

**Obrigatório:**
- **≥80% dos 200 cards** correspondem aos interesses/idiomas declarados, de acordo com o rótulo externo aprovado; a distribuição de relevância por assunto/idioma é publicada junto do resultado.
- **≥20 fontes distintas** aparecem; nenhuma fonte representa **>15%** dos cards quando o corpus oferece alternativas.
- **Zero pares de cards consecutivos da mesma fonte** em contexto multi-fonte (PD-4), incluindo fronteiras de segmentos.
- **Zero duplicatas de artigo canônico** apresentadas como descobertas novas na mesma edição; uma edição material segue a decisão PD-1 e é contada separadamente.
- Nunca inflar diversidade com nomes falsos, reatribuição fictícia de fonte ou repetição de cards para preencher a contagem.

**Observação:** os limiares de 80%, 20 e 15% são *propostas* para a primeira versão do benchmark; fixá-los somente após aceite do product owner, **não** após ver a pontuação da implementação.

### B03 — Runway real: 30 minutos de consumo, não 30 minutos com app aberto

**Entrada:** instalação limpa em contexto rico com ≥5.000 itens elegíveis; replay externo de **30 minutos de avanços efetivos**, a **1 card por segundo**, com rajadas de até **3 cards por segundo durante 20 segundos a cada 5 minutos**, usando gestos/scroll nativos. Fontes rápidas e lentas, aquisição variável e mídia tardia. O corpus deve ter oferta suficiente para o trace inteiro.

**Obrigatório:**
- Cada avanço previsto pela trilha alcança o próximo card distinto; o total de cards efetivamente consumidos deve corresponder ao trace, não a um contador de gestos disparados.
- **Zero fim artificial de feed**, tela vazia, retorno ao início, repetição para disfarçar falta de supply ou loading que substitua a história visível enquanto ainda há conteúdo elegível disponível.
- **Zero paralisação visível ≥1 segundo causada por falta de runway**, no ambiente controlado da versão aprovada do benchmark.
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

**Obrigatório:** sem crash, terminação por memória, travamento de interface ≥1 segundo, vazamento de recurso com crescimento sustentado não explicado durante uso prolongado ou salto/duplicação de cards. Coletar RSS do processo, CPU, memória, energia/térmica, frame hitches e tempo de scroll; reportar picos e tendência após aquecimento. Valores adicionais de orçamento de memória/energia devem ser aprovados pelo product owner com evidência de aparelho, jamais inventados para obter PASS.

**NOT_RUN** se não houver aparelho. Simulador não aprova esse gate.

## 4. Relatório obrigatório por execução

Um relatório único para cada build, com:

1. **Identidade imutável da execução:** commit/SHA, configuração e hashes externos de catálogo/corpus/runner, dispositivo, rede, perfis e janela temporal.
2. **Matriz B01–B06:** PASS/FAIL/NOT_RUN/BLOCKED com resultado observado, expectativa congelada, artefato de evidência e motivo do desvio.
3. **Provas de ponta a ponta:** fluxo de onboarding, fontes selecionadas automaticamente, quantidade de fontes efetivamente contactadas/contribuintes, relevância, diversidade, cards originais, runway por minuto, avanço real, continuidade visual, restauração e recursos.
4. **Sinais de manipulação:** mudança no runner/fixture/oráculos; pré-povoamento do banco; seleção manual de feeds não autorizada; limitação de catalog query ou fonte; trace encurtado; repetição sintética; mock do componente avaliado; ajustes ocultos por build flag.
5. **Conclusão:** release liberada somente se **todos** os gates P0 estiverem PASS na versão aprovada do benchmark. Um relatório honesto pode terminar em FAIL; ele é muito mais útil que um PASS falso.

## 5. Estado inicial honesto da V2 em 2026-10-10

O [registro atual de validação](../reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md) prova avanços de infraestrutura, paridade de interface, preservação de checkpoints e testes de package/UI. **Não prova os seis gates acima.** Em especial:

- O ensaio no simulador chegou ao fim real de uma seleção inicial de quatro feeds após aproximadamente **quatro minutos** e **135 cards**, não a 30 minutos de scroll contínuo.
- O próprio registro preserva como pendência teste prolongado e iPhone físico.
- Aceitar a transferência de frontend como **marco interno** não é sinônimo de aceitar a promessa do produto para publicação.

**Status provisório dos gates deste benchmark: B01 NOT_RUN, B02 NOT_RUN, B03 NOT_RUN, B04 NOT_RUN como protocolo completo (há testes parciais), B05 NOT_RUN como protocolo completo (há testes parciais), B06 NOT_RUN.** Não retroconverter testes parciais em aprovação.

## 6. Como sair da proposta sem rebaixar a barra

1. Product owner aprova ou modifica este texto **antes** de ser executado sobre uma build candidata. Ajustes se justificam pela promessa ao usuário e pela capacidade do cenário, não pelo que o código atual já faz.
2. Congelar corpus, traces e oráculos fora do alcance de escrita do agente executor; guardar SHA-256 e cópia controlada.
3. Construir somente a infraestrutura mínima para repetir a jornada **usando o aplicativo real**. Não criar segundo runtime, segundo editor ou outra forma de abastecimento de produção.
4. Rodar primeiro para obter **linha de base honesta**, com FAILs esperados. Resolver um problema de produto de cada vez no pipeline existente.
5. Rodar novamente sem alterar a régua. Terceiro revisor ou product owner compara a versão anterior dos contratos e os resultados brutos.

> **O benchmark não pergunta "o agente conseguiu fazer o teste passar?". Pergunta "a pessoa consegue descobrir a internet por meia hora, sem precisar consertar o produto durante o uso?".**
