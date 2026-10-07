//
// File: FeedSegment.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Represent one immutable ordered publication append unit.
//
// Owns:
//   Segment metadata and nonempty unique ordered PublicationCardIDs.
//
// Does not own:
//   Cross-segment validation, append execution, card payload or storage mechanics.
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

import Foundation
import FeedMineDomain

/// Supplied order is semantic and never sorted or deduplicated.
/// Future append authority validates ordinal continuity, cross-segment uniqueness
/// and equality of Segment and Edition publication schema versions.
public struct FeedSegment: Hashable, Sendable {
    public let id: FeedSegmentID
    public let editionID: FeedEditionID
    public let ordinal: UInt64
    public let segmentSeed: UInt64
    public let publicationSchemaVersion: PublicationSchemaVersion
    public let createdAt: Date
    public let cardIDs: [PublicationCardID]

    public init?(
        id: FeedSegmentID,
        editionID: FeedEditionID,
        ordinal: UInt64,
        segmentSeed: UInt64,
        publicationSchemaVersion: PublicationSchemaVersion,
        createdAt: Date,
        cardIDs: [PublicationCardID]
    ) {
        guard !cardIDs.isEmpty, Set(cardIDs).count == cardIDs.count else { return nil }
        self.id = id
        self.editionID = editionID
        self.ordinal = ordinal
        self.segmentSeed = segmentSeed
        self.publicationSchemaVersion = publicationSchemaVersion
        self.createdAt = createdAt
        self.cardIDs = cardIDs
    }
}
