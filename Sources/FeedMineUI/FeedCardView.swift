//
// File: FeedCardView.swift
// Module: FeedMineUI
//
// Responsibility:
//   Renderizar um PresentationCard já local e presentation-ready.
//
// Owns:
//   Future rendering of PresentationCard received through the Runtime presentation boundary.
//
// Does not own:
//   Publication model translation, remote image resolution, downloads, URL resolution, networking, database, acquisition or connector access.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMineRuntime. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-01, INV-02; import FeedMinePublication is prohibited.
//
// Planned public surface:
//   FeedCardView rendering PresentationCard. Documentation only; no API is declared.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// FeedCardView never consumes PublishedCard directly.
// Remote image resolution, network, database, acquisition and connector access are prohibited.
// Presentation resources are already local and ready before rendering.
