---
title: "FeedMine — Benchmark competitivo e direção de design do feed"
subtitle: "Pesquisa de mercado, auditoria da V2, UX/UI, hierarquia editorial e plano de validação"
date: "18 de outubro de 2026"
lang: pt-BR
---

# FeedMine — Benchmark competitivo e direção de design do feed

**Pesquisa de mercado, diagnóstico da V2 e proposta de experiência · 18 de outubro de 2026**  
**Escopo:** feed de descoberta, layout editorial, conteúdo, hierarquia de informação, navegação, filtros, retorno, estados, acessibilidade e validação em iOS.  
**Status:** estudo de produto e proposta de design; **não** constitui aprovação de UX, alteração de código, nem comprovação dos gates B01–B06.  
**Público:** dono do produto, UX/UI, arquitetura, implementação SwiftUI e validação de produto.

> **Tese:** o FeedMine não deve parecer apenas um leitor RSS com cards, nem replicar um feed social opaco. Sua melhor posição é **uma revista viva da internet aberta**: descoberta sem configuração especializada, seleção plural e compreensível, composição editorial apropriada a cada história e continuidade local que respeita a leitura em andamento.

## 0. Sumário executivo

### 0.1. Conclusão

O FeedMine já possui um norte de produto mais ambicioso que a maior parte dos leitores tradicionais: uma pessoa informa idiomas e lugares e começa a descobrir histórias de fontes que ainda não segue. Na V2, a base de apresentação evoluiu de forma importante: `FeedPresentationSnapshot` local, `PublicationCardID` estável, cards publicados imutáveis, slots de imagem de geometria reservada, `LazyVStack` e separação de execução em relação ao renderer. Esses avanços são **condições necessárias** para a experiência — não prova de que a experiência está visualmente resolvida.

A oportunidade imediata é elevar a qualidade editorial percebida. O mesmo card de artigo com imagem hero, resumo, origem e data serve bem a uma notícia, mas não basta como gramática universal para ensaios, fotografia, comentários curtos, podcasts e outros formatos. A V2 também carrega várias decisões visuais da V1 e um cabeçalho com controles úteis que competem entre si. Falta um ensaio comparativo visual registrado para dizer se a V2 ficou tão boa quanto a V1, ou melhor.

O estudo recomenda **quatro composições básicas**, resolvidas **antes da publicação** por contratos que já existem, não uma proliferação de templates: `hero` (reportagem visual), `text-first` (ensaio/longform), `compact` (conteúdo curto) e `media` (áudio/vídeo). Também recomenda diferenciar nitidamente três domínios: **Explorar** (descoberta), **Contextos** (orientação) e **Biblioteca** (escolhas pessoais). O primeiro fluxo de uso continua com apenas idiomas e lugares, conforme F02; não adicionar temas, contas, fontes ou walkthrough obrigatório.

A prioridade zero não é redesenhar tudo. É **congelar um corpus representativo, capturar a UI atual em aparelhos reais e estabelecer comparações rastreáveis**. Em seguida, experimentar variantes pequenas no owner de UI, sem permitir que imagens tardias, refresh, edição, mudança de filtro ou playback mudem silenciosamente o que já está publicado.

### 0.2. Decisões recomendadas

1. **Manter o North Star:** descoberta antes de assinatura, conteúdo real antes de controles, interesse declarado antes de personalização presumida.
2. **Separar seleção editorial de layout:** relevância e diversidade escolhem *qual* história; `RenderContract` escolhe *como* ela aparece, com base em evidência e material preparado.
3. **Adotar quatro composições canônicas** sem depender de protocolo nem de heurística de rede durante o render.
4. **Priorizar título e razão para abrir**, mantendo atribuição de fonte, data e proveniência sempre reconhecíveis.
5. **Fazer o contexto ativo legível**, sem transformar o cabeçalho em um painel de diagnóstico do motor.
6. **Distinguir “salvar”, “seguir fonte”, “quero mais tema”, “não quero tema”** como intenções diferentes.
7. **Preservar posição ao abrir/fechar, voltar offline, trocar A→B→A e receber novidades**; oferecer entrada explícita para novidades, nunca empurrá-las sobre o leitor.
8. **Tratar preparação inicial como experiência informativa verdadeira**: mostrar fontes e manchetes reais, sem contagem fictícia nem animação que substitua progresso.
9. **Garantir escalabilidade tipográfica e acessibilidade**, especialmente onde a V2 hoje usa fontes fixas de 11/12 pontos.
10. **Não criar novo pipeline, cache, fila, timer nem estado paralelo de UI** sem um invariant concreto que o exija.

### 0.3. O que este documento NÃO afirma

- Não afirma que a aparência atual da V2 foi comparada por screenshots com os concorrentes; essa comparação ainda precisa ser produzida.
- Não atribui a competidores arquitetura interna sem fonte pública.
- Não declara que features previstas em PRDs de 10/10/2026 passaram integralmente como jornadas de usuário.
- Não propõe copiar interfaces com direitos de terceiros pixel a pixel; usa padrões observáveis como referência.
- Não reabre B01–B06, F02, F05, F06, PD-8/9/10/11 ou o Blueprint v0.4 sem registrar tensão explícita.

## 1. Método, escopo e nível de evidência

### 1.1. Fontes utilizadas

**Fontes primárias do FeedMine:** [Product North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [Product Decisions](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [F02 Onboarding](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F02_DISCOVERY_FEED_ONBOARDING_PRD.md), [F05 Runway](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F05_CONTINUOUS_RUNWAY_PRODUCT_PRD.md), [F06 Sacred Feed](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F06_SACRED_FEED_CARD_READINESS_PRD.md), [F14 Reading Navigation](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F14_READER_LINK_NAVIGATION_UX_PRD.md), [F15 Playback](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md), [F17 Localization/Accessibility](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F17_LOCALIZATION_APPEARANCE_ACCESSIBILITY_UX_PRD.md), [V1→V2 UI Transfer Matrix](https://github.com/wsmontes/feedmine_v2/blob/main/docs/v1-study/UI_TRANSFER_MATRIX.md), [Frontend Transfer Evidence](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md) e código na branch `main` (consultado em 18/10/2026). O Blueprint v0.4 e a especificação V2 fornecidos no projeto fundamentam as fronteiras arquiteturais.

**Fontes externas verificadas:** sites de produto, históricos de versão, App Store, suporte oficial, HIG Apple e análise editorial de mercado. A documentação de concorrentes prova a existência de recursos, mas nem sempre sua eficiência ou sua implementação interna.

### 1.2. Taxonomia de evidência

| Código | Significado | Permite afirmar |
|---|---|---|
| **C — Código** | Componente ou fluxo lido diretamente no repositório | A estrutura existe no código consultado; não prova usabilidade em dispositivo |
| **D — Documento vinculante** | North Star, PD ou PRD do FeedMine | É intenção/regra de produto, não evidência de entrega |
| **T — Teste relatado** | Execução documentada com caso e resultado | Aquela cobertura existiu na revisão reportada, sem implicar aceitação geral |
| **O — Fonte oficial externa** | Site, release note, docs de fabricante | O fabricante documenta a funcionalidade; experiência concreta pode variar |
| **R — Resenha independente** | Review com observação e capturas | Uma observação contextual de UX, não verdade arquitetural |
| **H — Hipótese** | Proposta deste estudo | Requer protótipo, validação e aceitação explícita |

Este relatório sinaliza inferências como **hipótese**, **proposta** ou **risco**. Quando dois documentos de momentos distintos divergem, dá precedência a uma decisão vigente expressa, sem apagar a evidência histórica.

### 1.3. Dimensões de benchmark

O benchmark usa nove critérios: (1) qualidade da primeira impressão; (2) descoberta sem conhecimento prévio da fonte; (3) hierarquia tipográfica e visual; (4) diversidade de formatos; (5) consumo/leitura aprofundado; (6) entendimento do contexto e das ações; (7) biblioteca e retorno; (8) continuidade de posição e ausência de surpresa; (9) acessibilidade e adaptação. Não há pontuação numérica fictícia: o foco é em mecanismos, oportunidades e provas.

## 2. Posicionamento: onde o FeedMine deve competir

### 2.1. Leitor RSS não é o espaço competitivo completo

Um leitor RSS tradicional geralmente assume uma lista de assinaturas. Um feed social assume uma rede de usuários, sinais de engajamento e servidor próprio de conteúdo. O FeedMine assume fontes abertas muito heterogêneas, obtidas no dispositivo, e pessoas que **não precisam saber quais fontes seguir**.

Seu ciclo, descrito no North Star, é **Curiosidade → Descoberta → Leitura/consumo → Nova curiosidade → Descoberta**. Portanto, seu benchmark precisa incluir:

- **feeeed:** curadoria pessoal e mistura de fontes sem pressão de “zerar não lidos”.
- **Tapestry:** timeline heterogênea com regras explícitas de ocultação/redução.
- **Reeder:** continuidade da timeline e retomada pelo ponto de leitura.
- **NewsBlur:** compromisso entre lista densa, reader e melhoria contínua de performance percebida.
- **Unread:** tipografia e leitura confortável como prioridade.
- **Readwise Reader:** distinção Feed/Library e organização progressiva.
- **Flipboard:** publicação editorial, descoberta por assunto e coleções.
- **Pinterest:** encadeamento de curiosidade e comandos explícitos para afinar recomendações.

### 2.2. Proposta de valor em uma frase

**“Abra para encontrar histórias boas que você não sabia procurar; leia sem interrupções; guarde o que importa; explore outros caminhos quando quiser.”**

A frase é uma **proposta de posicionamento**, não substitui a copy de onboarding aprovada em F02. Reforça que o benefício não é “milhares de RSS feeds”, “algoritmo inteligente” nem “sempre atualizado”, e sim a descoberta editorialmente valiosa, estável e controlável.

### 2.3. O que não copiar

Não copiar de redes sociais o scroll infinito como objetivo de retenção a qualquer custo; não esconder proveniência de conteúdos; não confundir tempo de permanência com aprovação editorial; não transformar preferências em sinais psicológicos inferidos; não exigir conta; não tornar salvos uma caixa de entrada que obriga triagem; não introduzir layouts aleatórios só para parecer dinâmico; não forçar recomendação porque não há material de qualidade disponível.

## 3. Benchmark de mercado — achados por produto

### 3.1. feeeed: variedade de cards sem ansiedade de unread

**Evidência R —** [MacStories, “feeeed: Embracing Feed Diversity and Personal News Curation”](https://www.macstories.net/reviews/feeeed-embracing-feed-diversity-and-personal-news-curation/). O app combina blogs, feeds RSS, newsletters, YouTube e outras fontes. A página Home mistura conteúdo novo com material que o leitor pode ter perdido; privilegia cards e pode apresentar múltiplas histórias em uma unidade visual, com diferenças por origem. A resenha mostra também um modo “Latest” cronológico, opção de lista compacta, Reading List e controles para sugestões no feed.

**Boa prática:** layouts orientados pelo conteúdo, convivência entre atualidade e evergreen, sugestões opcionais, foco em descoberta em vez de unread counts. **Trade-off:** misturar cards com várias histórias pode tornar autoria, gestos e progresso menos claros. **Transferência ao FeedMine:** usar variedade editorial com regras simples, sem transformar conteúdo plural em cluster arbitrário ou criar sub-histórias publicadas sem identidade própria.

**Não transferir automaticamente:** agrupamentos que exijam reformatar cards após publicação, sugestões incessantes, integrações pessoais estranhas ao North Star ou recomendação baseada em rastreamento. Recomendações editoriais só podem atuar no trabalho futuro e dentro de restrições explícitas.

### 3.2. Tapestry: heterogeneidade e semântica de filtros

**Evidência O —** [site oficial](https://tapestry.iconfactory.com/), [histórico de versões](https://tapestry.iconfactory.com/history) e [blog Iconfactory](https://blog.iconfactory.com/). O Tapestry integra blogs, redes sociais, podcasts e YouTube em timeline cronológica. Oferece “muffle” (recolher/reduzir presença) e “mute” (ocultar). A atualização Crosstalk procura duplicações textuais entre feeds. O histórico documenta customização de aparência, acessibilidade, player compacto e ajustes de controles.

**Boa prática:** controle explícito em vez de supor preferência; distinção entre reduzir e remover; coerência de origem apesar dos protocolos; deduplicação atravessando fontes. **Trade-off:** uma única timeline cronológica explica a ordem, mas reduz a oportunidade editorial de descobrir um conteúdo atemporal surpreendente. **Transferência:** oferecer ações semânticas claras de frequência/exclusão, sem confundir a operação de longo prazo com ocultação de um único item.

**Diferença central:** o FeedMine pode selecionar com relevância e diversidade; o Tapestry assume intencionalmente a ordem cronológica. Não afirmar que um modelo é universalmente melhor. Transparência no motivo de uma história aparecer é a contrapartida do FeedMine.

### 3.3. Reeder: posição como primeira classe

**Evidência O —** [App Store Reeder.](https://apps.apple.com/ca/app/reeder/id6475002485). A descrição atual fala de timeline unificada de RSS, vídeos, podcasts e posts, sem centralizar unread counts. A versão 2025.4 introduziu acesso direto a **Timeline Position**, **Today** e **Top**, além de contagem de itens mais novos sem empurrar automaticamente a timeline.

**Boa prática:** diferenciar *continuar onde parei* de *ver novidades*. **Trade-off:** ferramentas de timeline exigem uma metáfora temporal entendida pelo usuário. **Transferência:** manter a âncora de leitura como fato durável e comunicar novas histórias por entrada explícita; não criar carrossel paralelo ou alterar o topo do feed presente.

**Oportunidade de diferenciação:** o FeedMine pode oferecer isso sem exigir sync remoto entre dispositivos. Preservar a posição **local** é parte do produto, não concessão técnica.

### 3.4. NewsBlur: desempenho que vira affordance

**Evidência O —** [NewsBlur 15 para iOS, 3/10/2026](https://blog.newsblur.com/2026/10/03/newsblur-15-for-ios/). A equipe descreve melhoria na inclusão incremental de histórias, miniaturas e texto, toolbar flutuante personalizável, controle que se recolhe durante a leitura e visualização ampliada de imagens. O post reporta métricas específicas de sua própria aplicação, que não devem ser tomadas como metas ou resultados do FeedMine.

**Boa prática:** tratar a lista e o reader como superfícies distintas, minimizar interferência do chrome, preservar retorno à história após abrir imagem. **Trade-off:** ferramentas flutuantes podem cobrir conteúdo ou introduzir saltos em áreas seguras se implementadas incorretamente. **Transferência:** experimentar chrome que economiza espaço, mas provar fisicamente que sua entrada/saída não muda âncora nem interrompe gesto.

### 3.5. Unread: leitura como produto de primeira ordem

**Evidência O —** [App Store Unread](https://apps.apple.com/ca/app/unread-an-rss-reader/id1363637349). Posiciona-se em tipografia, gestos, temas e texto de artigo obtido do site quando o feed contém só resumo, com alternância entre o texto do feed e o conteúdo da web.

**Boa prática:** conforto, leitura longa, escolhas tipográficas deliberadas e ações que não monopolizam a tela. **Trade-off:** interface minimalista pode esconder descoberta de fontes e ações que um usuário novo ainda não conhece. **Transferência:** levar a disciplina tipográfica para cards e reader; não imitar ocultação excessiva de controles em uma experiência de primeiro uso.

### 3.6. Readwise Reader: Feed ≠ Library

**Evidência O —** [Reader: Adding Content](https://docs.readwise.io/reader/docs/faqs/adding-new-content) e [Library Configuration](https://docs.readwise.io/reader/guides/workflows/library-configuration). O Reader distingue um Feed de conteúdo entregue automaticamente de uma Library de documentos escolhidos para guardar; esta pode operar em vários modelos (triage, shortlist e outros).

**Boa prática:** as intenções “chegou para mim”, “quero ler depois” e “escolhi preservar” são diferentes. **Trade-off:** alguns leitores apreciam Inbox/Later/Archive; outros detestam obrigação de triagem. **Transferência:** preservar o significado dos salvos, coleções e fontes, sem impor “Inbox Zero” como objetivo do FeedMine.

### 3.7. Flipboard: qualidade editorial antes de densidade

**Evidência O —** [About Flipboard](https://about.flipboard.com/), [How it works](https://about.flipboard.com/how-it-works/) e [App Store](https://apps.apple.com/ca/app/flipboard-the-social-magazine/id358801284). A proposta editorial mistura veículos conhecidos, temas e revistas curadas. Há distinção entre descobrir, seguir e construir coleções temáticas.

**Boa prática:** uma história precisa parecer digna de atenção, com imagem, tipografia e identificação da publicação. **Trade-off:** estética editorial pode ser lenta, ocupar área excessiva e não funcionar para posts curtos. **Transferência:** card hero quando a mídia merece protagonismo e fonte confiável ao lado de especialistas; não transformar todas as histórias em capas de revista nem impor cota de imagem.

### 3.8. Pinterest: curiosidade que leva a outra curiosidade

**Evidência O —** [Pinterest Help: See more or fewer Pins](https://help.pinterest.com/en/article/hide-a-pin-on-your-home-feed) e [Refine recommendations](https://help.pinterest.com/en/article/tune-your-home-feed). O usuário pode pedir mais/menos similares, identificar por que viu um item e ajustar influências sobre a recomendação.

**Boa prática:** cada descoberta pode abrir uma exploração relacionada; controles visíveis ajudam a compreender o mecanismo. **Trade-off:** feeds altamente visuais/irregulares não são apropriados como padrão para textos heterogêneos, e os sinais de engajamento podem ser opacos. **Transferência:** “Explorar mais sobre X” como mudança deliberada de contexto, preservando A→B→A; não reclassificar silenciosamente o leitor por ter aberto um card.

### 3.9. Matriz comparativa por oportunidade

| Dimensão | Referência exemplar | Aprendizado para FeedMine | Copiar? |
|---|---|---|---|
| Mistura visual de fontes | feeeed | Diferenciar composições por natureza editorial | **Sim, com limites** |
| Transparência e controle | Tapestry | “Recolher”, “reduzir”, “excluir” são ações distintas | **Sim, sem novo motor** |
| Retomar e acessar novos itens | Reeder | Posição guardada ≠ topo ≠ novidades | **Sim** |
| Chrome e fluidez | NewsBlur | Controles desaparecem apenas quando não atrapalham | **Testar** |
| Tipografia e reader | Unread | O conteúdo deve ser confortável para ler longamente | **Sim** |
| Descoberta vs biblioteca | Readwise | Evitar transformar exploração em triagem compulsória | **Sim, simplificado** |
| Hierarquia editorial | Flipboard | Imagem e manchete valorizadas quando adequadas | **Sim, seletivamente** |
| Exploração relacionada | Pinterest | Cada história pode abrir um novo contexto reversível | **Sim, sem perfil implícito** |

## 4. Auditoria factual da V2: o que existe, onde está e o que falta provar

### 4.1. Inventário do caminho de apresentação

**Código C —** A superfície atual em [FeedScreen.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedScreen.swift) utiliza `ScrollView`, `LazyVStack`, `PresentationCard` e `FeedItemView`. Os itens são identificados por `PublicationCardID`; há captura de geometria visível e evidência de viewport, com guarda contra apresentações obsoletas. O arquivo documenta a decisão de evitar que uma leitura da posição no corpo do feed provoque reavaliações excessivas da lista.

[FeedPresentationSnapshot.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineRuntime/FeedPresentationSnapshot.swift) define a janela finita, âncora por identidade e provenance local. Isso cria uma fronteira de apresentação importante: a UI recebe o que já foi preparado, e uma observação não tem autoridade para exigir nova seleção editorial.

A composição em [FeedItemView.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Cards/FeedItemView.swift) oferece `automatic`, `band` ou `row`. O modo automático depende principalmente de `horizontalSizeClass`: em largura regular usa linha; nas demais, card. **Diagnóstico:** há responsividade, mas ainda pouca política editorial explícita de composição por significado do conteúdo.

[FeedItemCardView.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Cards/FeedItemCardView.swift) exibe imagem hero, origem, título de até duas linhas, resumo até três linhas, data e ações. Na imagem, a proporção é estabelecida pelo card publicado; quando os pixels chegam, o slot não muda de altura. São avanços positivos para não quebrar a leitura. O componente contém melhorias específicas de hit testing e VoiceOver para gestos de playback. Não se deve apagar esses reparos ao redesenhar.

[FeedItemRowView.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Cards/FeedItemRowView.swift) possui miniatura compacta, título, resumo, origem e data. Parte da tipografia usa `.font(.system(size: 12))` ou valores ainda menores. Isso não é prova automática de inacessibilidade, mas exige teste explícito com tamanhos maiores do iOS.

[ReaderHeader.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Reader/ReaderHeader.swift) reúne status, busca, salvos, filtros e menu em header com `ultraThinMaterial`. [ReaderShell.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Reader/ReaderShell.swift) reserva a altura do header e da pesquisa com lógica própria; qualquer proposta de chrome recolhível deve preservar âncora e hit targets.

[FeedPreparationView.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedPreparationView.swift) apresenta fonte consultada, manchetes reais e cards entrando em deck animado; atende à ideia de preparação honesta. [FeedLoadingView.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedLoadingView.swift) distingue preparo, impossibilidade de conexão e ausência de conteúdo, com chamadas a ações de recuperação do host. Um visual mais agradável **não** deve falsificar dados.

### 4.2. Avanços reais que devem permanecer

| Avanço constatado no código/documentação | Por que importa em UX | Risco ao redesenhar |
|---|---|---|
| Identidade `PublicationCardID` | A história conserva identidade no scroll e no retorno | Vincular `id` ao índice visual ou à posição de viewport |
| `FeedPresentationSnapshot` | Uma tela local publicada em vez de depender da internet | Renderizar URL remota na View ou iniciar fetch em `.onAppear` |
| Slot de imagem com proporção reservada | Pixels atrasados não empurram o texto | Trocar layout ao receber mídia ou conteúdo atualizado |
| Gestos separados de botões do card | Bookmark, menu e opening tap são alcançáveis | Envolver o card inteiro em camada que captura toques |
| Header medido e padding declarado | Área de leitura sabe onde começa | Alterar altura do header por progresso/background |
| Preparação baseada em títulos/fonte reais | Espera inicial informa algo verdadeiro | Substituir por skeleton e porcentagem fictícia |
| Mini-player app-wide, documentado na composição | Reprodução não pertence a um card que saiu da tela | Criar `AVPlayer` por célula ou perder sessão ao filtrar |

### 4.3. Limites e lacunas já registrados internamente

**Documento D/T —** A [UI Transfer Matrix](https://github.com/wsmontes/feedmine_v2/blob/main/docs/v1-study/UI_TRANSFER_MATRIX.md) contabiliza estados de transferência de controles, mas avisa que **não foi realizado diff de screenshots V1×V2**, portanto testes de função não equivalem a paridade visual. O [relatório de execução](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md) lista casos efetivamente executados e ressalva que o histórico “T12 PASS with device waiver” não aprova B06 em iPhone físico.

O [F02](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F02_DISCOVERY_FEED_ONBOARDING_PRD.md) é um contrato de experiência revisado: **duas perguntas, idiomas e lugares, depois feed real**. Uma transferência de Welcome→Composer anterior pode estar tecnicamente testada e ainda não ser o onboarding atualmente aprovado.

O [F06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F06_SACRED_FEED_CARD_READINESS_PRD.md) registra potencial conflito entre a política de espera recuperável e `MediaReadiness.presentation(for:)` quando imagem ainda está pendente. Portanto, uma proposta que “resolve” visualmente uma imagem lenta simplesmente tornando-a text-only por timeout seria incompatível com o contrato.

O [F05](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F05_CONTINUOUS_RUNWAY_PRODUCT_PRD.md) registra limites atuais e lacunas de prova da continuidade do runway. O design não pode tentar mascarar fim artificial de feed com mais cards decorativos.

O [F14](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F14_READER_LINK_NAVIGATION_UX_PRD.md), [F15](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md) e [F17](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F17_LOCALIZATION_APPEARANCE_ACCESSIBILITY_UX_PRD.md) deixam jornadas integrais de navegação, playback e acessibilidade como **NOT_RUN**, apesar de evidências parciais em código e testes. Este estudo não as converte em PASS.

### 4.4. Scorecard honesto da situação

| Eixo | Base presente | Prova de produto | Situação |
|---|---|---|---|
| Identidade e publicação local | Sim | Parcial por testes e código | **Fundação sólida, prova integral pendente** |
| Card visual com hero e linha | Sim | Parcial (componentes) | **Precisa ensaio editorial e visual** |
| Bootstrap honesto e animado | Sim | Capacidade em UI | **Precisa observação de primeiro uso** |
| Descoberta sem pré-assinatura | Contrato e implementação em progresso | B01/B02 exigem execução | **Não assumir aprovado** |
| Scroll contínuo em corpus longo | Política e testes parciais | B03/F05 exigem ensaio extenso | **Risco de produto** |
| Estabilidade de imagem/ordem | Contrato e testes parciais | B04/F06 físico pendente | **Não flexibilizar** |
| Leitura/retorno | Ações e browser no app | F14 integral NOT_RUN | **Validar fluxo real** |
| Playback/retomada | Adapter/mini-player e testes | F15 integral NOT_RUN | **Validar interrupção/relaunch** |
| Idioma/acessibilidade | Componentes diversos | F17 integral NOT_RUN | **Auditar de ponta a ponta** |
| Paridade visual com V1 | Referências antigas | Diff não executado | **Lacuna de evidência** |

## 5. Arquitetura de informação proposta

### 5.1. Modelo mental: três domínios, não três bancos de dados

A interface deve permitir ao leitor entender três realidades:

1. **Explorar:** fluxo editorial vivo. É onde descubro histórias relevantes e inesperadas sem saber quais fontes existem.
2. **Contextos:** o recorte atual: idiomas elegíveis, lugares, assuntos, fontes, busca, lente transitória e presets. Um contexto direciona *o que virá*, não reescreve o que já foi mostrado.
3. **Biblioteca:** aquilo que o leitor escolheu guardar ou seguir: histórias salvas, caixas/coleções, fontes escolhidas, contextos salvos e histórico quando oferecido.

Estes são **domínios de UX**, não instrução para criar três tab bars nem três store objects. A implementação deve reutilizar as superfícies e os owners já existentes (`ReaderShell`, `FeedScreenStore`, `FeedSession`, `ReaderLibraryCoordinator`, `ReaderActionCoordinator`, `ContextKey`).

### 5.2. Navegação candidata — hipótese H, não decisão aprovada

```text
EXPORAR — rota primária
  Header: contexto ativo · Buscar · Filtrar · Salvos · Mais
  Feed contínuo com história publicada
  Ações: Abrir / Salvar / Compartilhar / Ver fonte / Explorar tema

SALVOS — destino fácil e explícito
  Histórias salvas / caixas / coleções
  Abrir na ocorrência pretendida / Voltar ao contexto anterior

FONTES — destino acessível, não pré-requisito
  Fontes seguidas / descobrir fonte / coleções de fontes / OPML

AJUSTES — configuração avançada
  Idioma da interface / idiomas de leitura / aparência / offline / import/export
```

Esse mapa deve ser comparado com o header e menu existentes. Uma tab bar fixa pode tornar destinos mais claros, mas também encurtar a janela vertical e interagir com o mini-player. Um header compacto pode preservar mais área, mas esconder recursos. Testar antes de codificar.

### 5.3. Prioridade de acesso

**Primário:** história, contexto atual, abrir, salvar. **Secundário:** buscar, filtrar, alterar contexto. **Terciário:** fontes, coleções, import/export, ajustes. Ações de alta frequência não podem depender de caminho excessivo; configurações técnicas não precisam aparecer em todo card. O salvos deve estar sempre encontrável, mas não necessariamente em todo cabeçalho como botão de destaque cromático.

### 5.4. O que é um contexto visível

Um chip ou pequena linha contextual deve responder: **“O que estou explorando?”** Exemplos de copy (somente quando confirmados pelos dados): “Explorar”, “Ciência”, “Sobre o Canadá”, “Minhas fontes”, “Busca: astronomia”. O recorte explícito deve ter saída simples: *Limpar filtro*, *Voltar para Explorar*, *Desfazer*. Não exibir “Notícias do país X” quando somente a nacionalidade do publicador é conhecida.

O histórico de A deve sobreviver à ida para B, inclusive posição e conteúdo preparado reutilizável. A tela não precisa mostrar cache, epoch nem processo de aquisição. A mudança de contexto deve afetar **próxima leitura** por transição explícita, não alterar os cards que estão sob o dedo.

## 6. Hierarquia editorial da unidade de conteúdo

### 6.1. O card responde cinco perguntas em ordem

1. **O que é?** Título/frase de valor e mídia real representada.
2. **Por que abrir?** Resumo ou trecho informativo (quando útil e disponível).
3. **Quem publicou?** Fonte identificável, não nome derivado de URL host obscuro.
4. **Quando e em que contexto?** Data honesta, formatos, duração, relevância temporal.
5. **O que posso fazer?** Abrir, reproduzir ou guardar; outras ações por menu secundário.

A ordem visual exata depende do tipo de história. “Título primeiro” é uma prioridade cognitiva, não a proibição de hero visual acima do texto em conteúdo orientado por imagem.

### 6.2. Atribuição e proveniência

Fonte é fundamental para o produto, pois a descoberta pode vir de lugares desconhecidos. Identificação deve evitar siglas incompreensíveis e também falsas marcas de validação. Não inventar “Fonte verificada” com base em escore de catálogo. Quando o usuário abre **Ver fonte**, a navegação deve identificar a fonte e permitir segui-la sem convertê-la automaticamente em uma subscrição por ter aberto uma matéria.

Quando uma história aparece por orientação de contexto, uma explicação ocasional e curta — “Você está explorando astronomia” — pode ajudar. Nunca acrescentar texto editorial como se fosse parte da publicação original.

### 6.3. Tipo, duração, atualidade e evergreen

Um podcast pode evidenciar duração e Play; um vídeo pode evidenciar Play e provedor; um ensaio pode evidenciar indicação de leitura aproximada **somente se houver base confiável**. Data absoluta ou relativa não pode mascarar que um conteúdo antigo é uma notícia antiga. Evergreen pode ser legítimo, mas não deve receber o mesmo tratamento de breaking news.

### 6.4. Limites de resumo, título e truncamento

O `lineLimit(2)` atual é uma escolha visual, não garantia de compreensão. Títulos de atualidade muitas vezes dependem de um complemento; truncá-lo pode inverter ou perder o sentido. Propor teste com variantes em 2, 3 e sem limite em text-first, sempre verificando que a geometria final é definida antes da publicação. Não utilizar trucagem automática de título nem “...saiba mais” em todo card. Resumos devem acrescentar contexto, não apenas repetir o título.

### 6.5. A importância de não uniformizar o valor editorial

Um card de fotografia ou mapa pode justificar imagem dominante. Uma denúncia jornalística sem imagem deve obter design digno, não uma versão defeituosa da mesma capa. Um vídeo curto pode precisar de ação explícita com poster. Um post de cinquenta caracteres não exige um hero de 16:9. A gramática visual deve ser finita e previsível, mas flexível onde há diferença editorial comprovada.

## 7. Sistema proposto de quatro composições

### 7.1. Restrições de implementação

O sistema precisa reutilizar `PresentationCard`, `RenderContract`, `PublishedMediaSet` e `PublicationCardID`. Decisão visual acontece até a publicação. A UI observa dados **congelados** e pixels locais. Mudança de tamanho da tela ou Dynamic Type pode recompor layout de forma controlada, mas não autoriza nova seleção nem mídia tardia que transforme o card em outro tipo. Nenhuma classe de card implica nova solicitação de rede na View.

### 7.2. Arquétipo A: HERO (história visual)

**Uso:** reportagem com imagem real relevante, foto, capa visual, vídeo com poster local apropriado. **Hierarquia:** imagem → título → breve contexto → fonte/data/ações. **Mídia:** proporção publicada e slot estável, crop deliberado, alt text quando disponível. **Riscos:** imagens irrelevantes, excesso de altura, thumbnails repetitivos, leitura interrompida pela decoração.

```text
┌───────────────────────────────────┐
│       IMAGEM REAL PREPARADA       │
│         proporção estável         │
├───────────────────────────────────┤
│ FONTE RECONHECÍVEL      18 out    │
│ Uma manchete interessante que    │
│ merece atenção                   │
│ Resumo curto que acrescenta       │
│ informação.                      │
│                 [Salvar]  [•••]  │
└───────────────────────────────────┘
```

### 7.3. Arquétipo B: TEXT-FIRST (ensaio e leitura longa)

**Uso:** história excelente sem imagem, análise, ensaio, texto técnico ou reportagem cujo título domina. **Hierarquia:** fonte/contexto discretos → título amplo → fragmento útil → data e ação. **Mídia:** ausência de imagem é decisão legítima de publicação, não placeholder “aguardando”. **Riscos:** densidade excessiva, repetição visual, corpo muito pequeno.

```text
┌───────────────────────────────────┐
│ PUBLICAÇÃO · CULTURA · 18 out     │
│                                   │
│ Uma questão importante que       │
│ merece leitura com calma         │
│                                   │
│ Um parágrafo curto, bem composto, │
│ apresenta o argumento da história│
│ sem reproduzir a página inteira.  │
│                                   │
│ Ler história            [Salvar]  │
└───────────────────────────────────┘
```

### 7.4. Arquétipo C: COMPACT (atualização breve)

**Uso:** nota curta, micro-post, notícia simples, repetição de fonte cujo hero não aumenta entendimento. **Hierarquia:** título → origem/contexto → hora. Miniatura opcional dimensionada antes da publicação. **Riscos:** card pequeno demais para alvo de toque, retirar contexto, alternância excessiva entre alturas.

```text
┌───────────────────────────────────┐
│ Manchete curta com foco  [thumb]  │
│ Fonte conhecida · 2 h            │
└───────────────────────────────────┘
```

### 7.5. Arquétipo D: MEDIA (mídia com ação explícita)

**Uso:** podcast, videocast nativo, vídeo do YouTube embutível, outras mídias. **Hierarquia:** capa/poster → título/autor → duração, tipo → Play/abrir. **Riscos:** confundir miniatura de vídeo com reprodução já ativa, autoplay no scroll, alegar playback offline inexistente. A publicação visual local pode existir mesmo sem arquivo completo.

```text
┌───────────────────────────────────┐
│ [ CAPA / POSTER LOCAL ] [▶]      │
│                                   │
│ Episódio sobre ciência           │
│ Podcast · 42 min · Origem         │
│ [Ouvir]  [Salvar]         [•••]   │
└───────────────────────────────────┘
```

O trabalho anterior de benchmark de mídia (Pocket Casts, Inoreader, Readwise Reader e Snipd) continua sendo a referência de playback detalhado; esta proposta especifica como a mídia entra na gramática editorial do feed, sem alterar as políticas da Apple/YouTube.

### 7.6. Matriz de decisão visual

| Evidência publicada | Composição preferida | Condição proibitiva |
|---|---|---|
| Imagem local relevante, válida, preparada e adequada | Hero | Imagem ainda pendente e recuperável não vira text-first por timeout arbitrário |
| Texto completo ou resumo útil, sem imagem materialmente válida | Text-first | Não publicar link morto apenas para preencher área |
| Conteúdo realmente breve, atribuição suficiente | Compact | Não truncar até perder o argumento ou esconder ação importante |
| URL/identidade reproduzível explicitamente, capa/poster ou placeholder determinístico | Media | Não iniciar stream/AVPlayer em `body` ou `.onAppear` |
| Conteúdo ambíguo | Modelo conservador e honesto | Não inferir classificação só do domínio ou do protocolo |

**Hipótese de design:** o contrato pode expor um `presentationStyle` canônico já resolvido. **A implementação não deve adicionar este campo se o `RenderContract` atual já representar a mesma decisão de maneira suficiente.** Verificar primeiro a estrutura existente e reduzir duplicação.

### 7.7. O que não fazer: “variedade aleatória”

A sucessão de heros grandes, cards textuais e linhas compactas cria ritmo quando cada diferença tem causa editorial. Se a escolha é aleatória, a variação vira ruído, complica o escaneamento e dificulta prever gestos. Não usar quotas fixas (“um hero a cada 5 cards”), nem regras por fornecedor (“todo YouTube é hero”), nem transição tardia de compact para hero.

## 8. Densidade editorial e ritmo do scroll

### 8.1. O paradoxo da descoberta

Densidade alta permite percorrer muitas histórias, mas pode apagar imagens e contexto. Densidade baixa valoriza cada card, mas torna o feed lento para leitores que procuram variedade. O trade-off não se resolve por uma única estética nem por medir cards por minuto em isolamento.

### 8.2. Variantes candidatas para teste

| Variante | Descrição | Vantagem esperada | Risco |
|---|---|---|---|
| **A — Baseline** | V2 atual com ajustes mínimos de contraste/spacing | Controle experimental | Pode parecer uniforme |
| **B — Editorial** | Quatro composições decididas na publicação, hero seletivo, texto-first rico | Aumentar valor percebido | Mais áreas altas e possibilidades de inconsistência |
| **C — Compacta** | Mesmas identidades e ações com densidade aumentada por preferência explícita | Eficiência para leitores intensivos | Tipografia pequena, menor descoberta casual |

Não introduzir automaticamente uma preferência de densidade antes de provar que B melhora o produto. O teste pode ser feito com protótipos e fixtures, sem estado de produto novo. Qualquer opção persistida deve ser uma preferência visual explícita e manter o mesmo histórico/âncora.

### 8.3. Métricas que importam

Tempo até compreender o assunto de cada card; taxa de destinos errados; proporção de fontes corretamente identificadas; sucesso em reencontrar uma história; leitura/retorno sem salto; capacidade de distinguir conteúdo atual de evergreen; legibilidade em tamanho de fonte aumentado. Não usar somente número de toques, número de cards vistos ou tempo de engajamento: podem premiar interface compulsiva em vez de descoberta útil.

## 9. Navegação e chrome: que controles merecem espaço?

### 9.1. O header não pode parecer um painel de operação

O cabeçalho atual combina status, busca, bookmarks, filtros e menu. Uma pessoa nova não precisa monitorar quantos feeds foram contatados para escolher uma história. Ela precisa entender onde está, o que está explorando e como alterar o rumo. O status operacional é útil em preparação e diagnóstico, mas deve perder protagonismo quando já há feed pronto.

**Proposta:** primeira camada com nome de contexto claro e busca; filtros presentes por affordance própria; salvos acessíveis por ícone/rota com label de acessibilidade; menu com ferramentas secundárias. Testar tanto o header fixo atual quanto um chrome que se recolhe só após gesto inequívoco do usuário. Nenhuma animação por mudança de rede, chegada de conteúdo ou progresso assíncrono pode alterar área útil de leitura no meio do gesto.

### 9.2. O que deve sempre ser recuperável

Ações essenciais — voltar do leitor, acessar salvos, trocar contexto e retornar ao ponto anterior — devem ser descobertas sem depender de long press. Menu contextual é ótimo para comandos secundários e pode conter “Ver fonte”, “Adicionar fonte à coleção”, “Copiar link” e “Compartilhar”. Não deve ser o único lugar para salvar quando salvar é um gesto central.

### 9.3. Experimento de header

**H1 — Compacto existente:** status reduzido + busca + salvos + filtros + menu. **H2 — Contextual:** “Explorar · Mundo todo” como título/entrada de contexto, com Busca e Filtro, biblioteca persistente acessível por tab ou menu. **H3 — Chrome recolhível:** H2 some durante leitura, reaparece em reversão de scroll. Comparar área útil, alcance de ações, salto de layout, compatibilidade com mini-player e VoiceOver. Não aprovar H3 só por ganhar pixels: se encobre conteúdo ou dificulta orientação, H2 é melhor.

## 10. Curiosidade e descoberta progressiva

### 10.1. Primeira abertura (F02 é vinculante)

O primeiro uso apresenta **somente idiomas para ler e lugares de interesse**, oferece sugestões editáveis, depois entra no feed real. Não pedir assuntos, fontes favoritas, peso de exploração, estilos, conta ou preferência de mídia. Se a rede e o estado local exigirem preparação, mostrar fatos do pipeline: fontes contatadas, histórias chegando e progressos reais, sem barras fictícias.

O primeiro feed funciona como demonstração de qualidade editorial e amplitude da internet: veículos reconhecíveis coexistem com publicações independentes boas, sem rotas conspiratórias nem obrigação de assinar. Assuntos diversos são intercalados de forma natural, sem quotas fixas por tema ou grupos mecânicos de dez.

### 10.2. Convites editoriais ocasionais

O F02 prevê perguntas opcionais inseridas no scroll, rotuladas claramente como intervenção do FeedMine. A história do publicador vem primeiro. Se a classificação do tema é clara, o FeedMine pode perguntar: “Quer descobrir mais sobre astronomia?” com **Quero mais astronomia**, **Não é minha praia** e ação **Desfazer** depois de um voto. Se o tema é incerto, sensível ou composto, não ofertar convite. Passar reto **não** é um voto.

**Ponto crítico de UX:** o convite não pode alterar a sequência já publicada. Sua resposta reprioriza a próxima seleção e potencialmente a descoberta de novas fontes elegíveis. Isso é diferente de assinatura automática e diferente de personalizar implicitamente com base em rolagem, abertura, tempo de permanência ou compartilhamento.

### 10.3. “Explorar mais” como contexto reversível

Uma história sobre a superfície de Marte pode abrir um contexto “Explorar Marte”, mantendo o feed anterior congelado para retorno. A composição nova não é uma “tela de resultados” que começa vazia por construção; deve reutilizar conteúdo local elegível e, quando necessário, admitir novas histórias pelo caminho normal. Retorno usa `ContextKey`, edição e âncora preservados, sem segunda timeline competidora.

### 10.4. Feed de fontes escolhidas vs descoberta geral

A fonte seguida é uma opção consciente. O usuário pode ler apenas suas fontes quando quiser, mas a tela padrão não deve excluir automaticamente o restante do catálogo. “Quero mais sobre X” não inscreve em sites que tratam de X. “Não quero mais sobre X” não deveria apagar histórias já admitidas. Essas fronteiras precisam aparecer em copy e em testes.

## 11. Ações e microcopy: contrato semântico

### 11.1. O problema PD-11

A decisão [PD-11](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md) registra que o comando atual “Menos de X” executa **exclusão de tema** no perfil de descoberta, e não redução de frequência. O texto aprovado para uma correção futura é **“Não quero mais sobre X”**, confirmação **“Entendido. Vamos excluir X das próximas descobertas.”**, com **Desfazer**. A implementação da rodada anterior não foi autorizada a alterar esse comportamento. Este relatório o trata como dívida de honestidade da interface, não como ranking leve já existente.

### 11.2. Dicionário de intenção

| Label do usuário | Efeito correto | Alcance temporal | Desfazer |
|---|---|---|---|
| **Quero mais X** | Aumentar interesse declarado em X | Futuro | Sim |
| **Menos X** | Reduzir prioridade/frequência, sem excluir | Futuro | Sim; **não ofertar até existir semântica real** |
| **Não quero mais X** | Excluir X da descoberta futura | Futuro | Sim |
| **Ocultar esta história** | Esconder somente a ocorrência, se tal ação for explicitamente modelada | Atual ou futuro segundo contrato | Sim |
| **Não mostrar esta fonte** | Excluir fonte conforme escolha explícita | Futuro | Sim |
| **Salvar** | Guardar artigo/ocorrência de modo durável | Biblioteca | Sim |
| **Seguir fonte** | Incluir fonte no conjunto escolhido do leitor | Futuro | Sim |
| **Explorar mais X** | Abrir contexto temático | Novo contexto | Voltar |

Este quadro descreve significados de UX, **não implica que todas as ações já existam**. Se um comportamento não está implementado, o controle correspondente não deve aparecer na UI.

### 11.3. Copy para progresso e escassez

**Aprovável se verdadeiro:** “Descobrindo histórias para você…”, “Conversando com 12 fontes” quando há efetivamente 12 fontes sendo contatadas, “Ainda não encontramos conteúdo suficiente para este recorte”, “Não foi possível conectar; seus conteúdos salvos continuam disponíveis”. **Não usar:** “Não há conteúdo na internet”, “Tudo visto” quando apenas a reserva acabou, “Pronto em 5 segundos”, “100% concluído” sem denominador real, “Fonte verificada” sem autoridade para verificação.

### 11.4. Confiança por atribuição, não selo inventado

Em um agregador de internet aberta, o usuário avalia fontes que desconhece. Exibir publisher reconhecível, idioma, data, formato e eventual caminho “Ver fonte” é melhor do que um selo “confiável” derivado de classificação técnica. O caso “mesma história em múltiplas fontes” deve usar deduplicação editorial antes da publicação e explicação coerente, não uma contagem artificial de reputação.

## 12. Leitor de artigo, vídeo e áudio: transições sem perda

### 12.1. Abrir um artigo

O gesto de abrir precisa atingir o destino congelado do card correto, com saída evidente. O F14 admite `SFSafariViewController` na V2 e exige que o leitor possa retornar exatamente ao card e contexto de origem, inclusive quando dados chegam em background. O protótipo visual deve mostrar claramente **Fechar e voltar ao FeedMine** e **Abrir externamente**, evitando dois comandos ambíguos “Voltar”.

Se há paywall, erro remoto ou link indisponível, a interface não deve culpar a pessoa nem marcar a leitura como bem-sucedida. Deve preservar o caminho de volta. Um item com link comprovadamente morto não é um card pronto para consumo só porque possui um título bonito.

### 12.2. Conteúdo nativo local e originário da web

Quando texto integral é autorizado e local, pode haver leitura imediata offline. Quando só o link existe, a tela e os estados devem assumir dependência da origem. “Disponível offline” precisa indicar **o que** está disponível (card, texto integral, áudio salvo), nunca significar indistintamente “todo o conteúdo e mídia estão baixados”.

### 12.3. Mini-player como estado da reprodução, não do card

A V2 já documenta um `MediaPlaybackAdapter` app-wide. A aparência do mini-player deve poder sobreviver à troca de contexto e à abertura de leitor sem empurrar a âncora. Controles de play/pause, título e fechamento devem ter semântica previsível. Um podcast não deve reiniciar porque a célula original foi reciclada pelo `LazyVStack`.

### 12.4. Interromper e voltar

O F15 registra que interrupções de sistema, background e retorno após fechamento/relaunch ainda requerem jornada completa. A UI deve expressar os estados reais: reproduzindo, pausado, aguardando rede, indisponível e progresso retomável. Não transformar uma falha de playback em falso alerta de escassez de conteúdo do feed.

## 13. Estados de interface: o sistema deve explicar a realidade

### 13.1. Matriz de estados

| Situação real | O que o usuário deve ver | O que não deve ocorrer |
|---|---|---|
| Primeiro uso, nenhum card local | Preparação com fontes/manchetes reais | Skeleton fictício ou barra inventada |
| Preparação em andamento, cards iniciais prontos | Feed começa a ser consumido; trabalho prossegue | Tela de loading bloquear até catálogo “terminar” |
| Fonte lenta, outras prontas | Histórias prontas aparecem normalmente | Candidato lento segurar o primeiro lugar |
| Imagem recuperável lenta | Candidato fica fora da fila pronta; demais avançam | Virar texto puro por timeout arbitrário |
| Imagem definitivamente quebrada | Texto-first **se** leitura for legítima | Placeholder de imagem quebrada para sempre |
| Link morto e sem alternativa consumível | Suspender/rejeitar com motivo | Publicar card clicável sem destino válido |
| Rede perdida com feed local | Feed e salvos locais permanecem navegáveis | Apagar o feed e exibir tela de erro geral |
| Rede perdida e runway esgotado | Mensagem de limite real ao final do histórico | “Sem conteúdo” quando há histórias antigas reutilizáveis |
| Contexto sem histórias elegíveis agora | Ausência contextual com ajustar interesses/voltar | Tratar como falha global do catálogo |
| Conteúdo novo chegou | Opção explícita de ir às novidades | Inserir no topo e mover a pessoa |
| Artigo abre e falha | Explicação e controle de retorno | Fechar a edição ou perder âncora |
| Player remoto falha | Estado de playback específico e opções reais | Mostrar erro de feed ou prometer offline |

### 13.2. Um falso “acabou” é grave

A ausência de cards na janela não pode ser exibida como exaustão definitiva da internet elegível. F05 distingue catálogo elegível, fonte contatada, supply adquirido, candidato pronto, card publicado e janela admitida. Esses estados devem continuar distintos também na copy da UI. Se a reserva realmente se esgotar offline, a mensagem aparece ao final da leitura já preservada, sem substituir o histórico por tela vazia.

### 13.3. Preparação inicial: bom conceito, falta ensaio de qualidade

O `FeedPreparationView` já usa uma pilha de manchetes reais, chips de fontes e transições. Vale preservar sua essência. Mas o teste UX deve cobrir: manchete que chega sem imagem; fonte com nome enorme; zero fontes respondendo; dados em idiomas diferentes; Reduce Motion; atualização rápida; atualização lenta; e primeiro conteúdo que efetivamente aparece no feed. A experiência não deve parecer estar “concluída” quando apenas um pequeno prefixo está pronto.

### 13.4. Não romantizar latência

Mostrar trabalho real não significa transformar cada consulta HTTP em uma animação. O preparo inicial só precisa comunicar o processo enquanto ainda não há feed utilizável. Depois, o melhor feedback de trabalho é **a chegada contínua e não disruptiva de conteúdo relevante**. Um status discreto basta para diagnósticos comuns; a UI não precisa ficar pulsando eternamente.

## 14. Acessibilidade e comportamento em tamanhos reais

### 14.1. Hierarquia sem dependência de cor

A fonte não pode ser distinguida apenas pelo tom da barra lateral; estado salvo não pode depender de um ponto de cor; conteúdo de mídia deve ter rótulos e ações acessíveis; feedback editorial deve ser diferenciado por texto e agrupamento. Usar contraste, alinhamento, rótulos e, quando adequado, símbolo.

### 14.2. Dynamic Type como teste de estrutura, não só da fonte

A [HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout) e a [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) recomendam adaptar disposição, quebrar elementos de uma linha para coluna e evitar truncamento sob fontes grandes. O código V2 contém áreas de tamanho fixo e `.font(.system(size: 11/12))`; isso exige comprovação. Não basta ajustar um multiplicador de fonte se botões e thumbnails continuam competindo com o texto.

**Critérios propostos:** nenhum título essencial perde significado; a fonte continua identificável; botões permanecem clicáveis; mini-player não cobre a última linha; cards compactos podem evoluir para arranjo vertical em AX; o scroll mantém âncora sem mutação editorial.

### 14.3. VoiceOver e gestos

Tap e long press devem ter equivalentes reconhecíveis. Cada card anuncia título, fonte, contexto e ações disponíveis, sem ler texto duplicado por imagem decorativa. O code review do V2 já registra correções de hit testing e ação acessível de Play; o redesenho não deve reintroduzir uma camada de gesto que sequestra bookmark ou menu contextual.

### 14.4. iPad e orientação

Uma largura regular não significa que toda história deva virar linha compacta. O layout atual faz essa escolha principalmente pela size class; o novo sistema deve combinar significado editorial e largura útil. Em iPad, a mesma história pode ocupar uma coluna de leitura confortável com espaços laterais em vez de esticar imagem e texto indefinidamente. [FeedDesignTokens](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedDesignTokens.swift) já define `readableContentWidth`; verificar resultados reais em split view, landscape e rotação.

### 14.5. Idiomas e localização

O F17 separa **idioma da interface** de **idioma das histórias**. A mudança de um não deve reescrever o outro. Testes de locale precisam incluir caracteres não latinos, palavras longas, pluralização, datas e comparação entre EN/pt-BR. RTL só é critério de suporte quando realmente anunciado e implementado; não prometer idiomas pelo mero fato de a V1 exibir uma lista de opções.

## 15. Visual design: paleta, tipografia, microcomponentes

### 15.1. Conservar identidade sem distrair

A V1 possuía paletas e variações circadianas. A V2 conserva valores de aparência como preferências imutáveis, evitando que um relógio recalcule silenciosamente o feed. Isso é correto para continuidade. O estudo recomenda usar cor sobretudo para navegação, affordances e identificação de estado, deixando a cor/arte da história dominar sua própria mídia.

### 15.2. Tipografia proposta por função

- **Manchete:** linha-base forte e clara, peso adequado, que não colapse no Dynamic Type.
- **Origem:** tamanho secundário, mas suficientemente legível e com contraste; não virar mero rodapé invisível.
- **Resumo/deck:** texto de apoio conciso que acrescenta contexto, sem mini-fonte.
- **Metadados:** data, duração e formato apenas quando informativos, sem empilhar quatro ícones decorativos.
- **Labels:** verbos diretos (“Salvar”, “Ouvir”, “Explorar tema”, “Ver fonte”).

Fontes e tamanhos finais devem ser decididos com capturas da V2 e protótipos, não simplesmente copiados de screenshots de outras marcas.

### 15.3. Espaçamento e raio

Manter um número pequeno de tokens semânticos, como já existe, mas avaliar se cada card precisa de background contornado, barra de destaque e raio. Se todas as histórias têm três camadas de chrome, o texto perde força. Um ensaio em dispositivos pode comparar composição “cartões elevados” versus “divisões editoriais leves”, preservando identidades e hit targets. Não acrescentar sombra e animação por default.

### 15.4. Fotografias, cropping e alt

Não esticar, distorcer ou mostrar resolução inútil. Se um crop muda o significado (retrato, mapa, texto em imagem), usar tratamento que preserve informação, quando os metadados permitem. Nunca dar crop de face como prova de reconhecimento automatizado sem evidência. Conteúdo textual importante em imagem requer acesso alternativo quando houver descrição. A imagem preparada no slot publicado continua local, com proporção decidida previamente.

## 16. Fluxos de usuário completos

### 16.1. Jornada A — primeira descoberta, sem seguir fontes

**Pré-condição:** instalação limpa, catálogo local válido, sem fontes seguidas nem conteúdo de usuário. **Ações:** escolhe Português/Inglês e Canadá/Brasil; entra no feed; encontra publicação reconhecível e fonte menor especializada; abre história; retorna; explora algo inesperado; opcionalmente responde a convite editorial. **Sucesso:** não precisou conhecer RSS; conteúdo é real, variado e consumível; nenhum convite obrigatório; o leitor compreende por que uma história apareceu sem ter que entender o algoritmo.

**Falhas a capturar:** parecer uma coletânea de blogs obscuros, exibir conteúdos muito antigos como recentes, só encontrar os mesmos publishers rápidos, usar placeholder de notícia inventada, mostrar convites antes de demonstrar qualidade, travar no primeiro RSS lento.

### 16.2. Jornada B — artigo longo e retorno exato

**Pré-condição:** contexto A com âncora X conhecida, candidatos novos chegando. **Ações:** toca card X; lê artigo; abre imagem; fecha reader; volta ao feed. **Sucesso:** mesmo X, offset, contexto e cards já admitidos; mini-player continua se existia; reorientação é imediata. **Falhas:** novo conteúdo no topo, troca de layout após retorno, botão Voltar ambíguo, card abre URL diferente.

### 16.3. Jornada C — explorar outro assunto e voltar

**Pré-condição:** contexto Explorar, card Y sobre física, oferta relacionada existente no armazenamento local. **Ações:** solicita “Explorar mais física”; percorre novo contexto B; altera interesse; volta ao A. **Sucesso:** B reaproveita dados locais e prioriza novas descobertas; A reaparece como estava, sem reconstrução cara ou nova edição desnecessária; preferência explícita altera futuro, não o histórico de A.

### 16.4. Jornada D — salvar e seguir são coisas diferentes

**Pré-condição:** história boa de fonte desconhecida. **Ações:** salva matéria, vai a Salvos, relê; retorna e opcionalmente escolhe Seguir fonte. **Sucesso:** salvar não segue automaticamente; seguir não duplica cards antigos; salvos persistem offline com metadata/caminho; remover da biblioteca não altera catálogo gerenciado.

### 16.5. Jornada E — offline e escassez real

**Pré-condição:** conteúdo e imagens já apresentados, rede indisponível, histórico local navegável. **Ações:** reabre app offline, percorre, abre um artigo local, chega ao fim da disponibilidade local. **Sucesso:** aparece primeiro conteúdo aproveitável; nenhuma tela de loading fictícia; limitações de rede são específicas; histórico é mantido e fim real é indicado sem afirmar fim do universo.

### 16.6. Jornada F — mídia independente do scroll

**Pré-condição:** podcast válido, card com capa preparada e duração quando disponível. **Ações:** toca Play; rola, abre um artigo, troca contexto, volta, minimiza e retorna; interrompe com áudio do sistema. **Sucesso:** player único mantém identidade, posição e controles; cards não se deslocam; estados de erro/offline honestos; action não começa playback só porque o card apareceu.

### 16.7. Jornada G — filtros com semântica verdadeira

**Pré-condição:** contexto com tema X e fonte Z. **Ações:** seleciona exclusão durável X; vê confirmação e Desfazer; aplica lente transitória; limpa lente e retorna. **Sucesso:** exclusão aplica-se ao futuro; não remove cards já publicados; filtro transitório é visível e reversível; *Menos* não é oferecido enquanto não houver redução real.

## 17. Corpus de avaliação e roteiro de screenshots

### 17.1. O corpus precisa evitar demonstrações perfeitas

Uma única tela bonita com dez imagens de capa não é um bom teste de um leitor da internet aberta. O corpus deve misturar imagens excelentes, imagens inexistentes, artigo de fundo, notícia atual, evergreen, post curto, podcast, vídeo com poster, publisher desconhecido, fonte local, título longo, resumo redundante, caractere não latino, link indisponível e imagem recuperável lenta.

**Princípio:** usar histórias reais, licenciadas/acessíveis, congeladas com proveniência e identidade para a comparação. Quando um fixture artificial for inevitável para erro/edge case, rotulá-lo como fixture e nunca apresentá-lo como notícia editorial no protótipo.

### 17.2. Casos de conteúdo a reunir

| Caso | Composição esperada | Tensão revelada |
|---|---|---|
| Notícia com foto horizontal expressiva | Hero | Crop, legibilidade da fonte, proporção |
| Investigação de qualidade sem imagem | Text-first | Ausência de “hero obrigatório” |
| Artigo de título comprido e relevante | Text-first | Truncamento e tamanho de fonte |
| Atualização de uma frase | Compact | Densidade e área de toque |
| Imagem vertical / reportagem fotográfica | Hero adaptado | Crop, aspecto e altura |
| Podcast de 50 minutos | Media | Duração, ação Play e mini-player |
| YouTube sem embed autorizado | Media ou link externo válido | Não prometer player que não existe |
| Um assunto em duas fontes | Dois cards válidos ou decisão de dedup upstream | Repetição e diversidade |
| Artigo evergreen antigo | Hero/text-first | Data honesta e contexto |
| Publicação com nome enorme | Qualquer | Truncamento e atribuição |
| Foto atrasada, recuperável | Sem publicação até readiness conforme F06 | Falso downgrade text-only |
| Link definitivamente quebrado | Não publicar enquanto sem consumo válido | Card morto |
| Idiomas pt-BR, inglês e CJK | Qualquer | Locale, fonte e line breaking |
| Dynamic Type AX | Todos | Navegação e leitura acessíveis |

### 17.3. Capturas obrigatórias

Para V2 atual e variantes A/B/C: iPhone em retrato com primeiro viewport; scroll intermediário com mistura de cards; leitor aberto; retorno ao feed; estado de preparo inicial; feed offline; filtro/ações; Salvos; podcast com mini-player; tema claro/escuro; tamanho de texto padrão e acessibilidade; iPad portrait/landscape/split view. Registrar SHA, versão, aparelho/simulador, idioma, content size, corpus e âncora.

### 17.4. Comparação com concorrentes

Usar screenshots oficiais ou observações diretas atuais, não layouts lembrados de versões antigas. Marcar claramente a data de captura; não assumir que tela de marketing representa defaults da versão corrente. Classificar cada padrão: **copiar princípio**, **testar como hipótese**, **não copiar**, **fora de escopo**. Proibir aprovação por semelhança estética isolada.

## 18. Protocolo de teste comparativo de design

### 18.1. Perguntas mensuráveis

- Um novo usuário consegue encontrar e iniciar leitura de uma história real sem ser ensinado a adicionar feed?
- Em quanto tempo ele identifica o assunto, a origem e o tipo de mídia de três cards consecutivos?
- Consegue explicar a diferença entre salvar, seguir fonte e pedir mais conteúdo sobre tema?
- Ao interromper a leitura, consegue reencontrar exatamente a história?
- Percebe imediatamente se há ou não conteúdo offline?
- Entende quando uma história é antiga, atual ou atemporal?
- A versão editorial melhora compreensão e curiosidade sem aumentar erro de toque ou instabilidade?

### 18.2. Método recomendado

**Rodada de inspeção:** um especialista em UX e o responsável técnico inspecionam a V2 em aparelhos reais e registram screenshots, vídeos, hierarquia de VoiceOver e comportamento de rolagem. **Rodada de protótipos:** variantes A/B/C com o mesmo corpus congelado, sem alterar a selection upstream. **Rodada com leitores:** tarefas curtas sem instrução técnica, incluindo pessoas não familiarizadas com RSS; observar execução, erros, compreensão e linguagem espontânea. **Rodada técnica:** regressão de áncora, bounds, ids e publish invariants conforme B04/B05.

Não inventar tamanhos amostrais como metas de produto. Uma rodada qualitativa inicial pode revelar problemas evidentes, mas **não** produz significância estatística. Se houver experimento quantitativo posterior, pré-registrar hipóteses e critérios.

### 18.3. Matriz de aceitação UX de design

| ID | Comportamento comprovável | Tipo de evidência |
|---|---|---|
| UXD-01 | Primeira abertura com idioma/lugar entra em histórias reais variadas | Vídeo de jornada + fontes/ids |
| UXD-02 | Dois cards de classes diferentes têm hierarquia intencional, não quebra | Screenshots comparados + julgamento de leitores |
| UXD-03 | Falta de imagem legítima aparece como composição text-first digna | Captura + evidência de readiness |
| UXD-04 | Imagem recuperável lenta não bloqueia outros candidatos nem vira downgrade mágico | Rastros de candidato e publicação + captura |
| UXD-05 | Abrir/voltar restaura mesma âncora e offset | Coordenadas e vídeo real |
| UXD-06 | A→B→A reaproveita contexto e posição | IDs, contextos, tempo de retorno, captura |
| UXD-07 | Novidades não empurram topo do feed em uso | Vídeo com chegada assíncrona |
| UXD-08 | “Não quero mais X” afeta só futuro e oferece Desfazer | Ação real + estado persistente |
| UXD-09 | Salvar e seguir fonte produzem estados duráveis diferentes | Inspeção da biblioteca + relaunch |
| UXD-10 | Mini-player continua sem deslocar a lista | Coordenadas antes/depois e áudio |
| UXD-11 | Dynamic Type alto mantém título, fonte e ações compreensíveis | Capturas/VoiceOver por tamanho |
| UXD-12 | Offline exibe história preparada primeiro e estado de rede verdadeiro | Rede desligada + relaunch |
| UXD-13 | Não há fetch/decoding bloqueante em View body | Instrumentação + código |
| UXD-14 | Feed não termina artificialmente sob corpus longo e consumo variável | B03/F05 com swipe real |
| UXD-15 | Uma opção de composição não reescreve ordem/identidade já publicada | IDs/ordem, snapshots antes/depois |
| UXD-16 | Trocar claro/escuro ou aparência preserva posição e semântica | Captura, bounds, viewport, UI accessibility |

**Resultado por caso:** `PASS`, `FAIL`, `NOT_RUN` ou `BLOCKED`, com motivo e artefato. O novo benchmark **complementa**, não substitui, os B01–B06 e UX14/15/17 já definidos.

## 19. Diretrizes para implementação sem regressões

### 19.1. Owner e fronteira para cada mudança

| Mudança de UX | Local provável a auditar primeiro | Proibido |
|---|---|---|
| Composição dos cards | `Cards/FeedItemCardView.swift`, `FeedItemRowView.swift`, `FeedItemView.swift` | I/O, parsing de protocolo, busca de mídia em View |
| Contrato editorial visual | `PresentationCard` / `RenderContract` / `MediaPreparation` | Mudar história publicada após chegada de pixels |
| Header e navegação | `ReaderHeader.swift`, `ReaderShell.swift`, `FeedScreenStore.swift` | Estado de aquisição duplicado no header |
| Primeira preparação | `FeedPreparationView.swift`, `FeedLoadingView.swift` | Notícias fictícias, temporizador fake, spinner sem fato |
| Voltar ao ponto lido | `FeedSession`, `FeedPresentationSnapshot`, visual capture | Índice visual como identidade durável |
| Contexto A→B→A | `ContextKey`, `FeedSession`, composição atual | Destruir edição anterior indiscriminadamente |
| Ações salvar/seguir/filtro | `ReaderActionCoordinator`, `ReaderLibraryCoordinator`, `ReaderFilter` | Ação com label mais leve que o efeito real |
| Mini-player | `MediaPlaybackAdapter`, `ReaderMediaCoordinator`, UI hospedadora | Player por célula, recomputar feed por tempo de playback |

**Regra:** nomes acima são pontos de partida comprovados ou documentados, não autorização para adicionar um subsistema. Antes de editar, conferir o owner concreto no HEAD e o menor caminho que resolve o comportamento. Não alterar `AppComposition.swift` só para acomodar preferências cosméticas do card.

### 19.2. Sequência mínima de mudança

1. Fotografar comportamento atual e fixar casos de conteúdo.
2. Resolver uma necessidade visual mensurável (ex.: título text-first não pode ficar com aspecto de imagem quebrada).
3. Conferir se a representação já pode ser expressa no contrato de apresentação existente.
4. Modificar o owner do card, com testes de semântica e screenshot/viewport.
5. Rodar as jornadas de retorno, Dynamic Type e publicação atrasada.
6. Comparar V2 atual com a variante; se não há melhora perceptível ou houve regressão, reverter.

### 19.3. Nada de performance cosmética

Substituir conteúdo por skeleton eterno ou adiantar cards irrelevantes para fingir abundância não melhora um feed. Fechar em 4 segundos em vez de 5 é útil apenas quando muda a leitura real. Se a interface ainda chega ao fim artificialmente ou salta durante uma imagem tardia, os problemas centrais continuam abertos.

## 20. Roadmap de produto e design (proposto)

### Etapa 0 — Evidência e linha de base (P0)

**Entregas:** capturas V2 e V1 comparáveis em corpus congelado; vídeos de scroll, retorno e offline; inventário visual de variantes; diagnóstico Dynamic Type; mapeamento de touch targets. **Critério de pronto:** a equipe consegue apontar defeitos por screenshots e interações reproduzíveis, não por opinião solta.

### Etapa 1 — Hierarquia e cards (P0)

**Entregas:** protótipo dos quatro padrões e experimento com card textual versus hero; revisão de tipografia de títulos, resumos, atribuição e metadados; casos extremos. **Critério de pronto:** não há card “quebrado porque não tem imagem”; títulos e fontes são identificáveis; nenhuma perda de âncora nem I/O em render.

### Etapa 2 — Intenção e orientação (P0/P1)

**Entregas:** rótulo PD-11 honesto, contexto atual compreensível, gesto claro de voltar ao feed anterior, exploração relacionada por ação explícita e distinção entre Salvos/Fontes. **Critério:** uma pessoa entende consequência antes do toque e pode desfazer sem alterar cards passados.

### Etapa 3 — Navegação e chrome (P1)

**Entregas:** teste comparativo do header atual versus contextual; organização clara de destino primário/terciário; mini-player sem salto; leitura imersiva. **Critério:** acesso às ações essenciais não piora, espaço visual aumenta quando útil e medição B04 mantém estabilidade.

### Etapa 4 — Adaptação e polimento (P1/P2)

**Entregas:** opções de densidade se comprovadamente úteis; iPad e split view; tema/locale; imagens fullscreen; microinterações discretas; acessibilidade expandida. **Critério:** todas as variantes preservam conteúdo/ações, não aparecem estados novos sem owner e não reduzem cobertura da fonte.

**Ordem condicionada por produto:** se B03/B04 ainda falham em dispositivos, estabilizar antes de investir em estética periférica. Um card fantástico que some ao voltar do artigo é pior do que um card simples e confiável.

## 21. Registro de riscos e tensões

| Risco | Probabilidade conceitual | Impacto | Mitigação sem novo mecanismo |
|---|---|---|---|
| Multiplicação de templates por protocolo | Média | Alta manutenção / inconsistência | Quatro arquétipos canônicos, decididos pelo conteúdo |
| Imagem chega e altera card publicado | Alta em implementação ingênua | Salto, perda de leitura | Slot e RenderContract congelados antes da publicação |
| Densidade compacta destrói legibilidade | Média | Acessibilidade / compreensão | Teste Dynamic Type e tarefa de reconhecimento |
| Tab bar / mini-player altera geometria | Média | Perda de âncora | Medição física e layout persistente com espaço reservado |
| Feedback “sem conteúdo” antes do fim real | Alta em sistema distribuído | Quebra promessa principal | F05 estados distintos e copy factual |
| Controles demais na superfície primária | Média | Sobrecarga cognitiva | Separar primary/secondary/tertiary, testar achabilidade |
| Recomendação entendida como assinatura | Média | Perda de controle | Labels e persistências diferentes para tema e fonte |
| Pseudoverificação de fonte | Média | Dano de confiança | Atribuição real, sem selo derivado de score técnico |
| Abertura web quebra retorno | Média | Usuário abandona feed | UX14 e snapshots com âncora |
| Condicionar primeira experiência a fontes rápidas | Alta sem política editorial | Feed fraco / repetitivo | F02 qualidade/diversidade + runway adaptativo |
| UI lê dados diretamente do armazenamento/rede | Média quando cresce escopo | Acoplamento e travamentos | Contrato `FeedPresentationSnapshot` e owners existentes |
| Documentação chama componente de prova de jornada | Alta em revisão superficial | Falso verde | Classe de evidência e estado NOT_RUN explícitos |

## 22. Decisões pendentes a levar à rodada de produto

| ID | Questão | Opções plausíveis | Como decidir |
|---|---|---|---|
| D-01 | O usuário pode escolher densidade? | Não; compacta opcional; automática por contexto | Prova de tarefa e acessibilidade A/B/C |
| D-02 | Header fixo ou recolhível? | Atual; contextual fixo; contextual recolhível | Vídeo de scroll e retorno, acertos de ação, B04 |
| D-03 | Salvos vira destino persistente? | Ícone; tab; menu de raiz | Achabilidade sem tutorial, área útil |
| D-04 | Quando hero merece destaque? | Política de mídia/texto; preferência visual | Corpus heterogêneo + fontes/formatos |
| D-05 | Card mostra categoria? | Nunca; ocasional; baseada em evidência | Compreensão e confiança, sem rótulo falso |
| D-06 | Novidades aparecem como? | Ação no header; marcador discreto; topo explícito | Retorno, posição, sem edição paralela |
| D-07 | “Explorar mais” fica onde? | Menu card; intervenção ocasional; detail | Descoberta com baixo ruído, reversibilidade |
| D-08 | Fonte é primária ou secundária no card? | Acima do título; abaixo; lado | Teste de credibilidade e velocidade de scan |
| D-09 | Longform precisa de mais título? | 2 linhas; 3; altura editorial | Compreensão de manchete com truncamento |
| D-10 | Escassez offline pede quê? | Voltar; ajustar contexto; tentar quando houver rede | Entendimento correto e ausência de falsa promessa |

O presente relatório não decide unilateralmente preferências que exigem observação de uso. Indica o custo de alternativas e a menor evidência necessária.

## 23. Referências, documentação e rastreabilidade

### 23.1. FeedMine — fontes internas da revisão

1. [North Star — intenção do produto, invariantes de comportamento, descoberta e continuidade](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md).
2. [Product Decisions 2026-10-09 — PD-1 a PD-11, inclusive PD-8/9/10 e semântica de PD-11](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md).
3. [F02 — primeiro contato em dois passos, feed real e convites editoriais opcionais](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F02_DISCOVERY_FEED_ONBOARDING_PRD.md).
4. [F05 — runway adaptativo, estados de oferta e cenários de 5.000 itens/30 min](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F05_CONTINUOUS_RUNWAY_PRODUCT_PRD.md).
5. [F06 — card sagrado, readiness não bloqueante, proibição de mutação tardia](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F06_SACRED_FEED_CARD_READINESS_PRD.md).
6. [F14 — leitura e retorno ao feed](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F14_READER_LINK_NAVIGATION_UX_PRD.md).
7. [F15 — continuidade do podcast](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md).
8. [F17 — idioma, aparência e acessibilidade](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/F17_LOCALIZATION_APPEARANCE_ACCESSIBILITY_UX_PRD.md).
9. [V1→V2 UI Transfer Matrix — inventário e advertência contra alegar paridade visual](https://github.com/wsmontes/feedmine_v2/blob/main/docs/v1-study/UI_TRANSFER_MATRIX.md).
10. [Frontend Transfer Evidence — testes executados, ressalva B06 e lacunas de comparação visual](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/V1_V2_FRONTEND_TRANSFER_EVIDENCE.md).
11. [FeedScreen.swift — ScrollView/LazyVStack, vista local e captura de geometria](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedScreen.swift).
12. [FeedPresentationSnapshot.swift — janela, âncora e provenance](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineRuntime/FeedPresentationSnapshot.swift).
13. [FeedItemCardView.swift — composição hero, tipografia e ações](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Cards/FeedItemCardView.swift).
14. [FeedItemRowView.swift — composição compacta](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Cards/FeedItemRowView.swift).
15. [FeedItemView.swift — escolha band/row e inventário de ações](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Cards/FeedItemView.swift).
16. [ReaderHeader.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Reader/ReaderHeader.swift) e [ReaderShell.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Reader/ReaderShell.swift) — chrome e geometria.
17. [FeedPreparationView.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedPreparationView.swift), [FeedLoadingView.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedLoadingView.swift) — primeira preparação e estados de ausência.
18. [FeedDesignTokens.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/FeedDesignTokens.swift) e [ReaderAppearance.swift](https://github.com/wsmontes/feedmine_v2/blob/main/Sources/FeedMineUI/Appearance/ReaderAppearance.swift) — tokens, tipografia e paletas.

### 23.2. Mercado — fontes externas

1. [MacStories — feeeed, diversidade de feed e Reading List](https://www.macstories.net/reviews/feeeed-embracing-feed-diversity-and-personal-news-curation/) (resenha com capturas; não é código-fonte).
2. [Tapestry — site oficial](https://tapestry.iconfactory.com/) e [release history](https://tapestry.iconfactory.com/history).
3. [Iconfactory — Crosstalk para publicações repetidas](https://blog.iconfactory.com/) (notícia de 8/4/2025, acessível via arquivo do blog).
4. [Reeder — App Store](https://apps.apple.com/ca/app/reeder/id6475002485) (inclui a versão 2025.4 e controles de timeline).
5. [NewsBlur 15 para iOS, 3/10/2026](https://blog.newsblur.com/2026/10/03/newsblur-15-for-ios/).
6. [Unread — App Store](https://apps.apple.com/ca/app/unread-an-rss-reader/id1363637349).
7. [Readwise Reader — Feed versus Library](https://docs.readwise.io/reader/docs/faqs/adding-new-content) e [Library configuration](https://docs.readwise.io/reader/guides/workflows/library-configuration).
8. [Flipboard — About](https://about.flipboard.com/) e [How it works](https://about.flipboard.com/how-it-works/).
9. [Pinterest — See more or fewer Pins](https://help.pinterest.com/en/article/hide-a-pin-on-your-home-feed) e [Refine recommendations](https://help.pinterest.com/en/article/tune-your-home-feed).
10. [Apple HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Writing](https://developer.apple.com/design/human-interface-guidelines/writing) e [Design Principles](https://developer.apple.com/design/human-interface-guidelines/design-principles).

### 23.3. Limites desta etapa e próximo artefato

Este estudo inspecionou documentação, código e fontes de mercado, **mas não executou o app em simulador ou iPhone**, nem produziu screenshots V2 ou usabilidade com leitores. O próximo artefato de alto valor é uma **auditoria visual baseada em capturas reais**, com as mesmas histórias em iPhone/iPad, contrapostas às quatro composições canônicas. A etapa de implementação deve respeitar a própria documentação de release do projeto e preservar os gates de produto existentes.

## 24. Fechamento: a direção que vale perseguir

A identidade mais forte do FeedMine é **descoberta editorial da internet aberta**, apresentada com a naturalidade de um feed contínuo, sem pedir ao usuário que configure uma infraestrutura de RSS. Para sustentar essa identidade, o conteúdo não pode ser apenas corretamente adquirido: deve ser **bem escolhido, bem composto, atribuível, consumível e fácil de reencontrar**.

O mercado oferece peças valiosas: o feeeed demonstra que uma timeline heterogênea pode ser agradável; o Tapestry, que controle sobre filtros precisa ter semântica explícita; o Reeder, que a posição de leitura é um bem precioso; o NewsBlur, que performance percebida e interface estão ligadas; o Unread, que tipografia importa; o Readwise, que biblioteca não é feed; o Flipboard, que a linguagem de revista pode valorizar histórias; o Pinterest, que uma descoberta pode abrir outra. **Nenhum desses produtos fornece, isoladamente, a resposta do FeedMine.**

A V2 já possui os contratos técnicos capazes de preservar a leitura publicada. A recomendação é explorar **quatro composições editoriais claras**, reorganizar as ações conforme a intenção do usuário, manter a biblioteca distinta da descoberta e provar o ganho com o aplicativo real. O critério de sucesso não é a quantidade de estilos nem uma nota cosmética: é a pessoa abrir o FeedMine, encontrar algo verdadeiramente interessante, consumir sem fricção e voltar para descobrir mais.

**Próximo passo concreto:** captura comparativa da V2 atual com o corpus editorial descrito na seção 17; só então escolher qual variante de card/header merece implementação. O estudo deve funcionar como documento orientador de UX, subordinado ao North Star, ao Blueprint v0.4, às decisões de produto e aos invariantes de publicação já estabelecidos.

