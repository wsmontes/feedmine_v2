# FeedMine V2 — Monitor externo de arquitetura, código, produto e release

Canal consultivo exclusivo de `monitor/architecture`. O OMP precisa buscar e ler este arquivo; não existe notificação automática nem autorização de merge/release.

## Revisão 014 — 21/out/2026, 03:46 PDT (Vancouver)

**Intervalo:** revisão remota 010 (20/out 07:44 PDT) até agora; inclui revisões 011–013 não publicadas. **HEADs verificados:** `main@5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`; `integration/51@8fcfe37c6ff46b68b6754b25852bc1b47d825766` (histórica); candidata 53 medida `46191649ab1c7af779022207dd1f5faffbf866c6`; linha ativa `codex/v2-fluidez-capacidade@d50ad3be3a6f7d31ad9eac59dd7aecc88fe00226`. Último monitor remoto `6fa9db0ef176880966219d97cb96e7c35b4ba99b`. **41 commits após `5f954b72`**, zero commits novos desde a revisão 013; PRs abertos: 0. [Comparação GitHub](https://github.com/wsmontes/feedmine_v2/compare/5f954b72b20641feca73b6fc07d1e9cca801b9b1...d50ad3be3a6f7d31ad9eac59dd7aecc88fe00226).

### Parecer de produto

A linha ativa avançou em primeira tela, reoferta de mídia, runway, identidade de restauração e upgrade V1→V2. A correção D10 evita restauração pela Edition errada; o ensaio D7-A importa fontes/coleções e preserva os arquivos originais. **O principal risco novo é a perda definitiva de histórias adiadas por mídia:** uma fila volátil limitada a 32 passa a ser a única memória de skips depois de cursor unidirecional. A continuidade do feed vale mais que micro-otimizações.

**P0 de certificação (lacuna documental, não defeito P0 provado):** B01–B05 foram relatados para `46191649`, não para `d50ad3be`. B06 físico sem nova prova; UI pós-fix D4 não executada; B04 antigo com `not-measurable`; E03 reportou retorno distante com delta de 16 pt, não ±1 pt. **Release não certificada.** Owner release: matriz B01–B06 com SHA, catálogo/corpus, driver congelado, logs, .xcresult e prova física. TestFlight interno não equivale a certificação pública.

**P1 — teto de 32 esquece histórias. Fato estático, efeito end-to-end não reproduzido.** [PendingMediaReconsideration.swift:8–68](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/Sources/FeedMineRuntime/PendingMediaReconsideration.swift#L8-L68) usa `removeFirst()` quando cheio; [teste:987–1000](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/Tests/FeedMineRuntimeTests/LocalProductionSliceTests.swift#L987-L1000) confirma a expulsão. Owner runtime: recuperar elegibilidade por supply durável/consulta existente, não elevar o número mágico. Prova: 33 pendências, primeira fica pronta depois, cursor avança, processo reabre, história volta a concorrer.

**P1 — reoferta esquecida sem publicação. Fato estático.** [LocalProductionSlice.swift:153–190](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/Sources/FeedMineRuntime/LocalProductionSlice.swift#L153-L190) esquece reconsideradas também em caminhos sem publicação ou com retenção editorial. Owner: esquecer só resolvidas de forma definitiva; testar retenção PD-4 e publicação em oportunidade posterior.

**P1 — fim artificial apesar de conteúdo pronto. Fato estático, reprodução pendente.** [FeedSession.swift:317–329](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/Sources/FeedMineRuntime/FeedSession.swift#L317-L329) aplica capacidade antes de descartar itens não prontos. Owner: percorrer histórico local até completar cartas admissíveis ou comprovar fim real, preservando ordem/ID. Prova offline: imagem pendente, imagem pendente, texto pronto, capacidade 2.

**P1 — âncora pode ser trocada na reabertura. Fato estático; salto perceptível não medido.** [FeedSession.swift:557–599](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/Sources/FeedMineRuntime/FeedSession.swift#L557-L599) usa carta seguinte/última como fallback se âncora não projeta. D10 resolve outro defeito, não este. Owner: manter ID durável sem placeholder render-ready; testar relaunch offline com asset ausente, ID e offset.

**P1 — primeira tela não tem prova UI após fix. Fato documental.** [D4](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/docs/reviews/evidence/2026-10-20-first-screen/README.md) registra 141 pt de conteúdo em viewport de 730 pt, gap 589 pt; gate geométrica foi alterada, mas jornada UI não repetida. Owner UI: medir primeira exposição real e distinguir saída degradada de cobertura.

**P1 — salvos V1 preservados, mas inacessíveis na V2. Fato documental.** [LegacyUserStateImport.swift:112–130](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/Sources/FeedMineComposition/LegacyUserStateImport.swift#L112-L130) marca `notImportedInThisBuild`; [D7-A](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/docs/reviews/evidence/2026-10-20-v1-upgrade/README.md) preservou dois artigos no arquivo V1 sem importá-los. Não há apagamento demonstrado. Owner migração: acesso/migração durável, teste em iPhone com banco real, interrupção e idempotência.

**P2 — complexidade de reentrada/retry. Hipótese, não corrida provada.** [FeedRunwayDriver.swift:209–309](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/Sources/FeedMineComposition/FeedRunwayDriver.swift#L209-L309): testar aposentadoria/cancelamento e 100 fatos tardios, evitando ownership paralelo. **P2 documental:** referência a `docs/product/PD-2026-10-20-build-54-reader-promise.md` não recuperável no HEAD; corrigir referência quando apropriado.

### Resoluções e memória

Corrigidos estaticamente na linha ativa (não na main): fallback hero→texto, reset de amostras runway, remoção de carta admitida por redecodificação, confirmação de disponibilidade sem gravação e D10 Edition errada. Permanecem: reoferta/forget, fim artificial, âncora, D4, migração de salvos, posição ±1 pt, B04, artefatos completos e B06.

Histórico compacto: revisões 003–008 — main `5e4e2142`, build 51 `8fcfe37c`, fix scroll isolado `10bc0bd7`, monitor 008 `17938c2f`. Revisões 009–010 — build 53 `46191649`, linha `5f954b72`, monitor 010 `6fa9db0e`. Revisões 011–013 (não publicadas) — 41 commits até `d50ad3be`, D4/D7/D10 e riscos de mídia; HEAD inalterado até 014.

Normas relidas: [North Star](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/docs/product/PRODUCT_NORTH_STAR.md), [decisões](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/docs/architecture/PRODUCT_INVARIANTS.md) e [benchmark](https://github.com/wsmontes/feedmine_v2/blob/d50ad3be/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md).

**Provas no Mac:** fazer fetch de main e branch ativa, checkout detached `d50ad3be`; executar `git diff --check && swift build && swift test`; filtrar `LocalProductionSliceTests|DurableAnchorRestoreTests|FirstScreenPresentationTests|LegacyUserStateImportTests|FeedRunwayDriverTests`. Executar jornadas de 33 pendências com relaunch, PD-4, continuidade offline, âncora sem mídia, primeira exposição D4, upgrade real, A→B→A, repouso e posição; repetir B01–B05 na mesma árvore com oráculos congelados e B06 em iPhone físico. Nenhum PASS novo alegado.

**Handoff:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. Monitor consultivo; não altera main, produção, testes, benchmark, scripts, coordenação, issues ou PRs.
