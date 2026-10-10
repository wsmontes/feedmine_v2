# Feedmine limpo: UI do V1 e barreira de apresentação

## Direção dada pelo usuário

O V2 é o Feedmine com implementação sustentável. O frontend do V1 é a referência de produto e deve ser reaproveitado como código: aparência, cards, menus, filtros, navegação e interações. A simplificação deve acontecer nas responsabilidades e dependências, preservando a experiência.

Após a carga inicial, trabalho de aquisição e preparação não autoriza inserir cards na apresentação. O scroll libera cards já preparados. Cards apresentados conservam identidade, ordem, conteúdo editorial, mídia e geometria durante a leitura. Ações explícitas, como mudar filtros, iniciam outro contexto; não permitem callbacks do contexto anterior alterarem o atual.

## Evidências desta análise

Análise estática dos checkouts locais em 2026-10-09. V1: `../feedmine`; V2: este repositório, HEAD `372f4c5`. Não houve reprodução no iPhone, comparação visual por screenshots ou execução de testes nesta análise. Os estudos anteriores em `docs/v1-study` ajudam a localizar responsabilidades, mas contagens e linhas desses estudos não representam necessariamente o checkout atual.

### 1. A interface atual foi reconstruída, não portada

`Sources/FeedMineUI/FeedCardView.swift` usa outra composição visual, tipografia, espaçamentos e metadados. `FeedMineApp/FeedMineApp/FeedMineApp.swift` oferece uma navegação reduzida a Feed, Salvos, Fontes e busca local. Não equivale ao conjunto de menus, filtros e superfícies do V1.

`Sources/FeedMineUI/FeedDesignTokens.swift` declara explicitamente que o sistema visual do V1 não foi portado, admitindo apenas influência futura de suas paletas. Isso documenta uma decisão incompatível com a direção atual do produto.

Referências concretas para reaproveitamento:

| Origem no V1 (`feedmine/`) | Destino/responsabilidade no V2 |
| --- | --- |
| `Views/FeedItemCardView.swift`, `FeedItemView.swift` | Renderização e gestos dos cards, adaptados ao contrato de apresentação |
| `Views/FeedScreen.swift` | Composição visual, cabeçalho, menus, busca e comportamento do scroll, extraídos em componentes focados |
| `Views/FilterSheetView.swift`, `ContentFilterView.swift`, `TaxonomyChipBar.swift` | Controles e comportamento de seleção dos filtros |
| `Views/SourceManagementView.swift`, `CatalogExploreView.swift`, telas de taxonomia | Seleção e descoberta de fontes |
| `Views/BookmarkBoxesView.swift`, `BookmarkBoxPickerView.swift` | Organização e ações dos salvos |
| `Views/SettingsSheetView.swift`, `ArticleReaderView.swift`, `ToastView.swift` | Preferências, leitor e feedback |
| `Services/DesignTokens.swift`, valores visuais de `CircadianEngine`, assets | Fidelidade visual e preferências de aparência |

Portar a view inclui suas interações e os dados necessários. Remover controles por falta de suporte no V2 não conta como paridade. Registrar cada dependência e implementar seu contrato em uma camada adequada.

### 2. Produção ainda pode modificar a janela sem gesto

Em `Sources/FeedMineComposition/FeedRunwayDriver.swift`, `driveCausalEffects`, o caso `.runLocalSlice` chama `session.refreshCurrentPresentation()` quando há publicação. Esse método, em `Sources/FeedMineRuntime/FeedSession.swift`, consulta novamente o histórico com as capacidades da janela atual. Se havia menos cards disponíveis, novos cards podem passar a compor a janela sem nova autorização do scroll.

O mesmo driver é acionado por ativação e foreground, além de observações de viewport. Em `AppComposition.swift`, o resultado de foreground é instalado no store. Portanto, a imutabilidade de um card individual não garante estabilidade da coleção apresentada.

### 3. A janela deslizante exige prova de estabilidade física

`FeedSession.submitViewport` rematerializa uma janela em torno da nova âncora com capacidades para trás e para frente. `FeedScreen` renderiza diretamente `presentation.window.items`. Isso pode retirar itens do início e inserir outros ao final; o vínculo de posição por ID precisa preservar o deslocamento dentro do card, não apenas o ID central. O código lido não basta para certificar essa estabilidade em scroll nativo.

Não há evidência nesta análise de que esse mecanismo seja a causa de cada salto observado no aparelho. É um risco concreto a verificar antes de conservar a estratégia.

### 4. Estado de trabalho altera a área do scroll

`FeedScreen.swift` apresenta `FeedWorkBadge` em `safeAreaInset(edge: .bottom)`. O badge alterna entre conteúdo e `EmptyView` conforme o trabalho. Isso pode alterar a altura disponível e provocar nova geometria durante a leitura. Estado de abastecimento deve ter uma apresentação que não mude o espaço reservado para o feed.

### 5. Existem proteções úteis para conservar

O card do V1 recebe mídia local/resolvida e documenta que mídia tardia não deve aumentar a altura de um card publicado. O V2 também possui IDs de publicação, contratos imutáveis, proveniência de projeção, rejeição de resultados incompatíveis e reutilização de cards já projetados em `FeedSession.project`. Essas proteções devem continuar servindo à UI portada.

O backend é local ao aplicativo, conforme o README. Sua produção antecipada opera sob os recursos e o ciclo de vida do iOS; a autonomia de preparação deve ser comprovada em foreground, sem pressupor execução ilimitada em background.

## Abordagem recomendada

Copiar o frontend do V1 por superfície e adaptar suas entradas e ações ao V2. Extrair componentes da tela grande mantendo o código de layout e comportamento. O adaptador deve traduzir valores e intenções; não deve criar outro motor de aquisição, filtros ou publicação.

Copiar também o `FeedStore`/`FeedLoader` inteiro aceleraria a compilação inicial, mas carregaria os acoplamentos que motivaram o V2. Recriar a UI por aproximação já produziu divergência. O reaproveitamento direto das views com contratos menores atende à direção do usuário.

## Contrato proposto para a barreira

1. **Produção:** busca, normaliza, seleciona e resolve mídia antecipadamente. Atualiza somente a reserva enquanto há apresentação ativa.
2. **Reserva pronta:** ordem editorial definida; cards com estado visual final e mídia local preparada. Resultado tardio não reescreve cards apresentados.
3. **Apresentação:** libera uma carga inicial suficiente para leitura. Depois, estende o conteúdo apenas quando o avanço real do scroll demanda mais cards. Um callback de rede, preparação, retry ou foreground não constitui essa autorização.
4. **Scroll:** revela o prefixo pronto seguinte, preservando o conteúdo anterior e a posição física do leitor. Sem reserva suficiente, preserva a tela e espera abastecimento; não substitui o feed por loading.
5. **Navegação:** troca explícita de filtros/contextos restaura sua apresentação e posição ou prepara uma nova carga inicial. Retorno de background conserva a apresentação da sessão ativa; recuperação após encerramento restaura o checkpoint local.

“Apresentado” significa admitido na lista do scroll, não somente pixels momentaneamente visíveis. `LazyVStack.onAppear` e mudanças de geometria causadas pelo próprio layout não podem, sozinhos, autorizar essa admissão. A proteção deve cobrir também cards recém-admitidos abaixo da dobra.

Separar a reserva da lista admitida não exige outro histórico persistente nem uma fila concorrente com dono independente. Aproveitar a autoridade existente do histórico e tornar explícita a fronteira de admissão na sessão. A estratégia de memória para scroll longo precisa manter histórico acessível e compensar qualquer descarte visual com evidência de posição física estável.

Se a origem não oferece imagem válida, uma decisão final de card sem imagem/placeholder precisa acontecer antes da admissão. Não existe promoção visual tardia do mesmo card.

## Ordem de trabalho

1. Registrar comparação visual e funcional V1/V2: cards, header, menus, filtros, leitor, salvos e preferências. Cada superfície recebe origem, dependências e critério de paridade.
2. Criar reprodução controlada da barreira: deixar o leitor parado, concluir aquisição/preparação e verificar que a lista admitida, seus frames e a posição não mudam. Incluir badge e foreground.
3. Corrigir a ligação produção → apresentação antes de ampliar a UI. Provar reserva crescendo sem cards entrando no scroll; gesto posterior libera somente cards finalizados.
4. Portar cards, design e shell do V1 com ações reais. Depois portar filtros e demais superfícies, rastreando a paridade completa para que nada desapareça por simplificação.
5. Verificar em simulador e iPhone: leitura parada com rede ativa, imagens lentas, scroll contínuo em ambos os sentidos, filtros A→B→A, offline e background/foreground. Comparar screenshots ao V1 e medir posição antes/depois das transições.

## Critérios de aceite

- UI e interações reconhecíveis como o V1, comprovadas por comparação por superfície.
- Preparação de novos cards com leitor parado não altera lista admitida, ordem, frames ou deslocamento.
- Nenhum download/decode iniciado pelo renderer; card admitido possui apresentação final.
- Scroll libera cards preparados sem salto de âncora ou descarte perceptível dos anteriores.
- Falha de abastecimento mantém o conteúdo legível; feedback não redimensiona o viewport.
- Trocas de contexto rejeitam callbacks antigos e retorno conserva a posição.
- Responsabilidades têm um único dono e adaptadores não reproduzem o monólito do V1.

Este documento é uma análise e proposta concreta de sequência. Não certifica estabilidade do build instalado nem implementa a portabilidade nesta etapa.
