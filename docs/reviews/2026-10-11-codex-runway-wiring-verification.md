# Verificação da integração do runway — 2026-10-11

Trabalho na árvore compartilhada, sem commit e sem editar `bench/`. A bateria completa e o novo benchmark ficam para o responsável pela medição após a liberação da árvore. Esta verificação não altera os vereditos das builds anteriores.

## (1) Reconstrução pelos três caminhos

`selectContext`, `activateSavedPreset` e `replaceSession` têm testes que recebem uma resposta enquanto o construtor aguarda a leitura real do catálogo. O construtor resolve um perfil antes de suspender; ao terminar, o pedido de reconstrução pendente deve reler a preferência e instalar a associação correspondente. Os testes conferem as fontes contra o catálogo, não apenas a preferência persistida.

As transições de contexto e preset não drenavam `pendingRebuild`; agora drenam. A prova de `replaceSession` também revelou `database is locked` na persistência: trabalho assíncrono da associação antiga e preferências escreviam por pools diferentes. O host passa seu `RuntimeDatabase` às associações, compartilhando um escritor e evitando uma migração/abertura por reconstrução.

T11: a travessia retinha snapshots com o transporte antigo. O teste isolado reproduziu a exceção Objective-C de sessão invalidada. Uma prova menor mostrou algo anterior ao crash: uma associação nova configurada offline adquiria dados pelo transporte antigo. Os conectores de páginas retidas agora recebem o transporte da associação atual; cursor, registros e cercas de geração permanecem. T11 passou depois da correção.

## (3) Orçamento de mídia por oportunidade

`MediaPreparationOpportunity` captura um deadline. Uma fábrica consulta a tolerância derivada uma vez; todas as janelas do bootstrap, callbacks de aquisição e slices do dreno ativo compartilham esse deadline. Uma nova oportunidade recebe novo orçamento. O host conecta a mesma fábrica ao bootstrap, driver e manutenção da cauda.

A prontidão continua opcional: esgotar a espera não decide text-only e não reserva publicação para um candidato pendente. Os testes existentes de suspensão permanecem na bateria selecionada. Os novos testes conferem múltiplas janelas/slices e renovação apenas na próxima oportunidade. Um teste de desativação durante a leitura do orçamento falhou antes da cerca adicional de escopo e passou depois: uma oportunidade revogada não pode avançar o catálogo ao retomar.

## (2) Política incluindo descoberta

A definição e as chamadas já estavam presentes na árvore inspecionada: bootstrap, slice ativo e consulta dos próximos candidatos. A verificação cobre aquisição/publicação além de 120 fontes, fonte descoberta revogada, identidade da apresentação, pesos curados e todas as versões de comportamento. Nenhuma segunda implementação foi criada.

## U4 e U11

O coletor de prova reconhecia apenas `ForEach<[PresentationCard]>`. As linhas editoriais fizeram a view usar `ForEach` de pares `(offset, element)`, com a mesma identidade publicada. O coletor foi atualizado para ler essa forma. As exigências de IDs, títulos e ordem permanecem; ambos passaram. Isso era incompatibilidade do instrumento com a forma nova da view, não falta de apresentação no store.

## Comandos e evidências

- `swift test --filter 'ColdFeedBootstrapTests|FeedRunwayDriverTests|ReaderDiscoveryPoolTests|FeedScreenRenderingTests'`: **107 testes, zero falhas**. [Log](evidence/2026-10-11-codex-runway/library.log).
- `xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -destination 'platform=iOS Simulator,id=8871DCF5-0C06-4C7C-88D2-7B3DC36E8284' -only-testing:FeedMineAppTests/CompositionTests -only-testing:FeedMineAppTests/MediaWaitDerivationTests`: **41 testes, zero falhas**. [Log](evidence/2026-10-11-codex-runway/app-composition.log).
- Após a cerca de escopo e a revisão final, o app foi recompilado e os três caminhos, T11 e a derivação de espera foram repetidos: **7 testes, zero falhas**. [Log final](evidence/2026-10-11-codex-runway/app-final.log).
- [Transporte antes da correção](evidence/2026-10-11-codex-runway/transport-red.log), [diagnóstico de reconstrução](evidence/2026-10-11-codex-runway/reconstruction-diagnostic.log) e [desativação antes da cerca](evidence/2026-10-11-codex-runway/budget-scope-red.log).

A prova de fluidez/expansão ao longo de trinta minutos ainda depende de nova corrida com esta build. Estes testes não substituem B03 nem B06 em aparelho físico.
