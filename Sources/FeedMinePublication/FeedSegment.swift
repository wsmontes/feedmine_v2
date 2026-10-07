//
// File: FeedSegment.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Bloco imutável e ordenado de PublishedCards.
//
// Owns:
//   Future ownership: Immutable ordered block of PublishedCards.
//
// Does not own:
//   Silent reordering of existing history.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence, FeedMineEditorial, FeedMineMedia. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-08, INV-09; Append future history; never silently reorder old segments.
//
// Planned public surface:
//   Immutable ordered block of PublishedCards. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Bloco imutável e ordenado de PublishedCards.
//
// Depois de publicado:
//
// ```text
// append future history
// ```
//
// é permitido.
//
// ```text
// silently reorder old segment
// ```
//
// é proibido.
