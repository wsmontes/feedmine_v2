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
