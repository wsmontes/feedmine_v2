//
// File: AdmissionPolicy.swift
// Module: FeedMineAcquisition
//
// Responsibility:
//   Definir o gate entre evidence trazida por connector e canonical local supply.
//
// Owns:
//   Future ownership: Validation, appropriate deduplication, write admission and canonicalization gate.
//
// Does not own:
//   Editorial selection or protocol transport.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-13; Accepted supply is canonical.
//
// Planned public surface:
//   Validation, appropriate deduplication, write admission and canonicalization gate. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Definir o gate entre evidence trazida por connector e canonical local supply.
//
// Responsável futuramente por:
//
// - validação;
// - dedup apropriado;
// - write admission;
// - canonicalization boundary.
//
// Does not perform editorial selection.
