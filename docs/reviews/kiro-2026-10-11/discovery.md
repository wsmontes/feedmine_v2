# FeedMine V2 — Revisão estática E1 (descoberta de fontes e catálogo)

**Checkout:** `C:\workspace\feedmine_v2-kiro`, branch `main`, HEAD `aefa19f` (declarado; não verificado por git nesta máquina Windows sem toolchain).
**Natureza:** revisão apenas por leitura. Nenhum arquivo do repositório modificado. Sem `swift build`/`swift test`/simulador.
**Área:** E1 — catálogo → targets → contato → admissão → fontes contribuintes; PD-10.
**Pergunta central:** por que o feed fica preso a poucas fontes (ensaio ~135 cards / 4 fontes apesar de 77.443 no catálogo).

## Resposta direta à pergunta central

**Porque o universo de aquisição em runtime é, por construção, uma lista fixa de 4 chaves — o catálogo de 77.443 fontes nunca alimenta a aquisição, só a UI de navegação/busca.**

Cadeia exata (cada elo citado abaixo em D1):
`TrustedFeed.catalog` tem uma lista literal de **4 keys** → `AppComposition.feeds` (≤4) → `FeedAssociation` registra **um target por feed** (`authorizedSources: [feed.sourceID]`) → `SyndicationAcquisitionSnapshot.eligibleTargets` itera **só essas registrations** → `ColdFeedBootstrap` e `FeedRunwayDriver` planejam aquisição **só sobre esses targets** → a seleção editorial tem `eligibility: .selectedSources(Set(feeds.map(\.sourceID)))`, ou seja ≤4 SourceIDs. Não existe nenhum caminho que promova uma linha do catálogo a target sem um toque explícito do usuário. A "exploração progressiva" de PD-8/INV-16 **não está implementada**: `LegacyCatalogImport.entries(from:limit:)` (a única função de importação paginada em massa) **não é chamada em lugar nenhum** do app ou de `Sources/`.

O limite não é `reserveCards: 16` nem os probes (esses governam runway/E2). O limite é a **largura do conjunto elegível = 4**. Com 4 fontes RSS e exposição `.excludePublishedMaterial`, o supply elegível esgota em poucas dezenas/centenas de itens; ~135 cards é consistente com isso.

---

## Achados (ordenados por impacto)

### D1 — P0 — O universo de aquisição é uma lista fixa de 4 fontes; o catálogo nunca entra na aquisição
**Status:** já conhecido em alto nível (DOCUMENTATION_CONSISTENCY_AUDIT_2026-10-10, "P0/P1 não corrigidos" item 2; F05_RUNWAY_CONTINUITY_DIAGNOSIS achado 5). **Mecânica exata e prova de que `limit` é inócuo: novo.**

**Arquivo:linha / trecho citado:**

`FeedMineApp/FeedMineApp/TrustedFeeds.swift:32-45` — a lista é literalmente 4 keys e `limit` só corta sobre ela:
```swift
static func catalog(limit: Int, resourceURL: URL?) throws -> [TrustedFeed] {
    ...
    let keys = ["https://feeds.bbci.co.uk/news/rss.xml", "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
        "https://feeds.npr.org/1001/rss.xml", "https://theguardian.com/world/rss"]
    return try keys.prefix(limit).map { key in ... }
}
```

`FeedMineApp/FeedMineApp/AppComposition.swift:242` — `limit: 64` sobre uma lista de 4 → ainda 4:
```swift
init(..., feeds: [TrustedFeed] = TrustedFeed.catalogOrDevelopment(limit: 64), ...)
```

`FeedMineApp/FeedMineApp/AppComposition.swift:1069-1077` — único registro de targets em runtime, só sobre `feeds`, **um source por target**:
```swift
let registrations = try feeds.map { feed in
    let target = try existing ?? authority.register(id: feed.targetID,
        connectorKind: .syndication, authorizedSources: [feed.sourceID])
    ...
}
```

`FeedMineApp/FeedMineApp/AppComposition.swift` (init de `FeedAssociation`) — a elegibilidade editorial é fechada no conjunto `feeds`:
```swift
eligibility: .selectedSources(Set(feeds.map(\.sourceID)))
```

`Sources/FeedMineComposition/SyndicationAcquisitionSnapshot.swift:89-112` — `eligibleTargets` percorre apenas `registrations`.

**Por que é defeito (invariante/PD/gate):** viola PD-8 ("todo o catálogo elegível é universo de exploração progressiva … cada fonte elegível eventualmente recebe oportunidade de contato"), INV-16 (idem; "proibido número mágico como política … contagens permanentes de fontes") e o gate B01/F01 (no cenário rico, ≥50 fontes no conjunto elegível e ≥20 fontes contribuintes nos primeiros 300 cards). Hoje o teto é 4.

**Prova no próprio repositório (sem rodar):** `FeedMineApp/FeedMineAppTests/CompositionTests.swift:193-194` afirma `catalog(limit: 2).count == 2` e que `catalog(limit: 64)` é o mesmo conjunto — isto é, `limit` nunca excede o tamanho da lista literal. `LegacyCatalogImport.entries(from:limit:)` (`Sources/FeedMineComposition/LegacyCatalogImport.swift:…`) existe para paginar o catálogo inteiro mas **grep em `Sources/` e `FeedMineApp/` retorna zero chamadas** fora de testes.

**Cenário de reprodução:** build com o `catalog.sqlite` real (77.443 fontes). Cold start em `.main`. Observar que `eligibleTargets(for: .main)` retorna 4 targets e que, após esgotar BBC/NPR/Guardian, nenhuma nova fonte é contatada mesmo com runway/recursos sobrando e scroll contínuo. ≈ o ensaio de 135 cards.

**Correção mínima proposta (dentro dos owners existentes, sem segundo pipeline):**
A responsabilidade de "quais fontes elegíveis existem" é do Acquisition/catálogo, não da lista `feeds` da UI. Introduzir uma fonte de elegibilidade progressiva lida de `LegacyCatalogReader` (idioma como filtro rígido — ver D2) que `SyndicationAcquisitionSnapshot.eligibleTargets(for: .main)` consome, materializando targets sob demanda via `authority.register`/`materializeSources` em lotes limitados por recurso (não por contagem permanente). O starter set de 4 permanece como bootstrap da primeira tela; a cada oportunidade de aquisição o planner (que já suporta `selectionAfter` como anel mecânico — `AcquisitionPlanner.plan`) avança o cursor por **novas** fontes do catálogo, respeitando `coolingTargetIDs`, `targetWorkCapacity` e fairness. Não trocar 4 por 50 fixas: o conjunto elegível deve ser o catálogo filtrado por idioma, visitado progressivamente.

**Teste que provaria:** integração com catálogo-fixture de ≥300 fontes elegíveis; após N oportunidades de aquisição com runway saudável e recursos disponíveis, asserção de que o número de **targets distintos contatados** cresce muito além de 4 e que ≥20 SourceIDs distintos aparecem nos primeiros 300 cards publicados, sem adjacência PD-4. (É exatamente a prova B01 esperada pela diretriz.)

**Não pôde verificar:** o volume/tempo real (precisa de build + simulador + corpus); se há um branch concorrente com descoberta progressiva já iniciada (a diretriz E0 pede reler HEAD e comparar branches — não feito aqui).

---

### D2 — P0 — Idioma do leitor não é filtro rígido de elegibilidade em lugar nenhum da aquisição/seleção
**Status:** novo (a auditoria menciona "idioma como filtro rígido" como requisito pendente, mas não aponta a ausência no código; aqui está a localização).

**Arquivo:linha / trecho:**
- O `language` existe no catálogo (`Sources/FeedMinePersistence/LegacyCatalogReader.swift`, `LegacyCatalogSourceRecord.language`, `languages()`), mas o único consumo é a **UI de filtro** (`AppComposition.filterLanguages()`, `onboardingOptions()`), nunca a elegibilidade de aquisição.
- `LegacyCatalogImport.entry(_:)` carrega `language` no `LegacyCatalogEntry`, porém `TrustedFeed`/registration **descartam** o idioma; `eligibleTargets` e `.selectedSources(...)` não têm noção de idioma.

**Por que é defeito:** PD-8 e INV-16 declaram "idioma selecionado pelo leitor é regra rígida de elegibilidade de conteúdo". Quando D1 for corrigido (abrir o catálogo à aquisição), **sem** este filtro a descoberta progressiva passaria a contatar fontes de qualquer idioma — violando PD-8 e poluindo B01/B02 (relevância ≥80% com rótulos externos). É um defeito latente que a correção de D1 ativaria; precisa ser resolvido junto.

**Cenário de reprodução:** após habilitar exploração do catálogo, um leitor "pt" receberia fontes `en`, `und`, etc., porque nada restringe o conjunto elegível por idioma.

**Correção mínima:** a fonte de elegibilidade progressiva de D1 filtra por `primarySubtag` do idioma do leitor (comparando subtag primária, como o V1 fazia — já há `LegacyCatalogLanguageRecord.primarySubtag`); `und`/vazio nunca é apresentável como idioma selecionável (o reader já marca `isUndeclared`). Owner: catálogo/Acquisition boundary, não a UI.

**Teste:** fixture multilíngue; leitor "pt" → asserção de que todo SourceID elegível/contactado declara idioma com subtag primária `pt`; nenhuma fonte `en`/`und` contribui.

**Não pôde verificar:** se o modelo de preferências já persiste o idioma do leitor de forma consumível pela aquisição (li `ReaderFilter.languages` só no caminho de UI/contexto; não li `ReaderPreferencesStore` a fundo).

---

### D3 — P1 — Starter set hard-coded quebra o app em release se qualquer das 4 keys sumir do catálogo gerenciado
**Status:** novo.

**Arquivo:linha / trecho — `FeedMineApp/FeedMineApp/TrustedFeeds.swift:37-44`:**
```swift
let keys = ["https://feeds.bbci.co.uk/news/rss.xml", ".../science_and_environment/rss.xml",
    "https://feeds.npr.org/1001/rss.xml", "https://theguardian.com/world/rss"]
return try keys.prefix(limit).map { key in
    guard let record = try reader.source(key: key), let entry = LegacyCatalogImport.entry(record) else {
        throw TrustedCatalogError.missingDefaultSource(key)   // <- lança
    }
    ...
}
```
E em `catalogOrDevelopment(limit:)` (linha 66-75), no release (`#else`) qualquer throw vira `return []`, e `AppComposition.init` (linha ~305) faz:
```swift
if feeds.isEmpty { startupFailure = "Não foi possível carregar o catálogo local de fontes." }
```

**Por que é defeito:** PD-10 diz explicitamente que uma revisão pública pode **remover/reclassificar fontes e alterar URLs**, e que remoção do catálogo gerenciado **não** pode inutilizar o app. Aqui, se o catálogo embarcado numa release futura (sincronizado da autoridade pública) não contiver exatamente `theguardian.com/world/rss` com essa key canônica, o starter set lança e o app sobe com **falha de inicialização** — exatamente o cenário que PD-10 proíbe. As keys também parecem frágeis: `"https://theguardian.com/world/rss"` sem `www.` pode não ser a key canônica normalizada do snapshot.

**Cenário de reprodução:** editar/renomear uma das 4 keys no `catalog.sqlite` (simula uma revisão pública) → `catalog(limit:)` lança `missingDefaultSource` → release mostra `startupFailure`, sem feed.

**Correção mínima:** tratar o starter set como preferência best-effort, não configuração obrigatória — mapear as keys disponíveis e, se faltarem, cair para "as N primeiras fontes elegíveis por idioma do catálogo" (reutilizando a fonte de elegibilidade de D1), nunca lançar/retornar vazio por uma key ausente. `resolveAvailable` já adota essa filosofia ("a key que o catálogo não contém é descartada"); `catalog(limit:)` deveria seguir a mesma regra.

**Teste:** fixture de catálogo sem uma das 4 keys → asserção de que `catalogOrDevelopment` retorna um starter set não vazio e o app não registra `startupFailure`.

**Não pôde verificar:** a key canônica exata do Guardian no snapshot real (precisa abrir o `catalog.sqlite`, 118 MB, ausente neste checkout; `scripts/fetch-catalog.sh` baixa sob demanda).

---

### D4 — P1 — `.main` com 1 fonte selecionada vira contexto de fonte única e desliga alternância PD-4, podendo estreitar ainda mais a descoberta
**Status:** novo.

**Arquivo:linha / trecho — `FeedMineApp/FeedMineApp/AppComposition.swift`** (em `toggleSource` e `adoptSelectionChange`):
```swift
let request: FeedContextRequest = next.count == 1 ? .source(next[0].sourceID) : .main
```
E `SyndicationAcquisitionSnapshot.eligibleTargets` para `.source(let source)` filtra `registrations` à fonte única; PD-4 regra 4 isenta contexto de fonte única da alternância.

**Por que é defeito:** quando o usuário reduz a seleção a 1 fonte, o app silenciosamente entra em `.source(...)`, o que (a) por definição exclui qualquer descoberta de outras fontes e (b) desativa a alternância PD-4. Isso é defensável como escolha explícita do leitor, mas combinado com D1 significa que o caminho "neutro" (`.main`) nunca explora além das 4 e o caminho de 1 fonte nunca explora nada — não há estado em que a exploração progressiva de PD-8 aconteça. É o reforço do aprisionamento, não a causa raiz (D1 é a causa raiz).

**Cenário de reprodução:** selecionar 1 fonte → `.source` → feed preso a 1 SourceID por design; voltar a `.main` → preso a 4.

**Correção mínima:** nenhuma mudança neste comportamento isoladamente (é intencional por PD-4 regra 4); a correção pertence a D1 — `.main` deve explorar o catálogo progressivamente, de modo que o estado neutro deixe de ser "4 fontes".

**Teste:** coberto por D1 (contexto `.main` contata >4 fontes).

**Não pôde verificar:** intenção de produto para 1-fonte-selecionada (parece deliberada; não é reportada como bug, apenas como fator agravante).

---

### D5 — P1 — PD-10 não implementado: release embarca catálogo derivado da V1 (release do próprio repo V2), não da revisão pública `wawasoft/feed-repository`, e não há reconciliação
**Status:** já conhecido (DOCUMENTATION_CONSISTENCY_AUDIT item 1; OMP update `8c31b83`). Localização e lacunas confirmadas.

**Arquivo:linha / trecho — `scripts/fetch-catalog.sh:8-12`:**
```sh
TAG="catalog-v1"
URL="https://github.com/wsmontes/feedmine_v2/releases/download/${TAG}/catalog.sqlite"
SHA256="c2ae483a7525fd2b6797855149eb6fb312abbed788549a90a7754121eb5c8629"
SIZE=117940224
```

**Por que é defeito:** PD-10/INV-18 definem `https://github.com/wawasoft/feed-repository` como autoridade e exigem: (1) snapshot da release derivado da **revisão pública validada** com procedência rastreável; (2) verificação ~24h não bloqueante em launch/foreground; (3) staging + validação SHA-256/tamanho/esquema + ativação atômica; (4) aplicar adição/remoção/edição só a trabalho futuro, sem tocar em salvos/história/`runtime.sqlite`. **Nada disso existe no código.** O script baixa de uma release do **próprio repositório V2** (`wsmontes/feedmine_v2`), derivada da V1; contagem igual (77.443) não prova identidade de revisão com a autoridade pública. Não há leitor de `manifest.json`, nem verificação periódica, nem caminho de staging/ativação atômica em `Sources/`.

**Cenário de reprodução:** inspeção estática — não há símbolo que leia `manifest.json` nem referência a `wawasoft/feed-repository` no código; `grep` por `manifest` em `Sources/` esperado vazio (não executado aqui, inferido de ausência nos arquivos E1 lidos).

**Correção mínima:** fora de E1-descoberta-runtime (é F09/F10). Implementar um reconciliador de catálogo com owner único (Acquisition/Persistence), disparado em oportunidade legítima (launch/foreground, idade >~24h), que faz staging de um novo `catalog.sqlite` validado por manifesto/SHA-256 e ativa atomicamente, preservando `runtime.sqlite`. Não bloquear primeira apresentação (INV-07) nem criar segundo scheduler.

**Teste:** revisão igual → sem substituição; revisão nova com add/remove/edit → reflete só em elegibilidade futura; manifesto/arquivo inválido → mantém snapshot anterior; salvos/história intactos.

**Não pôde verificar:** confirmação por `grep` de ausência total de leitura de manifesto (li os arquivos E1; não varri `FeedMinePersistence` inteiro além de `LegacyCatalogReader`/`AcquisitionTargetStore`/`AcquisitionAdmissionStore`).

---

### D6 — P2 — `TrustedFeed.resolveAvailable` abre o catálogo via `Bundle.main` e lança se ausente; caminho de bootstrap frágil fora do app bundle
**Status:** novo (menor).

**Arquivo:linha / trecho — `FeedMineApp/FeedMineApp/TrustedFeeds.swift:52-63`:**
```swift
if reader == nil {
    guard let url = Bundle.main.url(forResource: "catalog", withExtension: "sqlite") else { throw TrustedCatalogError.missingResource }
    reader = try LegacyCatalogReader(catalogURL: url)
}
```

**Por que é defeito (leve):** `resolveAvailable` é chamado no `init` de `AppComposition` para resolver as keys salvas do leitor. Se o recurso `catalog.sqlite` não estiver no bundle (ex.: build sem rodar `fetch-catalog.sh`), lança e vira `startupFailure` de seleção — enquanto `catalogOrDevelopment` já tratou o mesmo caso de forma mais graciosa. Inconsistência de robustez entre os dois caminhos que leem o mesmo asset. Não é a causa do aprisionamento; é risco de robustez de boot.

**Correção mínima:** uniformizar o tratamento de catálogo ausente entre `catalog(limit:)`, `catalogOrDevelopment` e `resolveAvailable` (mesma política best-effort de D3).

**Teste:** boot sem asset de catálogo → app sobe com development feeds (DEBUG) ou falha de startup única e clara (release), nunca dois comportamentos divergentes para o mesmo asset ausente.

**Não pôde verificar:** se o projeto Xcode inclui `catalog.sqlite` em Copy Bundle Resources (o pbxproj não foi lido; F02 histórico sugere que a distribuição foi resolvida via release asset + script).

---

## O que não pôde ser verificado (global)

- **Build/execução:** sem toolchain Swift/simulador nesta máquina Windows; nenhum número de runtime (contagem de fontes contatadas, duração, 135 cards) foi medido. Todos os achados são de leitura de código.
- **HEAD/branches concorrentes:** não executei git; HEAD `aefa19f` é o declarado. A diretriz E0 pede comparar `main` com branches em execução antes de concluir status — não feito.
- **Catálogo real:** `catalog.sqlite` (118 MB) não está no checkout; keys canônicas exatas e distribuição por idioma não confirmadas contra o snapshot.
- **Varredura completa de `Sources/`:** li a fundo os arquivos E1 listados e os stores de persistência relevantes; não varri todo `FeedMinePersistence`/`FeedMineEditorial`, então a afirmação "idioma nunca é filtro rígido" e "nenhum leitor de manifesto" baseia-se nos caminhos E1 lidos + grep dirigido, não numa varredura exaustiva.

## Resumo para o owner

Causa raiz do aprisionamento = **D1**: a aquisição opera sobre uma lista fixa de 4 fontes; o catálogo de 77.443 só serve a UI. `limit: 64`, `reserveCards: 16` e os probes são irrelevantes para isto. Corrigir D1 exige, no mesmo gate, **D2** (idioma como elegibilidade rígida) para não violar PD-8/B01 ao abrir o catálogo. **D3/D6** endurecem o bootstrap para não quebrar quando o catálogo mudar (PD-10). **D5** é a implementação pendente de PD-10 (F09/F10), separada da exploração runtime. **D4** é agravante por design, resolvido por D1.
