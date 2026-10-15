# Ocorrências vermelhas de `testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates`

Registro exigido pelo arquiteto depois de a terceira ocorrência aparecer durante a medição do PD10-P0A.
Nada aqui reabre o gate: o estado continua **FLAKY — ROOT CAUSE UNDETERMINED**.

## 1. As duas primeiras (2026-10-14, árvore `1b990306`)

| # | quando | árvore | execução | literal |
|---|---|---|---|---|
| 1 | 17:03 | `1b990306` | suíte `CompositionTests` completa | `CompositionTests.swift:180: XCTAssertEqual failed: ("18") is not equal to ("17") - Anchor plus a sixteen-card idle reserve` |
| 2 | 17:05 | `1b990306` | idem | idem |

Condição ambiental: a máquina rodava, em paralelo, as suítes de verificação das outras branches
(`mk15`, `mk14`, `mk15k14`), com builds concorrentes no worktree `/tmp/fm-verify`.
Janelas decisivas versionadas em `decisive/red-cand.composition{,2}.txt`.

## 2. A terceira (2026-10-15, árvore `122ef5d5` — PD10-P0A antes do ajuste de compilação)

| campo | valor |
|---|---|
| quando | 2026-10-15, `05:01:04.136` (hora local) |
| árvore | `122ef5d52fb6e045bfc038c0de2a4373c1708014` (branch `chatgpt/pd10-p0a-sync-contract`, primeiro commit) |
| worktree | `/tmp/fm-pd10a` (recém-criado, `detach` em `122ef5d5`) |
| comando | `xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination "platform=iOS Simulator,id=16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE" "-only-testing:FeedMineAppTests/CompositionTests"` |
| resultado | `Executed 57 tests, with 1 failure (0 unexpected)` — `Test Suite 'CompositionTests' failed` |
| literal | `CompositionTests.swift:217: error: -[FeedMineAppTests.CompositionTests testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates] : XCTAssertEqual failed: ("18") is not equal to ("17") - Anchor plus a sixteen-card idle reserve` |
| condição ambiental | a mesma máquina tinha acabado de rodar `swift build`/`swift test` (que **falhou por compilação** — o defeito do consumidor de `.manifest`) e a restauração do insumo `catalog.sqlite` do worktree; a suíte do app rodou logo depois, com o processo de build recém-encerrado |
| nota | os outros 4 testes PD10 do app passaram nessa mesma execução; a única falha foi esta |

## 3. As duas repetições verdes (mesma árvore de app, `5d02f8d7`)

| # | quando | resultado | caso |
|---|---|---|---|
| 1ª | 05:21:53 | `Executed 57 tests, with 0 failures`, `** TEST SUCCEEDED **` | passed |
| 2ª | serial, máquina ociosa | idem, zero falhas | passed |

## 4. Placar honesto

- 15 execuções limpas (4 base + 6 instrumentadas + 5 sob carga induzida) **sem** nenhuma reprodução.
- 3 execuções vermelhas conhecidas: **todas** em condição de máquina ocupada (builds/suítes concorrentes),
  duas em `1b990306` (17:03/17:05) e uma em `122ef5d5` (05:01).
- 2 repetições verdes seguidas na mesma árvore de app depois da terceira ocorrência.
- Conclusão mantida: **FLAKY — ROOT CAUSE UNDETERMINED**; a asserção de 17 segue intacta, o commit
  diagnóstico `4a05a182` não entrou em `main`, e nenhum PASS foi declarado.

## 5. A quarta ocorrência (2026-10-15, árvore `e15ef6b3` — candidato de aceite do PD10-P0B)

| campo | valor |
|---|---|
| quando | 2026-10-15, segunda execução serial da mesma medição (manhã, hora local) |
| árvore | `e15ef6b36606a613e2336c28f19b22bfaef8d92c` (branch `chatgpt/pd10-p0b-active-catalog-recovery`, candidato de aceite) |
| comando | `xcodebuild test … "-only-testing:FeedMineAppTests/CompositionTests"` (2ª das duas execuções seriais) |
| resultado | `Executed 60 tests, with 1 failure (0 unexpected)` — `** TEST FAILED **`; a 1ª execução da mesma árvore passou com 0 falhas |
| literal | `testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates` : `XCTAssertEqual failed: ("18") is not equal to ("17") - Anchor plus a sixteen-card idle reserve` |
| condição ambiental | a máquina acabara de rodar `swift build` + `swift test` (1330 testes) e a primeira suíte do app; a segunda execução foi serial, sem build em paralelo |
| nota | os sete testes PD10 passaram nas duas execuções; a única falha foi esta |

**Placar do G-18F nesta árvore: 1 verde / 1 vermelha em 2 execuções.**

### Placar acumulado das ocorrências

| # | quando | árvore | condição |
|---|---|---|---|
| 1 | 2026-10-14 17:03 | `1b990306` | builds/suítes concorrentes |
| 2 | 2026-10-14 17:05 | `1b990306` | builds/suítes concorrentes |
| 3 | 2026-10-15 05:01 | `122ef5d5` | build recém-encerrado + restauração de insumo |
| 4 | 2026-10-15 (2ª execução serial) | `e15ef6b3` | após `swift test` completo e a 1ª suíte do app |

Estado mantido: **FLAKY — ROOT CAUSE UNDETERMINED**. Nenhuma dessas ocorrências foi atribuída a branch ou a produto; as 15 execuções limpas do G-18F e as duas repetições verdes posteriores seguem registradas acima.

## 6. A quinta ocorrência (2026-10-15, árvore `40bc9fa1` — quinta passada do PD10-P0B)

| campo | valor |
|---|---|
| quando | 2026-10-15, segunda das duas execuções seriais da medição do candidato |
| árvore | `40bc9fa1d514781561393d844763a0b46052cd4a` (branch `chatgpt/pd10-p0b-active-catalog-recovery`) |
| comando | `xcodebuild test … "-only-testing:FeedMineAppTests/CompositionTests"` (2ª execução) |
| resultado | `Executed 60 tests, with 1 failure (0 unexpected)` — `** TEST FAILED **`; a 1ª execução da mesma árvore passou com 0 falhas |
| literal | `CompositionTests.swift:289: error: -[FeedMineAppTests.CompositionTests testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates] : XCTAssertEqual failed` |
| condição ambiental | a máquina acabara de rodar `swift build` + `swift test` (1353 testes) e a primeira suíte do app; a segunda execução foi serial |
| nota | os **sete** testes PD10 passaram nas duas execuções; a única falha foi esta |

**Placar nesta árvore: 1 verde / 1 vermelha em 2 execuções** (a vermelha já é a **5ª ocorrência conhecida**).

### Placar acumulado

| # | quando | árvore | condição |
|---|---|---|---|
| 1 | 2026-10-14 17:03 | `1b990306` | builds/suítes concorrentes |
| 2 | 2026-10-14 17:05 | `1b990306` | builds/suítes concorrentes |
| 3 | 2026-10-15 05:01 | `122ef5d5` | build recém-encerrado + restauração de insumo |
| 4 | 2026-10-15 (2ª execução serial) | `e15ef6b3` | após `swift test` completo e a 1ª suíte do app |
| 5 | 2026-10-15 (2ª execução serial) | `40bc9fa1` | idem: após `swift test` (1353) e a 1ª suíte do app |

Estado mantido: **FLAKY — ROOT CAUSE UNDETERMINED**. Nenhuma ocorrência foi atribuída a branch ou a produto; as 15 execuções limpas do G-18F seguem registradas acima.

## 7. Taxa medida no corpus completo de logs (extraído em 2026-10-15)

Todas as execuções da suíte do app que existem nos logs desta máquina, agrupadas por **sequência de
execuções seriais por árvore** (`xcodebuild … -only-testing:FeedMineAppTests/CompositionTests`):

| rodada (árvore) | 1ª execução | 2ª execução |
|---|---|---|
| `pd10b3` (`a983b019`), `pd10b4` (`3caef142`), `pd10b6` (`91a63b33`), `pd10b7` (`6c19e4b6`), `pd10b8` (`0a142da3`) | 60/0 | 60/0 |
| `pd10c` (`fe476ad4`, P0C), `pd10d` (`b0cab431`, P0C) | 60/0 | 60/0 |
| `pd10r` | 57/0 | 57/0 |
| **`pd10b5` (`e15ef6b3`)** | 60/0 | **60/1 — o G-18F** |
| **`pd10e` (`40bc9fa1`)** | 60/0 | **60/1 — o G-18F** |

Somando as 15 execuções **únicas** da campanha do G-18F (4 base + 6 instrumentadas + 5 sob carga induzida,
todas verdes) e as duas vermelhas antigas de `1b990306`:

- **2 vermelhas em 26 execuções** da suíte do app nesta máquina (~8%);
- **ambas na 2ª posição** de um par consecutivo, com a máquina **ociosa** — o único trabalho simultâneo era a
  própria suíte que acabara de rodar. As ocorrências 1–3 tinham "máquina ocupada" como explicação plausível;
  **as ocorrências 4 e 5 não têm**;
- 11 outros pares de execuções ficaram integralmente verdes.

Isso **não** prova um efeito de segunda execução (com ~8% de taxa, dois acertos na casa "run 2" aconteceriam
cerca de 1 vez em 4), mas **derruba** a atribuição "intermitência de máquina ocupada" para as ocorrências 4 e
5. O experimento decisivo proposto (e ainda não executado) é repetir a suíte **5× num mesmo SHA fixo** e ver
se a falha se concentra na 2ª/últimas posições — o que distinguiria **contaminação de estado entre execuções**
(reprodutível, investigável) de **corrida aleatória** (que exigiria estimar a taxa com mais amostras).
