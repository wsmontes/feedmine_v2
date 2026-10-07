//
// File: FeedIdentifiers.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Definir o local conceitual futuro de identificadores estáveis pertencentes ao domínio FeedMine.
//
// Owns:
//   Future ownership: SourceID, ProviderID, OriginRecordID, OriginRevisionID, FeedEditionID, FeedSegmentID, SessionID, AssetID, ActionID.
//
// Does not own:
//   Endpoint identity, protocol-specific identity or transport-derived ID generation.
//
// Allowed dependencies:
//   Swift standard library only; no FeedMine module imports. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-13; FeedMine identity is not network location.
//
// Planned public surface:
//   SourceID, ProviderID, OriginRecordID, OriginRevisionID, FeedEditionID, FeedSegmentID, SessionID, AssetID, ActionID. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Definir o local conceitual futuro de identificadores estáveis pertencentes ao domínio FeedMine.
//
// Owns futuramente:
//
// ```text
// SourceID
// ProviderID
// OriginRecordID
// OriginRevisionID
// FeedEditionID
// FeedSegmentID
// SessionID
// AssetID
// ActionID
// ```
//
// Does not own:
//
// - URL de endpoint como identidade;
// - identidade específica de RSS/Mastodon/etc.;
// - geração de IDs a partir de detalhes de transporte.
//
// Invariant:
//
// > FeedMine identity is not network location.
