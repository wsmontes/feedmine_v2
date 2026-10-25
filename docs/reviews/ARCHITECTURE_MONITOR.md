# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 030 · Vancouver, 25/out/2026, 01:42 PDT.** Monitor consultivo: OMP deve fazer fetch e ler explicitamente; não há notificação automática.

## Base, janela, SHAs e escopo

- **Anterior publicado:** [revisão 029](https://github.com/wsmontes/feedmine_v2/commit/5efa2afebb5a6a88404d54438df21221fed79d88), 24/out 23:39 PDT, blob `97ff90ca8dd2552009839e2c5d9873c2b4c3b808`. **Janela:** 24/out 23:39 → 25/out 01:42 PDT.
- **Linha corrente:** `product/reserve-20261024` **`8d4766b0` → `06e94c71` → `ca532f25effc4d1f4819b82be16402e7a14c8f70`**. [Comparação](https://github.com/wsmontes/feedmine_v2/compare/8d4766b0e79fd735872095cf98dd48d64845e598...ca532f25effc4d1f4819b82be16402e7a14c8f70): **dois commits, diferença líquida de arquivos vazia**; os dois modificaram apenas `FeedMineApp/FeedMineApp/AppComposition.swift` e a segunda alteração desfez a primeira. [Tentativa 48](https://github.com/wsmontes/feedmine_v2/commit/06e94c71ddd188aa35c20636b67f0536071e6cbd); [reversão para 32](https://github.com/wsmontes/feedmine_v2/commit/ca532f25effc4d1f4819b82be16402e7a14c8f70).
- **Sem novos SHAs verificados:** `main@fb8e65ff`, `product/integrity-20261024@031b27d3`, `codex/feedmine-next-internal@d6a05266`, `release/build-56@cede37f6`; tag distribuída build 56 `1fe0afaf`. PR [#5](https://github.com/wsmontes/feedmine_v2/pull/5) permanece aberto e histórico, sem atualização. Branches de design, integração antiga e experiências anteriores não foram tratadas como candidatas correntes.
- **Normas relidas no SHA corrente:** [North Star](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/docs/product/PRODUCT_NORTH_STAR.md), [decisões PD-1–PD-11](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz executora](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark B01–B06](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) e [contrato da reserva PM-028A](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/coordination/SPEC-2026-10-24-PM-028A-reserva.md) já incorporado na revisão anterior. Contrato B03 exige **zero stalls visíveis ≥1 s**, não uma média aceitável.

## Resumo executivo — consequência para o produto

**Nova evidência relevante: aumentar o teto de publicação NÃO eliminou os vazios de admissão.** A mensagem de `06e94c71` relata **sete** janelas de 1 segundo sem admissão sob teto **32**, das quais três concentradas em um intervalo de 2 segundos; o autor tentou **48** (32 requeridas + 16 da janela de apresentação). A mensagem de `ca532f25` relata três execuções B03 com a mesma árvore exceto o teto: **16 → 6 stalls / 3.405 avanços; 32 → 7 / 3.393; 48 → 8 / 3.424**. Reverteu a 32, que continua em [AppComposition.swift:3357–3376](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/FeedMineApp/FeedMineApp/AppComposition.swift#L3357-L3376). A apresentação ainda tem **forwardCapacity 16**, com requisito mínimo de runway **32**, em [AppComposition.swift:2763–2784](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/FeedMineApp/FeedMineApp/AppComposition.swift#L2763-L2784).

**FATO comprovado no diff:** o estado final do código é igual ao da revisão 029, com teto 32 no driver e bootstrap. **EVIDÊNCIA relatada, não independentemente certificada:** as três execuções B03 falharam na cláusula de stalls. **HIPÓTESE contrariada pelos dados apresentados:** só elevar o teto (16→32→48) resolveria a cauda. **Não é prova causal definitiva:** as execuções têm números distintos de avanços, não foram disponibilizados aqui traces brutos, timestamps por estágio, identidade de build, ambiente, hashes e artefatos de oráculo comparáveis. Não transformar “todas as outras cláusulas verdes” da mensagem em PASS do gate.

**Orientação de produto:** parar de tratar tamanho do lote como explicação suficiente. O próximo defeito está no **intervalo observável entre demanda, publicação, admissão e próxima carta realmente alcançável**, sobretudo durante rajadas. O feed deve manter cartas completas disponíveis sem tocar no prefixo/posição do leitor, sem segundo scheduler, polling, cache ou retry paralelo.

## Achados e ações mínimas

### P0 — B03 continua FAIL relatado; não há certificação do SHA final

**EVIDÊNCIA relatada:** [commit 06e94c71](https://github.com/wsmontes/feedmine_v2/commit/06e94c71ddd188aa35c20636b67f0536071e6cbd) e [commit ca532f25](https://github.com/wsmontes/feedmine_v2/commit/ca532f25effc4d1f4819b82be16402e7a14c8f70). As janelas de 1 s violam [B03:70–80](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L70-L80) **se confirmadas pelo oráculo congelado**. **FATO estático:** teto 32, janela visual 16, [crescimento da admissão por recibo e oportunidade em AppComposition.swift:3659–3732](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/FeedMineApp/FeedMineApp/AppComposition.swift#L3659-L3732); [viewport e crescimento em AppComposition.swift:4210–4281](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/FeedMineApp/FeedMineApp/AppComposition.swift#L4210-L4281). **HIPÓTESES a separar:** (a) demanda emitida tarde; (b) material pronto/publicado mas não admitido; (c) admissão ocorreu mas a UI não mostrou a próxima carta; (d) serialização/coalescência de observações na rajada; (e) seleção sem candidato PD-4 apesar da reserva. **Risco:** novo ajuste de lote mascarar ou piorar B04 sem corrigir a janela vazia. **Owner:** correlacionar por `editionID`, `segmentID`, `PublicationCardID`, âncora e relógio monotônico, em cada stall: `required_cards`, pronto, publicado, admitido, efetivamente visível, início/fim do drain, solicitação e entrega do recibo. Reproduzir primeiro o cluster de 2 segundos e provar a transição que falhou, antes de editar parâmetros.

### P1 — Comparação B03 ainda não é experimento discriminante verificável

**FATO documental:** as mensagens citam três contagens diferentes de avanços (3.405, 3.393, 3.424), sem anexar os arquivos de execução no diff. **Não concluir** que a diferença 6→7→8 mede efeito do teto sem confirmar que o mesmo trace de gestos, corpus, dispositivo, carga, oráculo, rede, seed e janela temporal foram preservados; o benchmark exige comparar avanços **efetivamente consumidos**, não apenas tentativas de gesto. **Orientação:** anexar identificadores completos de cada execução, hash de `bench/EVALUATOR.sha256`, `bench/MANIFEST.sha256`, contagem esperada vs realizada, logs de admissão e os intervalos de stalls; comparar distribuições de latência e posição do leitor. Uma contagem pequena de stalls por corrida não autoriza otimização por ruído estatístico.

### P1 — B04@32 e integridade visual permanecem sem prova atual

**EVIDÊNCIA relatada anteriormente:** B04 passou com teto 16 e falhou com publicação sem limite (55 por segmento), conforme [revisão 029](https://github.com/wsmontes/feedmine_v2/commit/5efa2afebb5a6a88404d54438df21221fed79d88). **Não existe prova nova** de B04@32 ou @48 nesta janela. **FATO de código:** o receptor de publicação chama `growAdmittedWindowIfPublished` após verificar Edition em [AppComposition.swift:3704–3732](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/FeedMineApp/FeedMineApp/AppComposition.swift#L3704-L3732), com sessão responsável pela janela. **Risco:** otimizar abastecimento causando instalação não contígua, salto de âncora/offset ou mudança silenciosa no prefixo. **Owner:** repetir B04 na árvore final e capturar IDs, bounds e offset antes/depois de publicações concorrentes, inclusive idle de 10 minutos. O B04 é prova de UI, não só de array.

### P1 — Pendências da reserva não foram alteradas pelos dois commits

**FATO estático preservado:** [PreparedReserve.swift:188–258](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/Sources/FeedMineRuntime/PreparedReserve.swift#L188-L258) ainda exige prova de progresso com 112 cartas de fonte incompatível e a 113ª alternativa; [PreparedReserve.swift:333–343](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/Sources/FeedMineRuntime/PreparedReserve.swift#L333-L343) transforma 3 falhas transitórias em `exhausted`, contrariando [INV-17](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/docs/architecture/PRODUCT_INVARIANTS.md#L154-L169); [PreparedReserve.swift:239–303](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/Sources/FeedMineRuntime/PreparedReserve.swift#L239-L303) mantém risco de `outstanding` sob duas oportunidades com fechamento invertido. **Ocorrência real não comprovada.** **Owner:** três fixtures específicas (112+1; 5xx×3→recuperação; duas janelas invertidas), sem criar fila ou owner paralelo.

### P1 — Segurança de redirects continua bloqueadora

**FATO estático anterior sem modificação:** [FeedDiscoveryTransport.swift:75–90](https://github.com/wsmontes/feedmine_v2/blob/ca532f25/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L75-L90) valida destino final depois da requisição que pode ter seguido redirect. **Owner:** negar cada hop proibido antes de conectar e provar **zero requisições** ao destino privado de teste; preservar transporte de benchmark autorizado apenas em build instrumentada.

### P1/P2 — Editorial, filtros, persistência e multimídia

**Sem mudanças nesta janela.** P1: v6 ainda piora distância entre tipos no [replay 629](https://github.com/wsmontes/feedmine_v2/blob/product/integrity-20261024/docs/reviews/2026-10-24-v6-replay-fila-629.md); selecionar preset salvo e transições concorrentes ainda precisam de prova; primeira tela, âncora ±1 pt, A→B→A, salvos V1→V2, PD-10 e B05/B06 seguem sem certificação integrada. P2: medir disco/memória e vídeo real; 14 claims de vídeo e zero publicação no [comparativo de reserva](https://github.com/wsmontes/feedmine_v2/blob/product/reserve-20261024/docs/reviews/2026-10-24-reserva-comparacao-catalogo-real.md). **Opinião:** priorizar continuidade e estabilidade antes de ampliar volume ou adicionar playback flutuante.

## Release e evidências

**Estado desta revisão:** GitHub permitiu ler commits, branches, PR, normas, código, testes e scripts; o SHA `ca532f25` não apresenta check-runs (0) nem status conclusivo. **Não executado por este monitor:** Swift build/test, XCTest, simulador, iPhone físico, B01–B06. **B03: FAIL relatado nas três configurações; não reexecutado independentemente. B04@32: sem prova nova. B06 físico: sem certificação.** Não transportar resultados entre a build 56 distribuída (`1fe0afaf`) e a linha de reserva, nem entre configurações 16/32/48. O benchmark congelado continua soberano.

**Resoluções preservadas apenas por inspeção:** recuperação de adiamentos A→B→A e retenção editorial desde 55; NF-03 Concluído; marcação/contabilidade de reserva; limite de publicação voltou a 32. **Reabertos/não resolvidos:** causa dos stalls B03, B04 na candidata, SSRF, starvation da reserva, falha temporária, concorrência, diversidade, filtros/presets, scroll/offline, migração, PD-10, B05 e B06.

## Handoff concreto ao Mac

```bash
git fetch origin main monitor/architecture product/reserve-20261024 product/integrity-20261024 release/build-56 --tags
git rev-parse origin/main origin/product/reserve-20261024 origin/product/integrity-20261024 origin/release/build-56
git diff --check 8d4766b0..origin/product/reserve-20261024
git diff --stat 8d4766b0..origin/product/reserve-20261024 # deve estar vazio: tentativa + revert
git log --oneline 8d4766b0..origin/product/reserve-20261024
git worktree add --detach /tmp/feedmine-monitor-030 origin/product/reserve-20261024
cd /tmp/feedmine-monitor-030
shasum -a 256 bench/EVALUATOR.sha256 bench/MANIFEST.sha256
swift build
swift test --filter 'SelectionEngine|LocalProductionSlice|InitialProductionSlice|PreparedReserve'
swift test
# No Mac com Xcode, guardar artefatos, .xcresult, identity.txt, traces e hashes:
# B03 completo: scripts/run-discovery-benchmark.sh --gate B03 --full-trace
# B04: executar o driver/oráculo congelado do gate correspondente, sem mudar parâmetros.
# Consultar bench/run.sh, bench/README.md e o contrato antes de executar.
```

**Decisão mínima:** (1) preservar traces brutos das três corridas e localizar a primeira falha publicação→admissão→visibilidade; (2) corrigir o owner responsável, não ajustar lote por palpite; (3) B03 e B04 completos no **mesmo SHA**, corpus e oráculos; (4) retestar B05 e B06 físico na candidata integrada; (5) resolver reserva/segurança e demais gates. Nenhum benchmark, código, teste, script, issue ou PR deve ser modificado por este monitor.

## Memória compacta e registro de SHAs

Monitores recentes: 025 `309c1d20` → 026 `859c34ce` → 027 `c6aee149` → 028 `6885ed5d` → 029 `5efa2afb` → **030 este documento**. Últimos técnicos: `main fb8e65ff`, `next d6a05266`, `integrity 031b27d3`, `reserve 8d4766b0→06e94c71→ca532f25`, `release/build-56 cede37f6`, tag 56 `1fe0afaf`, PR #5 `5b252eaa`. Prioridade aberta: **P0 B03/cauda e segurança de redirects; P1 B04/scroll, reserva 112+1/3×5xx/concorrência, v6, filtros, A→B→A, PD-10, B05/B06; P2 custo/vídeo.** OMP precisa fazer fetch e ler. **Somente este arquivo pode ser alterado pelo monitor.**
