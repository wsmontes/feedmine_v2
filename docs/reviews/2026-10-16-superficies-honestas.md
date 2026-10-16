# Superfícies honestas: o banner de clipboard removido, e a jornada real de compartilhamento

**Data:** 2026-10-16 · **Autor:** agente `HonestSurfaces` (tarefa delegada pelo agente principal)
**Branch:** `fix/honest-surfaces-2`, worktree `/tmp/fm-honest2`, **base** `baf10e2d` (`origin/main`)

**O que este relatório responde.** Duas coisas: (1) o banner de clipboard — uma superfície que existia em
código e que **nada no app construía** — foi removido de verdade, com o caminho do paste manual que fica
citado por linha e intocado; (2) a única lacuna de fechamento que sobrava na bateria de UI — o controle
`export-share`, que os testes só **encontravam** (`exists`) e nunca **tocavam** — passou a ter uma jornada
real: ela toca o controle, exige que a superfície de compartilhamento **do sistema** suba sobre a folha do
app, sai por ela e confere que o ponto de leitura não mudou. Sem afirmar nada sobre o conteúdo da lista de
atividades, que é da plataforma.

## 0. Método, ambiente e limites (para poder desconfiar deste relatório)

| Item | Valor |
|---|---|
| Repositório | `feedmine_v2`, worktree `/tmp/fm-honest2`, branch `fix/honest-surfaces-2` |
| Base | `baf10e2d` — `origin/main` (`main` já publicado com o código da build 48) |
| Máquina | macOS 25.3.0 arm64 · Xcode 26.6 (17F113) · SDK iOS 26.5 |
| Simulador | device **criado por esta sessão**: `039F7AF6-0744-4DC6-8384-84685BB8D558` ("FeedMine Honest", iPhone 17 Pro Max, iOS 26.5). Os devices de outros agentes (`16DA3DB5` Bench, `7C4E3C51` Verify, `7420F436` OMP, `616105F9` Instrument) **não foram usados nem desligados** |
| Insumos do app | `FEEDMINE_USE_DEVELOPMENT_FEEDS=1`, `FEEDMINE_LOCAL_FEEDS=1`, `FEEDMINE_SKIP_ONBOARDING=1`, namespace novo por corrida — o fixture que o próprio app serve; nenhuma rede |
| Comandos | `swift build` · `swift test` · `xcodebuild test … -only-testing:FeedMineUITests/FeedMineUITests/testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint` · `git diff --check` · `git status --porcelain` |
| Corpus / congelados | `bench/oracle.py`, `bench/EVALUATOR.sha256`, `bench/MANIFEST.sha256`, o driver e os critérios **não foram tocados** (zero arquivos de `bench/` no diff) |

**Dois insumos gitignored que uma worktree nova não traz — e como eles foram instalados.** O build do alvo
do app falha explicitamente sem o par do catálogo (`FeedMineApp/FeedMineApp/Resources/catalog.sqlite` +
`catalog.manifest.json`) e o bundle de UI falha sem `bench/corpus/profiles.json`. Nenhum dos dois é
versionado. Em vez de rodar um script de preparação, os **bytes verificados que já existem nesta máquina**
foram instalados por clone APFS (`cp -c`), conferidos contra os descritores versionados:

| Insumo | Descritor que o declara | SHA-256 dos bytes instalados |
|---|---|---|
| `FeedMineApp/FeedMineApp/Resources/catalog.sqlite` (117 993 472 bytes) | `catalog.manifest.json` (`role: catalogue`) | `42e602341d18f47290b06615eb9d49a25a693e36f3e9a4c327bbecd83e923b66` |
| `bench/corpus/profiles.json` (964 bytes) | `bench/MANIFEST.sha256:6` | `24109941fee198e0ffb0b914fb9f23d01b0509ffcf7ffe691020b2c9ce0738f9` |

Os dois descritores batem byte a byte com os arquivos instalados, e **nenhum arquivo de `bench/` foi
modificado** — `profiles.json` é um insumo lido pelo bundle de UI, não uma entrada de benchmark.

## 1. O banner morto: removido, e o paste manual que fica

### 1.1 O que foi removido, e a prova de que era superfície morta

`Sources/FeedMineUI/Feedback/ClipboardBanner.swift` (62 linhas) foi **deletado**. Antes da remoção, a
varredura por `ClipboardBanner|clipboard-banner` em `Sources/`, `FeedMineApp/FeedMineApp/` e `Tests/`
devolvia **zero** call sites: o tipo existia, era público, e nada o instanciava — nem o host, nem o shell,
nem teste algum. Um controle que ninguém constrói é uma superfície que o leitor não tem: o cabeçalho do
próprio arquivo dizia "the host detects the link (T10 owns import) and states it here", e o host nunca o
fez. A decisão do arquiteto (2026-10-16) é literal — *"Clipboard: REMOVER, NÃO LIGAR"* — e remover é o que
este commit faz; ligá-lo teria sido inventar um fluxo que o produto não pediu.

### 1.2 O que fica: o paste manual, citado por linha e intocado

O paste manual é a via real, e **nenhum arquivo dela foi tocado** (o diff não inclui nenhuma das linhas
abaixo):

| Onde | Linha | O que é |
|---|---|---|
| `Sources/FeedMineUI/Tools/ReaderAddFeedViews.swift:120-126` | `private let clipboard: @MainActor () -> String?` e seu `init` | a view/store **nunca** lê a área de transferência; ela recebe a leitura como fechamento injetado |
| `Sources/FeedMineUI/Tools/ReaderAddFeedViews.swift:141-145` | `public func pasteFromClipboard()` | lê o fechamento **só** quando o leitor pede, e acrescenta o texto ao campo |
| `Sources/FeedMineUI/Tools/ReaderAddFeedViews.swift:239` | `add-feed-input` | o campo onde o endereço colado aparece |
| `Sources/FeedMineUI/Tools/ReaderAddFeedViews.swift:248-253` | `add-feed-paste` (`"Colar da área de transferência"`, `doc.on.clipboard`) | o gesto explícito do leitor |
| `FeedMineApp/FeedMineApp/AppComposition.swift:1064-1068` | `clipboard: { UIPasteboard.general.string }` | o host é o dono da superfície de plataforma, e a injeta |

**O que a bateria cobre disso, honestamente.** A folha de adicionar feed é exercida ponta a ponta por
`FeedMineUITests/testAddFeedByLinkDiscoversAddsAndReadsIt`, que **digita** o endereço
(`field.typeText("https://site.feedmine.test/")`) — o **botão de colar** (`add-feed-paste`) não tem teste
executado. Isso é uma lacuna registrada, não uma cobertura afirmada: ela ficou como estava antes deste
commit, e o banner removido nunca foi a via suportada de nada.

### 1.3 O que registrava o banner, atualizado

| Arquivo | Mudança |
|---|---|
| `docs/architecture/FILE_RESPONSIBILITIES.md:941` | a linha `Feedback` deixa de nomear `ClipboardBanner.swift` (um registro da árvore **viva** não pode nomear arquivo que não existe) |
| `docs/v1-study/PORT_LOG.md` | a linha do banner sai da tabela "What was copied"; entra um parágrafo "Ported and then removed — the clipboard banner" com a decisão, a data e o caminho do paste que fica |
| `docs/v1-study/UI_TRANSFER_MATRIX.md:276` | a linha do banner passa de `em transferência` para `removido`, com o motivo e as linhas do paste que fica; `:283-284` (totais da seção) acompanha |
| `Sources/FeedMineUI/Reader/ReaderShell.swift:3` | o cabeçalho do shell dizia que ele era dono do "clipboard banner"; a citação sai (era a última menção viva ao banner em código) |
| `docs/v1-study/UI_TRANSFER_MATRIX.md:110, :161` | o `proof` do `export` passa a citar também a jornada nova (a que **toca** `export-share`) |

## 2. A jornada real de compartilhamento

`FeedMineUITests/testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint` faz o que o §4 do
inventário (`docs/reviews/2026-10-15-jornadas-de-usuario-v1-vs-v2.md:281`) declarava faltar, e o que a
regra de fechamento da V1 exige (`1.0-application-closure-plan.md:30`, "do not ship dead buttons"):

1. abre o leitor no fixture local, rola de verdade e **exige** que a rolagem tenha completado uma
   oportunidade (`native-viewport-delivery`), para que o ponto de leitura seja um fato e não "o topo";
2. guarda os contadores da sessão e o card no topo do viewport (`topmostCardIdentifier`);
3. abre o menu do leitor e entra na folha de exportação;
4. exige que a folha mostre o **documento** (`export-preview` presente e `export-empty` ausente) e que
   `export-share` esteja **habilitado** — compartilhar um vazio não provaria nada;
5. **toca** `export-share`;
6. exige que a superfície de compartilhamento **do sistema** suba por cima da folha do app
   (`app.otherElements["ActivityListView"]`), anexa a captura e **imprime o tempo medido**;
7. sai pela própria saída que a superfície do sistema oferece e exige que ela **saia**
   (`waitForAbsence`), que a folha do app volte a ser a superfície de cima e que `export-done` a feche;
8. exige que os contadores da sessão sejam **os mesmos** e que o card do topo do viewport seja **o mesmo**
   — sair por uma superfície de plataforma não pode trocar a sessão nem mover o ponto de leitura.

**O que não é afirmado, e por quê.** O conteúdo da lista de atividades. O que ela oferece é da plataforma:
muda com o aparelho, com os apps instalados e com o idioma. Uma asserção sobre uma entrada seria uma
asserção sobre o iOS, não sobre este app. O que este app possui é o documento que escreveu e a apresentação
que pediu — e é isso que a jornada mede.

**Seletores independentes de idioma.** A jornada não consulta nenhuma palavra visível do menu: um item de
menu do SwiftUI carrega o **SF Symbol** como identificador e a string traduzida como rótulo — é o que o
próprio código registra em `Sources/FeedMineUI/Reader/ReaderMenu.swift:93-97`. Por isso a entrada de export
é alcançada por `app.buttons["square.and.arrow.up"]` e a folha é reconhecida por identificadores estáveis
(`export-preview`, `export-empty`, `export-share`, `export-done`). Medido: no simulador desta sessão o
idioma do device é **inglês**, e o menu diz `Export` — uma jornada que consultasse `"Exportar"` só passaria
num aparelho cujo idioma fosse o do idioma-fonte do app.

## 3. O achado de produto: a folha do app bloqueia a superfície do sistema

A jornada **reprova na sua premissa**, e a reprovação é a medida. `Compartilhar` **não** põe a superfície de
compartilhamento do sistema sobre a folha de exportação.

### 3.1 O que foi medido (seis corridas na mesma árvore)

| Corrida | Espera pela superfície | Superfície sobre a folha do app? | Evidência |
|---|---|---|---|
| 2ª (`uitest4`) | 20 s | não no prazo; apareceu depois de a folha do app sair | dump com `identifier: 'ActivityListView'` + `ShareSheet.RemoteContainerView` |
| 3ª (`uitest5`) | 90 s | idem | idem |
| 4ª–6ª (`uitest6`–`9`) | 150 s, 240 s, 240 s | **não** | dumps sem `ActivityListView`; folha do app no topo |
| 7ª (`uitest10`), simulador **apagado antes** (`simctl erase`) | 240 s | **não** | `export-share-system-surface.png` do `xcresult`: só a folha de exportação, com o OPML real na prévia |
| diagnóstico (run `diag`) | 30 s | **não** | e, 4 s depois de fechar a folha do app, **sim** |

Saída bruta do diagnóstico (a discriminação entre "adiada" e "recusada"):

```
export-share DIAGNOSTIC: surface over the app's own sheet within 30 s = false
export-share DIAGNOSTIC: after closing the app's own export sheet, platform surface = true
```

A captura `export-share-system-surface` da corrida em que a espera foi de 240 s (extraída do `.xcresult`
com `xcrun xcresulttool export attachments`) mostra a tela **inteira** como a folha de exportação do app —
`Export`, "What to export / My sources", a prévia com o OPML real (`<title>My sources</title>`,
`<outline type="rss" text="bbc-science" …/>`) e as duas ações `Share` / `Save file` — e **nenhuma** lista de
atividades. A imagem foi preservada em `/tmp/fm-honest2-240s-sheet-still-up.png` (277 411 bytes); como
`docs/evidence/` é gitignored, ela não entra no commit. A prova do outro lado da discriminação são as duas
linhas de `print` acima, no log `/tmp/fm-honest2-diag.log`, mais a captura que a mesma corrida tirou
**depois** de fechar a folha do app (aquela, com a superfície do sistema no ar).

### 3.2 Leitura

- **Adiada, não recusada.** O pedido de apresentação é feito e honrado: quando a folha do app sai do
  caminho, a superfície do sistema sobe em segundos. O que o leitor vê é o pior dos dois mundos: toca
  `Compartilhar` e **nada acontece**; a folha de compartilhamento aparece depois, quando ele abandona a
  folha de exportação.
- **Vale para `Salvar arquivo` também**, que escreve o mesmo `sharedExport`
  (`FeedMineApp/FeedMineApp/FeedMineApp.swift:1111-1112`).
- **Não é regressão deste commit.** O diff não toca `FeedMineApp.swift`, `AppComposition.swift`,
  `PlatformSurfaces.swift` nem `ReaderImportExportViews.swift`: a única linha de app alterada é um
  **comentário** de cabeçalho (`Sources/FeedMineUI/Reader/ReaderShell.swift:3`). O defeito é pré-existente e
  nunca foi exercido: a bateria só perguntava `export-share.exists` (`FeedMineUITests.swift:567`).
- **Causa provável (leitura de código, não medida — [INFERÊNCIA]).** A folha de exportação é desenhada pelo
  host de superfícies em `.sheet(item: sheetItem)` (`FeedMineApp/FeedMineApp/FeedMineApp.swift:319`) e a
  superfície do sistema por um **segundo** `.sheet(item: $sharedExport)` (`:448`) encadeado na **mesma**
  view. Uma segunda apresentação do mesmo apresentador enquanto a primeira está no ar é exatamente o caso
  que o iOS recusa/adia. O caminho irmão do card (`:478`, `.sheet(item: $sharedLink)`) é apresentado com o
  **leitor** no topo, não com uma folha no topo — e não exibe o sintoma.
- **Nada foi corrigido.** Por instrução da tarefa, o achado é relatado antes de qualquer tentativa de
  conserto, e nenhuma linha de app foi mudada para acomodá-lo.

### 3.3 A jornada, como ficou

`testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint` mantém a exigência **devida** — a
superfície do sistema **sobre** a folha do app — e por isso **reprova** nesta árvore; a falha é única, no
primeiro fato, e a jornada para ali (o resto mede a volta de uma superfície que precisa estar no ar). O
comentário do teste carrega o achado medido, com as corridas e as capturas, para que o vermelho seja
auto-explicativo em vez de parecer instabilidade. Saída bruta de uma das duas corridas da versão final
(a outra: `Executed 1 test, with 1 failure (0 unexpected) in 88.956 (88.960) seconds`, a mesma asserção):

```
error: -[FeedMineUITests.FeedMineUITests testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint] :
XCTAssertTrue failed - Compartilhar must open the system's own share surface over the app's own sheet;
measured on 2026-10-16: it does not (see the finding in this test's own documentation); on screen: …
Test Case '-[FeedMineUITests.FeedMineUITests testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint]' failed (87.744 seconds).
	 Executed 1 test, with 1 failure (0 unexpected) in 87.744 (87.746) seconds
** TEST FAILED **
```

O que **não** foi afirmado sobre a lista de atividades continua valendo: nada nela é asseverado — a
jornada mede a apresentação que o app pede e a volta do leitor, não o conteúdo da plataforma.

## 4. Verificação e limites

| Verificação | Comando | Resultado |
|---|---|---|
| Pacote, build | `swift build` | exit **0** (`/tmp/fm-honest2-build-final.log`) |
| Pacote, suíte | `swift test` | exit **0** — `Executed 1400 tests, with 3 tests skipped and 0 failures (0 unexpected) in 77.429 (77.646) seconds` (`/tmp/fm-honest2-test-final.log`) |
| App + jornada nova | `xcodebuild test … -only-testing:FeedMineUITests/FeedMineUITests/testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint` | exit **65** — `Executed 1 test, with 1 failure` (**o achado da §3**, não erro de teste) |
| Diff | `git diff --check` | vazio |
| Árvore | `git status --porcelain` | só os arquivos desta entrega; `bench/` intocado |
| Simulador | `xcrun simctl …` | device próprio `039F7AF6` ("FeedMine Honest", iPhone 17 Pro Max, iOS 26.5), apagado uma vez no meio da investigação; os devices de outros agentes não foram tocados |

**Sensibilidade medida ao ambiente (para poder desconfiar das medições acima).** A latência da superfície
do sistema, quando nada a bloqueia, variou de **4 s a ~90 s** conforme a carga da máquina (load average de
34 → 5 durante a sessão; houve janelas com um `xctrace` de outro agente rodando). É por isso que as esperas
da jornada são generosas e **declaradas**, e é por isso que a prova do achado **não** depende de tempo: a
discriminação "adiada × recusada" foi medida como diferença **de estado** (com a folha no ar: ausente; 4 s
depois de fechá-la: presente), não como diferença de espera.

**O que este relatório não prova.** (a) Nada foi medido em aparelho físico: o achado é de simulador, iOS
26.5. (b) A causa provável (§3.2) é leitura de código, não experimento: não se mediu um host corrigido.
(c) O botão de colar da folha de adicionar feed (`add-feed-paste`) continua sem teste executado (§1.2) —
lacuna registrada, não coberta aqui.

