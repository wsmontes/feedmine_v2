//
// File: Candidate.swift
// Module: FeedMineEditorial
//
// Responsibility:
//   Representar uma origin/revision elegível sendo considerada para publicação.
//
// Owns:
//   Future ownership: Eligible origin/revision considered for future publication.
//
// Does not own:
//   PublishedCard snapshots or protocol evidence.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-08, INV-13; A candidate is not a PublishedCard.
//
// Planned public surface:
//   Eligible origin/revision considered for future publication. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Representar uma origin/revision elegível sendo considerada para publicação.
//
// Candidate não é PublishedCard.
