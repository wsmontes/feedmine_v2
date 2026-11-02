# Estudo de cenários do feed: variedade, repetição, frescor e qualidade — 2026-11-02

Continuação de `2026-11-02-kiro-randomization-diversity-review.md`. Base `origin/main` `2eca5b4`
(idêntica ao branch `kiro/review-fixes-20261102` nestas partes). Tudo por leitura de código; nada medido
em aparelho. **V** = caminho lido; **S** = suspeita (um elo não lido).

## Resumo

O feed é um funil estreito e determinístico, sem noção de tempo nem memória do leitor fora de uma Edition:

1. **Oferta:** descoberta alfabética que recomeça a cada abertura; pool fixo de 120; janela dos 128 itens
   mais novos de todas as fontes; aquisição na ordem de UUID.
2. **Ordem:** v6 lexicográfico (tipo → assunto → fonte); sem teto por fonte; sem seed.
3. **Identidade:** cada filtro, preset ou contexto é uma Edition separada, com o seu "visto" e a sua posição.
4. **Tempo:** nenhuma política de idade, nenhuma Edition nova na volta do leitor, refresh em background só
   confere o catálogo.
5. **Velocidade decide composição:** a primeira tela e cada oportunidade publicam o que ficou pronto
   primeiro.

## Cenário 1 — primeira execução

| Passo | O que acontece | Evidência |
|---|---|---|
| Fontes contatadas | Até 48 alvos planejados, 8 simultâneos, na ordem de **UUID** (anel mecânico) | `AcquisitionPlanner.swift:103-123`, `CollectionLaunchSettings.swift:27-49` V |
| Gatilho da 1ª publicação | O **primeiro** alvo que traz oferta selecionável dispara a publicação do Segmento 0 | `ColdFeedBootstrap.swift:244-259` V |
| Base do Segmento 0 | Janela dos 32 mais novos do banco naquele instante; nenhum piso de cards, fontes ou cobertura | `InitialProductionSlice.swift`, `ColdFeedBootstrap.swift` V |
| Ordem | v6 sem histórico; tipo/assunto/fonte só dentro do lote | `SelectionEngine.swift:177-183` V |
| Fontes lentas | Só entram em segmentos seguintes (anexados) | `ColdFeedBootstrap.swift:253` V |

**O leitor vê:** a abertura composta pelo feed (ou poucos feeds) que respondeu primeiro, até 32 cards.
Isso contraria F02:96 ("a primeira aquisição não pode ser determinada apenas por quais feeds responderam mais
rápido") e a meta do plano de variedade (≥10 fontes nos 12 primeiros). Somado ao gate de prontidão (cenário 6),
itens sem imagem e áudio tendem a dominar essa abertura. **Alta, V.**

## Cenário 2 — reabertura

| Pergunta | Resposta | Evidência |
|---|---|---|
| Volta ao mesmo lugar? | Sim: mesma Edition, mesmo card e deslocamento | `AppComposition.swift:739-753`, `FeedSession.warmStart` V |
| Quando nasce uma Edition nova? | Só na primeira execução, num ContextKey sem checkpoint, ou quando a revisão editorial deixa de valer. **Nunca por tempo** | `PublicationCoordinator.createInitialEdition` (único chamador: `InitialProductionSlice`) V |
| Conteúdo novo entra onde? | **Depois da cauda**: o leitor rola pelos cards já publicados e não vistos (reserva de 32 + janela) antes do novo | `LocalProductionSlice.swift:233`, reserva `AppComposition.swift:3419` V |
| Idade do topo depois de dias? | Ilimitada; não há política de idade | grep de `maxAge`/`freshness`/`isStale`: vazio V |
| Refresh em background? | Só confere o manifesto do catálogo; não busca feeds nem publica | `AppComposition.swift:911-920` V |
| Descoberta depois de um kill | Recomeça na primeira chave alfabética | `ReaderDiscoveryTraversal.swift:27` V |
| "Novas histórias" / Edition mais nova (F20 R2/R3) | Não implementado | nada encontrado V |

**O leitor vê:** depois de um dia fora, abre exatamente onde parou, com cards velhos à frente e nada novo
até rolar a reserva inteira; a primeira busca de rede só começa em foreground. **Alta, V.**

## Cenário 3 — cards já vistos

- "Visto" é **por Edition**: `exposure` e `markSeen` filtram por `edition_id`
  (`PublicationStore+History.swift:13-50, 95-130`). V
- A Edition é **por ContextKey** (pedido + preset + filtro + escopo; `resolveHistoryBinding`,
  `AppComposition.swift:2251-2334`). V
- **Consequência (Alta, V):** ao trocar filtro, preset, fonte, coleção ou busca, histórias que o leitor acabou
  de ver voltam, inclusive no topo. Uma troca de versão de pontuação reinicia até o mesmo contexto.
- **Fling (Média, V):** `markSeen` marca seen tudo entre o high-water anterior e a nova âncora
  (`PublicationStore+History.swift:33-37`): cards pulados sem aparecer contam como vistos.
- Só a âncora é reportada; cards visíveis abaixo dela esperam a âncora passar (conservador). V
- Atualização material de uma história vista volta como card novo na mesma Edition (PD-1 regra 2,
  `SelectionExposure.swift:36-44`). V
- Mesma história de veículos diferentes: dois origins, nenhuma ligação (`contentClusterID` sempre `nil`,
  `AppComposition.swift:4241`). S para fusão a montante.

## Cenário 4 — conteúdo clicado

- Abrir um card **não grava nada** (`open`/`read`, `AppComposition.swift:3291-3321`). V
- O estilo "lido" existe e nunca é ligado (`isRead` não é passado em `FeedScreen`). V
- Não há sinal de clique para descoberta, pesos ou exclusão futura. V
- O preset **"Último aberto"** (`.lastClicked`) aparece no filtro e não faz nada além de criar outra
  Edition (`ReaderFilter.swift:136-146`, `AppComposition.swift:1355`). **Média, V.**
- Salvar (bookmark) não influencia seleção; só retenção de mídia. V
- Votos "mais/menos" do convite gravam o perfil e **não reconstroem** a sessão (por decisão, comentário em
  `AppComposition.swift:2530-2572`): o assunto rejeitado continua vindo até a próxima reconstrução
  (reabertura ou troca de contexto). **Média, V** no código; o momento exato da aplicação é S.

**O leitor vê:** ler um artigo não muda nada; o mesmo artigo pode reaparecer em outro filtro; "Último aberto"
mostra um feed comum.

## Cenário 5 — mudança de filtro e de contexto

- Cada filtro diferente é outra Edition: ou nova (preparação do zero), ou a antiga daquele filtro, restaurada
  com posição e cards de dias atrás. Nada é filtrado no lugar. V
- **Fome de filtro (Alta, V mecanismo):** o filtro é aplicado **depois** da janela de 128
  (`CandidateProvider.swift:91-161`); o cursor avança pelo examinado, não pelo elegível. Filtros estreitos
  examinam 128, aproveitam poucos e chegam a "Sem histórias" com conteúdo compatível mais fundo ou em fontes
  não buscadas. Se a esteira pagina várias janelas por oportunidade: S.
- **Humor errado em português (Alta, V):** palavras-chave do V1 em inglês, por substring, só no título
  (`ReaderFilter.swift:59-79`, `ReaderFilterEligibility.swift:83-86`). "ai" casa "m**ai**s"/"p**ai**s",
  "fun" casa "**fun**ção", "war" casa "soft**war**e", "ban" casa "**ban**co". Títulos em PT quase nunca casam de
  verdade.
- **Idioma (Média, V):** a elegibilidade rejeita item sem idioma declarado
  (`ReaderFilterEligibility.swift:76-77`), mas a aquisição mantém fontes sem idioma
  (`SyndicationAcquisitionSnapshot.swift:186-189`): banda gasta em conteúdo que nunca aparece.
- Região, tópico e tipo não são aplicados (`enforceable = [.preset, .languages, .mood]`). A folha não os
  oferece; só chegam por presets/receitas. **Baixa, V.**
- Expiração de 4 h aplicada no lançamento troca a identidade em silêncio: o leitor cai noutra Edition sem
  aviso (`AppComposition.swift:704-719`). **Média, V.**
- Abrir uma coleção descarta o filtro atual (`openCollectionFeed`, filtro `.unrestricted`). **Baixa, V.**
- Exclusões de palavra/fonte nos ajustes valem só para publicações futuras; cards já mostrados ficam
  (`AppComposition.swift:4482-4491`). **Baixa, V.**

## Cenário 6 — preparação de cards

- Pronto = imagem baixada e decodificada, ou item que não declara imagem (`MediaPrefetcher.swift:65-96`). V
- Sem imagem pronta, o card não entra (INV-17/PD-5, `PublicationPreparation.swift:56-79`). Depois de 3 falhas
  transitórias, a revisão é esgotada; nunca vira card de texto. V
- **Viés de velocidade (Alta, V mecanismo; magnitude S):** a seleção só vê candidatos prontos, e a janela de
  mídia fecha por oportunidade (12–20 s). Hosts rápidos e itens sem imagem (áudio, link-blogs) chegam primeiro;
  fotos de hosts lentos entram depois ou nunca.
- Sem memória de custo por host: cada item novo de um host lento paga a espera inteira de novo
  (`MediaPrefetcher.swift:359`). **Média, V.**
- Calor crítico ou offline proíbem mídia remota (`MediaPolicy.swift:150-152`): só cards de texto publicam;
  feeds de imagem chegam ao fundo. **Média, V.**
- Encaixe de imagem sem limite de proporção (banners, logos como hero; `MediaPolicy.swift:172-180`). **Baixa, V.**
- Revisão esgotada pode continuar na fila de reconsideração (teto 128 no app) ocupando lugar. **Média, S.**

## Cenário 7 — bufferização

- Reserva mínima de 32 cards (comentário: ~32 s a 1 card/s), janela apresentada 8 atrás / 16 à frente,
  reserva preparada alvo 96 (`AppComposition.swift:3411-3431`, `PreparedReserve.swift:158`). V
- Por oportunidade: examina 128 (64/48/32 sob pressão), publica até 32. A seleção vê uma fatia pequena, e a
  diversidade fica limitada à fatia. V
- Oportunidades: rolagem, mudança de prontidão de mídia, oferta durável nova, cadência de 10 s em foreground. V
- Em background nada é buscado (cenário 2). V

## Cenário 8 — qualidade do conteúdo

| Regra | Estado | Evidência |
|---|---|---|
| Qualidade da fonte | Só **ordena** a aquisição (0,55 qualidade + 0,30 atividade + 0,15 latência) | `AcquisitionTargetOrdering.swift:51-66` V |
| Idade máxima de item (F02:84) | **Não existe** | V |
| Título vazio, resumo curto, spam, clickbait (F02:86) | Não existem | `SyndicationTranslator.swift:82-87` V |
| Datas futuras | Recortadas para o momento da observação | `SyndicationTranslator.swift:50-61` V |
| HTML no resumo | Removedor léxico, não DOM | `ReadablePublicationText.swift` V |
| Idioma | Do canal (RDF sem), mais checagem de alfabeto | `SyndicationTranslator.swift:125-129` V |
| Fonte quebrada | Resfriamento exponencial; nunca desativada | `AcquisitionBackoff.swift` V |
| Feed > 1 MB | `bodyTooLarge`; tratamento como falha ou truncamento: S | `SyndicationHTTP.swift:74` |

## Causas-raiz que atravessam os cenários

| # | Causa | Cenários |
|---|---|---|
| R1 | Funil de oferta estreito e determinístico (alfabeto, top-120, 128 globais, UUID) | 1, 2, 5, 7 |
| R2 | Ordem lexicográfica tipo > assunto > fonte, sem teto e sem seed | 1, 7 |
| R3 | Memória do leitor presa à Edition, e Edition presa ao ContextKey | 3, 4, 5 |
| R4 | Ausência de tempo: idade, volta do leitor, background | 2, 8 |
| R5 | Prontidão por janela de tempo decide a composição | 1, 6 |

## Direção proposta (dentro dos invariantes: nunca reescrever o publicado, PD-4/PD-5, sem aleatoriedade opaca)

1. **Memória do leitor por história, não por Edition** (R3): um registro de exposição/abertura por
   `originRecordID` (e identidade de história quando houver), consultado por toda Edition nova. Visto e aberto
   deixam de voltar ao trocar filtro; aberto liga o estilo "lido"; "Último aberto" passa a mostrar os abertos.
2. **Política de volta** (R4, F20): na reabertura depois de um intervalo, com oferta nova pronta, oferecer
   "Novas histórias"; o toque abre uma Edition nova; a antiga fica no histórico. O refresh em background passa a
   adquirir (sem publicar), para a volta já ter oferta.
3. **Idade e qualidade mínima** (R4, F02:84/86): idade máxima por contexto (fonte única isenta), título não
   vazio, resumo mínimo; ordem com peso de recência, não só desempate.
4. **Coorte antes da 1ª publicação** (R5, F02:96; plano FM59 passo 3): publicar o Segmento 0 quando houver K
   fontes distintas prontas ou ao fim de um prazo curto, nunca no primeiro feed que responder.
5. **v7 de ordem** (R2): distância mínima por fonte como restrição; tipo e assunto proporcionais à oferta;
   desempate por seed persistido da Edition.
6. **Funil mais largo** (R1): cursor de descoberta persistido ou partida semeada; cota por interesse antes do
   corte por qualidade; janela de candidatos com rodízio por fonte, em vez dos 128 mais novos globais; aquisição
   preferindo alvos nunca buscados.
7. **Filtros honestos** (cenário 5): paginar janelas até K elegíveis antes de declarar fim; humor com palavras
   em PT, limite de palavra e resumo, ou esconder humor até lá; com filtro de idioma, não buscar fontes sem idioma
   (ou detectar idioma do item, como o plano FM59 propõe).
8. **Preparação** (R5): memória de latência por host para não pagar a espera de novo; limite de proporção no
   hero.

Cada mudança de ordem exige versão nova de sequenciamento; mudanças de identidade (memória do leitor) exigem
migração com teste de reabertura nos dois lados.

## Como validar sem aparelho primeiro

- Estender `evidence/2026-11-02-v6-sequencing-sim/` para sequências multi-oportunidade: primeira execução com
  chegada escalonada de fontes, reabertura com reserva não vista, troca de filtro, filtro estreito.
- Métricas (as do plano FM59 mais estas): fontes distintas nos 12/50 primeiros; maior participação de uma fonte
  em janela de 50; idade do card no topo na reabertura; repetição de `originRecordID` entre contextos; cards
  "Sem histórias" com oferta compatível existente; fração de cards sem imagem nos 50 primeiros.
- No Mac: os mesmos números a partir dos traços existentes (`ReplenishmentTrace`, `RunwayTrace`,
  `FeedLaunchWitness`), primeiro num corpus controlado, depois no catálogo real.
