# Build 48 no aparelho físico: imagem desenhada, rolagem exercitada — e o que ainda NÃO está certificado

Data: 2026-10-16. Este relatório registra a passagem da candidata interna **1.0 (48)** pelo iPhone 14 Plus do dono.
Ele **não** substitui B06, **não** certifica fluidez e **não** declara release externa.

## 0. Distinções que este relatório preserva, por escrito

| Afirmação | Estado |
|---|---|
| Build 48 no TestFlight | **Interna**, `VALID` e `IN_BETA_TESTING`. Sem distribuição externa e sem submissão à App Review |
| Jornada física de imagem | **PASS**, com controle negativo na mesma corrida (zero pixels da testemunha) |
| Rolagem real e movimento do leitor no aparelho | **EXECUTED** — o ponto de leitura mudou |
| Engasgos no aparelho | **MEDIDOS** (série crua). Causa **não** determinada |
| Fluidez | **NOT_CERTIFIED** |
| B06 (régua congelada, aparelho) | **NOT_RUN** |
| Reabertura sem tela de carregamento | **Ausente** desta build (produto em HOLD por decisão do arquiteto) |
| `com.feedmine.app` (app do dono) | **Não alterado**: nem instalação, nem lançamento, nem término, nem desinstalação por este trabalho |
| Evidência bruta | Identificada por SHA-256 nas §2 e §4 |

### Sobre onde a evidência vive

O log do aparelho está versionado em
`docs/reviews/evidence/2026-10-16-rodada-48/int48-physical-authorized.log` — o sha256 citado na §2 foi conferido já
contra essa cópia versionada. Os artefatos restantes citados (`/tmp/int48-physical-evidence/`,
`/tmp/int48-apple-confirmed.json`, os `.xcresult`) são **referências locais desta máquina, não arquivos
versionados no repositório**. Os hashes estão no texto para que uma cópia futura possa ser conferida contra eles.
Quem precisar de uma cópia durável deve **reproduzir** as corridas: a §2 tem o comando exato e a §4 tem a consulta
read-only à API da Apple. Nada aqui afirma que esses arquivos estejam preservados no Git.

## 1. Identidade

| Item | Valor |
|---|---|
| Candidata publicada | `1.0 (48)`, archive pareado com `03d05f5f4bfff9ec0ce6c3be3f4a78ef5073c38f` |
| Árvore | worktree exclusiva `/tmp/fm-int48-verify`, branch `release/1.0-build.48` |
| Código sob teste | `03d05f5f` (a mesma revisão do archive; estes relatórios são commits posteriores) |
| Aparelho | iPhone 14 Plus, iOS 18.6.2, UDID `<physical-device-udid>`, `devicectl` id `BBA4F656-…` |
| Bundle exercitado | `com.feedmine.development` (Debug). **`com.feedmine.app` nunca foi tocado**: nem instalação, nem lançamento, nem término, nem desinstalação |
| Ferramenta | Xcode 26.6, `xcodebuild test` com `-destination 'id=<physical-device-udid>'` |

Catálogo da corrida de mídia: o fixture local de duas fontes com PNG magenta 16:9 (o mesmo do simulador), porque o
teste exige um bitmap conhecido. Isto **não** mede download de fotos da internet — essa metade está na §5.

## 2. Resultado executado no aparelho

```sh
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -destination 'id=<physical-device-udid>' -derivedDataPath /tmp/fm-int48-dd -allowProvisioningUpdates \
  -only-testing:FeedMineUITests/CardImageJourneyUITests \
  -only-testing:FeedMineUITests/FluidityJourneyUITests
```

Saída bruta (`docs/reviews/evidence/2026-10-16-rodada-48/int48-physical-authorized.log`, sha256 `03fd1799f7d269ba9ac441812fa94bc0c4f58e276c47c313c8531b0c2bac37be` **dos bytes publicados antes da redação de identificadores** — o hash dos bytes da ponta atual e o registro por arquivo estão em `docs/reviews/evidence/REDACTION.md`):

```
CardImageJourneyUITests: Executed 2 tests, with 0 failures (0 unexpected)
FluidityJourneyUITests: Executed 1 test, with 0 failures (30.782 s)
FeedMineUITests.xctest:  Executed 3 tests, with 0 failures (0 unexpected) in 76.262 seconds
** TEST SUCCEEDED **
```

Result bundle: `/tmp/fm-int48-dd/Logs/Test/Test-FeedMine-2026.10.16_08-58-11--0700.xcresult`.
Anexos exportados em `/tmp/int48-physical-evidence/` (com `manifest.json` associando cada arquivo ao seu teste).

### 2.1 A imagem apareceu — pixels, não presença de arquivo

O teste de imagem amostra o retângulo do slot e conta a testemunha (magenta `#F4F`, que nenhuma paleta, texto ou
chrome do app desenha). Na carta com a imagem pronta, no aparelho:

```
JOURNEY drawn 1188x1020px sampled=302940 dominant=#F4F=191759 #FFF=97795 #E8E=1914 #F3F=1506 #000=1286
JOURNEY first frame=(15.75, 106.75, 396.5, 340.5) witness=193397/302940 bounds=(0.66,0.66,395.33,222.0) spacing=Optional(356.0)
JOURNEY settled window=ids=44A6AE8C-…,BADE71A7-…,6CE40E3C-…
JOURNEY away rounds=2 stillAdmitted=true
JOURNEY returned frame=(15.75, 137.75, 370.5, 327.83) witness=168332/272505
```

E o **controle** do mesmo arquivo, na mesma corrida, mediu na janela inteira:

```
JOURNEY drawn 1206x2622px sampled=790533 dominant=#FFE=611319 #FFF=140657 #FED=11896 #000=7018 #888=4598
```

ou seja: **zero** pixels da testemunha quando nenhuma mídia é declarada. O discriminador funciona nos dois sentidos.

Captura da tela do aparelho, tirada pelo XCTest, anexada ao resultado do teste
(`/tmp/int48-physical-evidence/2FAFF157-9309-4E89-B596-1B4125180A05.png`,
sha256 `49e770cd7c1581edbb346945dc0fa70a27e19fbda1a655a6920b1480846350d7`): bitmap magenta nos slots, cabeçalho da
fonte, manchete, resumo e data, e o contador de janela `received=0 completed=0 backward=0` no topo. O layout não se
moveu entre tirar a carta da janela e trazê-la de volta (`witness=193397` → `168332` com geometria preservada).

### 2.2 A rolagem no aparelho, crua — e o que ela mostra

Série publicada pelo próprio app durante a jornada dirigida no iPhone
(`/tmp/int48-physical-evidence/62CB9727-697D-4E49-9FE1-1AADCB3CBFBD.txt`,
sha256 `39c4fd95eae06dccc10c0174a4c9ef0396a49acdf3ef30bd4cc6ab8c5571a1fb`):

```
initial_card=1AABE4AE-2F18-488A-B875-AB604632E2DF
final_card=3FBA78EC-D7FB-4B4C-B120-EA4BC39E9215
after=budget_ms=16.67;seconds=27;series=49/0/0/3/128.5|45/0/0/2/213.6|60/0/0/0/19.1|47/5/8/0/39.8|58/1/1/0/35.0|
57/2/1/0/39.7|50/0/1/2/276.0|25/3/8/7/94.1|60/0/0/0/16.8|44/0/1/2/234.7|23/1/8/6/143.1|60/0/0/0/16.7|
47/0/0/3/125.8|26/0/3/8/127.8|51/1/2/2/58.8|44/0/1/1/252.0|17/0/3/10/145.4|52/1/3/1/50.0|45/0/1/1/236.4|
26/0/3/9/97.3|51/0/2/3/52.0|51/0/0/1/246.0|28/0/1/6/277.2|41/1/2/5/221.8|44/1/1/3/243.3|53/1/5/0/48.9|54/0/6/0/37.2
```

Leitura honesta, sem selo:

- **A jornada funcional aconteceu**: o ponto de leitura mudou (`initial_card` ≠ `final_card`) e o feed continuou
  oferecendo cartas.
- **Existem engasgos reais durante o consumo**, e eles são do aparelho, não do simulador: há segundos com 1 a 10
  quadros severos e pior intervalo de 221 a 277 ms. Isso é mais do que os 25 quadros severos em 31.479 quadros que
  a passagem de 2026-10-15 registrava em uso normal, mas **também** é uma jornada dirigida com gestos rápidos
  empilhados — as duas coisas não são a mesma condição e este relatório não as iguala.
- **Sem correlação não há causa**: a série diz *quando* o quadro atrasou, não *o que o app estava fazendo*. Atribuir
  esses intervalos à aquisição, à publicação, à decodificação de mídia ou à própria montagem da árvore de
  acessibilidade do XCTest exigiria a associação temporal que o gate de caracterização ainda vai produzir.
- Nenhum limiar foi criado a partir desta série. Ela informa; não aprova.

## 3. A automação que falhava era infraestrutura

A primeira tentativa (`/tmp/int48-physical-journeys.log`, sha256
`d08b538f1b72acc025ebb2aad2d6393a4d5913cf799102eba096a5e41b07cc35`) encerrou com
`The test runner failed to initialize for UI testing. Timed out while enabling automation mode.` — **depois** de
instalar o runner. Nada nesse momento testemunhava comportamento do FeedMine.

A tentativa seguinte, após o dono replugar o cabo (e sem alterar permissões, senha, Developer Mode ou
emparelhamento), passou. A diferença medida entre as duas é infraestrutura de conexão/autorização, **não** o
produto. Registro para o próximo: repetir tentativas idênticas de automação não informa; observar o estado físico do
aparelho e a negociação do serviço é o que informa.

Também foi observado, e descartado como prova, um lançamento do app de desenvolvimento por `devicectl --console`:
ele emitiu uma linha `feedmine frames=` por segundo (60 fps estáveis, com picos isolados de 130–350 ms) mas **nenhuma**
`feedmine journey`, então não testemunha cards, fontes ou mídia. A corrida terminou com `App terminated due to
signal 9` quando o cabo foi replugado. O artefato bruto dessa observação não foi persistido em arquivo; ela não é
citada como evidência neste relatório.

## 4. Publicação na Apple (read-only, do lado da Apple)

```
build 48  id=b4df9c3e-fbbf-4626-8e8b-442312bd5214  processingState=VALID  expired=false
          uploadedDate=2026-10-16T07:43:13-07:00  buildAudienceType=APP_STORE_ELIGIBLE
          internalBuildState=IN_BETA_TESTING  externalBuildState=READY_FOR_BETA_SUBMISSION
          betaGroups=[WawaTesters (isInternalGroup=true, hasAccessToAllBuilds=true)]
```

O grupo interno tem acesso a todas as builds; a Apple recusou a associação manual com
`Builds cannot be assigned to this internal group` e depois confirmou a associação automática. **Nenhum testador
externo foi adicionado e nenhuma submissão externa foi feita.** Resposta bruta em `/tmp/int48-apple-confirmed.json`.
Tag local `ios/1.0-build.48-03d05f5f` (não empurrada).

## 5. O que este relatório NÃO prova

- **B06 continua `NOT_RUN`.** O gate congelado exige a jornada B03 no aparelho com o corpus servido pelo Mac, sem
  travamentos de interface de 1 s ou mais, continuidade visual e tendência de recursos em sessão prolongada. Uma
  jornada de 30 s com fixture **não** é isso; o simulador também não aprova B06.
- **Fluidez não certificada.** Não há, aqui, prova de que o leitor não percebe travamento em uso normal. O que existe
  é a série medida, com engasgos, e a distinção entre medir e aprovar.
- **Download real de imagens**: a prova de pixel usou fixture local. Que os conteúdos baixem da internet no aparelho
  foi medido na passagem de 2026-10-15 (censo do contêiner: 147 blobs, 27.282.790 B) e **não** nesta rodada.
- **Reabertura sem loading**: o produto corrigido **não** está nesta build (arquiteto em HOLD; o desenho mínimo
  corrigido está em revisão separada). O critério da V1 continua pendente nesta candidata e isso está declarado.
- **Aparelho do dono**: `com.feedmine.app` (TestFlight) não foi instalado nem executado por este trabalho; o teste
  de jornada no aparelho usou o bundle de desenvolvimento.

## 6. Próximo passo, na ordem do arquiteto

Caracterizar os intervalos severos, não mascará-los: associar cada evento relevante ao gesto/posição, à janela
admitida e ao trabalho de aquisição/publicação/mídia no mesmo intervalo, separando arranque, foreground e consumo.
Três condições de um gate honesto: (a) o evento ocorre durante rolagem efetiva; (b) existe trabalho de backend
correspondente — ou a ausência dele é medida; (c) a explicação vem de dados, não de um número escolhido para
aprovar.
