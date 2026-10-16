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
| Corrida no aparelho (fases A e B do `hitch-pass.sh`) | **EXECUTADA** em 2026-10-16 16:39–16:44 UTC (§9): fase A ociosa **PASS** (0,13% dos quadros fora do orçamento), fase B com rolagem **PASS** (12,7%; 90 severos; pior 289,3 ms) |
| Relatório com as cinco dimensões por evento severo | **COMPLETO para a corrida do GO** (§9: cinco dimensões por janela pesada, com `arquivo:linha`) **e PARCIAL para a captura de 2026-10-16** (§3: só a dimensão (a) existe; (b)-(e) `NOT_AVAILABLE` com o arquivo que falta) |
| Correção de produto | **NENHUMA** (esta frente é medição). Os dois consertos desta frente são de **instrumento**: um em `scripts/hitch-pass.sh` e outro no bloco do WAL de `scripts/device-journey.sh`, autorizado pelo arquiteto (§2.1) |
| Commits | em `gate/f48-hitch`, sobre `03d05f5f`: instrumentos + relatório, conserto de instrumento autorizado, e o resultado da corrida no aparelho |

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
`console-journey.log` (mais o recorte de foco `console-journey-focus.log`) → **contêiner inteiro** de todos os
namespaces → prova de que `com.feedmine.app` ficou como estava (container antes = container depois) → imprime cada
bruto e o comando de junção.

Três decisões que não são óbvias e que vieram de medição:

1. **Duas capturas de console, não uma.** O app fala por duas vias: `NSLog` (`feedmine frames=`, `feedmine journey`,
   `FeedMineApp/FeedMineApp/FeedFrameMeter.swift:150,153`) e `Logger(subsystem:category:)`
   (`FeedMineApp/FeedMineApp/AppComposition.swift:32,2879`). O `devicectl --console` carrega a primeira e **não** a
   segunda (medido: 605 linhas de console na jornada de 2026-10-16, nenhuma `[composition]`); o `idevicesyslog`
   carrega as duas — medido na fase B: 26 `feedmine frames=`, **110 `installed cards=…`**, 39 `viewport forwarded`,
   41 `Runway opportunity completed`. O recorte de foco (`console-journey-focus.log`) é por **processo**
   (`FeedMine(`/`FeedMine[` no começo da linha), não por vocabulário de mensagem: o log unificado põe a categoria no
   nome do processo e o texto é só o que o app disse, então procurar `[composition]` no texto não acha
   `installed cards=…` nem `published growth: …` (medido: 0 linhas com `[composition]` e 110 `installed cards=` no
   mesmo arquivo).
2. **A variável tem de ser provada aplicada, não declarada.** O pass procura `feedmine journey` no console
   persistido e, quando não acha, grava a causa exata medida com a lista de causas verificáveis (o runner de teste
   não propaga a chave ao app; `idevicesyslog` ausente; app errado) — em vez de reportar medição sem sujeito. A
   fase B ainda tenta `TEST_RUNNER_FEEDMINE_JOURNEY_CONSOLE=1`, mas o resultado **não é presumido**.
3. **`--build-only`**: compila e sai sem executar **nenhum** comando de aparelho. É o modo com que esta frente deixou
   a corrida armada sem tocar no telefone do dono (§8). Dois recursos gitignored que o build exige são checados no
   pré-voo — `FeedMineApp/FeedMineApp/Resources/catalog.sqlite` (o build morre em `CpResource` sem ele: medido, 151 s
   de build perdidos) e `bench/corpus/profiles.json` (o **alvo de teste** morre sem ele: medido na primeira tentativa
   da fase B, `xcodebuild test` exit 65 e **nenhum** teste executado). E a presença do aparelho é esperada por até
   7 tentativas de 10 s, **impressas** — o iPhone desapareceu do `devicectl` por alguns segundos entre as fases A e B
   na corrida real, e esperar um hiccup de USB não é contornar a recusa, é não queimar a janela do dono.

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

O mesmo idioma existia em `scripts/device-journey.sh:397-402` (`wc -c <"$DB-wal"` **depois** do checkpoint). Ali, a
medição que fiz depois mostra que **o problema é de fidelidade do número, não de o script morrer** — e a primeira
versão deste relatório afirmava a queda erradamente. Quem remove o `-wal` é o **cliente que fecha a última conexão**,
e os dois clientes desta árvore divergem; medido na mesma cópia real, com um escritor morto deixando 94.792 bytes
pendentes:

| cliente | `-wal` antes | depois de `pragma wal_checkpoint(TRUNCATE)` |
|---|---|---|
| `sqlite3` (CLI — o de `device-journey.sh`) | 94.792 B | 0 B, **arquivo mantido** |
| `sqlite3` (módulo do Python — o de `hitch-pass.sh`) | 94.792 B | **arquivo removido** |

Duas consequências:

1. O `wc -c` **depois** do checkpoint **não** falhou em nenhuma execução com o CLI: controle negativo rodado na
   fixture (com `-wal` de 0 B) e na cópia com 94.792 B pendentes — as duas exit **0**. A queda que eu supus naquele
   arquivo **não se reproduziu**; o que se reproduziu (e foi corrigido) é o `FileNotFoundError` no bloco **do
   Python**, que é o do `hitch-pass.sh`.
2. O que a linha antiga fazia de errado é reportar um número que **esconde o fato**: com 94.792 bytes pendentes ela
   imprimia `wal_checkpoint: TRUNCATE em 0 bytes` — a **mesma** linha de uma corrida em que nada estava pendente, e
   foi essa a linha que a corrida de 2026-10-16 deixou. Quem lê não consegue distinguir "o app gravou pelo WAL" de
   "o app não tocou no WAL".

O conserto em `device-journey.sh` (commit separado, autorizado pelo arquiteto) lê o tamanho **antes** e imprime os
dois, nomeados:

```console
$ bash <bloco corrigido> ; echo exit=$?      # cópia com escritor morto: 94.792 B pendentes
wal_checkpoint: TRUNCATE: antes=94792 bytes, depois=0 bytes
exit=0
$ bash <bloco ANTIGO>  ; echo exit=$?        # a MESMA condição: não morreu, e escondeu os 94.792 B
wal_checkpoint: TRUNCATE em 0 bytes
exit=0
$ bash <bloco corrigido>                     # fixture real, `-wal` de 0 B (o caso do primeiro estouro)
wal_checkpoint: TRUNCATE: antes=0 bytes, depois=0 bytes
```

Uso (GO):

```sh
scripts/hitch-pass.sh --skip-build \
  --app /tmp/fm-hitch-pre/derived/Build/Products/Debug-iphoneos/FeedMine.app \
  --derived-data /tmp/fm-hitch-pre/derived \
  --out /tmp/fm-hitch-pass-<UTC>
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
   (`before` lido antes dos 6 `swipeUp`). O arranque não é limpo. **Estes 5 não podem ser somados aos 70 restantes
   sem dizer que a condição é outra**: são arranque **dentro de um teste dirigido** (app recém-lançado, com fixture),
   não uso do leitor; o que a série prova é que o arranque não é limpo, não que o consumo seja.
3. **A condição da medição muda o resultado em duas ordens de grandeza.** Jornada dirigida: 75/1208 = **6,2%** de
   quadros severos. Uso normal (passagem de 2026-10-15, citada em
   `main:docs/reviews/2026-10-16-build-48-aparelho-e-publicacao.md` §2.2): 25/31479 = **0,08%**. Mesmo app, mesmo
   aparelho, condições diferentes. Isso é observação, não causa — e é a razão de a corrida do GO ter uma **fase A
   ociosa** e uma **fase B dirigida**, para que as duas condições existam na mesma corrida.
4. **Quando o app está ocioso depois de arrancar, ele não engasga**: 297 segundos sem um quadro severo na §4.
5. **Quando o app publica arrancando, ele engasga**: na §4 o único segundo com 3 severos é o da publicação de dois
   segmentos + admissão de 17 cartas + 64 `media_ready`. **E é a hipótese de trabalho desta frente**: o engasgo que
   o leitor percebe vem de **publicação/admissão/mídia chegando**, não da rolagem em si. O que sustenta essa leitura
   nesta rodada é a coincidência exata (um só segundo com trabalho de publicação e três quadros severos) **mais** a
   ausência total de trabalho e de quadros severos nos 297 segundos seguintes. O que ela **não** é: uma medida de
   consumo — **esta captura não teve rolagem nenhuma** (zero `advance` em 299 s), logo ela não fala de consumo. Para
   este insumo, e só para ele, o dado também **refuta** a leitura de que "o medidor está errado": o medidor acusa no
   mesmo segundo em que o app publica, e fica mudo quando o app está parado, que é precisamente o que se espera de
   um medidor que mede a apresentação.
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

**H1 — Trabalho de publicação/admissão no mesmo segundo (arranque e bursts de crescimento). [hipótese de trabalho]**
*Dado que apoia*: na §4, o único segundo severo de três quadros é o da publicação de dois segmentos (20 + 21 cartas,
`trace.jsonl:76,123`), da admissão da janela de 17 cartas (`trace.jsonl:125`) e de 64 `media_ready`
(`trace.jsonl:4..:100`), com a linha de jornada pulando `cards` 0→17 e `media_prepared` 31→64 (`console.log:12`); e os
297 segundos ociosos seguintes não têm um quadro severo. O crescimento da janela é agendado em rajada
(`AppComposition.swift:2428-2434` — 8 tentativas de 0,75 s — disparadas em `:2595` e `:2604`). É a hipótese de
trabalho da rodada, e **não** uma medida de consumo: a captura que a apoia não teve rolagem (itens 3 e 5 de "o que a
evidência sustenta", §5).
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
de ids admitidos muda dentro daquele segundo. **Correção medida em 2026-10-16**: os `ids=[…]` **não** vão para o
evento `admitted` do traço — eles são o sufixo da **linha de log unificado** `installed cards=… ids=[…]`
(`AppComposition.swift:2389-2393`, dentro do `#if DEBUG` da chave `FEEDMINE_TRACE_CAPTURE`); o `invoke` do `[composition]` virou `FeedMine(FeedMine.debug.dylib)` na categoria e por isso o filtro do pass passou a recortar por **processo**, não por vocabulário (§2.1). Se nenhum segundo severo contiver admissão com mudança de ids, H4 cai.

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

## 8. Procedimento do GO — **executado em 2026-10-16** (o resultado está na §9)

1. **GO por mensagem** — dado pelo arquiteto na janela do dono. Piso de disco: ≥3 GB (havia 6,1 GB).
2. `scripts/hitch-pass.sh --skip-build --app /tmp/fm-hitch-pre/derived/Build/Products/Debug-iphoneos/FeedMine.app
   --derived-data /tmp/fm-hitch-pre/derived --out /tmp/fm-hitch-pass-<UTC>`
   — as duas fases, o console em arquivo (com o caminho impresso no fim) e o contêiner inteiro.
3. `python3 scripts/hitch-join.py --journey <OUT>/journey-standalone --select severe` (fase A, ociosa) e o mesmo
   sobre `<OUT>` inteiro (fase B, dirigida), com `--select bad` e `--context 2` para o entorno.
4. **Se a linha `feedmine journey` não aparecer** no console persistido da fase B, a causa exata sai do pass
   (`hitch-pass.sh` procura a linha e imprime as causas verificáveis) e a fase A continua sendo o insumo da jornada —
   nenhuma medição é reportada sem sujeito.
5. Feito: a seção §9 traz as cinco dimensões por janela pesada, a separação rolagem efetiva × repouso (`advance`)
   e o veredito de H1-H6. **Nenhuma correção de produto** foi implementada nesta frente.

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

## 9. A corrida física (2026-10-16, 16:39–16:44 UTC) — fase A ociosa × fase B com rolagem

Identidade: `.app` `com.feedmine.development`, build 48, **`FeedmineGitSHA=91b55a52`** (`= HEAD` desta branch; a
estampa bate com a árvore medida e o código do app é **idêntico** ao da 48 — `git diff --stat 03d05f5f..HEAD --
FeedMineApp Sources Package.swift` é vazio). Binário sha256 `8937560089990e518d02f9c201756c9a03019d83edf017e9702ae228b852a68b`.
Brutos: fase A em `/tmp/fm-hitch-pass-20261016T163928Z/journey-standalone/`, fase B em
`/tmp/fm-hitch-passB-20261016T164309Z/` (o teste foi re-rodado depois de o alvo de teste exigir
`bench/corpus/profiles.json`, gitignored — o pass agora recusa antes, §2.1). `com.feedmine.app` **inalterado**:
`apps-owner-before.json` e `-after.json` trazem o mesmo container
(`file:///private/var/containers/Bundle/Application/C78B92AD-0DE7-47AA-A12D-8095BF104AFC/FeedMine.app/`), e o pass
imprime o veredito.

### 9.1 Fase A — ociosa (89 s, sem gesto)

```
totais da série: janelas=89 quadros=5316 late=1 bad=0 severe=6 pior_ms=268.1
segundos com pelo menos um quadro: late=1 bad=0 severe=3
janelas severas: #1 3 severos 62,7 ms | #2 2 severos (1 late) 268,1 ms | #3 1 severo 50,4 ms
nenhum evento `advance` em 89 s
```

Os 6 quadros severos estão **nos três primeiros segundos medidos** (arranque: 3 admissões, `cards` 0→17,
`media_prepared` 15→64 na linha de jornada) e os **86 segundos seguintes não têm um quadro sequer fora do
orçamento**: 7 quadros fora do orçamento em 5316 = **0,13%**. A janela 1 é a única com evidência de pressão: uma
linha `malloc: xzm: failed to initialize deferred reclamation buffer` do próprio app. Zero `advance`.

### 9.2 Fase B — a jornada de rolagem (26 s medidos, 6 `swipeUp(velocity:.fast)`)

```
totais da série: janelas=26 quadros=1138 late=15 bad=39 severe=90 pior_ms=289.3
segundos com pelo menos um quadro: late=11 bad=16 severe=21
```

**144 dos 1138 quadros fora do orçamento = 12,7%**, contra **0,13%** da fase A: a mesma build, o mesmo aparelho, a
mesma hora — **97×**. E os engasgos **não** se concentram no arranque: **21 dos 26 segundos** têm pelo menos um
quadro severo, do primeiro ao último.

O que a captura conseguiu ver (e o que não):

| canal | o que trouxe |
|---|---|
| `console-journey.log` (syslog do aparelho, 98.894.060 B) | 26 linhas `feedmine frames=`, **110 `installed cards=… ids=[…]`**, 54 `published growth`, 39 `viewport forwarded`, 41 `Runway opportunity completed`, ~600–800 `native card observed` por segundo de rolagem |
| `trace.jsonl` do namespace do teste (`633D4BAF…`, 386 linhas) | 23 `frames`, 113 `admitted`, 80 `candidate`, **41 `advance`**, 60 `window`, 41 `runway_completed`, 9 `position_checkpoint`, 10 `replenishment_arrived` |
| anexo do XCTest | a série publicada (o teste passou: 1 teste, 0 falhas, 35,4 s) |
| `journey-test.log` | **zero** linhas do app — a confirmação independente de que no aparelho a saída do app não entra no log do `xcodebuild` |

**`FEEDMINE_TRACE_CAPTURE=1` foi aplicado** (o app imprimiu os `ids=[…]` da janela admitida e publicou a série);
**`FEEDMINE_JOURNEY_CONSOLE=1` não foi** — ver §9.7. Consequência prática: a dimensão dos fatos por segundo nesta
fase vem do **traço + do log unificado**, não da linha de jornada.

### 9.3 A estrutura por segundo — e ela é inequívoca

| janela | frames | late | bad | severe | pior ms | `advance` | admissões | trabalho do traço |
|---|---|---|---|---|---|---|---|---|
| 1 | 54 | 0 | 0 | 2 | 198,7 | 0 | 3 (cards 17) | 2 `window`, 31 `candidate` — **arranque** |
| 4 | 59 | 1 | 0 | 0 | 33,3 | 0 | 0 | — |
| 5 | 55 | 1 | 1 | 1 | 66,3 | 0 | 0 | — |
| **6** | **10** | 0 | 0 | **9** | **289,3** | **4 forward** | **11** (cards→22) | 7 `window` |
| 7 | 39 | 0 | 0 | 5 | 137,1 | 1 forward | 4 (→24) | 3 `window` |
| 8 | 52 | 1 | 0 | 2 | 90,5 | 1 stationary | 2 (→24) | `position_checkpoint` |
| **9** | **13** | 0 | 0 | **10** | **194,7** | **5 forward** | **13** (→28) | 7 `window` |
| 10 | 49 | 1 | 0 | 4 | 66,4 | 1 forward | 3 (→29) | 2 `window` |
| 11 | 53 | 0 | 1 | 1 | 99,3 | 1 stationary | 2 (→29) | `position_checkpoint` |
| **12** | **22** | 0 | 2 | **8** | **150,7** | **5 forward** | **13** (→33) | 8 `window` |
| 13 | 48 | 1 | 2 | 4 | 67,3 | 1 forward | 4 (→35) | 3 `window` |
| 14 | 53 | 1 | 1 | 1 | 98,9 | 1 stationary | 2 (→35) | `position_checkpoint` |
| **15** | **20** | 0 | 3 | **9** | **150,5** | **5 forward** | **13** (→39) | 7 `window` |
| 16 | 51 | 0 | 1 | 3 | 63,6 | 1 forward | 3 (→40) | 2 `window` |
| 17 | 53 | 0 | 1 | 1 | 99,2 | 1 stationary | 2 (→40) | `position_checkpoint` |
| **18** | **21** | 1 | 3 | **7** | **140,6** | **5 forward** | **13** (→44) | 7 `window` |
| 19 | 51 | 0 | 1 | 2 | 105,8 | 1 forward | 3 (→45) | 2 `window` |
| 20 | 53 | 0 | 1 | 1 | 97,8 | 1 stationary | 2 (→45) | `position_checkpoint` |
| **21** | **23** | 0 | 0 | **11** | **128,9** | **5 forward** | **9** (→49) | 6 `window` + **5 `replenishment_arrived`, 3 `requested`, 2 `concluded`** |
| 22 | 39 | 2 | 1 | 7 | 73,0 | 1 forward | 7 (→51) | 4 `window` + `replenishment_*` |
| 23 | 53 | 0 | 1 | 1 | 101,1 | 0 | 0 | — |
| 24 | 53 | 1 | 5 | 0 | 42,9 | 0 | 0 | — |
| 25 | 50 | 2 | 7 | 0 | 42,6 | 0 | 0 | — |
| 26 | 44 | 3 | 8 | 1 | 59,5 | 0 | 0 | — |

As janelas 23–26 são o **pós-teste** (o app já sem gesto, ainda medindo): 152 quadros em 4 segundos com `late/bad`
miúdos e **um** severo — o regime "quieto" de novo.

**A agregação por classe de segundo, que é o resultado:**

| classe | janelas | quadro severo | admissões por janela |
|---|---|---|---|
| **≥4 avanços `forward`** (o gesto) | 6, 9, 12, 15, 18, 21 | **54 dos 90 severos (60%)** | 11, 13, 13, 13, 13, 9 |
| exatamente 1 avanço `forward` | 7, 10, 13, 16, 19, 22 | 25 | 4, 3, 4, 3, 3, 7 |
| só repouso (`stationary`) | 8, 11, 14, 17, 20 | 6 | todos 2 |
| nenhum `advance` | 1, 4, 5, 23–26 | 5 (dos quais 2 na janela 1, arranque) | 0–3 |

Os **6 segundos pesados são exatamente os 6 `swipeUp`** do teste (espaçados ~3 s, cada gesto com 4–5 observações do
viewport), e a cada um segue um segundo de cauda (1 avanço, 3–4 admissões) e um de repouso (2 admissões). O
**número de admissões dentro do segundo acompanha o número de observações**, e o **número de quadros severos
acompanha as admissões**: 54 dos 90 severos estão nos 6 segundos em que o app instalou a janela 11–13 vezes.

### 9.4 As cinco dimensões, verbatim, numa janela pesada (6) e numa com reposição (21)

```
--- janela 6  severe=9
  (a) quadro: frames=10 late=0 bad=0 severe=9 worst_ms=289.3 budget_ms=16.67  [console-journey-focus.log:19791]
      carimbo do aparelho (verbatim): Oct 16 09:44:07.433134
      intervalo: mono 139567.381 → 139568.446 (1.065 s)   at=2026-10-16T16:44:07Z
  (b) [trace.jsonl:86]  mono=139567.399 advance activity=forward anchor=FAB80204-…  ↳ âncora: pos 2 (seg 0, carta 2, BBC World)
      [trace.jsonl:92]  mono=139567.778 advance anchor=C3A08ED7-… activity=forward ↳ pos 4
      [trace.jsonl:100] mono=139568.054 advance anchor=E9385133-… activity=forward ↳ pos 5
      [trace.jsonl:106] mono=139568.256 advance anchor=BE9A9EBA-… activity=forward ↳ pos 6
      [trace.jsonl:96]  mono=139567.909 window cards=19 cards_traversed=2      [trace.jsonl:105] cards=22 cards_traversed=3
      do log unificado: `native SwiftUI phase=idle->interacting`, `native phase active=true velocityUnverified=false`,
      `native geometry offset=16.0 extent=2691.0 height=785.0`, e **116** `native card observed id=… frame=…`
  (c) última admissão antes do fim [trace.jsonl:109] cards=22 order=8
      ↳ head: pos 0 (seg 0, carta 0)   ↳ tail: pos 21 (seg 0, carta 21)   ↳ anchor: pos 6 (seg 0, carta 6)
  (d) contagem por evento: admitted=11   (17, 19, 19, 21, 22 — a janela cresce sob o gesto)
      NOT_AVAILABLE: a linha `feedmine journey` não está nesta captura
  (e) NOT_OBSERVED nesta janela — nenhuma linha de pressão
```

```
--- janela 21  severe=11
  (a) quadro: frames=23 late=0 bad=0 severe=11 worst_ms=128.9 budget_ms=16.67
      carimbo: Oct 16 09:44:22.625984   intervalo: mono 139582.609 → 139583.645 (1.036 s)
  (b) 5 × `advance activity=forward` (âncoras pos 29, 30, 31, 32, 33) + 6 × `window`; o app também registra
      `FeedMine(UIAccessibility) … Post notification failed … error:-25201` e `FeedMine(UIKitCore) … Evaluating dispatch of UIEvent …`
  (c) [trace.jsonl:339] cards=49 order=55   ↳ tail: pos 48 (seg 1, carta 17)   ↳ anchor: pos 32
  (d) admitted=9, **replenishment_arrived=5**, replenishment_requested=3, replenishment_concluded=2 —
      e a reposição é de **rede**: `kind=network target=40000000-…-0001 bytes=26329 observations=32`, com o
      fornecimento local declarado esgotado (`exhausted=true`) no mesmo segundo
  (e) NOT_OBSERVED nesta janela — nenhuma linha de pressão
```

### 9.5 (e) Pressão do sistema: nenhuma nas janelas de engasgo

Nenhuma das 21 janelas severas tem uma linha de pressão **do aparelho sobre o app**. As duas únicas linhas que a
regra dura pegou em 26 s, e de quem são:

```
[console-journey-focus.log] FeedMineUITests-Runner(BaseBoard)[7493]  … for "jetsamMode": required --> optional
[console-journey-focus.log] runningboardd(RunningBoard)[33]  [app<com.feedmine.development.FeedMineUITests.xctrunner…>:7493] Set jetsam priority to 100
[console-journey-focus.log] amsondevicestoraged(OnDeviceStorageInternal)[1027]  Received low memory warning   (janela 26, sozinha)
```

A primeira é o **runner de teste** registrando `jetsamMode` no arranque (o nome dele contém "FeedMine" — por isso a
regra agora separa emissor), e a terceira é um aviso de memória de **outro processo** do sistema, na última janela do
recorte. Memória, térmico e watchdog, portanto, **não** explicam nenhuma janela desta corrida.

### 9.6 O que a correlação sustenta agora (observação)

1. **O engasgo é do gesto, não do repouso.** Ocioso: 0,13% dos quadros fora do orçamento (6 severos em 89 s). Com
   rolagem: 12,7% (90 severos em 26 s). **97×** na mesma build, no mesmo aparelho, na mesma corrida (`hitch-pass.sh`
   roda as duas fases em sequência, com o mesmo `.app`).
2. **O engasgo acompanha o número de admissões no mesmo segundo**, e as admissões acompanham o número de
   observações do viewport que o gesto produz: nos 6 segundos com ≥4 `advance forward` houve 11–13 admissões e **54
   dos 90 quadros severos**; nos segundos de repouso, 2 admissões e 6 severos.
3. **Os 6 segundos pesados são os 6 `swipeUp`**, com o ciclo gesto → cauda → repouso repetido 6 vezes. Nada disso é
   visível na série do teste sozinha (que não tem `advance`): é a junção que dá a estrutura.
4. **A janela admitida cresce sob o gesto** (17 → 51 cartas ao longo da jornada; 11–13 admissões por segundo pesado),
   com o pico do gesto movendo a âncora 4–5 posições no mesmo segundo.
5. **A telemetria da própria medição é uma carga constante**: ~600–800 linhas `native card observed id=… frame=…`
   por segundo de rolagem, além de 39 `viewport forwarded` e 54 `published growth` — tudo isso só existe porque
   `FEEDMINE_TRACE_CAPTURE=1` (a chave que a jornada liga). É custo do instrumento, não do feed.
6. **O regime "quieto" volta quando o gesto para**: as janelas 23–26, já sem gesto, somam 152 quadros com um único
   severo.

### 9.7 O que ela NÃO sustenta

1. **Não separa o custo do app do custo do harness.** Os 6 segundos pesados são os 6 gestos sintetizados pelo
   XCTest; o app, no mesmo segundo, fez trabalho real (admissões, `UIEvent` dispatch, transições de fase do SwiftUI)
   **e** o harness sintetizou o arrasto. Esta corrida não decide a fração de cada um.
2. **Não sustenta mídia como causa nesta fase.** O traço da fase B tem **0 `media_ready`**: nos segundos pesados não
   houve evento de mídia nenhum. O que a fase A mostrou (64 `media_ready` num segundo, junto de um severo) é um
   fenômeno **de arranque**, e o arranque da fase B é a janela 1 (2 severos, 198,7 ms, 3 admissões).
3. **Não sustenta publicação/reposição como causa geral.** Só as janelas 21 e 22 têm `replenishment_*`; as janelas
   6, 9, 12, 15 e 18 são igualmente pesadas **sem** nenhum evento de reposição.
4. **Não sustenta pressão de sistema** (§9.5).
5. **Não é a média que diz nada**: 21 dos 26 segundos têm severo, então "razão média" esconderia que o problema é
   concentrado nos 6 segundos de gesto.
6. **Um limite do insumo, declarado**: o relay do log unificado **perde linhas** do app (26 linhas `frames=` no
   console contra 23 eventos no traço, com discordância já na segunda janela), então o alinhamento console × traço
   foi feito por **conteúdo** (quíntupla `frames/late/bad/severe/worst_ms` idêntica), não por posição — e onde duas
   janelas têm a mesma quíntupla a ordem de ocorrência é a chave (entre gêmeas o segundo pode trocar; os números,
   não). Além disso, o traço cobre 23 dos 26 segundos (o último lote não chegou ao disco) e a janela 1 não tem
   limite inferior no console.

### 9.8 Veredito por hipótese (o que o dado novo faz com cada uma)

| # | Hipótese | Veredito com esta corrida | Experimento que decide (se ainda for preciso) |
|---|---|---|---|
| **H4** | Instalação/re-render da janela no caminho do gesto | **APOIADA (a mais forte)**: 6 janelas com 4–5 observações do gesto e 11–13 admissões no **mesmo segundo** concentram 54 dos 90 severos; repouso (2 admissões) tem 6 | medir a mesma jornada com as admissões coalescidas por gesto (uma instalação por gesto em vez de uma por observação) — ramo de **medição**, não de produto |
| **H1** | Publicação/admissão no arranque | **APOIADA só para o arranque**: fase A concentra 6/6 severos nos 3 primeiros segundos; fase B, janela 1 (2 severos, 198,7 ms) é arranque. **Não** explica os 6 segundos de gesto | já delimitada: a hipótese vale para "arranque", não para "consumo" |
| **H6** | Custo do instrumento ligado (`TRACE_CAPTURE`) | **APOIADA como carga constante**: 600–800 linhas `native card observed`/s durante toda a rolagem, em todos os segundos (não só nos pesados) | repetir a jornada com a **série publicada sem o log por carta** (hoje as duas coisas compartilham `FEEDMINE_TRACE_CAPTURE=1`) e comparar a série |
| **H3** | Custo do XCTest + árvore de acessibilidade | **INDETERMINADA / enfraquecida como causa única**: o app registra trabalho próprio no mesmo segundo (`UIEvent` dispatch, fases do SwiftUI, 11–13 admissões), mas o gesto é sintetizado pelo harness | rodar a mesma sequência de gestos num teste que não leia a árvore e comparar; e/ou `press(forDuration:thenDragTo:)` (mais passos, mesmo deslocamento) contra `swipeUp(velocity:.fast)` — se o custo segue o **número de observações**, é o app; se segue a síntese do gesto, é o harness |
| **H2** | Mídia no intervalo | **REFUTADA para esta fase**: 0 `media_ready`; o fenômeno de mídia medido é de arranque (fase A) | repetir com conteúdo sem mídia e mesma carga de gestos (verifica se o arranque muda, não os 6 segundos de gesto) |
| **H5** | Pressão do sistema | **REFUTADA nesta corrida**: nenhuma linha de pressão sobre o app em 26 s; as duas únicas são do runner (arranque) e de outro processo (última janela) | capturar sob carga prolongada (sessão de minutos) para ver se memória/térmico aparecem quando o estado acumula |

### 9.9 A armadilha da linha de jornada, medida (e o que entrou no lugar)

A linha `feedmine journey` **não** aparece na fase B. Causa exata, medida, não suposta:

1. `hitch-pass.sh` exporta `TEST_RUNNER_FEEDMINE_JOURNEY_CONSOLE=1` — que põe a chave no processo do **runner de
   teste**, e o app sob teste **não a herda**: o teste declara em `launchEnvironment` apenas
   `FEEDMINE_TRACE_CAPTURE` (`FluidityJourneyUITests.swift:9-14`);
2. a chave para o app só existe pelo `launchEnvironment` do teste, e o teste não a declara — logo `feedmine journey`
   é 0 em toda jornada dirigida, **por construção**, até que o teste (ou outro caminho) a declare;
3. **não** foi o canal de captura: o syslog trouxe 26 `feedmine frames=`, 110 `installed cards=… ids=[…]` e 39
   `viewport forwarded` do **processo certo** (`FeedMine(FeedMine.debug.dylib)[7494]`), e a fase A tem 89 linhas de
   jornada com a chave ligada — a diferença é o caminho do lançamento, não a captura.

O que substituiu a linha de jornada na fase B, e é melhor para esta pergunta: os `installed cards=… ids=[…]` (o
texto da janela admitida, por instalação), o `published growth: …`, o `viewport forwarded activity=… anchor=…` e os
eventos do traço. O que se perdeu com ela: o par `media_resident`/`media_prepared` por segundo — que nesta fase
seria zero de qualquer forma (0 `media_ready`).

---

## 10. F48-HITCH-X — a pergunta semântica, respondida com o dado que já existe

O arquiteto pediu que a pergunta fosse de **semântica**, antes de coalescer: distinguir (a) instalações aceitas pelo
store, (b) mudanças efetivas de snapshot/proveniência e (c) mudanças na lista renderizada que realmente exigem
atualização SwiftUI — porque *"onze instalações registradas não significam onze reconstruções integrais do feed"*.
Esta seção responde isso com a captura de F48-HITCH (a fase B), **sem build nem aparelho**. O experimento de
coalescência vem depois, e só se estes números justificarem.

### 10.1 A taxonomia das 113 instalações de 26 s, por dois canais independentes

Classificação de cada instalação contra a anterior, pelo **traço** (`admitted`: geração, `order`, `head`, `tail`,
`anchor`, `cards`) e pelo **log unificado** (`installed cards=… order=… ids=[…]`, que carrega a lista inteira na
ordem):

| classe | traço | log (`ids=[…]`) |
|---|---|---|
| **idêntica ao valor corrente** (mesma geração, mesma ordem, mesma janela, mesma âncora) | **54 (48%)** | **51 (46%)** |
| muda só a **âncora** (e a proveniência `order`); a lista de cartas é a mesma | **32 (28%)** | **32 (29%)** |
| **conteúdo da janela muda** (`cards` 17→59, `head`/`tail` mudam) | **26 (23%)** | **26 (24%)** |
| primeira | 1 | 1 |

Os dois canais concordam (a diferença de 3 linhas no log é o relay do syslog, que perde linhas do app — §9.7).
Por janela de gesto: os 6 segundos com 4–5 observações têm **13 instalações cada**, das quais ~5–6 idênticas, ~4–5
só de âncora e 3 de conteúdo; os segundos de repouso têm 2, **ambas idênticas**.

### 10.2 O que o código já faz hoje — e onde está o custo

**(c) já está guardado, e o comentário prova que foi medido antes.** `FeedScreenStore.install`
(`Sources/FeedMineUI/FeedScreenStore.swift:137-158`) publica **só o que a lista desenha**, e só quando muda:

```swift
let rendered = presentationState.presentation?.window.items
if rendered != renderedItems { renderedItems = rendered ?? [] }      // :150
if received.work != work { work = received.work }                    // :151
```

com a nota do próprio arquivo: *"Sem isso, cada avanço re-renderizava a lista inteira — 12–14 vezes por segundo numa
rajada (medido no aparelho, 2026-10-14)"*. Das 113 instalações desta jornada, portanto, **só as 26 de conteúdo
republicam a lista**.

**O que não é coalescido é a publicação do estado.** `state = presentationState.reporting(received.work)`
(`:148`) acontece em **toda** instalação, e `state` é uma propriedade `@Observable`: toda view que lê `state` é
invalidada — inclusive nas 54 que não mudam nada.

**E há leitura no corpo de uma view.** `NativeFeedViewport.body` lê `store.state.presentation` duas vezes, em
`.id(...)` (`Sources/FeedMineUI/FeedScreen.swift:654-655`), sobre o conteúdo que é o leitor inteiro. O autor
documentou a intenção (`:625-627`: *"um avanço reavalia este modificador, **barato**, e não o corpo da lista"*),
mas o modificador reavalia nas **113** — enquanto a lista, nas 26.

Em números, o espaço exato que sobra para coalescer:

| | hoje | mínimo necessário |
|---|---|---|
| publicações do **estado** (`state = …`) | **113** | **59** (as que mudam o valor: 26 de conteúdo + 32 de âncora + 1) |
| publicações da **lista** (`renderedItems`) | 26 | 26 (já coalescido) |

**48% das publicações de estado não têm o que publicar.** É esse o alvo do H4a — e é o único: coalescer as 32 de
âncora junto com as 26 de conteúdo mexeria no compromisso semântico da posição, que é exatamente o que o arquiteto
proibiu.

### 10.3 O desenho dos dois experimentos

**H3 (harness × app)** — `FeedMineApp/FeedMineAppTests/HitchGestureExperimentUITests.swift`, dois métodos com a
**mesma instrumentação**. Aqui a chave `FEEDMINE_JOURNEY_CONSOLE=1` é ligada de propósito e pelo mesmo motivo nos
dois métodos: **o lado A e o lado B têm de carregar a mesma carga de logging**, senão a comparação seria entre duas
condições diferentes — e a carga não é pequena (600–800 linhas `native card observed` por segundo de rolagem, mais
39 `viewport forwarded` e 54 `published growth`, tudo sob `FEEDMINE_TRACE_CAPTURE`; §9.6). Ligar a chave nos dois
lados é o que torna a diferença medida atribuível ao **gesto**, e não à instrumentação. Os dois métodos são:

* `testA6FastSwipes` — 6 × `scroll.swipeUp(velocity: .fast)` (o gesto que mediu os engasgos);
* `testB6SlowMultiStepDrags` — 6 × `press(forDuration: 0.4, thenDragTo: dy 0.8→0.3, withVelocity: .slow,
  thenHoldForDuration: 0.1)`: mesma fração de deslocamento pedida (0,5 da altura), **mais passos**, velocidade lenta.

O que decide: se os quadros severos seguirem o **número de observações do app** (`advance` no traço), é o app; se
seguirem a síntese do gesto, é o harness. Como o deslocamento alcançado não é igual por construção, a comparação é
**normalizada por posição de leitura movida**, com o deslocamento medido no `anchor` do traço — nunca estimado pelo
teste. E os dois métodos afirmam que o ponto de leitura mudou (`initial_card ≠ final_card`): um experimento que
"melhora" porque o leitor andou menos se refuta.

**H4a (coalescer somente o redundante)** — um guard de igualdade no host, com o fato preservado
(`FeedMineApp/FeedMineApp/AppComposition.swift:2381`):

```swift
let redundant = received == store.state
if redundant { FeedFlowCounters.installRedundant += 1 }
else { do { try store.install(received); FeedFlowCounters.installAccepts += 1 } catch { … } }
```

Tudo o mais do `install` segue idêntico ao controle (contador de tentativas, evento `admitted` no traço, a linha
`[composition] installed …`, `frameMeter`, bookmarks): o que se pula é **a atribuição do valor observável**, e como
o valor recebido é igual ao corrente, pular **não pode** atrasar o compromisso da posição — a posição do valor
recebido é a que já está publicada. `FeedPresentationState` já é `Hashable`
(`Sources/FeedMineUI/FeedPresentationState.swift:29`), então a comparação é a do próprio contrato. A ablação é
contável na evidência pelo campo `redundant` do evento `admitted` e pelo contador `FeedFlowCounters.installRedundant`.

**H4b (ablação agressiva, "uma instalação por gesto")** — **não implementada**. Só entra se o H4a mostrar que as
redundantes custam algo; entra isolada, com a diferença de comportamento (âncora, janela, reposição) medida e
reportada, como o arquiteto exigiu.

### 10.4 Conformidade com as condições do arquiteto

| Condição | Como esta frente a cumpre (verificável) |
|---|---|
| ramo **descartável** derivado da **árvore de medição** | `gate/f48-hitch-x`, criada de `gate/f48-hitch` cujo código de app é idêntico a `03d05f5f`; `git merge-base --is-ancestor 03d05f5f HEAD` verdadeiro |
| **controle com a MESMA instrumentação** | `FEEDMINE_TRACE_CAPTURE=1` **e** `FEEDMINE_JOURNEY_CONSOLE=1` nos **dois** métodos do teste (§10.3), e a razão é essa: dois lados com cargas de logging diferentes não provam nada sobre o gesto |
| nada de tocar a **release distribuída** nem o **bench congelado** | nenhum arquivo de `bench/` alterado (`git status --porcelain -- bench/` vazio); `release/1.0-build.48` e a tag `ios/1.0-build.48-03d05f5f` intocadas; nenhum commit desta frente foi promovido à main |
| nada promovido à main direto | os commits vivem em `gate/f48-hitch` e `gate/f48-hitch-x`; a promoção é verdict de outro dono |
| medir **âncora, continuidade da janela e capacidade de reposição**, não só quadros | `scripts/hitch-compare.py` imprime as três e **recusa** a comparação quando uma das corridas não movimentou o leitor; o relatório do resultado traz a taxonomia das admissões e as contagens de `replenishment_*` dos dois lados |
| a técnica experimental **não** vira arquitetura antes do resultado | o guard é um commit próprio, revertível, com o fato registrado igual ao controle; a ablação agressiva (H4b) não foi implementada |

### 10.5 O que ainda NÃO foi medido (lista explícita)

1. ~~**O custo do gesto por síntese** (H3)~~ — **medido na §11.1**: a fração fora do orçamento é ~10% nas três
   receitas e a contagem segue as observações do app.
2. ~~**O ganho de coalescer as 54 publicações redundantes** (H4a)~~ — **medido na §11.2**: o mecanismo pulou 47%
   das publicações e **nenhum** ganho apareceu acima do ruído de ±12–22% entre corridas do mesmo código.
3. **Se o custo está no modificador do viewport ou em outras views que leem `state`** — a captura mede o efeito
   agregado; atribuir a uma view específica exigiria instrumentação por view (não autorizada, não feita).
4. **Comportamento sob sessão longa** (memória/térmico acumulando) — a corrida mediu 26 s com gesto e 89 s ociosos.
5. ~~**A linha `feedmine journey` na jornada dirigida**~~ — **apareceu** nos dois lados (§11): era o caminho do
   lançamento, como a §9.9 tinha diagnosticado.
6. **Repetições por célula** — o efeito procurado é menor que o ruído de uma corrida (§11.2, três corridas do
   mesmo código: severe −12%, pior intervalo +22%): qualquer conclusão fina exige N corridas por método.
6. **Nada de arquitetura**: o guard é um ramo experimental, revertível, e não uma decisão sobre o fluxo de
   apresentação. Coalescer não é redesenhar.

---

## 11. F48-HITCH-X — o resultado dos dois experimentos (2026-10-16, 17:20–17:31 UTC)

Duas corridas no aparelho, cada uma com **três métodos de gesto** e a mesma instrumentação nos dois lados
(`FEEDMINE_TRACE_CAPTURE=1` **e** `FEEDMINE_JOURNEY_CONSOLE=1`, §10.3). Os dois lados diferem **só** no guard do
H4a (`git diff --stat gate/f48-hitch-x-control gate/f48-hitch-x -- FeedMineApp Sources Package.swift` → só
`AppComposition.swift` e `FeedScreen.swift`; o arquivo de teste é idêntico). Cada método lança o seu próprio app,
logo tem o seu namespace e o seu traço — e o mapa método→namespace foi conferido pela série que o app publicou
(`scripts/hitch-methods.py`; a contagem de janelas do traço é ≤ o `seconds=N` da série, porque a cauda do traço se
perde no encerramento).

A linha do `feedmine journey` **apareceu** nos dois lados: o teste novo a declara no `launchEnvironment`, e isso
fecha o diagnóstico da §9.9 (o caminho era o lançamento, não a captura).

### 11.1 H3 — o custo acompanha as observações do app (apoiada), e o harness não fica excluído

As três receitas de gesto, **na mesma corrida e no mesmo app** (controle, `d8d3feb0`):

| método | gestos | observações do app (`advance`) | quadros | severos | severos/observação | %fora | pior ms |
|---|---|---|---|---|---|---|---|
| **A** `swipeUp(.fast)` | 6 flings | 40 | 1047 | 84 | **2,10** | 10,51% | 375,5 |
| **B** 24 arrastos em etapas (6 unidades de gesto) | 24 drags | 101 | 3031 | 277 | **2,74** | 10,33% | **1516,9** |
| **C** `swipeUp(.slow)` | 6 flings lentos | 30 | 948 | 76 | **2,53** | 9,39% | 1055,1 |

**O que o número sustenta:** a fração de quadros fora do orçamento é **~10% nas três receitas** (9,39%–10,51%,
uma faixa de ±6%), enquanto a contagem absoluta acompanha as **observações do app** (30 → 76 severos; 40 → 84;
101 → 277) e a duração. Ou seja: o custo é **por observação do viewport** — a mesma ordem de grandeza em três
sínteses de gesto muito diferentes (um fling rápido, 24 arrastos lentos, seis flings lentos). A razão
severos/observação fica em 2,10–2,74.

**O que ele NÃO sustenta:** isolar o harness. A razão de B é 30% maior que a de A e a de C 20% — na direção de
"mais passos sintetizados custa mais por observação", e dentro/na borda do ruído medido abaixo. Com **uma corrida
por célula** não se separa o custo do app do custo da injeção de eventos do XCTest; o que se pode afirmar é que
**a fração de quadros fora do orçamento não muda com a receita** (o que seria esperado se a síntese dominasse) e
que a contagem **segue as observações**.

**Um achado à parte, e ele importa para a régua:** o **pior intervalo** das receitas com mais passos foi muito
maior (B: 1516,9 ms; C: 1055,1 ms; A: 375,5 ms) — mas não é estável entre corridas (o mesmo B deu 299,5 ms na
outra corrida, 5× menos). O pior intervalo de uma corrida **não** serve como métrica de comparação sem repetições.

### 11.2 H4a — o mecanismo funciona e **não** há ganho de quadros (o custo não está na publicação redundante)

Método **A** (os mesmos 6 `swipeUp(.fast)`), controle × ramo com o guard:

| | controle (`d8d3feb0`) | ramo (guard) | Δ |
|---|---|---|---|
| janelas | 24 | 25 | — |
| quadros | 1047 | 1015 | −3% |
| late + bad + **severe** | 9 + 17 + **84** | 8 + 10 + **98** | severe **+17%** |
| %fora do orçamento | 10,51% | 11,43% | +9% |
| pior intervalo | 375,5 ms | 407,3 ms | +8% |
| observações do app | 40 | 41 | +2% |
| âncoras distintas | 31 | **31** | **=** |
| admissões | 113 | 118 | +4% |
| eventos de reposição (`replenishment_*`) | 19 | 20 | +5% |
| **instalações marcadas `redundant=1`** | **0** | **55** | o guard pulou 55 de 118 = **47%** |

**O mecanismo é o previsto:** o guard marcou **55 publicações redundantes de 118 (47%)** — a §10.1 previu 48%. E a
continuidade está **igual** (âncoras 31 = 31, admissões e reposição dentro de 5%), que era a condição para o
resultado valer.

**O ganho não apareceu: os quadros não melhoraram** — pioraram 3%–17%, na direção contrária à esperada, e a
magnitude é a do **ruído**. Piso de ruído medido na mesma receita (A) em três corridas idênticas de código:

| corrida | observações | quadros | fora | severos | %fora | pior ms |
|---|---|---|---|---|---|---|
| controle v1 (mesmo app) | 37 | 1115 | 117 | 95 | 10,49% | 308,4 |
| controle v2 (mesmo app) | 40 | 1047 | 110 | 84 | 10,51% | 375,5 |
| ramo (guard) | 41 | 1015 | 116 | 98 | 11,43% | 407,3 |

O mesmo código, a mesma receita, duas corridas: severos 95 × 84 (**−12%**), pior intervalo 308 × 376 ms (**+22%**).
Ou seja: **a diferença entre controle e ramo (severe +17%, pior +8%) está dentro do espalhamento entre duas
corridas do mesmo código**. Não há ganho detectável, e o resultado honesto é o que o arquiteto previu: **o custo
não está na publicação redundante do estado.**

**O que isso NÃO significa:** que a publicação do `state` seja gratuita. Significa que, neste aparelho e com esta
instrumentação, **48% menos publicações não produziram diferença mensurável** — e que o efeito que se procura é
menor que o ruído de uma corrida (~12–22%), logo uma detecção exigiria **repetições por célula** e não uma
corrida.

### 11.3 Veredito por experimento

| experimento | veredito | o número que o sustenta |
|---|---|---|
| **H3** (harness × app) | **o custo acompanha as observações do APP** — e o harness **não** fica excluído | %fora do orçamento ~10% nas três receitas (9,39%–10,51%) com razão severos/observação 2,10–2,74; a contagem absoluta segue as observações (30/76, 40/84, 101/277) |
| **H4a** (coalescer só o redundante) | **mecanismo confirmado, ganho NÃO detectável** → "o custo não está na publicação redundante" | 55 de 118 (47%) publicações puladas, continuidade igual (âncoras 31=31), quadros +17% de severos — dentro do ruído de ±12–22% medido em três corridas do mesmo código |
| **H4b** (ablação agressiva) | **não executada** (por decisão: o H4a não justificou) | — |

### 11.4 O que este resultado pede antes de qualquer reescrita

1. **Repetições, não uma corrida:** para detectar efeitos <20% são precisas N corridas por célula; o instrumento já
   dá o número por método e o ruído (três corridas do método A estão medidas acima).
2. **O alvo mudou de lugar:** se o custo é por **observação do viewport** (o que H3 sugere), a pergunta seguinte é
   *quantas dessas observações são necessárias* — e aí a §10.1 já diz que 47% das **instalações** são idênticas e
   28% mudam só a âncora, mas **nenhuma** dessas duas classes é a publicação do estado, que é o que o H4a mostrou
   não custar. O caminho que sobra é o próprio trabalho por observação (a leitura do viewport, a admissão, o
   `install` inteiro: contrato de estado, bookmarks, medidor, log) — e isso é uma pergunta nova.
3. **Nada de arquitetura:** o guard fica no ramo experimental, revertível, e não vira desenho.


---

## Anexo A — arquivos desta frente

| Arquivo | Papel |
|---|---|
| `scripts/hitch-pass.sh` | a corrida física (build, fase A reusando `device-journey.sh`, fase B com syslog, contêiner, prova do app do dono, `--audit`, `--build-only`) |
| `scripts/hitch-join.py` | a junção por segundo e o relatório por janela severa (5 dimensões, com `arquivo:linha`; `--json`; `--select severe|bad|late|any`) |
| `FeedMineApp/FeedMineAppTests/HitchGestureExperimentUITests.swift` | F48-HITCH-X: os dois gestos com a mesma instrumentação (H3) e o controle/experimento do H4a (`project.pbxproj` com os ids `…0113`/`…0114` na fase `…0036` e no grupo `…000D`) |
| `scripts/hitch-methods.py` | F48-HITCH-X: as métricas **por método de gesto** de uma corrida (mapa método→namespace pelo carimbo do anexo e pela série publicada) |
| `docs/reviews/2026-10-16-f48-hitch-caracterizacao.md` | este relatório |

## Anexo B — como reconferir cada número deste relatório

```sh
# a série da corrida de hoje (19 janelas severas, dimensão (a) e o que falta)
python3 scripts/hitch-join.py --journey /tmp/int48-physical-evidence --select severe --context 0

# a captura que suporta as cinco dimensões (jornada ociosa de 2026-10-16)
python3 scripts/hitch-join.py --journey /tmp/fm-journey-20261016T075109Z --select severe --context 1

# os totais das duas séries
python3 scripts/hitch-join.py --journey /tmp/int48-physical-evidence --select any --context 0 | sed -n '/totais/,+2p'

# a corrida do GO: fase A (ociosa) e fase B (rolagem), com a junção por conteúdo
python3 scripts/hitch-join.py --journey /tmp/fm-hitch-pass-20261016T163928Z/journey-standalone --select any --context 1
B=/tmp/fm-hitch-passB-20261016T164309Z; NS=633D4BAF-C28B-4165-A246-4987532D643C
python3 scripts/hitch-join.py --console "$B/console-journey-focus.log" \
  --trace "$B/container/Library/Application Support/FeedMine/$NS/trace.jsonl" \
  --db    "$B/container/Library/Application Support/FeedMine/$NS/runtime.sqlite" \
  --series "$B/attachments/5B9BFA26-E680-46EE-A63E-D5ACE5A87BE9.txt" --select any --context 1

# a prova de que o app foi tocado pelo syslog e de que a linha de jornada não veio
grep -c 'feedmine frames=' /tmp/fm-hitch-passB-20261016T164309Z/console-journey-focus.log
grep -c 'feedmine journey' /tmp/fm-hitch-passB-20261016T164309Z/console-journey-focus.log
grep -m1 'installed cards=' /tmp/fm-hitch-passB-20261016T164309Z/console-journey-focus.log | cut -c1-200

# os hashes dos insumos citados
shasum -a 256 /tmp/int48-physical-evidence/62CB9727-697D-4E49-9FE1-1AADCB3CBFBD.txt
shasum -a 256 /tmp/fm-journey-20261016T075109Z/console.log
```
