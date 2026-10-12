# Rodada 3 — continuidade do feed, proteção do catálogo e parecer do PO

Data: 2026-10-11. Autor: sessão OMP. Investigação: nenhuma linha de código alterada, nenhum commit.
Corrige, também, uma afirmação minha da rodada 2 sobre onde o harness escreve o catálogo de benchmark.

## 1. Continuidade do feed (diagnóstico)

### 1.1 Instalação limpa

Ações: `simctl uninstall` + `simctl install` do build com o **catálogo real** (`source_count = 77443`);
namespace novo (`F4477FFD-…`); onboarding "Montar meu feed" (idiomas + Brasil). Vídeo:
`docs/evidence/2026-10-11-ux-diagnosis/R3-primeira-abertura.mp4`.

Medições no mesmo instante:

```
14:47:2x  cold bootstrap started            ("Abrir meu feed")
          primeiro card instalado ~3 s depois
store:    published_cards 22 · feed_segments 3 (1 + 1 + 20) · origin_records 419
          session_checkpoint → card 252520F1… (anchor=top)
trace:    window cards=0 → cards=0 (known_subjects=120) → cards=1 (resolved_sources=1)
          admitted cards=1 (head=tail=anchor=252520F1…)
          replenishment_concluded: 2 alvos (observations 10 e 32, supply_changed=true),
          destination = pool_admission
```

Renderização: **exatamente 1 card** na tela (Áudio "Duas e Tanto"), resto do espaço vazio.
O trace nunca registra outra janela depois disso: os 20 cards publicados no terceiro segmento
ficaram na reserva (`pool_admission`), não na janela admitida.

### 1.2 Reabertura (mesmo store, mesmo namespace)

```
14:51:56  composition: "local restore before HTTP"
```

Renderização: **vários cards** (o card de podcast + "O São Gonçalo — Jovem de 17 anos…" + outro
parcialmente visível), com os mesmos `received=0 completed=0 backward=0`.
Ou seja: o mesmo conjunto de 22 cards publicados vira uma janela de vários cards no caminho de
**restauração**, e uma janela de 1 card no caminho **frio**.

### 1.3 Gestos (executados com XCUI, não sintéticos)

Testes do próprio repositório, com swipe real, ambos **PASS**:

```
FeedMineUITests.testNativeSwipeReachesRealRunwayAndReverseNavigation ... passed (18,4 s)
FeedMineUITests.testT3ScrollAdmitsWithoutMovingTheReadingPoint ........ passed (22,6 s)
```

Eles provam: um `swipeUp` real completa uma oportunidade real do driver (`completed>=1`), um
`swipeDown` registra gesto de retorno (`backward>=1`), e o retorno do app ao foreground não troca a
associação nem move o ponto de leitura. Vídeo: `…/R3-gestos-xcui.mp4`.

Limite honesto: esses testes rodam com o transporte local de teste (`FEEDMINE_LOCAL_FEEDS=1`), não com
o catálogo real. Na sessão real eu **não** consegui entregar um gesto: o arrasto sintético
(`drag`) e a ação de rolagem por acessibilidade não produziram nenhum `native-capture` no log — ou
seja, o toque não chegou ao app. A prova do mecanismo vem dos testes; a prova do caso real
(catálogo real + swipe) fica pendente de instrumento.

### 1.4 Veredito: esperado ou defeito?

- **Mecanismo (contrato, não defeito):** `docs/architecture/RUNTIME_PRESENTATION_CONTRACT.md:65` —
  "Only `admitPresentation(.forwardScroll(observation))` extends the admitted list". A janela nasce do
  que está publicado no instante da primeira publicação; por isso ela tem 1 card, e o resto vai para a
  reserva. Com um gesto, a admissão funciona (1.3).
- **Experiência (defeito P0):** com 22 cards publicados, a primeira abertura mostra 1 card cercado de
  espaço vazio, sem indicação de continuidade, e depende de um primeiro gesto para materializar
  conteúdo **já publicado**. A reabertura do mesmo store apresenta vários cards: a primeira abertura é
  inconsistente com todas as seguintes.
- **Parecer do PO:** REPROVADO como estado estável (§3), com exigência de expansão automática da janela
  e indicação visual de continuidade.

## 2. Proteção do catálogo de avaliação

### 2.1 Mecanismo real (corrigindo a rodada 2)

O harness **não** escreve no repositório. `bench/run.sh:121-124` compila o app em
`$OUT/derived/Build/Products/…/FeedMine.app`; `:139-164` injeta ali o catálogo do corpus e um
descritor próprio (com `bench_corpus` no `catalog_metadata`); o runner então instala esse app
instrumentado no simulador **compartilhado**, sob o bundle id do produto
(`bench/run.sh:16` e `scripts/soak.py:43`: `com.feedmine.development`). Nada restaura o build de
produto depois: `scripts/soak.py` termina apenas encerrando o processo. Resultado medido: o simulador
fica com um app que *parece* o produto, mas cujo catálogo aponta para `http://127.0.0.1:8757`, vivo
somente durante uma corrida — foi exatamente o que a rodada 1 mediu sem saber.

### 2.2 Proposta

1. **Identidade (ou dispositivo) própria para o benchmark — recomendada.** Rodar o benchmark em um
   simulador dedicado (criado uma vez) e/ou instalar como `com.feedmine.development.benchmark`; nunca o
   id do produto. Arquivos: `bench/run.sh:16` (BUNDLE_ID), a seleção de device em `bench/run.sh:15-37`,
   `scripts/soak.py:43`. É robusto a execução interrompida, que é justamente o que "restaurar ao final"
   não cobre.
2. **Recusa explícita em avaliação de produto.** Novo `scripts/verify_product_catalogue.sh
   <FeedMine.app|container>`: falha se `catalog_metadata` contiver `bench_corpus` e exige
   `source_count = 77443`; citado no README e em `docs/IOS_RUN.md`. Opcional no app: registrar/recusar
   em `CatalogInstallation` (`FeedMineApp/FeedMineApp/AppComposition.swift:167`) quando o descritor
   declarar o benchmark.
3. **Tornar o catálogo visível.** O app já lê `catalog_metadata`; mostrar a origem do catálogo no
   overlay de DEBUG (ou numa linha de Ajustes) faz uma captura de tela dizer qual catálogo está em uso.

Rejeitado: "restaurar o arquivo ao final" — frágil diante de interrupção (o próprio Codex já apontou).

## 3. Parecer do PO (ChatGPT, thread "Assumir papel de PO")

> **Parecer do PO — Rodada 3.** Decisão: aprovo a proposta dos quatro estados, com ajustes de
> linguagem e uma exigência adicional para a janela de cards.
>
> **(a) Textos.**
> 1. *Buscando histórias* — APROVADO com ajustes. Título: "Descobrindo histórias para você…";
>    progresso: "1 de 2 fontes consultadas trouxe novidades."; complemento: "Encontramos: [manchete]".
>    Mostrar apenas fatos reais; não apresentar contadores como porcentagem de conclusão quando não
>    representam o trabalho total.
> 2. *Nova tentativa agendada* — REESCREVER. Título: "Procurando mais novidades…"; texto: "Ainda não
>    encontramos conteúdo suficiente. Vamos tentar novamente em instantes." Evitar "tentativa
>    agendada", expressão técnica; não simular progresso enquanto o motor aguarda.
> 3. *Falha de conexão* — APROVADO com ajustes. Título: "Não foi possível conectar."; texto: "Não
>    conseguimos buscar novas histórias agora." Só com evidência de falha de conexão; falhas
>    individuais de fontes não justificam esse estado global.
> 4. *Fontes consultadas sem histórias* — REESCREVER. Título: "Ainda não encontramos histórias para
>    você."; texto: "As fontes consultadas não trouxeram novidades para seus interesses." Usar somente
>    quando a tentativa terminou sem conteúdo elegível, não durante espera temporária.
>
> **(b) Ações.** "Tentar novamente": aprovado para falha e ausência de resultados, e deve iniciar uma
> tentativa real. "Ajustar interesses": aprovado para ausência de resultados; não deve aparecer como
> solução principal de falhas de conexão. Não adicionar mais ações nesta rodada. Quando já existem
> cards, os controles de recuperação não devem substituir o feed.
>
> **(c) Critérios de aceite** (exige demonstração no simulador, com catálogo real): na instalação limpa,
> o primeiro card aparece assim que estiver apresentável, sem aguardar artificialmente outros cards; os
> estados refletem o estado verdadeiro do motor, inclusive durante o ciclo de espera de ~21 s; nenhuma
> espera silenciosa parece travamento; progresso e manchetes são factuais e atualizados; cards já
> disponíveis continuam navegáveis durante aquisição e novas tentativas; falhas e ausência de resultados
> apresentam ações funcionais e apropriadas; **novos cards aparecem automaticamente, sem exigir refresh
> ou gesto de carregamento**; evidência em vídeo de primeiro uso, recuperação e ausência de conteúdo,
> acompanhada dos eventos correspondentes do runtime.
>
> **(d) Janela de 1 card — REPROVADO como estado estável.** "Se existem 22 cards publicados, apresentar
> apenas um com o restante da tela vazio é um defeito P0 de experiência." Não exige esperar um número
> arbitrário antes do primeiro card; exige: primeiro card assim que pronto; **expansão automática da
> janela com o conteúdo local disponível**; indicação visual evidente de continuidade, preferencialmente
> o próximo card parcialmente visível; nenhuma dependência de um primeiro gesto para materializar
> conteúdo já publicado. "Não considero a primeira experiência pronta enquanto houver 22 cards
> publicados e o usuário enxergar um único card cercado de espaço vazio, sem indicação de continuidade.
> Corrigir textos sem resolver isso não fecha a rodada."

## 4. Achado novo com o catálogo real: ATS bloqueia feeds http

No log de composição, ao reabrir:

```
execution failure Error Domain=NSURLErrorDomain Code=-1022 "The resource could not be loaded because
the App Transport Security policy requires the use of a secure connection."
NSErrorFailingURLStringKey=http://feeds.feedburner.com/LiteraturaRioDeJaneiro
```

Na tela: cabeçalho "Feedmine · Falha ao atualizar o…" e a faixa "⚠ Falha ao atualizar o feed". O catálogo
real contém feeds em HTTP simples; o build de produto não tem exceção de ATS (o harness cria uma
**para o próprio transporte**, `bench/run.sh:177-184`, o que não cobre o produto). Isso é independente
do tema desta rodada, mas é um defeito real de catálogo real e explica o aviso que o PO verá na
primeira reabertura.

## 5. Evidências

- Vídeos: `R3-primeira-abertura.mp4` (instalação limpa → primeiro card → 1 card), `R3-gestos-xcui.mp4`
  (swipes reais dos testes), `R3-arrasto-sintetico.mp4` (arrasto que **não** chega ao app).
- Imagens: `R3-reabertura-varios-cards.png` e as capturas J1–J10/R2.
- Logs/testes: `/tmp/r3-uitest.log` (2 testes, 0 falhas), trace do store `F4477FFD-…/trace.jsonl`.

## 6. O que ainda não está fechado

- Gesto real **na sessão de catálogo real** (o instrumento não entrega toque; os testes provam o
  mecanismo no transporte de teste).
- Estado "sem conteúdo elegível" e "falha comprovada" com o catálogo real (para os textos 3 e 4 do PO).
- Contagem de cards renderizados na reabertura por acessibilidade: a árvore AX ficou vazia nesse
  instante (só a captura visual contou os cards) — vale investigar como item de acessibilidade.
