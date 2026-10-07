//
// File: InteractionCoordinator.swift
// Module: FeedMineRuntime
//
// Responsibility:
//   Executar semanticamente ações oferecidas por `InteractionOffer`.
//
// Owns:
//   Future ownership: Semantic execution of InteractionOffer actions through appropriate boundaries.
//
// Does not own:
//   Feed production or exposed protocol-specific commands.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-12, INV-13; Interaction stays separate from feed production.
//
// Planned public surface:
//   Semantic execution of InteractionOffer actions through appropriate boundaries. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Executar semanticamente ações oferecidas por `InteractionOffer`.
//
// A execução protocol-specific futura deve continuar atrás de boundaries apropriadas.
//
// Não misturar interaction com feed production.
