//
// File: FeedContext.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Representar o contexto editorial solicitado pelo usuário.
//
// Owns:
//   Future ownership: Main feed, collection, source, search, smart feed and saved context semantics.
//
// Does not own:
//   Acquisition, network, database, UI navigation or connector metadata.
//
// Allowed dependencies:
//   Swift standard library only; no FeedMine module imports. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-10; Context describes what the user wants, not how to acquire it.
//
// Planned public surface:
//   Main feed, collection, source, search, smart feed and saved context semantics. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Representar o contexto editorial solicitado pelo usuário.
//
// Exemplos futuros:
//
// - main feed;
// - collection;
// - source;
// - search;
// - smart feed;
// - saved context.
//
// Does not own:
//
// - acquisition;
// - network;
// - database;
// - UI navigation;
// - connector metadata.
//
// Invariant:
//
// > contexto descreve o que o usuário quer, não como obtê-lo.
