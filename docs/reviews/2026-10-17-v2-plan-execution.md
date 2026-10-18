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
