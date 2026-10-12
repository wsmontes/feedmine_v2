# Rodada 2 — causa do bloqueio da primeira abertura e proposta

Data: 2026-10-11. Autor: sessão OMP. Investigação apenas: nenhum código-fonte alterado, nenhum commit.
Corrige explicitamente a leitura de uma evidência do relatório da rodada 1 (ver "Correção").

## Resumo

A primeira abertura no simulador **não** falha por defeito do fluxo frio. O build instalado no simulador
embarca um **catálogo de benchmark**: as 2.305 fontes têm `request_url` apontando para um proxy local
(`http://127.0.0.1:8757/s/<url>`), que só existe durante uma corrida de benchmark. Fora da corrida, toda
aquisição falha instantaneamente, nenhuma origem é admitida e o feed nunca publica — exatamente o que foi
observado. O mesmo binário, com uma seleção de fontes cujas URLs são reais, publicou **21 cards em 0,92 s**.

## Ambiente (medido)

|Fato|Valor|
|---|---|
|Build instalado|`com.feedmine.development` build 26, Debug (14:04)|
|Catálogo DENTRO do bundle instalado|`source_count=2305`, `bench_corpus = feedmine-discovery-acceptance-benchmark`, `bench_corpus_transport_base_url = http://127.0.0.1:8757`, `bench_corpus_real_catalog_source_count = 77443`|
|URLs de aquisição do bundle|`http://127.0.0.1:8757/s/https%3A%2F%2F...` — **2305 de 2305**|
|Porta 8757|fechada (`lsof` vazio); `curl` na URL de uma fonte: `http=000 time=0.0002s`|
|Catálogo no REPOSITÓRIO|`FeedMineApp/FeedMineApp/Resources/catalog.sqlite`, 117.993.472 B, `source_count=77443`, sem `bench_corpus`, rev 5 (`scripts/bootstrap_catalog.py`)|

## Reprodução isolada (sem flags de benchmark)

Namespace novo (store vazio), lançamento simples, onboarding concluído pelos **dois** caminhos
("Montar meu feed" + idiomas/país e "Começar amplo"):

```
14:32:11.665 cold bootstrap started
14:32:11.679 cold bootstrap settled        (+14 ms)
14:32:32.555 cold bootstrap started        (+20,9 s)
… indefinidamente, ~21 s por ciclo
```

Store do namespace isolado, medido em 3 amostras a cada 22 s:

```
t=14:34:45  targets=181  origin_records=0  selection_supply=0  published_cards=0
t=14:35:07  targets=197  origin_records=0  selection_supply=0  published_cards=0
t=14:35:29  targets=208  origin_records=0  selection_supply=0  published_cards=0
```

Superfície: "Nenhuma apresentação local recebida"; `acquisition_targets.state` sempre `enabled`,
`checkpoint_revision = 0` em todas (nunca houve fetch bem-sucedido).

## Experimento decisivo — mesmo binário, alvos com URL real

Namespace novo + `SIMCTL_CHILD_FEEDMINE_USE_DEVELOPMENT_FEEDS=1` (seleção não vazia:
`source_keys = ["bbc-world","bbc-science"]`, URLs `https://feeds.bbci.co.uk/...`):

```
14:37:58.800 cold bootstrap started
14:37:59.723 installed cards=1 edition=3087231F-… order=1     (+0,92 s)
14:37:59.833 cold bootstrap settled
```

Store: `origin_records 60 · origin_revisions 60 · published_cards 21 · feed_editions 1 ·
selection_supply 60 · source_memberships 60`. Evidência visual:
`docs/evidence/2026-10-11-ux-diagnosis/R2-devfeeds-21cards-1s.png`.

**Conclusão:** aquisição → candidatos → publicação → apresentação funcionam com URLs alcançáveis. O que
muda entre "funciona" e "nunca publica" é a **alcançabilidade do `request_url` do catálogo**, não o
fluxo frio.

## Ponto exato onde o fluxo para (com a leitura corrigida)

O caminho percorrido é:

1. `FeedAssociation.launch()` → `cold.run(...)` (`FeedMineApp/FeedMineApp/AppComposition.swift:1944-1952`).
2. `ColdFeedBootstrap.run` examina o catálogo (`advanceDiscovery`, `examinedCapacity: 32`) e registra
   alvos — é isso que faz `acquisition_targets` crescer a cada ciclo.
3. Fatia local sobre `selection_supply` (vazio) → sem publicação.
4. `AcquisitionPlanner.plan` **planeja** trabalho: `resources.targetWorkCapacity = 2`
   (`AppComposition.swift:1577-1590`), então cada oportunidade contata no máximo 2 alvos.
5. `coordinator.executeConcurrently` tenta os 2 alvos: são URLs `127.0.0.1:8757` **mortas**, falham em
   milissegundos, `selectableSupplyChanged == false`.
6. `ColdFeedBootstrap.run` → `guard changed else { return .noPublicationAfterAcquisition(...) }`
   (`Sources/FeedMineComposition/ColdFeedBootstrap.swift:232`).
7. `FeedPresentationHandoff.receive(coldOutcome:)` mapeia `.noPublicationAfterAcquisition` → `.idle`
   (`Sources/FeedMineComposition/FeedPresentationHandoff.swift:20-21`), que a UI mostra como
   "Nenhuma apresentação local recebida" (`Sources/FeedMineUI/FeedLoadingView.swift:25`).
8. `launch()` reprograma: `nextCoolingExpiry() ?? uptime + 20 s` → ciclo de ~21 s.

Ou seja: **o fluxo frio funciona; ele é alimentado por um catálogo cujos alvos não respondem.** A
`selection_supply` permanece vazia porque nenhuma observação é admitida (é um read model sobre
`origin_records`/`origin_revisions`), e não porque a seleção esteja vazia — o mesmo `source_keys = []`
publicou 21 cards quando as URLs eram reais.

## Correção de uma evidência da rodada 1

No relatório da rodada 1 registrei "nenhuma tentativa de rede falha aparece no log" como indício de que a
aquisição nunca começava. **Isso estava errado como conclusão.** Não há log por alvo no caminho de
aquisição, e uma falha contra `127.0.0.1` fechada custa ~0,2 ms — logo a ausência de linhas de erro era
compatível com "contatou e falhou", que é o que de fato acontece. A medição correta é: o planejador
contata até 2 alvos por oportunidade, todos apontando para o proxy morto.

Consequência para as demais observações da rodada 1: as que dependem do **conteúdo** do corpus (títulos
sintéticos, link `127.0.0.1` ao abrir card, contagens de idioma do Filtros, dicas "FeedMine sugere") foram
observadas sobre o catálogo de benchmark e precisam ser reconferidas com o catálogo real. As que são de
**chrome de UI** (rótulos, hierarquia, folhas, acessibilidade, copy de estados) valem independentemente do
catálogo.

## Proposta técnica (sem código nesta rodada)

1. **O build avaliado precisa carregar o catálogo real.** O repositório já tem o artefato correto
   (`Resources/catalog.sqlite`, 77.443 fontes, 117 MB, verificado contra `catalog.manifest.json`). O build
   instalado no simulador não tem: foi montado com o catálogo de benchmark. Ação: recompilar/reinstalar o
   app e repetir as duas jornadas; confirmar no bundle
   `catalog_metadata.bench_corpus` ausente e `source_count = 77443`.
2. **Impedir que o catálogo de benchmark chegue a um build de avaliação de produto.** Medido na rodada 3:
   o harness **não** escreve no repositório — `bench/run.sh:121-164` injeta o catálogo do corpus e o
   descritor no app **compilado** (`$OUT/derived/Build/Products/…/FeedMine.app`) e o runner instala esse
   app instrumentado no simulador compartilhado sob o bundle id do produto
   (`bench/run.sh:16`, `scripts/soak.py:43`); nada restaura o build de produto depois. Sugestão: rodar o
   benchmark com identidade (ou simulador) própria — `com.feedmine.development.benchmark` — e manter uma
   verificação que **recuse** `bench_corpus` num build de avaliação de produto (ver rodada 3, §2).
3. **Falha de transporte precisa ser visível.** Hoje um alvo que falha não deixa rastro no log de
   composição; um `request_url` inalcançável é indistinguível de "não havia nada a fazer". Mínimo: registrar
   por alvo o resultado (sucesso/falha de transporte) no log de composição — é a evidência que faltou para
   fechar esta investigação sem medir o banco por fora.
4. **Revisar `targetWorkCapacity: 2` para o primeiro preenchimento.** Com 2 alvos por oportunidade e
   backoff de ~20 s, mesmo com URLs vivas o primeiro card depende de qual par foi sorteado. O experimento
   com feeds reais mostrou 0,92 s porque havia exatamente 2 alvos; com um catálogo de 77 mil fontes isso
   não se repete.

## Proposta de estados de UX para o primeiro uso (item 3 do pedido)

O motor **já produz** a evidência (`ColdFeedEvidence`: `.contacting(targets)`, `.settled(target,
stop:supplyChanged:)`, `.preparingMedia`, `.published(snapshot)`) e a UI a ignora: `FeedLoadingView` recebe
apenas `FeedPresentationState.Work` e imprime uma frase fixa por caso.

1. **Preparação inicial com mensagem compreensível.** Substituir "Nenhuma apresentação local recebida" por
   linguagem de produto ("Buscando histórias para você…") e, quando houver alvos em contato, dizer o que
   está acontecendo de real ("Consultando *BBC World*…") usando `.contacting`.
2. **Progresso a partir de fatos do motor.** Um indicador por fonte que respondeu (`.settled(_, supplyChanged:)`)
   e a contagem real de histórias preparadas — nunca um percentual inventado. O norte de produto exige
   "evidências reais de fontes e histórias chegando".
3. **Primeiro conteúdo assim que estiver pronto.** Manter a superfície informativa até o primeiro card e,
   no instante `.published`, trocar sem salto de layout (o motor já entrega o 1º card em ~0,9 s com alvos
   vivos).
4. **Fim honesto do caminho.** Se a caminhada terminar sem nada (`.unavailable`), dizê-lo com o motivo
   compreensível e uma ação ("Tentar de novo", "Escolher fontes"), em vez de ficar em "preparando" para
   sempre. Hoje `.localWorkRemaining` e `.noPublicationAfterAcquisition` caem em `.idle`: "ocioso" e
   "tentei e nada voltou" apresentam-se iguais ao usuário — e é isso que faz a tela parecer travada.
5. **Nunca parecer travado.** Enquanto houver trabalho agendado (`retryTask`, `coldRetryAt`), a superfície
   deve indicar que ainda está tentando; o silêncio de 21 s entre tentativas é indistinguível de app morto.

## Evidências

- Capturas: `docs/evidence/2026-10-11-ux-diagnosis/` (rodada 1 + `R2-isolado-onboarding.png`,
  `R2-isolado-sem-conteudo.png`, `R2-devfeeds-21cards-1s.png`).
- Log do app: `xcrun simctl spawn booted log show --last 5m --info --debug --predicate 'subsystem == "com.feedmine.development"'`.
- Store isolado: `…/Application Support/FeedMine/<namespace>/runtime.sqlite` (read-only, copiado).
- Catálogo: `FeedMineApp/FeedMineApp/Resources/{catalog.sqlite,catalog.manifest.json}` e o do bundle
  instalado (metadata `bench_corpus`).

## Verificação com o catálogo real (executada nesta rodada)

Ação: recompilado o app a partir do repositório (que já contém o catálogo real) e reinstalado no simulador.
Bundle instalado agora: `source_count = 77443`, **sem** `bench_corpus`.

Jornada "Montar meu feed" (idiomas + Brasil), namespace novo, loja vazia, seleção de fontes **vazia**
(`source_keys = []` — a mesma configuração que "nunca publicava" com o catálogo de benchmark):

```
14:41:39.575 cold bootstrap started      ("Abrir meu feed")
14:41:42.700 installed cards=1 …         (primeiro card 3,1 s depois)
14:41:42.860 cold bootstrap settled
```

Loja: `origin_records 419 · selection_supply 419 · source_memberships 419 · published_cards 22 ·
feed_editions 1 · acquisition_targets 121`.

Superfície durante a preparação (texto real, com uma fonte já respondendo):

> "Preparando seu feed. 1 de 2 fontes já trouxeram novidades. Última manchete: Lula muda a estratégia;
> Flávio já fala em mudar a Constituição"

Evidências: `R2-real-preparando-com-evidencia.png` (espera) e `R2-real-feed-apos-3s.png` (primeiro card,
conteúdo real: imagem, selo "Podcast", fonte, manchete, linha de apoio, idade).

### Correção da rodada 1, item 2 ("a espera não mostra trabalho algum")

Também era artefato do build: com alvos inalcançáveis nenhuma fonte responde e a superfície fica em `.idle`
("Nenhuma apresentação local recebida"). Com catálogo real ela mostra a contagem de fontes que responderam e
a última manchete. O que **permanece** como problema: `.idle` e `.noPublicationAfterAcquisition` continuam
indistinguíveis de app travado quando algo falha, e a tela não oferece ação quando a caminhada termina vazia.

### Achados novos (com conteúdo real)

- Após a primeira publicação a janela apresenta **1 card** (`installed cards=1`) com 22 publicados na loja, e
  o resto da tela fica vazio. A admissão de conteúdo à frente é deliberada (`explicitTailApproach`), mas para
  o leitor não há indicação de que rolar traz mais. Tentei rolar por `scroll` e por gesto sintético: **a
  árvore não mudou** — continuidade do scroll **não verificada** nesta rodada (segue como P0 para a próxima).
- O card de podcast é bom (imagem real, selo de tipo, hierarquia legível) mas alto: ~1 card por tela; e a
  idade aparece em inglês — "2 days ago" — numa interface em português.

## Em aberto (próxima rodada)

- Continuidade do scroll e admissão da cauda com conteúdo real (sem gesto sintético; usar o caminho nativo).
- Estados `.idle`/`.noPublicationAfterAcquisition`: distinguir "falhou e nada voltou" de "ocioso".
- Primeira abertura pelos dois caminhos de onboarding com catálogo real (o caminho "Começar amplo" não foi
  repetido após a reinstalação).
- Reconferir os itens de chrome que dependiam de conteúdo: card→artigo, dicas "FeedMine sugere", Filtros.
