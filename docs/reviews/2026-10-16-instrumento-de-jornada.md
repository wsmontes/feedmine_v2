# O instrumento de jornada — medições binárias lidas do registro do app (`instruments/journey/journey.py`)

**Data:** 2026-10-16 · **Autor:** agente `ObviousInstrument` (tarefa delegada pelo agente principal) ·
**Ambiente:** macOS 25.3.0 (arm64), Python 3.12.13 · **sem build, sem simulador, sem rede** nesta sessão.

**Recorte aprovado (2026-10-16, veredito do arquiteto):** o instrumento **saiu de `bench/`** — que é a referência
congelada — para `instruments/journey/`, com hash próprio, e o código de saída passou a ser **de quatro vias**
(0/1/2/3). O veredito do arquiteto aprovou a implementação como diagnóstico e pediu exatamente esses dois ajustes
antes da integração à `main`; a §11 registra o que mudou, com os quatro caminhos medidos por execução. A baseline
B01–B06 permanece intocada, byte a byte.

**Versão do recorte.** O artefato é `instruments/journey/journey.py`, sha256
`4e4eff074fec7c3d9728aed17693d3c8b9feafb80caec52f99d070765d2bed8e` (92.805 B) — o mesmo hash de
`instruments/journey/journey.sha256`. As seções §0.1 a §10 foram medidas na versão anterior (sha256
`92869365…`, 63.108 B, ainda em `bench/journey.py`, num `/tmp` de sessão que não existe mais); elas continuam
descrevendo o mesmo modelo de cláusula e os mesmos contratos, e a §11 lista **o que o recorte mudou** e o que ele
**não** mudou.

**Versão corrigida.** Esta é a segunda versão, depois de uma revisão independente do agente
`ReviewJourneyInstrument`. A §7 responde item por item, com a evidência medida do que mudou. O artefato testado é
`/tmp/fm-obvious/bench/journey.py`, sha256
`92869365178130c2eb25b4526bb3508332cc21c728e050a1a9d7d87ae2c0fb25` (63.108 B), o mesmo hash de
`bench/journey.sha256`. Nada de `bench/` foi editado; nenhum commit foi feito (decisão do agente principal depois
de o disco esgotar e de o agente principal pedir o diff para revisão).

## 0. Método, insumos, e os três contratos de evidência

| Item | Valor |
|---|---|
| Instrumento | `instruments/journey/journey.py` (no recorte; era `bench/journey.py`), sha256 `4e4eff07…`, 92.805 B, arquivo novo, hash próprio |
| Onde mora | `instruments/journey/`, **fora** de `bench/`: `bench/` é a régua congelada (B01–B06) e uma ferramenta nova e evolutiva ali dentro pareceria ter autoridade sobre ela |
| Medições implementadas | M1, M2, M3, M4, M5, M7, M10 |
| Sem evidência hoje | M1/M6 (superfície), M8, M9, M11, M12, M7-pouso (§6) |
| Controles positivos | dez injeções (§5) + `--selftest` com os quatro códigos de saída e as dez injeções (§11.4) |
| Código de saída | `0` tudo aplicável medido e PASS · `1` alguma cláusula FAIL · `2` erro de entrada/execução · `3` sem FAIL, com cláusula aplicável não medida (§11.2) |
| Leitura do banco | cópia de `runtime.sqlite` **com** `-wal` e `-shm` para diretório temporário, aberta em `mode=ro` |

Contratos que decidem o veredito, e que a revisão mostrou faltarem na primeira versão:

1. **Sem sujeito não há veredito**: cláusula sem o que medir é `NOT_RUN`, com a razão escrita, nunca `PASS`
   (`bench/oracle.py:357-378`).
2. **Ausência sobre evidência incompleta não é prova**: se o próprio traço anuncia eventos perdidos
   (`trace_truncated`) ou há linha ilegível, quem contou **zero** violações não conclui nada — `NOT_RUN`.
   Violação **observada** continua `FAIL`: o que se perdeu foi a chance de ver mais, não a legitimidade do que
   se viu.
3. **Fato obrigatório não observado contamina a afirmação composta**: qualquer sub-fato não medido torna o
   agregado `NOT_RUN` (`[PASS, NOT_RUN]` → `NOT_RUN`), como em `bench/oracle.py:624-631`.

Onde o traço não tem a informação, a ferramenta diz `NOT_RUN` e não deriva o estado de outro campo parecido. O
caso concreto: `preparation=done` na linha de jornada só significa que o relé não recebeu nada
(`AppComposition.swift:2363-2366`) — **não** é fim de feed declarado (`work == .endOfContent`), e a primeira
versão desta ferramenta tratava os dois como a mesma coisa.

### 0.1 Os insumos, com o que o próprio traço diz ter perdido

| Insumo | traço | linhas | janela | perda declarada | completo? | bytes que decidiram | cartas / edições |
|---|---|---|---|---|---|---|---|
| `bench/run/20261014T182436Z` (B03) | `5d2ee817…` | 40332 | 2026-10-14T18:26:34Z → 2026-10-14T18:57:23Z | **2030 recusados pelo teto + 0 perdidos na escrita** | **não** | `runtime.sqlite` e2f5c9d1… (2498560 B), `runtime.sqlite-wal` aa4ef2bc… (1050632 B), `runtime.sqlite-shm` fcafca8a… (32768 B) | 867 / 1 |
| `bench/run/20261014T173601Z` (B05) | `ba1114ba…` | 658 | 2026-10-14T17:37:42Z → 2026-10-14T17:38:40Z | nenhuma | sim | `runtime.sqlite` e96054f3… (1466368 B), `runtime.sqlite-wal` 178e3224… (601552 B), `runtime.sqlite-shm` d6e74e47… (32768 B) | 63 / 1 |
| `bench/run/20261014T214403Z` (B04) | `59c71ea6…` | 1199 | 2026-10-14T21:45:56Z → 2026-10-14T21:48:18Z | nenhuma | sim | `runtime.sqlite` 8fafe9ee… (1650688 B), `runtime.sqlite-wal` d1660029… (1582112 B), `runtime.sqlite-shm` 22ff402a… (32768 B) | 75 / 1 |
| `bench/run/20261014T200700Z` (B03) | `6b6aa168…` | 39961 | 2026-10-14T20:10:39Z → 2026-10-14T20:40:39Z | **137 recusados pelo teto + 64 perdidos na escrita** | **não** | `runtime.sqlite` 7fe6a945… (2498560 B), `runtime.sqlite-wal` 27aaddb2… (3584432 B), `runtime.sqlite-shm` 0025a3dc… (32768 B) | 873 / 1 |
| `/tmp/fm-journey-20261016T075109Z` (aparelho, build 47 Debug) | `861d2f97…` | 384 | 2026-10-16T07:51:12Z → 2026-10-16T07:55:32Z | nenhuma | sim | `runtime.sqlite` 3e899fd6… (425984 B), `runtime.sqlite-wal` e3b0c442… (0 B), `runtime.sqlite-shm` fd4c9fda… (32768 B) | 42 / 1 | · console `5ee23079…` (598 linhas)

A proveniência impressa lista **sha256 de cada byte que decidiu o resultado** — `runtime.sqlite`, `-wal` e
`-shm` — porque o WAL carrega a posição durável que o banco principal não tem: medido, ler com `immutable=1`
mostra `context_checkpoints` 43 s mais velho que a verdade (`bench/run/20261014T214403Z`).

## 1. O que o instrumento mede

| # | Pergunta do leitor | Campo que responde | Veredito binário | Números crus ao lado |
|---|---|---|---|---|
| **M1** | Abri e o conteúdo apareceu, sem me dizer antes que o feed estava vazio? | `window.cards` por geração (geração = `edition`+`sequence` do último `admitted`) | `empty_then_content == 0` | janelas, gerações, vazias por categoria, `install_rejects` |
| **M2** | Toda carta tem fonte e destino? | `published_cards.source_id`, `.primary_action_reference` | `cards_sem_fonte == 0`, `cards_sem_destino == 0` | cartas, edições, fontes, layouts |
| **M3** | Rolei e cheguei a cartas de verdade? | `advance.activity/.anchor` + janela instalada + ordem **da edição** | `âncora fora da janela == 0`, `forward atrás da posição observada anterior == 0` | avanços por atividade, âncoras distintas, não resolvidas, pares comparáveis |
| **M4** | Nada acima de mim mudou? | `admitted.cards/head/tail/anchor` | contém a âncora, `encolhimentos == 0`, `cauda recuou == 0`, `buracos == 0` | instalações, não resolvidas, `cabeça_avançou` |
| **M5** | As imagens apareceram? | `media_key` vs. `Media/sha256/<digest>` **da janela instalada** | `cartas da janela com mídia declarada sem asset == 0`; **a pergunta visual é `NOT_RUN`** | censo de blobs, digests, arquivos |
| **M7** | Reabri onde eu estava? | `position_checkpoint` + `context_checkpoints` **do contexto medido** + `session_checkpoint` | âncora durável == última relatada; linha de sessão concorda | índices, instantes, `regressão_da_âncora` |
| **M10** | Rolar rápido: o que o app mediu? | `frames.*` do traço e `feedmine frames=…` | **sem limiar**: só a guarda `série medida` | quadros, late/bad/severe, razão, pior intervalo |

## 2. Saída bruta — `bench/run/20261014T182436Z` (B03, traço **incompleto**)

O que importa aqui é o que **mudou** em relação à primeira versão: sobre um traço que anuncia 2.030 eventos
recusados, M1/M3/M4/M7 deixam de afirmar `PASS` e passam a `NOT_RUN`. M2 e M10 seguem medíveis (M2 vem do banco,
e M10 afirma presença, que a perda não fabrica).

```
================================================================================================
insumo: /Users/wagnermontes/Documents/GitHub/feedmine_v2/bench/run/20261014T182436Z (corrida do bench)
================================================================================================
proveniência:
  traço: /Users/wagnermontes/Documents/GitHub/feedmine_v2/bench/run/20261014T182436Z/container/Library/Application Support/FeedMine/79B3C037-2300-49F1-9210-10FAE603ECBD/trace.jsonl
    sha256=5d2ee8173085005fa9b3f2264edcc7315855878e3e7278e92e5181ab14ab3468 linhas=40332 ilegíveis=0 janela=2026-10-14T18:26:34Z → 2026-10-14T18:57:23Z completo=False
    perda declarada pelo traço: {'anúncios': 332, 'teto': 40000, 'escrito': 40000, 'perdidos_pelo_teto': 2030, 'perdidos_pela_escrita': 0, 'perdidos_pela_codificação': 0}
  banco: /Users/wagnermontes/Documents/GitHub/feedmine_v2/bench/run/20261014T182436Z/container/Library/Application Support/FeedMine/79B3C037-2300-49F1-9210-10FAE603ECBD/runtime.sqlite
    runtime.sqlite: sha256=e2f5c9d142afcb31451dd539c2b2c5589fd126e77ffb8bc56e171104d5291858 bytes=2498560
    runtime.sqlite-wal: sha256=aa4ef2bc4d4ba8021d9e81b9ac347641eea2429bd6613ed79d26d3408b3a1f32 bytes=1050632
    runtime.sqlite-shm: sha256=fcafca8a6cef33cbe34c71c99d4bb5edbc9a8c86e1d9f1b999e950b3a599f131 bytes=32768
  mídia: ausente
  cartas na ordem do leitor: 867   edições: 1

[M1] A abertura entrega conteúdo na mesma geração
  pergunta do leitor: Abri o app e o conteúdo apareceu — sem o app me dizer antes que o feed estava vazio?
  fato lido: `window.cards` por geração, com o `window` atribuído ao último `admitted` anterior (AppComposition.swift:1356-1360, :2346-2350)
    [NOT_RUN] empty_then_content == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    janelas_gravadas: 3746
    gerações_com_janela: 2
    vazias_atribuídas_a_uma_geração: 1
    vazias_antes_do_primeiro_install: 2
    vazias_no_fim_da_geração: 1
    linhas_de_jornada_no_console: 0
    cartas_na_linha_de_jornada: []
    install_rejects_máximo: None
  nota: O vazio **declarado** (a superfície dizendo que acabou) não é medido aqui: o traço não grava o estado da superfície e `preparation=done` não é isso — ver a lista de NOT_RUN.
  veredito: NOT_RUN

[M2] A primeira tela tem história
  pergunta do leitor: Toda carta que eu vi pertence a uma fonte que existe e tem para onde me levar?
  fato lido: `published_cards.source_id` e `.primary_action_reference` (a cláusula parcial do oráculo é bench/oracle.py:285-287)
    [PASS] cards_sem_fonte == 0 — esperado: 0, observado: 0
    [PASS] cards_sem_destino == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    cartas: 867
    edições: 1
    fontes_distintas: 115
    layouts: ['textOnly']
  nota: Lida do banco, não do traço: a perda de eventos do traço não contamina esta medição.
  veredito: PASS

[M3] Rolar atinge carta que existe e para frente é para frente
  pergunta do leitor: Rolei — e cheguei a cartas de verdade, sem o app me dizer que avancei para um lugar onde eu já estava?
  fato lido: `advance.activity`/`.anchor` (AppComposition.swift:2577-2579) cruzados com a janela instalada (`admitted.head`/`tail`) e com a ordem do leitor dentro da edição (`feed_segments.edition_id`, `feed_segments.ordinal`, `published_cards.ordinal`)
    [NOT_RUN] âncora fora da janela instalada == 0 — esperado: 0, observado: 0
    [NOT_RUN] avanço forward atrás da posição observada anterior == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    avanços: 5407
    por_atividade: backward=2039, forward=1093, stationary=1259, explicitTailApproach=1016
    avanços_com_posição_observada_anterior: 5405
    âncoras_distintas: 865
    âncoras_não_resolvidas_na_edição: 0
    avanços_para_trás_que_pousam_à_frente: 0
    gerações: 2
  nota: `avanços_para_trás_que_pousam_à_frente` = 1 em 5.390 avanços (`bench/run/20261014T200700Z`) e 0 nas outras corridas: número cru, não cláusula — o gesto ainda não foi julgado.
  veredito: NOT_RUN

[M4] Rolar com trabalho de fundo não move o que está acima da âncora
  pergunta do leitor: Rolei e nada acima de mim mudou — o app não retirou, não encolheu e não remendou o feed sob a minha leitura?
  fato lido: `admitted.cards`/`head`/`tail`/`anchor` na ordem do leitor da edição (AppComposition.swift:2346-2350; o instrumento de B04 mede o mesmo registro em bench/oracle.py:390-460)
    [NOT_RUN] janela instalada contém a âncora == 0 — esperado: 0, observado: 0
    [NOT_RUN] encolhimentos == 0 — esperado: 0, observado: 0
    [NOT_RUN] cauda recuou == 0 — esperado: 0, observado: 0
    [NOT_RUN] buracos na janela == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    instalações: 11669
    instalações_não_resolvidas: 0
    cabeça_avançou: 0
    gerações: 2
  nota: `cabeça_avançou` é número cru: numa corrida que rola, a cabeça seguir o leitor é a poda declarada (`backwardWindowCards = 8`). A cláusula congelada `head == first` (bench/oracle.py:449) só é aplicável onde o leitor não anda — proposta de revisão no relatório, não executada.
  veredito: NOT_RUN

[M5] As imagens aparecem (o que o asset local prova, e o que não prova)
  pergunta do leitor: As imagens apareceram nos cartões — sem imagem quebrada?
  fato lido: `published_cards.media_key` vs. `Media/sha256/<digest>` para as cartas da janela instalada (AssetStore.swift:37-45,78-79); `render_layout` em PresentationCard.swift:11-15
    [NOT_RUN] cartas da janela com mídia declarada e sem asset local == 0 — esperado: 0, observado: 0
    [NOT_RUN] a imagem foi desenhada (pixel decodificado) — precisa de tela, não de arquivo — esperado: igualdade com a tela do cartão, observado: sem evidência
  números crus (informam, não decidem):
    cartas: 867
    edições: 1
    cartas_na_última_janela: 867
    com_mídia_declarada: 0
    digests_distintos: 0
    arquivos_em_Media/sha256: 0
    declaradas_sem_asset_em_toda_a_publicação: 0
    layouts: ['textOnly']
  nota: O censo de toda a publicação (`declaradas_sem_asset_em_toda_a_publicação`) é número cru: a limpeza de mídia evicta por orçamento por desenho (`Sources/FeedMineMedia/MediaHousekeeping.swift:6-7`), então ausência fora da janela não é defeito. A cláusula só olha a janela instalada.
  nota: Sem `Media/sha256/` no contêiner puxado, nada disto é observável naquele insumo (as corridas do bench não materializam mídia e publicam `textOnly` em todas as cartas).
  nota: O console do aparelho já publica `hero`/`thumb`/`media_resident` por segundo (AppComposition.swift:2340-2356); transformá-los em cláusula exige decidir o que `media_resident < thumb` significa no produtor — não decidido aqui.
  veredito: NOT_RUN

[M7] A âncora que eu reabro é a âncora que o app gravou
  pergunta do leitor: Fechei e reabri — o app me devolveu exatamente onde eu estava?
  fato lido: último `position_checkpoint.anchor` do traço (AppComposition.swift:2689-2690) vs. `context_checkpoints.card_id` (a linha do contexto medido) e `session_checkpoint.card_id`
    [NOT_RUN] âncora durável do contexto medido == última âncora relatada — esperado: igualdade, observado: não comparável
    [PASS] a linha de sessão concorda com a do contexto medido — esperado: 468ef7e8-c618-42f0-b7d6-af8babe6519a, observado: 468ef7e8-c618-42f0-b7d6-af8babe6519a
  números crus (informam, não decidem):
    edição_medida: 30c7fa42-7245-4280-aceb-98784430772c
    checkpoints_relatados: 353
    âncora_relatada: 468ef7e8-c618-42f0-b7d6-af8babe6519a
    âncora_relatada_índice: 863
    âncora_durável: 468ef7e8-c618-42f0-b7d6-af8babe6519a
    âncora_durável_índice: 863
    linhas_de_contexto_do_medido: 1
    âncora_durável_em: 2026-10-14T18:57:07Z
    último_evento_do_traço_em: 2026-10-14T18:57:23Z
    traço_completo: False
    regressão_da_âncora: False
  nota: O **pouso** da reabertura não é medido: o traço cobre uma sessão e a instalação que restaura a âncora é de outra. `admitted` grava a âncora instalada (AppComposition.swift:2346-2350) mas não grava o tipo de admissão — `.restore` existe em `Sources/FeedMineRuntime/FeedPresentationAdmission.swift:72` e é usado em AppComposition.swift:2709. Sem esse campo, o instrumento não sabe qual instalação é a reabertura e não afirma nada sobre o pouso.
  veredito: NOT_RUN

[M10] Rolar rápido: a série de quadros, relatada
  pergunta do leitor: Rolei rápido — o que o app mediu de cada segundo, quadro a quadro?
  fato lido: `frames.frames/late/bad/severe/worst_ms/budget_ms` do traço (FeedFrameMeter.swift) e as linhas `feedmine frames=…` do console
    [PASS] série medida (segundos > 0) — esperado: > 0, observado: 1916
  números crus (informam, não decidem):
    traço: segundos=1916, quadros=104742, late=3065, bad=4621, severe=665, fora_do_orçamento=8351, razão_fora_do_orçamento=0.07973, pior_intervalo_ms=139.2, segundos_com_severe=607
    console: segundos=0, quadros=0, late=0, bad=0, severe=0, fora_do_orçamento=0, razão_fora_do_orçamento=None, pior_intervalo_ms=None, segundos_com_severe=0
    traço_completo: False
  nota: Sem limiar por desenho: a razão fora do orçamento é impressa e não decide. `--series` imprime a série inteira, uma linha por segundo.
  veredito: PASS

sem evidência hoje (NOT_RUN por contrato, não por falha):
[M1/M6 (superfície)] O vazio e o fim **declarados** pela superfície
  veredito: NOT_RUN
  falta: Nenhum evento diz que a superfície declarou o feed vazio ou o fim de feed. `preparation=done` na linha de jornada **não** é isso: significa que o relé não recebeu nada (`FeedMineApp/FeedMineApp/AppComposition.swift:2363-2366`), e depois dele o host ainda agenda nova tentativa (`:2507-2535`). Sem essa evidência, a cláusula do vazio terminal fica não medida.
  onde: `Sources/FeedMineUI/FeedPresentationState.swift:45` (o caso `endOfContent`), `Sources/FeedMineUI/FeedScreen.swift:200` (onde é desenhado), `FeedMineApp/FeedMineApp/AppComposition.swift:2431-2433` (onde é concluído) e `:2399-2400` (onde o app descobre que o fim mostrado era falso) — nenhum grava.
[M8] Sem rede: história local e a carta salva abre
  veredito: NOT_RUN
  falta: O app não grava que o transporte estava bloqueado (`FEEDMINE_BLOCK_RSS_NETWORK` é lido e não vira evento) nem que a carta salva abriu (o banco diz que foi salva).
  onde: `FeedMineApp/FeedMineApp/AppComposition.swift:174-177`.
[M9] Primeiro uso sem assinatura
  veredito: NOT_RUN
  falta: Não implementada de propósito: exige o conjunto congelado `STARTER_KEYS`, que é régua congelada — duplicá-lo aqui criaria duas fontes para o mesmo fato. A cláusula já existe como B01.
  onde: `bench/oracle.py:35-39,195-198`.
[M11] App aberto 30 min: fontes novas no fim das janelas
  veredito: NOT_RUN
  falta: O traço não tem o carimbo de fim de janela nem o conjunto de fontes por janela.
  onde: `bench/expand.py:26` (o instrumento congelado que já mede isso).
[M12] p50/p95 de lançamento → primeira carta
  veredito: NOT_RUN
  falta: O instante do lançamento não é gravado: o traço começa no primeiro `window`/`frames` e a linha de jornada conta `t=` do primeiro quadro desenhado. Um percentil exige ≥30 execuções.
  onde: Um `record("launch", …)` em `FeedMineApp/FeedMineApp/AppComposition.swift:71-72`/`:258` ou em `FeedMineApp/FeedMineApp/FeedMineApp.swift:23`.
[M7 (pouso)] O pouso da reabertura: a carta que o app instala no topo depois de relançar
  veredito: NOT_RUN
  falta: O traço cobre uma sessão e não diz qual instalação é a restauração. `admitted` grava a âncora instalada, mas não o tipo de admissão.
  onde: `FeedMineApp/FeedMineApp/AppComposition.swift:2346-2350` (gravar o tipo) — `.restore` em `Sources/FeedMineRuntime/FeedPresentationAdmission.swift:72`, usado em `AppComposition.swift:2709`.

veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=NOT_RUN, M2=PASS, M3=NOT_RUN, M4=NOT_RUN, M5=NOT_RUN, M7=NOT_RUN, M10=PASS)
```

## 3. Saída bruta — `/tmp/fm-journey-20261016T075109Z` (jornada de aparelho: iPhone 14 Plus, build 47 Debug)

```
================================================================================================
insumo: /tmp/fm-journey-20261016T075109Z (jornada de aparelho)
================================================================================================
proveniência:
  traço: /tmp/fm-journey-20261016T075109Z/container/Library/Application Support/FeedMine/394FA0C4-89E8-47BF-8874-FE30EDAB9937/trace.jsonl
    sha256=861d2f97f52b763828b7101a5097899f6866884898848d7cae301244ae3c2091 linhas=384 ilegíveis=0 janela=2026-10-16T07:51:12Z → 2026-10-16T07:55:32Z completo=True
  banco: /tmp/fm-journey-20261016T075109Z/container/Library/Application Support/FeedMine/394FA0C4-89E8-47BF-8874-FE30EDAB9937/runtime.sqlite
    runtime.sqlite: sha256=3e899fd624b5ef323af5bc42f5a4be1f3c79d7aab226d65da53074597e429fa8 bytes=425984
    runtime.sqlite-wal: sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 bytes=0
    runtime.sqlite-shm: sha256=fd4c9fda9cd3f9ae7c962b0ddf37232294d55580e1aa165aa06129b8549389eb bytes=32768
  console: /tmp/fm-journey-20261016T075109Z/console.log sha256=5ee23079bacffdcf39229f0806e9cb4d9d9ceffb17deb762c9282c560b75fdea linhas_de_medida=598
  mídia: /tmp/fm-journey-20261016T075109Z/container/Library/Application Support/FeedMine/394FA0C4-89E8-47BF-8874-FE30EDAB9937/Media/sha256
  cartas na ordem do leitor: 42   edições: 1

[M1] A abertura entrega conteúdo na mesma geração
  pergunta do leitor: Abri o app e o conteúdo apareceu — sem o app me dizer antes que o feed estava vazio?
  fato lido: `window.cards` por geração, com o `window` atribuído ao último `admitted` anterior (AppComposition.swift:1356-1360, :2346-2350)
    [PASS] empty_then_content == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    janelas_gravadas: 3
    gerações_com_janela: 1
    vazias_atribuídas_a_uma_geração: 0
    vazias_antes_do_primeiro_install: 1
    vazias_no_fim_da_geração: 0
    linhas_de_jornada_no_console: 299
    cartas_na_linha_de_jornada: [0, 17]
    install_rejects_máximo: 0
  nota: O vazio **declarado** (a superfície dizendo que acabou) não é medido aqui: o traço não grava o estado da superfície e `preparation=done` não é isso — ver a lista de NOT_RUN.
  veredito: PASS

[M2] A primeira tela tem história
  pergunta do leitor: Toda carta que eu vi pertence a uma fonte que existe e tem para onde me levar?
  fato lido: `published_cards.source_id` e `.primary_action_reference` (a cláusula parcial do oráculo é bench/oracle.py:285-287)
    [PASS] cards_sem_fonte == 0 — esperado: 0, observado: 0
    [PASS] cards_sem_destino == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    cartas: 42
    edições: 1
    fontes_distintas: 2
    layouts: ['thumbnail']
  nota: Lida do banco, não do traço: a perda de eventos do traço não contamina esta medição.
  veredito: PASS

[M3] Rolar atinge carta que existe e para frente é para frente
  pergunta do leitor: Rolei — e cheguei a cartas de verdade, sem o app me dizer que avancei para um lugar onde eu já estava?
  fato lido: `advance.activity`/`.anchor` (AppComposition.swift:2577-2579) cruzados com a janela instalada (`admitted.head`/`tail`) e com a ordem do leitor dentro da edição (`feed_segments.edition_id`, `feed_segments.ordinal`, `published_cards.ordinal`)
    [NOT_RUN] âncora fora da janela instalada == 0 — esperado: 0, observado: 0
    [NOT_RUN] avanço forward atrás da posição observada anterior == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    avanços: 0
    por_atividade: 
    avanços_com_posição_observada_anterior: 0
    âncoras_distintas: 0
    âncoras_não_resolvidas_na_edição: 0
    avanços_para_trás_que_pousam_à_frente: 0
    gerações: 1
  nota: `avanços_para_trás_que_pousam_à_frente` = 1 em 5.390 avanços (`bench/run/20261014T200700Z`) e 0 nas outras corridas: número cru, não cláusula — o gesto ainda não foi julgado.
  veredito: NOT_RUN

[M4] Rolar com trabalho de fundo não move o que está acima da âncora
  pergunta do leitor: Rolei e nada acima de mim mudou — o app não retirou, não encolheu e não remendou o feed sob a minha leitura?
  fato lido: `admitted.cards`/`head`/`tail`/`anchor` na ordem do leitor da edição (AppComposition.swift:2346-2350; o instrumento de B04 mede o mesmo registro em bench/oracle.py:390-460)
    [PASS] janela instalada contém a âncora == 0 — esperado: 0, observado: 0
    [PASS] encolhimentos == 0 — esperado: 0, observado: 0
    [PASS] cauda recuou == 0 — esperado: 0, observado: 0
    [PASS] buracos na janela == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    instalações: 6
    instalações_não_resolvidas: 0
    cabeça_avançou: 0
    gerações: 1
  nota: `cabeça_avançou` é número cru: numa corrida que rola, a cabeça seguir o leitor é a poda declarada (`backwardWindowCards = 8`). A cláusula congelada `head == first` (bench/oracle.py:449) só é aplicável onde o leitor não anda — proposta de revisão no relatório, não executada.
  veredito: PASS

[M5] As imagens aparecem (o que o asset local prova, e o que não prova)
  pergunta do leitor: As imagens apareceram nos cartões — sem imagem quebrada?
  fato lido: `published_cards.media_key` vs. `Media/sha256/<digest>` para as cartas da janela instalada (AssetStore.swift:37-45,78-79); `render_layout` em PresentationCard.swift:11-15
    [PASS] cartas da janela com mídia declarada e sem asset local == 0 — esperado: 0, observado: 0
    [NOT_RUN] a imagem foi desenhada (pixel decodificado) — precisa de tela, não de arquivo — esperado: igualdade com a tela do cartão, observado: sem evidência
  números crus (informam, não decidem):
    cartas: 42
    edições: 1
    cartas_na_última_janela: 17
    com_mídia_declarada: 42
    digests_distintos: 37
    arquivos_em_Media/sha256: 51
    declaradas_sem_asset_em_toda_a_publicação: 0
    layouts: ['thumbnail']
  nota: O censo de toda a publicação (`declaradas_sem_asset_em_toda_a_publicação`) é número cru: a limpeza de mídia evicta por orçamento por desenho (`Sources/FeedMineMedia/MediaHousekeeping.swift:6-7`), então ausência fora da janela não é defeito. A cláusula só olha a janela instalada.
  nota: Sem `Media/sha256/` no contêiner puxado, nada disto é observável naquele insumo (as corridas do bench não materializam mídia e publicam `textOnly` em todas as cartas).
  nota: O console do aparelho já publica `hero`/`thumb`/`media_resident` por segundo (AppComposition.swift:2340-2356); transformá-los em cláusula exige decidir o que `media_resident < thumb` significa no produtor — não decidido aqui.
  veredito: NOT_RUN

[M7] A âncora que eu reabro é a âncora que o app gravou
  pergunta do leitor: Fechei e reabri — o app me devolveu exatamente onde eu estava?
  fato lido: último `position_checkpoint.anchor` do traço (AppComposition.swift:2689-2690) vs. `context_checkpoints.card_id` (a linha do contexto medido) e `session_checkpoint.card_id`
    [PASS] âncora durável do contexto medido == última âncora relatada — esperado: igualdade, observado: True
    [PASS] a linha de sessão concorda com a do contexto medido — esperado: 5b2ee11d-b253-426c-bde2-2d331c218b67, observado: 5b2ee11d-b253-426c-bde2-2d331c218b67
  números crus (informam, não decidem):
    edição_medida: 0bca9384-0e4f-4d86-9bb1-c27aa811bb6b
    checkpoints_relatados: 1
    âncora_relatada: 5b2ee11d-b253-426c-bde2-2d331c218b67
    âncora_relatada_índice: 0
    âncora_durável: 5b2ee11d-b253-426c-bde2-2d331c218b67
    âncora_durável_índice: 0
    linhas_de_contexto_do_medido: 1
    âncora_durável_em: 2026-10-16T07:51:13Z
    último_evento_do_traço_em: 2026-10-16T07:55:32Z
    traço_completo: True
    regressão_da_âncora: False
  nota: O **pouso** da reabertura não é medido: o traço cobre uma sessão e a instalação que restaura a âncora é de outra. `admitted` grava a âncora instalada (AppComposition.swift:2346-2350) mas não grava o tipo de admissão — `.restore` existe em `Sources/FeedMineRuntime/FeedPresentationAdmission.swift:72` e é usado em AppComposition.swift:2709. Sem esse campo, o instrumento não sabe qual instalação é a reabertura e não afirma nada sobre o pouso.
  veredito: PASS

[M10] Rolar rápido: a série de quadros, relatada
  pergunta do leitor: Rolei rápido — o que o app mediu de cada segundo, quadro a quadro?
  fato lido: `frames.frames/late/bad/severe/worst_ms/budget_ms` do traço (FeedFrameMeter.swift) e as linhas `feedmine frames=…` do console
    [PASS] série medida (segundos > 0) — esperado: > 0, observado: 260
  números crus (informam, não decidem):
    traço: segundos=260, quadros=15586, late=2, bad=0, severe=4, fora_do_orçamento=6, razão_fora_do_orçamento=0.00038, pior_intervalo_ms=152.0, segundos_com_severe=2
    console: segundos=299, quadros=17938, late=2, bad=0, severe=4, fora_do_orçamento=6, razão_fora_do_orçamento=0.00033, pior_intervalo_ms=152.0, segundos_com_severe=2
    traço_completo: True
  nota: Sem limiar por desenho: a razão fora do orçamento é impressa e não decide. `--series` imprime a série inteira, uma linha por segundo.
  veredito: PASS

sem evidência hoje (NOT_RUN por contrato, não por falha):
[M1/M6 (superfície)] O vazio e o fim **declarados** pela superfície
  veredito: NOT_RUN
  falta: Nenhum evento diz que a superfície declarou o feed vazio ou o fim de feed. `preparation=done` na linha de jornada **não** é isso: significa que o relé não recebeu nada (`FeedMineApp/FeedMineApp/AppComposition.swift:2363-2366`), e depois dele o host ainda agenda nova tentativa (`:2507-2535`). Sem essa evidência, a cláusula do vazio terminal fica não medida.
  onde: `Sources/FeedMineUI/FeedPresentationState.swift:45` (o caso `endOfContent`), `Sources/FeedMineUI/FeedScreen.swift:200` (onde é desenhado), `FeedMineApp/FeedMineApp/AppComposition.swift:2431-2433` (onde é concluído) e `:2399-2400` (onde o app descobre que o fim mostrado era falso) — nenhum grava.
[M8] Sem rede: história local e a carta salva abre
  veredito: NOT_RUN
  falta: O app não grava que o transporte estava bloqueado (`FEEDMINE_BLOCK_RSS_NETWORK` é lido e não vira evento) nem que a carta salva abriu (o banco diz que foi salva).
  onde: `FeedMineApp/FeedMineApp/AppComposition.swift:174-177`.
[M9] Primeiro uso sem assinatura
  veredito: NOT_RUN
  falta: Não implementada de propósito: exige o conjunto congelado `STARTER_KEYS`, que é régua congelada — duplicá-lo aqui criaria duas fontes para o mesmo fato. A cláusula já existe como B01.
  onde: `bench/oracle.py:35-39,195-198`.
[M11] App aberto 30 min: fontes novas no fim das janelas
  veredito: NOT_RUN
  falta: O traço não tem o carimbo de fim de janela nem o conjunto de fontes por janela.
  onde: `bench/expand.py:26` (o instrumento congelado que já mede isso).
[M12] p50/p95 de lançamento → primeira carta
  veredito: NOT_RUN
  falta: O instante do lançamento não é gravado: o traço começa no primeiro `window`/`frames` e a linha de jornada conta `t=` do primeiro quadro desenhado. Um percentil exige ≥30 execuções.
  onde: Um `record("launch", …)` em `FeedMineApp/FeedMineApp/AppComposition.swift:71-72`/`:258` ou em `FeedMineApp/FeedMineApp/FeedMineApp.swift:23`.
[M7 (pouso)] O pouso da reabertura: a carta que o app instala no topo depois de relançar
  veredito: NOT_RUN
  falta: O traço cobre uma sessão e não diz qual instalação é a restauração. `admitted` grava a âncora instalada, mas não o tipo de admissão.
  onde: `FeedMineApp/FeedMineApp/AppComposition.swift:2346-2350` (gravar o tipo) — `.restore` em `Sources/FeedMineRuntime/FeedPresentationAdmission.swift:72`, usado em `AppComposition.swift:2709`.

veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=PASS, M2=PASS, M3=NOT_RUN, M4=PASS, M5=NOT_RUN, M7=PASS, M10=PASS)
```

## 4. Os outros três insumos (extrato: vereditos e linhas de medida)

Texto inteiro em `/tmp/fm-obvious/out-run-<stamp>.txt`; aqui só a linha de proveniência, os fatos e o veredito de
cada insumo.

```text
### bench/run/20261014T173601Z (B05, completo)
    sha256=ba1114ba4685e30817cb19f29071d2040b171bc065b617462da285bb5b367431 linhas=658 ilegíveis=0 janela=2026-10-14T17:37:42Z → 2026-10-14T17:38:40Z completo=True
[M1] A abertura entrega conteúdo na mesma geração
    [PASS] empty_then_content == 0 — esperado: 0, observado: 0
  veredito: PASS
[M2] A primeira tela tem história
    [PASS] cards_sem_fonte == 0 — esperado: 0, observado: 0
    [PASS] cards_sem_destino == 0 — esperado: 0, observado: 0
  veredito: PASS
[M3] Rolar atinge carta que existe e para frente é para frente
    [PASS] âncora fora da janela instalada == 0 — esperado: 0, observado: 0
    [PASS] avanço forward atrás da posição observada anterior == 0 — esperado: 0, observado: 0
  veredito: PASS
[M4] Rolar com trabalho de fundo não move o que está acima da âncora
    [PASS] janela instalada contém a âncora == 0 — esperado: 0, observado: 0
    [PASS] encolhimentos == 0 — esperado: 0, observado: 0
    [PASS] cauda recuou == 0 — esperado: 0, observado: 0
    [PASS] buracos na janela == 0 — esperado: 0, observado: 0
  veredito: PASS
[M5] As imagens aparecem (o que o asset local prova, e o que não prova)
    [NOT_RUN] cartas da janela com mídia declarada e sem asset local == 0 — esperado: 0, observado: 0
    [NOT_RUN] a imagem foi desenhada (pixel decodificado) — precisa de tela, não de arquivo — esperado: igualdade com a tela do cartão, observado: sem evidência
  veredito: NOT_RUN
[M7] A âncora que eu reabro é a âncora que o app gravou
    [NOT_RUN] âncora durável do contexto medido == última âncora relatada — esperado: igualdade, observado: não comparável
    [PASS] a linha de sessão concorda com a do contexto medido — esperado: 7d1ccd45-5bd6-4324-9ada-8650c4aea826, observado: 7d1ccd45-5bd6-4324-9ada-8650c4aea826
  veredito: NOT_RUN
[M10] Rolar rápido: a série de quadros, relatada
    [PASS] série medida (segundos > 0) — esperado: > 0, observado: 108
  veredito: PASS
[M1/M6 (superfície)] O vazio e o fim **declarados** pela superfície
  veredito: NOT_RUN
[M8] Sem rede: história local e a carta salva abre
  veredito: NOT_RUN
[M9] Primeiro uso sem assinatura
  veredito: NOT_RUN
[M11] App aberto 30 min: fontes novas no fim das janelas
  veredito: NOT_RUN
[M12] p50/p95 de lançamento → primeira carta
  veredito: NOT_RUN
[M7 (pouso)] O pouso da reabertura: a carta que o app instala no topo depois de relançar
  veredito: NOT_RUN
veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=PASS, M2=PASS, M3=PASS, M4=PASS, M5=NOT_RUN, M7=NOT_RUN, M10=PASS)

### bench/run/20261014T214403Z (B04, completo)
    sha256=59c71ea67386d593cc9779d1a10d5e81533e5bd980bb0e014fa5b6101142e147 linhas=1199 ilegíveis=0 janela=2026-10-14T21:45:56Z → 2026-10-14T21:48:18Z completo=True
[M1] A abertura entrega conteúdo na mesma geração
    [PASS] empty_then_content == 0 — esperado: 0, observado: 0
  veredito: PASS
[M2] A primeira tela tem história
    [PASS] cards_sem_fonte == 0 — esperado: 0, observado: 0
    [PASS] cards_sem_destino == 0 — esperado: 0, observado: 0
  veredito: PASS
[M3] Rolar atinge carta que existe e para frente é para frente
    [PASS] âncora fora da janela instalada == 0 — esperado: 0, observado: 0
    [PASS] avanço forward atrás da posição observada anterior == 0 — esperado: 0, observado: 0
  veredito: PASS
[M4] Rolar com trabalho de fundo não move o que está acima da âncora
    [PASS] janela instalada contém a âncora == 0 — esperado: 0, observado: 0
    [PASS] encolhimentos == 0 — esperado: 0, observado: 0
    [PASS] cauda recuou == 0 — esperado: 0, observado: 0
    [PASS] buracos na janela == 0 — esperado: 0, observado: 0
  veredito: PASS
[M5] As imagens aparecem (o que o asset local prova, e o que não prova)
    [NOT_RUN] cartas da janela com mídia declarada e sem asset local == 0 — esperado: 0, observado: 0
    [NOT_RUN] a imagem foi desenhada (pixel decodificado) — precisa de tela, não de arquivo — esperado: igualdade com a tela do cartão, observado: sem evidência
  veredito: NOT_RUN
[M7] A âncora que eu reabro é a âncora que o app gravou
    [PASS] âncora durável do contexto medido == última âncora relatada — esperado: igualdade, observado: True
    [PASS] a linha de sessão concorda com a do contexto medido — esperado: 7bea1728-5213-43d9-a7b8-97a2ee0c5367, observado: 7bea1728-5213-43d9-a7b8-97a2ee0c5367
  veredito: PASS
[M10] Rolar rápido: a série de quadros, relatada
    [PASS] série medida (segundos > 0) — esperado: > 0, observado: 276
  veredito: PASS
[M1/M6 (superfície)] O vazio e o fim **declarados** pela superfície
  veredito: NOT_RUN
[M8] Sem rede: história local e a carta salva abre
  veredito: NOT_RUN
[M9] Primeiro uso sem assinatura
  veredito: NOT_RUN
[M11] App aberto 30 min: fontes novas no fim das janelas
  veredito: NOT_RUN
[M12] p50/p95 de lançamento → primeira carta
  veredito: NOT_RUN
[M7 (pouso)] O pouso da reabertura: a carta que o app instala no topo depois de relançar
  veredito: NOT_RUN
veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=PASS, M2=PASS, M3=PASS, M4=PASS, M5=NOT_RUN, M7=PASS, M10=PASS)

### bench/run/20261014T200700Z (B03, incompleto)
    sha256=6b6aa1680bccb9817c974b6bf0560afa2b435ed7903b50c44f4bbab055b6cea1 linhas=39961 ilegíveis=0 janela=2026-10-14T20:10:39Z → 2026-10-14T20:40:39Z completo=False
    perda declarada pelo traço: {'anúncios': 25, 'teto': 40000, 'escrito': 40000, 'perdidos_pelo_teto': 137, 'perdidos_pela_escrita': 64, 'perdidos_pela_codificação': 0}
[M1] A abertura entrega conteúdo na mesma geração
    [NOT_RUN] empty_then_content == 0 — esperado: 0, observado: 0
  veredito: NOT_RUN
[M2] A primeira tela tem história
    [PASS] cards_sem_fonte == 0 — esperado: 0, observado: 0
    [PASS] cards_sem_destino == 0 — esperado: 0, observado: 0
  veredito: PASS
[M3] Rolar atinge carta que existe e para frente é para frente
    [NOT_RUN] âncora fora da janela instalada == 0 — esperado: 0, observado: 0
    [NOT_RUN] avanço forward atrás da posição observada anterior == 0 — esperado: 0, observado: 0
  veredito: NOT_RUN
[M4] Rolar com trabalho de fundo não move o que está acima da âncora
    [NOT_RUN] janela instalada contém a âncora == 0 — esperado: 0, observado: 0
    [NOT_RUN] encolhimentos == 0 — esperado: 0, observado: 0
    [NOT_RUN] cauda recuou == 0 — esperado: 0, observado: 0
    [NOT_RUN] buracos na janela == 0 — esperado: 0, observado: 0
  veredito: NOT_RUN
[M5] As imagens aparecem (o que o asset local prova, e o que não prova)
    [NOT_RUN] cartas da janela com mídia declarada e sem asset local == 0 — esperado: 0, observado: 0
    [NOT_RUN] a imagem foi desenhada (pixel decodificado) — precisa de tela, não de arquivo — esperado: igualdade com a tela do cartão, observado: sem evidência
  veredito: NOT_RUN
[M7] A âncora que eu reabro é a âncora que o app gravou
    [NOT_RUN] âncora durável do contexto medido == última âncora relatada — esperado: igualdade, observado: não comparável
    [PASS] a linha de sessão concorda com a do contexto medido — esperado: 0528bbce-e651-4d0e-98c3-dab84e42e769, observado: 0528bbce-e651-4d0e-98c3-dab84e42e769
  veredito: NOT_RUN
[M10] Rolar rápido: a série de quadros, relatada
    [PASS] série medida (segundos > 0) — esperado: > 0, observado: 1927
  veredito: PASS
[M1/M6 (superfície)] O vazio e o fim **declarados** pela superfície
  veredito: NOT_RUN
[M8] Sem rede: história local e a carta salva abre
  veredito: NOT_RUN
[M9] Primeiro uso sem assinatura
  veredito: NOT_RUN
[M11] App aberto 30 min: fontes novas no fim das janelas
  veredito: NOT_RUN
[M12] p50/p95 de lançamento → primeira carta
  veredito: NOT_RUN
[M7 (pouso)] O pouso da reabertura: a carta que o app instala no topo depois de relançar
  veredito: NOT_RUN
veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=NOT_RUN, M2=PASS, M3=NOT_RUN, M4=NOT_RUN, M5=NOT_RUN, M7=NOT_RUN, M10=PASS)
```

**Resumo dos cinco insumos.** Completos: B05 → M1/M2/M3/M4/M10 PASS e M7 `NOT_RUN` só porque a linha durável
foi escrita 35 s depois do fim do traço; B04 → o mesmo com M7 PASS; aparelho → M1/M2/M4/M7/M10 PASS e M3
`NOT_RUN` (a jornada não rolou: 0 `advance`). Incompletos: B03 ×2 → M1/M3/M4/M7 `NOT_RUN`, M2 e M10 `PASS`.
M5 é `NOT_RUN` em todos, e o motivo é diferente em cada família de insumo (sem mídia no bench; pergunta visual
em todos) — ver §6.

## 5. Controle positivo — dez injeções

Cada injeção é aplicada numa **cópia** do insumo; o original nunca é aberto para escrita. A cópia agora leva
**todo** o insumo (traço, banco com sidecars, mídia e `console.log`), porque sem o console uma injeção tiraria da
cópia evidência que não tem nada a ver com ela.

### injeção m1 — exit=1

```text
    linha 543:
    [FAIL] empty_then_content == 0 — esperado: 0, observado: 1
veredito do insumo (sem substituir gate nenhum): FAIL (M1=FAIL, M2=PASS, M3=PASS, M4=PASS, M5=NOT_RUN, M7=NOT_RUN, M10=PASS)
```

### injeção m2 — exit=1

```text
    [FAIL] cards_sem_destino == 0 — esperado: 0, observado: 1
veredito do insumo (sem substituir gate nenhum): FAIL (M1=PASS, M2=FAIL, M3=PASS, M4=PASS, M5=NOT_RUN, M7=NOT_RUN, M10=PASS)
```

### injeção m3a — exit=1

```text
    linha 556:
    [FAIL] âncora fora da janela instalada == 0 — esperado: 0, observado: 1
veredito do insumo (sem substituir gate nenhum): FAIL (M1=PASS, M2=PASS, M3=FAIL, M4=PASS, M5=NOT_RUN, M7=NOT_RUN, M10=PASS)
```

### injeção m3b — exit=1

```text
    linha 541:
    [FAIL] avanço forward atrás da posição observada anterior == 0 — esperado: 0, observado: 1
veredito do insumo (sem substituir gate nenhum): FAIL (M1=PASS, M2=PASS, M3=FAIL, M4=PASS, M5=NOT_RUN, M7=NOT_RUN, M10=PASS)
```

### injeção m4 — exit=1

```text
    linha 469:
    [FAIL] encolhimentos == 0 — esperado: 0, observado: 1
veredito do insumo (sem substituir gate nenhum): FAIL (M1=PASS, M2=PASS, M3=PASS, M4=FAIL, M5=NOT_RUN, M7=NOT_RUN, M10=PASS)
```

### injeção m5 — exit=1

```text
    [FAIL] cartas da janela com mídia declarada e sem asset local == 0 — esperado: 0, observado: 1
veredito do insumo (sem substituir gate nenhum): FAIL (M1=PASS, M2=PASS, M3=NOT_RUN, M4=PASS, M5=FAIL, M7=PASS, M10=PASS)
```

### injeção m5b — exit=0

```text
veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=PASS, M2=PASS, M3=NOT_RUN, M4=PASS, M5=NOT_RUN, M7=PASS, M10=PASS)
```

### injeção m7 — exit=1

```text
    [FAIL] âncora durável do contexto medido == última âncora relatada — esperado: igualdade, observado: False
veredito do insumo (sem substituir gate nenhum): FAIL (M1=PASS, M2=PASS, M3=PASS, M4=PASS, M5=NOT_RUN, M7=FAIL, M10=PASS)
```

### injeção m7a — exit=1

```text
    [FAIL] âncora durável do contexto medido == última âncora relatada — esperado: igualdade, observado: False
veredito do insumo (sem substituir gate nenhum): FAIL (M1=PASS, M2=PASS, M3=PASS, M4=PASS, M5=NOT_RUN, M7=FAIL, M10=PASS)
```

### injeção m10 — exit=0

```text
    linha 2 REMOVIDA: {"at":1791999462.7412019,"event":"frames","fields":{"bad":"0","worst_at":"2423959.223","budget_ms":"16.67","frames":"1","late":"0","worst_ms":"211.1","severe":"
    linha 3 REMOVIDA: {"event":"frames","mono":2423960.2505417084,"at":1791999463.7578301,"fields":{"late":"1","bad":"0","frames":"60","worst_at":"2423959.250","worst_ms":"27.0","sev
    linha 4 REMOVIDA: {"fields":{"late":"0","budget_ms":"16.67","frames":"53","worst_at":"2423961.178","bad":"1","worst_ms":"111.6","severe":"1"},"mono":2423961.250530542,"at":179199
    linha 5 REMOVIDA: {"mono":2423962.2505343333,"at":1791999465.757837,"event":"frames","fields":{"late":"0","frames":"54","worst_at":"2423961.478","worst_ms":"94.5","bad":"1","budg
veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=PASS, M2=PASS, M3=PASS, M4=PASS, M5=NOT_RUN, M7=NOT_RUN, M10=NOT_RUN)
```


### 5.11 Contraprovas sintéticas (achados 2 e 5 da revisão)

Três insumos minúsculos, montados em `/tmp` a partir de um banco real (B05) mais um traço escrito por
`/tmp/fm-obvious/contraprovas.py` — nenhum corpus foi copiado. Eles reproduzem **os exemplos da própria revisão**:

```text
########## fx-duas-edicoes (exit=0)
[M3] Rolar atinge carta que existe e para frente é para frente
  pergunta do leitor: Rolei — e cheguei a cartas de verdade, sem o app me dizer que avancei para um lugar onde eu já estava?
  fato lido: `advance.activity`/`.anchor` (AppComposition.swift:2577-2579) cruzados com a janela instalada (`admitted.head`/`tail`) e com a ordem do leitor dentro da edição (`feed_segments.edition_id`, `feed_segments.ordinal`, `published_cards.ordinal`)
    [NOT_RUN] âncora fora da janela instalada == 0 — esperado: 0, observado: 0
    [NOT_RUN] avanço forward atrás da posição observada anterior == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    avanços: 3
    por_atividade: forward=3
    avanços_com_posição_observada_anterior: 0
    âncoras_distintas: 2
    âncoras_não_resolvidas_na_edição: 1
    avanços_para_trás_que_pousam_à_frente: 0
    gerações: 2
  nota: `avanços_para_trás_que_pousam_à_frente` = 1 em 5.390 avanços (`bench/run/20261014T200700Z`) e 0 nas outras corridas: número cru, não cláusula — o gesto ainda não foi julgado.
  veredito: NOT_RUN

[M4] Rolar com trabalho de fundo não move o que está acima da âncora
  pergunta do leitor: Rolei e nada acima de mim mudou — o app não retirou, não encolheu e não remendou o feed sob a minha leitura?
  fato lido: `admitted.cards`/`head`/`tail`/`anchor` na ordem do leitor da edição (AppComposition.swift:2346-2350; o instrumento de B04 mede o mesmo registro em bench/oracle.py:390-460)
    [PASS] janela instalada contém a âncora == 0 — esperado: 0, observado: 0
    [PASS] encolhimentos == 0 — esperado: 0, observado: 0
    [PASS] cauda recuou == 0 — esperado: 0, observado: 0
    [PASS] buracos na janela == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    instalações: 2
    instalações_não_resolvidas: 0
    cabeça_avançou: 0
    gerações: 2
  nota: `cabeça_avançou` é número cru: numa corrida que rola, a cabeça seguir o leitor é a poda declarada (`backwardWindowCards = 8`). A cláusula congelada `head == first` (bench/oracle.py:449) só é aplicável onde o leitor não anda — proposta de revisão no relatório, não executada.
  veredito: PASS
  [contraprova] na ordem GLOBAL a mesma instalação daria head=34 tail=36 cards=2 → buraco=True; e a âncora da outra edição ficaria no índice 35, dentro de [34,36] → passaria como se fosse da mesma janela

########## fx-geracoes (exit=0)
[M3] Rolar atinge carta que existe e para frente é para frente
  pergunta do leitor: Rolei — e cheguei a cartas de verdade, sem o app me dizer que avancei para um lugar onde eu já estava?
  fato lido: `advance.activity`/`.anchor` (AppComposition.swift:2577-2579) cruzados com a janela instalada (`admitted.head`/`tail`) e com a ordem do leitor dentro da edição (`feed_segments.edition_id`, `feed_segments.ordinal`, `published_cards.ordinal`)
    [PASS] âncora fora da janela instalada == 0 — esperado: 0, observado: 0
    [PASS] avanço forward atrás da posição observada anterior == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    avanços: 3
    por_atividade: forward=3
    avanços_com_posição_observada_anterior: 1
    âncoras_distintas: 3
    âncoras_não_resolvidas_na_edição: 0
    avanços_para_trás_que_pousam_à_frente: 0
    gerações: 2
  nota: `avanços_para_trás_que_pousam_à_frente` = 1 em 5.390 avanços (`bench/run/20261014T200700Z`) e 0 nas outras corridas: número cru, não cláusula — o gesto ainda não foi julgado.
  veredito: PASS

[M4] Rolar com trabalho de fundo não move o que está acima da âncora
  pergunta do leitor: Rolei e nada acima de mim mudou — o app não retirou, não encolheu e não remendou o feed sob a minha leitura?
  fato lido: `admitted.cards`/`head`/`tail`/`anchor` na ordem do leitor da edição (AppComposition.swift:2346-2350; o instrumento de B04 mede o mesmo registro em bench/oracle.py:390-460)
    [PASS] janela instalada contém a âncora == 0 — esperado: 0, observado: 0
    [PASS] encolhimentos == 0 — esperado: 0, observado: 0
    [PASS] cauda recuou == 0 — esperado: 0, observado: 0
    [PASS] buracos na janela == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    instalações: 2
    instalações_não_resolvidas: 0
    cabeça_avançou: 0
    gerações: 2
  nota: `cabeça_avançou` é número cru: numa corrida que rola, a cabeça seguir o leitor é a poda declarada (`backwardWindowCards = 8`). A cláusula congelada `head == first` (bench/oracle.py:449) só é aplicável onde o leitor não anda — proposta de revisão no relatório, não executada.
  veredito: PASS

########## fx-stationary (exit=1)
[M3] Rolar atinge carta que existe e para frente é para frente
  pergunta do leitor: Rolei — e cheguei a cartas de verdade, sem o app me dizer que avancei para um lugar onde eu já estava?
  fato lido: `advance.activity`/`.anchor` (AppComposition.swift:2577-2579) cruzados com a janela instalada (`admitted.head`/`tail`) e com a ordem do leitor dentro da edição (`feed_segments.edition_id`, `feed_segments.ordinal`, `published_cards.ordinal`)
    [PASS] âncora fora da janela instalada == 0 — esperado: 0, observado: 0
    [FAIL] avanço forward atrás da posição observada anterior == 0 — esperado: 0, observado: 1
  números crus (informam, não decidem):
    avanços: 3
    por_atividade: forward=2, stationary=1
    avanços_com_posição_observada_anterior: 2
    âncoras_distintas: 3
    âncoras_não_resolvidas_na_edição: 0
    avanços_para_trás_que_pousam_à_frente: 0
    gerações: 1
  nota: `avanços_para_trás_que_pousam_à_frente` = 1 em 5.390 avanços (`bench/run/20261014T200700Z`) e 0 nas outras corridas: número cru, não cláusula — o gesto ainda não foi julgado.
  veredito: FAIL

[M4] Rolar com trabalho de fundo não move o que está acima da âncora
  pergunta do leitor: Rolei e nada acima de mim mudou — o app não retirou, não encolheu e não remendou o feed sob a minha leitura?
  fato lido: `admitted.cards`/`head`/`tail`/`anchor` na ordem do leitor da edição (AppComposition.swift:2346-2350; o instrumento de B04 mede o mesmo registro em bench/oracle.py:390-460)
    [PASS] janela instalada contém a âncora == 0 — esperado: 0, observado: 0
    [PASS] encolhimentos == 0 — esperado: 0, observado: 0
    [PASS] cauda recuou == 0 — esperado: 0, observado: 0
    [PASS] buracos na janela == 0 — esperado: 0, observado: 0
  números crus (informam, não decidem):
    instalações: 1
    instalações_não_resolvidas: 0
    cabeça_avançou: 0
    gerações: 1
  nota: `cabeça_avançou` é número cru: numa corrida que rola, a cabeça seguir o leitor é a poda declarada (`backwardWindowCards = 8`). A cláusula congelada `head == first` (bench/oracle.py:449) só é aplicável onde o leitor não anda — proposta de revisão no relatório, não executada.
  veredito: PASS
```

Leitura dos controles: oito injeções (m1, m2, m3a, m3b, m4, m5, m7, m7a) viram exatamente **uma** cláusula
`FAIL` e nada mais muda; `m10` vira a guarda de vacuidade em `NOT_RUN` (M10 não tem limiar por desenho — escolher
um seria o defeito Q3); `m5b` **não** muda veredito nenhum e é o controle documental de que o censo de blobs é
número cru: `com_mídia_declarada` cai de 42 para 41 e `digests_distintos` de 37 para 36, e M5 continua
`NOT_RUN` pela metade visual.

## 6. O que ficou `NOT_RUN` — lista explícita

**Sem evidência no produto (falta gravar):**

| # | Falta | Onde gravar |
|---|---|---|
| **M1/M6 (superfície)** | Um evento quando a superfície declara o feed vazio ou o fim de feed. `preparation=done` **não** serve: é só "o relé não recebeu nada" (`AppComposition.swift:2363-2366`), e depois dele o host agenda nova tentativa (`:2507-2535`) | `FeedPresentationState.swift:45`, `FeedScreen.swift:200`, `AppComposition.swift:2431-2433` e `:2399-2400` |
| **M8** | Que o transporte estava bloqueado e que a carta salva abriu | `AppComposition.swift:174-177` |
| **M9** | Não implementada de propósito: exigiria duplicar `STARTER_KEYS`, régua congelada | já existe como B01 (`bench/oracle.py:35-39,195-198`) |
| **M11** | Carimbo de fim de janela e fontes por janela | medido por `bench/expand.py:26` (congelado) |
| **M12** | O instante do lançamento (e ≥30 execuções para um percentil) | `AppComposition.swift:71-72`/`:258`, `FeedMineApp.swift:23` |
| **M7 (pouso)** | O tipo de admissão da instalação: sem ele não se sabe qual instalação é a restauração | `AppComposition.swift:2346-2350` (`.restore` existe em `FeedPresentationAdmission.swift:72`, usado em `:2709`) |

**Depende do insumo ou da evidência disponível:**

| # | Insumo | Por que `NOT_RUN` |
|---|---|---|
| **M5 (visual)** | todos | arquivo presente não prova pixel desenhado: `PresentationImage.swift:48-65` devolve `nil` quando a decodificação falha e `PresentationCard.swift:50-51` distingue bitmap residente de slot. O repo não guarda tela decodificada |
| **M5 (censo)** | corridas do bench | nenhuma carta declara mídia (`textOnly` em 867/867 no B03) e o contêiner não traz `Media/sha256/` |
| **M1, M3, M4, M7** | B03 ×2 (traço incompleto) | o traço anuncia 2.030 (e 137+64) eventos perdidos: ausência de violação não é prova |
| **M7** | B05 | a linha durável é 35 s mais nova que o último evento do traço — os dois registros não são do mesmo instante |
| **M3** | jornada de aparelho | 0 `advance`: a jornada não rolou, não há gesto para julgar |
| **M7** | qualquer insumo com ≥2 linhas de contexto na mesma edição, ou com a edição medida ausente | o instrumento não sabe **qual** contexto foi medido e não escolhe a primeira linha |

### 6.1 A lista acima não é aprovação de nada

As cláusulas da primeira tabela (falta gravar no produto) e as que o instrumento congelado já mede no lugar
(M9 = B01, M11 = `bench/expand.py`) continuam **identificadas como não implementadas aqui** — no relatório e na
saída impressa, sem exceção: o bloco `sem evidência hoje` diz, em cada linha, "cláusulas que este instrumento
**não** implementa e que **não** são aprovação global". Elas não são medida deste instrumento, não viram `PASS` e
**não entram no código de saída**: um insumo limpo devolve `0` com elas listadas, porque `0` afirma apenas "toda
cláusula **aplicável** foi medida e deu `PASS`" (§11.2) — nada além disso. Nenhuma linha daqui substitui
B01–B06, e o instrumento continua diagnóstico auxiliar, nunca oráculo.

## 7. Resposta à revisão independente (item por item)

| # | Achado | O que mudou | Evidência medida nesta versão |
|---|---|---|---|
| 1 | Evidência truncada não pode provar ausência | Traço ganhou `complete()` (perdas anunciadas + linhas ilegíveis) e cada cláusula de contagem usa `absence()`: violação observada permanece `FAIL`, zero sobre traço incompleto vira `NOT_RUN` | §2: B03 (2.030 perdidos) e §4: 200700Z (137+64) → M1/M3/M4/M7 `NOT_RUN`; B05/B04/aparelho (completos) → `PASS` |
| 2 | Ordem das cartas por edição | `READER_ORDER` passou a devolver `edition` e a ordenar por edição; todo índice é resolvido na ordem **da edição da carta** | fixtures §5.11: em `fx-duas-edicoes` (duas edições com o mesmo ordinal de segmento) M4 dá `buracos == 0` e `instalações_não_resolvidas: 0`, enquanto a ordem **global** daria `head=34 tail=36 cards=2 → buraco=True`; e a âncora de outra edição fica `âncoras_não_resolvidas_na_edição: 1` → `NOT_RUN`, em vez de passar dentro da janela |
| 3 | Arquivo de mídia ≠ pixel | M5 passou a ter dois fatos separados: (a) cartas **da janela instalada** que declaram mídia e não têm o asset (o arquivo ausente prova que a imagem não pôde ser desenhada); (b) a pergunta visual, `NOT_RUN` — e o censo de toda a publicação virou número cru | aparelho: (a) `PASS` com 17 cartas na janela, 51 arquivos; injeção `m5` apaga o asset de uma carta da janela → `FAIL`; `m5b` muda só o censo |
| 4 | Checkpoint do contexto medido | O contexto é escolhido pela **edição do último `admitted`**; se não houver exatamente uma linha, `NOT_RUN`. A linha de `session_checkpoint` virou **fato** (antes era só número) | B04 e aparelho: contexto medido identificado, as duas linhas concordam → `PASS`; injeções `m7`/`m7a` → `FAIL` |
| 5 | Reset da posição anterior por geração | A comparação de M3 é dentro da geração e usa a **última posição observada, inclusive `stationary`** | fixtures §5.11: `fx-geracoes` → `PASS` com `avanços_com_posição_observada_anterior: 1` (o primeiro avanço da segunda geração não é comparado com a primeira); `fx-stationary` (o exemplo da revisão: `forward 10 → stationary 20 → forward 15`) → `FAIL`, observado 1; injeção `m3b` no insumo real → `FAIL` |
| 6 | `preparation=done` não é fim vazio | A metade de console de M1 foi **retirada** (era falso vermelho em potencial) e virou entrada explícita de `NOT_RUN` | §6, primeira linha da tabela de "falta gravar" |
| 7 | `[True, None]` virava `PASS` | `verdict_of` agora é `FAIL` > `NOT_RUN` (qualquer sub-fato não medido) > `PASS` | M5 em todos os insumos: `(a) PASS` + `(b) NOT_RUN` → `NOT_RUN`, não `PASS` |
| 8 | Console não sobrevivia às cópias | `_copy_insumo` copia traço, banco com sidecars, mídia **e `console.log`** | injeção `m10` reporta agora "linhas do console" além das do traço; a comparação "só a cláusula-alvo muda" é verificada nas dez injeções |

Também atendido: a proveniência passou a registrar **sha256 de cada arquivo bruto** (`runtime.sqlite`, `-wal`,
`-shm`), não só do banco principal; a nota sobre "dois orçamentos de quadro no mesmo arquivo" foi **removida** —
ela estava desatualizada (na revisão revisada, `FeedFrameMeter` publica o mesmo orçamento que usa para
classificar), e não era medição deste instrumento.

## 8. Achados sobre a régua congelada — documentados, **não** executados

Nada de `bench/` foi alterado. Os dois achados abaixo são medidos; o resto da primeira versão (§7.3, §7.5,
§7.6) era hipótese ou estava desatualizado e saiu do relatório.

1. **`head == first` não é aplicável onde o leitor anda** (`bench/oracle.py:432-460`, linha `:449`). Medido em
   `bench/run/20261014T173601Z`: a cabeça avançou 22 vezes, e nas duas ocasiões inspecionadas a cabeça era
   `âncora − 8` — a poda declarada de `backwardWindowCards = 8` (`AppComposition.swift:1861`). A cláusula foi
   escrita para o B04, onde o leitor não anda; numa corrida que rola ela acusaria a própria poda. Proposta (não
   executada): escopar a cláusula pela jornada, ou medir "a janela contém a âncora + não encolhe + a cauda não
   recua + sem buracos" — que é o M4 daqui, e que dá 0 nos cinco insumos.
2. **`avanços == cartas_distintas` (M3 no estudo) é falso nos dados reais, e não por defeito do produto.**
   `bench/run/20261014T182436Z`: 5.407 `advance` para 865 âncoras distintas, e 230 avanços `forward` repetem a
   âncora anterior — 219 deles logo depois de uma observação `stationary`, no topo do feed. Adotar a cláusula
   literal reprovaria o gesto legítimo (falha Q1). Não é adotada aqui.

Fato medido que sustenta o `NOT_RUN` de M7-pouso (também não é proposta de mudança, é o que falta):
`bench/run/20261014T173601Z` tem 658 eventos cobrindo 58,6 s de **um** lançamento, e a linha durável de posição
foi escrita 35 s depois do último evento do traço. O caminho pelo qual a cópia do contêiner deixa de fora a
sessão que gravou (`bench/run.sh:536-542`) não foi investigado: o instrumento relata o que falta, não a causa.

## 9. O que este relatório não prova, e como reproduzir

Não prova: (a) nada foi executado em build novo (o disco ficou em 1,8 GB e a regra do projeto recusa corrida
abaixo de 3 GB — toda a evidência vem de corridas de 2026-10-14 e de uma jornada de aparelho de 2026-10-16);
(b) M7 mede metade da jornada (a identidade durável, não o pouso); (c) M5 mede o asset local, não o pixel;
(d) M10 não tem veredito de desempenho por desenho; (e) o bench não publica mídia, então M5 só tem sujeito no
aparelho; (f) esta seção foi escrita antes do recorte: hoje o instrumento está commitado na branch
`instruments/journey-measurements` e o recorte revisado, pronto para fast-forward da `main`, em
`instruments/journey-recut` (§11.5) — a evidência de medição continua sendo a das corridas de 2026-10-14 e da
jornada de aparelho de 2026-10-16, nenhuma delas refeita.

```bash
# instrumento (o artefato testado; sha256 92869365… nesta versão, 4e4eff07… no recorte — ver §11)
python3 bench/journey.py --help
python3 bench/journey.py --run bench/run/20261014T173601Z          # completo: M1/M2/M3/M4/M10 PASS
python3 bench/journey.py --run bench/run/20261014T182436Z          # traço incompleto: NOT_RUN, não PASS
python3 bench/journey.py --run bench/run/20261014T214403Z
python3 bench/journey.py --journey /tmp/fm-journey-20261016T075109Z
python3 bench/journey.py --journey /tmp/fm-journey-20261016T075109Z --json | python3 -m json.tool | head
python3 bench/journey.py --run bench/run/20261014T173601Z --series | sed -n '/série de quadros/,$p' | head

# controle positivo (cópia; o original nunca é aberto para escrita)
for k in m1 m2 m3a m3b m4 m10; do python3 bench/journey.py --run bench/run/20261014T173601Z --inject $k --out /tmp/inj-$k; done
python3 bench/journey.py --journey /tmp/fm-journey-20261016T075109Z --inject m5  --out /tmp/inj-m5
python3 bench/journey.py --journey /tmp/fm-journey-20261016T075109Z --inject m5b --out /tmp/inj-m5b
for k in m7 m7a; do python3 bench/journey.py --run bench/run/20261014T214403Z --inject $k --out /tmp/inj-$k; done

# nada congelado foi tocado (as duas saídas têm de ser vazias)
git diff --stat 78a37428..HEAD -- bench/oracle.py bench/EVALUATOR.sha256 bench/MANIFEST.sha256 bench/corpus
git status --porcelain -- bench/oracle.py bench/EVALUATOR.sha256 bench/MANIFEST.sha256 bench/corpus
```

Os caminhos acima são `bench/journey.py` porque foi assim que a versão desta seção foi medida. No recorte o
arquivo é `instruments/journey/journey.py`; os insumos de `bench/run/` e a jornada de `/tmp` **não estão nesta
máquina hoje** (as corridas são `gitignored`), então a §11 mede os quatro códigos de saída em insumos sintéticos
mínimos, com o comando que qualquer revisor reproduz.

**Ambiente:** macOS 25.3.0 (Darwin, arm64) · Python 3.12.13 · `df -h /` = 1,8 GB livres na medição · nenhum
`swift build`, nenhum `xcodebuild`, nenhum simulador, nenhuma rede.

---

## 10. Conferência do ORCH, independente do agente que escreveu o instrumento

Comando, na worktree `instruments/journey-measurements` (base `78a37428`), apontando para uma corrida real do
diretório canônico (gitignored, lido só em leitura):

```sh
python3 instruments/journey/journey.py --run /Users/wagnermontes/Documents/GitHub/feedmine_v2/bench/run/20261014T214403Z
```

(medido quando o arquivo ainda era `bench/journey.py`; o caminho acima é o do recorte)

Saída (trecho bruto):

```
[M1] A abertura entrega conteúdo na mesma geração                  veredito: PASS
[M2] A primeira tela tem história                                  veredito: PASS
[M3] Rolar atinge carta que existe e para frente é para frente     veredito: PASS
[M4] Rolar com trabalho de fundo não move o que está acima da âncora veredito: PASS
[M5] As imagens aparecem (o que o asset local prova, o que não prova) veredito: NOT_RUN
[M7] A âncora que eu reabro é a âncora que o app gravou            veredito: PASS
[M10] Rolar rápido: a série de quadros, relatada                   veredito: PASS
[M1/M6 (superfície)] O vazio e o fim declarados pela superfície    veredito: NOT_RUN
  falta: `preparation=done` não é fim de feed (`AppComposition.swift:2363-2366`; o host ainda agenda nova
  tentativa em `:2507-2535`)
[M8] Sem rede                                                      veredito: NOT_RUN
  falta: o app lê `FEEDMINE_BLOCK_RSS_NETWORK` e não grava evento, nem grava que a carta salva abriu
[M12] p50/p95 de lançamento → primeira carta                       veredito: NOT_RUN
  falta: o instante do lançamento não é gravado; um percentil exige ≥30 execuções
```

Duas corridas recentes (`20261014T225053Z`, `20261014T214843Z`) devolveram `NOT_RUN` em **todas** as medições por não
terem traço utilizável — o instrumento não converteu ausência de insumo em silêncio verde.

O que esta conferência prova: que o instrumento roda num insumo real do `bench/run` e devolve veredito binário com o
número cru ao lado, e que onde o traço não contém o fato ele diz `NOT_RUN` com a linha do código que deveria gravá-lo,
em vez de escolher um limiar. O que **não** prova: fluidez, desempenho ou aprovação de release — nenhuma cláusula
aqui é limiar de qualidade de experiência, e as medições de quadro são relatadas como série, sem teto.

`shasum -a 256 -c instruments/journey/journey.sha256` (do diretório do repo) → `instruments/journey/journey.py: OK`.

---

## 11. Recorte aprovado — localização e saída em quatro códigos (2026-10-16)

O veredito do arquiteto aprovou o instrumento **como diagnóstico** e pediu dois ajustes antes da integração: tirar
a ferramenta de `bench/` (que é a régua congelada) e não deixar o processo sair `0` quando existe cláusula
aplicável `NOT_RUN`. Esta seção é o registro do que foi feito, medido **por execução** — o artefato é
`instruments/journey/journey.py`, sha256 `4e4eff074fec7c3d9728aed17693d3c8b9feafb80caec52f99d070765d2bed8e`,
92.805 B, e o mesmo hash de `instruments/journey/journey.sha256`.

### 11.1 Localização: `instruments/journey/`, fora da régua

`git mv bench/journey.py instruments/journey/journey.py` e `git mv bench/journey.sha256
instruments/journey/journey.sha256` (o git registra as duas como renomeações, com o histórico preservado), e o
conteúdo do hash passou a apontar o caminho novo. `bench/` perdeu os dois arquivos **novos** do instrumento e não
teve nenhum dos arquivos congelados tocado — a §11.5 mostra o diff vazio.

Por que sair: `bench/` é a referência congelada (B01–B06, `oracle.py`, `EVALUATOR.sha256`, `MANIFEST.sha256`,
`manifest.json`, `revisions/`), e uma ferramenta nova e evolutiva morando ali dentro pareceria ter autoridade
sobre ela. O instrumento não lê nada de `bench/` para decidir e não escreve nada lá: é diagnóstico auxiliar.

### 11.2 Saída de quatro vias

| Resultado do instrumento | Código |
|---|---:|
| Toda cláusula **aplicável** medida e `PASS` | `0` |
| Pelo menos uma cláusula `FAIL` | `1` |
| Erro de entrada ou execução | `2` |
| Sem `FAIL`, mas com cláusula **aplicável** `NOT_RUN` | `3` |

Antes do recorte o código era binário: `1` se houvesse `FAIL`, `0` em todo o resto — inclusive num insumo sem
artefato nenhum, em que todas as cláusulas ficam `NOT_RUN`. Uma automação que só olhasse o código lia medição
incompleta (ou insumo quebrado) como sucesso. Era exatamente o risco apontado.

**O que "aplicável" quer dizer aqui.** Não é sinônimo de "todo `NOT_RUN`": é uma decisão do modelo de cláusula
deste instrumento, e ela está **no código**, não no julgamento de quem lê. Cada sub-fato não medido carrega um
`motivo` de vocabulário fechado, e os motivos são de duas famílias:

| Motivo | Quando aparece | Família |
|---|---|---|
| `sem_sujeito` | o insumo não tem o que medir: sem janela atribuída a uma geração, sem carta publicada, sem avanço, sem dois avanços comparáveis na mesma geração, sem série de quadros, sem linha durável, sem checkpoint relatado | **fora de escopo** — não força `3` |
| `nao_implementado` | nenhuma fonte de evidência existe, por desenho: só o fato visual de M5 hoje (pixel decodificado) | **fora de escopo** — não força `3` |
| `evidencia_incompleta` | o sujeito existe, mas o traço anuncia perdas (`trace_truncated`) ou tem linha ilegível: zero violação não prova nada (contrato 2) | **lacuna** — força `3` |
| `nao_resolvido` | o sujeito existe, mas alguma âncora não se resolve na ordem do leitor da edição | **lacuna** — força `3` |
| `nao_identificado` | o sujeito existe e o registro é ambíguo: 0 linhas duráveis para a edição medida (com linhas de outras edições) ou ≥2 linhas na mesma edição; ou a linha de sessão existe mas não há com o que compará-la | **lacuna** — força `3` |
| `nao_comparavel` | o sujeito existe e os dois registros não são do mesmo instante: a linha durável é mais nova que o último evento do traço, falta metade do par, ou o instante durável não é numérico | **lacuna** — força `3` |

O veredito agregado **impresso** continua sendo o do contrato 3 (`FAIL` > qualquer sub-fato não medido >
`PASS`, como em `bench/oracle.py:624-631`), sem enfraquecer nada: M5 continua imprimindo `NOT_RUN` pela metade
visual. O que mudou é que o `NOT_RUN` passou a **dizer de que família é**, e o código de saída lê a família:

```
    [NOT_RUN: lacuna de medição — evidencia_incompleta] empty_then_content == 0 — esperado: 0, observado: 0
    [NOT_RUN: fora de escopo — nao_implementado] a imagem foi desenhada (pixel decodificado) — precisa de tela…
  cláusula: aplicável, com lacuna de medição: evidencia_incompleta      # força 3
  cláusula: aplicável e medida; fora de escopo: nao_implementado        # não força 3
  cláusula: não aplicável neste insumo: sem_sujeito                     # não força 3
```

**O caso M5, explicitamente.** M5 tem dois sub-fatos: (a) carta da janela com mídia declarada e sem asset local
— medível, e é a cláusula de verdade; (b) o pixel desenhado — **nunca** medível, por desenho. Se (b) contasse
como lacuna, todo insumo com mídia na janela sairia `3` para sempre e o código deixaria de distinguir medição
completa de incompleta — precisamente o que a automação precisa ler. Por isso `nao_implementado` é escopo, e não
lacuna; o que **não** acontece é (b) sumir: ele continua impresso, com o motivo ao lado, e continua na lista
explícita da §6 — sem virar `PASS` e sem virar aprovação global (§6.1).

O JSON carrega a mesma decisão para a automação: por insumo `codigo_de_saida` e `razao_do_codigo`; por medição
`veredito`, `aplicavel`, `lacunas`, `fora_de_escopo`; por sub-fato `pass` e `motivo`.

### 11.3 Erro de entrada deixou de se confundir com medição

Antes, três caminhos silenciosos convergiam para o mesmo `0`: diretório sem artefato nenhum, banco que não abre
ou não tem o esquema, e injeção impossível. Agora os três imprimem `ERRO DE ENTRADA` (ou `ERRO DE EXECUÇÃO`) no
stderr e devolvem `2`, **sem veredito de cláusula** — o código `2` não afirma nada sobre o produto:

| Situação | Antes | Agora |
|---|---|---|
| diretório inexistente | `2` (já estava certo) | `2`, `ERRO DE ENTRADA: <dir> não é um diretório: insumo inexistente` |
| insumo sem `trace.jsonl`, sem `runtime.sqlite` e sem `console.log` | **`0`** com todas as cláusulas `NOT_RUN` | `2`, `ERRO DE ENTRADA: … nenhum artefato …` |
| `runtime.sqlite` que não é banco, ou sem `published_cards`/`feed_segments` | **`0`** com `cartas: 0` (a leitura devolvia lista vazia) | `2`, `ERRO DE ENTRADA: SQLite ilegível ou sem o esquema do leitor …` |
| tabela `context_checkpoints`/`session_checkpoint` ausente | `M7` sem sujeito | igual: esquema antigo não é banco quebrado |
| argumentos inválidos (`--out` sem `--inject`, nada a medir) | `2` | `2` (o mesmo caminho do `argparse`) |
| injeção impossível no insumo (`REFUSED: …`) | **`1`** (parecia falha medida) | `2`, `ERRO DE ENTRADA: REFUSED: …` |
| arquivo de traço/console ilegível, e qualquer exceção de execução | traceback → `1` | `2`, `ERRO DE EXECUÇÃO: <tipo>: <mensagem>` |

A tabela explica o caso já registrado na §10: duas corridas do `bench` "sem traço utilizável" imprimiam todas as
cláusulas `NOT_RUN` (nada de silêncio verde no veredito) mas o processo saía `0`. Agora elas saem `2` — o
veredito continua sendo que não há medição, e o código passou a dizer a mesma coisa.

A única mudança de comportamento dentro de uma cláusula: `context_checkpoints.updated_at` com valor não numérico
(texto) passa a ser `nao_comparavel` (lacuna → `3`) em vez de derrubar a medição com `TypeError`. No app o campo
é numérico; a guarda existe para que um banco estranho não vire "falha medida".

### 11.4 Controles positivos: quatro códigos + as dez injeções, por execução

Os controles agora são **dois grupos**, e os dois rodam **o próprio processo** (um `subprocess` por caminho) e
conferem o código de saída observado *e* a linha que o justifica. Como as corridas de `bench/run/` não estão
nesta máquina (são `gitignored`), os insumos de medição são **sintéticos e mínimos** — traço de 7 a 9 eventos e
banco de 5 cartas, com as colunas que as injeções tocam — montados pelo próprio instrumento, com a receita da
§5.11 e agora escrita dentro do arquivo. Nenhum insumo sintético é apresentação de produto: eles existem para
exercitar caminho de código.

```sh
# 1) monta os insumos dos controles (ficam; nenhum é medição de produto)
python3 instruments/journey/journey.py --fixtures /tmp/fmc

# 2) os quatro caminhos, um comando por caminho
python3 instruments/journey/journey.py --run /tmp/fmc/completo                                  # 0
python3 instruments/journey/journey.py --run /tmp/fmc/fora-de-escopo                            # 0 (fora de escopo ≠ 3)
python3 instruments/journey/journey.py --run /tmp/fmc/completo --inject m2 --out /tmp/fmc/copia-m2   # 1
python3 instruments/journey/journey.py --run /tmp/fmc/nao-existe                                # 2
python3 instruments/journey/journey.py --journey /tmp/fmc/vazio                                 # 2
python3 instruments/journey/journey.py --run /tmp/fmc/sqlite-ilegivel                           # 2
python3 instruments/journey/journey.py --run /tmp/fmc/completo --out /tmp/fmc/sem-inject        # 2
python3 instruments/journey/journey.py --run /tmp/fmc/lacuna                                    # 3

# 3) o controle inteiro, com os 18 casos e o código de cada um
python3 instruments/journey/journey.py --selftest
```

Saída bruta dos oito comandos do passo 2 (exit code e linha do veredito, verbatim; o `--run completo` e o
`--run lacuna` também imprimem as sete cláusulas, cortadas aqui):

```text
$ python3 instruments/journey/journey.py --run /tmp/fmc/completo                                     # exit=0
veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=PASS, M2=PASS, M3=PASS, M4=PASS, M5=NOT_RUN, M7=PASS, M10=PASS)
código de saída do insumo: 0 — todas as cláusulas aplicáveis medidas e PASS; fora de escopo neste insumo: M5 (nao_implementado)
código de saída do processo: 0 — /tmp/fmc/completo: todas as cláusulas aplicáveis medidas e PASS; fora de escopo neste insumo: M5 (nao_implementado)

$ python3 instruments/journey/journey.py --run /tmp/fmc/fora-de-escopo                               # exit=0
veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=PASS, M2=PASS, M3=NOT_RUN, M4=PASS, M5=NOT_RUN, M7=NOT_RUN, M10=NOT_RUN)
código de saída do insumo: 0 — todas as cláusulas aplicáveis medidas e PASS; fora de escopo neste insumo: M3 (sem_sujeito); M5 (nao_implementado, sem_sujeito); M7 (sem_sujeito); M10 (sem_sujeito)
código de saída do processo: 0 — /tmp/fmc/fora-de-escopo: todas as cláusulas aplicáveis medidas e PASS; fora de escopo neste insumo: M3 (sem_sujeito); M5 (nao_implementado, sem_sujeito); M7 (sem_sujeito); M10 (sem_sujeito)

$ python3 instruments/journey/journey.py --run /tmp/fmc/completo --inject m2 --out /tmp/fmc/copia-m2   # exit=1
veredito do insumo (sem substituir gate nenhum): FAIL (M1=PASS, M2=FAIL, M3=PASS, M4=PASS, M5=NOT_RUN, M7=PASS, M10=PASS)
código de saída do insumo: 1 — cláusula FAIL: M2
código de saída do processo: 1 — /tmp/fmc/copia-m2: cláusula FAIL: M2

$ python3 instruments/journey/journey.py --run /tmp/fmc/nao-existe                                   # exit=2
ERRO DE ENTRADA: /tmp/fmc/nao-existe não é um diretório: insumo inexistente

$ python3 instruments/journey/journey.py --journey /tmp/fmc/vazio                                    # exit=2
ERRO DE ENTRADA: /tmp/fmc/vazio: nenhum artefato — sem `trace.jsonl`, sem `runtime.sqlite` e sem `console.log`. Insumo ausente ou vazio: erro de entrada, não medição vazia (código 2, não 0)

$ python3 instruments/journey/journey.py --run /tmp/fmc/sqlite-ilegivel                              # exit=2
ERRO DE ENTRADA: SQLite ilegível ou sem o esquema do leitor (`published_cards`/`feed_segments`): /tmp/fmc/sqlite-ilegivel/runtime.sqlite (file is not a database)

$ python3 instruments/journey/journey.py --run /tmp/fmc/completo --out /tmp/fmc/sem-inject           # exit=2
journey.py: error: --out só faz sentido com --inject

$ python3 instruments/journey/journey.py --run /tmp/fmc/lacuna                                       # exit=3
veredito do insumo (sem substituir gate nenhum): NOT_RUN (M1=NOT_RUN, M2=PASS, M3=NOT_RUN, M4=NOT_RUN, M5=NOT_RUN, M7=NOT_RUN, M10=PASS)
código de saída do insumo: 3 — sem FAIL, mas cláusula aplicável não medida: M1 (evidencia_incompleta); M3 (evidencia_incompleta); M4 (evidencia_incompleta); M7 (evidencia_incompleta)
código de saída do processo: 3 — /tmp/fmc/lacuna: sem FAIL, mas cláusula aplicável não medida: M1 (evidencia_incompleta); M3 (evidencia_incompleta); M4 (evidencia_incompleta); M7 (evidencia_incompleta)
```

Qual caminho cada controle exercita:

| Controle | Caminho exercitado | Código |
|---|---|---|
| `passe-limpo` (`--run completo`) | `0` — M1/M2/M3/M4/M5(a)/M7/M10 medidos (`M5` metade (`b`) é `nao_implementado`) | `0` |
| `fora-de-escopo` (`--run fora-de-escopo`) | `0` com M3/M5/M7/M10 `sem_sujeito`: prova que "não aplicável" **não** vira `3` | `0` |
| `falha` (`--inject m2`) | `1` — uma cláusula `FAIL` (M2), sem nenhum outro `FAIL` na saída | `1` |
| `injeção m1/m2/m3a/m3b/m4/m5/m7/m7a` | `1` cada: as oito injeções que medem violação continuam virando exatamente **um** `FAIL` na cláusula alvo | `1` |
| `injeção m5b/m10` | `0` cada: continuam sem mudar veredito (número cru e guarda de vacuidade) | `0` |
| `entrada-inexistente` | `2` — insumo que não existe | `2` |
| `entrada-sem-artefato` | `2` — diretório vazio (antes saía `0`) | `2` |
| `entrada-sqlite-ilegivel` | `2` — `runtime.sqlite` que não é banco (antes saía `0`) | `2` |
| `entrada-argumentos` | `2` — argumento inválido | `2` |
| `lacuna` (`--run lacuna`: o insumo completo + `trace_truncated` de 2 eventos perdidos) | `3` — nenhum `FAIL`, quatro cláusulas com lacuna `evidencia_incompleta` | `3` |

Resumo da execução de `--selftest` (18 controles, um processo por controle; a saída completa tem a linha e o
comando de cada um):

```text
caminho 0: 4/4 controles OK — passe-limpo, fora-de-escopo, injeção m5b, injeção m10
caminho 1: 9/9 controles OK — falha, injeção m1, injeção m2, injeção m3a, injeção m3b, injeção m4, injeção m5, injeção m7, injeção m7a
caminho 2: 4/4 controles OK — entrada-sqlite-ilegivel, entrada-sem-artefato, entrada-inexistente, entrada-argumentos
caminho 3: 1/1 controles OK — lacuna
controles: todos OK          # exit=0
```

`--selftest` sai `0` quando os controles valem, `1` quando algum quebrou e `2` quando não conseguiu montar os
insumos — contrato próprio do modo, separado do contrato de medição: nenhum dos quatro códigos de medição
depende dele.

### 11.5 Integridade do congelado e integração

No commit do recorte, `git diff --numstat` contra o pai nas dez referências congeladas
(`bench/oracle.py`, `bench/run.sh`, `bench/serve.py`, `bench/build_corpus.py`, `bench/EVALUATOR.sha256`,
`bench/MANIFEST.sha256`, `bench/manifest.json`, `bench/expand.py`, `bench/transport_variant.py`,
`bench/README.md`, `bench/REFERENCE.md`, `bench/revisions/`) é **vazio**, e `git diff --name-status` lista
apenas as duas renomeações e este relatório. A branch pronta para integrar, criada **da `main`** com um único
commit, tem exatamente três arquivos: `instruments/journey/journey.py`, `instruments/journey/journey.sha256` e
este relatório — de modo que a `main` pode avançar por fast-forward.

### 11.6 O que o recorte **não** mudou

- O modelo de cláusula e os três contratos de evidência: `verdict_of` continua `FAIL` > `NOT_RUN` > `PASS`, e
  qualquer sub-fato não medido continua contaminando o agregado.
- As sete medições (M1, M2, M3, M4, M5, M7, M10), seus fatos, números crus, notas e o que cada uma lê.
- A lista de cláusulas explicitamente não implementadas (`NOT_RUN_MEASUREMENTS`), que continua impressa e
  identificada como não implementada (§6.1), e as dez injeções, cujo alvo e veredito continuam os mesmos
  (§11.4).
- O que o relatório já registrava como não provado: nada de build novo, M5 mede asset e não pixel, M7 mede a
  identidade durável e não o pouso, M10 não tem limiar por desenho.

