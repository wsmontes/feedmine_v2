# FeedMine V2 — Estudo arquitetural do engasgo na rolagem

**Revisor externo · 17/out/2026, America/Vancouver · baseline `main@5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`.** Análise estática das fronteiras UI/Runtime, confronto com relatório físico da build 48 e com correção candidata `fix/deferral-invalidates-list@10bc0bd72cfd`. Não executei código, Instruments, trace ou testes; separo mecanismos observados de causa ainda não isolada. Este é **um estudo de comportamento e arquitetura**, não uma meta de economizar 1–2 ms.

> **Esclarecimento posterior do dono (mesma data; substitui qualquer leitura de “medir primeiro” deste estudo):** a fluidez não é uma meta de micro-otimização. O travamento é tratado como erro de fronteira UI/runtime a remover por construção. **Implementação arquitetural primeiro; medição apenas para comprovar e para investigar defeitos que persistirem.** Ver contratos e ordem revisados no §5.

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

## 5. Direção de correção: separar responsabilidades **antes** de otimizar

**Esclarecimento do dono em 17/out/2026:** o defeito percebido não é uma degradação marginal de FPS a ser compensada com tuning. É um **engasgo incompatível com um leitor simples**. A meta é eliminar o acoplamento entre gesto e produção de conteúdo. O iPhone tem capacidade para renderizar a porção visível de texto/imagens já preparados; não aceitar a dificuldade atual como natural nem iniciar outra caça longa a percentuais antes de remover violações evidentes de fronteira.

Isso **não significa** que a thread principal execute zero instruções (o sistema precisa calcular layout e desenhar). Significa que a resposta ao gesto **não aguarda** aquisição, SQLite, decodificação, seleção, publicação, recomposição de janela ou comunicação síncrona com um ator produtor. A UI publica um sinal pequeno, de custo previsível, e segue. O trabalho é dos consumidores da observação, com estado/cursores próprios, sem depender do frame seguinte para concluir. O runway mantém trabalho adiantado **proativamente**, sem depender de o usuário rolar para começar.

### Contratos de implementação a impor no owner existente

**C1 — UI pura consumidora.** Desenhar `PresentationCard` já preparado e apresentado localmente; o corpo de view e callbacks de geometria/scroll podem apenas ler a geometria nativa necessária, atualizar um fato visual pequeno e encaminhar um evento. São proibidos nesse caminho: I/O, trabalho editorial, construção de arrays/sets de toda a janela por evento, comparações estruturais amplas repetidas, decode e instalação de uma nova apresentação como efeito obrigatório de cada avanço.

**C2 — Observação não é execução.** `viewport`, `anchor`, `phase` e `atRest` são entradas **assíncronas e substituíveis quando apropriado**. O produtor não precisa responder para permitir o scroll continuar. O reconhecimento do fato pelo runtime não é uma condição para o próximo frame. Evitar uma `Task` por frame; transferir e coalescer pelo owner já existente se isso for necessário. Não descartar eventos semanticamente importantes (repouso durável, contexto/edição, posição relevante, conclusão de publicação). Manter fences de proveniência.

**C3 — Runtime com autonomia temporal.** `FeedSession`/`FeedRunwayDriver` observam sinais com suas próprias posições e processam registro de leitura, runway, consulta local, aquisição e seleção **fora do MainActor** naquilo que não é UI. O runtime prepara a apresentação futura e mantém a capacidade adaptativa de avanço independentemente da frequência de observações; o sinal do scroll reprioriza, não comanda síncronamente o trabalho.

**C4 — Publicação concluída, entrega segura.** O valor novo pode alcançar o host somente após preparação/admissão correta, por recibo de identidade e escopo. O recebimento no `MainActor` deve ser curto, apenas instalar valores materiais coesos; o processamento preparatório, consulta ao disco, seleção e decodificação ficam do outro lado. O gesto mantém sua janela emprestada, e a publicação não rearranja nem modifica o que foi visto/admitido.

**C5 — Preservação de continuidade.** A separação não pode eliminar: avanço sustentado, renda de runway, identidade/posição, reabertura offline, filtros A→B→A, mídia pronta, checkpoints e persistência real. Uma interface que ficou suave por deixar de produzir conteúdo falhou no produto.

### Violações/prioridades identificáveis pela leitura atual

1. **I/O síncrono em `MainActor` dentro de instalação:** [`AppComposition.swift:2623–2636`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L2623-L2636) consulta `PublicationStore.bookmarkedCardIDs()` quando janela/IDs mudam. **Eliminar esse acoplamento por contrato**, mesmo antes de provar que ele foi a pior stack. Preparar o resultado pelo dono da biblioteca/persistência e aplicar com a projeção material, sem segundo cache proprietário.
2. **Varreduras/arrays no callback visual:** [`FeedScreen.swift:113–140`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineUI/FeedScreen.swift#L113-L140), [`FeedNativeViewport.swift:52–57`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineUI/FeedNativeViewport.swift#L52-L57), [`FeedPresentationSnapshot.swift:133–139`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineRuntime/FeedPresentationSnapshot.swift#L133-L139) fazem `contains`, validações estruturais e `map(\.id)` por observação. Substituir por uma prova leve de identidade/proveniência existente, preservando os casos de callbacks obsoletos e edição errada. **Não criar índice/cache adicional por reflexo.**
3. **Reentrada em composição principal por cada observação:** [`AppComposition.swift:1788–1794`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L1788-L1794) cria `Task` no `FeedAssociation @MainActor` e chama [`viewport(...)` em :2880–2930](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/FeedMineApp/FeedMineApp/AppComposition.swift#L2880-L2930). Tornar o caminho quente do host apenas entrega curta de fatos; deslocar o processamento do lado consumidor, sem depender do `MainActor` para executar. `Task { }` não é, por si, off-main.
4. **Comparação/republicação estrutural acoplada a progresso do leitor:** [`FeedScreenStore.swift:136–178`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineUI/FeedScreenStore.swift#L136-L178), [`FeedInteractionPresentation.swift:20–56`](https://github.com/wsmontes/feedmine_v2/blob/5e4e21425f5e/Sources/FeedMineUI/FeedInteractionPresentation.swift#L20-L56). A branch `fix/deferral-invalidates-list` reduz invalidações de lista observadas; conservar seu benefício sem confundi-lo com desacoplamento completo. Não suprimir recibos necessários só para reduzir contadores.

### Plano de execução enxuto

1. Integrar ou reconciliar a correção candidata de invalidação da lista como **melhoria parcial**, protegendo a mesma janela/âncora durante gesto.
2. Corrigir os **três cruzamentos proibidos verificáveis** acima: I/O em instalação no MainActor, varreduras/arrays no hot path, e uso de `Task @MainActor` como canal para processar cada observação. Não redesenhar arquitetura inteira; reutilizar os donos existentes.
3. Verificar que o feed é conduzido pelo runtime proativo e entregue por fatos concluídos, não exige que cada gesto execute uma passagem de trabalho de produção. Manter os sinais relevantes, fences, posição durável e cancelamento de trabalho obsoleto.
4. **Depois das correções**, fazer provas curtas de isolamento e experiência. Se ainda houver engasgos, só então usar instrumentos para localizar o *trabalho residual*; não exigir uma bateria prévia de perfis para decidir o que o código já mostra como fronteira errada.

### Aceitação: sim/não, não torneio de FPS

- **Scroll com produção em andamento**: continua nativo e responsivo sem engasgos perceptíveis; produtor lento não bloqueia o desenho.
- **Scroll com runtime intencionalmente atrasado** (instrumento controlado): a janela publicada local continua navegável e mantém posição; preparar conteúdo novo pode atrasar, o gesto não.
- **Separação visível em código**: callbacks de gesto não fazem I/O, não fazem varreduras proporcionais ao tamanho do histórico, não obrigam consulta a outros atores e não instalam por frame; instalação no MainActor não consulta SQLite nem decodifica.
- **Correção de produto**: runway volta a abastecer quando há oportunidade (inclusive sem gesto), crescimento/admissão são coerentes, não há fim artificial, B03/B04/B05 e B06 físico continuam como gates oficiais, com PASS apenas quando executados e verificados.
- Métricas de hitches/CPU ajudam a **verificar** e a descobrir trabalho remanescente; jamais substituem esse contrato de separação. Não introduzir novo percentual arbitrário de aprovação.

## 6. O que não fazer

- Não celebrar queda de 3,02%→1,51% como “fluidez resolvida” se ainda existem engasgos visíveis.
- Não esconder stalls com animação, placeholder, reconversão de mídia/identidade, rebalanceamento da janela durante o gesto ou um timer de atraso fixo.
- Não declarar `Task { }` ou `await` sinônimo de execução off-main. Ver [Swift Concurrency](https://docs.swift.org/latest/documentation/the-swift-programming-language/concurrency/) e [Apple: Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness).
- Não criar produtor por frame, segunda fila, outro `ScrollCoordinator` ou cache para armazenar observações sem necessidade demonstrada.
- Não otimizar a comparação mais visível sem stack/ensaio: a ablação antiga piorou.
- Não abandonar observação da posição real, durabilidade e proteção de edição para reduzir trabalho: uma UX que perde o ponto de leitura não é correção.

## 7. Próxima ordem sugerida ao OMP

**Mandato:** tratar engasgo como **defeito de acoplamento**. Sem mais rodadas de tuning incremental como estratégia principal; aplicar os contratos C1–C5 em mudanças mínimas nos owners atuais, reconciliar o diff de fluidez já produzido, e validar que o gesto ficou independente dos produtores. Medir depois para confirmar a experiência e localizar eventual trabalho residual; não confundir percentual menor com correção concluída.

Sequência: (1) preservar o hold da janela durante gesto; (2) retirar I/O síncrono e processamento proporcional ao tamanho da janela do MainActor quente; (3) repassar observações mínimas para consumidores com independência temporal; (4) aplicar somente recibos prontos sem interferir no scroll; (5) verificar o aplicativo real e o B03/B04/B05/B06 sem alterar a régua.

**Relação com o inventário:** [Intenções versus entregas](FEEDMINE_INTENTIONS_VS_DELIVERIES_2026-10-17.md). Este estudo é o diagnóstico dedicado da frente **scroll/fluidez**, não um substituto da prioridade do feed contínuo.
