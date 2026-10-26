# A referência congelada do benchmark de aceitação

O runner recusa correr se o **manifesto do corpus** ou o **hash do avaliador** mudaram desde o congelamento
(`MANIFEST.sha256`, `EVALUATOR.sha256`). Este arquivo registra cada mudança do avaliador e por quê — uma régua que
muda em silêncio não mede nada.

## Insumos (corpus): congelados em 2026-10-10

`bench/corpus/` — catálogo, itens, mídia, perfis e critérios. Nenhuma dessas mudanças toca o corpus: os totais
medidos (2.305 fontes, 15.917 itens, 270 pares duplicados, 75 revisões materiais) continuam os mesmos, e o
manifesto continua válido.

## Avaliador: versão 2 — a jornada vigente (2026-10-10, noite)

O product owner alinhou B01/B02 ao PRD de F02: os dois assuntos são declarados **dentro do feed**, depois da
orientação de idiomas e lugares, e as duas fases (feed neutro / feed após as respostas) são observadas
separadamente. O avaliador mudou para medir essa jornada:

|Mudança|Por quê|
|---|---|
|`oracle.py`: B01 mede o **conjunto de aquisição** (`acquisition_target_sources`), não as fontes consultadas | as fontes registradas, as efetivamente buscadas e as que chegaram aos cards são **três estados**; o relatório passou a imprimi-los separadamente |
|`oracle.py`: B02 fica **NOT_RUN** sem a fase temática caminhada | B02 mede o feed **depois** das duas respostas; sem elas, o feed neutro seria outra medição |
|`oracle.py`: a execução sem banco legível é **NOT_RUN** com a razão, não um erro | um aparelho que sumiu no meio é uma medição ausente; o relatório não pode se perder |
|`run.sh`: o runner **nomeia o perfil** (`TEST_RUNNER_FEEDMINE_BENCH_PROFILE`) | sem isso as duas passagens rodariam o mesmo perfil e a cláusula "outro perfil muda as fontes consultadas" seria falsa por construção |
|`run.sh` + `DiscoveryBenchmarkTests`: o registro de fases vai do container do runner ao result bundle (`tearDown` → anexo `phases`) e o `run.sh` o extrai nos **dois** modos | o driver registra as fases que **realmente** caminhou, e fase não caminhada não vira PASS; nenhuma escrita do runner nomeia caminho do host — a que nomeava bloqueou em `open(2)` (medido 2026-10-26) |
|`DiscoveryBenchmarkTests`: a jornada é a vigente (idiomas e lugares → feed → duas respostas no feed); perfil sem país não responde lugar; perfil B acrescenta resposta negativa e reversão; a geometria ao esconder as dicas é medida | o contrato mudou; o driver segue o contrato, e nunca injeta preferência nem escolhe fonte por caminho exclusivo de teste |

O relatório de cada execução traz a identidade dos insumos (os hashes de `EVALUATOR.sha256`), o commit e o número
de arquivos sujos — uma execução nunca é comparável sem isso.

## Avaliador: versão 3 — a prontidão lida onde ela está (2026-10-11)

O B03 (`bench/run/20261011T043906Z`) publicou `candidatos: 871` com `pendentes: 0, texto: 0, preparados: 0` — a
distribuição virava zero porque o oráculo lia a prontidão na chave errada do evento. O traço a aninha em
`fields` desde que a instrumentação passou a registrar transições. Corrigido **sem tocar em critério, limiar ou
corpus**, e re-julgado sobre a **mesma** execução: 871 candidatos, **871 `preparados`**. Um veredito não é
retroagido por ler-se certo o que o traço já dizia; a correção vale para as execuções seguintes.

## 2026-10-11 — o caminho de aparelho do runner

`bench/run.sh` ganhou um modo de aparelho físico, e `DiscoveryBenchmarkTests.swift` deixou de depender de um
caminho de corpus do host. O selo do avaliador foi regerado de propósito ao fim desta entrada, e é esta a razão:

- **Destino parametrizado.** `FEEDMINE_BENCH_DEVICE_UDID` seleciona `platform:iOS,id:`; sem ele, o runner é o
  mesmo de antes (`platform=iOS Simulator,name:`). Todos os desvios são guardados por `MODE`.
- **Injeção e assinatura.** O catálogo do corpus continua sendo injetado no bundle do app; num aparelho isso
  invalida a assinatura que o Xcode acabou de fazer, e a instalação falha com `ApplicationVerificationFailed`
  apontando para o `Info.plist` e não para a causa. O runner agora re-assina com os entitlements que o próprio
  build gerou. Ver `docs/v1-study/PORT_LOG.md` §67.
- **ATS e Rede Local.** No simulador o transporte é o loopback; num aparelho é um IP da LAN, e desde o iOS 17 o
  ATS **recusa endereços IP por padrão**. O runner passa a declarar o endereço como chave de `NSExceptionDomains`
  (sem porta), mantém `NSAllowsLocalNetworking` como declaração de intenção, e adiciona
  `NSLocalNetworkUsageDescription` — uma conexão TCP de saída para um endereço de LAN exige o privilégio de Rede
  Local (TN3179), e sem ele a falha é silenciosa.
- **Servidor alcançável.** `serve.py --host 0.0.0.0` no modo aparelho, com o corpus da variante de transporte
  (`bench/device/corpus`), verificada contra o seu próprio manifesto antes da corrida.
- **O caminho de volta.** Não existe visão do container de dados pelo host; `devicectl device copy from` o
  endereça por caminho relativo, então o banco é puxado para a mesma forma de diretório que o simulador usa.
- **Captura.** Não há `simctl` num aparelho; as capturas do driver são anexadas ao result bundle e exportadas
  dele.

E a mudança no driver, que é a que mais importa para a integridade: **ele não lê mais o corpus do disco**. O
driver usava o corpus para uma única coisa — `profiles.json`, os rótulos que ele responde ao Composer. Um
caminho de host funcionava no simulador apenas porque um simulador lê o filesystem do Mac; num aparelho esse
caminho não existe. O alvo de teste agora carrega `profiles.json` como recurso e o driver o resolve do próprio
bundle, o que faz os dois modos percorrerem **um só caminho** em vez de dois que diferem exatamente onde o
benchmark mede.

## 2026-10-11 (2) — as fases, e o hash do que foi empacotado

O arquiteto confirmou a opção (a) e apontou três furos; esta entrada registra a mudança correspondente no driver,
que está sob este selo.

- **`FEEDMINE_BENCH_PHASES` era um segundo caminho do host.** O runner apontava para um arquivo no Mac e o driver
  escrevia nele com `try?` — decisão deliberada, para um disco cheio não derrubar o runner — de modo que num
  aparelho a escrita simplesmente falhava **em silêncio** e o oráculo recebia um registro ausente. Agora: quando o
  runner não nomeia caminho, o driver escreve dentro do **próprio container** e o `tearDown` **anexa o registro ao
  result bundle** (`lifetime = .keepAlways`, porque a vida útil padrão apaga anexos em caso de sucesso — que é
  exatamente o caso que isto existe para registrar). O runner extrai o anexo para o lugar onde o oráculo sempre leu,
  então o caminho do oráculo não muda e não há descoberta de container. (A variável foi **removida** em 2026-10-26: o
  caminho do host deixou de existir nos dois modos — ver a última entrada deste arquivo.)
- **Recusa em vez de fallback silencioso.** `FEEDMINE_BENCH_CORPUS`, quando definido, é honrado; se o
  `profiles.json` dali não for legível, o driver **recusa antes de qualquer medição** — uma corrida cujos rótulos
  vieram de outro lugar não é a corrida que foi pedida.
- **Hash do que foi efetivamente empacotado.** A verificação de `profiles.json` é feita sobre o arquivo dentro do
  test bundle construído, contra o manifesto congelado, e não sobre o arquivo de origem.

## 2026-10-11 (3) — correção de medição em B05

**O que estava errado:** a reabertura de B05 herdava `FEEDMINE_SKIP_ONBOARDING=0` do primeiro lançamento da corrida
(deliberado ali, porque a jornada de B01 *começa* no portão). O portão de primeira execução voltava a ser apresentado
sobre um feed já restaurado, como `fullScreenCover`, e a cláusula `b05-reopen-keeps-saved` acabava consultando o
controle do feed **por baixo da cobertura** — resultado dependente do tempo, não do produto.

**A prova de que era medição, não produto:** a instrumentação mostrou o id salvo no conjunto e na janela na mesma
chamada (`hits=1`) e o card do feed construído com `isBookmarked=true`; a segunda construção do mesmo id com `false`
vem de `ReaderOnboardingView`, com falso fixo. E a corrida instrumentada **passou**.

**O que muda, e só isso:** a reabertura passa a dizer o que é — `FEEDMINE_SKIP_ONBOARDING=1`, exatamente como o
comentário do próprio app convida (*"a run that is testing something else says so and keeps the gate out of the way"*)
e como o relançamento offline do mesmo teste já fazia. E a superfície do leitor é identificada **antes** de consultar
seu controle: a ausência do portão é aguardada como ausência, não presumida.

**O que NÃO muda:** a exigência de identidade do salvo, a de reabertura, a de bloqueio real de transporte e qualquer
critério. A cláusula afetada fica registrada como **medição inválida** nas corridas anteriores, e **não** é convertida
retroativamente em PASS; o B05 é medido de novo, inteiro.

## 2026-10-11 (4) — o traço bruto do simulador passa a ser preservado

**O que estava errado:** o diretório da corrida guardava relatório, veredictos, registro de fases, captura e identidade
— mas **não o traço bruto**. No simulador o oráculo lia `trace.jsonl` **no lugar**, dentro do container de dados do
app, e o caminho de aparelho era o único que puxava o namespace de volta. O container é substituído a cada
reinstalação do app, então o traço sobrevive só até a próxima build.

**Custo medido:** a corrida de B03 (`20261011T174453Z`) produziu **uma** paralisação de 1,56 s em t+343,77 s, e a
pergunta do arquiteto — *havia próximo card pronto e alcançável, ou o leitor ficou sem oferta?* — não tinha mais de
onde ser respondida: o traço já não existia. É exatamente o que o conselheiro fixou como requisito — *"preservar build
SHA, hashes, trace bruto e classificação de cada cláusula"*.

**O que muda:** os **dois** modos copiam o namespace para dentro da corrida antes de julgar, e o oráculo recebe a
**cópia**, não o container vivo. O aparelho já fazia isso via `devicectl`; o simulador passa a fazer com uma cópia
local. A forma do destino é a mesma nos dois casos, então os caminhos que o oráculo constrói a partir de `--database`
não mudam.

**O que não muda:** nenhum critério, nenhuma cláusula, nenhuma classificação. É preservação de evidência — o que não
pode ser reconstruído não deve ficar onde pode ser destruído.

## 2026-10-11 (5) — a injeção passa a levar o par

**O que estava errado:** o runner substituía o catálogo do bundle pelo do corpus e **deixava o descritor do
bootstrap**. O app verifica o arquivo que o descritor declara — tamanho e SHA-256 —, então a corrida não media "o
app com o insumo do benchmark": media **um app degradado**, e sem dizer. Medido em B05
(`20261011T182906Z`): `outcome: rejected`, `reason: size mismatch for catalog.sqlite: declared 117993472, present
3719168`, seguido de `outcome: deferred, "serving the bundled catalogue unverified"` — e as três aberturas do app
registraram o mesmo.

**O que muda:** a injeção escreve **o par**. O descritor passa a descrever o corpus honestamente — o tamanho real, o
digest real e a contagem que o `catalog_metadata` do próprio corpus declara (`source_count`), que é o número que o
leitor do produto reporta. A revisão segue 5, porque o corpus é uma fatia da revisão 5 e o diz na mesma tabela.

**O que não muda:** nenhum critério, nenhuma cláusula, nenhuma classificação. É a harness que passa a dizer a verdade
sobre o que injeta — a mesma regra que o pipeline já escreveu para si: *"o descritor e o catálogo que ele declara são
um par"*.

## 2026-10-26 — o registro de fases sai do host nos dois modos, e o result bundle deixa de ser apagado

**O que estava errado (medido):** `run.sh` pré-criava `$OUT/<gate>-<profile>.phases` no Mac e passava o caminho ao
runner por `TEST_RUNNER_FEEDMINE_BENCH_PHASES`, **só** no modo simulador. Duas execuções de B03
(`20261026T085541Z`, `20261026T100032Z`) pararam no **primeiro** `record` da jornada: a main thread do
`FeedMineUITests-Runner` ficou 46 min dentro de `open(2)` — `record(_:to:)` → `-[NSConcreteFileHandle
initWithURL:flags:createMode:error:]` → `_NSOpenFileDescriptor` → `open` —, o arquivo de fases ficou em 0 byte,
nenhum swipe foi enviado e o traço do app não recebeu nenhum evento `advance`. O app estava vivo e publicando nas
duas. Controlos: o mesmo inode aberto pelo shell em 0,000 s; sem negação de `tccd`/`sandboxd` nas janelas dos dois
travamentos (zero linhas); `~/Documents` é diretório comum, sem flags, sem xattr e sem domínio de File Provider;
disco com GB livres. A razão **no kernel** não está estabelecida — o que está é a operação que bloqueia, e que ela
era a **única** escrita do runner para um caminho que não é dele.

**O que muda:** o registro de fases vai para o container do próprio runner **nos dois modos**
(`FileManager.default.temporaryDirectory`, sem variável de ambiente que nomeie caminho), é anexado ao result bundle
no `tearDown` (`keepAlways`) como já era no aparelho, e o `run.sh` extrai o anexo com **o mesmo código** nos dois
modos para o mesmo `$OUT/<gate>-<profile>.phases` que o oráculo lê. O `run.sh` não pré-cria mais o arquivo: sem
anexo, a fase não existe e o portão lê NOT_RUN, nunca PASS. Um `<gate>-<profile>.transport.log` registra o que o
transporte fez (exportação, extração, linhas/bytes, ou a razão da ausência).

**Evidência que deixava de existir:** `$OUT/derived` (≈1 GB de produtos de build, regeneráveis) era apagado no fim do
run e levava junto o `.xcresult` de cada portão — medido: as duas corridas travadas perderam o único relato do
runner, e o detalhe do XCUITest além do log do portão não sobreviveu. Agora o bundle é movido para
`$OUT/<gate>-<profile>.xcresult` antes da limpeza, junto do diretório de anexos exportados; os produtos de build
continuam sendo apagados.

**O que NÃO muda:** nenhum critério, limiar, corpus, duração, gesto ou cláusula do oráculo. `bench/oracle.py`,
`bench/serve.py`, `bench/corpus/**`, `bench/MANIFEST.sha256` e os critérios congelados ficam byte a byte como
estavam; o selo `bench/EVALUATOR.sha256` é regerado apenas para `bench/run.sh` e para o driver, e o congelamento
anterior está verbatim em `bench/revisions/`.

**Risco residual conhecido (um portão por invocação):** o `run.sh` resolve o result bundle por
`ls -dt "$OUT/derived/Logs/Test/"*.xcresult | head -1`. Com mais de um `--gate` na mesma invocação, um portão cujo
`xcodebuild` morresse antes de escrever o bundle resolveria para o bundle do portão anterior, e a fase dele cairia no
`<gate>-<profile>.phases` errado. Rode **um portão por invocação** até que o caminho seja nomeado
(`-resultBundlePath`). O endurecimento não foi aplicado na revisão de 2026-10-26 porque o selo tem de continuar sendo
o instrumento que produziu o veredito medido; está registrado em `docs/reviews/2026-10-26-b03-instrument-transport.md`.
