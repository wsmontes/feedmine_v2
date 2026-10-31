# FeedMine V2 — Intenções, entregas, lacunas e decisões de integração

**Revisão externa | 17/out/2026, America/Vancouver | baseline remoto `main@5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`.** Este é um inventário operacional de reconciliação para os agentes, não uma nova especificação ou autorização de release. Foi feito por leitura estática de documentação/código/branches GitHub; **nenhum teste ou benchmark foi executado por esta revisão**. O estado do Mac, trabalho local não publicado e artefatos Git-ignored não são visíveis aqui.

## 1. Ordem de autoridade e como usar

1. [Norte](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_NORTH_STAR.md), [PDs](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/PRODUCT_DECISIONS_2026-10-09.md), [invariantes](https://github.com/wsmontes/feedmine_v2/blob/main/docs/architecture/PRODUCT_INVARIANTS.md), [B01–B06 congelado](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [diretriz de execução](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/V2_AGENT_EXECUTION_DIRECTIVE_2026-10-11.md); depois PRDs/ADRs vigentes.
2. **Entregue na `main`**, **implementado em branch**, **validado no simulador**, **medido no iPhone**, **certificado pelo gate** são cinco fatos diferentes. A existência de commit/teste não equivale a PASS.
3. `monitor/architecture` é um **canal consultivo**. Nenhuma recomendação muda automaticamente ownership, benchmark, prioridades do PO ou autoriza merge; os agentes devem confirmar os achados contra seu checkout.
4. Não ampliar backlog porque o repositório é grande. Escolher o próximo defeito de maior impacto **em jornadas**, reaproveitar owners, evitar scheduler/cache/fila/timer paralelos e não modificar `bench/`.

## 2. Resumo executivo

**Direção de produto melhor articulada; integração funcional ainda aquém.** Desde `main@37633bb3` (build 49) até `main@5e4e2142`, dez commits na `main` são documentais, não alterações de runtime; correções funcionais aparecem em branches. O gargalo de decisão agora é **reconciliar os contratos e integrar só alterações corretas com provas completas**, não criar novas camadas nem multiplicar documentos.

**Conflito P0:** a branch `fix/render-ready-admission` apresenta um `PublishedCard` de imagem como `.textOnly` quando o decode falha **sem alterar o ID**, embora PD-5 e a [regra de prontidão](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-render-ready-admission-rule.md) proíbam alteração da apresentação publicada ou uso de text-only como disfarce de mídia pendente. Esse commit já é ancestral da branch `feat/durable-saves`. Não integrar a cadeia sem resolver.

**Resultado promissor e delimitado:** `fix/deferral-invalidates-list@10bc0bd72cfd` relata em Release/iPhone queda da mediana de intervalos acima de 1,5× o orçamento de 3,02% para 1,51% em jornada controlada de 14 arrastadas (três corridas por lado). É um resultado **reportado pelo commit, não uma auditoria independente dos logs**, não é certificação de fluidez, e não prova que o caminho do gesto esteja desacoplado do trabalho do backend.

## 3. Matriz de intenção → entrega → lacuna → próxima prova

| Intenção/contrato | Entrega já observável | Lacuna / status nesta base | Próxima demonstração útil |
|---|---|---|---|
| Descobrir além das fontes seguidas (Norte, B01, PD-8) | Catálogo snapshot de 77.443 fontes, traversal/planejamento e correções históricas de descoberta constam na `main` | B01 tem histórico de provas em bases diferentes, **sem certificação atual demonstrada neste inventário**. Risco de confundir catálogo empacotado com fontes realmente consultadas/contribuintes | B01 íntegro com corpus externo, fontes contactadas/contribuintes e duas preferências explícitas |
| Runway continuamente adiante sem fim artificial (F05, INV-04/05, B03) | RunwayController, driver, publicação em segmentos e demanda com déficit medido existem; foreground reativa produção | Nenhuma prova B03 de 30 min sobre o **HEAD atual** encontrada; `RunwayController.activate` limpa amostras mesmo ao reativar o mesmo scope | B03 integral, medir runway/local supply/latência/consumo e background→foreground do mesmo escopo |
| Rolagem fluida e não comandando fetch (INV-01/02/03, B04/B06) | Scroll nativo, `LazyVStack`, `FeedVisualMotion` não observável, hold da janela durante gesto | UI ainda executa leituras/checagens e envio por `MainActor`; `fix/deferral-invalidates-list` melhora métrica em branch, não isola causalidade completa | Medir durante gesto com/sem produção, marcar frame stalls e *call stacks*; estudo dedicado de causalidade em outro documento |
| Imutabilidade e prontidão visual (PD-5/9, INV-08/09/17, regra 17/out) | Publicação imutável e decoder local; branch de teste/implementação de readmissão preparada | **P0 de contrato:** `PresentationCard(admitting:)` converte `.hero` em `.textOnly` para mesmo ID por ausência de pixels; testes passam a exigir comportamento proibido | Corrigir antes de merge; provar que mídia pendente não é admitida nem degrada publicação existente e que outras cartas prontas progridem |
| Alteração de filtros com conservação de contexto A→B→A (INV-10, T6, B05) | Identidade contextual/checkpoints; branch `fix/filter-confirmation-boundary` persiste seleção antes de mudar memória | Branch ainda fora da `main`; falha após persistir e antes de mostrar precisa ser distinguida | Integração + simulações de falha de disco, falha de sessão, retorno A→B→A e relaunch offline |
| Salvos, caixas, texto/mídia offline e retenção (F16, PD-10, INV-11) | Biblioteca e bookmarks na `main`; `feat/durable-saves` acrescenta mídia persistida, disponibilidade e retry | Prova ponta a ponta incompleta; derivada de branch com P0 da mídia; não confundir bookmark com conteúdo integral baixado | Reconciliação de dependência P0, salve/feche/limpe cache/desconecte/abra e verifique bytes, texto e mensagens honestas |
| Primeira abertura agradável e honesta (PD-3, F02, F-UX-2) | ColdFeedBootstrap e estado de loading; correção da primeira abertura offline integrada | [revisão 17/out](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-17-first-start-consolidated-review.md) aponta amplitude inicial não certificada, erro de persistência de boas-vindas e idioma truncado | Instalação limpa, fonte lenta, interrupção da rede, preferências, navegação sem botão morto e progressão depois do first paint |
| Diversidade e qualidade editorial (PD-4, B02, interleave 17/out) | Alternância de SourceID e evidência temática/temporal no domínio | [análise de paridade V1](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/2026-10-17-interleave-v1-parity-direction.md): sequenciador V2 não aplica ainda toda variedade temática/geográfica/formato/temporal; não portar números mágicos da V1 | Demonstrar diversidade real entre segmentos num corpus rotulado, sem reordenar o prefixo publicado |
| Busca, pesquisas salvas e retorno (F11/F16) | SearchContext e preset salvo com identidade; UI promete sintaxe `-termo` | [`CandidateProvider.swift:84–93`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineEditorial/CandidateProvider.swift#L84-L93) ainda usa substring literal; cancelar não restaura necessariamente contexto original, conforme revisão de 17/out | Termos AND/NOT, busca unificada, abrir/voltar/cancelar com âncora, salvar/reabrir offline |
| Personalização/controle explícito (F02/F13/PD-11) | Preferências e controles já existem; copy do feedback negativo atualizada | [revisão 17/out](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-17-personalization-conversion-and-v1-reading.md) identifica `.neutral` gravado convertido em exclusão, duas mídias viram `.all`, namespace editorial como assunto, e demora na aplicação | Teste por controle: intenção→persistência→interpretação→efeito futuro→desfazer/erro |
| Leitura local e Ver fonte (F14 + decisões 17/out) | Leitor local quando corpo/texto útil, navegação web sob intenção explícita | Branch `fix/reader-availability-language` corrige casos sem URL; `Ver fonte` ainda não é necessariamente lista interna da fonte, segundo [revisão](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-17-view-source-contract-gap.md) | Navegação interna da fonte, URL inválida, corpo parcial, volta com âncora, salvo offline |
| Local-first/catalog refresh (PD-10/INV-18) | Empacotamento verificável com manifesto/catalog SHA e sincronização desenhada; build 49 reporta preflight OK | Preflight e número de fontes **não** provam sozinho atualização remota não bloqueante, rollback, dados pessoais intactos ou release externa | Verificar update de manifesto/catalog atomizado no aparelho, offline e falhas; registro da build real |
| Integração e simplicidade (INV-12/14/15) | Splits de arquivos grandes e owners mais explícitos em fases anteriores | Muitas branches competindo por AppComposition/UI/Session e testes; risco de merge cruzado e worktree desatualizada | Uma candidata reconciliada e medida, sem criar mais mecanismos, com diff de escopo e owners claros |

## 4. Branches de implementação: não confundir com `main`

| Branch / SHA na consulta | Conteúdo | Parecer atual |
|---|---|---|
| [`fix/deferral-invalidates-list@10bc0bd72cfd`](https://github.com/wsmontes/feedmine_v2/commit/10bc0bd72cfdfcdb2cfe89e2eed7b4a520183f27) | Menos invalidation da lista sob gesto, evidência física reportada | **Priorizar integração isolada após revalidar comportamento e medida** |
| [`fix/render-ready-admission@3c741ce53d4a`](https://github.com/wsmontes/feedmine_v2/commit/3c741ce53d4aef905cc274e18587b7dd12c1632f) | Teste+implementação de imagem decodificada antes da admissão | **HOLD P0**: downgrade `.hero`→`.textOnly` sob mesma identidade |
| [`feat/durable-saves@ab5c6067fa61`](https://github.com/wsmontes/feedmine_v2/commit/ab5c6067fa61af41a3e517f388a072591d51513a) | Preparação/persistência e disponibilidade de mídia salva | **HOLD dependência P0**, validar retenção/reopen offline |
| [`fix/filter-confirmation-boundary@2c642abcd514`](https://github.com/wsmontes/feedmine_v2/commit/2c642abcd514145da92f15a7090f45e42b1d029b) | Confirmação de filtro no disco antes da memória | Revalidar na integração |
| [`fix/reader-availability-language@faf8256af2b2`](https://github.com/wsmontes/feedmine_v2/commit/faf8256af2b28741b71818b4ce1a2c2ab9351b5f) | Texto local sem destino web, linguagem de disponibilidade | Prova UX/offline e integração pendentes |
| `fix/ux-localization`, `fix/a11y-dynamic-type`, `fix/trace-posix-numbers`, `measure/frames-during-scroll` | Locale, Dynamic Type, traço, instrumento de frames | Candidatas isoladas: não certificam UI integrada/fluidez por si |
| `integration/candidate` e antigas branches `omp/*`, `chatgpt/*` | Gates históricos e integração parcial | Não chamá-las de trabalho novo sem SHA/data e comparação; reconciliar owners antes de cherry-pick |

## 5. Gates e release — honestidade de proveniência

O [benchmark vigente](https://github.com/wsmontes/feedmine_v2/blob/main/docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md) registra **B01–B05 PASS históricos (atualização de 11/out)** e remete ao `docs/evidence/ACCEPTANCE_RECORD.md`. Um [relatório posterior, de 13/out](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-13-production-delivery.md) registra B01 `NOT_RUN` naquela corrida (uma cláusula sem prova), B02–B05 `NOT_RUN` naquela sessão e manda preservar a prova histórica sem aplicá-la ao HEAD. **Não reconciliar artificialmente os dois fatos:** são corridas/bases distintas. Para `main@5e4e2142` e branches não integradas, **não há matriz B01–B06 integral nova e verificável por esta revisão**.

A [jornada física build 48](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-16-build-48-aparelho-e-publicacao.md) confirma pixels numa jornada específica e engasgos reais; explicita **fluidez NOT_CERTIFIED; B06 NOT_RUN**. Build 49 sobe versão/proveniência, sem upload ou certificação implícita. TestFlight interno não é release externa.

Próxima matriz obrigatória do **checkout candidato**, não do histórico: `gate | status | SHA/build | corpus/fixture | hash do oráculo | logs/xcresult | condição não satisfeita`. Se não há os artefatos do Mac, registrar `NÃO VERIFICADO NESTA REVISÃO`, não inventar PASS.

## 6. Fila de decisões — impacto antes de micro-otimização

**P0 (integridade da solução):**
1. Reconciliar fronteira publicação imutável vs admissão render-ready; recusar conversão silenciosa de card publicado em text-only. `PresentationCard.swift:88–102` e teste discriminante devem refletir o **contrato**, não a facilidade de passar.
2. Não levar o P0 para `main` indiretamente via branch de salvos.

**P1 (jornada perceptível, validação):**
3. Validar e integrar a correção de scroll em árvore controlada; usar o estudo separado de causalidade antes de declarar resolvido.
4. Provar consumo contínuo (B03) e fronteira UI/background no aparelho/simulador com supply concorrente; manter publicação estável.
5. Provar filtros/salvos/restauração com desligamento real/relaunch e falhas de disco.
6. Corrigir reativação do runway para preservar aprendizagem no **mesmo** escopo ([`RunwayController.swift:283–305`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineRuntime/RunwayController.swift#L283-L305)).

**P2 (produto após estabilização das jornadas):**
7. Corrigir semântica de busca, neutral→exclusão, receitas de mídia, paridade editorial multidimensional, Ver fonte e UX de primeira abertura, sem duplicar subsistemas.
8. Manter TestFlight interno para feedback do dono e executar B06 de verdade antes de release externa.

## 7. Handoff e critérios de fechamento

- Cada owner traz `branch/SHA + diferença de comportamento demonstrada + teste discriminante que falha no estado anterior + prova Mac/iPhone apropriada + impacto no produto + riscos restantes`.
- Para fluidez: **não** aceitar apenas queda de percentual; eliminar engasgos perceptíveis e demonstrar ausência de trabalho de runtime no caminho crítico de gestos (ver estudo separado).
- Proteger `main` e `bench/`; usar worktree própria para cada integração e testar a árvore **final**, não soma de relatórios de branches.
- O OMP lê: `git fetch origin monitor/architecture && git show origin/monitor/architecture:docs/reviews/FEEDMINE_INTENTIONS_VS_DELIVERIES_2026-10-17.md`. Consulta **não equivale** a recepção automática: confirmar leitura no harness.

**Acompanhamento:** atualizar esta matriz por nova evidência, não por sentimento de progresso. Este documento permanece separado do relatório vivo `ARCHITECTURE_MONITOR.md`, e não modifica código.
