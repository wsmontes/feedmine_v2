# Revisão da consolidação de 30/out e passagem para o Codex (2026-11-02)

Escopo revisado: `c039274..2eca5b4` em `main` (consolidação das 21 PRs). Branch com as correções:
`kiro/review-fixes-20261102`, partindo de `2eca5b4`. Esta máquina é Windows, sem toolchain Swift:
**nenhuma linha Swift deste branch foi compilada ou testada aqui.** O próximo passo exige macOS.

## O que este branch muda

| Commit | O quê | Verificado aqui |
|---|---|---|
| `9f52adb` | cherry-pick de `e232f4c` (PR30): `FeedItemRowView.==` não lê closure isolada no MainActor (Swift 6) | Não; verde no CI de `ci/full-swiftpm-ui-legacy-20261031` (run 41225997714) |
| `c478a87` | cherry-pick de `d4c8c23` (PR34): fixture V1 em pasta colapsada (APFS recusa `mkdir feedmine` após `FeedMine`) | Idem |
| `e3871fd` | `FeedNativeViewport`: volta o `.onChange(of: unavailableImageCardIDs)` que `473dee7` criou e a resolução de conflito do cherry-pick `c415ca3` (de `10bc0bd`, anterior a `473dee7`) apagou | Não |
| `87c8117` | `FeedSession.submitViewport`: observação recusada (âncora sem pixels) agora instala a residência que `boundedResidency` decidiu; mantém âncora anterior e substituição; não chama `markSeen`. Teste novo `ScrollAdmissionTests.testRefusedObservationStillCommitsTheResidencyItDecided` (deve ser RED em `2eca5b4`) | Não |
| `028a2ba` | `RuntimeDatabase`: recusa migrações desconhecidas **antes** de `migrate` | Não |
| `2b9fae4` | `release-testflight.sh`: archive e export expandem o mesmo `SIGNING_FLAGS` (antes era código morto); +x em `bootstrap_catalog.py` e `run-browser-return-ab.sh` | Sim, ver abaixo |
| `146915e` | workflow `feedmine-main-package.yml`: suíte do pacote + contratos de release em push para `main` e PR para `main` (`main` não tinha workflow) | Não |
| `0c50dfd` | `test-export-signing-flags.sh`: stub do `xcodebuild` carimba Branch/BuildDate (sem isso os casos 1a–2a saíam com 8 desde `f7dd4be`); caso (5) estático da definição única | Sim |

Verificação local do harness de assinatura (Git Bash + shims de `PlistBuddy`/`mktemp` BSD, com o
script copiado trocando `/usr/libexec/PlistBuddy` por `PlistBuddy`): `origin/main` passa os 12 casos
comportamentais e falha o (5); este branch passa 13/13. `Tests/ReleaseScripts`: 34 de 40 passam no
Windows; os 6 restantes falham só por ambiente (symlink sem privilégio, `mktemp` BSD, arquivo
bloqueado), não por estas mudanças.

## Para fazer no Mac, em ordem

1. `xcodebuild test -scheme FeedMine-Package -destination 'platform=iOS Simulator,…' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`.
   Confirmar que compila e que o teste novo de `ScrollAdmissionTests` passa aqui e falha em `2eca5b4`.
2. `bash scripts/test-export-signing-flags.sh` (macOS nativo, sem shims).
3. Se verde, abrir PR para `main`. Não foi aberto daqui.

## Pendente, exige simulador/aparelho

**Alta: a lista física congela depois que a residência libera a cabeça** (`FeedScreenStore.install`,
bloco `nextIDs.starts(with: previousIDs)`). O produto usa `keepsAdmittedHead: true` com 8/16
(`AppComposition.swift:4480`). Após ~9 cartas, a imagem da carta 0 é liberada, o
`FeedReadyVisualWindow.initial` passa a começar depois dela, a mudança deixa de ser "só append" e
`renderedItems`/`physicalWindow` não são mais atualizados no mesmo escopo: cartas novas não aparecem
e as cartas antigas continuam segurando bitmaps. Os testes do store só usam fixtures 100% prontas.
O trabalho em andamento está em `fix/native-ready-handoff-staging-20261031`,
`test/feed-screen-native-proof-20261102`, `ci/native-stage-host-validation-20261101` e no RED
`ci/native-host-nonprefix-red-20261031`. Não mexi nisso para não competir com essa linha.

**Baixa:** `FeedReadyWindowOwnership`, `FeedNativeReadyWindowHandshake`, `FeedVisualWindowPlan`,
`FeedVisualRailIndex` e a API provisória de `FeedNativeScrollOffset` não têm chamador em produção
em `2eca5b4`; as checagens `provisional*` rodam em `observe`/`updateWindow`. Fica para quando o
handoff nativo for ligado (item acima).

**Baixa:** `busyMode = .timeout(10)` — não verifiquei se alguma escrita roda no MainActor (um lock
disputado viraria 10 s de tela parada).

## Rodada 2: correções de usabilidade (mesmo branch, `727db59..HEAD`)

Base: `docs/reviews/2026-11-02-kiro-usability-review.md`. Também **não compilado aqui**; uma revisão de
compilação feita por leitura não achou erro certo e apontou quatro riscos de runtime, já corrigidos em `a1372a7`.

Feito:
- D1 falha de inicialização: `StartupFailureView` com "Tentar novamente" (`AppComposition.retryStartup`);
  falha na construção da composição diz para reabrir o app.
- Menu: as ferramentas de cada preset só aparecem no próprio preset (o achado B1/B2 do relatório estava
  exagerado: `refreshMenuDestinations` já filtrava; o defeito real era "Excluir marcador inteligente" num feed
  curado).
- Retry no fim da lista com cards (`FeedScreen.tailRecoveryBlock`) e retry no `.failed` sem cards
  (expectativa U10 de `FeedScreenRenderingTests` atualizada).
- Salvos: remover por swipe/menu (`FeedAssociation.removeSaved`), "Tentar de novo" na falha de leitura.
- Alertas de erro que não fechavam (4 stores ganharam `dismissError()`); erro das ferramentas de fontes
  agora aparece (`SourceToolErrorAlert`); colar no add-feed descarta a prévia velha.
- Prompts da biblioteca: `libraryPrompt` capturado antes do `Task`; falhas viram toast; nome vazio desabilita
  "Salvar". Criar feed nas preferências avisa falha e limpa o nome.
- Export: só a falha de escrita foi acrescentada. "Salvar arquivo" continua abrindo a folha do sistema
  (desenho testado por `testSavingTheExportOpensTheSystemSurfaceAndKeepsTheReadingPoint`).
- Rascunho de filtro obsoleto: descartar ou continuar editando; no swipe, descarta com toast.
- Item sem nada para abrir: toast "Este conteúdo não está disponível".
- Coleção vazia: "Adicionar feed por link". Leitura em recuperação: aviso visível com "Escolher como
  continuar"; sem ações de fim de conteúdo ali. Falha ao salvar o onboarding: alerta que reabre.
- Mídia: fechar o mini player (`stopMedia`); player cheio sem "Carregando…" junto do erro.
- Caixas: confirmação ao apagar (apagar a caixa tira dos salvos o que só estava nela); um só "Concluir"
  ao reordenar.
- Convite editorial: título uma vez; botões quebram linha com `ViewThatFits`.
- Busca: fechar pela lupa é o mesmo que "Cancelar".
- Busca no catálogo de fontes (`SourceManagementView.searchable`).
- Compartilhar no leitor local (`ShareLink`).
- Humor/tipo de conteúdo em pt-BR (`displayName`); "carta" → "card"; valores em inglês no
  `Localizable.xcstrings` para todas as strings novas.

Não feito, de propósito:
- F1/F2 (lista física congela; tela volta a "Descobrindo…" com âncora sem pixels) e F3 (convite editorial
  entrando numa célula visível): dependem da linha `native-*` e de simulador.
- F5 estado "lido": não há registro persistido de leitura; precisa de decisão de produto (aberto ou visto).
- Valores de VoiceOver em inglês ("selected", "bookmarked"): são contrato dos UI tests e do benchmark congelado.
- Puxar para atualizar: o feed é uma pista que cresce no fim; um gesto no topo que não traz nada no topo
  confunde, e `.refreshable` mexe no inset do scroll que a captura nativa mede. Substituído pelo retry no fim.
- Baixa prioridade: aviso do limite de 200 salvos, restaurar padrões nos ajustes, compartilhar visível no
  card, salvar visível no iPad em lista, motivos por link no add-feed direto.

Para validar no Mac, além da suíte do pacote:
- UI tests que podem mudar: fontes (barra de busca nova no `NavigationStack`), caixas (sem `bookmarkBoxes.done`
  durante reordenação; apagar pede confirmação), mini player (botão `mini-player-close`), feed com
  `.unavailable/.deferred/.unreachable/.failed` e cards (bloco `feed-tail-recovery` depois do último card),
  `FeedVisibleExperienceUITests` caso 3 (falha atrás de conteúdo: o bloco entra no fim, os cards não devem mover).
- Conferir no simulador: swipe "Remover" nos Salvos some com a linha e mostra o toast; "Tentar de novo" relê.

## Rodada 3: sequenciamento v7 (mesmo branch)

Edi??es novas passam a declarar `sequencingPolicyVersion` 7 (`.sourceShareThenMaximumDistance`). A cada
escolha, entre os candidatos compat?veis com PD-4, ficam s? as fontes com a menor participa??o nas ?ltimas 32
posi??es da Edition (regra de provedor menos usado da V1). Dentro desse empate, o v6 decide como antes (tipo ?
assuntos ? fonte ? ordem base). Sem aleatoriedade.

- C?digo: `MaximumDistanceSequencing.sequence(..., sourceShareWindow:)`, `SelectionEngine` (v6 s? com revis?o 6,
  v7 s? com revis?o 7), `LocalProductionSlice` (v7 l? as mesmas posi??es completas), `PublicationPreparation`
  (v7 congela o tipo de m?dia como o v6), `FeedAssociation.sequencingBehavior` e vers?o 7 na composi??o.
- Edi??es j? publicadas em v6 continuam em v6 quando restauradas (mesma conven??o da passagem 5?6). Uma
  instala??o existente s? v? o v7 quando uma Edition nova ? criada para o contexto.
- Prova offline: `evidence/2026-11-02-v6-sequencing-sim/v7_sim.py` e `v7_output.txt`. Um podcast entre 20
  feeds de texto: v6 25/50, v7 3/50, tamb?m em oportunidades de 4 cards lendo o hist?rico. Fonte que entra
  depois de 200 posi??es: 3 cards e depois rod?zio normal.
- Testes: `SourceShareSequencingTests` (novo; n?meros iguais aos da simula??o), `CompositionTests` (vers?o 7,
  8 cai para rec?ncia), `MaximumDistanceSequencingTests` (7 e 8 com o comportamento v6 n?o herdam v6),
  `PublicationPreparationTests` (v7 congela o tipo).
- No Mac: rodar esses quatro primeiro. Depois, num aparelho com o cat?logo real, comparar os 50 primeiros
  cards de uma Edition nova com os da Edition v6 atual (participa??o de ?udio e fontes distintas).

## Rodada 4: teto de feed e imagens decorativas (mesmo branch)

- **Teto do corpo do feed: 1 MB para 4 MB no estado nominal** (`StageBudgetPolicy.nominalFeedBodyBytes`). Um feed
  acima do teto d? `bodyTooLarge` (conte?do remoto, sem nova tentativa), ent?o um podcast que publica o cat?logo
  inteiro num documento nunca gerava card. Os degraus de press?o n?o mudaram: 500 KB em rede limitada, pouco
  espa?o ou aquecimento s?rio; 250 KB em cr?tico. Teste: `PipelineHeadroomTests.testNominalPullReadsLargeFeedsAndPressureKeepsTheSmallerRungs`.
  No aparelho: medir mem?ria com 8 feeds grandes simult?neos.
- **Imagens decorativas filtradas na origem**, para o item virar card de texto em vez de imagem declarada que
  falha e sai da fila (INV-17):
  - marcadores novos em `SyndicationMediaLocator.decorativeMarkers`: smilies do WordPress (`/wp-includes/images/smilies/`,
    `wp-smiley`), bot?es de coment?rio do WordPress.com, Feedsportal, `doubleclick` em qualquer dom?nio, `/avatars/`;
  - `<img>` com `width`/`height` declarados: um lado de 1 ou 2 px, ou os dois ? 150, ? pulado e a pr?xima imagem
    vale (`isDecorativeDeclaredSize`);
  - `media:thumbnail`/`media:content` com um lado declarado de 1 ou 2 px ? recusado mesmo sem o outro lado.
  - Testes: `SyndicationMediaLocatorDecorativeTests` (novo) e `SyndicationTranslatorTests.test28b...`.
  - Efeito colateral esperado: como as URLs de m?dia entram na impress?o material, itens que tinham uma dessas
    imagens ganham uma revis?o nova na pr?xima coleta. Cards j? publicados n?o mudam (PD-5).

**Fora desta m?quina, de prop?sito:**
- Mem?ria de visto/aberto por mat?ria: migra??o de banco e decis?o de produto sobre "lido".
- Chave de provedor/agregador no v7: `providerID` ? sempre nil em produ??o (`SyndicationTranslator.swift`, `providerID: nil`)
  e nenhum campo de publicador original ? lido; exige modelo novo.
- Limite por fonte e filtros antes do `LIMIT`: a janela ? paginada por cursor e um corte em SQL pula linhas para
  sempre (`ContentStore.candidateWindow`). Precisa de desenho e testes rodando.
- Idade m?xima: vários fixtures usam datas fixas antigas (ex.: 1_700_000_000, nov/2023); um corte quebraria testes que n?o consigo rodar aqui.
- Busca ao voltar depois de N minutos: a coleta s? nasce da press?o do runway (`RunwayController.acquisitionIntentIfEligible`);
  um gatilho por tempo mexe nesse contrato.
- Port?es de qualidade por item e idioma detectado: mudam a contagem de rejei??es e a identidade do que entra.
