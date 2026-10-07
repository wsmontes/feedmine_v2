//
// File: EditorialPolicy.swift
// Module: FeedMineEditorial
//
// Responsibility:
//   Local explícito para políticas editoriais puras:
//
// Owns:
//   Future ownership: Eligibility, scoring, sequencing and exposure rules.
//
// Does not own:
//   Fetching, publication or renderer behavior.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-12, INV-13; Editorial rules have one owner.
//
// Planned public surface:
//   Eligibility, scoring, sequencing and exposure rules. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Local explícito para políticas editoriais puras:
//
// - eligibility;
// - scoring;
// - sequencing;
// - exposure/diversity.
//
// Evitar espalhar regras editoriais por Runtime/UI.
