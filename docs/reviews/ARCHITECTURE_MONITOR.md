# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 032 · Vancouver, 25/10/2026, 05:41 PDT.** Parecer consultivo. O OMP deve fazer fetch e ler este arquivo explicitamente; nenhum agente é notificado automaticamente.

## Base, janela e autoridade

- **Memória anterior:** [revisão 031, commit 8f608791](https://github.com/wsmontes/feedmine_v2/commit/8f608791c97c5c9a4d8ca9f63d3ab7199c2ec71f), 25/out/2026 03:42 PDT, blob c17e6e50dd9e6a5a3456e91cfb36a8d741523ac7. **Janela desta revisão:** 03:42 até 25/10/2026, 05:41 PDT.
- **Linha técnica corrente:** product/reserve-20261024 **7a5d555d6538cb9eb56ddacbbc78ad8e85a9423e → 38387ace6d3be886899b4dc57ead10b912ebfdcb**, **8 commits**. [Diff consolidado](https://github.com/wsmontes/feedmine_v2/compare/7a5d555d...38387ace). Saldo: **um teste UI modificado (+17/-6) e um relatório de validação atualizado (+45/-25)**. **Nenhum arquivo de produção alterado nesta janela.**
- **Outras refs conferidas, sem avanço:** main **fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48**; product/integrity-20261024 **031b27d3bfc0355c5fc3be72d03c57cde0f0f91f**; codex/feedmine-next-internal **d6a052667abfd478d5e09f13afe0e01685ef9344**; release/build-56 **cede37f6e925dc19e54a2d67416abd9569559e01**; build 56 distribuída na tag **1fe0afaf**. PR [#5](https://github.com/wsmontes/feedmine_v2/pull/5) permanece aberto, HEAD **5b252eaa858d444f61e4a4acfec1f389286683eb**, sem atualização desde 22/out; histórico, não candidato de integração. integration/candidate está 432 commits atrás da base da revisão 031; integration/chatgpt diverge, não é automaticamente candidata atual.
- **Normas atuais lidas na linha de reserva:** [PRODUCT_NORTH_STAR](https://github.com/wsmontes/feedmine_v2/blob/38387ace/docs/product/PRODUCT_NORTH_STAR.md), [PRODUCT_DECISIONS_2026-10-09](https://github.com/wsmontes/feedmine_v2/blob/38387ace/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11](https://github.com/wsmontes/feedmine_v2/blob/38387ace/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [PRODUCT_INVARIANTS](https://github.com/wsmontes/feedmine_v2/blob/38387ace/docs/architecture/PRODUCT_INVARIANTS.md) e [DISCOVERY_ACCEPTANCE_BENCHMARK](https://github.com/wsmontes/feedmine_v2/blob/38387ace/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md). Autoridade: North Star, PD-4/5/8/9/10, INV-03/04/05/07/08/10/11/12/15/17/18 e gates B01–B06; blueprints históricos não revogam essas decisões.

## Resumo executivo — duas mudanças de parecer, nenhuma correção de produto

**P0 continuidade:** os novos traces relatados isolam o aglomerado de stalls B03 no **handoff entre bootstrap frio e runway**, não na quantidade de cartas publicada por fatia. O bootstrap publica 12 cartas em **t=10,04 s**, a janela é admitida em **t=10,23 s**, e a primeira fatia do runway só é solicitada em **t=15,93 s**. Entre 10,9 e 15,9 s o trace registra **zero publicação, zero instalação e zero solicitação de fatia**. A diferença de **5,70 s entre admissão e primeira fatia** é suficiente para esgotar 12 cartas numa rajada de 3/s. [Relatório da candidata, linhas 24–49](https://github.com/wsmontes/feedmine_v2/blob/38387ace/docs/reviews/2026-10-25-candidata-validacao.md#L24-L49). **Classificação:** tempos e contagens são evidência **relatada pelo executor**, não trace bruto reproduzido por este monitor; a lacuna estrutural de ativação foi confirmada estaticamente abaixo. **B03 permanece FAIL.**

**P1 retorno do navegador da revisão 031:** **reclassificado como falso negativo do instrumento, não regressão comprovada do produto**. A investigação observou que o tap de acessibilidade em Close deixava o Safari modal aberto. O commit [55a04ee8](https://github.com/wsmontes/feedmine_v2/commit/55a04ee8e3e5be9b20262a388643993ea44dc3f3) troca por toque de coordenada no frame do controle e mantém a comparação de identidade, posição e geometria. O executor relata **duas corridas restored=true em 36,7 s**. O produto não foi alterado. **Não chamar isso de PASS independente nem inferir que toda navegação/offline esteja certificada.** A afirmação anterior de que o volume de publicação causava a perda de âncora fica **retirada**; o que se demonstrou foi uma falha do gesto de fechamento no teste.

**Parecer de release:** candidata 57 **não certificada**: B03 FAIL, B06 físico NOT_RUN, redirect de descoberta P0 aberto, e os demais riscos estruturais sem provas discriminantes. Não gastar esforço com outro ajuste 16/32/48 ou piso 32/64 antes de corrigir a transição inicial no owner existente.

## Mudanças verificadas e consequências

Os oito commits novos foram: [e43024f4](https://github.com/wsmontes/feedmine_v2/commit/e43024f4533eb66dcd31f50774ecbf0cf78a8dec) (hipótese inicial de retorno), [6a8aa961](https://github.com/wsmontes/feedmine_v2/commit/6a8aa961be07fe631bf569355edb8762264ccd0b) (traces de B03), [0f99bc22](https://github.com/wsmontes/feedmine_v2/commit/0f99bc228112bdae6930893aca0ad38727b0b734) (bisseção do navegador), [0e13b41e](https://github.com/wsmontes/feedmine_v2/commit/0e13b41e9f8cc908ed956408502eb6035e15b3fc) (hipótese de árvore remota), [07b42ae5](https://github.com/wsmontes/feedmine_v2/commit/07b42ae5cee3c275753cb1fd9e7f1deb5932abf8) (diagnóstico do gesto), [55a04ee8](https://github.com/wsmontes/feedmine_v2/commit/55a04ee8e3e5be9b20262a388643993ea44dc3f3) (correção do teste), [b1a30274](https://github.com/wsmontes/feedmine_v2/commit/b1a302747df6025ef73e7d401d9140501274ed90) (experimento piso 64) e [38387ace](https://github.com/wsmontes/feedmine_v2/commit/38387ace6d3be886899b4dc57ead10b912ebfdcb) (identificação do vão bootstrap/runway).

O relatório evoluiu de uma acusação de regressão de posição para um diagnóstico do instrumento e de uma hipótese de lote insuficiente para um atraso mensurado de ativação inicial. **Isso altera a prioridade de investigação, mas não altera o comportamento do binário**: só o teste UI e a documentação mudaram.

## Achados priorizados: evidência, natureza, risco e orientação mínima

### P0 — Bootstrap apresenta cartas antes de ativar a reposição contínua (fato estrutural + evidência de stall relatada)

**Fato no código:** [AppComposition.swift:3786–3844](https://github.com/wsmontes/feedmine_v2/blob/38387ace/FeedMineApp/FeedMineApp/AppComposition.swift#L3786-L3844) aguarda o término de cold.run antes de executar driver.activateCurrentPresentation. A publicação antecipada recebida pelo relé em [4160–4207](https://github.com/wsmontes/feedmine_v2/blob/38387ace/FeedMineApp/FeedMineApp/AppComposition.swift#L4160-L4207) **instala e cresce a janela**, mas **não ativa explicitamente o runway** naquele ponto. Enquanto launching=true, o caminho de oportunidade agendada também é barrado em [4134–4142](https://github.com/wsmontes/feedmine_v2/blob/38387ace/FeedMineApp/FeedMineApp/AppComposition.swift#L4134-L4142) e o foreground não atravessa o guard de lançamento em [4380–4393](https://github.com/wsmontes/feedmine_v2/blob/38387ace/FeedMineApp/FeedMineApp/AppComposition.swift#L4380-L4393). **Limite da conclusão:** callbacks de viewport ainda podem alcançar o driver; portanto não afirmar que absolutamente nenhum outro caminho o aciona. O trace do executor registra a primeira fatia apenas em t=15,93 s, o que é compatível com essa lacuna.

**Evidência do executor:** 12 publicadas em 10,04 s; admitidas 10,23 s; primeira fatia 15,93 s; cluster ~3 s no início. Fatias normais mediana **215 ms**, p99 **291 ms**, máximo **340 ms**; frames 39–60 fps. Lotes 16/32/48 deram 6/7/8 stalls; piso 32/64 deu 7/6. [Relatório, linhas 18–49](https://github.com/wsmontes/feedmine_v2/blob/38387ace/docs/reviews/2026-10-25-candidata-validacao.md#L18-L49). Esses números **não são resultados de execução deste monitor**.

**Hipótese causal forte, ainda não fechada:** o lançamento segura a ativação do runway depois da primeira publicação visível, deixando uma reserva inicial insuficiente para a rajada. **Risco de correção:** ativar um segundo driver ou disparar trabalho paralelo a cada evidência de bootstrap duplicaria ownership e poderia quebrar PD-4/INV-12. **Owner:** usar a **mesma sessão/driver/runway** para sinalizar uma única oportunidade assim que a primeira Edition estiver instalada e o estoque for observável; coordenar o restante de cold.run com esse owner, sem bloquear a apresentação nem gerar filas/timers novos. Provar a ordem exata no trace: primeira publicação → primeira observação/ativação → primeira fatia → próxima publicação → próxima instalação → consumo, com os IDs e Edition. Repetir B03 e B04 no **mesmo SHA de correção**, além da reabertura offline.

### P1 — Retorno do navegador: falso bloqueador retirado, teste ainda depende de gesto do sistema (correção de instrumento)

**Fato no diff:** [VideoCardJourneyUITests.swift:561–601](https://github.com/wsmontes/feedmine_v2/blob/38387ace/FeedMineApp/FeedMineAppTests/VideoCardJourneyUITests.swift#L561-L601) tenta fechar o Safari por toque na coordenada do botão, espera até 20 s pelo desaparecimento de URL e depois consulta a superfície. [Linhas 286–313](https://github.com/wsmontes/feedmine_v2/blob/38387ace/FeedMineApp/FeedMineAppTests/VideoCardJourneyUITests.swift#L286-L313) ainda comparam a carta original, Y ±2 pt e altura ±2 pt. **Evidência relatada:** duas execuções com restored=true, 36,7 s; bisseção encontrou a mudança de apresentação modal em 67d78212, não um defeito de âncora. [Relatório, linhas 75–93](https://github.com/wsmontes/feedmine_v2/blob/38387ace/docs/reviews/2026-10-25-candidata-validacao.md#L75-L93).

**Parecer:** retirar o P1 de perda de posição como defeito comprovado; preservar a jornada de retorno como requisito de release. **Risco residual P2 de instrumento:** a espera pelo desaparecimento de URL expira sem asserção própria e o toque por coordenada pode depender do frame/idioma/dispositivo; a comparação de carta ainda é o discriminante principal. **Owner:** registrar explicitamente que o Safari foi fechado antes de aceitar a volta e guardar o xcresult; não mudar o produto em resposta a um falso negativo.

### P0 segurança — Redirecionamento de descoberta ainda validado tarde (fato estático herdado)

[FeedDiscoveryTransport.swift:69–101](https://github.com/wsmontes/feedmine_v2/blob/38387ace/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L69-L101) permite que URLSession siga redirect antes da validação final. **Fato de ordem das operações; conexão indevida não reproduzida.** Owner: validar cada hop **antes** da conexão e testar zero hits no destino privado proibido. Não confundir exceções ATS DEBUG do benchmark com autorização de produção.

### P1 — Reserva, mídia, concorrência e diversidade (pendências herdadas, sem correção nesta janela)

[PreparedReserve.swift:188–258](https://github.com/wsmontes/feedmine_v2/blob/38387ace/Sources/FeedMineRuntime/PreparedReserve.swift#L188-L258): targetDepth+16 não demonstra liveness se as 16 extras também forem PD-4 incompatíveis. [333–343](https://github.com/wsmontes/feedmine_v2/blob/38387ace/Sources/FeedMineRuntime/PreparedReserve.swift#L333-L343): três falhas transitórias podem virar estado exhausted definitivo, em tensão com INV-17. [239–303](https://github.com/wsmontes/feedmine_v2/blob/38387ace/Sources/FeedMineRuntime/PreparedReserve.swift#L239-L303): duas janelas concorrentes ainda carecem de prova contra conclusão invertida. **Riscos estáticos/hipóteses de ocorrência, não regressões medidas.** Provas mínimas: 112+1 fontes, 3×5xx seguido de recuperação, duas janelas com conclusões invertidas. Manter PD-4 absoluto; não criar scheduler de mídia paralelo. Shuffle amplo exige variedade de oferta preparada, não apenas reordenar áudios dominantes.

### P1 — Filtros, posição offline, biblioteca e catálogo público (pendências herdadas)

NF-03 do botão Concluído e recuperação A→B→A de adiamentos têm **correções estáticas reconhecidas** em linhas anteriores, mas o preset salvo e confirmações concorrentes continuam sem prova integrada. Reabertura offline, posição após navegação, salvos/coleções/fontes, migração V1→V2 e atualização não bloqueante do catálogo público (PD-10/INV-18) ainda requerem demonstração funcional numa única árvore candidata. **Não chamar resolvido apenas porque B05 do corpus limitado foi relatado verde.** O controle de apresentação deve permanecer local, imutável e independente de rede.

### P2 — Custo de mídia e vídeo amplo

[Relatório: linhas 51–93](https://github.com/wsmontes/feedmine_v2/blob/38387ace/docs/reviews/2026-10-25-candidata-validacao.md#L51-L93) relata 335,4 MB de mídia em 180 s, 488 cartas com imagem, zero omissões de imagem declarada e duas cartas de vídeo num feed isolado; **nenhuma carta de vídeo** na janela de catálogo amplo. Resultado do executor, não medição independente. Medir orçamento relativo de disco/memória, retenção e diversidade do catálogo real sem abandonar mídia ou sacrificar a apresentação local.

## Release: matriz, limites e provas no Mac

**Matriz publicada pelo executor para a base ca532f25:** B01 PASS relatado; B02 PASS relatado; **B03 FAIL relatado** (7 avanços com espera ≥1 s, concentrados em dois episódios); B04 PASS relatado; B05 PASS relatado; **B06 NOT_RUN** (iPhone físico bloqueado). Corrida posterior de piso 64 relatou 6 stalls; **não é PASS**. A correção do teste de vídeo relata duas voltas corretas, mas não substitui B04/B05 nem prova iPhone. O SHA atual **38387ace** contém mudanças de teste/docs, não uma correção de produto. Nenhum artefato bruto .xcresult, hash de corpus, logs completos ou identidade de binário foi auditado independentemente aqui. **Nenhum swift build/test, XCTest, simulador, iPhone ou bench foi executado por este monitor; CI de status e workflow do HEAD sem resultados.**

**Comandos de prova, a executar no Mac (não executados aqui):**

    git fetch origin main monitor/architecture product/reserve-20261024 product/integrity-20261024 release/build-56 --tags
    git rev-parse origin/main origin/product/reserve-20261024 origin/product/integrity-20261024 origin/release/build-56
    git log --oneline 7a5d555d..origin/product/reserve-20261024
    git diff --check 7a5d555d..origin/product/reserve-20261024
    git diff --stat 7a5d555d..origin/product/reserve-20261024
    git worktree add --detach /tmp/feedmine-monitor-032 origin/product/reserve-20261024
    cd /tmp/feedmine-monitor-032
    (cd bench && shasum -a 256 -c MANIFEST.sha256)
    swift build && swift test
    bash bench/run.sh --gate B03 --full-trace
    bash bench/run.sh --gate B04 --profile A --profile B
    bash bench/run.sh --gate B05 --profile A --profile B

**Coleta adicional indispensável:** no B03, sincronizar host_started, cold.published, admitted, runway.requested, local_slice, publicationConcluded e frame/advance num mesmo relógio monotônico, com Edition/IDs, para provar a ausência ou presença de solicitação no intervalo 10,23–15,93 s. Repetir com a correção mínima de handoff, mantendo corpus e oráculo; comparar B03/B04 antes/depois e uma volta real do Safari (confirmando fechamento modal e ID/offset ±2 pt). B06 somente em iPhone desbloqueado com evidência física. Preservar diretórios de execução, manifesto, hashes, logs, xcresult e SHA do binário.

**Ordem mínima ao owner:** (1) corrigir handoff bootstrap→runway no owner existente e medir primeiro pedido sem esperar esgotamento; (2) repetir B03/B04/B05 + jornada do Safari na mesma árvore; (3) fechar redirect P0 e os contraexemplos da reserva; (4) validar PD-10, biblioteca/offline, diversidade e B06; (5) somente então considerar candidata 57. Não trocar limite de lote, piso ou timer como substituto de causalidade.

## Memória compacta e histórico de SHAs

- **Revisões remotas:** 025 309c1d20 → 026 859c34ce → 027 c6aee149 → 028 6885ed5d → 029 5efa2afb → 030 31d01b64 → 031 8f608791 → **032 presente**.
- **SHAs técnicos verificados:** main fb8e65ff; integrity 031b27d3; next d6a05266; release/build-56 cede37f6; tag build 56 1fe0afaf; reserve **7a5d555d → e43024f4 → 6a8aa961 → 0f99bc22 → 0e13b41e → 07b42ae5 → 55a04ee8 → b1a30274 → 38387ace**; PR #5 5b252eaa.
- **Resolvido/reclassificado nesta revisão:** a suposta perda de âncora no navegador era **falha de fechamento modal no instrumento**; teste corrigido estaticamente e duas corridas verdes **relatadas**. A causa atribuída antes à publicação em volume foi retirada. **Não** se declarou nova correção de produto.
- **Abertos prioritários:** **P0 B03/hand-off bootstrap-runway e redirect**; **P1 reserva 112+1, recuperação transitória, concorrência, shuffle, filtros/presets, scroll e offline/salvos, PD-10, B06**; **P2 robustez do gesto de teste, custo de mídia e vídeo amplo**. B01/B02/B04/B05 verdes apenas **relatados** na base indicada; B03 vermelho, B06 não executado. Nenhum PASS independente.

Este monitor não altera main, código, testes, benchmarks, scripts, coordenação, issues ou PRs. O OMP precisa fazer fetch de monitor/architecture e ler este arquivo.
