# Product invariants

Regras arquiteturais obrigatórias e não negociáveis.

## INV-01 — Local presentation

A UI apresenta estado local.

Nenhum renderer depende de uma resposta de rede para continuar mostrando conteúdo já publicado.

## INV-02 — Network outside UI

SwiftUI nunca:

- inicia acquisition;
- chama connector;
- consulta banco diretamente;
- resolve mídia remota;
- implementa retries;
- implementa pagination de protocolo.

## INV-03 — Scroll is observation

Scroll não significa:

```text
loadMore()
fetchNextPage()
downloadMore()
```

Scroll produz apenas uma observação de viewport/consumo.

O Runtime decide se precisa preparar mais supply.

## INV-04 — Adaptive runway

FeedMine mantém uma quantidade adaptativa de conteúdo presentation-ready à frente do consumo.

Não usar como estratégia arquitetural:

```text
sempre 10 cards
sempre 20 cards
sempre 50 cards
fetch a cada N segundos
fetch quando faltarem exatamente N cards
```

Um número pode existir como limite operacional ou configuração.

Ele não pode representar a lógica conceitual do sistema.

Runway deve responder a fatores como:

- velocidade de consumo;
- quantidade local disponível;
- custo de acquisition;
- estado de rede;
- estado de background;
- disponibilidade de mídia;
- histórico recente;
- contexto editorial;
- pressão de memória;
- restrições de energia;
- capacidade atual do device.

## INV-05 — Work continues after first presentation

Quando os primeiros cards aparecem, apenas o bloqueio percebido pelo usuário terminou.

O trabalho de preparação não terminou.

Acquisition, admission, media preparation e preparação futura continuam enquanto houver benefício e orçamento operacional.

## INV-06 — First launch may legitimately take time

No primeiro launch sem supply local suficiente, FeedMine pode exibir uma experiência de preparação.

Essa experiência deve no futuro conseguir mostrar progresso e evidência do conteúdo que está chegando.

Não falsear instantaneidade.

## INV-07 — Warm launch is local

Quando existe supply/publication local válida:

```text
launch
→ restore session/publication
→ materialize local window
→ show feed
```

Não aguardar:

- network;
- connector;
- catalog refresh;
- image download;
- fresh selection.

## INV-08 — Published history is immutable

Uma vez publicado um segmento de feed para uma sessão, acquisition futura não pode silenciosamente reconstruir ou reorderar aquele segmento.

Novos dados afetam supply futura e publicação futura.

## INV-09 — Background work does not disturb visible history

Trabalho de background aumenta capacidade futura.

Não modifica silenciosamente o que o usuário já está vendo.

## INV-10 — Context changes reprioritize; they do not destroy gratuitously

Quando o usuário muda filtro/contexto:

- o novo contexto recebe prioridade;
- trabalho futuro é redirecionado;
- contexto anterior pode permanecer localmente reutilizável;
- voltar rapidamente a um contexto recente não deve exigir reconstrução completa se o trabalho ainda é válido.

## INV-11 — Offline is a first-class condition

O sistema deve obter o máximo benefício razoável do estado local existente.

Network é uma fonte de reposição de supply.

Network não é o feed.

## INV-12 — One owner per responsibility

Cada responsabilidade possui exatamente um owner arquitetural.

Não criar dois mecanismos de:

- acquisition;
- selection;
- publication;
- runway;
- media preparation;
- session restore;
- feed ownership.

## INV-13 — Protocol-specific semantics stop at connector/admission boundary

RSS, Atom, JSON Feed, Mastodon, ATProto, Nostr ou qualquer protocolo futuro não podem vazar suas representações para:

- Selection;
- Publication;
- Session;
- UI.

## INV-14 — No hidden alternate pipelines

Não criar:

- legacy path;
- fallback runtime paralelo;
- shadow production path;
- compatibility feed;
- alternate selector;
- emergency secondary acquisition pipeline.

Um caminho.

## INV-15 — Simplicity is an invariant

Não criar abstração porque ela poderá ser útil futuramente.

Criar abstração somente quando existe responsabilidade real atual.

# Boundary consequences

INV-01 + INV-02:
FeedMineUI consumes presentation projections, not publication models.

INV-08:
PublishedCard remains publication history even when its PresentationCard
projection changes because of presentation environment.

INV-12:
Publication semantics have one owner: FeedMinePublication.

Persistence stores publication history but does not independently define
what publication means.


## Phase 3R5 — publication occurrence identity

Uma FeedEdition admite no máximo uma ocorrência publicada para cada OriginRecordID. Nova revisão, enriquecimento ou chegada tardia de mídia não constitui uma nova ocorrência na mesma Edition. O histórico permanece imutável. Outra Edition possui elegibilidade independente.

Selection reduces redundant publication attempts using durable origin exposure scoped to the Edition and bounded candidate set. PublicationStore enforces uniqueness transactionally for initial creation and both append paths; concurrent callers cannot duplicate an origin and a mixed invalid segment is never partially published. Late media does not create an Edition automatically.


### Phase 3R6B — independent durable availability

A rejected immutable revision does not discard an authoritative removal/revocation signal. ContentStore applies availability independently within admission's existing transaction, preserving revision/media/currentness and all memberships. One durable `availability_observed_at` supplies precedence: strictly newer signals replace state and timestamp; older signals and identical ties do not; conflicting ties retain the established state without enum priority. Explicit available must be strictly newer to reactivate removed/revoked content. Absence in RSS is not a removal and no canonical history is erased.

The additive migration uniformly backfills from last_observed_at and every legitimate new origin initializes the logical non-null timestamp. lastObservedAt retains its prior processed-observation meaning; it is neither made monotonic nor used for availability precedence. Rejected revisions update only availability and its supply projection, leaving lastObservedAt unchanged. Membership authority is deferred to 3R6C.


## Phase 3R6C — durable target/Source authority

The approved authority is acquisition_target_sources(target_id, source_id, generation), owned by Acquisition/Persistence. The additive acquisition-target-sources-v1 migration creates the relation and performs no backfill from canonical memberships, observations, checkpoints or publications. Cardinality remains many-to-many. Register and reconfigure now require an explicit nonempty authorizedSources set supplied by trusted external configuration; reconfigure replaces it atomically with the generation/checkpoint transition. Empty configured sets are not supported by these operations, so absence of grants denotes an unreconciled legacy target. Revoke/enable preserve the set and update its generation in the same transaction, without deleting canonical history.

SyndicationAcquisitionSnapshot owns explicit materialization of trusted caller-supplied registrations in its synchronous throwing initializer before constructing the immutable operational snapshot. Authority remains in Acquisition/Persistence. Target identity, connector kind and generation are checked; equivalent Source sets ignore input order and cause no authority write or generation bump. Same generation with a different set throws a configuration conflict and requires explicit reconfigure. Missing targets are not created. Legacy reconciliation requires matching enabled target/generation and validated nonempty bindings, preserving checkpoint/revision/generation. eligibleTargets, connector(for:) and makeCoordinator do not write authority. This supersedes the earlier bridge contract that snapshot construction performed no writes.

Admission validates each claimed Source within its existing writer transaction. Unauthorized Source is a typed structural error and cannot become transport failure or grant itself permission. Authorized memberships can be applied even when the known revision payload/media is rejected: immutable revision/media/current pointer and typed original-index rejection remain intact, and 3R6B availability precedence remains independent. Membership upserts retain their existing first/last observation semantics; authority removal does not delete canonical memberships or publication history.

Verification: full regression passes with 710 tests and zero failures, including nine focused membership-authority integration tests. Approved fixture realignment declares legitimate Sources before registration, updates explicit reconfiguration, preserves coherent overflow generations, and expects invalid snapshot configuration at materialization. Authorized rejected observations now update membership independently; revision/media/currentness and availability precedence remain protected. Publication schema expectations name the exact new table, primary-key autoindex and migration, retaining all publication and query-plan assertions. Independent read-only review found no actionable findings. This gate is delivered on its work branch for review; it is not integrated into main.


## Phase 3R7 / M2 — single causal effect owner

FeedRunwayDriver claims one private optional execution record before its first suspension and releases it with defer on success, structural failure or cancellation. The record holds current resource facts and one coalesced reconsideration bit; it owns neither observations nor intents. This bit is necessary because an input may arrive during the final presentation read, or activation may replace the scope while HTTP is pending. It is consumed only after validating the existing scope, and settlement has no suspension between the last pending-input check and ownership release. No generation, task registry, queue, lock, scheduler, timer or polling is introduced.

Reentrant callers can register Session/Runway observations and read current presentation immediately. One owner then reconsiders the latest controller facts at safe boundaries. Measurements superseded by a legitimate newer observation are reconsidered, and stale acquisition intent/acknowledgement fences remain authoritative. Deferred intents are resumed only at the initial explicit caller opportunity, not repeatedly by the drain. Viewport movement does not cancel acquisition or roll back receipts. The scope of each causal pass is the existing RunwayScope; old work cannot drive another context. A pending valid new Edition activation gets a fresh scope pass after settlement, without reactivating the old scope or duplicating its effects.

Controlled URLProtocol/AsyncStream tests establish HTTP entry, submit competing calls and observations before releasing HTTP, then inspect current and final presentation, canonical supply, publication uniqueness and reopen. The reproduction failed the old driver with two assertions: B started another target GET while A was suspended. The fixed driver returns B/C presentation without starting another executor, later measures the latest anchor, and retains committed supply. Separate tests cover cancellation cleanup, structural-error cleanup, deactivation, context change, valid new-Edition activation, and independent driver instances. Existing driver tests and all Publication/Acquisition contracts remain intact. Phase 3R7 is delivered on its work branch for external review; integration into main is not performed by this gate.


## Phase 3R8 / M11 — readable editorial Candidate text

ContentStore retains the exact admitted headline and summary. CandidateProvider owns one private pure conservative tokenizer and projects those fields into readable Candidate text, preserving optional nil, identities, timestamp meaning, language, provider, window order, examinedCount, cursor and exhaustion. CandidateProvider is the only production constructor of Candidate in this repository. Directly constructed Candidates remain explicit presentation values: PublicationPreparation copies them exactly and does not normalize again. PublicationCoordinator retains its byte-exact Candidate/draft fence; PublicationStore freezes the resulting text without modifying historical cards. No connector, admission, selection, UI or persistence/schema changes are involved.

The tokenizer visits scalar spans monotonically, with O(n) work and O(n) temporary storage; failed tag spans are consumed once so malformed attributes do not trigger repeated suffix scans. It recognizes ASCII tag names and quote-delimited tag endings, coalesces block separators to two line breaks and br to a single break, removes inline/link markup without interpreting attributes, and decodes the approved common named entities and valid decimal/hexadecimal Unicode references once. Unknown/invalid references remain literal. Decoded angle brackets are never scanned again. Plain inputs retain their whitespace and UTF-8 representation; boundary whitespace is normalized only around introduced block/line separators. No arbitrary character limit, truncation, cache, dependency, browser, fetch, CSS/JavaScript execution or rendering-time parsing is introduced. Existing acquisition byte bounds still bound fetched documents; locally stored text has no new character cap.

Conservative limits: format metadata does not reach Candidate, so syntactically complete tags are treated as editorial markup, including unknown tag names; literal comparisons such as 2 < 3 are preserved. This is not DOM or HTML layout. A malformed tag span remains literal. Comments and script/style/iframe/object/embed contents are suppressed until the matching syntactically recognized closing tag; an unclosed such element/comment suppresses the remaining tail. Explicit self-closing hidden elements discard only their tag. Tables receive no visual layout. Named entities beyond the approved common set remain literal. Atom summary is covered; Atom content is not currently projected. JSON summary remains plain text and contentText is a body field; JSON contentHtml is not consumed by the existing translator. Neither limitation is changed here.

Real RSS (stable GUID, CDATA HTML, entities, links and blocks), Atom HTML summary, and JSON plain summary are admitted with explicit target/Source authority, projected, selected, prepared and published through the unmodified coordinator. Integration verifies original canonical title/summary bytes, membership, identity, old raw published history, same-Edition origin exclusion and transactional rejection, a readable future card in a separate Edition, exact reopen and zero intercepted requests. Earlier cards remain unchanged; normalization never grants a second occurrence of an origin within an Edition. This gate is delivered on phase/3r8-readable-published-text for review, without integration into main.


## Real viewport evidence — Phase 3R9 / M14

Geometry is position, not automatically a user gesture. ScrollPhase qualifies the current navigation context. Direction requires an active interacting/decelerating context, a directional viewport displacement with unchanged viewport/content dimensions, and corroborating displacement of the same observed card with unchanged dimensions and unchanged position in content coordinates. The selected anchor must be a real PublicationCardID belonging to the currently presented Edition/window. The reading reference is the viewport center, clamped to the content end; the declared 16-point inter-card gap is divided equally. An offscreen or merely constructed lazy card is not reading evidence.

Changes of presentation window, context, Edition, viewport/content dimensions, card dimensions or card content coordinates fence the corresponding movement proof. A displacement identified as layout-only by these observable changes cannot generate forward/backward even during active interaction. Insufficient or indistinguishable evidence is not converted into movement. No universal distinction between physically different operations with identical observable facts is claimed. Velocity is optional: nil/zero is neither absence of scroll nor proof of layout and does not erase known direction. The native nonzero vector orientation is unverified in this gate; such a vector conservatively prevents choosing a direction and records that evidence limitation in transient visual state. It is not another navigation authority.

A legitimate forward event can be followed immediately by explicitTailApproach at the same anchor when a matching current-offset tail proof arrives later (V9-L). Partial intersection of the real final card or the geometrically reached content end is sufficient; no arbitrary remaining-card count is used. These are local-window facts, not claims of durable exhaustion. Equivalent consecutive anchor/activity events are deduplicated; different activity is retained in emission order. A stale tail offset cannot revive an earlier anchor, and an Edition/context change clears visual memory. No temporal waiting, historical callback queue or growing identity set is introduced.

One private visual @State in FeedScreen stores only current geometry, reference-card proof and finite evidence/deduplication scalars. FeedScreenStore remains the sole UI presentation value and forwards observations through submitViewport; FeedSession and Runway retain their existing semantic ownership. Real observation APIs are guarded by iOS 18/macOS 15 availability. macOS 14 renders without automatic capture or fabricated fallback. Executable composition and physical gesture validation are deferred to 3R10.
