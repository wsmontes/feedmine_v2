//
// File: FeedEdition.swift
// Module: FeedMinePublication
//
// Responsibility:
//   Represent concrete published history under editorial rules.
//
// Owns:
//   PublicationSchemaVersion and immutable FeedEdition metadata.
//
// Does not own:
//   Mutable segments, lifecycle flags, selection execution or persistence mechanics.
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

/// Persisted semantic publication format, distinct from selection and database versions.
public struct PublicationSchemaVersion: Hashable, Sendable, Comparable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Concrete history identity; distinct Editions may share the same editorial rules.
/// History grows through external immutable Segments, never mutation of this metadata.
public struct FeedEdition: Hashable, Sendable {
    public let id: FeedEditionID
    public let editorialRevision: EditorialRevision
    public let publicationSchemaVersion: PublicationSchemaVersion
    public let selectionSeed: UInt64
    public let createdAt: Date

    public var contextKey: ContextKey {
        editorialRevision.contextKey
    }

    public init(
        id: FeedEditionID,
        editorialRevision: EditorialRevision,
        publicationSchemaVersion: PublicationSchemaVersion,
        selectionSeed: UInt64,
        createdAt: Date
    ) {
        self.id = id
        self.editorialRevision = editorialRevision
        self.publicationSchemaVersion = publicationSchemaVersion
        self.selectionSeed = selectionSeed
        self.createdAt = createdAt
    }
}
