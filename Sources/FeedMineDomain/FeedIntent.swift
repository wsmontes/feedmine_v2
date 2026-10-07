//
// File: FeedIntent.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Representar intenções semânticas emitidas pelo usuário/UI.
//
// Owns:
//   Future ownership: changeContext, refresh, open, bookmark, markRead, primaryAction intentions.
//
// Does not own:
//   Intent execution, networking or persistence.
//
// Allowed dependencies:
//   Swift standard library only; no FeedMine module imports. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-02; Semantic intent is separate from execution.
//
// Planned public surface:
//   changeContext, refresh, open, bookmark, markRead, primaryAction intentions. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Representar intenções semânticas emitidas pelo usuário/UI.
//
// Exemplos:
//
// ```text
// changeContext
// refresh
// open
// bookmark
// markRead
// primaryAction
// ```
//
// Does not own:
//
// - execução da intenção;
// - networking;
// - persistence.
