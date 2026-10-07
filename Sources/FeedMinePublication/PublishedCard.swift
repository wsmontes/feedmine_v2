//
// File: PublishedCard.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Snapshot semântico congelado de um card publicado.
//
// Owns:
//   Future ownership: Frozen semantic snapshot of a published card.
//
// Does not own:
//   Live OriginRecord projections or retrospective upstream changes.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence, FeedMineEditorial, FeedMineMedia. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-08, INV-09; Published snapshots remain immutable.
//
// Planned public surface:
//   Frozen semantic snapshot of a published card. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Snapshot semântico congelado de um card publicado.
//
// PublishedCard não é live projection de OriginRecord.
//
// Mudanças upstream não modificam retrospectivamente o PublishedCard.
