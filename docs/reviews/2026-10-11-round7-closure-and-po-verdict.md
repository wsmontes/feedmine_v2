# Rodada 7 — fechamento da frente e parecer final do PO

Data: 2026-10-11. Autor: sessão OMP. Nenhum commit (restrição da rodada 5 mantida).

## 1. Publicação posterior à janela de acompanhamento (Codex item 1)

**Medido primeiro, corrigido depois.** A cadeia temporizada cobria ~6 s; um teste novo faz o segundo feed
responder **10 s** depois (`FEEDMINE_SLOW_FEED_SECONDS=10`, instrumento novo no transporte controlado) — ou
seja, a publicação conclui *depois* de a cadeia ter terminado.

- Antes da correção o teste falhava (a rajada tardia não era lida).
- Correção: o crescimento passou a ser acionado pelo **evento de publicação concluída**
  (`ColdFeedEvidence.settled(changed: true)` e `.published` reiniciam a cadeia limitada), preservando
  associação, âncora e limites; a cadeia temporizada continua apenas como segurança.
- Evidência (log, corrida real do teste):
  `published growth: admitted 1 -> 1` ×5 (tentativas sem nada publicado ainda) e, quando a rajada chega,
  `admitted 1 -> 12`.
- `testPublicationAfterTheFollowUpWindowStillReachesTheWindow` — **PASS (16,4 s)**, sem gesto
  (`received=0 completed=0 backward=0`).

## 2. S5 — encaminhamento e desfecho (Codex item 2)

- Caso mínimo escrito e encaminhado por onde o repositório define: bloco "R7 — cross-session handoff" em
  `docs/superpowers/handoffs/PARALLEL_SESSION_HANDOFF.md` §Claims, apontando para
  `docs/reviews/2026-10-11-s5-handoff-minimal-case.md` (sintoma, medidas, o que já está excluído, como
  reproduzir).
- **Não há canal direto** entre sessões nesta máquina, então não há "status do dono" a relatar; o registro no
  handoff é o meio que o projeto define.
- **Parecer do PO sobre isso:** não bloqueante — "o teste exige igualdade de tamanho entre janelas, algo que
  não constitui requisito de produto... Revisar a validade dessa expectativa. Adaptar o teste aos invariantes
  reais, se necessário. **Não alterar o runtime apenas para satisfazer igualdade artificial**."

## 3. Vídeos pendentes entregues (Codex item 3)

|Vídeo|O que mostra|Teste que o produziu|
|---|---|---|
|`R7-primeiro-uso-real-expansao.mp4`|primeira abertura com o **catálogo real**: onboarding → primeiro card → janela se expandindo sozinha|`testFirstRunOverTheRealCatalogueExpandsWithoutAGesture` (PASS)|
|`R7-sem-historias-duas-acoes.mp4`|superfície "sem histórias" com **Tentar novamente** e **Ajustar interesses** acionados (o segundo abre Ajustes)|`testNoStoriesSurfaceOffersItsRecoveryActions` (PASS)|

Ambos em `docs/evidence/2026-10-11-ux-diagnosis/`.

## 4. Parecer final do PO (Codex item 4)

> **Parecer final do PO — Rodada 7. DECISÃO: ACEITE FINAL APROVADO.**
> Autorizo o encerramento desta frente de UX do FeedMine V2, com base nas evidências apresentadas.
>
> **1. Primeiro uso — APROVADO.** Primeiro card aparece assim que está pronto; janela cresce automaticamente,
> sem interação; crescimento funciona mesmo com aquisição atrasada em 10 segundos; **publicação concluída
> aciona a atualização, sem depender de timers**; estados de espera e recuperação foram demonstrados; o P0
> original está fechado.
>
> **2. Restauração — APROVADA.** Os três critérios atendidos: continuidade (edição e âncora preservadas),
> disponibilidade (todos os cards anteriores permanecem alcançáveis), transparência (sem espaços vazios,
> finais falsos ou refresh obrigatório). "A diferença de 17 para 9 cards na janela restaurada é aceitável.
> Janela de apresentação não é histórico publicado."
>
> **3. Teste interno vermelho — NÃO BLOQUEANTE.** "O teste exige igualdade de tamanho entre janelas, algo que
> não constitui requisito de produto." Encaminhamento ao responsável pelo caminho de restauração, sob
> coordenação do Codex: revisar a validade da expectativa e adaptar o teste aos invariantes reais, se
> necessário. "Isso permanece como pendência técnica, não como defeito de UX demonstrado."
>
> **4. Decisão para registro.** Status: **ACEITO — FRENTE ENCERRADA**. Não há exigências adicionais desta
> rodada. A engenharia está autorizada a avançar para a próxima prioridade de UX. "Não exigimos quantidades
> fixas de cards nem equivalência artificial de janelas."
>
> Ressalva do próprio PO: "Parecer emitido com base nos resultados e evidências relatados pela engenharia, sem
> reexecução independente dos testes."

## 5. Estado

Frente de UX do primeiro uso **encerrada pelo PO**. O que fica aberto e não é desta frente: o S5 (pendência
técnica com o dono do caminho de restauração, sob coordenação do Codex) e a inexistência de commit — a árvore
segue com 132+ entradas sujas que misturam o trabalho desta sessão com o de outra (§
`2026-10-11-round5-inventory-and-commit-restriction.md`).
