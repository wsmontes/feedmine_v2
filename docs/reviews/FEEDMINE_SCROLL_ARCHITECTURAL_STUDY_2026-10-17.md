# FeedMine V2 — Estudo arquitetural do engasgo na rolagem

**Revisor externo · 17/out/2026, America/Vancouver · baseline `main@5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`.** Análise estática das fronteiras UI/Runtime, confronto com relatório físico da build 48 e com correção candidata `fix/deferral-invalidates-list@10bc0bd72cfd`. Não executei código, Instruments, trace ou testes; separo mecanismos observados de causa ainda não isolada. Este é **um estudo de comportamento e arquitetura**, não uma meta de economizar 1–2 ms.

## 1. Veredito e definição do problema

**A hipótese do dono é tecnicamente correta em essência:** scroll deve **observar** o leitor e apresentar dados locais prontos. Aquisição, ordenação editorial, admissão/publicação, decodificação de mídia, persistência e reposição de runway não devem formar dependência síncrona do gesto ou do próximo frame. O produto deve tolerar esses trabalhos demorando sem interromper movimento e sem modificar o prefixo já apresentado.

**Nuance necessária:** captura de posição, decisão de identidade visível, layout/hit testing e desenho **inevitavelmente** usam CPU no caminho da UI. O requisito não é literalmente zero instruções, mas *trabalho mínimo, local, previsível, sem I/O/espera e independente da velocidade dos produtores*. “Flags” devem carregar uma evidência pequena e identificada (contexto, edição/proveniência, âncora, direção, fase/repouso, geração), e não apenas booleans frágeis.

**Estado real:** FeedMine já tem várias peças corretas (`LazyVStack`, `FeedVisualMotion` não observável, snapshots, sessão/driver como owners, janela segurada durante gesto). **A fronteira não está completamente isolada**: ainda há consultas/comparações de janela, construção de provas e tarefas no `MainActor` disparadas por callbacks de rolagem; as conclusões acionam instalação de estado e, em certas mudanças de janela, consulta síncrona a SQLite no mesmo ator da UI.

Não confundir **defeito de desenho potencial identificado por inspeção** com **causa raiz medida**. A cadeia é suficientemente acoplada para merecer correção dirigida; para dizer *qual* etapa produz os quadros atrasados é necessário trace sincronizado com call stacks.

## 2. O contraste decisivo: medir um sintoma não isola sua causa

A [jornada física de 16/out, build 48](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-16-rodada-entrega-48.md#L77-L108) mediu no mesmo app/aparelho:

| Condição | Fora do orçamento | Fatos do trace |
|---|---:|---|
| Ocioso, 89 s | 0,13% | 6 intervalos severos; nenhum `advance` |
| Scroll, 26 s | 12,7% | 90 severos, 41 `advance`; 54 severos nos 6 segundos de swipe, 11–13 instalações/s nesses momentos |

A proporção entre repouso/gesto é ~97×. Isso **localiza o sintoma no exercício da jornada** e correlaciona observação/admissão com hitches, mas **não prova** que cada instalação causou um hitch. O próprio relatório refutou uma intervenção plausível: pular republicação redundante piorou o resultado dentro da variabilidade observada; pior intervalo de uma corrida isolada foi instável. Não ressuscitar essa “otimização” como solução sem nova prova.

A branch [`fix/deferral-invalidates-list@10bc0bd72cfd`](https://github.com/wsmontes/feedmine_v2/commit/10bc0bd72cfdfcdb2cfe89e2eed7b4a520183f27) atacou invalidações enquanto uma janela estava emprestada ao gesto. O autor relata **3,02% → 1,51%** (medianas de três corridas de 14 arrastadas) para quadros acima de 1,5× orçamento, no iPhone 14 Plus em Release. É evidência promissora de redução de custo **reportada**, mas não é o mesmo protocolo/métrica da comparação ocioso/scroll anterior, não certifica o desaparecimento dos engasgos e não demonstra isolamento total.

As orientações do PO em [`2026-10-17-passive-scroll-observation-direction.md`](https://github.com/wsmontes/feedmine_v2/blob/main/docs/reviews/2026-10-17-passive-scroll-observation-direction.md) já exigem essa separação; este estudo adiciona o percurso de chamadas e decisões de investigação.

## 3. Percurso real — do dedo ao armazenamento e de volta

```text
UIScrollView / SwiftUI layout (precisa estar responsivo)
    |
    +-- FeedScreen.onGeometryChange / NativeFeedViewport.onScroll*
            [@MainActor; posição, validação, comparação, evento]
    |
    +-- FeedScreenStore.submitViewport
            [@MainActor; evidence(for:) + callback]
    |
    +-- FeedAssociation.store.onRenderedViewport
            [@MainActor; Task { await self.viewport(...) }]
    |
    +-- FeedAssociation.viewport
            [@MainActor; checagem, exposure, trace, handoff]
    |
    +-- FeedPresentationHandoff -> FeedRunwayDriver -> FeedSession actor
            [atores existentes; markSeen, band/decoding, janela,
             drive de runway, possíveis publicação e aquisição]
    |
    +-- onCommitted / retorno -> MainActor.run -> FeedAssociation.install
            [FeedScreenStore.install, estado observado/array equality;
             em troca de janela: consulta síncrona de bookmarks SQLite]
    |
    +-- SwiftUI recalcula dependências/layout necessários para apresentar
```

**O gesto em si não espera conscientemente uma chamada de rede.** Mas o app cria oportunidades, traz processamento e resultados de volta para a mesma thread/ator que sustenta a UI. A contenda pode ser por tarefas no `MainActor`, diffs/layout, I/O síncrono ou combinação; não presumir que `await` significa automaticamente execução fora da UI.

### Evidências concretas, com limites

| Caminho | O que o código realmente faz | Categoria |
|---|---|---|
| [`FeedScreen.swift:99–150`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineUI/FeedScreen.swift#L99-L150) | No `onGeometryChange` de célula: `renderedItems.contains(where:)`, leituras de `store.state.presentation`, captura, `submitViewport` e posição apresentada. A verificação de presença percorre janela. | **Fato**, custo quantitativo não medido |
| [`FeedNativeViewport.swift:21–27, 52–57, 119–159`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineUI/FeedNativeViewport.swift#L21-L27) | `matchesScope` compara `window` e dados de `state`; setter de scroll position faz `contains(where:)`; `onScrollGeometryChange` chama `capture.observe` e encaminha fato. | **Fato**; custo por evento precisa ser medido |
| [`FeedInteractionPresentation.swift:20–56`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineUI/FeedInteractionPresentation.swift#L20-L56) | Hold/release compara snapshots e mapeia IDs da janela; mutação `deferredWindows` tocava estado observado, mitigada na branch candidata. | **Fato**; já existe solução parcial |
| [`FeedPresentationSnapshot.swift:115–139`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineRuntime/FeedPresentationSnapshot.swift#L115-L139) | Para cada evidência renderizada verifica âncora percorrendo `window.items` e **materializa `admittedIDs: window.items.map(\.id)`**; prova `Sendable`, mas produzida no callback da UI. | **Fato**; alocação proporcional à janela, em vez de pequeno sinal |
| [`FeedScreenStore.swift:136–178`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineUI/FeedScreenStore.swift#L136-L178) | `@MainActor`; `submitViewport` gera evidência e invoca callback síncrono; `install` compara arrays renderizados em cada instalação, embora só reatribua se diferentes. | **Fato**; custo de comparação variável |
| [`AppComposition.swift:1713–1718,1788–1806`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L1788-L1806) | `FeedAssociation` é `@MainActor`; cada callback cria `Task { await self.viewport(...) }`. O `Task` **herda isolamento do contexto**; não é ordem automática para um executor independente. | **Fato estrutural**; enfileiramento/tempo efetivo ainda não medidos |
| [`AppComposition.swift:2880–2930`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L2880-L2930) | `viewport` executa checagens/exposição/trace no `MainActor`, `await` de driver e instalação de recibos no `MainActor`; resultados tardios têm fence de proveniência. | **Fato**; fence é valiosa, não removê-la |
| [`FeedRunwayDriver.swift:145–203`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineComposition/FeedRunwayDriver.swift#L145-L203) | Cada oportunidade aceita percorre sessão, observação runway, possível admissão forward/back e drive de produção. O driver preserva causal ownership, não é `loadMore` direto de SwiftUI. | **Fato**; distinguir eventos indispensáveis dos substituíveis |
| [`FeedSession.swift:135–174`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineRuntime/FeedSession.swift#L135-L174) | Actor da sessão faz `markSeen` no armazenamento, calcula residência/decodificação e re-projeção ao receber observação. **Não é o MainActor**, mas pode atrasar o recibo e amplificar instalações concorrentes; não é execução direta no callback. | **Fato** com localização de executor esclarecida |
| [`AppComposition.swift:2623–2636`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L2623-L2636) | `FeedAssociation.install` é isolado no `MainActor`; em mudança de conjunto de IDs executa `PublicationStore(database: database).bookmarkedCardIDs()` **sincronamente**. | **Fato e violação concreta da fronteira pretendida:** I/O SQLite pode disputar a UI. Não dizer que ocorreu em todo frame |

**Importante:** `FeedVisualMotion` já foi retirado do estado observável (movimento por frame não deveria invalidar `FeedScreen`). A nova branch corrige adicionalmente leituras observadas e mutação de contador de deferral. **Não reintroduzir outro sistema de motion** nem reabrir esses fatos como se nada tivesse sido feito.

## 4. Modelo arquitetural desejado (sem outro runtime)

```text
                 UI / MainActor — CAMINHO CRÍTICO
gesto nativo -> layout/desenho do snapshot local imutável
              -> captura mínima de posição + identidade + fase
              -> entrega de fato pequeno; callback retorna
                       | (não espera trabalho do runtime)
                       v
                 DONOS EXISTENTES, FORA DA UI
FeedSession / FeedRunwayDriver processam observações com escopo,
descartam observações substituídas quando semanticamente permitido,
atualizam cursor/exposure, runway, aquisição, seleção, mídia, publicação,
sempre sem tocar na janela que está sob o dedo
                       |
                  RECIBO COERENTE
                       v
                 UI / MainActor
          instala somente nova apresentação material,
          em fronteira segura (por exemplo, fim de hold)
          e sem query síncrona ou cálculo editorial
```

O projeto **já possui** atores e canal causal (`FeedSession`, `FeedRunwayDriver`, `FeedPresentationHandoff`), tokens/provenance, buffers de retenção visual e banco local. Preferir **repassar sinais curtos e deslocar operações para esses donos** a adicionar fila, temporizador, cache ou um novo ator genérico.

Não confundir “trabalho em background” com correr tudo em `Task.detached`: isolamento explícito e `Sendable` são necessários; criar uma tarefa destacada **para cada frame** seria outra origem de custo, falta de ordem e starvation. Coalescer *apenas* movimento intermediário substituível no dono já existente, preservando fronteiras de fase/repouso, mudança de contexto/edição, posição a persistir e oportunidades de publicação. Não perder direção, âncora e fences.

A UI pode aplicar uma janela nova em fronteira semanticamente segura. Isso não significa atrasar indefinidamente a admissão: alimentar a reserva local proativamente e deixar o gesto revelar o que já está pronto. Evitar trocar janelas dentro de gesto ativo ou perder resposta ao fim do hold. Correções de offset durante gesto não são alternativa aceitável.

## 5. Ordem de diagnóstico e intervenção mínima

### Etapa A — provar a dependência, não ajustar porcentagens

Instrumentar a **mesma build Release no iPhone** com Instruments (SwiftUI Update Groups/Long View Body, Hitches, Time Profiler, Hangs e, quando útil, Swift Concurrency). Correlacionar no mesmo relógio:

1. begin/end do gesto + offset/âncora, mudanças visíveis da lista;
2. callback de geometria: duração e frequência;
3. `evidence(for:)` e criação de `Task` no MainActor (fila de tarefas pendentes);
4. entrada/saída de `FeedAssociation.viewport`;
5. `FeedSession.submitViewport`/SQLite/decodificação/admissão;
6. `FeedAssociation.install`/leitura síncrona de bookmarks/SwiftUI update/layout;
7. publicação/aquisição e seus recibos.

Reutilizar o trace/signpost já existente, com pontos de começo/fim de baixa sobrecarga. Não ativar trace de milhões de linhas e depois atribuir o custo ao produto. Coletar **stacks dos quadros severos**; presença temporal não é causa. Relatar travamentos perceptíveis, durações contínuas e piores agrupamentos, não só proporção média de atrasos.

### Etapa B — ensaio discriminante em quatro condições

No mesmo aparelho, corpus de oferta suficiente e mesma sequência reprodutível de gestos:

- **A:** scroll de edição local já publicada com aquisição/seleção desabilitadas por instrumento de teste, sem alterar UI;
- **B:** mesma edição, trabalho real de aquisição/seleção/publicação concorrendo, UI idêntica;
- **C:** manter observador enviando sinais, mas desligar *apenas o consumo do driver* em instrumentação, sem desligar captura/scroll; marcar o que deixa de ser atualizado;
- **D:** mesmo trabalho de C recolocado através dos owners existentes com processamento fora da UI, sem mudança de produto visível.

Interpretação: se A engasga igual, olhar primariamente render/layout/capture; se B piora com stacks do instalador/consulta, tratar concorrência/retornos ao MainActor; se C remove engasgos, isolar o hop consumidor; se D mantém continuidade sem hitches, validar arquitetura. **Esses são experimentos propostos, não resultados obtidos.**

### Etapa C — corrigir no owner, incrementalmente

1. **No hot path visual** (`FeedScreen`, `NativeFeedViewport`, `FeedScreenStore`): não percorrer `window.items` ou criar arrays inteiros por observação; usar identidade/proveniência/snapshot já disponíveis para atestar pertinência. Mudar somente após provar que mantém proteção contra callbacks obsoletos.
2. **Separar eventos de posição dos efeitos** no handoff já existente. A apresentação recebe apenas valores prontos e mudanças materiais; movimento não deve implicar instalação ampla. Preservar event ordering/idle/fences; não inventar `loadMore` por scroll.
3. **Remover a consulta SQLite síncrona do `MainActor` durante `install`**, preparando bookmarks com a janela no owner de persistência/composição fora da UI e instalando um resultado coeso. Não criar um segundo estado proprietário da biblioteca.
4. **Limitar reinstalações com prova material**, sem supor que ignorar snapshots equivalentes é sempre correto. O ensaio anterior de “supressão de instalação redundante” foi refutado por medição; não repetí-lo como cosmética.
5. Em `FeedSession`/driver, analisar se o trabalho `markSeen`, decodificação e seleção de janela pode ficar fora do ciclo de observações substituíveis; **não** atrasar confirmação durável necessária nem permitir card sem pixels prontos. Uma resposta mais rápida não pode violar o prefixo imutável.

### Etapa D — validação de produto

**Obrigatório, após integração numa árvore única:**
- 14+ arrastadas e gesto prolongado, com/sem supply concorrente; sem travas visíveis e sem dependência do produtor;
- gesto não gera rede, decode, query ou publicação no caminho crítico do próximo frame; a cadeia assíncrona pode ser disparada por observação, mas não bloquear UI;
- avanço contínuo com runway e **B03 integral (30 minutos)** em corpus suficiente, sem fim artificial ou pausa ≥1 s por falta de runway;
- **B04**: trabalho concluído durante gesto não move conteúdo/âncora nem cambia geometria;
- A→B→A, app em background/foreground, reinício e retomada offline com ponto correto; não perder fatos por coalescência;
- mídia render-ready e preservação da ocorrência histórica (sem text-only automático por falha temporária de decode);
- **B06 físico integral** com CPU, memória, energia/térmica, frame hitches e tempo de scroll, sem inventar PASS antes de prova.

**Critério de saída:** uma jornada que não engasga perceptivelmente enquanto os produtores estão ocupados **e** um trace demonstrando que callbacks e updates que sustentam o gesto não executam I/O ou trabalho do runtime; o produto continua entregando cards e restauração. Percentuais de frames atrasados são evidência auxiliar, não substitutos desse contrato. Não definir limite arbitrário novo em lugar da régua congelada.

## 6. O que não fazer

- Não celebrar queda de 3,02%→1,51% como “fluidez resolvida” se ainda existem engasgos visíveis.
- Não esconder stalls com animação, placeholder, reconversão de mídia/identidade, rebalanceamento da janela durante o gesto ou um timer de atraso fixo.
- Não declarar `Task { }` ou `await` sinônimo de execução off-main. Ver [Swift Concurrency](https://docs.swift.org/latest/documentation/the-swift-programming-language/concurrency/) e [Apple: Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).
- Não criar produtor por frame, segunda fila, outro `ScrollCoordinator` ou cache para armazenar observações sem necessidade demonstrada.
- Não otimizar a comparação mais visível sem stack/ensaio: a ablação antiga piorou.
- Não abandonar observação da posição real, durabilidade e proteção de edição para reduzir trabalho: uma UX que perde o ponto de leitura não é correção.

## 7. Próxima ordem sugerida ao OMP

1. Revisar o diagnóstico e a branch `fix/deferral-invalidates-list`, reproduzir o ganho após integrá-la isoladamente num checkout limpo (com logs/provenance de build).
2. Rodar Etapas A/B para localizar **qual trecho** mantém custo dependente do scroll. Não abrir refactor amplo sem prova.
3. Eliminar primeiro o I/O sincrônico no `install` do MainActor e os scans/arrays por callback **se o trace demonstrar custo**, mantendo owner/fence.
4. Demonstrar que a UI consome snapshot local enquanto runtime trabalha independentemente e que B03/B04/B05 seguem válidos; executar B06 no aparelho.
5. Registrar árvore/SHAs, traces, resultados brutos, erros remanescentes e se o engasgo ainda é perceptível. **Sem PASS inventado, sem mudança em `bench/`.**

**Relação com o inventário:** [Intenções versus entregas](FEEDMINE_INTENTIONS_VS_DELIVERIES_2026-10-17.md). Este estudo é o diagnóstico dedicado da frente **scroll/fluidez**, não um substituto da prioridade do feed contínuo.
