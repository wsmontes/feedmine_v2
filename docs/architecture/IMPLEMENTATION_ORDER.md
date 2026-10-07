# Implementation order

```text
Phase 0 — Architecture scaffold
Phase 1 — Domain models
Phase 2 — Local persistence
Phase 3 — Syndication acquisition
Phase 4 — Canonical admission
Phase 5 — Editorial selection
Phase 6 — Media preparation
Phase 7 — Immutable publication
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

Esta tarefa termina na Phase 0. Nenhuma API ou comportamento de domínio é implementado. A importação histórica mencionada na Phase 15 não cria runtime paralelo nem compatibilidade arquitetural.
