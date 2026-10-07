//
// File: FeedConnector.swift
// Module: FeedMineAcquisition
//
// Responsibility:
//   Boundary protocol entre FeedMine acquisition e implementações de sistemas externos.
//
// Owns:
//   Future ownership: Boundary between canonical acquisition work and external system implementations; future AcquisitionBatch output.
//
// Does not own:
//   Concrete protocol implementation, selection, publication or universal plugin frameworks.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-12, INV-13; External semantics stop at connector/admission.
//
// Planned public surface:
//   Boundary between canonical acquisition work and external system implementations; future AcquisitionBatch output. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Boundary protocol entre FeedMine acquisition e implementações de sistemas externos.
//
// O connector futuramente recebe acquisition work canônico e produz `AcquisitionBatch`.
//
// Não adicionar UniversalPlugin framework.
