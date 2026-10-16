# Jornada de rolagem e diagnóstico de quadros — 2026-10-16

## Decisão e limites

**Fluidez NOT_CERTIFIED. B06 NOT_RUN.** A jornada funcional não certifica desempenho.

O arquiteto aprovou a revisão como instrumento diagnóstico e rejeitou os tetos do WIP:
90 quadros severos, razão 0,25 e pior intervalo 250 ms, derivados de quatro corridas mais uma margem escolhida
de 30%. Um baseline lento não é contrato de experiência. Também não se adotou `zero severe` como substituto.
Verdict: [conversa do arquiteto](https://chatgpt.com/g/g-p-6a584059c8f0819180f2f1d07b1ccbbe-feedmine/c/6ad16b59-5a88-83e8-9235-71ceb8048e95).

A exigência original permanece: `feedmine/docs/release/1.0-checklist.md:3114-3132` exige cards prontos,
imagens desenhadas, rolagem sem engasgos e reabertura imediata. Uma candidata interna de observabilidade não fecha
esses requisitos nem autoriza release externa.

## Implementação

- `FeedFrameMeter.swift`: usa o orçamento do display também no registro, em vez de registrar sempre 60 Hz;
  mantém o histórico da série somente em DEBUG e apenas com captura ligada. O primeiro callback inicia a janela
  de amostragem; não é apresentado como um segundo inteiro desde o timestamp zero do display link.
- A linha `feedmine frames=` preserva os campos consumidos pelo instrumento do aparelho e acrescenta `budget_ms`.
  O amostrador de jornada usa o mesmo callback existente, sem segundo timer.
- `FeedFrameEvidenceSurface` expõe a série para a jornada DEBUG. Em Release não há superfície nem histórico.
- `foreground()` reinicia o medidor existente, de forma idempotente. Nenhuma política de seleção, aquisição,
  publicação, ordenação ou layout foi alterada por esta frente.
- `FluidityJourneyUITests` exerce seis gestos, exige outro ponto de leitura visível e anexa screenshot e série.
  Os seis gestos são a carga do cenário, não limiar de qualidade. O teste não chama a proporção de callbacks
  atrasados de métrica de hitch da Apple e não afirma que callbacks equivalem a pixels efetivamente apresentados.
- Foram removidos o teto arbitrário, os controles de valores copiados e a tentativa de usar `XCTHitchMetric`
  sem obter medição no ambiente anterior. Não há novo selo de fluidez em seu lugar.

## Ambiente e corpus

Mac arm64, Xcode 26.6, simulador iOS 26.5, iPhone 17 Pro de teste
`26AAAE22-70DD-4768-B63C-5058E0737C75`; worktree isolada `/tmp/fm-int48-verify`.
Fixture local com 95 itens por fonte, duas fontes de desenvolvimento; imagem magenta no teste de mídia e controle
sem declaração de imagem. Não é uma avaliação de diversidade ou de download pela internet.

## Evidência executada

Na integração antes do ajuste inicial da janela de amostragem:

```sh
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'id=26AAAE22-70DD-4768-B63C-5058E0737C75' -derivedDataPath /tmp/fm-int48-dd \
  -only-testing:FeedMineUITests/CardImageJourneyUITests \
  -only-testing:FeedMineUITests/FluidityJourneyUITests \
  -only-testing:FeedMineAppTests/FeedFrameBudgetTests \
  -only-testing:FeedMineAppTests/CompositionTests
```

Saída bruta em `/tmp/int48-combined-journeys.log`:

```
CompositionTests: Executed 64 tests, with 0 failures (194.197 s)
FeedFrameBudgetTests: Executed 3 tests, with 0 failures
CardImageJourneyUITests: Executed 2 tests, with 0 failures (38.319 s)
FluidityJourneyUITests: Executed 1 test, with 0 failures (28.513 s)
** TEST SUCCEEDED **
```

A validação final após o ajuste do relógio é registrada no relatório de entrega desta candidata, não inferida
pelos resultados acima. Capturas e séries estão no `.xcresult` indicado pelo log.

## Aparelho físico: tentativa e bloqueio observado

O iPhone 14 Plus, iOS 18.6.2, UDID `00008110-00067D861486201E`, foi reconhecido, pareado por cabo e com Developer
Mode ativo. `xcodebuild test` das duas classes de jornada, na candidata `ec9016aa`, instalou o runner, mas encerrou:

```
The test runner failed to initialize for UI testing.
Timed out while enabling automation mode.
** TEST FAILED **
```

Log: `/tmp/int48-physical-journeys.log`. **Jornadas físicas desta tentativa: NOT_RUN**, não falha atribuída ao
produto. `devicectl device info lockState` informou `passcodeRequired: false`, `unlockedSinceBoot: true`.
Não foram alteradas permissões para contornar o bloqueio. A ausência de `idevicescreenshot` não demonstra que
capturas via XCTest sejam impossíveis; essa rota ainda precisa de automação operacional no aparelho.

## Próxima prova de produto

Correlacionar intervalos monotônicos severos com gestos/posição, janela admitida, aquisição, publicação e mídia no
mesmo período no aparelho. Separar arranque, foreground e consumo. Correlação temporal não estabelece causalidade.
Nenhum cache, fila, scheduler ou mudança de layout foi criado para mascarar engasgos não explicados.
