# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 029 · Vancouver, 24/out/2026, 23:39 PDT.** Monitor consultivo: OMP deve fazer fetch e ler explicitamente; não há notificação automática.

## Base, janela, escopo e SHAs

- **Anterior publicado:** revisão 028, commit [6885ed5d](https://github.com/wsmontes/feedmine_v2/commit/6885ed5d758e53e7a9f14ba0a59cf7d48b0637ff), blob `895c8caab707e28ac0601357b6c7049c8b24d7ff`, 24/out 21:44 PDT. **Intervalo examinado:** 21:44–23:39 PDT.
- **Mudança nova confirmada:** `product/reserve-20261024` **20be579e → 8d4766b0e79fd735872095cf98dd48d64845e598**, **1 commit, 1 arquivo, 2 linhas substituídas**: [diff exato](https://github.com/wsmontes/feedmine_v2/compare/20be579e9bfc4290b2bac1b02376abdc1c330993...8d4766b0e79fd735872095cf98dd48d64845e598), [commit](https://github.com/wsmontes/feedmine_v2/commit/8d4766b0e79fd735872095cf98dd48d64845e598).
- **Sem avanço:** `main@fb8e65ff5a5e83ae85c9061996aaa0ebf2b7ca48`; `product/integrity-20261024@031b27d3bfc0355c5fc3be72d03c57cde0f0f91f`; `codex/feedmine-next-internal@d6a052667abfd478d5e09f13afe0e01685ef9344`; `release/build-56@cede37f6e925dc19e54a2d67416abd9569559e01`. Tag distribuída 56 = `1fe0afaf811637307fcbc2dd73d1d5085028dc94`, **não** a árvore de reserva. PR [#5](https://github.com/wsmontes/feedmine_v2/pull/5) continua aberto, revisão histórica da 54, não candidato corrente. `integration/candidate@1b990306` e `release/v2-1.0-27@c7cf61e0` são linhas antigas, não interpretar como integração atual. Reserva e integrity ainda [divergem](https://github.com/wsmontes/feedmine_v2/compare/product/integrity-20261024...product/reserve-20261024) (18 commits à frente, 1 atrás a partir da integrity).
- **Normas lidas na linha corrente:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/docs/product/PRODUCT_NORTH_STAR.md), [PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz executora](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/docs/architecture/PRODUCT_INVARIANTS.md), [B01–B06](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [PM-028A](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/coordination/SPEC-2026-10-24-PM-028A-reserva.md). A prioridade é experiência real, não micro-otimização ou blueprints antigos.

## Resumo executivo e consequência para o leitor

**A correção da rajada foi recalibrada de 16 para 32 cartas por oportunidade.** O [commit novo](https://github.com/wsmontes/feedmine_v2/commit/8d4766b0e79fd735872095cf98dd48d64845e598) relata **B03 ainda falhando** na árvore anterior: **seis travamentos de 1 segundo em 30 minutos**, 3.405 avanços, zero repetições e zero pares que violam PD-4. A decisão do runtime pedia `required_cards: 32`, mas cada oportunidade publicava no máximo 16. O commit também **relata** B04 aprovado com o limite 16 (262 instalações), em contraste com a rajada anterior de 55 cartas/segmento e 2.149 instalações não contíguas. **Esses números estão na mensagem do autor, sem artefatos brutos verificados nesta execução; não são PASS independentes.**

**FATO de código:** `FeedAssociation` agora passa `Self.runwayMinimumReserveCards` (**32**) para **ambos** `FeedRunwayDriver` e `ColdFeedBootstrap` em [AppComposition.swift:3357–3376](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/FeedMineApp/FeedMineApp/AppComposition.swift#L3357-L3376); antes passava `Self.forwardWindowCards` (**16**). As constantes permanecem distintas em [AppComposition.swift:2763–2773](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/FeedMineApp/FeedMineApp/AppComposition.swift#L2763-L2773). **HIPÓTESE plausível:** uma oportunidade com 32 cartas elimina os seis vazios de B03. **Não demonstrado:** B03/B04/primeira tela/offset no novo SHA.

**Parecer:** faz sentido relacionar a publicação ao requisito real do runway, mas não aprovar release por uma alteração de duas linhas sem repetir a prova que acusou a regressão. O teto de publicação de 32 não equivale a 32 cartas imediatamente admitidas à janela visual (forwardCapacity continua 16), nem prova que aquisição e preparação acompanham o consumo.

## Achados P0/P1/P2 — evidência, grau de certeza e ação mínima

### P0 PRODUTO/RELEASE — B03 continua FAIL no relato anterior; B04 da nova árvore desconhecido

**FATO relatado:** B03 teve seis stalls de 1 s em 30 min sob teto 16, conforme [mensagem do commit 8d4766b0](https://github.com/wsmontes/feedmine_v2/commit/8d4766b0e79fd735872095cf98dd48d64845e598). **FATO de código:** limite sobe para 32 no bootstrap e no driver, enquanto a janela de apresentação permanece 16 ([AppComposition.swift:2763–2784](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/FeedMineApp/FeedMineApp/AppComposition.swift#L2763-L2784)). [SelectionEngine.swift:221–253](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Sources/FeedMineEditorial/SelectionEngine.swift#L221-L253) preserva os excedentes como held e recua cursor quando houve publicação. **HIPÓTESE:** 32 reduz a cauda seca sem reintroduzir rajadas/instalações não contíguas. **RISCO de regressão:** B04 fora da tolerância, primeiro paint mais pesado, entrega de 32 publicações com somente 16 lugares à frente e scroll alterado durante a admissão. **Owner:** repetir **B03 e B04 integrais no SHA 8d4766b0**, preservar corpus/oráculos/traces, guardar logs de `required_cards`, `publicationLimit`, publicações por oportunidade, `published→admitted→visible`, stalls, posição e instalações contíguas. Comparar 16 vs 32 no mesmo perfil, sem confundir aumento de publicação com continuidade visual.

### P1 TESTE DISCRIMINANTE — não há prova de integração para o novo teto 32

**FATO estático:** [SelectionEngineTests.swift:307–344](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Tests/FeedMineEditorialTests/SelectionEngineTests.swift#L307-L344), [LocalProductionSliceTests.swift:389–416](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Tests/FeedMineRuntimeTests/LocalProductionSliceTests.swift#L389-L416) e [InitialProductionSliceTests.swift:227–245](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Tests/FeedMineRuntimeTests/InitialProductionSliceTests.swift#L227-L245) testam teto **16**; o commit novo não modifica testes. Isso não invalida a lógica genérica, mas não certifica a configuração real 32. **Owner:** teste de composição com 64+ candidatas prontas, teto 32, duas oportunidades, nenhum ID duplicado/perdido, PD-4 na fronteira, janela visual 16 e âncora/offset estáveis; também cold bootstrap 32 e retomada offline. Evitar teste cosmético que apenas compare constante.

### P1 CONTINUIDADE — reserva cheia pode impedir fonte alternativa

**FATO lógico anterior ainda presente:** [PreparedReserve.swift:188–258](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Sources/FeedMineRuntime/PreparedReserve.swift#L188-L258) mantém alvo 96 + uma expansão 16; 112 prontas da mesma fonte da cauda podem bloquear a 113ª de outra fonte que permitiria PD-4. **HIPÓTESE:** ocorrência em catálogo real não medida. **Owner:** fixture 112 incompatíveis + 113ª alternativa, provar progresso sem novo scheduler, quota permanente ou violação de PD-4. O teto 32 de publicação não resolve sozinho ausência de candidato publicável.

### P1 RESILIÊNCIA — falha transitória vira exaustão definitiva

**FATO de código/teste anterior, não modificado:** [PreparedReserve.swift:333–343](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Sources/FeedMineRuntime/PreparedReserve.swift#L333-L343) e [PreparedReserveIntegrationTests.swift:288–327](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Tests/FeedMineRuntimeTests/PreparedReserveIntegrationTests.swift#L288-L327) tornam `transientFailure` ×3 `exhausted` e não reautorizam após 600 s; conflita com [INV-17](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/docs/architecture/PRODUCT_INVARIANTS.md#L174-L178). **Owner:** distinguir fim de oportunidade de ineligibilidade permanente; prova 5xx×3 → rede recupera → carta com imagem preparada, sem retry incessante.

### P1 CONCORRÊNCIA — oportunidade dupla perde outstanding

**FATO de interleaving possível, sem reprodução:** [PreparedReserve.swift:239–303](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Sources/FeedMineRuntime/PreparedReserve.swift#L239-L303) + [MediaPrefetcher.swift:432–440](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Sources/FeedMineRuntime/MediaPrefetcher.swift#L432-L440). Duas oportunidades para a mesma revisão, segundo fechamento antes do primeiro, podem deixar download em curso sem contabilidade outstanding. **Owner:** duas janelas, mesmo revisionID, fechamento invertido, assert outstanding=1 até settle; não criar owner paralelo.

### P1 EDITORIAL — v6 ainda piora distância entre tipos no replay

**FATO registrado pelo executor:** [replay v5/v6 de 629 cartas](https://github.com/wsmontes/feedmine_v2/blob/product/integrity-20261024/docs/reviews/2026-10-24-v6-replay-fila-629.md#L17-L49) mostra distância média de tipo 1,955→1,416 (piora), fonte 16,804→19,447 (melhora), PD-4 zero. [MaximumDistanceSequencing.swift:48–79](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Sources/FeedMineEditorial/MaximumDistanceSequencing.swift#L48-L79) faz escolha local. **HIPÓTESE:** monotonia perceptível; falta sessão humana e execução incremental. **Owner:** comparar com mesmo estoque real, história de consumo e distribuição de mídia; diversificar oferta preparada, não só sort.

### P1 SEGURANÇA — redirect proibido ainda pode ser contactado

**FATO estático anterior sem alteração nesta janela:** [FeedDiscoveryTransport.swift:75–90](https://github.com/wsmontes/feedmine_v2/blob/8d4766b0/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) verifica host final após `URLSession.bytes(for:)`, potencialmente depois de redirect automático. **Owner:** bloquear hop proibido **antes** de conexão; prova servidor privado recebe zero requests, inclusive redirect encadeado, e URLs públicas seguem funcionais. Não confundir autorização DEBUG do benchmark com Release.

### P2 MÍDIA/CUSTO — volume não prova vídeo e recursos

**FATO relatado, em árvore anterior:** [comparação de reserva](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/docs/reviews/2026-10-24-reserva-comparacao-catalogo-real.md#L17-L67) 629→1.068 publicações, imagens 64→447, fontes 41→77, ativos 12→314,7 MB/180 s; 14 claims de vídeo e zero vídeo publicado. **HIPÓTESE:** pressão de disco/memória e cobertura multimídia ainda não caracterizadas. **Owner:** medir claims→preparação→publicação→player real, consumo de rede/disco e estabilidade de leitura antes de otimizar retenção.

## Resoluções preservadas, pendências e release

**Corrigidos apenas estaticamente:** adiamentos A→B→A e retenção editorial desde a linha 55; botão Concluído NF-03; conclusões tardias para a reserva; orçamento contabilizado na autorização; limitação de rajada agora **32** em ambas as entradas (novo, **não certificado**). **Ainda abertos:** preset salvo/concorrência de filtros; primeira tela D4; posição ±1 pt; reabertura offline; salvos V1→V2; PD-10; B05; B06 físico; P0 de continuidade e SSRF; P1 de reserva/concorrência/editorial. O SHA do binário 56 distribuído não contém esta alteração.

**Provas desta revisão:** GitHub — leitura do relatório anterior, diff/commit novo, refs de main/integrity/reserve/release/next, PR aberto, normas, código e testes; status de commit 8d4766b0 sem checks retornados. **Nenhum** `swift build`, `swift test`, XCTest, simulador, iPhone ou B01–B06 executado por este monitor. O relato do autor sobre B04@16 é **evidência declarada**, não um PASS verificável aqui; B03@32 e B04@32 continuam **NOT_RUN/não comprovados**. Nunca transportar PASS entre SHAs, builds, corpus ou oráculos.

## Handoff mínimo ao Mac

```bash
git fetch origin main monitor/architecture product/integrity-20261024 product/reserve-20261024 release/build-56 --tags
git rev-parse origin/main origin/product/integrity-20261024 origin/product/reserve-20261024 origin/release/build-56
git diff --check 20be579e..origin/product/reserve-20261024
git diff 20be579e..origin/product/reserve-20261024 -- FeedMineApp/FeedMineApp/AppComposition.swift
git worktree add --detach /tmp/feedmine-monitor-029 origin/product/reserve-20261024
cd /tmp/feedmine-monitor-029
swift build
swift test --filter 'SelectionEngine|LocalProductionSlice|InitialProductionSlice|PreparedReserve'
swift test
# No Mac com Xcode, escolher UDID/scheme válidos e guardar .xcresult + SHA.
xcrun simctl list devices available
# scripts/run-discovery-benchmark.sh --gate B03 [perfis/argumentos do contrato]
# scripts/run-discovery-benchmark.sh --gate B04 [perfis/argumentos do contrato]
```

**Ordem de decisão:** (1) B03 e B04 no mesmo 8d4766b0, trace completo de publicação→admissão→visibilidade, sem stalls/não-contiguidade; (2) primeira tela/âncora/offset e reabertura; (3) 112+1 e falha transitória/concorrência; (4) B01/B02/B05 e B06 físico na árvore integrada; (5) diversidade incremental, vídeo e custo; (6) SSRF com zero conexão proibida. **Não alterar benchmark/oráculo/corpus para obter verde.**

## Memória compacta

Últimos monitores: 023 `039bf1d5` → 024 `918a2c8b` → 025 `309c1d20` → 026 `859c34ce` → 027 `c6aee149` → 028 `6885ed5d` → **029 este documento**. Últimos SHAs técnicos: main `fb8e65ff`; next `d6a05266`; integrity `031b27d3`; reserve `20be579e→8d4766b0`; release/build-56 `cede37f6`, tag 56 `1fe0afaf`; PR #5 `5b252eaa`. Abertos prioritários: **P0 B03/B04/cauda/SSRF**; **P1 reserva PD-4, falha transitória, outstanding, v6, filtros, D4/scroll/offline, B05/B06/PD-10**; **P2 custo/vídeo**. OMP precisa fazer fetch e ler. **Somente este arquivo pode ser alterado pelo monitor.**
