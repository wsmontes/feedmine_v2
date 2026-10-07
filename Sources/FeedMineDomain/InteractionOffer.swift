//
// File: InteractionOffer.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Representar ações semanticamente disponíveis para um item.
//
// Owns:
//   Future ownership: open, reply, repost, like, share, play semantic offers.
//
// Does not own:
//   Action execution or SDK-specific action objects.
//
// Allowed dependencies:
//   Swift standard library only; no FeedMine module imports. No imports are necessary in this scaffold.
//
// Architectural invariants:
//   INV-13; Offered actions remain protocol-neutral.
//
// Planned public surface:
//   open, reply, repost, like, share, play semantic offers. Documentation only; no API is declared in this phase.
//
// Status:
//   Architecture scaffold only. Production behavior is intentionally absent.
//

// Specification notes:
// Responsibility:
//
// Representar ações semanticamente disponíveis para um item.
//
// Exemplos futuros:
//
// ```text
// open
// reply
// repost
// like
// share
// play
// ```
//
// Does not execute ações.
//
// Does not contain SDK-specific action objects.
