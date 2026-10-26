# S1/F12 — correções da revisão de autoridade e UX12-A/D executados

> **Este documento prevalece sobre o §7 de `2026-10-26-f12-s1-visit-acquisition.md`** nos pontos de UX12-A e
> UX12-D: aquela seção registrava ambas as jornadas como não executadas, e as duas foram executadas aqui (UI real,
> com evidência em `.xcresult`). O texto antigo permanece como registro daquela rodada; as notas de correção foram
> acrescentadas lá apontando para cá.

Base: `d199553b` (árvore limpa salvo `capacity-ready.json`). Rodada de 2026-10-26, um executor, sem push/merge.
Escopo: os defeitos D1–D3 e as hipóteses H1/H3/H5 de `/tmp/feedmine-s1-f12-authority-review.md`, revalidados
contra o texto real de INV-11/12 (`docs/architecture/PRODUCT_INVARIANTS.md:124/:132`) e o código em HEAD; depois
UX12-A e UX12-D em UI real. Nada foi alterado em `bench/**`, oráculo congelado, driver, `criteria.json`,
`capacity-ready.json` ou corpus.

## 1. D1 — `.visit` podia admitir com alvo durável revogado

**Defeito (confirmado em HEAD).** `AcquisitionAdmissionStore.admit` no `case .visit` usava `connectorKind` e
`authorizedSources` do chamador (`AuthorityStamp` é público) sem ler a linha durável. A regra "linha durável sempre
vence, inclusive `revoked`" existia só no ledger/snapshot/coordenador. No app o stamp vinha do ledger (correto),
mas a garantia do store não existia.

**Correção.** `AcquisitionAdmissionStore.admit` (`.visit`) lê `AcquisitionTargetStore.readTarget(id:in:)` **dentro
da mesma transação de escrita** e lança `durableTargetExists` se qualquer linha existir (`enabled` ou `revoked`).
Um segundo guard recusa `.visit` sem fontes (`visitAuthorityWithoutSources`), fechando o caso (b) do D3 na origem.

**Regressão causal (medida).** `Tests/FeedMinePersistenceTests/TransientAdmissionTests.swift`:
`testVisitIsRefusedForEnabledAndRevokedDurableRowsAndWritesNothing` (linha enabled → lança; `revoke` → lança;
controle `.durable` continua lançando `targetRevoked`; nenhuma escrita canônica) e
`testVisitAuthorityWithoutSourcesIsRefused`. **Red medido** com os dois guards removidos: 5 testes falham
(`/tmp/s1-red.log`, exit 1). **Green com os guards**: 5/5 PASS (`/tmp/s1-green.log`, exit 0).

## 2. D3 — `?? []` na revogação entre leituras e mistura de origem

**Defeito.** `AcquisitionCoordinator.run` lia alvo (`:424`) e fontes (`:432`) em duas leituras independentes;
`authorizedSources(...) ?? []` transformava aposentadoria em licença vazia: batch com memberships → erro fatal
(irmãos cancelados), batch sem memberships → admitido sob arming inexistente.

**Correção (menor solução correta).**
- `VisitTargetAuthority.authority(id:)` — alvo e fontes na **mesma aquisição de lock**.
- `AcquisitionTargetStore.authority(id:)` e `AcquisitionTargetAuthority.authority(id:)` — alvo e fontes na
  **mesma transação de leitura**; nil é "sem linha durável".
- `AcquisitionTargetLedger.authority(id:)` — durável primeiro, visita só na ausência, devolvendo
  `(target, origin, sources)` de uma vez.
- Coordenador: `guard ... revalidated.origin == .visit ... let sources = revalidated.sources else { return
  result(.cancelled) }`. `?? []` removido; aposentadoria é `.cancelled`, nunca exceção.

**Barreira medida.** `testRevocationHeldDuringThePullCancelsWithoutAdmittingOrPullingAgain`: o connector segura o
pull (`BarrierConnector`), o teste revoga, libera. Resultado: `stop == .cancelled`, `receipts.isEmpty`,
`pulls == 1` (nenhum request depois de `revokeAll`), 0 registros canônicos. Não há rollback afirmado — o que a
barreira prova é que nada nasce depois da aposentadoria. A janela intra-bloco (linha durável nasce entre a leitura
e a escrita) é fechada estruturalmente pela leitura única e, na última instância, pelo guard do store (D1), que
recusa o batch em vez de admiti-lo.

## 3. D2 — CAS depois do admit: o comentário mentia

O batch é admitido (supply durável) **antes** do CAS do cursor em memória; um CAS falho descarta o receipt e não
avança a visita, mas não desfaz o payload. Comentário corrigido em `AcquisitionCoordinator.swift` para dizer o
comportamento real e por que a ordem inversa (CAS antes do admit) seria pior (cursor sem payload).

**Regressão fixando o comportamento permitido.** `testSupplyAdmittedBeforeRetirementStaysCanonicalWhileTheVisitCursor-
DoesNotAdvance`: admit `.visit` → revoke → CAS devolve nil → o registro canônico existe (não é rollback), nenhum
alvo durável, `checkpointAdvanced == false`.

## 4. H3 — precisão do receipt/trace

`AdmissionRecord.checkpointAdvanced` documentado: **só** o cursor durável armazenado; uma visita sempre reporta
false porque seu cursor é o arming. O evento `concluded` passou a declarar `authority_origin` (`visit`/`durable`),
sem alterar `checkpoint_advanced` nem qualquer campo consumido por gate. Sem mudança de schema.

## 5. H1 — paridade de namespace/SourceID

**Revalidado.** O princípio de catálogo é `record.key`/`identityKey`, validado como URL http(s) com host
(`LegacyCatalogImport.entryWithIdentityKey`), e a identidade do leitor declara `ReaderSourceIdentity.principalNamespace`.
A derivação do binding, porém, inventava `"feedmine-development-rss"` para principal não-http com namespace nil —
justamente o caso de um alias de autoridade `catalog` cujo `anchorKey` não é URL (`TrustedFeeds.resolveAvailable:108-112`),
enquanto o caminho durável estampa `LegacyCatalogImport.principalNamespace` incondicionalmente
(`ReaderDiscoveryTraversal:312-314`). A promoção compara namespace exato.

**Correção.** `FeedAssociation.binding(for:)` usa `feed.principalNamespace ?? LegacyCatalogImport.principalNamespace`
(a string inventada não tem outro consumidor). Durable e visita derivam do mesmo ponto, então não há divergência de
namespace nem de `SourceID` para a mesma fonte.

**Testes.** `FeedMineAppTests/S1SourceSurfaceTests.testACatalogueFeedWithNoStatedNamespaceUsesTheCatalogueNamespace`
(nil + principal sem esquema → namespace do catálogo, mesmos `sourceID`/`bindingID`) e
`testAReaderFeedKeepsItsReaderNamespace`.

## 6. H5 — teste de store prometido

`Tests/FeedMinePersistenceTests/TransientAdmissionTests.swift` (novo, 5 casos) cobre: admissão `.visit` sem criar
alvo e sem reportar cursor durável; membership fora do conjunto armado recusada sem resíduo; D1 enabled/revoked;
licença vazia; e que a visita não move o cursor de outro alvo durável.

## 7. UX12-A — UI real, executado

`FeedMineUITests/CardActionJourneyUITests/testViewSourceOpensTheInternalSourceAndReturns` estendido e executado:
card → menu "Ver a fonte" → contexto da fonte (não abre o site), chip nomeando a fonte; **Fontes abre e fecha a
partir do contexto da fonte** e o contexto sobrevive; limpar restaura o contexto principal **e a mesma carta** como
ponto de leitura (`firstCard.identifier`); Fontes continua abrindo/fechando no principal sem mudar o contexto.
Língua fixada em pt_BR (as entradas de menu são copy do produto; a primeira execução falhou por o simulador estar em
inglês — registrado, não é defeito). **PASS 47,987 s** (`/tmp/s1-ui-2.xcresult`), prova anexada
`ux12a-card-source-return`.

## 8. UX12-D — UI real, executado, com copy nova

`FeedMineUITests/SourceAbsenceJourneyUITests/testADisabledCatalogueSourceWithNoPayloadStatesTheFeedBoundary` (novo):
seleção vazia desde o launch → Fontes (ação da superfície vazia) → nó Wildlife & Nature → fonte **desabilitada**
(`node-source-toggle-... = 0`) → abrir a linha. Sem payload local e com a rede bloqueada, a superfície afirma:
chip "BBC News" (origem declarada), nota de limite **"Você está vendo os itens que BBC News publica no feed. O
arquivo completo do site não faz parte dele."**, 0 cartas, sem `feed-empty-title` (a ausência é da fonte, não da
seleção); limpar restaura a superfície vazia anterior; reabrir Fontes volta ao mesmo nó e a fonte continua
desabilitada. **PASS 126,285 s** (`/tmp/s1-ui-4.xcresult`) com o texto de prova `ux12d-disabled-source-absence`;
o screenshot daquela execução estava mal atribuído — ver a correção logo abaixo.

**Correção de atribuição da imagem (2026-10-26, sobre `4973f1c9`).** O screenshot `ux12d-absence-surface` de
`/tmp/s1-ui-4.xcresult` foi tirado no **fim** do teste — depois de `chip.tap` → `reader-context-clear` → reabrir
Fontes → `node-sources-done`. O que ele mostra é a **superfície vazia do principal** ("Nenhuma fonte habilitada",
"Escolher fontes", chip "Sem histórias"), não a ausência da fonte. A imagem não provava o que o nome afirmava. O
PASS e as asserções não são atingidos: `chip.label == "BBC News"`, a nota do limite, `cards() == 0` e a ausência de
`feed-empty-title` foram afirmados na tela da fonte, **antes** do fechamento; o defeito era só de atribuição da
prova visual.

Correção aplicada no teste (produção, asserções e flags intocadas): captura `ux12d-source-absence-before-return`
adicionada imediatamente após essas asserções e **antes** de `chip.tap`; a captura final renomeada para
`ux12d-main-empty-after-return`, que é o que ela de fato mostra. Execução causal única do mesmo método
(`-only-testing:FeedMineUITests/SourceAbsenceJourneyUITests/testADisabledCatalogueSourceWithNoPayloadStatesTheFeedBoundary`,
mesmo DerivedData `FeedMineApp-elrtsjoinadyscatutssffaaecyb`): **PASS 130,159 s** em
`/tmp/s1-ui-evidence-corrected.xcresult` (log `/tmp/s1-ui-evidence-corrected.log`). Anexos exportados em
`/tmp/feedmine-source-absence-corrected-attachments/`:

- `C07E98B4-19A4-4223-BB95-8805430F155D.png` (`ux12d-source-absence-before-return`) — header "Feedmine · BBC News",
  0 cartas, alerta "Não foi possível atualizar / Não foi possível abrir o feed desta fonte." e "Tentar novamente".
  É a ausência **da fonte**, com o chip nomeando-a; a superfície vazia do principal não aparece.
- `A4477DB7-7319-4F3A-8454-E8EC1E947C07.png` (`ux12d-main-empty-after-return`) — "Nenhuma fonte habilitada" /
  "Escolher fontes", o que a captura final de `/tmp/s1-ui-4.xcresult` já mostrava.
- `1C179AD7-594E-472A-99BB-88C217319CF6.txt` (`ux12d-disabled-source-absence`) — chip, nota literal, `cards=0`,
  `main-empty-restored=true`, `source-still-disabled=true`, `fontes-path=Wildlife&Nature`.

Limite honesto da nova imagem: o alerta de falha de carga cobre parte da nota, então o texto exato da nota não é
legível no PNG; ele é afirmado por asserção nessa mesma execução e carregado literalmente no `.txt` acima. Nenhum
estado foi forçado para a captura e nenhuma imagem foi produzida fora da tela real do simulador.

**Não são screenshots limpos de produto:** os dois PNGs carregam, no canto superior direito, o overlay de depuração
`received=0 completed=0 backward=0` que o app desenha na build de teste; ele fica sobre a barra de status e não
esconde chip, cartas ou o corpo das superfícies. Somado a isso, é o alerta — não o overlay — que cobre a nota no
frame de antes do retorno.

Duas execuções anteriores falharam e estão registradas: (1) com `FEEDMINE_LOCAL_FEEDS=1` o transporte de fixture
respondia a fonte visitada e desenhava 12 cartas — premissa errada, corrigida removendo o flag; (2) a prova final
lia `chip.label` depois de fechar o contexto (elemento inexistente) — valores capturados antes. Nenhuma delas foi
defeito de produto.

**Copy e localização.** `FeedLoadingView.sourceScopeNote(sourceContextName:)` e
`showsSourceScopeNote(work:sourceContextName:)`: a nota só aparece em ausência de fonte (`unavailable`,
`unreachable`, `deferred`, `failed`, `endOfContent`), nunca no principal nem durante preparação. Chave nova em
`Localizable.xcstrings` com tradução `en` (fonte pt-BR). `FeedScreen` recebe `sourceContextName` do host
(`composition.sourceContextDisplayName`, nil fora de `.source`).

## 9. Verificação executada

| Prova | Resultado |
|---|---|
| `swift test --filter TransientAdmissionTests` (guards presentes) | **5/5 PASS**; **red medido** 5 falhas sem os guards |
| `swift test --filter VisitAcquisitionTests` | **8/8 PASS** (inclui barreira D3 e contrato D2) |
| `swift test` (pacote completo) | **1743 testes, 1 skip, 0 falhas** (107,0 s) |
| app: `FeedMineAppTests/S1SourceSurfaceTests` | **3/3 PASS** |
| app: `FeedMineUITests/CardActionJourneyUITests` (UX12-A) | **PASS 48,0 s** |
| app: `FeedMineUITests/SourceAbsenceJourneyUITests` (UX12-D) | **PASS 126,3 s** |
| app: mesmo método, correção de evidência (`ux12d-source-absence-before-return`) | **PASS 130,2 s** |

Artefatos: `/tmp/s1-package-full.log`, `/tmp/s1-red.log`, `/tmp/s1-green.log`, `/tmp/s1-app-unit.xcresult`,
`/tmp/s1-ui-2.xcresult`, `/tmp/s1-ui-4.xcresult`, `/tmp/s1-ui-evidence-corrected.xcresult` (+ `.log`),
`/tmp/feedmine-source-absence-corrected-attachments/`. Build de app reutilizou o DerivedData existente
(`FeedMineApp-elrtsjoinadyscatutssffaaecyb`); nenhum simulador de bench tocado.

## 10. Limites

- A janela "batch já admitido no instante da aposentadoria" continua aceita por política (§6 da revisão): o payload
  foi autorizado por gesto, é supply durável, e nenhuma publicação entra na associação aposentada (fence de runway).
  O que agora está medido é (a) nenhum request após `revokeAll` e (b) nenhum payload novo admitido após a revogação.
- D2 continua sendo supply antes do CAS por escolha: a alternativa avançaria cursor sem payload.
- A nota de UX12-D é copy de ausência; não foi adicionada a `.endOfContent` com cartas (o bloco final já tem texto
  próprio) — só quando a superfície não tem conteúdo.
- `capacity-ready.json` permanece untracked e intocado; sem push/merge/deploy.
