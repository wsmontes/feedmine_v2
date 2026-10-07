//
// File: FeedSessionState.swift
// Module: FeedMineRuntime
//
// Responsibility:
//   Value state completo necessário para reduzir eventos de sessão.
//
// Owns:
//   Future ownership: Explicit complete value state needed to reduce session events.
//
// Does not own:
//   Scattered independent flags, I/O or UI rendering.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-07, INV-12; Session state stays explicit.
//
// Planned public surface:
//   Explicit complete value state needed to reduce session events. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Value state completo necessário para reduzir eventos de sessão.
//
// Manter estado explícito.
//
// Evitar flags independentes espalhadas.
