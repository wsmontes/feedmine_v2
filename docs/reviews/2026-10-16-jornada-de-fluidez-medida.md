# Jornada de rolagem e evidência de quadros — revisão em andamento (2026-10-16)

> **Correção do ORCH nesta revisão:** o texto abaixo registra o experimento anterior, não certifica a árvore
> atual. O agente foi interrompido por ENOSPC; não há commit final nem validação completa desta revisão.
> O teto `90 severe / 0,25 / 250 ms`, derivado de quatro corridas mais uma margem escolhida de 30%, foi retirado
> da proposta: ele pode aceitar engasgos evidentes e não demonstra a qualidade pedida pelo dono.
> O teste proposto agora exerce rolagem, exige mudança do ponto de leitura e anexa a série e screenshot, sem
> declarar fluidez aprovada. A série DEBUG não aloca histórico em Release. A mudança de aceitação foi submetida
> ao arquiteto; **fluidez NOT_CERTIFIED, B06 NOT_RUN** até prova própria no aparelho.
> Build e teste desta proposta: **NOT_RUN neste ponto do registro**; os resultados históricos abaixo não os
> substituem. A aprovação do teste de rolagem não será apresentada como aprovação de desempenho.


Base: `2202cdd8`. Branch: `fix/fluidity-journey` (o WIP `a7cc70a7`, preservado quando o disco encheu, foi retomado
e reescrito num commit único). Ambiente: macOS arm64 (darwin 25.3.0), Xcode 26.6 (`17F113`), iOS SDK 26.5, Swift 6.
Simulador próprio desta rodada: **"FeedMine Fluidity"**, iPhone 17 Pro Max / iOS 26.5, UDID
`4E312E42-2743-4080-9984-1E36125574E3` — criado para esta jornada e **deletado ao fim**; nenhum outro simulador foi
tocado (`xcrun simctl shutdown all` nunca foi usado). Aparelho físico: **iPhone 14 Plus** do dono
(`BBA4F656-A5EA-5D81-934E-E484ED71B8E2`).

Nenhum arquivo de `bench/**` foi modificado, nenhum oráculo, nenhum critério congelado. O `catalog.sqlite`
empacotado (117.993.472 bytes) e `bench/corpus/profiles.json` foram **copiados** para o worktree (ambos gitignored)
porque o alvo de UI os referencia como recurso — sem eles o build falha em `CpResource`.

## 1. O que estava em jogo

`FeedFrameMeter` mede quadro a quadro desde 2026-10-14 e escreve uma linha por segundo no traço do app, mas
**nenhum teste lia o número**. A jornada J21 ("escala e fluidez no aparelho físico") estava na lista de lacunas, o
`scripts/soak.py` declara `"hitches": "Not measured"` e o B06 segue `NOT_RUN`. O dono paga o custo dessa cegueira:
a doutrina dele é "nenhum engasgo ao rolar", e nada no repositório reprovava um engasgo.

## 2. O que foi medido, e o que a medição mostrou

Cada achado abaixo nasceu de uma corrida, não de uma leitura de código.

**(a) Dois orçamentos de quadro no mesmo arquivo.** O `flush` escrevia `budget_ms=1000/60` no traço, enquanto os
buckets julgavam `link.targetTimestamp - link.timestamp`. Medido na série que o app publica: o alvo do display é
**16,67 ms** no simulador *e* **16,67 ms** no iPhone 14 Plus (`budget_ms=16.67` na linha do console). É por isso
que a constante *parecia* certa: nos dois ambientes em uso os dois números coincidem. Num painel de 120 Hz o traço
declararia 16,67 ms enquanto os buckets julgavam 8,33 ms — o mesmo quadro seria "no orçamento" no registro e "dois
orçamentos perdidos" na contagem. Defeito latente, agora impossível: há uma função só
(`FeedFrameMeter.budgetMilliseconds(target:)`) e o registro recebe o número que julgou.

**(b) A publicação da série para a árvore de acessibilidade congelava.** A primeira versão empurrava a string para
um `UILabel` dentro de um `UIViewRepresentable` (`label.text = série`). Medido numa jornada de 120 s: o app
escreveu **110 janelas** no próprio traço (`Application Support/FeedMine/6A45C195-…/trace.jsonl`, um evento
`frames` por segundo, 00:31:05→00:32:54) enquanto a árvore de acessibilidade continuou servindo **a janela 1** —
com `XCUIElement` guardado e com consulta nova a cada leitura, os dois lados liam `seconds=1`. Repetiu na corrida
seguinte (120 janelas no traço de `9F9BECE2-…`, 00:37:58→00:39:58, e `seconds=1` na árvore). A instância que a
árvore servia não era a que recebia as escritas. O canal passou a ser um `Text` do SwiftUI sobre um `@Observable`
minúsculo: ler a propriedade **é** a leitura, e o estado é lido só pelo overlay de 1×1 (uma reavaliação por
segundo, nunca do feed).

**(c) O medidor parava com a tela e só voltava por tabela.** `background()` chama `frameMeter.stop()`;
`foreground()` não chamava `start()` — a medição só retomava por efeito colateral do `install()` alcançado pelo
restore/reativação. Um foreground que não passe por ali (falha em `activateCurrentPresentation`, o early-return
`guard active, !launching`) deixaria o medidor parado pelo resto da vida do processo. Agora o par é simétrico:
`foreground()` chama `start()`, que é idempotente (`guard link == nil`).

**(d) O leitor guardava o retrato.** O `probe` do teste relia o mesmo `XCUIElement`; a série avança uma vez por
segundo. Toda leitura agora resolve a consulta de novo (`app.staticTexts[…]` outra vez) — e o passo do polling é
1 s, não 0,25 s, porque a série muda a 1 Hz.

**(e) A fronteira exata do bucket.** O caso de teste do WIP afirmava `severe` para 50 ms num painel de 60 Hz: 50 ms
são **exatamente** três orçamentos de 16,67 ms e a régua é `>` estrito, e um quadro dessa duração perde **dois**
quadros. O caso passou a medir a fronteira: 50 ms é `bad`, 51 ms é `severe`.

**(f) A API documentada da Apple tem dois becos e nenhuma medição neste ambiente.** `XCTHitchMetric` (iOS 26) não
implementa os ganchos **opcionais** do `XCTMetric` — chamá-los derruba o teste com
`-[XCTHitchMetric willBeginMeasuring]: unrecognized selector sent to instance` — e `reportMeasurements(from:to:)`
sozinho estoura com `Invalid parameter not satisfying: _startDate`, porque a métrica exige a medição conduzida
pelo harness (`measure(metrics:)`). Conduzida pelo harness (duas variantes: com `manuallyStart/manuallyStop` e com
as opções padrão), ela **não deixa medição nenhuma** no bundle de resultados neste simulador:
`xcrun xcresulttool get test-results metrics` devolve `[]`, e o JSON do bundle não menciona nenhum identificador de
métrica. A testemunha está armada e o lado do app é gravado junto (ver §7), mas **não há número da Apple para
comparar aqui** — é o ambiente, não o medidor.

## 3. Correções (owners)

| Arquivo | O que mudou |
| --- | --- |
| `FeedMineApp/FeedMineApp/FeedFrameMeter.swift` | um orçamento só (`budgetMilliseconds(target:)`, usada pelos buckets **e** pelo registro); `Window` (frames/late/bad/severe/worst_ms) e `recent` (até 120 janelas) em vez de contadores soltos; `bucket(intervalMilliseconds:budgetMilliseconds:)` puro e testável; a linha do console carrega `budget_ms`; `publishedSeries` — a série como ela é lida; a publicação passou de `UILabel` a `@Observable` + `Text` |
| `FeedMineApp/FeedMineApp/FeedMineApp.swift` | overlay `topLeading` com `FeedFrameEvidenceSurface()` (só em `DEBUG`) |
| `FeedMineApp/FeedMineApp/AppComposition.swift` | `foreground()` reinicia o medidor (o outro lado de `background()`) |
| `FeedMineApp/FeedMineAppTests/FluidityJourneyUITests.swift` | **novo**: a jornada, o controle e a testemunha |
| `FeedMineApp/FeedMineAppTests/CompositionTests.swift` | `FeedFrameBudgetTests`: o orçamento é do display, o mesmo intervalo é julgado pelo painel em que chegou, e o registro declara o orçamento que julgou |

Nada de timer, cron, fila ou máquina de estados: o medidor já existia e é um `CADisplayLink`; o que se acrescentou
foi um leitor.

## 4. A linha de base, e o teto derivado dela (nunca escolhido)

Medida: a **própria jornada**, quatro corridas em 2026-10-16, no simulador desta máquina
(`-only-testing:FeedMineUITests/FluidityJourneyUITests/testScrollingTheFeedKeepsTheFramesTheBaselineHeld`), trecho
**rolado** (janelas 6–16 de cada corrida, ~190 cartas, gestos `swipeUp(velocity: .fast)` por 10 s):

| corrida | janelas | quadros | late | bad | severe | razão | pior ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 11 | 404 | 3 | 3 | 69 | 0,1856 | 168,8 |
| 2 | 11 | 434 | 5 | 4 | 69 | 0,1797 | 172,5 |
| 3 | 11 | 416 | 5 | 8 | 66 | 0,1899 | 189,9 |
| 4 | 11 | 401 | 4 | 5 | 70 | 0,1970 | 193,9 |

Máximos: **70 severos, razão 0,1970, pior quadro 193,9 ms**. O teto é cada máximo com **~30% de margem**,
arredondado para cima: `severeFrames: 90`, `hitchRatio: 0,25`, `worstMilliseconds: 250`. A tabela e a margem vivem
no doc de `FluidScrollCeiling.journey`, ao lado do número — não há um teto redondo escolhido a dedo.

A derivação é auditável das quatro séries **cruas**, e não da tabela: cada linha abaixo é o trecho rolado
(janelas 6–16) da série que o app publicou, no formato `frames/late/bad/severe/worst_ms` em que ele publica. A
corrida 1 é a `raw_series` de `/tmp/fm-fluidity-j4.log`; as corridas 2–4 são as iterações 1–3 da corrida
`-test-iterations 3` de `/tmp/fm-fluidity-base3.log`.

```
1: 38/0/3/5/168.8|22/0/0/11/126.2|60/0/0/0/16.7|23/0/0/10/133.4|31/1/0/9/115.9|58/0/0/1/80.3|16/0/0/11/126.3|43/1/0/6/73.4|49/0/0/3/108.0|17/0/0/10/139.6|47/1/0/3/126.0
2: 27/1/1/9/162.9|43/0/0/7/62.6|54/0/1/3/63.6|19/1/0/11/172.5|48/2/0/4/67.9|49/1/1/3/95.1|13/0/0/13/137.3|58/0/0/1/57.8|39/0/1/5/139.2|26/0/0/12/68.1|58/0/0/1/63.7
3: 23/2/3/10/111.1|43/0/0/7/61.6|54/0/2/2/65.9|16/0/0/10/188.7|48/1/0/4/68.0|42/0/0/4/189.9|13/1/0/12/133.9|61/0/0/0/16.7|34/0/1/7/129.8|26/0/0/9/129.9|56/1/2/1/77.9
4: 30/1/1/9/136.7|37/0/0/8/112.7|52/0/2/2/62.8|16/0/0/11/131.9|45/0/0/4/120.2|47/1/1/4/78.0|15/0/0/10/124.2|49/1/0/4/65.5|40/1/1/6/79.0|16/0/0/10/193.9|54/0/0/2/69.0
```

Somando cada linha: 404/3/3/69, 434/5/4/69, 416/5/8/66, 401/4/5/70 — os quatro máximos da tabela saem daqui, e
não o contrário. A corrida 1 é a série que o controle (`measuredScrolledWindows`) alimenta na régua para provar que
o teto aceita quem o derivou.

O que essa linha de base **não** é: a fluidez do dono. Nas mesmas corridas o medidor viu segundos com 16 a 23
quadros (a máquina renderiza a 20–40 Hz enquanto o XCUI empurra uma edição de ~190 cartas) e a **pintura fria**
mediu pior quadro de 282 a 435 ms (17 a 26 orçamentos). No iPhone do dono, no mesmo medidor, o regime é outro:
razão **0,00045** (§6) — duas ordens de grandeza abaixo. O teto do simulador guarda **regressão**; a afirmação
sobre o que o dono sente pertence à medição do aparelho.

## 5. O controle

`testTheCeilingAcceptsTheBaselineAndRejectsColdPaintAndAStall` alimenta a **mesma régua** com séries **medidas** —
a saída crua da corrida está em §8. Quatro lados:

1. a rolagem que **derivou** o teto (as 11 janelas da corrida 1) passa: `hitch_ratio=0.1856 worst_ms=168.8` →
   `violations=[]`;
2. a **pintura fria** da mesma corrida (janelas 1–5) reprova: `pior quadro 435.3 ms (26.11 orçamentos) acima do
   teto 250.0 ms` — é isto que separa "o dono permite que a abertura seja lenta" de "a rolagem está lenta", e
   mostra que o teto não é vazio;
3. o pior quadro que o **aparelho do dono** produziu (377,9 ms, da telemetria do próprio app) reprova e o motivo
   nomeia o número: `pior quadro 377.9 ms (22.67 orçamentos) acima do teto 250.0 ms`;
4. o mesmo intervalo de 16,7 ms é **1,00 orçamento** num painel de 60 Hz e **2,00** num de 120 Hz — a razão pela
   qual a régua lê o orçamento da série em vez de uma constante.

## 6. A medição no aparelho (iPhone 14 Plus)

Comandos (na ordem):

```sh
# 1. build Debug iphoneos da branch (assinado com "Apple Development: wmontes@gmail.com")
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -configuration Debug \
  -destination "platform=iOS,id=BBA4F656-A5EA-5D81-934E-E484ED71B8E2" \
  -derivedDataPath /tmp/fm-fluidity-device-dd -allowProvisioningUpdates build

# 2. instalar como o bundle de desenvolvimento (o container do dono é com.feedmine.app e nunca foi tocado)
xcrun devicectl device install app --device BBA4F656-A5EA-5D81-934E-E484ED71B8E2 \
  /tmp/fm-fluidity-device-dd/Build/Products/Debug-iphoneos/FeedMine.app

# 3. capturar o que o app publica no console (a série é uma linha por segundo; SIGTERM ao devicectl é
#    encaminhado ao app, e é assim que a captura termina)
timeout 150 xcrun devicectl device process launch --device BBA4F656-A5EA-5D81-934E-E484ED71B8E2 --console \
  --terminate-existing \
  -e '{"FEEDMINE_RUNTIME_NAMESPACE":"96B970A3-5EBB-4F2E-843B-6823FC116BA8","FEEDMINE_SKIP_ONBOARDING":"1",
       "FEEDMINE_USE_DEVELOPMENT_FEEDS":"1","FEEDMINE_LOCAL_FEEDS":"1"}' \
  com.feedmine.development
```

Proveniência do que foi medido: o bundle instalado é o construído no passo 1, e o `Info.plist` **dele** diz
`FeedmineGitSHA = a7cc70a7`, `FeedmineGitBranch = fix/fluidity-journey`, `FeedmineBuildDate =
2026-10-16T07:59:51Z`, `CFBundleVersion = 47`; a árvore de bytes do `.app` (1.567 arquivos, 156.774.764 bytes,
caminhos + conteúdo, na ordem) tem `sha256 = fdabe11dae18013f350a892ec4fb86ef573efd769a1780befd79b249e23f92aa`.
O carimbo é do WIP `a7cc70a7` porque o build saiu do worktree com as mudanças ainda não commitadas; o commit
publicado tem o **mesmo conteúdo de trabalho** (a diferença é o carimbo).

**Série crua do aparelho (148 janelas, uma por segundo, `frames/late/bad/severe/worst_ms/budget_ms`)** — o que
aqui está é a linha do console, sem reamostragem:

```
01:02:55 frames=1  late=0 bad=0 severe=1 worst_ms=148.3 budget_ms=16.67
01:02:56 frames=44 late=0 bad=0 severe=3 worst_ms=152.6 budget_ms=16.67
01:02:57 frames=60 late=0 bad=0 severe=0 worst_ms=16.7  budget_ms=16.67
… (146 janelas seguintes: frames=60 em 64 delas, frames=61 nas outras 82, late=0 bad=0 severe=0,
   worst_ms entre 16.7 e 22.5 — nunca chegando a 1,5 orçamento, que é onde começa o `late`) …
01:05:22 frames=61 late=0 bad=0 severe=0 worst_ms=16.7  budget_ms=16.66
```

Totais das 148 janelas: **frames_total=8887, late=0, bad=0, severe=4, worst=152,6 ms**, razão de engasgo
**0,00045**. Os 4 quadros severos estão **todos** nas duas primeiras janelas (148,3 ms e 152,6 ms: a pintura fria
do lançamento). Da terceira janela até a última — 146 segundos seguidos — **nenhum quadro passou de 1,5
orçamento**: zero `late`, zero `bad`, zero `severe`, e o pior intervalo do trecho em regime é 22,5 ms (1,35
orçamentos). O orçamento publicado pelo aparelho é o alvo do display: `16.67` (e `16.66`, o mesmo número com
ruído de ponto flutuante).

Comparação com a linha de base que o dono já tinha medido em uso normal (`frames_total=31479 late=5 bad=0
severe=25 worst=377,9 ms`, razão 0,00095 — registrada em `docs/reviews/2026-10-15-build-47-e-jornadas-no-aparelho.md`,
linha 51): a mesma ordem de grandeza, e o pior quadro daquela medição (377,9 ms)
está do mesmo lado da fronteira que os 4 severos daqui — a abertura. **Limite declarado:** nesta captura não houve
gesto nenhum: esta máquina não injeta toque no aparelho (não há espelhamento nem captura de tela, e `devicectl`
não tem gesto). A série acima é o app em primeiro plano com o feed em tela. A rolagem real do dono é a corrida
dele (`31479` quadros); a minha é repetível e é a que diz que o caminho console→série funciona no aparelho, com
o orçamento certo.

## 7. A testemunha independente

`testApplesHitchMetricWitnessesTheSameScroll` mede o **mesmo** trecho com as duas testemunhas: o `CADisplayLink`
do app (série publicada, lida antes e depois) e o `XCTHitchMetric` da Apple, conduzido pelo harness
(`measure(metrics:options:)`, `iterationCount=1`). Resultado medido: a corrida passa (33 s, os 8 gestos das duas
passagens do bloco), a série do app cobre o intervalo, e o lado da Apple **não tem número neste ambiente** — o
bundle de resultados sai sem nenhuma métrica (§2f). O caso existe para que a comparação apareça sem mudança de
código no dia em que o ambiente publicar o número (por exemplo numa corrida no aparelho); hoje ele registra a
série do app como anexo e não afirma nada sobre a Apple. **NÃO HÁ** comparação entre as duas testemunhas aqui:
declaro `NOT_RUN` para esse lado, com a razão exata medida.

## 8. Verificação

```sh
swift build
swift test
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination "platform=iOS Simulator,id=4E312E42-2743-4080-9984-1E36125574E3" \
  -derivedDataPath /tmp/fm-fluidity-derived -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
git diff --check
```

Nenhuma corrida foi feita em paralelo com outra corrida de medição, e nenhuma corrida morreu por disco: `df -h /`
foi conferido antes de cada etapa pesada (≥5,6 GiB livres), o DerivedData fica em um caminho só e é removido no
fim.

## 9. Limites

- **Sem gesto no aparelho** (§6): a medição do iPhone é o app em primeiro plano, não a rolagem do dono.
- **`XCTHitchMetric` sem número** neste simulador (§2f, §7): a comparação está armada, não executada.
- O teto do simulador é sensível a esta máquina: as quatro corridas concordaram (66–70 severos), mas ele deve ser
  re-derivado se a jornada ou o ambiente mudarem — e o lugar de re-derivar é a tabela de
  `FluidScrollCeiling.journey`, não uma margem nova inventada.
