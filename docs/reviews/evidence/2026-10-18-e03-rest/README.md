# E03 — repouso de dez minutos, chegada tardia e retorno distante

Exercício complementar à régua congelada (não altera o driver, o corpus nem o oráculo do benchmark). Vive em
`FeedMineUITests/FeedMineUITests.swift` como
`testTenMinuteRestKeepsTheCardThroughLateSupplyAndADistantReturn`.

## Desenho

- Fixture local declarada (`FEEDMINE_USE_DEVELOPMENT_FEEDS=1`, `FEEDMINE_LOCAL_FEEDS=1`, `FEEDMINE_SKIP_ONBOARDING=1`),
  40 itens por feed, segundo endpoint atrasado (`FEEDMINE_SLOW_FEED_SECONDS=30`).
- O teste espera a oferta do endpoint lento chegar à janela (≥5 cartas) antes de escolher a âncora.
- **Repouso:** lê o frame da carta âncora em três instantes (início, 5 min, 10 min) e compara `minY` e altura com
  tolerância de 1 pt. Nenhum gesto é enviado nesse intervalo.
- **Retorno distante:** rola para cima até a carta do topo mudar (máx. 30 gestos), depois desce até reencontrar a
  âncora, por identidade, e registra o deslocamento vertical exato.
- Gated por `FEEDMINE_LONG_REST=1`; no runner XCTest a variável precisa do prefixo `TEST_RUNNER_`:
  `TEST_RUNNER_FEEDMINE_LONG_REST=1 xcodebuild … test`.

## O que este exercício NÃO cobre

- Pressão de memória real: o aviso é um sinal do sistema, não um gesto que o harness possa injetar.
- Asset indisponível: coberto por `CardImageJourneyUITests` e pela captura de ócio de B04 (pixels desenhados).
- O controle real "Voltar ao início": coberto por `EndOfContentUITests` (bloco `feed-end-return-to-start`).

## Execução 1 (`run.log`, 2026-10-18 18:01–18:12)

- Repouso: **estável nos três instantes** (nenhuma falha nas comparações de `minY`/altura).
- O feed permaneceu com **uma única carta** durante os dez minutos: o endpoint lento em 600 s não entregou oferta
  nova e a preparação seguiu "Preparando" até o fim do repouso (capturas `e03-rest-start`/`e03-rest-end`).
- Por isso o "scroll distante" não saiu da carta (30 gestos com uma carta não movem o feed) — falha do exercício,
  não do produto nesse ponto.
- O retorno, quando medido, ficou **16 pt** abaixo do início: é a margem de conteúdo de `NativeFeedTargets.padding`
  já registrada na revisão de execução (decisão do dono, não violação). O exercício passou a registrar o delta em
  vez de escondê-lo numa tolerância.

## Execução 2 (`run2.log`)

Repetição com chegada tardia em 30 s e espera explícita por ≥5 cartas. O binário do test runner era **stale**
(instalado numa execução anterior; o bundle compilado tinha o código novo, o instalado não). Aprendizado: depois de
editar testes, `xcrun simctl uninstall <udid> com.feedmine.development[.FeedMineUITests.xctrunner]` antes de
repetir; sem isso o runner antigo é relançado mesmo com `test` (só código do app, não do teste, é reinstalado).

## Execução 3 (`run3.log`, runner reinstalado)

- Configuração: 40 itens por feed, endpoint lento em 30 s.
- **Achado:** a janela permaneceu com **uma única carta** por mais de 15 minutos (a espera de 300 s por ≥5 cartas
  falhou; as capturas mostram uma carta e a área abaixo vazia). O mesmo endpoint lento, com 6 itens e 10 s, cresce
  normalmente (o teste `testPublicationAfterTheFollowUpWindowStillReachesTheWindow` e a execução 4). Causa **não
  isolada**: documento maior, atraso maior ou interação entre os dois. Fica registrado como observação para o dono,
  não como veredito de produto — B03, com 475 fontes, não exibe o mesmo estado.
- O scroll distante não pôde ser medido (uma carta não sai do lugar) e o delta de 16 pt foi lido ao voltar ao topo
  absoluto: `start=121.75 returned=137.75`.

## Execução 4 (`run4.log`) — PASS

- Configuração: 6 itens por feed, endpoint lento em 10 s (a mesma que o teste de publicação tardia já prova).
- **Repouso:** estável nos três instantes (início, 5 min, 10 min), `minY` e altura com tolerância de 1 pt.
- **Chegada tardia:** a oferta do endpoint lento chegou à janela sem gesto (≥2 cartas).
- **Retorno distante:** a carta âncora foi reencontrada por identidade depois de 30 gestos para cima e até 40 para
  baixo; delta vertical **16,0 pt**, exatamente a margem de conteúdo de `NativeFeedTargets.padding` já registrada
  (decisão do dono, não violação). O valor fica no log como `E03_OFFSET` em vez de escondido numa tolerância.
- Duração: 631 s. Capturas anexadas: `e03-rest-start`, `e03-rest-end`, `e03-distant-return`.

## Execução 5 (`run5`, 2026-10-19) — delta reproduzível; posição ainda PARCIAL

- Mesma configuração da execução 4 (6 itens, endpoint lento em 10 s), com o critério de offset apertado de “até
  20 pt” para **16 pt ± 1**.
- Repouso estável (início/5 min/10 min, ±1 pt), chegada tardia sem gesto, rolagem distante e retorno por identidade.
- `E03_OFFSET start=121.75 returned=137.75 delta=16.0` → PASS (631,9 s). O deslocamento é exatamente a margem de
  conteúdo de `NativeFeedTargets.padding`; qualquer outro sinal/magnitude falha.
- **Classificação mantida: PARCIAL quanto à posição.** O Codex não registrou aprovação do dono para trocar o
  requisito de preservar a posição em ±1; 16±1 prova que o deslocamento é reproduzível, não que o requisito
  anterior foi cumprido. O repouso estável (0 pt) e o retorno deslocado (16 pt) ficam separados. Antes de mexer em
  layout ou tolerância, investigar o contrato de coordenadas/padding.
- **Memória:** pressão real não é injetável pelo XCUITest (é um sinal do sistema); permanece **NOT_RUN**, não
  convertido em PASS. **Asset indisponível:** coberto pela demolição offline de `ready → pending` em
  `SavedMediaCoordinatorTests.testOfflinePurgeDemotesReadyInsteadOfClaimingAvailable` e por
  `CardImageJourneyUITests`/B04 para os pixels desenhados.
