# F20 — Voltar ao FeedMine, reconhecer novidades e continuar lendo

**Status:** especificação de produto/UX candidata, 2026-10-10. Não é implementação, prova executada ou autorização para substituir B01–B06.  
**Referências comuns:** [norte](PRODUCT_NORTH_STAR.md), [decisões](PRODUCT_DECISIONS_2026-10-09.md), [invariantes](../architecture/PRODUCT_INVARIANTS.md), [benchmark vigente](DISCOVERY_ACCEPTANCE_BENCHMARK.md), [mapa de impactos](PRODUCT_SPEC_DEPENDENCIES_F11_F20.md), [matriz V1→V2](../v1-study/UI_TRANSFER_MATRIX.md).

## 1. Promessa e o que é produto pronto

Reabrir o FeedMine deve parecer reencontrar seu lugar e, quando houver material novo, descobrir que existem oportunidades de leitura sem que o conteúdo publicado seja mexido pelas costas do usuário.

**Pronto significa:** UX20-A–E devem demonstrar retorno, novidades e transições sem mudança involuntária de história, duplicata falsa ou estado inventado. B03/B04/B05 permanecem os gates transversais e nenhuma cota da V1 deve ser transportada.

## 2. Evidência V1/V2 e gargalo

Na V1 `WhatsNewManager` combinava carousel e aquisição extra, usando cotas de candidatos; o app mantinha baseline de novidades e atividades de foreground/badge. Esses detalhes técnicos da V1 não devem migrar. Na V2, restore local, sucessor de Edition e refresh existem conceitualmente e parcialmente em código; a matriz não comprova a semântica de 'novidade' e efeitos de retorno (badge/scene-phase) em todos os casos.

## 3. Contrato de experiência

- **R1 — Retomar antes de atualizar:** após suspensão, relançamento ou retorno offline, mostrar imediatamente o contexto e card local válido antes de depender de rede; nunca esquecer a posição por haver notícias recentes.

- **R2 — Novidade = nova oportunidade, não novo scroll involuntário:** permitir perceber que histórias novas estão disponíveis sem inserir acima do card atual, trocar a Edition silenciosamente ou falsificar exposição de itens não vistos.

- **R3 — Atualização com escolha:** a pessoa deve compreender o gesto que passa a uma história/Edition mais recente, distinguindo refresh intencional de manutenção passiva.

- **R4 — Identidade e deduplicação:** mesma matéria reapresentada sem mudança material não vira repetidamente 'novidade'; edições materiais seguem PD-1 e permanecem ocorrências explícitas.

- **R5 — Contextos independentes:** novidades em B não roubam o foco de A; trocar A→B→A aproveita o estado compatível. Presets/idiomas restritivos continuam válidos.

- **R6 — Estado honesto:** offline sem conteúdo novo não anuncia atualização; quando há material local novo mas não elegível no contexto, não mostra badge enganoso.

- **R7 — Notificações opcionais:** badge/push/local notification só se houver utilidade explícita, sem pressupor servidor FeedMine ou detecção contínua com app suspenso. O produto não depende de notificação para ser considerado funcional.

## 4. Benchmark UX20 (provas black-box)

| Caso | Cenário e gesto reais | Oráculo de aprovação |
| --- | --- | --- |
| **UX20-A** | Ler até card X no contexto A; sair; admitir conteúdo adicional; voltar. | X permanece no mesmo lugar e Edition anterior intacta, com notícia de disponibilidade não intrusiva quando apropriado. |
| **UX20-B** | Solicitar atualização explicitamente após A; avaliar nova Edition e voltar. | Transição deliberada e clara; não há contaminação retroativa de X. |
| **UX20-C** | A→B→A com novidades diferentes e rede cortada. | Contextos independentes; A conserva posição/estado e acesso offline ao preparado. |
| **UX20-D** | Receber a mesma matéria várias vezes e uma edição material verdadeira. | Sem falsa repetição por fetch duplicado; nova ocorrência legítima identificável conforme PD-1. |
| **UX20-E** | Suspender por tempo suficiente para OS impedir background; voltar sem rede. | Sem promessa falsa de aquisição durante suspensão; melhor estado local aparece antes de qualquer erro remoto. |

Executar com dados/versão/dispositivo identificados, evidências de gestos reais, capturas e identidades de entrada/saída. Cada caso recebe **PASS / FAIL / NOT_RUN / BLOCKED** e motivo. Os gates B01–B06 não são substituídos nem reduzidos; percentuais e durações do benchmark vigente não são convertidos em cotas de produção.

## 5. Documentos conectados e limites

[F02 primeiras escolhas](F02_DISCOVERY_FEED_ONBOARDING_PRD.md); [F05 runway/refresh](F05_CONTINUOUS_RUNWAY_PRODUCT_PRD.md); [F07 contextos](PRODUCT_AUDIT_10_FRONTS.md); [F09 restore](PRODUCT_AUDIT_10_FRONTS.md); [F15 retomada de áudio](F15_PODCAST_PLAYBACK_CONTINUITY_UX_PRD.md); [PD-1 edições e PD-5 imutabilidade](PRODUCT_DECISIONS_2026-10-09.md).

**Fronteira:** F05 mantém abastecimento enquanto há uso; F09 garante restauração/offline. F20 define **o que a pessoa vê e decide ao voltar e perceber novidades**, sem pedir um segundo motor de novidades ou execução ilimitada em background.

**Não-objetivos:** copiar automaticamente a V1, exigir conta/servidor próprio, criar UI com ações mortas, quebrar o prefixo publicado ou definir soluções técnicas nesta etapa.

## 6. Estado e conflitos em aberto

**Jornada UX20 integral: NOT_RUN.** O que existe nos componentes/testes do repositório é evidência de capacidade, não certificação desta promessa. Diferenças deliberadas da V1 devem ser aceitas ou revertidas **por decisão de produto explícita** e não por presunção de paridade.

---

## Referências técnicas externas — F20

Estas referências complementam o PRD e não alteram seus critérios de aceitação, nem comprovam funcionalidade já implementada.

**Aplicação:** Retomar Edition/cursor local antes de rede, mostrar novidades sem mutação silenciosa.

- [ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase) — Transições app ativo/inativo.
- [Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) — Trabalho oportunista de background.
- [MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit) — Medir experiência de retorno.
- [HIG Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback) — Novidade real sem deslocar feed.

**Índice integral:** [Pesquisa F01–F20](../research/FeedMine_V2_referencias_F01-F20_2026-10-10.md). Usar os responsáveis/pipelines já existentes; não criar um mecanismo concorrente por causa de uma API ou padrão de interface.

## Pesquisa Apple transversal — F20 (2026-10-10)

Cenários de plataforma complementares: [F21](F21_IOS_SCENE_SESSION_CONTINUITY_PRD.md) · [F23](F23_BACKGROUND_EXECUTION_TRANSFERS_PRD.md) · [F27](F27_DEVICE_PRESSURE_PERFORMANCE_EVIDENCE_PRD.md). Fonte primária: [Apple — Choosing Background Strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app). Consultar [matriz Apple F21–F27](PRODUCT_AUDIT_APPLE_FRONTS_21_27.md) e [índice de documentação Apple](../research/APPLE_IOS_UI_UX_RELIABILITY_2026-10-10.md).

Estas referências não modificam este PRD, não autorizam outro engine/store e não comprovam os benchmarks B01–B06.

## Ouro V1 relacionado — novidades honestas sem `WhatsNewManager` (G15)

[Garimpo V1: 15 oportunidades com prova no código](../v1-study/V1_HIDDEN_GEMS_PRODUCT_MINING_2026-10-10.md) registra baseline de novidades da V1 e separa seu valor de produto do pool/booster. [Briefs de implementação por jornada](V1_GOLD_IMPLEMENTATION_BRIEFS_2026-10-10.md) (S6) exige indicação de novidades já prontas, por gesto explícito, preservando Edition e âncora; [Lista do que não portar](../v1-study/V1_GOLD_DO_NOT_PORT_2026-10-10.md) lista o carrossel concorrente que não se deve portar.
