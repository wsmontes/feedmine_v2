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
residente é medida em R04/R22, não neste registro. A jornada de imagem rodou em Debug; a variante Release fica
para o fechamento de G1.

### Registro R03

SHA inicial: `a4a1b3af` | vermelho: tabela de mutações | alteração: banda anterior protegida + falha de asset preserva a carta | verde: tabela | jornada protegida: reversão antes do callback com pixels reais; âncora/geometria preservadas sem asset | pendências: R04 (saltos, VoiceOver, pressão de memória) | SHA final: registrado no commit `fix(runtime): preserve ready pixels across reverse exposure`.
