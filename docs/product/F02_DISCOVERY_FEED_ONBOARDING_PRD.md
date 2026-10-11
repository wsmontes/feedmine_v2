# F02 — Primeiro contato: conhecer o mundo, descobrir a internet, descobrir o próprio gosto
## Especificação de produto e experiência (PRD) — revisão 2, 2026-10-10

**Estado:** especificação vigente de **experiência de produto**, refinada com as decisões expressas pelo product owner e a verificação direta da V1. **Não** é especificação de implementação, plano de classes, instrução para transplantar código da V1 ou alegação de que a V2 já passou nos testes.

**Autoridade:** [Norte de produto](PRODUCT_NORTH_STAR.md), [decisões de produto](PRODUCT_DECISIONS_2026-10-09.md), [benchmark de aceitação](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [dez frentes](PRODUCT_AUDIT_10_FRONTS.md). Os critérios B01–B06 não são reduzidos por esta revisão. A execução é autônoma: nenhuma aprovação humana intermediária deve bloquear investigação, implementação, medição ou correção.

> **A experiência em uma frase:** a pessoa responde duas perguntas simples — **em quais idiomas quer ler** e **quais lugares quer acompanhar** — e entra imediatamente em um **feed de conteúdo real, excelente e variado**. O próprio FeedMine, às vezes com humor, mostra as possibilidades da internet e pergunta, sem interromper o scroll, se ela quer explorar mais ou menos cada universo.

## 1. Intenção do produto

A primeira abertura tem duas obrigações, nessa ordem de confiança:

1. **Demonstrar que o FeedMine apresenta a internet de verdade.** A pessoa reconhece que está diante de excelentes reportagens, histórias, publicações e fontes legítimas — inclusive nomes conhecidos —, não de uma coleção de blogs obscuros, conteúdo antigo, feeds quebrados ou uma “internet secreta”.
2. **Transformar curiosidade em descoberta pessoal.** A pessoa experimenta assuntos diferentes e pode orientar a próxima exploração sem conhecer RSS, procurar feeds, assinar provedores ou preencher um formulário de interesses.

A qualidade e a confiança da **primeira impressão** têm prioridade sobre exibir o assunto mais específico possível. Diversidade, independência e surpresa continuam essenciais, mas **dentro de um padrão alto de qualidade**, não como desculpa para expor conteúdo ruim.

**Não posicionar o produto como “a internet que escondem de você”, “conteúdo proibido” ou alternativa conspiratória às publicações tradicionais.** A promessa é abrir a internet existente e ampliar os caminhos para explorá-la.

## 2. Jornada: duas perguntas curtas, depois o feed de verdade

### 2.1. Tela inicial de orientação

**Mensagem de abertura, curta:** “A internet tem muito mais para oferecer. O FeedMine ajuda você a descobrir.”

O primeiro acesso apresenta somente dois grupos de escolhas simples, na mesma tela ou em dois passos curtos. **Não perguntar assuntos, temas favoritos, fontes, peso editorial, nível de descoberta ou formatos de mídia nesse momento.**

**Pergunta A — “Em quais idiomas você quer ler?”**

- Seleção de **vários idiomas ao mesmo tempo**; por exemplo, **Português** e **Inglês**.
- A sugestão inicial vem dos idiomas do aparelho quando possível, claramente editável. O idioma da **interface** não é obrigatoriamente o idioma de todas as histórias.
- Mostrar nomes de idiomas escritos para pessoas, nunca códigos técnicos; permitir encontrar outro idioma sem percorrer uma lista interminável.
- Não presumir que falar português significa querer somente notícias do Brasil, nem que morar no Canadá significa querer somente notícias em inglês.

**Pergunta B — “Quais lugares você gostaria de acompanhar?”**

- Seleção de **vários países ou regiões de interesse**; por exemplo, **Canadá**, **Brasil** e **China**.
- Explicação curta: “Para encontrar histórias sobre esses lugares — e continuar descobrindo o resto do mundo.”
- **Lugar de interesse** não é sinônimo de idioma, localização física atual, nacionalidade ou país onde fica o servidor da fonte. Uma matéria **sobre a China publicada em inglês** deve continuar sendo uma possibilidade válida para alguém que escolheu China e inglês.
- Não exigir GPS, acesso à localização, conta, cidadania nem adivinhar países a partir de dados privados. O idioma ou a região do aparelho podem sugerir opções, nunca impor escolha.
- **“Mundo todo”** é um estado compreensível quando não há lugar específico escolhido; escolher lugares aumenta a prioridade desses destinos, sem eliminar a descoberta global.
- Quando o FeedMine **não consegue distinguir com evidência** o lugar tratado por uma história do local do publicador, não deve afirmar que encontrou “notícias sobre a China” só porque a fonte foi catalogada naquele país. Preferir informação verdadeira e variedade a precisão geográfica fingida.

**Ação principal:** **“Começar a explorar”**. A pessoa pode aceitar as sugestões ou alterá-las. Não precisa escolher quantidade mínima de países, nem assunto algum. Se nenhuma seleção geográfica for feita, começa com “Mundo todo”; para idiomas, oferecer uma sugestão inicial utilizável que pode ser trocada a qualquer momento.

**Tempo de atenção exigido:** somente o necessário para responder/confirmar essas duas perguntas. Não adicionar tela obrigatória de boas-vindas após elas, tour longo nem segunda etapa de preferências.

### 2.2. Preparação honesta, se necessária

Assim que a orientação acaba, a pessoa vai **direto ao feed vertical normal** do FeedMine. Se não houver histórias locais prontas, mostrar uma preparação breve **baseada em fatos reais**: fontes efetivamente consultadas, títulos reais chegando e cards realmente preparados. Não usar porcentagem fictícia, títulos fabricados nem promessas de segundos.

Assim que houver uma sequência inicial apresentável e diversificada, publicar para leitura. A descoberta e a preparação de mais histórias **continuam durante o scroll**; não esperar terminar uma exploração completa do catálogo. O trabalho posterior não altera os cards já apresentados.

**Cobertura progressiva (PD-8):** publicar a primeira sequência encerra somente a espera inicial, não a exploração. Fontes elegíveis do catálogo inteiro continuam tendo oportunidades ao longo do uso conforme capacidade e prioridades reais. Idiomas selecionados são filtro determinante e não são relaxados para gerar surpresa. Lugares e interesses orientam a exploração sem transformar o catálogo em shortlist fixa. Todos os orçamentos de aquisição e preparação são relativos às condições observadas, sem cotas numéricas permanentes; o feed visível conserva prioridade.

### 2.3. O primeiro feed é uma demonstração editorial, não uma pesquisa

O feed inicial apresenta excelentes histórias de universos diferentes: notícias e análises, ciência, cultura, entretenimento, tecnologia, esporte, sociedade, artes, natureza, curiosidades e eventualmente um nicho fascinante. As possibilidades reais variam de acordo com conteúdo disponível, idiomas e lugares escolhidos. **Não há ordem fixa de categorias, quotas, páginas temáticas, número obrigatório de cards por assunto nem lista fechada de publicadores.**

A pessoa deve encontrar **alguns nomes reconhecíveis** como sinais legítimos de familiaridade e confiança, ao lado de veículos especializados ou independentes **igualmente bons**. Um grande veículo não ganha direito de dominar o feed; uma excelente fonte pequena não é punida por não ser famosa.

A sequência é **intercalada naturalmente** no scroll, sem blocos de dez notícias de um assunto seguidos por dez de outro. Não é um catálogo visual de categorias: é um feed genuinamente interessante **mesmo se ninguém responder aos convites**.

## 3. Política editorial da primeira impressão

### 3.1. Três qualidades distintas

**A. Evidência prévia sobre a fonte.** Aproveitar a pesquisa e a classificação já presentes no catálogo: descrição, tags extraídas da análise de conteúdo, assuntos, idioma, formato, atividade, natureza, data da última publicação conhecida, sinal de habilitação para descoberta e pontuação de qualidade.

**B. Credibilidade/editorialidade.** Tratar separadamente reputação editorial, vínculo institucional ou científico, especialização, clareza de autoria/publicador, utilidade pública e independência editorial. Veículos conhecidos podem facilitar a confiança inicial, mas fama não é sinônimo de precisão, neutralidade ou qualidade.

**C. Qualidade da história atual.** O artigo que chega agora precisa ter conteúdo real, título compreensível, origem rastreável, link utilizável, apresentação íntegra, relevância e temporalidade apropriada. Uma boa fonte pode publicar um item fraco; uma fonte menos conhecida pode publicar uma história excelente.

**Regra de honestidade:** a pontuação numérica do catálogo **não comprova credibilidade, verificação factual nem boa experiência em todos os artigos**. Não chamar um artigo de “verificado” ou um publicador de “confiável” apenas porque um algoritmo reconheceu palavras no nome ou porque o score técnico é alto.

### 3.2. O que merece aparecer primeiro

Na primeira impressão, privilegiar histórias que:

- Venham de fontes elegíveis, com histórico editorial ou especialização identificável e atividade compatível com seu tipo de conteúdo.
- Sejam genuinamente **boas de ler ou consumir**, não apenas coletadas com sucesso; tenham link funcional, título informativo, texto/descrição suficiente e autoria/origem transparente.
- Respeitem idioma escolhido e considerem os lugares de interesse, sem reduzir a internet ao país de residência da pessoa.
- Equilibrem atualidade com conteúdo atemporal de valor. **Notícias antigas apresentadas como atuais são inadequadas**; um excelente ensaio histórico ou arquivo evergreen pode ser apropriado, com contexto e data honestos.
- Ofereçam assuntos e perspectivas diversos, sem repetição excessiva de fonte, tema, artigo ou formato.
- Evitem clickbait enganoso, agregadores que obscurecem a origem, spam comercial, anúncios disfarçados de artigos, links quebrados e relatos sensacionalistas escolhidos apenas para provocar reação.

**Não transformar uma imagem em condição de qualidade.** Histórias com imagem real bem preparada podem causar ótima primeira impressão, mas um artigo excelente sem imagem deve receber **card text-only intencional e elegante**. Imagem ausente ou tardia não pode quebrar o layout. Não inventar ilustração, manchete ou publicação para preencher uma categoria.

**Conteúdo sensível:** assuntos graves podem aparecer quando relevantes, mas o onboarding não deve privilegiar material gráfico ou explorar tragédias para obter votos. A linguagem editorial, se existir, permanece respeitosa.

### 3.3. Como apresentar amplitude sem perder credibilidade

A primeira curadoria procura conscientemente **fontes e assuntos diferentes**: tradicionais e independentes, abrangentes e especialistas, locais e internacionais, atuais e atemporais, populares e surpreendentes. Deve ser uma amostra **convincente da internet real**, não um desfile de fontes raras só para parecer diferente.

**A primeira aquisição não pode ser determinada apenas por quais feeds responderam mais rápido.** A experiência deve buscar qualidade e diversidade de contribuintes enquanto mantém um primeiro conteúdo utilizável tão cedo quanto possível.

Quando a pessoa expressa um interesse, a exploração do catálogo passa a procurar **novas fontes** relacionadas, e não apenas reordenar as poucas fontes já consultadas. A qualidade da apresentação continua protegida quando o assunto se torna especializado.

**Escassez real:** se o conteúdo qualificado para um idioma/lugar não existe ou está temporariamente indisponível, não relaxar silenciosamente para spam e links ruins. Usar histórias boas de outras partes do universo permitido, indicar limites com honestidade e continuar a busca. Nunca prometer cobertura geográfica que o conteúdo não comprova.

## 4. A voz do FeedMine dentro do feed

O FeedMine apresenta possibilidades enquanto a pessoa rola. A **história real vem primeiro**; comentários curtos e ocasionais funcionam como intervenções editoriais distinguíveis do texto do publicador.

Exemplos de **tom** — **não manchetes inventadas nem sequências obrigatórias**:

- Ciência: **“É impressionante o que a gente descobre quando olha um pouco mais longe.”**
- Cultura: **“A internet também é feita de histórias que você nem sabia que queria ler.”**
- Entretenimento: **“Sim, também tem fofoca. A curiosidade não exige diploma.”**
- Nichos: **“Existe um universo inteiro dedicado a isso. Quer explorar?”**
- Geografia: **“O que acontece do outro lado do mundo pode ter muito a ver com você.”**
- Notícias graves: **“Uma reportagem importante sobre este assunto. Quer acompanhar mais?”** — ou simplesmente nenhum comentário.

**Tom:** curioso, inteligente, acessível e levemente irreverente, não infantil, sarcástico com o leitor, moralizante nem conspiratório. O FeedMine não sugere que alguém “esconde” notícias ou que oferece uma internet alternativa. **“A internet tem muito mais para oferecer”** é o enquadramento do produto.

### 4.1. Composição da intervenção

1. Card verdadeiro: título, fonte, história, data e mídia real se houver.
2. Pequena intervenção visualmente identificada como **“FeedMine sugere”** (ou tratamento equivalente).
3. Pergunta ocasional sobre o universo **identificável** do conteúdo: **“Quer descobrir mais sobre astronomia?”**
4. Duas ações claramente rotuladas: **“Quero mais disso”** e **“Não é minha praia”**.
5. Scroll prossegue mesmo que não haja escolha; não transformar cada card em questionário.

**Se a história abordar vários temas, explicitar qual assunto o voto altera** (por exemplo, “Mais astronomia” em vez de um “mais disso” ambíguo). Pode não haver convite quando o assunto é ambíguo ou sensível.

A fala editorial jamais pode ser confundida com citação, opinião ou manchete atribuída ao veículo de origem. Comentário e botões não escondem o artigo, não exigem resposta, não abrem modal e não sequestram o gesto de scroll.

## 5. Aprender com respostas declaradas, nunca com adivinhação

- **“Quero mais disso”**: aumentar o interesse editorial em **histórias e fontes novas relacionadas a esse universo**.
- **“Não é minha praia”**: diminuir a prioridade **futura** desse universo, **sem bloquear definitivamente** o assunto, o site ou o continente.
- **Não tocar em nada**: não há voto. Rolar, passar rápido ou não abrir um artigo **não significa desgostar**.
- **Abrir, ler, salvar, compartilhar**: continuam ações sobre a história; não são votos explícitos de personalização.
- **“Desfazer”**: reverte uma resposta feita por engano, sem penalidade nem reinício do feed.
- **Persistência:** “Meus interesses” mostra as preferências que a pessoa declarou e permite alterar ou retirar respostas. Não exibir score secreto como se fosse uma verdade psicológica.
- **Assuntos ≠ assinaturas:** gostar de astronomia **não inscreve o usuário em centenas de sites**. Seguir uma fonte individualmente é uma escolha consciente, separada e reversível.
- **Mudança futura, não retroativa:** novas respostas orientam **o próximo conteúdo adquirido, escolhido e preparado**. Não apagam nem reorganizam cards já publicados, não deslocam o scroll e não invalidam trabalho local que ainda pode ser útil.

Um voto positivo deve produzir diferença **perceptível e verificável** em relação a uma sessão equivalente sem aquele voto. Essa diferença deve alcançar o universo de **fontes exploradas**, não ser só um badge, uma cor de botão ou um novo sort dentro das mesmas quatro fontes.

Mesmo após vários votos, o FeedMine preserva descoberta fora das preferências; o usuário não fica preso a uma bolha. **Quem nunca votar também merece um ótimo feed.**

## 6. Experiência visual e controles

**Antes do feed:** a orientação de idiomas e lugares é limpa, breve e acessível: texto curto, sugestões pré-selecionáveis, múltipla escolha, indicativo claro do que será acompanhado e botão principal **“Começar a explorar”**. Não mostrar percentuais de personalização, ranking, scores de fontes ou “taxa de aprendizado”.

**No feed:** interface vertical normal. Títulos e fontes reais são protagonistas. Cards sem imagem são completos e bem desenhados. A intervenção editorial é discreta e claramente própria do FeedMine; botões de voto aparecem apenas quando existe um assunto identificável e uma pergunta útil.

**Depois de um voto:** confirmação pequena, próxima ao card: **“Entendido. Vamos procurar mais sobre {assunto}.”**, ou **“Entendido. Menos {assunto} nas próximas descobertas.”**, com **“Desfazer”**. Não afirmar que o próximo card já será daquele tema; a descoberta leva o tempo real necessário.

**Uso habitual:** o primeiro contato não tem número mínimo de votos, tutorial para “concluir” nem troca para uma segunda interface. Intervenções didáticas ficam menos frequentes sem interromper o feed. **“Ocultar dicas de descoberta”** deve ser possível sem desativar histórias ou escolhas já registradas; **“Conhecer o FeedMine”** permite revisitá-las voluntariamente.

**Preferências posteriores:** entradas compreensíveis para **“Idiomas e lugares”**, **“Meus interesses”** e, quando disponíveis e verdadeiramente funcionais, filtros e ajustes editoriais avançados. Não exibir controle cujo efeito prometido o aplicativo não pode cumprir.

**Acessibilidade e localização:** todos os controles funcionam com VoiceOver, Dynamic Type, contraste adequado e alvos de toque confortáveis. Idiomas de interface e conteúdo permanecem independentes. Textos e humor são localizáveis pelo sentido, não pela tradução literal.

## 7. Linguagem de interface — texto de referência

| Momento | Texto |
| --- | --- |
| Introdução | **“A internet tem muito mais para oferecer. O FeedMine ajuda você a descobrir.”** |
| Pergunta de idiomas | **“Em quais idiomas você quer ler?”** |
| Pergunta de lugares | **“Quais lugares você gostaria de acompanhar?”** |
| Ajuda geográfica | “Mais histórias sobre esses lugares, sem deixar de explorar o mundo.” |
| Sem preferência geográfica | **“Mundo todo”** |
| Ação de entrada | **“Começar a explorar”** |
| Preparação | **“Indo atrás de histórias para você”** |
| Contexto de convite | **“Quer descobrir mais sobre {assunto}?”** |
| Ação positiva | **“Quero mais disso”** |
| Ação negativa | **“Não é minha praia”** |
| Explicação de consequência | “Sua resposta orienta as próximas descobertas.” |
| Confirmação positiva | “Vamos procurar mais sobre {assunto}.” |
| Confirmação negativa | “Vamos mostrar menos {assunto} daqui para a frente.” |
| Reversão | **“Desfazer”** |
| Revisão | **“Meus interesses”** / **“Idiomas e lugares”** |
| Ocultar guia editorial | **“Ocultar dicas de descoberta”** |
| Revisitar guia | **“Conhecer o FeedMine”** |
| Sem rede e sem histórias locais | “Ainda não temos histórias salvas aqui. Conecte-se para começar a explorar.” |

Evitar no texto público: RSS como requisito de entrada, “crawler”, “modelo”, “algoritmo secreto”, “fontes que não querem que você conheça”, “sua internet foi desbloqueada”, “já sabemos tudo sobre você” e alegações falsas de qualidade verificada.

## 8. Estados e limites que o produto precisa explicar

| Situação | Experiência exigida |
| --- | --- |
| Instalação limpa | Duas perguntas básicas → feed; sem seleção manual de fontes, OPML ou interesses temáticos obrigatórios. |
| Dois idiomas e três lugares | Todos permanecem válidos simultaneamente; China pode aparecer em inglês e Brasil em português; países não implicam idiomas. |
| País escolhido sem conteúdo diretamente verificável | Não inventar cobertura “sobre o país” baseada só na localização do publicador; buscar alternativas reais e comunicar disponibilidade. |
| “Mundo todo” | Descoberta geográfica ampla, não apenas veículos locais ou fontes nacionais do aparelho. |
| Sem voto | Feed interessante e variado; nenhuma inferência negativa a partir do scroll. |
| Muitos votos positivos no mesmo tema | Mais foco futuro **e** persistência de variedade; não monopolizar o feed. |
| Voto negativo / desfazer | Menos foco futuro / preferência revertida; histórico e cards visíveis preservados. |
| Um site grande domina resultados rápidos | Preservar variedade editorial e alternância de fontes; velocidade de rede não concede monopólio. |
| Artigo excelente, sem imagem | Card de texto completo, legível e estável; não excluir automaticamente por ser text-only. |
| Fonte de score alto, artigo ruim ou link quebrado | Não promovê-lo só pelo score; manter padrão de integridade da primeira impressão. |
| Fonte pequena excelente | Pode aparecer no primeiro feed junto às fontes conhecidas; fama não é condição de entrada. |
| Artigo antigo | Data/contexto claros; conteúdo evergreen pode ser valioso, notícia antiga não é apresentada como atual. |
| Sem rede, com conteúdo local | Mostrar primeiro a leitura local existente, sem reiniciar onboarding. |
| Sem rede, sem conteúdo local | Explicar a situação; não fabricar cards de exemplo. |
| Falha isolada de uma fonte | Continuar com outras fontes saudáveis; sem degradar a tela inteira se ainda há oferta. |
| Retorno ao app | Recuperar escolhas, contexto, leitura, posição e preferências, sem novo questionário obrigatório. |
| Conteúdo sensível | Tom respeitoso ou nenhum comentário lúdico; nada de humor com tragédia. |
| Idioma escolhido sem oferta suficiente | Ser honesto sobre escassez; permitir ajustar a seleção, não inventar histórias no idioma. |

## 9. Critérios de aceitação observáveis — histórias do usuário

**US-01 — Orientação mínima.** Em instalação limpa, aparecem somente **idiomas** e **lugares** como decisões iniciais. A pessoa consegue combinar idiomas e locais e começar, sem configurar assuntos ou fontes.

**US-02 — Independência geográfica e linguística.** Selecionando português+inglês e Canadá+Brasil+China, a experiência não confunde idioma com país: mostra, quando disponível e comprovado, conteúdo sobre cada lugar nos idiomas permitidos, inclusive sobre a China em inglês. Não usa país da fonte como prova automática do assunto da notícia.

**US-03 — Primeiro feed real e editorialmente convincente.** Com corpus rico, a primeira sequência contém histórias legítimas, legíveis, acessíveis e com fontes identificadas; combina veículos reconhecidos e boas fontes especializadas/independentes. Não depende apenas das quatro fontes padrão.

**US-04 — Qualidade não é um número.** Uma fonte com score técnico máximo, mas conteúdo promocional, link inválido ou artigo inadequado, não recebe privilégio indevido. Uma fonte boa de score técnico moderado e um artigo text-only excelente permanecem possíveis.

**US-05 — Atualidade com contexto.** Notícias ultrapassadas não são apresentadas como novidades; excelentes textos atemporais podem aparecer com datas e descrição honestas.

**US-06 — Diversidade sem quotas do produto.** O usuário encontra assuntos, fontes e perspectivas variados na ordem natural do scroll; nenhum grupo monopoliza a abertura por ser rápido de buscar ou famoso.

**US-07 — Sem obrigações após começar.** O primeiro feed funciona sem votos; histórias podem ser abertas, salvas e compartilhadas imediatamente; não existe gate para “concluir” onboarding.

**US-08 — Convites verdadeiros.** Comentários editoriais aparecem ligados a artigos reais, deixam a autoria clara e não fabricam manchetes ou imagens.

**US-09 — Preferência positiva efetiva.** Ao declarar “mais astronomia”, a exploração futura passa a consultar fontes pertinentes adicionais e a produzir mais histórias relacionadas do que uma execução equivalente sem resposta.

**US-10 — Preferência negativa efetiva.** Declarando “menos celebridades”, a frequência futura desse universo diminui, sem bloqueio irrevogável nem perda das histórias já publicadas.

**US-11 — Não resposta não significa rejeição.** Ignorar convites, passar um card ou não abri-lo não cria uma preferência negativa em “Meus interesses”.

**US-12 — Reversão e controle.** Um voto pode ser desfeito e ajustado depois; idioma e lugares podem ser alterados sem reinstalar e sem apagar conteúdo útil.

**US-13 — Scroll estável.** Votar, atualizar fontes, preparar mídia ou alterar preferências não move/reordena/redimensiona cards já apresentados; obedecer B04.

**US-14 — Persistência local.** Ao encerrar e reabrir, o usuário conserva lugar na leitura, dados salvos, idiomas, locais, votos e dicas ocultadas; obedecer B05.

**US-15 — Preparação honesta.** Sem conteúdo local, só aparecem fatos reais de aquisição/preparação, não percentuais, notícias ou imagens inventadas.

**US-16 — Descoberta contínua.** Mesmo após a primeira impressão, o feed mantém descoberta real de fontes e histórias conforme B01, B02 e B03; uma seleção inicial bem feita não pode mascarar um feed que termina.

**US-17 — Tom, sensibilidade e acessibilidade.** Textos são compreensíveis no idioma da interface, decisões são acessíveis e não há humor inadequado com violência, morte ou vulnerabilidade.

**US-18 — Ajustes cumprem a promessa.** Nenhum controle de idioma, lugar, assunto, formato ou foco editorial pode aparentar funcionar se sua consequência real não existe.

## 10. Prova de produto, sem prescrever implementação

A avaliação percorre **a jornada real no aplicativo**, não uma simulação de botões:

1. **Perfil A (exploração neutra):** instalação limpa, dois idiomas, múltiplos lugares, **nenhum voto temático**; verificar a excelência do primeiro contato, fontes reconhecíveis, amplitude, integridade de links, datas e cards text-only.
2. **Perfil B (preferências declaradas):** mesmos idiomas e lugares, depois votos positivos em **dois assuntos apresentados no próprio feed**, mais uma resposta negativa e uma reversão; comparar fontes realmente consultadas e a pertinência do conteúdo futuro com o perfil A, sem alterar o que já estava visível.
3. **Perfil C (independência de contexto):** mudar idiomas/lugares, inclusive país diferente do idioma; confirmar seleção e ausência de pressupostos geográficos falsos.
4. **Condições adversas:** rede lenta/ausente, fontes falhas, mídia ausente, artigo antigo, grande volume de fontes, retorno e VoiceOver.

**Avaliação qualitativa do primeiro contato:** inspetores devem abrir as histórias e verificar se conteúdo, origem, atualidade e acabamento são realmente bons. O score do catálogo **é entrada de curadoria, não oráculo de sucesso**. Registrar amostras aceitas/rejeitadas e motivos; não substituir inspeção de experiência por contagem de funções verdes.

**Critérios transversais:** B01 (fontes realmente descobertas), B02 (relevância/diversidade), B03 (30 min de consumo), B04 (feed visível estável), B05 (restauração/offline), B06 (iPhone real) permanecem obrigatórios **com seus limiares e duração originais**. A diferença de cenário é explícita: os **dois interesses temáticos** cobrados na prova de personalização são declarados **dentro do feed**, não como formulário inicial. Isso aumenta a fidelidade ao produto; não dispensa o teste de relevância.

**Estado:** estes são requisitos e provas a executar, não resultados já medidos na V2. Relatar PASS, FAIL, NOT_RUN ou BLOCKED honestamente; avançar autonomamente sem solicitar aprovação intermediária nem alterar a régua diante de uma falha.

## 11. Evidência histórica: o que a V1 já demonstrou — e o que NÃO se transfere

A V1 foi inspecionada diretamente em [wawasoft/feedmine](https://github.com/wawasoft/feedmine), e o [catálogo público](https://github.com/wawasoft/feed-repository) também foi consultado. Referências **de origem e comportamento**, não tarefas para copiar classes:

- [Curadoria do OPML](https://github.com/wawasoft/feedmine/blob/main/scripts/curate_opml_catalog.py): a pontuação chamada quality_score usa principalmente **descrição, tags, artigos analisados e nível de atividade**. Ela não certifica reputação editorial, precisão factual nem sucesso atual de HTTP. A curadoria separa conteúdo *current-sensitive* de *evergreen* e identifica fontes dormantes.
- [CuratedPreferenceEngine](https://github.com/wawasoft/feedmine/blob/main/feedmine/Services/CuratedPreferenceEngine.swift): avaliação editorial independente por sinais de publicação reconhecida, instituição, especialidade e propósitos editoriais; exclusões de agregação/promoção; repertório de veículos de referência para a apresentação inicial; diversidade por idioma, assunto, papel editorial, geografia e mídia. **Esses sinais são heurísticos**, não auditoria jornalística conclusiva.
- [FeedStore — seleção inicial](https://github.com/wawasoft/feedmine/blob/main/feedmine/Services/FeedStore.swift): o primeiro carregamento chama uma seleção de fontes do catálogo local e prepara conteúdo real. A presença de código e testes na V1 **não comprova** que a experiência completa satisfaz os novos requisitos da F02.
- [Catalog README](https://github.com/wawasoft/feedmine/blob/main/editorial/feed-curation/README.md): o snapshot reconciliado publicado tem **77.443 fontes canônicas** e trilha de proveniência/quarentena. O README geral da V1 menciona **88.084 fontes analisadas**, mas o [manifesto público verificado](https://github.com/wawasoft/feed-repository/blob/main/manifest.json) declara **77.443** no canal publicado. Não pressupor que os dois números representam o mesmo conjunto, ou que a V2 já embute um inventário maior sem verificar.

**Regra de aproveitamento:** recuperar **conhecimento editorial, taxonomia, evidências e contratos observáveis**, não importar os schedulers, caches, cotas de primeira página, estados ou caminhos paralelos acumulados na V1. A especificação não escolhe componentes, algoritmos, armazenamento ou etapas de execução.

## 12. O que não queremos construir

- Longo onboarding em que o usuário escolhe temas antes de poder descobrir uma história.
- Feed disfarçado de formulário, Tinder de cards, swipes binários ou quiz com respostas obrigatórias.
- “Internet alternativa”, promessa conspiratória ou seleção que parece uma coleção de links obscuros.
- Primeira impressão definida só por velocidade do feed, score técnico ou presença de imagem.
- Só grandes veículos, só fontes desconhecidas ou só notícias de última hora.
- País da fonte confundido com país sobre o qual a matéria fala; idioma confundido com residência.
- Lista fixa de publishers com uma fachada de personalização; novos votos só mudando cores e ordenação das mesmas fontes.
- Cards inventados para preencher categorias; links quebrados; informação velha passada como nova.
- Votos inferidos de silêncio/scroll; preferências irreversíveis ou que apagam trabalho visível.
- Um segundo motor de onboarding que entrega um feed diferente ao “terminar” a experiência.
- Exigência de IA generativa, conta, geolocalização ou serviço proprietário para curadoria.
- Metas artificiais de cards, fontes ou minutos **na implementação**; os limiares do **benchmark independente** continuam sendo verificações, não receitas de execução.

## 13. Fronteiras com as demais frentes

- **F01** deve encontrar e expandir fontes de verdade a partir do catálogo, também após preferências explicitadas.
- **F03** garante artigo utilizável, integridade da fonte e atualização apropriada.
- **F04** mantém qualidade, relevância, alternância e diversidade.
- **F05** mantém o runway adaptativo preparado enquanto o usuário consome.
- **F06** entrega cards bons, inclusive sem imagem, e posição estável.
- **F07** trata interesses/idiomas/lugares como preferências compreensíveis e ajustáveis.
- **F09** preserva material local, escolhas e reabertura.
- **F10** demonstra que a experiência funciona no dispositivo físico.

### Definição final de sucesso

> “Escolhi ler em português e inglês, acompanhar Canadá, Brasil e China e comecei a ver ótimas histórias de fontes reais — algumas conhecidas, outras novas. Fui dizendo do que queria mais ou menos, e o FeedMine começou a explorar novos caminhos, sem me tirar do meu feed e sem precisar aprender o que é RSS.”

## 14. Especificações derivadas de UX (F11–F20)

O primeiro feed não exige gestão de Sources ou OPML. Após o primeiro contato, a exploração por [fonte/região/assunto F12](F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md) é opcional; os votos «mais/menos» continuam preferências leves, distintos de [regras duráveis de exclusão F13](F13_CONTENT_CONTROL_EXCLUSIONS_UX_PRD.md); idiomas de conteúdo do onboarding não são a mesma coisa que [idioma dos controles F17](F17_LOCALIZATION_APPEARANCE_ACCESSIBILITY_UX_PRD.md); e retorno/novidades são descritos na [F20](F20_RETURN_FRESHNESS_LIFECYCLE_PRD.md). Consulte o [mapa de impactos](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md). Os casos US-01..US-18 e B01–B06 não são alterados por estes links.

---

## Referências externas de apoio — F02 (complementares, sem alterar os critérios de aceite):

Começar pelo feed real, com escolhas opcionais e evidências honestas de preparação.

- [HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding) — Evitar gate obrigatório de configuração.
- [HIG Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls) — Mostrar preferências no contexto de uso.
- [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) — Comunicar progresso real, não inventado.

Índice completo: [Pesquisa F01–F20](../research/FeedMine_V2_referencias_F01-F20_2026-10-10.md). A aplicação deve respeitar os owners existentes e as decisões de produto vigentes.

