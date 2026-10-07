//
// File: SessionCursor.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Represent a persistible logical position within published history.
//
// Owns:
//   AnchorPlacement, FeedWindowAnchor and immutable SessionCursor.
//
// Does not own:
//   Pixels, global session identity, restore execution or persistence mechanics.
//
// Allowed dependencies:
//   FeedMineDomain and Foundation value types.
//
// Architectural invariants:
//   INV-07, INV-08, INV-12; immutable published history and logical restore identity.
//
// Public surface:
//   Phase 2B semantic values only; no Codable storage representation or execution API.
//
// Status:
//   Phase 2B publication identity and exact restore semantics implemented.
//

import FeedMineDomain

public enum AnchorPlacement: String, Hashable, Sendable {
    case top
    case center
}

/// Relative placement of the same published occurrence across render environments.
public struct FeedWindowAnchor: Hashable, Sendable {
    public let cardID: PublicationCardID
    public let placement: AnchorPlacement

    public init(cardID: PublicationCardID, placement: AnchorPlacement) {
        self.cardID = cardID
        self.placement = placement
    }
}

/// Exact restore requires the retained Edition and occurrence, never reselection.
/// Dynamic Type, width and media availability may change layout, not cursor identity.
public struct SessionCursor: Hashable, Sendable {
    public let editionID: FeedEditionID
    public let anchor: FeedWindowAnchor

    public init(editionID: FeedEditionID, anchor: FeedWindowAnchor) {
        self.editionID = editionID
        self.anchor = anchor
    }
}
