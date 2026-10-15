# G-18F — rodada da sequência-predecessora (2 rodadas, SHA congelado `40bc9fa1`)

Segunda medição autorizada pelo arquiteto em 2026-10-15, depois de a campanha 5+5 (`campaign-5plus5.md`) ter dado
10/10 verde **sem replicar o contexto precedente** das ocorrências 4 e 5. As duas vermelhas históricas tiveram,
entre o build e as execuções do app, a **suíte do pacote inteira**; esta rodada reproduz exatamente essa sequência.

## 1. Condições executadas

|Item|Valor|
|---|---|
|SHA congelado|`40bc9fa1d514781561393d844763a0b46052cd4a`|
|Árvore|worktree `/tmp/fm-pd10f` (o mesmo da campanha anterior, `--detach`, sem limpeza intermediária)|
|Simulador|`FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE)`|
|Paralelismo|desabilitado (`-parallel-testing-enabled NO`)|
|Sequência por rodada|`swift test` (suíte do pacote inteira) → app #1 → app #2|
|Concorrência externa|nenhuma medição concorrente|
|Alterações de código/critérios|nenhuma|
|Logs|`/tmp/pd10-g18f-pre/R{1,2}-{swifttest,app1,app2}.log` + `pre-runs.tsv`|

## 2. Resultado — 6 de 6 etapas verdes, exit 0

|rodada|etapa|início|dur (s)|exit|resultado|G-18F|
|---|---|---|---|---|---|---|
|1|`swift test`|12:03:47|167|0|`Executed 1353 tests, with 1 test skipped and 0 failures`|—|
|1|app #1|12:06:34|197|0|`Executed 60 tests, with 0 failures`|passed|
|1|app #2|12:09:53|192|0|`Executed 60 tests, with 0 failures`|**passed**|
|2|`swift test`|12:13:07|56|0|`Executed 1353 tests, with 1 test skipped and 0 failures`|—|
|2|app #1|12:14:03|195|0|`Executed 60 tests, with 0 failures`|passed|
|2|app #2|12:17:19|197|0|`Executed 60 tests, with 0 failures`|**passed**|

**Nenhuma falha de nenhum tipo em nenhuma das 6 etapas.**

## 3. O contexto precedente foi replicado (não aproximado)

A suíte do pacote rodou **1353 testes em 55,3 s (R1) e 54,3 s (R2)** — contra **55,8 s** na ocorrência 5
(`/tmp/pd10e-test.log`). As duas janelas que distinguiram as ocorrências 4 e 5 (segunda execução do app
imediatamente após a suíte do pacote, sem limpeza de dados) ficaram **verdes nas duas rodadas**.

Nota de método: o campo `executed` do `pre-runs.tsv` para as etapas de `swift test` registra `3 tests, ...` por
uma limitação do extrator (o SwiftPM imprime um resumo por suíte e o extrator pegou a última linha, não o
agregado). O agregado correto é o da tabela acima, obtido da linha `Test Suite 'All tests'`.

## 4. Disco

O disco permaneceu em ~856 MB livres durante toda a medição e **nenhuma etapa falhou**; as durações das
execuções do app ficaram em 192–197 s, dentro da faixa da campanha limpa (191–200 s), sem sinal de truncamento.
Entre as etapas da rodada 2 foram removidos **apenas** caches alheios à medição (um diretório de rascunho, o
cache de VSIX do VS Code e o cache do SwiftPM) — o container do simulador, o `-dd` da medição, o worktree e os
logs não foram tocados. Registro o incidente para que o veredito seja auditável.

## 5. Interpretação (do arquiteto)

Pela matriz fixada antes da medição: **duas rodadas inteiramente verdes ⇒ encerrar esta investigação adicional
como `NOT_REPRODUCED`, não como `FIXED`**, e voltar à autorização de merge técnico do P0B, com o G-18F
registrado como **flakiness conhecida e não resolvida**. Esta é, por decisão do arquiteto, a **última repetição
sem instrumentação**; daqui em diante, ou evidência causal, ou decisão explícita de aceitar o risco.
