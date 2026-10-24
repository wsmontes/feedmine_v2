# Handoff — OMP → Codex, 24/out/2026

Leia de cima para baixo. O que está aqui foi medido nesta sessão; onde eu errei, está marcado como erro, para não ser repetido.

## 1. Estado agora

| Item | Valor |
|---|---|
| Worktree usado | `/Users/wagnersilvamontes/.codex/worktrees/feedmine-reader-position/feedmine_v2` |
| Branch de trabalho | `product/integrity-20261024` @ `a7a95787` (publicada) |
| Branch de release | `release/build-56` @ `cede37f6` (publicada) — build cortado de `1fe0afaf` |
| Tag do build | `ios/1.0-build.56-1fe0afaf` (publicada no origin) |
| TestFlight | build `1.0 (56)`, `VALID`, `internalBuildState = IN_BETA_TESTING`, externo `READY_FOR_BETA_SUBMISSION` |
| Disco | **3,6 GB livres** — insuficiente para archive (≈3 GB + margem). Limpe antes de qualquer build. |

Nada está em voo: nenhum agente meu rodando, nenhum patch pendente.

## 2. O que foi entregue e verificado (não refaça)

| Commit | Correção | Como foi verificado |
|---|---|---|
| `0d91b9f6` | Gate de idioma **no texto** na admissão (`ContentScriptEligibility` + `ReaderFilterEligibility`) | 6 testes de domínio + 9 de editorial; instalação limpa: 26 manchetes cirílicas adquiridas, **0 publicadas** |
| `e526b08f` | 55 literais ganharam inglês, 4 ganharam português no String Catalog | recontagem: zero literais não interpolados sem entrada; rótulos viraram "Play episode" |
| `95a3ec22` | Falha de tentativa ≠ feed falhado; falha de leitura ≠ biblioteca vazia | `FeedPresentationStateTests` 13/13; salvo sobreviveu a relançamento |
| `b7e0f141` | Alvo de testes do app realmente executado | `FeedMineAppTests/CompositionTests` 118/0, `** TEST SUCCEEDED **` |
| `6b27bca5` | Plural "1 story ready for you" | capturado na tela de preparação |
| `d8600f2c` | Aviso da V1 em um só idioma | instalação com `user.sqlite` V1 sintético: importou 1 caixa/fonte/coleção, reportou salvos inacessíveis |
| `2cde7f32` | Pílula de trabalho não cobre mais o conteúdo | cabeçalho assenta em `Feedmine ·`; `FeedScreenRenderingTests` 18/18 |
| `ea415ac2` | Constante do limite do primeiro ecrã separada da tolerância de mídia | build verde |
| `ce8878e1` | Removidos os dois retângulos cinza do onboarding | instalação limpa: nenhum skeleton na árvore de acessibilidade |
| `70178f3f` | Tolerância declarada de mídia 5 s → 12 s (PM-018) | 3 testes de derivação; efeito medido: cobertura 32,2% → 35,3%, deadline inalterado |

Relatório de entrega com limites declarados: `docs/reviews/2026-10-24-build-56-internal.md` (em `release/build-56`).

## 3. O que eu errei — não repita

1. **Medi "0 imagens" e era contêiner reaproveitado.** Instalação limpa dá 307/883 cartas com imagem (34,8%). Sempre meça em contêiner novo e diga a procedência do número.
2. **Juntei traço de mídia com banco por id e deu interseção zero** — era diferença de caixa no UUID (traço em maiúsculas, banco em minúsculas). Normalize antes de concluir qualquer perda.
3. **Tratei `deadline` de mídia como defeito a corrigir.** Não é: `SelectionEngine` filtra `readyRevisionIDs` (apenas revisões com apresentação preparada) e imagem declarada que falha assenta como `.unavailable`, nunca `textOnly`. O prazo é o que impede publicar carta sem a imagem que ela declarou. Não "conserte" isso encurtando ou esticando prazos.
4. **Desliguei o Wi-Fi da máquina para testar offline.** O simulador usa a rede do host; isso derruba a sessão inteira. O dono testa offline no aparelho.
5. **Alterei `policyInputs` achando que mudava só mídia** — o mesmo objeto alimenta o `RunwayController`. Se for medir a janela de mídia, dê a ela um `RunwayPolicyInputs` próprio.

## 4. Direção do dono (vale sobre qualquer plano anterior)

`coordination/DIRECTIVA-2026-10-24-shuffle-e-volume.md`, commit `a7a95787`. Em resumo:

- **Imagem nunca se sacrifica.** Publicar carta sem a imagem declarada para ganhar tempo está proibido.
- **A alavanca é volume**: manter estoque preparado muito maior que o consumo, para a carta incompleta perder o lugar dinamicamente.
- **Shuffle amplo é requisito**: distância máxima possível entre repetições de **tipo de conteúdo**, **tema** e **fonte**. Alternar algumas dezenas de fontes não conta.

Medição atual da fila publicada: tipo de mídia **distância 2,0 (mínima 1)**; fonte 19 (mínima 2); composição 936 áudio / 488 sem mídia / 1 vídeo em 1.425 cartas.

## 5. Próximas ações, em ordem

1. **Medir as quatro camadas na mesma execução**, antes de mexer em código: oferta declarada (candidatos de imagem), `ready-image` do traço, ativos em `Media/sha256`, cartas publicadas com `media_key`. Sem essa separação, "volume" pode só aumentar download pendente.
2. **v6 do sequenciamento**: distância máxima em tipo de mídia, tema e fonte. O que já existe e **não** deve ser reimplementado: suspensão de pendentes antes do ranking (`SelectionEngine`, `readyEligible`) e o `SelectionDiversityContext` da v5 (desempate suave sobre `.source/.provider/.subjects`). Falta a dimensão de tipo e tratar distância como exigência. v2–v5 ficam intactas para edições já publicadas.
3. **Profundidade de oferta à frente do cursor**, com a profundidade escolhida por medição — não por palpite.
4. **Cortar o próximo build** só com autorização; a tarefa inclui medir o embaralhamento novo e conferir que PD-4 continua com zero pares adjacentes.

Aceitação de cada passo: métrica antes/depois na fila publicada, PD-4 com zero pares adjacentes, e nenhuma carta publicada sem a imagem declarada.

## 6. Como rodar as coisas (o que custou tempo nesta sessão)

```bash
cd /Users/wagnersilvamontes/.codex/worktrees/feedmine-reader-position/feedmine_v2

# suíte do pacote (NÃO cobre o alvo do app)
swift test

# alvo de testes do APP (nome do alvo é FeedMineAppTests)
xcodebuild test -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine \
  -configuration Debug -destination 'platform=iOS Simulator,id=D4E09703-F0ED-4FBC-B0AF-7D68ADDC5A05' \
  -derivedDataPath .build/dd-product-tests -only-testing:FeedMineAppTests/CompositionTests

# app Release para simulador
xcodebuild -project FeedMineApp/FeedMineApp.xcodeproj -scheme FeedMine -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/dd-product-integrity build

# release: o preflight baixa o manifest público com o python do PATH, que não tem trust store
SSL_CERT_FILE=/etc/ssl/cert.pem \
ASC_KEY_ID=H3U55Z9WZ7 ASC_ISSUER_ID=0e1bd229-1284-4916-91d2-7bf989859bcc \
ASC_KEY_PATH=$HOME/.appstoreconnect/private_keys/AuthKey_H3U55Z9WZ7.p8 \
scripts/release-testflight.sh --no-upload      # sem --no-upload ele sobe e cria a tag
```

Gotchas:

- O script **recusa** árvore suja e exige `build/catalog-bootstrap/provenance.json`. Se faltar, gere com `scripts/bootstrap_catalog.py --compiler <_legacy_feedmine_v1/scripts/build_catalog.py> --compiler-sha256 … --identity-sha256 …` e instale o par em `Resources` (catalog.sqlite é gitignored; o descritor é commitado).
- O script **não empurra** branch nem tag: empurre `release/build-N` e `git push origin ios/<versão>-build.<N>-<sha>`.
- CFBundleVersion fica em `FeedMineApp/FeedMineApp/Info.plist`.
- No simulador, arrasto de dois pontos **não chega** ao app; use arrasto lento multi-ponto (`w.drag` com passos de ~45 px) para rolar. Scroll de roda também não chega.
- `xcrun simctl get_app_container <udid> com.feedmine.app data` → banco em `Library/Application Support/FeedMine/runtime.sqlite`, traço em `trace.jsonl` (traço só existe em build Debug, `#if DEBUG`).
- O app Debug tem bundle id **`com.feedmine.development`**; o Release usa `com.feedmine.app`.

## 7. Regras que não se negociam

- Não alterar `docs/product/DISCOVERY_ACCEPTANCE_BENCHMARK.md`, `bench/oracle.py` nem `bench/EVALUATOR.sha256`.
- Não publicar carta sem a imagem declarada para acelerar.
- Não mexer no alinhamento um-para-um de `LocalPreparedPublication` (`inputs` × `cardIDs`).
- Commits pequenos, cada um com a métrica que o justifica.

## 8. Pendências que dependem de terceiros

- **PM (ChatGPT):** se o limite do primeiro ecrã deve continuar acoplado à tolerância de mídia medida da associação (hoje: sim, acoplado em regime; só o valor pré-medição foi separado em `ea415ac2`).
- **Dono:** teste de offline real no aparelho; confirmação de que o embaralhamento novo atende ao critério de "distância máxima".
