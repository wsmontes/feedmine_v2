# F05 — Diagnóstico preliminar de continuidade e runway (2026-10-10)

**Estado:** auditoria de código/documentos em `main`; evidência parcial, **não** execução de B03 nem aprovação de comportamento. Não altera código, PRDs ou critérios do benchmark.

## Achados de implementação

1. **Existe separação real entre UI, sessão, runway, aquisição e publicação.** `RunwayController` avalia cobertura e pressão; `FeedRunwayDriver` executa efeitos causais; `FeedSession` mantém histórico admitido separado de trabalho externo. Isso sustenta o princípio do feed sagrado, mas por si só não prova continuidade prolongada.
2. **Há números fixos na composição de produção.** Em `FeedMineApp/FeedMineApp/AppComposition.swift`, `resources` fornece `examinedCandidateCapacity: 32`, `readyProbeBound: 32`, `readyProbeCeiling: 256`, `forwardAdvanceProbeBound: 256`, **`reserveCards: 16`**, `targetWorkCapacity: 2`, `batchCapacityPerNewExecution: 1`, `observationCapacityPerBatch: 32`, `byteCapacityPerBatch: 1_000_000` (linhas 992–998 na revisão inspecionada). Alguns são limites físicos legítimos por operação; **a reserva fixa de 16 como política de produto é especialmente suspeita** à luz de INV-04/INV-16/PD-8 e exige prova de que não governa a continuidade como uma cota.
3. **O tempo de preparo de mídia usa fração fixa de timeout de rede.** No mesmo arquivo, `mediaWait = configuration.timeoutIntervalForRequest / 4`, usado como deadline nas oportunidades de prefetch (linhas 1126–1141). Pode proteger a chamada, mas não deve converter imagem pendente em decisão editorial text-only, nem excluir persistentemente um candidato: PD-5/PD-9/INV-17 distinguem prontidão, deferral e decisão válida de degradação.
4. **Aquisição independente de escassez local foi introduzida, mas com alcance limitado.** `FeedRunwayDriver` aceita `selectedSourceCoverage` e examina alvos elegíveis das **fontes selecionadas**, inclusive quando há runway saudável (linhas 54–69, 181–185). `CONTINUOUS_FEED_RUNWAY_DESIGN.md` documenta a correção D1 e seus testes para quatro fontes selecionadas. Em `AppComposition.swift` o driver recebe `selectedSourceCoverage` (linha 1152). Portanto é incorreto dizer que toda aquisição externa depende de esgotar supply; **também é incorreto afirmar que essa cobertura visita progressivamente as 77.443 fontes do catálogo**.
5. **O universo inicialmente conectado ainda é limitado.** `AppComposition` inicializa `TrustedFeed.catalogOrDevelopment(limit: 64)` por padrão (linha 99) e resolve preferências de fontes a partir desse conjunto. Deve-se investigar a passagem de catálogo global → elegibilidade → alvos ativos (F01/F05); não confundir tamanho de lote operacional com universo permanentemente fechado.
6. **A prova prolongada ainda não passou.** `PRODUCT_AUDIT_10_FRONTS.md` e `DISCOVERY_ACCEPTANCE_BENCHMARK.md` registram aproximadamente 4 minutos/135 cards em uma seleção pequena. B03 exige 30 minutos de avanços reais em corpus rico (≥5.000 itens elegíveis), com rajadas, sem fim artificial e sem paralisação visível ≥1 segundo por falta de runway. Esse teste **não está aprovado**. O resultado pequeno não prova a causa específica do esgotamento; não atribuir automaticamente o fim aos valores fixos sem execução de perfil/trace.

## Contrato de produto a manter em F05

- **Duas obrigações complementares:** (A) runway presentation-ready adaptativo e sempre à frente do consumo; (B) expansão progressiva de fontes/conteúdo quando há capacidade, inclusive quando o runway está saudável.
- **Prioridade do leitor:** trabalho exploratório e mídia usam a capacidade que sobra depois da proteção do feed presente e sua reposição.
- **Sem número mágico:** capacidade medida por consumo/latência/recursos, sem assumir que 16 cards, 32 candidatos ou 256 probes bastam como política. Limites per-call seguem legais para segurança/memória.
- **Pendente SAI do caminho crítico:** uma história sem link válido ou mídia esperada sai da fila de publicação atual, não reserva posição, não trava cursor nem retarda outras prontas. Mantém identidade recuperável fora da fila e retorna à seleção quando houver apresentação legítima (PD-5/PD-9/INV-17/F06).
- **Ações de rede e aquisição não alteram o prefixo admitido** (INV-08/09, B04). O avanço do leitor autoriza a apresentação, não a aquisição de dados em si.
- **Economia sob pressão real:** rede, disco, energia, memória, térmica e restrições do iOS influenciam ritmo e retenção de maneira mensurada, sem polling incessante ou segundo scheduler.

## Provas prioritárias

1. **B03 integral**, mantendo corpus, trace e critérios congelados; medir a reserva ao longo do tempo, aquisição e contato efetivo de novas fontes.
2. **Runway saudável + fontes ainda não visitadas:** demonstrar contato progressivo sem perturbar a leitura, em vez de simplesmente repetir as primeiras selecionadas.
3. **Consumo mais veloz que reposição:** medir e recuperar runway conforme custo real de aquisição, sem depender de um número de cards assumido como suficiente.
4. **Primeiro candidato nunca prontifica:** avançar pelos seguintes sem travar fila ou cursor; depois, quando se recupera, o candidato compete por espaço futuro (F06).
5. **Carga real e pressão do sistema:** comparar recursos disponíveis/pressionados e observar se o orçamento operacional se adapta, mantendo preservação visual B04.

## Próxima decisão

Consolidar F05 como experiência orientada por **cobertura de consumo + exploração progressiva oportunista**, sem inventar dois pipelines concorrentes. Em seguida, realizar avaliação ponta a ponta antes de propor correção de código. As melhorias devem respeitar os donos existentes.

**Referências:** [mapa das frentes](../product/PRODUCT_AUDIT_10_FRONTS.md), [benchmark B03](../product/DISCOVERY_ACCEPTANCE_BENCHMARK.md), [decisão PD-8](../product/PRODUCT_DECISIONS_2026-10-09.md), [documento de runway](../architecture/CONTINUOUS_FEED_RUNWAY_DESIGN.md), [F06](../product/F06_SACRED_FEED_CARD_READINESS_PRD.md).
