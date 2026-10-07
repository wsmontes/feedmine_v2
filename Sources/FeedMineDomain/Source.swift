//
// File: Source.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Definir os conceitos canônicos futuros:
//
// Owns:
//   Future ownership: Source editorial unit, Provider attribution and SourceBinding external acquisition mapping.
//
// Does not own:
//   Endpoint identity, acquisition targets or transport execution.
//
// Allowed dependencies:
//   Swift standard library only; no FeedMine module imports. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-13; Source != endpoint; Source != provider; Source != acquisition target.
//
// Planned public surface:
//   Source editorial unit, Provider attribution and SourceBinding external acquisition mapping. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Definir os conceitos canônicos futuros:
//
// ```text
// Source
// Provider
// SourceBinding
// ```
//
// Source:
//
// unidade editorial que o usuário pode seguir/selecionar.
//
// Provider:
//
// entidade/autoria/origem apresentada ou atribuída ao conteúdo.
//
// SourceBinding:
//
// mapeamento entre uma Source FeedMine e informação externa necessária para acquisition.
//
// Invariant:
//
// ```text
// Source != endpoint
// Source != provider
// Source != acquisition target
// ```
