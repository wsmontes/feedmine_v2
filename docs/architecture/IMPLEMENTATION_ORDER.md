# Implementation order

```text
Phase 0 — Architecture scaffold
Phase 1 — Domain models
Phase 2 — Local persistence

Phase 2 does not implement durable FeedEdition/FeedSegment/PublishedCard
storage unless the Publication/Persistence boundary has first been closed.

Content persistence and basic local infrastructure may proceed independently.

Phase 3 — Syndication acquisition
Phase 4 — Canonical admission
Phase 5 — Editorial selection
Phase 6 — Media preparation
Phase 7 — Immutable publication

Publication/Persistence representation boundary must be explicitly resolved
before durable publication history is implemented.

Phase 8 — Feed session
Phase 9 — Adaptive runway
Phase 10 — SwiftUI presentation
Phase 11 — First-launch bootstrap UX
Phase 12 — Background preparation
Phase 13 — Context switching/reuse
Phase 14 — Other product surfaces
Phase 15 — Migration/import from FeedMine legacy where required
Phase 16 — Hardening and release
```

> uma phase não deve adicionar um segundo mecanismo para uma responsabilidade que uma phase anterior já possui.


Phase 0 — complete

Phase 1A — complete

Phase 1B — complete

Persistence Discovery — complete

Phase 2A — runtime persistence lifecycle — complete

Phase 2B — publication identity and exact restore semantics — complete

Phase 2C — frozen PublishedCard baseline — complete

Phase 2D — publication/session relational schema design — complete

Phase 2E — exact offline restore storage — complete

Phase 2F — semantic publication history + FeedWindow — complete

Phase 2G — complete

Phase 2H — complete

Phase 2I — complete

Phase 3A — canonical local supply design gate — complete

Phase 3B1 — canonical supply schema — complete

Phase 3B2 — atomic canonical ContentStore — complete

Phase 3B3 — bounded candidate query — deferred

Viewport movement remains memory-local. An explicit current-position checkpoint operation supplies durability; app lifecycle timing and automatic checkpoint policy remain deferred.

Phases 2G–2I close the local publication/session vertical slice. Phase 3A precedes network acquisition because acquisition needs a canonical authority to admit into; its design gate is [CANONICAL_SUPPLY_DESIGN.md](CANONICAL_SUPPLY_DESIGN.md). Phase 3B1 completed the schema; Phase 3B2 implemented atomic ContentStore changes and exact reads. Phase 3B3 bounded candidate queries remain deferred. The macro phase numbering above remains unchanged.
