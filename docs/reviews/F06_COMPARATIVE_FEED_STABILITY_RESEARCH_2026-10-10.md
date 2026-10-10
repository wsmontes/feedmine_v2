# F06 — Pesquisa comparativa: como feeds grandes protegem a leitura

**Data:** 2026-10-10  
**Escopo:** investigação de produto/engenharia para FeedMine V2; **não** aprova implementação, não muda PRD/benchmark e não pressupõe que o código privado atual das empresas seja idêntico ao descrito em publicações históricas.  
**Fonte de verdade para FeedMine:** [norte de produto](../product/PRODUCT_NORTH_STAR.md), [B04](../product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [PD-5 e PD-6](../product/PRODUCT_DECISIONS_2026-10-09.md), [INV-08 e INV-09](../architecture/PRODUCT_INVARIANTS.md).

## Conclusões sustentadas pelas fontes

**1. Instagram — evitar refresh involuntário que desloque o leitor.** Em março de 2018, o Instagram anunciou/testou o botão **New Posts**, deixando a pessoa escolher quando acessar a nova leva, depois de reconhecer que refrescar automaticamente e mandar o leitor ao topo prejudicava a experiência. A evidência é histórica; **não demonstra** que esse botão ainda existe, que todos os clientes atuais implementem o mesmo fluxo, ou como o Instagram gerencia buffers internos em 2026. Em 2022, o Instagram documentou controles **Following** e **Favorites** como visões cronológicas em contraste com o Home com recomendações.

Fontes: [relato com declaração do Instagram, 2018](https://www.socialmediatoday.com/news/instagrams-adding-new-ways-to-uncover-recent-posts-in-variance-to-the-cur/519787/); [anúncio oficial, 2022](https://about.fb.com/news/2022/03/two-new-ways-to-control-your-instagram-feed/).

**2. Facebook Feed — selecionar do estoque local o próximo conteúdo pronto.** Documento de engenharia da Meta de 2016 relata um pool de matérias ainda não vistas, armazenadas localmente, integrado a novidades do servidor. O aplicativo podia **reclassificar itens não vistos** conforme a prontidão de imagens/vídeos e a qualidade da conexão; selecionar o próximo item a cada avanço do usuário e evitar caixas cinzas e spinners. Assim, o conteúdo já disponível dá fluidez enquanto a internet fornece novos candidatos. O artigo não estabelece garantia universal de imutabilidade de todo o prefixo exibido, nem descreve necessariamente a implementação atual do Instagram.

Fonte: [Client-side ranking to more efficiently show people stories in feed, Meta Engineering, 2016](https://engineering.fb.com/2016/10/20/networking-traffic/client-side-ranking-to-more-efficiently-show-people-stories-in-feed/).

**3. Facebook Video Feed — buscar antes, apresentar apenas quando necessário.** Artigo de dezembro de 2024 separa **prefetch**, carga inicial, solicitação de cauda, pool em memória e entrega ao componente visual. Enfatiza apresentação conforme sinais de consumo, mídia pré-preparada, ordenação decidida por ranking e cache quando a rede demora. Como detalhe da implementação relatada, há um limiar explícito para novos pedidos de cauda. **Esse limiar local e datado não deve ser convertido em cota ou timer universal do FeedMine**. O princípio útil é separar aquisição, reserva e apresentação e ajustar os custos à experiência de consumo.

Fonte: [Inside Facebook’s video delivery system, Meta Engineering, 2024](https://engineering.fb.com/2024/12/10/video-engineering/inside-facebooks-video-delivery-system/).

**4. X/Twitter — distinção de visões e relevância; não há prova pública equivalente da estabilidade física.** O Help Center atual descreve **For you** personalizado e **Following** limitado às contas seguidas. Na documentação específica de recomendação, Following aparece em ordem cronológica reversa. O X também documenta retorno à aba anteriormente aberta. O Twitter publicou engenharia de classificação de posts e cache, mas não encontramos nessas fontes um contrato público preciso de posição física estável, preservação de offset após uma atualização e proibição de inserções sobre o leitor. **Não afirmar** que o X implementa a mesma fronteira de imutabilidade proposta para FeedMine.

Fontes: [X Help — timeline](https://help.x.com/en/using-x/x-timeline); [X Help — For You](https://help.x.com/en/resources/recommender-systems/for-you-home-timeline-recommendations); [Twitter Engineering — timeline prediction, 2020](https://blog.x.com/engineering/en_us/topics/infrastructure/2020/streaming-logging-pipeline-of-home-timeline-prediction-system).

**5. Reddit — cálculo antecipado da geometria e separação de rede e UI.** Post de engenharia do app iOS de 2017 descreve um feed de scroll contínuo com gerenciamento de rede separado do controller e cálculo **antecipado do tamanho dos cards** em background, antes do scroll, evitando cálculos caros na thread principal. Trata-se de engenharia histórica, não prova de que a posição nunca seja perdida. Há relatos públicos de usuários perdendo o ponto de leitura ao alternar aplicativos (evidência anedótica, não garantia da empresa), razão adicional para testar retorno/posição em hardware real.

Fontes: [Building the Feed for the Reddit iOS App, Reddit, 2017](https://redditinc.com/news/building-the-feed-for-the-reddit-ios-app); [relatos de regressão de posição no Reddit iOS, 2025](https://www.reddit.com/r/bugs/comments/1i26l2h/ios_losing_place_in_feed_after_leaving_app_for/).

**6. Ferramentas de lista móvel — proteger âncora visível e não reordenar a lista acima dela.** A documentação do React Native expõe `maintainVisibleContentPosition`, que conserva a posição da primeira célula visível ao inserir conteúdo; também avisa que **reordenar itens pode causar saltos**. É evidência pública de uma técnica de interface, não prova de que Instagram ou X usem esse componente.

Fonte: [React Native ScrollView](https://reactnative.dev/docs/scrollview).

## Síntese: padrão, variação e limites da analogia

**Padrão compartilhado nas fontes:** preparar candidatos e mídia antes de apresentar, desacoplar rede da lista visível, tratar material ainda não apresentado como oportunidade de melhorar a escolha e evitar mudanças involuntárias de posição. **Não há uma implementação única** de feed infinito: Instagram, X, Facebook e Reddit são produtos majoritariamente baseados em servidores próprios; o FeedMine consulta milhares de fontes externas em um modelo local-first, com orçamento de rede e armazenamento bem distinto.

**Diferença de produto:** os exemplos mostram que melhorar conteúdo futuro é desejável, mas alguns sistemas podem reclassificar ou atualizar o feed com mais liberdade que a prometida pelo FeedMine. O princípio do FeedMine é deliberadamente mais estrito: o que foi **admitido na sequência de leitura** é estável; conteúdo ainda não admitido pode ser continuamente adquirido, enriquecido e reordenado. Isso preserva a decisão discutida com o product owner sem bloquear preparação antecipada.

## Implicações recomendadas para F06

1. **Fronteira da leitura:** antes da admissão, a história é supply/candidata/preparação e pode mudar de prioridade, imagem ou formato. Depois da admissão, o card conserva ID, posição relativa, texto, ação e layout. Novidades só entram no avanço legítimo ou transição explicitamente escolhida.
2. **Mídia:** decidir layout e geometria antes da admissão. Card `textOnly` não vira `hero` por chegada tardia de mídia. Se o contrato já prevê slot de imagem, materializar/redecodificar **os mesmos bytes referenciados** dentro dele não deve mudar geometria, texto nem identidade; testar separadamente variações apenas de pixels.
3. **Atualizações de matéria:** edição material vira nova ocorrência elegível para posição futura, nunca reescrita do card que a pessoa já recebeu (PD-1).
4. **Mudança de contexto, refresh, retorno e rotação:** preservar âncora e offset sempre que a geometria/escopo permitir. Mudanças explícitas de escala da fonte e orientação podem alterar medidas legítimas, mas não podem fingir gesto de scroll, descartar posição ou misturar callbacks antigos.
5. **Recursos:** proteger primeiro UI e runway; trabalho especulativo/media adapta-se ao orçamento real (PD-8/INV-16), sem número mágico de cards ou polling.
6. **Prova:** B04 exige snapshots de IDs, ordem, bounds e deslocamento físico durante mídia tardia, fonte lenta, revisão de notícia, retorno de background e leitura imóvel prolongada; validar em iPhone real. Não rebaixar os critérios do benchmark.

## Questão de compatibilidade já identificada no repositório

[PD-5](../product/PRODUCT_DECISIONS_2026-10-09.md) permite re-preparar **cards publicados mas ainda não vistos** quando o app fica inativo. [B04](../product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) exige que o **prefixo admitido** e sua geometria não sejam alterados silenciosamente. A posição proposta após a conversa é: **a imutabilidade começa na admissão na sequência disponível, não apenas depois da visualização ocular**. Portanto, implementar eventual aprimoramento somente no estoque ainda **não admitido**, ou em uma nova transição claramente deliberada; não criar mecanismo de remendo da cauda já admitida só para trocar imagem.

**Estado:** pesquisa externa concluída e vinculada a fontes; **não** constitui teste ou prova de funcionamento da V2. Não modificar PD-5 ou código até registrar explicitamente a consequência dessa decisão numa especificação de F06.
