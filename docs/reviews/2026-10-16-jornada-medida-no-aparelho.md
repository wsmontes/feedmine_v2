# Jornada medida no aparelho físico — instrumentação e `scripts/device-journey.sh`

Data: 2026-10-16 · Branch: `feat/device-journey-instrument` · Commit único sobre `2202cdd8` (base revisada)
Aparelho: iPhone 14 Plus (`iPhone14,8`), `devicectl` id `BBA4F656-A5EA-5D81-934E-E484ED71B8E2`, `devicectl` 518.33
Bundle sob teste: `com.feedmine.development` (build 47, Debug, estampado `FeedmineGitSHA=d4403ff3`)
Catálogo empacotado (gitignored, copiado da árvore principal): `catalog.sqlite` sha256
`42e602341d18f47290b06615eb9d49a25a693e36f3e9a4c327bbecd83e923b66`
`com.feedmine.app` (TestFlight do dono): **nunca instalado, nunca lançado, nunca terminado, nunca apagado** — a
ferramenta recusa esse bundle por duas vias independentes.

> **Precisão de escopo na candidata 48:** esta corrida histórica mediu o commit `d4403ff3`, não o binário de
> TestFlight 48. `media_resident` conta imagens decodificadas na projeção; blob no disco ou imagem residente não
> provam que o pixel apareceu na tela. A prova de desenho é distinta (jornada de screenshot com controle).
> A instrumentação de console é DEBUG e desligada por padrão; não se afirma que a distribuição Release coleta
> essas linhas. A tentativa posterior de screenshot via XCTest no físico foi `NOT_RUN` por timeout ao ativar
> automação, não impossibilidade demonstrada de capturar a tela. Ver o relatório de rolagem desta data.


## 1. O que o PO pediu e o que existe agora

O relato dele: "desenvolva métodos inteligentes de monitoramento do telefone físico" e "conteúdos precisam ser
baixados". A passagem pelo iPhone de 2026-10-15 provou que o app funciona **e que ele é indiagnosticável**: 529
linhas de console em sete minutos, 523 delas telemetria de quadros por segundo e **zero** sobre aquisição, fontes
contactadas ou mídia preparada. Nesta rodada o app passou a dizer os seus próprios fatos no console e um comando
mede a jornada inteira (console + container).

## 2. A linha de jornada

Uma linha limitada por segundo no console do aparelho:

```
feedmine journey t=<segundos>s cards=<n> hero=<n> thumb=<n> text=<n> media_resident=<n> media_prepared=<n> media_settled=<n> sources_contacted=<n> sources_responded=<n> sources_unreachable=<n> preparation=<live|done> install_rejects=<n>
```

Exemplo real, desta corrida (linha completa, copiada do console do telefone):

```
2026-10-16 00:51:13.404 FeedMine[7062:1301249] feedmine journey t=2s cards=17 hero=0 thumb=17 text=0 media_resident=17 media_prepared=64 media_settled=64 sources_contacted=2 sources_responded=2 sources_unreachable=0 preparation=done install_rejects=0
```

Quem já sabia cada número (nenhum estado novo foi aberto — a linha só **diz**):

| Campo | Dono que já guardava o fato |
|---|---|
| `cards`, `hero`, `thumb`, `text`, `media_resident` | a projeção publicada (`store.state.presentation.window.items`), cartas por segundo |
| `media_prepared`, `media_settled` | o índice da própria camada de mídia (`MediaReadiness`), por **revisão** |
| `sources_contacted`, `sources_responded`, `sources_unreachable`, `preparation` | a evidência de pipeline do PD-3 (`PreparationProgress`), alimentada pelo relé do cold bootstrap |
| `install_rejects` | `FeedFlowCounters`, que o host já lê |

Unidades ditas, porque importam: `media_resident` é **por carta** (mesma unidade de `hero`/`thumb`/`text`, então o
par "mídia declarada" contra "mídia pronta" é lido na mesma linha), enquanto `media_prepared`/`media_settled` são
**por revisão** (o pipeline prepara mídia para a oferta antes da seleção). Medido nesta corrida, os dois
concordam: 64 candidatos declarados, 64 revisões decididas, 17 cartas com pixels prontos das 17 que declaram
mídia.

Que a série existe para mostrar **mudança**, e não repetição, é o que o instrumento imprime ao resumir 299 linhas
em três grupos: `0/0` no primeiro segundo, `1 respondida` no segundo, e o estado estável depois disso.

**Cadência e custo:** nenhum relógio novo. A linha pega carona no tique que o `FeedFrameMeter` já tem (o mesmo que
escreve `feedmine frames=`), uma vez por segundo — nunca mais frequente que o que já existia. O tipo inteiro
(`FeedJourneyConsole`) e a chamada são `#if DEBUG`, e a chave é `FEEDMINE_JOURNEY_CONSOLE=1` (desligada por
padrão), a mesma espécie da outra instrumentação de debug (`FEEDMINE_TRACE_CAPTURE`). Em Release o amostrador é
`nil` e o medidor não pergunta nada (§5 prova nos bytes).

Correção medida nesta rodada, dentro do mesmo tique: `CADisplayLink.timestamp` é **0** até o link disparar uma vez,
e o relógio lido em zero fazia a linha dizer a uptime do telefone (`t=101933s`). O relógio da jornada (e o `t=`)
começa agora no primeiro quadro realmente desenhado.

## 3. O instrumento: `scripts/device-journey.sh`

`--help` (saída real):

```
device-journey.sh — jornada medida em um iPhone físico (app de DESENVOLVIMENTO).

Uso:
  scripts/device-journey.sh --device <ID> --app <CAMINHO.app> [opções]

Obrigatórios:
  --device <ID>       Identificador do devicectl (UUID, UDID, ECID, serial, nome ou DNS).
  --app <CAMINHO.app> Bundle .app já construído. O caminho TEM de terminar em `.app`.

Opções:
  --seconds <N>       Duração da jornada com o app em primeiro plano (default: 240; 0 = só instalar/lançar/coletar).
  --out <DIR>         Onde ficam os artefatos brutos (default: /tmp/fm-journey-<UTC>).
  --bundle <ID>       Bundle id do app sob teste (default: com.feedmine.development).
  --namespace <N>     `auto` (default) = UUID novo por corrida: jornada fria, censo só deste run, nada existente é
                      tocado. `<uuid>` = reusa aquele namespace. `none` = container compartilhado do bundle (o
                      censo passa a incluir todo o histórico dele; o script avisa).
  --env <JSON>        Variáveis de ambiente do lançamento, em JSON. `FEEDMINE_JOURNEY_CONSOLE=1` é acrescentada se
                      você não a declarar; `--namespace` governa FEEDMINE_RUNTIME_NAMESPACE.
  --skip-install      Não instala; usa o que já está no aparelho.
  --help              Esta ajuda.

Recusa, sempre: com.feedmine.app (o app do dono). Nunca desinstala, nunca apaga, nunca dá `erase`.
```

O que ele faz, em ordem: instala o `.app` → identifica o **pid no aparelho** pelo container daquele bundle (nunca
pelo nome do executável: o app do dono também é `FeedMine.app/FeedMine`) → lança com `--console` em arquivo por um
tempo limitado → termina por `--pid` → analisa o console → puxa o container inteiro → dobra o WAL na cópia →
imprime o censo → diz o estado final (processos restantes do app sob teste, e se `com.feedmine.app` continua
instalado).

Recusas que existem no código, todas antes de tocar no aparelho (linhas de `scripts/device-journey.sh`):
`--bundle com.feedmine.app` (170-171); um `.app` cujo `CFBundleIdentifier` **é** `com.feedmine.app` (182-183); um
`.app` que não declara o `--bundle` pedido (184-185); `--app` sem `.app` (172-173); `--app` inexistente (174);
`--seconds` não inteiro (175); `--skip-install` com valor (176-177); `.app` sem `Info.plist` (180); dependência
fora do `PATH` (187-189); menos de 1 GB livre em `/` (193-195); `--namespace` que não é UUID/`auto`/`none`
(215-216); `--env` que não é objeto JSON ou que conflita com `--namespace` (244); `--out` existente e não vazio
(250-251); `--out` que não pôde ser criado (253). Quem é `NOT_RUN` (exit 3), e não `REFUSED`, é o dispositivo
ausente do `devicectl list devices` (197-198). Falhas de etapa viram `NOT_RUN` com a razão e o log: instalação
(exit 4, linha 275), app que não aparece entre os processos (5, linhas 307 e 349), container não copiado (6, linhas
392, 394, 401 e 408). O console é analisado **antes** do container, de propósito: é a medição que existe mesmo
quando a coleta do container falha.

### 3.1 Três recusas provadas por execução (2026-10-16, árvore `/tmp/fm-device`)

`bash -n scripts/device-journey.sh` → exit 0 (sem erro de sintaxe). As três execuções abaixo saem com exit 2 e
nenhuma delas roda comando de aparelho que escreva: as duas primeiras recusam antes de qualquer `devicectl`, e a
terceira passa só pelo `devicectl list devices` (leitura de lista) e recusa **antes** do `install`.

```console
$ bash scripts/device-journey.sh --device IGNORADO --app /tmp/nao-existe.app --bundle com.feedmine.app
REFUSED: --bundle com.feedmine.app é o app do dono (TestFlight, container pessoal): esta ferramenta nunca o toca
$ echo $?
2

$ bash scripts/device-journey.sh --device IGNORADO --app /tmp/nao-existe
REFUSED: --app precisa terminar em .app (o devicectl recusa outro caminho: CoreDeviceError 3002)
$ echo $?
2

# fixture mínima (.app só com Info.plist) porque esta árvore não tem .app construído: sem ela o pré-voo pararia
# antes de chegar à checagem de --out
$ mkdir -p /tmp/fm-refusal-fixture/FeedMine.app
$ /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.feedmine.development' \
      /tmp/fm-refusal-fixture/FeedMine.app/Info.plist
File Doesn't Exist, Will Create: /private/tmp/fm-refusal-fixture/FeedMine.app/Info.plist
$ bash scripts/device-journey.sh --device BBA4F656-A5EA-5D81-934E-E484ED71B8E2 \
      --app /tmp/fm-refusal-fixture/FeedMine.app --out /tmp/fm-refusal-out-44528
REFUSED: --out /tmp/fm-refusal-out-44528 já existe e não está vazio: use um diretório novo (ou apague-o) para não misturar duas jornadas
$ echo $?
2
$ ls -la /tmp/fm-refusal-out-44528     # o diretório do usuário ficou intocado
-rw-r--r--  1 wagnermontes wheel  29 Oct 16 06:55 console.log
```

E, por leitura do script inteiro (não por amostragem): `OWNER_BUNDLE` só aparece em 44 (a definição), 170 e 182 (as
duas recusas) e 544-547 (onde o valor é usado apenas para **imprimir** se o app do dono continua instalado, a partir
de `device info apps`, que é leitura). Todo comando que instala, lança, copia ou termina usa `$APP` (273, install)
ou `$BUNDLE` (324, launch; 379, `copy from`; 389, `info files`) — e `$BUNDLE` não pode ser `com.feedmine.app` sem
cair em 170/182 antes. Não há `uninstall`, `erase`, `shutdown` nem `terminate` por bundle id em nenhuma linha: o
único `terminate` (316 e 359) usa `--pid` de um processo resolvido pelo prefixo do container de `$BUNDLE` (332-346).

## 4. A corrida real

Comando executado (o `.app` é o Debug iphoneos estampado com o commit desta branch):

```sh
scripts/device-journey.sh --device BBA4F656-A5EA-5D81-934E-E484ED71B8E2 \
  --app /tmp/fm-device-derived/Build/Products/Debug-iphoneos/FeedMine.app --seconds 300 \
  --env '{"FEEDMINE_SKIP_ONBOARDING":"1","FEEDMINE_USE_DEVELOPMENT_FEEDS":"1"}'
```

Saída bruta (exit 0), de `/tmp/fm-journey-20261016T075109Z` (não versionado; `console.log` sha256
`5ee23079bacffdcf39229f0806e9cb4d9d9ceffb17deb762c9282c560b75fdea`):

```
=== proveniência
device=BBA4F656-A5EA-5D81-934E-E484ED71B8E2
bundle=com.feedmine.development
app=/tmp/fm-device-derived/Build/Products/Debug-iphoneos/FeedMine.app
app_version=1.0 build=47 git=d4403ff3 branch=feat/device-journey-instrument
devicectl=518.33
out=/tmp/fm-journey-20261016T075109Z
seconds=300
namespace=394FA0C4-89E8-47BF-8874-FE30EDAB9937
env={"FEEDMINE_JOURNEY_CONSOLE": "1", "FEEDMINE_RUNTIME_NAMESPACE": "394FA0C4-89E8-47BF-8874-FE30EDAB9937", "FEEDMINE_SKIP_ONBOARDING": "1", "FEEDMINE_USE_DEVELOPMENT_FEEDS": "1"}
host_utc=2026-10-16T07:51:09Z

=== install
App installed:
• installationURL: file:///private/var/containers/Bundle/Application/87D0A295-BF30-4D17-BACE-E6609F7388B6/FeedMine.app/

=== launch (console em /tmp/fm-journey-20261016T075109Z/console.log)
container do app=file:///private/var/containers/Bundle/Application/87D0A295-BF30-4D17-BACE-E6609F7388B6/FeedMine.app/
pid no aparelho=7062
jornada por 296s

=== terminate
00:56:11  Acquired tunnel connection to device.
00:56:11  Enabling developer disk image services.
00:56:12  Acquired usage assertion.
console: 605 linhas

=== console
console_lines=605 frame_windows=299
frames_total=17938 late=2 bad=0 severe=4
worst_windows=152ms(late0/bad0/sev3), 55ms(late1/bad0/sev1), 25ms(late1/bad0/sev0), 21ms(late0/bad0/sev0), 19ms(late0/bad0/sev0)
journey_lines=299
journey_changes=3
  t=0s (1s): cards=0 hero=0 thumb=0 text=0 media_resident=0 media_prepared=0 media_settled=0 sources_contacted=2 sources_responded=0 sources_unreachable=0 preparation=live install_rejects=0
  t=1s (1s): cards=0 hero=0 thumb=0 text=0 media_resident=0 media_prepared=31 media_settled=31 sources_contacted=2 sources_responded=1 sources_unreachable=0 preparation=live install_rejects=0
  t=2s..t=299s (297s): cards=17 hero=0 thumb=17 text=0 media_resident=17 media_prepared=64 media_settled=64 sources_contacted=2 sources_responded=2 sources_unreachable=0 preparation=done install_rejects=0
non_telemetry_lines=7 suspect_lines=2
  ! 00:51:11  Acquired usage assertion.
  ! FeedMine(7062,0x1f48cc380) malloc: xzm: failed to initialize deferred reclamation buffer [2] (null)
  | 00:51:11  Acquired tunnel connection to device.
  | 00:51:11  Enabling developer disk image services.
  | Launched application with com.feedmine.development bundle identifier.
  | Waiting for the application to terminate…
  | App terminated due to signal 15.

=== container
puxado: Library/Application Support/FeedMine/394FA0C4-89E8-47BF-8874-FE30EDAB9937
runtime.sqlite=4096 bytes
wal_checkpoint: TRUNCATE em 0 bytes

=== censo (cartas, fontes, alvos, mídia)
-- edições e segmentos (all = o container inteiro; run = criado depois do launch)
editions_all  editions_run  first_edition_epoch
------------  ------------  -------------------
1             1             1792137072.23197
time_to_first_edition_s=1.2 (relógio do host, contra launch_epoch=1792137071)
segments_all  segments_run
------------  ------------  ------------
3             3
-- cartas por tipo de mídia (all = histórico do container; run = publicadas nesta jornada)
render_layout  cards_all  with_media_key_all
-------------  ---------  ------------------
thumbnail      42         42
render_layout  cards_run  with_media_key_run
-------------  ---------  ------------------
thumbnail      42         42
-- alternância de fontes na ordem em que o leitor percorre (PD-4: tem de ser 0 pares)
adjacent_same_source_pairs_all
------------------------------
0
adjacent_same_source_pairs_run
------------------------------
0
-- fontes
publishing_sources_all
----------------------
2
publishing_sources_run
----------------------
2
source_namespaces  admitted_items
-----------------  --------------
2                  64
state    targets
-------  -------
enabled  2
connector_kind  targets
--------------  -------
syndication     2
-- candidatos de mídia que as fontes declararam
candidates  revisions  with_declared_size
----------  ---------  ------------------
64          64         64
-- quem publicou (as que mais contribuíram, histórico do container)
source       cards
-----------  -----
BBC Science  21
BBC World    21
-- mídia localmente disponível (bytes reais no container puxado)
media_blobs=51 media_bytes=667492 media_mb=0.6
  (sem extensão): 51 blobs, 667492 bytes
-- rastro da F05 (trace.jsonl)
trace_lines=384 trace_events=9
     260  frames
      64  media_ready
      42  candidate
       6  admitted
       4  replenishment_arrived
       3  window
       2  replenishment_requested
       2  replenishment_concluded
       1  position_checkpoint

=== estado final
processos_restantes_do_app_sob_teste=0  (bundle com.feedmine.development)
instalado[com.feedmine.app]=sim
instalado[com.feedmine.development]=sim

=== artefatos
todos os brutos em: /tmp/fm-journey-20261016T075109Z
```

(Tabelas acima reproduzidas em forma compacta onde o `sqlite3 -column` do console alinha as colunas; os valores são
idênticos aos brutos.)

### 4.1 O que a corrida diz, e o que confere consigo mesma

- **A jornada ficou diagnosticável.** Em um segundo o app diz quantas cartas admitiu (17), quantas declaram mídia
  e quantas já têm pixels (`thumb=17`, `media_resident=17`), quantas fontes contactou e quantas responderam
  (`2`/`2`, uma delas respondendo entre o primeiro e o segundo segundo), e quantas instalações foram recusadas
  (`0`). As falhas contadas são `sources_unreachable=0` e `install_rejects=0`.
- **Os dois canais concordam.** A linha diz `sources_contacted=2`/`responded=2` e o censo conta 2 fontes
  publicando (BBC Science 21 + BBC World 21 = 42 cartas) com 2 alvos `syndication` habilitados; a linha diz
  `media_prepared=64`/`settled=64` e o censo conta 64 candidatos de mídia declarados e 64 revisões decididas.
- **O que foi baixado, em bytes.** 51 blobs, 667.492 bytes (0,6 MB) de mídia no container — o par "conteúdos
  precisam ser baixados" medido, não inferido. Para as 64 revisões que a fonte declarou, 51 deixaram blob: o
  instrumento dá os dois números e **não** atribui a diferença a uma causa (mídia ainda pendente, decidida como
  insuficiente pela política, ou podada pelo PD-5 são todas compatíveis com o que se vê) — atribuir seria
  adivinhação.
- **1,2 s até a primeira edição** e 3 segmentos, `0` pares adjacentes da mesma fonte na ordem em que o leitor
  percorre (ordinais de segmento e de carta, não UUID) — a leitura do PD-4 continua limpa nesta jornada.
- O `console.log` tem 605 linhas: 299 de quadros, 299 de jornada e 7 que não são telemetria (as 5 do `devicectl`
  e 2 do próprio processo: uma assertion de uso e uma linha de malloc do Runtime). **Nenhuma** linha de erro de
  produto; o app terminou por `signal 15`, que é o `terminate` do próprio instrumento.

## 5. O custo em Release (a configuração de entrega)

Por construção: o tipo `FeedJourneyConsole`, a montagem da linha e a chamada no `FeedFrameMeter` estão todos
dentro de `#if DEBUG`; em Release `journeySampler()` devolve `nil`, o parâmetro do `init` não é guardado e o
medidor não pergunta nada por segundo — sobra o mesmo callback por quadro fazendo aritmética de antes.

Medido nos bytes, em vez de inferido (varredura de **todo** o bundle, porque o código do app não vive só no
executável: no Debug ele está em `FeedMine.debug.dylib`):

```sh
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/fm-device-derived CODE_SIGNING_ALLOWED=NO build
# para cada arquivo do .app: strings -a <arquivo> | contar as cadeias
```

| cadeia procurada | Release (`Release-iphoneos/FeedMine.app`) | Debug (`Debug-iphoneos/FeedMine.app`) |
|---|---|---|
| `feedmine journey` | **ausente** | 1 (`FeedMine.debug.dylib`) |
| `feedmine frames=` (já existia, mesmo gate) | **ausente** | 1 |
| `media_resident` | **ausente** | 1 |
| `runway_completed` — controle positivo, **não** gated | 1 (`FeedMine`) | 1 |

O controle positivo é o que impede a medida de ser vazia: `runway_completed` **está** no binário de Release, então
a varredura encontra cadeias reais; a ausência das outras três é uma medida, não um artefato do método. (Ela
também mostra que os `Self.log("cold bootstrap …")` do host já eram apenas de Debug — `cold bootstrap started`
também não aparece em Release.)

Nota de honestidade sobre o comando: o build de Release foi feito com `CODE_SIGNING_ALLOWED=NO` para não precisar
das credenciais de distribuição. Assinatura não muda geração de código nem as `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
da configuração; o que se mede aqui é o que a configuração de entrega compila.

## 6. Verificação

Árvore de trabalho `/tmp/fm-device` (worktree de `feat/device-journey-instrument`), `catalog.sqlite` copiado de
`FeedMineApp/FeedMineApp/Resources` da árvore principal antes de construir (é git-ignored), sem formatter nem lint.

```sh
swift build        # > Build complete! (85.89s)      exit 0
swift test         # exit 0
git diff --check   # exit 0, sem espaços em branco
```

O resumo da suíte do pacote, literal do log (`/tmp/fm-swift-test.log`):

```
Test Suite 'All tests' passed at 2026-10-16 01:00:47.845.
	 Executed 1399 tests, with 3 tests skipped and 0 failures (0 unexpected) in 84.040 (84.305) seconds
```

Os 3 pulados são os de `CatalogCompilerReferenceTests`, que se declaram pulados sem
`FEEDMINE_REFERENCE_FEEDS_ROOT`/`FEEDMINE_REFERENCE_CATALOG` — condição do ambiente, dita pelo próprio teste.

Alvo do app (o que cobre `AppComposition` e a linha do console), em simulador próprio
`FeedMine Instrument` (`616105F9-7E5B-4FFB-BA0C-EA5EEFB999E3`, iPhone 17 / iOS 26.5, criado e apagado nesta
rodada — nenhum simulador compartilhado foi usado):

```sh
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination "platform=iOS Simulator,id=616105F9-7E5B-4FFB-BA0C-EA5EEFB999E3" \
  -derivedDataPath /tmp/fm-device-derived -parallel-testing-enabled NO -only-testing:FeedMineAppTests test
```

**`NOT_RUN`** — o alvo de teste do app **não** produziu veredito nesta rodada. Quatro tentativas, quatro bloqueios
de ambiente, todos antes do primeiro caso de teste do app:

1. `/tmp/fm-app-tests.log` e 2. `/tmp/fm-app-tests2.log` morreram na **construção** do alvo `FeedMineUITests`,
   porque `bench/corpus/profiles.json` não existe nesta árvore — literal dos logs:
   `error: The file "profiles.json" couldn't be opened because there is no such file. (in target 'FeedMineUITests')`
   e `** TEST FAILED **` / `Testing cancelled because the build failed.`
3. `/tmp/fm-app-tests3.log` chegou a **executar** casos de `FeedMineAppTests` (há `passed`/`Failing tests:` no log),
   mas o arquivo termina truncado em `Failing tests:` — sem `** TEST FAILED **`, sem `Executed N tests`, sem
   veredito. Não é evidência de nada além de uma corrida interrompida.
4. `/tmp/fm-app-tests4.log`: `Command CodeSign failed with a nonzero exit code` (`internal error in Code Signing
   subsystem`) e `** TEST FAILED **` — a construção morreu na assinatura do `.dylib`, antes de rodar teste.

A suíte do **pacote** (onde vive `AppComposition`) passou inteira, isso está medido acima. O que não existe é um
resultado de `FeedMineAppTests` para citar, então fica `NOT_RUN` com os logs, e não um PASS de fachada. O efeito da
linha de jornada no app não foi provado por teste unitário nesta rodada: foi **medido no aparelho** (§4).

## 7. Limites, ditos em vez de escondidos

- **O alvo de UI do scheme exige o corpus do bench, e o corpus é git-ignored.** `xcodebuild test -scheme FeedMine`
  constrói **todos** os alvos de teste da ação de teste, inclusive `FeedMineUITests`, cuja fase de recursos copia
  `../../bench/corpus/profiles.json` — arquivo que só existe onde o harness do bench o preparou (~964 bytes). Numa
  árvore de trabalho nova o build morre ali **antes de rodar qualquer teste**
  (`error: The file "profiles.json" couldn't be opened`), e nem `-only-testing:` nem `-skip-testing:` evitam a
  construção do alvo. Nesta rodada o arquivo foi copiado da árvore principal (git-ignored, sha256 idêntico
  `24109941fee198e0ffb0b914fb9f23d01b0509ffcf7ffe691020b2c9ce0738f9`, nada versionado) só para o build passar; o
  corpus e o oráculo da árvore principal não foram tocados.
- **O disco desta máquina é o gargalo real, não o código.** O volume ficou entre 157 MB e 1,8 GB livres durante esta
  rodada, com outros agentes construindo em paralelo; um `xcodebuild` de teste do alvo do app pede ~600 MB e um
  simulador bootado ocupa 1,3–3,2 GB. Nada aqui foi medido sob ENOSPC (ver a nota da §6 sobre o que não rodou por
  isso), e o critério é o que já está registrado: um run que morre por disco é descartado, não relatado.
- **Sem gestos.** A ferramenta não injeta toque nem rolagem na tela (ela não existe nesta máquina para captura e
  não é o que o dono pediu). Uma jornada parada não cresce: o conjunto fica em 17 cartas porque ninguém avançou o
  leitor — o que a série mede aqui é o bootstrap e a preparação de mídia, não o consumo.
- **A cadência da jornada é a do medidor de quadros.** Um segundo sem nenhum quadro disparado não emite **nenhuma**
  das duas linhas (é o `guard frames > 0` que já existia): nesta corrida faltam três `t=` na faixa estável, e o
  resumo diz isso na contagem (`297s` de linhas dentro de uma faixa de 298 s).
- **Screenshot continua impossível** neste host (`idevicescreenshot` não inicia `screenshotr`, não há janela de
  espelhamento): o que está provado é o que o console e o container dizem, não o que a tela mostrava.
- **A mídia puxada é a do namespace novo** desta corrida: um `--namespace none` misturaria com o histórico do
  container compartilhado, e o script avisa em vez de fingir que separa.
- **Não foi medido**: jornada longa com rolagem real, consumo/energia, e o comportamento de `media_resident` sob
  liberação de pixels (residência) — a série do `t=` mostraria, mas nesta corrida não houve janela móvel.

## 8. Armadilhas do `devicectl` medidas nesta rodada

1. **`install app` exige um caminho terminado em `.app`** (outro caminho é `CoreDeviceError 3002`).
2. **`copy from` com origem em arquivo exige destino em arquivo**; com origem em diretório, o destino é um
   diretório e a cópia despeja o **conteúdo** dentro dele (é o que o modo device do `bench/run.sh` já faz).
3. **`terminate` só aceita `--pid`** (não aceita bundle id). `--terminate-existing` resolve o caso de uma instância
   anterior do mesmo bundle antes de lançar.
4. **O diretório do namespace é a forma canônica MAIÚSCULA do UUID.** Lançar com
   `FEEDMINE_RUNTIME_NAMESPACE=<uuid minúsculo>` cria `Library/Application Support/FeedMine/<UUID MAIÚSCULO>`, e
   puxar o caminho minúsculo falha com `CoreDeviceError 7000` ("file node not found") — que se lê como "o app não
   escreveu nada" quando ele escreveu tudo. O script normaliza; o erro de cópia agora também lista o que o
   container realmente tem.
5. **`runtime.sqlite` sozinho não é o banco**: 4.096 bytes de principal contra ~832 KB de WAL. Sem puxar o `-wal` e
   dobrar (`pragma wal_checkpoint(TRUNCATE)`, na cópia), o censo diz "vazio" com 42 cartas publicadas.
6. **Incremental build apaga o carimbo do `Info.plist`**: o `xcodebuild` reagenda `ProcessInfoPlistFile` depois da
   fase "Stamp build identity" quando o build não é limpo, e o `FeedmineGitSHA` desaparece do produto (medido: um
   build limpo carimba, o seguinte, sem mudança de fonte, apaga). Para evidência, construa limpo — ou confira o
   carimbo antes de confiar na proveniência do `.app`.

## 9. NOT_RUN — o que esta rodada **não** mediu

Dito em uma seção própria, para ninguém ler o resto do relatório como cobertura completa:

- **Teste do alvo do app (`FeedMineAppTests`)** — `NOT_RUN`: quatro tentativas, quatro bloqueios de ambiente, sem
  veredito (§6).
- **Captura de tela do aparelho** — `NOT_RUN` e **impossível neste host**: `idevicescreenshot` não inicia
  `screenshotr` e não existe janela de espelhamento. O que a tela mostrava durante a jornada não foi medido; o que
  o console e o container dizem, foi.
- **Jornada longa com rolagem real, consumo/energia, e `media_resident` sob liberação de pixels** — `NOT_RUN`: o
  instrumento não injeta gesto nenhum (por princípio) e a corrida não teve janela móvel (§7).
- **Release rodando no aparelho** — `NOT_RUN`: a checagem de custo em Release é a varredura de cadeias nos bytes do
  `.app` (§5), não uma corrida no telefone com o binário de Release.
- **`com.feedmine.app` (TestFlight do dono)** — não é lacuna, é proibição: **nunca** instalado, lançado, terminado,
  apagado nem lido; o script o recusa por duas vias independentes (`scripts/device-journey.sh:170-171` e `:182-183`)
  e só **imprime** se ele continua instalado, a partir de `device info apps` (leitura).
- **`--namespace none`** e reuso de namespace — `NOT_RUN`: não exercitados nesta rodada; a corrida foi `--namespace
  auto` (§4), então o caminho que mistura histórico do container compartilhado não foi medido, só documentado.
