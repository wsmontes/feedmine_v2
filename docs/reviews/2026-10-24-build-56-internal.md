# Build 56 — entrega interna, com evidência e limites

Data: 24/out/2026. Autor: OMP, operando sob coordenação de produto do ChatGPT (PM-012).
Escopo: build 56 como **validação interna**, não como candidato de produção.

## O que foi entregue

| Fato | Valor |
|---|---|
| Commit | `1fe0afaf811637307fcbc2dd73d1d5085028dc94` |
| Branch | `release/build-56` |
| Build | `1.0 (56)`, `CFBundleIdentifier com.feedmine.app` |
| Assinatura | `Apple Distribution: Wagner Montes`, TeamIdentifier `955573A4YH`, `codesign --verify --deep --strict` OK |
| Catálogo | par verificado: `catalog.sqlite` 117.993.472 bytes, sha256 `1825fdae…`, revision 5, 77.443 fontes, 118 OPML |
| TestFlight | `VALID`, `internalBuildState = IN_BETA_TESTING`, `externalBuildState = READY_FOR_BETA_SUBMISSION` |
| Tag local | `ios/1.0-build.56-1fe0afaf` |

## Correções, com a medida que as sustenta

1. **Idioma respeitado na admissão** (`0d91b9f6`). Antes: com só English selecionado, o feed publicava "Архитектура капитала" de fonte rotulada `en`. Depois: 26 manchetes cirílicas adquiridas, **0 publicadas**.
2. **Cobertura do String Catalog** (`e526b08f`). 55 literais ganharam inglês e 4 ganharam português; recontagem: zero literais não interpolados sem entrada. Rótulos como "Tocar episódio" viraram "Play episode".
3. **Falha de tentativa ≠ feed falhado; falha de leitura ≠ biblioteca vazia** (`95a3ec22`). 13/13 em `FeedPresentationStateTests`; salvo sobreviveu a relançamento.
4. **Plural** (`6b27bca5`): "1 story ready for you".
5. **Aviso da V1 em um só idioma** (`d8600f2c`): o corpo estava em português numa UI em inglês.
6. **Cobertura real do alvo de testes do app** (`b7e0f141`): `CompositionTests` 118/0, `** TEST SUCCEEDED **`.

## Verificação executada

- SwiftPM: 1.653 testes, 0 falhas, 1 skip.
- `FeedMineAppTests/CompositionTests`: 118 testes, 0 falhas.
- App Release no simulador (iPhone 17 Pro, iOS 26.5), catálogo publicado, sem fixtures: onboarding, feed, áudio com mini player, leitor, salvar/relançar, aviso e importação da V1 com `user.sqlite` de formato V1.
- Archive verificado pelo preflight P0C (bytes, sha, contagem física, inventário OPML, ausência de `bench_corpus`), export e upload com pareamento impresso.

## Limitações declaradas

- **Imagens**: nesta instalação, 573 cartas publicadas e **0 com imagem**; nenhum arquivo de mídia foi materializado, apesar de 7.900 revisões do supply com candidato de imagem e 568 adiamentos. É bloqueador do candidato de produção; o build 56 não o resolve.
- **Idioma**: o gate é por sistema de escrita. Texto em alfabeto latino de língua diferente (espanhol em canal `en`) continua passando; distinguir exige identificador de idioma, que esta rodada não adiciona.
- **Dispositivo físico**: nenhuma validação em iPhone. B06 segue NOT_RUN; nada aqui deve ser lido como aprovação física.
- **Vídeo**: superfície própria não demonstrada nesta rodada.
- **Distribuição externa**: não solicitada e não feita.
