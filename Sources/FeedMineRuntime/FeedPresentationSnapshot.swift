//
// File: FeedPresentationSnapshot.swift
// Module: FeedMineRuntime
//
// Responsibility:
//   Representar a projeção finita voltada à UI do estado local atual da sessão.
//
// Owns:
//   Finite immediately renderable local session presentation state containing future PresentationCard values.
//
// Does not own:
//   Publication semantics, direct PublishedCard exposure to FeedMineUI, network requirements or remote resource resolution.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence, FeedMineAcquisition, FeedMineEditorial, FeedMineMedia, FeedMinePublication. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-01, INV-02, INV-07, INV-08; Snapshot existence requires no network.
//
// Planned public surface:
//   FeedPresentationSnapshot containing/presenting future PresentationCard values. No API is declared.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// FeedPresentationSnapshot = finite UI-facing projection of current local session state.
// FeedPresentationSnapshot contains/presents future PresentationCard values.
// It does not expose PublishedCard directly to FeedMineUI.
// Snapshot não contém necessidade de network para existir.
