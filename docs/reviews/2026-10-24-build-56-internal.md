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

- **Imagens (corrigido em 24/out, depois de uma medição errada)**: numa instalação limpa do build 56 — Release, catálogo publicado, 3 minutos de feed —, **307 de 883 cartas publicadas têm imagem (34,8%)** e 193 ativos foram gravados. A medição anterior ("0 de 573") veio de um contêiner reaproveitado entre reinstalações e **não se reproduz**; ela foi retirada como bloqueador.
  O defeito real, medido com o build de Debug (que compila a testemunha de mídia) em 4.145 assentamentos: **636 `ready-image`**, **1.942 `transient-failed` por `deadline`**, 1.560 sem imagem declarada, 7 `too-small`. Ou seja, a preparação funciona e é interrompida pelo prazo em cerca de três de cada quatro tentativas com imagem declarada.
- **Idioma**: o gate é por sistema de escrita. Texto em alfabeto latino de língua diferente (espanhol em canal `en`) continua passando; distinguir exige identificador de idioma, que esta rodada não adiciona.
- **Dispositivo físico**: nenhuma validação em iPhone. B06 segue NOT_RUN; nada aqui deve ser lido como aprovação física.
- **Vídeo**: superfície própria não demonstrada nesta rodada.
- **Distribuição externa**: não solicitada e não feita.

## Apêndice — o catálogo do build 56 é o mesmo dado que as evidências anteriores

O preflight exige um staging de bootstrap verificado, que este worktree não tinha. O
`build/catalog-bootstrap` existia no checkout principal; minha primeira busca olhou só os
worktrees, então regenerei o staging com o compilador V1 fixado por SHA-256 em vez de copiá-lo.
O resultado, comparado arquivo a arquivo com o catálogo que vinha sendo usado:

| Medida | Antigo (`e6da170e…`) | Novo (`1825fdae…`) |
|---|---|---|
| `catalog_source` | 77.443 | 77.443 |
| `catalog_node` | 6.450 | 6.450 |
| `catalog_placement` | 77.443 | 77.443 |
| Hash de conteúdo sobre `(key, language, media_kind, quality_score, title, request_url)` | `a0dfbeff2fc58c10e32ba708b67b2311` | `a0dfbeff2fc58c10e32ba708b67b2311` |
| `catalog_version` | 1792180662394189 | 1792868795281916 |

Conteúdo idêntico; só o selo de compilação difere, que é o que o próprio bootstrap declara
esperar. Portanto build 56 embarca o mesmo conjunto de fontes sobre o qual B01–B05 e as
medições de 77.443 fontes foram tomadas — não um dataset novo.

## Apêndice — o funil de imagem, medido com identidade de revisão

Execução única (Debug, contêiner limpo, English, catálogo publicado, 3 minutos, parâmetros
atuais), casando o traço de preparação com as cartas publicadas **por revisão**, não por
contagem agregada:

| Medida | Valor |
|---|---|
| Cartas publicadas | 941 |
| Publicadas com `media_key` | 303 (32,2%) |
| Tentativas com imagem declarada | 558 |
| Chegaram a `ready-image` | 276 |
| Morreram em `deadline` | 280 (50,2%) |
| `ready-image` publicadas | **276 de 276** |
| `ready-image` não publicadas | **0** |

Conclusão medida: não existe perda entre preparação e publicação — toda revisão que ficou
pronta virou carta com imagem. A perda está inteiramente na preparação: metade das tentativas
que declaravam imagem é cortada pelo prazo.

Correção de método, registrada porque quase virou conclusão errada: a primeira passada desse
mesmo join deu interseção zero. Era diferença de caixa no UUID — o traço grava maiúsculas, o
banco grava minúsculas. Normalizado, o resultado é o da tabela.

O que o leitor vê hoje: nos salvos há rótulo por linha (`Mídia indisponível`, `Mídia pendente`);
no feed, não. Uma carta cuja imagem foi cortada pelo prazo é indistinguível de uma fonte que
não declara imagem.
