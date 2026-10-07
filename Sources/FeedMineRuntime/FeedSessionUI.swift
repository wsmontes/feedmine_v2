//
// File: FeedSessionUI.swift
// Module: FeedMineRuntime
//
// Responsibility:
//   Boundary mínima consumível pela camada UI.
//
// Owns:
//   Future ownership: Minimal UI boundary for FeedPresentationSnapshot / PresentationCard, FeedIntent input and ViewportObservation input.
//
// Does not own:
//   Exposed acquisition, publication or storage internals.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-02, INV-03; UI observes local state and sends semantic input.
//
// Planned public surface:
//   Minimal UI boundary for FeedPresentationSnapshot / PresentationCard, FeedIntent input and ViewportObservation input. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Boundary mínima consumível pela camada UI.
//
// Deve futuramente expor somente:
//
// - presentation snapshot stream/state;
// - intents;
// - viewport observations.
//
// Não expor internals de acquisition/publication/storage.

// Future UI surface exposes only:
// - FeedPresentationSnapshot / PresentationCard presentation stream/state;
// - FeedIntent input;
// - ViewportObservation input.
// It does not expose PublishedCard, FeedSegment, FeedEdition,
// PublicationCoordinator, AcquisitionCoordinator or persistence stores.
// No API is implemented in Phase 0.
