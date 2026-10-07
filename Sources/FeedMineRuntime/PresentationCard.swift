//
// File: PresentationCard.swift
// Module: FeedMineRuntime
//
// Responsibility:
//   Representar a projeção local, finita e presentation-ready de um card que pode ser consumida por FeedMineUI.
//
// Owns:
//   Future presentation-facing representation of a published card.
//
// Does not own:
//   Publication identity, publication history, editorial selection, acquisition, networking, remote media resolution or SwiftUI rendering.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-01, INV-02, INV-08.
//
// Planned public surface:
//   PresentationCard. Documentation only; no API is declared.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// PublishedCard
//     ↓ Runtime projection
// PresentationCard
//     ↓
// FeedMineUI
//
// PublishedCard is publication state.
// PresentationCard is presentation state.
// UI knows PresentationCard; UI does not know PublishedCard.
// PresentationCard is not a second source of truth.
// It is a projection derived from published history for UI consumption.
