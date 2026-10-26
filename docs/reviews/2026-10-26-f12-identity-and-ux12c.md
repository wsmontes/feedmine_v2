# F12 — identidade de fonte renomeada e UX12-C (2026-10-26)

Base: `b1915ad7` (docs de B03/limpeza já integradas). Commit deste trabalho: **`9b359d47`**, local, sem push.
Nenhum arquivo de `bench/**`, oráculo, `criteria.json`, corpus, driver congelado, catálogo compilado,
`capacity-ready.json`, simulador, banco ou evidência de outra lane foi tocado.

Régua: `docs/product/F12_SOURCE_TAXONOMY_NAVIGATION_UX_PRD.md` (R1–R6, UX12-A..D), S1
(`V1_GOLD_IMPLEMENTATION_BRIEFS_2026-10-10.md`, G01+G08), `docs/architecture/PUBLICATION_RESTORE_CONTRACT.md` e
`PUBLICATION_DESIGN.md` (Edition/Segment/card imutáveis; restore = mesma Edition + mesmo card + mesma âncora).

## 1. A — o card de uma fonte renomeada continua endereçável (F12/R1, PD10-P0D)

**O que estava errado.** `ReaderLibraryStore.reconcile` grava **duas** linhas por alias verificado, ambas com
`anchor_key = oldKey` e `current_key = newKey`. O caminho do card (`sourceKey(for:)`) derivava o id só do
`anchorKey` e devolvia `link.sourceKey`:

1. carta publicada **depois** da renomeação — o id foi cunhado de `newKey`, nenhuma linha o reproduz → `nil` →
   "Não foi possível abrir a fonte" **permanente**;
2. carta publicada **antes** — as duas linhas devolvem id de `oldKey`, e o retorno era `sourceKey` de qualquer
   linha que o `Dictionary` entregasse primeiro (`oldKey` ou `newKey`, ordem não determinística).

**Correção.** A pergunta passou a ser do owner, não do host:
`Sources/FeedMineComposition/SourceIdentityIndex.swift`. Ele tenta **as duas** derivações que mintaram o id
(`anchorKey` e `currentKey`) sob a autoridade que a linha declara, e devolve sempre `currentKey` (fallback
`sourceKey`, depois `anchorKey`), iterando as chaves em ordem — o resultado não depende da ordem de leitura.
`FeedMineApp/AppComposition.swift:sourceKey(for:)` agora delega.

**Autoridade sem palpite.** Os cinco sítios que gravavam identidade usavam
`principalNamespace == ReaderSourceIdentity.principalNamespace ? "reader" : "catalog"` — qualquer namespace
desconhecido virava `catalog` e ficava **pinado** (`INSERT OR IGNORE`). Agora há uma derivação única
(`sourceAuthority(of:)`) que trata `nil` como catálogo (é o que a resolução de catálogo deixa), reconhece os dois
namespaces declarados e **não grava** para um namespace desconhecido. A tabela já tinha `CHECK(authority IN
('catalog','reader'))`; o que faltava era não gravar a adivinhação.

**Red medido** (`Tests/FeedMineCompositionTests/SourceIdentityIndexTests.swift`, derivação antiga restaurada):

```
testAVerifiedAliasAnswersBothTheCardBeforeAndAfterTheRename
  :39 post-renomeação: ("nil") is not equal to ("Optional("https://new.example/rss")")
  :46 linha antiga, carta pré-renomeação: ("Optional("https://old.example/rss")") is not equal to (…new…)
  :48 linha nova, carta pós-renomeação:  ("nil") is not equal to (…new…)
  4 asserções, 1 teste — Executed 1 test, with 1 failure
```

**Green medido:** `swift test --filter SourceIdentityIndexTests` → **3 testes, 0 falhas**. O caso usa duas
catálogos compilados em disco (`revision 5` com `oldKey`, `revision 6` com `newKey`, **mesmo** `request_url`),
`VerifiedSourceAlias` e `ReaderLibraryStore.reconcile` **reais** — nada de linha inserida à mão.

**Cobertura do host:** `testF12AnUndeclaredNamespaceRecordsNoAuthority` (novo) prova no app que um namespace não
declarado **não** grava linha de identidade, e que o vínculo do catálogo (namespace `nil`) grava `catalog`.

**`FilterSheetView.init(applying:…)` removida — verificado, mantida removida.** Único chamador no repo:
`FeedMineApp.swift:341`, que usa `init(store:)`. A conveniência antiga construía o `ReaderFilterStore` **dentro**
do sheet, isto é, o segundo dono do draft que o F12 fechou; reintroduzi-la como compatibilidade recriaria o
defeito, então a remoção é a forma correta (API pública do módulo, sem consumidor externo no repo).

## 2. B — UX12-C: gerenciar fonte altera produção futura e não troca a leitura

**Medido antes** (nesta rodada, com a regra antiga restaurada, feed de 8 cartas de dois feeds):

|Fato|Antes|
|---|---|
|Destino|`.main` → `.source(50000000-…-000000000001)` (a fonte restante)|
|Edition|trocada|
|Cartas publicadas|substituídas (nenhum id em comum)|
|Âncora|trocada|
|Pós-relançamento|mesma história trocada, mesma âncora nova|

`Executed 1 test, with 9 failures` em `testSourceSelectionSurvivesRelaunchAndFiltersCanonicalSupply`.

**Mecanismo (dois elos, ambos causais):**

1. `toggleSource`/`adoptSelectionChange` reescreviam o destino:
   `next.count == 1 ? .source(next[0].sourceID) : .main`. Agora `destinationAfterSelectionChange()` mantém o
   destino; a **única** exceção é um contexto de fonte cuja fonte saiu da seleção (seria cerca em volta de nada).
   Ganhar ou perder a última *outra* fonte não é navegação: `.source` é entrada explícita (linha da taxonomia,
   card), nunca efeito colateral de um toggle.
2. `mayShow` comparava `userSelectionVersion` e, ao mudar a seleção, o construtor da associação **limpava** o
   checkpoint e publicava outra Edition. Agora a compatibilidade é identidade de contexto + políticas de
   apresentação (eligibility, scoring). Reconciliação explícita com o contrato, escrita no código:
   `PUBLICATION_RESTORE_CONTRACT` faz do histórico publicado a unidade restaurável e a Edition imutável, e a
   sessão continua essa Edition **sob a revisão que ela congelou** (o append exige igualdade exata e continua
   valendo). A seleção chega à produção futura pelo **suprimento** (as memberships que a sessão lê), não
   recusando a história na frente do leitor. `EditorialRevision.userSelectionVersion` continua separando as
   *identidades* de Editions publicadas sob seleções diferentes; deixou de invalidar a história da outra.

**Green medido** (`testSourceSelectionSurvivesRelaunchAndFiltersCanonicalSupply`, reescrito como a jornada do
oráculo): multisource → uma fonte (a última é **recusada** por `invalidSelection`, e a recusa não move nada),
cartas reais dos dois feeds de desenvolvimento, âncora avançada para a 4ª carta antes do toggle. Asserções:
seleção durável +1; `eligibleTargets` deixa de nomear o target da fonte desabilitada e continua nomeando o da
restante (produção futura); destino, Edition, ids publicados (prefixo idêntico, cauda só cresce) e âncora
inalterados; relançamento na **mesma** Edition, **mesma** âncora e **mesma** ordem publicada.

**Expectativas antigas atualizadas (4), todas premissas da reescrita removida:**

|Teste|Antes|Agora|
|---|---|---|
|`testSourceSelectionSurvivesRelaunchAndFiltersCanonicalSupply`|`.source(restante)` + cartas novas|destino, Edition, ordem e âncora preservados (a jornada do oráculo)|
|`testA05AdoptingSelectionOutsideCollectionExitsCollectionPreset`|`.source(a)`|`.main` (sair da coleção mantém o feed simples)|
|`testF12EmptySelectionOpensTheDisabledSourceWithNamedCards`|`.source(id)` ao habilitar|`.main`; o `.source` continua exigido **depois** da abertura explícita e no relançamento|
|`dormantSourceCard` (helper de dois testes)|`.source(id)` ao habilitar|`.main` + `feeds == [id]` como premissa de que o enable chegou à sessão|

`CompositionTests`: **132 testes**, 4 falhas na primeira passada (todas as quatro acima), **0** nas demais;
depois do ajuste, os quatro casos + UX12-C + S1 verdes (`Executed 4 tests, with 0 failures`, `Executed 6 tests,
with 0 failures`) e, com o alvo de app inteiro, `CompositionTests` **132/0** dentro de **204/0**.

## 3. C — S1 no transporte (evidência acrescentada, comportamento não alterado)

`testF12OpeningAnUnselectedSourceNeverReachesTheCoordinator` passou a medir no **log do transporte controlado**
(o registro do `FixtureTransport`, não a URL entregue ao app):

- abrir a fonte não selecionada (`openSourceFeed(forKey:)`) + `driver.drive` → **nenhum** request ao endpoint dela
  (S1: "abrir não reabilita o endpoint automaticamente"; R4: a seleção não é escrita, nenhum target registrado);
- **controle**: o ato explícito de selecionar a fonte é o que produz o request ao mesmo endpoint;
- **cerca**: a associação anterior está aposentada (`active == false`) e, fechada, um `drive` nela não emite
  request — a oportunidade morre com o contexto, não com um enable durável.

**Limite honesto do lado positivo.** Não implementei autoridade **efêmera** no coordenador. O motivo é medido no
código: `SyndicationAcquisitionSnapshot.eligibleTargets` só devolve target que a `AcquisitionTargetAuthority`
durável conhece e tem `state == .enabled`, e o único caminho que materializa supply novo
(`ReaderDiscoveryTraversal.materialization`) **registra** o target durável (`authority.register`) — inclusive para
descoberta, que é contextual. Uma autoridade efêmera exige um contrato novo em `FeedMineAcquisition` (generation e
checkpoint em memória, sem escrita em `runtime.sqlite`) e a cerca correspondente; não é uma correção mínima, e
fazê-la agora teria tocado a autoridade durável que INV-11/INV-12 protegem. O que S1 pede como evidência
("requests feitos por ação explícita", "sem `View.task` de HTTP") está medido acima, e `Sources/FeedMineUI` não
tem `URLSession` em nenhum arquivo.

## 4. D — UX12-D: NOT_RUN nesta rodada

Nenhuma captura de UI. O que se sabe sem inventar produto: o único estado vazio de primeira tela é o de
**seleção** (`FeedFirstScreenGate.swift`, `hasSources` descreve os feeds do leitor), e uma fonte **aberta** cai no
caminho preparação/ausência, cuja copy não foi escrita para "esta fonte ainda não tem histórias aqui". Escrever a
copy sem observar a tela seria inventar produto, então a pendência é a observação (bitmap/AX no simulador) e, só
depois, a entrada própria no gate. Nada do produto mudou por causa deste item.

## 5. Limites desta rodada

- Nada foi enviado: commit local `9b359d47`, sem push/merge/deploy.
- Alvo de app **inteiro** (`-only-testing:FeedMineAppTests`) depois das emendas: **204 testes, 0 falhas** (EXIT=0,
  430,3 s; `/tmp/f12b-apptarget.xcresult`), com `CompositionTests` 132/0 inteira, `ReadingCompositionTests` (13),
  `CatalogueUpdateAcceptTests`, `FilterConfirmationBoundaryTests` e as composições de leitura/mídia.
- Alvos **de UI** (`FeedMineUITests`, jornadas XCUITest): **não** executados nesta rodada.
- Pacote: `swift test` completo depois das mudanças de `FeedMineComposition` → **1729 testes, 1 skip, 0 falhas**
  (EXIT=0, 109,3 s).
- UX12-A (card/âncora no retorno) continua sem teste que afirme o card; UX12-B segue como estava; B03/B05/B06 não
  foram tocados nem reexecutados.
- Nenhum número desta rodada vem de benchmark: são testes de composição/pacote com transporte controlado.
