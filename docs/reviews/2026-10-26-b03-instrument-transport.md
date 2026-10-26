# B03 — revisão do instrumento: o registro de fases sai do caminho do host (2026-10-26)

Nota de revisão do **instrumento** do benchmark de aceitação, não do produto. Antecede a medição: o
instrumento é corrigido, revisado e congelado aqui; a execução de B03 medida depois entra no fim
deste arquivo, sem alterar critério nenhum.

## Defeito

Duas execuções de B03 (`bench/run/20261026T085541Z`, `bench/run/20261026T100032Z`, mesmo SHA, mesmo
corpus, namespaces distintos) pararam no **primeiro** `record(_:to:)` da jornada e leram NOT_RUN com
0 avanços. A main thread do `FeedMineUITests-Runner` ficou 46 minutos dentro de `open(2)`:

```
walkTheFirstRunJourney — DiscoveryBenchmarkTests.swift:544
record(_:to:)         — DiscoveryBenchmarkTests.swift:479
-[NSConcreteFileHandle initWithURL:flags:createMode:error:]
_NSOpenFileDescriptor
open                  — libsystem_kernel.dylib
```

(`sample` de 2026-10-26 02:54:14 local, pid 21378 — 785 de 785 amostras nessa pilha.)

A operação bloqueada é a única escrita do runner para um caminho que não é o próprio: o `run.sh`
pré-criava `$OUT/<gate>-<profile>.phases` no Mac e passava o caminho por
`TEST_RUNNER_FEEDMINE_BENCH_PHASES`, **somente** no modo simulador. O modo aparelho nunca teve essa
escrita — lá o driver grava no próprio container e o `tearDown` anexa o registro ao result bundle.

O app nunca foi o bloqueio: nas duas corridas ele estava vivo, publicando (726 e 713 cartas, 130 e
123 fontes) e a primeira tela estava preenchida.

## O que foi descartado, com o comando

| hipótese | verificação | resultado |
|---|---|---|
| negação de sandbox/TCC | `log show` nas janelas dos dois travamentos, `process == "tccd" OR process == "sandboxd"` | 0 linhas |
| prompt de TCC pendente para `~/Documents` | `log show`, `eventMessage CONTAINS Documents AND (tcc OR prompt OR sandbox)` | 0 linhas |
| iCloud / File Provider materializando | `ls -ld ~/Documents`, `fileproviderctl`, `brctl status` | diretório comum, nenhum domínio |
| flags / xattr / inode | `lstat` do diretório e do arquivo | `flags=0x0`, sem xattr, `st_size=0` |
| espaço em disco | `df -h /` | GB livres |

**A razão no kernel não está estabelecida** e não é afirmada aqui. O que a revisão usa é o que foi
medido: o syscall que bloqueia, a operação que o executa, e o fato de que o outro modo não a executa.

## Correção (transporte de evidência)

1. **Driver**: o registro de fases vai para `FileManager.default.temporaryDirectory` — o container do
   runner — **nos dois modos**. Nenhuma variável de ambiente nomeia caminho. `tearDown` continua
   anexando (`XCTAttachment`, `lifetime = .keepAlways`, nome `phases`). `record(_:to:)` cria o arquivo
   quando ele não existe (o `run.sh` deixou de pré-criá-lo) e continua sem lançar: um disco cheio custa
   a fase, nunca o runner.
2. **`bench/run.sh`**: `TEST_RUNNER_FEEDMINE_BENCH_PHASES` e a pré-criação do `.phases` desaparecem;
   os anexos do result bundle são exportados e `phases` é extraído **nos dois modos pelo mesmo
   código**, para o mesmo `$OUT/<gate>-<profile>.phases` que o oráculo sempre leu. O que o transporte
   fez fica em `$OUT/<gate>-<profile>.transport.log` (arquivo, extração, linhas/bytes, ou a razão da
   ausência).
3. **Ausência não é PASS**: sem anexo não existe `.phases`, e `walked_phases` devolve `[]` — o portão
   lê NOT_RUN. Antes, um `.phases` de 0 byte pré-criado era indistinguível de "o transporte falhou".
4. **Evidência**: cada `.xcresult` é movido para `$OUT/<gate>-<profile>.xcresult` antes de
   `rm -rf "$OUT/derived"`. A limpeza continua apagando os ~1 GB de produtos de build (regeneráveis),
   e deixa de apagar o único relato do runner — que as duas corridas travadas perderam.

## O que NÃO muda

Critério, limiar, corpus, duração, gestos, cláusulas e lógica do oráculo. `bench/oracle.py`,
`bench/serve.py`, `bench/build_corpus.py`, `bench/expand.py`, `bench/corpus/**` (incluindo
`criteria.json`), `bench/device/**` e `bench/MANIFEST.sha256` ficam byte a byte. O corpo de
`testB03ThirtyMinuteRunway` (1.800 s, 1 avanço/s, rajadas de 3/s por 20 s a cada 300 s) não foi
tocado. Nenhum fonte de produto foi tocado; `capacity-ready.json` não foi lido nem alterado.

## Congelamento

O congelamento anterior está preservado verbatim em `bench/revisions/`
(`EVALUATOR-pre-phases-transport.sha256`, `run-pre-phases-transport.sh`,
`driver-pre-phases-transport.swift`), e o selo vigente `bench/EVALUATOR.sha256` muda **apenas** nas
linhas de `bench/run.sh` e do driver. Os hashes novos estão registrados abaixo e foram fixados antes
de qualquer medição de produto.

## Revisão independente

Revisor de família distinta do autor (agente `reviewer`, `openai-codex/gpt-6.1-sol`), somente
leitura, sem executar build nem benchmark. Escopo: régua congelada intacta, transporte de fases nos
dois modos, ausência de fase nunca virando PASS, idiomática bash sob `set -euo pipefail`, preservação
do `.xcresult`, e correção do `record` quando o arquivo não existe.

**Resultado: dois achados, nenhum de régua; um corrigido, um registrado como pré-existente.**

1. **Selo (`P1`, corrigido).** O selo `bench/EVALUATOR.sha256` ainda tinha os hashes antigos, e o
   `run.sh` recusa a corrida (exit 3) antes de qualquer portão. Regerado para `bench/run.sh` e para o
   driver; `shasum -a 256 -c bench/EVALUATOR.sha256` = 6/6 `OK`. As quatro linhas restantes (oráculo,
   `serve.py`, `build_corpus.py`, `expand.py`) são **byte-idênticas** às do congelamento anterior.
2. **B02 sem registro de fases (`P2`, pré-existente, não alterado).** O revisor apontou que um B02
   sem `.phases` pode ler PASS. Confirmado no código congelado, e é **deliberado**:
   `gate_b02` julga a fase temática pela **evidência** do banco ("*The phase is judged by evidence: the
   reader's own stored answers … A phase name in the trail is not proof that the reader declared
   subjects*", `bench/oracle.py:288-292`), não pelo registro do driver. O mesmo `[]` chegava ao oráculo
   antes desta revisão (o `run.sh` pré-criava um arquivo de 0 byte, e `walked_phases` devolve `[]` para
   arquivo ausente e para arquivo vazio), então o achado não é criado pelo transporte novo. Fechá-lo
   exigiria mudar a régua congelada, que esta revisão não faz. O que esta revisão faz é não deixar a
   diferença implícita: os três modos de falha do transporte (`no-result-bundle`,
   `attachment-export-failed`, `no-phases-attachment`) ficam escritos em
   `$OUT/<gate>-<profile>.phases-missing`, no `transport.log` e no `report.md`.
3. **`mv` do bundle abortava o run (aplicado).** O revisor notou que um `mv` falho, sob `set -e`,
   encerraria o script antes do oráculo e do relatório. Agora o `mv` é tolerante: perder o bundle custa
   a evidência, nunca o veredito nem o relatório.

Confirmado pelo revisor, além desses pontos: só os três arquivos do instrumento mudaram; régua, corpus,
fontes de produto e carga de B03 intactos; mesma destinação de fases nos dois modos; `record` cria o
arquivo, não lança, e o anexo continua `phases`/`keepAlways`; nenhum resto de `FEEDMINE_BENCH_PHASES`,
`.shots` ou `PHASES_ASSIGN`; `bash -n` limpo; bundles e anexos sobrevivem à limpeza e os produtos de
build continuam sendo apagados.

## Hashes congelados antes da medição

| insumo | SHA-256 |
|---|---|
| `bench/run.sh` | `b027007d0fc7b2e3cb097b3f36e062738592f025bfb68b3f2bbb21fb30160b80` |
| driver `DiscoveryBenchmarkTests.swift` | `c3ae03a40d6c03353fad25f8aaa7891a33cc62bdbc8e6bb6bcf5893de8eaac7e` |
| `bench/EVALUATOR.sha256` (selo vigente) | `shasum -a 256 -c` = 6/6 OK |
| `bench/MANIFEST.sha256` (corpus + serve + build) | inalterado |

<!-- RESULTADO DA MEDIÇÃO -->
