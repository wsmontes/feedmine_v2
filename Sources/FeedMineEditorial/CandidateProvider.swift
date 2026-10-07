//
// File: CandidateProvider.swift
// Module: FeedMineEditorial
//
// Responsibility:
//   Consultar local supply para obter candidatos coerentes com `FeedPlan`.
//
// Owns:
//   Future ownership: Local canonical candidate retrieval.
//
// Does not own:
//   Remote acquisition, protocol parsing or final selection.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-11, INV-13; Candidates come from canonical local supply.
//
// Planned public surface:
//   Local canonical candidate retrieval. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Consultar local supply para obter candidatos coerentes com `FeedPlan`.
//
// Pode depender de persistence.
//
// Não faz acquisition.
