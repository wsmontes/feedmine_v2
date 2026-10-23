# FeedMine V2 — Monitor externo de arquitetura, produto e release

**Revisão 023 · Vancouver, 22/out/2026, 21:40 PDT.** Canal consultivo: apenas `monitor/architecture`. OMP precisa fazer fetch e ler; não há notificação automática.

## Base e intervalo

Último relatório remoto: revisão 014 (21/out 03:46 PDT), commit `b7d385a9`. Consolidam-se as revisões 015–022 que não foram publicadas. Desde a revisão 022 (22/out 15:38 PDT), **nenhum commit novo** nos HEADs verificados: `main@5e4e2142`; base `codex/v2-fluidez-capacidade@d50ad3be`; mídia `codex/direction-media-deferrals-20261021@15d8bbbc`; validação `codex/direction-validation-20261021@3eee1935`; mídia/release `codex/candidate54-deferral-experiment@145d12a3`; posição `codex/candidate54-position-experiment@77e9f7d1`; PR #5 `kiro/review-build54@5b252eaa`. `integration/candidate@1b990306` é anterior, não a candidata corrente. PR #5 está aberto e contém uma auditoria documental, mas seu diff contra main inclui mudanças herdadas de código: não fazer merge como se fosse docs-only. [Comparação da base com mídia](https://github.com/wsmontes/feedmine_v2/compare/d50ad3be...15d8bbbc); [divergência entre mídia e posição](https://github.com/wsmontes/feedmine_v2/compare/145d12a3...77e9f7d1) (3 commits exclusivos contra 2).

## Resumo executivo

A linha de mídia resolveu estaticamente três riscos antigos: exame local continua além de imagens pendentes, adiamentos deixaram de ser expulsos após 32 entradas e reofertas não publicadas deixam de ser esquecidas. **Não há árvore integrada com a última correção de posição e a última correção de mídia; release não certificada.** Prioridade: continuidade e segurança da descoberta, não micro-otimizações.

## Achados priorizados — classificação e orientação

**P0 segurança / bloqueador de release — validação tardia de redirecionamentos. FATO de ordem das chamadas, exploração não demonstrada.** [FeedDiscoveryTransport.swift:69–101](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMineSyndication/FeedDiscoveryTransport.swift#L69-L101) valida o host final somente após `URLSession.bytes(for:)`; redirecionamentos automáticos podem já ter alcançado destino que a política proíbe. Owner rede: verificar a política em cada redirecionamento **antes** da conexão. Prova Mac: servidor de teste confirma recusa e ausência de request ao destino vedado. Auditoria [PR #5](https://github.com/wsmontes/feedmine_v2/pull/5).

**P1 continuidade — associação de adiamento entre Editions. FATO de armazenamento; perda A→B→A é HIPÓTESE end-to-end.** [MediaDeferralStore.swift:70–89](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMinePersistence/MediaDeferralStore.swift#L70-L89) substitui `media_deferred_edition_id` por origem; [teste:1020–1026](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Tests/FeedMineRuntimeTests/LocalProductionSliceTests.swift#L1020-L1026) aceita a transferência. Owner runtime/persistência: preservar elegibilidade por contexto na autoridade durável existente, sem segundo scheduler. Prova: origem X adiada em A e B, B grava por último, mídia fica pronta, volta a A após relaunch offline; X ainda alcançável.

**P1 continuidade — página pronta mas retida pode encerrar reoferta. FATO de fluxo; starvation é HIPÓTESE.** [PendingMediaReconsideration.swift:155–186](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMineRuntime/PendingMediaReconsideration.swift#L155-L186) usa `ready.isEmpty` para continuar, antes da seleção editorial [LocalProductionSlice.swift:131–189](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMineRuntime/LocalProductionSlice.swift#L131-L189). PD-4 pode reter item tecnicamente pronto. Prova: 32 retidos + 33º publicável, uma única oportunidade, runway saudável; alcançar 33º sem outro evento.

**P1 primeira tela — geometria antiga pode contar. FATO estático, exposição precoce não reproduzida.** [FeedScreenStore.swift:452–488](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMineUI/FeedScreenStore.swift#L452-L488) usa máximo de posições acumuladas sem podar IDs retirados. Owner UI: medir somente cartas atualmente renderizadas; provar D4 em jornada UI após churn. [Evidência anterior](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/docs/reviews/evidence/2026-10-20-first-screen/README.md) não é PASS pós-correção.

**P1 preferências — possível perda de alterações rápidas. FATO de snapshots assíncronos; efeito não reproduzido.** [ReaderDiscoveryPreferencesView.swift:158–164](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMineUI/Settings/ReaderDiscoveryPreferencesView.swift#L158-L164). Owner settings: mutar campo contra estado mais recente no owner atual. Prova: dois controles antes de readback, reabrir, ambos persistidos.

**P1 seleção de fontes — alias pode deixar seleção com chave antiga. FATO de SQL; impacto condicionado à jornada.** [ReaderLibraryStore.swift:119–169](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMinePersistence/ReaderLibraryStore.swift#L119-L169) reconcilia identidade e memberships, mas não `reader_preferences.source_keys`; [ReaderPreferencesStore.swift:168–190](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMinePersistence/ReaderPreferencesStore.swift#L168-L190) lê seleção sem resolver anchor. Owner biblioteca: fixture com `newKey` selecionado e reconciliação para `oldKey`; preservar seleção na mesma transação ou leitura.

**P1 observação temporal — timestamps iguais podem gerar erro de feed. FATO do guard, efeito visual a reproduzir.** [RunwayController.swift:330–344](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMineRuntime/RunwayController.swift#L330-L344). Prova: duas observações simultâneas sem banner de falha.

**P1 posição/offline — integração e prova pendentes.** [Experimento 77e9f7d1](https://github.com/wsmontes/feedmine_v2/commit/77e9f7d1905cc50d7f885dfbdc1bdb320dfe3108) melhora captura do topo, mas não está integrado à última linha de mídia. Owner UI/runtime: validar identidade e offset no scroll reverso, repouso, force quit e relaunch offline; não afirmar ±1 pt sem medição.

**P1 migração — salvos V1 preservados, inacessíveis na V2. FATO documental.** [D7-A](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/docs/reviews/evidence/2026-10-20-v1-upgrade/README.md) importou fontes/coleções, não os dois artigos salvos. Prova de upgrade com dados reais, interrupção e idempotência.

**P2 desempenho — paginação durável possivelmente cara. HIPÓTESE.** [MediaDeferralStore.swift:152–197](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMinePersistence/MediaDeferralStore.swift#L152-L197). Medir `EXPLAIN QUERY PLAN` e p95 com 10k/100k antes de criar índices/caches. **P2 banco:** [RuntimeDatabase.swift:125–135](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/Sources/FeedMinePersistence/RuntimeDatabase.swift#L125-L135) permite fallback de grafia por erro de criação genérico; restringir ao erro esperado, testar falha de permissão.

## Release e memória

**P0 de certificação (lacuna, não defeito P0 de runtime provado):** sem matriz B01–B06 da **mesma árvore integrada**; B06 físico não demonstrado; PD-10 (catálogo público, snapshot verificável, sincronização discreta e recuperação) sem certificação completa da candidata. Não houve execução de XCTest, simulador, iPhone ou benchmark por este monitor. [North Star](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/docs/product/PRODUCT_NORTH_STAR.md), [decisões](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/docs/architecture/PRODUCT_INVARIANTS.md), [benchmark](https://github.com/wsmontes/feedmine_v2/blob/15d8bbbc/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md).

Histórico compacto: 003–010 main `5e4e2142`, integração 51 `8fcfe37c`, build 53 `46191649`, monitor 010 `6fa9db0e`; 011–014 linha `d50ad3be`, monitor 014 `b7d385a9`; 015–019 (não publicadas) linha mídia `15d8bbbc`, release `145d12a3`, posição `77e9f7d1`; 020–022 (não publicadas) PR #5 `5b252eaa` e segurança/UX; 023: sem commits novos, consolidação e verificação de alias/seleção. **Corrigidos estaticamente na linha de mídia:** janela de conteúdo pronto, expulsão após 32, esquecimento de reoferta sem publicação. Permanecem os P1 acima.

**Comandos Mac:**
```bash
git fetch origin main monitor/architecture codex/direction-media-deferrals-20261021 codex/candidate54-deferral-experiment codex/candidate54-position-experiment
git switch --detach 15d8bbbca7efbd4ee8833baa860b95a8dd053fa7
git diff --check && swift build && swift test
swift test --filter 'LocalProductionSliceTests|FeedRunwayDriverTests|FeedSessionCheckpointTests|FirstScreenPresentationTests'
```
Provas adicionais: redirect sem conexão proibida; A→B→A; 33ª publicável; preferências e alias; primeira tela; posição e reabertura; integrar em um SHA e repetir B01–B05 com oráculos/corpus congelados e B06 no iPhone físico, com logs e hashes. O monitor não altera main, produção, testes, benchmarks, scripts, coordenação, issues ou PRs.

**Handoff:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`.
