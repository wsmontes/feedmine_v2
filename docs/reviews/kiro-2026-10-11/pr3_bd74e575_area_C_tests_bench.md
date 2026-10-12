# Revisão K-04 final — PR #3 FeedMine V2 — ÁREA C (testes e benchmark)

Checkout: `C:\workspace\feedmine_v2-int` em `bd74e575` (detached). Diff base: `git diff origin/main...bd74e575`.
Somente leitura. Sem toolchain Swift — nenhum teste foi compilado nem executado; os achados são estáticos.

## Veredito

**Nenhum bloqueio P0.** Dois achados **P1** concretos de vacuidade em testes do app (CompositionTests e o
driver B05), e um **P1** no teste visual "em repouso". O oráculo do bench e os testes de admissão de runtime
(ScrollAdmissionTests / FeedPresentationAdmissionTests) estão **corretos e não vacuosos** — respondem o que a
coordenação pediu. Abaixo, por pergunta obrigatória.

---

## P1 — Q1: o teste visual "em repouso" pode passar sem mutação (vacuoso)

`FeedMineApp/FeedMineAppTests/ArticleReadingDiagnosisUITests.swift:188`
`func testWindowUpdateDoesNotShiftAStableVisibleCardWhileStopped()`

Trecho (fase 1, o único guard sobre o que aconteceu no avanço):
```swift
XCTAssertGreaterThanOrEqual(distinct.count, 2,
    "o avanço tem de mover o leitor para haver uma admissão pendente (\(distinct.count) cartas distintas)")
```
e a medida parada (linhas 254–272):
```swift
let shift = high - low
...
XCTAssertFalse(leftTheWindow, ...)
XCTAssertLessThan(shift, 1, "com o leitor PARADO, a atualização da janela moveu a carta visível em \(shift) pt...")
```

**Por que bloqueia (vacuidade):** o teste **não exige que uma poda/inserção acima tenha ocorrido no intervalo
medido**. O único guard é `distinct.count >= 2`, que só comprova que o *avanço* (fase 1) passou por ≥2 cartas —
não que uma admissão (poda de cabeça / inserção acima da âncora) **chegou durante os 20 s parados**. O comentário
é explícito: "a admissão é assíncrona, ela **pode** chegar depois de a rolagem assentar". Se nenhuma admissão
cair nessa janela de 20 s, `shift = 0` e `XCTAssertLessThan(shift, 1)` passa **sem nenhuma mutação** — exatamente
o caso vacuoso. Não há asserção que amarre um evento de mutação da janela ao intervalo medido; o traço
(`FEEDMINE_TRACE_CAPTURE`) só é anexado como string de evidência (linha 268), nunca é lido para afirmar que a
atualização ocorreu.

**Responde à pergunta, item a item:**
- Usa **frame e offset?** Sim — mede `element.frame.minY` (frame cheio), não só `y_conteúdo`. ✔
- Declara medida inválida se o card sai da janela? Sim — `XCTAssertFalse(leftTheWindow, ...)` (linha 270). ✔
- Exige mutação no intervalo? **Não.** Pode passar vacuamente. ✘

**Correção mínima:** antes do `XCTAssertLessThan(shift, 1)`, afirmar que a janela mudou durante o trecho parado —
ler o traço (`admitted`/`advance`) escrito no intervalo `[início-da-medida, fim]` e exigir ≥1 admissão com
`prune`/`insert` acima da âncora, ou pular a asserção com `throw XCTSkip("nenhuma admissão caiu no intervalo
parado")` em vez de PASS silencioso. Hoje "sem mutação" e "mutação sem deslocamento" são indistinguíveis.

Observação (não bloqueio): os 3 últimos commits (`bd74e575`, `308556d`, `1716b44`) giram em torno deste teste e
da "CORRELACAO que explica os 10 pt". Se a medição real no aparelho dá ~10 pt de deslocamento, o teste como
escrito ficaria **vermelho no device** (não vacuoso) — o que é bom. Não dá para confirmar sem rodar; o risco
estático é só o caminho vacuoso acima.

---

## Q2: tetos e alcance — runtime é sólido; o teste do app em 955 é vacuoso

### P1 — `testReopeningOfflineKeepsCardsBeyondTheBackwardCapacityReachable` pode passar vacuamente

`FeedMineApp/FeedMineAppTests/CompositionTests.swift:955`

Trecho (o arranjo):
```swift
try await produceAndAdmit(old)
try await produceAndAdmit(old)   // SEM bumpar ReadingFixture.generation
let before = try XCTUnwrap(old.store.state.presentation)
let publishedWhileOpen = Set(before.window.items.map(\.id))
```
e a asserção final:
```swift
let lost = publishedWhileOpen.subtracting(reachable)
XCTAssertTrue(lost.isEmpty, "\(lost.count) cartas que o leitor alcançava ANTES de fechar não voltam...")
```

**Por que bloqueia (vacuidade):** o fixture (`ReadingFixture`, em `ReadingCompositionTests.swift:35-45`) serve
`itemRange = (generation*24+1)...(generation*24+24)`. Este teste **não altera** `ReadingFixture.generation`
(fica em 0), então as **duas** publicações servem os **mesmos 24 itens** com GUID estável → a edição satura em
~24 cartas. O teto da janela restaurada é `8+1+16 = 25`. Logo `publishedWhileOpen` (≤24) cabe inteiro no recorte
restaurado + poucos passos para trás, e `lost` fica trivialmente vazio **sem exercitar "além do backwardCapacity"**.

A prova de que isto é vacuoso está no próprio arquivo: o teste irmão `testLongNavigationKeepsTheTotalWindow...`
(linha 1029) **bumpa** `ReadingFixture.generation` 8× de propósito e comenta (linha 1037-1040): *"Com o fixture
parado, cada publicação republicava os mesmos 24 itens, a edição saturava em ~20 cartas e a navegação longa nunca
chegava a exercitar o limite ... **sem ele o teste é vacuoso**."* O teste de 955 cai exatamente nesse arranjo
saturado que o de 1029 identificou como vacuoso.

**Correção mínima:** bumpar `ReadingFixture.generation` entre as duas publicações (como 1029 faz), para a edição
exceder `8+1+16` e `publishedWhileOpen` conter cartas realmente fora do recorte restaurado; e afirmar
`publishedWhileOpen.count > 25` como pré-condição do arranjo, para o teste falhar alto se o fixture voltar a
saturar.

### Corretos e NÃO vacuosos (runtime) — respondem Q2 de fato

- `Tests/FeedMineRuntimeTests/ScrollAdmissionTests.swift` (fixture de 30 cartas, bounds 2/4): afirma conteúdo
  **exato** da janela (`Array(f.ids[2...8])`), `items.count <= backwardCapacity+1+forwardCapacity`
  (`:264`), disjunção com o futuro não admitido, e **rematerialização offline** por `.backwardScroll`
  (`"Backward admission re-reads the cards the window had cut"`). Não satura: 30 > janela.
- `Tests/FeedMineRuntimeTests/FeedPresentationAdmissionTests.swift:testForwardScrollAdmitsOnlyReadyPrefix`:
  afirma **igualdade** `items.count == backwardCapacity+1+forwardCapacity` (`:217`), âncora centrada, IDs
  rematerializáveis do store (`PublicationHistory.window(...)` e `.backwardScroll` devolvem a carta cortada).
  Estes são os juízes reais de "`items.count ≤ B+1+F` e IDs rematerializáveis offline".

---

## Q3: testS5 e testK06 (versão final) exigem o que a coordenação pediu

**Sim.**

- `CompositionTests.swift:866 testS5OfflineReopenRestoresEditionWithFreshProvenance`: exige edição restaurada,
  proveniência **nova**, âncora preservada, **alcance anterior não encolhe** (`index >= min(before,8)`, `:933`)
  e **alcance posterior offline** — pedir a cauda (`.explicitTailApproach`) com a rede rejeitada tem de crescer a
  janela com IDs novos do store (`extendedItems.count > items.count` e `fresh` não vazio, `:963-968`). O alcance
  **anterior ao recorte** (cartas mais velhas que a janela) é deliberadamente **não** afirmado aqui, com
  justificativa registrada ("achado de produto, relatado ao arquiteto"); esse lado é coberto pelo teste de 955.
- `CompositionTests.swift:748 testK06AnsweringInABetweenAAndBKeepsTheReaderWhereTheyWere`: é exatamente o
  **B05 com uma resposta entre A e B** que a coordenação apontou como lacuna (K06-5). Exige edição/âncora/topo
  restaurados após A→B→A, **e** que a resposta (`declaredLevel == .more`) e os salvos sobrevivam (`:825-829`).
  Os gêmeos `:737` (troca por fonte) e `:744` (troca por filtro) são os controles pedidos.

Limite: estes dois são `async` em processo (não UITest); o alcance posterior em S5 é provado no store, não no
dispositivo. A versão "final" de K06 corresponde ao que a seção 5/6 do KIRO.md pediu.

---

## Q4: benchmark — oráculo não converte falha/não-medido em PASS

**Não converte.** `bench/oracle.py:verdict()` (linhas ~430):
```python
def verdict(clauses):
    if any(clause["pass"] is False for clause in clauses):
        return "FAIL"
    if any(clause["pass"] is None for clause in clauses):
        return "NOT_RUN"
    return "PASS"
```
FAIL tem precedência; qualquer cláusula `None` força NOT_RUN; PASS só com **todas** True. Os caminhos de
"não medido" produzem `None`, nunca True:
- B03 prontidão (`:candidates else None`) e avanços (`:advances else None`): sem medição → None; medido e
  incompleto → FAIL. O defeito antigo "PASS com 871 candidatos e 0/0/0" está corrigido (comentário no código).
- B04 `not-measurable` → `None` (gate incompleto), nunca PASS; `false` → FAIL.
- banco ausente → cláusula única `pass: None` → NOT_RUN (função `cards()`/`main()` tratam `os.path.exists`).

**EVALUATOR.sha256 cobre os arquivos que decidem?** Em grande parte **sim**: congela `run.sh`, `oracle.py`,
`serve.py`, `build_corpus.py`, `expand.py` e `DiscoveryBenchmarkTests.swift` (6 entradas, verificadas em
`bench/run.sh` passo 1b, que **recusa** com exit 3 se divergir). Além disso, `run.sh` re-hasha por corrida os
insumos do oráculo (`inputs.sha256`: `catalog.sqlite`, `items.json`, `oracle.py`, DiscoveryBenchmarkTests).
**Observação (não bloqueio):** `bench/transport_variant.py` **não** está no EVALUATOR.sha256. Ele é um gerador
offline que só afeta o caminho **device**, cuja saída é congelada em `bench/device/MANIFEST.sha256` e verificada
em `run.sh` passo 1a (exit 3 se divergir). Como ele não participa do veredito de uma corrida (produz o corpus do
device, que é hasheado à parte), não é um buraco de "converter falha em PASS". Fica como ponto a confirmar com o
arquiteto se quiserem o gerador também sob o selo do avaliador.

**run.sh exporta a origem exata?** **Sim.** `export FEEDMINE_BENCH_TRANSPORT_ORIGIN="$TRANSPORT_ORIGIN"`
(com o comentário "This is the loop that was open — the runner knew its transport and the app never heard of
it"). Device exige a origem (`exit 2` se ausente); simulador fixa `http://127.0.0.1:8757`. O selo de identidade
(`identity.txt`) grava commit + arquivos sujos; MANIFEST, device/MANIFEST e EVALUATOR são todos verificados antes
de qualquer build.

---

## Q5: no-ops, XCTExpectFailure, asserções afrouxadas

- **XCTExpectFailure:** **nenhum** em toda a Área C (`grep` vazio). O teste "em repouso" declara, no comentário,
  que o arquiteto **retirou** o marcador de falha esperada — confere com o código (não há marcador).
- **XCTSkip remanescentes:** todos legítimos e condicionais a execução fora do teste unitário:
  `DiscoveryBenchmarkTests.swift:34,732` (gates rodam via `bench/run.sh`, não em invocação nua),
  `FeedMineUITests.swift:13` (soak opt-in), `CatalogCompilerReferenceTests.swift:51,81,96,98` e
  `LegacyCatalogMetadataTests.swift:120` (dependem de assets de release/env). Nenhum mascara defeito.
- **No-op / asserção afrouxada:** o P1 de Q1 (teste "em repouso") e o P1 de Q2 (reach em 955) são os dois casos
  reais em que a asserção pode passar sem exercitar o que afirma. Fora deles, não achei asserção relaxada sem
  justificativa nos arquivos desta frente.

### Achado adicional (P2) — driver B05 pode registrar `return-preserves-anchor:true` vacuamente

`FeedMineApp/FeedMineAppTests/DiscoveryBenchmarkTests.swift:637 testB05ContextsReopenOfflineAndSaved`

A ida A→B→A é feita por `if`s aninhados best-effort (`more-menu` → `Salvos` → `reader-contexts`); se algum não
aparece, a navegação **silenciosamente não acontece** e `anchorAfterReturn` é lido sem ter ido a B. Como nada se
moveu, `b05-return-preserves-anchor:true` pode ser gravado sem a jornada ter ocorrido, e o oráculo
(`gate_b05`) só falha em valor **presente-e-não-true** — a ausência de `b05-context-b-reached` não reprova.
Resultado: um B05 pode dar PASS com o A→B→A não executado. É P2 (não bloqueia o merge do PR; o gate roda no Mac,
fora do alcance desta revisão) — mas vale endurecer: exigir `b05-context-b-reached:true` como cláusula do
oráculo, e falhar o driver se o menu/contexto não forem alcançados em vez de seguir.

---

## O que não li / limites

- **Sem toolchain Swift:** nada foi compilado ou executado. Vacuidade e correção são lidas no código; o
  comportamento real no device/Simulador (os UITests de `ArticleReadingDiagnosisUITests`, `ReadingSurfaceUITests`,
  `EditorialOfferBudgetUITests`, e os gates B01–B05 via `bench/run.sh`) **não** foi observado.
- **"Decisao Codex — 2026-10-12 03:32" não existe neste checkout.** `git grep` por "03:32"/"Decisao Codex" em
  `bd74e575` não encontra nada; a última seção datada de `coordination/KIRO.md` em `bd74e575` é a publicação
  TestFlight 1.0(27) e o log de checagens termina em `2026-10-12 00:37`. Li as "últimas seções" realmente
  presentes no checkout. Se a decisão 03:32 existe numa versão posterior, não a tive à disposição.
- **Li em detalhe:** `ArticleReadingDiagnosisUITests.swift` (inteiro), `CompositionTests.swift` (testS5, os três
  testK06, os três reach/cap ~866–1150, `produceAndAdmit`), `ScrollAdmissionTests.swift`,
  `FeedPresentationAdmissionTests.swift`, `ReadingCompositionTests.swift` (ReadingFixture), `bench/oracle.py`
  (inteiro), `bench/run.sh` (inteiro), `bench/EVALUATOR.sha256`, `scripts/verify_product_catalogue.sh` (inteiro).
- **Li por amostragem / só o cabeçalho:** `DiscoveryBenchmarkTests.swift` (B05 e B03 em volta de 637–732; não li
  os ~763 totais), `EditorialOfferBudgetUITests.swift` (não aberto por inteiro — a "nota de instrumento" do K06-2
  é descrita no inventário mas não a confrontei linha a linha).
- **NÃO li:** `bench/serve.py`, `bench/build_corpus.py`, `bench/expand.py`, `bench/transport_variant.py`,
  `bench/manifest.json`, `bench/MANIFEST.sha256`, `bench/README.md`, `bench/REFERENCE.md`,
  `scripts/soak.py`, `scripts/bootstrap_catalog.py`; e a maioria dos testes novos de `Tests/**`
  (Catalog*, Reader*, Language*, etc.) e dos UITests do app fora dos nomeados nas perguntas. São, pelo inventário,
  trabalho anterior commitado no release — não desta frente — e nenhuma pergunta obrigatória dependia deles.
  Não procurei exaustivamente por asserções afrouxadas fora dos arquivos desta frente (teto de 10 achados/área).
