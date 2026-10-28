# F13 — validação iOS e continuidade local — 2026-10-28

F13 continua aberta. O bloqueio de capacidade para **estes testes unitários do app** foi contornado com
um build Debug sem símbolos, sem índices, um job e checkouts existentes. Não é build de release,
não é benchmark e não reduz a guarda de 3 GiB do ensaio padrão. Um monitor reservou 700 MiB livres
e podia interromper cada tentativa. Não houve apagamento/reset de simulador ou de bancos históricos.

## Evidência atual

- `SourceExclusionProductionTests`: **5 testes, 0 falhas**, 0,386 s. Inclui nova conexão ao banco,
  restauração integral, salvo/checkpoint preservados, nova supply e remoção sem duplicação; inclui
  também casos compatível/retido por PD-4 sob sequenciamento v6.
- Build-for-testing iOS: **exit 0**. `t4-ios-warm-pd4-build.json` guarda comando, revisão base e hash
  do patch compilado. O patch adjacente identifica as alterações não commitadas naquele instante.
- `FeedMineAppTests/ContentFilterTests`: **8 testes, 0 falhas**, 4,328 s. Resultado oficial `Passed`
  em `t4-ios-warm-pd4-tests-summary.json`, extraído do xcresult. O manifesto do teste guarda hashes
  dos executáveis, xctestrun e relatório de build; o xcresult original está preservado em
  `.build/f13-ios-tests/t4-ios-warm-pd4-tests.xcresult`.
- Destino: iPhone 17 Pro Max, simulador iOS 26.5, UDID `220FD546-698A-4DFE-A9E6-DD40135DED72`.
- Avaliador congelado: 6/6 hashes válidos; diff sem erros. `capacity-ready.json` permanece intocado.

Os oito testes executam dentro do app iOS. A prova warm cria **outra AppComposition no mesmo processo**
sobre o banco persistido: não representa matar/reabrir o processo nem um gesto XCUI. Ela confirma
restauração da Edition/âncora, registros e bookmark; A inédita bloqueada, B compatível publicada;
remoção libera A uma vez; duas oportunidades adicionais não duplicam as novas revisões. O prefixo,
CardRecords salvos e checkpoint permanecem iguais entre alterações da regra. O avanço de cauda é
intenção explícita de leitura; seu novo checkpoint é capturado antes da remoção e preservado depois.

## Correções e diagnóstico

O parse anterior não detectava uma referência a `ReaderToolbarPlacement`, helper interno de UI.
O build iOS falhou com esse símbolo inacessível. A tela usa agora `.topBarTrailing` do SwiftUI.
O corpo grande também excedeu o limite de inferência: a sheet de filtros foi extraída e o callback
recebeu tipo explícito. Não houve mudança na lógica de espera ou publicação para resolver compilação.

A primeira versão da prova warm esperava B após uma carta também de B. O trace mostrou B preparada
como texto e presente na supply, mas retida pela alternância PD-4. Ao liberar A, A→B podia publicar.
A causa não era falta de mídia nem motivo para relaxar PD-4. A prova positiva agora exclui a fonte
da cauda anterior, estabelecendo um predecessor compatível para B. A nova integração negativa
mantém o caso B→B e exige o hold; após remover a regra, as duas revisões publicam uma vez.
A fixture negativa usa v6 explicitamente; a tentativa inicial com versão legada foi preservada.

Os testes de diagnóstico percorreram a reserva publicada antes de exigir material novo; a espera
final é somente leitura quando a cauda não muda. Trace completo do caso retido foi exportado do
anexo XCTest para `t4-warm-pd4-held-trace.jsonl.gz`. Logs de falha e patches foram preservados em gzip
verificado, sem contá-los como GREEN. O ensaio inicial aprovado tinha 7 testes; o último tem 8.

## Trabalho ainda necessário

- Jornada XCUI por gesto, confirmação/cancelamento, pt/en, Dynamic Type, AX, item compartilhado A/B,
  troca de contexto e término/reabertura de processo. Ainda não existe prova equivalente a UX13 completo.
- Teste explícito da notificação de lista vazia como no-op.
- **Recuperação em idle:** o diagnóstico iOS atingiu `work=idle` sem nova publicação, enquanto o
  componente de recuperação atual só aparece com `.endOfContent`. Alvos de aquisição continuam
  autorizados apesar das exclusões. Acrescentar caso de renderização/fluxo que cubra ausência de
  supply com regras ativas em idle, sem declarar falsamente que houve falha de rede ou fim definitivo.
- R4/histórico dos filtros por palavras, revisão independente do conjunto e gates B02/B04/B05.
  B03 e B06 conservam seus resultados anteriores; nenhum benchmark foi executado aqui.

A suíte completa do pacote mais recente continua sendo a de 1772 testes do checkpoint anterior;
neste incremento de testes rodaram os 5 focados. Não se declara uma suíte completa nova por soma.
