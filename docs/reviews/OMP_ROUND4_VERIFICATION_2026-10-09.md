# Rodada 4 — verificação executada (OMP, 2026-10-09)

Base verificada: `origin/main` = `880191f` (fast-forward de `fe91c0f`, 10 commits, sem divergência; a árvore local
apontava para `fe91c0f`). Branch local: `phase/3r11a-media-acquisition-durable-asset`.
Ambiente: Swift 6.3.3 / Xcode 26.6 (17F113); simuladores iPhone 16 (iOS 26.5) e iPhone 17 Pro Max.

Escopo: o delta **não compilado** do Kiro (`8c31b83`, `e78786e`, `880191f`) sobre o código que o Codex testou
(`f8eb67e`), mais os itens que o fechamento marcou como "a revalidar" em
`docs/reviews/OMP_VALIDATION_2026-10-09.md` (seção *Pós-integração — main*).

## 1. Estado do build testável (executado nesta rodada)

| Verificação | Comando | Resultado |
|---|---|---|
| Pacote | `swift build` | PASS |
| Pacote | `swift test` | **828 testes / 0 falhas**, 21,07 s (era 827 em `f8eb67e`; +1 = teste novo do ranking) |
| Higiene | `git diff --check` | exit 0 |
| App, integração | `xcodebuild test` (Debug, iPhone 16) | **15 testes / 0 falhas** |
| App, XCUI | `xcodebuild -only-testing:FeedMineUITests test` | **3 testes / 0 falhas**, 71,6 s |
| Catálogo (release `catalog-v1`) | `scripts/fetch-catalog.sh` | 117.940.224 bytes, sha256 `c2ae483a7525fd2b6797855149eb6fb312abbed788549a90a7754121eb5c8629` |
| Clone limpo (remoto) | `git clone` + `scripts/fetch-catalog.sh` | sem ponteiro LFS; asset instalado e verificado |
| Clone limpo, app | `xcodebuild -configuration Release build` | **BUILD SUCCEEDED**; `FeedMine.app/catalog.sqlite` = 117.940.224 bytes |
| Catálogo ausente | clone limpo, `catalog.sqlite` movido + mesmo build | **BUILD FAILED**, exit 65, `error: …/Resources/catalog.sqlite: No such file or directory` |
| Medição in-app (T7) | `testCatalogNameSearchIsLiteralBoundedAndMeasured` | 77.443 fontes, `BBC limit 5`: **p50 25,9 ms / p95 27,5 ms** |

Warnings não bloqueantes (pré-existentes): 3× `'nonisolated(unsafe)' is unnecessary` em
`Sources/FeedMineSyndication/SyndicationMediaLocator.swift:85,86,89`; 1× `no calls to throwing functions occur within 'try'`
em `Sources/FeedMinePublication/PublicationCoordinator.swift:151`.

Evidências: `~/Documents/feedmine-evidence/2026-10-09/omp-round4/` — `pkg-test-828.log`,
`app-test-FULL-diskfull-1-failure.log`, `app-xcui-isolated-rerun-green.log`, `app-xcui-all-green.log`,
`clean-clone-fetch-and-release-build.log`, `missing-catalog-build-fails.log`,
`repro-persisted-key-brick.transcript.txt`, `fm-r4-launch1-devfeeds.png`, `fm-r4-launch2-bricked.png`;
`xcresult` em `/tmp/feedmine-omp-r4.xcresult` (vermelho por disco), `/tmp/feedmine-omp-r4-rerun.xcresult` e
`/tmp/feedmine-omp-r4-xcui.xcresult` (verdes).

### Catálogo: promessas conferidas contra os bytes reais

Confere com `CATALOG.md`: 77.443 fontes, 6.450 nós, 77.443 placements, `schema_version=2`,
`catalog_version=1789618085179441`, `user_version=0`; 30.391 fontes `media_kind='text'`.
`quality_score` **nunca é NULL** (mín. 34, máx. 100, média 74,65) — a chave `quality_score IS NULL` do ranking é
código morto sobre estes dados.

O índice `catalog_source_fts` (FTS5) está **completo e alinhado** com `catalog_source` (77.443 linhas,
`rowid == catalog_source.id`) e **não é usado por ninguém**. Custo medido em processo, catálogo real:

| consulta | LIKE `%q%` + ORDER BY (código atual) | FTS5 (`MATCH 'q*'`) |
|---|---|---|
| `news` | 37,4 ms | 2,9 ms |
| `bbc` | 44,8 ms | 1,2 ms |
| `guardian` | 67,8 ms | 0,2 ms |
| `a` (1 letra) | 60,0 ms | 65,0 ms |

`EXPLAIN QUERY PLAN` atual: `SCAN catalog_source` + `USE TEMP B-TREE FOR ORDER BY`. Não bloqueia na escala atual
(o app mede 26 ms com `limit 5`), mas é o índice que já viaja dentro do arquivo ficando sem uso.

### Smoke de produção: starter set real de 4 fontes (executado)

Build Debug de `880191f` instalado no iPhone 16, namespace novo, **sem** `FEEDMINE_USE_DEVELOPMENT_FEEDS`
(portanto o caminho de produção: catálogo + 4 fontes do starter set), app ocioso em foreground.

| Fato medido | Valor |
|---|---|
| `reader_preferences.source_keys` | as 4 chaves do catálogo (BBC News, BBC Science, NPR, Guardian World) |
| edições / segmentos / cards | 1 / 2 / **30** |
| origens / revisões / memberships | 64 / 64 / 64 |
| fontes distintas com supply | **2 de 4** (as duas BBC; 32 memberships cada) |
| alvos de aquisição com `checkpoint_revision >= 1` | **2 de 4**; NPR e Guardian com `checkpoint_revision = 0` e sem `checkpoint_blob` |
| mix visível | **BBC News 30 / 30** (NPR e Guardian: 0) |
| adjacência PD-4 (mesmo `source_id` em cards consecutivos do mesmo segmento) | **0 violações** |
| layouts / mídia | 23 `thumbnail` (22 chaves distintas) + 7 `textOnly`; 1,7 MB de blobs content-addressed no disco |
| timeline | todas as 64 origens com `first_observed_at` no mesmo instante (15:57:33) e nada depois em ~4 min |

Evidência visual: `~/Documents/feedmine-evidence/2026-10-09/omp-round4/fm-r4-production-4-catalog-sources.png`.

**D1 — observação com dado (provável defeito de produto/variedade, não confirmado como bug):** com o starter set de
4 fontes, uma abertura fria entrega 30 cards **100% BBC** e nunca chega a buscar NPR/Guardian enquanto o leitor fica
parado (≥4 min, `checkpoint_revision = 0` nos dois alvos, nenhuma origem nova após o instante inicial). Duas causas
possíveis, ainda não separadas: (a) o runway só planeja aquisição quando a reserva/cobertura exige, e as duas BBC já
saturam a reserva de 16 -> leitor parado nunca pede as outras fontes; (b) a recuperação automática (F08/F16) cobre
feed vazio, não alvo nunca executado. Agrava: os dois feeds BBC têm o **mesmo título congelado no catálogo**
(`catalog_source.title` = "BBC News" para `news/rss.xml` e para `science_and_environment/rss.xml`), então a primeira
tela parece de uma única redação. Repro para separar (a) de (b): abrir com 4 fontes do catálogo, ficar 5 min sem gesto
e asserir `checkpoint_revision >= 1` para os 4 alvos; repetir com um swipe para ver se o gesto libera os dois restantes.
Isso também transforma a prova de PD-4 de C3 em teste automatizado — a regra em si **passou** aqui (0 violações em 2 segmentos com dados reais).

## 2. Incidente de ambiente: disco cheio (ENOSPC) — não é defeito de código

`/System/Volumes/Data` chegou a **100% (≈120 MiB livres)** durante a rodada.

1. `xcodebuild test` completo terminou `exit 65`: `FeedMineUITests.testRealRSSNavigationLifecycleAndNetworkBlockedRelaunch`
   falhou nas linhas 77/78 ("Local cards must restore without network"), sem `ScrollView` na janela relançada.
2. A hierarquia AX anexada pelo XCUITest mostra a causa no próprio app:
   `Não foi possível carregar a seleção de fontes: storage(resultCode: 4618, message: "disk I/O error")`
   — `4618 = SQLITE_IOERR_CLOSE`, falha de I/O por falta de espaço, não lógica de restore.
3. Com 2,7 GiB livres: o mesmo teste isolado passou (`exit 0`) e a suíte XCUI inteira passou 3/3.
4. O build do clone limpo também falhou primeiro com `ld: write() failed, errno=28` e
   `failed to rename … .pcm-…` (índice do Swift).

Liberado (só build output regenerável; nenhuma evidência `.log`/`.xcresult`/`.png` apagada):
`/tmp/feedmine-t1-derived` (1,8 GB), `/tmp/feedmine-3q6-ios-build` (566 MB), `/tmp/feedmine-3r10-derived` (836 MB),
`/tmp/feedmine-foundation-build` (191 MB), `/tmp/feedmine-dev-export` (70 MB), clone intermediário,
`~/Library/Developer/Xcode/DerivedData` (393 MB). O disco voltou a encher durante o build do clone e ficou com ~0,8 GiB:
**o headroom de disco é o limitador operacional desta máquina** (os dados de dispositivo dos simuladores ocupam 5,8 GB e 6,4 GB).

## 3. Achados

Convenções: **DEFECT** contradiz o próprio contrato; **GAP** contrato declarado sem prova; **DOC-DRIFT** documento afirma o que o código não faz.

### 3.1 Bloqueante/major

**C1 — DEFECT (major): chave de fonte persistida que sumiu do catálogo inutiliza o app, sem caminho de reparo.**
`FeedMineApp/FeedMineApp/AppComposition.swift:56-64` + `FeedMineApp/FeedMineApp/TrustedFeeds.swift:55-57`.

- Causa: `TrustedFeed.resolve(keys:fallback:)` lança `missingDefaultSource(key)` para **qualquer** chave salva que o
  catálogo empacotado não contenha mais. O `catch` só define `startupFailure`, então `launch()` (`:69`) nunca abre
  associação; e como `self.preferences = preferences` (`:61`) é a instrução **posterior** à chamada que lança,
  `preferences` fica `nil` para sempre — o único caminho de reparo, `toggleSource` (`:123`,
  `guard let choice = sourceChoices[sourceID], let preferences else { throw … }`), nunca pode ter sucesso.
  No `onToggle`, a UI reporta a mensagem não relacionada "Mantenha ao menos uma fonte selecionada."
  (`FeedMineApp.swift`) *(evidência de código; não executei o toque no picker)*.
- Contrato violado: `source_keys` são preferências do usuário em runtime.sqlite, não configuração embarcada
  (`docs/superpowers/specs/2026-10-09-reader-contexts.md:25`); a única falha dura documentada em Release é catálogo/starter
  set **embarcado** ausente/inválido (`CATALOG.md:13`), e o mesmo arquivo prevê substituições de catálogo
  (`CATALOG.md:16`). PD-2 garante identidade para chave que **existe**; nada diz sobre chave que desapareceu.
- **Reproduzido nesta rodada** (iPhone 16, build Debug de `880191f`):

```sh
DEV=2F70B5E4-DF56-428C-A7B9-0A769B6CAC3D
NS=$(uuidgen)
SIMCTL_CHILD_FEEDMINE_RUNTIME_NAMESPACE=$NS SIMCTL_CHILD_FEEDMINE_USE_DEVELOPMENT_FEEDS=1 xcrun simctl launch $DEV com.feedmine.development
xcrun simctl terminate $DEV com.feedmine.development
SIMCTL_CHILD_FEEDMINE_RUNTIME_NAMESPACE=$NS xcrun simctl launch $DEV com.feedmine.development   # sem dev feeds
```

  Resultado: 1º launch publica normalmente; 2º mostra **`Não foi possível carregar a seleção de fontes:
  missingDefaultSource("bbc-world")`** e nenhum feed (`fm-r4-launch2-bricked.png`). O banco comprova a causa:
  `reader_preferences.source_keys = ["bbc-world","bbc-science"]` (persistido pelo 1º launch), e
  `SELECT COUNT(*) FROM catalog_source WHERE key IN ('bbc-world','bbc-science')` = **0**. Registro em
  `reader_preferences` (`runtime.sqlite`), 331.776 bytes, no container `ED0AB3D3-C2CE-4CEE-9D95-E6456A975828`.
- Gatilho de produção: atualização do app com snapshot de catálogo sem uma fonte que o leitor havia escolhido (o picker
  busca as 77.443 chaves, qualquer uma pode ser salva). Recuperação hoje exige apagar o container do app.
- Correção e prova: ao resolver `saved.sourceKeys`, descartar/reparar as chaves que o catálogo não contém (manter as
  válidas, cair para o starter set se sobrar nada) e atribuir `preferences` **antes** de qualquer chamada que possa lançar.
  Prova: semear `ReaderPreferencesStore.initialize(sourceKeys: ["https://absent.example/rss"])` num diretório isolado,
  construir `AppComposition` com o catálogo empacotado e asserir `startupFailure == nil`, `feeds` = starter set, e que
  `toggleSource` persiste uma seleção nova.

### 3.2 Kiro (delta da rodada 4)

| # | Severidade | Tipo | Achado | Arquivo:linha |
|---|---|---|---|---|
| K1 | ✅ verificado | prova | Falha de build com catálogo ausente **confirmada por execução**: exit 65, `No such file or directory` no Copy Bundle Resources. Deixar de ser GAP; registrar a execução nos docs | `FeedMineApp/FeedMineApp/Resources/CATALOG.md:10` |
| K2 | minor | DOC-DRIFT | `IOS_RUN.md` termina afirmando que o catálogo está em LFS e que "clone remoto ainda precisa receber esse objeto" | `docs/IOS_RUN.md:157` |
| K3 | minor | DOC-DRIFT | Cabeçalho "first three done" contradiz o bullet da rodada 4 ("taxonomy … not started") no mesmo arquivo | `docs/v1-study/PORT_LOG.md:111-115` |
| K4 | minor | GAP (teste) | Teste novo do ranking não distingue `quality_score DESC` de `ASC` (só uma linha com score entre as que casam) | `Tests/FeedMinePersistenceTests/LegacyCatalogReaderTests.swift:68-74` |
| K5 | minor | GAP (prova) | `CATALOG.md:14` promete falha explícita em Release sem catálogo/starter set; nenhum teste executa o ramo não-DEBUG | `FeedMineApp/FeedMineApp/Resources/CATALOG.md:14` |
| K6 | minor | DOC-DRIFT (contrato) | Spec da T4 proíbe "ranking/recomendação"; o código agora ordena por prefixo de título + score | `Sources/FeedMinePersistence/LegacyCatalogReader.swift:124-126` |
| K7 | minor | DEFECT (script) | Sem `shasum`/`sha256sum`, `fetch-catalog.sh` baixa 118 MB e culpa o download em vez da ferramenta ausente (falha fechada, `DEST` intacto) | `scripts/fetch-catalog.sh:15-21` |

Notas: K4 — fixture tem `B=80` e `A`/`D` sem score; `ASC` produziria a mesma ordem `[B, A, D]`; a direção pretendida
também está em `docs/v1-study/04-catalog-editorial.md:64` (`sort_key (default_enabled, 100−quality, title)`).
K6 — o único registro da regra nova é o log de rodada (`PORT_LOG.md:127`). Melhoria opcional registrada aqui, não pedida:
migrar a busca para o FTS5 que já está no arquivo (tabela 1: ganho medido de 13–340× nas consultas reais acima).

### 3.3 Codex (T4–T7)

| # | Severidade | Tipo | Achado | Arquivo:linha |
|---|---|---|---|---|
| C2 | minor | corrida | Conjunto de eviction vem de um snapshot da janela tirado **antes** do `await` de prefetch e não é revalidado; "só roda invisível / janela do leitor protegida" não é revalidado numa transição para foreground | `Sources/FeedMineRuntime/MediaTidy.swift:48-57` |
| C3 | minor | GAP (prova) | PD-4 não é provado por teste automatizado para o starter set real de 4 fontes (o teste do catálogo para em bytes/IDs; a asserção de adjacência usa as 2 fontes de desenvolvimento). **Comportamento confirmado no smoke de produção da §1: 0 violações de adjacência em 2 segmentos com dados reais** | `FeedMineApp/FeedMineAppTests/CompositionTests.swift:163-178` |
| C4 | minor | DEFECT (contrato) | Lista de keys reordenada conta como seleção diferente (`keys == current.sourceKeys` compara ordem): remover e readicionar a mesma fonte incrementa `selectionVersion`, o fence de restore descarta o checkpoint e o leitor perde a posição — exatamente o que o contrato diz que a mesma escolha não pode causar | `Sources/FeedMinePersistence/ReaderPreferencesStore.swift:30` |
| C5 | minor | dead code | `searchContextUnavailable` perdeu os dois únicos `throw` (busca local não busca HTTP) e ficou nos dois enums públicos | `Sources/FeedMineEditorial/CandidateProvider.swift:26`, `Sources/FeedMineComposition/SyndicationAcquisitionSnapshot.swift:42` |
| C6 | minor | corrida/UX | Slice preemptado pela substituição de cauda lança `staleHistoryExpectation`, que ninguém trata: vira badge pegajoso "Falha ao atualizar o feed" em vez de ser absorvido como o `staleIntent` já é (confiança do interleaving: 0,45) | `FeedMineApp/FeedMineApp/AppComposition.swift:545-554` |
| C7 | minor | GAP (prova) | Metade de mídia da checagem de sucessão da cauda nunca é exercitada: todos os testes preparam `.textOnly`, então `old.mediaKey`/`new.media.primary` são sempre `nil` (PD-5 regra 3 sem prova end-to-end) | `Sources/FeedMineRuntime/HiddenTailMaintenance.swift:38-41` |
| C8 | minor | GAP (prova) | Clamp do high-water e o portão `unseenOriginIDs` (PD-1 regra 2 no store) não têm nenhum teste: nenhum teste passa `readerAnchorCardID:`, então `unseen` é sempre vazio | `Sources/FeedMinePersistence/PublicationStore.swift:596-600` |
| C9 | minor | GAP (prova) | Fronteira do `candidateWindow(originIDs:)` (LIMIT sobre o filtro IN) não é testada; o "teste" existente faz `grep` do texto-fonte do Swift, que não falha se o SQL deixar de aplicar o filtro | `Sources/FeedMinePersistence/ContentStore.swift:80-89` |

Verificado como correto nesta fatia (leitura + testes executados), para não repetir auditoria: fatos de uso/bookmark são
duráveis (`publication_card_usage`, `publication_bookmarks`, FK para `published_cards`); a consulta de eviction agrega por
`media_key` com `MAX(u.last_seen_at)` e `MAX(b.card_id IS NOT NULL)` (asset compartilhado herda bookmark); `unlink` falho não
infla `reclaimed`; asset ausente no render devolve `nil` preservando geometria/aspect ratio e sem rede; churn de tracking não
é material e query significativa é (`?utm_source=rss&fbclid=changed` → 0; `?image=other` → 1); cache de projeção só reutiliza
com mesmo `contextKey`+`editionID`, e IDs novos são cunhados a cada preparação e a cada segmento sucessor.

## 4. Bloqueios reais (inalterados)

- **Aparelho físico:** `xcrun devicectl list devices` mostra iPhone 14 Plus e iPhone 15 `unavailable`; o checklist físico
  (scroll prolongado, memória, energia, térmica, rede) segue sem execução. Nenhum dado de hardware nesta rodada.
- **Headroom de disco:** ~0,8 GiB livres após a rodada. Compilar o app + testar consome ~2 GB por vez.
- **Decisão de produto pendente** (não iniciada, corretamente não inventada): diversidade além do PD-4 e navegação por
  taxonomia sobre `catalog_node`.

## 5. Ordem sugerida para Codex/Kiro

1. **C1** (bloqueia qualquer atualização de catálogo; hoje o app fica inutilizável sem apagar o container). Correção pequena
   em `AppComposition.init`/`TrustedFeed.resolve` + teste de regressão. Prova: comando da §3.1 e o teste de chaves ausentes.
2. **K2/K3/K6** (docs mentirosos: custo ~zero, evitam que o próximo agente "conserte" o ranking ou persiga LFS).
3. **D1** (starter set de 4 fontes entrega 100% BBC e não adquire NPR/Guardian com o leitor parado): primeiro separar
   hipótese (a) reserva já saturada de (b) recuperação só para feed vazio; depois decidir se a primeira tela pode ficar
   mono-fornecedor. Afeta o produto de forma visível, e o teste de 5 min sem gesto da §1 resolve a separação.
4. **K7** (pré-checagem de `shasum`/`sha256sum` antes do `curl`).
5. **C4** (comparação insensível a ordem + teste de reordenação) — perda de posição do leitor com seleção líquida zero.
6. **C7/C8/C3/C9/K4/K5** (provas ausentes nas features já entregues; cada item tem fixture sugerida no achado).
7. **C2/C6** (corridas curtas; absorver `staleHistoryExpectation` como benigno é a de maior valor de UX).
8. **C5** (dead code).

Nenhuma correção foi aplicada nesta rodada: o repo está em `880191f` sem alterações rastreadas (o único arquivo novo é este
relatório; `Resources/catalog.sqlite` é gitignored).
