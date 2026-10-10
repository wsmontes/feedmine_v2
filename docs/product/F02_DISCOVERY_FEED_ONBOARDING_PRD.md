# F02 — Primeiro contato: o feed que apresenta a internet e conhece o leitor
## Especificação de produto e experiência (PRD)

**Status:** especificação de produto vigente para orientar execução autônoma.  
**Data:** 2026-10-10. **Frente:** F02 — primeira abertura, onboarding e tempo até a primeira descoberta.  
**Natureza:** define **o que a pessoa vê, entende, escolhe e recebe**. Não é desenho de arquitetura, plano de tarefas técnicas nem autorização para simplificar expectativas de produto.  
**Alinhamento obrigatório:** [Norte de produto](PRODUCT_NORTH_STAR.md), [Benchmark de aceitação](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [Mapa de dez frentes](PRODUCT_AUDIT_10_FRONTS.md), [Decisões de produto](PRODUCT_DECISIONS_2026-10-09.md).

> **Visão:** o usuário não preenche um questionário para depois usar o FeedMine. Ele **entra no feed**. O próprio feed apresenta, com histórias reais, a variedade de coisas que a internet aberta oferece e convida a pessoa a dizer, de forma explícita e opcional, **“quero mais disso”** ou **“não é minha praia”**. Descobrir conteúdo e descobrir seus interesses são a mesma experiência contínua.

### 1. Problema de produto que estamos resolvendo

A primeira experiência não deve pressupor que a pessoa entende RSS, escolheu fontes, tem uma lista de assinaturas ou sabe descrever precisamente seus interesses. O produto deve despertar curiosidade **antes** de solicitar trabalho.

Um onboarding convencional que exibe um Composer de idiomas, assuntos, equilíbrio editorial, intensidade de exploração e formatos exige escolhas abstratas sem antes demonstrar o resultado. O leitor tem de imaginar o que o FeedMine poderia oferecer. Pior: uma configuração pode parecer personalizada, mas continuar limitada às poucas fontes inicialmente cadastradas.

**Não basta copiar o onboarding da V1 ou reproduzir seus controles.** O requisito é que a pessoa experimente o diferencial do FeedMine imediatamente: descobrir algo que desconhecia, oriundo de uma fonte que provavelmente não procuraria sozinha.

### 2. Promessa e resultado esperado

Ao abrir o aplicativo pela primeira vez, a pessoa deve poder dizer: **“Já estou explorando a internet. O FeedMine me mostrou assuntos e fontes diferentes; quando demonstrei interesse, comecei a receber mais descobertas nessa direção. Não precisei configurar um leitor.”**

A experiência deve cumprir simultaneamente:

- **Descoberta imediatamente compreensível:** histórias reais, atraentes, de assuntos variados e fontes identificadas.
- **Aprendizado declarado pelo leitor:** controles explícitos e compreensíveis, integrados ao próprio feed.
- **Sem obrigação de configurar:** é possível rolar, abrir histórias e continuar sem responder nada.
- **Surpresa preservada:** preferências orientam a exploração sem aprisionar o leitor numa bolha.
- **Controle e confiança:** a pessoa sabe o que um voto significa, pode rever preferências e não perde a posição.
- **Um único produto:** após as primeiras interações, a experiência continua sendo o mesmo feed, sem trocar para outro modo de navegação.

**O scroll vertical permanece o gesto principal. Não é Tinder, quiz, carrossel de escolhas nem sequência de telas obrigatórias.**

### 3. Público e estados de entrada

**P01 — Leitor novo e curioso:** não conhece RSS, não segue nenhuma fonte e quer começar sem configuração. Deve entrar no feed exploratório sem barreira.

**P02 — Leitor com interesse claro:** ao encontrar um assunto específico, declara preferência por mais ou menos. O conteúdo futuro responde a isso, mas continua oferecendo novidades fora do tema.

**P03 — Leitor que não quer ser interrogado:** ignora todos os convites, rola e lê normalmente. O produto não interpreta silêncio nem scroll rápido como rejeição.

**P04 — Leitor que já usa FeedMine:** ao reabrir, recupera seu feed e suas preferências. Não volta ao tour, exceto por escolha explícita; ainda pode ajustar interesses a qualquer momento.

**P05 — Pessoa sem conexão ou com rede lenta:** vê o melhor conteúdo local disponível antes de depender da internet; quando não há material local, recebe uma espera honesta e acionável. O FeedMine não finge possuir histórias.

### 4. Conceito: um feed normal, com uma voz editorial

O aplicativo possui uma **voz editorial** que pontua histórias verdadeiras e comunica as possibilidades de descoberta, sem substituir essas histórias por publicidade sobre o próprio app.

A pessoa pode encontrar, ao longo do mesmo feed:

- Uma reportagem de ciência: **“A internet tem descobertas que parecem ficção. Quer encontrar mais coisas assim?”**
- Uma notícia de celebridades: **“Sim, também tem fofoca. Não vamos fingir que todo mundo só lê ciência.”**
- Um artigo de nicho sobre restauração de relógios: **“Tem uma comunidade inteira fascinada por isso. Você entraria nesse universo?”**
- Uma reportagem internacional: **“O que está acontecendo do outro lado do mundo também pode surpreender você.”**
- Fotografia, quadrinhos, cultura, arte, tecnologia, gastronomia, natureza ou outros campos — sempre acompanhados de **conteúdo efetivamente existente**, não de uma promessa vazia.

Esses textos são **exemplos de tom e intenção editorial**, não headlines de artigos, não catálogo fechado de assuntos e não permissão para inventar fatos. Cada intervenção deve ser pertinente ao assunto do material associado. A voz pode ser divertida, curiosa, inteligente e levemente irreverente, **nunca debochada com tragédias, sofrimento, grupos sociais ou pessoas vulneráveis**.

A primeira amostra precisa mostrar variedade real. Não pode apresentar apenas quatro publicadores conhecidos e chamar isso de universo da internet aberta. Notícias, fofocas, especialidades e descobertas inesperadas são **possibilidades**, não uma ordem rígida, uma proporção fixa ou dez cards obrigatórios.

### 5. Jornada principal — do primeiro toque à leitura cotidiana

#### 5.1. Primeira abertura

1. A pessoa abre o FeedMine; vê a identidade do produto e uma mensagem breve que a situa: **“A internet é muito maior que os lugares que você costuma visitar. Vamos explorar?”**
2. O **próprio feed** é o destino principal, já com a rolagem e os controles comuns do aplicativo. Não há formulário, obrigação de escolher um assunto nem explicação longa bloqueando a navegação.
3. O idioma de apresentação parte da preferência do aparelho, com possibilidade de alteração compreensível; a pessoa não precisa conhecer códigos de idioma.
4. O FeedMine apresenta histórias reais de diferentes campos conforme ficam prontas. Se precisar preparar a primeira sequência, a espera mostra indícios reais: nomes de fontes, manchetes efetivamente obtidas, conteúdo preparado — nunca percentuais inventados nem promessas de duração.
5. A primeira história já pode ser aberta, salva ou compartilhada como qualquer outra. A pessoa não precisa “terminar o onboarding” antes de usar o produto.

#### 5.2. Convites contextuais dentro do feed

Quando uma história ilustra um universo de interesse, aparece **um comentário curto do FeedMine**, ligado visualmente àquela história ou ao pequeno conjunto editorial imediatamente associado.

A estrutura de cada convite é:

1. **Possibilidade descoberta** — frase de personalidade que apresenta o universo.
2. **História real** — card com título, fonte, conteúdo e mídia reais quando disponíveis.
3. **Ação opcional e explícita** — dois botões do mesmo nível de hierarquia: **“Quero mais disso”** e **“Não é minha praia”**.
4. **Continuação natural** — rolar continua funcionando, com ou sem escolha.

O convite nunca encobre o artigo, exige resposta, bloqueia o scroll, dispara um modal ou sequestra um gesto lateral. Se o usuário escolher uma ação, a confirmação é discreta e a leitura continua exatamente onde estava.

**Distinção visual obrigatória:** o comentário é claramente uma intervenção editorial do FeedMine, separado do título e da autoria do publicador. Não pode parecer que o site escreveu a frase do aplicativo.

#### 5.3. Aprendizado ao longo da experiência

- **“Quero mais disso”** significa: *explore mais histórias e outras fontes relacionadas a esse universo*. Não é uma assinatura do publicador e não equivale a curtir publicamente uma postagem.
- **“Não é minha praia”** significa: *dê menos prioridade a esse tipo de conteúdo*. É um sinal de preferência, **não um bloqueio permanente**, não uma rejeição do autor e não uma exclusão automática de tudo que tenha palavras parecidas.
- **Não responder** significa **nenhuma preferência declarada**; o FeedMine continua oferecendo variedade.
- **Abrir, ler, salvar ou compartilhar** continuam ações normais sobre a história. Não devem ser disfarçadas de voto explícito nem convertidas em rejeição se não acontecerem.
- Se o leitor tocar por engano, há uma opção simples de **“Desfazer”** junto à confirmação.
- Respostas devem produzir diferença perceptível na descoberta **futura**: mais ou menos histórias pertinentes, inclusive de fontes novas que a pessoa ainda não conhece. Não basta trocar uma etiqueta ou apenas reordenar uma lista fixa de assinaturas.

Se o card puder representar mais de um tema, a interface deve deixar claro **qual universo** está sendo escolhido. Ex.: “Mais **astronomia**”, não um “mais disso” cujo significado só o aplicativo conhece. O título curto dos botões pode permanecer genérico se o texto/contexto tornar inequívoco o assunto.

#### 5.4. A transição para o uso habitual

O aprendizado inicial **não possui número mínimo de votos nem botão obrigatório de conclusão**. A pessoa já está usando o FeedMine.

Conforme o usuário se familiariza, os comentários didáticos tornam-se menos presentes **sem interromper o feed nem mudar a navegação**. Preferências continuam acessíveis e editáveis; uma pessoa que gosta dos convites pode optar por receber sugestões de novos universos de exploração.

Há sempre uma forma clara de **“Ocultar dicas de descoberta”** — oculta as intervenções de onboarding, **não** restringe o conteúdo e não reinicia a experiência. As dicas não voltam de forma intrusiva após reiniciar o app. Uma opção **“Conhecer o FeedMine”** permite reencontrá-las voluntariamente.

Os controles avançados — equilíbrio editorial, alcance da exploração, filtros de idioma e tipos de mídia — permanecem disponíveis após o primeiro contato em **Preferências de descoberta**. Não são exigidos para começar. Toda opção oferecida deve produzir o comportamento correspondente; caso não possa ser honrada, não deve aparecer como funcional.

### 6. Composição visual e hierarquia

**A tela principal continua sendo o feed vertical do FeedMine.** Não criar uma experiência visual separada que depois descarte a posição e carregue um segundo feed.

**Cabeçalho:** identidade FeedMine e acesso discreto a interesses/preferências, busca e outras ações pertinentes. Um sinal inicial não intrusivo pode indicar **“Descobrindo sua internet”**, sem simular análise pessoal ou progresso fictício.

**Card editorial:** mantém a identidade do conteúdo: título da publicação, nome da fonte, data/contexto, imagem real quando disponível ou layout intencional de texto, e ação normal de leitura. A intervenção do FeedMine é distinguível por rótulo ou tratamento tipográfico próprio, sem parecer uma notícia independente.

**Pergunta contextual:** breve, em linguagem natural, associada ao assunto real do card. Não excede visualmente o peso da história. As ações **“Quero mais disso” / “Não é minha praia”** devem ser legíveis e acionáveis por toque, teclado e tecnologia assistiva. Não utilizar exclusivamente ícones de coração ou polegar para uma decisão que afeta **assuntos futuros**, não a postagem atual.

**Feedback do voto:** discreto e imediato. Ex.: **“Entendido. Vamos explorar mais astronomia.”** ou **“Entendido. Menos fofocas, mais espaço para outras descobertas.”** com **“Desfazer”**. Não aumentar pontuações, inventar estatísticas de aprendizagem nem celebrar desinteresse.

**Ausência de resposta:** nenhuma alteração visual obrigatória; o card não fica “pendente”, não reaparece como cobrança e não ocupa o lugar de outra história.

**Ritmo editorial:** convites são ocasionais, contextualizados e úteis; o feed não pode virar uma sequência de perguntas a cada card. Não impor contagem fixa ou cronograma artificial. O valor primário de cada tela é **descobrir e consumir conteúdo**.

**Privacidade da apresentação:** mostrar o motivo compreensível de uma sugestão quando útil (ex.: **“Você pediu mais ciência”**). Não afirmar que a pessoa “ama” um tema por ter passado por um card.

**Mídia:** nunca mostrar uma miniatura falsa ou reserva visual quebrada para promover uma categoria. Falta de imagem resulta em um card de texto bem composto. Uma imagem tardia não altera a geometria de conteúdo que já está sendo lido.

### 7. Linguagem, personalidade e texto de interface

**Voz:** curiosa, próxima, culta sem ser acadêmica, leve sem virar piada o tempo todo. O FeedMine é um guia de exploração, **não** um influenciador, uma autoridade que julga gostos ou um algoritmo que diz conhecer a pessoa melhor do que ela.

**Regras de redação:**
- Preferir palavras comuns: **assuntos, histórias, fontes, descobrir, explorar**. Evitar RSS, crawler, ingestão, pesos, modelo, algoritmo, embeddings, assinatura como requisito técnico.
- Convites em primeira pessoa do plural podem funcionar com parcimônia: **“Olha o que encontramos”**; evitar personificação invasiva como **“Estou te observando”**.
- Ser explícito na consequência: **“Mais histórias desse assunto”**, **“Menos desse assunto”**. Evitar “Curtir” sem explicar o impacto sobre a descoberta.
- Não sugerir que uma preferência é definitiva. A pessoa muda de opinião sem punição.
- Humor permitido com fofocas, hobbies e descobertas curiosas; **tom factual e respeitoso** com violência, morte, calamidade, saúde e temas vulneráveis. Nesses casos pode não haver comentário brincalhão.
- Não confundir conteúdo editorial do FeedMine com texto do publicador nem inventar citações, manchetes, fontes ou exemplos em forma de notícia.
- Os textos precisam ser localizáveis no idioma da interface; exemplos em português não significam forçar português a quem usa inglês. Manter sentido, intenção e tom, não traduções literais de piadas.

**Vocabulário-base proposto (português):**

| Ocasião | Texto |
| --- | --- |
| Primeira orientação | **“A internet é muito maior do que parece. Vamos explorar?”** |
| Convite à escolha | **“Quer encontrar mais histórias desse tipo?”** |
| Preferência positiva | **“Quero mais disso”** |
| Preferência negativa | **“Não é minha praia”** |
| Esclarecimento | **“Isso muda o que o FeedMine vai procurar daqui para a frente.”** |
| Confirmação positiva | **“Boa! Vamos buscar mais sobre {assunto}.”** |
| Confirmação negativa | **“Entendido. Vamos mostrar menos {assunto}.”** |
| Reversão | **“Desfazer”** |
| Ajuste posterior | **“Meus interesses”** |
| Suprimir intervenções | **“Ocultar dicas de descoberta”** |
| Revisitar o guia | **“Conhecer o FeedMine”** |
| Aguardando conteúdo real | **“Indo atrás de histórias para você”** |
| Sem rede nem conteúdo local | **“Ainda não temos histórias salvas aqui. Conecte-se para começar a explorar.”** |

**Amostras de tom (não slogans obrigatórios):**
- Ciência: *“Uma descoberta dessas faz a gente querer saber o que mais existe por aí.”*
- Fofoca: *“Também temos fofoca. A curiosidade humana não vem com manual.”*
- Nicho: *“Um universo inteiro dedicado a esse detalhe. A internet é maravilhosa por isso.”*
- Viagem/cultura: *“Outros lugares, outras histórias. Quer explorar mais desse lado do mundo?”*
- Temas graves: sem brincadeira — *“Uma reportagem importante sobre {assunto}. Quer acompanhar mais desse tema?”*

### 8. Relevância, surpresa e descoberta: comportamento prometido

A seleção inicial deve representar **amplitude verdadeira**, não apenas fontes convencionais de notícias. O FeedMine apresenta universos acessíveis e nichos inesperados, contextualizados ao idioma do usuário e às possibilidades reais de conteúdo.

As preferências explícitas **orientam a descoberta contínua**: quando a pessoa pede mais astronomia, devem surgir histórias pertinentes também de fontes antes desconhecidas. Pedir menos notícias de celebridades deve reduzir sua participação futura, sem virar bloqueio irrevogável, e sem apagar conteúdos já publicados.

A exploração mantém uma parcela perceptível de surpresa fora das preferências declaradas. O FeedMine não deve exagerar uma única resposta até monopolizar o feed. A relevância e a diversidade obedecem aos critérios globais [B01/B02](DISCOVERY_ACCEPTANCE_BENCHMARK.md) e às decisões de alternância existentes; este documento não autoriza enfraquecê-las.

**Importante:** demonstrar um interesse **não** adiciona uma fonte à lista de assinaturas. Seguir um publicador deve ser uma ação distinta, consciente e reversível, disponível quando a pessoa quiser.

### 9. Estados difíceis e resposta ao usuário

| Situação real | Comportamento exigido |
| --- | --- |
| Há material local | Mostrá-lo imediatamente, sem aguardar atualização remota. |
| Instalação realmente vazia | Preparação com fatos reais de fontes/histórias chegando; primeira história disponível assim que pronta. |
| Rede lenta | Não inventar promessa de “pronto em X segundos”; permitir leitura dos itens já preparados. |
| Sem conexão e sem cache | Explicação clara, sem tela falsa de feed, com caminho para tentar novamente quando houver rede. |
| Pouca variedade disponível | Expor histórias reais, reduzir intervenções que prometam variedade inexistente e continuar procurando; escassez honesta ao esgotar. |
| Uma fonte falha | Não transformar a falha isolada em erro genérico do produto se outras histórias estão disponíveis. |
| O usuário rejeita um tema | Não remover, mover ou redimensionar cards já visíveis; não interpretar isso como bloqueio de um publicador. |
| O usuário erra o toque | Oferecer “Desfazer” e reverter a preferência declarada. |
| O usuário não vota | Scroll e leitura intactos; nenhuma conclusão negativa inferida de silêncio. |
| O usuário fecha e volta | Recuperar posição, histórias e escolhas; não reiniciar o guia obrigatório. |
| Um artigo toca em múltiplos temas | Deixar identificável sobre qual assunto a resposta age; não esconder ambiguidades atrás de ícones. |
| Tema sensível | Frase respeitosa ou nenhum comentário, sem humor deslocado ou coerção emocional. |
| Conteúdo sem imagem | Card text-only completo e legível, nunca notícia ou ilustração inventada. |
| Idioma do conteúdo indisponível | Não fingir ter opções no idioma escolhido; oferecer ajuste claro sem falsificar metadados. |

### 10. Interesses e transparência após o primeiro uso

**Meus interesses** é um lugar simples para a pessoa revisar aquilo que **ela declarou**: assuntos com preferência por mais ou menos, sem score secreto exibido como verdade. Deve poder desfazer ou mudar escolhas. A interface distingue **“assunto que quero explorar”** de **“fonte que escolhi seguir”**; uma não substitui a outra.

Ajustes mais granulares são **progressive disclosure**: encontram-se quando o usuário os procurar, e não são o preço de entrada no produto. O FeedMine pode oferecer explicações simples de por que está mostrando um tipo de história, sem insinuar análise de personalidade ou perfis compartilhados.

A experiência deve funcionar **localmente e sem criar uma conta**. O produto não exige rede social, login nem concessão de rastreamento externo para a pessoa expressar gostos.

### 11. O que o produto NÃO deve virar

- Formulário de interesses obrigatório antes do feed.
- Tinder de cards, deck de swipe para aceitar/rejeitar ou tela de quiz.
- Tour que termina em uma **mudança de aplicativo ou de modelo de navegação**.
- Série de cards inventados, comentários sem histórias reais ou falsos títulos para representar categorias.
- Feed de quatro fontes antigas com novos rótulos de personalização.
- Sistema que considera rolagem rápida um **“não gostei”**.
- Sistema que exige número mínimo de votos, retenção ou tempo de uso para “aprender”.
- Votação que **reordena a lista visível** ou muda tamanho de cards já apresentados.
- Likes públicos, contagem social, perfis de engajamento ou gamificação de respostas.
- Controle “somente podcasts” / “sem vídeo” que não consegue cumprir literalmente sua promessa.
- IA generativa obrigatória para escrever frases de onboarding: o produto precisa de **mensagens editoriais verdadeiras**, não de geração on-line nem de uma camada de tecnologia específica.

### 12. Histórias de usuário e critérios de aceitação observáveis

**US-01 — Começar sem configurar.** Dada instalação limpa, quando a pessoa abre o FeedMine, então entra em uma experiência de feed com conteúdo real ou preparação honesta; não precisa conhecer fontes, tocar em configurações ou responder perguntas.

**US-02 — Mostrar amplitude.** Com oferta elegível ampla e variada, a pessoa encontra histórias de temas e publicadores distintos que demonstram a pluralidade prometida, sem depender exclusivamente de quatro feeds iniciais. A prova global de fontes elegíveis/contribuintes é o B01.

**US-03 — Preferência positiva tem consequência.** Ao selecionar “Quero mais disso” em um assunto identificável, depois de continuar explorando, a pessoa recebe maior presença de histórias pertinentes, inclusive de fontes novas, comparada a uma execução equivalente sem essa preferência.

**US-04 — Preferência negativa tem consequência.** Ao selecionar “Não é minha praia”, a presença futura do assunto diminui em comparação ao mesmo cenário sem voto, sem apagar o passado nem proibir toda surpresa.

**US-05 — Não participar é válido.** Uma pessoa pode percorrer e consumir o feed sem votar uma vez sequer, e nunca recebe solicitação obrigatória para prosseguir.

**US-06 — Escolher não desloca a leitura.** Depois de responder, baixar mídia ou receber novas histórias, a posição e a geometria do card que está sendo lido permanecem estáveis; obedecer B04.

**US-07 — Reverter é simples.** Um voto feito por engano pode ser desfeito, e a preferência efetiva acompanha a reversão.

**US-08 — O sistema não atribui falsamente preferências.** Rolar, passar um card sem abrir ou voltar ao app não aparece como voto negativo em “Meus interesses”.

**US-09 — O comentário é editorial, não a notícia.** A interface e as opções de acessibilidade distinguem perfeitamente voz do FeedMine, autoria da publicação e botão de preferência.

**US-10 — Retornar não reinicia a conversa.** Após fechar e reabrir o app, o usuário retoma a leitura e suas escolhas; dicas ocultadas não reaparecem como imposição; obedecer B05.

**US-11 — Controles avançados são verdadeiros.** Toda opção oferecida na interface de personalização deve produzir exatamente o efeito que seu texto promete, ou não ser oferecida.

**US-12 — O conteúdo continua chegando.** A experiência inicial não termina em uma seleção finita disfarçada. Sob oferta elegível suficiente, o feed mantém continuidade conforme B03, independentemente de quantos votos forem feitos.

**US-13 — A linguagem respeita contexto.** As frases são compreensíveis no idioma da interface, acessíveis por VoiceOver e não brincam com tragédias ou sofrimento.

**US-14 — Sem histórias, sem invenções.** Se falta rede e conteúdo local, a experiência informa o limite; não injeta histórias demonstrativas no feed para cumprir o tour.

### 13. Como avaliar e o que significa sucesso

**Avaliação de produto, não de compilação:** testar duas pessoas fictícias ou perfis distintos com a mesma disponibilidade de conteúdo, um votando explicitamente em alguns assuntos e outro apenas rolando. Verificar diferenças **reais e futuras** no conteúdo/fontes; não basta checar se o controle mudou de cor ou se a receita foi gravada.

Observar também uma pessoa que escolhe repetidamente “menos”, uma que desfaz votos, uma com mídia indisponível, alguém com VoiceOver/texto grande e alguém que entra e sai durante o primeiro carregamento.

Os requisitos B01–B06 do benchmark geral continuam em vigor, sem redução de duração, diversidade ou estabilidade. Se a fonte real não permite uma prova, usar cenário externo de aceitação fiel ao produto; **não** substituir a experiência pela aprovação de funções internas.

A Frente F02 recebe **PASS** somente quando as histórias US-01 a US-14 pertinentes forem demonstradas no aplicativo real e registradas com evidência reproduzível. Falha, recurso ausente ou teste não executado recebe seu status real. **Não existe aprovação intermediária humana para continuar a implementação; os agentes executam autonomamente de acordo com esta especificação.**

### 14. Limites e relação com as outras frentes

- **F01 — descoberta automática de fontes:** garante que existe diversidade de fontes reais para cumprir esta experiência. F02 define o que o usuário vê e escolhe; não define como F01 organiza suas responsabilidades internas.
- **F04 — curadoria:** garante relevância e diversidade de histórias resultantes das escolhas.
- **F05 — continuidade:** garante que a leitura iniciada durante o onboarding não pare ao esgotar um estoque arbitrário.
- **F06 — interface:** garante cards, mídia, geometria e acessibilidade.
- **F07 — busca e filtros:** garante que preferências e contextos continuem ajustáveis.
- **F09 — offline e persistência:** garante que escolhas e história sobrevivam à reabertura.

**Esta é uma mudança intencional de direção de produto em relação ao Welcome → Composer obrigatório que a V2 transferiu da V1.** Preservar o que funciona nessa experiência não significa manter a obrigação de configurar antes de descobrir. Não há exigência de preservar o Composer como porta de entrada; os ajustes avançados permanecem disponíveis por escolha.

---

**Definição de sucesso em uma frase:** a pessoa começa a rolar um feed genuinamente interessante, descobre a variedade da internet aberta, diz com naturalidade onde quer explorar mais ou menos, e percebe o FeedMine responder — **sem deixar de ser um feed em nenhum momento**.
