# Diagnóstico UX — rodada 01 (investigação, sem alterar código)

Data: 2026-10-11. Autor: sessão OMP. Insumo para o Codex (team lead) definir escopo/critérios de aceite.
Método: app real no simulador (iPhone 17 Pro Max, iOS 26.5), build local Debug, navegação por
elementos reais (AX) e captura por `simctl`, mais leitura do banco do app (read-only) e do log de
composição. Nenhum arquivo do app foi modificado.

> ## ⚠️ Correção de 2026-10-11 (rodada 2)
>
> **A causa do item 1 (bloqueio da primeira abertura) registrada abaixo está ERRADA.** O build instalado no
> simulador embarca um **catálogo de benchmark**: as 2.305 fontes têm `request_url` apontando para
> `http://127.0.0.1:8757/s/<url>` (`catalog_metadata`: `bench_corpus`,
> `bench_corpus_real_catalog_source_count = 77443`), um proxy que só existe durante uma corrida de
> benchmark. Fora da corrida, **toda** aquisição falha em milissegundos, por isso nada é publicado — não é
> defeito do fluxo frio. O mesmo binário, com alvos de URL real (feeds BBC), publicou **21 cards em 0,92 s**.
>
> Também errada como conclusão: "nenhuma tentativa de rede falha aparece no log" — não há log por alvo, e
> uma falha contra `127.0.0.1` fechada custa ~0,2 ms, então a ausência de erro era compatível com
> "contatou e falhou" (que é o que acontece). Detalhes e prova em
> `docs/reviews/2026-10-11-cold-start-diagnosis-round2.md`.
>
> Itens abaixo que dependem do **conteúdo** do corpus de benchmark (títulos sintéticos, link `127.0.0.1`
> ao abrir card, contagens de idioma no Filtros, dicas "FeedMine sugere") precisam ser reconferidos com o
> catálogo real. Os itens de **chrome de UI** (rótulos, hierarquia, folhas, acessibilidade, copy de
> estados) permanecem válidos.

## Ambiente medido (fatos)

|Fato|Valor|
|---|---|
|Bundle instalado|`com.feedmine.development`, build 26|
|Catálogo empacotado|`catalog.sqlite` **2.305 fontes** (manifest rev 5, generatedAt 2026-10-11T21:04:07Z) — não o snapshot de 77.443|
|Conteúdo do feed avaliado|histórico publicado por uma corrida de bench/soak (namespace `A6CF6253…`), com links `127.0.0.1` e títulos sintéticos|
|Estado do app "limpo"|store raiz vazio: `reader_preferences.hasSeenOnboarding=false`, `source_keys=[]`|
|Lançamentos sem env|`xcrun simctl launch booted com.feedmine.development`|

`scripts/soak.py` explica a diferença de estado: ele define `SIMCTL_CHILD_FEEDMINE_SKIP_ONBOARDING=1`
e `SIMCTL_CHILD_FEEDMINE_RUNTIME_NAMESPACE=<uuid>` — por isso a corrida medida já entrava com feed.

## Jornadas percorridas

### J1 — Feed com histórico local
Evidência: `J1-feed-aberto.png`.
Observado: cards com fonte, manchete, linha de apoio, idade relativa ("2 days ago") e ícone de
bookmark; filete colorido por fonte; topo com seletor de contexto ("Feedmine ⌄") e quatro botões
**apenas de ícone** (Buscar, Salvos, Filtros, Mais). O contador de DEBUG
(`received=… completed=… backward=…`) é desenhado sobre a barra de status.
Passos: lançar com namespace → feed restaurado.

### J2 — Abrir um card (leitura)
Evidência: `J2-card-abre-browser-link-morto.png`, `J10-card-abre-safari.png`.
Observado: o toque no card abre um `SFSafariViewController` (barra com `127.0.0.1`) e, como o link do
corpus é local, aparece o erro cru do Safari ("Safari can't open the page because it couldn't connect
to the server"). Não há moldura do FeedMine (fonte, título, ações), nem repetir, nem "abrir no
navegador", nem leitor interno; a árvore de acessibilidade dessa tela fica **vazia** (nada é anunciado).
Limite honesto: não foi possível avaliar renderização de artigo real — os links deste corpus são locais.

### J3 — Busca
Observado: abre campo com placeholder `Adicionar um termo · use -termo para excluir` e filtra o feed
no lugar; o termo casa sem acento ("vacinacao" acha "vacinação") e aparece destacado na manchete.
A linha de contagem de resultados fica **atrás do teclado** durante a digitação.

### J4 — Salvos
Observado: o botão de bookmark abre a folha **"Caixas de salvos"** (Todos os salvos / Salvos, 0 /
Nova caixa). Os controles visíveis no topo da folha (Concluir, Reordenar) **não estão expostos** na
árvore de acessibilidade, e não há outro controle de fechar na folha.

### J5 — Filtros
Evidência: captura da folha na sessão.
Observado: "Limpar todos os filtros"; Feeds (Tudo ✓ / Último aberto / Países); Idioma com **linhas
duplicadas e indistinguíveis**: English 757, Portuguese 658, Portuguese 310, English 278, Spanish 90,
English 34, German 29, French 27, German 10… Os números provam que são conjuntos distintos, mas nada
na interface diz qual é qual (idioma×região). A rolagem programática da folha não respondeu.

### J6 — Mais
Observado: seis itens — Criar feed curado, Adicionar feed, Exportar, Coleções de fontes, Fontes,
Ajustes — sem descrição; três deles disputam o mesmo modelo mental (feed curado / coleções / fontes).

### J7 — Primeira abertura (onboarding)
Evidências: `J4-relaunch-mostra-onboarding.png`, `J5-onboarding-idiomas-lugares.png`.
Observado: tela 1 com wordmark, promessa, três selos e duas ações — primária **"Montar meu feed"**
(exige configurar) e secundária "Começar amplo". O headline está em inglês ("The open web, arranged by
you.") e o resto em pt-BR. Tela 2 "Escolha idiomas e lugares": chips de idioma **duplicados**
(English, Portuguese, Portuguese, English, Spanish, English, German, French, German, Spanish, Spanish,
German) e sempre em inglês; **English já vem selecionado** apesar do locale pt-BR; países em inglês,
lista curta sem sinal claro de rolagem; um `composer-preview-skeleton` deixa **dois retângulos cinza
vazios** no topo; ações Reiniciar / Começar amplo / Abrir meu feed.

### J8 — Primeira abertura sem conteúdo (artefato do catálogo de benchmark — ver correção no topo)
Evidências: `J6-primeira-abertura-25s.png`, `J7-primeira-abertura-55s.png`,
`J8-primeira-abertura-3min.png`, `J9-comecar-amplo-sem-conteudo.png`.
Reprodução: lançamento normal (sem env) → concluir o onboarding por **qualquer** dos dois caminhos →
a superfície de feed mostra o wordmark e a frase "Nenhuma apresentação local recebida" e **nunca**
produz conteúdo (observado por mais de 10 minutos).
Medições no mesmo período:

```
log (subsystem com.feedmine.development):
14:19:40.556 cold bootstrap started
14:19:40.618 cold bootstrap settled      (+62 ms, nada publicado)
14:20:01.557 cold bootstrap started      (+21 s)
14:20:01.608 cold bootstrap settled
… repete a cada ~21 s indefinidamente
```

```
store raiz: acquisition_targets 172 → 232 → 401 (todas state=enabled)
            origin_records 0 · selection_supply 0 · published_cards 0 · feed_editions 0
```

Explicação estabelecida na rodada 2 (não é defeito do fluxo frio): o build instalado embarca um catálogo de
benchmark cujos `request_url` apontam para `http://127.0.0.1:8757` (proxy morto fora da corrida). O
planejador contata até 2 alvos por oportunidade; todos falham em milissegundos; nenhuma origem é admitida.
Com alvos de URL real, o mesmo binário publicou 21 cards em 0,92 s. Ver
`docs/reviews/2026-10-11-cold-start-diagnosis-round2.md`.

### J9 — Retorno (reabrir com histórico)
Evidência: `J3-relaunch-restauracao.png` (contraponto: `J4-relaunch-mostra-onboarding.png`).
Observado: com namespace cujo store tem histórico, reabrir restaura cards imediatamente e os
contadores ficam `received=0 completed=0 backward=0` — ou seja, veio do local, não da rede.

## Observado × hipótese

- **Observado (rodada 1, corrigido na rodada 2):** onboarding concluído (duas variantes) não produz
  nenhuma origem, nenhum card e nenhuma edição; o cold bootstrap "assenta" em 40–60 ms e se reagenda a cada
  ~21 s; o caminho de restauração funciona; os alvos crescem entre lançamentos.
- **Causa (provada na rodada 2):** o build instalado carrega o catálogo de benchmark com URLs
  `http://127.0.0.1:8757` (proxy morto). A aquisição é planejada e executada, falha em milissegundos e
  retorna `.noPublicationAfterAcquisition` → `.idle`. Com URLs reais, 21 cards em 0,92 s.
- **Hipótese descartada:** "a fatia fria não encontra candidato elegível / nunca chega à aquisição".

## Cinco problemas mais relevantes

1. **Primeira abertura nunca produz conteúdo** — *na rodada 2 provou-se artefato do build* (catálogo de
   benchmark com URLs mortas), **não** um defeito do app; precisa ser reconferido com o catálogo real de
   77.443 fontes. O problema de UX que **permanece** mesmo assim: enquanto espera, a tela não mostra nada
   além do wordmark e de uma frase que descreve o motor, e uma tentativa falha é indistinguível de ociosidade.
2. **A espera não mostra trabalho algum.** Estados da superfície vão de "Nenhuma apresentação local
   recebida" a "Preparando apresentação local"; não há evidência real de fontes/histórias chegando,
   no motivo, nem no que fazer — contra o comportamento 1 do norte de produto.
3. **Ler o artigo sai do produto.** Card → Safari de sistema, sem contexto e sem recuperação quando o
   link falha.
4. **As dicas "FeedMine sugere" quebram o ritmo.** Uma dica depois de **cada** card, cada uma com
   altura de card (dois botões + explicação). O feed lido fica metade cards, metade dicas, e o efeito
   do "mais/menos deste grupo" não é visível.
5. **Superfícies não se explicam.** Barra só de ícones; "Salvos" abre gerenciador de caixas; idiomas
   duplicados sem rótulo em Filtros e no onboarding; três conceitos sobrepostos em "Mais"; idioma
   padrão English com aparelho em pt-BR e promessa em inglês no meio de tela em português.

## Recomendação de primeira jornada

**Primeira abertura até o primeiro card** (J7→J8), mantida — é o único caminho que sustenta a promessa de
descoberta. Com a correção da rodada 2, a ordem real é: (a) **fazer o baseline valer** — recompilar com o
catálogo real de 77.443 fontes, porque o build avaliado carregava o corpus de benchmark com URLs mortas;
(b) substituir a espera silenciosa por evidência real de trabalho (estados de UX); (c) só então atacar
leitura, dicas e rótulos.

## Não verificado

Artigo real (links do corpus são locais), cards com imagem (o corpus não tem), offline real,
Dynamic Type/Reduce Motion, corrida em aparelho físico, filtros Último aberto/Países, coleções,
feeds curados, exportação e Ajustes. O contador de DEBUG sobre a barra de status é artefato do build
de desenvolvimento, não do produto.

## Briefing do PO

Instância: ChatGPT (projeto **Feedmine**), thread "Assumir papel de PO" —
`chatgpt.com/g/g-p-6a584059c8f0819180f2f1d07b1ccbbe-feedmine`. A primeira resposta veio dentro de um
documento ("Writing") que ficou sem corpo na conversa; foi re-solicitada em texto simples e lida por
dois caminhos (transcrição do documento + resposta em texto).

1. **Usuário principal.** Pessoa curiosa (notícias, tecnologia, ciência, cultura, entretenimento) que
   quer descobrir conteúdo interessante sem depender de redes sociais nem conhecer RSS. Não é usuário
   técnico de leitores de feeds; está acostumada à facilidade de Instagram, Reddit e Threads, mas quer
   explorar a internet aberta com autonomia.
2. **Problema que resolve.** A internet aberta tem diversidade enorme, mas descobrir e acompanhar
   exige esforço (achar sites, acompanhar publicações, alternar entre plataformas). O FeedMine
   transforma milhares de fontes independentes em uma experiência unificada de descoberta contínua —
   a facilidade de um feed social com a diversidade da internet aberta, sem exigir configurar fontes
   nem entender RSS, aquisição, cache ou sincronização.
3. **Jornada prioritária.** Descoberta → Consumo → Exploração → Retorno: abrir e entender a proposta,
   escolher interesses sem complexidade, receber conteúdo relevante e variado, navegar continuamente
   sem paginação ou interrupções artificiais, alterar interesses/filtros e explorar novas fontes sem
   perder trabalho e contexto, salvar e retornar depois encontrando conteúdo e posição preservados
   (inclusive offline). **O feed é o centro; Busca, Salvos, Filtros e Mais devem fortalecê-lo, não
   competir com ele.**
4. **Resultado esperado desta rodada.** Identificar o que impede o app de parecer simples, agradável,
   coerente e pronto para pessoas reais, examinando a experiência executada no simulador (não só
   código/especificação). Prioridades: **P0** primeiro uso, estados de carregamento, qualidade visual
   dos cards, continuidade do scroll, comportamento das imagens, mudanças de filtros e preservação de
   contexto; **P1** clareza dos controles, hierarquia visual, busca, salvos, menus, feedback e
   consistência entre telas; **P2** tipografia, espaçamento, microinterações, acabamento. Entrega:
   evidências visuais, problemas com severidade, consequência para o usuário e propostas objetivas.
   Não quer lista genérica de sugestões estéticas nem reestruturação antecipada do código.

**Diretriz final do PO:** "FeedMine deve parecer uma janela viva para a internet, não uma ferramenta
técnica para administrar feeds. A complexidade pertence ao motor; a simplicidade pertence ao usuário."

Consequência para este diagnóstico: o bloqueador da primeira abertura (J8) cai exatamente no P0 do PO
(primeiro uso + estados de carregamento); e o item P0 "comportamento das imagens" **não pôde** ser
avaliado nesta corrida, porque o corpus disponível não tem imagens — ver "Não verificado".
