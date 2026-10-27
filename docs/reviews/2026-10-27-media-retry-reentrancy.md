# Retry de mídia: revalidação após autorização assíncrona

Base: `ef5d7999`, branch `product/nf04-tail-truth`. Correção no owner existente,
`MediaPrefetcher.prefetch`; nenhum limiar, deadline, limite de concorrência, contrato de imagem ou
regra de publicação alterado.

## Defeito reproduzido

`prefetch` filtrava revisões prontas/em voo/em backoff antes de chamar `await authorizeRetries(due)`.
Essa suspensão permite outra oportunidade de preparação entrar no mesmo ator. Ao retomar, a primeira
usava a lista antiga sem consultar o estado atual.

Teste determinístico com barreira, sem sleeps:

1. Primeiro fetch falha; a revisão fica em retry com prazo 10.
2. Relógio controlado avança a 10; a primeira oportunidade de retry espera na autorização.
3. Uma segunda oportunidade recebe autorização, baixa a imagem e conclui a revisão.
4. A barreira libera a primeira autorização. Antes da correção, ela aceitava a revisão já pronta e
   fazia **um terceiro fetch**.

RED medido: 1 teste, **2 falhas** — lista aceita deveria ser vazia, mas continha a revisão;
contador de fetches deveria ser 2, mas era **3**. Log preservado em
`evidence/2026-10-27-media-retry/red.log`.

## Correção

Após a autorização, reconsultar aposentadoria do owner, readiness, trabalho em voo e backoff com
relógio atualizado antes de registrar witness ou criar trabalho. Isso também cobre mudanças nas
revisões da lista explícita enquanto a autorização de outros retries estava suspensa.

Não há novo scheduler, download owner, índice ou política. `acquireSingleFlight` continua sendo o
owner do download, usado tanto pela oferta quanto pelos salvos. O contrato dos salvos não mudou.

## Verificação

- Reserva antes do fix: **24 testes, 0 falhas**, build incremental em `.build/index-build`.
- RED do caso novo: **1 teste, 2 falhas**, demonstrando download redundante.
- `swift test --scratch-path .build/index-build --disable-index-store --jobs 2 --filter
  'MediaPrefetcher|PreparedReserve'`: **37 testes, 0 falhas** (1,008 s), incluindo regressão nova.
  Log em `evidence/2026-10-27-media-retry/green.log`.
- Revisão independente dos dois arquivos: nenhum defeito acionável encontrado. Cobertura específica
  de retirement/em voo/backoff durante autorização foi sugerida como melhoria de testes; o cenário
  causal desta correção cobre conclusão bem-sucedida durante a suspensão.

O primeiro comando no sandbox falhou ao acessar o cache do compilador; a execução com acesso aprovado
usou o cache existente. Nenhum simulador foi iniciado e nenhum cache/evidência foi removido.

## Pendências preservadas

O residual P1 da reserva não foi fechado: os 16 extras podem pertencer todos à fonte incompatível com
a cauda. O teste da reserva demonstra concessão limitada, não liveness editorial geral. A política
proíbe preparar indefinidamente; o teto continua intacto. O fix de retry resolve desperdício de trabalho,
não esse limite de seleção.

B03 continua FAIL. Nenhum ensaio de UI, build de app, gate ou distribuição foi executado nesta rodada.

Suíte completa concluída na árvore corrigida:
`swift test --scratch-path .build/index-build --disable-index-store --jobs 2` —
**1741 testes, 1 pulado, 0 falhas**, 104,666 s. Log preservado em
`evidence/2026-10-27-media-retry/package.log`. Esta é prova do pacote; não compila `AppComposition`
nem executa jornadas de UI. Disco ao término: **686 MiB** livres.
