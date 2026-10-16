# Rodada 5 — inventário entregue e restrição de commit

Data: 2026-10-11. Autor: sessão OMP. **Nada foi commitado.** Este documento existe para revisão: lista
exatamente o que esta sessão entregou, o que está misturado com trabalho alheio e por que um commit
seguro ainda não é possível.

## 1. A regra que impede o commit agora (pedido do Codex: caminho e trecho exato)

|Arquivo|Linha|Trecho|
|---|---|---|
|`/Users/<user>/.omp/agent/AGENTS.md`|457|"- Nunca commite ou faça push sem pedido explícito do usuário." (seção *Preferências de trabalho*)|
|`docs/superpowers/handoffs/PARALLEL_SESSION_HANDOFF.md`|35-36|"4. Commit per task with the message the plan gives that task. Never `git push`. Never `git stash` or `git checkout -- .` on a tree you did not verify: the other session may have uncommitted work."|

A segunda linha é o protocolo do próprio repositório para duas sessões na mesma árvore: ele permite commits
por tarefa, proíbe `push`, e proíbe mexer no estado de uma árvore que não verifiquei. É exatamente o caso:
132 entradas sujas, com trabalho de outra sessão entrelaçado nas mesmas funções que editei.

## 2. Trabalho desta sessão, por arquivo

### 2.1 Só meu (nenhum hunk alheio no arquivo)

|Arquivo|O que é|Estado|
|---|---|---|
|`Sources/FeedMineRuntime/FeedPresentationAdmission.swift`|caso `publishedGrowth` (crescimento automático, sem observação)|modificado|
|`Sources/FeedMineUI/FeedLoadingView.swift`|textos aprovados pelo PO + ações de recuperação|modificado|
|`Sources/FeedMineUI/FeedPresentationState.swift`|`.unreachable` + rótulos derivados|modificado|
|`Tests/FeedMineRuntimeTests/FeedPresentationAdmissionTests.swift`|teste do crescimento automático|modificado|
|`docs/architecture/RUNTIME_PRESENTATION_CONTRACT.md`|contrato do novo caso de admissão|modificado|
|`docs/reviews/2026-10-11-ux-diagnosis-round1.md`|rodada 1 (diagnóstico + correções)|novo|
|`docs/reviews/2026-10-11-cold-start-diagnosis-round2.md`|rodada 2 (causa + proposta)|novo|
|`docs/reviews/2026-10-11-continuity-and-catalogue-protection-round3.md`|rodada 3|novo|
|`docs/reviews/2026-10-11-round4-plan.md`|plano da rodada 4|novo|
|`docs/reviews/2026-10-11-round4-implementation-and-demo.md`|rodada 4|novo|
|`docs/reviews/2026-10-11-round5-inventory-and-criteria.md`|este documento|novo|
|`docs/evidence/2026-10-11-ux-diagnosis/**`|25 capturas/vídeos/logs (git-ignored por decisão do repo)|novo|

### 2.2 Misturado com trabalho de outra sessão (não commitável sem separação)

|Arquivo|Minha parte|Parte alheia|
|---|---|---|
|`FeedMineApp/FeedMineApp/AppComposition.swift`|crescimento automático, `retryNow`, mapeamento de falha de conexão, mensagens de startup sem erro cru|~37 hunks (≈1000 linhas) não meus|
|`FeedMineApp/FeedMineApp/FeedMineApp.swift`|closures de recuperação na `FeedScreen`, copy do erro de troca de contexto|13 hunks não meus|
|`Sources/FeedMineRuntime/FeedSession.swift`|`admitPublishedGrowth`|1 hunk não meu|
|`Sources/FeedMineUI/FeedScreen.swift`|closures `onTryAgain`/`onAdjustInterests`|3 hunks não meus|
|`Tests/ArchitectureSmokeTests/FeedScreenRenderingTests.swift`|expectativas dos textos aprovados + estado novo|1 hunk não meu|

### 2.3 Harness (arquivos **untracked** no git — não são meus, mas receberam minha mudança)

`bench/run.sh`, `scripts/soak.py`, `bench/EVALUATOR.sha256`, `scripts/verify_product_catalogue.sh` (novo),
`docs/IOS_RUN.md`, `README.md`. Como `bench/` e esses scripts nunca foram versionados, um commit deles
levaria arquivos inteiros de outra origem; ficam no inventário, fora de commit.

## 3. Commits pendentes — o que seria preciso para destravar

1. A outra sessão commitar as ~1000 linhas dela em `AppComposition.swift` (e os outros hunks alheios);
   depois disso meus hunks ficam isolados e um commit por caminho é seguro.
2. Ou autorização explícita do usuário para um commit que inclua o trabalho das duas sessões na mesma
   árvore (o que a regra de `AGENTS.md:457` exige, e o handoff §35 desaconselha).
3. Ou eu preparo um patch linha a linha, para aplicação manual, ciente de que ele não aplica limpo sobre o
   índice atual (as linhas de contexto ainda são as de HEAD).

## 4. Critérios da rodada 5

Ver a tabela na seção 5 do relatório final desta rodada (`2026-10-11-round5-acceptance.md`), preenchida com
as execuções concluídas.
