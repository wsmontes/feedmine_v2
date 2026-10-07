//
// File: Content.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Local conceitual dos modelos canônicos de conteúdo aceitos após admission.
//
// Owns:
//   Future ownership: OriginRecord, OriginRevision, ExternalIdentity, SourceMembership, ContentRelation.
//
// Does not own:
//   FeedKit models, XML, Mastodon models, ATProto records, Nostr events or downstream raw protocol JSON.
//
// Allowed dependencies:
//   Swift standard library only; no FeedMine module imports. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-13; Evidence is heterogeneous before admission and canonical after admission.
//
// Planned public surface:
//   OriginRecord, OriginRevision, ExternalIdentity, SourceMembership, ContentRelation. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Local conceitual dos modelos canônicos de conteúdo aceitos após admission.
//
// Owns futuramente:
//
// ```text
// OriginRecord
// OriginRevision
// ExternalIdentity
// SourceMembership
// ContentRelation
// ```
//
// Invariant:
//
// > representações externas são heterogêneas antes da admission e canônicas depois dela.
//
// Does not contain:
//
// - FeedKit model;
// - XML;
// - Mastodon model;
// - ATProto record;
// - Nostr event;
// - raw protocol JSON used downstream.
