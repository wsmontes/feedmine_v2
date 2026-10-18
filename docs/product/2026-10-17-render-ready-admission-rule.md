# Regra absoluta do dono: prontidão antes da admissão ao feed

Data: 2026-10-17 (America/Vancouver).
Status: diretriz explícita do dono do produto, registrada a seu pedido. Este commit trata exclusivamente desta regra; não altera implementação nem certifica seu cumprimento.

## Regra

**O feed é sagrado. Um card só pode entrar na apresentação do feed depois de sua preparação estar concluída. Não existe card admitido aguardando trabalho para se tornar a apresentação que deveria ter sido entregue.**

Para um card cuja apresentação inclui imagem, isso exige que a mídia esteja resolvida, disponível localmente, decodificada e pronta para desenho antes da admissão. Arquivo baixado, chave de cache, dimensões ou espaço de imagem reservado não equivalem a prontidão visual.

A view consome a apresentação pronta. Mostrar o card não pode iniciar ou aguardar download, resolução, decodificação ou enriquecimento necessário para completar essa apresentação. Não pode haver placeholder temporário que depois receba a imagem na mesma ocorrência publicada. Preservar a geometria enquanto a imagem chega não satisfaz esta regra.

**Não é uma questão de timing.** Preparar rapidamente depois da admissão, terminar antes de o leitor perceber ou ganhar uma corrida contra a rolagem não são implementações aceitáveis. A prontidão é uma precondição de admissão.

## Imutabilidade e preparação futura

- Trabalho de aquisição e preparação pode continuar para conteúdo futuro, fora da apresentação já admitida.
- Mídia tardia não modifica a ocorrência já publicada. Pode beneficiar uma composição futura legitimamente autorizada pelas regras de publicação existentes; não cria nova ocorrência ou edição automaticamente.
- Card de texto pode ser uma apresentação final legítima pelas regras editoriais vigentes. Não serve de disfarce para imagem pendente nem autoriza rebaixamento automático por timeout ou número de tentativas. INV-17 permanece vigente.
- Um candidato ainda sem apresentação válida fica fora da fila de publicação corrente e não bloqueia os demais candidatos prontos, conforme INV-17.
- Gestão de memória não pode transformar um card apresentado em uma apresentação incompleta. A reconstrução de recursos liberados deve estar concluída antes de qualquer readmissão à apresentação; recursos da apresentação efetivamente mantida na tela não podem ser retirados para depois serem repostos nela. Não se exige manter todo o histórico decodificado em RAM; exige-se preservar a fronteira entre preparo e apresentação.

## Referência concreta da V1

Inspeção realizada em `wsmontes/feedmine-dev` nesta sessão:

- `feedmine/Models/PreparedFeedCard.swift`: distingue `ResolvedCardAsset` (arquivo/decisão no disco) de `RenderReadyMedia` (imagem decodificada) e `PreparedFeedCard` (valor entregue à UI).
- `feedmine/Services/CardPreparationCoordinator.swift`: `prepareItem` resolve o asset, chama `decodeToRenderReady` e só então `storeRenderReady`. `peekRenderReadyPrefix` entrega apenas cards existentes em `renderReadyByID`; `commitPublished` valida o prefixo/contexto antes de consumi-lo.
- No mesmo coordenador, `upgradeDeferredToHero` prepara mídia para composição futura e declara a apresentação publicada imutável. A chegada tardia não deve alterar o card publicado.

Esses mecanismos são referência de comportamento e de fronteira, não autorização para copiar runtime, timers, cotas, políticas de fallback ou filas legadas para a V2. A V2 deve preservar a garantia usando seus donos existentes.

## Verificação exigida na V2

Demonstrar, no caminho real de apresentação:

1. Card com imagem pendente ou sem pixels preparados não atravessa a fronteira de admissão à UI como se estivesse pronto.
2. O valor com imagem entregue à view já contém a imagem pronta para desenho; a view não completa sua preparação.
3. Uma imagem que termina depois não modifica a mídia/layout da ocorrência já publicada.
4. Memória, ida e volta na rolagem e restauração não expõem card incompleto aguardando reconstrução.
5. O teste discriminante reprova quando se permite admitir antes de terminar o preparo; um teste que apenas verifica geometria estável ou imagem eventualmente presente é insuficiente.

Não mudar benchmarks congelados nem enfraquecer contratos para obter aprovação. Este documento registra o requisito; não afirma que os caminhos atuais da V2 já o cumpram ou que uma violação visual específica tenha sido reproduzida nesta sessão.

## Implementação na V2 (2026-10-17, branch `fix/render-ready-admission`)

A regra é cumprida por **exclusão, nunca por conversão**. Nenhum card com imagem publicada vira
`.textOnly` sob a mesma `PublicationCardID`; o contrato publicado permanece o que foi declarado.

- **Preparação (`MediaPrefetcher`/`MediaReadiness`):** uma revisão cujo feed declara imagem de card e cuja
  mídia não ficou utilizável fica *settled* sem apresentação (`presentation(for:) == nil`). Só ausência de
  mídia declarada (card de texto por desenho) produz `.textOnly`. A candidata sai da fila de publicação
  corrente e permanece em supply (INV-17).
- **Publicação (`PublicationPreparation.plan`):** uma apresentação `.image` cujo `MediaPreparationResult`
  não é `.usable` não gera rascunho; candidato, rascunho e `cardIDs` são reduzidos juntos, de modo que os
  demais candidatos prontos publicam na mesma oportunidade. Um card assim nunca recebe ocorrência.
- **Admissão (`FeedSession.admitted`/`PresentationCard.isRenderReady`):** uma carda com layout de imagem
  e `image == nil` não atravessa a fronteira. Quando a âncora publicada é uma delas, a janela passa a
  apontar para a carda admitida mais próxima, com o mesmo placement; as demais seguem normalmente.
- **Readmissão (`FeedSession.boundedResidency`):** se a reconstrução de uma carda que retorna à banda
  falha, ela é removida daquela readmissão — não é desenhada como texto nem como slot vazio.

Teste discriminante: `RenderReadyAdmissionTests.testAnImageCardWhoseMediaCannotBeDecodedIsNotAdmitted`;
readmissão: `testACardReturningToThePixelBandIsReconstructedBeforeItIsDrawn`; restauração:
`FeedSessionWarmRestoreTests.testWarmRestoreWithoutDecoderAdmitsNoImageCard`; preparação:
`MediaPrefetcherTests.testAllCandidatesFailingHasNoPresentationAndIsNotRetried`.
