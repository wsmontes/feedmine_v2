# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 028 · Vancouver, 24/out/2026, 21:44 PDT.** Monitor consultivo: OMP deve fazer fetch e ler; não há notificação automática.

## Base, janela e proveniência

- **Anterior remoto:** revisão 027, commit [c6aee149](https://github.com/wsmontes/feedmine_v2/commit/c6aee1498570a994be266229089c59d731180250), blob e7f6edab605cb3041c9ccce2f382c52c424f2c93; 24/out 19:39 PDT. **Janela:** 19:39–21:44 PDT.
- **main:** fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48, sem avanço. **codex/feedmine-next-internal:** d6a052667abfd478d5e09f13afe0e01685ef9344, sem avanço. **release/build-56:** cede37f6e925dc19e54a2d67416abd9569559e01, sem avanço; tag de distribuição 56 = 1fe0afaf811637307fcbc2dd73d1d5085028dc94.
- **product/integrity-20261024:** d6ef2452 → **031b27d3bfc0355c5fc3be72d03c57cde0f0f91f**, 12 commits e 25 arquivos ([diff](https://github.com/wsmontes/feedmine_v2/compare/d6ef2452...031b27d3)). Inclui sequenciamento v6, histórico de diversidade, replay, documentação de reserva e autorização de transporte de benchmark.
- **Nova linha corrente:** **product/reserve-20261024@20be579e9bfc4290b2bac1b02376abdc1c330993**, 28 commits após d6ef2452, incluindo reserve, integração de mídia, video claim, testes, correções concorrentes e cap de publicação ([diff](https://github.com/wsmontes/feedmine_v2/compare/d6ef2452...20be579e)). Ela diverge da integrity atual por um commit exclusivo de cada lado desde 2dfa3f9a: [comparação](https://github.com/wsmontes/feedmine_v2/compare/product/integrity-20261024...product/reserve-20261024). O patch de autorização do benchmark parece duplicado por commits diferentes; comparar conteúdo ao integrar, não presumir merge.
- **PR [#5](https://github.com/wsmontes/feedmine_v2/pull/5):** ainda único aberto, auditoria histórica 54, não candidato atual. Branches 54/integration antigas não são o trabalho corrente.
- **Normas relidas nesta execução:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [novas frentes](https://github.com/wsmontes/feedmine_v2/blob/product/integrity-20261024/docs/product/NOVAS_FRENTES_PARA_O_CODEX.md), [PM-027A](https://github.com/wsmontes/feedmine_v2/blob/product/integrity-20261024/coordination/DESIGN-2026-10-24-PM-027A-reserva.md) e [PM-028A](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/coordination/SPEC-2026-10-24-PM-028A-reserva.md). As diretivas recentes são lidas como orientação do dono, não substituídas por blueprints antigos.

## Resumo executivo: consequência para o leitor

**Há avanço real na disponibilidade de imagens e um novo risco de regressão na publicação.** A reserva preparada entrega conclusões tardias ao owner de mídia, aumenta profundidade examinada e preserva imagens declaradas. [Medição única no catálogo real](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/docs/reviews/2026-10-24-reserva-comparacao-catalogo-real.md#L17-L67), feita pelo executor em uma candidata ANTERIOR aos últimos fixes: 629→1.068 cartas/180 s, 64→447 com imagem, 41→77 fontes, 0 imagens declaradas omitidas, 423 conclusões tardias; porém 12→314,7 MB de ativos em três minutos. São dados relatados, não reproduzidos por este monitor.

**O mesmo trabalho revelou uma regressão crítica no B04 antes do último commit:** o autor de [20be579e](https://github.com/wsmontes/feedmine_v2/commit/20be579e9bfc4290b2bac1b02376abdc1c330993) registra 3.616 publicações e 2.149 instalações não contíguas contra histórico 68–80 e zero. O commit agora limita cada oportunidade a 16 cartas e retém as demais para próxima fatia. **Correção estática plausível; B04 no SHA 20be579e NÃO foi reexecutado aqui nem demonstrado PASS.** Os números de volume anteriores não certificam esta última árvore.

**V6 não é automaticamente melhor que v5:** o replay congelado de 629 cartas mediu distância média de tipo **1,955→1,416 (pior)**, fonte 16,804→19,447 (melhor), PD-4 zero em ambos. A causa descrita é gulosa: gasta cedo os 131 itens sem mídia, deixando longa cauda de 498 áudios. Não chamar esse resultado de ganho global de diversidade; o replay é uma seleção única, não a execução incremental real.

## Achados priorizados: fato, hipótese, risco, ação mínima

### P0 PRODUTO/RELEASE — continuidade e B04 sem prova após a correção da rajada

**FATO registrado pelo executor:** B04 com a reserva anterior publicou 3.616 cartas e instalou 2.149 posições não contíguas. **FATO de código:** [SelectionEngine.swift:221–250](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineEditorial/SelectionEngine.swift#L221-L250) passou a limitar a seleção e preservar candidatos excedentes; [AppComposition.swift:3350–3377](https://github.com/wsmontes/feedmine_v2/blob/20be579e/FeedMineApp/FeedMineApp/AppComposition.swift#L3350-L3377) liga limite 16 ao driver e ao bootstrap. **HIPÓTESE:** a correção elimina a explosão sem introduzir cauda vazia por repetição da mesma janela. **Owner:** repetir B04 integral com mesmo corpus, oráculo e trace, comparar cartões efetivamente publicados, instalações contíguas, âncora/offset e progresso; depois B03 consumo acelerado e B05 contexto. Sem resultado do novo SHA, não liberar release.

### P1 PRODUTO — reserva cheia pode impedir preparar a fonte que desbloquearia PD-4

**FATO lógico do código:** [PreparedReserve.swift:150–156](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineRuntime/PreparedReserve.swift#L150-L156), [188–258](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineRuntime/PreparedReserve.swift#L188-L258) deixam 96 prontas + uma única expansão de 16; quando todas têm a mesma fonte da cauda, Editorial não pode publicá-las (PD-4). Se a fonte alternativa está na posição 113 ou posterior, o teto 112 impede preparar a alternativa; sem publicação, nenhuma vaga é liberada. O próprio comentário admite que a preparação para ali e aquisição prossegue; **adquirir não é preparar**. A guarda de 96 MB também pode recusar novas revisões sem despejar as prontas. **RISCO:** fim artificial com oferta elegível. **HIPÓTESE de frequência:** não medida. **Owner:** fixture determinística 112 cartas prontas incompatíveis com a cauda + 113ª de outra fonte, aquisição disponível; provar progresso sem violar PD-4 nem autorizar trabalho ilimitado. O desbloqueio deve depender de elegibilidade/pressão reais, não de um novo scheduler ou um lote mágico.

### P1 PRODUTO — três falhas temporárias viram exclusão permanente da sessão

**FATO de código e teste:** [PreparedReserve.swift:333–343](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineRuntime/PreparedReserve.swift#L333-L343) faz transientFailure ×3 → exhausted(.attemptsSpent), e [plan:244–250](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineRuntime/PreparedReserve.swift#L244-L250) nunca reautoriza exhausted; [PreparedReserveIntegrationTests.swift:288–327](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Tests/FeedMineRuntimeTests/PreparedReserveIntegrationTests.swift#L288-L327) explicitamente verifica que nem após 600 s há nova tentativa. **CONFLITO normativo:** [INV-17:174–178](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md#L174-L178) diz que falha temporária não equivale a exclusão permanente. **RISCO:** imagens e histórias temporariamente inacessíveis nunca retornam na associação corrente, mesmo após rede recuperar. **Owner:** separar fim da oportunidade de ineligibilidade definitiva; backoff/pressão adaptativos no owner existente e prova rede 5xx×3 → recuperação posterior, sem retry incessante.

### P1 CONCORRÊNCIA — duas oportunidades com a mesma revisão podem perder a contagem outstanding

**FATO de fluxo; interleaving ainda não reproduzido:** [plan:239–258](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineRuntime/PreparedReserve.swift#L239-L258) permite que dois planos recebam a mesma revisão ainda autorizada; [markPreparing:270–283](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineRuntime/PreparedReserve.swift#L270-L283) é idempotente; [MediaPrefetcher.swift:432–440](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineRuntime/MediaPrefetcher.swift#L432-L440) recusa ao segundo a revisão já em running. Se o segundo windowClosed(X, outstanding: vazio) executar primeiro, [windowClosed:294–303](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineRuntime/PreparedReserve.swift#L294-L303) transforma X em deferred; o primeiro windowClosed(X, outstanding: X) encontra deferred e não registra outstanding. O download real ainda está em curso, mas o teto pode considerá-lo livre. **RISCO:** contabilidade incorreta de trabalho, replanejamento desnecessário e pressão de memória/rede. **Owner:** teste com duas oportunidades sobre a MESMA revisão, continuação controlada, fechamento invertido e assert outstanding=1 até o único settle; garantir um único owner da janela/settlement.

### P1 EDITORIAL — v6 melhora fonte, piora repetição de tipo no replay

**FATO medido no [replay de 629](https://github.com/wsmontes/feedmine_v2/blob/product/integrity-20261024/docs/reviews/2026-10-24-v6-replay-fila-629.md#L17-L49):** tipo 1,955→1,416; fonte 16,804→19,447; PD-4 zero. **FATO de algoritmo:** [MaximumDistanceSequencing.swift:48–79](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineEditorial/MaximumDistanceSequencing.swift#L48-L79) escolhe máximo local, sem distribuir tipo escasso ao longo da sequência. **HIPÓTESE:** piora da experiência percebida, ainda sem estudo de uso. **Owner:** comparar v5/v6 no MESMO conjunto pronto, no fluxo incremental com histórico real; avaliar pacing proporcional como alternativa versionada, sem reescrever Editions antigas e sem prometer vídeo quando oferta não tem. Corrigir composição da oferta em paralelo, não apenas sort.

### P1 SEGURANÇA — redirecionamento privado ainda é validado tarde

**FATO estático anterior não refutado nesta linha:** [FeedDiscoveryTransport.swift:75–90](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) valida destino final após URLSession.bytes(for:); redirect automático pode contactar destino privado antes da recusa. **PROVA:** servidor privado instrumentado deve receber zero requisições, incluindo cadeias de redirect, e público continuar funcional. O novo [benchmark-origin DEBUG](https://github.com/wsmontes/feedmine_v2/blob/031b27d3/FeedMineApp/FeedMineApp/AppComposition.swift#L3030-L3075) permite loopback 127.0.0.1:8757 quando ATS NSAllowsLocalNetworking está no build instrumentado; não é prova de segurança do transporte Release.

### P2 MÍDIA/CUSTO — vídeo declarado não é vídeo consumível; retenção cresceu 26×

**FATO registrado:** [relatório de reserva:55–67](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/docs/reviews/2026-10-24-reserva-comparacao-catalogo-real.md#L55-L67) tem 14 claims playback/video e zero cartas de vídeo publicadas; 314,7 MB em três minutos, contra 12 MB na base. **FATO de código:** [SyndicationTranslator.swift:321–357](https://github.com/wsmontes/feedmine_v2/blob/20be579e/Sources/FeedMineSyndication/SyndicationTranslator.swift#L321-L357) agora reconhece media:content inclusive Flash do YouTube como claim, mas isso não prova reprodução via player oficial nem publicação. **Owner:** traçar claims→elegibilidade→publicação→play real; medir rede, disco e pressão antes de mexer em retenção. Não declarar NF-12/NF-13 ou YouTube PASS.

## Resoluções, limites e release

**Avanços estáticos reconhecidos:** v6 versionado e histórico congelado; conclusões tardias chegam à reserva; tentativas têm outcome explícito; slots autorizados são contabilizados antes de começar; revisão outstanding não é replanejada; bootstrap/hidden-tail informam publicações; cap 16 impede rajada ilimitada por oportunidade. **Não equivalem a experiência aprovada.** Os P1 anteriores de A→B→A e retenção editorial seguem corrigidos estaticamente desde 55, sem contraprova nova. NF-03 Concluído corrigido, mas preset salvo/concorrência de filtros permanecem; D4, scroll ±1 pt, offline/relaunch, salvos V1→V2, PD-10, B05 e B06 continuam sem certificação integrada.

**Evidência executada por este monitor:** leitura GitHub de monitor, branches, commits, PRs, normas, código, testes, diffs e relatórios; consulta de status CI para 20be579e e 031b27d3 retornou lista vazia. **Nenhum** swift test, XCTest, xcodebuild, simulador, iPhone ou benchmark foi executado por este monitor. O relatório de 180 s é de a2675129+ e os resultados B04 anteriores são relatados no commit 20be579e; **nenhum PASS pode ser transferido ao HEAD 20be579e**. B01–B06 no mesmo SHA/binário permanecem NOT_RUN/não comprovados por este monitor; B06 físico sem evidência de execução.

## Handoff mínimo ao Mac (owner)

    git fetch origin main monitor/architecture product/integrity-20261024 product/reserve-20261024 release/build-56 --tags
    git rev-parse origin/main origin/product/integrity-20261024 origin/product/reserve-20261024 origin/release/build-56
    git merge-base origin/product/integrity-20261024 origin/product/reserve-20261024
    git diff --check d6ef2452..origin/product/reserve-20261024
    git diff --stat d6ef2452..origin/product/reserve-20261024
    git diff origin/product/integrity-20261024...origin/product/reserve-20261024 -- FeedMineApp/FeedMineApp/AppComposition.swift
    git worktree add --detach /tmp/feedmine-monitor-028 origin/product/reserve-20261024
    cd /tmp/feedmine-monitor-028
    swift build
    swift test --filter 'PreparedReserve|MediaPrefetcher|MaximumDistanceSequencing|SelectionEngine'
    swift test
    xcrun simctl list devices available
    # No simulador Mac, escolher UDID e scheme reais; guardar xcresult e logs com SHA.
    # xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -resultBundlePath /tmp/fm-monitor-028.xcresult CODE_SIGNING_ALLOWED=NO test

**Ordem de provas:** (1) B04 com cap 16, instalações contíguas/posição; (2) 112 incompatíveis + 113ª alternativa; (3) 3 falhas temporárias + recuperação; (4) duas oportunidades concorrentes sobre mesma revisão; (5) B03 com estoque pronto/cauda e D4/scroll; (6) v5/v6 replay incremental e oferta por tipo/tema/fonte; (7) B01/B02/B05 no instrumento congelado, B06 físico; (8) redirect sem conexão, catálogo PD-10, persistência offline e migração V1. Nunca editar corpus, oracle ou benchmark para obter verde.

## Memória compacta

Monitor 023 039bf1d5 → 024 918a2c8b → 025 309c1d20 → 026 859c34ce → 027 c6aee149 → **028 este documento**. main fb8e65ff; codex/feedmine-next-internal d6a05266; product/integrity d6ef2452→031b27d3; **product/reserve 20be579e**; release/build-56 cede37f6; tag 56 1fe0afaf; PR #5 5b252eaa. Abertos prioritários: P0 cauda/B04/SSRF; P1 reserva PD-4, transiente permanente, concorrência, v6, filtros, D4/scroll/offline, B05/B06/PD-10; P2 custo e vídeo não comprovado. O OMP precisa fazer fetch e ler. **Somente este arquivo pode ser modificado pelo monitor.**
