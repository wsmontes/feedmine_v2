# Execução do plano V2 — 17/out/2026

Plano: `2026-10-17-v2-fluidez-capacidade-entregas.md`.

## Base reconciliada (T1)

- Checkout original: `docs/status-pause-2026-10-17`, HEAD `711cfac3`; dois documentos não rastreados, preservados.
- Main: `5e4e21425f5e1be22cdf7ed10e4c1728d2a33f15`.
- Candidata: `integration/51`, `8fcfe37c6ff46b68b6754b25852bc1b47d825766`.
- Comparação refeita: 74 arquivos, 3.676 inserções, 289 remoções.
- Implementação isolada na branch `codex/v2-fluidez-capacidade`, a partir da candidata.
- Primeira execução `swift test`: bloqueio ambiental de escrita em caches e na worktree; repetida com permissão de execução fora do sandbox. Não é falha de produto.
- Suíte ampla: PASS, 1.445 testes, 4 ignorados, zero falhas (48,55 s); evidência temporária `/tmp/feedmine-v2-baseline.log`.
- Destino Xcode consultado nesta sessão: simulador FeedMine UI ptBR / iOS 26.5.

## Decisões de execução

Ruling: a instrução humana “implemente” autoriza executar o roteiro fornecido; a ressalva histórica do documento sobre não autorizar tudo por si só não substitui essa instrução. Sem merge, push ou release.

Ruling: usar a candidata 51, não a branch documental aberta — preserva correções já integradas e a base examinada pelo plano.

## Interfaces compartilhadas

- T2/T3: projeção imutável, evidência de membership e admissão continuam pertencendo à sessão; instalação não pode reconstruir pixels.
- T2/T7: instalação e bookmarks precisam respeitar proveniência e mudanças concorrentes de contexto.
- T4/T5/T6: um único causal execution autoriza publicação; conclusões de rede/mídia são fatos para o owner existente.
- T7/T8/T9: contexto/checkpoint e preferências confirmadas mantêm durabilidade; cancelamento não substitui fences.
- T6/T10/T12: limites de trabalho não são quotas editoriais; benchmark congelado não será alterado.

## Estado

T1: reconciliação executada, com falhas preexistentes documentadas. T2: somente membership implementado; tarefa aberta. T3–T12: pendentes. Nenhum gate de produto ou jornada física certificado.

T2 Ruling: antecipar somente a otimização mecânica de membership durante a execução dos testes iOS de T1. A própria janela imutável prepara o Set; nenhuma fila, scheduler ou autoridade nova. Não muda semântica e usa regressões existentes, sem teste que espelhe implementação. T1 continua aberto até prova pelo host.

## Provas executadas

- Pacote na base: `swift test`, 1.445 testes, 4 ignorados, zero falhas, exit 0.
- Pacote com membership preparado: `swift test`, 1.445 testes, 3 ignorados, zero falhas, exit 0. A diferença nos skips vem dos artefatos locais de catálogo; os skips restantes dizem respeito a compilador/corpus não disponíveis.
- Viewport/store/admissão: 75 testes, zero falhas, exit 0 (2,384 s).
- Host iOS: iOS 26.5, simulador `3AEA0B45-0BE6-49F1-8BAB-2591B13BBE7A` (nome local FeedMine UI ptBR). `CompositionTests`, `ContentFilterTests` e `FilterConfirmationBoundaryTests`: 80 testes, quatro asserções falharam em três casos; 4/4 testes da fronteira de confirmação passaram.
- Repetição dos três casos na candidata **sem alterações de implementação**, restaurada por `git show HEAD:<arquivo>` e com restauração automática dos bytes de trabalho no `finally`: as mesmas quatro asserções falharam. Não são regressões do membership.

### Defeitos/provas ainda vermelhos

1. `testAPublicationConcludedAfterTheFollowUpWindowGrowsTheAdmittedWindow`: duas asserções. A premissa de segunda publicação falha (reserva 3 → 3); portanto a jornada não certifica crescimento.
2. `testAReceiptForASupersededEditionDoesNotGrowTheCurrentEditionsWindow`: não obtém o recibo da segunda publicação; não certifica o fence dessa jornada.
3. `testATemplateTheReaderTurnsOnHidesWhatItsWordsMatch`: espera uma regra, recebe duas no locale português. O contrato de templates inclui inglês mais o idioma do leitor; o fixture contém palavras nos dois idiomas. Confirmado: o mesmo teste passou com `-testLanguage en -testRegion US`, sem alteração de código. A falha em português vem da premissa de uma única língua do fixture, não do comportamento de exclusão.

Nenhuma destas falhas foi suprimida ou marcada como PASS.

### Ambiente e referências

- O primeiro comando Xcode usou o nome incorreto `FeedMineTests`; o scheme declara `FeedMineAppTests`. Corrigido antes de qualquer prova válida.
- Recursos locais ignorados pelo Git foram copiados sem alteração do checkout original: catálogo de produto e `bench/corpus/profiles.json`, exigido pelo target de UI mesmo no teste unitário. Nenhum script, avaliador ou conteúdo congelado do benchmark foi alterado.
- As três referências `FEEDMINE_{INTENTIONS_VS_DELIVERIES,SCROLL_ARCHITECTURAL_STUDY,BACKEND_HEADROOM_KERNEL_AUDIT}_2026-10-17.md` não existem nestes checkouts. Produto e invariantes vigentes foram lidos; nenhuma conclusão desses estudos ausentes foi inventada.
- Nova regressão T1 acrescentada pelo host real: movimento → inactive → background → foreground preserva taxa e scope; trocar contexto cria scope sem taxa aprendida. PASS: um teste, zero falhas, 1,020 s; xcodebuild exit 0.
- Revisão independente: membership, fences e Hashable sem achados. Lacuna inicial da regressão (inactive sem background) corrigida; revisão confirmou a correção.

## Alcance efetivo da alteração T2

Somente membership: o Set de IDs pertence à janela imutável e é compartilhado pelas evidências; igualdade/hash continuam baseados em cards e âncora, sem percorrer novamente o estado derivado. Não há nova autoridade nem invalidadores.

Ainda NÃO implementados: consumo limitado de observações, metadados de bookmark fora do MainActor, T3–T12 e jornadas físicas. Nenhum gate G1–G4 está fechado. Não há alegação de fluidez medida a partir de testes unitários.

### Registro T1

SHA inicial: `8fcfe37c6ff46b68b6754b25852bc1b47d825766` | defeito/prova: quatro asserções iOS vermelhas, reproduzidas na candidata intacta | alteração: registro de base e regressão do host para aprendizagem/lifecycle/scope | prova verde: pacote e nova regressão do host | jornada protegida: retorno ao foreground sem apagar aprendizagem e troca de contexto sem herdá-la | pendência: defeitos de segunda publicação, locale do teste, T2–T12 | SHA final: `ba4f0aa7`.

A reconciliação de T1 não afirma que a candidata está inteiramente verde. Os testes vermelhos permanecem como lacunas registradas e impedem certificação integrada.

### Subentrega T2 — membership preparado

SHA inicial: `ba4f0aa7` | alteração: Set de IDs preparado na janela; observações compartilham o valor e conferem membership sem map/varredura | prova: 75 regressões específicas e 1.445 testes de pacote, zero falhas; nova regressão nativa e filtro em inglês passaram | revisão independente: sem achados remanescentes | pendência: restante de T2 e todos os gates. A mudança não foi medida como correção de frames em Release.

## R00 — provas discriminantes (resíduo de T1)

Executado em 2026-10-17 na worktree `~/.codex/worktrees/v2-fluidez-capacidade/feedmine_v2`, base
`bc6a38dc2e16072fb82dc17071d100534d070a8a`, branch `codex/v2-fluidez-capacidade`. Destino Xcode:
simulador `FeedMine Gate` (`3314B597-4CBF-4B95-9B7C-AF52BB432FC2`, iOS 26.5). DerivedData:
`/tmp/feedmine-v2-dd`.

### Reprodução (vermelho, sem alteração)

Os dois testes de publicação executados isoladamente com `-testLanguage en -testRegion US`
reproduziram as falhas registradas: reserva `3 -> 3` no teste de crescimento e ausência do recibo da
segunda publicação no teste de recibo superado (1 teste/3 falhas; xcresult
`/tmp/fm-v2-r00-repro.xcresult`).

### Causa medida (não suposta)

Diagnóstico temporário no host leu `RunwayControllerSnapshot` e chamou `reconsider` diretamente
(removido antes do commit): após o `launch`, `localSupplyExhausted=true`, `inFlight=false`,
`readyAhead=exact(3)`, `coverage=pressured(requiredCards: 32)`, `resources.reserveCards=16`,
`consumption=nil`. A ativação usada pelo teste (`activateCurrentPresentation`) reenvia a posição
como `stationary`; a medição seguinte registra **0 cartas/s**, e `RunwayPolicy` responde `healthy`
para um leitor parado — a pista não repõe nada, corretamente. O instrumento do teste, portanto, não
era um caminho que produz publicação; a premissa é que estava errada, não o produto.

O segundo diagnóstico mostrou ainda que `drive()` sem observação nova é inerte por contrato
(`lastAcknowledgedAcquisitionIntent` ainda igual ao intento da largada): "Only an explicit caller
opportunity resumes a deferred intent".

### Alteração

- `CompositionTests.testAPublicationConcludedAfterTheFollowUpWindowGrowsTheAdmittedWindow` passa a
  liberar a segunda publicação pela **oportunidade de cauda** do leitor
  (`driver.submitViewport(activity: .explicitTailApproach)`), a mesma chamada que a associação faz e
  **sem** o `growAdmittedWindowIfPublished()` dela. Antes da asserção visual, o caso agora afirma:
  (1) as fontes foram consultadas de novo depois da resposta de dois itens; (2) os candidatos novos
  foram admitidos ao pool canônico (`ContentStore.candidateWindow`); (3) a segunda publicação existe
  como segmento durável e o recibo chegou ao destinatário; (4) **no instante da chegada do primeiro
  recibo** a janela ainda era a antiga — o crescimento segue o recibo, não o antecede. O prefixo
  admitido anterior é preservado na ordem.
- `CompositionTests.testAReceiptForASupersededEditionDoesNotGrowTheCurrentEditionsWindow` usa a
  mesma oportunidade de cauda nas duas publicações retidas (edições superada e vigente).
- `ContentFilterTests.testATemplateTheReaderTurnsOnHidesWhatItsWordsMatch` declara a expectativa pelo
  idioma do ensaio: o fixture é bilíngue de propósito (`en` + `pt`), então o template resolve **uma**
  regra em inglês e **duas** em português. Nenhuma palavra válida foi removida.

### Provas verdes

| Prova | Resultado | xcresult |
|---|---|---|
| crescimento + recibo superado, `-testLanguage en -testRegion US` | 2 testes / 0 falhas | `/tmp/fm-v2-r00-en2.xcresult` |
| `ContentFilterTests` (4 casos), inglês | 4 testes / 0 falhas | `/tmp/fm-v2-r00-en.xcresult` |
| template, `-testLanguage pt-BR -testRegion BR` | 1 teste / 0 falhas | `/tmp/fm-v2-r00-pt.xcresult` |
| mutação: fence de edição removida de `publicationConcluded` | **vermelho** (a janela cresceu com o recibo obsoleto) | `/tmp/fm-v2-r00-mutation.xcresult` |

A fence foi restaurada (`git checkout -- AppComposition.swift`) antes do commit.

### Registro R00

SHA inicial: `bc6a38dc2e16072fb82dc17071d100534d070a8a` | vermelho: reprodução acima (3 asserções) | alteração: instrumento de cauda + fatos afirmados + locale explícito | verde: tabela acima | jornada protegida: crescimento por recibo, fence do destinatário (mutação prova a discriminação) | pendências: nenhuma desta tarefa; restante do plano segue pendente | SHA final: registrado no commit `test(composition): make publication and locale regressions discriminating`.

## R01 — ingresso de observações com trabalho pendente limitado

Base da tarefa: `062711eb` (R00). Worktree e destino os mesmos; `-testLanguage en -testRegion US`.

### Defeito e prova vermelha

As três callbacks do host (`onViewport`, `onRenderedViewport`, `onPresentedPosition`) criavam **uma `Task`
por evento** (`AppComposition.swift:1842-1860`): N callbacks produzem N tarefas não supervisionadas que
intercalam em cada `await`; nada limita o pendente e `close()` não as alcança. O consumidor já coalesce
no driver (`causalExecution`), mas só depois de todas as tarefas existirem.

A prova vermelha foi obtida por mutação dos dois fatos medidos, não por suposição:

| Mutação | Teste | Resultado |
|---|---|---|
| ingress volta a criar `Task` por callback (contador vivo do pendente) | `testScrollIngressDoesNotAwaitProducer` | **vermelho**: pendente `301 > 6` na rajada de 300 |
| driver carimba `sampledAt` na entrega (`monotonicNow()`) em vez do instante de captura | `testCoalescingPreservesCapturedConsumptionTiming` | **vermelho**: taxa `0.249` contra `0.5` esperado |

xcresult da mutação: `/tmp/fm-v2-r01-mutation.xcresult`. As duas mutações foram revertidas antes do commit.

### Alteração

- `FeedAssociation` recebe **um** resumo finito do ingresso (`PendingViewportIngress`): primeira
  movimentação (âncora de medição), última posição, e o mais novo de cada fato semântico — reversão,
  oportunidade de cauda, repouso e reconciliação local — além da posição desenhada (última vence).
  São no máximo 6 slots, independentes do tamanho da rajada. Fatos são entregues em ordem de instante de
  captura (empate pela ordem de ingresso), o que preserva a monotonicidade estrita do runway.
- Um **único** consumidor (`viewportDrain`) esvazia o resumo; a callback registra e retorna, sem `Task`
  por evento e sem aguardar produtor. O drain é geracional para não ser sobrescrito por uma tarefa
  aposentada.
- O instante e a identidade são capturados **no ingresso**: `IngressViewportFact.sampledAt` desce por
  `FeedPresentationHandoff.submitViewport` → `FeedRunwayDriver.submitViewport` → `runway.submitObservation`,
  em vez de ser carimbado na entrega. A identidade continua a `RenderedViewportEvidence`, validada pelo
  dono (`belongs(to:)`/ordinal da sessão) no momento da entrega.
- Exposição (`EditorialExposureLedger`) e o contador `viewportReceived` passam a ser fatos da callback;
  coalescer não perde carta vista.
- `background()` revoga a autorização de produção do ingresso e **conserva a posição prometida**: entrega
  a posição desenhada pendente antes do checkpoint, depois limpa o resumo. `foreground()` restaura a
  autorização; `close()` encerra pelo `active` e limpa o pendente.
- Relógio injetável: `AppComposition`/`FeedAssociation` aceitam `monotonicNow` (default: uptime do
  processo); o teste usa `IngressClock` controlado com tick de 1 ms (o controller recusa latência zero).
- Os nomes de atividade seguem os existentes; nenhuma fila, scheduler, cache ou segundo pipeline foi
  criado. A `FeedScreenStore` permanece sem `Task`/timer (regressão S12 intacta).

### Provas verdes

| Prova | Resultado | xcresult |
|---|---|---|
| os três casos novos (`testScrollIngressDoesNotAwaitProducer`, `testMovingObservationsRemainBoundedAndPreserveRest`, `testCoalescingPreservesCapturedConsumptionTiming`) | 3 / 0 falhas | `/tmp/fm-v2-r01c.xcresult` |
| host completo: `CompositionTests` + `ContentFilterTests` + `FilterConfirmationBoundaryTests` | **84 testes / 0 falhas** (76 + 4 + 4) | `/tmp/fm-v2-r01-suite.xcresult` |
| `swift test --filter FeedScreenStoreTests` | 18 / 0 | — |
| `swift test --filter FeedViewportCaptureTests` | 36 / 0 | — |
| `swift test --filter FeedPresentationHandoffTests` | 19 / 0 | — |
| `git diff --check` | limpo | — |

O teste de rajada também afirma: última posição entregue = posição do repouso; taxa de consumo medida > 0
(high-water real sobrevive); toda carta vista está no ledger de exposição; e o repouso é gravado no
checkpoint do contexto na posição desenhada.

### Registro R01

SHA inicial: `062711eb` | vermelho: tabela de mutações acima | alteração: resumo finito + consumidor único + instante de captura + revogação no background | verde: tabela acima | jornada protegida: captura não aguarda produtor; rajada limitada; avanço/repouso/exposição preservados; background não produz fora da tela | pendências: R02 e seguintes | SHA final: registrado no commit `fix(ui): bound viewport ingress without losing semantic facts`.

## R02 — instalação preparada e bookmarks sem I/O no MainActor

Base: `1deb0722` (R01). Destino e idioma os mesmos.

### Defeito

`FeedAssociation.install` lia `PublicationStore.bookmarkedCardIDs()` **sincronamente no MainActor** a cada
mudança de janela (o `bookmarksReadFor` era o paliativo), e o toggle lia o conjunto inteiro logo depois do
write. Além disso, nada distinguia uma preparação de bookmarks anterior a um toggle confirmado de uma
posterior: uma leitura atrasada podia reinstalar o conjunto antigo por cima do que o leitor acabou de
salvar/remover.

### Prova vermelha (mutação)

| Mutação | Teste | Resultado |
|---|---|---|
| instalação ignora o pacote preparado e agenda leitura | `testInstallDoesNotReadDatabase` | **vermelho** (`[]` ≠ `[card]`, duas asserções) |
| sem fence de revisão na leitura atualizada | `testOldBookmarkPreparationCannotUndoConfirmedToggle` | **vermelho** (a resposta velha limpou o conjunto confirmado; 6 asserções) |

xcresult: `/tmp/fm-v2-r02-mutation.xcresult`. Mutações revertidas antes do commit.

### Alteração

- `PreparedFeedInstallation` (novo arquivo `Sources/FeedMineComposition/PreparedFeedInstallation.swift`) carrega
  `state` e, opcionalmente, `Bookmarks { ids, base }`. Vive **ao lado** do handoff, não dentro dele: o teste de
  arquitetura do próprio handoff (`testStaticBridgeHasNoParallelAuthorityOrAutomaticExecution`) proíbe
  `init`/`var`/`actor` no arquivo do bridge, e um value type com inicializador quebraria essa fence. O intento do
  plano — um único valor preparado usado pela instalação — é preservado.
- `FeedAssociation.install(_ prepared:)` só valida e atribui: nenhuma leitura, nenhum `await`, nenhum abridor de
  banco. O half de bookmarks só instala quando `base == bookmarkMutationRevision`; caso contrário o conjunto
  confirmado vence e uma única leitura nova é agendada.
- Leitura durável off-MainActor (`Task.detached`) com single-flight (`bookmarkRefreshTask`); a janela preparada é
  memorizada, então uma posição sem diferença material não republica a lista nem relê bookmarks — o handoff
  continua alimentando runway/produção.
- Toggles e mutações da biblioteca entram no **mesmo** caminho confirmado: `bookmarkMutationConfirmed()` move a
  revisão e agenda a leitura. A exclusão de caixa é entregue por `ReaderBookmarkBoxesBackend(onConfirmedChange:)`,
  fiado em `makeBookmarkBoxesStore()`; o `ReaderLibraryCoordinator` que já existia segue autoridade de escrita.
- Removidos: a leitura síncrona dentro de `install` e o workaround `bookmarksReadFor`. Nenhum cache ou contador de
  geração de aquisição foi criado; a revisão é a das mutações **confirmadas** de bookmarks.

### Provas verdes

| Prova | Resultado | xcresult |
|---|---|---|
| `testInstallDoesNotReadDatabase` + `testOldBookmarkPreparationCannotUndoConfirmedToggle` | 2 / 0 | `/tmp/fm-v2-r02-final.xcresult` |
| host completo `CompositionTests` + `ContentFilterTests` + `FilterConfirmationBoundaryTests` | **86 / 0** (78+4+4) | `/tmp/fm-v2-r02-suite.xcresult` |
| `swift test --filter FeedPresentationHandoffTests` | 19 / 0 | — |
| `swift test --filter FeedScreenStoreTests` | 18 / 0 | — |
| `git diff --check` | limpo | — |

Os dois regressivos cobrem: instalação com o seam de storage **suspenso** (nenhuma chamada ao preparador),
pacote antigo não desfaz o toggle, conclusão invertida (salvar→remover→salvar com uma leitura velha), duas caixas
e exclusão de caixa, com o conjunto mantido na caixa padrão.

### Registro R02

SHA inicial: `1deb0722` | vermelho: tabela de mutações | alteração: pacote preparado + fence de revisão + leitura off-main single-flight + caminho confirmado único | verde: tabela | jornada protegida: instalação sem I/O, toggle confirmado imune a preparação antiga, exclusão de caixa consistente | pendências: R03 e seguintes | SHA final: registrado no commit `fix(ui): install prepared projection metadata without database reads`.

## R03 — pixels e âncora preservados na reversão

Base: `a4a1b3af` (R02). Suíte de runtime e host no mesmo destino.

### Defeito

`FeedSession.boundedResidency` liberava os bitmaps de tudo o que estava **fora da banda atual** e, ao voltar,
**excluía** a carta cuja reconstrução falhasse. Dois efeitos: (a) a superfície pode revelar a região que o leitor
acabou de deixar **antes** de o runtime receber a observação de reversão — ali o slot desenha vazio; (b) um asset
removido depois da publicação tirava a carta da janela, mudando ordem/geometria e podendo levar a âncora do leitor
junto.

### Prova vermelha (mutação)

| Mutação | Teste | Resultado |
|---|---|---|
| manter só a banda atual (sem a banda anterior) | `testReverseExposurePrecedesViewportCallback` | **vermelho**: o destino da reversão perdeu os pixels antes do callback |
| excluir a carta cuja reconstrução falhou (gate antigo) | `testMissingAssetDoesNotRemoveVisibleAnchor` | **vermelho**: identidade removida da janela e `XCTUnwrap` da carta falhou |

Mutações revertidas antes do commit.

### Alteração

- `FeedSession` mantém, além da banda atual, a banda do **anchor de residência anterior** (`previousResidencyAnchor`,
  inicializado também no warm start e no restore do checkpoint). O conjunto protegido é a união das duas bandas —
  no máximo duas janelas —, exatamente a região que a superfície pode revelar imediatamente. A decisão registra o
  anchor corrente para a próxima observação.
- Reconstrução que falha **não remove** a carta: ela mantém id, ordem, âncora e geometria congelada (layout, razão
  de aspecto, título/texto) com o placeholder publicado; não é reclassificada como texto. O id entra em
  `unrecoverableImageCards` para não repetir o decode a cada observação (sem varredura/retry infinito). As cartas
  ao redor são reconstruídas normalmente.
- O teste antigo `testACardReturningToThePixelBandIsReconstructedBeforeItIsDrawn` foi reconciliado: agora prova a
  reconstrução (sucesso) antes da publicação, com a geometria real do fixture; o caso de asset ausente virou o
  teste novo acima.
- O fixture de teste cresceu para 12 cartas; o sombreamento `UInt8(20 + index * 30)` estourava em 9+ cartas e foi
  corrigido para uma função que não transborda (defeito de fixture, não de produto).

### Provas verdes

| Prova | Resultado | xcresult |
|---|---|---|
| `RenderReadyAdmissionTests` (5 casos: admissão, decode em curso, readmissão, reversão, asset ausente) | 5 / 0 | `swift test` |
| `FeedSessionViewportTests` / `FeedPresentationAdmissionTests` / `FeedSessionCheckpointTests` | 6 / 0, 12 / 0, 21 / 0 | `swift test` |
| jornada de imagem `CardImageJourneyUITests` (desenho, burst e ida/volta) | 2 / 0 | `/tmp/fm-v2-r03-journey2.xcresult` |
| host `CompositionTests` + filtros + fronteira | 86 / 0 | `/tmp/fm-v2-r03-suite.xcresult` |

**Limite declarado:** a união de duas bandas aumenta a residência de bitmaps (até ~2× a banda) — a memória
residente é medida em R04/R22, não neste registro. A jornada de imagem rodou em Debug; a variante Release foi
tentada no fechamento de G1 e ficou **NOT_RUN** com o bloqueio registrado lá (o test action do scheme compila
`FeedMineAppTests` em Release, e os fixtures de teste do app são `#if DEBUG`).

### Registro R03

SHA inicial: `a4a1b3af` | vermelho: tabela de mutações | alteração: banda anterior protegida + falha de asset preserva a carta | verde: tabela | jornada protegida: reversão antes do callback com pixels reais; âncora/geometria preservadas sem asset | pendências: R04 (saltos, VoiceOver, pressão de memória) | SHA final: registrado no commit `fix(runtime): preserve ready pixels across reverse exposure`.

## R04 — histórico, saltos e pressão de memória com transição segura

Base: `503c9ed1` (R03).

### Defeito

Um salto programático ou um movimento de VoiceOver aplicavam a posição direto no `scrollPosition`, mesmo quando o
destino estava admitido mas com o bitmap liberado: a superfície desenhava o slot vazio até o callback chegar. E não
havia caminho para a pressão de memória soltar a banda anterior protegida por R03, porque a residência só mudava por
observação.

### Prova vermelha (mutação)

| Mutação | Teste | Resultado |
|---|---|---|
| `FeedDestinationGate.readiness` responde `ready` sempre | `testProgrammaticJumpWaitsForReadyDestination` | **vermelho** (`ready` ≠ `needsPreparation`) |
| idem | `testVoiceOverNavigationNeverExposesReleasedPixels` | **vermelho** (`ready` sem pixels) |
| `trimResidencyForMemoryPressure` não libera nada | `testMemoryPressurePreservesCurrentReading` | **vermelho** (nada foi liberado) |

Mutações revertidas antes do commit.

### Alteração

- `FeedDestinationGate` (Runtime, decisão pura): `ready` só para carta admitida com pixels (ou texto);
  `needsPreparation` para bitmap liberado; `notAdmitted` para fora da janela; e
  `readinessAfterPreparation` devolve `unavailableAfterPreparation` quando o destino sumiu do valor preparado.
- Superfície nativa (`FeedNativeViewport`): o setter de `scrollPosition` (o caminho de salto programático **e** de
  VoiceOver) passa pelo gate. Destino pronto aplica; bitmap liberado mantém a leitura atual, registra
  `capture.pendingJump` e pede a banda do destino por `store.submitViewport(..., reconciliation: true)` — uma
  reconciliação local, sem runway/aquisição; o `onChange` da janela aplica a posição quando o valor preparado está
  pronto, ou comunica indisponibilidade por toast sem reescrever publicação. O estado pendente mora em
  `FeedVisualCapture` (o `@State` existente), não em um segundo `@State` — a fence U14 do viewport segue intacta.
- `FeedSession.trimResidencyForMemoryPressure()`: sob pressão, mantém a banda do leitor e libera o resto (a banda
  anterior de R03 deixa de ser protegida). Identidade, ordem, âncora, geometria e payload durável não mudam; a
  segunda chamada sem nada a liberar devolve `false` e não republica.
- Host: `UIApplication.didReceiveMemoryWarningNotification` → `AppComposition.trimResidencyForMemoryPressure()` →
  associação instala o valor aparado (o store tem a própria cópia das cartas; sem instalar, os pixels não sairiam).

### Provas verdes

| Prova | Resultado | xcresult |
|---|---|---|
| `RenderReadyAdmissionTests` (8 casos, incl. salto, VoiceOver, pressão) | 8 / 0 | `swift test` |
| `FeedViewportCaptureTests` / `FeedScreenRenderingTests` (fences de UI) | 36 / 0, 18 / 0 | `swift test` |
| host `CompositionTests` + filtros + fronteira + jornada de imagem | 86 / 0 e 2 / 0 | `/tmp/fm-v2-r04-suite2.xcresult` |

**Limites declarados:** VoiceOver não é ligável por XCUITest; a regra foi provada no gate que a superfície consulta —
nenhum destino com bitmap liberado responde `ready` antes do preparo. A jornada Release com pressão de memória e
trace correlacionado fica para a candidata congelada (R23); bytes residentes são medidos em R22/R23.

### Registro R04

SHA inicial: `503c9ed1` | vermelho: tabela de mutações | alteração: gate de destino + preparo antes da posição + trim por pressão | verde: tabela | jornada protegida: salto/acessibilidade não expõem bitmap liberado; pressão preserva a leitura | pendências: jornada Release de pressão em R23 | SHA final: registrado no commit `fix(ui): gate historical navigation on ready presentation`.

## G1 — fechamento

Condições e onde foram provadas:

| Condição G1 | Prova |
|---|---|
| Ingresso limitado | R01: rajada de 300 com pendente limitado a 6 (mutação: 301); teste verde e host 84/0 |
| Instalação sem I/O | R02: pacote preparado instala com o seam de storage suspenso; mutações vermelhas |
| Prontidão anterior à exposição | R03: pixels do destino da reversão presentes no valor **antes** do callback (mutação: ausentes) |
| Nenhuma perda de âncora em reversão/salto/acessibilidade | R03 asset ausente preserva id/âncora/geometria; R04 salto espera o preparo; gate de VoiceOver |

### Suíte ampla e jornada Release (exigidas no fechamento do gate)

| Prova | Resultado | Evidência |
|---|---|---|
| `swift test` completo pós-R03/R04 | **1.450 testes, 3 ignorados, 0 falhas** (54,4 s) | saída do `swift test` |
| `ScrollAdmissionTests` (afirmava a liberação de pixels) | reconciliado ao contrato R03/R04 e verde (6/0) | `swift test --filter ScrollAdmissionTests` |
| jornada de imagem em Debug (`CardImageJourneyUITests`) | 2/0 | `/tmp/fm-v2-r04-suite2.xcresult` |
| jornada de imagem em **Release** (`-configuration Release`) | **NOT_RUN** | ver bloqueio abaixo |

Bloqueio medido da jornada Release: com `-configuration Release` o test action do scheme compila também
`FeedMineAppTests`, cujos fixtures dependem de símbolos `#if DEBUG` do app (`AddFeedFixtureSite`), e o build falha
antes de qualquer ensaio (`unable to resolve Swift module dependency` sem `ENABLE_TESTABILITY`, e
`cannot find 'AddFeedFixtureSite' in scope` com ele). Um scheme de UI-only em Release (ou a jornada pelo harness do
benchmark em R23) é o caminho; **NOT_RUN não é PASS**.

**G1 fechado contratualmente em 2026-10-17** com as suítes acima e a jornada Release explicitamente NOT_RUN. Não é
certificação de release: a candidata congelada, a jornada Release com pressão de memória e os ensaios físicos
continuam em R23/G4.

## R05 — slots de rede independentes do consumidor de resultados

Base: `a1e8f9cc`.

### Defeito

`AcquisitionCoordinator.executeConcurrently` fazia `try await onResult(result)` **antes** de `startMore()`. Um
callback editorial suspenso (o caso real: o consumidor do driver bloqueado enquanto processa A) prendia o bombeiro
de slots: C e D nunca iniciavam, apesar de a autorização e o plano já os permitirem. A conclusão durável existia,
mas a oportunidade de rede ficava parada atrás do consumidor.

### Prova vermelha

Restaurando literalmente a implementação anterior (HEAD do arquivo) e rodando só o caso novo:
`testBlockedResultConsumerDoesNotStopOtherEligibleTargets` → **4 asserções vermelhas** (C não iniciou, contagem 0;
D não iniciou, contagem 0) em 4,06 s. Com a implementação nova: 1 teste / 0 falhas em 0,106 s.

### Alteração

- `executeConcurrently` passa a rodar **dois filhos estruturados** do mesmo `withThrowingTaskGroup`:
  1. o **bombeiro de slots** (`settle`): janela deslizante de `concurrentTargetLimit`, registra cada resultado
     durável e o entrega a um `AsyncStream` **sem aguardar** o consumidor, reabrindo o slot imediatamente;
  2. o **consumidor serial**: drena o stream e aguarda `onResult` um por vez — nenhuma `Task` por resultado.
- O backlog do stream é limitado pelo próprio plano (`work.count`: no máximo um resultado por item planejado), não
  por um número arbitrário; um resultado cancelado para novos starts, erro fatal cancela os irmãos pelo grupo, e os
  resultados já duráveis permanecem contabilizados no relatório final, que mantém a **ordem do plano**
  (`SettledResults.ordered`).
- Single-flight/joins continuam em `execute`; o consumo não muda a contabilidade.

### Provas verdes

| Prova | Resultado |
|---|---|
| `swift test --filter AcquisitionCoordinatorTests` (31 casos + novo) | **38 / 0** |
| caso novo com consumidor suspenso | C e D iniciam antes da liberação; 4 notificações únicas; ordem final == plano |

Casos de erro fatal, cancelamento, joins e single-flight já cobertos pelos testes existentes da classe
(`test05/06` cancelamento, `test15/16` coalescência e join, `test07` erro de conector, `test28` falha de admissão
interrompe o próximo pull), executados na mesma corrida.

### Registro R05

SHA inicial: `a1e8f9cc` | vermelho: 4 asserções contra a implementação anterior | alteração: bombeiro e consumidor separados, backlog limitado pelo plano, ordem final preservada | verde: 38/0 | jornada protegida: consumidor suspenso não impede C/D | pendências: R06–R10 | SHA final: registrado no commit `fix(acquisition): decouple network slots from result consumption`.

## R06 — resultado durável publicado antes do fim da rodada

Base: `4c05c610` (R05).

### Defeito

`FeedRunwayDriver.executeAcquisition` aguardava a rodada inteira (`acquisitionCycle.run` → `executeConcurrently`
até o fim). Mesmo com a conclusão durável de A já admitida e notificada pelo consumidor, nenhum slice local era
executado enquanto B não respondesse: a fonte rápida ficava presa atrás do fim da rodada, não atrás da rede.

### Prova vermelha

Voltando o driver à implementação anterior (HEAD) e rodando o caso novo:
`testFastSourcePublishesWhileSlowSourceIsPending` → **vermelho** em 5,36 s (`XCTAssertFalse(publications.isEmpty)`:
nenhum recibo com B suspenso). Com o driver novo: 1 / 0 em 0,08 s.

### Alteração

- `RunwayAcquisitionCycle.start(...)` (novo) faz o mesmo planejamento/acknowledgement de `run`, mas entrega a
  rodada como um **stream de resultados duráveis** (`RunwayAcquisitionRound { results, completion }`), com backlog
  limitado pelo plano. A notificação `noteLocalSupplyChanged` continua sendo a existente e é dada por resultado.
- O driver consome o stream e retorna ao **mesmo loop de publicação** no primeiro resultado que mudou suprimento,
  sem esperar o resto da rodada; o slice local publica A. A rodada continua em segundo plano, e sua conclusão é
  observada (`observeBackgroundRound`): erro fatal é relançado na próxima oportunidade, nunca engolido. `deactivate`
  **não cancela** a rodada em voo: a aposentadoria encerra publicação e runway, não o trabalho de rede já autorizado
  — o supply durável ainda é admitido (contrato de R14/cycle) e a notificação tardia é ignorada pelo escopo limpo; a
  conclusão deixada para trás não é observada como oportunidade do driver (`noteBackgroundRoundSettled` ignora
  rodada que não pertence mais a ele).
- `run` permanece para os testes/contratos existentes. `settledAcquisition` fica nulo quando a publicação ocorreu
  antes do fim da rodada (o “fim da oferta” não é declarado a partir de uma rodada incompleta).

### Reconciliação de testes existentes

`ColdFeedBootstrapTests.testC19/C20` exigiam “a fonte rápida publica antes de o próximo alvo começar” — ordem que
dependia justamente do acoplamento removido em R05. O contrato preservado agora é: o plano é sequencial entre alvos
(A start/response antes de B start/response), há exatamente uma publicação inicial, e ela carrega só o que a fonte
rápida trouxe (snapshot de 1 carta; o suprimento da lenta é admitido depois). O teste do cold bootstrap novo confirma
que a edição fica durável com B suspenso.

### Provas verdes

| Prova | Resultado |
|---|---|
| `FeedRunwayDriverTests` (41 + 2 novos) | **43 / 0** (61,5 s) |
| `ColdFeedBootstrapTests` (38 + 1 novo) | **40 / 0** |
| `RunwayAcquisitionCycleTests` | **17 / 0** |
| novos: fonte rápida publica com lenta suspensa (driver e cold) | 1 / 0 cada |
| novo: resultado durável tardio não publica no escopo aposentado | 1 / 0 |

### Registro R06

SHA inicial: `4c05c610` | vermelho: caso do driver contra o driver anterior | alteração: rodada em stream + retorno ao loop no primeiro suprimento + monitor de conclusão + cancelamento na aposentadoria | verde: tabela | jornada protegida: A publica com B suspenso; escopo aposentado não recebe resultado tardio | pendências: R07 | SHA final: registrado no commit `fix(composition): publish durable results before round completion`.

## R07 — prontidão de mídia sem barreira para candidatos prontos

Base: `54aa08a0` (R06).

### Defeito

O driver aguardava `await prepareMedia(...)` (a `MediaPreparationOpportunity.prepare`) **antes** de executar cada
slice local, e o cold bootstrap aguardava a preparação da janela antes de examinar. Uma preparação lenta de um
candidato prendia a publicação de todos os candidatos prontos ao redor — exatamente a barreira que a seleção por
prontidão já tornava desnecessária (`SelectionReadinessSnapshot`).

### Prova vermelha

Mutação: trocar `opportunity.request(revisions)` por `await opportunity.prepare(revisions)` no driver, com a
preparação suspensa em um portão. `testReadyCandidatePublishesBeforeUnrelatedMediaCompletes` → **vermelho** em
2,38 s (nenhuma publicação com a preparação pendente). Com `request`: 1 / 0 em 0,08 s. Mutação revertida.

### Alteração

- `MediaPreparationOpportunity.request(_:)` (novo): declara a prioridade da janela que vem e retorna. A operação
  roda na tarefa do dono single-flight do prefetcher; o orçamento é o deadline fixo da oportunidade, nunca renovado
  por slice. `prepare(_:)` permanece para chamadores que precisam aguardar (contrato existente).
- Driver: o slice não depende mais da preparação — `request` quando há oportunidade (produto) e o closure legado
  (teste) mantém o `await` explícito. `nextEditorialRevisions` ainda alimenta a prioridade; a seleção continua
  lendo o **mesmo** índice de prontidão (`MediaReadiness`), então só oferta pronta/elegível publica, e uma imagem
  pendente nunca vira texto.
- Cold bootstrap: a prioridade é requisitada e o exame roda uma única vez sobre o que está pronto; os dois caminhos
  de `initialProductionSlice.run` viraram um (a fence estática do arquivo foi atualizada de 2 para 1 chamada — menos
  caminhos, não mais).
- A transição individual de prontidão continua acordando `noteMediaReadinessChanged` → `noteLocalSupplyChanged` →
  reconsideração existente; nenhum polling/varredura de pendentes foi criado.

### Cobertura de reconsideração e falha

Os casos `testLateReadyCandidateIsReconsideredOnce` e `testReadinessFailureDoesNotCreateRetrySpin` já existem como
contratos verdes nas classes dos donos e foram executados nesta tarefa:
`LocalProductionSliceTests.testReadinessTransitionSchedulesTheDriveThatPublishesPendingMedia` e
`testF06PendingHeadAdvancesAcrossWindowsAndRecoversThroughExistingRunway` (candidato tardio reconsiderado pelo
caminho existente), e `MediaPrefetcherTests.testAllCandidatesFailingHasNoPresentationAndIsNotRetried` /
`testTransientFailureRetriesLaterDefinitiveSettles` (falha definitiva não vira retry; transitória tem backoff).

### Provas verdes

| Prova | Resultado |
|---|---|
| `FeedRunwayDriverTests` (43 + 1 novo) | 44 / 0 |
| `ColdFeedBootstrapTests` | 40 / 0 (fence estática atualizada e verde) |
| `LocalProductionSliceTests` | 19 / 0 |
| `MediaPrefetcherTests` | 7 / 0 |

### Registro R07

SHA inicial: `54aa08a0` | vermelho: mutação prepare-before-slice | alteração: prioridade sem barreira no driver e no cold; um caminho de exame | verde: tabela | jornada protegida: prontos publicam com decode alheio pendente; tardio reconsiderado; falha não gira | pendências: R08 | SHA final: registrado no commit `fix(media): publish ready supply without preparation barriers`.

## R08 — descoberta indexada e seções críticas limitadas

Base: `81941d17` (R07).

### Defeito

`ReaderDiscoveryTraversal` varria **todas as páginas** para cada checagem de duplicado (`Set(pages.flatMap...)`),
reconstruía a lista de entradas a cada leitura e executava a página do catálogo e a materialização (SQL/autoridade)
**sob o lock**. Não havia reserva: duas oportunidades podiam materializar a mesma página, e uma promoção de catálogo
durante a materialização podia instalar alvos de um catálogo superado.

### Prova vermelha (mutação)

| Mutação | Teste | Resultado |
|---|---|---|
| remover `!advancing` da reserva | `testAReservedMaterializationRefusesAConcurrentAdvance` | **vermelho**: 2 materializações, a concorrente devolveu página |
| remover a revalidação da identidade **viva** | `testCatalogueRevocationDuringMaterializationCannotReinstallTarget` | **vermelho**: página do catálogo superado instalada |

Mutações revertidas.

### Alteração

- Índices derivados da travessia (`knownTargetIDs`, `entryByTarget`, `flattenedEntries`), atualizados na instalação
  válida de página (`install(entries:snapshot:)`) e reconstruídos só na promoção (`rebuildIndices`). Toda checagem
  de duplicado e o lookup de conector que lê `entries` são O(1)/sem varredura; `adopt` e `advance` usam o índice.
  `connector(for:using:)` resolve por `snapshotByTarget` (a página que materializou o alvo), removendo o último
  `for page in pages` linear do arquivo — ver o commit de correção abaixo.
- **Reserva de oportunidade**: um `advancing` por travessia; uma segunda oportunidade durante a materialização
  devolve `nil` (nada é duplicado). O `builder.page(...)` e a materialização rodam **fora** do lock; a instalação
  re-locka e exige `cursor` inalterado e a **identidade viva** do catálogo igual à reservada. Identidade mudou →
  página descartada, cursor intacto, `catalogueFingerprint` adotado para a próxima tentativa; exceção/cancelamento
  libera a reserva sem avançar. A promoção continua chamando `refreshIfNeeded` (rebind de páginas retidas).
- Seam mínimo: `catalogueIdentity` (default: `installation.activeFingerprint()`), a identidade que a reserva compara —
  o teste determina a promoção/revogação sem construir um segundo catálogo.

### Provas verdes

| Prova | Resultado |
|---|---|
| `ReaderDiscoveryTraversalTests` (novo: lookup indexado, reserva concorrente, falha preserva cursor, identidade superada) | 4 / 0 |
| `ReaderDiscoveryPoolTests` (regressões de travessia/eligibility/progressão) | 19 / 0 |
| `SyndicationAcquisitionSnapshotTests` | 30 / 0 |

### Registro R08

SHA inicial: `81941d17` | vermelho: tabela | alteração: índices + reserva + materialização fora do lock + revalidação de identidade | verde: tabela | jornada protegida: nenhum alvo revogado/superado readmitido; concorrência não duplica; falha não avança | pendências: R09 | SHA final: registrado no commit `perf(discovery): index targets and bound traversal critical sections`.

### Correção pós-revisão (R08)

A revisão apontou que `connector(for:using:)` ainda fazia `for page in pages where page.entries.contains(...)`.
Corrigido: `snapshotByTarget` é mantido por `install`/`rebuildIndices` e o lookup resolve em O(1)
(`snapshotByTarget[target.id]?.connector(...)`). Provas: `ReaderDiscoveryTraversalTests` 4/0 e
`ReaderDiscoveryPoolTests` 19/0 na correção.

## R09 — orçamentos adaptativos por estágio

Base: `5dcba807` (R08).

### Defeito

Os recursos de uma oportunidade eram constantes no host (`examinedCandidateCapacity: 32`, plano de 48), sem relação
com pressão medida. Termal, modo de baixa energia, rede restrita e volume quase cheio não reduziam trabalho; e não
havia um lugar único que declarasse como os fatos medidos viram autorização.

### Prova vermelha (mutação)

`StageBudgetPolicy.budget` devolvendo sempre o bootstrap (pressão ignorada) →
`testPressureReducesWorkWithoutStarvingEligibleTargets` **vermelho** (2 asserções: sério e crítico iguais a 48).
Mutação revertida.

### Alteração

- `StageBudgetPolicy` (novo, puro): `StagePressureFacts { thermal, lowPowerMode, networkConstrained,
  freeStorageBytes }` (todos medidos; ausência = bootstrap) → `StageBudget { acquisition, examinedCandidateCapacity,
  localWorkAllowed }`. Bootstrap documentado preservado: 48 planejados / 8 sockets (no coordenador) / 32 examinados /
  1 MB. Reduções: termal `fair` → plano/2 e 16 examinados; `serious` → ≤8, 12, 500 KB; `critical` → 1, 8, 250 KB;
  baixa energia ≤8; rede restrita/expensiva/indisponível → plano/2 e ≤500 KB; volume < 100 MB → ≤500 KB. O plano
  **nunca** cai abaixo de 1 alvo elegível e `localWorkAllowed` permanece verdadeiro: pressão reduz trabalho
  deferível, não desliga a leitura local nem zera a autorização.
- `FeedAssociation.resources` passa a usar a política com os fatos que a plataforma declara agora
  (`ProcessInfo.thermalState`, `isLowPowerModeEnabled`, `NetworkPathObserver.shared.current`, capacidade livre do
  volume). Sem fato medido → bootstrap. Nenhuma latência/CPU é inventada: utilização de CPU não é amostrada e, por
  isso, não participa.
- 10 s (cadência foreground) e 2000 (guarda de cartas) continuam limites operacionais, agora afirmados por teste.

### Provas verdes

| Prova | Resultado |
|---|---|
| `PipelineHeadroomTests` (novo: recursos↑ trabalho útil↑, pressão reduz sem inanição, oferta vazia espera fatos, limites operacionais) | 4 / 0 |
| host `CompositionTests` (a montagem do host com a política nova) | ver abaixo |

### Registro R09

SHA inicial: `5dcba807` | vermelho: mutação pressão-ignorada | alteração: política pura + fatos medidos no host | verde: tabela | jornada protegida: bootstrap 48/8/32/1 MB; pressão só reduz; um elegível progride | pendências: R10 | SHA final: registrado no commit `perf(runtime): adapt stage budgets to demand and measured resources`.

## R10 — transações curtas sem perder atomicidade (fechamento T6)

Base: `5dcba807` (R08) + R09.

### Medição antes de alterar

Ensaio novo `PipelineHeadroomTests.testConcurrentDurableStagesPreserveWriterConsistency`: admissão
(`AdmissionPolicy.admit`) e publicação (`PublicationStore.appendSegment`) concorrentes no **mesmo** banco, sob o
escritor serial. Medido nesta máquina: **0,0027 s** para os dois estágios combinados. Não há trabalho síncrono caro
dentro das transações que justifique mover código; a decisão registrada é **nenhuma alteração de produção** (o plano
admite esse desfecho), e as fences existentes permanecem.

### Prova de atomicidade (regressões existentes executadas)

| Contrato | Prova | Resultado |
|---|---|---|
| falha de admissão desfaz supply e checkpoint | `AvailabilityPrecedenceTests.testA14A15AvailabilityAndCheckpointRollbackOnStructuralFailure` (+ classe) | 7 / 0 |
| falha de publicação não deixa segmento parcial | `PublicationStoreTests.testAppendRejectsPersistedMalformedTailAtomically` etc. (+ classe) | 17 / 0 |
| conflitos de revisão/mídia desfazem a escrita | `ContentStoreTests` (incl. `testIdentityRevisionAndVersionConflictsRollback`) | 12 / 0 |
| consistência dos dois estágios concorrentes + duração medida | `PipelineHeadroomTests` | 5 / 0 |

O ensaio afirma: segmento concorrente inteiro (2 segmentos, carta presente), admissão sem rejeições e supply
completo, e uma guarda operacional de 5 s (não um alvo de desempenho).

### Registro R10

SHA inicial: `5dcba807` | vermelho: não aplicável (nenhum defeito reproduzido; medição feita antes de alterar) |
alteração: nenhuma em produção; ensaio de contenção adicionado | verde: tabela | jornada protegida: atomicidade de admissão/publicação e consistência do escritor | pendências: G2 | SHA final: no commit que reúne R09/R10.

## R11 — A→B→A, prioridades e confirmação durável

Base: `f4224ebf` (R09/R10).

### Alteração (provas de contrato, sem mecanismo novo)

- **A→B→A sob carga** (`CompositionTests.testContextSwitchUnderLoadReusesCanonicalWork`): com a fonte de ciência
  suspensa e uma resposta diferente chegando, a ida A→B→A volta à **mesma edição canônica** e à **mesma posição
  prometida** (checkpoint), sem uma publicação nova para repetir bytes já válidos. Não há aquisição geração nova
  nem âncora inventada.
- **Confirmação durável + relaunch** (`FilterConfirmationBoundaryTests.testFilterPresentationFailureKeepsTheSelection
  ConfirmedAndRecoverable`, estendido): os quatro testes de confirmação continuam verdes; depois de a apresentação
  falhar (trigger real de SQLite no checkpoint), a seleção confirmada é durável, e uma **nova composição** no mesmo
  diretório apresenta o mesmo contexto e o mesmo filtro (`pt` + `fun`), com a associação ativa.
- **Recibo tardio na fronteira de instalação**: a fence do destinatário provada em R00
  (`testAReceiptForASupersededEditionDoesNotGrowTheCurrentEditionsWindow` + mutação que a remove) é a prova de que um
  recibo de edição superada não admite na vigente — instalado ou entregue depois.
- **Leitor parado sem esperar cadência**: o crescimento por recibo (R00) e a espera por fatos (R09,
  `testExhaustedSupplyWaitsForNewFacts`) cobrem os dois lados: publicação concluída cresce a janela na hora; sem
  fato novo, nada gira e a cadência de 10 s não é necessária para progresso causal.
- Nenhuma prioridade nova/cancelamento novo foi criado: os owners atuais (contexto/edição/revisão/proveniência e o
  runway) continuam autorizando; trabalho sem utilidade já é cancelado pela aposentadoria (R06).

### Provas verdes

| Prova | Resultado | xcresult |
|---|---|---|
| `testContextSwitchUnderLoadReusesCanonicalWork` | 1 / 0 (61,5 s, fonte retida) | `/tmp/fm-v2-r11b.xcresult` |
| `FilterConfirmationBoundaryTests` (4, incl. relaunch) | 4 / 0 | `/tmp/fm-v2-r11c.xcresult` |
| `testFilterPresentationFailureKeepsTheSelectionConfirmedAndRecoverable` isolado | 1 / 0 | `/tmp/fm-v2-r11d.xcresult` |
| pacote completo (antes de R11) | 1464 / 3 ignorados / 0 falhas | — |

**Limite:** background/offline foram exercitados no pacote e no host em R01/R04; uma jornada física A→B→A em
Release fica para a candidata de R23.

### Registro R11

SHA inicial: `f4224ebf` | vermelho: não aplicável (contratos já verdes; prova de reuso nova) | alteração: testes de
reuso A→B→A e de relaunch pós-falha | verde: tabela | jornada protegida: edição/posição canônicas reusadas; filtro
confirmado durável | pendências: R12 | SHA final: registrado no commit `fix(context): preserve reusable work and
durable scope transitions`.

## G2 — fechamento

| Condição G2 | Prova |
|---|---|
| Conclusões individuais alimentam publicação | R06: drvier publica A com B suspenso (também no cold bootstrap) |
| HTTP/mídia pendentes não barram prontos | R05 (slots independentes do consumidor), R07 (prioridade de mídia sem barreira) |
| Descoberta com custo limitado | R08: índices O(1), materialização fora do lock, reserva e revalidação de identidade |
| Recursos com custo limitado e adaptativo | R09: bootstrap 48/8/32/1 MB; pressão só reduz, nunca a zero; limites operacionais afirmados |
| Transações duráveis atômicas e curtas | R10: medição 0,0027 s; rollbacks existentes verdes; nenhuma alteração necessária |

Suítes no fechamento: pacote completo **1464 / 0** e host `CompositionTests` 78 – 0 (R09), com os conjuntos de R05–R10
acima. **G2 fechado contratualmente em 2026-10-17**; certificação de release continua em R23/G4.

## R12 — salvos, retenção e recuperação offline

Base: `f0a9257b` (R11).

### Alteração e provas

- Novo `SavedMediaCoordinatorTests.testSavedContentSurvivesRelaunchAndDisposableCachePurge`:
  salva e conclui a preparação (ready = bytes duráveis), remove o asset de uma ocorrência **não salva** (cache
  descartável) e mantém o da salva; reabre com um **novo handle de banco** e um coordinator cujo transporte falha e
  cujo path está `unavailable`. Resultado: `prepareSavedMedia` devolve `.ready` sem nenhuma busca (`calls == 0`), a
  disponibilidade persistida diz offline, o texto e a ação congelada vêm do banco de publicação, o bookmark continua
  durável e o decoder lê o bitmap. Link não vira corpo completo baixado: o que é prometido é o que existe.
- Cobertura já existente executada nesta tarefa (contratos de R12 sem mecanismo novo):
  `SavedMediaCoordinatorTests` (evicção/re-preparo, falha honesta, disco cheio preserva o salvo, resume, texto nunca
  ganha mídia), `SavedMediaAvailabilityStoreTests` (limpar um box mantém a carta do outro; tentativas/limite),
  `MediaTidyFactsTests` (retenção protege visível/salvo).

### Reconciliação descoberta na verificação

`ReadingCompositionTests.testAStillRenderedCardOpensAfterCanonicalPruningButAStaleOwnerCannot` estava **vermelho na
candidata** herdada: com `keepsAdmittedHead: true` (decisão do dono, 2026-10-13), o topo admitido nunca é podado, e a
premissa "canonical pruning" não é alcançável nessa configuração. O teste foi reconciliado ao contrato real: o topo
mantido continua admitido, a carta do rendering retido abre, e um owner aposentado não abre. Não é conserto de
produto; a classe passou a ser exercitada nesta tarefa.

### Provas verdes

| Prova | Resultado |
|---|---|
| `SavedMediaCoordinatorTests` (6 + novo) | 7 / 0 |
| `SavedMediaAvailabilityStoreTests` | 3 / 0 |
| `MediaTidyFactsTests` | 1 / 0 |
| host `ReadingCompositionTests` | verde integral (`/tmp/fm-v2-r12-host3.xcresult`) |

**Limite:** a jornada offline em aparelho físico continua em R23; aqui o "relaunch" é um novo handle de banco no
mesmo processo, com transporte indisponível — o que é o que o teste de unidade pode provar.

### Registro R12

SHA inicial: `f0a9257b` | vermelho: nenhum defeito de salvos reproduzido (cobertura existente verde); uma premissa de
teste herdada reconciliada | alteração: teste de relaunch/purge; premissa de pruning corrigida | verde: tabela |
jornada protegida: salvos sobrevivem a relaunch/purge e leem offline; retenção protege visível/salvo | pendências:
R13 | SHA final: registrado no commit `fix(library): complete saved-content durability and offline recovery`.

## R13 — neutralidade, namespaces e combinações de mídia

Base: `9ee4480b` (R12).

### Defeitos

1. `ReaderDiscoveryProfile.init(recipe:)` tratava toda resposta de assunto que não era `.more` como **exclusão**
   (`if level == .more ... else excluded`): voltar um assunto para **Normal** continuava escondendo-o.
2. As respostas editoriais (`media:`, `nature:`) eram dobradas em `excludedTopicNodeKeys` — namespaces diferentes
   colidiam: uma resposta editorial podia excluir um "nó de assunto" que nunca foi assunto.
3. Uma receita com **duas** mídias resolvia `contentTypeCriterion` para `.all` e o `ReaderFilter` não carregava o
   conjunto: par == todos, contra a semântica declarada.

### Prova vermelha (mutação)

| Mutação | Teste | Resultado |
|---|---|---|
| `.neutral` volta a entrar em `excluded` | `testNeutralPreferenceDoesNotExcludePersistedTopic` | **vermelho** (2 asserções) |
| chave editorial volta a virar nó de assunto | `testEditorialAndTopicKeysDoNotCollide` | **vermelho** |
| resolução descarta o conjunto de mídia | `testEveryMediaSelectionCombinationReachesTheFilterUnchanged` | **vermelho** (6 seleções) |

Mutações revertidas.

### Alteração

- `.neutral` não interessa nem exclui; o ciclo `more → less → neutral` deixa de carregar exclusão velha.
- Só uma resposta editorial **com chave de assunto** (`topic:`) exclui um assunto; `media:`/`nature:` continuam
  pesos na ordenação.
- `ReaderFilter` ganha `mediaTypes` (o par exato). **Identidade legada preservada:** um tipo único é exatamente a
  lente `contentType` e todos os três é "sem critério"; ambos não acrescentam componente de mídia ao
  `identityText` (a resolução só passa o conjunto para **pares**). Um filtro decodificado da forma antiga mantém o
  mesmo `identityText` — o checkpoint persiste (correção da revisão desta tarefa). O par, que antes virava `.all`,
  agora tem identidade própria; `activeCriteria`/`removing(.contentType)` limpam os dois.
- `FeedRecipeResolution.filter` e o draft do sheet carregam o conjunto; encode omite a chave quando não há par.

### Provas verdes

| Prova | Resultado |
|---|---|
| `ReaderDiscoveryPoolTests` (incl. neutral/namespace) | 21 / 0 |
| `FeedRecipeDefinitionTests` (todas as 7 seleções não vazias + legado/round-trip) | 10 / 0 |
| `FeedRecipeResolutionTests` | 8 / 0 |
| `ReaderFilterTests` | 11 / 0 |
| `ReaderFilterEligibilityTests` | 7 / 0 |

### Registro R13

SHA inicial: `9ee4480b` | vermelho: tabela | alteração: neutral não exclui; namespaces separados; par de mídia
carregado com identidade legada intacta | verde: tabela | jornada protegida: round-trip de persistência e
elegibilidade correspondem exatamente às escolhas | pendências: R14 | SHA final: registrado no commit
`fix(preferences): preserve neutrality and exact media selections`.

## R14 — expressão de busca única e compatibilidade persistida

Base: `70ca6e89` (R13).

### Defeito

A busca era uma **substring literal única** sobre título ou resumo (`CandidateProvider`), e `SearchContext` não
distinguia a gramática de uma consulta antiga. Não havia expressão compartilhada entre domínio/provider/UI; termos
positivos separados, exclusão com `-` e hífen interno não tinham contrato.

### Prova vermelha (mutação)

| Mutação | Testes | Resultado |
|---|---|---|
| `matches` volta a usar a consulta inteira como literal | `testPositivesMayLiveInDifferentFieldsAndAnExclusionAnywhereFails` (+ literal) | **vermelho** |
| decodificação sem marcador assume `.termsV1` | `testLegacyLiteralKeepsItsMeaningBytesAndIdentity` | **vermelho** (7 asserções: semântica, expressão, identidade, bytes, igualdade) |

Mutações revertidas.

### Alteração

- `SearchExpression` (novo, Domain): a gramática aprovada e só ela — termos separados por espaço, `-` inicial
  exclui, hífen interno é parte do termo, `-` isolado não é termo, caixa/diacríticos não distinguem, positivos podem
  casar em campos diferentes (título + resumo), excluído em qualquer campo derruba, só negativos não inicia busca.
  Nenhum operador novo.
- `SearchSemantics` (`legacyLiteral`/`termsV1`) em `SearchContext`: ausência do marcador decodifica como legado; nova
  consulta grava `termsV1`; a codificação do legado **omite** o marcador, preservando representação/identidade
  anterior; semântica participa de igualdade/hash e da identidade do contexto (`search:` × `search:terms-v1:`).
  Consulta legada nunca é reinterpretada pela gramática; só negativos legados continuam decodificando.
- `CandidateProvider` e a resolução/UI consomem a mesma expressão; o literal antigo continua sendo uma substring
  única (mesmo `en_US_POSIX` case/diacritic-insensitive).
- `ContextIdentityTests` reconciliado: a consulta corrente declara a gramática; a forma legada mantém
  `search:<texto>` e a identidade antiga.

### Provas verdes

| Prova | Resultado |
|---|---|
| `SearchExpressionTests` (novo; todos os casos do plano + exemplo discriminante + legado/round-trip) | 4 / 0 |
| `CandidateProviderTests` (incl. exemplo título/resumo/exclusão e literal legado) | 21 / 0 |
| `ContextIdentityTests` (legado preservado) | 7 / 0 |
| `ContextTests` / `ReaderPreferencesStoreTests` / `ReaderLibraryStoreTests` / `LegacyUserStateImportTests` / `PublicationPersistenceMappingTests` | 8 / 8 / 12 / 3 / 3, zero falhas |

### Registro R14

SHA inicial: `70ca6e89` | vermelho: tabela | alteração: expressão compartilhada + semântica versionada + legado intacto | verde: tabela | jornada protegida: fixtures legados preservam significado; UI/provider usam a mesma expressão | pendências: R15 | SHA final: registrado no commit `feat(search): share query expressions with explicit legacy compatibility`.

### Correção pós-revisão (R14)

A revisão apontou que três caminhos que reconstroem busca a partir de **texto** ainda criavam `.termsV1`:
`PublicationStore+Coding.decodeEdition` (linha achatada), `RuntimeMigrations` (linhas antigas) e
`LegacyUserStateImport` (query V1). Todos passaram a construir `.legacyLiteral`. Provas: novo
`PublicationStoreTests.testAFlattenedSearchEditionDecodesAsLegacyLiteral` (linha sem `context_key_json`, query
`-astrologia`, decodifica como literal com `search:-astrologia`) e
`LegacyUserStateImportTests.testImportCarriesBoxesCollectionsAndSmartFeedsOnce` (preset importado como literal).
`PublicationPersistenceMappingTests` continua verde (a identidade completa viaja no `EditionRecord`).

## R15 — cancelar/retornar busca e erros de ação recuperáveis

Base: `67763988` (R14).

### Defeito

`submitSearch` fazia `Task { try? await selectContext(.search(...)) }`: **todos** os desfechos eram engolidos
(nada gravado, gravado sem apresentar, ativo) e a UI não distinguia nenhum. Cancelar a busca só limpava o campo do
store: o host não restaurava a origem, então o leitor ficava no contexto de busca (ou num feed errado).

### Prova vermelha (mutação)

| Mutação | Testes | Resultado |
|---|---|---|
| `submitSearch` volta a `try?` e não lança | `testSavedSearchFailureDistinguishesWriteFromActivation` | **vermelho** (não lançou; chave mudou) |
| `cancelSearch` vira no-op | `testCancelSearchRestoresExactPreviousContextAndAnchor` | **vermelho** (contexto, edição e âncora não voltam) |

Mutações revertidas.

### Alteração

- `AppComposition.searchOrigin`: a origem completa (ContextKey com preset/filtro/scope) do último search. A posição
  prometida é o **checkpoint da própria origem**, escrito quando o `replaceSession` da busca aposenta a associação
  anterior; nenhum estado novo de posição.
- `submitSearch` (agora `async throws`) faz a fronteira de confirmação: persiste a chave; só então troca memória e
  reconstrói a sessão. `ReaderSearchFailure { unusableQuery, notStored, storedNotActivated }` distingue as metades, e
  a UI mostra mensagens diferentes (termo ausente / não salvou / salvou mas não abriu).
- `cancelSearch` restaura a origem inteira por `replaceSession` (a busca é checkpointada antes de sair); falha ao
  restaurar mantém a busca e informa, sem inventar destino. Duplo cancelar é no-op.
- O store ganhou `onCancelSearch` (intenção repassada; a fence S11 foi atualizada com o novo label); a associação
  encaminha, o host executa.
- Retornar de um artigo não troca o contexto da busca: `testReturningFromArticleRestoresSearch` afirma contexto e
  âncora inalterados.

### Provas verdes

| Prova | Resultado |
|---|---|
| os três casos novos (cancelar restaura; falhas distinguem; artigo preserva a busca) | 3 / 0 |
| `FeedScreenStoreTests` (fence S11 atualizada) | 18 / 0 |
| `FilterConfirmationBoundaryTests` (fronteira irmã) | 4 / 0 (R11) |

**Limite:** uma jornada UI busca→artigo→voltar→cancelar em Release fica em R23; aqui a navegação é a de composição
(abrir leitura não muda contexto nem posição).

### Registro R15

SHA inicial: `67763988` | vermelho: tabela | alteração: origem+checkpoint, confirmação explícita, cancelar restaura | verde: tabela | jornada protegida: identidade/posição restauradas; mensagem compatível com o commit | pendências: R16 | SHA final: registrado no commit `fix(search): restore search origins and report durable action outcomes`.

## R16 — escopos e resultados locais unificados (parcial)

Base: `c39cfd13` (R15).

### Entregue e provado

- Tipos de resultado no **Domain** (`ReaderSearchResults`: query, scope, token de conclusão, seções
  sources/saved/articles; `ReaderSearchResult` com `destination` tipada). Compartilhados pelo host e pela UI, sem
  cópia de dados canônicos.
- `AppComposition.unifiedSearch(_:scope:token:)` consulta as autoridades reais e **só locais** (sem rede):
  fontes pelo catálogo (`LegacyCatalogReader.matchingSources` + a expressão de R14), salvos pelos bookmarks + cartas
  publicadas, artigos pelo `ContentStore` + resolução em lote de cartas publicadas (`PublicationStore.cardIDs`,
  uma consulta). Escopo decide o universo: `.sources` só fontes; `.contents` salvos + artigos; `.both` os três.
- `ReaderSearchResultsStore` (UI): token de início; uma conclusão só é aplicada sob o token mais novo — uma busca
  suspensa não substitui a nova.
- Provas: `testSearchScopesReturnOnlyTheirRealResultKinds` (tipos reais por escopo; salvo abre a ocorrência real),
  `testStaleSearchCompletionCannotReplaceNewScope`, `testSavedSearchReopensWithSameExpressionAndScopeOffline`
  (chave durável round-trip com expressão+escopo; busca local sem nenhuma requisição). 3 / 0.

### Pendente (bloqueia R16/G3)

A **superfície de resultados** na barra do leitor não foi construída nesta execução: o submit atual continua
trocando o contexto para a busca do feed, e não há lista tipada com navegação (fonte→contexto, salvo→leitura,
artigo→leitura) nem testes de troca de termo/escopo durante consultas suspensas em UI. O backbone acima é o que a
superfície consumiria; sem ela, a busca unificada **não está certificada** por F11/F16.

**Registro parcial:** SHA inicial `c39cfd13` | alteração: tipos + consultas reais + store com token | verde: 3/0 |
pendências: superfície e jornada F11/F16 | SHA final: registrado no commit `feat(search): connect explicit scopes to
local result authorities` (parcial, declarado).

## R17 — diversidade multidimensional nas emendas de segmentos (parcial)

Base: `031c2dea` (R16).

### Entregue e provado

- `EditorialDiversityFact` (Domain): os fatos pequenos congelados de uma publicação — fontes, provedor e os
  **assuntos declarados pela própria história**. Geografia/formato não existem neste build e permanecem
  desconhecidos (nada é inventado da categoria da fonte).
- `SelectionDiversityContext` (Editorial): janela recente; comparação **por dimensão**, apenas quando **ambos** os
  candidatos conhecem a dimensão. Dimensão ausente é pulada: metadado faltante não inventa novidade nem repetição.
- `SelectionEngine.select(..., diversity:)`: desempate após peso (relevância) e antes de recência/tie-breakers.
  **Versão explícita:** só `sequencingPolicyVersion >= 5` aplica diversidade; versões 1–4 restauradas mantêm a ordem
  exata; versão desconhecida não ganha comportamento novo. Ofertas homogêneas continuam publicáveis (reordena, nunca
  retém).
- Provas: `SelectionDiversityTests` (3/0) — dimensões conhecidas na emenda, versão 4 inalterada, homogênea
  publicável, metadado ausente neutro. Mutação (remover o gate de versão) → **vermelho**. Regressões:
  `SelectionEngineTests` 22/0, `SourceDiversityContractTests` 14/0, caracterizações 11/0, weighted 3/0.

### Pendente (bloqueia R17/B02)

- Persistir os fatos no **owner de publicação**, na mesma transação do segmento (coluna/JSON versionado), com
  histórico antigo = desconhecido.
- A composição criar uma revisão com sequencing **5** e o `LocalProductionSlice` passar o contexto lido do histórico
  publicado. Enquanto isso, a diversidade está implementada e testada como decisão pura, mas **dormente** em produção
  (nenhum chamador passa contexto numa revisão v5) — B02 não executado.

**Registro parcial:** SHA inicial `031c2dea` | vermelho: gate de versão removido | verde: 3/0 + regressões | pendências:
persistência/fiação B02 | SHA final: registrado no commit `feat(editorial): maintain factual diversity across
publication seams` (parcial, declarado).
