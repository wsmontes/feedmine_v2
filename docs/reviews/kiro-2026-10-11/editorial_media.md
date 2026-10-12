# FeedMine V2 — Revisão estática E3 (editorial, mídia, sindicação)

**Checkout:** `C:\workspace\feedmine_v2-kiro`, branch `main`, HEAD `aefa19f` (não reconfirmado via git nesta máquina — sem toolchain; baseei-me no caminho de checkout fornecido).
**Método:** leitura apenas. Nenhum arquivo do repositório modificado. Sem build/teste Swift (Windows, sem toolchain).
**Área:** `FeedMineEditorial/*`, `FeedMineMedia/*`, `FeedMineSyndication/*`, `FeedMineComposition/MediaHTTPFetcher.swift`, `FeedMineRuntime/{MediaPrefetcher,MediaTidy}.swift`, `FeedMineDomain/{NetworkHostPolicy,Content,ContentLocatorIdentity,MediaCandidate}.swift`.
**Autoridades usadas como régua:** PRODUCT_INVARIANTS (INV-04/05/08/09/16/17), PD-4/5/6/8/9, benchmark B01–B06. Reviews conferidos para "novo vs. já conhecido": `FeedMine_V1_vs_V2_Code_Review_Comparativo_2026-10-09.md` (R15/R16/M13), `CODE_REVIEW_2026-10-08.md` (M12/M13), `DOCUMENTATION_CONSISTENCY_AUDIT_2026-10-10.md`, `F05_RUNWAY_CONTINUITY_DIAGNOSIS_2026-10-10.md`, `F06_SACRED_FEED_CARD_READINESS_PRD.md`, `CODE_REVIEW_COMPARATIVO_2026-10-09.md`.

Achados ordenados por impacto. Severidade: P0 bloqueia aceitação de uma jornada; P1 defeito real sem bloqueio imediato de gate; P2 risco/robustez.

---

## E3-01 — SSRF por redirect na busca do documento de feed (não só mídia) — **P0** — **NOVO**

**Arquivo:** `Sources/FeedMineSyndication/SyndicationHTTP.swift:118-128` (`SyndicationHTTPClient.fetch`, ramo de redirect).

**Trecho:**
```swift
case 301, 302, 303, 307, 308:
    guard redirects < redirectCapacity else { throw ...redirectCapacityExceeded(...) }
    guard let location = hop.location, !location.utf8.isEmpty,
        let destination = URL(string: location, relativeTo: request.url)?.absoluteURL else {
        throw SyndicationHTTPError.missingRedirectLocation(hop.statusCode)
    }
    guard let scheme = destination.scheme?.lowercased(), scheme == "http" || scheme == "https",
        let host = destination.host, !host.isEmpty, destination.user == nil, destination.password == nil else {
        throw SyndicationHTTPError.invalidRedirectTarget
    }
    // v1 lesson IN-2 / review M13: never follow a redirect from https down to http.
    if request.url?.scheme?.lowercased() == "https", scheme == "http" { throw ...invalidRedirectTarget }
    request = URLRequest(url: destination, ...)   // ← nenhum NetworkHostPolicy.isPubliclyRoutable(host)
```

**Por que é defeito:** o alvo do redirect é controlado pelo servidor da fonte (conteúdo não confiável). Diferente de `MediaHTTPFetcher` — que chama `NetworkHostPolicy.isPubliclyRoutable` antes do request, em cada redirect e na URL final (`MediaHTTPFetcher.swift:20,29,61`) — e de `SyndicationMediaLocator.resolve` (`:35`), o caminho de **documento de feed** não valida roteabilidade em nenhum ponto. Uma fonte do catálogo cujo servidor responda `302 Location: http://169.254.169.254/latest/meta-data/...` (metadados de nuvem), `http://127.0.0.1:…` ou `http://192.168.1.1/…` será seguida e o corpo baixado e entregue ao parser. A verificação `grep NetworkHostPolicy.isPubliclyRoutable` confirma: só aparece em `MediaHTTPFetcher.swift` e `SyndicationMediaLocator.swift`; nunca em `SyndicationHTTP.swift` nem no connector. Viola o modelo de segurança R15 (destinos privados vedados em admissão e em cada redirect) e o princípio de que conteúdo de feed é não confiável.

**Escopo R15 (por que é NOVO):** R15 (P1) é explicitamente sobre `SyndicationMediaLocator.resolve()` e `MediaHTTPFetcher.fetch()` — mídia. Esses dois foram corrigidos. O redirect do **documento** não estava no escopo de R15; M13 só tratou o downgrade https→http aqui. Portanto a lacuna de roteabilidade no fetch de documento é nova.

**Cenário de reprodução:** transport fake (ou `URLProtocol`) que, para o endpoint da fonte, devolve `SyndicationHTTPHop(statusCode: 302, location: "http://169.254.169.254/", …)`; depois um `200` com um corpo RSS a partir desse host interno. `SyndicationHTTPClient.fetch` segue o redirect sem rejeitar o host privado.

**Correção mínima:** no ramo de redirect, após obter `host`, exigir `NetworkHostPolicy.isPubliclyRoutable(host)` e lançar `SyndicationHTTPError.invalidRedirectTarget` caso contrário — espelhando `MediaRedirectGuard`. (Opcional, defesa em profundidade: validar o host do `configuration.endpoint` inicial também, embora venha do catálogo.)

**Teste que provaria:** `SyndicationHTTPClient` com transport que emite `302 → http://169.254.169.254/` deve lançar `invalidRedirectTarget` e nunca executar o segundo hop (contador de chamadas do transport == 1). Simetricamente, `302 → https://public.example/feed` continua sendo seguido.

**Não verificável sem toolchain:** se há um bloqueio NSAppTransportSecurity/ATS ou um `URLSessionDelegate` em `AppComposition` que vede hosts privados por fora. Mesmo que exista no app, o módulo de sindicação continua sem a defesa própria que R15 exige "em cada redirect".

---

## E3-02 — Candidato com mídia ainda em download é publicado como text-only imutável — **P0** — **JÁ CONHECIDO** (audit 2026-10-10 item 3; F05_DIAGNOSIS; F06 PRD)

**Arquivos:** `Sources/FeedMineRuntime/MediaPrefetcher.swift:45-54` (`MediaReadiness.presentation(for:)`) + `FeedMineApp/FeedMineApp/AppComposition.swift:1165-1181` (`prepare`).

**Trecho (readiness):**
```swift
public func presentation(for revision: OriginRevisionID) -> PublicationPresentation {
    guard let value = prepared(revision) else { return .textOnly }   // ← nil = "ainda não pronto" OU "text-only definitivo"
    ...
}
```
**Trecho (prepare):**
```swift
.init(inputs: selection.orderedCandidates.map { candidate in
    ...
    presentation: readiness.presentation(for: candidate.originRevisionID))   // ← mapeia TODOS os candidatos; não exclui pendências
```

**Por que é defeito:** `prepared(revision)` é `nil` em dois estados distintos — (a) revision ainda baixando/aguardando retry transitório (`inFlight`, não `settled`), e (b) revision definitivamente text-only (`settled` com valor nil). `presentation(for:)` colapsa ambos em `.textOnly`. `prepare` publica **todos** os `orderedCandidates`, então uma história cuja imagem ainda está chegando é publicada text-only imediatamente. Como a publicação é imutável (INV-08, PD-5 regra 4), a imagem tardia nunca mais corrige o card. Viola INV-17 / PD-5 regra 1-3 / PD-9: "pendente não é quebrado"; o candidato pendente deve **sair da fila de publicação atual** sem reservar posição, não virar text-only por chegar atrasado. É exatamente "timeout virando text-only" e "mídia tardia alterando o layout" na forma mais danosa (decide text-only cedo demais).

**Cenário de reprodução:** supply com imagem lenta (fetch que demora > janela de preparação). `MediaPrefetcher.prefetch` deixa a revision `inFlight` (não settled). Seleção produz o candidato; `prepare` chama `presentation(for:)` → `.textOnly`; `LocalProductionSlice.run` publica. Card congela text-only mesmo quando a imagem chega 1 s depois.

**Correção mínima (sem segundo scheduler — INV-12/PD-9):** `prepare` deve **excluir** da fila pronta os candidatos cujo revision não está `settled` (consultar um predicado de prontidão em `MediaReadiness`, p.ex. `isSettled`), publicando apenas os prontos; os pendentes permanecem no supply elegível e são reconsiderados na próxima seleção. A exclusão deve ocorrer **antes** da alternância PD-4 para não deixar buraco de adjacência no prefixo publicado (ver E3-03). Não é um filtro pós-seleção que perca o cursor.

**Teste que provaria:** corpus com uma história de imagem lenta e várias prontas; após a primeira seleção, a história lenta **não** aparece no lote publicado; nenhuma publicação text-only é criada para ela; quando a imagem settla, uma seleção posterior a publica com `.image`. E: um `settled`-nil legítimo (todas as candidatas definitivamente inválidas) continua publicando text-only.

**Observação:** a auditoria já alerta "não fazer um simples filtro pós-seleção que perca o candidato do cursor/alternância". A correção precisa integrar a prontidão **na** seleção/alternância, não depois.

---

## E3-03 — Exclusão de pendentes aplicada após a alternância PD-4 deixaria adjacência de SourceID no prefixo publicado — **P1** — **NOVO** (dependente de E3-02)

**Arquivos:** `Sources/FeedMineEditorial/SelectionEngine.swift:155-176` + `SourceAlternation.swift` + `AppComposition.swift:1165`.

**Por que é defeito:** a alternância PD-4 (`SourceAlternation.alternation`) roda sobre `orderedCandidates` sem conhecer prontidão de mídia — ela garante que nenhum par adjacente **da lista selecionada** compartilhe SourceID. Se a exclusão de pendentes (E3-02) for feita depois, em `prepare`, remover a história B de uma sequência `A(src1) B(src2) C(src1)` deixa `A(src1) C(src1)` adjacentes no prefixo publicado → viola PD-4 regra 1 ("inclusive na borda dos segmentos") exatamente onde o leitor vê. PD-4 regra 3 exige que a ordem seja decidida pela Editorial a partir das candidatas, "nunca pela ordem de chegada de rede ou mídia"; filtrar por prontidão de mídia fora da Editorial é precisamente deixar a mídia reordenar/reespaçar o feed.

**Cenário de reprodução:** três candidatas prontas em ordem `A(src1), B(src2), C(src1)`; B com imagem ainda pendente. Alternância aprova a tripla (PD-4 ok). `prepare` dropa B → publica `A(src1), C(src1)` adjacentes.

**Correção mínima:** a prontidão de mídia precisa ser uma entrada da seleção/alternância (candidato não pronto é tratado como "não colocável agora", igual a um bloqueado por PD-4 — fica retido e o cursor rebobina via `SelectionSupplyReport`), de modo que o prefixo publicado já respeite PD-4 sem a mídia. É a mesma correção estrutural de E3-02, por isso E3-03 é a prova de que a correção não pode ser um filtro em `prepare`.

**Teste que provaria:** invariante PD-4 sobre a **sequência publicada** com uma candidata intermediária pendente de mídia; nenhum par adjacente publicado compartilha SourceID.

**Não verificável:** se o pipeline integrado já injeta prontidão na seleção (o `prepare` lido indica que não). Marcado P1 porque só se materializa quando E3-02 for corrigido de forma ingênua.

---

## E3-04 — Nenhum teto de 15% por fonte sobre a sequência publicada (B02) — **P1** — **PARCIALMENTE CONHECIDO** (R1_EDITORIAL_DIAGNOSIS §R2 discute distribuição; o teto duro de B02 não é imposto)

**Arquivo:** `Sources/FeedMineEditorial/SourceAlternation.swift` (todo o módulo) e `SelectionEngine.swift`.

**Por que é defeito (de aceitação, não de runtime):** B02 exige "nenhuma fonte acima de 15%" em 200 cards. A alternância v3/v4 (`applyBySupplyShare`/`applyByWeightedSupplyShare`) é **proporcional e por janela**: distribui pela menor fração consumida `served/offered` **dentro da janela corrente**, e os contadores são "deste call apenas; a janela, não a Edition, é a unidade" (comentário em `supplyShare`). Não há acumulador por Edition nem limite rígido de participação. Em um corpus pobre (poucas fontes com muito volume), nada impede uma fonte de ficar acima de 15% ao longo das 200 cards — PD-4 só impede adjacência, não concentração. INV-16/PD-8 proíbem "percentuais editoriais artificiais" como política de runtime, então o teto de 15% é uma **condição de benchmark**, não deveria ser hard-coded; porém **não existe o mecanismo que faça B02 passar** num corpus adversário, e nada no código demonstra que a diversidade por janela converge para ≤15% por Edition.

**Cenário de reprodução:** corpus com 2 fontes "prolíficas" dominando e 18 fontes esparsas; a cada janela a alternância equilibra localmente, mas as prolíficas reaparecem janela após janela; soma por Edition de uma prolífica > 15%.

**Correção mínima:** não hard-codar 15%. O defeito real é E1/E2 (supply de fontes insuficiente). A prova de B02 depende de o universo elegível trazer ≥20 fontes contribuintes com volume comparável; a distribuição por janela já é a ferramenta certa. Recomendo: teste de propriedade que meça participação por SourceID na **sequência publicada completa** sob um corpus rico e falhe se >15% — como *gate*, confirmando que a combinação supply+alternância satisfaz B02 sem cota.

**Teste que provaria:** executar seleção repetida (cursor avançando) sobre corpus rico até 200 cards publicadas; assert `max(count[source]) / 200 <= 0.15` e `distinct(source) >= 20`.

**Não verificável:** o resultado numérico (sem build/corpus). O achado é "o invariante B02 não é imposto em lugar nenhum e depende inteiramente da riqueza do supply, que E1/E2 ainda não comprovam".

---

## E3-05 — `prefetchSupplyHead` prepara mídia ignorando fairness/alternância, podendo gastar orçamento nas fontes prolíficas — **P2** — **NOVO**

**Arquivo:** `Sources/FeedMineRuntime/MediaPrefetcher.swift:120-123` + `MediaTidy.swift:... run` (chama `prefetchSupplyHead`).

**Trecho:**
```swift
public func prefetchSupplyHead(limit: Int, deadline: Double? = nil) async {
    guard limit > 0, let window = try? contentStore.candidateWindow(sourceID: nil, after: nil, examinedCapacity: limit) else { return }
    await prefetch(window.records.map(\.originRevisionID), deadline: deadline)
}
```

**Por que é defeito:** `candidateWindow(sourceID: nil, after: nil, examinedCapacity: limit)` pega os `limit` mais recentes **sem** aplicar a diversidade da Editorial (PD-4/supply-share) nem o filtro de idioma do leitor (`ReaderFilterEligibility`, que só é aplicado em `CandidateProvider`, não aqui). Se as fontes mais prolíficas dominam a cabeça do supply por recência, o orçamento de download (PD-6) é gasto preparando imagens de histórias que a seleção vai reter por PD-4, enquanto fontes escassas (que a seleção precisa para separadores) ficam sem imagem pronta → publicadas text-only por E3-02, ou retidas. Contradiz PD-8 ("preparação adapta-se a demanda") e a intenção de E2 (preparar os próximos candidatos editoriais, não a cabeça bruta por recência). O próprio `prefetch(_ ordered:)` existe justamente para "os próximos candidatos editoriais (review F05)"; `prefetchSupplyHead` ignora essa ordem.

**Cenário de reprodução:** supply onde as 16 revisions mais recentes são todas de 2 fontes; `prefetchSupplyHead(limit: 16)` prepara só essas; a seleção publica 1–2 delas (PD-4) e precisa de fontes escassas sem imagem pronta.

**Correção mínima:** `MediaTidy`/composição deve alimentar `prefetch(_ ordered:)` com a ordem editorial prevista (a mesma `applyBySupplyShare` produz), não com a cabeça bruta do supply. Reutilizar o owner Editorial; não criar segunda fila.

**Teste que provaria:** com supply enviesado por fonte, as revisions preparadas por um ciclo de preparação cobrem ≥N fontes distintas (igual ao que a seleção pediria), não só as 2 prolíficas.

**Não verificável:** o impacto real no runway (precisa B03). É um gargalo plausível de descoberta/runway por leitura do código.

---

## E3-06 — `MediaReadiness` é índice só-em-memória: após reabrir sessão/recriar associação, revisions já settle-adas voltam a `nil` → text-only — **P1** — **PARCIALMENTE CONHECIDO** (comparativo 2026-10-09 §77 nota curta; não há achado estruturado)

**Arquivo:** `Sources/FeedMineRuntime/MediaPrefetcher.swift:19-55` (`MediaReadiness`, dicionários `ready`/`settled` em RAM).

**Por que é defeito:** `MediaReadiness` guarda `ready`/`settled` em `[OriginRevisionID: …]` na memória do processo. Os bytes do asset são duráveis (`AssetStore`, content-addressed), mas o **índice de prontidão** não. Após relançamento a frio ou troca de sessão (3R10 cria store novo), uma revision cuja mídia já foi preparada e cujos bytes estão em disco responde `presentation(for:)` → `.textOnly` até ser reprocessada, porque `prepared()` é `nil`. Combinado com E3-02 (publica tudo), uma Edition nova pode publicar text-only histórias que têm imagem local pronta. Isso tangencia INV-07 (warm launch é local) — a prontidão de mídia deveria derivar do estado local durável, não exigir rede/reprocessamento.

**Cenário de reprodução:** preparar mídia de R (settled .image, bytes em disco); recriar `MediaReadiness` (novo processo/sessão); `presentation(for: R)` → `.textOnly`.

**Correção mínima:** `presentation(for:)`/`prepared(_)` devem consultar o `AssetStore`/`ContentStore` durável (ou reidratar o índice no init a partir dos assets locais) antes de concluir `.textOnly`. Reutilizar `ImageMaterializer.localAsset(for:)`. Não criar cache paralelo.

**Teste que provaria:** materializar mídia, descartar e recriar `MediaReadiness` apontando ao mesmo `assetDirectory`/db, e assert `presentation(for: R)` == `.image(...)` sem nova rede.

**Não verificável:** se a composição real reidrata o índice em algum ponto (não observei isso no `AppComposition.prepare`/`launch` lidos; a restauração a frio usa `admitPresentation`, que publica Edition salva — essa já está congelada, então o risco é para Editions **novas** preparadas após o relançamento).

---

## E3-07 — `firstContentImage` desescapa `&quot;` globalmente e pode casar `<img>` dentro de bloco oculto/comentário — **P2** — **NOVO**

**Arquivo:** `Sources/FeedMineSyndication/SyndicationMediaLocator.swift:88-116` (`firstContentImage`).

**Por que é defeito:** diferente do tokenizer conservador de `ReadablePublicationText` (que suprime `script/style/iframe/object/embed` e comentários), `firstContentImage` roda uma regex `<img\b[^>]*>` sobre o HTML inteiro, incluindo conteúdo dentro de `<!-- … -->`, `<script>`, `<noscript>` ou atributos. Um feed pode esconder uma URL de imagem controlada (tracking/beacon) num comentário ou bloco script e ela vira a imagem do card. Os filtros `isDecorative`/`isUnsupported`/`isPubliclyRoutable` reduzem o dano, mas a extração a partir de contexto não-renderizável é incorreta e explorável para forçar uma imagem escolhida pelo autor do feed. Não é SSRF (roteabilidade é checada), mas é escolha de mídia a partir de markup que um renderer nunca mostraria.

**Cenário de reprodução:** `description` com `<!-- <img src="https://attacker.example/track.png?u=..."> -->` e nenhuma `<img>` visível. `firstContentImage` retorna a URL do comentário.

**Correção mínima:** antes da regex de `<img>`, remover comentários e conteúdo de elementos ocultos (reutilizar a mesma lista `hidden` de `ReadablePublicationText`), ou extrair imagens pelo mesmo tokenizer conservador em vez de regex sobre o texto cru.

**Teste que provaria:** HTML com `<img>` só dentro de comentário/`<script>` → `firstContentImage` retorna `nil`; `<img>` visível legítimo continua retornando a URL.

---

## E3-08 — Entidade `&amp;` dentro de `firstContentImage` não é desescapada; locators com `&amp;` em `src` podem falhar o `resolve` — **P2** — **NOVO (robustez de parsing)**

**Arquivo:** `SyndicationMediaLocator.swift:91-93` (desescape parcial) vs. `:19-21` (`resolve` desescapa `&amp;`/`&#038;`/`&#38;`).

**Por que é defeito:** `firstContentImage` desescapa apenas `&lt;`/`&gt;`/`&quot;` para extrair o atributo, mas o **valor** de `src`/`srcset` extraído ainda pode conter `&amp;`. Esse valor segue para `preferredSrcsetCandidate` (que faz `split(separator: ",")`/por espaço) e para `resolve`. `resolve` desescapa `&amp;`, então o `src` simples sobrevive; porém `preferredSrcsetCandidate` roda **antes** de `resolve` e separa por vírgula/espaço sobre um srcset ainda com `&amp;` — um srcset como `a.jpg?x=1&amp;y=2 960w` tem o `&amp;` preservado (sem espaço, ok), mas entidades numéricas de vírgula/espaço escapadas quebrariam o parsing de candidatos. É um defeito de robustez de parsing RSS/Atom (feeds reais escapam `&` em atributos), parcialmente mitigado em `resolve` mas não no caminho de srcset.

**Cenário de reprodução:** `description` com `<img srcset="https://cdn/a.jpg?w=960&amp;s=x 960w, https://cdn/b.jpg?w=480&amp;s=y 480w">`. `preferredSrcsetCandidate` divide por `,` e por espaço corretamente neste caso, mas o descriptor é lido como `960w` ✓ — o `&amp;` sobrevive e `resolve` o normaliza. O caso quebrado é com entidade que contém vírgula/espaço codificado. Severidade P2: impacto é "perde a imagem" (degrada para text-only por E3-02), não corrompe.

**Correção mínima:** desescapar `&amp;`/`&#038;`/`&#38;` no valor do atributo em `firstContentImage` antes de `preferredSrcsetCandidate`, unificando com `resolve`.

**Teste que provaria:** srcset com `&amp;` entre candidatos resolve o candidato esperado em vez de `nil`.

---

## E3-09 — Clamp de data futura usa `min(claimed, observedAt)` mas identidade de versão depende do fingerprint, não da data clampada — risco de reaparição por `observedAt` — **P2** — **NOVO** (interação com PD-1/M12)

**Arquivo:** `Sources/FeedMineSyndication/SyndicationTranslator.swift:63-78` (`observation`/`clamped`/`materialVersion`).

**Por que é defeito:** `clamped` fixa `authored/modified` a `observedAt` (bom, M12). Mas `materialVersion` concatena `claimed.value + ":" + materialFingerprint(...)`, onde `materialFingerprint` cobre título/summary/body/link/mídia — **não** a data. Correto para PD-1 (edição material = novo revision). Porém o `authoredAt`/`modifiedAt` clampado entra na **ordenação por recência** da seleção (`SelectionEngine` ordena por `timestamp.value`). Dois pulls do mesmo item em dias diferentes, sem mudança material, geram o **mesmo** `versionIdentity` (fingerprint igual) — ok, não reaparece — mas o `sortDate` do candidato pode mudar entre observações se o store usa `observedFallback` quando `authored` é nil. Resultado possível: um item sem data autoral confiável sobe no feed a cada observação (via `observed` fallback clampado a `observedAt`), aproximando-se do bug IN-4/M12 que o clamp pretendia evitar — não via data futura, mas via `observedAt` crescente como chave de ordenação.

**Por que marco P2 e não P1:** depende de `ContentStore.sortDateBasis`/`candidateWindow` (fora da minha área E3; não li a persistência) decidir usar `observed` como sortDate e de o store **atualizar** esse valor a cada observação. Não pude verificar isso. Se o store congela o `sortDate` no primeiro registro do revision, não há bug. Reporto como risco a confirmar.

**Cenário de reprodução (a confirmar na persistência):** item RSS sem `pubDate` e GUID estável; pull dia 1 e dia 2; se o candidato apresenta `timestamp.kind == .observed` com valor = `observedAt` do pull mais recente, ele reordena para o topo sem edição material.

**Correção mínima (se confirmado):** congelar o sortDate observado na primeira admissão do revision; observações seguintes do mesmo revision não movem a chave de ordenação.

**Teste que provaria:** dois pulls do mesmo revision sem mudança material → `candidate.timestamp.value` idêntico nos dois.

**Não verificável:** semântica de `sortDateBasis`/atualização em `ContentStore` (não lida; fora da área). Explicitamente marcado.

---

## E3-10 — `playback` enclosure aceita MIME declarado sem checar roteabilidade antes de virar ação `mediaPlayback` — **P2** — **NOVO**

**Arquivo:** `SyndicationTranslator.swift` (`playback`) → `SyndicationMediaLocator.resolve(..., allowingPlayableMedia: true)` (`:28-39`) → `AppComposition.prepare` (`primaryAction: .mediaPlayback(url)`).

**Por que é defeito:** `resolve(allowingPlayableMedia: true)` **mantém** a checagem `NetworkHostPolicy.isPubliclyRoutable` (linha `:35` aplica a ambos os casos), então o host privado é vedado na admissão — bom. Porém a URL de playback vira `primaryAction: .mediaPlayback(url)` e, no F15 (player), será carregada por `AVPlayer`/`URLSession` **sem** o guard de redirect de `MediaHTTPFetcher`. Um enclosure de áudio cujo host é público mas que **redireciona** para um host privado em tempo de play não tem o `MediaRedirectGuard`. Hoje não há player integrado (F15 pendente), então é latente, mas o contrato "feed é não confiável, veto em cada redirect" não se estende ao caminho de playback.

**Cenário de reprodução (futuro, quando F15 existir):** enclosure `https://public/ep.mp3` que redireciona 302 para `http://169.254.169.254/…`.

**Correção mínima:** quando o player for implementado (F15), reutilizar um guard de redirect equivalente ao `MediaRedirectGuard` para o transporte de playback. Documentar como pré-condição de F15.

**Teste que provaria:** carregar enclosure que redireciona a host privado deve falhar o fetch de playback.

**Não verificável:** não há código de player no checkout para confirmar o caminho real.

---

## E3-11 — `MediaResolver` descarta candidatas com dimensões declaradas inválidas em vez de inspecioná-las por bytes — perde imagens boas rotuladas errado — **P2** — **NOVO**

**Arquivo:** `Sources/FeedMineMedia/MediaResolver.swift:40-55`.

**Trecho:**
```swift
if width > policy.ceilings.maximumPixelSide || height > policy.ceilings.maximumPixelSide { continue }
if width < minimum { continue }
```

**Por que é defeito:** feeds declaram dimensões erradas com frequência (lição v1: "declared dimensions are hints, measured dimensions decide" — está no próprio cabeçalho do arquivo). Aqui, uma candidata com `declaredPixelWidth` abaixo do `minimum` (ou acima do ceiling) é **descartada antes de qualquer byte**, embora a imagem real possa ser boa. A regra correta por v1/PD-6 é: dimensões declaradas são dica; só a medição decide `fit`. Candidatas com dimensão **desconhecida** (`unknown`) são corretamente mantidas e baixadas; mas as declaradas-pequenas são eliminadas sem medir. Isso reduz cobertura de mídia (mais text-only via E3-02) por confiar num hint que o resto do sistema trata como não confiável.

**Observação de equilíbrio:** descartar declaradas-acima-do-ceiling é defensável (proteção decode-bomb antes de baixar). Descartar declaradas-abaixo-do-mínimo não é — o custo é só baixar e medir, e a medição já rejeita o que for pequeno (`policy.fit` → `.unsuitable`).

**Correção mínima:** mover candidatas com `declaredPixelWidth < minimum` para a lista `unknown`/`undersized` (baixar e medir) em vez de `continue`; manter o descarte só para o teto de segurança.

**Teste que provaria:** candidata com `declaredPixelWidth: 10` mas imagem real 1200px é escolhida e vira `.hero` após medição, em vez de ser descartada.

---

## E3-12 — `isMalformedNestedScheme` só reconhece aninhamento http(s); proxies `?url=//host` ou com esquema ausente passam — **P2** — **NOVO**

**Arquivo:** `SyndicationMediaLocator.swift:154-162` (`isMalformedNestedScheme`).

**Por que é defeito:** a função detecta `.../https://real-host` (proxy/colagem) quando o alvo tem esquema explícito e o caractere anterior não é `/` nem `=`. Mas um proxy comum é `https://img.cdn/resize?url=%2F%2Fattacker/...` ou `?u=//host/...` (sem esquema, protocol-relative) — esses não têm `http://`/`https://` embutido, então `nested == nil` e passam. O risco é baixo (o host final ainda é o do proxy, público) mas a mídia real exibida pode ser escolhida pelo autor do feed via proxy, driblando `isDecorative`. É robustez de parsing, não SSRF.

**Correção mínima:** além de esquema aninhado, tratar `url=`/`u=`/`image=` com valor que começa por `//` ou `%2F%2F` como suspeito, ou simplesmente aceitar que o host do proxy é o que conta (comportamento atual) e documentar que proxies não são desembrulhados. Baixo impacto; incluído por completude do checklist "proxies".

**Teste que provaria:** `https://proxy/resize?url=//evil/x.png` — definir o comportamento esperado e travá-lo com teste (hoje é aceito silenciosamente).

---

## Itens verificados que NÃO são defeito (para evitar retrabalho)

- **IPs decimal/octal/hex e IPv4-mapped IPv6:** `NetworkHostPolicy.isPubliclyRoutable` bloqueia `2130706433`, `0177.0.0.1`, `127.1`, `0x7f.1` (via ramo `labels.allSatisfy(numeric)` → `false`) e `::ffff:127.0.0.1`/`::ffff:7f00:1` (via `dottedQuad`/bloqueio conservador). `::`, `::1`, `fc00::/7`, `fe80::/10`, `ff00::/8` bloqueados. **Verificado por leitura.**
- **Downgrade https→http:** vedado em `SyndicationHTTP` (`:126`), `MediaHTTPFetcher` (`:27`) e `MediaRedirectGuard` (`:60`). M13 corrigido.
- **Userinfo em URL (`user:pass@host`):** rejeitado em `SyndicationTargetConfiguration`, `webURL`, `resolve`, redirect do documento. OK.
- **`data:`/`javascript:` em locators de mídia:** rejeitados (`resolve :16`).
- **Entidades HTML no texto legível:** tabela HTML 4.01 completa; nomes desconhecidos ficam literais; tokenizer suprime `script/style/iframe/object/embed` e comentários (ReadablePublicationText). Sólido.
- **Teto de bytes em streaming:** `SyndicationHTTP` e `MediaHTTPFetcher` cortam no primeiro byte além da capacidade, mesmo com Content-Length ausente/mentiroso. OK.
- **Decode-bomb:** `MediaPolicy.fit` checa `maximumPixelSide`/`maximumPixelCount` com proteção de overflow; `ImageMaterializer.inspect` não decodifica pixels (só propriedades). OK.

## Limitações desta revisão (o que NÃO pôde ser verificado)

- **Sem build/test Swift** (Windows, sem toolchain): nenhum achado foi reproduzido executando; todos derivam de leitura de código e das réguas de produto. Os "testes que provariam" são propostas, não executados.
- **HEAD não reconfirmado por git** nesta máquina; assumi `aefa19f` conforme o enunciado.
- **Persistência (`ContentStore`/`PublicationStore`/`candidateWindow`/`sortDateBasis`)** está fora da área E3 e não foi lida a fundo — E3-09 depende dela e fica como risco a confirmar.
- **Composição de player (F15)** e eventual `URLSessionDelegate`/ATS global em `AppComposition` não foram auditados por inteiro; E3-01 e E3-10 observam a ausência da defesa **no módulo**, independentemente de mitigação externa.
- **Números de B01–B06** (participação por fonte, cobertura, continuidade) não medidos; E3-04 é estrutural, não empírico.

## Resumo priorizado

| ID | Sev | Área | Novo? |
|----|-----|------|-------|
| E3-01 | P0 | SSRF redirect no fetch de documento de feed | Novo |
| E3-02 | P0 | Pendente de mídia → text-only imutável | Já conhecido (audit §3, F06) |
| E3-03 | P1 | Exclusão de pendente quebraria PD-4 se feita pós-alternância | Novo (dep. E3-02) |
| E3-04 | P1 | Teto de 15% (B02) não imposto; depende do supply | Parcial (R1 §R2) |
| E3-06 | P1 | Readiness só-em-memória → text-only após relançamento | Parcial (comparativo §77) |
| E3-05 | P2 | prefetchSupplyHead ignora fairness/idioma | Novo |
| E3-07 | P2 | firstContentImage casa `<img>` em comentário/script | Novo |
| E3-08 | P2 | `&amp;` não desescapado no caminho de srcset | Novo |
| E3-09 | P2 | sortDate observado pode reordenar sem edição (a confirmar) | Novo |
| E3-10 | P2 | Playback enclosure sem guard de redirect (latente, F15) | Novo |
| E3-11 | P2 | MediaResolver descarta declaradas-pequenas sem medir | Novo |
| E3-12 | P2 | isMalformedNestedScheme não cobre proxies `?url=//` | Novo |

**Maior impacto para a promessa central:** E3-02 (mídia tardia/pendente destruindo a imagem do card de forma imutável) e E3-05 (preparação sem fairness) atacam diretamente E2/E3 — runway e qualidade editorial. E3-01 é o único problema de segurança P0 e é independente/barato de corrigir. E3-03 é a armadilha a evitar ao corrigir E3-02.
