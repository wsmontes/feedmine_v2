# Revisão estática — app iOS, UI, persistência e testes

**Checkout:** `C:\workspace\feedmine_v2-kiro`, branch `main`, HEAD `aefa19f` (relatado).
**Método:** leitura apenas. Sem toolchain Swift nesta máquina Windows: nada foi compilado, nenhum teste rodado, nenhuma migração executada. Toda afirmação sobre comportamento de runtime/SQLite é inferência de leitura e está marcada como tal.
**Área:** `FeedMineApp/FeedMineApp/*.swift`, `FeedMineApp/FeedMineAppTests/*`, `Sources/FeedMineUI/**`, `Sources/FeedMinePersistence/{RuntimeDatabase,RuntimeMigrations,ReaderLibraryStore,ReaderPreferencesStore,LegacyUserStateReader}.swift`, `Sources/FeedMineComposition/{Reader*,LegacyUserStateImport}.swift`, `Package.swift`, `scripts/*.sh`, `.gitignore`.
**Autoridade usada:** PRODUCT_INVARIANTS (INV-01..18), PD-1..PD-10, benchmark B01–B06, e as revisões em `docs/reviews/` para classificar novo vs. já conhecido.

Achados ordenados por impacto. Severidade: P0 = quebra/perde dado do usuário ou bloqueia gate; P1 = correção/concorrência séria; P2 = robustez/risco condicional.

---

## A01 — P0 — `DeviceMediaConditions.current()` chama `DispatchQueue.main.sync` fora da main thread: risco de deadlock na preparação de mídia

- **Arquivo:** `FeedMineApp/FeedMineApp/AppComposition.swift:` bloco `DeviceMediaConditions`
  ```swift
  static func current() -> DeviceMediaConditions {
      if Thread.isMainThread { return MainActor.assumeIsolated { currentOnMain() } }
      return DispatchQueue.main.sync { MainActor.assumeIsolated { currentOnMain() } }
  }
  ```
- **Chamada:** `FeedAssociation.init(...)` executa `let device = DeviceMediaConditions.current()`. `FeedAssociation` é `@MainActor`, portanto no caminho normal (`AppComposition` chama `association(contextKey:)` na main actor) `Thread.isMainThread` é verdadeiro e o ramo `.sync` não dispara. **O defeito é o ramo `.sync`:** ele só existe para ser chamado de thread não-main, e nesse caso faz um `DispatchQueue.main.sync` bloqueante.
- **Por que é defeito:** `DispatchQueue.main.sync` a partir de uma thread da cooperative pool do Swift concurrency pode bloquear a main thread indefinidamente / causar deadlock se a main estiver suspensa aguardando o mesmo trabalho (padrão clássico de inversão). Mesmo sem deadlock, é bloqueio síncrono da main thread (viola a intenção de INV-02/PD-6 de medir sem travar a apresentação). O `init` do `FeedAssociation` roda SQLite síncrono e constrói o pipeline inteiro; se qualquer refator mover a construção de associação para fora da main actor (ou um teste a construir de uma task detached), o ramo `.sync` passa a ser atingido.
- **Cenário de reprodução (previsível, não executado):** construir `FeedAssociation` de um contexto não-main (ex.: `Task.detached { try FeedAssociation(...) }`) com a main thread ocupada → `DispatchQueue.main.sync` nunca retorna. Hoje o caminho de produção está protegido pelo `@MainActor`, por isso classifico o risco como latente mas P0 pela severidade (travamento total do app, difícil de diagnosticar).
- **Invariante/PD:** PD-6 (orçamento de mídia medido sem travar), INV-01/INV-05 (preparação não bloqueia apresentação).
- **Correção mínima:** eliminar o ramo `.sync`. Como todo o consumo de produção já é main-actor, tornar o método `@MainActor static func current()` e remover o fallback; ou, se precisar ser chamável de qualquer isolamento, passar os fatos de tela como parâmetro capturado na main actor em vez de reentrar na main thread.
- **Teste que provaria:** teste de concorrência construindo a associação a partir de uma `Task.detached` com a main thread em um `await` longo; o teste atual não cobre isso. Com a correção (`@MainActor`), a tentativa de chamada off-main vira erro de compilação — prova estática.
- **Status:** **novo.** Nenhuma das revisões (`CODE_REVIEW_2026-10-08`, `_COMPARATIVO`, `F05`, `DOCUMENTATION_CONSISTENCY_AUDIT`) menciona `DispatchQueue.main.sync` nem `DeviceMediaConditions`.

---

## A02 — P1 — `AppComposition` abre `RuntimeDatabase` em pool novo por ação, exatamente o anti-padrão que o próprio código documenta como bug

- **Arquivo:** `FeedMineApp/FeedMineApp/AppComposition.swift`
  - `media` (`:612`): `guard let database = try? RuntimeDatabase(location: ...)` — abre um pool novo a **cada** acesso ao player.
  - `makeSourceManagementStore()` (`:622`): `let database = try? RuntimeDatabase(location: ...)` — pool novo por apresentação da tela de fontes.
  - `libraryDatabase()` fallback (`:373`): abre novo pool se `library` for nil.
  - Além disso, `FeedAssociation.init` (`:1004`) abre o seu próprio pool, e vários métodos internos (`sourcePage`, `resolvedExternalURL`, `toggleBookmark`, `savedArticles`) instanciam `PublicationStore(database: database)` reusando o pool da associação — ok — mas `ReaderActionCoordinator(database: database)` idem.
- **Por que é defeito:** o comentário em `libraryDatabase()` (`:365–372`) declara explicitamente o motivo de centralizar: *"opening a fresh pool per action ran the migrations again and contended with the session's own connections, and a refused open was swallowed by `try?` — which is how an export could silently become 'nothing to export'."* Os três sites acima (`media`, `makeSourceManagementStore`, e implicitamente o `FeedAssociation.database`) continuam abrindo pools paralelos ao mesmo `runtime.sqlite`. Cada `RuntimeDatabase.init` roda `migrator.migrate(pool)` de novo. Múltiplos `DatabasePool` sobre o mesmo arquivo WAL concorrem por escrita; `media` ainda usa `try?`, então uma falha de abertura some silenciosamente ("mídia indisponível" sem causa).
- **Invariante/PD:** INV-12 (um owner por responsabilidade — aqui, a conexão `runtime.sqlite`). PD-7 (prática de qualidade: não reintroduzir o bug já corrigido).
- **Cenário de reprodução (não executado):** abrir a tela de fontes (`makeSourceManagementStore`) enquanto a sessão escreve checkpoint em background → dois `DatabasePool` disputando o WAL; sob SQLITE_BUSY o `try?` em `media`/`makeSourceManagementStore` engole o erro. Em disco cheio ou corrida de migração, `media` retorna nil e a UI mostra "Mídia indisponível" sem log.
- **Correção mínima:** rotear `media`, `makeSourceManagementStore` e o pool do `FeedAssociation` pelo mesmo `library` já mantido por `AppComposition` (passar a `RuntimeDatabase` por injeção em vez de reabrir). O comentário já descreve a solução para o caso library; estender aos três sites restantes.
- **Teste que provaria:** teste de composição que abre a tela de fontes e dispara uma escrita de sessão concorrente e afirma que nenhuma abertura é recusada (exige instrumentar contagem de `RuntimeDatabase.init`). Hoje nenhum teste conta aberturas de pool.
- **Status:** **parcialmente conhecido.** O comentário do próprio código reconhece o padrão para `libraryDatabase`; `DOCUMENTATION_CONSISTENCY_AUDIT` não lista. A persistência dos sites `media`/`makeSourceManagementStore`/`FeedAssociation.database` é **nova** como achado explícito.

---

## A03 — P1 — Migração `media-playback-candidate-v1` reconstrói tabela com DROP/RENAME sem desabilitar foreign keys

- **Arquivo:** `Sources/FeedMinePersistence/RuntimeMigrations.swift`, migração `media-playback-candidate-v1`:
  ```sql
  CREATE TABLE media_candidates_v2 (...);
  INSERT INTO media_candidates_v2 SELECT * FROM media_candidates;
  DROP TABLE media_candidates;
  ALTER TABLE media_candidates_v2 RENAME TO media_candidates;
  ```
  e o mesmo padrão em `reader-context-identity-v1` (`context_checkpoints_v2` → drop → rename).
- **Por que é defeito:** `RuntimeDatabase` abre com `configuration.foreignKeysEnabled = true` e as migrações são registradas por `registerMigration(_:)` **sem** `foreignKeyChecks: .deferred`. O padrão oficial do SQLite/GRDB para rebuild-and-rename exige executar com foreign keys desabilitadas (GRDB expõe `migrator.registerMigration(_, foreignKeyChecks: .immediate/.deferred)` e desliga/religa automaticamente). `media_candidates` tem FK **saída** para `origin_revisions`; o `INSERT ... SELECT *` depende de ordem posicional de colunas (frágil, mas aqui coincide) e, com FKs imediatas ligadas, o `DROP TABLE media_candidates` seguido de rename roda com verificação ativa. Confirmei por grep que **nenhuma** tabela referencia `media_candidates` por FK de entrada, o que reduz o risco de órfão; ainda assim o rebuild de `context_checkpoints` (que tem FK para `feed_editions` e `published_cards`) sob FK imediata pode falhar o `INSERT...SELECT` se alguma linha referenciar edição/‑card já ausente.
- **Invariante/PD:** INV-12 (uma autoridade de migração, migração nunca apaga estado semântico), PD-10 (atualização íntegra/atômica — aqui o estado durável do leitor).
- **Não pude verificar:** se GRDB nesta versão desabilita FK por padrão dentro de `registerMigration`. GRDB historicamente **não** desabilita a menos que se passe `foreignKeyChecks:`. Sem rodar a migração não posso confirmar que o rebuild passa limpo em um banco com dados reais; é exatamente o tipo de defeito que a suíte de 710/827 testes pode não cobrir se os fixtures de migração começam vazios.
- **Cenário de reprodução (não executado):** migrar um `runtime.sqlite` real que já tenha `media_candidates` com linhas e `context_checkpoints` com uma linha cujo `edition_id` foi retirado por outra operação → `INSERT INTO context_checkpoints_v2 SELECT ...` sob FK imediata rejeita a linha ou aborta a migração, deixando o leitor sem posição salva (perda de continuidade B05).
- **Correção mínima:** registrar as duas migrações de rebuild com `foreignKeyChecks: .deferred` (ou envolver em `PRAGMA foreign_keys=OFF; ...; PRAGMA foreign_key_check; PRAGMA foreign_keys=ON`), e substituir `INSERT ... SELECT *` por lista explícita de colunas.
- **Teste que provaria:** teste de migração que semeia `media_candidates` e `context_checkpoints` com dados antes de aplicar a migração alvo e verifica contagem/igualdade pós-migração e integridade de FK (`PRAGMA foreign_key_check`). Procurar em `RuntimeMigrations`/`PersistenceTests` se existe fixture não-vazio; pela leitura dos testes acessíveis não há evidência de rebuild com dados.
- **Status:** **novo.** Não aparece em `CODE_REVIEW_2026-10-08` (que trata de admissão/aquisição, não do rebuild de tabelas do leitor).

---

## A04 — P0 — Fonte importada por OPML nunca entra no conjunto de aquisição: `TrustedFeed.resolveAvailable` só consulta `fallback` + catálogo embarcado, nunca `reader_imported_sources`

- **Arquivo:** `FeedMineApp/FeedMineApp/TrustedFeeds.swift` (`resolveAvailable`), `ReaderLibraryStore.commitImport`, `AppComposition.adoptSelectionChange`.
- **Mecanismo (verificado por leitura):** `commitImport` grava em `reader_imported_sources` e sobe `selection_version` (atômico, correto). `AppComposition.commitImport` chama `adoptSelectionChange()`, que resolve a seleção com:
  ```swift
  var resolved = (try? TrustedFeed.resolveAvailable(keys: record.sourceKeys, fallback: feeds)) ?? []
  if resolved.isEmpty, !record.sourceKeys.isEmpty { resolved = feeds }
  ```
  `resolveAvailable` (confirmado em `TrustedFeeds.swift`) resolve cada chave **apenas** por (a) `fallback.first(where: principal == key)` e (b) `LegacyCatalogReader(catalog.sqlite).source(key:)`. **Não há nenhuma consulta a `reader_imported_sources`.** Logo uma chave importada que não está no catálogo embarcado retorna `nil` do `compactMap` e é descartada. Se todas as chaves selecionadas forem importadas (fora do catálogo), `resolved` fica vazio → o fallback atribui `resolved = feeds` (a seleção anterior). A versão subiu, a sessão foi reconstruída, mas sobre as fontes antigas — a importação é funcionalmente um no-op.
- **Por que é defeito:** PD-10/INV-18 exigem que imports próprios do usuário sejam de primeira classe e não sejam apagados por lógica de catálogo. O feed importado aparece em `importedSources()`/UI mas nunca contribui com um card, porque a materialização de alvos de aquisição passa só por `TrustedFeed`/catálogo embarcado. Quebra E1 (descoberta/importação) e a promessa de OPML.
- **Cenário de reprodução (não executado):** importar OPML com 1 feed cuja URL/chave não está em `catalog.sqlite` → `importedSources()` lista o feed; nenhum card dele jamais é publicado; se for a única fonte, a sessão silenciosamente volta à seleção anterior.
- **Correção mínima:** fazer `resolveAvailable` (ou `adoptSelectionChange`/`association(...)`) mesclar `reader_imported_sources` construindo `TrustedFeed` a partir de `request_url` (exatamente como `searchSources` já constrói `TrustedFeed` de registros do catálogo). Nunca cair no fallback `feeds` quando houver chaves importadas presentes na seleção.
- **Teste que provaria:** teste de composição: importar OPML com 1 feed fora do catálogo (servido por `FixtureTransport`), afirmar que após `commitImport` a sessão adquire e publica ≥1 card dessa fonte. Inexistente hoje.
- **Status:** **novo** (relacionado a E1; nenhuma revisão aponta o descarte de fontes importadas em `resolveAvailable`/`adoptSelectionChange`).

---

## A05 — P1 — `openCollectionFeed` reseta `self.feeds` para a seleção logo após `launch()`, corrompendo `sourceHealth()`/`scoring()` da sessão de coleção em execução

- **Arquivo:** `FeedMineApp/FeedMineApp/AppComposition.swift`, `openCollectionFeed(id:)`:
  ```swift
  feeds = resolved                     // sessão da coleção
  ...
  let next = try association(contextKey: ..., sessionFeeds: resolved)
  association = next
  try await next.launch()
  feeds = sessionFeeds                 // volta para a seleção do leitor
  ```
- **Mecanismo:** a associação da coleção foi construída com `sessionFeeds: resolved` (correto — ela congela os próprios feeds em `self.feeds` da associação). Mas `AppComposition.feeds` é restaurado para a seleção original **enquanto a associação de coleção continua ativa**. Métodos de `AppComposition` que leem `self.feeds` passam a mentir sobre a sessão visível:
  - `sourceHealth()` itera `AppComposition`? Não — itera `association...`? Confirme: `sourceHealth()` usa `self.feeds` para mapear `targetID→principal`. Com `feeds` restaurado à seleção, a saúde das fontes da **coleção** não é mapeada (as fontes da coleção podem não estar na seleção), então a tela de fontes mostra estado vazio para a sessão ativa.
  - `scoring(for:)` e `feedFacts()` leem `self.feeds`; se o leitor salvar/editar algo enquanto na coleção, resolve contra as fontes erradas.
- **Por que é defeito:** INV-10 (mudança de contexto reprioriza sem destruir), INV-12 (um owner). `self.feeds` é usado como se fosse "as fontes da sessão atual", mas após `openCollectionFeed` deixa de corresponder à associação ativa. É um estado observável inconsistente.
- **Cenário de reprodução (não executado):** abrir feed de coleção → abrir tela "Fontes" → saúde das fontes da coleção aparece vazia; ou salvar contexto como preset enquanto na coleção → preset resolve pela seleção, não pela coleção.
- **Correção mínima:** não restaurar `self.feeds` prematuramente; derivar "fontes da sessão atual" de `association?.feeds` (a associação já congela as suas), e só restaurar a seleção na próxima transição explícita. Alternativamente documentar que `self.feeds` == seleção durável e trocar os leitores de sessão (`sourceHealth`) para `association.feeds`.
- **Teste que provaria:** teste de composição que abre coleção e verifica `root.sourceHealth()` cobre as fontes da coleção. Inexistente.
- **Status:** **novo.**

---

## A06 — P2 — `release-testflight.sh`: `set -uo pipefail` sem `-e` deixa falhas silenciosas; API key/issuer embarcados no script

- **Arquivo:** `scripts/release-testflight.sh`.
- **Mecanismo A (robustez):** `set -uo pipefail` **sem `-e`**. Vários comandos verificam `$?` explicitamente (`if xcodebuild ...`), mas `SHA="$(git rev-parse HEAD)"`, `BUILD="$(/usr/libexec/PlistBuddy ...)"` etc. não são checados; se `PlistBuddy` falhar (plist ausente), `BUILD`/`VERSION` ficam vazios e o `TAG` vira `ios/-build.-$SHORT`, e o upload prossegue com metadados vazios em vez de abortar. Com `pipefail` mas sem `-e`, um `git rev-parse` que falhe não interrompe.
- **Mecanismo B (segredo):** `KEY_ID="H3U55Z9WZ7"` e `ISSUER_ID="0e1bd229-..."` estão hardcoded e versionados. O `.p8` em si está fora (`$HOME/.appstoreconnect/...`, bom), mas o par KEY_ID+ISSUER_ID identifica a chave da App Store Connect e **não deveria** estar no repositório; combinados com o `.p8` vazado dão upload à conta. `bundle id` e `ASC record 6793279758` também expostos (menor).
- **Por que é defeito:** PD-7/robustez de release; higiene de segredos (diretriz de segurança: não versionar identificadores de credencial). Não é vazamento do `.p8`, mas KEY_ID/ISSUER_ID são material de credencial.
- **Correção mínima:** ler `KEY_ID`/`ISSUER_ID` de variáveis de ambiente (`${ASC_KEY_ID:?}`), falhar cedo se ausentes; adicionar `set -e` ou checar `$?`/vazio após cada `rev-parse`/`PlistBuddy`; validar `VERSION`/`BUILD` não-vazios antes de arquivar.
- **Teste que provaria:** `shellcheck scripts/release-testflight.sh` (apontaria SC2086/variáveis não checadas) e um dry-run com `INFO_PLIST` apontando para arquivo inexistente deve abortar, não gerar tag malformada. Não há CI (PD-7 L4 "won't do"), então é prova manual.
- **Status:** **novo** (nenhuma revisão examina os scripts de release).

---

## A07 — P2 — `fetch-catalog.sh` baixa o catálogo da release do próprio repo V2, não da autoridade pública PD-10/INV-18

- **Arquivo:** `scripts/fetch-catalog.sh`:
  ```sh
  URL="https://github.com/wsmontes/feedmine_v2/releases/download/catalog-v1/catalog.sqlite"
  SHA256="c2ae483a...8629"
  SIZE=117940224
  ```
- **Por que é defeito:** PD-10/INV-18 declaram que a autoridade do catálogo gerenciado é `https://github.com/wawasoft/feed-repository` (manifest.json revisão 5), e que cada release deve embarcar o snapshot derivado da **revisão pública validada**, com procedência rastreável. O script fixa um asset derivado da V1 na release do próprio repo V2; a coincidência de contagem (77.443) não prova identidade de revisão. O `CATALOG.md` da própria app reconhece isso textualmente.
- **Invariante/PD:** PD-10 (critério de release 1), INV-18.
- **Correção mínima:** apontar a origem para a revisão pública validada e gravar procedência/revisão junto ao asset; ou, no mínimo, não tratar o snapshot como autoridade (já é o estado documentado como pendente). Isto é requisito de release, não bug de runtime.
- **Teste que provaria:** verificação de que o snapshot embarcado carrega a revisão do `manifest.json` público e que o SHA bate com a árvore `Feeds/` dessa revisão. Pendente de implementação do fluxo PD-10.
- **Status:** **já conhecido** — `DOCUMENTATION_CONSISTENCY_AUDIT_2026-10-10.md` §"P0/P1 de implementação", item 1, descreve exatamente este ponto. Registro aqui só para completude da minha área (scripts).

---

## A08 — P2 — Lacunas de teste: B01–B05 não têm prova real na suíte iOS acessível; XCUI nunca exercita scroll/runway

- **Arquivos:** `FeedMineApp/FeedMineAppTests/FeedMineUITests.swift`, `CompositionTests.swift`.
- **Observações concretas:**
  - `FeedMineUITests` abre o app, navega contexto, abre a tela de fontes e verifica o estado de seleção vazia. **Não há scroll de feed, nem avanço de cursor, nem medição de runway.** O próprio comentário no topo diz *"N1/N2: the test never constructs ViewportObservation or calls submitViewport."* Logo **B03 (30 min de avanço contínuo) e B04 (estabilidade física/idle) não têm prova XCUI** — confirmado pela diretriz que já marca B03 NOT_RUN.
  - `CompositionTests.produceAndAdmit` força admissão via `association.viewport(..., activity: .explicitTailApproach)` chamando o driver diretamente — prova o pipeline de produção/admissão em componente, **não** o gesto físico (B04 "teste só de IDs em memória não basta").
  - `FixtureTransport` injeta 24 itens de uma única fonte fixture. **PD-4 (alternância de SourceID) não pode ser provado** com corpus de fonte única; a continuidade A→B→A (B05) é exercitada só em nível de composição, não como jornada XCUI com reabertura real do processo.
- **Por que é defeito:** a diretriz exige B01–B05 com prova real; a área de testes é minha responsabilidade reportar. O relato canônico de B05 (corrida `20261011T174133Z`) está **fora do checkout** (no Mac), então no repositório não há artefato que o comprove — alinho com a instrução: "PASS relatado pelo owner; ainda não verificado no checkout".
- **Correção mínima:** (1) teste XCUI que role o feed por N cards e afirme ausência de parada ≥1s (B03 reduzido reproduzível no simulador); (2) corpus multi-fonte no `FixtureTransport` para provar PD-4 na sequência publicada; (3) teste de relaunch de processo (terminate/launch) afirmando que âncora e salvos sobrevivem (B05 como jornada, não só componente).
- **Teste que provaria:** os próprios testes acima, novos.
- **Status:** **já conhecido** em parte — B01–B06 NOT_RUN está em `DOCUMENTATION_CONSISTENCY_AUDIT` e `F05`. A observação específica de que o corpus XCUI é de fonte única (bloqueia prova de PD-4) é **nova**.

---

## A09 — P2 — `ReaderLibraryStore.apply` e `commitImport` usam `JSONEncoder()`/`JSONDecoder()` recém-criados dentro de loops de transação

- **Arquivo:** `Sources/FeedMinePersistence/ReaderLibraryStore.swift`, `apply(_:at:)` (preset loop) e vários `presets()/createPreset()`.
- **Mecanismo:** cada iteração de preset faz `try JSONEncoder().encode(preset.key)` e `try preset.recipe.map { try JSONEncoder().encode($0) }`. Correto funcionalmente, mas em `apply` (import grande) e `presets()` isso aloca encoder/decoder por linha. Não é correção/segurança — é custo em caminho que pode processar a biblioteca inteira de uma vez.
- **Por que é (apenas) P2:** não viola invariante; a transação é atômica e correta. Reporto por ser caminho de dados pessoais em volume (import V1 pode ter muitos presets) e a diretriz pede atenção a gargalos. **Não** é bug de corretude.
- **Correção mínima:** reusar um `JSONEncoder`/`JSONDecoder` por chamada. Baixa prioridade.
- **Status:** **novo**, mas marginal.

---

## Itens inspecionados e considerados corretos (para não gerar retrabalho)

- **Fronteira UI (INV-01/02):** `FeedScreen`, `FeedScreenStore`, `FeedItemCardView` não fazem SQL, não iniciam aquisição, não resolvem imagem remota. Ações saem como `ReaderCardActionEvent`; imagens são `card.image?.cgImage` (decodificado fora da UI). `heroSlot` congela o aspect ratio independentemente de bytes (INV-08/PD-5 — slot imutável). **Correto.**
- **`FeedPresentationState.receiving`:** fence de identidade + sequência + posição (INV-08/3R9B). Rejeição preserva estado. **Correto.**
- **`ReaderLibraryStore` / `ReaderPreferencesStore`:** toda escrita é uma transação GRDB; `updateSources` não sobe versão em reordenação de mesmo conjunto (OMP C4) — preserva posição no restore. Deleção de coleção/box não apaga fontes/artigos (só memberships via cascade). **Correto.**
- **`LegacyUserStateReader`:** abre `user.sqlite` **read-only** (`configuration.readonly = true`) — import nunca modifica a origem. **Correto.**
- **`SessionStore.activateContext`:** persiste o checkpoint corrente antes de trocar; posição por `context_identity` (T6) evita colisão de superfícies filtradas. **Correto.**

---

## O que explicitamente NÃO pôde ser verificado (sem toolchain/execução)

1. Comportamento real de foreign keys dentro de `registerMigration` nesta versão de GRDB (A03) — exige rodar a migração com dados.
2. Qualquer medição de runtime: B03 (30 min), B04 (idle/estabilidade física), memória/térmica (B06 exige iPhone físico — **NOT_RUN**, não é waiver de simulador).
3. O PASS canônico de B05 (corrida `20261011T174133Z`): artefatos relatados como só no Mac; não verificável neste checkout.
4. Contagem de testes verdes (710/827): relato de agente, não recompilado aqui.

**Próximo bloqueador de maior impacto (um só):** A04 (confirmado) — fontes importadas por OPML nunca entram no conjunto de aquisição; sem isso a importação (parte de E1/descoberta) é cosmética. A01 é o maior risco de estabilidade latente e deve ser fechado em seguida (remover o ramo `.sync`).
