//
// File: PublishedPrimaryAction.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Freeze self-contained semantic values for deterministic local published presentation.
//
// Owns:
//   Frozen baseline primary interaction targets for the owning card.
//
// Does not own:
//   Action execution, connector writes, network behavior or card identity.
//
// Allowed dependencies:
//   Foundation value types and FeedMineDomain; PublishedCard also uses FeedMineMedia.
//
// Architectural invariants:
//   INV-08, INV-12; published history survives canonical eviction without live joins.
//
// Public surface:
//   Phase 2C immutable semantic values; no Codable storage blobs or execution API.
//
// Status:
//   Phase 2C frozen PublishedCard baseline implemented.
//

import Foundation

/// A URL is a target, never publication identity; its future failure cannot destroy the card.
/// Explicit interaction may use network, while scroll/render may not.
public enum PublishedPrimaryAction: Hashable, Sendable {
    case externalURL(URL)
    case mediaPlayback(URL)
    case localContentDetail
}
