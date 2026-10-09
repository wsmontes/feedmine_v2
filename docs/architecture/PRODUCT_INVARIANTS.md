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
