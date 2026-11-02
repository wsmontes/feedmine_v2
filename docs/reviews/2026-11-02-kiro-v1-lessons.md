# O que a V1 ensina para os problemas atuais da V2 — 2026-11-02

V1: `wsmontes/feedmine-dev` `b5c2f59c` (clone local `C:\Users\RL3B\feedmine-dev`). V2: `origin/main` `2eca5b4`.
Leitura de código, mais simulação (`evidence/2026-11-02-v6-sequencing-sim/`). Os problemas da V2 citados estão em
`2026-11-02-kiro-randomization-diversity-review.md` e `2026-11-02-kiro-feed-scenarios-study.md`.

Restrições respeitadas: `docs/v1-study/V1_GOLD_DO_NOT_PORT_2026-10-10.md` (não portar motores, WhatsNew,
shake-flush, auto-limpeza de filtro sem aviso, allowlist rígida), a diretiva do dono de 24/out (nunca publicar
card sem a imagem declarada; shuffle amplo é obrigatório) e os invariantes de publicação imutável.

## 1. Ordem: a V1 resolve o problema que o v6 criou

A ordem final da V1 é `EditorialSequencer.sequence` (`EditorialSequencer.swift:42-91`): **round-robin pelo
provedor menos usado**. Cada passo pega o provedor que contribuiu menos até agora, nunca o anterior enquanto
houver outro, desempate pela posição de entrada. Isso dá a cada provedor ~1/P da sequência sem teto explícito.
O comentário registra duas alternativas que falharam ("puxar o provedor diferente mais próximo" e "próximo item
mais cedo" só alternam os dois primeiros).

Mesmas ofertas da simulação, 50 primeiros cards:

| Oferta | v6 (V2 atual) | V1 | Híbrido (V1 primeiro, v6 dentro do empate) |
|---|---|---|---|
| A: 1 podcast + 20 textos | **POD 25/50**, áudio 25 | POD 3/50, áudio 3 | POD 3/50, áudio 3 |
| B: 4 podcasts + 20 textos | P0 7/50, áudio 25 (1 a cada 2) | máx 3/50, áudio 9 | máx 3/50, áudio 9, distância média de áudio 6 |
| C: 1 blog com tags novas + 19 | **TAGGY 24/50** | 3/50 | 3/50 |
| D: 1 prolífica + 19 pequenas | 3/50 | 3/50 | 3/50 |

Lições:
- **Portar** a participação igual por fonte como primeira regra do v7. O tipo e o assunto do v6 escolhem só
  entre as fontes empatadas na menor participação (híbrido). A participação de tipo passa a seguir a de
  provedores (B: 9 de 50 com 4 de 24 provedores), sem o rodízio igualitário que dava 25 de 50.
- **Portar** as verificações sobre a sequência produzida (`consecutiveRunIssues`, `leadingProviderCount`,
  `EditorialSequencer.swift:96-121`) como métricas/asserts.
- **Portar** a chave de provedor que funde agregadores (`Reservoir.providerKey`, `Reservoir.swift:539-549`:
  todos os feeds do Google News são um provedor). A V2 tem o mesmo risco com feeds gerados.
- **Fraqueza conhecida da V1:** participação igual ignora relevância e pesos de preset. Se a V2 quiser pesos,
  usar round-robin por déficit ponderado, não multiplicação.
- **Não portar** o resto da pilha de ordem da V1: pesos de slot proporcionais ao volume da fonte
  (`Reservoir.swift:338-345`), descarte proporcional (`:586`), cinco camadas que se desfazem, e `shuffled()` sem
  seed em todas elas. A aleatoriedade da V1 era opaca e irreprodutível; na V2 o desempate deve ser um seed
  persistido da Edition.

## 2. Janela de candidatos e cotas

| V1 | V2 hoje | Lição |
|---|---|---|
| Fatias por mídia na leitura SQL (texto ilustrado 300, texto 3.700, vídeo 500, áudio 500, fórum 100; `FeedStore.swift:5880-5922, 6052-6056`) | 128 mais novos globais | Portar a ideia de fatias por fonte/mídia, com custo da V2 (keyset por fonte, não 5.000 linhas) |
| `balancedCandidatePool`: no máximo 8 por provedor, sobra em round-robin, reserva por mídia sem deixar uma fonte gastar a reserva (`FeedStore.swift:6058-6139`) | sem teto por fonte | Portar o teto por fonte antes da ordem |
| Cota por tópico no começo: `ROW_NUMBER() OVER (PARTITION BY category)` intercalando tópicos (`FeedStore.swift:1394-1480`) | união e um corte global por qualidade | Portar a partição por interesse antes do corte |
| `showcaseSources`: round-robin por idioma, papel editorial, escopo, mídia e tópico (`CuratedPreferenceEngine.swift:282-310`) | top-120 por qualidade em ordem alfabética | Portar o round-robin multidimensional na formação do pool |

## 3. Memória do leitor: a V1 tinha o que falta na V2

- **Visto global por item** (`consumed_at`), gravado a 50% de visibilidade (`FeedScreen.swift:887-890`,
  `FeedStore.swift:3818-3830`); **toda** consulta que monta o feed exclui consumidos e lidos, em qualquer filtro,
  preset ou região (`FeedStore.swift:5754-5761`, `604-609`). Na V2 o visto é por Edition e volta ao trocar filtro.
- **Clicado** (`clicked_at`, `opened_at`, `is_read`; `markAsClicked`, `FeedStore.swift:3852-3888`); o card
  aparece esmaecido; "Último aberto" é `ORDER BY clicked_at DESC LIMIT 1000` (`FeedStore.swift:4237-4254`).
  Na V2 abrir não grava nada e o preset não faz nada.
- **"Não lido" não devolve à fila**: limpa `is_read`, mantém `consumed_at` (`FeedStore.swift:3941-3958`).
- Aprendizado por clique só em feed curado com aprendizado ligado, com passo pequeno (+0,055; `CuratedPreferenceEngine.swift:788-818`).

Lição: **portar o modelo** (visto por história, aberto por história, consultado por toda Edition nova), mantendo a
prova da V2 de que o card foi realmente desenhado. A V2 ainda precisa resolver o que a V1 também não resolveu: a
mesma história de fontes diferentes (o id da V1 inclui a URL da fonte, `FeedItem.swift:393-406`).

## 4. Tempo e volta do leitor

| V1 | Lição para a V2 |
|---|---|
| Janela de 30 dias na consulta e limpeza (`FeedStore.swift:1357-1364, 7205-7231`) | Portar uma idade máxima; usar data de publicação, não de busca |
| Balde "velho": notícia > 24 h e perene > 7 dias vão para depois dos recentes (`Reservoir.swift:316-335`) | Portar como peso de recência, não só desempate |
| `refreshIfStale`: busca ao voltar se passaram 15 min ou há menos de 10 cards (`FeedStore.swift:2957-3000`) | Portar o gatilho; a V2 hoje só reage à rolagem e à cadência |
| WhatsNew em carrossel e shake que esvazia o feed | **Não portar** (já vetado). A necessidade continua: oferecer uma Edition nova, sem rearranjar a atual |
| Background: só smart feeds (`BackgroundRefreshService.swift`) | A V1 também não buscava em background; isso seria novo nos dois |

## 5. Filtros

- A V1 filtra **antes do limite**: fontes antes de buscar (`FeedStore.swift:3695-3727`) e região, tipo e idioma
  no SQL (`FeedStore.swift:5762-5800`), com estado vazio mostrando progresso de busca. Na V2 o filtro vem depois
  da janela de 128 e passa fome. **Portar.**
- Idioma por item: alfabeto, depois `NLLanguageRecognizer`, sobrepondo o idioma declarado só com ≥48
  caracteres, confiança ≥0,80 e margem ≥0,15 (`FeedStore.swift:415-470`). **Portar** (o plano FM59 pede o mesmo).
- Humor: a V1 tinha o **mesmo** filtro quebrado (substring em inglês só no título, `FeedLoader.swift:279-301`).
  Não portar; nenhuma das versões resolveu.

## 6. Preparação de cards

- A V1 publica como **card de texto** quando a imagem perde o prazo (`CardPreparationCoordinator.swift:405-437`,
  `612-620`). **Não portar:** contraria a diretiva de 24/out e PD-5/INV-17.
- **Portar** o que não conflita:
  - prazo por posição (6 s nos 20 primeiros, 15 s até 120, 30 s depois; `RunwayPolicy.swift:28-34`), em vez de
    uma janela por oportunidade;
  - busca de imagem no artigo (og:image, twitter:image, srcset 720–1600w, JSON-LD; HTML ≤192 KB, 4 simultâneas,
    cache de falha de 5 min; `ImageCache.swift:162-330`). Aumenta a oferta de cards com imagem real, que é a
    alavanca de volume que a diretiva pede;
  - filtros de imagem decorativa, pixel de rastreio e logo no parse (`RSSFetcher.swift:1106-1149, 1240-1272`),
    tamanho mínimo (lado menor ≥180, maior ≥480; `ImageCache.swift:72-103`). A V1 não tinha limite de proporção;
    acrescentar.
- A V1 também não tinha memória de latência por host.

## 7. Oferta e qualidade

- **Agendamento de busca** (`AdaptiveScheduler.swift`): `Retry-After`, `skipHours`/`skipDays`, intervalo mínimo
  por `Cache-Control`/`ttl`/cadência estimada, urgência 1,0 para fonte nunca buscada, backoff `2^(f-2)·60 s` até
  24 h, seleção do lote com penalidades por categoria/mídia/região (`diverseSources`, `:432-474`). **Portar**;
  substitui a ordem por UUID. **Não portar** a multiplicação de déficits (zera o score) nem o bônus fixo de 2×
  para áudio/vídeo.
- **Cobertura**: meta de 100 fontes distintas armazenadas, fontes não buscadas em ordem aleatória, cursor que
  gira pelas categorias da taxonomia (`FeedStore.swift:5293-5361`). **Portar** a meta e o cursor; o embaralhamento
  vira seed.
- **Portões de item**: título vazio descartado (`RSSFetcher.swift:961-967`); para a abertura, título de 12 a 190
  caracteres, até 85% maiúsculas, sem título-URL, termos promocionais, resumo ≥20, títulos repetidos dobrados
  (`CuratedPreferenceEngine.swift:503-519`). **Portar** para o feed todo, com cuidado para títulos curtos em
  alfabetos não latinos.
- **Avaliação editorial** (autoridade, institucional, especialista, comercial, agregador, host genérico;
  `CuratedPreferenceEngine.swift:169-249`): **portar como sinal**, não como portão (o veto de allowlist rígida
  continua valendo).
- Feed até 20 MB em streaming (`FeedHTTPSync.swift:123-148`) contra 1 MB na V2: subir o teto da V2 para alguns MB.

## Ordem sugerida

1. **v7 de ordem** = participação igual por fonte (V1) + tipo/assunto dentro do empate (v6) + desempate por seed da
   Edition; métricas `leadingProviderCount`/`consecutiveRunIssues`; chave de provedor com agregadores.
2. **Memória por história**: visto e aberto fora da Edition; "Último aberto" funcional; estilo lido.
3. **Janela e cotas**: teto por fonte, fatias por mídia, partição por interesse; filtro antes do limite.
4. **Tempo**: idade máxima, peso de recência, busca ao voltar depois de N minutos, Edition nova oferecida.
5. **Oferta**: agendador com gates HTTP e urgência; meta de cobertura com cursor persistido.
6. **Preparação e qualidade**: prazo por posição, og:image, filtros de imagem, portões de item, idioma por item.

O item 1 tem prova por simulação; os demais precisam de corpus controlado e depois de aparelho.
