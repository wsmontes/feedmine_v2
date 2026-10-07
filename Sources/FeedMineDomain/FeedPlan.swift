//
// File: FeedPlan.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Representar uma política editorial resolvida para um contexto.
//
// Owns:
//   Future ownership: Resolved eligibility, scoring, sequencing, exposure and acquisition policy descriptions.
//
// Does not own:
//   Policy execution, fetching or UI queries.
//
// Allowed dependencies:
//   Swift standard library only; no FeedMine module imports. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-12; Policy values do not execute services.
//
// Planned public surface:
//   Resolved eligibility, scoring, sequencing, exposure and acquisition policy descriptions. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Representar uma política editorial resolvida para um contexto.
//
// FeedPlan descreve:
//
// - elegibilidade;
// - scoring;
// - sequencing;
// - exposure;
// - acquisition policy.
//
// Does not execute essas políticas.
//
// Does not fetch.
//
// Does not query UI.
