//
// File: AcquisitionModels.swift
// Module: FeedMineAcquisition
//
// Responsibility:
//   Concentrar os value types pequenos usados por acquisition.
//
// Owns:
//   Future ownership: AcquisitionTarget, AcquisitionBatch, AcquisitionDemand, AcquisitionPurpose, AcquisitionFrontier.
//
// Does not own:
//   Source identity, protocol SDK models or published cards.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-13; AcquisitionTarget represents external work and is not Source.
//
// Planned public surface:
//   AcquisitionTarget, AcquisitionBatch, AcquisitionDemand, AcquisitionPurpose, AcquisitionFrontier. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Concentrar os value types pequenos usados por acquisition.
//
// Planned concepts:
//
// ```text
// AcquisitionTarget
// AcquisitionBatch
// AcquisitionDemand
// AcquisitionPurpose
// AcquisitionFrontier
// ```
//
// Target representa trabalho externo.
//
// Target NÃO é Source.
