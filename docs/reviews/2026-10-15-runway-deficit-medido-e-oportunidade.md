# Runway — a reposição nasce do déficit medido, e o foreground é uma oportunidade (2026-10-15)

Base: `main` = `b88d3f80` (`fix(feed): resolve an expired overlay selection at launch`). Ambiente: macOS
arm64, Swift 6.3.3 (swift-driver 1.148.6), target `arm64-apple-macosx26.0`. Nenhum arquivo de `bench/**`,
nenhum oráculo e nenhum critério congelado foi tocado.

## 1. O que estava quebrado

**(a) A demanda de rede exigia prova exata abaixo do probe.** `RunwayController.acquisitionIntentIfEligible`
só emitia a demanda com `case .exact(count) = readyAhead.amount`. Uma leitura saturada (`.atLeast`) era
respondida com um **probe maior** (`readyProbeCeiling`) e, no teto de recursos, com **recusa** (`return .none`):
"a reserva parece saudável" fazia o papel da medida, e a rede só era pedida quando a contagem à frente estava
provada abaixo do probe — o "buscar quando faltarem exatamente N cards" que o INV-04 proíbe. Consequência
medida no código: com o walk local já gasto e o leitor no fim (pressão lógica) mas a leitura saturada, o runway
não pedia a rede nem dizia nada — a oportunidade terminava em `.measure` ou `.none`.

**(b) O único momento que produzia era o gesto.** `driver.drive` era alcançado pelo evento de viewport e por
`foreground()`; depois de background→foreground, `markConsumptionInactive()` zera `latestObservation` e o
`foreground()` antigo chamava `drive` **sem re-observar**: sem observação, `reconsider` devolve `.none` e o
pipeline ficava morto até o leitor rolar. A diretiva de execução V2 (linha 86) diz o contrário: *"o runtime
deve continuar adquirindo... antecipando consumo... Scroll **não** deve... acordar um pipeline parado."*

## 2. Causa e correção (owners)

**`Sources/FeedMineRuntime/RunwayController.swift`** — a demanda passa a ser lida da cobertura que a própria
política mediu (`RunwayPolicy.evaluate`): `.pressured(requiredCards:)` → `coverageDeficit`,
`.logicalPressure` → `logicalTailPressure`, e a evidência local é a reserva que o probe estabeleceu — um
`readySupply(_:)` que mapeia `.exact(count)` → `count` e `.atLeast(bound)` → o **piso** `bound` (nunca uma
contagem que o probe não provou; `AcquisitionDemand` continua recusando um déficit que não exceda essa
reserva). O caminho "probe maior até o teto e então recusa" foi removido. Cobertura medida como **saudável** e
cobertura **não medida** (`.unknown`) continuam recusando rede, e a ordem local-first continua obrigatória
(reserva pronta → supply local → preparação local → demanda, §12/§18 do design): a demanda segue exigindo o fim
estrutural do walk local, sem trabalho em voo e sem falha local pendente.

**`FeedMineApp/FeedMineApp/AppComposition.swift`** — `foreground()` reativa a apresentação corrente com
`driver.activateCurrentPresentation(resources:)` (o mesmo mecanismo de `restoreAndActivate`/`launch`) em vez de
`drive` com a observação zerada. Isso devolve ao runway a observação do leitor na âncora corrente
(`.stationary`: sem gesto, sem evento de viewport, sem mexer na lista admitida) e a oportunidade acontece.

## 3. Regressões

- **Falhava antes / passa agora** (`Tests/FeedMineRuntimeTests/RunwayControllerTests.swift`):
  `testLogicalTailDemandsFromMeasuredPressureWithoutExactProbeEvidence` — pressão lógica + lane local gasta +
  leitura saturada. O teste que a substitui agora (`testUnknownHealthyAndSaturatedStockNeverEscalate`) mantém
  as metades legítimas (unknown/saudável/saturado não escalam por medição). Antes deste commit, o teste
  devolvia o probe do teto em vez da demanda (saída literal na §4).
- **Oportunidade sem gesto** (`Tests/FeedMineCompositionTests/FeedRunwayDriverTests.swift`):
  `testForegroundReactivationIsAnOpportunityWithoutViewportEvent` — depois de `markConsumptionInactive`, um
  `drive` puro não tem observação (`latestObservation == nil`, nenhum outstanding); a reativação devolve a
  observação na âncora do leitor e a produção acontece na mesma oportunidade (novo segmento publicado + a
  reposição pedida), sem evento de viewport. Este teste é uma **guarda** do mecanismo: ele passa também no
  controlador anterior (o que mudou no app é o *call site*), e é por isso que a evidência de falha-antes dele
  não existe no pacote — o `AppComposition` não é alvo do SwiftPM.
- `testNonexhaustedKnownPressureStaysLocalAndExhaustionForcesPostSettleMeasurement` foi **mantido** (com
  comentário explicando o porquê) em vez de reescrito: ver §6.

## 4. Verificação

```sh
swift build
swift test
swift test --filter "RunwayControllerTests|FeedRunwayDriverTests|FeedSessionRunwayTests|RunwayPolicyTests|MeasuredRunwayReserveTests"
git diff --check
```

- `swift build`: limpo (sem erros, sem avisos novos).
- Suíte do pacote: **`Executed 1399 tests, with 1 test skipped and 0 failures (0 unexpected) in 51.508
  (51.657) seconds`** (`Test Suite 'All tests' passed at 2026-10-15 21:55:21.569`).
- Suítes que nomeiam runway/driver/sessão: **86 testes, 0 falhas** (`RunwayControllerTests` 28,
  `FeedRunwayDriverTests` 40, `FeedSessionRunwayTests` 5, `RunwayPolicyTests` 10, `MeasuredRunwayReserveTests`
  3).
- Evidência de falha-antes (mesmo teste, controlador anterior — `RunwayController.swift` guardado no stash):

```text
RunwayControllerTests.swift:379: error: -[RunwayControllerTests testLogicalTailDemandsFromMeasuredPressureWithoutExactProbeEvidence]
  : failed - Pressão lógica medida pede rede sem prova exata:
  measure(RunwayMeasurementRequest(scope: RunwayScope(editionID: 00000000-...-000000000001, ...),
  observation: RunwayObservation(..., sampledAt: RunwayMonotonicTime(seconds: 2.0),
  activity: RunwayActivity.explicitTailApproach), readyProbeBound: 100, advance: nil))
```

e, depois da correção, `Executed 1 test, with 0 failures` para o mesmo teste. `git diff --check` limpo.

## 5. Não alterado (deliberadamente)

- `bench/**`, oráculos, driver do bench, corpus e critérios congelados.
- Owners de publicação/história; PD-4 (adjacência) e PD-5 (imutabilidade do segmento publicado).
- `RunwayPolicy` (a medição) e as constantes da reserva móvel (`minimumReserveCards: 32` em
  `AppComposition`, `reserveCards: 16`): a mudança é no *gate da demanda*, não na régua; nenhuma constante foi
  ajustada por gosto.
- `FeedMineAcquisition` (`AcquisitionDemand`/`ExhaustedLocalSupply`): a leitura saturada entra como o piso que
  o probe provou, então o invariante do inicializador (`required > readyCards`) segue válido.
- `FeedRunwayDriver` (FeedMineComposition): o contrato de execução causal (3R7) e a ordem local-first que ele
  depende continuam como estavam.
- A chamada de `activate()` continua limpando as amostras/episode (contrato existente, compartilhado com
  launch/restore): depois de um foreground o runway reaprende a taxa/latência nas primeiras oportunidades, e o
  piso de bootstrap (32) cobre esse intervalo.

## 6. Achado para o arquiteto (conflito entre a instrução literal e a ordem local-first)

A leitura literal do item 1 do gate ("o cursor local não precisa estar gasto") foi implementada e **medida**:
ela emite a demanda enquanto a lane local ainda pode produzir, e aí a oportunidade termina na aquisição — o
drain do driver devolve a apresentação quando a aquisição não muda supply e o trabalho local só rodaria na
próxima oportunidade. Com o controlador sem o gate do cursor, três testes legítimos da composição quebram:

```text
FeedRunwayDriverTests.swift:185: test01SemanticTailFullProductionLoop : XCTAssertEqual failed: ("1") is not equal to ("3")
FeedRunwayDriverTests.swift:206: test02LocalPresentationSurvivesSuspendedTailHTTP : ... ("1") is not equal to ("3")
FeedRunwayDriverTests.swift:223: test04LocalSupplyPrecedesNetwork : XCTAssertEqual failed: ("1") is not equal to ("2")
FeedRunwayDriverTests.swift:227: test04LocalSupplyPrecedesNetwork : ... ("[.exact(0), .exact(0)]") is not equal to ("[.exact(1), .exact(3)]")
```

`test04LocalSupplyPrecedesNetwork` é o nome literal da regra que o design declara obrigatória (§12/§18) e que o
3K4 registra ("Local-first is mandatory whenever a lane can progress"). Por isso a entrega mantém o gate do
cursor local gasto (**"a lane local não pode fechar o déficit"**) e remove o que o gate nomeava como
proibido — a exigência de uma **leitura exata abaixo do probe**. Se o arquiteto quiser mesmo a leitura literal
sem o gate, ela exige também mudar o drain do `FeedRunwayDriver` (hoje: uma aquisição sem mudança de supply
encerra a oportunidade), o que este gate não faz por ser outro owner.
