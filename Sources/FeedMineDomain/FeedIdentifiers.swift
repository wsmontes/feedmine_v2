//
// File: FeedIdentifiers.swift
// Module: FeedMineDomain
//
// Responsibility:
//   Define nominal FeedMine-owned identities independent of transport.
//
// Owns:
//   SourceID, ProviderID, OriginRecordID, OriginRevisionID, SourceBindingID, ContentEntityID, ContentClusterID.
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
//   Only the seven canonical IDs are implemented in Phase 1A.
//
// Status:
//   Phase 1A canonical domain implementation.
//

import Foundation

// Future IDs remain documentation only: FeedEditionID, FeedSegmentID, SessionID,
// AssetID, ActionID, PublicationCardID and AcquisitionTargetID. Their concepts are not moved.

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
