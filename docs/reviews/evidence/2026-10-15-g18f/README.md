# G-18F — evidência do gate da intermitência (2026-10-15)

Gate autorizado pelo arquiteto para caracterizar a intermitência de
`FeedMineAppTests/CompositionTests/testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates`
("Anchor plus a sixteen-card idle reserve", 17 × 18 cards). Estado final: **FLAKY — ROOT CAUSE
UNDETERMINED**, 15 execuções verdes, nenhuma reprodução.

## Árvores medidas

| item | valor |
|---|---|
| Base (sem instrumentação) | `1b9903067b52614863de682eb9a3a7e2407fdb02` |
| Instrumentada | `4a05a182026b7cef0627c4b2a579b9d56d03df4f` (branch `chatgpt/g18f-reserve-diagnosis`; 1 arquivo de teste, 69+/3−; asserção intacta) |
| Simulador | `FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE)` |
| Comando | `xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination "platform=iOS Simulator,id=16DA3DB5-…" -only-testing:FeedMineAppTests/CompositionTests` |

## Resultado por grupo

| grupo | execuções | resultado | extrato |
|---|---|---|---|
| Linha de base, sem instrumentação | 4 | 4× `53 tests, with 0 failures` | `baseline/run1..4.txt` |
| Instrumentada, ociosa | 6 | 6× `53 tests, with 0 failures` | `instrumented/run1..6.txt` |
| Instrumentada, carga induzida (4 de 10 núcleos) | 5 | 5× `53 tests, with 0 failures` | `induced-load/run1..5.txt` |

## O que é bruto e o que é extrato

Os **logs completos** (1,2–2,3 MB cada, a maior parte linhas `feedmine frames=`) viviam em
`/tmp/fm-verify-logs/`, diretório descartável. O que está versionado aqui é **extrato filtrado** com as
linhas que sustentam o veredito — `[G18F]` (as seis fases instrumentadas), a asserção que falha, os
vereditos por caso e as linhas `[composition]` — acompanhado do tamanho, da contagem de linhas e do
**SHA-256 do log completo**, para que qualquer cópia sobrevivente seja identificável.

### Extratos da linha de base

| extrato | log original | bytes | linhas | sha256 do original |
|---|---|---|---|---|
| `baseline/run1.txt` | `g18f-baseline-run1.log` | 2267595 | 16238 | `7e0531a8e93fe4f46b65e2dd668344f22402841e933ed1813c03d392df903f8f` |
| `baseline/run2.txt` | `g18f-baseline-run2.log` | 1204770 | 10634 | `2b54c5efa5df4a3f3aa5f733ba083a7c1614e54d59e7ef1bd780fbdd03088c55` |
| `baseline/run3.txt` | `g18f-baseline-run3.log` | 1219819 | 10800 | `840b5a6908edc15a595e8ea93590f95bec271ed50c868016a6b7ad6258b2f76b` |
| `baseline/run4.txt` | `g18f-baseline-run4.log` | 1197349 | 10596 | `68e17b2432f79d56f5fc5225b8edaed73ea6eef4b3cf18a841bc7ed6013ffba4` |

### Extratos da árvore instrumentada

| extrato | log original | bytes | linhas | sha256 do original |
|---|---|---|---|---|
| `instrumented/run1.txt` | `g18f-instr-run1.log` | 1269721 | 10753 | `f8572759af63e8fac3e36a3d755c4f8075eaf212e46e2bdad320d0b4988cd4fc` |
| `instrumented/run2.txt` | `g18f-instr-run2.log` | 1230416 | 10732 | `a596c2056fe47ca92b590fe231c71aba6864723234c9e0b6dd78d58b2bc1c0be` |
| `instrumented/run3.txt` | `g18f-instr-run3.log` | 1233485 | 10758 | `d35e76fa7191cf6fdac56ce71c2dbeb1bc53aecb5a927cfc3205d65d678da41f` |
| `instrumented/run4.txt` | `g18f-instr-run4.log` | 1216009 | 10603 | `8fc6758546ae32875996e076a8d7ac5735fb895e4172e72bbd94539b2970292c` |
| `instrumented/run5.txt` | `g18f-instr-run5.log` | 1221855 | 10653 | `5c98a172cb59bd6e275a70cad8b41f8ca97d62140453a1fac95eb903a312a6d6` |
| `instrumented/run6.txt` | `g18f-instr-run6.log` | 1246669 | 10878 | `7b7b9c1b97d16723249b268702781300a4504f4d2a79084ac99c8d87717eb60d` |

### Extratos sob carga induzida

| extrato | log original | bytes | linhas | sha256 do original |
|---|---|---|---|---|
| `induced-load/run1.txt` | `g18f-load-run1.log` | 1294532 | 11218 | `6a947e36c998c4912364be42482e4e940ac70dab8a67972e3a2d703ea294a9d4` |
| `induced-load/run2.txt` | `g18f-load-run2.log` | 1262927 | 11020 | `cda4b36e5ca7ea934a09ef20eb5314eb50724e230c48005bca163d12f56c7893` |
| `induced-load/run3.txt` | `g18f-load-run3.log` | 1305753 | 11403 | `91c42e836890d2dcb1eb27e2370ebf90371ab520d66e95db1188f2f1a1cf0ce7` |
| `induced-load/run4.txt` | `g18f-load-run4.log` | 1269413 | 11078 | `a1aba146675132a89539ef9ebc5f6f17b2d382a1c4a78d966ccf7450a6ebc03a` |
| `induced-load/run5.txt` | `g18f-load-run5.log` | 1271941 | 11100 | `e5e134ac87a4780d93127ab0e80c1b2b88a9a81a3e0d7a077b6a28d027391cdb` |

### Janelas decisivas (suíte completa)

| extrato | log original | bytes | linhas | sha256 do original |
|---|---|---|---|---|
| `decisive/red-cand.composition.txt` | `cand.composition.log` | 1697630 | 12686 | `e1ae1eb12f348665c6923835bc4d25d391f1b9ecf547beaf20cdf93c9db18483` |
| `decisive/red-cand.composition2.txt` | `cand.composition2.log` | 1251474 | 10994 | `a28a687ab8fd301dd1da9266f3d525a5e02a4ab589bc63a7e1c3d12e8b75a2b1` |
| `decisive/green-trio-c01.composition.txt` | `trio-c01.composition.log` | 1293700 | 11017 | `c38b4d3e0c7ed4cb994baf160a6039825c59fbb45e8fab7c01f881ff5e630bf0` |
| `decisive/isolated-cand.fastfeed.txt` | `cand.fastfeed-isolated.log` | 1106616 | 6116 | `079e32c0b098e482ee118098891074629be97372ac7e80bbcce7667b88044f7f` |

## Leitura das janelas decisivas

- `red-cand.composition.txt` (17:03) e `red-cand.composition2.txt` (17:05): **as duas falhas conhecidas**, com
  `installed cards=18 … order=4` entre o `order=2/3` e o checkpoint de posição.
- `green-trio-c01.composition.txt` (17:52): mesma suíte, **verde**, 17 cards do início ao fim.
- `isolated-cand.fastfeed.txt` (17:41): o caso **isolado** passa — o que mostrou que o fenômeno é de suíte.

## O que este diretório NÃO prova

- Não reproduz o 18º card: nenhuma das 15 execuções o produziu.
- A carga induzida (`yes` em 4 de 10 núcleos) quase não mudou os tempos (187–200 s contra 177–185 s ociosos); **não** é a
  concorrência original de builds/simulador/disco.
- Nenhum PASS de produto; a asserção de 17 segue intacta e o commit diagnóstico **não** entrou em `main`.
