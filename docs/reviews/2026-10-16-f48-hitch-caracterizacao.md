# Os engasgos da candidata 48 no iPhone: o instrumento de correlação por segundo, o que a evidência disponível sustenta e o que ainda NÃO sustenta

Data: 2026-10-16 · Frente: caracterização dos engasgos (medição; **nenhuma** correção foi implementada)
Árvore: `/tmp/fm-hitch`, branch `gate/f48-hitch`, base **`release/1.0-build.48` = `03d05f5f`**
Aparelho: iPhone 14 Plus, `devicectl` id `BBA4F656-A5EA-5D81-934E-E484ED71B8E2`, UDID `00008110-00067D861486201E`
Bundle sob teste: `com.feedmine.development` (Debug). **`com.feedmine.app` (TestFlight do dono) nunca é instalado,
lançado, terminado nem desinstalado por este trabalho** — prova mecânica na §7.
Estado da corrida no aparelho: **ARMADA e não executada** — o dono está instalando/validando a build 48 de TestFlight
e uma corrida instala o bundle de desenvolvimento e toma o primeiro plano dele. Falta o GO (§8).

---

## 0. O que está entregue, e o que espera o GO

| Entrega | Estado |
|---|---|
| `scripts/hitch-join.py` — junção por segundo (quadros × jornada × traço) | **ENTREGUE** e executada sobre duas capturas reais (§3, §4) |
| `scripts/hitch-pass.sh` — corrida física com o console **persistido em arquivo** | **ENTREGUE**; `bash -n` ok; recusas e auditoria provadas por execução (§2.1, §7) |
| Build Debug iphoneos do candidato, armado para o GO | **EXECUTADO** (§8) |
| Corrida no aparelho (fases A e B do `hitch-pass.sh`) | **NOT_RUN** — espera GO (dono usando o aparelho) |
| Relatório com as cinco dimensões por evento severo | **PARCIAL**: dimensão (a) para as 19 janelas severas da captura de hoje; (b)-(e) `NOT_AVAILABLE` com o arquivo que falta, item por item (§3) — e as cinco completas na captura que as suporta (§4) |
| Correção de qualquer espécie | **NENHUMA** (esta frente é medição) |

---

## 1. Base: `release/1.0-build.48` (`03d05f5f`), não `main` — com a prova

A missão manda reusar `scripts/device-journey.sh` e o leitor `bench/journey.py`, e rodar a jornada
`-only-testing:FeedMineUITests/FluidityJourneyUITests`. Nenhum dos três **existe em `main`**:

```console
$ git grep -n "FeedJourneyConsole\|FEEDMINE_JOURNEY_CONSOLE\|feedmine journey" main -- '*.swift'
(vazio)
$ git ls-tree -r --name-only main -- scripts/device-journey.sh FeedMineApp/FeedMineAppTests/FluidityJourneyUITests.swift
(vazio)
$ git diff --stat main integration/build-48 | tail -4
 .../FeedMineAppTests/FluidityJourneyUITests.swift  |  62 +++
 scripts/device-journey.sh                          | 553 +++++++++++++++++++++
 29 files changed, 2523 insertions(+), 545 deletions(-)
$ git merge-base main integration/build-48
78a37428 docs(review): livro-razão das branches — o que eu verifiquei, o que ficou em WIP e as armadilhas de integração
```

`main` (`1bebf3bf`) é `78a37428` **mais um único commit documental**; o código da candidata 48 está na linha
`release/1.0-build.48` → `integration/build-48`, e o próprio relatório do arquiteto em
`main:docs/reviews/2026-10-16-build-48-aparelho-e-publicacao.md` §1 diz "**Código sob teste: `03d05f5f`** (a mesma
revisão do archive)". A árvore desta frente é a árvore medida: `/tmp/fm-hitch`, branch própria `gate/f48-hitch`, a
partir de `release/1.0-build.48` (`03d05f5f`). Confirmado por mensagem do arquiteto durante o trabalho; **sem
rebase**.

---

## 2. Os dois instrumentos

### 2.1 `scripts/hitch-pass.sh` — a corrida que persiste o console

O que a corrida de 2026-10-16 perdeu, medido:

```console
$ python3 -c "data=open('/tmp/int48-physical-authorized.log',errors='replace').read(); print('bytes',len(data)); \
print('feedmine frames=',data.count('feedmine frames=')); print('feedmine journey',data.count('feedmine journey'))"
bytes 725786
feedmine frames= 0
feedmine journey 0
```

725.786 bytes de `xcodebuild test` no aparelho e **zero** linhas do app. A distinção é aparelho × simulador, e ela
está medida nos dois lados: no **simulador**, a saída do app sob teste entra no log do `xcodebuild` —
`docs/reviews/evidence/2026-10-15-aplicacao-dos-relatorios/integrated-tree-app-tests.log` tem **11.350** linhas
`feedmine frames=` e o comando que o produziu é `-destination "platform=iOS Simulator,id=…"` (190 ocorrências de
"Simulator", nenhuma de "iPhone 14 Plus"); no **aparelho**, 0 linhas. E a tentativa por `devicectl --console` não foi
guardada em arquivo (`…-build-48-aparelho-e-publicacao.md` §3). Sem console não há série por segundo nem linha de
jornada, e sem isso "o que estava acontecendo no segundo do travamento" não existe.

O pass faz, em ordem: pré-voo (recusa `com.feedmine.app`, exige ≥2 GB livres, exige `--out` novo) → **build** Debug
`iphoneos` do candidato → **fase A** reusando `scripts/device-journey.sh` (instala, lança com
`FEEDMINE_JOURNEY_CONSOLE=1` + `FEEDMINE_TRACE_CAPTURE=1` e `--console`, persiste `console.log`, puxa o contêiner,
dobra o WAL, imprime o censo) → **fase B** a jornada de rolagem por `xcodebuild test` com o log inteiro em
`journey-test.log`, o result bundle em `journey.xcresult` e o **syslog do aparelho** capturado durante a corrida em
`console-journey.log` (mais o derivado `console-journey-feedmine.log`) → **contêiner inteiro** de todos os
namespaces → prova de que `com.feedmine.app` ficou como estava (container antes = container depois) → imprime cada
bruto e o comando de junção.

Três decisões que não são óbvias e que vieram de medição:

1. **Duas capturas de console, não uma.** O app fala por duas vias: `NSLog` (`feedmine frames=`, `feedmine journey`,
   `FeedMineApp/FeedMineApp/FeedFrameMeter.swift:150,153`) e `Logger(subsystem:category:)`
   (`FeedMineApp/FeedMineApp/AppComposition.swift:32,2879`, com o texto `[composition] …`). O `devicectl --console`
   carrega a primeira e **não** a segunda (medido: 605 linhas de console na jornada de 2026-10-16, nenhuma
   `[composition]`); o `idevicesyslog` carrega as duas. Por isso a fase B captura o syslog do sistema, sem filtro
   (o filtro é aplicado depois, no arquivo derivado, para o bruto ficar bruto).
2. **A variável tem de ser provada aplicada, não declarada.** O pass procura `feedmine journey` no console
   persistido e, quando não acha, grava a causa exata medida com a lista de causas verificáveis (o runner de teste
   não propaga a chave ao app; `idevicesyslog` ausente; app errado) — em vez de reportar medição sem sujeito. A
   fase B ainda tenta `TEST_RUNNER_FEEDMINE_JOURNEY_CONSOLE=1`, mas o resultado **não é presumido**.
3. **`--build-only`**: compila e sai sem executar **nenhum** comando de aparelho. É o modo com que esta frente deixou
   a corrida armada sem tocar no telefone do dono (§8).

Um defeito do próprio pass foi encontrado e corrigido **exercitando o bloco de censo do contêiner sobre uma cópia de
um contêiner real** (não no aparelho): o SQLite apaga o `-wal` quando a última conexão fecha, e o
`os.path.getsize(wal)` depois do `close()` estourou `FileNotFoundError` e derrubou o censo inteiro — o tamanho agora
é lido **antes** do checkpoint, e o resultado fica explícito. Medido:

```console
$ python3 <bloco de censo de hitch-pass.sh> /tmp/hitch-census-test
namespaces no contêiner copiado:
  394FA0C4-89E8-47BF-8874-FE30EDAB9937: wal 0 B → removido pelo SQLite ao fechar a conexão
    runtime.sqlite=425984 B  trace.jsonl=384 linhas  mtime_runtime=1792168099
exit=0
```

O mesmo idioma existe em `scripts/device-journey.sh:397-402` (`wc -c <"$DB-wal"` **depois** do checkpoint, sob
`set -euo pipefail`): se o SQLite remover o `-wal` ao fechar — foi o que aconteceu na cópia que eu testei —, aquele
`wc` falha e o script sai no meio do censo, **depois** de já ter escrito o console (o dano é um `NOT_RUN` espúrio da
fase A, não a perda da medida). Nas corridas de 2026-10-16 isso **não** foi observado (o script imprimiu
`TRUNCATE em 0 bytes`). O arquivo é de outro dono e **não foi editado**: fica registrado aqui e no resultado desta
frente para handoff.

Uso (GO):

```sh
scripts/hitch-pass.sh --skip-build --app /tmp/fm-hitch-pre/Build/Products/Debug-iphoneos/FeedMine.app \
  --derived-data /tmp/fm-hitch-pre/derived --out /tmp/fm-hitch-pass-<UTC>
```

### 2.2 `scripts/hitch-join.py` — a junção por segundo

Para cada segundo: (a) intervalo monotônico e duração do quadro; (b) posição e movimento do leitor; (c) estado da
janela admitida; (d) trabalho de aquisição/publicação/mídia; (e) pressão do sistema quando a captura a carrega —
cada linha com o `arquivo:linha` de origem.

Três contratos que ele impõe, todos por medição e não por escrúpulo:

1. **A chave é o ordinal do app, e o relógio é conferência.** O console diz a hora local do aparelho sem fuso
   (`2026-10-16 00:51:12.355` contra `at=2026-10-16T07:51:12Z` no traço: 7 h de diferença, o fuso do aparelho). Uma
   junção por relógio dependeria de uma suposição de fuso; o ordinal (`t=` da linha de jornada, `seconds=` da série,
   índice do k-ésimo evento `frames`) sai do **mesmo tique** do `FeedFrameMeter` e não depende de fuso. O join
   imprime o ordinal, o `mono`, o `at` e o carimbo verbatim de cada janela, e reporta o desvio relógio×ordinal como
   teste — não como chave.
2. **O alinhamento entre insumos é conferido campo a campo, não presumido.** Console (299 linhas `feedmine frames=`)
   e traço (260 eventos `frames`) discordam de contagem na jornada de 2026-10-16; o join compara
   `frames/late/bad/severe/worst_ms` dos segundos que os dois têm em comum e só anexa os relógios se **todos**
   concordarem (concordaram nos 260). Discordância recusa o alinhamento em vez de deslocar a série.

   ```console
   $ python3 scripts/hitch-join.py --journey /tmp/fm-journey-20261016T075109Z --select severe
   nota: alinhamento console × traço CONFERIDO campo a campo em 260 segundos (frames/late/bad/severe/worst_ms
         concordam; o relógio do traço entra pela posição, não por suposição)
   nota: o traço cobre os primeiros 260 de 299 segundos: as janelas 261..299 existem no console e não no traço
         (último lote perdido no encerramento, ou traço truncado — ver `trace_truncated` no próprio traço)
   ```

3. **Sem sujeito é `NOT_AVAILABLE` com o nome do arquivo que falta** — nunca um valor derivado de outro campo
   parecido. E o que não é por segundo (o banco, a mídia no disco) fica de fora, rotulado.

Relação com `bench/journey.py` (`instruments/journey-measurements`, `870634c3`): aquele é o instrumento de
**vereditos binários** sobre um insumo inteiro (M4 "rolar com trabalho de fundo" em `bench/journey.py:486`, M10 "a
série de quadros, relatada" em `:650`). O join não repete M4/M10 nem emite veredito: responde *o que estava em curso
no segundo em que o quadro travou* e imprime as linhas cruas. Onde os dois olham o mesmo fato, o número é o mesmo
porque a fonte é a mesma.

---

## 3. A captura de hoje (`/tmp/int48-physical-evidence/`) — o que ela sustenta

A corrida de hoje deixou **um** arquivo de medida: o anexo do XCTest com a série que o próprio app publicou
(`FluidityJourneyUITests` lê o rótulo `feed-frame-proof`, `FeedMineApp/FeedMineAppTests/FluidityJourneyUITests.swift:30,44`).

```console
$ python3 scripts/hitch-join.py --journey /tmp/int48-physical-evidence --select severe
insumo: /tmp/int48-physical-evidence
proveniência:
  série publicada: /tmp/int48-physical-evidence/62CB9727-697D-4E49-9FE1-1AADCB3CBFBD.txt
      sha256=39c4fd95eae06dccc10c0174a4c9ef0396a49acdf3ef30bd4cc6ab8c5571a1fb
  nota: eixo dos segundos: série publicada (27 janelas)
  FALTA: série de quadros no console (`feedmine frames=`): nenhum arquivo de console com essa linha em /tmp/int48-physical-evidence
  FALTA: fatos da jornada (`feedmine journey`): nenhuma linha — a captura não ligou `FEEDMINE_JOURNEY_CONSOLE=1`, ou o console desta corrida não foi persistido
  FALTA: traço do app (`trace.jsonl`): não está em /tmp/int48-physical-evidence — sem ele não há posição do leitor nem trabalho de fundo por segundo
  FALTA: banco (`runtime.sqlite`): não está em /tmp/int48-physical-evidence — as âncoras saem como UUID cru

totais da série: janelas=27 quadros=1208 late=17 bad=61 severe=75 pior_ms=277.2
segundos com pelo menos um quadro: late=10 bad=20 severe=19  (seleção: `--select severe` = o balde do próprio
medidor; nenhum limiar foi escolhido aqui)
```

### 3.1 Dimensão (a) — intervalo e duração do quadro, para as 19 janelas severas

O que o anexo permite, sem inventar nada: o **ordinal** da janela e o pior quadro dela. O intervalo monotônico
`mono` não existe nesta captura (não há traço), e o join diz isso na linha, por janela.

| janela | frames/late/bad/severe/worst_ms | leitura |
|---|---|---|
| 1 | 49/0/0/**3**/128.5 | **antes de qualquer gesto** (a série `before=` foi lida com 6 janelas, antes dos 6 `swipeUp`) |
| 2 | 45/0/0/**2**/213.6 | idem |
| 7 | 50/0/1/**2**/276.0 | começo da série pós-gesto |
| 8 | 25/3/8/**7**/94.1 | janela longa com poucos quadros |
| 10 | 44/0/1/**2**/234.7 | |
| 11 | 23/1/8/**6**/143.1 | |
| 13 | 47/0/0/**3**/125.8 | |
| 14 | 26/0/3/**8**/127.8 | |
| 15 | 51/1/2/**2**/58.8 | |
| 16 | 44/0/1/**1**/252.0 | |
| 17 | 17/0/3/**10**/145.4 | 17 quadros em ≥1 s: ~10/16 intervalos acima de 3 orçamentos |
| 18 | 52/1/3/**1**/50.0 | |
| 19 | 45/0/1/**1**/236.4 | |
| 20 | 26/0/3/**9**/97.3 | |
| 21 | 51/0/2/**3**/52.0 | |
| 22 | 51/0/0/**1**/246.0 | |
| 23 | 28/0/1/**6**/277.2 | pior intervalo da corrida |
| 24 | 41/1/2/**5**/221.8 | |
| 25 | 44/1/1/**3**/243.3 | |

Números da série inteira: **1208 quadros, 153 fora do orçamento (17 late + 61 bad + 75 severe) = 12,7%**, pior
intervalo **277,2 ms**, 19 de 27 segundos com pelo menos um quadro severo, 9 segundos com pior quadro ≥ 200 ms.

Duas leituras que a série sozinha permite, com a linha de origem:

- **5 dos 75 quadros severos são anteriores a qualquer gesto.** O teste lê a série duas vezes — `before` depois de
  esperar a primeira publicação do medidor e **antes** dos 6 `swipeUp`
  (`FluidityJourneyUITests.swift:30-38`), e `after` depois (`:44`). O `after=` da corrida tem `seconds=27` e o
  `before=` tem `seconds=6`, então as janelas 1-6 foram medidas sem gesto nenhum: 5 severos (janelas 1 e 2, piores
  128,5 ms e 213,6 ms). O arranque desta candidata **não** é limpo.
- **O segundo do medidor é *pelo menos* um segundo**, e nos segundos severos sobra pouco: a janela fecha no primeiro
  quadro depois de 1 s decorrido (`FeedFrameMeter.swift:140`, `if now - windowStarted >= 1 { flush(at: now) }`), e os
  baldes são >3× orçamento = severo, >2× = bad, >1,5× = late (`:97-100`). Uma janela com 17 quadros e 10 severos é
  um intervalo ≥1 s em que a apresentação passou a maior parte do tempo parada — e não "um segundo com poucos
  quadros porque o app estava ocioso".

### 3.2 Dimensões (b) a (e) — o que falta, arquivo por arquivo

O join imprime, para cada janela severa, exatamente isto (recorte verbatim da janela 7, a de pior intervalo):

```
--- janela 7  severe=2
    · contexto #6: frames=57 late=2 bad=1 severe=0 worst_ms=39.7
    · contexto #8: frames=25 late=3 bad=8 severe=7 worst_ms=94.1
  (a) intervalo monotônico e duração do quadro
    quadro: frames=50 late=0 bad=1 severe=2 worst_ms=276.0 budget_ms=16.67  [62CB9727-….txt:4 (after=#7)]
    NOT_AVAILABLE: intervalo monotônico — esta captura não carrega o traço nem `mono`; o ordinal do app é a única chave
  (b) posição e movimento do leitor
    nenhum evento de posição do traço nesta janela (`advance`, `runway_completed`, `position_checkpoint`, `window`)
    NOT_AVAILABLE: falta o traço (`trace.jsonl`) — sem ele não há movimento do leitor atribuível a um segundo; o que
    existe é só a carta inicial/final da corrida
    da série publicada: initial_card=1AABE4AE-2F18-488A-B875-AB604632E2DF
    da série publicada: final_card=3FBA78EC-D7FB-4B4C-B120-EA4BC39E9215
  (c) estado da janela admitida
    NOT_AVAILABLE: falta o traço (`trace.jsonl`) — a janela admitida por segundo não é observável nesta captura
  (d) trabalho de aquisição, publicação e mídia no intervalo
    nenhum evento de trabalho do traço nesta janela
    NOT_AVAILABLE: falta o traço (`trace.jsonl`) — o trabalho de fundo por segundo não é observável nesta captura
    NOT_AVAILABLE: a linha `feedmine journey` não está nesta captura
  (e) pressão do sistema
    NOT_OBSERVED nesta janela (vocabulário procurado: malloc, memory warning, low memory, jetsam, highwater,
    thermal, watchdog, hang, stuck, no space, enospc, disk, signal, terminated due to, acquired tunnel, usage
    assertion, coredeviceerror, respring, spinlock)
    o que uma captura de console NÃO vê por si: memória sob pressão (jetsam/memorystatus), estado térmico e hang do
    watchdog só aparecem se o syslog do sistema tiver sido capturado durante a jornada — `scripts/hitch-pass.sh` faz
    isso quando `idevicesyslog` está disponível, e o arquivo `console-journey.log` é a captura; `worst_ms` acima do
    orçamento é a única medida direta de atraso desta janela
```

O que falta, nomeado:

| Dimensão | Arquivo que falta | Por que ele faltou |
|---|---|---|
| (a) intervalo `mono` | o `trace.jsonl` do namespace do teste | a corrida não puxou o contêiner de `com.feedmine.development` depois do teste |
| (b) movimento do leitor | `trace.jsonl` (`advance`, `runway_completed`, `position_checkpoint`) e/ou `console-journey.log` (`viewport forwarded …`) | idem; e a fase B do pass ainda não rodou |
| (c) janela admitida | `trace.jsonl` (`admitted`, `window`) | idem |
| (d) trabalho de fundo | `trace.jsonl` (`candidate`/`suspended`, `media_ready`, `replenishment_*`) e `feedmine journey` | idem, e a captura de hoje não ligou `FEEDMINE_JOURNEY_CONSOLE=1` em lugar nenhum |
| (e) pressão do sistema | syslog do aparelho (`idevicesyslog`/`log collect`) durante a jornada | nunca foi capturado |

Os anexos de hoje **têm** `initial_card` e `final_card` (1AABE4AE… → 3FBA78EC…, distintos): a rolagem aconteceu e o
ponto de leitura mudou — o que a corrida de hoje **não** deixou foi o caminho entre os dois.

Uma reconciliação que importa para o desenho da corrida: os números citados na missão ("1 a 10 quadros severos por
segundo, pior intervalo 221–277 ms") são **esta** série, medida por `FluidityJourneyUITests` no bundle de
desenvolvimento — não pelo dono rolando a build 48 do TestFlight. A observação de consumo real do dono **não existe
como medida**.

---

## 4. O que o instrumento produz quando a captura está completa

Insumo: a jornada de aparelho de 2026-10-16, que é a única captura disponível com console **e** traço **e** banco
(`/tmp/fm-journey-20261016T075109Z`, do `scripts/device-journey.sh`).

```console
$ python3 scripts/hitch-join.py --journey /tmp/fm-journey-20261016T075109Z --select severe --context 1
proveniência:
  console: …/console.log                        sha256=5ee23079bacffdcf39229f0806e9cb4d9d9ceffb17deb762c9282c560b75fdea
  traço:   …/394FA0C4-…/trace.jsonl             sha256=861d2f97f52b763828b7101a5097899f6866884898848d7cae301244ae3c2091
  banco:   …/394FA0C4-…/runtime.sqlite          sha256=3e899fd624b5ef323af5bc42f5a4be1f3c79d7aab226d65da53074597e429fa8
      linhas `feedmine frames=`: 299   `feedmine journey`: 299   linhas de pressão: 5   outras: 2
      eventos: 384 admitted=6, candidate=42, frames=260, media_ready=64, position_checkpoint=1,
                   replenishment_arrived=4, replenishment_concluded=2, replenishment_requested=2, window=3
      cartas na ordem do leitor: 42
totais da série: janelas=299 quadros=17938 late=2 bad=0 severe=4 pior_ms=152.0
segundos com pelo menos um quadro: late=2 bad=0 severe=2
```

A janela 3 é a única com mais de um quadro severo, e o join entrega as cinco dimensões:

```
--- janela 3  severe=3
    · contexto #2: frames=57 late=1 bad=0 severe=1 worst_ms=55.1
    · contexto #4: frames=60 late=0 bad=0 severe=0 worst_ms=21.4
  (a) intervalo monotônico e duração do quadro
    quadro: frames=48 late=0 bad=0 severe=3 worst_ms=152.0 budget_ms=16.67  [console.log:11]
    carimbo do aparelho (verbatim): 2026-10-16 00:51:14.384
    intervalo: mono 107593.790 → 107594.818 (1.029 s)   at=2026-10-16T07:51:14Z
    pior intervalo do medidor: worst_at=107593.991 (mono do fim − worst_at = 0.827 s antes do fim da janela)
  (b) posição e movimento do leitor
    [trace.jsonl:40]  mono=107593.937 window … cards=1 resolved_sources=1
    [trace.jsonl:42]  mono=107594.004 position_checkpoint placement=top window_seconds=20 anchor=5B2EE11D-…
      ↳ âncora: pos 0 (seg 0, carta 0, BBC World)
    [trace.jsonl:126] mono=107594.818 window … cards=17 resolved_sources=17
    (nenhum evento `advance` em 299 s: **não houve rolagem nesta jornada**)
  (c) estado da janela admitida
    última admissão antes do fim da janela [trace.jsonl:125] cards=17 order=2
      ↳ head: pos 0 (seg 0, carta 0, BBC World)   ↳ tail: pos 16 (seg 1, carta 15, BBC World)
      ↳ anchor: pos 0 (seg 0, carta 0, BBC World)
  (d) trabalho de aquisição, publicação e mídia no intervalo
    contagem por evento: admitted=6, candidate=42, media_ready=64, replenishment_arrived=4,
                         replenishment_concluded=2, replenishment_requested=2
    [trace.jsonl:4..:100] 64 × media_ready revision=… (todos em mono=107593.840)
    [trace.jsonl:43]      replenishment_requested … kind=local coverage=pressured ready=exact required_cards=32
    [trace.jsonl:76]      replenishment_concluded … destination=segment_publication cards=20 ordinal=1
    [trace.jsonl:123]     replenishment_concluded … destination=segment_publication cards=21 ordinal=2
    [trace.jsonl:125]     admitted cards=17 sequence=A7E2E02B-… order=2
    linha de jornada desta janela, com o Δ contra a anterior:
      Δcards: 0 → 17 (+17)
      Δmedia_resident: 0 → 17 (+17)
      Δmedia_prepared: 31 → 64 (+33)
      Δmedia_settled: 31 → 64 (+33)
      Δsources_responded: 1 → 2 (+1)
    [console.log:12] t=2s cards=17 hero=0 thumb=17 text=0 media_resident=17 media_prepared=64 media_settled=64
                     sources_contacted=2 sources_responded=2 sources_unreachable=0 preparation=done install_rejects=0
  (e) pressão do sistema
    NOT_OBSERVED nesta janela (…)
```

Leitura do que está ali, sem esticar: **no único insumo em que é possível correlacionar, os quatro quadros severos
da jornada inteira estão nos dois primeiros segundos medidos** (janelas 2 e 3: 55,1 ms e 152,0 ms) e o segundo pior
é exatamente o segundo em que o app publicou dois segmentos (20 + 21 cartas), admitiu a janela de 17 cartas e
processou 64 `media_ready`. Nos **297 segundos restantes** não há um único quadro severo, e não há gesto nenhum
(nenhum evento `advance` em 299 s de `trace.jsonl`). Os 4 quadros severos são **2/299 = 0,7%** dos segundos e
**4/17938 = 0,02%** dos quadros.

---

## 5. Observação × causa: o que a correlação sustenta e o que ela não sustenta

### O que a evidência sustenta (observação)

1. **Existem engasgos medidos pelo próprio app na jornada dirigida**, com os números brutos da §3.1 (75 quadros
   severos em 19 segundos, 12,7% dos quadros fora do orçamento, pior 277,2 ms). Evidência: a série anexada, sha256
   `39c4fd95…`.
2. **5 dos 75 quadros severos são anteriores a qualquer gesto** — a própria estrutura do teste prova a fronteira
   (`before` lido antes dos 6 `swipeUp`). O arranque não é limpo.
3. **A condição da medição muda o resultado em duas ordens de grandeza.** Jornada dirigida: 75/1208 = **6,2%** de
   quadros severos. Uso normal (passagem de 2026-10-15, citada em
   `main:docs/reviews/2026-10-16-build-48-aparelho-e-publicacao.md` §2.2): 25/31479 = **0,08%**. Mesmo app, mesmo
   aparelho, condições diferentes. Isso é observação, não causa — e é a razão de a corrida do GO ter uma **fase A
   ociosa** e uma **fase B dirigida**, para que as duas condições existam na mesma corrida.
4. **Quando o app está ocioso depois de arrancar, ele não engasga**: 297 segundos sem um quadro severo na §4.
5. **Quando o app publica arrancando, ele engasga**: na §4 o único segundo com 3 severos é o da publicação de dois
   segmentos + admissão de 17 cartas + 64 `media_ready`.
6. **`worst_ms` mede o pior intervalo, e o medidor diz onde ele caiu** — na §4, `worst_at=107593.991` está no meio da
   janela (0,83 s antes do fim), entre a avalanche de `media_ready` (107593.840) e o segundo bloco de publicação
   (107594.271). Essa é a granularidade temporal que o instrumento oferece.

### O que a correlação NÃO sustenta

1. **Não sustenta qual trabalho interrompeu a apresentação em nenhum dos 19 segundos severos da corrida dirigida.**
   A captura de hoje não tem traço, console nem banco; as dimensões (b)-(e) saem `NOT_AVAILABLE` com o arquivo
   faltante nomeado (§3.2). Nenhuma atribuição é possível — e isto é resultado, não falha do instrumento.
2. **Não sustenta que a causa dos engasgos de rolagem seja publicação/mídia.** A evidência que aponta para
   publicação é de uma corrida **sem gesto** (§4); o perfil de trabalho durante uma rolagem é outro e não foi medido.
3. **Não sustenta que o aparelho esteja sob pressão de sistema.** Nenhuma captura disponível carrega
   memorystatus/jetsam/térmico/watchdog. O único sinal dessa família em qualquer bruto é um
   `FeedMine(7062,…) malloc: xzm: failed to initialize deferred reclamation buffer [2] (null)` em `console.log:6` da
   jornada ociosa — no arranque do processo, não no intervalo do travamento.
4. **Não sustenta nem exclui a própria automação do XCTest como parte do custo.** Sem o instante dos gestos
   registrado por qualquer insumo, "quadro travado durante gesto" e "quadro travado enquanto o app publica" não se
   separam na captura de hoje.
5. **Não sustenta generalizar a segunda metade da série.** Depois do gesto, a captura de hoje mistura rolagem com
   espera; sem o traço, a fronteira é desconhecida.

---

## 6. Hipóteses ordenadas por evidência, com o experimento que refuta cada uma

Ordem = força do dado que já existe, do mais apoiado ao menos.

**H1 — Trabalho de publicação/admissão no mesmo segundo (arranque e bursts de crescimento).**
*Dado que apoia*: na §4, o único segundo severo de três quadros é o da publicação de dois segmentos (20 + 21 cartas,
`trace.jsonl:76,123`), da admissão da janela de 17 cartas (`trace.jsonl:125`) e de 64 `media_ready`
(`trace.jsonl:4…`), com a linha de jornada pulando `cards` 0→17 e `media_prepared` 31→64 (`console.log:12`); e os 297
segundos ociosos seguintes não têm um quadro severo. O crescimento da janela é agendado em rajada
(`AppComposition.swift:2428-2434` — 8 tentativas de 0,75 s — disparadas em `:2595` e `:2604`).
*Experimento que refuta*: na corrida do GO com captura completa, exigir que ≥50% dos segundos severos tenham **ou**
um `admitted`/`replenishment_*`/`window` na janela **ou** mudança de `cards`/`media_prepared` na linha de jornada. Se
a maioria dos segundos severos tiver a janela admitida estável e nenhum evento de publicação, H1 cai para o caso
"arranque" e não explica a rolagem.

**H2 — Mídia: preparação/decodificação no intervalo (avalanche de `media_ready`).**
*Dado que apoia*: 64 eventos `media_ready` no mesmo `mono` (107593.840) e `media_prepared` 31→64 em um segundo
(§4); o par "carta declara mídia × carta tem pixels" é medido na própria linha de jornada
(`media_resident` contra `hero + thumb`).
*Experimento que refuta*: repetir a jornada de gestos com conteúdo **sem mídia** (`FEEDMINE_FIXTURE_ITEMS` com itens
sem imagem, ou a simulação de mídia que a suíte já usa) e a mesma carga de gestos; se a contagem de quadros severos
não cair de forma material, mídia não é o custo daquele intervalo.

**H3 — O custo da própria medição/automação (XCTest + árvore de acessibilidade).**
*Dado que apoia*: a assimetria de ~77× entre a jornada dirigida (6,2%) e o uso normal (0,08%); o teste resolve
`cards.allElementsBoundByIndex` sobre **todos** os elementos cujo identificador casa um UUID
(`FluidityJourneyUITests.swift:22-28`) e lê `app.staticTexts["feed-frame-proof"].label` duas vezes (`:33,:44`), e
cada leitura de rótulo é um snapshot da árvore do app inteiro.
*Experimento que refuta*: rodar a mesma sequência de gestos num teste que **não** leia a árvore (sem
`staticTexts`/`allElementsBoundByIndex`, só gestos e depois uma leitura única) e comparar a série; se a série não
mudar, a árvore/automação não é o gargalo. (Exige um teste novo **de medição**, não mudança de produto.)

**H4 — Instalação/re-render da janela no caminho do gesto.**
*Dado que apoia*: o caminho do viewport instala a projeção comprometida no `onCommitted`
(`AppComposition.swift:2640-2652`) e `install` é onde o medidor começa e onde a janela é reescrita (`:2369-2375`);
a rajada de crescimento roda a cada 0,75 s durante e depois do gesto.
*Experimento que refuta*: medir, na corrida do GO, quantos segundos severos contêm um `admitted` **e** se o conjunto
de ids admitidos muda dentro daquele segundo (`TRACE_CAPTURE=1` já imprime `ids=[…]` em
`AppComposition.swift:2388-2390`). Se nenhum segundo severo contiver admissão com mudança de ids, H4 cai.

**H5 — Pressão do sistema (memória/térmico/watchdog).**
*Dado que apoia*: **nenhum** — a hipótese existe porque nunca foi medida e porque é a explicação que sobra para
intervalos de 200–277 ms que não se repetem de forma determinística.
*Experimento que confirma/refuta*: a captura do syslog do aparelho na fase B (`console-journey.log`,
`idevicesyslog`); contar memorystatus/jetsam/thermalState/hang nos segundos severos. Zero ocorrências em 19 segundos
severos refuta a hipótese para esta corrida.

**H6 — Custo do instrumento ligado (`FEEDMINE_TRACE_CAPTURE=1` publica a série e os `ids=`).**
*Dado que apoia*: `FeedFrameEvidence.publish` roda a cada segundo com a captura ligada
(`FeedFrameMeter.swift:157-168`, `:204-208`) e o `admitted` passa a carregar a lista de ids da janela
(`AppComposition.swift:2388-2390`); a magnitude esperada é pequena (uma escrita de estado por segundo, um `Text` de
1×1 que não afeta o feed), mas é medida **dentro** da mesma corrida que julga fluidez.
*Experimento que refuta*: rodar a jornada com a captura desligada (removendo `FEEDMINE_TRACE_CAPTURE=1` do
`launchEnvironment` do teste, numa cópia de medição) e comparar a série. Sem diferença, o instrumento não é causa.

**Regra de leitura para a corrida do GO (para não repetir o erro de tratar "sem gesto" como "com gesto")**: um
segundo só conta como **rolagem efetiva** se tiver eventos `advance` no traço; `stationary`/ausência é repouso. Os
critérios do arquiteto (`…-build-48-aparelho-e-publicacao.md` §6) ficam aplicáveis exatamente assim: (a) o evento
ocorre durante rolagem efetiva; (b) existe trabalho de backend correspondente **ou a ausência dele é medida**;
(c) a explicação vem do dado, não de um número escolhido.

---

## 7. Prova: nada congelado tocado, `com.feedmine.app` nunca tocado

`bench/oracle.py`, `bench/EVALUATOR.sha256`, `bench/MANIFEST.sha256` e o corpus: **intocados** — nenhum arquivo de
`bench/` aparece em `git status`/`git diff` desta frente, e os hashes no working tree batem com o commit:

```console
$ git status --porcelain -- bench/ | wc -l
0
$ shasum -a 256 bench/oracle.py bench/EVALUATOR.sha256 bench/MANIFEST.sha256
57804e0bc354c26fe6010ae4070e9232ab2202dfb809a239f0fc468c68bce8b7  bench/oracle.py
debd34934a503bc964fb94795209ae4662fde7f825336e1baed5ea52fa6f1e7b  bench/EVALUATOR.sha256
f3ad5968ecba27fc1c6475230d23ed47d18a612441a5daee1125c44eaa12b6ad  bench/MANIFEST.sha256
```

`com.feedmine.app` — `bash scripts/hitch-pass.sh --audit` (sem tocar no aparelho), **saída bruta**:

```console
$ bash scripts/hitch-pass.sh --audit
=== prova, sem tocar no aparelho, de que esta corrida não toca em com.feedmine.app
-- scripts/hitch-pass.sh: onde o bundle do dono aparece
15:#   1. pré-voo: recusa `com.feedmine.app`, exige dispositivo, exige espaço em disco, exige diretório de saída novo;
32:#   Nunca instala, lança, termina ou desinstala `com.feedmine.app` (o TestFlight do dono). Recusa-se a isso por
42:#   scripts/hitch-pass.sh --audit        # prova, sem tocar no aparelho, que o script não toca em com.feedmine.app
67:readonly OWNER_BUNDLE="com.feedmine.app"
-- scripts/hitch-pass.sh: comandos que de fato apagam/desinstalam/reiniciam (comentário não executa e fica fora)
   (nenhum)
-- scripts/hitch-pass.sh: comandos que falam com o aparelho (todos usam $BUNDLE/$APP, nunca o bundle do dono)
8:# §2.2, §6) e **não** deixou a correlação: a corrida dirigida por `xcodebuild test` no aparelho não persiste o
54:UDID="${UDID:-00008110-00067D861486201E}"                       # id do xcodebuild (-destination id=…)
177:for cmd in xcrun xcodebuild python3 uuidgen sqlite3 awk; do
205:xcode=$(xcodebuild -version 2>/dev/null | head -1 || echo '?')
210:    xcrun devicectl device info lockState --device "$DEVICE" 2>&1 | sed -n '1,4p' || true
226:    if ! xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
267:xcrun devicectl device info apps --device "$DEVICE" --json-output "$OUT/apps-owner-before.json" >/dev/null 2>&1 || true
329:    xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "id=$UDID" \
335:    printf 'xcodebuild test exit=%s (log: %s)\n' "$journey_status" "$OUT/journey-test.log"
380:if xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
386:    xcrun devicectl device info files --device "$DEVICE" --domain-type appDataContainer \
416:xcrun devicectl device info apps --device "$DEVICE" --json-output "$OUT/apps-owner-after.json" >/dev/null 2>&1 || true

=== o instrumento que a fase A reusa, auditado do mesmo jeito
-- scripts/device-journey.sh: onde o bundle do dono aparece
20:#   Nunca desinstala, nunca apaga, nunca "erase". Recusa-se a tocar em `com.feedmine.app` — o TestFlight do dono,
44:readonly OWNER_BUNDLE="com.feedmine.app"
71:Recusa, sempre: com.feedmine.app (o app do dono). Nunca desinstala, nunca apaga, nunca dá `erase`.
544:installed = {"com.feedmine.app": False, "com.feedmine.development": False}
-- scripts/device-journey.sh: comandos que de fato apagam/desinstalam/reiniciam (comentário não executa e fica fora)
   (nenhum)
-- scripts/device-journey.sh: comandos que falam com o aparelho (todos usam $BUNDLE/$APP, nunca o bundle do dono)
273:    if ! xcrun devicectl device install app --device "$DEVICE" "$APP" >"$OUT/install.log" 2>&1; then
289:app_url="$(xcrun devicectl device info apps --device "$DEVICE" \
316:    [[ -n "$app_pid" ]] && xcrun devicectl device process terminate --device "$DEVICE" --pid "$app_pid" \
324:xcrun devicectl device process launch --device "$DEVICE" --console --terminate-existing \
330:    xcrun devicectl device info processes --device "$DEVICE" \
359:if xcrun devicectl device process terminate --device "$DEVICE" --pid "$app_pid" >"$OUT/terminate.log" 2>&1; then
379:if xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
389:    xcrun devicectl device info files --device "$DEVICE" --domain-type appDataContainer \
522:xcrun devicectl device info processes --device "$DEVICE" \
536:xcrun devicectl device info apps --device "$DEVICE" --json-output "$OUT/apps.json" >/dev/null 2>&1 || true

=== a terceira perna: o .app construído é conferido pelo CFBundleIdentifier antes de instalar
240:app_bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
241:[[ "$app_bundle" != "$OWNER_BUNDLE" ]] \
243:[[ "$app_bundle" == "$BUNDLE" ]] \
244:    || refused "o .app declara CFBundleIdentifier=$app_bundle, não $BUNDLE"

nenhuma linha acima instala, lança, termina ou desinstala com.feedmine.app.
```

As três pernas da prova: (1) **nenhum** comando destrutivo (`uninstall`/`erase`/`simctl erase`/`rm -rf`) em nenhum
dos dois scripts, com controle positivo e negativo do padrão executados (§7.1); (2) toda escrita no aparelho usa
`$APP`/`$BUNDLE`, e `$BUNDLE` não pode ser `com.feedmine.app` — `hitch-pass.sh:161-162` e `device-journey.sh:170-171`
recusam, e `hitch-pass.sh:241-244` recusa também pelo `CFBundleIdentifier` de dentro do `.app`; (3) o container de
`com.feedmine.app` é lido por `device info apps` **antes e depois** da corrida e a corrida falha a prova se ele
mudar. A auditoria não audita a si mesma (as linhas da própria função ficam fora da varredura: a primeira versão
acusava a si própria).

### 7.1 Controles executados (positivo e negativo) da varredura de comandos destrutivos

```console
$ P='devicectl +(device +)?(uninstall|erase)|simctl +(device +)?(erase|uninstall|delete)|(^|[^a-zA-Z-])rm +-[a-zA-Z]*[rf]'
$ for probe in 'xcrun devicectl device uninstall com.feedmine.app' 'xcrun devicectl device erase --device X' \
    'xcrun simctl erase all' 'rm -rf /tmp/x' '# nunca desinstala nada, nunca dá erase' \
    'Recusa, sempre: com.feedmine.app (o app do dono). Nunca desinstala'; do
    if grep -qEi "$P" <<< "$probe"; then echo "ACUSA  : $probe"; else echo "ignora : $probe"; fi; done
ACUSA  : xcrun devicectl device uninstall com.feedmine.app
ACUSA  : xcrun devicectl device erase --device X
ACUSA  : xcrun simctl erase all
ACUSA  : rm -rf /tmp/x
ignora : # nunca desinstala nada, nunca dá erase
ignora : Recusa, sempre: com.feedmine.app (o app do dono). Nunca desinstala
```

A varredura acusa os quatro comandos de verdade e ignora a prosa — que é o erro que a primeira versão da auditoria
cometeu (acusou o próprio texto de ajuda do `device-journey.sh`).

---

## 8. Procedimento do GO (o que falta executar)

1. **GO por mensagem** (o dono está instalando/validando a build 48; a corrida instala o bundle de desenvolvimento e
   toma o primeiro plano dele). Piso de disco: ≥3 GB livres.
2. `scripts/hitch-pass.sh --skip-build --app <prebuild> --derived-data <prebuild>/derived --out /tmp/fm-hitch-pass-<UTC>`
   — as duas fases, o console em arquivo (com o caminho impresso no fim) e o contêiner inteiro.
3. `python3 scripts/hitch-join.py --journey <OUT>/journey-standalone --select severe` (fase A, ociosa) e o mesmo
   sobre `<OUT>` inteiro (fase B, dirigida), com `--select bad` e `--context 2` para o entorno.
4. **Se a linha `feedmine journey` não aparecer** no console persistido da fase B, a causa exata sai do pass
   (`hitch-pass.sh` procura a linha e imprime as causas verificáveis) e a fase A continua sendo o insumo da jornada —
   nenhuma medição é reportada sem sujeito.
5. Este relatório ganha a seção §9 com as cinco dimensões por evento severo da corrida dirigida, a separação
   rolagem efetiva × repouso (`advance`) e o veredito de H1-H6. **Nenhuma correção** é implementada nesta frente.

### 8.1 Build armado (executado nesta frente, sem tocar no aparelho)

```console
$ bash scripts/hitch-pass.sh --build-only --out /tmp/fm-hitch-pre2 --derived-data /tmp/fm-hitch-pre/derived
=== build (Debug, iphoneos) → /tmp/fm-hitch-pre2/build.log
** BUILD SUCCEEDED **
app=/tmp/fm-hitch-pre/derived/Build/Products/Debug-iphoneos/FeedMine.app
versão=1.0 build=48 git=03d05f5f branch=gate/f48-hitch

=== build-only: nada foi tocado no aparelho
.app construído: /tmp/fm-hitch-pre/derived/Build/Products/Debug-iphoneos/FeedMine.app
derived data:    /tmp/fm-hitch-pre/derived
log do build:    /tmp/fm-hitch-pre2/build.log
NENHUM comando de aparelho foi executado neste modo (nem 'device info', nem instalação, nem lançamento).

o GO usa este build sem recompilar:
  scripts/hitch-pass.sh --skip-build --app '/tmp/fm-hitch-pre/derived/Build/Products/Debug-iphoneos/FeedMine.app' --derived-data '/tmp/fm-hitch-pre/derived' --out /tmp/fm-hitch-pass-$(date -u +%Y%m%dT%H%M%SZ)
disco livre depois do build: 2196608 KB
```

Identidade do `.app` (é ela que a corrida no aparelho prova de novo, pelo `FeedmineGitSHA` que o próprio app
carrega):

```console
$ /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :CFBundleVersion' \
    -c 'Print :FeedmineGitSHA' -c 'Print :FeedmineGitBranch' <app>/Info.plist
com.feedmine.development
48
03d05f5f
gate/f48-hitch
$ shasum -a 256 <app>/FeedMine
43715c9f5b5ba20229619052389c90b84f0120508a9c8b393b2663f40b7f54b1  <app>/FeedMine
```

**Um obstáculo medido, que o pass agora recusa antes de pagar**: o primeiro build falhou (151,6 s) com **um** erro —
`error: The file "catalog.sqlite" couldn't be opened because there is no such file` — porque `catalog.sqlite` é
**gitignored** (`.gitignore:20`) e uma worktree nova não o tem. A cópia veio da árvore principal e o sha256 bate
exatamente com o citado no relatório do instrumento de jornada de 2026-10-16:

```console
$ shasum -a 256 /tmp/fm-hitch/FeedMineApp/FeedMineApp/Resources/catalog.sqlite
42e602341d18f47290b06615eb9d49a25a693e36f3e9a4c327bbecd83e923b66  …
```

O `hitch-pass.sh` agora verifica a presença do catálogo no pré-voo (quando vai compilar) e recusa com o comando de
cópia, em vez de gastar dois minutos e meio num build que não pode terminar.

**Piso de disco para o GO: ≥3 GB.** No fim do build havia **2,1 GB** livres (2.196.608 KB, medido logo depois do
`BUILD SUCCEEDED`); o derived data armado ocupa 1018 MB e o `.app` 152 MB. A fase B compila o alvo de teste
(`xcodebuild test`, `-only-testing:FluidityJourneyUITests`) no mesmo derived data. Regra operacional: o `hitch-pass.sh`
recusa sozinho abaixo de 2 GB (o piso da missão), mas para **iniciar** um build vale o piso de 3 GB do arquiteto —
abaixo dele, libere espaço antes ou aponte `--derived-data` para outro lugar.

---

## Anexo A — arquivos desta frente

| Arquivo | Papel |
|---|---|
| `scripts/hitch-pass.sh` | a corrida física (build, fase A reusando `device-journey.sh`, fase B com syslog, contêiner, prova do app do dono, `--audit`, `--build-only`) |
| `scripts/hitch-join.py` | a junção por segundo e o relatório por janela severa (5 dimensões, com `arquivo:linha`; `--json`; `--select severe|bad|late|any`) |
| `docs/reviews/2026-10-16-f48-hitch-caracterizacao.md` | este relatório |

## Anexo B — como reconferir cada número deste relatório

```sh
# a série da corrida de hoje (19 janelas severas, dimensão (a) e o que falta)
python3 scripts/hitch-join.py --journey /tmp/int48-physical-evidence --select severe --context 0

# a captura que suporta as cinco dimensões (jornada ociosa de 2026-10-16)
python3 scripts/hitch-join.py --journey /tmp/fm-journey-20261016T075109Z --select severe --context 1

# os totais das duas séries
python3 scripts/hitch-join.py --journey /tmp/int48-physical-evidence --select any --context 0 | sed -n '/totais/,+2p'

# os hashes dos insumos citados
shasum -a 256 /tmp/int48-physical-evidence/62CB9727-697D-4E49-9FE1-1AADCB3CBFBD.txt
shasum -a 256 /tmp/fm-journey-20261016T075109Z/console.log
```
