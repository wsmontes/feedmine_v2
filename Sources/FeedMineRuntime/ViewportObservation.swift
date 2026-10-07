//
// File: ViewportObservation.swift
// Module: FeedMineRuntime
//
// Responsibility:
//   Descrever o que o usuário está vendo/consumindo.
//
// Owns:
//   Future ownership: Visible range, anchor, consumption direction and velocity estimates.
//
// Does not own:
//   loadMore commands or protocol pagination.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-03; Scroll is observation.
//
// Planned public surface:
//   Visible range, anchor, consumption direction and velocity estimates. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Descrever o que o usuário está vendo/consumindo.
//
// Exemplos futuros:
//
// - visible range;
// - anchor;
// - consumption direction;
// - velocity estimate.
//
// ViewportObservation não contém `loadMore`.
