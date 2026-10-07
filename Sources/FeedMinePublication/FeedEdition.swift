//
// File: FeedEdition.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Representar uma sequência/versionamento coerente de publicação para determinado contexto/revision.
//
// Owns:
//   Future ownership: Coherent publication sequence/version for context/revision and successors.
//
// Does not own:
//   Silent rewriting of a published edition.
//
// Allowed dependencies:
//   FeedMineDomain, FeedMinePersistence, FeedMineEditorial, FeedMineMedia. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-08; New editorial reality may create a successor.
//
// Planned public surface:
//   Coherent publication sequence/version for context/revision and successors. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Representar uma sequência/versionamento coerente de publicação para determinado contexto/revision.
//
// Nova realidade editorial gera sucessora quando necessário.
//
// Não reescrever silenciosamente uma Edition já publicada.
