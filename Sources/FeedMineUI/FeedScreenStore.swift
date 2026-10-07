//
// File: FeedScreenStore.swift
// Module: FeedMineUI
//
// Responsibility:
//   Bridge `@MainActor` futura entre `FeedSessionUI` e SwiftUI.
//
// Owns:
//   Future ownership: Future @MainActor bridge: screen presentation state and forwarding intents/viewport observations.
//
// Does not own:
//   Business logic, publication model translation, acquisition, publication or persistence.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMineRuntime. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-02, INV-03; Screen state bridges FeedSessionUI and SwiftUI.
//
// Planned public surface:
//   Future @MainActor bridge: screen presentation state and forwarding intents/viewport observations. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Bridge `@MainActor` futura entre `FeedSessionUI` e SwiftUI.
//
// Owns apenas:
//
// - presentation state necessário pela tela;
// - forwarding de intents;
// - forwarding de viewport observation.
//
// Não conter business logic.

// FeedScreenStore receives FeedPresentationSnapshot / PresentationCard through FeedSessionUI.
// It does not translate publication models itself.
// FeedScreenStore does not consume PublishedCard directly.
// Projection from published state to presentation state belongs to Runtime.
