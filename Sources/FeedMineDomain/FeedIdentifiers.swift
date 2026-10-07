//
// File: FeedIdentifiers.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Define nominal FeedMine-owned identities independent of transport.
//
// Owns:
//   SourceID, ProviderID, OriginRecordID, OriginRevisionID, SourceBindingID, ContentEntityID, ContentClusterID, EditorialRevisionID, FeedEditionID, FeedSegmentID, PublicationCardID.
//
// Does not own:
//   External identities, endpoint-derived identity or a generic identity framework.
//
// Allowed dependencies:
//   Swift standard library and Foundation value types (UUID, Date, URL).
//   No other FeedMine module dependencies.
//
// Architectural invariants:
//   INV-13; FeedMine internal identity is not external identity or network location.
//
// Planned public surface:
//   Eleven nominal IDs implemented across Phase 1A, Phase 1B and Phase 2B; ContextKey belongs to FeedContext.swift.
//
// Status:
//   Phase 1A/1B canonical and Phase 2B publication nominal identifier implementation.
//   Publication IDs cross FeedMinePublication, FeedMineRuntime, future persistence commands,
//   exposure and presentation identity boundaries. Domain owns only nominal identity;
//   FeedMinePublication retains Edition/Segment/Card semantics.
//

import Foundation

// Future IDs remain documentation only: SessionID, AssetID, ActionID and AcquisitionTargetID.
// Their concepts are not moved.

public struct SourceID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}

public struct ProviderID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}

public struct OriginRecordID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}

public struct OriginRevisionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}

public struct SourceBindingID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}

public struct ContentEntityID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}

public struct ContentClusterID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}


/// Phase 1B nominal identity; never derived deterministically from request or transport.
public struct EditorialRevisionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}


/// Concrete published history identity.
public struct FeedEditionID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}


/// Immutable publication append-unit identity.
public struct FeedSegmentID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}


/// Stable published occurrence identity, independent of canonical content identity.
public struct PublicationCardID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }

    public var description: String {
        rawValue.uuidString
    }
}
