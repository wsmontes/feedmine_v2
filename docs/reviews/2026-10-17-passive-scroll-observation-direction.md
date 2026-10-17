# Rolagem: observação passiva e separação do processamento

Data: 2026-10-17 (America/Vancouver).
Base inspecionada: `6cbaa2fee3445e92957f9172d756cbbed4609108`.
Natureza: orientação de investigação e implementação, solicitada pelo dono. Não é correção de código, certificação de desempenho nem comprovação de causa raiz.

## Direção do dono

A rolagem deve ser observada de forma passiva. O gesto nativo e a preparação do próximo quadro não devem esperar processamento editorial, admissão de conteúdo, consultas de persistência ou comparações de apresentações completas.

A captura visual mínima pode e precisa executar no contexto da UI. Isso não autoriza transportar todo o processamento para o MainActor. `async` e `Task { ... }` não garantem execução fora desse ator.

## Suspeitas concretas no código da base

1. `Sources/FeedMineUI/FeedScreen.swift`: `@State private var capture` pertence à superfície que constrói a lista; `feedBody` lê `capture.interaction.heldItems(matching:)`. `Sources/FeedMineUI/FeedNativeViewport.swift`: o setter do binding de `scrollPosition` escreve `capture.positionID`. Investigar a granularidade efetiva da dependência desse estado e as invalidações da superfície decorrentes dessas escritas. É um caminho suspeito, não prova de que cada escrita reconstrói todos os cards.
2. `FeedScreen.swift`: cada callback de `onGeometryChange` faz `store.renderedItems.contains(where:)`, acessa a apresentação e encaminha observação/posição. `FeedNativeViewport.matchesScope` compara janelas por igualdade. São operações no caminho de callbacks visuais; identificar custo e frequência e evitar percorrer conteúdo completo para responder perguntas de escopo/identidade.
3. `Sources/FeedMineUI/FeedInteractionPresentation.swift`: `end(afterReading:store:)` e `noteIncoming(_:)` comparam snapshots por igualdade; `noteIncoming` também mapeia IDs das duas janelas. Conferir onde essas operações são chamadas e se a pergunta exige igualdade estrutural ou apenas uma identidade/revisão já existente. Não substituir igualdade por identidade sem preservar o contrato.
4. `Sources/FeedMineUI/FeedScreenStore.swift`: `submitViewport` constrói evidência e chama closures `@MainActor` diretamente. Seguir essas closures na composição e discriminar trabalho síncrono antes de qualquer suspensão, retomadas no ator e consultas realizadas no caminho. Ainda não foi concluída nesta análise a inspeção de toda a cadeia até persistência/admissão; não afirmar que toda ela bloqueia a UI.

A hipótese prioritária é acoplamento entre observação do movimento, estado lido pela lista e processamento de apresentação. Não atribuir a causa dominante a essa hipótese sem discriminar os custos. Esta orientação nasceu de leitura de código, não da interpretação dos números dos instrumentos.

## Fronteira desejada

- Callback visual: capturar um fato pequeno com identidade/geração, âncora visível, direção e os dados geométricos estritamente necessários. Encaminhar e retornar, sem esperar trabalho de produção.
- Processamento: um consumidor com trabalho limitado e política explícita de coalescência, usando os donos existentes. Posições intermediárias substituíveis podem ceder lugar à mais recente. Eventos de ciclo de vida, repouso, troca de contexto, publicação e fatos necessários ao cálculo de avanço não podem ser descartados indiscriminadamente.
- Não criar uma tarefa por callback nem fila sem limite. Não introduzir timer/debounce arbitrário para esconder custo. Preservar os contratos atuais de durabilidade e os fatos necessários ao runway.
- Trabalho que não depende da UI deve executar fora do MainActor por isolamento explícito apropriado. Registrar o isolamento efetivo, em vez de deduzi-lo de `async`.
- Retorno à UI: instalar somente mudanças materiais necessárias à apresentação. Uma atualização da posição observada não deve, por si só, republicar o conteúdo da lista. Conservar estabilidade de identidade, posição e geometria durante gesto e desaceleração.
- Preservar o comportamento nativo da rolagem. Nenhuma correção de offset durante gesto para compensar trabalho introduzido pelo observador.

Isto define uma fronteira de responsabilidade, não prescreve novo subsistema, mailbox ou segundo dono de sessão. Reutilizar mecanismos existentes quando suficientes.

## Trabalho esperado antes de escolher a correção

1. Mapear a cadeia concreta: callback visual → evidência → closure do store → composição → sessão/runway/persistência → instalação de apresentação. Para cada trecho, indicar arquivo, símbolo, ator/fila efetiva, suspensão e trabalho síncrono.
2. Separar três custos: captura geométrica; invalidação/reavaliação/layout da lista; processamento backend que ocupa o MainActor. Não tratar os três como uma única causa.
3. Verificar se `capture.positionID` e mudanças no hold invalidam o corpo da lista; se comparações estruturais percorrem janelas; e se o consumidor acumula trabalho enquanto chegam posições novas.
4. Propor o menor ajuste que retire o trabalho identificado do caminho visual, preservando os donos e a semântica de observação. Esta nota não autoriza reescrever a arquitetura nem alterar a régua congelada.

## Critérios de verificação

- O observador retorna sem aguardar aquisição, seleção, publicação ou persistência; captura mínima da UI continua correta.
- Movimento sem mudança de conteúdo não obriga a lista a reconstruir sua apresentação por causa do estado de posição. Medir invalidação efetiva, não assumir que reavaliação implica redesenho integral.
- Carga rápida não cria crescimento ilimitado de tarefas/eventos; o estado mais recente é processado sem perder fatos semânticos indispensáveis.
- Troca de edição/contexto rejeita resultados antigos; repouso, background e reabertura preservam o cursor correto e o conteúdo offline.
- Rolagem, desaceleração, acessibilidade e navegação programática mantêm posição e continuidade. Não obter desempenho abandonando esses casos.
- Demonstrar o efeito da mudança isoladamente com o mesmo cenário e configuração; separar Debug/telemetria de Release. Compilação e teste funcional verde não certificam fluidez.

## Limites desta revisão

Não foram executados builds, testes ou profiling nesta sessão. A nota não exclui outros custos de renderização, mídia ou preparação; apenas prioriza suspeitas presentes na implementação examinada. As medições históricas não são reutilizadas como prova causal. O resultado esperado é uma investigação discriminante e uma correção pequena sustentada pelo código e por execução, não apenas mover tudo para uma `Task`.
