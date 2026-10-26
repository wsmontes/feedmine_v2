# F12/UX12-B — abrir o feed de uma fonte a partir da linha da taxonomia (25/10/2026)

Requisito: `docs/product/F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md` — R1 (tocar a origem leva ao destino
declarado), R4 (habilitar é opcional e é do toggle), UX12-B (o feed de S contém **somente** memberships legítimas
de S) e o “Ouro V1 — abrir uma Source, não só ativar um toggle” (G01/G08/G09). O mapa de produto registrava a
lacuna: “a linha de fonte na taxonomia oferece toggle, sem ação própria de abrir seu feed”.

## O que mudou

| Arquivo | Mudança |
|---|---|
| `Sources/FeedMineUI/Sources/NodeSourcesView.swift` | `NodeSourceRowView` ganha `onOpen` opcional: quando existe destino, o trecho de título vira um `Button` (`node-source-<key>`); sem destino, nenhum controle é desenhado. O `Toggle` (`node-source-toggle-<key>`) permanece irmão, com área própria |
| `FeedMineApp/FeedMineApp/AppComposition.swift` | `openSourceFeed(forKey:)`: adota a seleção pendente (os toggles do sheet são duráveis), casa a **chave do catálogo** com o `TrustedFeed` resolvido pelo próprio owner e seleciona `.source(sourceID)`. Devolve `false` quando a chave não está na seleção — sem derivar identidade e sem cair no feed principal |
| `FeedMineApp/FeedMineApp/FeedMineApp.swift` | as duas chamadas de `NodeSourcesView` (fontes e árvore dos filtros) passam `onOpenSource`; o host fecha o sheet e, em falha, declara “Não foi possível abrir o feed desta fonte.” O caminho interno do sheet é preservado, então reabrir Fontes volta ao mesmo nó |

**Por que a fonte precisa estar na seleção:** `sessionState(for:)` converte `.source(id)` em `.main` quando a
fonte não está entre os feeds ativos. Abrir uma fonte fora da seleção mostraria o feed principal com o rótulo de
outra fonte — exatamente o “destino falso” que R1/S1 proíbem. Habilitar é o ato do toggle (R4); depois disso a
linha ganha o controle de abrir. Essa fronteira está registrada como lacuna de produto (contexto de fonte única
fora da seleção não existe), não como funcionalidade inventada.

## Validação executada

| Verificação | Resultado |
|---|---|
| Pacote: `swift build` | Build complete |
| Pacote: `SourceManagementStoreTests` + `FeedScreenRenderingTests` | 47 testes, 0 falhas |
| Oráculo UX12-B (membership) | já provado em `CandidateProviderTests.testSourceFilteringPreservesExaminedCountAndRelativeOrder`: com itens de a e de b no banco, `candidates(plan(.source(a)))` devolve somente a — nenhuma identidade é filtrada por título ou URL |
| App (simulador, integrado) | `CompositionTests.testF12SourceRowOpensTheSelectedSourceAndRefusesAKeyOutsideTheSelection` — **PASS**: chave fora da seleção devolve `false` e não mexe no contexto nem na seleção; chave selecionada leva a `.source(sourceID)` e a seleção permanece idêntica |
| UI (jornada) | `SourceFeedOpeningUITests` — **SKIPPED com medição**, não PASS: neste device/runtime o conteúdo de **sheets** não entra na árvore de acessibilidade (árvore só com `Application`, app em foreground, 181 s). O controle negativo confirma que não é desta superfície: o teste existente `FeedMineUITests.testBookmarkBoxesManageAndOpenTheirOwnList` falha do mesmo modo (nav bar do sheet e conteúdo ausentes). Controle positivo: uma jornada sem sheet (`PortabilityJourneyUITests.testOnboardingComposerResetAndStartBroad`, e a jornada `deferred`) passa no mesmo device |

A jornada preservada (`SourceFeedOpeningUITests.testTheSourceRowOpensItsOwnFeedAndTheToggleDoesNot`) descreve o
fluxo completo: Fontes → seção → nó real do catálogo → linha da fonte (sem controle enquanto não selecionada) →
toggle sem navegar → linha abre o feed → rótulo do contexto é o nome da fonte → cartas só daquela fonte →
reabrir Fontes volta ao mesmo nó. Ela roda e exige tudo isso num harness cujo sheet exponha a árvore.

## Limites

- **A prova de UI não é PASS.** O skip carrega a medição; nenhuma asserção foi trocada por existência de
  `Application`.
- O feed de fonte fora da seleção não existe no modelo de sessão (documentado acima); não foi inventado.
- Nada de gates, oráculo, limiar, corpus ou driver foi tocado. B03 continua FAIL mecânico, alheio a esta entrega.
- Não há alegação de UX12 completo: UX12-A/C/D seguem sem prova nesta rodada.
- Artefatos externos: `/tmp/nf04-r7-apptest3.log`, `/tmp/nf04-r7-ui4.log`, `/tmp/nf04-r7-sheetcontrol.log`,
  `/tmp/nf04-r7-dd` (derived data, descartável).
