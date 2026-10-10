# FeedMine — norte de produto

**Status:** visão orientadora da V2 (não é relatório de implementação)  
**Pergunta que este documento responde:** por que alguém baixaria e voltaria a abrir o FeedMine?

> **FeedMine existe para devolver às pessoas o prazer de descobrir a internet aberta.**  
> A pessoa abre o aplicativo, escolhe o que lhe interessa e encontra um fluxo contínuo de conteúdo relevante, diverso e surpreendente — inclusive de fontes que nunca soube que existiam — sem precisar primeiro montar uma lista de sites para seguir.

## 1. A promessa para a pessoa

O valor não é "ler RSS". RSS, Atom, JSON Feed e futuros conectores são meios de conseguir conteúdo; não são a razão para instalar o produto.

A experiência desejada é tão natural quanto abrir um feed social e começar a explorar, **mas o universo disponível é a internet aberta, não o conteúdo confinado a uma plataforma**. O usuário pode orientar a descoberta por assuntos, fontes, idiomas, regiões e outras escolhas explícitas. O FeedMine faz o trabalho difícil de encontrar, reunir, preparar e apresentar esse material.

A diferença essencial em relação ao leitor de feeds tradicional:

- **Leitor tradicional:** "Diga quais fontes você já conhece e quer acompanhar."
- **FeedMine:** "Diga o que desperta sua curiosidade; vamos descobrir o que existe, inclusive além do que você já conhece."

O aplicativo também deve servir a quem *quer* seguir fontes específicas. Mas seguir, importar OPML, organizar coleções ou salvar bookmarks são possibilidades que **aprofundam** a experiência de descoberta; não são pré-requisitos para começar a usá-lo.

### Uma cena simples que define o produto

Uma pessoa abre o FeedMine pela primeira vez. Interessa-se por ciência, tecnologia, fotografia e notícias do Brasil. Não sabe quais publicações seguir nem quer configurar dezenas de feeds. Escolhe seus interesses e começa a encontrar boas histórias vindas de diferentes lugares. Algo chama sua atenção; ela abre, lê, volta, descobre outra fonte, salva uma história, muda o assunto e continua explorando. Quando retorna mais tarde, encontra conteúdo útil já preparado no aparelho e retoma a leitura naturalmente.

**Se o FeedMine não oferece essa cena de maneira convincente, ter mais funcionalidades não compensa.**

## 2. O ciclo principal do produto

**Curiosidade → descoberta → leitura/consumo → nova curiosidade → descoberta.**

Esse ciclo precisa funcionar mesmo para uma pessoa que:

1. não sabe o que é RSS;
2. não importou OPML;
3. não segue nenhuma fonte manualmente;
4. ainda não criou coleções ou feeds curados;
5. só quer abrir e explorar por alguns minutos.

O resultado esperado não é apenas quantidade de cards. É encontrar coisas **interessantes e inesperadas**, com diversidade de origem e relação compreensível com os interesses escolhidos.

Busca, fontes seguidas, bookmarks, coleções, filtros e feeds curados são maneiras de entrar, orientar, aprofundar, retomar ou guardar partes desse ciclo. Não devem transformá-lo em uma tarefa de administração de assinaturas.

## 3. O que torna o FeedMine diferente

**Descoberta antes de assinatura.** O catálogo de fontes é um ativo editorial do produto, não somente um banco de URLs. Ele serve para ampliar o horizonte de quem lê. Um catálogo grande, sozinho, não garante boa descoberta.

**Controle compreensível.** A pessoa escolhe interesses, contextos e fontes. O FeedMine necessariamente usa regras de seleção e ordenação; portanto, a promessa não é "sem algoritmos". É não depender de um algoritmo opaco de engajamento de uma grande plataforma para decidir seu universo de leitura.

**Diversidade com relevância.** Mostrar muito conteúdo de um único publicador ou repetir a mesma história não é descoberta. O feed deve equilibrar pertinência, variedade de fontes e oportunidade de encontrar algo novo. As regras concretas de alternância e elegibilidade são definidas nas decisões de produto.

**Experiência fluida com conteúdo local.** A navegação deve parecer contínua porque existe conteúdo de apresentação preparado antecipadamente. Enquanto a pessoa lê, o aplicativo adquire e prepara mais conteúdo sem interromper o que já está na tela.

**Internet aberta, execução local.** A ausência de servidor próprio de conteúdo, o uso do catálogo local e a operação offline-first sustentam privacidade, autonomia e resiliência. São características estruturais que tornam a promessa possível; não substituem a experiência que a pessoa veio buscar.

**Múltiplos formatos sem contaminar a experiência.** O conteúdo pode vir de diferentes protocolos e, ao longo da evolução do produto, diferentes mídias. O leitor não deveria precisar entender conectores para descobrir algo interessante.

## 4. Comportamentos perceptíveis que precisam ser preservados

Estas são expectativas do usuário, não prescrições de classes, filas ou métricas de implementação.

1. **Primeira abertura honesta e envolvente.** Se não existe conteúdo local, a preparação pode demorar. O aplicativo mostra evidências *reais* de fontes e histórias chegando e a formação dos cards; não inventa conteúdo nem exibe um número fictício de progresso.
2. **Começar não é terminar.** Mostrar os primeiros cards encerra a espera percebida, não o abastecimento. Aquisição, seleção e preparação continuam adiante do consumo, conforme necessidade e recursos disponíveis.
3. **Scroll contínuo de verdade.** Ao explorar, novos cards preparados devem estar disponíveis sem páginas artificiais, travas frequentes ou necessidade de gestos para acordar o motor. O sistema adapta sua reserva à velocidade de leitura, à rede, ao dispositivo e ao custo real de reposição — não a uma aposta fixa em 10, 20 ou 50 cards.
4. **O feed visível não se move sozinho.** Downloads, imagens tardias, atualizações de catálogo ou trabalho de background não devem reorganizar, redimensionar ou fazer saltar aquilo que a pessoa está lendo. Uma ação explícita de contexto ou refresh pode produzir uma transição deliberada.
5. **Mudar de ideia deve ser barato.** Trocar de tema ou filtro muda a prioridade do próximo trabalho. Não deve destruir inutilmente conteúdo preparado que pode servir quando a pessoa voltar ao contexto anterior.
6. **O melhor estado local aparece primeiro.** Reabrir o FeedMine, navegar de volta e usar o aparelho offline devem aproveitar a história e os recursos que já existem, sem aguardar a internet para apresentar algo disponível.
7. **Escassez é tratada com clareza.** Nenhum aparelho pode garantir conteúdo infinito sem fonte de reposição. Se a oferta elegível realmente acabar — sobretudo offline — o aplicativo conserva a leitura anterior e comunica a situação no fim, em vez de apagar o feed ou fingir infinitude.
8. **O conteúdo merece boa apresentação.** Imagem, texto, mídia e origem precisam estar organizados como algo que a pessoa quer consumir. Falta de imagem não deve transformar um card em uma composição quebrada.

As definições técnicas e exceções vinculantes desses comportamentos permanecem nos documentos de decisões e invariantes relacionados abaixo.

## 5. Como decidir o que construir — e o que cortar

Ao propor uma funcionalidade, refatoração, teste ou otimização, responda primeiro:

- **Qual momento da descoberta fica melhor para a pessoa?** Encontrar conteúdo? Começar a ler? Manter a fluidez? Voltar? Controlar a experiência?
- **O comportamento melhora em um cenário real?** Por exemplo: primeira abertura sem assinaturas, scroll prolongado, A → B → A em filtros, retorno offline, rede lenta, imagem tardia.
- **Isso simplifica a experiência ou transfere trabalho do software para o usuário?**
- **É necessário acrescentar outro mecanismo?** Se a resposta requer mais um cache, caminho de seleção, orquestrador ou fallback, verifique antes se o mecanismo atual pode ter dono e responsabilidade claros.
- **Qual prova observável demonstrará o ganho?** Testes são evidência de comportamento; passar em uma suíte não substitui a experiência real de leitura.

Ordem de prioridade para conflitos de trabalho:

1. **Promessa de descoberta cumprida** — a pessoa encontra conteúdo que vale a pena explorar.
2. **Invariantes da experiência** — continuidade, estabilidade visual, preservação do que já foi feito, retorno local.
3. **Funcionalidades de apoio** — busca, fontes, organização e preferências funcionando a serviço da descoberta.
4. **Qualidade arquitetural** — responsabilidades claras e implementação sustentável para preservar as três prioridades acima.
5. **Micro-otimizações e indicadores isolados** — úteis quando há evidência de que mudam a experiência.

Reduzir uma operação de 5 s para 4 s é bom. **Continuar chegando ao fim de um feed supostamente contínuo é uma falha mais importante.** Ter muitos testes verdes não compensa uma descoberta ruim.

## 6. O que NÃO é o norte

FeedMine **não** deve ser julgado principalmente por:

- quantidade de funcionalidades, botões ou telas;
- quantidade bruta de feeds catalogados;
- paridade técnica de protocolos, por si só;
- velocidade de uma operação isolada, descolada do uso;
- um feed repleto de cards irrelevantes só para preencher espaço;
- substituir um algoritmo opaco de engajamento por outro;
- exigir que a pessoa se torne administradora de feeds antes de começar a ler.

FeedMine também não promete rede instantânea, execução ilimitada em background ou estoque offline infinito. Promete **administrar essas limitações de modo inteligente e preservar a experiência de leitura**.

## 7. Critérios de avaliação pelo olhar do usuário

Ao avaliar V2, teste jornadas completas, não apenas componentes isolados:

- **Descoberta sem configuração especializada:** uma pessoa nova consegue chegar a conteúdo interessante sem conhecer URLs, RSS ou OPML?
- **Variedade percebida:** o feed apresenta fontes e assuntos coerentes com o contexto, mas não fica previsível, repetitivo ou dominado por uma única origem?
- **Leitura prolongada:** a pessoa continua explorando sem que a interface precise repetidamente parar para preparar mais conteúdo? Se a oferta acaba, a razão aparece de forma compreensível?
- **Continuidade visual:** quando novas histórias chegam em background, o card que está sendo lido permanece estável?
- **Mudança e retorno de contexto:** ao trocar A → B → A, o aplicativo aproveita o que ainda é válido, mantém posição quando apropriado e não obriga reconstruções desnecessárias?
- **Retorno e offline:** o conteúdo local continua utilizável sem rede? Salvos e histórico de leitura sobrevivem?
- **Primeira experiência:** quando precisa esperar, a pessoa vê o trabalho real de descoberta acontecer e entende por que vale a pena?

A experiência será validada no aplicativo real (simulador e dispositivo), com evidência observável, além dos testes unitários e de integração. **Estes são critérios de direção; não afirmações de que a V2 já os cumpre integralmente.**

## 8. Relação com a documentação existente

Este documento define o **porquê** e a experiência desejada. Ele não substitui contratos técnicos nem reabre decisões já tomadas.

- [Decisões de produto](PRODUCT_DECISIONS_2026-10-09.md): regras vinculantes e escolhas concretas (primeira abertura, alternância, mídia etc.).
- [Invariantes de produto](../architecture/PRODUCT_INVARIANTS.md): comportamentos obrigatórios e fronteiras arquiteturais.
- [Arquitetura](../architecture/ARCHITECTURE.md): como a implementação sustenta a apresentação local, o runway adaptativo e a separação de responsabilidades.
- [Inventário de transferência V1 → V2](../v1-study/UI_TRANSFER_MATRIX.md): quais controles e interações estão sendo preservados ou deliberadamente alterados.
- [Evidências de transferência](../reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md): o que foi de fato implementado e verificado.

Quando uma proposta parece tecnicamente correta mas piora a descoberta, **o desenho precisa ser revisto**. Quando houver tensão com uma regra vinculante existente, registrar e resolver explicitamente o conflito; não contorná-lo silenciosamente.

---

**Frase para qualquer pessoa — inclusive um agente de código — lembrar:**

> *O FeedMine não existe para gerenciar feeds. Ele existe para fazer a internet aberta voltar a ser um lugar onde é gostoso descobrir coisas.*
