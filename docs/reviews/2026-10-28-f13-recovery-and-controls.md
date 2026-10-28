# F13 — recuperação e controles — 2026-10-28

Checkpoint posterior: [recuperação real e geometria](2026-10-28-f13-recovery-route.md) corrige
o deslocamento de 117 pt medido ao retirar o footer, usando o menu Mais estável. Rotas pt/en AX XXXL
aprovadas com delta zero; este documento preserva a evidência do incremento anterior.

Incremento sobre `ef485ed7`; F13 permanece aberta.

## Comportamento

Com regras efetivas, a recuperação aparece em idle, unavailable, deferred e fim de conteúdo.
Idle não anuncia busca em andamento nem esgotamento definitivo. O histórico publicado permanece
na mesma sequência; o callback continua condicionado a regras efetivas. Não há alteração de scheduler,
PD-4, seleção de fontes ou banco.

A jornada XCUI encontrou um problema real: o identificador da linha SwiftUI sobrescrevia o do botão
de remoção. A linha agora é um grupo de acessibilidade explícito, preservando a ação filha.

## Evidência

- RED idle: dois testes, três falhas esperadas; GREEN renderização inicial: 24/0.
- RED provisional: um teste, duas falhas esperadas; GREEN renderização final: 25/0.
- Suíte completa após o agrupamento AX: 1777 testes, um skip, zero falhas, 107,686 s.
- App iOS: `t5-ios-provisional-unit-tests`, 9 testes, zero falhas. Inclui lista vazia como no-op
  e lançamento sem supply com recuperação após remoção, preservando a associação e preferências.
- Build da correção AX: `t6-ui-source-row-ax-build`, exit 0.
  Runner final: `t6-ui-native-margin-build`, exit 0; produção sem alterações entre eles. Manifesto registra revisão base,
  patch compilado, hashes e reserva de 700 MiB. Não é benchmark nem build de release.
- Português: `t6-source-controls-pt-ax-tests`, resultado oficial Passed, 1/0. Cancelar não cria
  regra; confirmar mantém a carta; master off guarda a regra; terminate/launch conserva regra,
  switch e carta; remover conserva o switch desligado e a mesma carta. Captura inspecionada.
- As tentativas XCUI anteriores foram preservadas: as duas primeiras diagnosticaram a interação do
  popover nativo; a terceira comprovou cancelar sem criar regra, confirmar sem mover a carta e
  revelou a colisão AX. Não são resultados GREEN.

- Inglês AX XXXL: `t6-source-controls-en-large-capacity-tests`, resultado oficial Passed, 1/0,
  exit 0, sem atingir a reserva (mínimo 916561920 bytes livres). Mesmas verificações de processo e
  carta; altura do nome >30 pt comprova ampliação real. Captura inspecionada: fonte e ação legíveis,
  com quebras de linha no tamanho máximo. O app e bundle unitário têm os mesmos hashes dos testes
  pt; o runner final só ajusta o gesto externo de cancelamento.

- Regressão pt no runner final: `t6-source-controls-pt-final-tests`, resultado oficial Passed,
  1/0, exit 0, mínimo 978251776 bytes livres. Mesmo app, bundle unitário e runner da jornada en.

- App no build final: `t5-ios-recovery-final-unit-tests`, resultado oficial Passed, 9/0, exit 0,
  sem interrupção. Hashes coincidem com as duas jornadas finais.

## Revisão independente

Revisão somente leitura por subagente, conforme requesting-code-review, desde a base F13
`382edf73`/plano `e5f75031` até `ef485ed7` e patch atual: nenhum defeito crítico/importante
confirmado. A revisão não rodou testes. Apontou como aceitação pendente a geometria/viewport da
última carta durante transições do footer, além das jornadas A/B/contexto/recuperação e R4.
O relatório anterior foi reconciliado por referência a este checkpoint.

## Capacidade e tentativas ampliadas

A confirmação nativa com AX XXXL cobre o botão Done; as tentativas iniciais de cancelamento
não são GREEN. A captura `t6-en-large-native-confirmation.png` mostra a faixa externa direita.
O teste usa essa região e exige desaparecimento da confirmação e ausência de regra gravada.
Duas tentativas atravessaram a reserva de 700 MiB e o monitor as interrompeu; não foram contadas como PASS. A última delas chegou ao switch desligado com regra retida e à captura ampliada, mas não concluiu a reabertura. O xcresult interrompido não finalizou Info.plist; o log e o manifesto da interrupção permanecem como diagnóstico, sem resultado oficial aprovado.
Foi removido somente o cache inativo regenerável `.build/index-build/arm64-apple-macosx/debug/ModuleCache`
(160 MiB), e depois os intermediários inativos iOS e diretórios `*.build` do pacote,
sem tocar em produtos, xcresults, bancos ou simuladores. O manifesto
`recovery-intermediate-cleanup.json` registra caminhos e bytes da segunda limpeza. Logs/patches terminais foram
comprimidos em gzip com comparação integral dos bytes descomprimidos.

## Limites

A nova classe XCUI cobre controles e persistência de processo; não substitui publicação futura A/B,
item canônico compartilhado, contexto A→B→A ou recuperação pelo destino real da interface.
R4/histórico das palavras, revisão independente e gates B02/B04/B05 continuam pendentes.
B03/B06 e a guarda padrão de capacidade não foram alterados. `capacity-ready.json` foi preservado.
