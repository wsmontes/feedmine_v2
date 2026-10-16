# HS-02 — o share do export sobe na folha que o pede (não no feed atrás dela)

Branch: `fix/hs-02`, criada de `main` (`c9d599eb`, o commit imediatamente posterior a `baf10e2d`).
Worktree: `/tmp/fm-hs02` (o checkout canônico ficou intocado, em `feat/journey-instrument`).
Data: 2026-10-16.

## 1. O defeito, medido (não é hipótese)

Tocar **Compartilhar** — e **Salvar arquivo**, que escreve o mesmo `sharedExport` — não apresentava a
superfície de compartilhamento do sistema enquanto a folha de exportação do app estava no ar. A
apresentação era **adiada**, não recusada: fechando a folha do app, a superfície do sistema aparecia
**4 s** depois.

- Reprodução: `xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination
  id=<simulador> -derivedDataPath /tmp/fm-honest2-dd -parallel-testing-enabled
  NO "-only-testing:FeedMineUITests/FeedMineUITests/testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint"`.
  A corrida é a do ORCH, na estação antiga, no **simulador que ela própria bootou** — mas com a *derived data*
  **do agente** (`/tmp/fm-honest2-dd`): a *derived data* **não** era própria (correção de 2026-10-16; a
  frase anterior dizia que era).
- Saída bruta: `/tmp/sharecheck-ORCH-repro.log` — **uma** sessão de teste, **uma** asserção falhada, 94,005 s,
  sempre a mesma:

```
/tmp/fm-honest2/FeedMineApp/FeedMineAppTests/FeedMineUITests.swift:662: error: -[FeedMineUITests.FeedMineUITests testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint] : XCTAssertTrue failed - Compartilhar must open the system's own share surface over the app's own sheet; measured on 2026-10-16: it does not (see the finding in this test's own documentation); on screen: … (a árvore de acessibilidade que a asserção imprime fica no log, fora do repositório)
```

e, 93,47 s depois do toque, o topo da árvore de acessibilidade ainda era a folha do app
(`export-share`, `export-save`, `export-done`, `export-preview` com o OPML real; nenhum
`ActivityListView`) — `/tmp/sharecheck-ORCH-repro.log:1117-1375`.

Contagem (corrigida em 2026-10-16): o relato conta **quatro reprodutores** do mesmo defeito — **três corridas
do agente** mais **uma do ORCH**. A versão anterior desta frase imprimia "4 observações" somando "duas
próprias mais três do agente", que dá cinco: erro de aritmética apontado pelo arquiteto, e a leitura
auto-consistente do total é 3 + 1. O que os logs disponíveis sustentam como reproduções **distintas** de
vermelho é **uma** antes de hoje (esta, a do ORCH) e **duas** contando o controle de hoje no commit-base
`c9d599eb` (§6). A revisão do próprio agente (`docs/reviews/2026-10-16-superficies-honestas.md` §3.1)
registra, à parte, seis corridas e um diagnóstico na mesma árvore — outra conta, mais larga, que não é esta.

O achado está relatado, com a discriminação entre "adiada" e "recusada",
em `docs/reviews/2026-10-16-superficies-honestas.md` §3 (essa revisão está correta para o commit que
ela descreve: "nada foi corrigido"; esta é a correção).

## 2. A propriedade que dirigiu a correção (arquiteto, verbatim)

> Quando o usuário toca Compartilhar ou Salvar arquivo, o sistema apresenta a ação solicitada **naquele
> fluxo**, sem exigir outra ação inesperada. Cancelar devolve o usuário ao contexto anterior, sem perder
> a leitura.
>
> É esse comportamento que deve dirigir a implementação e o teste, **não a quantidade de `.sheet` que o
> SwiftUI permite declarar.**

## 3. Diagnóstico (leitura de código, antes de qualquer mudança)

Todas as apresentações do host pendiam da **mesma** view — o `NavigationStack` raiz do feed —, cada uma
num modificador irmão:

| linha em `main` | apresentação | apresentador |
|---|---|---|
| `FeedMineApp.swift:311` | `.sheet(isPresented: $showsPlayer)` | a view raiz |
| `FeedMineApp.swift:319` | `.sheet(item: sheetItem)` — o host de "uma superfície por vez" (`.export` entre elas) | a view raiz |
| `FeedMineApp.swift:448` | `.sheet(item: $sharedExport)` → `ActivityView` | a view raiz |
| `FeedMineApp.swift:457` | `.sheet(item: $importPreview)` | a view raiz |
| `FeedMineApp.swift:478` | `.sheet(item: $sharedLink)` → `ActivityView` | a view raiz |

`Compartilhar`/`Salvar arquivo` (`FeedMineApp.swift:1111-1112` em `main`; `:1103-1104` depois deste
diff, `onShare`/`onSave` → `sharedExport = writtenExport()`) são pedidos **enquanto a folha de exportação está no ar**, e essa folha
é desenhada pelo mesmo apresentador (`.sheet(item: sheetItem)`, o `case .export`). O pedido chega, então,
a um apresentador que já tem uma apresentação em curso: o iOS **adia** o segundo pedido até o primeiro
sair — que é exatamente o que a medição mostra (o `ActivityListView` aparece 4 s depois de fechar a
folha de exportação).

## 4. A correção — o menor caminho

A apresentação passa a ser pedida **pela folha que a pede**: o `.sheet(item: $sharedExport)` saiu do
encadeamento da view raiz e passou para dentro do conteúdo da folha de exportação.

`FeedMineApp/FeedMineApp/FeedMineApp.swift` (depois; antes: `:448` no feed e `:1111-1112` no callback):

```swift
    @ViewBuilder private var exportSheet: some View {
        let choices = composition.exportChoices()
        NavigationStack {
            ReaderExportView(scopes: choices,
                ...
                onShare: { sharedExport = writtenExport() },
                onSave: { sharedExport = writtenExport() },
                onClose: { popSurface() })
                .task { ... }
        }
        // ... (o comentário do porquê, com a medição de 2026-10-16 citada)
        .sheet(item: $sharedExport) { link in     // FeedMineApp.swift:1129
            shareSurface(link)
        }
    }

    /// The platform's own share surface for a document or a link this app produced: one adapter, presented by
    /// whichever surface asked for it — the export sheet for the document it shows, the feed for a card's link.
    @ViewBuilder private func shareSurface(_ link: SharedLink) -> some View {   // FeedMineApp.swift:1136
        #if os(iOS)
        ActivityView(url: link.url, subject: link.subject)
        #else
        Text(verbatim: link.url.absoluteString).padding()
        #endif
    }
```

O caminho irmão do card (`sharedLink`, `FeedMineApp.swift:474`) **não** mudou de lugar: ele é
apresentado com o **leitor** no topo, não com uma folha no topo, e não exibe o sintoma — ver
`docs/reviews/2026-10-16-superficies-honestas.md:161-162`. O que mudou nele é só o corpo, que agora usa
`shareSurface(link)`: o `#if os(iOS)` estava duplicado em dois lugares e passaria a três, e o adapter é
um só em `PlatformSurfaces.swift:39` (`ActivityView`) — nada do que ele apresenta mudou.

O que **não** mudou, por regra desta tarefa: o conteúdo exportado (o OPML e o arquivo continuam sendo
produzidos por `composition.writeExport(exportRequest)`, `FeedMineApp.swift:1170-1173`, sem uma linha
tocada), o caminho do paste manual (`ReaderAddFeedViews.swift:239`/`:248-253`) e o estado de superfícies
do host (`present`/`pushReader`/`popSurface`, `FeedMineApp.swift:120-140`).

### 4.1 Por que isso é o que resolve (e não uma hipótese de estilo)

- **O pedido passa a ter outro apresentador.** Numa `.sheet` dentro do conteúdo de outra `.sheet`, o
  contexto de apresentação é o *view controller* que a folha de exportação já apresenta — que está
  apresentado e livre —, não a view raiz, que está com uma folha no ar. É o caso que o iOS atende na
  hora. `ActivityView` (`PlatformSurfaces.swift:36-49`) não mudou: é o mesmo
  `UIActivityViewController(activityItems: [url])`; muda quem o pede.
- **A propagação de estado até o conteúdo apresentado já é medida neste app.** O `previewText` da folha
  é o `@State exportText` do host, recomputado **dentro** da folha pelo `.task`
  (`FeedMineApp.swift:1109-1118`) e lido pela asserção do outro teste (`FeedMineUITests.swift:569`,
  `export-preview` com o OPML real) — ou seja, mudar estado do host depois da folha estar no ar
  re-renderiza o conteúdo da folha. É esse mesmo mecanismo que faz o `.sheet(item: $sharedExport)` agora
  dentro dela ver o valor e apresentar.
- **A folha que pede é a folha que volta.** Sair da superfície do sistema só desfaz a apresentação dela;
  a folha de exportação segue no ar (`export-done` continua endereçável, `FeedMineUITests.swift:694-695`)
  e o ponto de leitura do feed, que nunca saiu de baixo, é o mesmo.

### 4.2 O que é inferência, e o que vai ser medido

- `[INFERENCE]` Os itens de 4.1 são leitura de código e de comportamento documentado do SwiftUI; a
  confirmação é a corrida do teste (§6) — em especial (a) a superfície do sistema endereçável **com a
  folha do app no ar** e (b) a folha do app de volta depois de sair dela.
- `[INFERENCE]` O `app.otherElements["ActivityListView"]` (`FeedMineUITests.swift:850-851`) é
  identificador do próprio `UIActivityViewController`, independente de quem o apresenta; ele foi medido
  com a superfície apresentada pelo feed. Apresentada pela folha, espera-se o mesmo identificador —
  medido na corrida de §6.

## 5. O que mudou no teste, e por quê

`FeedMineApp/FeedMineAppTests/FeedMineUITests.swift` — a jornada que já existia,
`testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint`, e a irmã nova,
`testSavingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint`:

1. **A documentação do achado** (`:595-620`) deixa de dizer "nada aqui muda o app" e passa a registrar:
   o que foi medido em 2026-10-16 (mantido: é a evidência), a causa (apresentador ocupado), a correção
   (apresentação ancorada na folha que a pede) e a propriedade do arquiteto, verbatim, como o que
   dirige o teste.
2. **O `guard surfaced else { return }` saiu** (`main`: `let surfaced` em `:661`, a asserção que a
   nomeava em `:662-665`, o `guard` em `:668`). O guard existia por causa da
   premissa que falhava: ele transformava os quatro últimos fatos da jornada em medidas condicionais a
   uma superfície que nunca subia. Agora a premissa é do app — quem pede é quem apresenta — e a jornada
   mede a volta sem porta de saída própria. A asserção acima do guard continua sendo a falha que nomeia
   a regressão (não afrouxei nenhuma asserção: nenhuma foi removida ou teve limite diminuído).
   Custo aceito: numa build regredida, os limites generosos que já existiam (240 s + 240 s) passam a ser
   gastos antes do fim da jornada, em vez de a jornada terminar cedo com um `return` silencioso.
3. **A mensagem da falha** (`:678-679`) deixa de citar "measured on 2026-10-16: it does not" — que
   descrevia o defeito — e passa a nomear a propriedade: a superfície do sistema sobe *no fluxo que a
   pediu, sem outra ação antes*.
4. **A simultaneidade, medida nas duas jornadas** (`:687-689` e `:809-811`): enquanto a superfície do
   sistema está endereçável, `app.buttons["export-done"]` existe — o `Concluir` da folha do app
   (`ReaderImportExportViews.swift:128`), que tem **um** produtor só, de modo que a asserção não pode ser
   satisfeita por outro estado do app. É o fato que as outras asserções só alcançam por transitividade:
   uma apresentação que fechasse a folha primeiro e subisse depois passaria por todas as demais.
5. **O ponto de leitura medido como distância, e não só como identidade** (`:643-648` e `:718-725` na
   jornada do share; `:776-779` e `:838-844` na irmã): o `frame.minY` do cartão no topo contra a
   referência tirada antes do toque, `accuracy: 1` — a convenção que o arquivo já usa nas suas outras
   asserções de deslocamento (`:1760`, `:1806`). Uma mudança que deixasse o mesmo cartão no topo a outro
   offset passaria pela comparação de identidade.
6. **A jornada irmã, para a segunda porta** (`:728-845`): `Salvar arquivo` (`export-save`) é o **outro**
   controle que escreve o mesmo `sharedExport` (`FeedMineApp.swift:1103-1104`), e até agora ele aparecia
   em **zero** testes — a equivalência das duas portas era leitura de código. A irmã mede, no mesmo
   fluxo e com os mesmos ajudantes: a folha mostra o documento real, `Salvar arquivo` põe a superfície do
   sistema sobre a folha, a saída da plataforma devolve a folha, e fechá-la devolve o leitor ao ponto de
   leitura.

As asserções de ponto de leitura (`:714-717`) não foram tocadas: é o critério 2 da tarefa, e elas valem
agora porque o `guard` não as intercepta mais.

Em números, contra o commit-base `c9d599eb`: o arquivo fica em **174 inserções e 24 remoções**
(`c9d599eb → 090b8352` = 31/24, o WIP já commitado; `090b8352 → árvore de trabalho` = 143/0, o que este gate
acrescenta). Das 24 remoções, **18 são linhas de comentário `///`** (o bloco `:595-620` do base: o parágrafo do
achado foi reescrito e ampliado, não apagado em substância) e **6 são código**: `let surfaced =
systemSurface.waitForExistence(timeout: 60)`, o `XCTAssertTrue(surfaced, …)` que o consumia e o
`guard surfaced else { return }` — reescritos na árvore de trabalho em `:678` como
`XCTAssertTrue(systemSurface.waitForExistence(timeout: 60), …)`, **mesmo elemento e mesmo limite 60**. A
auditoria independente do acréscimo mede: sítios de asserção **462 → 486** (+24), nenhuma condição ou limite
alterado, e o histograma de limites só ganha contagens — nenhum valor perde ocorrências.

## 6. Evidência (executada, 2026-10-16)

Tudo abaixo foi **executado** nesta árvore, depois da autorização de build. O insumo dos medidores é o corpus
congelado: `bench/corpus/profiles.json` =
`24109941fee198e0ffb0b914fb9f23d01b0509ffcf7ffe691020b2c9ce0738f9` e `cd bench && shasum -a 256 -c
MANIFEST.sha256` → **0 FAILED** (`MANIFEST FAILED count=0`, `STATE=clean` — `/tmp/hs02-verify/fixture.log`,
133 B, 16:11:37). A corrida de `swift test` das **16:09** (`/tmp/hs02-verify/test.log`, 458 861 B) foi feita com
o corpus **regerado** e está **superada**: o fixture congelado só volta ao lugar às 16:11, e é esse o estado
que o cabeçalho de `test-after-fixture.log` registra.

Os logs completos ficam **fora do repositório** (`/tmp/hs02-verify/`, `/tmp/hs02-control/`, `/tmp/hs02-save/`)
e não entram no commit. De cada um, abaixo vai só a linha decisiva — sem as árvores de acessibilidade que as
asserções imprimem (`app.debugDescription`), sem caminhos de casa e sem caudas de log.

### 6.1 O verde da correção

1. **`swift build`** — `/tmp/hs02-verify/build.log` (39 070 B):

```
Build complete! (45.35s)
BUILD_EXIT=0
```

2. **`swift test`** (a rede de segurança do pacote) — `/tmp/hs02-verify/test-after-fixture.log` (408 240 B),
   com o skip nomeado pelo próprio log:

```
	 Executed 1400 tests, with 1 test skipped and 0 failures (0 unexpected) in 41.176 (41.301) seconds
…/Tests/FeedMinePersistenceTests/CatalogCompilerReferenceTests.swift:96: -[FeedMinePersistenceTests.CatalogCompilerReferenceTests testCompiledTreeMatchesTheReferenceCatalogueRowForRow] : Test skipped - set FEEDMINE_REFERENCE_FEEDS_ROOT and FEEDMINE_REFERENCE_CATALOG to compare a whole tree
```

   (o caminho do arquivo foi encurtado: o log traz o caminho absoluto da estação. O skip é o
   `CatalogCompilerReferenceTests.swift:96`, com `FEEDMINE_REFERENCE_FEEDS_ROOT` e `FEEDMINE_REFERENCE_CATALOG`
   não definidas — a corrida das 16:09 imprimia o mesmo skip e está superada pelo fixture.)

3. **As duas portas, uma jornada por corrida** — `xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj
   -scheme FeedMine -destination id=<simulador> -derivedDataPath /tmp/fm-hs02-dd
   -parallel-testing-enabled NO "-only-testing:FeedMineUITests/FeedMineUITests/<jornada>"` — verde nas duas,
   com os tempos impressos por elas mesmas (cada corrida no simulador que o próprio cabeçalho dela nomeia).
   `Salvar arquivo` (`/tmp/hs02-save/green.log`, 111 391 B):

```
export-save: system surface addressable 1.35 s after the tap
export-save: system's own close control reachable 1.77 s after the tap
export-save: reading point offset reference=209.4 final=209.4 pt
	 Executed 1 test, with 0 failures (0 unexpected) in 37.080 (37.082) seconds
** TEST SUCCEEDED **
```

`Compartilhar`, re-corrida depois do acréscimo (a medição de deslocamento é dela —
`/tmp/hs02-save/share-still-green.log`, 79 454 B):

```
export-share: system surface addressable 1.29 s after the tap
export-share: system's own close control reachable 1.69 s after the tap
export-share: reading point offset reference=218.1 final=218.1 pt
	 Executed 1 test, with 0 failures (0 unexpected) in 33.976 (33.978) seconds
** TEST SUCCEEDED **
```

Lido: a superfície do sistema fica endereçável **1,3 s a 1,8 s** depois do toque (o limite é 60 s), a própria
saída da plataforma aparece logo em seguida, e o topo do cartão **não se move** (referência e final iguais, em
pontos). A primeira corrida verde do share, antes do acréscimo das duas medidas, imprimiu o mesmo par de
tempos — `1.23 s` e `1.64 s`, `Executed 1 test, with 0 failures (0 unexpected) in 29.977 (29.978) seconds` —
em `/tmp/hs02-verify/uitest-after-fixture.log` (77 221 B).

### 6.2 O corte vermelho: as duas portas no commit-base `c9d599eb`

O controle é o mesmo teste contra o app do commit-base, nos dois worktrees de controle (`/tmp/fm-hs02-base`,
`/tmp/fm-hs02-base2`). `Compartilhar` — `/tmp/hs02-control/red-on-base.log` (898 864 B):

```
/tmp/fm-hs02-base/FeedMineApp/FeedMineAppTests/FeedMineUITests.swift:662: error: -[FeedMineUITests.FeedMineUITests testSharingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint] : XCTAssertTrue failed - Compartilhar must open the system's own share surface over the app's own sheet; measured on 2026-10-16: it does not (see the finding in this test's own documentation); on screen: … (a árvore de acessibilidade que a asserção imprime fica no log, fora do repositório)
	 Executed 1 test, with 1 failure (0 unexpected) in 88.938 (88.947) seconds
** TEST FAILED **
```

Nenhuma linha `export-share:` é impressa: a jornada para na premissa — a asserção acima é o primeiro fato dela,
e o `:662` é a jornada como o commit-base a tem (a mensagem ainda é a que descrevia o defeito).

`Salvar arquivo` — `/tmp/hs02-save/red.log` (971 350 B):

```
/tmp/fm-hs02-base2/FeedMineApp/FeedMineAppTests/FeedMineUITests.swift:802: error: -[FeedMineUITests.FeedMineUITests testSavingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint] : XCTAssertTrue failed - Salvar arquivo must open the system's own share surface over the app's own sheet, in the flow that asked for it and without another action first; on screen: … (árvore de acessibilidade: fica no log)
/tmp/fm-hs02-base2/FeedMineApp/FeedMineAppTests/FeedMineUITests.swift:823: error: -[FeedMineUITests.FeedMineUITests testSavingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint] : XCTAssertNotNil failed - the system's share surface must offer its own way out; on screen: … (árvore de acessibilidade: fica no log)
export-save: system surface addressable 61.75 s after the tap
export-save: system's own close control reachable 302.61 s after the tap
export-save: reading point offset reference=186.4 final=186.4 pt
	 Executed 1 test, with 2 failures (0 unexpected) in 336.840 (336.842) seconds
** TEST FAILED **
```

Lido: a superfície do sistema só fica endereçável **61,75 s** depois do toque — o limite de 60 s já tinha
passado — e a própria saída da plataforma só chega **302,61 s** depois, quando chega. As duas falhas são fatos
medidos: a jornada nova não tem `return` que a interrompa.

### 6.3 As três corridas de UI, uma linha cada

| corrida | log (fora do repositório) | tamanho | veredito | medida |
|---|---|---|---|---|
| **verde** — `Salvar arquivo` | `/tmp/hs02-save/green.log` | 111 391 B | `Executed 1 test, with 0 failures … 37.080 s` · `** TEST SUCCEEDED **` | superfície 1,35 s; saída da plataforma 1,77 s; deslocamento 209.4 → 209.4 pt |
| **verde** — `Compartilhar`, re-corrida | `/tmp/hs02-save/share-still-green.log` | 79 454 B | `Executed 1 test, with 0 failures … 33.976 s` · `** TEST SUCCEEDED **` | superfície 1,29 s; saída 1,69 s; deslocamento 218.1 → 218.1 pt |
| **vermelhos** — os dois controles no `c9d599eb` | `/tmp/hs02-control/red-on-base.log` (898 864 B) e `/tmp/hs02-save/red.log` (971 350 B) | — | `Executed 1 test, with 1 failure … 88.938 s` · `** TEST FAILED **` e `Executed 1 test, with 2 failures … 336.840 s` · `** TEST FAILED **` | `Compartilhar`: falha em `:662`, nenhuma linha `export-share:` (para na premissa). `Salvar arquivo`: falha em `:802` e `:823`, superfície a 61,75 s (limite de 60 s estourado) e saída a 302,61 s; deslocamento 186.4 → 186.4 pt |

A corrida de `swift test` das 16:09 (`/tmp/hs02-verify/test.log`) **não** entra nessa conta: ela usou o corpus
regerado e está superada pela das 16:11 com o fixture congelado.

## 7. Arquivos tocados

| arquivo | o que mudou |
|---|---|
| `FeedMineApp/FeedMineApp/FeedMineApp.swift` | `.sheet(item: $sharedExport)` sai do feed (`main:448`) e passa para dentro de `exportSheet` (`:1129`); o corpo duplicado do share vira `shareSurface(_:)` (`:1136`), usado também pelo card (`:474`); comentário do estado `sharedExport` (`:193-196`) |
| `FeedMineApp/FeedMineAppTests/FeedMineUITests.swift` | a jornada do share (documentação do achado/correção `:595-620`, asserção da superfície no fluxo `:678-679`, `guard` removido) **mais** a jornada irmã da segunda porta (`:728-845`), a **simultaneidade** medida nas duas (`:687-689`, `:809-811`) e o **deslocamento** medido como distância nas duas (`:643-648`, `:718-725`, `:776-779`, `:838-844`); contra o base `c9d599eb`, 174 inserções e 24 remoções (§5) |
| `docs/reviews/2026-10-16-share-do-export-na-folha-que-o-pede.md` | este relatório |

`FeedMineApp/FeedMineApp/PlatformSurfaces.swift` **não** foi tocado: o adapter já era o certo
(`PlatformSurfaces.swift:36-49`); o defeito era o apresentador.

O commit carrega exatamente esses três arquivos. O descritor do catálogo
(`FeedMineApp/FeedMineApp/Resources/catalog.manifest.json`) está modificado na árvore de trabalho **sem**
entrar neste commit: ele é da linha de release P0C e não tem parte neste gate.
