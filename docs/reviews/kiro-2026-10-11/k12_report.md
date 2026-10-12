# FeedMine V2 — Relatório K-12: descoberta de fontes e catálogo (linha integrada)

**Checkout:** `C:\workspace\feedmine_v2-int`, `origin/integration/main-into-app-line` @ `8274d0c` (declarado; git não executado nesta máquina).
**Natureza:** apenas leitura. Nenhum arquivo do repositório modificado. Sem toolchain Swift / sem build / sem simulador. Todo número de runtime é hipótese.
**Comparação:** contra a revisão original E1 (`feedmine_v2-kiro/docs/reviews/kiro-2026-10-11/discovery.md`, D1–D6; A07 em `.../app_ui_persistence.md`).

## Veredito geral

A linha do app **implementou descoberta progressiva de catálogo** (D1, D2 resolvidos) e **implementou a maquinaria PD-10** de manifest/validação/ativação atômica, agora ligada (D5/A07 majoritariamente resolvidos). **D3 continua aberto**: o starter set literal ainda pode lançar e derrubar o startup se uma key sumir. B01 fica dependente de medição no simulador (não verificável aqui).

---

## 1. D1 — universo de aquisição e crescimento progressivo

**Agora o catálogo inteiro é universo elegível, visitado progressivamente por oportunidade de runway — não há teto de 4 nem número mágico de fontes.** (confirmado por leitura)

- **Como entra:** `AppComposition.association(contextKey:)` passa `discovery: await discoveryFeeds(profile:)` e `discoveryTraversal:` ao `FeedAssociation` (`AppComposition.swift:1065-1071`). A travessia é um `ReaderDiscoveryTraversal` por `(profile, contextKey, revisão-do-catálogo)`, cacheado (`AppComposition.swift:1076-1086`).
- **O que avança a página:** cada oportunidade legítima do runway. `FeedRunwayDriver.drive` chama `acquisition.advanceDiscovery(for:examinedCapacity: discoveryResources.discoveryExaminedCapacity)` **uma página por oportunidade**, fora do dreno causal (`FeedRunwayDriver.swift:177-180`). O cold start também avança uma página (`ColdFeedBootstrap.swift:167` e `:290`). Portanto **o universo cresce ao longo da sessão (runway)**, não só na construção.
- **Paginação da travessia:** `ReaderDiscoveryTraversal.advance` lê `builder.page(for:after:cursor:examinedCapacity:)`, materializa os `entries` da página como registrations (`SyndicationAcquisitionSnapshot.advanceDiscovery`, `ReaderDiscoveryTraversal.swift:62-92`), guarda o `cursor` e marca `finished` só quando `records.count <= examinedCapacity` (fim estrutural real). O cursor percorre o catálogo em ordem de key estável (`ReaderDiscoveryPool.page`, `ReaderDiscoveryPool.swift:107-139`).
- **Tamanho do pool / números:** dois números distintos, **ambos limites de recurso por passo, não cotas permanentes** (coerente com PD-8/INV-16, `PRODUCT_DECISIONS:153`, `PRODUCT_INVARIANTS.md:182`):
  - `discoveryExaminedCapacity` default **120** por oportunidade (`FeedRunwayDriver.swift:22-25`): quantas linhas são **examinadas** por página; a página seguinte retoma do cursor. Não limita o total da sessão.
  - `AppComposition.discoverySourceLimit = 120` (`AppComposition.swift:1296`) é o teto do **preview de UI** `discoveryFeeds` (lista `[TrustedFeed]` mostrada), via `ReaderDiscoveryBuilder.pool(for:limit:)`. É só preview; o comentário do próprio `pool` diz "Compatibility preview only. Active associations should retain and advance `page` cursors." A aquisição real usa a travessia paginada, não esse limite.
  - Tetos do builder (`perTopicCeiling: 2_000`, `keyCeiling: 4_000`, `ReaderDiscoveryPool.swift:95-99`) limitam só o custo de uma consulta de subárvore do **preview**; o `page()` da travessia não os aplica.
- **Perfil vazio (feed neutro, sem respostas):** **não há descoberta — volta à seleção do leitor (as 4).** `discoveryTraversal(for:profile:)` retorna `nil` quando `profile.isEmpty` (`AppComposition.swift:1078`), e `discoveryFeeds` retorna `[]` (`AppComposition.swift` em `discoveryFeeds`). `ReaderDiscoveryProfile.isEmpty == languages.isEmpty && topicNodeKeys.isEmpty` (`ReaderDiscoveryPool.swift:44`). **Porém** `discoveryProfile(for:)` deriva o perfil de `key.filter.languages`/`taxonomyNodeIDs` quando não há recipe salvo (`AppComposition.swift:1132-1140`): se o onboarding de B01 declara **idiomas/lugares**, o perfil **não** é vazio e a descoberta roda já na fase neutra, antes de qualquer voto temático. Só um perfil sem idioma e sem tema é verdadeiramente vazio e cai nas 4.

## 2. D2 — idioma como filtro rígido

**Sim, idiomas explícitos filtram a descoberta de forma estrita.** (confirmado por leitura)

- `ReaderDiscoveryBuilder.admits` (`ReaderDiscoveryPool.swift`): quando `profile.languages` não é vazio, exige `record.language` não vazio **e** `ReaderLanguageCode.answered(language, by: profile.languages)`; caso contrário retorna `false`. `und`/vazio nunca passa. Subtag primária (`pt-BR` responde `pt`) resolvida em `ReaderLanguageCode`.
- Vale tanto para o `page()` da travessia (aquisição) quanto para o `pool()` (preview), pois ambos chamam `admits`. Resolve o defeito latente D2 da revisão original.

## 3. D3 — starter literal derruba startup?

**Sim — continua aberto.** (confirmado por leitura)

- `TrustedFeed.catalog(limit:resourceURL:)` ainda tem as **4 keys literais** e lança `TrustedCatalogError.missingDefaultSource(key)` se qualquer uma faltar no catálogo (`TrustedFeeds.swift`, bloco `catalog`). Em release, `catalogOrDevelopment` transforma o throw em `[]`.
- Mitigação parcial nova: `AppComposition.init` só marca `startupFailure` se **`feeds.isEmpty` E `catalogueURL == nil`** (`AppComposition.swift:195-197`). Ou seja, catálogo ilegível ainda derruba; mas um catálogo legível em que **falte uma das 4 keys** ⇒ `catalog(limit:)` lança ⇒ `feeds == []` com `catalogueURL != nil` ⇒ **não** marca `startupFailure`, mas sobe **sem seleção inicial** (depende só da descoberta). Logo o travamento duro de PD-10 foi atenuado, **mas a fragilidade da key canônica permanece**: `catalog(limit:)` ainda lança por key ausente, ao contrário de `resolveAvailable`, que já descarta key ausente em vez de lançar. Divergência de robustez entre os dois caminhos (também é o D6 original).

## 4. D5 / A07 / PD-10 — manifest, atualização atômica, catálogo público

**Majoritariamente implementado e ligado.** (confirmado por leitura)

- **Manifest:** `CatalogManifest` decodifica a forma pública (`revision/schemaVersion/sourceCount/fileCount/files[{path,bytes,sha256}]`) e valida antes de construir (`CatalogManifest.swift`). O descritor empacotado `catalog.manifest.json` adiciona a entrada do `catalog.sqlite` (`fileCount=119`).
- **Ativação atômica + staging + ledger:** `CatalogInstallation` (verifica, instala in-place no bootstrap, ativa revisão buscada atomicamente, grava `CatalogRevisionRecord` activated/bootstrapped/rejected/deferred). `CatalogUpdater` baixa payload, verifica cada byte, compila em staging e ativa — ou recusa preservando o snapshot ativo. Não toca `runtime.sqlite`.
- **Verificação ~24h não bloqueante:** ligada. `AppComposition.foreground()` chama `syncCatalogueIfDue()` (`:263`), que usa `CatalogSyncPolicy.decision` (janela ~24h) e `CatalogUpdateChannel.fetch()` (conditional GET), fora da barreira de primeira apresentação. O launch só faz `bootstrap()` síncrono local (`AppComposition.swift:188`).
- **Autoridade pública:** default `CatalogUpdateChannel.publicManifestURL = https://raw.githubusercontent.com/wawasoft/feed-repository/main/manifest.json` (`CatalogUpdateChannel.swift:61`). Override só em DEBUG via `FEEDMINE_CATALOGUE_AUTHORITY` (`AppComposition.swift:391-394`).
- **`fetch-catalog.sh`:** **não mudou** o código (ainda aponta `wsmontes/feedmine_v2` release `catalog-v1`, sha `c2ae483…`), mas **foi declarado obsoleto**. `CATALOG.md` diz textualmente que ele está obsoleto e que o caminho atual é `scripts/bootstrap_catalog.py` (fixa a revisão pública, confere cada OPML por tamanho+SHA-256, compila, recusa se o inventário divergir). O catálogo não é mais versionado em Git/LFS nem baixado de release.
- **CATALOG.md:** descreve snapshot derivado da **revisão pública 5** de `wawasoft/feed-repository` (77.443 fontes), com SHA-256 e `derivedFrom`; admite que a cópia anterior (V1) tinha 1/118 OPMLs batendo e foi substituída pela construção a partir dos OPMLs publicados. Marca o estado como "implementação atual, não comportamento aprovado de release" e mantém o gate PD-10 de evidência ponta-a-ponta.
- **Resíduo A07:** o único ponto ainda não resolvido é o script obsoleto não removido/corrigido no repo (texto, não código de produto).

## 5. Fairness / PD-4 no supply misto seleção + descoberta

**PD-4 e a distribuição proporcional aplicam-se uniformemente sobre seleção + descoberta.** (confirmado por leitura)

- As SourceIDs de descoberta entram na elegibilidade de seleção via `SyndicationAcquisitionSnapshot.policyIncludingDiscovery`, que faz `union(discovery.liveSourceIDs())` sobre `.selectedSources` (`ReaderDiscoveryTraversal.swift:94-105`). É chamado tanto no cold start (`ColdFeedBootstrap.swift:290`) quanto no runway contínuo (`FeedRunwayDriver.swift:263,307`).
- `SelectionEngine` deriva `countedSources = selected` do `.selectedSources` (`SelectionEngine.swift:146-149`); como a descoberta já foi unida a esse conjunto, as fontes descobertas **contam** na distribuição proporcional (`SourceAlternation.applyBySupplyShare`). PD-4 (adjacência) usa o conjunto de sources completo de cada candidato (`SourceAlternation.compatible`), independentemente de origem. Não há caminho em que uma fonte descoberta escape à proibição de adjacência ou à partilha proporcional.

## 6. O que falta para B01 passar — lista curta priorizada

Confirmado por leitura: o encanamento (D1/D2 + supply misto + PD-10) existe. O que resta é fragilidade pontual e verificação que exige build/simulador.

1. **D3 — starter set tolerante a key ausente.** Owner: `TrustedFeed.catalog(limit:resourceURL:)` (`TrustedFeeds.swift`). Menor mudança: fazer `catalog` descartar key ausente (como `resolveAvailable`) em vez de lançar `missingDefaultSource`, retornando as keys presentes. Fecha a fragilidade PD-10/D6 sem shortlist nova. *Confirmado por leitura.*
2. **Perfil neutro de B01 depende de idioma/lugar do onboarding.** Owner: `AppComposition.discoveryProfile(for:)` (`AppComposition.swift:1130-1140`). Verificar que o onboarding de B01 realmente grava idiomas/lugares em `key.filter`/`discoveryProfile` **antes** da primeira associação neutra, senão a fase neutra cai nas 4. Menor mudança (se faltar): garantir que o onboarding popula `settings.discoveryProfile`/filtro antes de `launch()`. *Hipótese — não verifiquei o fluxo de onboarding de B01 nem `completeFirstRun`.*
3. **≥50 fontes elegíveis / ≥20 contribuintes nos 300 primeiros cards.** Owner: medição no `DiscoveryBenchmarkTests`/`DiscoveryAcceptance` (fora do produto). Depende de nº de oportunidades × `discoveryExaminedCapacity=120` × admissão por idioma produzir fontes suficientes nos 300 primeiros cards. Não há cota, mas o **ritmo** (1 página por oportunidade) pode ser lento no início; verificar empiricamente. *Hipótese — não medi.*
4. **PD-4 vs supply escasso no início.** Owner: `SourceAlternation` (custo medido: serve fontes escassas primeiro, segura cards). Pode atrasar a diversidade dentro dos 300 primeiros até a travessia ter páginas suficientes. Verificar na matriz B02 junto. *Hipótese.*

## O que não pôde ser verificado

- **Build/simulador/corpus:** nenhum número de runtime (fontes elegíveis/contribuintes, 300 cards, 30 min). B01 "PASS" no `DISCOVERY_ACCEPTANCE_BENCHMARK.md:§5` é afirmação do registro, não verificação minha; o doc `2026-10-12-b04-...` mostra que vereditos recentes mudam (B04 agora NOT_RUN por `idle-stable` não medível) — tratar status do benchmark com ceticismo.
- **Fluxo de onboarding B01** (`completeFirstRun`, escrita de idiomas/lugares/temas antes da primeira associação) não foi lido a fundo.
- **Catálogo real** (`catalog.sqlite`, 118 MB) ausente no checkout: distribuição por idioma e keys canônicas exatas das 4 (item D3) não confirmadas contra os bytes.
- **git/HEAD/branches concorrentes:** não executados; `8274d0c` é o declarado.
