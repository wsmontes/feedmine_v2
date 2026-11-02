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
