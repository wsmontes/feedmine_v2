# S1 — aquisição contextual de uma fonte visitada (e os limites do F12)

Escopo: completar a jornada S1 (`V1_GOLD_IMPLEMENTATION_BRIEFS`, G01+G08) sem segundo pipeline, e fechar as lacunas
B1–B4 apontadas por `2026-10-26-f12-identity-and-ux12c`. Base medida: `64828464`. Registro de execução de uma sessão;
o que está **executado** aparece com o número; o que é leitura de contrato aparece citado.

## 1. Contrato interno alterado (menor possível)

| Owner | Mudança | Por quê |
|---|---|---|
| `FeedMineAcquisition/AcquisitionTarget.swift` | `VisitTargetAuthority` (licença e cursor do processo) + `AcquisitionTargetLedger` (`durable`/`visit`) | a mesma responsabilidade de `AcquisitionTargetAuthority` com outra *lifetime*, como o plano exigia. Um `ContextKey` não foi copiado para a autoridade: o fence de execução continua sendo escopo/revisão da lane de coverage. |
| `FeedMinePersistence/AcquisitionAdmissionStore.swift` | `BatchCommand.authority` (`.durable` \| `.visit(kind, sources)`) | no caminho `.visit` o admission **não** faz `requireTarget`, **não** valida stamp durável, **não** grava checkpoint; valida as observações pelas mesmas regras canônicas e pela lista de fontes autorizadas do arming. Zero schema novo. |
| `FeedMineAcquisition/AdmissionPolicy.swift` | sobrecarga com `authority:` (default `.durable`) | um único `admit`, um dono de admissão. |
| `FeedMineAcquisition/AcquisitionCoordinator.swift` | `visitAuthority` opcional; `run` lê o ledger, re-lê a autoridade **imediatamente antes** do admit, e faz o CAS do cursor em memória depois | nenhum scheduler novo; fences de generation/state/connectorKind idênticos. |
| `FeedMineComposition/SyndicationAcquisitionSnapshot.swift` | `visitRegistrations`/`visitAuthority`; elegibilidade só no contexto `.source` do alvo armado; connector revalidado contra catálogo promovido | um caminho de fetch, dois lifetimes. Um relançamento (sem arming) não devolve alvo nenhum. |
| `FeedMineComposition/SourceIdentityIndex.swift` | `sourceIDs(in:for:)` | um alias verificado dá **dois** ids cunhados à mesma fonte editorial; a superfície precisa ler os dois (B2). |
| `FeedMineApp/AppComposition.swift` | `FeedAssociation(visitFeed:)` arma/revoga; `openSourceContext` é o único gesto que arma; `close()` revoga antes do settle; `destinationAfterSelectionChange`/`toggleSource`/`allowsSourceOutsideSelection` preservam a visita | B1 e a fiação de S1. |

### Precedência que impede ressurreição (INV-11/12)

`AcquisitionTargetLedger.target(id:)` responde **sempre** pela linha durável quando ela existe — `enabled` **ou**
`revoked`. A visita só responde onde não há linha durável alguma. Consequência testada: uma fonte revogada não pode ser
"reaberta" por um gesto (o snapshot lança `visitAuthorityWithdrawn`), e um alvo durável habilitado mantém seu próprio
generation e cursor (não há cursor bifurcado). O plano original previa "efêmero responde quando não há linha durável
**ou ela não está enabled**" — isso era exatamente o fallback que o pedido proíbe; foi rejeitado na implementação.

### O que o gesto arma, e o que ele não faz

`openSourceContext` (via `openSourceFeed(forKey:)`/`openSourceFeed(forSourceID:)`) arma **um** alvo, para **uma**
fonte, com `authorizedSources = [fonte]`. Não escreve `preferences`, não registra `acquisition_target`, não habilita
endpoint e não altera a Edition corrente (que é checkpointeada antes). `close()` revoga o arming; o pull em voo cai em
`.cancelled` e um alvo aposentado não entra em elegibilidade. Relançamento restaura o lugar de leitura **sem** armar.

## 2. B1 — toggle ejetava o leitor de uma fonte dormente: corrigido

`destinationAfterSelectionChange` só reconhecia fonte **selecionada**; uma visita tem `contextSource != nil` e
`.source(x)` com `x ∉ selectedFeeds`, então `toggleSource` devolvia `.main`. Correção em três pontos, todos no host:

1. `destinationAfterSelectionChange`: preserva `.source(x)` quando `contextSource?.sourceID == x`.
2. `allowsSourceOutsideSelection`: a visita desta sessão é destino mesmo antes de publicar (a regra de Edition continua
   valendo para o relançamento).
3. `toggleSource`: o rebuild passou a consultar a mesma regra — sem isso o destino preservado era reparado para
   `.main` por `sessionState` na entrada.

Regressão: `testF12TogglingAnotherSourceWhileReadingADormantOneKeepsTheVisit` — muda a seleção de verdade (o toggle
remove uma fonte selecionada), e afirma destino `.source(dormente)`, mesma `FeedEditionID`, mesmos `PublicationCardID`
na mesma ordem, mesmo `PresentationAnchor`, e a mesma elegibilidade da visita. **Executado: PASS.**

## 3. B2 — alias verificado: a superfície lê os dois ids; o cenário segue latente

O defeito declarado (toast permanente) já estava fechado em `9b359d47`. O que faltava era o outro lado: a visita
resolve pelo **anchor** (`LegacyCatalogImport.entryWithIdentityKey`), enquanto a carta publicada depois da renomeação
carrega o id cunhado da `current_key`. A sessão `.source(minted(oldKey))` elegia só o anchor, e as memberships
canônicas sob `minted(newKey)` ficavam fora da produção.

Correção: a elegibilidade da sessão de fonte inclui os dois ids que as **linhas de alias daquela fonte** derivam
(`SourceIdentityIndex.sourceIDs(in:for:)`), nunca um mapa global. Regressão unitária: os dois ids respondem pelo mesmo
conjunto a partir de qualquer metade, e um id não cunhado devolve `[]` — `SourceIdentityIndexTests` (executado no
pacote).

Limite honesto: `reconcile(VerifiedSourceAlias)` **continua sem chamador de produção** (só testes). A correção é real e
testada no owner da elegibilidade, mas o cenário "renomeação verificada" não é alcançável pelo app até a reconciliação
ser fiada a uma ingestão real. Não foi inventada uma heurística de alias para "fazer aparecer" (o manifesto público não
publica mapa de alias, e `VerifiedSourceAlias` exige prova de duas revisões compiladas). O teste ponta a ponta com carta
pós-renomeação exigiria um catálogo sintético instalado no app; ficou registrado como pendência em vez de simulado.

## 4. B3 — seleção vazia: decisão pela autoridade, não pelo comentário

A régua original decide: UX12-C exige que habilitar/desabilitar **não remova nem reordene** os cards já publicados
(`docs/product/F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md`, §4, linha do UX12-C), e o contrato de restauração diz que a
unidade restaurável é o histórico publicado, não a seleção (`PUBLICATION_RESTORE_CONTRACT`, §1/§7). Logo o estado
correto com seleção vazia é: **histórico preservado** (Edition, cards, ordem, âncora) + superfície do leitor declarando
que nada está selecionado (`surfaceHasSources == false`), e nenhum suprimento futuro. O comentário antigo em
`adoptSelectionChange` ("an emptied selection is a state the reader's own surface states") é compatível com isso e não
precisou ser derrubado; o "feed preenchido" denunciado na revisão é o contrato, não o defeito.

Regressão: `testF12AnEmptiedSelectionKeepsPublishedHistoryAndStatesTheEmptySelection` — esvazia a seleção pelo owner
(`SourceManagementCoordinator.setSelection([])`), afirma destino `.main`, seleção vazia, `surfaceHasSources == false`,
Edition/cards/âncora idênticos, e repete tudo após relançamento. **Executado: PASS.** Nenhuma mudança de código.

## 5. B4 — desabilitar × descoberta: limite declarado (F13 é o dono da exclusão)

O suprimento de uma associação é **seleção ∪ descoberta** (`SyndicationAcquisitionSnapshot.eligibleTargets`), e a
descoberta é, por definição, o canal de fontes que o leitor **não** nomeou. O contrato separa os vocabulários: F13/R1
distingue "menos deste assunto" (preferência), "filtro contextual" e **"exclusão durável de termo/fonte"**
(`docs/product/F13_CONTENT_CONTROL_EXCLUSIONS_UX_PRD.md` §3, R1); o toggle de fonte é o ato de seleção do F12/R4, e
`SourceManagementCoordinator.apply` grava **apenas preferências**. `revoke` é outra coisa (retirada de autoridade, usada
pela remoção do catálogo).

Decisão: **não** inventar uma blacklist permanente dentro da seleção. Isso contradiria a descoberta de fontes não
selecionadas e criaria um segundo vocabulário de exclusão sem contrato. O limite fica declarado: uma fonte que o leitor
desmarcou pode voltar a ser suprida pela descoberta enquanto F13 (exclusão durável, hoje NOT_RUN) não existir; o que o
toggle garante — e o que o teste de UX12-C mede — é que a **produção da seleção** muda e o publicado não é tocado.
Quando F13 for implementado, o lugar é o owner da exclusão (pré-filtro do suprimento), não `revoke`.

## 6. Verificação executada

| Prova | Resultado |
|---|---|
| `swift test --filter VisitAcquisitionTests` (servidor HTTP real em `127.0.0.1`, sem `URLProtocol`) | **5/5 PASS** |
| `SourceIdentityIndexTests` (novo caso de alias) | executado no pacote |
| app: `testF12OpeningAnUnselectedSourcePullsOnlyItsOwnEndpointByExplicitGesture` | **PASS** |
| app: `testF12TogglingAnotherSourceWhileReadingADormantOneKeepsTheVisit` | **PASS** |
| app: `testF12AnEmptiedSelectionKeepsPublishedHistoryAndStatesTheEmptySelection` | **PASS** |
| app: classe `CompositionTests` completa | **134/134 PASS** |
| `swift test` (pacote completo) | **1735 testes, 1 skip, 0 falhas** |
| app: `testF12AConstrainedVisitStatesAbsenceWithoutInventingOrSubstituting` (UX12-D) | **PASS** |
| app: alvo `FeedMineAppTests` completo | **206/206 PASS** |

Incidente medido na primeira passada da suíte completa: 9 falhas, todas em fences de generation/revogação do caminho
**durável**. Causa: a releitura defensiva da autoridade antes do admit interceptava a recusa e devolvia `.cancelled` em
vez do erro estrutural que os callers esperam. Correção: a releitura passou a valer só para o caminho `.visit`; o
caminho durável mantém exatamente o erro do admission. Os 4 arquivos afetados (161 testes) voltaram a PASS e a suíte
completa foi repetida (1735/1 skip/0).

Os testes de pacote provam, sobre socket real: só a fonte visitada é buscada; a admissão é canônica e durável (duas
memberships da fonte visitada, nenhuma da outra); **nenhum** `acquisition_target` é criado; um alvo durável habilitado
mantém seu próprio cursor; uma linha durável `revoked` não é ressuscitada; sem arming o snapshot recusa a registration;
após `revokeAll` a elegibilidade fica vazia e uma execução obsoleta não admite nada.

## 7. Limites e não-objetivos

- O cursor da visita é do processo: uma nova visita refaz o pull desde o início. A identidade canônica torna a
  re-admissão um no-op (`selectableSupplyChanged == false`), e não foi criada tabela de cursor temporário (seria
  autoridade durável disfarçada).
- Janela aceita: um batch já buscado pode ser admitido no instante da aposentadoria; a releitura imediatamente antes do
  admit fecha a janela para um arming já revogado, e nenhuma publicação entra numa associação aposentada (fence de
  runway). Testado no nível de admissão.
- **UX12-D — estado factual medido, captura de tela NOT_RUN.** A visita a uma fonte sem payload local, com a
  rede recusada (`FixtureTransport.rejecting`), apresenta ausência **na própria fonte**: contexto `.source`, zero
  cards, nenhuma Edition substituta, `surfaceHasSources == true` (a ausência é da fonte, não da seleção),
  `work != .endOfContent` (uma falha de rede não é "você leu tudo"), `startupFailure == nil` e o chip ainda nomeando
  a fonte. O caminho de copy é o gate já pinado para `unreachable`/`failed` em `FirstScreenPresentationTests`; o que
  falta — e é o bloqueador real — é a captura antes/depois: esta rodada não executou jornada de UI (o sheet de Fontes
  não expõe as linhas na árvore de acessibilidade neste device, já documentado em
  `docs/reviews/evidence/2026-10-25-f12-source-feed/README.md`), então nenhuma tela é alegada.
- UX12-A não foi reaberto: a rota card→detalhe→assunto→país→lista→fonte continua dependendo do sheet que não expõe
  linhas; o que esta rodada prova é o **destino** da fonte (`.source` correto, card/âncora preservados), não o percurso
  completo.
- `bench/**`, oráculo congelado, driver, `criteria.json`, `capacity-ready.json`, corpus: intocados. B03 permanece o
  resultado congelado (não é PASS) e B06 não é declarado provado.
