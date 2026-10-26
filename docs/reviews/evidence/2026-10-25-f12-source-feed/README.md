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
| `FeedMineApp/FeedMineApp/FeedMineApp.swift` | **só** o call site da superfície de Fontes passa `onOpenSource` — o sheet de filtros mantém apenas a própria navegação, porque abrir uma fonte ali fecharia o sheet e descartaria o rascunho do leitor, fora do F12. O host **abre primeiro e fecha depois** (o `onDismiss` do sheet adota a seleção e marcaria `replacingSession`, recusando a transição legítima se as duas corressem juntas), preserva `sourcesPath` (reabrir volta ao mesmo nó) e, quando a chave selecionada não é resolvível, declara “Não foi possível abrir o feed desta fonte.” em vez de silêncio |

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
| UI (jornada) | `FeedMineUITests.testF12TheSourceRowOpensItsOwnFeedAndTheToggleDoesNot` — **SKIPPED com medição**, não PASS. No `FeedMine Reserve 1024` a árvore do sheet fica `Application`-only (app em foreground, `state=4`, inalterada aos 181 s). No **iPhone 17 ocioso** (device diferente, mesma jornada): o sheet abre (`sources-done` presente), mas **nenhuma linha do catálogo aparece em 90 s** — falha diferente, mesmo efeito. Controle positivo: jornadas **sem sheet** (`PortabilityJourneyUITests.testOnboardingComposerResetAndStartBroad` e a jornada `deferred`) passam no Reserve. Controle negativo: o teste **existente** `FeedMineUITests.testBookmarkBoxesManageAndOpenTheirOwnList` falha com o **mesmo sintoma de título/conteúdo do sheet ausente** (nav bar `Caixas de salvos` e `Salvos` ausentes) — e a árvore **não** estava vazia ali: o campo de texto do alerta apareceu (`Emoji`, `dictate`). Ou seja, o que se mede é a ausência do título/conteúdo do sheet, não “sheet sem árvore alguma”. |

A jornada preservada (`FeedMineUITests.testF12TheSourceRowOpensItsOwnFeedAndTheToggleDoesNot`, dentro da mesma
classe dos helpers comprovados — `scrollIntoView` com `app.tables`, e o toggle como `app.switches`, não botão)
descreve o fluxo completo: superfície vazia → Fontes → seção → nó real do catálogo → linha da fonte (sem controle
enquanto não selecionada) → toggle sem navegar → linha abre o feed → rótulo do contexto é o nome da fonte → cartas
só daquela fonte → reabrir Fontes volta ao mesmo nó. Verificada nesta árvore: **compila e skipa** com a medição
acima (`1 skipped, 0 failures`).

## Limites

- **A prova de UI não é PASS.** O skip carrega a medição; nenhuma asserção foi trocada por existência de
  `Application`.
- O feed de fonte fora da seleção não existe no modelo de sessão (documentado acima); não foi inventado.
- Nada de gates, oráculo, limiar, corpus ou driver foi tocado. B03 continua FAIL mecânico, alheio a esta entrega.
- Não há alegação de UX12 completo: UX12-A/C/D seguem sem prova nesta rodada.
- Artefatos externos: `/tmp/nf04-r7-apptest3.log`, `/tmp/nf04-r7-ui4.log`, `/tmp/nf04-r7-sheetcontrol.log`,
  `/tmp/nf04-r7-dd` (derived data, descartável).

## Rodada 8 — a fonte catalogada **não selecionada** (requisito integral)

A rodada 7 abria somente fontes já selecionadas, e a limitação de `sessionState` (`.source` fora da seleção vira
`.main`) havia sido tratada como regra. Não é: R1 (tocar a origem leva ao destino), R4 (habilitar é opcional) e S1
(abrir não reabilita endpoint nem substitui a Edition) pedem a fonte catalogada **mesmo desabilitada**.

| Requisito | Implementação | Prova |
|---|---|---|
| identidade canônica, sem invenção | `AppComposition.catalogueFeed(forKey:)` resolve a chave pelo dono (`TrustedFeed.resolveAvailable` sobre o catálogo ativo); nada é derivado, nada é casado por título/URL | teste de app resolve a mesma chave por `LegacyCatalogReader` + `LegacyCatalogImport` e compara o `SourceID` |
| abrir sem habilitar endpoint / alterar seleção | `openSourceContext` mantém `feeds` = seleção do leitor; só o **filtro** passa a ser a fonte. Nenhum target/registro é criado para ela | `sourceKeys` idêntico antes/depois; `composition.feeds` idêntico; `selectContext(.source:)` continua recusando a mesma fonte |
| só memberships locais da fonte | elegibilidade da sessão inclui **apenas** a fonte do contexto (`AppComposition` policy: `eligible ∪ {contextSource}`); a janela de candidatos já é *source-scoped* | duas memberships semeadas (S e outra); publica a de S e **nenhuma** da outra |
| vazio/erro honestos | sem supply local a sessão apresenta a ausência (`.unavailable`), sem cair no feed principal | UI (jornada, quando o sheet expõe linhas) verifica a superfície de ausência e a ausência de outras fontes |
| botão e toggle independentes, também desabilitada | `NodeSourcesView` desenha o controle sempre que o host tem destino (não exige `isSelected`); o toggle segue irmão | teste de app abre com a fonte fora da seleção; a jornada de UI afirma o controle com o switch em `0` |
| retorno/nó/contexto preservados | `sourcesPath` não é limpo; o host abre antes de fechar (o dismiss não disputa `replacingSession`) | UI (quando executável); app test afirma o contexto após a recusa da rota comum |

**Validação executada (candidata):** `CompositionTests.testF12OpensAnUnselectedCatalogueSourceWithOnlyItsLocalMemberships`
— **PASS** (0,79 s): contexto `.source(sourceID)`, nunca `.main`; seleção e feeds inalterados; carta publicada só da
fonte S; a outra fonte semeada não aparece. `testF12RefusesAnUnresolvableKeyAndOpensTheSelectedSource` — **PASS**.

**Controle base × candidata (device e configuração idênticos):** o teste **pré-existente**
`testCleanInstallPresentsTheBundledCatalogueSourceWithTransportBlocked` foi executado na candidata e na base
`dde275fa` (worktree isolado `/tmp/feedmine-base-dde275fa`, assets não versionados copiados do checkout principal,
depois removido). **As duas árvores falham nas mesmas linhas (215/224/226)**: a asserção de locale espera pt-BR num
device em inglês e a superfície de Fontes não lista as seções. Causa medida no container do app: a instalação
recusa a revisão 5 obtida da rede por `sha256 mismatch` (`quarantine.jsonl`) e serve o catálogo empacotado em modo
degradado; o sheet não expõe as linhas em nenhuma das árvores. **Isso não é F12 e não é regressão da candidata.**

**Limites declarados, sem aceite:**
- A jornada de UI segue **skipada** com a medição (compila; `1 skipped, 0 failures`). Skip **não** é aceite: a
  prova de UI da abertura não selecionada continua pendente enquanto o sheet não expuser as linhas — o próximo
  passo é o modo degradado do catálogo (`hasCatalog`/fallback empacotado) ou um harness com a árvore do sheet.
- **Relançamento:** abrir grava o contexto da fonte; num novo launch, `sessionState` (sem o flag explícito) ainda
  converte `.source` fora da seleção em `.main`. Isso é uma lacuna conhecida do caminho de launch, **não** coberta
  por esta rodada; não foi alterada para não mexer no fallback global sem a suíte completa.
- `capacity-ready.json` preservado; nenhum gate/oráculo/limiar/corpus tocado; B03 segue FAIL mecânico.
