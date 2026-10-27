# Fila de mídia: validar de novo ao iniciar o item

Base: `268c9594`, branch `product/nf04-tail-truth`.

## Defeito causal

A revalidação após autorização de retry não cobre outra suspensão: o tempo de uma revisão aceita
aguardando atrás de outras em `prepareAll`. Cada oportunidade tem sua fila; outra pode preparar a
mesma revisão enquanto a primeira ainda espera num item anterior. `prepare` iniciava o item da
fila antiga sem consultar a decisão/backoff mais recente.

Regressão determinística, sem sleeps:

1. Uma oportunidade aceita `[slow, queued]`, com limite de um download; `slow` espera em uma barreira.
2. Outra oportunidade prepara `queued` e termina — em uma variante, com imagem pronta; em outra,
   com falha transitória e backoff de 30 s. Relógio da política fixo em zero.
3. Liberar `slow` permite à fila original chegar a `queued`.
4. Antes da correção, **ambas as variantes faziam um segundo fetch de queued**.

RED: 1 teste, **2 falhas**, uma por variante. Log preservado em
`evidence/2026-10-27-media-queue/red.log`.

## Correção

`prepare` reconsulta readiness e prazo de retry antes de entrar no download compartilhado.
O item já decidido ou ainda em backoff não cria novo trabalho nem um segundo settlement.
O caminho explícito de salvos continua ignorando os atalhos de supply, como exige seu contrato.
Nenhum limite de concorrência, prazo, orçamento, teto de reserva ou política de seleção mudou.

## Verificação

- `swift test --scratch-path .build/index-build --disable-index-store --jobs 2 --filter
  'MediaPrefetcher|PreparedReserve'`: **38 testes, 0 falhas**, 1,315 s.
- Revisão independente dos dois arquivos: nenhum defeito acionável encontrado.
- `git diff --check`: sem erros.
- Logs red/green preservados no diretório de evidência acima.

O teste prova trabalho concluído enquanto um item aguarda na fila; não é ensaio de throughput,
não resolve o residual P1 da seleção e não reclassifica B03. Sem simulador, limpeza ou distribuição.

Suíte completa da árvore corrigida: **1742 testes, 1 pulado, 0 falhas**, 108,543 s,
com `swift test --scratch-path .build/index-build --disable-index-store --jobs 2`.
Log integral comprimido em `evidence/2026-10-27-media-queue/package.log.gz`.
Os 6 hashes de `bench/EVALUATOR.sha256` continuam válidos. Prova de pacote, sem build/teste do app.
