# PD8-R1 — a oportunidade externa coalescida chega à descoberta

Branch: `gate/pd8-r1-coalesced-discovery-opportunity` · worktree `/private/tmp/fm-pd8r1` · base
`78a374288d38e5c965b9ecc9fe587ac8fe4dbd43`.

Ambiente: macOS Darwin 25.3.0 (arm64), Swift 6.3.3 (swiftlang-6.3.3.1.3), alvo `arm64-apple-macosx26.0`.
Corpus: o catálogo sintético de `progressiveFixture` (`Tests/FeedMineCompositionTests/ReaderDiscoveryPoolTests.swift:116`,
5 fontes `https://progress0000..0004.test/feed` no nó `topics/science`), sem rede real
(`ProgressiveDiscoveryURLProtocol`). Nada de `bench/` foi tocado.

Arquivos e hashes (sha256, ao fim do gate):

```
b11c816b59daf1592a744453172d5573c565158ad5152f11e23575f7b84ee771  Sources/FeedMineComposition/FeedRunwayDriver.swift
4affd1a6aff42e8df519173e24144d0cd48135b7592530c3ca7cd327d46a0205  Tests/FeedMineCompositionTests/ReaderDiscoveryPoolTests.swift
```

## 1. O contrato medido no código (antes da correção)

`FeedRunwayDriver.drive` tinha a página de catálogo **acima** do laço causal, e o caminho coalescido não voltava
para lá: `:193-197` marcava `reconsiderRequested` e retornava quando já havia execução em curso; o laço de
reconsideração (`:222-230`, `while true { … if reconsiderRequested { continue } }`) ficava **depois** do
`advanceDiscovery` (`:212-220`). O contrato escrito estava em `:199-200`:

> One catalogue page per caller opportunity, outside the causal drain. Coverage may settle this page through the
> existing planner; it cannot load the next page here.

Ele já dizia "per caller opportunity"; o código honrava apenas o chamador que **adquiriu** a execução. O chamador
que coagiu (chegou durante a página ou durante o dreno) recebia reconsideração causal e **nenhuma** página — a
oportunidade externa não chegava à descoberta. É exatamente o item 1 do §9 da revisão de 2026-10-15, agora medido.

## 2. Vermelho (código anterior, teste herdado)

```
$ swift test --filter testCoalescedCallerOpportunityStillOwnsItsCataloguePage
Test Case '-[FeedMineCompositionTests.ReaderDiscoveryPoolTests testCoalescedCallerOpportunityStillOwnsItsCataloguePage]' started.
/private/tmp/fm-pd8r1/Tests/FeedMineCompositionTests/ReaderDiscoveryPoolTests.swift:391: error: -[FeedMineCompositionTests.ReaderDiscoveryPoolTests testCoalescedCallerOpportunityStillOwnsItsCataloguePage] : XCTAssertEqual failed: ("1") is not equal to ("2") - The opportunity that coalesced into the drain still owns its page
/private/tmp/fm-pd8r1/Tests/FeedMineCompositionTests/ReaderDiscoveryPoolTests.swift:392: error: -[FeedMineCompositionTests.ReaderDiscoveryPoolTests testCoalescedCallerOpportunityStillOwnsItsCataloguePage] : XCTAssertGreaterThan failed: ("2") is not greater than ("2") - The coalesced opportunity reached the pool
Test Case '-[FeedMineCompositionTests.ReaderDiscoveryPoolTests testCoalescedCallerOpportunityStillOwnsItsCataloguePage]' failed (0.969 seconds).
      Executed 1 test, with 2 failures (0 unexpected) in 0.969 (0.969) seconds
```

As duas asserções que falham são a metade do contrato que não existia: `pages.served` continua `1` (a oportunidade
coalescida não serviu página) e o pool não cresce além da primeira página. A asserção intermediária
(`:389`, `pages.served == 1` — "um chamador coalescido não examina enquanto outro possui o exame") passa nos dois
lados: o coalescido nunca serve a página **dentro** da chamada dele.

## 3. Correção mínima (`Sources/FeedMineComposition/FeedRunwayDriver.swift`)

1. `:40-42` — `CausalExecution` ganha o fato que faltava: `callerPagesPending`, com o comentário de que cada
   oportunidade é um fato externo e possui exatamente uma página, e que **nada** dentro da execução soma a ele.
2. `:196-198` — o caminho coalescido (`causalExecution != nil`) passa a somar a oportunidade antes de retornar.
   É o mesmo lugar que já marcava `reconsiderRequested`; a oportunidade continua tratada como fato, não como tique.
3. `:201-203` — o chamador que adquire a execução é ele mesmo uma oportunidade, então começa devendo uma página
   (`callerPagesPending: 1`). Não há novo caminho para "alguém" pedir página.
4. `:216-241` — o laço. As páginas são servidas em `while causalExecution!.callerPagesPending > 0`, **fora** do
   dreno, uma por oportunidade, cada uma atrás do mesmo fence de revogação (`session.currentRunwayScope()` e
   `runway.snapshot().scope`, antes e depois). O laço causal continua depois, e o `continue` de saída agora é
   `reconsiderRequested || callerPagesPending > 0`: a conta zerada é o único jeito de a página ser devida, então
   uma conclusão interna (dreno, cobertura, fim de página) **não** autoriza página nenhuma.
5. `:244-253` — `serveCallerCataloguePage()`: o `advanceDiscovery` com as `discoveryExaminedCapacity` da
   oportunidade mais recente. Não há retry, timer, cache nem fila nova; o resultado `nil` é resposta àquela
   oportunidade, não uma oportunidade nova.

O contrato escrito mudou de lugar e de texto (`:218-222`): antes dizia que a cobertura não pode carregar a próxima
página dali; agora diz o mesmo **mais** o que faltava — que só uma oportunidade de chamador soma a
`callerPagesPending`, e que a página do chamador coalescido é servida antes das conclusões daquele passo. O
`docs/architecture/CONTINUOUS_FEED_RUNWAY_DESIGN.md` e o `ACQUISITION_DESIGN.md` foram varridos por
`advanceDiscovery|one page|next page|pages` e **não** afirmam nada sobre páginas por oportunidade: não há contrato
escrito contradito fora do arquivo.

## 4. Verde

```
$ swift build
Build complete! (2.58s)

$ swift test --filter testCoalescedCallerOpportunityStillOwnsItsCataloguePage
Test Case '-[FeedMineCompositionTests.ReaderDiscoveryPoolTests testCoalescedCallerOpportunityStillOwnsItsCataloguePage]' passed (0.141 seconds).
      Executed 1 test, with 0 failures (0 unexpected) in 0.141 (0.144) seconds

$ swift test --filter 'ReaderDiscoveryPoolTests|FeedRunwayDriverTests|SelectedSourceCoverageTests|FeedPresentationHandoffTests'
      Executed 87 tests, with 0 failures (0 unexpected) in 6.241 (6.252) seconds

$ swift test --filter 'FeedMineCompositionTests|ArchitectureSmokeTests'
      Executed 517 tests, with 0 failures (0 unexpected) in 18.799 (18.853) seconds
```

## 5. O que a correção preserva (com o teste que o mede)

- **Escopo revogado / alvo cancelado**: `testDiscoveryMetadataSuspensionCoalescesDriveAndDeactivationStopsWork`
  (desativação durante a página) e `testDeactivationDuringMediaBudgetCreationDoesNotAdvanceDiscovery` passam — em
  ambos o fence de revogação roda **antes** de a página devida ser servida, então o chamador coalescido não
  descobre nada depois da revogação. `testExistingDriverAndCoordinatorAcquireProgressivePagesBeyond120` mantém
  `checkpointRevision` intacto para o alvo revogado nas chamadas seguintes.
- **Local-first**: nenhuma escrita nova, nenhuma rede nova; o único `advanceDiscovery` continua sendo o que já
  existia, agora numa função própria chamada uma vez por oportunidade.
- **Déficit da reposição**: `FeedRunwayDriverTests` (40 casos) e `SelectedSourceCoverageTests` (18) verdes; o
  caminho causal do dreno (`driveCausalEffects`) não foi tocado.
- **Posição do leitor**: o teste novo fecha com `snapshot == f.initial` — a descoberta não move nem admite posição.

## 6. NOT_RUN

- **Aparelho físico / build 48**: não é escopo deste gate (PD8-R1 e R6-E não entram na build 48). Nada foi rodado
  em iPhone.
- **Suíte completa do pacote** (`swift test` sem filtro): NOT_RUN por escolha operacional — havia corrida no
  aparelho em curso e a regra é não competir; o alvo do módulo alterado mais `ArchitectureSmokeTests` (517 casos)
  foi o que rodou. Os módulos não tocados (`FeedMinePersistence`, `FeedMineAcquisition`, …) não têm caminho para o
  laço alterado, mas isso é inferência, não medição.
- **`FeedMineApp` (Xcode/UI tests)**: NOT_RUN — o alvo não compõe este pacote SwiftPM, e `AppComposition.swift`
  está sob posse de outro agente; não foi aberto nem lido.
- **R6-E**: não iniciado, conforme a ordem do arquiteto.
