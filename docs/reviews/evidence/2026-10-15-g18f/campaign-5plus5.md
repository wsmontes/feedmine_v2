# G-18F — campanha diagnóstica 5+5 (SHA congelado `40bc9fa1`)

Registro bruto e condições da campanha autorizada pelo arquiteto em 2026-10-15, depois de ele **reabrir** a
investigação da intermitência (as ocorrências 4 e 5 caíram na **segunda de duas execuções seriais, com a máquina
ociosa** — ver `occurrences.md`, seção 7). O objetivo era caracterizar o mecanismo, não estimar a taxa.

## 1. Condições executadas

|Item|Valor|
|---|---|
|SHA congelado|`40bc9fa1d514781561393d844763a0b46052cd4a` (`chatgpt/pd10-p0b-active-catalog-recovery`)|
|Árvore de medição|worktree `--detach` em `/tmp/fm-pd10f` (não tocado durante a campanha)|
|Simulador|`FeedMine Bench (16DA3DB5-C9E0-4190-AF2F-AFAADC7EB7AE)`|
|Paralelismo|desabilitado (`-parallel-testing-enabled NO`)|
|Produtos de teste|`build-for-testing` uma vez; as 10 execuções usaram `test-without-building`|
|Dados entre execuções|preservados (sem `erase`, sem reinstalação, dentro do mesmo grupo)|
|Grupo A|5 execuções de `-only-testing:FeedMineAppTests/CompositionTests`|
|Grupo B|5 execuções do caso isolado `testFastFeedPublishesBeforeHeldFeedAndIdleReserveAlternates`|
|Logs brutos|`/tmp/pd10-g18f-campaign/{A1..A5,B1..B5}.log` + `runs.tsv`|

## 2. Resultado — 10 de 10 verdes

|run|grupo|início|fim|dur (s)|exit|`Executed`|G-18F|outras falhas|
|---|---|---|---|---|---|---|---|---|
|A1|A|11:40:33|11:43:53|200|0|60/0|passed|nenhuma|
|A2|A|11:43:55|11:47:13|198|0|60/0|passed|nenhuma|
|A3|A|11:47:15|11:50:31|196|0|60/0|passed|nenhuma|
|A4|A|11:50:33|11:53:47|194|0|60/0|passed|nenhuma|
|A5|A|11:53:48|11:56:59|191|0|60/0|passed|nenhuma|
|B1|B|11:57:00|11:57:09|9|0|1/0|passed|nenhuma|
|B2|B|11:57:10|11:57:17|7|0|1/0|passed|nenhuma|
|B3|B|11:57:18|11:57:25|7|0|1/0|passed|nenhuma|
|B4|B|11:57:26|11:57:32|6|0|1/0|passed|nenhuma|
|B5|B|11:57:34|11:57:40|6|0|1/0|passed|nenhuma|

## 3. Como isto deve ser lido (estado do veredito: **não resolvido**)

- **A execução A2 era o teste direto da hipótese de sequência** (segunda de um par consecutivo, mesma árvore, sem
  limpeza de dados) e ficou **verde**, como A3–A5. Não houve dependência de posição observada nesta árvore.
- **A campanha não distingue taxa baixa de zero.** Com a taxa medida no corpus (~8% por execução),
  `P(10 verdes) ≈ 0,43`; ela só exclui taxa alta (≈26% seria rejeitada a 95%). Nada aqui autoriza declarar a
  intermitência extinta.
- Pela tabela de interpretação do arquiteto, "10 execuções verdes" significa **"a intermitência não reproduziu
  nesta campanha"** — reavaliar com o histórico, não encerrar a causa.

## 4. Duas diferenças materiais entre a campanha e as ocorrências 4–5

**(a) A sequência-predecessora não foi replicada.** Nas duas vermelhas houve a **suíte do pacote inteira** entre o
build e as execuções do app; a campanha foi do `build-for-testing` direto para as execuções:

```
ocorrência 5:  build-for-testing 11:17 → swift test (1353 testes) 11:20 → app#1 11:24 verde → app#2 11:28 VERMELHA
campanha:      build-for-testing 11:40 ────────────────────────────→ app#1 … app#5 (todas verdes)
```

O discriminador candidato pode ser "suíte do pacote antes das execuções do app", e não "segunda execução".

**(b) A árvore instrumentada ficou fora da campanha.** As 15 execuções verdes anteriores eram **todas solitárias**
(nunca pares consecutivos), e a árvore que emite o trace `[G18F]` das seis fases é
`chatgpt/g18f-reserve-diagnosis` (`4a05a182`) — **não** o `40bc9fa1`, que só produz pass/fail e portanto **não pode
responder** de onde veio o 18º card.

## 5. Próximos passos propostos (aguardando autorização do arquiteto)

1. Repetir a **sequência-predecessora exata** em `40bc9fa1`: 2 rodadas de "suíte do pacote + 2 execuções do app".
2. **Pares consecutivos na árvore instrumentada** `4a05a182`: 3 pares, para que uma reprodução traga o trace das
   seis fases e responda a origem do card adicional.

Enquanto isso, o merge do P0B (candidato `40bc9fa1`) permanece **suspenso**.
