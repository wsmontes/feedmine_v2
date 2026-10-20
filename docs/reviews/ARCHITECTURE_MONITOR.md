# FeedMine V2 — Monitor externo de arquitetura, código, produto e release

> **Canal consultivo — somente `monitor/architecture`.** Não autoriza merge, envio TestFlight ou release. O OMP deve fazer `git fetch origin monitor/architecture` e ler este arquivo; a publicação não notifica automaticamente agentes.

## Revisão 010 — 2026-10-20 07:44 PDT (America/Vancouver)

**Intervalo:** último monitor remoto 008 (19/out 11:36 PDT) → 20/out 07:44 PDT; inclui a revisão 009 apresentada no ChatGPT em 20/out 05:39 PDT, **não publicada**. **Método:** leitura pelo conector GitHub do monitor anterior, refs e PRs, comparação de commits, normas vigentes, código crítico, relatórios e artefatos versionados. Nenhuma execução de Swift/XCTest/simulador/iPhone/bench pelo monitor.

**Identidades verificadas:** `main@5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`; `integration/51@8fcfe37c6ff46b68b6754b25852bc1b47d825766`; linha técnica corrente `codex/v2-fluidez-capacidade@5f954b72b20641feca73b6fc07d1e9cca801b9b1` (33 commits à frente da 51, zero atrás); árvore de produto e gates `46191649ab1c7af779022207dd1f5faffbf866c6` (dois commits posteriores de documentação/artefatos, sem mudança de produção); monitor anterior `17938c2fe6130a28fd5c67e2d4b23a004e0c4a1a`. **PRs abertos: 0.** Nenhum novo commit nas referências correntes após a revisão 009; esta publicação atualiza o monitor remoto 008 com as evidências substanciais da candidata 53. Branches antigas de fase, `integration/candidate` e `integration/51` não são a linha técnica mais recente.

### Resumo executivo e consequências para a experiência

A candidata 53 avançou significativamente em fluxo contínuo, abastecimento por fato durável, proteção de background, busca offline, filtros, salvos e apresentação local. A remoção da consulta SQLite durante o render foi associada a melhora medida em **simulador Release**, de **5,44% para 0,12% de misses** na janela de gesto comparável (77/1416 → 2/1678); o trace completo após a correção marca 0,21%, incluindo aquecimento. Esses números são **evidência registrada pelo executor**, não medição independente nem iPhone físico. [Resumo de frames](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/reviews/evidence/2026-10-18-release-hitch/summary.json).

**Não certificar release:** B06 físico `NOT_RUN/BLOCKED`; suíte UI completa com cinco testes falhando; B04 reporta um `not-measurable`; retorno distante tem offset reproduzível de 16 pt e a prova de posição ±1 pt permanece parcial. O produto está mais avançado que a 51, mas ainda há duas violações potenciais de continuidade/identidade no `FeedSession` e um cenário de oferta tardia que exige diagnóstico.

### Mudanças verificadas desde a 51

- [Comparação 51 → linha atual](https://github.com/wsmontes/feedmine_v2/compare/integration/51...codex/v2-fluidez-capacidade): 33 commits, incluindo admissão/pixel residency, otimização da projeção de viewport, publicação incremental, desacoplamento da aquisição, stage budgets medidos, diversidade editorial, busca tipada/paginada, contexto e salvos duráveis.
- [`46191649`](https://github.com/wsmontes/feedmine_v2/commit/46191649ab1c7af779022207dd1f5faffbf866c6): oportunidade local única por supply tardio em `RunwayController`, inclusive quando a política anterior faria hold. Benefício: fonte lenta não deve segurar cartas prontas de outra fonte. Necessita prova de custo de reconsiderações repetidas.
- [`fa79735d`](https://github.com/wsmontes/feedmine_v2/commit/fa79735d5785513d1c41f0f32b18fdbd7b1ff705) e [`5f954b72`](https://github.com/wsmontes/feedmine_v2/commit/5f954b72b20641feca73b6fc07d1e9cca801b9b1): documentação de gates e remoção intencional do tarball de assets do Git. Não tratar como nova árvore de produto.
- [Snapshot da candidata](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/reviews/evidence/2026-10-18-candidate-snapshot/README.md#L42-L62): relatos no SHA `46191649`: Swift 1518 testes/1 skip/0 falhas; app host 158/0; UI 76/9 skips/**5 falhas**; B01 A+B PASS, B02 PASS, B03 PASS (2786 avanços, 0 paradas ≥1s), B04 PASS pelo avaliador (301 instalações, 1 not-measurable), B05 PASS (7/7), **B06 NOT_RUN**. Resultados não executados por este monitor.
- O antigo P0 de hero→texto silencioso, o reset de amostras do runway, a remoção de carta admitida por redecodificação e a falsa confirmação de `SavedMediaCoordinator` em erro de escrita estão **corrigidos estaticamente na candidata**. [`SavedMediaCoordinator.swift:65–105`](https://github.com/wsmontes/feedmine_v2/blob/46191649/Sources/FeedMineComposition/SavedMediaCoordinator.swift#L65-L105) agora usa `recordState` e retorna falha quando a escrita não é confirmada; há teste discriminante relatado.

### Achados e decisões de owner

**P0 — Certificação da candidata indisponível (FATO DOCUMENTAL, não bug P0 comprovado).** [Snapshot:42–62](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/reviews/evidence/2026-10-18-candidate-snapshot/README.md#L42-L62) registra B06 `NOT_RUN`, cinco testes UI falhando e B04 com cláusula não mensurável. **Risco:** promover progresso de implementação a aceitação física. **Owner release:** manter gates de release abertos; obter B06 no iPhone físico e evidência de PD-10, preservar SHA de produto + hashes do catálogo/corpus + logs/.xcresult. Não transformar falhas UI classificadas como ambientais em PASS da suíte.

**P1 — Fim artificial quando itens não prontos ocupam a janela (FATO ESTÁTICO; reprodução pendente).** [`FeedSession.swift:309–333`](https://github.com/wsmontes/feedmine_v2/blob/46191649/Sources/FeedMineRuntime/FeedSession.swift#L309-L333): `publicationHistory.window(...forwardCapacity:)` limita a busca antes de `compactMap(admitted)`; duas imagens indisponíveis podem esconder texto pronto adiante. Viola o comportamento PD-9/INV-17 se reproduzido. **Owner FeedSession:** percorrer progressivamente história local até preencher capacidade com cartas admissíveis ou comprovar fim real, sem saltar cursor, reordenar ou fazer rede no scroll. **Prova:** [imagem sem pixels, imagem sem pixels, texto pronto], capacidade 2, avanço offline; verificar IDs/cursor e nenhuma falsa exaustão.

**P1 — Restauração substitui âncora quando sua mídia não projeta (FATO ESTÁTICO; impacto visual ainda hipótese).** [`FeedSession.swift:557–599`](https://github.com/wsmontes/feedmine_v2/blob/46191649/Sources/FeedMineRuntime/FeedSession.swift#L557-L599): `projectedWindow` escolhe card seguinte ou último como fallback quando a âncora não está nos valores admitidos. **Risco:** reabrir offline em outra história. **Owner FeedSession/checkpoint:** preservar identidade lógica do checkpoint e explicitar indisponibilidade temporária da apresentação; não inventar placeholder render-ready. **Prova:** relaunch de processo com asset da âncora removido, comparar `PublicationCardID` e offset antes/depois.

**P1 — Estabilidade de posição ainda parcial apesar de repouso estável (FATO MEDIDO PELO EXECUTOR).** [E03](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/reviews/evidence/2026-10-18-e03-rest/README.md): repouso de 10 min sem deslocamento e retorno por identidade, mas `start=121.75`, `returned=137.75`, delta **16 pt**. Critério 16±1 foi satisfeito; isso **não prova** a exigência original ±1 pt. Uma configuração com 40 itens/atraso 30 s ficou com uma carta por >15 min, causa não isolada (pode ser fixture, preparação ou produto). **Owner UI/runtime:** distinguir padding fixo de mudança real de geometria e investigar a configuração de uma carta; não afrouxar oráculo nem anunciar correção de posição sem prova.

**P1 — B04 tem observação não mensurável (FATO DOCUMENTAL; não equivale a FAIL do avaliador).** [Snapshot:53–62](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/reviews/evidence/2026-10-18-candidate-snapshot/README.md#L53-L62) relata B04 PASS com um `not-measurable`; [benchmark B04](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md#L82-L88) exige geometria/âncora estáveis, inclusive dez minutos parado. E03 oferece prova complementar de repouso, mas não fecha sozinho toda a régua. **Owner benchmark/release:** localizar a cláusula exata, preservar trace e repetir cenário mensurável sem tocar em `bench/`; distinguir PASS formal de cobertura comportamental incompleta.

**P1 — Artefatos de reprodução incompletos no Git (FATO DE INSPEÇÃO).** [Snapshot:6–18](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/reviews/evidence/2026-10-18-candidate-snapshot/README.md#L6-L18) referencia `candidate-assets.tgz`; a pasta versionada contém `assets.sha256`, `archive.sha256`, patch, logs, mas **não** o tarball, removido em [`5f954b72`](https://github.com/wsmontes/feedmine_v2/commit/5f954b72b20641feca73b6fc07d1e9cca801b9b1). **Risco:** SHA Git sozinho não permite reproduzir bytes do catálogo/corpus. **Owner release:** guardar tarball em armazenamento externo durável com SHA-256 e instrução de recuperação; não reintroduzir binários grandes no Git.

**P2 — Reconsideração fresca pode gastar slices sem ganho (HIPÓTESE).** [`RunwayController.swift:557–575`](https://github.com/wsmontes/feedmine_v2/blob/46191649/Sources/FeedMineRuntime/RunwayController.swift#L557-L575) habilita oportunidade local por novo supply. **Owner runway:** medir 100 fatos tardios com runway saudável: slices úteis/vazios, latência, CPU e progressão; ajustar no owner existente, sem fila/timer/scheduler paralelo.

**P2 — Exceção aritmética ao cap de 2.000 (FATO ESTÁTICO, baixo impacto imediato).** [`FeedSession.swift:364–383`](https://github.com/wsmontes/feedmine_v2/blob/46191649/Sources/FeedMineRuntime/FeedSession.swift#L364-L383): âncora na primeira carta e capacidade futura 3000 podem preservar 3001. **Owner FeedSession:** validar bounds ou formalizar exceção; o cap é guarda de memória, não meta de runway.

### Normas aplicadas, pendências e release

Normas lidas: [North Star](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/product/PRODUCT_NORTH_STAR.md), [decisões 09/out](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [diretriz 11/out](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/architecture/PRODUCT_INVARIANTS.md) e [benchmark vigente](https://github.com/wsmontes/feedmine_v2/blob/codex/v2-fluidez-capacidade/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md). A experiência real de descoberta/continuidade precede contagem de testes e micro-otimização. INV-16 proíbe quotas mágicas; PD-9 proíbe head-of-line por item não pronto; PD-10/INV-18 exigem catálogo público verificável, atualização não bloqueante e preservação de dados pessoais. TestFlight interno para feedback **não equivale** a certificação pública B01–B06.

**Resolvidos na candidata 53 (não na main):** fallback hero→texto silencioso, perda de amostras ao reativar escopo, remoção de card admitido por falha de redecodificação, confirmação falsa de disponibilidade salva, escopo/expressão de busca e neutralidade de filtros. **Abertos:** P0 release, P1 continuidade/âncora/posição/B04/artefatos acima; prova completa de PD-10 e migração V1→V2 no mesmo build; falhas UI reais ainda não resolvidas; B06 físico. O antigo fix de scroll `10bc0bd7` não precisa ser cherry-picked cegamente: a nova linha possui sua própria medição e implementação.

### Provas discriminantes e comandos no Mac

```bash
git fetch origin main integration/51 codex/v2-fluidez-capacidade monitor/architecture
git rev-parse origin/main origin/integration/51 origin/codex/v2-fluidez-capacidade
git checkout --detach 46191649ab1c7af779022207dd1f5faffbf866c6
git diff --check && swift build && swift test
swift test --filter 'FeedPresentationAdmissionTests|FeedSessionWarmRestoreTests|SavedMediaCoordinatorTests|RunwayControllerTests'
scripts/run-discovery-benchmark.sh --gate B01 --profile A --profile B
scripts/run-discovery-benchmark.sh --gate B02
scripts/run-discovery-benchmark.sh --gate B03 --full-trace
scripts/run-discovery-benchmark.sh --gate B04
scripts/run-discovery-benchmark.sh --gate B05
# B06: executar em iPhone físico com transporte/configuração do benchmark,
# o mesmo SHA e hashes de catálogo/corpus; guardar logs e xcresult.
```

Complementar: fixture offline de itens não prontos antes de texto pronto; reabertura de processo com imagem da âncora ausente; scroll reverso e offset por identidade; repouso de 10 min com supply tardio; filtros A→B→A; salvos sob falha SQLite/ENOSPC e force quit; busca salva e paginação offline; prova PD-10 com manifesto igual/alterado/inválido. Nenhum PASS novo é alegado por este monitor.

### Memória compacta e últimos SHAs

- **003–008:** `main@5e4e2142`; `integration/51@8fcfe37c`; fix isolado de gesto `10bc0bd7`; P0 hero→texto corrigido na 51; P1 de starvation, âncora, reentrada e salvos; B06 da 51 não executado. Monitor 008 publicado em `17938c2f`.
- **009 (20/out 05:39 PDT, ChatGPT apenas):** candidata `46191649` na branch `codex/v2-fluidez-capacidade@5f954b72`; 33 commits após 51; B01–B05 relatados PASS, B06 NOT_RUN; novos achados de B04/artefatos e dois P1 `FeedSession` persistentes; publicação bloqueada.
- **010 (20/out 07:44 PDT):** refs, PRs, normas, código e evidência reconferidos; sem novos commits desde 009; consolidada a nova linha no canal remoto. **Últimos SHAs de produto verificados:** `main 5e4e2142`, `51 8fcfe37c`, `53 46191649`, `HEAD docs 5f954b72`.

**Handoff:** `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/ARCHITECTURE_MONITOR.md`. A leitura é responsabilidade explícita do OMP. Monitor não altera `main`, código, testes, scripts, benchmark, coordenação, issues ou PRs.
